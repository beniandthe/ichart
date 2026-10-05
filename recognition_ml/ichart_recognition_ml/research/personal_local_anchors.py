"""Research-only kernel residual learner with public untaught-shape priors."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch

from .personal_adaptability import STARTING_SHA256, summarize
from .personal_anchors import AnchorBank, VERSION as ANCHOR_VERSION
from .personal_encoder_export import load_research_model
from .personal_local import LocalResidualHead, VERSION as LOCAL_VERSION, evaluate_local, rbf
from .personal_residual import validate_features
from .personal_visual_encoder import encode_samples, infer
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers

VERSION = "personal-local-untaught-anchor-v1"
LOCAL_REPORT_SHA256 = "739b2b7c7d408bddb0a6b8f21dc09a9e23fc6266a18b65d8dc6f67230804f660"
WIDTH_SHA256 = "33ed8df132011bbec26ceb419d7c0dc71aaaf6a257d0330461a260dd1348471e"


def fit_local_anchored(features, base_scores, labels, vocabulary, width, bank):
    original = LocalResidualHead.fit(features, base_scores, labels, vocabulary, width)
    features = original.features
    validate_features(bank.features)
    if (len(bank.vocabulary) != len(bank.features) or not 2 <= len(bank.vocabulary) <= 512
            or len(set(bank.vocabulary)) != len(bank.vocabulary) or not set(bank.vocabulary).issubset(vocabulary)
            or bank.features.shape[1] != features.shape[1]):
        raise ValueError("Wrong public prior vocabulary or features")
    untaught = [i for i, label in enumerate(bank.vocabulary) if label not in labels]
    if not labels or not untaught:
        return original
    points = np.concatenate((features, bank.features[untaught]))
    balance = np.concatenate((np.array([1 / np.sqrt(labels.count(label)) for label in labels]), np.ones(len(untaught))))
    residuals = np.array([[float(label == c) for c in vocabulary] for label in labels]) - np.asarray(base_scores)
    target = np.concatenate((residuals, np.zeros((len(untaught), len(vocabulary)))))
    weighted = rbf(points, points, width) * balance[:, None] * balance[None, :]
    beta = np.linalg.solve(weighted + .1 * np.eye(len(points)), target * balance[:, None])
    coefficients = beta * balance[:, None]
    if not np.isfinite(coefficients).all():
        raise ValueError("Nonfinite local prior fit")
    points.setflags(write=False); coefficients.setflags(write=False)
    return LocalResidualHead(tuple(vocabulary), points, coefficients, float(width))


def run(checkpoint, source, reference_path, anchor_path, bank_path, local_path, width_path, protocol, output):
    if output.exists():
        raise ValueError("Output must be new")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    model, training = load_research_model(checkpoint)
    blobs = {name: path.read_bytes() for name, path in (("reference", reference_path), ("anchors", anchor_path),
             ("bank", bank_path), ("local", local_path), ("width", width_path), ("protocol", protocol))}
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in blobs.items()}
    reference, anchor, bank_data, local, width_data = (json.loads(blobs[k]) for k in ("reference", "anchors", "bank", "local", "width"))
    if (hashes["local"] != LOCAL_REPORT_SHA256 or hashes["width"] != WIDTH_SHA256
            or training["weightsSHA256"] != STARTING_SHA256 or local["version"] != LOCAL_VERSION
            or local["referenceSHA256"] != hashes["reference"] or local["anchorReferenceSHA256"] != hashes["anchors"]
            or local["widthSHA256"] != hashes["width"] or anchor["version"] != ANCHOR_VERSION
            or anchor["anchorSHA256"] != hashes["bank"] or bank_data["sourceSHA256"] != SOURCE_SHA256
            or bank_data["encoderSHA256"] != STARTING_SHA256):
        raise ValueError("Frozen model, width, prior or comparison binding changed")
    records = load_official_source(source)
    train_writers, dev_writers, reserved = split_writers(records)
    for key, expected in (("trainingWriters", train_writers), ("developmentWriters", dev_writers), ("reservedWriters", reserved)):
        if any(report[key] != list(expected) for report in (training, reference, anchor, local)):
            raise ValueError("Writer split changed")
    vocabulary = tuple(training["labels"])
    bank = AnchorBank(tuple(bank_data["vocabulary"]), np.asarray(bank_data["features"], dtype=np.float64))
    if bank.vocabulary != vocabulary or not np.isclose(width_data["width"], local["width"], rtol=0, atol=0):
        raise ValueError("Wrong encoder vocabulary or width")
    metadata = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "weightsSHA256": STARTING_SHA256,
                "boundSHA256": hashes, "width": width_data["width"], "regularization": .1,
                "trainingWriters": train_writers, "developmentWriters": dev_writers, "reservedWriters": reserved,
                "reservedWritersEvaluated": False, "productionEligible": False, "inferenceAuthority": "research-rank-only",
                "codeSHA256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(Path(__file__).parent.glob("*.py"))}}
    output.mkdir(parents=True, exist_ok=False)
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
    (output / "frozen-protocol.md").write_bytes(blobs["protocol"])
    samples = tuple(s for s in records if s.writer in dev_writers)
    images, _ = encode_samples(samples, dev_writers)
    features, logits = infer(model, images)
    results = {}
    for name, task in reference["results"]["starting"].items():
        result = evaluate_local(samples, features, logits, vocabulary, width_data["width"], task, anchor["results"][name],
            fit=lambda x, base, labels, vocabulary, width: fit_local_anchored(x, base, labels, vocabulary, width, bank))
        before = {row["queryID"]: row for row in local["results"][name]["rows"]}
        if (result["eligibleQueries"] != 772 or len(before) != len(result["rows"]) or len(before) != 776
                or any(row["queryID"] not in before or any(row[k] != before[row["queryID"]][k]
                    for k in ("eligible", "exclusions", "intended", "generic")) for row in result["rows"])):
            raise ValueError("Local comparison identities or denominator changed")
        eligible = [row for row in result["rows"] if row["eligible"]]
        result["comparisons"]["localPersonal"] = {
            "correct": sum(before[row["queryID"]]["personalCorrect"] for row in eligible),
            "gains": sum(row["personalCorrect"] and not before[row["queryID"]]["personalCorrect"] for row in eligible),
            "harms": sum(not row["personalCorrect"] and before[row["queryID"]]["personalCorrect"] for row in eligible)}
        for row in result["rows"]:
            row["localPersonal"] = before[row["queryID"]]["personal"]
        results[name] = result
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source changed")
    may_advance = (results["sparse16"]["personalCorrect"] >= 614 and results["full97"]["personalCorrect"] >= 639
                   and results["sparse16"]["harms"] <= 5)
    report = {**metadata, "sourceUnchanged": True, "results": results, "mayAdvanceToAppComparison": may_advance}
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True))
    for name, result in results.items():
        print(json.dumps({"profile": name, **summarize(result["rows"]), "comparisons": result["comparisons"],
                          "taught": result["taught"], "untaught": result["untaught"]}), flush=True)
    print(json.dumps({"mayAdvanceToAppComparison": may_advance}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("checkpoint", "source", "reference", "anchors", "bank", "local", "width", "protocol", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    a = parser.parse_args()
    run(a.checkpoint.resolve(), a.source.resolve(), a.reference.resolve(), a.anchors.resolve(), a.bank.resolve(),
        a.local.resolve(), a.width.resolve(), a.protocol.resolve(), a.output.resolve())

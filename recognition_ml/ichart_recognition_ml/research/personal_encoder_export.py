"""Research-only embedding export/parity and frozen wider-personalization probe.

Does not emit an app-compatible production manifest or modify any live profile.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch

from .personal_visual_encoder import (ROOTS, VERSION, PersonalVisualEncoder, encode_samples,
                                      fit_personal, infer, rank_personal)
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers, trajectory_fingerprint


def directory_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for file in sorted(path for path in root.rglob("*") if path.is_file()):
        if file.is_symlink():
            raise ValueError("Model package cannot contain symlinks")
        digest.update(file.relative_to(root).as_posix().encode() + b"\0")
        digest.update(hashlib.sha256(file.read_bytes()).hexdigest().encode() + b"\n")
    return digest.hexdigest()


def load_research_model(run: Path):
    report = json.loads((run / "report.json").read_text())
    if (report.get("version") != VERSION or report.get("productionEligible") is not False
            or report.get("reservedWritersEvaluated") is not False or report.get("sourceSHA256") != SOURCE_SHA256
            or len(report.get("trainingHistory", [])) != 30 or report.get("epochs") != 30):
        raise ValueError("Expected the complete fixed research checkpoint")
    weights = run / "research-weights.pt"
    if hashlib.sha256(weights.read_bytes()).hexdigest() != report["weightsSHA256"]:
        raise ValueError("Weights differ from the evaluated checkpoint")
    model = PersonalVisualEncoder(len(report["labels"]))
    model.load_state_dict(torch.load(weights, map_location="cpu", weights_only=True), strict=True)
    model.eval()
    return model, report


def wider_personalization(samples, features, logits, labels, training_pixels, pixels):
    rows = []
    for writer in sorted({s.writer for s in samples}):
        support = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 1]
        queries = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 2]
        if len(support) != 97 or len(queries) != 97:
            raise ValueError("Incomplete 97-character session")
        fitted = fit_personal(features[support], tuple(samples[i].label for i in support))
        support_pixels = {pixels[i] for i in support}
        support_ink = {trajectory_fingerprint(samples[i]) for i in support}
        for i in queries:
            ranking = rank_personal(fitted, features[i])
            personal, generic = ranking[0]["label"], labels[int(logits[i].argmax())]
            exclusions = []
            if pixels[i] in training_pixels:
                exclusions.append("encoder_training_raster_copy")
            if pixels[i] in support_pixels:
                exclusions.append("support_raster_copy")
            if trajectory_fingerprint(samples[i]) in support_ink:
                exclusions.append("normalized_support_copy")
            rows.append({"writer": writer, "queryID": samples[i].identity, "intended": samples[i].label,
                         "personal": personal, "generic": generic, "eligible": not exclusions,
                         "exclusions": exclusions, "personalCorrect": personal == samples[i].label,
                         "genericCorrect": generic == samples[i].label, "rankOnlyNotAccepted": True})
    eligible = [r for r in rows if r["eligible"]]
    return {"scope": "97-way public character personalization development, not chords",
            "queries": len(rows), "eligibleQueries": len(eligible),
            "personalCorrect": sum(r["personalCorrect"] for r in eligible),
            "genericCorrect": sum(r["genericCorrect"] for r in eligible),
            "gains": sum(r["personalCorrect"] and not r["genericCorrect"] for r in eligible),
            "harms": sum(not r["personalCorrect"] and r["genericCorrect"] for r in eligible),
            "writers": [{"writer": w, "eligible": sum(r["writer"] == w for r in eligible),
                         "personalCorrect": sum(r["writer"] == w and r["personalCorrect"] for r in eligible),
                         "genericCorrect": sum(r["writer"] == w and r["genericCorrect"] for r in eligible)}
                        for w in sorted({s.writer for s in samples})], "rows": rows}


def export(run: Path, source: Path, output: Path, *, include_generic=False, all_characters=False):
    import coremltools as ct
    if output.exists():
        raise ValueError("Output directory must be new")
    if all_characters and not include_generic:
        raise ValueError("Wider residual parity requires generic logits")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    model, report = load_research_model(run)
    records = load_official_source(source)
    training_writers, development_writers, reserved = split_writers(records)
    if (list(training_writers) != report["trainingWriters"] or list(development_writers) != report["developmentWriters"]
            or list(reserved) != report["reservedWriters"]):
        raise ValueError("Research split changed")
    samples = tuple(r for r in records if r.writer in development_writers)
    training = tuple(r for r in records if r.writer in training_writers)
    labels = tuple(report["labels"])
    if labels != tuple(sorted({record.label for record in training})):
        raise ValueError("Research checkpoint vocabulary changed")
    images, pixels = encode_samples(samples, development_writers)
    _, train_pixels = encode_samples(training, training_writers)
    features, logits = infer(model, images)
    wider = wider_personalization(samples, features, logits, labels, set(train_pixels), pixels)
    wider["trainingReportSHA256"] = hashlib.sha256((run / "report.json").read_bytes()).hexdigest()
    wider["weightsSHA256"] = report["weightsSHA256"]
    output.mkdir(parents=True, exist_ok=False)
    (output / "wider-personalization.json").write_text(json.dumps(wider, indent=2, sort_keys=True))
    print(json.dumps({k: v for k, v in wider.items() if k not in ("rows", "writers")}), flush=True)

    class EmbeddingOnly(torch.nn.Module):
        def __init__(self, encoder):
            super().__init__()
            self.encoder = encoder

        def forward(self, ink_raster):
            features, generic = self.encoder(ink_raster)
            return (features, generic) if include_generic else features

    traced = torch.jit.trace(EmbeddingOnly(model).eval(), torch.zeros(1, 1, 96, 256))
    outputs = [ct.TensorType(name="personalEmbedding", dtype=np.float32)]
    if include_generic:
        outputs.append(ct.TensorType(name="genericLogits", dtype=np.float32))
    converted = ct.convert(traced, inputs=[ct.TensorType(name="inkRaster", shape=(1, 1, 96, 256), dtype=np.float32)],
                           outputs=outputs,
                           convert_to="mlprogram", minimum_deployment_target=ct.target.iOS17,
                           compute_precision=ct.precision.FLOAT32, compute_units=ct.ComputeUnit.CPU_ONLY)
    converted.short_description = "Research-only personal glyph embedding; not a chord recognizer or trust score"
    converted.author = "iChart research; UJI Pen Characters v2 source: Prat et al., CC BY 4.0"
    converted.user_defined_metadata["ichart.scope"] = "personal-development-comparison-only"
    converted.user_defined_metadata["ichart.weights.sha256"] = report["weightsSHA256"]
    artifact = output / "PersonalVisualEncoderResearch.mlpackage"
    converted.save(str(artifact))
    # Reload the saved artifact, not the in-memory conversion object.
    runtime = ct.models.MLModel(str(artifact), compute_units=ct.ComputeUnit.CPU_ONLY)
    packet_samples = []
    maximum_error = 0.0
    maximum_generic_error = 0.0
    for i, sample in enumerate(samples):
        if not all_characters and sample.label not in ROOTS:
            continue
        expected = features[i]
        prediction = runtime.predict({"inkRaster": images[i:i + 1].numpy().astype(np.float32) / 255})
        actual = prediction["personalEmbedding"]
        if actual.shape != (1, 128) or not np.isfinite(actual).all():
            raise ValueError("Core ML output contract mismatch")
        error = float(np.max(np.abs(actual[0] - expected)))
        maximum_error = max(maximum_error, error)
        if error > 1e-4:
            raise ValueError(f"Core ML embedding parity failed: {error}")
        record = {"identity": sample.identity, "writer": sample.writer, "session": sample.session,
                  "label": sample.label, "strokes": [[{"x": p.x, "y": p.y} for p in stroke.points]
                                                     for stroke in sample.strokes],
                  "rasterSHA256": pixels[i], "embedding": expected.tolist()}
        if include_generic:
            generic = prediction["genericLogits"]
            if generic.shape != (1, len(labels)) or not np.isfinite(generic).all():
                raise ValueError("Core ML generic-logit contract mismatch")
            generic_error = float(np.max(np.abs(generic[0] - logits[i])))
            maximum_generic_error = max(maximum_generic_error, generic_error)
            if generic_error > 1e-4:
                raise ValueError(f"Core ML generic-logit parity failed: {generic_error}")
            record["genericLogits"] = logits[i].tolist()
        packet_samples.append(record)
    if len(packet_samples) != (len(samples) if all_characters else 112):
        raise ValueError("Missing planned parity samples")
    packet = {"version": VERSION, "researchOnly": True, "sourceSHA256": SOURCE_SHA256,
              "modelPackageSHA256": directory_digest(artifact), "maximumPythonCoreMLError": maximum_error,
              "includesGenericLogits": include_generic, "vocabulary": labels,
              "maximumPythonCoreMLGenericError": maximum_generic_error,
              "trainingReportSHA256": wider["trainingReportSHA256"], "samples": packet_samples,
              "queries": [{"identity": row["queryID"], "ranks": row["learnedRanks"]} for row in report["rows"]]}
    (output / "swift-parity.json").write_text(json.dumps(packet, indent=2, sort_keys=True))
    print(json.dumps({"pythonCoreMLParitySamples": len(packet_samples), "maximumAbsoluteError": maximum_error,
                      "maximumGenericError": maximum_generic_error,
                      "modelPackageSHA256": packet["modelPackageSHA256"], "researchOnly": True}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--include-generic", action="store_true")
    parser.add_argument("--all-characters", action="store_true")
    args = parser.parse_args()
    export(args.run.resolve(), args.source.resolve(), args.output.resolve(),
           include_generic=args.include_generic, all_characters=args.all_characters)

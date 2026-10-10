"""Blind final-checkpoint freeze, then separate literal scoring; research only.

No truth, writer, dataset, native alias, or copy cohort enters model inference.
The complete raw payload is authenticated before the scorer opens truth.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import itertools
from pathlib import Path
import platform

import numpy as np
import torch

from ..contracts import canonical_json_bytes as canonical, strict_json_loads

VERSION = "personal-hwrt-stroke-field-predictions-v1"
SCORE_VERSION = "personal-hwrt-stroke-field-score-v1"
PROTOCOL_SHA256 = "3cda2bcb7c64a79c3ef4371a8ef01fb1df0e0e75512a7f2f49f39cdc58ff9d13"
DOMAIN_SHA256 = "5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010"
ARMS = ("rasterControl", "strokeField")
NOVEL = ("#", "+", "/", "ø", "△")
WRITERS = ("trn_UJI_W04", "trn_UJI_W06", "trn_UJI_W08", "trn_UJI_W11",
           "trn_UPV_W35", "trn_UPV_W43", "trn_UPV_W47", "trn_UPV_W56")
NATIVE = {"196": ("+", "+"), "922": ("/", "/"), "266": ("\\#", "#"),
          "948": ("\\sharp", "#"), "950": ("\\emptyset", "ø"),
          "959": ("\\triangle", "△"), "977": ("\\vartriangle", "△"), "152": ("\\Delta", "△")}
NOVEL_COUNTS = {"+": 9, "/": 54, "#": 131, "ø": 97, "△": 144}
ROOT = Path(__file__).resolve().parents[3]
BLIND_FIELDS = {"opaqueID", "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def digest(value):
    return isinstance(value, str) and len(value) == 64 and set(value) <= set("0123456789abcdef")


def read_json(path, expected=None, maximum=128 * 1024 * 1024):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path and path.is_file() and not path.is_symlink()
            and 0 < path.stat().st_size <= maximum, "Bounded canonical regular JSON required")
    payload = path.read_bytes()
    require(expected is None or digest(expected) and sha(payload) == expected, "Artifact SHA256 changed")
    value = strict_json_loads(payload.decode("utf-8"), str(path))
    require(isinstance(value, dict) and canonical(value) == payload, "Canonical JSON object required")
    return value, payload


def write_exclusive(path, value, protected=()):
    path = Path(path)
    require(path.is_absolute() and path.parent.is_dir() and path.parent.resolve() == path.parent
            and not path.exists() and not path.is_symlink() and ROOT not in path.parents
            and all(path != Path(p).resolve() and Path(p).resolve() not in path.parents for p in protected),
            "Exclusive output outside input/repository required")
    payload = canonical(value)
    with path.open("xb") as stream:
        stream.write(payload)
    require(path.read_bytes() == payload, "Published prediction bytes changed")
    return sha(payload)


def code_identity():
    from . import personal_hwrt_stroke_train as train
    return train.code_identity()


def artifact_sha(receipt, name):
    value = receipt["artifacts"][name]
    result = value if isinstance(value, str) else value.get("SHA256", value.get("sha256"))
    require(digest(result), "Invalid bound artifact digest")
    return result


def vocabulary_check(vocabulary):
    require(isinstance(vocabulary, list) and len(vocabulary) == len(set(vocabulary)) == 102
            and all(isinstance(v, str) and v for v in vocabulary)
            and vocabulary[:97] == sorted(vocabulary[:97]) and tuple(vocabulary[97:]) == NOVEL,
            "Fixed ordered 97+5 vocabulary required")


def validate_inputs(inputs):
    require(set(inputs) == {"version", "vocabulary", "rows"}
            and inputs["version"] == "personal-hwrt-stroke-field-development-inputs-v1", "Blind input schema changed")
    vocabulary_check(inputs["vocabulary"])
    rows = inputs["rows"]
    require(isinstance(rows, list) and len(rows) == 1987 and len({r["opaqueID"] for r in rows}) == 1987,
            "All 1987 unique blind rows required")
    require(all(set(r) == BLIND_FIELDS and all(digest(v) for v in r.values()) for r in rows),
            "Blind input must contain hashes only, no query metadata")


def validate_domain(domain, vocabulary):
    require(domain["version"] == "chord-recognition-domain-v1" and domain["vocabulary"] == vocabulary[:97]
            and len(domain["allowedLabels"]) == len(set(domain["allowedLabels"])) == 41
            and set(domain["allowedLabels"]) <= set(vocabulary[:97]), "Exact Swift 97/41 export required")
    return domain["allowedLabels"] + list(NOVEL)


def projected(logits, vocabulary, allowed):
    require(len(logits) == len(vocabulary) and all(type(v) in (int, float) for v in logits)
            and np.isfinite(np.asarray(logits)).all(), "Complete finite logits required")
    raw = vocabulary[int(np.argmax(logits))]
    return raw, raw if raw in allowed else None


def vector_sha(values):
    return sha(np.asarray(values, dtype="<f4").tobytes())


def result(embedding, logits, vocabulary, allowed):
    require(len(embedding) == 128 and all(type(v) in (int, float) for v in embedding)
            and np.isfinite(embedding).all() and abs(float(np.linalg.norm(embedding)) - 1) <= 2e-5,
            "Finite unit 128-dimensional embedding required")
    raw, domain = projected(logits, vocabulary, allowed)
    return {"failure": None, "embedding": embedding, "rawLogits": logits, "rawTop1": raw,
            "domainTop1": domain, "embeddingSHA256": vector_sha(embedding), "logitsSHA256": vector_sha(logits)}


def failure(error):
    return {"failure": f"{type(error).__name__}: {error}", "embedding": None, "rawLogits": None,
            "rawTop1": None, "domainTop1": None, "embeddingSHA256": None, "logitsSHA256": None}


def freeze_forward(models, fields, inputs, allowed, batch_size=128):
    rows = [{**r, "results": {}} for r in inputs["rows"]]
    require(len(fields) == len(rows) and set(models) == set(ARMS) and all(not m.training and all(not c.training for c in m.modules())
            for m in models.values()), "Both CPU eval models required")
    with torch.inference_mode():
        for start in range(0, len(rows), batch_size):
            batch = torch.from_numpy(np.asarray(fields[start:start + batch_size]).copy())
            require(batch.dtype == torch.float32 and batch.shape[1:] == (5, 96, 256)
                    and torch.isfinite(batch).all(), "Finite unchanged field batch required")
            for offset, field in enumerate(batch.numpy()):
                raster = np.rint(field[0] * np.float32(255)).astype(np.uint8)
                require(np.array_equal(field[0], raster.astype(np.float32) / np.float32(255))
                        and sha(raster.tobytes()) == rows[start + offset]["rasterSHA256"]
                        and sha(field.astype("<f4", copy=False).tobytes()) == rows[start + offset]["fieldSHA256"],
                        "Field/occupancy row identity changed")
            for arm in ARMS:
                try:
                    features, logits = models[arm](batch)
                    require(features.shape == (len(batch), 128) and logits.shape == (len(batch), 102),
                            "Complete paired 102/128 model output required")
                    for offset, (e, l) in enumerate(zip(features.cpu().tolist(), logits.cpu().tolist())):
                        try:
                            rows[start + offset]["results"][arm] = result(e, l, inputs["vocabulary"], allowed)
                        except (ValueError, RuntimeError, FloatingPointError) as error:
                            rows[start + offset]["results"][arm] = failure(error)
                except (ValueError, RuntimeError, FloatingPointError) as error:
                    for row in rows[start:start + len(batch)]:
                        row["results"][arm] = failure(error)
    return rows


def predict(data_dir, fit_dir, domain_path, output, *, data_receipt_sha256, fit_receipt_sha256):
    from . import personal_hwrt_stroke_data as data, personal_hwrt_stroke_train as train
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    code = code_identity()
    models, fit = train.load_fitted_models(Path(fit_dir), fit_receipt_sha256)  # BEFORE dev inputs.
    receipt, receipt_bytes = read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)
    require(receipt["protocolSHA256"] == PROTOCOL_SHA256 and receipt["fitReceiptSHA256"] == fit_receipt_sha256
            and fit["codeSHA256"] == code and receipt["codeSHA256"] == data.code_identity()
            and receipt["trainingDataReceiptSHA256"] == fit["dataReceiptSHA256"]
            and receipt["sourceBindings"]["domain"]["sha256"] == DOMAIN_SHA256,
            "Data/final-fit/protocol/code/source binding changed")
    fields, inputs, loaded = data.load_development_inputs(Path(data_dir))
    require(loaded == receipt, "Loaded data receipt changed")
    validate_inputs(inputs)
    require(inputs["vocabulary"] == fit["vocabulary"], "Model/input vocabulary mismatch")
    domain, domain_bytes = read_json(domain_path, DOMAIN_SHA256)
    allowed = validate_domain(domain, inputs["vocabulary"])
    states = {a: train._state_digest(m.state_dict()) for a, m in models.items()}
    require(states == fit["finalStateSHA256"], "Loaded final states mismatch")
    rows = freeze_forward(models, fields, inputs, allowed)
    require(states == {a: train._state_digest(m.state_dict()) for a, m in models.items()}, "Inference changed model/BN state")
    _, fit_after = train.load_fitted_models(Path(fit_dir), fit_receipt_sha256)
    _, inputs_after, receipt_after = data.load_development_inputs(Path(data_dir))
    require(fit_after == fit and inputs_after == inputs and receipt_after == receipt
            and read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)[1] == receipt_bytes
            and read_json(domain_path, DOMAIN_SHA256)[1] == domain_bytes and code_identity() == code
            and data.code_identity() == receipt["codeSHA256"],
            "Frozen sources/code/weights changed during inference")
    packet = {"version": VERSION, "scope": "reused-public-isolated-glyph-research-only",
              "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": code, "fitReceiptSHA256": fit_receipt_sha256,
              "fitReceipt": fit,
              "weightsSHA256": fit["weightsSHA256"], "finalStateSHA256": states,
              "dataReceiptSHA256": data_receipt_sha256, "dataReceipt": receipt,
              "inputsSHA256": artifact_sha(receipt, "inputs.json"), "fieldsSHA256": artifact_sha(receipt, "fields.npy"),
              "truthSHA256": artifact_sha(receipt, "truth.json"), "domainSHA256": DOMAIN_SHA256, "domain": domain,
              "vocabulary": inputs["vocabulary"], "allowedLabels": allowed, "rows": rows,
              "runtime": {"python": platform.python_version(), "numpy": str(np.__version__), "torch": str(torch.__version__),
                          "cpuThreads": 4, "deterministicAlgorithms": True, "batchNormalizationUpdates": 0},
              "personalizationPerformed": False, "privateInkUsed": False, "reservedWriterInferencePerformed": False,
              "freshValidation": False, "liveRecognitionChanged": False, "productionEligible": False}
    return write_exclusive(output, packet, (data_dir, fit_dir, domain_path))


def validate_packet(packet, receipt, inputs):
    from . import personal_hwrt_stroke_data as data
    require(packet["version"] == VERSION and packet["protocolSHA256"] == PROTOCOL_SHA256
            and packet["codeSHA256"] == code_identity() and packet["dataReceipt"] == receipt
            and packet["vocabulary"] == inputs["vocabulary"] and packet["domainSHA256"] == DOMAIN_SHA256
            and sha(canonical(packet["domain"])) == DOMAIN_SHA256
            and packet["allowedLabels"] == validate_domain(packet["domain"], inputs["vocabulary"])
            and packet["fitReceiptSHA256"] == receipt["fitReceiptSHA256"]
            and packet["truthSHA256"] == artifact_sha(receipt, "truth.json")
            and packet["inputsSHA256"] == artifact_sha(receipt, "inputs.json")
            and packet["fieldsSHA256"] == artifact_sha(receipt, "fields.npy"), "Prediction binding mismatch")
    require(receipt["codeSHA256"] == data.code_identity(), "Bound preparation code changed")
    fit = packet["fitReceipt"]
    require(sha(canonical(fit)) == packet["fitReceiptSHA256"] and fit["codeSHA256"] == packet["codeSHA256"]
            and fit["protocolSHA256"] == PROTOCOL_SHA256 and fit["vocabulary"] == inputs["vocabulary"]
            and fit["weightsSHA256"] == packet["weightsSHA256"] and fit["finalStateSHA256"] == packet["finalStateSHA256"]
            and fit["dataReceiptSHA256"] == receipt["trainingDataReceiptSHA256"]
            and set(packet["weightsSHA256"]) == set(packet["finalStateSHA256"]) == set(ARMS)
            and all(digest(v) for v in (*packet["weightsSHA256"].values(), *packet["finalStateSHA256"].values())),
            "Final model/state/training source commitments mismatch")
    require(len(packet["rows"]) == len(inputs["rows"]), "Missing prediction rows")
    for row, blind in zip(packet["rows"], inputs["rows"]):
        require(set(row) == BLIND_FIELDS | {"results"} and {k: row[k] for k in BLIND_FIELDS} == blind
                and set(row["results"]) == set(ARMS), "Paired opaque row order/metadata mismatch")
        for output in row["results"].values():
            if output["failure"] is None:
                require(output == result(output["embedding"], output["rawLogits"], packet["vocabulary"], packet["allowedLabels"]),
                        "Numerical vector/hash/actual-top projection mismatch")
            else:
                require(isinstance(output["failure"], str) and output["failure"]
                        and set(output) == set(failure(ValueError()))
                        and all(output[k] is None for k in output if k != "failure"), "Incomplete failure retention")


def paired(rows):
    c = [r["results"][ARMS[0]]["rawTop1"] == r["label"] for r in rows]
    p = [r["results"][ARMS[1]]["rawTop1"] == r["label"] for r in rows]
    gains, harms = sum(not a and b for a, b in zip(c, p)), sum(a and not b for a, b in zip(c, p))
    return {"count": len(rows), "controlCorrect": sum(c), "candidateCorrect": sum(p), "gains": gains,
            "harms": harms, "net": gains - harms, "bothCorrect": sum(a and b for a, b in zip(c, p)),
            "neitherCorrect": sum(not a and not b for a, b in zip(c, p)),
            "invalidControl": sum(r["results"][ARMS[0]]["failure"] is not None for r in rows),
            "invalidCandidate": sum(r["results"][ARMS[1]]["failure"] is not None for r in rows),
            "domain": {arm: {"correct": sum(r["results"][arm]["domainTop1"] == r["label"] for r in rows),
                       "wrongPermitted": sum(r["results"][arm]["domainTop1"] is not None and r["results"][arm]["domainTop1"] != r["label"] for r in rows),
                       "unresolved": sum(r["results"][arm]["domainTop1"] is None for r in rows)} for arm in ARMS}}


def sign_flip(nets):
    require(len(nets) == 8 and all(type(v) is int for v in nets), "Eight writer net correction counts required")
    observed = abs(sum(nets))
    extreme = sum(abs(sum(s * n for s, n in zip(signs, nets))) >= observed
                  for signs in itertools.product((-1, 1), repeat=8))
    return {"observedNet": sum(nets), "extremeAssignments": extreme, "assignments": 256, "twoSidedP": extreme / 256}


def summarize(rows, old_allowed):
    uji = [r for r in rows if r["source"] == "uji"]
    hwrt = [r for r in rows if r["source"] == "hwrt"]
    writers = {w: paired([r for r in uji if r["writer"] == w]) for w in WRITERS}
    ood = [r for r in uji if r["label"] not in old_allowed]
    return {"uji": paired(uji), "hwrt": paired(hwrt), "writers": writers,
            "writerSignFlip": sign_flip([writers[w]["net"] for w in WRITERS]),
            "oldDomain": paired([r for r in uji if r["label"] in old_allowed]),
            "ood": {"count": len(ood), "controlNoReadToCandidatePermitted": sum(r["results"][ARMS[0]]["domainTop1"] is None and r["results"][ARMS[1]]["domainTop1"] is not None for r in ood),
                    "permitted": {a: sum(r["results"][a]["domainTop1"] is not None for r in ood) for a in ARMS}},
            "mappedClasses": {l: paired([r for r in hwrt if r["label"] == l]) for l in NOVEL},
            "nativeAliases": {str(i): {"nativeLabel": label, "mappedLabel": mapped,
                               **paired([r for r in hwrt if r["nativeSymbolID"] == i])} for i, (label, mapped) in NATIVE.items()}}


def fixed_screen(view, *, raw):
    writers, uji, hwrt, ood = view["writers"], view["uji"], view["hwrt"], view["ood"]
    checks = {"completeFiniteOutputs": all(v["invalidControl"] == v["invalidCandidate"] == 0 for v in (uji, hwrt)),
              "eligibleWriterAndClassCohorts": all(v["count"] > 0 for v in writers.values()) and all(v["count"] > 0 for v in view["mappedClasses"].values()) and view["oldDomain"]["count"] > 0 and ood["count"] > 0,
              "ujiGainsExceedHarms": uji["gains"] > uji["harms"], "writerTwoSidedPBelowPoint05": view["writerSignFlip"]["twoSidedP"] < .05,
              "sixWritersNonWorse": sum(v["net"] >= 0 for v in writers.values()) >= 6,
              "noWriterNetBelowMinusTwo": min(v["net"] for v in writers.values()) >= -2,
              "oldDomainGainsExceedHarms": view["oldDomain"]["gains"] > view["oldDomain"]["harms"],
              "zeroNewOODPermittedTransitions": ood["controlNoReadToCandidatePermitted"] == 0,
              "noIncreasedOODPermittedOutputs": ood["permitted"][ARMS[1]] <= ood["permitted"][ARMS[0]],
              "hwrtGainsExceedHarms": hwrt["gains"] > hwrt["harms"],
              "everyNovelClassNonWorse": all(v["net"] >= 0 for v in view["mappedClasses"].values())}
    if raw:
        checks["rawCandidateUJIAtLeast1229"] = uji["candidateCorrect"] >= 1229
    return {"checks": checks, "passes": all(checks.values())}


def join_truth(packet, truth):
    require(set(truth) == {"version", "rows", "copyUnion"}
            and truth["version"] == "personal-hwrt-stroke-field-development-truth-v1" and len(truth["rows"]) == 1987
            and len({r["opaqueID"] for r in truth["rows"]}) == 1987, "Complete unique truth required")
    lookup = {r["opaqueID"]: r for r in truth["rows"]}
    require(set(lookup) == {r["opaqueID"] for r in packet["rows"]}, "Truth/prediction row-set mismatch")
    truth_fields = BLIND_FIELDS | {"label", "source", "writer", "session", "nativeSymbolID", "copyReasons"}
    require(all(set(r) == truth_fields for r in truth["rows"])
            and all({k: lookup[r["opaqueID"]][k] for k in BLIND_FIELDS} == {k: r[k] for k in BLIND_FIELDS}
                    for r in packet["rows"]), "Truth feature/source identity mismatch")
    rows = [{**lookup[r["opaqueID"]], **r} for r in packet["rows"]]
    copy_reasons = {prefix + field for prefix in ("training-", "repeated-development-")
                    for field in ("rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256")}
    require(all(r["label"] in packet["vocabulary"] and r["source"] in ("uji", "hwrt")
                and isinstance(r["copyReasons"], list) and len(set(r["copyReasons"])) == len(r["copyReasons"])
                and set(r["copyReasons"]) <= copy_reasons for r in rows), "Invalid truth/copy metadata")
    uji, hwrt = [r for r in rows if r["source"] == "uji"], [r for r in rows if r["source"] == "hwrt"]
    require(len(uji) == 1552 and len(hwrt) == 435 and all(sum(r["writer"] == w for r in uji) == 194 for w in WRITERS)
            and all(r["writer"] in WRITERS and type(r["session"]) is int and r["session"] in (1, 2) and r["nativeSymbolID"] is None and r["label"] in packet["vocabulary"][:97] for r in uji)
            and all(sum(r["writer"] == w and r["session"] == s and r["label"] == l for r in uji) == 1 for w in WRITERS for s in (1, 2) for l in packet["vocabulary"][:97]), "Complete fixed UJI development grid required")
    require(all(r["writer"] is None and r["session"] is None and isinstance(r["nativeSymbolID"], str)
                and r["nativeSymbolID"] in NATIVE and NATIVE[r["nativeSymbolID"]][1] == r["label"] for r in hwrt)
            and all(sum(r["label"] == l for r in hwrt) == n for l, n in NOVEL_COUNTS.items())
            and set(r["nativeSymbolID"] for r in hwrt) == set(NATIVE), "Fixed original-HWRT test mapping/counts required")
    union = truth["copyUnion"]
    reasons = Counter(reason for r in rows for reason in r["copyReasons"])
    require(union["version"] == "personal-hwrt-stroke-field-input-copy-union-v1"
            and union["hashFields"] == ["rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"]
            and union["representativeRule"] == "lexicographically-smallest-opaqueID-per-development-hash"
            and union["affectedOpaqueIDs"] == sorted(r["opaqueID"] for r in rows if r["copyReasons"])
            and union["reasonCounts"] == dict(reasons), "Source-only copy-union coverage/reasons mismatch")
    return rows


def score(predictions, data_dir, output, *, predictions_sha256, data_receipt_sha256):
    packet, frozen = read_json(predictions, predictions_sha256)  # Authenticated FIRST, before any truth open.
    receipt, receipt_bytes = read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)
    inputs, _ = read_json(Path(data_dir) / "inputs.json", artifact_sha(receipt, "inputs.json"))
    validate_inputs(inputs)
    require(packet["dataReceiptSHA256"] == data_receipt_sha256, "Data receipt pin mismatch")
    validate_packet(packet, receipt, inputs)
    truth, truth_bytes = read_json(Path(data_dir) / "truth.json", packet["truthSHA256"])
    rows = join_truth(packet, truth)
    require(truth["copyUnion"]["trainingDataReceiptSHA256"] == receipt["trainingDataReceiptSHA256"]
            and len(truth["copyUnion"]["affectedOpaqueIDs"]) == receipt["counts"]["copyUnionRows"],
            "Copy union/training source receipt binding mismatch")
    raw = summarize(rows, packet["domain"]["allowedLabels"])
    kept = [r for r in rows if not r["copyReasons"]]
    no_copy = summarize(kept, packet["domain"]["allowedLabels"])
    screens = {"raw": fixed_screen(raw, raw=True), "inputCopyUnionExcluded": fixed_screen(no_copy, raw=False)}
    report = {"version": SCORE_VERSION, "protocolSHA256": PROTOCOL_SHA256, "predictionsSHA256": predictions_sha256,
              "dataReceiptSHA256": data_receipt_sha256, "truthSHA256": packet["truthSHA256"], "codeSHA256": packet["codeSHA256"],
              "raw": raw, "inputCopyUnionExcluded": no_copy, "fixedScreen": screens,
              "passesFixedScreen": all(v["passes"] for v in screens.values()), "copyUnion": truth["copyUnion"],
              "excludedCount": len(rows) - len(kept), "excludedOpaqueIDs": [r["opaqueID"] for r in rows if r["copyReasons"]],
              "rows": rows, "scope": "reused-UJI-eight-writers-and-original-HWRT-test-isolated-glyphs",
              "pooledAccuracyReported": False, "personalizationMeasured": False, "freshValidation": False,
              "liveRecognitionChanged": False, "productionEligible": False, "shippingRightsCleared": False}
    require(read_json(predictions, predictions_sha256)[1] == frozen
            and read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)[1] == receipt_bytes
            and read_json(Path(data_dir) / "truth.json", packet["truthSHA256"])[1] == truth_bytes
            and code_identity() == packet["codeSHA256"], "Scoring changed frozen inputs/code")
    return write_exclusive(output, report, (predictions, data_dir))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("predict")
    for name in ("data", "data-receipt-sha256", "fit", "fit-receipt-sha256", "domain", "output"):
        p.add_argument("--" + name, required=True)
    s = sub.add_parser("score")
    for name in ("predictions", "predictions-sha256", "data", "data-receipt-sha256", "output"):
        s.add_argument("--" + name, required=True)
    a = vars(parser.parse_args()); command = a.pop("command")
    if command == "predict":
        predict(a.pop("data"), a.pop("fit"), a.pop("domain"), a.pop("output"), **a)
    else:
        score(a.pop("predictions"), a.pop("data"), a.pop("output"), **a)


if __name__ == "__main__":
    main()

"""Versioned neutral-field blind freeze and separate literal scorer.

Only stateless numerical/metric functions are reused from the rejected directed
experiment. No old protocol or receipt is rewritten or presented as neutral.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
from pathlib import Path
import platform

import torch

from ..contracts import canonical_json_bytes as canonical, strict_json_loads
from .personal_hwrt_stroke_evaluate import freeze_forward, result, summarize, fixed_screen

VERSION = "personal-unoriented-hwrt-predictions-v1"
SCORE_VERSION = "personal-unoriented-hwrt-score-v1"
DATA_VERSION = "personal-unoriented-hwrt-data-v1"
INPUT_VERSION = "personal-unoriented-hwrt-development-inputs-v1"
TRUTH_VERSION = "personal-unoriented-hwrt-development-truth-v1"
COPY_VERSION = "personal-unoriented-hwrt-input-copy-union-v1"
FIT_VERSION = "personal-unoriented-hwrt-fit-v1"
FIELD_VERSION = "personal-unoriented-stroke-field-v1"
MODEL_VERSION = "personal-unoriented-stroke-field-encoder-v1-97-or-102"
PROTOCOL_SHA256 = "4d72f1e61e409e8da9c563dc7a8eca430370675b5b6fa81eeab9dad327178fe3"
OLD_PROTOCOL_SHA256 = "3cda2bcb7c64a79c3ef4371a8ef01fb1df0e0e75512a7f2f49f39cdc58ff9d13"
PRIOR_PREDICTIONS_SHA256 = "ee3aab3135b609117c9556ffbd119bb26424bffb43b277db7f81116d82c303f0"
DOMAIN_SHA256 = "5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010"
CONTROL_STATE = "ca97f42d345c3e7e777ef92412db30e7a26930f0b2f8411873e5db8505970c99"
CONTROL_SCHEDULE = "d1ef91c13bb4477de88c57510851149177e528858f0e2bfcf69643b8c062d6ed"
CONTROL_AFFINE = "1fb59eaa47d693eab351ea9b909659fd48b66eb411dd06ac7767a884e7ebeabc"
ARMS = ("rasterControl", "strokeField")
NOVEL = ("#", "+", "/", "ø", "△")
WRITERS = ("trn_UJI_W04", "trn_UJI_W06", "trn_UJI_W08", "trn_UJI_W11",
           "trn_UPV_W35", "trn_UPV_W43", "trn_UPV_W47", "trn_UPV_W56")
NATIVE = {"196": "+", "922": "/", "266": "#", "948": "#", "950": "ø",
          "959": "△", "977": "△", "152": "△"}
NOVEL_COUNTS = {"+": 9, "/": 54, "#": 131, "ø": 97, "△": 144}
BLIND_FIELDS = {"opaqueID", "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"}
ROOT = Path(__file__).resolve().parents[3]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def digest(value):
    return isinstance(value, str) and len(value) == 64 and set(value) <= set("0123456789abcdef")


def read_json(path, expected, maximum=128 * 1024 * 1024):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path and path.is_file() and not path.is_symlink()
            and 0 < path.stat().st_size <= maximum, "Bounded canonical regular JSON required")
    payload = path.read_bytes()
    require(digest(expected) and sha(payload) == expected, "Artifact SHA256 changed")
    value = strict_json_loads(payload.decode("utf-8"), str(path))
    require(isinstance(value, dict) and canonical(value) == payload, "Canonical JSON object required")
    return value, payload


def write_exclusive(path, value, protected):
    path = Path(path)
    require(path.is_absolute() and path.parent.is_dir() and path.parent.resolve() == path.parent
            and not path.exists() and not path.is_symlink() and ROOT not in path.parents
            and all(path != Path(p).resolve() and Path(p).resolve() not in path.parents for p in protected),
            "Exclusive output outside inputs/repository required")
    payload = canonical(value)
    with path.open("xb") as stream:
        stream.write(payload)
    require(path.read_bytes() == payload, "Published bytes changed")
    return sha(payload)


def code_identity():
    from . import personal_unoriented_hwrt_train as train
    return train.code_identity()


def artifact_sha(receipt, name):
    value = receipt["artifacts"][name]
    require(set(value) == {"bytes", "sha256"} and digest(value["sha256"])
            and type(value["bytes"]) is int and value["bytes"] > 0, "Bound artifact identity required")
    return value["sha256"]


def validate_inputs(inputs):
    require(set(inputs) == {"version", "vocabulary", "rows"} and inputs["version"] == INPUT_VERSION,
            "Neutral blind input version/schema required")
    vocabulary = inputs["vocabulary"]
    require(isinstance(vocabulary, list) and len(vocabulary) == len(set(vocabulary)) == 102
            and all(isinstance(v, str) and v for v in vocabulary) and vocabulary[:97] == sorted(vocabulary[:97])
            and tuple(vocabulary[97:]) == NOVEL, "Fixed ordered 97+5 vocabulary required")
    rows = inputs["rows"]
    require(len(rows) == 1987 and len({r["opaqueID"] for r in rows}) == 1987
            and all(set(r) == BLIND_FIELDS and all(digest(v) for v in r.values()) for r in rows),
            "Complete label-free 1987-row input required")


def validate_domain(domain, vocabulary):
    require(domain["version"] == "chord-recognition-domain-v1" and domain["vocabulary"] == vocabulary[:97]
            and len(domain["allowedLabels"]) == len(set(domain["allowedLabels"])) == 41
            and set(domain["allowedLabels"]) <= set(vocabulary[:97]), "Exact Swift 97/41 export required")
    return domain["allowedLabels"] + list(NOVEL)


def validate_receipts(receipt, fit, fit_sha, code, preparation_code):
    require(receipt["version"] == DATA_VERSION and receipt["role"] == "development"
            and fit["version"] == FIT_VERSION and receipt["fieldVersion"] == fit["fieldVersion"] == FIELD_VERSION
            and fit["modelVersion"] == MODEL_VERSION and receipt["protocolSHA256"] == fit["protocolSHA256"] == PROTOCOL_SHA256
            and receipt["fitReceiptSHA256"] == fit_sha and sha(canonical(fit)) == fit_sha
            and fit["codeSHA256"] == code and receipt["codeSHA256"] == preparation_code
            and receipt["trainingDataReceiptSHA256"] == fit["dataReceiptSHA256"]
            and receipt["sourceBindings"]["domain"]["sha256"] == DOMAIN_SHA256
            and receipt["vocabulary"] == fit["vocabulary"], "Neutral source/model/protocol/code commitment mismatch")
    control = fit["augmentationLedger"]["rasterControl"]
    require(fit["finalStateSHA256"]["rasterControl"] == CONTROL_STATE
            and control["scheduleSHA256"] == CONTROL_SCHEDULE
            and control["augmentationDrawStreamSHA256"] == CONTROL_AFFINE,
            "Refitted control state/schedule/affine reproducibility sentinel failed")


def control_parity(rows, prior, vocabulary, allowed):
    require(prior["version"] == "personal-hwrt-stroke-field-predictions-v1"
            and prior["protocolSHA256"] == OLD_PROTOCOL_SHA256 and prior["vocabulary"] == vocabulary
            and prior["allowedLabels"] == allowed and len(rows) == len(prior["rows"]) == 1987,
            "Pinned original blind control packet required")
    for row, original in zip(rows, prior["rows"]):
        require(all(row[k] == original[k] for k in ("opaqueID", "rasterSHA256", "normalizedGeometrySHA256")),
                "Neutral/prior blind source alignment mismatch")
        output = original["results"]["rasterControl"]
        require(output["failure"] is None and output == result(output["embedding"], output["rawLogits"], vocabulary, allowed)
                and row["results"]["rasterControl"] == output, "Refitted control full numerical output mismatch")
    return {"priorPredictionsSHA256": PRIOR_PREDICTIONS_SHA256, "rows": 1987, "equalFullOutputs": True,
            "labelsOrTruthOpened": False}


def predict(data_dir, fit_dir, domain_path, prior_predictions, output, *, data_receipt_sha256, fit_receipt_sha256):
    from . import personal_unoriented_hwrt_data as data, personal_unoriented_hwrt_train as train
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    code = code_identity()
    models, fit = train.load_fitted_models(Path(fit_dir), fit_receipt_sha256)  # BEFORE any dev loader.
    receipt, receipt_bytes = read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)
    validate_receipts(receipt, fit, fit_receipt_sha256, code, data.code_identity())
    fields, inputs, loaded = data.load_development_inputs(Path(data_dir))
    require(loaded == receipt, "Loaded neutral data receipt changed")
    validate_inputs(inputs)
    require(inputs["vocabulary"] == fit["vocabulary"], "Model/blind vocabulary mismatch")
    domain, domain_bytes = read_json(domain_path, DOMAIN_SHA256)
    allowed = validate_domain(domain, inputs["vocabulary"])
    states = {a: train._state_digest(m.state_dict()) for a, m in models.items()}
    require(states == fit["finalStateSHA256"], "Loaded final states mismatch")
    rows = freeze_forward(models, fields, inputs, allowed)
    require(states == {a: train._state_digest(m.state_dict()) for a, m in models.items()}, "Inference changed model/BN state")
    prior, prior_bytes = read_json(prior_predictions, PRIOR_PREDICTIONS_SHA256)
    parity = control_parity(rows, prior, inputs["vocabulary"], allowed)  # Label-free, BEFORE publication.
    _, fit_after = train.load_fitted_models(Path(fit_dir), fit_receipt_sha256)
    _, inputs_after, receipt_after = data.load_development_inputs(Path(data_dir))
    require(fit_after == fit and inputs_after == inputs and receipt_after == receipt and code_identity() == code
            and data.code_identity() == receipt["codeSHA256"]
            and read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)[1] == receipt_bytes
            and read_json(domain_path, DOMAIN_SHA256)[1] == domain_bytes
            and read_json(prior_predictions, PRIOR_PREDICTIONS_SHA256)[1] == prior_bytes,
            "Frozen sources/code/weights changed during inference")
    packet = {"version": VERSION, "fieldVersion": FIELD_VERSION, "modelVersion": MODEL_VERSION,
              "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": code, "fitReceiptSHA256": fit_receipt_sha256, "fitReceipt": fit,
              "weightsSHA256": fit["weightsSHA256"], "finalStateSHA256": states, "dataReceiptSHA256": data_receipt_sha256,
              "dataReceipt": receipt, "inputsSHA256": artifact_sha(receipt, "inputs.json"), "fieldsSHA256": artifact_sha(receipt, "fields.npy"),
              "truthSHA256": artifact_sha(receipt, "truth.json"), "domainSHA256": DOMAIN_SHA256, "domain": domain,
              "vocabulary": inputs["vocabulary"], "allowedLabels": allowed, "rows": rows, "controlParity": parity,
              "runtime": {"python": platform.python_version(), "torch": str(torch.__version__), "cpuThreads": 4,
                          "deterministicAlgorithms": True, "batchNormalizationUpdates": 0},
              "scope": "neutral-field-reused-public-isolated-glyph-research-only", "personalizationPerformed": False,
              "privateInkUsed": False, "reservedWriterInferencePerformed": False, "freshValidation": False,
              "liveRecognitionChanged": False, "productionEligible": False}
    return write_exclusive(output, packet, (data_dir, fit_dir, domain_path, prior_predictions))


def validate_packet(packet, receipt, inputs, prior):
    from . import personal_unoriented_hwrt_data as data
    require(packet["version"] == VERSION and packet["fieldVersion"] == FIELD_VERSION and packet["modelVersion"] == MODEL_VERSION
            and packet["protocolSHA256"] == PROTOCOL_SHA256 and packet["codeSHA256"] == code_identity()
            and packet["dataReceipt"] == receipt and packet["vocabulary"] == inputs["vocabulary"]
            and packet["domainSHA256"] == DOMAIN_SHA256 and sha(canonical(packet["domain"])) == DOMAIN_SHA256
            and packet["allowedLabels"] == validate_domain(packet["domain"], inputs["vocabulary"])
            and all(packet[key] == artifact_sha(receipt, name) for key, name in
                    (("inputsSHA256", "inputs.json"), ("fieldsSHA256", "fields.npy"), ("truthSHA256", "truth.json"))),
            "Neutral prediction/source commitment mismatch")
    validate_receipts(receipt, packet["fitReceipt"], packet["fitReceiptSHA256"], packet["codeSHA256"], data.code_identity())
    require(packet["weightsSHA256"] == packet["fitReceipt"]["weightsSHA256"]
            and packet["finalStateSHA256"] == packet["fitReceipt"]["finalStateSHA256"]
            and set(packet["weightsSHA256"]) == set(packet["finalStateSHA256"]) == set(ARMS)
            and all(digest(v) for v in (*packet["weightsSHA256"].values(), *packet["finalStateSHA256"].values())), "Final weights/state mismatch")
    require(len(packet["rows"]) == len(inputs["rows"]), "Missing prediction rows")
    for row, blind in zip(packet["rows"], inputs["rows"]):
        require(set(row) == BLIND_FIELDS | {"results"} and {k: row[k] for k in BLIND_FIELDS} == blind
                and set(row["results"]) == set(ARMS), "Paired opaque row order/metadata mismatch")
        for output in row["results"].values():
            if output["failure"] is None:
                require(output == result(output["embedding"], output["rawLogits"], packet["vocabulary"], packet["allowedLabels"]),
                        "Full vector/hash/actual-top projection mismatch")
            else:
                require(set(output) == {"failure", "embedding", "rawLogits", "rawTop1", "domainTop1", "embeddingSHA256", "logitsSHA256"}
                        and isinstance(output["failure"], str) and output["failure"]
                        and all(v is None for k, v in output.items() if k != "failure"), "Incomplete failure retention")
    require(packet["controlParity"] == control_parity(packet["rows"], prior, inputs["vocabulary"], packet["allowedLabels"]),
            "Full blind control parity commitment mismatch")


def join_truth(packet, truth):
    require(set(truth) == {"version", "rows", "copyUnion"} and truth["version"] == TRUTH_VERSION
            and len(truth["rows"]) == 1987 and len({r["opaqueID"] for r in truth["rows"]}) == 1987, "Complete neutral truth required")
    lookup = {r["opaqueID"]: r for r in truth["rows"]}
    require(set(lookup) == {r["opaqueID"] for r in packet["rows"]}, "Truth/prediction row-set mismatch")
    truth_fields = BLIND_FIELDS | {"label", "source", "writer", "session", "nativeSymbolID", "copyReasons"}
    require(all(set(r) == truth_fields for r in truth["rows"])
            and all({k: lookup[r["opaqueID"]][k] for k in BLIND_FIELDS} == {k: r[k] for k in BLIND_FIELDS} for r in packet["rows"]),
            "Truth feature/source identity mismatch")
    rows = [{**lookup[r["opaqueID"]], **r} for r in packet["rows"]]
    hash_fields = ["rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"]
    allowed_reasons = {prefix + field for prefix in ("training-", "repeated-development-") for field in hash_fields}
    require(all(r["label"] in packet["vocabulary"] and r["source"] in ("uji", "hwrt") and isinstance(r["copyReasons"], list)
                and len(set(r["copyReasons"])) == len(r["copyReasons"]) and set(r["copyReasons"]) <= allowed_reasons for r in rows), "Invalid truth/copy metadata")
    uji, hwrt = [r for r in rows if r["source"] == "uji"], [r for r in rows if r["source"] == "hwrt"]
    require(len(uji) == 1552 and len(hwrt) == 435 and all(sum(r["writer"] == w for r in uji) == 194 for w in WRITERS)
            and all(r["writer"] in WRITERS and type(r["session"]) is int and r["session"] in (1, 2)
                    and r["nativeSymbolID"] is None and r["label"] in packet["vocabulary"][:97] for r in uji)
            and all(sum(r["writer"] == w and r["session"] == s and r["label"] == l for r in uji) == 1
                    for w in WRITERS for s in (1, 2) for l in packet["vocabulary"][:97]), "Complete fixed UJI development grid required")
    require(all(r["writer"] is None and r["session"] is None and isinstance(r["nativeSymbolID"], str)
                and r["nativeSymbolID"] in NATIVE and NATIVE[r["nativeSymbolID"]] == r["label"] for r in hwrt)
            and all(sum(r["label"] == l for r in hwrt) == n for l, n in NOVEL_COUNTS.items())
            and set(r["nativeSymbolID"] for r in hwrt) == set(NATIVE), "Fixed original-HWRT test mapping/counts required")
    union = truth["copyUnion"]
    require(union["version"] == COPY_VERSION and union["hashFields"] == hash_fields
            and union["representativeRule"] == "lexicographically-smallest-opaqueID-per-development-hash"
            and union["affectedOpaqueIDs"] == sorted(r["opaqueID"] for r in rows if r["copyReasons"])
            and union["reasonCounts"] == dict(Counter(reason for r in rows for reason in r["copyReasons"])), "Recomputed source-only copy-union mismatch")
    return rows


def score(predictions, data_dir, prior_predictions, output, *, predictions_sha256, data_receipt_sha256):
    packet, frozen = read_json(predictions, predictions_sha256)  # Authenticated FIRST, before truth.
    receipt, receipt_bytes = read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)
    inputs, _ = read_json(Path(data_dir) / "inputs.json", artifact_sha(receipt, "inputs.json"))
    validate_inputs(inputs)
    require(packet["dataReceiptSHA256"] == data_receipt_sha256, "Data receipt pin mismatch")
    prior, prior_bytes = read_json(prior_predictions, PRIOR_PREDICTIONS_SHA256)
    validate_packet(packet, receipt, inputs, prior)
    truth, truth_bytes = read_json(Path(data_dir) / "truth.json", packet["truthSHA256"])
    rows = join_truth(packet, truth)
    require(truth["copyUnion"]["trainingDataReceiptSHA256"] == receipt["trainingDataReceiptSHA256"]
            and len(truth["copyUnion"]["affectedOpaqueIDs"]) == receipt["counts"]["copyUnionRows"], "Copy union receipt mismatch")
    raw = summarize(rows, packet["domain"]["allowedLabels"])
    kept = [r for r in rows if not r["copyReasons"]]
    no_copy = summarize(kept, packet["domain"]["allowedLabels"])
    screens = {"raw": fixed_screen(raw, raw=True), "inputCopyUnionExcluded": fixed_screen(no_copy, raw=False)}
    report = {"version": SCORE_VERSION, "fieldVersion": FIELD_VERSION, "modelVersion": MODEL_VERSION,
              "protocolSHA256": PROTOCOL_SHA256, "predictionsSHA256": predictions_sha256, "dataReceiptSHA256": data_receipt_sha256,
              "truthSHA256": packet["truthSHA256"], "codeSHA256": packet["codeSHA256"], "controlParity": packet["controlParity"],
              "raw": raw, "inputCopyUnionExcluded": no_copy, "fixedScreen": screens, "passesFixedScreen": all(v["passes"] for v in screens.values()),
              "copyUnion": truth["copyUnion"], "excludedCount": len(rows) - len(kept),
              "excludedOpaqueIDs": [r["opaqueID"] for r in rows if r["copyReasons"]], "rows": rows,
              "scope": "neutral-field-reused-public-UJI-eight-writers-and-original-HWRT-test-isolated-glyphs",
              "pooledAccuracyReported": False, "personalizationMeasured": False, "freshValidation": False,
              "liveRecognitionChanged": False, "productionEligible": False, "shippingRightsCleared": False}
    require(read_json(predictions, predictions_sha256)[1] == frozen and read_json(prior_predictions, PRIOR_PREDICTIONS_SHA256)[1] == prior_bytes
            and read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)[1] == receipt_bytes
            and read_json(Path(data_dir) / "truth.json", packet["truthSHA256"])[1] == truth_bytes
            and code_identity() == packet["codeSHA256"], "Scoring changed frozen inputs/code")
    return write_exclusive(output, report, (predictions, data_dir, prior_predictions))


def main():
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest="command", required=True)
    for command, names in (("predict", ("data", "data-receipt-sha256", "fit", "fit-receipt-sha256", "domain", "prior-predictions", "output")),
                           ("score", ("predictions", "predictions-sha256", "data", "data-receipt-sha256", "prior-predictions", "output"))):
        p = sub.add_parser(command)
        for name in names: p.add_argument("--" + name, required=True)
    a = vars(parser.parse_args()); command = a.pop("command")
    if command == "predict": predict(a.pop("data"), a.pop("fit"), a.pop("domain"), a.pop("prior_predictions"), a.pop("output"), **a)
    else: score(a.pop("predictions"), a.pop("data"), a.pop("prior_predictions"), a.pop("output"), **a)


if __name__ == "__main__":
    main()

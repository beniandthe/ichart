"""One frozen literal-source substitution; reused internal public glyphs only.

Baseline control vectors are reused exactly, never the prior 47-way candidate.
Both 102-way heads use the unchanged first-argmax legal projection.  Common
copy accounting reads hashes only; a separate authenticated score joins truth.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

import numpy as np
import torch

from ..contracts import canonical_json_bytes as canonical
from . import personal_domain_reject as core
from . import personal_domain_reject_evaluate as parent

require, sha, digest = parent.require, parent.sha, parent.digest
read_json, write_exclusive = parent.read_json, parent.write_exclusive
VERSION = "personal-same-label-transfer-predictions-v1"
SCORE_VERSION = "personal-same-label-transfer-score-v1"
COPY_VERSION = "personal-same-label-transfer-common-copy-union-v1"
MANIFEST_VERSION = "personal-same-label-transfer-input-manifest-v1"
PROTOCOL_SHA256 = "cbab15675ed16698c0a9cfb32f420df1ef54c80bd6054cd034b793f9ba713061"
PARENT_DATA_SHA256 = "d835b1e01ec21cdaac4f8882d8ef02309c3cd9960408b45fa17cc74a0b5023d5"
PARENT_FIT_SHA256 = "556dbc308fc778ce6273910301b13ab1652742a474ed1a0d000f1ec65ef90bdb"
BASELINE_SHA256 = "849c4bdd2e4ec57934fcf8eff3c8f948f5803bbeafbeb08671712f337aa4994d"
FINGERPRINT_VERSION = "personal-same-label-transfer-fit-fingerprints-v1"
FOLDS, BLIND_FIELDS, NATIVE = parent.FOLDS, parent.BLIND_FIELDS, parent.NATIVE
ARMS = ("control", "sameLabelTransfer")
QUERY_ROWS, EXPOSURES, DISTINCT_DRAWINGS = 3874, 7748, 6978


def code_identity():
    from . import personal_same_label_transfer_train as train
    return train.code_identity()


def validate_fit(fit, expected_sha):
    from . import personal_same_label_transfer_train as train
    train._validate_fit_receipt(fit, code_identity())
    require(sha(canonical(fit)) == expected_sha and fit["protocolSHA256"] == PROTOCOL_SHA256
            and fit["parentDataReceiptSHA256"] == PARENT_DATA_SHA256 and fit["parentFitReceiptSHA256"] == PARENT_FIT_SHA256,
            "Candidate/protocol/frozen-parent identity changed")
    return core.make_vocabulary(fit["sourceVocabulary"], fit["legalOldLabels"])


def validate_output(output, vocab):
    if output["failure"] is None:
        require(output == parent.result(output["embedding"], output["rawLogits"], "control", vocab),
                "Unchanged 102-way control decoder/vector/hash required")
    else:
        require(set(output) == set(parent.failed(ValueError())) and isinstance(output["failure"], str) and output["failure"]
                and all(v is None for k, v in output.items() if k != "failure"), "Complete failure row required")


def validate_baseline(baseline, receipt, inputs, vocab):
    require(baseline["version"] == parent.VERSION and baseline["protocolSHA256"] == parent.PROTOCOL_SHA256
            and baseline["fitReceiptSHA256"] == PARENT_FIT_SHA256 and sha(canonical(baseline["fitReceipt"])) == PARENT_FIT_SHA256
            and baseline["dataReceiptSHA256"] == PARENT_DATA_SHA256 and baseline["dataReceipt"] == receipt
            and baseline["codeSHA256"] == parent.code_identity() and baseline["vocabulary"] == list(vocab.source_labels)
            and baseline["allowedLabels"] == list(vocab.legal_labels) and set(baseline["folds"]) == set(FOLDS),
            "Frozen 102-control baseline source/model binding changed")
    ids = []
    for fold in FOLDS:
        parent.validate_inputs(inputs[fold], fold, vocab)
        rows = baseline["folds"][fold]["rows"]
        require(len(rows) == len(inputs[fold]["rows"]) == QUERY_ROWS, "Complete paired baseline required")
        for row, blind in zip(rows, inputs[fold]["rows"]):
            require(all(row[k] == blind[k] for k in BLIND_FIELDS), "Baseline/input ID or raster/geometry hash changed")
            validate_output(row["results"]["control"], vocab)  # Do not read the rejected 47-way result.
            ids.append(row["opaqueID"])
    require(len(ids) == EXPOSURES and len(set(ids)) == DISTINCT_DRAWINGS, "Shared-query exposure/drawing counts changed")


def merge_fingerprints(original, candidate, fold):
    require(set(candidate) == {"version", "fold", "rows"} and candidate["version"] == FINGERPRINT_VERSION
            and candidate["fold"] == fold and isinstance(candidate["rows"], list), "Candidate actual-fit fingerprint schema changed")
    combined, actual = {}, {}
    for row in (*original["rows"], *candidate["rows"]):
        require(set(row) == BLIND_FIELDS and all(digest(v) for v in row.values())
                and (row["opaqueID"] not in combined or combined[row["opaqueID"]] == row), "Label-free exact fitting identities required")
        combined[row["opaqueID"]] = row
    actual = {r["opaqueID"]: r for r in candidate["rows"]}
    require(len(actual) == len(candidate["rows"]) and all(actual.get(r["opaqueID"]) == r for r in original["rows"]),
            "All unchanged first-occurrence parent drawings must remain in fitting")
    return [combined[k] for k in sorted(combined)]


def load_common_fingerprints(data_dir, fit_dir, fold, receipt, fit):
    from . import personal_domain_reject_data as data
    original, loaded = data.load_fit_fingerprints(Path(data_dir), fold)
    require(loaded == receipt, "Parent source receipt changed")
    binding = fit["fitFingerprints"][fold]; relative = binding["path"]
    require(isinstance(relative, str) and not Path(relative).is_absolute() and ".." not in Path(relative).parts
            and digest(binding["sha256"]), "Bound safe fingerprint path required")
    candidate, payload = read_json(Path(fit_dir) / relative, binding["sha256"])
    return original, candidate, payload, merge_fingerprints(original, candidate, fold)


def common_union(query, fingerprints):
    return {**parent.copy_union(query, fingerprints), "version": COPY_VERSION}


def input_manifest(fit, fit_sha, receipt, baseline, unions):
    return {"version": MANIFEST_VERSION, "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": fit["codeSHA256"],
            "fitReceiptSHA256": fit_sha, "weights": fit["weights"], "finalStateSHA256": fit["finalStateSHA256"],
            "baselinePredictionsSHA256": BASELINE_SHA256, "parentDataReceiptSHA256": PARENT_DATA_SHA256,
            "parentFitReceiptSHA256": PARENT_FIT_SHA256,
            "baselineControlWeights": {f: baseline["fitReceipt"]["weights"][f]["control"] for f in FOLDS},
            "queryExposures": EXPOSURES, "distinctQueryDrawings": DISTINCT_DRAWINGS,
            "folds": {f: {"queryInputsSHA256": parent.artifact_sha(receipt, parent.fold_path(f, "query-inputs.json")),
                           "queryRastersSHA256": parent.artifact_sha(receipt, parent.fold_path(f, "query-rasters.npy")),
                           "baselineFitFingerprintsSHA256": parent.artifact_sha(receipt, parent.fold_path(f, "fit-fingerprints.json")),
                           "candidateFitFingerprintsSHA256": fit["fitFingerprints"][f]["sha256"], "copyUnion": unions[f]} for f in FOLDS}}


def manifest_path(predictions, packet):
    expected = Path(predictions).stem + "-input-manifest.json"
    require(packet["inputManifestPath"] == expected, "Strict sibling pre-inference manifest filename required")
    return Path(predictions).with_name(expected)


def freeze_forward(model, rasters, inputs, vocab, baseline_rows, batch_size=128):
    require(not model.training and all(not m.training for m in model.modules())
            and all(p.device.type == "cpu" for p in model.parameters()), "Final CPU/eval candidate required")
    rows = [{**r, "results": {"control": old["results"]["control"]}} for r, old in zip(inputs["rows"], baseline_rows)]
    require(len(rows) == len(rasters) == len(baseline_rows), "Complete paired raster/baseline inputs required")
    with torch.inference_mode():
        for start in range(0, len(rows), batch_size):
            batch = torch.from_numpy(np.asarray(rasters[start:start + batch_size]).copy())
            require(batch.dtype == torch.float32 and tuple(batch.shape[1:]) == (1, 96, 256) and torch.isfinite(batch).all(), "Finite source raster batch required")
            for offset, raster in enumerate(batch.numpy()):
                pixels = np.rint(raster[0] * np.float32(255)).astype(np.uint8)
                require(np.array_equal(raster[0], pixels.astype(np.float32) / np.float32(255))
                        and sha(pixels.tobytes()) == rows[start + offset]["rasterSHA256"], "Unchanged source raster identity required")
            try:
                features, logits = model(batch)
                require(features.shape == (len(batch), 128) and logits.shape == (len(batch), 102), "Complete candidate102/128 output required")
                for offset, (e, l) in enumerate(zip(features.cpu().tolist(), logits.cpu().tolist())):
                    try: output = parent.result(e, l, "control", vocab)
                    except (ValueError, RuntimeError, FloatingPointError) as error: output = parent.failed(error)
                    rows[start + offset]["results"][ARMS[1]] = output
            except (ValueError, RuntimeError, FloatingPointError) as error:
                for row in rows[start:start + len(batch)]: row["results"][ARMS[1]] = parent.failed(error)
    return rows


def predict(data_dir, fit_dir, baseline_predictions, output, *, fit_receipt_sha256):
    from . import personal_domain_reject_data as data, personal_same_label_transfer_train as train
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    models, fit = train.load_fitted_models(Path(fit_dir), fit_receipt_sha256)  # Both final candidates BEFORE blind queries.
    vocab = validate_fit(fit, fit_receipt_sha256)
    require(set(models) == set(FOLDS), "Both final model folds required")
    receipt, receipt_bytes = read_json(Path(data_dir) / "data-receipt.json", PARENT_DATA_SHA256)
    data._validate_receipt(receipt)
    baseline, baseline_bytes = read_json(baseline_predictions, BASELINE_SHA256)
    prepared, inputs, unions = {}, {}, {}
    for fold in FOLDS:
        rasters, inputs[fold], loaded = data.load_query(Path(data_dir), fold)
        require(loaded == receipt, "Parent blind input lineage changed")
        original, candidate, fingerprint_bytes, merged = load_common_fingerprints(data_dir, fit_dir, fold, receipt, fit)
        unions[fold] = common_union(inputs[fold]["rows"], merged)  # Both actual fitting sets; no query truth.
        prepared[fold] = (rasters, original, candidate, fingerprint_bytes)
    validate_baseline(baseline, receipt, inputs, vocab)
    states = {f: train.state_digest(models[f].state_dict()) for f in FOLDS}
    require(states == fit["finalStateSHA256"], "Final candidate state binding changed")
    require(not Path(output).exists(), "Exclusive new prediction output required")
    manifest_path = Path(output).with_name(Path(output).stem + "-input-manifest.json")
    manifest = input_manifest(fit, fit_receipt_sha256, receipt, baseline, unions)
    manifest_sha = write_exclusive(manifest_path, manifest, (data_dir, fit_dir, baseline_predictions))  # BEFORE first forward.
    folds = {}
    for fold in FOLDS:
        rows = freeze_forward(models[fold], prepared[fold][0], inputs[fold], vocab, baseline["folds"][fold]["rows"])
        folds[fold] = {"copyUnion": unions[fold], "candidateFitFingerprints": prepared[fold][2], "rows": rows}
        _, after, loaded = data.load_query(Path(data_dir), fold)
        original, candidate, payload, _ = load_common_fingerprints(data_dir, fit_dir, fold, receipt, fit)
        require(after == inputs[fold] and loaded == receipt and (original, candidate, payload) == prepared[fold][1:], "Query/fitting hash sources changed")
    require(states == {f: train.state_digest(models[f].state_dict()) for f in FOLDS}, "Inference changed candidate/BN state")
    _, after_fit = train.load_fitted_models(Path(fit_dir), fit_receipt_sha256)
    require(after_fit == fit and read_json(Path(data_dir) / "data-receipt.json", PARENT_DATA_SHA256)[1] == receipt_bytes
            and read_json(baseline_predictions, BASELINE_SHA256)[1] == baseline_bytes and code_identity() == fit["codeSHA256"]
            and read_json(manifest_path, manifest_sha)[0] == manifest, "Frozen models/sources/code changed")
    packet = {"version": VERSION, "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": fit["codeSHA256"],
              "fitReceiptSHA256": fit_receipt_sha256, "fitReceipt": fit, "baselinePredictionsSHA256": BASELINE_SHA256,
              "parentDataReceiptSHA256": PARENT_DATA_SHA256, "parentFitReceiptSHA256": PARENT_FIT_SHA256,
              "weights": fit["weights"], "finalStateSHA256": states, "sourceVocabulary": list(vocab.source_labels),
              "legalLabels": list(vocab.legal_labels), "folds": folds, "queryExposures": EXPOSURES, "distinctQueryDrawings": DISTINCT_DRAWINGS,
              "inputManifestPath": manifest_path.name, "inputManifestSHA256": manifest_sha,
              "scope": "reused-public-internal-writer-blocked-literal-source-transfer-only", "freshValidation": False,
              "personalizationMeasured": False, "naturalChordAccuracyMeasured": False, "productionEligible": False, "liveRecognitionChanged": False}
    return write_exclusive(output, packet, (data_dir, fit_dir, baseline_predictions))


def validate_packet(packet, receipt, baseline, inputs, originals):
    vocab = validate_fit(packet["fitReceipt"], packet["fitReceiptSHA256"])
    validate_baseline(baseline, receipt, inputs, vocab)
    require(packet["version"] == VERSION and packet["protocolSHA256"] == PROTOCOL_SHA256 and packet["codeSHA256"] == code_identity()
            and packet["parentDataReceiptSHA256"] == PARENT_DATA_SHA256 and packet["parentFitReceiptSHA256"] == PARENT_FIT_SHA256
            and packet["baselinePredictionsSHA256"] == BASELINE_SHA256 and packet["sourceVocabulary"] == list(vocab.source_labels)
            and packet["legalLabels"] == list(vocab.legal_labels) and packet["weights"] == packet["fitReceipt"]["weights"]
            and packet["finalStateSHA256"] == packet["fitReceipt"]["finalStateSHA256"]
            and packet["queryExposures"] == EXPOSURES and packet["distinctQueryDrawings"] == DISTINCT_DRAWINGS
            and set(packet["folds"]) == set(FOLDS), "New prediction/model/source binding changed")
    for fold in FOLDS:
        value = packet["folds"][fold]; candidate = value["candidateFitFingerprints"]
        binding = packet["fitReceipt"]["fitFingerprints"][fold]
        require(sha(canonical(candidate)) == binding["sha256"] and candidate["version"] == FINGERPRINT_VERSION and candidate["fold"] == fold,
                "Actual candidate fitting fingerprint commitment changed")
        fingerprints = merge_fingerprints(originals[fold], candidate, fold)
        require(value["copyUnion"] == common_union(inputs[fold]["rows"], fingerprints)
                and len(value["rows"]) == QUERY_ROWS, "Common paired copy union/denominator changed")
        for row, blind, old in zip(value["rows"], inputs[fold]["rows"], baseline["folds"][fold]["rows"]):
            require(set(row) == BLIND_FIELDS | {"results"} and all(row[k] == blind[k] for k in BLIND_FIELDS)
                    and set(row["results"]) == set(ARMS) and row["results"]["control"] == old["results"]["control"], "Baseline must remain exact on identical inputs")
            for output in row["results"].values(): validate_output(output, vocab)
    return vocab


def summarize(rows):
    states = [(parent.state(r, ARMS[0]), parent.state(r, ARMS[1])) for r in rows]
    transitions = Counter(f"{a}->{b}" for a, b in states)
    counts = {arm: {s: sum(parent.state(r, arm) == s for r in rows) for s in ("correct", "wrongLegal", "unresolved")} for arm in ARMS}
    return {"count": len(rows), "arms": counts, "acceptedCoverage": {a: counts[a]["correct"] + counts[a]["wrongLegal"] for a in ARMS},
            "gains": sum(a != "correct" and b == "correct" for a, b in states), "lostCorrectReads": sum(a == "correct" and b != "correct" for a, b in states),
            "newCorrectOrUnresolvedToWrongLegal": sum(a in ("correct", "unresolved") and b == "wrongLegal" for a, b in states),
            "transitions": {f"{a}->{b}": transitions[f"{a}->{b}"] for a in ("correct", "wrongLegal", "unresolved") for b in ("correct", "wrongLegal", "unresolved")},
            "invalid": {a: sum(r["results"][a]["failure"] is not None for r in rows) for a in ARMS}}


def view(rows, writers, vocab):
    uji = [r for r in rows if r["source"] == "uji"]; hwrt = [r for r in rows if r["source"] == "hwrt"]
    return {"safety": {k: v for k, v in summarize(rows).items() if k in ("invalid", "newCorrectOrUnresolvedToWrongLegal")},
            "uji": summarize(uji), "ujiLegal": summarize([r for r in uji if r["label"] in vocab.legal_labels]),
            "ujiForbidden": summarize([r for r in uji if r["label"] not in vocab.legal_labels]), "hwrt": summarize(hwrt),
            "writers": {w: summarize([r for r in uji if r["writer"] == w]) for w in writers},
            "classes": {label: summarize([r for r in uji if r["label"] == label]) for label in vocab.source_labels[:97]},
            "mappedClasses": {label: summarize([r for r in hwrt if r["label"] == label]) for label in core.NOVEL_LEGAL_LABELS},
            "nativeIDs": {native: summarize([r for r in hwrt if r["nativeSymbolID"] == native]) for native in NATIVE}}


def fixed_screen(value):
    def correct(summary, arm): return summary["arms"][arm]["correct"]
    checks = {"completeFiniteOutputs": not any(value["safety"]["invalid"].values()),
              "strictlyMoreCorrectLegalUJI": correct(value["ujiLegal"], ARMS[1]) > correct(value["ujiLegal"], ARMS[0]),
              "fewerTotalWrongLegalUJI": value["uji"]["arms"][ARMS[1]]["wrongLegal"] < value["uji"]["arms"][ARMS[0]]["wrongLegal"],
              "everyQueryWriterCorrectNonWorse": all(correct(v, ARMS[1]) >= correct(v, ARMS[0]) for v in value["writers"].values()),
              "zeroNewCorrectOrUnresolvedToWrongLegal": value["safety"]["newCorrectOrUnresolvedToWrongLegal"] == 0,
              "everyMappedHWRTClassCorrectNonWorse": all(correct(v, ARMS[1]) >= correct(v, ARMS[0]) for v in value["mappedClasses"].values())}
    return {"checks": checks, "passes": all(checks.values())}


def join_truth(fold, frozen, truth, vocab, original_fingerprints):
    original_union = parent.copy_union([{k: r[k] for k in BLIND_FIELDS} for r in frozen["rows"]], original_fingerprints["rows"])
    original = {"rows": frozen["rows"], "copyUnion": original_union}
    rows, writers = parent.join_truth(fold, original, truth, vocab)  # Validates only source identities, not arm scores.
    common = {r["opaqueID"]: r["reasons"] for r in frozen["copyUnion"]["rows"]}
    return [{**r, "copyReasons": common[r["opaqueID"]]} for r in rows], writers


def score(predictions, data_dir, baseline_predictions, output, *, predictions_sha256):
    from . import personal_domain_reject_data as data
    packet, payload = read_json(predictions, predictions_sha256)  # BEFORE truth access.
    receipt, _ = read_json(Path(data_dir) / "data-receipt.json", PARENT_DATA_SHA256); data._validate_receipt(receipt)
    baseline, _ = read_json(baseline_predictions, BASELINE_SHA256)
    inputs, originals = {}, {}
    for fold in FOLDS:
        inputs[fold], _ = read_json(Path(data_dir) / parent.fold_path(fold, "query-inputs.json"), parent.artifact_sha(receipt, parent.fold_path(fold, "query-inputs.json")))
        originals[fold], loaded = data.load_fit_fingerprints(Path(data_dir), fold); require(loaded == receipt, "Parent fingerprint receipt changed")
    vocab = validate_packet(packet, receipt, baseline, inputs, originals)
    frozen_manifest_path = manifest_path(predictions, packet)
    manifest, manifest_bytes = read_json(frozen_manifest_path, packet["inputManifestSHA256"])
    require(manifest == input_manifest(packet["fitReceipt"], packet["fitReceiptSHA256"], receipt, baseline,
            {f: packet["folds"][f]["copyUnion"] for f in FOLDS}), "Pre-inference common-union/model/source commitment changed")
    folds, joined = {}, {}
    for fold in FOLDS:
        truth, _ = read_json(Path(data_dir) / parent.fold_path(fold, "query-truth.json"), parent.artifact_sha(receipt, parent.fold_path(fold, "query-truth.json")))
        rows, writers = join_truth(fold, packet["folds"][fold], truth, vocab, originals[fold]); joined[fold] = rows
        views = {"raw": view(rows, writers, vocab), "commonNoCopy": view([r for r in rows if not r["copyReasons"]], writers, vocab)}
        folds[fold] = {"views": views, "fixedScreens": {name: fixed_screen(v) for name, v in views.items()}, "copyUnion": packet["folds"][fold]["copyUnion"], "rows": rows}
    uji = [{r["opaqueID"] for r in joined[f] if r["source"] == "uji"} for f in FOLDS]
    hwrt = [{r["opaqueID"]: {k: r[k] for k in ("label", "nativeSymbolID", *parent.HASH_FIELDS)} for r in joined[f] if r["source"] == "hwrt"} for f in FOLDS]
    require(not uji[0] & uji[1] and hwrt[0] == hwrt[1], "Disjoint writer folds and identical shared HWRT cohort required")
    require(read_json(predictions, predictions_sha256)[1] == payload and read_json(baseline_predictions, BASELINE_SHA256)[0] == baseline
            and read_json(Path(data_dir) / "data-receipt.json", PARENT_DATA_SHA256)[0] == receipt and code_identity() == packet["codeSHA256"], "Frozen bytes/code changed during score")
    require(read_json(frozen_manifest_path, packet["inputManifestSHA256"])[1] == manifest_bytes, "Pre-inference manifest changed during score")
    report = {"version": SCORE_VERSION, "protocolSHA256": PROTOCOL_SHA256, "predictionsSHA256": predictions_sha256,
              "baselinePredictionsSHA256": BASELINE_SHA256, "fitReceiptSHA256": packet["fitReceiptSHA256"], "codeSHA256": packet["codeSHA256"],
              "inputManifestSHA256": packet["inputManifestSHA256"],
              "folds": folds, "queryExposures": EXPOSURES, "distinctQueryDrawings": DISTINCT_DRAWINGS, "sourcesPooled": False,
              "passesFixedScreen": all(s["passes"] for f in folds.values() for s in f["fixedScreens"].values()),
              "freshValidation": False, "personalizationMeasured": False, "naturalChordAccuracyMeasured": False, "productionEligible": False}
    return write_exclusive(output, report, (predictions, data_dir, baseline_predictions))


def main():
    parser = argparse.ArgumentParser(description=__doc__); commands = parser.add_subparsers(dest="command", required=True)
    for name in ("predict", "score"):
        command = commands.add_parser(name); command.add_argument("--data", required=True); command.add_argument("--baseline-predictions", required=True); command.add_argument("--output", required=True)
        if name == "predict": command.add_argument("--fit", required=True); command.add_argument("--fit-receipt-sha256", required=True)
        else: command.add_argument("--predictions", required=True); command.add_argument("--predictions-sha256", required=True)
    args = parser.parse_args()
    if args.command == "predict": print(predict(args.data, args.fit, args.baseline_predictions, args.output, fit_receipt_sha256=args.fit_receipt_sha256))
    else: print(score(args.predictions, args.data, args.baseline_predictions, args.output, predictions_sha256=args.predictions_sha256))


if __name__ == "__main__":
    main()

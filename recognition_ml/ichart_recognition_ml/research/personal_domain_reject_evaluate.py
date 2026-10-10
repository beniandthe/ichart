"""Frozen 102-vs-47 internal-fold predictions, then separate domain scoring.

Prediction sees only raster inputs and label-free fit fingerprints.  REJECT
and ties are unresolved, never correct text.  These reused public fragments
are neither fresh validation nor a personalization/app-promotion experiment.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import platform

import numpy as np
import torch

from ..contracts import canonical_json_bytes as canonical
from .personal_hwrt_stroke_evaluate import require, sha, digest, read_json, write_exclusive, vector_sha, failure
from . import personal_domain_reject as core

VERSION = "personal-domain-reject-predictions-v1"
SCORE_VERSION = "personal-domain-reject-score-v1"
COPY_VERSION = "personal-domain-reject-copy-union-v1"
INPUT_VERSION = "personal-domain-reject-query-inputs-v1"
TRUTH_VERSION = "personal-domain-reject-query-truth-v1"
FIT_VERSION = "personal-domain-reject-fit-v1"
DATA_VERSION = "personal-domain-reject-data-v1"
PROTOCOL_SHA256 = "790ffda2fd09500a57f09da3f3dde3d18cfb8d8ad12c55b4850dbb97de43c552"
DOMAIN_SHA256 = "5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010"
FOLDS = ("A16-to-B16", "B16-to-A16")
ARMS = core.ARMS
QUERY_ROWS, FIT_ROWS, EXPOSURES, DISTINCT_DRAWINGS = 3874, 6199, 7748, 6978
HASH_FIELDS = ("rasterSHA256", "normalizedGeometrySHA256")
BLIND_FIELDS = {"opaqueID", *HASH_FIELDS}
NATIVE = {"196": "+", "922": "/", "266": "#", "948": "#", "950": "ø",
          "959": "△", "977": "△", "152": "△"}


def code_identity():
    from . import personal_domain_reject_train as train
    return train.code_identity()


def artifact_sha(receipt, name):
    value = receipt["artifacts"][name]
    result = value if isinstance(value, str) else value.get("sha256", value.get("SHA256"))
    require(digest(result), "Bound artifact digest required")
    return result


def fold_path(fold, name):
    require(fold in FOLDS, "Unknown fold")
    return f"folds/{fold}/{name}"


def vocabulary(receipt):
    labels, old = receipt["sourceVocabulary"], receipt["legalOldLabels"]
    require(isinstance(labels, list) and len(labels) == len(set(labels)) == 102
            and labels[:97] == sorted(labels[:97]) and tuple(labels[97:]) == core.NOVEL_LEGAL_LABELS,
            "Exact ordered 97+5 source labels required")
    vocab = core.make_vocabulary(labels, old)
    require(receipt["candidateLabels"] == list(vocab.candidate_labels),
            "Exact 46 legal plus internal REJECT output identities required")
    return vocab


def validate_inputs(inputs, fold, vocab):
    require(set(inputs) == {"version", "fold", "vocabulary", "rows"} and inputs["version"] == INPUT_VERSION
            and inputs["fold"] == fold and inputs["vocabulary"] == list(vocab.source_labels), "Blind fold schema changed")
    rows = inputs["rows"]
    require(isinstance(rows, list) and len(rows) == QUERY_ROWS and all(isinstance(r, dict) and set(r) == BLIND_FIELDS
            and all(digest(v) for v in r.values()) for r in rows)
            and len({r["opaqueID"] for r in rows}) == QUERY_ROWS, "3874 unique hashes-only query rows required")


def copy_union(query_rows, fit_rows):
    """Source-only, own-fold fit overlaps and within-query duplicate union."""
    require(all(isinstance(r, dict) and set(r) == BLIND_FIELDS and all(digest(v) for v in r.values())
                for r in (*query_rows, *fit_rows))
            and len({r["opaqueID"] for r in fit_rows}) == len(fit_rows), "Label-free fingerprints required")
    reasons = {r["opaqueID"]: set() for r in query_rows}
    for field in HASH_FIELDS:
        fit_hashes = {r[field] for r in fit_rows}
        representatives = {}
        for row in query_rows:
            representatives[row[field]] = min(row["opaqueID"], representatives.get(row[field], row["opaqueID"]))
        for row in query_rows:
            if row[field] in fit_hashes:
                reasons[row["opaqueID"]].add(f"fit-{field}")
            if row["opaqueID"] != representatives[row[field]]:
                reasons[row["opaqueID"]].add(f"repeated-query-{field}")
    rows = [{"opaqueID": r["opaqueID"], "reasons": sorted(reasons[r["opaqueID"]])} for r in query_rows]
    return {"version": COPY_VERSION, "hashFields": list(HASH_FIELDS), "fitRows": len(fit_rows), "queryRows": len(query_rows),
            "representativeRule": "lexicographically-smallest-opaqueID-per-query-hash",
            "rows": rows, "affectedOpaqueIDs": sorted(k for k, v in reasons.items() if v),
            "reasonCounts": dict(sorted(Counter(reason for r in rows for reason in r["reasons"]).items()))}


def result(embedding, logits, arm, vocab):
    width = 102 if arm == ARMS[0] else 47
    require(arm in ARMS and isinstance(embedding, list) and len(embedding) == 128
            and isinstance(logits, list) and len(logits) == width
            and all(type(v) in (int, float) for v in (*embedding, *logits))
            and np.isfinite(embedding).all() and np.isfinite(logits).all()
            and abs(float(np.sqrt(np.einsum('d,d->', embedding, embedding, optimize=False))) - 1) <= 2e-5,
            "Complete finite 128-dimensional unit feature and logits required")
    labels = vocab.source_labels if arm == ARMS[0] else vocab.candidate_labels
    maximum = max(logits); winners = [i for i, value in enumerate(logits) if value == maximum]
    raw = labels[winners[0]]
    projected = raw if raw in vocab.legal_labels and (arm == ARMS[0] or len(winners) == 1) else None
    return {"failure": None, "embedding": embedding, "rawLogits": logits, "rawTop1": raw,
            "domainTop1": projected, "maximumTied": len(winners) != 1,
            "embeddingSHA256": vector_sha(embedding), "logitsSHA256": vector_sha(logits)}


def failed(error):
    return {**failure(error), "maximumTied": None}


def freeze_forward(models, rasters, inputs, vocab, batch_size=128):
    require(set(models) == set(ARMS) and all(not m.training and all(not c.training for c in m.modules())
            and all(p.device.type == "cpu" for p in m.parameters()) for m in models.values()), "Both CPU eval arms required")
    rows = [{**r, "results": {}} for r in inputs["rows"]]
    require(len(rasters) == len(rows), "Missing raster rows")
    with torch.inference_mode():
        for start in range(0, len(rows), batch_size):
            batch = torch.from_numpy(np.asarray(rasters[start:start + batch_size]).copy())
            require(batch.dtype == torch.float32 and tuple(batch.shape[1:]) == (1, 96, 256)
                    and torch.isfinite(batch).all(), "Finite unchanged Float32 raster inputs required")
            for offset, raster in enumerate(batch.numpy()):
                pixels = np.rint(raster[0] * np.float32(255)).astype(np.uint8)
                require(np.array_equal(raster[0], pixels.astype(np.float32) / np.float32(255))
                        and sha(pixels.tobytes()) == rows[start + offset]["rasterSHA256"], "Raster identity changed")
            for arm in ARMS:
                try:
                    features, logits = models[arm](batch)
                    require(features.shape == (len(batch), 128) and logits.shape == (len(batch), 102 if arm == ARMS[0] else 47),
                            "Complete arm output dimensions required")
                    for offset, (e, l) in enumerate(zip(features.cpu().tolist(), logits.cpu().tolist())):
                        try:
                            rows[start + offset]["results"][arm] = result(e, l, arm, vocab)
                        except (ValueError, RuntimeError, FloatingPointError) as error:
                            rows[start + offset]["results"][arm] = failed(error)
                except (ValueError, RuntimeError, FloatingPointError) as error:
                    for row in rows[start:start + len(batch)]:
                        row["results"][arm] = failed(error)
    return rows


def validate_receipts(receipt, fit, data_sha, fit_sha):
    from . import personal_domain_reject_data as data, personal_domain_reject_train as train
    data._validate_receipt(receipt); train._validate_fit_receipt(fit, code_identity())
    require(receipt["version"] == DATA_VERSION and fit["version"] == FIT_VERSION
            and receipt["protocolSHA256"] == fit["protocolSHA256"] == PROTOCOL_SHA256
            and receipt["codeSHA256"] == data.code_identity() and fit["codeSHA256"] == code_identity()
            and sha(canonical(receipt)) == data_sha and sha(canonical(fit)) == fit_sha
            and fit["dataReceiptSHA256"] == data_sha and fit["modelVersion"] == core.MODEL_VERSION,
            "New data/final-fit/code/protocol identities required")
    vocab = vocabulary(fit)
    require(all(receipt[k] == fit[k] for k in ("sourceVocabulary", "legalOldLabels", "candidateLabels"))
            and receipt["domain"]["sha256"] == DOMAIN_SHA256,
            "Prepared source/domain vocabulary changed")
    return vocab


def load_blind(data_dir, fold, receipt, vocab):
    from . import personal_domain_reject_data as data
    rasters, inputs, loaded = data.load_query(Path(data_dir), fold)
    require(loaded == receipt, "Data receipt changed")
    validate_inputs(inputs, fold, vocab)
    name = fold_path(fold, "fit-fingerprints.json")
    fingerprints, payload = read_json(Path(data_dir) / name, artifact_sha(receipt, name))
    require(set(fingerprints) == {"version", "fold", "rows"} and fingerprints["version"] == "personal-domain-reject-fit-fingerprints-v1"
            and fingerprints["fold"] == fold and len(fingerprints["rows"]) == FIT_ROWS, "6199 own-fold safe fingerprints required")
    return rasters, inputs, fingerprints, payload


def predict(data_dir, fit_dir, output, *, data_receipt_sha256, fit_receipt_sha256):
    from . import personal_domain_reject_train as train
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    models, fit = train.load_fitted_models(Path(fit_dir), fit_receipt_sha256)  # BOTH folds final before query access.
    receipt, receipt_bytes = read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)
    vocab = validate_receipts(receipt, fit, data_receipt_sha256, fit_receipt_sha256)
    require(set(models) == set(FOLDS), "Both complete model folds required")
    states = {fold: {arm: train.state_digest(model.state_dict()) for arm, model in models[fold].items()} for fold in FOLDS}
    require(states == fit["finalStateSHA256"], "Loaded state commitment changed")
    prepared = {fold: load_blind(data_dir, fold, receipt, vocab) for fold in FOLDS}
    ids = [r["opaqueID"] for _, inputs, _, _ in prepared.values() for r in inputs["rows"]]
    require(len(ids) == EXPOSURES and len(set(ids)) == DISTINCT_DRAWINGS, "7748 exposures/6978 drawings required; shared HWRT is not independent")
    unions = {fold: copy_union(prepared[fold][1]["rows"], prepared[fold][2]["rows"]) for fold in FOLDS}
    folds = {}
    for fold in FOLDS:
        rasters, inputs, fingerprints, fingerprint_bytes = prepared[fold]
        rows = freeze_forward(models[fold], rasters, inputs, vocab)
        _, after_inputs, after_fingerprints, after_bytes = load_blind(data_dir, fold, receipt, vocab)
        require(inputs == after_inputs and fingerprints == after_fingerprints and fingerprint_bytes == after_bytes,
                "Query/fingerprint bytes changed during inference")
        folds[fold] = {"copyUnion": unions[fold], "rows": rows}
    require(states == {f: {a: train.state_digest(m.state_dict()) for a, m in models[f].items()} for f in FOLDS},
            "Inference mutated model/BN states")
    _, fit_after = train.load_fitted_models(Path(fit_dir), fit_receipt_sha256)
    require(fit_after == fit and read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)[1] == receipt_bytes
            and code_identity() == fit["codeSHA256"], "Frozen inputs/code/final weights changed")
    packet = {"version": VERSION, "protocolSHA256": PROTOCOL_SHA256, "modelVersion": core.MODEL_VERSION,
              "codeSHA256": fit["codeSHA256"], "fitReceiptSHA256": fit_receipt_sha256, "fitReceipt": fit,
              "dataReceiptSHA256": data_receipt_sha256, "dataReceipt": receipt,
              "weights": fit["weights"], "finalStateSHA256": states,
              "vocabulary": list(vocab.source_labels), "allowedLabels": list(vocab.legal_labels),
              "candidateVocabulary": list(vocab.candidate_labels), "folds": folds,
              "queryExposures": EXPOSURES, "distinctQueryDrawings": DISTINCT_DRAWINGS,
              "runtime": {"python": platform.python_version(), "numpy": str(np.__version__), "torch": str(torch.__version__),
                          "cpuThreads": 4, "deterministicAlgorithms": True, "batchNormalizationUpdates": 0},
              "scope": "reused-public-internal-writer-blocked-glyph-fragments-only",
              "freshValidation": False, "personalizationPerformed": False, "privateInkUsed": False,
              "reservedWriterInferencePerformed": False, "liveRecognitionChanged": False, "productionEligible": False}
    return write_exclusive(output, packet, (data_dir, fit_dir))


def validate_packet(packet, receipt, inputs, fingerprints, data_sha):
    vocab = validate_receipts(receipt, packet["fitReceipt"], data_sha, packet["fitReceiptSHA256"])
    require(packet["version"] == VERSION and packet["protocolSHA256"] == PROTOCOL_SHA256 and packet["modelVersion"] == core.MODEL_VERSION
            and packet["dataReceipt"] == receipt and packet["dataReceiptSHA256"] == data_sha
            and packet["codeSHA256"] == packet["fitReceipt"]["codeSHA256"]
            and packet["weights"] == packet["fitReceipt"]["weights"]
            and packet["finalStateSHA256"] == packet["fitReceipt"]["finalStateSHA256"]
            and packet["vocabulary"] == list(vocab.source_labels) and packet["allowedLabels"] == list(vocab.legal_labels)
            and packet["candidateVocabulary"] == list(vocab.candidate_labels) and set(packet["folds"]) == set(FOLDS), "Prediction binding changed")
    ids = []
    for fold in FOLDS:
        validate_inputs(inputs[fold], fold, vocab)
        value = packet["folds"][fold]
        require(set(value) == {"copyUnion", "rows"} and value["copyUnion"] == copy_union(inputs[fold]["rows"], fingerprints[fold]["rows"])
                and len(value["rows"]) == QUERY_ROWS, "Missing rows or source-only copy union changed")
        for row, blind in zip(value["rows"], inputs[fold]["rows"]):
            require(set(row) == BLIND_FIELDS | {"results"} and {k: row[k] for k in BLIND_FIELDS} == blind
                    and set(row["results"]) == set(ARMS), "Paired blind row order/bindings changed")
            ids.append(row["opaqueID"])
            for arm, output in row["results"].items():
                if output["failure"] is None:
                    require(output == result(output["embedding"], output["rawLogits"], arm, vocab), "Numeric vectors/actual-top projection changed")
                else:
                    require(set(output) == set(failed(ValueError())) and isinstance(output["failure"], str) and output["failure"]
                            and all(v is None for k, v in output.items() if k != "failure"), "Failure must retain the full row")
    require(packet["queryExposures"] == len(ids) == EXPOSURES and packet["distinctQueryDrawings"] == len(set(ids)) == DISTINCT_DRAWINGS,
            "Cross-fold drawing/exposure commitments changed")
    return vocab


def state(row, arm):
    label = row["results"][arm]["domainTop1"]
    return "unresolved" if label is None else "correct" if label == row["label"] else "wrongLegal"


def summarize(rows):
    states = [(state(r, ARMS[0]), state(r, ARMS[1])) for r in rows]
    transitions = Counter(f"{a}->{b}" for a, b in states)
    counts = {arm: {s: sum(state(r, arm) == s for r in rows) for s in ("correct", "wrongLegal", "unresolved")} for arm in ARMS}
    return {"count": len(rows), "arms": counts, "acceptedCoverage": {a: counts[a]["correct"] + counts[a]["wrongLegal"] for a in ARMS},
            "gains": sum(a != "correct" and b == "correct" for a, b in states),
            "lostCorrectReads": sum(a == "correct" and b != "correct" for a, b in states),
            "newCorrectOrUnresolvedToWrongLegal": sum(a in ("correct", "unresolved") and b == "wrongLegal" for a, b in states),
            "transitions": {f"{a}->{b}": transitions[f"{a}->{b}"] for a in ("correct", "wrongLegal", "unresolved") for b in ("correct", "wrongLegal", "unresolved")},
            "invalid": {a: sum(r["results"][a]["failure"] is not None for r in rows) for a in ARMS}}


def view(rows, writers, legal):
    uji = [r for r in rows if r["source"] == "uji"]; hwrt = [r for r in rows if r["source"] == "hwrt"]
    safety = {"invalid": {a: sum(r["results"][a]["failure"] is not None for r in rows) for a in ARMS},
              "newCorrectOrUnresolvedToWrongLegal": sum(state(r, ARMS[0]) in ("correct", "unresolved")
                  and state(r, ARMS[1]) == "wrongLegal" for r in rows)}
    return {"safety": safety, "uji": summarize(uji), "ujiLegal": summarize([r for r in uji if r["label"] in legal]),
            "ujiForbidden": summarize([r for r in uji if r["label"] not in legal]), "hwrt": summarize(hwrt),
            "writers": {w: summarize([r for r in uji if r["writer"] == w]) for w in writers},
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


def join_truth(fold, frozen, truth, vocab):
    require(set(truth) == {"version", "fold", "rows", "copyUnion"} and truth["version"] == TRUTH_VERSION and truth["fold"] == fold
            and len(truth["rows"]) == len(frozen["rows"]) == QUERY_ROWS
            and truth["copyUnion"] == {k: v for k, v in frozen["copyUnion"].items() if k != "rows"}, "New complete truth/source-only copy union required")
    reasons = {r["opaqueID"]: r["reasons"] for r in frozen["copyUnion"]["rows"]}
    rows = []
    for blind, labeled in zip(frozen["rows"], truth["rows"]):
        require(set(labeled) == BLIND_FIELDS | {"label", "source", "writer", "session", "nativeSymbolID", "copyReasons"}
                and all(labeled[k] == blind[k] for k in BLIND_FIELDS) and labeled["label"] in vocab.source_labels
                and labeled["copyReasons"] == reasons[blind["opaqueID"]], "Paired exact truth identities/copy masks required")
        if labeled["source"] == "uji":
            require(isinstance(labeled["writer"], str) and labeled["writer"] and type(labeled["session"]) is int
                    and labeled["session"] in (1, 2) and labeled["nativeSymbolID"] is None and labeled["label"] in vocab.source_labels[:97], "Invalid UJI role")
        else:
            require(labeled["source"] == "hwrt" and labeled["writer"] is None and labeled["session"] is None
                    and labeled["nativeSymbolID"] in NATIVE and NATIVE[labeled["nativeSymbolID"]] == labeled["label"], "Invalid native alias or source")
        rows.append({**blind, **labeled, "copyReasons": reasons[blind["opaqueID"]]})
    uji = [r for r in rows if r["source"] == "uji"]; hwrt = [r for r in rows if r["source"] == "hwrt"]
    writers = sorted({r["writer"] for r in uji})
    require(len(uji) == 3104 and len(hwrt) == 770 and len(writers) == 16
            and len({(r["writer"], r["session"], r["label"]) for r in uji}) == 3104
            and set(r["nativeSymbolID"] for r in hwrt) == set(NATIVE), "Complete 16-writer/97-label/two-session grid plus eight native IDs required")
    return rows, writers


def score(predictions, data_dir, output, *, predictions_sha256, data_receipt_sha256):
    packet, payload = read_json(predictions, predictions_sha256)  # Authentication BEFORE any truth access.
    receipt, receipt_bytes = read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)
    inputs, fingerprints = {}, {}
    for fold in FOLDS:
        inputs[fold], _ = read_json(Path(data_dir) / fold_path(fold, "query-inputs.json"), artifact_sha(receipt, fold_path(fold, "query-inputs.json")))
        fingerprints[fold], _ = read_json(Path(data_dir) / fold_path(fold, "fit-fingerprints.json"), artifact_sha(receipt, fold_path(fold, "fit-fingerprints.json")))
    vocab = validate_packet(packet, receipt, inputs, fingerprints, data_receipt_sha256)
    folds, joined = {}, {}
    for fold in FOLDS:
        truth, _ = read_json(Path(data_dir) / fold_path(fold, "query-truth.json"), artifact_sha(receipt, fold_path(fold, "query-truth.json")))
        rows, writers = join_truth(fold, packet["folds"][fold], truth, vocab); joined[fold] = rows
        views = {"raw": view(rows, writers, vocab.legal_labels), "noCopy": view([r for r in rows if not r["copyReasons"]], writers, vocab.legal_labels)}
        folds[fold] = {"views": views, "fixedScreens": {name: fixed_screen(value) for name, value in views.items()},
                       "copyUnion": packet["folds"][fold]["copyUnion"], "rows": rows}
    uji_sets = [{r["opaqueID"] for r in joined[f] if r["source"] == "uji"} for f in FOLDS]
    hwrt_rows = [{r["opaqueID"]: {k: r[k] for k in ("label", "source", "writer", "session", "nativeSymbolID", *HASH_FIELDS)}
                  for r in joined[f] if r["source"] == "hwrt"} for f in FOLDS]
    require(not uji_sets[0] & uji_sets[1] and hwrt_rows[0] == hwrt_rows[1], "Writer folds must be disjoint; shared HWRT must be identical, never pooled")
    require(read_json(predictions, predictions_sha256)[1] == payload
            and read_json(Path(data_dir) / "data-receipt.json", data_receipt_sha256)[1] == receipt_bytes
            and code_identity() == packet["codeSHA256"], "Frozen prediction/source/code changed during score")
    report = {"version": SCORE_VERSION, "protocolSHA256": PROTOCOL_SHA256, "predictionsSHA256": predictions_sha256,
              "dataReceiptSHA256": data_receipt_sha256, "fitReceiptSHA256": packet["fitReceiptSHA256"],
              "codeSHA256": packet["codeSHA256"], "folds": folds, "queryExposures": 7748, "distinctQueryDrawings": 6978,
              "passesFixedScreen": all(s["passes"] for f in folds.values() for s in f["fixedScreens"].values()),
              "sourcesPooled": False, "freshValidation": False, "personalizationMeasured": False,
              "naturalChordAccuracyMeasured": False, "productionEligible": False}
    return write_exclusive(output, report, (predictions, data_dir))


def main():
    parser = argparse.ArgumentParser(description=__doc__); commands = parser.add_subparsers(dest="command", required=True)
    for name in ("predict", "score"):
        command = commands.add_parser(name); command.add_argument("--data", required=True)
        command.add_argument("--data-receipt-sha256", required=True); command.add_argument("--output", required=True)
        if name == "predict":
            command.add_argument("--fit", required=True); command.add_argument("--fit-receipt-sha256", required=True)
        else:
            command.add_argument("--predictions", required=True); command.add_argument("--predictions-sha256", required=True)
    args = parser.parse_args()
    if args.command == "predict":
        print(predict(args.data, args.fit, args.output, data_receipt_sha256=args.data_receipt_sha256, fit_receipt_sha256=args.fit_receipt_sha256))
    else:
        print(score(args.predictions, args.data, args.output, predictions_sha256=args.predictions_sha256, data_receipt_sha256=args.data_receipt_sha256))


if __name__ == "__main__":
    main()

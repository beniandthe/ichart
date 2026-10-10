"""Post-freeze paired public-glyph scoring; no encoder fit or forward pass.

The optional direct ridge is a declared all-97-taught diagnostic, not evidence
of sparse/untaught safety. Neither endpoint promotes a model into the app.
"""

from __future__ import annotations

import argparse
import hashlib
import math
from collections import Counter
from pathlib import Path

from ..contracts import canonical_json_bytes
from ..features import encode_trajectory, rasterize
from . import personal_dual_view_scoring as previous
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers, trajectory_fingerprint

ARMS = ("rasterOnly", "dual")
SCOPE = previous.SCOPE
FIT_VERSION = "personal-synchronized-dual-view-fit-v1"
PREDICTION_VERSION = "personal-synchronized-dual-view-predictions-v1"
SCORE_VERSION = "personal-synchronized-dual-view-score-v1"
PROTOCOL_PATH = "docs/personal-synchronized-dual-view-protocol-2026-10-02.md"
AUGMENTATION_VERSION = "personal-synchronized-augmentation-v1"
CODE_PATHS = tuple(dict.fromkeys((*previous.CODE_PATHS, PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/research/personal_synchronized_augmentation.py",
    "recognition_ml/tests/test_personal_synchronized_augmentation.py",
    "recognition_ml/ichart_recognition_ml/research/personal_synchronized_dual_view.py",
    "recognition_ml/tests/test_personal_synchronized_dual_view.py",
    "recognition_ml/ichart_recognition_ml/research/personal_synchronized_dual_view_scoring.py",
    "recognition_ml/tests/test_personal_synchronized_dual_view_scoring.py")))
FIT_FIELDS = previous.FIT_FIELDS | {
    "augmentationContract", "augmentationLedger", "sourceRasterMappings", "sourceRasterMappingsSHA256"}
FEATURE_CONTRACT = {**previous.FEATURE_CONTRACT,
    "augmentation": AUGMENTATION_VERSION, "inferenceAugmentation": "none"}
AUGMENTATION_CONTRACT = {
    "version": AUGMENTATION_VERSION,
    "drawContractVersion": "sha256-seed-epoch-source-four-u64-v1",
    "pairContractVersion": "canonical-trajectory-raster-affine-pair-v1",
    "seed": 29, "streamResetPerArm": True,
    "angleDegrees": [-8.0, 8.0], "samplingScale": [0.9, 1.1],
    "translationXFraction": [-0.03, 0.03], "translationYFraction": [-0.05, 0.05],
    "gridTranslationFactor": 2.0, "sampling": "bilinear-zero-align-corners-false",
    "trajectoryTransform": "inverse-pixel-affine-no-recenter-no-clip",
    "sourceMapping": "raw-source-bbox-maxdim-min-finite-237-width-77-height",
    "degenerateEffectivePixelsPerUnit": 77.0,
    "timing": "unavailable-zero", "invalidRows": "zero",
    "sourceIdentity": "personal-dual-view-v1 opaque SHA256 of pinned source and exact sample identity",
    "streamFraming": "uint64-big-endian payload-byte-count followed by payload",
    "permutationPayload": "per-epoch ordered ordinal array, little-endian int64 C-order",
    "drawPayload": "per-batch canonical JSON of SynchronizedAugmentedBatch.metadata in permutation order",
    "featurePayload": "per-batch trajectory then raster, full little-endian float32 C-order, framed separately",
}
MODEL_CONTRACT = {
    "architectureVersion": "personal-dual-view-glyph-v1", "embedding": "l2-normalized-fused-raw-128",
    "embeddingSize": 128, "fusion": "concatenate-raw-128-plus-128-linear-256-to-128",
    "inactiveBranchMask": "zeros-after-projection", "labelCount": 97,
    "rasterBranch": "avgpool2;conv-bn-relu-16-32-64-64;linear1536-to-128",
    "trajectoryBranch": "conv1d-8-32-k7;32-64-k5s2;64-64-k3s2;pool8;linear512-to-128",
}
OPTIMIZATION = {
    "augmentation": AUGMENTATION_VERSION, "batchSize": 128, "cpuThreads": 4,
    "deterministicAlgorithms": True, "epochs": 30, "loss": "cross-entropy",
    "optimizer": {"learningRate": 0.001, "name": "AdamW", "weightDecay": 0.0001},
    "permutationGeneratorSeedPerArm": 29,
    "scheduler": {"name": "CosineAnnealingLR", "tMax": 30}, "seed": 29,
}
INITIAL_STATE = {
    "sha256": "cac7f83a780b5167f1d92eb7db1fd68087e40050f81c7b3c9a10a409dbd266b3",
    "stateKeysSHA256": "cb55a09713e8a28d1cc940c5ef92855423893cb4b9df29a47e6fb56532f52166",
    "stateKeyCount": 43, "parameterCount": 392865,
    "armSHA256": {a: "cac7f83a780b5167f1d92eb7db1fd68087e40050f81c7b3c9a10a409dbd266b3" for a in ARMS},
}
ROLE_GUARDS = {k: False for k in (
    "developmentFeaturesConstructedDuringFit", "developmentInferredDuringFit", "privateInkUsed",
    "productionEligible", "reservedWritersEncoded", "reservedWritersInferred", "reservedWritersTransformed")}


def code_identity():
    root = Path(__file__).resolve().parents[3]
    return {name: previous.sha256(previous._file(root / name).read_bytes()) for name in CODE_PATHS}


def validate_source_mappings(rows):
    if not isinstance(rows, list) or len(rows) != 6208:
        raise ValueError("Source mapping cohort incomplete")
    ids = []
    for row in rows:
        previous._keys(row, {"opaqueID", "normalizedWidth", "normalizedHeight", "sourceRasterScale", "effectivePixelsPerUnit"}, "source mapping")
        if not previous._digest(row["opaqueID"]):
            raise ValueError("Source mapping identity invalid")
        ids.append(row["opaqueID"])
        if any(type(row[k]) not in (int, float) or not math.isfinite(row[k]) for k in row if k != "opaqueID"):
            raise ValueError("Nonfinite source mapping")
        width, height = row["normalizedWidth"], row["normalizedHeight"]
        if not 0 <= width <= 1 or not 0 <= height <= 1 or (max(width, height) not in (0, 1)):
            raise ValueError("Source mapping extent invalid")
        scales = [span / dimension for span, dimension in ((237.0, width), (77.0, height)) if dimension > 0]
        expected = min(scales) if scales else 0.0
        effective = expected if expected else 77.0
        if row["sourceRasterScale"] != expected or row["effectivePixelsPerUnit"] != effective:
            raise ValueError("Source mapping scale is not the frozen raw-source mapping")
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate source mapping identity")


def validate_ledger(ledger):
    previous._keys(ledger, ARMS, "augmentation ledger arms")
    for arm in ARMS:
        receipt = previous._keys(ledger[arm], {"epochs", "sampleExposures", "updateCount", "drawStreamSHA256", "permutationStreamSHA256", "augmentedFeatureStreamSHA256"}, "augmentation ledger")
        if type(receipt["sampleExposures"]) is not int or receipt["sampleExposures"] != 6208 * 30 or type(receipt["updateCount"]) is not int or receipt["updateCount"] != 49 * 30:
            raise ValueError("Incomplete augmentation exposure/update counts")
        if not all(previous._digest(receipt[k]) for k in ("drawStreamSHA256", "permutationStreamSHA256", "augmentedFeatureStreamSHA256")):
            raise ValueError("Invalid augmentation stream digest")
        if not isinstance(receipt["epochs"], list) or len(receipt["epochs"]) != 30:
            raise ValueError("Incomplete augmentation epochs")
        complete_permutations = hashlib.sha256()
        for epoch, row in enumerate(receipt["epochs"], 1):
            previous._keys(row, {"epoch", "sampleCount", "batchCount", "drawStreamSHA256", "permutationSHA256", "permutationOrdinals", "augmentedFeatureSHA256"}, "augmentation epoch")
            if any(type(row[k]) is not int or row[k] != v for k, v in (("epoch", epoch), ("sampleCount", 6208), ("batchCount", 49))) or not all(previous._digest(row[k]) for k in ("drawStreamSHA256", "permutationSHA256", "augmentedFeatureSHA256")):
                raise ValueError("Invalid augmentation epoch counts/digests")
            ordinals = row["permutationOrdinals"]
            if not isinstance(ordinals, list) or len(ordinals) != 6208 or any(type(i) is not int for i in ordinals) or sorted(ordinals) != list(range(6208)):
                raise ValueError("Incomplete or duplicated permutation ordinal trace")
            payload = b"".join(i.to_bytes(8, "little", signed=True) for i in ordinals)
            if previous.sha256(payload) != row["permutationSHA256"]:
                raise ValueError("Permutation ordinal bytes/digest mismatch")
            complete_permutations.update(len(payload).to_bytes(8, "big"))
            complete_permutations.update(payload)
        if complete_permutations.hexdigest() != receipt["permutationStreamSHA256"]:
            raise ValueError("Complete permutation stream digest mismatch")
    if ledger["rasterOnly"] != ledger["dual"]:
        raise ValueError("Arms did not consume identical augmentation/permutation streams")


def validate_fit_receipt(fit, code, protocol_sha, weights):
    previous._keys(fit, FIT_FIELDS, "synchronized fit receipt")
    expected = {
        "version": FIT_VERSION, "scope": SCOPE, "arms": list(ARMS), "sourceSHA256": SOURCE_SHA256,
        "protocolSHA256": protocol_sha, "codeSHA256": code, "featureContract": FEATURE_CONTRACT,
        "augmentationContract": AUGMENTATION_CONTRACT, "optimization": OPTIMIZATION,
        "modelContract": MODEL_CONTRACT, "initialState": INITIAL_STATE, "roleGuards": ROLE_GUARDS,
        "trainingSamples": 6208, "developmentSamples": 1552, "reservedSamples": 3880,
        "selection": "final-epoch-only", "weightFiles": {a: f"weights/{a}.pt" for a in ARMS}, "weightsSHA256": weights,
    }
    if set(code) != set(CODE_PATHS) or not all(previous._digest(x) for x in code.values()) or code[PROTOCOL_PATH] != protocol_sha or any(fit[k] != v for k, v in expected.items()):
        raise ValueError("Fit metadata/bindings do not match the synchronized frozen contract")
    if set(weights) != set(ARMS) or not all(previous._digest(x) for x in weights.values()):
        raise ValueError("Invalid weights bindings")
    runtime = previous._keys(fit["runtime"], {"python", "platform", "torch", "numpy", "cpuThreads", "deterministicAlgorithms"}, "runtime")
    if runtime["cpuThreads"] != 4 or runtime["deterministicAlgorithms"] is not True or any(not isinstance(runtime[k], str) or not runtime[k] for k in ("python", "platform", "torch", "numpy")):
        raise ValueError("Invalid deterministic runtime")
    vocabulary = fit["vocabulary"]
    if not isinstance(vocabulary, list) or len(vocabulary) != 97 or any(not isinstance(x, str) or len(x) != 1 for x in vocabulary) or sorted(set(vocabulary)) != vocabulary or fit["vocabularySHA256"] != previous.sha256(canonical_json_bytes(vocabulary)):
        raise ValueError("Invalid 97-class vocabulary binding")
    writers = []
    for field, count, prefix in (("trainingWriters", 32, "trn_"), ("developmentWriters", 8, "trn_"), ("reservedWriters", 20, "tst_")):
        role = fit[field]
        if not isinstance(role, list) or len(role) != count or any(not isinstance(w, str) or not w.startswith(prefix) for w in role) or sorted(set(role)) != role:
            raise ValueError("Invalid writer role receipt")
        writers.extend(role)
    if len(set(writers)) != 60:
        raise ValueError("Overlapping writer roles")
    hashes = fit["trainingInputHashes"]
    if not isinstance(hashes, list) or len(hashes) != 6208 or any(not isinstance(r, dict) or set(r) != previous.HASH_FIELDS or not all(previous._digest(x) for x in r.values()) for r in hashes) or hashes != sorted(hashes, key=lambda r: (r["rasterSHA256"], r["trajectorySHA256"], r["normalizedTrajectorySHA256"])) or fit["trainingInputHashesSHA256"] != previous.sha256(canonical_json_bytes(hashes)):
        raise ValueError("Invalid training feature bindings")
    validate_source_mappings(fit["sourceRasterMappings"])
    if fit["sourceRasterMappingsSHA256"] != previous.sha256(canonical_json_bytes(fit["sourceRasterMappings"])):
        raise ValueError("Source mapping hash mismatch")
    validate_ledger(fit["augmentationLedger"])
    previous._keys(fit["trainingHistory"], ARMS, "training histories")
    for history in fit["trainingHistory"].values():
        if not isinstance(history, list) or len(history) != 30:
            raise ValueError("Incomplete fit history")
        for epoch, row in enumerate(history, 1):
            previous._keys(row, {"epoch", "trainCorrect", "trainLoss"}, "fit epoch")
            if type(row["epoch"]) is not int or row["epoch"] != epoch or type(row["trainCorrect"]) is not int or not 0 <= row["trainCorrect"] <= 6208 or type(row["trainLoss"]) not in (int, float) or not math.isfinite(row["trainLoss"]) or row["trainLoss"] < 0:
                raise ValueError("Invalid fit history")


def validate_prediction_packet(payload, fit, fit_bytes, code, protocol_sha, weights):
    packet = previous._json(payload, "synchronized frozen predictions")
    previous._keys(packet, previous.PREDICTION_FIELDS, "prediction packet")
    validate_fit_receipt(fit, code, protocol_sha, weights)
    if canonical_json_bytes(fit) != fit_bytes:
        raise ValueError("Noncanonical fit bytes")
    expected = {"version": PREDICTION_VERSION, "scope": SCOPE, "arms": list(ARMS), "rowCount": 1552,
        "sourceSHA256": SOURCE_SHA256, "protocolSHA256": protocol_sha, "codeSHA256": code,
        "runtime": fit["runtime"], "featureContract": FEATURE_CONTRACT,
        "fitReceiptSHA256": previous.sha256(fit_bytes), "weightsSHA256": weights,
        "vocabularySHA256": fit["vocabularySHA256"]}
    if any(packet[k] != v for k, v in expected.items()):
        raise ValueError("Prediction bindings changed")
    if not isinstance(packet["rows"], list) or len(packet["rows"]) != 1552:
        raise ValueError("Incomplete frozen prediction cohort")
    ids = []
    for row in packet["rows"]:
        previous._keys(row, {"opaqueID", "outputs", "rasterSHA256", "sourceGroups", "trajectorySHA256"}, "prediction row")
        if not all(previous._digest(row[k]) for k in ("opaqueID", "rasterSHA256", "trajectorySHA256")):
            raise ValueError("Invalid prediction identity/hashes")
        ids.append(row["opaqueID"])
        groups = row["sourceGroups"]
        if not isinstance(groups, list) or len(groups) != 1 or not isinstance(groups[0], list) or not 1 <= len(groups[0]) <= 64 or any(type(i) is not int for i in groups[0]) or groups[0] != list(range(len(groups[0]))):
            raise ValueError("Incomplete original stroke ownership")
        for value in previous._keys(row["outputs"], ARMS, "prediction arms").values():
            previous._keys(value, {"embedding", "rawLogits"}, "prediction output")
            if not previous._finite_vector(value["rawLogits"], 97) or not previous._finite_vector(value["embedding"], 128) or abs(math.sqrt(sum(x * x for x in value["embedding"])) - 1.0) > 1e-4:
                raise ValueError("Nonfinite, malformed or unnormalized prediction output")
    if ids != sorted(set(ids)):
        raise ValueError("Duplicate or unsorted prediction identity")
    return packet


def advancement_gate(rows):
    result = previous.advancement_gate(rows)
    result["rules"]["historicalOperationalFloor1229"] = result["paired"]["candidateCorrect"] >= 1229
    result["nextBlindDevelopmentGateEligible"] = all(result["rules"].values())
    result["historicalFloorScope"] = "Pinned historical operational count; not a matched causal control"
    return result


def personalize(rows, packet_rows, vocabulary):
    # Freeze all direct-ridge predictions before scoring query correctness.
    frozen = {}
    for arm in ARMS:
        for writer in sorted({r["writer"] for r in rows}):
            support = sorted((r for r in rows if r["writer"] == writer and r["session"] == 1), key=lambda r: r["intended"])
            queries = sorted((r for r in rows if r["writer"] == writer and r["session"] == 2), key=lambda r: r["opaqueID"])
            if [r["intended"] for r in support] != vocabulary or len(queries) != 97:
                raise ValueError("All-97-taught support/query cohort incomplete")
            labels = previous.predict_personal([packet_rows[r["opaqueID"]]["outputs"][arm]["embedding"] for r in support],
                [r["intended"] for r in support], [packet_rows[r["opaqueID"]]["outputs"][arm]["embedding"] for r in queries])
            if len(labels) != 97 or any(label not in vocabulary for label in labels):
                raise ValueError("Incomplete personal diagnostic predictions")
            support_hashes = previous._hash_sets([r["inputHashes"] for r in support])
            for query, label in zip(queries, labels):
                frozen[arm, query["opaqueID"]] = (label, previous._copy_reasons(query["inputHashes"], support_hashes, "support"))
    result = {}
    for arm in ARMS:
        scored = []
        for row in rows:
            if row["session"] == 2:
                label, reasons = frozen[arm, row["opaqueID"]]
                predictions = {"generic": row["predictions"][arm], "personal": label}
                scored.append({**row, "predictions": predictions,
                    "correct": {k: v == row["intended"] for k, v in predictions.items()},
                    "noveltyExclusions": row["noveltyExclusions"] + reasons})
        if len(scored) != 776:
            raise ValueError("Missing personal query rows")
        novel = [r for r in scored if not r["noveltyExclusions"]]
        result[arm] = {"method": "unchanged direct balanced one-hot ridge lambda0.1; no generic addition",
            "all97ClassesTaught": True, "untaughtSafetyMeasured": False, "productionEligible": False,
            "rows": scored, "rawPaired": previous.paired_summary(scored, "generic", "personal"),
            "noveltyPaired": previous.paired_summary(novel, "generic", "personal"),
            "generic": previous.identity_summary(scored, "generic"), "personal": previous.identity_summary(scored, "personal"),
            "noveltyCount": len(novel)}
    return result


def _preserved(snapshot, code):
    if any(previous.sha256(p.read_bytes()) != value for p, value in snapshot.items()) or code_identity() != code:
        raise ValueError("Bound source, fit, predictions, protocol, weights or code changed")


def score(predictions, fit_directory, source, baseline, protocol, output, *, personalization=False):
    predictions = previous._file(predictions)
    prediction_bytes = predictions.read_bytes()  # Complete frozen outputs first.
    fit_path = previous._file(fit_directory / "fit-receipt.json")
    fit_bytes = fit_path.read_bytes()
    fit = previous._json(fit_bytes, "fit receipt")
    protocol = previous._file(protocol)
    frozen_protocol = previous._file(fit_directory / "frozen-protocol.md")
    protocol_bytes = protocol.read_bytes()
    code = code_identity()
    if previous.sha256(protocol_bytes) != code[PROTOCOL_PATH] or frozen_protocol.read_bytes() != protocol_bytes:
        raise ValueError("Frozen protocol mismatch")
    weight_paths = {a: previous._file(fit_directory / "weights" / f"{a}.pt") for a in ARMS}
    weights = {a: previous.sha256(p.read_bytes()) for a, p in weight_paths.items()}
    packet = validate_prediction_packet(prediction_bytes, fit, fit_bytes, code, previous.sha256(protocol_bytes), weights)
    frozen = {r["opaqueID"]: {a: previous.argmax_label(r["outputs"][a]["rawLogits"], fit["vocabulary"]) for a in ARMS} for r in packet["rows"]}
    source, baseline = previous._file(source), previous._file(baseline)
    paths = {"predictions": predictions, "fitReceipt": fit_path, "source": source, "historicalBaseline": baseline,
        "protocol": protocol, "fitProtocol": frozen_protocol, **{f"weights:{a}": p for a, p in weight_paths.items()}}
    snapshot = {p: previous.sha256(p.read_bytes()) for p in paths.values()}
    snapshot.update({predictions: previous.sha256(prediction_bytes), fit_path: previous.sha256(fit_bytes),
        protocol: previous.sha256(protocol_bytes), frozen_protocol: previous.sha256(protocol_bytes),
        **{p: weights[a] for a, p in weight_paths.items()}})
    try:
        _preserved(snapshot, code)
        if snapshot[source] != SOURCE_SHA256 or snapshot[baseline] != previous.BASELINE_SHA256:
            raise ValueError("Pinned source/historical digest mismatch")
        records = load_official_source(source)
        roles = split_writers(records)
        if tuple(fit[k] for k in ("trainingWriters", "developmentWriters", "reservedWriters")) != tuple(list(x) for x in roles):
            raise ValueError("Actual source roles differ from fit")
        development = tuple(r for r in records if r.writer in set(roles[1]))
        if len(development) != 1552 or sorted({r.label for r in records}) != fit["vocabulary"]:
            raise ValueError("Development/vocabulary cohort mismatch")
        packet_rows = {r["opaqueID"]: r for r in packet["rows"]}
        if set(packet_rows) != {previous.opaque_id(SOURCE_SHA256, s.identity) for s in development}:
            raise ValueError("Frozen query source identity mismatch")
        historical = previous._baseline(baseline.read_bytes(), development)
        training_hashes = previous._hash_sets(fit["trainingInputHashes"])
        rows = []
        for sample in sorted(development, key=lambda s: previous.opaque_id(SOURCE_SHA256, s.identity)):
            oid = previous.opaque_id(SOURCE_SHA256, sample.identity)
            packet_row = packet_rows[oid]
            hashes = {"rasterSHA256": previous.sha256(rasterize(sample.strokes).pixels),
                "trajectorySHA256": previous.sha256(encode_trajectory(sample.strokes).to_bytes()),
                "normalizedTrajectorySHA256": trajectory_fingerprint(sample)}
            if packet_row["sourceGroups"] != [list(range(len(sample.strokes)))] or any(packet_row[k] != hashes[k] for k in ("rasterSHA256", "trajectorySHA256")):
                raise ValueError("Frozen inference geometry differs from source")
            predicted = {**frozen[oid], "historicalCoreML": historical[sample.identity]}
            rows.append({"opaqueID": oid, "sourceID": sample.identity, "writer": sample.writer, "session": sample.session,
                "intended": sample.label, "sourceGroups": packet_row["sourceGroups"], "inputHashes": hashes,
                "predictions": predicted, "correct": {a: p == sample.label for a, p in predicted.items()},
                "noveltyExclusions": previous._copy_reasons(hashes, training_hashes, "training")})
        novel = [r for r in rows if not r["noveltyExclusions"]]
        report = {"version": SCORE_VERSION, "scope": SCOPE, "rowCount": len(rows), "arms": list(ARMS),
            "productionEligible": False, "freshWriterEvaluation": False, "naturalChordEvaluation": False,
            "inputSHA256": {role: snapshot[p] for role, p in paths.items()}, "codeSHA256": code,
            "vocabulary": fit["vocabulary"], "vocabularySHA256": fit["vocabularySHA256"], "rows": rows,
            "primary": advancement_gate(rows), "summaries": {a: previous.identity_summary(rows, a) for a in ARMS},
            "historicalReference": {"scope": "Pinned prior Core ML source-owner inference; unmatched historical architecture/regime",
                "summary": previous.identity_summary(rows, "historicalCoreML")},
            "novelty": {"count": len(novel), "excluded": len(rows) - len(novel),
                "exclusionReasons": dict(sorted(Counter(reason for r in rows for reason in r["noveltyExclusions"]).items())),
                "summaries": {a: previous.identity_summary(novel, a) for a in ARMS}, "paired": previous.paired_summary(novel, "rasterOnly", "dual")},
            "personalization": personalize(rows, packet_rows, fit["vocabulary"]) if personalization else None,
            "inputsUnchanged": True}
        _preserved(snapshot, code)
    finally:
        _preserved(snapshot, code)
    output = Path(output)
    if not output.is_absolute() or ".." in output.parts or output.exists() or output.is_symlink() or output.parent.resolve(strict=True) != output.parent:
        raise ValueError("Output must be a new exclusive canonical directory")
    output.mkdir(mode=0o700)
    with (output / "score.json").open("xb") as stream:
        stream.write(canonical_json_bytes(report))
    print(f"SYNCHRONIZED_SCORE rows={len(rows)} writerUnits=8 primaryEligible={report['primary']['nextBlindDevelopmentGateEligible']} personalization={personalization}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("predictions", "fit-directory", "source", "baseline", "protocol", "output"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    parser.add_argument("--personalization", action="store_true")
    args = parser.parse_args()
    score(args.predictions, args.fit_directory, args.source, args.baseline, args.protocol, args.output, personalization=args.personalization)


if __name__ == "__main__":
    main()

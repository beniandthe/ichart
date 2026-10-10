"""Post-freeze scoring only: no shared model construction, fitting or inference.

All raw queries remain in the primary endpoint. The optional personal diagnostic
uses only the existing direct ridge on session-one support embeddings. Neither
endpoint grants production eligibility or measures natural chord recognition.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import math
import stat
from collections import Counter
from fractions import Fraction
from pathlib import Path

from ..contracts import canonical_json_bytes, strict_json_loads
from ..errors import ContractError
from ..features import encode_trajectory, rasterize
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers, trajectory_fingerprint

ARMS = ("rasterOnly", "trajectoryOnly", "dual")
SCOPE = "public-uji-observed-development-shared-glyph-identity-research-not-production"
BASELINE_SHA256 = "c4b6acc6caf76e0f7d0af9ee8036cd672673f1690e790fee3dcf14fea329c01b"
PROTOCOL_PATH = "docs/personal-dual-view-glyph-protocol-2026-09-30.md"
CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
    "recognition_ml/ichart_recognition_ml/research/personal_dual_view.py",
    "recognition_ml/tests/test_personal_dual_view.py",
    "recognition_ml/ichart_recognition_ml/research/personal_dual_view_scoring.py",
    "recognition_ml/tests/test_personal_dual_view_scoring.py",
)
FIT_FIELDS = {
    "arms", "codeSHA256", "developmentSamples", "developmentWriters", "featureContract",
    "initialState", "modelContract", "optimization", "protocolSHA256", "reservedSamples",
    "reservedWriters", "roleGuards", "runtime", "scope", "selection", "sourceSHA256",
    "trainingHistory", "trainingInputHashes", "trainingInputHashesSHA256", "trainingSamples",
    "trainingWriters", "version", "vocabulary", "vocabularySHA256", "weightFiles", "weightsSHA256",
}
PREDICTION_FIELDS = {
    "arms", "codeSHA256", "featureContract", "fitReceiptSHA256", "protocolSHA256", "rowCount",
    "rows", "runtime", "scope", "sourceSHA256", "version", "vocabularySHA256", "weightsSHA256",
}
HASH_FIELDS = {"rasterSHA256", "trajectorySHA256", "normalizedTrajectorySHA256"}
FEATURE_CONTRACT = {
    "augmentation": "none", "featureSchemaVersion": "chord-ink-features-v1",
    "geometryChannelIndexes": [0, 1, 2, 3, 4, 7, 8, 9], "rasterEncoding": "uint8-gray",
    "rasterHashEncoding": "sha256-exact-uint8-plane", "rasterNormalization": "float32-divide-255",
    "rasterShape": [1, 96, 256], "sourceGroups": "single-source-glyph-all-original-stroke-indexes",
    "timingChannelIndexesExcluded": [5, 6], "trajectoryEncoding": "float32-le",
    "trajectoryHashEncoding": "sha256-exact-full-10-channel-float32-le",
    "trajectoryShape": [1, 256, 10],
}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _keys(value, expected, name):
    if not isinstance(value, dict) or set(value) != set(expected):
        raise ValueError(f"{name}: missing or unknown fields")
    return value


def _digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _finite_vector(value, size):
    return isinstance(value, list) and len(value) == size and all(
        type(x) in (int, float) and math.isfinite(x) for x in value
    )


def _json(payload: bytes, name: str, *, canonical=True):
    try:
        value = strict_json_loads(payload.decode("utf-8"), name)
    except (ContractError, UnicodeDecodeError) as error:
        raise ValueError(f"{name}: invalid JSON bytes") from error
    if not isinstance(value, dict) or (canonical and canonical_json_bytes(value) != payload):
        raise ValueError(f"{name}: not a canonical JSON object")
    return value


def opaque_id(source_sha: str, identity: str) -> str:
    return sha256(b"personal-dual-view-v1\0" + source_sha.encode("ascii") + b"\0" + identity.encode("utf-8"))


def code_identity() -> dict[str, str]:
    root = Path(__file__).resolve().parents[3]
    return {name: sha256(_file(root / name).read_bytes()) for name in CODE_PATHS}


def validate_fit_receipt(fit, code, protocol_sha, weights):
    """Validate bytes/metadata without loading checkpoint tensors or the producer."""
    _keys(fit, FIT_FIELDS, "fit receipt")
    expected = {
        "version": "personal-dual-view-fit-v1", "scope": SCOPE, "arms": list(ARMS),
        "sourceSHA256": SOURCE_SHA256, "protocolSHA256": protocol_sha, "codeSHA256": code,
        "featureContract": FEATURE_CONTRACT, "trainingSamples": 6208,
        "developmentSamples": 1552, "reservedSamples": 3880, "selection": "final-epoch-only",
        "weightFiles": {arm: f"weights/{arm}.pt" for arm in ARMS}, "weightsSHA256": weights,
        "roleGuards": {key: False for key in (
            "developmentFeaturesConstructedDuringFit", "developmentInferredDuringFit", "privateInkUsed",
            "productionEligible", "reservedWritersEncoded", "reservedWritersInferred", "reservedWritersTransformed")},
        "modelContract": {
            "architectureVersion": "personal-dual-view-glyph-v1", "embedding": "l2-normalized-fused-raw-128",
            "embeddingSize": 128, "fusion": "concatenate-raw-128-plus-128-linear-256-to-128",
            "inactiveBranchMask": "zeros-after-projection", "labelCount": 97,
            "rasterBranch": "avgpool2;conv-bn-relu-16-32-64-64;linear1536-to-128",
            "trajectoryBranch": "conv1d-8-32-k7;32-64-k5s2;64-64-k3s2;pool8;linear512-to-128"},
        "optimization": {
            "augmentation": "none", "batchSize": 128, "cpuThreads": 4, "deterministicAlgorithms": True,
            "epochs": 30, "loss": "cross-entropy", "optimizer": {
                "learningRate": 0.001, "name": "AdamW", "weightDecay": 0.0001},
            "permutationGeneratorSeedPerArm": 29, "scheduler": {"name": "CosineAnnealingLR", "tMax": 30}, "seed": 29},
    }
    if any(fit.get(key) != value for key, value in expected.items()):
        raise ValueError("Fit metadata/bindings do not match the frozen contract")
    if set(weights) != set(ARMS) or not all(_digest(x) for x in weights.values()):
        raise ValueError("Invalid weights binding")
    runtime = _keys(fit["runtime"], {"python", "platform", "torch", "numpy", "cpuThreads", "deterministicAlgorithms"}, "runtime")
    if runtime["cpuThreads"] != 4 or runtime["deterministicAlgorithms"] is not True or any(
        not isinstance(runtime[k], str) or not runtime[k] for k in ("python", "platform", "torch", "numpy")
    ):
        raise ValueError("Invalid fit runtime")
    vocab = fit["vocabulary"]
    if not isinstance(vocab, list) or len(vocab) != 97 or any(not isinstance(x, str) or len(x) != 1 for x in vocab) or sorted(set(vocab)) != vocab:
        raise ValueError("Invalid 97-label vocabulary")
    if fit["vocabularySHA256"] != sha256(canonical_json_bytes(vocab)):
        raise ValueError("Vocabulary hash mismatch")
    all_writers = []
    for field, count, prefix in (("trainingWriters", 32, "trn_"), ("developmentWriters", 8, "trn_"), ("reservedWriters", 20, "tst_")):
        writers = fit[field]
        if not isinstance(writers, list) or len(writers) != count or any(not isinstance(w, str) or not w.startswith(prefix) for w in writers) or sorted(set(writers)) != writers:
            raise ValueError("Invalid writer-role receipt")
        all_writers.extend(writers)
    if len(set(all_writers)) != 60:
        raise ValueError("Overlapping writer roles")
    initial = _keys(fit["initialState"], {"armSHA256", "parameterCount", "sha256", "stateKeyCount", "stateKeysSHA256"}, "initial state")
    if not _digest(initial["sha256"]) or not _digest(initial["stateKeysSHA256"]) or initial["armSHA256"] != {a: initial["sha256"] for a in ARMS} or any(type(initial[k]) is not int or initial[k] <= 0 for k in ("parameterCount", "stateKeyCount")):
        raise ValueError("Initial-state identity mismatch")
    hashes = fit["trainingInputHashes"]
    if not isinstance(hashes, list) or len(hashes) != 6208 or any(
        not isinstance(row, dict) or set(row) != HASH_FIELDS or not all(_digest(x) for x in row.values()) for row in hashes
    ) or hashes != sorted(hashes, key=lambda r: (r["rasterSHA256"], r["trajectorySHA256"], r["normalizedTrajectorySHA256"])) or fit["trainingInputHashesSHA256"] != sha256(canonical_json_bytes(hashes)):
        raise ValueError("Training-copy hashes missing or changed")
    histories = _keys(fit["trainingHistory"], ARMS, "histories")
    for history in histories.values():
        if not isinstance(history, list) or len(history) != 30:
            raise ValueError("Incomplete training history")
        for epoch, row in enumerate(history, 1):
            _keys(row, {"epoch", "trainCorrect", "trainLoss"}, "history row")
            if row["epoch"] != epoch or type(row["trainCorrect"]) is not int or not 0 <= row["trainCorrect"] <= 6208 or type(row["trainLoss"]) not in (int, float) or not math.isfinite(row["trainLoss"]) or row["trainLoss"] < 0:
                raise ValueError("Invalid training history")


def validate_prediction_packet(payload: bytes, fit: dict, fit_bytes: bytes, code: dict, protocol_sha: str, weights: dict) -> dict:
    packet = _json(payload, "frozen predictions")
    _keys(packet, PREDICTION_FIELDS, "predictions")
    validate_fit_receipt(fit, code, protocol_sha, weights)
    if canonical_json_bytes(fit) != fit_bytes:
        raise ValueError("Fit receipt bytes are not canonical")
    expected = {
        "version": "personal-dual-view-predictions-v1", "scope": SCOPE, "arms": list(ARMS),
        "rowCount": 1552, "sourceSHA256": SOURCE_SHA256, "protocolSHA256": protocol_sha,
        "codeSHA256": code, "runtime": fit["runtime"], "featureContract": FEATURE_CONTRACT,
        "fitReceiptSHA256": sha256(fit_bytes), "weightsSHA256": weights,
        "vocabularySHA256": fit["vocabularySHA256"],
    }
    if any(packet.get(key) != value for key, value in expected.items()):
        raise ValueError("Prediction bindings changed")
    rows = packet["rows"]
    if not isinstance(rows, list) or len(rows) != 1552:
        raise ValueError("Missing prediction rows")
    ids = []
    for row in rows:
        _keys(row, {"opaqueID", "outputs", "rasterSHA256", "sourceGroups", "trajectorySHA256"}, "prediction row")
        if not all(_digest(row[k]) for k in ("opaqueID", "rasterSHA256", "trajectorySHA256")):
            raise ValueError("Invalid row digests")
        ids.append(row["opaqueID"])
        groups = row["sourceGroups"]
        if not isinstance(groups, list) or len(groups) != 1 or not isinstance(groups[0], list) or not 1 <= len(groups[0]) <= 64 or any(type(i) is not int for i in groups[0]) or groups[0] != list(range(len(groups[0]))):
            raise ValueError("Not one complete original-index owner")
        outputs = _keys(row["outputs"], ARMS, "arm outputs")
        for output in outputs.values():
            _keys(output, {"embedding", "rawLogits"}, "output")
            if not _finite_vector(output["embedding"], 128) or not _finite_vector(output["rawLogits"], 97):
                raise ValueError("Invalid frozen output shape or finite values")
            if abs(math.sqrt(sum(x * x for x in output["embedding"])) - 1.0) > 1e-4:
                raise ValueError("Frozen embedding is not L2-normalized")
    if ids != sorted(set(ids)):
        raise ValueError("Duplicate or unsorted opaque IDs")
    return packet


def argmax_label(logits, vocabulary):
    if len(logits) != len(vocabulary) or not logits or any(type(x) not in (int, float) or not math.isfinite(x) for x in logits):
        raise ValueError("Invalid raw logits")
    return vocabulary[max(range(len(logits)), key=lambda i: logits[i])]


def exact_mcnemar(gains: int, harms: int) -> dict:
    if type(gains) is not int or type(harms) is not int or min(gains, harms) < 0:
        raise ValueError("Invalid discordant counts")
    n = gains + harms
    p = min(Fraction(1), Fraction(2 * sum(math.comb(n, k) for k in range(min(gains, harms) + 1)), 2 ** n)) if n else Fraction(1)
    return {"discordantRows": n, "pValue": float(p), "numerator": str(p.numerator), "denominator": str(p.denominator), "scope": "row-level descriptive only; correlated glyphs are not independent writer units"}


def writer_sign_flip(writer_deltas: dict[str, int]) -> dict:
    if len(writer_deltas) != 8 or any(not isinstance(w, str) or not w or type(d) is not int for w, d in writer_deltas.items()):
        raise ValueError("Exactly eight writer-cluster integer deltas required")
    deltas = [writer_deltas[w] for w in sorted(writer_deltas)]
    observed = abs(sum(deltas))
    tail = sum(abs(sum(s * d for s, d in zip(signs, deltas))) >= observed for signs in itertools.product((-1, 1), repeat=8))
    return {"pValue": tail / 256, "tailAssignments": tail, "totalAssignments": 256, "writerUnits": 8, "absoluteDelta": observed, "assumptions": "independent writer clusters and sign symmetry; eight already-observed writers, not fresh-test accuracy"}


def _paired(rows, reference, candidate):
    outcomes = Counter((r["predictions"][reference] == r["intended"], r["predictions"][candidate] == r["intended"]) for r in rows)
    gains, harms = outcomes[False, True], outcomes[True, False]
    return {"count": len(rows), "referenceCorrect": outcomes[True, True] + harms, "candidateCorrect": outcomes[True, True] + gains, "bothCorrect": outcomes[True, True], "neitherCorrect": outcomes[False, False], "gains": gains, "harms": harms, "net": gains - harms}


def paired_summary(rows, reference, candidate):
    result = _paired(rows, reference, candidate)
    result.update(reference=reference, candidate=candidate,
        perWriter={w: _paired([r for r in rows if r["writer"] == w], reference, candidate) for w in sorted({r["writer"] for r in rows})},
        perLabel={label: _paired([r for r in rows if r["intended"] == label], reference, candidate) for label in sorted({r["intended"] for r in rows})},
        rowMcNemarDescriptive=exact_mcnemar(result["gains"], result["harms"]))
    return result


def advancement_gate(rows):
    summary = paired_summary(rows, "rasterOnly", "dual")
    if len(rows) != 1552 or len(summary["perWriter"]) != 8 or any(x["count"] != 194 for x in summary["perWriter"].values()):
        raise ValueError("Primary writer denominators are not eight times 194")
    deltas = {w: x["net"] for w, x in summary["perWriter"].items()}
    sign_flip = writer_sign_flip(deltas)
    rules = {"gainsExceedHarms": summary["gains"] > summary["harms"], "writerSignFlipPBelow005": sign_flip["tailAssignments"] * 20 < 256,
        "atLeastSixWritersNonWorse": sum(d >= 0 for d in deltas.values()) >= 6, "worstWriterLossAtMostTwo": min(deltas.values()) >= -2}
    return {"paired": summary, "writerSignFlip": sign_flip, "writerDeltas": deltas, "rules": rules, "nextBlindDevelopmentGateEligible": all(rules.values()), "productionEligible": False}


def identity_summary(rows, arm):
    def counts(subset):
        confusion = Counter((r["intended"], r["predictions"][arm]) for r in subset)
        case_only = sum(a != b and a.isascii() and b.isascii() and a.isalpha() and b.isalpha() and a.lower() == b.lower()
            for a, b in ((r["intended"], r["predictions"][arm]) for r in subset))
        return {"count": len(subset), "correct": sum(r["predictions"][arm] == r["intended"] for r in subset), "asciiCaseOnlyMisses": case_only,
            "confusions": [{"intended": a, "predicted": b, "count": n} for (a, b), n in sorted(confusion.items())]}
    return {**counts(rows), "perWriter": {w: counts([r for r in rows if r["writer"] == w]) for w in sorted({r["writer"] for r in rows})},
        "perLabel": {label: counts([r for r in rows if r["intended"] == label]) for label in sorted({r["intended"] for r in rows})}}


def predict_personal(support_features, support_labels, query_features):
    # This is the unchanged direct one-hot ridge, not a shared-model call and
    # not the Swift residual head. Query labels are deliberately not arguments.
    from .personal_visual_encoder import fit_personal, rank_personal
    model = fit_personal(support_features, support_labels, regularization=0.1)
    return [rank_personal(model, features)[0]["label"] for features in query_features]


def _copy_reasons(hashes, reference, prefix):
    return [f"{prefix}:{key}" for key in sorted(HASH_FIELDS) if hashes[key] in reference[key]]


def _hash_sets(rows):
    return {key: {row[key] for row in rows} for key in HASH_FIELDS}


def _personalize(rows, packet_rows, vocabulary):
    frozen = {}
    for arm in ARMS:
        for writer in sorted({r["writer"] for r in rows}):
            support = sorted((r for r in rows if r["writer"] == writer and r["session"] == 1), key=lambda r: r["intended"])
            queries = sorted((r for r in rows if r["writer"] == writer and r["session"] == 2), key=lambda r: r["opaqueID"])
            if [r["intended"] for r in support] != vocabulary or len(queries) != 97:
                raise ValueError("Personal support/query cohort incomplete")
            predictions = predict_personal([packet_rows[r["opaqueID"]]["outputs"][arm]["embedding"] for r in support],
                [r["intended"] for r in support], [packet_rows[r["opaqueID"]]["outputs"][arm]["embedding"] for r in queries])
            support_hashes = _hash_sets([r["inputHashes"] for r in support])
            for query, predicted in zip(queries, predictions):
                frozen[arm, query["opaqueID"]] = (predicted, _copy_reasons(query["inputHashes"], support_hashes, "support"))
    # All 3 x 776 predictions above are fixed before query correctness below.
    result = {}
    for arm in ARMS:
        scored = []
        for row in rows:
            if row["session"] != 2:
                continue
            predicted, reasons = frozen[arm, row["opaqueID"]]
            predictions = {"generic": row["predictions"][arm], "personal": predicted}
            scored.append({**row, "predictions": predictions,
                "correct": {name: label == row["intended"] for name, label in predictions.items()},
                "noveltyExclusions": row["noveltyExclusions"] + reasons})
        if len(scored) != 776:
            raise ValueError("Missing personal query predictions")
        novel = [r for r in scored if not r["noveltyExclusions"]]
        result[arm] = {"method": "existing direct one-hot balanced ridge lambda 0.1; no generic addition", "rows": scored,
            "rawPaired": paired_summary(scored, "generic", "personal"), "noveltyPaired": paired_summary(novel, "generic", "personal"),
            "generic": identity_summary(scored, "generic"), "personal": identity_summary(scored, "personal"), "noveltyCount": len(novel)}
    return result


def _file(path: Path) -> Path:
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts or path.resolve(strict=True) != path or path.is_symlink() or not stat.S_ISREG(path.stat().st_mode):
        raise ValueError("Input must be an absolute unaliased regular file")
    return path


def _preserved(snapshot, code):
    if any(sha256(path.read_bytes()) != digest for path, digest in snapshot.items()) or code_identity() != code:
        raise ValueError("Frozen source, predictions, fit, weights, protocol or code changed during scoring")


def _baseline(payload, development):
    if sha256(payload) != BASELINE_SHA256:
        raise ValueError("Historical report digest mismatch")
    report = _json(payload, "historical conditional identity", canonical=False)
    if report.get("version") != "public-conditional-identity-v1" or report.get("sourceSHA256") != SOURCE_SHA256 or report.get("parserRuns") != 0 or report.get("glyphLessonCount") != 0 or report.get("wholeChordLessonCount") != 0:
        raise ValueError("Wrong historical diagnostic scope")
    all_rows = report.get("rows", [])
    if len(all_rows) != 3104 or len({r["id"] for r in all_rows}) != 3104 or Counter(r["arm"] for r in all_rows) != {"isolatedPoints32": 1552, "adjacentSecond32Gap8": 1552}:
        raise ValueError("Historical report incomplete")
    isolated = {tuple(r["sourceIDs"]): r for r in all_rows if r["arm"] == "isolatedPoints32"}
    if len(isolated) != 1552 or set(isolated) != {(sample.identity,) for sample in development}:
        raise ValueError("Historical source-ID cohort mismatch")
    predictions = {}
    for sample in development:
        row = isolated[sample.identity,]
        groups = [list(range(len(sample.strokes)))]
        reading = row["sourceOwnerReading"]
        glyphs = reading["glyphs"]
        if row["writers"] != [sample.writer] or row["sessions"] != [sample.session] or row["expectedTokens"] != [sample.label] or row["sourceOwnerGroups"] != groups or reading["sourceStrokeCount"] != len(sample.strokes) or len(glyphs) != 1 or glyphs[0]["originalStrokeIndexes"] != groups[0] or not glyphs[0]["generic"]:
            raise ValueError("Historical owner/source mismatch")
        predicted = glyphs[0]["generic"][0]["label"]
        if row["oracleTop1Tokens"] != [predicted] or row["oracleGlyphCorrect"] != [predicted == sample.label]:
            raise ValueError("Historical first-rank counters mismatch")
        predictions[sample.identity] = predicted
    if sum(predictions[s.identity] == s.label for s in development) != 1229:
        raise ValueError("Historical isolated reference count changed")
    return predictions


def score(predictions: Path, fit_directory: Path, source: Path, baseline: Path, protocol: Path, output: Path, *, personalization=False):
    # Read the complete frozen blind prediction packet before any labeled source.
    predictions = _file(predictions)
    prediction_bytes = predictions.read_bytes()
    fit_path = _file(fit_directory / "fit-receipt.json")
    fit_bytes = fit_path.read_bytes()
    fit = _json(fit_bytes, "fit receipt")
    protocol = _file(protocol)
    frozen_protocol = _file(fit_directory / "frozen-protocol.md")
    protocol_bytes = protocol.read_bytes()
    code = code_identity()
    if sha256(protocol_bytes) != code[PROTOCOL_PATH] or frozen_protocol.read_bytes() != protocol_bytes:
        raise ValueError("Frozen protocol bytes mismatch")
    weight_paths = {a: _file(fit_directory / "weights" / f"{a}.pt") for a in ARMS}
    weights = {a: sha256(p.read_bytes()) for a, p in weight_paths.items()}
    packet = validate_prediction_packet(prediction_bytes, fit, fit_bytes, code, sha256(protocol_bytes), weights)
    # Freeze first argmax independently of source label/writer joins.
    frozen_predictions = {r["opaqueID"]: {a: argmax_label(r["outputs"][a]["rawLogits"], fit["vocabulary"]) for a in ARMS} for r in packet["rows"]}
    source, baseline = _file(source), _file(baseline)
    paths = {"predictions": predictions, "fitReceipt": fit_path, "source": source, "historicalBaseline": baseline,
        "protocol": protocol, "fitProtocol": frozen_protocol, **{f"weights:{a}": p for a, p in weight_paths.items()}}
    snapshot = {p: sha256(p.read_bytes()) for p in paths.values()}
    # Snapshot the bytes actually validated, not a later re-read that could
    # accidentally accept a concurrently replaced frozen packet/receipt.
    snapshot.update({predictions: sha256(prediction_bytes), fit_path: sha256(fit_bytes), protocol: sha256(protocol_bytes),
        frozen_protocol: sha256(protocol_bytes), **{p: weights[a] for a, p in weight_paths.items()}})
    try:
        _preserved(snapshot, code)
        if snapshot[source] != SOURCE_SHA256 or snapshot[baseline] != BASELINE_SHA256:
            raise ValueError("Pinned source/reference digest mismatch")
        records = load_official_source(source)
        roles = split_writers(records)
        if tuple(fit[k] for k in ("trainingWriters", "developmentWriters", "reservedWriters")) != tuple(list(x) for x in roles):
            raise ValueError("Actual source writer-role partition mismatch")
        development = tuple(r for r in records if r.writer in set(roles[1]))
        if len(development) != 1552 or sorted({r.label for r in records}) != fit["vocabulary"]:
            raise ValueError("Actual development/vocabulary cohort mismatch")
        packet_rows = {r["opaqueID"]: r for r in packet["rows"]}
        if set(packet_rows) != {opaque_id(SOURCE_SHA256, s.identity) for s in development}:
            raise ValueError("Opaque-ID source cohort mismatch")
        historical = _baseline(baseline.read_bytes(), development)
        training_hashes = _hash_sets(fit["trainingInputHashes"])
        rows = []
        for sample in sorted(development, key=lambda s: opaque_id(SOURCE_SHA256, s.identity)):
            oid = opaque_id(SOURCE_SHA256, sample.identity)
            row = packet_rows[oid]
            # Only the authorized eight development writers are feature-encoded.
            hashes = {"rasterSHA256": sha256(rasterize(sample.strokes).pixels),
                "trajectorySHA256": sha256(encode_trajectory(sample.strokes).to_bytes()),
                "normalizedTrajectorySHA256": trajectory_fingerprint(sample)}
            if row["sourceGroups"] != [list(range(len(sample.strokes)))] or any(row[k] != hashes[k] for k in ("rasterSHA256", "trajectorySHA256")):
                raise ValueError("Frozen prediction input/source mismatch")
            predicted = {**frozen_predictions[oid], "historicalCoreML": historical[sample.identity]}
            rows.append({"opaqueID": oid, "sourceID": sample.identity, "writer": sample.writer, "session": sample.session,
                "intended": sample.label, "sourceGroups": row["sourceGroups"], "inputHashes": hashes,
                "predictions": predicted, "correct": {a: p == sample.label for a, p in predicted.items()},
                "noveltyExclusions": _copy_reasons(hashes, training_hashes, "training")})
        novel = [r for r in rows if not r["noveltyExclusions"]]
        report = {"version": "personal-dual-view-score-v1", "scope": SCOPE, "rowCount": len(rows), "arms": list(ARMS),
            "productionEligible": False, "freshWriterEvaluation": False, "naturalChordEvaluation": False,
            "inputSHA256": {role: snapshot[path] for role, path in paths.items()}, "codeSHA256": code,
            "vocabulary": fit["vocabulary"], "vocabularySHA256": fit["vocabularySHA256"], "rows": rows,
            "primary": advancement_gate(rows), "summaries": {a: identity_summary(rows, a) for a in ARMS},
            "secondaryTrajectoryVsRaster": paired_summary(rows, "rasterOnly", "trajectoryOnly"),
            "historicalReference": {"scope": "Pinned prior Core ML source-owner inference; not a matched architecture or fresh gate", "summary": identity_summary(rows, "historicalCoreML")},
            "novelty": {"count": len(novel), "excluded": len(rows) - len(novel), "exclusionReasons": dict(sorted(Counter(reason for r in rows for reason in r["noveltyExclusions"]).items())),
                "summaries": {a: identity_summary(novel, a) for a in ARMS}, "paired": paired_summary(novel, "rasterOnly", "dual")},
            "personalization": _personalize(rows, packet_rows, fit["vocabulary"]) if personalization else None,
            "inputsUnchanged": True}
        _preserved(snapshot, code)
    finally:
        _preserved(snapshot, code)
    # A failed join/scoring/preservation check publishes no success receipt.
    output = Path(output)
    if not output.is_absolute() or ".." in output.parts or output.exists() or output.is_symlink() or output.parent.resolve(strict=True) != output.parent:
        raise ValueError("Output must be a new exclusive canonical directory")
    output.mkdir(mode=0o700)
    with (output / "score.json").open("xb") as handle:
        handle.write(canonical_json_bytes(report))
    print(f"DUAL_VIEW_SCORE rows={len(rows)} writerUnits=8 primaryEligible={report['primary']['nextBlindDevelopmentGateEligible']} personalization={personalization}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("predictions", "fit-directory", "source", "baseline", "protocol", "output"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    parser.add_argument("--personalization", action="store_true")
    args = parser.parse_args()
    score(args.predictions, args.fit_directory, args.source, args.baseline, args.protocol, args.output, personalization=args.personalization)


if __name__ == "__main__":
    main()

"""Fixed residual diagnostic over the frozen dual-view development packet.

Prepare, predict, and score are deliberately separate processes.  This module
never constructs or runs the shared encoder and never grants acceptance or
production authority to a personal rank.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import platform
import stat
from collections import Counter
from pathlib import Path

import numpy as np

from ..contracts import canonical_json_bytes
from ..features import encode_trajectory, rasterize
from . import personal_dual_view_scoring as parent
from .personal_adaptability import sparse_labels
from .personal_residual import ResidualHead, normalized_scores
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers, trajectory_fingerprint

VERSION = "personal-dual-view-residual-diagnostic-v1"
PLAN_VERSION = "personal-dual-view-residual-plan-v1"
PREDICTION_VERSION = "personal-dual-view-residual-predictions-v1"
SCORE_VERSION = "personal-dual-view-residual-score-v1"
SCOPE = "observed-public-uji-dual-residual-descriptive-research-not-production"
REGIMES = ("sparse16", "full97")
PROTOCOL_PATH = "docs/personal-dual-view-residual-diagnostic-protocol-2026-09-30.md"
MODULE_PATH = "recognition_ml/ichart_recognition_ml/research/personal_dual_view_residual.py"
TEST_PATH = "recognition_ml/tests/test_personal_dual_view_residual.py"
RESIDUAL_PATH = "recognition_ml/ichart_recognition_ml/research/personal_residual.py"
SWIFT_RESIDUAL_PATH = "iChart/Recognition/PersonalInkResidualHead.swift"
SELECTOR_PATH = "recognition_ml/ichart_recognition_ml/research/personal_adaptability.py"
CODE_PATHS = tuple(dict.fromkeys(parent.CODE_PATHS + (
    PROTOCOL_PATH, RESIDUAL_PATH, SWIFT_RESIDUAL_PATH, SELECTOR_PATH, MODULE_PATH, TEST_PATH,
)))

FIT_SHA256 = "ce60efb539ce4d0897e0c339e6d1e1d90485ec07798aa1da499047482724a46f"
PARENT_PREDICTION_SHA256 = "06cae336f6bd00960a75669cace55fd6d3400a847b9d2e30602c297de4d27328"
PARENT_SCORE_SHA256 = "898825e57a45bc1467fa17ee7de8bb4407ef3eae7b03c959153400b93d42195c"
DUAL_WEIGHT_SHA256 = "ed722707ad992b6c282dd6f416ac173bc972c7517b1804d72c08f57cbf1a1507"
VOCABULARY_SHA256 = "2fc83d80121b8177598f563b7253ee6bb8de2a38e45fbd825bb2e656c52cfb59"
RESIDUAL_SHA256 = "cd8922f542c1c4dd1f3cd2e7c44e2e677412ded238227780565b2dd99c55959d"
SWIFT_RESIDUAL_SHA256 = "c37df45b299e9013eb26f67e44d96a94b545c90dc949cd24f36426c85e94885f"
SELECTOR_SHA256 = "1f0b981a4bea5119765c5cbfb211ff5fe932b7c7296ea4985a989d05c0fdaaf8"
SPARSE_LABELS = ("!", "E", "F", "L", "T", "Z", "d", "g", "j", "k", "n", "t", "w", "x", "Ó", "á")
ALGORITHM = {
    "baseScoreNormalization": "temperature-one-softmax-all-97-raw-logits",
    "classBalance": "one-over-square-root-label-frequency",
    "correctionAlpha": 1.0,
    "learnerVersion": "personal-residual-ridge-v1",
    "regularization": 0.1,
    "tieOrder": {"baseline": "descending-raw-logit-then-vocabulary-index",
                 "residual": "descending-score-then-label"},
}
HASH_KEYS = {"normalizedTrajectorySHA256", "rasterSHA256", "trajectorySHA256"}
PLAN_FIELDS = {
    "algorithm", "codeSHA256", "developmentWriters", "parentBindings", "protocolSHA256",
    "queryCount", "queryRows", "regimes", "roleGuards", "runtime", "scope",
    "sourceSHA256", "sparseSupportLabels", "supportCount", "supportRows", "version",
    "vocabulary", "vocabularySHA256",
}
SUPPORT_FIELDS = {"embedding", "inputHashes", "label", "opaqueID", "rawLogits", "session", "writer"}
QUERY_FIELDS = SUPPORT_FIELDS - {"label"}
PREDICTION_FIELDS = {
    "algorithm", "codeSHA256", "parentBindings", "planSHA256", "protocolSHA256", "regimes",
    "rowCount", "rows", "runtime", "scope", "supportSets", "version", "vocabulary",
    "vocabularySHA256",
}
RANK_FIELDS = {"label", "score"}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _root() -> Path:
    return Path(__file__).resolve().parents[3]


def _keys(value, expected, name):
    if not isinstance(value, dict) or set(value) != set(expected):
        raise ValueError(f"{name}: missing or unknown fields")
    return value


def _digest(value) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _runtime() -> dict[str, object]:
    return {"numpy": str(np.__version__), "platform": platform.platform(), "python": platform.python_version()}


def code_identity() -> dict[str, str]:
    return {name: sha256(_file(_root() / name).read_bytes()) for name in CODE_PATHS}


def _file(path: Path) -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.is_symlink()
            or path.resolve(strict=True) != path or not stat.S_ISREG(path.stat().st_mode)):
        raise ValueError("Input must be an absolute unaliased regular file")
    return path


def _directory(path: Path) -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.is_symlink()
            or path.resolve(strict=True) != path or not path.is_dir()):
        raise ValueError("Input must be an absolute unaliased directory")
    return path


def _new_directory(path: Path) -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.exists() or path.is_symlink()
            or path.parent.resolve(strict=True) != path.parent):
        raise ValueError("Output must be a new exclusive canonical directory")
    path.mkdir(mode=0o700)
    return path


def _preserved(snapshot: dict[Path, str], code: dict[str, str]) -> None:
    if code_identity() != code or any(sha256(path.read_bytes()) != digest for path, digest in snapshot.items()):
        raise ValueError("Frozen inputs or code changed during the process")


def _row_hashes(sample) -> dict[str, str]:
    return {
        "normalizedTrajectorySHA256": trajectory_fingerprint(sample),
        "rasterSHA256": sha256(rasterize(sample.strokes).pixels),
        "trajectorySHA256": sha256(encode_trajectory(sample.strokes).to_bytes()),
    }


def _valid_feature_row(row, *, support: bool) -> None:
    _keys(row, SUPPORT_FIELDS if support else QUERY_FIELDS, "support row" if support else "query row")
    if (not _digest(row["opaqueID"]) or not isinstance(row["writer"], str) or not row["writer"].startswith("trn_")
            or type(row["session"]) is not int or row["session"] != (1 if support else 2)):
        raise ValueError("Invalid row identity or role")
    hashes = _keys(row["inputHashes"], HASH_KEYS, "input hashes")
    if not all(_digest(value) for value in hashes.values()):
        raise ValueError("Invalid input digest")
    embedding, logits = row["embedding"], row["rawLogits"]
    if (not isinstance(embedding, list) or len(embedding) != 128
            or any(type(x) not in (int, float) or not math.isfinite(x) for x in embedding)
            or abs(math.sqrt(sum(x * x for x in embedding)) - 1) > 1e-4):
        raise ValueError("Invalid unit embedding")
    if (not isinstance(logits, list) or len(logits) != 97
            or any(type(x) not in (int, float) or not math.isfinite(x) or abs(x) > 1e6 for x in logits)):
        raise ValueError("Invalid raw logits")
    if support and (not isinstance(row["label"], str) or len(row["label"]) != 1):
        raise ValueError("Invalid explicit support label")


def validate_plan(payload: bytes, *, expected_code=None, expected_protocol_sha=None) -> dict:
    plan = parent._json(payload, "residual plan")
    _keys(plan, PLAN_FIELDS, "residual plan")
    code = code_identity() if expected_code is None else expected_code
    protocol_sha = code[PROTOCOL_PATH] if expected_protocol_sha is None else expected_protocol_sha
    expected = {
        "version": PLAN_VERSION, "scope": SCOPE, "sourceSHA256": SOURCE_SHA256,
        "protocolSHA256": protocol_sha, "codeSHA256": code, "runtime": _runtime(),
        "algorithm": ALGORITHM, "regimes": list(REGIMES), "queryCount": 776,
        "supportCount": 776, "sparseSupportLabels": list(SPARSE_LABELS),
        "vocabularySHA256": VOCABULARY_SHA256,
        "roleGuards": {"privateInkUsed": False, "productionEligible": False,
                       "reservedWritersUsed": False, "sharedModelInferencePerformed": False},
    }
    if any(plan.get(key) != value for key, value in expected.items()):
        raise ValueError("Plan metadata or bindings changed")
    parents = _keys(plan["parentBindings"], {
        "dualWeightsSHA256", "fitReceiptSHA256", "parentCodeSHA256", "parentPredictionSHA256",
        "parentProtocolSHA256", "parentScoreSHA256",
    }, "parent bindings")
    if (parents["fitReceiptSHA256"] != FIT_SHA256
            or parents["parentPredictionSHA256"] != PARENT_PREDICTION_SHA256
            or parents["parentScoreSHA256"] != PARENT_SCORE_SHA256
            or parents["dualWeightsSHA256"] != DUAL_WEIGHT_SHA256
            or parents["parentProtocolSHA256"] != code[parent.PROTOCOL_PATH]
            or parents["parentCodeSHA256"] != {name: code[name] for name in parent.CODE_PATHS}):
        raise ValueError("Wrong immutable parent bindings")
    vocabulary = plan["vocabulary"]
    if (not isinstance(vocabulary, list) or len(vocabulary) != 97 or sorted(set(vocabulary)) != vocabulary
            or any(not isinstance(label, str) or len(label) != 1 for label in vocabulary)
            or sha256(canonical_json_bytes(vocabulary)) != VOCABULARY_SHA256
            or tuple(sparse_labels(vocabulary)) != SPARSE_LABELS):
        raise ValueError("Wrong vocabulary or sparse selector")
    writers = plan["developmentWriters"]
    if (not isinstance(writers, list) or len(writers) != 8 or writers != sorted(set(writers))
            or any(not isinstance(writer, str) or not writer.startswith("trn_") for writer in writers)):
        raise ValueError("Wrong development-writer role")
    support, queries = plan["supportRows"], plan["queryRows"]
    if not isinstance(support, list) or len(support) != 776 or not isinstance(queries, list) or len(queries) != 776:
        raise ValueError("Plan must contain 776 support and 776 query rows")
    for row in support:
        _valid_feature_row(row, support=True)
    for row in queries:
        _valid_feature_row(row, support=False)
    support_ids = [row["opaqueID"] for row in support]
    query_ids = [row["opaqueID"] for row in queries]
    if (support_ids != sorted(set(support_ids)) or query_ids != sorted(set(query_ids))
            or set(support_ids) & set(query_ids)):
        raise ValueError("Duplicate, overlapping, or unsorted plan identities")
    for writer in writers:
        writer_support = [row for row in support if row["writer"] == writer]
        writer_queries = [row for row in queries if row["writer"] == writer]
        if len(writer_support) != 97 or len(writer_queries) != 97 or sorted(row["label"] for row in writer_support) != vocabulary:
            raise ValueError("Incomplete writer/session plan")
    if set(row["writer"] for row in support + queries) != set(writers):
        raise ValueError("Plan contains a wrong-role writer")
    return plan


def _baseline_rank(vocabulary, scores, raw_logits) -> list[dict[str, object]]:
    if len(vocabulary) != len(scores) or len(scores) != len(raw_logits):
        raise ValueError("Wrong baseline ranking dimensions")
    order = sorted(range(len(vocabulary)), key=lambda index: (-raw_logits[index], index))
    return [{"label": vocabulary[index], "score": float(scores[index])} for index in order]


def predict_residual(support_features, support_logits, support_labels, query_features, query_logits, vocabulary):
    """Return generic and residual ranks without accepting query labels."""
    support_features = np.asarray(support_features, dtype=np.float64)
    query_features = np.asarray(query_features, dtype=np.float64)
    support_logits = np.asarray(support_logits, dtype=np.float64)
    query_logits = np.asarray(query_logits, dtype=np.float64)
    vocabulary = tuple(vocabulary)
    support_labels = tuple(support_labels)
    if (support_features.ndim != 2 or query_features.ndim != 2 or support_features.shape[1:] != (128,)
            or query_features.shape[1:] != (128,) or support_logits.shape != (len(support_features), 97)
            or query_logits.shape != (len(query_features), 97) or len(support_labels) != len(support_features)
            or len(vocabulary) != 97):
        raise ValueError("Wrong residual diagnostic dimensions")
    support_scores = normalized_scores(support_logits)
    query_scores = normalized_scores(query_logits)
    head = ResidualHead.fit(support_features, support_scores, support_labels, vocabulary, regularization=0.1)
    return [{"baselineRanking": _baseline_rank(vocabulary, scores, logits),
             "residualRanking": head.rank(feature, scores)}
            for feature, scores, logits in zip(query_features, query_scores, query_logits)]


def _validate_ranking(value, vocabulary, *, normalized: bool, raw_logits=None) -> None:
    if (not isinstance(value, list) or len(value) != 97
            or any(not isinstance(row, dict) or set(row) != RANK_FIELDS for row in value)):
        raise ValueError("Invalid complete ranking")
    labels = [row["label"] for row in value]
    scores = [row["score"] for row in value]
    if (any(not isinstance(label, str) for label in labels)
            or len(set(labels)) != 97 or set(labels) != set(vocabulary)
            or any(type(score) not in (int, float) or not math.isfinite(score) for score in scores)):
        raise ValueError("Invalid complete ranking")
    score_by_label = dict(zip(labels, scores))
    if normalized:
        if (not isinstance(raw_logits, list) or len(raw_logits) != 97
                or any(type(value) not in (int, float) or not math.isfinite(value) for value in raw_logits)):
            raise ValueError("Invalid baseline logits")
        expected_labels = [vocabulary[index] for index in sorted(
            range(97), key=lambda index: (-raw_logits[index], index))]
    else:
        expected_labels = sorted(vocabulary, key=lambda label: (-score_by_label[label], label))
    if labels != expected_labels:
        raise ValueError("Invalid complete ranking")
    if normalized and (any(not 0 <= row["score"] <= 1 for row in value)
                       or abs(sum(row["score"] for row in value) - 1) > 1e-8):
        raise ValueError("Baseline ranking is not normalized")


def validate_prediction(payload: bytes, plan: dict, plan_bytes: bytes, *, expected_code=None) -> dict:
    packet = parent._json(payload, "residual predictions")
    _keys(packet, PREDICTION_FIELDS, "residual predictions")
    code = code_identity() if expected_code is None else expected_code
    expected = {
        "version": PREDICTION_VERSION, "scope": SCOPE, "algorithm": ALGORITHM,
        "codeSHA256": code, "protocolSHA256": plan["protocolSHA256"], "runtime": _runtime(),
        "planSHA256": sha256(plan_bytes), "parentBindings": plan["parentBindings"],
        "regimes": list(REGIMES), "rowCount": 1552, "vocabulary": plan["vocabulary"],
        "vocabularySHA256": VOCABULARY_SHA256,
    }
    if canonical_json_bytes(plan) != plan_bytes or any(packet.get(key) != value for key, value in expected.items()):
        raise ValueError("Prediction metadata or plan binding changed")
    support_lookup = {row["writer"]: sorted((r for r in plan["supportRows"] if r["writer"] == row["writer"]), key=lambda r: r["label"])
                      for row in plan["supportRows"]}
    query_lookup = {row["opaqueID"]: row for row in plan["queryRows"]}
    support_sets = packet["supportSets"]
    if not isinstance(support_sets, list) or len(support_sets) != 16:
        raise ValueError("Missing support-set bindings")
    expected_sets = []
    for regime in REGIMES:
        for writer in plan["developmentWriters"]:
            rows = support_lookup[writer]
            if regime == "sparse16":
                rows = [row for row in rows if row["label"] in SPARSE_LABELS]
            expected_sets.append({"regime": regime, "supportOpaqueIDs": [row["opaqueID"] for row in rows], "writer": writer})
    if support_sets != expected_sets:
        raise ValueError("Support identities changed")
    rows = packet["rows"]
    if not isinstance(rows, list) or len(rows) != 1552:
        raise ValueError("Incomplete prediction rows")
    keys, grouped = [], {}
    for row in rows:
        _keys(row, {"baselineRanking", "opaqueID", "regime", "residualRanking", "writer"}, "prediction row")
        key = (row["regime"], row["opaqueID"])
        keys.append(key)
        if row["regime"] not in REGIMES or row["opaqueID"] not in query_lookup or row["writer"] != query_lookup[row["opaqueID"]]["writer"]:
            raise ValueError("Prediction row role mismatch")
        _validate_ranking(row["baselineRanking"], plan["vocabulary"], normalized=True,
                          raw_logits=query_lookup[row["opaqueID"]]["rawLogits"])
        _validate_ranking(row["residualRanking"], plan["vocabulary"], normalized=False)
        grouped.setdefault((row["regime"], row["writer"]), []).append(row)
    if keys != sorted(set(keys)) or set(keys) != {(regime, oid) for regime in REGIMES for oid in query_lookup}:
        raise ValueError("Duplicate, unsorted, or missing prediction identity")
    # Recompute from the truth-free plan, before a scorer may open source answers.
    for regime in REGIMES:
        for writer in plan["developmentWriters"]:
            support = support_lookup[writer]
            if regime == "sparse16":
                support = [row for row in support if row["label"] in SPARSE_LABELS]
            queries = sorted((row for row in plan["queryRows"] if row["writer"] == writer), key=lambda row: row["opaqueID"])
            expected_rows = predict_residual(
                [row["embedding"] for row in support], [row["rawLogits"] for row in support],
                [row["label"] for row in support], [row["embedding"] for row in queries],
                [row["rawLogits"] for row in queries], plan["vocabulary"],
            )
            actual = sorted(grouped[regime, writer], key=lambda row: row["opaqueID"])
            for query, expected_row, actual_row in zip(queries, expected_rows, actual):
                if actual_row != {"opaqueID": query["opaqueID"], "writer": writer, "regime": regime, **expected_row}:
                    raise ValueError("Prediction arithmetic does not reproduce the fixed residual")
    return packet


def _parent_paths(fit_directory: Path) -> tuple[Path, Path, dict[str, Path]]:
    fit_directory = _directory(fit_directory)
    fit_path = _file(fit_directory / "fit-receipt.json")
    frozen_protocol = _file(fit_directory / "frozen-protocol.md")
    weights = {arm: _file(fit_directory / "weights" / f"{arm}.pt") for arm in parent.ARMS}
    return fit_path, frozen_protocol, weights


def project_plan_rows(packet_rows, reference_rows):
    """Project truth-free learner inputs; query answers are intentionally unread."""
    packet_lookup = {row["opaqueID"]: row for row in packet_rows}
    if len(packet_lookup) != 1552 or len(packet_rows) != 1552 or len(reference_rows) != 1552:
        raise ValueError("Incomplete parent rows")
    support, queries, seen = [], [], set()
    for metadata in sorted(reference_rows, key=lambda row: row.get("opaqueID", "")):
        if not isinstance(metadata, dict):
            raise ValueError("Invalid parent metadata row")
        oid, writer, session = metadata.get("opaqueID"), metadata.get("writer"), metadata.get("session")
        if (not _digest(oid) or oid in seen or not isinstance(writer, str) or not writer.startswith("trn_")
                or type(session) is not int or session not in (1, 2)):
            raise ValueError("Invalid projected parent role")
        seen.add(oid)
        frozen = packet_lookup.get(oid)
        hashes = metadata.get("inputHashes")
        if (frozen is None or not isinstance(hashes, dict) or set(hashes) != HASH_KEYS
                or not all(_digest(value) for value in hashes.values())
                or frozen["rasterSHA256"] != hashes["rasterSHA256"]
                or frozen["trajectorySHA256"] != hashes["trajectorySHA256"]):
            raise ValueError("Parent input binding changed")
        projected = {"opaqueID": oid, "writer": writer, "session": session, "inputHashes": hashes,
                     "embedding": frozen["outputs"]["dual"]["embedding"],
                     "rawLogits": frozen["outputs"]["dual"]["rawLogits"]}
        if session == 1:
            label = metadata.get("intended")
            if not isinstance(label, str) or len(label) != 1:
                raise ValueError("Missing explicit support label")
            support.append({**projected, "label": label})
        else:
            # Do not read intended/correct/predictions/novelty/sourceID here.
            queries.append(projected)
    return support, queries


def prepare(parent_predictions: Path, fit_directory: Path, parent_score: Path, source: Path,
            protocol: Path, output: Path) -> None:
    parent_predictions, parent_score, source, protocol = map(_file, (parent_predictions, parent_score, source, protocol))
    fit_path, frozen_parent_protocol, weight_paths = _parent_paths(fit_directory)
    prediction_bytes, fit_bytes, score_bytes, source_bytes, protocol_bytes = (
        parent_predictions.read_bytes(), fit_path.read_bytes(), parent_score.read_bytes(),
        source.read_bytes(), protocol.read_bytes())
    frozen_parent_protocol_bytes = frozen_parent_protocol.read_bytes()
    weight_bytes = {arm: path.read_bytes() for arm, path in weight_paths.items()}
    if (sha256(fit_bytes) != FIT_SHA256 or sha256(prediction_bytes) != PARENT_PREDICTION_SHA256
            or sha256(score_bytes) != PARENT_SCORE_SHA256 or sha256(source_bytes) != SOURCE_SHA256):
        raise ValueError("Wrong immutable parent or public source")
    code = code_identity()
    if (sha256(protocol_bytes) != code[PROTOCOL_PATH] or code[RESIDUAL_PATH] != RESIDUAL_SHA256
            or code[SWIFT_RESIDUAL_PATH] != SWIFT_RESIDUAL_SHA256 or code[SELECTOR_PATH] != SELECTOR_SHA256):
        raise ValueError("Frozen diagnostic dependency changed")
    parent_code = parent.code_identity()
    parent_protocol = _file(_root() / parent.PROTOCOL_PATH)
    parent_protocol_bytes = parent_protocol.read_bytes()
    snapshot = {
        parent_predictions: sha256(prediction_bytes), fit_path: sha256(fit_bytes),
        parent_score: sha256(score_bytes), source: sha256(source_bytes), protocol: sha256(protocol_bytes),
        frozen_parent_protocol: sha256(frozen_parent_protocol_bytes),
        parent_protocol: sha256(parent_protocol_bytes),
        **{weight_paths[arm]: sha256(payload) for arm, payload in weight_bytes.items()},
    }
    if frozen_parent_protocol_bytes != parent_protocol_bytes:
        raise ValueError("Parent protocol copy changed")
    weights = {arm: sha256(payload) for arm, payload in weight_bytes.items()}
    fit = parent._json(fit_bytes, "parent fit receipt")
    packet = parent.validate_prediction_packet(
        prediction_bytes, fit, fit_bytes, parent_code, sha256(parent_protocol_bytes), weights)
    if weights["dual"] != DUAL_WEIGHT_SHA256 or fit["vocabularySHA256"] != VOCABULARY_SHA256:
        raise ValueError("Wrong frozen dual model or vocabulary")
    reference = parent._json(score_bytes, "parent score")
    if reference.get("version") != "personal-dual-view-score-v1" or reference.get("rowCount") != 1552:
        raise ValueError("Wrong parent score scope")
    _preserved(snapshot, code)
    records = load_official_source(source)
    roles = split_writers(records)
    if tuple(list(role) for role in roles) != tuple(fit[key] for key in ("trainingWriters", "developmentWriters", "reservedWriters")):
        raise ValueError("Source writer roles changed")
    development = tuple(sample for sample in records if sample.writer in set(roles[1]))
    if (len(development) != 1552 or any(
            sum(sample.writer == writer and sample.session == session for sample in development) != 97
            for writer in roles[1] for session in (1, 2))):
        raise ValueError("Incomplete development source roles")
    support, queries = project_plan_rows(packet["rows"], reference.get("rows", []))
    parent_bindings = {
        "dualWeightsSHA256": DUAL_WEIGHT_SHA256, "fitReceiptSHA256": FIT_SHA256,
        "parentCodeSHA256": parent_code, "parentPredictionSHA256": PARENT_PREDICTION_SHA256,
        "parentProtocolSHA256": sha256(parent_protocol_bytes), "parentScoreSHA256": PARENT_SCORE_SHA256,
    }
    plan = {
        "version": PLAN_VERSION, "scope": SCOPE, "sourceSHA256": SOURCE_SHA256,
        "protocolSHA256": sha256(protocol_bytes), "codeSHA256": code, "runtime": _runtime(),
        "algorithm": ALGORITHM, "parentBindings": parent_bindings, "regimes": list(REGIMES),
        "developmentWriters": list(roles[1]), "vocabulary": fit["vocabulary"],
        "vocabularySHA256": VOCABULARY_SHA256, "sparseSupportLabels": list(SPARSE_LABELS),
        "supportCount": len(support), "queryCount": len(queries), "supportRows": support, "queryRows": queries,
        "roleGuards": {"privateInkUsed": False, "productionEligible": False,
                       "reservedWritersUsed": False, "sharedModelInferencePerformed": False},
    }
    plan_bytes = canonical_json_bytes(plan)
    validate_plan(plan_bytes, expected_code=code, expected_protocol_sha=sha256(protocol_bytes))
    _preserved(snapshot, code)
    destination = _new_directory(output)
    with (destination / "plan.json").open("xb") as handle:
        handle.write(plan_bytes)
    _preserved(snapshot, code)


def predict(plan_path: Path, protocol: Path, output: Path) -> None:
    plan_path, protocol = map(_file, (plan_path, protocol))
    plan_bytes, protocol_bytes = plan_path.read_bytes(), protocol.read_bytes()
    code = code_identity()
    snapshot = {plan_path: sha256(plan_bytes), protocol: sha256(protocol_bytes)}
    if sha256(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Wrong diagnostic protocol")
    plan = validate_plan(plan_bytes, expected_code=code, expected_protocol_sha=sha256(protocol_bytes))
    support_lookup = {writer: sorted((row for row in plan["supportRows"] if row["writer"] == writer), key=lambda row: row["label"])
                      for writer in plan["developmentWriters"]}
    rows, support_sets = [], []
    for regime in REGIMES:
        for writer in plan["developmentWriters"]:
            support = support_lookup[writer]
            if regime == "sparse16":
                support = [row for row in support if row["label"] in SPARSE_LABELS]
            queries = sorted((row for row in plan["queryRows"] if row["writer"] == writer), key=lambda row: row["opaqueID"])
            support_sets.append({"regime": regime, "supportOpaqueIDs": [row["opaqueID"] for row in support], "writer": writer})
            predicted = predict_residual(
                [row["embedding"] for row in support], [row["rawLogits"] for row in support],
                [row["label"] for row in support], [row["embedding"] for row in queries],
                [row["rawLogits"] for row in queries], plan["vocabulary"],
            )
            rows.extend({"opaqueID": query["opaqueID"], "writer": writer, "regime": regime, **result}
                        for query, result in zip(queries, predicted))
    rows.sort(key=lambda row: (row["regime"], row["opaqueID"]))
    packet = {
        "version": PREDICTION_VERSION, "scope": SCOPE, "algorithm": ALGORITHM,
        "protocolSHA256": sha256(protocol_bytes), "codeSHA256": code, "runtime": _runtime(),
        "planSHA256": sha256(plan_bytes), "parentBindings": plan["parentBindings"],
        "regimes": list(REGIMES), "rowCount": len(rows), "supportSets": support_sets,
        "vocabulary": plan["vocabulary"], "vocabularySHA256": VOCABULARY_SHA256, "rows": rows,
    }
    packet_bytes = canonical_json_bytes(packet)
    validate_prediction(packet_bytes, plan, plan_bytes, expected_code=code)
    _preserved(snapshot, code)
    destination = _new_directory(output)
    prediction_path = destination / "predictions.json"
    with prediction_path.open("xb") as handle:
        handle.write(packet_bytes)
    receipt = {
        "artifactKind": "personal-dual-view-residual-prediction-receipt",
        "codeSHA256": code, "passed": True, "planSHA256": sha256(plan_bytes),
        "predictionByteCount": len(packet_bytes), "predictionSHA256": sha256(packet_bytes),
        "rowCount": 1552, "supportSetCount": 16, "version": VERSION,
    }
    _preserved(snapshot, code)
    with (destination / "prediction-receipt.json").open("xb") as handle:
        handle.write(canonical_json_bytes(receipt))
    _preserved(snapshot, code)


def _validate_receipt(payload: bytes, packet_bytes: bytes, plan_bytes: bytes, code: dict[str, str]) -> dict:
    receipt = parent._json(payload, "prediction receipt")
    _keys(receipt, {"artifactKind", "codeSHA256", "passed", "planSHA256", "predictionByteCount",
                    "predictionSHA256", "rowCount", "supportSetCount", "version"}, "prediction receipt")
    expected = {
        "artifactKind": "personal-dual-view-residual-prediction-receipt", "codeSHA256": code,
        "passed": True, "planSHA256": sha256(plan_bytes), "predictionByteCount": len(packet_bytes),
        "predictionSHA256": sha256(packet_bytes), "rowCount": 1552, "supportSetCount": 16,
        "version": VERSION,
    }
    if receipt != expected:
        raise ValueError("Prediction receipt binding changed")
    return receipt


def _regime_report(scored, *, direct_reference: bool) -> dict:
    novel = [row for row in scored if not row["commonNoveltyExclusions"]]
    raw = parent.paired_summary(scored, "generic", "residual")
    novelty = parent.paired_summary(novel, "generic", "residual")
    result = {
        "commonNovelty": {"count": len(novel), "excluded": len(scored) - len(novel),
                          "generic": parent.identity_summary(novel, "generic"),
                          "paired": novelty, "residual": parent.identity_summary(novel, "residual")},
        "generic": parent.identity_summary(scored, "generic"), "rawPaired": raw,
        "residual": parent.identity_summary(scored, "residual"), "rows": scored,
        "worstWriterDelta": min(row["net"] for row in raw["perWriter"].values()),
    }
    if direct_reference:
        result["fullSupportDirectReference"] = {
            "scope": "frozen full97 direct one-hot ridge reference; secondary only",
            "rawPaired": parent.paired_summary(scored, "directFull97", "residual"),
            "commonNoveltyPaired": parent.paired_summary(novel, "directFull97", "residual"),
            "direct": parent.identity_summary(scored, "directFull97"),
        }
    else:
        result["fullSupportDirectReference"] = None
    return result


def _sparse_label_slices(scored) -> dict[str, dict]:
    taught = [row for row in scored if row["intended"] in SPARSE_LABELS]
    untaught = [row for row in scored if row["intended"] not in SPARSE_LABELS]
    if len(taught) != 128 or len(untaught) != 648:
        raise ValueError("Sparse taught/untaught denominators changed")
    return {
        "taught16": {"count": len(taught), "generic": parent.identity_summary(taught, "generic"),
                      "paired": parent.paired_summary(taught, "generic", "residual"),
                      "residual": parent.identity_summary(taught, "residual")},
        "untaught81": {"count": len(untaught), "generic": parent.identity_summary(untaught, "generic"),
                        "paired": parent.paired_summary(untaught, "generic", "residual"),
                        "residual": parent.identity_summary(untaught, "residual")},
    }


def score(plan_path: Path, prediction_directory: Path, parent_score: Path, source: Path,
          protocol: Path, output: Path) -> None:
    plan_path, parent_score, source, protocol = map(_file, (plan_path, parent_score, source, protocol))
    prediction_directory = _directory(prediction_directory)
    prediction_path = _file(prediction_directory / "predictions.json")
    receipt_path = _file(prediction_directory / "prediction-receipt.json")
    # Validate every truth-free byte and recompute every prediction before truth is opened.
    plan_bytes, packet_bytes, receipt_bytes, protocol_bytes = (
        plan_path.read_bytes(), prediction_path.read_bytes(), receipt_path.read_bytes(), protocol.read_bytes())
    code = code_identity()
    blind_snapshot = {
        plan_path: sha256(plan_bytes), prediction_path: sha256(packet_bytes),
        receipt_path: sha256(receipt_bytes), protocol: sha256(protocol_bytes),
    }
    if sha256(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Wrong diagnostic protocol")
    plan = validate_plan(plan_bytes, expected_code=code, expected_protocol_sha=sha256(protocol_bytes))
    packet = validate_prediction(packet_bytes, plan, plan_bytes, expected_code=code)
    _validate_receipt(receipt_bytes, packet_bytes, plan_bytes, code)
    _preserved(blind_snapshot, code)

    score_bytes, source_bytes = parent_score.read_bytes(), source.read_bytes()
    snapshot = {**blind_snapshot, parent_score: sha256(score_bytes), source: sha256(source_bytes)}
    if sha256(score_bytes) != PARENT_SCORE_SHA256 or sha256(source_bytes) != SOURCE_SHA256:
        raise ValueError("Wrong frozen truth/reference parent")
    reference = parent._json(score_bytes, "parent score")
    records = load_official_source(source)
    _preserved(snapshot, code)
    roles = split_writers(records)
    if list(roles[1]) != plan["developmentWriters"] or sorted({sample.label for sample in records}) != plan["vocabulary"]:
        raise ValueError("Truth source roles or vocabulary changed")
    source_queries = {parent.opaque_id(SOURCE_SHA256, sample.identity): sample for sample in records
                      if sample.writer in set(roles[1]) and sample.session == 2}
    plan_queries = {row["opaqueID"]: row for row in plan["queryRows"]}
    direct_rows = reference.get("personalization", {}).get("dual", {}).get("rows", [])
    direct = {row["opaqueID"]: row for row in direct_rows}
    if len(source_queries) != 776 or len(plan_queries) != 776 or len(direct) != 776:
        raise ValueError("Incomplete query truth/reference")
    for oid, sample in source_queries.items():
        row, prior = plan_queries.get(oid), direct.get(oid)
        if (row is None or prior is None or row["writer"] != sample.writer or row["inputHashes"] != _row_hashes(sample)
                or prior.get("writer") != sample.writer or prior.get("session") != 2
                or prior.get("intended") != sample.label or prior.get("inputHashes") != row["inputHashes"]
                or set(prior.get("predictions", {})) != {"generic", "personal"}):
            raise ValueError("Frozen query truth/reference mismatch")
    by_key = {(row["regime"], row["opaqueID"]): row for row in packet["rows"]}
    regimes = {}
    for regime in REGIMES:
        scored = []
        for oid in sorted(source_queries):
            predicted, sample, prior = by_key[regime, oid], source_queries[oid], direct[oid]
            generic, residual = predicted["baselineRanking"][0]["label"], predicted["residualRanking"][0]["label"]
            if generic != prior["predictions"]["generic"]:
                raise ValueError("Shared baseline changed")
            predictions = {"generic": generic, "residual": residual}
            if regime == "full97":
                predictions["directFull97"] = prior["predictions"]["personal"]
            scored.append({
                "commonNoveltyExclusions": prior["noveltyExclusions"],
                "correct": {name: label == sample.label for name, label in predictions.items()},
                "intended": sample.label, "opaqueID": oid, "predictions": predictions,
                "regime": regime, "writer": sample.writer,
            })
        if sum(not row["commonNoveltyExclusions"] for row in scored) != 772:
            raise ValueError("Frozen common novelty cohort changed")
        regimes[regime] = _regime_report(scored, direct_reference=regime == "full97")
        regimes[regime]["supportLabelCount"] = 16 if regime == "sparse16" else 97
        regimes[regime]["supportLabels"] = list(SPARSE_LABELS if regime == "sparse16" else plan["vocabulary"])
        regimes[regime]["labelSlices"] = _sparse_label_slices(scored) if regime == "sparse16" else None
    report = {
        "version": SCORE_VERSION, "scope": SCOPE, "codeSHA256": code,
        "inputSHA256": {"parentScore": PARENT_SCORE_SHA256, "plan": sha256(plan_bytes),
                        "predictionReceipt": sha256(receipt_bytes), "predictions": sha256(packet_bytes),
                        "protocol": sha256(protocol_bytes), "source": SOURCE_SHA256},
        "productionEligible": False, "freshWriterEvaluation": False, "naturalChordEvaluation": False,
        "primaryRegime": "sparse16", "queryCount": 776, "scoredRowCount": 1552, "regimes": regimes,
        "interpretation": "descriptive observed-writer residual diagnostic; no promotion threshold",
    }
    report_bytes = canonical_json_bytes(report)
    _preserved(snapshot, code)
    destination = _new_directory(output)
    with (destination / "score.json").open("xb") as handle:
        handle.write(report_bytes)
    verification = {
        "codeSHA256": code, "commonNoveltyCountPerRegime": 772, "passed": True,
        "planSHA256": sha256(plan_bytes), "predictionSHA256": sha256(packet_bytes),
        "queryCount": 776, "scoreByteCount": len(report_bytes), "scoreSHA256": sha256(report_bytes),
        "scoredRowCount": 1552, "version": VERSION,
    }
    _preserved(snapshot, code)
    with (destination / "verification-receipt.json").open("xb") as handle:
        handle.write(canonical_json_bytes(verification))
    _preserved(snapshot, code)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    for name in ("parent-predictions", "fit-directory", "parent-score", "source", "protocol", "output"):
        prepare_parser.add_argument(f"--{name}", required=True, type=Path)
    predict_parser = commands.add_parser("predict")
    for name in ("plan", "protocol", "output"):
        predict_parser.add_argument(f"--{name}", required=True, type=Path)
    score_parser = commands.add_parser("score")
    for name in ("plan", "prediction-directory", "parent-score", "source", "protocol", "output"):
        score_parser.add_argument(f"--{name}", required=True, type=Path)
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.parent_predictions, args.fit_directory, args.parent_score, args.source, args.protocol, args.output)
    elif args.command == "predict":
        predict(args.plan, args.protocol, args.output)
    else:
        score(args.plan, args.prediction_directory, args.parent_score, args.source, args.protocol, args.output)


if __name__ == "__main__":
    main()

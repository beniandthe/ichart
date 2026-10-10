"""Strict dual-review resolution for leakage-scan candidates.

The output is deterministic preparation for a protected registry service.  It
is intentionally unsigned and cannot qualify a corpus on its own.
"""

import hashlib
import re
import uuid
from pathlib import Path
from typing import Dict, List, Mapping, MutableMapping, Sequence, Set, Tuple

from .contracts import canonical_json_bytes, strict_json_loads
from .errors import ContractError
from .leakage_scan import LEAKAGE_SCAN_REPORT_SCHEMA_VERSION


LEAKAGE_ADJUDICATION_SCHEMA_VERSION = "recognition-leakage-adjudication-v1"
LEAKAGE_ADJUDICATION_PROTOCOL_VERSION = "dual-independent-review-v1"
LEAKAGE_CLUSTER_RECEIPT_SCHEMA_VERSION = "recognition-leakage-cluster-receipt-v1"

DECISION_SAME = "same-geometry"
DECISION_DISTINCT = "distinct-geometry"
DECISIONS = (DECISION_SAME, DECISION_DISTINCT)

_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
_CLUSTER_NAMESPACE = uuid.UUID("f043bc5d-6c55-55e2-a311-faf1f4cfd617")
_ADJUDICATION_FIELDS = {
    "adjudication_protocol_version",
    "decisions",
    "scan_report_sha256",
    "schema_version",
}
_DECISION_FIELDS = {
    "adjudicator_decision",
    "adjudicator_id_hash",
    "final_decision",
    "first_decision",
    "first_reviewer_id_hash",
    "left_sample_id",
    "right_sample_id",
    "second_decision",
    "second_reviewer_id_hash",
}
_SCAN_REPORT_FIELDS = {
    "all_root_pairs_compared",
    "artifact_commitments",
    "authority",
    "candidate_pair_count",
    "candidate_pairs",
    "config",
    "corpus_qualified",
    "feature_schema",
    "labels_inspected",
    "pair_comparison_count",
    "records_sha256",
    "requires_protected_adjudication",
    "root_sample_count",
    "schema_version",
    "status",
    "tier_counts",
}
_CANDIDATE_FIELDS = {
    "left_sample_id",
    "metrics",
    "reasons",
    "right_sample_id",
    "tier",
}
_CANDIDATE_TIERS = ("exact-content", "high-similarity", "manual-review")


def _require_exact_fields(value: Mapping[str, object], fields: Set[str], path: str) -> None:
    missing = sorted(fields.difference(value.keys()))
    unknown = sorted(set(value.keys()).difference(fields))
    if missing:
        raise ContractError("missing_field", path, ", ".join(missing))
    if unknown:
        raise ContractError("unknown_field", path, ", ".join(unknown))


def _require_uuid(value: object, path: str) -> str:
    if not isinstance(value, str):
        raise ContractError("invalid_uuid", path, "must be lowercase canonical UUID text")
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError):
        raise ContractError("invalid_uuid", path, "must be lowercase canonical UUID text")
    if str(parsed) != value:
        raise ContractError("invalid_uuid", path, "must be lowercase canonical UUID text")
    return value


def _require_hash(value: object, path: str) -> str:
    if not isinstance(value, str) or not _HEX_64.fullmatch(value):
        raise ContractError(
            "invalid_sha256", path, "must be 64 lowercase hexadecimal characters"
        )
    return value


def _require_decision(value: object, path: str) -> str:
    if value not in DECISIONS:
        raise ContractError(
            "invalid_leakage_decision",
            path,
            f"expected one of {', '.join(DECISIONS)}",
        )
    return str(value)


def _require_optional_reviewer_hash(value: object, path: str):
    if value is None:
        return None
    return _require_hash(value, path)


def load_canonical_json(path: Path) -> object:
    try:
        payload = path.read_bytes()
    except OSError as error:
        raise ContractError("json_unreadable", str(path), str(error))
    try:
        text = payload.decode("utf-8")
    except UnicodeError as error:
        raise ContractError("json_unreadable", str(path), str(error))
    if not text.endswith("\n") or text.endswith("\n\n"):
        raise ContractError(
            "noncanonical_json", str(path), "expected canonical JSON followed by one newline"
        )
    value = strict_json_loads(text[:-1], str(path))
    if canonical_json_bytes(value) + b"\n" != payload:
        raise ContractError("noncanonical_json", str(path), "bytes are not canonical")
    return value


def scan_report_sha256(report: Mapping[str, object]) -> str:
    return hashlib.sha256(canonical_json_bytes(report)).hexdigest()


def _validate_scan_report(report: object):
    if not isinstance(report, dict):
        raise ContractError("invalid_object", "scan_report", "must be an object")
    _require_exact_fields(report, _SCAN_REPORT_FIELDS, "scan_report")
    if report["schema_version"] != LEAKAGE_SCAN_REPORT_SCHEMA_VERSION:
        raise ContractError(
            "scan_report_schema_mismatch",
            "scan_report.schema_version",
            f"expected {LEAKAGE_SCAN_REPORT_SCHEMA_VERSION}",
        )
    if (
        report["authority"] != "candidate-generation-only"
        or report["corpus_qualified"] is not False
        or report["labels_inspected"] is not False
        or report["all_root_pairs_compared"] is not True
    ):
        raise ContractError(
            "invalid_scan_report_authority",
            "scan_report",
            "the source report must remain exhaustive, label-blind, and candidate-only",
        )
    _require_hash(report["records_sha256"], "scan_report.records_sha256")

    commitments = report["artifact_commitments"]
    if not isinstance(commitments, list) or not commitments:
        raise ContractError(
            "invalid_scan_commitments",
            "scan_report.artifact_commitments",
            "must contain every scanned human root",
        )
    sample_ids = []
    for index, commitment in enumerate(commitments):
        path = f"scan_report.artifact_commitments[{index}]"
        if not isinstance(commitment, dict):
            raise ContractError("invalid_object", path, "must be an object")
        _require_exact_fields(
            commitment,
            {
                "raster_sha256",
                "sample_id",
                "stroke_payload_sha256",
                "trajectory_sha256",
            },
            path,
        )
        sample_ids.append(_require_uuid(commitment["sample_id"], f"{path}.sample_id"))
        for field in ("raster_sha256", "stroke_payload_sha256", "trajectory_sha256"):
            _require_hash(commitment[field], f"{path}.{field}")
    if sample_ids != sorted(sample_ids) or len(set(sample_ids)) != len(sample_ids):
        raise ContractError(
            "noncanonical_scan_commitments",
            "scan_report.artifact_commitments",
            "sample IDs must be unique and sorted",
        )
    if report["root_sample_count"] != len(sample_ids):
        raise ContractError(
            "scan_report_count_mismatch",
            "scan_report.root_sample_count",
            "does not match artifact commitments",
        )
    expected_comparisons = len(sample_ids) * (len(sample_ids) - 1) // 2
    if report["pair_comparison_count"] != expected_comparisons:
        raise ContractError(
            "scan_report_count_mismatch",
            "scan_report.pair_comparison_count",
            f"expected {expected_comparisons}",
        )

    candidates = report["candidate_pairs"]
    if not isinstance(candidates, list):
        raise ContractError(
            "invalid_array", "scan_report.candidate_pairs", "must be an array"
        )
    pairs = []
    tier_counts = {tier: 0 for tier in _CANDIDATE_TIERS}
    membership = set(sample_ids)
    for index, candidate in enumerate(candidates):
        path = f"scan_report.candidate_pairs[{index}]"
        if not isinstance(candidate, dict):
            raise ContractError("invalid_object", path, "must be an object")
        _require_exact_fields(candidate, _CANDIDATE_FIELDS, path)
        left = _require_uuid(candidate["left_sample_id"], f"{path}.left_sample_id")
        right = _require_uuid(candidate["right_sample_id"], f"{path}.right_sample_id")
        if left >= right or left not in membership or right not in membership:
            raise ContractError(
                "invalid_scan_candidate_pair",
                path,
                "pair IDs must be sorted, distinct scanned roots",
            )
        tier = candidate["tier"]
        if tier not in _CANDIDATE_TIERS:
            raise ContractError("invalid_scan_candidate_tier", f"{path}.tier", str(tier))
        if not isinstance(candidate["metrics"], dict) or not isinstance(candidate["reasons"], list):
            raise ContractError(
                "invalid_scan_candidate_evidence", path, "metrics and reasons are required"
            )
        pairs.append((left, right))
        tier_counts[str(tier)] += 1
    if pairs != sorted(pairs) or len(set(pairs)) != len(pairs):
        raise ContractError(
            "noncanonical_scan_candidates",
            "scan_report.candidate_pairs",
            "candidate pairs must be unique and sorted",
        )
    if report["candidate_pair_count"] != len(pairs) or report["tier_counts"] != tier_counts:
        raise ContractError(
            "scan_report_count_mismatch",
            "scan_report.candidate_pairs",
            "candidate or tier counts do not reconcile",
        )
    if report["requires_protected_adjudication"] is not bool(pairs):
        raise ContractError(
            "scan_report_adjudication_mismatch",
            "scan_report.requires_protected_adjudication",
            "must reflect whether candidates exist",
        )
    return tuple(sample_ids), tuple(pairs), {
        pair: str(candidate["tier"]) for pair, candidate in zip(pairs, candidates)
    }


def _validated_decisions(
    adjudication: object,
    expected_scan_sha256: str,
    expected_pairs: Sequence[Tuple[str, str]],
    tiers_by_pair: Mapping[Tuple[str, str], str],
):
    if not isinstance(adjudication, dict):
        raise ContractError("invalid_object", "adjudication", "must be an object")
    _require_exact_fields(adjudication, _ADJUDICATION_FIELDS, "adjudication")
    if adjudication["schema_version"] != LEAKAGE_ADJUDICATION_SCHEMA_VERSION:
        raise ContractError(
            "adjudication_schema_mismatch",
            "adjudication.schema_version",
            f"expected {LEAKAGE_ADJUDICATION_SCHEMA_VERSION}",
        )
    if (
        adjudication["adjudication_protocol_version"]
        != LEAKAGE_ADJUDICATION_PROTOCOL_VERSION
    ):
        raise ContractError(
            "adjudication_protocol_mismatch",
            "adjudication.adjudication_protocol_version",
            f"expected {LEAKAGE_ADJUDICATION_PROTOCOL_VERSION}",
        )
    scan_sha256 = _require_hash(
        adjudication["scan_report_sha256"], "adjudication.scan_report_sha256"
    )
    if scan_sha256 != expected_scan_sha256:
        raise ContractError(
            "adjudication_scan_mismatch",
            "adjudication.scan_report_sha256",
            f"expected {expected_scan_sha256}",
        )
    raw_decisions = adjudication["decisions"]
    if not isinstance(raw_decisions, list):
        raise ContractError("invalid_array", "adjudication.decisions", "must be an array")

    parsed = []
    for index, value in enumerate(raw_decisions):
        path = f"adjudication.decisions[{index}]"
        if not isinstance(value, dict):
            raise ContractError("invalid_object", path, "must be an object")
        _require_exact_fields(value, _DECISION_FIELDS, path)
        left = _require_uuid(value["left_sample_id"], f"{path}.left_sample_id")
        right = _require_uuid(value["right_sample_id"], f"{path}.right_sample_id")
        if left >= right:
            raise ContractError(
                "noncanonical_adjudication_pair", path, "pair IDs must be sorted"
            )
        first_reviewer = _require_hash(
            value["first_reviewer_id_hash"], f"{path}.first_reviewer_id_hash"
        )
        second_reviewer = _require_hash(
            value["second_reviewer_id_hash"], f"{path}.second_reviewer_id_hash"
        )
        if first_reviewer == second_reviewer:
            raise ContractError(
                "reviewers_not_independent",
                path,
                "the first and second reviewer commitments must differ",
            )
        first = _require_decision(value["first_decision"], f"{path}.first_decision")
        second = _require_decision(value["second_decision"], f"{path}.second_decision")
        final = _require_decision(value["final_decision"], f"{path}.final_decision")
        adjudicator = _require_optional_reviewer_hash(
            value["adjudicator_id_hash"], f"{path}.adjudicator_id_hash"
        )
        adjudicator_decision = value["adjudicator_decision"]
        if first == second:
            if adjudicator is not None or adjudicator_decision is not None or final != first:
                raise ContractError(
                    "invalid_agreed_adjudication",
                    path,
                    "reviewer agreement must be final without an adjudicator",
                )
        else:
            if adjudicator is None:
                raise ContractError(
                    "adjudicator_required", path, "reviewer disagreement requires a third reviewer"
                )
            if adjudicator in (first_reviewer, second_reviewer):
                raise ContractError(
                    "adjudicator_not_independent",
                    path,
                    "the adjudicator commitment must differ from both reviewers",
                )
            adjudicated = _require_decision(
                adjudicator_decision, f"{path}.adjudicator_decision"
            )
            if final != adjudicated:
                raise ContractError(
                    "invalid_final_adjudication",
                    path,
                    "the final decision must match the independent adjudicator",
                )
        pair = (left, right)
        if tiers_by_pair.get(pair) == "exact-content" and final != DECISION_SAME:
            raise ContractError(
                "exact_content_marked_distinct",
                path,
                "digest-identical content must remain in one geometry cluster",
            )
        parsed.append((pair, final))

    parsed_pairs = [pair for pair, _ in parsed]
    if parsed_pairs != sorted(parsed_pairs) or len(set(parsed_pairs)) != len(parsed_pairs):
        raise ContractError(
            "noncanonical_adjudication_decisions",
            "adjudication.decisions",
            "decisions must be unique and sorted by pair",
        )
    if tuple(parsed_pairs) != tuple(expected_pairs):
        raise ContractError(
            "adjudication_completeness_mismatch",
            "adjudication.decisions",
            "every and only scanner candidate pair must be resolved",
        )
    return tuple(parsed)


def _find(parent: MutableMapping[str, str], sample_id: str) -> str:
    root = sample_id
    while parent[root] != root:
        root = parent[root]
    while parent[sample_id] != sample_id:
        next_sample = parent[sample_id]
        parent[sample_id] = root
        sample_id = next_sample
    return root


def _union(parent: MutableMapping[str, str], left: str, right: str) -> None:
    left_root = _find(parent, left)
    right_root = _find(parent, right)
    if left_root == right_root:
        return
    retained, merged = sorted((left_root, right_root))
    parent[merged] = retained


def build_leakage_cluster_receipt(
    scan_report: Mapping[str, object], adjudication: Mapping[str, object]
) -> Dict[str, object]:
    sample_ids, candidate_pairs, tiers_by_pair = _validate_scan_report(scan_report)
    scan_sha256 = scan_report_sha256(scan_report)
    decisions = _validated_decisions(
        adjudication,
        scan_sha256,
        candidate_pairs,
        tiers_by_pair,
    )

    parent = {sample_id: sample_id for sample_id in sample_ids}
    for (left, right), decision in decisions:
        if decision == DECISION_SAME:
            _union(parent, left, right)
    for (left, right), decision in decisions:
        if decision == DECISION_DISTINCT and _find(parent, left) == _find(parent, right):
            raise ContractError(
                "transitive_adjudication_conflict",
                f"{left}|{right}",
                "a distinct decision conflicts with transitive same-geometry decisions",
            )

    members_by_root: Dict[str, List[str]] = {}
    for sample_id in sample_ids:
        members_by_root.setdefault(_find(parent, sample_id), []).append(sample_id)
    components = sorted(tuple(sorted(members)) for members in members_by_root.values())
    cluster_id_by_sample = {}
    clusters = []
    for members in components:
        cluster_id = str(
            uuid.uuid5(_CLUSTER_NAMESPACE, scan_sha256 + "|" + "|".join(members))
        )
        clusters.append(
            {"geometry_cluster_id": cluster_id, "sample_ids": list(members)}
        )
        for sample_id in members:
            cluster_id_by_sample[sample_id] = cluster_id

    assignments = [
        {
            "geometry_cluster_id": cluster_id_by_sample[sample_id],
            "sample_id": sample_id,
        }
        for sample_id in sample_ids
    ]
    decision_counts = {DECISION_DISTINCT: 0, DECISION_SAME: 0}
    for _, decision in decisions:
        decision_counts[decision] += 1
    return {
        "adjudication_protocol_version": LEAKAGE_ADJUDICATION_PROTOCOL_VERSION,
        "adjudication_sha256": hashlib.sha256(
            canonical_json_bytes(adjudication)
        ).hexdigest(),
        "all_candidates_resolved": True,
        "assignments": assignments,
        "authority": "unsigned-registry-preparation-only",
        "candidate_pair_count": len(candidate_pairs),
        "cluster_count": len(clusters),
        "clusters": clusters,
        "corpus_qualified": False,
        "decision_counts": decision_counts,
        "records_sha256": scan_report["records_sha256"],
        "registry_signed": False,
        "root_sample_count": len(sample_ids),
        "scan_report_sha256": scan_sha256,
        "schema_version": LEAKAGE_CLUSTER_RECEIPT_SCHEMA_VERSION,
        "status": "leakage-candidates-resolved-for-protected-registry",
    }

"""Freeze fixed same-label HWRT eligibility without fitting or inference."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
from typing import Mapping, Sequence

from ..contracts import canonical_json_bytes
from . import personal_hwrt_stroke_data as parent_data
from . import personal_literal_hwrt_rasters as literal_data


VERSION = "personal-same-label-eligibility-v1"
ELIGIBILITY_VERSION = "personal-same-label-eligibility-rows-v1"
SELECTED_VERSION = "personal-same-label-selected-ids-v1"
PROTOCOL_PATH = "docs/personal-same-label-transfer-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "cbab15675ed16698c0a9cfb32f420df1ef54c80bd6054cd034b793f9ba713061"
ENCODED_RECEIPT_SHA256 = "37c49925e8aff8774bf46c6e7b5e6a1686d68ce6bad37b1c29f36b63cac8e6b5"
ENCODED_ROWS_SHA256 = "a9ac2321281fd6ae32a9c81eed41c11e8448cc8fc9f58b74f0bcd189a0b9cdc1"
HASY_PIXEL_LEDGER_SHA256 = "9fc0a0a41cfff52c73eac50dd470c430901b1a84e5d1739293360e557cbc8336"
HASY_TEST_ROW_COUNT = 17_074
EXPECTED_ROWS = 2_439
EXPECTED_CLASSES = 35
EXPECTED_HASY_DUPLICATE_PATH_ROWS = 34
ROOT = Path(__file__).resolve().parents[3]
CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/research/personal_same_label_eligibility.py",
    "recognition_ml/tests/test_personal_same_label_eligibility.py",
)
HASH_FIELDS = ("rasterSHA256", "normalizedGeometrySHA256")
OLD_FIELDS = {"opaqueID", *HASH_FIELDS}
NEW_REQUIRED = {
    "opaqueID", "sourceRecordID", "sourceSymbolID", "sourceLabel", "sourceRecordIndex",
    "source", "writer", "session", "rasterSHA256", "modelPlaneSHA256",
    "normalizedGeometrySHA256", "encodingFailure",
}
_HASY_PATH = re.compile(r"hasy-data/v2-[0-9]{5,6}\.png")


def _sha(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def code_identity() -> dict[str, str]:
    identity = dict(literal_data.code_identity())
    for relative in CODE_PATHS:
        identity[relative] = _sha(parent_data._read_regular(ROOT / relative))
    if identity[PROTOCOL_PATH] != PROTOCOL_SHA256:
        raise ValueError("Frozen same-label protocol changed")
    return dict(sorted(identity.items()))


def _source_hasy_path(source_record_index: int) -> str:
    if type(source_record_index) is not int or source_record_index < 0:
        raise ValueError("Invalid HWRT training ordinal")
    return f"hasy-data/v2-{source_record_index + HASY_TEST_ROW_COUNT:05d}.png"


def _load_new_rows(directory: Path) -> tuple[list[dict], dict, dict[str, bytes]]:
    directory = Path(directory)
    receipt_bytes = parent_data._read_regular(directory / "data-receipt.json")
    rows_bytes = parent_data._read_regular(directory / "rows.json", maximum=parent_data._MAX_SOURCE_BYTES)
    if _sha(receipt_bytes) != ENCODED_RECEIPT_SHA256 or _sha(rows_bytes) != ENCODED_ROWS_SHA256:
        raise ValueError("Pinned encoded literal receipt or rows changed")
    receipt = parent_data._json(receipt_bytes, "encoded literal receipt")
    value = parent_data._json(rows_bytes, "encoded literal rows")
    if (
        receipt.get("version") != literal_data.VERSION
        or receipt.get("counts", {}).get("rows") != EXPECTED_ROWS
        or receipt.get("counts", {}).get("encodingFailures") != 0
        or receipt.get("claims", {}).get("encodedWithoutFailures") is not True
        or receipt.get("claims", {}).get("eligibilitySelected") is not False
        or receipt.get("codeSHA256") != literal_data.code_identity()
        or receipt.get("artifacts", {}).get("rows.json")
        != {"bytes": len(rows_bytes), "sha256": ENCODED_ROWS_SHA256}
        or set(value) != {"version", "rows"}
        or value.get("version") != literal_data.METADATA_VERSION
        or not isinstance(value.get("rows"), list) or len(value["rows"]) != EXPECTED_ROWS
    ):
        raise ValueError("Encoded literal source contract changed")
    seen, labels, rows = set(), set(), []
    for item in value["rows"]:
        if (
            not isinstance(item, dict) or set(item) != NEW_REQUIRED
            or item.get("source") != "hwrt-literal" or item.get("writer") is not None
            or item.get("session") is not None or item.get("encodingFailure") is not None
            or not isinstance(item.get("sourceLabel"), str) or not item["sourceLabel"]
            or not isinstance(item.get("sourceSymbolID"), str)
            or any(not parent_data._digest(item.get(field)) for field in
                   ("opaqueID", "sourceRecordID", "modelPlaneSHA256", *HASH_FIELDS))
            or item["opaqueID"] in seen
        ):
            raise ValueError("Encoded literal row changed")
        enriched = dict(item)
        enriched["sourceHASYPath"] = _source_hasy_path(item["sourceRecordIndex"])
        rows.append(enriched); seen.add(item["opaqueID"]); labels.add(item["sourceLabel"])
    if len(labels) != EXPECTED_CLASSES:
        raise ValueError("Literal class scope changed")
    return rows, receipt, {"encodedReceipt": receipt_bytes, "encodedRows": rows_bytes}


def project_old_inputs(rows: Sequence[Mapping[str, object]]) -> tuple[dict, ...]:
    projected, seen = [], set()
    for row in rows:
        value = {field: row.get(field) for field in OLD_FIELDS}
        if (
            any(not parent_data._digest(value[field]) for field in OLD_FIELDS)
            or value["opaqueID"] in seen
        ):
            raise ValueError("Prior training input projection changed")
        seen.add(value["opaqueID"]); projected.append(value)
    return tuple(projected)


def _load_old_inputs(directory: Path) -> tuple[tuple[dict, ...], dict[str, bytes]]:
    rows, _, snapshots = literal_data._load_old_training(directory)
    return project_old_inputs(rows), snapshots


def _load_hasy_duplicate_paths(path: Path) -> tuple[set[str], bytes]:
    payload = parent_data._read_regular(Path(path), maximum=parent_data._MAX_SOURCE_BYTES)
    if _sha(payload) != HASY_PIXEL_LEDGER_SHA256:
        raise ValueError("Pinned HASY pixel-duplicate ledger changed")
    try:
        value = json.loads(payload)
    except json.JSONDecodeError as error:
        raise ValueError("Malformed HASY pixel-duplicate ledger") from error
    if not isinstance(value, list):
        raise ValueError("HASY pixel-duplicate ledger must be an array")
    paths = set()
    for group in value:
        members = group.get("pngMembers") if isinstance(group, dict) else None
        if not isinstance(members, list) or len(members) < 2:
            raise ValueError("Malformed HASY pixel-duplicate group")
        for member in members:
            if not isinstance(member, str) or _HASY_PATH.fullmatch(member) is None:
                raise ValueError("Malformed HASY duplicate member path")
            paths.add(member)
    return paths, payload


class _DSU:
    def __init__(self, values):
        self.parent = {value: value for value in values}

    def find(self, value):
        parent = self.parent[value]
        if parent != value:
            self.parent[value] = self.find(parent)
        return self.parent[value]

    def union(self, left, right):
        left, right = self.find(left), self.find(right)
        if left != right:
            smaller, larger = sorted((left, right))
            self.parent[larger] = smaller


def build_eligibility(new_rows: Sequence[Mapping[str, object]],
                      old_inputs: Sequence[Mapping[str, object]],
                      hasy_duplicate_paths: set[str], *, required_labels: Sequence[str]) -> dict:
    if len(set(required_labels)) != len(required_labels) or not required_labels:
        raise ValueError("Required literal labels are empty or duplicated")
    nodes = [("new", row["opaqueID"]) for row in new_rows] + [
        ("old", row["opaqueID"]) for row in old_inputs
    ]
    if len(nodes) != len(set(nodes)):
        raise ValueError("Duplicate source identity in eligibility graph")
    dsu, first = _DSU(nodes), {field: {} for field in HASH_FIELDS}
    indexed = [("new", row) for row in new_rows] + [("old", row) for row in old_inputs]
    for kind, row in indexed:
        required = NEW_REQUIRED | {"sourceHASYPath"} if kind == "new" else OLD_FIELDS
        if not isinstance(row, Mapping) or not required <= set(row):
            raise ValueError("Eligibility graph row schema changed")
        node = (kind, row["opaqueID"])
        for field in HASH_FIELDS:
            digest = row[field]
            if not parent_data._digest(digest):
                raise ValueError("Eligibility graph hash changed")
            previous = first[field].setdefault(digest, node)
            dsu.union(node, previous)

    components = defaultdict(lambda: {"new": [], "old": []})
    for kind, row in indexed:
        components[dsu.find((kind, row["opaqueID"]))][kind].append(row)
    output_rows, component_rows, selected = [], [], []
    for members in components.values():
        if not members["new"]:
            continue
        new = sorted(members["new"], key=lambda row: row["opaqueID"])
        old = sorted(members["old"], key=lambda row: row["opaqueID"])
        node_ids = sorted(
            ["N:" + row["opaqueID"] for row in new] + ["O:" + row["opaqueID"] for row in old]
        )
        component_id = _sha((VERSION + "\0" + "\0".join(node_ids)).encode())
        labels = sorted({row["sourceLabel"] for row in new})
        component_reasons = []
        if old:
            component_reasons.append("component-touches-prior-training-input")
        if any(row["sourceHASYPath"] in hasy_duplicate_paths for row in new):
            component_reasons.append("component-touches-hasy-pixel-duplicate")
        if len(labels) > 1:
            component_reasons.append("component-conflicting-new-labels")
        canonical = new[0]["opaqueID"]
        retained = None if component_reasons else canonical
        for row in new:
            reasons = list(component_reasons)
            if not reasons and row["opaqueID"] != canonical:
                reasons.append("same-label-component-nonrepresentative")
            eligible = not reasons
            if eligible:
                selected.append(row["opaqueID"])
            output_rows.append({
                "opaqueID": row["opaqueID"],
                "sourceRecordID": row["sourceRecordID"],
                "sourceSymbolID": row["sourceSymbolID"],
                "sourceLabel": row["sourceLabel"],
                "sourceRecordIndex": row["sourceRecordIndex"],
                "sourceHASYPath": row["sourceHASYPath"],
                "componentID": component_id,
                "componentNewRowCount": len(new),
                "componentOldRowCount": len(old),
                "canonicalRepresentativeOpaqueID": canonical,
                "retainedRepresentativeOpaqueID": retained,
                "eligible": eligible,
                "exclusionReasons": sorted(reasons),
            })
        component_rows.append({
            "componentID": component_id,
            "newOpaqueIDs": [row["opaqueID"] for row in new],
            "oldOpaqueIDs": [row["opaqueID"] for row in old],
            "newLabels": labels,
            "canonicalRepresentativeOpaqueID": canonical,
            "retainedRepresentativeOpaqueID": retained,
            "componentReasons": sorted(component_reasons),
        })
    output_rows.sort(key=lambda row: row["opaqueID"])
    component_rows.sort(key=lambda row: row["componentID"])
    by_label = {}
    for label in required_labels:
        rows = [row for row in output_rows if row["sourceLabel"] == label]
        eligible = [row for row in rows if row["eligible"]]
        if not rows or not eligible:
            raise ValueError(f"Literal class lost all eligible records: {label}")
        multiplicities = Counter(row["componentNewRowCount"] for row in eligible)
        by_label[label] = {
            "sourceRows": len(rows), "eligibleRows": len(eligible),
            "excludedRows": len(rows) - len(eligible),
            "eligibleComponentMultiplicityCounts": {
                str(size): count for size, count in sorted(multiplicities.items())
            },
        }
    if {row["sourceLabel"] for row in output_rows} != set(required_labels):
        raise ValueError("Unexpected literal label outside the fixed 35-class scope")
    return {
        "version": ELIGIBILITY_VERSION,
        "hashRules": list(HASH_FIELDS),
        "oldLabelsConsumed": False,
        "eligibilityUsesPredictionOutcomes": False,
        "rows": output_rows,
        "components": component_rows,
        "selectedOpaqueIDs": sorted(selected),
        "byClass": dict(sorted(by_label.items())),
    }


def prepare(encoded_data: Path, old_training_data: Path, hasy_pixel_ledger: Path,
            protocol: Path, output: Path) -> dict:
    protocol_bytes = parent_data._read_regular(Path(protocol))
    if _sha(protocol_bytes) != PROTOCOL_SHA256:
        raise ValueError("Wrong frozen same-label protocol")
    code = code_identity()
    new_rows, encoded_receipt, encoded_snapshots = _load_new_rows(encoded_data)
    old_inputs, old_snapshots = _load_old_inputs(old_training_data)
    hasy_paths, hasy_bytes = _load_hasy_duplicate_paths(hasy_pixel_ledger)
    duplicate_path_rows = sum(row["sourceHASYPath"] in hasy_paths for row in new_rows)
    if duplicate_path_rows != EXPECTED_HASY_DUPLICATE_PATH_ROWS:
        raise ValueError("Selected-training HASY duplicate-path coverage changed")
    required_labels = tuple(sorted({row["sourceLabel"] for row in new_rows}))
    if len(required_labels) != EXPECTED_CLASSES:
        raise ValueError("Fixed literal class scope changed")
    result = build_eligibility(new_rows, old_inputs, hasy_paths, required_labels=required_labels)
    selected = {
        "version": SELECTED_VERSION,
        "selectedOpaqueIDs": result["selectedOpaqueIDs"],
        "byClass": result["byClass"],
    }
    destination = parent_data._fresh_output(Path(output))
    parent_data._write(destination / "eligibility.json", canonical_json_bytes(result))
    parent_data._write(destination / "selected-ids.json", canonical_json_bytes(selected))
    artifacts = {
        name: parent_data._artifact(destination / name)
        for name in ("eligibility.json", "selected-ids.json")
    }
    reason_counts = Counter(
        reason for row in result["rows"] for reason in row["exclusionReasons"]
    )
    receipt = {
        "version": VERSION,
        "protocolSHA256": PROTOCOL_SHA256,
        "inputBindings": {
            "encodedDataReceiptSHA256": ENCODED_RECEIPT_SHA256,
            "encodedRowsSHA256": ENCODED_ROWS_SHA256,
            "oldDataReceiptSHA256": literal_data.OLD_DATA_RECEIPT_SHA256,
            "oldTrainingMetadataSHA256": literal_data.OLD_TRAINING_SHA256,
            "hasyPixelDuplicateLedgerSHA256": HASY_PIXEL_LEDGER_SHA256,
            "encodedSourceBindings": encoded_receipt["sourceBindings"],
        },
        "counts": {
            "sourceRows": len(new_rows), "priorTrainingInputRows": len(old_inputs),
            "hasyDuplicatePathRows": duplicate_path_rows,
            "eligibleRows": len(result["selectedOpaqueIDs"]),
            "excludedRows": len(new_rows) - len(result["selectedOpaqueIDs"]),
        },
        "selectedOpaqueIDs": result["selectedOpaqueIDs"],
        "byClass": result["byClass"],
        "exclusionReasonCounts": dict(sorted(reason_counts.items())),
        "artifacts": artifacts,
        "codeSHA256": code,
        "roleGuards": {
            "oldLabelsConsumedByEligibility": False,
            "predictionOutcomesUsed": False,
            "privateDataUsed": False,
            "dedicatedDevelopmentOrQueryArtifactsRead": False,
            "priorTrainingContainsInternalHoldouts": True,
            "sourceRecordsModified": False,
            "modelFittingOrInferencePerformed": False,
        },
    }
    final_new, final_encoded_receipt, final_encoded_snapshots = _load_new_rows(encoded_data)
    final_old, final_old_snapshots = _load_old_inputs(old_training_data)
    final_hasy, final_hasy_bytes = _load_hasy_duplicate_paths(hasy_pixel_ledger)
    if (
        final_new != new_rows or final_encoded_receipt != encoded_receipt
        or final_old != old_inputs or final_hasy != hasy_paths or final_hasy_bytes != hasy_bytes
        or final_encoded_snapshots != encoded_snapshots or final_old_snapshots != old_snapshots
        or code_identity() != code or parent_data._read_regular(protocol) != protocol_bytes
        or any(parent_data._artifact(destination / name) != identity
               for name, identity in artifacts.items())
    ):
        raise ValueError("Bound inputs, code, or artifacts changed before publication")
    parent_data._write(destination / "eligibility-receipt.json", canonical_json_bytes(receipt))
    return receipt


def load_eligibility(directory: Path, expected_receipt_sha256: str) -> tuple[dict, dict]:
    """Load the authenticated fit-side eligibility ledger; never opens source data."""
    if not parent_data._digest(expected_receipt_sha256):
        raise ValueError("Exact eligibility receipt SHA256 is required")
    directory = Path(directory)
    receipt_bytes = parent_data._read_regular(directory / "eligibility-receipt.json")
    if _sha(receipt_bytes) != expected_receipt_sha256:
        raise ValueError("Eligibility receipt SHA256 changed")
    receipt = parent_data._json(receipt_bytes, "same-label eligibility receipt")
    if set(receipt) != {
        "version", "protocolSHA256", "inputBindings", "counts", "selectedOpaqueIDs",
        "byClass", "exclusionReasonCounts", "artifacts", "codeSHA256", "roleGuards",
    } or receipt.get("version") != VERSION or receipt.get("protocolSHA256") != PROTOCOL_SHA256:
        raise ValueError("Eligibility receipt contract changed")
    if receipt.get("codeSHA256") != code_identity():
        raise ValueError("Eligibility code identity changed")
    bindings = receipt.get("inputBindings")
    expected_bindings = {
        "encodedDataReceiptSHA256": ENCODED_RECEIPT_SHA256,
        "encodedRowsSHA256": ENCODED_ROWS_SHA256,
        "oldDataReceiptSHA256": literal_data.OLD_DATA_RECEIPT_SHA256,
        "oldTrainingMetadataSHA256": literal_data.OLD_TRAINING_SHA256,
        "hasyPixelDuplicateLedgerSHA256": HASY_PIXEL_LEDGER_SHA256,
    }
    if (
        not isinstance(bindings, dict)
        or set(bindings) != {*expected_bindings, "encodedSourceBindings"}
        or any(bindings.get(key) != value for key, value in expected_bindings.items())
        or not isinstance(bindings.get("encodedSourceBindings"), dict)
    ):
        raise ValueError("Eligibility input bindings changed")
    if receipt.get("roleGuards") != {
        "oldLabelsConsumedByEligibility": False,
        "predictionOutcomesUsed": False,
        "privateDataUsed": False,
        "dedicatedDevelopmentOrQueryArtifactsRead": False,
        "priorTrainingContainsInternalHoldouts": True,
        "sourceRecordsModified": False,
        "modelFittingOrInferencePerformed": False,
    }:
        raise ValueError("Eligibility role guards changed")
    artifacts = receipt.get("artifacts")
    if not isinstance(artifacts, dict) or set(artifacts) != {
        "eligibility.json", "selected-ids.json"
    }:
        raise ValueError("Eligibility artifact set changed")
    payloads = {}
    for name in sorted(artifacts):
        payload = parent_data._read_regular(directory / name, maximum=parent_data._MAX_SOURCE_BYTES)
        if {"bytes": len(payload), "sha256": _sha(payload)} != artifacts[name]:
            raise ValueError("Eligibility artifact identity changed")
        payloads[name] = parent_data._json(payload, name)
    result, selected = payloads["eligibility.json"], payloads["selected-ids.json"]
    if (
        set(result) != {
            "version", "hashRules", "oldLabelsConsumed", "eligibilityUsesPredictionOutcomes",
            "rows", "components", "selectedOpaqueIDs", "byClass",
        }
        or result.get("version") != ELIGIBILITY_VERSION
        or set(selected) != {"version", "selectedOpaqueIDs", "byClass"}
        or selected.get("version") != SELECTED_VERSION
        or selected.get("selectedOpaqueIDs") != result.get("selectedOpaqueIDs")
        or selected.get("selectedOpaqueIDs") != receipt.get("selectedOpaqueIDs")
        or selected.get("byClass") != result.get("byClass")
        or selected.get("byClass") != receipt.get("byClass")
        or not isinstance(result.get("rows"), list)
    ):
        raise ValueError("Eligibility selection binding changed")
    derived = sorted(
        row.get("opaqueID") for row in result["rows"]
        if isinstance(row, dict) and row.get("eligible") is True
    )
    if derived != result["selectedOpaqueIDs"] or len(derived) != len(set(derived)):
        raise ValueError("Eligibility selected IDs do not match retained rows")
    return result, receipt


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--encoded-data", type=Path, required=True)
    parser.add_argument("--old-training-data", type=Path, required=True)
    parser.add_argument("--hasy-pixel-ledger", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    receipt = prepare(
        args.encoded_data, args.old_training_data, args.hasy_pixel_ledger,
        args.protocol, args.output,
    )
    print(json.dumps({**receipt["counts"], "version": receipt["version"]},
                     sort_keys=True), flush=True)


if __name__ == "__main__":
    main()

import uuid

from ichart_recognition_ml.features import InkPoint, InkStroke, encode_feature_artifacts


def identifier(index: int) -> str:
    return str(uuid.UUID(int=index))


def _label_evidence(label):
    if label is None:
        return {"outcome": "no-read", "canonical_label": None}
    return {"outcome": "canonical-notation", "canonical_label": label}


def valid_feature_payloads(index: int):
    trajectory, raster = encode_feature_artifacts(
        (
            InkStroke(
                (
                    InkPoint(0.0, 0.0, 0.0),
                    InkPoint(8.0 + float(index), 3.0 + float(index), 0.1),
                )
            ),
        )
    )
    return trajectory.to_bytes(), raster.to_bytes()


def record_mapping(
    index: int,
    split: str,
    label="C△7",
    *,
    writer_hash=None,
    trajectory=None,
    raster=None,
):
    sample_id = identifier(index)
    outcome = "canonical-notation" if label is not None else "no-read"
    return {
        "schema_version": "recognition-corpus-record-v2",
        "sample_id": sample_id,
        "writer_id_hash": writer_hash or f"{index:064x}",
        "capture_session_id": identifier(100 + index),
        "split": split,
        "feature_schema_version": "chord-ink-features-v1",
        "label_schema_version": "writer-independent-ground-truth-v2",
        "label_record_id": identifier(200 + index),
        "canonical_label": label,
        "ground_truth_outcome": outcome,
        "legibility_class": "legible-valid" if label is not None else "legible-negative-or-open-set",
        "prompted_intent": _label_evidence(label) if label is not None else {"outcome": "not-applicable", "canonical_label": None},
        "writer_confirmed_intent": _label_evidence(label),
        "first_reader_transcription": {"reader_id_hash": f"{1000 + index:064x}", **_label_evidence(label)},
        "second_reader_transcription": {"reader_id_hash": f"{2000 + index:064x}", **_label_evidence(label)},
        "adjudication": {"state": "readers-agreed", "adjudicator_id_hash": None, "outcome": outcome, "canonical_label": label},
        "ground_truth_frozen": True,
        "source_kind": "consented-human-capture",
        "consent_record_id": identifier(300 + index),
        "consent_scope": "chord-recognition-research-v1",
        "consent_status": "active",
        "consent_ledger_version": "consent-ledger-v1",
        "consent_record_sha256": f"{400 + index:064x}",
        "provenance_registry_version": "provenance-v1",
        "provenance_record_sha256": f"{500 + index:064x}",
        "capture_protocol_version": "writer-independent-capture-v2",
        "chart_style": "simple-chord-sheet" if index % 2 else "rhythm-section-sheet",
        "orientation": "portrait" if index % 2 else "landscape",
        "device_performance_class": "oldest-supported" if index % 2 else "current-reference",
        "pace": ("natural", "fast", "careful")[(index - 1) % 3],
        "size_bucket": ("small", "normal", "large")[(index - 1) % 3],
        "handedness": "left" if index % 2 else "right",
        "pencil_experience": "novice" if index % 2 else "experienced",
        "construction_variation": ("root-first", "modifier-first", "mixed-or-retraced")[(index - 1) % 3],
        "app_build": "study-build-1",
        "recognition_pipeline_version": "dual-view-v1",
        "leakage_check_version": "near-neighbor-v1",
        "lineage_version": "recognition-lineage-v1",
        "root_sample_id": sample_id,
        "parent_sample_id": None,
        "geometry_cluster_id": identifier(600 + index),
        "stroke_payload_sha256": f"{700 + index:064x}",
        "trajectory": trajectory or {"relative_path": f"trajectory/{index}.f32le", "sha256": f"{800 + index:064x}", "byte_count": 10_240, "encoding": "float32-le"},
        "raster": raster or {"relative_path": f"raster/{index}.u8", "sha256": f"{900 + index:064x}", "byte_count": 24_576, "encoding": "uint8-gray"},
    }

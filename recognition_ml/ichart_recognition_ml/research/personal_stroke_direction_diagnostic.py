"""Frozen field-space direction diagnostic for the rejected stroke-field model.

The prediction phase opens only the already-prepared blind five-plane fields.
It first reproduces every saved original vector, then applies the one fixed
algebraic operation ``[occupancy, -tx, -ty, end, start]``.  Truth and the old
score are opened only by the separate scoring phase.  This module does not fit,
average, select, calibrate, or expose a production recognition route.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import platform
from typing import Sequence

import numpy as np
import torch

from ..contracts import canonical_json_bytes
from . import personal_hwrt_stroke_data as data
from . import personal_hwrt_stroke_evaluate as evaluation
from . import personal_hwrt_stroke_train as train
from . import personal_stroke_field as field


VERSION = "personal-stroke-direction-diagnostic-predictions-v1"
SCORE_VERSION = "personal-stroke-direction-diagnostic-score-v1"
TRANSFORM_VERSION = "global-field-direction-reversal-v1"
PROTOCOL_PATH = "docs/personal-stroke-direction-diagnostic-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "6d130183b2d2c29208b55f7361e6dea554ec04facaa8a9d8d5e2d0c7cf291d28"
FIT_RECEIPT_SHA256 = "1ca3d5d29dd292312a386d27c2e0b4a169ac9d1d1fa1bd56acb54685e07216a0"
DATA_RECEIPT_SHA256 = "e1f49705e3bfa249287d13ef011457b057763da17b228e3b4802d13a9150bf3f"
ORIGINAL_PREDICTIONS_SHA256 = "ee3aab3135b609117c9556ffbd119bb26424bffb43b277db7f81116d82c303f0"
ORIGINAL_SCORE_SHA256 = "13cddbf669ced84f13ffd68f947149dc38519bfecae2d88196f2b00eb3fff836"
BATCH_SIZE = 128
ROW_COUNT = 1_987
COPY_EXCLUDED_COUNT = 7
ARMS = evaluation.ARMS
BLIND_FIELDS = evaluation.BLIND_FIELDS
ROOT = evaluation.ROOT

_OWN_CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/research/personal_stroke_direction_diagnostic.py",
    "recognition_ml/tests/test_personal_stroke_direction_diagnostic.py",
)
_TRANSFORM = {
    "version": TRANSFORM_VERSION,
    "occupancy": "unchanged",
    "tangentX": "negated",
    "tangentY": "negated",
    "strokeStart": "source-strokeEnd",
    "strokeEnd": "source-strokeStart",
    "geometryRotation": False,
    "geometryReflection": False,
    "interStrokeOrderChanged": False,
    "timingUsed": False,
}


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _digest(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def code_identity() -> dict[str, str]:
    """Bind the frozen fit/evaluator code plus this diagnostic and protocol."""

    result = dict(evaluation.code_identity())
    for relative in _OWN_CODE_PATHS:
        payload = (ROOT / relative).read_bytes()
        result[relative] = _sha256(payload)
    _require(result[PROTOCOL_PATH] == PROTOCOL_SHA256, "Frozen diagnostic protocol changed")
    return result


def reverse_direction_fields(fields: np.ndarray) -> np.ndarray:
    """Apply the fixed field-space operation without mutating its input."""

    if not isinstance(fields, np.ndarray) or fields.dtype != np.dtype("float32"):
        raise ValueError("Direction diagnostic requires a Float32 NumPy field array")
    if fields.ndim not in (3, 4) or tuple(fields.shape[-3:]) != (
        field.CHANNEL_COUNT,
        field.RASTER_HEIGHT,
        field.RASTER_WIDTH,
    ):
        raise ValueError("Direction diagnostic field shape changed")
    if not np.isfinite(fields).all():
        raise ValueError("Direction diagnostic fields must be finite")
    result = np.empty_like(fields)
    result[..., 0, :, :] = fields[..., 0, :, :]
    result[..., 1, :, :] = -fields[..., 1, :, :]
    result[..., 2, :, :] = -fields[..., 2, :, :]
    result[..., 3, :, :] = fields[..., 4, :, :]
    result[..., 4, :, :] = fields[..., 3, :, :]
    _require(np.array_equal(result[..., 0, :, :], fields[..., 0, :, :]),
             "Direction transform changed occupancy")
    return result


def _field_sha256(value: np.ndarray) -> str:
    array = np.asarray(value)
    _require(array.dtype == np.dtype("float32") and array.shape == (5, 96, 256)
             and np.isfinite(array).all(), "Complete finite field required")
    return _sha256(array.astype("<f4", copy=False).tobytes())


def _result_sha256(value: dict) -> str:
    return _sha256(canonical_json_bytes(value))


def _verify_original_replay(replayed: list[dict], original: list[dict]) -> list[dict[str, str]]:
    """Require both original arms to reproduce before any transformed forward."""

    _require(len(replayed) == len(original) == ROW_COUNT, "Complete original replay required")
    result_hashes: list[dict[str, str]] = []
    for replayed_row, original_row in zip(replayed, original):
        _require({key: replayed_row[key] for key in BLIND_FIELDS}
                 == {key: original_row[key] for key in BLIND_FIELDS},
                 "Original replay row order or blind identity changed")
        _require(set(replayed_row["results"]) == set(original_row["results"]) == set(ARMS),
                 "Original replay arms changed")
        hashes: dict[str, str] = {}
        for arm in ARMS:
            replayed_result = replayed_row["results"][arm]
            original_result = original_row["results"][arm]
            _require(replayed_result == original_result,
                     "Original Float32 output replay differs from frozen prediction")
            hashes[arm] = _result_sha256(original_result)
        result_hashes.append(hashes)
    return result_hashes


def _forward_results(
    model: torch.nn.Module,
    batch: torch.Tensor,
    vocabulary: list[str],
    allowed: list[str],
) -> list[dict]:
    try:
        embeddings, logits = model(batch)
        _require(embeddings.shape == (len(batch), 128) and logits.shape == (len(batch), 102),
                 "Complete transformed 102/128 model output required")
        outputs = []
        for embedding, scores in zip(embeddings.cpu().tolist(), logits.cpu().tolist()):
            try:
                outputs.append(evaluation.result(embedding, scores, vocabulary, allowed))
            except (ValueError, RuntimeError, FloatingPointError) as error:
                outputs.append(evaluation.failure(error))
        return outputs
    except (ValueError, RuntimeError, FloatingPointError) as error:
        return [evaluation.failure(error) for _ in range(len(batch))]


def freeze_transformed(
    models: dict[str, torch.nn.Module],
    fields: np.ndarray,
    inputs: dict,
    allowed: list[str],
    original_rows: list[dict],
    original_result_hashes: list[dict[str, str]],
    *,
    batch_size: int = BATCH_SIZE,
) -> list[dict]:
    """Freeze full transformed vectors after the completed original replay."""

    _require(batch_size == BATCH_SIZE, "The frozen batch size is 128")
    _require(set(models) == set(ARMS) and all(
        not model.training and all(not child.training for child in model.modules())
        for model in models.values()
    ), "Both CPU evaluation models are required")
    rows = inputs["rows"]
    _require(len(fields) == len(rows) == len(original_rows) == len(original_result_hashes) == ROW_COUNT,
             "All 1,987 ordered blind rows are required")
    frozen: list[dict] = []
    with torch.inference_mode():
        for start in range(0, ROW_COUNT, batch_size):
            original = np.asarray(fields[start:start + batch_size]).copy()
            _require(original.dtype == np.dtype("float32") and original.shape[1:] == (5, 96, 256)
                     and np.isfinite(original).all(), "Finite unchanged field batch required")
            for offset, source_field in enumerate(original):
                source_row = rows[start + offset]
                raster = np.rint(source_field[0] * np.float32(255.0)).astype(np.uint8)
                _require(np.array_equal(source_field[0], raster.astype(np.float32) / np.float32(255.0))
                         and _sha256(raster.tobytes()) == source_row["rasterSHA256"]
                         and _field_sha256(source_field) == source_row["fieldSHA256"],
                         "Original blind field identity changed")
            transformed = reverse_direction_fields(original)
            _require(reverse_direction_fields(transformed).tobytes() == original.tobytes(),
                     "Direction transform is not an exact involution")
            tensor = torch.from_numpy(transformed)
            arm_outputs = {
                arm: _forward_results(models[arm], tensor, inputs["vocabulary"], allowed)
                for arm in ARMS
            }
            for offset, transformed_field in enumerate(transformed):
                index = start + offset
                transformed_results = {arm: arm_outputs[arm][offset] for arm in ARMS}
                _require(transformed_results["rasterControl"]
                         == original_rows[index]["results"]["rasterControl"],
                         "Image-only control changed under auxiliary-channel reversal")
                frozen.append({
                    **rows[index],
                    "originalResultSHA256": original_result_hashes[index],
                    "transformedFieldSHA256": _field_sha256(transformed_field),
                    "transformedResults": transformed_results,
                })
    return frozen


def _validate_output(value: dict, vocabulary: list[str], allowed: list[str]) -> None:
    if value.get("failure") is None:
        _require(value == evaluation.result(
            value["embedding"], value["rawLogits"], vocabulary, allowed
        ), "Transformed numerical vector/hash/projection mismatch")
    else:
        _require(isinstance(value.get("failure"), str) and value["failure"]
                 and set(value) == set(evaluation.failure(ValueError()))
                 and all(value[key] is None for key in value if key != "failure"),
                 "Incomplete transformed failure retention")


def validate_packet(
    packet: dict,
    original: dict,
    receipt: dict,
    inputs: dict,
    fields: np.ndarray | None = None,
) -> None:
    evaluation.validate_packet(original, receipt, inputs)
    _require(packet["version"] == VERSION and packet["scope"]
             == "reused-public-field-direction-sensitivity-diagnostic-only"
             and packet["protocolSHA256"] == PROTOCOL_SHA256
             and packet["codeSHA256"] == code_identity()
             and packet["originalPredictionsSHA256"] == ORIGINAL_PREDICTIONS_SHA256
             and packet["originalPredictionsCodeSHA256"] == original["codeSHA256"]
             and packet["fitReceiptSHA256"] == FIT_RECEIPT_SHA256
             and packet["dataReceiptSHA256"] == DATA_RECEIPT_SHA256
             and packet["inputsSHA256"] == evaluation.artifact_sha(receipt, "inputs.json")
             and packet["fieldsSHA256"] == evaluation.artifact_sha(receipt, "fields.npy")
             and packet["truthSHA256"] == evaluation.artifact_sha(receipt, "truth.json")
             and packet["weightsSHA256"] == original["weightsSHA256"]
             and packet["finalStateSHA256"] == original["finalStateSHA256"]
             and packet["vocabulary"] == inputs["vocabulary"] == original["vocabulary"]
             and packet["allowedLabels"] == original["allowedLabels"]
             and packet["transform"] == _TRANSFORM and packet["batchSize"] == BATCH_SIZE
             and packet["originalReplayVerified"] is True
             and packet["originalReplayRowCount"] == ROW_COUNT,
             "Direction-diagnostic packet binding changed")
    _require(len(packet["rows"]) == len(original["rows"]) == ROW_COUNT,
             "Complete transformed row set required")
    if fields is not None:
        _require(len(fields) == ROW_COUNT, "Complete source field array required")
    row_keys = BLIND_FIELDS | {
        "originalResultSHA256", "transformedFieldSHA256", "transformedResults"
    }
    for index, (row, original_row, blind_row) in enumerate(
        zip(packet["rows"], original["rows"], inputs["rows"])
    ):
        _require(set(row) == row_keys
                 and {key: row[key] for key in BLIND_FIELDS} == blind_row
                 and {key: original_row[key] for key in BLIND_FIELDS} == blind_row
                 and set(row["originalResultSHA256"]) == set(row["transformedResults"]) == set(ARMS)
                 and _digest(row["transformedFieldSHA256"]),
                 "Transformed opaque row order/schema changed")
        for arm in ARMS:
            _require(row["originalResultSHA256"][arm]
                     == _result_sha256(original_row["results"][arm]),
                     "Original result commitment changed")
            _validate_output(row["transformedResults"][arm], packet["vocabulary"], packet["allowedLabels"])
        _require(row["transformedResults"]["rasterControl"]
                 == original_row["results"]["rasterControl"],
                 "Image-only control output changed")
        if fields is not None:
            source = np.asarray(fields[index]).copy()
            transformed = reverse_direction_fields(source)
            _require(_field_sha256(transformed) == row["transformedFieldSHA256"]
                     and np.array_equal(source[0], transformed[0]),
                     "Transformed field commitment changed")


def predict(
    data_dir: Path,
    fit_dir: Path,
    original_predictions: Path,
    output: Path,
    *,
    data_receipt_sha256: str,
    fit_receipt_sha256: str,
    original_predictions_sha256: str,
) -> str:
    """Replay original vectors first, then freeze the one transformed pass."""

    _require(data_receipt_sha256 == DATA_RECEIPT_SHA256
             and fit_receipt_sha256 == FIT_RECEIPT_SHA256
             and original_predictions_sha256 == ORIGINAL_PREDICTIONS_SHA256,
             "Only the frozen rejected stroke-field run is permitted")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    diagnostic_code = code_identity()
    original, original_bytes = evaluation.read_json(
        original_predictions, ORIGINAL_PREDICTIONS_SHA256
    )
    models, fit_receipt = train.load_fitted_models(Path(fit_dir), FIT_RECEIPT_SHA256)
    receipt, receipt_bytes = evaluation.read_json(
        Path(data_dir) / "data-receipt.json", DATA_RECEIPT_SHA256
    )
    fields, inputs, loaded_receipt = data.load_development_inputs(Path(data_dir))
    _require(loaded_receipt == receipt and original["fitReceiptSHA256"] == FIT_RECEIPT_SHA256
             and original["dataReceiptSHA256"] == DATA_RECEIPT_SHA256
             and fit_receipt == original["fitReceipt"],
             "Frozen original model/data binding changed")
    evaluation.validate_inputs(inputs)
    evaluation.validate_packet(original, receipt, inputs)
    states = {arm: train._state_digest(model.state_dict()) for arm, model in models.items()}
    _require(states == original["finalStateSHA256"], "Loaded final model states changed")

    # This complete replay deliberately finishes before the first transformed
    # model call.  It is the chronology gate for the counterfactual.
    replayed = evaluation.freeze_forward(
        models, fields, inputs, original["allowedLabels"], batch_size=BATCH_SIZE
    )
    replay_hashes = _verify_original_replay(replayed, original["rows"])
    transformed_rows = freeze_transformed(
        models,
        fields,
        inputs,
        original["allowedLabels"],
        original["rows"],
        replay_hashes,
        batch_size=BATCH_SIZE,
    )
    _require(states == {arm: train._state_digest(model.state_dict()) for arm, model in models.items()},
             "Direction diagnostic changed model or batch-normalization state")

    _, fit_after = train.load_fitted_models(Path(fit_dir), FIT_RECEIPT_SHA256)
    fields_after, inputs_after, receipt_after = data.load_development_inputs(Path(data_dir))
    _require(fit_after == fit_receipt and inputs_after == inputs and receipt_after == receipt
             and fields_after.shape == fields.shape
             and evaluation.read_json(original_predictions, ORIGINAL_PREDICTIONS_SHA256)[1] == original_bytes
             and evaluation.read_json(Path(data_dir) / "data-receipt.json", DATA_RECEIPT_SHA256)[1]
             == receipt_bytes and code_identity() == diagnostic_code,
             "Frozen sources, model, or diagnostic code changed during prediction")
    packet = {
        "version": VERSION,
        "scope": "reused-public-field-direction-sensitivity-diagnostic-only",
        "protocolSHA256": PROTOCOL_SHA256,
        "codeSHA256": diagnostic_code,
        "originalPredictionsSHA256": ORIGINAL_PREDICTIONS_SHA256,
        "originalPredictionsCodeSHA256": original["codeSHA256"],
        "fitReceiptSHA256": FIT_RECEIPT_SHA256,
        "dataReceiptSHA256": DATA_RECEIPT_SHA256,
        "inputsSHA256": original["inputsSHA256"],
        "fieldsSHA256": original["fieldsSHA256"],
        "truthSHA256": original["truthSHA256"],
        "weightsSHA256": original["weightsSHA256"],
        "finalStateSHA256": states,
        "vocabulary": inputs["vocabulary"],
        "allowedLabels": original["allowedLabels"],
        "transform": _TRANSFORM,
        "batchSize": BATCH_SIZE,
        "originalReplayVerified": True,
        "originalReplayRowCount": ROW_COUNT,
        "rows": transformed_rows,
        "runtime": {
            "python": platform.python_version(),
            "numpy": str(np.__version__),
            "torch": str(torch.__version__),
            "cpuThreads": 4,
            "deterministicAlgorithms": True,
            "batchNormalizationUpdates": 0,
        },
        "fitPerformed": False,
        "truthOpened": False,
        "sourceGeometryOpened": False,
        "privateInkUsed": False,
        "reservedWriterInferencePerformed": False,
        "freshValidation": False,
        "liveRecognitionChanged": False,
        "productionEligible": False,
    }
    validate_packet(packet, original, receipt, inputs, fields)
    return evaluation.write_exclusive(
        output, packet, (data_dir, fit_dir, original_predictions)
    )


def _direction_summary(rows: list[dict], arm: str) -> dict:
    _require(arm in ARMS, "Unknown diagnostic arm")
    original = [row["results"][arm] for row in rows]
    transformed = [row["transformedResults"][arm] for row in rows]
    original_correct = [value["rawTop1"] == row["label"] for value, row in zip(original, rows)]
    transformed_correct = [value["rawTop1"] == row["label"] for value, row in zip(transformed, rows)]
    original_domain_correct = [value["domainTop1"] == row["label"] for value, row in zip(original, rows)]
    transformed_domain_correct = [value["domainTop1"] == row["label"] for value, row in zip(transformed, rows)]
    comparable = [a["failure"] is None and b["failure"] is None for a, b in zip(original, transformed)]
    logit_max, embedding_max = 0.0, 0.0
    for include, before, after in zip(comparable, original, transformed):
        if include:
            logit_max = max(logit_max, float(np.max(np.abs(
                np.asarray(before["rawLogits"], dtype=np.float32)
                - np.asarray(after["rawLogits"], dtype=np.float32)
            ))))
            embedding_max = max(embedding_max, float(np.max(np.abs(
                np.asarray(before["embedding"], dtype=np.float32)
                - np.asarray(after["embedding"], dtype=np.float32)
            ))))
    return {
        "count": len(rows),
        "originalInvalid": sum(value["failure"] is not None for value in original),
        "transformedInvalid": sum(value["failure"] is not None for value in transformed),
        "comparable": sum(comparable),
        "rawTop1Changed": sum(a["rawTop1"] != b["rawTop1"] for a, b in zip(original, transformed)),
        "permittedOutputChanged": sum(a["domainTop1"] != b["domainTop1"] for a, b in zip(original, transformed)),
        "logitsFloat32Changed": sum(a["logitsSHA256"] != b["logitsSHA256"] for a, b in zip(original, transformed)),
        "embeddingsFloat32Changed": sum(a["embeddingSHA256"] != b["embeddingSHA256"] for a, b in zip(original, transformed)),
        "maximumAbsoluteLogitChange": logit_max,
        "maximumAbsoluteEmbeddingChange": embedding_max,
        "originalRawCorrect": sum(original_correct),
        "transformedRawCorrect": sum(transformed_correct),
        "rawCorrections": sum(not a and b for a, b in zip(original_correct, transformed_correct)),
        "rawRegressions": sum(a and not b for a, b in zip(original_correct, transformed_correct)),
        "originalPermittedCorrect": sum(original_domain_correct),
        "transformedPermittedCorrect": sum(transformed_domain_correct),
        "permittedCorrections": sum(not a and b for a, b in zip(original_domain_correct, transformed_domain_correct)),
        "permittedRegressions": sum(a and not b for a, b in zip(original_domain_correct, transformed_domain_correct)),
        "originalPermittedWrong": sum(value["domainTop1"] is not None and not correct
                                      for value, correct in zip(original, original_domain_correct)),
        "transformedPermittedWrong": sum(value["domainTop1"] is not None and not correct
                                         for value, correct in zip(transformed, transformed_domain_correct)),
        "originalNoRead": sum(value["domainTop1"] is None for value in original),
        "transformedNoRead": sum(value["domainTop1"] is None for value in transformed),
        "noReadToWrong": sum(a["domainTop1"] is None and b["domainTop1"] is not None
                             and b["domainTop1"] != row["label"]
                             for row, a, b in zip(rows, original, transformed)),
    }


def _cohort(rows: list[dict]) -> dict[str, dict]:
    return {arm: _direction_summary(rows, arm) for arm in ARMS}


def summarize(rows: list[dict], old_allowed: list[str]) -> dict:
    uji = [row for row in rows if row["source"] == "uji"]
    hwrt = [row for row in rows if row["source"] == "hwrt"]
    return {
        "uji": _cohort(uji),
        "ujiChordFragment41": _cohort([row for row in uji if row["label"] in old_allowed]),
        "ujiOutOfDomain": _cohort([row for row in uji if row["label"] not in old_allowed]),
        "hwrt": _cohort(hwrt),
        "writers": {
            writer: _cohort([row for row in uji if row["writer"] == writer])
            for writer in evaluation.WRITERS
        },
        "mappedShapes": {
            label: _cohort([row for row in hwrt if row["label"] == label])
            for label in evaluation.NOVEL
        },
    }


def _join_transformed(original_rows: list[dict], transformed_rows: list[dict]) -> list[dict]:
    _require(len(original_rows) == len(transformed_rows) == ROW_COUNT,
             "Complete scored direction rows required")
    joined = []
    for original_row, transformed_row in zip(original_rows, transformed_rows):
        _require({key: transformed_row[key] for key in BLIND_FIELDS}
                 == {key: original_row[key] for key in BLIND_FIELDS},
                 "Scored direction row identity changed")
        joined.append({**original_row, "transformedResults": transformed_row["transformedResults"]})
    return joined


def _thin_row(row: dict) -> dict:
    return {
        "opaqueID": row["opaqueID"],
        "source": row["source"],
        "writer": row["writer"],
        "session": row["session"],
        "nativeSymbolID": row["nativeSymbolID"],
        "label": row["label"],
        "copyReasons": row["copyReasons"],
        "arms": {
            arm: {
                "originalFailure": row["results"][arm]["failure"],
                "transformedFailure": row["transformedResults"][arm]["failure"],
                "originalRawTop1": row["results"][arm]["rawTop1"],
                "transformedRawTop1": row["transformedResults"][arm]["rawTop1"],
                "originalDomainTop1": row["results"][arm]["domainTop1"],
                "transformedDomainTop1": row["transformedResults"][arm]["domainTop1"],
            }
            for arm in ARMS
        },
    }


def score(
    predictions: Path,
    original_predictions: Path,
    original_score: Path,
    data_dir: Path,
    output: Path,
    *,
    predictions_sha256: str,
    original_predictions_sha256: str,
    original_score_sha256: str,
    data_receipt_sha256: str,
) -> str:
    """Authenticate frozen outputs first; only then open old truth and score."""

    _require(original_predictions_sha256 == ORIGINAL_PREDICTIONS_SHA256
             and original_score_sha256 == ORIGINAL_SCORE_SHA256
             and data_receipt_sha256 == DATA_RECEIPT_SHA256,
             "Only the frozen rejected stroke-field evidence is permitted")
    packet, packet_bytes = evaluation.read_json(predictions, predictions_sha256)
    original, original_bytes = evaluation.read_json(
        original_predictions, ORIGINAL_PREDICTIONS_SHA256
    )
    receipt, receipt_bytes = evaluation.read_json(
        Path(data_dir) / "data-receipt.json", DATA_RECEIPT_SHA256
    )
    fields, inputs, loaded_receipt = data.load_development_inputs(Path(data_dir))
    _require(loaded_receipt == receipt, "Loaded development receipt changed")
    evaluation.validate_inputs(inputs)
    validate_packet(packet, original, receipt, inputs, fields)

    # The authenticated packet and all blind field commitments are complete at
    # this point.  No scoring artifact is opened above this line.
    truth, truth_bytes = evaluation.read_json(
        Path(data_dir) / "truth.json", packet["truthSHA256"]
    )
    original_score_value, original_score_bytes = evaluation.read_json(
        original_score, ORIGINAL_SCORE_SHA256
    )
    original_rows = evaluation.join_truth(original, truth)
    _require(original_score_value["predictionsSHA256"] == ORIGINAL_PREDICTIONS_SHA256
             and original_score_value["dataReceiptSHA256"] == DATA_RECEIPT_SHA256
             and original_score_value["truthSHA256"] == packet["truthSHA256"]
             and original_score_value["rows"] == original_rows,
             "Original score does not match the authenticated source rows")
    rows = _join_transformed(original_rows, packet["rows"])
    excluded = [row for row in rows if row["copyReasons"]]
    _require(len(excluded) == COPY_EXCLUDED_COUNT,
             "The existing seven-row copy exclusion changed")
    kept = [row for row in rows if not row["copyReasons"]]
    old_allowed = original["domain"]["allowedLabels"]
    raw = summarize(rows, old_allowed)
    no_copy = summarize(kept, old_allowed)
    original_gains = [
        row for row in rows
        if row["results"]["rasterControl"]["rawTop1"] != row["label"]
        and row["results"]["strokeField"]["rawTop1"] == row["label"]
    ]
    original_harms = [
        row for row in rows
        if row["results"]["rasterControl"]["rawTop1"] == row["label"]
        and row["results"]["strokeField"]["rawTop1"] != row["label"]
    ]
    report = {
        "version": SCORE_VERSION,
        "scope": "reused-public-field-direction-sensitivity-diagnostic-only",
        "protocolSHA256": PROTOCOL_SHA256,
        "predictionsSHA256": predictions_sha256,
        "originalPredictionsSHA256": ORIGINAL_PREDICTIONS_SHA256,
        "originalScoreSHA256": ORIGINAL_SCORE_SHA256,
        "dataReceiptSHA256": DATA_RECEIPT_SHA256,
        "truthSHA256": packet["truthSHA256"],
        "codeSHA256": packet["codeSHA256"],
        "raw": raw,
        "inputCopyUnionExcluded": no_copy,
        "copyExcludedCount": len(excluded),
        "copyExcludedOpaqueIDs": [row["opaqueID"] for row in excluded],
        "originalArmComparisonCohorts": {
            source: {
                "rasterWrongStrokeCorrect": _cohort([
                    row for row in original_gains if row["source"] == source
                ]),
                "rasterCorrectStrokeWrong": _cohort([
                    row for row in original_harms if row["source"] == source
                ]),
            }
            for source in ("uji", "hwrt")
        },
        "rows": [_thin_row(row) for row in rows],
        "diagnosticOnly": True,
        "advancementDecision": None,
        "fitPerformed": False,
        "freshValidation": False,
        "causalAttributionEstablished": False,
        "liveRecognitionChanged": False,
        "productionEligible": False,
    }
    _require(evaluation.read_json(predictions, predictions_sha256)[1] == packet_bytes
             and evaluation.read_json(original_predictions, ORIGINAL_PREDICTIONS_SHA256)[1]
             == original_bytes
             and evaluation.read_json(original_score, ORIGINAL_SCORE_SHA256)[1]
             == original_score_bytes
             and evaluation.read_json(Path(data_dir) / "data-receipt.json", DATA_RECEIPT_SHA256)[1]
             == receipt_bytes
             and evaluation.read_json(Path(data_dir) / "truth.json", packet["truthSHA256"])[1]
             == truth_bytes and code_identity() == packet["codeSHA256"],
             "Frozen inputs or diagnostic code changed during scoring")
    return evaluation.write_exclusive(
        output, report, (predictions, original_predictions, original_score, data_dir)
    )


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    predict_parser = commands.add_parser("predict")
    for name in (
        "data", "data-receipt-sha256", "fit", "fit-receipt-sha256",
        "original-predictions", "original-predictions-sha256", "output",
    ):
        predict_parser.add_argument("--" + name, required=True)
    score_parser = commands.add_parser("score")
    for name in (
        "predictions", "predictions-sha256", "original-predictions",
        "original-predictions-sha256", "original-score", "original-score-sha256",
        "data", "data-receipt-sha256", "output",
    ):
        score_parser.add_argument("--" + name, required=True)
    values = vars(parser.parse_args(argv))
    command = values.pop("command")
    if command == "predict":
        predict(values.pop("data"), values.pop("fit"), values.pop("original_predictions"),
                values.pop("output"), **values)
    else:
        score(values.pop("predictions"), values.pop("original_predictions"),
              values.pop("original_score"), values.pop("data"), values.pop("output"), **values)


if __name__ == "__main__":
    main()

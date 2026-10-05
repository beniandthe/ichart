"""Writer-disjoint development-only comparison for learned architectures.

This module is deliberately unable to inspect calibration or sealed feature
bytes. It compares frozen model families by held-out development writer and
emits descriptive selection evidence only; it cannot calibrate, promote, or
authorize a runtime artifact.
"""

from __future__ import annotations

import hashlib
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, Mapping, Sequence, Tuple

from .contracts import (
    CorpusRecord,
    CorpusSupervisionKind,
    canonical_json_bytes,
    records_digest,
    strict_json_loads,
)
from .dataset import (
    PipelineRole,
    assert_exact_role,
    load_numpy_feature_batch,
    require_optional_dependency,
    select_role_records,
)
from .decode import decode_factor_logits
from .errors import ContractError, OperationRefusedError
from .models.factory import MODEL_ARCHITECTURE_IDS, candidate_model_factory
from .models.output_contract import (
    FactorLogits,
    OUTPUT_CONTRACT_VERSION,
    OUTPUT_HEADS,
)
from .schema import FEATURE_SCHEMA
from .selection_contract import BOUND_DEVELOPMENT_SELECTION_AUTHORITY
from .train_pipeline import (
    CATEGORICAL_CLASS_REWEIGHTING_INVERSE_FREQUENCY_V1,
    CATEGORICAL_CLASS_REWEIGHTING_NONE,
    LOSS_NORMALIZATION_CONTRACT_VERSION,
    TRAJECTORY_AUGMENTATION_CONTRACT_VERSION,
    TrainingConfig,
    fit_development_partition,
)


DEVELOPMENT_COMPARISON_SCHEMA_VERSION = (
    "chord-ink-development-writer-comparison-v4"
)
DEVELOPMENT_FOLD_ASSIGNMENT_VERSION = (
    "chord-ink-development-writer-fold-assignment-v1"
)
DEVELOPMENT_SELECTION_RANKING_VERSION = (
    "writer-macro-balanced-accuracy-then-frozen-candidate-order-v1"
)
_CANDIDATE_SPECS = tuple(
    (
        architecture_id
        if class_reweighting == CATEGORICAL_CLASS_REWEIGHTING_NONE
        else architecture_id + "+categorical-inverse-frequency-v1",
        architecture_id,
        class_reweighting,
    )
    for architecture_id in MODEL_ARCHITECTURE_IDS
    for class_reweighting in (
        CATEGORICAL_CLASS_REWEIGHTING_NONE,
        CATEGORICAL_CLASS_REWEIGHTING_INVERSE_FREQUENCY_V1,
    )
)
MODEL_CANDIDATE_IDS = tuple(spec[0] for spec in _CANDIDATE_SPECS)
_CANDIDATE_SPEC_BY_ID = {spec[0]: spec[1:] for spec in _CANDIDATE_SPECS}

_REPORT_FIELDS = {
    "authority",
    "calibrated",
    "calibration_features_loaded",
    "candidate_aggregates",
    "candidate_ids_in_tie_break_order",
    "config",
    "development_records_sha256",
    "development_sample_count",
    "development_writer_commitment",
    "development_writer_count",
    "feature_schema_version",
    "fold_assignment_version",
    "folds",
    "loss_normalization_contract_version",
    "output_contract_version",
    "promotion_eligible",
    "runs",
    "schema_version",
    "sealed_features_loaded",
    "selected_architecture_id",
    "selected_candidate_id",
    "selected_categorical_class_reweighting",
    "selection_ranking_version",
    "status",
    "trajectory_augmentation_contract_version",
    "writer_balanced_loss",
}
_CONFIG_FIELDS = {
    "batch_size",
    "device",
    "epochs",
    "fold_count",
    "learning_rate",
    "seeds",
    "weight_decay",
}
_FOLD_FIELDS = {"fold_index", "writer_count", "writer_commitment"}
_AGGREGATE_FIELDS = {
    "architecture_id",
    "candidate_id",
    "categorical_class_reweighting",
    "mean_writer_macro_balanced_top_path_accuracy",
    "mean_writer_macro_no_read_top_path_accuracy",
    "mean_writer_macro_notation_top_path_accuracy",
    "writer_seed_count",
}
_RUN_FIELDS = {
    "architecture_id",
    "candidate_id",
    "categorical_class_reweighting",
    "correct_count",
    "final_epoch_loss",
    "fold_index",
    "held_out_writer_commitment",
    "no_read_correct_count",
    "no_read_sample_count",
    "notation_correct_count",
    "notation_sample_count",
    "sample_count",
    "seed",
    "writer_count",
    "writer_macro_balanced_top_path_accuracy",
    "writer_macro_no_read_top_path_accuracy",
    "writer_macro_notation_top_path_accuracy",
    "writer_macro_top_path_accuracy",
}


@dataclass(frozen=True)
class BoundDevelopmentModelSelection:
    authority: str
    report_sha256: str
    selected_candidate_id: str
    selected_architecture_id: str
    selected_categorical_class_reweighting: str
    comparison_config: DevelopmentComparisonConfig


@dataclass(frozen=True)
class DevelopmentComparisonConfig:
    fold_count: int = 5
    seeds: Tuple[int, ...] = (17, 29, 43)
    epochs: int = 40
    batch_size: int = 64
    learning_rate: float = 1e-3
    weight_decay: float = 1e-4
    device: str = "cpu"

    def validate(self) -> None:
        if (
            isinstance(self.fold_count, bool)
            or not isinstance(self.fold_count, int)
            or self.fold_count < 2
        ):
            raise ContractError(
                "invalid_development_comparison_config",
                "fold_count",
                "must be an integer of at least two",
            )
        if (
            not isinstance(self.seeds, tuple)
            or not self.seeds
            or len(set(self.seeds)) != len(self.seeds)
            or any(
                isinstance(seed, bool) or not isinstance(seed, int) or seed < 0
                for seed in self.seeds
            )
        ):
            raise ContractError(
                "invalid_development_comparison_config",
                "seeds",
                "must be a non-empty tuple of unique nonnegative integers",
            )
        TrainingConfig(
            seed=self.seeds[0],
            epochs=self.epochs,
            batch_size=self.batch_size,
            learning_rate=self.learning_rate,
            weight_decay=self.weight_decay,
            device=self.device,
            deterministic=True,
            writer_balanced_loss=True,
        ).validate()


def _writer_sort_key(writer_hash: str) -> Tuple[int, str]:
    digest = hashlib.sha256(
        (DEVELOPMENT_FOLD_ASSIGNMENT_VERSION + "\0" + writer_hash).encode(
            "ascii"
        )
    ).hexdigest()
    return (0, digest)


def build_writer_folds(
    development: Sequence[CorpusRecord],
    requested_fold_count: int,
) -> Tuple[Tuple[str, ...], ...]:
    """Assign whole writers to deterministic, sample-count-balanced folds."""

    assert_exact_role(development, PipelineRole.TRAINING)
    if (
        isinstance(requested_fold_count, bool)
        or not isinstance(requested_fold_count, int)
        or requested_fold_count < 2
    ):
        raise ContractError(
            "invalid_development_comparison_config",
            "fold_count",
            "must be an integer of at least two",
        )
    sample_counts: Dict[str, int] = {}
    for record in development:
        sample_counts[record.writer_id_hash] = (
            sample_counts.get(record.writer_id_hash, 0) + 1
        )
    if len(sample_counts) < 4:
        raise OperationRefusedError(
            "insufficient_development_writers",
            "development",
            "at least four development writers are required for grouped comparison",
        )
    fold_count = min(requested_fold_count, len(sample_counts))
    folds = [[] for _ in range(fold_count)]
    fold_sample_counts = [0] * fold_count
    writers = sorted(
        sample_counts,
        key=lambda writer: (-sample_counts[writer], _writer_sort_key(writer)),
    )
    for writer in writers:
        fold_index = min(
            range(fold_count),
            key=lambda index: (
                fold_sample_counts[index],
                len(folds[index]),
                index,
            ),
        )
        folds[fold_index].append(writer)
        fold_sample_counts[fold_index] += sample_counts[writer]
    return tuple(tuple(sorted(fold)) for fold in folds)


def _candidate_spec(candidate_id: str) -> Tuple[str, str]:
    try:
        return _CANDIDATE_SPEC_BY_ID[candidate_id]
    except KeyError:
        raise ContractError(
            "unknown_development_model_candidate", "candidate_id", candidate_id
        )


def _model_factory(candidate_id: str, seed: int):
    architecture_id, _ = _candidate_spec(candidate_id)
    return candidate_model_factory(architecture_id, seed)


def _top_path_is_correct(record: CorpusRecord, output: FactorLogits) -> bool:
    decoded = decode_factor_logits(output)
    top_candidate = decoded.candidates[0] if decoded.candidates else None
    if record.supervision_kind == CorpusSupervisionKind.NO_READ:
        return top_candidate is None or (
            decoded.no_read_log_score >= top_candidate.raw_joint_log_score
        )
    expected = record.supervised_canonical_label
    return (
        top_candidate is not None
        and top_candidate.raw_joint_log_score > decoded.no_read_log_score
        and top_candidate.canonical_label == expected
    )


def _evaluate_partition(
    model: object,
    records: Sequence[CorpusRecord],
    data_root: Path,
    batch_size: int,
    device_name: str,
) -> Mapping[str, object]:
    assert_exact_role(records, PipelineRole.TRAINING)
    numpy_batch = load_numpy_feature_batch(records, data_root)
    torch = require_optional_dependency("torch", "training")
    device = torch.device(device_name)
    model.eval()
    per_writer: Dict[str, list[int]] = {}
    correct_count = 0
    notation_correct_count = 0
    notation_sample_count = 0
    no_read_correct_count = 0
    no_read_sample_count = 0
    with torch.no_grad():
        for start in range(0, len(records), batch_size):
            stop = min(len(records), start + batch_size)
            output = model(
                torch.from_numpy(numpy_batch.trajectory[start:stop]).to(device),
                torch.from_numpy(numpy_batch.raster[start:stop]).to(device),
            )
            for offset, record in enumerate(records[start:stop]):
                logits = FactorLogits.from_mapping(
                    {
                        head.name: output[head.name][offset]
                        .detach()
                        .cpu()
                        .tolist()
                        for head in OUTPUT_HEADS
                    }
                )
                correct = int(_top_path_is_correct(record, logits))
                correct_count += correct
                # [notation correct, notation total, no-read correct, no-read total]
                counters = per_writer.setdefault(record.writer_id_hash, [0, 0, 0, 0])
                if record.supervision_kind == CorpusSupervisionKind.NOTATION:
                    notation_correct_count += correct
                    notation_sample_count += 1
                    counters[0] += correct
                    counters[1] += 1
                else:
                    no_read_correct_count += correct
                    no_read_sample_count += 1
                    counters[2] += correct
                    counters[3] += 1
    writer_notation_accuracies = []
    writer_no_read_accuracies = []
    writer_balanced_accuracies = []
    writer_overall_accuracies = []
    for notation_correct, notation_total, no_read_correct, no_read_total in per_writer.values():
        if notation_total <= 0 or no_read_total <= 0:
            raise OperationRefusedError(
                "writer_lacks_required_supervision",
                "development_holdout",
                "every held-out writer requires notation and no-read attempts",
            )
        notation_accuracy = notation_correct / notation_total
        no_read_accuracy = no_read_correct / no_read_total
        writer_notation_accuracies.append(notation_accuracy)
        writer_no_read_accuracies.append(no_read_accuracy)
        writer_balanced_accuracies.append((notation_accuracy + no_read_accuracy) / 2.0)
        writer_overall_accuracies.append(
            (notation_correct + no_read_correct) / (notation_total + no_read_total)
        )
    return {
        "correct_count": correct_count,
        "sample_count": len(records),
        "notation_correct_count": notation_correct_count,
        "notation_sample_count": notation_sample_count,
        "no_read_correct_count": no_read_correct_count,
        "no_read_sample_count": no_read_sample_count,
        "writer_count": len(per_writer),
        "writer_macro_top_path_accuracy": sum(writer_overall_accuracies)
        / len(writer_overall_accuracies),
        "writer_macro_notation_top_path_accuracy": sum(writer_notation_accuracies)
        / len(writer_notation_accuracies),
        "writer_macro_no_read_top_path_accuracy": sum(writer_no_read_accuracies)
        / len(writer_no_read_accuracies),
        "writer_macro_balanced_top_path_accuracy": sum(writer_balanced_accuracies)
        / len(writer_balanced_accuracies),
    }


def _writer_commitment(writers: Sequence[str]) -> str:
    payload = ("\n".join(sorted(writers)) + "\n").encode("ascii")
    return hashlib.sha256(payload).hexdigest()


def _require_exact_fields(
    value: object,
    expected: set[str],
    path: str,
) -> Mapping[str, object]:
    if not isinstance(value, dict):
        raise ContractError("invalid_object", path, "must be an object")
    missing = sorted(expected.difference(value.keys()))
    unknown = sorted(set(value.keys()).difference(expected))
    if missing:
        raise ContractError("missing_field", path, ", ".join(missing))
    if unknown:
        raise ContractError("unknown_field", path, ", ".join(unknown))
    return value


def _require_positive_integer(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ContractError("invalid_integer", path, "must be a positive integer")
    return value


def _require_probability(value: object, path: str) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(float(value))
        or not 0 <= float(value) <= 1
    ):
        raise ContractError("invalid_probability", path, "must be finite and in [0, 1]")
    return float(value)


def _load_canonical_report(path: Path) -> Tuple[Mapping[str, object], bytes]:
    if path.is_symlink() or not path.is_file():
        raise ContractError(
            "development_selection_report_unreadable",
            str(path),
            "must be a non-symlink regular file",
        )
    try:
        payload = path.read_bytes()
        text = payload.decode("utf-8")
    except (OSError, UnicodeError) as error:
        raise ContractError("development_selection_report_unreadable", str(path), str(error))
    if not text.endswith("\n") or text.endswith("\n\n"):
        raise ContractError(
            "noncanonical_json",
            str(path),
            "expected canonical JSON followed by one newline",
        )
    value = strict_json_loads(text[:-1], str(path))
    if canonical_json_bytes(value) + b"\n" != payload:
        raise ContractError("noncanonical_json", str(path), "bytes are not canonical")
    return _require_exact_fields(value, _REPORT_FIELDS, "development_selection_report"), payload


def load_bound_development_model_selection(
    path: Path,
    records: Sequence[CorpusRecord],
) -> BoundDevelopmentModelSelection:
    """Validate and bind one canonical development-only comparison report.

    This prevents an accidental architecture/loss mismatch after comparison.
    The report remains development-only evidence and is not a promotion gate.
    """

    report, payload = _load_canonical_report(path)
    exact_values = {
        "schema_version": DEVELOPMENT_COMPARISON_SCHEMA_VERSION,
        "status": "development-only-model-comparison",
        "authority": "development-model-selection-only",
        "feature_schema_version": FEATURE_SCHEMA.version,
        "output_contract_version": OUTPUT_CONTRACT_VERSION,
        "fold_assignment_version": DEVELOPMENT_FOLD_ASSIGNMENT_VERSION,
        "selection_ranking_version": DEVELOPMENT_SELECTION_RANKING_VERSION,
        "loss_normalization_contract_version": LOSS_NORMALIZATION_CONTRACT_VERSION,
        "trajectory_augmentation_contract_version": TRAJECTORY_AUGMENTATION_CONTRACT_VERSION,
    }
    for field, expected in exact_values.items():
        if report[field] != expected:
            raise ContractError(
                "development_selection_contract_mismatch",
                f"development_selection_report.{field}",
                f"expected {expected}",
            )
    for field in (
        "writer_balanced_loss",
    ):
        if report[field] is not True:
            raise ContractError(
                "development_selection_contract_mismatch",
                f"development_selection_report.{field}",
                "must be true",
            )
    for field in (
        "calibration_features_loaded",
        "sealed_features_loaded",
        "calibrated",
        "promotion_eligible",
    ):
        if report[field] is not False:
            raise ContractError(
                "invalid_development_selection_authority",
                f"development_selection_report.{field}",
                "must remain false",
            )
    if report["candidate_ids_in_tie_break_order"] != list(MODEL_CANDIDATE_IDS):
        raise ContractError(
            "development_selection_candidate_order_mismatch",
            "development_selection_report.candidate_ids_in_tie_break_order",
            "must equal the frozen candidate order",
        )

    config_mapping = _require_exact_fields(
        report["config"], _CONFIG_FIELDS, "development_selection_report.config"
    )
    seeds = config_mapping["seeds"]
    if not isinstance(seeds, list):
        raise ContractError(
            "invalid_development_comparison_config",
            "development_selection_report.config.seeds",
            "must be an array",
        )
    config = DevelopmentComparisonConfig(
        fold_count=config_mapping["fold_count"],
        seeds=tuple(seeds),
        epochs=config_mapping["epochs"],
        batch_size=config_mapping["batch_size"],
        learning_rate=config_mapping["learning_rate"],
        weight_decay=config_mapping["weight_decay"],
        device=config_mapping["device"],
    )
    config.validate()

    development = select_role_records(records, PipelineRole.TRAINING)
    writers = tuple(sorted({record.writer_id_hash for record in development}))
    expected_binding = {
        "development_records_sha256": records_digest(development),
        "development_sample_count": len(development),
        "development_writer_count": len(writers),
        "development_writer_commitment": _writer_commitment(writers),
    }
    for field, expected in expected_binding.items():
        if report[field] != expected:
            raise ContractError(
                "development_selection_corpus_mismatch",
                f"development_selection_report.{field}",
                f"expected {expected}",
            )

    expected_folds = build_writer_folds(development, config.fold_count)
    folds = report["folds"]
    if not isinstance(folds, list) or len(folds) != len(expected_folds):
        raise ContractError(
            "development_selection_fold_mismatch",
            "development_selection_report.folds",
            "fold count changed",
        )
    for fold_index, (fold, expected_writers) in enumerate(zip(folds, expected_folds)):
        fold = _require_exact_fields(
            fold, _FOLD_FIELDS, f"development_selection_report.folds[{fold_index}]"
        )
        expected_fold = {
            "fold_index": fold_index,
            "writer_count": len(expected_writers),
            "writer_commitment": _writer_commitment(expected_writers),
        }
        if dict(fold) != expected_fold:
            raise ContractError(
                "development_selection_fold_mismatch",
                f"development_selection_report.folds[{fold_index}]",
                "fold membership commitment changed",
            )

    runs = report["runs"]
    expected_run_count = len(expected_folds) * len(config.seeds) * len(MODEL_CANDIDATE_IDS)
    if not isinstance(runs, list) or len(runs) != expected_run_count:
        raise ContractError(
            "incomplete_development_comparison",
            "development_selection_report.runs",
            f"expected {expected_run_count} runs",
        )
    run_by_key: Dict[Tuple[str, int, int], Mapping[str, object]] = {}
    for index, raw_run in enumerate(runs):
        run = _require_exact_fields(
            raw_run, _RUN_FIELDS, f"development_selection_report.runs[{index}]"
        )
        candidate_id = run["candidate_id"]
        if candidate_id not in MODEL_CANDIDATE_IDS:
            raise ContractError(
                "unknown_development_model_candidate",
                f"development_selection_report.runs[{index}].candidate_id",
                str(candidate_id),
            )
        architecture_id, reweighting = _candidate_spec(str(candidate_id))
        fold_index = run["fold_index"]
        seed = run["seed"]
        if (
            isinstance(fold_index, bool)
            or not isinstance(fold_index, int)
            or not 0 <= fold_index < len(expected_folds)
            or seed not in config.seeds
        ):
            raise ContractError(
                "invalid_development_comparison_run",
                f"development_selection_report.runs[{index}]",
                "unknown fold or seed",
            )
        key = (str(candidate_id), fold_index, int(seed))
        if key in run_by_key:
            raise ContractError(
                "duplicate_development_comparison_run",
                f"development_selection_report.runs[{index}]",
                str(key),
            )
        run_by_key[key] = run
        held_out_writers = expected_folds[fold_index]
        held_out_records = tuple(
            record for record in development if record.writer_id_hash in held_out_writers
        )
        expected_notation_count = sum(
            record.supervision_kind == CorpusSupervisionKind.NOTATION
            for record in held_out_records
        )
        expected_no_read_count = len(held_out_records) - expected_notation_count
        if (
            run["architecture_id"] != architecture_id
            or run["categorical_class_reweighting"] != reweighting
            or run["held_out_writer_commitment"] != _writer_commitment(held_out_writers)
            or run["writer_count"] != len(held_out_writers)
            or run["sample_count"] != len(held_out_records)
            or run["notation_sample_count"] != expected_notation_count
            or run["no_read_sample_count"] != expected_no_read_count
        ):
            raise ContractError(
                "invalid_development_comparison_run",
                f"development_selection_report.runs[{index}]",
                "run metadata does not match its frozen fold and candidate",
            )
        for correct_field, total_field in (
            ("correct_count", "sample_count"),
            ("notation_correct_count", "notation_sample_count"),
            ("no_read_correct_count", "no_read_sample_count"),
        ):
            correct = run[correct_field]
            total = run[total_field]
            if (
                isinstance(correct, bool)
                or not isinstance(correct, int)
                or correct < 0
                or correct > total
            ):
                raise ContractError(
                    "invalid_development_comparison_run",
                    f"development_selection_report.runs[{index}].{correct_field}",
                    "must be an integer between zero and its sample count",
                )
        final_loss = run["final_epoch_loss"]
        if (
            isinstance(final_loss, bool)
            or not isinstance(final_loss, (int, float))
            or not math.isfinite(float(final_loss))
            or float(final_loss) < 0
        ):
            raise ContractError(
                "invalid_development_comparison_run",
                f"development_selection_report.runs[{index}].final_epoch_loss",
                "must be finite and nonnegative",
            )
        for metric in (
            "writer_macro_top_path_accuracy",
            "writer_macro_notation_top_path_accuracy",
            "writer_macro_no_read_top_path_accuracy",
            "writer_macro_balanced_top_path_accuracy",
        ):
            _require_probability(
                run[metric], f"development_selection_report.runs[{index}].{metric}"
            )
    expected_run_keys = {
        (candidate_id, fold_index, seed)
        for candidate_id in MODEL_CANDIDATE_IDS
        for fold_index in range(len(expected_folds))
        for seed in config.seeds
    }
    if set(run_by_key) != expected_run_keys:
        raise ContractError(
            "incomplete_development_comparison",
            "development_selection_report.runs",
            "candidate/fold/seed coverage changed",
        )

    aggregates = report["candidate_aggregates"]
    if not isinstance(aggregates, list) or len(aggregates) != len(MODEL_CANDIDATE_IDS):
        raise ContractError(
            "incomplete_development_comparison",
            "development_selection_report.candidate_aggregates",
            "must contain every frozen candidate",
        )
    aggregate_by_candidate: Dict[str, Mapping[str, object]] = {}
    expected_writer_seed_count = len(writers) * len(config.seeds)
    metric_pairs = (
        (
            "mean_writer_macro_balanced_top_path_accuracy",
            "writer_macro_balanced_top_path_accuracy",
        ),
        (
            "mean_writer_macro_notation_top_path_accuracy",
            "writer_macro_notation_top_path_accuracy",
        ),
        (
            "mean_writer_macro_no_read_top_path_accuracy",
            "writer_macro_no_read_top_path_accuracy",
        ),
    )
    for index, raw_aggregate in enumerate(aggregates):
        aggregate = _require_exact_fields(
            raw_aggregate,
            _AGGREGATE_FIELDS,
            f"development_selection_report.candidate_aggregates[{index}]",
        )
        candidate_id = aggregate["candidate_id"]
        if candidate_id != MODEL_CANDIDATE_IDS[index]:
            raise ContractError(
                "development_selection_candidate_order_mismatch",
                f"development_selection_report.candidate_aggregates[{index}]",
                "aggregate order must match the frozen tie-break order",
            )
        architecture_id, reweighting = _candidate_spec(str(candidate_id))
        if (
            aggregate["architecture_id"] != architecture_id
            or aggregate["categorical_class_reweighting"] != reweighting
            or aggregate["writer_seed_count"] != expected_writer_seed_count
        ):
            raise ContractError(
                "invalid_development_comparison_aggregate",
                f"development_selection_report.candidate_aggregates[{index}]",
                "candidate metadata changed",
            )
        for aggregate_metric, run_metric in metric_pairs:
            actual = _require_probability(
                aggregate[aggregate_metric],
                f"development_selection_report.candidate_aggregates[{index}].{aggregate_metric}",
            )
            weighted = sum(
                float(run[run_metric]) * int(run["writer_count"])
                for key, run in run_by_key.items()
                if key[0] == candidate_id
            ) / expected_writer_seed_count
            if not math.isclose(actual, weighted, rel_tol=1e-12, abs_tol=1e-12):
                raise ContractError(
                    "development_selection_aggregate_mismatch",
                    f"development_selection_report.candidate_aggregates[{index}].{aggregate_metric}",
                    "aggregate does not reconstruct from writer-weighted runs",
                )
        aggregate_by_candidate[str(candidate_id)] = aggregate

    selected_candidate_id = max(
        MODEL_CANDIDATE_IDS,
        key=lambda candidate_id: (
            float(
                aggregate_by_candidate[candidate_id][
                    "mean_writer_macro_balanced_top_path_accuracy"
                ]
            ),
            -MODEL_CANDIDATE_IDS.index(candidate_id),
        ),
    )
    selected_architecture_id, selected_reweighting = _candidate_spec(
        selected_candidate_id
    )
    if (
        report["selected_candidate_id"] != selected_candidate_id
        or report["selected_architecture_id"] != selected_architecture_id
        or report["selected_categorical_class_reweighting"] != selected_reweighting
    ):
        raise ContractError(
            "development_selection_winner_mismatch",
            "development_selection_report.selected_candidate_id",
            "winner does not follow the frozen ranking and tie-break rule",
        )
    return BoundDevelopmentModelSelection(
        authority=BOUND_DEVELOPMENT_SELECTION_AUTHORITY,
        report_sha256=hashlib.sha256(payload).hexdigest(),
        selected_candidate_id=selected_candidate_id,
        selected_architecture_id=selected_architecture_id,
        selected_categorical_class_reweighting=selected_reweighting,
        comparison_config=config,
    )


def build_development_model_comparison(
    records: Sequence[CorpusRecord],
    data_root: Path,
    config: DevelopmentComparisonConfig = DevelopmentComparisonConfig(),
) -> Mapping[str, object]:
    """Compare frozen candidates without loading calibration/sealed artifacts."""

    config.validate()
    development = select_role_records(records, PipelineRole.TRAINING)
    folds = build_writer_folds(development, config.fold_count)
    all_writers = {record.writer_id_hash for record in development}
    all_outcomes = {record.supervision_kind for record in development}
    required_outcomes = {
        CorpusSupervisionKind.NOTATION,
        CorpusSupervisionKind.NO_READ,
    }
    if not required_outcomes.issubset(all_outcomes):
        raise OperationRefusedError(
            "incomplete_development_supervision",
            "development",
            "comparison requires both notation and adjudicated no-read rows",
        )

    runs = []
    candidate_writer_seed_scores: Dict[str, Dict[Tuple[str, int], list[int]]] = {
        candidate: {} for candidate in MODEL_CANDIDATE_IDS
    }
    for fold_index, held_out_writers in enumerate(folds):
        held_out = tuple(
            record
            for record in development
            if record.writer_id_hash in held_out_writers
        )
        training = tuple(
            record
            for record in development
            if record.writer_id_hash not in held_out_writers
        )
        if {record.writer_id_hash for record in training}.intersection(
            held_out_writers
        ):
            raise ContractError(
                "development_writer_leakage",
                f"fold[{fold_index}]",
                "a writer appears in training and holdout",
            )
        if not required_outcomes.issubset(
            {record.supervision_kind for record in training}
        ):
            raise OperationRefusedError(
                "fold_lacks_required_supervision",
                f"fold[{fold_index}]",
                "every training fold requires notation and no-read writers",
            )
        for seed in config.seeds:
            for candidate_id in MODEL_CANDIDATE_IDS:
                architecture_id, class_reweighting = _candidate_spec(
                    candidate_id
                )
                training_config = TrainingConfig(
                    seed=seed,
                    epochs=config.epochs,
                    batch_size=config.batch_size,
                    learning_rate=config.learning_rate,
                    weight_decay=config.weight_decay,
                    device=config.device,
                    deterministic=True,
                    writer_balanced_loss=True,
                    categorical_class_reweighting=class_reweighting,
                )
                fit = fit_development_partition(
                    training,
                    data_root,
                    training_config,
                    _model_factory(candidate_id, seed),
                )
                assessment = _evaluate_partition(
                    fit.model,
                    held_out,
                    data_root,
                    config.batch_size,
                    config.device,
                )
                for writer in held_out_writers:
                    writer_records = tuple(
                        record
                        for record in held_out
                        if record.writer_id_hash == writer
                    )
                    writer_assessment = _evaluate_partition(
                        fit.model,
                        writer_records,
                        data_root,
                        config.batch_size,
                        config.device,
                    )
                    candidate_writer_seed_scores[candidate_id][
                        (writer, seed)
                    ] = [
                        int(writer_assessment["notation_correct_count"]),
                        int(writer_assessment["notation_sample_count"]),
                        int(writer_assessment["no_read_correct_count"]),
                        int(writer_assessment["no_read_sample_count"]),
                    ]
                runs.append(
                    {
                        "candidate_id": candidate_id,
                        "architecture_id": architecture_id,
                        "categorical_class_reweighting": class_reweighting,
                        "fold_index": fold_index,
                        "held_out_writer_commitment": _writer_commitment(
                            held_out_writers
                        ),
                        "seed": seed,
                        "final_epoch_loss": fit.epoch_losses[-1],
                        **assessment,
                    }
                )

    aggregates = []
    for candidate_id in MODEL_CANDIDATE_IDS:
        architecture_id, class_reweighting = _candidate_spec(candidate_id)
        scores = candidate_writer_seed_scores[candidate_id]
        expected_keys = {
            (writer, seed) for writer in all_writers for seed in config.seeds
        }
        if set(scores) != expected_keys:
            raise ContractError(
                "incomplete_development_comparison",
                candidate_id,
                "every writer and seed must appear exactly once",
            )
        balanced_accuracies = [
            ((notation_correct / notation_total) + (no_read_correct / no_read_total))
            / 2.0
            for (
                notation_correct,
                notation_total,
                no_read_correct,
                no_read_total,
            ) in scores.values()
        ]
        notation_accuracies = [
            notation_correct / notation_total
            for notation_correct, notation_total, _, _ in scores.values()
        ]
        no_read_accuracies = [
            no_read_correct / no_read_total
            for _, _, no_read_correct, no_read_total in scores.values()
        ]
        aggregates.append(
            {
                "candidate_id": candidate_id,
                "architecture_id": architecture_id,
                "categorical_class_reweighting": class_reweighting,
                "writer_seed_count": len(balanced_accuracies),
                "mean_writer_macro_balanced_top_path_accuracy": sum(
                    balanced_accuracies
                )
                / len(balanced_accuracies),
                "mean_writer_macro_notation_top_path_accuracy": sum(
                    notation_accuracies
                )
                / len(notation_accuracies),
                "mean_writer_macro_no_read_top_path_accuracy": sum(
                    no_read_accuracies
                )
                / len(no_read_accuracies),
            }
        )
    selected = max(
        aggregates,
        key=lambda item: (
            float(item["mean_writer_macro_balanced_top_path_accuracy"]),
            -MODEL_CANDIDATE_IDS.index(str(item["candidate_id"])),
        ),
    )
    selected_architecture_id, selected_class_reweighting = _candidate_spec(
        str(selected["candidate_id"])
    )
    return {
        "schema_version": DEVELOPMENT_COMPARISON_SCHEMA_VERSION,
        "status": "development-only-model-comparison",
        "authority": "development-model-selection-only",
        "feature_schema_version": FEATURE_SCHEMA.version,
        "output_contract_version": OUTPUT_CONTRACT_VERSION,
        "fold_assignment_version": DEVELOPMENT_FOLD_ASSIGNMENT_VERSION,
        "selection_ranking_version": DEVELOPMENT_SELECTION_RANKING_VERSION,
        "loss_normalization_contract_version": (
            LOSS_NORMALIZATION_CONTRACT_VERSION
        ),
        "trajectory_augmentation_contract_version": (
            TRAJECTORY_AUGMENTATION_CONTRACT_VERSION
        ),
        "writer_balanced_loss": True,
        "candidate_ids_in_tie_break_order": list(MODEL_CANDIDATE_IDS),
        "development_records_sha256": records_digest(development),
        "development_sample_count": len(development),
        "development_writer_count": len(all_writers),
        "development_writer_commitment": _writer_commitment(tuple(all_writers)),
        "config": asdict(config),
        "folds": [
            {
                "fold_index": index,
                "writer_count": len(writers),
                "writer_commitment": _writer_commitment(writers),
            }
            for index, writers in enumerate(folds)
        ],
        "runs": runs,
        "candidate_aggregates": aggregates,
        "selected_candidate_id": selected["candidate_id"],
        "selected_architecture_id": selected_architecture_id,
        "selected_categorical_class_reweighting": (
            selected_class_reweighting
        ),
        "calibration_features_loaded": False,
        "sealed_features_loaded": False,
        "calibrated": False,
        "promotion_eligible": False,
    }

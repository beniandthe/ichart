"""Deterministic development-only training for the dual-view factor model."""

from __future__ import annotations

import random
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, Mapping, Sequence, Tuple

from .contracts import CorpusRecord, CorpusSupervisionKind, records_digest
from .dataset import (
    PipelineRole,
    assert_exact_role,
    load_numpy_feature_batch,
    require_optional_dependency,
    select_role_records,
)
from .errors import ContractError
from .features import TrajectoryChannel
from .models.factory import (
    DUAL_VIEW_MODEL_ARCHITECTURE_ID,
    default_model_config,
    make_chord_model,
    require_model_architecture_id,
)
from .models.output_contract import OUTPUT_CONTRACT_VERSION, OUTPUT_HEADS
from .selection_contract import (
    UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY,
    validate_development_selection_binding,
)


TRAJECTORY_AUGMENTATION_CONTRACT_VERSION = (
    "chord-ink-trajectory-order-direction-v2-source-mass"
)
LOSS_NORMALIZATION_CONTRACT_VERSION = "chord-ink-global-minibatch-weighting-v1"
CATEGORICAL_CLASS_REWEIGHTING_NONE = "none"
CATEGORICAL_CLASS_REWEIGHTING_INVERSE_FREQUENCY_V1 = (
    "categorical-inverse-frequency-v1"
)
CATEGORICAL_CLASS_REWEIGHTING_MODES = (
    CATEGORICAL_CLASS_REWEIGHTING_NONE,
    CATEGORICAL_CLASS_REWEIGHTING_INVERSE_FREQUENCY_V1,
)


@dataclass(frozen=True)
class TrainingConfig:
    seed: int = 17
    epochs: int = 40
    batch_size: int = 64
    learning_rate: float = 1e-3
    weight_decay: float = 1e-4
    device: str = "cpu"
    deterministic: bool = True
    writer_balanced_loss: bool = True
    categorical_class_reweighting: str = CATEGORICAL_CLASS_REWEIGHTING_NONE
    loss_normalization_contract_version: str = (
        LOSS_NORMALIZATION_CONTRACT_VERSION
    )
    trajectory_augmentation_contract_version: str = (
        TRAJECTORY_AUGMENTATION_CONTRACT_VERSION
    )

    def validate(self) -> None:
        if isinstance(self.seed, bool) or not isinstance(self.seed, int) or self.seed < 0:
            raise ContractError("invalid_training_config", "seed", "must be a nonnegative integer")
        for name, value in (("epochs", self.epochs), ("batch_size", self.batch_size)):
            if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
                raise ContractError("invalid_training_config", name, "must be a positive integer")
        for name, value in (
            ("learning_rate", self.learning_rate),
            ("weight_decay", self.weight_decay),
        ):
            if (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(float(value))
                or float(value) < 0
            ):
                raise ContractError("invalid_training_config", name, "must be finite and nonnegative")
        if self.learning_rate == 0:
            raise ContractError("invalid_training_config", "learning_rate", "must be greater than zero")
        if self.device not in ("cpu", "cuda", "mps"):
            raise ContractError("invalid_training_config", "device", "must be cpu, cuda, or mps")
        if not self.deterministic:
            raise ContractError(
                "nondeterministic_training_refused",
                "deterministic",
                "this pipeline requires deterministic execution",
            )
        if not isinstance(self.writer_balanced_loss, bool):
            raise ContractError(
                "invalid_training_config",
                "writer_balanced_loss",
                "must be a boolean",
            )
        if not self.writer_balanced_loss:
            raise ContractError(
                "writer_balanced_training_required",
                "writer_balanced_loss",
                "a prolific development writer must not dominate the training objective",
            )
        if self.categorical_class_reweighting not in (
            CATEGORICAL_CLASS_REWEIGHTING_MODES
        ):
            raise ContractError(
                "invalid_training_config",
                "categorical_class_reweighting",
                "must be one of "
                + ", ".join(CATEGORICAL_CLASS_REWEIGHTING_MODES),
            )
        if (
            self.loss_normalization_contract_version
            != LOSS_NORMALIZATION_CONTRACT_VERSION
        ):
            raise ContractError(
                "loss_normalization_version_mismatch",
                "loss_normalization_contract_version",
                f"expected {LOSS_NORMALIZATION_CONTRACT_VERSION}",
            )
        if (
            self.trajectory_augmentation_contract_version
            != TRAJECTORY_AUGMENTATION_CONTRACT_VERSION
        ):
            raise ContractError(
                "trajectory_augmentation_version_mismatch",
                "trajectory_augmentation_contract_version",
                f"expected {TRAJECTORY_AUGMENTATION_CONTRACT_VERSION}",
            )


@dataclass(frozen=True)
class TrainingResult:
    model: object
    epoch_losses: Tuple[float, ...]
    development_sample_ids: Tuple[str, ...]
    development_writer_hashes: Tuple[str, ...]
    seed: int
    model_architecture_id: str
    model_config: object
    training_config: TrainingConfig
    development_records_sha256: str
    development_selection_authority: str
    development_selection_report_sha256: str | None
    has_negative_no_read_supervision: bool = False
    output_contract_version: str = OUTPUT_CONTRACT_VERSION
    is_calibrated: bool = False


@dataclass(frozen=True)
class DevelopmentPartitionFit:
    model: object
    epoch_losses: Tuple[float, ...]
    sample_ids: Tuple[str, ...]
    writer_hashes: Tuple[str, ...]
    has_negative_no_read_supervision: bool


def _seed_everything(seed: int, numpy, torch) -> None:
    random.seed(seed)
    numpy.random.seed(seed)
    torch.manual_seed(seed)
    if hasattr(torch, "cuda") and torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    torch.use_deterministic_algorithms(True)
    if hasattr(torch.backends, "cudnn"):
        torch.backends.cudnn.benchmark = False
        torch.backends.cudnn.deterministic = True


def writer_balanced_head_weights(
    records: Sequence[CorpusRecord],
    active: Mapping[str, object],
    numpy,
    source_indices: Sequence[int] | None = None,
) -> Dict[str, object]:
    """Give every writer and original source equal active loss mass.

    When deterministic derivatives are present, all rows with one source index
    split that source capture's weight. Derivative count therefore cannot make
    a multi-stroke capture more authoritative than a single-stroke capture.
    """

    if not records:
        raise ContractError("empty_supervision", "training", "records are empty")
    if source_indices is None:
        source_indices = tuple(range(len(records)))
    if (
        len(source_indices) != len(records)
        or any(
            isinstance(source_index, bool)
            or not isinstance(source_index, int)
            or source_index < 0
            for source_index in source_indices
        )
    ):
        raise ContractError(
            "invalid_training_source_indices",
            "training.source_indices",
            "must contain one nonnegative integer per training row",
        )
    result: Dict[str, object] = {}
    for head in OUTPUT_HEADS:
        if head.name not in active:
            raise ContractError(
                "missing_active_head", f"training.active.{head.name}", "head is absent"
            )
        mask = numpy.asarray(active[head.name], dtype=numpy.bool_)
        if mask.shape != (len(records),):
            raise ContractError(
                "active_head_shape_mismatch",
                f"training.active.{head.name}",
                f"expected {(len(records),)}, got {mask.shape}",
            )
        source_rows: Dict[int, list[int]] = {}
        source_writer: Dict[int, str] = {}
        source_active: Dict[int, bool] = {}
        for index, (record, is_active, source_index) in enumerate(
            zip(records, mask, source_indices)
        ):
            source_rows.setdefault(source_index, []).append(index)
            previous_writer = source_writer.setdefault(
                source_index, record.writer_id_hash
            )
            if previous_writer != record.writer_id_hash:
                raise ContractError(
                    "training_source_writer_mismatch",
                    f"training.source_indices.{source_index}",
                    "one source index spans multiple writers",
                )
            previous_active = source_active.setdefault(source_index, bool(is_active))
            if previous_active != bool(is_active):
                raise ContractError(
                    "training_source_active_mismatch",
                    f"training.active.{head.name}",
                    "one source has inconsistent derivative masks",
                )
        active_sources_by_writer: Dict[str, int] = {}
        for source_index, is_active in source_active.items():
            if is_active:
                writer = source_writer[source_index]
                active_sources_by_writer[writer] = (
                    active_sources_by_writer.get(writer, 0) + 1
                )
        weights = numpy.zeros(len(records), dtype=numpy.float32)
        for source_index, rows in source_rows.items():
            if source_active[source_index]:
                writer = source_writer[source_index]
                source_weight = 1.0 / float(active_sources_by_writer[writer])
                row_weight = source_weight / float(len(rows))
                for index in rows:
                    weights[index] = row_weight
        result[head.name] = weights
    return result


def training_head_weights(
    records: Sequence[CorpusRecord],
    targets: Mapping[str, object],
    active: Mapping[str, object],
    categorical_class_reweighting: str,
    numpy,
    source_indices: Sequence[int] | None = None,
) -> Dict[str, object]:
    """Build deterministic per-sample weights without inventing supervision.

    Writer balancing is always the first constraint. The optional categorical
    inverse-frequency factor is a development-selection candidate, not a
    presumed improvement: grouped held-out writers must decide whether it
    helps. Independent-Bernoulli alteration logits retain writer-only weights
    because one scalar sample weight cannot correctly rebalance each bit.
    """

    if categorical_class_reweighting not in CATEGORICAL_CLASS_REWEIGHTING_MODES:
        raise ContractError(
            "invalid_training_config",
            "categorical_class_reweighting",
            "unsupported mode",
        )
    weights = writer_balanced_head_weights(
        records,
        active,
        numpy,
        source_indices=source_indices,
    )
    if categorical_class_reweighting == CATEGORICAL_CLASS_REWEIGHTING_NONE:
        return weights

    for head in OUTPUT_HEADS:
        if head.is_independent_bernoulli:
            continue
        if head.name not in targets:
            raise ContractError(
                "missing_target_head",
                f"training.targets.{head.name}",
                "head is absent",
            )
        mask = numpy.asarray(active[head.name], dtype=numpy.bool_)
        labels = numpy.asarray(targets[head.name])
        if labels.shape != (len(records),):
            raise ContractError(
                "target_head_shape_mismatch",
                f"training.targets.{head.name}",
                f"expected {(len(records),)}, got {labels.shape}",
            )
        if source_indices is None:
            source_indices = tuple(range(len(records)))
        label_by_source: Dict[int, int] = {}
        for index, is_active in enumerate(mask):
            if not bool(is_active):
                continue
            source_index = source_indices[index]
            label = int(labels[index])
            previous = label_by_source.setdefault(source_index, label)
            if previous != label:
                raise ContractError(
                    "training_source_target_mismatch",
                    f"training.targets.{head.name}",
                    "one source has inconsistent derivative labels",
                )
        if not label_by_source:
            continue
        count_by_label: Dict[int, int] = {}
        for label in label_by_source.values():
            count_by_label[label] = count_by_label.get(label, 0) + 1
        adjusted = weights[head.name].copy()
        for index, is_active in enumerate(mask):
            if bool(is_active):
                adjusted[index] /= float(count_by_label[int(labels[index])])
        weights[head.name] = adjusted
    return weights


def normalize_head_weights_for_minibatches(
    weights: Mapping[str, object],
    row_count: int,
    numpy,
) -> Tuple[Dict[str, object], Tuple[str, ...]]:
    """Scale global head weights for an unbiased mini-batch objective.

    Every globally supervised head is normalized to ``row_count`` total mass.
    A batch then divides its weighted sum by its own row count. Combining batch
    losses by batch size reconstructs the exact full-dataset weighted loss;
    no batch-local renormalization can erase writer or class weights.
    """

    if isinstance(row_count, bool) or not isinstance(row_count, int) or row_count <= 0:
        raise ContractError(
            "invalid_training_row_count",
            "training.row_count",
            "must be a positive integer",
        )
    normalized: Dict[str, object] = {}
    supervised = []
    for head in OUTPUT_HEADS:
        if head.name not in weights:
            raise ContractError(
                "missing_head_weight",
                f"training.weights.{head.name}",
                "head is absent",
            )
        values = numpy.asarray(weights[head.name], dtype=numpy.float32)
        if values.shape != (row_count,) or not numpy.isfinite(values).all() or bool(
            (values < 0).any()
        ):
            raise ContractError(
                "invalid_head_weight",
                f"training.weights.{head.name}",
                f"expected {row_count} finite nonnegative weights",
            )
        total = float(values.sum())
        if total > 0:
            values = values * (float(row_count) / total)
            supervised.append(head.name)
        normalized[head.name] = values
    if not supervised:
        raise ContractError("empty_supervision", "training", "no active factor targets")
    return normalized, tuple(supervised)


def _rebuild_trajectory_segments(segments, reverse_directions: bool, numpy):
    rebuilt = numpy.zeros((1, 256, 10), dtype=numpy.float32)
    cursor = 0
    for source in segments:
        segment = source[::-1].copy() if reverse_directions else source.copy()
        if cursor + len(segment) > 256:
            raise ContractError(
                "trajectory_augmentation_overflow",
                "training.trajectory",
                "rebuilt trajectory exceeds the frozen sample count",
            )
        segment[:, int(TrajectoryChannel.NORMALIZED_DELTA_TIME)] = 0.0
        segment[:, int(TrajectoryChannel.TIMING_AVAILABLE)] = 0.0
        segment[:, int(TrajectoryChannel.STROKE_START)] = 0.0
        segment[:, int(TrajectoryChannel.STROKE_END)] = 0.0
        segment[0, int(TrajectoryChannel.STROKE_START)] = 1.0
        segment[-1, int(TrajectoryChannel.STROKE_END)] = 1.0
        segment[:, int(TrajectoryChannel.VALID)] = 1.0
        previous_x = segment[0, int(TrajectoryChannel.X)]
        previous_y = segment[0, int(TrajectoryChannel.Y)]
        for index in range(len(segment)):
            x = segment[index, int(TrajectoryChannel.X)]
            y = segment[index, int(TrajectoryChannel.Y)]
            delta_x = 0.0 if index == 0 else x - previous_x
            delta_y = 0.0 if index == 0 else y - previous_y
            segment[index, int(TrajectoryChannel.DELTA_X)] = delta_x
            segment[index, int(TrajectoryChannel.DELTA_Y)] = delta_y
            segment[index, int(TrajectoryChannel.ARC_STEP)] = math.hypot(
                float(delta_x), float(delta_y)
            )
            previous_x = x
            previous_y = y
        rebuilt[0, cursor : cursor + len(segment), :] = segment
        cursor += len(segment)
    return rebuilt


def build_trajectory_invariance_variants(trajectory, numpy) -> Tuple[object, ...]:
    """Create deterministic construction-order/direction variants.

    These are correlated derivatives of one writer, never independent samples.
    Timing is cleared after reordering because the original temporal deltas no
    longer describe the derived sequence. The raster view remains unchanged.
    """

    value = numpy.asarray(trajectory, dtype=numpy.float32)
    if value.shape != (1, 256, 10):
        raise ContractError(
            "trajectory_augmentation_shape_mismatch",
            "training.trajectory",
            f"expected {(1, 256, 10)}, got {value.shape}",
        )
    valid = value[0, :, int(TrajectoryChannel.VALID)] > 0.5
    valid_count = int(valid.sum())
    if valid_count <= 0 or not bool(valid[:valid_count].all()) or bool(
        valid[valid_count:].any()
    ):
        raise ContractError(
            "invalid_trajectory_padding",
            "training.trajectory",
            "valid samples must be one non-empty contiguous prefix",
        )
    rows = value[0, :valid_count, :].copy()
    starts = [
        index
        for index in range(valid_count)
        if rows[index, int(TrajectoryChannel.STROKE_START)] > 0.5
    ]
    if not starts or starts[0] != 0:
        raise ContractError(
            "invalid_trajectory_stroke_boundaries",
            "training.trajectory",
            "the first valid sample must start a stroke",
        )
    boundaries = starts + [valid_count]
    segments = tuple(
        rows[boundaries[index] : boundaries[index + 1], :]
        for index in range(len(starts))
    )
    variants = []
    if len(segments) > 1:
        variants.append(
            _rebuild_trajectory_segments(tuple(reversed(segments)), False, numpy)
        )
    variants.append(_rebuild_trajectory_segments(segments, True, numpy))
    unique = []
    seen = {value.tobytes()}
    for variant in variants:
        identity = variant.tobytes()
        if identity not in seen:
            seen.add(identity)
            unique.append(variant)
    return tuple(unique)


def _expanded_training_arrays(batch, records, numpy):
    trajectories = []
    rasters = []
    source_indices = []
    expanded_records = []
    for index, record in enumerate(records):
        variants = (batch.trajectory[index],) + build_trajectory_invariance_variants(
            batch.trajectory[index], numpy
        )
        for variant in variants:
            trajectories.append(variant)
            rasters.append(batch.raster[index])
            source_indices.append(index)
            expanded_records.append(record)
    targets = {
        name: numpy.asarray(value)[source_indices]
        for name, value in batch.targets.items()
    }
    active = {
        name: numpy.asarray(value)[source_indices]
        for name, value in batch.active.items()
    }
    return (
        numpy.stack(trajectories).astype(numpy.float32),
        numpy.stack(rasters).astype(numpy.float32),
        targets,
        active,
        tuple(expanded_records),
        tuple(source_indices),
    )


def _masked_factor_loss(
    outputs,
    targets,
    active,
    weights,
    supervised_head_names,
    batch_row_count,
    torch,
):
    if batch_row_count <= 0:
        raise ContractError(
            "invalid_training_row_count", "training.batch", "must not be empty"
        )
    losses = []
    for head in OUTPUT_HEADS:
        if head.name not in supervised_head_names:
            continue
        mask = active[head.name]
        if not bool(mask.any().item()):
            losses.append(outputs[head.name].sum() * 0.0)
            continue
        selected_output = outputs[head.name][mask]
        selected_target = targets[head.name][mask]
        selected_weight = weights[head.name][mask].to(dtype=selected_output.dtype)
        if head.is_independent_bernoulli:
            per_element = torch.nn.functional.binary_cross_entropy_with_logits(
                selected_output, selected_target, reduction="none"
            )
            per_sample = per_element.mean(dim=1)
        else:
            per_sample = torch.nn.functional.cross_entropy(
                selected_output, selected_target, reduction="none"
            )
        loss = (per_sample * selected_weight).sum() / float(batch_row_count)
        losses.append(loss)
    if not losses:
        raise ContractError("empty_supervision", "training", "no active factor targets")
    return torch.stack(losses).mean()


def fit_development_partition(
    development: Sequence[CorpusRecord],
    data_root: Path,
    config: TrainingConfig,
    model_factory: Callable[[], object],
) -> DevelopmentPartitionFit:
    """Fit one already isolated development-writer partition.

    This lower-level boundary exists for development-only writer cross-
    validation. It never accepts calibration or sealed rows and it never emits
    a checkpoint or promotion artifact.
    """

    config.validate()
    assert_exact_role(development, PipelineRole.TRAINING)
    numpy = require_optional_dependency("numpy", "training")
    torch = require_optional_dependency("torch", "training")
    _seed_everything(config.seed, numpy, torch)
    batch = load_numpy_feature_batch(development, data_root)

    outcomes = {record.supervision_kind for record in development}
    has_negative_no_read_supervision = {
        CorpusSupervisionKind.NOTATION,
        CorpusSupervisionKind.NO_READ,
    }.issubset(outcomes)
    if not has_negative_no_read_supervision:
        # One-class validity loss manufactures confidence. Leave this head
        # unsupervised unless the independently adjudicated development split
        # contains both notation and true no-read examples.
        batch.active["validity"].fill(False)

    (
        expanded_trajectory,
        expanded_raster,
        expanded_targets,
        expanded_active,
        expanded_records,
        expanded_source_indices,
    ) = _expanded_training_arrays(batch, development, numpy)
    trajectory = torch.from_numpy(expanded_trajectory)
    raster = torch.from_numpy(expanded_raster)
    targets = {
        name: torch.from_numpy(value) for name, value in expanded_targets.items()
    }
    active = {
        name: torch.from_numpy(value) for name, value in expanded_active.items()
    }
    head_weights = training_head_weights(
        expanded_records,
        expanded_targets,
        expanded_active,
        config.categorical_class_reweighting,
        numpy,
        source_indices=expanded_source_indices,
    )
    head_weights, supervised_head_names = normalize_head_weights_for_minibatches(
        head_weights,
        len(expanded_records),
        numpy,
    )
    weights = {name: torch.from_numpy(value) for name, value in head_weights.items()}
    tensor_dataset = torch.utils.data.TensorDataset(
        trajectory,
        raster,
        *[targets[head.name] for head in OUTPUT_HEADS],
        *[active[head.name] for head in OUTPUT_HEADS],
        *[weights[head.name] for head in OUTPUT_HEADS],
    )
    generator = torch.Generator().manual_seed(config.seed)
    loader = torch.utils.data.DataLoader(
        tensor_dataset,
        batch_size=config.batch_size,
        shuffle=True,
        generator=generator,
        num_workers=0,
    )

    device = torch.device(config.device)
    model = model_factory().to(device)
    if getattr(model, "output_contract_version", None) != OUTPUT_CONTRACT_VERSION:
        raise ContractError(
            "output_contract_version_mismatch",
            "training.model",
            f"expected {OUTPUT_CONTRACT_VERSION}",
        )
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=float(config.learning_rate),
        weight_decay=float(config.weight_decay),
    )
    epoch_losses = []
    head_count = len(OUTPUT_HEADS)
    for _ in range(config.epochs):
        model.train()
        total = 0.0
        examples = 0
        for packed in loader:
            trajectory_part = packed[0].to(device)
            raster_part = packed[1].to(device)
            target_parts = packed[2 : 2 + head_count]
            active_parts = packed[2 + head_count : 2 + head_count * 2]
            weight_parts = packed[2 + head_count * 2 :]
            target_map = {
                head.name: value.to(device) for head, value in zip(OUTPUT_HEADS, target_parts)
            }
            active_map = {
                head.name: value.to(device) for head, value in zip(OUTPUT_HEADS, active_parts)
            }
            weight_map = {
                head.name: value.to(device) for head, value in zip(OUTPUT_HEADS, weight_parts)
            }
            optimizer.zero_grad(set_to_none=True)
            output = model(trajectory_part, raster_part)
            count = int(trajectory_part.shape[0])
            loss = _masked_factor_loss(
                output,
                target_map,
                active_map,
                weight_map,
                supervised_head_names,
                count,
                torch,
            )
            loss.backward()
            optimizer.step()
            total += float(loss.detach().cpu().item()) * count
            examples += count
        epoch_losses.append(total / examples)

    model.eval()
    return DevelopmentPartitionFit(
        model=model,
        epoch_losses=tuple(epoch_losses),
        sample_ids=batch.sample_ids,
        writer_hashes=tuple(sorted({record.writer_id_hash for record in development})),
        has_negative_no_read_supervision=has_negative_no_read_supervision,
    )


def train_development_model(
    records: Sequence[CorpusRecord],
    data_root: Path,
    config: TrainingConfig = TrainingConfig(),
    model_architecture_id: str = DUAL_VIEW_MODEL_ARCHITECTURE_ID,
    model_config: object | None = None,
    development_selection_authority: str = (
        UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY
    ),
    development_selection_report_sha256: str | None = None,
) -> TrainingResult:
    """Train on the development split only; never inspect calibration/sealed features."""

    config.validate()
    (
        development_selection_authority,
        development_selection_report_sha256,
    ) = validate_development_selection_binding(
        development_selection_authority,
        development_selection_report_sha256,
    )
    model_architecture_id = require_model_architecture_id(model_architecture_id)
    if model_config is None:
        model_config = default_model_config(model_architecture_id, config.seed)
    model_config.validate()
    development = select_role_records(records, PipelineRole.TRAINING)
    fit = fit_development_partition(
        development,
        data_root,
        config,
        lambda: make_chord_model(model_architecture_id, model_config),
    )
    return TrainingResult(
        model=fit.model,
        epoch_losses=fit.epoch_losses,
        development_sample_ids=fit.sample_ids,
        development_writer_hashes=fit.writer_hashes,
        seed=config.seed,
        model_architecture_id=model_architecture_id,
        model_config=model_config,
        training_config=config,
        development_records_sha256=records_digest(development),
        development_selection_authority=development_selection_authority,
        development_selection_report_sha256=(
            development_selection_report_sha256
        ),
        has_negative_no_read_supervision=fit.has_negative_no_read_supervision,
    )

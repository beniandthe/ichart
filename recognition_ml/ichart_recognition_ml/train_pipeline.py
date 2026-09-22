"""Deterministic development-only training for the dual-view factor model."""

from __future__ import annotations

import random
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence, Tuple

from .contracts import CorpusRecord, CorpusSupervisionKind, records_digest
from .dataset import (
    PipelineRole,
    assert_exact_role,
    load_numpy_feature_batch,
    require_optional_dependency,
    select_role_records,
)
from .errors import ContractError
from .models.dual_view import DualViewChordModel, DualViewModelConfig
from .models.output_contract import OUTPUT_CONTRACT_VERSION, OUTPUT_HEADS


@dataclass(frozen=True)
class TrainingConfig:
    seed: int = 17
    epochs: int = 40
    batch_size: int = 64
    learning_rate: float = 1e-3
    weight_decay: float = 1e-4
    device: str = "cpu"
    deterministic: bool = True

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


@dataclass(frozen=True)
class TrainingResult:
    model: object
    epoch_losses: Tuple[float, ...]
    development_sample_ids: Tuple[str, ...]
    development_writer_hashes: Tuple[str, ...]
    seed: int
    model_config: DualViewModelConfig
    training_config: TrainingConfig
    development_records_sha256: str
    has_negative_no_read_supervision: bool = False
    output_contract_version: str = OUTPUT_CONTRACT_VERSION
    is_calibrated: bool = False


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


def _masked_factor_loss(outputs, targets, active, torch):
    losses = []
    for head in OUTPUT_HEADS:
        mask = active[head.name]
        if not bool(mask.any().item()):
            continue
        selected_output = outputs[head.name][mask]
        selected_target = targets[head.name][mask]
        if head.is_independent_bernoulli:
            loss = torch.nn.functional.binary_cross_entropy_with_logits(
                selected_output, selected_target
            )
        else:
            loss = torch.nn.functional.cross_entropy(selected_output, selected_target)
        losses.append(loss)
    if not losses:
        raise ContractError("empty_supervision", "training", "no active factor targets")
    return torch.stack(losses).mean()


def train_development_model(
    records: Sequence[CorpusRecord],
    data_root: Path,
    config: TrainingConfig = TrainingConfig(),
    model_config: DualViewModelConfig = DualViewModelConfig(),
) -> TrainingResult:
    """Train on the development split only; never inspect calibration/sealed features."""

    config.validate()
    model_config.validate()
    development = select_role_records(records, PipelineRole.TRAINING)
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

    trajectory = torch.from_numpy(batch.trajectory)
    raster = torch.from_numpy(batch.raster)
    targets = {name: torch.from_numpy(value) for name, value in batch.targets.items()}
    active = {name: torch.from_numpy(value) for name, value in batch.active.items()}
    tensor_dataset = torch.utils.data.TensorDataset(
        trajectory,
        raster,
        *[targets[head.name] for head in OUTPUT_HEADS],
        *[active[head.name] for head in OUTPUT_HEADS],
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
    model = DualViewChordModel(model_config).to(device)
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
            active_parts = packed[2 + head_count :]
            target_map = {
                head.name: value.to(device) for head, value in zip(OUTPUT_HEADS, target_parts)
            }
            active_map = {
                head.name: value.to(device) for head, value in zip(OUTPUT_HEADS, active_parts)
            }
            optimizer.zero_grad(set_to_none=True)
            output = model(trajectory_part, raster_part)
            loss = _masked_factor_loss(output, target_map, active_map, torch)
            loss.backward()
            optimizer.step()
            count = int(trajectory_part.shape[0])
            total += float(loss.detach().cpu().item()) * count
            examples += count
        epoch_losses.append(total / examples)

    model.eval()
    return TrainingResult(
        model=model,
        epoch_losses=tuple(epoch_losses),
        development_sample_ids=batch.sample_ids,
        development_writer_hashes=tuple(sorted({record.writer_id_hash for record in development})),
        seed=config.seed,
        model_config=model_config,
        training_config=config,
        development_records_sha256=records_digest(development),
        has_negative_no_read_supervision=has_negative_no_read_supervision,
    )

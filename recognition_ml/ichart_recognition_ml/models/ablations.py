"""Deterministic single-view ablations for the frozen factor-logit contract.

Both ablations deliberately retain the dual-view call signature so the same
training/evaluation plumbing can compare them with ``DualViewChordModel``.
The unused input is shape-checked but never enters the computation graph.
Outputs are raw, uncalibrated logits for exactly ``OUTPUT_HEADS``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

from ..dataset import require_optional_dependency
from ..errors import ContractError
from ..schema import FEATURE_SCHEMA
from .dual_view import (
    RASTER_POOL_HEIGHT_BINS,
    RASTER_POOL_WIDTH_BINS,
    TRAJECTORY_POOL_BINS,
)
from .output_contract import HEAD_NAMES, OUTPUT_CONTRACT_VERSION, OUTPUT_HEADS


ABLATION_CONTRACT_VERSION = "chord-ink-single-view-ablation-v2-layout-preserving"


def _require_positive_integer(name: str, value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ContractError("invalid_ablation_config", name, "must be a positive integer")
    return value


def _require_seed(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ContractError(
            "invalid_ablation_config",
            "initialization_seed",
            "must be a nonnegative integer",
        )
    return value


@dataclass(frozen=True)
class TrajectoryOnlyModelConfig:
    """Frozen, data-independent trajectory ablation architecture."""

    channels: int = 64
    hidden_width: int = 192
    initialization_seed: int = 17
    contract_version: str = ABLATION_CONTRACT_VERSION

    def validate(self) -> None:
        if self.contract_version != ABLATION_CONTRACT_VERSION:
            raise ContractError(
                "ablation_contract_version_mismatch",
                "contract_version",
                f"expected {ABLATION_CONTRACT_VERSION}, got {self.contract_version}",
            )
        _require_positive_integer("channels", self.channels)
        _require_positive_integer("hidden_width", self.hidden_width)
        _require_seed(self.initialization_seed)


@dataclass(frozen=True)
class RasterOnlyModelConfig:
    """Frozen, data-independent raster ablation architecture."""

    channels: int = 48
    hidden_width: int = 192
    initialization_seed: int = 17
    contract_version: str = ABLATION_CONTRACT_VERSION

    def validate(self) -> None:
        if self.contract_version != ABLATION_CONTRACT_VERSION:
            raise ContractError(
                "ablation_contract_version_mismatch",
                "contract_version",
                f"expected {ABLATION_CONTRACT_VERSION}, got {self.contract_version}",
            )
        _require_positive_integer("channels", self.channels)
        _require_positive_integer("hidden_width", self.hidden_width)
        _require_seed(self.initialization_seed)


try:
    _torch = require_optional_dependency("torch", "training")
    _nn = _torch.nn
except Exception:  # Constructors below re-emit the precise dependency error.
    _torch = None
    _nn = None


if _nn is not None:

    class _RawFactorHeads(_nn.Module):
        def __init__(self, input_width: int):
            super().__init__()
            self.heads = _nn.ModuleDict(
                {
                    head.name: _nn.Linear(input_width, len(head.labels))
                    for head in OUTPUT_HEADS
                }
            )

        def forward(self, encoded) -> Dict[str, object]:
            return {head.name: self.heads[head.name](encoded) for head in OUTPUT_HEADS}


    def _validate_input_shapes(trajectory, raster) -> None:
        expected_trajectory = tuple(FEATURE_SCHEMA.trajectory_shape)
        expected_raster = (
            FEATURE_SCHEMA.raster_height,
            FEATURE_SCHEMA.raster_width,
            1,
        )
        if trajectory.ndim != 4 or tuple(trajectory.shape[1:]) != expected_trajectory:
            raise ValueError(
                f"trajectory must have shape [batch, {expected_trajectory}], "
                f"got {tuple(trajectory.shape)}"
            )
        if raster.ndim != 4 or tuple(raster.shape[1:]) != expected_raster:
            raise ValueError(
                f"raster must have shape [batch, {expected_raster}], got {tuple(raster.shape)}"
            )
        if trajectory.shape[0] != raster.shape[0]:
            raise ValueError(
                "trajectory and raster batch dimensions must match, got "
                f"{trajectory.shape[0]} and {raster.shape[0]}"
            )


    class TrajectoryOnlyChordModel(_nn.Module):
        """TCN-style trajectory ablation with no raster dependency."""

        output_contract_version = OUTPUT_CONTRACT_VERSION
        output_head_names = HEAD_NAMES
        model_architecture_id = "trajectory-only-v2-layout-preserving"
        ablation_contract_version = ABLATION_CONTRACT_VERSION
        input_view = "trajectory-only"

        def __init__(
            self,
            config: TrajectoryOnlyModelConfig = TrajectoryOnlyModelConfig(),
        ):
            super().__init__()
            config.validate()
            self.config = config
            # Model creation is reproducible and does not consume the caller's
            # global RNG stream. Training determinism remains the trainer's job.
            with _torch.random.fork_rng(devices=[]):
                _torch.manual_seed(config.initialization_seed)
                channels = config.channels
                self.encoder = _nn.Sequential(
                    _nn.Conv1d(
                        FEATURE_SCHEMA.trajectory_shape[2],
                        channels,
                        kernel_size=7,
                        padding=3,
                    ),
                    _nn.GELU(),
                    _nn.Conv1d(channels, channels, kernel_size=5, stride=2, padding=2),
                    _nn.GELU(),
                    _nn.Conv1d(
                        channels,
                        channels * 2,
                        kernel_size=3,
                        stride=2,
                        padding=1,
                    ),
                    _nn.GELU(),
                    _nn.AdaptiveAvgPool1d(TRAJECTORY_POOL_BINS),
                )
                self.projection = _nn.Sequential(
                    _nn.Linear(
                        channels * 2 * TRAJECTORY_POOL_BINS,
                        config.hidden_width,
                    ),
                    _nn.LayerNorm(config.hidden_width),
                    _nn.GELU(),
                )
                self.factor_heads = _RawFactorHeads(config.hidden_width)

        def forward(self, trajectory, raster) -> Dict[str, object]:
            _validate_input_shapes(trajectory, raster)
            encoded = self.encoder(trajectory.squeeze(1).transpose(1, 2)).flatten(1)
            return self.factor_heads(self.projection(encoded))


    class RasterOnlyChordModel(_nn.Module):
        """Spatial raster ablation with no trajectory dependency."""

        output_contract_version = OUTPUT_CONTRACT_VERSION
        output_head_names = HEAD_NAMES
        model_architecture_id = "raster-only-v2-layout-preserving"
        ablation_contract_version = ABLATION_CONTRACT_VERSION
        input_view = "raster-only"

        def __init__(self, config: RasterOnlyModelConfig = RasterOnlyModelConfig()):
            super().__init__()
            config.validate()
            self.config = config
            with _torch.random.fork_rng(devices=[]):
                _torch.manual_seed(config.initialization_seed)
                channels = config.channels
                self.encoder = _nn.Sequential(
                    _nn.Conv2d(1, channels, kernel_size=5, stride=2, padding=2),
                    _nn.GELU(),
                    _nn.Conv2d(channels, channels, kernel_size=3, stride=2, padding=1),
                    _nn.GELU(),
                    _nn.Conv2d(
                        channels,
                        channels * 2,
                        kernel_size=3,
                        stride=2,
                        padding=1,
                    ),
                    _nn.GELU(),
                    _nn.AdaptiveAvgPool2d(
                        (RASTER_POOL_HEIGHT_BINS, RASTER_POOL_WIDTH_BINS)
                    ),
                )
                self.projection = _nn.Sequential(
                    _nn.Linear(
                        channels
                        * 2
                        * RASTER_POOL_HEIGHT_BINS
                        * RASTER_POOL_WIDTH_BINS,
                        config.hidden_width,
                    ),
                    _nn.LayerNorm(config.hidden_width),
                    _nn.GELU(),
                )
                self.factor_heads = _RawFactorHeads(config.hidden_width)

        def forward(self, trajectory, raster) -> Dict[str, object]:
            _validate_input_shapes(trajectory, raster)
            encoded = self.encoder(raster.permute(0, 3, 1, 2)).flatten(1)
            return self.factor_heads(self.projection(encoded))


else:

    class TrajectoryOnlyChordModel:  # type: ignore[no-redef]
        output_contract_version = OUTPUT_CONTRACT_VERSION
        output_head_names = HEAD_NAMES
        model_architecture_id = "trajectory-only-v2-layout-preserving"
        ablation_contract_version = ABLATION_CONTRACT_VERSION
        input_view = "trajectory-only"

        def __init__(
            self,
            config: TrajectoryOnlyModelConfig = TrajectoryOnlyModelConfig(),
        ):
            config.validate()
            require_optional_dependency("torch", "training")


    class RasterOnlyChordModel:  # type: ignore[no-redef]
        output_contract_version = OUTPUT_CONTRACT_VERSION
        output_head_names = HEAD_NAMES
        model_architecture_id = "raster-only-v2-layout-preserving"
        ablation_contract_version = ABLATION_CONTRACT_VERSION
        input_view = "raster-only"

        def __init__(self, config: RasterOnlyModelConfig = RasterOnlyModelConfig()):
            config.validate()
            require_optional_dependency("torch", "training")

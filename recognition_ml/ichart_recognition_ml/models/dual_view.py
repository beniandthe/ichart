"""PyTorch dual-view trajectory/raster model with raw factor-logit heads."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

from ..dataset import require_optional_dependency
from ..errors import ContractError
from ..schema import FEATURE_SCHEMA
from .output_contract import HEAD_NAMES, OUTPUT_CONTRACT_VERSION, OUTPUT_HEADS


DUAL_VIEW_ARCHITECTURE_VERSION = "chord-ink-dual-view-v2-layout-preserving"
TRAJECTORY_POOL_BINS = 8
RASTER_POOL_HEIGHT_BINS = 3
RASTER_POOL_WIDTH_BINS = 8


@dataclass(frozen=True)
class DualViewModelConfig:
    trajectory_channels: int = 64
    raster_channels: int = 48
    fused_width: int = 192
    dropout: float = 0.10
    architecture_contract_version: str = DUAL_VIEW_ARCHITECTURE_VERSION

    def validate(self) -> None:
        if self.architecture_contract_version != DUAL_VIEW_ARCHITECTURE_VERSION:
            raise ContractError(
                "model_architecture_version_mismatch",
                "architecture_contract_version",
                f"expected {DUAL_VIEW_ARCHITECTURE_VERSION}, "
                f"got {self.architecture_contract_version}",
            )
        for name, value in (
            ("trajectory_channels", self.trajectory_channels),
            ("raster_channels", self.raster_channels),
            ("fused_width", self.fused_width),
        ):
            if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
                raise ContractError("invalid_model_config", name, "must be a positive integer")
        if not isinstance(self.dropout, (int, float)) or not 0.0 <= float(self.dropout) < 1.0:
            raise ContractError("invalid_model_config", "dropout", "must be in [0, 1)")


try:
    _torch = require_optional_dependency("torch", "training")
    _nn = _torch.nn
except Exception:  # Construction below re-emits the precise fail-closed error.
    _torch = None
    _nn = None


if _nn is not None:

    class DualViewChordModel(_nn.Module):
        """Fuses lossless trajectory features with the deterministic raster.

        Inputs use the exact Swift/Core ML shapes. Outputs are unnormalized,
        uncalibrated logits in the exact order declared by ``OUTPUT_HEADS``.
        """

        output_contract_version = OUTPUT_CONTRACT_VERSION
        output_head_names = HEAD_NAMES
        model_architecture_id = "dual-view-v2-layout-preserving"
        architecture_contract_version = DUAL_VIEW_ARCHITECTURE_VERSION

        def __init__(self, config: DualViewModelConfig = DualViewModelConfig()):
            super().__init__()
            config.validate()
            self.config = config
            tc = config.trajectory_channels
            rc = config.raster_channels

            self.trajectory_encoder = _nn.Sequential(
                _nn.Conv1d(FEATURE_SCHEMA.trajectory_shape[2], tc, kernel_size=7, padding=3),
                _nn.GELU(),
                _nn.Conv1d(tc, tc, kernel_size=5, stride=2, padding=2),
                _nn.GELU(),
                _nn.Conv1d(tc, tc * 2, kernel_size=3, stride=2, padding=1),
                _nn.GELU(),
                # Preserve coarse temporal position. A single global average
                # made early root strokes and late suffix/slash strokes
                # indistinguishable whenever their local features matched.
                _nn.AdaptiveAvgPool1d(TRAJECTORY_POOL_BINS),
            )
            self.raster_encoder = _nn.Sequential(
                _nn.Conv2d(1, rc, kernel_size=5, stride=2, padding=2),
                _nn.GELU(),
                _nn.Conv2d(rc, rc, kernel_size=3, stride=2, padding=1),
                _nn.GELU(),
                _nn.Conv2d(rc, rc * 2, kernel_size=3, stride=2, padding=1),
                _nn.GELU(),
                # Chord semantics are spatial: a glyph on the left is usually
                # the root while the same glyph after a slash is a bass note.
                # Retain a small layout grid instead of erasing position with
                # global average pooling.
                _nn.AdaptiveAvgPool2d(
                    (RASTER_POOL_HEIGHT_BINS, RASTER_POOL_WIDTH_BINS)
                ),
            )
            self.trajectory_projection = _nn.Sequential(
                _nn.Linear(tc * 2 * TRAJECTORY_POOL_BINS, config.fused_width),
                _nn.LayerNorm(config.fused_width),
                _nn.GELU(),
            )
            self.raster_projection = _nn.Sequential(
                _nn.Linear(
                    rc
                    * 2
                    * RASTER_POOL_HEIGHT_BINS
                    * RASTER_POOL_WIDTH_BINS,
                    config.fused_width,
                ),
                _nn.LayerNorm(config.fused_width),
                _nn.GELU(),
            )
            self.fusion = _nn.Sequential(
                _nn.Linear(config.fused_width * 2, config.fused_width),
                _nn.LayerNorm(config.fused_width),
                _nn.GELU(),
                _nn.Dropout(float(config.dropout)),
            )
            self.heads = _nn.ModuleDict(
                {
                    head.name: _nn.Linear(config.fused_width, len(head.labels))
                    for head in OUTPUT_HEADS
                }
            )

        def forward(self, trajectory, raster) -> Dict[str, object]:
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
            trajectory_features = self.trajectory_projection(self.trajectory_encoder(
                trajectory.squeeze(1).transpose(1, 2)
            ).flatten(1))
            raster_features = self.raster_projection(
                self.raster_encoder(raster.permute(0, 3, 1, 2)).flatten(1)
            )
            fused = self.fusion(_torch.cat((trajectory_features, raster_features), dim=1))
            return {head.name: self.heads[head.name](fused) for head in OUTPUT_HEADS}

else:

    class DualViewChordModel:  # type: ignore[no-redef]
        output_contract_version = OUTPUT_CONTRACT_VERSION
        output_head_names = HEAD_NAMES
        model_architecture_id = "dual-view-v2-layout-preserving"
        architecture_contract_version = DUAL_VIEW_ARCHITECTURE_VERSION

        def __init__(self, config: DualViewModelConfig = DualViewModelConfig()):
            config.validate()
            require_optional_dependency("torch", "training")

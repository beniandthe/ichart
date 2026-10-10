"""Frozen model-family identities and construction for training/checkpoints."""

from __future__ import annotations

from dataclasses import fields
from typing import Mapping, Tuple

from ..errors import ContractError
from .ablations import (
    RasterOnlyChordModel,
    RasterOnlyModelConfig,
    TrajectoryOnlyChordModel,
    TrajectoryOnlyModelConfig,
)
from .dual_view import DualViewChordModel, DualViewModelConfig


DUAL_VIEW_MODEL_ARCHITECTURE_ID = "dual-view-v2-layout-preserving"
TRAJECTORY_ONLY_MODEL_ARCHITECTURE_ID = (
    "trajectory-only-v2-layout-preserving"
)
RASTER_ONLY_MODEL_ARCHITECTURE_ID = "raster-only-v2-layout-preserving"
MODEL_ARCHITECTURE_IDS = (
    DUAL_VIEW_MODEL_ARCHITECTURE_ID,
    TRAJECTORY_ONLY_MODEL_ARCHITECTURE_ID,
    RASTER_ONLY_MODEL_ARCHITECTURE_ID,
)

_CONFIG_TYPES = {
    DUAL_VIEW_MODEL_ARCHITECTURE_ID: DualViewModelConfig,
    TRAJECTORY_ONLY_MODEL_ARCHITECTURE_ID: TrajectoryOnlyModelConfig,
    RASTER_ONLY_MODEL_ARCHITECTURE_ID: RasterOnlyModelConfig,
}
_MODEL_TYPES = {
    DUAL_VIEW_MODEL_ARCHITECTURE_ID: DualViewChordModel,
    TRAJECTORY_ONLY_MODEL_ARCHITECTURE_ID: TrajectoryOnlyChordModel,
    RASTER_ONLY_MODEL_ARCHITECTURE_ID: RasterOnlyChordModel,
}


def require_model_architecture_id(value: object) -> str:
    if value not in MODEL_ARCHITECTURE_IDS:
        raise ContractError(
            "unknown_model_architecture",
            "model_architecture_id",
            f"must be one of {', '.join(MODEL_ARCHITECTURE_IDS)}",
        )
    return str(value)


def default_model_config(
    architecture_id: str,
    initialization_seed: int,
):
    architecture_id = require_model_architecture_id(architecture_id)
    config_type = _CONFIG_TYPES[architecture_id]
    if architecture_id == DUAL_VIEW_MODEL_ARCHITECTURE_ID:
        return config_type()
    return config_type(initialization_seed=initialization_seed)


def model_config_from_mapping(
    architecture_id: str,
    value: object,
):
    architecture_id = require_model_architecture_id(architecture_id)
    if not isinstance(value, dict):
        raise ContractError("invalid_object", "metadata.model_config", "must be an object")
    config_type = _CONFIG_TYPES[architecture_id]
    expected = {field.name for field in fields(config_type)}
    missing = sorted(expected.difference(value.keys()))
    unknown = sorted(set(value.keys()).difference(expected))
    if missing:
        raise ContractError(
            "missing_checkpoint_field", "metadata.model_config", ", ".join(missing)
        )
    if unknown:
        raise ContractError(
            "unknown_checkpoint_field", "metadata.model_config", ", ".join(unknown)
        )
    try:
        config = config_type(**value)
    except TypeError as error:
        raise ContractError("invalid_checkpoint_config", "metadata.model_config", str(error))
    config.validate()
    return config


def make_chord_model(architecture_id: str, config):
    architecture_id = require_model_architecture_id(architecture_id)
    expected_config_type = _CONFIG_TYPES[architecture_id]
    if not isinstance(config, expected_config_type):
        raise ContractError(
            "model_config_architecture_mismatch",
            "model_config",
            f"{architecture_id} requires {expected_config_type.__name__}",
        )
    config.validate()
    return _MODEL_TYPES[architecture_id](config)


def candidate_model_factory(
    architecture_id: str,
    initialization_seed: int,
):
    config = default_model_config(architecture_id, initialization_seed)
    return lambda: make_chord_model(architecture_id, config)


def model_architecture_and_config_fields() -> Mapping[str, Tuple[str, ...]]:
    return {
        architecture_id: tuple(field.name for field in fields(config_type))
        for architecture_id, config_type in _CONFIG_TYPES.items()
    }

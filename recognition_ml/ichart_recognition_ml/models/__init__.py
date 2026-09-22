"""Dual-view learned model contracts.

The package imports without PyTorch. Constructing the model still fails closed
until the ``training`` optional dependency set is installed.
"""

from .output_contract import (
    OUTPUT_CONTRACT_VERSION,
    OUTPUT_HEADS,
    FactorHeadContract,
    FactorLogits,
    FactorTargets,
    factorize_canonical_label,
    factorize_corpus_record,
    factorize_ground_truth,
)


def __getattr__(name):
    if name in ("DualViewChordModel", "DualViewModelConfig"):
        from .dual_view import DualViewChordModel, DualViewModelConfig

        return {
            "DualViewChordModel": DualViewChordModel,
            "DualViewModelConfig": DualViewModelConfig,
        }[name]
    raise AttributeError(name)

__all__ = [
    "DualViewChordModel",
    "DualViewModelConfig",
    "FactorHeadContract",
    "FactorLogits",
    "FactorTargets",
    "OUTPUT_CONTRACT_VERSION",
    "OUTPUT_HEADS",
    "factorize_canonical_label",
    "factorize_corpus_record",
    "factorize_ground_truth",
]

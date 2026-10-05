"""Research-only support-conditioned metric over a frozen 128-D encoder.

The learned scorer sees class-relative support residuals, never class IDs or
query answers.  Encoder embeddings, generic logits, and the complete anchor
bank are detached at this boundary.  This module is an uncalibrated comparison
candidate; it has no acceptance, fallback-selection, or app routing authority.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

import torch
from torch import nn
from torch.nn import functional as F


VERSION = "personal-support-metric-v1"
PROTOCOL_PATH = "docs/personal-support-metric-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "bc94d5b92815119ba70d8c2abeb5b54dc42b1ec9801cc6bebbae2a07993decad"
FEATURE_COUNT = 128
CLASS_COUNT = 97
MAX_SUPPORT = 192
MAX_QUERIES = 512
UNIT_TOLERANCE = 1e-3
METRIC_DELTA_BOUND = 0.25
METRIC_LOGIT_SCALE = 10.0
SEED = 43


@dataclass(frozen=True)
class SupportMetricOutput:
    candidate_logits: torch.Tensor
    base_logits: torch.Tensor
    delta_metric: torch.Tensor
    metric: torch.Tensor
    support_class_indices: tuple[int, ...]
    effective_support_count: int


@dataclass(frozen=True)
class SupportMetricLoss:
    total: torch.Tensor
    cross_entropy: torch.Tensor
    untaught_kl: torch.Tensor
    locality: torch.Tensor


def _require_float64_cpu(value: torch.Tensor, shape_tail: tuple[int, ...], maximum: int,
                         *, allow_empty: bool) -> None:
    if (
        not isinstance(value, torch.Tensor)
        or value.device.type != "cpu"
        or value.dtype != torch.float64
        or value.ndim != len(shape_tail) + 1
        or tuple(value.shape[1:]) != shape_tail
        or value.shape[0] > maximum
        or (not allow_empty and value.shape[0] == 0)
        or not bool(torch.isfinite(value).all())
    ):
        raise ValueError("Invalid frozen tensor")


def _require_unit_rows(value: torch.Tensor, maximum: int, *, allow_empty: bool) -> None:
    _require_float64_cpu(value, (FEATURE_COUNT,), maximum, allow_empty=allow_empty)
    if value.shape[0]:
        norms = torch.linalg.vector_norm(value.detach(), dim=1)
        if bool(torch.any(torch.abs(norms - 1.0) > UNIT_TOLERANCE)):
            raise ValueError("Frozen embeddings must have unit norm")


def _row_key(row: torch.Tensor) -> bytes:
    frozen = row.detach().contiguous()
    return bytes(frozen.view(torch.uint8).reshape(-1).tolist())


def _mean_in_order(rows: Sequence[torch.Tensor]) -> torch.Tensor:
    if not rows:
        raise ValueError("Cannot average an empty sequence")
    return torch.stack(tuple(rows)).sum(dim=0) / len(rows)


def _validate_vocabulary(vocabulary: Sequence[str]) -> tuple[str, ...]:
    result = tuple(vocabulary)
    if (
        len(result) != CLASS_COUNT
        or len(set(result)) != CLASS_COUNT
        or any(not isinstance(label, str) or not label for label in result)
    ):
        raise ValueError("Invalid full vocabulary")
    return result


class PersonalSupportMetric(nn.Module):
    """A bounded metric update whose range lies in the support-residual span."""

    version = VERSION

    def __init__(self) -> None:
        super().__init__()
        with torch.random.fork_rng(devices=[]):
            torch.manual_seed(SEED)
            self.scorer = nn.Sequential(
                nn.Linear(FEATURE_COUNT * 2, 32),
                nn.GELU(),
                nn.Linear(32, 1),
            ).double()
        nn.init.zeros_(self.scorer[-1].weight)
        nn.init.zeros_(self.scorer[-1].bias)

    def _check_runtime(self) -> None:
        parameters = tuple(self.parameters())
        if (
            not parameters
            or any(value.device.type != "cpu" or value.dtype != torch.float64 for value in parameters)
            or any(not bool(torch.isfinite(value).all()) for value in parameters)
        ):
            raise ValueError("Metric scorer must remain deterministic CPU Float64")

    def _support_delta(
        self,
        support_embeddings: torch.Tensor,
        support_labels: Sequence[str],
        anchors: torch.Tensor,
        vocabulary: tuple[str, ...],
    ) -> tuple[torch.Tensor, tuple[int, ...], int]:
        labels = tuple(support_labels)
        if len(labels) != support_embeddings.shape[0]:
            raise ValueError("Support labels do not align with embeddings")
        lookup = {label: index for index, label in enumerate(vocabulary)}
        if any(not isinstance(label, str) or label not in lookup for label in labels):
            raise ValueError("Support label is outside the full vocabulary")

        # Exact duplicate lessons are one observation.  The same frozen vector
        # cannot support two identities.  Canonical byte order makes summation
        # independent of caller order without using label spelling as a feature.
        unique: dict[bytes, tuple[torch.Tensor, str]] = {}
        for row, label in zip(support_embeddings.detach(), labels, strict=True):
            key = _row_key(row)
            previous = unique.get(key)
            if previous is not None and previous[1] != label:
                raise ValueError("Identical support vector has conflicting labels")
            unique[key] = (row, label)

        grouped: dict[int, list[torch.Tensor]] = {}
        for key in sorted(unique):
            row, label = unique[key]
            index = lookup[label]
            residual = row - anchors[index]
            grouped.setdefault(index, []).append(residual)
        if not grouped:
            zero = anchors.new_zeros((FEATURE_COUNT, FEATURE_COUNT))
            return zero, (), 0

        # Context and denominators retain every unique labeled lesson, including
        # exact-zero residuals.  Zero residuals contribute no direction but do
        # not silently give the remaining lessons extra metric weight.
        # Every reduction has a fixed source-derived order.  In particular, do
        # not sort learned contribution tensors: that would serialize a 128x128
        # matrix per class on every forward and make ordering depend on model
        # state.  Residual-byte tuples remain stable under caller order and a
        # simultaneous vocabulary/anchor permutation.
        ordered_classes = []
        for index, rows in grouped.items():
            ordered = tuple(sorted(rows, key=_row_key))
            ordered_classes.append((tuple(_row_key(row) for row in ordered), index, ordered))
        ordered_classes.sort(key=lambda item: item[0])
        class_means = [_mean_in_order(rows) for _, _, rows in ordered_classes]
        context = _mean_in_order(class_means)
        class_contributions = []
        effective_count = 0
        for _, _, rows in ordered_classes:
            contributions = []
            for residual in rows:
                norm = torch.linalg.vector_norm(residual)
                if bool(torch.all(residual == 0)):
                    contributions.append(anchors.new_zeros((FEATURE_COUNT, FEATURE_COUNT)))
                    continue
                if not bool(torch.isfinite(norm)) or norm.detach().item() <= 0:
                    raise ValueError("Invalid nonzero support residual")
                direction = residual / norm
                alpha = torch.tanh(self.scorer(torch.cat((residual, context)))).squeeze()
                contributions.append(alpha * torch.outer(direction, direction))
                effective_count += 1
            class_contributions.append(_mean_in_order(contributions))
        delta = METRIC_DELTA_BOUND * _mean_in_order(class_contributions)
        if delta.shape != (FEATURE_COUNT, FEATURE_COUNT) or not bool(torch.isfinite(delta).all()):
            raise ValueError("Invalid support-conditioned metric")
        return delta, tuple(sorted(grouped)), effective_count

    def forward(
        self,
        query_embeddings: torch.Tensor,
        generic_logits: torch.Tensor,
        anchors: torch.Tensor,
        vocabulary: Sequence[str],
        support_embeddings: torch.Tensor,
        support_labels: Sequence[str],
    ) -> SupportMetricOutput:
        self._check_runtime()
        words = _validate_vocabulary(vocabulary)
        _require_unit_rows(query_embeddings, MAX_QUERIES, allow_empty=False)
        _require_unit_rows(anchors, CLASS_COUNT, allow_empty=False)
        _require_unit_rows(support_embeddings, MAX_SUPPORT, allow_empty=True)
        if anchors.shape[0] != CLASS_COUNT:
            raise ValueError("Anchor bank must cover the full vocabulary")
        _require_float64_cpu(generic_logits, (CLASS_COUNT,), MAX_QUERIES, allow_empty=False)
        if generic_logits.shape[0] != query_embeddings.shape[0]:
            raise ValueError("Generic logits do not align with queries")

        # This is a frozen-representation boundary.  Gradients update only the
        # support-conditioned scorer, never encoder outputs or generic logits.
        queries = query_embeddings.detach()
        base = generic_logits.detach()
        fixed_anchors = anchors.detach()
        support = support_embeddings.detach()
        delta, support_indices, effective_count = self._support_delta(
            support, support_labels, fixed_anchors, words,
        )
        identity = torch.eye(FEATURE_COUNT, dtype=torch.float64)
        metric = identity + delta
        if effective_count == 0:
            return SupportMetricOutput(base, base, delta, metric, support_indices, 0)

        # Use the same base terms in both cosines.  At zero initialization the
        # subtraction is exactly zero while retaining a differentiable path to
        # scorer parameters; do not branch on a zero learned DeltaM.
        base_numerator = queries @ fixed_anchors.T
        base_query_norm = torch.sum(queries * queries, dim=1, keepdim=True)
        base_anchor_norm = torch.sum(fixed_anchors * fixed_anchors, dim=1).unsqueeze(0)
        base_denominator = torch.sqrt(base_query_norm * base_anchor_norm)
        base_cosine = base_numerator / base_denominator

        query_delta = queries @ delta
        anchor_delta = fixed_anchors @ delta
        metric_numerator = base_numerator + query_delta @ fixed_anchors.T
        metric_query_norm = base_query_norm + torch.sum(query_delta * queries, dim=1, keepdim=True)
        metric_anchor_norm = base_anchor_norm + torch.sum(
            anchor_delta * fixed_anchors, dim=1,
        ).unsqueeze(0)
        if bool(torch.any(metric_query_norm <= 0)) or bool(torch.any(metric_anchor_norm <= 0)):
            raise ValueError("Metric lost positive definiteness")
        metric_cosine = metric_numerator / torch.sqrt(metric_query_norm * metric_anchor_norm)
        candidate = base + METRIC_LOGIT_SCALE * (metric_cosine - base_cosine)
        if candidate.shape != base.shape or not bool(torch.isfinite(candidate).all()):
            raise ValueError("Invalid full-vocabulary candidate logits")
        return SupportMetricOutput(
            candidate, base, delta, metric, support_indices, effective_count,
        )


def support_metric_loss(output: SupportMetricOutput, query_targets: torch.Tensor) -> SupportMetricLoss:
    """Full-vocabulary objective; query identity is consumed only here."""

    if not isinstance(output, SupportMetricOutput) or output.effective_support_count <= 0:
        raise ValueError("Training requires nonzero support residuals")
    logits = output.candidate_logits
    base = output.base_logits
    if (
        not isinstance(query_targets, torch.Tensor)
        or query_targets.device.type != "cpu"
        or query_targets.dtype != torch.long
        or query_targets.shape != (logits.shape[0],)
        or bool(torch.any(query_targets < 0))
        or bool(torch.any(query_targets >= CLASS_COUNT))
    ):
        raise ValueError("Invalid loss-only query targets")
    taught = torch.zeros_like(query_targets, dtype=torch.bool)
    for index in output.support_class_indices:
        taught |= query_targets == index
    untaught = ~taught
    if not bool(taught.any()) or not bool(untaught.any()):
        raise ValueError("Training requires taught and untaught queries")

    cross_entropy = F.cross_entropy(logits, query_targets)
    base_probabilities = F.softmax(base[untaught], dim=1)
    untaught_kl = F.kl_div(
        F.log_softmax(logits[untaught], dim=1),
        base_probabilities,
        reduction="batchmean",
    )
    locality = torch.sum(output.delta_metric * output.delta_metric)
    total = cross_entropy + untaught_kl + 0.1 * locality
    if not bool(torch.isfinite(total)):
        raise ValueError("Nonfinite metric-learning loss")
    return SupportMetricLoss(total, cross_entropy, untaught_kl, locality)

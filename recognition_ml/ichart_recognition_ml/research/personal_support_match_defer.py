"""Research-only joint support matching with an explicit DEFER outcome.

The matcher is class-ID-free: confirmed support labels remain sidecar metadata
and never enter learned layers.  DEFER preserves this candidate model's own
generic logits exactly; joint training may still change those logits relative
to any control or production model.  Nothing here is calibrated acceptance.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import string
from typing import Callable, Sequence

import torch
from torch import nn
from torch.nn import functional as F

from ..features import RASTER_HEIGHT, RASTER_WIDTH
from .personal_visual_encoder import PersonalVisualEncoder


VERSION = "personal-support-match-defer-v1"
GENERIC_LABEL_COUNT = 97
FEATURE_COUNT = 128
MAX_SUPPORT_EXAMPLES = 192
MAX_QUERY_BATCH = 512
UNIT_TOLERANCE = 1e-3


class InferenceScope(str, Enum):
    RESEARCH_COMPARISON_ONLY = "uncalibrated-research-comparison-only"


class RouteKind(str, Enum):
    GENERIC = "generic"
    EXPLICIT_SUPPORT = "explicit-support"


@dataclass(frozen=True)
class PooledSupport:
    labels: tuple[str, ...]
    prototypes: torch.Tensor
    counts: tuple[int, ...]
    support_ids: tuple[tuple[str, ...], ...]
    source_hashes: tuple[tuple[str, ...], ...]
    ink_hashes: tuple[tuple[str, ...], ...]


@dataclass(frozen=True)
class EpisodeEncoding:
    support_embeddings: torch.Tensor
    query_embeddings: torch.Tensor
    support_generic_logits: torch.Tensor
    query_generic_logits: torch.Tensor


@dataclass(frozen=True)
class MatchDeferOutput:
    scope: InferenceScope
    encoding: EpisodeEncoding
    support: PooledSupport
    match_defer_logits: torch.Tensor | None


@dataclass(frozen=True)
class RoutedPrediction:
    scope: InferenceScope
    generic_logits: torch.Tensor
    route_kinds: tuple[RouteKind, ...]
    support_labels: tuple[str | None, ...]


@dataclass(frozen=True)
class TrainingLoss:
    total: torch.Tensor
    generic: torch.Tensor
    match_defer: torch.Tensor


@dataclass(frozen=True)
class JointTrainingTargets:
    generic: torch.Tensor
    match_defer: torch.Tensor


def _is_sha256(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in string.hexdigits for character in value)
        and value == value.lower()
    )


def _validate_unit_features(
    values: torch.Tensor,
    *,
    allow_empty: bool,
    maximum: int,
) -> None:
    if (
        not isinstance(values, torch.Tensor)
        or values.ndim != 2
        or values.shape[1] != FEATURE_COUNT
        or (not allow_empty and values.shape[0] == 0)
        or values.shape[0] > maximum
        or not values.dtype.is_floating_point
        or not bool(torch.isfinite(values).all())
    ):
        raise ValueError("Invalid embedding matrix")
    if values.shape[0]:
        norms = torch.linalg.vector_norm(values, dim=1)
        if bool(torch.any(torch.abs(norms - 1) > UNIT_TOLERANCE)):
            raise ValueError("Embeddings must have unit norm")


def _validate_rasters(values: torch.Tensor, *, maximum: int, allow_empty: bool) -> None:
    if (
        not isinstance(values, torch.Tensor)
        or values.ndim != 4
        or tuple(values.shape[1:]) != (1, RASTER_HEIGHT, RASTER_WIDTH)
        or values.shape[0] > maximum
        or (not allow_empty and values.shape[0] == 0)
        or not values.dtype.is_floating_point
        or not bool(torch.isfinite(values).all())
    ):
        raise ValueError("Invalid normalized raster batch")
    if values.numel() and (bool(torch.any(values < 0)) or bool(torch.any(values > 1))):
        raise ValueError("Raster values must be in [0, 1]")


def _validate_pooled_support(support: PooledSupport) -> None:
    if not isinstance(support, PooledSupport):
        raise ValueError("Invalid pooled support")
    count = len(support.labels)
    _validate_unit_features(
        support.prototypes,
        allow_empty=True,
        maximum=MAX_SUPPORT_EXAMPLES,
    )
    if (
        support.prototypes.shape[0] != count
        or len(set(support.labels)) != count
        or any(not isinstance(label, str) or not label for label in support.labels)
        or len(support.counts) != count
        or len(support.support_ids) != count
        or len(support.source_hashes) != count
        or len(support.ink_hashes) != count
        or any(value <= 0 for value in support.counts)
        or sum(support.counts) > MAX_SUPPORT_EXAMPLES
    ):
        raise ValueError("Malformed pooled support")
    flat_ids = tuple(value for group in support.support_ids for value in group)
    flat_sources = tuple(value for group in support.source_hashes for value in group)
    flat_inks = tuple(value for group in support.ink_hashes for value in group)
    if (
        tuple(map(len, support.support_ids)) != support.counts
        or tuple(map(len, support.source_hashes)) != support.counts
        or tuple(map(len, support.ink_hashes)) != support.counts
        or len(set(flat_ids)) != len(flat_ids)
        or len(set(flat_sources)) != len(flat_sources)
        or len(set(flat_inks)) != len(flat_inks)
        or any(not isinstance(value, str) or not value for value in flat_ids)
        or any(not _is_sha256(value) for value in (*flat_sources, *flat_inks))
    ):
        raise ValueError("Malformed support provenance")


def pool_confirmed_support(
    embeddings: torch.Tensor,
    labels: Sequence[str],
    support_ids: Sequence[str],
    source_hashes: Sequence[str],
    ink_hashes: Sequence[str],
    is_allowed_label: Callable[[str], bool],
) -> PooledSupport:
    """Pool repeated exact labels in deterministic ID order without detaching."""

    _validate_unit_features(
        embeddings,
        allow_empty=True,
        maximum=MAX_SUPPORT_EXAMPLES,
    )
    count = embeddings.shape[0]
    label_tuple = tuple(labels)
    id_tuple = tuple(support_ids)
    source_tuple = tuple(source_hashes)
    ink_tuple = tuple(ink_hashes)
    if (
        count > MAX_SUPPORT_EXAMPLES
        or any(len(values) != count for values in (label_tuple, id_tuple, source_tuple, ink_tuple))
        or not callable(is_allowed_label)
        or any(not isinstance(label, str) or not label for label in label_tuple)
        or any(not bool(is_allowed_label(label)) for label in label_tuple)
        or any(not isinstance(value, str) or not value for value in id_tuple)
        or len(set(id_tuple)) != count
        or any(not _is_sha256(value) for value in (*source_tuple, *ink_tuple))
        or len(set(source_tuple)) != count
        or len(set(ink_tuple)) != count
    ):
        raise ValueError("Invalid or unsupported confirmed support")
    ordered_labels = tuple(sorted(set(label_tuple)))
    if not ordered_labels:
        result = PooledSupport((), embeddings.new_empty((0, FEATURE_COUNT)), (), (), (), ())
        _validate_pooled_support(result)
        return result

    prototypes = []
    grouped_ids = []
    grouped_sources = []
    grouped_inks = []
    counts = []
    for label in ordered_labels:
        indexes = sorted(
            (index for index, value in enumerate(label_tuple) if value == label),
            key=lambda index: (id_tuple[index], source_tuple[index], ink_tuple[index]),
        )
        selected = embeddings[torch.tensor(indexes, device=embeddings.device)]
        mean = selected.mean(dim=0)
        norm = torch.linalg.vector_norm(mean)
        if not bool(torch.isfinite(norm)) or float(norm.detach()) <= 0:
            raise ValueError("Support prototype has zero or nonfinite norm")
        prototypes.append(mean / norm)
        counts.append(len(indexes))
        grouped_ids.append(tuple(id_tuple[index] for index in indexes))
        grouped_sources.append(tuple(source_tuple[index] for index in indexes))
        grouped_inks.append(tuple(ink_tuple[index] for index in indexes))
    result = PooledSupport(
        labels=ordered_labels,
        prototypes=torch.stack(prototypes),
        counts=tuple(counts),
        support_ids=tuple(grouped_ids),
        source_hashes=tuple(grouped_sources),
        ink_hashes=tuple(grouped_inks),
    )
    _validate_pooled_support(result)
    return result


class PersonalSupportMatchDeferModel(nn.Module):
    version = VERSION
    scope = InferenceScope.RESEARCH_COMPARISON_ONLY

    def __init__(self) -> None:
        super().__init__()
        self.encoder = PersonalVisualEncoder(GENERIC_LABEL_COUNT)
        self.relation_mlp = nn.Sequential(
            nn.Linear(FEATURE_COUNT * 4, 64),
            nn.GELU(),
            nn.Linear(64, 1),
        )
        self.defer_mlp = nn.Sequential(
            nn.Linear(FEATURE_COUNT, 64),
            nn.GELU(),
            nn.Linear(64, 1),
        )

    def encode_episode(
        self,
        support_rasters: torch.Tensor,
        query_rasters: torch.Tensor,
    ) -> EpisodeEncoding:
        """Encode support then query in one ordered call for matched BN exposure."""

        _validate_rasters(support_rasters, maximum=MAX_SUPPORT_EXAMPLES, allow_empty=True)
        _validate_rasters(query_rasters, maximum=MAX_QUERY_BATCH, allow_empty=False)
        if support_rasters.dtype != query_rasters.dtype or support_rasters.device != query_rasters.device:
            raise ValueError("Support and query rasters must share dtype and device")
        support_count = support_rasters.shape[0]
        combined = torch.cat((support_rasters, query_rasters), dim=0)
        embeddings, logits = self.encoder(combined)
        if (
            embeddings.shape != (len(combined), FEATURE_COUNT)
            or logits.shape != (len(combined), GENERIC_LABEL_COUNT)
            or not bool(torch.isfinite(logits).all())
        ):
            raise ValueError("Encoder output contract changed")
        _validate_unit_features(
            embeddings,
            allow_empty=False,
            maximum=MAX_SUPPORT_EXAMPLES + MAX_QUERY_BATCH,
        )
        return EpisodeEncoding(
            support_embeddings=embeddings[:support_count],
            query_embeddings=embeddings[support_count:],
            support_generic_logits=logits[:support_count],
            query_generic_logits=logits[support_count:],
        )

    def match_defer_logits(
        self,
        query_embeddings: torch.Tensor,
        support_prototypes: torch.Tensor,
    ) -> torch.Tensor:
        _validate_unit_features(
            query_embeddings,
            allow_empty=False,
            maximum=MAX_QUERY_BATCH,
        )
        _validate_unit_features(
            support_prototypes,
            allow_empty=False,
            maximum=MAX_SUPPORT_EXAMPLES,
        )
        if support_prototypes.shape[0] > MAX_SUPPORT_EXAMPLES:
            raise ValueError("Too many support prototypes")
        batch = query_embeddings.shape[0]
        count = support_prototypes.shape[0]
        query = query_embeddings[:, None, :].expand(batch, count, FEATURE_COUNT)
        support = support_prototypes[None, :, :].expand(batch, count, FEATURE_COUNT)
        pair = torch.cat((query, support, torch.abs(query - support), query * support), dim=2)
        matches = self.relation_mlp(pair).squeeze(2)
        defer = self.defer_mlp(query_embeddings)
        logits = torch.cat((matches, defer), dim=1)
        if logits.shape != (batch, count + 1) or not bool(torch.isfinite(logits).all()):
            raise ValueError("Nonfinite match/defer logits")
        return logits

    def forward(
        self,
        query_embeddings: torch.Tensor,
        support_prototypes: torch.Tensor,
    ) -> torch.Tensor:
        """Tensor-only learned relation; labels and provenance stay outside."""

        return self.match_defer_logits(query_embeddings, support_prototypes)


def make_match_defer_output(
    model: PersonalSupportMatchDeferModel,
    encoding: EpisodeEncoding,
    support: PooledSupport,
) -> MatchDeferOutput:
    """Join already validated sidecars to tensor-only matcher output."""

    if not isinstance(model, PersonalSupportMatchDeferModel):
        raise ValueError("Invalid match/defer model")
    if not isinstance(encoding, EpisodeEncoding):
        raise ValueError("Invalid episode encoding")
    _validate_pooled_support(support)
    _validate_unit_features(
        encoding.support_embeddings,
        allow_empty=True,
        maximum=MAX_SUPPORT_EXAMPLES,
    )
    _validate_unit_features(
        encoding.query_embeddings,
        allow_empty=False,
        maximum=MAX_QUERY_BATCH,
    )
    if (
        encoding.support_embeddings.shape[0] != sum(support.counts)
        or encoding.support_generic_logits.shape
        != (encoding.support_embeddings.shape[0], GENERIC_LABEL_COUNT)
        or encoding.query_generic_logits.shape
        != (encoding.query_embeddings.shape[0], GENERIC_LABEL_COUNT)
        or not bool(torch.isfinite(encoding.support_generic_logits).all())
        or not bool(torch.isfinite(encoding.query_generic_logits).all())
    ):
        raise ValueError("Episode encoding and support do not align")
    logits = model(encoding.query_embeddings, support.prototypes) if support.labels else None
    return MatchDeferOutput(model.scope, encoding, support, logits)


def prepare_match_defer_episode(
    model: PersonalSupportMatchDeferModel,
    support_rasters: torch.Tensor,
    query_rasters: torch.Tensor,
    *,
    support_labels: Sequence[str],
    support_ids: Sequence[str],
    source_hashes: Sequence[str],
    ink_hashes: Sequence[str],
    is_allowed_label: Callable[[str], bool],
) -> MatchDeferOutput:
    """Encode one ordered batch, then pool validated sidecars outside forward."""

    if not isinstance(model, PersonalSupportMatchDeferModel):
        raise ValueError("Invalid match/defer model")
    encoding = model.encode_episode(support_rasters, query_rasters)
    support = pool_confirmed_support(
        encoding.support_embeddings,
        support_labels,
        support_ids,
        source_hashes,
        ink_hashes,
        is_allowed_label,
    )
    return make_match_defer_output(model, encoding, support)


def route_match_or_defer(
    output: MatchDeferOutput,
    *,
    is_allowed_label: Callable[[str], bool],
) -> RoutedPrediction:
    if not isinstance(output, MatchDeferOutput):
        raise ValueError("Invalid match/defer output")
    generic = output.encoding.query_generic_logits
    if (
        generic.ndim != 2
        or generic.shape[1] != GENERIC_LABEL_COUNT
        or not bool(torch.isfinite(generic).all())
    ):
        raise ValueError("Invalid candidate generic logits")
    _validate_pooled_support(output.support)
    if (
        not callable(is_allowed_label)
        or any(not bool(is_allowed_label(label)) for label in output.support.labels)
    ):
        raise ValueError("Unsupported support label at routing boundary")
    if not output.support.labels:
        if output.match_defer_logits is not None:
            raise ValueError("Empty support must skip matcher")
        return RoutedPrediction(
            output.scope,
            generic,
            (RouteKind.GENERIC,) * generic.shape[0],
            (None,) * generic.shape[0],
        )
    logits = output.match_defer_logits
    if (
        not isinstance(logits, torch.Tensor)
        or logits.shape != (generic.shape[0], len(output.support.labels) + 1)
        or not bool(torch.isfinite(logits).all())
    ):
        raise ValueError("Invalid match/defer output logits")
    defer_index = len(output.support.labels)
    labels = []
    for row in logits:
        maximum = row.max()
        winners = torch.nonzero(row == maximum, as_tuple=False).flatten().tolist()
        winner = winners[0] if len(winners) == 1 else defer_index
        labels.append(None if winner == defer_index else output.support.labels[winner])
    label_tuple = tuple(labels)
    kinds = tuple(
        RouteKind.GENERIC if label is None else RouteKind.EXPLICIT_SUPPORT
        for label in label_tuple
    )
    return RoutedPrediction(output.scope, generic, kinds, label_tuple)


def match_defer_targets(
    query_labels: Sequence[str],
    support_labels: Sequence[str],
    *,
    device: torch.device | str | None = None,
) -> torch.Tensor:
    """Truth-side training preparation only; never called by model.forward."""

    queries = tuple(query_labels)
    support = tuple(support_labels)
    if (
        not queries
        or len(set(support)) != len(support)
        or any(not isinstance(label, str) or not label for label in (*queries, *support))
    ):
        raise ValueError("Invalid loss-only label sidecar")
    indexes = {label: index for index, label in enumerate(support)}
    return torch.tensor(
        [indexes.get(label, len(support)) for label in queries],
        dtype=torch.long,
        device=device,
    )


def joint_training_targets(
    query_labels: Sequence[str],
    generic_vocabulary: Sequence[str],
    support_labels: Sequence[str],
    *,
    device: torch.device | str | None = None,
) -> JointTrainingTargets:
    """Derive both target tensors from one truth sidecar outside the model."""

    queries = tuple(query_labels)
    vocabulary = tuple(generic_vocabulary)
    support = tuple(support_labels)
    if (
        len(vocabulary) != GENERIC_LABEL_COUNT
        or len(set(vocabulary)) != GENERIC_LABEL_COUNT
        or any(not isinstance(label, str) or not label for label in vocabulary)
        or any(label not in vocabulary for label in queries)
        or any(label not in vocabulary for label in support)
    ):
        raise ValueError("Invalid joint training vocabulary or labels")
    generic_indexes = {label: index for index, label in enumerate(vocabulary)}
    generic = torch.tensor(
        [generic_indexes[label] for label in queries],
        dtype=torch.long,
        device=device,
    )
    match = match_defer_targets(queries, support, device=device)
    return JointTrainingTargets(generic, match)


def joint_training_loss(
    generic_logits: torch.Tensor,
    generic_targets: torch.Tensor,
    match_defer_logits: torch.Tensor,
    match_targets: torch.Tensor,
) -> TrainingLoss:
    """Generic CE plus equally weighted taught/untaught match-defer CE."""

    if (
        generic_logits.ndim != 2
        or generic_logits.shape[1] != GENERIC_LABEL_COUNT
        or not bool(torch.isfinite(generic_logits).all())
        or generic_targets.shape != (generic_logits.shape[0],)
        or generic_targets.dtype != torch.long
        or match_defer_logits.ndim != 2
        or match_defer_logits.shape[0] != generic_logits.shape[0]
        or match_defer_logits.shape[1] < 2
        or not bool(torch.isfinite(match_defer_logits).all())
        or match_targets.shape != (generic_logits.shape[0],)
        or match_targets.dtype != torch.long
    ):
        raise ValueError("Invalid training loss inputs")
    if (
        bool(torch.any(generic_targets < 0))
        or bool(torch.any(generic_targets >= GENERIC_LABEL_COUNT))
        or bool(torch.any(match_targets < 0))
        or bool(torch.any(match_targets >= match_defer_logits.shape[1]))
    ):
        raise ValueError("Training target outside output domain")
    defer_index = match_defer_logits.shape[1] - 1
    taught = match_targets != defer_index
    untaught = match_targets == defer_index
    if not bool(taught.any()) or not bool(untaught.any()):
        raise ValueError("Balanced loss requires taught and untaught queries")
    generic_loss = F.cross_entropy(generic_logits, generic_targets)
    per_query = F.cross_entropy(match_defer_logits, match_targets, reduction="none")
    match_loss = 0.5 * per_query[taught].mean() + 0.5 * per_query[untaught].mean()
    total = generic_loss + match_loss
    if not bool(torch.isfinite(total)):
        raise ValueError("Nonfinite training loss")
    return TrainingLoss(total, generic_loss, match_loss)

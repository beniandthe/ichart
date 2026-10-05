"""Research-only chord-domain classifier with one explicit reject outcome.

The control preserves the frozen 102-way raster-only encoder.  The candidate
shares its seed-29 feature initialization, copies the 46 legal classifier rows
exactly, and collapses every other source identity into one internal REJECT
output.  This module contains no corpus loader, fitting loop, scorer, app, or
profile entry point.
"""

from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Sequence

import torch
from torch import nn
from torch.nn import functional as F

from ..features import RASTER_HEIGHT, RASTER_WIDTH
from . import personal_stroke_field as field


VERSION = "personal-domain-reject-core-v1"
MODEL_VERSION = "personal-domain-reject-raster-encoder-v1"
SEED = 29
ARMS = ("control", "domainReject")
CONTROL_ARM, DOMAIN_REJECT_ARM = ARMS
REJECT_LABEL = "REJECT"
NOVEL_LEGAL_LABELS = ("#", "+", "/", "ø", "△")
SOURCE_LABEL_COUNT = 102
ORIGINAL_LEGAL_LABEL_COUNT = 41
LEGAL_LABEL_COUNT = ORIGINAL_LEGAL_LABEL_COUNT + len(NOVEL_LEGAL_LABELS)
CANDIDATE_LABEL_COUNT = LEGAL_LABEL_COUNT + 1
EMBEDDING_SIZE = field.EMBEDDING_SIZE


def _labels(values: Sequence[str], *, count: int, name: str) -> tuple[str, ...]:
    if isinstance(values, (str, bytes)):
        raise ValueError(f"{name} must be a label sequence")
    result = tuple(values)
    if len(result) != count:
        raise ValueError(f"{name} must contain exactly {count} labels")
    if any(type(label) is not str or not label for label in result):
        raise ValueError(f"{name} contains an invalid label")
    if len(set(result)) != len(result):
        raise ValueError(f"{name} labels must be unique")
    return result


@dataclass(frozen=True)
class DomainVocabulary:
    """Exact source and legal output identities for the fixed experiment."""

    source_labels: tuple[str, ...]
    legal_labels: tuple[str, ...]

    def __post_init__(self) -> None:
        source = _labels(
            self.source_labels, count=SOURCE_LABEL_COUNT, name="Source vocabulary"
        )
        legal = _labels(
            self.legal_labels, count=LEGAL_LABEL_COUNT, name="Legal vocabulary"
        )
        object.__setattr__(self, "source_labels", source)
        object.__setattr__(self, "legal_labels", legal)
        if legal[-len(NOVEL_LEGAL_LABELS) :] != NOVEL_LEGAL_LABELS:
            raise ValueError("The five novel legal labels have the wrong identity or order")
        if REJECT_LABEL in source or REJECT_LABEL in legal:
            raise ValueError("REJECT must not be a source or teachable label")
        if any(label not in source for label in legal):
            raise ValueError("Every legal label must occur in the source vocabulary")

    @property
    def candidate_labels(self) -> tuple[str, ...]:
        return self.legal_labels + (REJECT_LABEL,)

    @property
    def reject_index(self) -> int:
        return LEGAL_LABEL_COUNT

    @property
    def legal_source_indices(self) -> tuple[int, ...]:
        source_index = {label: index for index, label in enumerate(self.source_labels)}
        return tuple(source_index[label] for label in self.legal_labels)

    @property
    def forbidden_source_indices(self) -> tuple[int, ...]:
        legal = set(self.legal_source_indices)
        return tuple(index for index in range(SOURCE_LABEL_COUNT) if index not in legal)

    @property
    def source_to_candidate(self) -> tuple[int, ...]:
        legal_index = {label: index for index, label in enumerate(self.legal_labels)}
        return tuple(
            legal_index.get(label, self.reject_index) for label in self.source_labels
        )


def make_vocabulary(
    source102: Sequence[str], legalOld41: Sequence[str]
) -> DomainVocabulary:
    """Build the fixed 102-source / 46-legal / one-reject vocabulary."""

    source = _labels(source102, count=SOURCE_LABEL_COUNT, name="Source vocabulary")
    old = _labels(
        legalOld41,
        count=ORIGINAL_LEGAL_LABEL_COUNT,
        name="Original legal vocabulary",
    )
    if any(label in NOVEL_LEGAL_LABELS for label in old):
        raise ValueError("Novel legal labels must not occur in the original 41")
    return DomainVocabulary(source, old + NOVEL_LEGAL_LABELS)


class DomainRejectModel(nn.Module):
    """Frozen raster trunk with either the literal or domain-reject head."""

    def __init__(
        self,
        arm: str,
        convolution: nn.Module,
        projection: nn.Linear,
        classifier: nn.Linear,
    ):
        super().__init__()
        if arm not in ARMS:
            raise ValueError("Unknown domain-reject arm")
        expected_outputs = (
            SOURCE_LABEL_COUNT if arm == CONTROL_ARM else CANDIDATE_LABEL_COUNT
        )
        if (
            not isinstance(projection, nn.Linear)
            or projection.out_features != EMBEDDING_SIZE
            or not isinstance(classifier, nn.Linear)
            or classifier.in_features != EMBEDDING_SIZE
            or classifier.out_features != expected_outputs
        ):
            raise ValueError("Domain-reject model modules have the wrong shape")
        self.arm = arm
        self.label_count = expected_outputs
        self.convolution = convolution
        self.projection = projection
        self.classifier = classifier

    def forward(self, rasters: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        if (
            not isinstance(rasters, torch.Tensor)
            or rasters.ndim != 4
            or len(rasters) == 0
            or tuple(rasters.shape[1:]) != (1, RASTER_HEIGHT, RASTER_WIDTH)
        ):
            raise ValueError("Raster batch must have shape [B,1,96,256]")
        if rasters.dtype != torch.float32 or not bool(torch.isfinite(rasters).all()):
            raise ValueError("Raster batch must be finite Float32")

        # Reproduce the frozen raster-control boundary exactly: plane zero is
        # the caller's raster and the four auxiliary planes are explicit zero.
        fields = torch.cat((rasters, torch.zeros_like(rasters).expand(-1, 4, -1, -1)), 1)
        raw = self.projection(self.convolution(fields).flatten(1))
        logits = self.classifier(raw)
        if raw.shape != (len(rasters), EMBEDDING_SIZE) or logits.shape != (
            len(rasters),
            self.label_count,
        ):
            raise RuntimeError("Domain-reject model produced a malformed output")
        if not bool(torch.isfinite(raw).all()) or not bool(torch.isfinite(logits).all()):
            raise RuntimeError("Domain-reject model produced nonfinite output")
        return F.normalize(raw, dim=1), logits


def _same_feature_state(control: DomainRejectModel, candidate: DomainRejectModel) -> bool:
    for control_module, candidate_module in (
        (control.convolution, candidate.convolution),
        (control.projection, candidate.projection),
    ):
        left = control_module.state_dict()
        right = candidate_module.state_dict()
        if left.keys() != right.keys() or any(
            not torch.equal(left[key], right[key]) for key in left
        ):
            return False
    return True


def make_matched_models(
    vocabulary: DomainVocabulary,
) -> dict[str, DomainRejectModel]:
    """Create the fixed seed-29 control and matched 47-way candidate."""

    if not isinstance(vocabulary, DomainVocabulary):
        raise ValueError("A DomainVocabulary is required")
    # Accessing the properties also checks the expected 46/56 partition.
    if (
        len(vocabulary.legal_source_indices) != LEGAL_LABEL_COUNT
        or len(vocabulary.forbidden_source_indices)
        != SOURCE_LABEL_COUNT - LEGAL_LABEL_COUNT
    ):
        raise ValueError("Domain vocabulary partition changed")

    before = torch.get_rng_state().clone()
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(SEED)
        frozen = field.PersonalStrokeFieldEncoder(
            SOURCE_LABEL_COUNT, field.ARMS[0]
        )
        control = DomainRejectModel(
            CONTROL_ARM,
            copy.deepcopy(frozen.convolution),
            copy.deepcopy(frozen.projection),
            copy.deepcopy(frozen.classifier),
        )
        candidate_classifier = nn.Linear(EMBEDDING_SIZE, CANDIDATE_LABEL_COUNT)
        candidate = DomainRejectModel(
            DOMAIN_REJECT_ARM,
            copy.deepcopy(frozen.convolution),
            copy.deepcopy(frozen.projection),
            candidate_classifier,
        )
        with torch.no_grad():
            for destination, source in enumerate(vocabulary.legal_source_indices):
                candidate.classifier.weight[destination].copy_(
                    control.classifier.weight[source]
                )
                candidate.classifier.bias[destination].copy_(
                    control.classifier.bias[source]
                )
            forbidden = torch.tensor(
                vocabulary.forbidden_source_indices, dtype=torch.long
            )
            candidate.classifier.weight[vocabulary.reject_index].copy_(
                control.classifier.weight.index_select(0, forbidden).mean(0)
            )
            candidate.classifier.bias[vocabulary.reject_index].copy_(
                control.classifier.bias.index_select(0, forbidden).mean(0)
            )
    if not torch.equal(before, torch.get_rng_state()):
        raise RuntimeError("Domain-reject initialization changed global Torch RNG")
    if not _same_feature_state(control, candidate):
        raise RuntimeError("Matched feature initialization differs between arms")
    return {CONTROL_ARM: control, DOMAIN_REJECT_ARM: candidate}


def map_targets(
    sourceTargets: torch.Tensor, vocabulary: DomainVocabulary
) -> dict[str, torch.Tensor]:
    """Return literal control and collapsed candidate targets for one batch."""

    if not isinstance(vocabulary, DomainVocabulary):
        raise ValueError("A DomainVocabulary is required")
    if (
        not isinstance(sourceTargets, torch.Tensor)
        or sourceTargets.dtype != torch.long
        or sourceTargets.ndim != 1
        or len(sourceTargets) == 0
    ):
        raise ValueError("Source targets must be a nonempty one-dimensional Long tensor")
    if int(sourceTargets.min()) < 0 or int(sourceTargets.max()) >= SOURCE_LABEL_COUNT:
        raise ValueError("Source target is outside the 102-way vocabulary")
    lookup = torch.tensor(
        vocabulary.source_to_candidate,
        dtype=torch.long,
        device=sourceTargets.device,
    )
    return {
        CONTROL_ARM: sourceTargets.clone(),
        DOMAIN_REJECT_ARM: lookup.index_select(0, sourceTargets),
    }


def decode(
    logits: torch.Tensor, arm: str, vocabulary: DomainVocabulary
) -> tuple[str | None, ...]:
    """Decode first-argmax control or unique-max legal candidate outputs."""

    if arm not in ARMS or not isinstance(vocabulary, DomainVocabulary):
        raise ValueError("Unknown arm or vocabulary")
    width = SOURCE_LABEL_COUNT if arm == CONTROL_ARM else CANDIDATE_LABEL_COUNT
    if (
        not isinstance(logits, torch.Tensor)
        or logits.ndim != 2
        or len(logits) == 0
        or logits.shape[1] != width
        or not logits.is_floating_point()
        or not bool(torch.isfinite(logits).all())
    ):
        raise ValueError("Logits have the wrong shape, type, or finite values")

    legal = set(vocabulary.legal_labels)
    decoded: list[str | None] = []
    for row in logits:
        if arm == CONTROL_ARM:
            label = vocabulary.source_labels[int(torch.argmax(row))]
            decoded.append(label if label in legal else None)
            continue
        maximum = torch.max(row)
        winners = torch.nonzero(row == maximum, as_tuple=False).flatten()
        if len(winners) != 1:
            decoded.append(None)
            continue
        index = int(winners[0])
        decoded.append(
            None if index == vocabulary.reject_index else vocabulary.legal_labels[index]
        )
    return tuple(decoded)


def validate_teaching_labels(
    labels: Sequence[str], vocabulary: DomainVocabulary
) -> tuple[str, ...]:
    """Accept only exact legal fragments; REJECT is never teachable."""

    if not isinstance(vocabulary, DomainVocabulary) or isinstance(labels, (str, bytes)):
        raise ValueError("Teaching labels and vocabulary are required")
    result = tuple(labels)
    if not result or any(type(label) is not str for label in result):
        raise ValueError("Teaching labels must be a nonempty string sequence")
    legal = set(vocabulary.legal_labels)
    if any(label not in legal for label in result):
        raise ValueError("Teaching labels must belong to the legal chord domain")
    return result

"""Grammar-constrained parity decoder for the Swift learned runtime.

This module intentionally returns raw joint log scores.  It does not calibrate,
renormalize grammar survivors, or make an acceptance decision.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple

from .chord_notation import (
    FORM_ADDED_TONE,
    FORM_ALTERED,
    FORM_AUGMENTED,
    FORM_DIMINISHED,
    FORM_EXPLICIT_MAJOR,
    FORM_HALF_DIMINISHED,
    FORM_MINOR,
    FORM_MINOR_MAJOR,
    FORM_PLAIN,
    FORM_SUSPENDED,
    CanonicalChordLabel,
    CanonicalChordLabelError,
    Pitch,
    REPEAT_LABEL,
    parse_canonical_chord_label,
)
from .errors import ContractError
from .models.output_contract import (
    HEAD_BY_NAME,
    OUTPUT_CONTRACT_VERSION,
    FactorLogits,
)


EXPECTED_HEAD_NAMES = (
    "validity",
    "kind",
    "root_letter",
    "root_accidental",
    "quality",
    "extension",
    "alteration_logits",
    "slash_presence",
    "slash_bass_letter",
    "slash_bass_accidental",
)

_FORM_BY_FACTOR_LABEL = {
    "plain": FORM_PLAIN,
    "minor": FORM_MINOR,
    "explicitMajor": FORM_EXPLICIT_MAJOR,
    "minorMajor": FORM_MINOR_MAJOR,
    "augmented": FORM_AUGMENTED,
    "diminished": FORM_DIMINISHED,
    "halfDiminished": FORM_HALF_DIMINISHED,
    "suspended": FORM_SUSPENDED,
    "addedTone": FORM_ADDED_TONE,
    "altered": FORM_ALTERED,
}
_ACCIDENTAL_BY_FACTOR_LABEL = {"natural": "", "sharp": "#", "flat": "b"}


@dataclass(frozen=True)
class DecodedCandidate:
    canonical_label: str
    raw_joint_log_score: float


@dataclass(frozen=True)
class DecodeResult:
    candidates: Tuple[DecodedCandidate, ...]
    no_read_log_score: float


@dataclass(frozen=True)
class _Ranked:
    value: object
    score: float
    tie_key: str


@dataclass(frozen=True)
class _Suffix:
    form: str
    extension: Optional[str]
    alterations: Tuple[str, ...]


def _retain(candidate: _Ranked, ranked: List[_Ranked], limit: int) -> None:
    ranked.append(candidate)
    ranked.sort(key=lambda item: (-item.score, item.tie_key))
    del ranked[limit:]


def _log_softmax(logits: Sequence[float]) -> Tuple[float, ...]:
    maximum = max(logits)
    denominator = sum(math.exp(value - maximum) for value in logits)
    log_denominator = math.log(denominator)
    return tuple(value - maximum - log_denominator for value in logits)


def _log_sigmoid(value: float) -> float:
    if value >= 0:
        return -math.log1p(math.exp(-value))
    return value - math.log1p(math.exp(value))


def _validated_output(output: FactorLogits) -> FactorLogits:
    if not isinstance(output, FactorLogits):
        raise ContractError(
            "invalid_factor_output",
            "factor_logits",
            "expected FactorLogits",
        )
    if tuple(HEAD_BY_NAME) != EXPECTED_HEAD_NAMES or len(HEAD_BY_NAME) != 10:
        raise ContractError(
            "decoder_contract_mismatch",
            "factor_logits",
            "decoder requires the frozen ten-head factor contract",
        )
    return FactorLogits.from_mapping(
        output.values,
        contract_version=output.contract_version,
    )


def _top_root_choices(scores: dict[str, Tuple[float, ...]]) -> Tuple[_Ranked, ...]:
    letter_head = HEAD_BY_NAME["root_letter"]
    accidental_head = HEAD_BY_NAME["root_accidental"]
    result: List[_Ranked] = []
    for letter_index, letter in enumerate(letter_head.labels):
        for accidental_index, accidental_label in enumerate(accidental_head.labels):
            pitch = Pitch(letter, _ACCIDENTAL_BY_FACTOR_LABEL[accidental_label])
            _retain(
                _Ranked(
                    pitch,
                    scores["root_letter"][letter_index]
                    + scores["root_accidental"][accidental_index],
                    pitch.canonical_display,
                ),
                result,
                3,
            )
    return tuple(result)


def _alteration_subsets(
    logits: Sequence[float],
) -> Tuple[Tuple[Tuple[str, ...], float], ...]:
    labels = HEAD_BY_NAME["alteration_logits"].labels
    result = []
    for mask in range(1 << len(labels)):
        selected = []
        score = 0.0
        for index, (label, logit) in enumerate(zip(labels, logits)):
            if mask & (1 << index):
                selected.append(label)
                score += _log_sigmoid(logit)
            else:
                score += _log_sigmoid(-logit)
        # The frozen factor order is also the typed grammar's canonical order.
        result.append((tuple(selected), score))
    return tuple(result)


def _top_suffix_choices(
    scores: dict[str, Tuple[float, ...]],
    alteration_logits: Sequence[float],
) -> Tuple[_Ranked, ...]:
    quality_head = HEAD_BY_NAME["quality"]
    extension_head = HEAD_BY_NAME["extension"]
    result: List[_Ranked] = []
    subsets = _alteration_subsets(alteration_logits)
    for quality_index, quality_label in enumerate(quality_head.labels):
        form = _FORM_BY_FACTOR_LABEL[quality_label]
        for extension_index, extension_label in enumerate(extension_head.labels):
            extension = None if extension_label == "none" else extension_label
            for alterations, alteration_score in subsets:
                probe = CanonicalChordLabel(
                    is_repeat=False,
                    root=Pitch("C"),
                    form=form,
                    extension=extension,
                    alterations=alterations,
                )
                try:
                    canonical = probe.canonical_display
                    parse_canonical_chord_label(canonical)
                except CanonicalChordLabelError:
                    continue
                _retain(
                    _Ranked(
                        _Suffix(form, extension, alterations),
                        scores["quality"][quality_index]
                        + scores["extension"][extension_index]
                        + alteration_score,
                        canonical,
                    ),
                    result,
                    3,
                )
    return tuple(result)


def _top_slash_choices(scores: dict[str, Tuple[float, ...]]) -> Tuple[_Ranked, ...]:
    presence_head = HEAD_BY_NAME["slash_presence"]
    letter_head = HEAD_BY_NAME["slash_bass_letter"]
    accidental_head = HEAD_BY_NAME["slash_bass_accidental"]
    none_index = presence_head.labels.index("none")
    present_index = presence_head.labels.index("present")
    result: List[_Ranked] = []
    _retain(_Ranked(None, scores["slash_presence"][none_index], ""), result, 3)
    for letter_index, letter in enumerate(letter_head.labels):
        for accidental_index, accidental_label in enumerate(accidental_head.labels):
            pitch = Pitch(letter, _ACCIDENTAL_BY_FACTOR_LABEL[accidental_label])
            _retain(
                _Ranked(
                    pitch,
                    scores["slash_presence"][present_index]
                    + scores["slash_bass_letter"][letter_index]
                    + scores["slash_bass_accidental"][accidental_index],
                    pitch.canonical_display,
                ),
                result,
                3,
            )
    return tuple(result)


def decode_factor_logits(
    output: FactorLogits,
    maximum_candidate_count: int = 3,
) -> DecodeResult:
    """Decode the frozen ten-head output exactly like the Swift decoder.

    Categorical heads are independently log-softmaxed.  The seven alteration
    logits enumerate all ``2^7`` Bernoulli subsets.  Invalid typed-grammar
    combinations are discarded without renormalizing the surviving paths.
    """

    if isinstance(maximum_candidate_count, bool) or not isinstance(
        maximum_candidate_count, int
    ):
        raise ContractError(
            "invalid_candidate_count",
            "maximum_candidate_count",
            "must be an integer",
        )
    validated = _validated_output(output)
    requested_count = max(0, min(3, maximum_candidate_count))

    categorical_scores = {
        name: _log_softmax(validated.values[name])
        for name in EXPECTED_HEAD_NAMES
        if name != "alteration_logits"
    }
    validity_head = HEAD_BY_NAME["validity"]
    no_read_index = validity_head.labels.index("no_read")
    notation_index = validity_head.labels.index("notation")
    no_read_score = categorical_scores["validity"][no_read_index]
    if requested_count == 0:
        return DecodeResult(candidates=(), no_read_log_score=no_read_score)

    roots = _top_root_choices(categorical_scores)
    suffixes = _top_suffix_choices(
        categorical_scores,
        validated.values["alteration_logits"],
    )
    slash_choices = _top_slash_choices(categorical_scores)

    ranked: List[_Ranked] = []
    notation_base_score = categorical_scores["validity"][notation_index]
    kind_head = HEAD_BY_NAME["kind"]
    repeat_index = kind_head.labels.index("chord_repeat")
    rooted_index = kind_head.labels.index("rooted")
    _retain(
        _Ranked(
            REPEAT_LABEL,
            notation_base_score + categorical_scores["kind"][repeat_index],
            REPEAT_LABEL,
        ),
        ranked,
        requested_count,
    )

    for root in roots:
        for suffix in suffixes:
            suffix_value = suffix.value
            assert isinstance(suffix_value, _Suffix)
            for slash in slash_choices:
                slash_value = slash.value
                if slash_value is not None and not isinstance(slash_value, Pitch):
                    raise AssertionError("invalid internal slash choice")
                notation = CanonicalChordLabel(
                    is_repeat=False,
                    root=root.value,
                    form=suffix_value.form,
                    extension=suffix_value.extension,
                    alterations=suffix_value.alterations,
                    slash_bass=slash_value,
                )
                try:
                    canonical = notation.canonical_display
                    parsed = parse_canonical_chord_label(canonical)
                except CanonicalChordLabelError:
                    continue
                if parsed != notation:
                    continue
                _retain(
                    _Ranked(
                        canonical,
                        notation_base_score
                        + categorical_scores["kind"][rooted_index]
                        + root.score
                        + suffix.score
                        + slash.score,
                        canonical,
                    ),
                    ranked,
                    requested_count,
                )

    return DecodeResult(
        candidates=tuple(
            DecodedCandidate(
                canonical_label=str(candidate.value),
                raw_joint_log_score=candidate.score,
            )
            for candidate in ranked
        ),
        no_read_log_score=no_read_score,
    )

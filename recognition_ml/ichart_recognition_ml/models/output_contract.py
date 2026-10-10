"""Frozen factor-logit contract shared with the Swift learned runtime."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, Mapping, Optional, Sequence, Tuple, Union

from ..chord_notation import (
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
    parse_canonical_chord_label,
)
from ..errors import ContractError
from ..contracts import CorpusRecord, CorpusSupervisionKind
from ..schema import GROUND_TRUTH_CANONICAL, GROUND_TRUTH_NO_READ


OUTPUT_CONTRACT_VERSION = "chord-ink-factor-output-v1"


@dataclass(frozen=True)
class FactorHeadContract:
    name: str
    labels: Tuple[str, ...]
    is_independent_bernoulli: bool = False

    @property
    def shape(self) -> Tuple[int, int]:
        return (1, len(self.labels))


OUTPUT_HEADS = (
    FactorHeadContract("validity", ("no_read", "notation")),
    FactorHeadContract("kind", ("rooted", "chord_repeat")),
    FactorHeadContract("root_letter", tuple("ABCDEFG")),
    FactorHeadContract("root_accidental", ("natural", "sharp", "flat")),
    FactorHeadContract(
        "quality",
        (
            "plain",
            "minor",
            "explicitMajor",
            "minorMajor",
            "augmented",
            "diminished",
            "halfDiminished",
            "suspended",
            "addedTone",
            "altered",
        ),
    ),
    FactorHeadContract("extension", ("none", "2", "4", "6", "7", "9", "11", "13", "6/9")),
    FactorHeadContract(
        "alteration_logits",
        ("b3", "b5", "#5", "b9", "#9", "#11", "b13"),
        is_independent_bernoulli=True,
    ),
    FactorHeadContract("slash_presence", ("none", "present")),
    FactorHeadContract("slash_bass_letter", tuple("ABCDEFG")),
    FactorHeadContract("slash_bass_accidental", ("natural", "sharp", "flat")),
)

HEAD_BY_NAME = {head.name: head for head in OUTPUT_HEADS}
HEAD_NAMES = tuple(head.name for head in OUTPUT_HEADS)


@dataclass(frozen=True)
class FactorLogits:
    """One sample of raw, uncalibrated model output."""

    values: Mapping[str, Tuple[float, ...]]
    contract_version: str = OUTPUT_CONTRACT_VERSION

    @classmethod
    def from_mapping(
        cls,
        value: Mapping[str, Sequence[float]],
        contract_version: str = OUTPUT_CONTRACT_VERSION,
    ) -> "FactorLogits":
        if contract_version != OUTPUT_CONTRACT_VERSION:
            raise ContractError(
                "output_contract_version_mismatch",
                "factor_logits.contract_version",
                f"expected {OUTPUT_CONTRACT_VERSION}, got {contract_version}",
            )
        missing = sorted(set(HEAD_NAMES).difference(value.keys()))
        unknown = sorted(set(value.keys()).difference(HEAD_NAMES))
        if missing:
            raise ContractError("missing_output_head", "factor_logits", ", ".join(missing))
        if unknown:
            raise ContractError("unknown_output_head", "factor_logits", ", ".join(unknown))

        normalized: Dict[str, Tuple[float, ...]] = {}
        for head in OUTPUT_HEADS:
            raw = value[head.name]
            if isinstance(raw, (str, bytes)):
                raise ContractError(
                    "invalid_output_logits", head.name, "logits must be a numeric sequence"
                )
            try:
                logits = tuple(float(item) for item in raw)
            except (TypeError, ValueError):
                raise ContractError(
                    "invalid_output_logits", head.name, "logits must be numeric"
                )
            if len(logits) != len(head.labels):
                raise ContractError(
                    "output_shape_mismatch",
                    head.name,
                    f"expected {len(head.labels)} logits, got {len(logits)}",
                )
            if any(not math.isfinite(item) for item in logits):
                raise ContractError(
                    "nonfinite_output_logit", head.name, "every logit must be finite"
                )
            normalized[head.name] = logits
        return cls(values=normalized, contract_version=contract_version)

    def ordered_values(self) -> Tuple[Tuple[float, ...], ...]:
        return tuple(self.values[head.name] for head in OUTPUT_HEADS)


TargetValue = Union[int, Tuple[float, ...]]


@dataclass(frozen=True)
class FactorTargets:
    values: Mapping[str, TargetValue]
    active: Mapping[str, bool]


_FORM_TO_SWIFT_LABEL = {
    FORM_PLAIN: "plain",
    FORM_MINOR: "minor",
    FORM_EXPLICIT_MAJOR: "explicitMajor",
    FORM_MINOR_MAJOR: "minorMajor",
    FORM_AUGMENTED: "augmented",
    FORM_DIMINISHED: "diminished",
    FORM_HALF_DIMINISHED: "halfDiminished",
    FORM_SUSPENDED: "suspended",
    FORM_ADDED_TONE: "addedTone",
    FORM_ALTERED: "altered",
}
_ACCIDENTAL_TO_LABEL = {"": "natural", "#": "sharp", "b": "flat"}


def _index(head_name: str, label: str) -> int:
    try:
        return HEAD_BY_NAME[head_name].labels.index(label)
    except ValueError:
        raise ContractError("unknown_factor_label", head_name, label)


def factorize_canonical_label(label: str) -> FactorTargets:
    """Convert one strict canonical label into masked head supervision.

    Conditional heads receive a stable placeholder index while inactive. The
    loss must honor ``active``; placeholders are never supervision.
    """

    parsed = parse_canonical_chord_label(label)
    values: Dict[str, TargetValue] = {
        "validity": _index("validity", "notation"),
        "kind": _index("kind", "chord_repeat" if parsed.is_repeat else "rooted"),
        "root_letter": 0,
        "root_accidental": 0,
        "quality": 0,
        "extension": 0,
        "alteration_logits": tuple(0.0 for _ in HEAD_BY_NAME["alteration_logits"].labels),
        "slash_presence": 0,
        "slash_bass_letter": 0,
        "slash_bass_accidental": 0,
    }
    active = {name: False for name in HEAD_NAMES}
    active["validity"] = True
    active["kind"] = True

    if parsed.is_repeat:
        return FactorTargets(values=values, active=active)

    assert parsed.root is not None
    assert parsed.form is not None
    values["root_letter"] = _index("root_letter", parsed.root.letter)
    values["root_accidental"] = _index(
        "root_accidental", _ACCIDENTAL_TO_LABEL[parsed.root.accidental]
    )
    values["quality"] = _index("quality", _FORM_TO_SWIFT_LABEL[parsed.form])
    values["extension"] = _index("extension", parsed.extension or "none")
    selected_alterations = set(parsed.alterations)
    values["alteration_logits"] = tuple(
        1.0 if token in selected_alterations else 0.0
        for token in HEAD_BY_NAME["alteration_logits"].labels
    )
    slash_is_present = parsed.slash_bass is not None
    values["slash_presence"] = _index(
        "slash_presence", "present" if slash_is_present else "none"
    )

    for name in (
        "root_letter",
        "root_accidental",
        "quality",
        "extension",
        "alteration_logits",
        "slash_presence",
    ):
        active[name] = True

    if parsed.slash_bass is not None:
        values["slash_bass_letter"] = _index("slash_bass_letter", parsed.slash_bass.letter)
        values["slash_bass_accidental"] = _index(
            "slash_bass_accidental",
            _ACCIDENTAL_TO_LABEL[parsed.slash_bass.accidental],
        )
        active["slash_bass_letter"] = True
        active["slash_bass_accidental"] = True

    return FactorTargets(values=values, active=active)


def factorize_ground_truth(
    outcome: str,
    canonical_label: Optional[str],
) -> FactorTargets:
    """Create supervision for an adjudicated v2 corpus outcome."""

    if outcome == GROUND_TRUTH_CANONICAL:
        return factorize_canonical_label(canonical_label)
    if outcome != GROUND_TRUTH_NO_READ:
        raise ContractError(
            "unsupported_training_ground_truth",
            "ground_truth_outcome",
            "model roles accept only canonical notation or adjudicated no-read",
        )
    if canonical_label is not None:
        raise ContractError(
            "unexpected_canonical_label",
            "canonical_label",
            "no-read supervision must not carry chord text",
        )
    values: Dict[str, TargetValue] = {
        "validity": _index("validity", "no_read"),
        "kind": 0,
        "root_letter": 0,
        "root_accidental": 0,
        "quality": 0,
        "extension": 0,
        "alteration_logits": tuple(0.0 for _ in HEAD_BY_NAME["alteration_logits"].labels),
        "slash_presence": 0,
        "slash_bass_letter": 0,
        "slash_bass_accidental": 0,
    }
    active = {name: False for name in HEAD_NAMES}
    active["validity"] = True
    return FactorTargets(values=values, active=active)


def factorize_corpus_record(record: CorpusRecord) -> FactorTargets:
    """Factorize only supervision explicitly authorized by corpus v2."""

    if record.supervision_kind == CorpusSupervisionKind.NOTATION:
        label = record.supervised_canonical_label
        if label is None:
            raise ContractError(
                "missing_supervised_canonical_label", record.sample_id, "notation target is empty"
            )
        return factorize_canonical_label(label)
    if record.supervision_kind == CorpusSupervisionKind.NO_READ:
        return factorize_ground_truth(GROUND_TRUTH_NO_READ, None)
    raise ContractError(
        "excluded_ground_truth_in_model_batch",
        record.sample_id,
        "ambiguous, unresolved, execution-error, and technical-failure rows cannot supervise the model",
    )

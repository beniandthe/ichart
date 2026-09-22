"""Dependency-free mirror of Swift's strict ``ChordNotation`` language.

This module parses canonical labels only. It deliberately does not normalize
aliases, typography, OCR output, or handwriting guesses. Any grammar change
must be made in lockstep with ``iChart/Shared/ChordNotation`` and versioned.
"""

from dataclasses import dataclass
from typing import Dict, Optional, Tuple


REPEAT_LABEL = "•/•"
LETTERS = tuple("ABCDEFG")
ACCIDENTALS = ("", "#", "b")

FORM_PLAIN = "plain"
FORM_MINOR = "minor"
FORM_EXPLICIT_MAJOR = "explicit-major"
FORM_MINOR_MAJOR = "minor-major"
FORM_AUGMENTED = "augmented"
FORM_DIMINISHED = "diminished"
FORM_HALF_DIMINISHED = "half-diminished"
FORM_SUSPENDED = "suspended"
FORM_ADDED_TONE = "added-tone"
FORM_ALTERED = "altered"

EXTENSIONS_BY_FORM = {
    FORM_PLAIN: (None, "6", "7", "9", "11", "13", "6/9"),
    FORM_MINOR: (None, "6", "7", "9", "11", "13", "6/9"),
    FORM_EXPLICIT_MAJOR: (None, "6", "7", "9", "11", "13", "6/9"),
    FORM_MINOR_MAJOR: ("7", "9", "11", "13"),
    FORM_AUGMENTED: (None, "6", "7", "9", "11", "13", "6/9"),
    FORM_DIMINISHED: (None, "7"),
    FORM_HALF_DIMINISHED: ("7",),
    FORM_SUSPENDED: (None, "2", "4", "7", "9", "13"),
    FORM_ADDED_TONE: ("2", "4", "9", "11"),
    FORM_ALTERED: ("7",),
}

ALTERATION_ORDER = {
    "b3": (3, 0),
    "b5": (5, 0),
    "#5": (5, 1),
    "b9": (9, 0),
    "#9": (9, 1),
    "#11": (11, 1),
    "b13": (13, 0),
}
ALTERATION_FORMS = {
    FORM_PLAIN,
    FORM_MINOR,
    FORM_EXPLICIT_MAJOR,
    FORM_SUSPENDED,
}


class CanonicalChordLabelError(ValueError):
    pass


@dataclass(frozen=True)
class Pitch:
    letter: str
    accidental: str = ""

    @property
    def canonical_display(self) -> str:
        return self.letter + self.accidental


@dataclass(frozen=True)
class CanonicalChordLabel:
    is_repeat: bool
    root: Optional[Pitch] = None
    form: Optional[str] = None
    extension: Optional[str] = None
    alterations: Tuple[str, ...] = ()
    slash_bass: Optional[Pitch] = None

    @property
    def canonical_display(self) -> str:
        if self.is_repeat:
            return REPEAT_LABEL
        if self.root is None or self.form is None:
            raise CanonicalChordLabelError("incomplete chord label")
        descriptor = _descriptor(self.form, self.extension)
        alterations = "".join(f"({alteration})" for alteration in self.alterations)
        bass = "" if self.slash_bass is None else f"/{self.slash_bass.canonical_display}"
        return self.root.canonical_display + descriptor + alterations + bass


def _descriptor(form: str, extension: Optional[str]) -> str:
    suffix = "" if extension is None else extension
    if form == FORM_PLAIN:
        return suffix
    if form == FORM_MINOR:
        return "-" + suffix
    if form == FORM_EXPLICIT_MAJOR:
        return "△" + suffix
    if form == FORM_MINOR_MAJOR:
        return "-△" + suffix
    if form == FORM_AUGMENTED:
        return "+" + suffix
    if form == FORM_DIMINISHED:
        return "°" + suffix
    if form == FORM_HALF_DIMINISHED:
        return "ø" + suffix
    if form == FORM_SUSPENDED:
        return "7sus" if extension == "7" else "sus" + suffix
    if form == FORM_ADDED_TONE:
        return "add" + suffix
    if form == FORM_ALTERED:
        return "7alt"
    raise CanonicalChordLabelError("unsupported form")


def _descriptor_table() -> Dict[str, Tuple[str, Optional[str]]]:
    result: Dict[str, Tuple[str, Optional[str]]] = {}
    for form, extensions in EXTENSIONS_BY_FORM.items():
        for extension in extensions:
            descriptor = _descriptor(form, extension)
            if descriptor in result:
                raise RuntimeError(f"non-unique canonical descriptor: {descriptor}")
            result[descriptor] = (form, extension)
    return result


DESCRIPTORS = _descriptor_table()


def _parse_pitch(text: str) -> Optional[Pitch]:
    if len(text) not in (1, 2) or text[0] not in LETTERS:
        return None
    if len(text) == 1:
        return Pitch(text)
    if text[1] not in ("#", "b"):
        return None
    return Pitch(text[0], text[1])


def _split_slash_bass(text: str) -> Tuple[str, Optional[Pitch]]:
    slash_index = text.rfind("/")
    if slash_index < 0:
        return text, None

    possible_bass = _parse_pitch(text[slash_index + 1 :])
    if possible_bass is not None:
        return text[:slash_index], possible_bass

    is_six_nine_separator = (
        slash_index > 0
        and slash_index + 1 < len(text)
        and text[slash_index - 1] == "6"
        and text[slash_index + 1] == "9"
        and "/" not in text[:slash_index]
    )
    if is_six_nine_separator:
        return text, None
    raise CanonicalChordLabelError("invalid slash bass")


def _parse_alterations(text: str) -> Tuple[str, ...]:
    alterations = []
    remaining = text
    while remaining:
        if not remaining.startswith("("):
            raise CanonicalChordLabelError("malformed alteration")
        closing = remaining.find(")")
        if closing < 0:
            raise CanonicalChordLabelError("malformed alteration")
        token = remaining[1:closing]
        if token not in ALTERATION_ORDER:
            raise CanonicalChordLabelError("unsupported alteration")
        alterations.append(token)
        remaining = remaining[closing + 1 :]

    encountered_degrees = set()
    previous_order = None
    for alteration in alterations:
        order = ALTERATION_ORDER[alteration]
        degree = order[0]
        if degree in encountered_degrees:
            raise CanonicalChordLabelError("duplicate alteration degree")
        if previous_order is not None and previous_order >= order:
            raise CanonicalChordLabelError("alterations are not canonically sorted")
        encountered_degrees.add(degree)
        previous_order = order
    return tuple(alterations)


def parse_canonical_chord_label(text: str) -> CanonicalChordLabel:
    if not isinstance(text, str) or not text:
        raise CanonicalChordLabelError("label is empty")
    if text == REPEAT_LABEL:
        return CanonicalChordLabel(is_repeat=True)

    chord_text, slash_bass = _split_slash_bass(text)
    if not chord_text or chord_text[0] not in LETTERS:
        raise CanonicalChordLabelError("invalid root")
    descriptor_start = 1
    root_accidental = ""
    if len(chord_text) > 1 and chord_text[1] in ("#", "b"):
        root_accidental = chord_text[1]
        descriptor_start = 2
    root = Pitch(chord_text[0], root_accidental)

    suffix = chord_text[descriptor_start:]
    first_parenthesis = suffix.find("(")
    if first_parenthesis < 0:
        descriptor = suffix
        alteration_suffix = ""
    else:
        descriptor = suffix[:first_parenthesis]
        alteration_suffix = suffix[first_parenthesis:]
    if descriptor not in DESCRIPTORS:
        raise CanonicalChordLabelError("unsupported descriptor")
    form, extension = DESCRIPTORS[descriptor]
    alterations = _parse_alterations(alteration_suffix)
    if alterations and form not in ALTERATION_FORMS:
        raise CanonicalChordLabelError("alterations are not allowed for this form")

    parsed = CanonicalChordLabel(
        is_repeat=False,
        root=root,
        form=form,
        extension=extension,
        alterations=alterations,
        slash_bass=slash_bass,
    )
    if parsed.canonical_display != text:
        raise CanonicalChordLabelError(
            f"label is not canonical; expected {parsed.canonical_display}"
        )
    return parsed


def require_canonical_chord_label(text: str) -> str:
    parsed = parse_canonical_chord_label(text)
    return parsed.canonical_display

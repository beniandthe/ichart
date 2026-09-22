import unittest

from ichart_recognition_ml.chord_notation import (
    CanonicalChordLabelError,
    parse_canonical_chord_label,
    require_canonical_chord_label,
)


class CanonicalChordLabelTests(unittest.TestCase):
    def test_accepts_canonical_repeat_roots_forms_extensions_alterations_and_basses(self):
        accepted = [
            "•/•",
            "C",
            "Bb",
            "F#",
            "C6/9",
            "C6/9/Eb",
            "C-",
            "C-7",
            "C-6/9",
            "C△",
            "C△7",
            "C△13",
            "C-△9",
            "C+7",
            "C°",
            "C°7",
            "Cø7",
            "Csus",
            "Csus2",
            "Csus4",
            "C7sus",
            "Csus13",
            "Cadd11",
            "C7alt",
            "Bb7(b3)(#5)(b9)(#11)(b13)/D",
            "F#7sus(b9)/C#",
        ]
        for label in accepted:
            with self.subTest(label=label):
                parsed = parse_canonical_chord_label(label)
                self.assertEqual(parsed.canonical_display, label)
                self.assertEqual(require_canonical_chord_label(label), label)

    def test_rejects_same_aliases_whitespace_and_lookalikes_as_swift_parser(self):
        rejected = [
            "",
            " C",
            "C ",
            "c",
            "H",
            "C♯",
            "C♭",
            "C＃",
            "Cm",
            "Cmin",
            "Cmaj7",
            "CM7",
            "CΔ7",
            "C∆7",
            "Cdim7",
            "CØ7",
            "Chalf-dim7",
            "C7sus4",
            "Csus7",
            "Cadd6",
            "Calt",
            "C altered",
            "%",
            "./.",
            "• / •",
            "C7b9",
            "C7(b9)(#5)",
            "C7(b9)(b9)",
            "C7(#5)(b5)",
            "C/E5",
            "C/eb",
            "C6/8",
            "C6/9/",
            "C6/9/E5",
        ]
        for label in rejected:
            with self.subTest(label=label):
                with self.assertRaises(CanonicalChordLabelError):
                    parse_canonical_chord_label(label)

    def test_rejects_form_extension_pairs_forbidden_by_swift_language(self):
        rejected = [
            "C2",
            "C4",
            "C-2",
            "C△2",
            "C-△",
            "C-△6",
            "C+2",
            "C°9",
            "Cø",
            "Cø9",
            "Csus6",
            "Csus7",
            "Csus11",
            "Cadd7",
            "C9alt",
        ]
        for label in rejected:
            with self.subTest(label=label):
                with self.assertRaises(CanonicalChordLabelError):
                    parse_canonical_chord_label(label)

    def test_rejects_alterations_on_forbidden_forms(self):
        rejected = [
            "C-△7(b9)",
            "C+7(b9)",
            "C°7(b9)",
            "Cø7(b9)",
            "Cadd9(b5)",
            "C7alt(b9)",
        ]
        for label in rejected:
            with self.subTest(label=label):
                with self.assertRaises(CanonicalChordLabelError):
                    parse_canonical_chord_label(label)

    def test_requires_unique_alteration_degrees_and_canonical_order(self):
        rejected = [
            "C7(#5)(b5)",
            "C7(b9)(#9)",
            "C7(b9)(b3)",
            "C7(#11)(#9)",
            "C7(b13)(#11)",
        ]
        for label in rejected:
            with self.subTest(label=label):
                with self.assertRaises(CanonicalChordLabelError):
                    parse_canonical_chord_label(label)

    def test_root_and_slash_bass_require_uppercase_ascii_pitch_spelling(self):
        for label in ("Cb/B#", "F#/Gb", "Ab/C", "G/Bb"):
            with self.subTest(label=label):
                self.assertEqual(require_canonical_chord_label(label), label)
        for label in ("C/c", "C/eb", "C/E#b", "C/Bbb", "C/#F", "C/"):
            with self.subTest(label=label):
                with self.assertRaises(CanonicalChordLabelError):
                    parse_canonical_chord_label(label)


if __name__ == "__main__":
    unittest.main()

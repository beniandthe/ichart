import copy
import inspect
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.features import InkPoint, InkStroke
from ichart_recognition_ml.research import personal_hwrt_stroke_evaluate as evaluation
from ichart_recognition_ml.research import personal_stroke_direction_diagnostic as diagnostic
from ichart_recognition_ml.research import personal_stroke_field as stroke_field


VOCABULARY = [f"old{index:02}" for index in range(97)] + list(evaluation.NOVEL)
ALLOWED = VOCABULARY[:41] + list(evaluation.NOVEL)


def _blind_rows(fields):
    rows = []
    for index, value in enumerate(fields):
        raster = np.rint(value[0] * np.float32(255.0)).astype(np.uint8)
        rows.append({
            "opaqueID": evaluation.sha(f"blind/{index}".encode()),
            "rasterSHA256": evaluation.sha(raster.tobytes()),
            "normalizedGeometrySHA256": evaluation.sha(f"geometry/{index}".encode()),
            "fieldSHA256": diagnostic._field_sha256(value),
        })
    return rows


class TinyDirectionModel(torch.nn.Module):
    def __init__(self, *, direction_sensitive):
        super().__init__()
        self.direction_sensitive = direction_sensitive
        self.register_buffer("unchanged", torch.tensor([1.0], dtype=torch.float32))

    def forward(self, fields):
        embeddings = torch.zeros((len(fields), 128), dtype=torch.float32)
        embeddings[:, 0] = 1.0
        logits = torch.zeros((len(fields), 102), dtype=torch.float32)
        if self.direction_sensitive:
            signal = fields[:, 1].sum(dim=(1, 2))
            logits[:, 0] = signal
            logits[:, 1] = -signal
        else:
            logits[:, 0] = 1.0
        return embeddings, logits


def _result(raw_index, *, invalid=False):
    if invalid:
        return evaluation.failure(ValueError("synthetic invalid"))
    embedding = [1.0] + [0.0] * 127
    logits = [0.0] * 102
    logits[raw_index] = 1.0
    return evaluation.result(embedding, logits, VOCABULARY, ALLOWED)


class PersonalStrokeDirectionDiagnosticTests(unittest.TestCase):
    def test_transform_is_exact_involution_and_does_not_mutate_input(self):
        generator = np.random.default_rng(29)
        source = generator.normal(size=(3, 5, 96, 256)).astype(np.float32)
        source[:, 0] = generator.integers(0, 2, size=(3, 96, 256)).astype(np.float32)
        unchanged = source.copy()
        transformed = diagnostic.reverse_direction_fields(source)

        self.assertTrue(np.array_equal(source, unchanged))
        self.assertFalse(np.shares_memory(source, transformed))
        self.assertTrue(np.array_equal(transformed[:, 0], source[:, 0]))
        self.assertTrue(np.array_equal(transformed[:, 1:3], -source[:, 1:3]))
        self.assertTrue(np.array_equal(transformed[:, 3], source[:, 4]))
        self.assertTrue(np.array_equal(transformed[:, 4], source[:, 3]))
        restored = diagnostic.reverse_direction_fields(transformed)
        self.assertEqual(restored.tobytes(), source.tobytes())

    def test_transform_matches_synthetic_point_reversal_with_rounding_tolerance(self):
        strokes = (
            InkStroke((
                InkPoint(-12.0, -5.0), InkPoint(-7.0, 2.0),
                InkPoint(-1.0, 6.0), InkPoint(6.0, 3.0),
            )),
            InkStroke((InkPoint(-8.0, 5.0), InkPoint(8.0, -5.0))),
            InkStroke((InkPoint(-9.0, 0.0), InkPoint(9.0, 0.0), InkPoint(-9.0, 0.0))),
            InkStroke((InkPoint(2.0, -7.0), InkPoint(2.0, -7.0), InkPoint(5.0, -4.0))),
            InkStroke((InkPoint(3.0, -2.0), InkPoint(3.0, -2.0))),
            InkStroke((InkPoint(10.0, 7.0),)),
        )
        point_reversed = tuple(
            InkStroke(tuple(reversed(stroke.points))) for stroke in strokes
        )
        source = stroke_field.encode_stroke_field(strokes)
        expected = diagnostic.reverse_direction_fields(source)
        actual = stroke_field.encode_stroke_field(point_reversed)

        self.assertTrue(np.array_equal(actual[0], expected[0]))
        np.testing.assert_allclose(actual[1:3], expected[1:3], rtol=0, atol=2e-6)
        self.assertTrue(np.array_equal(actual[3], expected[3]))
        self.assertTrue(np.array_equal(actual[4], expected[4]))

    def test_original_replay_precedes_transform_and_control_is_exact(self):
        fields = np.zeros((3, 5, 96, 256), dtype=np.float32)
        fields[:, 1, 40:42, 100:103] = np.float32(0.75)
        rows = _blind_rows(fields)
        inputs = {"vocabulary": VOCABULARY, "rows": rows}
        models = {
            "rasterControl": TinyDirectionModel(direction_sensitive=False).eval(),
            "strokeField": TinyDirectionModel(direction_sensitive=True).eval(),
        }
        original = evaluation.freeze_forward(
            models, fields, inputs, ALLOWED, batch_size=diagnostic.BATCH_SIZE
        )
        with patch.object(diagnostic, "ROW_COUNT", len(fields)):
            hashes = diagnostic._verify_original_replay(copy.deepcopy(original), original)
            transformed = diagnostic.freeze_transformed(
                models, fields, inputs, ALLOWED, original, hashes,
                batch_size=diagnostic.BATCH_SIZE,
            )
        self.assertEqual(len(transformed), len(fields))
        for before, after in zip(original, transformed):
            self.assertEqual(
                before["results"]["rasterControl"],
                after["transformedResults"]["rasterControl"],
            )
            self.assertNotEqual(
                before["results"]["strokeField"]["rawTop1"],
                after["transformedResults"]["strokeField"]["rawTop1"],
            )
            self.assertEqual(set(after["transformedResults"]), set(evaluation.ARMS))
            self.assertEqual(set(after["originalResultSHA256"]), set(evaluation.ARMS))
        self.assertTrue(all(torch.equal(model.unchanged, torch.tensor([1.0]))
                            for model in models.values()))

    def test_replay_mismatch_or_direction_sensitive_control_fails_closed(self):
        fields = np.zeros((2, 5, 96, 256), dtype=np.float32)
        fields[:, 1, 0, 0] = 1.0
        inputs = {"vocabulary": VOCABULARY, "rows": _blind_rows(fields)}
        normal_models = {
            "rasterControl": TinyDirectionModel(direction_sensitive=False).eval(),
            "strokeField": TinyDirectionModel(direction_sensitive=True).eval(),
        }
        original = evaluation.freeze_forward(normal_models, fields, inputs, ALLOWED)
        broken = copy.deepcopy(original)
        broken[0]["results"]["strokeField"]["rawTop1"] = VOCABULARY[2]
        with patch.object(diagnostic, "ROW_COUNT", len(fields)):
            with self.assertRaisesRegex(ValueError, "replay differs"):
                diagnostic._verify_original_replay(original, broken)

            sensitive_control = {
                "rasterControl": TinyDirectionModel(direction_sensitive=True).eval(),
                "strokeField": TinyDirectionModel(direction_sensitive=True).eval(),
            }
            sensitive_original = evaluation.freeze_forward(
                sensitive_control, fields, inputs, ALLOWED
            )
            hashes = diagnostic._verify_original_replay(
                copy.deepcopy(sensitive_original), sensitive_original
            )
            with self.assertRaisesRegex(ValueError, "Image-only control changed"):
                diagnostic.freeze_transformed(
                    sensitive_control, fields, inputs, ALLOWED,
                    sensitive_original, hashes,
                )

    def test_summary_keeps_failures_corrections_regressions_and_no_read_to_wrong(self):
        rows = [
            {"label": VOCABULARY[0], "results": {"strokeField": _result(1)},
             "transformedResults": {"strokeField": _result(0)}},
            {"label": VOCABULARY[0], "results": {"strokeField": _result(0)},
             "transformedResults": {"strokeField": _result(1)}},
            {"label": VOCABULARY[0], "results": {"strokeField": _result(50)},
             "transformedResults": {"strokeField": _result(1)}},
            {"label": VOCABULARY[0], "results": {"strokeField": _result(0)},
             "transformedResults": {"strokeField": _result(0, invalid=True)}},
        ]
        summary = diagnostic._direction_summary(rows, "strokeField")
        self.assertEqual(summary["count"], 4)
        self.assertEqual(summary["originalInvalid"], 0)
        self.assertEqual(summary["transformedInvalid"], 1)
        self.assertEqual(summary["comparable"], 3)
        self.assertEqual(summary["rawCorrections"], 1)
        self.assertEqual(summary["rawRegressions"], 2)
        self.assertEqual(summary["noReadToWrong"], 1)

    def test_fixed_protocol_and_truth_separation_are_explicit(self):
        identity = diagnostic.code_identity()
        self.assertEqual(identity[diagnostic.PROTOCOL_PATH], diagnostic.PROTOCOL_SHA256)
        self.assertEqual(diagnostic._TRANSFORM, {
            "version": "global-field-direction-reversal-v1",
            "occupancy": "unchanged",
            "tangentX": "negated",
            "tangentY": "negated",
            "strokeStart": "source-strokeEnd",
            "strokeEnd": "source-strokeStart",
            "geometryRotation": False,
            "geometryReflection": False,
            "interStrokeOrderChanged": False,
            "timingUsed": False,
        })
        predictor = inspect.getsource(diagnostic.predict)
        self.assertNotIn('"truth.json"', predictor)
        self.assertNotIn("original_score", predictor)
        self.assertLess(
            predictor.index("evaluation.freeze_forward"),
            predictor.index("freeze_transformed"),
        )
        scorer = inspect.getsource(diagnostic.score)
        self.assertLess(scorer.index("validate_packet"), scorer.index('"truth.json"'))

    def test_invalid_transform_inputs_fail_closed(self):
        source = np.zeros((5, 96, 256), dtype=np.float32)
        with self.assertRaisesRegex(ValueError, "Float32"):
            diagnostic.reverse_direction_fields(source.astype(np.float64))
        with self.assertRaisesRegex(ValueError, "shape"):
            diagnostic.reverse_direction_fields(source[:4])
        broken = source.copy()
        broken[1, 0, 0] = np.nan
        with self.assertRaisesRegex(ValueError, "finite"):
            diagnostic.reverse_direction_fields(broken)


if __name__ == "__main__":
    unittest.main()

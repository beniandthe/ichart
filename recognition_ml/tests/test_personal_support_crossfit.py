import math
import unittest
from dataclasses import replace

import numpy as np
import torch

from ichart_recognition_ml.features import InkPoint, InkStroke, rasterize
from ichart_recognition_ml.research import personal_support_crossfit as crossfit
from ichart_recognition_ml.research.uji_personal import Sample


class SupportCrossfitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)
        torch.use_deterministic_algorithms(True)
        cls.labels = tuple(chr(0x100 + index) for index in range(97))
        cls.records = tuple(Sample(f"{prefix}_UPV_W{writer:02d}", session, label, ())
            for prefix, count in (("trn", 40), ("tst", 20)) for writer in range(count)
            for session in (1, 2) for label in cls.labels)

    def test_folds_are_fixed_complementary16_training_writers_and3104_rows(self):
        training, folds, development, reserved = crossfit.fold_writers(self.records)
        self.assertEqual(len(training), 6208)
        self.assertEqual((len(folds["A"]), len(folds["B"])), (16, 16))
        self.assertFalse(set(folds["A"]) & set(folds["B"]))
        ranked = sorted({sample.writer for sample in training},
            key=lambda writer: crossfit._sha256(("personal-support-retrieval-v1:fold:" + writer).encode()))
        self.assertEqual(folds["A"], tuple(ranked[:16]))
        self.assertEqual(folds["B"], tuple(ranked[16:]))
        for fold in folds.values():
            rows = [sample for sample in training if sample.writer in fold]
            self.assertEqual(len(rows), 3104)
            self.assertEqual({(sample.writer, sample.session, sample.label) for sample in rows},
                {(writer, session, label) for writer in fold for session in (1, 2) for label in self.labels})
            self.assertFalse(set(fold) & (set(development) | set(reserved)))
        self.assertEqual(crossfit.fold_writers(tuple(reversed(self.records)))[1], folds)
        for records in (self.records[:-1], self.records[:-1] + self.records[:1]):
            with self.assertRaises(ValueError):
                crossfit.fold_writers(records)

    def test_epoch_full_visit_count_and_original_shared_rng_stream(self):
        generators = [torch.Generator().manual_seed(29) for _ in range(2)]
        receipts = []
        for generator in generators:
            histories = []
            for _ in range(30):
                permutation, batches = crossfit.epoch_batch_plan(generator)
                self.assertEqual([len(batch) for batch in batches], [128] * 24 + [32])
                self.assertEqual(sorted(permutation.tolist()), list(range(3104)))
                for batch in batches:
                    # Original augment uses exactly (batch_rows,4) torch draws.
                    torch.rand((len(batch), 4), generator=generator)
                histories.append((crossfit._sha256(permutation.numpy().tobytes()),
                                  crossfit._sha256(generator.get_state().numpy().tobytes())))
            receipts.append(histories)
        self.assertEqual(receipts[0], receipts[1])
        self.assertNotEqual(receipts[0][0], receipts[0][1])
        self.assertEqual(30 * 25, crossfit.UPDATES_PER_ENCODER)

    def test_setup_shape_exact_known_geometry_and_no_invented_extent(self):
        result = crossfit.setup_shape((InkStroke((InkPoint(0., 0.), InkPoint(100., 50.))),))
        self.assertEqual(result[0].points, (InkPoint(2.5, 5.), InkPoint(44.5, 26.)))
        horizontal = crossfit.setup_shape((InkStroke((InkPoint(0., 0.), InkPoint(10., 0.))),))
        self.assertEqual(horizontal[0].points, (InkPoint(2.5, 15.5), InkPoint(44.5, 15.5)))
        vertical = crossfit.setup_shape((InkStroke((InkPoint(0., 0.), InkPoint(0., 10.))),))
        self.assertEqual(vertical[0].points, (InkPoint(23.5, 2.5), InkPoint(23.5, 28.5)))
        bad = ((), (InkStroke((InkPoint(0., 0.),)),),
            (InkStroke((InkPoint(0., 0.), InkPoint(.49, 0.))),),
            (InkStroke((InkPoint(1e8, 0.), InkPoint(1e8, 2.))),),
            (InkStroke((InkPoint(float("nan"), 0.), InkPoint(1., 1.))),))
        for strokes in bad:
            self.assertIsNone(crossfit.setup_shape(strokes))

    def test_setup_decimation_matches_swift_endpoint_rule_and_strips_timing(self):
        for count, expected in ((128, 128), (129, 65), (256, 129), (257, 87)):
            stroke = InkStroke(tuple(InkPoint(float(index), float(index % 2), float(index)) for index in range(count)), creation_time_offset=10.)
            result = crossfit.setup_shape((stroke,))
            self.assertEqual(len(result[0].points), expected)
            self.assertTrue(all(point.time_offset is None for point in result[0].points))
            self.assertIsNone(result[0].creation_time_offset)
            self.assertAlmostEqual(result[0].points[-1].x, 44.5)
        repeated = InkStroke((InkPoint(0., 0.), InkPoint(1., 1.), InkPoint(1., 1.)))
        self.assertEqual(len(crossfit.setup_shape((InkStroke(()), repeated))[0].points), 3)

    def test_setup_rasters_translation_scale_invariant_and_stroke_order_preserved(self):
        strokes = (InkStroke((InkPoint(0., 0.), InkPoint(8., 20.))),
                   InkStroke((InkPoint(0., 20.), InkPoint(8., 0.))))
        moved = tuple(InkStroke(tuple(InkPoint(point.x * 2 + 100, point.y * 2 - 30) for point in stroke.points)) for stroke in strokes)
        original, shifted = crossfit.setup_shape(strokes), crossfit.setup_shape(moved)
        self.assertEqual(crossfit.stroke_bits(original), crossfit.stroke_bits(shifted))
        self.assertEqual(rasterize(original).pixels, rasterize(shifted).pixels)
        reversed_shape = crossfit.setup_shape(tuple(reversed(strokes)))
        self.assertEqual(original[0].points, reversed_shape[1].points)
        self.assertEqual(original[1].points, reversed_shape[0].points)

    def test_support_adapter_matches248_retained_swift_geometry_and_pixel_goldens(self):
        result = crossfit.verify_support_adapter()
        self.assertEqual(result["supportChecks"], 248)
        self.assertEqual(result["checksSHA256"], "808b9f75a74af8b48d384c2ba0274ebf2d47d0a90bbb9784ddccba6e6d4070f8")
        self.assertTrue(result["pixelsExactlyMatched"])
        self.assertFalse(result["modelInferencePerformed"])
        self.assertFalse(result["queryTruthRead"])

    def test_source_only_generic_fit_copy_reasons_do_not_require_answers(self):
        cases = (("r", "t", {"r"}, {"t"}, ["generic-fit-raw-raster-copy", "generic-fit-normalized-trajectory-copy"]),
                 ("r", "t", {"r"}, {"other"}, ["generic-fit-raw-raster-copy"]),
                 ("r", "t", {"other"}, {"t"}, ["generic-fit-normalized-trajectory-copy"]),
                 ("r", "t", set(), set(), []))
        for raw, trajectory, rasters, trajectories, expected in cases:
            self.assertEqual(crossfit.source_copy_reasons(raw, trajectory, rasters, trajectories), expected)

    def test_real_synthetic_gradient_update_is_finite_and_matched(self):
        before_rng = torch.get_rng_state().clone()
        models, initial = crossfit.initialized_models()
        self.assertTrue(torch.equal(before_rng, torch.get_rng_state()))
        rasters = torch.zeros((2, 1, 96, 256), dtype=torch.uint8)
        rasters[0, :, 30:60, 100:106] = 255
        rasters[1, :, 20:25, 60:180] = 255
        targets = torch.tensor([0, 96])
        states = []
        for model in models.values():
            self.assertEqual(crossfit._state_digest(model.state_dict()), initial)
            model.train()
            optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
            generator = torch.Generator().manual_seed(29)
            loss = crossfit._train_update(model, rasters, targets, optimizer, generator)
            self.assertTrue(math.isfinite(loss))
            state = crossfit._state_digest(model.state_dict())
            self.assertNotEqual(state, initial)
            states.append(state)
            features, logits = crossfit.infer(model, rasters)
            self.assertEqual(features.shape, (2, 128))
            self.assertEqual(logits.shape, (2, 97))
            self.assertTrue(np.isfinite(features).all())
        self.assertEqual(states[0], states[1])

    def test_training_rejects_wrong_counts_shapes_and_targets_before_update(self):
        models, _ = crossfit.initialized_models()
        model = models[crossfit.ARMS[0]]
        rasters = torch.zeros((2, 1, 96, 256), dtype=torch.uint8)
        targets = torch.tensor([0, 1])
        optimizer = torch.optim.AdamW(model.parameters(), lr=.001)
        generator = torch.Generator().manual_seed(29)
        for wrong in (rasters.float(), rasters[:, :, :-1], rasters[:0]):
            with self.assertRaises(ValueError):
                crossfit._train_update(model, wrong, targets, optimizer, generator)
        for wrong in (targets.float(), torch.tensor([-1, 1]), torch.tensor([0, 97]), targets[:1]):
            with self.assertRaises(ValueError):
                crossfit._train_update(model, rasters, wrong, optimizer, generator)
        with self.assertRaises(ValueError):
            crossfit.train_encoder(model, "fitA", rasters, targets)


if __name__ == "__main__":
    unittest.main()

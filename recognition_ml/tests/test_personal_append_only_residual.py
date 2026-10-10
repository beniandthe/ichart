import importlib.util
import unittest


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalAppendOnlyResidualTests(unittest.TestCase):
    @staticmethod
    def _unit_rows(values):
        import numpy as np

        rows = np.asarray(values, dtype=np.float64)
        return rows / np.linalg.norm(rows, axis=1, keepdims=True)

    def test_reference_is_exact_existing_fit_and_no_append_returns_same_snapshot(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_append_only_residual import (
            append_only_refit,
            fit_reference,
        )
        from ichart_recognition_ml.research.personal_residual import ResidualHead

        features = self._unit_rows([[1, 2, 0], [0, 1, 3], [2, 0, 1]])
        base = np.array([[.7, .2, .1], [.1, .8, .1], [.2, .3, .5]])
        labels = ("A", "B", "C")
        ids = ("source-a", "source-b", "source-c")
        reference = fit_reference(features, base, labels, ids, labels, "encoder-97-v1")
        original = ResidualHead.fit(features, base, labels, labels, regularization=.1)

        np.testing.assert_array_equal(reference.weights, original.weights)
        self.assertFalse(reference.weights.flags.writeable)
        self.assertFalse(reference.support_features.flags.writeable)
        self.assertFalse(reference.support_base_scores.flags.writeable)
        unchanged = append_only_refit(
            reference,
            features=features,
            base_scores=base,
            labels=labels,
            source_ids=ids,
            vocabulary=labels,
            encoder_identity="encoder-97-v1",
        )
        self.assertIs(unchanged, reference)
        query = self._unit_rows([[1, 1, 2]])[0]
        expected_ranks = original.rank(query, [.2, .5, .3])
        actual_ranks = reference.rank(query, [.2, .5, .3])
        self.assertEqual(
            [row["label"] for row in actual_ranks],
            [row["label"] for row in expected_ranks],
        )
        np.testing.assert_allclose(
            reference.adjusted_scores(query, [.2, .5, .3]),
            np.asarray([
                next(row["score"] for row in expected_ranks if row["label"] == label)
                for label in labels
            ]),
            rtol=0,
            atol=1e-15,
        )
        tied = fit_reference(
            np.empty((0, 3)), np.empty((0, 2)), (), (),
            ("B", "A"), "encoder-tie",
        )
        self.assertEqual(
            [row["label"] for row in tied.rank([1., 0., 0.], [.5, .5])],
            ["A", "B"],
        )

    def test_only_appended_labels_change_and_match_the_unchanged_full_refit(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_append_only_residual import (
            append_only_refit,
            fit_reference,
        )
        from ichart_recognition_ml.research.personal_residual import ResidualHead

        rng = np.random.default_rng(29)
        features = self._unit_rows(rng.normal(size=(4, 8)))
        base = rng.random((4, 3)); base /= base.sum(axis=1, keepdims=True)
        reference = fit_reference(
            features[:3], base[:3], ("A", "B", "C"), ("a", "b", "c"),
            ("A", "B", "C"), "encoder",
        )
        updated = append_only_refit(
            reference,
            features=features,
            base_scores=base,
            labels=("A", "B", "C", "A"),
            source_ids=("a", "b", "c", "d"),
            vocabulary=("A", "B", "C"),
            encoder_identity="encoder",
        )
        full = ResidualHead.fit(features, base, ("A", "B", "C", "A"), ("A", "B", "C"))
        np.testing.assert_array_equal(updated.weights[:, 0], full.weights[:, 0])
        np.testing.assert_array_equal(updated.weights[:, 1:], reference.weights[:, 1:])
        self.assertEqual(updated.last_refitted_labels, ("A",))

        query_features = self._unit_rows(rng.normal(size=(64, 8)))
        query_base = rng.random((64, 3)); query_base /= query_base.sum(axis=1, keepdims=True)
        for feature, scores in zip(query_features, query_base, strict=True):
            before = reference.adjusted_scores(feature, scores)
            after = updated.adjusted_scores(feature, scores)
            np.testing.assert_array_equal(before[1:].view(np.uint64), after[1:].view(np.uint64))
        self.assertEqual(
            updated.rank(query_features[0], query_base[0]),
            sorted(updated.rank(query_features[0], query_base[0]), key=lambda row: (-row["score"], row["label"])),
        )

    def test_sequential_three_appends_freeze_every_untaught_column(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_append_only_residual import (
            append_only_refit,
            fit_reference,
        )
        from ichart_recognition_ml.research.personal_residual import ResidualHead

        features = self._unit_rows([[1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 1, 1], [1, 0, 1]])
        base = np.array([[.8, .2, 0], [.2, .8, 0], [.6, .4, 0], [.1, .9, 0], [.7, .3, 0]])
        snapshots = [fit_reference(features[:2, :], base[:2, :2], ("A", "B"), ("0", "1"), ("A", "B"), "encoder")]
        histories = [
            (("A", "B", "A"), ("A", "B")),
            (("A", "B", "A", "C"), ("A", "B", "C")),
            (("A", "B", "A", "C", "B"), ("A", "B", "C")),
        ]
        for count, (labels, vocabulary) in enumerate(histories, start=3):
            previous = snapshots[-1]
            snapshot = append_only_refit(
                previous,
                features=features[:count],
                base_scores=base[:count, :len(vocabulary)],
                labels=labels,
                source_ids=tuple(str(i) for i in range(count)),
                vocabulary=vocabulary,
                encoder_identity="encoder",
            )
            full = ResidualHead.fit(features[:count], base[:count, :len(vocabulary)], labels, vocabulary)
            changed = labels[-1]
            changed_column = vocabulary.index(changed)
            np.testing.assert_array_equal(snapshot.weights[:, changed_column], full.weights[:, changed_column])
            for label in previous.vocabulary:
                column = vocabulary.index(label)
                if label != changed:
                    np.testing.assert_array_equal(snapshot.weights[:, column], previous.weights[:, column])
            snapshots.append(snapshot)
        self.assertEqual(snapshots[-1].source_ids, ("0", "1", "2", "3", "4"))

    def test_novel_vocabulary_is_sorted_zero_padded_and_explicitly_taught(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_append_only_residual import (
            append_only_refit,
            fit_reference,
        )
        from ichart_recognition_ml.research.personal_residual import ResidualHead

        reference = fit_reference(np.eye(2), np.eye(2), ("A", "B"), ("a", "b"), ("A", "B"), "encoder")
        features = self._unit_rows([[1, 0], [0, 1], [1, 1]])
        scores = np.array([[1., 0., 0.], [0., 1., 0.], [.4, .6, 0.]])
        updated = append_only_refit(
            reference,
            features=features,
            base_scores=scores,
            labels=("A", "B", "C"),
            source_ids=("a", "b", "c"),
            vocabulary=("A", "B", "C"),
            encoder_identity="encoder",
        )
        full = ResidualHead.fit(features, scores, ("A", "B", "C"), ("A", "B", "C"))
        np.testing.assert_array_equal(updated.weights[:, :2], reference.weights)
        np.testing.assert_array_equal(updated.weights[:, 2], full.weights[:, 2])
        old_query_scores = reference.adjusted_scores(features[2], [.4, .6])
        extended_query_scores = updated.adjusted_scores(features[2], [.4, .6, 0.])
        np.testing.assert_array_equal(
            old_query_scores.view(np.uint64),
            extended_query_scores[:2].view(np.uint64),
        )

        nonzero_padding = scores.copy(); nonzero_padding[0] = [.9, 0, .1]
        with self.assertRaisesRegex(ValueError, "zero vocabulary padding"):
            append_only_refit(
                reference, features=features, base_scores=nonzero_padding,
                labels=("A", "B", "C"), source_ids=("a", "b", "c"),
                vocabulary=("A", "B", "C"), encoder_identity="encoder",
            )
        nonzero_new_lesson_padding = scores.copy(); nonzero_new_lesson_padding[2] = [.4, .5, .1]
        with self.assertRaisesRegex(ValueError, "zero vocabulary padding"):
            append_only_refit(
                reference, features=features, base_scores=nonzero_new_lesson_padding,
                labels=("A", "B", "C"), source_ids=("a", "b", "c"),
                vocabulary=("A", "B", "C"), encoder_identity="encoder",
            )
        with self.assertRaisesRegex(ValueError, "zero non-encoder padding"):
            updated.rank(features[2], [.4, .5, .1])

        initial_novel_tail = fit_reference(
            features,
            scores,
            ("A", "B", "C"),
            ("a", "b", "c"),
            ("A", "B", "C"),
            "encoder-with-existing-novel-tail",
            encoder_vocabulary=("A", "B"),
        )
        self.assertEqual(initial_novel_tail.encoder_vocabulary, ("A", "B"))
        self.assertEqual(len(initial_novel_tail.rank(features[2], [.4, .6, 0.])), 3)
        with self.assertRaisesRegex(ValueError, "zero non-encoder padding"):
            initial_novel_tail.adjusted_scores(features[2], [.4, .5, .1])
        with self.assertRaisesRegex(ValueError, "zero non-encoder padding"):
            fit_reference(
                features, nonzero_new_lesson_padding, ("A", "B", "C"),
                ("a", "b", "c"), ("A", "B", "C"), "encoder",
                encoder_vocabulary=("A", "B"),
            )
        with self.assertRaisesRegex(ValueError, "sorted suffix"):
            append_only_refit(
                reference, features=np.vstack([features, features[-1]]),
                base_scores=np.array([[1., 0., 0., 0.], [0., 1., 0., 0.], [.4, .6, 0., 0.], [.3, .7, 0., 0.]]),
                labels=("A", "B", "D", "C"), source_ids=("a", "b", "d", "c"),
                vocabulary=("A", "B", "D", "C"), encoder_identity="encoder",
            )

    def test_old_support_edit_delete_reorder_or_encoder_change_refuses(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_append_only_residual import (
            append_only_refit,
            fit_reference,
        )

        features = np.eye(2)
        scores = np.eye(2)
        reference = fit_reference(features, scores, ("A", "B"), ("a", "b"), ("A", "B"), "encoder")
        valid = dict(
            features=np.vstack([features, [[2 ** -.5, 2 ** -.5]]]),
            base_scores=np.vstack([scores, [[.5, .5]]]),
            labels=("A", "B", "A"), source_ids=("a", "b", "c"),
            vocabulary=("A", "B"), encoder_identity="encoder",
        )
        invalid = []
        edited_features = valid["features"].copy(); edited_features[0] = [0, 1]
        invalid.append({"features": edited_features})
        edited_scores = valid["base_scores"].copy(); edited_scores[0] = [.9, .1]
        invalid.append({"base_scores": edited_scores})
        invalid.extend([
            {"labels": ("B", "A", "A")},
            {"source_ids": ("b", "a", "c")},
            {"source_ids": ("a", "b", "a")},
            {"encoder_identity": "other-encoder"},
            {"features": np.vstack([features, [[0., 0.]]])},
            {"features": features[:1], "base_scores": scores[:1], "labels": ("A",), "source_ids": ("a",)},
        ])
        for mutation in invalid:
            with self.subTest(mutation=tuple(mutation)):
                with self.assertRaises(ValueError):
                    append_only_refit(reference, **{**valid, **mutation})

    def test_updated_column_can_harm_an_old_correct_query(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_append_only_residual import (
            append_only_refit,
            fit_reference,
        )

        reference = fit_reference([[1., 0.]], [[1., 0.]], ("A",), ("old-a",), ("A", "B"), "encoder")
        updated = append_only_refit(
            reference,
            features=[[1., 0.], [1., 0.]],
            base_scores=[[1., 0.], [1., 0.]],
            labels=("A", "B"),
            source_ids=("old-a", "new-b"),
            vocabulary=("A", "B"),
            encoder_identity="encoder",
        )
        query_base = np.array([.55, .45])
        self.assertEqual(reference.rank([1., 0.], query_base)[0]["label"], "A")
        self.assertEqual(updated.rank([1., 0.], query_base)[0]["label"], "B")
        np.testing.assert_array_equal(updated.weights[:, 0], reference.weights[:, 0])
        np.testing.assert_array_equal(
            reference.adjusted_scores([1., 0.], query_base)[:1].view(np.uint64),
            updated.adjusted_scores([1., 0.], query_base)[:1].view(np.uint64),
        )


if __name__ == "__main__":
    unittest.main()

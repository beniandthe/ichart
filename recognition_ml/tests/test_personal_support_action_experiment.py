import unittest
from unittest import mock


class PersonalSupportActionExperimentTests(unittest.TestCase):
    @staticmethod
    def _row(index, role, catalog, *, fallback=False):
        baseline = "C" if fallback else "A"
        proposal = None if fallback else "B"
        return {
            "episodeID": f"{role}:{catalog}:{index}",
            "queryPosition": 0,
            "sourceIndex": index,
            "writer": f"writer-{role}-{catalog}",
            "catalog": catalog,
            "session": 1,
            "role": role,
            "baseline": baseline,
            "proposal": proposal,
            "wrongProposal": None if fallback else "A",
            "features": None if fallback else [1.0] * 10,
            "wrongFeatures": None if fallback else [0.0] * 10,
            "taughtLabels": ["B"],
            "copyReasons": [],
        }

    @staticmethod
    def _output(row):
        if row["features"] is None:
            logits = wrong = None
            selected = wrong_selected = row["baseline"]
        else:
            logits, wrong = [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]
            selected, wrong_selected = row["proposal"], row["baseline"]
        return {
            "episodeID": row["episodeID"],
            "queryPosition": row["queryPosition"],
            "sourceIndex": row["sourceIndex"],
            "logits": logits,
            "wrongLogits": wrong,
            "selected": selected,
            "wrongSelected": wrong_selected,
        }

    def _score_fixture(self):
        rows = []
        index = 0
        for role in ("metaFit", "reusedCheck"):
            for catalog in ("core10", "catalog21"):
                rows.append(self._row(index, role, catalog)); index += 1
                rows.append(self._row(index, role, catalog, fallback=True)); index += 1
        outputs = [self._output(row) for row in rows]
        labels = [{
            "direction": "A16-to-B16",
            "episodeID": row["episodeID"],
            "queryPosition": row["queryPosition"],
            "sourceIndex": row["sourceIndex"],
            "writer": row["writer"],
            "catalog": row["catalog"],
            "control": row["baseline"],
            "copyReasons": row["copyReasons"],
            "intended": "C" if row["features"] is None else "B",
            "inDomain": True,
        } for row in rows]
        return rows, outputs, labels

    def test_score_recomputes_routes_preserves_fallback_and_passes_complete_screen(self):
        from ichart_recognition_ml.research import personal_support_action_experiment as experiment

        rows, outputs, labels = self._score_fixture()
        forward = {"allowedLabels": ["A", "B", "C"], "rows": rows}
        prediction = {"version": experiment.VERSION, "featuresSHA256": "features",
            "fitSHA256": "fit", "codeSHA256": {"code": "hash"},
            "checkTruthRead": False, "rows": outputs}
        fitted = {"featuresSHA256": "features", "state": {"synthetic": True}}
        scored = {"rows": labels}

        def fake_read(path, expected=None):
            name = str(path)
            if name.endswith("predictions.json"):
                return prediction
            if name.endswith("fit.json"):
                return fitted
            if name.endswith("score.json"):
                return scored
            raise AssertionError(name)

        def fake_logits(batch, state):
            self.assertEqual(state, fitted["state"])
            return [[1.0, 0.0, 0.0] if row[0] == 1.0 else [0.0, 1.0, 0.0] for row in batch]

        def fake_select(baseline, proposal, logits, allowed):
            self.assertEqual(allowed, forward["allowedLabels"])
            return proposal if proposal is not None and logits == [1.0, 0.0, 0.0] else baseline

        published = {}
        with mock.patch.object(experiment, "features", return_value=(forward, "features")), \
                mock.patch.object(experiment, "identity", return_value={"code": "hash"}), \
                mock.patch.object(experiment, "read", side_effect=fake_read), \
                mock.patch.object(experiment, "publish", side_effect=lambda _, name, value: published.setdefault(name, value) or name), \
                mock.patch.object(experiment.selector, "action_logits", side_effect=fake_logits), \
                mock.patch.object(experiment.selector, "select_output", side_effect=fake_select):
            result = experiment.score("bundle", "output", "prediction-sha")

        self.assertTrue(result["passes"])
        self.assertTrue(all(summary[cohort]["passes"]
            for summary in result["results"]["reusedCheck"].values()
            for cohort in ("raw", "noCopy")))
        frozen = published["score.json"]["rows"]
        self.assertTrue(all(row["selected"] == row["baseline"]
            for row in frozen if row["features"] is None))

    def test_score_rejects_duplicate_prediction_keys(self):
        from ichart_recognition_ml.research import personal_support_action_experiment as experiment

        rows, outputs, _ = self._score_fixture()
        outputs[-1] = dict(outputs[0])
        prediction = {"version": experiment.VERSION, "featuresSHA256": "features",
            "fitSHA256": "fit", "codeSHA256": {"code": "hash"},
            "checkTruthRead": False, "rows": outputs}

        def fake_read(path, expected=None):
            return prediction if str(path).endswith("predictions.json") else {"featuresSHA256": "features", "state": {}}

        with mock.patch.object(experiment, "features", return_value=({"allowedLabels": ["A", "B", "C"], "rows": rows}, "features")), \
                mock.patch.object(experiment, "identity", return_value={"code": "hash"}), \
                mock.patch.object(experiment, "read", side_effect=fake_read):
            with self.assertRaisesRegex(ValueError, "Prediction coverage changed"):
                experiment.score("bundle", "output", "prediction-sha")

    def test_fit_rejects_duplicate_or_missing_target_coverage_before_training(self):
        from ichart_recognition_ml.research import personal_support_action_experiment as experiment

        row = self._row(1, "metaFit", "core10")
        forward = {"allowedLabels": ["A", "B"], "rows": [dict(row) for _ in range(3104)]}
        target = {"version": experiment.VERSION, "featuresSHA256": "features",
            "parentScoreSHA256": experiment.SCORE_SHA, "role": "metaFitOnly",
            "rows": [{"episodeID": row["episodeID"], "queryPosition": 0,
                "sourceIndex": 1, "action": 0} for _ in range(3104)]}
        with mock.patch.object(experiment, "features", return_value=(forward, "features")), \
                mock.patch.object(experiment, "read", return_value=target):
            with self.assertRaisesRegex(ValueError, "Training target coverage changed"):
                experiment.fit("output")

    def test_summary_exposes_harm_untaught_and_out_of_domain_failures(self):
        from ichart_recognition_ml.research import personal_support_action_experiment as experiment

        passing = [
            {"writer": "w1", "sourceIndex": 1, "inDomain": True, "truth": "B",
             "baseline": "A", "selected": "B", "wrongSelected": "A", "taught": True, "invalid": False},
            {"writer": "w2", "sourceIndex": 2, "inDomain": True, "truth": "C",
             "baseline": "C", "selected": "C", "wrongSelected": "A", "taught": False, "invalid": False},
            {"writer": "w2", "sourceIndex": 3, "inDomain": False, "truth": "X",
             "baseline": None, "selected": None, "wrongSelected": None, "taught": False, "invalid": False},
        ]
        self.assertTrue(experiment.summarize(passing)["passes"])
        harmed = [dict(row) for row in passing]
        harmed[1]["selected"] = "A"
        summary = experiment.summarize(harmed)
        self.assertFalse(summary["passes"])
        self.assertEqual((summary["harms"], summary["untaughtHarms"]), (1, 1))
        self.assertFalse(summary["gates"]["everyWriterNonnegative"])
        harmed[1]["selected"] = "C"
        harmed[2]["selected"] = "B"
        self.assertFalse(experiment.summarize(harmed)["gates"]["noNewOutOfDomainRead"])


if __name__ == "__main__":
    unittest.main()

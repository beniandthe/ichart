import contextlib
import copy
import importlib.util
import io
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest import mock


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalSupportMetricExperimentTests(unittest.TestCase):
    @staticmethod
    def _source_fixture(experiment):
        catalog = set().union(*(set(labels) for labels in experiment.TASKS.values()))
        vocabulary = sorted(catalog | {f"z{index:03d}" for index in range(97 - len(catalog))})
        encoder = [f"encoder-{index:02d}" for index in range(16)]
        meta = [f"meta-{index:02d}" for index in range(8)]
        check = [f"check-{index:02d}" for index in range(8)]
        writers = encoder + meta + check
        rows = []
        for writer in writers:
            for session in (1, 2):
                for label in vocabulary:
                    identity = f"{writer}:{session}:{label}"
                    rows.append({
                        "writer": writer,
                        "session": session,
                        "label": label,
                        "sourceID": identity,
                        "generator": "fitA",
                        "rawRasterSHA256": experiment.sha(("raw:" + identity).encode()),
                        "storedRasterSHA256": experiment.sha(("stored:" + identity).encode()),
                        "trajectorySHA256": experiment.sha(("trajectory:" + identity).encode()),
                        "storedTrajectorySHA256": experiment.sha(
                            ("stored-trajectory:" + identity).encode()
                        ),
                        "storedFailure": None,
                    })
        meta_indices = [i for i, row in enumerate(rows) if row["writer"] in meta]
        check_indices = [i for i, row in enumerate(rows) if row["writer"] in check]
        roles = {
            "generator": "fitA",
            "freshValidation": False,
            "encoderFitWriters": encoder,
            "metaFitWriters": meta,
            "internalValidationWriters": check,
            "sourceIndices": {"metaFit": meta_indices, "internalValidation": check_indices},
        }
        allowed = sorted(catalog | set(vocabulary[: 41 - len(catalog)]))
        self_count = len(set(allowed))
        if self_count < 41:
            allowed.extend(label for label in vocabulary if label not in allowed)
            allowed = sorted(set(allowed[:41]))
        return rows, vocabulary, roles, allowed

    @staticmethod
    def _episode(plan, role, writer, session, catalog):
        return next(
            item for item in plan["episodes"][role]
            if (item["writer"], item["supportSession"], item["catalog"])
            == (writer, session, catalog)
        )

    def test_source_plan_roles_catalogs_copy_rules_and_fail_closed_inputs(self):
        import torch
        from ichart_recognition_ml.research import personal_support_metric_experiment as experiment

        rows, vocabulary, roles, allowed = self._source_fixture(experiment)
        base, _, _, _ = experiment.source_plan(rows, vocabulary, roles)
        meta_episode = base["episodes"]["metaFit"][0]
        check_episode = base["episodes"]["internalCheck"][0]

        # A query's own unused stored rendering is not an exclusion.  Actual
        # raw-query equality to encoder and meta-fit references is.
        unused = meta_episode["queryIndices"][-1]
        encoder_index = next(i for i, row in enumerate(rows)
                             if row["writer"] in roles["encoderFitWriters"])
        rows[unused]["storedRasterSHA256"] = rows[encoder_index]["rawRasterSHA256"]
        rows[meta_episode["queryIndices"][0]]["rawRasterSHA256"] = rows[encoder_index][
            "storedRasterSHA256"
        ]
        meta_index = roles["sourceIndices"]["metaFit"][0]
        rows[check_episode["queryIndices"][0]]["trajectorySHA256"] = rows[meta_index][
            "storedTrajectorySHA256"
        ]

        # Record a same-label copy between the true and fixed wrong support.
        true_index, wrong_index = meta_episode["support"][0], meta_episode["wrongSupport"][0]
        self.assertEqual(rows[true_index]["label"], rows[wrong_index]["label"])
        rows[wrong_index]["rawRasterSHA256"] = rows[true_index]["rawRasterSHA256"]
        forward, targets, truth, ledger = experiment.source_plan(rows, vocabulary, roles)
        forward["allowedLabels"] = allowed
        experiment.validate_forward(forward)

        self.assertEqual(len(rows), 6208)
        self.assertEqual({role: len(forward["writers"][role]) for role in experiment.ROLES},
                         {"metaFit": 8, "internalCheck": 8})
        self.assertEqual(len(set(forward["encoderFitWriters"])), 16)
        self.assertEqual({role: len(forward["sourceIndices"][role]) for role in experiment.ROLES},
                         {"metaFit": 1552, "internalCheck": 1552})
        self.assertEqual({role: len(forward["episodes"][role]) for role in experiment.ROLES},
                         {"metaFit": 32, "internalCheck": 32})
        self.assertEqual(len(targets["rows"]), 32)
        self.assertEqual(len(truth["rows"]), 3104)
        self.assertEqual(len(ledger["queryRows"]), 6208)
        self.assertEqual(len(forward["updateEpisodeIndices"]), 960)
        generator = torch.Generator().manual_seed(43)
        self.assertEqual(
            forward["updateEpisodeIndices"],
            [index for _ in range(30)
             for index in torch.randperm(32, generator=generator).tolist()],
        )
        for role in experiment.ROLES:
            for writer in forward["writers"][role]:
                for session in (1, 2):
                    for catalog in experiment.TASKS:
                        episode = self._episode(forward, role, writer, session, catalog)
                        self.assertEqual(len(episode["queryIndices"]), 97)

        by_query = {(row["episodeID"], row["queryIndex"]): row["reasons"]
                    for row in ledger["queryRows"]}
        self.assertIn(
            "encoder-fit-raw-raster-copy",
            by_query[meta_episode["episodeID"], meta_episode["queryIndices"][0]],
        )
        self.assertEqual(by_query[meta_episode["episodeID"], unused], [])
        self.assertIn(
            "meta-fit-normalized-trajectory-copy",
            by_query[check_episode["episodeID"], check_episode["queryIndices"][0]],
        )
        support_record = next(
            row for row in ledger["supportRows"] if row["episodeID"] == meta_episode["episodeID"]
        )
        self.assertTrue(any(
            item["arm"] == "sameSupport-vs-wrongSupport"
            and item["indices"] == [true_index, wrong_index]
            for item in support_record["copies"]
        ))

        failure_index = meta_episode["support"][1]
        rows[failure_index]["storedFailure"] = "synthetic-unavailable"
        with self.assertRaisesRegex(ValueError, "catalog unavailable"):
            experiment.source_plan(rows, vocabulary, roles)
        rows[failure_index]["storedFailure"] = None

        conflicting_wrong = meta_episode["wrongSupport"][1]
        self.assertNotEqual(rows[conflicting_wrong]["label"], rows[true_index]["label"])
        saved_hash = rows[conflicting_wrong]["rawRasterSHA256"]
        rows[conflicting_wrong]["rawRasterSHA256"] = rows[true_index]["rawRasterSHA256"]
        with self.assertRaisesRegex(ValueError, "conflicting explicit labels"):
            experiment.source_plan(rows, vocabulary, roles)
        rows[conflicting_wrong]["rawRasterSHA256"] = saved_hash

    def test_optimizer_updates_all_scorer_blocks_and_checkpoint_is_finite(self):
        import torch
        from ichart_recognition_ml.research import personal_support_metric as core
        from ichart_recognition_ml.research import personal_support_metric_experiment as experiment

        generator = torch.Generator().manual_seed(430)
        unit = lambda count: torch.nn.functional.normalize(
            torch.randn(count, 128, generator=generator, dtype=torch.float64), dim=1,
        )
        queries, anchors, support = unit(8), unit(97), unit(3)
        generic = torch.randn(8, 97, generator=generator, dtype=torch.float64)
        vocabulary = tuple(f"label-{index:02d}" for index in range(97))
        inputs = (queries, generic, anchors, vocabulary, support, vocabulary[:3])
        frozen = tuple(value.clone() for value in (queries, generic, anchors, support))
        model = core.PersonalSupportMetric()
        initial = {name: value.detach().clone() for name, value in model.state_dict().items()}
        optimizer = torch.optim.Adam(model.parameters(), lr=0.001, weight_decay=0.0)
        targets = torch.arange(8, dtype=torch.long)
        first = experiment.optimizer_step(model, optimizer, inputs, targets)
        second = experiment.optimizer_step(model, optimizer, inputs, targets)
        self.assertTrue(all(value == value for value in (*first.values(), *second.values())
                            if isinstance(value, float)))
        self.assertTrue(all(
            not torch.equal(value, initial[name]) for name, value in model.state_dict().items()
        ))
        self.assertTrue(all(bool(torch.isfinite(value).all()) for value in model.state_dict().values()))
        buffer = io.BytesIO()
        torch.save(model.state_dict(), buffer)
        reloaded = core.PersonalSupportMetric()
        reloaded.load_state_dict(torch.load(io.BytesIO(buffer.getvalue()), weights_only=True))
        self.assertEqual(
            experiment._state_digest(model.state_dict()),
            experiment._state_digest(reloaded.state_dict()),
        )
        for value, expected in zip((queries, generic, anchors, support), frozen, strict=True):
            self.assertTrue(torch.equal(value, expected))
            self.assertIsNone(value.grad)

    def test_historical_generation_validator_allows_only_pinned_swift_drift(self):
        from ichart_recognition_ml.research import personal_support_metric_experiment as experiment

        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary).resolve()
            swift = experiment.SWIFT_CODE
            historical_swift = b"historical Swift source\n"
            current_swift = b"current reviewed Swift source\n"
            python_source = b"unchanged Python source\n"
            (archive / swift).parent.mkdir(parents=True)
            (archive / swift).write_bytes(historical_swift)
            (archive / "toy.py").write_bytes(python_source)
            recorded = {
                swift: experiment.sha(historical_swift),
                "toy.py": experiment.sha(python_source),
            }
            current = {
                swift: experiment.sha(current_swift),
                "toy.py": experiment.sha(python_source),
            }
            patches = (
                mock.patch.object(experiment, "GENERATION_ARCHIVE_PATHS", (swift, "toy.py")),
                mock.patch.object(experiment, "HISTORICAL_SWIFT_SHA256", recorded[swift]),
                mock.patch.object(experiment, "CURRENT_SWIFT_SHA256", current[swift]),
            )
            with patches[0], patches[1], patches[2]:
                experiment.validate_generation_code(recorded, current, archive)

                wrong = dict(recorded)
                wrong[swift] = experiment.sha(b"wrong historical Swift")
                with self.assertRaisesRegex(ValueError, "Unreviewed generation-code drift"):
                    experiment.validate_generation_code(wrong, current, archive)

                wrong = dict(current)
                wrong[swift] = experiment.sha(b"wrong current Swift")
                with self.assertRaisesRegex(ValueError, "Unreviewed generation-code drift"):
                    experiment.validate_generation_code(recorded, wrong, archive)

                wrong = dict(current)
                wrong["toy.py"] = experiment.sha(b"changed Python")
                with self.assertRaisesRegex(ValueError, "Unreviewed generation-code drift"):
                    experiment.validate_generation_code(recorded, wrong, archive)

                wrong = {**current, "extra.py": experiment.sha(b"extra")}
                with self.assertRaisesRegex(ValueError, "Unreviewed generation-code drift"):
                    experiment.validate_generation_code(recorded, wrong, archive)

                (archive / "toy.py").write_bytes(b"tampered archive")
                with self.assertRaisesRegex(ValueError, "Historical generation-code archive"):
                    experiment.validate_generation_code(recorded, current, archive)
                (archive / "toy.py").unlink()
                with self.assertRaises(ValueError):
                    experiment.validate_generation_code(recorded, current, archive)

    def test_domain_projection_requires_unique_raw_legal_winner(self):
        import numpy as np
        from ichart_recognition_ml.research import personal_support_metric_experiment as experiment

        vocabulary = [f"label-{index:02d}" for index in range(97)]
        allowed = {vocabulary[3], vocabulary[7]}
        logits = np.arange(97, dtype=np.float64) * -1.0
        logits[3] = 5.0
        self.assertEqual(experiment.projected(logits, vocabulary, allowed), (3, 3))
        logits[3] = logits[4] = 6.0
        self.assertEqual(experiment.projected(logits, vocabulary, allowed), (None, None))
        logits[4], logits[3] = 8.0, 7.0
        self.assertEqual(experiment.projected(logits, vocabulary, allowed), (4, None))
        logits[4] = float("nan")
        with self.assertRaisesRegex(ValueError, "Full97 finite"):
            experiment.projected(logits, vocabulary, allowed)

    def test_prediction_packet_requires_all_64_episodes_and_failures_block_gate(self):
        import numpy as np
        from ichart_recognition_ml.research import personal_support_metric_experiment as experiment

        plan = {"episodes": {role: [
            {"episodeID": f"{role}-{index}"} for index in range(32)
        ] for role in experiment.ROLES}}
        matrix = np.zeros((97, 97), dtype=np.float64)
        episodes = []
        for role in experiment.ROLES:
            for item in plan["episodes"][role]:
                episodes.append({
                    "episodeID": item["episodeID"],
                    "role": role,
                    "logits": {arm: matrix for arm in experiment.ARMS},
                    "failures": {arm: None for arm in experiment.ARMS},
                })
        packet = {
            "version": experiment.VERSION,
            "queryTruthRead": False,
            "deterministicReplayVerified": True,
            "episodes": episodes,
            "failures": 0,
        }
        experiment.validate_packet(packet, plan)
        with self.assertRaisesRegex(ValueError, "coverage changed"):
            experiment.validate_packet({**packet, "episodes": episodes[:-1]}, plan)
        broken = copy.deepcopy(packet)
        broken["episodes"][0]["logits"]["generic"] = None
        broken["episodes"][0]["failures"]["generic"] = "synthetic"
        broken["failures"] = 1
        with self.assertRaisesRegex(ValueError, "baseline must remain complete"):
            experiment.validate_packet(broken, plan)
        with self.assertRaisesRegex(ValueError, "Failure denominator"):
            experiment.validate_packet({**packet, "failures": 1}, plan)

        retained = copy.deepcopy(packet)
        retained["episodes"][0]["logits"]["wrongSupport"] = None
        retained["episodes"][0]["failures"]["wrongSupport"] = "synthetic failure"
        retained["failures"] = 1
        experiment.validate_packet(retained, plan)

        report = experiment.summarize([{
            "inDomain": True,
            "generic": None,
            "sameSupport": 0,
            "wrongSupport": None,
            "target": 0,
            "taught": False,
            "writer": "writer",
            "supportSession": session,
            "queryIndex": session,
            "invalid": True,
        } for session in (1, 2)])
        self.assertFalse(report["passes"])
        self.assertTrue(report["gates"]["positiveCorrectNet"])
        self.assertTrue(report["gates"]["sameBeatsWrong"])
        self.assertTrue(report["gates"]["sameBeatsWrongEachSession"])
        self.assertFalse(report["gates"]["completeFiniteEvidence"])

    def test_synthetic_prepare_real_960_fit_predict_and_score_stage_separation(self):
        import numpy as np
        import torch
        from ichart_recognition_ml.research import personal_support_metric as core
        from ichart_recognition_ml.research import personal_support_metric_experiment as experiment

        rows, vocabulary, roles, allowed = self._source_fixture(experiment)
        generator = np.random.default_rng(43)
        anchors = generator.normal(size=(97, 128))
        anchors /= np.linalg.norm(anchors, axis=1, keepdims=True)
        writer_names = roles["encoderFitWriters"] + roles["metaFitWriters"] + roles[
            "internalValidationWriters"
        ]
        styles = {writer: generator.normal(scale=0.04, size=128) for writer in writer_names}
        raw_features = np.empty((6208, 128), dtype=np.float64)
        stored_features = np.empty_like(raw_features)
        raw_logits = np.full((6208, 97), -1.0, dtype=np.float64)
        label_index = {label: index for index, label in enumerate(vocabulary)}
        for index, row in enumerate(rows):
            target = label_index[row["label"]]
            raw = anchors[target] + styles[row["writer"]]
            stored = anchors[target] + 1.5 * styles[row["writer"]]
            raw_features[index] = raw / np.linalg.norm(raw)
            stored_features[index] = stored / np.linalg.norm(stored)
            raw_logits[index, target] = 1.0
        arrays = {"raw_features": raw_features, "raw_logits": raw_logits,
                  "stored_features": stored_features}

        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary).resolve()
            synthetic_root = temporary / "source-root"
            protocol_path = synthetic_root / experiment.PROTOCOL
            protocol_path.parent.mkdir(parents=True)
            actual_protocol = (Path(__file__).resolve().parents[2] / experiment.PROTOCOL).read_bytes()
            protocol_path.write_bytes(actual_protocol)
            (synthetic_root / "synthetic.py").write_bytes(b"synthetic support metric fixture\n")
            code = {
                experiment.PROTOCOL: experiment.sha(actual_protocol),
                "synthetic.py": experiment.sha(b"synthetic support metric fixture\n"),
            }
            crossfit = temporary / "crossfit"
            crossfit.mkdir()
            (crossfit / "parent.bin").write_bytes(b"parent")
            metadata_poison = b"not-json: synthetic metadata must remain opaque after prepare"
            (crossfit / "metadata.json").write_bytes(metadata_poison)
            parent_binding = {
                "parent.bin": experiment.sha(b"parent"),
                "metadata.json": experiment.sha(metadata_poison),
            }
            roles_path = temporary / "roles.json"
            roles_path.write_bytes(b"roles")
            domain_path = temporary / "domain.json"
            domain_path.write_bytes(b"domain")
            centroids = temporary / "centroids"
            centroids.mkdir()
            for name in ("centroid-receipt.json", "centroids.npz", "training-features.npz",
                         "training-rows.json"):
                (centroids / name).write_bytes(name.encode())
            runtime = {"python": "synthetic", "torch": str(torch.__version__)}
            calls = {"parent": 0, "centroids": 0, "domain": 0, "identity": 0}

            def fake_parent(*_args):
                calls["parent"] += 1
                return arrays, rows, {"vocabulary": vocabulary}, roles

            def fake_identity(*_args):
                calls["identity"] += 1
                return parent_binding

            def fake_centroids(*_args, **_kwargs):
                calls["centroids"] += 1
                return torch.from_numpy(anchors.copy()), {"synthetic": True}

            def fake_domain(data, expected, actual_vocabulary):
                calls["domain"] += 1
                self.assertEqual(experiment.sha(data), expected)
                self.assertEqual(actual_vocabulary, vocabulary)
                return {"allowedLabels": allowed}

            with ExitStack() as stack:
                stack.enter_context(mock.patch.object(experiment, "ROOT", synthetic_root))
                stack.enter_context(mock.patch.object(experiment, "ROLE_SHA256",
                                                       experiment.sha(b"roles")))
                stack.enter_context(mock.patch.object(experiment, "DOMAIN_SHA256",
                                                       experiment.sha(b"domain")))
                stack.enter_context(mock.patch.object(experiment, "code_identity",
                                                       side_effect=lambda: dict(code)))
                stack.enter_context(mock.patch.object(experiment, "runtime",
                                                       side_effect=lambda: dict(runtime)))
                parent_mock = stack.enter_context(mock.patch.object(
                    experiment, "load_parent", side_effect=fake_parent,
                ))
                identity_mock = stack.enter_context(mock.patch.object(
                    experiment, "input_identity", side_effect=fake_identity,
                ))
                centroid_mock = stack.enter_context(mock.patch.object(
                    experiment, "load_frozen_centroids", side_effect=fake_centroids,
                ))
                domain_mock = stack.enter_context(mock.patch.object(
                    experiment, "validate_domain", side_effect=fake_domain,
                ))
                generation_mock = stack.enter_context(mock.patch.object(
                    experiment,
                    "generation_evidence",
                    return_value=({
                        "generationCodeSHA256": {},
                        "generationArchiveSHA256": {},
                        "currentSwiftSHA256": experiment.CURRENT_SWIFT_SHA256,
                    }, {}, {}),
                ))

                prepared = temporary / "prepared"
                result = experiment.prepare(
                    crossfit, roles_path, centroids, domain_path, prepared,
                )
                preparation_sha = result["commitmentSHA256"]
                self.assertEqual((parent_mock.call_count, identity_mock.call_count,
                                  centroid_mock.call_count, domain_mock.call_count), (1, 1, 1, 1))
                self.assertEqual(generation_mock.call_count, 1)

                original_read = experiment.read

                def fit_read_guard(path, *args, **kwargs):
                    if Path(path).name in {"check-features.npz", "score-truth.json",
                                            "copy-ledger.json"}:
                        raise AssertionError(f"fit opened forbidden artifact: {Path(path).name}")
                    return original_read(path, *args, **kwargs)

                fitted = temporary / "fitted"
                with mock.patch.object(experiment, "read", side_effect=fit_read_guard), \
                        contextlib.redirect_stdout(io.StringIO()):
                    fit_result = experiment.fit(prepared, preparation_sha, fitted)
                fit_sha = fit_result["fitReceiptSHA256"]
                state = torch.load(io.BytesIO((fitted / "weights.pt").read_bytes()),
                                   weights_only=True)
                initial = core.PersonalSupportMetric().state_dict()
                self.assertEqual(set(state), set(initial))
                self.assertTrue(all(torch.isfinite(value).all() for value in state.values()))
                self.assertTrue(all(not torch.equal(state[name], initial[name]) for name in state))
                self.assertEqual((parent_mock.call_count, identity_mock.call_count,
                                  centroid_mock.call_count, domain_mock.call_count), (1, 1, 1, 1))
                self.assertEqual(generation_mock.call_count, 1)

                original_json_file = experiment.json_file
                original_parsed = experiment.parsed
                forbidden = {"meta-targets.json", "score-truth.json", "copy-ledger.json"}

                def predict_json_guard(path, expected=None):
                    if Path(path).name in forbidden:
                        raise AssertionError(f"predict decoded forbidden artifact: {Path(path).name}")
                    return original_json_file(path, expected)

                def predict_read_guard(path, *args, **kwargs):
                    if Path(path).name in forbidden:
                        raise AssertionError(f"predict opened forbidden artifact: {Path(path).name}")
                    return original_read(path, *args, **kwargs)

                def predict_parse_guard(data, *, name):
                    if data == metadata_poison:
                        raise AssertionError("predict decoded source metadata")
                    return original_parsed(data, name=name)

                predicted = temporary / "predicted"
                with mock.patch.object(experiment, "json_file",
                                       side_effect=predict_json_guard), \
                        mock.patch.object(experiment, "read", side_effect=predict_read_guard), \
                        mock.patch.object(experiment, "parsed", side_effect=predict_parse_guard):
                    prediction = experiment.predict(
                        prepared, preparation_sha, fitted, fit_sha, predicted,
                    )
                self.assertEqual(prediction["episodes"], 64)
                self.assertEqual(prediction["scheduledQueries"], 6208)
                self.assertEqual(prediction["failures"], 0)
                self.assertEqual((parent_mock.call_count, identity_mock.call_count,
                                  centroid_mock.call_count, domain_mock.call_count), (1, 1, 1, 1))
                self.assertEqual(generation_mock.call_count, 1)

                scored = temporary / "scored"
                result = experiment.score(
                    prepared, preparation_sha, predicted,
                    prediction["predictionsSHA256"], scored,
                )
                self.assertIn("passes", result)
                self.assertTrue((scored / "score.json").is_file())
                score = experiment.json_file(scored / "score.json", result["scoreSHA256"])
                self.assertEqual(len(score["rows"]), 6208)
                for role in experiment.ROLES:
                    for catalog in experiment.TASKS:
                        for cohort in ("raw", "noCopy"):
                            report = score["reports"][role][catalog][cohort]
                            self.assertEqual(report["exposures"], 1552)
                            self.assertEqual(report["domainQueries"], 41 * 16)
                            self.assertEqual(report["full97Correct"]["generic"], 97 * 16)

                binding, plan = experiment.load_binding(prepared, preparation_sha)
                weights_path = fitted / "weights.pt"
                weights_bytes = weights_path.read_bytes()
                try:
                    weights_path.write_bytes(weights_bytes + b"tamper")
                    with self.assertRaisesRegex(ValueError, "checkpoint bytes changed"):
                        experiment.load_fit(fitted, fit_sha, preparation_sha, binding)
                finally:
                    weights_path.write_bytes(weights_bytes)

                check_path = prepared / "check-features.npz"
                check_bytes = check_path.read_bytes()
                try:
                    check_path.write_bytes(check_bytes + b"tamper")
                    with self.assertRaisesRegex(ValueError, "role arrays changed"):
                        experiment.feature_tensors(
                            prepared, binding, plan, "internalCheck",
                        )
                finally:
                    check_path.write_bytes(check_bytes)

                with self.assertRaisesRegex(ValueError, "Fresh output directory required"):
                    experiment._new_output(scored)


if __name__ == "__main__":
    unittest.main()

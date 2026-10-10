import importlib.util
import unittest
from dataclasses import replace


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalSupportMatchDeferTests(unittest.TestCase):
    @staticmethod
    def _hash(value):
        return f"{value:064x}"

    @staticmethod
    def _unit(torch, rows):
        values = torch.tensor(rows, dtype=torch.float32)
        return torch.nn.functional.normalize(values, dim=1)

    @staticmethod
    def _rasters(torch, count, *, requires_grad=False):
        values = torch.linspace(.01, .99, count * 96 * 256, dtype=torch.float32)
        return values.reshape(count, 1, 96, 256).requires_grad_(requires_grad)

    def test_duplicate_pooling_is_order_stable_and_provenance_strict(self):
        import torch
        from ichart_recognition_ml.research.personal_support_match_defer import pool_confirmed_support

        embeddings = self._unit(torch, [[1, 0, 0] + [0] * 125,
                                        [0, 1, 0] + [0] * 125,
                                        [0, 0, 1] + [0] * 125])
        labels = ("A", "A", "B")
        ids = ("second-a", "first-a", "only-b")
        sources = tuple(self._hash(i) for i in (1, 2, 3))
        inks = tuple(self._hash(i) for i in (11, 12, 13))
        domain = {"A", "B"}.__contains__
        pooled = pool_confirmed_support(embeddings, labels, ids, sources, inks, domain)
        order = torch.tensor([2, 0, 1])
        reordered = pool_confirmed_support(
            embeddings[order], tuple(labels[i] for i in order), tuple(ids[i] for i in order),
            tuple(sources[i] for i in order), tuple(inks[i] for i in order), domain,
        )
        self.assertEqual(pooled.labels, ("A", "B"))
        self.assertEqual(pooled.counts, (2, 1))
        self.assertEqual(pooled.support_ids[0], ("first-a", "second-a"))
        self.assertTrue(torch.equal(pooled.prototypes, reordered.prototypes))
        expected_a = torch.nn.functional.normalize(embeddings[:2].mean(0), dim=0)
        self.assertTrue(torch.equal(pooled.prototypes[0], expected_a))

        invalid = [
            dict(labels=("A", "X", "B")),
            dict(support_ids=("same", "same", "only-b")),
            dict(source_hashes=(sources[0], sources[0], sources[2])),
            dict(ink_hashes=(inks[0], inks[0], inks[2])),
        ]
        base = dict(embeddings=embeddings, labels=labels, support_ids=ids,
                    source_hashes=sources, ink_hashes=inks, is_allowed_label=domain)
        for mutation in invalid:
            with self.subTest(mutation=tuple(mutation)):
                with self.assertRaises(ValueError):
                    pool_confirmed_support(**{**base, **mutation})
        with self.assertRaises(ValueError):
            pool_confirmed_support(embeddings * 2, labels, ids, sources, inks, domain)
        with self.assertRaises(ValueError):
            pool_confirmed_support(
                torch.stack((embeddings[0], -embeddings[0])), ("A", "A"), ids[:2],
                sources[:2], inks[:2], domain,
            )

    def test_encoder_sees_one_support_then_query_batch_and_empty_support_skips_matcher(self):
        import torch
        from ichart_recognition_ml.research.personal_support_match_defer import (
            PersonalSupportMatchDeferModel,
            RouteKind,
            prepare_match_defer_episode,
            route_match_or_defer,
        )

        torch.manual_seed(29)
        model = PersonalSupportMatchDeferModel().eval()
        support = self._rasters(torch, 2)
        query = self._rasters(torch, 3)
        seen = []
        handle = model.encoder.register_forward_pre_hook(lambda _module, args: seen.append(args[0].detach().clone()))
        domain = {"A", "B"}.__contains__
        output = prepare_match_defer_episode(
            model,
            support, query, support_labels=("A", "B"), support_ids=("a", "b"),
            source_hashes=(self._hash(1), self._hash(2)),
            ink_hashes=(self._hash(11), self._hash(12)),
            is_allowed_label=domain,
        )
        handle.remove()
        self.assertEqual(len(seen), 1)
        self.assertTrue(torch.equal(seen[0], torch.cat((support, query))))
        self.assertEqual(output.encoding.query_generic_logits.shape, (3, 97))
        self.assertEqual(output.encoding.query_embeddings.shape, (3, 128))

        defer_logits = torch.zeros(3, 3); defer_logits[:, 2] = 1
        deferred = route_match_or_defer(
            replace(output, match_defer_logits=defer_logits),
            is_allowed_label=domain,
        )
        self.assertIs(deferred.generic_logits, output.encoding.query_generic_logits)
        self.assertEqual(deferred.route_kinds, (RouteKind.GENERIC,) * 3)
        self.assertEqual(deferred.support_labels, (None,) * 3)

        calls = []
        relation = model.relation_mlp.register_forward_hook(lambda *_: calls.append("relation"))
        defer = model.defer_mlp.register_forward_hook(lambda *_: calls.append("defer"))
        empty = prepare_match_defer_episode(
            model,
            support[:0], query, support_labels=(), support_ids=(), source_hashes=(), ink_hashes=(),
            is_allowed_label=domain,
        )
        relation.remove(); defer.remove()
        self.assertIsNone(empty.match_defer_logits)
        self.assertEqual(calls, [])
        routed = route_match_or_defer(empty, is_allowed_label=domain)
        self.assertIs(routed.generic_logits, empty.encoding.query_generic_logits)
        self.assertEqual(routed.support_labels, (None,) * 3)

    def test_prototype_and_label_permutation_is_equivariant_and_remapping_is_class_free(self):
        import torch
        from ichart_recognition_ml.research.personal_support_match_defer import (
            PersonalSupportMatchDeferModel,
            pool_confirmed_support,
        )

        torch.manual_seed(7)
        model = PersonalSupportMatchDeferModel().eval()
        queries = torch.nn.functional.normalize(torch.randn(4, 128), dim=1)
        prototypes = torch.nn.functional.normalize(torch.randn(3, 128), dim=1)
        logits = model(queries, prototypes)
        permutation = torch.tensor([2, 0, 1])
        permuted = model(queries, prototypes[permutation])
        self.assertTrue(torch.equal(permuted[:, :3], logits[:, permutation]))
        self.assertTrue(torch.equal(permuted[:, 3], logits[:, 3]))

        labels = ("z", "a", "z")
        ids = ("z1", "a1", "z2")
        sources = tuple(self._hash(i) for i in (1, 2, 3))
        inks = tuple(self._hash(i) for i in (11, 12, 13))
        original = pool_confirmed_support(prototypes, labels, ids, sources, inks, {"a", "z"}.__contains__)
        renamed_labels = tuple({"a": "y", "z": "b"}[label] for label in labels)
        renamed = pool_confirmed_support(
            prototypes, renamed_labels, ids, sources, inks, {"b", "y"}.__contains__,
        )
        original_logits = model(queries, original.prototypes)
        renamed_logits = model(queries, renamed.prototypes)
        original_by_meaning = {label: original_logits[:, i] for i, label in enumerate(original.labels)}
        renamed_by_meaning = {{"b": "z", "y": "a"}[label]: renamed_logits[:, i]
                              for i, label in enumerate(renamed.labels)}
        for label in original_by_meaning:
            self.assertTrue(torch.equal(original_by_meaning[label], renamed_by_meaning[label]))
        self.assertTrue(torch.equal(original_logits[:, -1], renamed_logits[:, -1]))

    def test_truth_is_loss_only_and_route_never_rescues_a_runner_up(self):
        import torch
        from ichart_recognition_ml.research.personal_support_match_defer import (
            EpisodeEncoding,
            InferenceScope,
            MatchDeferOutput,
            PooledSupport,
            RouteKind,
            match_defer_targets,
            route_match_or_defer,
        )

        generic = torch.zeros(2, 97); generic[:, 0] = 5
        embeddings = torch.nn.functional.normalize(torch.randn(2, 128), dim=1)
        support = PooledSupport(
            labels=("A", "B"), prototypes=embeddings, counts=(1, 1),
            support_ids=(("a",), ("b",)),
            source_hashes=((self._hash(1),), (self._hash(2),)),
            ink_hashes=((self._hash(11),), (self._hash(12),)),
        )
        encoding = EpisodeEncoding(embeddings, embeddings, generic, generic)
        logits = torch.tensor([[1., 9., 8.], [8., 7., 9.]])
        output = MatchDeferOutput(InferenceScope.RESEARCH_COMPARISON_ONLY, encoding, support, logits)
        before = logits.clone()
        domain = {"A", "B"}.__contains__
        route = route_match_or_defer(output, is_allowed_label=domain)
        self.assertIs(route.generic_logits, generic)
        self.assertEqual(route.support_labels, ("B", None))
        self.assertEqual(route.route_kinds, (RouteKind.EXPLICIT_SUPPORT, RouteKind.GENERIC))
        first_targets = match_defer_targets(("A", "X"), support.labels)
        second_targets = match_defer_targets(("X", "B"), support.labels)
        self.assertFalse(torch.equal(first_targets, second_targets))
        self.assertTrue(torch.equal(output.match_defer_logits, before))
        rerouted = route_match_or_defer(output, is_allowed_label=domain)
        self.assertEqual(rerouted.route_kinds, route.route_kinds)
        self.assertEqual(rerouted.support_labels, route.support_labels)
        self.assertIs(rerouted.generic_logits, route.generic_logits)

        support_tie = replace(output, match_defer_logits=torch.tensor([[9., 9., 1.], [9., 9., 1.]]))
        defer_tie = replace(output, match_defer_logits=torch.tensor([[9., 1., 9.], [1., 9., 9.]]))
        for tied in (support_tie, defer_tie):
            tied_route = route_match_or_defer(tied, is_allowed_label=domain)
            self.assertEqual(tied_route.route_kinds, (RouteKind.GENERIC,) * 2)
            self.assertEqual(tied_route.support_labels, (None, None))
            self.assertIs(tied_route.generic_logits, generic)

        invalid = replace(support, labels=("", "B"))
        with self.assertRaises(ValueError):
            route_match_or_defer(replace(output, support=invalid), is_allowed_label=domain)
        forbidden = replace(support, labels=("X", "B"))
        with self.assertRaisesRegex(ValueError, "Unsupported support label"):
            route_match_or_defer(
                replace(output, support=forbidden, match_defer_logits=torch.tensor([[9., 8., 0.], [9., 8., 0.]])),
                is_allowed_label=domain,
            )
        with self.assertRaises(ValueError):
            route_match_or_defer(
                replace(output, match_defer_logits=torch.tensor([[float("nan"), 9, 8], [8, 7, 9]])),
                is_allowed_label=domain,
            )

    def test_balanced_loss_backpropagates_through_both_encoder_paths_and_both_matchers(self):
        import torch
        from ichart_recognition_ml.research.personal_support_match_defer import (
            PersonalSupportMatchDeferModel,
            joint_training_targets,
            joint_training_loss,
            prepare_match_defer_episode,
        )

        torch.manual_seed(29)
        model = PersonalSupportMatchDeferModel().train()
        support = self._rasters(torch, 4, requires_grad=True)
        query = self._rasters(torch, 4, requires_grad=True)
        domain = {"A", "B"}.__contains__
        output = prepare_match_defer_episode(
            model,
            support, query, support_labels=("A", "A", "B", "B"),
            support_ids=("a1", "a2", "b1", "b2"),
            source_hashes=tuple(self._hash(i) for i in range(1, 5)),
            ink_hashes=tuple(self._hash(i) for i in range(11, 15)),
            is_allowed_label=domain,
        )
        vocabulary = ("A", "X", "B", "Y") + tuple(f"L{index}" for index in range(93))
        targets = joint_training_targets(
            ("A", "X", "B", "Y"),
            vocabulary,
            output.support.labels,
        )
        losses = joint_training_loss(
            output.encoding.query_generic_logits,
            targets.generic,
            output.match_defer_logits,
            targets.match_defer,
        )
        output.encoding.support_embeddings.retain_grad()
        output.encoding.query_embeddings.retain_grad()
        losses.match_defer.backward()
        self.assertGreater(float(output.encoding.support_embeddings.grad.abs().sum()), 0)
        self.assertGreater(float(output.encoding.query_embeddings.grad.abs().sum()), 0)
        self.assertGreater(float(model.encoder.projection.weight.grad.abs().sum()), 0)
        self.assertGreater(float(support.grad.abs().sum()), 0)
        self.assertGreater(float(query.grad.abs().sum()), 0)
        self.assertGreater(float(model.relation_mlp[0].weight.grad.abs().sum()), 0)
        self.assertGreater(float(model.defer_mlp[0].weight.grad.abs().sum()), 0)
        self.assertIsNone(model.encoder.classifier.weight.grad)

        model.zero_grad(set_to_none=True)
        support.grad = None
        query.grad = None
        output = prepare_match_defer_episode(
            model,
            support, query, support_labels=("A", "A", "B", "B"),
            support_ids=("a1", "a2", "b1", "b2"),
            source_hashes=tuple(self._hash(i) for i in range(1, 5)),
            ink_hashes=tuple(self._hash(i) for i in range(11, 15)),
            is_allowed_label=domain,
        )
        losses = joint_training_loss(
            output.encoding.query_generic_logits,
            targets.generic,
            output.match_defer_logits,
            targets.match_defer,
        )
        losses.total.backward()
        self.assertGreater(float(model.encoder.classifier.weight.grad.abs().sum()), 0)
        self.assertGreater(float(model.relation_mlp[0].weight.grad.abs().sum()), 0)
        self.assertGreater(float(model.defer_mlp[0].weight.grad.abs().sum()), 0)
        self.assertTrue(torch.isfinite(losses.total))

    def test_false_support_match_can_harm_a_generic_correct_query(self):
        import torch
        from ichart_recognition_ml.research.personal_support_match_defer import (
            EpisodeEncoding,
            InferenceScope,
            MatchDeferOutput,
            PooledSupport,
            route_match_or_defer,
        )

        generic = torch.zeros(1, 97); generic[0, 0] = 10
        feature = torch.nn.functional.normalize(torch.ones(1, 128), dim=1)
        support = PooledSupport(
            labels=("B",), prototypes=feature, counts=(1,),
            support_ids=(("support",),), source_hashes=((self._hash(1),),),
            ink_hashes=((self._hash(2),),),
        )
        encoding = EpisodeEncoding(feature, feature, generic, generic)
        output = MatchDeferOutput(
            InferenceScope.RESEARCH_COMPARISON_ONLY, encoding, support,
            torch.tensor([[4., 0.]]),
        )
        route = route_match_or_defer(output, is_allowed_label={"B"}.__contains__)
        self.assertEqual(int(generic.argmax(1)[0]), 0)
        self.assertEqual(route.support_labels, ("B",))
        self.assertIs(route.generic_logits, generic)

    def test_input_bounds_and_balanced_cohorts_fail_closed(self):
        import torch
        from ichart_recognition_ml.research.personal_support_match_defer import (
            PersonalSupportMatchDeferModel,
            _validate_unit_features,
            joint_training_loss,
            joint_training_targets,
        )

        model = PersonalSupportMatchDeferModel().eval()
        query = self._rasters(torch, 1)
        for invalid in (query * 2, torch.full_like(query, float("nan")), query[:, :, :-1, :]):
            with self.assertRaises(ValueError):
                model.encode_episode(query[:0], invalid)
        combined = torch.zeros(704, 128); combined[:, 0] = 1
        _validate_unit_features(combined, allow_empty=False, maximum=704)
        with self.assertRaises(ValueError):
            _validate_unit_features(
                torch.cat((combined, combined[:1])),
                allow_empty=False,
                maximum=704,
            )
        generic = torch.zeros(2, 97)
        match = torch.zeros(2, 3)
        with self.assertRaisesRegex(ValueError, "taught and untaught"):
            joint_training_loss(generic, torch.tensor([0, 1]), match, torch.tensor([0, 1]))
        with self.assertRaisesRegex(ValueError, "taught and untaught"):
            joint_training_loss(generic, torch.tensor([0, 1]), match, torch.tensor([2, 2]))
        vocabulary = tuple(f"L{index}" for index in range(97))
        targets = joint_training_targets(("L0", "L2"), vocabulary, ("L0",))
        self.assertTrue(torch.equal(targets.generic, torch.tensor([0, 2])))
        self.assertTrue(torch.equal(targets.match_defer, torch.tensor([0, 1])))
        with self.assertRaises(ValueError):
            joint_training_targets(("missing",), vocabulary, ("L0",))


if __name__ == "__main__":
    unittest.main()

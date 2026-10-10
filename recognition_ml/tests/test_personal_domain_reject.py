import unittest

import torch
from torch.nn import functional as F

from ichart_recognition_ml.research import personal_domain_reject as domain
from ichart_recognition_ml.research import personal_stroke_field as field


def vocabulary():
    old = tuple(f"legal-{index:02d}" for index in range(41))
    forbidden = tuple(f"forbidden-{index:02d}" for index in range(56))
    source = old + forbidden + domain.NOVEL_LEGAL_LABELS
    return domain.make_vocabulary(source, old)


def raster_batch(count=2):
    values = torch.linspace(0.0, 1.0, count * 96 * 256, dtype=torch.float32)
    return values.reshape(count, 1, 96, 256)


class PersonalDomainRejectTests(unittest.TestCase):
    def test_vocabulary_is_exact_46_legal_plus_internal_reject(self):
        vocab = vocabulary()
        self.assertEqual(len(vocab.source_labels), 102)
        self.assertEqual(len(vocab.legal_labels), 46)
        self.assertEqual(vocab.legal_labels[-5:], domain.NOVEL_LEGAL_LABELS)
        self.assertEqual(vocab.candidate_labels[-1], domain.REJECT_LABEL)
        self.assertEqual(vocab.reject_index, 46)
        self.assertEqual(len(vocab.forbidden_source_indices), 56)
        self.assertEqual(
            {vocab.source_to_candidate[index] for index in vocab.forbidden_source_indices},
            {vocab.reject_index},
        )
        with self.assertRaises(ValueError):
            domain.make_vocabulary(vocab.source_labels[:-1], vocab.legal_labels[:41])
        with self.assertRaises(ValueError):
            domain.make_vocabulary(vocab.source_labels, vocab.legal_labels[:40] + ("missing",))

    def test_initialization_preserves_rng_and_exact_frozen_control(self):
        vocab = vocabulary()
        torch.manual_seed(481)
        before = torch.get_rng_state().clone()
        models = domain.make_matched_models(vocab)
        self.assertTrue(torch.equal(before, torch.get_rng_state()))

        with torch.random.fork_rng(devices=[]):
            torch.manual_seed(domain.SEED)
            frozen = field.PersonalStrokeFieldEncoder(102, "rasterControl")
        control = models[domain.CONTROL_ARM]
        candidate = models[domain.DOMAIN_REJECT_ARM]
        self.assertEqual(control.label_count, 102)
        self.assertEqual(candidate.label_count, 47)
        for key, value in frozen.state_dict().items():
            self.assertTrue(torch.equal(value, control.state_dict()[key]), key)
        for module_name in ("convolution", "projection"):
            left = getattr(control, module_name).state_dict()
            right = getattr(candidate, module_name).state_dict()
            self.assertEqual(left.keys(), right.keys())
            for key in left:
                self.assertTrue(torch.equal(left[key], right[key]), f"{module_name}.{key}")

        for destination, source in enumerate(vocab.legal_source_indices):
            self.assertTrue(
                torch.equal(
                    candidate.classifier.weight[destination],
                    control.classifier.weight[source],
                )
            )
            self.assertTrue(
                torch.equal(
                    candidate.classifier.bias[destination],
                    control.classifier.bias[source],
                )
            )
        forbidden = torch.tensor(vocab.forbidden_source_indices)
        self.assertTrue(
            torch.equal(
                candidate.classifier.weight[vocab.reject_index],
                control.classifier.weight.index_select(0, forbidden).mean(0),
            )
        )
        self.assertTrue(
            torch.equal(
                candidate.classifier.bias[vocab.reject_index],
                control.classifier.bias.index_select(0, forbidden).mean(0),
            )
        )

    def test_one_plane_control_is_byte_exact_with_frozen_five_plane_model(self):
        vocab = vocabulary()
        models = domain.make_matched_models(vocab)
        control = models[domain.CONTROL_ARM].eval()
        with torch.random.fork_rng(devices=[]):
            torch.manual_seed(domain.SEED)
            frozen = field.PersonalStrokeFieldEncoder(102, "rasterControl").eval()
        rasters = raster_batch()
        five_planes = torch.cat((rasters, torch.zeros((2, 4, 96, 256))), dim=1)
        expected_embedding, expected_logits = frozen(five_planes)
        actual_embedding, actual_logits = control(rasters)
        self.assertTrue(torch.equal(actual_embedding, expected_embedding))
        self.assertTrue(torch.equal(actual_logits, expected_logits))

    def test_target_mapping_drives_real_gradients_in_both_heads(self):
        vocab = vocabulary()
        models = domain.make_matched_models(vocab)
        source_targets = torch.tensor(
            [vocab.legal_source_indices[0], vocab.forbidden_source_indices[0]],
            dtype=torch.long,
        )
        targets = domain.map_targets(source_targets, vocab)
        self.assertTrue(torch.equal(targets[domain.CONTROL_ARM], source_targets))
        self.assertEqual(
            targets[domain.DOMAIN_REJECT_ARM].tolist(), [0, vocab.reject_index]
        )
        rasters = raster_batch()
        for arm in domain.ARMS:
            model = models[arm]
            optimizer = torch.optim.SGD(model.parameters(), lr=0.01)
            before = model.classifier.weight.detach().clone()
            optimizer.zero_grad(set_to_none=True)
            _embedding, logits = model(rasters)
            loss = F.cross_entropy(logits, targets[arm])
            self.assertTrue(bool(torch.isfinite(loss)))
            loss.backward()
            self.assertIsNotNone(model.classifier.weight.grad)
            self.assertTrue(bool(torch.isfinite(model.classifier.weight.grad).all()))
            self.assertGreater(float(model.classifier.weight.grad.abs().sum()), 0.0)
            optimizer.step()
            self.assertFalse(torch.equal(before, model.classifier.weight))
        with self.assertRaises(ValueError):
            domain.map_targets(torch.tensor([102], dtype=torch.long), vocab)
        with self.assertRaises(ValueError):
            domain.map_targets(torch.tensor([0.0]), vocab)

    def test_candidate_unique_max_rejects_ties_and_never_promotes_runner_up(self):
        vocab = vocabulary()
        candidate = torch.zeros((4, 47), dtype=torch.float32)
        candidate[0, 3] = 2.0
        candidate[1, vocab.reject_index] = 3.0
        candidate[1, 4] = 2.9
        candidate[2, 5] = 2.0
        candidate[2, 6] = 2.0
        candidate[3, vocab.reject_index] = 4.0
        candidate[3, 7] = 4.0
        self.assertEqual(
            domain.decode(candidate, domain.DOMAIN_REJECT_ARM, vocab),
            (vocab.legal_labels[3], None, None, None),
        )

        control = torch.zeros((3, 102), dtype=torch.float32)
        control[0, vocab.legal_source_indices[1]] = 2.0
        control[1, vocab.forbidden_source_indices[0]] = 2.0
        control[2, vocab.legal_source_indices[0]] = 3.0
        control[2, vocab.legal_source_indices[1]] = 3.0
        self.assertEqual(
            domain.decode(control, domain.CONTROL_ARM, vocab),
            (vocab.legal_labels[1], None, vocab.legal_labels[0]),
        )

    def test_teaching_labels_allow_only_legal_fragments(self):
        vocab = vocabulary()
        expected = (vocab.legal_labels[0], "#", "1" if "1" in vocab.legal_labels else "ø")
        # The synthetic vocabulary has no literal "1", so exercise another
        # exact legal fragment without adding alias normalization to the core.
        expected = expected[:2] + (vocab.legal_labels[12],)
        self.assertEqual(domain.validate_teaching_labels(expected, vocab), expected)
        for invalid in ((domain.REJECT_LABEL,), (vocab.source_labels[50],), ("unknown",)):
            with self.assertRaises(ValueError):
                domain.validate_teaching_labels(invalid, vocab)

    def test_models_and_decoder_fail_closed_on_malformed_or_nonfinite_values(self):
        vocab = vocabulary()
        model = domain.make_matched_models(vocab)[domain.DOMAIN_REJECT_ARM]
        for malformed in (
            torch.zeros((1, 5, 96, 256), dtype=torch.float32),
            torch.zeros((1, 1, 95, 256), dtype=torch.float32),
            torch.zeros((1, 1, 96, 256), dtype=torch.float64),
        ):
            with self.assertRaises(ValueError):
                model(malformed)
        nonfinite = torch.zeros((1, 1, 96, 256), dtype=torch.float32)
        nonfinite[0, 0, 0, 0] = float("nan")
        with self.assertRaises(ValueError):
            model(nonfinite)
        bad_logits = torch.zeros((1, 47), dtype=torch.float32)
        bad_logits[0, 0] = float("inf")
        with self.assertRaises(ValueError):
            domain.decode(bad_logits, domain.DOMAIN_REJECT_ARM, vocab)
        with self.assertRaises(ValueError):
            domain.decode(torch.zeros((1, 46)), domain.DOMAIN_REJECT_ARM, vocab)


if __name__ == "__main__":
    unittest.main()

"""Synthetic oracle-control contracts only; no model/source/private inference."""

import copy
from dataclasses import dataclass, replace
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import sys

from ichart_recognition_ml.features import InkBounds, InkPoint, InkStroke
from ichart_recognition_ml.research import personal_whole_chord_atomic_control as control


VOCABULARY = tuple(chr(i) for i in range(32, 127)) + ("°", "ø")


@dataclass(frozen=True)
class SourceOnly:
    sample_id: str
    input_sha256: str
    strokes: tuple
    oracle_owner_groups: tuple


def source(strokes=None, groups=((0, 1), (2,), (3,)), sample_id="a" * 64):
    if strokes is None:
        strokes = tuple(InkStroke((InkPoint(i * 20, 0), InkPoint(i * 20 + i + 2, 8))) for i in range(4))
    strokes = tuple(strokes)
    return SourceOnly(sample_id, control.sha256(control.canonical_bytes(control._strokes_value(strokes))), strokes, groups)


def logits(token, *, runner_up=None):
    values = [-3.0] * 97
    values[VOCABULARY.index(token)] = 7.0
    if runner_up is not None:
        values[VOCABULARY.index(runner_up)] = 6.0
    return values


def spec():
    def feature(name, shape):
        return SimpleNamespace(name=name, type=SimpleNamespace(multiArrayType=SimpleNamespace(shape=shape, dataType=65568)))
    return SimpleNamespace(description=SimpleNamespace(
        metadata=SimpleNamespace(userDefined={"ichart.scope": "personal-development-comparison-only",
            "ichart.weights.sha256": control.PINNED_WEIGHTS_SHA256}),
        input=[feature("inkRaster", [1, 1, 96, 256])],
        output=[feature("personalEmbedding", [1, 128]), feature("genericLogits", [1, 97])]))


class AtomicControlTests(unittest.TestCase):
    def run_control(self, tokens=("B", "b", "7"), rows=None, cache=False):
        outputs = iter(logits(t) for t in tokens)
        return control.freeze_oracle_control(rows or (source(),), VOCABULARY,
            lambda pixels: next(outputs), bindings={"protocolSHA256": "b" * 64}, cache_by_raster=cache)

    def test_complete_unrestricted_outputs_source_hashes_and_no_truth_fields(self):
        original = source()
        before = copy.deepcopy(original)
        packet = self.run_control(rows=(original,))
        row = packet["rows"][0]
        self.assertEqual((row["rawTokenString"], row["canonicalChord"]), ("Bb7", "Bb7"))
        self.assertEqual(row["inputSHA256"], original.input_sha256)
        self.assertNotEqual(row["inputSHA256"], row["oracleProjectionRowSHA256"])
        self.assertEqual([o["sourceStrokeIndexes"] for o in row["owners"]], [[0, 1], [2], [3]])
        self.assertEqual([o["sourcePointCount"] for o in row["owners"]], [4, 2, 2])
        self.assertEqual([o["rawLogits"] for o in row["owners"]], [logits(t) for t in ("B", "b", "7")])
        self.assertTrue(all(len(o["rawLogits"]) == 97 for o in row["owners"]))
        self.assertEqual((packet["rowCount"], packet["ownerCount"], packet["inputDrops"], packet["inputFailures"]), (1, 3, 0, 0))
        self.assertFalse(packet["truthJoined"] or packet["productionEligible"] or packet["trustOrAcceptanceApplied"])
        for forbidden in ("intended", "correct", "writer", "sourceLabel", "sourceID"):
            self.assertNotIn(forbidden, json.dumps(packet))
        self.assertEqual(original, before)

    def test_strict_raw_parser_no_alias_case_trim_or_invalid_column_rescue(self):
        for tokens, raw in ((('B', 'm', '7'), 'Bm7'), (('B', 'o', '7'), 'Bo7'),
                            (('b', 'b', '7'), 'bb7'), (('B', '?', '7'), 'B?7'),
                            (('B', ' ', '7'), 'B 7')):
            with self.subTest(raw=raw):
                row = self.run_control(tokens)["rows"][0]
                self.assertEqual(row["rawTokenString"], raw)
                self.assertIsNone(row["canonicalChord"])
                self.assertEqual(len(row["owners"]), 3)
        self.assertEqual(self.run_control(('B', '-', '7'))["rows"][0]["canonicalChord"], 'B-7')

    def test_nonchord_global_winner_and_first_index_tie_not_grammar_rescued(self):
        values = logits('z', runner_up='B')
        row = control.freeze_oracle_control((source(groups=((0, 1, 2, 3),)),), VOCABULARY,
            lambda pixels: values, bindings={"protocolSHA256": "b" * 64})['rows'][0]
        self.assertEqual(row['rawTokenString'], 'z')
        self.assertIsNone(row['canonicalChord'])
        values = [-1.0] * 97
        values[0] = values[VOCABULARY.index('B')] = 4.0
        row = control.freeze_oracle_control((source(groups=((0, 1, 2, 3),)),), VOCABULARY,
            lambda pixels: values, bindings={"protocolSHA256": "b" * 64})['rows'][0]
        self.assertEqual((row['owners'][0]['firstArgmaxIndex'], row['rawTokenString']), (0, ' '))
        self.assertIsNone(row['canonicalChord'])

    def test_malformed_full_distribution_refuses_without_fabricated_token(self):
        for values in ([0.0] * 96, [0.0] * 98, [[0.0] * 97], [True] * 97,
                       [float('nan')] * 97, [float('inf')] * 97, ['0'] * 97):
            with self.subTest(length=len(values)):
                with self.assertRaises(ValueError):
                    control._logits(values)

    def test_middle_inference_failure_retains_owner_and_invalidates_whole_read(self):
        outputs = iter((logits('B'), [0.0] * 96, logits('7')))
        packet = control.freeze_oracle_control((source(),), VOCABULARY,
            lambda pixels: next(outputs), bindings={"protocolSHA256": "b" * 64}, cache_by_raster=False)
        row = packet['rows'][0]
        self.assertEqual(len(row['owners']), 3)
        self.assertEqual(row['owners'][1]['sourceStrokeIndexes'], [2])
        self.assertIsNone(row['owners'][1]['rawLogits'])
        self.assertEqual(row['owners'][1]['failure'], 'owner-model-output-or-inference-failure')
        self.assertIsNone(row['rawTokenString'])
        self.assertIsNone(row['canonicalChord'])
        self.assertEqual((packet['inputFailures'], packet['ownerFailures'], packet['inputDrops']), (1, 1, 0))

    def test_ordinary_backend_exception_retains_middle_owner_and_null_whole_read(self):
        calls = []
        def model(pixels):
            calls.append(pixels)
            if len(calls) == 2:
                raise OSError('synthetic backend failure')
            return logits('B' if len(calls) == 1 else '7')
        packet = control.freeze_oracle_control((source(),), VOCABULARY, model,
            bindings={"protocolSHA256": "b" * 64}, cache_by_raster=False)
        self.assertEqual(len(calls), 3)
        row = packet['rows'][0]
        self.assertEqual(len(row['owners']), 3)
        self.assertEqual(row['owners'][1]['sourceStrokeIndexes'], [2])
        self.assertIsNone(row['rawTokenString'])
        self.assertIsNone(row['canonicalChord'])
        self.assertEqual((packet['inputFailures'], packet['ownerFailures'], packet['inputDrops']), (1, 1, 0))

    def test_raster_encoding_failure_is_retained_not_silently_dropped(self):
        from ichart_recognition_ml.features import FeatureEncodingError
        calls = []
        actual = control.rasterize
        def raster(strokes):
            if len(calls) == 1:
                calls.append('failed')
                raise FeatureEncodingError('synthetic', 'owner', 'test only')
            calls.append('encoded')
            return actual(strokes)
        with patch.object(control, 'rasterize', side_effect=raster):
            packet = self.run_control(tokens=('B', '7'))
        self.assertEqual(len(packet['rows'][0]['owners']), 3)
        self.assertEqual(packet['rows'][0]['owners'][1]['failure'], 'owner-raster-encoding-failure')
        self.assertEqual((packet['ownerFailures'], packet['inputFailures'], packet['inputDrops']), (1, 1, 0))

    def test_ownership_missing_overlap_empty_negative_or_out_of_range_refuse_before_model(self):
        for groups in (((0, 1), (2,)), ((0, 1), (1, 2), (3,)), ((0, 1), (), (2, 3)),
                       ((-1, 0), (1, 2, 3)), ((0, 1), (2,), (4,)), ((1, 0), (2,), (3,))):
            with self.subTest(groups=groups):
                called = []
                with self.assertRaises(ValueError):
                    control.freeze_oracle_control((source(groups=groups),), VOCABULARY,
                        lambda p: called.append(p), bindings={"protocolSHA256": "b" * 64})
                self.assertEqual(called, [])

    def test_exact_raster_cache_retains_every_owner_and_independent_binding(self):
        strokes = (InkStroke((InkPoint(0, 0), InkPoint(2, 8))), InkStroke((InkPoint(20, 0), InkPoint(22, 8))))
        item = source(strokes, ((0,), (1,)))
        calls = []
        packet = control.freeze_oracle_control((item,), VOCABULARY,
            lambda p: calls.append(p) or logits('B'), bindings={"protocolSHA256": "b" * 64})
        owners = packet['rows'][0]['owners']
        self.assertEqual((len(calls), packet['ownerCount'], len(owners)), (1, 2, 2))
        self.assertEqual(owners[0]['rasterSHA256'], owners[1]['rasterSHA256'])
        self.assertNotEqual(owners[0]['ownerInputSHA256'], owners[1]['ownerInputSHA256'])
        self.assertEqual([o['sourceStrokeIndexes'] for o in owners], [[0], [1]])
        self.assertEqual([o['cacheHit'] for o in owners], [False, True])

    def test_input_only_projection_rejects_truth_fields_timing_and_changed_ink_hash(self):
        row = control.source_owner_projection((source(),))[0]
        for field in ('intended', 'writer', 'sourceID'):
            with self.subTest(field=field):
                with self.assertRaises(ValueError):
                    self.run_control(rows=({**row, field: 'forbidden'},))
        bad = copy.deepcopy(row)
        bad['strokes'][0]['points'][0]['timeOffset'] = 1.0
        with self.assertRaises(ValueError):
            self.run_control(rows=(bad,))
        bad = copy.deepcopy(row)
        bad['strokes'][0]['points'][0]['x'] += 1
        with self.assertRaises(ValueError):
            self.run_control(rows=(bad,))
        with self.assertRaises(ValueError):
            control.source_owner_projection((SimpleNamespace(sample_id='a' * 64, intended='B'),))

    def test_projection_keeps_explicit_bounds_and_unavailable_timing(self):
        item = source()
        row = control.source_owner_projection((item,))[0]
        self.assertEqual(row['inputSHA256'], item.input_sha256)
        self.assertEqual(row['strokes'], control._strokes_value(item.strokes))
        self.assertIsNone(row['strokes'][0]['creationTimeOffset'])
        self.assertIsNone(row['strokes'][0]['points'][0]['timeOffset'])
        self.assertEqual(row['strokes'][0]['bounds']['maxX'], item.strokes[0].bounds.max_x)

    def test_runtime_creator_metadata_float32_shape_and_duplicate_outputs_refuse(self):
        control.validate_runtime_spec(spec())
        for change in ('scope', 'weights', 'input_shape', 'output_shape', 'dtype', 'duplicate'):
            value = spec()
            if change == 'scope':
                value.description.metadata.userDefined.pop('ichart.scope')
            elif change == 'weights':
                value.description.metadata.userDefined['ichart.weights.sha256'] = 'a' * 64
            elif change == 'input_shape':
                value.description.input[0].type.multiArrayType.shape = [1, 96, 256]
            elif change == 'output_shape':
                value.description.output[1].type.multiArrayType.shape = [1, 96]
            elif change == 'dtype':
                value.description.input[0].type.multiArrayType.dataType = 65600
            else:
                value.description.output.append(value.description.output[0])
            with self.subTest(change=change), self.assertRaises(ValueError):
                control.validate_runtime_spec(value)

    def test_injected_coreml_adapter_cpu_only_input_and_full_array_validation(self):
        import numpy as np
        calls = []
        outputs = []
        class FakeModel:
            def get_spec(self):
                return spec()
            def predict(self, inputs):
                self_test.assertEqual(set(inputs), {'inkRaster'})
                self_test.assertEqual(inputs['inkRaster'].shape, (1, 1, 96, 256))
                self_test.assertEqual(inputs['inkRaster'].dtype, np.float32)
                self_test.assertGreaterEqual(float(inputs['inkRaster'].min()), 0)
                self_test.assertLessEqual(float(inputs['inkRaster'].max()), 1)
                return {'genericLogits': outputs.pop(0)}
        self_test = self
        backend = SimpleNamespace(__version__='synthetic-test', ComputeUnit=SimpleNamespace(CPU_ONLY='synthetic-CPU-only'),
            models=SimpleNamespace(MLModel=lambda path, compute_units: calls.append((path, compute_units)) or FakeModel()))
        artifact = {'manifestSHA256': control.PINNED_MANIFEST_SHA256, 'packageSHA256': control.PINNED_PACKAGE_SHA256,
            'weightsMetadataSHA256': control.PINNED_WEIGHTS_SHA256, 'vocabulary': list(VOCABULARY),
            'vocabularySHA256': control.sha256(control.canonical_bytes(list(VOCABULARY)))}
        with tempfile.TemporaryDirectory(dir='/private/tmp') as directory:
            manifest = Path(directory) / 'manifest.json'
            manifest.write_bytes(b'synthetic no actual model')
            with patch.dict(sys.modules, {'coremltools': backend}), \
                 patch.object(control, 'validate_pinned_artifacts', return_value=artifact):
                runtime = control.PinnedCoreMLPredictor(manifest, Path(directory) / 'synthetic.mlpackage')
                self.assertEqual(calls, [(str(Path(directory) / 'synthetic.mlpackage'), 'synthetic-CPU-only')])
                pixels = bytes([0, 255]) * (96 * 256 // 2)
                outputs.append(np.array([logits('B')], dtype=np.float32))
                self.assertEqual(runtime(pixels), tuple(logits('B')))
                for bad in (np.zeros((97,)), np.zeros((1, 96)), np.full((1, 97), np.nan)):
                    outputs.append(bad)
                    with self.assertRaises(ValueError):
                        runtime(pixels)

    def test_manifest_or_package_changes_refuse_before_coreml_loading(self):
        with tempfile.TemporaryDirectory(dir='/private/tmp') as directory:
            root = Path(directory)
            package = root / 'model.mlpackage'
            package.mkdir()
            (package / 'weight.bin').write_bytes(b'synthetic package')
            manifest = root / 'manifest.json'
            value = {'researchOnly': True, 'featureCount': 128, 'vocabulary': list(VOCABULARY),
                     'packageSHA256': control.package_digest(package), 'weightsSHA256': 'c' * 64}
            manifest.write_bytes(control.canonical_bytes(value))
            with patch.object(control, 'PINNED_MANIFEST_SHA256', control.sha256(manifest.read_bytes())), \
                 patch.object(control, 'PINNED_PACKAGE_SHA256', value['packageSHA256']), \
                 patch.object(control, 'PINNED_WEIGHTS_SHA256', value['weightsSHA256']):
                receipt = control.validate_pinned_artifacts(manifest, package)
                self.assertEqual(receipt['vocabulary'], list(VOCABULARY))
                (package / 'weight.bin').write_bytes(b'changed')
                with self.assertRaises(ValueError):
                    control.PinnedCoreMLPredictor(manifest, package)
                (package / 'weight.bin').write_bytes(b'synthetic package')
                manifest.write_bytes(b'{}')
                with self.assertRaises(ValueError):
                    control.PinnedCoreMLPredictor(manifest, package)

    def test_invalid_vocabulary_ids_and_missing_bindings_refuse(self):
        for vocabulary in (VOCABULARY[:-1], VOCABULARY + ('x',), VOCABULARY[:-1] + (VOCABULARY[0],)):
            with self.assertRaises(ValueError):
                control.validate_vocabulary(vocabulary)
        with self.assertRaises(ValueError):
            self.run_control(rows=(source(sample_id='writer-label-id'),))
        with self.assertRaises(ValueError):
            control.freeze_oracle_control((source(),), VOCABULARY, lambda p: logits('B'), bindings={})
        with self.assertRaises(ValueError):
            control.freeze_oracle_control((source(),), VOCABULARY, lambda p: logits('B'), bindings={'writerSHA': 'b' * 64})

    def test_output_freeze_is_exclusive_and_does_not_overwrite(self):
        with tempfile.TemporaryDirectory(dir='/private/tmp') as directory:
            output = Path(directory) / 'predictions.json'
            packet = self.run_control()
            digest = control.write_frozen_output(output, packet)
            self.assertEqual(digest, hashlib.sha256(output.read_bytes()).hexdigest())
            original = output.read_bytes()
            with self.assertRaises(FileExistsError):
                control.write_frozen_output(output, {**packet, 'changed': True})
            self.assertEqual(output.read_bytes(), original)

    def test_source_factor_and_atomic_input_hashes_match_both_acquisition_variants(self):
        # Synthetic atoms only. No source file or real model is opened.
        from ichart_recognition_ml.research import personal_whole_chord_source as source_module
        from ichart_recognition_ml.research import personal_whole_chord_factor as factor
        from ichart_recognition_ml.research.uji_personal import Sample
        atoms = tuple(Sample('trn_toy_W01', 1, token, (InkStroke((InkPoint(0, 0), InkPoint(i + 2, 8))),))
                      for i, token in enumerate(('B', 'b', '7')))
        examples = source_module._compose_chord_examples(atoms, 'development', 'Bb7')
        for example in examples:
            item = source_module.WholeChordAtomicOwnerInput(example.sample_id, example.trajectory_source_sha256,
                example.strokes, tuple(atom.acquisition_stroke_indexes for atom in example.atoms))
            projection = control.source_owner_projection((item,))[0]
            self.assertEqual(projection['strokes'], source_module.canonical_strokes_value(item.strokes))
            self.assertEqual(projection['inputSHA256'], source_module.canonical_strokes_sha256(item.strokes))
            whole_input = source_module.WholeChordPredictionInput(item.sample_id, item.input_sha256, item.strokes)
            factor_batch = factor.encode_inputs((whole_input,))
            self.assertEqual(projection['inputSHA256'], factor_batch.input_hashes[0])
            packet = self.run_control(rows=(item,))
            self.assertEqual(packet['rows'][0]['inputSHA256'], example.trajectory_source_sha256)
            self.assertEqual(packet['rows'][0]['rawTokenString'], 'Bb7')
            self.assertEqual([o['sourceStrokeIndexes'] for o in packet['rows'][0]['owners']],
                             [list(atom.acquisition_stroke_indexes) for atom in example.atoms])

    def test_append_only_cli_boundary_with_synthetic_source_plan_and_injected_runtime(self):
        from ichart_recognition_ml.research import personal_whole_chord_factor as factor
        from ichart_recognition_ml.research import personal_whole_chord_source as source_module
        roles = (tuple('train' + str(i) for i in range(32)), tuple('dev' + str(i) for i in range(8)),
                 tuple('reserved' + str(i) for i in range(20)))
        item = source(groups=((0, 1, 2, 3),))
        projected = (item, replace(item, sample_id='c' * 64))
        artifact = {'manifestSHA256': control.PINNED_MANIFEST_SHA256, 'packageSHA256': control.PINNED_PACKAGE_SHA256,
            'weightsMetadataSHA256': control.PINNED_WEIGHTS_SHA256, 'vocabulary': list(VOCABULARY),
            'vocabularySHA256': control.sha256(control.canonical_bytes(list(VOCABULARY)))}
        class FakeRuntime:
            vocabulary = VOCABULARY
            artifact_receipt = artifact
            runtime_receipt = {'computeUnits': 'CPU_ONLY', 'modelExported': False, 'torchWeightsReconstructed': False}
            def __init__(self, manifest, package):
                loads.append((manifest, package))
            def assert_unchanged(self):
                pass
            def __call__(self, pixels):
                return logits('B')
        loads = []
        with tempfile.TemporaryDirectory(dir='/private/tmp') as directory:
            root = Path(directory)
            source_path, protocol_path, manifest_path = (root / n for n in ('source.txt', 'protocol.md', 'manifest.json'))
            for p in (source_path, protocol_path, manifest_path):
                p.write_bytes(b'synthetic only')
            captured = (source_path, protocol_path, b'synthetic only', b'synthetic only', {'synthetic.py': 'a' * 64}, {}, (), roles)
            plan = SimpleNamespace(writers=roles[1], examples=(None, None), version='synthetic-source-plan')
            with patch.object(factor, '_captured_inputs', return_value=captured), \
                 patch.object(factor, '_preserved'), \
                 patch.object(source_module, 'build_role_plan', return_value=plan), \
                 patch.object(source_module, 'atomic_owner_inputs', return_value=projected), \
                 patch.object(control, 'validate_pinned_artifacts', return_value=artifact), \
                 patch.object(control, 'PinnedCoreMLPredictor', FakeRuntime), \
                 patch.object(control, 'DEVELOPMENT_EXAMPLE_COUNT', 2):
                output = root / 'prediction'
                control.predict(source_path, protocol_path, manifest_path, root / 'synthetic.mlpackage', output)
                packet = json.loads((output / 'predictions.json').read_bytes())
                receipt = json.loads((output / 'prediction-receipt.json').read_bytes())
                self.assertEqual(packet['rowCount'], 2)
                self.assertEqual(receipt['predictionsSHA256'], control.sha256((output / 'predictions.json').read_bytes()))
                self.assertEqual(receipt['modelManifestPath'], str(manifest_path))
                self.assertFalse(receipt['productionEligible'])
                self.assertEqual((output / 'frozen-protocol.md').read_bytes(), b'synthetic only')
                self.assertEqual((output / 'model-manifest.json').read_bytes(), b'synthetic only')
                original = (output / 'predictions.json').read_bytes()
                with self.assertRaises(ValueError):
                    control.predict(source_path, protocol_path, manifest_path, root / 'synthetic.mlpackage', output)
                self.assertEqual(len(loads), 1)
                self.assertEqual((output / 'predictions.json').read_bytes(), original)

    def test_cli_wrong_role_or_changed_code_refuses_before_runtime_load(self):
        from ichart_recognition_ml.research import personal_whole_chord_factor as factor
        from ichart_recognition_ml.research import personal_whole_chord_source as source_module
        roles = (tuple('train' + str(i) for i in range(32)), tuple('dev' + str(i) for i in range(8)),
                 tuple('reserved' + str(i) for i in range(20)))
        with tempfile.TemporaryDirectory(dir='/private/tmp') as directory:
            root = Path(directory)
            manifest = root / 'manifest.json'
            manifest.write_bytes(b'synthetic only')
            captured = (root / 'source.txt', root / 'protocol.md', b'source', b'protocol', {}, {}, (), roles)
            plan = SimpleNamespace(writers=('wrong-role',) * 8, examples=(None, None), version='synthetic')
            with patch.object(factor, '_captured_inputs', return_value=captured), \
                 patch.object(control, 'validate_pinned_artifacts', return_value={}), \
                 patch.object(source_module, 'build_role_plan', return_value=plan), \
                 patch.object(control, 'PinnedCoreMLPredictor') as runtime, \
                 patch.object(control, 'DEVELOPMENT_EXAMPLE_COUNT', 2):
                with self.assertRaises(ValueError):
                    control.predict(root / 'source.txt', root / 'protocol.md', manifest, root / 'synthetic.mlpackage', root / 'output')
                runtime.assert_not_called()
            good_plan = SimpleNamespace(writers=roles[1], examples=(None, None), version='synthetic')
            with patch.object(factor, '_captured_inputs', return_value=captured), \
                 patch.object(control, 'validate_pinned_artifacts', return_value={'manifestSHA256': 'a' * 64, 'packageSHA256': 'b' * 64}), \
                 patch.object(source_module, 'build_role_plan', return_value=good_plan), \
                 patch.object(source_module, 'atomic_owner_inputs', return_value=(source(), replace(source(), sample_id='c' * 64))), \
                 patch.object(factor, '_preserved', side_effect=ValueError('synthetic code mutation')), \
                 patch.object(control, 'PinnedCoreMLPredictor') as runtime, \
                 patch.object(control, 'DEVELOPMENT_EXAMPLE_COUNT', 2):
                with self.assertRaises(ValueError):
                    control.predict(root / 'source.txt', root / 'protocol.md', manifest, root / 'synthetic.mlpackage', root / 'output')
                runtime.assert_not_called()


if __name__ == '__main__':
    unittest.main()

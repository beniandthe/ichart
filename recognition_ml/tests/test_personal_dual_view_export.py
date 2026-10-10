import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np


HAS_TORCH = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(HAS_TORCH, "Optional export dependencies required")
class PersonalDualViewExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import torch
        from ichart_recognition_ml.research import personal_dual_view as dual
        from ichart_recognition_ml.research import personal_dual_view_export as export

        cls.torch = torch
        cls.dual = dual
        cls.export = export
        torch.set_num_threads(2)
        cls.models, _ = dual.initialized_models()
        for model in cls.models.values():
            model.eval()
        cls.features = export.feature_cases()

    @staticmethod
    def _stroke_signature(strokes):
        return (
            tuple(stroke.creation_time_offset for stroke in strokes),
            tuple(
                tuple((point.x, point.y, point.time_offset) for point in stroke.points)
                for stroke in strokes
            ),
        )

    def test_twelve_unlabeled_synthetic_originals_have_frozen_coordinates(self):
        e = self.export
        cases = e.synthetic_cases()
        self.assertEqual(tuple(identifier for identifier, _ in cases), e.CASE_IDS)
        expected = {
            "singlePoint": ((None,), (((1.25, -2.5, None),),)),
            "horizontal": (
                (None,),
                (((-9.0, 0.0, None), (0.0, 0.0, None), (11.0, 0.0, None)),),
            ),
            "vertical": (
                (None,),
                (((0.0, -10.0, None), (0.0, 0.0, None), (0.0, 13.0, None)),),
            ),
            "corner": (
                (None,),
                (((-6.0, 7.0, None), (-6.0, -5.0, None), (8.0, -5.0, None)),),
            ),
            "curve": (
                (None,),
                (((-9.0, 4.0, None), (-7.0, 0.0, None), (-3.0, -5.0, None),
                  (3.0, -6.0, None), (9.0, -1.0, None)),),
            ),
            "unequalMultiStroke": (
                (None, None),
                (((-7.0, -4.0, None), (-3.0, 3.0, None), (2.0, 7.0, None),
                  (8.0, 2.0, None)), ((-5.0, 8.0, None), (6.0, -6.0, None))),
            ),
            "reversedDirection": (
                (None,),
                (((11.0, 0.0, None), (0.0, 0.0, None), (-9.0, 0.0, None)),),
            ),
            "reversedStrokeOrder": (
                (None, None),
                (((-5.0, 8.0, None), (6.0, -6.0, None)),
                 ((-7.0, -4.0, None), (-3.0, 3.0, None), (2.0, 7.0, None),
                  (8.0, 2.0, None))),
            ),
            "timedMultiStroke": (
                (0.0, 0.5),
                (((-7.0, -4.0, 0.0), (-3.0, 3.0, 0.1), (2.0, 7.0, 0.2),
                  (8.0, 2.0, 0.3)), ((-5.0, 8.0, 0.0), (6.0, -6.0, 0.2))),
            ),
            "retimedMultiStroke": (
                (4.0, 7.0),
                (((-7.0, -4.0, 0.0), (-3.0, 3.0, 0.25), (2.0, 7.0, 0.5),
                  (8.0, 2.0, 0.75)), ((-5.0, 8.0, 0.0), (6.0, -6.0, 0.9))),
            ),
            "translatedMultiStroke": (
                (None, None),
                (((96.0, -51.0, None), (100.0, -44.0, None), (105.0, -40.0, None),
                  (111.0, -45.0, None)), ((98.0, -39.0, None), (109.0, -53.0, None))),
            ),
            "scaledMultiStroke": (
                (None, None),
                (((-17.5, -10.0, None), (-7.5, 7.5, None), (5.0, 17.5, None),
                  (20.0, 5.0, None)), ((-12.5, 20.0, None), (15.0, -15.0, None))),
            ),
        }
        self.assertEqual(
            {identifier: self._stroke_signature(strokes) for identifier, strokes in cases},
            expected,
        )
        serialized = repr([feature.raw_strokes for feature in self.features]).lower()
        for forbidden in ("label", "writer", "correctness", "intended chord"):
            self.assertNotIn(forbidden, serialized)

    def test_feature_artifacts_are_exact_fixed_shape_bytes(self):
        e = self.export
        self.assertEqual(tuple(feature.case_id for feature in self.features), e.CASE_IDS)
        for feature in self.features:
            self.assertEqual(feature.trajectory.shape, (1, 1, 256, 10))
            self.assertEqual(feature.trajectory.dtype, np.dtype("float32"))
            self.assertEqual(len(feature.trajectory_bytes), 256 * 10 * 4)
            self.assertEqual(feature.raster.shape, (1, 1, 96, 256))
            self.assertEqual(feature.raster.dtype, np.dtype("float32"))
            self.assertEqual(len(feature.raster_uint8), 96 * 256)
            self.assertEqual(len(feature.raster_float32_bytes), 96 * 256 * 4)
            expected_raster = (
                np.frombuffer(feature.raster_uint8, dtype=np.uint8).astype("<f4")
                / np.float32(255.0)
            )
            self.assertEqual(
                feature.raster_float32_bytes,
                expected_raster.astype("<f4", copy=False).tobytes(order="C"),
            )

        by_id = {feature.case_id: feature for feature in self.features}
        self.assertEqual(
            by_id["horizontal"].raster_uint8,
            by_id["reversedDirection"].raster_uint8,
        )
        self.assertNotEqual(
            by_id["horizontal"].trajectory_bytes,
            by_id["reversedDirection"].trajectory_bytes,
        )
        geometry = list(self.dual.GEOMETRY_CHANNELS)
        for identifier in ("timedMultiStroke", "retimedMultiStroke"):
            np.testing.assert_array_equal(
                by_id["unequalMultiStroke"].trajectory[:, :, :, geometry],
                by_id[identifier].trajectory[:, :, :, geometry],
            )
            self.assertNotEqual(
                by_id["unequalMultiStroke"].trajectory_bytes,
                by_id[identifier].trajectory_bytes,
            )

    def test_model_contracts_and_creator_metadata_are_exact(self):
        e = self.export
        self.assertEqual(
            e._input_features(),
            [
                {"dataType": "float32", "name": "inkRaster", "shape": [1, 1, 96, 256]},
                {"dataType": "float32", "name": "inkTrajectory", "shape": [1, 1, 256, 10]},
            ],
        )
        self.assertEqual(
            e._output_features(),
            [
                {"dataType": "float32", "name": "genericLogits", "shape": [1, 97]},
                {"dataType": "float32", "name": "personalEmbedding", "shape": [1, 128]},
            ],
        )
        fit = e.FrozenFit(
            Path("/synthetic"),
            {"vocabularySHA256": "a" * 64, "weightsSHA256": {arm: arm[0] * 64 for arm in e.ARMS}},
            b"",
            {},
            {},
            {},
        )
        metadata = e._metadata("dual", fit)
        self.assertEqual(tuple(sorted(metadata)), e.MODEL_METADATA_KEYS)
        self.assertEqual(metadata["ichart.scope"], "research-runtime-parity-only-not-production")
        self.assertEqual(metadata["ichart.weightSeed"], "29")
        self.assertEqual(
            e._invariance_contract(),
            {
                "inactiveInputProbe": {
                    "zeroRasterForArms": ["trajectoryOnly"],
                    "zeroTrajectoryForArms": ["rasterOnly"],
                },
                "timingProbe": {"trajectoryChannel5": 0.37, "trajectoryChannel6": 1.0},
            },
        )

    def test_traced_output_contract_is_fixed_float32(self):
        e = self.export
        trajectory = self.torch.zeros((1, 1, 256, 10), dtype=self.torch.float32)
        raster = self.torch.zeros((1, 1, 96, 256), dtype=self.torch.float32)
        traced = self.torch.jit.trace(e._ExportWrapper(self.models["dual"]), (trajectory, raster))
        e._validate_traced_output_contract(traced, trajectory, raster)

        def wrong_shape(_trajectory, _raster):
            return self.torch.zeros((1, 128)), self.torch.zeros((97,))

        with self.assertRaisesRegex(ValueError, "Traced Torch output"):
            e._validate_traced_output_contract(wrong_shape, trajectory, raster)

    def test_timing_and_inactive_inputs_are_independent_for_the_frozen_arms(self):
        e = self.export
        feature = self.features[5]
        changed_timing = feature.trajectory.copy()
        changed_timing[:, :, :, 5] = np.float32(0.37)
        changed_timing[:, :, :, 6] = np.float32(1.0)
        for arm in e.ARMS:
            base = e._torch_predict(self.models[arm], feature.trajectory, feature.raster)
            timing = e._torch_predict(self.models[arm], changed_timing, feature.raster)
            self.assertEqual(base, timing)
        raster_base = e._torch_predict(
            self.models["rasterOnly"], feature.trajectory, feature.raster
        )
        raster_zeroed = e._torch_predict(
            self.models["rasterOnly"], np.zeros_like(feature.trajectory), feature.raster
        )
        self.assertEqual(raster_base, raster_zeroed)
        trajectory_base = e._torch_predict(
            self.models["trajectoryOnly"], feature.trajectory, feature.raster
        )
        trajectory_zeroed = e._torch_predict(
            self.models["trajectoryOnly"], feature.trajectory, np.zeros_like(feature.raster)
        )
        self.assertEqual(trajectory_base, trajectory_zeroed)

    def test_fixture_cell_schema_retains_both_runtime_vectors_and_probes(self):
        e = self.export

        class TorchBackedRuntime:
            def __init__(self, model, torch_module):
                self.model = model
                self.torch = torch_module

            def predict(self, inputs):
                with self.torch.inference_mode():
                    embedding, logits = self.model(
                        self.torch.from_numpy(inputs["inkTrajectory"].copy()),
                        self.torch.from_numpy(inputs["inkRaster"].copy()),
                    )
                return {
                    "genericLogits": logits.detach().numpy(),
                    "personalEmbedding": embedding.detach().numpy(),
                }

        expected_keys = {
            "coreMLPython", "inactiveInputProbe", "parity", "rasterFloat32LEBase64",
            "rasterFloat32SHA256", "rasterSHA256", "rasterUInt8Base64", "timingProbe",
            "torch", "trajectoryFloat32LEBase64", "trajectorySHA256",
        }
        probe_keys = {"coreMLPython", "invariance", "parity", "torch"}
        feature = self.features[0]
        for arm in e.ARMS:
            cell = e._case_expected(
                arm,
                self.models[arm],
                TorchBackedRuntime(self.models[arm], self.torch),
                feature,
            )
            self.assertEqual(set(cell), expected_keys)
            self.assertEqual(set(cell["timingProbe"]), probe_keys)
            if arm == "dual":
                self.assertIsNone(cell["inactiveInputProbe"])
            else:
                self.assertEqual(set(cell["inactiveInputProbe"]), probe_keys)
            self.assertEqual(cell["trajectorySHA256"], hashlib.sha256(feature.trajectory_bytes).hexdigest())
            self.assertEqual(cell["rasterSHA256"], hashlib.sha256(feature.raster_uint8).hexdigest())
            self.assertEqual(cell["parity"]["embeddingMaximumAbsoluteError"], 0.0)
            self.assertEqual(cell["parity"]["logitsMaximumAbsoluteError"], 0.0)
            self.assertIs(cell["parity"]["firstGenericArgmaxEqual"], True)

    def test_saved_model_description_rejects_missing_inputs_wrong_shapes_and_extra_metadata(self):
        e = self.export

        class ArrayType:
            def __init__(self, shape):
                self.shape = shape
                self.dataType = 7

        class FeatureType:
            def __init__(self, shape):
                self.multiArrayType = ArrayType(shape)
                self.isOptional = False

            def WhichOneof(self, _name):
                return "multiArrayType"

        class Feature:
            def __init__(self, name, shape):
                self.name = name
                self.type = FeatureType(shape)

        class Metadata:
            def __init__(self, values):
                self.userDefined = values

        class Description:
            def __init__(self, inputs, outputs, metadata):
                self.input = inputs
                self.output = outputs
                self.metadata = Metadata(metadata)

        class Runtime:
            def __init__(self, description):
                self.description = description

            def get_spec(self):
                return type("Spec", (), {"description": self.description})()

        class CoreMLTools:
            proto = type(
                "Proto", (),
                {"FeatureTypes_pb2": type("FeatureTypes", (), {
                    "ArrayFeatureType": type("ArrayFeatureType", (), {"FLOAT32": 7})
                })},
            )

        metadata = {key: key for key in e.MODEL_METADATA_KEYS}
        inputs = [Feature(item["name"], item["shape"]) for item in e._input_features()]
        outputs = [Feature(item["name"], item["shape"]) for item in e._output_features()]
        e._validate_model_contract(
            Runtime(Description(inputs, outputs, metadata)), CoreMLTools, metadata
        )
        with self.assertRaisesRegex(ValueError, "feature names"):
            e._validate_model_contract(
                Runtime(Description(inputs[1:], outputs, metadata)), CoreMLTools, metadata
            )
        outputs[0].type.multiArrayType.shape = [97]
        with self.assertRaisesRegex(ValueError, "shape/type/optionality"):
            e._validate_model_contract(
                Runtime(Description(inputs, outputs, metadata)), CoreMLTools, metadata
            )
        outputs[0].type.multiArrayType.shape = [1, 97]
        with self.assertRaisesRegex(ValueError, "metadata"):
            e._validate_model_contract(
                Runtime(Description(inputs, outputs, {**metadata, "extra": "forbidden"})),
                CoreMLTools,
                metadata,
            )

    def test_fit_receipt_digest_is_checked_before_checkpoint_deserialization(self):
        e = self.export
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            fit = Path(directory) / "fit"
            fit.mkdir()
            (fit / self.dual.FIT_RECEIPT_NAME).write_bytes(b"{}")
            with patch.object(e, "FIT_DIRECTORY", fit), \
                    patch.object(e, "FIT_RECEIPT_SHA256", "f" * 64), \
                    patch.object(self.dual, "_load_checkpoint") as load:
                with self.assertRaisesRegex(ValueError, "predeclared frozen digest"):
                    e.load_frozen_fit(fit)
                load.assert_not_called()

    def test_package_tree_digest_has_frozen_framing_and_rejects_symlinks(self):
        e = self.export
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            package = Path(directory) / "model.mlpackage"
            (package / "z").mkdir(parents=True)
            (package / "a.txt").write_bytes(b"A")
            (package / "z" / "b.bin").write_bytes(b"BC")
            digest = hashlib.sha256()
            for relative, payload in (("a.txt", b"A"), ("z/b.bin", b"BC")):
                digest.update(relative.encode("utf-8"))
                digest.update(b"\0")
                digest.update(hashlib.sha256(payload).hexdigest().encode("ascii"))
                digest.update(b"\n")
            self.assertEqual(e.package_tree_identity(package), (digest.hexdigest(), 3))
            (package / "alias").symlink_to(package / "a.txt")
            with self.assertRaisesRegex(ValueError, "symlink"):
                e.package_tree_identity(package)

    def test_source_binding_is_complete_and_has_no_dataset_or_nonexistent_geometry_file(self):
        e = self.export
        self.assertEqual(set(e.APP_FEATURE_PATHS), {
            "iChart/Recognition/InkTrajectoryTypes.swift",
            "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
            "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
            "iChart/Recognition/Learned/ChordInkRasterizer.swift",
            "iChart/Recognition/Learned/ChordInkTrajectoryFeatureEncoder.swift",
        })
        self.assertIn(e.EXPORT_MODULE_PATH, e.BOUND_SOURCE_PATHS)
        self.assertIn(e.EXPORT_TEST_PATH, e.BOUND_SOURCE_PATHS)
        self.assertIn(e.SWIFT_GATE_PATH, e.BOUND_SOURCE_PATHS)
        self.assertIn(e.PARITY_PROTOCOL_PATH, e.BOUND_SOURCE_PATHS)
        self.assertFalse(any("PreparedFeatureGeometry.swift" in path for path in e.BOUND_SOURCE_PATHS))
        source = Path(e.__file__).read_text(encoding="utf-8")
        self.assertNotIn("load_official_source(", source)
        self.assertNotIn("encode_samples(", source)


if __name__ == "__main__":
    unittest.main()

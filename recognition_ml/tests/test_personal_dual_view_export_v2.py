import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np


HAS_TORCH = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(HAS_TORCH, "Optional export dependencies required")
class PersonalDualViewExportV2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import torch
        from ichart_recognition_ml.research import personal_dual_view as dual
        from ichart_recognition_ml.research import personal_dual_view_export as v1
        from ichart_recognition_ml.research import personal_dual_view_export_v2 as v2

        cls.torch, cls.dual, cls.v1, cls.v2 = torch, dual, v1, v2
        torch.set_num_threads(2)
        cls.models, _ = dual.initialized_models()
        for model in cls.models.values():
            model.eval()
        cls.feature = v1.feature_cases()[5]

    def test_v2_binding_adds_exactly_four_files_to_the_frozen_twenty(self):
        e = self.v2
        self.assertEqual(len(self.v1.BOUND_SOURCE_PATHS), 20)
        self.assertEqual(len(e.BOUND_SOURCE_PATHS), 24)
        self.assertEqual(
            set(e.BOUND_SOURCE_PATHS) - set(self.v1.BOUND_SOURCE_PATHS),
            {e.PARITY_PROTOCOL_PATH, e.EXPORT_MODULE_PATH, e.EXPORT_TEST_PATH, e.SWIFT_GATE_PATH},
        )
        self.assertEqual(e.EXPORT_VERSION, "personal-dual-view-coreml-export-v2")
        self.assertEqual(e.EQUIVALENCE_VERSION, "personal-dual-view-export-equivalence-v2")
        artifacts = e.source_artifacts()
        self.assertEqual(len(artifacts), 24)
        self.assertEqual({item["relativePath"] for item in artifacts}, set(e.BOUND_SOURCE_PATHS))
        source = Path(e.__file__).read_text(encoding="utf-8")
        self.assertNotIn("load_official_source(", source)
        self.assertNotIn("encode_samples(", source)

    def test_wrapper_aliases_original_state_and_is_bit_exact_for_every_arm(self):
        e, torch = self.v2, self.torch
        trajectory = torch.from_numpy(self.feature.trajectory.copy())
        raster = torch.from_numpy(self.feature.raster.copy())
        for arm in e.ARMS:
            model = self.models[arm]
            wrapper = e._ExportWrapperV2(model).eval()
            identity = e._wrapper_identity(model, wrapper)
            self.assertEqual(identity["rawKeys"], [f"model.{key}" for key in identity["normalizedKeys"]])
            self.assertEqual(
                [id(value) for value in wrapper.parameters()],
                [id(value) for value in model.parameters()],
            )
            self.assertEqual(
                [id(value) for value in wrapper.buffers()],
                [id(value) for value in model.buffers()],
            )
            with torch.inference_mode():
                original = e._output_identity(model(trajectory, raster))[1]
                rewritten = e._output_identity(wrapper(trajectory, raster))[1]
            self.assertEqual(rewritten, original)

    def test_wrapper_rejects_any_added_parameter_or_buffer(self):
        e, torch = self.v2, self.torch

        class ExtraState(e._ExportWrapperV2):
            def __init__(self, model):
                super().__init__(model)
                self.register_buffer("forbidden", torch.ones(1))

        with self.assertRaisesRegex(ValueError, "copied, replaced, or added"):
            e._wrapper_identity(self.models["dual"], ExtraState(self.models["dual"]))

    def test_output_contract_rejects_nonfinite_or_non_float32_values(self):
        e, torch = self.v2, self.torch
        valid = (
            torch.nn.functional.normalize(torch.ones((1, 128), dtype=torch.float32), dim=1),
            torch.ones((1, 97), dtype=torch.float32),
        )
        identity, payloads = e._output_identity(valid)
        self.assertEqual(identity["personalEmbedding"]["elementCount"], 128)
        self.assertEqual(identity["genericLogits"]["elementCount"], 97)
        self.assertEqual(sum(map(len, payloads)), (128 + 97) * 4)
        invalid = (torch.full((1, 128), float("nan")), valid[1])
        with self.assertRaisesRegex(ValueError, "finiteness"):
            e._output_identity(invalid)
        with self.assertRaisesRegex(ValueError, "type"):
            e._output_identity((valid[0].double(), valid[1]))

    @staticmethod
    def _const(name, *, ints=None, bools=None):
        node = {"inputs": {}, "outputs": [{"name": name, "shape": []}], "type": "const"}
        if ints is not None:
            node["constInts"] = ints
        if bools is not None:
            node["constBools"] = bools
        return node

    def _candidate_nodes(self):
        e = self.v2
        required = [
            "model_trajectory_convolution_0_weight", "model_trajectory_convolution_0_bias",
            "model_trajectory_convolution_2_weight", "model_trajectory_convolution_2_bias",
            "model_trajectory_convolution_4_weight", "model_trajectory_convolution_4_bias",
            "model_trajectory_projection_weight", "model_trajectory_projection_bias",
            "model_fusion_weight", "model_fusion_bias",
            "model_classifier_weight", "model_classifier_bias",
        ]
        conv_inputs = {f"learned{index}": [name] for index, name in enumerate(required)}
        conv_inputs["x"] = ["selected"]
        return [
            self._const("perm", ints=[0, 1, 3, 2]),
            self._const("squeeze", bools=[False, True, False, False]),
            self._const("axis", ints=[1]),
            self._const("indexes", ints=list(e.INDEXES)),
            {
                "inputs": {"perm": ["perm"], "x": ["inkTrajectory"]},
                "outputs": [{"name": "rank4", "shape": [1, 1, 10, 256]}],
                "type": "transpose",
            },
            {
                "inputs": {"squeeze_mask": ["squeeze"], "x": ["rank4"]},
                "outputs": [{"name": "rank3", "shape": [1, 10, 256]}],
                "type": "slice_by_index",
            },
            {
                "inputs": {"axis": ["axis"], "indices": ["indexes"], "x": ["rank3"]},
                "outputs": [{"name": "selected", "shape": [1, 8, 256]}],
                "type": "gather",
            },
            {"inputs": conv_inputs, "outputs": [{"name": "conv", "shape": []}], "type": "conv"},
        ]

    def test_saved_mil_selector_requires_rank4_transpose_then_axis1_gather(self):
        result = self.v2._selector_graph(self._candidate_nodes(), "trajectoryOnly")
        self.assertEqual(result["selectorCandidateCount"], 1)
        self.assertEqual(result["transposeIndex"], 4)
        self.assertEqual(result["sliceIndex"], 5)
        self.assertEqual(result["gatherIndex"], 6)

    def test_saved_mil_selector_rejects_original_and_optimizer_rewrites(self):
        e = self.v2
        original = [
            self._const("axis2", ints=[2]),
            self._const("indexes", ints=list(e.INDEXES)),
            {
                "inputs": {"axis": ["axis2"], "indices": ["indexes"], "x": ["squeezed"]},
                "outputs": [{"name": "geometry", "shape": [1, 256, 8]}],
                "type": "gather",
            },
        ]
        with self.assertRaisesRegex(ValueError, "rejected gather"):
            e._selector_graph(original, "trajectoryOnly")
        rewritten = self._candidate_nodes()
        rewritten[0]["constInts"] = [0, 1, 2, 3]
        with self.assertRaisesRegex(ValueError, "0 valid V2 selector"):
            e._selector_graph(rewritten, "trajectoryOnly")

    def test_raster_only_may_remove_the_inactive_selector_but_other_arms_may_not(self):
        result = self.v2._selector_graph([], "rasterOnly")
        self.assertIs(result["optimizedAwayAsInactiveBranch"], True)
        with self.assertRaisesRegex(ValueError, "0 valid V2 selector"):
            self.v2._selector_graph([], "dual")

    def test_retained_parent_package_identity_is_exactly_pinned(self):
        e = self.v2
        for arm, expected in e.PARENT_PACKAGE_PINS.items():
            e._verify_parent_package_identity(arm, expected.copy())
            mutated = {**expected, "treeSHA256": "0" * 64}
            with self.assertRaisesRegex(ValueError, "fixed identity"):
                e._verify_parent_package_identity(arm, mutated)
        expected = e.PARENT_PACKAGE_PINS["rasterOnly"]
        mutated = {
            **expected,
            "learnedWeightBlob": {**expected["learnedWeightBlob"], "byteCount": 1},
        }
        with self.assertRaisesRegex(ValueError, "fixed identity"):
            e._verify_parent_package_identity("rasterOnly", mutated)

    def test_dual_control_comparator_requires_same_downstream_graph_and_blob(self):
        e = self.v2
        nodes = [
            {"inputs": {}, "outputs": [], "type": "gather"},
            {"inputs": {}, "outputs": [], "type": "conv"},
            {"inputs": {}, "outputs": [], "type": "linear"},
        ]
        blob = {"byteCount": 4, "relativePath": "weight.bin", "sha256": "a" * 64}
        reference = {
            "downstreamDynamicOperationTypes": ["conv", "linear"],
            "learnedWeightBlob": blob,
        }
        result = e._validate_against_reference(nodes, 0, blob, reference, kind="Dual control")
        self.assertEqual(result, reference)
        with self.assertRaisesRegex(ValueError, "topology changed"):
            e._validate_against_reference(nodes, 1, blob, reference, kind="Dual control")
        with self.assertRaisesRegex(ValueError, "weight blob changed"):
            e._validate_against_reference(
                nodes, 0, {**blob, "sha256": "b" * 64}, reference, kind="Dual control"
            )

    def test_converter_receives_only_v2_wrapper_and_preserves_v1_metadata(self):
        e, torch = self.v2, self.torch
        seen = {}

        class Converted:
            def __init__(self):
                self.user_defined_metadata = {"discard": "me"}

            def save(self, path):
                Path(path).mkdir()

        class CoreMLTools:
            class TensorType:
                def __init__(self, **values):
                    self.values = values

            class ComputeUnit:
                CPU_ONLY = "cpu"

            class target:
                macOS13 = "macOS13"

            class precision:
                FLOAT32 = "float32"

            class models:
                @staticmethod
                def MLModel(path, compute_units):
                    return (path, compute_units)

            @staticmethod
            def convert(traced, **values):
                seen["traced"] = traced
                seen["conversion"] = values
                return Converted()

        fit = self.v1.FrozenFit(
            Path("/synthetic"),
            {
                "vocabularySHA256": "a" * 64,
                "weightsSHA256": {arm: hashlib.sha256(arm.encode()).hexdigest() for arm in e.ARMS},
            },
            b"",
            {},
            {},
            self.models,
        )

        def fake_trace(module, _inputs, **_options):
            seen["wrapper"] = module
            return module

        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory, \
                patch.object(torch.jit, "trace", side_effect=fake_trace), \
                patch.object(self.v1, "_validate_traced_output_contract"), \
                patch.object(self.v1, "_validate_model_contract"), \
                patch.object(e, "_validate_saved_mil", return_value={"passed": True}):
            runtime, static = e._convert_arm(
                CoreMLTools, "dual", fit, Path(directory) / "dual.mlpackage"
            )
        self.assertIsInstance(seen["wrapper"], e._ExportWrapperV2)
        self.assertIs(seen["wrapper"].model, self.models["dual"])
        self.assertEqual(static, {"passed": True})
        self.assertEqual(runtime[1], "cpu")
        self.assertEqual(seen["conversion"]["convert_to"], "mlprogram")
        self.assertEqual(seen["conversion"]["compute_precision"], "float32")


if __name__ == "__main__":
    unittest.main()

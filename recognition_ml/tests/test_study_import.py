import contextlib
import copy
import hashlib
import io
import json
import math
import struct
import tempfile
import unittest
from pathlib import Path

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.study_import import (
    MAXIMUM_CANONICAL_PACKET_BYTE_COUNT,
    MAXIMUM_COMMIT_BYTE_COUNT,
    decode_canonical_commit,
    decode_canonical_study_packet,
    entrypoint,
    import_study_packet,
)


def bits(value):
    return struct.pack(">d", value).hex()


def timing(value=None, state=None):
    if state is None:
        state = "missing" if value is None else (
            "finite" if math.isfinite(value) else "nonFinite"
        )
    if state == "missing":
        return {"state": "missing"}
    return {"bitPattern": bits(value), "state": state}


def point(x, y, time_offset=None):
    return {
        "timeOffset": timing(time_offset),
        "x": bits(x),
        "y": bits(y),
    }


def stroke(points, creation_time_offset=None, bounds=None):
    if bounds is None:
        if points:
            xs = [struct.unpack(">d", bytes.fromhex(value["x"]))[0] for value in points]
            ys = [struct.unpack(">d", bytes.fromhex(value["y"]))[0] for value in points]
            bounds = (min(xs), min(ys), max(xs), max(ys))
        else:
            bounds = (0.0, 0.0, 0.0, 0.0)
    return {
        "bounds": {
            "maxX": bits(bounds[2]),
            "maxY": bits(bounds[3]),
            "minX": bits(bounds[0]),
            "minY": bits(bounds[1]),
        },
        "creationTimeOffset": timing(creation_time_offset),
        "points": points,
    }


def packet(strokes):
    return {
        "coordinateSpace": "transformed-prepared-drawing",
        "formatVersion": "ink-trajectory-packet-v1",
        "strokes": strokes,
    }


def packet_bytes(strokes):
    return canonical_json_bytes(packet(strokes))


def commit(packet_data, **overrides):
    value = {
        "authorizationID": "06060606-0707-0808-0909-101010101010",
        "envelopeByteCount": 1024,
        "envelopeSHA256": "ab" * 32,
        "localCaptureID": "11111111-1212-1313-1414-151515151515",
        "localSessionID": "01010101-0202-0303-0404-050505050505",
        "schemaVersion": "recognition-study-local-commit-v1",
        "trajectoryByteCount": len(packet_data),
        "trajectorySHA256": hashlib.sha256(packet_data).hexdigest(),
    }
    value.update(overrides)
    return value


class RecognitionStudyImportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.packet_data = packet_bytes(
            [stroke([point(0.0, 0.0), point(10.0, 0.0)])]
        )
        self.packet_path = self.root / "trajectory.json"
        self.packet_path.write_bytes(self.packet_data)
        self.trajectory_output = self.root / "features.f32le"
        self.raster_output = self.root / "features.u8"

    def tearDown(self):
        self.temporary.cleanup()

    def test_import_generates_exact_swift_golden_artifacts_and_receipt(self):
        receipt = import_study_packet(
            self.packet_path,
            self.trajectory_output,
            self.raster_output,
            expected_packet_sha256=hashlib.sha256(self.packet_data).hexdigest(),
        )

        trajectory = self.trajectory_output.read_bytes()
        raster = self.raster_output.read_bytes()
        self.assertEqual(len(trajectory), 10_240)
        self.assertEqual(len(raster), 24_576)
        self.assertEqual(
            hashlib.sha256(trajectory).hexdigest(),
            "566333bce82eecec3493e8dfb67187fb4e236ce1d49ce41d5163e1848885bbe1",
        )
        self.assertEqual(receipt.packet_sha256, hashlib.sha256(self.packet_data).hexdigest())
        self.assertEqual(receipt.trajectory_sha256, hashlib.sha256(trajectory).hexdigest())
        self.assertEqual(receipt.raster_sha256, hashlib.sha256(raster).hexdigest())
        self.assertIsNone(receipt.local_capture_id)

    def test_packet_rejects_unknown_missing_duplicate_and_noncanonical_json(self):
        mutations = []
        unknown_top = packet([stroke([point(0.0, 0.0)])])
        unknown_top["label"] = "C7"
        mutations.append((canonical_json_bytes(unknown_top), "unknown_field"))

        missing_nested = packet([stroke([point(0.0, 0.0)])])
        del missing_nested["strokes"][0]["points"][0]["y"]
        mutations.append((canonical_json_bytes(missing_nested), "missing_field"))

        duplicate = self.packet_data.replace(
            b'"formatVersion":',
            b'"formatVersion":"ink-trajectory-packet-v1","formatVersion":',
            1,
        )
        mutations.append((duplicate, "duplicate_json_key"))
        mutations.append((self.packet_data + b"\n", "noncanonical_json"))

        for payload, error in mutations:
            with self.subTest(error=error):
                with self.assertRaisesRegex(ContractError, error):
                    decode_canonical_study_packet(payload)

    def test_packet_rejects_invalid_bit_patterns_and_timing_state_mismatches(self):
        cases = []
        uppercase = packet([stroke([point(0.0, 0.0)])])
        uppercase["strokes"][0]["points"][0]["x"] = bits(1.5).upper()
        cases.append((uppercase, "invalid_bit_pattern"))

        infinite_geometry = packet([stroke([point(0.0, 0.0)])])
        infinite_geometry["strokes"][0]["points"][0]["x"] = bits(math.inf)
        cases.append((infinite_geometry, "nonfinite_geometry"))

        finite_as_nonfinite = packet([stroke([point(0.0, 0.0)])])
        finite_as_nonfinite["strokes"][0]["points"][0]["timeOffset"] = timing(
            0.25, "nonFinite"
        )
        cases.append((finite_as_nonfinite, "timing_state_mismatch"))

        missing_with_bits = packet([stroke([point(0.0, 0.0)])])
        missing_with_bits["strokes"][0]["points"][0]["timeOffset"] = {
            "bitPattern": bits(0.0),
            "state": "missing",
        }
        cases.append((missing_with_bits, "unknown_field"))

        for value, error in cases:
            with self.subTest(error=error):
                with self.assertRaisesRegex(ContractError, error):
                    decode_canonical_study_packet(canonical_json_bytes(value))

    def test_nonfinite_source_timing_is_preserved_then_uses_feature_fallback(self):
        nonfinite_value = packet(
            [
                stroke(
                    [point(0.0, 0.0, math.nan), point(10.0, 0.0, math.inf)],
                    creation_time_offset=math.inf,
                )
            ]
        )
        nonfinite_data = canonical_json_bytes(nonfinite_value)
        decoded = decode_canonical_study_packet(nonfinite_data)
        self.assertTrue(math.isnan(decoded[0].points[0].time_offset))
        self.assertTrue(math.isinf(decoded[0].creation_time_offset))

        nonfinite_path = self.root / "nonfinite-trajectory.json"
        nonfinite_path.write_bytes(nonfinite_data)
        nonfinite_trajectory = self.root / "nonfinite.f32le"
        nonfinite_raster = self.root / "nonfinite.u8"
        import_study_packet(nonfinite_path, nonfinite_trajectory, nonfinite_raster)
        import_study_packet(
            self.packet_path, self.trajectory_output, self.raster_output
        )
        self.assertEqual(
            nonfinite_trajectory.read_bytes(), self.trajectory_output.read_bytes()
        )
        self.assertEqual(nonfinite_raster.read_bytes(), self.raster_output.read_bytes())

    def test_packet_enforces_study_byte_stroke_point_and_nonempty_budgets(self):
        with self.assertRaisesRegex(ContractError, "byte_budget_exceeded"):
            decode_canonical_study_packet(
                b"x" * (MAXIMUM_CANONICAL_PACKET_BYTE_COUNT + 1)
            )
        with self.assertRaisesRegex(ContractError, "stroke_complexity_exceeded"):
            decode_canonical_study_packet(
                packet_bytes([stroke([]) for _ in range(257)])
            )
        with self.assertRaisesRegex(ContractError, "point_complexity_exceeded"):
            decode_canonical_study_packet(
                packet_bytes([stroke([point(float(index), 0.0) for index in range(8_193)])])
            )
        repeated_point = point(0.0, 0.0)
        too_many_total = [
            stroke([repeated_point] * 8_192),
            stroke([repeated_point] * 8_192),
            stroke([repeated_point] * 8_192),
            stroke([repeated_point] * 8_192),
            stroke([repeated_point]),
        ]
        with self.assertRaisesRegex(ContractError, "point_complexity_exceeded"):
            decode_canonical_study_packet(packet_bytes(too_many_total))
        with self.assertRaisesRegex(ContractError, "empty_capture"):
            decode_canonical_study_packet(packet_bytes([]))

    def test_study_valid_empty_stroke_still_fails_closed_at_feature_boundary(self):
        payload = packet_bytes(
            [stroke([]), stroke([point(0.0, 0.0), point(1.0, 0.0)])]
        )
        self.packet_path.write_bytes(payload)
        with self.assertRaisesRegex(ContractError, "empty_stroke"):
            import_study_packet(
                self.packet_path, self.trajectory_output, self.raster_output
            )
        self.assertFalse(self.trajectory_output.exists())
        self.assertFalse(self.raster_output.exists())

    def test_expected_and_commit_digests_are_verified_before_outputs(self):
        wrong = "00" * 32
        with self.assertRaisesRegex(ContractError, "packet_digest_mismatch"):
            import_study_packet(
                self.packet_path,
                self.trajectory_output,
                self.raster_output,
                expected_packet_sha256=wrong,
            )
        with self.assertRaisesRegex(ContractError, "invalid_sha256"):
            import_study_packet(
                self.packet_path,
                self.trajectory_output,
                self.raster_output,
                expected_packet_sha256="ABC",
            )

        commit_path = self.root / "commit.json"
        commit_path.write_bytes(
            canonical_json_bytes(commit(self.packet_data, trajectorySHA256=wrong))
        )
        with self.assertRaisesRegex(ContractError, "commit_digest_mismatch"):
            import_study_packet(
                self.packet_path,
                self.trajectory_output,
                self.raster_output,
                commit_path=commit_path,
            )
        commit_path.write_bytes(
            canonical_json_bytes(
                commit(self.packet_data, trajectoryByteCount=len(self.packet_data) - 1)
            )
        )
        with self.assertRaisesRegex(ContractError, "commit_byte_count_mismatch"):
            import_study_packet(
                self.packet_path,
                self.trajectory_output,
                self.raster_output,
                commit_path=commit_path,
            )
        self.assertFalse(self.trajectory_output.exists())
        self.assertFalse(self.raster_output.exists())

    def test_commit_validates_canonical_uuids_unsigned_numbers_fields_and_budget(self):
        valid = commit(self.packet_data)
        binding = decode_canonical_commit(canonical_json_bytes(valid))
        self.assertEqual(binding.local_capture_id, valid["localCaptureID"])

        invalid_values = []
        uppercase_uuid = copy.deepcopy(valid)
        uppercase_uuid["localCaptureID"] = "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        invalid_values.append((canonical_json_bytes(uppercase_uuid), "invalid_uuid"))
        boolean_count = copy.deepcopy(valid)
        boolean_count["trajectoryByteCount"] = True
        invalid_values.append((canonical_json_bytes(boolean_count), "invalid_integer"))
        zero_count = copy.deepcopy(valid)
        zero_count["trajectoryByteCount"] = 0
        invalid_values.append((canonical_json_bytes(zero_count), "invalid_byte_count"))
        unknown = copy.deepcopy(valid)
        unknown["prompt"] = "C7"
        invalid_values.append((canonical_json_bytes(unknown), "unknown_field"))
        invalid_values.append((canonical_json_bytes(valid) + b" ", "noncanonical_json"))
        invalid_values.append((b"x" * (MAXIMUM_COMMIT_BYTE_COUNT + 1), "byte_budget_exceeded"))

        for payload, error in invalid_values:
            with self.subTest(error=error):
                with self.assertRaisesRegex(ContractError, error):
                    decode_canonical_commit(payload)

    def test_valid_commit_binds_packet_and_surfaces_only_local_capture_id(self):
        commit_path = self.root / "commit.json"
        value = commit(self.packet_data)
        commit_path.write_bytes(canonical_json_bytes(value))
        receipt = import_study_packet(
            self.packet_path,
            self.trajectory_output,
            self.raster_output,
            commit_path=commit_path,
        )
        self.assertEqual(receipt.local_capture_id, value["localCaptureID"])

    def test_outputs_are_exclusive_and_partial_creation_is_rolled_back(self):
        self.raster_output.write_bytes(b"keep")
        with self.assertRaises(FileExistsError):
            import_study_packet(
                self.packet_path, self.trajectory_output, self.raster_output
            )
        self.assertFalse(self.trajectory_output.exists())
        self.assertEqual(self.raster_output.read_bytes(), b"keep")

        with self.assertRaisesRegex(ContractError, "duplicate_output_path"):
            import_study_packet(
                self.packet_path, self.trajectory_output, self.trajectory_output
            )

    def test_module_entrypoint_is_executable_and_never_overwrites(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        arguments = [
            "--trajectory-json",
            str(self.packet_path),
            "--trajectory-output",
            str(self.trajectory_output),
            "--raster-output",
            str(self.raster_output),
        ]
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(entrypoint(arguments), 0)
        receipt = json.loads(stdout.getvalue())
        self.assertEqual(receipt["trajectory_byte_count"], 10_240)
        self.assertEqual(stderr.getvalue(), "")

        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            self.assertEqual(entrypoint(arguments), 2)
        self.assertIn("File exists", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()

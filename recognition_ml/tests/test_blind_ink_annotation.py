import ast
import copy
import hashlib
import inspect
import math
import struct
import unittest
from pathlib import Path

from ichart_recognition_ml.contracts import canonical_json_bytes, strict_json_loads
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.research import blind_ink_annotation as annotation
from ichart_recognition_ml.research.blind_ink_annotation import (
    freeze_identity,
    freeze_ownership,
    make_identity_packets,
    make_identity_review,
    make_ownership_packet,
    make_ownership_review,
    validate_identity_freeze,
    validate_identity_packet,
    validate_ownership_freeze,
    validate_ownership_packet,
)
from test_study_import import bits, packet_bytes, point, stroke


def role_hash(name):
    return hashlib.sha256(("synthetic-role:" + name).encode("utf-8")).hexdigest()


def decode(payload, path="synthetic"):
    return strict_json_loads(payload.decode("utf-8"), path)


def changed(payload, mutate):
    value = copy.deepcopy(decode(payload))
    mutate(value)
    return canonical_json_bytes(value)


class BlindInkAnnotationTests(unittest.TestCase):
    WRITER = role_hash("writer")
    OWNER_ONE = role_hash("owner-one")
    OWNER_TWO = role_hash("owner-two")
    OWNER_THREE = role_hash("owner-three")
    IDENTITY_ONE = role_hash("identity-one")
    IDENTITY_TWO = role_hash("identity-two")
    IDENTITY_THREE = role_hash("identity-three")

    def setUp(self):
        # Synthetic only. It deliberately includes duplicate points, signed
        # zeroes, nonfinite timing (but finite geometry), and zero extent.
        self.source_stroke_values = [
            stroke(
                [point(-0.0, -0.0, math.nan), point(-0.0, -0.0, math.inf)],
                creation_time_offset=-math.inf,
                bounds=(-0.0, -0.0, -0.0, -0.0),
            ),
            stroke(
                [point(10.0, -0.0), point(11.0, 2.0, -0.0)],
                creation_time_offset=-0.0,
                bounds=(9.5, -0.0, 11.5, 2.5),
            ),
            stroke(
                [point(20.0, 3.0, -math.inf)],
                creation_time_offset=math.nan,
                bounds=(20.0, 3.0, 20.0, 3.0),
            ),
            stroke(
                [point(30.0, 4.0, 0.25), point(31.0, 5.0, 0.5)],
                creation_time_offset=7.0,
                bounds=(29.0, 3.0, 32.0, 6.0),
            ),
        ]
        self.source_bytes = packet_bytes(self.source_stroke_values)
        self.ownership_packet = make_ownership_packet(self.source_bytes)

    def assert_code(self, code, operation):
        with self.assertRaises(ContractError) as caught:
            operation()
        self.assertEqual(caught.exception.code, code)

    def resolved_ownership(self, first_groups=((0, 2), (1, 3)),
                           second_groups=((3, 1), (2, 0))):
        first = make_ownership_review(
            self.ownership_packet, self.OWNER_ONE, first_groups
        )
        second = make_ownership_review(
            self.ownership_packet, self.OWNER_TWO, second_groups
        )
        receipt = freeze_ownership(
            self.ownership_packet,
            first,
            second,
            writer_hash=self.WRITER,
        )
        return first, second, receipt

    def test_ownership_packet_preserves_exact_source_bytes_metadata_and_geometry(self):
        source_value = decode(self.source_bytes, "source")
        packet, strokes = validate_ownership_packet(self.ownership_packet)
        self.assertEqual(
            canonical_json_bytes(packet["trajectoryPacket"]), self.source_bytes
        )
        self.assertEqual(packet["trajectoryPacket"], source_value)
        self.assertEqual(
            packet["sourcePacketSHA256"], hashlib.sha256(self.source_bytes).hexdigest()
        )
        self.assertEqual(len(strokes), 4)
        self.assertEqual(len(strokes[0].points), 2)
        self.assertEqual(strokes[0].points[0].x, strokes[0].points[1].x)
        self.assertTrue(math.isnan(strokes[0].points[0].time_offset))
        self.assertTrue(math.isinf(strokes[0].points[1].time_offset))
        self.assertLess(strokes[0].creation_time_offset, 0)
        self.assertEqual(math.copysign(1.0, strokes[1].points[0].y), -1.0)
        self.assertEqual(math.copysign(1.0, strokes[1].creation_time_offset), -1.0)
        self.assertEqual(strokes[0].bounds.min_x, 0.0)
        self.assertEqual(strokes[0].bounds.max_x, 0.0)
        self.assertEqual(source_value["strokes"][0]["points"][0]["x"], bits(-0.0))
        self.assertEqual(source_value["strokes"][1]["creationTimeOffset"]["bitPattern"], bits(-0.0))

    def test_empty_source_stroke_is_preserved_but_can_only_freeze_unresolved(self):
        source = packet_bytes([
            stroke([]),
            stroke([point(2.0, 3.0)], bounds=(2.0, 3.0, 2.0, 3.0)),
        ])
        packet = make_ownership_packet(source)
        packet_value, strokes = validate_ownership_packet(packet)
        self.assertEqual(len(strokes), 2)
        self.assertEqual(strokes[0].points, ())
        self.assertEqual(packet_value["trajectoryPacket"]["strokes"][0]["points"], [])
        self.assert_code(
            "nonseparable_empty_stroke",
            lambda: make_ownership_review(packet, self.OWNER_ONE, [[0], [1]]),
        )
        first = make_ownership_review(packet, self.OWNER_ONE, outcome="unresolved")
        second = make_ownership_review(packet, self.OWNER_TWO, outcome="unresolved")
        receipt = freeze_ownership(packet, first, second, writer_hash=self.WRITER)
        self.assertEqual(validate_ownership_freeze(packet, receipt)["outcome"], "unresolved")
        self.assert_code("ownership_unresolved", lambda: make_identity_packets(packet, receipt))

    def test_global_finite_coordinates_with_nonrepresentable_extent_are_refused(self):
        source = packet_bytes([
            stroke(
                [point(-1.0e308, 0.0), point(1.0e308, 0.0)],
                bounds=(-1.0e308, 0.0, 1.0e308, 0.0),
            )
        ])
        self.assert_code(
            "geometry_extent_not_representable", lambda: make_ownership_packet(source)
        )

    def test_packet_rejects_unknown_missing_duplicate_noncanonical_and_binding_tamper(self):
        unknown = changed(self.ownership_packet, lambda value: value.update({"label": "C7"}))
        missing = changed(self.ownership_packet, lambda value: value.pop("version"))
        duplicate = self.ownership_packet.replace(
            b'{"artifactKind":',
            b'{"artifactKind":"engineering-only-blind-annotation-v1","artifactKind":',
            1,
        )
        wrong_hash = changed(
            self.ownership_packet,
            lambda value: value.update({"sourcePacketSHA256": "00" * 32}),
        )
        cases = [
            ("unknown_field", unknown),
            ("missing_field", missing),
            ("duplicate_json_key", duplicate),
            ("noncanonical_json", self.ownership_packet + b"\n"),
            ("source_binding_mismatch", wrong_hash),
        ]
        for code, payload in cases:
            with self.subTest(code=code):
                self.assert_code(code, lambda payload=payload: validate_ownership_packet(payload))

    def test_source_bounds_must_be_ordered_and_enclose_original_points(self):
        reversed_bounds = packet_bytes([
            stroke([point(1.0, 1.0)], bounds=(2.0, 0.0, 1.0, 2.0))
        ])
        outside = packet_bytes([
            stroke([point(3.0, 3.0)], bounds=(0.0, 0.0, 2.0, 2.0))
        ])
        self.assert_code("invalid_bounds", lambda: make_ownership_packet(reversed_bounds))
        self.assert_code("bounds_do_not_enclose_points", lambda: make_ownership_packet(outside))

    def test_partition_rejects_boolean_negative_missing_duplicate_and_empty(self):
        cases = [
            ("invalid_index", [[True], [1], [2], [3]]),
            ("invalid_index", [[-1, 0], [1], [2, 3]]),
            ("invalid_index", [[0, 1], [2, 4]]),
            ("invalid_index", [[0.0, 1], [2, 3]]),
            ("invalid_partition", [[0], [1], [2]]),
            ("invalid_partition", [[0, 1], [1, 2, 3]]),
            ("invalid_partition", [[0, 1], [], [2, 3]]),
            ("invalid_partition", []),
        ]
        for code, groups in cases:
            with self.subTest(code=code, groups=groups):
                self.assert_code(
                    code,
                    lambda groups=groups: make_ownership_review(
                        self.ownership_packet, self.OWNER_ONE, groups
                    ),
                )

    def test_reordered_groups_have_equal_canonical_ownership(self):
        first, second, receipt = self.resolved_ownership()
        first_value = decode(first)
        second_value = decode(second)
        self.assertEqual(first_value["originalIndexGroups"], [[0, 2], [1, 3]])
        self.assertEqual(second_value["originalIndexGroups"], [[0, 2], [1, 3]])
        frozen = validate_ownership_freeze(self.ownership_packet, receipt)
        self.assertEqual(frozen["outcome"], "partitioned")
        self.assertEqual(frozen["originalIndexGroups"], [[0, 2], [1, 3]])

    def test_noncanonical_direct_review_and_review_binding_are_refused(self):
        good = make_ownership_review(
            self.ownership_packet, self.OWNER_TWO, [[0, 2], [1, 3]]
        )
        noncanonical = changed(
            make_ownership_review(
                self.ownership_packet, self.OWNER_ONE, [[0, 2], [1, 3]]
            ),
            lambda value: value.update({"originalIndexGroups": [[2, 0], [1, 3]]}),
        )
        wrong_packet = changed(
            good, lambda value: value.update({"packetSHA256": "00" * 32})
        )
        self.assert_code(
            "noncanonical_partition",
            lambda: freeze_ownership(
                self.ownership_packet, noncanonical, good, writer_hash=self.WRITER
            ),
        )
        self.assert_code(
            "packet_binding_mismatch",
            lambda: freeze_ownership(
                self.ownership_packet, good, wrong_packet, writer_hash=self.WRITER
            ),
        )

    def test_role_hashes_enforce_mechanical_separation_without_claiming_human_proof(self):
        first = make_ownership_review(
            self.ownership_packet, self.OWNER_ONE, [[0, 2], [1, 3]]
        )
        same = make_ownership_review(
            self.ownership_packet, self.OWNER_ONE, [[0, 2], [1, 3]]
        )
        writer_review = make_ownership_review(
            self.ownership_packet, self.WRITER, [[0, 2], [1, 3]]
        )
        self.assert_code(
            "reviewer_not_independent",
            lambda: freeze_ownership(
                self.ownership_packet, first, same, writer_hash=self.WRITER
            ),
        )
        self.assert_code(
            "reviewer_not_independent",
            lambda: freeze_ownership(
                self.ownership_packet, first, writer_review, writer_hash=self.WRITER
            ),
        )
        packet_value = decode(self.ownership_packet)
        review_value = decode(first)
        self.assertEqual(packet_value["artifactKind"], "engineering-only-blind-annotation-v1")
        self.assertTrue(review_value["blindAttestation"])
        flattened_keys = set(packet_value) | set(review_value)
        self.assertTrue({"independenceVerified", "consentVerified", "provenanceVerified"}.isdisjoint(flattened_keys))

    def test_disagreement_and_unresolved_block_identity_until_third_adjudication(self):
        first = make_ownership_review(
            self.ownership_packet, self.OWNER_ONE, [[0, 1], [2, 3]]
        )
        second = make_ownership_review(
            self.ownership_packet, self.OWNER_TWO, [[0, 2], [1, 3]]
        )
        unresolved = freeze_ownership(
            self.ownership_packet, first, second, writer_hash=self.WRITER
        )
        self.assertEqual(decode(unresolved)["outcome"], "unresolved")
        self.assert_code(
            "ownership_unresolved",
            lambda: make_identity_packets(self.ownership_packet, unresolved),
        )
        bad_third = make_ownership_review(
            self.ownership_packet, self.OWNER_ONE, [[0, 2], [1, 3]]
        )
        self.assert_code(
            "adjudicator_not_independent",
            lambda: freeze_ownership(
                self.ownership_packet,
                first,
                second,
                writer_hash=self.WRITER,
                adjudication=bad_third,
            ),
        )
        third = make_ownership_review(
            self.ownership_packet, self.OWNER_THREE, [[3, 1], [2, 0]]
        )
        resolved = freeze_ownership(
            self.ownership_packet,
            first,
            second,
            writer_hash=self.WRITER,
            adjudication=third,
        )
        frozen = validate_ownership_freeze(self.ownership_packet, resolved)
        self.assertEqual(frozen["outcome"], "partitioned")
        self.assertEqual(frozen["reviewerIDHashes"], [
            self.OWNER_ONE, self.OWNER_TWO, self.OWNER_THREE
        ])
        self.assertEqual(len(make_identity_packets(self.ownership_packet, resolved)), 2)

    def test_identity_packets_are_exact_index_sorted_source_subsets(self):
        _, _, receipt = self.resolved_ownership()
        source = decode(self.source_bytes)
        packets = make_identity_packets(self.ownership_packet, receipt)
        self.assertEqual(len(packets), 2)
        first, decoded_strokes = validate_identity_packet(
            packets[0], self.ownership_packet, receipt
        )
        self.assertEqual(first["originalStrokeIndexes"], [0, 2])
        self.assertEqual(
            first["trajectoryPacket"]["strokes"],
            [source["strokes"][0], source["strokes"][2]],
        )
        self.assertEqual(len(decoded_strokes[0].points), 2)
        self.assertEqual(len(decoded_strokes[1].points), 1)
        self.assertEqual(first["trajectoryPacket"]["strokes"][0]["points"][0]["x"], bits(-0.0))
        self.assertEqual(first["trajectoryPacket"]["strokes"][1]["bounds"]["minX"], bits(20.0))

    def test_identity_packet_requires_both_parent_bindings_and_rejects_tamper(self):
        _, _, receipt = self.resolved_ownership()
        identity = make_identity_packets(self.ownership_packet, receipt)[0]
        self.assert_code(
            "missing_binding_artifact",
            lambda: validate_identity_packet(identity, self.ownership_packet, None),
        )
        mutations = [
            ("source_binding_mismatch", lambda value: value.update({"sourcePacketSHA256": "00" * 32})),
            ("receipt_binding_mismatch", lambda value: value.update({"ownershipReceiptSHA256": "00" * 32})),
            ("group_binding_mismatch", lambda value: value.update({"originalStrokeIndexes": [0, 1]})),
            ("trajectory_binding_mismatch", lambda value: value["trajectoryPacket"].update({
                "strokes": [decode(self.source_bytes)["strokes"][1], decode(self.source_bytes)["strokes"][2]]
            })),
        ]
        for code, mutation in mutations:
            with self.subTest(code=code):
                payload = changed(identity, mutation)
                self.assert_code(
                    code,
                    lambda payload=payload: validate_identity_packet(
                        payload, self.ownership_packet, receipt
                    ),
                )

    def test_ownership_artifacts_cannot_receive_or_expose_identity_labels(self):
        review = make_ownership_review(
            self.ownership_packet, self.OWNER_ONE, [[0, 2], [1, 3]]
        )
        self.assertNotIn("symbol", inspect.signature(make_ownership_review).parameters)
        forbidden = {"symbol", "label", "chord", "intendedAnswer", "prediction"}
        for value in (decode(self.ownership_packet), decode(review)):
            self.assertTrue(forbidden.isdisjoint(value))
            self.assertNotIn("reviewerIDHash", value.get("trajectoryPacket", {}))

    def test_identity_symbol_is_one_printable_nfc_codepoint_and_is_not_chord_normalized(self):
        _, _, receipt = self.resolved_ownership()
        identity = make_identity_packets(self.ownership_packet, receipt)[0]
        accepted = make_identity_review(
            identity, self.IDENTITY_ONE, outcome="symbol", symbol="b"
        )
        self.assertEqual(decode(accepted)["symbol"], "b")
        sharp = make_identity_review(
            identity, self.IDENTITY_TWO, outcome="symbol", symbol="♯"
        )
        self.assertEqual(decode(sharp)["symbol"], "♯")
        for symbol in ("", "C7", "e\u0301", " ", "\n", "\x00"):
            with self.subTest(symbol=repr(symbol)):
                self.assert_code(
                    "invalid_symbol",
                    lambda symbol=symbol: make_identity_review(
                        identity, self.IDENTITY_ONE, outcome="symbol", symbol=symbol
                    ),
                )
        self.assert_code(
            "unexpected_symbol",
            lambda: make_identity_review(
                identity, self.IDENTITY_ONE, outcome="no-read", symbol="C"
            ),
        )

    def test_identity_disagreement_is_preserved_until_separate_adjudication(self):
        _, _, ownership_receipt = self.resolved_ownership()
        identity = make_identity_packets(self.ownership_packet, ownership_receipt)[0]
        first = make_identity_review(identity, self.IDENTITY_ONE, symbol="B")
        second = make_identity_review(identity, self.IDENTITY_TWO, symbol="G")
        frozen = freeze_identity(
            identity,
            first,
            second,
            writer_hash=self.WRITER,
            ownership_reviewer_hashes=[self.OWNER_ONE, self.OWNER_TWO],
            ownership_packet_bytes=self.ownership_packet,
            ownership_receipt_bytes=ownership_receipt,
        )
        value = validate_identity_freeze(
            identity, frozen, self.ownership_packet, ownership_receipt
        )
        self.assertEqual(value["outcome"], "human-ambiguous")
        self.assertIsNone(value["symbol"])
        self.assertEqual([item["symbol"] for item in value["reviews"]], ["B", "G"])
        third = make_identity_review(identity, self.IDENTITY_THREE, symbol="B")
        adjudicated = freeze_identity(
            identity,
            first,
            second,
            writer_hash=self.WRITER,
            ownership_reviewer_hashes=[self.OWNER_TWO, self.OWNER_ONE],
            ownership_packet_bytes=self.ownership_packet,
            ownership_receipt_bytes=ownership_receipt,
            adjudication=third,
        )
        result = validate_identity_freeze(
            identity, adjudicated, self.ownership_packet, ownership_receipt
        )
        self.assertEqual(result["outcome"], "symbol")
        self.assertEqual(result["symbol"], "B")
        self.assertEqual(result["reviewerIDHashes"], [
            self.IDENTITY_ONE, self.IDENTITY_TWO, self.IDENTITY_THREE
        ])

    def test_identity_roles_bind_to_writer_and_every_ownership_reviewer(self):
        _, _, ownership_receipt = self.resolved_ownership()
        identity = make_identity_packets(self.ownership_packet, ownership_receipt)[0]
        first = make_identity_review(identity, self.IDENTITY_ONE, symbol="B")
        second = make_identity_review(identity, self.IDENTITY_TWO, symbol="B")
        common = dict(
            ownership_packet_bytes=self.ownership_packet,
            ownership_receipt_bytes=ownership_receipt,
        )
        self.assert_code(
            "ownership_role_binding_mismatch",
            lambda: freeze_identity(
                identity, first, second, writer_hash=role_hash("other-writer"),
                ownership_reviewer_hashes=[self.OWNER_ONE, self.OWNER_TWO], **common
            ),
        )
        self.assert_code(
            "ownership_role_binding_mismatch",
            lambda: freeze_identity(
                identity, first, second, writer_hash=self.WRITER,
                ownership_reviewer_hashes=[self.OWNER_ONE, self.OWNER_THREE], **common
            ),
        )
        owner_as_identity = make_identity_review(identity, self.OWNER_ONE, symbol="B")
        self.assert_code(
            "reviewer_not_independent",
            lambda: freeze_identity(
                identity, owner_as_identity, second, writer_hash=self.WRITER,
                ownership_reviewer_hashes=[self.OWNER_ONE, self.OWNER_TWO], **common
            ),
        )

    def test_embedded_freeze_evidence_tamper_is_refused(self):
        _, _, ownership_receipt = self.resolved_ownership()
        bad_ownership = changed(
            ownership_receipt,
            lambda value: value.update({"originalIndexGroups": [[0, 1], [2, 3]]}),
        )
        self.assert_code(
            "receipt_evidence_mismatch",
            lambda: validate_ownership_freeze(self.ownership_packet, bad_ownership),
        )
        identity = make_identity_packets(self.ownership_packet, ownership_receipt)[0]
        first = make_identity_review(identity, self.IDENTITY_ONE, symbol="B")
        second = make_identity_review(identity, self.IDENTITY_TWO, symbol="B")
        identity_receipt = freeze_identity(
            identity, first, second, writer_hash=self.WRITER,
            ownership_reviewer_hashes=[self.OWNER_ONE, self.OWNER_TWO],
            ownership_packet_bytes=self.ownership_packet,
            ownership_receipt_bytes=ownership_receipt,
        )
        bad_identity = changed(
            identity_receipt, lambda value: value.update({"symbol": "G"})
        )
        self.assert_code(
            "receipt_evidence_mismatch",
            lambda: validate_identity_freeze(
                identity, bad_identity, self.ownership_packet, ownership_receipt
            ),
        )

    def test_module_has_no_model_pipeline_parser_dependency_or_eligibility_output(self):
        module_path = Path(annotation.__file__)
        tree = ast.parse(module_path.read_text(encoding="utf-8"))
        imports = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imports.update(alias.name for alias in node.names)
            elif isinstance(node, ast.ImportFrom):
                imports.add(node.module or "")
        banned = {
            "features", "train_pipeline", "dataset", "schema", "decode",
            "chord_notation", "models", "evaluate", "selective_evaluation",
        }
        self.assertTrue(banned.isdisjoint(imports), imports)

        source_before = bytes(self.source_bytes)
        first, second, receipt = self.resolved_ownership()
        identity = make_identity_packets(self.ownership_packet, receipt)[0]
        identity_review = make_identity_review(identity, self.IDENTITY_ONE, symbol="B")
        artifacts = [
            decode(self.ownership_packet), decode(first), decode(second), decode(receipt),
            decode(identity), decode(identity_review),
        ]
        eligibility_fields = {
            "split", "role", "trainingEligible", "modelSupervision",
            "consentRecordSHA256", "provenanceRecordSHA256", "prediction",
        }

        def keys(value):
            if isinstance(value, dict):
                return set(value).union(*(keys(item) for item in value.values()))
            if isinstance(value, list):
                return set().union(*(keys(item) for item in value)) if value else set()
            return set()

        for artifact in artifacts:
            self.assertTrue(eligibility_fields.isdisjoint(keys(artifact)))
        self.assertEqual(self.source_bytes, source_before)


if __name__ == "__main__":
    unittest.main()

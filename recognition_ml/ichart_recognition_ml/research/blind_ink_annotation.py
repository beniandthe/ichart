"""Blind, research-only natural-ink annotation artifacts.

Ownership is frozen before any identity packet exposes an isolated group.  The
module never accepts an intended answer, expected symbol count, training split,
or live-recognition result.  It preserves the canonical source trajectory JSON,
including empty strokes, duplicate points, and IEEE-754 timing bit-pattern
strings, and never builds feature tensors.  Indexes always address the prepared
packet's stroke array; they do not claim to be raw PencilKit indexes.  Canonical
group sorting is equality/job bookkeeping, not inferred token or chord reading
order.  Identity labels apply only to isolated groups; full-sequence evaluation
remains a separate future gate.

The hashes, role exclusions, and ``blindAttestation`` fields below enforce only
mechanical consistency.  They do not prove human independence, informed
consent, provenance, corpus eligibility, or recognition quality.  Coordinator
code must retain those separate controls; nothing here is a training or live-app
API.
"""

from __future__ import annotations

import hashlib
import math
import re
import unicodedata
from typing import Mapping, Optional, Sequence, Tuple

from ..contracts import canonical_json_bytes, strict_json_loads
from ..errors import ContractError
from ..study_import import decode_canonical_study_packet


ARTIFACT_KIND = "engineering-only-blind-annotation-v1"
OWNERSHIP_PACKET_VERSION = "blind-ink-ownership-packet-v1"
OWNERSHIP_REVIEW_VERSION = "blind-ink-ownership-review-v1"
OWNERSHIP_FREEZE_VERSION = "blind-ink-ownership-freeze-v1"
IDENTITY_PACKET_VERSION = "blind-ink-identity-packet-v1"
IDENTITY_REVIEW_VERSION = "blind-ink-identity-review-v1"
IDENTITY_FREEZE_VERSION = "blind-ink-identity-freeze-v1"

_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
_OWNERSHIP_PACKET_FIELDS = {
    "artifactKind", "sourcePacketSHA256", "trajectoryPacket", "version"
}
_OWNERSHIP_REVIEW_FIELDS = {
    "blindAttestation", "originalIndexGroups", "outcome", "packetSHA256",
    "reviewerIDHash", "version",
}
_OWNERSHIP_FREEZE_FIELDS = {
    "adjudication", "adjudicationSHA256", "artifactKind", "originalIndexGroups",
    "outcome", "packetSHA256", "reviewerIDHashes", "reviews", "reviewSHA256s",
    "sourcePacketSHA256", "version", "writerIDHash",
}
_IDENTITY_PACKET_FIELDS = {
    "artifactKind", "originalStrokeIndexes", "ownershipReceiptSHA256",
    "sourcePacketSHA256", "trajectoryPacket", "version",
}
_IDENTITY_REVIEW_FIELDS = {
    "blindAttestation", "outcome", "packetSHA256", "reviewerIDHash", "symbol",
    "version",
}
_IDENTITY_FREEZE_FIELDS = {
    "adjudication", "adjudicationSHA256", "artifactKind", "originalStrokeIndexes",
    "outcome", "ownershipReceiptSHA256", "ownershipReviewerIDHashes",
    "packetSHA256", "reviewerIDHashes", "reviews", "reviewSHA256s",
    "sourcePacketSHA256", "symbol", "version", "writerIDHash",
}


def make_ownership_packet(canonical_source_bytes: bytes) -> bytes:
    """Bind one canonical prepared-ink packet without adding labels or outcomes."""

    trajectory, strokes = _decode_source(canonical_source_bytes, "trajectory.json")
    _validate_annotation_strokes(strokes, "trajectory.json.strokes", allow_empty=True)
    return canonical_json_bytes({
        "artifactKind": ARTIFACT_KIND,
        "sourcePacketSHA256": _sha256(canonical_source_bytes),
        "trajectoryPacket": trajectory,
        "version": OWNERSHIP_PACKET_VERSION,
    })


def validate_ownership_packet(packet_bytes: bytes) -> Tuple[dict, Tuple[object, ...]]:
    """Validate a canonical ownership packet and return its exact decoded strokes."""

    packet = _decode_object(packet_bytes, "ownershipPacket")
    _exact_fields(packet, _OWNERSHIP_PACKET_FIELDS, "ownershipPacket")
    _fixed(packet["version"], OWNERSHIP_PACKET_VERSION, "ownershipPacket.version")
    _fixed(packet["artifactKind"], ARTIFACT_KIND, "ownershipPacket.artifactKind")
    source_digest = _hash(packet["sourcePacketSHA256"], "ownershipPacket.sourcePacketSHA256")
    trajectory_bytes = canonical_json_bytes(packet["trajectoryPacket"])
    trajectory, strokes = _decode_source(trajectory_bytes, "ownershipPacket.trajectoryPacket")
    _validate_annotation_strokes(
        strokes, "ownershipPacket.trajectoryPacket.strokes", allow_empty=True
    )
    if _sha256(trajectory_bytes) != source_digest:
        _refuse("source_binding_mismatch", "ownershipPacket.sourcePacketSHA256",
                "does not bind the complete nested trajectory packet")
    if trajectory != packet["trajectoryPacket"]:
        _refuse("trajectory_binding_mismatch", "ownershipPacket.trajectoryPacket",
                "nested trajectory changed during strict decoding")
    return packet, strokes


def make_ownership_review(
    packet_bytes: bytes,
    reviewer_hash: str,
    groups: Optional[Sequence[Sequence[int]]] = None,
    outcome: str = "partitioned",
) -> bytes:
    """Create one blind ownership review; canonicalization is label-free."""

    _, strokes = validate_ownership_packet(packet_bytes)
    reviewer = _hash(reviewer_hash, "reviewerIDHash")
    if outcome == "partitioned":
        if any(not stroke.points for stroke in strokes):
            _refuse("nonseparable_empty_stroke", "originalIndexGroups",
                    "a source containing an empty prepared stroke can only be unresolved")
        partition = _canonical_partition(groups, len(strokes), "originalIndexGroups")
        encoded_groups: object = [list(group) for group in partition]
    elif outcome == "unresolved":
        if groups is not None:
            _refuse("invalid_review_outcome", "originalIndexGroups",
                    "unresolved ownership must not carry a partition")
        encoded_groups = None
    else:
        _refuse("invalid_review_outcome", "outcome", "must be partitioned or unresolved")
    return canonical_json_bytes({
        "blindAttestation": True,
        "originalIndexGroups": encoded_groups,
        "outcome": outcome,
        "packetSHA256": _sha256(packet_bytes),
        "reviewerIDHash": reviewer,
        "version": OWNERSHIP_REVIEW_VERSION,
    })


def freeze_ownership(
    packet_bytes: bytes,
    first_review: bytes,
    second_review: bytes,
    *,
    writer_hash: str,
    adjudication: Optional[bytes] = None,
) -> bytes:
    """Freeze two blinded ownership reviews, never a majority-derived guess."""

    packet, strokes = validate_ownership_packet(packet_bytes)
    packet_digest = _sha256(packet_bytes)
    first, first_groups = _decode_ownership_review(first_review, packet_digest, strokes)
    second, second_groups = _decode_ownership_review(second_review, packet_digest, strokes)
    writer = _hash(writer_hash, "writerIDHash")
    reader_ids = [first["reviewerIDHash"], second["reviewerIDHash"]]
    if len(set(reader_ids)) != 2 or writer in reader_ids:
        _refuse("reviewer_not_independent", "reviewerIDHashes",
                "ownership reviewers must be distinct from each other and the writer")

    adjudication_value = None
    adjudication_digest = None
    final_groups: Optional[Tuple[Tuple[int, ...], ...]]
    if adjudication is not None:
        adjudication_value, final_groups = _decode_ownership_review(
            adjudication, packet_digest, strokes
        )
        adjudicator = adjudication_value["reviewerIDHash"]
        if adjudicator == writer or adjudicator in reader_ids:
            _refuse("adjudicator_not_independent", "adjudication.reviewerIDHash",
                    "adjudicator must be distinct from the writer and both reviewers")
        reader_ids.append(adjudicator)
        adjudication_digest = _sha256(adjudication)
        final_outcome = adjudication_value["outcome"]
    elif first["outcome"] == second["outcome"] == "partitioned" and first_groups == second_groups:
        final_outcome, final_groups = "partitioned", first_groups
    else:
        # Agreement on unresolved and every disagreement remain unresolved.
        final_outcome, final_groups = "unresolved", None

    return canonical_json_bytes({
        "adjudication": adjudication_value,
        "adjudicationSHA256": adjudication_digest,
        "artifactKind": ARTIFACT_KIND,
        "originalIndexGroups": None if final_groups is None else [list(group) for group in final_groups],
        "outcome": final_outcome,
        "packetSHA256": packet_digest,
        "reviewerIDHashes": reader_ids,
        "reviews": [first, second],
        "reviewSHA256s": [_sha256(first_review), _sha256(second_review)],
        "sourcePacketSHA256": packet["sourcePacketSHA256"],
        "version": OWNERSHIP_FREEZE_VERSION,
        "writerIDHash": writer,
    })


def validate_ownership_freeze(packet_bytes: bytes, receipt_bytes: bytes) -> dict:
    """Recompute an ownership freeze from its embedded canonical evidence."""

    receipt = _decode_object(receipt_bytes, "ownershipFreeze")
    _exact_fields(receipt, _OWNERSHIP_FREEZE_FIELDS, "ownershipFreeze")
    _fixed(receipt["version"], OWNERSHIP_FREEZE_VERSION, "ownershipFreeze.version")
    _fixed(receipt["artifactKind"], ARTIFACT_KIND, "ownershipFreeze.artifactKind")
    reviews = _embedded_reviews(receipt["reviews"], "ownershipFreeze.reviews")
    adjudication = _embedded_adjudication(receipt["adjudication"], "ownershipFreeze.adjudication")
    expected = freeze_ownership(
        packet_bytes,
        canonical_json_bytes(reviews[0]),
        canonical_json_bytes(reviews[1]),
        writer_hash=_hash(receipt["writerIDHash"], "ownershipFreeze.writerIDHash"),
        adjudication=None if adjudication is None else canonical_json_bytes(adjudication),
    )
    if expected != receipt_bytes:
        _refuse("receipt_evidence_mismatch", "ownershipFreeze",
                "receipt does not equal the freeze recomputed from embedded reviews")
    return receipt


def make_identity_packets(
    ownership_packet_bytes: bytes,
    ownership_receipt_bytes: bytes,
) -> Tuple[bytes, ...]:
    """Isolate exact source strokes only after a recomputed partition freeze."""

    ownership, _ = validate_ownership_packet(ownership_packet_bytes)
    receipt = validate_ownership_freeze(ownership_packet_bytes, ownership_receipt_bytes)
    if receipt["outcome"] != "partitioned" or receipt["originalIndexGroups"] is None:
        _refuse("ownership_unresolved", "ownershipFreeze.outcome",
                "identity packets require a frozen ownership partition")
    trajectory = _object(ownership["trajectoryPacket"], "ownershipPacket.trajectoryPacket")
    source_strokes = trajectory["strokes"]
    receipt_digest = _sha256(ownership_receipt_bytes)
    packets = []
    for group in receipt["originalIndexGroups"]:
        selected_trajectory = {
            "coordinateSpace": trajectory["coordinateSpace"],
            "formatVersion": trajectory["formatVersion"],
            "strokes": [source_strokes[index] for index in group],
        }
        packets.append(canonical_json_bytes({
            "artifactKind": ARTIFACT_KIND,
            "originalStrokeIndexes": group,
            "ownershipReceiptSHA256": receipt_digest,
            "sourcePacketSHA256": ownership["sourcePacketSHA256"],
            "trajectoryPacket": selected_trajectory,
            "version": IDENTITY_PACKET_VERSION,
        }))
    return tuple(packets)


def validate_identity_packet(
    packet_bytes: bytes,
    ownership_packet_bytes: Optional[bytes] = None,
    ownership_receipt_bytes: Optional[bytes] = None,
) -> Tuple[dict, Tuple[object, ...]]:
    """Validate structure, and when supplied, source/receipt content binding."""

    identity, strokes = _decode_identity_packet(packet_bytes)
    if ownership_packet_bytes is None and ownership_receipt_bytes is None:
        return identity, strokes
    if ownership_packet_bytes is None or ownership_receipt_bytes is None:
        _refuse("missing_binding_artifact", "identityPacket",
                "ownership packet and freeze receipt must be supplied together")
    ownership, _ = validate_ownership_packet(ownership_packet_bytes)
    receipt = validate_ownership_freeze(ownership_packet_bytes, ownership_receipt_bytes)
    if identity["sourcePacketSHA256"] != ownership["sourcePacketSHA256"]:
        _refuse("source_binding_mismatch", "identityPacket.sourcePacketSHA256",
                "does not bind the ownership source packet")
    if identity["ownershipReceiptSHA256"] != _sha256(ownership_receipt_bytes):
        _refuse("receipt_binding_mismatch", "identityPacket.ownershipReceiptSHA256",
                "does not bind the full ownership freeze receipt")
    indexes = tuple(identity["originalStrokeIndexes"])
    groups = receipt["originalIndexGroups"]
    if receipt["outcome"] != "partitioned" or groups is None or list(indexes) not in groups:
        _refuse("group_binding_mismatch", "identityPacket.originalStrokeIndexes",
                "indexes are not one frozen ownership group")
    source = _object(ownership["trajectoryPacket"], "ownershipPacket.trajectoryPacket")
    expected_trajectory = {
        "coordinateSpace": source["coordinateSpace"],
        "formatVersion": source["formatVersion"],
        "strokes": [source["strokes"][index] for index in indexes],
    }
    if identity["trajectoryPacket"] != expected_trajectory:
        _refuse("trajectory_binding_mismatch", "identityPacket.trajectoryPacket",
                "selected strokes are not the exact frozen source group")
    return identity, strokes


def make_identity_review(
    packet_bytes: bytes,
    reviewer_hash: str,
    *,
    outcome: str = "symbol",
    symbol: object = ...,
) -> bytes:
    """Create one blind isolated-glyph review without exposing other groups."""

    _decode_identity_packet(packet_bytes)
    reviewer = _hash(reviewer_hash, "reviewerIDHash")
    resolved_symbol = _identity_symbol(outcome, symbol, "identityReview")
    return canonical_json_bytes({
        "blindAttestation": True,
        "outcome": outcome,
        "packetSHA256": _sha256(packet_bytes),
        "reviewerIDHash": reviewer,
        "symbol": resolved_symbol,
        "version": IDENTITY_REVIEW_VERSION,
    })


def freeze_identity(
    packet_bytes: bytes,
    first_review: bytes,
    second_review: bytes,
    *,
    writer_hash: str,
    ownership_reviewer_hashes: Sequence[str],
    ownership_packet_bytes: bytes,
    ownership_receipt_bytes: bytes,
    adjudication: Optional[bytes] = None,
) -> bytes:
    """Freeze isolated identity evidence with ownership-role separation."""

    packet, _ = validate_identity_packet(
        packet_bytes, ownership_packet_bytes, ownership_receipt_bytes
    )
    ownership_receipt = validate_ownership_freeze(
        ownership_packet_bytes, ownership_receipt_bytes
    )
    packet_digest = _sha256(packet_bytes)
    first, first_result = _decode_identity_review(first_review, packet_digest)
    second, second_result = _decode_identity_review(second_review, packet_digest)
    writer = _hash(writer_hash, "writerIDHash")
    if writer != ownership_receipt["writerIDHash"]:
        _refuse("ownership_role_binding_mismatch", "writerIDHash",
                "identity writer must equal the source ownership receipt writer")
    ownership_ids = _ownership_reviewer_ids(ownership_reviewer_hashes)
    actual_ownership_ids = _ownership_reviewer_ids(
        ownership_receipt["reviewerIDHashes"], "ownershipFreeze.reviewerIDHashes"
    )
    if ownership_ids != actual_ownership_ids:
        _refuse("ownership_role_binding_mismatch", "ownershipReviewerIDHashes",
                "must exactly equal every reviewer in the source ownership receipt")
    reader_ids = [first["reviewerIDHash"], second["reviewerIDHash"]]
    if len(set(reader_ids)) != 2 or writer in reader_ids or any(value in ownership_ids for value in reader_ids):
        _refuse("reviewer_not_independent", "reviewerIDHashes",
                "identity reviewers must differ from writer, ownership reviewers, and each other")

    adjudication_value = None
    adjudication_digest = None
    if adjudication is not None:
        adjudication_value, final_result = _decode_identity_review(adjudication, packet_digest)
        adjudicator = adjudication_value["reviewerIDHash"]
        if adjudicator == writer or adjudicator in reader_ids or adjudicator in ownership_ids:
            _refuse("adjudicator_not_independent", "adjudication.reviewerIDHash",
                    "adjudicator must be distinct from every writer and reviewer role")
        reader_ids.append(adjudicator)
        adjudication_digest = _sha256(adjudication)
    elif first_result == second_result:
        final_result = first_result
    else:
        final_result = ("human-ambiguous", None)

    return canonical_json_bytes({
        "adjudication": adjudication_value,
        "adjudicationSHA256": adjudication_digest,
        "artifactKind": ARTIFACT_KIND,
        "originalStrokeIndexes": packet["originalStrokeIndexes"],
        "outcome": final_result[0],
        "ownershipReceiptSHA256": packet["ownershipReceiptSHA256"],
        "ownershipReviewerIDHashes": list(ownership_ids),
        "packetSHA256": packet_digest,
        "reviewerIDHashes": reader_ids,
        "reviews": [first, second],
        "reviewSHA256s": [_sha256(first_review), _sha256(second_review)],
        "sourcePacketSHA256": packet["sourcePacketSHA256"],
        "symbol": final_result[1],
        "version": IDENTITY_FREEZE_VERSION,
        "writerIDHash": writer,
    })


def validate_identity_freeze(
    packet_bytes: bytes,
    receipt_bytes: bytes,
    ownership_packet_bytes: bytes,
    ownership_receipt_bytes: bytes,
) -> dict:
    """Recompute an identity freeze from its embedded canonical evidence."""

    receipt = _decode_object(receipt_bytes, "identityFreeze")
    _exact_fields(receipt, _IDENTITY_FREEZE_FIELDS, "identityFreeze")
    _fixed(receipt["version"], IDENTITY_FREEZE_VERSION, "identityFreeze.version")
    _fixed(receipt["artifactKind"], ARTIFACT_KIND, "identityFreeze.artifactKind")
    reviews = _embedded_reviews(receipt["reviews"], "identityFreeze.reviews")
    adjudication = _embedded_adjudication(receipt["adjudication"], "identityFreeze.adjudication")
    expected = freeze_identity(
        packet_bytes,
        canonical_json_bytes(reviews[0]),
        canonical_json_bytes(reviews[1]),
        writer_hash=_hash(receipt["writerIDHash"], "identityFreeze.writerIDHash"),
        ownership_reviewer_hashes=_ownership_reviewer_ids(
            receipt["ownershipReviewerIDHashes"], "identityFreeze.ownershipReviewerIDHashes"
        ),
        ownership_packet_bytes=ownership_packet_bytes,
        ownership_receipt_bytes=ownership_receipt_bytes,
        adjudication=None if adjudication is None else canonical_json_bytes(adjudication),
    )
    if expected != receipt_bytes:
        _refuse("receipt_evidence_mismatch", "identityFreeze",
                "receipt does not equal the freeze recomputed from embedded reviews")
    return receipt


def _decode_source(payload: bytes, path: str) -> Tuple[dict, Tuple[object, ...]]:
    value = _decode_object(payload, path)
    strokes = decode_canonical_study_packet(payload)
    return value, strokes


def _validate_annotation_strokes(
    strokes: Sequence[object], path: str, *, allow_empty: bool
) -> None:
    if not strokes:
        _refuse("empty_capture", path, "must contain at least one stroke")
    for stroke_index, stroke in enumerate(strokes):
        stroke_path = f"{path}[{stroke_index}]"
        if not stroke.points and not allow_empty:
            _refuse("empty_stroke", f"{stroke_path}.points", "annotation strokes must be nonempty")
        bounds = stroke.bounds
        if bounds is None:
            _refuse("invalid_bounds", f"{stroke_path}.bounds", "bounds are required")
        values = (bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y)
        if not all(math.isfinite(value) for value in values):
            _refuse("nonfinite_geometry", f"{stroke_path}.bounds", "bounds must be finite")
        if bounds.min_x > bounds.max_x or bounds.min_y > bounds.max_y:
            _refuse("invalid_bounds", f"{stroke_path}.bounds", "bounds must be ordered")
        if any(not (bounds.min_x <= point.x <= bounds.max_x and
                    bounds.min_y <= point.y <= bounds.max_y) for point in stroke.points):
            _refuse("bounds_do_not_enclose_points", f"{stroke_path}.bounds",
                    "bounds must enclose every original point")
    points = [point for stroke in strokes for point in stroke.points]
    if points:
        width = max(point.x for point in points) - min(point.x for point in points)
        height = max(point.y for point in points) - min(point.y for point in points)
        if not math.isfinite(width) or not math.isfinite(height):
            _refuse("geometry_extent_not_representable", path,
                    "finite source coordinates must also have finite global extents")


def _decode_ownership_review(
    payload: bytes, packet_digest: str, strokes: Sequence[object]
) -> Tuple[dict, Optional[Tuple[Tuple[int, ...], ...]]]:
    review = _decode_object(payload, "ownershipReview")
    _exact_fields(review, _OWNERSHIP_REVIEW_FIELDS, "ownershipReview")
    _fixed(review["version"], OWNERSHIP_REVIEW_VERSION, "ownershipReview.version")
    if _hash(review["packetSHA256"], "ownershipReview.packetSHA256") != packet_digest:
        _refuse("packet_binding_mismatch", "ownershipReview.packetSHA256",
                "review does not bind the full ownership packet")
    _hash(review["reviewerIDHash"], "ownershipReview.reviewerIDHash")
    if review["blindAttestation"] is not True:
        _refuse("invalid_blind_attestation", "ownershipReview.blindAttestation", "must be true")
    outcome = review["outcome"]
    if outcome == "partitioned":
        if any(not stroke.points for stroke in strokes):
            _refuse("nonseparable_empty_stroke", "ownershipReview.originalIndexGroups",
                    "a source containing an empty prepared stroke can only be unresolved")
        groups = _canonical_partition(review["originalIndexGroups"], len(strokes),
                                      "ownershipReview.originalIndexGroups")
        if review["originalIndexGroups"] != [list(group) for group in groups]:
            _refuse("noncanonical_partition", "ownershipReview.originalIndexGroups",
                    "inner and outer groups must be in canonical source order")
        return review, groups
    if outcome == "unresolved" and review["originalIndexGroups"] is None:
        return review, None
    _refuse("invalid_review_outcome", "ownershipReview",
            "outcome and originalIndexGroups are inconsistent")


def _decode_identity_packet(payload: bytes) -> Tuple[dict, Tuple[object, ...]]:
    packet = _decode_object(payload, "identityPacket")
    _exact_fields(packet, _IDENTITY_PACKET_FIELDS, "identityPacket")
    _fixed(packet["version"], IDENTITY_PACKET_VERSION, "identityPacket.version")
    _fixed(packet["artifactKind"], ARTIFACT_KIND, "identityPacket.artifactKind")
    _hash(packet["sourcePacketSHA256"], "identityPacket.sourcePacketSHA256")
    _hash(packet["ownershipReceiptSHA256"], "identityPacket.ownershipReceiptSHA256")
    indexes = _strict_index_group(packet["originalStrokeIndexes"], "identityPacket.originalStrokeIndexes")
    trajectory, strokes = _decode_source(canonical_json_bytes(packet["trajectoryPacket"]),
                                         "identityPacket.trajectoryPacket")
    _validate_annotation_strokes(
        strokes, "identityPacket.trajectoryPacket.strokes", allow_empty=False
    )
    if len(indexes) != len(strokes):
        _refuse("group_binding_mismatch", "identityPacket.originalStrokeIndexes",
                "must contain exactly one original index per encoded stroke")
    if trajectory != packet["trajectoryPacket"]:
        _refuse("trajectory_binding_mismatch", "identityPacket.trajectoryPacket",
                "nested trajectory changed during strict decoding")
    return packet, strokes


def _decode_identity_review(payload: bytes, packet_digest: str) -> Tuple[dict, Tuple[str, Optional[str]]]:
    review = _decode_object(payload, "identityReview")
    _exact_fields(review, _IDENTITY_REVIEW_FIELDS, "identityReview")
    _fixed(review["version"], IDENTITY_REVIEW_VERSION, "identityReview.version")
    if _hash(review["packetSHA256"], "identityReview.packetSHA256") != packet_digest:
        _refuse("packet_binding_mismatch", "identityReview.packetSHA256",
                "review does not bind the full identity packet")
    _hash(review["reviewerIDHash"], "identityReview.reviewerIDHash")
    if review["blindAttestation"] is not True:
        _refuse("invalid_blind_attestation", "identityReview.blindAttestation", "must be true")
    symbol = _identity_symbol(review["outcome"], review["symbol"], "identityReview")
    return review, (review["outcome"], symbol)


def _identity_symbol(outcome: object, symbol: object, path: str) -> Optional[str]:
    if outcome not in ("symbol", "human-ambiguous", "no-read"):
        _refuse("invalid_review_outcome", f"{path}.outcome",
                "must be symbol, human-ambiguous, or no-read")
    if symbol is ...:
        symbol = None
    if outcome != "symbol":
        if symbol is not None:
            _refuse("unexpected_symbol", f"{path}.symbol",
                    "ambiguous and no-read outcomes must use null")
        return None
    if (not isinstance(symbol, str) or len(symbol) != 1 or not symbol.isprintable()
            or symbol.isspace() or unicodedata.normalize("NFC", symbol) != symbol):
        _refuse("invalid_symbol", f"{path}.symbol",
                "must be one printable NFC Unicode codepoint")
    return symbol


def _canonical_partition(
    groups: object, stroke_count: int, path: str
) -> Tuple[Tuple[int, ...], ...]:
    if isinstance(groups, (str, bytes)) or not isinstance(groups, Sequence) or not groups:
        _refuse("invalid_partition", path, "must be a nonempty array of groups")
    frozen = []
    for group_index, group in enumerate(groups):
        group_path = f"{path}[{group_index}]"
        if isinstance(group, (str, bytes)) or not isinstance(group, Sequence) or not group:
            _refuse("invalid_partition", group_path, "group must be a nonempty index array")
        indexes = []
        for index_index, index in enumerate(group):
            if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < stroke_count:
                _refuse("invalid_index", f"{group_path}[{index_index}]",
                        "must be a non-boolean in-range original stroke index")
            indexes.append(index)
        frozen.append(tuple(sorted(indexes)))
    if sorted(index for group in frozen for index in group) != list(range(stroke_count)):
        _refuse("invalid_partition", path, "must cover every original index exactly once")
    return tuple(sorted(frozen, key=lambda group: group[0]))


def _strict_index_group(value: object, path: str) -> Tuple[int, ...]:
    if not isinstance(value, list) or not value:
        _refuse("invalid_partition", path, "must be a nonempty original-index array")
    indexes = []
    for position, index in enumerate(value):
        if isinstance(index, bool) or not isinstance(index, int) or index < 0:
            _refuse("invalid_index", f"{path}[{position}]",
                    "must be a non-boolean nonnegative integer")
        indexes.append(index)
    if indexes != sorted(set(indexes)):
        _refuse("noncanonical_partition", path, "indexes must be unique and sorted")
    return tuple(indexes)


def _ownership_reviewer_ids(value: object, path: str = "ownershipReviewerIDHashes") -> Tuple[str, ...]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Sequence):
        _refuse("invalid_ownership_reviewer_hashes", path, "must be a hash array")
    hashes = tuple(_hash(item, f"{path}[{index}]") for index, item in enumerate(value))
    if len(hashes) < 2 or len(set(hashes)) != len(hashes):
        _refuse("invalid_ownership_reviewer_hashes", path,
                "must contain at least two distinct ownership reviewer hashes")
    return tuple(sorted(hashes))


def _embedded_reviews(value: object, path: str) -> Tuple[dict, dict]:
    if not isinstance(value, list) or len(value) != 2 or not all(isinstance(item, dict) for item in value):
        _refuse("invalid_embedded_reviews", path, "must contain exactly two review objects")
    return value[0], value[1]


def _embedded_adjudication(value: object, path: str) -> Optional[dict]:
    if value is not None and not isinstance(value, dict):
        _refuse("invalid_embedded_adjudication", path, "must be an object or null")
    return value


def _decode_object(payload: bytes, path: str) -> dict:
    if not isinstance(payload, bytes):
        _refuse("invalid_bytes", path, "must be canonical JSON bytes")
    try:
        text = payload.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        _refuse("invalid_utf8", path, str(error))
    value = strict_json_loads(text, path)
    try:
        encoded = canonical_json_bytes(value)
    except (TypeError, ValueError, UnicodeError) as error:
        _refuse("invalid_json_value", path, str(error))
    if encoded != payload:
        _refuse("noncanonical_json", path, "bytes do not match canonical encoding")
    return _object(value, path)


def _object(value: object, path: str) -> dict:
    if not isinstance(value, dict):
        _refuse("invalid_object", path, "must be an object")
    return value


def _exact_fields(value: Mapping[str, object], fields: set[str], path: str) -> None:
    missing = sorted(fields.difference(value))
    if missing:
        _refuse("missing_field", path, ", ".join(missing))
    unknown = sorted(set(value).difference(fields))
    if unknown:
        _refuse("unknown_field", path, ", ".join(unknown))


def _fixed(value: object, expected: str, path: str) -> str:
    if value != expected or not isinstance(value, str):
        _refuse("fixed_value_mismatch", path, f"expected {expected}")
    return value


def _hash(value: object, path: str) -> str:
    if not isinstance(value, str) or _HEX_64.fullmatch(value) is None:
        _refuse("invalid_sha256", path, "must be 64 lowercase hexadecimal characters")
    return value


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _refuse(code: str, path: str, detail: str):
    raise ContractError(code, path, detail)

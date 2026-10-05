"""Research-only join of frozen ML hypotheses and independently frozen ink reviews.

No inference, training, answer-aware grouping, chord parser or profile mutation
runs here. Groups are joined by exact original source indexes, never by labels,
position or intended chord order. Every submitted query remains in the report;
unresolved human evidence is explicit, not a correct read or a silently dropped
sample. Metadata commitments do not authenticate writers, consent, sessions,
blindness, temporal ordering or eligibility for a new-writer quality claim.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence, Tuple

from ..contracts import canonical_json_bytes, strict_json_loads
from ..errors import ContractError
from ..schema import CHART_STYLES
from . import blind_ink_annotation as annotation


ARTIFACT_KIND = "engineering-only-blind-evaluation-v1"
PREDICTION_VERSION = "blind-ink-prediction-freeze-v1"
REPORT_VERSION = "blind-ink-paired-evaluation-v1"
_HEX = re.compile(r"^[0-9a-f]{64}$")
_PREDICTION_FIELDS = {
    "version", "artifactKind", "sourcePacketSHA256", "ownershipReceiptSHA256",
    "sourceStrokeCount", "encoderIdentity", "profileSHA256", "runtimeSHA256",
    "codeSHA256", "automatic", "supplied",
}
_META_FIELDS = {
    "writerIDHash", "querySessionIDHash", "supportSessionIDHashes", "chartStyle",
    "evidenceClass",
}
_COUNTERS = (
    "queries", "ownershipResolvedQueries", "ownershipUnresolvedQueries",
    "automaticExactOwnershipQueries", "automaticInvalidInkQueries",
    "suppliedInvalidInkQueries", "resolvedGlyphs", "unresolvedGlyphs",
    "conditionalSharedCorrect", "conditionalPersonalCorrect",
    "conditionalSharedNoRead", "conditionalPersonalNoRead", "personalGains",
    "personalHarms", "bothCorrect", "bothWrong", "automaticMatchedOwners",
    "automaticResolvedMatchedOwners", "automaticSharedCorrect",
    "automaticPersonalCorrect",
)


@dataclass(frozen=True)
class QueryEvidence:
    prediction: bytes
    ownership_packet: bytes
    ownership_receipt: bytes
    identity_artifacts: Sequence[Tuple[bytes, bytes]]
    metadata: Mapping[str, object]


def evaluate_query(query: QueryEvidence) -> dict:
    """Validate exact bindings and join hypotheses only after their freeze."""
    if not isinstance(query, QueryEvidence):
        _refuse("invalid_query", "query", "require explicit QueryEvidence")
    if not isinstance(query.metadata, Mapping):
        _refuse("invalid_metadata", "metadata", "require exact metadata object")
    if (not isinstance(query.identity_artifacts, (list, tuple))
            or len(query.identity_artifacts) > 256
            or any(not isinstance(pair, (list, tuple)) or len(pair) != 2
                   or any(not isinstance(value, bytes) for value in pair)
                   for pair in query.identity_artifacts)):
        _refuse("invalid_identity_artifacts", "identityArtifacts", "require bounded packet/freeze byte pairs")
    owner, strokes = annotation.validate_ownership_packet(query.ownership_packet)
    receipt = annotation.validate_ownership_freeze(
        query.ownership_packet, query.ownership_receipt
    )
    prediction = _object_bytes(query.prediction, "prediction")
    _fields(prediction, _PREDICTION_FIELDS, "prediction")
    if prediction["version"] != PREDICTION_VERSION or prediction["artifactKind"] != ARTIFACT_KIND:
        _refuse("wrong_version", "prediction", "unsupported prediction freeze")
    for key in ("sourcePacketSHA256", "ownershipReceiptSHA256", "profileSHA256",
                "runtimeSHA256", "codeSHA256"):
        _hash(prediction[key], "prediction." + key)
    if (prediction["sourcePacketSHA256"] != owner["sourcePacketSHA256"]
            or prediction["ownershipReceiptSHA256"] != _digest(query.ownership_receipt)):
        _refuse("prediction_binding_mismatch", "prediction", "source/ownership freeze differs")
    count = prediction["sourceStrokeCount"]
    if isinstance(count, bool) or not isinstance(count, int) or count != len(strokes):
        _refuse("source_count_mismatch", "prediction.sourceStrokeCount", "must equal original source array")
    encoder = prediction["encoderIdentity"]
    if not isinstance(encoder, str) or not encoder.strip() or len(encoder) > 512:
        _refuse("invalid_encoder_identity", "prediction.encoderIdentity", "missing or oversized identity")
    automatic = _arm(prediction["automatic"], count, "prediction.automatic")
    resolved = receipt["outcome"] == "partitioned"
    if resolved:
        supplied = _arm(prediction["supplied"], count, "prediction.supplied")
        owners = [tuple(group) for group in receipt["originalIndexGroups"]]
        if supplied["outcome"] == "read" and set(supplied["byIndexes"]) != set(owners):
            _refuse("supplied_ownership_mismatch", "prediction.supplied", "must equal frozen original owners")
    else:
        if prediction["supplied"] is not None:
            _refuse("unresolved_supplied_arm", "prediction.supplied", "unresolved ownership cannot supply guessed owners")
        supplied, owners = None, []

    meta = dict(query.metadata)
    _fields(meta, _META_FIELDS, "metadata")
    for key in ("writerIDHash", "querySessionIDHash"):
        _hash(meta[key], "metadata." + key)
    if meta["writerIDHash"] != receipt["writerIDHash"]:
        _refuse("writer_binding_mismatch", "metadata.writerIDHash", "must equal reviewed source writer")
    support = meta["supportSessionIDHashes"]
    if not isinstance(support, list) or len(support) > 256:
        _refuse("invalid_support_sessions", "metadata.supportSessionIDHashes", "must be bounded array")
    for value in support:
        _hash(value, "metadata.supportSessionIDHashes")
    if len(set(support)) != len(support) or meta["querySessionIDHash"] in support:
        _refuse("support_query_overlap", "metadata.supportSessionIDHashes", "support must be unique and separate from query session")
    meta["supportSessionIDHashes"] = sorted(support)
    if meta["chartStyle"] not in CHART_STYLES:
        _refuse("invalid_chart_style", "metadata.chartStyle", "must name either supported chart style")
    if meta["evidenceClass"] not in ("synthetic-contract-test", "development-capture"):
        _refuse("invalid_evidence_class", "metadata.evidenceClass", "this tool is not a sealed evaluation gate")

    identities = {}
    expected_packets = annotation.make_identity_packets(
        query.ownership_packet, query.ownership_receipt
    ) if resolved else ()
    expected_by_hash = {_digest(packet): packet for packet in expected_packets}
    for packet, freeze in query.identity_artifacts:
        digest = _digest(packet)
        if digest not in expected_by_hash or packet != expected_by_hash[digest]:
            _refuse("identity_binding_mismatch", "identityArtifacts", "not an exact isolated source owner")
        identity = annotation.validate_identity_freeze(
            packet, freeze, query.ownership_packet, query.ownership_receipt
        )
        indexes = tuple(identity["originalStrokeIndexes"])
        if indexes in identities:
            _refuse("duplicate_identity", "identityArtifacts", "one identity freeze per original owner")
        identities[indexes] = (identity, _digest(packet), _digest(freeze))
    if set(identities) != set(owners):
        _refuse("incomplete_identity_evidence", "identityArtifacts", "retain a freeze for every owner, including ambiguous/no-read")

    counts = {name: 0 for name in _COUNTERS}
    counts["queries"] = 1
    counts["ownershipResolvedQueries" if resolved else "ownershipUnresolvedQueries"] = 1
    counts["automaticInvalidInkQueries"] = int(automatic["outcome"] == "invalid-ink")
    counts["suppliedInvalidInkQueries"] = int(supplied is not None and supplied["outcome"] == "invalid-ink")
    exact = None if not resolved else (
        automatic["outcome"] == "read" and set(automatic["byIndexes"]) == set(owners)
    )
    counts["automaticExactOwnershipQueries"] = int(exact is True)
    rows = []
    for indexes in owners:
        identity, packet_hash, freeze_hash = identities[indexes]
        symbol = identity["symbol"] if identity["outcome"] == "symbol" else None
        conditional = supplied["byIndexes"].get(indexes)
        matched = automatic["byIndexes"].get(indexes)
        shared = conditional["sharedTop1"] if conditional else None
        personal = conditional["personalTop1"] if conditional else None
        shared_correct = None if symbol is None else shared == symbol
        personal_correct = None if symbol is None else personal == symbol
        counts["automaticMatchedOwners"] += int(matched is not None)
        if symbol is None:
            counts["unresolvedGlyphs"] += 1
        else:
            counts["resolvedGlyphs"] += 1
            counts["conditionalSharedCorrect"] += int(shared_correct)
            counts["conditionalPersonalCorrect"] += int(personal_correct)
            counts["conditionalSharedNoRead"] += int(shared is None)
            counts["conditionalPersonalNoRead"] += int(personal is None)
            counts["personalGains"] += int(not shared_correct and personal_correct)
            counts["personalHarms"] += int(shared_correct and not personal_correct)
            counts["bothCorrect"] += int(shared_correct and personal_correct)
            counts["bothWrong"] += int(not shared_correct and not personal_correct)
            counts["automaticResolvedMatchedOwners"] += int(matched is not None)
            counts["automaticSharedCorrect"] += int(matched is not None and matched["sharedTop1"] == symbol)
            counts["automaticPersonalCorrect"] += int(matched is not None and matched["personalTop1"] == symbol)
        rows.append({
            "originalStrokeIndexes": list(indexes), "identityPacketSHA256": packet_hash,
            "identityReceiptSHA256": freeze_hash, "identityOutcome": identity["outcome"],
            "symbol": symbol, "sharedTop1": shared, "personalTop1": personal,
            "sharedCorrect": shared_correct, "personalCorrect": personal_correct,
            "automaticMatchedOwner": matched is not None,
            "automaticSharedTop1": matched["sharedTop1"] if matched else None,
            "automaticPersonalTop1": matched["personalTop1"] if matched else None,
        })
    return {
        "sourcePacketSHA256": owner["sourcePacketSHA256"],
        "ownershipPacketSHA256": _digest(query.ownership_packet),
        "ownershipReceiptSHA256": _digest(query.ownership_receipt),
        "predictionSHA256": _digest(query.prediction),
        "runtimeSHA256": prediction["runtimeSHA256"], "codeSHA256": prediction["codeSHA256"],
        "encoderIdentity": encoder, "profileSHA256": prediction["profileSHA256"],
        "metadata": meta, "ownershipOutcome": receipt["outcome"],
        "automaticExactOwnership": exact, "counts": counts, "glyphs": rows,
    }


def evaluate_batch(queries: Sequence[QueryEvidence]) -> bytes:
    """Return a complete count/rate report; no silent exclusions or promotion."""
    if not queries or len(queries) > 512:
        _refuse("invalid_query_count", "queries", "require 1..512 queries")
    rows = [evaluate_query(query) for query in queries]
    sources = [row["sourcePacketSHA256"] for row in rows]
    if len(set(sources)) != len(sources):
        _refuse("duplicate_source", "queries", "same exact source cannot inflate query denominators")
    runtime_keys = {(row["runtimeSHA256"], row["codeSHA256"], row["encoderIdentity"]) for row in rows}
    if len(runtime_keys) != 1:
        _refuse("mixed_runtime", "queries", "one frozen runtime/code/encoder per report")
    profiles = {}
    for row in rows:
        writer = row["metadata"]["writerIDHash"]
        key = (row["profileSHA256"], tuple(row["metadata"]["supportSessionIDHashes"]))
        if writer in profiles and profiles[writer] != key:
            _refuse("mixed_writer_profile", "queries", "one frozen profile/support set per writer in paired report")
        profiles[writer] = key
    rows.sort(key=lambda row: row["sourcePacketSHA256"])
    totals = _totals(rows)
    slices = {}
    for field in ("writerIDHash", "querySessionIDHash", "chartStyle", "evidenceClass"):
        keys = sorted({row["metadata"][field] for row in rows})
        slices[field] = {key: _totals([row for row in rows if row["metadata"][field] == key]) for key in keys}
    return canonical_json_bytes({
        "version": REPORT_VERSION, "artifactKind": ARTIFACT_KIND,
        "trainingEligible": False, "newWriterAccuracyVerified": False,
        "fullChordAccuracyMeasured": False, "metadataProvenanceVerified": False,
        "predictionChronologyVerified": False,
        "counts": totals, "rates": _rates(totals), "slices": slices, "rows": rows,
    })


def _totals(rows):
    return {name: sum(row["counts"][name] for row in rows) for name in _COUNTERS}


def _rates(counts):
    mappings = {
        "exactOwnership": ("automaticExactOwnershipQueries", "ownershipResolvedQueries"),
        "conditionalSharedIdentity": ("conditionalSharedCorrect", "resolvedGlyphs"),
        "conditionalPersonalIdentity": ("conditionalPersonalCorrect", "resolvedGlyphs"),
        "personalGain": ("personalGains", "resolvedGlyphs"),
        "personalHarm": ("personalHarms", "resolvedGlyphs"),
        "automaticSharedOverResolvedOwners": ("automaticSharedCorrect", "resolvedGlyphs"),
        "automaticPersonalOverResolvedOwners": ("automaticPersonalCorrect", "resolvedGlyphs"),
        "automaticSharedOnMatchedOwners": ("automaticSharedCorrect", "automaticResolvedMatchedOwners"),
        "automaticPersonalOnMatchedOwners": ("automaticPersonalCorrect", "automaticResolvedMatchedOwners"),
    }
    return {name: {"numerator": counts[num], "denominator": counts[den],
                   "value": counts[num] / counts[den] if counts[den] else None}
            for name, (num, den) in mappings.items()}


def _arm(value, count, path):
    if not isinstance(value, dict):
        _refuse("invalid_arm", path, "must explicitly record read or invalid-ink")
    _fields(value, {"outcome", "glyphs"}, path)
    if value["outcome"] not in ("read", "invalid-ink") or not isinstance(value["glyphs"], list):
        _refuse("invalid_arm", path, "unknown outcome or glyph array")
    if value["outcome"] == "invalid-ink":
        if value["glyphs"]:
            _refuse("partial_failed_arm", path, "invalid ink cannot retain partial hypotheses")
        return {"outcome": "invalid-ink", "byIndexes": {}}
    if not 1 <= len(value["glyphs"]) <= 16:
        _refuse("invalid_arm", path, "read requires 1..16 complete groups")
    by_indexes = {}
    for glyph in value["glyphs"]:
        if not isinstance(glyph, dict):
            _refuse("invalid_glyph", path, "glyph must be object")
        _fields(glyph, {"originalStrokeIndexes", "sharedTop1", "personalTop1"}, path)
        indexes = glyph["originalStrokeIndexes"]
        if (not isinstance(indexes, list) or not indexes
                or any(isinstance(i, bool) or not isinstance(i, int) or not 0 <= i < count for i in indexes)):
            _refuse("invalid_indexes", path, "indexes must address original source array")
        if indexes != sorted(set(indexes)):
            _refuse("invalid_indexes", path, "acquisition indexes must be sorted and unique")
        for key in ("sharedTop1", "personalTop1"):
            _symbol(glyph[key], path + "." + key)
        by_indexes[tuple(indexes)] = glyph
    if (len(by_indexes) != len(value["glyphs"])
            or sorted(i for group in by_indexes for i in group) != list(range(count))):
        _refuse("invalid_partition", path, "every original index must occur exactly once")
    return {"outcome": "read", "byIndexes": by_indexes}


def _symbol(value, path):
    if value is not None and (not isinstance(value, str) or len(value) != 1
            or not value.isprintable() or value.isspace()
            or unicodedata.normalize("NFC", value) != value):
        _refuse("invalid_symbol", path, "raw printable NFC codepoint or explicit null required")


def _object_bytes(payload, path):
    if not isinstance(payload, bytes) or len(payload) > 4 * 1024 * 1024:
        _refuse("invalid_bytes", path, "require bounded JSON bytes")
    try:
        value = strict_json_loads(payload.decode("utf-8"), path)
        canonical = canonical_json_bytes(value)
    except (ValueError, TypeError, UnicodeError) as error:
        _refuse("invalid_json", path, str(error))
    if not isinstance(value, dict) or canonical != payload:
        _refuse("noncanonical_json", path, "require canonical object bytes")
    return value


def _fields(value, expected, path):
    if set(value) != expected:
        _refuse("wrong_fields", path, "require exact versioned fields")


def _hash(value, path):
    if not isinstance(value, str) or _HEX.fullmatch(value) is None:
        _refuse("invalid_sha256", path, "require lowercase 64-hex commitment")


def _digest(value):
    return hashlib.sha256(value).hexdigest()


def _refuse(code, path, detail):
    raise ContractError(code, path, detail)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        manifest_bytes = _read(args.manifest)
        manifest = _object_bytes(manifest_bytes, "manifest")
        _fields(manifest, {"version", "queries"}, "manifest")
        if manifest["version"] != "blind-ink-evaluation-manifest-v1" or not isinstance(manifest["queries"], list) or not 1 <= len(manifest["queries"]) <= 512:
            _refuse("invalid_manifest", "manifest", "require 1..512 explicit queries")
        parent = args.manifest.resolve().parent
        queries = []
        for item in manifest["queries"]:
            if not isinstance(item, dict):
                _refuse("invalid_manifest", "queries", "require object")
            _fields(item, {"prediction", "ownershipPacket", "ownershipReceipt", "identityArtifacts", "metadata"}, "query")
            if not isinstance(item["identityArtifacts"], list) or len(item["identityArtifacts"]) > 256:
                _refuse("invalid_manifest", "identityArtifacts", "require bounded artifact array")
            identity_artifacts = []
            for identity in item["identityArtifacts"]:
                if not isinstance(identity, dict):
                    _refuse("invalid_manifest", "identityArtifacts", "require object")
                _fields(identity, {"packet", "receipt"}, "identityArtifacts")
                identity_artifacts.append((_read_path(parent, identity["packet"]), _read_path(parent, identity["receipt"])))
            queries.append(QueryEvidence(
                _read_path(parent, item["prediction"]), _read_path(parent, item["ownershipPacket"]),
                _read_path(parent, item["ownershipReceipt"]), identity_artifacts, item["metadata"],
            ))
        report = evaluate_batch(queries)
        # Exclusive directory, receipt-last; partial directory is not complete.
        args.output_dir.mkdir(mode=0o700)
        _write(args.output_dir / "paired-evaluation.json", report)
        _write(args.output_dir / "evaluation-receipt.json", canonical_json_bytes({
            "artifactKind": ARTIFACT_KIND, "manifestSHA256": _digest(manifest_bytes),
            "reportSHA256": _digest(report), "trainingEligible": False,
            "version": "blind-ink-evaluation-bundle-v1",
        }))
        print(f"Evaluated {len(queries)} research queries; no training or eligibility promotion.")
        return 0
    except (ContractError, OSError) as error:
        parser.exit(2, f"Refused: {error}\n")


def _read_path(parent, value):
    if not isinstance(value, str) or not value:
        _refuse("invalid_path", "manifest", "require explicit file path")
    return _read(parent / value)


def _read(path):
    with path.open("rb") as handle:
        value = handle.read(4 * 1024 * 1024 + 1)
    if len(value) > 4 * 1024 * 1024:
        _refuse("invalid_bytes", str(path), "artifact exceeds 4 MiB")
    return value


def _write(path, payload):
    with path.open("xb") as handle:
        path.chmod(0o600)
        handle.write(payload)


if __name__ == "__main__":
    raise SystemExit(main())

"""Extract exact visible ink from one ended local development capture.

This is a mechanical source bridge, not inference, annotation, consent, writer
verification or training intake. Private envelope/provenance files must not be
distributed with the blind reviewer HTML. No intended answer or prediction is
consulted, and the stored canonical trajectory bytes are never regenerated for
publication.
"""

import argparse
import base64
import hashlib
import json
import math
import os
import re
import struct
import uuid
from pathlib import Path
from typing import Sequence

from ..contracts import canonical_json_bytes
from ..errors import ContractError
from ..study_import import MAXIMUM_CANONICAL_PACKET_BYTE_COUNT, decode_canonical_study_packet
from .blind_ink_annotation import make_ownership_packet


MAXIMUM_JOURNAL_BYTES = 24 * 1024 * 1024
ARTIFACT_KIND = "engineering-only-local-development-capture-v1"
_CHART_STYLES = {"simpleChordSheet": "simple-chord-sheet", "rhythmSectionSheet": "rhythm-section-sheet"}
_SNAPSHOT_FIELDS = {
    "schemaVersion", "requestID", "inkRevision", "normalizedDrawingData",
    "canonicalVisibleTrajectoryData", "chordFrame", "pages", "measures",
    "visibleStrokes", "recognitionVisibleFragmentIndices", "ownership", "outcome",
}
_OWNERSHIP_FIELDS = {
    "schemaVersion", "indexSpace", "sourcePencilStrokeCount",
    "visibleFragmentSourceStrokeIndices", "barlineVisibleFragmentIndices",
    "targetGroups", "unassignedVisibleFragmentIndices",
}


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _object(value, fields=None, optional=()):
    _require(isinstance(value, dict), "object required")
    if fields is not None:
        _require(fields <= value.keys() and value.keys() <= fields | set(optional),
                 "missing or unknown source fields")
    return value


def _integer(value, maximum=(1 << 63) - 1):
    _require(type(value) is int and 0 <= value <= maximum, "invalid integer")
    return value


def _array(value, maximum=None):
    _require(isinstance(value, list) and (maximum is None or len(value) <= maximum),
             "invalid array or count")
    return value


def _identifier(value):
    _require(isinstance(value, str), "UUID required")
    parsed = str(uuid.UUID(value))
    _require(value in (parsed, parsed.upper()), "noncanonical UUID")
    return parsed


def _text(value, maximum=256):
    _require(isinstance(value, str) and 0 < len(value.encode("utf-8")) <= maximum,
             "invalid source text")
    return value


def _number(value):
    _require(type(value) in (int, float), "finite number required")
    number = float(value)
    _require(math.isfinite(number), "finite number required")
    return number


def _bits(value):
    return struct.pack(">d", _number(value)).hex()


def _timing(value):
    return {"state": "missing"} if value is None else {
        "state": "finite", "bitPattern": _bits(value)
    }


def _plain_strokes(value):
    """Compare Swift numeric InkStroke JSON to exact stored packet bitstrings."""
    result = []
    for stroke in _array(value, 512):
        _object(stroke, {"points", "bounds"}, {"creationTimeOffset"})
        bounds = _object(stroke["bounds"], {"minX", "minY", "maxX", "maxY"})
        points = []
        for point in _array(stroke["points"], 8192):
            _object(point, {"x", "y"}, {"timeOffset"})
            points.append({"x": _bits(point["x"]), "y": _bits(point["y"]),
                           "timeOffset": _timing(point.get("timeOffset"))})
        _require(points, "empty source stroke")
        result.append({"bounds": {key: _bits(value) for key, value in bounds.items()},
                       "points": points,
                       "creationTimeOffset": _timing(stroke.get("creationTimeOffset"))})
    return result


def _rect(value):
    # Foundation CGRect Codable is [[origin.x, origin.y], [width, height]].
    _require(isinstance(value, list) and len(value) == 2
             and all(isinstance(part, list) and len(part) == 2 for part in value),
             "invalid CGRect")
    x, y, width, height = [_number(item) for part in value for item in part]
    _require(width >= 0 and height >= 0 and math.isfinite(x + width)
             and math.isfinite(y + height), "invalid CGRect extent")


def _data(value, maximum):
    _require(isinstance(value, str) and len(value) <= 4 * ((maximum + 2) // 3),
             "Data exceeds byte budget")
    data = base64.b64decode(value, validate=True)
    _require(0 < len(data) <= maximum and base64.b64encode(data).decode() == value,
             "empty, oversized or noncanonical Data")
    return data


def _indexes(value, count):
    indexes = [_integer(item) for item in _array(value, count)]
    _require(indexes == sorted(set(indexes)) and all(item < count for item in indexes),
             "invalid, duplicate or unsorted original indexes")
    return indexes


def _snapshot(value):
    source = _object(value, _SNAPSHOT_FIELDS, {"pageBounds"})
    _require(_integer(source["schemaVersion"]) == 1, "unsupported source schema")
    _identifier(source["requestID"])
    _integer(source["inkRevision"], (1 << 64) - 1)
    drawing = _data(source["normalizedDrawingData"], 1_000_000)
    trajectory = _data(source["canonicalVisibleTrajectoryData"], MAXIMUM_CANONICAL_PACKET_BYTE_COUNT)
    decode_canonical_study_packet(trajectory)  # Existing strict canonical/budget contract.
    make_ownership_packet(trajectory)  # Existing fail-closed reviewer geometry contract.
    packet = json.loads(trajectory)
    _require(_plain_strokes(source["visibleStrokes"]) == packet["strokes"],
             "canonical trajectory disagrees with saved visible strokes")
    _rect(source["chordFrame"])
    if source.get("pageBounds") is not None:
        _rect(source["pageBounds"])
    page_indexes = []
    for page in _array(source["pages"]):
        _object(page, {"index", "frame"})
        page_indexes.append(_integer(page["index"]))
        _rect(page["frame"])
    _require(page_indexes == sorted(set(page_indexes)), "invalid page indexes")
    measure_ids = []
    for measure in _array(source["measures"]):
        _object(measure, {"measureID", "index", "chordWritingFrame"}, {"targetMeasureID"})
        measure_ids.append(_identifier(measure["measureID"]))
        if measure.get("targetMeasureID") is not None:
            _identifier(measure["targetMeasureID"])
        _integer(measure["index"])
        _rect(measure["chordWritingFrame"])
    _require(len(set(measure_ids)) == len(measure_ids), "duplicate visual measure IDs")
    _require(source["outcome"] in ("ready", "noVisibleStrokes", "noRecognitionData",
             "skippedWeakBatchTargets", "skippedSingleTarget", "noTarget"), "unsupported source outcome")
    ownership = _object(source["ownership"], _OWNERSHIP_FIELDS)
    _require(_integer(ownership["schemaVersion"]) == 1
             and ownership["indexSpace"] == "visibleFragmentsBeforeBarlineFilteringV1",
             "unsupported ownership schema")
    count = len(packet["strokes"])
    pencil_count = _integer(ownership["sourcePencilStrokeCount"])
    mapping = [_integer(item) for item in _array(ownership["visibleFragmentSourceStrokeIndices"], count)]
    _require(len(mapping) == count and all(item < pencil_count for item in mapping),
             "invalid source-to-visible mapping")
    barlines = _indexes(ownership["barlineVisibleFragmentIndices"], count)
    claimed = set(barlines)
    groups = _array(ownership["targetGroups"], 64)
    _require((source["outcome"] == "ready") == bool(groups), "source outcome/target count mismatch")
    for ordinal, group in enumerate(groups):
        _object(group, {"targetOrdinal", "visibleFragmentIndices"})
        indexes = _indexes(group["visibleFragmentIndices"], count)
        _require(_integer(group["targetOrdinal"]) == ordinal and indexes
                 and claimed.isdisjoint(indexes), "invalid target partition or order")
        claimed.update(indexes)
    unassigned = _indexes(ownership["unassignedVisibleFragmentIndices"], count)
    _require(unassigned == sorted(set(range(count)) - claimed),
             "ownership must retain every unassigned visible fragment")
    recognition = _indexes(source["recognitionVisibleFragmentIndices"], count)
    _require(recognition == sorted(set(range(count)) - set(barlines)),
             "recognition map must be exactly visible ink minus retained barlines")
    return trajectory, drawing, packet, groups


def _profile_counts(profile, lineage, run_id):
    profile = _object(profile)
    _require(_integer(profile.get("version")) == 1, "unsupported profile version")
    _identifier(profile.get("revision"))
    _identifier(profile.get("generation"))
    _require(type(profile.get("isEnabled")) is bool
             and type(profile.get("learnsFromReviews")) is bool, "invalid frozen profile flags")
    example_ids, kinds, examples = [], [], []
    for example in _array(profile.get("examples"), 192):
        example = _object(example)
        example_ids.append(_identifier(example.get("id")))
        kinds.append(example.get("kind"))
        examples.append(example)
    _require(len(set(example_ids)) == len(example_ids)
             and all(kind in ("glyph", "chord") for kind in kinds), "invalid support examples")
    lineage = _object(lineage)
    _require(_identifier(lineage.get("querySessionID")) == run_id, "profile query-session mismatch")
    lists = {}
    for name in ("trackedExampleIDs", "untrackedExampleIDs", "mismatchedExampleIDs",
                 "overlapExampleIDs", "observedSupportSessionIDs"):
        identifiers = [_identifier(item) for item in _array(lineage.get(name), 192)]
        _require(len(set(identifiers)) == len(identifiers), "duplicate support lineage IDs")
        lists[name] = set(identifiers)
    partition = [lists[name] for name in ("trackedExampleIDs", "untrackedExampleIDs", "mismatchedExampleIDs")]
    _require(set.union(*partition) == set(example_ids)
             and sum(map(len, partition)) == len(example_ids)
             and lists["overlapExampleIDs"] <= lists["trackedExampleIDs"],
             "support lineage counts or partition mismatch")
    observed = {name: set() for name in lists}
    for example_id, example in zip(example_ids, examples):
        provenance = example.get("learningProvenance")
        if provenance is None:
            observed["untrackedExampleIDs"].add(example_id)
            continue
        try:
            _object(provenance, {"version", "context", "taughtAt", "originalInputSHA256", "storedInputSHA256"})
            _require(_integer(provenance["version"]) == 1, "unsupported lesson provenance")
            context = _object(provenance["context"], {"sessionID", "captureID", "capturedAt", "origin"}, {"chartStyle"})
            session_id = _identifier(context["sessionID"])
            _identifier(context["captureID"])
            _number(context["capturedAt"])
            _number(provenance["taughtAt"])
            _require(context["origin"] in ("setup", "practice", "chartReview", "savedEvaluation", "selectedSavedSymbol")
                     and context.get("chartStyle") in (None, "simple-chord-sheet", "rhythm-section-sheet"),
                     "invalid lesson context")
            _require(all(isinstance(provenance[name], str) and re.fullmatch(r"[0-9a-f]{64}", provenance[name])
                         for name in ("originalInputSHA256", "storedInputSHA256")), "invalid lesson digest")
            stored_packet = {"formatVersion": "ink-trajectory-packet-v1",
                             "coordinateSpace": "transformed-prepared-drawing",
                             "strokes": _plain_strokes(example.get("strokes"))}
            _require(hashlib.sha256(canonical_json_bytes(stored_packet)).hexdigest() == provenance["storedInputSHA256"],
                     "stored lesson input mismatch")
        except (ValueError, OverflowError):
            observed["mismatchedExampleIDs"].add(example_id)
            continue
        observed["trackedExampleIDs"].add(example_id)
        observed["observedSupportSessionIDs"].add(session_id)
        if session_id == run_id:
            observed["overlapExampleIDs"].add(example_id)
    _require(observed == lists, "support session, overlap or stored-input lineage mismatch")
    complete = not (lists["untrackedExampleIDs"] or lists["mismatchedExampleIDs"])
    _require(lineage.get("isMetadataComplete") is complete
             and lineage.get("areObservedSupportSessionsDisjoint") is (complete and not lists["overlapExampleIDs"]),
             "support lineage flags mismatch")
    return {"glyphSupportExamples": kinds.count("glyph"), "chordSupportExamples": kinds.count("chord"),
            "observedSupportSessions": len(lists["observedSupportSessionIDs"])}


def _load_journal(data):
    # Preserve JSON's integer spelling -0 as a Double sign bit for comparisons.
    # The shared loader cannot configure parse_int; retain its strict rejection
    # of duplicate keys/nonfinite constants here without silently losing -0.
    def pairs(items):
        result = {}
        for key, value in items:
            _require(key not in result, "duplicate JSON key")
            result[key] = value
        return result

    def nonfinite(_):
        raise ValueError("nonfinite JSON constant")

    return json.loads(data.decode("utf-8"), object_pairs_hook=pairs, parse_constant=nonfinite,
                      parse_int=lambda value: -0.0 if value == "-0" else int(value))


def prepare_capture_artifacts(journal_data: bytes, run_id: str) -> dict:
    """Validate an immutable journal read completely before producing artifacts."""
    _require(0 < len(journal_data) <= MAXIMUM_JOURNAL_BYTES, "journal byte budget exceeded")
    requested_id = _identifier(run_id)
    journal = _object(_load_journal(journal_data), {"version", "runs"})
    _require(_integer(journal["version"]) == 1, "unsupported journal version")
    runs = _array(journal["runs"], 16)
    run_ids = [_identifier(_object(run).get("id")) for run in runs]
    _require(len(set(run_ids)) == len(run_ids) and requested_id in run_ids, "duplicate or missing run ID")
    run = runs[run_ids.index(requested_id)]
    _require(run.get("sourceCaptureState") == "complete"
             and run.get("status") in ("cancelled", "labeling", "complete"),
             "capture is pending, legacy, or not ended")
    trajectory, drawing, packet, groups = _snapshot(run.get("sourceSnapshot"))
    source = run["sourceSnapshot"]
    request_id = _identifier(run.get("sourceRequestID"))
    revision = _integer(run.get("sourceInkRevision"), (1 << 64) - 1)
    _require(request_id == _identifier(source["requestID"]) and revision == source["inkRevision"],
             "source snapshot request or revision mismatch")
    records = _array(run.get("records"), 64)
    _require(len(records) == len(groups), "complete capture has missing or extra targets")
    for record, group in zip(records, groups):
        record = _object(record)
        _require(_identifier(record.get("sourceRequestID")) == request_id
                 and _integer(record.get("targetOrdinal")) == group["targetOrdinal"],
                 "record request or target order mismatch")
        exact_group = [packet["strokes"][index] for index in group["visibleFragmentIndices"]]
        _require(_plain_strokes(record.get("recognitionStrokes")) == exact_group,
                 "record exact recognition input disagrees with source ownership")
    _require(isinstance(run.get("style"), str) and run["style"] in _CHART_STYLES, "unsupported chart style")
    _require(run.get("phase") in ("beforeCorrections", "afterCorrections"), "unsupported capture phase")
    _identifier(run.get("chartID"))
    _text(run.get("pipeline"))
    counts = _profile_counts(run.get("profile"), run.get("profileLineage"), requested_id)
    counts.update({"sourcePencilStrokes": source["ownership"]["sourcePencilStrokeCount"],
                   "visibleStrokes": len(packet["strokes"]), "recognitionStrokes": len(source["recognitionVisibleFragmentIndices"]),
                   "barlineFragments": len(source["ownership"]["barlineVisibleFragmentIndices"]),
                   "unassignedFragments": len(source["ownership"]["unassignedVisibleFragmentIndices"]),
                   "targets": len(groups), "records": len(records)})
    # Deliberate allow-list: never copy expected counts, intended answers,
    # recognizer hypotheses, target ordinals from a score report, or corrections.
    envelope = {"version": "blind-ink-capture-source-envelope-v1", "artifactKind": ARTIFACT_KIND,
                "trainingEligible": False, "runID": run["id"], "chartID": run["chartID"],
                "capturedChartStyle": run["style"], "chartStyle": _CHART_STYLES[run["style"]],
                "phase": run["phase"], "pipeline": run["pipeline"],
                "sourceSnapshot": source, "frozenProfile": run["profile"], "profileLineage": run["profileLineage"]}
    envelope_data = canonical_json_bytes(envelope)
    provenance = {"version": "blind-ink-capture-provenance-v1", "artifactKind": ARTIFACT_KIND,
                  "evidenceClass": "one-writer-local-development", "trainingEligible": False,
                  "writerIdentityVerified": False, "consentVerified": False,
                  "rawOriginalDrawingArchived": False, "recognitionAccuracyMeasured": False,
                  "runID": run["id"], "chartStyle": _CHART_STYLES[run["style"]],
                  "requestID": source["requestID"], "inkRevision": revision,
                  "sourcePacketSHA256": hashlib.sha256(trajectory).hexdigest(),
                  "sourcePacketByteCount": len(trajectory), "journalSHA256": hashlib.sha256(journal_data).hexdigest(),
                  "normalizedDrawingSHA256": hashlib.sha256(drawing).hexdigest(),
                  "privateEnvelopeSHA256": hashlib.sha256(envelope_data).hexdigest(),
                  "frozenProfileJSONProjectionSHA256": hashlib.sha256(canonical_json_bytes(run["profile"])).hexdigest(),
                  "counts": counts,
                  "assuranceNote": "Mechanical local bindings only. Drawing is color-normalized recognition input, not raw original archival. Profile digest is a Python canonical JSON projection, not a Swift model-profile commitment. Keep envelope and provenance private; distribute only separately prepared blind reviewer HTML."}
    return {"trajectory.json": trajectory, "source-envelope.json": envelope_data,
            "capture-provenance.json": canonical_json_bytes(provenance)}


def extract_capture(journal_path: Path, run_id: str, output_dir: Path) -> dict:
    with Path(journal_path).open("rb") as handle:
        journal_data = handle.read(MAXIMUM_JOURNAL_BYTES + 1)
    artifacts = prepare_capture_artifacts(journal_data, run_id)
    receipt = {"version": "blind-ink-capture-bundle-v1", "artifactKind": ARTIFACT_KIND,
               "trainingEligible": False,
               "artifacts": {name: hashlib.sha256(data).hexdigest() for name, data in artifacts.items()}}
    # All source checks precede any writes. An exclusive, private directory and
    # receipt-last publication preserve partial I/O failure as an incomplete job.
    directory = Path(output_dir)
    directory.mkdir(mode=0o700)
    for name, data in {**artifacts, "prepared-receipt.json": canonical_json_bytes(receipt)}.items():
        descriptor = os.open(directory / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
    return json.loads(artifacts["capture-provenance.json"])


def entrypoint(argv: Sequence[str] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal-json", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        provenance = extract_capture(args.journal_json, args.run_id, args.output_dir)
    except (ContractError, ValueError, OSError, OverflowError, RecursionError) as error:
        print(json.dumps({"status": "rejected-capture-source", "error": str(error)}, sort_keys=True))
        return 1
    print(json.dumps({"status": "extracted-local-development-source", "trainingEligible": False,
                      "sourcePacketSHA256": provenance["sourcePacketSHA256"],
                      "sourcePacketByteCount": provenance["sourcePacketByteCount"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(entrypoint())

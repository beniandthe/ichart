"""Post-freeze exact chord scoring. No parser, model, inference, or teaching.

The request pins every input byte and two explicit runs. User labels enter only
after a source/profile/native-output mutation audit. Automatic glyph ownership
is unverified, so results are diagnostic target counts, never percentages or
glyph-accuracy claims. Saved intended strings are compared verbatim.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import uuid


REQUEST_VERSION = "fresh-symbol-transfer-score-request-v1"
REPORT_VERSION = "fresh-symbol-transfer-score-v1"
PREDICTION_VERSION = "fresh-unlabeled-paired-profile-freeze-v1"
COMPOSITION_VERSION = "frozen-top-choice-composition-v1"
ML_METHODS = ("sharedML", "original34", "original37", "anchored34", "anchored37")
METHODS = ("nativeBaseline", "nativeProfile37") + ML_METHODS
FILES = {
    "prediction": 64 * 1_024 * 1_024, "composition": 2 * 1_024 * 1_024,
    "sourceJournal": 24_000_000, "annotatedJournal": 24_000_000,
    "oldProfile": 2_000_000, "newProfile": 2_000_000, "currentProfile": 2_000_000,
}
STYLES = {"simpleChordSheet", "rhythmSectionSheet"}
RUN_MUTABLE = {"status", "finishedAt", "expectedChordCount", "inkFeltSlow", "unexpectedChartChanges"}
RECORD_MUTABLE = {"intended", "groupingIssue"}
_HEX = re.compile(r"^[0-9a-f]{64}$")


class ScoringError(ValueError):
    """A refused join; messages contain field names, never private labels."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ScoringError(message)


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value: object) -> bytes:
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
                          allow_nan=False).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise ScoringError("non-finite or unsupported JSON value") from error


def _decode(data: bytes, maximum: int, field: str) -> dict:
    _require(isinstance(data, bytes) and len(data) <= maximum, field + ": byte budget exceeded")
    def pairs(items: list) -> dict:
        result = {}
        for key, value in items:
            _require(key not in result, field + ": duplicate JSON key")
            result[key] = value
        return result
    try:
        value = json.loads(data, object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(ScoringError(field + ": non-finite JSON")))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ScoringError(field + ": invalid JSON") from error
    _require(isinstance(value, dict), field + ": object required")
    canonical(value)  # Includes overflowed numeric literals such as 1e999.
    return value


def _same(left: object, right: object) -> bool:
    return canonical(left) == canonical(right)


def _uuid(value: object, field: str) -> str:
    _require(isinstance(value, str), field + ": UUID required")
    try:
        uuid.UUID(value)
    except ValueError as error:
        raise ScoringError(field + ": invalid UUID") from error
    return value


def _label(value: object, field: str, *, nullable: bool = True) -> str | None:
    if nullable and value is None:
        return None
    _require(isinstance(value, str) and 0 < len(value) <= 128 and value == value.strip()
             and not any(ord(character) < 32 for character in value), field + ": invalid saved label")
    return value


def _native_read(value: object, field: str) -> str | None:
    # An empty native string is a present wrong read, not a rescued no-read.
    _require(value is None or isinstance(value, str) and len(value) <= 128,
             field + ": optional bounded string required")
    return value


def _keyed(items: object, field: str, key: str = "id", maximum: int = 64) -> dict:
    _require(isinstance(items, list) and len(items) <= maximum, field + ": bounded array required")
    result = {}
    for item in items:
        _require(isinstance(item, dict), field + ": object required")
        identifier = _uuid(item.get(key), field + "." + key)
        _require(identifier not in result, field + ": duplicate identifier")
        result[identifier] = item
    return result


def validate_request(data: bytes) -> dict:
    request = _decode(data, 32_768, "request")
    fields = {"version", "runs", "outputPath"} | {key + suffix for key in FILES for suffix in ("Path", "SHA256")}
    _require(set(request) == fields and request["version"] == REQUEST_VERSION, "request: wrong schema/version")
    for key in FILES:
        _require(isinstance(request[key + "Path"], str) and Path(request[key + "Path"]).is_absolute(), key + ": absolute path required")
        _require(isinstance(request[key + "SHA256"], str) and _HEX.fullmatch(request[key + "SHA256"]) is not None,
                 key + ": invalid SHA-256")
    _require(isinstance(request["outputPath"], str) and Path(request["outputPath"]).is_absolute(), "output: absolute path required")
    runs = request["runs"]
    _require(isinstance(runs, list) and len(runs) == 2, "request: exactly two explicit runs required")
    for run in runs:
        _require(isinstance(run, dict) and set(run) == {"runID", "style", "expectedChordCount"}, "request.run: wrong fields")
        _uuid(run["runID"], "request.runID")
        _require(run["style"] in STYLES and type(run["expectedChordCount"]) is int and run["expectedChordCount"] == 6,
                 "request.run: fixed style/six-written contract required")
    _require(len({run["runID"] for run in runs}) == 2 and {run["style"] for run in runs} == STYLES,
             "request: distinct runs and both chart styles required")
    return request


def _audit_annotations(source: dict, annotated: dict, selected: dict, newer: dict) -> dict:
    old_runs = _keyed(source.get("runs"), "source.runs", maximum=32)
    new_runs = _keyed(annotated.get("runs"), "annotated.runs", maximum=32)
    _require(source.get("version") == 1 and annotated.get("version") == 1, "journal: wrong version")
    _require(_same({key: value for key, value in source.items() if key != "runs"},
                   {key: value for key, value in annotated.items() if key != "runs"})
             and list(old_runs) == list(new_runs), "journal: non-annotation mutation")
    _require(set(selected).issubset(old_runs), "journal: requested run missing")
    for identifier, before in old_runs.items():
        after = new_runs[identifier]
        if identifier not in selected:
            _require(_same(before, after), "journal: historical run changed")
            continue
        _require(before.get("status") == "labeling" and before.get("phase") == "afterCorrections"
                 and before.get("finishedAt") is None and before.get("expectedChordCount") is None,
                 "source: not a stopped unannotated run")
        _require(before.get("sourceCaptureState") == "complete" and _same(before.get("profile"), newer),
                 "source: incomplete source or changed frozen profile")
        _require(before.get("style") == selected[identifier]["style"], "source: style mismatch")
        _require(after.get("status") == "complete" and type(after.get("finishedAt")) in (int, float)
                 and math.isfinite(after["finishedAt"]), "annotated: completed run required")
        _require(type(after.get("expectedChordCount")) is int
                 and after["expectedChordCount"] == selected[identifier]["expectedChordCount"], "annotated: written count differs")
        _require(type(after.get("inkFeltSlow")) is bool and type(after.get("unexpectedChartChanges")) is bool,
                 "annotated: experience flags required")
        _require(before.get("teachingReceipt") is None and after.get("teachingReceipt") is None, "journal: query was taught")
        omit = RUN_MUTABLE | {"records"}
        _require(_same({key: value for key, value in before.items() if key not in omit},
                       {key: value for key, value in after.items() if key not in omit}), "run: forbidden mutation")
        old_records = _keyed(before.get("records"), "source.records")
        new_records = _keyed(after.get("records"), "annotated.records")
        _require(list(old_records) == list(new_records), "records: identity/order changed")
        for record_id, original in old_records.items():
            labeled = new_records[record_id]
            _require(original.get("intended") is None and original.get("groupingIssue") is False
                     and original.get("taught") is False and labeled.get("taught") is False, "record: query annotation/teaching mismatch")
            _require(_same({key: value for key, value in original.items() if key not in RECORD_MUTABLE},
                           {key: value for key, value in labeled.items() if key not in RECORD_MUTABLE}), "record: forbidden mutation")
            _require(type(labeled.get("groupingIssue")) is bool, "record: grouping flag required")
            _label(labeled.get("intended"), "record.intended", nullable=labeled["groupingIssue"])
    return new_runs


def _audit_freeze(prediction: dict, composition: dict, source: dict, selected: dict,
                  request: dict) -> dict:
    _require(prediction.get("version") == PREDICTION_VERSION and prediction.get("sourceJournalSHA256") == request["sourceJournalSHA256"],
             "prediction: wrong source/version")
    for prefix, key in (("old", "oldProfile"), ("new", "newProfile")):
        _require(prediction.get(prefix + "ProfileFileSHA256") == request[key + "SHA256"], "prediction: support file mismatch")
    _require(composition.get("version") == COMPOSITION_VERSION
             and composition.get("predictionSHA256") == request["predictionSHA256"]
             and composition.get("codeFileMapSHA256") == prediction.get("codeFileMapSHA256")
             and composition.get("sourceJournalSHA256") == prediction.get("sourceJournalSHA256"),
             "composition: wrong prediction/code/source binding")
    for flag in ("profileChanged", "inferenceRerun", "accuracyMeasured"):
        _require(composition.get(flag) is False, "composition: unsupported execution claim")
    sources = _keyed(prediction.get("sources"), "prediction.sources", key="runID", maximum=2)
    _require(set(sources) == set(selected), "prediction: requested run set mismatch")
    original_runs = _keyed(source["runs"], "source.runs", maximum=32)
    expected = {}
    for run_id, item in sources.items():
        run = original_runs[run_id]
        _require(item.get("style") == run.get("style") and item.get("pipeline") == run.get("pipeline")
                 and _same(item.get("sourceSnapshot"), run.get("sourceSnapshot"))
                 and _same(item.get("profileLineage"), run.get("profileLineage")), "prediction: frozen source/lineage mismatch")
        _require(item.get("frozenProfileSHA256") == prediction.get("newProfileCanonicalSHA256"), "prediction: frozen profile binding mismatch")
        records = _keyed(run["records"], "source.records")
        groups = run["sourceSnapshot"]["ownership"]["targetGroups"]
        _require(isinstance(item.get("targets"), list) and len(item["targets"]) == len(records) == len(groups), "prediction: target count mismatch")
        ordinals = {record.get("targetOrdinal") for record in records.values()}
        _require(len(ordinals) == len(records) and all(type(value) is int and value >= 0 for value in ordinals), "source: duplicate/invalid target ordinal")
        group_map = {group.get("targetOrdinal"): group for group in groups}
        _require(set(group_map) == ordinals and len(group_map) == len(groups), "source: ownership target mismatch")
        for target in item["targets"]:
            _require(isinstance(target, dict) and target.get("recordID") in records, "prediction: unknown record")
            record = records[target["recordID"]]
            ordinal = target.get("targetOrdinal")
            _require(type(ordinal) is int and ordinal == record["targetOrdinal"], "prediction: ordinal mismatch")
            key = (run_id, record["id"], ordinal)
            _require(key not in expected, "prediction: duplicate target")
            _require(_same(target.get("childToParentVisibleFragmentIndices"), group_map[ordinal]["visibleFragmentIndices"]), "prediction: source ownership changed")
            for profile_key in ("olderProfileFreeze", "newerProfileFreeze"):
                freeze = target.get(profile_key)
                _require(isinstance(freeze, dict) and freeze.get("glyphOwnershipVerified") is False and freeze.get("supplied") is None,
                         "prediction: unsupported ownership arm")
            old = target["olderProfileFreeze"]["automatic"]
            new = target["newerProfileFreeze"]["automatic"]
            _require(old.get("outcome") == new.get("outcome")
                     and _same([g["originalStrokeIndexes"] for g in old["glyphs"]], [g["originalStrokeIndexes"] for g in new["glyphs"]])
                     and _same([g["sharedRanks"] for g in old["glyphs"]], [g["sharedRanks"] for g in new["glyphs"]]), "prediction: shared/group support mismatch")
            _require(isinstance(target.get("sourcePacketSHA256"), str)
                     and _HEX.fullmatch(target["sourcePacketSHA256"]) is not None, "prediction: invalid child source hash")
            try:
                packet = base64.b64decode(target["sourcePacketData"], validate=True)
            except (ValueError, TypeError) as error:
                raise ScoringError("prediction: invalid child source packet") from error
            _require(len(packet) <= 4 * 1_024 * 1_024 and _sha(packet) == target["sourcePacketSHA256"],
                     "prediction: child packet hash mismatch")
            expected[key] = (run["style"], target["sourcePacketSHA256"], item["sourcePacketSHA256"])
    targets = composition.get("targets")
    _require(isinstance(targets, list) and len(targets) == len(expected), "composition: incomplete target coverage")
    result = {}
    for target in targets:
        _require(isinstance(target, dict) and set(target) == {"runID", "recordID", "targetOrdinal", "style", "methods", "glyphOwnershipVerified",
                                                            "sourcePacketSHA256", "parentSourcePacketSHA256"}, "composition: wrong target fields")
        key = (target["runID"], target["recordID"], target["targetOrdinal"])
        _require(type(target["targetOrdinal"]) is int and key in expected and key not in result
                 and (target["style"], target["sourcePacketSHA256"], target["parentSourcePacketSHA256"]) == expected[key]
                 and target["glyphOwnershipVerified"] is False, "composition: duplicate/mismatched target")
        methods = target["methods"]
        _require(isinstance(methods, dict) and set(methods) == set(ML_METHODS), "composition: all five methods required")
        for method, value in methods.items():
            _label(value, "composition.methods." + method)
        result[key] = methods
    _require(set(result) == set(expected), "composition: target coverage differs")
    return result


def score(request_data: bytes, payloads: dict[str, bytes]) -> bytes:
    """Pure byte-bound join, suitable for synthetic tests and offline execution."""
    request = validate_request(request_data)
    _require(set(payloads) == set(FILES), "inputs: all seven artifacts required")
    data = {}
    for key, maximum in FILES.items():
        _require(_sha(payloads[key]) == request[key + "SHA256"], key + ": SHA-256 mismatch")
        data[key] = _decode(payloads[key], maximum, key)
    old, new = data["oldProfile"], data["newProfile"]
    _require(_same(new, data["currentProfile"]), "profile: current support changed")
    _require(len(old.get("examples", [])) == 34 and len(new.get("examples", [])) == 37
             and old.get("isEnabled") is True and new.get("isEnabled") is True,
             "profile: wrong frozen support counts/state")
    _require(_same(old["examples"], new["examples"][:34]) and _same(
        {k: v for k, v in old.items() if k not in {"examples", "revision"}},
        {k: v for k, v in new.items() if k not in {"examples", "revision"}}), "profile: previous support changed")
    _keyed(old["examples"], "oldProfile.examples", maximum=256)
    _keyed(new["examples"], "newProfile.examples", maximum=256)
    _require(all(example.get("kind") == "glyph" and example.get("source") == "explicitCorrection"
                 for example in new["examples"][34:]), "profile: additions are not explicit glyphs")
    selected = {run["runID"]: run for run in request["runs"]}
    annotated = _audit_annotations(data["sourceJournal"], data["annotatedJournal"], selected, new)
    composed = _audit_freeze(data["prediction"], data["composition"], data["sourceJournal"], selected, request)
    results = []
    pairs = (("nativeBaseline", "nativeProfile37"), ("sharedML", "original34"),
             ("sharedML", "original37"), ("sharedML", "anchored34"), ("sharedML", "anchored37"),
             ("original34", "original37"), ("anchored34", "anchored37"))
    for specification in request["runs"]:
        run = annotated[specification["runID"]]
        rows = []
        for record in run["records"]:
            methods = {"nativeBaseline": _native_read(record.get("baseline"), "record.baseline"),
                       "nativeProfile37": _native_read(record.get("personalized"), "record.personalized")}
            methods.update(composed[(run["id"], record["id"], record["targetOrdinal"])])
            reasons = (["incorrectGrouping"] if record["groupingIssue"] else [])
            if record.get("knownInk") is True: reasons.append("knownInk")
            if record.get("recognitionStrokes") is None: reasons.append("missingOriginalInput")
            rows.append({"recordID": record["id"], "targetOrdinal": record["targetOrdinal"],
                         "intended": record.get("intended"), "exclusions": reasons, "methods": methods})
        eligible = [row for row in rows if not row["exclusions"]]
        counts = {}
        missing = max(0, 6 - len(rows))
        for method in METHODS:
            correct = sum(row["methods"][method] == row["intended"] for row in eligible)
            no_reads = sum(row["methods"][method] is None for row in eligible)
            counts[method] = {"correct": correct, "wrongReads": len(eligible) - correct - no_reads,
                              "noReads": no_reads, "missingWrittenAttempts": missing}
        comparisons = []
        for reference, candidate in pairs:
            corrections = sum(row["methods"][reference] != row["intended"] and row["methods"][candidate] == row["intended"] for row in eligible)
            regressions = sum(row["methods"][reference] == row["intended"] and row["methods"][candidate] != row["intended"] for row in eligible)
            changes = [{"recordID": row["recordID"], "targetOrdinal": row["targetOrdinal"],
                        "referenceRead": row["methods"][reference], "candidateRead": row["methods"][candidate],
                        "correction": row["methods"][reference] != row["intended"] and row["methods"][candidate] == row["intended"],
                        "regression": row["methods"][reference] == row["intended"] and row["methods"][candidate] != row["intended"]}
                       for row in eligible if row["methods"][reference] != row["methods"][candidate]]
            comparisons.append({"reference": reference, "candidate": candidate,
                                "corrections": corrections, "regressions": regressions, "discordances": changes})
        ownership = run["sourceSnapshot"]["ownership"]
        results.append({"runID": run["id"], "style": run["style"], "writtenCount": 6,
                        "capturedCount": len(rows), "eligibleCount": len(eligible),
                        "missingCount": missing, "extraCapturedCount": max(0, len(rows) - 6),
                        "groupingIssueCount": sum(record["groupingIssue"] for record in run["records"]),
                        "unassignedSourceFragmentCount": len(ownership["unassignedVisibleFragmentIndices"]),
                        "barlineSourceFragmentCount": len(ownership["barlineVisibleFragmentIndices"]),
                        "glyphOwnershipVerified": False, "wholeChartPercentage": None,
                        "methods": counts, "comparisons": comparisons, "rows": rows})
    report = {"version": REPORT_VERSION, "requestSHA256": _sha(request_data),
              "inputSHA256": {key: _sha(payloads[key]) for key in FILES},
              "codeFileMapSHA256": data["prediction"]["codeFileMapSHA256"],
              "sameWriterDevelopmentOnly": True, "inferenceRerun": False,
              "trainingEligible": False, "acrossWriterAccuracyEstablished": False,
              "ownershipVerified": False, "profileChanged": False,
              "annotationIndependent": False, "predictionChronologyIndependentlyVerified": False,
              "glyphAccuracyEstablished": False, "runs": results}
    return canonical(report)


def _read(path: str, maximum: int) -> bytes:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        info = os.fstat(descriptor)
        _require(stat.S_ISREG(info.st_mode) and info.st_size <= maximum, "input: regular bounded file required")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            data = stream.read(maximum + 1)
        _require(len(data) <= maximum, "input: byte budget exceeded")
        return data
    finally:
        os.close(descriptor)


def run_request(request_path: str) -> dict:
    request_data = _read(request_path, 32_768)
    request = validate_request(request_data)
    output = Path(request["outputPath"])
    inputs = [Path(request_path)] + [Path(request[key + "Path"]) for key in FILES]
    _require(output.resolve() not in {path.resolve() for path in inputs}, "output: must not replace input")
    _require(not output.exists() and not output.is_symlink(), "output: already exists")
    payloads = {key: _read(request[key + "Path"], maximum) for key, maximum in FILES.items()}
    report = score(request_data, payloads)
    _require(_read(request_path, 32_768) == request_data and all(
        _read(request[key + "Path"], maximum) == payloads[key] for key, maximum in FILES.items()), "inputs: changed before publication")
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as stream:
            stream.write(report)
            stream.flush()
            os.fsync(descriptor)
    except BaseException:
        output.unlink(missing_ok=True)
        raise
    finally:
        os.close(descriptor)
    return {"version": REPORT_VERSION, "runs": 2, "reportSHA256": _sha(report),
            "inferenceRerun": False, "acrossWriterAccuracyEstablished": False}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", required=True)
    arguments = parser.parse_args(argv)
    try:
        metadata = run_request(arguments.request)
    except (ScoringError, OSError, KeyError, TypeError, ValueError) as error:
        parser.exit(2, "Scoring refused: " + str(error) + "\n")
    print(json.dumps(metadata, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

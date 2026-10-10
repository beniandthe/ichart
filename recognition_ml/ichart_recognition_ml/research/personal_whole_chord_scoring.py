"""Pure post-freeze whole-chord paired arithmetic, never model inference."""
from __future__ import annotations

from collections import Counter
import re

from ..chord_notation import parse_canonical_chord_label, require_canonical_chord_label
from .personal_whole_chord_source import ACQUISITION_ORDERS, canonical_chord_specs

VERSION = "personal-whole-chord-paired-score-v1"
SELECTED_FIELDS = {"sampleID", "inputSHA256", "canonicalLabel", "inputFailure"}
HEX = re.compile(r"[0-9a-f]{64}\Z")


def _selected(rows):
    indexed = {}
    for row in rows:
        if not isinstance(row, dict) or set(row) != SELECTED_FIELDS:
            raise ValueError("Selected prediction fields are incomplete or unknown")
        identity, digest = row["sampleID"], row["inputSHA256"]
        if not isinstance(identity, str) or not identity or identity in indexed:
            raise ValueError("Missing or duplicate opaque prediction identity")
        if not isinstance(digest, str) or HEX.fullmatch(digest) is None:
            raise ValueError("Prediction input is not bound to exact source bytes")
        label, failure = row["canonicalLabel"], row["inputFailure"]
        if label is not None:
            require_canonical_chord_label(label)
        if failure is not None and (not isinstance(failure, str) or not failure or len(failure) > 256):
            raise ValueError("Malformed retained input failure")
        if failure is not None and label is not None:
            raise ValueError("A failed input cannot have a successful hypothesis")
        indexed[identity] = row
    return indexed


def _counts(rows):
    counter = Counter()
    for row in rows:
        a, b = row["atomicCorrect"], row["factorCorrect"]
        counter.update({"count": 1, "atomicCorrect": int(a), "factorCorrect": int(b),
            "corrections": int(not a and b), "regressions": int(a and not b),
            "bothCorrect": int(a and b), "bothWrong": int(not a and not b),
            "factorNull": int(row["factorLabel"] is None),
            "atomicNull": int(row["atomicLabel"] is None),
            "factorInputFailures": int(row["factorInputFailure"] is not None),
            "atomicInputFailures": int(row["atomicInputFailure"] is not None)})
    counter["net"] = counter["factorCorrect"] - counter["atomicCorrect"]
    return dict(sorted(counter.items()))


def score_selected_predictions(truth_rows, factor_rows, atomic_rows, *, expected_writers,
                               canonical_labels=None):
    """Join previously selected predictions, refusing an incomplete workload.

    Callers must validate the raw packets/code/weights/protocol before projecting
    selected rows. This pure counter cannot authenticate chronology or bindings
    outside each complete source-input hash. Optional labels exist for synthetic
    contract tests only; actual execution must use the full fixed 168-label grid.
    """
    writers = tuple(expected_writers)
    if not writers or len(set(writers)) != len(writers) or any(
        not isinstance(writer, str) or not writer.startswith("trn_") for writer in writers
    ):
        raise ValueError("Scoring needs explicit disjoint development-writer identities")
    labels = tuple(canonical_labels if canonical_labels is not None else
                   (label for label, _ in canonical_chord_specs()))
    if not labels or len(set(labels)) != len(labels):
        raise ValueError("Invalid fixed canonical workload")
    for label in labels:
        require_canonical_chord_label(label)
    # Parse and validate ALL prediction records before accessing any truth row.
    factors, atoms = _selected(factor_rows), _selected(atomic_rows)
    if set(factors) != set(atoms):
        raise ValueError("Prediction arms have different or omitted inputs")
    joined, seen_ids, seen_cells = [], set(), set()
    for truth in truth_rows:
        identity = truth["sampleID"]
        if identity in seen_ids or identity not in factors:
            raise ValueError("Duplicate or unmatched source truth")
        seen_ids.add(identity)
        writer, session = truth["writer"], truth["session"]
        label, order = truth["canonicalLabel"], truth["acquisitionOrder"]
        if (truth["role"] != "development" or writer not in writers or
            type(session) is not int or session not in (1, 2) or label not in labels or
            order not in ACQUISITION_ORDERS or truth["syntheticNotNaturalInk"] is not True):
            raise ValueError("Truth is outside the frozen synthetic development role")
        cell = (writer, session, label, order)
        if cell in seen_cells:
            raise ValueError("Duplicate writer/session/label/order source cell")
        seen_cells.add(cell)
        factor, atom = factors[identity], atoms[identity]
        source_hash = truth["trajectorySourceSHA256"]
        if source_hash != factor["inputSHA256"] or source_hash != atom["inputSHA256"]:
            raise ValueError("Scored predictions are not for identical complete input")
        joined.append({"sampleID": identity, "writer": writer, "session": session,
            "canonicalLabel": label, "acquisitionOrder": order, "inputSHA256": source_hash,
            "factorLabel": factor["canonicalLabel"], "atomicLabel": atom["canonicalLabel"],
            "factorInputFailure": factor["inputFailure"], "atomicInputFailure": atom["inputFailure"],
            "factorCorrect": factor["canonicalLabel"] == label,
            "atomicCorrect": atom["canonicalLabel"] == label})
    expected = {(w, s, label, order) for w in writers for s in (1, 2)
                for label in labels for order in ACQUISITION_ORDERS}
    if seen_cells != expected or seen_ids != set(factors):
        raise ValueError("Missing or extra workload cells; unread inputs may not be omitted")
    summaries = {}
    for order in ACQUISITION_ORDERS:
        arm = [row for row in joined if row["acquisitionOrder"] == order]
        writers_report = {writer: _counts([row for row in arm if row["writer"] == writer])
                          for writer in writers}
        components = Counter()
        for row in arm:
            intended = parse_canonical_chord_label(row["canonicalLabel"])
            if row["factorLabel"] is not None:
                actual = parse_canonical_chord_label(row["factorLabel"])
                components.update({"rootPitchWrong": int(actual.root != intended.root),
                    "qualityWrong": int(actual.form != intended.form),
                    "extensionWrong": int(actual.extension != intended.extension),
                    "alterationsWrong": int(actual.alterations != intended.alterations),
                    "slashBassWrong": int(actual.slash_bass != intended.slash_bass)})
        summaries[order] = {"counts": _counts(arm), "writers": writers_report,
            "factorComponentErrorsOnNonNull": dict(components)}
    forward, reversed_arm = (summaries[order] for order in ACQUISITION_ORDERS)
    rules = {"zeroInputFailures": all(row["factorInputFailure"] is None and
        row["atomicInputFailure"] is None for row in joined),
        "positivePrimaryNet": forward["counts"]["net"] > 0,
        "noPrimaryWriterRegression": all(c["net"] >= 0 for c in forward["writers"].values()),
        "noReversedStressWriterRegression": all(c["net"] >= 0 for c in reversed_arm["writers"].values())}
    return {"version": VERSION, "rowCount": len(joined), "rows": joined,
        "summaries": summaries, "rules": rules,
        "syntheticBridgeScreenPass": all(rules.values()),
        "productionEligible": False, "personalizationBenefitTested": False,
        "naturalChordAccuracyTested": False, "freshWriterAccuracyTested": False,
        "pairedAcquisitionVariantsAreIndependent": False,
        "scope": "conditional-rooted-synthetic-factor-vs-raw-greedy-oracle-atomic"}


# Execution binding is append-only below the original pure counter.  No forward
# model call is permitted here; model state can only be authenticated/read.
def _raw_factor_selection(rows):
    from ..contracts import canonical_json_bytes
    from ..models.output_contract import OUTPUT_HEADS, FactorLogits
    from . import personal_whole_chord_factor as factor
    fields = {"conditionalCanonicalLabel", "conditionalValidRootedCandidates", "inputFailure", "inputSHA256",
        "logits", "rasterSHA256", "sampleID", "trajectorySHA256"}
    selected, cache = [], {}
    for row in rows:
        factor._require_exact_keys(row, fields, "factor prediction row")
        if not isinstance(row["sampleID"], str) or HEX.fullmatch(row["sampleID"]) is None:
            raise ValueError("Factor source identity is not opaque")
        if row["inputFailure"] is not None:
            if any(row[name] is not None for name in ("logits", "rasterSHA256", "trajectorySHA256",
                    "conditionalCanonicalLabel", "conditionalValidRootedCandidates")):
                raise ValueError("Failed factor input has a rescued output")
            identity = None
        else:
            raw = row["logits"]
            if not isinstance(raw, dict) or any(not isinstance(raw.get(h.name), list)
                or any(type(v) not in (int, float) for v in raw[h.name]) for h in OUTPUT_HEADS):
                raise ValueError("Factor prediction does not preserve numeric raw heads")
            FactorLogits.from_mapping(raw)
            if any(not isinstance(row[name], str) or HEX.fullmatch(row[name]) is None
                    for name in ("rasterSHA256", "trajectorySHA256")):
                raise ValueError("Missing successful factor feature bindings")
            key = canonical_json_bytes(raw)
            if key not in cache:
                decoded = factor.decode_factor_logits(factor.conditional_valid_rooted_logits(raw),
                    maximum_candidate_count=factor.CONDITIONAL_CANDIDATE_COUNT)
                candidates = [{"canonicalLabel": c.canonical_label, "rawJointLogScore": c.raw_joint_log_score}
                    for c in decoded.candidates if c.canonical_label != "•/•"]
                identity = factor.conditional_identity(raw)
                if len(candidates) != 3 or identity != candidates[0]["canonicalLabel"]:
                    raise ValueError("Conditional factor ranking contract changed")
                cache[key] = (identity, candidates)
            identity, candidates = cache[key]
            if row["conditionalCanonicalLabel"] != identity or row["conditionalValidRootedCandidates"] != candidates:
                raise ValueError("Frozen factor selection differs from raw heads")
        selected.append({"sampleID": row["sampleID"], "inputSHA256": row["inputSHA256"],
            "canonicalLabel": identity, "inputFailure": row["inputFailure"]})
    _selected(selected)
    return selected


def _raw_atomic_selection(packet):
    from ..chord_notation import CanonicalChordLabelError
    from . import personal_whole_chord_atomic_control as atomic
    vocabulary = atomic.validate_vocabulary(packet["vocabulary"])
    if packet["vocabularySHA256"] != atomic.sha256(atomic.canonical_bytes(list(vocabulary))):
        raise ValueError("Atomic vocabulary binding changed")
    row_fields = {"sampleID", "inputSHA256", "oracleProjectionRowSHA256", "sourceStrokeCount", "sourcePointCount",
        "owners", "rawTokenString", "canonicalChord", "inputFailure", "parserOutcome"}
    owner_fields = {"ownerOrdinal", "sourceStrokeIndexes", "sourceStrokeCount", "sourcePointCount", "ownerInputSHA256",
        "rasterSHA256", "rawLogits", "firstArgmaxIndex", "firstArgmaxToken", "cacheHit", "failure"}
    selected, owner_count, owner_failures = [], 0, 0
    for row in packet["rows"]:
        if (not isinstance(row, dict) or set(row) != row_fields or type(row["inputFailure"]) is not bool
            or not isinstance(row["sampleID"], str) or HEX.fullmatch(row["sampleID"]) is None):
            raise ValueError("Atomic prediction row schema changed")
        if not isinstance(row["owners"], list) or not row["owners"]:
            raise ValueError("Atomic owners omitted")
        tokens, membership, points, failures = [], [], 0, []
        for ordinal, owner in enumerate(row["owners"]):
            if not isinstance(owner, dict) or set(owner) != owner_fields:
                raise ValueError("Atomic owner fields changed")
            indexes = owner["sourceStrokeIndexes"]
            if (type(owner["ownerOrdinal"]) is not int or owner["ownerOrdinal"] != ordinal
                or not isinstance(indexes, list) or not indexes or any(type(i) is not int or i < 0 for i in indexes)
                or indexes != sorted(set(indexes)) or type(owner["sourceStrokeCount"]) is not int or owner["sourceStrokeCount"] != len(indexes)
                or type(owner["sourcePointCount"]) is not int or owner["sourcePointCount"] < len(indexes)
                or type(owner["cacheHit"]) is not bool or not isinstance(owner["ownerInputSHA256"], str)
                or HEX.fullmatch(owner["ownerInputSHA256"]) is None):
                raise ValueError("Atomic owner membership or geometry metadata changed")
            failure = owner["failure"]
            if failure is not None:
                if not isinstance(failure, str) or not failure or any(owner[k] is not None
                        for k in ("rawLogits", "firstArgmaxIndex", "firstArgmaxToken")):
                    raise ValueError("Atomic owner failure was rescued")
                failures.append(failure)
            else:
                logits = atomic._logits(owner["rawLogits"])
                first = max(range(97), key=logits.__getitem__)
                if (type(owner["firstArgmaxIndex"]) is not int or owner["firstArgmaxIndex"] != first
                    or owner["firstArgmaxToken"] != vocabulary[first] or not isinstance(owner["rasterSHA256"], str)
                    or HEX.fullmatch(owner["rasterSHA256"]) is None):
                    raise ValueError("Atomic first-argmax differs from saved full97 logits")
                tokens.append(vocabulary[first])
            membership.extend(indexes); points += owner["sourcePointCount"]
        if (type(row["sourceStrokeCount"]) is not int or sorted(membership) != list(range(row["sourceStrokeCount"]))
            or type(row["sourcePointCount"]) is not int or row["sourcePointCount"] != points
            or not isinstance(row["oracleProjectionRowSHA256"], str) or HEX.fullmatch(row["oracleProjectionRowSHA256"]) is None):
            raise ValueError("Atomic source membership omitted or duplicated")
        raw, canonical = None if failures else "".join(tokens), None
        if raw is not None:
            try:
                canonical = require_canonical_chord_label(raw)
            except CanonicalChordLabelError:
                pass
        outcome = "canonical" if canonical is not None else "owner-failure" if failures else "invalid-raw-string"
        if (row["rawTokenString"] != raw or row["canonicalChord"] != canonical
            or row["inputFailure"] != bool(failures) or row["parserOutcome"] != outcome):
            raise ValueError("Atomic raw-greedy parser selection changed")
        selected.append({"sampleID": row["sampleID"], "inputSHA256": row["inputSHA256"], "canonicalLabel": canonical,
            "inputFailure": "atomic-owner-input-or-model-failure" if failures else None})
        owner_count += len(row["owners"]); owner_failures += len(failures)
    _selected(selected)
    if (packet["ownerCount"] != owner_count or packet["ownerFailures"] != owner_failures
        or packet["inputFailures"] != sum(r["inputFailure"] is not None for r in selected)):
        raise ValueError("Atomic failure/owner denominators changed")
    return selected


def _factor_binding(fit_files, prediction_files, code, protocol_bytes):
    from ..contracts import canonical_json_bytes
    from . import personal_whole_chord_factor as factor
    protocol_sha = factor._sha256(protocol_bytes)
    receipt = factor.validate_fit_receipt(factor._read_canonical_json_bytes(fit_files["fit-receipt.json"], "fit receipt"),
        code=code, protocol_sha256=protocol_sha)
    if fit_files["frozen-protocol.md"] != protocol_bytes or prediction_files["frozen-protocol.md"] != protocol_bytes:
        raise ValueError("Frozen factor protocol differs")
    expected_history = b"".join(canonical_json_bytes(row) + b"\n" for row in receipt["history"])
    if (fit_files["training-history.jsonl"] != expected_history
        or len(expected_history) != receipt["trainingHistoryByteCount"]
        or factor._sha256(expected_history) != receipt["trainingHistorySHA256"]
        or len(fit_files["training-source-truth.json"]) != receipt["trainingTruthLedgerByteCount"]
        or factor._sha256(fit_files["training-source-truth.json"]) != receipt["trainingTruthLedgerSHA256"]
        or factor._sha256(fit_files["weights.pt"]) != receipt["checkpointSHA256"]):
        raise ValueError("Frozen factor fit companions changed")
    model = factor.load_checkpoint(fit_files["weights.pt"], code=code, protocol_sha256=protocol_sha,
        source_plan_version=receipt["sourcePlanVersion"], truth_sha256=receipt["trainingTruthLedgerSHA256"])
    if factor._state_digest(model.state_dict()) != receipt["finalStateSHA256"]:
        raise ValueError("Checkpoint state differs from frozen receipt")
    if (factor._tensor_digests(model.state_dict()) != receipt["finalTensorSHA256"]
        or factor._head_state_digest(model.state_dict(), factor.INACTIVE_HEADS) != receipt["finalInactiveHeadSHA256"]):
        raise ValueError("Checkpoint tensor or inactive-head bindings changed")
    packet = factor._read_canonical_json_bytes(prediction_files["predictions.json"], "factor prediction packet")
    fields = {"checkpointSHA256", "codeSHA256", "conditionalRankingContract", "featureContract", "fitReceiptSHA256",
        "inputFeatureStreamSHA256", "modelContract", "protocolSHA256", "roleGuards", "rowCount", "rows", "runtime",
        "scope", "sourcePlanVersion", "sourceSHA256", "version"}
    factor._require_exact_keys(packet, fields, "factor prediction packet")
    expected = {"checkpointSHA256": receipt["checkpointSHA256"], "codeSHA256": code,
        "conditionalRankingContract": {"candidateCount": 3, "kind": "force-rooted-for-identity-ranking-only",
            "validity": "equal-logit-neutralized-for-identity-ranking-only", "isAcceptanceDecision": False},
        "featureContract": factor._feature_contract(), "fitReceiptSHA256": factor._sha256(fit_files["fit-receipt.json"]),
        "modelContract": factor._model_contract(), "protocolSHA256": protocol_sha, "roleGuards": factor._role_guards(),
        "rowCount": 5376, "runtime": factor._runtime_contract(), "scope": factor.SCOPE,
        "sourcePlanVersion": receipt["sourcePlanVersion"], "sourceSHA256": factor.SOURCE_SHA256,
        "version": factor.PREDICTION_VERSION}
    if (any(packet[k] != v for k, v in expected.items()) or not isinstance(packet["rows"], list)
        or len(packet["rows"]) != 5376 or not factor._is_sha256(packet["inputFeatureStreamSHA256"])):
        raise ValueError("Factor packet fixed execution contract changed")
    frozen = factor._read_canonical_json_bytes(prediction_files["prediction-receipt.json"], "factor prediction receipt")
    expected_receipt = {"checkpointSHA256": receipt["checkpointSHA256"], "fitReceiptSHA256": expected["fitReceiptSHA256"],
        "packetByteCount": len(prediction_files["predictions.json"]), "packetRelativePath": "predictions.json",
        "packetSHA256": factor._sha256(prediction_files["predictions.json"]), "protocolSHA256": protocol_sha,
        "rowCount": 5376, "sourceSHA256": factor.SOURCE_SHA256, "version": factor.PREDICTION_RECEIPT_VERSION}
    if frozen != expected_receipt:
        raise ValueError("Factor prediction freeze receipt changed")
    return packet, _raw_factor_selection(packet["rows"])


def _atomic_binding(files, code, protocol_bytes, artifacts, manifest_path, package_path):
    import importlib.metadata
    import platform
    import numpy as np
    from . import personal_whole_chord_atomic_control as atomic
    from . import personal_whole_chord_factor as factor
    packet = factor._read_canonical_json_bytes(files["predictions.json"], "atomic prediction packet")
    fields = {"version", "scope", "productionEligible", "automaticOwnership", "swiftProbabilitySearch", "truthJoined",
        "personalizationTested", "trustOrAcceptanceApplied", "composition", "bindings", "oracleProjectionSHA256",
        "vocabulary", "vocabularySHA256", "rowCount", "ownerCount", "modelCallCount", "cacheByExactRasterSHA256",
        "runtime", "inputDrops", "ownerFailures", "inputFailures", "rows", "codeSHA256", "sourceSHA256",
        "protocolSHA256", "roleBindingSHA256", "sourcePlanVersion", "developmentWriterCount", "trainingWriterCount",
        "reservedWriterCount", "roleGuards"}
    factor._require_exact_keys(packet, fields, "atomic prediction packet")
    protocol_sha = atomic.sha256(protocol_bytes)
    guards = {"privateInkUsed": False, "reservedWritersComposed": False, "reservedWritersEncoded": False,
        "automaticAcceptanceAuthorized": False, "sourceTruthSuppliedToPredictor": False, "sourceWriterSuppliedToPredictor": False}
    expected = {"version": atomic.VERSION, "scope": atomic.SCOPE, "productionEligible": False,
        "automaticOwnership": False, "swiftProbabilitySearch": False, "truthJoined": False,
        "personalizationTested": False, "trustOrAcceptanceApplied": False,
        "composition": "unrestricted-97-first-argmax-concatenation-strict-canonical-or-null", "codeSHA256": code,
        "sourceSHA256": factor.SOURCE_SHA256, "protocolSHA256": protocol_sha,
        "developmentWriterCount": 8, "trainingWriterCount": 32, "reservedWriterCount": 20,
        "sourcePlanVersion": factor.whole_source.VERSION, "roleGuards": guards, "rowCount": 5376, "inputDrops": 0,
        "vocabulary": artifacts["vocabulary"], "vocabularySHA256": artifacts["vocabularySHA256"], "cacheByExactRasterSHA256": True}
    runtime = {"kind": "pinned-operational-CoreML", "computeUnits": "CPU_ONLY",
        "coremltoolsVersion": importlib.metadata.version("coremltools"), "numpyVersion": np.__version__,
        "pythonVersion": platform.python_version(), "platform": platform.platform(), "modelExported": False,
        "torchWeightsReconstructed": False, **{k: v for k, v in artifacts.items() if k != "vocabulary"}}
    if (any(packet[k] != v for k, v in expected.items()) or packet["runtime"] != runtime
        or not isinstance(packet["rows"], list) or len(packet["rows"]) != 5376
        or any(not factor._is_sha256(packet[k]) for k in ("roleBindingSHA256", "oracleProjectionSHA256"))
        or files["frozen-protocol.md"] != protocol_bytes
        or files["code-snapshot.json"] != atomic.canonical_bytes(code)):
        raise ValueError("Atomic fixed scope/runtime/code/source bindings changed")
    bindings = {"sourceSHA256": factor.SOURCE_SHA256, "protocolSHA256": protocol_sha,
        "roleBindingSHA256": packet["roleBindingSHA256"], "codeSnapshotSHA256": atomic.sha256(atomic.canonical_bytes(code)),
        "manifestSHA256": artifacts["manifestSHA256"], "packageSHA256": artifacts["packageSHA256"]}
    if packet["bindings"] != bindings:
        raise ValueError("Atomic hashed execution inputs changed")
    receipt = factor._read_canonical_json_bytes(files["prediction-receipt.json"], "atomic prediction receipt")
    wanted = {"version": atomic.RECEIPT_VERSION, "scope": atomic.SCOPE, "productionEligible": False,
        "predictionsRelativePath": "predictions.json", "predictionsSHA256": atomic.sha256(files["predictions.json"]),
        "predictionsByteCount": len(files["predictions.json"]), "inputsUnchanged": True,
        "modelManifestPath": str(manifest_path), "modelPackagePath": str(package_path),
        "modelManifestRelativePath": "model-manifest.json",
        **{k: artifacts[k] for k in ("manifestSHA256", "packageSHA256", "weightsMetadataSHA256", "vocabularySHA256")},
        **{k: packet[k] for k in ("codeSHA256", "sourceSHA256", "protocolSHA256", "roleBindingSHA256", "sourcePlanVersion",
            "oracleProjectionSHA256", "runtime", "rowCount", "ownerCount", "modelCallCount", "inputDrops", "inputFailures",
            "ownerFailures", "roleGuards")}}
    if (atomic.canonical_bytes(receipt) != atomic.canonical_bytes(wanted)
        or atomic.sha256(files["model-manifest.json"]) != artifacts["manifestSHA256"]):
        raise ValueError("Atomic prediction freeze receipt changed")
    selected = _raw_atomic_selection(packet)
    calls = sum(o["rasterSHA256"] is not None and not o["cacheHit"] for r in packet["rows"] for o in r["owners"])
    if type(packet["modelCallCount"]) is not int or calls != packet["modelCallCount"]:
        raise ValueError("Atomic model-call denominator changed")
    return packet, selected


def score_frozen(source_path, protocol_path, fit_directory, factor_directory, atomic_predictions,
                 atomic_manifest, atomic_package, output_path):
    """Authenticate both complete freezes before any source truth construction."""
    from pathlib import Path
    from ..contracts import canonical_json_bytes
    from . import personal_whole_chord_atomic_control as atomic
    from . import personal_whole_chord_factor as factor
    from . import personal_whole_chord_source as source
    source_path, protocol_path, fit_directory, factor_directory, atomic_predictions, atomic_manifest, atomic_package, output_path = map(
        Path, (source_path, protocol_path, fit_directory, factor_directory, atomic_predictions, atomic_manifest, atomic_package, output_path))
    atomic_directory = atomic_predictions.parent
    if atomic_predictions.name != "predictions.json":
        raise ValueError("Atomic freeze must be its receipt-bound predictions.json")
    if (factor._repo_root() in output_path.parents or any(p == output_path or p in output_path.parents
            for p in (fit_directory, factor_directory, atomic_directory, atomic_package))):
        raise ValueError("Scoring output must be new and outside source/input directories")
    code, snapshot = factor._code_snapshot()
    def capture(path):
        path = factor._require_regular_file(path, name="frozen score input")
        payload = path.read_bytes(); snapshot[path] = factor._sha256(payload)
        return payload
    source_bytes, protocol_bytes = capture(source_path), capture(protocol_path)
    if factor._sha256(source_bytes) != factor.SOURCE_SHA256 or factor._sha256(protocol_bytes) != code[factor.PROTOCOL_PATH]:
        raise ValueError("Scoring source or protocol bytes differ")
    fit_files = {name: capture(fit_directory / name) for name in ("fit-receipt.json", "weights.pt", "frozen-protocol.md",
        "training-history.jsonl", "training-source-truth.json")}
    factor_files = {name: capture(factor_directory / name) for name in ("predictions.json", "prediction-receipt.json", "frozen-protocol.md")}
    atomic_files = {name: capture(atomic_directory / name) for name in ("predictions.json", "prediction-receipt.json",
        "frozen-protocol.md", "code-snapshot.json", "model-manifest.json")}
    manifest_bytes = capture(atomic_manifest)
    artifacts = atomic.validate_pinned_artifacts(atomic_manifest, atomic_package)  # Byte-only: no Core ML load.
    factor_packet, factor_selected = _factor_binding(fit_files, factor_files, code, protocol_bytes)
    if atomic_files["model-manifest.json"] != manifest_bytes:
        raise ValueError("Atomic original/copied manifest bytes differ")
    atomic_packet, atomic_selected = _atomic_binding(atomic_files, code, protocol_bytes, artifacts, atomic_manifest, atomic_package)
    left, right = _selected(factor_selected), _selected(atomic_selected)
    if (len(left) != 5376 or set(left) != set(right)
        or any(left[i]["inputSHA256"] != right[i]["inputSHA256"] for i in left)
        or factor_packet["sourcePlanVersion"] != atomic_packet["sourcePlanVersion"]):
        raise ValueError("Frozen arms differ in complete workload/source inputs")
    selected_bytes = canonical_json_bytes({"factor": factor_selected, "atomic": atomic_selected})
    # Both raw freezes and selections have now passed, before source truth.
    records, roles = factor._load_records(source_bytes)
    plan = source.build_role_plan(records, "development")
    if tuple(plan.writers) != tuple(roles[1]) or len(plan.writers) != 8 or len(plan.examples) != 5376:
        raise ValueError("Scoring requires all eight development writers and full168 labels")
    role_digest = atomic.sha256(atomic.canonical_bytes({"training": list(roles[0]), "development": list(roles[1]), "reserved": list(roles[2])}))
    projected = sorted(atomic.source_owner_projection(source.atomic_owner_inputs(plan)), key=lambda r: r["sampleID"])
    if (role_digest != atomic_packet["roleBindingSHA256"]
        or atomic.sha256(atomic.canonical_bytes(projected)) != atomic_packet["oracleProjectionSHA256"]):
        raise ValueError("Frozen atomic ownership/role projection differs from source")
    atomic_index = {r["sampleID"]: r for r in atomic_packet["rows"]}
    for row in projected:
        saved = atomic_index[row["sampleID"]]
        if atomic.sha256(atomic.canonical_bytes(row)) != saved["oracleProjectionRowSHA256"]:
            raise ValueError("Atomic source-owner projection row changed")
        if (len(saved["owners"]) != len(row["oracleOwners"]) or saved["sourceStrokeCount"] != len(row["strokes"])
            or saved["sourcePointCount"] != sum(len(s["points"]) for s in row["strokes"])):
            raise ValueError("Atomic complete source geometry counts changed")
        for ordinal, indexes in enumerate(row["oracleOwners"]):
            owner = {"sampleID": row["sampleID"], "ownerOrdinal": ordinal, "sourceStrokeIndexes": indexes,
                "strokes": [row["strokes"][i] for i in indexes]}
            output_owner = saved["owners"][ordinal]
            if (output_owner["sourceStrokeIndexes"] != indexes or output_owner["sourcePointCount"] != sum(len(s["points"]) for s in owner["strokes"])
                or atomic.sha256(atomic.canonical_bytes(owner)) != output_owner["ownerInputSHA256"]):
                raise ValueError("Atomic owner source hash changed")
    truth = source.truth_ledger_bytes(plan)
    ledger = factor._read_canonical_json_bytes(truth, "development truth ledger")
    result = score_selected_predictions(ledger["rows"], factor_selected, atomic_selected, expected_writers=plan.writers)
    if result["rowCount"] != 5376 or any(result["summaries"][o]["counts"]["count"] != 2688 for o in ACQUISITION_ORDERS):
        raise ValueError("Actual scoring denominator is not the full fixed grid")
    if selected_bytes != canonical_json_bytes({"factor": factor_selected, "atomic": atomic_selected}):
        raise ValueError("Truth join mutated frozen selections")
    factor._preserved(snapshot)
    if atomic.validate_pinned_artifacts(atomic_manifest, atomic_package) != artifacts:
        raise ValueError("Pinned atomic artifacts changed during score")
    report = {**result, "codeSHA256": code, "sourceSHA256": factor.SOURCE_SHA256,
        "protocolSHA256": factor._sha256(protocol_bytes), "truthLedgerSHA256": factor._sha256(truth),
        "factorPacketSHA256": factor._sha256(factor_files["predictions.json"]),
        "atomicPacketSHA256": factor._sha256(atomic_files["predictions.json"]),
        "selectedProjectionSHA256": factor._sha256(selected_bytes),
        "inputBindings": {str(path): digest for path, digest in snapshot.items()},
        "atomicArtifacts": artifacts, "sourceExposureLedger": ledger["exposureLedger"],
        "modelInferencePerformedDuringScoring": False, "rawTenHeadOutputsModified": False,
        "inputsUnchanged": True}
    output = factor._new_output_directory(output_path)
    factor._write_exclusive(output / "development-source-truth.json", truth)
    factor._write_exclusive(output / "selected-predictions.json", selected_bytes)
    factor._write_exclusive(output / "score.json", canonical_json_bytes(report))
    return report


def main(argv=None):
    import argparse
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "protocol", "fit-directory", "factor-directory", "atomic-predictions", "atomic-manifest", "atomic-package", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args(argv)
    report = score_frozen(args.source, args.protocol, args.fit_directory, args.factor_directory, args.atomic_predictions,
        args.atomic_manifest, args.atomic_package, args.output)
    print(f"PAIRED_SCORE_FROZEN rows={report['rowCount']} syntheticBridgeScreenPass={report['syntheticBridgeScreenPass']} productionEligible=False", flush=True)


if __name__ == "__main__":
    main()

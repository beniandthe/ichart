"""Source-only joint support-match/defer schedules; no geometry, encoder or fit.

Consumes the pinned crossfit metadata ledger, never its features/checkpoints or
development/reserved samples. Unavailable setup slots stay explicit and are
never replaced or encoded as invented zero images. Training targets are a
separate artifact; heldout forward schedules contain no query labels/targets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import re

import torch

from ..contracts import strict_json_loads
from . import personal_support_crossfit as crossfit
from .personal_cross_writer_evaluation import TASKS
from .uji_personal import SOURCE_SHA256

VERSION = "personal-support-match-defer-source-plan-v1"
ARMS = ("genericCEControl", "jointMatchDefer")
SEED, EPOCHS, EPISODES_PER_EPOCH = 29, 30, 64
PROTOCOL = "docs/personal-support-match-defer-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "b8bc1c371f3e5cfd60c8f8867e8380148d93d7105ff62289c4ff1b02484d5c33"
DOMAIN_SHA256 = "5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010"
PARENT = {"receipt": "d2a31e73d53b25b812f0ba4f24f812014515606f97a20e6b7170eaf94d0e20d2",
          "plan": "75adca9c1b19b0b4b54328ffb010d8fccedaf085cf43496e0f2d20269bc9be3e",
          "metadata": "97653c8a59077588a886cdee2577f94084cf704f55435f320016720870642332"}
ROOT = Path(__file__).resolve().parents[3]
CODE_PATHS = ("recognition_ml/ichart_recognition_ml/research/personal_support_match_defer_plan.py",
    "recognition_ml/tests/test_personal_support_match_defer_plan.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_crossfit.py",
    "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_evaluation.py",
    "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_contrastive.py",
    "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/features.py", "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_match_defer.py",
    "recognition_ml/tests/test_personal_support_match_defer.py", PROTOCOL,
    "recognition_ml/ichart_recognition_ml/research/personal_support_match_defer_source.py",
    "recognition_ml/tests/test_personal_support_match_defer_source.py",
    "iChart/Shared/ChordNotation/ChordRecognitionDomain.swift", "iChart/Shared/ChordNotation/ChordNotation.swift",
    "iChart/Recognition/PersonalInkSetupCatalog.swift")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(value):
    return hashlib.sha256(value).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def read(path):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path and path.is_file() and not path.is_symlink()
            and path.stat().st_size <= 64 * 1024 * 1024, "Bounded regular metadata required")
    return path.read_bytes()


def parsed(data):
    return strict_json_loads(data.decode(), "support-match-defer-source-plan")


def code_identity():
    result = {name: sha(read(ROOT / name)) for name in CODE_PATHS}
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Fixed protocol changed")
    for name, expected in (("iChart/Shared/ChordNotation/ChordRecognitionDomain.swift", "c1c4d50e5317e8872987d123bcfbe5defa97189c149638c038a5235e7f78b385"),
        ("iChart/Shared/ChordNotation/ChordNotation.swift", "b725238345c881c7d0ee1fcfba52c49bca7469b1e301663265c7d50bd6d6e25d"),
        ("iChart/Recognition/PersonalInkSetupCatalog.swift", "4ab20979181952d1f8ca2d09e31348e6ddfb6fbfc41c07821387c2b3eccc1360")):
        require(result[name] == expected, "Swift setup/domain source changed")
    return result


def validate_domain(data, expected_sha256, vocabulary):
    require(expected_sha256 == DOMAIN_SHA256 and sha(data) == expected_sha256, "Frozen Swift domain export changed")
    domain = parsed(data)
    require(domain["version"] == "chord-recognition-domain-v1" and domain["vocabulary"] == vocabulary
            and len(domain["allowedLabels"]) == len(set(domain["allowedLabels"])) == 41
            and set(domain["allowedLabels"]) <= set(vocabulary), "Full97/41 Swift domain required")
    source = read(ROOT / "iChart/Recognition/PersonalInkSetupCatalog.swift").decode()
    core = re.findall(r'\.init\(label: "([^"]+)"', source.split("static let coreSymbols: [Prompt] = [", 1)[1].split("\n    ]", 1)[0])
    extra = re.findall(r'\.init\(label: "([^"]+)"', source.split("static let symbols: [Prompt] = coreSymbols + [", 1)[1].split("\n    ]", 1)[0])
    actual = {"core10": [l for l in core if l in vocabulary], "catalog21": [l for l in core + extra if l in vocabulary]}
    require(actual == {k: list(v) for k, v in TASKS.items()} and set(actual["catalog21"]) <= set(domain["allowedLabels"]), "Actual app catalog intersection changed")
    return domain


def validate_metadata(receipt, metadata, receipt_sha256, metadata_sha256):
    """Same source-hash ranking as fold_writers, without inventing excluded rows."""
    require(digest(receipt_sha256) and sha(canonical(receipt)) == receipt_sha256 and digest(metadata_sha256)
            and sha(canonical(metadata)) == metadata_sha256 == receipt["metadataSHA256"]
            and receipt_sha256 == PARENT["receipt"] and metadata_sha256 == PARENT["metadata"], "Pinned metadata/receipt changed")
    require(receipt["version"] == metadata["version"] == crossfit.VERSION and receipt["sourceSHA256"] == SOURCE_SHA256, "Wrong strict source/metadata version")
    rows, vocabulary = metadata["rows"], metadata["vocabulary"]
    writers, excluded = receipt["trainingWriters"], receipt["developmentWriters"] + receipt["reservedWriters"]
    require(vocabulary == receipt["vocabulary"] == sorted(set(vocabulary)) and len(vocabulary) == 97
            and set().union(*map(set, TASKS.values())) <= set(vocabulary), "Full97/app catalogs required")
    require(len(writers) == len(set(writers)) == 32 and len(receipt["developmentWriters"]) == 8 and len(receipt["reservedWriters"]) == 20
            and len(set(excluded)) == 28 and not set(writers) & set(excluded)
            and all(re.fullmatch(r"trn_(?:UJI|UPV)_W[0-9]{2}", w) for w in writers + receipt["developmentWriters"])
            and all(re.fullmatch(r"tst_(?:UJI|UPV)_W[0-9]{2}", w) for w in receipt["reservedWriters"]), "Exact writer roles required")
    # This is the frozen fold_writers ranking; its full-source parser cannot be
    # called on a training-only ledger without fabricating dev/reserved records.
    ranked = sorted(writers, key=lambda w: crossfit._sha256(("personal-support-retrieval-v1:fold:" + w).encode()))
    require(receipt["folds"] == {"A": ranked[:16], "B": ranked[16:]}, "Existing crossfit fold order changed")
    require(len(rows) == 6208 and len({r["sourceID"] for r in rows}) == 6208
            and {(r["writer"], r["session"], r["label"]) for r in rows}
            == {(w, s, l) for w in writers for s in (1, 2) for l in vocabulary}, "Incomplete/duplicate32-writer metadata grid")
    for row in rows:
        require(row["sourceID"] == f'{row["writer"]}-{row["session"]}-{row["label"]}' and type(row["session"]) is int
                and len(row["label"]) == 1 and not row["label"].isspace()
                and row["generator"] == ("fitA" if row["writer"] in receipt["folds"]["B"] else "fitB")
                and digest(row["rawRasterSHA256"]) and digest(row["trajectorySHA256"]), "Malformed source identity/hash/generator")
        available = row["storedFailure"] is None
        require((digest(row["storedRasterSHA256"]) and digest(row["storedTrajectorySHA256"])) if available else
                (row["storedRasterSHA256"] is None and row["storedTrajectorySHA256"] is None and isinstance(row["storedFailure"], str) and bool(row["storedFailure"])), "Stored availability/hash contradiction")
    require(receipt["roleGuards"]["training32Only"] is True and receipt["roleGuards"]["privateInkUsed"] is False
            and receipt["roleGuards"]["developmentModelInferencePerformed"] is False and receipt["roleGuards"]["reservedRastersConstructed"] is False,
            "Parent source role guard changed")
    return rows, vocabulary


def source_row(index, row, *, explicit_support=False):
    result = {"sourceIndex": index, "sourceKey": sha(row["sourceID"].encode()), "writer": row["writer"], "session": row["session"],
            "rawRasterSHA256": row["rawRasterSHA256"], "trajectorySHA256": row["trajectorySHA256"],
            "storedRasterSHA256": row["storedRasterSHA256"], "storedTrajectorySHA256": row["storedTrajectorySHA256"], "storedFailure": row["storedFailure"]}
    if explicit_support:
        result["sourceID"] = row["sourceID"]
    return result


def episode(rows, lookup, writer, query_session, catalog, support_writer, fold):
    support = []
    for slot, label in enumerate(TASKS[catalog]):
        i = lookup[support_writer, 3 - query_session, label]
        support.append({"slot": slot, "label": label, **source_row(i, rows[i], explicit_support=True)})
    query = sorted((i for i, row in enumerate(rows) if row["writer"] == writer and row["session"] == query_session),
                   key=lambda i: sha(("personal-support-match-defer-v1:query:" + rows[i]["sourceID"]).encode()))
    require(len(query) == len(set(query)) == 97, "Episode must retain all97 distinct queries")
    batch = [{"sourceIndex": s["sourceIndex"], "role": "storedSupport", "supportSlot": s["slot"], "rasterSHA256": s["storedRasterSHA256"]}
             for s in support if s["storedFailure"] is None]
    query_offset = len(batch)
    available = [s for s in support if s["storedFailure"] is None]
    issues = (["no-available-stored-support"] if not available else []) + ["duplicate-" + key for key in
        ("sourceID", "storedRasterSHA256", "storedTrajectorySHA256") if len({s[key] for s in available}) != len(available)]
    prototype_labels = sorted({s["label"] for s in available})
    batch += [{"sourceIndex": i, "role": "rawQuery", "queryPosition": p, "rasterSHA256": rows[i]["rawRasterSHA256"]} for p, i in enumerate(query)]
    return {"episodeID": f"{fold}:{writer}:query{query_session}:{catalog}", "writer": writer, "querySession": query_session,
            "supportSession": 3 - query_session, "supportWriter": support_writer, "catalog": catalog, "support": support,
            "querySourceIndices": query, "queryBatchOffset": query_offset, "batchSources": batch, "batchSHA256": sha(canonical(batch)),
            "scheduledSupportSlots": len(support), "availableSupportRows": query_offset,
            "profileUsable": not issues, "profileIssues": issues,
            "requestedSupportLabels": list(TASKS[catalog]), "availablePrototypeLabels": prototype_labels,
            "prototypeIndexBySupportSlot": [prototype_labels.index(s["label"]) if s["storedFailure"] is None else None for s in support],
            "unavailableSupportSlots": [s["slot"] for s in support if s["storedFailure"] is not None]}


COPY_FIELDS = (("raw-raster", "rawRasterSHA256", "rawRasterSHA256"), ("stored-raster", "rawRasterSHA256", "storedRasterSHA256"),
               ("raw-trajectory", "trajectorySHA256", "trajectorySHA256"), ("stored-trajectory", "trajectorySHA256", "storedTrajectorySHA256"))


def copy_sets(groups):
    return {name: {kind: {s[support_key] for s in sources if s[support_key] is not None}
                  for kind, _, support_key in COPY_FIELDS} for name, sources in groups.items()}


def copy_reasons(query, groups):
    reasons = []
    for name, sources in groups.items():
        for kind, query_key, _ in COPY_FIELDS:
            if query[query_key] in sources[kind]:
                reasons.append(name + "-" + kind + "-copy")
    return reasons


def epoch_schedule(episodes):
    generator = torch.Generator().manual_seed(SEED)
    epochs = []
    for epoch in range(EPOCHS):
        order = sorted(episodes, key=lambda e: sha(("personal-support-match-defer-v1:epoch:" + str(epoch) + e["episodeID"]).encode()))
        updates = []
        for e in order:
            before = sha(generator.get_state().numpy().tobytes())
            draws = torch.rand((len(e["batchSources"]), 4), generator=generator)
            updates.append({"episodeID": e["episodeID"], "batchSHA256": e["batchSHA256"], "batchRows": len(e["batchSources"]),
                "augmentationDrawsSHA256": sha(draws.numpy().tobytes()), "generatorBeforeSHA256": before,
                "generatorAfterSHA256": sha(generator.get_state().numpy().tobytes())})
        require(len(updates) == EPISODES_PER_EPOCH, "Epoch episode count changed")
        epochs.append({"epoch": epoch, "updates": updates, "scheduleSHA256": sha(canonical(updates))})
    return epochs


def build_plan(receipt, metadata, *, receipt_sha256, metadata_sha256, domain_data, domain_sha256, protocol_sha256=PROTOCOL_SHA256):
    rows, vocabulary = validate_metadata(receipt, metadata, receipt_sha256, metadata_sha256)
    require(protocol_sha256 == PROTOCOL_SHA256, "Fixed protocol digest required")
    domain = validate_domain(domain_data, domain_sha256, vocabulary)
    lookup = {(r["writer"], r["session"], r["label"]): i for i, r in enumerate(rows)}
    forward, targets, ledgers, counts = {}, {}, {}, {}
    for fit_fold, heldout_fold in (("A", "B"), ("B", "A")):
        direction = fit_fold + "16-to-" + heldout_fold + "16"
        fit_writers, heldout_writers = receipt["folds"][fit_fold], receipt["folds"][heldout_fold]
        training, heldout, target_rows, ledger, episode_evidence = [], [], [], [], []
        for writer in fit_writers:
            for session in (1, 2):
                for catalog in TASKS:
                    e = episode(rows, lookup, writer, session, catalog, writer, fit_fold)
                    training.append(e); slots = {label: index for index, label in enumerate(e["availablePrototypeLabels"])}
                    for position, i in enumerate(e["querySourceIndices"]):
                        label = rows[i]["label"]
                        target_rows.append({"episodeID": e["episodeID"], "queryPosition": position, "sourceIndex": i,
                            "genericClassIndex": vocabulary.index(label), "matchPrototypeIndex": slots.get(label), "defer": label not in slots,
                            "matchDeferClassIndex": slots.get(label, len(slots)),
                            "cohort": "taught" if label in slots else "requestedSupportUnavailable" if label in TASKS[catalog] else "untaught"})
        fit_indices = sorted({i for e in training for i in e["querySourceIndices"]})
        fitted_stored = sorted({s["sourceIndex"] for e in training for s in e["support"] if s["storedFailure"] is None})
        fit_sources = [source_row(i, rows[i]) for i in fit_indices]
        # Only selected catalog setup images, not every stored class, are fitted.
        fit_stored_sources = [{**source_row(i, rows[i]), "rawRasterSHA256": None, "trajectorySHA256": None} for i in fitted_stored]
        for rank, writer in enumerate(heldout_writers):
            donor = heldout_writers[(rank + 1) % len(heldout_writers)]
            for session in (1, 2):
                for catalog in TASKS:
                    true = episode(rows, lookup, writer, session, catalog, writer, heldout_fold)
                    wrong = episode(rows, lookup, writer, session, catalog, donor, heldout_fold)
                    require(true["querySourceIndices"] == wrong["querySourceIndices"] and donor != writer, "Wrong support changed query source schedule")
                    groups = copy_sets({"encoder-fit": [{**s, "storedRasterSHA256": None, "storedTrajectorySHA256": None} for s in fit_sources] + fit_stored_sources,
                                        "true-support": true["support"], "wrong-support": wrong["support"]})
                    eligible_cohorts = {"taught": 0, "untaught": 0, "requestedSupportUnavailable": 0}
                    for position, i in enumerate(true["querySourceIndices"]):
                        reasons = copy_reasons(rows[i], groups)
                        ledger.append({"episodeID": true["episodeID"], "queryPosition": position, "sourceIndex": i,
                            "reasons": reasons})
                        if not reasons:
                            label = rows[i]["label"]
                            cohort = "taught" if label in true["availablePrototypeLabels"] else "requestedSupportUnavailable" if label in TASKS[catalog] else "untaught"
                            eligible_cohorts[cohort] += 1
                    same_coverage = set(true["availablePrototypeLabels"]) == set(wrong["availablePrototypeLabels"])
                    heldout.append({"trueSupport": true, "wrongSupport": wrong, "availableLabelSetsEqual": same_coverage,
                        "batchNormalization": "eval-fixed-training-statistics-no-heldout-updates"})
                    episode_evidence.append({"episodeID": true["episodeID"], "sourceOnlyEligibleCohortCounts": eligible_cohorts, "evidenceUnavailable": not
                        (same_coverage and true["profileUsable"] and wrong["profileUsable"] and eligible_cohorts["taught"] and eligible_cohorts["untaught"])})
        epochs = epoch_schedule(training)
        require(len(training) == len(heldout) == 64 and len(fit_indices) == 3104 and len(target_rows) == len(ledger) == 6208, "Fixed fold schedule changed")
        forward[direction] = {"fitWriters": fit_writers, "heldoutWriters": heldout_writers, "trainingEpisodes": training,
            "epochs": epochs, "heldoutEpisodes": heldout, "matchedArmScheduleSHA256": {arm: sha(canonical(epochs)) for arm in ARMS}}
        targets[direction], ledgers[direction] = target_rows, {"queryRows": ledger, "episodeEvidence": episode_evidence}
        available_per_epoch = sum(e["availableSupportRows"] for e in training)
        counts[direction] = {"updatesPerArm": 1920, "trainingRawDistinctSources": 3104, "trainingQueryExposuresPerEpoch": 6208,
            "trainingRawDistinctRasterHashes": len({rows[i]["rawRasterSHA256"] for i in fit_indices}),
            "trainingStoredDistinctRasterHashes": len({rows[i]["storedRasterSHA256"] for i in fitted_stored}),
            "trainingRawQueryExposures": EPOCHS * 6208, "trainingStoredDistinctSources": len(fitted_stored),
            "trainingScheduledSupportSlotsPerEpoch": 992, "trainingAvailableSupportExposuresPerEpoch": available_per_epoch,
            "trainingUnavailableSupportSlotsPerEpoch": 992 - available_per_epoch,
            "unusableTrainingEpisodes": sum(not e["profileUsable"] for e in training),
            "numericalFitAllowed": all(e["profileUsable"] for e in training),
            "evidenceUnavailableHeldoutEpisodes": sum(e["evidenceUnavailable"] for e in episode_evidence),
            "mismatchedAvailableLabelSetEpisodes": sum(not e["availableLabelSetsEqual"] for e in heldout),
            "trainingEncodedRows": EPOCHS * (6208 + available_per_epoch), "heldoutDistinctQuerySources": 3104,
            "heldoutCatalogQueryExposures": 6208, "heldoutCopyExcludedExposures": sum(bool(r["reasons"]) for r in ledger),
            "heldoutCopyEligibleExposures": sum(not r["reasons"] for r in ledger)}
    return {"version": VERSION, "protocolSHA256": protocol_sha256, "protocolBindingDeferred": False,
        "bindings": {"sourceSHA256": SOURCE_SHA256, "crossfitReceiptSHA256": receipt_sha256, "metadataSHA256": metadata_sha256,
            "parentCodeSHA256": receipt["codeSHA256"], "codeSHA256": code_identity(), "domainSHA256": domain_sha256},
        "vocabulary": vocabulary, "allowedLabels": domain["allowedLabels"],
        "catalogs": {k: list(v) for k, v in TASKS.items()}, "sourceLedger": [source_row(i, row) for i, row in enumerate(rows)],
        "setupAdapter": {"function": "personal_support_crossfit.setup_shape", "supportAdapterGolden": receipt["supportAdapterGolden"]},
        "recipe": {"seed": SEED, "epochs": EPOCHS, "episodesPerEpoch": 64, "arms": list(ARMS), "optimizer": "AdamW", "cpuThreads": 4,
            "initialization": "one-complete-seed29-state-deepcopied-both-arms-and-both-folds-including-buffers",
            "learningRate": .001, "weightDecay": .0001, "scheduler": {"name": "CosineAnnealingLR", "tMax": 1920, "stepPer": "optimizer-update"},
            "selection": "final-epoch-only-no-heldout-selection",
            "episodeOrder": "SHA256(personal-support-match-defer-v1:epoch: + zeroBasedEpoch + episodeID)",
            "augmentation": "original-augment-affine-shared-seed29-torch-generator-4-draws-per-concatenated-row",
            "encoderBatch": "available-stored-support-then-all97-rawqueries-single-forward-identical-between-arms"},
        "forward": forward, "trainingTargets": targets,
        "trainingTargetBindings": {direction: {"path": direction + "-training-targets.json", "SHA256": sha(canonical(value)), "rows": len(value)} for direction, value in targets.items()},
        "scoringLedgerBindings": {direction: {"path": direction + "-scoring-ledger.json", "SHA256": sha(canonical(value)), "queryRows": len(value["queryRows"])} for direction, value in ledgers.items()},
        "sourceCopyLedger": ledgers, "counts": counts,
        "runtime": {"python": platform.python_version(), "torch": str(torch.__version__)},
        "roleGuards": {"sourceOnly": True, "rastersConstructed": False, "encoderInferencePerformed": False, "optimizationPerformed": False,
            "heldoutTruthAttachedToForward": False, "developmentOrReservedSamplesOpened": False, "privateInkUsed": False,
            "independentPhysicalSamplesCertified": False, "productionEligible": False}}


def prepare(directory, output, *, receipt_sha256, domain_path, domain_sha256, protocol_sha256=PROTOCOL_SHA256):
    directory, output = Path(directory), Path(output)
    data = {name: read(directory / name) for name in ("fit-receipt.json", "fit-plan.json", "metadata.json")}
    receipt, old_plan, metadata = (parsed(data[name]) for name in ("fit-receipt.json", "fit-plan.json", "metadata.json"))
    require(sha(data["fit-receipt.json"]) == receipt_sha256 and sha(data["fit-plan.json"]) == receipt["fitPlanSHA256"] == PARENT["plan"]
            and all(receipt.get(k) == v for k, v in old_plan.items()), "Cached receipt/plan binding changed")
    domain_data = read(domain_path)
    result = build_plan(receipt, metadata, receipt_sha256=receipt_sha256, metadata_sha256=sha(data["metadata.json"]),
        domain_data=domain_data, domain_sha256=domain_sha256, protocol_sha256=protocol_sha256)
    require(output.is_absolute() and output.parent.resolve() == output.parent and output.parent.is_dir() and not output.exists()
            and ROOT not in output.parents and directory not in output.parents, "Fresh outside-source/parent output required")
    output.mkdir()
    targets, ledgers, counts = (result.pop(name) for name in ("trainingTargets", "sourceCopyLedger", "counts"))
    require(all(read(directory / name) == value for name, value in data.items()) and read(domain_path) == domain_data
            and code_identity() == result["bindings"]["codeSHA256"], "Source/code changed during planning")
    artifacts_to_write = {"forward-plan.json": result,
        **{direction + "-training-targets.json": value for direction, value in targets.items()},
        **{direction + "-scoring-ledger.json": value for direction, value in ledgers.items()}}
    for name, value in artifacts_to_write.items():
        with (output / name).open("xb") as stream:
            stream.write(canonical(value))
    artifacts = {name: sha(canonical(value)) for name, value in artifacts_to_write.items()}
    require(all(sha(read(output / name)) == expected for name, expected in artifacts.items())
            and code_identity() == result["bindings"]["codeSHA256"] and read(domain_path) == domain_data
            and all(read(directory / name) == value for name, value in data.items()), "Frozen plan/targets/source/code changed during writing")
    new_receipt = {"version": VERSION, "bindings": result["bindings"], "protocolSHA256": protocol_sha256,
                   "artifacts": artifacts, "counts": counts, "sourceOnly": True, "optimizationPerformed": False}
    with (output / "plan-receipt.json").open("xb") as stream:
        stream.write(canonical(new_receipt))
    return new_receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--crossfit", type=Path, required=True); p.add_argument("--output", type=Path, required=True)
    p.add_argument("--receipt-sha256", required=True); p.add_argument("--protocol-sha256", default=PROTOCOL_SHA256)
    p.add_argument("--domain", type=Path, required=True); p.add_argument("--domain-sha256", required=True)
    a = p.parse_args(); result = prepare(a.crossfit, a.output, receipt_sha256=a.receipt_sha256, domain_path=a.domain,
        domain_sha256=a.domain_sha256, protocol_sha256=a.protocol_sha256)
    print(json.dumps({"output": str(a.output), "sourceOnly": True, "counts": result["counts"]}, sort_keys=True))


if __name__ == "__main__":
    main()

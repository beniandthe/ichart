"""Frozen training-only additive-residual diagnostic; no model computation."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import platform
from pathlib import Path
import re
import stat

import numpy as np

VERSION = "personal-training-residual-signal-v1"
PROTOCOL = "docs/personal-training-residual-signal-protocol-2026-10-01.md"
PROTOCOL_SHA256 = "247301a14155232a22004bedf57e9f47029874a7b49c840a0041f5ec08559a52"
CODE_FILES = (PROTOCOL,
    "recognition_ml/ichart_recognition_ml/research/personal_training_residual_signal.py",
    "recognition_ml/tests/test_personal_training_residual_signal.py")
INPUT_SHA256 = {
    "centroid-receipt.json": "c4c895caee391b6076018244b9b5a8a19230c8052a95776d0d7459a90dea9bad",
    "training-features.npz": "78f220cfe8052d847ba9c6119c747decd0c0243dd0d66b8ebd0413516aff5163",
    "training-rows.json": "0fd4d41c38070a43bc1e13ba89f38cd03f558a6876b1785f6d58dd9c89748c73",
}
WEIGHTS_SHA256 = "1cfbcd2c11fe5173bbd7367121fdb9c4c1d965618d9272a6c7421dd6901261c1"
STATE_SHA256 = "42307941fda891c989149585727fdf402f442edfa6a1e8c155429c6719618286"
SOURCE_SHA256 = "cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61"
TASKS = {"core10": list("ABCDEFGb-7"), "catalog21": list("ABCDEFGb-7mo6924513()")}
ROW_KEYS = {"sourceID", "writer", "session", "label", "rawRasterSHA256", "trajectorySHA256", "generator"}
HASH = re.compile(r"[0-9a-f]{64}")
WRITER = re.compile(r"trn_(?:UJI|UPV)_W[0-9]{2}")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def regular_bytes(path):
    path = Path(path)
    require(stat.S_ISREG(path.lstat().st_mode), f"Regular non-symlink input required: {path.name}")
    return path.read_bytes()


def code_identity():
    root = Path(__file__).resolve().parents[3]
    result = {name: sha(regular_bytes(root / name)) for name in CODE_FILES}
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Frozen residual protocol changed")
    return result


def input_identity(directory):
    return {name: sha(regular_bytes(Path(directory) / name)) for name in INPUT_SHA256}


def validate_grid(rows, writers, vocabulary, tasks):
    """Complete small synthetic grids are allowed here; the CLI is exact A16."""
    require(isinstance(writers, (list, tuple)) and len(writers) >= 2
        and all(isinstance(w, str) and w for w in writers) and len(writers) == len(set(writers)),
        "Unique fitting writers required")
    require(isinstance(vocabulary, (list, tuple)) and len(vocabulary) >= 2
        and all(isinstance(c, str) and len(c) == 1 and not c.isspace() for c in vocabulary)
        and list(vocabulary) == sorted(set(vocabulary)), "Sorted unique character vocabulary required")
    require(isinstance(tasks, dict) and tasks and all(isinstance(k, str) and k
        and isinstance(v, (list, tuple)) and 0 < len(v) == len(set(v)) < len(vocabulary)
        and set(v) <= set(vocabulary) for k, v in tasks.items()), "Nonempty exact support catalogs required")
    require(isinstance(rows, list) and len(rows) == len(writers) * 2 * len(vocabulary)
        and all(isinstance(r, dict) and set(r) == ROW_KEYS and r["writer"] in writers
            and type(r["session"]) is int and r["session"] in (1, 2) and r["label"] in vocabulary
            and r["sourceID"] == f'{r["writer"]}-{r["session"]}-{r["label"]}' and r["generator"] == "fitA"
            and all(isinstance(r[k], str) and HASH.fullmatch(r[k]) for k in ("rawRasterSHA256", "trajectorySHA256"))
            for r in rows), "Complete bound fitA source rows required")
    require([r["sourceID"] for r in rows] == sorted({r["sourceID"] for r in rows})
        and {(r["writer"], r["session"], r["label"]) for r in rows}
            == {(w, s, c) for w in writers for s in (1, 2) for c in vocabulary}, "Source grid/order changed")


def validate_features(features, rows):
    require(isinstance(features, np.ndarray) and features.dtype == np.float32 and features.ndim == 2
        and features.shape[0] == len(rows) and 1 <= features.shape[1] <= 2048
        and np.isfinite(features).all()
        and np.allclose(np.linalg.norm(features.astype(np.float64), axis=1), 1, rtol=1e-4, atol=1e-5),
        "Finite raw float32 unit embeddings required")


def load_inputs(directory):
    """Only the three pinned training-domain files are opened, never a checkpoint."""
    directory = Path(directory)
    blobs = {name: regular_bytes(directory / name) for name in INPUT_SHA256}
    require({name: sha(data) for name, data in blobs.items()} == INPUT_SHA256, "Pinned training inputs changed")
    receipt = json.loads(blobs["centroid-receipt.json"])
    source = json.loads(blobs["training-rows.json"])
    require(blobs["centroid-receipt.json"] == canonical(receipt)
        and blobs["training-rows.json"] == canonical(source), "Canonical bound JSON required")
    require(isinstance(receipt, dict) and receipt.get("version") == "personal-fitA-training-centroids-v1"
        and receipt.get("generator") == "fitA" and receipt.get("generatorWeightsSHA256") == WEIGHTS_SHA256
        and receipt.get("generatorStateSHA256") == STATE_SHA256 and receipt.get("sourceSHA256") == SOURCE_SHA256
        and isinstance(receipt.get("parentBinding"), dict)
        and receipt["parentBinding"].get("weights/fitA.pt") == WEIGHTS_SHA256
        and receipt.get("sourceCount") == 3104 and receipt.get("countPerLabel") == 32
        and receipt.get("storedUnavailableRawRowsRetained") == 12
        and receipt.get("trainingFeaturesSHA256") == INPUT_SHA256["training-features.npz"]
        and receipt.get("trainingRowsSHA256") == INPUT_SHA256["training-rows.json"]
        and receipt.get("inSampleTrainingCentroids") is True and receipt.get("sourceAndEncoderUnchanged") is True
        and receipt.get("privateInkUsed") is False and receipt.get("developmentOrReservedInferred") is False
        and receipt.get("productionEligible") is False, "Pinned fitA training provenance required")
    require(isinstance(source, dict) and set(source) == {"vocabulary", "rows"}
        and source["vocabulary"] == receipt.get("vocabulary"), "Bound source vocabulary required")
    writers, vocabulary, rows = receipt.get("encoderFitWriters"), source["vocabulary"], source["rows"]
    validate_grid(rows, writers, vocabulary, TASKS)
    require(len(writers) == 16 and all(WRITER.fullmatch(w) for w in writers) and len(vocabulary) == 97,
        "Exact pinned A16/full97 roles required")
    with np.load(io.BytesIO(blobs["training-features.npz"]), allow_pickle=False) as bundle:
        require(bundle.files == ["features"], "Raw-only training array required")
        features = bundle["features"].copy()
    validate_features(features, rows)
    require(features.shape == (3104, 128), "Exact A16 feature dimensions required")
    features.flags.writeable = False
    return features, rows, writers, vocabulary, receipt


def _matches(query, candidates, key):
    return sorted(r["sourceID"] for r in candidates if r[key] == query[key])


def make_plan(rows, writers, vocabulary, tasks):
    """Source-only lesson, donor, query and complete copy plan; no vectors."""
    validate_grid(rows, writers, vocabulary, tasks)
    lookup = {(r["writer"], r["session"], r["label"]): r for r in rows}
    cells = []
    for writer in writers:
        donors = [w for w in writers if w != writer]
        contributors = [r for r in rows if r["writer"] != writer]
        for task, support_labels in tasks.items():
            for session in (1, 2):
                support = [lookup[writer, session, c] for c in support_labels]
                queries = []
                for label in vocabulary:
                    if label in support_labels:
                        continue
                    query = lookup[writer, 3 - session, label]
                    reasons = []
                    for group, candidates in (("prototype", contributors), ("own-support", support)):
                        for kind, key in (("raw-raster", "rawRasterSHA256"), ("normalized-trajectory", "trajectorySHA256")):
                            matches = _matches(query, candidates, key)
                            if matches:
                                reasons.append({"reason": f"{group}-{kind}-copy", "matchingSourceIDs": matches})
                    queries.append({"sourceID": query["sourceID"], "copyReasons": reasons})
                cells.append({"cellID": f"{writer}:{task}:{session}->{3 - session}", "writer": writer, "task": task,
                    "supportSession": session, "querySession": 3 - session, "supportLabels": list(support_labels),
                    "ownSupportSources": [r["sourceID"] for r in support], "donors": donors,
                    "donorSupportSources": {w: [lookup[w, session, c]["sourceID"] for c in support_labels] for w in donors},
                    "prototypeContributorWriters": donors, "prototypeSessions": [1, 2],
                    "prototypeLabels": list(vocabulary), "queries": queries})
    return {"version": VERSION, "writers": list(writers), "vocabulary": list(vocabulary),
        "tasks": {k: list(v) for k, v in tasks.items()}, "sourceRowsSHA256": sha(canonical(rows)), "cells": cells}


def focal_means(features, rows, writers, vocabulary, focal):
    """Unnormalized float64 means, balanced by session; shared by every donor."""
    require(focal in writers, "Unknown focal writer")
    lookup = {(r["writer"], r["session"], r["label"]): i for i, r in enumerate(rows)}
    result = {}
    for label in vocabulary:
        sessions = [features[[lookup[w, s, label] for w in writers if w != focal]].astype(np.float64).mean(0)
            for s in (1, 2)]
        result[label] = (sessions[0] + sessions[1]) / 2
    return result


def evaluate(features, rows, writers, vocabulary, tasks, plan):
    validate_grid(rows, writers, vocabulary, tasks)
    validate_features(features, rows)
    require(plan == make_plan(rows, writers, vocabulary, tasks), "Frozen source-only plan changed")
    lookup = {r["sourceID"]: (i, r) for i, r in enumerate(rows)}
    means = {w: focal_means(features, rows, writers, vocabulary, w) for w in writers}
    records = []
    for cell in plan["cells"]:
        focal = means[cell["writer"]]
        supports = {cell["writer"]: cell["ownSupportSources"], **cell["donorSupportSources"]}
        styles = {w: np.stack([features[lookup[s][0]].astype(np.float64) - focal[lookup[s][1]["label"]]
            for s in sources]).mean(0) for w, sources in supports.items()}
        for query in cell["queries"]:
            index, source = lookup[query["sourceID"]]
            residual = features[index].astype(np.float64) - focal[source["label"]]
            squared = lambda vector: float(np.sum(vector * vector, dtype=np.float64))
            donors = {w: squared(residual - styles[w]) for w in cell["donors"]}
            errors = {"zero": squared(residual), "focal": squared(residual - styles[cell["writer"]]),
                "unrelated": float(np.mean(list(donors.values()))), "donors": donors}
            require(all(np.isfinite(v) and v >= 0 for v in
                [errors["zero"], errors["focal"], errors["unrelated"], *donors.values()]), "Nonfinite residual error")
            records.append({"cellID": cell["cellID"], "task": cell["task"], "writer": cell["writer"],
                "supportSession": cell["supportSession"], "querySession": cell["querySession"],
                "source": dict(source), "copyReasons": query["copyReasons"], "errors": errors})
    return records


def _counts(records):
    eligible = [r for r in records if not r["copyReasons"]]
    excluded = [r for r in records if r["copyReasons"]]
    distinct = lambda values: len({r["source"]["sourceID"] for r in values})
    return {"scheduledExposures": len(records), "distinctScheduledSources": distinct(records),
        "repeatedScheduledExposures": len(records) - distinct(records), "eligibleExposures": len(eligible),
        "distinctEligibleSources": distinct(eligible), "repeatedEligibleExposures": len(eligible) - distinct(eligible),
        "excludedExposures": len(excluded), "distinctExcludedSources": distinct(excluded)}


def _errors(records):
    sums = {k: float(sum(r["errors"][k] for r in records)) for k in ("zero", "focal", "unrelated")}
    return {"queryExposures": len(records), "sumSquaredError": sums,
        "meanSquaredError": {k: v / len(records) if records else None for k, v in sums.items()}}


def summarize(records):
    return {"counts": _counts(records), "rawScheduled": _errors(records),
        "sourceOnlyNoCopy": _errors([r for r in records if not r["copyReasons"]])}


def screen(records, plan):
    """Predeclared primary task and query-weighted writer screen, including empty cells."""
    summaries = {"overall": summarize(records), "cells": {}, "tasks": {}, "writers": {}}
    for cell in plan["cells"]:
        selected = [r for r in records if r["cellID"] == cell["cellID"]]
        summaries["cells"][cell["cellID"]] = summarize(selected)
    for task in plan["tasks"]:
        summaries["tasks"][task] = summarize([r for r in records if r["task"] == task])
        for writer in plan["writers"]:
            summaries["writers"].setdefault(writer, {})[task] = summarize(
                [r for r in records if r["writer"] == writer and r["task"] == task])
    finite = all(np.isfinite(v) and v >= 0 for r in records
        for v in [r["errors"][k] for k in ("zero", "focal", "unrelated")] + list(r["errors"]["donors"].values()))
    nonempty = all(s["sourceOnlyNoCopy"]["queryExposures"] > 0 for s in summaries["cells"].values())
    task_conditions, writer_conditions = {}, {}
    for task, summary in summaries["tasks"].items():
        errors = summary["sourceOnlyNoCopy"]["meanSquaredError"]
        task_conditions[task] = {"strictlyBelowZero": errors["focal"] is not None and errors["focal"] < errors["zero"],
            "strictlyBelowMeanUnrelated": errors["focal"] is not None and errors["focal"] < errors["unrelated"]}
    for writer, tasks in summaries["writers"].items():
        writer_conditions[writer] = {}
        for task, summary in tasks.items():
            errors = summary["sourceOnlyNoCopy"]["meanSquaredError"]
            writer_conditions[writer][task] = {"noWorseThanZero": errors["focal"] is not None and errors["focal"] <= errors["zero"],
                "noWorseThanMeanUnrelated": errors["focal"] is not None and errors["focal"] <= errors["unrelated"]}
    passed = finite and nonempty and all(all(c.values()) for c in task_conditions.values()) \
        and all(all(c.values()) for tasks in writer_conditions.values() for c in tasks.values())
    return {"summaries": summaries, "fixedScreen": {"finiteOutputs": bool(finite), "nonemptyEligibleCells": nonempty,
        "taskConditions": task_conditions, "writerConditions": writer_conditions, "passed": bool(passed),
        "disposition": "evidence-for-new-query-canonicalization-protocol" if passed else "stop-single-additive-support-mean"},
        "inSampleTrainingDiagnostic": True, "optimisticRawSupportGeometry": True, "newWriterEvidence": False,
        "recognitionAccuracyComputed": False, "encoderOrScorerInferencePerformed": False, "optimizerPerformed": False,
        "productionEligible": False}


def _fresh_output(path):
    path = Path(path)
    require(path.is_absolute() and path.parent.is_dir() and not path.exists() and not path.is_symlink(),
        "Fresh absolute output with existing parent required")
    path = path.resolve()
    root = Path(__file__).resolve().parents[3]
    require(not path.is_relative_to(root) and not any((p / ".git").exists() for p in (path.parent, *path.parent.parents)),
        "Diagnostic output must be outside Git")
    return path


def _publish(path, value):
    data = canonical(value)
    with Path(path).open("xb") as stream:
        stream.write(data)
    return sha(data)


def run(centroid_directory, output):
    output = _fresh_output(output)
    code_before, inputs_before = code_identity(), input_identity(centroid_directory)
    require(inputs_before == INPUT_SHA256, "Pinned training inputs changed")
    features, rows, writers, vocabulary, _ = load_inputs(centroid_directory)
    plan = make_plan(rows, writers, vocabulary, TASKS)
    require(code_identity() == code_before and input_identity(centroid_directory) == inputs_before,
        "Inputs/code changed before plan publication")
    output.mkdir(mode=0o700)
    plan_packet = {"version": VERSION, "inputSHA256": inputs_before, "codeSHA256": code_before,
        "runtime": {"python": platform.python_version(), "numpy": str(np.__version__)}, "plan": plan}
    plan_sha = _publish(output / "plan.json", plan_packet)
    records = evaluate(features, rows, writers, vocabulary, TASKS, plan)
    report = screen(records, plan)
    require(report["summaries"]["overall"]["counts"]["scheduledExposures"] == 5216
        and report["summaries"]["overall"]["counts"]["distinctScheduledSources"] == 2784
        and report["summaries"]["tasks"]["core10"]["counts"]["scheduledExposures"] == 2784
        and report["summaries"]["tasks"]["catalog21"]["counts"]["scheduledExposures"] == 2432
        and len(plan["cells"]) == 64, "Fixed scheduled denominator changed")
    code_after, inputs_after = code_identity(), input_identity(centroid_directory)
    require(code_after == code_before and inputs_after == inputs_before, "Inputs/code changed before geometry publication")
    require(regular_bytes(output / "plan.json") == canonical(plan_packet), "Published plan changed")
    geometry_sha = _publish(output / "geometry.json", {"version": VERSION, "planSHA256": plan_sha, "records": records})
    require(code_identity() == code_before and input_identity(centroid_directory) == inputs_before,
        "Inputs/code changed before screen publication")
    summary_sha = _publish(output / "summary.json", {"version": VERSION, "planSHA256": plan_sha,
        "geometrySHA256": geometry_sha, **report})
    code_final, inputs_final = code_identity(), input_identity(centroid_directory)
    require(code_final == code_before and inputs_final == inputs_before,
        "Inputs/code changed before receipt publication")
    require(all(sha(regular_bytes(output / name)) == digest for name, digest in
        (("plan.json", plan_sha), ("geometry.json", geometry_sha), ("summary.json", summary_sha))),
        "Published artifacts changed before receipt publication")
    receipt = {"version": VERSION, "inputBeforeSHA256": inputs_before, "inputAfterSHA256": inputs_final,
        "codeBeforeSHA256": code_before, "codeAfterSHA256": code_final, "planSHA256": plan_sha,
        "geometrySHA256": geometry_sha, "summarySHA256": summary_sha, "trainingSourceCount": len(rows),
        "sourceAndCodeUnchanged": True, "fitAInSampleOnly": True, "pooledFeaturesOrCheckpointOpened": False,
        "encoderOrScorerInferencePerformed": False, "optimizerPerformed": False, "productionEligible": False}
    _publish(output / "receipt.json", receipt)
    return {"output": str(output), "scheduledExposures": 5216, "cells": 64,
        "passed": report["fixedScreen"]["passed"], "disposition": report["fixedScreen"]["disposition"],
        "summarySHA256": summary_sha}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    command = sub.add_parser("run")
    command.add_argument("--centroid-directory", required=True, type=Path)
    command.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(run(args.centroid_directory, args.output), sort_keys=True))


if __name__ == "__main__":
    main()

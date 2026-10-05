"""Fixed training-only cache feasibility audit, never a fitted candidate.

Prediction has no query-answer argument. Its full distributions are frozen
before explicitly training-only scoring. Alpha is a diagnostic grid, not a
chosen setting or new development evaluation.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import platform
import re

import numpy as np
import torch
from torch.nn import functional as F

from . import personal_support_crossfit as crossfit
from . import personal_support_retrieval as retrieval
from .personal_cross_writer_contrastive import _regular_file, _write_exclusive
from .uji_personal import SOURCE_SHA256

VERSION = "personal-support-signal-audit-v1"
ALPHAS = (0., .01, .03, .05, .1, .2, .35, .5, .75, 1.)
PROTOCOL_PATH = "docs/personal-support-signal-protocol-2026-10-01.md"
PROTOCOL_SHA256 = "71c89c33e0162a0b77591beae6976e6cfec7a99f5651ec043528e3c95c492376"
RECEIPT_SHA256 = "d2a31e73d53b25b812f0ba4f24f812014515606f97a20e6b7170eaf94d0e20d2"
FEATURES_SHA256 = "b1bbb6066ef2bd1d5cc0398df2d9713fb60f6086ec501bb0687fce81976faaef"
_HASH = re.compile(r"[0-9a-f]{64}")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(value):
    return hashlib.sha256(value).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def code_identity():
    root = Path(__file__).resolve().parents[3]
    result = {**crossfit.code_identity(), **retrieval.code_identity()}
    for path in (PROTOCOL_PATH, "recognition_ml/ichart_recognition_ml/research/personal_support_signal_audit.py",
                 "recognition_ml/tests/test_personal_support_signal_audit.py"):
        result[path] = sha((root / path).read_bytes())
    require(result[PROTOCOL_PATH] == PROTOCOL_SHA256, "Signal audit protocol changed")
    return result


def input_identity(directory):
    return {name: sha(_regular_file(Path(directory) / name, "cross-fit audit input").read_bytes())
        for name in ("fit-receipt.json", "fit-plan.json", "metadata.json", "features.npz", "protocol.md",
                     "weights/fitA.pt", "weights/fitB.pt")}


def validate_bundle(arrays, rows, receipt):
    vocabulary = receipt["vocabulary"]
    writers = tuple(sorted({row["writer"] for row in rows}))
    require(len(vocabulary) == 97 and vocabulary == sorted(set(vocabulary)), "Exact sorted vocabulary97 required")
    require(len(rows) == 6208 and len(writers) == 32 and all(re.fullmatch(r"trn_(?:UJI|UPV)_W[0-9]{2}", writer) for writer in writers)
        and sorted(receipt["trainingWriters"]) == list(writers)
        and not set(writers) & (set(receipt["developmentWriters"]) | set(receipt["reservedWriters"]))
        and set(receipt["folds"]) == {"A", "B"} and all(len(set(receipt["folds"][key])) == 16 for key in ("A", "B"))
        and set(receipt["folds"]["A"]) | set(receipt["folds"]["B"]) == set(writers)
        and not set(receipt["folds"]["A"]) & set(receipt["folds"]["B"]), "Non-training or overlapping source writers")
    require(all(type(row["session"]) is int and row["session"] in (1, 2)
        and row["sourceID"] == f'{row["writer"]}-{row["session"]}-{row["label"]}'
        and row["label"] in vocabulary
        and row["generator"] == ("fitA" if row["writer"] in receipt["folds"]["B"] else "fitB")
        and all(isinstance(row[key], str) and _HASH.fullmatch(row[key]) for key in ("rawRasterSHA256", "trajectorySHA256"))
        and all(row[key] is None or isinstance(row[key], str) and _HASH.fullmatch(row[key]) for key in ("storedRasterSHA256", "storedTrajectorySHA256"))
        and ((row["storedRasterSHA256"] is None) == (row["storedTrajectorySHA256"] is None) == (row["storedFailure"] is not None))
        for row in rows), "Source identity, geometry, role or availability changed")
    require(len({row["sourceID"] for row in rows}) == 6208
        and [row["sourceID"] for row in rows] == sorted(row["sourceID"] for row in rows)
        and {(row["writer"], row["session"], row["label"]) for row in rows}
            == {(writer, session, label) for writer in writers for session in (1, 2) for label in vocabulary}, "Incomplete query/source grid")
    shapes = {"raw_features": (6208, 128), "raw_logits": (6208, 97), "stored_features": (6208, 128),
              "stored_logits": (6208, 97), "stored_available": (6208,)}
    require(set(arrays) == set(shapes) and all(isinstance(arrays[name], np.ndarray) and arrays[name].shape == shape
        for name, shape in shapes.items()), "Invalid audit matrices")
    available = arrays["stored_available"]
    require(available.dtype == np.bool_ and available.tolist() == [row["storedFailure"] is None for row in rows]
        and all(value.dtype == np.float32 and np.isfinite(value).all() for name, value in arrays.items() if name != "stored_available")
        and np.allclose(np.linalg.norm(arrays["raw_features"], axis=1), 1, rtol=1e-4, atol=1e-5)
        and np.allclose(np.linalg.norm(arrays["stored_features"][available], axis=1), 1, rtol=1e-4, atol=1e-5)
        and not arrays["stored_features"][~available].any() and not arrays["stored_logits"][~available].any(), "Nonfinite or unavailable audit features")
    # The frozen source-only planner additionally validates copy reasons.
    return retrieval.episode_plan(rows, vocabulary, epochs=1)


def _probability_matrix(value):
    require(isinstance(value, torch.Tensor) and value.ndim == 2 and value.dtype == torch.float64
        and value.device.type == "cpu" and torch.isfinite(value).all() and 2 <= value.shape[1] <= 512
        and torch.all(value >= 0) and torch.all(value <= 1)
        and torch.all(torch.abs(value.sum(1) - 1) <= 1e-8), "Finite normalized float64 probability matrices required")


def cache_evidence(support_features, support_probabilities, support_labels, query_features, query_probabilities):
    """Full-class deterministic cache; no query-answer or learned parameter."""
    _probability_matrix(support_probabilities)
    _probability_matrix(query_probabilities)
    require(isinstance(support_features, torch.Tensor) and support_features.ndim == 2
        and isinstance(query_features, torch.Tensor) and query_features.ndim == 2
        and isinstance(support_labels, torch.Tensor), "Cache tensor matrices required")
    count, width = support_features.shape
    queries, classes = query_probabilities.shape
    require(1 <= count <= 192 and 1 <= queries <= 4096 and 1 <= width <= 2048
        and support_probabilities.shape == (count, classes) and query_features.shape == (queries, width)
        and support_labels.shape == (count,) and support_labels.dtype == torch.long and support_labels.device.type == "cpu"
        and int(support_labels.min()) >= 0 and int(support_labels.max()) < classes, "Invalid cache dimensions/labels")
    require(all(isinstance(value, torch.Tensor) and value.ndim == 2 and value.dtype == torch.float64
        and value.device.type == "cpu" and torch.isfinite(value).all()
        and torch.all(torch.abs(value.norm(dim=1) - 1) <= 1e-3) for value in (support_features, query_features)), "Unit float64 cache features required")
    unique, inverse = torch.unique(torch.cat((support_features, support_probabilities, support_labels[:, None].double()), dim=1),
                                   dim=0, return_inverse=True)
    features, labels = unique[:, :width], unique[:, -1].long()
    multiplicity = torch.bincount(labels, minlength=classes)
    cosine = query_features @ features.T
    attention = (10 * cosine - multiplicity[labels].double().log()).softmax(1)
    cache = attention @ F.one_hot(labels, classes).double()
    _probability_matrix(cache)
    groups = [[index for index, group in enumerate(inverse.tolist()) if group == position] for position in range(len(unique))]
    return cache, {"deduplicatedSupportGroups": groups, "uniqueSupportLabels": labels.tolist(),
        "labelMultiplicity": multiplicity.tolist(), "supportCountBefore": count, "supportCountAfter": len(unique)}


def mixtures(generic, cache):
    _probability_matrix(generic)
    _probability_matrix(cache)
    require(generic.shape == cache.shape, "Mixture vocabulary mismatch")
    result = tuple((1 - alpha) * generic + alpha * cache for alpha in ALPHAS)
    for value in result:
        _probability_matrix(value)
    require(torch.equal(result[0], generic), "Alpha-zero identity failed")
    return result


def predict_episodes(arrays, rows, vocabulary, plans):
    tensors = {name: torch.from_numpy(np.array(arrays[name], dtype=np.float64, copy=True))
        for name in ("raw_features", "raw_logits", "stored_features", "stored_logits")}
    raw_base, stored_base = tensors["raw_logits"].softmax(1), tensors["stored_logits"].softmax(1)
    outputs = []
    for number, episode in enumerate(plans):
        si, qi = episode["support"], episode["queries"]
        support_labels = torch.tensor([vocabulary.index(rows[index]["label"]) for index in si], dtype=torch.long)
        generic = raw_base[qi]
        cache, details = cache_evidence(tensors["stored_features"][si], stored_base[si], support_labels,
                                       tensors["raw_features"][qi], generic)
        blended = mixtures(generic, cache)
        outputs.append({"episodeIndex": number, "writer": episode["writer"], "supportSession": episode["session"],
            "task": f"K{len(si)}", "supportIndices": si, "queryIndices": qi,
            "deduplicatedSupport": details, "genericProbabilities": generic.tolist(), "cacheProbabilities": cache.tolist(),
            "mixtureTop1Indices": [value.argmax(1).tolist() for value in blended]})
    return outputs


def score_training_predictions(predictions, rows, vocabulary):
    """Explicit supervised-training diagnostics only, separate from prediction."""
    observations = []
    for episode in predictions:
        taught = set(episode["deduplicatedSupport"]["uniqueSupportLabels"])
        generic, cache = np.array(episode["genericProbabilities"], dtype=np.float64), np.array(episode["cacheProbabilities"], dtype=np.float64)
        for position, index in enumerate(episode["queryIndices"]):
            truth = vocabulary.index(rows[index]["label"])
            base_top, cache_top = int(generic[position].argmax()), int(cache[position].argmax())
            blended = [(1 - alpha) * generic[position] + alpha * cache[position] for alpha in ALPHAS]
            predicted = [int(value.argmax()) for value in blended]
            require(predicted == [values[position] for values in episode["mixtureTop1Indices"]], "Frozen mixture arithmetic changed")
            observations.append({"episodeIndex": episode["episodeIndex"], "writer": episode["writer"],
                "supportSession": episode["supportSession"], "task": episode["task"], "queryIndex": index,
                "trueLabelIndex": truth, "taught": truth in taught, "genericCorrect": base_top == truth,
                "mixtureCorrect": [label == truth for label in predicted],
                "nll": [-math.log(max(float(value[truth]), 1e-300)) for value in blended],
                "taughtBaselineMistakeTrueCacheTop1": truth in taught and base_top != truth and cache_top == truth,
                "taughtBaselineMistakeTrueCacheCoHighest": truth in taught and base_top != truth and bool(cache[position, truth] == float(cache[position].max())),
                "correctUntaughtOvertaken": [truth not in taught and base_top == truth and label != truth and label in taught for label in predicted]})
    return observations


def summarize(observations):
    require(observations and any(row["taught"] for row in observations) and any(not row["taught"] for row in observations), "Both diagnostic strata required")
    result = []
    for position, alpha in enumerate(ALPHAS):
        cell = {"alpha": alpha, "strata": {}}
        for name, selected in (("all", observations), ("taught", [row for row in observations if row["taught"]]),
                               ("untaught", [row for row in observations if not row["taught"]])):
            gains = sum(not row["genericCorrect"] and row["mixtureCorrect"][position] for row in selected)
            harms = sum(row["genericCorrect"] and not row["mixtureCorrect"][position] for row in selected)
            cell["strata"][name] = {"queryExposures": len(selected), "genericCorrect": sum(row["genericCorrect"] for row in selected),
                "mixtureCorrect": sum(row["mixtureCorrect"][position] for row in selected), "gains": gains, "harms": harms,
                "netCorrect": gains - harms, "meanNLL": float(np.mean([row["nll"][position] for row in selected]))}
        by_episode = defaultdict(list)
        for row in observations:
            by_episode[row["episodeIndex"]].append(row)
        balanced = [.5 * np.mean([row["nll"][position] for row in values if row["taught"]])
                    + .5 * np.mean([row["nll"][position] for row in values if not row["taught"]]) for values in by_episode.values()]
        cell.update({"balancedNLL": float(np.mean(balanced)),
            "balancedNLLDefinition": "mean-of-equal-taught-untaught-episode-NLL",
            "pooledBalancedNLL": .5 * cell["strata"]["taught"]["meanNLL"] + .5 * cell["strata"]["untaught"]["meanNLL"],
            "taughtBaselineMistakes": sum(row["taught"] and not row["genericCorrect"] for row in observations),
            "taughtBaselineMistakesTrueCacheTop1": sum(row["taughtBaselineMistakeTrueCacheTop1"] for row in observations),
            "taughtBaselineMistakesTrueCacheCoHighest": sum(row["taughtBaselineMistakeTrueCacheCoHighest"] for row in observations),
            "correctUntaughtOvertaken": sum(row["correctUntaughtOvertaken"][position] for row in observations)})
        result.append(cell)
    return result


def exposure_counts(indices, rows):
    unique = sorted(set(indices))
    require(all(type(index) is int and 0 <= index < len(rows) for index in indices), "Invalid source exposure index")
    fingerprints = defaultdict(list)
    for index in unique:
        fingerprints[(rows[index]["rawRasterSHA256"], rows[index]["trajectorySHA256"])].append(index)
    return {"queryExposures": len(indices), "distinctSourceIndices": len(unique),
        "distinctRawRasterHashes": len({rows[index]["rawRasterSHA256"] for index in unique}),
        "distinctNormalizedTrajectoryHashes": len({rows[index]["trajectorySHA256"] for index in unique}),
        "distinctJointInkFingerprints": len(fingerprints),
        "sourceIndexExposureHistogram": dict(sorted(Counter(Counter(indices).values()).items())),
        "jointCopyGroups": [{"rawRasterSHA256": key[0], "trajectorySHA256": key[1], "sourceIndices": value}
                            for key, value in sorted(fingerprints.items()) if len(value) > 1],
        "physicalSampleIndependenceEstablished": False,
        "interpretation": "IDs count source rows; exact raw-pixel and normalized-trajectory fingerprint counts are separate proxies, not certified independent physical samples"}


def run(crossfit_directory, output):
    directory, output = Path(crossfit_directory), Path(output)
    root = Path(__file__).resolve().parents[3]
    require(directory.is_absolute() and directory.resolve() == directory and directory.is_dir(), "Canonical training input directory required")
    require(output.is_absolute() and output.parent.is_dir() and output.parent.resolve() == output.parent
        and not output.exists() and not output.is_symlink() and root not in output.parents
        and directory not in output.parents, "Exclusive JSON output must stay outside source and inputs")
    inputs, code = input_identity(directory), code_identity()
    require(inputs["fit-receipt.json"] == RECEIPT_SHA256 and inputs["features.npz"] == FEATURES_SHA256, "Wrong frozen cross-fit packet")
    arrays, rows, receipt = crossfit.load_crossfit_bundle(directory)
    require(receipt["sourceSHA256"] == SOURCE_SHA256, "Wrong public training source")
    plans = validate_bundle(arrays, rows, receipt)
    require(len(plans) == 128 and {(episode["writer"], episode["session"], len(episode["support"])) for episode in plans}
        == {(writer, session, count) for writer in receipt["trainingWriters"] for session in (1, 2) for count in (10, 21)}, "Incomplete fixed episode directions")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    with torch.inference_mode():
        predictions = predict_episodes(arrays, rows, receipt["vocabulary"], plans)
    prediction_sha = sha(canonical(predictions))  # Frozen before supervised scoring.
    observations = score_training_predictions(predictions, rows, receipt["vocabulary"])
    scheduled = [index for episode in plans for index in episode["queries"] + [item["index"] for item in episode["exclusions"]]]
    eligible = [index for episode in plans for index in episode["queries"]]
    excluded = [item["index"] for episode in plans for item in episode["exclusions"]]
    tasks = []
    for task in ("K10", "K21"):
        selected = [row for row in observations if row["task"] == task]
        writers = []
        for writer in receipt["trainingWriters"]:
            writer_rows = [row for row in selected if row["writer"] == writer]
            writers.append({"writer": writer, "byAlpha": summarize(writer_rows), "bySupportSession": [
                {"session": session, "byAlpha": summarize([row for row in writer_rows if row["supportSession"] == session])}
                for session in (1, 2)]})
        tasks.append({"task": task, "byAlpha": summarize(selected), "byWriter": writers,
                      "eligibleExposureCounts": exposure_counts([row["queryIndex"] for row in selected], rows)})
    require(input_identity(directory) == inputs and code_identity() == code
        and sha(canonical(predictions)) == prediction_sha, "Audit inputs/code/frozen predictions changed")
    report = {"version": VERSION, "scope": "training-feasibility-diagnostic-not-candidate-selection-or-generalization",
        "protocolSHA256": PROTOCOL_SHA256, "sourceSHA256": SOURCE_SHA256, "inputsBefore": inputs, "inputsAfter": inputs,
        "codeBefore": code, "codeAfter": code, "alphaGrid": list(ALPHAS), "temperature": 10,
        "episodePlan": plans, "episodePlanSHA256": sha(canonical(plans)), "predictions": predictions,
        "predictionsSHA256": prediction_sha, "predictionsFrozenBeforeTrainingScoring": True,
        "trainingScoringLabels": [{"index": index, "sourceID": row["sourceID"], "label": row["label"]} for index, row in enumerate(rows)],
        "trainingScoringObservations": observations, "aggregateByAlpha": summarize(observations), "tasks": tasks,
        "exposureAccounting": {"scheduled": exposure_counts(scheduled, rows), "eligible": exposure_counts(eligible, rows),
                               "excluded": exposure_counts(excluded, rows)},
        "unavailableSetup": [{"index": index, "sourceID": row["sourceID"], "writer": row["writer"], "session": row["session"],
                              "label": row["label"], "reason": row["storedFailure"]} for index, row in enumerate(rows) if row["storedFailure"] is not None],
        "runtime": {"python": platform.python_version(), "numpy": str(np.__version__), "torch": str(torch.__version__),
                    "cpuThreads": torch.get_num_threads(), "deterministicAlgorithms": torch.are_deterministic_algorithms_enabled()},
        "boundaries": {"optimizationPerformed": False, "newEncoderOrLearnedLearnerInferencePerformed": False, "developmentDataOpened": False,
            "reservedDataOpened": False, "privateInkUsed": False, "bestAlphaSelected": False,
            "candidateAdvanced": False, "productionEligible": False, "appOrProfileMutated": False}}
    _write_exclusive(output, canonical(report))
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--crossfit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    report = run(arguments.crossfit, arguments.output)
    print(json.dumps({"version": report["version"], "episodes": len(report["episodePlan"]),
                      "eligibleQueryExposures": report["exposureAccounting"]["eligible"]["queryExposures"],
                      "predictionsSHA256": report["predictionsSHA256"]}, sort_keys=True), flush=True)

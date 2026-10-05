"""Fixed B8 leave-one-writer-out head fit; separate frozen prediction scoring.

Only preparation/scoring parse source metadata. The optimizer and predictor use
fitA arrays and frozen plans; this runner never constructs or fits an encoder.
There is deliberately no final-B8-fit operation or advancement permission.
"""
from __future__ import annotations

import argparse
import io
from pathlib import Path

import numpy as np
import torch

from . import personal_centroid_transport as core
from . import personal_conditional_support_trust as parent
from . import personal_cross_writer_evaluation as common
from .personal_cross_writer_contrastive import _new_output, _state_digest, _write_exclusive

VERSION = "personal-centroid-transport-experiment-v1"
ROLE_SHA256, GENERATOR_SHA256 = parent.ROLE_SHA256, parent.GENERATOR_SHA256
CORE_SHA256 = "46987f03c2fee72b2110a64b0d9bf5a9cde10d781c31edbc6fdb08e95dc9cc9e"
CORE_TEST_SHA256 = "444c2c32bae9f251374f0e93cd56879faab6c5a9304a732b648d995143963a6e"
EXECUTION = "docs/personal-centroid-transport-execution-2026-10-01.md"
EXECUTION_SHA256 = "2dcb455e70b7519ab9c48c59a4bf8f6eaa1266ade070de3bbe36c5081f4dc444"
EPOCHS, UPDATES_PER_EPOCH = 30, 28
TASKS = common.TASKS
HASH_KEYS = (("rawRasterSHA256", "storedRasterSHA256"), ("trajectorySHA256", "storedTrajectorySHA256"))
REASONS = tuple(f"{stage}-{kind}-copy" for stage in ("encoder-fit", "head-fit", "correct-support", "unrelated-support")
                for kind in ("raster", "normalized-trajectory"))
canonical, sha, read, parsed, require = common.canonical, common.sha, common.read, common.parsed, common.require


def code_identity():
    from . import personal_training_centroids as centroid_source
    root = Path(__file__).resolve().parents[3]
    result = {**parent.code_identity(), **core.code_identity(), **centroid_source.code_identity()}
    require(result["recognition_ml/ichart_recognition_ml/research/personal_centroid_transport.py"] == CORE_SHA256
        and result["recognition_ml/tests/test_personal_centroid_transport.py"] == CORE_TEST_SHA256, "Frozen centroid core changed")
    for path in ("recognition_ml/ichart_recognition_ml/research/personal_centroid_transport_experiment.py",
                 "recognition_ml/tests/test_personal_centroid_transport_experiment.py",
                 "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_evaluation.py",
                 "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_contrastive.py",
                 "recognition_ml/ichart_recognition_ml/research/personal_conditional_support_trust.py", EXECUTION):
        result[path] = sha(read(root / path))
    require(result[EXECUTION] == EXECUTION_SHA256, "Execution supplement changed")
    return result


def fit_recipe():
    return {"epochs": EPOCHS, "updatesPerEpoch": UPDATES_PER_EPOCH, "updatesPerFold": 840, "folds": 8,
        "seed": 41, "optimizer": "AdamW", "learningRate": .001, "weightDecay": .0001, "cosineTMax": 30,
        "lossCoefficients": [1, 1, 1], "architecture": "shared-4-32-tanh-1", "finalCheckpointOnly": True,
        "supportTasks": {k: list(v) for k, v in TASKS.items()}, "scoreTiePolicy": "first-max-in-frozen-vocabulary",
        "uncoveredAppLabels": ["#", "+", "/", "ø", "△"]}


def source_folds(rows, vocabulary, roles):
    """Pure source plan: hashes/roles/availability only, never outcome selection."""
    writers, encoder = roles["metaFitWriters"], roles["encoderFitWriters"]
    require(len(writers) == len(set(writers)) == 8 and len(encoder) == len(set(encoder)) == 16
        and not set(writers) & (set(encoder) | set(roles["internalValidationWriters"]))
        and roles["generator"] == "fitA" and roles["generatorWeightsSHA256"] == GENERATOR_SHA256
        and roles["freshValidation"] is False and len(vocabulary) == 97 and vocabulary == sorted(set(vocabulary)), "Wrong fixed writer roles")
    lookup = {(r["writer"], r["session"], r["label"]): i for i, r in enumerate(rows)}
    indices = [i for i, r in enumerate(rows) if r["writer"] in writers]
    require(len(indices) == 1552 and indices == roles["sourceIndices"]["metaFit"]
        and {(rows[i]["writer"], rows[i]["session"], rows[i]["label"]) for i in indices}
        == {(w, s, c) for w in writers for s in (1, 2) for c in vocabulary}
        and all(rows[i]["generator"] == "fitA" for i in indices)
        and all(c in vocabulary for labels in TASKS.values() for c in labels), "Incomplete app-domain fitA source grid")
    def pools(selected):
        return [{rows[i][key] for i in selected for key in keys if rows[i][key] is not None} for keys in HASH_KEYS]
    encoder_pool = pools([i for i, r in enumerate(rows) if r["writer"] in encoder])
    folds = []
    for heldout in writers:
        fit_writers = [w for w in writers if w != heldout]
        fit_indices = [i for i in indices if rows[i]["writer"] in fit_writers]
        head_pool = pools(fit_indices)
        donor_maps = {}
        for session in (1, 2):
            for task, labels in TASKS.items():
                ranked = sorted(fit_writers, key=lambda w: sha(canonical([rows[lookup[w, session, c]]["sourceID"] for c in labels])))
                donor_maps[session, task] = {w: ranked[(n + 1) % 7] for n, w in enumerate(ranked)}
        def episode(writer, session, task, oof):
            labels = TASKS[task]
            support = [lookup[writer, session, c] for c in labels]
            require(all(rows[i]["storedFailure"] is None for i in support), "App-domain support coverage insufficient")
            donors = [w for w in fit_writers if w != writer and all(rows[lookup[w, session, c]]["storedFailure"] is None for c in labels)]
            require(donors, "No unrelated fitting-writer support coverage")
            donor = (min(donors, key=lambda w: sha(canonical([rows[lookup[w, session, c]]["sourceID"] for c in labels])))
                if oof else donor_maps[session, task][writer])
            require(donor in donors, "Frozen unrelated support unavailable")
            unrelated = [lookup[donor, session, c] for c in labels]
            scheduled = [lookup[writer, 3 - session, c] for c in vocabulary]
            groups = [("encoder-fit", encoder_pool), ("correct-support", pools(support)), ("unrelated-support", pools(unrelated))]
            if oof: groups.insert(1, ("head-fit", head_pool))
            excluded = []
            for i in scheduled:
                reasons = [f"{stage}-{kind}-copy" for stage, group in groups
                    for kind, keys, pool in zip(("raster", "normalized-trajectory"), HASH_KEYS, group)
                    if any(rows[i][key] is not None and rows[i][key] in pool for key in keys)]
                if reasons: excluded.append({"index": i, "reasons": reasons})
            eligible = [i for i in scheduled if i not in {e["index"] for e in excluded}]
            taught = [rows[i]["label"] in labels for i in eligible]
            require(any(taught) and not all(taught), "Source exclusions removed a query stratum")
            unavailable = [{"index": i, "failure": rows[i]["storedFailure"]} for i in indices
                if rows[i]["writer"] in (writer, donor) and rows[i]["storedFailure"] is not None]
            value = {"writer": writer, "supportSession": session, "querySession": 3 - session, "task": task,
                "support": support, "unrelatedSupport": unrelated, "unrelatedWriter": donor,
                "supportLabels": list(labels), "supportLabelIndices": [vocabulary.index(c) for c in labels],
                "scheduledQueries": scheduled, "queries": eligible, "exclusions": excluded, "unavailableSetup": unavailable}
            return value
        training = [episode(w, s, k, False) for w in fit_writers for s in (1, 2) for k in TASKS]
        generator = torch.Generator().manual_seed(41)
        updates = [i for _ in range(EPOCHS) for i in torch.randperm(28, generator=generator).tolist()]
        folds.append({"foldIndex": len(folds), "heldOutWriter": heldout, "fitWriters": fit_writers, "fitIndices": fit_indices,
            "fitEpisodes": training, "updateEpisodeIndices": updates,
            "oofEpisodes": [episode(heldout, s, k, True) for s in (1, 2) for k in TASKS]})
    validate_folds(folds, vocabulary, roles, {str(i): {k: rows[i][k] for k in ("writer", "session", "generator")} for i in indices})
    return folds


def validate_folds(folds, vocabulary, roles, owners):
    """No query-label metadata required for role, ledger and schedule checking."""
    writers, permitted = roles["metaFitWriters"], set(roles["sourceIndices"]["metaFit"])
    require(len(folds) == 8 and len(permitted) == 1552 and {int(i) for i in owners} == permitted
        and all(type(i) is int for i in permitted) and len(vocabulary) == 97 and vocabulary == sorted(set(vocabulary))
        and len(writers) == len(set(writers)) == 8 and roles["generator"] == "fitA"
        and roles["generatorWeightsSHA256"] == GENERATOR_SHA256 and roles["freshValidation"] is False
        and not permitted & set(roles["sourceIndices"]["internalValidation"])
        and not set(writers) & (set(roles["encoderFitWriters"]) | set(roles["internalValidationWriters"])), "Frozen roles changed")
    require(all(o["writer"] in writers and type(o["session"]) is int and o["session"] in (1, 2) and o["generator"] == "fitA" for o in owners.values()), "Non-fitA source ownership")
    for number, fold in enumerate(folds):
        heldout = writers[number]; fit_writers = [w for w in writers if w != heldout]
        allowed = {i for i in permitted if owners[str(i)]["writer"] in fit_writers}
        require(fold["foldIndex"] == number and fold["heldOutWriter"] == heldout and fold["fitWriters"] == fit_writers
            and len(fold["fitIndices"]) == len(allowed) == 1358 and set(fold["fitIndices"]) == allowed
            and len(fold["fitEpisodes"]) == 28 and len(fold["oofEpisodes"]) == 4
            and len(fold["updateEpisodeIndices"]) == 840
            and all(sorted(fold["updateEpisodeIndices"][e * 28:(e + 1) * 28]) == list(range(28)) for e in range(30)), "Fold schedule or optimizer role changed")
        for oof, episodes in ((False, fold["fitEpisodes"]), (True, fold["oofEpisodes"])):
            cohort = [heldout] if oof else fit_writers
            require({(p["writer"], p["supportSession"], p["task"]) for p in episodes}
                == {(w, s, k) for w in cohort for s in (1, 2) for k in TASKS}, "Missing source direction")
            if not oof:
                require(all({p["unrelatedWriter"] for p in episodes if p["supportSession"] == s and p["task"] == k}
                    == set(fit_writers) for s in (1, 2) for k in TASKS), "Unrelated donors are not a derangement")
            for p in episodes:
                support, wrong, scheduled, eligible = (p[k] for k in ("support", "unrelatedSupport", "scheduledQueries", "queries"))
                excluded = [e["index"] for e in p["exclusions"]]
                require(p["querySession"] == 3 - p["supportSession"] and p["supportLabels"] == list(TASKS[p["task"]])
                    and p["supportLabelIndices"] == [vocabulary.index(c) for c in TASKS[p["task"]]]
                    and len(support) == len(wrong) == len(set(support)) == len(set(wrong)) == len(p["supportLabels"])
                    and len(scheduled) == len(set(scheduled)) == 97 and len(eligible) == len(set(eligible))
                    and len(excluded) == len(set(excluded)) and set(eligible) | set(excluded) == set(scheduled)
                    and not set(eligible) & set(excluded) and p["unrelatedWriter"] in fit_writers
                    and p["unrelatedWriter"] != p["writer"] and all(type(i) is int and i in permitted for i in support + wrong + scheduled)
                    and all(owners[str(i)] == {"writer": p["writer"], "session": p["supportSession"], "generator": "fitA"} for i in support)
                    and all(owners[str(i)] == {"writer": p["unrelatedWriter"], "session": p["supportSession"], "generator": "fitA"} for i in wrong)
                    and all(owners[str(i)] == {"writer": p["writer"], "session": p["querySession"], "generator": "fitA"} for i in scheduled)
                    and all(e["reasons"] and e["reasons"] == [r for r in REASONS if r in e["reasons"]] for e in p["exclusions"])
                    and all(type(e["index"]) is int and e["index"] in permitted and isinstance(e["failure"], str)
                        and e["failure"] for e in p["unavailableSetup"]), "Episode support, copies or denominator changed")
                require("targets" not in p and (oof or set(support + wrong + scheduled) <= allowed), "OOF truth or optimizer leakage")


def load_centroids(directory, binding, roles, vocabulary, receipt_sha256):
    from .personal_training_centroids import load_frozen_centroids
    centroids, _ = load_frozen_centroids(directory, binding, roles, vocabulary, receipt_sha256=receipt_sha256)
    return centroids, {name: sha(read(Path(directory) / name)) for name in
        ("centroid-receipt.json", "centroids.npz", "training-features.npz", "training-rows.json")}


def validate_binding(binding):
    require(binding["version"] == VERSION and binding["recipe"] == fit_recipe()
        and binding["protocolSHA256"] == core.PROTOCOL_SHA256 and binding["codeSHA256"] == code_identity()
        and binding["runtime"] == common.runtime_identity() and binding["roleManifestSHA256"] == ROLE_SHA256
        and sha(read(binding["rolesPath"])) == ROLE_SHA256
        and parent.input_identity(binding["parentPath"]) == binding["parentBinding"]
        and binding["planSHA256"] == sha(canonical(binding["folds"]))
        and sha(read(Path(binding["preparationPath"]) / "meta-features.npz")) == binding["metaFeaturesSHA256"], "Frozen input, code or plan changed")
    centroids, identity = load_centroids(binding["centroidPath"], binding["parentBinding"], binding["roles"], binding["vocabulary"], binding["centroidReceiptSHA256"])
    require(identity == binding["centroidBinding"] and identity["centroid-receipt.json"] == binding["centroidReceiptSHA256"], "Centroid bundle changed")
    validate_folds(binding["folds"], binding["vocabulary"], binding["roles"], binding["owners"])
    return centroids


def prepare(crossfit, roles_path, centroid_directory, centroid_receipt_sha256, output):
    common.configure(); before, code = parent.input_identity(crossfit), code_identity()
    require(common.digest_string(centroid_receipt_sha256)
        and sha(read(Path(centroid_directory) / "centroid-receipt.json")) == centroid_receipt_sha256, "Centroid receipt SHA mismatch before preparation")
    arrays, rows, receipt, roles = parent.load_parent(crossfit, roles_path)
    folds = source_folds(rows, receipt["vocabulary"], roles)
    _, centroids = load_centroids(centroid_directory, before, roles, receipt["vocabulary"], centroid_receipt_sha256)
    output = Path(output); require(Path(__file__).resolve().parents[3] not in output.parents
        and all(Path(p) not in output.parents and output != Path(p) for p in (crossfit, centroid_directory)), "Aliased preparation output")
    output = _new_output(output); indices = roles["sourceIndices"]["metaFit"]
    stream = io.BytesIO(); np.savez(stream, source_indices=np.asarray(indices, dtype=np.int64),
        **{k: np.array(arrays[k][indices], dtype=np.float64, copy=True) for k in ("raw_features", "raw_logits", "stored_features")})
    meta = stream.getvalue(); _write_exclusive(output / "meta-features.npz", meta)
    target_hashes = []
    for fold in folds:
        payload = canonical({"indices": fold["fitIndices"], "targets": [receipt["vocabulary"].index(rows[i]["label"]) for i in fold["fitIndices"]]})
        _write_exclusive(output / f'fold-{fold["foldIndex"]}-targets.json', payload); target_hashes.append(sha(payload))
    truth = canonical({"vocabulary": receipt["vocabulary"], "rows": [{"sourceIndex": i, "target": receipt["vocabulary"].index(rows[i]["label"]),
        "writer": rows[i]["writer"], "session": rows[i]["session"]} for i in indices]})
    _write_exclusive(output / "truth.json", truth)
    binding = {"version": VERSION, "recipe": fit_recipe(), "protocolSHA256": core.PROTOCOL_SHA256,
        "parentPath": str(crossfit), "parentBinding": before, "rolesPath": str(roles_path), "roleManifestSHA256": ROLE_SHA256,
        "roles": roles, "centroidPath": str(centroid_directory), "centroidBinding": centroids,
        "codeSHA256": code, "runtime": common.runtime_identity(), "vocabulary": receipt["vocabulary"],
        "owners": {str(i): {k: rows[i][k] for k in ("writer", "session", "generator")} for i in roles["sourceIndices"]["metaFit"]},
        "folds": folds, "planSHA256": sha(canonical(folds)), "predictionPerformed": False, "internalReuseOnly": True,
        "preparationPath": str(output), "metaFeaturesSHA256": sha(meta), "trainingTargetsSHA256": target_hashes,
        "truthSHA256": sha(truth), "centroidReceiptSHA256": centroid_receipt_sha256}
    validate_binding(binding); data = canonical(binding)
    _write_exclusive(output / "commitment.json", data)
    return {"commitmentSHA256": sha(data), "folds": 8, "updatesPerFold": 840, "scheduledOOFExposures": 3104}


def feature_tensors(directory, indices, permitted):
    """No metadata parser; only explicitly authorized rows become tensors."""
    require(len(indices) == len(set(indices)) and all(type(i) is int and i in permitted for i in indices), "Unauthorized feature row")
    with np.load(io.BytesIO(read(Path(directory) / "meta-features.npz")), allow_pickle=False) as archive:
        shapes = {"source_indices": (1552,), "raw_features": (1552, 128), "stored_features": (1552, 128), "raw_logits": (1552, 97)}
        require(set(archive.files) == set(shapes) and all(archive[k].shape == s and archive[k].dtype == (np.int64 if k == "source_indices" else np.float64)
            for k, s in shapes.items()), "Invalid meta-only archive schema")
        source = archive["source_indices"].tolist(); require(len(source) == len(set(source)) == 1552 and set(indices) <= set(source), "Meta-only source grid changed")
        selected = [source.index(i) for i in indices]
        tensors = {name: torch.from_numpy(np.array(archive[name][selected], dtype=np.float64, copy=True))
            for name in ("raw_features", "raw_logits", "stored_features")}
    require(all(bool(torch.isfinite(t).all()) for t in tensors.values()), "Nonfinite authorized features")
    return tensors, {i: n for n, i in enumerate(indices)}


def training_targets(binding, fold):
    data = read(Path(binding["preparationPath"]) / f'fold-{fold["foldIndex"]}-targets.json')
    require(sha(data) == binding["trainingTargetsSHA256"][fold["foldIndex"]], "Training-target SHA changed")
    value = parsed(data); require(data == canonical(value) and value["indices"] == fold["fitIndices"]
        and len(value["targets"]) == len(fold["fitIndices"]) and all(type(t) is int and 0 <= t < 97 for t in value["targets"]), "Seven-writer targets changed")
    return dict(zip(value["indices"], value["targets"]))


def episode_inputs(tensors, remap, p, centroids, *, scheduled=False):
    indices = p["scheduledQueries"] if scheduled else p["queries"]
    take = lambda name, rows: tensors[name][[remap[i] for i in rows]]
    return (centroids, take("stored_features", p["support"]), torch.tensor(p["supportLabelIndices"], dtype=torch.long),
        take("raw_features", indices), take("raw_logits", indices), take("stored_features", p["unrelatedSupport"]))


def train_head(model, prepared, schedule):
    """Exactly 840 finite supervised updates; synthetic episodes are allowed."""
    require(len(prepared) == 28 and len(schedule) == 840
        and all(sorted(schedule[e * 28:(e + 1) * 28]) == list(range(28)) for e in range(30)), "Fixed 30x28 update schedule required")
    initial = {k: v.clone() for k, v in model.state_dict().items()}
    digest = _state_digest({f"{i}:{j}": t for i, values in enumerate(prepared) for j, t in enumerate(values)})
    optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=30)
    gradients = {k: 0. for k, _ in model.named_parameters()}; history = []
    for epoch in range(30):
        losses = []; components = {k: [] for k in ("balancedCE", "preservationMargin", "unrelatedSupportKL")}
        learning_rate = float(optimizer.param_groups[0]["lr"])
        for number in schedule[epoch * 28:(epoch + 1) * 28]:
            centroids, support, labels, query, generic, unrelated, targets, taught = prepared[number]
            require(not any(t.requires_grad for t in prepared[number]), "Training inputs must stay frozen")
            candidate = model.adapted_logits(centroids, support, labels, query, generic)
            wrong = model.adapted_logits(centroids, unrelated, labels, query, generic)
            loss, parts = core.training_objective(candidate, generic, wrong, targets, taught)
            optimizer.zero_grad(set_to_none=True); loss.backward()
            for name, parameter in model.named_parameters():
                require(parameter.grad is not None and bool(torch.isfinite(parameter.grad).all()), "Nonfinite/missing head gradient")
                gradients[name] = max(gradients[name], float(parameter.grad.abs().max()))
            optimizer.step(); losses.append(float(loss.detach()))
            for name, value in parts.items(): components[name].append(float(value.detach()))
        scheduler.step()
        history.append({"epoch": epoch + 1, "updates": len(losses), "learningRate": learning_rate,
            "meanLoss": float(np.mean(losses)), **{k: float(np.mean(v)) for k, v in components.items()}})
    deltas = {k: float((v - initial[k]).norm()) for k, v in model.state_dict().items()}
    meaningful = ("scorer.0.weight", "scorer.0.bias", "scorer.2.weight")
    require(all(deltas[k] > 0 and gradients[k] > 0 for k in meaningful)
        and deltas["scorer.2.bias"] <= 1e-12
        and all(bool(torch.isfinite(v).all()) for v in model.state_dict().values())
        and _state_digest({f"{i}:{j}": t for i, values in enumerate(prepared) for j, t in enumerate(values)}) == digest,
        "Unchanged meaningful blocks, nonfinite weights or mutated inputs")
    return {"history": history, "updates": 840, "parameterDeltaNorms": deltas, "maximumAbsoluteGradients": gradients,
        "initialStateSHA256": _state_digest(initial), "finalStateSHA256": _state_digest(model.state_dict()), "inputTensorSHA256": digest,
        "finalBiasCancelsAlgebraically": True, "canceledFinalBiasDeltaNorm": deltas["scorer.2.bias"], "canceledFinalBiasTolerance": 1e-12}


def checkpoint(model, binding):
    stream = io.BytesIO(); torch.save({"version": VERSION, "binding": binding, "state_dict": model.state_dict()}, stream)
    return stream.getvalue()


def load_checkpoint(data, expected_sha, binding):
    require(sha(data) == expected_sha, "Checkpoint SHA mismatch")
    value = torch.load(io.BytesIO(data), map_location="cpu", weights_only=True); model = core.CentroidTransport()
    schema = model.state_dict(); state = value["state_dict"]
    require(set(value) == {"version", "binding", "state_dict"} and value["version"] == VERSION and value["binding"] == binding
        and set(state) == set(schema) and all(v.dtype == torch.float64 and v.device.type == "cpu"
        and v.shape == schema[k].shape and bool(torch.isfinite(v).all()) for k, v in state.items()), "Checkpoint binding/schema changed")
    model.load_state_dict(state, strict=True); return model.eval()


def predict_episode(model, tensors, remap, plan, centroids):
    values = episode_inputs(tensors, remap, plan, centroids, scheduled=True)
    mu, support, labels, query, generic, unrelated = values
    probabilities, failures = {"generic": generic.softmax(1)}, {}
    for arm, lessons in (("candidate", support), ("unrelated", unrelated)):
        try:
            with torch.inference_mode(): probabilities[arm] = model.probabilities(mu, lessons, labels, query, generic)
        except (ValueError, RuntimeError) as error: failures[arm] = f"{type(error).__name__}: {str(error)[:240]}"
    rows = []
    for position, index in enumerate(plan["scheduledQueries"]):
        row = {"sourceIndex": index}
        for arm in ("generic", "candidate", "unrelated"):
            vector = None if arm in failures else probabilities[arm][position].detach().numpy()
            failure = failures.get(arm)
            if vector is not None:
                try: common.validate_scores(vector[None], 1, 97)
                except ValueError as error: vector, failure = None, str(error)
            require(arm != "generic" or vector is not None, "Invalid frozen generic prediction")
            row[arm + "Probabilities"] = None if vector is None else vector.tolist(); row[arm + "Failure"] = failure
        rows.append(row)
    return {"rows": rows}


def validate_packet(packet):
    binding = packet["bindings"]
    require(packet["version"] == VERSION and packet["commitmentSHA256"] == sha(canonical(binding))
        and all(packet[k] is False for k in ("oofQueryTruthOpened", "encoderFitted", "encoderInferencePerformed",
            "failedValidationInferred", "developmentInferred", "reservedInferred", "privateInkUsed", "productionEligible")), "Prediction boundary changed")
    validate_folds(binding["folds"], binding["vocabulary"], binding["roles"], binding["owners"])
    plans = [(f["foldIndex"], p) for f in binding["folds"] for p in f["oofEpisodes"]]
    require(len(packet["episodes"]) == len(plans) == 32 and len(packet["fitReceipts"]) == 8, "Missing OOF output or fit receipt")
    for number, receipt in enumerate(packet["fitReceipts"]):
        require(receipt["foldIndex"] == number and receipt["updates"] == 840 and len(receipt["history"]) == 30
            and all(r["epoch"] == e + 1 and r["updates"] == 28 and all(np.isfinite(r[k]) for k in
                ("learningRate", "meanLoss", "balancedCE", "preservationMargin", "unrelatedSupportKL")) for e, r in enumerate(receipt["history"]))
            and all(np.isfinite(receipt["parameterDeltaNorms"][k]) and receipt["parameterDeltaNorms"][k] > 0
                and np.isfinite(receipt["maximumAbsoluteGradients"][k]) and receipt["maximumAbsoluteGradients"][k] > 0
                for k in ("scorer.0.weight", "scorer.0.bias", "scorer.2.weight"))
            and receipt["finalStateSHA256"] == receipt["reloadStateSHA256"]
            and receipt["canceledFinalBiasTolerance"] == 1e-12 and receipt["canceledFinalBiasDeltaNorm"] <= 1e-12
            and receipt["canceledFinalBiasDeltaNorm"] == receipt["parameterDeltaNorms"]["scorer.2.bias"]
            and all(common.digest_string(receipt[k]) for k in ("weightsSHA256", "initialStateSHA256", "finalStateSHA256", "inputTensorSHA256")), "Invalid fit/reload receipt")
    for episode, (fold, plan) in zip(packet["episodes"], plans):
        require(episode["foldIndex"] == fold and [r["sourceIndex"] for r in episode["rows"]] == plan["scheduledQueries"], "Scheduled denominator changed")
        for row in episode["rows"]:
            for arm in ("generic", "candidate", "unrelated"):
                vector, failure = row[arm + "Probabilities"], row[arm + "Failure"]
                if vector is not None: common.validate_scores(np.asarray(vector)[None], 1, 97); require(failure is None, "Read has failure")
                else: require(arm != "generic" and isinstance(failure, str) and bool(failure), "Missing row repaired/deleted")


def fit_predict(commitment, commitment_sha256, output):
    common.configure(); frozen = read(commitment)
    require(common.digest_string(commitment_sha256) and sha(frozen) == commitment_sha256, "Commitment SHA mismatch before fitting")
    binding = parsed(frozen); require(frozen == canonical(binding), "Noncanonical commitment")
    centroids = validate_binding(binding); destination = Path(output)
    require(Path(__file__).resolve().parents[3] not in destination.parents
        and all(Path(binding[k]) not in destination.parents and destination != Path(binding[k]) for k in ("parentPath", "centroidPath")), "Aliased fit output")
    destination = _new_output(destination); _write_exclusive(destination / "commitment.json", frozen)
    episodes, receipts = [], []
    for fold in binding["folds"]:
        tensors, remap = feature_tensors(binding["preparationPath"], fold["fitIndices"], set(fold["fitIndices"]))
        target_map = training_targets(binding, fold)
        prepared = []
        for p in fold["fitEpisodes"]:
            values = episode_inputs(tensors, remap, p, centroids); targets = torch.tensor([target_map[i] for i in p["queries"]], dtype=torch.long)
            prepared.append((*values, targets, torch.isin(targets, values[2])))
        model = core.CentroidTransport(); receipt = train_head(model, prepared, fold["updateEpisodeIndices"])
        frozen_checkpoint = {"commitmentSHA256": commitment_sha256, "foldIndex": fold["foldIndex"], "finalEpoch": 30}
        data = checkpoint(model, frozen_checkpoint); path = destination / f'fold-{fold["foldIndex"]}.pt'; _write_exclusive(path, data)
        reloaded = load_checkpoint(read(path), sha(data), frozen_checkpoint)
        require(_state_digest(reloaded.state_dict()) == receipt["finalStateSHA256"], "Reloaded state changed")
        receipt.update(foldIndex=fold["foldIndex"], weightsSHA256=sha(data), reloadStateSHA256=_state_digest(reloaded.state_dict()))
        receipts.append(receipt); del tensors, prepared, model
        # Held-out raw query tensors are created only after this fold is frozen.
        indices = sorted({i for p in fold["oofEpisodes"] for k in ("support", "unrelatedSupport", "scheduledQueries") for i in p[k]})
        tensors, remap = feature_tensors(binding["preparationPath"], indices, set(binding["roles"]["sourceIndices"]["metaFit"]))
        before = _state_digest(reloaded.state_dict())
        for plan in fold["oofEpisodes"]: episodes.append({"foldIndex": fold["foldIndex"], **predict_episode(reloaded, tensors, remap, plan, centroids)})
        require(_state_digest(reloaded.state_dict()) == before, "OOF prediction mutated frozen head")
        validate_binding(binding); training_targets(binding, fold)
        require(read(commitment) == frozen, "Commitment changed during fit")
    packet = {"version": VERSION, "bindings": binding, "commitmentSHA256": commitment_sha256, "fitReceipts": receipts, "episodes": episodes,
        **{k: False for k in ("oofQueryTruthOpened", "encoderFitted", "encoderInferencePerformed", "failedValidationInferred",
            "developmentInferred", "reservedInferred", "privateInkUsed", "productionEligible")}}
    validate_packet(packet); validate_binding(binding)
    after_code, after_inputs = code_identity(), parent.input_identity(binding["parentPath"])
    target_hashes = [sha(read(Path(binding["preparationPath"]) / f"fold-{n}-targets.json")) for n in range(8)]
    require(after_code == binding["codeSHA256"] and after_inputs == binding["parentBinding"]
        and target_hashes == binding["trainingTargetsSHA256"] and read(commitment) == frozen, "Frozen inputs/code changed before publication")
    payload = canonical(packet)
    _write_exclusive(destination / "predictions.json", payload)
    _write_exclusive(destination / "verification.json", canonical({"codeBefore": binding["codeSHA256"], "codeAfter": after_code,
        "inputsBefore": binding["parentBinding"], "inputsAfter": after_inputs,
        "trainingTargetsBefore": binding["trainingTargetsSHA256"], "trainingTargetsAfter": target_hashes, "predictionSHA256": sha(payload)}))
    return {"predictionSHA256": sha(payload), "folds": 8, "updates": sum(r["updates"] for r in receipts), "scheduledExposures": 3104}


def summarize(rows):
    gains = [r["exposureID"] for r in rows if not r["genericCorrect"] and r["candidateCorrect"]]
    harms = [r["exposureID"] for r in rows if r["genericCorrect"] and not r["candidateCorrect"]]
    return {"queryExposures": len(rows), "distinctSourceIndices": len({r["sourceIndex"] for r in rows}),
        "repeatedExposures": len(rows) - len({r["sourceIndex"] for r in rows}),
        "excludedExposures": sum(bool(r["exclusions"]) for r in rows), "eligibleExposures": sum(not r["exclusions"] for r in rows),
        "distinctExcludedSourceIndices": len({r["sourceIndex"] for r in rows if r["exclusions"]}),
        "distinctEligibleSourceIndices": len({r["sourceIndex"] for r in rows if not r["exclusions"]}),
        "exclusionReasonExposures": {reason: sum(reason in r["exclusions"] for r in rows) for reason in REASONS},
        **{arm + "Correct": sum(r[arm + "Correct"] for r in rows) for arm in ("generic", "candidate", "unrelated")},
        "gains": len(gains), "harms": len(harms), "netCorrect": len(gains) - len(harms),
        "gainExposureIDs": gains, "harmExposureIDs": harms,
        "invalidCandidate": sum(r["candidateFailure"] is not None for r in rows), "invalidUnrelated": sum(r["unrelatedFailure"] is not None for r in rows)}


def screen(rows, writers):
    tasks, passed = {}, True
    for task in TASKS:
        tasks[task] = {}
        for view in ("rawScheduled", "sourceOnlyNoCopy"):
            selected = [r for r in rows if r["task"] == task and (view == "rawScheduled" or not r["exclusions"])]
            total = summarize(selected); by_writer = {w: summarize([r for r in selected if r["writer"] == w]) for w in writers}
            strata = {name: summarize([r for r in selected if r["taught"] == taught]) for name, taught in (("taught", True), ("untaught", False))}
            conditions = [total["candidateCorrect"] > total["genericCorrect"], total["candidateCorrect"] > total["unrelatedCorrect"],
                all(v["netCorrect"] >= 0 for v in by_writer.values()), strata["untaught"]["harms"] == 0]
            valid_outputs = total["invalidCandidate"] == total["invalidUnrelated"] == 0
            tasks[task][view] = {**total, "writers": by_writer, "strata": strata, "screenConditions": conditions,
                "validPredictionOutputsRequired": True, "validPredictionOutputs": valid_outputs,
                "supportSessions": {str(s): summarize([r for r in selected if r["supportSession"] == s]) for s in (1, 2)},
                "writerSessions": {w: {str(s): summarize([r for r in selected if r["writer"] == w and r["supportSession"] == s]) for s in (1, 2)} for w in writers},
                "writerStrata": {w: {n: summarize([r for r in selected if r["writer"] == w and r["taught"] == t]) for n, t in (("taught", True), ("untaught", False))} for w in writers},
                "sessionStrata": {str(s): {n: summarize([r for r in selected if r["supportSession"] == s and r["taught"] == t]) for n, t in (("taught", True), ("untaught", False))} for s in (1, 2)},
                "sourceDomains": {name: summarize([r for r in selected if (r["trueLabel"] in TASKS["catalog21"]) == app])
                    for name, app in (("appCatalog21", True), ("nonAppStress", False))},
                "authoritativeFixedScreen": view == "sourceOnlyNoCopy"}
            if view == "sourceOnlyNoCopy": passed &= valid_outputs and all(conditions)
    return tasks, bool(passed)


def score(predictions, predictions_sha256, output):
    common.configure(); data = read(predictions)
    require(common.digest_string(predictions_sha256) and sha(data) == predictions_sha256, "Prediction SHA mismatch before truth")
    packet = parsed(data); require(data == canonical(packet), "Noncanonical predictions")
    validate_packet(packet); binding = packet["bindings"]; validate_binding(binding)
    for receipt in packet["fitReceipts"]:
        payload = read(Path(predictions).parent / f'fold-{receipt["foldIndex"]}.pt')
        model = load_checkpoint(payload, receipt["weightsSHA256"], {"commitmentSHA256": packet["commitmentSHA256"], "foldIndex": receipt["foldIndex"], "finalEpoch": 30})
        require(_state_digest(model.state_dict()) == receipt["finalStateSHA256"], "Scoring checkpoint changed")
    # First OOF query-label join occurs only after the complete prediction SHA gate.
    truth_data = read(Path(binding["preparationPath"]) / "truth.json")
    require(sha(truth_data) == binding["truthSHA256"], "Scoring truth SHA changed")
    truth = parsed(truth_data); require(truth_data == canonical(truth) and truth["vocabulary"] == binding["vocabulary"], "Scoring vocabulary changed")
    source = {r["sourceIndex"]: r for r in truth["rows"]}; roles = binding["roles"]
    require(len(source) == len(truth["rows"]) == 1552 and set(source) == set(roles["sourceIndices"]["metaFit"])
        and all(type(r["target"]) is int and 0 <= r["target"] < 97
            and {"writer": r["writer"], "session": r["session"], "generator": "fitA"} == binding["owners"][str(i)] for i, r in source.items()), "Scoring source roles changed")
    tensors, remap = feature_tensors(binding["preparationPath"], list(source), set(source))
    rows = []; plans = [p for f in binding["folds"] for p in f["oofEpisodes"]]
    for number, (plan, episode) in enumerate(zip(plans, packet["episodes"])):
        generic = tensors["raw_logits"][[remap[i] for i in plan["scheduledQueries"]]].softmax(1).numpy()
        exclusions = {e["index"]: e["reasons"] for e in plan["exclusions"]}
        for position, prediction in enumerate(episode["rows"]):
            index = prediction["sourceIndex"]; target = source[index]["target"]
            require(np.array_equal(generic[position], np.asarray(prediction["genericProbabilities"])), "Generic prediction changed")
            rows.append({"exposureID": f"{number}:{index}", "sourceIndex": index, "writer": plan["writer"], "task": plan["task"],
                "supportSession": plan["supportSession"], "querySession": plan["querySession"], "trueLabel": binding["vocabulary"][target],
                "taught": target in plan["supportLabelIndices"], "exclusions": exclusions.get(index, []),
                **{arm + "Correct": prediction[arm + "Probabilities"] is not None
                    and int(np.argmax(prediction[arm + "Probabilities"])) == target for arm in ("generic", "candidate", "unrelated")},
                **{arm + "Failure": prediction[arm + "Failure"] for arm in ("candidate", "unrelated")}})
    tasks, passed = screen(rows, roles["metaFitWriters"])
    for task, views in tasks.items():
        related = [p for p in plans if p["task"] == task]
        for cell in views.values():
            cell.update(unavailableSetupExposures=sum(len(p["unavailableSetup"]) for p in related),
                distinctUnavailableSetupIndices=len({e["index"] for p in related for e in p["unavailableSetup"]}))
    value = {"version": VERSION, "predictionSHA256": predictions_sha256, "commitmentSHA256": packet["commitmentSHA256"],
        "internalReuseOnly": True, "freshValidation": False, "productionEligible": False, "finalB8FitAuthorized": False,
        "scheduledExposures": len(rows), "distinctSourceIndices": len({r["sourceIndex"] for r in rows}),
        "excludedExposures": sum(bool(r["exclusions"]) for r in rows), "eligibleExposures": sum(not r["exclusions"] for r in rows),
        "distinctExcludedSourceIndices": len({r["sourceIndex"] for r in rows if r["exclusions"]}),
        "distinctEligibleSourceIndices": len({r["sourceIndex"] for r in rows if not r["exclusions"]}),
        "repeatedExposures": len(rows) - len({r["sourceIndex"] for r in rows}), "uncoveredAppLabels": fit_recipe()["uncoveredAppLabels"],
        "unavailableSetupExposures": sum(len(p["unavailableSetup"]) for p in plans),
        "distinctUnavailableSetupIndices": len({e["index"] for p in plans for e in p["unavailableSetup"]}),
        "unavailableSetupLedger": [{"episodeIndex": n, **e} for n, p in enumerate(plans) for e in p["unavailableSetup"]],
        "tasks": tasks, "rows": rows, "passesFixedScreen": passed,
        "disposition": "eligible-for-separately-authorized-final-B8-fit" if passed else "reject-fixed-recipe-no-retuning"}
    validate_binding(binding); require(read(predictions) == data, "Frozen predictions changed during scoring")
    common.exclusive(output, canonical(value), (predictions, binding["parentPath"], binding["rolesPath"], binding["centroidPath"]))
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest="operation", required=True)
    p = sub.add_parser("prepare")
    for field in ("crossfit", "roles", "centroid-directory", "output"): p.add_argument("--" + field, type=Path, required=True)
    p.add_argument("--centroid-receipt-sha256", required=True)
    for operation, field in (("fit-predict", "commitment"), ("score", "predictions")):
        p = sub.add_parser(operation); p.add_argument("--" + field, type=Path, required=True)
        p.add_argument("--" + field + "-sha256", required=True); p.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.operation == "prepare": result = prepare(args.crossfit, args.roles, args.centroid_directory, args.centroid_receipt_sha256, args.output)
    elif args.operation == "fit-predict": result = fit_predict(args.commitment, args.commitment_sha256, args.output)
    else: result = score(args.predictions, args.predictions_sha256, args.output)
    print(canonical({k: v for k, v in result.items() if k not in ("rows", "tasks", "unavailableSetupLedger")}).decode())


if __name__ == "__main__": main()

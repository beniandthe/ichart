"""Fixed public-cache support metric: prepare -> fit -> predict -> score.

No encoder is constructed. Prediction opens only answer-free plans/arrays and
the final scalar-scorer checkpoint; truth and copy ledgers are joined last.
"""
from __future__ import annotations

import argparse
from collections import Counter
import io
from pathlib import Path

import numpy as np
import torch

from . import personal_support_metric as core
from . import personal_conditional_support_trust as parent
from . import personal_training_centroids as centroid
from .personal_conditional_support_trust import input_identity, code_identity as parent_code_identity
from .personal_training_centroids import code_identity as centroid_code_identity
from .personal_support_match_defer_plan import validate_domain, DOMAIN_SHA256, TASKS, code_identity as domain_code_identity
from .personal_support_retrieval import canonical, require, sha
from .personal_cross_writer_contrastive import _state_digest
from .personal_hwrt_stroke_train import (_read as read, _parsed as parsed, _tensor_sha256 as tensor_sha,
    _fresh_directory as _new_output, _write_exclusive)

VERSION = "personal-support-metric-experiment-v1"
PROTOCOL = "docs/personal-support-metric-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "bc94d5b92815119ba70d8c2abeb5b54dc42b1ec9801cc6bebbae2a07993decad"
ROLE_SHA256 = "47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa"
CENTROID_SHA256 = "c4c895caee391b6076018244b9b5a8a19230c8052a95776d0d7459a90dea9bad"
ROOT = Path(__file__).resolve().parents[3]
SWIFT_CODE = "iChart/Recognition/ChordInkPersonalization.swift"
HISTORICAL_SWIFT_SHA256 = "b4287512477490e7816e34bda29dde87831f37ba560c61b1d9642c40cfe8c3cd"
CURRENT_SWIFT_SHA256 = "81d7684dd4efaace71d4cfeec5196648eff73f4e53fc1c46f73dab21f819fde0"
GENERATION_ARCHIVE_DIRECTORY = Path("/Users/benirossman/.local/share/ichart/recognition-development/support-retrieval-20261001.WmWgZ3/source-snapshot")
CENTROID_ARCHIVE_DIRECTORY = Path("/Users/benirossman/.local/share/ichart/recognition-development/centroid-transport-20261001.qXnoY5/code")
GENERATION_ARCHIVE_PATHS = parent.crossfit.CODE_PATHS
ROLES, ARMS = ("metaFit", "internalCheck"), ("generic", "sameSupport", "wrongSupport")
HASH_KEYS = (("rawRasterSHA256", "storedRasterSHA256"), ("trajectorySHA256", "storedTrajectorySHA256"))
REASONS = tuple(f"{stage}-{kind}-copy" for stage in ("encoder-fit", "meta-fit", "same-support", "wrong-support")
                for kind in ("raw-raster", "normalized-trajectory"))
RECIPE = {"seed": 43, "epochs": 30, "episodesPerEpoch": 32, "updates": 960,
    "optimizer": "Adam", "learningRate": .001, "weightDecay": 0., "lossCoefficients": [1., 1., .1],
    "scheduler": None, "augmentation": False, "clipping": False, "selection": "final-epoch-only"}


def configure():
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)


def runtime():
    from .personal_hwrt_stroke_train import _runtime_contract
    return _runtime_contract()


def code_identity():
    result = {**parent_code_identity(), **centroid_code_identity(), **domain_code_identity()}
    for path in (PROTOCOL, "recognition_ml/ichart_recognition_ml/research/personal_support_metric.py",
        "recognition_ml/tests/test_personal_support_metric.py",
        "recognition_ml/ichart_recognition_ml/research/personal_support_metric_experiment.py",
        "recognition_ml/tests/test_personal_support_metric_experiment.py",
        "recognition_ml/ichart_recognition_ml/research/personal_hwrt_stroke_train.py"):
        result[path] = sha(read(ROOT / path, maximum=32 * 1024 * 1024))
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Fixed metric protocol changed")
    return result


def json_file(path, expected=None):
    data = read(Path(path)); require(expected is None or sha(data) == expected, "Artifact SHA changed")
    return parsed(data, name="support-metric")


def publish(directory, name, value):
    data = canonical(value); _write_exclusive(Path(directory) / name, data)
    return sha(data)


def validate_generation_code(recorded, current, archive_directory):
    """Authenticate old generation bytes, separately from executed Python code.

    The only reviewed drift adds persistence evidence/access, not geometry.
    Every other file must still match; no old validator or artifact is changed.
    """
    require(set(recorded) == set(current) and set(GENERATION_ARCHIVE_PATHS) <= set(recorded)
        and recorded.get(SWIFT_CODE) == HISTORICAL_SWIFT_SHA256
        and current.get(SWIFT_CODE) == CURRENT_SWIFT_SHA256
        and all(recorded[k] == current[k] for k in current if k != SWIFT_CODE), "Unreviewed generation-code drift")
    require(all(sha(read(Path(archive_directory) / name)) == recorded[name] for name in recorded),
        "Historical generation-code archive changed")


def load_parent(directory, manifest):
    """Pinned parent validation only; pooled NPZ becomes no fitB Torch tensor."""
    directory, manifest = Path(directory), Path(manifest); before = input_identity(directory); role_bytes = read(manifest)
    require(before["fit-receipt.json"] == parent.audit.RECEIPT_SHA256 and before["features.npz"] == parent.audit.FEATURES_SHA256
        and sha(role_bytes) == ROLE_SHA256, "Frozen parent or role manifest changed")
    receipt = json_file(directory / "fit-receipt.json", before["fit-receipt.json"])
    validate_generation_code(receipt["codeSHA256"], parent.crossfit.code_identity(), GENERATION_ARCHIVE_DIRECTORY)
    require(receipt["metadataSHA256"] == before["metadata.json"] and receipt["featuresSHA256"] == before["features.npz"]
        and receipt["fitPlanSHA256"] == before["fit-plan.json"] and receipt["protocolSHA256"] == before["protocol.md"] == parent.crossfit.PROTOCOL_SHA256
        and receipt["weightsSHA256"] == {arm: before[f"weights/{arm}.pt"] for arm in ("fitA", "fitB")}
        and receipt["weightsSHA256"]["fitA"] == parent.GENERATOR_SHA256, "Cross-fit evidence changed")
    metadata = json_file(directory / "metadata.json", before["metadata.json"])
    fit_plan = json_file(directory / "fit-plan.json", before["fit-plan.json"])
    require(metadata["vocabulary"] == receipt["vocabulary"] and metadata["version"] == parent.crossfit.VERSION
        and all(receipt[k] == v for k, v in fit_plan.items()), "Cross-fit metadata/plan changed")
    payload = read(directory / "features.npz"); require(sha(payload) == before["features.npz"], "Parent arrays changed")
    with np.load(io.BytesIO(payload), allow_pickle=False) as bundle:
        arrays = {name: bundle[name].copy() for name in bundle.files}
    rows = metadata["rows"]; parent.audit.validate_bundle(arrays, rows, receipt)
    roles = parsed(role_bytes, name="inner-roles"); centroid.validate_role_manifest(receipt, rows, roles)
    require(input_identity(directory) == before and read(manifest) == role_bytes, "Parent changed during loading")
    return arrays, rows, receipt, roles


def load_frozen_centroids(directory, binding, roles, vocabulary, *, receipt_sha256):
    """Reconstruct retained A16 means; never construct or invoke an encoder."""
    directory = Path(directory); receipt = json_file(directory / "centroid-receipt.json", receipt_sha256)
    require(receipt_sha256 == CENTROID_SHA256, "Fixed centroid receipt required")
    validate_generation_code(receipt["codeSHA256"], centroid_code_identity(), CENTROID_ARCHIVE_DIRECTORY)
    expected = {"version": centroid.VERSION, "vocabulary": list(vocabulary), "parentBinding": binding,
        "roleManifestSHA256": ROLE_SHA256, "generator": "fitA", "generatorWeightsSHA256": centroid.WEIGHTS_SHA256,
        "generatorStateSHA256": centroid.STATE_SHA256, "encoderFitWriters": roles["encoderFitWriters"],
        "sourceCount": 3104, "countPerLabel": 32, "sourceSHA256": centroid.SOURCE_SHA256,
        "inSampleTrainingCentroids": True, "privateInkUsed": False, "developmentOrReservedInferred": False,
        "productionEligible": False, "sourceAndEncoderUnchanged": True, "storedUnavailableRawRowsRetained": 12}
    require(all(receipt.get(k) == v for k, v in expected.items()) and sha(canonical(roles)) == ROLE_SHA256
        and roles["generator"] == "fitA" and roles["generatorWeightsSHA256"] == centroid.WEIGHTS_SHA256
        and binding["fit-receipt.json"] == parent.audit.RECEIPT_SHA256 and binding["weights/fitA.pt"] == centroid.WEIGHTS_SHA256,
        "Centroid parent/roles changed")
    recorded_runtime = receipt["runtime"]; actual_runtime = runtime()
    require(all(recorded_runtime[k] == actual_runtime[k] for k in ("python", "torch", "numpy", "cpuThreads", "deterministicAlgorithms")), "Centroid runtime changed")
    blobs = {name: read(directory / name) for name in ("centroids.npz", "training-features.npz", "training-rows.json")}
    require(all(sha(blobs[name]) == receipt[key] for name, key in (("centroids.npz", "dataSHA256"),
        ("training-features.npz", "trainingFeaturesSHA256"), ("training-rows.json", "trainingRowsSHA256"))), "Centroid data changed")
    rows = parsed(blobs["training-rows.json"], name="centroid-training-rows")
    require(set(rows) == {"vocabulary", "rows"} and rows["vocabulary"] == list(vocabulary)
        and all(set(r) == centroid.ROW_KEYS and all(isinstance(r[k], str) and centroid._HASH.fullmatch(r[k])
            for k in ("rawRasterSHA256", "trajectorySHA256")) for r in rows["rows"]), "Centroid source rows changed")
    arrays = []
    for name, key in (("centroids.npz", "centroids"), ("training-features.npz", "features")):
        with np.load(io.BytesIO(blobs[name]), allow_pickle=False) as bundle:
            require(bundle.files == [key], "Centroid array keys changed"); arrays.append(bundle[key].copy())
    anchors, features = arrays
    rebuilt = centroid.session_balanced_centroids(features, rows["rows"], roles["encoderFitWriters"], vocabulary)
    require(anchors.dtype == np.float64 and anchors.shape == (97, 128) and np.array_equal(anchors, rebuilt), "Centroids differ from retained means")
    return torch.from_numpy(anchors), receipt


def generation_evidence(parent_receipt, centroid_receipt):
    maps = {"crossfit": parent_receipt["codeSHA256"], "centroids": centroid_receipt["codeSHA256"]}
    validate_generation_code(maps["crossfit"], parent.crossfit.code_identity(), GENERATION_ARCHIVE_DIRECTORY)
    validate_generation_code(maps["centroids"], centroid_code_identity(), CENTROID_ARCHIVE_DIRECTORY)
    directories = {"crossfit": GENERATION_ARCHIVE_DIRECTORY, "centroids": CENTROID_ARCHIVE_DIRECTORY}
    payloads = {f"{kind}/{name}": read(directories[kind] / name) for kind, recorded in maps.items() for name in recorded}
    hashes = {name: sha(data) for name, data in payloads.items()}
    external = {str(directories[kind] / name): recorded[name] for kind, recorded in maps.items() for name in recorded}
    external[str(ROOT / SWIFT_CODE)] = CURRENT_SWIFT_SHA256
    return {"generationCodeSHA256": maps, "generationArchiveSHA256": hashes,
        "currentSwiftSHA256": CURRENT_SWIFT_SHA256}, payloads, external


def source_plan(rows, vocabulary, roles):
    """Metadata-only: fixed catalogs and actual-raw-query copy comparisons."""
    require(len(rows) == 6208 and len(vocabulary) == 97 and vocabulary == sorted(set(vocabulary)), "Complete source grid required")
    role_writers = {"metaFit": roles["metaFitWriters"], "internalCheck": roles["internalValidationWriters"]}
    require(roles["generator"] == "fitA" and roles["freshValidation"] is False
        and all(len(set(w)) == len(w) == 8 for w in role_writers.values())
        and len(set(roles["encoderFitWriters"] + sum(role_writers.values(), []))) == 32, "Disjoint A16/B8/B8 roles required")
    lookup = {(r["writer"], r["session"], r["label"]): i for i, r in enumerate(rows)}
    require(len(lookup) == len(rows) and len({r["sourceID"] for r in rows}) == len(rows), "Duplicate source identities")
    indices = {role: [i for i, r in enumerate(rows) if r["writer"] in writers] for role, writers in role_writers.items()}
    require(indices["metaFit"] == roles["sourceIndices"]["metaFit"] and indices["internalCheck"] == roles["sourceIndices"]["internalValidation"]
        and all(len(v) == 1552 and {(rows[i]["writer"], rows[i]["session"], rows[i]["label"]) for i in v}
            == {(w, s, c) for w in role_writers[k] for s in (1, 2) for c in vocabulary}
            and all(rows[i]["generator"] == "fitA" for i in v) for k, v in indices.items()), "Non-fitA/incomplete role source grid")
    def pool(selected):
        return [{rows[i][k] for i in selected for k in keys if rows[i][k] is not None} for keys in HASH_KEYS]
    encoder = pool([i for i, r in enumerate(rows) if r["writer"] in roles["encoderFitWriters"]]); meta = pool(indices["metaFit"])
    episodes, ledger, targets = {k: [] for k in ROLES}, [], []
    support_ledger = []
    for role, writers in role_writers.items():
        for writer in writers:
            for session in (1, 2):
                for catalog, labels in TASKS.items():
                    support = [lookup[writer, session, c] for c in labels]
                    require(all(rows[i]["storedFailure"] is None for i in support), f"Requested catalog unavailable: {writer}/{session}/{catalog}")
                    donors = [w for w in role_writers["metaFit"] if w != writer]
                    donor = min(donors, key=lambda w: sha(canonical([rows[lookup[w, session, c]]["sourceID"] for c in labels])))
                    wrong = [lookup[donor, session, c] for c in labels]
                    require(all(rows[i]["storedFailure"] is None for i in wrong), "Fixed wrong catalog unavailable; no donor replacement")
                    episode_id = sha(canonical([writer, session, catalog])); copies = []
                    for arm, selected in (("sameSupport", support), ("wrongSupport", wrong)):
                        for n, i in enumerate(selected):
                            for j in selected[:n]:
                                matches = [kind for kind, keys in zip(("raster", "normalized-trajectory"), HASH_KEYS)
                                    if {rows[i][k] for k in keys if rows[i][k] is not None} & {rows[j][k] for k in keys if rows[j][k] is not None}]
                                if rows[i]["sourceID"] == rows[j]["sourceID"]: matches.append("sourceID")
                                if matches:
                                    copies.append({"arm": arm, "indices": [j, i], "reasons": matches})
                                    require(rows[i]["label"] == rows[j]["label"], "Source-identical support has conflicting explicit labels")
                    for i in support:
                        for j in wrong:
                            matches = [kind for kind, keys in zip(("raster", "normalized-trajectory"), HASH_KEYS)
                                if {rows[i][k] for k in keys if rows[i][k] is not None} & {rows[j][k] for k in keys if rows[j][k] is not None}]
                            if matches:
                                copies.append({"arm": "sameSupport-vs-wrongSupport", "indices": [i, j], "reasons": matches})
                                require(rows[i]["label"] == rows[j]["label"], "Cross-arm source-identical support has conflicting explicit labels")
                    support_ledger.append({"episodeID": episode_id, "copies": copies,
                        "commitments": {arm: [{k: rows[i][k] for k in ("sourceID", "label", "rawRasterSHA256", "storedRasterSHA256", "trajectorySHA256", "storedTrajectorySHA256")} for i in selected]
                            for arm, selected in (("sameSupport", support), ("wrongSupport", wrong))}})
                    query = [lookup[writer, 3 - session, c] for c in vocabulary]
                    groups = [("encoder-fit", encoder), ("same-support", pool(support)), ("wrong-support", pool(wrong))]
                    if role == "internalCheck": groups.insert(1, ("meta-fit", meta))
                    eligible = []
                    for i in query:
                        reasons = [f"{stage}-{kind}-copy" for stage, pools in groups
                            for kind, key, hashes in zip(("raw-raster", "normalized-trajectory"), ("rawRasterSHA256", "trajectorySHA256"), pools)
                            if rows[i][key] in hashes]
                        ledger.append({"episodeID": episode_id, "queryIndex": i, "reasons": reasons})
                        if not reasons: eligible.append(i)
                    if role == "metaFit":
                        labels_used = [vocabulary.index(rows[i]["label"]) for i in eligible]
                        require(any(rows[i]["label"] in labels for i in eligible) and any(rows[i]["label"] not in labels for i in eligible), "Copy rules removed a training stratum")
                        targets.append({"episodeID": episode_id, "queryIndices": eligible, "targets": labels_used})
                    episodes[role].append({"episodeID": episode_id, "writer": writer, "supportSession": session,
                        "querySession": 3 - session, "catalog": catalog, "support": support, "wrongSupport": wrong,
                        "wrongWriter": donor, "supportLabels": list(labels), "queryIndices": query})
    generator = torch.Generator().manual_seed(43)
    order = [i for _ in range(30) for i in torch.randperm(32, generator=generator).tolist()]
    forward = {"version": VERSION, "vocabulary": vocabulary, "writers": role_writers, "encoderFitWriters": roles["encoderFitWriters"],
        "sourceIndices": indices, "owners": {str(i): {k: rows[i][k] for k in ("writer", "session", "generator")} for v in indices.values() for i in v},
        "episodes": episodes, "updateEpisodeIndices": order}
    unavailable = [{"sourceIndex": i, "failure": r["storedFailure"], "writer": r["writer"], "generator": r["generator"]}
                   for i, r in enumerate(rows) if r["storedFailure"] is not None]
    truth = {"version": VERSION, "rows": [{"queryIndex": i, "target": vocabulary.index(rows[i]["label"]),
        "writer": rows[i]["writer"], "session": rows[i]["session"]} for v in indices.values() for i in v]}
    return forward, {"version": VERSION, "rows": targets}, truth, {"version": VERSION, "queryRows": ledger, "supportRows": support_ledger, "sourceUnavailable": unavailable}


def validate_forward(plan):
    require(plan["version"] == VERSION and len(plan["vocabulary"]) == 97 and plan["vocabulary"] == sorted(set(plan["vocabulary"]))
        and len(plan["allowedLabels"]) == len(set(plan["allowedLabels"])) == 41 and set(plan["allowedLabels"]) <= set(plan["vocabulary"]), "Vocabulary/domain changed")
    require(set(plan["episodes"]) == set(plan["sourceIndices"]) == set(plan["writers"]) == set(ROLES)
        and len(set(plan["encoderFitWriters"] + sum(plan["writers"].values(), []))) == 32, "Writer roles changed")
    for role in ROLES:
        indices = set(plan["sourceIndices"][role]); require(len(indices) == 1552 and len(plan["writers"][role]) == 8 and len(plan["episodes"][role]) == 32, "Missing role episodes/sources")
        require({(p["writer"], p["supportSession"], p["catalog"]) for p in plan["episodes"][role]}
            == {(w, s, k) for w in plan["writers"][role] for s in (1, 2) for k in TASKS}, "Session/catalog coverage changed")
        for p in plan["episodes"][role]:
            require(set(p) == {"episodeID", "writer", "supportSession", "querySession", "catalog", "support", "wrongSupport", "wrongWriter", "supportLabels", "queryIndices"}
                and p["episodeID"] == sha(canonical([p["writer"], p["supportSession"], p["catalog"]]))
                and p["supportLabels"] == list(TASKS[p["catalog"]]) and p["querySession"] == 3 - p["supportSession"]
                and len(p["queryIndices"]) == len(set(p["queryIndices"])) == 97 and set(p["queryIndices"]) <= indices
                and len(p["support"]) == len(set(p["support"])) == len(p["wrongSupport"]) == len(set(p["wrongSupport"])) == len(p["supportLabels"])
                and set(p["support"]) <= indices and set(p["wrongSupport"]) <= set(plan["sourceIndices"]["metaFit"])
                and p["wrongWriter"] in plan["writers"]["metaFit"] and p["wrongWriter"] != p["writer"], "Invalid answer-free episode")
            for field, writer, session in (("support", p["writer"], p["supportSession"]), ("wrongSupport", p["wrongWriter"], p["supportSession"]), ("queryIndices", p["writer"], p["querySession"])):
                require(all(plan["owners"][str(i)] == {"writer": writer, "session": session, "generator": "fitA"} for i in p[field]), "Episode source-role leakage")
    order = plan["updateEpisodeIndices"]
    generator = torch.Generator().manual_seed(43)
    require(order == [i for _ in range(30) for i in torch.randperm(32, generator=generator).tolist()], "Fixed seed43/960 update order changed")


def npz_bytes(**arrays):
    stream = io.BytesIO(); np.savez(stream, **arrays); return stream.getvalue()


def prepare(crossfit, roles_path, centroid_directory, domain_path, output):
    configure(); code = code_identity(); binding = input_identity(crossfit)
    arrays, rows, receipt, roles = load_parent(crossfit, roles_path)
    anchors, centroid_receipt = load_frozen_centroids(centroid_directory, binding, roles, receipt["vocabulary"], receipt_sha256=CENTROID_SHA256)
    generation, generation_payloads, generation_external = generation_evidence(receipt, centroid_receipt)
    domain_bytes = read(Path(domain_path)); domain = validate_domain(domain_bytes, DOMAIN_SHA256, receipt["vocabulary"])
    forward, targets, truth, ledger = source_plan(rows, receipt["vocabulary"], roles); forward["allowedLabels"] = domain["allowedLabels"]; validate_forward(forward)
    external = {str(Path(crossfit) / name): h for name, h in binding.items()}
    external[str(Path(roles_path))] = ROLE_SHA256; external[str(Path(domain_path))] = DOMAIN_SHA256
    external.update({str(Path(centroid_directory) / name): sha(read(Path(centroid_directory) / name)) for name in
        ("centroid-receipt.json", "centroids.npz", "training-features.npz", "training-rows.json")})
    external.update(generation_external)
    destination = _new_output(Path(output)); artifacts = {}
    for name, value in (("forward-plan.json", forward), ("meta-targets.json", targets), ("score-truth.json", truth), ("copy-ledger.json", ledger)):
        artifacts[name] = publish(destination, name, value)
    for role, filename in (("metaFit", "meta-features.npz"), ("internalCheck", "check-features.npz")):
        selected = forward["sourceIndices"][role]
        payload = npz_bytes(source_indices=np.asarray(selected, dtype=np.int64), **{k: np.array(arrays[k][selected], dtype=np.float64, copy=True) for k in ("raw_features", "raw_logits", "stored_features")})
        _write_exclusive(destination / filename, payload); artifacts[filename] = sha(payload)
    payload = npz_bytes(anchors=anchors.numpy()); _write_exclusive(destination / "anchors.npz", payload); artifacts["anchors.npz"] = sha(payload)
    _write_exclusive(destination / "protocol.md", read(ROOT / PROTOCOL))
    for name, expected in code.items():
        data = read(ROOT / name, maximum=32 * 1024 * 1024); require(sha(data) == expected, "Code changed before source freeze")
        _write_exclusive(destination / "code" / name, data)
    for name, data in generation_payloads.items(): _write_exclusive(destination / "generation-code" / name, data)
    result = {"version": VERSION, "protocolSHA256": PROTOCOL_SHA256, "coreVersion": core.VERSION, "codeSHA256": code,
        **generation,
        "runtime": runtime(), "recipe": RECIPE, "artifacts": artifacts, "externalSHA256": external,
        "sourceOnlyCounts": {role: {"episodes": 32, "scheduledExposures": 3104, "distinctSources": 1552,
            "eligibleExposures": sum(not r["reasons"] for r in ledger["queryRows"] if r["episodeID"] in {p["episodeID"] for p in forward["episodes"][role]})} for role in ROLES},
        "freshValidation": False, "privateInkUsed": False, "encoderInferred": False, "productionEligible": False}
    require(code_identity() == code and all(sha(read(Path(p))) == h for p, h in external.items()), "Preparation input/code changed")
    result_sha = publish(destination, "commitment.json", result)
    return {"commitmentSHA256": result_sha, "counts": result["sourceOnlyCounts"]}


def load_binding(directory, expected):
    configure(); directory = Path(directory); binding = json_file(directory / "commitment.json", expected)
    require(binding["version"] == VERSION and binding["protocolSHA256"] == PROTOCOL_SHA256 and binding["coreVersion"] == core.VERSION
        and binding["recipe"] == RECIPE and binding["codeSHA256"] == code_identity() and binding["runtime"] == runtime()
        and binding["freshValidation"] is False and binding["privateInkUsed"] is False and binding["encoderInferred"] is False, "Frozen preparation identity changed")
    require(sha(read(directory / "protocol.md")) == PROTOCOL_SHA256, "Frozen protocol changed")
    for name, expected_code in binding["codeSHA256"].items():
        require(sha(read(directory / "code" / name, maximum=32 * 1024 * 1024)) == expected_code, "Executed-code snapshot changed")
    require(binding["currentSwiftSHA256"] == CURRENT_SWIFT_SHA256 and all(
        sha(read(directory / "generation-code" / name)) == h for name, h in binding["generationArchiveSHA256"].items()),
        "Generation-code snapshot/current Swift changed")
    require(all(sha(read(Path(p))) == h for p, h in binding["externalSHA256"].items()), "Bound external source changed")
    plan = json_file(directory / "forward-plan.json", binding["artifacts"]["forward-plan.json"]); validate_forward(plan)
    return binding, plan


def feature_tensors(directory, binding, plan, role):
    filename = "meta-features.npz" if role == "metaFit" else "check-features.npz"
    payload = read(Path(directory) / filename); require(sha(payload) == binding["artifacts"][filename], "Frozen role arrays changed")
    with np.load(io.BytesIO(payload), allow_pickle=False) as bundle:
        require(set(bundle.files) == {"source_indices", "raw_features", "raw_logits", "stored_features"}, "Answer-free array schema changed")
        indices = bundle["source_indices"]; require(indices.dtype == np.int64 and indices.tolist() == plan["sourceIndices"][role], "Role indices changed")
        shapes = {"raw_features": (1552, 128), "raw_logits": (1552, 97), "stored_features": (1552, 128)}
        require(all(bundle[k].shape == s and bundle[k].dtype == np.float64 and np.isfinite(bundle[k]).all() for k, s in shapes.items()), "Invalid frozen role tensor")
        tensors = {k: torch.from_numpy(bundle[k].copy()) for k in shapes}
    return tensors, {i: n for n, i in enumerate(indices.tolist())}


def anchor_tensor(directory, binding):
    payload = read(Path(directory) / "anchors.npz"); require(sha(payload) == binding["artifacts"]["anchors.npz"], "Frozen anchors changed")
    with np.load(io.BytesIO(payload), allow_pickle=False) as bundle:
        require(bundle.files == ["anchors"] and bundle["anchors"].shape == (97, 128) and bundle["anchors"].dtype == np.float64, "Full97 anchors required")
        return torch.from_numpy(bundle["anchors"].copy())


def episode_forward(model, tensors, remap, episode, anchors, vocabulary, *, wrong=False, queries=None):
    query = episode["queryIndices"] if queries is None else queries
    take = lambda name, indices: tensors[name][[remap[i] for i in indices]]
    support = episode["wrongSupport"] if wrong else episode["support"]
    return model(take("raw_features", query), take("raw_logits", query), anchors, vocabulary,
                 take("stored_features", support), episode["supportLabels"])


def optimizer_step(model, optimizer, inputs, targets):
    before = {str(i): tensor_sha(inputs[i]) for i in (0, 1, 2, 4)}
    optimizer.zero_grad(set_to_none=True); output = model(*inputs); loss = core.support_metric_loss(output, targets)
    loss.total.backward(); require(all(p.grad is not None and bool(torch.isfinite(p.grad).all()) for p in model.parameters()), "Missing/nonfinite scorer gradient")
    optimizer.step(); require(all(bool(torch.isfinite(p).all()) for p in model.parameters()), "Nonfinite updated scorer")
    require(before == {str(i): tensor_sha(inputs[i]) for i in (0, 1, 2, 4)}, "Forward/loss mutated frozen inputs")
    return {"total": float(loss.total.detach()), "crossEntropy": float(loss.cross_entropy.detach()), "untaughtKL": float(loss.untaught_kl.detach()), "locality": float(loss.locality.detach()), "inputSHA256": before}


def fit(prepared, preparation_sha256, output):
    binding, plan = load_binding(prepared, preparation_sha256); destination = _new_output(Path(output))
    target = json_file(Path(prepared) / "meta-targets.json", binding["artifacts"]["meta-targets.json"])
    by_id = {p["episodeID"]: p for p in target["rows"]}; episodes = plan["episodes"]["metaFit"]
    require(len(by_id) == len(target["rows"]) == 32 and set(by_id) == {p["episodeID"] for p in episodes}, "Meta-only target coverage changed")
    tensors, remap = feature_tensors(prepared, binding, plan, "metaFit"); anchors = anchor_tensor(prepared, binding)
    initial_inputs = {k: tensor_sha(v) for k, v in tensors.items()}; anchor_hash = tensor_sha(anchors)
    prepared_inputs = []
    for p in episodes:
        t = by_id[p["episodeID"]]; require(set(t) == {"episodeID", "queryIndices", "targets"} and len(t["queryIndices"]) == len(set(t["queryIndices"]))
            and set(t["queryIndices"]) <= set(p["queryIndices"]) and len(t["targets"]) == len(t["queryIndices"])
            and all(type(i) is int and 0 <= i < 97 for i in t["targets"]), "Training target role/count changed")
        take = lambda name, indices: tensors[name][[remap[i] for i in indices]]
        prepared_inputs.append(((take("raw_features", t["queryIndices"]), take("raw_logits", t["queryIndices"]), anchors,
            plan["vocabulary"], take("stored_features", p["support"]), p["supportLabels"]), torch.tensor(t["targets"], dtype=torch.long)))
    model = core.PersonalSupportMetric(); initial = {n: p.detach().clone() for n, p in model.state_dict().items()}
    manifest = {"version": VERSION, "preparationSHA256": preparation_sha256, "codeSHA256": binding["codeSHA256"],
        "recipe": RECIPE, "initialStateSHA256": _state_digest(initial), "updateOrderSHA256": sha(canonical(plan["updateEpisodeIndices"]))}
    publish(destination, "run-manifest.json", manifest)
    optimizer = torch.optim.Adam(model.parameters(), lr=.001, weight_decay=0.); history = []
    for step, index in enumerate(plan["updateEpisodeIndices"], 1):
        history.append(optimizer_step(model, optimizer, *prepared_inputs[index]))
        if step % 32 == 0: print(canonical({"epoch": step // 32, "updates": step, "meanLoss": sum(r["total"] for r in history[-32:]) / 32}).decode(), flush=True)
    require(len(history) == 960 and all(float((p - initial[n]).abs().max()) > 0 for n, p in model.state_dict().items()), "Completed count/nonzero scorer blocks failed")
    require(initial_inputs == {k: tensor_sha(v) for k, v in tensors.items()} and tensor_sha(anchors) == anchor_hash, "Frozen inputs were mutated")
    buffer = io.BytesIO(); torch.save(model.state_dict(), buffer); payload = buffer.getvalue(); _write_exclusive(destination / "weights.pt", payload)
    reloaded = core.PersonalSupportMetric(); reloaded.load_state_dict(torch.load(io.BytesIO(read(destination / "weights.pt")), weights_only=True), strict=True)
    state_hash = _state_digest(model.state_dict()); require(_state_digest(reloaded.state_dict()) == state_hash, "Checkpoint reload changed")
    require(load_binding(prepared, preparation_sha256)[0] == binding, "Inputs/code changed during fit")
    receipt = {**manifest, "protocolSHA256": PROTOCOL_SHA256, "coreVersion": core.VERSION, "runtime": runtime(),
        "weightsSHA256": sha(payload), "finalStateSHA256": state_hash, "history": history, "updates": 960,
        "inputTensorSHA256": initial_inputs, "anchorTensorSHA256": anchor_hash, "manifestSHA256": sha(canonical(manifest)), "finalOnly": True}
    return {"fitReceiptSHA256": publish(destination, "fit-receipt.json", receipt), "updates": 960}


def load_fit(directory, expected, preparation_sha256, binding):
    directory = Path(directory); receipt = json_file(directory / "fit-receipt.json", expected)
    require(receipt["version"] == VERSION and receipt["preparationSHA256"] == preparation_sha256 and receipt["coreVersion"] == core.VERSION
        and receipt["codeSHA256"] == binding["codeSHA256"] and receipt["protocolSHA256"] == PROTOCOL_SHA256 and receipt["recipe"] == RECIPE
        and receipt["runtime"] == runtime() and receipt["updates"] == len(receipt["history"]) == 960 and receipt["finalOnly"] is True, "Fixed final scorer identity changed")
    require(sha(read(directory / "run-manifest.json")) == receipt["manifestSHA256"], "Run manifest changed")
    manifest = json_file(directory / "run-manifest.json")
    require(all(receipt[k] == v for k, v in manifest.items()) and all(np.isfinite(r[k]) for r in receipt["history"]
        for k in ("total", "crossEntropy", "untaughtKL", "locality")), "Manifest/finite history changed")
    payload = read(directory / "weights.pt"); require(sha(payload) == receipt["weightsSHA256"], "Final checkpoint bytes changed")
    model = core.PersonalSupportMetric(); model.load_state_dict(torch.load(io.BytesIO(payload), weights_only=True), strict=True)
    require(all(bool(torch.isfinite(t).all()) for t in model.state_dict().values()) and _state_digest(model.state_dict()) == receipt["finalStateSHA256"], "Final scorer state changed")
    return model.eval(), receipt


def predict(prepared, preparation_sha256, fitted, fit_sha256, output):
    binding, plan = load_binding(prepared, preparation_sha256); model, fit_receipt = load_fit(fitted, fit_sha256, preparation_sha256, binding)
    state_before = _state_digest(model.state_dict()); anchors = anchor_tensor(prepared, binding); anchors_before = tensor_sha(anchors)
    meta, meta_map = feature_tensors(prepared, binding, plan, "metaFit"); check, check_map = feature_tensors(prepared, binding, plan, "internalCheck")
    input_before = {role: {k: tensor_sha(v) for k, v in tensors.items()} for role, tensors in (("metaFit", meta), ("internalCheck", check))}
    combined = {k: torch.cat((meta[k], check[k])) for k in meta}; combined_before = {k: tensor_sha(v) for k, v in combined.items()}
    full_map = {**meta_map, **{i: n + 1552 for i, n in check_map.items()}}
    episodes = []; failures = 0
    with torch.no_grad():
        for role, tensors, remap in (("metaFit", meta, meta_map), ("internalCheck", check, check_map)):
            for p in plan["episodes"][role]:
                logits = {"generic": tensors["raw_logits"][[remap[i] for i in p["queryIndices"]]].tolist()}; failed = {"generic": None}
                for arm, wrong in (("sameSupport", False), ("wrongSupport", True)):
                    try:
                        result = episode_forward(model, combined, full_map, p, anchors, plan["vocabulary"], wrong=wrong).candidate_logits
                        replay = episode_forward(model, combined, full_map, p, anchors, plan["vocabulary"], wrong=wrong).candidate_logits
                        require(torch.equal(result, replay) and result.shape == (97, 97) and bool(torch.isfinite(result).all()), "Invalid/nonrepeatable complete logits")
                        logits[arm] = result.tolist(); failed[arm] = None
                    except (ValueError, RuntimeError) as error:
                        logits[arm] = None; failed[arm] = f"{type(error).__name__}: {error}"; failures += 1
                episodes.append({"episodeID": p["episodeID"], "role": role, "logits": logits, "failures": failed})
    require(_state_digest(model.state_dict()) == state_before and tensor_sha(anchors) == anchors_before
        and input_before == {role: {k: tensor_sha(v) for k, v in tensors.items()} for role, tensors in (("metaFit", meta), ("internalCheck", check))}
        and combined_before == {k: tensor_sha(v) for k, v in combined.items()}
        and all(sha(read(Path(prepared) / name)) == binding["artifacts"][name] for name in ("meta-features.npz", "check-features.npz", "anchors.npz"))
        and load_binding(prepared, preparation_sha256)[0] == binding and load_fit(fitted, fit_sha256, preparation_sha256, binding)[1] == fit_receipt, "Prediction input/state changed")
    packet = {"version": VERSION, "preparationSHA256": preparation_sha256, "fitReceiptSHA256": fit_sha256,
        "codeSHA256": binding["codeSHA256"], "finalStateSHA256": state_before, "episodes": episodes,
        "inputTensorSHA256": input_before, "combinedTensorSHA256": combined_before, "anchorTensorSHA256": anchors_before,
        "queryTruthRead": False, "deterministicReplayVerified": True, "failures": failures}
    validate_packet(packet, plan); destination = _new_output(Path(output))
    return {"predictionsSHA256": publish(destination, "predictions.json", packet), "episodes": 64, "scheduledQueries": 6208, "failures": failures}


def validate_packet(packet, plan):
    expected = {p["episodeID"]: (role, p) for role in ROLES for p in plan["episodes"][role]}
    require(packet["version"] == VERSION and packet["queryTruthRead"] is False and packet["deterministicReplayVerified"] is True
        and len(packet["episodes"]) == len(expected) == 64 and {p["episodeID"] for p in packet["episodes"]} == set(expected), "Frozen prediction coverage changed")
    for p in packet["episodes"]:
        require(p["role"] == expected[p["episodeID"]][0] and set(p["logits"]) == set(p["failures"]) == set(ARMS), "Frozen arms/role changed")
        require(p["failures"]["generic"] is None and p["logits"]["generic"] is not None, "Raw baseline must remain complete")
        for arm in ARMS:
            value = p["logits"][arm]
            if value is None: require(isinstance(p["failures"][arm], str) and bool(p["failures"][arm]), "Missing failure record")
            else:
                matrix = np.asarray(value); require(matrix.shape == (97, 97) and np.isfinite(matrix).all() and p["failures"][arm] is None, "Incomplete/nonfinite frozen logits")
    require(packet["failures"] == sum(p["failures"][a] is not None for p in packet["episodes"] for a in ARMS), "Failure denominator changed")


def projected(logits, vocabulary, allowed):
    if logits is None: return None, None
    values = np.asarray(logits); require(values.shape == (97,) and np.isfinite(values).all(), "Full97 finite row required")
    winners = np.flatnonzero(values == values.max())
    if len(winners) != 1: return None, None
    index = int(winners[0]); return index, index if vocabulary[index] in allowed else None


def summarize(rows):
    methods = {a: {"correct": sum(r["inDomain"] and r[a] == r["target"] for r in rows),
        "wrong": sum(r[a] is not None and r[a] != r["target"] for r in rows), "noRead": sum(r[a] is None for r in rows)} for a in ARMS}
    gains = sum(r["inDomain"] and r["generic"] != r["target"] and r["sameSupport"] == r["target"] for r in rows)
    lost = sum(r["inDomain"] and r["generic"] == r["target"] and r["sameSupport"] != r["target"] for r in rows)
    danger = sum(r["generic"] in (None, r["target"]) and r["sameSupport"] not in (None, r["target"]) for r in rows)
    untaught = sum(not r["taught"] and r["inDomain"] and r["generic"] == r["target"] and r["sameSupport"] != r["target"] for r in rows)
    ood = sum(not r["inDomain"] and r["generic"] is None and r["sameSupport"] is not None for r in rows)
    writer_net = {w: sum(int(r["sameSupport"] == r["target"]) - int(r["generic"] == r["target"]) for r in rows if r["inDomain"] and r["writer"] == w) for w in sorted({r["writer"] for r in rows})}
    session_beats_wrong = {str(s): sum(r["inDomain"] and r["sameSupport"] == r["target"] for r in rows if r["supportSession"] == s)
        > sum(r["inDomain"] and r["wrongSupport"] == r["target"] for r in rows if r["supportSession"] == s) for s in (1, 2)}
    gates = {"positiveCorrectNet": gains > lost, "sameBeatsWrong": methods["sameSupport"]["correct"] > methods["wrongSupport"]["correct"],
        "everyWriterNonnegative": bool(writer_net) and min(writer_net.values()) >= 0, "noUntaughtLostCorrect": untaught == 0,
        "noCorrectOrUnresolvedToWrong": danger == 0, "noNewOutOfDomainFalseAccept": ood == 0,
        "completeFiniteEvidence": bool(rows) and not any(r["invalid"] for r in rows), "sameBeatsWrongEachSession": all(session_beats_wrong.values())}
    return {"exposures": len(rows), "domainQueries": sum(r["inDomain"] for r in rows), "distinctSources": len({r["queryIndex"] for r in rows}), "repeatedExposures": len(rows) - len({r["queryIndex"] for r in rows}),
        "methods": methods, "gains": gains, "lostCorrect": lost, "net": gains - lost, "correctOrUnresolvedToWrong": danger,
        "untaughtLostCorrect": untaught, "newOutOfDomainFalseAccept": ood, "writerNet": writer_net, "sameBeatsWrongBySupportSession": session_beats_wrong,
        "invalid": sum(r["invalid"] for r in rows), "gates": gates, "passes": all(gates.values())}


def score(prepared, preparation_sha256, predictions, predictions_sha256, output):
    binding, plan = load_binding(prepared, preparation_sha256)
    packet = json_file(Path(predictions) / "predictions.json", predictions_sha256); validate_packet(packet, plan)
    require(packet["preparationSHA256"] == preparation_sha256 and packet["codeSHA256"] == binding["codeSHA256"], "Prediction/preparation commitment changed")
    # Only after full prediction coverage and commitments are authenticated, join answers.
    truth = json_file(Path(prepared) / "score-truth.json", binding["artifacts"]["score-truth.json"])
    ledger = json_file(Path(prepared) / "copy-ledger.json", binding["artifacts"]["copy-ledger.json"])
    labels = {r["queryIndex"]: r for r in truth["rows"]}; copies = {(r["episodeID"], r["queryIndex"]): r["reasons"] for r in ledger["queryRows"]}
    require(len(labels) == len(truth["rows"]) == 3104 and len(copies) == len(ledger["queryRows"]) == 6208, "Truth/copy source coverage changed")
    expected = {p["episodeID"]: (role, p) for role in ROLES for p in plan["episodes"][role]}; rows = []
    for frozen in packet["episodes"]:
        role, p = expected[frozen["episodeID"]]
        for position, index in enumerate(p["queryIndices"]):
            t = labels[index]; require(t["writer"] == p["writer"] and t["session"] == p["querySession"] and type(t["target"]) is int and 0 <= t["target"] < 97, "Scoring source join changed")
            r = {"episodeID": p["episodeID"], "queryIndex": index, "role": role, "catalog": p["catalog"], "writer": p["writer"],
                "supportSession": p["supportSession"], "querySession": p["querySession"], "target": t["target"],
                "inDomain": plan["vocabulary"][t["target"]] in plan["allowedLabels"], "taught": plan["vocabulary"][t["target"]] in p["supportLabels"],
                "copyReasons": copies[p["episodeID"], index], "invalid": any(frozen["failures"][a] is not None for a in ARMS), "full97": {}}
            for arm in ARMS:
                vector = None if frozen["logits"][arm] is None else frozen["logits"][arm][position]
                raw, domain = projected(vector, plan["vocabulary"], plan["allowedLabels"]); r["full97"][arm] = raw; r[arm] = domain
            rows.append(r)
    reports = {}
    for role in ROLES:
        reports[role] = {}
        for catalog in TASKS:
            raw = [r for r in rows if r["role"] == role and r["catalog"] == catalog]
            require(len(raw) == 1552, "A raw97 source row was removed")
            reports[role][catalog] = {}
            for cohort, selected in (("raw", raw), ("noCopy", [r for r in raw if not r["copyReasons"]])):
                report = summarize(selected)
                report["full97Correct"] = {a: sum(r["full97"][a] == r["target"] for r in selected) for a in ARMS}
                report["strata"] = {name: summarize([r for r in selected if r["taught"] == taught]) for name, taught in (("taught", True), ("untaught", False))}
                report["writers"] = {w: summarize([r for r in selected if r["writer"] == w]) for w in plan["writers"][role]}
                report["sessions"] = {str(s): summarize([r for r in selected if r["supportSession"] == s]) for s in (1, 2)}
                reports[role][catalog][cohort] = report
    result = {"version": VERSION, "preparationSHA256": preparation_sha256, "predictionsSHA256": predictions_sha256,
        "reports": reports, "rows": rows, "passesInternalReuseScreen": all(reports["internalCheck"][k][c]["passes"] for k in TASKS for c in ("raw", "noCopy")),
        "freshValidation": False, "productionEligible": False}
    require(load_binding(prepared, preparation_sha256)[0] == binding and sha(read(Path(predictions) / "predictions.json")) == predictions_sha256, "Scoring inputs changed")
    destination = _new_output(Path(output)); return {"scoreSHA256": publish(destination, "score.json", result), "passes": result["passesInternalReuseScreen"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest="operation", required=True)
    p = sub.add_parser("prepare")
    for name in ("crossfit", "roles", "centroids", "domain", "output"): p.add_argument("--" + name, type=Path, required=True)
    for operation in ("fit", "predict", "score"):
        p = sub.add_parser(operation); p.add_argument("--prepared", type=Path, required=True); p.add_argument("--preparation-sha256", required=True); p.add_argument("--output", type=Path, required=True)
        if operation == "predict": p.add_argument("--fit", type=Path, required=True); p.add_argument("--fit-sha256", required=True)
        if operation == "score": p.add_argument("--predictions", type=Path, required=True); p.add_argument("--predictions-sha256", required=True)
    a = parser.parse_args()
    if a.operation == "prepare": result = prepare(a.crossfit, a.roles, a.centroids, a.domain, a.output)
    elif a.operation == "fit": result = fit(a.prepared, a.preparation_sha256, a.output)
    elif a.operation == "predict": result = predict(a.prepared, a.preparation_sha256, a.fit, a.fit_sha256, a.output)
    else: result = score(a.prepared, a.preparation_sha256, a.predictions, a.predictions_sha256, a.output)
    print(canonical(result).decode(), flush=True)


if __name__ == "__main__": main()

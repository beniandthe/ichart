"""Bound fitA in-sample centroids; no head fitting, query inference or app writes."""
from __future__ import annotations

import argparse
import io
import json
from pathlib import Path
import platform
import re

import numpy as np
import torch

from . import personal_centroid_transport as transport
from . import personal_support_crossfit as crossfit
from . import personal_support_signal_audit as core
from .personal_cross_writer_contrastive import _new_output, _regular_file, _state_digest, _write_exclusive
from .personal_support_inner_roles import inner_roles
from .personal_support_retrieval import canonical, require, sha
from .personal_visual_encoder import PersonalVisualEncoder, encode_samples, infer
from .uji_personal import SOURCE_SHA256, parse_source, trajectory_fingerprint

VERSION = "personal-fitA-training-centroids-v1"
MANIFEST_SHA256 = "47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa"
WEIGHTS_SHA256 = "1cfbcd2c11fe5173bbd7367121fdb9c4c1d965618d9272a6c7421dd6901261c1"
STATE_SHA256 = "42307941fda891c989149585727fdf402f442edfa6a1e8c155429c6719618286"
EXECUTION = "docs/personal-centroid-transport-execution-2026-10-01.md"
EXECUTION_SHA256 = "2dcb455e70b7519ab9c48c59a4bf8f6eaa1266ade070de3bbe36c5081f4dc444"
ROW_KEYS = {"sourceID", "writer", "session", "label", "rawRasterSHA256", "trajectorySHA256", "generator"}
PLANNER_FILES = ("recognition_ml/ichart_recognition_ml/research/personal_support_inner_roles.py",
                 "recognition_ml/tests/test_personal_support_inner_roles.py")
_WRITER = re.compile(r"trn_(?:UJI|UPV)_W[0-9]{2}")
_SOURCE_ID = re.compile(r"((?:trn|tst)_(?:UJI|UPV)_W[0-9]{2})-0([12])")
_HASH = re.compile(r"[0-9a-f]{64}")


def code_identity():
    root = Path(__file__).resolve().parents[3]
    paths = (EXECUTION, "recognition_ml/ichart_recognition_ml/research/personal_training_centroids.py",
        "recognition_ml/tests/test_personal_training_centroids.py",
        *PLANNER_FILES,
        "recognition_ml/ichart_recognition_ml/research/personal_support_signal_audit.py")
    result = {**crossfit.code_identity(), **transport.code_identity(),
              **{name: sha((root / name).read_bytes()) for name in paths}}
    require(result[EXECUTION] == EXECUTION_SHA256, "Centroid execution protocol changed")
    return result


def planner_code_identity():
    root = Path(__file__).resolve().parents[3]
    return {name: sha((root / name).read_bytes()) for name in PLANNER_FILES}


def validate_role_manifest(receipt, rows, roles):
    expected = inner_roles(receipt, rows)
    require(set(roles) == set(expected) | {"plannerCodeSHA256"}
        and all(roles[name] == value for name, value in expected.items()), "Source-only learned-stage roles changed")
    require(roles["plannerCodeSHA256"] == planner_code_identity(), "Role planner code changed")


def _role_contract(writers, vocabulary):
    require(len(writers) == len(set(writers)) == 16 and all(isinstance(w, str) and _WRITER.fullmatch(w) for w in writers)
        and len(vocabulary) == 97 and list(vocabulary) == sorted(set(vocabulary))
        and all(isinstance(c, str) and len(c) == 1 and not c.isspace() for c in vocabulary), "Exact A16/full97 roles required")


def validate_rows(rows, writers, vocabulary, generator="fitA"):
    _role_contract(writers, vocabulary)
    require(len(rows) == 3104 and all(type(r["session"]) is int and r["session"] in (1, 2)
        and r["sourceID"] == f'{r["writer"]}-{r["session"]}-{r["label"]}'
        and r["generator"] == generator for r in rows)
        and [r["sourceID"] for r in rows] == sorted({r["sourceID"] for r in rows})
        and {(r["writer"], r["session"], r["label"]) for r in rows}
            == {(w, s, c) for w in writers for s in (1, 2) for c in vocabulary}, "A16 source grid/order/generator changed")


def select_training_source(text, writers, vocabulary):
    """Parse coordinates only for A16 WORD blocks; other point lines are opaque."""
    _role_contract(writers, vocabulary)
    allowed, selected = set(writers), []
    lines = iter(line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("//"))
    try:
        for line in lines:
            header = line.split()
            require(len(header) == 3 and header[0] == "WORD" and len(header[1]) == 1, "Malformed source WORD header")
            identity = _SOURCE_ID.fullmatch(header[2])
            require(identity is not None, "Malformed source writer/session header")
            count_line = next(lines)
            count = count_line.split()
            require(len(count) == 2 and count[0] == "NUMSTROKES" and 1 <= int(count[1]) <= 64, "Malformed source stroke header")
            keep = identity[1] in allowed
            points = []
            for _ in range(int(count[1])):
                payload = next(lines)
                if keep:
                    points.append(payload)
            if keep:
                selected.extend(parse_source("\n".join((line, count_line, *points))))
    except StopIteration as exc:
        raise ValueError("Truncated selected-source scan") from exc
    samples = tuple(sorted(selected, key=lambda s: s.identity))
    rows = [{"sourceID": s.identity, "writer": s.writer, "session": s.session, "label": s.label,
             "generator": "fitA"} for s in samples]
    validate_rows(rows, writers, vocabulary)
    return samples


def match_source_rows(samples, raster_hashes, reference, writers, vocabulary):
    validate_rows(reference, writers, vocabulary, "fitB")
    require(len(samples) == len(raster_hashes) == 3104, "All raw A16 samples required")
    rows = [{"sourceID": s.identity, "writer": s.writer, "session": s.session, "label": s.label,
        "rawRasterSHA256": h, "trajectorySHA256": trajectory_fingerprint(s), "generator": "fitA"}
        for s, h in zip(samples, raster_hashes)]
    validate_rows(rows, writers, vocabulary)
    require(all(all(row[key] == original[key] for key in ROW_KEYS - {"generator"})
                for row, original in zip(rows, reference)), "A16 raw raster/trajectory/source binding changed")
    return rows


def session_balanced_centroids(features, rows, writers, vocabulary):
    validate_rows(rows, writers, vocabulary)
    require(isinstance(features, np.ndarray) and features.dtype == np.float32 and features.shape == (3104, 128)
        and np.isfinite(features).all() and np.allclose(np.linalg.norm(features, axis=1), 1, rtol=1e-4, atol=1e-5),
        "All 3104 finite unit raw float32 embeddings required")
    result = []
    for label in vocabulary:
        means = [features[[i for i, r in enumerate(rows) if r["label"] == label and r["session"] == session]]
                 .astype(np.float64).mean(0) for session in (1, 2)]
        mean = (means[0] + means[1]) / 2
        norm = np.linalg.norm(mean)
        require(np.isfinite(mean).all() and np.isfinite(norm) and norm > 0, "Degenerate training centroid")
        result.append(mean / norm)
    return np.stack(result)


def validate_checkpoint(checkpoint, receipt):
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(crossfit.SEED)
        model = PersonalVisualEncoder(97)
    expected = {"version": crossfit.VERSION, "arm": "fitA", "finalEpoch": 30, "sourceSHA256": SOURCE_SHA256,
        "protocolSHA256": crossfit.PROTOCOL_SHA256, "initialStateSHA256": _state_digest(model.state_dict()),
        "fitWriters": receipt["folds"]["A"], "exportWriters": receipt["folds"]["B"], "vocabulary": receipt["vocabulary"]}
    require(isinstance(checkpoint, dict) and set(checkpoint) == set(expected) | {"state_dict"}
        and all(checkpoint[k] == v for k, v in expected.items())
        and expected["initialStateSHA256"] == receipt["initialStateSHA256"], "Pinned fitA checkpoint metadata changed")
    schema, state = model.state_dict(), checkpoint["state_dict"]
    require(isinstance(state, dict) and set(state) == set(schema)
        and all(isinstance(state[k], torch.Tensor) and state[k].device.type == "cpu"
            and state[k].shape == schema[k].shape and state[k].dtype == schema[k].dtype
            and bool(torch.isfinite(state[k]).all()) for k in schema)
        and _state_digest(state) == receipt["finalStateSHA256"]["fitA"], "Pinned fitA checkpoint state changed")
    model.load_state_dict(state, strict=True)
    return model.cpu().eval().requires_grad_(False)


def load_parents(directory, manifest):
    directory = Path(directory)
    binding = core.input_identity(directory)  # Hash only; never open pooled feature arrays.
    require(binding["fit-receipt.json"] == core.RECEIPT_SHA256 and binding["features.npz"] == core.FEATURES_SHA256
        and binding["weights/fitA.pt"] == WEIGHTS_SHA256, "Frozen crossfit parent changed")
    receipt = json.loads(_regular_file(directory / "fit-receipt.json", "parent receipt").read_bytes())
    metadata = json.loads(_regular_file(directory / "metadata.json", "source metadata").read_bytes())
    plan = json.loads(_regular_file(directory / "fit-plan.json", "parent plan").read_bytes())
    payload = _regular_file(Path(manifest), "role manifest").read_bytes()
    roles = json.loads(payload)
    require(sha(payload) == MANIFEST_SHA256 and payload == canonical(roles)
        and sha(canonical(receipt)) == binding["fit-receipt.json"]
        and sha(canonical(metadata)) == binding["metadata.json"] == receipt["metadataSHA256"]
        and sha(canonical(plan)) == binding["fit-plan.json"] == receipt["fitPlanSHA256"]
        and all(receipt[k] == v for k, v in plan.items()) and receipt["codeSHA256"] == crossfit.code_identity()
        and binding["protocol.md"] == receipt["protocolSHA256"] == crossfit.PROTOCOL_SHA256
        and receipt["sourceSHA256"] == SOURCE_SHA256 and receipt["featuresSHA256"] == binding["features.npz"]
        and receipt["weightsSHA256"] == {arm: binding[f"weights/{arm}.pt"] for arm in crossfit.ARMS}
        and metadata["version"] == crossfit.VERSION and metadata["vocabulary"] == receipt["vocabulary"],
        "Parent receipt/code/source roles changed")
    validate_role_manifest(receipt, metadata["rows"], roles)
    rows = [r for r in metadata["rows"] if r["writer"] in roles["encoderFitWriters"]]
    validate_rows(rows, roles["encoderFitWriters"], receipt["vocabulary"], "fitB")
    return receipt, roles, rows, binding


def _npz(**arrays):
    buffer = io.BytesIO()
    np.savez(buffer, **arrays)
    return buffer.getvalue()


def prepare(source, crossfit_directory, manifest, output):
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists() and not output.is_relative_to(root), "Fresh centroid output outside Git required")
    code = code_identity()
    parent, roles, reference, binding = load_parents(crossfit_directory, manifest)
    source = _regular_file(Path(source), "public raw source")
    payload = source.read_bytes()
    require(sha(payload) == SOURCE_SHA256, "Pinned raw source changed")
    samples = select_training_source(payload.decode("utf-8"), roles["encoderFitWriters"], parent["vocabulary"])
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    runtime = {"python": platform.python_version(), "torch": str(torch.__version__), "numpy": str(np.__version__),
        "platform": platform.platform(), "cpuThreads": torch.get_num_threads(), "deterministicAlgorithms": True}
    require(runtime == parent["runtime"], "Frozen encoder runtime changed")
    checkpoint_bytes = _regular_file(Path(crossfit_directory) / "weights/fitA.pt", "fitA checkpoint").read_bytes()
    require(sha(checkpoint_bytes) == WEIGHTS_SHA256, "fitA changed before load")
    model = validate_checkpoint(torch.load(io.BytesIO(checkpoint_bytes), weights_only=True, map_location="cpu"), parent)
    state_before = _state_digest(model.state_dict())
    images, raster_hashes = encode_samples(samples, tuple(roles["encoderFitWriters"]))
    rows = match_source_rows(samples, raster_hashes, reference, roles["encoderFitWriters"], parent["vocabulary"])
    require(sum(r["storedFailure"] is not None for r in reference) == 12, "Stored-unavailable A16 source coverage changed")
    features, _ = infer(model, images)
    centroids = session_balanced_centroids(features, rows, roles["encoderFitWriters"], parent["vocabulary"])
    require(_state_digest(model.state_dict()) == state_before == parent["finalStateSHA256"]["fitA"]
        and code_identity() == code and core.input_identity(crossfit_directory) == binding
        and sha(source.read_bytes()) == SOURCE_SHA256 and sha(Path(manifest).read_bytes()) == MANIFEST_SHA256,
        "Centroid preparation input/code/state changed")
    data, retained, row_data = _npz(centroids=centroids), _npz(features=features), canonical({"vocabulary": parent["vocabulary"], "rows": rows})
    receipt = {"version": VERSION, "vocabulary": parent["vocabulary"], "parentBinding": binding,
        "roleManifestSHA256": MANIFEST_SHA256, "generator": "fitA", "generatorWeightsSHA256": WEIGHTS_SHA256,
        "generatorStateSHA256": state_before, "encoderFitWriters": roles["encoderFitWriters"], "sourceCount": 3104,
        "countPerLabel": 32, "dataSHA256": sha(data), "trainingFeaturesSHA256": sha(retained),
        "trainingRowsSHA256": sha(row_data), "codeSHA256": code, "runtime": runtime, "sourceSHA256": SOURCE_SHA256,
        "inSampleTrainingCentroids": True, "privateInkUsed": False, "developmentOrReservedInferred": False,
        "productionEligible": False, "sourceAndEncoderUnchanged": True, "storedUnavailableRawRowsRetained": 12}
    output = _new_output(output)
    for name, content in (("centroids.npz", data), ("training-features.npz", retained), ("training-rows.json", row_data),
                          ("centroid-receipt.json", canonical(receipt))):
        _write_exclusive(output / name, content)
    return receipt


def load_frozen_centroids(directory, parent, roles, vocabulary, *, receipt_sha256):
    """Require caller-pinned receipt bytes; reconstruct means from retained outputs."""
    directory = Path(directory)
    payload = _regular_file(directory / "centroid-receipt.json", "centroid receipt").read_bytes()
    receipt = json.loads(payload)
    require(isinstance(receipt_sha256, str) and _HASH.fullmatch(receipt_sha256)
        and sha(payload) == receipt_sha256 and payload == canonical(receipt), "Centroid receipt pin changed")
    expected = {"version": VERSION, "vocabulary": list(vocabulary), "parentBinding": parent,
        "roleManifestSHA256": sha(canonical(roles)), "generator": "fitA", "generatorWeightsSHA256": WEIGHTS_SHA256,
        "generatorStateSHA256": STATE_SHA256,
        "encoderFitWriters": roles["encoderFitWriters"], "sourceCount": 3104, "countPerLabel": 32,
        "codeSHA256": code_identity(), "sourceSHA256": SOURCE_SHA256, "inSampleTrainingCentroids": True,
        "privateInkUsed": False, "developmentOrReservedInferred": False, "productionEligible": False,
        "sourceAndEncoderUnchanged": True, "storedUnavailableRawRowsRetained": 12}
    require(all(receipt.get(k) == v for k, v in expected.items()) and expected["roleManifestSHA256"] == MANIFEST_SHA256
        and roles["generator"] == "fitA" and roles["generatorWeightsSHA256"] == WEIGHTS_SHA256
        and parent["fit-receipt.json"] == core.RECEIPT_SHA256 and parent["weights/fitA.pt"] == WEIGHTS_SHA256,
        "Centroid parent/code/roles changed")
    runtime = receipt["runtime"]
    require(runtime["python"] == platform.python_version() and runtime["torch"] == str(torch.__version__)
        and runtime["numpy"] == str(np.__version__) and runtime["cpuThreads"] == 4
        and runtime["deterministicAlgorithms"] is True, "Centroid runtime changed")
    blobs = {}
    for name, key in (("centroids.npz", "dataSHA256"), ("training-features.npz", "trainingFeaturesSHA256"), ("training-rows.json", "trainingRowsSHA256")):
        blobs[name] = _regular_file(directory / name, "centroid data").read_bytes()
        require(sha(blobs[name]) == receipt[key], "Centroid data changed")
    rows = json.loads(blobs["training-rows.json"])
    require(blobs["training-rows.json"] == canonical(rows) and set(rows) == {"vocabulary", "rows"}
        and rows["vocabulary"] == list(vocabulary) and all(set(r) == ROW_KEYS
            and all(isinstance(r[k], str) and _HASH.fullmatch(r[k]) for k in ("rawRasterSHA256", "trajectorySHA256"))
            for r in rows["rows"]), "Centroid source rows changed")
    arrays = []
    for name, key in (("centroids.npz", "centroids"), ("training-features.npz", "features")):
        with np.load(io.BytesIO(blobs[name]), allow_pickle=False) as bundle:
            require(bundle.files == [key], "Centroid array keys changed")
            arrays.append(bundle[key].copy())
    centroids, features = arrays
    rebuilt = session_balanced_centroids(features, rows["rows"], roles["encoderFitWriters"], vocabulary)
    require(centroids.dtype == np.float64 and centroids.shape == (97, 128) and np.array_equal(centroids, rebuilt),
        "Centroids differ from retained session-balanced embeddings")
    return torch.from_numpy(centroids), receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "crossfit", "manifest", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    result = prepare(args.source, args.crossfit, args.manifest, args.output)
    print(json.dumps({"version": result["version"], "sourceCount": result["sourceCount"], "dataSHA256": result["dataSHA256"]}))

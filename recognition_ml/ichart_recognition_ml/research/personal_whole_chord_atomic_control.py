"""Research-only raw-greedy oracle-owner control; never a live chord route.

Only source-only oracle projections enter this module. Expected chord labels,
writer identities and source-label IDs are not accepted. Full unrestricted
97-way logits are retained before strict canonical parsing. This is not a port
of Swift's canonical-probability search, a trust decision or personalization.
Core ML imports/loading occur only in the explicit pinned-runtime loader.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
from dataclasses import fields, is_dataclass
from pathlib import Path
from typing import Callable, Sequence

from ..chord_notation import CanonicalChordLabelError, require_canonical_chord_label
from ..features import FeatureEncodingError, InkBounds, InkPoint, InkStroke, RASTER_HEIGHT, RASTER_WIDTH, rasterize


VERSION = "personal-whole-chord-atomic-control-v1"
RECEIPT_VERSION = "personal-whole-chord-atomic-prediction-receipt-v1"
SCOPE = "synthetic-public-whole-chord-raw-greedy-oracle-control-research-only"
PINNED_MANIFEST_SHA256 = "d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1"
PINNED_PACKAGE_SHA256 = "c51029092ea80e6d2621db4606f7051139177169dc9d036b89c9e74b2f5988f5"
PINNED_WEIGHTS_SHA256 = "5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0"
LABEL_COUNT = 97
DEVELOPMENT_WRITER_COUNT = 8
DEVELOPMENT_EXAMPLE_COUNT = 5376


def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _digest(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _strict_json(payload: bytes) -> dict:
    def unique(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("Duplicate JSON key")
            result[key] = value
        return result

    def nonfinite(_):
        raise ValueError("Nonfinite JSON constant")

    value = json.loads(payload.decode("utf-8"), object_pairs_hook=unique, parse_constant=nonfinite)
    if not isinstance(value, dict):
        raise ValueError("Expected JSON object")
    return value


def _regular_file(path: Path) -> Path:
    path = Path(path)
    if not path.is_absolute() or path.is_symlink() or path.resolve() != path or not path.is_file():
        raise ValueError("Expected unaliased absolute regular file")
    return path


def package_digest(root: Path) -> str:
    """Same relative-path/file-SHA framing as the unchanged research exporter."""
    root = Path(root)
    if not root.is_absolute() or root.is_symlink() or root.resolve() != root or not root.is_dir():
        raise ValueError("Expected unaliased absolute model package")
    digest = hashlib.sha256()
    files = []
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError("Model package cannot contain symlinks")
        if path.is_file():
            files.append(path)
    if not files:
        raise ValueError("Empty model package")
    for path in sorted(files):
        digest.update(path.relative_to(root).as_posix().encode() + b"\0")
        digest.update(sha256(path.read_bytes()).encode() + b"\n")
    return digest.hexdigest()


def validate_vocabulary(vocabulary: Sequence[str]) -> tuple[str, ...]:
    result = tuple(vocabulary)
    if (len(result) != LABEL_COUNT or len(set(result)) != LABEL_COUNT
            or any(not isinstance(token, str) or len(token) != 1 for token in result)):
        raise ValueError("Expected full unique 97-character vocabulary")
    return result


def validate_runtime_spec(spec) -> None:
    """Inspect shape/type and creator metadata; usable with a synthetic spec."""
    metadata = dict(spec.description.metadata.userDefined)
    if (metadata.get("ichart.scope") != "personal-development-comparison-only"
            or metadata.get("ichart.weights.sha256") != PINNED_WEIGHTS_SHA256):
        raise ValueError("Core ML metadata weight/scope binding changed")
    inputs = list(spec.description.input)
    outputs = {item.name: item for item in spec.description.output}
    expected = {"personalEmbedding": (1, 128), "genericLogits": (1, LABEL_COUNT)}
    if (len(inputs) != 1 or inputs[0].name != "inkRaster"
            or tuple(inputs[0].type.multiArrayType.shape) != (1, 1, RASTER_HEIGHT, RASTER_WIDTH)
            or inputs[0].type.multiArrayType.dataType != 65568
            or len(spec.description.output) != 2 or set(outputs) != set(expected)
            or any(tuple(outputs[name].type.multiArrayType.shape) != shape
                   or outputs[name].type.multiArrayType.dataType != 65568
                   for name, shape in expected.items())):
        raise ValueError("Core ML input/output Float32 shape contract changed")


def validate_pinned_artifacts(manifest_path: Path, package_path: Path) -> dict:
    """Read-only byte bindings, no Core ML import, load or prediction."""
    manifest_path = _regular_file(manifest_path)
    payload = manifest_path.read_bytes()
    if sha256(payload) != PINNED_MANIFEST_SHA256:
        raise ValueError("Pinned manifest bytes changed")
    manifest = _strict_json(payload)
    vocabulary = validate_vocabulary(manifest.get("vocabulary", ()))
    if (manifest.get("researchOnly") is not True
            or manifest.get("featureCount") != 128
            or manifest.get("packageSHA256") != PINNED_PACKAGE_SHA256
            or manifest.get("weightsSHA256") != PINNED_WEIGHTS_SHA256
            or package_digest(package_path) != PINNED_PACKAGE_SHA256):
        raise ValueError("Pinned package/weight contract changed")
    return {"manifestSHA256": PINNED_MANIFEST_SHA256,
            "packageSHA256": PINNED_PACKAGE_SHA256,
            "weightsMetadataSHA256": PINNED_WEIGHTS_SHA256,
            "vocabulary": list(vocabulary), "vocabularySHA256": sha256(canonical_bytes(list(vocabulary)))}


class PinnedCoreMLPredictor:
    """Explicit CPU-only adapter, callable with unchanged uint8 raster bytes."""

    def __init__(self, manifest_path: Path, package_path: Path):
        self.manifest_path = _regular_file(manifest_path)
        self.package_path = Path(package_path)
        self.artifact_receipt = validate_pinned_artifacts(self.manifest_path, self.package_path)
        # Deliberately lazy: importing this module and synthetic tests never
        # loads the pinned runtime or a real-source model input.
        import coremltools as ct
        import numpy as np

        self._np = np
        self._model = ct.models.MLModel(str(self.package_path), compute_units=ct.ComputeUnit.CPU_ONLY)
        validate_runtime_spec(self._model.get_spec())
        self.vocabulary = tuple(self.artifact_receipt["vocabulary"])
        self.runtime_receipt = {"computeUnits": "CPU_ONLY", "coremltoolsVersion": ct.__version__,
                                "numpyVersion": np.__version__, "pythonVersion": platform.python_version(),
                                "platform": platform.platform(), "modelExported": False,
                                "torchWeightsReconstructed": False}
        self.assert_unchanged()

    def assert_unchanged(self) -> None:
        if validate_pinned_artifacts(self.manifest_path, self.package_path) != self.artifact_receipt:
            raise ValueError("Pinned runtime changed during control execution")

    def __call__(self, pixels: bytes) -> tuple[float, ...]:
        if not isinstance(pixels, bytes) or len(pixels) != RASTER_HEIGHT * RASTER_WIDTH:
            raise ValueError("Invalid unchanged raster input bytes")
        np = self._np
        image = np.frombuffer(pixels, dtype=np.uint8).astype(np.float32).reshape(1, 1, RASTER_HEIGHT, RASTER_WIDTH) / 255
        output = self._model.predict({"inkRaster": image})
        logits = np.asarray(output.get("genericLogits"))
        if logits.shape != (1, LABEL_COUNT) or not np.isfinite(logits).all():
            raise ValueError("Core ML full-logit output contract changed")
        return tuple(float(value) for value in logits[0])


def _logits(value: Sequence[float]) -> tuple[float, ...]:
    try:
        values = tuple(value)
    except TypeError as exc:
        raise ValueError("Malformed model logits") from exc
    if (len(values) != LABEL_COUNT or any(isinstance(v, bool) or not isinstance(v, (int, float))
            or not math.isfinite(v) for v in values)):
        raise ValueError("Expected exactly 97 finite unrestricted raw logits")
    return tuple(float(v) for v in values)


def _strokes_value(strokes: Sequence[InkStroke]) -> list[dict]:
    result = []
    for stroke in strokes:
        if not isinstance(stroke, InkStroke) or stroke.bounds is None:
            raise ValueError("Expected complete source InkStroke objects")
        if stroke.creation_time_offset is not None or any(p.time_offset is not None for p in stroke.points):
            raise ValueError("Synthetic source timing must remain unavailable")
        result.append({"bounds": {"maxX": float(stroke.bounds.max_x), "maxY": float(stroke.bounds.max_y),
            "minX": float(stroke.bounds.min_x), "minY": float(stroke.bounds.min_y)}, "creationTimeOffset": None,
            "points": [{"timeOffset": None, "x": float(p.x), "y": float(p.y)} for p in stroke.points]})
    return result


def source_owner_projection(inputs: Sequence[object]) -> list[dict]:
    """Serialize the source module's four-field WholeChordAtomicOwnerInput.

    No source plan or truth-bearing example is accepted. The source adapter is
    intentionally structural, so importing this control does not import the
    source builder's historical Torch geometry dependencies.
    """
    result = []
    expected = {"sample_id", "input_sha256", "strokes", "oracle_owner_groups"}
    for item in inputs:
        if not is_dataclass(item) or isinstance(item, type) or {f.name for f in fields(item)} != expected:
            raise ValueError("Expected source-only WholeChordAtomicOwnerInput projection")
        result.append({"sampleID": item.sample_id, "inputSHA256": item.input_sha256,
            "strokes": _strokes_value(item.strokes), "oracleOwners": [list(g) for g in item.oracle_owner_groups]})
    for row in result:
        _source_only_row(row)
    return result


def _source_only_row(row: dict) -> tuple[tuple[InkStroke, ...], tuple[tuple[int, ...], ...]]:
    if (not isinstance(row, dict) or set(row) != {"sampleID", "inputSHA256", "strokes", "oracleOwners"}
            or not _digest(row["sampleID"]) or not _digest(row["inputSHA256"])):
        raise ValueError("Expected source-only opaque oracle row; truth/writer fields forbidden")
    raw_strokes = row["strokes"]
    if not isinstance(raw_strokes, list) or not raw_strokes:
        raise ValueError("Missing complete source strokes")
    strokes = []
    for raw_stroke in raw_strokes:
        if (not isinstance(raw_stroke, dict) or set(raw_stroke) != {"bounds", "creationTimeOffset", "points"}
                or raw_stroke["creationTimeOffset"] is not None or not isinstance(raw_stroke["points"], list)
                or not raw_stroke["points"]):
            raise ValueError("Empty source stroke")
        bounds = raw_stroke["bounds"]
        if (not isinstance(bounds, dict) or set(bounds) != {"maxX", "maxY", "minX", "minY"}
                or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in bounds.values())):
            raise ValueError("Source bounds require complete finite extents")
        points = []
        for point in raw_stroke["points"]:
            if (not isinstance(point, dict) or set(point) != {"x", "y", "timeOffset"}
                    or point["timeOffset"] is not None
                    or any(isinstance(point[k], bool) or not isinstance(point[k], (int, float))
                           or not math.isfinite(point[k]) for k in ("x", "y"))):
                raise ValueError("Source points require only finite x/y, never invented timing")
            points.append(InkPoint(point["x"], point["y"]))
        strokes.append(InkStroke(points, InkBounds(bounds["minX"], bounds["minY"], bounds["maxX"], bounds["maxY"])))
    if sha256(canonical_bytes(row["strokes"])) != row["inputSHA256"]:
        raise ValueError("Whole-stroke source hash changed")
    owners = row["oracleOwners"]
    if not isinstance(owners, list) or not owners:
        raise ValueError("Missing complete oracle owner groups")
    converted = []
    for owner in owners:
        if (not isinstance(owner, list) or not owner or any(type(i) is not int for i in owner)
                or owner != sorted(set(owner))):
            raise ValueError("Oracle owner must retain ordered unique original indexes")
        converted.append(tuple(owner))
    flattened = [i for owner in converted for i in owner]
    if sorted(flattened) != list(range(len(strokes))):
        raise ValueError("Oracle coverage missing, overlapping or out of range")
    return tuple(strokes), tuple(converted)


def freeze_oracle_control(rows: Sequence[object], vocabulary: Sequence[str],
                          predict_pixels: Callable[[bytes], Sequence[float]], *,
                          bindings: dict[str, str], cache_by_raster: bool = True) -> dict:
    """Freeze every owner/output without any intended-label or scoring input.

    Owners must already be in spatial order, irrespective of whole-input stroke
    acquisition order. The supplied original indexes remain attached to every
    owner even when its exact raster shares cached logits with another owner.
    Structural failures refuse the complete process. Per-owner encoding/model
    failures retain their complete membership and make the whole read null.
    """
    vocabulary = validate_vocabulary(vocabulary)
    if (not isinstance(bindings, dict) or not bindings or any(not isinstance(k, str) or not k
            or not _digest(v) for k, v in bindings.items())):
        raise ValueError("Missing hash-only protocol/source/role/runtime bindings")
    if any(part in key.lower() for key in bindings for part in ("intended", "writer", "label")):
        raise ValueError("Truth/writer binding names forbidden")
    if isinstance(predict_pixels, PinnedCoreMLPredictor):
        if vocabulary != predict_pixels.vocabulary:
            raise ValueError("Runtime vocabulary binding changed")
        if not {"protocolSHA256", "sourceSHA256", "roleBindingSHA256"} <= set(bindings):
            raise ValueError("Real runtime requires frozen protocol/source/role bindings")
        predict_pixels.assert_unchanged()
    rows = tuple(rows)
    if rows and all(is_dataclass(row) for row in rows):
        rows = tuple(source_owner_projection(rows))
    if not rows or any(not isinstance(row, dict) for row in rows):
        raise ValueError("Missing complete oracle cohort")
    ids = [row.get("sampleID") for row in rows]
    if any(not _digest(i) for i in ids) or len(set(ids)) != len(ids):
        raise ValueError("Oracle sample IDs must be unique opaque hashes")
    rows = tuple(sorted(rows, key=lambda row: row["sampleID"]))
    projection_bytes = canonical_bytes(list(rows))
    checked = [_source_only_row(row) for row in rows]
    cache: dict[str, tuple[bytes, tuple[float, ...]]] = {}
    frozen, owner_count, calls, failures = [], 0, 0, 0
    for row, (strokes, owners) in zip(rows, checked):
        outputs = []
        for ordinal, indexes in enumerate(owners):
            ink = [row["strokes"][index] for index in indexes]
            owner_input = {"sampleID": row["sampleID"], "ownerOrdinal": ordinal,
                           "sourceStrokeIndexes": list(indexes), "strokes": ink}
            owner_output = {"ownerOrdinal": ordinal, "sourceStrokeIndexes": list(indexes),
                "sourceStrokeCount": len(indexes), "sourcePointCount": sum(len(s["points"]) for s in ink),
                "ownerInputSHA256": sha256(canonical_bytes(owner_input)), "rasterSHA256": None,
                "rawLogits": None, "firstArgmaxIndex": None, "firstArgmaxToken": None,
                "cacheHit": False, "failure": None}
            try:
                pixels = rasterize(tuple(strokes[index] for index in indexes)).pixels
            except (ValueError, FeatureEncodingError):
                owner_output["failure"] = "owner-raster-encoding-failure"
            else:
                raster_hash = sha256(pixels)
                owner_output["rasterSHA256"] = raster_hash
                cached = cache.get(raster_hash) if cache_by_raster else None
                if cached is not None and cached[0] != pixels:
                    raise ValueError("Raster digest collision")
                try:
                    if cached is None:
                        calls += 1
                        logits = _logits(predict_pixels(pixels))
                        if cache_by_raster:
                            cache[raster_hash] = (pixels, logits)
                    else:
                        logits = cached[1]
                except Exception:
                    # Only the backend/output boundary is caught. Ownership,
                    # immutable input and digest-collision checks remain fatal.
                    owner_output["failure"] = "owner-model-output-or-inference-failure"
                else:
                    first = max(range(LABEL_COUNT), key=logits.__getitem__)
                    owner_output.update(rawLogits=list(logits), firstArgmaxIndex=first,
                                        firstArgmaxToken=vocabulary[first], cacheHit=cached is not None)
            if owner_output["failure"] is not None:
                failures += 1
            outputs.append(owner_output)
        raw = None if any(o["failure"] for o in outputs) else "".join(o["firstArgmaxToken"] for o in outputs)
        canonical = None
        if raw is not None:
            try:
                canonical = require_canonical_chord_label(raw)
            except CanonicalChordLabelError:
                pass
        frozen.append({"sampleID": row["sampleID"], "inputSHA256": row["inputSHA256"],
            "oracleProjectionRowSHA256": sha256(canonical_bytes(row)),
            "sourceStrokeCount": len(strokes), "sourcePointCount": sum(len(s.points) for s in strokes),
            "owners": outputs, "rawTokenString": raw, "canonicalChord": canonical,
            "inputFailure": raw is None,
            "parserOutcome": "canonical" if canonical is not None else "owner-failure" if raw is None else "invalid-raw-string"})
        owner_count += len(outputs)
    if canonical_bytes(list(rows)) != projection_bytes:
        raise ValueError("Source-only projection changed during inference")
    runtime = {"kind": "injected-synthetic-model", "realModelLoadedByControl": False}
    if isinstance(predict_pixels, PinnedCoreMLPredictor):
        predict_pixels.assert_unchanged()
        runtime = {"kind": "pinned-operational-CoreML", **predict_pixels.runtime_receipt,
                   **{k: v for k, v in predict_pixels.artifact_receipt.items() if k != "vocabulary"}}
    return {"version": VERSION, "scope": SCOPE, "productionEligible": False,
        "automaticOwnership": False, "swiftProbabilitySearch": False, "truthJoined": False,
        "personalizationTested": False, "trustOrAcceptanceApplied": False,
        "composition": "unrestricted-97-first-argmax-concatenation-strict-canonical-or-null",
        "bindings": dict(sorted(bindings.items())), "oracleProjectionSHA256": sha256(projection_bytes),
        "vocabulary": list(vocabulary), "vocabularySHA256": sha256(canonical_bytes(list(vocabulary))),
        "rowCount": len(frozen), "ownerCount": owner_count, "modelCallCount": calls,
        "cacheByExactRasterSHA256": cache_by_raster, "runtime": runtime,
        "inputDrops": 0, "ownerFailures": failures,
        "inputFailures": sum(row["inputFailure"] for row in frozen), "rows": frozen}


def write_frozen_output(path: Path, packet: dict) -> str:
    """Exclusive output, never overwrite a prediction freeze."""
    path = Path(path)
    if not path.is_absolute() or path.parent.resolve() != path.parent or not path.parent.is_dir():
        raise ValueError("Expected absolute unaliased existing output directory")
    payload = canonical_bytes(packet)
    with path.open("xb") as handle:
        handle.write(payload)
    return sha256(payload)


def predict(source_path: Path, protocol_path: Path, manifest_path: Path,
            package_path: Path, output_path: Path) -> None:
    """Separate append-only public-development process, never fit/export.

    The public source builder may parse its label-bearing construction inputs.
    Its exact-owner projection is the only object supplied to the control;
    neither canonical targets nor writer/source-label identities enter it.
    """
    # Lazy shared helpers retain the exact source/32-8-20/code/protocol gates
    # without imposing Torch on pure injected synthetic-control imports.
    from . import personal_whole_chord_factor as factor
    from . import personal_whole_chord_source as source

    source_path, protocol_path, source_bytes, protocol_bytes, code, snapshot, records, roles = factor._captured_inputs(source_path, protocol_path)
    manifest_path = _regular_file(manifest_path)
    artifact_receipt = validate_pinned_artifacts(manifest_path, package_path)
    manifest_bytes = manifest_path.read_bytes()
    snapshot[manifest_path] = sha256(manifest_bytes)
    plan = source.build_role_plan(records, "development")
    if (tuple(plan.writers) != tuple(roles[1]) or len(plan.writers) != DEVELOPMENT_WRITER_COUNT
            or len(plan.examples) != DEVELOPMENT_EXAMPLE_COUNT
            or len(roles[0]) != 32 or len(roles[2]) != 20 or set(plan.writers) & set(roles[2])):
        raise ValueError("Atomic control requires exact eight-writer/5376 development source plan")
    projected = source.atomic_owner_inputs(plan)
    if len(projected) != DEVELOPMENT_EXAMPLE_COUNT:
        raise ValueError("Incomplete atomic source projection")
    # Validate every source hash/owner before loading the actual runtime.
    projection = source_owner_projection(projected)
    role_hash = sha256(canonical_bytes({"training": list(roles[0]), "development": list(roles[1]), "reserved": list(roles[2])}))
    bindings = {"sourceSHA256": sha256(source_bytes), "protocolSHA256": sha256(protocol_bytes),
        "roleBindingSHA256": role_hash, "codeSnapshotSHA256": sha256(canonical_bytes(code)),
        "manifestSHA256": artifact_receipt["manifestSHA256"], "packageSHA256": artifact_receipt["packageSHA256"]}
    output_path = Path(output_path)
    if not output_path.is_absolute() or output_path.parent.resolve() != output_path.parent or output_path.exists():
        raise ValueError("Expected new absolute unaliased atomic output directory")
    factor._preserved(snapshot)
    runtime = PinnedCoreMLPredictor(manifest_path, package_path)
    if runtime.artifact_receipt != artifact_receipt:
        raise ValueError("Pinned runtime artifact changed before prediction")
    packet = freeze_oracle_control(projection, runtime.vocabulary, runtime, bindings=bindings)
    packet.update(codeSHA256=code, sourceSHA256=sha256(source_bytes), protocolSHA256=sha256(protocol_bytes),
        roleBindingSHA256=role_hash, sourcePlanVersion=plan.version, developmentWriterCount=DEVELOPMENT_WRITER_COUNT,
        trainingWriterCount=32, reservedWriterCount=20,
        roleGuards={"privateInkUsed": False, "reservedWritersComposed": False,
                    "reservedWritersEncoded": False, "automaticAcceptanceAuthorized": False,
                    "sourceTruthSuppliedToPredictor": False, "sourceWriterSuppliedToPredictor": False})
    runtime.assert_unchanged()
    factor._preserved(snapshot)
    output = factor._new_output_directory(output_path)
    factor._write_exclusive(output / "frozen-protocol.md", protocol_bytes)
    factor._write_exclusive(output / "code-snapshot.json", canonical_bytes(code))
    factor._write_exclusive(output / "model-manifest.json", manifest_bytes)
    prediction_sha = write_frozen_output(output / "predictions.json", packet)
    receipt = {"version": RECEIPT_VERSION, "scope": SCOPE, "productionEligible": False,
        "predictionsRelativePath": "predictions.json", "predictionsSHA256": prediction_sha,
        "predictionsByteCount": (output / "predictions.json").stat().st_size,
        "codeSHA256": code, "sourceSHA256": packet["sourceSHA256"], "protocolSHA256": packet["protocolSHA256"],
        "roleBindingSHA256": role_hash, "sourcePlanVersion": plan.version,
        "modelManifestPath": str(manifest_path), "modelPackagePath": str(package_path),
        "manifestSHA256": artifact_receipt["manifestSHA256"], "packageSHA256": artifact_receipt["packageSHA256"],
        "weightsMetadataSHA256": artifact_receipt["weightsMetadataSHA256"],
        "vocabularySHA256": artifact_receipt["vocabularySHA256"],
        "modelManifestRelativePath": "model-manifest.json",
        "oracleProjectionSHA256": packet["oracleProjectionSHA256"], "runtime": packet["runtime"],
        "rowCount": packet["rowCount"], "ownerCount": packet["ownerCount"],
        "modelCallCount": packet["modelCallCount"], "inputDrops": packet["inputDrops"],
        "inputFailures": packet["inputFailures"], "ownerFailures": packet["ownerFailures"],
        "inputsUnchanged": True, "roleGuards": packet["roleGuards"]}
    factor._preserved(snapshot)
    runtime.assert_unchanged()
    write_frozen_output(output / "prediction-receipt.json", receipt)
    print(f"ATOMIC_PREDICTION_FROZEN rows={packet['rowCount']} owners={packet['ownerCount']} inputFailures={packet['inputFailures']} productionEligible=False", flush=True)


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "protocol", "manifest", "package", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args(argv)
    predict(args.source, args.protocol, args.manifest, args.package, args.output)


if __name__ == "__main__":
    main()

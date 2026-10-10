"""Fixed whole-chord conditional-factor experiment (research only).

Fit and prediction are intentionally separate processes.  The fit uses only
the 32 public UJI fit writers selected by ``personal_whole_chord_source``.
Prediction uses only its eight already-observed development writers and writes
label-free rows.  The ten raw model heads are preserved; the additional
candidate list is explicitly conditional on the input already being valid,
rooted chord notation and is never an acceptance/no-read decision.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import math
import os
import platform
import random
import stat
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import torch
from torch.nn import functional as F

from ..contracts import canonical_json_bytes, strict_json_loads
from ..decode import decode_factor_logits
from ..errors import ContractError
from ..features import encode_feature_artifacts
from ..models.dual_view import DualViewChordModel, DualViewModelConfig
from ..models.output_contract import (
    HEAD_BY_NAME,
    OUTPUT_CONTRACT_VERSION,
    OUTPUT_HEADS,
    FactorLogits,
    factorize_canonical_label,
)
from ..schema import FEATURE_SCHEMA
from . import personal_whole_chord_source as whole_source
from .uji_personal import SOURCE_SHA256, parse_source, split_writers


FIT_VERSION = "personal-whole-chord-factor-fit-v1"
PREDICTION_VERSION = "personal-whole-chord-factor-predictions-v1"
PREDICTION_RECEIPT_VERSION = "personal-whole-chord-factor-prediction-receipt-v1"
SCOPE = "public-uji-valid-rooted-whole-chord-conditional-identity-research-not-production"
SEED = 29
EPOCHS = 30
BATCH_SIZE = 128
LEARNING_RATE = 0.001
WEIGHT_DECAY = 0.0001
CPU_THREADS = 4
TRAINING_WRITER_COUNT = 32
DEVELOPMENT_WRITER_COUNT = 8
RESERVED_WRITER_COUNT = 20
EXAMPLES_PER_WRITER = 14 * 12 * 2 * 2
TRAINING_EXAMPLE_COUNT = TRAINING_WRITER_COUNT * EXAMPLES_PER_WRITER
DEVELOPMENT_EXAMPLE_COUNT = DEVELOPMENT_WRITER_COUNT * EXAMPLES_PER_WRITER
CONDITIONAL_CANDIDATE_COUNT = 3
ROOTED_LOGIT = 0.0
NONROOTED_LOGIT = -1.0e30

TRAINED_HEADS = (
    "root_letter",
    "root_accidental",
    "quality",
    "extension",
    "alteration_logits",
    "slash_presence",
)
INACTIVE_HEADS = (
    "validity",
    "kind",
    "slash_bass_letter",
    "slash_bass_accidental",
)

MODULE_PATH = "recognition_ml/ichart_recognition_ml/research/personal_whole_chord_factor.py"
TEST_PATH = "recognition_ml/tests/test_personal_whole_chord_factor.py"
SOURCE_MODULE_PATH = "recognition_ml/ichart_recognition_ml/research/personal_whole_chord_source.py"
SOURCE_TEST_PATH = "recognition_ml/tests/test_personal_whole_chord_source.py"
ATOMIC_CONTROL_PATH = "recognition_ml/ichart_recognition_ml/research/personal_whole_chord_atomic_control.py"
ATOMIC_CONTROL_TEST_PATH = "recognition_ml/tests/test_personal_whole_chord_atomic_control.py"
SCORING_PATH = "recognition_ml/ichart_recognition_ml/research/personal_whole_chord_scoring.py"
SCORING_TEST_PATH = "recognition_ml/tests/test_personal_whole_chord_scoring.py"
PROTOCOL_PATH = "docs/personal-whole-chord-factor-protocol-2026-10-02.md"
CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/__init__.py",
    "recognition_ml/ichart_recognition_ml/chord_notation.py",
    "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/dataset.py",
    "recognition_ml/ichart_recognition_ml/decode.py",
    "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/models/dual_view.py",
    "recognition_ml/ichart_recognition_ml/models/__init__.py",
    "recognition_ml/ichart_recognition_ml/models/output_contract.py",
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity.py",
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity_experiment.py",
    "recognition_ml/ichart_recognition_ml/research/__init__.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    SOURCE_MODULE_PATH,
    SOURCE_TEST_PATH,
    ATOMIC_CONTROL_PATH,
    ATOMIC_CONTROL_TEST_PATH,
    SCORING_PATH,
    SCORING_TEST_PATH,
    MODULE_PATH,
    TEST_PATH,
)


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _is_sha256(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _require_exact_keys(value: object, expected: set[str], name: str) -> dict:
    if not isinstance(value, dict) or set(value) != expected:
        raise ValueError(f"{name} has missing or unknown fields")
    return value


def _require_regular_file(path: Path, *, name: str) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{name} path must be absolute and canonical")
    try:
        resolved = path.resolve(strict=True)
    except (FileNotFoundError, RuntimeError) as error:
        raise ValueError(f"{name} does not exist") from error
    if resolved != path or path.is_symlink() or not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f"{name} must be an unaliased regular file")
    return path


def _require_directory(path: Path, *, name: str) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{name} path must be absolute and canonical")
    try:
        resolved = path.resolve(strict=True)
    except (FileNotFoundError, RuntimeError) as error:
        raise ValueError(f"{name} does not exist") from error
    if resolved != path or path.is_symlink() or not stat.S_ISDIR(path.stat().st_mode):
        raise ValueError(f"{name} must be an unaliased directory")
    return path


def _new_output_directory(path: Path) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute() or ".." in path.parts or path.exists() or path.is_symlink():
        raise ValueError("output must be a new absolute canonical path")
    parent = _require_directory(path.parent, name="output parent")
    if parent != path.parent:
        raise ValueError("output parent aliases are forbidden")
    path.mkdir(mode=0o700)
    return path


def _write_exclusive(path: Path, payload: bytes) -> None:
    with path.open("xb") as handle:
        handle.write(payload)


def _read_canonical_json_bytes(payload: bytes, name: str) -> dict:
    try:
        decoded = payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"{name} is not UTF-8") from error
    value = strict_json_loads(decoded, name)
    if not isinstance(value, dict) or canonical_json_bytes(value) != payload:
        raise ValueError(f"{name} must be canonical JSON bytes")
    return value


def _code_snapshot() -> tuple[dict[str, str], dict[Path, str]]:
    root = _repo_root()
    identity: dict[str, str] = {}
    snapshot: dict[Path, str] = {}
    for relative in CODE_PATHS:
        path = _require_regular_file(root / relative, name=f"code dependency {relative}")
        digest = _sha256(path.read_bytes())
        identity[relative] = digest
        snapshot[path] = digest
    return identity, snapshot


def _preserved(snapshot: Mapping[Path, str]) -> None:
    for path, expected in snapshot.items():
        if _sha256(path.read_bytes()) != expected:
            raise ValueError(f"bound input changed during execution: {path}")


def _configure_runtime() -> None:
    os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
    torch.set_num_threads(CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    random.seed(SEED)
    np.random.seed(SEED)
    torch.manual_seed(SEED)


def _runtime_contract() -> dict[str, object]:
    return {
        "cpuThreads": CPU_THREADS,
        "deterministicAlgorithms": True,
        "numpy": str(np.__version__),
        "platform": platform.platform(),
        "python": platform.python_version(),
        "torch": str(torch.__version__),
    }


def _feature_contract() -> dict[str, object]:
    return {
        "augmentation": "none",
        "featureSchemaVersion": FEATURE_SCHEMA.version,
        "rasterEncoding": FEATURE_SCHEMA.raster_encoding,
        "rasterNormalization": "float32-divide-255",
        "rasterShape": [FEATURE_SCHEMA.raster_height, FEATURE_SCHEMA.raster_width, 1],
        "sourceGrouping": "one-complete-synthetic-whole-chord-input",
        "timing": "unchanged-source-adapter-output-no-invented-timing",
        "trajectoryEncoding": FEATURE_SCHEMA.trajectory_encoding,
        "trajectoryShape": list(FEATURE_SCHEMA.trajectory_shape),
    }


def _model_contract() -> dict[str, object]:
    config = DualViewModelConfig()
    return {
        "architectureContractVersion": config.architecture_contract_version,
        "architectureID": DualViewChordModel.model_architecture_id,
        "config": asdict(config),
        "inactiveHeads": list(INACTIVE_HEADS),
        "outputContractVersion": OUTPUT_CONTRACT_VERSION,
        "outputHeads": [
            {"independentBernoulli": head.is_independent_bernoulli,
             "labels": list(head.labels), "name": head.name}
            for head in OUTPUT_HEADS
        ],
        "trainedHeads": list(TRAINED_HEADS),
    }


def _optimization_contract() -> dict[str, object]:
    return {
        "batchSize": BATCH_SIZE,
        "epochs": EPOCHS,
        "headLoss": "equal-mean-of-six-active-head-losses",
        "optimizer": {"learningRate": LEARNING_RATE, "name": "AdamW", "weightDecay": WEIGHT_DECAY},
        "permutationSeed": SEED,
        "scheduler": {"etaMin": 0.0, "name": "CosineAnnealingLR", "tMax": EPOCHS},
        "seed": SEED,
        "selection": "final-epoch-only-no-development-selection",
    }


def _role_guards() -> dict[str, object]:
    return {
        "automaticAcceptanceAuthorized": False,
        "calibratedNoReadAvailable": False,
        "developmentFeaturesConstructedDuringFit": False,
        "privateInkUsed": False,
        "reservedWritersEncoded": False,
        "validityOrKindSupervised": False,
    }


def _load_records(source_bytes: bytes):
    if _sha256(source_bytes) != SOURCE_SHA256:
        raise ValueError("public source digest differs from the frozen UJI source")
    try:
        records = parse_source(source_bytes.decode("utf-8"))
    except UnicodeDecodeError as error:
        raise ValueError("public source is not UTF-8") from error
    training, development, reserved = split_writers(records)
    if (
        len(records) != 11_640
        or len(training) != TRAINING_WRITER_COUNT
        or len(development) != DEVELOPMENT_WRITER_COUNT
        or len(reserved) != RESERVED_WRITER_COUNT
        or len(set(training + development + reserved)) != 60
    ):
        raise ValueError("public source roles are incomplete or changed")
    return records, (training, development, reserved)


@dataclass(frozen=True)
class FeatureBatch:
    sample_ids: tuple[str, ...]
    input_hashes: tuple[str, ...]
    trajectory: torch.Tensor
    raster: torch.Tensor
    trajectory_hashes: tuple[str, ...]
    raster_hashes: tuple[str, ...]
    stream_sha256: str


@dataclass(frozen=True)
class PredictionEncoding:
    sample_ids: tuple[str, ...]
    input_hashes: tuple[str, ...]
    successful: FeatureBatch | None
    failures: Mapping[str, str]
    stream_sha256: str


def encode_inputs(inputs: Sequence[object]) -> FeatureBatch:
    """Encode already-authorized rows without consulting targets or writer IDs."""
    if not inputs:
        raise ValueError("cannot encode an empty source plan")
    sample_ids: list[str] = []
    input_hashes: list[str] = []
    trajectory_bytes: list[bytes] = []
    raster_bytes: list[bytes] = []
    ledger: list[dict[str, str]] = []
    for row in inputs:
        sample_id = getattr(row, "sample_id", None)
        strokes = getattr(row, "strokes", None)
        input_sha256 = getattr(row, "input_sha256", None)
        if not isinstance(sample_id, str) or not sample_id or strokes is None or not _is_sha256(input_sha256):
            raise ValueError("source input lacks opaque sample ID or strokes")
        if whole_source.canonical_strokes_sha256(strokes) != input_sha256:
            raise ValueError("source input SHA does not bind exact canonical strokes")
        trajectory, raster = encode_feature_artifacts(strokes)
        trajectory_payload = trajectory.to_bytes()
        raster_payload = raster.to_bytes()
        trajectory_digest = _sha256(trajectory_payload)
        raster_digest = _sha256(raster_payload)
        sample_ids.append(sample_id)
        input_hashes.append(input_sha256)
        trajectory_bytes.append(trajectory_payload)
        raster_bytes.append(raster_payload)
        ledger.append({"inputSHA256": input_sha256, "rasterSHA256": raster_digest, "sampleID": sample_id,
                       "trajectorySHA256": trajectory_digest})
    if len(set(sample_ids)) != len(sample_ids):
        raise ValueError("source plan contains duplicate opaque sample IDs")
    trajectories = np.frombuffer(b"".join(trajectory_bytes), dtype="<f4").copy().reshape(
        len(inputs), *FEATURE_SCHEMA.trajectory_shape
    )
    rasters = np.frombuffer(b"".join(raster_bytes), dtype=np.uint8).copy().reshape(
        len(inputs), FEATURE_SCHEMA.raster_height, FEATURE_SCHEMA.raster_width, 1
    )
    return FeatureBatch(
        sample_ids=tuple(sample_ids),
        input_hashes=tuple(input_hashes),
        trajectory=torch.from_numpy(trajectories),
        raster=torch.from_numpy(rasters),
        trajectory_hashes=tuple(row["trajectorySHA256"] for row in ledger),
        raster_hashes=tuple(row["rasterSHA256"] for row in ledger),
        stream_sha256=_sha256(canonical_json_bytes(ledger)),
    )


def encode_prediction_inputs(inputs: Sequence[object]) -> PredictionEncoding:
    """Retain per-row feature failures without shortening the denominator."""
    if not inputs:
        raise ValueError("prediction source plan is empty")
    sample_ids = tuple(getattr(row, "sample_id", None) for row in inputs)
    input_hashes = tuple(getattr(row, "input_sha256", None) for row in inputs)
    if (any(not isinstance(value, str) or not value for value in sample_ids)
            or len(set(sample_ids)) != len(sample_ids)
            or any(not _is_sha256(value) for value in input_hashes)):
        raise ValueError("prediction identities or input hashes are malformed")
    successes: list[FeatureBatch] = []
    failures: dict[str, str] = {}
    ledger: list[dict[str, object]] = []
    for row, sample_id, input_hash in zip(inputs, sample_ids, input_hashes):
        try:
            encoded = encode_inputs((row,))
        except (ContractError, ValueError, OverflowError) as error:
            failure = f"{type(error).__name__}:{error}"
            if not failure or len(failure) > 256:
                failure = f"{type(error).__name__}:{_sha256(str(error).encode('utf-8'))}"
            failures[sample_id] = failure
            ledger.append({"inputFailure": failure, "inputSHA256": input_hash,
                           "sampleID": sample_id})
            continue
        successes.append(encoded)
        ledger.append({"inputFailure": None, "inputSHA256": input_hash,
                       "rasterSHA256": encoded.raster_hashes[0], "sampleID": sample_id,
                       "trajectorySHA256": encoded.trajectory_hashes[0]})
    successful = None
    if successes:
        successful_ledger = [row for row in ledger if row["inputFailure"] is None]
        successful = FeatureBatch(
            sample_ids=tuple(value for batch in successes for value in batch.sample_ids),
            input_hashes=tuple(value for batch in successes for value in batch.input_hashes),
            trajectory=torch.cat(tuple(batch.trajectory for batch in successes), dim=0),
            raster=torch.cat(tuple(batch.raster for batch in successes), dim=0),
            trajectory_hashes=tuple(value for batch in successes for value in batch.trajectory_hashes),
            raster_hashes=tuple(value for batch in successes for value in batch.raster_hashes),
            stream_sha256=_sha256(canonical_json_bytes(successful_ledger)),
        )
    return PredictionEncoding(
        sample_ids=sample_ids, input_hashes=input_hashes, successful=successful,
        failures=failures, stream_sha256=_sha256(canonical_json_bytes(ledger)),
    )


def conditional_targets(labels: Sequence[str]) -> dict[str, torch.Tensor]:
    if not labels:
        raise ValueError("conditional training labels are empty")
    values: dict[str, list[object]] = {head: [] for head in TRAINED_HEADS}
    for label in labels:
        targets = factorize_canonical_label(label)
        if not all(targets.active[name] for name in TRAINED_HEADS):
            raise ValueError("covered label lacks required conditional supervision")
        if targets.active["slash_bass_letter"] or targets.active["slash_bass_accidental"]:
            raise ValueError("slash-bass labels are outside this fixed experiment")
        alterations = tuple(float(value) for value in targets.values["alteration_logits"])
        slash = int(targets.values["slash_presence"])
        if any(value != 0.0 for value in alterations) or slash != HEAD_BY_NAME["slash_presence"].labels.index("none"):
            raise ValueError("altered or slash chords are outside this fixed experiment")
        for name in TRAINED_HEADS:
            values[name].append(targets.values[name])
    result: dict[str, torch.Tensor] = {}
    for name in TRAINED_HEADS:
        if HEAD_BY_NAME[name].is_independent_bernoulli:
            result[name] = torch.tensor(values[name], dtype=torch.float32)
        else:
            result[name] = torch.tensor(values[name], dtype=torch.long)
    return result


def conditional_factor_loss(
    outputs: Mapping[str, torch.Tensor], targets: Mapping[str, torch.Tensor]
) -> tuple[torch.Tensor, dict[str, float]]:
    if set(outputs) != {head.name for head in OUTPUT_HEADS} or set(targets) != set(TRAINED_HEADS):
        raise ValueError("factor output or target head set differs from the frozen contract")
    count = next(iter(outputs.values())).shape[0]
    components: list[torch.Tensor] = []
    report: dict[str, float] = {}
    for head in OUTPUT_HEADS:
        logits = outputs[head.name]
        if logits.ndim != 2 or tuple(logits.shape) != (count, len(head.labels)) or not torch.isfinite(logits).all():
            raise ValueError(f"malformed or nonfinite logits for {head.name}")
        if head.name not in TRAINED_HEADS:
            continue
        target = targets[head.name].to(logits.device)
        if head.is_independent_bernoulli:
            if tuple(target.shape) != tuple(logits.shape):
                raise ValueError(f"target shape differs for {head.name}")
            component = F.binary_cross_entropy_with_logits(logits, target)
        else:
            if tuple(target.shape) != (count,):
                raise ValueError(f"target shape differs for {head.name}")
            component = F.cross_entropy(logits, target)
        components.append(component)
        report[head.name] = float(component.detach())
    loss = torch.stack(components).mean()
    if not torch.isfinite(loss):
        raise ValueError("conditional factor loss is nonfinite")
    return loss, report


def _state_digest(state: Mapping[str, torch.Tensor]) -> str:
    digest = hashlib.sha256()
    for key in sorted(state):
        tensor = state[key].detach().cpu().contiguous()
        descriptor = canonical_json_bytes({"dtype": str(tensor.dtype), "key": key, "shape": list(tensor.shape)})
        raw = tensor.numpy().tobytes(order="C")
        digest.update(len(descriptor).to_bytes(8, "big")); digest.update(descriptor)
        digest.update(len(raw).to_bytes(8, "big")); digest.update(raw)
    return digest.hexdigest()


def _tensor_digests(state: Mapping[str, torch.Tensor]) -> dict[str, str]:
    result = {}
    for key in sorted(state):
        tensor = state[key].detach().cpu().contiguous()
        descriptor = canonical_json_bytes({"dtype": str(tensor.dtype), "shape": list(tensor.shape)})
        result[key] = _sha256(descriptor + b"\0" + tensor.numpy().tobytes(order="C"))
    return result


def _head_state_digest(state: Mapping[str, torch.Tensor], heads: Sequence[str]) -> str:
    prefixes = tuple(f"heads.{name}." for name in heads)
    selected = {key: value for key, value in state.items() if key.startswith(prefixes)}
    if not selected or any(not any(key.startswith(prefix) for key in selected) for prefix in prefixes):
        raise ValueError("checkpoint lacks an expected head state")
    return _state_digest(selected)


def initialized_model() -> tuple[DualViewChordModel, dict[str, str]]:
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(SEED)
        model = DualViewChordModel(DualViewModelConfig())
    state = model.state_dict()
    return model, {"inactiveHeadSHA256": _head_state_digest(state, INACTIVE_HEADS),
                   "stateSHA256": _state_digest(state), "tensorSHA256": _tensor_digests(state)}


def train_model(model: DualViewChordModel, batch: FeatureBatch,
                targets: Mapping[str, torch.Tensor], history_sink=None) -> list[dict[str, object]]:
    count = len(batch.sample_ids)
    if count != TRAINING_EXAMPLE_COUNT or any(len(value) != count for value in targets.values()):
        raise ValueError("training cohort is not the complete fixed 32-writer plan")
    generator = torch.Generator(device="cpu").manual_seed(SEED)
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS, eta_min=0.0)
    history: list[dict[str, object]] = []
    model.train()
    for epoch in range(1, EPOCHS + 1):
        permutation = torch.randperm(count, generator=generator)
        permutation_bytes = permutation.numpy().astype("<i8", copy=False).tobytes()
        total_loss = 0.0
        component_totals = {name: 0.0 for name in TRAINED_HEADS}
        steps = 0
        for indexes in permutation.split(BATCH_SIZE):
            outputs = model(batch.trajectory[indexes].float(), batch.raster[indexes].float() / 255.0)
            selected = {name: value[indexes] for name, value in targets.items()}
            loss, components = conditional_factor_loss(outputs, selected)
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            if any(parameter.grad is not None and not torch.isfinite(parameter.grad).all() for parameter in model.parameters()):
                raise ValueError("training produced a nonfinite gradient")
            optimizer.step()
            total_loss += float(loss.detach()) * len(indexes)
            for name, value in components.items():
                component_totals[name] += value * len(indexes)
            steps += 1
        scheduler.step()
        row = {
            "activeHeadLosses": {name: component_totals[name] / count for name in TRAINED_HEADS},
            "epoch": epoch,
            "learningRateAfterEpoch": float(scheduler.get_last_lr()[0]),
            "permutationSHA256": _sha256(permutation_bytes),
            "steps": steps,
            "trainLoss": total_loss / count,
        }
        history.append(row)
        row_bytes = canonical_json_bytes(row)
        print(row_bytes.decode("utf-8"), flush=True)
        if history_sink is not None:
            history_sink.write(row_bytes + b"\n")
            history_sink.flush()
            os.fsync(history_sink.fileno())
    if any(not torch.isfinite(value).all() for value in model.state_dict().values() if value.is_floating_point()):
        raise ValueError("final checkpoint contains nonfinite tensors")
    return history


CHECKPOINT_FIELDS = {
    "architectureContractVersion", "codeSHA256", "featureSchemaVersion", "inactiveHeads",
    "modelConfig", "outputContractVersion", "protocolSHA256", "sourcePlanVersion",
    "sourceSHA256", "stateDict", "trainedHeads", "trainingTruthLedgerSHA256", "version",
}


def checkpoint_bytes(model: DualViewChordModel, *, code: Mapping[str, str], protocol_sha256: str,
                     source_plan_version: str, truth_sha256: str) -> bytes:
    buffer = io.BytesIO()
    torch.save({
        "architectureContractVersion": model.architecture_contract_version,
        "codeSHA256": dict(code),
        "featureSchemaVersion": FEATURE_SCHEMA.version,
        "inactiveHeads": list(INACTIVE_HEADS),
        "modelConfig": asdict(model.config),
        "outputContractVersion": OUTPUT_CONTRACT_VERSION,
        "protocolSHA256": protocol_sha256,
        "sourcePlanVersion": source_plan_version,
        "sourceSHA256": SOURCE_SHA256,
        "stateDict": model.state_dict(),
        "trainedHeads": list(TRAINED_HEADS),
        "trainingTruthLedgerSHA256": truth_sha256,
        "version": FIT_VERSION,
    }, buffer)
    return buffer.getvalue()


def load_checkpoint(payload: bytes, *, code: Mapping[str, str], protocol_sha256: str,
                    source_plan_version: str, truth_sha256: str) -> DualViewChordModel:
    value = _require_exact_keys(
        torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True), CHECKPOINT_FIELDS, "checkpoint"
    )
    expected = {
        "architectureContractVersion": DualViewModelConfig().architecture_contract_version,
        "codeSHA256": dict(code), "featureSchemaVersion": FEATURE_SCHEMA.version,
        "inactiveHeads": list(INACTIVE_HEADS), "modelConfig": asdict(DualViewModelConfig()),
        "outputContractVersion": OUTPUT_CONTRACT_VERSION, "protocolSHA256": protocol_sha256,
        "sourcePlanVersion": source_plan_version, "sourceSHA256": SOURCE_SHA256,
        "trainedHeads": list(TRAINED_HEADS), "trainingTruthLedgerSHA256": truth_sha256,
        "version": FIT_VERSION,
    }
    if any(value.get(key) != expected_value for key, expected_value in expected.items()):
        raise ValueError("checkpoint binding differs from the frozen experiment")
    if not isinstance(value["stateDict"], dict):
        raise ValueError("checkpoint state is malformed")
    model = DualViewChordModel(DualViewModelConfig())
    model.load_state_dict(value["stateDict"], strict=True)
    if any(not torch.isfinite(item).all() for item in model.state_dict().values() if item.is_floating_point()):
        raise ValueError("checkpoint contains nonfinite tensors")
    return model


def conditional_valid_rooted_logits(raw: Mapping[str, Sequence[float]]) -> FactorLogits:
    """Project only the decoder context; never overwrite retained raw heads."""
    validated = FactorLogits.from_mapping(raw)
    values = {name: tuple(items) for name, items in validated.values.items()}
    values["validity"] = tuple(0.0 for _ in HEAD_BY_NAME["validity"].labels)
    kind = [NONROOTED_LOGIT for _ in HEAD_BY_NAME["kind"].labels]
    kind[HEAD_BY_NAME["kind"].labels.index("rooted")] = ROOTED_LOGIT
    values["kind"] = tuple(kind)
    return FactorLogits.from_mapping(values)


def conditional_identity(logits: Mapping[str, Sequence[float]]) -> str | None:
    """Return the first rooted grammar hypothesis, never an acceptance result."""
    decoded = decode_factor_logits(
        conditional_valid_rooted_logits(logits),
        maximum_candidate_count=CONDITIONAL_CANDIDATE_COUNT,
    )
    for candidate in decoded.candidates:
        if candidate.canonical_label != "•/•":
            return candidate.canonical_label
    return None


def infer(model: DualViewChordModel, batch: FeatureBatch) -> dict[str, np.ndarray]:
    if not batch.sample_ids:
        return {head.name: np.empty((0, len(head.labels)), dtype=np.float32) for head in OUTPUT_HEADS}
    model.eval()
    pieces = {head.name: [] for head in OUTPUT_HEADS}
    with torch.inference_mode():
        for start in range(0, len(batch.sample_ids), BATCH_SIZE):
            selected = slice(start, start + BATCH_SIZE)
            outputs = model(batch.trajectory[selected].float(), batch.raster[selected].float() / 255.0)
            for head in OUTPUT_HEADS:
                pieces[head.name].append(outputs[head.name].detach().cpu().numpy())
    result = {name: np.concatenate(values, axis=0) for name, values in pieces.items()}
    count = len(batch.sample_ids)
    for head in OUTPUT_HEADS:
        if result[head.name].shape != (count, len(head.labels)) or not np.isfinite(result[head.name]).all():
            raise ValueError(f"prediction output malformed for {head.name}")
    return result


def prediction_rows(encoding: PredictionEncoding,
                    outputs: Mapping[str, np.ndarray]) -> list[dict[str, object]]:
    if set(outputs) != {head.name for head in OUTPUT_HEADS}:
        raise ValueError("prediction lacks the exact ten raw heads")
    batch = encoding.successful
    success_indexes = {} if batch is None else {
        sample_id: index for index, sample_id in enumerate(batch.sample_ids)
    }
    expected_count = len(success_indexes)
    for head in OUTPUT_HEADS:
        if outputs[head.name].shape != (expected_count, len(head.labels)):
            raise ValueError(f"prediction matrix has wrong shape for {head.name}")
    rows: list[dict[str, object]] = []
    for sample_id, input_sha in zip(encoding.sample_ids, encoding.input_hashes):
        failure = encoding.failures.get(sample_id)
        if failure is not None:
            rows.append({
                "conditionalCanonicalLabel": None,
                "conditionalValidRootedCandidates": None,
                "inputFailure": failure,
                "inputSHA256": input_sha,
                "logits": None,
                "rasterSHA256": None,
                "sampleID": sample_id,
                "trajectorySHA256": None,
            })
            continue
        if batch is None or sample_id not in success_indexes:
            raise ValueError("successful prediction input is absent from the encoded batch")
        index = success_indexes[sample_id]
        raw = {head.name: [float(value) for value in outputs[head.name][index]] for head in OUTPUT_HEADS}
        conditional = decode_factor_logits(
            conditional_valid_rooted_logits(raw), maximum_candidate_count=CONDITIONAL_CANDIDATE_COUNT
        )
        candidates = [
            {"canonicalLabel": item.canonical_label, "rawJointLogScore": item.raw_joint_log_score}
            for item in conditional.candidates if item.canonical_label != "•/•"
        ]
        if len(candidates) != CONDITIONAL_CANDIDATE_COUNT:
            raise ValueError("conditional rooted decoder did not retain three rooted candidates")
        identity = conditional_identity(raw)
        if identity != candidates[0]["canonicalLabel"]:
            raise ValueError("conditional identity and retained rank disagree")
        rows.append({
            "conditionalCanonicalLabel": identity,
            "conditionalValidRootedCandidates": candidates,
            "inputFailure": None,
            "inputSHA256": input_sha,
            "logits": raw,
            "rasterSHA256": batch.raster_hashes[index],
            "sampleID": sample_id,
            "trajectorySHA256": batch.trajectory_hashes[index],
        })
    rows.sort(key=lambda row: row["sampleID"])
    if len({row["sampleID"] for row in rows}) != len(rows):
        raise ValueError("prediction rows contain duplicate sample IDs")
    return rows


FIT_FIELDS = {
    "changedStateKeys", "checkpointRelativePath", "checkpointSHA256", "codeSHA256",
    "developmentWriterCount", "featureContract", "finalInactiveHeadSHA256",
    "finalStateSHA256", "finalTensorSHA256", "history",
    "initialInactiveHeadSHA256", "initialStateSHA256", "inputFeatureStreamSHA256",
    "initialTensorSHA256",
    "modelContract", "optimization", "protocolSHA256", "reservedWriterCount", "roleGuards", "runtime",
    "scope", "selection", "sourcePlanVersion", "sourceSHA256", "trainingExampleCount",
    "trainingHistoryByteCount", "trainingHistoryRelativePath", "trainingHistorySHA256",
    "trainingTruthLedgerByteCount", "trainingTruthLedgerRelativePath",
    "trainingTruthLedgerSHA256", "trainingWriterCount", "unchangedStateKeys", "version",
}


def validate_fit_receipt(receipt: object, *, code: Mapping[str, str], protocol_sha256: str) -> dict:
    receipt = _require_exact_keys(receipt, FIT_FIELDS, "fit receipt")
    fixed = {
        "checkpointRelativePath": "weights.pt", "codeSHA256": dict(code),
        "developmentWriterCount": DEVELOPMENT_WRITER_COUNT, "featureContract": _feature_contract(),
        "modelContract": _model_contract(), "optimization": _optimization_contract(),
        "protocolSHA256": protocol_sha256, "reservedWriterCount": RESERVED_WRITER_COUNT,
        "roleGuards": _role_guards(), "runtime": _runtime_contract(),
        "scope": SCOPE, "selection": "final-epoch-only",
        "sourceSHA256": SOURCE_SHA256, "trainingExampleCount": TRAINING_EXAMPLE_COUNT,
        "trainingHistoryRelativePath": "training-history.jsonl",
        "trainingTruthLedgerRelativePath": "training-source-truth.json",
        "trainingWriterCount": TRAINING_WRITER_COUNT, "version": FIT_VERSION,
    }
    if any(receipt.get(key) != value for key, value in fixed.items()):
        raise ValueError("fit receipt metadata differs from the frozen contract")
    for key in ("checkpointSHA256", "finalInactiveHeadSHA256", "finalStateSHA256",
                "initialInactiveHeadSHA256", "initialStateSHA256", "inputFeatureStreamSHA256",
                "trainingHistorySHA256", "trainingTruthLedgerSHA256"):
        if not _is_sha256(receipt.get(key)):
            raise ValueError(f"fit receipt {key} is not a SHA-256 digest")
    if not isinstance(receipt.get("sourcePlanVersion"), str) or not receipt["sourcePlanVersion"]:
        raise ValueError("fit source plan version is missing")
    history = receipt.get("history")
    if not isinstance(history, list) or len(history) != EPOCHS or [row.get("epoch") for row in history] != list(range(1, EPOCHS + 1)):
        raise ValueError("fit history is incomplete")
    generator = torch.Generator(device="cpu").manual_seed(SEED)
    expected_steps = math.ceil(TRAINING_EXAMPLE_COUNT / BATCH_SIZE)
    for epoch, row in enumerate(history, 1):
        if not isinstance(row, dict) or set(row) != {
            "activeHeadLosses", "epoch", "learningRateAfterEpoch",
            "permutationSHA256", "steps", "trainLoss",
        }:
            raise ValueError("fit history row contract changed")
        permutation = torch.randperm(TRAINING_EXAMPLE_COUNT, generator=generator)
        permutation_sha = _sha256(permutation.numpy().astype("<i8", copy=False).tobytes())
        expected_lr = LEARNING_RATE * (1.0 + math.cos(math.pi * epoch / EPOCHS)) / 2.0
        components = row["activeHeadLosses"]
        if (row["steps"] != expected_steps or row["permutationSHA256"] != permutation_sha
                or not isinstance(components, dict) or set(components) != set(TRAINED_HEADS)
                or any(not isinstance(value, (int, float)) or isinstance(value, bool)
                       or not math.isfinite(value) or value < 0 for value in components.values())
                or not isinstance(row["trainLoss"], (int, float)) or isinstance(row["trainLoss"], bool)
                or not math.isfinite(row["trainLoss"]) or row["trainLoss"] < 0
                or not isinstance(row["learningRateAfterEpoch"], (int, float))
                or not math.isclose(row["learningRateAfterEpoch"], expected_lr, rel_tol=0, abs_tol=1e-15)):
            raise ValueError("fit history arithmetic or permutation differs")
    _, expected_initial = initialized_model()
    if (receipt["initialStateSHA256"] != expected_initial["stateSHA256"]
            or receipt["initialInactiveHeadSHA256"] != expected_initial["inactiveHeadSHA256"]
            or receipt["initialTensorSHA256"] != expected_initial["tensorSHA256"]):
        raise ValueError("fit initial seed-29 tensors differ from the frozen model")
    initial_tensors, final_tensors = receipt["initialTensorSHA256"], receipt["finalTensorSHA256"]
    if (not isinstance(final_tensors, dict) or set(final_tensors) != set(initial_tensors)
            or any(not _is_sha256(value) for value in final_tensors.values())):
        raise ValueError("fit final tensor hashes are incomplete")
    changed = sorted(key for key in initial_tensors if initial_tensors[key] != final_tensors[key])
    unchanged = sorted(set(initial_tensors) - set(changed))
    if receipt["changedStateKeys"] != changed or receipt["unchangedStateKeys"] != unchanged or not changed:
        raise ValueError("fit changed-state receipt differs from tensor hashes")
    inactive_prefixes = tuple(f"heads.{name}." for name in INACTIVE_HEADS)
    if any(key in changed for key in initial_tensors if key.startswith(inactive_prefixes)):
        raise ValueError("an inactive output-head tensor changed")
    if receipt["initialInactiveHeadSHA256"] != receipt["finalInactiveHeadSHA256"]:
        raise ValueError("inactive head parameters changed despite absent supervision")
    if (not isinstance(receipt.get("trainingHistoryByteCount"), int)
            or receipt["trainingHistoryByteCount"] <= 0
            or not isinstance(receipt.get("trainingTruthLedgerByteCount"), int)
            or receipt["trainingTruthLedgerByteCount"] <= 0):
        raise ValueError("fit source/history byte counts are invalid")
    return receipt


def _captured_inputs(source_path: Path, protocol_path: Path):
    source_path = _require_regular_file(source_path, name="public source")
    protocol_path = _require_regular_file(protocol_path, name="frozen protocol")
    source_bytes, protocol_bytes = source_path.read_bytes(), protocol_path.read_bytes()
    code, code_snapshot = _code_snapshot()
    snapshot = {source_path: _sha256(source_bytes), protocol_path: _sha256(protocol_bytes), **code_snapshot}
    if _sha256(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("supplied protocol differs from the bound repository protocol")
    records, roles = _load_records(source_bytes)
    return source_path, protocol_path, source_bytes, protocol_bytes, code, snapshot, records, roles


def fit(source_path: Path, protocol_path: Path, output_path: Path) -> None:
    _configure_runtime()
    source_path, protocol_path, _, protocol_bytes, code, snapshot, records, roles = _captured_inputs(source_path, protocol_path)
    plan = whole_source.build_role_plan(records, "training")
    if len(plan.writers) != TRAINING_WRITER_COUNT or tuple(plan.writers) != tuple(roles[0]) or len(plan.examples) != TRAINING_EXAMPLE_COUNT:
        raise ValueError("training source plan is not the exact 32-writer cohort")
    source_plan_version = plan.version
    training_writer_count = len(plan.writers)
    training_example_count = len(plan.examples)
    truth_bytes = whole_source.truth_ledger_bytes(plan)
    truth_sha = _sha256(truth_bytes)
    truth_byte_count = len(truth_bytes)
    # Publish the complete deduplicated source plan before feature work or the
    # first optimizer step.  A later failure cannot silently shorten coverage.
    output = _new_output_directory(output_path)
    _write_exclusive(output / "frozen-protocol.md", protocol_bytes)
    _write_exclusive(output / "training-source-truth.json", truth_bytes)
    labels = tuple(example.canonical_label for example in plan.examples)
    batch = encode_inputs(whole_source.prediction_inputs(plan))
    targets = conditional_targets(labels)
    # Training needs only frozen feature/target tensors from here onward.
    # Release the much larger repeated source-plan objects before 30 epochs.
    del labels, plan, records, truth_bytes
    model, initial = initialized_model()
    _preserved(snapshot)
    history_path = output / "training-history.jsonl"
    with history_path.open("xb") as history_sink:
        history = train_model(model, batch, targets, history_sink=history_sink)
    history_bytes = history_path.read_bytes()
    final_state = _state_digest(model.state_dict())
    final_inactive = _head_state_digest(model.state_dict(), INACTIVE_HEADS)
    final_tensors = _tensor_digests(model.state_dict())
    changed_state_keys = sorted(
        key for key in initial["tensorSHA256"]
        if initial["tensorSHA256"][key] != final_tensors[key]
    )
    unchanged_state_keys = sorted(set(initial["tensorSHA256"]) - set(changed_state_keys))
    if final_inactive != initial["inactiveHeadSHA256"]:
        raise ValueError("inactive head parameters changed")
    protocol_sha = _sha256(protocol_bytes)
    checkpoint = checkpoint_bytes(model, code=code, protocol_sha256=protocol_sha,
                                  source_plan_version=source_plan_version, truth_sha256=truth_sha)
    restored = load_checkpoint(checkpoint, code=code, protocol_sha256=protocol_sha,
                               source_plan_version=source_plan_version, truth_sha256=truth_sha)
    if _state_digest(restored.state_dict()) != final_state:
        raise ValueError("serialized final checkpoint differs after reload")
    receipt = {
        "changedStateKeys": changed_state_keys, "checkpointRelativePath": "weights.pt",
        "checkpointSHA256": _sha256(checkpoint),
        "codeSHA256": code, "developmentWriterCount": DEVELOPMENT_WRITER_COUNT,
        "featureContract": _feature_contract(), "finalInactiveHeadSHA256": final_inactive,
        "finalStateSHA256": final_state, "finalTensorSHA256": final_tensors, "history": history,
        "initialInactiveHeadSHA256": initial["inactiveHeadSHA256"],
        "initialStateSHA256": initial["stateSHA256"], "initialTensorSHA256": initial["tensorSHA256"],
        "inputFeatureStreamSHA256": batch.stream_sha256,
        "modelContract": _model_contract(), "optimization": _optimization_contract(),
        "protocolSHA256": protocol_sha, "reservedWriterCount": RESERVED_WRITER_COUNT,
        "roleGuards": _role_guards(), "runtime": _runtime_contract(),
        "scope": SCOPE, "selection": "final-epoch-only",
        "sourcePlanVersion": source_plan_version, "sourceSHA256": SOURCE_SHA256,
        "trainingExampleCount": training_example_count, "trainingHistoryByteCount": len(history_bytes),
        "trainingHistoryRelativePath": "training-history.jsonl",
        "trainingHistorySHA256": _sha256(history_bytes),
        "trainingTruthLedgerByteCount": truth_byte_count,
        "trainingTruthLedgerRelativePath": "training-source-truth.json",
        "trainingTruthLedgerSHA256": truth_sha,
        "trainingWriterCount": training_writer_count, "unchangedStateKeys": unchanged_state_keys,
        "version": FIT_VERSION,
    }
    validate_fit_receipt(receipt, code=code, protocol_sha256=protocol_sha)
    _preserved(snapshot)
    _write_exclusive(output / "weights.pt", checkpoint)
    _write_exclusive(output / "fit-receipt.json", canonical_json_bytes(receipt))


def predict(source_path: Path, protocol_path: Path, fit_directory: Path, output_path: Path) -> None:
    _configure_runtime()
    _, _, _, protocol_bytes, code, snapshot, records, roles = _captured_inputs(source_path, protocol_path)
    fit_directory = _require_directory(fit_directory, name="fit directory")
    fit_receipt_path = _require_regular_file(fit_directory / "fit-receipt.json", name="fit receipt")
    checkpoint_path = _require_regular_file(fit_directory / "weights.pt", name="fit checkpoint")
    fit_protocol_path = _require_regular_file(fit_directory / "frozen-protocol.md", name="fit protocol")
    fit_history_path = _require_regular_file(fit_directory / "training-history.jsonl", name="fit history")
    fit_truth_path = _require_regular_file(fit_directory / "training-source-truth.json", name="fit source truth")
    fit_receipt_bytes, checkpoint_payload, fit_protocol_bytes, fit_history_bytes, fit_truth_bytes = (
        fit_receipt_path.read_bytes(), checkpoint_path.read_bytes(), fit_protocol_path.read_bytes(),
        fit_history_path.read_bytes(), fit_truth_path.read_bytes(),
    )
    snapshot.update({fit_receipt_path: _sha256(fit_receipt_bytes), checkpoint_path: _sha256(checkpoint_payload),
                     fit_protocol_path: _sha256(fit_protocol_bytes), fit_history_path: _sha256(fit_history_bytes),
                     fit_truth_path: _sha256(fit_truth_bytes)})
    if fit_protocol_bytes != protocol_bytes:
        raise ValueError("fit protocol bytes differ from prediction protocol")
    protocol_sha = _sha256(protocol_bytes)
    receipt = validate_fit_receipt(_read_canonical_json_bytes(fit_receipt_bytes, "fit receipt"),
                                   code=code, protocol_sha256=protocol_sha)
    if _sha256(checkpoint_payload) != receipt["checkpointSHA256"]:
        raise ValueError("fit checkpoint digest differs from receipt")
    expected_history = b"".join(canonical_json_bytes(row) + b"\n" for row in receipt["history"])
    if (fit_history_bytes != expected_history
            or _sha256(fit_history_bytes) != receipt["trainingHistorySHA256"]
            or len(fit_history_bytes) != receipt["trainingHistoryByteCount"]
            or _sha256(fit_truth_bytes) != receipt["trainingTruthLedgerSHA256"]
            or len(fit_truth_bytes) != receipt["trainingTruthLedgerByteCount"]):
        raise ValueError("fit source truth or streamed history differs from receipt")
    model = load_checkpoint(checkpoint_payload, code=code, protocol_sha256=protocol_sha,
                            source_plan_version=receipt["sourcePlanVersion"],
                            truth_sha256=receipt["trainingTruthLedgerSHA256"])
    if _state_digest(model.state_dict()) != receipt["finalStateSHA256"]:
        raise ValueError("fit checkpoint state differs from receipt")
    if _tensor_digests(model.state_dict()) != receipt["finalTensorSHA256"]:
        raise ValueError("fit checkpoint tensor hashes differ from receipt")
    if _head_state_digest(model.state_dict(), INACTIVE_HEADS) != receipt["finalInactiveHeadSHA256"]:
        raise ValueError("fit checkpoint inactive heads differ from receipt")
    plan = whole_source.build_role_plan(records, "development")
    if len(plan.writers) != DEVELOPMENT_WRITER_COUNT or tuple(plan.writers) != tuple(roles[1]) or len(plan.examples) != DEVELOPMENT_EXAMPLE_COUNT:
        raise ValueError("prediction source plan is not the exact eight-writer development cohort")
    if plan.version != receipt["sourcePlanVersion"]:
        raise ValueError("fit and prediction source-plan versions differ")
    # From this point onward the runner consumes only the source module's
    # label-free projection.  Truth is reserved for a separate scorer.
    prediction_inputs = whole_source.prediction_inputs(plan)
    encoding = encode_prediction_inputs(prediction_inputs)
    outputs = (infer(model, encoding.successful) if encoding.successful is not None
               else {head.name: np.empty((0, len(head.labels)), dtype=np.float32)
                     for head in OUTPUT_HEADS})
    rows = prediction_rows(encoding, outputs)
    packet = {
        "checkpointSHA256": receipt["checkpointSHA256"], "codeSHA256": code,
        "conditionalRankingContract": {
            "candidateCount": CONDITIONAL_CANDIDATE_COUNT,
            "kind": "force-rooted-for-identity-ranking-only",
            "validity": "equal-logit-neutralized-for-identity-ranking-only",
            "isAcceptanceDecision": False,
        },
        "featureContract": _feature_contract(), "fitReceiptSHA256": _sha256(fit_receipt_bytes),
        "inputFeatureStreamSHA256": encoding.stream_sha256, "modelContract": _model_contract(),
        "protocolSHA256": protocol_sha, "roleGuards": _role_guards(), "rowCount": len(rows),
        "rows": rows, "runtime": _runtime_contract(), "scope": SCOPE,
        "sourcePlanVersion": plan.version, "sourceSHA256": SOURCE_SHA256,
        "version": PREDICTION_VERSION,
    }
    packet_bytes = canonical_json_bytes(packet)
    prediction_receipt = {
        "checkpointSHA256": receipt["checkpointSHA256"], "fitReceiptSHA256": _sha256(fit_receipt_bytes),
        "packetByteCount": len(packet_bytes), "packetRelativePath": "predictions.json",
        "packetSHA256": _sha256(packet_bytes), "protocolSHA256": protocol_sha,
        "rowCount": len(rows), "sourceSHA256": SOURCE_SHA256, "version": PREDICTION_RECEIPT_VERSION,
    }
    _preserved(snapshot)
    output = _new_output_directory(output_path)
    _write_exclusive(output / "frozen-protocol.md", protocol_bytes)
    _write_exclusive(output / "predictions.json", packet_bytes)
    _write_exclusive(output / "prediction-receipt.json", canonical_json_bytes(prediction_receipt))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    fit_parser = subparsers.add_parser("fit")
    fit_parser.add_argument("--source", required=True, type=Path)
    fit_parser.add_argument("--protocol", required=True, type=Path)
    fit_parser.add_argument("--output", required=True, type=Path)
    predict_parser = subparsers.add_parser("predict")
    predict_parser.add_argument("--source", required=True, type=Path)
    predict_parser.add_argument("--protocol", required=True, type=Path)
    predict_parser.add_argument("--fit-directory", required=True, type=Path)
    predict_parser.add_argument("--output", required=True, type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> None:
    arguments = _parser().parse_args(argv)
    if arguments.command == "fit":
        fit(arguments.source, arguments.protocol, arguments.output)
    else:
        predict(arguments.source, arguments.protocol, arguments.fit_directory, arguments.output)


if __name__ == "__main__":
    main()

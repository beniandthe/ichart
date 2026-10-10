"""Frozen three-arm public glyph-information experiment.

This research-only module compares matched raster-only, trajectory-only, and
dual-view glyph encoders.  It is deliberately separate from the production
recognizer.  Fitting is restricted to the 32 public UJI training writers;
prediction is restricted to the eight already-observed public development
writers.  Official test writers, private ink, and app acceptance are outside
this module's authority.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import io
import math
import platform
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

from ..contracts import canonical_json_bytes, strict_json_loads
from ..features import (
    RASTER_HEIGHT,
    RASTER_WIDTH,
    TRAJECTORY_CHANNEL_COUNT,
    TRAJECTORY_SAMPLE_COUNT,
    encode_trajectory,
    rasterize,
)
from ..schema import FEATURE_SCHEMA
from .uji_personal import (
    SOURCE_SHA256,
    Sample,
    load_official_source,
    split_writers,
    trajectory_fingerprint,
)


FIT_VERSION = "personal-dual-view-fit-v1"
PREDICTION_VERSION = "personal-dual-view-predictions-v1"
ARCHITECTURE_VERSION = "personal-dual-view-glyph-v1"
SCOPE = "public-uji-observed-development-shared-glyph-identity-research-not-production"
ARMS = ("rasterOnly", "trajectoryOnly", "dual")
GEOMETRY_CHANNELS = (0, 1, 2, 3, 4, 7, 8, 9)
TIMING_CHANNELS_EXCLUDED = (5, 6)
SEED = 29
EPOCHS = 30
BATCH_SIZE = 128
LEARNING_RATE = 0.001
WEIGHT_DECAY = 0.0001
CPU_THREADS = 4
TRAINING_WRITER_COUNT = 32
DEVELOPMENT_WRITER_COUNT = 8
RESERVED_WRITER_COUNT = 20
TRAINING_SAMPLE_COUNT = 6_208
DEVELOPMENT_SAMPLE_COUNT = 1_552
RESERVED_SAMPLE_COUNT = 3_880
VOCABULARY_SIZE = 97
EMBEDDING_SIZE = 128

PROTOCOL_PATH = "docs/personal-dual-view-glyph-protocol-2026-09-30.md"
MODULE_PATH = "recognition_ml/ichart_recognition_ml/research/personal_dual_view.py"
TEST_PATH = "recognition_ml/tests/test_personal_dual_view.py"
SCORER_PATH = "recognition_ml/ichart_recognition_ml/research/personal_dual_view_scoring.py"
SCORER_TEST_PATH = "recognition_ml/tests/test_personal_dual_view_scoring.py"
CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
    MODULE_PATH,
    TEST_PATH,
    SCORER_PATH,
    SCORER_TEST_PATH,
)
FIT_RECEIPT_NAME = "fit-receipt.json"
FROZEN_PROTOCOL_NAME = "frozen-protocol.md"

FIT_FIELDS = {
    "version", "scope", "sourceSHA256", "protocolSHA256", "codeSHA256",
    "runtime", "featureContract", "modelContract", "optimization", "arms",
    "trainingWriters", "developmentWriters", "reservedWriters",
    "trainingSamples", "developmentSamples", "reservedSamples", "vocabulary",
    "vocabularySHA256", "initialState", "weightFiles", "weightsSHA256",
    "trainingInputHashes", "trainingInputHashesSHA256", "trainingHistory",
    "selection", "roleGuards",
}
PREDICTION_FIELDS = {
    "version", "scope", "arms", "rowCount", "sourceSHA256", "protocolSHA256",
    "codeSHA256", "runtime", "featureContract", "fitReceiptSHA256",
    "weightsSHA256", "vocabularySHA256", "rows",
}


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _is_hex_digest(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _require_exact_keys(value: object, expected: set[str], name: str) -> dict:
    if not isinstance(value, dict) or set(value) != expected:
        raise ValueError(f"{name} has missing or unknown fields")
    return value


def _absolute_unaliased(path: Path, *, kind: str) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{kind} path must be absolute and canonical")
    try:
        resolved = path.resolve(strict=True)
    except (FileNotFoundError, RuntimeError) as error:
        raise ValueError(f"{kind} does not exist") from error
    if resolved != path or path.is_symlink():
        raise ValueError(f"{kind} aliases and symlinks are forbidden")
    return path


def _require_regular_file(path: Path, *, kind: str) -> Path:
    path = _absolute_unaliased(path, kind=kind)
    if not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f"{kind} must be a regular file")
    return path


def _require_directory(path: Path, *, kind: str) -> Path:
    path = _absolute_unaliased(path, kind=kind)
    if not stat.S_ISDIR(path.stat().st_mode):
        raise ValueError(f"{kind} must be a directory")
    return path


def _new_output_directory(path: Path) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute() or ".." in path.parts or path.exists() or path.is_symlink():
        raise ValueError("Output directory must be a new absolute canonical path")
    parent = _require_directory(path.parent, kind="output parent")
    if path.parent != parent:
        raise ValueError("Output parent aliases are forbidden")
    path.mkdir(mode=0o700)
    return path


def _write_exclusive(path: Path, payload: bytes) -> None:
    with path.open("xb") as handle:
        handle.write(payload)


def _read_canonical_json(path: Path, *, kind: str) -> tuple[dict, bytes]:
    path = _require_regular_file(path, kind=kind)
    payload = path.read_bytes()
    try:
        decoded = payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"{kind} is not UTF-8") from error
    value = strict_json_loads(decoded, str(path))
    if not isinstance(value, dict) or canonical_json_bytes(value) != payload:
        raise ValueError(f"{kind} must be canonical JSON bytes")
    return value, payload


def code_identity() -> dict[str, str]:
    root = _repo_root()
    result = {}
    for relative in CODE_PATHS:
        path = _require_regular_file(root / relative, kind=f"code dependency {relative}")
        result[relative] = _sha256(path.read_bytes())
    return result


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
        "geometryChannelIndexes": list(GEOMETRY_CHANNELS),
        "rasterEncoding": FEATURE_SCHEMA.raster_encoding,
        "rasterHashEncoding": "sha256-exact-uint8-plane",
        "rasterNormalization": "float32-divide-255",
        "rasterShape": [1, RASTER_HEIGHT, RASTER_WIDTH],
        "sourceGroups": "single-source-glyph-all-original-stroke-indexes",
        "timingChannelIndexesExcluded": list(TIMING_CHANNELS_EXCLUDED),
        "trajectoryEncoding": FEATURE_SCHEMA.trajectory_encoding,
        "trajectoryHashEncoding": "sha256-exact-full-10-channel-float32-le",
        "trajectoryShape": list(FEATURE_SCHEMA.trajectory_shape),
    }


def _model_contract() -> dict[str, object]:
    return {
        "architectureVersion": ARCHITECTURE_VERSION,
        "embedding": "l2-normalized-fused-raw-128",
        "embeddingSize": EMBEDDING_SIZE,
        "fusion": "concatenate-raw-128-plus-128-linear-256-to-128",
        "inactiveBranchMask": "zeros-after-projection",
        "labelCount": VOCABULARY_SIZE,
        "rasterBranch": "avgpool2;conv-bn-relu-16-32-64-64;linear1536-to-128",
        "trajectoryBranch": "conv1d-8-32-k7;32-64-k5s2;64-64-k3s2;pool8;linear512-to-128",
    }


def _optimization_contract() -> dict[str, object]:
    return {
        "augmentation": "none",
        "batchSize": BATCH_SIZE,
        "cpuThreads": CPU_THREADS,
        "deterministicAlgorithms": True,
        "epochs": EPOCHS,
        "loss": "cross-entropy",
        "optimizer": {
            "learningRate": LEARNING_RATE,
            "name": "AdamW",
            "weightDecay": WEIGHT_DECAY,
        },
        "permutationGeneratorSeedPerArm": SEED,
        "scheduler": {"name": "CosineAnnealingLR", "tMax": EPOCHS},
        "seed": SEED,
    }


def _role_guards() -> dict[str, object]:
    return {
        "developmentFeaturesConstructedDuringFit": False,
        "developmentInferredDuringFit": False,
        "privateInkUsed": False,
        "productionEligible": False,
        "reservedWritersEncoded": False,
        "reservedWritersInferred": False,
        "reservedWritersTransformed": False,
    }


def _configure_runtime() -> None:
    torch.set_num_threads(CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED)
    np.random.seed(SEED)


class PersonalDualViewEncoder(nn.Module):
    """Identically parameterized encoder whose arm masks only projected views."""

    def __init__(self, label_count: int, arm: str):
        super().__init__()
        if label_count != VOCABULARY_SIZE:
            raise ValueError(f"Expected exactly {VOCABULARY_SIZE} glyph labels")
        if arm not in ARMS:
            raise ValueError("Unknown information arm")
        self.arm = arm

        raster_blocks: list[nn.Module] = [nn.AvgPool2d(2)]
        incoming = 1
        for outgoing in (16, 32, 64, 64):
            raster_blocks.extend(
                (
                    nn.Conv2d(incoming, outgoing, 3, stride=2, padding=1),
                    nn.BatchNorm2d(outgoing),
                    nn.ReLU(),
                )
            )
            incoming = outgoing
        self.raster_convolution = nn.Sequential(*raster_blocks)
        self.raster_projection = nn.Linear(64 * 3 * 8, EMBEDDING_SIZE)

        self.trajectory_convolution = nn.Sequential(
            nn.Conv1d(8, 32, kernel_size=7, padding=3),
            nn.ReLU(),
            nn.Conv1d(32, 64, kernel_size=5, stride=2, padding=2),
            nn.ReLU(),
            nn.Conv1d(64, 64, kernel_size=3, stride=2, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool1d(8),
        )
        self.trajectory_projection = nn.Linear(64 * 8, EMBEDDING_SIZE)
        self.fusion = nn.Linear(EMBEDDING_SIZE * 2, EMBEDDING_SIZE)
        self.classifier = nn.Linear(EMBEDDING_SIZE, label_count)
        self.register_buffer(
            "geometry_channel_indexes",
            torch.tensor(GEOMETRY_CHANNELS, dtype=torch.long),
            persistent=True,
        )

    def forward(
        self, trajectory: torch.Tensor, raster: torch.Tensor
    ) -> tuple[torch.Tensor, torch.Tensor]:
        expected_trajectory = (1, TRAJECTORY_SAMPLE_COUNT, TRAJECTORY_CHANNEL_COUNT)
        expected_raster = (1, RASTER_HEIGHT, RASTER_WIDTH)
        if trajectory.ndim != 4 or tuple(trajectory.shape[1:]) != expected_trajectory:
            raise ValueError(
                f"trajectory must have shape [batch,{expected_trajectory}], got {tuple(trajectory.shape)}"
            )
        if raster.ndim != 4 or tuple(raster.shape[1:]) != expected_raster:
            raise ValueError(f"raster must have shape [batch,{expected_raster}], got {tuple(raster.shape)}")
        if trajectory.shape[0] != raster.shape[0]:
            raise ValueError("trajectory and raster batch dimensions must match")

        geometry = trajectory[:, 0, :, :].index_select(2, self.geometry_channel_indexes)
        trajectory_raw = self.trajectory_projection(
            self.trajectory_convolution(geometry.transpose(1, 2)).flatten(1)
        )
        raster_raw = self.raster_projection(
            self.raster_convolution(raster).flatten(1)
        )
        # Mask after each complete projection.  Inactive projection biases and
        # all other branch-derived values therefore carry no information.
        if self.arm == "rasterOnly":
            trajectory_raw = torch.zeros_like(trajectory_raw)
        elif self.arm == "trajectoryOnly":
            raster_raw = torch.zeros_like(raster_raw)
        fused_raw = self.fusion(torch.cat((raster_raw, trajectory_raw), dim=1))
        return F.normalize(fused_raw, dim=1), self.classifier(fused_raw)


def _state_digest(state: Mapping[str, torch.Tensor]) -> str:
    digest = hashlib.sha256()
    for key in sorted(state):
        tensor = state[key].detach().cpu().contiguous()
        descriptor = canonical_json_bytes(
            {"dtype": str(tensor.dtype), "key": key, "shape": list(tensor.shape)}
        )
        raw = tensor.numpy().tobytes(order="C")
        digest.update(len(descriptor).to_bytes(8, "big"))
        digest.update(descriptor)
        digest.update(len(raw).to_bytes(8, "big"))
        digest.update(raw)
    return digest.hexdigest()


def _initial_state() -> dict[str, torch.Tensor]:
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(SEED)
        model = PersonalDualViewEncoder(VOCABULARY_SIZE, ARMS[0])
    return {key: value.detach().clone() for key, value in model.state_dict().items()}


def initialized_models() -> tuple[dict[str, PersonalDualViewEncoder], dict[str, object]]:
    """Return all arms at one bit-identical parameter/buffer starting state."""

    initial = _initial_state()
    models = {}
    arm_digests = {}
    arm_keys = {}
    arm_parameter_counts = {}
    for arm in ARMS:
        with torch.random.fork_rng(devices=[]):
            torch.manual_seed(SEED)
            model = PersonalDualViewEncoder(VOCABULARY_SIZE, arm)
        model.load_state_dict(copy.deepcopy(initial), strict=True)
        models[arm] = model
        state = model.state_dict()
        arm_digests[arm] = _state_digest(state)
        arm_keys[arm] = tuple(sorted(state))
        arm_parameter_counts[arm] = sum(parameter.numel() for parameter in model.parameters())
    if len(set(arm_digests.values())) != 1:
        raise ValueError("Arm initial tensors are not bit-identical")
    if len(set(arm_keys.values())) != 1 or len(set(arm_parameter_counts.values())) != 1:
        raise ValueError("Arm parameter keys or counts differ")
    keys = arm_keys[ARMS[0]]
    metadata = {
        "armSHA256": arm_digests,
        "parameterCount": arm_parameter_counts[ARMS[0]],
        "sha256": arm_digests[ARMS[0]],
        "stateKeyCount": len(keys),
        "stateKeysSHA256": _sha256(canonical_json_bytes(list(keys))),
    }
    return models, metadata


@dataclass(frozen=True)
class FeatureBatch:
    trajectory: torch.Tensor
    raster: torch.Tensor
    trajectory_hashes: tuple[str, ...]
    raster_hashes: tuple[str, ...]
    normalized_trajectory_hashes: tuple[str, ...] | None


def encode_samples(
    samples: tuple[Sample, ...],
    allowed_writers: tuple[str, ...],
    *,
    include_normalized_trajectory_hashes: bool,
) -> FeatureBatch:
    """Encode only a pre-authorized public `trn_` role, fail-closed first."""

    allowed = set(allowed_writers)
    if not samples:
        raise ValueError("Cannot encode an empty sample role")
    if (
        len(allowed) != len(allowed_writers)
        or any(not writer.startswith("trn_") for writer in allowed)
        or any(sample.writer not in allowed or not sample.writer.startswith("trn_") for sample in samples)
    ):
        raise ValueError("Reserved, private, or wrong-role writer reached feature encoding")

    trajectories = []
    rasters = []
    normalized = []
    for sample in samples:
        trajectory = encode_trajectory(sample.strokes)
        raster = rasterize(sample.strokes)
        trajectories.append(trajectory.to_bytes())
        rasters.append(raster.pixels)
        if include_normalized_trajectory_hashes:
            normalized.append(trajectory_fingerprint(sample))

    trajectory_array = np.frombuffer(b"".join(trajectories), dtype="<f4").copy().reshape(
        len(samples), *FEATURE_SCHEMA.trajectory_shape
    )
    raster_array = np.frombuffer(b"".join(rasters), dtype=np.uint8).copy().reshape(
        len(samples), 1, RASTER_HEIGHT, RASTER_WIDTH
    )
    return FeatureBatch(
        trajectory=torch.from_numpy(trajectory_array),
        raster=torch.from_numpy(raster_array),
        trajectory_hashes=tuple(_sha256(payload) for payload in trajectories),
        raster_hashes=tuple(_sha256(payload) for payload in rasters),
        normalized_trajectory_hashes=tuple(normalized) if include_normalized_trajectory_hashes else None,
    )


def _validate_roles(
    records: tuple[Sample, ...],
) -> tuple[tuple[str, ...], tuple[str, ...], tuple[str, ...]]:
    training, development, reserved = split_writers(records)
    if (
        tuple(map(len, (training, development, reserved)))
        != (TRAINING_WRITER_COUNT, DEVELOPMENT_WRITER_COUNT, RESERVED_WRITER_COUNT)
        or len(set(training + development + reserved)) != 60
        or any(not writer.startswith("trn_") for writer in training + development)
        or any(not writer.startswith("tst_") for writer in reserved)
    ):
        raise ValueError("Public writer roles do not match the frozen 32/8/20 partition")
    return training, development, reserved


def _select_role_samples(
    records: tuple[Sample, ...], allowed_writers: tuple[str, ...], expected_count: int
) -> tuple[Sample, ...]:
    allowed = set(allowed_writers)
    if len(allowed) != len(allowed_writers) or any(not writer.startswith("trn_") for writer in allowed):
        raise ValueError("Only public trn_ roles may be selected")
    selected = tuple(sorted((sample for sample in records if sample.writer in allowed), key=lambda item: item.identity))
    if len(selected) != expected_count or any(sample.writer not in allowed for sample in selected):
        raise ValueError("Selected role is incomplete or contaminated")
    return selected


def _vocabulary(samples: Sequence[Sample]) -> tuple[str, ...]:
    vocabulary = tuple(sorted({sample.label for sample in samples}))
    if len(vocabulary) != VOCABULARY_SIZE or any(len(label) != 1 for label in vocabulary):
        raise ValueError("Expected the complete 97-label UJI vocabulary")
    return vocabulary


def vocabulary_digest(vocabulary: Sequence[str]) -> str:
    return _sha256(canonical_json_bytes(list(vocabulary)))


def opaque_id(source_sha256: str, sample_identity: str) -> str:
    if not _is_hex_digest(source_sha256) or not sample_identity:
        raise ValueError("Invalid opaque identity input")
    return _sha256(
        b"personal-dual-view-v1\0"
        + source_sha256.encode("ascii")
        + b"\0"
        + sample_identity.encode("utf-8")
    )


def _training_input_hashes(batch: FeatureBatch) -> list[dict[str, str]]:
    normalized = batch.normalized_trajectory_hashes
    if normalized is None:
        raise ValueError("Training normalized trajectory hashes were not constructed")
    if not (
        len(batch.raster_hashes) == len(batch.trajectory_hashes) == len(normalized)
    ):
        raise ValueError("Training feature hash streams have different lengths")
    values = [
        {
            "normalizedTrajectorySHA256": normalized[index],
            "rasterSHA256": batch.raster_hashes[index],
            "trajectorySHA256": batch.trajectory_hashes[index],
        }
        for index in range(len(normalized))
    ]
    if any(not all(_is_hex_digest(value) for value in row.values()) for row in values):
        raise ValueError("Invalid training feature hash")
    # No label-bearing source identity is retained.  Sort the three hashes while
    # preserving duplicate rows and thus exact multiplicity.
    return sorted(
        values,
        key=lambda row: (
            row["rasterSHA256"],
            row["trajectorySHA256"],
            row["normalizedTrajectorySHA256"],
        ),
    )


def _train_arm(
    model: PersonalDualViewEncoder,
    arm: str,
    batch: FeatureBatch,
    targets: torch.Tensor,
) -> list[dict[str, object]]:
    if model.arm != arm or arm not in ARMS:
        raise ValueError("Model/checkpoint arm mask mismatch")
    if len(targets) != len(batch.trajectory) or len(targets) != len(batch.raster):
        raise ValueError("Training feature and target counts differ")
    generator = torch.Generator(device="cpu").manual_seed(SEED)
    optimizer = torch.optim.AdamW(
        model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)
    history = []
    for epoch in range(EPOCHS):
        model.train()
        permutation = torch.randperm(len(targets), generator=generator)
        total_loss = 0.0
        correct = 0
        for indexes in permutation.split(BATCH_SIZE):
            trajectory = batch.trajectory[indexes].float()
            raster = batch.raster[indexes].float() / 255.0
            optimizer.zero_grad(set_to_none=True)
            _, logits = model(trajectory, raster)
            loss = F.cross_entropy(logits, targets[indexes])
            if not torch.isfinite(loss):
                raise ValueError("Training produced nonfinite loss")
            loss.backward()
            optimizer.step()
            total_loss += float(loss.detach()) * len(indexes)
            correct += int((logits.detach().argmax(1) == targets[indexes]).sum())
        scheduler.step()
        epoch_report = {
            "epoch": epoch + 1,
            "trainCorrect": correct,
            "trainLoss": total_loss / len(targets),
        }
        history.append(epoch_report)
        print(
            canonical_json_bytes({"arm": arm, **epoch_report}).decode("utf-8"),
            flush=True,
        )
    if any(not torch.isfinite(value).all() for value in model.state_dict().values() if value.is_floating_point()):
        raise ValueError("Final model contains nonfinite tensors")
    return history


def _checkpoint_bytes(
    model: PersonalDualViewEncoder, arm: str, vocabulary_sha256: str
) -> bytes:
    if model.arm != arm:
        raise ValueError("Cannot publish a checkpoint under another arm mask")
    buffer = io.BytesIO()
    torch.save(
        {
            "architectureVersion": ARCHITECTURE_VERSION,
            "arm": arm,
            "stateDict": model.state_dict(),
            "version": FIT_VERSION,
            "vocabularySHA256": vocabulary_sha256,
        },
        buffer,
    )
    return buffer.getvalue()


def _load_checkpoint(
    payload: bytes, arm: str, vocabulary_sha256: str
) -> PersonalDualViewEncoder:
    checkpoint = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
    checkpoint = _require_exact_keys(
        checkpoint,
        {"architectureVersion", "arm", "stateDict", "version", "vocabularySHA256"},
        "checkpoint",
    )
    if (
        checkpoint["architectureVersion"] != ARCHITECTURE_VERSION
        or checkpoint["arm"] != arm
        or checkpoint["version"] != FIT_VERSION
        or checkpoint["vocabularySHA256"] != vocabulary_sha256
        or not isinstance(checkpoint["stateDict"], dict)
    ):
        raise ValueError("Checkpoint contract or arm mask does not match")
    model = PersonalDualViewEncoder(VOCABULARY_SIZE, arm)
    model.load_state_dict(checkpoint["stateDict"], strict=True)
    return model


def _infer(
    model: PersonalDualViewEncoder, batch: FeatureBatch
) -> tuple[np.ndarray, np.ndarray]:
    model.eval()
    embeddings = []
    logits = []
    with torch.inference_mode():
        for start in range(0, len(batch.trajectory), BATCH_SIZE):
            selection = slice(start, start + BATCH_SIZE)
            embedding, raw_logits = model(
                batch.trajectory[selection].float(),
                batch.raster[selection].float() / 255.0,
            )
            embeddings.append(embedding.cpu().numpy())
            logits.append(raw_logits.cpu().numpy())
    embedding_values = np.concatenate(embeddings)
    logit_values = np.concatenate(logits)
    if (
        embedding_values.shape != (len(batch.trajectory), EMBEDDING_SIZE)
        or logit_values.shape != (len(batch.trajectory), VOCABULARY_SIZE)
        or not np.isfinite(embedding_values).all()
        or not np.isfinite(logit_values).all()
    ):
        raise ValueError("Prediction output has wrong shape or nonfinite values")
    return embedding_values, logit_values


def _prediction_rows(
    samples: tuple[Sample, ...],
    batch: FeatureBatch,
    outputs: Mapping[str, tuple[np.ndarray, np.ndarray]],
    source_sha256: str,
) -> list[dict[str, object]]:
    if set(outputs) != set(ARMS) or len(samples) != len(batch.trajectory):
        raise ValueError("Incomplete prediction arms or rows")
    rows = []
    for index, sample in enumerate(samples):
        arm_outputs = {}
        for arm in ARMS:
            embedding, logits = outputs[arm]
            if (
                embedding.shape != (len(samples), EMBEDDING_SIZE)
                or logits.shape != (len(samples), VOCABULARY_SIZE)
            ):
                raise ValueError("Prediction matrix has wrong shape")
            row_embedding = embedding[index]
            row_logits = logits[index]
            if not np.isfinite(row_embedding).all() or not np.isfinite(row_logits).all():
                raise ValueError("Prediction row contains nonfinite values")
            arm_outputs[arm] = {
                "embedding": [float(value) for value in row_embedding],
                "rawLogits": [float(value) for value in row_logits],
            }
        rows.append(
            {
                "opaqueID": opaque_id(source_sha256, sample.identity),
                "outputs": arm_outputs,
                "rasterSHA256": batch.raster_hashes[index],
                "sourceGroups": [list(range(len(sample.strokes)))],
                "trajectorySHA256": batch.trajectory_hashes[index],
            }
        )
    rows.sort(key=lambda row: row["opaqueID"])
    if len({row["opaqueID"] for row in rows}) != len(rows):
        raise ValueError("Opaque query identity collision")
    return rows


def _validate_fit_receipt(
    receipt: object,
    *,
    code: dict[str, str],
    runtime: dict[str, object],
    protocol_sha256: str,
    roles: tuple[tuple[str, ...], tuple[str, ...], tuple[str, ...]],
) -> dict:
    receipt = _require_exact_keys(receipt, FIT_FIELDS, "fit receipt")
    training, development, reserved = roles
    expected_scalars = {
        "version": FIT_VERSION,
        "scope": SCOPE,
        "sourceSHA256": SOURCE_SHA256,
        "protocolSHA256": protocol_sha256,
        "codeSHA256": code,
        "runtime": runtime,
        "featureContract": _feature_contract(),
        "modelContract": _model_contract(),
        "optimization": _optimization_contract(),
        "arms": list(ARMS),
        "trainingWriters": list(training),
        "developmentWriters": list(development),
        "reservedWriters": list(reserved),
        "trainingSamples": TRAINING_SAMPLE_COUNT,
        "developmentSamples": DEVELOPMENT_SAMPLE_COUNT,
        "reservedSamples": RESERVED_SAMPLE_COUNT,
        "selection": "final-epoch-only",
        "roleGuards": _role_guards(),
    }
    if any(receipt.get(key) != value for key, value in expected_scalars.items()):
        raise ValueError("Fit receipt metadata is unbound or changed")
    vocabulary = receipt["vocabulary"]
    if (
        not isinstance(vocabulary, list)
        or len(vocabulary) != VOCABULARY_SIZE
        or len(set(vocabulary)) != VOCABULARY_SIZE
        or any(not isinstance(label, str) or len(label) != 1 for label in vocabulary)
        or vocabulary != sorted(vocabulary)
        or receipt["vocabularySHA256"] != vocabulary_digest(vocabulary)
    ):
        raise ValueError("Fit vocabulary is invalid or unbound")

    _, expected_initial = initialized_models()
    if receipt["initialState"] != expected_initial:
        raise ValueError("Fit initial tensors/keys/count do not match current architecture")
    weight_files = receipt["weightFiles"]
    weights_sha = receipt["weightsSHA256"]
    if (
        weight_files != {arm: f"weights/{arm}.pt" for arm in ARMS}
        or not isinstance(weights_sha, dict)
        or set(weights_sha) != set(ARMS)
        or any(not _is_hex_digest(value) for value in weights_sha.values())
    ):
        raise ValueError("Fit weight bindings are invalid")

    training_hashes = receipt["trainingInputHashes"]
    expected_hash_keys = {
        "normalizedTrajectorySHA256", "rasterSHA256", "trajectorySHA256"
    }
    if (
        not isinstance(training_hashes, list)
        or len(training_hashes) != TRAINING_SAMPLE_COUNT
        or any(
            not isinstance(row, dict)
            or set(row) != expected_hash_keys
            or any(not _is_hex_digest(value) for value in row.values())
            for row in training_hashes
        )
        or training_hashes
        != sorted(
            training_hashes,
            key=lambda row: (
                row["rasterSHA256"],
                row["trajectorySHA256"],
                row["normalizedTrajectorySHA256"],
            ),
        )
        or receipt["trainingInputHashesSHA256"]
        != _sha256(canonical_json_bytes(training_hashes))
    ):
        raise ValueError("Fit training feature hashes are incomplete or unbound")

    histories = receipt["trainingHistory"]
    if not isinstance(histories, dict) or set(histories) != set(ARMS):
        raise ValueError("Fit histories are incomplete")
    for arm in ARMS:
        history = histories[arm]
        if not isinstance(history, list) or len(history) != EPOCHS:
            raise ValueError("Fit history has wrong epoch count")
        for index, row in enumerate(history, 1):
            if (
                not isinstance(row, dict)
                or set(row) != {"epoch", "trainCorrect", "trainLoss"}
                or row["epoch"] != index
                or isinstance(row["trainCorrect"], bool)
                or not isinstance(row["trainCorrect"], int)
                or not 0 <= row["trainCorrect"] <= TRAINING_SAMPLE_COUNT
                or isinstance(row["trainLoss"], bool)
                or not isinstance(row["trainLoss"], (int, float))
                or not math.isfinite(float(row["trainLoss"]))
                or float(row["trainLoss"]) < 0
            ):
                raise ValueError("Fit history row is invalid")
    return receipt


def _input_snapshot(paths: Sequence[Path]) -> dict[Path, str]:
    return {path: _sha256(path.read_bytes()) for path in paths}


def _assert_inputs_preserved(snapshot: Mapping[Path, str], code: Mapping[str, str]) -> None:
    if any(_sha256(path.read_bytes()) != digest for path, digest in snapshot.items()):
        raise ValueError("Source, protocol, fit, or weights changed during operation")
    if code_identity() != dict(code):
        raise ValueError("Bound code changed during operation")


def fit(source: Path, protocol: Path, output: Path) -> None:
    source = _require_regular_file(source, kind="public UJI source")
    protocol = _require_regular_file(protocol, kind="frozen protocol")
    source_bytes = source.read_bytes()
    protocol_bytes = protocol.read_bytes()
    code = code_identity()
    if _sha256(source_bytes) != SOURCE_SHA256:
        raise ValueError("Wrong public UJI source digest")
    if _sha256(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Supplied protocol differs from the frozen repository protocol")
    snapshot = _input_snapshot((source, protocol))
    _configure_runtime()
    runtime = _runtime_contract()

    records = load_official_source(source)
    roles = training_writers, development_writers, reserved_writers = _validate_roles(records)
    training = _select_role_samples(records, training_writers, TRAINING_SAMPLE_COUNT)
    vocabulary = _vocabulary(training)
    vocabulary_sha = vocabulary_digest(vocabulary)
    targets = torch.tensor([vocabulary.index(sample.label) for sample in training], dtype=torch.long)

    # Only training-role samples cross the feature boundary during fit.
    training_batch = encode_samples(
        training,
        training_writers,
        include_normalized_trajectory_hashes=True,
    )
    training_hashes = _training_input_hashes(training_batch)
    models, initial_metadata = initialized_models()

    output = _new_output_directory(output)
    weights_directory = output / "weights"
    weights_directory.mkdir(mode=0o700)
    _write_exclusive(output / FROZEN_PROTOCOL_NAME, protocol_bytes)
    histories = {}
    weights_sha = {}
    for arm in ARMS:
        model = models[arm]
        if _state_digest(model.state_dict()) != initial_metadata["sha256"]:
            raise ValueError("Arm did not begin from the frozen bit-identical tensors")
        histories[arm] = _train_arm(model, arm, training_batch, targets)
        payload = _checkpoint_bytes(model, arm, vocabulary_sha)
        path = weights_directory / f"{arm}.pt"
        _write_exclusive(path, payload)
        weights_sha[arm] = _sha256(payload)

    receipt = {
        "arms": list(ARMS),
        "codeSHA256": code,
        "developmentSamples": DEVELOPMENT_SAMPLE_COUNT,
        "developmentWriters": list(development_writers),
        "featureContract": _feature_contract(),
        "initialState": initial_metadata,
        "modelContract": _model_contract(),
        "optimization": _optimization_contract(),
        "protocolSHA256": _sha256(protocol_bytes),
        "reservedSamples": RESERVED_SAMPLE_COUNT,
        "reservedWriters": list(reserved_writers),
        "roleGuards": _role_guards(),
        "runtime": runtime,
        "scope": SCOPE,
        "selection": "final-epoch-only",
        "sourceSHA256": SOURCE_SHA256,
        "trainingHistory": histories,
        "trainingInputHashes": training_hashes,
        "trainingInputHashesSHA256": _sha256(canonical_json_bytes(training_hashes)),
        "trainingSamples": TRAINING_SAMPLE_COUNT,
        "trainingWriters": list(training_writers),
        "version": FIT_VERSION,
        "vocabulary": list(vocabulary),
        "vocabularySHA256": vocabulary_sha,
        "weightFiles": {arm: f"weights/{arm}.pt" for arm in ARMS},
        "weightsSHA256": weights_sha,
    }
    _validate_fit_receipt(
        receipt,
        code=code,
        runtime=runtime,
        protocol_sha256=_sha256(protocol_bytes),
        roles=roles,
    )
    _assert_inputs_preserved(snapshot, code)
    # The canonical receipt is deliberately the final fit artifact written.
    _write_exclusive(output / FIT_RECEIPT_NAME, canonical_json_bytes(receipt))


def predict(source: Path, protocol: Path, fit_directory: Path, output: Path) -> None:
    source = _require_regular_file(source, kind="public UJI source")
    protocol = _require_regular_file(protocol, kind="frozen protocol")
    fit_directory = _require_directory(fit_directory, kind="fit directory")
    source_bytes = source.read_bytes()
    protocol_bytes = protocol.read_bytes()
    code = code_identity()
    if _sha256(source_bytes) != SOURCE_SHA256:
        raise ValueError("Wrong public UJI source digest")
    if _sha256(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Supplied protocol differs from the frozen repository protocol")
    _configure_runtime()
    runtime = _runtime_contract()

    receipt, receipt_bytes = _read_canonical_json(
        fit_directory / FIT_RECEIPT_NAME, kind="fit receipt"
    )
    frozen_protocol = _require_regular_file(
        fit_directory / FROZEN_PROTOCOL_NAME, kind="fit frozen protocol"
    )
    if frozen_protocol.read_bytes() != protocol_bytes:
        raise ValueError("Fit frozen protocol differs from supplied protocol")

    records = load_official_source(source)
    roles = training_writers, development_writers, reserved_writers = _validate_roles(records)
    receipt = _validate_fit_receipt(
        receipt,
        code=code,
        runtime=runtime,
        protocol_sha256=_sha256(protocol_bytes),
        roles=roles,
    )

    weight_paths = {
        arm: _require_regular_file(
            fit_directory / receipt["weightFiles"][arm], kind=f"{arm} checkpoint"
        )
        for arm in ARMS
    }
    weight_payloads = {arm: weight_paths[arm].read_bytes() for arm in ARMS}
    if any(_sha256(weight_payloads[arm]) != receipt["weightsSHA256"][arm] for arm in ARMS):
        raise ValueError("Fit checkpoint digest mismatch")
    input_paths = (source, protocol, fit_directory / FIT_RECEIPT_NAME, frozen_protocol) + tuple(
        weight_paths[arm] for arm in ARMS
    )
    input_snapshot = _input_snapshot(input_paths)
    # Validate every final checkpoint and its immutable arm mask before any
    # development feature is transformed.
    models = {
        arm: _load_checkpoint(weight_payloads[arm], arm, receipt["vocabularySHA256"])
        for arm in ARMS
    }

    development = _select_role_samples(
        records, development_writers, DEVELOPMENT_SAMPLE_COUNT
    )
    if _vocabulary(development) != tuple(receipt["vocabulary"]):
        raise ValueError("Development vocabulary differs from fit vocabulary")
    ordered = tuple(
        sorted(
            development,
            key=lambda sample: opaque_id(SOURCE_SHA256, sample.identity),
        )
    )
    development_batch = encode_samples(
        ordered,
        development_writers,
        include_normalized_trajectory_hashes=False,
    )
    outputs = {arm: _infer(models[arm], development_batch) for arm in ARMS}
    rows = _prediction_rows(ordered, development_batch, outputs, SOURCE_SHA256)
    if len(rows) != DEVELOPMENT_SAMPLE_COUNT:
        raise ValueError("Prediction did not retain the complete development cohort")

    prediction = {
        "arms": list(ARMS),
        "codeSHA256": code,
        "featureContract": _feature_contract(),
        "fitReceiptSHA256": _sha256(receipt_bytes),
        "protocolSHA256": _sha256(protocol_bytes),
        "rowCount": DEVELOPMENT_SAMPLE_COUNT,
        "rows": rows,
        "runtime": runtime,
        "scope": SCOPE,
        "sourceSHA256": SOURCE_SHA256,
        "version": PREDICTION_VERSION,
        "vocabularySHA256": receipt["vocabularySHA256"],
        "weightsSHA256": receipt["weightsSHA256"],
    }
    _require_exact_keys(prediction, PREDICTION_FIELDS, "prediction packet")
    output = _new_output_directory(output)
    _assert_inputs_preserved(input_snapshot, code)
    _write_exclusive(output / "predictions.json", canonical_json_bytes(prediction))


def entrypoint(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    fit_parser = commands.add_parser("fit")
    fit_parser.add_argument("--source", type=Path, required=True)
    fit_parser.add_argument("--protocol", type=Path, required=True)
    fit_parser.add_argument("--output", type=Path, required=True)
    predict_parser = commands.add_parser("predict")
    predict_parser.add_argument("--source", type=Path, required=True)
    predict_parser.add_argument("--protocol", type=Path, required=True)
    predict_parser.add_argument("--fit", type=Path, required=True)
    predict_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command == "fit":
        fit(args.source, args.protocol, args.output)
    else:
        predict(args.source, args.protocol, args.fit, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(entrypoint())

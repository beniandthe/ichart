"""Fixed matched 102-class raster-control versus stroke-field training.

This research-only module consumes the prepared training-only mmap.  It never
opens development inputs, development truth, private ink, profiles, or app
state.  The complete exposure schedule is frozen before the first optimizer
step and only final-epoch checkpoints may be published.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import io
import os
from pathlib import Path
import platform

import numpy as np
import torch
from torch.nn import functional as F

from ..contracts import canonical_json_bytes, strict_json_loads
from . import personal_hwrt_stroke_data as data
from . import personal_stroke_field as field


VERSION = "personal-hwrt-stroke-field-fit-v1"
SCOPE = "research-only-matched-hwrt-stroke-field-v1"
PLAN_VERSION = "personal-hwrt-stroke-field-training-plan-v1"
PROTOCOL = "docs/personal-hwrt-stroke-field-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "3cda2bcb7c64a79c3ef4371a8ef01fb1df0e0e75512a7f2f49f39cdc58ff9d13"
ROOT = Path(__file__).resolve().parents[3]

ARMS = field.ARMS
LABEL_COUNT = 102
OLD_LABEL_COUNT = 97
NOVEL_LABELS = ("#", "+", "/", "ø", "△")
SEED = 29
CPU_THREADS = 4
EPOCHS = 30
BATCH_SIZE = 128
OLD_EXPOSURES_PER_EPOCH = 6_208
NOVEL_EXPOSURES_PER_LABEL_PER_EPOCH = 64
EXPOSURES_PER_EPOCH = 6_528
UPDATES_PER_EPOCH = 51
EXPOSURES_PER_ARM = 195_840
UPDATES_PER_ARM = 1_530
TOTAL_TRAINING_ROWS = 10_073

RECIPE = {
    "epochs": EPOCHS,
    "updatesPerArm": UPDATES_PER_ARM,
    "exposuresPerArm": EXPOSURES_PER_ARM,
    "batchSize": BATCH_SIZE,
    "seed": SEED,
}

OPTIMIZATION = {
    "loss": "crossEntropy",
    "optimizer": "AdamW",
    "learningRate": 0.001,
    "weightDecay": 0.0001,
    "scheduler": {"name": "CosineAnnealingLR", "tMax": EPOCHS, "stepPer": "epoch"},
    "cpuThreads": CPU_THREADS,
    "deterministicAlgorithms": True,
    "selection": "final-epoch-only",
}

ROW_FIELDS = {
    "opaqueID",
    "label",
    "source",
    "writer",
    "session",
    "nativeSymbolID",
    "rasterSHA256",
    "fieldSHA256",
    "normalizedGeometrySHA256",
}

NATIVE_MAPPING = {
    "196": "+",
    "922": "/",
    "266": "#",
    "948": "#",
    "950": "ø",
    "959": "△",
    "977": "△",
    "152": "△",
}

NOVEL_COUNTS = {"+": 81, "/": 478, "#": 1_173, "ø": 853, "△": 1_280}

# Every implementation and boundary that can affect encoding, fitting, blind
# freezing, or domain projection is copied and hashed before optimization.
CODE_PATHS = tuple(dict.fromkeys((*data.CODE_PATHS,
    "recognition_ml/ichart_recognition_ml/research/hwrt_source_intake.py",
    "recognition_ml/ichart_recognition_ml/research/personal_hwrt_stroke_train.py",
    "recognition_ml/ichart_recognition_ml/research/personal_hwrt_stroke_evaluate.py",
    "recognition_ml/tests/test_hwrt_source_intake.py",
    "recognition_ml/tests/test_personal_stroke_field.py",
    "recognition_ml/tests/test_personal_hwrt_stroke_data.py",
    "recognition_ml/tests/test_personal_hwrt_stroke_train.py",
    "recognition_ml/tests/test_personal_hwrt_stroke_evaluate.py",
    "iChart/Shared/ChordNotation/ChordRecognitionDomain.swift",
    "iChartTests/Recognition/ChordRecognitionDomainTests.swift",
)))


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _digest(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _regular(path: Path, *, maximum: int = 2 * 1024 * 1024 * 1024) -> Path:
    path = Path(path)
    _require(path.is_absolute() and path.resolve() == path, "Absolute canonical path required")
    _require(path.is_file() and not path.is_symlink(), "Bounded regular file required")
    size = path.stat().st_size
    _require(0 < size <= maximum, "Bounded nonempty file required")
    return path


def _read(path: Path, *, maximum: int = 2 * 1024 * 1024 * 1024) -> bytes:
    return _regular(path, maximum=maximum).read_bytes()


def _file_sha256(path: Path, *, maximum: int = 8 * 1024 * 1024 * 1024) -> str:
    path = _regular(path, maximum=maximum)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _parsed(payload: bytes, *, name: str) -> object:
    try:
        value = strict_json_loads(payload.decode("utf-8"), name)
    except (UnicodeDecodeError, TypeError) as error:
        raise ValueError(f"Invalid UTF-8 JSON for {name}") from error
    _require(canonical_json_bytes(value) == payload, f"Canonical JSON required for {name}")
    return value


def _write_exclusive(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())


def _fresh_directory(path: Path) -> Path:
    path = Path(path)
    _require(path.is_absolute() and path.resolve() == path, "Fresh absolute output path required")
    _require(path.parent.is_dir() and path.parent.resolve() == path.parent
             and ROOT != path and ROOT not in path.parents, "Output must be outside the repository")
    _require(not path.exists() and not path.is_symlink(), "Fresh output directory required; resume is forbidden")
    path.mkdir(mode=0o700, parents=False)
    return path


def _stream_update(digest: "hashlib._Hash", payload: bytes) -> None:
    digest.update(len(payload).to_bytes(8, "big"))
    digest.update(payload)


def _tensor_bytes(tensor: torch.Tensor) -> bytes:
    return tensor.detach().cpu().contiguous().numpy().tobytes()


def _tensor_sha256(tensor: torch.Tensor) -> str:
    return _sha256(_tensor_bytes(tensor))


def _state_digest(state: dict[str, torch.Tensor]) -> str:
    digest = hashlib.sha256()
    for name in sorted(state):
        tensor = state[name].detach().cpu().contiguous()
        _stream_update(digest, name.encode("utf-8"))
        _stream_update(digest, str(tensor.dtype).encode("ascii"))
        _stream_update(digest, canonical_json_bytes(list(tensor.shape)))
        _stream_update(digest, tensor.numpy().tobytes())
    return digest.hexdigest()


def _runtime_contract() -> dict[str, object]:
    return {
        "python": platform.python_version(),
        "numpy": np.__version__,
        "torch": torch.__version__,
        "platform": platform.platform(),
        "cpuThreads": torch.get_num_threads(),
        "deterministicAlgorithms": torch.are_deterministic_algorithms_enabled(),
    }


def code_identity() -> dict[str, str]:
    result = {name: _sha256(_read(ROOT / name, maximum=32 * 1024 * 1024)) for name in CODE_PATHS}
    _require(result[PROTOCOL] == PROTOCOL_SHA256, "Frozen protocol changed")
    return result


def _vocabulary_sha256(vocabulary: list[str] | tuple[str, ...]) -> str:
    return _sha256(canonical_json_bytes(list(vocabulary)))


def _derived_seed(kind: str, identity: str | int) -> int:
    payload = canonical_json_bytes({"seed": SEED, "kind": kind, "identity": identity})
    return int.from_bytes(hashlib.sha256(payload).digest()[:8], "big", signed=False)


def _validate_training_bundle(fields: np.ndarray, metadata: dict, receipt: dict) -> tuple[list[dict], tuple[str, ...]]:
    _require(isinstance(fields, np.memmap), "Training fields must remain disk-backed")
    _require(fields.dtype == np.float32 and fields.shape == (TOTAL_TRAINING_ROWS, 5, 96, 256),
             "Training field mmap shape/dtype changed")
    _require(not fields.flags.writeable and fields.flags.c_contiguous, "Training mmap must be read-only C-order")
    _require(isinstance(metadata, dict) and set(metadata) == {"version", "vocabulary", "rows"},
             "Training metadata schema changed")
    _require(metadata["version"] == data.TRAINING_VERSION, "Training metadata version changed")
    vocabulary = tuple(metadata["vocabulary"])
    _require(len(vocabulary) == LABEL_COUNT and len(set(vocabulary)) == LABEL_COUNT,
             "Training vocabulary must contain 102 unique labels")
    _require(tuple(sorted(vocabulary[:OLD_LABEL_COUNT])) == vocabulary[:OLD_LABEL_COUNT]
             and vocabulary[OLD_LABEL_COUNT:] == NOVEL_LABELS
             and not set(vocabulary[:OLD_LABEL_COUNT]) & set(NOVEL_LABELS),
             "Vocabulary is not the sorted UJI97 prefix plus fixed five-label suffix")
    rows = metadata["rows"]
    _require(isinstance(rows, list) and len(rows) == TOTAL_TRAINING_ROWS, "Training metadata row count changed")
    _require(isinstance(receipt, dict) and receipt.get("version") == data.DATA_VERSION,
             "Data receipt version changed")
    _require(receipt.get("role") == "training" and receipt.get("fieldVersion") == field.VERSION
             and receipt.get("protocolSHA256") == PROTOCOL_SHA256
             and receipt.get("counts") == {
                 "rows": TOTAL_TRAINING_ROWS, "ujiRows": OLD_EXPOSURES_PER_EPOCH,
                 "hwrtRows": TOTAL_TRAINING_ROWS - OLD_EXPOSURES_PER_EPOCH,
             }
             and receipt.get("fitReceiptSHA256") is None
             and receipt.get("trainingDataReceiptSHA256") is None,
             "Training data role/count/lineage changed")
    _require(receipt.get("vocabulary") == list(vocabulary)
             and receipt.get("vocabularySHA256") == _vocabulary_sha256(vocabulary),
             "Data receipt vocabulary changed")
    _require(receipt.get("codeSHA256") == data.code_identity(), "Prepared-data code identity changed")
    bindings = receipt.get("sourceBindings")
    _require(isinstance(bindings, dict) and set(bindings) == {
        "ujiSourceSHA256", "hwrtReceiptSHA256", "hwrtSelectedRecordsSHA256", "hasyReceiptSHA256",
        "hasyLabelsSHA256", "hasyPixelDuplicatesSHA256", "joinReportSHA256", "domain", "hwrtArchiveSHA256",
    } and bindings["ujiSourceSHA256"] == data.SOURCE_SHA256
        and bindings["hwrtReceiptSHA256"] == data.HWRT_RECEIPT_SHA256
        and bindings["hwrtSelectedRecordsSHA256"] == data.HWRT_SELECTED_SHA256
        and bindings["hasyReceiptSHA256"] == data.HASY_RECEIPT_SHA256
        and bindings["hasyLabelsSHA256"] == data.HASY_LABELS_SHA256
        and bindings["hasyPixelDuplicatesSHA256"] == data.HASY_PIXEL_DUPLICATES_SHA256
        and bindings["joinReportSHA256"] == data.JOIN_REPORT_SHA256
        and bindings["hwrtArchiveSHA256"] == "b96feafd71b01f1623997dff3cc8ac4d18628d128cee1b3df1880518bba3ea4a"
        and isinstance(bindings["domain"], dict)
        and bindings["domain"].get("sha256") == data.DOMAIN_SHA256,
        "Prepared-data source bindings changed")

    opaque_ids: set[str] = set()
    uji_counts = {label: 0 for label in vocabulary[:OLD_LABEL_COUNT]}
    novel_counts = {label: 0 for label in NOVEL_LABELS}
    for index, row in enumerate(rows):
        _require(isinstance(row, dict) and set(row) == ROW_FIELDS, "Training row schema changed")
        _require(row["source"] in {"uji", "hwrt"},
                 "Only fixed training roles may be fitted")
        _require(isinstance(row["opaqueID"], str) and row["opaqueID"] not in opaque_ids,
                 "Duplicate or invalid opaque training identity")
        opaque_ids.add(row["opaqueID"])
        _require(row["label"] in vocabulary and all(_digest(row[name]) for name in
                 ("rasterSHA256", "fieldSHA256", "normalizedGeometrySHA256")),
                 "Invalid label or feature commitment")
        # This bounded check reads one mmap row at a time; no full in-memory copy.
        value = np.asarray(fields[index])
        _require(bool(np.isfinite(value).all()) and _sha256(value.tobytes()) == row["fieldSHA256"],
                 "Training field bytes differ from metadata")
        if row["source"] == "uji":
            _require(row["label"] in uji_counts and row["writer"] is not None
                     and row["session"] in (1, 2) and row["nativeSymbolID"] is None,
                     "Malformed UJI training row")
            uji_counts[row["label"]] += 1
        else:
            _require(row["writer"] is None and row["session"] is None
                     and isinstance(row["nativeSymbolID"], str)
                     and row["nativeSymbolID"] in NATIVE_MAPPING,
                     "Malformed HWRT training row")
            _require(row["label"] == NATIVE_MAPPING[row["nativeSymbolID"]],
                     "HWRT native/model mapping changed")
            novel_counts[row["label"]] += 1
    _require(set(uji_counts.values()) == {64} and sum(uji_counts.values()) == OLD_EXPOSURES_PER_EPOCH,
             "UJI training grid is not exactly 64 rows per class")
    _require(novel_counts == NOVEL_COUNTS, "HWRT training class counts changed")
    return rows, vocabulary


def _shuffle(values: list[int], generator: np.random.Generator) -> list[int]:
    order = generator.permutation(len(values)).tolist()
    return [values[index] for index in order]


class _CyclingPool:
    def __init__(self, label: str, values: list[int]):
        _require(values and len(set(values)) == len(values), "Novel class pool must be nonempty and unique")
        self.label = label
        self.values = list(values)
        self.generator = np.random.default_rng(_derived_seed("novel-pool", label))
        self.order = _shuffle(self.values, self.generator)
        self.cursor = 0
        self.shuffle_count = 1

    def draw(self, count: int) -> list[int]:
        result: list[int] = []
        while len(result) < count:
            if self.cursor == len(self.order):
                self.order = _shuffle(self.values, self.generator)
                self.cursor = 0
                self.shuffle_count += 1
            take = min(count - len(result), len(self.order) - self.cursor)
            result.extend(self.order[self.cursor:self.cursor + take])
            self.cursor += take
        return result


def build_training_plan(rows: list[dict], vocabulary: tuple[str, ...]) -> dict:
    """Freeze all 195,840 source-row exposures before optimization."""

    _require(len(rows) == TOTAL_TRAINING_ROWS and len(vocabulary) == LABEL_COUNT,
             "Incomplete training rows/vocabulary")
    old = [index for index, row in enumerate(rows) if row["source"] == "uji"]
    _require(len(old) == OLD_EXPOSURES_PER_EPOCH, "Incomplete UJI training rows")
    pools = {
        label: _CyclingPool(label, [i for i, row in enumerate(rows)
                                  if row["source"] == "hwrt" and row["label"] == label])
        for label in NOVEL_LABELS
    }
    multiplicity = np.zeros(len(rows), dtype=np.int64)
    epochs: list[dict] = []
    schedule_digest = hashlib.sha256()
    for epoch in range(1, EPOCHS + 1):
        selected = list(old)
        selected_by_label = {}
        for label in NOVEL_LABELS:
            values = pools[label].draw(NOVEL_EXPOSURES_PER_LABEL_PER_EPOCH)
            selected.extend(values)
            selected_by_label[label] = values
        _require(len(selected) == EXPOSURES_PER_EPOCH, "Epoch exposure count changed")
        generator = np.random.default_rng(_derived_seed("epoch-permutation", epoch))
        positions = generator.permutation(len(selected))
        ordered = [selected[int(position)] for position in positions]
        index_bytes = np.asarray(ordered, dtype="<i8").tobytes()
        _stream_update(schedule_digest, index_bytes)
        for index in ordered:
            multiplicity[index] += 1
        counts = {label: 0 for label in vocabulary}
        for index in ordered:
            counts[rows[index]["label"]] += 1
        _require(all(counts[label] == 64 for label in vocabulary), "Epoch is not exactly 64 exposures per label")
        epochs.append({
            "epoch": epoch,
            "rowIndices": ordered,
            "permutationSHA256": _sha256(index_bytes),
            "novelDrawSHA256": {
                label: _sha256(np.asarray(selected_by_label[label], dtype="<i8").tobytes())
                for label in NOVEL_LABELS
            },
            "exposures": EXPOSURES_PER_EPOCH,
            "updates": UPDATES_PER_EPOCH,
        })
    old_counts = multiplicity[old]
    _require(bool(np.all(old_counts == EPOCHS)), "Old UJI rows must occur exactly once each epoch")
    coverage = {}
    for label, pool in pools.items():
        indexes = pool.values
        counts = multiplicity[indexes]
        coverage[label] = {
            "availableRows": len(indexes),
            "uniqueRowsSeen": int(np.count_nonzero(counts)),
            "exposures": int(counts.sum()),
            "minimumMultiplicity": int(counts.min()),
            "maximumMultiplicity": int(counts.max()),
            "shuffleCount": pool.shuffle_count,
        }
        _require(coverage[label]["uniqueRowsSeen"] == len(indexes)
                 and coverage[label]["exposures"] == EPOCHS * NOVEL_EXPOSURES_PER_LABEL_PER_EPOCH,
                 "Novel class pool coverage changed")
    return {
        "version": PLAN_VERSION,
        "vocabulary": list(vocabulary),
        "vocabularySHA256": _vocabulary_sha256(vocabulary),
        "recipe": RECIPE,
        "optimization": OPTIMIZATION,
        "trainingRows": len(rows),
        "epochs": epochs,
        "scheduleSHA256": schedule_digest.hexdigest(),
        "novelPoolCoverage": coverage,
        "rowMultiplicitySHA256": _sha256(multiplicity.astype("<i8", copy=False).tobytes()),
        "oldRowMultiplicity": {"minimum": int(old_counts.min()), "maximum": int(old_counts.max())},
    }


def initialized_models() -> tuple[dict[str, field.PersonalStrokeFieldEncoder], str]:
    """Create one seed-29 state and deep-copy it into both fixed arms."""

    before = torch.get_rng_state().clone()
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(SEED)
        original = field.PersonalStrokeFieldEncoder(LABEL_COUNT, ARMS[0])
    models = {arm: copy.deepcopy(original) for arm in ARMS}
    for arm, model in models.items():
        model.arm = arm
    _require(torch.equal(before, torch.get_rng_state()), "Initialization changed global Torch RNG")
    digests = {_state_digest(model.state_dict()) for model in models.values()}
    _require(len(digests) == 1, "Matched arms did not receive identical complete state")
    return models, digests.pop()


def _optimizers(models: dict[str, field.PersonalStrokeFieldEncoder]):
    optimizers = {
        arm: torch.optim.AdamW(model.parameters(), lr=0.001, weight_decay=0.0001)
        for arm, model in models.items()
    }
    schedulers = {
        arm: torch.optim.lr_scheduler.CosineAnnealingLR(optimizers[arm], T_max=EPOCHS)
        for arm in ARMS
    }
    return optimizers, schedulers


def _paired_step(
    models: dict[str, field.PersonalStrokeFieldEncoder],
    optimizers: dict[str, torch.optim.Optimizer],
    augmented: torch.Tensor,
    targets: torch.Tensor,
) -> dict[str, dict[str, object]]:
    """Apply one matched real gradient update to both arms."""

    _require(augmented.dtype == torch.float32 and augmented.shape[1:] == (5, 96, 256)
             and targets.dtype == torch.long and targets.shape == (len(augmented),),
             "Malformed paired training batch")
    input_sha = _tensor_sha256(augmented)
    reports = {}
    for arm in ARMS:
        model = models[arm]
        _require(model.arm == arm, "Model/arm mask mismatch")
        model.train()
        optimizers[arm].zero_grad(set_to_none=True)
        calls: list[str] = []

        def hook(_module, args):
            calls.append(_tensor_sha256(args[0]))

        handle = model.register_forward_pre_hook(hook)
        try:
            _embedding, logits = model(augmented)
        finally:
            handle.remove()
        _require(calls == [input_sha], "Arm did not receive the exact shared augmented tensor")
        _require(logits.shape == (len(augmented), LABEL_COUNT), "Classifier output shape changed")
        loss = F.cross_entropy(logits, targets)
        _require(bool(torch.isfinite(loss)), "Nonfinite training loss")
        loss.backward()
        _require(all(parameter.grad is not None and bool(torch.isfinite(parameter.grad).all())
                     for parameter in model.parameters()), "Missing or nonfinite training gradient")
        optimizers[arm].step()
        _require(all(bool(torch.isfinite(tensor).all()) for tensor in model.state_dict().values()
                     if tensor.is_floating_point()), "Nonfinite updated model state")
        reports[arm] = {
            "loss": float(loss.detach()),
            "correct": int((logits.detach().argmax(1) == targets).sum()),
            "actualInputSHA256": calls[0],
        }
    _require(len({reports[arm]["actualInputSHA256"] for arm in ARMS}) == 1,
             "Matched arms received different bytes")
    return reports


def train_models(
    models: dict[str, field.PersonalStrokeFieldEncoder],
    fields: np.ndarray,
    rows: list[dict],
    vocabulary: tuple[str, ...],
    plan: dict,
) -> tuple[dict[str, list[dict]], dict[str, dict]]:
    """Execute the frozen 30x51 paired schedule, final epoch only."""

    _require(plan["version"] == PLAN_VERSION and len(plan["epochs"]) == EPOCHS,
             "Frozen training plan changed")
    optimizers, schedulers = _optimizers(models)
    label_index = {label: index for index, label in enumerate(vocabulary)}
    augmentation_generator = torch.Generator(device="cpu").manual_seed(SEED)
    histories = {arm: [] for arm in ARMS}
    draw_digest = hashlib.sha256()
    augmented_digest = hashlib.sha256()
    actual_digests = {arm: hashlib.sha256() for arm in ARMS}
    order_digest = hashlib.sha256()
    total_updates = 0
    for epoch in plan["epochs"]:
        order = epoch["rowIndices"]
        order_bytes = np.asarray(order, dtype="<i8").tobytes()
        _require(_sha256(order_bytes) == epoch["permutationSHA256"], "Epoch order changed")
        _stream_update(order_digest, order_bytes)
        aggregates = {arm: {"loss": 0.0, "correct": 0} for arm in ARMS}
        for offset in range(0, len(order), BATCH_SIZE):
            indexes = order[offset:offset + BATCH_SIZE]
            _require(len(indexes) == BATCH_SIZE, "Partial batch is forbidden by fixed recipe")
            source = torch.from_numpy(np.array(fields[indexes], dtype=np.float32, copy=True, order="C"))
            source_before = _tensor_sha256(source)
            draws = field.sample_affine_draws(BATCH_SIZE, augmentation_generator)
            _stream_update(draw_digest, _tensor_bytes(draws))
            augmented = field.augment_stroke_fields(source, draws)
            _require(_tensor_sha256(source) == source_before, "Augmentation mutated prepared source fields")
            augmented_bytes = _tensor_bytes(augmented)
            _stream_update(augmented_digest, augmented_bytes)
            targets = torch.tensor([label_index[rows[index]["label"]] for index in indexes], dtype=torch.long)
            reports = _paired_step(models, optimizers, augmented, targets)
            for arm in ARMS:
                _stream_update(actual_digests[arm], augmented_bytes)
                aggregates[arm]["loss"] += reports[arm]["loss"] * len(indexes)
                aggregates[arm]["correct"] += reports[arm]["correct"]
            total_updates += 1
        for arm in ARMS:
            schedulers[arm].step()
            histories[arm].append({
                "epoch": epoch["epoch"],
                "meanLoss": aggregates[arm]["loss"] / EXPOSURES_PER_EPOCH,
                "correct": aggregates[arm]["correct"],
                "learningRate": float(schedulers[arm].get_last_lr()[0]),
            })
        print(canonical_json_bytes({
            "epoch": epoch["epoch"],
            "cumulativeUpdatesPerArm": total_updates,
            "cumulativeExposuresPerArm": epoch["epoch"] * EXPOSURES_PER_EPOCH,
            "arms": {
                arm: {
                    "meanTrainingLoss": histories[arm][-1]["meanLoss"],
                    "trainingCorrect": histories[arm][-1]["correct"],
                }
                for arm in ARMS
            },
        }).decode("utf-8"), flush=True)
    _require(total_updates == UPDATES_PER_ARM, "Fixed update count changed")
    actual = {arm: actual_digests[arm].hexdigest() for arm in ARMS}
    _require(len(set(actual.values())) == 1 and next(iter(actual.values())) == augmented_digest.hexdigest(),
             "Actual arm input streams differ from the shared augmented stream")
    ledger = {
        arm: {
            "epochs": EPOCHS,
            "updates": total_updates,
            "exposures": EXPOSURES_PER_ARM,
            "scheduleSHA256": plan["scheduleSHA256"],
            "batchOrderStreamSHA256": order_digest.hexdigest(),
            "augmentationDrawStreamSHA256": draw_digest.hexdigest(),
            "augmentedFeatureStreamSHA256": augmented_digest.hexdigest(),
            "actualForwardInputStreamSHA256": actual[arm],
        }
        for arm in ARMS
    }
    _require(ledger[ARMS[0]] == ledger[ARMS[1]], "Matched arm ledgers differ")
    return histories, ledger


def checkpoint_bytes(model: field.PersonalStrokeFieldEncoder, arm: str, vocabulary_sha256: str) -> bytes:
    _require(arm in ARMS and model.arm == arm and model.label_count == LABEL_COUNT,
             "Checkpoint arm/label contract changed")
    _require(_digest(vocabulary_sha256), "Checkpoint vocabulary digest invalid")
    buffer = io.BytesIO()
    torch.save({
        "version": VERSION,
        "arm": arm,
        "fieldVersion": field.VERSION,
        "modelVersion": field.MODEL_VERSION,
        "labelCount": LABEL_COUNT,
        "vocabularySHA256": vocabulary_sha256,
        "stateDict": model.state_dict(),
    }, buffer)
    return buffer.getvalue()


def load_checkpoint(payload: bytes, arm: str, vocabulary_sha256: str) -> field.PersonalStrokeFieldEncoder:
    try:
        value = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
    except Exception as error:
        raise ValueError("Invalid checkpoint") from error
    _require(isinstance(value, dict) and set(value) == {
        "version", "arm", "fieldVersion", "modelVersion", "labelCount", "vocabularySHA256", "stateDict"
    }, "Checkpoint schema changed")
    _require(value["version"] == VERSION and value["arm"] == arm and arm in ARMS
             and value["fieldVersion"] == field.VERSION and value["modelVersion"] == field.MODEL_VERSION
             and value["labelCount"] == LABEL_COUNT and value["vocabularySHA256"] == vocabulary_sha256
             and isinstance(value["stateDict"], dict), "Checkpoint identity changed")
    model = field.PersonalStrokeFieldEncoder(LABEL_COUNT, arm)
    try:
        model.load_state_dict(value["stateDict"], strict=True)
    except (RuntimeError, ValueError) as error:
        raise ValueError("Checkpoint state changed") from error
    _require(all(bool(torch.isfinite(tensor).all()) for tensor in model.state_dict().values()
                 if tensor.is_floating_point()), "Nonfinite checkpoint tensor")
    return model


FIT_RECEIPT_FIELDS = {
    "version", "scope", "arms", "fieldVersion", "modelVersion", "labelCount", "vocabulary",
    "vocabularySHA256", "protocolSHA256", "codeSHA256", "dataReceiptSHA256",
    "dataArtifactsSHA256", "runtime", "recipe", "initialStateSHA256", "initialArmStateSHA256",
    "trainingPlanPath", "trainingPlanSHA256", "augmentationLedger", "trainingHistory",
    "weightFiles", "weightsSHA256", "finalStateSHA256", "selection",
}


def _validate_fit_receipt(receipt: dict, *, code: dict[str, str] | None = None) -> None:
    _require(isinstance(receipt, dict) and set(receipt) == FIT_RECEIPT_FIELDS, "Fit receipt schema changed")
    _require(receipt["version"] == VERSION and receipt["scope"] == SCOPE
             and receipt["arms"] == list(ARMS) and receipt["fieldVersion"] == field.VERSION
             and receipt["modelVersion"] == field.MODEL_VERSION and receipt["labelCount"] == LABEL_COUNT,
             "Fit receipt identity changed")
    vocabulary = receipt["vocabulary"]
    _require(isinstance(vocabulary, list) and len(vocabulary) == LABEL_COUNT
             and _vocabulary_sha256(vocabulary) == receipt["vocabularySHA256"],
             "Fit receipt vocabulary changed")
    _require(receipt["protocolSHA256"] == PROTOCOL_SHA256 and receipt["recipe"] == RECIPE
             and receipt["selection"] == "final-epoch-only", "Fit recipe/protocol changed")
    if code is not None:
        _require(receipt["codeSHA256"] == code, "Fit code bindings changed")
    _require(_digest(receipt["dataReceiptSHA256"])
             and isinstance(receipt["dataArtifactsSHA256"], dict)
             and receipt["dataArtifactsSHA256"]
             and all(isinstance(name, str) and _digest(value)
                     for name, value in receipt["dataArtifactsSHA256"].items())
             and receipt["weightFiles"] == {arm: f"weights/{arm}.pt" for arm in ARMS}
             and set(receipt["weightsSHA256"]) == set(ARMS)
             and all(_digest(value) for value in receipt["weightsSHA256"].values()),
             "Fit artifact bindings changed")
    _require(receipt["initialArmStateSHA256"] == {arm: receipt["initialStateSHA256"] for arm in ARMS}
             and _digest(receipt["initialStateSHA256"]), "Initial matched state changed")
    _require(set(receipt["finalStateSHA256"]) == set(ARMS)
             and all(_digest(value) and value != receipt["initialStateSHA256"]
                     for value in receipt["finalStateSHA256"].values()),
             "Final state identity changed or remained initial")
    _require(receipt["trainingPlanPath"] == "training-plan.json"
             and _digest(receipt["trainingPlanSHA256"]), "Training plan binding changed")
    expected_ledger_fields = {
        "epochs", "updates", "exposures", "scheduleSHA256", "batchOrderStreamSHA256",
        "augmentationDrawStreamSHA256", "augmentedFeatureStreamSHA256", "actualForwardInputStreamSHA256",
    }
    _require(set(receipt["augmentationLedger"]) == set(ARMS), "Matched augmentation arms missing")
    for arm in ARMS:
        ledger = receipt["augmentationLedger"][arm]
        _require(isinstance(ledger, dict) and set(ledger) == expected_ledger_fields
                 and (ledger["epochs"], ledger["updates"], ledger["exposures"])
                 == (EPOCHS, UPDATES_PER_ARM, EXPOSURES_PER_ARM)
                 and all(_digest(ledger[name]) for name in expected_ledger_fields
                         - {"epochs", "updates", "exposures"})
                 and ledger["augmentedFeatureStreamSHA256"] == ledger["actualForwardInputStreamSHA256"],
                 "Incomplete or inconsistent augmentation ledger")
    _require(receipt["augmentationLedger"][ARMS[0]] == receipt["augmentationLedger"][ARMS[1]],
             "Matched augmentation ledgers differ")
    _require(set(receipt["trainingHistory"]) == set(ARMS), "Training history arms missing")
    for arm in ARMS:
        history = receipt["trainingHistory"][arm]
        _require(isinstance(history, list) and len(history) == EPOCHS, "Training history incomplete")
        for epoch, row in enumerate(history, start=1):
            _require(isinstance(row, dict) and set(row) == {"epoch", "meanLoss", "correct", "learningRate"}
                     and row["epoch"] == epoch and type(row["correct"]) is int
                     and 0 <= row["correct"] <= EXPOSURES_PER_EPOCH
                     and all(isinstance(row[name], (int, float)) and not isinstance(row[name], bool)
                             and np.isfinite(row[name]) and row[name] >= 0
                             for name in ("meanLoss", "learningRate")), "Malformed training history")


def _snapshot_data(directory: Path, receipt: dict, receipt_bytes: bytes) -> dict[Path, str]:
    artifacts = receipt.get("artifacts")
    _require(isinstance(artifacts, dict) and artifacts, "Data receipt artifact map missing")
    snapshot = {directory / "data-receipt.json": _sha256(receipt_bytes)}
    # Never open development inputs or truth while fitting.  Their hashes may
    # be transitively bound by the source-only receipt, but only these two
    # training artifacts are read and rehashed here.
    _require({"fields.npy", "training.json"} <= set(artifacts), "Training artifacts missing")
    for name in ("fields.npy", "training.json"):
        identity = artifacts[name]
        _require(isinstance(identity, dict) and set(identity) == {"bytes", "sha256"}
                 and type(identity["bytes"]) is int and identity["bytes"] > 0
                 and _digest(identity["sha256"]), "Data artifact identity changed")
        path = _regular(directory / name, maximum=8 * 1024 * 1024 * 1024)
        payload_hash = _file_sha256(path)
        _require(path.stat().st_size == identity["bytes"] and payload_hash == identity["sha256"],
                 "Data artifact differs from receipt")
        snapshot[path] = payload_hash
    return snapshot


def _preserved(code: dict[str, str], snapshot: dict[Path, str]) -> None:
    _require(code_identity() == code, "Bound source/protocol changed during fit")
    for path, expected in snapshot.items():
        _require(_file_sha256(path) == expected, "Bound data artifact changed during fit")


def _copy_code_snapshot(output: Path, code: dict[str, str]) -> None:
    for relative, expected in code.items():
        payload = _read(ROOT / relative, maximum=32 * 1024 * 1024)
        _require(_sha256(payload) == expected, "Code changed before snapshot")
        _write_exclusive(output / "executed-code" / relative, payload)


def fit(data_directory: Path, protocol: Path, output: Path) -> None:
    """Run the one fixed matched fit.  The success receipt is written last."""

    data_directory = Path(data_directory)
    _require(data_directory.is_absolute() and data_directory.resolve() == data_directory
             and data_directory.is_dir() and not data_directory.is_symlink(), "Canonical data directory required")
    protocol = _regular(Path(protocol), maximum=2 * 1024 * 1024)
    protocol_bytes = protocol.read_bytes()
    _require(_sha256(protocol_bytes) == PROTOCOL_SHA256
             and protocol_bytes == _read(ROOT / PROTOCOL, maximum=2 * 1024 * 1024),
             "Caller protocol differs from frozen repository protocol")
    torch.set_num_threads(CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    code = code_identity()

    receipt_bytes = _read(data_directory / "data-receipt.json", maximum=16 * 1024 * 1024)
    parsed_receipt = _parsed(receipt_bytes, name="data-receipt.json")
    fields, metadata, data_receipt = data.load_training(data_directory)
    _require(data_receipt == parsed_receipt, "Data loader receipt differs from bound bytes")
    rows, vocabulary = _validate_training_bundle(fields, metadata, data_receipt)
    snapshot = _snapshot_data(data_directory, data_receipt, receipt_bytes)
    data_receipt_sha = _sha256(receipt_bytes)
    data_artifacts = {name: value["sha256"] for name, value in data_receipt["artifacts"].items()}
    plan = build_training_plan(rows, vocabulary)
    plan.update({
        "protocolSHA256": PROTOCOL_SHA256,
        "codeSHA256": code,
        "dataReceiptSHA256": data_receipt_sha,
        "dataArtifactsSHA256": data_artifacts,
        "metadataSHA256": data_receipt["artifacts"]["training.json"]["sha256"],
    })
    plan_bytes = canonical_json_bytes(plan)
    models, initial_sha = initialized_models()
    output = _fresh_directory(Path(output))
    (output / "weights").mkdir(mode=0o700)
    _write_exclusive(output / "frozen-protocol.md", protocol_bytes)
    _copy_code_snapshot(output, code)
    _write_exclusive(output / "training-plan.json", plan_bytes)

    histories, ledgers = train_models(models, fields, rows, vocabulary, plan)
    weights_sha: dict[str, str] = {}
    final_sha: dict[str, str] = {}
    for arm in ARMS:
        payload = checkpoint_bytes(models[arm], arm, plan["vocabularySHA256"])
        restored = load_checkpoint(payload, arm, plan["vocabularySHA256"])
        expected = _state_digest(models[arm].state_dict())
        _require(_state_digest(restored.state_dict()) == expected, "Checkpoint reload changed final tensors")
        _write_exclusive(output / "weights" / f"{arm}.pt", payload)
        weights_sha[arm] = _sha256(payload)
        final_sha[arm] = expected
    _require(all(value != initial_sha for value in final_sha.values()), "Training did not change complete model state")
    _preserved(code, snapshot)

    receipt = {
        "version": VERSION,
        "scope": SCOPE,
        "arms": list(ARMS),
        "fieldVersion": field.VERSION,
        "modelVersion": field.MODEL_VERSION,
        "labelCount": LABEL_COUNT,
        "vocabulary": list(vocabulary),
        "vocabularySHA256": plan["vocabularySHA256"],
        "protocolSHA256": PROTOCOL_SHA256,
        "codeSHA256": code,
        "dataReceiptSHA256": data_receipt_sha,
        "dataArtifactsSHA256": data_artifacts,
        "runtime": _runtime_contract(),
        "recipe": RECIPE,
        "initialStateSHA256": initial_sha,
        "initialArmStateSHA256": {arm: initial_sha for arm in ARMS},
        "trainingPlanPath": "training-plan.json",
        "trainingPlanSHA256": _sha256(plan_bytes),
        "augmentationLedger": ledgers,
        "trainingHistory": histories,
        "weightFiles": {arm: f"weights/{arm}.pt" for arm in ARMS},
        "weightsSHA256": weights_sha,
        "finalStateSHA256": final_sha,
        "selection": "final-epoch-only",
    }
    _validate_fit_receipt(receipt, code=code)
    _write_exclusive(output / "fit-receipt.json", canonical_json_bytes(receipt))


def load_fitted_models(directory: Path, expected_receipt_sha256: str):
    """Load only final CPU-eval models and their fully validated receipt."""

    _require(_digest(expected_receipt_sha256), "Caller-pinned fit receipt SHA-256 required")
    torch.set_num_threads(CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    directory = Path(directory)
    _require(directory.is_absolute() and directory.resolve() == directory
             and directory.is_dir() and not directory.is_symlink(), "Canonical fit directory required")
    receipt_bytes = _read(directory / "fit-receipt.json", maximum=32 * 1024 * 1024)
    _require(_sha256(receipt_bytes) == expected_receipt_sha256, "Fit receipt SHA-256 changed")
    receipt = _parsed(receipt_bytes, name="fit-receipt.json")
    code = code_identity()
    _validate_fit_receipt(receipt, code=code)
    _require(receipt["runtime"] == _runtime_contract(), "Fit/runtime contract changed")
    _require(_sha256(_read(directory / "frozen-protocol.md", maximum=2 * 1024 * 1024)) == PROTOCOL_SHA256,
             "Fit protocol snapshot changed")
    _require(_sha256(_read(directory / receipt["trainingPlanPath"], maximum=64 * 1024 * 1024))
             == receipt["trainingPlanSHA256"], "Training plan changed")
    for relative, expected in code.items():
        _require(_sha256(_read(directory / "executed-code" / relative, maximum=32 * 1024 * 1024)) == expected,
                 "Executed source snapshot changed")
    models = {}
    for arm in ARMS:
        payload = _read(directory / receipt["weightFiles"][arm], maximum=256 * 1024 * 1024)
        _require(_sha256(payload) == receipt["weightsSHA256"][arm], "Checkpoint bytes changed")
        model = load_checkpoint(payload, arm, receipt["vocabularySHA256"])
        _require(_state_digest(model.state_dict()) == receipt["finalStateSHA256"][arm],
                 "Checkpoint tensor identity changed")
        model.eval()
        models[arm] = model
    return models, receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    fit(arguments.data, arguments.protocol, arguments.output)


if __name__ == "__main__":
    main()

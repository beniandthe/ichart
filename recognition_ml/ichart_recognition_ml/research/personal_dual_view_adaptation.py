"""One frozen matched continuation fit through the existing residual learner.

Research only.  Fit uses the 32 public training writers; prediction uses only
the eight already-observed development writers after both final checkpoints
exist.  Scoring opens query truth only after validating the complete blind
prediction packet and recomputing every generic and residual rank.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import math
import platform
import stat
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import torch
from torch.nn import functional as F

from ..contracts import canonical_json_bytes, strict_json_loads
from ..features import encode_trajectory, rasterize
from . import personal_dual_view as dual
from . import personal_dual_view_scoring as metrics
from .personal_adaptability import adapted_scores, sparse_labels
from .personal_residual import ResidualHead, normalized_scores
from .uji_personal import SOURCE_SHA256, Sample, parse_source, split_writers, trajectory_fingerprint


VERSION = "personal-dual-adaptation-v1"
PLAN_VERSION = "personal-dual-adaptation-episode-plan-v1"
FIT_VERSION = "personal-dual-adaptation-fit-v1"
PREDICTION_VERSION = "personal-dual-adaptation-predictions-v1"
SCORE_VERSION = "personal-dual-adaptation-score-v1"
SCOPE = "public-uji-observed-development-adaptation-aware-research-not-production"
ARMS = ("genericControl", "adaptationAware")
PROTOCOL_PATH = "docs/personal-dual-view-adaptation-training-protocol-2026-09-30.md"
MODULE_PATH = "recognition_ml/ichart_recognition_ml/research/personal_dual_view_adaptation.py"
TEST_PATH = "recognition_ml/tests/test_personal_dual_view_adaptation.py"
ADAPTABILITY_PATH = "recognition_ml/ichart_recognition_ml/research/personal_adaptability.py"
RESIDUAL_PATH = "recognition_ml/ichart_recognition_ml/research/personal_residual.py"
SWIFT_RESIDUAL_PATH = "iChart/Recognition/PersonalInkResidualHead.swift"
CODE_PATHS = tuple(dict.fromkeys(dual.CODE_PATHS + (
    ADAPTABILITY_PATH, RESIDUAL_PATH, SWIFT_RESIDUAL_PATH,
    PROTOCOL_PATH, MODULE_PATH, TEST_PATH,
)))

PARENT_FIT_SHA256 = "ce60efb539ce4d0897e0c339e6d1e1d90485ec07798aa1da499047482724a46f"
PARENT_DUAL_WEIGHT_SHA256 = "ed722707ad992b6c282dd6f416ac173bc972c7517b1804d72c08f57cbf1a1507"
VOCABULARY_SHA256 = "2fc83d80121b8177598f563b7253ee6bb8de2a38e45fbd825bb2e656c52cfb59"
SEED = 29
EPOCHS = 10
SUPPORT_COUNT = 16
REGULARIZATION = 0.1
LEARNING_RATE = 0.0001
WEIGHT_DECAY = 0.0001
CPU_THREADS = 4
TRAINING_SAMPLE_COUNT = 6_208
DEVELOPMENT_SAMPLE_COUNT = 1_552
QUERY_COUNT = 776
VOCABULARY_SIZE = 97
EMBEDDING_SIZE = 128
FIT_RECEIPT_NAME = "fit-receipt.json"
PLAN_NAME = "episode-plan.json"
FROZEN_PROTOCOL_NAME = "frozen-protocol.md"
PREDICTION_NAME = "predictions.json"
PREDICTION_RECEIPT_NAME = "prediction-receipt.json"
SPARSE_LABELS = ("!", "E", "F", "L", "T", "Z", "d", "g", "j", "k", "n", "t", "w", "x", "Ó", "á")
HASH_FIELDS = {"normalizedTrajectorySHA256", "rasterSHA256", "trajectorySHA256"}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _root() -> Path:
    return Path(__file__).resolve().parents[3]


def _keys(value, expected, name):
    if not isinstance(value, dict) or set(value) != set(expected):
        raise ValueError(f"{name}: missing or unknown fields")
    return value


def _digest(value) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def _file(path: Path, name: str = "input") -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.is_symlink()
            or path.resolve(strict=True) != path or not stat.S_ISREG(path.stat().st_mode)):
        raise ValueError(f"{name} must be an absolute unaliased regular file")
    return path


def _directory(path: Path, name: str = "input directory") -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.is_symlink()
            or path.resolve(strict=True) != path or not stat.S_ISDIR(path.stat().st_mode)):
        raise ValueError(f"{name} must be an absolute unaliased directory")
    return path


def _new_directory(path: Path) -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.exists() or path.is_symlink()
            or path.parent.resolve(strict=True) != path.parent):
        raise ValueError("Output must be a new exclusive canonical directory")
    path.mkdir(mode=0o700)
    return path


def _write(path: Path, payload: bytes) -> None:
    with path.open("xb") as handle:
        handle.write(payload)


def _json(payload: bytes, name: str) -> dict:
    try:
        value = strict_json_loads(payload.decode("utf-8"), name)
    except Exception as error:
        raise ValueError(f"{name}: invalid JSON bytes") from error
    if not isinstance(value, dict) or canonical_json_bytes(value) != payload:
        raise ValueError(f"{name}: not a canonical JSON object")
    return value


def code_identity() -> dict[str, str]:
    result = {}
    for relative in CODE_PATHS:
        path = _file(_root() / relative, f"code dependency {relative}")
        result[relative] = sha256(path.read_bytes())
    return result


def _runtime() -> dict[str, object]:
    return {
        "cpuThreads": CPU_THREADS,
        "deterministicAlgorithms": True,
        "numpy": str(np.__version__),
        "platform": platform.platform(),
        "python": platform.python_version(),
        "torch": str(torch.__version__),
    }


def _configure_runtime() -> None:
    torch.set_num_threads(CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED)
    np.random.seed(SEED)


def _snapshot_bytes(files: Mapping[Path, bytes]) -> dict[Path, str]:
    """Bind the exact bytes already consumed, never a later baseline re-read."""
    if not files or any(not isinstance(payload, bytes) for payload in files.values()):
        raise ValueError("Snapshot requires exact nonempty byte captures")
    return {path: sha256(payload) for path, payload in files.items()}


def _preserved(snapshot: Mapping[Path, str], code: Mapping[str, str]) -> None:
    if code_identity() != dict(code) or any(sha256(path.read_bytes()) != digest for path, digest in snapshot.items()):
        raise ValueError("Frozen source, protocol, parent, model, or code changed during operation")


def _feature_hashes(sample: Sample) -> dict[str, str]:
    return {
        "normalizedTrajectorySHA256": trajectory_fingerprint(sample),
        "rasterSHA256": sha256(rasterize(sample.strokes).pixels),
        "trajectorySHA256": sha256(encode_trajectory(sample.strokes).to_bytes()),
    }


def _load_source_bytes(source_bytes: bytes) -> tuple[Sample, ...]:
    """Validate and parse only the exact source bytes captured by the caller."""
    if sha256(source_bytes) != SOURCE_SHA256:
        raise ValueError("Source digest does not match the frozen public dataset")
    try:
        records = parse_source(source_bytes.decode("utf-8"))
    except UnicodeDecodeError as error:
        raise ValueError("Public source is not UTF-8") from error
    writers = {record.writer for record in records}
    labels = {record.label for record in records}
    if len(records) != 11_640 or len(writers) != 60 or len(labels) != VOCABULARY_SIZE:
        raise ValueError("Incomplete public dataset")
    for writer in writers:
        for session in (1, 2):
            if {record.label for record in records if record.writer == writer and record.session == session} != labels:
                raise ValueError("Incomplete writer/session")
    split_writers(records)
    return records


def opaque_id(source_ordinal: int, writer: str, session: int) -> str:
    """Answer-independent row identity fixed by immutable global source position."""
    if (type(source_ordinal) is not int or source_ordinal < 0 or not isinstance(writer, str)
            or not writer.startswith("trn_") or session not in (1, 2)):
        raise ValueError("Invalid source ordinal or role")
    return sha256(
        b"personal-dual-adaptation-v1\0" + SOURCE_SHA256.encode("ascii") + b"\0"
        + str(source_ordinal).encode("ascii") + b"\0" + writer.encode("utf-8")
        + b"\0" + str(session).encode("ascii")
    )


def development_projection(records: Sequence[Sample], writers: Sequence[str], *, expected_count=DEVELOPMENT_SAMPLE_COUNT):
    allowed = set(writers)
    if (len(allowed) != len(tuple(writers)) or any(not writer.startswith("trn_") for writer in allowed)
            or type(expected_count) is not int or expected_count < 1):
        raise ValueError("Invalid development projection role")
    projected = tuple((sample, ordinal, opaque_id(ordinal, sample.writer, sample.session))
                      for ordinal, sample in enumerate(records) if sample.writer in allowed)
    if len(projected) != expected_count or len({row[2] for row in projected}) != expected_count:
        raise ValueError("Development projection is incomplete or ambiguous")
    return tuple(sorted(projected, key=lambda row: (row[0].session, row[2])))


def support_permutation(vocabulary: Sequence[str]) -> tuple[str, ...]:
    vocabulary = tuple(vocabulary)
    if (len(vocabulary) != VOCABULARY_SIZE or len(set(vocabulary)) != VOCABULARY_SIZE
            or any(not isinstance(label, str) or len(label) != 1 for label in vocabulary)):
        raise ValueError("Expected complete 97-label vocabulary")
    return tuple(sorted(vocabulary, key=lambda label: sha256(
        f"personal-dual-adaptation-v1:training-support:{label}".encode("utf-8"))))


def support_window(vocabulary: Sequence[str], global_episode_index: int) -> tuple[str, ...]:
    if type(global_episode_index) is not int or global_episode_index < 0:
        raise ValueError("Invalid global episode index")
    ordered = support_permutation(vocabulary)
    start = SUPPORT_COUNT * global_episode_index % len(ordered)
    return tuple(ordered[(start + offset) % len(ordered)] for offset in range(SUPPORT_COUNT))


@dataclass(frozen=True)
class Episode:
    epoch: int
    global_index: int
    writer: str
    support_session: int
    support: tuple[int, ...]
    queries: tuple[int, ...]
    exclusions: tuple[tuple[int, tuple[str, ...]], ...]


def plan_episodes(
    samples: tuple[Sample, ...],
    writers: tuple[str, ...],
    vocabulary: tuple[str, ...],
    raster_hashes: Sequence[str],
    normalized_hashes: Sequence[str],
    *,
    epochs: int = EPOCHS,
) -> tuple[tuple[Episode, ...], dict[str, int]]:
    if (not samples or type(epochs) is not int or epochs < 1
            or len(samples) != len(raster_hashes) or len(samples) != len(normalized_hashes)
            or len(set(writers)) != len(writers) or any(not writer.startswith("trn_") for writer in writers)
            or any(sample.writer not in set(writers) for sample in samples)):
        raise ValueError("Wrong-role or incomplete episode source")
    support_permutation(vocabulary)
    lookup = {(sample.writer, sample.session, sample.label): index for index, sample in enumerate(samples)}
    required = {(writer, session, label) for writer in writers for session in (1, 2) for label in vocabulary}
    if len(lookup) != len(samples) or set(lookup) != required:
        raise ValueError("Missing or duplicate writer/session/label")
    if any(not _digest(value) for value in tuple(raster_hashes) + tuple(normalized_hashes)):
        raise ValueError("Invalid feature-copy hash")

    pairs = [(writer, session) for writer in sorted(writers) for session in (1, 2)]
    generator = torch.Generator(device="cpu").manual_seed(SEED)
    episodes: list[Episode] = []
    counts = Counter({label: 0 for label in vocabulary})
    global_index = 0
    for epoch in range(1, epochs + 1):
        # The global index is assigned after this seeded pair permutation and is
        # therefore exactly the index of the resulting training step.
        for pair_index in torch.randperm(len(pairs), generator=generator).tolist():
            writer, support_session = pairs[pair_index]
            labels = support_window(vocabulary, global_index)
            support = tuple(lookup[writer, support_session, label] for label in labels)
            support_rasters = {raster_hashes[index] for index in support}
            support_trajectories = {normalized_hashes[index] for index in support}
            queries, exclusions = [], []
            for label in vocabulary:
                index = lookup[writer, 3 - support_session, label]
                reasons = []
                if raster_hashes[index] in support_rasters:
                    reasons.append("support_raster_copy")
                if normalized_hashes[index] in support_trajectories:
                    reasons.append("support_normalized_trajectory_copy")
                if reasons:
                    exclusions.append((index, tuple(reasons)))
                else:
                    queries.append(index)
            if not queries:
                raise ValueError("All outer queries were excluded")
            counts.update(labels)
            episodes.append(Episode(epoch, global_index, writer, support_session, support,
                                    tuple(queries), tuple(exclusions)))
            global_index += 1
    if len(episodes) != epochs * len(writers) * 2 or max(counts.values()) - min(counts.values()) > 1:
        raise ValueError("Episode plan is incomplete or support counts are imbalanced")
    return tuple(episodes), dict(sorted(counts.items()))


def episode_manifest(episodes: Sequence[Episode], samples: Sequence[Sample], sample_hashes: Sequence[dict[str, str]],
                     support_counts: Mapping[str, int], vocabulary: Sequence[str],
                     code: Mapping[str, str], protocol_sha: str) -> dict:
    if len(samples) != len(sample_hashes):
        raise ValueError("Source rows and feature hashes differ")
    source_rows = [{"inputHashes": dict(sample_hashes[index]), "label": sample.label,
                    "session": sample.session, "sourceID": sample.identity, "writer": sample.writer}
                   for index, sample in enumerate(samples)]
    source_rows.sort(key=lambda row: row["sourceID"])
    entries = []
    for episode in episodes:
        entries.append({
            "epoch": episode.epoch,
            "excludedQueries": [{"reasons": list(reasons), "sourceID": samples[index].identity}
                                for index, reasons in episode.exclusions],
            "globalEpisodeIndex": episode.global_index,
            "querySourceIDs": [samples[index].identity for index in episode.queries],
            "querySession": 3 - episode.support_session,
            "supportLabels": [samples[index].label for index in episode.support],
            "supportSession": episode.support_session,
            "supportSourceIDs": [samples[index].identity for index in episode.support],
            "writer": episode.writer,
        })
    query_counts = {str(epoch): sum(len(episode.queries) for episode in episodes if episode.epoch == epoch)
                    for epoch in range(1, EPOCHS + 1)}
    return {
        "codeSHA256": dict(code),
        "episodeCount": len(entries),
        "episodes": entries,
        "epochs": EPOCHS,
        "protocolSHA256": protocol_sha,
        "queryCountsPerEpoch": query_counts,
        "seed": SEED,
        "sourceSHA256": SOURCE_SHA256,
        "sourceRows": source_rows,
        "supportCountPerEpisode": SUPPORT_COUNT,
        "supportCounts": dict(support_counts),
        "supportPermutation": list(support_permutation(vocabulary)),
        "trainingWriters": sorted({sample.writer for sample in samples}),
        "version": PLAN_VERSION,
        "vocabularySHA256": dual.vocabulary_digest(vocabulary),
    }


def validate_episode_manifest(value: object, *, code: Mapping[str, str], protocol_sha: str,
                              vocabulary: Sequence[str]) -> dict:
    value = _keys(value, {"codeSHA256", "episodeCount", "episodes", "epochs", "protocolSHA256",
                          "queryCountsPerEpoch", "seed", "sourceRows", "sourceSHA256",
                          "supportCountPerEpisode", "supportCounts", "supportPermutation",
                          "trainingWriters", "version", "vocabularySHA256"}, "episode plan")
    expected = {
        "codeSHA256": dict(code), "episodeCount": EPOCHS * 64, "epochs": EPOCHS,
        "protocolSHA256": protocol_sha, "seed": SEED, "sourceSHA256": SOURCE_SHA256,
        "supportCountPerEpisode": SUPPORT_COUNT, "supportPermutation": list(support_permutation(vocabulary)),
        "version": PLAN_VERSION, "vocabularySHA256": dual.vocabulary_digest(vocabulary),
    }
    if any(value.get(key) != item for key, item in expected.items()):
        raise ValueError("Episode-plan metadata changed")
    counts = value["supportCounts"]
    if (not isinstance(counts, dict) or set(counts) != set(vocabulary)
            or any(type(count) is not int or count < 0 for count in counts.values())
            or sum(counts.values()) != EPOCHS * 64 * SUPPORT_COUNT
            or max(counts.values()) - min(counts.values()) > 1):
        raise ValueError("Episode support counts are incomplete or unbalanced")
    writers = value["trainingWriters"]
    if (not isinstance(writers, list) or len(writers) != 32 or writers != sorted(set(writers))
            or any(not writer.startswith("trn_") for writer in writers)):
        raise ValueError("Episode training-writer role changed")
    source_rows = value["sourceRows"]
    if not isinstance(source_rows, list) or len(source_rows) != TRAINING_SAMPLE_COUNT:
        raise ValueError("Episode source-row coverage changed")
    source_lookup = {}
    for row in source_rows:
        _keys(row, {"inputHashes", "label", "session", "sourceID", "writer"}, "episode source row")
        if (row["writer"] not in writers or row["session"] not in (1, 2) or row["label"] not in vocabulary
                or row["sourceID"] != f'{row["writer"]}-{row["session"]}-{row["label"]}'
                or row["sourceID"] in source_lookup or set(row["inputHashes"]) != HASH_FIELDS
                or not all(_digest(item) for item in row["inputHashes"].values())):
            raise ValueError("Invalid episode source identity or feature hash")
        source_lookup[row["sourceID"]] = row
    expected_source_ids = {f"{writer}-{session}-{label}" for writer in writers
                           for session in (1, 2) for label in vocabulary}
    if set(source_lookup) != expected_source_ids or [row["sourceID"] for row in source_rows] != sorted(source_lookup):
        raise ValueError("Episode source rows are incomplete or unsorted")
    entries = value["episodes"]
    if not isinstance(entries, list) or len(entries) != EPOCHS * 64:
        raise ValueError("Episode plan has wrong size")
    seen_pairs = Counter()
    recomputed_query_counts = Counter()
    recomputed_support_counts = Counter()
    for index, row in enumerate(entries):
        _keys(row, {"epoch", "excludedQueries", "globalEpisodeIndex", "querySourceIDs", "querySession",
                    "supportLabels", "supportSession", "supportSourceIDs", "writer"}, "episode")
        if (row["globalEpisodeIndex"] != index or row["epoch"] != index // 64 + 1
                or not isinstance(row["writer"], str) or not row["writer"].startswith("trn_")
                or row["supportSession"] not in (1, 2) or row["querySession"] != 3 - row["supportSession"]
                or row["supportLabels"] != list(support_window(vocabulary, index))
                or not isinstance(row["supportSourceIDs"], list) or len(row["supportSourceIDs"]) != SUPPORT_COUNT
                or not isinstance(row["querySourceIDs"], list) or not row["querySourceIDs"]
                or len(set(row["supportSourceIDs"])) != SUPPORT_COUNT
                or set(row["supportSourceIDs"]) & set(row["querySourceIDs"])):
            raise ValueError("Episode roles, order, or support window changed")
        support_ids = row["supportSourceIDs"]
        expected_support = [f'{row["writer"]}-{row["supportSession"]}-{label}'
                            for label in row["supportLabels"]]
        if support_ids != expected_support:
            raise ValueError("Episode support source IDs do not match declared labels")
        recomputed_support_counts.update(row["supportLabels"])
        exclusions = row["excludedQueries"]
        if (not isinstance(exclusions, list) or any(
                not isinstance(item, dict) or set(item) != {"reasons", "sourceID"}
                or not isinstance(item["sourceID"], str)
                or not isinstance(item["reasons"], list) or not item["reasons"]
                or any(reason not in {"support_raster_copy", "support_normalized_trajectory_copy"}
                       for reason in item["reasons"])
                for item in exclusions)):
            raise ValueError("Invalid copy-exclusion receipt")
        excluded_ids = [item["sourceID"] for item in exclusions]
        query_ids = row["querySourceIDs"]
        expected_queries = [f'{row["writer"]}-{row["querySession"]}-{label}' for label in vocabulary]
        if (len(set(query_ids)) != len(query_ids) or len(set(excluded_ids)) != len(excluded_ids)
                or set(query_ids) & set(excluded_ids) or set(query_ids) | set(excluded_ids) != set(expected_queries)
                or any(source_id not in source_lookup for source_id in query_ids + excluded_ids)):
            raise ValueError("Episode query/exclusion partition is incomplete")
        support_rasters = {source_lookup[source_id]["inputHashes"]["rasterSHA256"] for source_id in support_ids}
        support_normalized = {source_lookup[source_id]["inputHashes"]["normalizedTrajectorySHA256"]
                              for source_id in support_ids}
        expected_exclusions = {}
        expected_query_order = []
        for source_id in expected_queries:
            hashes = source_lookup[source_id]["inputHashes"]
            reasons = []
            if hashes["rasterSHA256"] in support_rasters:
                reasons.append("support_raster_copy")
            if hashes["normalizedTrajectorySHA256"] in support_normalized:
                reasons.append("support_normalized_trajectory_copy")
            if reasons:
                expected_exclusions[source_id] = reasons
            else:
                expected_query_order.append(source_id)
        if query_ids != expected_query_order or {item["sourceID"]: item["reasons"] for item in exclusions} != expected_exclusions:
            raise ValueError("Episode copy exclusions do not match frozen input hashes")
        seen_pairs[row["writer"], row["supportSession"], row["epoch"]] += 1
        recomputed_query_counts[str(row["epoch"])] += len(query_ids)
    if set(row["writer"] for row in entries) != set(writers) or any(seen_pairs[writer, session, epoch] != 1
                                 for writer in writers for session in (1, 2) for epoch in range(1, EPOCHS + 1)):
        raise ValueError("Episode writer/session coverage changed")
    if value["queryCountsPerEpoch"] != {str(epoch): recomputed_query_counts[str(epoch)]
                                         for epoch in range(1, EPOCHS + 1)}:
        raise ValueError("Episode per-epoch query counts changed")
    if value["supportCounts"] != {label: recomputed_support_counts[label] for label in vocabulary}:
        raise ValueError("Episode per-label support counts changed")
    return value


def _bn_buffers(model: dual.PersonalDualViewEncoder) -> dict[str, torch.Tensor]:
    return {key: value.detach().clone() for key, value in model.state_dict().items()
            if "running_mean" in key or "running_var" in key or "num_batches_tracked" in key}


def _bn_hashes_from_state(state: Mapping[str, torch.Tensor]) -> dict[str, str]:
    values = {key: value.detach().cpu().contiguous() for key, value in state.items()
              if "running_mean" in key or "running_var" in key or "num_batches_tracked" in key}
    if not values:
        raise ValueError("Checkpoint has no BatchNorm state")
    return {key: sha256(value.numpy().tobytes(order="C")) for key, value in sorted(values.items())}


def episode_losses(model: dual.PersonalDualViewEncoder, batch: dual.FeatureBatch, targets: torch.Tensor,
                   episode: Episode, *, adaptation_aware: bool) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    indexes = list(episode.support + episode.queries)
    if not episode.support or not episode.queries or set(episode.support) & set(episode.queries):
        raise ValueError("Invalid support/query episode")
    embeddings, logits = model(batch.trajectory[indexes].float(), batch.raster[indexes].float() / 255.0)
    support_count = len(episode.support)
    query_logits = logits[support_count:]
    query_targets = targets[list(episode.queries)]
    generic = F.cross_entropy(query_logits, query_targets)
    if adaptation_aware:
        adjusted = adapted_scores(
            embeddings[:support_count].double(), logits[:support_count].double(),
            targets[list(episode.support)], embeddings[support_count:].double(), query_logits.double(),
        )
        second = F.cross_entropy(adjusted, query_targets)
    else:
        second = generic
    total = 0.5 * generic.double() + 0.5 * second.double()
    if any(not torch.isfinite(value) for value in (generic, second, total)):
        raise ValueError("Nonfinite episode loss")
    return total, generic, second


def train_arm(starting: dual.PersonalDualViewEncoder, arm: str, batch: dual.FeatureBatch,
              targets: torch.Tensor, episodes: Sequence[Episode], *, epochs: int = EPOCHS):
    if arm not in ARMS or starting.arm != "dual" or epochs < 1:
        raise ValueError("Wrong training arm or source model")
    model = copy.deepcopy(starting)
    model.eval()  # Freeze BatchNorm running statistics without freezing parameter gradients.
    before_bn = _bn_buffers(model)
    torch.manual_seed(SEED)
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    schedule = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    history = []
    for epoch in range(1, epochs + 1):
        selected = [episode for episode in episodes if episode.epoch == epoch]
        if not selected:
            raise ValueError("Missing training epoch episodes")
        losses, generic_losses, second_losses, query_count = [], [], [], 0
        for episode in selected:
            total, generic, second = episode_losses(
                model, batch, targets, episode, adaptation_aware=arm == "adaptationAware")
            optimizer.zero_grad(set_to_none=True)
            total.backward()
            if any(parameter.grad is not None and not torch.isfinite(parameter.grad).all()
                   for parameter in model.parameters()):
                raise ValueError("Nonfinite training gradient")
            optimizer.step()
            losses.append(float(total.detach()))
            generic_losses.append(float(generic.detach()))
            second_losses.append(float(second.detach()))
            query_count += len(episode.queries)
        schedule.step()
        row = {
            "episodeCount": len(selected), "epoch": epoch,
            "genericLoss": float(np.mean(generic_losses)), "loss": float(np.mean(losses)),
            "queryCount": query_count, "secondHalfLoss": float(np.mean(second_losses)),
        }
        history.append(row)
        print(canonical_json_bytes({"arm": arm, **row}).decode("utf-8"), flush=True)
    after_bn = _bn_buffers(model)
    if set(before_bn) != set(after_bn) or any(not torch.equal(before_bn[key], after_bn[key]) for key in before_bn):
        raise ValueError("BatchNorm running state changed during continuation")
    if any(not torch.isfinite(value).all() for value in model.state_dict().values() if value.is_floating_point()):
        raise ValueError("Final checkpoint contains nonfinite tensors")
    return model, history, _bn_hashes_from_state(before_bn)


def _checkpoint_bytes(model: dual.PersonalDualViewEncoder, training_arm: str,
                      vocabulary_sha: str, parent_weight_sha: str) -> bytes:
    if model.arm != "dual" or training_arm not in ARMS:
        raise ValueError("Checkpoint arm mismatch")
    buffer = io.BytesIO()
    torch.save({
        "architectureVersion": dual.ARCHITECTURE_VERSION,
        "modelArm": "dual",
        "parentWeightsSHA256": parent_weight_sha,
        "stateDict": model.state_dict(),
        "trainingArm": training_arm,
        "version": FIT_VERSION,
        "vocabularySHA256": vocabulary_sha,
    }, buffer)
    return buffer.getvalue()


def _load_checkpoint(payload: bytes, training_arm: str, vocabulary_sha: str) -> dual.PersonalDualViewEncoder:
    value = _checkpoint_value(payload, training_arm, vocabulary_sha)
    model = dual.PersonalDualViewEncoder(VOCABULARY_SIZE, "dual")
    model.load_state_dict(value["stateDict"], strict=True)
    return model


def _checkpoint_value(payload: bytes, training_arm: str, vocabulary_sha: str) -> dict:
    value = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
    _keys(value, {"architectureVersion", "modelArm", "parentWeightsSHA256", "stateDict",
                  "trainingArm", "version", "vocabularySHA256"}, "adaptation checkpoint")
    if (value["architectureVersion"] != dual.ARCHITECTURE_VERSION or value["modelArm"] != "dual"
            or value["parentWeightsSHA256"] != PARENT_DUAL_WEIGHT_SHA256
            or value["trainingArm"] != training_arm or value["version"] != FIT_VERSION
            or value["vocabularySHA256"] != vocabulary_sha or not isinstance(value["stateDict"], dict)):
        raise ValueError("Adaptation checkpoint contract changed")
    return value


def _parent_bundle(parent_fit: Path, code: Mapping[str, str]):
    parent_fit = _directory(parent_fit, "parent fit directory")
    receipt_path = _file(parent_fit / dual.FIT_RECEIPT_NAME, "parent fit receipt")
    protocol_path = _file(parent_fit / dual.FROZEN_PROTOCOL_NAME, "parent frozen protocol")
    weight_paths = {arm: _file(parent_fit / "weights" / f"{arm}.pt", f"parent {arm} weight") for arm in dual.ARMS}
    receipt_bytes, protocol_bytes = receipt_path.read_bytes(), protocol_path.read_bytes()
    weights = {arm: path.read_bytes() for arm, path in weight_paths.items()}
    captured = {receipt_path: receipt_bytes, protocol_path: protocol_bytes,
                **{weight_paths[arm]: payload for arm, payload in weights.items()}}
    snapshot = _snapshot_bytes(captured)
    _preserved(snapshot, code)
    parent_code = dual.code_identity()
    receipt = metrics._json(receipt_bytes, "parent fit receipt")
    weight_hashes = {arm: sha256(payload) for arm, payload in weights.items()}
    metrics.validate_fit_receipt(receipt, parent_code, sha256(protocol_bytes), weight_hashes)
    if (sha256(receipt_bytes) != PARENT_FIT_SHA256 or weight_hashes["dual"] != PARENT_DUAL_WEIGHT_SHA256
            or receipt["vocabularySHA256"] != VOCABULARY_SHA256
            or protocol_bytes != (_root() / dual.PROTOCOL_PATH).read_bytes()):
        raise ValueError("Wrong frozen parent fit, dual weight, vocabulary, or protocol")
    _preserved(snapshot, code)
    return receipt, receipt_bytes, weights, weight_hashes, snapshot, parent_code


def _optimization_contract() -> dict[str, object]:
    return {
        "augmentation": "none", "batchNormRunningStatistics": "frozen-eval-mode",
        "epochs": EPOCHS, "episodeCountPerArm": EPOCHS * 64,
        "genericLoss": "query-only-cross-entropy",
        "losses": {"adaptationAware": "0.5-generic-query-ce-plus-0.5-float64-residual-query-ce",
                   "genericControl": "0.5-generic-query-ce-plus-0.5-identical-generic-query-ce"},
        "optimizer": {"learningRate": LEARNING_RATE, "name": "AdamW", "weightDecay": WEIGHT_DECAY},
        "residual": {"classBalance": "one-over-sqrt-frequency", "regularization": REGULARIZATION,
                     "solverDType": "float64"},
        "scheduler": {"name": "CosineAnnealingLR", "tMax": EPOCHS}, "seed": SEED,
    }


def _role_guards() -> dict[str, bool]:
    return {
        "developmentEncodedDuringFit": False, "developmentInferredDuringFit": False,
        "privateInkUsed": False, "productionEligible": False,
        "reservedWritersEncoded": False, "reservedWritersInferred": False,
        "reservedWritersTransformed": False,
    }


def _validate_history(history, arm, query_counts):
    if not isinstance(history, list) or len(history) != EPOCHS:
        raise ValueError("Incomplete training history")
    for epoch, row in enumerate(history, 1):
        _keys(row, {"episodeCount", "epoch", "genericLoss", "loss", "queryCount", "secondHalfLoss"}, "history row")
        if (row["epoch"] != epoch or row["episodeCount"] != 64 or type(row["queryCount"]) is not int
                or row["queryCount"] != query_counts[str(epoch)]
                or any(type(row[key]) not in (int, float) or not math.isfinite(row[key]) or row[key] < 0
                       for key in ("genericLoss", "loss", "secondHalfLoss"))
                or (arm == "genericControl" and abs(row["loss"] - row["genericLoss"]) > 1e-12)
                or (arm == "genericControl" and abs(row["secondHalfLoss"] - row["genericLoss"]) > 1e-12)):
            raise ValueError("Invalid matched training history")


FIT_FIELDS = {"arms", "batchNormBufferSHA256", "codeSHA256", "developmentWriters", "episodePlan",
              "featureContract", "finalStateSHA256", "initialStateSHA256", "modelContract", "optimization",
              "parentBatchNormBufferSHA256", "parentBindings", "protocolSHA256", "reservedWriters", "roleGuards", "runtime", "scope",
              "selection", "sourceSHA256", "trainingHistory", "trainingInputHashes",
              "trainingInputHashesSHA256", "trainingWriters", "version", "vocabulary",
              "vocabularySHA256", "weightFiles", "weightsSHA256"}


def validate_fit_receipt(value: object, *, code: Mapping[str, str], protocol_sha: str,
                         runtime: Mapping[str, object]) -> dict:
    value = _keys(value, FIT_FIELDS, "adaptation fit receipt")
    expected = {
        "arms": list(ARMS), "codeSHA256": dict(code), "featureContract": dual._feature_contract(),
        "modelContract": dual._model_contract(), "optimization": _optimization_contract(),
        "protocolSHA256": protocol_sha, "roleGuards": _role_guards(), "runtime": dict(runtime),
        "scope": SCOPE, "selection": "final-epoch-only", "sourceSHA256": SOURCE_SHA256,
        "version": FIT_VERSION, "vocabularySHA256": VOCABULARY_SHA256,
        "weightFiles": {arm: f"weights/{arm}.pt" for arm in ARMS},
    }
    if any(value.get(key) != expected_value for key, expected_value in expected.items()):
        raise ValueError("Fit metadata or bindings changed")
    vocabulary = value["vocabulary"]
    if (not isinstance(vocabulary, list) or len(vocabulary) != VOCABULARY_SIZE
            or sorted(set(vocabulary)) != vocabulary or dual.vocabulary_digest(vocabulary) != VOCABULARY_SHA256
            or tuple(sparse_labels(vocabulary)) != SPARSE_LABELS):
        raise ValueError("Wrong fit vocabulary or sparse selector")
    for key, count, prefix in (("trainingWriters", 32, "trn_"), ("developmentWriters", 8, "trn_"),
                               ("reservedWriters", 20, "tst_")):
        writers = value[key]
        if (not isinstance(writers, list) or len(writers) != count or writers != sorted(set(writers))
                or any(not writer.startswith(prefix) for writer in writers)):
            raise ValueError("Wrong fit writer roles")
    if len(set(value["trainingWriters"] + value["developmentWriters"] + value["reservedWriters"])) != 60:
        raise ValueError("Fit writer roles overlap")
    parents = _keys(value["parentBindings"], {"codeSHA256", "dualWeightsSHA256", "fitReceiptSHA256",
                                               "protocolSHA256", "weightsSHA256"}, "parent bindings")
    if (parents["fitReceiptSHA256"] != PARENT_FIT_SHA256
            or parents["dualWeightsSHA256"] != PARENT_DUAL_WEIGHT_SHA256
            or parents["protocolSHA256"] != code[dual.PROTOCOL_PATH]
            or parents["codeSHA256"] != {path: code[path] for path in dual.CODE_PATHS}
            or not isinstance(parents["weightsSHA256"], dict) or set(parents["weightsSHA256"]) != set(dual.ARMS)
            or parents["weightsSHA256"]["dual"] != PARENT_DUAL_WEIGHT_SHA256):
        raise ValueError("Wrong frozen parent bindings")
    episode_plan = _keys(value["episodePlan"], {"byteCount", "episodeCount", "queryCountsPerEpoch",
                                                 "relativePath", "sha256", "supportCounts"}, "episode-plan binding")
    if (episode_plan["relativePath"] != PLAN_NAME or episode_plan["episodeCount"] != EPOCHS * 64
            or type(episode_plan["byteCount"]) is not int or episode_plan["byteCount"] <= 0
            or not _digest(episode_plan["sha256"]) or not isinstance(episode_plan["supportCounts"], dict)
            or set(episode_plan["supportCounts"]) != set(vocabulary)
            or max(episode_plan["supportCounts"].values()) - min(episode_plan["supportCounts"].values()) > 1
            or not isinstance(episode_plan["queryCountsPerEpoch"], dict)
            or set(episode_plan["queryCountsPerEpoch"]) != {str(epoch) for epoch in range(1, EPOCHS + 1)}
            or any(type(count) is not int or not 0 < count <= 64 * 97
                   for count in episode_plan["queryCountsPerEpoch"].values())):
        raise ValueError("Invalid episode-plan binding")
    hashes = value["trainingInputHashes"]
    if (not isinstance(hashes, list) or len(hashes) != TRAINING_SAMPLE_COUNT
            or any(not isinstance(row, dict) or set(row) != HASH_FIELDS
                   or not all(_digest(item) for item in row.values()) for row in hashes)
            or hashes != sorted(hashes, key=lambda row: (row["rasterSHA256"], row["trajectorySHA256"],
                                                         row["normalizedTrajectorySHA256"]))
            or value["trainingInputHashesSHA256"] != sha256(canonical_json_bytes(hashes))):
        raise ValueError("Training feature hashes changed")
    parent_bn = value["parentBatchNormBufferSHA256"]
    if (not isinstance(parent_bn, dict) or not parent_bn or any(
            not isinstance(key, str) or not _digest(item) for key, item in parent_bn.items())):
        raise ValueError("Invalid frozen parent BatchNorm identity")
    if (not _digest(value["initialStateSHA256"]) or not isinstance(value["finalStateSHA256"], dict)
            or set(value["finalStateSHA256"]) != set(ARMS)
            or any(not _digest(item) for item in value["finalStateSHA256"].values())
            or not isinstance(value["batchNormBufferSHA256"], dict)
            or set(value["batchNormBufferSHA256"]) != set(ARMS)
            or any(value["batchNormBufferSHA256"][arm] != parent_bn for arm in ARMS)):
        raise ValueError("Invalid state identity")
    weights = value["weightsSHA256"]
    if not isinstance(weights, dict) or set(weights) != set(ARMS) or any(not _digest(item) for item in weights.values()):
        raise ValueError("Invalid final weight bindings")
    histories = value["trainingHistory"]
    if not isinstance(histories, dict) or set(histories) != set(ARMS):
        raise ValueError("Missing training histories")
    for arm in ARMS:
        _validate_history(histories[arm], arm, episode_plan["queryCountsPerEpoch"])
    return value


def fit(source: Path, protocol: Path, parent_fit: Path, output: Path) -> None:
    source, protocol = _file(source, "public UJI source"), _file(protocol, "frozen protocol")
    source_bytes, protocol_bytes = source.read_bytes(), protocol.read_bytes()
    code = code_identity()
    if sha256(source_bytes) != SOURCE_SHA256 or sha256(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Wrong public source or frozen protocol")
    snapshot = _snapshot_bytes({source: source_bytes, protocol: protocol_bytes})
    _preserved(snapshot, code)
    parent_receipt, parent_receipt_bytes, parent_weights, parent_weight_hashes, parent_snapshot, parent_code = _parent_bundle(parent_fit, code)
    snapshot.update(parent_snapshot)
    _preserved(snapshot, code)
    _configure_runtime()
    runtime = _runtime()
    records = _load_source_bytes(source_bytes)
    roles = training_writers, development_writers, reserved_writers = dual._validate_roles(records)
    if tuple(parent_receipt[key] for key in ("trainingWriters", "developmentWriters", "reservedWriters")) != tuple(list(role) for role in roles):
        raise ValueError("Parent/source writer roles changed")
    training = dual._select_role_samples(records, training_writers, TRAINING_SAMPLE_COUNT)
    vocabulary = dual._vocabulary(training)
    if list(vocabulary) != parent_receipt["vocabulary"] or dual.vocabulary_digest(vocabulary) != VOCABULARY_SHA256:
        raise ValueError("Training vocabulary differs from frozen parent")
    targets = torch.tensor([vocabulary.index(sample.label) for sample in training], dtype=torch.long)
    batch = dual.encode_samples(training, training_writers, include_normalized_trajectory_hashes=True)
    if batch.normalized_trajectory_hashes is None:
        raise ValueError("Missing normalized trajectory hashes")
    episodes, support_counts = plan_episodes(training, training_writers, vocabulary,
                                              batch.raster_hashes, batch.normalized_trajectory_hashes)
    source_hashes = [{"normalizedTrajectorySHA256": batch.normalized_trajectory_hashes[index],
                      "rasterSHA256": batch.raster_hashes[index],
                      "trajectorySHA256": batch.trajectory_hashes[index]}
                     for index in range(len(training))]
    manifest = episode_manifest(episodes, training, source_hashes, support_counts, vocabulary,
                                code, sha256(protocol_bytes))
    manifest_bytes = canonical_json_bytes(manifest)
    validate_episode_manifest(manifest, code=code, protocol_sha=sha256(protocol_bytes), vocabulary=vocabulary)
    training_hashes = dual._training_input_hashes(batch)
    parent_model = dual._load_checkpoint(parent_weights["dual"], "dual", VOCABULARY_SHA256)
    initial_sha = dual._state_digest(parent_model.state_dict())
    parent_bn_hashes = _bn_hashes_from_state(parent_model.state_dict())

    destination = _new_directory(output)
    weights_directory = destination / "weights"
    weights_directory.mkdir(mode=0o700)
    _write(destination / FROZEN_PROTOCOL_NAME, protocol_bytes)
    # The complete deterministic plan is published before the first optimizer step.
    _write(destination / PLAN_NAME, manifest_bytes)
    histories, weights_sha, final_states, bn_hashes = {}, {}, {}, {}
    for arm in ARMS:
        if dual._state_digest(parent_model.state_dict()) != initial_sha:
            raise ValueError("Frozen parent model changed before matched arm initialization")
        trained, histories[arm], bn_hashes[arm] = train_arm(parent_model, arm, batch, targets, episodes)
        if bn_hashes[arm] != parent_bn_hashes:
            raise ValueError("Continuation changed frozen parent BatchNorm state")
        final_states[arm] = dual._state_digest(trained.state_dict())
        payload = _checkpoint_bytes(trained, arm, VOCABULARY_SHA256, PARENT_DUAL_WEIGHT_SHA256)
        _load_checkpoint(payload, arm, VOCABULARY_SHA256)
        _write(weights_directory / f"{arm}.pt", payload)
        weights_sha[arm] = sha256(payload)
    if dual._state_digest(parent_model.state_dict()) != initial_sha:
        raise ValueError("Frozen parent checkpoint was mutated")
    parent_bindings = {
        "codeSHA256": parent_code, "dualWeightsSHA256": PARENT_DUAL_WEIGHT_SHA256,
        "fitReceiptSHA256": sha256(parent_receipt_bytes), "protocolSHA256": code[dual.PROTOCOL_PATH],
        "weightsSHA256": parent_weight_hashes,
    }
    receipt = {
        "arms": list(ARMS), "batchNormBufferSHA256": bn_hashes, "codeSHA256": code,
        "developmentWriters": list(development_writers),
        "episodePlan": {"byteCount": len(manifest_bytes), "episodeCount": len(episodes),
                        "queryCountsPerEpoch": manifest["queryCountsPerEpoch"],
                        "relativePath": PLAN_NAME, "sha256": sha256(manifest_bytes),
                        "supportCounts": support_counts},
        "featureContract": dual._feature_contract(), "finalStateSHA256": final_states,
        "initialStateSHA256": initial_sha, "modelContract": dual._model_contract(),
        "optimization": _optimization_contract(), "parentBatchNormBufferSHA256": parent_bn_hashes,
        "parentBindings": parent_bindings,
        "protocolSHA256": sha256(protocol_bytes), "reservedWriters": list(reserved_writers),
        "roleGuards": _role_guards(), "runtime": runtime, "scope": SCOPE,
        "selection": "final-epoch-only", "sourceSHA256": SOURCE_SHA256,
        "trainingHistory": histories, "trainingInputHashes": training_hashes,
        "trainingInputHashesSHA256": sha256(canonical_json_bytes(training_hashes)),
        "trainingWriters": list(training_writers), "version": FIT_VERSION,
        "vocabulary": list(vocabulary), "vocabularySHA256": VOCABULARY_SHA256,
        "weightFiles": {arm: f"weights/{arm}.pt" for arm in ARMS}, "weightsSHA256": weights_sha,
    }
    validate_fit_receipt(receipt, code=code, protocol_sha=sha256(protocol_bytes), runtime=runtime)
    _preserved(snapshot, code)
    _write(destination / FIT_RECEIPT_NAME, canonical_json_bytes(receipt))  # final fit artifact
    _preserved(snapshot, code)


def _fit_bundle(fit_directory: Path, protocol_bytes: bytes, code: Mapping[str, str],
                runtime: Mapping[str, object], *, load_models: bool = True):
    fit_directory = _directory(fit_directory, "adaptation fit directory")
    receipt_path = _file(fit_directory / FIT_RECEIPT_NAME, "adaptation fit receipt")
    plan_path = _file(fit_directory / PLAN_NAME, "episode plan")
    frozen_protocol = _file(fit_directory / FROZEN_PROTOCOL_NAME, "fit frozen protocol")
    receipt_bytes, plan_bytes, frozen_protocol_bytes = (
        receipt_path.read_bytes(), plan_path.read_bytes(), frozen_protocol.read_bytes())
    weight_paths = {arm: _file(fit_directory / "weights" / f"{arm}.pt", f"{arm} checkpoint") for arm in ARMS}
    weight_bytes = {arm: path.read_bytes() for arm, path in weight_paths.items()}
    captured = {receipt_path: receipt_bytes, plan_path: plan_bytes, frozen_protocol: frozen_protocol_bytes,
                **{weight_paths[arm]: payload for arm, payload in weight_bytes.items()}}
    snapshot = _snapshot_bytes(captured)
    _preserved(snapshot, code)
    if frozen_protocol_bytes != protocol_bytes:
        raise ValueError("Fit frozen protocol differs from supplied protocol")
    receipt = validate_fit_receipt(_json(receipt_bytes, "adaptation fit receipt"), code=code,
                                   protocol_sha=sha256(protocol_bytes), runtime=runtime)
    plan = validate_episode_manifest(_json(plan_bytes, "episode plan"), code=code,
                                     protocol_sha=sha256(protocol_bytes), vocabulary=receipt["vocabulary"])
    if (receipt["episodePlan"]["sha256"] != sha256(plan_bytes)
            or receipt["episodePlan"]["byteCount"] != len(plan_bytes)
            or receipt["episodePlan"]["supportCounts"] != plan["supportCounts"]
            or receipt["episodePlan"]["queryCountsPerEpoch"] != plan["queryCountsPerEpoch"]):
        raise ValueError("Fit receipt does not bind its exact episode plan")
    manifest_hashes = sorted((row["inputHashes"] for row in plan["sourceRows"]),
                             key=lambda row: (row["rasterSHA256"], row["trajectorySHA256"],
                                              row["normalizedTrajectorySHA256"]))
    if manifest_hashes != receipt["trainingInputHashes"]:
        raise ValueError("Episode source hashes differ from fit training hashes")
    if receipt["weightFiles"] != {arm: f"weights/{arm}.pt" for arm in ARMS}:
        raise ValueError("Fit checkpoint relative paths changed")
    if any(sha256(weight_bytes[arm]) != receipt["weightsSHA256"][arm] for arm in ARMS):
        raise ValueError("Final checkpoint digest mismatch")
    checkpoint_values = {arm: _checkpoint_value(weight_bytes[arm], arm, VOCABULARY_SHA256) for arm in ARMS}
    for arm, value in checkpoint_values.items():
        if (dual._state_digest(value["stateDict"]) != receipt["finalStateSHA256"][arm]
                or _bn_hashes_from_state(value["stateDict"]) != receipt["batchNormBufferSHA256"][arm]
                or receipt["batchNormBufferSHA256"][arm] != receipt["parentBatchNormBufferSHA256"]):
            raise ValueError("Final checkpoint state or BatchNorm binding changed")
    if load_models:
        models = {}
        for arm, value in checkpoint_values.items():
            model = dual.PersonalDualViewEncoder(VOCABULARY_SIZE, "dual")
            model.load_state_dict(value["stateDict"], strict=True)
            models[arm] = model
    else:
        models = None
    _preserved(snapshot, code)
    return receipt, receipt_bytes, plan_bytes, models, snapshot


def _finite_vector(value, size: int, *, unit=False):
    if (not isinstance(value, list) or len(value) != size
            or any(type(item) not in (int, float) or not math.isfinite(item) for item in value)):
        return False
    return not unit or abs(math.sqrt(sum(item * item for item in value)) - 1.0) <= 1e-4


def _generic_rank(vocabulary: Sequence[str], logits: Sequence[float]) -> list[dict[str, object]]:
    logits = np.asarray(logits, dtype=np.float64)
    scores = normalized_scores(logits[None, :])[0]
    order = sorted(range(len(vocabulary)), key=lambda index: (-float(logits[index]), index))
    return [{"label": vocabulary[index], "score": float(scores[index])} for index in order]


def _residual_ranks(support_rows, query_rows, vocabulary, arm):
    selected = sorted((row for row in support_rows if row["label"] in SPARSE_LABELS), key=lambda row: row["label"])
    if len(selected) != SUPPORT_COUNT or [row["label"] for row in selected] != sorted(SPARSE_LABELS):
        raise ValueError("Sparse support set changed")
    features = np.asarray([row["outputs"][arm]["embedding"] for row in selected], dtype=np.float64)
    logits = np.asarray([row["outputs"][arm]["rawLogits"] for row in selected], dtype=np.float64)
    head = ResidualHead.fit(features, normalized_scores(logits), tuple(row["label"] for row in selected),
                            tuple(vocabulary), regularization=REGULARIZATION)
    results = []
    for row in query_rows:
        output = row["outputs"][arm]
        results.append({
            "genericRanking": _generic_rank(vocabulary, output["rawLogits"]),
            "residualRanking": head.rank(np.asarray(output["embedding"], dtype=np.float64),
                                         normalized_scores(np.asarray(output["rawLogits"], dtype=np.float64)[None, :])[0]),
        })
    return results


def _output_rows(projected, batch: dual.FeatureBatch, outputs, *, expose_support_labels: bool):
    rows = []
    normalized = batch.normalized_trajectory_hashes
    if normalized is None:
        raise ValueError("Prediction normalized hashes were not constructed")
    if len(projected) != len(batch.trajectory):
        raise ValueError("Projected metadata and feature rows differ")
    for index, (sample, source_ordinal, row_id) in enumerate(projected):
        row = {
            "inputHashes": {"normalizedTrajectorySHA256": normalized[index],
                            "rasterSHA256": batch.raster_hashes[index],
                            "trajectorySHA256": batch.trajectory_hashes[index]},
            "opaqueID": row_id,
            "outputs": {arm: {"embedding": [float(item) for item in outputs[arm][0][index]],
                              "rawLogits": [float(item) for item in outputs[arm][1][index]]} for arm in ARMS},
            "session": sample.session, "sourceOrdinal": source_ordinal, "writer": sample.writer,
        }
        if expose_support_labels:
            row["label"] = sample.label
        rows.append(row)
    return sorted(rows, key=lambda row: row["opaqueID"])


PREDICTION_FIELDS = {"arms", "codeSHA256", "featureContract", "fitReceiptSHA256", "protocolSHA256",
                     "queryCount", "queryRows", "runtime", "scope", "sourceSHA256", "sparseSupportLabels",
                     "supportCount", "supportRows", "version", "vocabulary", "vocabularySHA256", "weightsSHA256"}


def _valid_output(output) -> None:
    _keys(output, {"embedding", "rawLogits"}, "model output")
    if not _finite_vector(output["embedding"], EMBEDDING_SIZE, unit=True) or not _finite_vector(output["rawLogits"], VOCABULARY_SIZE):
        raise ValueError("Invalid model output")


def _validate_rank(rank, vocabulary, *, generic: bool, raw_logits=None):
    if (not isinstance(rank, list) or len(rank) != VOCABULARY_SIZE
            or any(not isinstance(row, dict) or set(row) != {"label", "score"} for row in rank)):
        raise ValueError("Incomplete ranking")
    labels = [row["label"] for row in rank]
    scores = [row["score"] for row in rank]
    if set(labels) != set(vocabulary) or len(set(labels)) != VOCABULARY_SIZE or any(
            type(score) not in (int, float) or not math.isfinite(score) for score in scores):
        raise ValueError("Invalid ranking labels or scores")
    if generic:
        expected = _generic_rank(vocabulary, raw_logits)
        if labels != [row["label"] for row in expected] or not np.allclose(
                scores, [row["score"] for row in expected], atol=1e-12, rtol=1e-12):
            raise ValueError("Generic ranking arithmetic changed")
    elif labels != sorted(vocabulary, key=lambda label: (-dict(zip(labels, scores))[label], label)):
        raise ValueError("Residual ranking order changed")


def validate_prediction(value: object, *, receipt: dict, receipt_bytes: bytes,
                        code: Mapping[str, str], protocol_sha: str, runtime: Mapping[str, object]) -> dict:
    value = _keys(value, PREDICTION_FIELDS, "prediction packet")
    expected = {
        "arms": list(ARMS), "codeSHA256": dict(code), "featureContract": dual._feature_contract(),
        "fitReceiptSHA256": sha256(receipt_bytes), "protocolSHA256": protocol_sha,
        "queryCount": QUERY_COUNT, "runtime": dict(runtime), "scope": SCOPE,
        "sourceSHA256": SOURCE_SHA256, "sparseSupportLabels": list(SPARSE_LABELS),
        "supportCount": QUERY_COUNT, "version": PREDICTION_VERSION,
        "vocabulary": receipt["vocabulary"], "vocabularySHA256": VOCABULARY_SHA256,
        "weightsSHA256": receipt["weightsSHA256"],
    }
    if any(value.get(key) != item for key, item in expected.items()):
        raise ValueError("Prediction bindings changed")
    support, queries = value["supportRows"], value["queryRows"]
    if not isinstance(support, list) or len(support) != QUERY_COUNT or not isinstance(queries, list) or len(queries) != QUERY_COUNT:
        raise ValueError("Incomplete prediction cohort")
    common = {"inputHashes", "opaqueID", "outputs", "session", "sourceOrdinal", "writer"}
    for row in support:
        _keys(row, common | {"label"}, "support row")
        if row["session"] != 1 or row["label"] not in receipt["vocabulary"]:
            raise ValueError("Invalid labeled support role")
    for row in queries:
        _keys(row, common | {"predictions"}, "query row")
        if row["session"] != 2:
            raise ValueError("Invalid unlabeled query role")
    for row in support + queries:
        if (not _digest(row["opaqueID"]) or type(row["sourceOrdinal"]) is not int or row["sourceOrdinal"] < 0
                or row["opaqueID"] != opaque_id(row["sourceOrdinal"], row["writer"], row["session"])
                or not isinstance(row["writer"], str) or not row["writer"].startswith("trn_")
                or set(row["inputHashes"]) != HASH_FIELDS or not all(_digest(item) for item in row["inputHashes"].values())
                or not isinstance(row["outputs"], dict) or set(row["outputs"]) != set(ARMS)):
            raise ValueError("Invalid prediction row identity, hash, or arm")
        for output in row["outputs"].values():
            _valid_output(output)
    all_ids = [row["opaqueID"] for row in support + queries]
    if ([row["opaqueID"] for row in support] != sorted(row["opaqueID"] for row in support)
            or [row["opaqueID"] for row in queries] != sorted(row["opaqueID"] for row in queries)
            or len(set(all_ids)) != DEVELOPMENT_SAMPLE_COUNT):
        raise ValueError("Prediction IDs are duplicate, overlapping, or unsorted")
    writers = receipt["developmentWriters"]
    for writer in writers:
        writer_support = sorted((row for row in support if row["writer"] == writer), key=lambda row: row["label"])
        writer_queries = sorted((row for row in queries if row["writer"] == writer), key=lambda row: row["opaqueID"])
        if len(writer_support) != 97 or [row["label"] for row in writer_support] != receipt["vocabulary"] or len(writer_queries) != 97:
            raise ValueError("Writer support/query coverage changed")
        for arm in ARMS:
            recomputed = _residual_ranks(writer_support, writer_queries, receipt["vocabulary"], arm)
            for row, expected_ranks in zip(writer_queries, recomputed):
                predictions = _keys(row["predictions"], set(ARMS), "query arm predictions")
                ranks = _keys(predictions[arm], {"genericRanking", "residualRanking"}, "query rankings")
                _validate_rank(ranks["genericRanking"], receipt["vocabulary"], generic=True,
                               raw_logits=row["outputs"][arm]["rawLogits"])
                _validate_rank(ranks["residualRanking"], receipt["vocabulary"], generic=False)
                if ([item["label"] for item in ranks["residualRanking"]]
                        != [item["label"] for item in expected_ranks["residualRanking"]]
                        or not np.allclose([item["score"] for item in ranks["residualRanking"]],
                                           [item["score"] for item in expected_ranks["residualRanking"]],
                                           atol=1e-12, rtol=1e-12)):
                    raise ValueError("Residual prediction arithmetic changed")
    return value


def predict(source: Path, protocol: Path, fit_directory: Path, output: Path) -> None:
    source, protocol = _file(source, "public UJI source"), _file(protocol, "frozen protocol")
    source_bytes, protocol_bytes = source.read_bytes(), protocol.read_bytes()
    code = code_identity()
    if sha256(source_bytes) != SOURCE_SHA256 or sha256(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Wrong public source or frozen protocol")
    snapshot = _snapshot_bytes({source: source_bytes, protocol: protocol_bytes})
    _preserved(snapshot, code)
    _configure_runtime()
    runtime = _runtime()
    receipt, receipt_bytes, _, models, fit_snapshot = _fit_bundle(fit_directory, protocol_bytes, code, runtime)
    snapshot.update(fit_snapshot)
    _preserved(snapshot, code)
    records = _load_source_bytes(source_bytes)
    roles = dual._validate_roles(records)
    if tuple(receipt[key] for key in ("trainingWriters", "developmentWriters", "reservedWriters")) != tuple(list(role) for role in roles):
        raise ValueError("Prediction source writer roles changed")
    projected = development_projection(records, roles[1])
    support_projected = tuple(row for row in projected if row[0].session == 1)
    query_projected = tuple(row for row in projected if row[0].session == 2)
    support_samples = tuple(row[0] for row in support_projected)
    query_samples = tuple(row[0] for row in query_projected)
    support_batch = dual.encode_samples(support_samples, roles[1], include_normalized_trajectory_hashes=True)
    query_batch = dual.encode_samples(query_samples, roles[1], include_normalized_trajectory_hashes=True)
    support_outputs = {arm: dual._infer(models[arm], support_batch) for arm in ARMS}
    query_outputs = {arm: dual._infer(models[arm], query_batch) for arm in ARMS}
    support_rows = _output_rows(support_projected, support_batch, support_outputs, expose_support_labels=True)
    query_rows = _output_rows(query_projected, query_batch, query_outputs, expose_support_labels=False)
    for writer in receipt["developmentWriters"]:
        writer_support = [row for row in support_rows if row["writer"] == writer]
        writer_queries = [row for row in query_rows if row["writer"] == writer]
        by_id = {row["opaqueID"]: row for row in writer_queries}
        ordered_queries = sorted(writer_queries, key=lambda row: row["opaqueID"])
        frozen = {arm: _residual_ranks(writer_support, ordered_queries, receipt["vocabulary"], arm) for arm in ARMS}
        for index, row in enumerate(ordered_queries):
            by_id[row["opaqueID"]]["predictions"] = {arm: frozen[arm][index] for arm in ARMS}
    packet = {
        "arms": list(ARMS), "codeSHA256": code, "featureContract": dual._feature_contract(),
        "fitReceiptSHA256": sha256(receipt_bytes), "protocolSHA256": sha256(protocol_bytes),
        "queryCount": len(query_rows), "queryRows": query_rows, "runtime": runtime, "scope": SCOPE,
        "sourceSHA256": SOURCE_SHA256, "sparseSupportLabels": list(SPARSE_LABELS),
        "supportCount": len(support_rows), "supportRows": support_rows, "version": PREDICTION_VERSION,
        "vocabulary": receipt["vocabulary"], "vocabularySHA256": VOCABULARY_SHA256,
        "weightsSHA256": receipt["weightsSHA256"],
    }
    validate_prediction(packet, receipt=receipt, receipt_bytes=receipt_bytes, code=code,
                        protocol_sha=sha256(protocol_bytes), runtime=runtime)
    packet_bytes = canonical_json_bytes(packet)
    _preserved(snapshot, code)
    destination = _new_directory(output)
    _write(destination / PREDICTION_NAME, packet_bytes)
    prediction_receipt = {
        "artifactKind": "personal-dual-adaptation-prediction-receipt", "codeSHA256": code,
        "fitReceiptSHA256": sha256(receipt_bytes), "passed": True,
        "predictionByteCount": len(packet_bytes), "predictionSHA256": sha256(packet_bytes),
        "queryCount": QUERY_COUNT, "supportCount": QUERY_COUNT, "version": VERSION,
        "weightsSHA256": receipt["weightsSHA256"],
    }
    _preserved(snapshot, code)
    _write(destination / PREDICTION_RECEIPT_NAME, canonical_json_bytes(prediction_receipt))
    _preserved(snapshot, code)


def _validate_prediction_receipt(value, packet_bytes, fit_bytes, code, weights):
    expected = {
        "artifactKind": "personal-dual-adaptation-prediction-receipt", "codeSHA256": code,
        "fitReceiptSHA256": sha256(fit_bytes), "passed": True,
        "predictionByteCount": len(packet_bytes), "predictionSHA256": sha256(packet_bytes),
        "queryCount": QUERY_COUNT, "supportCount": QUERY_COUNT, "version": VERSION,
        "weightsSHA256": weights,
    }
    if value != expected:
        raise ValueError("Prediction receipt binding changed")


def _top(rank):
    return rank[0]["label"]


def _copy_reasons(hashes, reference, prefix):
    return [f"{prefix}:{key}" for key in sorted(HASH_FIELDS) if hashes[key] in reference[key]]


def _hash_sets(rows):
    return {key: {row[key] for row in rows} for key in HASH_FIELDS}


def score(source: Path, protocol: Path, fit_directory: Path, prediction_directory: Path, output: Path) -> None:
    protocol = _file(protocol, "frozen protocol")
    protocol_bytes = protocol.read_bytes()
    code = code_identity()
    if sha256(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Wrong frozen protocol")
    blind_snapshot = _snapshot_bytes({protocol: protocol_bytes})
    _preserved(blind_snapshot, code)
    _configure_runtime()
    runtime = _runtime()
    receipt, receipt_bytes, _, _, fit_snapshot = _fit_bundle(
        fit_directory, protocol_bytes, code, runtime, load_models=False)
    blind_snapshot.update(fit_snapshot)
    _preserved(blind_snapshot, code)
    prediction_directory = _directory(prediction_directory, "prediction directory")
    prediction_path = _file(prediction_directory / PREDICTION_NAME, "prediction packet")
    prediction_receipt_path = _file(prediction_directory / PREDICTION_RECEIPT_NAME, "prediction receipt")
    packet_bytes, prediction_receipt_bytes = prediction_path.read_bytes(), prediction_receipt_path.read_bytes()
    blind_snapshot.update(_snapshot_bytes({prediction_path: packet_bytes,
                                           prediction_receipt_path: prediction_receipt_bytes}))
    _preserved(blind_snapshot, code)
    packet = validate_prediction(_json(packet_bytes, "prediction packet"), receipt=receipt,
                                 receipt_bytes=receipt_bytes, code=code,
                                 protocol_sha=sha256(protocol_bytes), runtime=runtime)
    _validate_prediction_receipt(_json(prediction_receipt_bytes, "prediction receipt"), packet_bytes,
                                 receipt_bytes, code, receipt["weightsSHA256"])
    _preserved(blind_snapshot, code)

    # Query truth is opened only after every label-free row and all ranking
    # arithmetic above have passed.
    source = _file(source, "public UJI source")
    source_bytes = source.read_bytes()
    if sha256(source_bytes) != SOURCE_SHA256:
        raise ValueError("Wrong public truth source")
    snapshot = {**blind_snapshot, **_snapshot_bytes({source: source_bytes})}
    _preserved(snapshot, code)
    records = _load_source_bytes(source_bytes)
    roles = split_writers(records)
    if tuple(receipt[key] for key in ("trainingWriters", "developmentWriters", "reservedWriters")) != tuple(list(role) for role in roles):
        raise ValueError("Scoring source writer roles changed")
    projected = development_projection(records, roles[1])
    source_rows = {row_id: (sample, ordinal) for sample, ordinal, row_id in projected}
    packet_support = {row["opaqueID"]: row for row in packet["supportRows"]}
    packet_queries = {row["opaqueID"]: row for row in packet["queryRows"]}
    if set(source_rows) != set(packet_support) | set(packet_queries) or set(packet_support) & set(packet_queries):
        raise ValueError("Prediction/source coverage changed")
    for oid, (sample, ordinal) in source_rows.items():
        row = packet_support.get(oid) if sample.session == 1 else packet_queries.get(oid)
        if (row is None or row["writer"] != sample.writer or row["session"] != sample.session
                or row["sourceOrdinal"] != ordinal
                or row["inputHashes"] != _feature_hashes(sample)
                or (sample.session == 1 and row["label"] != sample.label)):
            raise ValueError("Prediction/source identity, hash, or support truth changed")

    generic_rows, residual_rows = [], []
    for oid in sorted(source_rows):
        sample, _ = source_rows[oid]
        row = packet_support.get(oid) or packet_queries.get(oid)
        predictions = {arm: _generic_rank(receipt["vocabulary"], row["outputs"][arm]["rawLogits"])[0]["label"]
                       for arm in ARMS}
        generic_rows.append({"correct": {arm: label == sample.label for arm, label in predictions.items()},
                             "intended": sample.label, "opaqueID": oid, "predictions": predictions,
                             "session": sample.session, "writer": sample.writer})
        if sample.session == 2:
            residual_predictions = {f"{arm}Generic": _top(row["predictions"][arm]["genericRanking"])
                                    for arm in ARMS}
            residual_predictions.update({f"{arm}Residual": _top(row["predictions"][arm]["residualRanking"])
                                         for arm in ARMS})
            residual_rows.append({"correct": {name: label == sample.label for name, label in residual_predictions.items()},
                                  "inputHashes": row["inputHashes"], "intended": sample.label,
                                  "opaqueID": oid, "predictions": residual_predictions,
                                  "writer": sample.writer})
    if len(generic_rows) != DEVELOPMENT_SAMPLE_COUNT or len(residual_rows) != QUERY_COUNT:
        raise ValueError("Scoring denominators changed")
    support_hashes_by_writer = {
        writer: _hash_sets([row["inputHashes"] for row in packet["supportRows"] if row["writer"] == writer])
        for writer in receipt["developmentWriters"]
    }
    training_hashes = _hash_sets(receipt["trainingInputHashes"])
    for row in residual_rows:
        row["noveltyExclusions"] = (_copy_reasons(row["inputHashes"], training_hashes, "training")
                                     + _copy_reasons(row["inputHashes"], support_hashes_by_writer[row["writer"]], "support"))
    taught = [row for row in residual_rows if row["intended"] in SPARSE_LABELS]
    untaught = [row for row in residual_rows if row["intended"] not in SPARSE_LABELS]
    if len(taught) != 128 or len(untaught) != 648:
        raise ValueError("Sparse taught/untaught denominator changed")
    novel = [row for row in residual_rows if not row["noveltyExclusions"]]
    if len(novel) != 772:
        raise ValueError("Frozen four-row conservative novelty cohort changed")
    residual_paired = metrics.paired_summary(residual_rows, "genericControlResidual", "adaptationAwareResidual")
    generic_paired = metrics.paired_summary(generic_rows, "genericControl", "adaptationAware")
    taught_paired = metrics.paired_summary(taught, "adaptationAwareGeneric", "adaptationAwareResidual")
    untaught_paired = metrics.paired_summary(untaught, "adaptationAwareGeneric", "adaptationAwareResidual")
    conditions = {
        "candidateGenericNoWorseThanControl": generic_paired["candidateCorrect"] >= generic_paired["referenceCorrect"],
        "candidateResidualBetterThanControl": residual_paired["candidateCorrect"] > residual_paired["referenceCorrect"],
        "candidateTaughtResidualBetterThanOwnGeneric": taught_paired["candidateCorrect"] > taught_paired["referenceCorrect"],
        "candidateUntaughtResidualNoWorseThanOwnGeneric": untaught_paired["candidateCorrect"] >= untaught_paired["referenceCorrect"],
    }
    report = {
        "codeSHA256": code, "conditions": conditions, "freshWriterEvaluation": False,
        "generic": {"arms": {arm: metrics.identity_summary(generic_rows, arm) for arm in ARMS},
                    "paired": generic_paired, "rows": generic_rows},
        "inputSHA256": {"fitReceipt": sha256(receipt_bytes), "predictionReceipt": sha256(prediction_receipt_bytes),
                        "predictions": sha256(packet_bytes), "protocol": sha256(protocol_bytes), "source": SOURCE_SHA256,
                        "weights": receipt["weightsSHA256"]},
        "naturalChordEvaluation": False, "nextIndependentWriterGateEligible": all(conditions.values()),
        "productionEligible": False, "queryCount": QUERY_COUNT,
        "residual": {
            "arms": {f"{arm}Generic": metrics.identity_summary(residual_rows, f"{arm}Generic") for arm in ARMS}
                    | {f"{arm}Residual": metrics.identity_summary(residual_rows, f"{arm}Residual") for arm in ARMS},
            "candidateTaught16": taught_paired, "candidateUntaught81": untaught_paired,
            "novelty": {"count": len(novel), "excluded": len(residual_rows) - len(novel),
                        "paired": metrics.paired_summary(novel, "genericControlResidual", "adaptationAwareResidual")},
            "paired": residual_paired, "rows": residual_rows,
        },
        "scope": SCOPE, "version": SCORE_VERSION,
    }
    report_bytes = canonical_json_bytes(report)
    _preserved(snapshot, code)
    destination = _new_directory(output)
    _write(destination / "score.json", report_bytes)
    verification = {
        "codeSHA256": code, "conditions": conditions, "genericRowCount": DEVELOPMENT_SAMPLE_COUNT,
        "passed": True, "predictionSHA256": sha256(packet_bytes), "queryCount": QUERY_COUNT,
        "scoreByteCount": len(report_bytes), "scoreSHA256": sha256(report_bytes), "version": VERSION,
    }
    _preserved(snapshot, code)
    _write(destination / "verification-receipt.json", canonical_json_bytes(verification))
    _preserved(snapshot, code)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    fit_parser = commands.add_parser("fit")
    for name in ("source", "protocol", "parent-fit", "output"):
        fit_parser.add_argument(f"--{name}", required=True, type=Path)
    predict_parser = commands.add_parser("predict")
    for name in ("source", "protocol", "fit", "output"):
        predict_parser.add_argument(f"--{name}", required=True, type=Path)
    score_parser = commands.add_parser("score")
    for name in ("source", "protocol", "fit", "predictions", "output"):
        score_parser.add_argument(f"--{name}", required=True, type=Path)
    args = parser.parse_args(argv)
    if args.command == "fit":
        fit(args.source, args.protocol, args.parent_fit, args.output)
    elif args.command == "predict":
        predict(args.source, args.protocol, args.fit, args.output)
    else:
        score(args.source, args.protocol, args.fit, args.predictions, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

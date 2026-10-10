"""Research-only HELP/HARM/NEUTRAL selector over frozen support proposals.

This module does not encode ink, fit a recognizer, read query truth during
prediction, or alter generic scores.  It extracts label-permutation-neutral
numeric evidence from already-frozen outputs and can only choose an eligible
explicit proposal or preserve the caller's exact baseline result.
"""
from __future__ import annotations

import math
from collections.abc import Collection, Sequence

import torch
import torch.nn.functional as F


VERSION = "personal-support-action-selector-v1"
FEATURE_NAMES = (
    "baselineProposalProbability",
    "baselineMaximumProbability",
    "baselineTopOneTopTwoProbabilityMargin",
    "baselineNormalizedEntropy",
    "baselineDomainRead",
    "proposalEqualsBaseline",
    "matcherProposalVsDeferLogitMargin",
    "matcherProposalVsBestOtherSupportLogitMargin",
    "proposedPrototypeCosine",
    "proposedPrototypeCosineVsBestOtherMargin",
)
ACTION_NAMES = ("HELP", "HARM", "NEUTRAL")
HELP, HARM, NEUTRAL = range(3)
FEATURE_COUNT = len(FEATURE_NAMES)
ACTION_COUNT = len(ACTION_NAMES)
EMBEDDING_COUNT = 128
MAX_ROWS = 100_000
STEPS = 1_000
LEARNING_RATE = 0.01
WEIGHT_DECAY = 0.001


def _token(value: object, *, optional: bool = False) -> bool:
    return (optional and value is None) or isinstance(value, str) and bool(value)


def _finite_vector(value: object, count: int) -> tuple[float, ...] | None:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)) or len(value) != count:
        return None
    result = []
    for item in value:
        if isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item):
            return None
        result.append(float(item))
    return tuple(result)


def _unit_vector(value: object) -> tuple[float, ...] | None:
    vector = _finite_vector(value, EMBEDDING_COUNT)
    if vector is None:
        return None
    norm = math.sqrt(sum(item * item for item in vector))
    return vector if abs(norm - 1.0) <= 1e-3 else None


def _probabilities(logits: tuple[float, ...]) -> tuple[float, ...] | None:
    maximum = max(logits)
    values = tuple(math.exp(item - maximum) for item in logits)
    total = sum(values)
    if not math.isfinite(total) or total <= 0:
        return None
    result = tuple(item / total for item in values)
    return result if all(math.isfinite(item) for item in result) else None


def feature_row(
    control_logits: Sequence[float],
    matcher_logits: Sequence[float],
    query_embedding: Sequence[float],
    prototypes: Sequence[Sequence[float]],
    vocabulary: Sequence[str],
    prototype_labels: Sequence[str],
    allowed: Collection[str],
    baseline: str | None,
    proposal: str | None,
) -> list[float] | None:
    """Return ten frozen numeric features or fail closed with ``None``.

    ``proposal`` must be the actual unique support winner.  A missing proposal,
    a DEFER/tied winner, invalid/nonfinite tensors, a baseline inconsistent with
    the control logits, or unsupported labels cannot reach the selector.
    """

    if (
        not isinstance(vocabulary, Sequence)
        or isinstance(vocabulary, (str, bytes))
        or not 2 <= len(vocabulary) <= 512
        or len(set(vocabulary)) != len(vocabulary)
        or any(not _token(label) for label in vocabulary)
        or not isinstance(prototype_labels, Sequence)
        or isinstance(prototype_labels, (str, bytes))
        or not 1 <= len(prototype_labels) <= 192
        or len(set(prototype_labels)) != len(prototype_labels)
        or any(not _token(label) for label in prototype_labels)
        or not isinstance(allowed, Collection)
        or isinstance(allowed, (str, bytes))
        or not allowed
        or any(not _token(label) for label in allowed)
        or not set(allowed) <= set(vocabulary)
        or not set(prototype_labels) <= set(allowed)
        or not _token(baseline, optional=True)
        or not _token(proposal, optional=True)
    ):
        return None

    generic = _finite_vector(control_logits, len(vocabulary))
    matcher = _finite_vector(matcher_logits, len(prototype_labels) + 1)
    query = _unit_vector(query_embedding)
    if generic is None or matcher is None or query is None or len(prototypes) != len(prototype_labels):
        return None
    prototype_vectors = tuple(_unit_vector(row) for row in prototypes)
    if any(row is None for row in prototype_vectors):
        return None

    raw_index = max(range(len(generic)), key=generic.__getitem__)
    raw_label = vocabulary[raw_index]
    expected_baseline = raw_label if raw_label in allowed else None
    maximum = max(matcher)
    winners = [index for index, value in enumerate(matcher) if value == maximum]
    if (
        baseline != expected_baseline
        or proposal is None
        or proposal not in allowed
        or len(winners) != 1
        or winners[0] >= len(prototype_labels)
        or prototype_labels[winners[0]] != proposal
    ):
        return None

    probabilities = _probabilities(generic)
    if probabilities is None:
        return None
    ordered = sorted(probabilities, reverse=True)
    entropy = -sum(value * math.log(value) for value in probabilities if value > 0) / math.log(len(probabilities))
    proposal_index = vocabulary.index(proposal)
    winner = winners[0]
    defer_index = len(prototype_labels)
    other_match = [matcher[index] for index in range(len(prototype_labels)) if index != winner]
    proposed_cosine = max(-1.0, min(1.0, sum(a * b for a, b in zip(query, prototype_vectors[winner]))))
    other_cosines = [sum(a * b for a, b in zip(query, row))
                     for index, row in enumerate(prototype_vectors) if index != winner]
    result = [
        probabilities[proposal_index],
        ordered[0],
        ordered[0] - ordered[1],
        entropy,
        1.0 if baseline is not None else 0.0,
        1.0 if proposal == baseline else 0.0,
        matcher[winner] - matcher[defer_index],
        matcher[winner] - max(other_match) if other_match else 0.0,
        proposed_cosine,
        proposed_cosine - max(other_cosines) if other_cosines else 0.0,
    ]
    return result if len(result) == FEATURE_COUNT and all(math.isfinite(value) for value in result) else None


def action_target(baseline: str | None, proposal: str | None, truth: str) -> int:
    """Loss-only utility target; truth is never an inference input."""

    if not _token(baseline, optional=True) or not _token(proposal, optional=True) or not _token(truth):
        raise ValueError("Invalid action-target label")
    if proposal is not None and proposal == truth and baseline != truth:
        return HELP
    if proposal is not None and proposal != truth and baseline in (None, truth):
        return HARM
    return NEUTRAL


def select_output(
    baseline: str | None,
    proposal: str | None,
    action_logits: Sequence[float],
    allowed: Collection[str],
) -> str | None:
    """Choose only a unique finite HELP winner; otherwise preserve baseline."""

    if not _token(baseline, optional=True):
        raise ValueError("Invalid baseline")
    if (
        proposal is None
        or not _token(proposal)
        or not isinstance(allowed, Collection)
        or isinstance(allowed, (str, bytes))
        or proposal not in allowed
    ):
        return baseline
    logits = _finite_vector(action_logits, ACTION_COUNT)
    if logits is None:
        return baseline
    maximum = max(logits)
    winners = [index for index, value in enumerate(logits) if value == maximum]
    return proposal if winners == [HELP] else baseline


def _feature_matrix(rows: Sequence[Sequence[float]]) -> list[list[float]]:
    if not isinstance(rows, Sequence) or isinstance(rows, (str, bytes)) or not 1 <= len(rows) <= MAX_ROWS:
        raise ValueError("Bounded nonempty feature rows required")
    result = []
    for row in rows:
        vector = _finite_vector(row, FEATURE_COUNT)
        if vector is None:
            raise ValueError("Finite ten-column feature rows required")
        result.append(list(vector))
    return result


def fit_action_selector(
    features: Sequence[Sequence[float]],
    targets: Sequence[int],
    sample_weights: Sequence[float],
) -> dict[str, object]:
    """Fit one deterministic class-macro linear selector on caller-weighted rows.

    The caller must compute inverse source-exposure weights using only eligible
    no-copy meta-fit rows.  This boundary intentionally accepts no identities,
    labels, truth strings, evaluation rows, or selection thresholds.
    """

    matrix = _feature_matrix(features)
    if (
        not isinstance(targets, Sequence)
        or isinstance(targets, (str, bytes))
        or not isinstance(sample_weights, Sequence)
        or isinstance(sample_weights, (str, bytes))
        or len(targets) != len(matrix)
        or len(sample_weights) != len(matrix)
        or any(type(target) is not int or target not in range(ACTION_COUNT) for target in targets)
        or any(isinstance(weight, bool) or not isinstance(weight, (int, float))
               or not math.isfinite(weight) or weight <= 0 for weight in sample_weights)
        or set(targets) != set(range(ACTION_COUNT))
    ):
        raise ValueError("Complete HELP/HARM/NEUTRAL weighted fit rows required")

    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    values = torch.tensor(matrix, dtype=torch.float64, device="cpu")
    target = torch.tensor(list(targets), dtype=torch.long, device="cpu")
    weights = torch.tensor([float(value) for value in sample_weights], dtype=torch.float64, device="cpu")
    total_weight = weights.sum()
    mean = (values * weights[:, None]).sum(dim=0) / total_weight
    variance = ((values - mean).square() * weights[:, None]).sum(dim=0) / total_weight
    scale = variance.sqrt()
    scale = torch.where(scale == 0, torch.ones_like(scale), scale)
    normalized = (values - mean) / scale
    if not bool(torch.isfinite(normalized).all()):
        raise ValueError("Invalid normalized fit features")

    linear_weights = torch.zeros((ACTION_COUNT, FEATURE_COUNT), dtype=torch.float64, requires_grad=True)
    bias = torch.zeros(ACTION_COUNT, dtype=torch.float64, requires_grad=True)
    optimizer = torch.optim.Adam((linear_weights, bias), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    trace = []
    for _ in range(STEPS):
        optimizer.zero_grad(set_to_none=True)
        logits = normalized @ linear_weights.T + bias
        per_row = F.cross_entropy(logits, target, reduction="none")
        class_losses = []
        for action in range(ACTION_COUNT):
            mask = target == action
            class_weights = weights[mask]
            class_losses.append((per_row[mask] * class_weights).sum() / class_weights.sum())
        loss = torch.stack(class_losses).mean()
        if not bool(torch.isfinite(loss)):
            raise ValueError("Nonfinite selector loss")
        loss.backward()
        if linear_weights.grad is None or bias.grad is None or not (
            bool(torch.isfinite(linear_weights.grad).all()) and bool(torch.isfinite(bias.grad).all())
        ):
            raise ValueError("Invalid selector gradient")
        optimizer.step()
        if not (bool(torch.isfinite(linear_weights).all()) and bool(torch.isfinite(bias).all())):
            raise ValueError("Nonfinite selector state")
        trace.append(float(loss.detach()))

    class_counts = [sum(target == action for target in targets) for action in range(ACTION_COUNT)]
    class_weight_sums = [sum(float(weight) for target, weight in zip(targets, sample_weights) if target == action)
                         for action in range(ACTION_COUNT)]
    return {
        "version": VERSION,
        "featureNames": list(FEATURE_NAMES),
        "actionNames": list(ACTION_NAMES),
        "weights": linear_weights.detach().tolist(),
        "bias": bias.detach().tolist(),
        "featureMean": mean.tolist(),
        "featureStd": scale.tolist(),
        "trace": trace,
        "fit": {
            "rows": len(matrix),
            "classCounts": class_counts,
            "classWeightSums": class_weight_sums,
            "steps": STEPS,
            "optimizer": "Adam",
            "learningRate": LEARNING_RATE,
            "weightDecay": WEIGHT_DECAY,
            "dtype": "float64",
            "cpuThreads": 4,
            "deterministicAlgorithms": True,
            "selection": "final-only",
        },
    }


def action_logits(features: Sequence[Sequence[float]], state: dict[str, object]) -> list[list[float]]:
    """Apply one frozen serializable selector state to truth-free feature rows."""

    matrix = _feature_matrix(features)
    required = {"version", "featureNames", "actionNames", "weights", "bias", "featureMean",
                "featureStd", "trace", "fit"}
    if not isinstance(state, dict) or set(state) != required or state.get("version") != VERSION \
            or state.get("featureNames") != list(FEATURE_NAMES) or state.get("actionNames") != list(ACTION_NAMES):
        raise ValueError("Invalid selector state identity")
    means = _finite_vector(state["featureMean"], FEATURE_COUNT)
    scales = _finite_vector(state["featureStd"], FEATURE_COUNT)
    bias = _finite_vector(state["bias"], ACTION_COUNT)
    raw_weights = state["weights"]
    if means is None or scales is None or bias is None or any(scale <= 0 for scale in scales) \
            or not isinstance(raw_weights, Sequence) or len(raw_weights) != ACTION_COUNT:
        raise ValueError("Invalid selector normalization/state")
    learned = tuple(_finite_vector(row, FEATURE_COUNT) for row in raw_weights)
    if any(row is None for row in learned):
        raise ValueError("Invalid selector weights")
    result = []
    for row in matrix:
        normalized = [(value - mean) / scale for value, mean, scale in zip(row, means, scales)]
        logits = [sum(weight * value for weight, value in zip(weights, normalized)) + intercept
                  for weights, intercept in zip(learned, bias)]
        if not all(math.isfinite(value) for value in logits):
            raise ValueError("Nonfinite selector output")
        result.append(logits)
    return result

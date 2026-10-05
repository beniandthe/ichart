"""Pure all-class centroid transport; no corpus runner, fitting or app adapter."""
from __future__ import annotations

from pathlib import Path

import torch
from torch import nn
from torch.nn import functional as F

from .personal_support_retrieval import require, sha

PROTOCOL = "docs/personal-centroid-transport-protocol-2026-10-01.md"
PROTOCOL_SHA256 = "0ab2689ae4042e855470ccbce08c1df289a71c1629190c8d6870e0f008fd4769"
VERSION, CLASSES, SEED = "personal-centroid-transport-v1", 97, 41


def code_identity():
    root = Path(__file__).resolve().parents[3]
    paths = (PROTOCOL, "recognition_ml/ichart_recognition_ml/research/personal_centroid_transport.py",
        "recognition_ml/tests/test_personal_centroid_transport.py",
        "recognition_ml/ichart_recognition_ml/research/personal_support_retrieval.py")
    result = {path: sha((root / path).read_bytes()) for path in paths}
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Centroid transport protocol changed")
    return result


def _matrix(tensor):
    require(isinstance(tensor, torch.Tensor) and tensor.ndim == 2 and tensor.dtype == torch.float64
        and tensor.device.type == "cpu" and bool(torch.isfinite(tensor).all()), "Finite CPU float64 matrix required")


def validate_inputs(centroids, support, labels, query, logits):
    for tensor in (centroids, support, query, logits):
        _matrix(tensor)
    count, width = support.shape
    require(0 <= count <= 192 and 1 <= width <= 2048 and 1 <= len(query) <= 4096
        and centroids.shape == (CLASSES, width) and query.shape[1] == width and logits.shape == (len(query), CLASSES)
        and isinstance(labels, torch.Tensor) and labels.dtype == torch.long and labels.device.type == "cpu"
        and labels.shape == (count,) and (not count or 0 <= int(labels.min()) <= int(labels.max()) < CLASSES),
        "Full97 centroid/support/query contract required")
    require(all(bool((torch.abs(t.norm(dim=1) - 1) <= 1e-3).all()) for t in (centroids, support, query)),
        "Unit centroids and feature vectors required")


def transported_centroids(centroids, support, labels):
    """Exact-copy deduplication then equal weight per explicitly taught class."""
    _matrix(centroids); _matrix(support)
    require(centroids.shape[0] == CLASSES and centroids.shape[1] == support.shape[1] and 1 <= len(support) <= 192
        and isinstance(labels, torch.Tensor) and labels.dtype == torch.long and labels.device.type == "cpu"
        and labels.shape == (len(support),) and 0 <= int(labels.min()) <= int(labels.max()) < CLASSES
        and all(bool((torch.abs(t.norm(dim=1) - 1) <= 1e-3).all()) for t in (centroids, support)),
        "Nonempty unit labeled support required")
    centroids, support = centroids.detach(), support.detach()
    unique = torch.unique(torch.cat((support, labels[:, None].double()), dim=1), dim=0)
    features, unique_labels = unique[:, :-1], unique[:, -1].long()
    style = torch.stack([features[unique_labels == label].mean(0) - centroids[label]
        for label in unique_labels.unique().tolist()]).mean(0)
    shifted = centroids + style
    norms = shifted.norm(dim=1, keepdim=True)
    require(bool((norms > 0).all()) and bool(torch.isfinite(norms).all()), "Degenerate transported centroid")
    transported = shifted / norms
    require(bool(torch.isfinite(transported).all()), "Nonfinite transported centroid")
    return transported, style


class CentroidTransport(nn.Module):
    """Shared scalar scorer only: no class, writer or embedding-axis weights."""
    def __init__(self):
        super().__init__()
        with torch.random.fork_rng():
            torch.manual_seed(SEED)
            self.scorer = nn.Sequential(nn.Linear(4, 32), nn.Tanh(), nn.Linear(32, 1)).double()
        nn.init.zeros_(self.scorer[-1].weight)
        nn.init.zeros_(self.scorer[-1].bias)

    def adapted_logits(self, centroids, support, labels, query, logits):
        validate_inputs(centroids, support, labels, query, logits)
        if not len(support):
            return logits
        transported, _ = transported_centroids(centroids, support, labels)
        generic, original = logits.detach(), query.detach() @ centroids.detach().T
        moved = query.detach() @ transported.T
        x = torch.stack((generic, original, moved, moved - original), dim=2)
        empty = torch.stack((generic, original, original, torch.zeros_like(original)), dim=2)
        residual = (self.scorer(x) - self.scorer(empty)).squeeze(2)
        residual = residual - residual.mean(1, keepdim=True)
        result = generic + residual
        _matrix(result)
        return result

    def probabilities(self, centroids, support, labels, query, logits):
        result = self.adapted_logits(centroids, support, labels, query, logits).softmax(1)
        require(bool(torch.isfinite(result).all()) and bool((torch.abs(result.sum(1) - 1) <= 1e-8).all()),
            "Invalid full97 probabilities")
        return result


def training_objective(candidate_logits, generic_logits, unrelated_logits, targets, taught):
    """Supervised loss only; answers never enter the candidate forward interface."""
    for logits in (candidate_logits, generic_logits, unrelated_logits):
        _matrix(logits)
    require(candidate_logits.shape == generic_logits.shape == unrelated_logits.shape
        and candidate_logits.shape[1] == CLASSES and len(candidate_logits) > 0
        and isinstance(targets, torch.Tensor) and targets.dtype == torch.long and targets.device.type == "cpu"
        and isinstance(taught, torch.Tensor) and taught.dtype == torch.bool and taught.device.type == "cpu"
        and targets.shape == taught.shape == (len(candidate_logits),) and 0 <= int(targets.min()) <= int(targets.max()) < CLASSES
        and bool(taught.any()) and bool((~taught).any()), "Both supervised full97 query strata required")
    generic = generic_logits.detach()
    rows = torch.arange(len(targets))
    other = F.one_hot(targets, CLASSES).bool()
    generic_truth, candidate_truth = generic[rows, targets], candidate_logits[rows, targets]
    correct = generic_truth == generic.max(1).values  # All exact tied maxima protected.
    generic_margin = generic_truth - generic.masked_fill(other, -torch.inf).max(1).values
    candidate_margin = candidate_truth - candidate_logits.masked_fill(other, -torch.inf).max(1).values
    preservation = F.relu(generic_margin[correct] - candidate_margin[correct]).mean() if bool(correct.any()) else candidate_logits.sum() * 0
    nll = -candidate_logits.log_softmax(1)[rows, targets]
    balanced_ce = .5 * nll[taught].mean() + .5 * nll[~taught].mean()
    log_generic = generic.log_softmax(1)
    wrong_writer_kl = (log_generic.exp() * (log_generic - unrelated_logits.log_softmax(1))).sum(1).mean()
    total = balanced_ce + preservation + wrong_writer_kl
    require(bool(torch.isfinite(total)), "Nonfinite centroid objective")
    return total, {"balancedCE": balanced_ce, "preservationMargin": preservation, "unrelatedSupportKL": wrong_writer_kl}

"""Disjoint learned stages for internal reuse selection, never fresh evidence."""
from __future__ import annotations

from .personal_support_retrieval import canonical, sha, require

VERSION = "personal-support-inner-reuse-roles-v1"
INPUT_HASHES = ("metadataSHA256", "featuresSHA256", "sourceSHA256", "protocolSHA256")


def inner_roles(receipt, rows):
    """Use one generator only; never cross another learned writer stage.

    Existing B-fold order is already source-hash-defined by crossfit. These
    rows were used in earlier research: disjointness does not restore freshness.
    This creates no selection rule, new model, or advancement permission.
    """
    vocabulary = receipt["vocabulary"]
    folds = receipt["folds"]
    fit, exported = list(folds["A"]), list(folds["B"])
    train = receipt["trainingWriters"]
    excluded = set(receipt["developmentWriters"]) | set(receipt["reservedWriters"])
    require(len(vocabulary) == len(set(vocabulary)) == 97 and vocabulary == sorted(vocabulary),
            "Full ordered vocabulary required")
    require(len(train) == len(set(train)) == 32 and all(w.startswith("trn_") for w in train)
            and len(fit) == len(set(fit)) == len(exported) == len(set(exported)) == 16
            and not set(fit) & set(exported) and set(fit) | set(exported) == set(train)
            and not set(train) & excluded, "Writer roles overlap or leave training pool")
    ranked = sorted(train, key=lambda w: sha(("personal-support-retrieval-v1:fold:" + w).encode()))
    require(fit == ranked[:16] and exported == ranked[16:], "Source-only fold order changed")
    require(len(rows) == 6208 and len({r["sourceID"] for r in rows}) == 6208
            and {(r["writer"], r["session"], r["label"]) for r in rows}
            == {(w, s, c) for w in train for s in (1, 2) for c in vocabulary}
            and all(r["generator"] == ("fitA" if r["writer"] in exported else "fitB") for r in rows),
            "Incomplete or mismatched source/generator grid")
    require(set(receipt["weightsSHA256"]) == {"fitA", "fitB"}
            and all(isinstance(h, str) and len(h) == 64 and all(c in "0123456789abcdef" for c in h)
                    for h in receipt["weightsSHA256"].values()), "Invalid generator binding")
    require(isinstance(receipt["codeSHA256"], dict) and bool(receipt["codeSHA256"])
            and all(isinstance(h, str) and len(h) == 64 and all(c in "0123456789abcdef" for c in h)
                    for h in [*(receipt[key] for key in INPUT_HASHES), *receipt["codeSHA256"].values()]),
            "Invalid parent artifact/code binding")
    partitions = {"metaFit": exported[:8], "internalValidation": exported[8:]}
    indices = {name: [i for i, row in enumerate(rows) if row["writer"] in writers]
               for name, writers in partitions.items()}
    require(all(len(value) == 1552 for value in indices.values())
            and not set(indices["metaFit"]) & set(indices["internalValidation"]), "Internal row partition overlap")
    return {"version": VERSION, "generator": "fitA", "generatorWeightsSHA256": receipt["weightsSHA256"]["fitA"],
            "crossfitReceiptSHA256": sha(canonical(receipt)),
            "parentInputsSHA256": {key: receipt[key] for key in INPUT_HASHES},
            "parentCodeSHA256": dict(receipt["codeSHA256"]),
            "encoderFitWriters": fit, "metaFitWriters": partitions["metaFit"],
            "internalValidationWriters": partitions["internalValidation"], "sourceIndices": indices,
            "rowCounts": {key: len(value) for key, value in indices.items()},
            "roleRowsSHA256": sha(canonical([{key: row[key] for key in
                ("sourceID", "writer", "session", "label", "generator")} for row in rows])),
            "allLearnedStageWriterSetsDisjoint": True, "otherGeneratorUsed": False,
            "previouslyUsedInAllWriterLearnerFit": True, "freshValidation": False,
            "candidateSelected": False, "modelFitted": False, "productionEligible": False,
            "claimCeiling": "writer-disjoint internal reuse/selection only; not fresh or confirmatory accuracy"}

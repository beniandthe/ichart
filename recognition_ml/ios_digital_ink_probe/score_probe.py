"""Offline scoring only. Expected answers never enter device inference."""
import argparse
import hashlib
import json
import math
import re
import statistics
from pathlib import Path


def notation(text):
    """Notation aliases only; no OCR substitutions or missing-symbol repair."""
    if not isinstance(text, str):
        return None
    value = "".join(text.split()).translate(str.maketrans({
        "♭": "b", "♯": "#", "Δ": "△", "−": "-", "–": "-"}))
    match = re.fullmatch(r"([A-Ga-g])([b#]?)(.*)", value)
    if not match:
        return value
    root, accidental, suffix = match.groups()
    # These are textual spellings of chord qualities, not inferred glyphs.
    suffix = re.sub(r"^(?:maj|M)(?=\d|$)", "△", suffix)
    suffix = re.sub(r"^(?:min|m)(?=\d|$)", "-", suffix)
    return root.upper() + accidental + suffix


def score(packet_bytes, report, labels):
    packet = json.loads(packet_bytes)
    ids = [item["id"] for item in packet]
    if not ids or len(ids) != len(set(ids)):
        raise ValueError("Packet must have distinct nonempty IDs")
    if (report.get("complete") is not True or report.get("inputCount") != len(ids)
            or report.get("inputSHA256") != hashlib.sha256(packet_bytes).hexdigest()):
        raise ValueError("Incomplete report or mismatched source packet")
    by_key = {}
    for row in report["rows"]:
        key = (row["id"], row["context"])
        if key in by_key:
            raise ValueError("Duplicate recognition result")
        if not math.isfinite(row["milliseconds"]) or row["milliseconds"] < 0:
            raise ValueError("Invalid inference duration")
        if any(not isinstance(candidate["text"], str) for candidate in row["candidates"]):
            raise ValueError("Malformed candidate")
        by_key[key] = row
    if set(by_key) != {(identity, context) for identity in ids for context in ("none", "bounds")}:
        raise ValueError("Missing, extra, or unexpected-context results")
    label_ids = [label["id"] for label in labels]
    if (not labels or len(label_ids) != len(set(label_ids)) or not set(label_ids) <= set(ids)
            or any(not isinstance(label.get("intended"), str) or not label["intended"].strip()
                   for label in labels)):
        raise ValueError("Labels must explicitly identify distinct captured inputs")

    comparisons = []
    for label in labels:
        for context in ("none", "bounds"):
            candidates = [candidate["text"] for candidate in by_key[label["id"], context]["candidates"]]
            expected = notation(label["intended"])
            rank = next((i + 1 for i, value in enumerate(candidates) if notation(value) == expected), None)
            comparisons.append({**label, "context": context, "candidates": candidates,
                "rawExactTop1": bool(candidates and candidates[0] == label["intended"]),
                "notationEquivalentTop1": rank == 1, "notationEquivalentRank": rank,
                "noCandidate": not candidates})
    totals = []
    for cohort in sorted({label.get("cohort", "all") for label in labels}):
        cohort_labels = [label for label in labels if label.get("cohort", "all") == cohort]
        for context in ("none", "bounds"):
            rows = [row for row in comparisons if row.get("cohort", "all") == cohort and row["context"] == context]
            totals.append({"cohort": cohort, "context": context, "count": len(rows),
                "rawExactTop1": sum(row["rawExactTop1"] for row in rows),
                "notationEquivalentTop1": sum(row["notationEquivalentTop1"] for row in rows),
                "notationEquivalentTop5": sum(row["notationEquivalentRank"] is not None
                                               and row["notationEquivalentRank"] <= 5 for row in rows),
                "notationEquivalentAnyCandidate": sum(row["notationEquivalentRank"] is not None for row in rows),
                "noCandidate": sum(row["noCandidate"] for row in rows),
                "nativeCorrect": (sum(label["native"] == label["intended"] for label in cohort_labels)
                                  if all("native" in label for label in cohort_labels) else None),
                "personalizedCorrect": (sum(label["personalized"] == label["intended"] for label in cohort_labels)
                                        if all("personalized" in label for label in cohort_labels) else None)})
    times = [row["milliseconds"] for row in report["rows"]]
    return {"scope": "development replay, one writer; not general accuracy or calibrated trust",
        "inputSHA256": report["inputSHA256"], "inputCount": len(ids), "labeledInputs": len(labels),
        "unlabeledInputs": len(ids) - len(labels), "totals": totals, "comparisons": comparisons,
        "inferenceMilliseconds": {"count": len(times), "median": statistics.median(times),
                                  "maximum": max(times), "includesFirstInference": True,
                                  "excludesDownloadAndAppInputLatency": True}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packet", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("labels", type=Path)
    args = parser.parse_args()
    result = score(args.packet.read_bytes(), json.loads(args.report.read_text()), json.loads(args.labels.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

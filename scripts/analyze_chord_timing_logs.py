#!/usr/bin/env python3
"""Summarize iChart chord timing console logs.

The parser is intentionally small and tolerant of Xcode/device-log prefixes. It
looks only for the Sprint 47/Sprint 48 debug labels:

- iChart chord timing
- iChart chord proposal
- iChart chord commit
- iChart chord render
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


PREFIXES = {
    "iChart chord timing:": "timing",
    "iChart chord proposal:": "proposal",
    "iChart chord commit:": "commit",
    "iChart chord render:": "render",
}


@dataclass
class Attempt:
    line_no: int
    timing: dict[str, str] = field(default_factory=dict)
    proposal: dict[str, str] = field(default_factory=dict)
    commit: dict[str, str] = field(default_factory=dict)
    render: dict[str, str] = field(default_factory=dict)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize iChart Sprint 47 chord timing console logs."
    )
    parser.add_argument(
        "logs",
        nargs="+",
        type=Path,
        help="Console log files copied from Xcode, Console, or device logging.",
    )
    parser.add_argument(
        "--format",
        choices=("markdown", "csv", "json"),
        default="markdown",
        help="Output format. Defaults to markdown.",
    )
    return parser.parse_args()


def matching_prefix(line: str) -> tuple[str, str, str] | None:
    for prefix, kind in PREFIXES.items():
        index = line.find(prefix)
        if index >= 0:
            payload = line[index + len(prefix) :].strip()
            return kind, prefix, payload
    return None


def parse_fields(payload: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for token in payload.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        fields[key] = value.rstrip(",")
    return fields


def parse_logs(paths: Iterable[Path]) -> list[Attempt]:
    attempts: list[Attempt] = []

    for path in paths:
        with path.open(errors="replace") as file:
            for line_no, line in enumerate(file, start=1):
                match = matching_prefix(line)
                if match is None:
                    continue

                kind, _prefix, payload = match
                fields = parse_fields(payload)
                fields["_source"] = str(path)
                fields["_line"] = str(line_no)

                if kind == "timing":
                    attempts.append(Attempt(line_no=line_no, timing=fields))
                elif kind == "proposal":
                    attempt = latest_without(attempts, "proposal")
                    if attempt is None:
                        attempt = Attempt(line_no=line_no)
                        attempts.append(attempt)
                    attempt.proposal = fields
                elif kind == "commit":
                    attempt = latest_without(attempts, "commit")
                    if attempt is None:
                        attempt = Attempt(line_no=line_no)
                        attempts.append(attempt)
                    attempt.commit = fields
                elif kind == "render":
                    attempt = latest_without(attempts, "render")
                    if attempt is None:
                        attempt = Attempt(line_no=line_no)
                        attempts.append(attempt)
                    attempt.render = fields

    return attempts


def latest_without(attempts: list[Attempt], field_name: str) -> Attempt | None:
    for attempt in reversed(attempts):
        if not getattr(attempt, field_name):
            return attempt
    return None


def value(attempt: Attempt, key: str, default: str = "") -> str:
    for bucket in (attempt.render, attempt.commit, attempt.proposal, attempt.timing):
        if key in bucket:
            return bucket[key]
    return default


def row_for_attempt(index: int, attempt: Attempt) -> dict[str, str]:
    return {
        "attempt": str(index),
        "best": value(attempt, "best"),
        "accepted": value(attempt, "accepted"),
        "confidence": value(attempt, "confidence"),
        "primaryAction": value(attempt, "primaryAction"),
        "finalAction": value(attempt, "finalAction"),
        "trust": value(attempt, "trust"),
        "agreement": value(attempt, "agreement"),
        "closeRace": value(attempt, "closeRace"),
        "gap": value(attempt, "gap"),
        "delayMs": value(attempt, "delay"),
        "idleMs": value(attempt, "idle"),
        "recognitionMs": value(attempt, "recognition"),
        "totalMs": value(attempt, "total"),
        "proposalMs": value(attempt, "decisionMs"),
        "commitMs": value(attempt, "commitMs"),
        "renderHandoffMs": value(attempt, "renderHandoffMs"),
        "ocrCount": value(attempt, "ocr"),
        "ocrMs": value(attempt, "ocrMs"),
        "reason": value(attempt, "reason"),
    }


def markdown_escape(text: str) -> str:
    return text.replace("|", "\\|")


def write_markdown(rows: list[dict[str, str]]) -> None:
    if not rows:
        print("No iChart chord timing lines found.")
        return

    columns = [
        "attempt",
        "best",
        "accepted",
        "confidence",
        "primaryAction",
        "finalAction",
        "trust",
        "agreement",
        "closeRace",
        "gap",
        "delayMs",
        "idleMs",
        "recognitionMs",
        "totalMs",
        "proposalMs",
        "commitMs",
        "renderHandoffMs",
        "ocrCount",
        "ocrMs",
        "reason",
    ]
    print("| " + " | ".join(columns) + " |")
    print("| " + " | ".join("---" for _ in columns) + " |")
    for row in rows:
        print("| " + " | ".join(markdown_escape(row.get(column, "")) for column in columns) + " |")

    print()
    print("Interpretation prompts:")
    print("- High delay/idle with low recognition/proposal/commit points at scheduling or waiting policy.")
    print("- High recognitionMs/totalMs points at recognizer compute or candidate conflict.")
    print("- Low recognition/proposal/commit with visible lag points at render/update handoff.")
    print("- High renderHandoffMs points at SwiftUI update/render handoff after chart mutation.")
    print("- Low confidence plus confirm/ambiguous final action points at trust/ink interpretation.")


def write_csv(rows: list[dict[str, str]]) -> None:
    columns = list(row_for_attempt(0, Attempt(line_no=0)).keys())
    writer = csv.DictWriter(sys.stdout, fieldnames=columns)
    writer.writeheader()
    writer.writerows(rows)


def main() -> int:
    args = parse_args()
    attempts = parse_logs(args.logs)
    rows = [row_for_attempt(index, attempt) for index, attempt in enumerate(attempts, start=1)]

    if args.format == "json":
        print(json.dumps(rows, indent=2))
    elif args.format == "csv":
        write_csv(rows)
    else:
        write_markdown(rows)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Import copied Smart Chart chord ink fixture JSON into the test fixture folder."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIXTURE_DIR = REPO_ROOT / "SmartChartTests" / "Fixtures" / "Ink"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Import fixture JSON copied from the Smart Chart chord confirmation "
            "sheet into SmartChartTests/Fixtures/Ink."
        )
    )
    parser.add_argument(
        "input",
        nargs="?",
        help="Path to fixture JSON. If omitted, reads stdin; with --clipboard, reads pbpaste.",
    )
    parser.add_argument(
        "--clipboard",
        action="store_true",
        help="Read fixture JSON from the macOS clipboard via pbpaste.",
    )
    parser.add_argument(
        "--simulator",
        metavar="DEVICE",
        help="Read fixture JSON from an iOS simulator pasteboard via xcrun simctl pbpaste.",
    )
    parser.add_argument(
        "--fixtures-dir",
        default=str(DEFAULT_FIXTURE_DIR),
        help="Destination fixture directory.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite an existing fixture file.",
    )
    return parser.parse_args()


def read_input(args: argparse.Namespace) -> str:
    if args.simulator:
        return subprocess.check_output(["xcrun", "simctl", "pbpaste", args.simulator], text=True)

    if args.clipboard:
        return subprocess.check_output(["pbpaste"], text=True)

    if args.input:
        return Path(args.input).read_text(encoding="utf-8")

    return sys.stdin.read()


def require_string(document: dict[str, Any], key: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Fixture JSON must include a non-empty string `{key}`.")

    return value.strip()


def validate_fixture(document: dict[str, Any]) -> tuple[str, str]:
    name = require_string(document, "name")
    expected_display_text = require_string(document, "expectedDisplayText")

    strokes = document.get("strokes")
    if not isinstance(strokes, list) or not strokes:
        raise ValueError("Fixture JSON must include a non-empty `strokes` array.")

    for index, stroke in enumerate(strokes):
        if not isinstance(stroke, dict):
            raise ValueError(f"Stroke {index + 1} must be an object.")

        points = stroke.get("points")
        if not isinstance(points, list) or not points:
            raise ValueError(f"Stroke {index + 1} must include a non-empty `points` array.")

    return name, expected_display_text


def safe_filename(name: str) -> str:
    sanitized = "".join(character for character in name if character.isalnum() or character in "-_")
    if not sanitized:
        raise ValueError("Fixture `name` does not contain any filename-safe characters.")

    return f"{sanitized}.json"


def fixture_fingerprint(document: dict[str, Any]) -> str:
    comparable = dict(document)
    comparable.pop("name", None)
    return json.dumps(comparable, sort_keys=True, separators=(",", ":"))


def existing_duplicate_path(fixtures_dir: Path, document: dict[str, Any]) -> Path | None:
    expected_display_text = require_string(document, "expectedDisplayText")
    fingerprint = fixture_fingerprint(document)

    for fixture_path in sorted(fixtures_dir.glob("*.json")):
        try:
            existing = json.loads(fixture_path.read_text(encoding="utf-8"))
        except Exception:
            continue

        if not isinstance(existing, dict):
            continue
        if existing.get("expectedDisplayText") != expected_display_text:
            continue
        if fixture_fingerprint(existing) == fingerprint:
            return fixture_path

    return None


def unique_fixture_path(fixtures_dir: Path, document: dict[str, Any], force: bool) -> Path:
    name = require_string(document, "name")
    fixture_path = fixtures_dir / safe_filename(name)

    if force or not fixture_path.exists():
        return fixture_path

    base_name = name
    for index in range(1, 1000):
        candidate_name = f"{base_name}Captured{index:02d}"
        candidate_path = fixtures_dir / safe_filename(candidate_name)
        if not candidate_path.exists():
            document["name"] = candidate_name
            return candidate_path

    raise FileExistsError(f"Could not find an available captured fixture name for {name}.")


def main() -> int:
    args = parse_args()

    try:
        raw_json = read_input(args)
        document = json.loads(raw_json)
        if not isinstance(document, dict):
            raise ValueError("Fixture JSON must be an object.")

        name, expected_display_text = validate_fixture(document)
        fixtures_dir = Path(args.fixtures_dir).resolve()
        fixtures_dir.mkdir(parents=True, exist_ok=True)

        if not args.force:
            duplicate_path = existing_duplicate_path(fixtures_dir, document)
            if duplicate_path is not None:
                try:
                    display_path = duplicate_path.relative_to(REPO_ROOT)
                except ValueError:
                    display_path = duplicate_path
                print(f"Skipped duplicate fixture for {expected_display_text}; already imported at {display_path}")
                return 0

        fixture_path = unique_fixture_path(fixtures_dir, document, args.force)
        name = require_string(document, "name")

        if fixture_path.exists() and not args.force:
            raise FileExistsError(f"{fixture_path} already exists. Re-run with --force to overwrite.")

        fixture_path.write_text(
            json.dumps(document, indent=2, sort_keys=False) + "\n",
            encoding="utf-8",
        )
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    try:
        display_path = fixture_path.relative_to(REPO_ROOT)
    except ValueError:
        display_path = fixture_path

    print(f"Imported {name} ({expected_display_text}) -> {display_path}")
    print("Run: swift test --scratch-path /tmp/SmartChartSwiftBuild --filter ChordInkRecognizerTests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

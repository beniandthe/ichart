#!/usr/bin/env python3
"""Watch an iOS simulator pasteboard and import copied chord ink fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
IMPORTER = REPO_ROOT / "scripts" / "import_chord_fixture.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import iChart chord fixture JSON as soon as the app copies it."
    )
    parser.add_argument(
        "--simulator",
        metavar="DEVICE",
        help="Simulator UDID. Defaults to the first booted simulator.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Polling interval in seconds.",
    )
    parser.add_argument(
        "--clear-on-start",
        action="store_true",
        help="Clear the simulator pasteboard before watching.",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Import one fixture and exit.",
    )
    return parser.parse_args()


def booted_simulator_id() -> str:
    output = subprocess.check_output(["xcrun", "simctl", "list", "devices", "booted", "-j"], text=True)
    data = json.loads(output)

    devices = data.get("devices", {})
    for runtime_devices in devices.values():
        for device in runtime_devices:
            if device.get("state") == "Booted" and isinstance(device.get("udid"), str):
                return device["udid"]

    raise RuntimeError("No booted simulator found. Boot the iPad simulator first.")


def clear_pasteboard(device_id: str) -> None:
    subprocess.run(["xcrun", "simctl", "pbcopy", device_id], input="", text=True, check=False)


def read_pasteboard(device_id: str) -> str:
    result = subprocess.run(
        ["xcrun", "simctl", "pbpaste", device_id],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.stdout


def is_fixture_json(raw_json: str) -> bool:
    try:
        document: Any = json.loads(raw_json)
    except json.JSONDecodeError:
        return False

    return (
        isinstance(document, dict)
        and isinstance(document.get("expectedDisplayText"), str)
        and isinstance(document.get("strokes"), list)
        and bool(document["strokes"])
    )


def import_fixture(raw_json: str) -> bool:
    result = subprocess.run(
        [sys.executable, str(IMPORTER)],
        input=raw_json,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=REPO_ROOT,
        check=False,
    )

    if result.stdout:
        print(result.stdout.strip(), flush=True)
    if result.stderr:
        print(result.stderr.strip(), file=sys.stderr, flush=True)

    return result.returncode == 0


def main() -> int:
    args = parse_args()

    try:
        device_id = args.simulator or booted_simulator_id()
        if args.clear_on_start:
            clear_pasteboard(device_id)
        print(f"Watching simulator pasteboard for chord fixtures: {device_id}", flush=True)
        print("Copy a Test Fixture in iChart; press Ctrl-C here when the pass is done.", flush=True)

        last_hash = ""
        while True:
            raw_json = read_pasteboard(device_id)
            digest = hashlib.sha256(raw_json.encode("utf-8")).hexdigest()
            if raw_json and digest != last_hash and is_fixture_json(raw_json):
                last_hash = digest
                if import_fixture(raw_json) and args.once:
                    return 0

            time.sleep(max(args.interval, 0.2))
    except KeyboardInterrupt:
        print("\nStopped watcher.", flush=True)
        return 0
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

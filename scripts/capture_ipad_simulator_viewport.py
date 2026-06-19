#!/usr/bin/env python3
"""Capture an iPad simulator screenshot at native or requested orientation."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run(command: list[str], *, text: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, capture_output=True, text=text)


def booted_device_id() -> str:
    result = run(["xcrun", "simctl", "list", "devices", "booted", "-j"])
    payload = json.loads(result.stdout)
    for devices in payload.get("devices", {}).values():
        for device in devices:
            if device.get("state") == "Booted":
                return str(device["udid"])
    raise RuntimeError("No booted simulator found.")


def image_size(path: Path) -> tuple[int, int]:
    result = run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)])
    width: int | None = None
    height: int | None = None
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("pixelWidth:"):
            width = int(stripped.split(":", 1)[1].strip())
        elif stripped.startswith("pixelHeight:"):
            height = int(stripped.split(":", 1)[1].strip())
    if width is None or height is None:
        raise RuntimeError(f"Could not read image size for {path}")
    return width, height


def normalize_orientation(path: Path, orientation: str) -> None:
    if orientation == "native":
        return

    width, height = image_size(path)
    if orientation == "landscape" and width < height:
        run(["sips", "-r", "-90", str(path), "--out", str(path)])
    elif orientation == "portrait" and width > height:
        run(["sips", "-r", "90", str(path), "--out", str(path)])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-id", help="Simulator UDID. Defaults to the first booted simulator.")
    parser.add_argument(
        "--orientation",
        choices=("native", "landscape", "portrait"),
        default="native",
        help="Output orientation. Native preserves the simulator framebuffer exactly.",
    )
    parser.add_argument(
        "--output",
        default="/tmp/ichart-ipad-simulator.png",
        help="Output PNG path.",
    )
    parser.add_argument("--open", action="store_true", help="Open the normalized capture with macOS.")
    args = parser.parse_args()

    device_id = args.device_id or booted_device_id()
    output_path = Path(args.output).expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    run(["xcrun", "simctl", "io", device_id, "screenshot", str(output_path)])
    normalize_orientation(output_path, args.orientation)

    width, height = image_size(output_path)
    print(f"{output_path} ({width} x {height})")

    if args.open:
        subprocess.run(["open", str(output_path)], check=False)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)

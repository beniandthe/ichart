#!/usr/bin/env bash
set -euo pipefail

simulator_payload="$(xcrun simctl list devices available -j)"
destination="$(
  SIMCTL_JSON="$simulator_payload" python3 - <<'PY'
import json
import os
import re
import sys

payload = json.loads(os.environ["SIMCTL_JSON"])
candidates = []
runtime_pattern = re.compile(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)")
uuid_pattern = re.compile(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")

for runtime, devices in payload.get("devices", {}).items():
    match = runtime_pattern.fullmatch(runtime)
    if match is None:
        continue
    version = tuple(int(component) for component in match.group(1).split("-"))
    version += (0,) * max(0, 4 - len(version))

    for device in devices:
        if device.get("isAvailable") is not True:
            continue

        udid = device.get("udid")
        # The mounted keyboard regressions require a real 820-by-1180 scene.
        # UIWindow cannot resize a 13-inch simulator into that physical fixture.
        if device.get("name") == "iPad (A16)" and isinstance(udid, str) and uuid_pattern.fullmatch(udid):
            candidates.append((version, runtime, udid))

if candidates:
    newest_version = max(version for version, _, _ in candidates)
    # A deterministic UUID tie-breaker keeps JSON ordering from changing the
    # selected device when a runner contains duplicate fixtures.
    _, selected_udid = min((runtime, udid) for version, runtime, udid in candidates
                           if version == newest_version)
    print(f"platform=iOS Simulator,id={selected_udid}")
    sys.exit(0)

print("No available iPad (A16) simulator was found on this runner. "
      "The keyboard and viewport regressions require its 820-by-1180 scene.", file=sys.stderr)
sys.exit(1)
PY
)"

echo "SIMULATOR_DESTINATION=$destination"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "SIMULATOR_DESTINATION=$destination" >> "$GITHUB_ENV"
fi

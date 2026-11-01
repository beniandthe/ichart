"""Select a CI fixture from fake simctl data; never contact a live Simulator."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SELECTOR = Path(__file__).with_name("select-ipad-simulator.sh")
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-"
A16_ID = "00000000-0000-4000-8000-000000000016"
OTHER_ID = "00000000-0000-4000-8000-000000000013"

MOCK_XCRUN = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
Path(os.environ["ICHART_SELECTOR_CALLS"]).write_text(json.dumps(args))
assert args == ["simctl", "list", "devices", "available", "-j"], args
failure = int(os.environ.get("ICHART_SELECTOR_FAILURE", "0"))
if failure:
    sys.exit(failure)
print(Path(os.environ["ICHART_SELECTOR_PAYLOAD"]).read_text())
'''


def device(name="iPad (A16)", udid=A16_ID, available=True):
    return dict(name=name, udid=udid, isAvailable=available, state="Shutdown")


class SimulatorSelectionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ichart-sim-selector-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        executable = self.directory / "xcrun"
        executable.write_text(MOCK_XCRUN)
        executable.chmod(0o755)
        self.payload = self.directory / "devices.json"
        self.calls = self.directory / "calls.json"
        self.github_env = self.directory / "github-env"
        self.github_env.write_text("EXISTING_VALUE=keep\n")
        self.environment = dict(os.environ,
                                PATH=str(self.directory) + os.pathsep + os.environ["PATH"],
                                GITHUB_ENV=str(self.github_env),
                                ICHART_SELECTOR_PAYLOAD=str(self.payload),
                                ICHART_SELECTOR_CALLS=str(self.calls))

    def select(self, devices, expected_status=0, failure=0):
        self.payload.write_text(json.dumps(dict(devices=devices)))
        environment = dict(self.environment, ICHART_SELECTOR_FAILURE=str(failure))
        result = subprocess.run(["bash", str(SELECTOR)], env=environment,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, expected_status, result.stderr)
        self.assertEqual(json.loads(self.calls.read_text()),
                         ["simctl", "list", "devices", "available", "-j"])
        return result

    def test_requires_a16_instead_of_air_or_pro_before_it(self):
        result = self.select({RUNTIME + "26-4": [
            device("iPad Air 13-inch", OTHER_ID),
            device("iPad Pro 13-inch", "00000000-0000-4000-8000-000000000014"),
            device(),
        ]})
        destination = "SIMULATOR_DESTINATION=platform=iOS Simulator,id=" + A16_ID
        self.assertEqual(result.stdout, destination + "\n")
        self.assertEqual(self.github_env.read_text(), "EXISTING_VALUE=keep\n" + destination + "\n")

    def test_ignores_unavailable_and_non_ios_fixtures(self):
        result = self.select({
            "com.apple.CoreSimulator.SimRuntime.tvOS-99-0": [device(udid=OTHER_ID)],
            "custom-iOS-99-0": [device(udid=OTHER_ID)],
            RUNTIME + "99-0": [device(udid=OTHER_ID, available=False)],
            RUNTIME + "26-4": [device()],
        })
        self.assertIn("id=" + A16_ID, result.stdout)

    def test_selects_newest_numeric_runtime_independent_of_payload_order(self):
        fixtures = [
            (RUNTIME + "26-9", [device(udid=OTHER_ID)]),
            (RUNTIME + "26-10", [device()]),
            (RUNTIME + "26-8-1", [device(udid="00000000-0000-4000-8000-000000000012")]),
        ]
        for ordered in (fixtures, list(reversed(fixtures))):
            with self.subTest(order=[runtime for runtime, _ in ordered]):
                result = self.select(dict(ordered))
                self.assertIn("id=" + A16_ID, result.stdout)

    def test_duplicate_fixture_selection_has_deterministic_uuid_tie_breaker(self):
        fixtures = [device(udid=OTHER_ID), device()]
        for ordered in (fixtures, list(reversed(fixtures))):
            with self.subTest(order=[row["udid"] for row in ordered]):
                result = self.select({RUNTIME + "26-4-1": ordered})
                self.assertIn("id=" + OTHER_ID, result.stdout)

    def test_missing_compatible_fixture_fails_without_exporting_destination(self):
        result = self.select({RUNTIME + "26-4": [device("iPad Air 13-inch", OTHER_ID)]},
                             expected_status=1)
        self.assertIn("No available iPad (A16)", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.github_env.read_text(), "EXISTING_VALUE=keep\n")

    def test_malformed_uuid_cannot_be_exported(self):
        self.select({RUNTIME + "26-4": [device(udid="bad\nINJECTED_VALUE=yes")]}, expected_status=1)
        self.assertEqual(self.github_env.read_text(), "EXISTING_VALUE=keep\n")

    def test_simctl_failure_is_preserved_without_exporting_destination(self):
        self.select({}, expected_status=42, failure=42)
        self.assertEqual(self.github_env.read_text(), "EXISTING_VALUE=keep\n")


if __name__ == "__main__":
    unittest.main()

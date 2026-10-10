"""Run the Bash wrapper against fake CLIs; never contact a live Simulator."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import textwrap
import time
import unittest


SIMULATOR_ID = "12345678-1234-1234-1234-123456789ABC"
DESTINATION = "platform=iOS Simulator,id=" + SIMULATOR_ID
WRAPPER = Path(__file__).with_name("with-simulator-accessibility.sh")

MOCK_CLI = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import plistlib
import signal
import sys
import time

state_path = Path(os.environ["ICHART_SIMULATOR_TEST_STATE"])
log_path = Path(os.environ["ICHART_SIMULATOR_TEST_LOG"])
state = json.loads(state_path.read_text())

def record(name, args):
    with log_path.open("a") as output:
        output.write(json.dumps([name, args]) + "\n")

def save():
    state_path.write_text(json.dumps(state))

def fail(flag, code):
    if state.get(flag):
        sys.exit(code)

name = Path(sys.argv[0]).name
args = sys.argv[1:]
record(name, args)
if name == "xcodebuild":
    def cancelled(received, frame):
        record("test_signal", [received])
        if state.get("ignore_cancellation"):
            return
        sys.exit(128 + received)
    signal.signal(signal.SIGINT, cancelled)
    signal.signal(signal.SIGTERM, cancelled)
    if "command_preference" in state:
        state["preference"] = state["command_preference"]
        save()
    Path(os.environ["ICHART_SIMULATOR_TEST_STARTED"]).write_text(str(os.getpid()))
    if state.get("command_wait"):
        while True:
            time.sleep(0.05)
    sys.exit(state.get("command_exit", 0))

assert name == "xcrun" and args[0] == "simctl", args
if args[1:5] == ["list", "devices", "available", "-j"]:
    fail("list_failure", 30)
    print(json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-4-1": [
        {"udid": "12345678-1234-1234-1234-123456789ABC", "name": "iPad Air",
         "isAvailable": True, "state": state.get("boot_state", "Booted")}
    ]}}))
    sys.exit(0)

assert args[2] == "12345678-1234-1234-1234-123456789ABC", args
if args[1] == "boot":
    fail("boot_failure", 31)
    state["boot_state"] = "Booted"
    save()
    sys.exit(0)
if args[1] == "bootstatus":
    assert args[3:] == ["-b"], args
    fail("bootstatus_failure", 32)
    sys.exit(0)

assert args[1] == "spawn" and args[3] == "defaults", args
operation = args[4]
if operation == "domains":
    fail("domains_failure", 33)
    if state.get("restoration_called"):
        fail("restore_read_failure", 34)
    print("com.example.Unrelated" + (", com.apple.Accessibility" if state.get("domain_present", True) else ""))
    sys.exit(0)
assert args[5] == "com.apple.Accessibility", args
if operation == "export":
    assert args[6] == "-", args
    fail("export_failure", 35)
    if state.get("malformed_export"):
        print("not a plist")
    else:
        preferences = {"Unrelated": "keep"}
        if state["preference"] is not None:
            preferences["ApplicationAccessibilityEnabled"] = state["preference"]
        sys.stdout.buffer.write(plistlib.dumps(preferences))
    sys.exit(0)
assert args[6] == "ApplicationAccessibilityEnabled", args
if operation == "write":
    enabling = args[7:] == ["-bool", "YES"] and not state.get("enabled")
    if enabling:
        state["enabled"] = True
        state["domain_present"] = True
        if not state.get("enable_verification_failure"):
            state["preference"] = True
        save()
        fail("enable_failure", 36)
    else:
        state["restoration_called"] = True
        save()
        fail("restore_failure", 37)
        if not state.get("restore_verification_failure"):
            if args[7] == "-bool":
                assert args[8] in ("YES", "NO"), args
                state["preference"] = args[8] == "YES"
            else:
                assert args[7] == "-int", args
                state["preference"] = int(args[8])
        save()
    sys.exit(0)
if operation == "delete":
    state["restoration_called"] = True
    save()
    fail("restore_failure", 37)
    state["preference"] = None
    save()
    sys.exit(0)
raise AssertionError(args)
'''


class SimulatorAccessibilityWrapperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ichart-ax-wrapper-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        for name in ("xcrun", "xcodebuild"):
            executable = self.directory / name
            executable.write_text(MOCK_CLI)
            executable.chmod(0o755)
        self.state_path = self.directory / "state.json"
        self.log_path = self.directory / "calls.jsonl"
        self.started_path = self.directory / "started"
        self.environment = dict(os.environ,
                                PATH=str(self.directory) + os.pathsep + os.environ["PATH"],
                                ICHART_SIMULATOR_TEST_STATE=str(self.state_path),
                                ICHART_SIMULATOR_TEST_LOG=str(self.log_path),
                                ICHART_SIMULATOR_TEST_STARTED=str(self.started_path))

    def arguments(self, destination=DESTINATION, command_destination=DESTINATION):
        return ["bash", str(WRAPPER), destination, "--", "xcodebuild", "test",
                "-destination", command_destination, "-parallel-testing-enabled", "NO"]

    def configure(self, preference=False, **flags):
        state = dict(preference=preference, domain_present=True)
        state.update(flags)
        self.state_path.write_text(json.dumps(state))

    def calls(self):
        return [json.loads(line) for line in self.log_path.read_text().splitlines()] if self.log_path.exists() else []

    def run_wrapper(self, preference=False, expected_status=0, **flags):
        self.configure(preference, **flags)
        result = subprocess.run(self.arguments(), env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, expected_status, result.stderr)
        return result

    def assert_preference(self, expected):
        value = json.loads(self.state_path.read_text())["preference"]
        self.assertIs(type(value), type(expected))
        self.assertEqual(value, expected)

    def test_restores_prior_boolean_integer_and_absent_states(self):
        for value in (False, True, 0, 1, None):
            with self.subTest(prior=value, value_type=type(value)):
                result = self.run_wrapper(value)
                self.assert_preference(value)
                self.assertIn("restored and verified", result.stderr)
        self.assertTrue(all(call[1][2] == SIMULATOR_ID for call in self.calls()
                            if call[0] == "xcrun" and call[1][1] != "list"))

    def test_absent_domain_is_restored_to_absent_key(self):
        self.run_wrapper(None, domain_present=False)
        self.assert_preference(None)

    def test_restores_prior_true_when_test_changes_preference(self):
        self.run_wrapper(True, command_preference=False)
        self.assert_preference(True)

    def test_unsupported_preference_type_fails_before_mutation(self):
        self.run_wrapper("unexpected", expected_status=65)
        self.assert_preference("unexpected")
        self.assertFalse(any(call[0] == "xcodebuild" or (call[0] == "xcrun" and "write" in call[1])
                             for call in self.calls()))

    def test_boots_only_selected_shutdown_device(self):
        self.run_wrapper(boot_state="Shutdown")
        self.assertIn(["xcrun", ["simctl", "boot", SIMULATOR_ID]], self.calls())

    def test_preserves_failed_test_exit_and_restores_preference(self):
        self.run_wrapper(expected_status=55, command_exit=55)
        self.assert_preference(False)

    def test_preparation_failures_do_not_run_xcodebuild(self):
        for flag, status in (("list_failure", 1), ("boot_failure", 31), ("bootstatus_failure", 32),
                             ("domains_failure", 33), ("export_failure", 35), ("malformed_export", 65)):
            with self.subTest(flag=flag):
                self.log_path.unlink(missing_ok=True)
                flags = {flag: True}
                if flag == "boot_failure":
                    flags["boot_state"] = "Shutdown"
                self.run_wrapper(expected_status=status, **flags)
                self.assert_preference(False)
                self.assertFalse(any(call[0] == "xcodebuild" for call in self.calls()))

    def test_partial_enable_failure_restores_preference(self):
        self.run_wrapper(expected_status=36, enable_failure=True)
        self.assert_preference(False)
        self.assertFalse(any(call[0] == "xcodebuild" for call in self.calls()))

    def test_failed_enable_verification_stops_before_tests(self):
        self.run_wrapper(expected_status=65, enable_verification_failure=True)
        self.assert_preference(False)
        self.assertFalse(any(call[0] == "xcodebuild" for call in self.calls()))

    def test_failed_restoration_or_verification_fails_successful_run(self):
        for flag in ("restore_failure", "restore_verification_failure", "restore_read_failure"):
            with self.subTest(flag=flag):
                result = self.run_wrapper(expected_status=70, **{flag: True})
                self.assertIn("ERROR: restoration could not be verified", result.stderr)

    def test_restoration_failure_overrides_test_failure_with_explicit_error(self):
        self.run_wrapper(expected_status=70, command_exit=55, restore_failure=True)

    def test_invalid_or_mismatched_destination_is_rejected_before_simulator_calls(self):
        for destination, command_destination in (("platform=iOS Simulator,id=booted", DESTINATION),
                                                  (DESTINATION, "platform=iOS Simulator,id=booted"),
                                                  ("platform=iOS,id=" + SIMULATOR_ID, DESTINATION)):
            with self.subTest(destination=destination, command_destination=command_destination):
                self.log_path.unlink(missing_ok=True)
                self.configure()
                result = subprocess.run(self.arguments(destination, command_destination), env=self.environment,
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertEqual(self.calls(), [])

    def test_unknown_uuid_does_not_boot_or_mutate(self):
        other = "platform=iOS Simulator,id=99999999-1234-1234-1234-123456789ABC"
        self.configure()
        result = subprocess.run(self.arguments(other, other), env=self.environment,
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assert_preference(False)

    def test_cancellation_reaps_child_before_restoring(self):
        cases = ((signal.SIGINT, False, False), (signal.SIGTERM, False, False),
                 (signal.SIGTERM, True, False), (signal.SIGTERM, False, True))
        for received, ignore_cancellation, signal_before_pid in cases:
            with self.subTest(signal=received, ignore=ignore_cancellation, before_pid=signal_before_pid):
                self.log_path.unlink(missing_ok=True)
                self.started_path.unlink(missing_ok=True)
                self.configure(command_wait=True, ignore_cancellation=ignore_cancellation)
                environment = dict(self.environment)
                if signal_before_pid:
                    # Inject only in the test shell, exactly before the wrapper
                    # records its asynchronous child PID. No production hook.
                    bash_environment = self.directory / "signal-before-pid.sh"
                    bash_environment.write_text(r'''trap 'if [[ "$BASH_COMMAND" == "command_pid=\"\$!\"" ]]; then
  trap - DEBUG
  for ((attempt = 0; attempt < 250; attempt++)); do
    [[ -f "$ICHART_SIMULATOR_TEST_STARTED" ]] && break
    sleep 0.02
  done
  kill -TERM "$$"
fi' DEBUG
''')
                    environment["BASH_ENV"] = str(bash_environment)
                process = subprocess.Popen(self.arguments(), env=environment, stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE, text=True, start_new_session=True)
                try:
                    deadline = time.monotonic() + 5
                    while not self.started_path.exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(self.started_path.exists(), "Fake xcodebuild did not start")
                    if not signal_before_pid:
                        process.send_signal(received)
                    stdout, stderr = process.communicate(timeout=5)
                    self.assertEqual(process.returncode, 128 + received, stdout + stderr)
                    self.assert_preference(False)
                    calls = self.calls()
                    child_signal_index = next(index for index, call in enumerate(calls) if call[0] == "test_signal")
                    restore_index = next(index for index, call in enumerate(calls)
                                         if call == ["xcrun", ["simctl", "spawn", SIMULATOR_ID, "defaults", "write",
                                                                "com.apple.Accessibility", "ApplicationAccessibilityEnabled", "-bool", "NO"]])
                    self.assertLess(child_signal_index, restore_index)
                    with self.assertRaises(ProcessLookupError):
                        os.kill(int(self.started_path.read_text()), 0)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate()
                    if self.started_path.exists():
                        try:
                            os.killpg(int(self.started_path.read_text()), signal.SIGKILL)
                        except ProcessLookupError:
                            pass

    def test_ci_summary_verifier_requires_executed_selected_device(self):
        workflow = WRAPPER.parent.parent / "workflows" / "ci.yml"
        marker = 'python3 - "$RUNNER_TEMP/iChart-summary.json" "$SIMULATOR_DESTINATION" <<\'PY\'\n'
        source = textwrap.dedent(workflow.read_text().split(marker, 1)[1].split("          PY", 1)[0])
        valid_row = dict(passedTests=3, failedTests=0, skippedTests=0, device=dict(deviceId=SIMULATOR_ID))
        cases = (([valid_row], True), ([], False), (None, False),
                 ([dict(valid_row, device=dict(deviceId="CLONE-UUID"))], False),
                 ([dict(valid_row, device={})], False),
                 ([dict(valid_row, passedTests=0, skippedTests=3)], False),
                 ([valid_row, dict(valid_row, device=dict(deviceId="CLONE-UUID"))], False))
        for rows, should_pass in cases:
            with self.subTest(rows=rows):
                summary = dict(result="Passed", passedTests=3, failedTests=0, skippedTests=0,
                               devicesAndConfigurations=rows)
                summary_path = self.directory / "summary.json"
                summary_path.write_text(json.dumps(summary))
                result = subprocess.run(["python3", "-c", source, str(summary_path), DESTINATION],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, should_pass, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

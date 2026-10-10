#!/usr/bin/env bash
# Hosted XCTest can render SwiftUI controls before initializing their public
# accessibility tree, reproduced with the service disabled on iOS 26.4.1.
# This undocumented Simulator preference initializes that test service.
# It is not an app fix or a device configuration.
# Restore only this key, including its original type or absence, on every exit.
set -euo pipefail

usage() {
  echo "Usage: $0 'platform=iOS Simulator,id=<UUID>' -- xcodebuild ... -destination '<same destination>' -parallel-testing-enabled NO" >&2
  exit 64
}

[[ $# -ge 4 ]] || usage
destination="$1"
shift
[[ "$1" == "--" ]] || usage
shift
[[ "$1" == "xcodebuild" ]] || usage
destination_pattern='^platform=iOS Simulator,id=([[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12})$'
[[ "$destination" =~ $destination_pattern ]] || usage
simulator_id="${BASH_REMATCH[1]}"

# Require one exact destination and no parallel clones: the configured device
# must be the device on which xcodebuild executes these hosted tests.
command_args=("$@")
destination_count=0
parallel_count=0
for ((index = 1; index < ${#command_args[@]}; index++)); do
  case "${command_args[index]}" in
    -destination)
      index=$((index + 1))
      [[ $index -lt ${#command_args[@]} && "${command_args[index]}" == "$destination" ]] || usage
      destination_count=$((destination_count + 1))
      ;;
    -parallel-testing-enabled)
      index=$((index + 1))
      [[ $index -lt ${#command_args[@]} && "${command_args[index]}" == "NO" ]] || usage
      parallel_count=$((parallel_count + 1))
      ;;
    -destination=*|-parallel-testing-enabled=*) usage ;;
  esac
done
[[ $destination_count -eq 1 && $parallel_count -eq 1 ]] || usage

preference_domain="com.apple.Accessibility"
preference_key="ApplicationAccessibilityEnabled"
prior_snapshot=""
restore_needed=false
command_pid=""
launch_in_progress=false
pending_signal=""
pending_signal_status=0

log() { printf 'Simulator accessibility workaround [%s]: %s\n' "$simulator_id" "$*" >&2; }

# A failed defaults read does not distinguish a missing key from other failures.
# Successful domain enumeration/export gives an unambiguous, typed snapshot.
read_snapshot() {
  local domains domain_presence exported
  domains="$(xcrun simctl spawn "$simulator_id" defaults domains)" || return
  domain_presence="$(printf '%s' "$domains" | python3 -c '
import sys
domains = [item.strip() for item in sys.stdin.read().split(",")]
print("present" if sys.argv[1] in domains else "absent")
' "$preference_domain")" || return
  if [[ "$domain_presence" == "absent" ]]; then
    printf 'absent\n'
    return
  fi
  exported="$(xcrun simctl spawn "$simulator_id" defaults export "$preference_domain" -)" || return
  printf '%s' "$exported" | python3 -c '
import plistlib
import sys
try:
    preferences = plistlib.loads(sys.stdin.buffer.read())
    if not isinstance(preferences, dict):
        raise ValueError("preference export must be a dictionary")
    key = sys.argv[1]
    if key not in preferences:
        print("absent")
    else:
        value = preferences[key]
        if type(value) is bool:
            print("boolean:" + str(int(value)))
        elif type(value) is int and value in (0, 1):
            print("integer:" + str(value))
        else:
            raise ValueError("expected a boolean or integer 0/1")
except Exception as error:
    print("Cannot snapshot simulator accessibility preference: " + str(error), file=sys.stderr)
    sys.exit(65)
' "$preference_key"
}

cleanup() {
  local original_status="$?" current_snapshot restore_boolean restore_status=0
  trap - EXIT
  trap '' INT TERM
  set +e
  if [[ "$restore_needed" == true ]]; then
    # A failed enable command may not have changed the key. Avoid deleting an
    # already absent key, but still verify the snapshot before reporting success.
    current_snapshot="$(read_snapshot)"
    if [[ $? -ne 0 || "$current_snapshot" != "$prior_snapshot" ]]; then
      case "$prior_snapshot" in
        absent)
          xcrun simctl spawn "$simulator_id" defaults delete "$preference_domain" "$preference_key"
          restore_status=$?
          ;;
        boolean:*)
          restore_boolean=NO
          [[ "$prior_snapshot" == "boolean:1" ]] && restore_boolean=YES
          xcrun simctl spawn "$simulator_id" defaults write "$preference_domain" "$preference_key" -bool "$restore_boolean"
          restore_status=$?
          ;;
        integer:*)
          xcrun simctl spawn "$simulator_id" defaults write "$preference_domain" "$preference_key" -int "${prior_snapshot#integer:}"
          restore_status=$?
          ;;
      esac
    fi
    current_snapshot="$(read_snapshot)"
    if [[ $? -ne 0 || $restore_status -ne 0 || "$current_snapshot" != "$prior_snapshot" ]]; then
      log "ERROR: restoration could not be verified (expected $prior_snapshot; observed ${current_snapshot:-unavailable}; command exit $original_status)."
      exit 70
    fi
    log "restored and verified $preference_key=$prior_snapshot"
  fi
  exit "$original_status"
}

cancel() {
  local signal="$1" status="$2"
  if [[ "$launch_in_progress" == true ]]; then
    # A trap may run after the asynchronous launch but before $! is captured.
    # Defer cancellation until the owned child's PID is available to reap.
    pending_signal="$signal"
    pending_signal_status="$status"
    return
  fi
  trap '' INT TERM
  if [[ -n "$command_pid" ]]; then
    log "forwarding $signal to owned xcodebuild process group $command_pid"
    kill -s "$signal" -- "-$command_pid" 2>/dev/null || true
    wait_for_group_exit
    if kill -0 -- "-$command_pid" 2>/dev/null && [[ "$signal" != TERM ]]; then
      log "xcodebuild has not stopped; forwarding TERM to its owned process group"
      kill -TERM -- "-$command_pid" 2>/dev/null || true
      wait_for_group_exit
    fi
    if kill -0 -- "-$command_pid" 2>/dev/null; then
      log "xcodebuild has not stopped; forwarding KILL to its owned process group"
      kill -KILL -- "-$command_pid" 2>/dev/null || true
    fi
    # The first wait is interrupted by the trap; reap the child before restoring.
    wait "$command_pid" 2>/dev/null || true
    command_pid=""
  fi
  exit "$status"
}

wait_for_group_exit() {
  local attempt
  for ((attempt = 0; attempt < 20; attempt++)); do
    kill -0 -- "-$command_pid" 2>/dev/null || return 0
    sleep 0.1
  done
}

trap cleanup EXIT
trap 'cancel INT 130' INT
trap 'cancel TERM 143' TERM

device_state="$(xcrun simctl list devices available -j | python3 -c '
import json
import sys
payload = json.load(sys.stdin)
matches = [(runtime, device) for runtime, devices in payload.get("devices", {}).items()
           for device in devices if device.get("udid", "").upper() == sys.argv[1].upper()]
if len(matches) != 1:
    sys.exit("Selected UUID must identify exactly one available simulator")
runtime, device = matches[0]
if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-") or not device.get("isAvailable", False):
    sys.exit("Selected UUID must identify an available iOS simulator")
print(device.get("state", ""))
' "$simulator_id")"
case "$device_state" in
  Shutdown) xcrun simctl boot "$simulator_id" ;;
  Booted|Booting) ;;
  *) log "ERROR: unexpected selected simulator state: $device_state"; exit 65 ;;
esac
xcrun simctl bootstatus "$simulator_id" -b

prior_snapshot="$(read_snapshot)"
log "undocumented Simulator-only test-service initialization; prior $preference_key=$prior_snapshot"
# Arm restoration before the write, including failures that partially apply.
restore_needed=true
xcrun simctl spawn "$simulator_id" defaults write "$preference_domain" "$preference_key" -bool YES
enabled_snapshot="$(read_snapshot)"
[[ "$enabled_snapshot" == "boolean:1" || "$enabled_snapshot" == "integer:1" ]] || {
  log "ERROR: enabled accessibility preference was not verified: $enabled_snapshot"
  exit 65
}
log "verified enabled preference; executing tests on $destination"

# Job control gives this one owned child a distinct process group and preserves
# SIGINT handling for an asynchronous command. Never signal the CI shell group.
set -m
launch_in_progress=true
"${command_args[@]}" &
command_pid="$!"
launch_in_progress=false
if [[ -n "$pending_signal" ]]; then
  cancel "$pending_signal" "$pending_signal_status"
fi
command_status=0
wait "$command_pid" || command_status="$?"
command_pid=""
exit "$command_status"

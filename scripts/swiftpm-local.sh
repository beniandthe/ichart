#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s {build|test} [SwiftPM options]\n' "${0##*/}" >&2
}

case "${1:-}" in
  build|test) action=$1; shift ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

for arg in "$@"; do
  case "$arg" in
    --) break ;;
    --package-path|--package-path=*|--scratch-path|--scratch-path=*|--build-path|--build-path=*)
      printf '%s chooses the checkout and scratch path. Use swift directly for an intentional override.\n' "${0##*/}" >&2
      exit 2
      ;;
  esac
done

package_root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
checkout_key="$(printf '%s' "$package_root" | /usr/bin/shasum -a 256)"
scratch_path="$HOME/Library/Caches/Smart Chart/SwiftPM/${checkout_key%% *}"

# SwiftPM gives this environment variable precedence over --scratch-path.
unset SWIFTPM_BUILD_DIR
exec /usr/bin/swift "$action" --package-path "$package_root" --scratch-path "$scratch_path" "$@"

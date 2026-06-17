#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SMART_CHART_ENV_FILE:-$ROOT_DIR/.env}"
BUNDLE_ID="${SMART_CHART_BUNDLE_ID:-com.smartchart.app}"
SIMULATOR_UDID="${SMART_CHART_SIMULATOR_UDID:-}"

read_env_value() {
  local key="$1"
  local value
  value="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

SUPABASE_URL_VALUE="${SUPABASE_URL:-$(read_env_value SUPABASE_URL)}"
SUPABASE_PUBLISHABLE_KEY_VALUE="${SUPABASE_PUBLISHABLE_KEY:-$(read_env_value SUPABASE_PUBLISHABLE_KEY)}"

if [[ -z "$SUPABASE_URL_VALUE" || -z "$SUPABASE_PUBLISHABLE_KEY_VALUE" ]]; then
  echo "Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY. Set them in .env or the shell environment." >&2
  exit 1
fi

if [[ -z "$SIMULATOR_UDID" ]]; then
  SIMULATOR_UDID="$(
    xcrun simctl list devices booted |
      sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)) (Booted).*/\1/p' |
      head -n 1
  )"
fi

if [[ -z "$SIMULATOR_UDID" ]]; then
  echo "No booted simulator found. Boot the iPad simulator first, or set SMART_CHART_SIMULATOR_UDID." >&2
  exit 1
fi

SIMCTL_CHILD_SUPABASE_URL="$SUPABASE_URL_VALUE" \
  SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY_VALUE" \
  xcrun simctl launch --terminate-running-process "$SIMULATOR_UDID" "$BUNDLE_ID"

echo "Launched $BUNDLE_ID on $SIMULATOR_UDID with Supabase runtime configuration."

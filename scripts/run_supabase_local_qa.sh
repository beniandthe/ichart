#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -d "$HOME/.orbstack/bin" ]]; then
  export PATH="$HOME/.orbstack/bin:$PATH"
fi

SUPABASE_CMD=()
if command -v supabase >/dev/null 2>&1; then
  SUPABASE_CMD=(supabase)
elif command -v npx >/dev/null 2>&1; then
  SUPABASE_CMD=(npx --yes supabase)
else
  echo "Supabase CLI is required. Install it with 'brew install supabase/tap/supabase' or run through npx." >&2
  exit 127
fi

supabase_cli() {
  "${SUPABASE_CMD[@]}" "$@"
}

load_local_supabase_env() {
  local status_env api_url publishable_key anon_key service_role_key
  status_env="$(supabase_cli status -o env 2>/dev/null || true)"
  api_url="$(printf '%s\n' "$status_env" | awk -F= '/^API_URL=/{ gsub(/"/, "", $2); print $2; exit }')"
  publishable_key="$(printf '%s\n' "$status_env" | awk -F= '/^PUBLISHABLE_KEY=/{ gsub(/"/, "", $2); print $2; exit }')"
  anon_key="$(printf '%s\n' "$status_env" | awk -F= '/^ANON_KEY=/{ gsub(/"/, "", $2); print $2; exit }')"
  service_role_key="$(printf '%s\n' "$status_env" | awk -F= '/^SERVICE_ROLE_KEY=/{ gsub(/"/, "", $2); print $2; exit }')"

  export SUPABASE_URL="${api_url:-http://127.0.0.1:54321}"
  export SUPABASE_PUBLISHABLE_KEY="${publishable_key:-$anon_key}"
  export SUPABASE_SERVICE_ROLE_KEY="$service_role_key"

  if [[ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
    echo "Local Supabase publishable key was not available from 'supabase status'." >&2
    exit 1
  fi

  if [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    echo "Local Supabase service role key was not available from 'supabase status'." >&2
    exit 1
  fi
}

wait_for_auth() {
  for _ in {1..30}; do
    if curl -fsS \
      -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
      "$SUPABASE_URL/auth/v1/settings" >/dev/null 2>&1; then
      return 0
    fi

    sleep 1
  done

  return 1
}

if ! supabase_cli db reset; then
  echo "Supabase db reset hit a local gateway readiness error; restarting local stack before verification..."
  supabase_cli stop >/tmp/smart-chart-supabase-stop.log 2>&1
  supabase_cli start >/tmp/smart-chart-supabase-start.log 2>&1
fi

load_local_supabase_env

supabase_cli test db

if ! wait_for_auth; then
  echo "Restarting local Supabase stack so the gateway refreshes Auth routing..."
  supabase_cli stop >/tmp/smart-chart-supabase-stop.log 2>&1
  supabase_cli start >/tmp/smart-chart-supabase-start.log 2>&1
  wait_for_auth
fi

SMART_CHART_SUPABASE_INTEGRATION=1 \
SUPABASE_URL="$SUPABASE_URL" \
SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
swift test \
  --scratch-path /tmp/SmartChartSwiftBuild-supabase-integration \
  --filter SupabaseIntegrationTests

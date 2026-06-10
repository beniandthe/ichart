#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is required. Install it with: brew install supabase/tap/supabase" >&2
  exit 127
fi

if [[ -f .env ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|SUPABASE_ANON_KEY)
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "$key=$value"
        ;;
    esac
  done < <(grep -E '^(SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|SUPABASE_ANON_KEY)=' .env || true)
fi

if [[ -z "${SUPABASE_URL:-}" ]]; then
  export SUPABASE_URL="http://127.0.0.1:54321"
fi

if [[ -z "${SUPABASE_PUBLISHABLE_KEY:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  export SUPABASE_PUBLISHABLE_KEY="$SUPABASE_ANON_KEY"
fi

if [[ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY is required for integration tests." >&2
  exit 1
fi

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

if ! supabase db reset; then
  echo "Supabase db reset hit a local gateway readiness error; restarting local stack before verification..."
  supabase stop >/tmp/smart-chart-supabase-stop.log 2>&1
  supabase start >/tmp/smart-chart-supabase-start.log 2>&1
fi

supabase test db

if ! wait_for_auth; then
  echo "Restarting local Supabase stack so the gateway refreshes Auth routing..."
  supabase stop >/tmp/smart-chart-supabase-stop.log 2>&1
  supabase start >/tmp/smart-chart-supabase-start.log 2>&1
  wait_for_auth
fi

SMART_CHART_SUPABASE_INTEGRATION=1 \
SUPABASE_URL="$SUPABASE_URL" \
SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
swift test \
  --scratch-path /tmp/SmartChartSwiftBuild-supabase-integration \
  --filter SupabaseIntegrationTests

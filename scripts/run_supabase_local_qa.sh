#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is required. Install it with: brew install supabase/tap/supabase" >&2
  exit 127
fi

supabase db reset
supabase test db

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
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

SMART_CHART_SUPABASE_INTEGRATION=1 \
SUPABASE_URL="$SUPABASE_URL" \
SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
swift test \
  --scratch-path /tmp/SmartChartSwiftBuild-supabase-integration \
  --filter SupabaseIntegrationTests

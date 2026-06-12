#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "error: $*" >&2
  exit 1
}

run() {
  echo
  echo "==> $*"
  "$@"
}

check_ignored_secret_paths() {
  local tracked_secret_files
  tracked_secret_files="$(
    git ls-files '.env' '.env.*' 'supabase/.temp/*' 'supabase/.branches/*' \
      | grep -v '^.env.example$' \
      || true
  )"
  if [[ -n "$tracked_secret_files" ]]; then
    printf '%s\n' "$tracked_secret_files" >&2
    fail "secret/runtime files are tracked"
  fi

  for ignored_path in .env .env.local supabase/.temp/current supabase/.branches/current; do
    git check-ignore -q "$ignored_path" || fail "$ignored_path is not ignored"
  done

  if git check-ignore -q .env.example; then
    fail ".env.example must stay tracked as the non-secret template"
  fi
}

scan_for_secrets() {
  local tmp_file file pattern found
  tmp_file="$(mktemp)"
  found=0

  git ls-files --cached --others --exclude-standard -z >"$tmp_file"

  local patterns=(
    'sb_secret_[A-Za-z0-9_-]+'
    'sk_live_[A-Za-z0-9]+'
    'SUPABASE_SERVICE_ROLE_KEY[[:space:]]*=[[:space:]]*[^[:space:]<]+'
    'JWT_SECRET[[:space:]]*=[[:space:]]*[^[:space:]<]+'
    'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
    'postgres(ql)?://[^[:space:]]+:[^[:space:]@]+@'
  )

  while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue

    for pattern in "${patterns[@]}"; do
      if grep -IEn "$pattern" "$file"; then
        found=1
      fi
    done
  done <"$tmp_file"

  if [[ "$found" -ne 0 ]]; then
    rm -f "$tmp_file"
    fail "possible secret material found in tracked or non-ignored files"
  fi

  rm -f "$tmp_file"
}

run git diff --check

echo
echo "==> Checking ignored secret paths"
check_ignored_secret_paths

echo
echo "==> Scanning tracked and non-ignored files for key-shaped secrets"
scan_for_secrets

run node --test \
  supabase/functions/_shared/app_store_subscription_authority.test.mjs \
  supabase/functions/_shared/app_store_verifier_config.test.mjs \
  supabase/functions/_shared/supabase_subscription_authority_store.test.mjs

run swift test \
  --scratch-path /tmp/SmartChartSwiftBuild-supabase-readiness-focused \
  --filter 'ProjectConfigurationTests|ChartCloudMergeTests|ChartLibraryStoreTests|SupabaseIntegrationTests'

if [[ "${SMART_CHART_SKIP_FULL_SWIFTPM:-0}" == "1" ]]; then
  echo
  echo "==> Skipping full SwiftPM because SMART_CHART_SKIP_FULL_SWIFTPM=1"
else
  run swift test --scratch-path /tmp/SmartChartSwiftBuild-supabase-readiness-full
fi

if [[ "${SMART_CHART_RUN_LOCAL_SUPABASE_QA:-0}" == "1" ]]; then
  run scripts/run_supabase_local_qa.sh
else
  echo
  echo "==> Skipping local Supabase reset/RLS/integration because SMART_CHART_RUN_LOCAL_SUPABASE_QA is not 1"
  echo "    Run with SMART_CHART_RUN_LOCAL_SUPABASE_QA=1 when the local Supabase stack is available."
fi

cat <<'EOF'

Manual simulator/cloud gate still required before release:
- Build/run the iPad simulator with CODE_SIGNING_ALLOWED=NO.
- Relaunch with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY for the target project.
- Walk the account/profile/chart-sync checklist in docs/supabase-production-readiness-checklist.md.
EOF

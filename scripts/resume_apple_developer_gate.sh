#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

project_ref="pausvvwoazbvmzyrebwl"
bundle_id="com.smartchart.app"
monthly_product_id="com.smartchart.app.pro.monthly"
annual_product_id="com.smartchart.app.pro.annual"
webhook_url="https://${project_ref}.supabase.co/functions/v1/app-store-server-notifications"
claim_url="https://${project_ref}.supabase.co/functions/v1/storekit-subscription-claims"
root_cert_bundle="/tmp/ichart-apple-root-certificates.pem"

section() {
  echo
  echo "==> $*"
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "error: missing required file: $path" >&2
    exit 1
  fi
}

require_text() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$path"; then
    echo "error: expected '$needle' in $path" >&2
    exit 1
  fi
}

smoke_post() {
  local label="$1"
  local url="$2"
  local body="$3"
  local expected_statuses="$4"
  local response status payload expected matched

  response="$(
    curl -sS \
      -X POST "$url" \
      -H "content-type: application/json" \
      -d "$body" \
      -w $'\n%{http_code}'
  )"
  status="${response##*$'\n'}"
  payload="${response%$'\n'*}"

  echo "$label"
  echo "status: $status"
  echo "body: $payload"

  matched=0
  for expected in $expected_statuses; do
    if [[ "$status" == "$expected" ]]; then
      matched=1
      break
    fi
  done

  if [[ "$matched" -ne 1 ]]; then
    echo "warning: expected HTTP status in [$expected_statuses] for $label" >&2
  fi
}

section "Git Checkpoint"
git status --short --branch
git log -1 --oneline

section "Local StoreKit Identifiers"
require_file "SmartChart/Models/IChartStoreKitProductCatalog.swift"
require_file "project.yml"
require_file "StoreKit/iChartProSubscriptions.storekit"
require_file "docs/ichart-storekit-subscription-runbook.md"
require_text "project.yml" "PRODUCT_BUNDLE_IDENTIFIER: ${bundle_id}"
require_text "SmartChart/Models/IChartStoreKitProductCatalog.swift" "$monthly_product_id"
require_text "SmartChart/Models/IChartStoreKitProductCatalog.swift" "$annual_product_id"
require_text "StoreKit/iChartProSubscriptions.storekit" "$monthly_product_id"
require_text "StoreKit/iChartProSubscriptions.storekit" "$annual_product_id"
echo "bundle id: $bundle_id"
echo "monthly:   $monthly_product_id"
echo "annual:    $annual_product_id"

section "Apple Root Certificate Bundle"
scripts/prepare_apple_root_certificates.sh "$root_cert_bundle"

section "Remote Edge Function Smoke"
smoke_post "webhook missing signedPayload" "$webhook_url" '{}' "400"
smoke_post "webhook opaque signedPayload" "$webhook_url" '{"signedPayload":"opaque"}' "401 501"
smoke_post "claim without Supabase auth" "$claim_url" '{}' "401"

section "Interpretation"
cat <<EOF
If "webhook opaque signedPayload" returns:
- HTTP 401: Apple verifier secrets are active and fake payloads are rejected correctly.
- HTTP 501: Apple verifier secrets are not configured yet. Set the Supabase secrets below.

Supabase Edge Function secrets for sandbox:
- APP_STORE_BUNDLE_ID=${bundle_id}
- APP_STORE_ENVIRONMENT=Sandbox
- APP_STORE_ROOT_CERTIFICATES_PEM=<contents of ${root_cert_bundle}>

App Store Connect setup to confirm:
- Subscription group: iChart Pro
- Monthly product ID: ${monthly_product_id}, price \$7.99
- Annual product ID: ${annual_product_id}, price \$64.99
- App Store Server Notifications sandbox URL, Version 2:
  ${webhook_url}

After Apple products and Supabase secrets are configured, run this script again.
Then run the sandbox/TestFlight purchase QA from docs/ichart-storekit-subscription-runbook.md.
EOF

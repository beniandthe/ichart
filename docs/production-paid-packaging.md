# Held production-paid artifact verification

This lane prepares a production-paid artifact while Apple upload, tester assignment,
release and activation remain held. It never builds, uploads, installs, changes
prices or changes the backend itself. The cutover procedure and final approval are
owned by `production-paid-release.md`.

The public-beta verifier remains unchanged. Use
`scripts/verify-production-paid-distribution.py` only for a distinct paid packet.
It reuses the public guard's strict signature, profile, active DER entitlement,
archive/IPA inventory, dSYM UUID and export-difference checks without modifying
its file or policy constants. The internal paid-staging packager is not a
production substitute: it targets the isolated staging endpoint/products and has
a different signing/namespace contract.

## Required source and build inputs

Start from the final reviewed, committed, clean source after combined CI. Version
and build are read from the quoted literals in authoritative `project.yml`; the
current preparation chooses 1.9.4 (208), subject to the release owner's live Apple
reservation check. A local device build is not an Apple reservation.

Generate from `project.yml`, then pin the generated project, native dependency
lock, compiled source and scripts. The iChart target has an empty normal
`ICHART_RELEASE_ACCESS_CONDITIONS` value. Only an explicit paid archive supplies
`ICHART_RELEASE_ACCESS_CONDITIONS=ICHART_PAID_SUBSCRIPTION`. Do not globally replace
Swift compilation conditions: dependencies retain their own flags.

The paid guard requires actual optimized native arm64 iChart compilation with
exactly `ICHART_PAID_SUBSCRIPTION`. Staging, Debug, local QA/preview and unreviewed
Swift conditions are rejected. Requirements-only/build-setting/echo evidence is
insufficient. Response files, the output map and fresh Release archive manifest
must bind the actual policy, catalog, public namespace, backend configuration,
App entry, StoreKit store, phase model, RPC client/store, library/UI routing and entitlement source files. The paid pin additionally hashes client tests, scripts and backend/RPC fixtures; it never claims those backend sources are deployed. Preserve DerivedData and
full non-quiet compiler output through verification. Every actual Swift input
must hash-match the pin, not merely the named required subset. Reject ignored or
external sources; separately hash generated DerivedData inputs. The complete
compiler file list, output map and archive manifest must agree.

The production catalog must contain the normal product IDs and targets of
699/6000 USD minor units. Those source targets do not establish Apple's actual
loaded prices. Production Info values, pinned client-key hash and empty legacy
key are checked. Runtime endpoint behavior is established by the reviewed source
and its native tests, not solely by baked Info or binary strings.

## Checked hold policy

Before pinning, the release owner writes a private JSON receipt outside source.
Fill the full final source head/tree and the exact version/build from that source:

```json
{
  "schema": 2,
  "package_mode": "production_paid",
  "source_head": "FULL_FINAL_COMMIT",
  "source_tree": "FULL_FINAL_TREE",
  "version": "1.9.4",
  "build": "208",
  "distribution_held": true,
  "apple_delivery_held": true,
  "automatic_activation": false,
  "production_activation_approved": false,
  "activation_strategy": "server_coordinated_runtime_phase",
  "public_beta_must_remain_on": true,
  "deploy_to_production_must_remain_off": true,
  "target_cutover_utc": "2026-12-01T17:00:00Z"
}
```

The target is a planning timestamp. Arrival of that date never clears either
hold and is not production-activation approval. The coordinated client separates
its compiled paid capability from the server-confirmed phase and owner-bound
access. Keep the existing public beta and production free-Pro policy on while
preparing it. The hold receipt expresses the required release policy, not a live
backend measurement; retain separate live readbacks. Previous static-paid signed
packets do not acquire this behavior through a policy-file edit and remain prior
attempts, not distribution candidates.

## Pin, archive, export and verify

Set `S` to the final clean source and `R` to a fresh private release folder outside
iCloud. First run the separate source-bound native validation in both
`production-paid` and `public-free` lanes as described in
`production-paid-validation.md`. Retain each complete output directory and set
`P` and `F` to their `validation-receipt.json` files. The old 86-test receipts and
preparation-only records cannot certify the new coordinated runtime contract.

Create the hold receipt as `$R/release-policy.json`. Clear injected Xcode
configuration, global Swift/compiler flags, backend overrides, personal ML inputs,
`SIMCTL_CHILD_*` and `DYLD_*` in the actual runner. Do not source staging secrets.

```sh
xcodegen generate --spec "$S/project.yml"
python3 "$S/scripts/verify-production-paid-distribution.py" pin \
  --source "$S" --release-policy "$R/release-policy.json" \
  --runtime-receipt "$P" --normal-free-runtime-receipt "$F" \
  --output "$R/paid-source-pin.json"
```

Archive with the existing manual Apple Distribution / iChart App Store profile,
Release configuration, generic iOS destination, frozen package lock and explicit
local DerivedData, SourcePackages, archive and result paths. Supply only the
app-scoped paid switch. Check the real exit status and preserve the full log.
A source, generated-project, package or hold-policy edit requires a new reviewed
pin and new archive; do not re-pin drift to waive a mismatch.

Export to disk using the same exact normal App Store export contract as
`public-beta-release.md`: manual Apple Distribution, iChart team/profile,
`destination=export`, `manageAppVersionAndBuildNumber=false`,
`testFlightInternalTestingOnly=false`. Internal/external audiences are Apple
controls; this verifier does not assign either. Do not upload a held artifact.

```sh
python3 "$S/scripts/verify-production-paid-distribution.py" verify \
  --source "$S" --release-policy "$R/release-policy.json" \
  --source-pin "$R/paid-source-pin.json" \
  --runtime-receipt "$P" --normal-free-runtime-receipt "$F" \
  --archive "$R/iChart-production-paid.xcarchive" \
  --derived-data "$R/DerivedData" --build-log "$R/archive.log" \
  --export-options "$R/ExportOptions.plist" --ipa "$R/export/iChart.ipa" \
  --output "$R/paid-artifact-verification.json"
```

Success writes `artifact_verified=true`, `distribution_held=true`,
`apple_delivery_held=true`, `delivery_ready=false` and
`production_activation_approved=false`. There is deliberately no generic `passed`
field to treat as a public-beta delivery authorization. Only after both native
receipts are independently revalidated against this exact source can it also
record `preactivation_free_pro_supported=true` and
`normal_free_native_verified=true`. The verifier re-reads the actual xcresult
summary and method tree, raw compiler log and source maps, complete result
inventory and generated-project/lock/runner hashes. The reviewed scenario method
inventory must execute exactly once without failures or skips in both capability
scopes. A success boolean or one passing test per class is insufficient.

The paired evidence fingerprints are bound into the source pin before archive.
Source, pin, policy, runtime receipts/evidence, signed archive, IPA, dSYM and build
log must remain unchanged through final verification. No script clears the hold
by clock or by reading `freeProAccess=false`.

Preserve the pin, policy, full compiler/response metadata, archive/dSYM, IPA,
export options, receipt and source recovery bundle privately. Verify at original
build paths before relocation; preserve byte hashes and signatures on copies.
Before any later potentially automatic TestFlight delivery or iPad replacement,
the release owner needs the current device-preservation and final release gates.

## Checks and evidence boundaries

Run the new synthetic tests with `python3 scripts/test_production_paid_distribution.py`.
Also run `python3 scripts/test_production_paid_validation.py`. Keep the existing
public, staging and personal-resource guards passing without altering their
policy. Count repeated public cases separately.

A held artifact receipt does not prove Apple product availability/prices, review
approval, purchase/restore/expiration, notification processing, grace behavior,
production migrations or current server access. A truthful preactivation claim
is bounded to the exact source-bound native fixture scenarios; it does not prove
the hosted RPC exists, that a distributed app can reach it, or that production has
activated. Ordinary full free CI, live rollout/legacy-cohort checks, current
device preservation, Apple delivery and any billing-grace subscribers remain
separate release gates.

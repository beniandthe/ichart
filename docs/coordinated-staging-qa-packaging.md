# Coordinated staging QA packaging

This separate lane prepares an internal-only QA artifact using the shared
coordinated phase/resolver, an isolated backend and isolated local/auth storage.
It does not deploy, upload, install, change Apple metadata or activate production.
The normal public and production verifiers remain byte-for-byte unchanged.

## Original packaging ownership and source coordination

Owner: `/root/archive_public_beta_199`. Checkout:
`/private/tmp/ichart-dec1-coordinated-qa-20261127/source`, branch
`codex/dec1-coordinated-qa`, client/root base
`30dd75ec707728b7cde9c5d1594592c7143b3917`. Root integrates and commits the final
combined source. The client/server owner owns runtime/configuration/Swift tests;
this packaging owner owns only:

- `scripts/prepare_coordinated_staging_qa_project.py`
- `scripts/run_coordinated_staging_qa_validation.py`
- `scripts/test_coordinated_staging_qa_validation.py`
- `scripts/verify-coordinated-staging-qa-distribution.py`
- `scripts/test_coordinated_staging_qa_distribution.py`
- This document and `coordinated-staging-qa-catalog.json`
- The explicit new-QA condition rejection and its regression in the historical
  `archive_internal_paid_staging.py` and its packaging test file.

Those ownership coordinates describe the original November 27 packaging work.
The current expiry follow-on uses `codex/dec1-client-entitlement-expiry` and the
release owner's acknowledged full HEAD/tree. Its source identity is 210 and its
separate QA override is 209. Retain the original 207/208 receipts as historical
evidence; prepare new native and archive proofs for the current exact source.

No production checkout, prior artifact, device backup or parked work is replaced.
Source review, synthetic guards, actual native validation, artifact verification,
Apple delivery and real Sandbox lifecycle evidence remain separate milestones.

## Fixed QA contract

The app must compile optimized Release with exactly:

```text
ICHART_PAID_SUBSCRIPTION
ICHART_STAGING_STOREKIT_PRODUCTS
ICHART_COORDINATED_STAGING_QA
```

Debug, local plan previews, unknown conditions and validation markers are forbidden
in the artifact. The native test target alone additionally uses the existing
`ICHART_PRODUCTION_PAID_VALIDATION` marker to execute retained paid-default
preservation assertions. That legacy marker name is not a production certificate.
None of these conditions may leak to dependencies or global project settings.

The normal source is **1.9.4 (210)**. The reviewed QA transformation overrides
**only the app Release target** to **1.9.4 (209)**. A different source identity is
rejected. These are release-owner choices after Apple readback, not an Apple build
reservation.

The exact origin is `https://yiuxduqhhbucsmooevxz.supabase.co`; the publishable key
must match SHA-256
`bfdf9049a7237013fea1b1f18d137e4d58daa34078fec4290b78a9676e9038e2`.
The legacy key is empty. The recipe accepts only the matching publishable key
from a bounded private input file, never a secret/service-role/JWT key. Client
code ignores launch-time backend/key overrides. Supabase documents publishable
keys for shipped clients and reserves secret keys for controlled backends.
[API key guidance](https://supabase.com/docs/guides/getting-started/api-keys)

The namespace is `coordinatedStagingQA`, directory
`iChart Coordinated QA yiuxduqhhbucsmooevxz`, preferences suite
`com.ichart.app.coordinated-qa.yiuxduqhhbucsmooevxz` and auth prefix
`coordinated-qa.yiuxduqhhbucsmooevxz.`. Shared phase caches are additionally bound
to the selected project and owner. Public and historical FIX036 storage and auth
stay separate; QA does not import or fall back to either. The new mode retains
ephemeral SDK network sessions.

The catalog uses the existing isolated FIX036 monthly/annual IDs, with target
US prices **$6.99 / exactly $60.00**, not public products. The separate JSON records
the release owner's November 27 App Store Connect observation: both level 1,
US-only, Prepare for Submission, no upcoming schedule. That observation is not
device-fetched pricing or completed billing verification. Preserve the original
FIX036 catalog and old endpoint documentation as historical evidence.

## Native evidence before archive

Freeze and commit the complete source. Set `S` to that source, `R` to a fresh
private durable packet outside iCloud, `H` to its full commit, `KEY` to the private
publishable-key file and `D` to an exact dedicated Simulator UUID.

```sh
python3 "$S/scripts/run_coordinated_staging_qa_validation.py" \
  --source "$S" --output "$R/native-qa" \
  --qa-public-key-file "$KEY" \
  --destination "platform=iOS Simulator,id=$D" --run-tests
```

Omitting `--run-tests` prepares only. Actual validation requires the retained
schema-2 receipt with `nativeValidationPassed=true`, a complete raw compiler log,
generated project/spec/Info/lock evidence and the actual xcresult bundle.

The focused selection retains relevant paid/default/downgrade, fonts,
billing-recovery and PDF/setlist controls. It requires all **99 explicit methods**:
69 shared cases including the 16 expiry scenarios, seven QA routing/configuration
cases, five auth isolation cases, five storage cases and 13 catalog cases, across 21 selected
classes. The actual app-bundle test verifies the QA host/key despite hostile launch
overrides. Missing/duplicate/unexpected methods, failures/skips, a different
Simulator, ignored/unpinned Swift inputs, hidden flags or stale evidence fail.

The copied neutral validators are guarded against their production counterparts
by AST and dependency-binding tests. The QA adapters explicitly change only the
lane, inputs, test scope and own evidence paths. Normal full CI and the other
capability-lane checks still require their own execution receipts.

## Prepare the archive project and pin

Use a separate immutable clone of the same committed source. Keep the native run
at its original recorded paths. This preparation generates only an isolated app
project; it does not compile, sign, export or deliver anything:

```sh
python3 "$S/scripts/prepare_coordinated_staging_qa_project.py" \
  --source "$S" --output "$R/project-recipe" \
  --expected-head "$H" --qa-public-key-file "$KEY"
```

Only the generated app Release target/Info receives the QA endpoint, key,
conditions, Build 209 and `TFInternalTestingOnly=true`. Normal source inputs,
dependency settings, source Build 210 and signing settings remain intact.
Testability is disabled for the archive app. The preparation receipt binds the
authoritative source, transformed spec, generated project and Info; the verifier
reconstructs the exact transformation rather than trusting supplied hashes alone.

Before pinning, the release owner writes the private exact-source policy below.
Replace `FULL_HEAD` and `FULL_TREE`; no field clears a hold:

```json
{
  "schema": 2,
  "package_mode": "coordinated_staging_qa",
  "source_head": "FULL_HEAD",
  "source_tree": "FULL_TREE",
  "version": "1.9.4",
  "build": "209",
  "source_version": "1.9.4",
  "source_build": "210",
  "qa_origin": "https://yiuxduqhhbucsmooevxz.supabase.co",
  "qa_key_sha256": "bfdf9049a7237013fea1b1f18d137e4d58daa34078fec4290b78a9676e9038e2",
  "internal_qa_only": true,
  "distribution_held": true,
  "apple_delivery_held": true,
  "automatic_activation": false,
  "production_activation_approved": false,
  "public_beta_must_remain_on": true,
  "deploy_to_production_must_remain_off": true,
  "production_resources_must_remain_unchanged": true
}
```

```sh
python3 "$S/scripts/verify-coordinated-staging-qa-distribution.py" pin \
  --source "$S" --release-policy "$R/qa-policy.json" \
  --runtime-receipt "$R/native-qa/validation-receipt.json" \
  --qa-project-receipt "$R/project-recipe/qa-project-receipt.json" \
  --output "$R/qa-source-pin.json"
```

## Held archive/export proof

After a separate archive GO, use the prepared project, Release/generic iOS,
frozen native package resolution and explicit local DerivedData, SourcePackages,
archive, result-bundle and full-log paths. Do not inject global flags or backend
overrides. Preserve a source recovery bundle and verify an independent restore.

Retain manual Apple Distribution signing, team `N6G8X4K46U`, bundle
`com.ichart.app`, the `iChart App Store` profile and exact active DER entitlements.
Export to disk only: `method=app-store-connect`, `destination=export`,
`manageAppVersionAndBuildNumber=false`, `testFlightInternalTestingOnly=true`.
The strict QA wrapper checks the real signature/profile/expiry, internal-only
Info and isolated catalog, exact native arm64 compiler/source/manifest closure,
archive/IPA/dSYM UUID equality and classified export differences. It never patches
the production/public verifier's functions or constants.

```sh
python3 "$S/scripts/verify-coordinated-staging-qa-distribution.py" verify \
  --source "$S" --release-policy "$R/qa-policy.json" \
  --runtime-receipt "$R/native-qa/validation-receipt.json" \
  --qa-project-receipt "$R/project-recipe/qa-project-receipt.json" \
  --source-pin "$R/qa-source-pin.json" --archive "$R/iChart-QA.xcarchive" \
  --derived-data "$R/DerivedData" --build-log "$R/archive.log" \
  --export-options "$R/ExportOptions.plist" --ipa "$R/export/iChart.ipa" \
  --output "$R/qa-artifact-verification.json"
```

Success remains `delivery_ready=false`, `apple_delivery_held=true` and
`production_activation_approved=false`. QA proof explicitly leaves production
native/artifact, hosted backend, actual fetched prices and billing unverified.
Source, policy, pin, spec, native evidence, compiler/maps/manifests, signatures,
IPA and dSYM are checked again before issuing the receipt.

Run both new Python test files and the existing public/production/historical
packaging matrix. These are synthetic guard checks, not native or Apple evidence.
Actual Internal QA delivery, saved-work confirmation/backups, Sandbox sign-in,
purchases/restores, cancellation through paid-through, annual/monthly expiration,
notification delivery and final preservation/teardown remain release-owner gates.

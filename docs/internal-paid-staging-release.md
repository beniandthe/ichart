# FIX-036 internal paid-staging package

This is an internal TestFlight candidate for the Basic/Pro implementation. It
uses the separate Supabase project `gfqpbikqvdgtjjgxrkgo`. The ordinary public
build continues to select free beta and the production backend through
`project.yml`. No public-beta price or live Apple subscription is changed by
this packaging command.

The requested staging prices are **USD $6.99 monthly** and **exactly USD $60.00
annually**. The machine-readable targets are in
`internal-paid-staging-catalog.json`. The release operator's November 20 App Store Connect readback confirmed the
annual product `6837601925` at exactly **USD $60.00**, in the separate
**iChart FIX036 Staging** subscription group `22601761`, available in the USA
only (1 of 175 territories), **Prepare for Submission**, and unsubmitted.
The isolated monthly product is being created; its final catalog readback is
pending. Actual StoreKit fetching, period, currency and displayed prices still
require runtime acceptance. A target amount in this repository does not set or prove Apple's
price. Release UI uses Apple's fetched product display prices.

The internal lane selects `ICHART_PAID_SUBSCRIPTION` and
`ICHART_STAGING_STOREKIT_PRODUCTS`. Its isolated product IDs are
`com.ichart.app.staging.fix036.monthly` and
`com.ichart.app.staging.fix036.annual`; the operator must supply the IDs
explicitly after their Apple verification. The script rejects any mismatch
with the staging branch of the runtime catalog. It does not silently remap
products or reuse the ordinary product IDs. Staging's server-side accepted
product IDs and Apple Sandbox claim/notification verification must also be
configured and checked separately. The staging Edge verifier selection is
`ICHART_STAGING_STOREKIT_PRODUCTS=true`, requires `APP_STORE_ENVIRONMENT=Sandbox`,
and is restricted to the exact staging `SUPABASE_URL`. These are server-only
inputs, separate from the app's Swift compilation conditions.

The operator reserved **1.9.4 (173)** after reading the uploaded Apple build
grid on November 20, 2026. Version and build remain required command arguments;
this document is not upload or release completion evidence.

## Prepare and review

Use a regular file outside the checkout containing only the **staging
publishable client key**. Only the `sb_publishable_` key form is accepted. Do
not use a secret key, service-role key, JWT, signing key or administrator
credential. The publishable key must independently be confirmed as belonging
to the staging project: its opaque value cannot establish project membership
offline. It is embedded into the app as a normal public client key, while
receipts and command logs retain only its SHA-256 or a redaction.

From the isolated source checkout, provide every release input explicitly:

```sh
python3 scripts/archive_internal_paid_staging.py plan \
  --project-ref gfqpbikqvdgtjjgxrkgo \
  --publishable-key-file /absolute/local/path/staging-publishable-key.txt \
  --version 1.9.4 --build 173 \
  --monthly-product-id com.ichart.app.staging.fix036.monthly \
  --annual-product-id com.ichart.app.staging.fix036.annual \
  --output-dir /private/tmp/ichart-fix036-paid-staging-173
```

`plan` reads and validates the inputs, prints a redacted plan, and creates no
build output. After reviewing the Apple-selected identity and products, use
that same invocation with `archive` in place of `plan`. The archive action
requires a fresh output directory, generates the local Xcode project from
unchanged `project.yml`, and runs native iOS **Release** archiving. It pins
actual source inputs, checks the native package lock, passes the two staging
compile conditions explicitly, and disables personal ML comparison resources.
Inherited backend variables, Swift flags, configuration injection and Simulator
launch overrides are removed from the command environment. The temporary
staging xcconfig is removed after the command; the resulting app necessarily
contains its public backend configuration.

## Verify the package

The script checks the actual Xcode Swift compiler arguments and bounded
response files for both required staging conditions, and rejects `DEBUG`,
`ICHART_LOCAL_PLAN_QA` and `ICHART_LOCAL_QA_PLAN_PREVIEW`. It correlates the
compiler output map to this checkout's access-policy source and the fresh
native Release archive build-request/manifest. Current Xcode manifests contain
compiler descriptions and inputs/outputs; they do not themselves contain the
Swift argument list. The separate retained compiler log provides that list.
The script checks exact archived app identity, iPad targeting, baked staging
URL, public-key hash, blank legacy anon value and excluded personal resources.

Export through the separately verified App Store distribution process. Then
repeat the command using `verify` instead of `archive`, the same source,
inputs and output directory, and add `--ipa /absolute/path/iChart.ipa`. This
also checks the exported IPA's baked configuration and records its hash.

These packaging checks do not replace signature/profile/active DER checks,
executable/dSYM UUID binding, Apple upload/processing, internal-group-only
selection, hosted policy checks, or end-to-end Apple Sandbox purchase and
restore evidence. No script action uploads, installs, launches, changes server
policy, changes Apple prices, or chooses an App Store release.

The `ICHART_STAGING_STOREKIT_PRODUCTS` build now selects separate local data and
auth namespaces as well as the isolated product catalog. Application Support,
caches and temporary paths add `iChart Internal Staging FIX036`; charts, original
and source ink, projects, selection, PDF files/manifests, setlists/checkpoints,
correction memory and diagnostic stores start in that separate namespace.
Preferences use `com.ichart.app.internal-staging.fix036`. Every app and SDK auth
storage operation prefixes its key with `internal-staging.fix036.`, including
SDK legacy-migration keys. Staging does not migrate, copy, delete or fall back
to public data. Its network clients use an ephemeral session without shared
cache, cookie or credential stores. Runtime backend configuration fails closed
unless it selects the exact staging HTTPS origin with a publishable client key.
The readonly **Internal staging** banner explains the separate QA data/account.
Normal builds retain their existing paths, keys, preferences and shared session.

Use a dedicated staging test account and only original synthetic QA content.
The bundle remains `com.ichart.app`, so this is still an in-place app update:
iOS manages the common app container, system snapshots and install metadata.
A fresh saved-state confirmation, stopped-app backup, and saved-content
preservation verification remain necessary before updating an existing iPad.
Never uninstall or erase saved work to test this candidate. The backend-isolated Debug Build 172 plan preview is retained as
recovery/QA evidence and is excluded from this distribution path.

The normal beta test suite includes assertions that the compiled default is
free beta and its normal backend is production. Preserve those tests in their
ordinary configuration; use the focused packaging guards and paid staging
runtime acceptance for this explicitly different candidate.

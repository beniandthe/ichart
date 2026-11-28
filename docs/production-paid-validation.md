# Coordinated production-paid and normal-free native validation

The normal project and ordinary CI remain the public free-beta build. Keep their
free-access assertions and strict public-beta archive verifier unchanged. A paid
policy injected into a normal free binary is not compile-time paid-client proof.

`scripts/run_production_paid_validation.py` generates an isolated Release project
outside the checkout from authoritative `project.yml` sources and the committed
native package resolution. Choose a dedicated Simulator and a new local output
directory outside iCloud for each lane:

```sh
python3 scripts/run_production_paid_validation.py \
  --lane production-paid \
  --output /private/tmp/ichart-production-paid-validation-PREPARE \
  --destination 'platform=iOS Simulator,id=REPLACE-WITH-EXACT-SIMULATOR-UUID'
```

This prepares only; it does not build or certify anything. Commit and freeze the
complete candidate, then add `--run-tests` with a fresh output path. Run the same
command separately with `--lane public-free` and another fresh path. The default
lane is `production-paid` for compatibility; always record the explicit lane in
release instructions.

Only paid-lane app/test targets receive `ICHART_PAID_SUBSCRIPTION`, and only its
test target receives `ICHART_PRODUCTION_PAID_VALIDATION`. Both normal-free targets
compile with neither condition. No paid flag is inherited by package dependencies
or global settings. Release testability permits native assertions; these
Simulator hosts are not signed distribution artifacts. Do not replace the normal
Debug project or weaken its full CI gates.

The reviewed shared coordination inventory is 69 explicit methods: 39 core
phase/billing/checkout methods, 14 library/presentation methods and 16 known-expiry
methods across seven classes:
`CoordinatedProductAccessStoreTests`, `CoordinatedPaidCheckoutAdmissionTests`,
`CoordinatedLibraryPolicyPreservationTests`, `CoordinatedPlanPresentationTests`,
`IChartSubscriptionDeadlineTests`, `IChartSubscriptionEntitlementExpiryTests` and
`IChartKnownExpiryExportContextTests`. The expiry cases cover publication at the
known deadline, renewal and owner changes, task lifetime, retained saved content,
and deadline checks at local admission and export.
The mounted tests include `Support/NativeAccessibilityLookup.swift`. A synthetic
guard compares the explicit inventory with every declared method so additions or
renames cannot silently fall out of the native gate.

The paid selection retains billing recovery, production configuration/catalog,
local chart/ink/font/PDF/setlist preservation and adds the complete reviewed
coordinated phase-to-access, mounted UI and checkout-admission scenarios. The
normal-free selection executes those same coordination scenarios plus actual
free build-scope, backend and catalog cases. It excludes the paid-default-only
class rather than skipping its assertions. Both lanes require all selected
classes and the exact reviewed coordination methods, each once, with nonempty
results, zero failures/skips and the configured Simulator. Missing/unsupported
RPC, stale or cross-owner reads, offline/restart caches, free/paid/rollback phase,
voluntary Basic, saved content and fresh checkout admission must be covered by
the finalized source/test contract. Do not mark the contract complete while its
method inventory is empty or a required scenario is untested.

The runner does not inherit compiler, xcconfig, backend, staging, preview or
DYLD/SIMCTL injection settings. It verifies actual optimized app and test compiler
commands, exact conditions, bounded response files, and file-list/output-map
binding to the required runtime and selected test sources. Every actual Swift
input must match a pinned source hash, including inputs not required by name;
unmanifested/ignored or external sources are rejected. Generated DerivedData
Swift inputs are separately hash-bound. Cache-only success,
requirements-only commands and a zero-selected-test exit are insufficient.

A successful schema-2 `validation-receipt.json` includes the unique run identity,
UTC execution chronology, exact clean HEAD/tree, complete app/test/script/backend
input hashes, lane/source/method scope, generated project/Info/lock/runner hashes,
actual compiler evidence, raw log digest, complete xcresult file inventory and
actual per-method results. Source and proof inputs must remain unchanged. Require
`nativeValidationPassed: true` and retain the complete output directory; copying
only the JSON does not preserve independently verifiable evidence. Prefer durable
private output paths outside iCloud. Generated projects and compiler response/map
paths are absolute, so revalidation runs at the original recorded paths. Verify
before relocation and preserve private byte hashes/recovery copies.

The held paid artifact guard independently re-reads both actual xcresults and
compiler logs, checks the paired evidence against the exact archive source and
pins their fingerprints before archive. It alone may derive
`preactivation_free_pro_supported=true` after those checks. That bounded native
claim never clears `delivery_ready=false` or authorizes activation. Earlier
static-paid archives and 86-test receipts remain prior evidence, not proof of the
new coordinated phase contract.

Run `python3 scripts/test_production_paid_validation.py` and
`python3 scripts/test_production_paid_distribution.py` for the synthetic adversarial
guards. These checks are not native execution. The focused Release lanes also do
not replace full ordinary free CI, signed package verification, live RPC/schema
compatibility and legacy-cohort checks, Apple prices, purchases/restores,
notifications/expiry/grace, or physical iPad preservation. This runner makes no
hosted deployment, billing transaction, Apple or physical-device change.

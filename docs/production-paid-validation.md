# Separate production-paid policy validation

The normal project and ordinary CI remain the free public-beta build. Keep their free-access assertions and strict public-beta archive verifier unchanged. Passing tests with an explicitly injected paid policy in that binary does not verify the compile-time paid client.

`scripts/run_production_paid_validation.py` generates a separate project outside the checkout, using the authoritative `project.yml` sources and pinned package resolution. Its Release app and test targets alone receive `ICHART_PAID_SUBSCRIPTION`; only the test target receives `ICHART_PRODUCTION_PAID_VALIDATION`. The original project, shared/global settings and package dependencies do not receive paid conditions. Release testability is enabled for native assertions; this Simulator test host is not a distribution artifact.

Choose a dedicated Simulator and a new local output directory outside iCloud. Prepare without starting a build:

```sh
python3 scripts/run_production_paid_validation.py \
  --output /private/tmp/ichart-production-paid-validation-PREPARE \
  --destination 'platform=iOS Simulator,id=REPLACE-WITH-EXACT-SIMULATOR-UUID'
```

Run the actual test gate using another new output directory and the same exact Simulator UUID:

```sh
python3 scripts/run_production_paid_validation.py \
  --output /private/tmp/ichart-production-paid-validation-RUN \
  --destination 'platform=iOS Simulator,id=REPLACE-WITH-EXACT-SIMULATOR-UUID' \
  --run-tests
```

The runner checks actual app/test build settings before execution, rejects Debug/staging/plan-preview flags and any observed dependency contamination, then requires every selected class to execute on that exact Simulator with zero failures/skips. It rejects zero-selected-test success and source changes during execution. Evidence stays in the output directory: generated spec/project, pinned resolution, build log, result bundle and source-bound JSON receipt. Preparation alone is not validation; require `nativeValidationPassed: true` in the receipt.

The focused scope covers paid **default** Basic, active Pro, cancelled-but-paid-through, expired and unavailable policy; new-creation limits while saved charts remain editable/exportable; original synthetic PencilKit source, converted-chart PDF links and applied premium fonts through persistence; read-only saved Projects; original/downloaded PDF bytes and local setlist references; re-upgrade; production-only backend configuration; production product IDs and $6.99/$60.00 targets; owner-bound claim recovery, server-record expiry/revocation and the existing local font/PDF/setlist preservation suites. The new build-scope assertion also runs in normal CI and strictly expects free defaults there. Paid-default cases compile in normal CI and skip unless the dedicated test marker is present.

This selected Release gate does not replace the full ordinary CI suite, signed distribution verification or Apple billing verification. Do not run the entire ordinary suite under paid flags and dismiss its free-specific failures. Existing free-only tests intentionally assert public beta behavior. Actual Apple-rendered price, subscription availability, purchase/restore, verified notifications, annual expiry, billing-grace compliance and production access remain separate release gates. This runner makes no network billing transaction or hosted deployment and does not certify the rollout as activated.

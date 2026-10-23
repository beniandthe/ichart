# PDF import: production review packet

Review base: refreshed `origin/main`, `5b5fe710e1627c7d83cf6de0fd43e00aabbbdd43`. Feature branch: `codex/pdf-import-setlists`.

## Resulting behavior

People can import an existing PDF from Files into the PDF Library or directly from a setlist's Add PDFs picker. The app retains the original document bytes locally, assigns a stable PDF-library ID, and uses that ID in setlists. Imported documents have their own provenance and do not claim native chart layout or transposition metadata. The importer validates a coordinated, security-scoped copy off the UI thread and commits its manifest before exposing the new item.

The physical proof exposed two preexisting entry blockers that are repaired here: a telemetry-consent/UserDefaults lock inversion that froze startup, and an offline profile request that left a recovered account signed out. Consent admission remains generation-checked; offline recovery applies only to a verified saved session with a typed transport failure during restoration. Interactive sign-in/signup and authorization failures keep their existing behavior.

PDF limits are 50 MiB and 200 pages. Encrypted, damaged, empty, non-PDF, and over-limit inputs are rejected. Camera capture, screenshot/image import, OCR, editable-chart conversion, and Pro Scan/OpenAI calls are outside this batch.

## Device acceptance

- The separate `com.ichart.app.pdfimportproof` app was installed on the iPad Air 4; the production bundle and recognition lab apps were not replaced.
- The user imported the supplied two-page fixture and saved it in a setlist. Device readback independently confirmed the owned file's exact bytes and the setlist's stable PDF reference.
- After the startup repairs, the user confirmed offline reopening and setlist/PDF readability.
- For the extended check, the user deleted the disposable original in Files, disconnected with Airplane Mode/Wi-Fi off, force-closed/reopened the proof app, and confirmed **both pages work offline**. Device file listing shows the original only in `.Trash`, with no active source at the original Documents path; the app-owned import and setlist remain present. The page-render result is a user report, not an agent-captured offline screenshot.

## Data compatibility and recovery contract

**Supported upgrade:** the current decoder accepts existing library/setlist manifests. Native exports and Forum downloads keep their IDs, relative paths, and metadata; adding imports does not rewrite their identities. The manifest remains an array and retains its existing location. New personal imports use the `personalImport` source and omit native-only metadata.

**Old-binary boundary:** iChart at `5b5fe710` cannot decode a manifest containing personal imports. Its enum does not accept `personalImport`, and its model requires native metadata absent from those documents. The old implementation refuses library mutation after decode failure, preserving files but making the PDF Library and related setlist references unavailable. Do not advertise backward compatibility or install that older binary over a container containing imports.

**Emergency feature rollback:** ship a newer, forward-compatible build that removes/disables the two import entry points while retaining the new decoder, optional-metadata presentation, imported-file directory validation, deletion recovery, and local-reader access. This stops new imports while preserving existing imported PDFs and setlists. Keep the startup fixes. Do not roll back the persistence model or delete/reinstall the app as a recovery procedure.

**Exceptional developer recovery:** close the app and preserve a complete app-data snapshot before investigating. At minimum retain the entire PDF Library (including `Imports`, every other PDF folder, and `.deletions`), the unmodified PDF manifest, and the entire Setlists folder. Record relative paths, byte counts, and SHA-256 hashes, and verify the copied snapshot before any mutation. Keep the snapshot immutable and restore only into a compatible build first so pending deletion recovery can run. Never discard import entries, fabricate native metadata, prune imported files, or rewrite their setlist IDs to make a legacy binary start. An old-binary experiment belongs in a separate disposable container with a separate preserved snapshot; it is not a customer recovery path.

Frozen legacy-decoder regressions document this boundary and verify current-version upgrade/reopen retention. They do not claim an installed old-binary downgrade test.

## Review validation

| Gate | Result |
| --- | --- |
| Physical source removal + both pages offline | User-confirmed pass; active original absent and owned import/setlist presence independently read back |
| Independent production-path review | No actionable correctness findings; schema recovery boundary documented above |
| Workflow scope predicates | 4 passed |
| Ordinary-build resource isolation | 7 passed |
| Simulator accessibility wrapper | 15 passed |
| Full Swift Package suite | 1,735 passed, 0 failed, 89 skipped |
| Full ordinary iChart simulator suite | 2,474 passed, 0 failed, 103 skipped; executed only on dedicated iPad A16 simulator `90A50B5D-884A-4CCD-B6F0-1E7EFD03A693`, iOS 26.5 |
| Ordinary unsigned production Release compile | Passed; `com.ichart.app`, 1.2.3 (78), production spec, experimental resources absent; no signing/install/archive |
| Frozen legacy/current compatibility contracts | Added after the full runs; 3 passed / 0 failed / 0 skipped on each native and Swift Package path, with no runtime-source changes |
| Backend contract suite | 666 passed, 0 failed, 0 skipped: 574 pure contracts, 85 pinned PGlite 0.5.8 cases, 7 real PostgreSQL 17.11 concurrency tests; isolated synthetic state only |
| Fresh PR CI, dependency review, actual Swift CodeQL analysis | Pending review PR |

The [production review receipt](qa/pdf-import-2026-10-23/production-review-receipt.json) records actual counts and source hashes. The detailed development/install/test receipts are linked from [the offline proof record](ichart-pdf-import-offline-proof-2026-10-23.md). Local full-suite outputs are in `/private/tmp/ichart-pdf-import-20261023/production-review/`. The initial sandboxed PostgreSQL attempt was denied shared-memory allocation; the exact isolated test passed after sandbox escalation. No live backend was accessed or changed.

## Integration boundary

This packet prepares a reviewable branch/PR. It does not authorize or claim a merge, production-container installation, signed archive, TestFlight upload, or public release. Production remains `com.ichart.app`, version 1.2.3 (78); a later upload needs a separately selected unused build number. No backend/schema change or OpenAI request is part of this batch. Graph/MyScript sources, worktrees, apps, data, and evidence remain outside the change.

# PDF import into setlists: implementation and offline proof

Implementation base: `origin/main` at `5b5fe710e1627c7d83cf6de0fd43e00aabbbdd43` (production iChart 1.2.3 build 78 source).

Scope: personal PDF file import, owned local storage, truthful document metadata, and existing PDF setlists. Graph/MyScript work remains separate and unchanged.

Status: PDF import succeeds on the physical iPad, and its saved setlist reference is present. The online startup deadlock and offline account-restoration bug are repaired. The replacement build is tested and installed; iPadOS requires developer-build trust/verification before the physical offline reader retest.

## Implemented behavior

- **PDFs > Import PDF** chooses one PDF in Files, lets the user name it, and opens its preview after durable import.
- **Setlists > Add PDFs > Import PDF** uses the same importer and selects the new item for adding.
- Personal imports keep their exact original bytes in Application Support and have stable library IDs. They display **Imported PDF / Original PDF**, page count, and size; native layout/transposition metadata is absent.
- Validation runs off the UI thread against retained PDFKit-readable bytes. It rejects damaged, empty, encrypted, non-PDF, over-50-MiB, and over-200-page inputs. Limits are centralized in `IChartPDFImportLimits`.
- Cancellation does not commit a partial import. The importer merges intervening durable library changes, saves the manifest before publishing, and rolls back the owned file on manifest-write failure.
- Existing library/setlist access and the current Pro — Free policy are unchanged. Camera capture, image import, and OpenAI conversion are later milestones.

## Verification completed

| Gate | Result |
| --- | --- |
| Release source | Refreshed `origin/main` at `5b5fe710e1627c7d83cf6de0fd43e00aabbbdd43`; existing production PDF/setlist code reused directly |
| Focused iOS checks | 106 passed, 0 failed, 0 skipped; dedicated iPad A16 simulator, iOS 26.5 |
| Focused Swift Package checks | 79 passed, 0 failed, 0 skipped |
| New import regressions | 11 executed on both native and package paths; original bytes/source removal, mixed setlist reload/reorder, legacy IDs/metadata, duplicates, billing access, malformed/encrypted/limited inputs, rollback, cancellation, intervening add/delete |
| Mounted reader | Imported second page renders after deleting the source and reconstructing the stores; title draft and existing navigation checks pass |
| PDF fixture | Both rendered pages visually inspected; 2 pages, 3,528 bytes, SHA-256 `43613ab545459532f19f0cd8186085ed638879da95f899317dbbd071eb40139c` |
| Device build/signature | Development build succeeded; strict deep signature verification passed |
| Device installation | Separate **iChart PDF Import**, `com.ichart.app.pdfimportproof`, version 1.2.3 (78), installed and read back |
| Device fixture | Copied to the proof app's Documents folder; device bytes read back and exactly match the fixture |
| Startup repair regressions | 53 passed, 0 failed, 0 skipped across telemetry, transport, privacy controls, PDF import, and mounted setlist reader tests |
| Physical startup repair | 1 UI check passed on iPad Air 4, iPadOS 26.6.2; normally launched proof process reached the signed-in library with the optional Quick Start banner, and two accessibility/screenshot captures returned |
| Offline-entry repair regressions | 95 passed, 0 failed, 0 skipped on the dedicated iPad simulator; includes all 10 new auth-restoration cases. Swift Package PDF checks: 42 passed, 0 failed. Replacement proof build and strict signature verification passed. |
| Physical PDF import | User reported "ok imported successfully" on October 23; exact file, both-page rendering, and screenshots were not supplied with that report |
| Device import/setlist readback | One personal import, stored as 2 pages / 3,528 bytes; owned PDF bytes match the supplied fixture; one setlist entry refers to that PDF ID. The disposable source is still present. This is storage evidence, not offline reader rendering. |
| Physical acceptance | Pending setlist use, source independence, and offline relaunch |

The initial native attempt caught a PDFKit option-type error in the new encrypted-fixture test. It was corrected before the passing run; no tests executed in that failed build. A separate proof-project attempt exposed a duplicate Info.plist resource; only the local proof configuration was corrected before its successful build. Existing compiler warnings remain.

Machine-readable evidence, including source hashes: [validation receipt](qa/pdf-import-2026-10-23/validation-receipt.json).

Local execution artifacts:

- `/private/tmp/ichart-pdf-import-20261023/PDFImportFocused02.xcresult`
- `/private/tmp/ichart-pdf-import-20261023/focused-native-02.log`
- `/private/tmp/ichart-pdf-import-20261023/focused-swiftpm.log`
- `/private/tmp/ichart-pdf-import-20261023/proof-device-build-02.log`
- `/private/tmp/ichart-pdf-import-20261023/DeviceDerivedData/Build/Products/Debug-iphoneos/iChart.app`

## Side-by-side proof build

The local proof spec was materialized from this branch's authoritative `project.yml`. Its changes are limited to a separate project/bundle/display name, private generated Info.plist path, an exclusive `ichart-pdfimportproof` URL scheme, Files visibility for disposable inputs, and excluding the original Info.plist from copied resources. It uses the exact tracked native package lock. The proof spec is `/private/tmp/ichart-pdf-import-20261023/proof-project.yml`.

The production bundle/configuration in the repository is unchanged. The public app and recognition lab bundles were not replaced. After the user brought the iPad online, the agent launched the proof app. The agent has not changed the device's network state. This is a development-signed installation, not TestFlight distribution or an App Store release.

## Physical startup diagnosis

The user reported completing sign-in, followed by a persistent loading/launch screen. The proof app's device report at 10:10 on October 23 confirms a watchdog termination (`FRONTBOARD`, `0x8BADF00D`) for a deadlock. The main thread held SwiftUI's update lock and waited for the telemetry consent lock. A utility thread held that consent lock while changing UserDefaults, whose synchronous SwiftUI observer waited for the update lock.

This path was inherited from the release base and was unchanged by the PDF feature. The repair separates memory-only consent admission from main-thread preference persistence, retaining generation checks for withdrawal, queue cleanup, and installation identity. Persisted consent is loaded at store initialization; the consent setter is the sole runtime writer. Five new regressions cover synchronous preference-observer reentry and stale identity/reset persistence. The focused 53-test run passed, and the replaced proof app reached the signed-in library on the physical iPad. The [sanitized diagnostic receipt](qa/pdf-import-2026-10-23/startup-diagnostic.json) records the evidence without copying the full device report into the repository.

The temporary UI runner attached only to the existing proof process, launched through devicectl with no XCTest environment injected into the app. It changed no app preferences, tapped no controls, and captured the library twice. Its first build failed because the temporary runner lacked a product name; the corrected runner executed one passing test. This confirms startup and returning accessibility snapshots; physical Files import and offline persistence remain separate gates. Local results: `/private/tmp/ichart-pdf-import-20261023/StartupRegression01.xcresult` and `/private/tmp/ichart-pdf-import-20261023/startup-diagnostic/StartupAfterFix02.xcresult`.

Installation-ID persistence is now asynchronous. Abrupt termination before the first identity write may split analytics continuity across identifiers. The ingest validator accepts event identifiers independently of batch context, so this window does not block delivery of the durable backlog.

The separate proof scheme also differs from the production auth callback scheme. Existing-account password sign-in does not use that callback. Email verification and password-reset links are outside this proof walkthrough until proof-specific callback routing is configured.

## Offline account-entry diagnosis

The user reported "The internet connection appears to be offline" inside the account/sign-in screen after reopening offline. A nonexpired saved SDK session can restore successfully without a request, but the app then awaits a separate profile fetch before publishing its restored account state. If that request fails offline, the cold-start state remains signed out and the account cover blocks local content. The preexisting expired-session path already maps a connectivity failure to `temporarilyOffline`; the valid-session/profile path did not.

The repair is limited to restoration of a recovered, verified session: a typed profile transport error selects `temporarilyOffline` without clearing the saved session or local documents. Authorization errors, missing profiles, malformed sessions, unverified users, and interactive sign-in/signup remain outside that fallback. All ten injected-service regressions passed within a 95-test native run; the 42 selected Swift Package PDF tests also passed. The replacement proof build passed strict signature verification and was installed. Both device manifests were read back unchanged after the update. See the [offline-entry diagnostic receipt](qa/pdf-import-2026-10-23/offline-entry-diagnostic.json).

The attempted offline UI diagnostic did not execute its test because iPadOS refused to launch the separate test runner with an untrusted developer certificate. That runner launch limitation is separate from the user's in-app profile error and provides no offline reader result. The earlier proof build launched through devicectl with the normal environment. After installing the offline-entry repair, iPadOS also denied the new proof build's launch for signature/entitlement/profile-trust reasons. The user was asked to reconnect briefly, open the new build once, then disconnect and repeat the physical offline entry/reader checks. The agent has not changed network settings.

## Offline iPad walkthrough

1. Open **iChart PDF Import** on the iPad. Sign in with the existing iChart account while online and finish the normal entry flow.
2. Open **PDFs**, then **Import PDF**.
3. In Files, browse **On My iPad > iChart PDF Import** and choose `ichart-pdf-import-offline-proof.pdf`.
4. Name it **Offline Import Proof** and tap **Import**. Verify both pages: page 1 starts with `Cmaj7` and ends with `G7`; page 2 starts with `F#m7b5` and ends with `C6`. Close the preview with **Done**.
5. Open **Setlists > New Setlist**, name it **PDF Import Proof**, and tap **Create**. Tap **Add PDFs**, select **Offline Import Proof**, and tap **Add 1**. Open the song and verify both pages again. A native export can be added to the same setlist for the mixed-document check.
6. In the Files app, delete only the disposable input at **On My iPad > iChart PDF Import > ichart-pdf-import-offline-proof.pdf**. Keep the saved PDF Library item and the setlist.
7. Force-close **iChart PDF Import**. Enable Airplane Mode and turn Wi-Fi off. Reopen the proof app, open the setlist/song, and confirm both pages remain readable. Confirm title, ordering, and navigation are retained.
8. Record any failure at its exact step and the visible message. Successful installation or the automated tests do not substitute for this physical result.

The test fixture is also available at [the generated PDF](../output/pdf/ichart-pdf-import-offline-proof.pdf). Recreate it using `scripts/create_pdf_import_proof.py` with ReportLab available. It contains only self-authored test material.

## Remaining release work

- Complete the physical picker/presentation/offline acceptance gate and any resulting fixes.
- Review this feature branch before production integration. A public build/version change, archive, TestFlight upload, and public release remain separate work.
- Before shipping into the production container, define rollback/migration handling: older binaries do not understand the new `personalImport` source. The proof app's separate container avoids exposing existing production data to that compatibility issue.
- No backend was changed, no API key was accessed, and no OpenAI requests were made. Graph/MyScript implementation, evidence, and installed lab apps remain outside this change.

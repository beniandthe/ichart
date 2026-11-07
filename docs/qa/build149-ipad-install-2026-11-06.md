# Build 149 iPad installation — November 6, 2026

Build 149 (1.2.4) from `d8774fa7cdeb2270d169200e14d2a09264335cd5` is installed on Ben’s iPad Air 4 / iPad13,2 running iPadOS 26.6.2. The main app was normally launched, observed running for eight seconds, stopped for saved-data readback, then normally reopened and left running for user testing. No preview or test arguments were passed to the main app.

## Artifact

The app source matches the accepted candidate. Xcode compile/link completed; its signing step encountered the existing FileProvider Finder-metadata error. A metadata-cleaned copy was signed with the existing development identity and generated entitlements, and passed deep/strict signature verification. Entitlements match Build 148; the existing provisioning profile includes this iPad. Bundle ID, version, build, full artifact file hashes, source hashes, and installed/running app identity were verified. Personal ML comparison resources remain excluded.

## Preservation

The user confirmed all chart edits and typed review/correction text were saved before closing the exact Build 148 process. Two fresh stopped full-container snapshots matched byte for byte and were frozen locally. Installed-before-launch readback preserved the saved library and files. Two independent stopped postlaunch snapshots also matched byte for byte.

Final comparison preserved 17 charts, 334 ink archives (323 source, one handwritten header, ten handwritten notation), 21 PDFs, one setlist with 15 references, three correction/profile files, and intentional deletions. No older library was restored. The saved decoder/source and signed candidate are retained locally with the snapshots.

The whole container is not byte-identical across launch. Known forward cloud clocks, order-only tombstones, platform snapshots/caches, append-only technical trace, and a fresh technical queue transition are classified separately. The sole additional library difference is a backward subscription-verification date; its exact before/after library and scalar hashes are pinned. Existing StoreKit refresh and remote-record date mapping code is unchanged from Build 148. This is consistent with pre-existing metadata refresh and does not prove the server response, backend subscription correctness, or access health. Only that scalar is normalized in a local deep copy; device/snapshot data is not rewritten. All other library fields remain strict.

The local comparator extension rejected six in-memory tampering cases, including unrelated subscription status, selection, chart content, source ink, and evidence/hash changes. An independent exact-code and bounded-evidence review found no actionable defect. The retired diagnostic checkpoint remains byte-identical with its pre-existing invalid binding; it is not an ink-loss or freshness claim.

## Physical and Simulator evidence

The prior Simulator pass remains 99 selected tests plus three external UI tests, with six focused duplicate rechecks after the Measure Layout contrast correction. The final one-line Library action-icon color correction compiled and was visually reviewed in light/dark appearance.

Two disposable physical QA attempts timed out enabling XCTest automation before feature test methods ran. A normal QA-only foreground launch succeeded. The synthetic QA charts and tombstones were preserved, and both disposable QA bundles were removed. These attempts do not establish Build 149 physical tool acceptance. The successful main-app startup/readback is separate from fresh Pencil input, which remains for the user’s manual test.

## Verification process note

An overly broad local helper-review search displayed chart/ink backup content unnecessarily. That review was stopped; the search did not modify backup or app/device data. Subsequent review was restricted to exact code files and bounded technical evidence.

Evidence, immutable snapshots, signing manifest, process records, and the installation receipt are under `.build/semantic-clarity-20261106/install149/`. No push, merge, or public release was performed.

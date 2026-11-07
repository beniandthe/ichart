# Write & Render entry crash — November 6, 2026

## Physical-device evidence

The user reported a crash immediately after tapping **Write & Render** in iChart 1.2.4, Build 146. The physical iPad report is retained locally at `.build/write-render-crash-20261106/iChart-2026-11-06-095337.ips`. Its report timestamp is **09:53:37 Pacific** on November 6, 2026; the embedded capture time is 09:53:35.7746.

The report identifies binary UUID `C62042FF-A918-37F0-863E-52700E4CEA7C`, iPadOS 26.6.2 (23G90), and `EXC_BAD_ACCESS` / `SIGSEGV` in the main-thread stack guard. The mapped stack is 1008 KB, with a 16 KB guard. The crashing frames repeatedly decode Swift generic type arguments (`swift::Demangle` / `TypeDecoder`). After the app's type-instantiation helper, the first feature frame is `closure #1 in EditorView.chordDraftActiveToolActions.getter`, followed by `automaticChordCommandControls`, `automaticChordToolControls`, and the editor toolbar.

The matching compiled metadata at that feature frame expands the nested styled `activeToolButton` type. This supports a toolbar generic-metadata stack overflow at entry. It is separate from handwriting recognition accuracy or rendering acceptance.

## Narrow repair

`EditorView.swift` now puts the existing styled button inside a concrete `EditorToolActionButton: View` component, and the chord draft action row has an `AnyView` boundary. These boundaries keep the nested button modifier and conditional row types from expanding throughout the toolbar.

The moved button implementation compares byte for byte with the original body. The row also compares byte for byte after removing the new type wrappers. Labels, action handlers, disabled states, accessibility, visibility rules, and reserved toolbar heights are unchanged. No recognition or source-ink ownership/consumption behavior changes.

The quick explainer, local Guide, rendering mode labels, and reachable render/review/clear controls were checked against this structural change. Their behavior and instructions remain aligned, so guidance copy is unchanged.

## Validation status

- Source/body equivalence and `git diff --check`: passed.
- New regression: `FormMarkerPlacementUITests.testColdWriteAndRenderEntryAndReentryAcrossLayoutsAndModes`, covering normal entry/re-entry in both layouts and both render modes.
- Candidate Build 147: device compile/link passed; metadata-cleaned artifact signed with the existing development identity and generated entitlements; deep/strict signature verification passed. The initial Xcode signing attempt hit File Provider FinderInfo metadata.
- Focused Simulator workflow suite: **62 passed, 0 failed, 0 skipped**.
- New cold-entry/reentry native Simulator test: **1 passed, 0 failed, 0 skipped**, covering four cold launches and eight Write & Render entries.
- Physical iPad native UI test: **1 passed, 0 failed, 0 skipped** on Ben’s iPad Air (4th generation), iPadOS 26.6.2. The same editor source ran in disposable `com.ichart.claritycrash20261106`, using two blank synthetic charts and offline service configuration. Both layouts × Automatic/Manual passed cold entry and Done → reentry: **four cold launches, eight successful entries**.
- Physical screenshots confirm visible guidance and reachable Write/Erase/Done controls. This covers toolbar construction and entry; it is not fresh Pencil recognition acceptance.
- Personal app replacement: **Build 147 installed** after fresh saved-work confirmation and independent byte-identical stopped backups. Prelaunch and postlaunch preservation checks passed for all **17 charts**, all **331 saved ink archives**, **20 PDFs**, the **15 setlist entries**, and **3 correction/profile files**. Intentional deletions are preserved. Normal startup clocks, performance trace appends, technical queue rotation and system metadata are classified separately; the full container is not byte-identical after launch. The retired diagnostic checkpoint is unchanged with its existing stale binding.
- Independent postlaunch snapshots matched byte for byte. The disposable physical QA app and runner were removed after their evidence was saved.

The prior Build 146 Simulator results missed the physical stack limit. The new physical native UI test verifies the repaired construction path with synthetic saved charts. Fresh Pencil recognition and the user’s own chart workflow remain separate acceptance checks.

Local evidence is under `.build/write-render-crash-20261106/`: `crash-analysis.json`, `hosted-summary.json`, `cold-entry-simulator-summary.json`, `cold-entry-physical-summary.json`, `physical-attachments/`, and `signed-build147-manifest.json`.

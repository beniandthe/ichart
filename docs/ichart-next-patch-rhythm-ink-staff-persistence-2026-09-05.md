# iChart Next Patch Intake: Sheet Staff, Pagination, Ink Persistence, Performance, Chord Editing, And Measure Editing

Status: implementation candidate covers repeat-leading staff rendering, dense-ink churn, header/viewport anchoring, margins, Join Row, rotation reprojection, compact cue-text entry, roadmap-symbol font normalization, and a full chord/Free-Write responsiveness pass; the exact latest signed build is installed with the chart library preserved, while direct physical Pencil feel and orientation/UI behavior remain acceptance gates
Date: 2026-09-05
Reported from: physical iPad chart-authoring pass

## Observed User Report

While making a chart in Rhythm Sheet:

- The user wrote four bars on the first staff.
- The user added a repeat sign for those first four bars.
- The leading system's staff lines disappeared. The clef and key signature still appeared, but the actual staff lines were gone.
- The user has seen similar behavior in Simple Chord Sheet.
- Ink appears to shift up/down/around when clicking between different tools.
- Overall ink speed feels too slow while writing, not just during one isolated dense-page case.
- The user suspects the slowdown is related to sync/persistence state.
- With a good amount of rewrite ink already on the page, writing chords feels very slow, with visible drag/weight in the stroke response.
- The user suspects the slowdown may be related to persistent ink state.
- While erasing free-write ink, erasing is also very slow.
- Some erased free-write artifacts pop back after being erased.
- Free-write erase persistence must treat erasure as authoritative, so stale saved ink or sync replay cannot resurrect deleted strokes.
- The user is seeing root-recognition issues again, this time around `G` and `B`.
- In a current two-chord reproduction, the first `B` temporarily previewed as `C`; after the user added `G`, the drafts changed to separate `B` and `G` previews. A second attempt behaved similarly.
- The user expects the `G`/`B` root issues to be checkable in telemetry.
- Flats and other accidentals can register as completely different notes when written slightly too far from the base letter.
- The recognizer needs more grace for the space between a base note and attached flats, accidentals, or other chord qualifiers, without collapsing separate neighboring root letters into one accidentalized root.
- Rendered Rhythm Sheet chords visually look close to the correct placement, but the edit box is too large.
- Because the edit box is too large, the chord appears to render outside the intended first beat slot even when the chord text itself looks roughly placed.
- When the user tries to adjust chord size, the chord snaps back.
- The snap-back behavior appears to affect all adjusted chords, not just one isolated symbol.
- In Simple Sheet edit mode, a measure with three chords will not let the user move the third chord to the fourth beat.
- During that drag, the editor shows the green placement state for the last beat, but releasing the drag snaps the chord back to the third beat.
- Simple Sheet rendered chord drag preview and committed placement state are therefore disagreeing.
- Simple Sheet chord movement also varies by measure density. In the first measure of the final system, the user could not move `Bb` or `C`, while the next measure's chords could be moved.
- The Rhythm Section Measures tool has no Join Measure feature.
- Joining adjacent Rhythm Section measures needs to be implemented.
- More broadly, Rhythm Section measure edits are not functioning as expected.
- Resizing a Rhythm Section measure can affect staff/system layout above it.
- Resizing can also change the beat placement of later measures and sometimes makes later measures larger.
- The Measures tool does not provide an Even Row / equalize-row action for Rhythm Section.
- Rhythm Section measure editing needs to realign with the Simple Chord Sheet measure-tool behavior where the contract is shared.
- A Rhythm Sheet created with 32 starting measures extended the first page instead of keeping the page at normal paper height.
- The first page became extraordinarily long, beyond a real chart page.
- Tapping Add Page then created a real new page with an extra measure, but the chart should not have needed a manual Add Page action to recover from the first page being overlong.
- The first page should snap to fixed page engraving bounds. If the starting measure count exceeds what the page can comfortably engrave, the layout should tighten/pack measures or paginate, not elongate the paper frame.
- In both Simple Chord Sheet and Rhythm Section Sheet, Add Text visually takes over almost the entire iPad instead of presenting a compact writing surface.
- Coda and other roadmap/form-marker symbols render at wildly different visual sizes across the bundled notation fonts. At the largest marker setting, Finale Broadway's coda appears tiny while Petaluma's appears huge.

This note remains a defect/verification record. Simulator coverage is not a physical Pencil acceptance claim.

## Attached Screenshot Evidence: 2026-09-05

The four supplied screenshots are evidence from the same "Nadie Como Tú" chart, but they do not all show the same editor mode or selection geometry:

- `IMG_0275.PNG` at 5:15 PM shows Edit / Measures with dense handwritten rhythmic notation across the first system. The selected fourth-measure box is measure-selection geometry, not a chord edit box.
- `IMG_0277.PNG` at 5:22 PM shows Repeats with the first four-bar repeat present and the staff lines still visible. The large blue box around `Bb sus` is again selected-measure geometry. This screenshot supports the four-bar repeat reproduction, but it does not capture the reported staff-line disappearance.
- `IMG_0278.PNG` at 5:24 PM shows the actual Edit / Chord selection for `Bb sus`. Its chord edit box is smaller than the measure boxes in the prior screenshots, but it still contains excess horizontal room and exposes the trailing resize handle, matching the reported chord-width/resize path rather than the repeat selection path.
- `IMG_0281.PNG` / `IMG_0281 2.PNG` at 5:43 PM shows the same chart with the structured chords preserved, while the earlier dense first-system rhythmic writing is no longer visible and handwritten marks overlap the clef/key-signature area of the following system. It also shows the repeat-specific staff defect more precisely: systems beginning with a repeat draw five lines across the musical measures, but the lines are absent underneath the leading clef/key-signature setup extension. The screenshot sequence supports the reported ink-loss/coordinate-shift class; the correlated telemetry below identifies the 33-to-19 measure reprojection that immediately preceded it.

Evidence boundary:

- The staff lines are not wholly absent: `IMG_0281 2.PNG` captures the narrower defect. On repeat-leading systems they start at the repeat/first-measure boundary instead of the system edge, leaving the clef, key signature, and first-system meter without staff lines behind them.
- The screenshots contain no raw strokes, glyph candidates, grammar decisions, trust state, or replacement history for the reported `G`, `B`, or spaced-accidental recognition failures. Recognition code is intentionally unchanged until a current DEBUG trace identifies the failing layer.
- The screenshot sequence and production coordinate-reprojection telemetry point toward changing page/layout coordinates, not a recognition failure, for the displaced ink.

## Physical iPad Follow-Up Evidence: 2026-09-07

The user continued editing the same `Nadie Como Tú` chart in the patched development build and supplied portrait and landscape captures:

- `IMG_0282.PNG` at 4:27 PM shows the chart in portrait. The viewport begins inside a paper page rather than at the page top, the document header is not visible, system widths and apparent inner margins vary substantially, and the next-page selected-measure overlay spans a broad area relative to the staff.
- `IMG_0283.PNG` at 4:29 PM shows the chart in landscape after rotation. Systems, handwriting, page breaks, blank space, and the selected-measure overlay occupy visibly different page-relative positions from the portrait capture. The music uses only part of the wider paper in several rows while other rows extend farther, so the apparent left/right engraving margins are not consistent.
- The two screenshots are direct evidence of orientation-dependent reflow and ink/page-layout instability. They do not by themselves prove that every handwritten mark changed coordinates because the viewport and visible page regions also changed between captures.
- The page header is visibly absent in both captures, but the current device container still stores `title = "Nadie Como Tú"`, `composerCredit = "Maverick City Música"`, `styleNote = "Son / Salsa"`, and `headerInputMode = "typed"`. The evidence therefore supports a header rendering, page-position, or scroll-restoration defect; it does not support model-level header deletion.
- The current chart contains five model systems with measure counts `4, 4, 5, 2, 7` and many persisted manual widths. The final system alone mixes four approximately `114.1`-point measures with approximately `96.5`, `269.5`, and `263.5`-point measures. That stored geometry corroborates the visibly uneven rows and margins, although it does not yet establish which editor transaction created each width.

The user's latest Pencil report is density-dependent: ink initially felt better, then began to drag and feel unresponsive as more ink filled the page. A fresh read-only capture of the patched app's local `performance-trace.jsonl` covers the 4:19–4:29 PM session:

- Page ink increased from 52 strokes / 23,776 persisted bytes at 4:20:05 PM to 93 strokes / 33,050 bytes at 4:21:51 PM, then 96 strokes / 36,554 bytes at 4:23:48 PM.
- Maximum persistence work in the aggregate windows was commonly about 2–8 ms, but reached 12.19 ms at 87 strokes and 15.49 ms at 96 strokes.
- Drawing batches were repeatedly followed by chart write-backs and multiple layout invalidations. One 3-change batch at 64 strokes was followed by 4 chart write-backs and 12 layout invalidations; a 5-change batch at 78 strokes was followed by 3 write-backs and 9 invalidations.
- This supports the reported relationship between page density and degraded responsiveness, and makes per-drawing persistence/write-back/layout churn a concrete suspect. The trace does not measure Apple Pencil contact-to-pixel latency, so it does not prove that persistence is the only or primary cost.
- The manual-erase sampling optimization already in this patch is not a general dense-writing latency fix. Ink-writing responsiveness remains open until a device pass measures the live stroke path and bounds write-back/layout work during drawing.

The requested `Join Row` behavior is a separate operation from the implemented `Join Measure` command:

- Select a measure, invoke `Join Row`, move that whole measure into the rendered row immediately above, and automatically equalize the measures in the destination row.
- Preserve the moved measure's musical identity, chords, rhythm content, repeats/endings, and attached ink. Do not merge its contents into an adjacent measure.
- Do not reflow or resize unrelated rows. If there is no preceding row, the command must be unavailable or have an explicit no-op state.

Latest read-only device and production evidence for the `B`/`G` and compact-measure drag reports:

- Production telemetry for build 51 on the reporting iPad contains two separate preview attempts at 5:52 PM local time. Both began from an empty preview. The first progressed from one trusted target to two trusted targets; the second progressed from one trusted target to two targets with one trusted and one confirmation decision. Aggregate telemetry deliberately contains counts and confidence classes, not raw chord text.
- The local chord-preview trace contained only a reset marker at 5:59 PM because every canvas creation truncated the file. Switching charts after reproducing `B`/`G` therefore destroyed the raw preview sequence before the container pull. This is an observability defect, not evidence that recognition did not run.
- The `Nadie Como Tú` model still preserved the final three pending Pencil strokes. An exact local replay groups them sequentially into two targets: `B` at confidence `3.759` with `D` close behind at `3.695`, and `G` at confidence `3.970`. The current trust policy correctly requires confirmation for the low-confidence `B` and trusts `G`. Replaying only the first persisted stroke produces no read, not `C`, so the temporary `C` report is not yet reproduced by this saved final drawing.
- The installed production telemetry ingest function is version 8 and drops the newer issue-bucket properties. The local source already permits those fields, but no live Edge Function deployment was performed as part of this patch investigation.
- The likely Simple Sheet reproduction chart's final system contains six compact measures with `manualLayoutWidth = 96`. In the reported first measure, `Bb` and `C` use wide default chord frames whose edit halos overlap. The next measure's two chords have explicitly narrowed display widths, reducing overlap. Router inspection confirmed that an unselected neighbor's equal-priority move halo could win first and then be rejected, leaving no drag target for the selected chord.

## Physical iPad Follow-Up Evidence: 2026-09-08

The user reported that changing Simple Sheet settings, specifically the displayed key and chord transposition, moved existing page ink during the current IPA pass.

- On the later physical-iPad chord pass, the user tried multiple handwritten variations of `B`, `C`, `D`, and `G` and did not reproduce the earlier wrong/transient previews. No recognition grammar, candidate-ranking, or trust-policy change was made in this latency pass, so this is a current non-reproduction rather than evidence that the root-recognition issue was fixed.
- The same pass reported that ink erasure now felt good. That is current physical evidence for erase feel, but erase persistence across close/reopen and relaunch remains a separate acceptance case.
- The newly reported failure was visible chord-ink latency: when writing a chord quickly, Pencil ink took a noticeable time to appear on the page. A read-only container capture was taken immediately at `/tmp/ichart-chord-ink-latency-live-20260908.kGFqu7` before changing the installed build.
- In that capture, final recognition batches for the reported session produced `B△7`, `G△7`, `C△7`, `D△7`, and `G△7`. A representative final recognition execution took about `18.6 ms`, and all targets in that batch took about `63.4 ms`; persistence was sub-millisecond with drawing payloads around `0.8–6.5 KB`. One batch took about `209 ms` wall-clock while doing only about `4.9 ms` of recognizer execution, exposing queue/wait time rather than a slow classifier.
- The retained chord diagnostic reached about `1.38 MB` across 104 JSONL records, including individual records near `49 KB`. Source inspection confirmed that those large diagnostic payloads were synchronously JSON-encoded and appended from UI-triggered paths. It also confirmed that superseded serial recognition batches kept running after new Pencil contact; the host rejected only their eventual completion, so obsolete work could continue competing with the live stroke path.

- A 10:07 AM physical-iPad screenshot taken after installing executable UUID `E7AD572E-099B-3082-BBBD-ADC4C8813FA9` disproved the first cue-text sizing fix. The card was correctly narrowed to about 420 points, but it still occupied almost the entire available height: Cancel/Text/Add floated near the vertical center and the 72-point input remained at the bottom. This proves the visible defect was the outer panel height, not merely the text field height or backdrop color.

- The connected iPad still identified the installed app as iChart 1.2.1 build 51 and as a developer app. That version/build pair is not sufficient to identify this worktree because the Debug target has not advanced the marketing version or build number.
- The pulled chord-preview trace contained only the latest reset marker. Current source retains earlier chart-session markers across canvas recreation, so this container proves that the installed developer app predates at least the current trace-retention change. It is not valid physical-device evidence against the complete current worktree.
- The pulled Simple Sheet chart stores 21 page-ink strokes in a legacy `724 x 1120` coordinate space. Replaying that saved drawing into the current `732 x 1020` page layout moves 13 of 21 stored strokes, with a maximum center displacement of 79 points. This is an existing-coordinate migration effect, not a key-recognition or chord-transposition result.
- The live performance trace records the Simple Sheet canvas at exactly `800 x 1200`, which is the page size used for the saved-state replay. No settings transaction was retained in that trace, but the replay is not relying on a guessed viewport size.
- After first projecting that exact saved drawing into the current layout, changing the displayed document key by one semitone moved 0 of 21 strokes, changed 0 measure-anchor frames, and had a maximum displacement of 0 points. Transposing the chart's chords by one semitone produced the same zero-movement result.
- The exact saved-state regression gate is `testReplayDeviceSimplePageInkRemainsFixedAcrossKeyAndChordTransposition`. Result bundle `/tmp/ichart-keychange-current-before.xcresult` selected 1 test and passed 1 with 0 failures or skips.
- A deterministic non-device-state regression, `testSimplePageInkRemainsFixedAcrossKeyAndChordTransposition`, is also part of the normal suite. Result bundle `/tmp/ichart-keychange-regression-20260908-1.xcresult` selected 1 test and passed 1 with 0 failures or skips.
- The first fresh physical-device build compiled and linked the current source, then blocked inside Apple code signing while `SecurityServer::ClientSession::generateSignature` waited on the development identity. That hung attempt was interrupted without installing anything.
- On the user-requested retry, the same current worktree built successfully. The interrupted attempt had left Xcode's known missing-`iChart.cstemp` resource-seal defect in the incremental product; re-signing the disposable app artifact with the same development identity completed, and `codesign --verify --deep --strict` then passed.
- The verified Debug app was installed over `com.ichart.app` and launched successfully on the connected iPad. The installed product came from `/tmp/ichart-keychange-device-dd-20260908/Build/Products/Debug-iphoneos/iChart.app`; its arm64 executable UUID is `B8B47B83-FAC2-3E4B-B754-58F109515A98`.
- A pre-install backup is at `/tmp/ichart-preinstall-20260908.ghr2Bh`, and the post-install capture is at `/tmp/ichart-postinstall-20260908.QNl4kz`. Their `library-state.json` files are byte-for-byte identical (`402,349` bytes; SHA-256 `42a01b338431afc6010a0bbe873827f20074c1a486c6d62a6a05148c46c83b3d`). All three charts remain present: `Untitled Chart`, `Nadie Como Tú`, and `Higher Love`.
- The post-launch chord diagnostic still contains only the pre-install reset marker because launch stopped at the library and no chart canvas had been opened yet. Trace-retention behavior must be checked after opening a chart; it is not claimed from app launch alone.
- The user then reproduced a much larger key-change failure in the live `Nadie Como Tú` Rhythm Section chart without switching charts. The immediate container capture is `/tmp/ichart-keychange-live-20260908.f6lRe4`; its retained chord trace grew from one to three lines and its performance trace grew from 1,052 to 1,500 lines, confirming that the new trace-retention behavior is active.
- The exact chart diff isolates the failure. Changing the displayed key from G major to C-flat major left all 22 measure IDs, the five model systems (`4, 4, 5, 2, 7` measures), manual widths, page-ink bytes (`87,872` base64 characters), and saved `732 x 2088` ink coordinate space intact. Only the key and transposed chord symbols changed.
- Despite that stable model and ink payload, the renderer changed from six systems at 3:58:20 PM to eight systems at 3:58:32 PM on the same `800 x 2168` canvas. Seven flats enlarged every leading signature gutter by 60 points; the packing algorithm incorrectly charged that engraving-only width against the musical row body and wrapped the two-measure and five-measure rows. The ink anchor policy then correctly followed those measures into the wrong new systems, producing the reported large vertical displacement.
- A patched exact-state replay now renders both snapshots as the same six rows (`4, 4, 5, 2, 5, 2`). All 174 saved PencilKit strokes preserve their system-relative vertical position with a maximum vertical center displacement of `0.00` points. Maximum horizontal movement is `61.00` points because the seven-flat signature legitimately widens the setup gutter and the same row is proportionally fitted into the remaining body width.
- A fresh signed Debug product was built at `/tmp/ichart-keylayout-device-dd-20260908/Build/Products/Debug-iphoneos/iChart.app`, verified with `codesign --verify --deep --strict`, installed over `com.ichart.app`, and launched on the connected iPad. Its arm64 executable UUID is `4A4AE322-6D42-3A44-BFA5-A2313F410826`; the unchanged target metadata still reports version 1.2.1 build 51.
- The immediate post-install capture is `/tmp/ichart-keylayout-postinstall-20260908.BGe6fF`. Its `library-state.json` is byte-for-byte identical to the live pre-install reproduction (`402,378` bytes; SHA-256 `d976547b56642eb70adda12b3fa34638a75f2f3888f0bbb136b0ddabca092299`), proving that the overwrite preserved the C-flat `Nadie Como Tú` model, its five saved systems, and its existing ink payload.

Visual acceptance remains physical: with executable UUID `4A4AE322-6D42-3A44-BFA5-A2313F410826` now open on the iPad, change only the key and transpose controls while watching the existing ink. If ink still moves in this exact build, capture the container immediately before switching charts so the retained trace and stored coordinate state remain available. Legacy coordinate migration and current semantic-setting stability must remain separate acceptance cases.

## Implementation Findings And Changes

- Reworked the shared cue-text entry overlay used by both chart styles into a compact panel: maximum width `420` points with `20`-point narrow-screen margins, a `72`-point scrollable text area, tighter spacing/padding, and no visible full-canvas dimming. The first pass constrained only the width and input; the 10:07 AM device screenshot proved that the UIKit-backed Cancel/Add row still accepted the overlay's full vertical proposal. The follow-up now constrains that row to `36` points and the complete card to `146` points, so the outer material cannot expand to iPad height. The invisible outside-tap capture remains so keyboard focus and dismissal behavior stay controlled without making the page look like a full-screen editor.
- Normalized shared coda and segno typography from the selected font's actual bundled SMuFL glyph bounds rather than applying one raw point size to every font. The renderer targets a consistent `3.5` staff-space symbol height with a bounded correction factor without changing marker layout frames or causing chart reflow.
- A later physical-iPad comparison disproved the original standalone-marker acceptance claim even though the raw glyph-outline tests were green. Finale Broadway reports an approximately `160`-point attributed line box for the maximum-size Rhythm Coda whose visible outline is only approximately `26.8` points high; Petaluma reports an approximately `44`-point line box for the same normalized visible height. The generic text fitter therefore shrank Finale Broadway a second time. Standalone Coda and Segno now bypass attributed-text line-box fitting and draw the actual normalized vector outline centered in the existing marker frame. The same renderer is used by the editor and PDF export. Inline To Coda and D.S. al Coda remain on the mixed text/symbol path and are a separate visual acceptance case.
- Fixed the root page-bounds defect: the layout engine previously used the editor viewport height as logical paper height whenever the model had no explicit page break. A 32-measure chart could therefore stretch one paper page; adding a page happened to switch it into fixed-page behavior. Paper height is now fixed and system plans automatically paginate by per-page capacity, while explicit Add Page boundaries remain authoritative.
- Kept free-write coordinate space stable across viewport-height changes. Automatic pagination and page/measure anchors now resolve identically for the same chart at compact and tall editor viewport heights, preventing the old viewport-driven reprojection path represented in the telemetry and screenshot sequence.
- Correlated the screenshot timeline to the privacy-safe production session for the 32-measure Rhythm chart. At 5:42:51 PM, the measure edit changed the chart from 33 to 19 measures and immediately reprojected the same 44 page-ink strokes (881 points) from a `724 x 2944` canvas into `724 x 1248`. This proves the 5:43 screenshot's displaced ink was a layout-driven coordinate collapse, not stroke loss at that transition. Page ink attached to surviving measures still follows its anchors; unmatched annotations and ink near removed measures now preserve page-local scale and position instead of falling back to whole-document vertical compression.
- Fixed Rhythm repeat-leading staff geometry. A repeat marker remains attached to the musical measure boundary, but can no longer define the staff's left edge; all five lines now begin at the system edge and run behind the clef, key signature, and first-system meter. The existing invalid-span fallback remains in place, and the regression now uses a five-flat key plus a leading repeat to assert that the setup region is covered.
- Fixed Simple Sheet drag commit/render disagreement by allowing stored multi-chord lane fractions to select later beat guides while retaining ordered, unique chord slots. The third chord in a three-chord 4/4 measure now persists at beat four through encoding/reopen.
- Fixed compact-measure chord targeting. Equal-priority overlapping chord bodies now select the chord nearest the touch, and drag routing filters out unselected neighbors before resolving priority. An overlapping `Bb`/`C` pair can no longer let the first provider-ordered move halo block the selected chord.
- Fixed deliberately moved lone Simple Sheet chords snapping back to slot one. A committed move now renders on the nearest beat guide, bounded to keep the full symbol inside the measure; an initially recognized lone chord still receives the normal first-slot layout.
- Fixed Rhythm chord resize snap-back by applying the stored `manualDisplayWidth` during layout instead of always recomputing natural text width.
- Changed Rhythm measure edit/select/resize geometry to the musical staff body instead of the first measure's broader clef/key/time-signature reserve.
- Added Rhythm Even Row behavior using musical body widths for only the selected rendered row.
- Added Rhythm Join Measure for safe adjacent measures. Chords, cue positions, roadmap offsets, repeat/ending anchors, and supported annotations are remapped to the merged lane. Joins are refused when a different meter/key/grid, a manual row/page boundary, rhythm maps, pitched/rhythmic ink, or right-measure attached free-write would make the merge lossy.
- Added Join Row as a distinct, nondestructive row operation. It moves exactly the selected row-leading measure into the preceding row, preserves that measure's ID/content/attachments, moves the explicit row break to the following measure so unrelated measures do not flow upward, and atomically equalizes the destination row. Page breaks, key-change boundaries, first-row selections, incomplete width plans, and rows that cannot fit the minimum readable measure width are refused without a partial mutation.
- Renamed the destructive two-measure operation in the Measures tool from the ambiguous `Join Measure` label to `Merge Next`; the intact row-moving operation is labeled `Join Row` in both direct selection actions and Measure mode.
- Made Rhythm `Even Row` and `Join Row` equalization responsive rather than storing a one-orientation result. Equalized rows retain equal-width intent and resolve against the current paper body, so they continue to fill the same left/right engraving margins after rotation.
- Standardized the editor's outer horizontal padding and the paper's horizontal inset. Combined with the existing fixed 34-point paper-to-system inset, full Rhythm rows now keep the same page-edge and system-edge margins in portrait and landscape.
- Reduced dense manual-erase hit-testing churn by coalescing sub-4-point move samples into the next segment while always processing the final point. Skipped movement is accumulated, so this reduces repeated full-stroke scans without creating erase-path gaps or weakening erase persistence. It does not address the newly observed density-dependent writing drag.
- Removed passive Free-Write/Header snapshot work from the active Pencil-change loop. Passive persistence is now a cancellable idle debounce: no whole-drawing stability snapshot is built while strokes are arriving, dense pages receive up to a 1.65-second idle window, and the drawing is snapshotted/serialized only once when the page becomes idle. Tool/scope exit still flushes immediately, so the optimization does not discard unsaved ink.
- Prevented page/header/chord-ink-only chart write-backs from invalidating and recomputing the entire notation layout. Repeated UIKit layout callbacks with an unchanged canvas size are also ignored. Musical/model changes and real bounds changes still invalidate normally.
- Replaced full-path stability signatures with bounded per-stroke signatures using PencilKit render bounds plus five distributed path samples. This keeps chord/rhythm stability checks sensitive to changed strokes without repeatedly walking every point on a dense page.
- Changed anchored page-ink reprojection so a mark's center follows its measure/chord anchor while the handwriting itself retains its original width and height. Unanchored page notes keep their vertical page position and proportional horizontal location without being inflated or compressed by portrait/landscape width changes.
- Decoupled Rhythm Section row packing from accidental count. The actual clef/key/time-signature gutter is still drawn at full width, but it no longer changes which measures belong to a row; heterogeneous manual measure widths are proportionally fitted only when the visible signature leaves less horizontal body space. This keeps key and transposition changes from adding systems and vertically relocating anchored page ink.
- Audited the shared pagination, paper-margin, page-ink, viewport-restoration, rotation, and Join Row paths with Simple Chord Sheet-specific regressions. Those fixes apply to Simple Sheet because it uses the same page and persistent-ink coordinate model. The repeat-leading five-line staff repair does not apply: Simple Sheet intentionally renders no staff, clef, or key signature. Its compact repeat-edge/terminal-barline geometry remains covered by the existing Simple-specific repeat tests.
- Fixed a separate Simple Sheet key/transposition reflow path. Automatic dense-measure packing previously used the chord spelling currently on screen, so enharmonic or transposed text such as slash chords could change measure widths and move every later anchor. Packing now reserves the widest spelling reachable across all twelve transpositions and both accidental preferences, while visible chord frames and drag bounds still use the current spelling. This keeps row/measure geometry stable without reducing a chord's legal movement range.
- Added viewport restoration around real canvas-size changes. If the header is visible it preserves the same document-top offset; farther down the chart it preserves the same measure/system at the top of the viewport. This addresses the stored-but-apparently-disappearing header and the large scroll jump seen in the supplied orientation screenshots without resetting the user to page one.
- Stopped chord-preview diagnostics from truncating on every canvas recreation. New chart sessions append a reset marker and retain prior chart events until the trace exceeds 8 MB, so a reproduction remains inspectable after switching charts.
- Moved chord-preview diagnostic JSON encoding and file appends onto a dedicated serial utility queue. Diagnostic append duration is now emitted separately as `chord.draft_diagnostics.append`, keeping trace collection available without doing large JSON/file work on the UI thread.
- Added generation-based cancellation to chord recognition. New Pencil contact invalidates queued or running superseded work, batches stop between targets, and canceled results cannot call back into the host. This removes obsolete recognition pressure without changing recognition candidates, confidence, grammar, preview replacement, or trust policy.
- Added `chord.recognition.prepare` timing around the main-thread preparation that precedes recognition, and corrected the draft-preview schedule timestamp so the trace includes the real requested idle delay. The next physical pass can therefore separate preparation, queue/wait, execution, diagnostics, and persistence instead of inferring latency from batch completion alone.
- The resulting device trace isolated the dominant chord-load cost. Across 27 preparations, the old main-thread preparation path had a 61.25 ms median, 82.08 ms p90, and 145.60 ms maximum, increasing by about 1.315 ms per accumulated stroke with correlation `r = 0.989`. The actual background recognizer had a 2.437 ms median, 8.061 ms p90, and 17.639 ms maximum. The visible lag was therefore preparation and callback churn, not the recognizer's core inference time.
- Moved chord preparation off the main actor into a dedicated generation-cancelable session. Drawing reconstruction, visible-stroke filtering, barline recognition, target selection, recognition-request assembly, and diagnostic payload preparation now run off the Pencil/UI thread. New contact cancels both queued and running preparation, and stale generations cannot publish previews or persistence results.
- Added a bounded 192-entry recognition-result cache keyed by drawing data and recognition options, reused the prepared `InkStroke` set through targeting and recognition, and removed the second normalization scan. This avoids repeating identical work while preserving the existing candidate, confidence, grammar, correction-memory, and trust behavior.
- Moved passive page/header, chord, and rhythm drawing serialization onto cancelable background sessions. The delegate now captures PencilKit's copy-on-write drawing once, extracts the stroke array/count/last stroke once, and uses an incrementing drawing revision for stability instead of constructing whole-drawing comparison snapshots. Tool/scope exit and app resignation still force a final authoritative save.
- Kept live ink writes out of layout. Page/header/chord-ink persistence no longer performs a full chart equality walk, canvas resynchronization, layout invalidation, or notation redraw. Chord-preview-only publication also skips full-page redraw, rhythm layout comparison ignores per-measure live ink, unchanged scroll-lock and barline values are not reassigned, and repeated nil rhythm-preview callbacks are suppressed.
- A fresh physical pass on the then-installed build exposed one remaining parent-echo redraw path that the internal write-back suppression did not cover. From 4:45:14 to 4:46:52 PM, `Nadie Como Tú` recorded 19 chord captures/preparations and 20 complete canvas redraws. Those redraws had a `117.92 ms` median, `120.83 ms` p95, and `121.54 ms` maximum. Chord capture itself stayed below `0.32 ms`, background preparation had a `10.55 ms` median and `15.86 ms` maximum, background serialization had a `2.99 ms` median and `4.11 ms` maximum, and main-thread write-back had a `0.61 ms` median and `0.70 ms` maximum. The full renderer repaint, not Pencil capture, persistence serialization, or the recognizer, was the dominant repeated stall.
- The same pass then grew passive page ink to 176 strokes / 3,276 points. Its idle serialization took `11.12 ms` off-main and its changed-chart write-back took `0.61 ms`, followed by one `125.63 ms` full canvas redraw. No `ink.input.slow_callback` event was emitted. This confirms that both Chord and Free-Write were paying the same saved-ink backing redraw after the SwiftUI parent echoed a persisted chart update.
- Added a chart-update display policy at the UIKit canvas boundary. When the only changed persistent-ink payload belongs to the active live `PKCanvasView`, the host still synchronizes the live canvas but does not invalidate the backing renderer; real notation/layout changes and changes to any non-active ink scope still redraw. The skip count is emitted as `ink_persistence_backing_redraw_skips` so the next device trace can prove that the intended path executed.
- Added a bounded, auto-purging raster cache for identical saved PencilKit drawings. Its key includes the drawing bytes, source and target coordinate spaces, bounds, and scale, so reuse cannot cross layout or coordinate-space changes. This avoids decoding and rasterizing unchanged saved page ink again when a legitimate full redraw is required, without changing persistence bytes or ink alignment.
- Added programmatic-canvas generation invalidation after model load, coordinate reprojection, chord/rhythm clear, normalization, and selection deletion. That prevents an older background serialization result from overwriting a newer drawing after rotation, settings changes, or tool-driven canvas replacement.
- Reduced diagnostic overhead without removing traceability. Breadcrumb metadata is lazily constructed only when its debug flag is enabled, large draft-diagnostic event construction and JSON/file work run on utility queues, duplicate raw stroke payloads were removed from intermediate targeting events, and full rendered-ink telemetry is sampled and rendered off the main actor. The retained payload event still contains the replay data needed for chord-specific diagnosis.
- The same pre-change device capture showed the healthy Free-Write shape to preserve: a 66-stroke burst over 27 seconds produced zero intermediate persistence writes or layout invalidations, followed by one 5.95 ms idle save at 88 total strokes / 1,602 points. The new path retains that idle/exit persistence contract while removing additional delegate, telemetry, and canvas-update work from every stroke callback.
- Added a drawing-revision and ink-scope serialization cache. Once background persistence has encoded an unchanged drawing, later tool/scope synchronization reuses those exact bytes instead of serializing the same dense PencilKit drawing again on the main thread; every real or programmatic drawing change invalidates the cache.
- Replaced dense manual-eraser full-drawing geometry scans with a 72-point spatial index whose bounds are expanded by the unchanged 18-point erase radius. A 400-stroke regression proves that the indexed result is exactly equal to the original geometric policy while evaluating fewer than ten nearby candidates for the tested segment. Dense drawings also increase the coalesced erase sample distance gradually from 4 to at most 12 points; skipped movement remains part of the next tested segment, so there is no path gap.
- Added cancellation checkpoints inside chord preparation and batch targeting, including between each clustering strategy and while assembling/serializing targets. A superseded preview now stops consuming CPU after new Pencil contact instead of merely suppressing its eventual callback; recognition routes and candidate policy are unchanged.
- Reused the already-resolved preview input for recognition-cache hits only when both the exact anchor and drawing bytes match the previous draft. Unchanged cached targets therefore skip repeated rendering-policy, compendium, and correction-memory digest work, while changed ink or placement still takes the complete resolution path.

Verification completed on iPad Air 11-inch (M4), iOS 26.4.1 Simulator:

- Final responsiveness-focused result `/tmp/iChartInkResponsivenessFocused-20260908-5.xcresult`: 237 selected tests, 235 passed, 0 failed, and 2 intentionally skipped replay-fixture gates. Coverage includes cancelable/background chord preparation, recognition caching, asynchronous diagnostics, revision-based serialization, trusted persistence updates, layout/redraw suppression, and the existing chord-preview behavior.
- Final full-suite result `/tmp/iChartInkResponsivenessFull-20260908-1.xcresult`: 1,185 selected tests, 1,141 passed, 0 failed, and 44 intentionally skipped environment, replay-fixture, saved-state, or live-integration gates.
- Final focused result after the serialization cache, indexed/adaptive erase path, cached preview-resolution reuse, and internal targeting cancellation, `/tmp/iChartInkResponsivenessTargetCancel-20260908-1.xcresult`: 243 selected tests, 241 passed, 0 failed, and 2 intentionally skipped replay-fixture gates.
- Final full `iChartTests` result for the exact source installed on the iPad, `/tmp/iChartInkResponsivenessFull-20260908-2.xcresult`: 1,191 selected tests, 1,147 passed, 0 failed, and 44 intentionally skipped behind explicit environment, fixture, saved-state, or live-integration gates.
- Parent-echo redraw policy and saved-ink raster-cache focused result `/tmp/iChartInkRedrawFocused-20260908-1.xcresult`: 3 selected tests, 3 passed, 0 failed, 0 skipped. The policy suite `/tmp/iChartInkRedrawPolicySuite-20260908-1.xcresult` selected 180 tests, passed 178, failed 0, and intentionally skipped 2 environment-backed fixture gates.
- Preview-stability result after replaying the captured same-chord interior-stroke drop, `/tmp/iChartPreviewStabilityFocused-20260908-1.xcresult`: 4 selected tests, 4 passed, 0 failed, 0 skipped. The previous readable preview remains visible while the expanded input stays explicitly unresolved, so stale text cannot silently commit.
- Final complete suite for the exact source installed after the 4:47 PM baseline capture, `/tmp/iChartInkResponsivenessFull-20260908-170330.xcresult`: 1,193 selected tests, 1,149 passed, 0 failed, and 44 intentionally skipped behind explicit environment, fixture, saved-state, or live-integration gates.
- Chord-ink latency focused result `/tmp/iChartChordInkLatencyFocused-20260908-1.xcresult`: 9 selected tests, 9 passed, 0 failed, 0 skipped. Coverage includes newer-work supersession, explicit cancellation, mid-batch cancellation, asynchronous diagnostic retention, and dense manual-erase sampling.
- Final full suite after the latency changes, `/tmp/iChartChordInkLatencyFull-20260908-1.xcresult`: 1,176 selected tests, 1,132 passed, 0 failed, and 44 intentionally skipped behind opt-in fixture, saved-state, or live-integration gates.
- Outer cue-text panel-height regression plus source wiring in `/tmp/ichart-text-height-focused-20260908.xcresult`: 4 selected tests, 4 passed, 0 failed, 0 skipped. The geometry contract explicitly totals the 36-point header, 72-point input, 10-point spacing, and two 14-point padding edges into a 146-point card.
- Final full suite after the physical-iPad screenshot correction, `/tmp/ichart-full-text-height-20260908.xcresult`: 1,173 selected tests, 1,129 passed, 0 failed, and 44 intentionally skipped behind opt-in fixture, saved-state, or live-integration gates.
- Compact cue-text geometry, shared edit-overlay behavior, roadmap rendering, actual bundled-font outlines, and marker-layout coverage in `/tmp/ichart-text-roadmap-focused-20260908.xcresult`: 36 selected tests, 36 passed, 0 failed, 0 skipped.
- Cue-text source-wiring guard in `/tmp/ichart-text-roadmap-config-20260908.xcresult`: 1 selected test, 1 passed, 0 failed, 0 skipped.
- Final actual-outline size rerun in `/tmp/ichart-text-roadmap-font-bounds-20260908.xcresult`: 2 selected tests, 2 passed, 0 failed, 0 skipped. The coda and segno paths from Finale Broadway and Petaluma remain within 4 percent of one another and occupy a bounded portion of the unchanged marker frame at the tested scales.
- The first full-raster standalone-Coda regression failed against that implementation in `/tmp/iChartDerived-coda-regression-20260908/Logs/Test/Test-iChart-2026.09.08_20-33-52--0700.xcresult`: 1 selected test, 1 failed, with all four Simple/Rhythm and minimum/maximum comparisons exposing the actual mismatch. At maximum size the visible Coda measured approximately `12` versus `39` points high in Simple Sheet and `15.3` versus `27` points in Rhythm Section for Finale Broadway versus Petaluma.
- After switching standalone Coda/Segno to centered vector-outline rendering, all 9 `LeadSheetNotationRendererTests` passed, including full-raster minimum/maximum comparisons for both fonts and both chart styles. The broader notation/layout/PDF gate `/tmp/ichart-coda-outline-focused-20260908.xcresult` selected and passed 156 tests with no failures or skips.
- Exact complete suite after the standalone roadmap correction, `/tmp/ichart-coda-outline-full-20260908.xcresult`: 1,212 selected, 1,168 passed, 44 explicit environment/fixture skips, and 0 failures.
- Final full `iChartTests` result after the cue-text and roadmap-symbol fixes, `/tmp/ichart-full-text-roadmap-20260908.xcresult`: 1,172 selected tests, 1,128 passed, 0 failed, and 44 intentionally skipped behind opt-in fixture, saved-state, or live-integration gates.
- Focused result bundle `/tmp/ichart-rhythm-focused-5.xcresult`: 14 selected tests, 14 passed, 0 failed, 0 skipped.
- Telemetry-shaped coordinate result bundle `/tmp/ichart-nadie-coordinate-suite-1.xcresult`: 9 selected tests, 9 passed, 0 failed, 0 skipped.
- Repeat-setup staff plus telemetry-shaped ink result bundle `/tmp/ichart-repeat-setup-staff-2.xcresult`: 2 selected tests, 2 passed, 0 failed, 0 skipped.
- Final full `iChartTests` result bundle `/tmp/ichart-nadie-full-2.xcresult`: 1,138 tests selected, 1,097 passed, 0 failed, 41 intentionally skipped behind opt-in fixture/live-integration gates.
- Current layout/ink/transaction result bundle `/tmp/ichart-cook-focused-20260907-6.xcresult`: 454 selected tests, 454 passed, 0 failed, 0 skipped. This includes exact-one-measure Join Row behavior, atomic refusal paths, responsive even-row margins, attached and unattached ink shape preservation, dense-ink debounce/layout policies, and header/measure viewport anchors across orientation.
- Current full result bundle `/tmp/ichart-cook-full-20260907-1.xcresult`: 1,149 tests selected, 1,108 passed, 0 failed, and 41 intentionally skipped behind opt-in fixture/live-integration gates.
- Compact-measure drag, lone-chord placement, and trace-retention result bundle `/tmp/ichart-focused-20260907-4.xcresult`: 160 selected tests, 160 passed, 0 failed, 0 skipped.
- Saved pending-ink replay result bundle `/tmp/ichart-bg-replay-20260907-3.xcresult`: 1 selected test, 1 passed, 0 failed, 0 skipped. The final three strokes replay as `B` (confirmation) plus `G` (trusted); the persisted first stroke alone remains a no-read rather than reproducing the transient `C` preview.
- Final suite after the compact-measure targeting, moved-lone-chord placement, retained diagnostic trace, and gated pending-ink replay additions: `/tmp/ichart-full-20260907-2.xcresult` selected 1,156 tests; 1,114 passed, 0 failed, and 42 intentionally skipped behind opt-in fixture/live-integration gates.
- Nadie-shaped key-layout regression `/tmp/ichart-key-layout-fixed-20260908.xcresult`: 1 selected test, 1 passed, 0 failed, 0 skipped. The same 22-measure manual-width chart stays in six identical rows from G major through C-flat major and remains inside the page margin.
- Exact before/after device-state replay `/tmp/ichart-key-layout-device-replay-final-20260908.xcresult`: 1 selected test, 1 passed, 0 failed, 0 skipped. It verifies unchanged ink bytes, identical `4, 4, 5, 2, 5, 2` row membership, 174 preserved strokes, `0.00` points maximum vertical movement, and `61.00` points maximum horizontal fitting movement.
- Full `LeadSheetPageLayoutTests` result `/tmp/ichart-layout-suite-final-key-fix-20260908.xcresult`: 129 selected tests, 129 passed, 0 failed, 0 skipped.
- Ink, key/transposition, anchor, rotation, viewport, and dense-write policy result `/tmp/ichart-ink-viewport-key-fix-20260908.xcresult`: 14 selected tests, 14 passed, 0 failed, 0 skipped.
- The Simple dense-key geometry regression was first run against the prior implementation and failed 8 geometry assertions in `/tmp/ichart-simple-key-geometry-baseline-20260908.xcresult`, confirming a real display-spelling-dependent reflow before the fix.
- Final combined layout/interaction result `/tmp/ichart-simple-parity-suites-final-20260908.xcresult`: 302 selected tests, 300 passed, 0 failed, and 2 intentionally skipped behind opt-in saved-state gates. It includes Simple pagination, portrait/landscape margins, viewport/header anchors, fixed page-ink coordinates, Join Row, compact repeat geometry, dense chord packing, and the full chord movement matrix.
- Exact current device-state Simple replay `/tmp/ichart-simple-device-replay-parity-20260908.xcresult`: 1 selected test, 1 passed, 0 failed, 0 skipped. `Higher Love` loaded 10 persisted strokes from `/tmp/ichart-keychange-live-20260908.f6lRe4/library-state.json`; both displayed-key change and one-semitone chord transposition moved 0 strokes, had `0.00` points maximum displacement, and changed 0 measure anchors.
- Final full-suite result `/tmp/ichart-full-simple-parity-final-20260908.xcresult`: 1,168 selected tests, 1,124 passed, 0 failed, and 44 intentionally skipped behind opt-in fixture, saved-state, or live-integration gates.
- A maximum-width signature-lane experiment made the exact replay report zero horizontal movement, but it failed three existing compact-engraving assertions by restoring an oversized setup gap. That variant was rejected and reverted; `/tmp/ichart-layout-suite-zero-movement-20260908.xcresult` is a discarded red result, not release evidence.
- Three launch attempts produced `Application failed preflight checks` / `Busy` and ran zero tests; they were discarded rather than counted. Intermediate red runs also exposed test-assumption errors around generated layout IDs, collision-resolved chord frames, and the exact midpoint of a joined lane; those assertions were corrected before the final focused and full gates. A manually booted simulator produced the valid gates above.

Physical iPad Air (4th generation), iPadOS 26.6.1 verification:

- A 9:15 AM Xcode device capture of the installed App Store 1.2.1 build 51 reproduced the defect on the live `Nadie Como Tú` chart: each repeat-leading system began its five staff lines at the repeat boundary, leaving the bass clef and five-flat key signature over blank paper.
- The patched Debug build was then built, installed over the same bundle identifier, and launched without losing the existing chart library. A 9:20 AM capture of the same chart showed the five staff lines beginning at the system edge and continuing behind the clef and key signature on every repeat-leading system.
- After the current dense-ink, viewport-anchor, margin, rotation-reprojection, and Join Row changes, the Debug device product at `/tmp/ichart-cook-device-dd-20260907/Build/Products/Debug-iphoneos/iChart.app` was built, installed over `com.ichart.app`, and launched successfully on the same connected iPad. Its executable UUID is `B3FA7777-4645-3EB5-9BBC-201B20B230FA`.
- A read-only post-install application-container capture at `/tmp/ichart-device-state-20260907.GqleDX` still contains `Nadie Como Tú` in `library-state.json`, plus the device's chord-preview and performance traces. This proves deployment and chart-library continuity only; it is not physical Pencil, rotation, erase, or UI acceptance evidence for the newer changes.
- After the live G-major to C-flat regression exposed key-dependent Rhythm row packing, the replacement Debug product at `/tmp/ichart-keylayout-device-dd-20260908/Build/Products/Debug-iphoneos/iChart.app` was built, signature-verified, installed, and launched. Its executable UUID is `4A4AE322-6D42-3A44-BFA5-A2313F410826`. The pre/post `library-state.json` SHA-256 values match exactly, but the key-toggle visual result still requires direct observation on this installed build.
- After the Simple Sheet parity audit, the final signed Debug product at `/tmp/ichart-simple-parity-device-dd-20260908-0945/Build/Products/Debug-iphoneos/iChart.app` was signature-verified, installed, and launched. Its arm64 executable UUID is `05D0E310-4CAA-3613-A17C-D52297FB0CA1`; the unchanged target metadata remains version 1.2.1 build 51. The immediate pre-install backup `/tmp/ichart-simple-parity-preinstall-20260908.C3gOlI/library-state.json` and post-install capture `/tmp/ichart-simple-parity-postinstall-20260908.DVMlP4/library-state.json` are byte-for-byte identical (`402,376` bytes; SHA-256 `ed5cf7482de83895485f8216e8d38c732db04082745e1f30bd52f23f81063465`). This proves install and persisted-library continuity, not physical Simple Sheet visual/Pencil acceptance.
- After the shared cue-text and roadmap-symbol fixes, the signed Debug product at `/tmp/ichart-text-roadmap-device-dd-20260908-1002/Build/Products/Debug-iphoneos/iChart.app` passed deep/strict signature verification, installed over `com.ichart.app`, and launched on the connected iPad. Its arm64 executable UUID is `E7AD572E-099B-3082-BBBD-ADC4C8813FA9`; target metadata remains version 1.2.1 build 51. The pre-install backup `/tmp/ichart-text-roadmap-preinstall-20260908.kWUtSy/library-state.json` and post-install capture `/tmp/ichart-text-roadmap-postinstall-20260908.nBwN5C/library-state.json` are byte-for-byte identical (`402,393` bytes; SHA-256 `3221d5ba187d5f962742337b7cfd7372edb73ad75e5ee5572f9ff7eb2e183af0`). This proves deployment and persisted-library continuity; it does not prove the two visual behaviors on physical iPad.
- After the 10:07 AM screenshot exposed the remaining vertical expansion, replacement product `/tmp/ichart-text-height-device-dd-20260908-1012/Build/Products/Debug-iphoneos/iChart.app` built successfully, passed deep/strict signature verification, installed over `com.ichart.app`, and launched. Its arm64 executable UUID is `B3E989EB-83C0-3B75-B696-CD875B752500`, distinct from the screenshot's superseded build. The immediate pre/post library files at `/tmp/ichart-text-height-preinstall-20260908.ISztKH/library-state.json` and `/tmp/ichart-text-height-postinstall-20260908.4B0ZTb/library-state.json` are byte-for-byte identical (`402,393` bytes; SHA-256 `3221d5ba187d5f962742337b7cfd7372edb73ad75e5ee5572f9ff7eb2e183af0`). Physical reopening of Add Text remains the visual acceptance gate.
- After the live chord-ink latency trace, the signed Debug product at `/tmp/ichart-chord-latency-device-dd-20260908.CApjlD/Build/Products/Debug-iphoneos/iChart.app` passed deep/strict signature verification, installed over `com.ichart.app`, and launched. Its arm64 executable UUID is `DFEBF645-528A-31F8-A52F-78DDC9110ABB`; target metadata remains version 1.2.1 build 51. The immediate pre-install backup `/tmp/ichart-chord-latency-preinstall-20260908.CLpzao/library-state.json` and post-install capture `/tmp/ichart-chord-latency-postinstall-20260908.tcoQJz/library-state.json` are byte-for-byte identical (`392,363` bytes; SHA-256 `08156c1c92a33cce00a1262a50c1cb40f477eee245f8a033a1dd94dbf2275dd6`). This proves deployment and chart-library continuity only; fresh physical Pencil writing remains the latency acceptance gate.
- The first responsiveness product at `/tmp/iChartInkResponsivenessDevice-20260908/Build/Products/Debug-iphoneos/iChart.app` built for the connected iPad, passed deep/strict signature verification, installed over `com.ichart.app`, and launched successfully. Its arm64 executable UUID is `24F0B0AC-7CE8-3326-BB54-93BA02ABECC2`; unchanged target metadata remains version 1.2.1 build 51. The pre-install backup `/tmp/ichart-ink-pass-device-before-20260908.4ogabk/library-state.json` and immediate post-install capture `/tmp/ichart-ink-pass-device-after-20260908.fe7umh/library-state.json` are byte-for-byte identical (`443,464` bytes; SHA-256 `ce699fb5d1ac47cdfb121f8cc68e89492e29a938a873d2ebc7152137e4fc653a`). All three charts remain present, including `Nadie Como Tú` and `Higher Love`; this product is now superseded by the build below.
- The final dense-ink iteration at `/tmp/iChartInkResponsivenessDeviceFinal-20260908/Build/Products/Debug-iphoneos/iChart.app` passed deep/strict signature verification, installed over `com.ichart.app`, and launched on the connected iPad. Its arm64 executable UUID is `74A7AFCF-1641-352C-9525-BC443A1C6FC7`; metadata remains version 1.2.1 build 51. The immediate pre-install backup `/tmp/ichart-ink-final-preinstall-20260908.26PmLV/library-state.json` and post-install capture `/tmp/ichart-ink-final-postinstall-20260908.YEpyVJ/library-state.json` are byte-for-byte identical (`435,543` bytes; SHA-256 `cd4d49034cfe076930067cab4e5ac73f25d53e550ff5e5df554c64448e80f734`). `Untitled Chart`, `Nadie Como Tú`, and `Higher Love` are all still present.
- The 4:45–4:47 PM baseline capture is `/tmp/ichart-ink-pass-postfix-20260908.8LOkEL`. Production received 37 matching events through the 4:47:31 PM page save; one 4:47:35 PM mode-change event remained in the local queue at capture time. The pass recorded 19 preview updates (12 trusted, 4 confirm, 2 mixed, 1 no-read, and 3 close-race observations), six chord-ink saves, and one page-ink save. `B` and `G` appeared as separate previews in the first update. Two final committed additions were `C#△7` and `D#ø7`; the chart grew from 26 to 28 committed chords and from 49,612 to 92,816 base64 page-ink characters while its saved row membership, 22 measure identities, and non-chord coordinate anchors stayed unchanged.
- Production telemetry still cannot retain the new recognition issue buckets: all 119 `chord.preview_updated` rows from this installation on September 8 have zero `issue_count`, `root_issue_count`, or `quality_issue_count` keys. The active `app-telemetry-ingest` Edge Function remains version 8 and its deployed allowlist strips those properties. Local source already contains the allowlist update; no production Edge Function deployment was performed in this build pass.
- The replacement signed Debug product at `/tmp/iChartDerived-device-ink-responsive-20260908-170452/Build/Products/Debug-iphoneos/iChart.app` passed deep/strict signature verification, installed over `com.ichart.app`, and launched at 5:06 PM. Its arm64 executable UUID is `A58EE342-6117-3B52-8F9B-CB8EA49923AA`, executable SHA-256 is `87504cdcdbf2e78b46bd8bb0de5feb60fa291aa8c662b14e9955525765584ec2`, and unchanged target metadata remains version 1.2.1 build 51. The immediate pre-install capture and `/tmp/ichart-post-install-preservation-20260908.GFTktD/app-support/library-state.json` are byte-for-byte identical (`505,771` bytes; SHA-256 `86e26ba0acef2b1814624c3deecaf61380eef34e8e5c4ca7b74d8ca0e49bf6a5`). This is now the only valid build for the redraw-suppression acceptance pass.
- Remaining acceptance work includes a deliberate physical-iPad Pencil pass for normal and density-dependent chord and Free-Write latency on executable UUID `A58EE342-6117-3B52-8F9B-CB8EA49923AA`, plus tool switching, ink position/scale through measure removal and save/reopen, erase/reopen persistence, chord/measure drag feel, header visibility, stable margins, portrait/landscape round trips, Join Row, and export/editor visual agreement. The performance trace must show a nonzero `ink_persistence_backing_redraw_skips` count and eliminate the repeated approximately 118 ms backing redraw after active-scope saves before this latency fix is accepted. Current erase feel has passed once on device, but the persistence sequence remains open. For this build specifically, verify in both Simple and Rhythm that Add Text opens a compact panel and long text scrolls, then compare maximum-size Coda/Segno and inline roadmap signs in Finale Broadway versus Petaluma in both the editor and exported PDF.

## Why This Matters

The editor must preserve visible musical context and handwritten ink identity across tool changes. A repeat sign must not suppress the first system's staff geometry, and switching tools must not reload, transform, or redraw saved ink in a different coordinate space.

Dense rewrite ink must also stay responsive. Persistence should protect the user's writing, but it must not put serialization, chart write-back, layout invalidation, recognition, or telemetry work into the live Pencil movement loop.

Erase persistence is part of the same trust boundary. When the user erases free-write strokes, the erased state must win over any stale saved drawing, pending persistence map, background sync replay, or restored canvas snapshot. Slow erasing is a performance issue; erased ink coming back is a data-integrity issue.

Accidental attachment needs to match how musicians write. A flat, sharp, natural, or suffix qualifier can be physically separated from the root while still belonging to the same chord. The fix cannot simply widen all grouping, because adjacent real roots such as `C D` must not collapse into `Cb` or another accidentalized note.

Rendered chord editing must match the visual placement model. If the user sees a chord in a beat slot, the hit/edit box and resize behavior should use the same geometry authority rather than a wider measure frame or stale free-position model.

Drag preview state and committed chord placement must also share the same authority. A green placement preview on beat four is not useful if the release transaction writes or normalizes the chord back to beat three.

The Measures tool should also support the normal structural edits users expect: stable resizing, row equalization, joining adjacent measures, and predictable row/system behavior. Rhythm Section should align with Simple Chord Sheet where both styles share measure-edit concepts, but it is not a mechanical copy because Rhythm Section measures can carry rhythm maps, repeats, cue text, roadmap anchors, and below-measure freehand articulations.

Page geometry must remain real page geometry. A large starting measure count must not stretch the first page's paper height; the layout engine should respect page bounds and decide between tighter measure packing, additional systems, or additional pages according to the chart style's engraving rules.

## Initial Classification

Likely failure classes to verify before patching:

- Rhythm Section renderer/layout regression: repeat-edge rendering or first-system leading notation may be changing the staff-line start/end bounds until the lines have zero or invalid width.
- Active ink scope handoff regression: switching tools may be persisting, reloading, or normalizing the same `PKDrawing` through a different frame.
- Coordinate-space mismatch: saved page, chord-lane, or rhythm-measure ink may be replayed using a stale page/system/measure frame after layout changes.
- Model anchoring gap: some ink may currently be tied to page/global coordinates when the product expectation is system- or measure-relative persistence.
- Dense-ink performance regression: persistent ink state may be causing too-frequent drawing serialization, chart mutation, layout invalidation, or telemetry enqueue work while the user is actively writing.
- Dense-ink write-back/layout churn: the September 7 device trace shows small drawing batches followed by repeated chart write-backs and layout invalidations as the page approached 100 strokes; this work may be competing with the live Pencil path.
- Erase-sync persistence regression: erased free-write strokes may be losing to an older persisted `PKDrawing`, pending dirty-state write, background sync merge, or restored canvas snapshot.
- Erase performance regression: eraser movement on dense pages may be serializing full drawings, rewriting chart state, recomputing layout, or replaying persistence too often.
- Chord root recognition regression: `G` and `B` failures need to be classified through current trace/telemetry as glyph classification, root construction, batch grouping, confidence/trust, or preview replacement before changing recognition code.
- Accidental attachment tolerance gap: flats, sharps, naturals, and chord qualifiers written slightly apart from the base letter may be classified as a separate root or separate chord instead of attaching to the intended base note.
- Rendered chord edit geometry regression: Rhythm Sheet chord hit/edit boxes may still be using a broad measure, chord-lane, or legacy fraction frame while visual placement uses beat-slot geometry.
- Rendered chord resize persistence regression: manual chord-size adjustments may be written, then immediately overwritten by layout recomputation, slot normalization, selection refresh, or chart reload.
- Simple Sheet chord drag commit regression: green placement preview can target the fourth beat, while the release transaction or placement normalization restores the chord to its previous third-beat/order slot.
- Measures-tool parity gap: Rhythm Section needs the shared Simple Sheet measure-edit affordances where applicable, including stable resize semantics, even-row/equalize behavior, and Join Measure.
- Measure resize transaction regression: Rhythm Section resize may be committing a selected measure change in a way that triggers row/system reflow, changes later beat placement, or expands neighboring measures unexpectedly.
- Beat-placement drift after resize: rendered chord/rhythm beat positions may be recomputed from changed measure frames without preserving the user's intended beat/slot authority.
- Page-bounds regression: Rhythm Sheet initial layout may be allowing system count/content height to define paper height instead of clipping, tightening, wrapping, or paginating within fixed page bounds.
- Starting-measure pagination gap: large initial measure counts such as 32 need deterministic page/system distribution at chart creation, without requiring a later Add Page command to create valid paper geometry.
- Header visibility/scroll-restoration regression: the persisted typed header fields remain present while the page header disappears from the visible editor, pointing to page rendering, clipping, or scroll-anchor restoration rather than data deletion.
- Orientation-dependent coordinate/reflow regression: logical page height is now fixed, but Rhythm/Simple paper width still resolves from the current editor viewport. Portrait/landscape rotation can therefore change paper width, system packing, persisted manual-width presentation, and the frames used to project anchored ink.
- Margin consistency regression: responsive paper width plus persisted heterogeneous measure widths may leave systems with inconsistent usable width and large unused right-side space.
- Measures-tool semantic gap: Join Row is required in addition to Join Measure. It moves an intact selected measure to the preceding rendered row and equalizes that destination row without merging musical contents.

Do not assume system/measure anchoring is the immediate fix. First prove whether the drift is caused by layout recomputation, scope identity mismatch, persistence timing, or rendering with stale geometry.

Do not assume server telemetry contains raw chord text or drawing payloads. Use aggregate telemetry/failure buckets where available, and use pulled device traces for chord-specific diagnosis.

## Patch Plan

1. Capture the current iPad app container immediately after reproducing the issue.
   - Pull `Library/Application Support/iChart`.
   - Preserve `library-state.json`, performance traces, telemetry queue, and any ink/debug JSONL files.
   - Record installed app version/build and current git commit separately.
   - If the installed app is an App Store/TestFlight build, confirm whether `devicectl` can access the app data container before assuming local JSONL traces are pullable.
2. Reproduce in a clean local fixture.
   - Create or identify a Rhythm Sheet with first-system four-bar content and a repeat sign.
   - Verify whether leading staff lines disappear while clef/key remain visible.
   - Check Simple Chord Sheet separately if the symptom appears there too.
3. Trace layout and render authority.
   - Inspect `LeadSheetPageLayoutEngine` output for first-system staff frames before and after repeat insertion.
   - Inspect notation rendering bounds for staff lines, leading barline/repeat marker, clef, key signature, and measure body.
   - Confirm whether the staff-line draw path is skipped or receives collapsed coordinates.
4. Trace page bounds and starting-measure pagination.
   - Create a Rhythm Sheet with 32 starting measures and inspect page frames, system frames, rendered paper bounds, and export page count.
   - Verify whether page height is derived from fixed paper geometry or from total system content height.
   - Check whether automatic system packing should tighten row measure widths before increasing vertical page content.
   - Define whether overflow should paginate automatically at creation time or present a bounded page with clear continuation behavior.
   - Confirm Add Page remains a manual true-page insertion action, not a workaround for invalid first-page height.
   - Define a canonical document/page width and ink coordinate space that do not change merely because the device rotates.
   - Preserve the visible page/system scroll anchor through portrait-to-landscape and landscape-to-portrait transitions.
   - Verify the typed header remains rendered at the top of page one after rotation, tool changes, pagination changes, and save/reopen.
   - Define consistent page-side and system engraving margins independent of persisted per-measure width variation.
5. Trace rendered chord edit geometry and resize persistence.
   - Compare visual chord text bounds, placement-slot bounds, hit/edit overlay bounds, and resize handle bounds in Rhythm Sheet.
   - Verify whether edit boxes are derived from placement guide geometry, measure body geometry, or a stale `manualLaneFraction`/free-position helper.
   - In Simple Sheet, create a measure with three chords and drag the third chord to the fourth beat.
   - Compare the drag preview target, green placement-slot state, release target, written `ChordEvent` placement/order/fraction, layout recomputation, and final rendered beat slot.
   - Verify whether slot normalization, chord ordering, `manualLaneFraction`, beat-index rounding, or adjacent-chord collision rules are preventing the third chord from committing to beat four.
   - Track one resize gesture from drag start through model write-back, layout invalidation, and redraw.
   - Confirm whether size changes are persisted in `ChordEvent` state or lost when slot placement recomputes rendered geometry.
   - Reproduce across multiple chords to determine whether this is global edit-overlay behavior or a per-measure/per-slot edge case.
6. Trace ink persistence across tool switches.
   - Record active ink scope identity, input frame, saved drawing bounds, and restored drawing bounds before and after switching tools.
   - Verify that tool changes persist outgoing dirty ink exactly once and reload the same scope in the same coordinate space.
   - Confirm no stale pending persisted-ink map or last-persisted snapshot is overriding newer live ink.
   - Repeat the same trace while erasing free-write ink, including partial erases and erase-to-empty.
   - Confirm erased strokes are removed from the live drawing, persisted drawing, restored drawing, and any sync/dirty-state cache.
   - Verify no older drawing snapshot can overwrite a newer erase operation after a tool switch, chart save, background persistence pass, or app relaunch.
7. Trace dense-ink performance.
   - Measure baseline writing latency on a normal page, a dense rewrite-ink page, and a page undergoing frequent sync/persistence updates.
   - Reproduce with a page that has substantial rewrite ink before writing chords.
   - Reproduce with the same page while erasing free-write ink.
   - Compare live Pencil latency against `editor.canvas.draw`, layout, persistence, recognition, and telemetry timing.
   - Check whether persistence is serializing full drawings too often or invalidating the full chart during active stroke input.
   - Separate canvas draw cost, eraser hit-testing cost, layout cost, persistence cost, recognition cost, and telemetry enqueue/upload cost.
   - Verify sync/write-back work is coalesced off the live Pencil movement path wherever possible.
8. Investigate root and accidental-spacing issues through evidence.
   - Pull the current iPad trace after a failing `G`/`B` pass.
   - Pull a current iPad trace where a flat, sharp, natural, or qualifier is written slightly farther from the base note and registers as a different note.
   - Check local chord draft preview diagnostics for top glyph candidates, root construction, grouping route, final action, and trust state.
   - Check telemetry failure buckets if the installed build emits them.
   - Distinguish target grouping, accidental glyph classification, accidental-to-root attachment, parser grammar, candidate scoring, and preview replacement.
   - Do not tune `G`/`B` or accidental-spacing heuristics until the failure class is known.
9. Redesign Rhythm Section Measures-tool parity with Simple Sheet.
   - Inventory every Simple Chord Sheet Measures-tool command and identify the shared contract that should also apply to Rhythm Section.
   - Define Rhythm Section-specific rules for resize, Even Row / equalize row, Join Measure, system breaks, measure insertion/deletion, and repeat boundaries.
   - Hold row/system geometry stable during active resize so the release position matches the preview instead of surprising the user.
   - Preserve beat/slot authority for chords and rhythm content when measure widths change.
   - Implement Even Row / equalize-row behavior for the selected Rhythm Section row without changing unrelated rows or upstream systems.
   - Define which adjacent Rhythm Section measure pairs are safely joinable.
   - Preserve chords and rhythm-map timing by remapping beat positions into the joined measure or refuse the join with clear behavior when remapping would be unsafe.
   - Preserve or deliberately resolve barlines, repeat boundaries, endings, section labels, cue text, roadmap anchors, and below-measure freehand attachments.
   - Add Join Measure to the Measures tool only when a valid adjacent target exists.
   - Add Join Row as a distinct command: move the selected measure intact to the immediately preceding rendered row, preserve its ID/content/attachments, and equalize only the destination row.
   - Keep Join Row unavailable when no preceding row exists, and define capacity/overflow behavior without silently moving unrelated measures.
   - Keep all measure operations undoable and deterministic.
10. Add focused regression coverage.
   - A layout test proving first-system Rhythm Sheet staff lines remain drawable after a repeat sign is added to the first four bars.
   - A page-layout test proving a 32-measure Rhythm Sheet keeps fixed page height and either packs/paginates within valid page bounds.
   - A PDF/export test proving large-measure-count Rhythm Sheets export as real pages rather than one elongated first page.
   - A rendered chord edit test proving Rhythm Sheet edit boxes match slot-rendered chord bounds closely enough to edit the intended symbol.
   - A Simple Sheet chord-drag test proving the third chord in a three-chord measure can move to the fourth beat when the green placement preview indicates that target.
   - A resize persistence test proving manual chord-size changes either persist intentionally or are disabled/explained instead of visually snapping back.
   - A tool-switch persistence test proving saved ink does not move when switching between chord, rhythm, freehand, selection, repeat, and measure tools.
   - A telemetry-shaped page-ink regression proving a `724 x 2944` to `724 x 1248` measure-count shrink does not vertically compress unmatched ink from a removed measure into the surviving page.
   - An erase persistence test proving deleted free-write strokes do not reappear after tool switches, saves, reloads, or erase-to-empty paths.
   - A dense-ink performance regression test or instrumentation fixture that bounds persistence/layout churn during active writing and erasing.
   - Root-specific recognizer tests only after a real `G`/`B` failure trace identifies the failing layer.
   - Accidental-spacing recognizer tests only after a real device trace identifies whether the failure is grouping, accidental attachment, or candidate scoring.
   - Boundary tests proving a legitimate spaced flat/accidental attaches to the base note while adjacent independent roots remain separate.
   - Model and layout tests proving Rhythm Section resize does not unexpectedly mutate later measure beat placement or upstream staff/system rows.
   - Model and layout tests proving Rhythm Section Even Row / equalize-row produces stable selected-row spacing.
   - Model and layout tests proving Rhythm Section Join Measure preserves supported content and refuses unsafe content.
   - Model and layout tests proving Join Row moves the selected measure intact to the row above, equalizes only the destination row, and preserves measure IDs, contents, and attached ink.
   - Portrait-to-landscape-to-portrait tests proving page identity, ink coordinates, header visibility, system margins, and the visible page/scroll anchor remain stable.
   - A header regression proving stored typed header fields remain visible at the top of page one after layout invalidation and save/reopen.
   - If drift depends on page/system geometry, add a fixture that changes layout and asserts expected coordinate anchoring.
11. Validate on device before release.
   - Install the patch build on the iPad.
   - Create a 32-measure Rhythm Sheet and verify the first page stays at normal paper height.
   - Verify overflow measures are packed/paginated according to the chosen contract.
   - Recreate the four-bar first-staff repeat case.
   - In Simple Sheet, create a three-chord measure, drag the third chord to the final beat, and confirm release persists the fourth-beat placement.
   - Select and resize multiple rendered Rhythm Sheet chords, including first-beat-slot chords.
   - Resize Rhythm Section measures across first, middle, and row-end positions and verify preview/release match.
   - Use Even Row / equalize row on Rhythm Section and verify only the intended row changes.
   - Join adjacent Rhythm Section measures through the Measures tool and verify the resulting notation, chords, repeats, and ink placement.
   - Select a measure below the first rendered row, invoke Join Row, and verify it moves intact to the row above while only that destination row is evenly spaced.
   - Recreate a dense rewrite-ink page and write chords while monitoring trace/performance output.
   - Erase dense free-write ink, including partial erases and erase-to-empty, and confirm deleted strokes do not return during tool switches or after save/reopen.
   - Recreate the `G`/`B` root-recognition cases from the pulled trace.
   - Recreate the spaced-flat/accidental cases from the pulled trace.
   - Switch through the affected tools repeatedly.
   - Rotate portrait to landscape and back while viewing the first page and a later page; verify header visibility, margins, paper/page identity, scroll anchor, selection overlays, and every ink anchor.
   - Close/reopen the chart and confirm staff lines plus ink positions are stable.
   - Export a PDF and compare editor/PDF placement.

## Guardrails

- Do not change chord recognition, OCR, Scribble, parser, compendium, or chord trust thresholds for this patch.
- Do not introduce broad system/measure anchoring until the current drift mechanism is proven.
- Do not make Rhythm Section measure splitting broader unless committed rhythm maps, cue text, roadmap markers, repeats/endings, and freehand attachments are explicitly handled.
- Do not optimize performance by weakening persistence guarantees or dropping user ink.
- Do not optimize erasing by skipping authoritative delete persistence or allowing stale saved drawings to merge deleted strokes back into the canvas.
- Do not improve flat/accidental spacing by globally widening chord grouping in a way that merges adjacent independent roots or reintroduces `C D` to `Cb`-style failures.
- Do not fix oversized edit boxes by abandoning the placement-slot rendering contract or reintroducing free-position chord layout drift.
- Do not treat green drag preview as acceptance unless the released chord persists and re-renders in the same beat slot.
- Do not implement Rhythm Section Join Measure by silently dropping rhythm maps, chords, repeats, cue text, roadmap anchors, or attached ink.
- Do not treat Join Measure as Join Row. Join Row must preserve the selected measure as an intact measure and must not merge musical contents.
- Do not widen committed Rhythm Section measure splitting as a side effect of adding join behavior.
- Do not claim Simple Sheet parity if Rhythm Section resize still changes upstream systems, later beat placement, or unrelated row widths unexpectedly.
- Do not allow starting-measure count or automatic system wrapping to stretch the physical page height.
- Do not regress the existing true Add Page behavior while fixing automatic pagination.
- Do not use aggregate telemetry as chord-specific proof unless the installed build actually emits the relevant failure buckets.
- Do not treat simulator success as physical Pencil acceptance. The final acceptance surface is a fresh physical iPad pass.

## Acceptance Criteria

The next patch can close this issue only when:

1. Rhythm Sheet first-system staff lines remain visible after adding a repeat sign across the first four bars.
2. Clef, key signature, repeat marks, measure lines, staff lines, chord lane, and rhythm area remain visually coherent in the same system.
3. A 32-measure Rhythm Sheet keeps fixed page height and uses valid measure packing or pagination instead of elongating the first page.
4. Add Page remains a true separate-page action and is not required to repair initial invalid page geometry.
5. Rendered Rhythm Sheet chord edit boxes align with the visually rendered chord and its intended beat slot.
6. In Simple Sheet, the third chord in a three-chord measure can be dragged to the fourth beat and remains there after release, redraw, save, and reopen.
7. Manual chord-size adjustments do not snap back unexpectedly across repeated chords.
8. Rhythm Section measure resizing has stable preview/release behavior and does not unexpectedly mutate upstream systems or later beat placement.
9. Rhythm Section Measures includes Even Row / equalize-row behavior for the selected row.
10. Rhythm Section Measures includes a Join Measure command for valid adjacent measures.
11. Join Measure preserves supported Rhythm Section content or refuses unsafe joins without silent data loss.
12. Handwritten ink does not shift when switching tools.
13. Erased free-write ink does not reappear after tool switches, chart save, close/reopen, app relaunch, or erase-to-empty.
14. Saved ink stays aligned after save/reopen and app relaunch.
15. Ink writing latency is acceptable on normal and dense pages, with sync/persistence work kept out of the live Pencil path where possible.
16. Dense rewrite-ink pages remain responsive while writing and erasing, with performance evidence separating draw, eraser hit-testing, layout, persistence, recognition, and telemetry cost.
17. `G` and `B` root failures are either fixed or classified as confirmation-gated/unsupported without confident wrong renders.
18. Flats, accidentals, and attached chord qualifiers tolerate realistic spacing from the base note without merging adjacent independent root letters.
19. PDF export agrees with the editor for the affected chart.
20. The fix is backed by focused tests plus physical iPad verification.
21. The stored chart header remains visible at the top of page one after tool changes, layout invalidation, save/reopen, and portrait/landscape rotation.
22. Paper-side and system engraving margins remain consistent across systems, pages, viewport sizes, and orientations.
23. A portrait-to-landscape-to-portrait round trip preserves page identity, ink scale/position, selection geometry, header visibility, and the user's visible page/scroll anchor.
24. Join Row moves the selected measure intact to the immediately preceding rendered row, equalizes only the destination row, preserves its contents and attached ink, and does not resize unrelated rows.
25. Writing remains responsive at approximately 100 page-ink strokes and beyond, with device evidence showing bounded serialization, chart write-back, and layout invalidation during active Pencil input.

## Telemetry Snapshot: 2026-09-05 21:32 PT

Source: production Supabase `public.telemetry_events`, filtered to iChart `1.2.1` build `51`, `iPadOS`, last 12 hours. This is aggregate telemetry only. It does not include raw handwriting strokes, raw chord text, chart titles, names, emails, or support content.

Device/container state:

- `xcrun devicectl list devices` saw Ben's iPad as `376D59F8-92F2-5260-B10E-BA0BEAF941AB`, model `iPad13,2`.
- `xcrun devicectl device info apps --include-all-apps --bundle-id com.ichart.app` reported installed `iChart` version `1.2.1`, build `51`, `Developer App = false`.
- A read-only `devicectl device copy from --domain-type appDataContainer --domain-identifier com.ichart.app --source 'Library/Application Support/iChart'` failed with `ContainerLookupErrorDomain error 3`.
- Therefore the current public install did not expose local debug JSONL files or `performance-trace.jsonl` through `devicectl`. Production DB telemetry was the only available source in this pass.

Production upload state:

- Last 12 hours for build `51` had 586 events from 2 installations and 3 sessions.
- The latest received production event was `2026-09-06 02:42:16Z` / `2026-09-05 19:42:16 PT`, about 1 hour 50 minutes before the query. Current just-written activity may still be queued or otherwise not represented in production telemetry yet.
- The most recent installation group (`iPad13,10`) showed 22 events, including two chart-created flows, but 0 chord events, 0 ink events, and 0 cloud events.
- The connected-iPad model group (`iPad13,2`) showed 564 events, including 178 chord events and 263 ink events. Its latest received event was `2026-09-06 01:24:57Z` / `2026-09-05 18:24:57 PT`.

Corroborated from production telemetry:

- A Rhythm Section chart setup completed with `measure_count = 32` at `2026-09-05 16:38:48 PT`.
- Later Rhythm Section editor events showed `measure_count = 33` starting at `2026-09-05 17:34 PT`, consistent with the report that Add Page added an extra measure after the original 32-measure page state.
- The connected-iPad group logged 247 `ink.persisted` events: 145 chord-scope and 102 page-scope.
- The same group logged 16 `ink.coordinate_space_reprojected` events.
- During the 32-measure Rhythm Section pass, page-scope coordinate reprojection repeatedly changed page-height frames, including `1584 -> 1752`, `1752 -> 1584`, and `1752 -> 1752`; chord-scope reprojection later mapped `1752 x 724` into `1188 x 596`.
- During the 33-measure post-Add-Page state, page/chord reprojection included `2944 x 724 -> 2944 x 724`, `2944 x 724 -> 1864 x 596`, and `2944 x 724 -> 1248 x 724`.

What this supports:

- The 32-measure / 33-measure sequence matches the user's page-bounds/Add Page report.
- The coordinate-space reprojection events match the class of "ink shifts when tool/layout state changes." They do not prove the exact visual shift, but they show the app is actively transforming saved ink between changing coordinate frames during the affected workflow.
- The high count of `ink.persisted` events and repeated reprojection make local persistence/canvas sync a plausible contributor to perceived ink heaviness. Production telemetry does not yet expose enough timing detail to prove this as the direct latency source.

Chart-session correlation after the screenshot timestamps were supplied:

- Production telemetry intentionally stores no chart title or chart ID, so `Nadie Como Tu` cannot be selected by name. The matching session was isolated by device model, build, local timestamps, layout style, and the distinctive `32 -> 33 -> 19` measure sequence.
- The matching `iPad13,2` / build `51` session created a Rhythm Section chart at 4:38:23 PM and completed its initial 32-measure setup at 4:38:48 PM.
- Chord-entry activity began at 5:15:34 PM, with preview activity from 5:19 PM onward, matching the 5:15, 5:22, and 5:24 screenshots.
- The chart changed to 33 measures by 5:34:05 PM. Page ink was then erased from 85 strokes down to 4 between 5:35:20 and 5:35:56, rebuilt to 44 strokes by 5:40:29, and retained exactly 44 strokes / 881 points through the 5:42:51 PM measure edit.
- At 5:42:51 PM the Measures tool committed `measure_count = 19` and switched directly to Free-Write. The app reprojected those unchanged 44 strokes from `724 x 2944` to `724 x 1248`; the next persistence row at 5:42:57 PM still had 44 strokes / 881 points in the shorter frame. This is direct evidence of coordinate compression and closely matches `IMG_0281.PNG` at 5:43 PM.
- This session correlation is strong but not a title-level database lookup: title and raw chart contents are absent by design.

What this does not prove:

- Production telemetry does not currently expose raw chord text or raw strokes, by design.
- The build `51` chord preview rows did not contain the newer issue-bucket keys such as `issue_count`, `root_issue_count`, `root_accidental_issue_count`, or `quality_issue_count`; rows-with-those-keys were 0 for both Rhythm Section and Simple Sheet preview telemetry.
- Therefore this production query cannot corroborate the current `G`/`B` root failures or the spaced-flat/accidental issue. Those still require a current DEBUG device trace or a later build that ships the aggregate issue-bucket telemetry.
- No recent `cloud.push_*` or `cloud.restore_*` events appeared in this filtered build-51 telemetry, so "sync state" currently points more strongly at local ink persistence/canvas sync than cloud sync unless cloud telemetry is missing or delayed.

Recognition timing seen in production telemetry:

- Rhythm Section `chord.preview_updated`: 77 preview events, 91 payloads, 82 matched, 67 trusted, 24 confirm, 9 no-read/unresolved. Median recognition time was about 4.49 ms, p95 about 40.27 ms, max 261.09 ms.
- Simple Sheet `chord.preview_updated`: 73 preview events, 141 payloads, 134 matched, 110 trusted, 31 confirm, 7 no-read/unresolved. Median recognition time was about 5.34 ms, p95 about 15.63 ms, max 20.68 ms.
- These recognition times do not explain broad Pencil drag by themselves. The stronger suspicion remains persistence, canvas drawing, layout invalidation, eraser hit-testing, or coordinate reprojection work.

## Ink Responsiveness Device Pass: 2026-09-08 17:28 PT

This pass used the current DEBUG app container plus production telemetry for installation `B8CA220C-25C8-40A0-AAFE-0F620FCF9A87` and session `21B4224E-5F96-4C36-B973-B2AFD5762127`. The local performance trace is a retained tail because the recorder rotates at 768 KB; production telemetry covers the full `00:06:14Z` through `00:12:04Z` session.

### Physical-iPad observations from the pre-vector-overlay build

- The retained local trace contains 475 events from `00:10:26Z` through `00:12:13Z`.
- Production received 55 events for the session: 24 `chord.preview_updated`, 3 `chord.preview_rendered`, 10 `ink.persisted`, 9 editor mode changes, 2 editor opens, 2 chart opens, 1 coordinate-space reprojection, and launch/bootstrap/auth/editor-close events.
- Rhythm Section preview work produced 12 events / 28 payloads: all 28 matched a target, 17 were trusted, 11 required confirmation, and none were no-read or unresolved. Recognition median was 13.311 ms, p95 56.278 ms, and max 90.011 ms.
- Simple Sheet preview work produced 12 events / 22 payloads: all 22 matched a target, 8 were trusted, 14 required confirmation, and none were no-read or unresolved. Recognition median was 6.079 ms, p95 18.899 ms, and max 21.803 ms.
- Persisted chord ink reached 27 strokes / 379 points. Persisted page ink reached 252 strokes / 4,982 points on `Nadie Como Tu` and 81 strokes / 2,064 points on the Simple Sheet chart.
- Chord live-callback main-thread work was bounded at 0.199–0.277 ms (median 0.228 ms) across the retained samples; there were zero `ink.input.slow_callback` events.
- Background chord preparation was 3.805–34.219 ms (median 9.504 ms, p95 30.338 ms). Preview replacement on the main thread was 0.523–2.623 ms (median 1.119 ms, p95 2.328 ms).
- Background serialization was 0.376–4.066 ms (median 2.252 ms, p95 3.742 ms). Main-thread chart writeback was 0.007–1.063 ms (median 0.586 ms, p95 0.681 ms).
- Manual erasing stayed at or below 1.10 ms in the retained trace.
- The editor skipped 28 backing redraws for persistence-only updates, eliminating the old pattern in which every recognition/save forced another full chart draw.
- At 61 Simple Sheet page strokes, background serialization took 1.885 ms and the main-thread chart writeback took 0.223 ms while the user continued to write to 81 strokes.

### Remaining cost isolated by the trace

Nine actual backing draws remained in the retained tail. Ordinary tool-state draws were about 7–10 ms, but saved page-ink rasterization made several transitions expensive:

- Rhythm Section exit from Free-Write: 83.374 ms total, including 71.354 ms saved-ink raster work.
- Simple Sheet initial open: 46.906 ms total, including 40.589 ms saved-ink raster work.
- Simple Sheet Render Chords: 124.870 ms total, including 116.656 ms saved-ink raster work.
- A later Simple Sheet Render Chords: 56.720 ms total, including 48.154 ms saved-ink raster work.
- Exit from dense Simple Sheet Free-Write: 60.832 ms total, including 54.954 ms saved-ink raster work.

The 124.870 ms draw occurred at the same timestamp as `chord.preview_rendered`. It was a real layout/render mutation, not a persistence echo. The repeated cost inside those slow draws was synchronous `PKDrawing.image(from:scale:)` conversion of unchanged page ink.

The single coordinate-space telemetry event at `00:10:28Z` reported `scope=chords`, 252 strokes, and a `732 x 2088` to `594 x 1008` transform. Timeline correlation showed Free-Write -> Browse at `00:10:26Z`, then Browse -> Chord at `00:10:28Z`. Inspection proved that a hidden authoring canvas still held the 252 page strokes after its scope identity had been cleared. Activating Chord temporarily reprojected those stale page strokes as chord ink before loading the correct empty chord drawing. The stale drawing was not written into chord storage, but the transform wasted main-thread work and emitted misleading telemetry.

### Final responsiveness iteration

- `LeadSheetInkCanvasSyncPolicy.shouldReprojectActiveCanvas` now permits reprojection only when the resident canvas identity exactly matches the target scope and the dirty resident drawing is not being preserved. A newly activated or switched scope loads its own model drawing without first transforming stale pixels from another scope.
- Saved page ink now remains in a noninteractive passive `PKCanvasView` beneath the active authoring canvas. Browse, Chord, Edit, Text, Time, Measures, and Repeat transitions keep the same vector drawing resident instead of synchronously flattening the page to a new image during `UIView.draw(_:)`.
- Saved handwritten header ink now uses its own noninteractive passive `PKCanvasView` as well. Entering Header hands the same drawing to the authoring surface; leaving Header returns it to the passive vector surface without a first-cache-miss raster stall.
- Free-Write temporarily hides the passive surface and uses the authoring surface for the same page drawing. Leaving Free-Write restores the passive vector surface; persisted bytes and source/target coordinate spaces still remain authoritative.
- The passive surfaces cache drawing data, source coordinate space, target coordinate space, and frame. Unchanged tool switches are no-ops. A real data or geometry change reloads/reprojects the vector drawing and emits `editor.saved_page_ink_canvas.load` or `editor.saved_header_ink_canvas.load` timing with source byte and stroke counts.
- PDF export and telemetry diagnostics continue using `LeadSheetSavedInkRenderer`; only interactive editor compositing moved off the synchronous raster path.

### Automated gates for the final source

- Scope-switch policy suite: `/tmp/iChartInkScopeSwitchFocused-20260908.xcresult` — 182 selected, 180 passed, 2 explicit fixture skips, 0 failures.
- Passive-vector surface regression: `/tmp/iChartPassiveInkOverlay-20260908.xcresult` — 1 selected, 1 passed, 0 failures.
- Page/header passive-vector regressions: `/tmp/iChartPassivePageHeaderInkOverlay-20260908.xcresult` — 2 selected, 2 passed, 0 failures.
- Combined policy and PDF suite: `/tmp/iChartPassiveInkFocused-20260908.xcresult` — 196 selected, 194 passed, 2 explicit fixture skips, 0 failures.
- Final full suite: `/tmp/iChartInkResponsivenessAllVectorFull-20260908.xcresult` — 1,197 selected, 1,153 passed, 44 explicit skips, 0 failures.
- `git diff --check` is clean.

### Exact installed build and persistence proof

- Installed app: `/tmp/iChartDerived-device-all-vector-20260908/Build/Products/Debug-iphoneos/iChart.app`.
- App version/build: `1.2.1 (51)`.
- arm64 UUID: `4170C610-6B8B-3BDF-B835-D7B40272F7CD`.
- Executable SHA-256: `f59ac046047acea0088025af69ddac120c465eb6d9c6712d1ea77e159b789a8b`.
- Deep strict code-sign verification passed; install and launch on device `376D59F8-92F2-5260-B10E-BA0BEAF941AB` succeeded.
- The build still emits the known `IChartTelemetry` UIDevice actor-isolation warnings, the old `LibraryView` `onChange` deprecation, and Supabase's `detail` -> `details` rename warning. It is not warning-free.
- A preceding install caused PencilKit to reserialize two drawings with 22 additional metadata bytes each, while their decoded stroke/control-point digests remained exact. Against that stabilized baseline, the final all-vector install preserved `library-state.json` byte-for-byte: 635,171 bytes and SHA-256 `2f72b2e1e3dcdcde3798be004ca9788a7ff0f7138e9b0a0eb17e7ec76758322c` before and after install.
- Semantic/model persistence is exact: selected chart, chart count, titles, layout styles, timestamps, row measure counts, measure IDs, chord IDs, coordinate-space dimensions, and anchor counts all remained unchanged.
- Decoded PencilKit stroke counts, control-point counts, and visible bounds remained unchanged: Simple Sheet `81 / 2,064 / (78,103,633,1102)`, `Nadie Como Tu` `252 / 4,982 / (37,129,698,1294)`, and `Higher Love` `1 / 6 / (94,575,5,17)`.
- Deterministic SHA-256 over each decoded stroke's ink type/color, affine transform, random seed, creation date, and every control point matched before/after install: Simple Sheet `dee646f47dc5d7eab440441007fcc39f086805746b594d9f6c579378570157ca`; `Nadie Como Tu` `f3db285f6ed47aaf71d74d25aa81270760c93c319bc5785ac2ad6ca474a49674`; `Higher Love` `23db6082cd5c91d7b3cce697fb4d6bf5c05b81977dcc0d628cc2a9b1da5e8c73`.

### Telemetry limitation and remaining physical acceptance

- The deployed telemetry ingest still strips the newer issue-bucket keys. This session had zero stored rows containing `issue_count`, `root_issue_count`, `root_accidental_issue_count`, or `quality_issue_count`; production telemetry must not be presented as chord-specific B/G proof.
- The exact all-vector build above is installed and launched, but it has not yet received a fresh human Pencil/tool-switch pass. Automated tests prove composition and persistence behavior, not perceived Pencil feel on hardware.
- Final acceptance requires a short pass on this exact UUID: dense fast Free-Write and chord writing, erase, Browse/Chord/Free-Write switches, Render Chords, and a portrait/landscape round trip. Pull the new local trace afterward and verify that `editor.saved_page_ink_canvas.load` replaces the prior 40–116 ms saved-raster spans, no cross-scope 252-stroke chord reprojection occurs, and no new live-input slow callbacks appear.
- No Edge Function deployment, commit, push, archive, upload, TestFlight delivery, or App Store submission occurred in this pass.

## All-Vector Physical-iPad Pass: 2026-09-08 17:40 PT

This pass exercised the exact all-vector device build above on `Nadie Como Tú` using installation `B8CA220C-25C8-40A0-AAFE-0F620FCF9A87` and session `8ADCE538-DAC7-4496-AE88-2E781B2A2A80`. The read-only device pull is `/tmp/ichart-fresh-pass-20260908.zLjrkF/app-support`; it contains the local performance trace, full DEBUG chord diagnostics, correction memory, telemetry queue, and the post-pass library state. Production Supabase received the aggregate events through `00:43:00Z`.

### Workload and persistence state

- The session ran from `00:37:59Z` through `00:43:11Z` locally. Production received 59 events: 29 editor mode changes, 14 chord preview updates, 3 preview renders, 1 preview discard, and 7 ink persistence events.
- Free-Write grew the existing page drawing from 252 strokes to 307 strokes / 6,944 points, then to 320 strokes / 7,247 points. The final eraser sweep persisted 294 strokes / 6,572 points.
- The pass repeatedly crossed Browse, Chord, and Free-Write, then wrote, rendered, rewrote, and erased chord ink before erasing the dense page drawing.
- There were zero `ink.coordinate_space_reprojected` production events and zero local `ink.input.slow_callback` events.
- The post-pass `library-state.json` is 670,557 bytes with SHA-256 `48830c97080fc38a41e990e3e30d86c062a83e81653fef36e81934713cebc1ba`. `Nadie Como Tú` remained selected, retained 22 measures, and stored the final page drawing as 126,173 decoded bytes.

### Measured hot-path timing

- Main-thread chord capture: 14 samples, 0.047-0.290 ms, median 0.239 ms.
- Background chord preparation: 14 samples, 2.075-24.675 ms, median 14.465 ms.
- Main-thread preview replacement: 14 samples, 0.309-1.327 ms, median 0.585 ms.
- Background ink serialization: 16 samples, 0.525-3.283 ms, median 2.943 ms.
- Main-thread chart writeback: 32 samples, 0.004-2.097 ms, median 0.127 ms and p95 0.713 ms.
- Manual erasing recorded 76 sampled segments. Seventy-four were at or below 1.88 ms; the two cold samples were 11.74 ms for the first dense-page erase and 87.84 ms for the first chord erase. Subsequent chord eraser groups peaked at 0.96, 0.99, and 1.13 ms, matching the user's report that erasure felt responsive while isolating the first-contact outlier for continued observation.

The live Pencil callback, serialization, and writeback numbers rule those paths out as the cause of sustained visible drag in this pass. Production recognition telemetry had median 8.769 ms, p95 66.874 ms, and max 93.265 ms across 14 preview rows, but recognition ran after the live stroke was already captured and therefore does not explain delayed ink appearance.

### Remaining main-thread cost found after vector compositing

The passive saved-page surface removed all legacy `PKDrawing.image(from:scale:)` spans, but it was still decoded and anchor-reprojected too often:

- 20 `editor.saved_page_ink_canvas.load` events consumed 248.428 ms on the main thread; median was 11.194 ms and max was 38.740 ms.
- Twelve unchanged 320-stroke / 138,067-byte reloads occurred during the `00:41:45Z` through `00:41:50Z` Chord/layout burst.
- Additional unchanged reloads took 20.870 ms at `00:41:58Z`, 20.561 ms at `00:42:38Z`, and 21.060 ms at `00:42:45Z`.
- The latter reloads correlated with rendered chord changes. New target-only chord anchors were invalidating the saved-page cache even though a chord created after the page ink was saved cannot own any of those old strokes.
- Orientation/layout churn also submitted every intermediate target geometry instead of allowing the geometry to settle.

### Follow-up iteration from this pass

- Saved page/header decode and anchor transformation now use a cancellable background preparation session after the initial load. The existing passive vector canvas remains visible until the latest result is ready.
- Geometry changes coalesce for 50 ms so a rotation applies the final coordinate space rather than every intermediate layout.
- The passive cache ignores target-only chord anchors while continuing to invalidate for page size, measure anchors, and matching source chord anchors. Rendering a new chord therefore no longer reprojects unrelated saved page ink.
- Leaving Header or Free-Write transfers the already-resident `PKDrawing` directly when its coordinate space matches, avoiding an unnecessary decode.
- The slow-looking per-stroke anchor lookup was also changed from repeated filtered-array allocation to a single-pass nearest-anchor scan without changing first-on-tie behavior.
- The first write contact is handed to PencilKit before cancellation locks are acquired. Stale background completions still remain ordered behind the main-queue cancellation.
- Focused post-change gate: `/tmp/iChartSavedInkAsyncFocused-20260908.xcresult` - 188 selected, 186 passed, 2 explicit fixture skips, 0 failures.

The all-vector pass is evidence for the remaining reload defect, not acceptance evidence for this follow-up source: the background/coalescing changes were made after the pass. They require a new exact build, persistence comparison, and a final physical-iPad trace.

## Async Saved-Ink Final Build and Read-Only Data Pull: 2026-09-08 18:07 PT

The follow-up source from the all-vector pass completed both focused and full automated gates, then received a new exact physical-device build. This section deliberately separates install/persistence proof from human Pencil acceptance.

### Automated gates and exact installed binary

- Saved-ink async focused suite: `/tmp/iChartSavedInkAsyncFocused-20260908.xcresult` - 188 selected, 186 passed, 2 explicit fixture skips, 0 failures.
- Combined policy/renderer/PDF suite: `/tmp/iChartSavedInkAsyncCombined-20260908.xcresult` - 209 selected, 207 passed, 2 explicit fixture skips, 0 failures.
- Final full suite: `/tmp/iChartInkResponsivenessAsyncFinalFull-20260908.xcresult` - 1,201 selected, 1,157 passed, 44 explicit environment/fixture skips, 0 failures.
- Installed app: `/tmp/iChartDerived-device-async-final-20260908/Build/Products/Debug-iphoneos/iChart.app`; version/build `1.2.1 (51)`; arm64 UUID `C249E4E6-9EAC-34DB-A6D5-93D544A7275E`; executable SHA-256 `c5872ba57d11c6f592a682d3877294aa46b0b490c16e21a315f9dad78b82e9ef`.
- Deep strict code-sign verification passed. Install completed at 18:00:10 PT and launch completed at 18:00:27 PT on device `376D59F8-92F2-5260-B10E-BA0BEAF941AB`.
- The known `IChartTelemetry` actor-isolation warnings, `LibraryView` `onChange` deprecation, and Supabase `detail` to `details` warning remain. This build is not warning-free.

### Install and launch persistence proof

- Preinstall snapshot: `/tmp/ichart-async-final-preinstall-20260908.WoVIS6/app-support`; `library-state.json` was 670,557 bytes with SHA-256 `48830c97080fc38a41e990e3e30d86c062a83e81653fef36e81934713cebc1ba`.
- Before first launch, the installed container matched that state byte-for-byte: `/tmp/ichart-async-final-postinstall-20260908.XUan40/app-support`.
- First launch changed only `charts[1].pageHandwrittenNotationData`, the `Nadie Como Tu` PencilKit archive, from 126,173 to 126,195 bytes. Canonical JSON with all drawing blobs redacted matched exactly with SHA-256 `21528d6da4bb7d78613b09f4e53f28171e2c8de001c001030b8b4c8ffcbad979`.
- The 22-byte archive change is metadata-only. Before/after decoded `Nadie Como Tu` drawings both contain 294 strokes, 6,572 control points, and bounds `(37, 67, 698, 1356)`. A deterministic digest over ink/color, transform, random seed, creation date, and every control point matched at `ccc4836e9982cf3783f94baf55037241819d4a92735e095757b54862657268fa`.
- The two Simple Sheet drawings remained byte-for-byte and semantically exact: Untitled Chart 81 strokes / 2,064 points / bounds `(78, 103, 633, 1102)` / digest `11d993610c67eeefea9f6a0eeedef80b866c2679749c3eb6691c3fe2390e25ac`; Higher Love 1 stroke / 6 points / bounds `(94, 575, 5, 17)` / digest `f712a71326571af4f5e649675d2c744ab6cee5d2e267c1bc807bf3c720d342e9`.

### What the latest pull contains and does not contain

- Immutable Application Support snapshot: `/tmp/ichart-async-final-pass-20260908.NswMO9/app-support`; full Library snapshot: `/tmp/ichart-async-final-full-container-20260908.z13mYh/Library`.
- The new runtime session is `8181CD60-BE1B-4780-A616-EA54B6CA65EE`. Both the local trace and production telemetry contain only `app.launched`, `app.bootstrap_completed`, and `auth.state_changed` at 18:00:28-18:00:29 PT.
- A second pull at 18:06:58 PT remained unchanged at 393,243 bytes and still ended at `app.bootstrap.end`. The iChart process remained running, and there were no iChart-named system crash logs.
- Therefore the current UUID has no recorded editor open, chart open, Pencil input, chord preview, tool switch, rotation/layout interaction, persistence, or erase evidence. This is not a buffering ambiguity: the local file and server independently stop at bootstrap.
- The preceding all-vector session now has 60 production rows. The 60th row is an `editor.mode_changed` event that occurred at 17:43:03 PT but remained queued until the new launch; it does not belong to the new runtime workload.

No Edge Function deployment, commit, push, archive, upload, TestFlight delivery, or App Store submission occurred in this data pull.

## Cold-Path Ink Responsiveness Candidate: 2026-09-08 18:26 PT

The later `01:15Z` physical-device trace on the preceding async build supplied the final cold-path targets. The page reached 359 strokes before erasure, passive page preparation took 12.653-31.831 ms in the background while main-thread apply stayed at 0.525-0.705 ms, and the page was ultimately persisted at 270 strokes. This supports the background saved-ink work, but it also leaves whole-drawing canvas handoff and the first erase index build as distinct costs.

### Final source changes from that evidence

- Initial saved page/header decode and coordinate preparation now use the cancellable background preparation session too; the initial chart load no longer performs that whole-drawing preparation on the main thread.
- Page and header authoring can take the already-prepared resident passive `PKDrawing` when the data, frame, and coordinate spaces match. Returning to Free-Write/Header therefore avoids decoding the same dense archive again.
- A fresh or switched active scope prepares the incoming model drawing once and installs it directly. It no longer serializes a hidden stale canvas merely to prove it differs, and it no longer decodes the same incoming archive twice.
- The direct scope-load rule applies to Chord, page Free-Write, header ink, Rhythm measure ink, and note-selection ink. A 320-stroke Page -> Chord regression covers both Simple Sheet and Rhythm Section.
- Selecting Erase now prebuilds the active drawing's spatial index on a background queue, keyed by drawing revision and ink scope. A contact that beats prewarm still takes the synchronous correctness fallback; stale or cancelled preparation cannot replace the index for a newer drawing.
- A dedicated regression simulates a new dirty page stroke followed immediately by a direct Page -> Chord switch in both chart styles. The pending page stroke is persisted before the canvas is reused, and the saved chord drawing then replaces the page drawing.

### Automated gates for the exact candidate source

- Post-refactor combined ink/recognition gate: `/tmp/iChartInkScopeLoadCombined-20260908.xcresult` - 259 selected, 257 passed, 2 explicit fixture skips, 0 failures.
- Dirty scope-handoff focused gate: `/tmp/iChartInkDirtyScopeFocused-20260908-1824.xcresult` - 195 selected, 193 passed, 2 explicit fixture skips, 0 failures.
- Exact final full suite: `/tmp/iChartInkResponsivenessFinalFull-20260908-1825.xcresult` - 1,208 selected, 1,164 passed, 44 explicit environment/fixture skips, 0 failures.
- `git diff --check` is clean.

### Exact installed binary and persistence baseline

- Installed app: `/tmp/iChartDerived-device-ink-coldpath-final-20260908-1825/Build/Products/Debug-iphoneos/iChart.app`; version/build `1.2.1 (51)`.
- arm64 UUID: `5A9D04CB-4AB9-3F60-9C04-6F7115CC363A`; executable SHA-256: `36ae07188d614618e83b7fcdc0fdfed50bb7748d5dfe3f03cf540a67463bbe36`.
- Deep strict code-sign verification passed. Installation completed at 18:26:12 PT and foreground launch completed at 18:26:35 PT on device `376D59F8-92F2-5260-B10E-BA0BEAF941AB`.
- Fresh preinstall snapshot: `/tmp/ichart-ink-coldpath-preinstall-20260908.lFmDUO`; `library-state.json` was 658,012 bytes with SHA-256 `abe1c3803ce168d2a426c5899f365b7b64a7afd0c4145219881ed1beceaf5f8d`.
- The postinstall/prelaunch snapshot `/tmp/ichart-ink-coldpath-postinstall-prelaunch-20260908.75suRm` matched the entire Application Support snapshot byte-for-byte.
- First launch changed only the `Nadie Como Tu` PencilKit archive from 116,555 to 116,577 decoded bytes. Canonical JSON with all `*Data` blobs redacted matched exactly at SHA-256 `7a16130a916272bdcb9f47cff159c9cc40d2fb7c86b796ff47c0d82d2d18084a`.
- Decoded drawings remain semantically exact before/after launch. Untitled Chart: 81 strokes / 2,064 points / digest `72b0418799702d345749b7db90590e8c849dd2676a4726e925b51dddbdb2c4bb`; Nadie Como Tu: 270 strokes / 6,247 points / digest `32a5a39d2ca53914c7fb40db353b073c43d7ea785f50cea7a17f2cfc925d8c0c`; Higher Love: 1 stroke / 6 points / digest `dd72eea3e18cf60aa6f02d55f4b6e018bec246a90dc8cd18ea9db1fa9eccd5fa`.
- The postlaunch baseline is `/tmp/ichart-ink-coldpath-postlaunch-baseline-20260908.aleW8m`. Its trace ends at `app.bootstrap.end` at `01:26:36Z`; this exact UUID has no editor/Pencil acceptance evidence yet.

Final acceptance still requires the human Pencil pass on this installed UUID: open `Nadie Como Tu`, rapidly add dense Free-Write ink, switch Browse -> Chord, write and render 10-15 chords quickly, return to Free-Write, select Erase and erase immediately, rotate landscape and back, then leave the app open for a read-only trace pull. The pull must confirm background initial preparation, resident reverse transfer, background eraser prewarm or a bounded fallback, no `ink.input.slow_callback`, and semantic persistence after the workload.

No Edge Function deployment, commit, push, archive, upload, TestFlight delivery, or App Store submission occurred in this candidate pass.

## Incremental Eraser Follow-up: 2026-09-08 18:35 PT

The cold-path candidate above is superseded before human acceptance. The later device workload showed that selecting Erase successfully warmed the first spatial index, but each successful removal invalidated that index. The next raw Pencil movement then cancelled the replacement preparation and rebuilt the complete dense-page index synchronously. The same gesture also materialized `drawing.strokes` solely to obtain a telemetry count on every movement. From `01:26:35Z` onward the superseded trace recorded 204 `editor.active_ink_erase.index_prepare` events, proving the rebuild was recurring rather than a one-time cold cost. Continuous erase samples of roughly 5-15.81 ms exposed the same defect even though first-contact prewarm itself worked.

### Follow-up implementation

- The active erase index now assigns stable stroke IDs and keeps separate active-ID and current-index maps. After a removal it incrementally removes only the affected IDs and remaps the surviving current indices; it does not recompute every surviving stroke's render bounds and grid cells.
- Candidate lookup filters inactive IDs, evaluates the original stored stroke geometry, and maps matches back to the current `PKDrawing` indices, preserving correctness after indices shift.
- A successful erase still advances the drawing revision and invalidates serialization, but preserves the already-updated erase index for the next movement in the same gesture.
- Manual-erase telemetry caches the active stroke count when erase mode is enabled and updates that count after removals. Raw touch movement no longer materializes the full stroke array just to record the sample.
- A successful removal now builds the replacement drawing, remaining count, and final surviving stroke from one retained-stroke pass. It no longer materializes the replacement drawing's full stroke array a second time before scheduling persistence/recognition.
- Programmatic drawing changes and real scope changes still invalidate the erase index and refresh the cached count, so the optimization cannot reuse geometry for a different drawing.
- A 400-stroke regression repeatedly removes eight rows and compares indexed candidates against a full scan after every index shift; the count reaches 392 and the removed region stops returning candidates.

### Post-follow-up automated gates

- Incremental-erasure focused gate: `/tmp/iChartInkIncrementalEraseFocused-20260908.xcresult` - 196 selected, 194 passed, 2 explicit fixture skips, 0 failures.
- Combined ink/recognition gate: `/tmp/iChartInkIncrementalEraseCombined-20260908-1835.xcresult` - 261 selected, 259 passed, 2 explicit fixture skips, 0 failures.
- Complete app suite: `/tmp/iChartInkIncrementalEraseFinalFull-20260908-1837.xcresult` - 1,209 selected, 1,165 passed, 44 explicit environment/fixture skips, 0 failures.
- Final retained-stroke focused gate: `/tmp/iChartInkRemovalSummaryFocused-20260908-1842.xcresult` - 196 selected, 194 passed, 2 explicit fixture skips, 0 failures.
- Exact final complete app suite: `/tmp/iChartInkResponsivenessExactFinalFull-20260908-1844.xcresult` - 1,209 selected, 1,165 passed, 44 explicit environment/fixture skips, 0 failures.
- `git diff --check` is clean.

The previously installed UUID `5A9D04CB-4AB9-3F60-9C04-6F7115CC363A` does not contain this incremental-erasure change and must not be used as acceptance evidence. A fresh signed device binary, install/launch persistence comparison, and physical Apple Pencil pass are still required.

### Exact incremental-erasure device candidate

- Installed app: `/tmp/iChartDerived-device-ink-incremental-erase-final-20260908/Build/Products/Debug-iphoneos/iChart.app`; version/build `1.2.1 (51)`.
- arm64 UUID: `9E0293BA-8884-3900-8E62-986154052496`; executable SHA-256: `1112e34f65debea0ef4035f214209aad89f8462f5cf848e91c0f03f01014eb2f`.
- Deep strict code-sign verification passed. Installation completed at 18:38:42 PT to `/private/var/containers/Bundle/Application/CC27FB0B-D0B0-4588-9E56-411F4949A6ED/iChart.app`, and launch completed at 18:39:14 PT with live PID 1295.
- Fresh preinstall Library snapshot: `/tmp/ichart-ink-incremental-preinstall-20260908.a78Xdy/Library`. The old running process changed only `selectedChartID` while install terminated it; all three decoded page drawings remained semantically exact across that boundary.
- Stable postinstall/prelaunch baseline: `/tmp/ichart-ink-incremental-postinstall-prelaunch-20260908.LzDBo0/Library`; postlaunch baseline: `/tmp/ichart-ink-incremental-postlaunch-baseline-20260908.xSxAB5/Library`.
- First launch restored the prior selected chart and added 22 metadata bytes to only the `Nadie Como Tú` PencilKit archive. Its decoded drawing remained exactly 109 strokes / 3,164 control points with semantic digest `098b8d7abd4335e31b613436cf259bca73429b0baf3f3c4603b659b483f8d0df`.
- The other page drawings also remained semantically exact: Untitled Chart 108 strokes / 2,755 points / digest `94640b553a15a0c48912ba572aa8df5c00c8ed20702618ddab05aa10c54a6ac4`; Higher Love 1 stroke / 6 points / digest `dd72eea3e18cf60aa6f02d55f4b6e018bec246a90dc8cd18ea9db1fa9eccd5fa`.

This exact UUID still needs the final physical Apple Pencil workload. Automated gates and archive digests prove code-path correctness and persistence, but they cannot establish perceived contact latency or prove that one continuous dense erase sweep no longer rebuilds the index on hardware.

## Cached Stroke-Count Final Candidate: 2026-09-08 18:52 PT

The incremental-erasure device candidate above is superseded before human acceptance. A final audit found that several live and transition paths still materialized the complete `PKDrawing.strokes` array only to recover its count. That work was redundant after the PencilKit delegate or a known programmatic mutation had already supplied the new drawing.

### Final implementation

- The canvas host now maintains `activeCanvasStrokeCount` from the authoritative PencilKit drawing-change callback and from every known programmatic drawing assignment.
- Intentionally muted model-sync callbacks return before materializing the stroke array. Saved-canvas transfer, direct scope load, reprojection, normalization, clear, persistence scheduling, recognition scheduling, telemetry, and slow-draw reporting reuse the known count.
- The scoped canvas maintains `manualEraseSamplingStrokeCount` from the host. Selecting Erase no longer enumerates the complete drawing merely to initialize erase telemetry.
- Draft-barline deletion removes strokes and computes the remaining count in one retained-stroke pass before assigning the replacement drawing.
- A regression, `testManualInkEraseToolSelectionPreservesHostSuppliedStrokeCount`, verifies that Erase selection preserves the host-supplied count without re-enumerating the drawing.

### Exact final automated gates

- Focused ink/interaction gate: `/tmp/iChartInkCachedStrokeCountFocused-20260908.xcresult` - 197 selected, 195 passed, 2 explicit fixture skips, 0 failures.
- Complete app suite: `/tmp/iChartInkCachedStrokeCountFinalFull-20260908.xcresult` - 1,210 selected, 1,166 passed, 44 explicit environment/fixture skips, 0 failures.
- `git diff --check` is clean.

### Exact installed binary and persistence evidence

- Installed app: `/tmp/iChartDerived-device-ink-cached-count-final-20260908/Build/Products/Debug-iphoneos/iChart.app`; version/build `1.2.1 (51)`.
- arm64 UUID: `5AC1C1A2-FCE5-332D-8231-EEF18F4622B3`; executable SHA-256: `da19bcc576d03ddf086edb8ad3016bc0ec4b2466166b803598a2a0c6420be6b1`.
- Deep strict code-sign verification passed. Installation completed at 18:52:03 PT; foreground launch completed at 18:52:24 PT. The exact executable is running as PID 1300 from `/private/var/containers/Bundle/Application/DAE11C02-49C4-404D-995E-8F79C199077B/iChart.app/iChart`.
- Preinstall Library snapshot: `/tmp/ichart-ink-cached-count-preinstall-20260908.vVZU49/Library`; postinstall/prelaunch snapshot: `/tmp/ichart-ink-cached-count-postinstall-prelaunch-20260908.nFa6O9/Library`; postlaunch baseline: `/tmp/ichart-ink-cached-count-postlaunch-baseline-20260908.eOXq0j/Library`.
- Install preserved the complete Application Support directory byte-for-byte. First launch rewrote PencilKit archive metadata but preserved the decoded drawings exactly: Untitled Chart 93 strokes / 3,341 points / digest `784b5d7b988e2160913f778766b22047cdc8277e351e928250ebebc01a4e72b1`; Nadie Como Tu 103 strokes / 3,878 points / digest `2f06af5a1aacba729e9e4bce19a47e6c2da4e7ebe7104751a4a64d52f36c8567`; Higher Love 1 stroke / 6 points / digest `dd72eea3e18cf60aa6f02d55f4b6e018bec246a90dc8cd18ea9db1fa9eccd5fa`.
- The exact-build trace currently contains only the 18:52:25-18:52:26 PT initialization, notation warm-up, and bootstrap records. A second container pull at 18:53:55 PT was byte-for-byte identical to the postlaunch baseline and added no trace records. Production telemetry independently contains only `app.launched`, `auth.state_changed`, and `app.bootstrap_completed` for runtime session `BE34E251-26B2-40D6-9BB5-FC2C287963C1`. This proves that no editor or Apple Pencil workload has yet been recorded on this UUID.

Physical acceptance remains mandatory on this exact UUID. The final workload must cover dense page Free-Write, rapid Chord writing and rendering, immediate continuous dense erasure, portrait/landscape round-trip, and a short Simple Sheet repetition. The subsequent trace must show bounded live callbacks, background or resident drawing preparation, no recurring complete erase-index rebuild, and exact persisted ink after the workload. No Edge Function deployment, commit, push, archive, upload, TestFlight delivery, or App Store submission occurred in this final candidate pass.

## Whole-App Drawing-Read Final Audit: 2026-09-08 19:04 PT

The cached stroke-count candidate above is superseded before human acceptance. A whole-app audit found additional repeated full-drawing reads outside the active canvas host: PencilKit recognition adaptation, batch chord targeting, recognition-session diagnostics, passive saved-canvas application, erase preparation, and persistence color-policy checks. These were individually bounded, but they compounded on dense drawings and during rapid tool/layout transitions.

### Final source changes

- PencilKit recognition adaptation caches the drawing's strokes once instead of materializing them separately for capacity and iteration.
- Batch chord targeting captures the drawing's strokes once for all clustered target lookups rather than retrieving the complete collection for each stroke index.
- Chord recognition sessions carry the already-known recognition stroke count through empty checks, result construction, and diagnostics instead of repeatedly reopening the recognition drawing.
- Saved page/header canvas application now carries the authoritative prepared or resident stroke count through passive clear, visibility, transfer, reprojection, and background serialization paths.
- Persistence serialization requests can carry a known stroke count. Color-policy and empty-drawing checks use it when available while preserving the previous fallback for callers without an authoritative count.
- Erase preparation reports the maintained spatial-index count instead of enumerating the complete drawing again.
- The authoritative PencilKit delegate count remains unchanged: the preceding hardware trace measured that remaining full read at only 0.047-0.290 ms for a 320-stroke drawing, and it is required to identify the true final stroke after external PencilKit mutations.

### Exact final automated gates

- Final-audit focused gate: `/tmp/iChartInkFinalAuditFocused-20260908.xcresult` - 279 selected, 277 passed, 2 explicit fixture skips, 0 failures.
- Complete app suite: `/tmp/iChartInkFinalAuditFull-20260908.xcresult` - 1,210 selected, 1,166 passed, 44 explicit environment/fixture skips, 0 failures.
- `git diff --check` is clean.

### Exact installed binary and persistence baseline

- Installed app: `/tmp/iChartDerived-device-ink-final-audit-20260908/Build/Products/Debug-iphoneos/iChart.app`; version/build `1.2.1 (51)`.
- arm64 UUID: `97AD011D-478E-3B7D-845A-C8AFA1C87BC5`; executable SHA-256: `f3657969b0f9a5a796e562c9dbe703f86abf6230ccbc95d6826ebd4455460648`.
- Deep strict code-sign verification passed with the Apple Development identity and team `N6G8X4K46U`. Installation completed at 19:03:59 PT to `/private/var/containers/Bundle/Application/B520182B-BB54-4DDB-B92D-9730EF19D1A8/iChart.app`; foreground launch completed at 19:04:11 PT with live PID 1301.
- Fresh preinstall Library snapshot: `/tmp/ichart-ink-final-audit-preinstall-20260908.4vWUco/Library`; postinstall/prelaunch snapshot: `/tmp/ichart-ink-final-audit-postinstall-prelaunch-20260908.fzNg1n/Library`; postlaunch baseline: `/tmp/ichart-ink-final-audit-postlaunch-baseline-20260908.nOKobW/Library`.
- Installation preserved the complete Application Support directory byte-for-byte. First launch re-encoded only PencilKit archive metadata while all three decoded page drawings remained semantically exact: Untitled Chart 1 stroke / 18 points / digest `afb156699a9b16c84fdeedac1fa6382c9c14dff31d35c9a14626368d3ce09e2f`; Nadie Como Tú 15 strokes / 350 points / digest `f357a785d574f773c83d3d9c4a631cf65bfc917c539929b28df2f6359a8701f2`; Higher Love 1 stroke / 6 points / digest `dd72eea3e18cf60aa6f02d55f4b6e018bec246a90dc8cd18ea9db1fa9eccd5fa`.
- The smaller preinstall drawings are the persisted result of a real Pencil workload on the superseded build at 18:59 PT, not an install regression. The immutable preinstall snapshot records that state before replacement, and the exact semantic match proves the new install/launch retained it.
- The new local trace contains only `app.init`, notation warm-up, and bootstrap at 19:04:11-19:04:12 PT. Production independently contains only `app.launched`, `auth.state_changed`, and `app.bootstrap_completed` for session `DF2C8629-9B50-4912-ABAC-268558043250`. No editor or Pencil workload has yet occurred on UUID `97AD011D-478E-3B7D-845A-C8AFA1C87BC5`.

Physical Apple Pencil acceptance remains the final gate on this exact UUID. It must cover rapid dense Free-Write, rapid Chord writing and rendering, an immediate continuous dense erase sweep, portrait/landscape round-trip, and a short Simple Sheet repetition. Afterward, local trace, production telemetry, and a new semantic drawing snapshot must be pulled together. No Edge Function deployment, commit, push, archive, upload, TestFlight delivery, or App Store submission occurred in this audit.

UUID `97AD011D-478E-3B7D-845A-C8AFA1C87BC5` was superseded before human acceptance by the final count-stability audit below.

## Count-Stable Recognition and Persistence Final Candidate: 2026-09-08 19:11 PT

The final static pass found one remaining multiplicative read: `ChordInkDraftVisibleDrawingContext.visibleStrokeCount` derived its value from `drawing.strokes.count`. Recognition preparation consults that value throughout cancellation and outcome branches, so one prepared drawing could repeatedly materialize the complete PencilKit stroke array just to recover the same integer.

### Final count-stability changes

- Visible chord-ink count now comes from the already-built original-index mapping. That mapping is created in the same visibility-filtering pass and has exactly one entry per visible stroke, so repeated recognition outcome/diagnostic checks are constant-time.
- Persistent color normalization now captures the drawing's strokes once and reuses that collection for its empty check, normalization decision, and optional normalized drawing construction.
- Persisted-ink telemetry uses the same cached collection for iteration and count, and determines normalization need during that existing pass rather than traversing the drawing again.
- The outer serialization request still carries the authoritative active-canvas count, avoiding an extra full count read before the single normalization pass. The color policy itself derives the final serialized content from the actual stroke collection, preserving the drawing even if a caller's cached count were ever stale.

### Final automated gates

- Count-stability focused gate: `/tmp/iChartInkFinalReadAuditFocused2-20260908.xcresult` - 279 selected, 277 passed, 2 explicit fixture skips, 0 failures.
- Exact complete app suite: `/tmp/iChartInkFinalReadAuditFull2-20260908.xcresult` - 1,210 selected, 1,166 passed, 44 explicit environment/fixture skips, 0 failures.
- `git diff --check` is clean.

### Exact installed binary and persistence baseline

- Installed app: `/tmp/iChartDerived-device-ink-final-read-audit2-20260908/Build/Products/Debug-iphoneos/iChart.app`; version/build `1.2.1 (51)`.
- arm64 UUID: `D0ED58A8-9E5A-374D-90D6-B0F4129155B1`; executable SHA-256: `57e5ded09d5a47171ff2cfbfcea2f661331daa69cc05286c11bdab99573fb024`.
- Deep strict code-sign verification passed with the Apple Development identity and team `N6G8X4K46U`. Installation completed at 19:11:35 PT to `/private/var/containers/Bundle/Application/2F581827-BB22-4EC9-8F75-64C33BB47396/iChart.app`; foreground launch completed at 19:11:46 PT with live PID 1313.
- Fresh preinstall Library snapshot: `/tmp/ichart-ink-final-read-audit2-preinstall-20260908.xbM1y1/Library`; postinstall/prelaunch snapshot: `/tmp/ichart-ink-final-read-audit2-postinstall-prelaunch-20260908.uOAdKS/Library`; postlaunch baseline: `/tmp/ichart-ink-final-read-audit2-postlaunch-baseline-20260908.4YLfTE/Library`.
- Installation preserved the complete Application Support directory byte-for-byte. First launch changed only the performance trace: `library-state.json` remained byte-for-byte identical at SHA-256 `e681b929302fea95bfcd72299c8c5b7fb1f051fee6e9ecde3b92ae21c6c0116e`.
- All decoded page drawings remained semantically exact across install and launch: Untitled Chart 1 stroke / 18 points / digest `afb156699a9b16c84fdeedac1fa6382c9c14dff31d35c9a14626368d3ce09e2f`; Nadie Como Tú 15 strokes / 350 points / digest `f357a785d574f773c83d3d9c4a631cf65bfc917c539929b28df2f6359a8701f2`; Higher Love 1 stroke / 6 points / digest `dd72eea3e18cf60aa6f02d55f4b6e018bec246a90dc8cd18ea9db1fa9eccd5fa`.
- The local trace currently contains only initialization, notation warm-up, and bootstrap at 19:11:46-19:11:47 PT. Production independently contains only `app.launched`, `auth.state_changed`, and `app.bootstrap_completed` for session `14A7E8A8-AC61-41C0-94A0-38E230610DDB`. No editor or Pencil workload has yet occurred on this exact UUID.

This exact UUID is the sole remaining physical-acceptance candidate. It still requires rapid dense Free-Write, rapid Chord writing/rendering, immediate continuous dense erasure, a portrait/landscape round trip, and a short Simple Sheet repetition. The post-workload pull must jointly verify local callback/preparation/erase timings, production event coverage, and semantic drawing persistence. No Edge Function deployment, commit, push, archive, upload, TestFlight delivery, or App Store submission occurred in this final candidate pass.

## Count-Stable Physical-iPad Acceptance: 2026-09-08 19:21 PT

The user completed the full Apple Pencil workload on exact UUID `D0ED58A8-9E5A-374D-90D6-B0F4129155B1`. The local session ran from `02:11:46Z` through `02:16:43Z`; its settled full-Library snapshot is `/tmp/ichart-ink-final-read-audit2-settle-20260908.M51vLk/Library`. It covers dense Free-Write, Chord writing and rendering, immediate continuous erase, Browse/Chord/Free-Write transitions, portrait/landscape changes, and repetition on both Rhythm Section and Simple Sheet.

### Live-input and erase result

- The session recorded 954 local performance events, including 394 drawing changes at loads up to 103 page strokes and 771 raw erase samples. There were zero `ink.input.slow_callback` events; no PencilKit drawing-change callback reached the instrumented 4 ms threshold.
- The eraser considered 1,266 indexed candidates and removed 192 strokes. Its worst sampled segment was 3.17 ms; Rhythm Section peaked at 2.99 ms and Simple Sheet at 3.17 ms.
- Exactly seven `editor.active_ink_erase.index_prepare` events occurred. Every one was a `tool_selection_prewarm`, ranging from 0.022 to 0.311 ms. No erase movement rebuilt the complete index, so the superseded recurring-rebuild defect is absent on hardware.
- Rhythm Section exercised 185 drawing changes, 390 erase samples, and 88 maximum page strokes. Simple Sheet exercised 209 drawing changes, 381 erase samples, and 103 maximum page strokes.

### Recognition, persistence, and transition timing

- Main-thread chord capture: 18 samples, 0.130-0.283 ms, median 0.197 ms.
- Background chord preparation: 18 samples, 1.132-77.852 ms, median 17.888 ms. This runs after Pencil capture and outside the live input callback.
- Main-thread preview replacement: 17 samples, 0.947-4.990 ms, median 3.239 ms.
- Background ink serialization: 23 samples, 0.306-8.427 ms, median 1.342 ms.
- Main-thread persistence writeback: 32 samples, 0.005-2.274 ms, median 0.457 ms and p95 0.733 ms.
- Saved page drawing preparation remained on the background queue: 16 samples, 0.207-5.887 ms. The corresponding main-thread vector apply was 0.214-3.402 ms, with a 0.229 ms median; the 3.402 ms maximum was the initial 15-stroke chart open.
- Six resident vector transfers occurred when Free-Write became active. The first transfer per transition cost 11.193-14.004 ms, below one 60 Hz frame, and happened on tool entry rather than during Pencil contact. SwiftUI's immediately repeated configuration reused the already-installed drawing in 0.358-0.374 ms.
- Twenty-three full notation backing draws crossed the 8 ms diagnostic threshold, ranging from 8.189 to 21.484 ms. They were confined to orientation/layout or tool-transition redraw bursts; saved ink was composited in separate vector canvases and no Pencil callback crossed 4 ms during those bursts. This is a sparse notation-layout frame cost, not a remaining live-ink serialization or callback cost.

### Production telemetry and exact persistence

- Production Supabase received 57 aggregate-only events for session `14A7E8A8-AC61-41C0-94A0-38E230610DDB`: 14 ink persistence events, 17 chord preview updates, 2 preview renders, 14 editor mode changes, and 2 coordinate-space reprojections. The session is version/build `1.2.1 (51)` on `iPad13,2` / iPadOS `26.6.1`.
- Rhythm page ink grew from the 15-stroke baseline to 88 strokes, then the continuous erase returned it to 15. Simple Sheet grew from 1 to 103 strokes, then returned to 1. Production independently received the final Simple Sheet 16-stroke and 1-stroke saves after the process was terminated.
- The settled drawing snapshot exactly matches the pre-pass semantic baselines: Untitled Chart 1 stroke / 18 points / digest `afb156699a9b16c84fdeedac1fa6382c9c14dff31d35c9a14626368d3ce09e2f`; Nadie Como Tu 15 strokes / 350 points / digest `f357a785d574f773c83d3d9c4a631cf65bfc917c539929b28df2f6359a8701f2`; Higher Love 1 stroke / 6 points / digest `dd72eea3e18cf60aa6f02d55f4b6e018bec246a90dc8cd18ea9db1fa9eccd5fa`.
- The app was then terminated, cold-launched, and pulled again at `/tmp/ichart-ink-final-read-audit2-cold-reopen-20260908.NbfAhi/Library`. All three decoded drawings retained the same stroke counts, control-point counts, bounds, and semantic digests. PencilKit re-encoded only the one-stroke Simple Sheet archive by 22 metadata bytes; no visible stroke property or point changed.
- The exact physical gate therefore passes for live input, dense erasure, both chart styles, rotation-safe vector ink, and process-restart persistence. The user's final `done` marks completion of the workload; it was not a separate subjective rating, so the acceptance claim rests on the device trace and reload evidence rather than inferred sentiment.

No Edge Function deployment, commit, push, archive, upload, TestFlight delivery, App Store submission, or public release occurred in this pass.

## Standalone Roadmap Glyph Follow-Up: 2026-09-08 20:47 PT

The user compared the maximum-size standalone Coda on the physical iPad and reported that Finale Broadway was still much smaller than Petaluma. The running executable was the exact previously committed build, so this was a real renderer failure rather than stale-install evidence. The selected `Nadie Como Tú` model provided the exact reproduction: Rhythm Section Sheet, Finale Broadway, rehearsal-draft/compact engraving, and a standalone `codaMarker` at the maximum `1.8` scale.

### Root cause and correction

- The prior test stopped at the normalized CoreText outline. Those raw Coda paths were both approximately `26.8` points high, so it passed without invoking the label fitter and final draw.
- The actual renderer then wrapped that glyph in an attributed label. At the live Rhythm maximum size, Finale Broadway reported an approximately `160`-point line box around the `26.8`-point outline, while Petaluma reported approximately `44` points. Fitting those hidden font metrics into the same marker frame shrank Finale Broadway a second time.
- A new full-raster regression first failed all four Simple/Rhythm and minimum/maximum comparisons. Maximum-scale visible height was approximately `12` versus `39` points in Simple Sheet and `15.3` versus `27` points in Rhythm Section for Finale Broadway versus Petaluma.
- Standalone Coda and Segno now bypass the attributed-text fitter. The renderer draws each selected font's normalized vector outline directly, centered and bounded inside the unchanged marker frame. This path is shared by on-screen rendering and PDF export and does not alter marker positions, movement frames, or chart pagination.
- Mixed text/symbol labels such as To Coda and D.S. al Coda remain on their existing label path; they were not the reported standalone failure and still require their own physical font-comparison acceptance.

### Automated and device evidence

- `/tmp/ichart-coda-outline-focused-20260908.xcresult`: 156 selected, 156 passed, 0 failed, 0 skipped. This covers fully rasterized Coda and Segno at minimum and maximum size in Finale Broadway and Petaluma for both chart styles, plus the broader notation, layout, and PDF suites.
- `/tmp/ichart-coda-outline-full-20260908.xcresult`: 1,212 selected, 1,168 passed, 44 explicit environment/fixture skips, and 0 failures.
- Signed app: `/tmp/iChartDerived-device-coda-outline-20260908/Build/Products/Debug-iphoneos/iChart.app`; version/build `1.2.1 (51)`; arm64 UUID `BB704518-F4CE-32FC-B0FB-D0CB6834DB2A`; executable SHA-256 `251048af41c17f7ad58e3905df607d7deb8e71f4605146eb0732c1e1bb6e9681`.
- The first automatic signing operation stalled in SecurityAgent and was interrupted after compilation. Re-signing the disposable app with the approved Apple Development identity initially exposed Xcode's known self-referential missing-`iChart.cstemp` resource seal; a deep replacement signature removed that stale seal. `codesign --verify --deep --strict` then passed with team `N6G8X4K46U`.
- Installation completed at 20:46:32 PT to `/private/var/containers/Bundle/Application/45916D83-6293-4DF1-A403-A1E7E88C4C82/iChart.app`; foreground launch completed at 20:46:48 PT and the exact executable is running as PID `1373`.
- Preinstall Library snapshot: `/tmp/ichart-coda-outline-preinstall-20260908.HPFZ3L/Library`; postinstall/prelaunch: `/tmp/ichart-coda-outline-postinstall-prelaunch-20260908.HI4Q9h/Library`; postlaunch: `/tmp/ichart-coda-outline-postlaunch-20260908.cS4yoC/Library`. `library-state.json` remained byte-for-byte identical in all three at `516,388` bytes and SHA-256 `e654d81223507365ea62d32e1c8b3a9a8ea69abe087f96e7728aa6293f852190`.

Direct physical acceptance passed on executable UUID `BB704518-F4CE-32FC-B0FB-D0CB6834DB2A`: after comparing the existing maximum-size standalone Coda on the iPad, the user confirmed that the Finale Broadway/Petaluma size mismatch was fixed. Segno remains protected by the same vector-outline renderer and full-raster regression, but it was not separately named in the user's confirmation. No commit, push, archive, upload, TestFlight delivery, App Store submission, or public release occurred in this follow-up.

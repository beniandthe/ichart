# iChart Post-Capture Assembly: SM-002 Wedding Key Changes

Status: vJ SM-001-style lifted upload candidate exported; native app preview required
Date: 2026-07-18
Brief: `docs/marketing/social-media/brief-sm-002-wedding-gig-key-changes.md`
Demo material: `docs/marketing/social-media/demo-material-packet-002.md`
Recording script: `docs/marketing/social-media/recording-script-sm-002-wedding-key-changes.md`
Publish packet: `docs/marketing/social-media/publish-packet-sm-002-wedding-key-changes.md`

## Capture Summary

Four AirDropped portrait iPad screen recordings were imported from Downloads and sorted by adjusted/modified time from earliest to latest.

Raw clips:

1. `assets/sm-002-wedding-key-changes/raw/sm-002-clip-01-095440.mp4`
   - Source: `ScreenRecording_07-18-2026 09-54-40_1.MP4`
   - Duration: 21.07s
   - Format: portrait iPad capture, `1640x2360`
   - User note: go from Charts to Projects tab; Wedding Set is empty; add `First Dance in C` and `Last Dance in C`; open both to show contents.
   - Contact-sheet note: frame review shows the captured list includes `Last Dance in F` and `First Dance in C`; use the visual footage as the source of truth for editing.

2. `assets/sm-002-wedding-key-changes/raw/sm-002-clip-02-095841.mp4`
   - Source: `ScreenRecording_07-18-2026 09-58-41_1.MP4`
   - Duration: 17.67s
   - Format: portrait iPad capture, `1640x2360`
   - User note: in Charts, duplicate `First Dance in C`; rename copy as `First Dance in F`.

3. `assets/sm-002-wedding-key-changes/raw/sm-002-clip-03-100035.mp4`
   - Source: `ScreenRecording_07-18-2026 10-00-35_1.MP4`
   - Duration: 24.63s
   - Format: portrait iPad capture, `1640x2360`
   - User note: still in Charts, enter duplicate `First Dance`; transpose up P4 to F; fix the in-chart title to say `First Dance in F`.

4. `assets/sm-002-wedding-key-changes/raw/sm-002-clip-04-100235.mp4`
   - Source: `ScreenRecording_07-18-2026 10-02-35_1.MP4`
   - Duration: 16.88s
   - Format: portrait iPad capture, `1640x2360`
   - User note: navigate to Projects; remove old `First Dance` chart; add new `First Dance` chart; open the new chart to show the new key.

Review contact sheet:

- `assets/sm-002-wedding-key-changes/review/sm-002-raw-contact-sheet-01.png`

## Working Story

The footage changes the pre-capture plan from C to Eb into C to F:

- Project: `Wedding Set`
- Original chart: `First Dance in C`
- Duplicate/chart version: `First Dance in F`
- Transposition: up P4
- Payoff: the project contains the updated F chart and it opens in the new key.

## First Assembly Plan

Use a vertical-native 9:16 master with the same restrained SM-001 visual language:

- solid iChart dark-blue background,
- full app capture fit inside the frame,
- logo-C blue border around the iPad capture,
- top iPad status strip cropped out,
- concise workflow labels,
- no final publishing polish until the rough order is approved.

Proposed sequence:

| Beat | Source | Purpose | Draft Overlay |
| --- | --- | --- | --- |
| 1 | Clip 01 | Establish Wedding Set project and chart context. | `Wedding set, new keys` |
| 2 | Clip 02 | Duplicate `First Dance in C` and rename it. | `Duplicate the chart` |
| 3 | Clip 03 | Open duplicate and transpose up P4. | `Transpose to F` |
| 4 | Clip 03 | Correct chart title to `First Dance in F`. | `Keep the chart version clear` |
| 5 | Clip 04 | Replace old project chart and open the updated F chart. | `Ready for the gig` |

## vA Raw Assembly

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vA-raw-assembly-01.mp4`
- Duration: 77.20s
- Format: 9:16 MP4, `1080x1920`, H.264 video-only
- Visual treatment: solid iChart dark-blue background, full portrait app capture fit in frame, top iPad status strip cropped out, logo-C blue border, concise workflow labels, and progress rail.
- Source order: clips 01-04 by adjusted/modified timestamp.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vA-raw-assembly-frame-sheet.png`
- Export script: `assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift`

## vB Top-Header Rough

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vB-top-headers-01.mp4`
- Duration: 77.20s
- Format: 9:16 MP4, `1080x1920`, H.264 video-only
- Visual treatment: same as vA, but the workflow labels are moved into the top dark-blue header area so future script/VO captions can live in the lower caption area.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vB-top-headers-frame-sheet.png`
- Export script: `assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --top-headers`

## vC Script-Caption Draft

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vC-script-captions-01.mp4`
- Duration: 77.20s
- Format: 9:16 MP4, `1080x1920`, H.264 video-only
- Visual treatment: vB top headers plus lower script-caption boxes.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vC-script-captions-frame-sheet.png`
- Export script: `assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --script-captions`
- Status note: superseded for now by the human VO path; keep it as a reference for later caption layout.

## Human Voiceover

- Script file: `assets/sm-002-wedding-key-changes/voiceover/sm-002-human-vo-script.md`
- Full raw recording: `assets/sm-002-wedding-key-changes/voiceover/takes/sm-002-human-vo-take-01.m4a`
- Selected final pass: `assets/sm-002-wedding-key-changes/voiceover/takes/sm-002-human-vo-take-01-final-pass-raw.m4a`
- Selected range: `51.85s` to `100.85s` from the full raw recording, based on the large pause before the last take.
- Mastered VO: `assets/sm-002-wedding-key-changes/voiceover/final/sm-002-human-vo-take-01-VO-MASTER-01.m4a`
- Mastering notes: 80 Hz high-pass, 30 ms fade-in/out, peak normalization to `-1.5 dBFS`; no aggressive gate or compression.
- Master analysis: `assets/sm-002-wedding-key-changes/review/sm-002-vo-master-01-analysis.txt`
- Audio QA: `49.00s`, optimized mono AAC, first active speech at about `0.475s`, trailing room about `0.55s`.
- Master script: `assets/sm-002-wedding-key-changes/scripts/master_sm002_voiceover.swift`
- Noise-reduced VO: `assets/sm-002-wedding-key-changes/voiceover/final/sm-002-human-vo-take-01-VO-MASTER-02-noise-reduced.m4a`
- Noise-reduced mastering notes: same high-pass/fade/peak target as master 01, plus soft downward expansion for low-level room noise.
- Noise-reduced analysis: `assets/sm-002-wedding-key-changes/review/sm-002-vo-master-02-noise-reduced-analysis.txt`

## vD Human-VO Rough

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vD-human-vo-01.mp4`
- Duration: `49.00s`
- Format: 9:16 MP4, `1080x1920`, H.264 + mono AAC human VO
- Visual treatment: same solid dark-blue field and logo-C blue app border as vB, with tighter source trims to fit the 49-second narration.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vD-human-vo-frame-sheet.png`
- Export script: `assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --human-vo`
- Frame export script: `assets/sm-002-wedding-key-changes/scripts/export_sm002_review_frames.swift`
- Frame export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_review_frames.swift`
- Status note: superseded by vE because clip 03 started after the visible transpose action.

## vE Transpose-Proof Rough

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vE-transpose-proof-01.mp4`
- Duration: `49.00s`
- Format: 9:16 MP4, `1080x1920`, H.264 + mono AAC human VO
- Change from vD: clip 03 now starts at source `3.00s` instead of `8.20s`, preserving the C chart, transpose menu, P4/key-change action, F-chord result, and title fix.
- Visual treatment: same solid dark-blue field, logo-C blue app border, and top workflow headers.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vE-transpose-proof-frame-sheet.png`
- Export script: `assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --human-vo-vE`
- Frame export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_review_frames.swift --vE`
- Status note: superseded by vF for bottom spoken captions and noise-reduced VO.

## vF Captioned / Noise-Reduced Rough

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vF-captioned-noise-reduced-01.mp4`
- Publish edition: `assets/sm-002-wedding-key-changes/editions/sm-002-vertical-edition-vF-captioned-noise-reduced-01.mp4`
- Duration: `49.00s`
- Format: 9:16 MP4, `1080x1920`, H.264 + mono AAC human VO
- Change from vE: keeps the restored transpose-proof clip timing, swaps in `VO-MASTER-02-noise-reduced`, and adds progressive spoken captions in the lower caption area.
- Caption style: pre-rendered transparent word layers with phrase-level timing and word-by-word reveal.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vF-captioned-noise-reduced-frame-sheet.png`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --captioned-vo-vF`
- Frame export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_review_frames.swift --vF`

## vG Platform-Safe Candidate

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vG-platform-safe-01.mp4`
- Publish edition: `assets/sm-002-wedding-key-changes/editions/sm-002-vertical-edition-vG-platform-safe-01.mp4`
- Duration: `49.00s`
- Format: 9:16 MP4, `1080x1920`, H.264 + mono AAC human VO
- Change from vF: preserves the same edit, VO, corrected transpose-proof timing, and word-reveal captions, but shrinks/shifts the app capture away from right-side platform controls and lifts spoken captions above common TikTok/Reels bottom UI.
- Local platform preview result: vG clears the modeled top/right/bottom UI danger zones for TikTok and Instagram Reels.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vG-platform-safe-frame-sheet.png`
- TikTok overlay sheet: `assets/sm-002-wedding-key-changes/review/sm-002-vG-platform-preview-tiktok-frame-sheet.png`
- Instagram Reels overlay sheet: `assets/sm-002-wedding-key-changes/review/sm-002-vG-platform-preview-instagram-reels-frame-sheet.png`
- Platform preview report: `assets/sm-002-wedding-key-changes/review/sm-002-vG-platform-preview-report.md`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --platform-safe-vG`
- Frame export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_review_frames.swift --vG`
- Platform preview command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_platform_previews.swift --vG`

## vH No-Header Platform-Safe Candidate

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vH-platform-safe-no-headers-01.mp4`
- Publish edition: `assets/sm-002-wedding-key-changes/editions/sm-002-vertical-edition-vH-platform-safe-no-headers-01.mp4`
- Duration: `49.00s`
- Format: 9:16 MP4, `1080x1920`, H.264 + mono AAC human VO
- Change from vG: removes the top workflow header pop-up cards while preserving the same platform-safe app/caption layout, VO, corrected transpose-proof timing, and word-reveal captions.
- Local platform preview result: vH clears the modeled top/right/bottom UI danger zones for TikTok and Instagram Reels.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vH-platform-safe-no-headers-frame-sheet.png`
- TikTok overlay sheet: `assets/sm-002-wedding-key-changes/review/sm-002-vH-platform-preview-tiktok-frame-sheet.png`
- Instagram Reels overlay sheet: `assets/sm-002-wedding-key-changes/review/sm-002-vH-platform-preview-instagram-reels-frame-sheet.png`
- Platform preview report: `assets/sm-002-wedding-key-changes/review/sm-002-vH-platform-preview-report.md`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --platform-safe-no-headers-vH`
- Frame export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_review_frames.swift --vH`
- Platform preview command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_platform_previews.swift --vH`

## vI SM-001-Style Full-Size Candidate

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vI-sm001-style-outro-01.mp4`
- Publish edition: `assets/sm-002-wedding-key-changes/editions/sm-002-vertical-edition-vI-sm001-style-outro-01.mp4`
- Duration: `49.00s`
- Format: 9:16 MP4, `1080x1920`, H.264 + mono AAC human VO
- Change from vH: follows the approved SM-001 vertical script treatment by removing workflow header pop-up cards, placing the progressive spoken captions below the app, keeping the solid dark-blue background and logo-C blue border, and adding the same soft fade blend into the iChart logo/details end card.
- QA note: rough and edition SHA-256 hashes match.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vI-sm001-style-outro-frame-sheet.png`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --sm001-style-vI`
- Frame export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_review_frames.swift --vI`
- Cover export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_publish_assets.swift --vI`
- Platform preview result: vI keeps the strongest app scale, but modeled TikTok/Reels overlays crowd the lower captions, progress rail, and right edge.
- Publishing note: keep vI as the full-size visual reference only; use vJ as the current upload candidate.

## vJ SM-001-Style Lifted Upload Candidate

- `assets/sm-002-wedding-key-changes/rough-cuts/sm-002-wedding-key-changes-vJ-sm001-style-lifted-01.mp4`
- Publish edition: `assets/sm-002-wedding-key-changes/editions/sm-002-vertical-edition-vJ-sm001-style-lifted-01.mp4`
- Duration: `49.00s`
- Format: 9:16 MP4, `1080x1920`, H.264 + mono AAC human VO
- Change from vI: keeps the no-header SM-001-style word captions and logo/details outro, but lifts and tightens the app/caption stack so the captions sit below the app while clearing modeled bottom platform UI.
- QA note: rough and edition SHA-256 hashes match.
- Platform preview result: TikTok clears modeled top/right/bottom zones. Instagram clears modeled bottom/right zones for the spoken captions and progress rail, while the top app chrome remains in the modeled top zone.
- Review frames: `assets/sm-002-wedding-key-changes/review/sm-002-vJ-sm001-style-lifted-frame-sheet.png`
- TikTok overlay sheet: `assets/sm-002-wedding-key-changes/review/sm-002-vJ-platform-preview-tiktok-frame-sheet.png`
- Instagram Reels overlay sheet: `assets/sm-002-wedding-key-changes/review/sm-002-vJ-platform-preview-instagram-reels-frame-sheet.png`
- Platform preview report: `assets/sm-002-wedding-key-changes/review/sm-002-vJ-platform-preview-report.md`
- Export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/make_sm002_vA_raw_assembly.swift --sm001-lifted-vJ`
- Frame export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_review_frames.swift --vJ`
- Platform preview command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_platform_previews.swift --vJ`
- Cover export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_publish_assets.swift --vJ`
- Publishing note: use vJ as the current upload candidate. Keep vH only as the strict platform-safe fallback if native Instagram top UI makes the lifted app feel crowded.

## Publish Assets

- Cover export script: `assets/sm-002-wedding-key-changes/scripts/export_sm002_publish_assets.swift`
- Cover export command: `swift docs/marketing/social-media/assets/sm-002-wedding-key-changes/scripts/export_sm002_publish_assets.swift --vJ`
- Recommended TikTok cover: `assets/sm-002-wedding-key-changes/publish/sm-002-cover-vJ-transpose-menu-26s.png`
- Recommended Instagram Reel cover: `assets/sm-002-wedding-key-changes/publish/sm-002-cover-vJ-final-chart-45s.png`
- Alternate context cover: `assets/sm-002-wedding-key-changes/publish/sm-002-cover-vJ-project-updated-43s.png`
- Prior vF/vG/vH/vI cover exports remain in `assets/sm-002-wedding-key-changes/publish/` for reference.

## Draft Voiceover Direction

This can use a tighter, more practical VO than SM-001:

> Wedding gigs move fast. You learn the songs, and then the singer changes the key.
>
> In iChart, duplicate the clean chart, transpose it to the new key, rename the version, and keep it inside the project.
>
> Now the updated chart is ready to send, save, or edit for the next gig.

## QA Before Polishing

- [x] Raw clips imported.
- [x] Clip order sorted by adjusted/modified time.
- [x] Contact sheet exported.
- [x] Export vA raw assembly.
- [x] Export vB top-header rough.
- [x] Export vC script-caption draft.
- [x] Record human VO source take.
- [x] Trim final pass after the large pause before the last take.
- [x] Export mastered VO.
- [x] Export vD human-VO rough.
- [x] Export vE correction with visible transpose action restored.
- [x] Export noise-reduced VO master.
- [x] Export vF with bottom progressive spoken captions.
- [x] Copy vF to `editions/` as the current publish candidate.
- [x] Export SM-002 cover candidates.
- [x] Build TikTok/Reels publish packet after the rough is approved.
- [x] Export vG platform-safe candidate.
- [x] Copy vG to `editions/` as the previous platform-safe candidate.
- [x] Export conservative local TikTok/Reels overlay previews.
- [x] Export vH no-header platform-safe candidate.
- [x] Copy vH to `editions/` as the strict platform-safe fallback.
- [x] Export vH header-free cover candidates.
- [x] Export vI SM-001-style candidate.
- [x] Copy vI to `editions/` as the full-size visual reference.
- [x] Export vI cover candidates.
- [x] Export vI conservative platform preview.
- [x] Export vJ SM-001-style lifted candidate.
- [x] Copy vJ to `editions/` as the current upload candidate.
- [x] Export vJ cover candidates.
- [x] Export vJ conservative platform preview.
- [ ] Confirm the clip order and timing in real time.
- [ ] Confirm the C-to-F story is clear without requiring detailed chord-reading.
- [ ] Preview vJ in TikTok with platform UI visible.
- [ ] Preview vJ in Instagram Reels with platform UI visible.

## Claim Guardrails

- Say `transpose`, `duplicate`, `chart version`, and `export/share`.
- Do not say iChart imports from another chord-chart app.
- Do not imply playback, auto chart generation, full arrangements, horn parts, or cleanup of messy paper charts.

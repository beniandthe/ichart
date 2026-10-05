# Isolated digital-ink engine probe

Developer-only comparison of a fixed pretrained handwriting engine on authorized
local trajectories. It is **not linked to iChart or RecognitionStudy**, does not
read either app's container, and is not a production dependency or release gate.
The app has its own bundle identifier, `com.ichart.development.digitalinkprobe`.

## Scope and privacy

- Pinned `GoogleMLKit/DigitalInkRecognition` 8.0.0 (component 7.0.0); English
  `en-US` model. The SDK downloads its model when absent and then recognizes on
  the device. It may send API usage/performance metrics to Google. Adding it to
  a shipped product requires a separate dependency/privacy/release decision.
- Official [iOS instructions](https://developers.google.com/ml-kit/vision/digital-ink-recognition/ios)
  and [privacy documentation](https://developers.google.com/ml-kit/terms).
  Google states that recognition input and output are not sent to its servers.
- No personal profile, expected chord, preceding text, corrected answer, or
  custom vocabulary is supplied. Private inputs/reports stay outside Git.
- Primary output uses no recognition context. A separately reported secondary
  pass uses the unpadded ink bounds as the writing area. Both configurations
  are fixed before inspecting predictions; do not choose one per expected chord.
- The adapter preserves every source stroke/point and its order, translates the
  spatial/time origins, and converts to the SDK's Float coordinates/integer-ms
  timestamps. Missing time stays missing. No resampling, stretching, or guessed
  character segmentation. This conversion is not bitwise coordinate equality.
- Report all raw candidates in their original ranking. No grammar rescue,
  automatic rendering, personal learning, or calibrated trust is implemented.
  A passing harness proves execution/integrity, not recognition accuracy.

## Run

Use XcodeGen and CocoaPods in **this subdirectory**, not the main iChart project.
The generated workspace is required for this isolated CocoaPods harness; the
main app continues using its existing explicit `.xcodeproj` workflow. Never
modify the generated projects by hand.

1. `xcodegen generate` then `pod install --deployment`.
2. Build the app with `xcodebuild -workspace DigitalInkProbe.xcworkspace
   -scheme DigitalInkProbe -destination 'id=<physical-device-UDID>'
   -derivedDataPath <dedicated-output> build
   CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic
   DEVELOPMENT_TEAM=<development-team> -allowProvisioningUpdates`.
   Approve any signing prompt yourself. Do not pass credentials in commands.
3. Verify the resulting app's signature, install that separate app on the paired
   device, and copy an authorized packet to its `Documents/probe-input.json`.
   Installation does not provide recognition results.
4. Launch only `com.ichart.development.digitalinkprobe` using `devicectl device
   process launch`, passing `--run-ink-probe`. The app validates the packet,
   downloads its fixed model if needed, then runs both configurations. Leave
   the device unlocked and this app foreground during the comparison.
5. Pull this app's `Documents/probe-report.json`. Require `complete: true`, an
   identical source packet SHA-256, the exact input ID set, and exactly one row
   per ID per fixed context. Missing, failed, or partial reports are not passes.
   Join labels to its IDs **after** inference for offline scoring.
   Keep no-reads, wrong top-1, top-N recall and baseline performance separate.
6. Return the device to iChart. Do not read, teach, relabel, or change its data
   as part of this isolated engine comparison.

This app-only run is **not an XCTest result**. The optional `ProbeTests` target
was compiled; its physical test runner encountered a framework-copy/signing
failure and was canceled before execution. No passing XCTest claim is made
for that target. The standalone app avoids embedding those test frameworks.

The pinned SDK excludes arm64 Simulator. On the current Apple Silicon/iOS 26.5
environment only a physical-device destination is available for this harness.
Do not treat an unavailable Simulator or signing failure as recognition failure.

## Private packet format

An array of distinct opaque IDs with original stroke geometry:

```json
[{"id":"sample-0","strokes":[{"creationTimeOffset":0,
  "points":[{"x":10,"y":20,"timeOffset":0},
            {"x":20,"y":30,"timeOffset":0.1}]}]}]
```

`creationTimeOffset` is seconds relative to a shared drawing origin;
`timeOffset` is seconds relative to each stroke's creation. Both are optional.
At most 128 inputs, 64 strokes and 32,768 points per input, 8 MB packet. Expected
labels are not part of this schema. The current harness has no capture UI;
fresh human trials still require the app's normal, separately verified flow.

Physical inference results and scope limits belong in the dated evaluation log.

## Offline scoring

Run `python3 -m unittest -v test_score_probe` in this directory for the pure
offline integrity/scoring checks. Then run `python3 score_probe.py
<private-packet> <private-report> <private-labels>` and redirect stdout to a
private output path outside the repository.

Labels are a separate array containing `id`, `intended`, and optional `cohort`,
`style`, `native`, `personalized`, and evidence identity fields. Establish their
join using the exact captured trajectories and recorded sample identities,
never by choosing whichever output resembles the answer. The scorer refuses
incomplete reports, wrong source hashes, duplicate IDs/results, missing fixed
contexts, and invalid/empty label sets. Unlabeled inputs remain unscored.

Raw exact top-1 and notation-equivalent top-1/top-5/full-list recall are distinct.
Equivalence covers whitespace, letter case at the root, printed accidental and
triangle variants, and `maj`/`M`/`min`/`m` chord-quality spellings. It does **not**
invent missing sevenths, replace roots or accidentals, reinterpret letters as
triangles, turn apostrophes into digits, or select the expected lower-ranked
candidate as the prediction. Missing baseline fields report unknown, not zero.
These scoring rules are not part of a recognition or acceptance pipeline.

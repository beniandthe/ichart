#if canImport(UIKit)
import XCTest
import CryptoKit
@testable import iChart

/// Exact captured-input replay, not a fresh-handwriting accuracy benchmark.
/// Neither expected chord labels nor user corrections are inputs to this check.
final class PersonalInkEditTraceReplayTests: XCTestCase {
    func testProvidedEditTraceSeparatesRecognitionEvidenceFromReviewGate() throws {
        let env = ProcessInfo.processInfo.environment
        guard let tracePath = env["ICHART_PERSONAL_EDIT_TRACE"],
              let profilePath = env["ICHART_PERSONAL_EDIT_PROFILE"],
              let pipeline = env["ICHART_PERSONAL_EDIT_SOURCE_PIPELINE"],
              let expectedChangeText = env["ICHART_PERSONAL_EDIT_EXPECTED_CHANGES"],
              let expectedChanges = Int(expectedChangeText) else {
            throw XCTSkip("Provide an authorized captured trace, frozen profile, source pipeline, and expected change count")
        }
        let traceURL = URL(fileURLWithPath: tracePath).resolvingSymlinksInPath()
        let profileURL = URL(fileURLWithPath: profilePath).resolvingSymlinksInPath()
        let traceData = try Data(contentsOf: traceURL), profileData = try Data(contentsOf: profileURL)
        let profile = try JSONDecoder().decode(PersonalInkProfile.self, from: profileData)
        let snapshot = PersonalInkSnapshot(profile: profile)
        let events = try ChordDraftPreviewDeviceDiagnosticRecorder(url: traceURL).loadEvents()
            .filter { $0.recognitionPipelineVersion == pipeline }
        // Match LeadSheetCanvasHostView's complete route, including semantic
        // conflicts and robustness probes, not its inner candidate recognizer.
        let recognizer = ChordInkMaximumTrustRecognizer()
        var rows: [[String: Any]] = []
        var changed = 0, edited = 0, passCount = 0
        var styles = Set<String>()
        for (index, event) in events.enumerated() where ["finish_batch", "finish_single"].contains(event.stage) {
            passCount += 1
            let style = try XCTUnwrap(event.layoutStyle)
            styles.insert(style)
            let next = events.dropFirst(index + 1).prefix { !["reset", "finish_batch", "finish_single"].contains($0.stage) }
            let replacement = try XCTUnwrap(next.first { $0.stage == "preview_replace" })
            XCTAssertEqual(replacement.replacements.count, event.payloads.count)
            for payload in event.payloads {
                let input = try XCTUnwrap(payload.inkStrokes)
                XCTAssertFalse(input.isEmpty)
                var native = recognizer.recognize(strokes: input)
                let evidence = ChordInkRecognitionPolicy.decision(for: native)
                XCTAssertEqual(native.match?.displayText, payload.matchText, "Native recognition must reproduce before comparing arbitration")
                XCTAssertEqual(native.trustEvidence?.outcome, payload.trustEvidence?.outcome)
                native.requiresEditReview = payload.requiresEditReview ?? false
                let gated = ChordInkRecognitionPolicy.decision(for: native)
                XCTAssertEqual(gated.action.rawValue, payload.action)
                XCTAssertEqual(gated.acceptedText, payload.acceptedText)
                let adapted = snapshot.applying(to: native, strokes: input)
                // Reproduce the old handoff using the old gated trust input.
                // select itself is unchanged; the v27 change supplies native
                // evidence separately while preserving the final review gate.
                let old = PersonalInkArbitrationPolicy.select(
                    baselineText: native.match?.displayText ?? ChordInkRenderResolutionPolicy.candidateTexts(for: native).first,
                    baselineTrusted: gated.action == .trusted, suggestion: adapted.personalSuggestion)
                let observed = try XCTUnwrap(replacement.replacements.first { $0.draftIndex == payload.targetIndex })
                XCTAssertEqual(old.text, observed.newPreviewText, "Frozen profile must reproduce the recorded default")
                let candidate = ChordInkRenderResolutionPolicy.resolution(
                    for: adapted, drawingData: Data(), correctionMemory: .init())
                let shouldProtect = native.requiresEditReview && evidence.action == .trusted && old.prefersPersonal
                if native.requiresEditReview {
                    edited += 1
                    XCTAssertEqual(candidate.decision.action, .confirm)
                }
                if shouldProtect {
                    changed += 1
                    XCTAssertEqual(candidate.decision.acceptedText, native.match?.displayText)
                    XCTAssertNotEqual(candidate.decision.acceptedText, old.text)
                } else {
                    XCTAssertEqual(candidate.decision.acceptedText, old.text)
                }
                rows.append(["style": style, "pass": passCount, "targetIndex": payload.targetIndex,
                    "edited": native.requiresEditReview, "native": native.match?.displayText ?? "no-read",
                    "recognitionEvidenceAction": evidence.action.rawValue, "capturedAction": gated.action.rawValue,
                    "capturedPreview": observed.newPreviewText ?? "no-read",
                    "candidatePreview": candidate.decision.acceptedText ?? "no-read",
                    "candidateAction": candidate.decision.action.rawValue, "changed": shouldProtect])
            }
        }
        XCTAssertGreaterThan(passCount, 0)
        XCTAssertGreaterThan(edited, 0)
        XCTAssertEqual(styles, ["simpleChordSheet", "rhythmSectionSheet"])
        XCTAssertEqual(changed, expectedChanges)
        guard testRun?.failureCount == 0 else { return }
        let report: [String: Any] = [
            "scope": "exact captured-input iOS replay; no labels, learning, or new-writer accuracy claim",
            "sourcePipeline": pipeline, "candidatePipeline": ChordInkRecognitionPipelineIdentity.version,
            "traceSHA256": SHA256.hash(data: traceData).map { String(format: "%02x", $0) }.joined(),
            "profileRevision": profile.revision.uuidString, "profileExamples": profile.examples.count,
            "passes": passCount, "targets": rows.count, "editedTargets": edited, "changedDefaults": changed, "rows": rows
        ]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        if let reportPath = env["ICHART_PERSONAL_EDIT_REPORT"] {
            let outputURL = URL(fileURLWithPath: reportPath).resolvingSymlinksInPath()
            guard outputURL != traceURL, outputURL != profileURL else {
                XCTFail("Report must not overwrite captured evidence"); return
            }
            try encoded.write(to: outputURL, options: .atomic)
        }
        XCTAssertEqual(try Data(contentsOf: traceURL), traceData)
        XCTAssertEqual(try Data(contentsOf: profileURL), profileData)
        print("PERSONAL_EDIT_REPLAY\n\(String(decoding: encoded, as: UTF8.self))")
    }
}
#endif

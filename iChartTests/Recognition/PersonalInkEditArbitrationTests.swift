import XCTest
@testable import iChart

final class PersonalInkEditArbitrationTests: XCTestCase {
    func testEveryConflictingPersonalExampleRemainsSelectableWithoutChangingTheNativeDefault() throws {
        let labels = try comparisonLabels()
        for baseline in labels {
            for personal in labels where personal != baseline {
                for provenance in [PersonalInkExampleSource.setup, .confirmedReview, .explicitCorrection] {
                    for trusted in [false, true] {
                        for edited in [false, true] {
                            var result = native(baseline, confidence: trusted ? 4.8 : 3.8)
                            result.requiresEditReview = edited
                            result.personalSuggestion = .init(text: personal, source: .wholeChord,
                                distance: 0, supportingExampleCount: 5,
                                correctionSupportCount: provenance == .explicitCorrection ? 5 : 0)
                            let original = result
                            XCTAssertEqual(ChordInkRecognitionPolicy.recognitionEvidenceDecision(for: result).action,
                                trusted ? .trusted : .confirm)
                            let selection = ChordInkRenderResolutionPolicy.personalSelection(for: result)
                            XCTAssertEqual(selection.text, baseline)
                            XCTAssertFalse(selection.prefersPersonal)
                            XCTAssertEqual(selection.disposition, trusted ? .protectedBaseline : .alternative)
                            let resolution = ChordInkRenderResolutionPolicy.resolution(
                                for: result, drawingData: Data(), correctionMemory: .init())
                            XCTAssertEqual(resolution.decision.acceptedText, baseline)
                            XCTAssertEqual(resolution.decision.action, trusted && !edited ? .trusted : .confirm)
                            if trusted && edited { XCTAssertTrue(resolution.decision.reason.contains("edited")) }
                            XCTAssertEqual(resolution.candidateTexts.first, baseline)
                            XCTAssertTrue(resolution.candidateTexts.contains(personal))
                            XCTAssertEqual(result, original, "Arbitration must preserve the native evidence and edit-review flag")
                        }
                    }
                }
            }
        }
    }

    func testEditReviewKeepsExplicitCorrectionAsAnAlternativeToUncertainNativeEvidence() {
        var result = native("C", confidence: 3.8)
        result.personalSuggestion = .init(text: "G", source: .wholeChord,
                                          distance: 0.01, correctionSupportCount: 1)
        for edited in [false, true] {
            result.requiresEditReview = edited
            let selection = ChordInkRenderResolutionPolicy.personalSelection(for: result)
            XCTAssertEqual(selection.text, "C")
            XCTAssertEqual(selection.disposition, .alternative)
            let resolution = ChordInkRenderResolutionPolicy.resolution(
                for: result, drawingData: Data(), correctionMemory: .init())
            XCTAssertEqual(resolution.decision.action, .confirm)
            XCTAssertEqual(resolution.decision.acceptedText, "C")
            XCTAssertEqual(resolution.candidateTexts, ["C", "G"])
        }
    }

    func testNoReadPersonalRecoveryRequiresReviewWithAndWithoutAnEdit() {
        for source in [ChordInkPersonalSuggestion.Source.wholeChord, .symbols] {
            for provenance in [PersonalInkExampleSource.setup, .confirmedReview, .explicitCorrection] {
                for edited in [false, true] {
                    var result = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
                    result.requiresEditReview = edited
                    result.personalSuggestion = .init(text: "G", source: source, distance: 0.01,
                        correctionSupportCount: provenance == .explicitCorrection ? 1 : 0)
                    let original = result
                    XCTAssertEqual(ChordInkRenderResolutionPolicy.personalSelection(for: result).disposition, .personalRecovery)
                    let resolution = ChordInkRenderResolutionPolicy.resolution(
                        for: result, drawingData: Data(), correctionMemory: .init())
                    XCTAssertEqual(resolution.decision.action, .confirm)
                    XCTAssertEqual(resolution.decision.acceptedText, "G")
                    XCTAssertEqual(resolution.candidateTexts.first, "G")
                    XCTAssertEqual(result, original)
                }
            }
        }
    }

    func testAgreementPreservesNativeTrustAndTheSeparateEditReviewGate() throws {
        for label in try comparisonLabels() {
            for source in [ChordInkPersonalSuggestion.Source.wholeChord, .symbols] {
                for provenance in [PersonalInkExampleSource.setup, .confirmedReview, .explicitCorrection] {
                    for trusted in [false, true] {
                        for edited in [false, true] {
                            var result = native(label, confidence: trusted ? 4.8 : 3.8)
                            result.requiresEditReview = edited
                            result.personalSuggestion = .init(text: label, source: source, distance: 0,
                                correctionSupportCount: provenance == .explicitCorrection ? 1 : 0)
                            let original = result
                            let selection = ChordInkRenderResolutionPolicy.personalSelection(for: result)
                            XCTAssertEqual(selection.disposition, .agreement)
                            XCTAssertFalse(selection.prefersPersonal)
                            let resolution = ChordInkRenderResolutionPolicy.resolution(
                                for: result, drawingData: Data(), correctionMemory: .init())
                            XCTAssertEqual(resolution.decision.acceptedText, label)
                            XCTAssertEqual(resolution.decision.action, trusted && !edited ? .trusted : .confirm)
                            XCTAssertEqual(result, original)
                        }
                    }
                }
            }
        }
    }

    private func native(_ text: String, confidence: Double) -> ChordInkRecognitionResult {
        .init(rawCandidates: [text], glyphCandidates: [], match: ChordRecognitionCompendium.match(text),
              confidence: confidence, candidateScores: [.init(text: text, displayText: text, confidence: confidence)])
    }

    private func comparisonLabels() throws -> [String] {
        let rootQualities = ["A", "B", "C", "D", "E", "F", "G"].flatMap { root in
            ["", "7", "m7", "maj7"].map { root + $0 }
        }
        return try (rootQualities + ["F#7", "Bb7", "Ebmaj7", "G/B", "F#m7/C#", "Bbmaj7/F"])
            .map { try XCTUnwrap(ChordRecognitionCompendium.match($0)?.displayText) }
    }
}

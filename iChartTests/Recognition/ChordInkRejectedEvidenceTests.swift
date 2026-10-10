import XCTest
@testable import iChart

final class ChordInkRejectedEvidenceTests: XCTestCase {
    private func candidate(_ text: String, _ confidence: Double) -> ChordInkCandidate {
        .init(text: text, confidence: confidence, glyphCandidates: [])
    }

    func testInvalidCompleteStringsLeaveOnlyRejectionEvidence() {
        let evidence = ChordInkRecognizer.scoredCandidateEvidence(
            from: [candidate("ñ", 5), candidate("J", 4.9), candidate("1", 4.8),
                   candidate("C7", 4.6), candidate("C13", 4.5)],
            minimumConfidence: 3.7, match: ChordRecognitionCompendium.match
        )
        XCTAssertEqual(evidence.scores.map(\.text), ["C7", "C13"])
        XCTAssertEqual(evidence.scores.map(\.displayText), ["C7", "C13"])
        XCTAssertEqual(evidence.scores.map(\.confidence), [4.6, 4.5])
        XCTAssertEqual(evidence.rejectedCandidateConfidence, 5)
    }

    func testRejectionPreservesOriginalWindowThresholdAndFirstDuplicate() {
        let candidates = [candidate("1", 3.8), candidate("1", 9),
                          candidate("J", 3.2), candidate("C", 4.3),
                          candidate("D", 4.2), candidate("E", 4.1),
                          candidate("F", 4), candidate("G", 3.9),
                          candidate("ñ", 10), candidate("C13", 3.8)]
        let evidence = ChordInkRecognizer.scoredCandidateEvidence(
            from: candidates, minimumConfidence: 3.7, match: ChordRecognitionCompendium.match
        )
        XCTAssertEqual(evidence.rejectedCandidateConfidence, 3.8)
        XCTAssertEqual(evidence.scores.map(\.text), ["C", "D", "E", "F", "G", "C13"])
        XCTAssertEqual(evidence.scores.map(\.confidence), [4.3, 4.2, 4.1, 4, 3.9, 3.8])
    }

    func testNumericRejectionRetainsTrustDecisionWithoutInvalidCandidateText() throws {
        let match = try XCTUnwrap(ChordRecognitionCompendium.match("C7"))
        let supported = ChordInkCandidateScore(text: "C7", displayText: "C7", confidence: 4.6)
        var trustedCount = 0
        var confirmedCount = 0
        for rejected in [3.6, 4.0, 4.4, 4.6, 5.0] {
            let legacy = ChordInkRecognitionResult(
                rawCandidates: [], glyphCandidates: [], match: match, confidence: 4.6,
                candidateScores: [.init(text: "1", displayText: nil, confidence: rejected), supported]
            )
            let separated = ChordInkRecognitionResult(
                rawCandidates: [], glyphCandidates: [], match: match, confidence: 4.6,
                candidateScores: [supported], rejectedCandidateConfidence: rejected
            )
            let before = ChordInkRecognitionPolicy.decision(for: legacy)
            let after = ChordInkRecognitionPolicy.decision(for: separated)
            XCTAssertEqual(after, before)
            XCTAssertEqual(after.acceptedText, "C7")
            if after.action == .trusted { trustedCount += 1 }
            if after.action == .confirm { confirmedCount += 1 }
        }
        XCTAssertGreaterThan(trustedCount, 0)
        XCTAssertGreaterThan(confirmedCount, 0)
    }

    func testRejectedOnlyEvidenceCannotBecomeAMatchOrSuggestion() {
        let evidence = ChordInkRecognizer.scoredCandidateEvidence(
            from: [candidate("1", 5)], minimumConfidence: 3.7,
            match: ChordRecognitionCompendium.match
        )
        let result = ChordInkRecognitionResult(
            rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0,
            candidateScores: evidence.scores,
            rejectedCandidateConfidence: evidence.rejectedCandidateConfidence
        )
        XCTAssertTrue(result.candidateScores.isEmpty)
        XCTAssertNil(ChordInkRecognitionPolicy.decision(for: result).acceptedText)
        XCTAssertTrue(ChordInkRenderResolutionPolicy.candidateTexts(for: result).isEmpty)
    }

    func testNumericRejectionKeepsPressureBoundaryAndRawTranscriptOutOfSuggestions() throws {
        let match = try XCTUnwrap(ChordRecognitionCompendium.match("C7"))
        for (rejected, expectedAction) in [(4.101, ChordInkRecognitionAction.confirm),
                                           (4.099, ChordInkRecognitionAction.trusted)] {
            let result = ChordInkRecognitionResult(
                rawCandidates: ["1", "C7"], glyphCandidates: [], match: match, confidence: 4.12,
                candidateScores: [.init(text: "C7", displayText: "C7", confidence: 4.12)],
                rejectedCandidateConfidence: rejected
            )
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            XCTAssertEqual(decision.action, expectedAction)
            XCTAssertEqual(ChordInkRenderResolutionPolicy.candidateTexts(for: result), ["C7"])
            if expectedAction == .confirm {
                XCTAssertEqual(decision.reason,
                    "Unsupported high-confidence read. Choose a suggestion or type the chord you meant.")
            }
        }
    }
}

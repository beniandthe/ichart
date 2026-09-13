import XCTest
@testable import iChart

final class ChordInkRenderResolutionPolicyTests: XCTestCase {
    func testRecognitionActionDecodesLegacyAutoRenderValueAsTrusted() throws {
        let data = Data(#""autoRender""#.utf8)

        let action = try JSONDecoder().decode(ChordInkRecognitionAction.self, from: data)
        let encoded = try JSONEncoder().encode(action)

        XCTAssertEqual(action, .trusted)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #""trusted""#)
    }

    func testClearTrustedCandidateStaysTrustedWhenMemoryAllowsIt() {
        let drawingData = Data("clear C".utf8)
        let resolution = ChordInkRenderResolutionPolicy.resolution(
            for: recognitionResult(
                matchText: "C",
                confidence: 4.8,
                scores: [
                    candidateScore("C", confidence: 4.8),
                    candidateScore("G", confidence: 4.1)
                ]
            ),
            drawingData: drawingData,
            correctionMemory: ChordInkUserCorrectionMemory()
        )

        XCTAssertEqual(resolution.decision.action, .trusted)
        XCTAssertEqual(resolution.decision.acceptedText, "C")
        XCTAssertEqual(Array(resolution.candidateTexts.prefix(2)), ["C", "G"])
    }

    func testExplicitlyCorrectedTrustedCandidateMemoryDemotesTrustedReadToConfirmation() {
        let drawingData = Data("rejected C".utf8)
        let result = recognitionResult(
            matchText: "C",
            confidence: 4.8,
            scores: [
                candidateScore("C", confidence: 4.8),
                candidateScore("G", confidence: 4.1)
            ]
        )
        let candidateTexts = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
        var memory = ChordInkUserCorrectionMemory()
        memory.recordRejectedTrustedCandidate(
            acceptedText: "C",
            drawingData: drawingData,
            candidateSignature: ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
        )

        let resolution = ChordInkRenderResolutionPolicy.resolution(
            for: result,
            drawingData: drawingData,
            correctionMemory: memory
        )

        XCTAssertEqual(resolution.decision.action, .confirm)
        XCTAssertEqual(resolution.decision.acceptedText, "C")
        XCTAssertTrue(resolution.decision.reason.contains("previously corrected from C"))
        XCTAssertFalse(resolution.decision.isCloseRace)
        XCTAssertNil(resolution.decision.confidenceGap)
    }

    func testReviewChoicesReserveVisibleSlotForSimplerSameRootPrimaryCandidate() {
        let result = recognitionResult(
            matchText: "C7(#11)(b3)",
            confidence: 5.41,
            scores: [
                candidateScore("C7(#11)(b3)", confidence: 5.41),
                candidateScore("C7(#11)(b5)", confidence: 5.38),
                candidateScore("C7(#11)(b9)", confidence: 5.37),
                candidateScore("C7(#11)", confidence: 4.95)
            ]
        )

        XCTAssertEqual(
            Array(ChordInkRenderResolutionPolicy.candidateTexts(for: result).prefix(3)),
            ["C7(#11)(b3)", "C7(#11)(b5)", "C7(#11)"]
        )
    }

    func testReviewChoicesSurfaceStrongReviewOnlyCandidateWithoutChangingPrimary() {
        var result = recognitionResult(
            matchText: "F#7(b5)",
            confidence: 4.82,
            scores: [
                candidateScore("F#7(b5)", confidence: 4.82),
                candidateScore("F#7(b9)", confidence: 4.75),
                candidateScore("F#7(b3)", confidence: 4.47)
            ]
        )
        result.reviewCandidateScores = [
            candidateScore("F#7(b13)", confidence: 5.02)
        ]

        XCTAssertEqual(
            Array(ChordInkRenderResolutionPolicy.candidateTexts(for: result).prefix(3)),
            ["F#7(b5)", "F#7(b13)", "F#7(b9)"]
        )
        XCTAssertEqual(result.match?.displayText, "F#7(b5)")
    }

    func testReviewChoicesPreferSimplerSameRootRecoveryForThirdVisibleSlot() {
        var result = recognitionResult(
            matchText: "Bb7(#5)",
            confidence: 4.75,
            scores: [
                candidateScore("Bb7(#5)", confidence: 4.75),
                candidateScore("Bb7(b5)", confidence: 4.72)
            ]
        )
        result.reviewCandidateScores = [
            candidateScore("Bb7(b5)(b13)", confidence: 5.19),
            candidateScore("Bb7(#11)", confidence: 3.77)
        ]

        XCTAssertEqual(
            Array(ChordInkRenderResolutionPolicy.candidateTexts(for: result).prefix(3)),
            ["Bb7(#5)", "Bb7(b5)(b13)", "Bb7(#11)"]
        )
    }

    func testReviewChoicesPreferSameStructureOverUnrelatedSimplerQuality() {
        var result = recognitionResult(
            matchText: "Db7(b5)",
            confidence: 4.91,
            scores: [
                candidateScore("Db7(b5)", confidence: 4.91),
                candidateScore("Bb7(b5)", confidence: 4.82),
                candidateScore("Db7(b9)", confidence: 4.20)
            ]
        )
        result.reviewCandidateScores = [
            candidateScore("Dbsus", confidence: 4.55)
        ]

        XCTAssertEqual(
            Array(ChordInkRenderResolutionPolicy.candidateTexts(for: result).prefix(3)),
            ["Db7(b5)", "Bb7(b5)", "Db7(b9)"]
        )
    }

    private func recognitionResult(
        matchText: String,
        confidence: Double,
        scores: [ChordInkCandidateScore]
    ) -> ChordInkRecognitionResult {
        ChordInkRecognitionResult(
            rawCandidates: scores.map(\.text),
            glyphCandidates: [],
            match: ChordRecognitionCompendium.match(matchText),
            confidence: confidence,
            candidateScores: scores
        )
    }

    private func candidateScore(_ text: String, confidence: Double) -> ChordInkCandidateScore {
        let match = ChordRecognitionCompendium.match(text)
        return ChordInkCandidateScore(
            text: text,
            displayText: match?.displayText,
            confidence: confidence
        )
    }
}

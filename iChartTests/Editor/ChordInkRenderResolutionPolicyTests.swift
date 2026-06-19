import XCTest
@testable import iChart

final class ChordInkRenderResolutionPolicyTests: XCTestCase {
    func testClearAutoRenderCandidateStaysAutomaticWhenMemoryAllowsIt() {
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

        XCTAssertEqual(resolution.decision.action, .autoRender)
        XCTAssertEqual(resolution.decision.acceptedText, "C")
        XCTAssertEqual(Array(resolution.candidateTexts.prefix(2)), ["C", "G"])
    }

    func testRejectedAutoRenderMemoryDemotesAutomaticRenderToConfirmation() {
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
        memory.recordRejectedAutoRender(
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
        XCTAssertTrue(resolution.decision.reason.contains("previously rendered as C"))
        XCTAssertFalse(resolution.decision.isCloseRace)
        XCTAssertNil(resolution.decision.confidenceGap)
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

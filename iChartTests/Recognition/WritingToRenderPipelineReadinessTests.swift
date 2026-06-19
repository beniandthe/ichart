import XCTest
@testable import iChart

final class WritingToRenderPipelineReadinessTests: XCTestCase {
    private let recognizer = ChordInkRecognizer()

    func testBoundedProductLoopFixturesMeetTrustAndLatencyBudget() throws {
        WritingToRenderPipelineProof.assertCaseSetIsBounded()

        var totalRecognitionMilliseconds = 0.0

        for proofCase in WritingToRenderPipelineProof.cases {
            let fixture = try InkFixtureLoader.load(proofCase.fixtureName, file: #filePath)
            let result = recognizer.recognize(strokes: fixture.strokes, options: .live)

            XCTAssertEqual(fixture.expectedDisplayText, proofCase.expectedDisplayText, fixture.name)
            XCTAssertFalse(result.rawCandidates.isEmpty, fixture.name)
            XCTAssertFalse(result.candidateScores.isEmpty, fixture.name)

            _ = try WritingToRenderPipelineProof.acceptedDecision(
                for: result,
                proofCase: proofCase
            )
            totalRecognitionMilliseconds += result.metrics.totalMilliseconds
        }

        XCTAssertLessThan(
            totalRecognitionMilliseconds,
            WritingToRenderPipelineProof.totalRecognitionLatencyBudgetMilliseconds,
            "The bounded writing-to-render proof set should stay comfortably below the product-loop latency budget."
        )
    }
}

import XCTest
@testable import iChart

enum WritingToRenderPipelineProof {
    struct ProductLoopCase {
        var fixtureName: String
        var measureIndex: Int
        var targetFraction: Double
        var expectedDisplayText: String
        var expectedDecisionAction: ChordInkRecognitionAction
        var expectsOCRSidecarRequest: Bool
    }

    struct AcceptedDecision {
        var match: ChordRecognitionMatch
        var acceptedText: String
        var action: ChordInkRecognitionAction
    }

    static let maxProductProofCases = 3
    static let recognitionLatencyBudgetMilliseconds = 750.0
    static let totalRecognitionLatencyBudgetMilliseconds = 1_500.0

    static let cases = [
        ProductLoopCase(
            fixtureName: "C",
            measureIndex: 0,
            targetFraction: 0.05,
            expectedDisplayText: "C",
            expectedDecisionAction: .autoRender,
            expectsOCRSidecarRequest: false
        ),
        ProductLoopCase(
            fixtureName: "Db7b9",
            measureIndex: 1,
            targetFraction: 0.30,
            expectedDisplayText: "Db7(b9)",
            expectedDecisionAction: .confirm,
            expectsOCRSidecarRequest: true
        ),
        ProductLoopCase(
            fixtureName: "GSlashB",
            measureIndex: 2,
            targetFraction: 0.55,
            expectedDisplayText: "G/B",
            expectedDecisionAction: .autoRender,
            expectsOCRSidecarRequest: false
        )
    ]

    static func assertCaseSetIsBounded(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(
            cases.count,
            maxProductProofCases,
            "Writing-to-render product proof must stay bounded; this is readiness evidence, not a handwriting training loop.",
            file: file,
            line: line
        )
    }

    static func acceptedDecision(
        for result: ChordInkRecognitionResult,
        proofCase: ProductLoopCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AcceptedDecision {
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(12))), scores: \(Array(result.candidateScores.prefix(6)))"
        let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
        let decision = ChordRecognitionTrustArbiter.decision(for: result)

        XCTAssertEqual(
            result.match?.displayText,
            proofCase.expectedDisplayText,
            "\(proofCase.fixtureName) \(debugSummary)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            primaryDecision.action,
            proofCase.expectedDecisionAction,
            proofCase.fixtureName,
            file: file,
            line: line
        )
        XCTAssertEqual(
            decision.action,
            proofCase.expectedDecisionAction,
            proofCase.fixtureName,
            file: file,
            line: line
        )
        XCTAssertEqual(
            decision.acceptedText,
            proofCase.expectedDisplayText,
            proofCase.fixtureName,
            file: file,
            line: line
        )
        XCTAssertEqual(
            decision.trustSource,
            .primaryRecognizer,
            proofCase.fixtureName,
            file: file,
            line: line
        )
        XCTAssertEqual(
            decision.agreementLevel,
            .ocrNotRequested,
            proofCase.fixtureName,
            file: file,
            line: line
        )
        XCTAssertEqual(
            ChordRecognitionTrustArbiter.shouldRequestOCR(
                for: result,
                primaryDecision: primaryDecision
            ),
            proofCase.expectsOCRSidecarRequest,
            proofCase.fixtureName,
            file: file,
            line: line
        )
        XCTAssertNil(result.symbolLedger, proofCase.fixtureName, file: file, line: line)
        XCTAssertNil(result.symbolLedgerAssessment, proofCase.fixtureName, file: file, line: line)
        XCTAssertLessThan(
            result.metrics.totalMilliseconds,
            recognitionLatencyBudgetMilliseconds,
            "\(proofCase.fixtureName) exceeded the bounded product-loop recognition latency budget.",
            file: file,
            line: line
        )

        let acceptedText = try XCTUnwrap(
            decision.acceptedText,
            proofCase.fixtureName,
            file: file,
            line: line
        )
        let match = try XCTUnwrap(
            ChordRecognitionCompendium.match(acceptedText),
            proofCase.fixtureName,
            file: file,
            line: line
        )

        return AcceptedDecision(
            match: match,
            acceptedText: acceptedText,
            action: decision.action
        )
    }
}

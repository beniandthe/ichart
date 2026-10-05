import XCTest
@testable import RecognitionStudy

final class RecognitionStudyVisionResultProviderTests: XCTestCase {
    func testUncalibratedVisionAcceptanceIsAlwaysPresentedAsReviewOnly() {
        let output = RecognitionStudyVisionChordRecognizer.Result(
            decision: .accepted(chord: "C7", confidenceFloor: 0.93),
            candidates: [
                .init(
                    rawText: "C7",
                    rawConfidence: 0.93,
                    normalizedChord: "C7",
                    passIndex: 0,
                    rank: 0
                )
            ]
        )

        let result = RecognitionStudyVisionResultProvider.presentation(
            for: output,
            elapsedMilliseconds: 42
        )

        guard case let .review(candidate, detail) = result else {
            return XCTFail("An uncalibrated baseline must never present an accepted result.")
        }
        XCTAssertEqual(candidate, "C7")
        XCTAssertTrue(detail.contains("Review only"))
        XCTAssertTrue(detail.contains("42 ms"))
    }

    func testGrammarInvalidVisionTextProducesNoReadWithoutDisplayingRawOCR() {
        let output = RecognitionStudyVisionChordRecognizer.Result(
            decision: .noRead(.noGrammarCandidate),
            candidates: [
                .init(
                    rawText: "Cmaj7",
                    rawConfidence: 0.97,
                    normalizedChord: nil,
                    passIndex: 0,
                    rank: 0
                )
            ]
        )

        let result = RecognitionStudyVisionResultProvider.presentation(
            for: output,
            elapsedMilliseconds: 18
        )

        guard case let .noRead(detail) = result else {
            return XCTFail("Raw out-of-grammar OCR must not become a displayed chord candidate.")
        }
        XCTAssertNil(result.displayText)
        XCTAssertTrue(detail.contains("outside the strict chord grammar"))
        XCTAssertTrue(detail.contains("Nothing was accepted"))
        XCTAssertEqual(output.candidates.first?.rawText, "Cmaj7")
    }

    func testInvalidVisionLeaderDoesNotDisplayOrPromoteValidRunnerUp() {
        let output = RecognitionStudyVisionChordRecognizer.Result(
            decision: .review(.topCandidateOutsideGrammar),
            candidates: [
                .init(rawText: "J", rawConfidence: 0.99, normalizedChord: nil, passIndex: 0, rank: 0),
                .init(rawText: "C7", rawConfidence: 0.90, normalizedChord: "C7", passIndex: 0, rank: 1)
            ]
        )
        let result = RecognitionStudyVisionResultProvider.presentation(for: output, elapsedMilliseconds: 3)
        guard case let .review(candidate, _) = result else {
            return XCTFail("An invalid leader remains unresolved review evidence.")
        }
        XCTAssertNil(candidate)
        XCTAssertNil(result.displayText)
        XCTAssertEqual(output.candidates.map(\.rawText), ["J", "C7"])
    }

    func testInvalidChordCannotReachDisplayThroughAcceptedOrNormalizedReviewPayload() {
        for decision in [
            RecognitionStudyVisionChordRecognizer.Decision.accepted(chord: "Cñ7", confidenceFloor: 0.99),
            .review(.confidenceBelowThreshold)
        ] {
            let output = RecognitionStudyVisionChordRecognizer.Result(
                decision: decision,
                candidates: [
                    .init(rawText: "Cñ7", rawConfidence: 0.99, normalizedChord: "Cñ7", passIndex: 0, rank: 0)
                ]
            )
            let result = RecognitionStudyVisionResultProvider.presentation(for: output, elapsedMilliseconds: 3)
            XCTAssertNil(result.displayText)
        }

        let mislabeledOCR = RecognitionStudyVisionChordRecognizer.Result(
            decision: .review(.confidenceBelowThreshold),
            candidates: [
                .init(rawText: "Cñ7", rawConfidence: 0.99, normalizedChord: "C7", passIndex: 0, rank: 0)
            ]
        )
        XCTAssertNil(RecognitionStudyVisionResultProvider.presentation(
            for: mislabeledOCR, elapsedMilliseconds: 3
        ).displayText)
    }

    func testNoVisionTextRemainsANoRead() {
        let output = RecognitionStudyVisionChordRecognizer.Result(
            decision: .noRead(.noVisionText),
            candidates: []
        )

        let result = RecognitionStudyVisionResultProvider.presentation(
            for: output,
            elapsedMilliseconds: 7
        )

        guard case let .noRead(detail) = result else {
            return XCTFail("Missing Vision evidence must remain a no-read.")
        }
        XCTAssertTrue(detail.contains("no text candidate"))
    }

    func testVisionExecutionErrorRequiresTechnicalExclusion() async throws {
        var configuration = RecognitionStudyVisionChordRecognizer.Configuration.default
        configuration.canvasWidth = 0
        let provider = RecognitionStudyVisionResultProvider(
            recognizer: RecognitionStudyVisionChordRecognizer(
                configuration: configuration
            )
        )
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(points: [InkPoint(x: 10, y: 10, timeOffset: 0)])
        ])
        let result = await provider.result(for: packet)
        guard case .technicalFailure = result else {
            return XCTFail("A Vision execution error is not a completed no-read prediction.")
        }
        XCTAssertTrue(result.requiresTechnicalFailureExclusion)
        XCTAssertNil(result.displayText)
    }
}

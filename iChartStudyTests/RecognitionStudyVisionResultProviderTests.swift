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

    func testGrammarInvalidVisionTextRemainsVisibleButUnaccepted() {
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

        guard case let .review(candidate, detail) = result else {
            return XCTFail("Raw out-of-grammar evidence should be review-only.")
        }
        XCTAssertEqual(candidate, "Cmaj7")
        XCTAssertTrue(detail.contains("outside the strict chord grammar"))
        XCTAssertTrue(detail.contains("not accepted"))
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
}

import XCTest
@testable import iChart

final class ChordInkTrustAcceptanceTests: XCTestCase {
    private let recognizer = ChordInkRecognizer()

    func testTrustAcceptanceFixtureSetIncludesRequiredFamilies() throws {
        let fixtureNames = Set(InkFixtureLoader.trustAcceptanceFixtureNames)

        XCTAssertTrue(fixtureNames.isSuperset(of: [
            "A",
            "B",
            "D",
            "E",
            "F",
            "G",
            "DFlatMinorCaptured01",
            "DFlat7susCaptured03",
            "GSlashBCaptured01",
            "CMajor7Captured01",
            "C7susCaptured03",
            "C7Flat9Captured01",
            "C7Sharp11Captured01",
            "C7altCaptured03",
            "ChordRepeatCaptured01"
        ]))
    }

    func testRecognizesTrustAcceptanceFixtureSet() throws {
        let fixtures = try InkFixtureLoader.loadTrustAcceptanceFixtures(file: #filePath)

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), scores: \(result.candidateScores.prefix(8))"

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, "\(fixture.name) \(debugSummary)")
            XCTAssertEqual(decision.acceptedText, fixture.expectedDisplayText, fixture.name)
        }
    }
}

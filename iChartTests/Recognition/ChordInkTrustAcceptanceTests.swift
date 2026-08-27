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
            "ARootSplitDevice01",
            "DFlatMinorCaptured01",
            "DFlat7susCaptured03",
            "GSlashBCaptured01",
            "CMajor7Captured01",
            "C7susCaptured03",
            "C7Flat9Captured01",
            "C7Sharp11Captured01",
            "C7altCaptured03",
            "DSlashFSharpLooseDevice01",
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

    func testLooseDSlashFSharpDeviceFixtureStaysPrimaryButRequiresConfirmation() throws {
        let fixture = try InkFixtureLoader.load("DSlashFSharpLooseDevice01", file: #filePath)
        let result = recognizer.recognize(strokes: fixture.strokes)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let rankedScores = ChordInkRecognitionPolicy.rankedSupportedScores(for: result)
        let rankedDisplayTexts = rankedScores.compactMap(\.displayText)
        let glyphSummary = result.glyphCandidates.map { group in
            group.prefix(8).map { "\($0.text):\($0.confidence)" }
        }
        let debugSummary = """
        raw: \(Array(result.rawCandidates.prefix(16)))
        glyphs: \(glyphSummary)
        scores: \(result.candidateScores.prefix(8))
        decision: \(decision)
        """

        XCTAssertEqual(result.match?.displayText, "D/F#", debugSummary)
        XCTAssertEqual(decision.acceptedText, "D/F#", debugSummary)
        XCTAssertEqual(decision.action, .confirm, debugSummary)
        XCTAssertTrue(decision.isCloseRace, debugSummary)
        XCTAssertEqual(decision.competingCandidateText, "B", debugSummary)
        XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, debugSummary)
        XCTAssertEqual(result.glyphCandidates.first?.first?.text, "D", debugSummary)
        XCTAssertEqual(Array(rankedDisplayTexts.prefix(2)), ["D/F#", "B/F#"], debugSummary)
    }
}

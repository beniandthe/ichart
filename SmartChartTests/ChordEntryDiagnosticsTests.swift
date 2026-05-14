import XCTest
@testable import SmartChart

final class ChordEntryDiagnosticsTests: XCTestCase {
    func testRecorderAppendsLoadsAndResetsDiagnosticEvents() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = ChordEntryDiagnosticsRecorder(
            url: temporaryDirectory.appendingPathComponent("chord-entry-diagnostics.jsonl")
        )
        let event = ChordEntryDiagnosticEvent(
            timestamp: Date(timeIntervalSinceReferenceDate: 10),
            chartID: UUID(),
            chartTitle: "Chord Writing Test Chart",
            measureID: UUID(),
            measureIndex: 2,
            chordEventID: UUID(),
            resolution: .manualCorrection,
            acceptedText: "Bb13",
            previousRenderedDisplayText: nil,
            renderedDisplayText: "Bb13",
            bestCandidateText: "Bbsus",
            suggestedCandidateTexts: ["Bbsus", "Bb13"],
            rawCandidates: ["Bbsus", "Bb13", "BB13"],
            candidateScores: [
                ChordInkCandidateScore(text: "Bbsus", displayText: "Bbsus", confidence: 4.31),
                ChordInkCandidateScore(text: "Bb13", displayText: "Bb13", confidence: 4.25)
            ],
            confidence: 4.25,
            recognitionReason: "Close race. Choose the chord you meant, or type it in.",
            wasCloseRace: true,
            confidenceGap: 0.06,
            targetFraction: 0.51
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try recorder.append(event)
        try recorder.append(event)

        XCTAssertEqual(try recorder.loadEvents(), [event, event])

        try recorder.reset()

        XCTAssertEqual(try recorder.loadEvents(), [])
    }
}

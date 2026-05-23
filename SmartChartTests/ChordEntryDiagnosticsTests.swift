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

    func testRecorderAppendsWhenPathContainsSpaces() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let recorder = ChordEntryDiagnosticsRecorder(
            url: temporaryDirectory.appendingPathComponent("chord-entry-diagnostics.jsonl")
        )
        let event = diagnosticEvent(
            chart: Chart.blank(title: "Chord Writing Test Chart", key: .cMajor),
            measureID: UUID(),
            chordEventID: UUID(),
            acceptedText: "C",
            renderedDisplayText: "C",
            resolution: .autoRendered
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory.deletingLastPathComponent())
        }

        try recorder.append(event)
        try recorder.append(event)

        XCTAssertEqual(try recorder.loadEvents(), [event, event])

        try recorder.reset()

        XCTAssertEqual(try recorder.loadEvents(), [])
    }

    func testCoverageReportFindsMissingChordEntryDiagnostics() throws {
        var chart = Chart.blank(title: "Chord Writing Test Chart", key: .cMajor, measureCount: 1)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let cMatch = try XCTUnwrap(ChordRecognitionCompendium.match("C"))
        let dbMatch = try XCTUnwrap(ChordRecognitionCompendium.match("Db7(b9)"))
        let cEventID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(cMatch.symbol, rawInput: "C", to: measureID, atFraction: nil)
        )
        let dbEventID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(dbMatch.symbol, rawInput: "Db7(b9)", to: measureID, atFraction: nil)
        )
        let loggedEvent = diagnosticEvent(
            chart: chart,
            measureID: measureID,
            chordEventID: cEventID,
            acceptedText: "C",
            renderedDisplayText: "C",
            resolution: .autoRendered
        )

        let report = ChordEntryDiagnosticCoverage.report(for: chart, events: [loggedEvent])

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.renderedChordEventIDs, [cEventID, dbEventID])
        XCTAssertEqual(report.loggedChordEventIDs, [cEventID])
        XCTAssertEqual(report.missingChordEventIDs, [dbEventID])
        XCTAssertEqual(report.staleChordEventIDs, [UUID]())
        XCTAssertEqual(report.resolutionCounts[ChordEntryDiagnosticResolution.autoRendered], 1)
    }

    func testCoverageReportAcceptsCorrectionDiagnosticsAsCoverage() throws {
        var chart = Chart.blank(title: "Chord Writing Test Chart", key: .cMajor, measureCount: 1)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let cMatch = try XCTUnwrap(ChordRecognitionCompendium.match("C"))
        let dbMatch = try XCTUnwrap(ChordRecognitionCompendium.match("Db/A"))
        let chordEventID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(cMatch.symbol, rawInput: "C", to: measureID, atFraction: nil)
        )
        XCTAssertTrue(chart.replaceChordEvent(chordEventID, with: dbMatch.symbol, rawInput: "Db/A"))
        let correctionEvent = diagnosticEvent(
            chart: chart,
            measureID: measureID,
            chordEventID: chordEventID,
            acceptedText: "Db/A",
            renderedDisplayText: "Db/A",
            resolution: .renderedChordCorrection
        )
        let staleEvent = diagnosticEvent(
            chart: chart,
            measureID: measureID,
            chordEventID: UUID(),
            acceptedText: "G",
            renderedDisplayText: "G",
            resolution: .manualCorrection
        )

        let report = ChordEntryDiagnosticCoverage.report(for: chart, events: [correctionEvent, staleEvent])

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.loggedChordEventIDs.count, 2)
        XCTAssertEqual(report.missingChordEventIDs, [UUID]())
        XCTAssertEqual(report.staleChordEventIDs, [staleEvent.chordEventID!])
        XCTAssertEqual(report.resolutionCounts[ChordEntryDiagnosticResolution.renderedChordCorrection], 1)
        XCTAssertEqual(report.resolutionCounts[ChordEntryDiagnosticResolution.manualCorrection], 1)
    }

    func testRecorderReconcilesRenderedChordEventsMissingDiagnostics() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = ChordEntryDiagnosticsRecorder(
            url: temporaryDirectory.appendingPathComponent("chord-entry-diagnostics.jsonl")
        )
        var chart = Chart.blank(title: "Chord Writing Test Chart", key: .cMajor, measureCount: 1)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let cMatch = try XCTUnwrap(ChordRecognitionCompendium.match("C"))
        let slashMatch = try XCTUnwrap(ChordRecognitionCompendium.match("G/B"))
        let cEventID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(cMatch.symbol, rawInput: "C", to: measureID, atFraction: nil)
        )
        let slashEventID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(slashMatch.symbol, rawInput: "G/B", to: measureID, atFraction: nil)
        )
        let loggedEvent = diagnosticEvent(
            chart: chart,
            measureID: measureID,
            chordEventID: cEventID,
            acceptedText: "C",
            renderedDisplayText: "C",
            resolution: .autoRendered
        )
        let timestamp = Date(timeIntervalSinceReferenceDate: 20)

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try recorder.append(loggedEvent)

        let reconciledEvents = try recorder.reconcileRenderedChordEvents(for: chart, timestamp: timestamp)

        XCTAssertEqual(reconciledEvents.count, 1)
        let reconciledEvent = try XCTUnwrap(reconciledEvents.first)
        XCTAssertEqual(reconciledEvent.timestamp, timestamp)
        XCTAssertEqual(reconciledEvent.chordEventID, slashEventID)
        XCTAssertEqual(reconciledEvent.resolution, .reconciledRenderedChord)
        XCTAssertEqual(reconciledEvent.acceptedText, "G/B")
        XCTAssertEqual(reconciledEvent.renderedDisplayText, "G/B")
        XCTAssertEqual(reconciledEvent.bestCandidateText, "G/B")
        XCTAssertEqual(reconciledEvent.suggestedCandidateTexts, ["G/B"])
        XCTAssertEqual(reconciledEvent.rawCandidates, ["G/B"])
        XCTAssertEqual(reconciledEvent.candidateScores, [])
        XCTAssertEqual(reconciledEvent.confidence, 0)
        XCTAssertEqual(reconciledEvent.recognitionReason, "Reconciled rendered chord event missing live diagnostic.")

        let loadedEvents = try recorder.loadEvents()
        XCTAssertEqual(loadedEvents.map(\.chordEventID), [cEventID, slashEventID])
        XCTAssertEqual(
            ChordEntryDiagnosticCoverage.report(for: chart, events: loadedEvents).missingChordEventIDs,
            [UUID]()
        )
    }

    func testRecorderDoesNotDuplicateReconciledDiagnostics() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = ChordEntryDiagnosticsRecorder(
            url: temporaryDirectory.appendingPathComponent("chord-entry-diagnostics.jsonl")
        )
        var chart = Chart.blank(title: "Chord Writing Test Chart", key: .cMajor, measureCount: 1)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let cMatch = try XCTUnwrap(ChordRecognitionCompendium.match("C"))
        _ = try XCTUnwrap(
            chart.appendRecognizedChordEvent(cMatch.symbol, rawInput: "C", to: measureID, atFraction: nil)
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        XCTAssertEqual(try recorder.reconcileRenderedChordEvents(for: chart).count, 1)
        XCTAssertEqual(try recorder.reconcileRenderedChordEvents(for: chart).count, 0)
        XCTAssertEqual(try recorder.loadEvents().count, 1)
    }

    private func diagnosticEvent(
        chart: Chart,
        measureID: UUID,
        chordEventID: UUID,
        acceptedText: String,
        renderedDisplayText: String,
        resolution: ChordEntryDiagnosticResolution
    ) -> ChordEntryDiagnosticEvent {
        ChordEntryDiagnosticEvent(
            timestamp: Date(timeIntervalSinceReferenceDate: 10),
            chartID: chart.id,
            chartTitle: chart.title,
            measureID: measureID,
            measureIndex: 0,
            chordEventID: chordEventID,
            resolution: resolution,
            acceptedText: acceptedText,
            previousRenderedDisplayText: nil,
            renderedDisplayText: renderedDisplayText,
            bestCandidateText: acceptedText,
            suggestedCandidateTexts: [acceptedText],
            rawCandidates: [acceptedText],
            candidateScores: [],
            confidence: 4.5,
            recognitionReason: "Test diagnostic.",
            wasCloseRace: false,
            confidenceGap: nil,
            targetFraction: nil
        )
    }
}

import XCTest
@testable import iChart

final class RhythmRecognitionDiagnosticsTests: XCTestCase {
    func testRecorderAppendsLoadsAndResetsRhythmEvents() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = RhythmRecognitionDiagnosticsRecorder(
            url: temporaryDirectory.appendingPathComponent("rhythm-recognition-diagnostics.jsonl")
        )
        let event = diagnosticEvent(stage: .tapRendered, route: "commit")

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try recorder.append(event)
        try recorder.append(event)

        XCTAssertEqual(try recorder.loadEvents(), [event, event])

        try recorder.reset()

        XCTAssertEqual(try recorder.loadEvents(), [])
    }

    func testRecorderCapsLocalLogSize() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = RhythmRecognitionDiagnosticsRecorder(
            url: temporaryDirectory.appendingPathComponent("rhythm-recognition-diagnostics.jsonl"),
            maxLogSizeBytes: 1
        )
        let firstEvent = diagnosticEvent(stage: .tapToRenderCandidate, route: "readyToRender")
        let secondEvent = diagnosticEvent(stage: .tapRendered, route: "commit")

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try recorder.append(firstEvent)
        try recorder.append(secondEvent)

        XCTAssertEqual(try recorder.loadEvents(), [secondEvent])
    }

    func testRhythmDiagnosticStatusTextPrefersProposalValues() {
        let event = diagnosticEvent(
            stage: .inkPreserved,
            route: "preserveInk",
            reason: "unsupported",
            proposalValues: [.quarter, .quarter],
            naturalValues: [.quarter, .quarter, .quarter]
        )

        XCTAssertEqual(event.statusTitle, "Rhythm Needs Check")
        XCTAssertEqual(event.valuesText, "quarter, quarter")
        XCTAssertEqual(event.statusDetail, "unsupported: quarter, quarter")
    }

    func testRhythmDiagnosticStatusTextFallsBackToNaturalValues() {
        let event = diagnosticEvent(
            stage: .tapToRenderCandidate,
            route: "readyToRender",
            proposalValues: [],
            naturalValues: [.slash, .slash, .slash]
        )

        XCTAssertEqual(event.statusTitle, "Tap To Render")
        XCTAssertEqual(event.valuesText, "slash, slash, slash")
        XCTAssertEqual(event.statusDetail, "slash, slash, slash")
    }

    func testRhythmDiagnosticStatusTextNamesTapToRenderCandidate() {
        let event = diagnosticEvent(
            stage: .tapToRenderCandidate,
            route: "readyToRender",
            proposalValues: [.quarter, .quarter, .quarter, .quarter]
        )

        XCTAssertEqual(event.statusTitle, "Tap To Render")
        XCTAssertEqual(event.statusDetail, "quarter, quarter, quarter, quarter")
    }

    func testRhythmDiagnosticPersistsPipelinePreview() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = RhythmRecognitionDiagnosticsRecorder(
            url: temporaryDirectory.appendingPathComponent("rhythm-recognition-diagnostics.jsonl")
        )
        let preview = RhythmRecognitionPipelinePreview(
            strokeCount: 2,
            evidenceCounts: ["eighthRestHook": 1, "stem": 1],
            evidence: [
                RhythmRecognitionPipelinePreview.GlyphEvidence(
                    strokeIndices: [0],
                    kind: "eighthRestHook",
                    bounds: RhythmRecognitionPipelineBounds(CGRect(x: 10, y: 12, width: 8, height: 18)),
                    confidence: 0.1
                )
            ],
            symbolGroups: [
                RhythmRecognitionPipelinePreview.SymbolGroup(
                    index: 0,
                    strokeIndices: [0],
                    evidenceKinds: ["eighthRestHook"],
                    bounds: RhythmRecognitionPipelineBounds(CGRect(x: 10, y: 12, width: 8, height: 18))
                )
            ],
            decision: "keepWriting",
            route: "preserveInk",
            selectedValues: [.eighthRest, .eighth],
            naturalUnits: 2,
            targetUnits: 8,
            reasoningPaths: [
                RhythmRecognitionPipelinePreview.ReasoningPath(
                    kind: "glyphOCR",
                    outcome: "keepWriting",
                    values: [.eighthRest, .eighth],
                    reason: "underfilled",
                    summary: "source=gridFirst reason=underfilled values=eighthRest,eighth"
                )
            ],
            notes: ["rest and notehead evidence both present"]
        )
        var event = diagnosticEvent(stage: .inkPreserved, route: "preserveInk")
        event.pipelinePreview = preview

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try recorder.append(event)

        let loadedEvent = try XCTUnwrap(recorder.loadEvents().first)
        XCTAssertEqual(loadedEvent.pipelinePreview, preview)
        XCTAssertTrue(loadedEvent.statusDetail.contains("2 strokes"))
        XCTAssertTrue(loadedEvent.statusDetail.contains("eighthRestHook=1"))
    }

    private func diagnosticEvent(
        stage: RhythmRecognitionDiagnosticStage,
        route: String,
        reason: String? = nil,
        proposalValues: [RhythmValue] = [.quarter, .quarter, .quarter, .quarter],
        naturalValues: [RhythmValue] = [.quarter, .quarter, .quarter, .quarter]
    ) -> RhythmRecognitionDiagnosticEvent {
        RhythmRecognitionDiagnosticEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSinceReferenceDate: 20),
            chartID: UUID(),
            chartTitle: "Rhythm QA",
            measureID: UUID(),
            measureIndex: 0,
            layoutStyle: .rhythmSectionSheet,
            meterText: "4/4",
            stage: stage,
            decision: "commit",
            route: route,
            reason: reason,
            proposalValues: proposalValues,
            proposalSafety: "readyToRender",
            proposalIsNaturalExactFit: true,
            phraseSource: "gridFirst",
            naturalValues: naturalValues,
            naturalUnits: 8,
            targetUnits: 8,
            passesCompendium: true,
            glyphEvidenceCount: 4,
            symbolCount: 4,
            unreadSymbolCount: 0,
            uncoveredStrokeCount: 0,
            inkStrokeCount: 4,
            pipelinePreview: nil
        )
    }
}

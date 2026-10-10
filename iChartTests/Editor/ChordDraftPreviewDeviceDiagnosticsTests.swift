import XCTest
@testable import iChart

final class ChordDraftPreviewDeviceDiagnosticsTests: XCTestCase {
    func testRecorderAppendsLoadsAndResetsDeviceDraftPreviewEvents() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = ChordDraftPreviewDeviceDiagnosticRecorder(
            url: temporaryDirectory.appendingPathComponent("chord-draft-preview-debug.jsonl")
        )
        let measureID = UUID()
        let inkStroke = InkStroke(points: [
            InkPoint(x: 10, y: 20, timeOffset: 0),
            InkPoint(x: 18, y: 32, timeOffset: 0.1)
        ])
        let event = ChordDraftPreviewDeviceDiagnosticEvent(
            timestamp: Date(timeIntervalSinceReferenceDate: 10),
            stage: "finish_batch",
            flow: "draft_preview",
            layoutStyle: ChartLayoutStyle.rhythmSectionSheet.rawValue,
            requestID: UUID(),
            sourceStrokeCount: 7,
            recognitionStrokeCount: 6,
            visibleStrokeCount: 7,
            ignoredInvisibleStrokeCount: 1,
            barlineCount: 1,
            rawBatchTargetCount: 2,
            boundedBatchTargetCount: 2,
            skippedBatchTargetCount: 0,
            targetingDiagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics(
                selectedRoute: "measure_lane",
                draftBarlineClusterCount: 0,
                laneSequentialClusterCount: 3,
                measureLaneClusterCount: 2,
                fallbackClusterCount: 2,
                selectedClusterCount: 2
            ),
            payloadCount: 2,
            candidatePayloadCount: 1,
            draftCount: 2,
            unresolvedDraftCount: 1,
            targets: [
                ChordDraftPreviewDeviceDiagnosticTarget(
                    targetIndex: 0,
                    measureID: measureID,
                    fraction: 0.12,
                    visualOrder: 0.12,
                    laneSystemIndex: 0,
                    laneFraction: 0.12,
                        strokeCount: 2,
                        bounds: ChordDraftPreviewDeviceDiagnosticBounds(
                            minX: 10,
                            minY: 20,
                            width: 30,
                            height: 40
                        ),
                        inkStrokes: [inkStroke]
                    )
                ],
                payloads: [
                ChordDraftPreviewDeviceDiagnosticPayload(
                    targetIndex: 0,
                    measureID: measureID,
                    fraction: 0.12,
                    visualOrder: 0.12,
                    laneSystemIndex: 0,
                    laneFraction: 0.12,
                    strokeCount: 2,
                    rawCandidates: ["D"],
                    supportedCandidates: ["D"],
                    matchText: "D",
                    acceptedText: "D",
                    action: "trusted",
                    reason: "Trusted read.",
                    confidence: 4.5,
                    closeRace: false,
                    confidenceGap: nil,
                    requestedDelayMilliseconds: 400,
                    idleMilliseconds: 410,
                    recognitionMilliseconds: 12,
                    recognitionTotalMilliseconds: 422,
                    topScores: [
                        ChordInkCandidateScore(text: "D", displayText: "D", confidence: 4.5)
                    ],
                    reviewScores: [
                        ChordInkCandidateScore(text: "Db", displayText: "Db", confidence: 3.4)
                    ],
                    inkStrokes: [inkStroke]
                )
            ],
            replacements: [
                ChordDraftPreviewDeviceDiagnosticReplacement(
                    draftIndex: 0,
                    anchorMeasureID: measureID,
                    anchorFractionBucket: 4,
                    previousDraftID: UUID(),
                    newDraftID: UUID(),
                    targetFraction: 0.12,
                    laneSystemIndex: 0,
                    laneFraction: 0.12,
                    previousPreviewText: "D",
                    newPreviewText: nil,
                    previousRenderable: true,
                    newRenderable: false,
                    bestCandidateText: nil,
                    candidateTexts: [],
                    strokeCount: 2,
                    confidence: 0
                )
            ]
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try recorder.append(event)
        try recorder.append(event)

        let loadedEvents = try recorder.loadEvents()
        XCTAssertEqual(loadedEvents, [event, event])
        XCTAssertEqual(
            loadedEvents.first?.recognitionPipelineVersion,
            ChordInkRecognitionPipelineIdentity.version
        )
        XCTAssertEqual(loadedEvents.first?.layoutStyle, ChartLayoutStyle.rhythmSectionSheet.rawValue)
        XCTAssertEqual(
            loadedEvents.first?.targetingDiagnosticsVersion,
            LeadSheetChordInkRecognitionBatchTargetingDiagnostics.version
        )
        XCTAssertNotEqual(
            loadedEvents.first?.recognitionPipelineVersion,
            loadedEvents.first?.targetingDiagnosticsVersion
        )
        XCTAssertEqual(loadedEvents.first?.targetingRoute, "measure_lane")
        XCTAssertEqual(loadedEvents.first?.laneSequentialClusterCount, 3)
        XCTAssertEqual(loadedEvents.first?.measureLaneClusterCount, 2)
        XCTAssertEqual(loadedEvents.first?.targets.first?.inkStrokes, [inkStroke])
        XCTAssertEqual(loadedEvents.first?.payloads.first?.inkStrokes, [inkStroke])
        XCTAssertEqual(loadedEvents.first?.payloads.first?.requestedDelayMilliseconds, 400)
        XCTAssertEqual(loadedEvents.first?.payloads.first?.idleMilliseconds, 410)
        XCTAssertEqual(loadedEvents.first?.payloads.first?.recognitionMilliseconds, 12)
        XCTAssertEqual(loadedEvents.first?.payloads.first?.recognitionTotalMilliseconds, 422)
        XCTAssertEqual(loadedEvents.first?.payloads.first?.reviewScores?.first?.displayText, "Db")

        try recorder.reset()

        XCTAssertEqual(try recorder.loadEvents(), [])
    }

    func testRecorderLoadsOlderDeviceDraftPreviewEventsWithoutLayoutStyle() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = temporaryDirectory.appendingPathComponent("chord-draft-preview-debug.jsonl")
        let recorder = ChordDraftPreviewDeviceDiagnosticRecorder(url: url)

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let legacyEventJSON = """
        {"payloads":[],"replacements":[],"stage":"targeting","targets":[],"timestamp":"2026-08-26T21:50:00Z"}
        """
        let legacyEventData = try XCTUnwrap((legacyEventJSON + "\n").data(using: .utf8))
        try legacyEventData.write(to: url)

        let loadedEvents = try recorder.loadEvents()

        XCTAssertEqual(loadedEvents.count, 1)
        XCTAssertEqual(loadedEvents.first?.stage, "targeting")
        XCTAssertNil(loadedEvents.first?.recognitionPipelineVersion)
        XCTAssertNil(loadedEvents.first?.layoutStyle)
    }

    func testRecorderRetainsPriorChartEventsUntilSizeLimitIsExceeded() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recorder = ChordDraftPreviewDeviceDiagnosticRecorder(
            url: temporaryDirectory.appendingPathComponent("chord-draft-preview-debug.jsonl")
        )
        let firstEvent = ChordDraftPreviewDeviceDiagnosticEvent(
            timestamp: Date(timeIntervalSinceReferenceDate: 10),
            stage: "finish_single"
        )
        let nextSession = ChordDraftPreviewDeviceDiagnosticEvent(
            timestamp: Date(timeIntervalSinceReferenceDate: 11),
            stage: "reset"
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try recorder.append(firstEvent)
        XCTAssertFalse(try recorder.resetIfLargerThan(8_000_000))
        try recorder.append(nextSession)
        XCTAssertEqual(try recorder.loadEvents(), [firstEvent, nextSession])

        XCTAssertTrue(try recorder.resetIfLargerThan(0))
        XCTAssertEqual(try recorder.loadEvents(), [])
    }
}

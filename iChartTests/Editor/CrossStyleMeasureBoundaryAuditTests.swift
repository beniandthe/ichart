import XCTest
#if canImport(PencilKit) && canImport(UIKit)
import Foundation
import PencilKit
import UIKit
#endif
@testable import iChart

/// Cross-style audit: a new divider partitions the original measure's
/// material. A following meter change must still follow both segments.
@MainActor
final class CrossStyleMeasureBoundaryAuditTests: XCTestCase {
    func testSimpleSplitKeepsFollowingMeterChangeAfterBothSegments() throws {
        let fixture = try chartWithFollowingMeterChange(style: .simpleChordSheet)
        var chart = fixture.chart
        let rightID = try XCTUnwrap(chart.splitSimpleChordMeasure(fixture.firstID, atFraction: 0.5))

        try assertOriginalMeterBoundary(chart: chart, firstID: fixture.firstID, rightID: rightID,
            followingID: fixture.followingID, changeID: fixture.changeID)
    }

    func testCommittedRhythmSplitKeepsFollowingMeterChangeAfterBothSegmentsControl() throws {
        let fixture = try chartWithFollowingMeterChange(style: .rhythmSectionSheet)
        var chart = fixture.chart
        let rightID = try XCTUnwrap(chart.splitCommittedRhythmSectionMeasure(fixture.firstID, atFraction: 0.5))

        try assertOriginalMeterBoundary(chart: chart, firstID: fixture.firstID, rightID: rightID,
            followingID: fixture.followingID, changeID: fixture.changeID)
    }

    #if canImport(PencilKit) && canImport(UIKit)
    func testManualSimpleDividerKeepsMeterChordArchivesAndRangesAfterFileReopen() throws {
        try assertSimpleDividerCommitAndFileReopen(automatic: false)
    }

    func testAutomaticSimpleDividerKeepsMeterChordArchivesAndRangesAfterFileReopen() throws {
        try assertSimpleDividerCommitAndFileReopen(automatic: true)
    }

    private func assertSimpleDividerCommitAndFileReopen(automatic: Bool) throws {
        let fixture = try chartWithFollowingMeterChange(style: .simpleChordSheet)
        var chart = fixture.chart
        let cSource = PKDrawing(strokes: [stroke([
            CGPoint(x: 30, y: 10), CGPoint(x: 10, y: 15), CGPoint(x: 10, y: 30), CGPoint(x: 30, y: 35)
        ], seed: 310)])
        let gSource = PKDrawing(strokes: [stroke([
            CGPoint(x: 100, y: 10), CGPoint(x: 80, y: 15), CGPoint(x: 80, y: 35),
            CGPoint(x: 100, y: 35), CGPoint(x: 100, y: 25), CGPoint(x: 92, y: 25)
        ], seed: 320), stroke([CGPoint(x: 107, y: 10), CGPoint(x: 120, y: 10), CGPoint(x: 110, y: 35)], seed: 321)])
        let cID = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("C"),
            rawInput: "C", to: fixture.firstID, atFraction: 0.18, sourceInkData: cSource.dataRepresentation(),
            sourceCandidateSignature: ["C"], spellingIntent: .explicit))
        let gID = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("G7"),
            rawInput: "G7", to: fixture.firstID, atFraction: 0.76, sourceInkData: gSource.dataRepresentation(),
            sourceCandidateSignature: ["G7"]))
        _ = chart.setChordEventManualLaneFraction(0.18, for: cID)
        _ = chart.setChordEventManualLaneFraction(0.76, for: gID)
        let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: fixture.firstID, endMeasureID: fixture.firstID))
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: fixture.firstID,
            endMeasureID: fixture.firstID, displayText: "1., 3.", endStyle: .open))
        for (id, seed) in [(repeatID, 330), (endingID, 340)] {
            let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == id })
            chart.roadmapObjects[index].sourceInkData = PKDrawing(strokes: [stroke([
                CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 5), CGPoint(x: 25, y: 20)
            ], seed: seed)]).dataRepresentation()
        }
        let originalChords = try XCTUnwrap(chart.measure(id: fixture.firstID)).chordEvents
        let originalRanges = chart.roadmapObjects
        let size = CGSize(width: 932, height: 1_400)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == fixture.firstID })
        let cGlyph = try XCTUnwrap(measure.chordLayouts.first { $0.id == cID })
        let gGlyph = try XCTUnwrap(measure.chordLayouts.first { $0.id == gID })
        let x = (cGlyph.frame.maxX + gGlyph.frame.minX) / 2
        XCTAssertGreaterThan(gGlyph.frame.minX, cGlyph.frame.maxX)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system,
            paperFrame: layout.paperFrame(for: system)))
        let halfHeight = lane.height * 0.42
        let source = LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: [stroke([
            CGPoint(x: x - region.frame.minX, y: lane.midY - halfHeight - region.frame.minY),
            CGPoint(x: x - region.frame.minX, y: lane.midY + halfHeight - region.frame.minY)
        ], seed: 350)]))
        let space = try XCTUnwrap(PersistentInkCoordinateSpace(size: region.frame.size))
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(source.dataRepresentation(), coordinateSpace: space))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library-state.json")
        let repository = FileChartRepository(url: url)
        try repository.saveSnapshot(.init(charts: [chart], selectedChartID: chart.id, entitlements: .free))
        chart = try XCTUnwrap(try FileChartRepository(url: url).loadSnapshot()?.charts.first)
        let current = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: current))
        let preparation = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: .now,
            requestedDelay: 0, drawingData: current.dataRepresentation(), chordFrame: region.frame,
            pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: chart.layoutStyle))
        XCTAssertEqual(preparation.barlines.count, 1)
        XCTAssertEqual(preparation.recognitionStrokeCount, 0)
        let state = ChordPreviewState(draftBarlines: preparation.barlines, layoutPageSize: size)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        let outcome: ChordInkDraftRenderCoordinator.Outcome
        if automatic {
            let inputAt = Date(timeIntervalSinceReferenceDate: 100)
            let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
                currentDrawing: current, coordinateSpace: space, now: inputAt.addingTimeInterval(4),
                lastInputAt: inputAt, isUsingTool: false, sourcePageLayout: layout, sourceChordFrame: region.frame)
            outcome = ChordInkDraftRenderCoordinator.explicitOutcome(try XCTUnwrap(attempt.outcome,
                "The divider must render in Automatic. Feedback: \(attempt.feedback)"))
        } else {
            outcome = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: state,
                currentDrawing: current, coordinateSpace: space, sourcePageLayout: layout, sourceChordFrame: region.frame)
        }
        XCTAssertTrue(outcome.canConsumeSource)
        XCTAssertNil(outcome.retainedDraft)
        XCTAssertEqual(outcome.result.renderedBarlineCount, 1)
        XCTAssertEqual(outcome.result.renderedChordCount, 0)
        XCTAssertTrue(outcome.result.unresolvedDraftIDs.isEmpty)
        XCTAssertNil(outcome.chart.pageHandwrittenChordData)
        let rightID = try XCTUnwrap(outcome.chart.measures.dropFirst().first?.id)
        try assertOriginalMeterBoundary(chart: outcome.chart, firstID: fixture.firstID, rightID: rightID,
            followingID: fixture.followingID, changeID: fixture.changeID)
        try repository.saveSnapshot(.init(charts: [outcome.chart], selectedChartID: chart.id, entitlements: .free))
        let snapshot = try XCTUnwrap(try FileChartRepository(url: url).loadSnapshot())
        XCTAssertEqual(snapshot.selectedChartID, chart.id)
        let reopened = try XCTUnwrap(snapshot.charts.first)
        XCTAssertEqual(reopened, outcome.chart)
        try assertOriginalMeterBoundary(chart: reopened, firstID: fixture.firstID, rightID: rightID,
            followingID: fixture.followingID, changeID: fixture.changeID)
        XCTAssertEqual(reopened.measure(id: fixture.firstID)?.chordEvents.map(\.id), [cID])
        XCTAssertEqual(reopened.measure(id: rightID)?.chordEvents.map(\.id), [gID])
        for original in originalChords {
            let matches = reopened.measures.flatMap(\.chordEvents).filter { $0.id == original.id }
            XCTAssertEqual(matches.count, 1)
            let saved = try XCTUnwrap(matches.first)
            XCTAssertEqual(saved.symbol, original.symbol)
            XCTAssertEqual(saved.rawInput, original.rawInput)
            XCTAssertEqual(saved.spellingIntent, original.spellingIntent)
            XCTAssertEqual(saved.sourceCandidateSignature, original.sourceCandidateSignature)
            XCTAssertEqual(saved.sourceRecognitionPipelineVersion, original.sourceRecognitionPipelineVersion)
            XCTAssertEqual(saved.sourceInkData, original.sourceInkData)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: try PKDrawing(data: XCTUnwrap(original.sourceInkData)),
                current: try PKDrawing(data: XCTUnwrap(saved.sourceInkData))))
        }
        for original in originalRanges {
            let saved = try XCTUnwrap(reopened.roadmapObjects.first { $0.id == original.id })
            XCTAssertEqual(saved.startMeasureID, fixture.firstID)
            XCTAssertEqual(saved.endMeasureID, rightID)
            XCTAssertEqual(saved.type, original.type)
            XCTAssertEqual(saved.displayText, original.displayText)
            XCTAssertEqual(saved.count, original.count)
            XCTAssertEqual(saved.endingEndStyle, original.endingEndStyle)
            XCTAssertEqual(saved.sourceInkData, original.sourceInkData)
            XCTAssertTrue(try XCTUnwrap(reopened.measure(id: fixture.firstID)).roadmapObjectIDs.contains(original.id))
            XCTAssertTrue(try XCTUnwrap(reopened.measure(id: rightID)).roadmapObjectIDs.contains(original.id))
        }
    }

    private func stroke(_ points: [CGPoint], seed: Int) -> PKStroke {
        let path = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 2.5, height: 2.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: path, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
    }
    #endif

    private func chartWithFollowingMeterChange(style: ChartLayoutStyle) throws
        -> (chart: Chart, firstID: UUID, followingID: UUID, changeID: UUID) {
        var chart = Chart.blank(title: "Split before meter change", measureCount: 2, layoutStyle: style)
        let firstID = chart.measures[0].id
        let followingID = chart.measures[1].id
        XCTAssertEqual(chart.applyMeterChange(Meter(numerator: 3, denominator: 4),
            after: firstID, scope: .toEndOfPiece), followingID)
        let change = try XCTUnwrap(chart.timeSignatureChanges.first)
        XCTAssertEqual(change.afterMeasureID, firstID)
        XCTAssertEqual(chart.measure(id: firstID)?.resolvedMeter(defaultMeter: chart.defaultMeter),
            Meter(numerator: 4, denominator: 4))
        XCTAssertEqual(chart.measure(id: followingID)?.resolvedMeter(defaultMeter: chart.defaultMeter),
            Meter(numerator: 3, denominator: 4))
        return (chart, firstID, followingID, change.id)
    }

    private func assertOriginalMeterBoundary(
        chart: Chart, firstID: UUID, rightID: UUID, followingID: UUID, changeID: UUID,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(chart.measures.map(\.id), [firstID, rightID, followingID], file: file, line: line)
        XCTAssertEqual(chart.measure(id: firstID)?.resolvedMeter(defaultMeter: chart.defaultMeter),
            Meter(numerator: 4, denominator: 4), file: file, line: line)
        XCTAssertEqual(chart.measure(id: rightID)?.resolvedMeter(defaultMeter: chart.defaultMeter),
            Meter(numerator: 4, denominator: 4),
            "The inserted right segment still belongs to the original 4/4 measure", file: file, line: line)
        XCTAssertEqual(chart.measure(id: followingID)?.resolvedMeter(defaultMeter: chart.defaultMeter),
            Meter(numerator: 3, denominator: 4), file: file, line: line)
        XCTAssertEqual(chart.timeSignatureChanges.count, 1, file: file, line: line)
        XCTAssertEqual(chart.timeSignatureChanges.first?.id, changeID, file: file, line: line)
        XCTAssertEqual(chart.timeSignatureChanges.first?.afterMeasureID, rightID,
            "The existing meter-change receipt must move after the complete original material", file: file, line: line)
    }
}

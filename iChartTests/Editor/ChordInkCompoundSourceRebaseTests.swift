#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// A selected structural subset changes the adapter's drawing-relative time
/// origin. The receipt must still describe the same exact original strokes.
@MainActor
final class ChordInkCompoundSourceRebaseTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_400)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testDoubleBarReceiptSurvivesWithholdingAnEarlierUnrelatedSource() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let originalChart = fixture.chart
            let originalSource = fixture.source.dataRepresentation()
            let selected = PKDrawing(strokes: Array(fixture.source.strokes.dropFirst()))
            let remapped = ChordDraftBarlineDeletionPolicy.remappingSourceIndices(
                fixture.state.draftBarlines, afterRemoving: [0])
            XCTAssertEqual(remapped.count, 1, style.rawValue)
            XCTAssertEqual(remapped.first?.ownedSourceStrokeIndices, [0, 1])
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: PKDrawing(strokes: [fixture.source.strokes[1], fixture.source.strokes[2]]),
                current: selected), "Withholding another source must not alter either double-bar stroke")

            // Establish that the exact selected strokes are recognizable and
            // placeable before checking their receipt from the larger drawing.
            let fresh = prepare(selected, chart: fixture.chart, geometry: fixture.geometry)
            XCTAssertEqual(fresh.barlines.map(\.kind), [.double], style.rawValue)
            let freshState = ChordPreviewState(draftBarlines: fresh.barlines, layoutPageSize: pageSize)
            let control = ChordInkDraftRenderCoordinator.prepare(chart: fixture.chart, state: freshState,
                currentDrawing: selected, coordinateSpace: .init(size: fixture.geometry.frame.size))
            XCTAssertTrue(control.canConsumeSource,
                "\(style): a fresh receipt proves this is valid, placeable double-bar ink")
            XCTAssertEqual(control.result.renderedBarlineCount, 1)

            let remappedState = ChordPreviewState(draftBarlines: remapped, layoutPageSize: pageSize)
            let outcome = ChordInkDraftRenderCoordinator.prepare(chart: fixture.chart, state: remappedState,
                currentDrawing: selected, coordinateSpace: .init(size: fixture.geometry.frame.size))
            XCTAssertTrue(outcome.canConsumeSource,
                "\(style): removing unrelated earliest source must not invalidate unchanged compound source")
            XCTAssertFalse(outcome.result.didRejectIncompleteSourceCoverage,
                "A drawing-relative time-origin change is not a source ownership change")
            XCTAssertEqual(outcome.result.renderedBarlineCount, 1)
            XCTAssertEqual(fixture.chart, originalChart, "Preparation must not mutate the input chart")
            XCTAssertEqual(fixture.source.dataRepresentation(), originalSource,
                "Preparation must not mutate the caller's source drawing")
        }
    }

    func testIndependentDoubleBarRendersAndRetainsEarlierUnreadSourceThroughReopen() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let originalChart = fixture.chart
            let originalSource = fixture.source.dataRepresentation()
            let maybeOutcome = ChordInkDraftRenderCoordinator.prepareIndependentChords(
                chart: fixture.chart, state: fixture.state, currentDrawing: fixture.source,
                coordinateSpace: .init(size: fixture.geometry.frame.size),
                sourcePageLayout: fixture.geometry.layout, sourceChordFrame: fixture.geometry.frame)
            XCTAssertNotNil(maybeOutcome,
                "\(style): an unrelated unread source cannot prevent exact double-bar progress")
            guard let outcome = maybeOutcome else { continue }
            XCTAssertTrue(outcome.canConsumeSource, style.rawValue)
            XCTAssertEqual(outcome.result.renderedBarlineCount, 1)
            XCTAssertEqual(outcome.result.renderedChordCount, 0)
            XCTAssertTrue(outcome.chart.measures.contains { $0.barlineAfter == .double })
            let retained = try XCTUnwrap(outcome.retainedDraft)
            let expected = PKDrawing(strokes: [fixture.source.strokes[0]])
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: expected, current: retained.drawing))
            XCTAssertEqual(retained.state.draftChords.map(\.id), fixture.state.draftChords.map(\.id))
            XCTAssertTrue(retained.state.draftBarlines.isEmpty)
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(outcome.chart))
            let persisted = try PKDrawing(data: XCTUnwrap(reopened.pageHandwrittenChordData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: expected, current: persisted))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(
                chart: reopened, state: retained.state))
            XCTAssertEqual(reopened, outcome.chart)
            XCTAssertEqual(fixture.chart, originalChart)
            XCTAssertEqual(fixture.source.dataRepresentation(), originalSource)
        }
    }

    func testRebasedDoubleBarReceiptStillRejectsChangedPointsAndInterStrokeInterval() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let originalChart = fixture.chart
            let selected = PKDrawing(strokes: Array(fixture.source.strokes.dropFirst()))
            let remapped = ChordDraftBarlineDeletionPolicy.remappingSourceIndices(
                fixture.state.draftBarlines, afterRemoving: [0])
            let oldState = ChordPreviewState(draftBarlines: remapped, layoutPageSize: pageSize)
            for changesInterval in [false, true] {
                let target = selected.strokes[1]
                let changedPoints: [PKStrokePoint]
                if changesInterval {
                    changedPoints = Array(target.path)
                } else {
                    changedPoints = target.path.map { point in
                        PKStrokePoint(location: CGPoint(x: point.location.x + 0.25, y: point.location.y),
                            timeOffset: point.timeOffset, size: point.size, opacity: point.opacity,
                            force: point.force, azimuth: point.azimuth, altitude: point.altitude)
                    }
                }
                let changed = PKStroke(ink: target.ink,
                    path: PKStrokePath(controlPoints: changedPoints,
                        creationDate: target.path.creationDate.addingTimeInterval(changesInterval ? 0.10 : 0)),
                    transform: target.transform, mask: target.mask, randomSeed: target.randomSeed)
                let live = PKDrawing(strokes: [selected.strokes[0], changed])
                let liveBytes = live.dataRepresentation()
                XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: selected, current: live), "The negative control must change real source")

                let fresh = prepare(live, chart: fixture.chart, geometry: fixture.geometry)
                XCTAssertEqual(fresh.barlines.map(\.kind), [.double], style.rawValue)
                let freshState = ChordPreviewState(draftBarlines: fresh.barlines, layoutPageSize: pageSize)
                let control = ChordInkDraftRenderCoordinator.prepare(chart: fixture.chart, state: freshState,
                    currentDrawing: live, coordinateSpace: .init(size: fixture.geometry.frame.size))
                XCTAssertTrue(control.canConsumeSource,
                    "The changed ink is independently valid; its old receipt must still be rejected")
                let stale = ChordInkDraftRenderCoordinator.prepare(chart: fixture.chart, state: oldState,
                    currentDrawing: live, coordinateSpace: .init(size: fixture.geometry.frame.size))
                XCTAssertFalse(stale.canConsumeSource,
                    "\(style): normalization must retain exact \(changesInterval ? "inter-stroke intervals" : "points")")
                XCTAssertTrue(stale.result.didRejectIncompleteSourceCoverage)
                XCTAssertEqual(stale.chart, originalChart)
                XCTAssertEqual(live.dataRepresentation(), liveBytes)
            }
        }
    }

    private struct Geometry {
        var layout: LeadSheetPageLayout
        var frame: CGRect
        var lane: CGRect
    }

    private struct Fixture {
        var chart: Chart
        var source: PKDrawing
        var state: ChordPreviewState
        var geometry: Geometry
    }

    private func makeFixture(_ style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.draft(title: "Compound source receipt", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: .init(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 3)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let geometry = Geometry(layout: layout,
            frame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), lane: lane)
        let first = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == chart.measures[0].id })
        let last = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == chart.measures[2].id })
        let unreadCenter = CGPoint(x: last.staffFrame.midX, y: lane.midY)
        let unread = stroke([
            CGPoint(x: unreadCenter.x - 7, y: unreadCenter.y - 5),
            CGPoint(x: unreadCenter.x + 7, y: unreadCenter.y + 5),
            CGPoint(x: unreadCenter.x - 7, y: unreadCenter.y + 5),
            CGPoint(x: unreadCenter.x + 7, y: unreadCenter.y - 5)
        ], geometry: geometry, createdAt: 10_000, seed: 10)
        let height = lane.height * 0.84
        let bars = [CGFloat(0), 7].enumerated().map { index, offset in
            let x = first.staffFrame.midX + offset
            return stroke([CGPoint(x: x, y: lane.midY - height / 2),
                CGPoint(x: x, y: lane.midY + height / 2)], geometry: geometry,
                createdAt: 10_001 + Double(index) * 0.06, seed: UInt32(11 + index))
        }
        let source = PKDrawing(strokes: [unread] + bars)
        _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation(),
            coordinateSpace: .init(size: geometry.frame.size), assumesNormalizedPersistentInk: true)
        let prepared = prepare(source, chart: chart, geometry: geometry)
        XCTAssertEqual(prepared.barlines.map(\.kind), [.double], style.rawValue)
        XCTAssertEqual(prepared.barlines.first?.ownedSourceStrokeIndices, [1, 2])
        XCTAssertFalse(try XCTUnwrap(prepared.barlines.first).sourceStrokeGeometry.isEmpty,
            "This fixture must exercise a compound receipt rather than a plain bar index")
        var state = ChordPreviewState(draftBarlines: prepared.barlines, layoutPageSize: pageSize)
        guard case .ready(let requests, _) = prepared.outcome else {
            throw FixtureError.missingUnreadTarget
        }
        XCTAssertEqual(requests.count, 1, style.rawValue)
        state.replaceDraftChords(with: requests.map { request in
            ChordInkDraftInput(measureID: request.target.measureID,
                measureIndex: (chart.measures.firstIndex { $0.id == request.target.measureID } ?? 0) + 1,
                targetFraction: request.target.fraction, visualOrder: request.visualOrder,
                laneLocation: request.laneLocation, layoutPageSize: pageSize,
                drawingData: request.drawingData, candidateTexts: [], bestCandidateText: nil,
                confidence: 0, strokeCount: request.strokes.count,
                targetLifecycle: request.collectingTargetLifecycle.advanced(to: .stable))
        })
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        return Fixture(chart: chart, source: source, state: state, geometry: geometry)
    }

    private enum FixtureError: Error { case missingUnreadTarget }

    private func prepare(_ drawing: PKDrawing, chart: Chart,
        geometry: Geometry) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: .now,
            requestedDelay: 0, drawingData: drawing.dataRepresentation(), chordFrame: geometry.frame,
            pageLayout: geometry.layout, flow: .draftPreview, options: .live, layoutStyle: chart.layoutStyle))
    }

    private func stroke(_ locations: [CGPoint], geometry: Geometry,
        createdAt: TimeInterval, seed: UInt32) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: CGPoint(x: location.x - geometry.frame.minX,
                    y: location.y - geometry.frame.minY), timeOffset: Double(index) * 0.05,
                size: .init(width: 2.5, height: 2.5), opacity: 1, force: 1,
                azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: .init(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points,
                creationDate: Date(timeIntervalSinceReferenceDate: createdAt)),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif

#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Exercises the production overlay/router and width-only persistence contract.
/// Physical Pencil reachability is a separate device acceptance check.
@MainActor
final class ChordResizeReachabilityTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_200)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testSelectedSideHandlesRemainReachableWhenAnotherMeasureChordCoversTheirUsualPosition() throws {
        for style in styles {
            for coveredEdge in [ActiveChordResizeDrag.Edge.leading, .trailing] {
                let fixture = try fixture(style: style)
                var page = LeadSheetPageLayoutEngine.pageLayout(for: fixture.chart, pageSize: pageSize)
                let sourceMeasure = try measure(fixture.measureID, in: page)
                let selectedFrame = CGRect(x: sourceMeasure.trailingBarlineFrame.midX - 32,
                    y: sourceMeasure.chordBandFrame.minY + 2, width: 86, height: 30)
                let neighborFrame = CGRect(
                    x: coveredEdge == .leading ? selectedFrame.minX - 32 : selectedFrame.maxX - 8,
                    y: selectedFrame.minY, width: 42, height: selectedFrame.height)
                replaceFrame(for: fixture.chordID, with: selectedFrame, in: &page)
                replaceFrame(for: fixture.neighborID, with: neighborFrame, in: &page)
                let selected = try chord(fixture.chordID, in: page)
                XCTAssertGreaterThan(selected.frame.maxX, sourceMeasure.trailingBarlineFrame.midX,
                    "The selected chord must genuinely cross the measure boundary in this regression")
                for screenScale: CGFloat in [0.5, 1, 2.5] {
                    let controls = LeadSheetChordEditOverlayGeometry.controlFrames(
                        for: selected, in: page, screenPointsPerDisplayedPoint: screenScale)
                    let context = RenderedEditContext(pageLayout: page, layoutStyle: style,
                        selection: .init(selectedObjectID: .chord(fixture.chordID)),
                        screenPointsPerDisplayedPoint: screenScale, allowsUnselectedChordMove: true)
                    let router = RenderedEditRouter(providers: [ChordRenderedEditHitTargetProvider()])
                    for (frame, action) in [(controls.leadingResize, RenderedEditAction.resizeLeading),
                        (controls.trailingResize, .resizeTrailing)] {
                        let point = CGPoint(x: frame.midX, y: frame.midY)
                        XCTAssertTrue(page.pageBounds.contains(frame))
                        XCTAssertFalse(neighborFrame.contains(point),
                            "A visible resize handle must have its own usable location outside the neighbor glyph")
                        let target = try XCTUnwrap(router.dragTarget(at: point, in: context))
                        XCTAssertEqual(target.objectID, .chord(fixture.chordID))
                        XCTAssertEqual(target.action, action)
                        XCTAssertEqual(target.mutationRisk, .visual)
                    }

                    let neighborPoint = CGPoint(
                        x: coveredEdge == .leading ? neighborFrame.minX + 3 : neighborFrame.maxX - 3,
                        y: neighborFrame.midY)
                    XCTAssertFalse(selectedFrame.contains(neighborPoint))
                    let neighborTap = try XCTUnwrap(router.tapTarget(at: neighborPoint, in: context))
                    XCTAssertEqual(neighborTap.objectID, .chord(fixture.neighborID))
                    XCTAssertEqual(neighborTap.action, .select)
                    let neighborMove = try XCTUnwrap(router.dragTarget(at: neighborPoint, in: context))
                    XCTAssertEqual(neighborMove.objectID, .chord(fixture.neighborID))
                    XCTAssertEqual(neighborMove.action, .move)
                }
            }
        }
    }

    func testBothHandlesStayReachableAtPaperEdgesWithoutTakingTheNarrowChordBody() throws {
        for style in styles {
            for width: CGFloat in [3, 14, 90] {
                for isRightEdge in [false, true] {
                    let fixture = try fixture(style: style)
                    var page = LeadSheetPageLayoutEngine.pageLayout(for: fixture.chart, pageSize: pageSize)
                    let frame = CGRect(x: isRightEdge ? page.pageBounds.maxX - width - 2 : 2,
                        y: 220, width: width, height: 30)
                    replaceFrame(for: fixture.chordID, with: frame, in: &page)
                    let selected = try chord(fixture.chordID, in: page)
                    let controls = LeadSheetChordEditOverlayGeometry.controlFrames(
                        for: selected, in: page)
                    let context = RenderedEditContext(pageLayout: page, layoutStyle: style,
                        selection: .init(selectedObjectID: .chord(fixture.chordID)),
                        allowsUnselectedChordMove: true)
                    let router = RenderedEditRouter(providers: [ChordRenderedEditHitTargetProvider()])
                    for (handle, action) in [(controls.leadingResize, RenderedEditAction.resizeLeading),
                        (controls.trailingResize, .resizeTrailing)] {
                        XCTAssertTrue(page.pageBounds.contains(handle))
                        let point = CGPoint(x: handle.midX, y: handle.midY)
                        XCTAssertFalse(frame.contains(point))
                        XCTAssertEqual(router.dragTarget(at: point, in: context)?.objectID, .chord(fixture.chordID))
                        XCTAssertEqual(router.dragTarget(at: point, in: context)?.action, action)
                    }
                    let bodyPoint = CGPoint(x: frame.midX, y: frame.midY)
                    XCTAssertEqual(router.tapTarget(at: bodyPoint, in: context)?.action, .select)
                    XCTAssertEqual(router.dragTarget(at: bodyPoint, in: context)?.action, .move)
                    XCTAssertNotEqual(router.tapTarget(at: bodyPoint, in: context)?.action, .delete)
                }
            }
        }
    }

    func testLeadingAndTrailingWidthChangesHoldTheOppositeVisibleEdgeAndHeight() throws {
        for style in styles {
            let fixture = try fixture(style: style)
            let page = LeadSheetPageLayoutEngine.pageLayout(for: fixture.chart, pageSize: pageSize)
            let original = CGRect(x: 150, y: 180, width: 100, height: 32)
            for edge in [ActiveChordResizeDrag.Edge.leading, .trailing] {
                let start = CGPoint(x: edge == .leading ? original.minX : original.maxX, y: original.midY)
                let drag = ActiveChordResizeDrag(chordID: fixture.chordID, sourcePageLayout: page,
                    edge: edge, initialFrame: original, currentFrame: original,
                    startLocation: start, initialHorizontalScale: 0.8)
                let end = CGPoint(x: start.x + (edge == .leading ? 12 : -12), y: start.y + 40)
                let preview = LeadSheetChordResizeDragPolicy.previewFrame(
                    for: drag, at: end, boundedBy: page.paperFrame)
                XCTAssertEqual(preview.width, 88, accuracy: 0.001)
                XCTAssertEqual(preview.height, original.height, accuracy: 0.001)
                XCTAssertEqual(preview.minY, original.minY, accuracy: 0.001)
                if edge == .leading {
                    XCTAssertEqual(preview.maxX, original.maxX, accuracy: 0.001)
                } else {
                    XCTAssertEqual(preview.minX, original.minX, accuracy: 0.001)
                }
            }
        }
    }

    func testBothResizeEdgesReopenWithThePreviewWidthAndPreserveMusicNeighborsAndInk() throws {
        for style in styles {
            let fixture = try fixture(style: style)
            let originalChart = fixture.chart
            let page = LeadSheetPageLayoutEngine.pageLayout(for: originalChart, pageSize: pageSize)
            let original = try chord(fixture.chordID, in: page)
            let sourceMeasure = try measure(fixture.measureID, in: page)
            let beforeEvent = try XCTUnwrap(originalChart.chordEvent(id: fixture.chordID))
            let beforeNeighbor = try XCTUnwrap(originalChart.chordEvent(id: fixture.neighborID))
            XCTAssertGreaterThan(original.frame.maxX, sourceMeasure.trailingBarlineFrame.midX)

            for edge in [ActiveChordResizeDrag.Edge.leading, .trailing] {
                let start = CGPoint(x: edge == .leading ? original.frame.minX : original.frame.maxX,
                    y: original.frame.midY)
                var drag = ActiveChordResizeDrag(chordID: fixture.chordID, sourcePageLayout: page,
                    edge: edge, initialFrame: original.frame, currentFrame: original.frame,
                    startLocation: start, initialHorizontalScale: original.horizontalCompressionScale)
                drag.currentFrame = LeadSheetChordResizeDragPolicy.previewFrame(for: drag,
                    at: CGPoint(x: start.x + (edge == .leading ? 6 : -6), y: start.y),
                    boundedBy: page.paperFrame)
                var resized = originalChart
                let horizontalScale = LeadSheetChordResizeDragPolicy.horizontalScale(for: drag)
                XCTAssertNotNil(resized.setChordEventManualHorizontalScale(horizontalScale, for: fixture.chordID))
                let placement = try XCTUnwrap(LeadSheetChordResizeDragPolicy.visualPlacement(for: drag))
                XCTAssertEqual(placement.measureID, fixture.measureID)
                XCTAssertTrue(resized.moveChordEventInCommittedChordLane(fixture.chordID,
                    to: placement.measureID, atFraction: nil, visualFraction: placement.fraction,
                    preserveMusicalPlacement: true, allowsLeadingVisualInset: edge == .leading ? true : nil))
                XCTAssertEqual(resized.chordEvent(id: fixture.chordID)?.sourceInkData, beforeEvent.sourceInkData)
                XCTAssertEqual(resized.pageHandwrittenChordData, originalChart.pageHandwrittenChordData)
                XCTAssertEqual(resized.measure(id: fixture.measureID)?.handwrittenRhythmicNotationData,
                    originalChart.measure(id: fixture.measureID)?.handwrittenRhythmicNotationData,
                    "Resizing itself must preserve every original ink archive byte")
                let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(resized))
                let after = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
                let rendered = try chord(fixture.chordID, in: after)

                XCTAssertEqual(rendered.frame.minX, drag.currentFrame.minX, accuracy: 0.001)
                XCTAssertEqual(rendered.frame.maxX, drag.currentFrame.maxX, accuracy: 0.001)
                XCTAssertEqual(rendered.frame.height, original.frame.height, accuracy: 0.001)
                XCTAssertEqual(rendered.frame.midY, original.frame.midY, accuracy: 0.001)
                XCTAssertEqual(reopened.measureContainingChordEvent(id: fixture.chordID)?.id, fixture.measureID)
                XCTAssertEqual(reopened.chordEvent(id: fixture.neighborID), beforeNeighbor)
                XCTAssertEqual(try chord(fixture.neighborID, in: after).frame,
                    try chord(fixture.neighborID, in: page).frame)
                var expected = beforeEvent
                expected.manualHorizontalScale = horizontalScale
                expected.manualDisplayScale = nil
                expected.manualDisplayWidth = nil
                expected.manualVisualLaneFraction = placement.fraction
                expected.manualVisualAllowsLeadingInset = edge == .leading ? true : beforeEvent.manualVisualAllowsLeadingInset
                let reopenedEvent = try XCTUnwrap(reopened.chordEvent(id: fixture.chordID))
                XCTAssertEqual(try XCTUnwrap(reopenedEvent.manualHorizontalScale), horizontalScale, accuracy: 1e-12)
                XCTAssertEqual(try XCTUnwrap(reopenedEvent.manualVisualLaneFraction), placement.fraction, accuracy: 1e-12)
                // JSON's numeric parser may round a Double by one ULP. Keep
                // musical/source-field equality exact after verifying those
                // two intentionally mutable geometry values numerically.
                expected.manualHorizontalScale = reopenedEvent.manualHorizontalScale
                expected.manualVisualLaneFraction = reopenedEvent.manualVisualLaneFraction
                XCTAssertEqual(reopenedEvent, expected,
                    "Resize must retain symbol, musical timing, and original source strokes")
                XCTAssertEqual(reopened.pageHandwrittenChordData, originalChart.pageHandwrittenChordData)
                XCTAssertEqual(reopened.measure(id: fixture.measureID)?.handwrittenRhythmicNotationData,
                    originalChart.measure(id: fixture.measureID)?.handwrittenRhythmicNotationData)
                XCTAssertEqual(after.systems.flatMap(\.measures).map(\.frame), page.systems.flatMap(\.measures).map(\.frame))
            }
        }
    }

    private struct Fixture {
        let chart: Chart
        let measureID: UUID
        let chordID: UUID
        let neighborID: UUID
    }

    private func fixture(style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.blank(title: "Overlapping resize", measureCount: 4, layoutStyle: style)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let neighborMeasureID = try XCTUnwrap(chart.measures.dropFirst().first?.id)
        let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(
            try ChordSymbolParser.parse("Bbmaj7(#11)/D"), rawInput: "Bbmaj7(#11)/D",
            to: measureID, atFraction: 0.25))
        let neighborID = try XCTUnwrap(chart.appendRecognizedChordEvent(
            try ChordSymbolParser.parse("G7"), rawInput: "G7", to: neighborMeasureID, atFraction: 0.05))
        _ = chart.setChordEventManualHorizontalScale(0.8, for: chordID)
        XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: measureID,
            atFraction: nil, visualFraction: 0.85, preserveMusicalPlacement: true))
        let ink = sourceDrawing().dataRepresentation()
        XCTAssertFalse(LeadSheetPersistentInkColorPolicy.needsNormalization(try PKDrawing(data: ink)),
            "This saved-ink fixture must already use the production persistent color")
        chart.systems[0].measures[0].chordEvents[0].sourceInkData = ink
        chart.pageHandwrittenChordData = ink
        chart.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_200)
        chart.systems[0].measures[0].handwrittenRhythmicNotationData = ink
        chart.systems[0].measures[0].handwrittenRhythmicNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 180, height: 80)
        return Fixture(chart: chart, measureID: measureID, chordID: chordID, neighborID: neighborID)
    }

    private func chord(_ id: UUID, in page: LeadSheetPageLayout) throws -> LeadSheetChordLayout {
        try XCTUnwrap(page.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == id })
    }

    private func measure(_ id: UUID, in page: LeadSheetPageLayout) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(page.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func replaceFrame(for chordID: UUID, with frame: CGRect, in page: inout LeadSheetPageLayout) {
        for systemIndex in page.systems.indices {
            for measureIndex in page.systems[systemIndex].measures.indices {
                if let chordIndex = page.systems[systemIndex].measures[measureIndex].chordLayouts.firstIndex(where: { $0.id == chordID }) {
                    page.systems[systemIndex].measures[measureIndex].chordLayouts[chordIndex].frame = frame
                    page.systems[systemIndex].measures[measureIndex].chordLayouts[chordIndex].fitFrame = frame
                    page.systems[systemIndex].measures[measureIndex].chordLayouts[chordIndex].naturalFrame = frame
                }
            }
        }
    }

    private func sourceDrawing() -> PKDrawing {
        let points = [CGPoint(x: 24, y: 24), CGPoint(x: 40, y: 12), CGPoint(x: 52, y: 40)]
            .enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 10)),
            transform: .identity, mask: nil, randomSeed: 17)])
    }
}
#endif

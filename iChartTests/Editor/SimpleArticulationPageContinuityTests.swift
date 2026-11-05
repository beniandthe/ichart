#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class SimpleArticulationPageContinuityTests: XCTestCase {
    func testDeletingFinalPageChordAndMeasurePreservesRenderedAndOriginalPaperPositions() throws {
        for kind in [FreeInkArticulationKind.fermata, .accent] {
            var fixture = try makeTwoPageFixture(kind: kind)
            let originalLayout = canonicalLayout(for: fixture.chart)
            let originalMark = try XCTUnwrap(fixture.chart.freeInkArticulations.first)
            let originalTarget = try XCTUnwrap(FreeInkArticulationPlacement.target(
                for: originalMark, chart: fixture.chart, pageLayout: originalLayout))
            let visiblePoint = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(
                at: originalTarget.center, pageLayout: originalLayout))
            XCTAssertEqual(visiblePoint.pageIndex, 1)
            XCTAssertEqual(originalMark.sourcePagePoint?.pageIndex, 1)

            // The normal canvas/inspector path snapshots the actually engraved
            // position before removing a target. The source stays independent.
            fixture.chart = FreeInkArticulationPlacement.preservingVisiblePagePoints(
                in: fixture.chart, pageLayout: originalLayout)
            XCTAssertTrue(fixture.chart.deleteChordEvent(fixture.chordID))
            let afterChordDeletion = try XCTUnwrap(fixture.chart.freeInkArticulations.first)
            XCTAssertNil(afterChordDeletion.attachment)
            XCTAssertEqual(afterChordDeletion.pagePoint, visiblePoint)
            XCTAssertEqual(afterChordDeletion.sourcePagePoint, originalMark.sourcePagePoint)
            XCTAssertEqual(afterChordDeletion.sourceInkData, originalMark.sourceInkData)

            fixture.chart = FreeInkArticulationPlacement.preservingVisiblePagePoints(
                in: fixture.chart, pageLayout: canonicalLayout(for: fixture.chart))
            XCTAssertTrue(fixture.chart.deleteMeasure(id: fixture.measureID))
            XCTAssertNil(fixture.chart.measure(id: fixture.measureID))

            let snapshot = ChartLibrarySnapshot(charts: [fixture.chart],
                selectedChartID: fixture.chart.id, entitlements: .free)
            let reopened = try ChartPersistenceCoders.decoder.decode(ChartLibrarySnapshot.self,
                from: ChartPersistenceCoders.encoder.encode(snapshot))
            let savedChart = try XCTUnwrap(reopened.charts.first)
            let savedMark = try XCTUnwrap(savedChart.freeInkArticulations.first)
            XCTAssertEqual(savedMark.pagePoint, visiblePoint)
            XCTAssertEqual(savedMark.sourcePagePoint, originalMark.sourcePagePoint)
            XCTAssertEqual(savedMark.sourceInkData, originalMark.sourceInkData)

            for viewportWidth in [CGFloat(500), CGFloat(1_180)] {
                let layout = canonicalLayout(for: savedChart, viewportWidth: viewportWidth)
                XCTAssertEqual(layout.pages.count, 2,
                    "Removing the last measure must retain paper occupied by a rendered mark or its source.")
                let target = try XCTUnwrap(FreeInkArticulationPlacement.target(
                    for: savedMark, chart: savedChart, pageLayout: layout))
                XCTAssertEqual(target.center.x, originalTarget.center.x, accuracy: 0.01)
                XCTAssertEqual(target.center.y, originalTarget.center.y, accuracy: 0.01,
                    "A missing target must not move a final-page mark onto an earlier paper page.")
                let sourcePoint = try XCTUnwrap(savedMark.sourcePagePoint)
                let sourceCenter = try XCTUnwrap(FreeInkArticulationPlacement.center(
                    for: sourcePoint, pageLayout: layout))
                let originalSourceCenter = try XCTUnwrap(FreeInkArticulationPlacement.center(
                    for: sourcePoint, pageLayout: originalLayout))
                XCTAssertEqual(sourceCenter, originalSourceCenter,
                    "Restore Ink must still resolve to the original paper page after save/reopen.")
            }

            try assertRestorationPreservesOriginalDrawing(savedChart,
                originalDrawing: fixture.source, originalLayout: originalLayout)
        }
    }

    func testRemovingFinalPageWithoutArticulationOrFreeInkAllowsPaperToCollapse() throws {
        var chart = Chart.blank(title: "No retained final-page content", measureCount: 8,
            layoutStyle: .simpleChordSheet)
        let finalMeasureID = try XCTUnwrap(chart.appendPage())
        XCTAssertEqual(canonicalLayout(for: chart).pages.count, 2)
        XCTAssertTrue(chart.deleteMeasure(id: finalMeasureID))
        XCTAssertEqual(canonicalLayout(for: chart).pages.count, 1,
            "Empty paper must not be retained merely because a page used to exist.")
    }

    func testFirstPageHandwritingDoesNotRetainAnUnoccupiedFinalPageFromItsOldCanvasSize() throws {
        var fixture = try makeTwoPageFixture(kind: .accent)
        let layout = canonicalLayout(for: fixture.chart)
        let space = try XCTUnwrap(fixture.chart.freeInkArticulations.first?.sourceCoordinateSpace)
        let pageStride = layout.pages[1].frame.minY - layout.pages[0].frame.minY
        fixture.chart.freeInkArticulations = []
        fixture.chart.pageHandwrittenNotationData = fixture.source.transformed(using:
            CGAffineTransform(translationX: 0, y: -pageStride)).dataRepresentation()
        fixture.chart.pageHandwrittenNotationCoordinateSpace = space
        XCTAssertTrue(fixture.chart.deleteMeasure(id: fixture.measureID))
        XCTAssertEqual(canonicalLayout(for: fixture.chart).pages.count, 1,
            "The old two-page drawing capacity must not keep wholly unoccupied paper")
    }

    func testInvalidImportedPaperIndicesDoNotAllocateExtraPages() {
        for index in [-1, Int.max] {
            var chart = Chart.blank(title: "Invalid mark page", measureCount: 4, layoutStyle: .simpleChordSheet)
            chart.freeInkArticulations = [FreeInkArticulation(kind: .accent, sourceInkData: Data([1]),
                pagePoint: .init(pageIndex: index, x: 200, y: 200))]
            XCTAssertEqual(canonicalLayout(for: chart).pages.count, 1)
        }
    }

    func testOriginalSourcePageRemainsRestorableAfterMarkMovesToEarlierPage() throws {
        var fixture = try makeTwoPageFixture(kind: .accent)
        let originalLayout = canonicalLayout(for: fixture.chart)
        let originalMark = try XCTUnwrap(fixture.chart.freeInkArticulations.first)
        let earlierPoint = FreeInkArticulationPagePoint(pageIndex: 0, x: 200, y: 200)
        fixture.chart.freeInkArticulations[0].measureID = nil
        fixture.chart.freeInkArticulations[0].attachment = nil
        fixture.chart.freeInkArticulations[0].pagePoint = earlierPoint
        fixture.chart = FreeInkArticulationPlacement.preservingVisiblePagePoints(
            in: fixture.chart, pageLayout: originalLayout)

        XCTAssertTrue(fixture.chart.deleteMeasure(id: fixture.measureID))
        let mark = try XCTUnwrap(fixture.chart.freeInkArticulations.first)
        XCTAssertEqual(mark.pagePoint, earlierPoint)
        XCTAssertEqual(mark.sourcePagePoint, originalMark.sourcePagePoint)
        XCTAssertEqual(canonicalLayout(for: fixture.chart).pages.count, 2,
            "An archive on otherwise empty final paper remains independently restorable after moving the glyph.")
        try assertRestorationPreservesOriginalDrawing(fixture.chart,
            originalDrawing: fixture.source, originalLayout: originalLayout)
    }

    private struct Fixture {
        var chart: Chart
        let measureID: UUID
        let chordID: UUID
        let source: PKDrawing
    }

    private func makeTwoPageFixture(kind: FreeInkArticulationKind) throws -> Fixture {
        var chart = Chart.blank(title: "Final-page \(kind.rawValue)", measureCount: 8,
            layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.appendPage())
        let symbol = try XCTUnwrap(ChordRecognitionCompendium.match("Cmaj7")?.symbol)
        let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(symbol, rawInput: "Cmaj7",
            to: measureID, atFraction: 0.5))
        let layout = canonicalLayout(for: chart)
        XCTAssertEqual(layout.pages.count, 2)
        let chord = try XCTUnwrap(layout.systems.flatMap(\.measures)
            .flatMap(\.chordLayouts).first(where: { $0.id == chordID }))
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        let localCenter = CGPoint(x: chord.frame.midX - frame.minX,
            y: chord.frame.minY - 16 - frame.minY)
        let path = [CGPoint(x: localCenter.x - 12, y: localCenter.y - 5),
                    CGPoint(x: localCenter.x + 12, y: localCenter.y),
                    CGPoint(x: localCenter.x - 12, y: localCenter.y + 5)]
        let points = path.enumerated().map { offset, point in
            PKStrokePoint(location: point, timeOffset: Double(offset) * 0.1,
                size: CGSize(width: 2, height: 2), opacity: 1, force: 0.7,
                azimuth: 0, altitude: .pi / 2)
        }
        let source = PKDrawing(strokes: [PKStroke(
            ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points,
                creationDate: Date(timeIntervalSinceReferenceDate: 7)),
            transform: .identity, mask: nil, randomSeed: 7)])
        let sourceCenter = CGPoint(x: source.bounds.midX + frame.minX, y: source.bounds.midY + frame.minY)
        let sourcePoint = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(
            at: sourceCenter, pageLayout: layout))
        var sourceSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: layout, relativeTo: frame))
        // Match a real Simple conversion: the last raw mark is consumed, and
        // its archive alone retains the canonical Free Ink document size.
        sourceSpace.measureAnchors = nil
        sourceSpace.chordAnchors = nil
        chart.freeInkArticulations = [FreeInkArticulation(kind: kind, measureID: measureID,
            sourceInkData: source.dataRepresentation(), sourceCoordinateSpace: sourceSpace,
            attachment: .chord(id: chordID), pagePoint: sourcePoint, sourcePagePoint: sourcePoint)]
        XCTAssertNil(chart.pageHandwrittenNotationData)
        XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart),
            layout.pageBounds.width)
        return Fixture(chart: chart, measureID: measureID, chordID: chordID, source: source)
    }

    private func canonicalLayout(for chart: Chart, viewportWidth: CGFloat = 932) -> LeadSheetPageLayout {
        let width = LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
            retainedWidth: nil, chart: chart, viewportWidth: viewportWidth)
        return LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: width, height: 1_400))
    }

    private func assertRestorationPreservesOriginalDrawing(
        _ chart: Chart, originalDrawing: PKDrawing, originalLayout: LeadSheetPageLayout
    ) throws {
        let mark = try XCTUnwrap(chart.freeInkArticulations.first)
        let layout = canonicalLayout(for: chart)
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero,
            size: CGSize(width: layout.pageBounds.width, height: max(1_400, layout.pageBounds.height))))
        view.chart = chart
        view.interactionMode = .freeHand
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertTrue(view.restoreFreeInkArticulation(articulationID: mark.id))
        XCTAssertTrue(view.chart.freeInkArticulations.isEmpty)
        let restored = try PKDrawing(data: XCTUnwrap(view.chart.pageHandwrittenNotationData))
        XCTAssertEqual(restored.strokes.count, originalDrawing.strokes.count)
        for (before, after) in zip(originalDrawing.strokes, restored.strokes) {
            XCTAssertEqual(after.randomSeed, before.randomSeed)
            for (original, actual) in zip(before.path, after.path) {
                let expected = original.location.applying(before.transform)
                let result = actual.location.applying(after.transform)
                XCTAssertEqual(result.x, expected.x, accuracy: 0.01)
                XCTAssertEqual(result.y, expected.y, accuracy: 0.01,
                    "Restoration must not translate the original source onto an earlier page.")
            }
        }
        let restoredLayout = canonicalLayout(for: view.chart)
        XCTAssertEqual(restoredLayout.pages.count, originalLayout.pages.count)
        let inputFrame = LeadSheetActiveInkScope.pageWritingFrame(for: restoredLayout)
        XCTAssertTrue(CGRect(origin: .zero, size: inputFrame.size).contains(restored.bounds),
            "Restored final-page ink must remain inside the editable page canvas.")
    }
}
#endif

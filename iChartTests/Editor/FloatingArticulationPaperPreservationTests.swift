#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class FloatingArticulationPaperPreservationTests: XCTestCase {
    func testDeletingFinalPageKeepsFloatingMarksAndTheirOriginalPaperAfterReopenInBothStyles() throws {
        for style in styles {
            for kind in [FreeInkArticulationKind.fermata, .accent] {
                var fixture = try makeFixture(style: style, kind: kind)
                let before = layout(fixture.chart)
                let originalMark = try XCTUnwrap(fixture.chart.freeInkArticulations.first)
                let originalCenter = try XCTUnwrap(FreeInkArticulationPlacement.target(
                    for: originalMark, chart: fixture.chart, pageLayout: before)).center
                try deleteAppendedPage(in: &fixture)
                let saved = try reopen(fixture.chart)
                XCTAssertEqual(saved.freeInkArticulations, [originalMark],
                    "Deleting unowned paper's measures must not rewrite mark or source records.")
                XCTAssertEqual(saved.measures.map(\.id), fixture.originalMeasureIDs)
                for viewport in [CGFloat(500), 1_180] {
                    let after = layout(saved, viewportWidth: viewport)
                    XCTAssertEqual(after.pages.count, 2)
                    let target = try XCTUnwrap(FreeInkArticulationPlacement.target(
                        for: originalMark, chart: saved, pageLayout: after))
                    XCTAssertEqual(target.center.x, originalCenter.x, accuracy: 0.01)
                    XCTAssertEqual(target.center.y, originalCenter.y, accuracy: 0.01)
                    XCTAssertEqual(FreeInkArticulationPlacement.center(
                        for: try XCTUnwrap(originalMark.sourcePagePoint), pageLayout: after), originalCenter)
                }
            }
        }
    }

    func testRestoreInkKeepsOriginalPaperAndGeometryAfterSaveReopenInBothStyles() throws {
        for style in styles {
            var fixture = try makeFixture(style: style, kind: .accent)
            try deleteAppendedPage(in: &fixture)
            let saved = try reopen(fixture.chart)
            let restored = try restore(saved, expected: fixture.source)
            XCTAssertTrue(restored.freeInkArticulations.isEmpty)
            let reopened = try reopen(restored)
            let after = layout(reopened)
            XCTAssertEqual(after.pages.count, 2,
                "Restoring the last mark must retain the paper now occupied by its unowned ink.")
            let raw = try PKDrawing(data: XCTUnwrap(reopened.pageHandwrittenNotationData))
            assertSameStrokes(raw, fixture.source)
            let frame = LeadSheetActiveInkScope.pageWritingFrame(for: after)
            XCTAssertTrue(CGRect(origin: .zero, size: frame.size).contains(raw.bounds))
            let paperCenter = CGPoint(x: raw.bounds.midX + frame.minX, y: raw.bounds.midY + frame.minY)
            XCTAssertEqual(FreeInkArticulationPlacement.pagePoint(at: paperCenter,
                pageLayout: after)?.pageIndex, 1)
        }
    }

    func testRestoredTailPaperIsRetainedAlongsideStaffInkWithoutMovingEitherSourceInBothStyles() throws {
        for style in styles {
            var fixture = try makeFixture(style: style, kind: .fermata)
            try deleteAppendedPage(in: &fixture)
            let currentLayout = layout(fixture.chart)
            let writingFrame = LeadSheetActiveInkScope.pageWritingFrame(for: currentLayout)
            let measure = try XCTUnwrap(currentLayout.systems.first?.measures.first)
            let local = CGPoint(x: measure.staffFrame.midX - writingFrame.minX,
                y: measure.staffFrame.midY - writingFrame.minY)
            let staffInk = drawing(at: local, kind: .accent, seed: 91)
            fixture.chart.setPageHandwrittenNotationDrawing(staffInk.dataRepresentation(),
                coordinateSpace: LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                    for: currentLayout, relativeTo: writingFrame))
            let combined = PKDrawing(strokes: staffInk.strokes + fixture.source.strokes)
            let restored = try restore(try reopen(fixture.chart), expected: combined)
            let saved = try reopen(restored)
            XCTAssertEqual(layout(saved).pages.count, 2,
                "Only the unowned tail group needs paper; a staff group must not hide it in aggregate bounds.")
            assertSameStrokes(try PKDrawing(data: XCTUnwrap(saved.pageHandwrittenNotationData)), combined)
        }
    }

    func testMovingFloatingMarkToEarlierPageStillRetainsItsOriginalSourcePaperInBothStyles() throws {
        for style in styles {
            var fixture = try makeFixture(style: style, kind: .accent)
            let originalSource = try XCTUnwrap(fixture.chart.freeInkArticulations.first?.sourcePagePoint)
            fixture.chart.freeInkArticulations[0].pagePoint = .init(pageIndex: 0, x: 200, y: 200)
            try deleteAppendedPage(in: &fixture)
            let saved = try reopen(fixture.chart)
            XCTAssertEqual(saved.freeInkArticulations[0].sourcePagePoint, originalSource)
            XCTAssertEqual(layout(saved).pages.count, 2)
            let restored = try restore(saved, expected: fixture.source)
            XCTAssertEqual(layout(try reopen(restored)).pages.count, 2)
        }
    }

    func testEmptyFinalPageStillCollapsesDespiteOldCanvasCapacityInBothStyles() throws {
        for style in styles {
            var fixture = try makeFixture(style: style, kind: .accent)
            fixture.chart.freeInkArticulations = []
            fixture.chart.pageHandwrittenNotationCoordinateSpace = fixture.originalSpace
            try deleteAppendedPage(in: &fixture)
            XCTAssertEqual(layout(try reopen(fixture.chart)).pages.count, 1)
        }
    }

    func testStaffOwnedRhythmInkDoesNotRetainADeletedPageOrRewriteItsArchive() throws {
        var fixture = try makeFixture(style: .rhythmSectionSheet, kind: .accent)
        let before = layout(fixture.chart)
        let writingFrame = LeadSheetActiveInkScope.pageWritingFrame(for: before)
        let measure = try XCTUnwrap(before.systems.last?.measures.last)
        let staffInk = drawing(at: CGPoint(x: measure.staffFrame.midX - writingFrame.minX,
            y: measure.staffFrame.midY - writingFrame.minY), kind: .accent, seed: 101)
        fixture.chart.freeInkArticulations = []
        fixture.chart.setPageHandwrittenNotationDrawing(staffInk.dataRepresentation(),
            coordinateSpace: fixture.originalSpace)
        let originalData = fixture.chart.pageHandwrittenNotationData
        let originalSpace = fixture.chart.pageHandwrittenNotationCoordinateSpace
        try deleteAppendedPage(in: &fixture)
        XCTAssertEqual(layout(fixture.chart).pages.count, 1,
            "Old staff-owned source geometry must not become a new absolute-paper retention rule.")
        XCTAssertEqual(fixture.chart.pageHandwrittenNotationData, originalData)
        XCTAssertEqual(fixture.chart.pageHandwrittenNotationCoordinateSpace, originalSpace)
    }

    func testMissingLegacyStaffGeometryDoesNotGuessNewRhythmPaperOwnership() throws {
        var fixture = try makeFixture(style: .rhythmSectionSheet, kind: .accent)
        fixture.chart.freeInkArticulations = []
        var legacySpace = fixture.originalSpace
        legacySpace.measureAnchors = nil
        legacySpace.chordAnchors = nil
        fixture.chart.setPageHandwrittenNotationDrawing(fixture.source.dataRepresentation(),
            coordinateSpace: legacySpace)
        let originalData = fixture.chart.pageHandwrittenNotationData
        let originalSpace = fixture.chart.pageHandwrittenNotationCoordinateSpace
        try deleteAppendedPage(in: &fixture)
        XCTAssertEqual(layout(fixture.chart).pages.count, 1)
        XCTAssertEqual(fixture.chart.pageHandwrittenNotationData, originalData)
        XCTAssertEqual(fixture.chart.pageHandwrittenNotationCoordinateSpace, originalSpace)
    }

    func testInvalidImportedPointsStayBoundedAndKeepExistingNearestPageFallbackInBothStyles() throws {
        for style in styles {
            var chart = Chart.blank(title: "Invalid imported paper point", measureCount: 4, layoutStyle: style)
            let page = try XCTUnwrap(layout(chart).pages.first)
            let invalidPoints: [FreeInkArticulationPagePoint] = [
                .init(pageIndex: -1, x: 200, y: 200),
                .init(pageIndex: Int.max, x: 200, y: 200),
                .init(pageIndex: 1, x: 200, y: page.frame.height + 30),
                .init(pageIndex: 1, x: page.frame.width + 1, y: 200)
            ]
            for point in invalidPoints {
                chart.freeInkArticulations = [FreeInkArticulation(kind: .accent, sourceInkData: Data([1]),
                    pagePoint: point, sourcePagePoint: point)]
                let current = layout(chart)
                XCTAssertEqual(current.pages.count, 1)
                let center = try XCTUnwrap(FreeInkArticulationPlacement.center(for: point, pageLayout: current))
                XCTAssertTrue(page.frame.contains(center))
                if point.y > page.frame.height {
                    XCTAssertEqual(center.y, page.frame.maxY - 10, accuracy: 0.01)
                }
            }
        }
    }

    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    private struct Fixture {
        var chart: Chart
        let originalMeasureIDs: [UUID]
        let appendedMeasureIDs: [UUID]
        let source: PKDrawing
        let originalSpace: PersistentInkCoordinateSpace
    }

    private func makeFixture(style: ChartLayoutStyle, kind: FreeInkArticulationKind) throws -> Fixture {
        var chart = Chart.blank(title: "Floating paper preservation", measureCount: 4, layoutStyle: style)
        let originalIDs = chart.measures.map(\.id)
        _ = try XCTUnwrap(chart.appendPage())
        let addedIDs = chart.measures.dropFirst(originalIDs.count).map(\.id)
        let before = layout(chart)
        XCTAssertEqual(before.pages.count, 2)
        let finalPage = try XCTUnwrap(before.pages.last)
        let center = CGPoint(x: finalPage.frame.midX, y: finalPage.frame.maxY - 55)
        XCTAssertNil(FreeInkArticulationPlacement.attachment(near: center, chart: chart, pageLayout: before))
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: before)
        let source = drawing(at: CGPoint(x: center.x - frame.minX, y: center.y - frame.minY), kind: kind, seed: 71)
        let sourceCenter = CGPoint(x: source.bounds.midX + frame.minX, y: source.bounds.midY + frame.minY)
        let point = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(at: sourceCenter, pageLayout: before))
        XCTAssertEqual(point.pageIndex, 1)
        let space = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: before, relativeTo: frame))
        var sourceSpace = space
        // Match a real floating conversion: no deleted-measure alias or source
        // registration can accidentally activate the attached-mark guards.
        sourceSpace.measureAnchors = nil
        sourceSpace.chordAnchors = nil
        chart.freeInkArticulations = [FreeInkArticulation(kind: kind,
            sourceInkData: source.dataRepresentation(), sourceCoordinateSpace: sourceSpace,
            pagePoint: point, sourcePagePoint: point)]
        XCTAssertNil(chart.pageHandwrittenNotationData)
        return Fixture(chart: chart, originalMeasureIDs: originalIDs, appendedMeasureIDs: addedIDs,
            source: source, originalSpace: space)
    }

    private func deleteAppendedPage(in fixture: inout Fixture) throws {
        let first = try XCTUnwrap(fixture.appendedMeasureIDs.first)
        let last = try XCTUnwrap(fixture.appendedMeasureIDs.last)
        XCTAssertTrue(fixture.chart.canDeleteMeasures(from: first, through: last))
        XCTAssertTrue(fixture.chart.deleteMeasures(from: first, through: last))
        XCTAssertEqual(fixture.chart.measures.map(\.id), fixture.originalMeasureIDs)
    }

    private func layout(_ chart: Chart, viewportWidth: CGFloat = 932) -> LeadSheetPageLayout {
        let width = LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
            retainedWidth: nil, chart: chart, viewportWidth: viewportWidth)
        return LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: width, height: 1_400))
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        let snapshot = ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id, entitlements: .free)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,
            isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        // This repository API saves synchronously; no async store write can
        // race the disk readback or masquerade as save/reopen coverage.
        try repository.saveSnapshot(snapshot)
        let saved = try XCTUnwrap(repository.loadSnapshot())
        return try XCTUnwrap(saved.charts.first)
    }

    private func restore(_ chart: Chart, expected: PKDrawing) throws -> Chart {
        let current = layout(chart)
        let writingFrame = LeadSheetActiveInkScope.pageWritingFrame(for: current)
        let currentSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: current, relativeTo: writingFrame))
        let survivingIDs = Set(chart.measures.map(\.id))
        XCTAssertTrue(currentSpace.measureAnchors?.allSatisfy { survivingIDs.contains($0.measureID) } == true)
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero,
            size: CGSize(width: current.pageBounds.width, height: max(1_400, current.pageBounds.height))))
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
        XCTAssertTrue(view.restoreFreeInkArticulation(articulationID: try XCTUnwrap(chart.freeInkArticulations.first?.id)))
        XCTAssertTrue(view.chart.freeInkArticulations.isEmpty)
        XCTAssertEqual(view.chart.pageHandwrittenNotationCoordinateSpace, currentSpace,
            "Restore Ink captures current blank-page capacity and only the surviving staff anchors.")
        assertSameStrokes(try PKDrawing(data: XCTUnwrap(view.chart.pageHandwrittenNotationData)), expected)
        return view.chart
    }

    private func drawing(at center: CGPoint, kind: FreeInkArticulationKind, seed: UInt32) -> PKDrawing {
        let paths: [[CGPoint]] = kind == .fermata
            ? [[CGPoint(x: -12, y: 5), CGPoint(x: -10, y: -2), CGPoint(x: 0, y: -8),
                CGPoint(x: 10, y: -2), CGPoint(x: 12, y: 5)], [CGPoint(x: 0, y: 3), CGPoint(x: 0.1, y: 3.1)]]
            : [[CGPoint(x: -12, y: -5), CGPoint(x: 12, y: 0), CGPoint(x: -12, y: 5)]]
        return PKDrawing(strokes: paths.enumerated().map { index, path in
            let points = path.enumerated().map { offset, point in
                PKStrokePoint(location: CGPoint(x: center.x + point.x, y: center.y + point.y),
                    timeOffset: Double(offset) * 0.1, size: CGSize(width: 2, height: 2),
                    opacity: 1, force: 0.7, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 7 + Double(index))),
                transform: .identity, mask: nil, randomSeed: seed + UInt32(index))
        })
    }

    private func assertSameStrokes(_ actual: PKDrawing, _ expected: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.strokes.count, expected.strokes.count, file: file, line: line)
        for (after, before) in zip(actual.strokes, expected.strokes) {
            XCTAssertEqual(after.randomSeed, before.randomSeed, file: file, line: line)
            XCTAssertEqual(after.transform, before.transform, file: file, line: line)
            XCTAssertEqual(after.path.creationDate, before.path.creationDate, file: file, line: line)
            XCTAssertEqual(after.path.count, before.path.count, file: file, line: line)
            for (point, original) in zip(after.path, before.path) {
                XCTAssertEqual(point.location.x, original.location.x, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(point.location.y, original.location.y, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(point.timeOffset, original.timeOffset, accuracy: 0.001, file: file, line: line)
                XCTAssertEqual(point.force, original.force, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(point.opacity, original.opacity, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(point.azimuth, original.azimuth, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(point.altitude, original.altitude, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(point.size.width, original.size.width, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(point.size.height, original.size.height, accuracy: 0.01, file: file, line: line)
            }
        }
    }
}
#endif

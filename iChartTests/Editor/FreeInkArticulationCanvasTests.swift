#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class FreeInkArticulationCanvasTests: XCTestCase {
    func testAutomaticCandidateClaimsOnlyNewIsolatedInk() throws {
        let first = accent(at: CGPoint(x: 6, y: 30), seed: 1)
        let last = accent(at: CGPoint(x: 100, y: 30), seed: 3)
        let drawing = PKDrawing(strokes: [first, last])

        XCTAssertNil(FreeInkArticulationSourceInk.automaticCandidate(in: drawing, firstNewStrokeIndex: 2))
        let candidate = try XCTUnwrap(FreeInkArticulationSourceInk.automaticCandidate(
            in: drawing, firstNewStrokeIndex: 1))
        XCTAssertEqual(candidate.kind, .accent)
        assertStrokes(candidate.source, equalTo: [last])
        assertStrokes(candidate.remaining, equalTo: [first])

        let crossing = stroke([CGPoint(x: 94, y: 37), CGPoint(x: 132, y: 37)], seed: 4)
        XCTAssertNil(FreeInkArticulationSourceInk.automaticCandidate(
            in: PKDrawing(strokes: [first, crossing, last]), firstNewStrokeIndex: 2))
    }

    func testRestorationFollowsTheAuthoredMeasureAfterReflow() throws {
        let authoredMeasureID = UUID()
        let otherMeasureID = UUID()
        let sourceStaff = CGRect(x: 50, y: 140, width: 100, height: 40)
        let movedStaff = CGRect(x: 15, y: 310, width: 120, height: 50)
        let source = try XCTUnwrap(PersistentInkMeasureAnchor(
            measureID: authoredMeasureID, frame: sourceStaff, staffFrame: sourceStaff))
        let moved = try XCTUnwrap(PersistentInkMeasureAnchor(
            measureID: authoredMeasureID, frame: movedStaff, staffFrame: movedStaff))
        let other = try XCTUnwrap(PersistentInkMeasureAnchor(
            measureID: otherMeasureID, frame: sourceStaff, staffFrame: sourceStaff))
        let sourceSpace = PersistentInkCoordinateSpace(width: 350, height: 400, measureAnchors: [source])
        let targetSpace = PersistentInkCoordinateSpace(width: 250, height: 500, measureAnchors: [other, moved])
        let mark = accent(at: CGPoint(x: 75, y: 150), seed: 10)
        let drawing = PKDrawing(strokes: [mark])

        let restored = try XCTUnwrap(FreeInkArticulationSourceInk.restore(
            drawing, source: sourceSpace, destination: targetSpace))
        let restoredStroke = try XCTUnwrap(restored.strokes.first)

        XCTAssertEqual(restored.strokes.count, 1)
        XCTAssertEqual(restoredStroke.randomSeed, mark.randomSeed)
        for (before, after) in zip(mark.path, restoredStroke.path) {
            let expectedX = movedStaff.minX + (before.location.x - sourceStaff.minX) * 1.2
            let expectedY = movedStaff.minY + (before.location.y - sourceStaff.minY) * 1.25
            let point = after.location.applying(restoredStroke.transform)
            XCTAssertEqual(point.x, expectedX, accuracy: 0.01)
            XCTAssertEqual(point.y, expectedY, accuracy: 0.01)
        }
        let missingMeasure = PersistentInkCoordinateSpace(width: 250, height: 500, measureAnchors: [other])
        XCTAssertNil(FreeInkArticulationSourceInk.restore(
            drawing, source: sourceSpace, destination: missingMeasure))
    }

    func testCanvasRendersSelectsMovesDeletesAndRestoresArticulation() async throws {
        let pageSize = CGSize(width: 1_200, height: 1_200)
        var chart = Chart.draft(title: "Free Ink articulation", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 4)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let pageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        let first = try XCTUnwrap(layout.systems.first?.measures.first)
        let staffCenter = CGPoint(x: first.staffFrame.midX - pageFrame.minX,
            y: first.staffFrame.midY - pageFrame.minY)
        let mark = accent(at: CGPoint(x: staffCenter.x - 12, y: staffCenter.y - 110), seed: 1)
        let nearby = stroke([
            CGPoint(x: staffCenter.x + 24, y: staffCenter.y - 9),
            CGPoint(x: staffCenter.x + 35, y: staffCenter.y + 8)
        ], seed: 2)
        let source = PKDrawing(strokes: [nearby])
        chart.pageHandwrittenNotationData = source.dataRepresentation()
        chart.pageHandwrittenNotationCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: layout, relativeTo: pageFrame)
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
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
        let authoring = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        assertStrokes(authoring.drawing, equalTo: source.strokes)
        let convertedMark = expectation(description: "Automatic Free Ink conversion")
        var published: [Chart] = []
        var didNotifyBeforePublication = false
        view.onFreeInkArticulationWillSave = { didNotifyBeforePublication = true }
        view.onChartChanged = { chart in
            published.append(chart)
            if !chart.freeInkArticulations.isEmpty {
                XCTAssertTrue(didNotifyBeforePublication)
                convertedMark.fulfill()
            }
        }
        view.canvasViewDidBeginUsingTool(authoring)
        authoring.drawing = PKDrawing(strokes: [nearby, mark])
        view.canvasViewDrawingDidChange(authoring)
        XCTAssertTrue(view.chart.freeInkArticulations.isEmpty)
        view.canvasViewDidEndUsingTool(authoring)
        await fulfillment(of: [convertedMark], timeout: 4)

        XCTAssertEqual(published.filter { !$0.freeInkArticulations.isEmpty }.count, 1)
        let converted = try XCTUnwrap(published.last)
        let articulation = try XCTUnwrap(converted.freeInkArticulations.first)
        XCTAssertEqual(articulation.kind, .accent)
        XCTAssertNil(articulation.measureID)
        XCTAssertNil(articulation.attachment)
        XCTAssertNotNil(articulation.pagePoint)
        XCTAssertEqual(articulation.pagePoint, articulation.sourcePagePoint)
        assertStrokes(try PKDrawing(data: articulation.sourceInkData), equalTo: [mark])
        assertStrokes(try PKDrawing(data: XCTUnwrap(converted.pageHandwrittenNotationData)),
            equalTo: [nearby])
        assertStrokes(authoring.drawing, equalTo: [nearby])

        view.onChartChanged = { published.append($0) }
        view.interactionMode = .browse
        view.layoutIfNeeded()
        let floatingTarget = try XCTUnwrap(FreeInkArticulationPlacement.target(for: articulation,
            chart: view.chart, pageLayout: layout))
        XCTAssertTrue(view.handleFreeInkArticulationTap(at: floatingTarget.center))
        XCTAssertEqual(view.selectedFreeInkArticulationID, articulation.id)
        let deleteButton = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "free-ink-articulation-delete"
        })
        XCTAssertFalse(deleteButton.isHidden)
        XCTAssertEqual(deleteButton.accessibilityLabel, "Delete accent")
        XCTAssertFalse(deleteButton.frame.contains(floatingTarget.center))
        XCTAssertTrue(view.hitTest(CGPoint(x: deleteButton.frame.midX, y: deleteButton.frame.midY),
            with: nil) === deleteButton)
        XCTAssertTrue(view.beginFreeInkArticulationDrag(at: floatingTarget.center))
        XCTAssertTrue(deleteButton.isHidden)
        let staffPoint = CGPoint(x: first.staffFrame.midX, y: first.staffFrame.midY)
        let guide = try XCTUnwrap(view.updateFreeInkArticulationDrag(to: staffPoint))
        XCTAssertEqual(guide.measureID, first.sourceMeasureID)
        XCTAssertTrue(first.staffFrame.contains(guide.guidePoint))
        XCTAssertEqual(view.chart.freeInkArticulations, [articulation])
        XCTAssertNil(view.updateFreeInkArticulationDrag(to: floatingTarget.center))
        XCTAssertEqual(view.chart.freeInkArticulations, [articulation])
        XCTAssertEqual(view.updateFreeInkArticulationDrag(to: staffPoint), guide)
        XCTAssertTrue(view.endFreeInkArticulationDrag(at: staffPoint))
        let moved = try XCTUnwrap(view.chart.freeInkArticulations.first)
        XCTAssertEqual(moved.measureID, first.sourceMeasureID)
        XCTAssertEqual(moved.attachment, guide.attachment)
        XCTAssertNil(view.updateFreeInkArticulationDrag(to: staffPoint))
        guard case .staff = moved.attachment else { return XCTFail("Expected staff attachment") }
        XCTAssertEqual(moved.sourcePagePoint, articulation.sourcePagePoint)
        XCTAssertEqual(moved.sourceInkData, articulation.sourceInkData)
        XCTAssertEqual(view.chart.pageHandwrittenNotationData, converted.pageHandwrittenNotationData)
        XCTAssertEqual(view.selectedFreeInkArticulationID, moved.id)
        let movedTarget = try XCTUnwrap(FreeInkArticulationPlacement.target(for: moved,
            chart: view.chart, pageLayout: layout))
        XCTAssertTrue(view.beginFreeInkArticulationDrag(at: movedTarget.center))
        XCTAssertNotNil(view.updateFreeInkArticulationDrag(to: movedTarget.center))
        view.cancelFreeInkArticulationDrag()
        XCTAssertNil(view.updateFreeInkArticulationDrag(to: movedTarget.center))
        XCTAssertEqual(view.chart.freeInkArticulations, [moved])
        XCTAssertFalse(deleteButton.frame.contains(movedTarget.center))
        XCTAssertFalse(view.handleFreeInkArticulationTap(at: .zero))
        XCTAssertTrue(deleteButton.isHidden)
        XCTAssertTrue(view.handleFreeInkArticulationTap(at: movedTarget.center))

        var undoAvailability: [Bool] = []
        view.onFreeInkArticulationDeletionAvailabilityChanged = { undoAvailability.append($0) }
        view.onChartChanged = { chart in
            XCTAssertTrue(didNotifyBeforePublication)
            didNotifyBeforePublication = false
            published.append(chart)
        }
        didNotifyBeforePublication = false
        deleteButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(view.chart.freeInkArticulations.isEmpty)
        XCTAssertEqual(view.chart.pageHandwrittenNotationData, converted.pageHandwrittenNotationData)
        XCTAssertNil(view.selectedFreeInkArticulationID)
        XCTAssertTrue(deleteButton.isHidden)
        XCTAssertEqual(undoAvailability, [true])
        XCTAssertTrue(view.undoFreeInkArticulationDeletion())
        XCTAssertEqual(view.chart.freeInkArticulations, [moved])
        XCTAssertEqual(view.selectedFreeInkArticulationID, moved.id)
        XCTAssertEqual(undoAvailability, [true, false])
        XCTAssertFalse(view.undoFreeInkArticulationDeletion())

        view.onChartChanged = { published.append($0) }
        XCTAssertTrue(view.beginFreeInkArticulationDrag(at: movedTarget.center))
        XCTAssertNotNil(view.updateFreeInkArticulationDrag(to: movedTarget.center))
        XCTAssertTrue(view.endFreeInkArticulationDrag(at: floatingTarget.center))
        let floated = try XCTUnwrap(view.chart.freeInkArticulations.first)
        XCTAssertNil(floated.measureID)
        XCTAssertNil(floated.attachment)
        XCTAssertEqual(floated.pagePoint, articulation.pagePoint)
        XCTAssertEqual(floated.sourceInkData, articulation.sourceInkData)
        view.interactionMode = .freeHand
        view.layoutIfNeeded()
        XCTAssertTrue(view.restoreFreeInkArticulation(articulationID: articulation.id))
        let restored = try XCTUnwrap(published.last)
        XCTAssertTrue(restored.freeInkArticulations.isEmpty)
        assertStrokes(try PKDrawing(data: XCTUnwrap(restored.pageHandwrittenNotationData)),
            equalTo: [nearby, mark])
        assertStrokes(authoring.drawing, equalTo: [nearby, mark])
    }

    func testTapChoosesTheNearestMarkWhenTouchTargetsOverlap() throws {
        let pageSize = CGSize(width: 1_200, height: 1_200)
        var chart = Chart.draft(title: "Overlapping touch targets", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 4)
        let first = FreeInkArticulation(kind: .accent, sourceInkData: Data(),
            pagePoint: FreeInkArticulationPagePoint(pageIndex: 0, x: 200, y: 200))
        let second = FreeInkArticulation(kind: .fermata, sourceInkData: Data(),
            pagePoint: FreeInkArticulationPagePoint(pageIndex: 0, x: 200, y: 208))
        chart.freeInkArticulations = [first, second]
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        view.chart = chart
        view.layoutIfNeeded()
        let firstCenter = try XCTUnwrap(FreeInkArticulationPlacement.target(for: first,
            chart: chart, pageLayout: layout)).center
        XCTAssertTrue(view.handleFreeInkArticulationTap(at: firstCenter))
        XCTAssertEqual(view.selectedFreeInkArticulationID, first.id)
        let deleteButton = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "free-ink-articulation-delete"
        })
        deleteButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(view.chart.freeInkArticulations, [second])

        // A subsequent chart edit may remove or change the original anchor.
        var edited = view.chart
        edited.title = "Updated engraving"
        view.chart = edited
        XCTAssertFalse(view.undoFreeInkArticulationDeletion())
        XCTAssertEqual(view.chart.freeInkArticulations, [second])
    }

    private func accent(at origin: CGPoint, seed: UInt32) -> PKStroke {
        let offsets: [(CGFloat, CGFloat)] = [(0, 0), (12, 3.3), (24, 7), (13, 10.4), (0, 14)]
        return stroke(offsets.map { CGPoint(x: origin.x + $0.0, y: origin.y + $0.1) }, seed: seed)
    }

    private func stroke(_ points: [CGPoint], seed: UInt32) -> PKStroke {
        let path = points.enumerated().map { offset, point in
            PKStrokePoint(location: point, timeOffset: Double(offset) * 0.1,
                size: CGSize(width: 2, height: 2), opacity: 0.8, force: 0.7,
                azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: path,
                creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }

    private func assertStrokes(_ actual: PKDrawing, equalTo expected: [PKStroke],
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.strokes.count, expected.count, file: file, line: line)
        for (stroke, original) in zip(actual.strokes, expected) {
            XCTAssertEqual(stroke.randomSeed, original.randomSeed, file: file, line: line)
            XCTAssertEqual(stroke.transform, original.transform, file: file, line: line)
            XCTAssertEqual(stroke.path.creationDate, original.path.creationDate, file: file, line: line)
            XCTAssertEqual(stroke.path.map(\.location), original.path.map(\.location), file: file, line: line)
            XCTAssertEqual(stroke.path.map(\.timeOffset), original.path.map(\.timeOffset), file: file, line: line)
        }
    }
}
#endif

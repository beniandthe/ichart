#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class SimpleArticulationCanvasTests: XCTestCase {
    private let pageSize = CGSize(width: 1_200, height: 1_400)

    func testSimpleFloatingAccentSharesSelectDragGuideDeleteUndoAndPaperRestore() async throws {
        var chart = try makeChart()
        let initialLayout = layout(for: chart)
        let pageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: initialLayout)
        let paperPoint = CGPoint(x: initialLayout.paperFrame.midX, y: initialLayout.paperFrame.maxY - 130)
        let source = accent(at: CGPoint(x: paperPoint.x - pageFrame.minX - 12,
            y: paperPoint.y - pageFrame.minY - 7), seed: 10)
        let neighbor = stroke([CGPoint(x: source.renderBounds.maxX + 90, y: source.renderBounds.minY + 25),
            CGPoint(x: source.renderBounds.maxX + 103, y: source.renderBounds.minY + 40)], seed: 1)
        chart.pageHandwrittenNotationData = PKDrawing(strokes: [neighbor]).dataRepresentation()
        chart.pageHandwrittenNotationCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: initialLayout, relativeTo: pageFrame)
        let fixture = try mount(chart)
        defer { fixture.window.isHidden = true }
        let mark = try await convert([source], in: fixture, kind: .accent)
        XCTAssertNil(mark.attachment)
        XCTAssertNil(mark.sourceCoordinateSpace?.measureAnchors)
        assertInk(try PKDrawing(data: mark.sourceInkData), matches: PKDrawing(strokes: [source]))
        assertInk(fixture.canvas.drawing, matches: PKDrawing(strokes: [neighbor]))

        fixture.view.interactionMode = .browse
        fixture.view.layoutIfNeeded()
        let floating = try XCTUnwrap(FreeInkArticulationPlacement.target(for: mark,
            chart: fixture.view.chart, pageLayout: initialLayout))
        XCTAssertTrue(fixture.view.handleFreeInkArticulationTap(at: floating.center))
        XCTAssertEqual(fixture.view.selectedFreeInkArticulationID, mark.id)
        let delete = try XCTUnwrap(fixture.view.subviews.compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "free-ink-articulation-delete"
        })
        XCTAssertFalse(delete.isHidden)
        XCTAssertEqual(delete.accessibilityLabel, "Delete accent")
        let chord = try XCTUnwrap(initialLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first)
        let chordPoint = CGPoint(x: chord.frame.midX, y: chord.frame.midY)
        XCTAssertTrue(fixture.view.beginFreeInkArticulationDrag(at: floating.center))
        let overlay = try XCTUnwrap(fixture.view.layer.sublayers?.first { $0.name == "free-ink-articulation-drag" })
        let line = try XCTUnwrap(overlay.sublayers?.first { $0.name == "guide" } as? CAShapeLayer)
        let guide = try XCTUnwrap(fixture.view.updateFreeInkArticulationDrag(to: chordPoint))
        XCTAssertEqual(guide.attachment, .chord(id: chord.id))
        XCTAssertFalse(line.isHidden)
        XCTAssertEqual(fixture.view.updateFreeInkArticulationDrag(to:
            CGPoint(x: chordPoint.x + 1, y: chordPoint.y))?.attachment, guide.attachment)
        XCTAssertNil(fixture.view.updateFreeInkArticulationDrag(to: floating.center))
        XCTAssertTrue(line.isHidden)
        XCTAssertTrue(fixture.view.endFreeInkArticulationDrag(at: chordPoint))
        let attached = try XCTUnwrap(fixture.view.chart.freeInkArticulations.first)
        XCTAssertEqual(attached.attachment, .chord(id: chord.id))
        XCTAssertEqual(attached.sourceInkData, mark.sourceInkData)
        XCTAssertEqual(attached.sourcePagePoint, mark.sourcePagePoint)
        XCTAssertNil(overlay.superlayer)

        var undoAvailability: [Bool] = []
        fixture.view.onFreeInkArticulationDeletionAvailabilityChanged = { undoAvailability.append($0) }
        delete.sendActions(for: .touchUpInside)
        XCTAssertTrue(fixture.view.chart.freeInkArticulations.isEmpty)
        assertInk(try PKDrawing(data: XCTUnwrap(fixture.view.chart.pageHandwrittenNotationData)),
            matches: PKDrawing(strokes: [neighbor]))
        XCTAssertTrue(fixture.view.undoFreeInkArticulationDeletion())
        XCTAssertEqual(fixture.view.chart.freeInkArticulations, [attached])
        XCTAssertEqual(undoAvailability, [true, false])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        try repository.saveSnapshot(ChartLibrarySnapshot(charts: [fixture.view.chart],
            selectedChartID: chart.id, entitlements: .free))
        let reopened = try XCTUnwrap(try repository.loadSnapshot()?.charts.first)
        XCTAssertEqual(reopened.freeInkArticulations, [attached])
        fixture.view.chart = reopened
        fixture.view.interactionMode = .freeHand
        fixture.view.layoutIfNeeded()
        XCTAssertTrue(fixture.view.restoreFreeInkArticulation(articulationID: mark.id))
        XCTAssertTrue(fixture.view.chart.freeInkArticulations.isEmpty)
        assertInk(fixture.canvas.drawing, matches: PKDrawing(strokes: [neighbor, source]))
    }

    func testSimpleFermataAttachesToChordAndRestoresAtAuthoredPaperAfterFormEdits() async throws {
        let chart = try makeChart()
        let initialLayout = layout(for: chart)
        let pageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: initialLayout)
        let chord = try XCTUnwrap(initialLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first)
        let origin = CGPoint(x: chord.frame.midX - pageFrame.minX - 13,
            y: chord.frame.minY - pageFrame.minY - 14)
        let arch = stroke([(0, 11), (3, 6), (7, 2), (12, 0), (18, 1.5), (23, 5.3), (26, 10)].map {
            CGPoint(x: origin.x + $0.0, y: origin.y + $0.1)
        }, seed: 20)
        let dot = stroke([(12.4, 7.5), (13, 7.8), (12.8, 8)].map {
            CGPoint(x: origin.x + $0.0, y: origin.y + $0.1)
        }, seed: 21, creationTime: 20.5)
        let source = PKDrawing(strokes: [arch, dot])
        let fixture = try mount(chart)
        defer { fixture.window.isHidden = true }
        let mark = try await convert(source.strokes, in: fixture, kind: .fermata)
        XCTAssertEqual(mark.attachment, .chord(id: chord.id))
        XCTAssertNil(mark.sourceCoordinateSpace?.measureAnchors)
        XCTAssertNil(mark.sourceCoordinateSpace?.chordAnchors)
        assertInk(try PKDrawing(data: mark.sourceInkData), matches: source)

        var edited = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(fixture.view.chart))
        let firstID = chart.measures[0].id
        _ = try XCTUnwrap(edited.splitSimpleChordMeasure(firstID, atFraction: 0.5))
        XCTAssertTrue(edited.joinMeasure(after: firstID))
        edited = FreeInkArticulationPlacement.preservingVisiblePagePoints(in: edited, pageLayout: layout(for: edited))
        XCTAssertTrue(edited.deleteMeasure(id: firstID))
        XCTAssertEqual(edited.freeInkArticulations.first?.sourcePagePoint, mark.sourcePagePoint)
        XCTAssertEqual(edited.freeInkArticulations.first?.sourceInkData, mark.sourceInkData)
        let afterEdits = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(edited))
        fixture.view.chart = afterEdits
        fixture.view.interactionMode = .freeHand
        fixture.view.layoutIfNeeded()
        XCTAssertTrue(fixture.view.restoreFreeInkArticulation(articulationID: mark.id))
        XCTAssertTrue(fixture.view.chart.freeInkArticulations.isEmpty)
        assertInk(fixture.canvas.drawing, matches: source)
    }

    func testSimpleStaffPaperKeepsMarcatoInkAndLeavesBareStaffAccentFloating() async throws {
        var chart = try makeChart()
        chart.stylePreset = .gigSheet
        let initialLayout = layout(for: chart)
        let pageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: initialLayout)
        let chord = try XCTUnwrap(initialLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first)
        let caretOrigin = CGPoint(x: chord.frame.midX - pageFrame.minX - 9,
            y: chord.frame.minY - pageFrame.minY - 14)
        let caret = stroke([(0, 14), (4.5, 7), (9, 0), (13.5, 6.5), (18, 13.4)].map {
            CGPoint(x: caretOrigin.x + $0.0, y: caretOrigin.y + $0.1)
        }, seed: 30)
        XCTAssertEqual(FreeInkArticulationSourceInk.automaticCandidate(
            in: PKDrawing(strokes: [caret]), firstNewStrokeIndex: 0)?.kind, .marcato)
        let fixture = try mount(chart)
        defer { fixture.window.isHidden = true }
        let unexpected = expectation(description: "Simple carets remain handwriting")
        unexpected.isInverted = true
        fixture.view.onFreeInkArticulationWillSave = { unexpected.fulfill() }
        write([caret], in: fixture)
        await fulfillment(of: [unexpected], timeout: 1.15)
        fixture.view.onFreeInkArticulationWillSave = nil
        XCTAssertTrue(fixture.view.chart.freeInkArticulations.isEmpty)
        assertInk(fixture.canvas.drawing, matches: PKDrawing(strokes: [caret]))

        let emptyMeasure = try XCTUnwrap(initialLayout.systems.flatMap(\.measures).first {
            $0.sourceMeasureID == chart.measures.last?.id
        })
        let bareStaffPoint = CGPoint(x: emptyMeasure.staffFrame.midX - pageFrame.minX,
            y: emptyMeasure.staffFrame.midY - pageFrame.minY)
        let accentInk = accent(at: CGPoint(x: bareStaffPoint.x - 12, y: bareStaffPoint.y - 7), seed: 40)
        let mark = try await convert([accentInk], in: fixture, kind: .accent)
        XCTAssertNil(mark.attachment)
        XCTAssertNil(mark.measureID)
        XCTAssertNotNil(mark.pagePoint)
        assertInk(fixture.canvas.drawing, matches: PKDrawing(strokes: [caret]))
    }

    private struct Fixture {
        let view: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let window: UIWindow
    }

    private func makeChart() throws -> Chart {
        var chart = Chart.blank(title: "Simple automatic marks", measureCount: 3, layoutStyle: .simpleChordSheet)
        let id = chart.measures[0].id
        _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("C"),
            rawInput: "C", to: id, atFraction: 0.1))
        _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("G7"),
            rawInput: "G7", to: id, atFraction: 0.8))
        _ = chart.setMeasureManualLayoutWidth(320, for: id)
        return chart
    }

    private func layout(for chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
    }

    private func mount(_ chart: Chart) throws -> Fixture {
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        view.chart = chart
        view.interactionMode = .freeHand
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let canvas = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        return Fixture(view: view, canvas: canvas, window: window)
    }

    private func convert(_ newStrokes: [PKStroke], in fixture: Fixture,
        kind: FreeInkArticulationKind) async throws -> FreeInkArticulation {
        let converted = expectation(description: "Simple \(kind.title) converts from fresh ink")
        let count = fixture.view.chart.freeInkArticulations.count
        var notified = false
        fixture.view.onChartChanged = { updated in
            guard !notified, updated.freeInkArticulations.count == count + 1 else { return }
            notified = true
            converted.fulfill()
        }
        write(fixture.canvas.drawing.strokes + newStrokes, in: fixture)
        await fulfillment(of: [converted], timeout: 4)
        fixture.view.onChartChanged = nil
        let mark = try XCTUnwrap(fixture.view.chart.freeInkArticulations.last)
        XCTAssertEqual(mark.kind, kind)
        return mark
    }

    private func write(_ strokes: [PKStroke], in fixture: Fixture) {
        fixture.view.canvasViewDidBeginUsingTool(fixture.canvas)
        fixture.canvas.drawing = PKDrawing(strokes: strokes)
        fixture.view.canvasViewDrawingDidChange(fixture.canvas)
        fixture.view.canvasViewDidEndUsingTool(fixture.canvas)
    }

    private func accent(at point: CGPoint, seed: UInt32) -> PKStroke {
        stroke([(0, 0), (12, 3.3), (24, 7), (13, 10.4), (0, 14)].map {
            CGPoint(x: point.x + $0.0, y: point.y + $0.1)
        }, seed: seed)
    }

    private func stroke(_ points: [CGPoint], seed: UInt32, creationTime: Double? = nil) -> PKStroke {
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.05,
                size: CGSize(width: 2, height: 2), opacity: 0.8, force: 0.7, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: creationTime ?? Double(seed)))
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: path, transform: .identity, mask: nil, randomSeed: seed)
    }

    private func assertInk(_ actual: PKDrawing, matches expected: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: actual),
            "Original paths, attributes, and chronology must survive mark operations", file: file, line: line)
    }
}
#endif

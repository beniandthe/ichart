#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Mounted production gesture paths. This is Simulator-capable evidence, not
/// a claim about physical Pencil feel or hardware palm rejection.
@MainActor
final class CueTextVerticalBoundaryGestureTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let positions: [CuePosition] = [.above, .below]

    func testTextBodyVerticalPreviewAndCommitKeepStaffAndPageGeometryFixed() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position)
                let mounted = try mount(fixture, route: .body)
                defer { mounted.close() }
                let beforeLayout = try cachedLayout(mounted.canvas)
                let beforeGeometry = Geometry(beforeLayout)
                let original = try cue(fixture.cueID, in: beforeLayout)
                let distance: CGFloat = position == .above ? -8 : 8
                let pan = try begin(mounted, fixture: fixture, route: .body)
                move(pan, from: mounted.start, by: distance, state: .changed, on: mounted.canvas)
                let preview = try preview(mounted.canvas, route: .body)

                XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
                XCTAssertTrue(mounted.writes.isEmpty)
                XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), beforeGeometry)
                XCTAssertEqual(preview.frame.minX, original.frame.minX, accuracy: 0.001)
                let achieved = preview.frame.minY - original.frame.minY
                XCTAssertGreaterThan(achieved * (distance < 0 ? -1 : 1), 0.01,
                    "\(style) \(position) cue should move where there is room")
                XCTAssertLessThanOrEqual(abs(achieved), abs(distance) + 0.01,
                    "The cue may stop at a boundary, but must respond in the requested direction")
                assertClearsNeighborStaves(preview.frame, cueID: fixture.cueID, in: beforeLayout)

                move(pan, from: mounted.start, by: distance, state: .ended, on: mounted.canvas)
                try assertOneVerticalCommit(mounted, fixture: fixture, preview: preview,
                    originalGeometry: beforeGeometry)
            }
        }
    }

    func testMoveUpOrDownHandleClampsAtNeighborStavesWithoutRepackingThePage() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position)
                let mounted = try mount(fixture, route: .handle)
                defer { mounted.close() }
                let before = try cachedLayout(mounted.canvas)
                let geometry = Geometry(before)
                let original = try cue(fixture.cueID, in: before)
                let distance: CGFloat = position == .above ? -140 : 140
                let pan = try begin(mounted, fixture: fixture, route: .handle)
                move(pan, from: mounted.start, by: distance, state: .changed, on: mounted.canvas)
                let preview = try preview(mounted.canvas, route: .handle)

                XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
                XCTAssertTrue(mounted.writes.isEmpty)
                XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), geometry)
                XCTAssertEqual(preview.frame.minX, original.frame.minX, accuracy: 0.001)
                XCTAssertGreaterThan(abs(preview.frame.minY - original.frame.minY), 0.01,
                    "\(style) \(position) cue should move before reaching its boundary")
                XCTAssertLessThan(abs(preview.frame.minY - original.frame.minY), abs(distance))
                assertClearsNeighborStaves(preview.frame, cueID: fixture.cueID, in: before)

                move(pan, from: mounted.start, by: distance, state: .ended, on: mounted.canvas)
                try assertOneVerticalCommit(mounted, fixture: fixture, preview: preview,
                    originalGeometry: geometry)
            }
        }
    }

    func testLegacyClampedRequestedOffsetsMoveBackFromTheirVisiblePositionImmediately() throws {
        for style in styles {
            for position in positions {
                let authored: Double = position == .above ? -72 : 72
                let inward: CGFloat = position == .above ? 8 : -8
                let fixture = try fixture(style: style, position: position, verticalOffset: authored)
                for route in Route.allCases {
                    let mounted = try mount(fixture, route: route)
                    defer { mounted.close() }
                    let layout = try cachedLayout(mounted.canvas)
                    let geometry = Geometry(layout)
                    let original = try cue(fixture.cueID, in: layout)
                    XCTAssertLessThan(abs(original.verticalOffsetFromDefault), CGFloat(abs(authored)) - 0.01,
                        "This regression needs an authored offset that is visibly clamped by the staff boundary")
                    let pan = try begin(mounted, fixture: fixture, route: route)
                    move(pan, from: mounted.start, by: inward, state: .changed, on: mounted.canvas)
                    let preview = try preview(mounted.canvas, route: route)
                    let achieved = preview.frame.minY - original.frame.minY
                    XCTAssertGreaterThan(achieved * (inward < 0 ? -1 : 1), 0.01,
                        "Moving inward must respond to the visible clamp immediately, without a hidden offset dead zone")
                    XCTAssertLessThanOrEqual(abs(achieved), abs(inward) + 0.01,
                        "An opposite boundary may limit movement, but the visible cue must never jump farther than the Pencil")
                    XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), geometry)
                    XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
                    assertClearsNeighborStaves(preview.frame, cueID: fixture.cueID, in: layout)
                    move(pan, from: mounted.start, by: inward, state: .ended, on: mounted.canvas)
                    try assertOneVerticalCommit(mounted, fixture: fixture, preview: preview,
                        originalGeometry: geometry)
                }
            }
        }
    }

    func testBlockedOutwardDragPreservesLegacyRequestedOffsetInsteadOfPublishingAnInvisibleEdit() throws {
        for style in styles {
            for position in positions {
                let authored: Double = position == .above ? -72 : 72
                let outward: CGFloat = position == .above ? -8 : 8
                let fixture = try fixture(style: style, position: position, verticalOffset: authored)
                for route in Route.allCases {
                    let mounted = try mount(fixture, route: route)
                    defer { mounted.close() }
                    let layout = try cachedLayout(mounted.canvas)
                    let original = try cue(fixture.cueID, in: layout)
                    let geometry = Geometry(layout)
                    let pan = try begin(mounted, fixture: fixture, route: route)
                    move(pan, from: mounted.start, by: outward, state: .changed, on: mounted.canvas)
                    let preview = try preview(mounted.canvas, route: route)
                    assertEqual(preview.frame, original.frame)
                    move(pan, from: mounted.start, by: outward, state: .ended, on: mounted.canvas)
                    XCTAssertTrue(mounted.writes.isEmpty)
                    XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
                    XCTAssertEqual(mounted.canvas.chart.cueText(id: fixture.cueID)?.verticalOffset, authored)
                    XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), geometry)
                }
            }
        }
    }

    func testStationaryAndCancelledGesturesDoNotWriteAndResetKeepsItsExistingModelMeaning() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position)
                for route in Route.allCases {
                    let mounted = try mount(fixture, route: route)
                    defer { mounted.close() }
                    let geometry = Geometry(try cachedLayout(mounted.canvas))
                    let still = try begin(mounted, fixture: fixture, route: route)
                    move(still, from: mounted.start, by: 0, state: .ended, on: mounted.canvas)
                    XCTAssertTrue(mounted.writes.isEmpty)
                    XCTAssertEqual(mounted.canvas.chart, mounted.baseline)

                    for state: UIGestureRecognizer.State in [.cancelled, .failed] {
                        let pan = try begin(mounted, fixture: fixture, route: route)
                        move(pan, from: mounted.start, by: position == .above ? -8 : 8,
                            state: .changed, on: mounted.canvas)
                        _ = try preview(mounted.canvas, route: route)
                        move(pan, from: mounted.start, by: position == .above ? -8 : 8,
                            state: state, on: mounted.canvas)
                        XCTAssertTrue(mounted.writes.isEmpty)
                        XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
                        XCTAssertNil(privateValue("activeCueTextMoveDrag", in: mounted.canvas) as ActiveCueTextMoveDrag?)
                        XCTAssertNil(privateValue("cueAnnotationPositionPreview", in: mounted.canvas) as LeadSheetCueTextLayout?)
                        XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), geometry)
                    }
                }

                let legacy = try self.fixture(style: style, position: position,
                    verticalOffset: position == .above ? -72 : 72)
                let mounted = try mount(legacy, route: .handle)
                defer { mounted.close() }
                let geometry = Geometry(try cachedLayout(mounted.canvas))
                var reset = mounted.canvas.chart
                XCTAssertTrue(LeadSheetAnnotationPositionDrag.setOffset(0, for: .cueText(legacy.cueID), in: &reset))
                XCTAssertEqual(reset.cueText(id: legacy.cueID)?.verticalOffset, 0)
                assertOnlyVerticalOffsetChanged(from: mounted.baseline, to: reset, cueID: legacy.cueID)
                mounted.canvas.chart = reset
                mounted.canvas.layoutIfNeeded()
                XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), geometry)
                XCTAssertFalse(LeadSheetAnnotationPositionDrag.setOffset(0, for: .cueText(legacy.cueID), in: &reset))
            }
        }
    }

    private enum Route: CaseIterable { case body, handle }

    private struct Fixture {
        let chart: Chart
        let cueID: UUID
    }

    private struct Geometry: Equatable {
        let document: CGRect
        let pages: [CGRect]
        let paper: CGRect
        let staffFrames: [CGRect]
        let measureFrames: [CGRect]

        init(_ page: LeadSheetPageLayout) {
            document = page.pageBounds
            pages = page.pages.map(\.frame)
            paper = page.paperFrame
            staffFrames = page.systems.flatMap(\.measures).map(\.staffFrame)
            measureFrames = page.systems.flatMap(\.measures).map(\.frame)
        }
    }

    @MainActor
    private final class Mounted {
        let window: UIWindow
        let canvas: LeadSheetCanvasUIKitView
        let baseline: Chart
        var writes: [Chart] = []
        var start = CGPoint.zero

        init(window: UIWindow, canvas: LeadSheetCanvasUIKitView) {
            self.window = window
            self.canvas = canvas
            baseline = canvas.chart
        }

        func close() {
            canvas.onChartChanged = nil
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func fixture(style: ChartLayoutStyle, position: CuePosition,
        verticalOffset: Double = 0) throws -> Fixture {
        var chart = Chart.blank(title: "Cue vertical boundaries", measureCount: 6, layoutStyle: style)
        chart.setStaffSystemDensity(.dense)
        let measures = chart.measures
        chart.systems = stride(from: 0, to: measures.count, by: 2).enumerated().map { index, first in
            ChartSystem(id: UUID(), index: index, spacingMode: .compact, lineBreakRule: .forced,
                measures: Array(measures[first..<min(first + 2, measures.count)]))
        }
        let measureID = chart.measures[2].id
        let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("Cmaj7"),
            rawInput: "Cmaj7", to: measureID, atFraction: 0.75))
        // The first Rhythm chord snaps to beat one. Use a separate cue column
        // so the fixture measures travel to the neighboring row's boundary.
        let cueID = try XCTUnwrap(chart.addCueText("On cue", anchorMeasureID: measureID,
            position: position, atFraction: 0.5))
        XCTAssertTrue(chart.updateCueText(cueID, verticalOffset: verticalOffset))
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen,
            color: LeadSheetPersistentInkColorPolicy.inkColor), path: PKStrokePath(controlPoints: [
                PKStrokePoint(location: CGPoint(x: 20, y: 20), timeOffset: 0, size: CGSize(width: 3, height: 3),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
                PKStrokePoint(location: CGPoint(x: 35, y: 30), timeOffset: 0.02, size: CGSize(width: 3, height: 3),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            ], creationDate: Date(timeIntervalSinceReferenceDate: 10)), transform: .identity, mask: nil, randomSeed: 17)])
        let data = try XCTUnwrap(LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: drawing))
        let eventIndex = try XCTUnwrap(chart.systems[1].measures[0].chordEvents.firstIndex { $0.id == chordID })
        chart.systems[1].measures[0].chordEvents[eventIndex].sourceInkData = data
        chart.pageHandwrittenNotationData = data
        chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
        chart.systems[1].measures[0].handwrittenRhythmicNotationData = data
        chart.systems[1].measures[0].handwrittenRhythmicNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 300, height: 80)
        chart = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        return Fixture(chart: chart, cueID: cueID)
    }

    private func mount(_ fixture: Fixture, route: Route) throws -> Mounted {
        let frame = CGRect(origin: .zero, size: pageSize)
        let canvas = LeadSheetCanvasUIKitView(frame: frame)
        canvas.chart = fixture.chart
        canvas.interactionMode = route == .body ? .textEdit : .browse
        let controller = UIViewController()
        controller.view = canvas
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        canvas.layoutIfNeeded()
        canvas.applyParentSelectionState(selectedMeasureID: fixture.chart.cueText(id: fixture.cueID)?.anchorMeasureID,
            selectedNoteSelection: nil, selectedChordID: nil, selectedCommittedBarlineMeasureID: nil,
            selectedCueTextID: fixture.cueID, selectedRoadmapMarkerID: nil, selectedEndingSpanID: nil)
        let mounted = Mounted(window: window, canvas: canvas)
        canvas.onChartChanged = { [weak mounted] chart in mounted?.writes.append(chart) }
        return mounted
    }

    private func begin(_ mounted: Mounted, fixture: Fixture, route: Route) throws -> CueBoundaryPanFixture {
        let frame: CGRect
        switch route {
        case .body:
            frame = try cue(fixture.cueID, in: cachedLayout(mounted.canvas)).frame
        case .handle:
            let handle = try XCTUnwrap(mounted.canvas.subviews.compactMap { $0 as? LeadSheetAnnotationPositionHandleView }.first)
            XCTAssertEqual(handle.accessibilityLabel, "Move Up or Down")
            frame = handle.frame
        }
        mounted.start = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(mounted.canvas.beginRenderedObjectMoveTouch(at: mounted.start, touchType: .pencil))
        let pan = CueBoundaryPanFixture(point: mounted.start, state: .began)
        mounted.canvas.handleRenderedObjectMovePan(pan)
        return pan
    }

    private func move(_ pan: CueBoundaryPanFixture, from start: CGPoint, by dy: CGFloat,
        state: UIGestureRecognizer.State, on canvas: LeadSheetCanvasUIKitView) {
        pan.point = CGPoint(x: start.x, y: start.y + dy)
        pan.simulatedTranslation = CGPoint(x: 0, y: dy)
        pan.simulatedState = state
        canvas.handleRenderedObjectMovePan(pan)
    }

    private func preview(_ canvas: LeadSheetCanvasUIKitView, route: Route) throws -> LeadSheetCueTextLayout {
        switch route {
        case .body:
            let drag: ActiveCueTextMoveDrag = try XCTUnwrap(privateValue("activeCueTextMoveDrag", in: canvas))
            return try XCTUnwrap(drag.currentProjection).cueLayout
        case .handle:
            return try XCTUnwrap(privateValue("cueAnnotationPositionPreview", in: canvas))
        }
    }

    private func assertOneVerticalCommit(_ mounted: Mounted, fixture: Fixture,
        preview: LeadSheetCueTextLayout, originalGeometry: Geometry,
        file: StaticString = #filePath, line: UInt = #line) throws {
        mounted.canvas.layoutIfNeeded()
        XCTAssertEqual(mounted.writes.count, 1, file: file, line: line)
        XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), originalGeometry, file: file, line: line)
        let rendered = try cue(fixture.cueID, in: cachedLayout(mounted.canvas))
        assertEqual(rendered.frame, preview.frame, file: file, line: line)
        assertOnlyVerticalOffsetChanged(from: mounted.baseline, to: mounted.canvas.chart,
            cueID: fixture.cueID, file: file, line: line)
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(mounted.canvas.chart))
        let reopenedLayout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
        XCTAssertEqual(Geometry(reopenedLayout), originalGeometry, file: file, line: line)
        assertEqual(try cue(fixture.cueID, in: reopenedLayout).frame, preview.frame, file: file, line: line)
        XCTAssertEqual(reopened, mounted.canvas.chart, file: file, line: line)
    }

    private func assertOnlyVerticalOffsetChanged(from baseline: Chart, to changed: Chart, cueID: UUID,
        file: StaticString = #filePath, line: UInt = #line) {
        var normalized = changed
        guard let index = normalized.cueTexts.firstIndex(where: { $0.id == cueID }),
              let source = baseline.cueText(id: cueID) else {
            return XCTFail("Cue disappeared during vertical movement", file: file, line: line)
        }
        normalized.cueTexts[index].verticalOffset = source.verticalOffset
        normalized.updatedAt = baseline.updatedAt
        XCTAssertEqual(normalized, baseline,
            "Only vertical placement and the edit timestamp may change; anchors, beats, other objects and ink must match",
            file: file, line: line)
    }

    private func assertClearsNeighborStaves(_ frame: CGRect, cueID: UUID, in layout: LeadSheetPageLayout,
        file: StaticString = #filePath, line: UInt = #line) {
        let sourceIndex = layout.systems.firstIndex { $0.measures.flatMap(\.cueTextLayouts).contains { $0.id == cueID } }
        for (index, system) in layout.systems.enumerated() where index != sourceIndex {
            for staff in system.measures.map(\.staffFrame) {
                XCTAssertFalse(frame.intersects(staff), "A cue must stop before a neighboring staff", file: file, line: line)
            }
        }
    }

    private func cue(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetCueTextLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.cueTextLayouts).first { $0.id == id })
    }

    private func cachedLayout(_ canvas: LeadSheetCanvasUIKitView) throws -> LeadSheetPageLayout {
        try XCTUnwrap(privateValue("pageLayout", in: canvas))
    }

    private func privateValue<T>(_ name: String, in canvas: LeadSheetCanvasUIKitView) -> T? {
        guard let stored = Mirror(reflecting: canvas).children.first(where: { $0.label == name })?.value else { return nil }
        if let value = stored as? T { return value }
        let mirror = Mirror(reflecting: stored)
        return mirror.displayStyle == .optional ? mirror.children.first?.value as? T : nil
    }

    private func assertEqual(_ actual: CGRect, _ expected: CGRect,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}

@MainActor
private final class CueBoundaryPanFixture: UIPanGestureRecognizer {
    var point: CGPoint
    var simulatedState: UIGestureRecognizer.State
    var simulatedTranslation = CGPoint.zero

    init(point: CGPoint, state: UIGestureRecognizer.State) {
        self.point = point
        simulatedState = state
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }

    override var numberOfTouches: Int { 1 }
    override func location(in view: UIView?) -> CGPoint { point }
    override func translation(in view: UIView?) -> CGPoint { simulatedTranslation }
}
#endif

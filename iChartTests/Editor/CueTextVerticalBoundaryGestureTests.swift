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

    func testDirectAndHeldTextMoveBothWaysWithoutChangingStaffOrPageGeometry() throws {
        for style in styles {
            for position in positions {
                for route in Route.allCases {
                    let fixture = try fixture(style: style, position: position)
                    let mounted = try mount(fixture, route: route)
                    defer { mounted.close() }
                    let before = try cachedLayout(mounted.canvas)
                    let geometry = Geometry(before)
                    let original = try cue(fixture.cueID, in: before)
                    let distance: CGFloat = position == .above ? -8 : 8
                    let gesture = try begin(mounted, fixture: fixture, route: route)
                    move(gesture, from: mounted.start, by: distance, state: .changed, on: mounted.canvas)
                    let preview = try preview(mounted.canvas)
                    XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
                    XCTAssertTrue(mounted.writes.isEmpty)
                    XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), geometry)
                    XCTAssertEqual(preview.frame.minX, original.frame.minX, accuracy: 0.001)
                    XCTAssertEqual(preview.frame.minY - original.frame.minY, distance, accuracy: 0.001)
                    move(gesture, from: mounted.start, by: distance, state: .ended, on: mounted.canvas)
                    try assertOneVerticalCommit(mounted, fixture: fixture, preview: preview,
                        originalGeometry: geometry)
                }
            }
        }
    }

    func testHeldTextCanCrossANeighboringStaffWithoutAnArtificialHeightStopOrRepacking() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .below)
            let mounted = try mount(fixture, route: .hold)
            defer { mounted.close() }
            let before = try cachedLayout(mounted.canvas)
            let geometry = Geometry(before)
            let original = try cue(fixture.cueID, in: before)
            let gesture = try begin(mounted, fixture: fixture, route: .hold)
            move(gesture, from: mounted.start, by: 100, state: .changed, on: mounted.canvas)
            let preview = try preview(mounted.canvas)
            XCTAssertEqual(preview.frame.minY - original.frame.minY, 100, accuracy: 0.001)
            XCTAssertEqual(preview.frame.minX, original.frame.minX, accuracy: 0.001)
            XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), geometry)
            XCTAssertTrue(mounted.writes.isEmpty)
            move(gesture, from: mounted.start, by: 100, state: .ended, on: mounted.canvas)
            XCTAssertGreaterThan(try XCTUnwrap(mounted.canvas.chart.cueText(id: fixture.cueID)?.manualVerticalOffset), 72)
            try assertOneVerticalCommit(mounted, fixture: fixture, preview: preview, originalGeometry: geometry)
        }
    }

    func testLegacyVisiblePlacementRespondsImmediatelyAndHugeMovesStayOnTheAttachmentPage() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position,
                    verticalOffset: position == .above ? -72 : 72)
                for route in Route.allCases {
                    let mounted = try mount(fixture, route: route)
                    defer { mounted.close() }
                    let before = try cachedLayout(mounted.canvas)
                    let original = try cue(fixture.cueID, in: before)
                    let geometry = Geometry(before)
                    let gesture = try begin(mounted, fixture: fixture, route: route)
                    let inward: CGFloat = position == .above ? 8 : -8
                    move(gesture, from: mounted.start, by: inward, state: .changed, on: mounted.canvas)
                    let immediate = try preview(mounted.canvas)
                    XCTAssertEqual(immediate.frame.minY - original.frame.minY, inward, accuracy: 0.001,
                        "A cue must follow the displayed starting position without a hidden requested-offset dead zone")
                    move(gesture, from: mounted.start, by: position == .above ? -100_000 : 100_000,
                        state: .changed, on: mounted.canvas)
                    let extreme = try preview(mounted.canvas)
                    XCTAssertGreaterThanOrEqual(extreme.frame.minY, before.paperFrame.minY)
                    XCTAssertLessThanOrEqual(extreme.frame.maxY, before.paperFrame.maxY)
                    XCTAssertEqual(extreme.frame.minX, original.frame.minX, accuracy: 0.001)
                    XCTAssertEqual(Geometry(try cachedLayout(mounted.canvas)), geometry)
                    move(gesture, from: mounted.start, by: inward, state: .ended, on: mounted.canvas)
                    try assertOneVerticalCommit(mounted, fixture: fixture, preview: immediate,
                        originalGeometry: geometry)
                }
            }
        }
    }

    func testStationaryCancelledAndStaleHoldsDoNotWriteOrPerformCueActions() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .above)
            let mounted = try mount(fixture, route: .hold)
            defer { mounted.close() }
            clearSelection(mounted.canvas)
            var selected = 0
            var edited = 0
            mounted.canvas.onCueTextSelectedFromCanvas = { _ in selected += 1 }
            mounted.canvas.onCueTextEditRequested = { _ in edited += 1 }
            let still = try begin(mounted, fixture: fixture, route: .hold)
            move(still, from: mounted.start, by: 0, state: .ended, on: mounted.canvas)
            XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
            XCTAssertTrue(mounted.writes.isEmpty)
            let restingCue = try cue(fixture.cueID, in: cachedLayout(mounted.canvas))
            let touchdown = CGPoint(x: restingCue.frame.midX, y: restingCue.frame.midY)
            XCTAssertTrue(mounted.canvas.beginCueTextPressTouch(at: touchdown, touchType: .pencil))
            let drifted = CueBoundaryHoldFixture(point: CGPoint(x: touchdown.x + 5, y: touchdown.y - 3),
                state: .began)
            mounted.canvas.handleCueTextPressGesture(drifted)
            assertEqual(try preview(mounted.canvas).frame, restingCue.frame)
            drifted.simulatedState = .ended
            mounted.canvas.handleCueTextPressGesture(drifted)
            XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
            XCTAssertTrue(mounted.writes.isEmpty)
            for state: UIGestureRecognizer.State in [.cancelled, .failed] {
                let gesture = try begin(mounted, fixture: fixture, route: .hold)
                move(gesture, from: mounted.start, by: 8, state: .changed, on: mounted.canvas)
                move(gesture, from: mounted.start, by: 8, state: state, on: mounted.canvas)
                XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
                XCTAssertTrue(mounted.writes.isEmpty)
                XCTAssertNil(privateValue("activeCueTextMoveDrag", in: mounted.canvas) as ActiveCueTextMoveDrag?)
            }
            let original = try cue(fixture.cueID, in: cachedLayout(mounted.canvas))
            let point = CGPoint(x: original.frame.midX, y: original.frame.midY)
            XCTAssertTrue(mounted.canvas.beginCueTextPressTouch(at: point, touchType: .pencil))
            var changed = mounted.canvas.chart
            XCTAssertTrue(changed.updateCueText(fixture.cueID, text: "Changed meanwhile"))
            mounted.canvas.chart = changed
            let stale = CueBoundaryHoldFixture(point: point, state: .began)
            mounted.canvas.handleCueTextPressGesture(stale)
            stale.simulatedState = .ended
            mounted.canvas.handleCueTextPressGesture(stale)
            XCTAssertTrue(mounted.writes.isEmpty)
            XCTAssertEqual(mounted.canvas.chart, changed)
            XCTAssertEqual(selected, 0)
            XCTAssertEqual(edited, 0)
        }
    }

    func testCueMovementTranslatesOneRasterWithoutBackingOrParentChangesAndClearsOnCancel() throws {
        for style in styles {
            for route in Route.allCases {
                let fixture = try fixture(style: style, position: .above)
                let mounted = try mount(fixture, route: route)
                defer { mounted.close() }
                if route == .hold { clearSelection(mounted.canvas) }
                var selectionChanges = 0
                var parentSelections = 0
                mounted.canvas.onCueTextSelectionChanged = { _ in selectionChanges += 1 }
                mounted.canvas.onCueTextSelectedFromCanvas = { _ in parentSelections += 1 }
                let gesture = try begin(mounted, fixture: fixture, route: route)
                let overlay = try XCTUnwrap(mounted.canvas.layer.sublayers?.first { $0.name == "cue-text-drag" })
                let glyph = try XCTUnwrap(overlay.sublayers?.first { $0.name == "glyph" })
                let guide = try XCTUnwrap(overlay.sublayers?.first { $0.name == "guide" } as? CAShapeLayer)
                let anchor = try XCTUnwrap(overlay.sublayers?.first { $0.name == "anchor" } as? CAShapeLayer)
                let image = try XCTUnwrap(glyph.contents)
                mounted.canvas.layer.displayIfNeeded()
                for sample in 1...30 {
                    move(gesture, from: mounted.start, by: -CGFloat(sample) / 5,
                        state: .changed, on: mounted.canvas)
                    let current = try preview(mounted.canvas)
                    XCTAssertFalse(mounted.canvas.layer.needsDisplay(), "A Pencil sample must only translate the cue layers")
                    XCTAssertTrue((glyph.contents as AnyObject?) === (image as AnyObject))
                    XCTAssertEqual(glyph.position.x, current.frame.midX, accuracy: 0.001)
                    XCTAssertEqual(glyph.position.y, current.frame.midY, accuracy: 0.001)
                    XCTAssertNotNil(guide.path)
                    XCTAssertEqual(mounted.canvas.chart, mounted.baseline)
                    XCTAssertTrue(mounted.writes.isEmpty)
                    XCTAssertEqual(selectionChanges, 0)
                    XCTAssertEqual(parentSelections, 0)
                }
                move(gesture, from: mounted.start, by: -6, state: .cancelled, on: mounted.canvas)
                XCTAssertNil(overlay.superlayer)
                XCTAssertNil(glyph.contents)
                XCTAssertNil(guide.path)
                XCTAssertNil(anchor.path)
                XCTAssertEqual(selectionChanges, 0)
                XCTAssertEqual(parentSelections, 0)
                XCTAssertTrue(mounted.writes.isEmpty)
            }
        }
    }

    func testHoldAdmissionUsesTheExactCueBoxAndPreservesControlsAndDeviceTouchRules() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .above)
            let mounted = try mount(fixture, route: .hold, environment: .device)
            defer { mounted.close() }
            let cue = try cue(fixture.cueID, in: cachedLayout(mounted.canvas))
            XCTAssertFalse(mounted.canvas.subviews.contains { $0 is LeadSheetAnnotationPositionHandleView })
            let control = LeadSheetCueTextEditOverlayGeometry.controlFrames(for: cue)
            for frame in [control.edit, control.shrink, control.grow, control.delete] {
                XCTAssertFalse(mounted.canvas.beginCueTextPressTouch(at: CGPoint(x: frame.midX, y: frame.midY), touchType: .pencil))
            }
            let selectedBox = LeadSheetCueTextEditOverlayGeometry.editFrame(for: cue)
            XCTAssertFalse(mounted.canvas.beginCueTextPressTouch(at: CGPoint(x: selectedBox.minX - 1, y: cue.frame.midY), touchType: .pencil))
            let point = CGPoint(x: cue.frame.midX, y: cue.frame.midY)
            XCTAssertFalse(mounted.canvas.beginCueTextPressTouch(at: point, touchType: .direct))
            clearSelection(mounted.canvas)
            XCTAssertTrue(mounted.canvas.beginCueTextPressTouch(at: point, touchType: .pencil))
            let installed = try XCTUnwrap(mounted.canvas.gestureRecognizers?.compactMap { $0 as? UILongPressGestureRecognizer }
                .first { $0.name == "cue-text-press-and-grab" })
            XCTAssertEqual(installed.minimumPressDuration, 0.28)
            XCTAssertEqual(installed.numberOfTouchesRequired, 1)
            var selected = 0
            var edited = 0
            mounted.canvas.onCueTextSelectedFromCanvas = { _ in selected += 1 }
            mounted.canvas.onCueTextEditRequested = { _ in edited += 1 }
            let gesture = try begin(mounted, fixture: fixture, route: .hold)
            // A lost competing pan must not cancel an active stationary hold.
            mounted.canvas.handleRenderedObjectMovePan(CueBoundaryPanFixture(point: point, state: .cancelled))
            XCTAssertNotNil(privateValue("activeCueTextMoveDrag", in: mounted.canvas) as ActiveCueTextMoveDrag?)
            move(gesture, from: mounted.start, dx: 28, by: 18, state: .ended, on: mounted.canvas)
            XCTAssertEqual(mounted.writes.count, 1)
            let moved = try self.cue(fixture.cueID, in: cachedLayout(mounted.canvas))
            XCTAssertGreaterThan(moved.frame.minX, cue.frame.minX)
            XCTAssertGreaterThan(moved.frame.minY, cue.frame.minY)
            XCTAssertEqual(selected, 0)
            XCTAssertEqual(edited, 0)
        }
    }

    func testCueAccessibilityMovesTheCueWithoutAddingAVisibleOrInterceptingHandle() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .above)
            let mounted = try mount(fixture, route: .hold)
            defer { mounted.close() }
            let accessible = try XCTUnwrap(mounted.canvas.subviews.compactMap { $0 as? LeadSheetCueTextAccessibilityView }.first)
            XCTAssertFalse(accessible.isUserInteractionEnabled)
            XCTAssertFalse(accessible.isOpaque)
            XCTAssertTrue(accessible.accessibilityTraits.contains(.adjustable))
            XCTAssertEqual(accessible.accessibilityCustomActions?.map(\.name), ["Move Left", "Move Right"])
            XCTAssertTrue(accessible.accessibilityHint?.contains("Press and hold") == true)
            let before = try cue(fixture.cueID, in: cachedLayout(mounted.canvas))
            accessible.accessibilityDecrement()
            XCTAssertEqual(mounted.writes.count, 1)
            let moved = try cue(fixture.cueID, in: cachedLayout(mounted.canvas))
            XCTAssertEqual(moved.frame.minX, before.frame.minX, accuracy: 0.001)
            XCTAssertEqual(moved.frame.minY, before.frame.minY + 8, accuracy: 0.001)
        }
    }

    func testSelectedHeldCueUpdatesItsMeasureContextAfterReleaseWithoutOpeningAnEditor() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .above)
            let mounted = try mount(fixture, route: .hold)
            defer { mounted.close() }
            let before = try cachedLayout(mounted.canvas)
            let original = try cue(fixture.cueID, in: before)
            let sourceID = try XCTUnwrap(fixture.chart.cueText(id: fixture.cueID)?.anchorMeasureID)
            let system = try XCTUnwrap(before.systems.first { $0.measures.contains { $0.sourceMeasureID == sourceID } })
            let destination = try XCTUnwrap(system.measures.last)
            let destinationID = try XCTUnwrap(destination.sourceMeasureID)
            XCTAssertNotEqual(destinationID, sourceID)
            var measureChanges: [UUID?] = []
            var cueActions = 0
            mounted.canvas.onMeasureSelectionChanged = { measureChanges.append($0) }
            mounted.canvas.onCueTextSelectedFromCanvas = { _ in cueActions += 1 }
            mounted.canvas.onCueTextEditRequested = { _ in cueActions += 1 }
            let gesture = try begin(mounted, fixture: fixture, route: .hold)
            let dx = destination.staffFrame.minX + 20 - original.frame.minX
            move(gesture, from: mounted.start, dx: dx, by: 0, state: .changed, on: mounted.canvas)
            XCTAssertTrue(measureChanges.isEmpty)
            XCTAssertEqual(mounted.canvas.selectedMeasureID, sourceID)
            move(gesture, from: mounted.start, dx: dx, by: 0, state: .ended, on: mounted.canvas)
            XCTAssertEqual(mounted.canvas.chart.cueText(id: fixture.cueID)?.anchorMeasureID, destinationID)
            XCTAssertEqual(mounted.canvas.selectedMeasureID, destinationID)
            XCTAssertEqual(measureChanges, [destinationID])
            XCTAssertEqual(mounted.writes.count, 1)
            XCTAssertEqual(cueActions, 0)
        }
    }

    func testCueAttachmentGuideDetachesAndReattachesDuringTheHeldGrab() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .above)
            let mounted = try mount(fixture, route: .hold)
            defer { mounted.close() }
            let layout = try cachedLayout(mounted.canvas)
            let original = try cue(fixture.cueID, in: layout)
            let gesture = try begin(mounted, fixture: fixture, route: .hold)
            let overlay = try XCTUnwrap(mounted.canvas.layer.sublayers?.first { $0.name == "cue-text-drag" })
            let guide = try XCTUnwrap(overlay.sublayers?.first { $0.name == "guide" } as? CAShapeLayer)
            let anchor = try XCTUnwrap(overlay.sublayers?.first { $0.name == "anchor" } as? CAShapeLayer)
            move(gesture, from: mounted.start, dx: layout.paperFrame.minX + 8 - original.frame.minX,
                by: 0, state: .changed, on: mounted.canvas)
            XCTAssertTrue(guide.isHidden)
            XCTAssertTrue(anchor.isHidden)
            XCTAssertNil(guide.path)
            move(gesture, from: mounted.start, by: 0, state: .changed, on: mounted.canvas)
            XCTAssertFalse(guide.isHidden)
            XCTAssertFalse(anchor.isHidden)
            let path = try XCTUnwrap(guide.path)
            XCTAssertEqual(path.currentPoint.x + guide.frame.minX, anchor.position.x, accuracy: 0.001)
            XCTAssertEqual(path.currentPoint.y + guide.frame.minY, anchor.position.y, accuracy: 0.001)
            move(gesture, from: mounted.start, by: 0, state: .cancelled, on: mounted.canvas)
            XCTAssertNil(overlay.superlayer)
            XCTAssertTrue(mounted.writes.isEmpty)
        }
    }

    private enum Route: CaseIterable { case body, hold }

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
            canvas.onCueTextSelectionChanged = nil
            canvas.onCueTextSelectedFromCanvas = nil
            canvas.onCueTextEditRequested = nil
            canvas.onMeasureSelectionChanged = nil
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

    private func mount(_ fixture: Fixture, route: Route,
        environment: LeadSheetLiveInkInputPolicy.RuntimeEnvironment = .simulator) throws -> Mounted {
        let frame = CGRect(origin: .zero, size: pageSize)
        let canvas = LeadSheetCanvasUIKitView(frame: frame, chordInkRecognizer: ChordInkMaximumTrustRecognizer(),
            inputEnvironment: environment)
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

    private func clearSelection(_ canvas: LeadSheetCanvasUIKitView) {
        canvas.applyParentSelectionState(selectedMeasureID: nil, selectedNoteSelection: nil,
            selectedChordID: nil, selectedCommittedBarlineMeasureID: nil, selectedCueTextID: nil,
            selectedRoadmapMarkerID: nil, selectedEndingSpanID: nil)
    }

    private func begin(_ mounted: Mounted, fixture: Fixture, route: Route) throws -> UIGestureRecognizer {
        let frame = try cue(fixture.cueID, in: cachedLayout(mounted.canvas)).frame
        mounted.start = CGPoint(x: frame.midX, y: frame.midY)
        switch route {
        case .body:
            XCTAssertTrue(mounted.canvas.beginRenderedObjectMoveTouch(at: mounted.start, touchType: .pencil))
            let pan = CueBoundaryPanFixture(point: mounted.start, state: .began)
            mounted.canvas.handleRenderedObjectMovePan(pan)
            return pan
        case .hold:
            XCTAssertTrue(mounted.canvas.beginCueTextPressTouch(at: mounted.start, touchType: .pencil))
            let hold = CueBoundaryHoldFixture(point: mounted.start, state: .began)
            mounted.canvas.handleCueTextPressGesture(hold)
            return hold
        }
    }

    private func move(_ gesture: UIGestureRecognizer, from start: CGPoint, dx: CGFloat = 0, by dy: CGFloat,
        state: UIGestureRecognizer.State, on canvas: LeadSheetCanvasUIKitView) {
        let point = CGPoint(x: start.x + dx, y: start.y + dy)
        if let pan = gesture as? CueBoundaryPanFixture {
            pan.point = point
            pan.simulatedTranslation = CGPoint(x: dx, y: dy)
            pan.simulatedState = state
            canvas.handleRenderedObjectMovePan(pan)
        } else if let hold = gesture as? CueBoundaryHoldFixture {
            hold.point = point
            hold.simulatedState = state
            canvas.handleCueTextPressGesture(hold)
        } else { XCTFail("Unexpected mounted gesture fixture") }
    }

    private func preview(_ canvas: LeadSheetCanvasUIKitView) throws -> LeadSheetCueTextLayout {
        let drag: ActiveCueTextMoveDrag = try XCTUnwrap(privateValue("activeCueTextMoveDrag", in: canvas))
        return try XCTUnwrap(drag.currentProjection).cueLayout
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
        normalized.cueTexts[index].manualVerticalOffset = source.manualVerticalOffset
        normalized.updatedAt = baseline.updatedAt
        XCTAssertEqual(normalized, baseline,
            "Only vertical placement and the edit timestamp may change; anchors, beats, other objects and ink must match",
            file: file, line: line)
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
@MainActor
private final class CueBoundaryHoldFixture: UILongPressGestureRecognizer {
    var point: CGPoint
    var simulatedState: UIGestureRecognizer.State
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
}
#endif

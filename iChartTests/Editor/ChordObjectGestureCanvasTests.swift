#if canImport(UIKit)
import UIKit
import PencilKit
import XCTest
@testable import iChart

@MainActor
final class ChordObjectGestureCanvasTests: XCTestCase {
    func testCanvasEdgeWidthControlMatchesVisibleRoutingInBothStyles() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            let authored = try chart(style: style, text: "Db7(b9)")
            var event = authored.measures[0].chordEvents[0]
            var original = Chart.blank(title: "Canvas edge controls", measureCount: 4, layoutStyle: style)
            for systemIndex in original.systems.indices {
                for measureIndex in original.systems[systemIndex].measures.indices {
                    original.systems[systemIndex].measures[measureIndex].authoringState = .committed
                }
            }
            event.manualDisplayWidth = 60
            event.manualLaneFraction = 0.9999
            event.manualVisualLaneFraction = 0.9999
            let lastMeasureIndex = original.systems[0].measures.count - 1
            original.systems[0].measures[lastMeasureIndex].chordEvents = [event]
            let host = mount(original)
            defer { host.close() }
            host.canvas.selectedChordID = event.id
            let glyph = try chordLayout(id: event.id, in: host.canvas)
            let unbounded = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph).trailingResize
                .insetBy(dx: -LeadSheetChordEditOverlayGeometry.controlHitOutset,
                    dy: -LeadSheetChordEditOverlayGeometry.controlHitOutset)
            XCTAssertGreaterThan(unbounded.maxX, host.canvas.bounds.maxX,
                "This full-row fixture must actually require the edge fallback")
            let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph, within: host.canvas.bounds)
            let widthHit = controls.trailingResize.insetBy(
                dx: -LeadSheetChordEditOverlayGeometry.controlHitOutset,
                dy: -LeadSheetChordEditOverlayGeometry.controlHitOutset)
            XCTAssertTrue(host.canvas.bounds.contains(widthHit))
            XCTAssertFalse(widthHit.intersects(LeadSheetChordEditOverlayGeometry.bodySelectionFrame(for: glyph)))
            let start = CGPoint(x: controls.trailingResize.midX, y: controls.trailingResize.midY)
            XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
            let pan = ChordMovePanFixture(point: CGPoint(x: start.x + 10, y: start.y),
                translation: CGPoint(x: 10, y: 0), state: .began, coordinateView: host.canvas)
            host.canvas.handleRenderedObjectMovePan(pan)
            pan.simulatedState = .ended
            host.canvas.handleRenderedObjectMovePan(pan)
            let resized = try XCTUnwrap(host.canvas.chart.chordEvent(id: event.id))
            XCTAssertNotEqual(resized.manualHorizontalScale, event.manualHorizontalScale)
            XCTAssertEqual(resized.sourceInkData, event.sourceInkData)
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.canvas.bounds).image { _ in
                host.canvas.drawHierarchy(in: host.canvas.bounds, afterScreenUpdates: true)
            })
            attachment.name = "chord-edge-controls-\(style)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testMovingPreviewReusesGlyphWithoutBackingRedrawOrChartWrites() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            let original = try chart(style: style, text: "C")
            let host = mount(original)
            defer { host.close() }
            let id = original.measures[0].chordEvents[0].id
            let chord = try chordLayout(id: id, in: host.canvas)
            let start = CGPoint(x: chord.frame.midX, y: chord.frame.midY)
            XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
            let event = ChordMovePanFixture(point: CGPoint(x: start.x + 24, y: start.y),
                translation: CGPoint(x: 24, y: 0), state: .began, coordinateView: host.canvas)
            var writes = 0
            host.canvas.onChartChanged = { _ in writes += 1 }
            host.canvas.handleRenderedObjectMovePan(event)
            let overlay = try XCTUnwrap(host.canvas.subviews.compactMap { $0 as? LeadSheetChordMoveOverlayView }.first)
            let glyph = try XCTUnwrap(overlay.layer.sublayers?.first { $0.name == "chordMove.glyph" })
            let image = try XCTUnwrap(glyph.contents)
            let width = glyph.bounds.width
            XCTAssertTrue(overlay.isActive)
            host.canvas.layer.displayIfNeeded()
            XCTAssertFalse(host.canvas.layer.needsDisplay())
            event.simulatedState = .changed
            for step in 1...60 {
                event.point = CGPoint(x: start.x + 24 + CGFloat(step), y: start.y + 3)
                host.canvas.handleRenderedObjectMovePan(event)
                XCTAssertFalse(host.canvas.layer.needsDisplay(), "A movement update must not redraw the document")
                XCTAssertTrue((glyph.contents as AnyObject?) === (image as AnyObject))
                XCTAssertEqual(glyph.bounds.width, width)
            }
            XCTAssertEqual(host.canvas.chart, original)
            XCTAssertEqual(writes, 0)
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.canvas.bounds).image { _ in
                host.canvas.drawHierarchy(in: host.canvas.bounds, afterScreenUpdates: true)
            })
            attachment.name = "chord-drag-preview-\(style)"
            attachment.lifetime = .keepAlways
            add(attachment)
            event.simulatedState = .cancelled
            host.canvas.handleRenderedObjectMovePan(event)
            XCTAssertFalse(overlay.isActive)
            XCTAssertTrue(overlay.isHidden)
            XCTAssertNil(glyph.contents)
            XCTAssertEqual(writes, 0)
        }
    }

    func testModeAndBoundsChangesCancelTheMovingOverlayWithoutWriting() throws {
        for changesMode in [false, true] {
            let original = try chart(style: .rhythmSectionSheet, text: "G")
            let host = mount(original)
            defer { host.close() }
            let id = original.measures[0].chordEvents[0].id
            let chord = try chordLayout(id: id, in: host.canvas)
            let start = CGPoint(x: chord.frame.midX, y: chord.frame.midY)
            XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
            let event = ChordMovePanFixture(point: CGPoint(x: start.x + 24, y: start.y),
                translation: CGPoint(x: 24, y: 0), state: .began, coordinateView: host.canvas)
            var writes = 0
            host.canvas.onChartChanged = { _ in writes += 1 }
            host.canvas.handleRenderedObjectMovePan(event)
            let overlay = try XCTUnwrap(host.canvas.subviews.compactMap { $0 as? LeadSheetChordMoveOverlayView }.first)
            XCTAssertTrue(overlay.isActive)
            if changesMode {
                host.canvas.interactionMode = .measureEdit
            } else {
                host.canvas.bounds.size.width += 30
                host.canvas.setNeedsLayout()
                host.canvas.layoutIfNeeded()
            }
            XCTAssertFalse(overlay.isActive)
            XCTAssertNil(host.canvas.chordMovePreviewFrame)
            event.simulatedState = .ended
            host.canvas.handleRenderedObjectMovePan(event)
            XCTAssertEqual(host.canvas.chart, original)
            XCTAssertEqual(writes, 0)
        }
    }

    func testPencilLeavingAndReturningToXCannotReviveDeleteIntent() throws {
        let original = try chart(style: .rhythmSectionSheet, text: "C")
        let host = mount(original)
        defer { host.close() }
        let id = original.measures[0].chordEvents[0].id
        host.canvas.selectedChordID = id
        let chord = try chordLayout(id: id, in: host.canvas)
        let control = LeadSheetChordEditOverlayGeometry.controlFrames(for: chord).delete
        let start = CGPoint(x: control.midX, y: control.midY)
        let overlay = try XCTUnwrap(host.canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
        host.canvas.beginRenderedEditTap(at: start, touchType: .pencil)
        let excursion = ChordPencilTouchFixture(point: CGPoint(x: start.x + 8, y: start.y), coordinateView: host.canvas)
        overlay.touchesMoved([excursion], with: nil)
        overlay.touchesMoved([ChordPencilTouchFixture(point: start, coordinateView: host.canvas)], with: nil)
        host.canvas.handleRenderedEditTapGesture(ChordTapFixture(point: start, coordinateView: host.canvas))
        XCTAssertEqual(host.canvas.chart, original)
        host.canvas.beginRenderedEditTap(at: start, touchType: .pencil)
        host.canvas.handleRenderedEditTapGesture(ChordTapFixture(point: start, coordinateView: host.canvas))
        XCTAssertNil(host.canvas.chart.chordEvent(id: id))
    }

    func testPencilSelectMovesUnselectedNarrowChordInOneGestureAndAppliesBeganDelta() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            for text in ["C", "G"] {
                let original = try chart(style: style, text: text)
                let host = mount(original)
                defer { host.close() }
                let chordID = original.measures[0].chordEvents[0].id
                let glyph = try chordLayout(id: chordID, in: host.canvas)
                let start = CGPoint(x: glyph.frame.minX + 1, y: glyph.frame.midY)
                let current = CGPoint(x: start.x + 54, y: start.y + 6)
                let pan = try installedMovePan(in: host.canvas)
                var writes = [Chart]()
                host.canvas.onChartChanged = { writes.append($0) }

                XCTAssertNil(host.canvas.selectedChordID)
                XCTAssertTrue(try receivesPencil(pan, at: start, in: host.canvas))
                XCTAssertTrue(host.canvas.gestureRecognizerShouldBegin(pan),
                    "The exact admitted Pencil body target must survive the pan threshold")
                // A retained touch-down is authoritative even when translation is
                // reset before UIKit delivers began. Startup must not hit-test current.
                let event = ChordMovePanFixture(point: current, translation: .zero,
                    state: .began, coordinateView: host.canvas)
                host.canvas.handleRenderedObjectMovePan(event)

                XCTAssertEqual(host.canvas.selectedChordID, chordID)
                let preview = try XCTUnwrap(host.canvas.chordMovePreviewFrame)
                XCTAssertGreaterThan(preview.minX, glyph.frame.minX + 30,
                    "The movement already accumulated before began must appear immediately")
                XCTAssertEqual(preview.minY, glyph.frame.minY + 6, accuracy: 0.001)
                XCTAssertTrue(writes.isEmpty, "Previewing a move must not save on each Pencil event")

                event.simulatedState = .ended
                host.canvas.handleRenderedObjectMovePan(event)

                XCTAssertEqual(writes.count, 1)
                XCTAssertNil(host.canvas.chordMovePreviewFrame)
                XCTAssertEqual(host.canvas.chart.measures.flatMap(\.chordEvents).map(\.id),
                    original.measures.flatMap(\.chordEvents).map(\.id))
                let moved = try XCTUnwrap(host.canvas.chart.chordEvent(id: chordID))
                XCTAssertEqual(moved.rawInput, text)
                XCTAssertNotEqual(moved.manualVisualLaneFraction,
                    original.chordEvent(id: chordID)?.manualVisualLaneFraction)
                XCTAssertEqual(moved.sourceInkData, original.chordEvent(id: chordID)?.sourceInkData)
                let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(host.canvas.chart))
                XCTAssertEqual(reopened, host.canvas.chart)
                let archive = try XCTUnwrap(reopened.chordEvent(id: chordID)?.sourceInkData)
                XCTAssertEqual(try PKDrawing(data: archive).strokes.count, 1)
            }
        }
    }

    func testFreshlyRenderedChordMovesImmediatelyAfterSwitchingToSelect() throws {
        let rendered = try chart(style: .rhythmSectionSheet, text: "C")
        var beforeRender = rendered
        beforeRender.systems[0].measures[0].chordEvents = []
        let host = mount(beforeRender)
        defer { host.close() }
        host.canvas.interactionMode = .chordEntry
        host.canvas.chart = rendered
        host.canvas.interactionMode = .browse
        host.canvas.layoutIfNeeded()
        let id = rendered.measures[0].chordEvents[0].id
        let glyph = try chordLayout(id: id, in: host.canvas)
        let start = CGPoint(x: glyph.frame.midX, y: glyph.frame.midY)

        XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil),
            "Fresh rendering must not impose a timed Select-mode editing dead zone")
        let event = ChordMovePanFixture(point: CGPoint(x: start.x + 24, y: start.y),
            translation: CGPoint(x: 24, y: 0), state: .began, coordinateView: host.canvas)
        host.canvas.handleRenderedObjectMovePan(event)
        XCTAssertEqual(host.canvas.selectedChordID, id)
        XCTAssertNotNil(host.canvas.chordMovePreviewFrame)
        event.simulatedState = .cancelled
        host.canvas.handleRenderedObjectMovePan(event)
        XCTAssertEqual(host.canvas.chart, rendered)
    }

    func testAdmittedChordRemainsTheDragOwnerWhenSelectionChangesBeforeBegan() throws {
        var original = try chart(style: .rhythmSectionSheet, text: "C")
        var neighbor = original.measures[0].chordEvents[0]
        neighbor.id = UUID()
        neighbor.manualLaneFraction = 0.6
        neighbor.manualVisualLaneFraction = 0.6
        original.systems[0].measures[0].chordEvents.append(neighbor)
        let host = mount(original)
        defer { host.close() }
        let id = original.measures[0].chordEvents[0].id
        let glyph = try chordLayout(id: id, in: host.canvas)
        let start = CGPoint(x: glyph.frame.minX + 1, y: glyph.frame.midY)
        XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
        host.canvas.selectedChordID = neighbor.id
        let event = ChordMovePanFixture(point: CGPoint(x: start.x + 40, y: start.y),
            translation: .zero, state: .began, coordinateView: host.canvas)

        host.canvas.handleRenderedObjectMovePan(event)

        XCTAssertEqual(host.canvas.selectedChordID, id,
            "Startup must consume the admitted chord ID rather than re-resolving selection")
        XCTAssertNotNil(host.canvas.chordMovePreviewFrame)
        event.simulatedState = .cancelled
        host.canvas.handleRenderedObjectMovePan(event)
        XCTAssertEqual(host.canvas.chart, original)
    }

    func testSelectedNarrowGlyphTapCannotDeleteAndBodyToXDoesNotAcquireDeleteIntent() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            let original = try chart(style: style, text: "C")
            let host = mount(original)
            defer { host.close() }
            let chordID = original.measures[0].chordEvents[0].id
            host.canvas.selectedChordID = chordID
            let glyph = try chordLayout(id: chordID, in: host.canvas)
            let body = CGPoint(x: glyph.frame.minX + 1, y: glyph.frame.midY)
            let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph)
            let delete = CGPoint(x: controls.delete.midX, y: controls.delete.midY)
            var writes = 0
            host.canvas.onChartChanged = { _ in writes += 1 }

            host.canvas.beginRenderedEditTap(at: body)
            host.canvas.handleRenderedEditTapGesture(ChordTapFixture(point: body, coordinateView: host.canvas))
            XCTAssertEqual(host.canvas.chart, original)
            host.canvas.beginRenderedEditTap(at: body)
            host.canvas.handleRenderedEditTapGesture(ChordTapFixture(point: delete, coordinateView: host.canvas))

            XCTAssertEqual(host.canvas.chart, original,
                "Touching the body and lifting on the X must not delete")
            XCTAssertEqual(host.canvas.selectedChordID, chordID)
            XCTAssertEqual(writes, 0)
        }
    }

    func testStableExplicitXPencilTapDeletesExactlyOnce() throws {
        let original = try chart(style: .rhythmSectionSheet, text: "G")
        let host = mount(original)
        defer { host.close() }
        let chordID = original.measures[0].chordEvents[0].id
        host.canvas.selectedChordID = chordID
        let glyph = try chordLayout(id: chordID, in: host.canvas)
        let control = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph).delete
        let point = CGPoint(x: control.midX, y: control.midY)
        let overlay = try XCTUnwrap(host.canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
        let tap = try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 1 })
        var writes = [Chart]()
        host.canvas.onChartChanged = { writes.append($0) }

        XCTAssertTrue(try receivesPencil(tap, at: point, in: host.canvas))
        host.canvas.handleRenderedEditTapGesture(ChordTapFixture(point: point, coordinateView: host.canvas))
        XCTAssertNil(host.canvas.chart.chordEvent(id: chordID))
        XCTAssertEqual(writes.count, 1)
        host.canvas.handleRenderedEditTapGesture(ChordTapFixture(point: point, coordinateView: host.canvas))
        XCTAssertEqual(writes.count, 1, "Lift handling must consume destructive tap intent")
    }

    func testPencilMovementWithinTheSameXTargetCannotDeleteButStableTapStillCan() throws {
        let original = try chart(style: .rhythmSectionSheet, text: "C")
        let host = mount(original)
        defer { host.close() }
        let chordID = original.measures[0].chordEvents[0].id
        host.canvas.selectedChordID = chordID
        let glyph = try chordLayout(id: chordID, in: host.canvas)
        let control = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph).delete
        let start = CGPoint(x: control.midX, y: control.midY)
        let shiftedLift = CGPoint(x: start.x + 8, y: start.y)
        let page = LeadSheetPageLayoutEngine.pageLayout(for: original, pageSize: host.canvas.bounds.size)
        let context = RenderedEditContext(pageLayout: page,
            selection: RenderedEditSelectionState(selectedObjectID: .chord(chordID)))
        let router = RenderedEditRouter(providers: [ChordRenderedEditHitTargetProvider()])
        XCTAssertEqual(router.tapTarget(at: start, in: context)?.action, .delete)
        XCTAssertEqual(router.tapTarget(at: shiftedLift, in: context)?.action, .delete)
        var writes = 0
        host.canvas.onChartChanged = { _ in writes += 1 }

        host.canvas.beginRenderedEditTap(at: start, touchType: .pencil)
        host.canvas.handleRenderedEditTapGesture(ChordTapFixture(point: shiftedLift, coordinateView: host.canvas))

        XCTAssertEqual(host.canvas.chart, original,
            "An attempted eight-point Pencil move must not become delete merely because it remains inside the X target")
        XCTAssertEqual(writes, 0)
        host.canvas.beginRenderedEditTap(at: start, touchType: .pencil)
        host.canvas.handleRenderedEditTapGesture(ChordTapFixture(
            point: CGPoint(x: start.x + 1, y: start.y), coordinateView: host.canvas))
        XCTAssertNil(host.canvas.chart.chordEvent(id: chordID))
        XCTAssertEqual(writes, 1, "The same explicit control must still accept an ordinary stable tap")
    }

    func testCancelledRecognizedMoveCannotFallThroughToDelete() throws {
        let original = try chart(style: .rhythmSectionSheet, text: "C")
        let host = mount(original)
        defer { host.close() }
        let chordID = original.measures[0].chordEvents[0].id
        host.canvas.selectedChordID = chordID
        let glyph = try chordLayout(id: chordID, in: host.canvas)
        let start = CGPoint(x: glyph.frame.midX, y: glyph.frame.midY)
        let control = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph).delete
        let delete = CGPoint(x: control.midX, y: control.midY)
        var writes = 0
        host.canvas.onChartChanged = { _ in writes += 1 }

        host.canvas.beginRenderedEditTap(at: delete)
        XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
        let event = ChordMovePanFixture(point: CGPoint(x: start.x + 24, y: start.y),
            translation: CGPoint(x: 24, y: 0), state: .began, coordinateView: host.canvas)
        host.canvas.handleRenderedObjectMovePan(event)
        event.simulatedState = .cancelled
        host.canvas.handleRenderedObjectMovePan(event)
        host.canvas.handleRenderedEditTapGesture(ChordTapFixture(point: delete, coordinateView: host.canvas))

        XCTAssertEqual(host.canvas.chart, original)
        XCTAssertNil(host.canvas.chordMovePreviewFrame)
        XCTAssertEqual(writes, 0)
    }

    func testExplicitResizeAndCorrectionStayAvailableAndTapsAreExclusiveWithMoves() throws {
        let original = try chart(style: .rhythmSectionSheet, text: "G")
        let host = mount(original)
        defer { host.close() }
        let chordID = original.measures[0].chordEvents[0].id
        host.canvas.selectedChordID = chordID
        let glyph = try chordLayout(id: chordID, in: host.canvas)
        let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph)
        let point = CGPoint(x: controls.trailingResize.midX, y: controls.trailingResize.midY)
        let pan = try installedMovePan(in: host.canvas)
        let overlay = try XCTUnwrap(host.canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
        let taps = try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer })
        for tap in taps {
            XCTAssertFalse(host.canvas.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: tap))
        }
        XCTAssertTrue(try receivesPencil(pan, at: point, in: host.canvas))
        XCTAssertTrue(host.canvas.gestureRecognizerShouldBegin(pan))
        let event = ChordMovePanFixture(point: CGPoint(x: point.x + 20, y: point.y),
            translation: CGPoint(x: 20, y: 0), state: .began, coordinateView: host.canvas)
        host.canvas.handleRenderedObjectMovePan(event)
        event.simulatedState = .ended
        host.canvas.handleRenderedObjectMovePan(event)
        let resized = try XCTUnwrap(host.canvas.chart.chordEvent(id: chordID))
        XCTAssertNotEqual(resized.manualHorizontalScale, original.chordEvent(id: chordID)?.manualHorizontalScale)
        XCTAssertEqual(host.canvas.chart.measures.flatMap(\.chordEvents).map(\.id), [chordID])

        let resizedGlyph = try chordLayout(id: chordID, in: host.canvas)
        let body = CGPoint(x: resizedGlyph.frame.midX, y: resizedGlyph.frame.midY)
        let correction = try XCTUnwrap(taps.first { $0.numberOfTapsRequired == 2 })
        XCTAssertTrue(try receivesPencil(correction, at: body, in: host.canvas))
        var corrections = [UUID]()
        host.canvas.onChordCorrectionRequested = { corrections.append($0) }
        let selector = NSSelectorFromString("handleChordCorrectionDoubleTap:")
        XCTAssertTrue(host.canvas.responds(to: selector))
        _ = host.canvas.perform(selector, with: ChordTapFixture(point: body, coordinateView: host.canvas))
        XCTAssertEqual(corrections, [chordID])
    }

    private func chart(style: ChartLayoutStyle, text: String) throws -> Chart {
        var chart = Chart.blank(title: "Pencil chord gesture", measureCount: 2, layoutStyle: style)
        chart.systems[0].measures[0].authoringState = .committed
        chart.systems[0].measures[0].manualLayoutWidth = 280
        chart.systems[0].measures[0].chordEvents = [ChordEvent(id: UUID(),
            symbol: try ChordSymbolParser.parse(text), spellingIntent: .explicit,
            startPosition: BeatPosition(beat: 2, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .quarter, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
            rawInput: text, sourceInkData: sourceArchive(), manualDisplayWidth: 20,
            manualLaneFraction: 0.3, manualVisualLaneFraction: 0.3)]
        return chart
    }

    private func sourceArchive() -> Data {
        let points = [CGPoint(x: 8, y: 14), CGPoint(x: 12, y: 10), CGPoint(x: 16, y: 14)]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.02,
                size: CGSize(width: 2, height: 2), opacity: 1, force: 1,
                azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 20))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path,
            transform: .identity, mask: nil, randomSeed: 21)]).dataRepresentation()
    }

    @MainActor
    private struct Host {
        let canvas: LeadSheetCanvasUIKitView
        let window: UIWindow
        let previousWindow: UIWindow?
        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
    }

    private func mount(_ chart: Chart) -> Host {
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 900, height: 1_400))
        canvas.recognizesChordInk = false
        canvas.chart = chart
        canvas.interactionMode = .browse
        let controller = UIViewController()
        controller.view = canvas
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(frame: canvas.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        return Host(canvas: canvas, window: window, previousWindow: previous)
    }

    private func chordLayout(id: UUID, in canvas: LeadSheetCanvasUIKitView) throws -> LeadSheetChordLayout {
        let page = LeadSheetPageLayoutEngine.pageLayout(for: canvas.chart, pageSize: canvas.bounds.size)
        return try XCTUnwrap(page.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == id })
    }

    private func installedMovePan(in canvas: LeadSheetCanvasUIKitView) throws -> UIPanGestureRecognizer {
        try XCTUnwrap(canvas.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }
            .first { $0.maximumNumberOfTouches == 1 })
    }

    private func receivesPencil(_ recognizer: UIGestureRecognizer, at point: CGPoint,
        in canvas: LeadSheetCanvasUIKitView) throws -> Bool {
        let touch = ChordPencilTouchFixture(point: point, coordinateView: canvas)
        return try XCTUnwrap(recognizer.delegate?.gestureRecognizer?(recognizer, shouldReceive: touch))
    }
}

@MainActor
private final class ChordPencilTouchFixture: UITouch {
    let point: CGPoint
    let coordinateView: UIView
    init(point: CGPoint, coordinateView: UIView) {
        self.point = point
        self.coordinateView = coordinateView
        super.init()
    }
    override var type: UITouch.TouchType { .pencil }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}

@MainActor
private final class ChordMovePanFixture: UIPanGestureRecognizer {
    var point: CGPoint
    var movement: CGPoint
    var simulatedState: UIGestureRecognizer.State
    let coordinateView: UIView
    init(point: CGPoint, translation: CGPoint, state: UIGestureRecognizer.State, coordinateView: UIView) {
        self.point = point
        movement = translation
        simulatedState = state
        self.coordinateView = coordinateView
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
    override var numberOfTouches: Int { 1 }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
    override func translation(in view: UIView?) -> CGPoint { movement }
}

@MainActor
private final class ChordTapFixture: UITapGestureRecognizer {
    let point: CGPoint
    let coordinateView: UIView
    init(point: CGPoint, coordinateView: UIView) {
        self.point = point
        self.coordinateView = coordinateView
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State {
        get { .ended }
        set { }
    }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}
#endif

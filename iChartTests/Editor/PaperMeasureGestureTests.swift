#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class PaperMeasureGestureTests: XCTestCase {
    func testMovingSelectedMeasureHasContinuousPreviewAndOneCommitInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let original = try fixture(style)
            let host = mount(original)
            defer { host.close() }
            let measureID = original.measures[0].id
            host.canvas.selectedMeasureID = measureID
            let page = layout(host.canvas)
            let measure = try XCTUnwrap(page.systems[0].measures.first)
            let handle = LeadSheetMeasureResizeGeometry.moveHandleFrame(for: measure)
            let start = CGPoint(x: handle.midX, y: handle.midY)
            XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
            var writes = 0
            host.canvas.onChartChanged = { _ in writes += 1 }
            let pan = PaperMeasurePan(point: start, movement: .zero, state: .began, view: host.canvas)
            host.canvas.handleRenderedObjectMovePan(pan)
            let overlay = try XCTUnwrap(host.canvas.layer.sublayers?.first { $0.name == "measureMove.snapshot" })
            let image = try XCTUnwrap(overlay.contents)
            host.canvas.layer.displayIfNeeded()
            pan.simulatedState = .changed
            for offset in 1...40 {
                pan.point.x = start.x - CGFloat(offset)
                host.canvas.handleRenderedObjectMovePan(pan)
                XCTAssertTrue(overlay.contents as AnyObject === image as AnyObject)
                XCTAssertFalse(host.canvas.layer.needsDisplay(), "Motion must reuse the cached measure")
                XCTAssertEqual(writes, 0)
            }
            pan.simulatedState = .ended
            host.canvas.handleRenderedObjectMovePan(pan)
            XCTAssertEqual(writes, 1)
            let saved = host.canvas.chart
            let moved = try XCTUnwrap(saved.measure(id: measureID))
            XCTAssertLessThan(try XCTUnwrap(moved.paperLayout).startFraction, 0.45)
            XCTAssertEqual(moved.paperLayout?.widthFraction ?? 0, 0.3, accuracy: 0.00001)
            XCTAssertEqual(moved.chordEvents, original.measures[0].chordEvents)
            XCTAssertEqual(saved.pageHandwrittenNotationData, original.pageHandwrittenNotationData)
            XCTAssertNil(overlay.superlayer)
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(saved))
            XCTAssertEqual(reopened, saved)
            try assertFreeInkFollowsMeasure(from: original, to: reopened)
        }
    }

    func testCancelledMeasureDragRestoresTheOriginalAndDoesNotWrite() throws {
        let original = try fixture(.simpleChordSheet)
        let host = mount(original)
        defer { host.close() }
        host.canvas.selectedMeasureID = original.measures[0].id
        let measure = try XCTUnwrap(layout(host.canvas).systems[0].measures.first)
        let start = CGPoint(x: measure.frame.midX, y: measure.frame.maxY - 10)
        var writes = 0
        host.canvas.onChartChanged = { _ in writes += 1 }
        XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
        let pan = PaperMeasurePan(point: start, movement: .zero, state: .began, view: host.canvas)
        host.canvas.handleRenderedObjectMovePan(pan)
        pan.point.x -= 50
        pan.simulatedState = .changed
        host.canvas.handleRenderedObjectMovePan(pan)
        pan.simulatedState = .cancelled
        host.canvas.handleRenderedObjectMovePan(pan)
        XCTAssertEqual(host.canvas.chart, original)
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(host.canvas.layer.sublayers?.contains { $0.name == "measureMove.snapshot" } ?? false)
    }

    func testMeasureBodyMoveRespectsChordAndResizeTargetsAndPencilPolicy() throws {
        let original = try fixture(.rhythmSectionSheet)
        let host = mount(original, environment: .device)
        defer { host.close() }
        host.canvas.selectedMeasureID = original.measures[0].id
        let page = layout(host.canvas)
        let measure = try XCTUnwrap(page.systems[0].measures.first)
        let selected = RenderedEditSelectionState(selectedObjectID: .measure(original.measures[0].id))
        let context = RenderedEditContext(pageLayout: page, layoutStyle: original.layoutStyle,
            selection: selected, allowsUnselectedChordMove: true, allowsSelectedMeasureMove: true)
        let chord = try XCTUnwrap(measure.chordLayouts.first)
        let chordPoint = CGPoint(x: chord.frame.midX, y: chord.frame.midY)
        XCTAssertEqual(RenderedEditRouter().dragTarget(at: chordPoint, in: context)?.objectID, .chord(chord.id))
        let grips = LeadSheetMeasureResizeGeometry.handleFrames(for: measure)
        let gripPoint = CGPoint(x: grips.right.midX, y: grips.right.midY)
        XCTAssertEqual(RenderedEditRouter().dragTarget(at: gripPoint, in: context)?.action, .resizeRight)
        let moveHandle = LeadSheetMeasureResizeGeometry.moveHandleFrame(for: measure)
        let start = CGPoint(x: moveHandle.midX, y: moveHandle.midY)
        XCTAssertFalse(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .direct))
        XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
    }

    func testPaperMeasureResizeKeepsAnIsolatedRightMeasureAtItsChosenEdge() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let original = try fixture(style)
            let host = mount(original)
            defer { host.close() }
            let measureID = original.measures[0].id
            host.canvas.selectedMeasureID = measureID
            let measure = try XCTUnwrap(layout(host.canvas).systems[0].measures.first)
            let handle = LeadSheetMeasureResizeGeometry.handleFrames(for: measure).right
            let start = CGPoint(x: handle.midX, y: handle.midY)
            let pan = PaperMeasurePan(point: start, movement: .zero, state: .began, view: host.canvas)
            let selector = NSSelectorFromString("handleMeasureResizePan:")
            host.canvas.perform(selector, with: pan)
            pan.point.x += 24
            pan.movement.x = 24
            pan.simulatedState = .changed
            host.canvas.perform(selector, with: pan)
            pan.simulatedState = .ended
            host.canvas.perform(selector, with: pan)
            let resized = try XCTUnwrap(host.canvas.chart.measure(id: measureID))
            XCTAssertEqual(resized.paperLayout?.startFraction, 0.45)
            XCTAssertGreaterThan(resized.paperLayout?.endFraction ?? 0, 0.75)
            XCTAssertEqual(resized.chordEvents, original.measures[0].chordEvents)
        }
    }

    func testLegacyMeasureCanBeGrabbedAndReorderedWithoutLosingItsContents() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var legacy = Chart.blank(title: "Existing measure move", measureCount: 4, layoutStyle: style)
            legacy.hasCompletedInitialSetup = true
            for row in legacy.systems.indices {
                for index in legacy.systems[row].measures.indices {
                    legacy.systems[row].measures[index].authoringState = .committed
                }
            }
            let originalIDs = Set(legacy.measures.map(\.id))
            let movedID = legacy.measures[3].id
            _ = legacy.appendRecognizedChordEvent(try ChordSymbolParser.parse("D7"),
                rawInput: "D7", to: movedID, atFraction: 0)
            let host = mount(legacy)
            defer { host.close() }
            host.canvas.selectedMeasureID = movedID
            let page = layout(host.canvas)
            let system = try XCTUnwrap(page.systems.first)
            let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == movedID })
            let handle = LeadSheetMeasureResizeGeometry.moveHandleFrame(for: measure)
            let start = CGPoint(x: handle.midX, y: handle.midY)
            let row = try XCTUnwrap(system.paperMeasurePositioningFrame(in: page.paperFrame(for: system)))
            XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
            let pan = PaperMeasurePan(point: start, movement: .zero, state: .began, view: host.canvas)
            host.canvas.handleRenderedObjectMovePan(pan)
            pan.point.x = start.x - measure.frame.minX + row.minX
            pan.simulatedState = .ended
            host.canvas.handleRenderedObjectMovePan(pan)
            XCTAssertTrue(host.canvas.chart.usesPaperMeasureLayout)
            XCTAssertEqual(Set(host.canvas.chart.measures.map(\.id)), originalIDs)
            XCTAssertEqual(host.canvas.chart.measures.first?.id, movedID)
            XCTAssertEqual(host.canvas.chart.measure(id: movedID)?.chordEvents,
                legacy.measure(id: movedID)?.chordEvents)
        }
    }

    func testInteriorReorderCommitsTheDropGuideWhileTheGrabbedMeasureFollowsThePencil() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var original = Chart.blank(title: "Interior measure move", measureCount: 4, layoutStyle: style)
            original.hasCompletedInitialSetup = true
            let ids = original.measures.map(\.id)
            for (index, id) in ids.enumerated() {
                _ = original.appendRecognizedChordEvent(try ChordSymbolParser.parse(["C7", "D7", "E7", "F7"][index]),
                    rawInput: ["C7", "D7", "E7", "F7"][index], to: id, atFraction: 0)
            }
            for row in original.systems.indices {
                for index in original.systems[row].measures.indices {
                    original.systems[row].measures[index].authoringState = .committed
                }
            }
            let spans = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
                (id, (Double(index) / 4)...(Double(index + 1) / 4))
            })
            XCTAssertTrue(original.adoptPaperMeasureLayout([spans]))
            let host = mount(original)
            defer { host.close() }
            let movedID = ids[3]
            host.canvas.selectedMeasureID = movedID
            let page = layout(host.canvas)
            let system = try XCTUnwrap(page.systems.first)
            let source = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == movedID })
            let row = try XCTUnwrap(system.paperWritingFrame)
            let handle = LeadSheetMeasureResizeGeometry.moveHandleFrame(for: source)
            let start = CGPoint(x: handle.midX, y: handle.midY)
            XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
            let pan = PaperMeasurePan(point: start, movement: .zero, state: .began, view: host.canvas)
            host.canvas.handleRenderedObjectMovePan(pan)
            let overlay = try XCTUnwrap(host.canvas.layer.sublayers?.first { $0.name == "measureMove.snapshot" })
            let initialOverlayX = overlay.frame.minX
            pan.point.x = start.x + row.minX + row.width * 0.22 - source.frame.minX
            pan.simulatedState = .changed
            host.canvas.handleRenderedObjectMovePan(pan)
            let previewX = source.frame.minX + overlay.frame.minX - initialOverlayX
            XCTAssertEqual(previewX, row.minX + row.width * 0.22, accuracy: 0.1)
            let dropGuide = try XCTUnwrap(host.canvas.layer.sublayers?.first { $0.name == "measureMove.dropGuide" })
            XCTAssertFalse(dropGuide.isHidden)
            let dropX = dropGuide.frame.minX
            var expected = original
            XCTAssertTrue(expected.movePaperMeasure(movedID, toStartFraction: 0.22))
            XCTAssertEqual(expected.measures.map(\.id), [ids[0], ids[3], ids[1], ids[2]])
            pan.simulatedState = .ended
            host.canvas.handleRenderedObjectMovePan(pan)
            XCTAssertEqual(host.canvas.chart.systems, expected.systems)
            let after = try XCTUnwrap(layout(host.canvas).systems.first?.measures.first { $0.sourceMeasureID == movedID })
            XCTAssertEqual(after.frame.minX, dropX, accuracy: 0.1)
            XCTAssertNil(dropGuide.superlayer)
            for id in ids {
                XCTAssertEqual(host.canvas.chart.measure(id: id)?.chordEvents, original.measure(id: id)?.chordEvents)
            }
        }
    }

    func testPackedMeasureFollowsNinetySixSmallPencilSamplesWithinOneDropSlot() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var original = Chart.blank(title: "Continuous packed measure drag", measureCount: 4, layoutStyle: style)
            original.hasCompletedInitialSetup = true
            let ids = original.measures.map(\.id)
            for (index, id) in ids.enumerated() {
                _ = original.appendRecognizedChordEvent(try ChordSymbolParser.parse(["C7", "D7", "E7", "F7"][index]),
                    rawInput: ["C7", "D7", "E7", "F7"][index], to: id, atFraction: 0)
            }
            for row in original.systems.indices {
                for index in original.systems[row].measures.indices {
                    original.systems[row].measures[index].authoringState = .committed
                }
            }
            let spans = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
                (id, (Double(index) / 4)...(Double(index + 1) / 4))
            })
            XCTAssertTrue(original.adoptPaperMeasureLayout([spans]))
            let host = mount(original)
            defer { host.close() }
            let movedID = ids[3]
            host.canvas.selectedMeasureID = movedID
            let page = layout(host.canvas)
            let system = try XCTUnwrap(page.systems.first)
            let source = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == movedID })
            let row = try XCTUnwrap(system.paperWritingFrame)
            let handle = LeadSheetMeasureResizeGeometry.moveHandleFrame(for: source)
            let start = CGPoint(x: handle.midX, y: handle.midY)
            XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
            let pan = PaperMeasurePan(point: start, movement: .zero, state: .began, view: host.canvas)
            var writes = 0
            host.canvas.onChartChanged = { _ in writes += 1 }
            host.canvas.handleRenderedObjectMovePan(pan)
            let image = try XCTUnwrap(host.canvas.layer.sublayers?.first { $0.name == "measureMove.snapshot" })
            let contents = try XCTUnwrap(image.contents)
            let initialImageX = image.frame.minX
            let dropGuide = try XCTUnwrap(host.canvas.layer.sublayers?.first { $0.name == "measureMove.dropGuide" })
            host.canvas.layer.displayIfNeeded()
            pan.simulatedState = .changed
            var lastImageX: CGFloat?
            var requestedFraction = 0.0
            for sample in 0..<96 {
                requestedFraction = 0.22 + Double(sample) * 0.00015
                let requestedX = row.minX + row.width * CGFloat(requestedFraction)
                pan.point.x = start.x + requestedX - source.frame.minX
                host.canvas.handleRenderedObjectMovePan(pan)
                XCTAssertEqual(image.frame.minX - initialImageX, requestedX - source.frame.minX, accuracy: 0.001,
                    "Every small Pencil movement must move the image even while the drop slot stays the same")
                if let lastImageX { XCTAssertGreaterThan(image.frame.minX, lastImageX) }
                lastImageX = image.frame.minX
                XCTAssertEqual(dropGuide.frame.minX, row.minX + row.width * 0.25, accuracy: 0.1)
                XCTAssertFalse(dropGuide.isHidden)
                XCTAssertTrue(image.contents as AnyObject === contents as AnyObject)
                XCTAssertFalse(host.canvas.layer.needsDisplay())
                XCTAssertEqual(writes, 0)
                XCTAssertEqual(host.canvas.chart, original)
            }
            let predictedDropX = dropGuide.frame.minX
            var expected = original
            XCTAssertTrue(expected.movePaperMeasure(movedID, toStartFraction: requestedFraction))
            pan.simulatedState = .ended
            host.canvas.handleRenderedObjectMovePan(pan)
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(host.canvas.chart.systems, expected.systems)
            let committed = try XCTUnwrap(layout(host.canvas).systems.first?.measures.first { $0.sourceMeasureID == movedID })
            XCTAssertEqual(committed.frame.minX, predictedDropX, accuracy: 0.1)
            XCTAssertNil(image.superlayer)
            XCTAssertNil(dropGuide.superlayer)
            for id in ids {
                XCTAssertEqual(host.canvas.chart.measure(id: id)?.chordEvents, original.measure(id: id)?.chordEvents)
            }
        }
    }

    func testConcurrentDeletionCancelsTheMeasureResizeLayerAndCannotResurrectItsOwner() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var original = Chart.blank(title: "Deleted resize owner", measureCount: 2, layoutStyle: style)
            original.hasCompletedInitialSetup = true
            let ids = original.measures.map(\.id)
            for row in original.systems.indices {
                for index in original.systems[row].measures.indices {
                    original.systems[row].measures[index].authoringState = .committed
                }
            }
            XCTAssertTrue(original.adoptPaperMeasureLayout([[
                ids[0]: 0...0.5, ids[1]: 0.5...1
            ]]))
            let host = mount(original)
            defer { host.close() }
            host.canvas.selectedMeasureID = ids[1]
            let measure = try XCTUnwrap(layout(host.canvas).systems.first?.measures.first { $0.sourceMeasureID == ids[1] })
            let handle = LeadSheetMeasureResizeGeometry.handleFrames(for: measure).right
            let start = CGPoint(x: handle.midX, y: handle.midY)
            let pan = PaperMeasurePan(point: start, movement: .zero, state: .began, view: host.canvas)
            let selector = NSSelectorFromString("handleMeasureResizePan:")
            host.canvas.perform(selector, with: pan)
            let preview = try XCTUnwrap(host.canvas.layer.sublayers?.first { $0.name == "measureResize.preview" })
            var writes = 0
            host.canvas.onChartChanged = { _ in writes += 1 }
            pan.simulatedState = .changed
            pan.point.x -= 20
            pan.movement.x = -20
            host.canvas.perform(selector, with: pan)
            var removed = original
            XCTAssertTrue(removed.deleteMeasure(id: ids[1]))
            XCTAssertNil(removed.measure(id: ids[1]))
            host.canvas.chart = removed
            XCTAssertNil(preview.superlayer)
            pan.simulatedState = .ended
            host.canvas.perform(selector, with: pan)
            XCTAssertEqual(host.canvas.chart, removed)
            XCTAssertEqual(writes, 0, "A canceled resize must never restore its deleted owner")
        }
    }

    func testChordResizeKeepsTheActiveGripWithThePencilAndClearsItOnCancel() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let original = try fixture(style)
            let host = mount(original)
            defer { host.close() }
            let chordID = try XCTUnwrap(original.measures.first?.chordEvents.first?.id)
            host.canvas.selectedChordID = chordID
            let page = layout(host.canvas)
            let glyph = try XCTUnwrap(page.systems.flatMap(\.measures).flatMap(\.chordLayouts)
                .first { $0.id == chordID })
            let context = RenderedEditContext(pageLayout: page, layoutStyle: style,
                selection: RenderedEditSelectionState(selectedObjectID: .chord(chordID)),
                allowsUnselectedChordMove: true, allowsSelectedMeasureMove: true)
            let target = try XCTUnwrap(ChordRenderedEditHitTargetProvider().hitTargets(in: context)
                .first { $0.objectID == .chord(chordID) && $0.action == .resizeTrailing })
            let start = CGPoint(x: target.frame.midX, y: target.frame.midY)
            XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil))
            let pan = PaperMeasurePan(point: start, movement: .zero, state: .began, view: host.canvas)
            host.canvas.handleRenderedObjectMovePan(pan)
            let grip = try XCTUnwrap(host.canvas.layer.sublayers?.first { $0.name == "chordResize.activeGrip" })
            XCTAssertNotNil(grip.contents)
            let initialGripX = grip.frame.midX
            host.canvas.layer.displayIfNeeded()
            pan.simulatedState = .changed
            // This fixture is already at maximum horizontal scale. Resize
            // inward so the policy permits a real width change rather than
            // correctly clamping an outward drag at the existing width.
            let movement = min(12, glyph.frame.width * 0.15)
            pan.point.x -= movement
            pan.movement.x = -movement
            host.canvas.handleRenderedObjectMovePan(pan)
            XCTAssertLessThan(grip.frame.midX, initialGripX)
            XCTAssertEqual(grip.frame.midX, initialGripX - movement, accuracy: 0.001)
            XCTAssertFalse(host.canvas.layer.needsDisplay())
            pan.simulatedState = .cancelled
            host.canvas.handleRenderedObjectMovePan(pan)
            XCTAssertNil(grip.superlayer)
            XCTAssertEqual(host.canvas.chart, original)
        }
    }

    private func fixture(_ style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Paper measure gesture", measureCount: 1, layoutStyle: style)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 1))
        chart.hasCompletedInitialSetup = true
        chart.systems[0].measures[0].authoringState = .committed
        chart.systems[0].measures[0].paperLayout = PaperMeasureLayout(rowIndex: 0,
            startFraction: 0.45, endFraction: 0.75, leadingBarline: .double)
        chart.systems[0].measures[0].barlineAfter = .double
        chart.systems[0].measures[0].chordEvents = [ChordEvent(id: UUID(),
            symbol: try ChordSymbolParser.parse("Eb/G"), spellingIntent: .explicit,
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .slash, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
            rawInput: "Eb/G", sourceInkData: stroke(from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 20, y: 20)).dataRepresentation())]
        let space = try coordinateSpace(chart)
        let chordFrame = try XCTUnwrap(space.chordAnchors?.first).frame.rect
        let y = chordFrame.maxY + 8
        let drawing = stroke(from: CGPoint(x: chordFrame.midX - 5, y: y),
            to: CGPoint(x: chordFrame.midX + 5, y: y + 3))
        chart.pageHandwrittenNotationData = drawing.dataRepresentation()
        chart.pageHandwrittenNotationCoordinateSpace = space
        return chart
    }

    private func assertFreeInkFollowsMeasure(from source: Chart, to target: Chart) throws {
        let before = try coordinateSpace(source)
        let after = try coordinateSpace(target)
        let sourceChord = try XCTUnwrap(before.chordAnchors?.first).frame.rect
        let targetChord = try XCTUnwrap(after.chordAnchors?.first).frame.rect
        let original = try PKDrawing(data: XCTUnwrap(source.pageHandwrittenNotationData))
        let projected = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            from: target.pageHandwrittenNotationData,
            sourceCoordinateSpace: target.pageHandwrittenNotationCoordinateSpace,
            targetCoordinateSpace: after))
        XCTAssertEqual(projected.strokes.count, original.strokes.count)
        XCTAssertEqual(projected.bounds.minX - original.bounds.minX,
            targetChord.minX - sourceChord.minX, accuracy: 0.15)
    }

    private func coordinateSpace(_ chart: Chart) throws -> PersistentInkCoordinateSpace {
        let page = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_400))
        return try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: page, relativeTo: LeadSheetActiveInkScope.pageWritingFrame(for: page)))
    }

    private func stroke(from first: CGPoint, to last: CGPoint) -> PKDrawing {
        let path = PKStrokePath(controlPoints: [first, last].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: .now)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor), path: path,
            transform: .identity, mask: nil, randomSeed: 21)])
    }

    private struct Host {
        let canvas: LeadSheetCanvasUIKitView
        let window: UIWindow
        let previous: UIWindow?
        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
    }

    private func mount(_ chart: Chart, environment: LeadSheetLiveInkInputPolicy.RuntimeEnvironment = .simulator) -> Host {
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 900, height: 1_400),
            chordInkRecognizer: ChordInkMaximumTrustRecognizer(), inputEnvironment: environment)
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
        canvas.layoutIfNeeded()
        return Host(canvas: canvas, window: window, previous: previous)
    }

    private func layout(_ canvas: LeadSheetCanvasUIKitView) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: canvas.chart, pageSize: canvas.bounds.size)
    }
}

@MainActor
private final class PaperMeasurePan: UIPanGestureRecognizer {
    var point: CGPoint
    var movement: CGPoint
    var simulatedState: UIGestureRecognizer.State
    let coordinateView: UIView
    init(point: CGPoint, movement: CGPoint, state: UIGestureRecognizer.State, view: UIView) {
        self.point = point
        self.movement = movement
        simulatedState = state
        coordinateView = view
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
    override func translation(in view: UIView?) -> CGPoint { movement }
}
#endif

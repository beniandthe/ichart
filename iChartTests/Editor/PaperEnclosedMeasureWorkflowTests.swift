#if canImport(UIKit) && canImport(PencilKit) && canImport(PDFKit)
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Replays the Build 201 row whose two internal boundaries enclosed an
/// interval that looked like a bar but had no model identity or tap target.
@MainActor
final class PaperEnclosedMeasureWorkflowTests: XCTestCase {
    func testSimpleSavedInternalGapBecomesASelectableMeasure() async throws {
        try await assertSelectableRepair(style: .simpleChordSheet)
    }

    func testRhythmSavedInternalGapBecomesASelectableMeasure() async throws {
        try await assertSelectableRepair(style: .rhythmSectionSheet)
    }

    func testSimpleRepairedMeasureCanBeResizedMovedAndReopened() throws {
        try assertEditableRepair(style: .simpleChordSheet)
    }

    func testRhythmRepairedMeasureCanBeResizedMovedAndReopened() throws {
        try assertEditableRepair(style: .rhythmSectionSheet)
    }

    func testDecodeRepairRetainsCanonicalInkArchivesAndExistingAnchors() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var source = try fixture(style)
            let thirdID = source.systems[0].measures[2].id
            let rightID = source.systems[1].measures[0].id
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: source,
                pageSize: CGSize(width: 900, height: 1400))
            let space = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                for: layout, relativeTo: LeadSheetActiveInkScope.pageWritingFrame(for: layout)))
            let owners = try [thirdID, rightID].map { measureID in
                try XCTUnwrap(space.chordAnchors?.first { $0.measureID == measureID })
            }
            let strokes = owners.enumerated().map { index, owner in
                let origin = CGPoint(x: owner.frame.rect.midX, y: owner.frame.rect.maxY + 10)
                let points = [origin, CGPoint(x: origin.x + 12, y: origin.y + 4)]
                let path = PKStrokePath(controlPoints: points.enumerated().map { offset, point in
                    PKStrokePoint(location: point, timeOffset: Double(offset) * 0.1,
                        size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }, creationDate: Date(timeIntervalSinceReferenceDate: Double(index + 1)))
                return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                    path: path, transform: .identity, mask: nil, randomSeed: UInt32(index + 1))
            }
            source.setPageHandwrittenNotationDrawing(PKDrawing(strokes: strokes).dataRepresentation(),
                coordinateSpace: space)
            let canonicalArchive = try XCTUnwrap(source.pageHandwrittenNotationData)
            source.systems[0].measures[2].chordEvents[0].sourceInkData = canonicalArchive
            source.systems[1].measures[0].chordEvents[0].sourceInkData = canonicalArchive
            XCTAssertNotNil(source.addCueText("Keep with the last written bar", anchorMeasureID: thirdID))
            source.freeInkArticulations = [FreeInkArticulation(kind: .accent, measureID: rightID,
                sourceInkData: canonicalArchive, sourceCoordinateSpace: space,
                attachment: .chord(id: source.systems[1].measures[0].chordEvents[0].id))]
            XCTAssertEqual(source.systems[0].measures.count, 3)

            let repaired = try reopen(source)
            let blankID = try assertRepair(repaired, original: source)
            let decodedAgain = try reopen(source)
            let reopened = try reopen(repaired)
            XCTAssertEqual(try assertRepair(decodedAgain, original: source), blankID)
            XCTAssertEqual(try assertRepair(reopened, original: source), blankID)
            XCTAssertEqual(reopened, repaired)
            for chart in [repaired, decodedAgain, reopened] {
                XCTAssertEqual(chart.pageHandwrittenNotationData, canonicalArchive)
                XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, space)
                XCTAssertEqual(chart.cueTexts, source.cueTexts)
                XCTAssertEqual(chart.freeInkArticulations, source.freeInkArticulations)
                XCTAssertEqual(chart.roadmapObjects, source.roadmapObjects)
                for measureID in [thirdID, rightID] {
                    XCTAssertEqual(chart.measure(id: measureID)?.chordEvents,
                        source.measure(id: measureID)?.chordEvents)
                    XCTAssertEqual(chart.measure(id: measureID)?.cueTextIDs,
                        source.measure(id: measureID)?.cueTextIDs)
                }
                XCTAssertEqual(try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenNotationData)).strokes.count, 2)
            }
        }
    }

    private func assertSelectableRepair(style: ChartLayoutStyle) async throws {
        let source = try fixture(style)
        XCTAssertEqual(source.systems[0].measures.count, 3)
        let repaired = try reopen(source)
        let blankID = try assertRepair(repaired, original: source)
        let host = mount(repaired)
        defer { host.close() }
        let page = pageLayout(host.canvas)
        let row = try XCTUnwrap(page.systems.first)
        XCTAssertEqual(row.measures.compactMap(\.sourceMeasureID).count, 4)
        let blank = try XCTUnwrap(row.measures.first { $0.sourceMeasureID == blankID })
        XCTAssertFalse(blank.isOpen)
        XCTAssertFalse(blank.isPaperWritingPlaceholder)
        let point = CGPoint(x: blank.staffFrame.midX, y: blank.frame.maxY - 12)
        let target = RenderedEditRouter().tapTarget(at: point,
            in: RenderedEditContext(pageLayout: page, layoutStyle: style))
        XCTAssertEqual(target?.objectID, .measure(blankID))

        var selected: UUID?
        host.canvas.onMeasureSelectedFromCanvas = { selected = $0 }
        host.canvas.handleRenderedEditTapGesture(EnclosedMeasureTap(point: point, view: host.canvas))
        XCTAssertEqual(selected, blankID, "A tap in the former gap must deliver the new real measure ID")
        XCTAssertEqual(host.canvas.selectedMeasureID, blankID)
        attach(canvasImage(host.canvas), name: "\(style.rawValue) repaired internal measure selected")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        let library = ChartLibraryStore(charts: [repaired], selectedChartID: repaired.id, repository: repository)
        try repository.saveSnapshot(library.snapshot)
        let saved = try XCTUnwrap(repository.loadSnapshot()?.charts.first)
        XCTAssertEqual(saved, repaired)
        XCTAssertEqual(try assertRepair(saved, original: source), blankID,
            "Saving and reopening must keep one stable identity for the repaired interval")

        let exported = try await PDFChartExporter(exportDirectory: directory.appendingPathComponent("Exports"))
            .exportPDF(for: saved)
        let pdf = try XCTUnwrap(PDFDocument(url: exported.url))
        XCTAssertGreaterThan(pdf.pageCount, 0)
        let text = try XCTUnwrap(pdf.string)
        for chord in ["C7", "D7", "E7", "G7"] {
            XCTAssertPDFExtractedTextContains(text, visibleChordText: chord)
        }
    }

    private func assertEditableRepair(style: ChartLayoutStyle) throws {
        let source = try fixture(style)
        let repaired = try reopen(source)
        let blankID = try assertRepair(repaired, original: source)
        let host = mount(repaired)
        defer { host.close() }
        host.canvas.selectedMeasureID = blankID
        let blank = try XCTUnwrap(pageLayout(host.canvas).systems.first?.measures.first {
            $0.sourceMeasureID == blankID
        })
        let rightHandle = LeadSheetMeasureResizeGeometry.handleFrames(for: blank).right
        let start = CGPoint(x: rightHandle.midX, y: rightHandle.midY)
        let resize = EnclosedMeasurePan(point: start, state: .began, view: host.canvas)
        let resizeSelector = NSSelectorFromString("handleMeasureResizePan:")
        host.canvas.perform(resizeSelector, with: resize)
        resize.point.x += 24
        resize.movement.x = 24
        resize.simulatedState = .changed
        host.canvas.perform(resizeSelector, with: resize)
        resize.simulatedState = .ended
        host.canvas.perform(resizeSelector, with: resize)
        let resized = try XCTUnwrap(host.canvas.chart.measure(id: blankID)?.paperLayout)
        let originalWidth = try XCTUnwrap(repaired.measure(id: blankID)?.paperLayout).widthFraction
        XCTAssertGreaterThan(resized.widthFraction, originalWidth,
            "The formerly untargetable interval must accept the ordinary resize handle")
        XCTAssertEqual(host.canvas.chart.systems[0].measures.count, 4)

        let newPage = pageLayout(host.canvas)
        let movedMeasure = try XCTUnwrap(newPage.systems.first?.measures.first { $0.sourceMeasureID == blankID })
        let moveHandle = LeadSheetMeasureResizeGeometry.moveHandleFrame(for: movedMeasure)
        let moveStart = CGPoint(x: moveHandle.midX, y: moveHandle.midY)
        XCTAssertTrue(host.canvas.beginRenderedObjectMoveTouch(at: moveStart, touchType: .pencil))
        let move = EnclosedMeasurePan(point: moveStart, state: .began, view: host.canvas)
        host.canvas.handleRenderedObjectMovePan(move)
        let axis = try XCTUnwrap(newPage.systems.first?.paperWritingFrame)
        move.point.x -= movedMeasure.staffFrame.minX - axis.minX
        move.simulatedState = .changed
        host.canvas.handleRenderedObjectMovePan(move)
        move.simulatedState = .ended
        host.canvas.handleRenderedObjectMovePan(move)

        let edited = host.canvas.chart
        XCTAssertEqual(edited.systems[0].measures.first?.id, blankID)
        XCTAssertEqual(edited.systems[0].measures.count, 4)
        XCTAssertTrue(try XCTUnwrap(edited.measure(id: blankID)).chordEvents.isEmpty)
        try assertExistingOwners(edited, original: source)
        let reopened = try reopen(edited)
        XCTAssertEqual(reopened, edited)
        XCTAssertEqual(reopened.systems[0].measures.first?.id, blankID)
        try assertExistingOwners(reopened, original: source)
        attach(canvasImage(host.canvas), name: "\(style.rawValue) repaired internal measure resized and moved")
    }

    @discardableResult
    private func assertRepair(_ chart: Chart, original: Chart) throws -> UUID {
        let originalIDs = Set(original.measures.map(\.id))
        XCTAssertEqual(chart.systems.count, 2)
        XCTAssertEqual(chart.systems.map { $0.measures.count }, [4, 1])
        let inserted = chart.systems[0].measures.filter { !originalIDs.contains($0.id) }
        let blank = try XCTUnwrap(inserted.first)
        XCTAssertEqual(inserted.count, 1)
        XCTAssertTrue(blank.chordEvents.isEmpty)
        XCTAssertEqual(blank.authoringState, .committed)
        let placement = try XCTUnwrap(blank.paperLayout)
        XCTAssertEqual(placement.startFraction, 0.6510545522018801, accuracy: 0.0000001)
        XCTAssertEqual(placement.endFraction, 0.843804119247897, accuracy: 0.0000001)
        XCTAssertEqual(placement.leadingBarline, .single)
        XCTAssertEqual(blank.barlineAfter, .single)
        XCTAssertFalse(placement.needsSystemFit)
        XCTAssertEqual(chart.paperMeasureTarget(inRow: 0, at: 0.75)?.measureID, blank.id)
        XCTAssertEqual(chart.measures.map(\.index), [1, 2, 3, 4, 5])
        try assertExistingOwners(chart, original: original)
        return blank.id
    }

    private func assertExistingOwners(_ chart: Chart, original: Chart) throws {
        XCTAssertEqual(chart.roadmapObjects, original.roadmapObjects,
            "Repeats and endings retain the original measure IDs and saved range values")
        for source in original.measures {
            let existing = try XCTUnwrap(chart.measure(id: source.id))
            XCTAssertEqual(existing.chordEvents, source.chordEvents)
            XCTAssertEqual(existing.roadmapObjectIDs, source.roadmapObjectIDs)
        }
        let originalRight = try XCTUnwrap(original.systems[1].measures.first)
        let right = try XCTUnwrap(chart.measure(id: originalRight.id))
        XCTAssertEqual(right.paperLayout, originalRight.paperLayout,
            "A lone right-edge measure keeps its empty left margin")
        XCTAssertEqual(chart.systems[1].measures.map(\.id), [originalRight.id])
    }

    private func fixture(_ style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Disposable enclosed measure", layoutStyle: style)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 2))
        let template = chart.systems[0].measures[0]
        let spans: [(Double, Double, BarlineType, BarlineType)] = [
            (0, 0.32552727610094007, .double, .double),
            (0.32552727610094007, 0.6510545522018801, .double, .single),
            (0.843804119247897, 1, .single, .single)
        ]
        chart.systems[0].measures = try spans.enumerated().map { index, span in
            var measure = template
            measure.id = UUID()
            measure.index = index + 1
            measure.authoringState = .committed
            measure.paperLayout = PaperMeasureLayout(rowIndex: 0, startFraction: span.0,
                endFraction: span.1, leadingBarline: span.2)
            measure.barlineAfter = span.3
            measure.chordEvents = [try chord(["C7", "D7", "E7"][index])]
            return measure
        }
        var right = chart.systems[1].measures[0]
        right.index = 4
        right.authoringState = .committed
        right.paperLayout = PaperMeasureLayout(rowIndex: 1, startFraction: 0.7480529221728673,
            endFraction: 1, leadingBarline: .single)
        right.barlineAfter = .single
        right.chordEvents = [try chord("G7")]
        chart.systems[1].measures = [right]
        let ids = chart.systems[0].measures.map(\.id)
        XCTAssertNotNil(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[2]))
        XCTAssertNotNil(chart.addEndingSpan(.ending1, startMeasureID: ids[2], endMeasureID: ids[2]))
        return chart
    }

    private func chord(_ text: String) throws -> ChordEvent {
        ChordEvent(id: UUID(), symbol: try ChordSymbolParser.parse(text), spellingIntent: .explicit,
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .whole, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none, rawInput: text)
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
    }

    private func mount(_ chart: Chart) -> Host {
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 900, height: 1400),
            chordInkRecognizer: ChordInkMaximumTrustRecognizer(), inputEnvironment: .simulator)
        canvas.recognizesChordInk = false
        canvas.chart = chart
        canvas.interactionMode = .browse
        canvas.overrideUserInterfaceStyle = .light
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

    private func pageLayout(_ canvas: LeadSheetCanvasUIKitView) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: canvas.chart, pageSize: canvas.bounds.size)
    }

    private func canvasImage(_ canvas: LeadSheetCanvasUIKitView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(canvas.bounds)
            canvas.draw(canvas.bounds)
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
}

@MainActor
private final class EnclosedMeasureTap: UITapGestureRecognizer {
    let point: CGPoint
    let coordinateView: UIView
    init(point: CGPoint, view: UIView) {
        self.point = point
        coordinateView = view
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State { get { .ended } set {} }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}

@MainActor
private final class EnclosedMeasurePan: UIPanGestureRecognizer {
    var point: CGPoint
    var movement = CGPoint.zero
    var simulatedState: UIGestureRecognizer.State
    let coordinateView: UIView
    init(point: CGPoint, state: UIGestureRecognizer.State, view: UIView) {
        self.point = point
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

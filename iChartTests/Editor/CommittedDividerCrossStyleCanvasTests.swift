#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class CommittedDividerCrossStyleCanvasTests: XCTestCase {
    func testBrowseTapSelectsBeforeDeleteAndMergesOnceWithoutLosingChordSources() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let original = try chart(style)
            let host = mount(original)
            defer { host.close() }
            let leftID = original.measures[0].id
            let removedID = original.measures[1].id
            let laterID = original.measures[2].id
            XCTAssertTrue(original.canDeleteCommittedChordBarline(after: leftID))
            let page = layout(host.canvas)
            let left = try XCTUnwrap(page.systems.flatMap(\.measures).first { $0.sourceMeasureID == leftID })
            let line = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: left, layoutStyle: style)
            let point = CGPoint(x: line.midX, y: line.midY)
            var published = [Chart]()
            host.canvas.onChartChanged = { published.append($0) }

            let initialContext = context(chart: original, page: page)
            let initialTarget = try XCTUnwrap(RenderedEditRouter(
                providers: [CommittedChordBarlineRenderedEditHitTargetProvider()]
            ).tapTarget(at: point, in: initialContext))
            XCTAssertEqual(initialTarget.objectID, .committedChordBarline(afterMeasureID: leftID))
            XCTAssertEqual(initialTarget.action, .select)
            XCTAssertEqual(initialTarget.mutationRisk, .nonMutating)
            try assertInstalledTapRouting(at: point, in: host.canvas)

            try tap(point, in: host.canvas)

            XCTAssertEqual(host.canvas.selectedCommittedBarlineMeasureID, leftID)
            XCTAssertEqual(host.canvas.chart, original, "Selecting a line must not alter the chart")
            XCTAssertTrue(published.isEmpty)
            try tap(point, in: host.canvas)
            XCTAssertEqual(host.canvas.chart, original, "A second line-body tap must still not delete")
            XCTAssertTrue(published.isEmpty)

            let delete = LeadSheetCommittedChordBarlineOverlayGeometry.controlFrames(
                for: left, layoutStyle: style).delete
            let deletePoint = CGPoint(x: delete.midX, y: delete.midY)
            let selectedContext = context(chart: original, page: page,
                selected: .committedChordBarline(afterMeasureID: leftID))
            let destructiveTarget = try XCTUnwrap(RenderedEditRouter(
                providers: [CommittedChordBarlineRenderedEditHitTargetProvider()]
            ).tapTarget(at: deletePoint, in: selectedContext))
            XCTAssertEqual(destructiveTarget.action, .delete)
            XCTAssertEqual(destructiveTarget.mutationRisk, .structural)
            try assertInstalledTapRouting(at: deletePoint, in: host.canvas)
            attach(host.canvas, name: "\(style.rawValue) selected divider and red X")

            try tap(deletePoint, in: host.canvas)

            XCTAssertEqual(published.count, 1)
            XCTAssertNil(host.canvas.selectedCommittedBarlineMeasureID)
            let changed = host.canvas.chart
            XCTAssertEqual(changed.measures.map(\.id), [leftID, laterID])
            XCTAssertNil(changed.measure(id: removedID))
            XCTAssertEqual(changed.measures[0].chordEvents.map(\.id),
                original.measures.prefix(2).flatMap(\.chordEvents).map(\.id))
            let later = try XCTUnwrap(changed.measure(id: laterID))
            var expectedLater = original.measures[2]
            expectedLater.index = later.index
            XCTAssertEqual(later, expectedLater, "Only the unrelated measure's ordinal may change")
            XCTAssertEqual(changed.pageHandwrittenHeaderData, original.pageHandwrittenHeaderData)
            for event in original.measures.flatMap(\.chordEvents) {
                let actual = try XCTUnwrap(changed.chordEvent(id: event.id))
                assertReceipt(actual, matches: event)
            }
            XCTAssertEqual(try reopen(changed), changed)
            attach(host.canvas, name: "\(style.rawValue) divider deleted once")
        }
    }

    func testProtectedRhythmBoundaryExposesNoDeleteTargetAndTapDoesNotChangeNotation() throws {
        var original = try chart(.rhythmSectionSheet)
        let leftID = original.measures[0].id
        original.systems[0].measures[0].rhythmMap = MeasureRhythmMap(values: [.quarter, .quarter, .half])
        original.systems[0].measures[0].pitchedNoteEvents = [
            LeadSheetPitchedNoteEvent(rhythmSlotIndex: 0,
                staffPosition: LeadSheetStaffPosition(staffStep: 2), sourceInkData: archive(seed: 15))
        ]
        XCTAssertFalse(original.canDeleteCommittedChordBarline(after: leftID))
        let host = mount(original)
        defer { host.close() }
        let page = layout(host.canvas)
        let left = try XCTUnwrap(page.systems.flatMap(\.measures).first { $0.sourceMeasureID == leftID })
        let line = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: left, layoutStyle: .rhythmSectionSheet)
        let provider = CommittedChordBarlineRenderedEditHitTargetProvider()
        let targets = provider.hitTargets(in: context(chart: original, page: page))
        XCTAssertFalse(targets.contains { $0.objectID == .committedChordBarline(afterMeasureID: leftID) })
        var publications = 0
        host.canvas.onChartChanged = { _ in publications += 1 }

        try tap(CGPoint(x: line.midX, y: line.midY), in: host.canvas)

        XCTAssertNil(host.canvas.selectedCommittedBarlineMeasureID)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(host.canvas.chart, original)
        XCTAssertEqual(try reopen(host.canvas.chart), original)
    }

    func testRhythmDividerSelectsThePrintedStaffLineRatherThanAPhantomChordBandLine() throws {
        let original = try chart(.rhythmSectionSheet)
        let leftID = original.measures[0].id
        let host = mount(original)
        defer { host.close() }
        let page = layout(host.canvas)
        let left = try XCTUnwrap(page.systems.flatMap(\.measures).first { $0.sourceMeasureID == leftID })
        let printed = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: left, layoutStyle: .rhythmSectionSheet)
        XCTAssertEqual(printed.minY, left.staffFrame.minY)
        XCTAssertEqual(printed.height, left.staffFrame.height)
        let phantom = CGPoint(x: printed.midX, y: left.chordBandFrame.midY)
        XCTAssertFalse(printed.contains(phantom), "The fixture must address the separate chord band")
        let router = RenderedEditRouter(providers: [CommittedChordBarlineRenderedEditHitTargetProvider()])
        XCTAssertNil(router.tapTarget(at: phantom, in: context(chart: original, page: page)))

        try tap(phantom, in: host.canvas)

        XCTAssertNil(host.canvas.selectedCommittedBarlineMeasureID)
        XCTAssertEqual(host.canvas.chart, original)
        try tap(CGPoint(x: printed.midX, y: printed.midY), in: host.canvas)
        XCTAssertEqual(host.canvas.selectedCommittedBarlineMeasureID, leftID)
        XCTAssertEqual(host.canvas.chart, original)
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
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(frame: canvas.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        return Host(canvas: canvas, window: window, previousWindow: previousWindow)
    }

    private func layout(_ canvas: LeadSheetCanvasUIKitView) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: canvas.chart, pageSize: canvas.bounds.size)
    }

    private func context(chart: Chart, page: LeadSheetPageLayout,
        selected: RenderedEditObjectID? = nil) -> RenderedEditContext {
        RenderedEditContext(pageLayout: page, layoutStyle: chart.layoutStyle,
            selection: RenderedEditSelectionState(selectedObjectID: selected),
            committedChordBarlineMeasures: page.systems.flatMap(\.measures).filter {
                $0.sourceMeasureID.map { chart.canDeleteCommittedChordBarline(after: $0) } == true
            })
    }

    private func assertInstalledTapRouting(at point: CGPoint, in canvas: LeadSheetCanvasUIKitView) throws {
        let overlay = try XCTUnwrap(canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
        let local = overlay.convert(point, from: canvas)
        XCTAssertTrue(overlay.point(inside: local, with: nil))
        XCTAssertTrue(overlay.hitTest(local, with: nil) === overlay)
        let recognizer = try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 1 })
        XCTAssertTrue(recognizer.isEnabled)
        XCTAssertTrue(recognizer.delegate === canvas)
        for type in [UITouch.TouchType.direct, .pencil] {
            let touch = DividerTouchFixture(type: type, point: point, coordinateView: canvas)
            XCTAssertTrue(try XCTUnwrap(recognizer.delegate?.gestureRecognizer?(recognizer, shouldReceive: touch)))
        }
    }

    private func tap(_ point: CGPoint, in canvas: LeadSheetCanvasUIKitView) throws {
        let selector = NSSelectorFromString("handleRenderedEditTapGesture:")
        XCTAssertTrue(canvas.responds(to: selector))
        _ = canvas.perform(selector, with: DividerTapFixture(point: point, coordinateView: canvas))
    }

    private func chart(_ style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Divider canvas integration", measureCount: 3, layoutStyle: style)
        for (index, text) in ["Cmaj7", "G7", "Dm7"].enumerated() {
            chart.systems[0].measures[index].authoringState = .committed
            chart.systems[0].measures[index].manualLayoutWidth = 190
            chart.systems[0].measures[index].chordEvents = [ChordEvent(id: UUID(),
                symbol: try ChordSymbolParser.parse(text), spellingIntent: .explicit,
                startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
                duration: .half, rhythmPlacement: .hidden, tieOut: true, hitStyle: .accent,
                rawInput: text, sourceInkData: archive(seed: index + 1),
                sourceCandidateSignature: [text], sourceRecognitionPipelineVersion: "divider-test",
                manualDisplayWidth: 46, manualLaneFraction: 0.15, manualVisualLaneFraction: 0.15)]
        }
        chart.pageHandwrittenHeaderData = archive(seed: 10)
        return chart
    }

    private func assertReceipt(_ actual: ChordEvent, matches original: ChordEvent,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, original.id, file: file, line: line)
        XCTAssertEqual(actual.symbol, original.symbol, file: file, line: line)
        XCTAssertEqual(actual.spellingIntent, original.spellingIntent, file: file, line: line)
        XCTAssertEqual(actual.spellingOverrideSource, original.spellingOverrideSource, file: file, line: line)
        XCTAssertEqual(actual.rawInput, original.rawInput, file: file, line: line)
        XCTAssertEqual(actual.sourceInkData, original.sourceInkData, file: file, line: line)
        XCTAssertEqual(actual.sourceCandidateSignature, original.sourceCandidateSignature, file: file, line: line)
        XCTAssertEqual(actual.sourceRecognitionPipelineVersion, original.sourceRecognitionPipelineVersion, file: file, line: line)
        XCTAssertEqual(actual.duration, original.duration, file: file, line: line)
        XCTAssertEqual(actual.tieOut, original.tieOut, file: file, line: line)
        XCTAssertEqual(actual.hitStyle, original.hitStyle, file: file, line: line)
        XCTAssertEqual(actual.manualDisplayWidth, original.manualDisplayWidth, file: file, line: line)
    }

    private func archive(seed: Int) -> Data {
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 35, y: 36), CGPoint(x: 48, y: 22)]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed)))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor), path: path,
            transform: .identity, mask: nil, randomSeed: UInt32(seed))]).dataRepresentation()
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        try repository.saveSnapshot(.init(charts: [chart], selectedChartID: chart.id, entitlements: .free))
        return try XCTUnwrap(try repository.loadSnapshot()?.charts.first)
    }

    private func attach(_ canvas: LeadSheetCanvasUIKitView, name: String) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(canvas.bounds)
            canvas.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class DividerTapFixture: UITapGestureRecognizer {
    let point: CGPoint
    let coordinateView: UIView
    init(point: CGPoint, coordinateView: UIView) {
        self.point = point
        self.coordinateView = coordinateView
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State { get { .ended } set { } }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}

@MainActor
private final class DividerTouchFixture: UITouch {
    let simulatedType: UITouch.TouchType
    let point: CGPoint
    let coordinateView: UIView
    init(type: UITouch.TouchType, point: CGPoint, coordinateView: UIView) {
        simulatedType = type
        self.point = point
        self.coordinateView = coordinateView
        super.init()
    }
    override var type: UITouch.TouchType { simulatedType }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}
#endif

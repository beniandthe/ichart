#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Source ownership and glyph placement are separate requirements. These
/// cases keep both chords in the same measure, where beat-guide snapping can
/// otherwise move a completed chord onto the next chord's unfinished ink.
@MainActor
final class ChordInkAutomaticPlacementTests: XCTestCase {
    // The captured build-95 layout trace records this page size. Its separate
    // 784 x 700 persisted coordinate space belongs to the chord canvas region.
    private let pageSize = CGSize(width: 932, height: 1_200)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)

    func testAutomaticPartialRenderKeepsSourceLeftEdgeWithoutChangingMusicalTimingOrManualLayout() throws {
        let chart = try chartWithF()
        let g = PKDrawing(strokes: [gStroke()])
        let a = PKDrawing(strokes: [aFirstStroke()])
        let source = PKDrawing(strokes: g.strokes + a.strokes)
        let state = try makeState(chart, drawings: [g, a], texts: ["G", nil])
        let automatic = try XCTUnwrap(prepare(chart, state: state, drawing: source))
        let autoG = try XCTUnwrap(automatic.chart.measures.flatMap(\.chordEvents).first { $0.rawInput == "G" })
        let autoLayout = layout(automatic.chart)
        let autoGlyph = try chordLayout(autoG.id, in: autoLayout)
        let sourceLayout = layout(chart)
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        let originalF = try XCTUnwrap(chart.measures.flatMap(\.chordEvents).first)
        let originalFGlyph = try chordLayout(originalF.id, in: sourceLayout)
        let afterFGlyph = try chordLayout(originalF.id, in: autoLayout)

        XCTAssertEqual(autoGlyph.naturalFrame.minX, g.bounds.minX + sourceFrame.minX, accuracy: 2)
        XCTAssertNotNil(autoG.manualVisualLaneFraction)
        XCTAssertEqual(afterFGlyph.naturalFrame, originalFGlyph.naturalFrame,
            "Incremental G placement must not shift an existing F")
        XCTAssertEqual(automatic.result.renderedChordCount, 1)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: a, current: automatic.drawing))
        assertGlyphsAvoidRetainedInk(chart: automatic.chart, drawing: automatic.drawing, sourceFrame: sourceFrame)

        let manualState = try makeState(chart, drawings: [g], texts: ["G"])
        let manual = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: manualState,
            currentDrawing: g, coordinateSpace: PersistentInkCoordinateSpace(size: sourceFrame.size))
        XCTAssertTrue(manual.canConsumeSource)
        let manualG = try XCTUnwrap(manual.chart.measures.flatMap(\.chordEvents).first { $0.rawInput == "G" })
        let manualGlyph = try chordLayout(manualG.id, in: layout(manual.chart))
        XCTAssertEqual(autoG.startPosition, manualG.startPosition)
        XCTAssertEqual(autoG.duration, manualG.duration)
        XCTAssertEqual(autoG.mappedRhythmSlotIndex, manualG.mappedRhythmSlotIndex)
        XCTAssertEqual(autoG.manualLaneFraction, manualG.manualLaneFraction)
        XCTAssertNil(manualG.manualVisualLaneFraction, "The explicit manual flow retains its existing guide placement")
        let legacyFrame = manualGlyph.naturalFrame.union(manualGlyph.frame)
        let retainedAFrame = a.bounds.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
        XCTAssertTrue(legacyFrame.intersects(retainedAFrame),
            "Legacy staging must reproduce actual overlap: glyph=\(legacyFrame), sourceFrame=\(sourceFrame), A=\(retainedAFrame)")
        XCTAssertGreaterThan(abs(manualGlyph.naturalFrame.minX - autoGlyph.naturalFrame.minX), 20,
            "The fixture must exercise source placement which differs from the committed beat guide")
    }

    func testAutomaticFirstRhythmChordUsesBeatOneGuideInsteadOfSourceLeftEdge() throws {
        var chart = Chart.blank(title: "Automatic downbeat", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarterRest, .quarter, .quarter, .quarter], for: measureID))
        let sourceLayout = layout(chart)
        let measureLayout = try XCTUnwrap(sourceLayout.systems.first?.measures.first)
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        let x = measureLayout.chordBandFrame.minX + measureLayout.chordBandFrame.width * 0.7 - sourceFrame.minX
        let y = measureLayout.chordBandFrame.midY - sourceFrame.minY
        let source = PKDrawing(strokes: [stroke([
            CGPoint(x: x + 14, y: y - 8),
            CGPoint(x: x, y: y),
            CGPoint(x: x + 14, y: y + 8)
        ], seed: 2)])
        let state = try makeState(chart, drawings: [source], texts: ["C"])
        XCTAssertGreaterThan(try XCTUnwrap(state.draftChords.first?.targetFraction), 0.6)

        let result = try XCTUnwrap(prepare(chart, state: state, drawing: source, elapsed: 2))
        let measure = try XCTUnwrap(result.chart.measure(id: measureID))
        let event = try XCTUnwrap(measure.chordEvents.first)
        let renderedMeasure = try XCTUnwrap(layout(result.chart).systems.first?.measures.first)
        let glyph = try chordLayout(event.id, in: layout(result.chart))
        let openingRest = try XCTUnwrap(renderedMeasure.noteLayouts.first)

        XCTAssertEqual(event.startPosition.displayText, "1")
        XCTAssertNil(event.manualVisualLaneFraction)
        XCTAssertEqual(glyph.snapGuideTarget.x, openingRest.noteheadFrame.midX, accuracy: 0.01)
        XCTAssertLessThan(glyph.naturalFrame.maxX, source.bounds.minX + sourceFrame.minX)
        XCTAssertTrue(result.drawing.strokes.isEmpty)
        let archive = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: archive))
    }

    func testIdleCompletionAlsoPreservesEachWrittenLeftEdge() throws {
        let chart = try chartWithF()
        let drawings = [PKDrawing(strokes: [gStroke()]), PKDrawing(strokes: [aFirstStroke()])]
        let state = try makeState(chart, drawings: drawings, texts: ["G", "A"])
        let source = PKDrawing(strokes: drawings.flatMap(\.strokes))
        let automatic = try XCTUnwrap(prepare(chart, state: state, drawing: source, elapsed: 2))
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout(chart))
        let resultLayout = layout(automatic.chart)
        for (index, text) in ["G", "A"].enumerated() {
            let event = try XCTUnwrap(automatic.chart.measures.flatMap(\.chordEvents).first { $0.rawInput == text })
            let glyph = try chordLayout(event.id, in: resultLayout)
            XCTAssertEqual(glyph.naturalFrame.minX, drawings[index].bounds.minX + frame.minX, accuracy: 2)
            XCTAssertNotNil(event.manualVisualLaneFraction)
        }
        XCTAssertTrue(automatic.drawing.strokes.isEmpty)
        XCTAssertNil(automatic.chart.pageHandwrittenChordData)
    }

    func testProspectiveWideGlyphCannotConsumeItsSourceWhenItWouldCoverUnfinishedNeighbor() throws {
        let chart = try chartWithF()
        let g = PKDrawing(strokes: [gStroke()])
        let neighbor = PKDrawing(strokes: [aFirstStroke(x: 159, top: 0, bottom: 65)])
        let source = PKDrawing(strokes: g.strokes + neighbor.strokes)
        let originalBytes = source.dataRepresentation()
        let state = try makeState(chart, drawings: [g, neighbor], texts: ["Cmaj7/E", nil])
        XCTAssertNotNil(ChordRecognitionCompendium.match("Cmaj7/E"))
        XCTAssertTrue(ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: [0],
            source: source, pageSize: pageSize, requiresLaterInk: true),
            "The old source-gap gate must pass so this case exercises prospective glyph safety")

        XCTAssertNil(prepare(chart, state: state, drawing: source),
            "A supported, trusted read cannot consume ink while its final glyph covers retained writing")
        XCTAssertEqual(source.dataRepresentation(), originalBytes)
        XCTAssertEqual(chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["F"])
    }

    func testActualContinuationKeepsGOffAWhileItsNextStrokeAndReaderRemainUnfinished() async throws {
        let gStarted = expectation(description: "G read is held before A begins")
        let currentA = expectation(description: "Current ownership includes the unfinished A")
        let aStarted = expectation(description: "A read remains unfinished")
        let gRendered = expectation(description: "G rendered without moving onto A")
        let recognizer = PlacementContinuationRecognizer(onG: { gStarted.fulfill() }, onA: { aStarted.fulfill() })
        let host = try makeHost(try chartWithF(), recognizer: recognizer)
        defer {
            host.view.onChordInkDraftPreviewChanged = nil
            recognizer.releaseG.signal()
            recognizer.releaseA.signal()
            host.view.recognizesChordInk = false
            host.window.isHidden = true
        }
        let g = gStroke()
        let a = aFirstStroke()
        let originalF = try XCTUnwrap(host.view.chart.measures.flatMap(\.chordEvents).first)
        let originalFGlyph = try chordLayout(originalF.id, in: layout(host.view.chart))
        var beganA = false
        var observedA = false
        var didRenderG = false
        host.view.onChordInkDraftPreviewChanged = { payloads in
            let state = self.previewState(payloads, chart: host.view.chart)
            host.view.chordPreviewState = state
            if beganA, !observedA, payloads.count == 2,
               payloads.allSatisfy({ $0.targetLifecycle?.stage == .collecting }) {
                XCTAssertEqual(Set(payloads.map { $0.target.measureID }).count, 1,
                    "Both source targets must exercise the same measure")
                observedA = true
                currentA.fulfill()
            }
            guard observedA, !didRenderG,
                  state.draftChords.contains(where: { $0.previewText == "G" && ChordInkAutomaticRenderPolicy.isTrusted($0) }),
                  state.draftChords.contains(where: { $0.targetLifecycle?.stage == .collecting }),
                  let lastInput = host.coordinator.lastInputAt,
                  let outcome = host.view.renderChordDraftAutomatically(chart: host.view.chart,
                      state: state, now: Date(), lastInputAt: lastInput) else { return }
            didRenderG = true
            XCTAssertEqual(outcome.result.renderedChordCount, 1)
            gRendered.fulfill()
        }
        host.view.canvasViewDidBeginUsingTool(host.canvas)
        host.canvas.drawing = PKDrawing(strokes: [g])
        host.view.canvasViewDrawingDidChange(host.canvas)
        host.view.canvasViewDidEndUsingTool(host.canvas)
        await fulfillment(of: [gStarted], timeout: 5)

        beganA = true
        host.view.canvasViewDidBeginUsingTool(host.canvas)
        host.canvas.drawing = PKDrawing(strokes: [g, a])
        host.view.canvasViewDrawingDidChange(host.canvas)
        host.view.canvasViewDidEndUsingTool(host.canvas)
        await fulfillment(of: [currentA], timeout: 5)
        recognizer.releaseG.signal()
        await fulfillment(of: [gRendered, aStarted], timeout: 5)

        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout(host.view.chart))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [a]), current: host.canvas.drawing))
        let gEvent = try XCTUnwrap(host.view.chart.measures.flatMap(\.chordEvents).first { $0.rawInput == "G" })
        let gGlyph = try chordLayout(gEvent.id, in: layout(host.view.chart))
        let afterFGlyph = try chordLayout(originalF.id, in: layout(host.view.chart))
        XCTAssertEqual(afterFGlyph.naturalFrame, originalFGlyph.naturalFrame)
        XCTAssertEqual(gGlyph.naturalFrame.minX, g.renderBounds.minX + sourceFrame.minX, accuracy: 2)
        assertGlyphsAvoidRetainedInk(chart: host.view.chart, drawing: host.canvas.drawing, sourceFrame: sourceFrame)

        // The next Pencil stroke is still part of A, not a completed chord.
        // Adding it must keep the first diagonal and G's visual anchor intact.
        let second = stroke([CGPoint(x: 219, y: 48), CGPoint(x: 235, y: 80)], seed: 20)
        host.view.canvasViewDidBeginUsingTool(host.canvas)
        host.canvas.drawing = PKDrawing(strokes: [a, second])
        host.view.canvasViewDrawingDidChange(host.canvas)
        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: host.view.chordPreviewState, now: Date(), lastInputAt: host.coordinator.lastInputAt))
        host.view.canvasViewDidEndUsingTool(host.canvas)
        host.view.layoutIfNeeded()
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [a, second]), current: host.canvas.drawing))
        let after = try chordLayout(gEvent.id, in: layout(host.view.chart))
        XCTAssertEqual(after.naturalFrame, gGlyph.naturalFrame)
        let continuedF = try chordLayout(originalF.id, in: layout(host.view.chart))
        XCTAssertEqual(continuedF.naturalFrame, originalFGlyph.naturalFrame)
        assertGlyphsAvoidRetainedInk(chart: host.view.chart, drawing: host.canvas.drawing, sourceFrame: sourceFrame)
    }

    func testOptionalCapturedOverlapSourceReplaysWithoutMovingGIntoRetainedInk() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let path = ProcessInfo.processInfo.environment["ICHART_AUTO_OVERLAP_LIBRARY"]
        let fixture = path.map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent(
            ".build/auto-render95-overlap-2026-10-30/app-support/library-state.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Optional local captured overlap source is not present")
        }
        let bytes = try Data(contentsOf: fixture)
        let snapshot = try XCTUnwrap(try FileChartRepository(url: fixture).loadSnapshot())
        let captured = try XCTUnwrap(snapshot.charts.filter {
            $0.pageHandwrittenChordData != nil && $0.pageHandwrittenChordCoordinateSpace?.width == 784
                && $0.pageHandwrittenChordCoordinateSpace?.height == 700
        }.max(by: { $0.updatedAt < $1.updatedAt }))
        var chart = captured
        let oldG = try XCTUnwrap(chart.measures.flatMap(\.chordEvents).first { $0.rawInput == "G" })
        let g = try PKDrawing(data: XCTUnwrap(oldG.sourceInkData))
        let a = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let capturedSpace = try XCTUnwrap(chart.pageHandwrittenChordCoordinateSpace)
        XCTAssertTrue(chart.deleteChordEvent(oldG.id))
        let state = try makeState(chart, drawings: [g, a], texts: ["G", nil])
        let source = PKDrawing(strokes: g.strokes + a.strokes)
        let manualState = try makeState(chart, drawings: [g], texts: ["G"])
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout(chart))
        XCTAssertEqual(sourceFrame.width, capturedSpace.size.width, accuracy: 0.01,
            "The replay page must reconstruct the actual saved chord-canvas width")
        XCTAssertEqual(sourceFrame.height, capturedSpace.size.height, accuracy: 0.01,
            "The replay page must reconstruct the actual saved chord-canvas height")
        let manual = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: manualState,
            currentDrawing: g, coordinateSpace: capturedSpace)
        XCTAssertTrue(manual.canConsumeSource)
        let legacyG = try XCTUnwrap(manual.chart.measures.flatMap(\.chordEvents).first { $0.rawInput == "G" })
        let legacyGlyph = try chordLayout(legacyG.id, in: layout(manual.chart))
        let legacyFrame = legacyGlyph.naturalFrame.union(legacyGlyph.frame)
        let retainedFrames = a.strokes.map {
            $0.renderBounds.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
        }
        XCTAssertTrue(retainedFrames.contains(where: legacyFrame.intersects),
            "Captured legacy overlap: glyph=\(legacyFrame), sourceFrame=\(sourceFrame), retained=\(retainedFrames)")
        let outcome = try XCTUnwrap(prepare(chart, state: state, drawing: source))
        let newG = try XCTUnwrap(outcome.chart.measures.flatMap(\.chordEvents).first { $0.rawInput == "G" })
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout(chart))
        let glyph = try chordLayout(newG.id, in: layout(outcome.chart))
        XCTAssertEqual(glyph.naturalFrame.minX, g.bounds.minX + frame.minX, accuracy: 2)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: a, current: outcome.drawing))
        assertGlyphsAvoidRetainedInk(chart: outcome.chart, drawing: outcome.drawing, sourceFrame: frame)
        XCTAssertEqual(try Data(contentsOf: fixture), bytes, "Captured source must remain read-only")
    }

    private func prepare(_ chart: Chart, state: ChordPreviewState, drawing: PKDrawing,
        elapsed: TimeInterval = 0.05) -> ChordInkDraftRenderCoordinator.AutomaticOutcome? {
        let sourceLayout = layout(chart)
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        return ChordInkDraftRenderCoordinator.prepareAutomatic(chart: chart, state: state,
            currentDrawing: drawing, coordinateSpace: PersistentInkCoordinateSpace(size: sourceFrame.size),
            now: inputAt.addingTimeInterval(elapsed), lastInputAt: inputAt, isUsingTool: false,
            allowsImmediateSpatialCompletion: true, sourcePageLayout: sourceLayout, sourceChordFrame: sourceFrame)
    }

    private func chartWithF() throws -> Chart {
        var chart = Chart.draft(title: "Automatic source placement", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        let match = try XCTUnwrap(ChordRecognitionCompendium.match("F"))
        _ = try XCTUnwrap(chart.appendRecognizedChordEvent(match.symbol, rawInput: "F",
            to: chart.measures[0].id, atFraction: 0.04))
        return chart
    }

    private func layout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
    }

    private func chordLayout(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetChordLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == id })
    }

    private func makeState(_ chart: Chart, drawings: [PKDrawing], texts: [String?]) throws -> ChordPreviewState {
        let pageLayout = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: pageLayout)
        let inputs = try drawings.enumerated().map { index, drawing -> ChordInkDraftInput in
            let target = try XCTUnwrap(LeadSheetChordInkRecognitionTargeting.target(for: drawing,
                chordFrame: frame, pageLayout: pageLayout))
            let measure = try XCTUnwrap(chart.measure(id: target.measureID))
            let text = texts[index]
            let decision = ChordInkRecognitionDecision(action: text == nil ? .confirm : .trusted,
                acceptedText: text, reason: "Test source read", isCloseRace: false,
                competingCandidateText: nil, confidenceGap: nil)
            var input = ChordInkDraftInput(measureID: target.measureID, measureIndex: measure.index,
                targetFraction: target.fraction,
                visualOrder: LeadSheetChordInkRecognitionTargeting.visualOrder(for: drawing,
                    chordFrame: frame, pageLayout: pageLayout),
                laneLocation: LeadSheetChordInkRecognitionTargeting.laneLocation(for: drawing,
                    chordFrame: frame, pageLayout: pageLayout),
                layoutPageSize: pageSize, drawingData: drawing.dataRepresentation(),
                candidateTexts: text.map { [$0] } ?? [], bestCandidateText: text,
                confidence: text == nil ? 0 : 4.5, strokeCount: drawing.strokes.count,
                recognitionDecision: decision)
            input.targetLifecycle = ChordInkRecognitionTargetLifecycle(generationID: UUID(), anchor: input.anchor,
                ownership: ChordInkRecognitionTargetOwnership(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: drawing)),
                stage: text == nil ? .collecting : .frozen)
            return input
        }
        return ChordPreviewState(draftChords: inputs.map { ChordInkDraft(input: $0) }, layoutPageSize: pageSize)
    }

    private func previewState(_ payloads: [ChordInkRecognitionProposalPayload], chart: Chart) -> ChordPreviewState {
        let inputs = payloads.compactMap { payload -> ChordInkDraftInput? in
            guard let measure = chart.measure(id: payload.target.measureID) else { return nil }
            let decision = ChordInkRecognitionPolicy.decision(for: payload.result)
            return ChordInkDraftInput(measureID: payload.target.measureID, measureIndex: measure.index,
                targetFraction: payload.target.fraction, visualOrder: payload.visualOrder,
                laneLocation: payload.laneLocation, layoutPageSize: payload.layoutPageSize,
                drawingData: payload.drawingData, candidateTexts: payload.result.rawCandidates,
                bestCandidateText: decision.acceptedText, confidence: payload.result.confidence,
                strokeCount: payload.timing.strokeCount, recognitionResult: payload.result,
                primaryDecision: decision, recognitionDecision: decision, targetLifecycle: payload.targetLifecycle,
                requiresManualReviewOnly: payload.requiresManualReviewOnly)
        }
        var state = ChordPreviewState()
        state.replaceDraftChords(with: inputs)
        return state
    }

    private func assertGlyphsAvoidRetainedInk(chart: Chart, drawing: PKDrawing, sourceFrame: CGRect,
        file: StaticString = #filePath, line: UInt = #line) {
        let inkFrames = drawing.strokes.flatMap { PencilKitInkAdapter.visibleStrokeFragments(from: $0) }
            .map { $0.renderBounds.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY) }
        let glyphs = layout(chart).systems.flatMap(\.measures).flatMap(\.chordLayouts)
        for glyph in glyphs {
            for ink in inkFrames {
                XCTAssertFalse(glyph.naturalFrame.union(glyph.frame).intersects(ink),
                    "Prospective notation must stay clear of unfinished source ink", file: file, line: line)
            }
        }
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let coordinator: ChordInkDraftRenderCoordinator
        let window: UIWindow
    }

    private func makeHost(_ chart: Chart, recognizer: any ChordInkRecognizing) throws -> Host {
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize), chordInkRecognizer: recognizer)
        view.chart = chart
        view.interactionMode = .chordEntry
        view.manualRenderWithPreview = false
        let coordinator = ChordInkDraftRenderCoordinator()
        view.chordDraftRenderCoordinator = coordinator
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: CGRect(origin: .zero, size: pageSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return Host(view: view, canvas: try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last),
            coordinator: coordinator, window: window)
    }

    private func gStroke() -> PKStroke {
        stroke([CGPoint(x: 128, y: 14), CGPoint(x: 112, y: 12), CGPoint(x: 106, y: 20),
            CGPoint(x: 106, y: 37), CGPoint(x: 112, y: 44), CGPoint(x: 128, y: 41),
            CGPoint(x: 128, y: 28), CGPoint(x: 118, y: 28)].map {
                CGPoint(x: $0.x, y: $0.y + 36)
            }, seed: 18)
    }

    private func aFirstStroke(x: CGFloat = 193, top: CGFloat = 48, bottom: CGFloat = 80) -> PKStroke {
        stroke([CGPoint(x: x, y: bottom), CGPoint(x: x + 26, y: top)], seed: 19)
    }

    private func stroke(_ locations: [CGPoint], seed: UInt32) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.01,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points,
                creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}

private final class PlacementContinuationRecognizer: ChordInkRecognizing {
    let releaseG = DispatchSemaphore(value: 0)
    let releaseA = DispatchSemaphore(value: 0)
    private let onG: () -> Void
    private let onA: () -> Void
    private var readG = false
    private var readA = false

    init(onG: @escaping () -> Void, onA: @escaping () -> Void) {
        self.onG = onG
        self.onA = onA
    }

    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        let text = (strokes.map(\.bounds.minX).min() ?? 0) < 170 ? "G" : "A"
        if text == "G", !readG {
            readG = true
            onG()
            _ = releaseG.wait(timeout: .now() + 15)
        } else if text == "A", !readA {
            readA = true
            onA()
            _ = releaseA.wait(timeout: .now() + 15)
        }
        return ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text), confidence: 4.5,
            candidateScores: [ChordInkCandidateScore(text: text, displayText: text, confidence: 4.5)])
    }
}
#endif

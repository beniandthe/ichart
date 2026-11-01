#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Drives real PencilKit delegate scheduling, current-source preparation,
/// incremental result publication and selective canvas consumption together.
/// A blocked reader proves independence without asserting device latency.
@MainActor
final class ChordInkIncrementalHostOrchestrationTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)

    func testActualInputRendersFWhileGReaderIsStillBlockedAndRetainsExactGSource() async throws {
        let gStarted = expectation(description: "G entered its reader")
        let fRendered = expectation(description: "F rendered independently of G")
        let recognizer = HostOrchestrationBlockingRecognizer(blocks: .g, onBlocked: {
            gStarted.fulfill()
        })
        let host = try makeHost(recognizer)
        defer {
            host.view.onChordInkDraftPreviewChanged = nil
            recognizer.release.signal()
            host.view.recognizesChordInk = false
            host.window.isHidden = true
        }
        let f = fStroke()
        let g = gStroke()
        let expectedG = PKDrawing(strokes: [g])
        var didRenderF = false
        var sawCollectingCensus = false
        host.view.onChordInkDraftPreviewChanged = { payloads in
            let state = self.previewState(payloads, chart: host.view.chart)
            host.view.chordPreviewState = state
            if payloads.count == 2,
               payloads.allSatisfy({ $0.targetLifecycle?.stage == .collecting }) {
                sawCollectingCensus = true
            }
            guard !didRenderF,
                  state.draftChords.contains(where: {
                      $0.previewText == "F" && ChordInkAutomaticRenderPolicy.isTrusted($0)
                  }),
                  state.draftChords.contains(where: { $0.targetLifecycle?.stage == .collecting }),
                  let inputAt = host.coordinator.lastInputAt,
                  let outcome = host.view.renderChordDraftAutomatically(
                      chart: host.view.chart, state: state, now: Date(), lastInputAt: inputAt
                  ) else { return }
            didRenderF = true
            XCTAssertEqual(outcome.result.renderedChordCount, 1)
            XCTAssertEqual(outcome.chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["F"])
            XCTAssertEqual(outcome.remainingState.draftChords.count, 1)
            XCTAssertEqual(outcome.remainingState.draftChords.first?.targetLifecycle?.stage, .collecting)
            fRendered.fulfill()
        }

        host.view.canvasViewDidBeginUsingTool(host.canvas)
        host.canvas.drawing = PKDrawing(strokes: [f, g])
        host.view.canvasViewDrawingDidChange(host.canvas)
        host.view.canvasViewDidEndUsingTool(host.canvas)

        await fulfillment(of: [gStarted, fRendered], timeout: 5)

        XCTAssertTrue(sawCollectingCensus, "Preparation must publish complete ownership before either read finishes")
        XCTAssertTrue(recognizer.isBlocked, "F must reach the real chart while G cannot finish")
        XCTAssertEqual(recognizer.completedTexts, ["F"])
        XCTAssertEqual(host.view.chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["F"])
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedG, current: host.canvas.drawing))
        let storedG = try PKDrawing(data: XCTUnwrap(host.view.chart.pageHandwrittenChordData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedG, current: storedG))
    }

    func testActualGEditRefreshesCensusWithoutDiscardingBlockedUnchangedFRead() async throws {
        let fStarted = expectation(description: "F entered its reader")
        let changedCensus = expectation(description: "Changed G owns its latest source")
        let fRendered = expectation(description: "Unchanged F survived the G edit")
        let recognizer = HostOrchestrationBlockingRecognizer(blocks: .f, onBlocked: {
            fStarted.fulfill()
        })
        let host = try makeHost(recognizer)
        defer {
            host.view.onChordInkDraftPreviewChanged = nil
            recognizer.release.signal()
            host.view.recognizesChordInk = false
            host.window.isHidden = true
        }
        let f = fStroke()
        let originalG = gStroke()
        let changedG = gStroke(xOffset: 8)
        let expectedChangedG = PKDrawing(strokes: [changedG])
        var editedG = false
        var didObserveChangedCensus = false
        var didRenderF = false
        host.view.onChordInkDraftPreviewChanged = { payloads in
            let state = self.previewState(payloads, chart: host.view.chart)
            host.view.chordPreviewState = state
            if editedG, !didObserveChangedCensus, payloads.count == 2,
               payloads.allSatisfy({ $0.targetLifecycle?.stage == .collecting }),
               let right = payloads.max(by: { ($0.visualOrder ?? 0) < ($1.visualOrder ?? 0) }),
               let currentG = try? PKDrawing(data: right.drawingData),
               ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expectedChangedG, current: currentG) {
                didObserveChangedCensus = true
                changedCensus.fulfill()
            }
            guard didObserveChangedCensus, !didRenderF,
                  state.draftChords.contains(where: {
                      $0.previewText == "F" && ChordInkAutomaticRenderPolicy.isTrusted($0)
                  }),
                  let inputAt = host.coordinator.lastInputAt,
                  let outcome = host.view.renderChordDraftAutomatically(
                      chart: host.view.chart, state: state, now: Date(), lastInputAt: inputAt
                  ) else { return }
            didRenderF = true
            XCTAssertEqual(outcome.result.renderedChordCount, 1)
            fRendered.fulfill()
        }

        host.view.canvasViewDidBeginUsingTool(host.canvas)
        host.canvas.drawing = PKDrawing(strokes: [f, originalG])
        host.view.canvasViewDrawingDidChange(host.canvas)
        host.view.canvasViewDidEndUsingTool(host.canvas)
        await fulfillment(of: [fStarted], timeout: 5)

        editedG = true
        host.view.canvasViewDidBeginUsingTool(host.canvas)
        host.canvas.drawing = PKDrawing(strokes: [f, changedG])
        host.view.canvasViewDrawingDidChange(host.canvas)
        host.view.canvasViewDidEndUsingTool(host.canvas)
        await fulfillment(of: [changedCensus], timeout: 5)
        XCTAssertTrue(recognizer.isBlocked)
        XCTAssertTrue(host.view.chart.measures.allSatisfy(\.chordEvents.isEmpty))

        recognizer.release.signal()
        await fulfillment(of: [fRendered], timeout: 5)

        XCTAssertEqual(recognizer.startedTexts.filter { $0 == "F" }.count, 1,
            "Editing G must reuse the unchanged in-flight F request")
        XCTAssertEqual(host.view.chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["F"])
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedChangedG, current: host.canvas.drawing))
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let window: UIWindow
        let coordinator: ChordInkDraftRenderCoordinator
    }

    private func makeHost(_ recognizer: any ChordInkRecognizing) throws -> Host {
        var chart = Chart.draft(title: "Incremental host orchestration", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 4)
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize),
            chordInkRecognizer: recognizer)
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
        let canvas = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        XCTAssertFalse(canvas.isHidden)
        XCTAssertTrue(canvas.isUserInteractionEnabled)
        XCTAssertGreaterThan(canvas.bounds.width, 0)
        return Host(view: view, canvas: canvas, window: window, coordinator: coordinator)
    }

    private func previewState(_ payloads: [ChordInkRecognitionProposalPayload], chart: Chart) -> ChordPreviewState {
        let inputs = payloads.compactMap { payload -> ChordInkDraftInput? in
            guard let measure = chart.measure(id: payload.target.measureID) else { return nil }
            let decision = ChordInkRecognitionPolicy.decision(for: payload.result)
            return ChordInkDraftInput(measureID: payload.target.measureID, measureIndex: measure.index,
                targetFraction: payload.target.fraction, visualOrder: payload.visualOrder,
                laneLocation: payload.laneLocation, layoutPageSize: payload.layoutPageSize,
                drawingData: payload.drawingData, candidateTexts: payload.result.rawCandidates,
                bestCandidateText: decision.acceptedText ?? payload.result.match?.displayText,
                confidence: payload.result.confidence, strokeCount: payload.timing.strokeCount,
                recognitionResult: payload.result, primaryDecision: decision, recognitionDecision: decision,
                targetLifecycle: payload.targetLifecycle, requiresManualReviewOnly: payload.requiresManualReviewOnly)
        }
        var state = ChordPreviewState()
        state.replaceDraftChords(with: inputs)
        return state
    }

    private func fStroke() -> PKStroke {
        stroke([CGPoint(x: 20, y: 44), CGPoint(x: 20, y: 12), CGPoint(x: 42, y: 12),
            CGPoint(x: 20, y: 12), CGPoint(x: 20, y: 27), CGPoint(x: 37, y: 27)], seed: 17)
    }

    private func gStroke(xOffset: CGFloat = 0) -> PKStroke {
        stroke([CGPoint(x: 242, y: 14), CGPoint(x: 226, y: 12), CGPoint(x: 220, y: 20),
            CGPoint(x: 220, y: 37), CGPoint(x: 226, y: 44), CGPoint(x: 242, y: 41),
            CGPoint(x: 242, y: 28), CGPoint(x: 232, y: 28)].map {
                CGPoint(x: $0.x + xOffset, y: $0.y)
            }, seed: 18)
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

private final class HostOrchestrationBlockingRecognizer: ChordInkRecognizing {
    enum BlockedChord { case f, g }
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let blocks: BlockedChord
    private let onBlocked: () -> Void
    private var didBlock = false
    private var blocked = false
    private var started: [String] = []
    private var completed: [String] = []

    init(blocks: BlockedChord, onBlocked: @escaping () -> Void) {
        self.blocks = blocks
        self.onBlocked = onBlocked
    }

    var isBlocked: Bool { lock.withLock { blocked } }
    var startedTexts: [String] { lock.withLock { started } }
    var completedTexts: [String] { lock.withLock { completed } }

    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        let minX = strokes.map(\.bounds.minX).min() ?? 0
        let text = minX < 150 ? "F" : "G"
        let shouldBlock = lock.withLock {
            started.append(text)
            guard !didBlock, (blocks == .f && text == "F") || (blocks == .g && text == "G") else { return false }
            didBlock = true
            blocked = true
            return true
        }
        if shouldBlock {
            onBlocked()
            _ = release.wait(timeout: .now() + 15)
            lock.withLock { blocked = false }
        }
        lock.withLock { completed.append(text) }
        return ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text), confidence: 4.5,
            candidateScores: [ChordInkCandidateScore(text: text, displayText: text, confidence: 4.5)])
    }
}
#endif

#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Uses the shipping Editor's callbacks, current-source preparation and real
/// scheduled automatic attempt, including direct ending-label approval.
@MainActor
final class ChordInkAutomaticStructuralWakeTests: XCTestCase {
    func testBarlineOnlyCensusWakesEditorAfterStructuralGraceWithoutReview() async throws {
        let host = try await mount()
        let source = try structuralDrawing(in: host, fractions: [0.5])
        append(source.strokes, to: host)
        try await waitForCensus(in: host, barlineCount: 1)

        XCTAssertTrue(host.view.chordPreviewState.draftChords.isEmpty)
        XCTAssertTrue(host.view.hasCurrentAutomaticChordCensus,
            "A real barline-only preparation must install a valid empty chord census")
        XCTAssertEqual(host.view.chordPreviewState.draftBarlines.first?.kind, .single)
        let inputAt = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.lastInputAt)
        try await wait(until: inputAt.addingTimeInterval(ordinaryIdlePlusMargin))
        XCTAssertEqual(host.model.chart.measures.count, 1,
            "A structural barline must wait for its configured structural idle interval")
        XCTAssertEqual(host.ink.drawing.strokes.count, 1)

        try await waitForCondition(in: host, timeout: 5) {
            host.model.chart.measures.count == 2 && host.ink.drawing.strokes.isEmpty
        }
        XCTAssertNil(host.model.chart.pageHandwrittenChordData)
        XCTAssertTrue(host.view.chordPreviewState.isEmpty)
        XCTAssertNil(host.window.rootViewController?.presentedViewController,
            "A recognized measure boundary must not depend on opening Fix Writing")
    }

    func testLateFinalDrawingCallbackWithUnchangedBarlineStillArmsLatestEditorDeadline() async throws {
        let host = try await mount()
        let source = try structuralDrawing(in: host, fractions: [0.5])
        append(source.strokes, to: host)
        try await waitForCensus(in: host, barlineCount: 1)
        let firstInputAt = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.lastInputAt)
        let firstDraftIDs = host.view.chordPreviewState.draftBarlines.map(\.id)

        try await Task.sleep(nanoseconds: 150_000_000)
        // PencilKit may publish its final drawing update after tool-end. The
        // detected boundary can remain identical while the actual input clock
        // and source revision change, so a barline-added callback alone cannot
        // be the only way to arm the Editor's automatic work.
        host.view.canvasViewDrawingDidChange(host.ink)
        let finalInputAt = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.lastInputAt)
        XCTAssertGreaterThan(finalInputAt, firstInputAt)
        try await waitForCensus(in: host, barlineCount: 1)
        XCTAssertEqual(host.view.chordPreviewState.draftBarlines.map(\.id), firstDraftIDs)
        try await wait(until: finalInputAt.addingTimeInterval(ordinaryIdlePlusMargin))
        XCTAssertEqual(host.model.chart.measures.count, 1)
        XCTAssertEqual(host.ink.drawing.strokes.count, 1)

        try await waitForCondition(in: host, timeout: 5) {
            host.model.chart.measures.count == 2 && host.ink.drawing.strokes.isEmpty
        }
        XCTAssertNil(host.model.chart.pageHandwrittenChordData)
        XCTAssertNil(host.window.rootViewController?.presentedViewController)
    }

    func testDirectEndingReviewApprovalCommitsAutomaticallyAfterPanelClearsInputClock() async throws {
        let host = try await mount(measureCount: 2)
        let originalMeasureIDs = host.model.chart.measures.map(\.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: host.model.chart,
            pageSize: host.view.bounds.size, includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == originalMeasureIDs[0] })
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let left = firstMeasure.frame.minX + 1 - region.frame.minX
        let right = firstMeasure.frame.maxX - 1 - region.frame.minX
        let top = lane.minY + lane.height * 0.12 - region.frame.minY
        let hook = max(6, lane.height * 0.20)
        let source = LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: [stroke([
            CGPoint(x: left, y: top + hook), CGPoint(x: left, y: top),
            CGPoint(x: right, y: top), CGPoint(x: right, y: top + hook)
        ], seed: 201)]))
        append(source.strokes, to: host)
        try await waitForCondition(in: host, timeout: 2) {
            host.view.hasCurrentAutomaticChordCensus && host.view.chordPreviewState.draftEndings.count == 1
        }
        let ending = try XCTUnwrap(host.view.chordPreviewState.draftEndings.first)
        XCTAssertFalse(ending.isReviewed)
        // This is the existing host event emitted by a direct ending-roof hit,
        // rather than the global Review & Render command (whose request has a
        // different continuesRendering value).
        let selectEnding = try XCTUnwrap(host.view.onChordInkDraftEndingSelected)
        selectEnding(ending.id)
        try await waitForCondition(in: host, timeout: 3) {
            host.window.rootViewController?.presentedViewController != nil
                && host.view.isInteractionSuspended
                && host.view.chordDraftRenderCoordinator?.automaticRenderReferenceAt == nil
                && self.descendants(host.window).contains {
                    ($0 as? IChartTypedUITextField)?.placeholder == "Ending label"
                }
        }
        let field = try XCTUnwrap(descendants(host.window).compactMap { $0 as? IChartTypedUITextField }
            .first { $0.placeholder == "Ending label" })
        field.text = "On cue"
        field.sendActions(for: .editingChanged)
        try await waitForCondition(in: host, timeout: 2) {
            self.descendants(host.window).compactMap { $0 as? PencilOnlyUIButton }
                .contains { $0.accessibilityLabel == "Use Ending" && $0.isEnabled }
        }
        let apply = try XCTUnwrap(descendants(host.window).compactMap { $0 as? PencilOnlyUIButton }
            .first { $0.accessibilityLabel == "Use Ending" && $0.isEnabled })
        apply.sendActions(for: .touchUpInside)
        try await waitForCondition(in: host, timeout: 4) {
            host.model.chart.roadmapObjects.contains { $0.type.isEnding }
                && host.ink.drawing.strokes.isEmpty
                && host.window.rootViewController?.presentedViewController == nil
        }
        let committed = try XCTUnwrap(host.model.chart.roadmapObjects.first { $0.type.isEnding })
        XCTAssertEqual(committed.startMeasureID, originalMeasureIDs[0])
        XCTAssertEqual(committed.endMeasureID, originalMeasureIDs[0])
        XCTAssertEqual(committed.resolvedEndingDisplayText, "On cue")
        XCTAssertEqual(committed.resolvedEndingEndStyle, .closed)
        let receipt = try PKDrawing(data: XCTUnwrap(committed.sourceInkData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: receipt))
        XCTAssertEqual(host.model.chart.measures.map(\.id), originalMeasureIDs)
        XCTAssertNil(host.model.chart.pageHandwrittenChordData)
    }

    private var ordinaryIdlePlusMargin: TimeInterval { ChordInkAutomaticRenderPolicy.idleDelay + 0.1 }

    private struct Mounted {
        let model: StructuralWakeChartModel
        let view: LeadSheetCanvasUIKitView
        let ink: PKCanvasView
        let window: UIWindow
    }

    private func mount(measureCount: Int = 1) async throws -> Mounted {
        let key = ChordInkWorkflowSettings.manualRenderWithPreviewKey
        let previousPreference = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        var chart = Chart.draft(title: "Disposable structural wake", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: measureCount)
        let model = StructuralWakeChartModel(chart)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = NavigationStack {
            EditorView(chart: Binding(get: { model.chart }, set: { model.chart = $0 }),
                chordInkUserCorrectionMemoryStore: .init(url: directory.appendingPathComponent("corrections.json")),
                initialCanvasMode: .chordEntry)
        }
        .environmentObject(ChartLibraryStore(charts: [chart], selectedChartID: chart.id))
        .environmentObject(IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library")))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in
            for canvas in self.descendants(window).compactMap({ $0 as? LeadSheetCanvasUIKitView }) {
                canvas.recognizesChordInk = false
                canvas.onChordInkDraftPreviewChanged = nil
                canvas.onChordInkDraftBarlinesChanged = nil
                canvas.onChordInkDraftEndingsChanged = nil
                canvas.onChordInkDraftEndingSelected = nil
                canvas.onChordInkAutomaticActivityChanged = nil
            }
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
            if let previousPreference { UserDefaults.standard.set(previousPreference, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<80 {
            window.layoutIfNeeded()
            if let view = descendants(window).compactMap({ $0 as? LeadSheetCanvasUIKitView }).first,
               let ink = view.subviews.compactMap({ $0 as? PKCanvasView }).last,
               !ink.isHidden, view.recognizesChordInk, view.chordDraftRenderCoordinator != nil,
               view.bounds.width > 0, view.bounds.height > 0 {
                XCTAssertTrue(ink.drawing.strokes.isEmpty)
                return Mounted(model: model, view: view, ink: ink, window: window)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("The shipping Editor did not expose its automatic chord-writing canvas")
        throw StructuralWakeFailure.missingCanvas
    }

    private func append(_ strokes: [PKStroke], to host: Mounted) {
        host.view.canvasViewDidBeginUsingTool(host.ink)
        host.ink.drawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(
            PKDrawing(strokes: host.ink.drawing.strokes + strokes))
        host.view.canvasViewDrawingDidChange(host.ink)
        host.view.canvasViewDidEndUsingTool(host.ink)
    }

    private func structuralDrawing(in host: Mounted, fractions: [CGFloat]) throws -> PKDrawing {
        let geometry = try geometry(in: host)
        return PKDrawing(strokes: fractions.enumerated().map { index, fraction in
            let x = geometry.lane.minX + geometry.lane.width * fraction - geometry.frame.minX
            let minY = geometry.lane.minY + geometry.lane.height * 0.06 - geometry.frame.minY
            let maxY = geometry.lane.maxY - geometry.lane.height * 0.06 - geometry.frame.minY
            return stroke([CGPoint(x: x, y: minY), CGPoint(x: x, y: maxY)], seed: index + 1)
        })
    }

    private func geometry(in host: Mounted) throws -> (lane: CGRect, frame: CGRect) {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: host.model.chart,
            pageSize: host.view.bounds.size, includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        return (try XCTUnwrap(region.inputFrames.first), region.frame)
    }

    private func stroke(_ points: [CGPoint], seed: Int) -> PKStroke {
        let path = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 2.5, height: 2.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: path,
                creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
    }

    private func waitForCensus(in host: Mounted, barlineCount: Int) async throws {
        try await waitForCondition(in: host, timeout: 1.1) {
            host.view.hasCurrentAutomaticChordCensus
                && host.view.chordPreviewState.draftBarlines.count == barlineCount
        }
    }

    private func wait(until deadline: Date) async throws {
        let remaining = deadline.timeIntervalSinceNow
        if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
    }

    private func waitForCondition(in host: Mounted, timeout: TimeInterval,
        _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            host.window.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Automatic structural Editor work did not reach the expected source-safe state")
        throw StructuralWakeFailure.deadline
    }

    private func descendants(_ root: UIView) -> [UIView] {
        root.subviews.flatMap { [$0] + descendants($0) }
    }
}

@MainActor
private final class StructuralWakeChartModel: ObservableObject {
    @Published var chart: Chart
    init(_ chart: Chart) { self.chart = chart }
}

private enum StructuralWakeFailure: Error { case missingCanvas, deadline }
#endif

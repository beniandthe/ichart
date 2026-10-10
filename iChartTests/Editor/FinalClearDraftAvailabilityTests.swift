#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Current EditorView toolbar integration. The represented-preview control
/// injects a proposal through the production canvas callback; it is not a
/// handwriting accuracy test or physical Cancel/Confirm acceptance.
@MainActor
final class FinalClearDraftAvailabilityTests: XCTestCase {
    func testNoInkAndNoPreviewDoesNotOfferClearDraftInk() async throws {
        let mounted = try await mountEditor(with: makeChart())
        defer { mounted.close() }
        XCTAssertNil(mounted.model.chart.pageHandwrittenChordData)
        XCTAssertTrue(mounted.canvas.chordPreviewState.isEmpty)
        XCTAssertTrue(clearElements(in: mounted.window).isEmpty)
    }

    func testStoredValidDrawingWithoutPreviewStillOffersEnabledClearDraftInk() async throws {
        var chart = makeChart()
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(tinyDrawing().dataRepresentation()))
        let persisted = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertEqual(persisted.strokes.count, 1)
        XCTAssertFalse(persisted.strokes[0].renderBounds.isEmpty)
        XCTAssertEqual(PencilKitInkAdapter.visibleStrokeFragments(from: persisted.strokes[0]).count, 1)
        XCTAssertEqual(ChordInkDraftVisibleStrokePolicy.visibleStrokeCount(in: persisted), 0,
            "The fixture intentionally preserves drawn ink below preview admission.")

        let mounted = try await mountEditor(with: chart)
        defer { mounted.close() }
        XCTAssertNotNil(mounted.model.chart.pageHandwrittenChordData)
        XCTAssertTrue(mounted.canvas.chordPreviewState.isEmpty)
        try await assertEnabledClear(in: mounted)
    }

    func testRepresentedPreviewOffersEnabledClearFromCurrentToolbar() async throws {
        var chart = makeChart()
        _ = chart.setPageHandwrittenChordDrawing(tinyDrawing().dataRepresentation())
        let mounted = try await mountEditor(with: chart)
        defer { mounted.close() }
        let source = try XCTUnwrap(mounted.model.chart.pageHandwrittenChordData)
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let result = ChordInkRecognitionResult(rawCandidates: ["C"], glyphCandidates: [],
            match: ChordRecognitionCompendium.match("C"), confidence: 1)
        let proposal = ChordInkRecognitionProposalPayload(requestID: UUID(), result: result,
            strokes: [], drawingData: source, target: (mounted.model.chart.measures[0].id, 0.25),
            timing: ChordInkRecognitionTiming(scheduledAt: date, requestedDelay: 0,
                recognitionStartedAt: date, recognitionFinishedAt: date, strokeCount: 1))
        let callback = try XCTUnwrap(mounted.canvas.onChordInkDraftPreviewChanged)
        callback([proposal])
        for _ in 0..<20 where mounted.canvas.chordPreviewState.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(mounted.canvas.chordPreviewState.isEmpty,
            "The positive control must reach the production EditorView preview state.")
        try await assertEnabledClear(in: mounted)
    }

    private func makeChart() -> Chart {
        // Rhythm style avoids the unrelated pending Simple Chart tour default.
        var chart = Chart.draft(title: "Disposable clear eligibility", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func tinyDrawing() -> PKDrawing {
        let points = [CGPoint(x: 160, y: 10), CGPoint(x: 160.5, y: 10.5)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 0.5, height: 0.5), opacity: 1, force: 1,
                azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 100)),
            transform: CGAffineTransform(scaleX: 0.1, y: 0.1), mask: nil, randomSeed: 17)
        return PKDrawing(strokes: [stroke])
    }

    private func mountEditor(with chart: Chart) async throws -> MountedEditor {
        let model = FinalClearDraftChartModel(chart)
        let isolatedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = EditorView(chart: Binding(get: { model.chart }, set: { model.chart = $0 }),
            chordInkUserCorrectionMemoryStore: .init(url: isolatedRoot.appendingPathComponent("corrections.json")),
            initialCanvasMode: .chordEntry)
            .environmentObject(ChartLibraryStore(charts: [chart], selectedChartID: chart.id))
            .environmentObject(IChartPDFLibraryStore(baseDirectory: isolatedRoot.appendingPathComponent("PDF Library")))
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "A foreground native test scene is required.")
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1_180)
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<40 {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            if let canvas = descendants(host.view).compactMap({ $0 as? LeadSheetCanvasUIKitView }).first {
                // Let stored-ink bootstrap settle before the callback control.
                try await Task.sleep(nanoseconds: 300_000_000)
                return MountedEditor(model: model, window: window, previousKeyWindow: previousKeyWindow, canvas: canvas)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        throw NSError(domain: "FinalClearDraftAvailabilityTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The production editor canvas did not mount."])
    }

    private func assertEnabledClear(in mounted: MountedEditor) async throws {
        for _ in 0..<20 {
            mounted.window.layoutIfNeeded()
            let elements = clearElements(in: mounted.window)
            if !elements.isEmpty {
                XCTAssertTrue(elements.contains { !$0.accessibilityTraits.contains(.notEnabled) },
                    "Clear Draft Ink must be enabled for retained ink or a represented preview.")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: mounted.window.bounds).image { _ in
            mounted.window.drawHierarchy(in: mounted.window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Current editor clear eligibility"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("Current EditorView did not expose Clear Draft Ink although draft ink is retained.")
    }

    private func clearElements(in root: UIView) -> [NSObject] {
        let views = [root] + descendants(root)
        // SwiftUI text/buttons can expose public accessibility elements instead
        // of native UILabel/UIButton views, as in SetlistAppearanceTests.
        let elements = views.flatMap { view -> [NSObject] in
            [view] + (view.accessibilityElements ?? []).compactMap { $0 as? NSObject }
        }
        return elements.filter { $0.accessibilityLabel == "Clear Draft Ink" }
    }

    private func descendants(_ root: UIView) -> [UIView] {
        root.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor
    private struct MountedEditor {
        let model: FinalClearDraftChartModel
        let window: UIWindow
        let previousKeyWindow: UIWindow?
        let canvas: LeadSheetCanvasUIKitView

        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
    }
}

@MainActor
private final class FinalClearDraftChartModel: ObservableObject {
    @Published var chart: Chart
    init(_ chart: Chart) { self.chart = chart }
}
#endif

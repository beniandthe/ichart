#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Bounds the native-source and ancestor-compositing hypotheses. Programmatic
/// drawing assignments do not reproduce physical Pencil prediction/Metal ink.
@MainActor
final class ProgressiveInkVisibilityBoundaryTests: XCTestCase {
    func testGrowingChordInkSurvivesPreviewAndStaleModelEchoesInsideNativeZoomViewport() async throws {
        for darkAppearance in [false, true] {
            var chart = Chart.draft(title: "Disposable progressive ink boundary", layoutStyle: .simpleChordSheet)
            chart.completeInitialSetup(title: chart.title, key: .cMajor,
                meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
            let model = ProgressiveInkBoundaryModel(chart)
            let root = ProgressiveInkBoundaryHarness(model: model, darkAppearance: darkAppearance)
            let controller = UIHostingController(rootView: root)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 820, height: 1_180)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }
            var mountedCanvas: LeadSheetCanvasUIKitView?
            for _ in 0..<40 {
                await settle(window)
                mountedCanvas = descendants(controller.view).compactMap { $0 as? LeadSheetCanvasUIKitView }.first
                if mountedCanvas?.window != nil { break }
            }
            let owner = try XCTUnwrap(mountedCanvas)
            let ink = try XCTUnwrap(owner.subviews.compactMap { $0 as? PKCanvasView }.last)
            let viewport = try XCTUnwrap(descendants(window).compactMap { $0 as? LeadSheetDocumentViewport }.first)
            XCTAssertFalse(ink.isHidden)
            XCTAssertFalse(owner.recognizesChordInk, "This boundary test must not invoke a recognizer.")
            let initialFrame = ink.frame
            let initialDocumentBounds = owner.bounds
            let counts = [3, 7, 13, 24]
            var priorDrawing = PKDrawing()
            var records: [[String: String]] = []
            for count in counts {
                let nextDrawing = drawing(count: count)
                owner.canvasViewDidBeginUsingTool(ink)
                let delegate = ink.delegate
                ink.delegate = nil
                ink.drawing = nextDrawing
                ink.delegate = delegate
                owner.canvasViewDrawingDidChange(ink)

                // A source save/preview result can publish while subsequent
                // Pencil input is resident. Keep the older archive in the echo.
                model.chart.pageHandwrittenChordData = priorDrawing.strokes.isEmpty ? nil : priorDrawing.dataRepresentation()
                model.chart.updatedAt = model.chart.updatedAt.addingTimeInterval(1)
                model.preview = state(chart: chart, drawing: nextDrawing, pageSize: owner.bounds.size)
                await settle(window)
                owner.canvasViewDidEndUsingTool(ink)
                await settle(window)

                XCTAssertEqual(ink.drawing.dataRepresentation(), nextDrawing.dataRepresentation(),
                    "A stale model/preview echo must not replace growing live chord ink (\(count) strokes).")
                XCTAssertEqual(ink.drawing.strokes.count, count)
                XCTAssertFalse(ink.isHidden)
                XCTAssertEqual(ink.alpha, 1)
                XCTAssertNotNil(ink.window)
                XCTAssertEqual(ink.frame, initialFrame)
                XCTAssertEqual(owner.bounds, initialDocumentBounds)
                XCTAssertFalse(owner.layer.shouldRasterize)
                XCTAssertFalse(viewport.layer.shouldRasterize)
                XCTAssertFalse(viewport.documentContainerView.layer.shouldRasterize)
                records += ancestorRecords(of: ink).map {
                    var result = $0
                    result["strokeCount"] = String(count)
                    result["darkAppearance"] = String(darkAppearance)
                    return result
                }
                priorDrawing = nextDrawing
            }
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: records,
                options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "Synthetic progressive ink ancestor compositing - \(darkAppearance ? "dark" : "light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func drawing(count: Int) -> PKDrawing {
        PKDrawing(strokes: (0..<count).map { index in
            let origin = CGPoint(x: 12 + CGFloat(index % 12) * 28, y: 10 + CGFloat(index / 12) * 30)
            let points = [origin, CGPoint(x: origin.x + 7, y: origin.y + 12), CGPoint(x: origin.x + 14, y: origin.y)]
                .enumerated().map { offset, point in
                    PKStrokePoint(location: point, timeOffset: Double(offset) * 0.02,
                        size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(index))),
                transform: .identity, mask: nil, randomSeed: UInt32(100 + index))
        })
    }

    private func state(chart: Chart, drawing: PKDrawing, pageSize: CGSize) -> ChordPreviewState {
        let drafts = drawing.strokes.enumerated().map { index, stroke in
            ChordInkDraft(input: ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: Double(index + 1) / Double(drawing.strokes.count + 1), layoutPageSize: pageSize,
                drawingData: PKDrawing(strokes: [stroke]).dataRepresentation(), candidateTexts: ["C"],
                bestCandidateText: "C", confidence: 4, strokeCount: 1))
        }
        return ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
    }

    private func ancestorRecords(of view: UIView) -> [[String: String]] {
        var records: [[String: String]] = []
        var current: UIView? = view
        while let next = current {
            records.append(["class": String(describing: type(of: next)),
                "shouldRasterize": String(next.layer.shouldRasterize),
                "rasterizationScale": String(describing: next.layer.rasterizationScale),
                "contentsScale": String(describing: next.layer.contentsScale),
                "hidden": String(next.isHidden), "alpha": String(describing: next.alpha)])
            current = next.superview
        }
        return records
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func settle(_ window: UIWindow) async {
        for _ in 0..<3 {
            window.layoutIfNeeded()
            window.rootViewController?.view.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

@MainActor
private final class ProgressiveInkBoundaryModel: ObservableObject {
    @Published var chart: Chart
    @Published var preview = ChordPreviewState()
    init(_ chart: Chart) { self.chart = chart }
}

@MainActor
private struct ProgressiveInkBoundaryHarness: View {
    @ObservedObject var model: ProgressiveInkBoundaryModel
    let darkAppearance: Bool
    var body: some View {
        LeadSheetCanvasHostView(chart: $model.chart,
            selectedMeasureID: .constant(nil), selectedNoteSelection: .constant(nil),
            selectedChordID: .constant(nil), selectedCommittedBarlineMeasureID: .constant(nil),
            selectedCueTextID: .constant(nil), selectedRoadmapMarkerID: .constant(nil),
            interactionMode: .chordEntry, inkToolMode: .write,
            documentSize: CGSize(width: 932, height: 1_400), recognizesChordInk: false,
            chordPreviewState: model.preview)
            .ichartDocumentDisplayAppearance(isDark: darkAppearance)
    }
}
#endif

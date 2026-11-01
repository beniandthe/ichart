#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Synthetic native form rendering. Saved user charts never enter this test.
@MainActor
final class ChordDraftEndingReviewVisualTests: XCTestCase {
    func testNativeReviewShowsCustomLabelAndCorrectableMeasureRange() async throws {
        var chart = Chart.blank(title: "Synthetic ending review", measureCount: 4, layoutStyle: .simpleChordSheet)
        let pageSize = CGSize(width: 900, height: 1400)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system,
            paperFrame: layout.paperFrame(for: system)))
        let first = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(system.measures[1], in: system,
            paperFrame: layout.paperFrame(for: system), layoutStyle: chart.layoutStyle)
        let last = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(system.measures[2], in: system,
            paperFrame: layout.paperFrame(for: system), layoutStyle: chart.layoutStyle)
        let left = first.frame.minX + 1 - frame.minX
        let right = last.frame.maxX - 1 - frame.minX
        let top = lane.minY + lane.height * 0.1 - frame.minY
        let hook = lane.height * 0.22
        let source = PKDrawing(strokes: [stroke([
            CGPoint(x: left, y: top + hook), CGPoint(x: left, y: top),
            CGPoint(x: right, y: top), CGPoint(x: right, y: top + hook)
        ])])
        _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation())
        let stored = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.repeatAwareVisibleDrawingContext(
            from: stored, chordFrame: frame, pageLayout: layout)
        let detected = ChordDraftEndingRecognizer.recognize(
            strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing), chordFrame: frame, pageLayout: layout)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftEndings(with: context.remappedEndingRecognition(
            context.endingRecognitionWithUnambiguousSourceStrokes(detected)).endings)
        XCTAssertEqual(state.draftEndings.count, 1)
        let initial = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        XCTAssertEqual(initial.measureRange, 2...3)
        XCTAssertEqual(initial.availableMeasureCount, 4)
        let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(
            for: initial, chart: chart, currentState: state, label: "1–3, 5", endStyle: .open,
            measureRange: 2...3))
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(
            for: chart, state: reviewed, endingID: initial.endingID, continuesRendering: false))
        let originalChart = chart
        var didApply = false
        var didCancel = false
        let sheet = ChordDraftEndingReviewSheet(request: request,
            onApply: { _, _, _ in didApply = true }, onCancel: { didCancel = true })
        let host = UIHostingController(rootView: sheet)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1180)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextField }
            .first { $0.placeholder == "Ending label" })
        XCTAssertEqual(field.text, "1–3, 5")
        XCTAssertFalse(field.isFirstResponder, "Opening review should leave all measure controls visible without a keyboard")
        let nodes = try NativeAccessibilityLookup.nodes(in: window)
        XCTAssertTrue(nodes.contains { ($0.element.accessibilityLabel ?? "").contains("Start measure") })
        XCTAssertTrue(nodes.contains { ($0.element.accessibilityLabel ?? "").contains("End measure") })
        let apply = try XCTUnwrap((descendants(window).compactMap { $0 as? PencilOnlyUIButton }
            + nodes.compactMap { $0.element as? PencilOnlyUIButton }).first {
                $0.accessibilityLabel == "Use Ending" || $0.configuration?.title == "Use Ending"
            })
        XCTAssertTrue(apply.isEnabled)
        XCTAssertTrue(apply.acceptsDirectTouches)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let png = try XCTUnwrap(image.pngData())
        XCTAssertEqual(image.size, CGSize(width: 820, height: 1180))
        XCTAssertGreaterThan(png.count, 5_000)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Synthetic ending review — custom label and measures 2–3"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let output = environment("ICHART_ENDING_REVIEW_QA_OUTPUT") {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("ending-review-custom-label-measures-2-3.png"))
        }
        XCTAssertFalse(didApply)
        XCTAssertFalse(didCancel)
        XCTAssertEqual(chart, originalChart)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func environment(_ key: String) -> String? {
        let values = ProcessInfo.processInfo.environment
        return values[key] ?? values["TEST_RUNNER_\(key)"]
    }

    private func stroke(_ points: [CGPoint]) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints:
            points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000)),
            transform: .identity, mask: nil, randomSeed: 37)
    }
}
#endif

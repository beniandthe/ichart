#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class RepeatPreviewFeedbackTests: XCTestCase {
    func testSourceHighlightFollowsWobblyBarsAndOffCanonicalDotsInEveryDirection() throws {
        let origin = CGPoint(x: 120, y: 200)
        for kind in [DraftBarlineKind.repeatStart, .repeatEnd, .repeatBoth] {
            let sign = sourceSign(kind: kind)
            let points = sign.sourceStrokeGeometry.flatMap(\.points)
            let minX = try XCTUnwrap(points.map(\.x).min())
            let maxX = try XCTUnwrap(points.map(\.x).max())
            let minY = try XCTUnwrap(points.map(\.y).min())
            let maxY = try XCTUnwrap(points.map(\.y).max())
            let expected = CGRect(x: minX + Double(origin.x) - 4, y: minY + Double(origin.y) - 4,
                width: maxX - minX + 8, height: maxY - minY + 8)
            let frame = try XCTUnwrap(ChordDraftBarlinePreviewDrawing.sourceHighlightFrame(for: sign, sourceOrigin: origin))

            XCTAssertEqual(frame, expected, kind.rawValue)
            XCTAssertEqual(frame.minY, 206, accuracy: 0.001)
            XCTAssertEqual(frame.maxY, 264, accuracy: 0.001)
            for point in points {
                XCTAssertTrue(frame.contains(CGPoint(x: point.x + Double(origin.x), y: point.y + Double(origin.y))), kind.rawValue)
            }
            XCTAssertNotEqual(frame.midX, origin.x + 44,
                "The feedback must follow the owned bars and off-center dots instead of placing a second idealized glyph at its anchor.")
        }
    }

    func testMissingAndNonfiniteSourceCannotProduceAnInventedHighlight() throws {
        var sign = sourceSign(kind: .repeatEnd)
        sign.sourceStrokeGeometry = []
        XCTAssertNil(ChordDraftBarlinePreviewDrawing.sourceHighlightFrame(for: sign, sourceOrigin: .zero))
        sign.sourceStrokeGeometry = [InkStroke(points: [
            InkPoint(x: .nan, y: 12), InkPoint(x: 14, y: .infinity)
        ])]
        XCTAssertNil(ChordDraftBarlinePreviewDrawing.sourceHighlightFrame(for: sign, sourceOrigin: .zero))
        sign.sourceStrokeGeometry.append(InkStroke(points: [InkPoint(x: 18, y: 24), InkPoint(x: 22, y: 31)]))
        XCTAssertNil(ChordDraftBarlinePreviewDrawing.sourceHighlightFrame(for: sign, sourceOrigin: CGPoint(x: 10, y: 20)),
            "A partly corrupt group must not receive a misleading partial source outline.")
        sign.sourceStrokeGeometry = [InkStroke(points: [InkPoint(x: 18, y: 24), InkPoint(x: 22, y: 31)])]
        XCTAssertNil(ChordDraftBarlinePreviewDrawing.sourceHighlightFrame(for: sign, sourceOrigin: CGPoint(x: CGFloat.infinity, y: 20)))
        XCTAssertEqual(ChordDraftBarlinePreviewDrawing.sourceHighlightFrame(for: sign, sourceOrigin: CGPoint(x: 10, y: 20)),
            CGRect(x: 24, y: 40, width: 12, height: 15))
    }

    func testSourceFeedbackDrawsOnlyAnOuterBoundaryWithoutDuplicatedBarsOrDots() throws {
        let sign = sourceSign(kind: .repeatBoth)
        let origin = CGPoint(x: 12, y: 12)
        let frame = try XCTUnwrap(ChordDraftBarlinePreviewDrawing.sourceHighlightFrame(for: sign, sourceOrigin: origin))
        let image = image(size: CGSize(width: 110, height: 100)) {
            ChordDraftBarlinePreviewDrawing.drawSourceHighlight(sign, sourceOrigin: origin, color: .black, selected: false)
        }
        let pixels = try Raster(image)
        XCTAssertGreaterThan(pixels.darkCount(in: frame.insetBy(dx: -2, dy: -2)), 0)
        XCTAssertEqual(pixels.darkCount(in: frame.insetBy(dx: 7, dy: 7)), 0,
            "A selected repeat is one source-bound rectangle. Canonical bars and dot pairs must not be added over its retained ink.")
        attach(image, named: "repeat-source-feedback-boundary")
    }

    func testToolbarSymbolsHaveCorrectDotSidesAndFitTheirNativeFrames() throws {
        for kind in [DraftBarlineKind.single, .repeatStart, .repeatEnd, .repeatBoth] {
            let symbol = ChordDiagnosticBarlineSymbol(kind: kind)
                .foregroundStyle(Color.black)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: symbol)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage, kind.rawValue)
            XCTAssertEqual(image.size.width, kind == .single ? 16 : (kind == .repeatBoth ? 40 : 30), accuracy: 0.001)
            XCTAssertEqual(image.size.height, 28, accuracy: 0.001)
            let pixels = try Raster(image)
            let barColumns = (0..<pixels.width).filter { x in pixels.darkCount(inColumn: x) >= pixels.height / 2 }
            let firstBar = try XCTUnwrap(barColumns.first, kind.rawValue)
            let lastBar = try XCTUnwrap(barColumns.last, kind.rawValue)
            let leftDots = pixels.darkCount(in: CGRect(x: 0, y: 0, width: max(0, firstBar - 1), height: pixels.height))
            let rightDots = pixels.darkCount(in: CGRect(x: lastBar + 2, y: 0,
                width: max(0, pixels.width - lastBar - 2), height: pixels.height))
            XCTAssertEqual(leftDots > 0, kind.endsRepeat, kind.rawValue)
            XCTAssertEqual(rightDots > 0, kind.startsRepeat, kind.rawValue)
            XCTAssertEqual(pixels.darkCount(in: CGRect(x: 0, y: 0, width: pixels.width, height: 1)), 0)
            XCTAssertEqual(pixels.darkCount(in: CGRect(x: 0, y: pixels.height - 1, width: pixels.width, height: 1)), 0)
            XCTAssertEqual(pixels.darkCount(inColumn: 0), 0)
            XCTAssertEqual(pixels.darkCount(inColumn: pixels.width - 1), 0)
            attach(image, named: "toolbar-symbol-\(kind.rawValue)")
        }
    }

    func testPreviewStripKeepsAllSymbolWidthsUnderTheToolbarViewportProposal() throws {
        let kinds: [DraftBarlineKind] = [.single, .repeatStart, .repeatEnd, .repeatBoth,
            .single, .repeatStart, .repeatEnd, .repeatBoth]
        let items = kinds.enumerated().map { index, kind in
            ChordDiagnosticPreviewItem(id: "sign-\(index)", visualOrder: Double(index), kind: .barline(kind))
        }
        let renderer = ImageRenderer(content: ChordDiagnosticPreviewStripContent(items: items)
            .foregroundStyle(Color.black).background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: ChordDiagnosticPreviewMetrics.stripWidth, height: 42)
        let rendered = try XCTUnwrap(renderer.uiImage)
        let expectedWidth = CGFloat(2 * (16 + 30 + 30 + 40))
            + CGFloat(kinds.count - 1) * ChordDiagnosticPreviewMetrics.itemSpacing
            + 2 * ChordDiagnosticPreviewMetrics.horizontalInset
        XCTAssertEqual(rendered.size.width, expectedWidth, accuracy: 0.001,
            "Scroll content must retain the native symbol frames instead of compressing marks into the viewport.")
        XCTAssertGreaterThan(rendered.size.width, ChordDiagnosticPreviewMetrics.stripWidth)
        attach(rendered, named: "repeat-preview-strip-natural-width")
    }

    func testChordOrderingUsesTheSameLaneCoordinatesAsRepeatSigns() {
        var input = ChordInkDraftInput(measureID: UUID(), measureIndex: 9, targetFraction: 0.85,
            visualOrder: 8.85, laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.3),
            drawingData: Data(), candidateTexts: ["C"], bestCandidateText: "C", confidence: 4, strokeCount: 1)
        let laneDraft = ChordInkDraft(input: input)
        XCTAssertEqual(ChordDiagnosticPreviewOrderPolicy.visualOrder(for: laneDraft), 1.3, accuracy: 0.001,
            "A chord in the second visual lane must stay between repeat signs in that lane, regardless of its stored measure index.")
        input.laneLocation = nil
        XCTAssertEqual(ChordDiagnosticPreviewOrderPolicy.visualOrder(for: ChordInkDraft(input: input)), 8.85, accuracy: 0.001)
        input.visualOrder = nil
        XCTAssertEqual(ChordDiagnosticPreviewOrderPolicy.visualOrder(for: ChordInkDraft(input: input)), 9.85, accuracy: 0.001)
    }

    func testRepeatHitTargetsFollowTranslatedBarsAndAllFourSourceOutlineEdges() throws {
        let laneFrame = CGRect(x: 100, y: 200, width: 300, height: 80)
        let origin = CGPoint(x: 120, y: 200)
        for kind in [DraftBarlineKind.repeatStart, .repeatEnd, .repeatBoth] {
            let sign = sourceSign(kind: kind)
            let outline = try XCTUnwrap(ChordDraftBarlinePreviewDrawing.sourceHighlightFrame(for: sign, sourceOrigin: origin))
            let selection = ChordDraftBarlineOverlayGeometry.selectionFrame(for: sign, in: laneFrame, sourceOrigin: origin)
            XCTAssertEqual(selection, outline.insetBy(dx: -3, dy: -3), kind.rawValue)
            let oldSelection = ChordDraftBarlineOverlayGeometry.lineFrame(for: sign, in: laneFrame).insetBy(dx: 3, dy: 8)
            let outlinePoints = [
                CGPoint(x: outline.minX, y: outline.midY), CGPoint(x: outline.maxX, y: outline.midY),
                CGPoint(x: outline.midX, y: outline.minY), CGPoint(x: outline.midX, y: outline.maxY)
            ]
            let drawnBarPoints = sign.sourceStrokeGeometry.prefix(2).flatMap(\.points).map {
                CGPoint(x: CGFloat($0.x) + origin.x, y: CGFloat($0.y) + origin.y)
            }
            for point in outlinePoints + drawnBarPoints {
                XCTAssertFalse(oldSelection.contains(point), "The fixture must exercise source geometry beyond the old narrow canonical line.")
                XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
                    at: point, barlines: [sign], laneFrameForBarline: { _ in laneFrame },
                    selectedBarlineID: nil, sourceOrigin: origin),
                    ChordDraftBarlineHitTarget(barlineID: sign.id, action: .select), kind.rawValue)
                XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
                    at: point, barlines: [sign], laneFrameForBarline: { _ in laneFrame },
                    selectedBarlineID: sign.id, sourceOrigin: origin),
                    ChordDraftBarlineHitTarget(barlineID: sign.id, action: .delete), kind.rawValue)
            }
        }
    }

    func testSourceHitTargetRejectsNearbyChordSpaceAndTheUnusedCanonicalAnchor() {
        let sign = sourceSign(kind: .repeatBoth)
        let laneFrame = CGRect(x: 100, y: 200, width: 300, height: 80)
        let origin = CGPoint(x: 120, y: 200)
        let selection = ChordDraftBarlineOverlayGeometry.selectionFrame(for: sign, in: laneFrame, sourceOrigin: origin)
        let canonical = ChordDraftBarlineOverlayGeometry.lineFrame(for: sign, in: laneFrame)
        let outsidePoints = [
            CGPoint(x: selection.minX - 1, y: selection.midY),
            CGPoint(x: selection.maxX + 1, y: selection.midY),
            CGPoint(x: selection.midX, y: selection.minY - 1),
            CGPoint(x: selection.midX, y: selection.maxY + 1),
            CGPoint(x: canonical.midX, y: canonical.midY)
        ]
        for point in outsidePoints {
            XCTAssertNil(ChordDraftBarlineOverlayGeometry.hitTarget(
                at: point, barlines: [sign], laneFrameForBarline: { _ in laneFrame },
                selectedBarlineID: nil, sourceOrigin: origin),
                "A source-bound repeat must not intercept nearby chord space or retain an invisible canonical hit line.")
        }
    }

    func testSelectedRepeatDeleteControlWinsOverAnotherSourceBodyAtTheSamePoint() {
        let selected = sourceSign(kind: .repeatEnd)
        let laneFrame = CGRect(x: 100, y: 200, width: 300, height: 80)
        let origin = CGPoint(x: 120, y: 200)
        let control = ChordDraftBarlineOverlayGeometry.controlFrames(for: selected, in: laneFrame).delete
        let point = CGPoint(x: control.midX, y: control.midY)
        var overlapping = sourceSign(kind: .repeatStart)
        overlapping.sourceStrokeGeometry = [stroke([
            (Double(point.x - origin.x - 6), Double(point.y - origin.y - 6)),
            (Double(point.x - origin.x + 6), Double(point.y - origin.y + 6))
        ])]
        XCTAssertTrue(ChordDraftBarlineOverlayGeometry.selectionFrame(
            for: overlapping, in: laneFrame, sourceOrigin: origin).contains(point))
        XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
            at: point, barlines: [selected, overlapping], laneFrameForBarline: { _ in laneFrame },
            selectedBarlineID: selected.id, sourceOrigin: origin),
            ChordDraftBarlineHitTarget(barlineID: selected.id, action: .delete))
        XCTAssertNil(ChordDraftBarlineOverlayGeometry.hitTarget(
            at: point, barlines: [selected], laneFrameForBarline: { _ in laneFrame },
            selectedBarlineID: nil, sourceOrigin: origin), "An unselected sign has no active delete control.")
    }

    func testSingleBarlineAndUnavailableSourceKeepLegacySelectionGeometry() {
        let laneFrame = CGRect(x: 100, y: 200, width: 300, height: 80)
        let origin = CGPoint(x: 120, y: 200)
        var single = sourceSign(kind: .repeatBoth)
        single.kind = .single
        var missingSource = sourceSign(kind: .repeatEnd)
        missingSource.sourceStrokeGeometry = []
        let sourceWithoutOrigin = sourceSign(kind: .repeatStart)
        let cases: [(DraftBarline, CGPoint?)] = [(single, origin), (missingSource, origin), (sourceWithoutOrigin, nil)]
        for (sign, sourceOrigin) in cases {
            let legacy = ChordDraftBarlineOverlayGeometry.lineFrame(for: sign, in: laneFrame).insetBy(dx: 3, dy: 8)
            XCTAssertEqual(ChordDraftBarlineOverlayGeometry.selectionFrame(for: sign, in: laneFrame, sourceOrigin: sourceOrigin), legacy)
            let point = CGPoint(x: legacy.midX, y: legacy.midY)
            XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
                at: point, barlines: [sign], laneFrameForBarline: { _ in laneFrame },
                selectedBarlineID: nil, sourceOrigin: sourceOrigin),
                ChordDraftBarlineHitTarget(barlineID: sign.id, action: .select))
            XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
                at: point, barlines: [sign], laneFrameForBarline: { _ in laneFrame },
                selectedBarlineID: sign.id, sourceOrigin: sourceOrigin),
                ChordDraftBarlineHitTarget(barlineID: sign.id, action: .delete))
        }
        let defaultPoint = ChordDraftBarlineOverlayGeometry.lineFrame(for: single, in: laneFrame)
        XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: defaultPoint.midX, y: defaultPoint.midY), barlines: [single],
            laneFrameForBarline: { _ in laneFrame }, selectedBarlineID: nil),
            ChordDraftBarlineHitTarget(barlineID: single.id, action: .select),
            "Callers that omit the new trailing source origin must keep the legacy API behavior.")
    }

    private func sourceSign(kind: DraftBarlineKind) -> DraftBarline {
        var geometry = [
            stroke([(44, 10), (41, 30), (43, 60)]),
            stroke([(49, 12), (51, 40), (48, 58)])
        ]
        if kind.endsRepeat {
            geometry.append(stroke([(27, 22), (28, 23)]))
            geometry.append(stroke([(25, 48), (26, 49)]))
        }
        if kind.startsRepeat {
            geometry.append(stroke([(69, 27), (68, 28)]))
            geometry.append(stroke([(72, 51), (71, 52)]))
        }
        return DraftBarline(measureID: UUID(), measureIndex: 1, fraction: 0.5,
            sourceStrokeIndex: 0,
            metrics: DraftBarlineGestureMetrics(height: 50, width: 10, angleDegreesFromVertical: 3,
                straightness: 0.96, laneCoverage: 0.85), kind: kind,
            sourceStrokeIndices: Set(geometry.indices), sourceStrokeGeometry: geometry)
    }

    private func stroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(points: points.enumerated().map { index, point in
            InkPoint(x: point.0, y: point.1, timeOffset: Double(index) * 0.05)
        })
    }

    private func image(size: CGSize, drawing: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            drawing()
        }
    }

    private func attach(_ image: UIImage, named name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Raster {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        init(_ image: UIImage) throws {
            let source = try XCTUnwrap(image.cgImage)
            let rasterWidth = source.width
            let rasterHeight = source.height
            var bytes = [UInt8](repeating: 255, count: rasterWidth * rasterHeight)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: rasterWidth, height: rasterHeight,
                    bitsPerComponent: 8, bytesPerRow: rasterWidth, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue))
                context.draw(source, in: CGRect(x: 0, y: 0, width: rasterWidth, height: rasterHeight))
            }
            width = rasterWidth
            height = rasterHeight
            pixels = bytes
        }

        func darkCount(inColumn column: Int) -> Int {
            (0..<height).reduce(0) { $0 + (pixels[$1 * width + column] < 150 ? 1 : 0) }
        }

        func darkCount(in frame: CGRect) -> Int {
            let x0 = max(0, min(width, Int(floor(frame.minX))))
            let x1 = max(x0, min(width, Int(ceil(frame.maxX))))
            let y0 = max(0, min(height, Int(floor(frame.minY))))
            let y1 = max(y0, min(height, Int(ceil(frame.maxY))))
            return (y0..<y1).reduce(0) { total, y in
                total + (x0..<x1).filter { pixels[y * width + $0] < 150 }.count
            }
        }
    }
}
#endif

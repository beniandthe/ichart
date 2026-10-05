#if canImport(UIKit)
import CoreText
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class HeaderRenderingGeometryTests: XCTestCase {
    @MainActor
    func testHeaderFontFittingKeepsCompleteLongAndUnbrokenTitlesVisible() {
        let titles = [
            "A Complete Long Title For The Evening Performance With The Final Words Still Visible",
            String(repeating: "WideTitle", count: 12),
            "First title line\nSecond title line with the complete ending"
        ]
        for size in [CGSize(width: 420, height: 36), CGSize(width: 724, height: 54)] {
            for title in titles {
                let preferredFont = UIFont.systemFont(ofSize: 38, weight: .semibold)
                let font = LeadSheetHeaderTextFittingPolicy.fittedFont(
                    for: title,
                    in: size,
                    font: preferredFont,
                    alignment: .center
                )
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byWordWrapping
                let text = NSAttributedString(string: title, attributes: [
                    .font: font,
                    .paragraphStyle: paragraph
                ])
                let framesetter = CTFramesetterCreateWithAttributedString(text)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: 0, length: text.length),
                    CGPath(rect: CGRect(origin: .zero, size: size), transform: nil),
                    nil
                )
                let visibleRange = CTFrameGetVisibleStringRange(frame)

                XCTAssertLessThanOrEqual(font.pointSize, preferredFont.pointSize)
                XCTAssertGreaterThan(font.pointSize, 0)
                XCTAssertGreaterThanOrEqual(font.pointSize, 12, "Ordinary long titles should remain readable.")
                XCTAssertEqual(visibleRange.location, 0)
                XCTAssertEqual(visibleRange.length, text.length, "Missing title ending: \(title)")
            }
        }
    }

    @MainActor
    func testHeaderFontFittingPreservesPreferredFontForShortTitle() {
        let preferredFont = UIFont.systemFont(ofSize: 24, weight: .bold)
        let font = LeadSheetHeaderTextFittingPolicy.fittedFont(
            for: "Night Train",
            in: CGSize(width: 724, height: 36),
            font: preferredFont,
            alignment: .center
        )
        XCTAssertEqual(font, preferredFont)
    }

    @MainActor
    func testHeaderFontFittingHandlesInvalidAndExtremeFrames() {
        let preferredFont = UIFont.systemFont(ofSize: 38, weight: .semibold)
        for size in [
            CGSize(width: 0, height: 36),
            CGSize(width: 0.5, height: 0.5),
            CGSize(width: CGFloat.infinity, height: 36),
            CGSize(width: 724, height: CGFloat.nan)
        ] {
            XCTAssertEqual(LeadSheetHeaderTextFittingPolicy.fittedFont(
                for: "A complete title",
                in: size,
                font: preferredFont
            ), preferredFont)
        }
        let font = LeadSheetHeaderTextFittingPolicy.fittedFont(
            for: String(repeating: "VeryLongTitle", count: 200),
            in: CGSize(width: 1, height: 1),
            font: preferredFont
        )
        XCTAssertTrue(font.pointSize.isFinite)
        XCTAssertGreaterThan(font.pointSize, 0)
        XCTAssertLessThanOrEqual(font.pointSize, preferredFont.pointSize)
    }

    @MainActor
    func testLongTypedHeaderIsCompleteInCanvasRendererAndPDFExport() async throws {
        let title = "The Complete Long Performance Title With The Full Band Name And An Unmistakable Final Ending"
        let composer = "A Complete Composer And Arranger Credit With Its Final Ending"
        let styleNote = "A Complete Performance Style Note With Its Final Ending"
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet, .leadSheet] {
            var chart = Chart.blank(title: title, measureCount: 4, layoutStyle: layoutStyle)
            chart.composerCredit = composer
            chart.styleNote = styleNote
            let expectedTitle = layoutStyle == .simpleChordSheet ? title : title.uppercased()

            for width in [CGFloat(772), 932] {
                let layout = LeadSheetPageLayoutEngine.pageLayout(
                    for: chart,
                    pageSize: CGSize(width: width, height: 1_100)
                )
                let previewData = UIGraphicsPDFRenderer(bounds: layout.pageBounds).pdfData { context in
                    context.beginPage()
                    LeadSheetNotationRenderer(chart: chart).drawHeader(layout.header)
                }
                let previewText = normalizedPDFText(try XCTUnwrap(PDFDocument(data: previewData)?.string))
                XCTAssertTrue(previewText.contains(expectedTitle), "Canvas header omitted title ending: \(previewText)")
                XCTAssertTrue(previewText.contains(composer), "Canvas header omitted credit ending: \(previewText)")
                XCTAssertTrue(previewText.contains(styleNote), "Canvas header omitted style ending: \(previewText)")
                try saveHeaderPreviewIfRequested(chart: chart, layout: layout, width: width, pdfData: previewData)
            }

            let export = try await PDFChartExporter(exportDirectory: exportDirectory).exportPDF(for: chart)
            let exportedText = normalizedPDFText(try XCTUnwrap(PDFDocument(url: export.url)?.string))
            XCTAssertTrue(exportedText.contains(expectedTitle), "PDF omitted title ending: \(exportedText)")
            XCTAssertTrue(exportedText.contains(composer), "PDF omitted credit ending: \(exportedText)")
            XCTAssertTrue(exportedText.contains(styleNote), "PDF omitted style ending: \(exportedText)")
            XCTAssertEqual(chart.title, title)
            XCTAssertEqual(chart.composerCredit, composer)
            XCTAssertEqual(chart.styleNote, styleNote)
        }
    }

    @MainActor
    func testWholeHeaderAuthoringBoxHasMatchingSavedAndPDFEdgeCoverage() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory) }

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for sourceKind in ["current", "storedCoordinateSpace", "legacyWithoutCoordinateSpace"] {
                var chart = Chart.blank(title: "Header Edge Coverage", measureCount: 4, layoutStyle: layoutStyle)
                chart.headerInputMode = .handwritten
                let targetLayout = LeadSheetPageLayoutEngine.pageLayout(
                    for: chart,
                    pageSize: CGSize(width: 932, height: 1_100)
                )
                let targetFrame = targetLayout.header.handwrittenFrame
                let sourceSize: CGSize
                if sourceKind == "storedCoordinateSpace" {
                    sourceSize = LeadSheetPageLayoutEngine.pageLayout(
                        for: chart,
                        pageSize: CGSize(width: 1_180, height: 1_100)
                    ).header.handwrittenFrame.size
                } else {
                    sourceSize = targetFrame.size
                }
                let sourceCoordinateSpace = sourceKind == "legacyWithoutCoordinateSpace"
                    ? nil : PersistentInkCoordinateSpace(size: sourceSize)
                let endpoint = CGPoint(x: sourceSize.width - 6, y: sourceSize.height - 8)
                let drawing = headerDrawing(endingAt: endpoint)
                let drawingData = drawing.dataRepresentation()
                chart.pageHandwrittenHeaderData = drawingData
                chart.pageHandwrittenHeaderCoordinateSpace = sourceCoordinateSpace

                let scope = try XCTUnwrap(LeadSheetActiveInkScope.resolve(
                    interactionMode: .headerEntry,
                    chartLayoutStyle: layoutStyle,
                    selectedMeasureID: nil,
                    selectedMeasureLayout: nil,
                    pageLayout: targetLayout
                ))
                XCTAssertEqual(scope.frame, targetFrame)
                XCTAssertEqual(scope.localInputFrames, [CGRect(origin: .zero, size: targetFrame.size)])
                let targetCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.coordinateSpace(for: targetFrame)
                let projectedDrawing = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
                    from: drawingData,
                    sourceCoordinateSpace: sourceCoordinateSpace,
                    targetCoordinateSpace: targetCoordinateSpace
                ))
                let projectedEndpoint = CGPoint(
                    x: endpoint.x * targetFrame.width / sourceSize.width,
                    y: endpoint.y * targetFrame.height / sourceSize.height
                )
                let projectedStroke = try XCTUnwrap(projectedDrawing.strokes.first)
                let endpointInStroke = try XCTUnwrap(projectedStroke.path.last?.location)
                let actualEndpoint = endpointInStroke.applying(projectedStroke.transform)
                XCTAssertEqual(actualEndpoint.x, projectedEndpoint.x, accuracy: 0.001)
                XCTAssertEqual(actualEndpoint.y, projectedEndpoint.y, accuracy: 0.001)

                let savedImage = try XCTUnwrap(LeadSheetSavedInkRenderer.renderedInkImage(
                    drawingData,
                    size: targetFrame.size,
                    sourceCoordinateSpace: sourceCoordinateSpace,
                    scale: 1
                ))
                XCTAssertTrue(try containsDarkInk(savedImage, near: projectedEndpoint), sourceKind)
                let previewImage = image(size: targetLayout.pageBounds.size) {
                    LeadSheetSavedInkRenderer.drawHeaderInk(
                        drawingData,
                        coordinateSpace: sourceCoordinateSpace,
                        in: targetLayout
                    )
                }
                XCTAssertTrue(try containsDarkInk(previewImage, near: CGPoint(
                    x: targetFrame.minX + projectedEndpoint.x,
                    y: targetFrame.minY + projectedEndpoint.y
                )), sourceKind)

                let export = try await PDFChartExporter(exportDirectory: exportDirectory).exportPDF(for: chart)
                let pdfDocument = try XCTUnwrap(PDFDocument(url: export.url))
                let pdfPage = try XCTUnwrap(pdfDocument.page(at: 0))
                let pageImage = withExtendedLifetime(pdfDocument) {
                    image(size: targetLayout.paperFrame.size) {
                        let context = UIGraphicsGetCurrentContext()!
                        context.translateBy(x: 0, y: targetLayout.paperFrame.height)
                        context.scaleBy(x: 1, y: -1)
                        pdfPage.draw(with: .mediaBox, to: context)
                    }
                }
                XCTAssertTrue(try containsDarkInk(pageImage, near: CGPoint(
                    x: targetFrame.minX - targetLayout.paperFrame.minX + projectedEndpoint.x,
                    y: targetFrame.minY - targetLayout.paperFrame.minY + projectedEndpoint.y
                )), sourceKind)
                XCTAssertEqual(chart.pageHandwrittenHeaderData, drawingData)
                XCTAssertEqual(chart.pageHandwrittenHeaderCoordinateSpace, sourceCoordinateSpace)
            }
        }
    }

    private func normalizedPDFText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func saveHeaderPreviewIfRequested(
        chart: Chart,
        layout: LeadSheetPageLayout,
        width: CGFloat,
        pdfData: Data
    ) throws {
        guard let directory = ProcessInfo.processInfo.environment["ICHART_HEADER_QA_OUTPUT"],
              !directory.isEmpty else {
            return
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let headerFrame = layout.header.handwrittenFrame
        let preview = image(size: headerFrame.size) {
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: headerFrame.size)).fill()
            UIGraphicsGetCurrentContext()?.translateBy(x: -headerFrame.minX, y: -headerFrame.minY)
            LeadSheetNotationRenderer(chart: chart).drawHeader(layout.header)
        }
        let label = "header-\(chart.layoutStyle.rawValue)-\(Int(width))"
        try XCTUnwrap(preview.pngData()).write(to: output.appendingPathComponent(label + ".png"))
        try pdfData.write(to: output.appendingPathComponent(label + ".pdf"))
    }

    private func headerDrawing(endingAt point: CGPoint) -> PKDrawing {
        let locations = [
            CGPoint(x: 6, y: point.y),
            CGPoint(x: point.x - 12, y: point.y),
            point
        ]
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKDrawing(strokes: [PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 10))
        )])
    }

    private func image(size: CGSize, drawing: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in drawing() }
    }

    private func containsDarkInk(_ image: UIImage, near point: CGPoint) throws -> Bool {
        let cgImage = try XCTUnwrap(image.cgImage)
        let region = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            .applying(CGAffineTransform(scaleX: image.scale, y: image.scale))
            .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let croppedImage = try XCTUnwrap(cgImage.cropping(to: region))
        let width = croppedImage.width
        let height = croppedImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).contains { index in
            pixels[index + 3] > 20
                && pixels[index] < 80
                && pixels[index + 1] < 80
                && pixels[index + 2] < 80
        }
    }
}
#endif

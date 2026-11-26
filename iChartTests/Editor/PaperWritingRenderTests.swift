#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class PaperWritingRenderTests: XCTestCase {
    private let editorSize = CGSize(width: 1180, height: 1500)
    private let pdfSize = CGSize(width: 932, height: 1100)

    func testBlankPaperShowsWritingLanesWithoutGeneratedBarlinesInBothStyles() async throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Blank paper", layoutStyle: style)
            XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
            let layout = LeadSheetPageLayoutEngine.pageLayout(
                for: chart, pageSize: editorSize, includesChordInkContinuationLanes: true)
            let native = canvasImage(chart, mode: .chordEntry)
            attach(native, name: "blank-\(style.rawValue)-write-render")
            for row in layout.systems {
                try assertNoGeneratedBars(in: native, row: row, paper: layout.paperFrame(for: row))
            }
            let row = try XCTUnwrap(layout.systems.first)
            let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: row, paperFrame: layout.paperFrame(for: row)))
            XCTAssertGreaterThan(try bluePixelCount(native, in: lane), 50,
                "Write & Render must paint the blue writing lane")
            if style == .rhythmSectionSheet {
                try assertStaffVisible(in: native, row: row)
            }

            let proof = try await pdfProof(chart, label: "blank-\(style.rawValue)")
            try assertNoGeneratedBars(in: proof.image, row: proof.row, paper: proof.paper, offset: proof.offset)
            if style == .rhythmSectionSheet {
                try assertStaffVisible(in: proof.image, row: proof.row, offset: proof.offset)
            }
        }
    }

    func testTwoDoubleBarlinesProduceOneMeasureWithTwoDoubleEdgesInCanvasAndPDF() async throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "One double bounded measure", layoutStyle: style)
            XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.12, kind: .double))
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.48, kind: .double))
            XCTAssertTrue(chart.finishPaperWritingRows())
            XCTAssertEqual(chart.systems[0].measures.count, 1)
            XCTAssertEqual(chart.systems[0].measures[0].paperLayout?.leadingBarline, .double)
            XCTAssertEqual(chart.systems[0].measures[0].barlineAfter, .double)

            let reopened = try reopen(chart)
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: editorSize)
            let row = try XCTUnwrap(layout.systems.first)
            let measure = try XCTUnwrap(row.measures.first)
            let native = canvasImage(reopened)
            attach(native, name: "double-pair-\(style.rawValue)-select")
            try assertDoubleEdges(in: native, measure: measure)

            let proof = try await pdfProof(reopened, label: "double-pair-\(style.rawValue)")
            try assertDoubleEdges(in: proof.image, measure: try XCTUnwrap(proof.row.measures.first),
                offset: proof.offset)
        }
    }

    func testRightOnlyMeasureAndItsChordKeepPositionAfterFinishAndReopenInCanvasAndPDF() async throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Right end measure", layoutStyle: style)
            XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
            let id = try XCTUnwrap(chart.placePaperBarline(inRow: 0, at: 0.8, kind: .double))
            XCTAssertTrue(chart.appendRecognizedChord(try ChordSymbolParser.parse("C7"),
                rawInput: "C7", to: id, atFraction: 0.25))
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.98, kind: .double))
            XCTAssertTrue(chart.finishPaperWritingRows())
            let reopened = try reopen(chart)
            XCTAssertEqual(reopened.systems[0].measures.count, 1)
            XCTAssertEqual(reopened.systems[0].measures[0].chordEvents.map(\.rawInput), ["C7"])
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: editorSize)
            let row = try XCTUnwrap(layout.systems.first)
            let measure = try XCTUnwrap(row.measures.first)
            try assertRightEndPosition(row: row, measure: measure)
            let native = canvasImage(reopened)
            attach(native, name: "right-only-\(style.rawValue)-select")
            try assertDoubleEdges(in: native, measure: measure)
            let leadingBlank = CGRect(x: row.frame.minX + row.frame.width * 0.3,
                y: measure.staffFrame.minY + 3, width: 30, height: measure.staffFrame.height - 6)
            XCTAssertEqual(try verticalLineClusters(native, in: leadingBlank), 0)

            let proof = try await pdfProof(reopened, label: "right-only-\(style.rawValue)")
            let pdfMeasure = try XCTUnwrap(proof.row.measures.first)
            try assertRightEndPosition(row: proof.row, measure: pdfMeasure)
            try assertDoubleEdges(in: proof.image, measure: pdfMeasure, offset: proof.offset)
        }
    }

    func testPDFTrimsUnusedAuthoringRowsAndRetainsAnExplicitBoundaryOnTheLastRow() async throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Reserved writing rows", layoutStyle: style)
            XCTAssertTrue(chart.initializePaperWritingRows(count: 12))
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.1, kind: .double))
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.5, kind: .single))
            XCTAssertTrue(chart.finishPaperWritingRows())
            let original = chart
            XCTAssertGreaterThan(LeadSheetPageLayoutEngine.pageLayout(
                for: chart, pageSize: pdfSize).pages.count, 1)
            let first = try await pdfProof(chart, label: "trim-unused-\(style.rawValue)")
            XCTAssertEqual(first.pageCount, 1)
            XCTAssertEqual(chart, original)

            XCTAssertNotNil(chart.placePaperBarline(inRow: 11, at: 0.75, kind: .double))
            let withLastBoundary = chart
            let last = try await pdfProof(chart, label: "retain-last-boundary-\(style.rawValue)")
            XCTAssertGreaterThan(last.pageCount, 1)
            XCTAssertEqual(chart, withLastBoundary)
        }
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
    }

    private func assertRightEndPosition(row: LeadSheetSystemLayout, measure: LeadSheetMeasureLayout) throws {
        let axis = try XCTUnwrap(row.paperWritingFrame)
        XCTAssertEqual(measure.staffFrame.minX, axis.minX + axis.width * 0.8, accuracy: 0.01)
        XCTAssertEqual(measure.staffFrame.maxX, axis.minX + axis.width * 0.98, accuracy: 0.01)
        XCTAssertEqual(measure.chordLayouts.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(measure.chordLayouts.first).frame.minX, axis.minX + axis.width * 0.79)
    }

    private func assertNoGeneratedBars(in image: UIImage, row: LeadSheetSystemLayout,
        paper: CGRect, offset: CGPoint = .zero) throws {
        let measure = try XCTUnwrap(row.measures.first)
        let axis = try XCTUnwrap(row.paperWritingFrame)
        for x in [axis.minX, axis.maxX, row.frame.maxX, paper.maxX - 15] {
            let strip = CGRect(x: x + offset.x - 7, y: measure.staffFrame.minY + offset.y + 3,
                width: 14, height: measure.staffFrame.height - 6)
            XCTAssertEqual(try verticalLineClusters(image, in: strip), 0,
                "An empty authoring row must not paint a vertical bar at x \(x)")
        }
    }

    private func assertDoubleEdges(in image: UIImage, measure: LeadSheetMeasureLayout,
        offset: CGPoint = .zero) throws {
        for x in [measure.leadingBarlineX, measure.trailingBarlineFrame.midX] {
            let strip = CGRect(x: x + offset.x - 14, y: measure.staffFrame.minY + offset.y + 4,
                width: 28, height: measure.staffFrame.height - 8)
            XCTAssertEqual(try verticalLineClusters(image, in: strip), 2,
                "A double boundary must paint two distinct vertical rules")
        }
    }

    private func assertStaffVisible(in image: UIImage, row: LeadSheetSystemLayout,
        offset: CGPoint = .zero) throws {
        XCTAssertEqual(row.staffLineYPositions.count, 5)
        let axis = try XCTUnwrap(row.paperWritingFrame)
        for y in row.staffLineYPositions {
            let strip = CGRect(x: axis.midX + offset.x - 30, y: y + offset.y - 1, width: 60, height: 2)
            XCTAssertGreaterThan(try grayPixels(image, in: strip).filter { $0 < 100 }.count, 50,
                "Rhythm writing keeps its five staff lines visible")
        }
    }

    private func canvasImage(_ chart: Chart, mode: EditorCanvasMode = .browse) -> UIImage {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: editorSize))
        view.recognizesChordInk = false
        view.chart = chart
        view.interactionMode = mode
        view.overrideUserInterfaceStyle = .light
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: editorSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: editorSize))
            view.draw(view.bounds)
        }
    }

    private struct PDFProof {
        var image: UIImage
        var row: LeadSheetSystemLayout
        var paper: CGRect
        var offset: CGPoint
        var pageCount: Int
    }

    private func pdfProof(_ chart: Chart, label: String) async throws -> PDFProof {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exported = try await PDFChartExporter(exportDirectory: directory).exportPDF(for: chart)
        let bytes = try Data(contentsOf: exported.url)
        let document = try XCTUnwrap(PDFDocument(data: bytes))
        let page = try XCTUnwrap(document.page(at: 0))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pdfSize)
        let row = try XCTUnwrap(layout.systems.first)
        let paper = try XCTUnwrap(layout.pages.first)
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        attach(image, name: "\(label)-pdf")
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "\(label).pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
        return PDFProof(image: image, row: row, paper: paper.frame,
            offset: CGPoint(x: -paper.frame.minX, y: -paper.frame.minY), pageCount: document.pageCount)
    }

    private func grayPixels(_ image: UIImage, in region: CGRect) throws -> [UInt8] {
        let scaled = region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        let cropped = try XCTUnwrap(image.cgImage?.cropping(to: scaled))
        var pixels = [UInt8](repeating: 255, count: cropped.width * cropped.height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: cropped.width, height: cropped.height,
                bitsPerComponent: 8, bytesPerRow: cropped.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
            return true
        }
        XCTAssertTrue(drew)
        return pixels
    }

    private func verticalLineClusters(_ image: UIImage, in region: CGRect) throws -> Int {
        let scaled = region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        let pixels = try grayPixels(image, in: region)
        let width = Int(scaled.width)
        let height = Int(scaled.height)
        var clusters = 0
        var previousWasLine = false
        for x in 0..<width {
            let dark = (0..<height).filter { pixels[$0 * width + x] < 100 }.count
            let isLine = Double(dark) > Double(height) * 0.6
            if isLine && !previousWasLine { clusters += 1 }
            previousWasLine = isLine
        }
        return clusters
    }

    private func bluePixelCount(_ image: UIImage, in region: CGRect) throws -> Int {
        let scaled = region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        let cropped = try XCTUnwrap(image.cgImage?.cropping(to: scaled))
        var pixels = [UInt8](repeating: 255, count: cropped.width * cropped.height * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: cropped.width, height: cropped.height,
                bitsPerComponent: 8, bytesPerRow: cropped.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
            return true
        }
        XCTAssertTrue(drew)
        return stride(from: 0, to: pixels.count, by: 4).filter {
            Int(pixels[$0 + 2]) > Int(pixels[$0]) + 8
                && Int(pixels[$0 + 2]) > Int(pixels[$0 + 1]) + 3
        }.count
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif

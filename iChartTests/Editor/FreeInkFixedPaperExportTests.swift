#if canImport(UIKit) && canImport(PencilKit)
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Export the real PDF, then inspect a known mark in blank paper. A shared
/// policy helper alone cannot prove that the final PDF preserves its position.
@MainActor
final class FreeInkFixedPaperExportTests: XCTestCase {
    func testActualPDFKeepsSavedPaperSizeAndFarRightInkLocationAcrossAllStyles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = PDFChartExporter(exportDirectory: directory)

        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet, .leadSheet] {
            for width in [CGFloat(800), CGFloat(1_200)] {
                var chart = Chart.draft(title: "Fixed paper PDF \(Int(width))", layoutStyle: style)
                chart.completeInitialSetup(title: chart.title, key: .cMajor,
                    meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
                chart.stylePreset = .plainWhite
                // Capture the authored document before attaching any ink.
                let source = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                    pageSize: CGSize(width: width, height: 1_100))
                let paper = source.paperFrame
                let writing = LeadSheetActiveInkScope.pageWritingFrame(for: source)
                let markOrigin = CGPoint(x: writing.width - 70, y: writing.height - 100)
                let ink = marker(at: markOrigin)
                chart.pageHandwrittenNotationData = ink.dataRepresentation()
                chart.pageHandwrittenNotationCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                    for: source, relativeTo: writing)
                let sourceBytes = chart.pageHandwrittenNotationData
                let sourceSpace = chart.pageHandwrittenNotationCoordinateSpace

                let exported = try await exporter.exportPDF(for: chart)
                let document = try XCTUnwrap(PDFDocument(url: exported.url))
                XCTAssertEqual(document.pageCount, 1)
                let page = try XCTUnwrap(document.page(at: 0))
                let mediaBox = page.bounds(for: .mediaBox)
                let name = "\(style.rawValue), authored canvas \(Int(width))"
                XCTAssertEqual(mediaBox.width, paper.width, accuracy: 0.01, name)
                XCTAssertEqual(mediaBox.height, paper.height, accuracy: 0.01, name)

                // Convert raw source points to PDF paper-local coordinates.
                // This expectation never calls the ink reprojection policy.
                let expectedPoint = CGPoint(x: writing.minX - paper.minX + markOrigin.x,
                    y: writing.minY - paper.minY + markOrigin.y)
                let expectedROI = CGRect(x: expectedPoint.x - 10, y: expectedPoint.y - 10, width: 50, height: 50)
                let notationBottom = (source.systems.map(\.frame.maxY).max() ?? paper.minY) - paper.minY
                XCTAssertGreaterThan(expectedROI.minY, notationBottom + 100,
                    "The ink check must be in otherwise blank paper: \(name)")
                XCTAssertGreaterThanOrEqual(expectedROI.minX, 0)
                XCTAssertLessThanOrEqual(expectedROI.maxX, mediaBox.width)
                XCTAssertLessThanOrEqual(expectedROI.maxY, mediaBox.height)

                let image = render(page)
                XCTAssertGreaterThan(try darkPixelCount(in: image, rect: expectedROI), 100,
                    "The far-right mark moved or was clipped in the actual exported PDF: \(name)")
                XCTAssertLessThan(try darkPixelCount(in: image, rect: expectedROI.offsetBy(dx: -80, dy: 0)), 5,
                    "The adjacent blank-paper control must not contain notation or another mark: \(name)")
                XCTAssertEqual(chart.pageHandwrittenNotationData, sourceBytes)
                XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, sourceSpace)
            }
        }
    }

    private func marker(at origin: CGPoint) -> PKDrawing {
        let locations = [origin, CGPoint(x: origin.x + 28, y: origin.y),
            CGPoint(x: origin.x + 28, y: origin.y + 28), CGPoint(x: origin.x, y: origin.y + 28), origin]
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 6, height: 6), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 88)),
            transform: .identity, mask: nil, randomSeed: 88)])
    }

    private func render(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: bounds.size))
            renderer.cgContext.translateBy(x: 0, y: bounds.height)
            renderer.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: renderer.cgContext)
        }
    }

    private func darkPixelCount(in image: UIImage, rect: CGRect) throws -> Int {
        // Crop the actual rendered image first. Explicit RGBA decoding of that
        // small crop makes counting independent of bitmap row orientation.
        let fullImage = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(fullImage.cropping(to: rect.integral))
        let width = crop.width
        let height = crop.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            context.interpolationQuality = .none
            context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        XCTAssertTrue(drawn)
        return stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 80 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80 && pixels[$0 + 3] > 200
        }.count
    }
}
#endif

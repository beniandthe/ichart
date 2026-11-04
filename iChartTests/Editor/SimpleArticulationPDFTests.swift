#if canImport(UIKit) && canImport(PencilKit)
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class SimpleArticulationPDFTests: XCTestCase {
    func testActualPDFDrawsChordAttachedAndFloatingFermatasAndAccentsWithoutChangingSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = PDFChartExporter(exportDirectory: directory)
        var chart = Chart.blank(title: "Simple fermatas and accents", measureCount: 4, layoutStyle: .simpleChordSheet)
        chart.stylePreset = .plainWhite
        let measureID = chart.measures[0].id
        let chordIDs = try ["Cmaj7", "G7"].enumerated().map { index, text in
            try XCTUnwrap(chart.appendRecognizedChordEvent(
                try XCTUnwrap(ChordRecognitionCompendium.match(text)?.symbol), rawInput: text,
                to: measureID, atFraction: index == 0 ? 0.2 : 0.75))
        }
        let size = CGSize(width: LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth, height: 1_100)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let baseline = try await image(for: chart, exporter: exporter)
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 16, y: 8), CGPoint(x: 0, y: 16)]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 1))
        let archive = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
        for (kind, chordID) in zip([FreeInkArticulationKind.fermata, .accent], chordIDs) {
            let chord = try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
                .first { $0.id == chordID })
            let point = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(
                at: CGPoint(x: chord.frame.midX, y: chord.frame.minY - 12), pageLayout: layout))
            chart.freeInkArticulations.append(FreeInkArticulation(kind: kind, measureID: measureID,
                sourceInkData: archive, attachment: .chord(id: chordID), pagePoint: point, sourcePagePoint: point))
        }
        for (index, kind) in [FreeInkArticulationKind.fermata, .accent].enumerated() {
            let point = FreeInkArticulationPagePoint(pageIndex: 0, x: 220 + Double(index) * 120, y: 500)
            chart.freeInkArticulations.append(FreeInkArticulation(kind: kind,
                sourceInkData: archive, pagePoint: point, sourcePagePoint: point))
        }
        let before = chart
        let rendered = try await image(for: chart, exporter: exporter)
        for mark in chart.freeInkArticulations {
            let target = try XCTUnwrap(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: layout))
            let region = target.markFrame.insetBy(dx: -3, dy: -3)
                .offsetBy(dx: -layout.paperFrame.minX, dy: -layout.paperFrame.minY)
            XCTAssertGreaterThan(try darkPixels(rendered, in: region) - darkPixels(baseline, in: region), 4,
                "The actual PDF must paint each attached and floating mark at the editor's displayed position")
        }
        XCTAssertEqual(chart, before)
        let attachment = XCTAttachment(image: UIImage(cgImage: rendered))
        attachment.name = "Simple attached and floating fermatas and accents - actual PDF"
        attachment.lifetime = .keepAlways
        add(attachment)
        let exported = try await exporter.exportPDF(for: chart)
        let pdf = XCTAttachment(data: try Data(contentsOf: exported.url), uniformTypeIdentifier: "com.adobe.pdf")
        pdf.name = "Simple attached and floating fermatas and accents.pdf"
        pdf.lifetime = .keepAlways
        add(pdf)
    }

    private func image(for chart: Chart, exporter: PDFChartExporter) async throws -> CGImage {
        let exported = try await exporter.exportPDF(for: chart)
        let page = try XCTUnwrap(PDFDocument(url: exported.url)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(bounds)
            renderer.cgContext.translateBy(x: 0, y: bounds.height)
            renderer.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: renderer.cgContext)
        }
        return try XCTUnwrap(image.cgImage)
    }

    private func darkPixels(_ image: CGImage, in rect: CGRect) throws -> Int {
        let crop = try XCTUnwrap(image.cropping(to: rect.integral))
        var bytes = [UInt8](repeating: 255, count: crop.width * crop.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        XCTAssertTrue(drawn)
        return stride(from: 0, to: bytes.count, by: 4).filter {
            bytes[$0] < 100 && bytes[$0 + 1] < 100 && bytes[$0 + 2] < 100
        }.count
    }
}
#endif

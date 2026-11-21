#if canImport(UIKit) && canImport(PDFKit)
import PDFKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class PDFStaffImportTests: XCTestCase {
    func testTwoPageDrawnStaffImportsEveryMeasureAndKeepsEmptyFields() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Drawn staff.pdf")
        let bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            drawStaff(context, chords: [("Cmaj7", 90), ("Dm7", 330), ("G7", 380), ("F/G", 450)])
            context.beginPage()
            drawStaff(context, chords: [("A", 90), ("F#7/A#", 210), ("Bm", 330), ("D7/A", 380), ("G", 450)])
        }
        try bytes.write(to: source)
        let library = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("PDF Library"))
        let imported = try await library.importPDF(from: source)
        let retained = try XCTUnwrap(library.exportedPDF(for: imported))
        let draft = try await PDFEditableChartReader.read(from: retained.url, title: "Drawn staff")
        XCTAssertTrue(draft.usesDrawnBarlines)
        XCTAssertEqual(draft.staffPageNumbers, [1, 2])
        XCTAssertEqual(draft.rows, [
            ["Cmaj7", "", "Dm7 G7", "F/G"],
            ["A", "F#7/A#", "Bm D7/A", "G"]
        ])
        XCTAssertNil(draft.reviewIssue(forMeasure: draft.rows[0][1]),
            "A printed measure with no new chord still belongs in the chart")

        let chart = try draft.makeChart(sourcePDFLibraryItemID: imported.id)
        XCTAssertEqual(chart.systems.map { $0.measures.count }, [4, 4])
        XCTAssertEqual(chart.measures.map { $0.chordEvents.count }, [1, 0, 2, 1, 1, 1, 2, 1])
        XCTAssertTrue(chart.measures.flatMap(\.chordEvents).allSatisfy { $0.spellingIntent == .explicit })
        XCTAssertEqual(chart.sourcePDFLibraryItemID, imported.id)
        XCTAssertEqual(try Data(contentsOf: retained.url), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    private func drawStaff(_ context: UIGraphicsPDFRendererContext, chords: [(String, CGFloat)]) {
        NSString(string: "Drawn staff fixture").draw(at: CGPoint(x: 80, y: 40),
            withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        NSString(string: "Piano solo intro").draw(at: CGPoint(x: 80, y: 92),
            withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
        let drawing = context.cgContext
        drawing.setStrokeColor(UIColor.black.cgColor)
        drawing.setLineWidth(0.8)
        for y in stride(from: CGFloat(160), through: 184, by: 6) {
            drawing.move(to: CGPoint(x: 80, y: y))
            drawing.addLine(to: CGPoint(x: 560, y: y))
        }
        for x in [CGFloat(80), 200, 320, 440, 558, 560] {
            drawing.move(to: CGPoint(x: x, y: 160))
            drawing.addLine(to: CGPoint(x: x, y: 184))
        }
        drawing.strokePath()
        for (chord, x) in chords {
            NSString(string: chord).draw(at: CGPoint(x: x, y: 136),
                withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
    }
}
#endif

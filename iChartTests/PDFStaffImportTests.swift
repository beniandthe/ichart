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

    func testShortFinalStaffRejectsPartialConversionAndPreservesOriginalPDF() async throws {
        try await assertUnsupportedPDF { context in
            drawStaff(context, chords: [("Cmaj7", 90)])
            drawStaffSystem(context, left: 80, right: 230, top: 320,
                dividers: [80, 230], chords: [("G7", 90)])
        }
    }

    func testSideBySideStaffsRejectPartialConversionAndPreserveOriginalPDF() async throws {
        try await assertUnsupportedPDF { context in
            drawStaffSystem(context, left: 30, right: 280, top: 160,
                dividers: [30, 155, 280], chords: [("Cmaj7", 50), ("Dm7", 175)])
            drawStaffSystem(context, left: 332, right: 582, top: 160,
                dividers: [332, 457, 582], chords: [("G7", 350), ("C", 480)])
        }
    }

    func testSideBySideStaffsWithDifferentRuleThicknessRejectPartialConversion() async throws {
        try await assertUnsupportedPDF { context in
            drawStaffSystem(context, left: 30, right: 282, top: 160,
                dividers: [30, 155, 282], chords: [("Cmaj7", 50)], lineWidth: 1.5)
            drawStaffSystem(context, left: 332, right: 582, top: 160,
                dividers: [332, 457, 582], chords: [("G7", 350)], lineWidth: 0.75)
        }
    }

    func testVerticallyOffsetSideBySideStaffsRejectPartialConversion() async throws {
        try await assertUnsupportedPDF { context in
            drawStaffSystem(context, left: 30, right: 280, top: 160,
                dividers: [30, 155, 280], chords: [("Cmaj7", 50)])
            drawStaffSystem(context, left: 332, right: 582, top: 166,
                dividers: [332, 457, 582], chords: [("G7", 350)])
        }
    }

    func testTwoFullWidthSystemsOnOnePageKeepEveryMeasure() async throws {
        let draft = try await readGeneratedPDF { context in
            drawStaff(context, chords: [("Cmaj7", 90)])
            drawStaffSystem(context, left: 80, right: 560, top: 320,
                dividers: [80, 200, 320, 440, 560], chords: [("G7", 90)])
        }
        XCTAssertEqual(draft.staffPageNumbers, [1, 1])
        XCTAssertEqual(draft.rows, [["Cmaj7", "", "", ""], ["G7", "", "", ""]])
    }

    func testFourShortParallelRulesDoNotRejectAnOtherwiseSupportedStaff() async throws {
        let draft = try await readGeneratedPDF { context in
            drawStaff(context, chords: [("Cmaj7", 90)])
            let drawing = context.cgContext
            for y in stride(from: CGFloat(320), through: 338, by: 6) {
                drawing.move(to: CGPoint(x: 80, y: y))
                drawing.addLine(to: CGPoint(x: 230, y: y))
            }
            drawing.strokePath()
        }
        XCTAssertEqual(draft.rows, [["Cmaj7", "", "", ""]])
    }

    func testOverprintedGlyphsAreNotExtraChordCharactersOrChanges() async throws {
        let draft = try await readGeneratedPDF { context in
            drawStaff(context, chords: [
                ("Dm7", 90), ("Dm7", 90.2), ("Fmaj7", 210), ("Fmaj7", 210.2),
                ("C11", 330), ("G7", 450), ("G7", 493)
            ])
        }

        XCTAssertEqual(draft.rows, [["Dm7", "Fmaj7", "C11", "G7 G7"]])
        let chart = try draft.makeChart(sourcePDFLibraryItemID: UUID())
        XCTAssertEqual(chart.measures.map { $0.chordEvents.count }, [1, 1, 1, 2])
    }

    func testInaccessibleLaterPageReportsItsNumberWithoutReturningPartialDraft() async throws {
        do {
            _ = try await readGeneratedPDF { context in
                drawStaff(context, chords: [("Cmaj7", 90)])
                context.beginPage()
                let drawing = context.cgContext
                drawing.setFillColor(UIColor.black.cgColor)
                drawing.fill(CGRect(x: 25, y: 50, width: 90, height: 30))
            }
            XCTFail("An unreadable second page must not produce a one-page draft")
        } catch let error as PDFEditableChartReadError {
            XCTAssertEqual(error, .noSelectableTextOnPage(2))
        }
    }

    func testAccessibleChordLabelsCanWrapWithoutLosingChords() async throws {
        let draft = try await readGeneratedPDF { _ in
            let spans: [(String, CGFloat)] = [
                ("Bar 1,", 120), ("g Minor Bar Line", 140),
                ("Bar 2, e Flat", 220), ("Over g Bar Line", 240),
                ("Bar 3, d Unknown Bar Line", 320), ("Made with iReal Pro", 700)
            ]
            for (text, y) in spans {
                NSString(string: text).draw(at: CGPoint(x: 80, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }

        XCTAssertEqual(draft.rows, [["Gm"], ["Eb/G"], ["[d Unknown]"]])
        XCTAssertNotNil(draft.reviewIssue(forMeasure: draft.rows[2][0], rowIndex: 2))
    }

    private func assertUnsupportedPDF(
        draw: (UIGraphicsPDFRendererContext) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        do {
            _ = try await readGeneratedPDF(draw: draw)
            XCTFail("A partial staff page must not become a successful editable draft", file: file, line: line)
        } catch let error as PDFEditableChartReadError {
            XCTAssertEqual(error, .unsupportedStaffPage(1), file: file, line: line)
            XCTAssertTrue(error.localizedDescription.contains("original PDF is unchanged"), file: file, line: line)
        }
    }

    private func readGeneratedPDF(
        draw: (UIGraphicsPDFRendererContext) -> Void
    ) async throws -> PDFEditableChartDraft {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Staff completeness.pdf")
        let bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            draw(context)
        }
        try bytes.write(to: source)
        let library = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("PDF Library"))
        let imported = try await library.importPDF(from: source)
        let retained = try XCTUnwrap(library.exportedPDF(for: imported))
        defer {
            XCTAssertEqual(try? Data(contentsOf: retained.url), bytes)
            XCTAssertEqual(try? Data(contentsOf: source), bytes)
        }
        return try await PDFEditableChartReader.read(from: retained.url, title: "Staff completeness")
    }

    private func drawStaff(_ context: UIGraphicsPDFRendererContext, chords: [(String, CGFloat)]) {
        NSString(string: "Drawn staff fixture").draw(at: CGPoint(x: 80, y: 40),
            withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        NSString(string: "Piano solo intro").draw(at: CGPoint(x: 80, y: 92),
            withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
        drawStaffSystem(context, left: 80, right: 560, top: 160,
            dividers: [80, 200, 320, 440, 558, 560], chords: chords)
    }

    private func drawStaffSystem(
        _ context: UIGraphicsPDFRendererContext, left: CGFloat, right: CGFloat, top: CGFloat,
        dividers: [CGFloat], chords: [(String, CGFloat)], lineWidth: CGFloat = 0.8
    ) {
        let drawing = context.cgContext
        drawing.setStrokeColor(UIColor.black.cgColor)
        drawing.setLineWidth(lineWidth)
        for y in stride(from: top, through: top + 24, by: 6) {
            drawing.move(to: CGPoint(x: left, y: y))
            drawing.addLine(to: CGPoint(x: right, y: y))
        }
        for x in dividers {
            drawing.move(to: CGPoint(x: x, y: top))
            drawing.addLine(to: CGPoint(x: x, y: top + 24))
        }
        drawing.strokePath()
        for (chord, x) in chords {
            NSString(string: chord).draw(at: CGPoint(x: x, y: top - 24),
                withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
    }
}
#endif

#if canImport(UIKit) && canImport(PDFKit)
import PDFKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class PDFEditableChartWorkflowTests: XCTestCase {
    func testTextPDFReviewCreatesEditableChartThatReopensTransposesAndExports() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Printed chords.pdf")
        let original = textPDF(lines: [
            "Printed chords",
            "| Bbmaj7 | Dm7 | G7 Cmaj7 | F/G |",
            "| Am7 | ??? | D7 | Gmaj7 |"
        ])
        try original.write(to: source)
        let pdfDirectory = root.appendingPathComponent("PDF Library", isDirectory: true)
        let pdfStore = IChartPDFLibraryStore(baseDirectory: pdfDirectory)
        let imported = try await pdfStore.importPDF(from: source, title: "Printed chords")
        let retained = try XCTUnwrap(pdfStore.exportedPDF(for: imported))
        XCTAssertEqual(imported.source, .personalImport)
        XCTAssertEqual(try Data(contentsOf: retained.url), original)

        var draft = try await PDFEditableChartReader.read(from: retained.url, title: imported.displayTitle)
        XCTAssertEqual(draft.rows.count, 2)
        XCTAssertEqual(draft.rows.map(\.count), [4, 4])
        XCTAssertEqual(draft.rows[0], ["Bbmaj7", "Dm7", "G7 Cmaj7", "F/G"])
        XCTAssertEqual(draft.rows[1][1], "???", "Unreadable measures must remain available for review")
        XCTAssertNotNil(PDFEditableChartDraft.issue(forMeasure: draft.rows[1][1]))
        XCTAssertThrowsError(try draft.makeChart(sourcePDFLibraryItemID: imported.id))
        draft.title = "Reviewed printed chords"
        draft.rows[1][1] = "E7"
        let converted = try draft.makeChart(sourcePDFLibraryItemID: imported.id)
        XCTAssertEqual(converted.sourcePDFLibraryItemID, imported.id)
        XCTAssertEqual(converted.layoutStyle, .simpleChordSheet)
        XCTAssertTrue(converted.hasCompletedInitialSetup)
        XCTAssertEqual(converted.systems.map { $0.measures.count }, [4, 4])
        XCTAssertEqual(converted.measures.map { $0.chordEvents.count }, [1, 1, 2, 1, 1, 1, 1, 1])
        let expected = try ["Bbmaj7", "Dm7", "G7", "Cmaj7", "F/G", "Am7", "E7", "D7", "Gmaj7"]
            .map(ChordSymbolParser.parse)
        XCTAssertEqual(converted.measures.flatMap(\.chordEvents).map(\.symbol), expected)

        let repository = FileChartRepository(url: root.appendingPathComponent("library-state.json"))
        let store = ChartLibraryStore(charts: [], repository: repository)
        let didSave = await store.saveConvertedPDFChart(converted)
        XCTAssertTrue(didSave, "Create Chart must finish saving before navigation continues")
        let saved = try XCTUnwrap(repository.loadSnapshot())
        XCTAssertEqual(saved.selectedChartID, converted.id)
        XCTAssertEqual(saved.charts, [converted])

        let reopened = ChartLibraryStore(snapshot: saved, repository: repository)
        let binding = try XCTUnwrap(reopened.editorBinding(for: converted.id))
        var edited = binding.wrappedValue
        let event = try XCTUnwrap(edited.measures.first?.chordEvents.first)
        XCTAssertTrue(edited.replaceChordEvent(event.id, with: try ChordSymbolParser.parse("Eb7"), rawInput: "Eb7"))
        edited.transposeChordsByHalfSteps(2)
        XCTAssertEqual(edited.measures.first?.chordEvents.first?.symbol, try ChordSymbolParser.parse("F7"))
        XCTAssertEqual(edited.sourcePDFLibraryItemID, imported.id)
        binding.wrappedValue = edited
        let persisted = try await savedChart(id: edited.id, matching: edited, in: repository)
        XCTAssertEqual(persisted, edited)

        let exported = try await PDFChartExporter(exportDirectory: root.appendingPathComponent("Exports"))
            .exportPDF(for: persisted)
        let document = try XCTUnwrap(PDFDocument(url: exported.url))
        XCTAssertGreaterThan(document.pageCount, 0)
        let exportedText = try XCTUnwrap(document.string)
        XCTAssertTrue(exportedText.contains("Reviewed printed chords"))
        XCTAssertPDFExtractedTextContains(exportedText, visibleChordText: "F7")
        let restoredPDFs = IChartPDFLibraryStore(baseDirectory: pdfDirectory)
        XCTAssertEqual(restoredPDFs.items, [imported])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restoredPDFs.exportedPDF(for: imported)).url), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testRasterPDFStaysReadableInLibraryAndReportsNoSelectableText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Scanned chords.pdf")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 100)).image { _ in
            NSString(string: "| Cmaj7 | Dm7 | G7 | Cmaj7 |").draw(at: CGPoint(x: 12, y: 30),
                withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        let original = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            image.draw(in: CGRect(x: 40, y: 50, width: 500, height: 125))
        }
        try original.write(to: source)
        let pdfStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("PDF Library"))
        let imported = try await pdfStore.importPDF(from: source)
        let retained = try XCTUnwrap(pdfStore.exportedPDF(for: imported))
        do {
            _ = try await PDFEditableChartReader.read(from: retained.url, title: imported.displayTitle)
            XCTFail("A raster page must not create an empty editable chart")
        } catch {
            XCTAssertEqual(error as? PDFEditableChartReadError, .noSelectableText)
        }
        XCTAssertEqual(pdfStore.items, [imported])
        XCTAssertEqual(try Data(contentsOf: retained.url), original)
        XCTAssertNotNil(PDFDocument(url: retained.url)?.page(at: 0))
    }

    func testMultipageTextGridKeepsPageOrderAndChordPlacement() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        let original = textPDF(pages: [
            ["Concert grid", "| Bbmaj7 | Dm7 | G7 Cmaj7 | F/G |"],
            ["| Am7 | C7 | D7 | Gmaj7 |"]
        ])
        try original.write(to: source)

        let draft = try await PDFEditableChartReader.read(from: source, title: "Concert grid")
        XCTAssertEqual(draft.rows, [
            ["Bbmaj7", "Dm7", "G7 Cmaj7", "F/G"],
            ["Am7", "C7", "D7", "Gmaj7"]
        ])
        XCTAssertEqual(draft.sourcePageNumber(forRow: 0), 1)
        XCTAssertEqual(draft.sourcePageNumber(forRow: 1), 2)
        let chart = try draft.makeChart(sourcePDFLibraryItemID: UUID())
        XCTAssertEqual(chart.systems.map { $0.measures.count }, [4, 4])
        XCTAssertEqual(chart.measures.map { $0.chordEvents.count }, [1, 1, 2, 1, 1, 1, 1, 1])
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testAccessibleGridKeepsStackedBassAndOffsetEndingInVisualOrder() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        let original = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            let labels: [(String, CGPoint)] = [
                ("Bar 1, g Minor Bar LineBar 2, e Flat Over g Bar Line", CGPoint(x: 40, y: 80)),
                ("Bar 6, b Flat Bar Line", CGPoint(x: 310, y: 130)),
                ("Made with iReal Pro", CGPoint(x: 175, y: 720))
            ]
            for (label, point) in labels {
                NSString(string: label).draw(at: point,
                    withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
            }
        }
        try original.write(to: source)

        let draft = try await PDFEditableChartReader.read(from: source, title: "Accessible grid")
        XCTAssertEqual(draft.rows, [["Gm", "Eb/G"], ["Bb"]])
        XCTAssertEqual(draft.sourcePageNumber(forRow: 1), 1)
        let chart = try draft.makeChart(sourcePDFLibraryItemID: UUID())
        XCTAssertEqual(chart.systems.map { $0.measures.count }, [2, 1])
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    private func textPDF(lines: [String]) -> Data {
        textPDF(pages: [lines])
    }

    private func textPDF(pages: [[String]]) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for lines in pages {
                context.beginPage()
                for (index, line) in lines.enumerated() {
                    NSString(string: line).draw(at: CGPoint(x: 40, y: CGFloat(40 + index * 40)),
                        withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)])
                }
            }
        }
    }

    private func savedChart(id: Chart.ID, matching chart: Chart, in repository: FileChartRepository) async throws -> Chart {
        for _ in 0..<80 {
            if let current = try repository.loadSnapshot()?.charts.first(where: { $0.id == id }), current == chart {
                return current
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        return try XCTUnwrap(repository.loadSnapshot()?.charts.first { $0.id == id }, "Edited native chart must save")
    }
}
#endif

#if canImport(UIKit)
import Foundation
import PDFKit
import UIKit
import XCTest
@testable import iChart

final class PDFChartExporterTests: XCTestCase {
    func testExportPDFWritesAValidLookingPDFFile() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedPDF = try await exporter.exportPDF(for: ChartSamples.syncopatedFunkGroove)
        let exportedURL = exportedPDF.url
        let data = try Data(contentsOf: exportedURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
        XCTAssertGreaterThan(data.count, 2_000)
        XCTAssertEqual(exportedPDF.chartTitle, ChartSamples.syncopatedFunkGroove.title)
        XCTAssertEqual(exportedPDF.layoutStyle, ChartSamples.syncopatedFunkGroove.layoutStyle)
        XCTAssertEqual(exportedPDF.transpositionView, ChartSamples.syncopatedFunkGroove.defaultTranspositionView)
        XCTAssertEqual(exportedPDF.pageCount, 1)
        XCTAssertEqual(exportedPDF.fileSizeBytes, data.count)
        XCTAssertFalse(exportedPDF.fileName.isEmpty)
    }

    func testExportPDFDoesNotIncludeEditorInstructionPlaceholderText() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let chart = Chart.blank(
            title: "Chord Writing Test Chart",
            key: .cMajor,
            measureCount: 8
        )
        let exportedURL = try await exporter.exportPDF(for: chart).url
        let documentText = PDFDocument(url: exportedURL)?.string ?? ""

        XCTAssertFalse(documentText.contains("Tap the measure in the editor"))
    }

    func testExportPDFUsesLeadSheetPageLayoutInsteadOfMeasureCards() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: ChartSamples.straightAheadSwing).url
        let document = try XCTUnwrap(PDFDocument(url: exportedURL))
        let documentText = document.string ?? ""
        let pageBounds = try XCTUnwrap(document.page(at: 0)?.bounds(for: .mediaBox))

        XCTAssertTrue(documentText.contains(ChartSamples.straightAheadSwing.title.uppercased()))
        XCTAssertFalse(documentText.contains("Page 1"))
        XCTAssertFalse(documentText.contains("M1"))
        XCTAssertFalse(documentText.contains("M2"))
        XCTAssertGreaterThan(pageBounds.height, pageBounds.width)
    }

    func testSimpleChordSheetExportProofRendersStructuredObjects() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        let chart = try makeSimpleChordSheetExportProofChart()

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: chart).url
        let document = try XCTUnwrap(PDFDocument(url: exportedURL))
        let documentText = document.string ?? ""
        let pageBounds = try XCTUnwrap(document.page(at: 0)?.bounds(for: .mediaBox))

        XCTAssertTrue(documentText.contains("Simple Export Proof"))
        XCTAssertTrue(documentText.contains("INTRO"))
        XCTAssertTrue(documentText.contains("C"))
        XCTAssertTrue(documentText.contains("F"))
        XCTAssertTrue(documentText.contains("G/B"))
        XCTAssertTrue(documentText.contains("freely"))
        XCTAssertTrue(documentText.contains("1."))
        XCTAssertPDFExtractedTextContains(
            documentText,
            visibleNotationText: "To \u{E048}"
        )
        XCTAssertTrue(documentText.contains("FINE"))
        XCTAssertFalse(documentText.contains("C MAJOR"))
        XCTAssertFalse(documentText.contains("Tap the measure in the editor"))
        XCTAssertGreaterThan(pageBounds.height, pageBounds.width)
    }

    func testAppendPageExportCreatesSeparatePDFPages() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        var chart = Chart.blank(
            title: "Two Page Export",
            measureCount: 8,
            layoutStyle: .simpleChordSheet
        )
        _ = try XCTUnwrap(chart.appendPage())

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedPDF = try await exporter.exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exportedPDF.url))
        let firstPageText = document.page(at: 0)?.string ?? ""
        let secondPageText = document.page(at: 1)?.string ?? ""

        XCTAssertEqual(exportedPDF.pageCount, 2)
        XCTAssertEqual(exportedPDF.pageCountText, "2 pages")
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertTrue(firstPageText.contains("Two Page Export"))
        XCTAssertFalse(secondPageText.contains("Two Page Export"))
    }

    func testAppendPageExportIncludesEveryChartPage() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        var chart = Chart.blank(
            title: "Three Page Export",
            measureCount: 8,
            layoutStyle: .simpleChordSheet
        )
        let secondPageMeasureID = try XCTUnwrap(chart.appendPage())
        let thirdPageMeasureID = try XCTUnwrap(chart.appendPage())
        _ = try XCTUnwrap(
            chart.addCueText(
                "second page export marker",
                anchorMeasureID: secondPageMeasureID,
                position: .above
            )
        )
        _ = try XCTUnwrap(
            chart.addCueText(
                "third page export marker",
                anchorMeasureID: thirdPageMeasureID,
                position: .above
            )
        )

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedPDF = try await exporter.exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exportedPDF.url))
        let firstPageText = document.page(at: 0)?.string ?? ""
        let secondPageText = document.page(at: 1)?.string ?? ""
        let thirdPageText = document.page(at: 2)?.string ?? ""

        XCTAssertEqual(exportedPDF.pageCount, 3)
        XCTAssertEqual(exportedPDF.pageCountText, "3 pages")
        XCTAssertEqual(document.pageCount, 3)
        XCTAssertTrue(firstPageText.contains("Three Page Export"))
        XCTAssertFalse(secondPageText.contains("Three Page Export"))
        XCTAssertFalse(thirdPageText.contains("Three Page Export"))
        XCTAssertTrue(secondPageText.contains("second page export marker"))
        XCTAssertFalse(firstPageText.contains("second page export marker"))
        XCTAssertFalse(thirdPageText.contains("second page export marker"))
        XCTAssertTrue(thirdPageText.contains("third page export marker"))
        XCTAssertFalse(firstPageText.contains("third page export marker"))
        XCTAssertFalse(secondPageText.contains("third page export marker"))
    }

    func testThirtyTwoMeasureRhythmExportUsesMultipleFixedPages() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        let chart = Chart.blank(
            title: "Thirty Two Measure Rhythm Export",
            measureCount: 32,
            layoutStyle: .rhythmSectionSheet
        )

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedPDF = try await exporter.exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exportedPDF.url))
        let pageBounds = try (0..<document.pageCount).map { pageIndex in
            try XCTUnwrap(document.page(at: pageIndex)?.bounds(for: .mediaBox))
        }

        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertEqual(exportedPDF.pageCount, document.pageCount)
        XCTAssertTrue(pageBounds.allSatisfy { $0.height > $0.width })
        for bounds in pageBounds.dropFirst() {
            XCTAssertEqual(bounds.width, pageBounds[0].width, accuracy: 0.01)
            XCTAssertEqual(bounds.height, pageBounds[0].height, accuracy: 0.01)
        }
        XCTAssertTrue(document.page(at: 0)?.string?.contains("THIRTY TWO MEASURE RHYTHM EXPORT") == true)
        XCTAssertFalse(document.page(at: 1)?.string?.contains("THIRTY TWO MEASURE RHYTHM EXPORT") == true)
    }

    func testDenseSystemSpacingPDFUsesSamePaginationAndRowsAsEditorLayout() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Dense Spacing Export", measureCount: 12, layoutStyle: layoutStyle)
            chart.engravingPreset = .compact
            chart.systems = chart.measures.enumerated().map { index, measure in
                ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced, measures: [measure])
            }
            for (index, measure) in chart.measures.enumerated() {
                _ = try XCTUnwrap(chart.addCueText("spacing row \(index + 1)", anchorMeasureID: measure.id, position: .above))
            }
            let standardPDF = try await exporter.exportPDF(for: chart)
            XCTAssertEqual(standardPDF.pageCount, 3)

            chart.setStaffSystemDensity(.dense)
            let editorLayout = LeadSheetPageLayoutEngine.pageLayout(
                for: chart,
                pageSize: CGSize(width: 932, height: 1_100)
            )
            let densePDF = try await exporter.exportPDF(for: chart)
            let document = try XCTUnwrap(PDFDocument(url: densePDF.url))
            XCTAssertEqual(densePDF.pageCount, 2)
            XCTAssertEqual(document.pageCount, editorLayout.pages.count)
            XCTAssertEqual(editorLayout.pages.first?.systemIDs.count, 7)
            for (index, page) in editorLayout.pages.enumerated() {
                let exportedPage = try XCTUnwrap(document.page(at: index))
                XCTAssertEqual(exportedPage.bounds(for: .mediaBox).size, page.frame.size)
                let text = exportedPage.string ?? ""
                let expectedMeasures = editorLayout.systems
                    .filter { page.systemIDs.contains($0.id) }
                    .flatMap(\.measures)
                    .compactMap(\.sourceMeasureID)
                for measureID in expectedMeasures {
                    let cue = try XCTUnwrap(chart.cueTexts.first { $0.anchorMeasureID == measureID })
                    XCTAssertTrue(text.contains(cue.text), "Expected \(cue.text) on PDF page \(index + 1)")
                }
            }
        }
    }

    @MainActor
    func testDenseChartPreviewWithChordsCueAndRepeat() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Closer to the Music", measureCount: 6, layoutStyle: layoutStyle)
            chart.composerCredit = "Density preview"
            chart.styleNote = "Medium swing"
            chart.engravingPreset = .compact
            chart.setStaffSystemDensity(.dense)
            chart.systems = chart.measures.enumerated().map { index, measure in
                ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced, measures: [measure])
            }
            let chords = ["C", "F7", "C7", "G7", "Am7", "D7"]
            for (index, measure) in chart.measures.enumerated() {
                if layoutStyle == .rhythmSectionSheet {
                    XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measure.id))
                }
                XCTAssertTrue(chart.appendRecognizedChord(
                    try ChordSymbolParser.parse(chords[index]), rawInput: chords[index], to: measure.id, atFraction: 0.05
                ))
            }
            _ = try XCTUnwrap(chart.addCueText("Play lightly", anchorMeasureID: chart.measures[2].id, position: .below))
            _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: chart.measures[3].id, endMeasureID: chart.measures[5].id))
            let exportedPDF = try await exporter.exportPDF(for: chart)
            let document = try XCTUnwrap(PDFDocument(url: exportedPDF.url))
            XCTAssertEqual(document.pageCount, 1)
            XCTAssertTrue(document.string?.contains("Play lightly") == true)

            if let directory = ProcessInfo.processInfo.environment["ICHART_HEADER_QA_OUTPUT"], !directory.isEmpty {
                let output = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let page = try XCTUnwrap(document.page(at: 0))
                let bounds = page.bounds(for: .mediaBox)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let preview = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: bounds.size))
                    context.cgContext.translateBy(x: 0, y: bounds.height)
                    context.cgContext.scaleBy(x: 1, y: -1)
                    page.draw(with: .mediaBox, to: context.cgContext)
                }
                try XCTUnwrap(preview.pngData()).write(to: output.appendingPathComponent("density-\(layoutStyle.rawValue)-compact-dense.png"))
            }
        }
    }

    func testRhythmSectionExportProofRendersStructuredObjects() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        let chart = try makeRhythmSectionExportProofChart()

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: chart).url
        let document = try XCTUnwrap(PDFDocument(url: exportedURL))
        let documentText = document.string ?? ""
        let pageBounds = try XCTUnwrap(document.page(at: 0)?.bounds(for: .mediaBox))

        XCTAssertTrue(documentText.contains("RHYTHM EXPORT PROOF"))
        XCTAssertTrue(documentText.contains("A"))
        XCTAssertPDFExtractedTextContains(documentText, visibleChordText: "C7")
        XCTAssertPDFExtractedTextContains(documentText, visibleChordText: "F7")
        XCTAssertPDFExtractedTextContains(documentText, visibleChordText: "G7sus")
        XCTAssertTrue(documentText.contains("stop time"))
        XCTAssertTrue(documentText.contains("1."))
        XCTAssertPDFExtractedTextContains(
            documentText,
            visibleNotationText: "D.S. al \u{E048}"
        )
        XCTAssertFalse(documentText.contains("C MAJOR"))
        XCTAssertFalse(documentText.contains("Tap the measure in the editor"))
        XCTAssertGreaterThan(pageBounds.height, pageBounds.width)
    }

    func testSimpleChordSheetPDFOmitsRowKeyTextForModulation() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        var chart = Chart.blank(
            title: "PDF Key Modulation",
            key: .bFlatMajor,
            measureCount: 6,
            layoutStyle: .simpleChordSheet
        )
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.setKeyChange(.dMajor, atStartOf: measureIDs[3]))

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: chart).url
        let documentText = PDFDocument(url: exportedURL)?.string ?? ""

        XCTAssertFalse(documentText.contains("BB MAJOR"))
        XCTAssertFalse(documentText.contains("Bb maj"))
        XCTAssertFalse(documentText.contains("D maj"))
    }

    func testPDFOmitsPrintedKeyMetadataAfterInstrumentTransposition() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        var chart = Chart.blank(
            title: "PDF Written Key",
            key: .cMajor,
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        chart.setInstrumentTranspositionView(.bb)

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: chart).url
        let documentText = PDFDocument(url: exportedURL)?.string ?? ""

        XCTAssertFalse(documentText.contains("D MAJOR"))
        XCTAssertFalse(documentText.contains("D maj"))
    }

    func testPDFChordSpellingUsesActiveKeyAndExplicitOverride() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        var chart = Chart.blank(
            title: "PDF Chord Spelling",
            key: .dMajor,
            measureCount: 2,
            layoutStyle: .simpleChordSheet
        )
        let measureIDs = chart.measures.map(\.id)
        _ = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("Db7/F"),
                rawInput: "Db7/F",
                to: measureIDs[0],
                atFraction: 0.1,
                spellingIntent: .automatic
            )
        )
        _ = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("Db7/F"),
                rawInput: "Db7/F",
                to: measureIDs[1],
                atFraction: 0.1,
                spellingIntent: .explicit
            )
        )

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: chart).url
        let documentText = PDFDocument(url: exportedURL)?.string ?? ""

        XCTAssertPDFExtractedTextContains(documentText, visibleChordText: "C#7/F")
        XCTAssertPDFExtractedTextContains(documentText, visibleChordText: "Db7/F")
    }

    func testExportPDFUsesProductReadyReadableFileNames() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        let chart = Chart.blank(
            title: #"Almost Like / Being: In Love?"#,
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedPDF = try await exporter.exportPDF(for: chart)

        XCTAssertEqual(
            exportedPDF.fileName,
            "Almost Like Being In Love - Simple Chord Sheet - Concert.pdf"
        )
        XCTAssertEqual(exportedPDF.url.lastPathComponent, exportedPDF.fileName)
        XCTAssertEqual(exportedPDF.transpositionText, "Concert")
        XCTAssertEqual(exportedPDF.pageCountText, "1 page")
        XCTAssertFalse(exportedPDF.fileSizeText.isEmpty)
    }

    func testExportPDFFileNameFallsBackForBlankTitles() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        let chart = Chart.blank(
            title: "   ",
            measureCount: 4,
            layoutStyle: .rhythmSectionSheet
        )

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedPDF = try await exporter.exportPDF(for: chart)

        XCTAssertEqual(exportedPDF.fileName, "iChart - Rhythm Section Sheet - Concert.pdf")
        XCTAssertEqual(exportedPDF.navigationTitle, "iChart - Rhythm Section Sheet - Concert")
    }

    func testForumPDFExportIncludesFixedCreatorCreditFooter() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        let postID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let chart = Chart.blank(title: "Forum Export Proof", measureCount: 4)

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(
            for: chart,
            context: ChartPDFExportContext(
                forumCredit: ForumPDFCredit(
                    creatorDisplayName: "Beni Rossman",
                    forumPostID: postID,
                    exportedAt: Date(timeIntervalSince1970: 1_781_308_800)
                )
            )
        ).url
        let documentText = PDFDocument(url: exportedURL)?.string ?? ""

        XCTAssertTrue(documentText.contains("Shared from iChart Forums"))
        XCTAssertTrue(documentText.contains("Creator: Beni Rossman"))
        XCTAssertTrue(documentText.contains(postID.uuidString))
        XCTAssertTrue(documentText.contains("Exported: 2026-06-13"))
    }

    private func makeSimpleChordSheetExportProofChart() throws -> Chart {
        var chart = Chart.blank(
            title: "Simple Export Proof",
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        let measureIDs = chart.measures.map(\.id)
        chart.addSectionLabel(text: "Intro")
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3])
        )
        _ = try XCTUnwrap(
            chart.addEndingSpan(.ending1, startMeasureID: measureIDs[0], endMeasureID: measureIDs[1])
        )
        _ = try XCTUnwrap(
            chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: measureIDs[2])
        )
        _ = try XCTUnwrap(
            chart.addPointRoadmapMarker(.fine, anchorMeasureID: measureIDs[3])
        )
        _ = try XCTUnwrap(
            chart.addCueText("freely", anchorMeasureID: measureIDs[1], position: .above, emphasis: .subtle)
        )
        try appendChord("C", to: measureIDs[0], in: &chart, atFraction: 0.05)
        try appendChord("F", to: measureIDs[1], in: &chart, atFraction: 0.05)
        try appendChord("G/B", to: measureIDs[2], in: &chart, atFraction: 0.05)
        return chart
    }

    private func makeRhythmSectionExportProofChart() throws -> Chart {
        var chart = Chart.blank(
            title: "Rhythm Export Proof",
            measureCount: 4,
            layoutStyle: .rhythmSectionSheet
        )
        let measureIDs = chart.measures.map(\.id)
        chart.addSectionLabel(text: "A")
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3])
        )
        _ = try XCTUnwrap(
            chart.addEndingSpan(.ending1, startMeasureID: measureIDs[0], endMeasureID: measureIDs[1])
        )
        _ = try XCTUnwrap(
            chart.addPointRoadmapMarker(.dsAlCoda, anchorMeasureID: measureIDs[2])
        )
        _ = try XCTUnwrap(
            chart.addCueText("stop time", anchorMeasureID: measureIDs[1], position: .below, emphasis: .normal)
        )
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureIDs[0]))
        XCTAssertTrue(chart.setMeasureRhythmMap([.dottedHalf, .eighth, .eighth], for: measureIDs[1]))
        try appendChord("C7", to: measureIDs[0], in: &chart, atFraction: 0.05)
        try appendChord("F7", to: measureIDs[1], in: &chart, atFraction: 0.05)
        try appendChord("G7sus", to: measureIDs[2], in: &chart, atFraction: 0.05)
        return chart
    }

    private func appendChord(
        _ text: String,
        to measureID: UUID,
        in chart: inout Chart,
        atFraction fraction: Double
    ) throws {
        XCTAssertTrue(
            chart.appendRecognizedChord(
                try ChordSymbolParser.parse(text),
                rawInput: text,
                to: measureID,
                atFraction: fraction
            )
        )
    }
}
#endif

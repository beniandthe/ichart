#if canImport(UIKit)
import Foundation
import PDFKit
import XCTest
@testable import SmartChart

final class PDFChartExporterTests: XCTestCase {
    func testExportPDFWritesAValidLookingPDFFile() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: ChartSamples.syncopatedFunkGroove)
        let data = try Data(contentsOf: exportedURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
        XCTAssertGreaterThan(data.count, 2_000)
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
        let exportedURL = try await exporter.exportPDF(for: chart)
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

        let exportedURL = try await exporter.exportPDF(for: ChartSamples.straightAheadSwing)
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

        let exportedURL = try await exporter.exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exportedURL))
        let documentText = document.string ?? ""
        let pageBounds = try XCTUnwrap(document.page(at: 0)?.bounds(for: .mediaBox))

        XCTAssertTrue(documentText.contains("Simple Export Proof"))
        XCTAssertTrue(documentText.contains("INTRO"))
        XCTAssertTrue(documentText.contains("C"))
        XCTAssertTrue(documentText.contains("F"))
        XCTAssertTrue(documentText.contains("G/B"))
        XCTAssertTrue(documentText.contains("freely"))
        XCTAssertTrue(documentText.contains("FINE"))
        XCTAssertFalse(documentText.contains("C MAJOR"))
        XCTAssertFalse(documentText.contains("Tap the measure in the editor"))
        XCTAssertGreaterThan(pageBounds.height, pageBounds.width)
    }

    func testRhythmSectionExportProofRendersStructuredObjects() async throws {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)
        let chart = try makeRhythmSectionExportProofChart()

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exportedURL))
        let documentText = document.string ?? ""
        let pageBounds = try XCTUnwrap(document.page(at: 0)?.bounds(for: .mediaBox))

        XCTAssertTrue(documentText.contains("RHYTHM EXPORT PROOF"))
        XCTAssertTrue(documentText.contains("A"))
        XCTAssertPDFExtractedTextContains(documentText, visibleChordText: "C7")
        XCTAssertPDFExtractedTextContains(documentText, visibleChordText: "F7")
        XCTAssertPDFExtractedTextContains(documentText, visibleChordText: "G7sus")
        XCTAssertTrue(documentText.contains("stop time"))
        XCTAssertTrue(documentText.contains("D.S. AL CODA"))
        XCTAssertFalse(documentText.contains("C MAJOR"))
        XCTAssertFalse(documentText.contains("Tap the measure in the editor"))
        XCTAssertGreaterThan(pageBounds.height, pageBounds.width)
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

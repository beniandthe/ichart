#if canImport(UIKit)
import Foundation
import PDFKit
import XCTest
@testable import SmartChart

final class PDFRendererVisualQATests: XCTestCase {
    private struct VisualQACase {
        var label: String
        var chart: Chart
        var expectedText: [String]
    }

    private struct ProductProofCase {
        var fixtureName: String
        var measureIndex: Int
        var targetFraction: Double
    }

    private let productProofCases = [
        ProductProofCase(fixtureName: "C", measureIndex: 0, targetFraction: 0.05),
        ProductProofCase(fixtureName: "Db7b9", measureIndex: 1, targetFraction: 0.30),
        ProductProofCase(fixtureName: "GSlashB", measureIndex: 2, targetFraction: 0.55)
    ]

    func testRepresentativeRendererExportsRemainVisuallyInspectable() async throws {
        XCTAssertLessThanOrEqual(
            productProofCases.count,
            3,
            "Renderer visual QA may use a few fixed product-proof fixtures, but must not become a personal handwriting training loop."
        )

        let (productProofChart, productProofExpectedText) = try makeBoundedInkProductProofChart()
        let qaCases = [
            makeVisualQACase(label: "syncopated-funk-groove", chart: ChartSamples.syncopatedFunkGroove),
            makeVisualQACase(label: "straight-ahead-swing", chart: ChartSamples.straightAheadSwing),
            VisualQACase(
                label: "bounded-ink-product-proof",
                chart: productProofChart,
                expectedText: ["Renderer Product Proof"] + productProofExpectedText
            )
        ]

        let output = try rendererQAOutputDirectory()
        let exporter = PDFChartExporter(exportDirectory: output.url)
        var manifestLines = [
            "Smart Chart renderer visual QA",
            "Artifacts are bounded product evidence, not training data.",
            "Output: \(output.url.path)"
        ]

        defer {
            if !output.keepArtifacts {
                try? FileManager.default.removeItem(at: output.url)
            }
        }

        for qaCase in qaCases {
            let exportedURL = try await exporter.exportPDF(for: qaCase.chart)
            let data = try Data(contentsOf: exportedURL)
            let documentText = try XCTUnwrap(PDFDocument(url: exportedURL)?.string, qaCase.label)

            XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path), qaCase.label)
            XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF", qaCase.label)
            XCTAssertGreaterThan(data.count, 2_000, qaCase.label)
            XCTAssertFalse(documentText.contains("Tap the measure in the editor"), qaCase.label)

            for expectedText in qaCase.expectedText {
                XCTAssertTrue(
                    documentText.contains(expectedText),
                    "Expected \(qaCase.label) export to contain \(expectedText). PDF text: \(documentText)"
                )
            }

            manifestLines.append("\(qaCase.label): \(exportedURL.path)")
        }

        if output.keepArtifacts {
            try manifestLines
                .joined(separator: "\n")
                .appending("\n")
                .write(
                    to: output.url.appendingPathComponent("manifest.txt", isDirectory: false),
                    atomically: true,
                    encoding: .utf8
                )
        }
    }

    private func makeVisualQACase(label: String, chart: Chart) -> VisualQACase {
        let expectedChordText = chart.measures.flatMap { measure in
            measure.renderedChordPlacements(defaultMeter: chart.defaultMeter).map { placement in
                placement.chordEvent
                    .transposed(for: chart.defaultTranspositionView)
                    .symbol
                    .displayText
            }
        }

        return VisualQACase(
            label: label,
            chart: chart,
            expectedText: [chart.title] + expectedChordText
        )
    }

    private func makeBoundedInkProductProofChart() throws -> (chart: Chart, expectedText: [String]) {
        let recognizer = ChordInkRecognizer()
        var chart = Chart.blank(
            title: "Renderer Product Proof",
            key: .cMajor,
            measureCount: 4
        )
        var expectedDisplayTexts: [String] = []

        for proofCase in productProofCases {
            let fixture = try InkFixtureLoader.load(proofCase.fixtureName, file: #filePath)
            let result = recognizer.recognize(strokes: fixture.strokes)
            let match = try XCTUnwrap(result.match, fixture.name)
            let measureID = chart.measures[proofCase.measureIndex].id
            let fixtureData = try JSONEncoder().encode(fixture)

            XCTAssertEqual(match.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertTrue(chart.setPageHandwrittenChordDrawing(fixtureData), fixture.name)
            XCTAssertTrue(
                chart.appendRecognizedChord(
                    match.symbol,
                    rawInput: fixture.name,
                    to: measureID,
                    atFraction: proofCase.targetFraction,
                    sourceInkData: fixtureData
                ),
                fixture.name
            )
            XCTAssertTrue(chart.setPageHandwrittenChordDrawing(nil), fixture.name)
            XCTAssertNil(chart.pageHandwrittenChordData, fixture.name)

            expectedDisplayTexts.append(fixture.expectedDisplayText)
        }

        return (chart, expectedDisplayTexts)
    }

    private func rendererQAOutputDirectory() throws -> (url: URL, keepArtifacts: Bool) {
        let environment = ProcessInfo.processInfo.environment
        let configuredPath = [
            "SMART_CHART_RENDERER_QA_OUTPUT",
            "TEST_RUNNER_SMART_CHART_RENDERER_QA_OUTPUT"
        ].compactMap { environment[$0] }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let configuredPath {
            let url = URL(fileURLWithPath: configuredPath, isDirectory: true)
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return (url, true)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartChartRendererQA-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return (url, false)
    }
}
#endif

#if canImport(UIKit)
import Foundation
import PDFKit
import XCTest
@testable import SmartChart

final class RendererProductProofTests: XCTestCase {
    func testBoundedInkProductProofRendersRecognizedChordsInExport() async throws {
        WritingToRenderPipelineProof.assertCaseSetIsBounded()

        let recognizer = ChordInkRecognizer()
        var chart = Chart.blank(
            title: "Renderer Product Proof",
            key: .cMajor,
            measureCount: 4
        )
        var expectedDisplayTexts: [String] = []

        for proofCase in WritingToRenderPipelineProof.cases {
            let fixture = try InkFixtureLoader.load(proofCase.fixtureName, file: #filePath)
            let result = recognizer.recognize(strokes: fixture.strokes)
            let acceptedDecision = try WritingToRenderPipelineProof.acceptedDecision(
                for: result,
                proofCase: proofCase
            )
            let measureID = chart.measures[proofCase.measureIndex].id
            let fixtureData = try JSONEncoder().encode(fixture)

            XCTAssertTrue(chart.setPageHandwrittenChordDrawing(fixtureData), fixture.name)
            XCTAssertNotNil(
                chart.commitRecognizedChordInk(
                    acceptedDecision.match.symbol,
                    rawInput: acceptedDecision.acceptedText,
                    to: measureID,
                    atFraction: proofCase.targetFraction,
                    sourceInkData: fixtureData
                ),
                fixture.name
            )
            XCTAssertNil(chart.pageHandwrittenChordData, fixture.name)

            expectedDisplayTexts.append(proofCase.expectedDisplayText)
        }

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let exporter = PDFChartExporter(exportDirectory: exportDirectory)

        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let exportedURL = try await exporter.exportPDF(for: chart)
        let documentText = try XCTUnwrap(PDFDocument(url: exportedURL)?.string)

        XCTAssertTrue(documentText.contains("RENDERER PRODUCT PROOF"))
        XCTAssertFalse(documentText.contains("M1"))
        XCTAssertFalse(documentText.contains("Tap the measure in the editor"))
        for expectedDisplayText in expectedDisplayTexts {
            XCTAssertPDFExtractedTextContains(
                documentText,
                visibleChordText: expectedDisplayText,
                "Expected exported renderer output to contain \(expectedDisplayText). PDF text: \(documentText)"
            )
        }
    }
}
#endif

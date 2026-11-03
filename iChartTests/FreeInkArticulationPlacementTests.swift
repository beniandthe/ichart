import CoreGraphics
import XCTest
@testable import iChart

#if canImport(UIKit)
import PDFKit
import UIKit
#endif

final class FreeInkArticulationPlacementTests: XCTestCase {
    func testMeasureAndBeatRemainAnchoredAfterReflowAndEngravingChange() throws {
        var chart = makeChart()
        let measureID = try XCTUnwrap(chart.measures.last?.id)
        let size = CGSize(width: 850, height: 1_100)
        let initialLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let initialTarget = try XCTUnwrap(FreeInkArticulationPlacement.target(
            measureID: measureID, beatIndex: 2, chart: chart, pageLayout: initialLayout
        ))
        XCTAssertEqual(FreeInkArticulationPlacement.target(
            near: initialTarget.center, chart: chart, pageLayout: initialLayout
        ), initialTarget)

        XCTAssertTrue(chart.insertSystemBreak(before: measureID))
        chart.engravingPreset = .compact
        let movedLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let movedTarget = try XCTUnwrap(FreeInkArticulationPlacement.target(
            measureID: measureID, beatIndex: 2, chart: chart, pageLayout: movedLayout
        ))
        let movedSystem = try XCTUnwrap(movedLayout.systems.first {
            $0.measures.contains(where: { $0.sourceMeasureID == measureID })
        })
        let movedMeasure = try XCTUnwrap(movedSystem.measures.first { $0.sourceMeasureID == measureID })
        XCTAssertGreaterThan(movedTarget.center.y, initialTarget.center.y)
        XCTAssertEqual(movedTarget.center.x, movedMeasure.staffFrame.minX + 8
            + (movedMeasure.staffFrame.width - 16) * 2.5 / 4, accuracy: 0.01)
        XCTAssertEqual(movedTarget.center.y, try XCTUnwrap(movedSystem.staffLineYPositions.first)
            - movedTarget.staffSpace * 0.6, accuracy: 0.01)
        XCTAssertEqual(FreeInkArticulationPlacement.target(
            near: movedTarget.center, chart: chart, pageLayout: movedLayout
        ), movedTarget)
    }

    func testPlacementRequiresRealRhythmMeasureAndInRangeBeat() throws {
        let size = CGSize(width: 850, height: 1_100)
        let chart = makeChart()
        let rhythmLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertNil(FreeInkArticulationPlacement.target(
            measureID: measureID, beatIndex: 4, chart: chart, pageLayout: rhythmLayout
        ))
        XCTAssertNil(FreeInkArticulationPlacement.target(
            near: rhythmLayout.header.handwrittenFrame.origin, chart: chart, pageLayout: rhythmLayout
        ))
        let simpleChart = makeChart(style: .simpleChordSheet)
        let simpleLayout = LeadSheetPageLayoutEngine.pageLayout(for: simpleChart, pageSize: size)
        XCTAssertNil(FreeInkArticulationPlacement.target(
            measureID: try XCTUnwrap(simpleChart.measures.first?.id), beatIndex: 0,
            chart: simpleChart, pageLayout: simpleLayout
        ))
    }

    func testLastConversionRetainsSavedPaperWidthAndRemainingInkTakesPrecedence() throws {
        var chart = makeChart()
        let archivedSpace = PersistentInkCoordinateSpace(width: 560, height: 1_100)
        let visibleSpace = PersistentInkCoordinateSpace(width: 920, height: 1_100)
        chart.pageHandwrittenNotationData = Data([0x01])
        chart.pageHandwrittenNotationCoordinateSpace = archivedSpace
        let originalWidth = try XCTUnwrap(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
        let originalSize = CGSize(width: originalWidth, height: 1_100)
        let originalPaper = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: originalSize).paperFrame
        chart.freeInkArticulations = [FreeInkArticulation(kind: .fermata,
            measureID: try XCTUnwrap(chart.measures.first?.id), beatIndex: 0,
            sourceInkData: Data([0x01]), sourceCoordinateSpace: archivedSpace)]

        chart.pageHandwrittenNotationCoordinateSpace = visibleSpace
        XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.savedPageCoordinateSpace(for: chart), visibleSpace)

        chart.pageHandwrittenNotationData = nil
        chart.pageHandwrittenNotationCoordinateSpace = nil
        XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart), originalWidth)
        XCTAssertEqual(LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: originalSize).paperFrame, originalPaper)
    }

    private func makeChart(style: ChartLayoutStyle = .rhythmSectionSheet) -> Chart {
        var chart = Chart.draft(title: "Articulation placement", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 2)
        chart.stylePreset = .plainWhite
        return chart
    }

    #if canImport(UIKit)
    @MainActor
    func testExportDrawsBothArticulationsAtThePreviewTargets() async throws {
        var chart = makeChart()
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth, height: 1_100))
        let targets = try [1, 2].map { beat in
            try XCTUnwrap(FreeInkArticulationPlacement.target(
                measureID: measureID, beatIndex: beat, chart: chart, pageLayout: layout
            ))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = PDFChartExporter(exportDirectory: directory)
        let baseline = try await renderedPage(for: chart, exporter: exporter)
        chart.freeInkArticulations = zip([FreeInkArticulationKind.fermata, .accent], targets).map { kind, target in
            FreeInkArticulation(kind: kind, measureID: measureID, beatIndex: target.beatIndex,
                                sourceInkData: Data([0x01]), sourceCoordinateSpace: nil)
        }
        let withMarks = try await renderedPage(for: chart, exporter: exporter)
        let paper = layout.paperFrame
        for target in targets {
            let roi = target.markFrame.offsetBy(dx: -paper.minX, dy: -paper.minY)
            XCTAssertGreaterThan(try darkPixels(in: withMarks, rect: roi) - darkPixels(in: baseline, rect: roi), 4)
        }
    }

    @MainActor
    private func renderedPage(for chart: Chart, exporter: PDFChartExporter) async throws -> CGImage {
        let exported = try await exporter.exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exported.url))
        let page = try XCTUnwrap(document.page(at: 0))
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

    private func darkPixels(in image: CGImage, rect: CGRect) throws -> Int {
        let crop = try XCTUnwrap(image.cropping(to: rect.integral))
        let bytesPerRow = crop.width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * crop.height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        XCTAssertTrue(drawn)
        return stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 100 && pixels[$0 + 1] < 100 && pixels[$0 + 2] < 100
        }.count
    }
    #endif
}

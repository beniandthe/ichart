#if canImport(UIKit) && canImport(PencilKit)
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class CrossStyleAuditTests: XCTestCase {
    func testLegacyFreeInkExportUsesEditorGeometryAfterEngravingChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Legacy ink export audit", measureCount: 8, layoutStyle: style)
            chart.stylePreset = .plainWhite
            chart.setEngravingPreset(.wide)
            let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: CGSize(width: 932, height: 1_100))
            let sourceFrame = LeadSheetActiveInkScope.pageWritingFrame(for: sourceLayout)
            let sourceSystem = try XCTUnwrap(sourceLayout.systems.first)
            let sourceMeasure = try XCTUnwrap(sourceSystem.measures.first { $0.sourceMeasureID != nil })
            let x = sourceMeasure.staffFrame.minX + 18 - sourceFrame.minX
            let y = sourceMeasure.staffFrame.minY + 3 - sourceFrame.minY
            let sourceInk = drawing(at: CGPoint(x: x, y: y))
            let originalBytes = sourceInk.dataRepresentation()
            var legacySpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                for: sourceLayout, relativeTo: sourceFrame))
            legacySpace.engravingPreset = nil
            legacySpace.measureAnchors = legacySpace.measureAnchors?.map { anchor in
                var legacy = anchor
                legacy.staffFrame = nil
                return legacy
            }
            chart.pageHandwrittenNotationData = originalBytes
            chart.pageHandwrittenNotationCoordinateSpace = legacySpace
            chart.setEngravingPreset(.compact)
            let originalChart = chart

            // The visible editor resolves this metadata before projecting saved ink.
            let editorSourceSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageSourceCoordinateSpace(
                legacySpace, chart: chart))
            if style == .rhythmSectionSheet {
                XCTAssertEqual(editorSourceSpace.engravingPreset, .wide)
                XCTAssertNotNil(editorSourceSpace.measureAnchors?.first?.staffFrame)
                let targetLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                    pageSize: CGSize(width: 932, height: 1_100))
                let targetFrame = LeadSheetActiveInkScope.pageWritingFrame(for: targetLayout)
                let targetSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                    for: targetLayout, relativeTo: targetFrame))
                let editorInk = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(sourceInk,
                    sourceCoordinateSpace: editorSourceSpace, targetCoordinateSpace: targetSpace)
                XCTAssertNotEqual(editorInk.bounds, sourceInk.bounds,
                    "The Rhythm fixture must require a visible projection after the engraving change")
            } else {
                XCTAssertEqual(editorSourceSpace, legacySpace,
                    "Simple Chord paper ink has no staff geometry to infer")
            }

            let exporter = PDFChartExporter(exportDirectory: directory.appendingPathComponent(style.rawValue))
            let originalExport = try await exporter.exportPDF(for: chart)
            let originalPDF = try Data(contentsOf: originalExport.url)
            var editorEquivalentChart = chart
            editorEquivalentChart.pageHandwrittenNotationCoordinateSpace = editorSourceSpace
            let editorEquivalentExport = try await exporter.exportPDF(for: editorEquivalentChart)
            let editorEquivalentPDF = try Data(contentsOf: editorEquivalentExport.url)
            let actualImage = try image(of: originalPDF)
            let expectedImage = try image(of: editorEquivalentPDF)
            let renderedPage = XCTAttachment(image: actualImage)
            renderedPage.name = "\(style.rawValue) fixed legacy export"
            renderedPage.lifetime = .keepAlways
            add(renderedPage)
            let exportedFile = XCTAttachment(data: originalPDF, uniformTypeIdentifier: "com.adobe.pdf")
            exportedFile.name = "\(style.rawValue) fixed legacy export.pdf"
            exportedFile.lifetime = .keepAlways
            add(exportedFile)
            XCTAssertTrue(actualImage.pngData() == expectedImage.pngData(),
                "\(style.rawValue) PDF must use the same legacy staff recovery as the editor")
            if actualImage.pngData() != expectedImage.pngData() {
                let actual = XCTAttachment(image: actualImage)
                actual.name = "\(style.rawValue) actual legacy export"
                actual.lifetime = .keepAlways
                add(actual)
                let expected = XCTAttachment(image: expectedImage)
                expected.name = "\(style.rawValue) export using editor source geometry"
                expected.lifetime = .keepAlways
                add(expected)
            }
            XCTAssertEqual(chart, originalChart)
            XCTAssertEqual(chart.pageHandwrittenNotationData, originalBytes)
            XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, legacySpace)
        }
    }

    func testFileBackedFreeInkKeepsLegacyAndCompleteMetadataThroughEngravingAndPDFExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for usesLegacyMetadata in [true, false] {
                let context = "\(style.rawValue), legacy metadata \(usesLegacyMetadata)"
                let chart = try chartWithPageInk(style: style, usesLegacyMetadata: usesLegacyMetadata)
                let originalData = try XCTUnwrap(chart.pageHandwrittenNotationData)
                let originalSpace = try XCTUnwrap(chart.pageHandwrittenNotationCoordinateSpace)
                let fixtureDirectory = directory.appendingPathComponent(UUID().uuidString)
                let file = fixtureDirectory.appendingPathComponent("library-state.json")
                let repository = FileChartRepository(url: file)
                try repository.saveSnapshot(ChartLibrarySnapshot(charts: [chart],
                    selectedChartID: chart.id, entitlements: .free))
                let savedWide = try XCTUnwrap(try repository.loadSnapshot())
                var changed = try XCTUnwrap(savedWide.charts.first)
                XCTAssertEqual(savedWide.selectedChartID, chart.id, context)
                XCTAssertEqual(changed.pageHandwrittenNotationData, originalData, context)
                XCTAssertEqual(changed.pageHandwrittenNotationCoordinateSpace, originalSpace, context)
                changed.setEngravingPreset(.compact)
                try repository.saveSnapshot(ChartLibrarySnapshot(charts: [changed],
                    selectedChartID: chart.id, entitlements: .free))

                let reopened = try XCTUnwrap(try repository.loadSnapshot()?.charts.first)
                XCTAssertEqual(reopened.id, chart.id, context)
                XCTAssertEqual(reopened.engravingPreset, .compact, context)
                XCTAssertEqual(reopened.pageHandwrittenNotationData, originalData, context)
                XCTAssertEqual(reopened.pageHandwrittenNotationCoordinateSpace, originalSpace, context)
                XCTAssertEqual(reopened.measures, chart.measures, context)
                XCTAssertEqual(reopened.roadmapObjects, chart.roadmapObjects, context)
                let editorSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageSourceCoordinateSpace(
                    originalSpace, chart: reopened))
                if style == .simpleChordSheet || !usesLegacyMetadata {
                    XCTAssertEqual(editorSpace, originalSpace, context)
                } else {
                    XCTAssertEqual(editorSpace.engravingPreset, .wide, context)
                    XCTAssertTrue(editorSpace.measureAnchors?.allSatisfy { $0.staffFrame != nil } == true, context)
                }

                let libraryBeforeExport = try Data(contentsOf: file)
                let exporter = PDFChartExporter(exportDirectory: fixtureDirectory.appendingPathComponent("exports"))
                let actualExport = try await exporter.exportPDF(for: reopened)
                let actualPDF = try Data(contentsOf: actualExport.url)
                var editorEquivalent = reopened
                editorEquivalent.pageHandwrittenNotationCoordinateSpace = editorSpace
                let expectedExport = try await exporter.exportPDF(for: editorEquivalent)
                let expectedPDF = try Data(contentsOf: expectedExport.url)
                XCTAssertTrue(try image(of: actualPDF).pngData() == image(of: expectedPDF).pngData(), context)

                XCTAssertEqual(try Data(contentsOf: file), libraryBeforeExport,
                    "Export must leave the saved library byte-for-byte intact: \(context)")
                let afterExport = try XCTUnwrap(try repository.loadSnapshot()?.charts.first)
                XCTAssertEqual(afterExport.pageHandwrittenNotationData, originalData, context)
                XCTAssertEqual(afterExport.pageHandwrittenNotationCoordinateSpace, originalSpace, context)
            }
        }
    }

    private func chartWithPageInk(style: ChartLayoutStyle, usesLegacyMetadata: Bool) throws -> Chart {
        var chart = Chart.blank(title: "Saved ink export audit", measureCount: 8, layoutStyle: style)
        chart.stylePreset = .plainWhite
        chart.setEngravingPreset(.wide)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 932, height: 1_100))
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        let measure = try XCTUnwrap(layout.systems.first?.measures.first { $0.sourceMeasureID != nil })
        let ink = drawing(at: CGPoint(x: measure.staffFrame.minX + 18 - frame.minX,
            y: measure.staffFrame.minY + 3 - frame.minY))
        var space = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: layout, relativeTo: frame))
        if usesLegacyMetadata {
            space.engravingPreset = nil
            space.measureAnchors = space.measureAnchors?.map { anchor in
                var legacy = anchor
                legacy.staffFrame = nil
                return legacy
            }
        }
        chart.pageHandwrittenNotationData = ink.dataRepresentation()
        chart.pageHandwrittenNotationCoordinateSpace = space
        return chart
    }

    private func drawing(at origin: CGPoint) -> PKDrawing {
        let locations = [origin, CGPoint(x: origin.x + 10, y: origin.y - 6),
            CGPoint(x: origin.x + 20, y: origin.y + 4)]
        let path = PKStrokePath(controlPoints: locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: path, transform: .identity, mask: nil, randomSeed: 132)])
    }

    private func image(of data: Data) throws -> UIImage {
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
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
}
#endif

#if canImport(UIKit)
import CoreGraphics
import Foundation
import PDFKit
import UIKit
import XCTest
@testable import iChart

final class FlexibleEndingRendererTests: XCTestCase {
    @MainActor
    func testLongEndingLabelUsesTheFullProvidedWidth() throws {
        let chart = proofAppearanceChart()
        let ending = LeadSheetEndingLayout(
            roadmapObjectID: UUID(), systemIndex: 0, type: .ending1,
            text: "1, 2, 3, 4, 5 — last time only",
            frame: CGRect(x: 20, y: 20, width: 360, height: 70),
            showsText: true, showsLeadingHook: true, showsTrailingHook: true,
            labelFrame: CGRect(x: 26, y: 27, width: 348, height: 54),
            labelFontSize: 20, labelLineCount: 1
        )
        let image = endingImage(chart: chart, ending: ending, size: CGSize(width: 410, height: 120))

        XCTAssertGreaterThan(
            try darkPixelCount(in: image, region: CGRect(x: 110, y: 28, width: 255, height: 45)),
            0,
            "Ending text must remain visible beyond the old 70-point label cap."
        )
        attach(image, name: "flexible-ending-full-width-label")
    }

    @MainActor
    func testEndingInstructionWrapsIntoTheProvidedMultilineArea() throws {
        let chart = proofAppearanceChart()
        let ending = LeadSheetEndingLayout(
            roadmapObjectID: UUID(), systemIndex: 0, type: .ending2,
            text: "1–3, 5 — repeat softly, then follow the conductor",
            frame: CGRect(x: 20, y: 20, width: 128, height: 125),
            showsText: true, showsLeadingHook: true, showsTrailingHook: false,
            labelFrame: CGRect(x: 26, y: 27, width: 116, height: 112),
            labelFontSize: 16, labelLineCount: 4
        )
        let image = endingImage(chart: chart, ending: ending, size: CGSize(width: 180, height: 170))

        XCTAssertGreaterThan(try darkPixelCount(in: image, region: CGRect(x: 27, y: 29, width: 113, height: 25)), 0)
        XCTAssertGreaterThan(
            try darkPixelCount(in: image, region: CGRect(x: 27, y: 60, width: 113, height: 77)),
            0,
            "The instruction must wrap instead of clipping to its first line."
        )
        attach(image, name: "flexible-ending-wrapped-instruction")
    }

    @MainActor
    func testOpenAndClosedBracketsRetainTheirLeadingHook() throws {
        var chart = proofAppearanceChart()
        chart.notationReadability = .performance
        let frame = CGRect(x: 20, y: 20, width: 200, height: 50)
        let closed = LeadSheetEndingLayout(
            roadmapObjectID: UUID(), systemIndex: 0, type: .ending1, text: "1–3, 5",
            frame: frame, showsText: false, showsLeadingHook: true, showsTrailingHook: true
        )
        var open = closed
        open.showsTrailingHook = false
        let closedImage = endingImage(chart: chart, ending: closed, size: CGSize(width: 250, height: 100))
        let openImage = endingImage(chart: chart, ending: open, size: CGSize(width: 250, height: 100))
        let leadingHookRegion = CGRect(x: 18, y: 45, width: 5, height: 20)
        let trailingHookRegion = CGRect(x: 218, y: 45, width: 5, height: 20)

        XCTAssertGreaterThan(try darkPixelCount(in: closedImage, region: leadingHookRegion), 0)
        XCTAssertGreaterThan(try darkPixelCount(in: openImage, region: leadingHookRegion), 0)
        XCTAssertGreaterThan(try darkPixelCount(in: closedImage, region: trailingHookRegion), 0)
        XCTAssertEqual(try darkPixelCount(in: openImage, region: trailingHookRegion), 0)
        attach(closedImage, name: "flexible-ending-closed-bracket")
        attach(openImage, name: "flexible-ending-open-bracket")
    }

    @MainActor
    func testFlexibleEndingLabelsExportAcrossAllLayoutsAndEndStyles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = PDFChartExporter(exportDirectory: directory)
        let labels = [
            "1, 2, 3, 4, 5",
            "1–3, 5",
            "Repeat quietly until the conductor cues the final ending"
        ]

        for layoutStyle in ChartLayoutStyle.allCases {
            for endStyle in [EndingEndStyle.closed, .open] {
                let chart = try flexibleEndingProofChart(layoutStyle: layoutStyle, endStyle: endStyle, labels: labels)
                let name = "flexible-endings-\(layoutStyle.rawValue)-\(endStyle.rawValue)"
                let exported = try await exporter.exportPDF(for: chart)
                let document = try XCTUnwrap(PDFDocument(url: exported.url), name)
                let text = normalizedWhitespace(document.string ?? "")

                XCTAssertEqual(document.pageCount, exported.pageCount, name)
                XCTAssertGreaterThan(exported.fileSizeBytes, 2_000, name)
                for label in labels {
                    XCTAssertTrue(text.contains(label), "Expected the complete ending label in \(name). Extracted text: \(text)")
                }
                let pageBounds = try XCTUnwrap(document.page(at: 0), name).bounds(for: .mediaBox)
                let pageLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageBounds.size)
                let segments = pageLayout.systems.flatMap(\.endingLayouts)
                XCTAssertEqual(Set(segments.filter(\.showsText).map(\.text)), Set(labels), name)
                XCTAssertEqual(segments.filter(\.showsTrailingHook).count, endStyle == .closed ? labels.count : 0, name)
                XCTAssertEqual(segments.filter(\.showsLeadingHook).count, labels.count, name)
                XCTAssertTrue(segments.filter(\.showsText).allSatisfy { !$0.labelFrame.isEmpty && $0.labelFontSize > 0 }, name)

                let pdf = XCTAttachment(data: try Data(contentsOf: exported.url), uniformTypeIdentifier: "com.adobe.pdf")
                pdf.name = name
                pdf.lifetime = .keepAlways
                add(pdf)
                for pageIndex in 0..<document.pageCount {
                    attach(pageImage(try XCTUnwrap(document.page(at: pageIndex))), name: "\(name)-page-\(pageIndex + 1)")
                }
            }
        }
    }

    private func proofAppearanceChart() -> Chart {
        var chart = Chart.blank(title: "Flexible Endings Proof", layoutStyle: .simpleChordSheet)
        chart.stylePreset = .plainWhite
        chart.engravingPreset = .balanced
        chart.notationFont = .petaluma
        chart.typography = .default(for: .petaluma)
        return chart
    }

    private func flexibleEndingProofChart(
        layoutStyle: ChartLayoutStyle,
        endStyle: EndingEndStyle,
        labels: [String]
    ) throws -> Chart {
        var chart = Chart.blank(title: "Flexible Endings Proof", measureCount: 8, layoutStyle: layoutStyle)
        chart.stylePreset = .plainWhite
        chart.engravingPreset = .balanced
        chart.notationFont = .petaluma
        chart.typography = .default(for: .petaluma)
        chart.notationReadability = .performance
        chart.repeatWings = true
        let symbols = try ["Cmaj7", "G7"].map(ChordSymbolParser.parse)
        for systemIndex in chart.systems.indices {
            for measureIndex in chart.systems[systemIndex].measures.indices {
                chart.systems[systemIndex].measures[measureIndex].chordEvents = symbols.enumerated().map { offset, symbol in
                    ChordEvent(
                        id: UUID(), symbol: symbol,
                        startPosition: BeatPosition(beat: offset * 2 + 1, subdivision: 0, subdivisionsPerBeat: 2),
                        duration: .half, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
                        rawInput: symbol.displayText
                    )
                }
            }
        }
        let ids = chart.measures.map(\.id)
        if layoutStyle == .simpleChordSheet {
            for id in ids { _ = chart.setMeasureManualLayoutWidth(320, for: id) }
        }
        if layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet {
            for index in [2, 4, 6] { XCTAssertTrue(chart.insertSystemBreak(before: ids[index])) }
        }
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[3]))
        for (index, label) in labels.enumerated() {
            _ = try XCTUnwrap(chart.addEndingSpan(
                index == 1 ? .ending2 : .ending1,
                startMeasureID: ids[index * 2], endMeasureID: ids[index * 2],
                displayText: label, endStyle: endStyle
            ))
        }
        return chart
    }

    private func normalizedWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    @MainActor
    private func endingImage(chart: Chart, ending: LeadSheetEndingLayout, size: CGSize) -> UIImage {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            LeadSheetNotationRenderer(chart: chart).drawEnding(ending)
        }
    }

    private func darkPixelCount(in image: UIImage, region: CGRect) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage?.cropping(to: region.integral))
        var pixels = [UInt8](repeating: 255, count: cgImage.width * cgImage.height)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return true
        }
        XCTAssertTrue(didDraw)
        return pixels.filter { $0 < 100 }.count
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func pageImage(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
}
#endif

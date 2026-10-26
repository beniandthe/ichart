import CoreGraphics
import Foundation
import XCTest
@testable import iChart

#if canImport(UIKit)
import PDFKit
import SwiftUI
import UIKit
#endif

final class NotationReadabilityRendererTests: XCTestCase {
    private let layoutStyles: [ChartLayoutStyle] = [.simpleChordSheet, .leadSheet, .rhythmSectionSheet]

    func testStandardRepeatsKeepExistingBarAndDotDimensions() {
        for layoutStyle in layoutStyles {
            for engraving in EngravingPreset.allCases {
                var chart = Chart.blank(title: "Original repeats", layoutStyle: layoutStyle)
                chart.engravingPreset = engraving
                let staffHeight: CGFloat = 84
                let staffSpace: CGFloat = 20
                let metrics = LeadSheetRepeatReadabilityMetrics(chart: chart, staffHeight: staffHeight)

                XCTAssertEqual(metrics.lineWidth, LeadSheetBarlineMetrics.repeatLineWidth(
                    staffSpace: staffSpace, strokeScale: engraving.strokeScale, layoutStyle: layoutStyle
                ), accuracy: 0.001)
                XCTAssertEqual(metrics.separation, LeadSheetBarlineMetrics.repeatSeparation(
                    staffSpace: staffSpace, layoutStyle: layoutStyle
                ), accuracy: 0.001)
                XCTAssertEqual(metrics.dotRadius, LeadSheetBarlineMetrics.repeatDotRadius(
                    staffSpace: staffSpace, layoutStyle: layoutStyle
                ), accuracy: 0.001)
                XCTAssertEqual(metrics.wingLength, 0)
                XCTAssertEqual(metrics.verticalOutset, 0)
            }
        }
    }

    func testPerformanceRepeatsStrengthenBarsAndDotsIndependentlyFromGlobalEngraving() {
        for layoutStyle in layoutStyles {
            var chart = Chart.blank(title: "Performance repeats", layoutStyle: layoutStyle)
            chart.engravingPreset = .balanced
            let standard = LeadSheetRepeatReadabilityMetrics(chart: chart, staffHeight: 84)
            chart.notationReadability = .performance
            let performance = LeadSheetRepeatReadabilityMetrics(chart: chart, staffHeight: 84)

            XCTAssertGreaterThan(performance.lineWidth, standard.lineWidth)
            XCTAssertGreaterThan(performance.dotRadius, standard.dotRadius)
            XCTAssertGreaterThan(performance.horizontalExtent, standard.horizontalExtent)
            XCTAssertEqual(chart.engravingPreset, .balanced)
            XCTAssertEqual(performance.wingLength, 0, "Repeat weight does not implicitly enable wings.")
        }
    }

    func testRepeatDotsClearBarsForEveryReadabilityAndEngravingCombination() {
        for layoutStyle in layoutStyles {
            for engraving in EngravingPreset.allCases {
                for readability in NotationReadabilityPreset.allCases {
                    for staffHeight in [CGFloat(28), CGFloat(46), CGFloat(100)] {
                        var chart = Chart.blank(title: "Repeat clearance", layoutStyle: layoutStyle)
                        chart.engravingPreset = engraving
                        chart.notationReadability = readability
                        chart.repeatWings = true
                        let metrics = LeadSheetRepeatReadabilityMetrics(chart: chart, staffHeight: staffHeight)

                        XCTAssertGreaterThan(metrics.dotOffset - metrics.dotRadius, metrics.lineWidth / 2)
                        XCTAssertGreaterThan(metrics.separation, metrics.lineWidth)
                        XCTAssertGreaterThanOrEqual(
                            metrics.horizontalExtent,
                            metrics.separation / 2 + metrics.dotOffset + metrics.dotRadius
                        )
                        XCTAssertGreaterThan(metrics.verticalOutset, metrics.wingHeight)
                    }
                }
            }
        }
    }

#if canImport(UIKit)
    @MainActor
    func testWingedRepeatsDrawAboveAndBelowTheStaffAndPreserveBothDirections() throws {
        let staffFrame = CGRect(x: 80, y: 35, width: 16, height: 84)
        var chart = Chart.blank(title: "Wing directions", layoutStyle: .simpleChordSheet)
        chart.stylePreset = .plainWhite
        chart.notationReadability = .performance
        let straight = repeatImage(chart: chart, edges: [.leading, .trailing], frame: staffFrame)
        chart.repeatWings = true
        let start = repeatImage(chart: chart, edges: [.leading], frame: staffFrame)
        let end = repeatImage(chart: chart, edges: [.trailing], frame: staffFrame)
        let combined = repeatImage(chart: chart, edges: [.leading, .trailing], frame: staffFrame)
        let topBand = CGRect(x: 55, y: 20, width: 66, height: 12)
        let bottomBand = CGRect(x: 55, y: 122, width: 66, height: 12)
        let leftWing = CGRect(x: staffFrame.midX - 22, y: 20, width: 16, height: 12)
        let rightWing = CGRect(x: staffFrame.midX + 6, y: 20, width: 16, height: 12)

        XCTAssertEqual(try darkPixelCount(in: straight, region: topBand), 0)
        XCTAssertEqual(try darkPixelCount(in: straight, region: bottomBand), 0)
        XCTAssertGreaterThan(try darkPixelCount(in: combined, region: topBand), 0)
        XCTAssertGreaterThan(try darkPixelCount(in: combined, region: bottomBand), 0)
        XCTAssertGreaterThan(try darkPixelCount(in: start, region: rightWing), 0)
        XCTAssertEqual(try darkPixelCount(in: start, region: leftWing), 0)
        XCTAssertGreaterThan(try darkPixelCount(in: end, region: leftWing), 0)
        XCTAssertEqual(try darkPixelCount(in: end, region: rightWing), 0)
        XCTAssertGreaterThan(try darkPixelCount(in: combined, region: leftWing), 0)
        XCTAssertGreaterThan(try darkPixelCount(in: combined, region: rightWing), 0)

        attach(straight, name: "repeat-performance-straight")
        attach(start, name: "repeat-winged-start")
        attach(end, name: "repeat-winged-end")
        attach(combined, name: "repeat-winged-combined")
    }

    @MainActor
    func testPerformanceRepeatRenderingHasMoreVisibleInkThanStandard() throws {
        let frame = CGRect(x: 80, y: 35, width: 16, height: 84)
        var chart = Chart.blank(title: "Repeat emphasis", layoutStyle: .simpleChordSheet)
        chart.stylePreset = .plainWhite
        let standard = repeatImage(chart: chart, edges: [.leading, .trailing], frame: frame)
        chart.notationReadability = .performance
        let performance = repeatImage(chart: chart, edges: [.leading, .trailing], frame: frame)
        let region = CGRect(x: 50, y: 15, width: 76, height: 124)

        XCTAssertGreaterThan(
            try darkPixelCount(in: performance, region: region),
            try darkPixelCount(in: standard, region: region)
        )
        attach(standard, name: "repeat-standard-straight")
        attach(performance, name: "repeat-performance-straight-emphasis")
    }

    @MainActor
    func testPerformanceEmphasizesPetalumaEndingAndNavigationLabels() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        XCTAssertNotNil(UIFont(name: "PetalumaText", size: 20), "Exercise the bundled handwriting family rather than a system-font fallback.")
        var chart = Chart.blank(title: "Petaluma navigation", layoutStyle: .simpleChordSheet)
        chart.stylePreset = .plainWhite
        chart.notationFont = .petaluma
        chart.typography = .default(for: .petaluma)
        let standard = navigationLabelImage(chart: chart)
        chart.notationReadability = .performance
        let performance = navigationLabelImage(chart: chart)
        let endingNumberRegion = CGRect(x: 28, y: 26, width: 65, height: 30)
        let navigationRegion = CGRect(x: 25, y: 80, width: 180, height: 50)

        XCTAssertGreaterThan(
            try darkPixelCount(in: performance, region: endingNumberRegion),
            try darkPixelCount(in: standard, region: endingNumberRegion)
        )
        // The marker has the same explicit scale in both images. This checks
        // actual outline emphasis even when Petaluma has no separate bold face.
        XCTAssertGreaterThan(
            try darkPixelCount(in: performance, region: navigationRegion),
            try darkPixelCount(in: standard, region: navigationRegion)
        )
        attach(standard, name: "petaluma-navigation-standard")
        attach(performance, name: "petaluma-navigation-performance")
    }

    @MainActor
    func testReadabilitySettingsShowTheActualChartPreview() throws {
        for readability in NotationReadabilityPreset.allCases {
            var chart = try navigationProofChart(layoutStyle: .simpleChordSheet)
            chart.notationReadability = readability
            chart.repeatWings = readability == .performance
            let host = UIHostingController(rootView: ChartAppearanceSheetView(chart: .constant(chart), panel: .engraving))
            let frame = CGRect(x: 0, y: 0, width: 560, height: 900)
            let window: UIWindow
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: frame)
            }
            window.frame = frame
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.frame = window.bounds
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            var drewHierarchy = false
            let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { _ in
                drewHierarchy = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(drewHierarchy, "The live settings view must render before retaining its screenshot.")
            attach(image, name: "notation-readability-settings-\(readability.rawValue)")
        }
    }

    @MainActor
    func testReadableNavigationExportsAcrossAllChartLayouts() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let exporter = PDFChartExporter(exportDirectory: output)

        for layoutStyle in layoutStyles {
            for readability in NotationReadabilityPreset.allCases {
                var chart = try navigationProofChart(layoutStyle: layoutStyle)
                chart.notationReadability = readability
                chart.repeatWings = readability == .performance
                let name = "readability-\(layoutStyle.rawValue)-\(readability.rawValue)"
                let exported = try await exporter.exportPDF(for: chart)
                let document = try XCTUnwrap(PDFDocument(url: exported.url), name)
                let page = try XCTUnwrap(document.page(at: 0), name)
                let text = document.string ?? ""

                XCTAssertEqual(document.pageCount, exported.pageCount, name)
                XCTAssertGreaterThan(document.pageCount, 0, name)
                XCTAssertGreaterThan(exported.fileSizeBytes, 2_000, name)
                XCTAssertTrue(text.uppercased().contains("NOTATION READABILITY PROOF"), name)
                XCTAssertTrue(text.contains("1."), name)
                XCTAssertTrue(text.contains("2."), name)
                XCTAssertPDFExtractedTextContains(text, visibleNotationText: "D.S. al \(NotationGlyphCatalog.coda)", name)
                XCTAssertTrue(text.uppercased().contains("FINE"), name)
                for chord in chart.measures[0].chordEvents {
                    XCTAssertPDFExtractedTextContains(text, visibleChordText: chord.symbol.displayText, name)
                }

                let pdfAttachment = XCTAttachment(data: try Data(contentsOf: exported.url), uniformTypeIdentifier: "com.adobe.pdf")
                pdfAttachment.name = name
                pdfAttachment.lifetime = .keepAlways
                add(pdfAttachment)
                attach(pageImage(page), name: "\(name)-page-1")
            }
        }
    }

    @MainActor
    private func repeatImage(chart: Chart, edges: [LeadSheetRepeatMarkerLayout.Edge], frame: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 176, height: 154), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 176, height: 154))
            let markers = edges.map { LeadSheetRepeatMarkerLayout(roadmapObjectID: UUID(), edge: $0, frame: frame) }
            LeadSheetNotationRenderer(chart: chart).drawRepeatBoundary(markers)
        }
    }

    @MainActor
    private func navigationLabelImage(chart: Chart) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 150), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 150))
            let renderer = LeadSheetNotationRenderer(chart: chart)
            renderer.drawEnding(LeadSheetEndingLayout(
                roadmapObjectID: UUID(), systemIndex: 0, type: .ending1, text: "1.",
                frame: CGRect(x: 20, y: 20, width: 190, height: 36),
                showsText: true, showsLeadingHook: true, showsTrailingHook: true
            ))
            let markerFrame = CGRect(x: 25, y: 80, width: 180, height: 50)
            renderer.drawRoadmapMarker(LeadSheetRoadmapMarkerLayout(
                roadmapObjectID: UUID(), type: .dsAlCoda, text: RoadmapType.dsAlCoda.defaultDisplayText,
                frame: markerFrame, movementFrame: markerFrame,
                anchorMeasureID: chart.measures[0].id, scale: 1
            ))
        }
    }

    private func darkPixelCount(in image: UIImage, region: CGRect) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage?.cropping(to: region.integral))
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
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

    private func navigationProofChart(layoutStyle: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Notation Readability Proof", measureCount: 8, layoutStyle: layoutStyle)
        chart.stylePreset = .plainWhite
        let symbols = try ["Cmaj7", "Am7", "Dm7", "G7"].map(ChordSymbolParser.parse)
        for systemIndex in chart.systems.indices {
            for measureIndex in chart.systems[systemIndex].measures.indices {
                let measureSymbols = layoutStyle == .simpleChordSheet ? symbols : [symbols[0], symbols[3]]
                chart.systems[systemIndex].measures[measureIndex].chordEvents = measureSymbols.enumerated().map { offset, symbol in
                    ChordEvent(
                        id: UUID(), symbol: symbol,
                        startPosition: BeatPosition(beat: offset * (4 / measureSymbols.count) + 1, subdivision: 0, subdivisionsPerBeat: 2),
                        duration: .quarter, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
                        rawInput: symbol.displayText
                    )
                }
            }
        }
        let ids = chart.measures.map(\.id)
        if layoutStyle == .simpleChordSheet {
            for id in ids {
                XCTAssertEqual(
                    chart.setMeasureManualLayoutWidth(320, for: id),
                    320,
                    "Give the four-chord visual proof enough room without changing production placement."
                )
            }
        }
        if layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet {
            for index in [2, 4, 6] {
                XCTAssertTrue(chart.insertSystemBreak(before: ids[index]), "Keep the export proof at two readable measures per row.")
            }
        }
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[3]))
        _ = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[3], endMeasureID: ids[3]))
        _ = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[4], endMeasureID: ids[4]))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: ids[0]))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.dsAlCoda, anchorMeasureID: ids[5]))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: ids[6]))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: ids[7]))
        return chart
    }
#endif
}

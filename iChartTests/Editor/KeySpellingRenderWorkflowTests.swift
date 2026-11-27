#if canImport(UIKit) && canImport(PencilKit)
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class KeySpellingRenderWorkflowTests: XCTestCase {
    private let pageSize = CGSize(width: 1180, height: 1500)
    private let expectedTexts = [
        "Db", "Bb-", "Gb", "Eb-",
        "G-", "F#°", "D7/F#",
        "E#/B#", "G#/B#",
        "Cb/Fb"
    ]

    func testKeyAwareSpellingsRenderSaveAndReopenInSimpleChordSheet() async throws {
        try await assertRenderedWorkflow(.simpleChordSheet)
    }

    func testKeyAwareSpellingsRenderSaveAndReopenInRhythmSectionSheet() async throws {
        try await assertRenderedWorkflow(.rhythmSectionSheet)
    }

    private func assertRenderedWorkflow(_ style: ChartLayoutStyle) async throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let original = try chartFixture(style)
        let originalEvents = original.measures.flatMap(\.chordEvents)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: original, pageSize: pageSize)
        try assertSpellings(original, layout: layout)

        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        canvas.recognizesChordInk = false
        canvas.chart = original
        canvas.interactionMode = .browse
        canvas.overrideUserInterfaceStyle = .light
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        let native = imageOfCanvas(canvas)
        attach(native, name: "key-spelling-\(style.rawValue)-native")
        for chord in layout.systems.flatMap(\.measures).flatMap(\.chordLayouts) {
            XCTAssertGreaterThan(try darkPixelCount(native, in: chord.frame.insetBy(dx: -3, dy: -3)), 8,
                "The real canvas must paint the corrected chord glyph")
        }
        XCTAssertEqual(canvas.chart, original,
            "Displaying spelling in the effective key must retain saved recognition and ink")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        let library = ChartLibraryStore(charts: [original], selectedChartID: original.id, repository: repository)
        try repository.saveSnapshot(library.snapshot)
        let snapshot = try XCTUnwrap(repository.loadSnapshot())
        XCTAssertEqual(snapshot.selectedChartID, original.id)
        let reopened = try XCTUnwrap(snapshot.charts.first)
        XCTAssertEqual(reopened, original)
        XCTAssertEqual(reopened.measures.flatMap(\.chordEvents), originalEvents)
        try assertSpellings(reopened, layout: LeadSheetPageLayoutEngine.pageLayout(
            for: reopened, pageSize: pageSize))

        let exported = try await PDFChartExporter(exportDirectory: directory.appendingPathComponent("PDF"))
            .exportPDF(for: reopened)
        let bytes = try Data(contentsOf: exported.url)
        let document = try XCTUnwrap(PDFDocument(data: bytes))
        let text = try XCTUnwrap(document.string)
        for expected in expectedTexts {
            let symbol = try ChordSymbolParser.parse(expected)
            let literalText = ChartTypographyResolver.chordTokens(for: symbol)
                .filter { $0.role != .musicSymbol }.map(\.text).joined()
            XCTAssertPDFExtractedTextContains(text, visibleChordText: literalText,
                "The actual export must retain the key-aware root, suffix, and slash bass for \(expected)")
        }
        let pdf = XCTAttachment(data: bytes, uniformTypeIdentifier: "com.adobe.pdf")
        pdf.name = "key-spelling-\(style.rawValue).pdf"
        pdf.lifetime = .keepAlways
        add(pdf)
        for pageIndex in 0..<document.pageCount {
            attach(imageOfPDFPage(try XCTUnwrap(document.page(at: pageIndex))),
                name: "key-spelling-\(style.rawValue)-pdf-\(pageIndex + 1)")
        }
        XCTAssertEqual(original.measures.flatMap(\.chordEvents), originalEvents)
    }

    private func chartFixture(_ style: ChartLayoutStyle) throws -> Chart {
        let stored = ["C#", "A#m", "F#", "D#m", "Gm", "F#dim", "D7/F#", "F/C", "G#/C", "B/E"]
        var chart = Chart.blank(title: "Key spelling examples", key: .dFlatMajor,
            measureCount: stored.count, layoutStyle: style)
        chart.setEngravingPreset(.compact)
        let sourceInk = sampleInk()
        for (index, token) in stored.enumerated() {
            let explicit = index == 2
            var event = ChordEvent(id: UUID(), symbol: try ChordSymbolParser.parse(token),
                spellingIntent: explicit ? .explicit : .automatic,
                spellingOverrideSource: explicit ? .userSelection : nil,
                startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
                duration: .slash, rhythmPlacement: .inline, tieOut: false, hitStyle: .none,
                rawInput: token, sourceInkData: sourceInk,
                sourceCandidateSignature: [token], sourceRecognitionPipelineVersion: "generic-render-fixture")
            // The legacy userSelection record has no key binding. It must
            // follow the current context while its source spelling is retained.
            event.spellingOverrideKey = nil
            chart.systems[0].measures[index].chordEvents = [event]
        }
        let ids = chart.measures.map(\.id)
        let rowRanges = [0..<4, 4..<7, 7..<9, 9..<10]
        let rows = rowRanges.map { range in
            Dictionary(uniqueKeysWithValues: range.enumerated().map { column, index in
                (ids[index], Double(column) / Double(range.count)...Double(column + 1) / Double(range.count))
            })
        }
        XCTAssertTrue(chart.adoptPaperMeasureLayout(rows))
        chart.keyChanges = [
            KeyChange(measureID: ids[4], key: .eFlatMajor),
            KeyChange(measureID: ids[7], key: .cSharpMajor),
            KeyChange(measureID: ids[9], key: .cFlatMajor)
        ]
        return chart
    }

    private func assertSpellings(_ chart: Chart, layout: LeadSheetPageLayout) throws {
        XCTAssertEqual(chart.measures.count, expectedTexts.count)
        let glyphs = Dictionary(uniqueKeysWithValues: layout.systems.flatMap(\.measures)
            .flatMap(\.chordLayouts).map { ($0.id, $0) })
        for (measure, expectedText) in zip(chart.measures, expectedTexts) {
            let chord = try XCTUnwrap(measure.chordEvents.first)
            let expected = try ChordSymbolParser.parse(expectedText)
            XCTAssertEqual(chart.displayedChordSymbol(for: chord, in: measure.id), expected,
                "The effective key of measure \(measure.index) must choose \(expectedText)")
            let glyph = try XCTUnwrap(glyphs[chord.id])
            XCTAssertEqual(glyph.symbol, expected)
            XCTAssertEqual(glyph.text, expected.displayText)
        }
        // These functional chromatic spellings retain the sharp letter.
        XCTAssertEqual(try XCTUnwrap(chart.measures[5].chordEvents.first)
            .symbol.root, .f)
        XCTAssertEqual(try XCTUnwrap(chart.measures[6].chordEvents.first)
            .symbol.slashBass, "F#")
    }

    private func sampleInk() -> Data {
        let points = [
            PKStrokePoint(location: CGPoint(x: 2, y: 18), timeOffset: 0, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 0.5, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 12, y: 3), timeOffset: 0.1, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 0.5, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 22, y: 18), timeOffset: 0.2, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 0.5, azimuth: 0, altitude: .pi / 2)
        ]
        let stroke = PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1)))
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    private func imageOfCanvas(_ canvas: LeadSheetCanvasUIKitView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: pageSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))
            canvas.draw(canvas.bounds)
        }
    }

    private func imageOfPDFPage(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private func darkPixelCount(_ image: UIImage, in frame: CGRect) throws -> Int {
        let scaled = frame.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: scaled))
        var pixels = [UInt8](repeating: 255, count: crop.width * crop.height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        XCTAssertTrue(drew)
        return pixels.filter { $0 < 100 }.count
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif

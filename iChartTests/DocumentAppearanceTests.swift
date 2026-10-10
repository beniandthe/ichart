#if canImport(UIKit)
import Combine
import PDFKit
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class DocumentAppearanceTests: XCTestCase {
    private let appearanceKey = "iChartHomeAppearanceMode"

    func testPersistedAppearanceResolvesExplicitModesAndFallsBackToLight() {
        let light = IChartAppAppearance(persistedValue: "light")
        let dark = IChartAppAppearance(persistedValue: "dark")
        XCTAssertEqual(light, .light)
        XCTAssertEqual(light.colorScheme, .light)
        XCTAssertFalse(light.isDark)
        XCTAssertEqual(dark, .dark)
        XCTAssertEqual(dark.colorScheme, .dark)
        XCTAssertTrue(dark.isDark)

        for invalidValue in ["", "system", "DARK", "unknown"] {
            let fallback = IChartAppAppearance(persistedValue: invalidValue)
            XCTAssertEqual(fallback, .light, invalidValue)
            XCTAssertEqual(fallback.colorScheme, .light, invalidValue)
            XCTAssertFalse(fallback.isDark, invalidValue)
        }
    }

    func testMountedNativePaperInvertsWithReadableMarksWithoutRecreatingSource() async throws {
        let model = DocumentAppearanceModel()
        let recorder = NativeDocumentRecorder()
        let host = UIHostingController(rootView: NativeDocumentHarness(model: model, recorder: recorder))
        let window = try makeWindow(host: host)
        defer { window.close() }
        try await settle(window)
        let nativeView = try XCTUnwrap(recorder.views.first)
        let originalBounds = nativeView.bounds

        for isDark in [false, true, false] {
            model.isDark = isDark
            try await settle(window)
            let image = try screenshot(window, name: "native-document-\(isDark ? "dark" : "light")")
            try assertPaperAndMark(
                image,
                paperPoint: nativeView.convert(CGPoint(x: 24, y: 24), to: window),
                markPoint: nativeView.convert(CGPoint(x: 160, y: 120), to: window),
                isDark: isDark
            )
            XCTAssertEqual(recorder.views.count, 1, "Changing display appearance must retain the native drawing view")
            XCTAssertTrue(descendants(window).contains { $0 === nativeView })
            XCTAssertEqual(nativeView.bounds, originalBounds, "Display appearance must preserve source geometry")
            XCTAssertEqual(nativeView.paperColor, .white)
            XCTAssertEqual(nativeView.markColor, .black)
            let target = nativeView.convert(CGPoint(x: 160, y: 120), to: window)
            XCTAssertTrue(window.hitTest(target, with: nil) === nativeView,
                "The display overlay must not intercept the document's touch target")
        }
    }

    func testSavedAppAppearanceControlsMountedDocumentIndependentlyOfSystemAppearance() async throws {
        let previousValue = UserDefaults.standard.object(forKey: appearanceKey)
        defer { restoreAppearance(previousValue) }
        UserDefaults.standard.set("light", forKey: appearanceKey)
        let recorder = NativeDocumentRecorder()
        let host = UIHostingController(rootView: PersistedNativeDocumentHarness(recorder: recorder))
        let window = try makeWindow(host: host)
        window.overrideUserInterfaceStyle = .dark
        defer { window.close() }
        try await settle(window)
        let nativeView = try XCTUnwrap(recorder.views.first)

        for persistedValue in ["light", "dark", "invalid"] {
            UserDefaults.standard.set(persistedValue, forKey: appearanceKey)
            try await settle(window)
            let image = try screenshot(window, name: "stored-appearance-\(persistedValue)-system-dark")
            try assertPaperAndMark(
                image,
                paperPoint: nativeView.convert(CGPoint(x: 24, y: 24), to: window),
                markPoint: nativeView.convert(CGPoint(x: 160, y: 120), to: window),
                isDark: persistedValue == "dark"
            )
            XCTAssertEqual(recorder.views.count, 1)
            XCTAssertTrue(descendants(window).contains { $0 === nativeView })
        }
    }

    func testMountedPencilKitInkRemainsVisibleWithoutChangingDrawingOrCanvas() async throws {
        let model = DocumentAppearanceModel()
        let recorder = PencilKitDocumentRecorder()
        let host = UIHostingController(rootView: PencilKitDocumentHarness(model: model, recorder: recorder))
        let window = try makeWindow(host: host)
        defer { window.close() }
        try await settle(window, frames: 12)
        let canvas = try XCTUnwrap(recorder.canvases.first)
        let originalBytes = canvas.drawing.dataRepresentation()
        let originalBounds = canvas.bounds
        let originalTool = try XCTUnwrap(canvas.tool as? PKInkingTool)
        XCTAssertEqual(canvas.drawing.strokes.count, 1)

        for isDark in [false, true, false] {
            model.isDark = isDark
            // PencilKit commits its rendered ink asynchronously. This bounded
            // wait captures resident ink, without generating Pencil events.
            try await settle(window, frames: 12)
            let image = try screenshot(window, name: "pencilkit-document-\(isDark ? "dark" : "light")")
            try assertPaperAndMark(
                image,
                paperPoint: canvas.convert(CGPoint(x: 24, y: 24), to: window),
                markPoint: canvas.convert(CGPoint(x: 160, y: 120), to: window),
                isDark: isDark
            )
            XCTAssertEqual(recorder.canvases.count, 1, "Changing appearance must preserve the live PencilKit canvas")
            XCTAssertTrue(descendants(window).contains { $0 === canvas })
            XCTAssertEqual(canvas.drawing.dataRepresentation(), originalBytes,
                "Changing display appearance must preserve the exact source drawing bytes")
            XCTAssertEqual(canvas.bounds, originalBounds)
            XCTAssertEqual(canvas.overrideUserInterfaceStyle, .light)
            XCTAssertEqual(canvas.traitCollection.userInterfaceStyle, .light)
            XCTAssertEqual(canvas.backgroundColor, .clear)
            XCTAssertFalse(canvas.isOpaque)
            let tool = try XCTUnwrap(canvas.tool as? PKInkingTool)
            XCTAssertEqual(tool.inkType, originalTool.inkType)
            XCTAssertEqual(tool.width, originalTool.width, accuracy: 0.001)
            XCTAssertEqual(tool.color, originalTool.color)
            XCTAssertTrue(LeadSheetPersistentInkColorPolicy.matchesPersistentInkColor(tool.color))
            XCTAssertEqual(canvas.drawingPolicy, .anyInput)
            XCTAssertTrue(canvas.isUserInteractionEnabled)
            let target = canvas.convert(CGPoint(x: 160, y: 120), to: window)
            let hit = try XCTUnwrap(window.hitTest(target, with: nil))
            XCTAssertTrue(hit === canvas || hit.isDescendant(of: canvas),
                "The display overlay must preserve the native canvas's input target")
        }
    }

    func testMountedPDFPreviewInvertsWithoutReloadingDocumentOrChangingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-appearance-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try writePaperPDF(in: directory)
        let originalBytes = try Data(contentsOf: url)
        let model = DocumentAppearanceModel()
        let host = UIHostingController(rootView: PDFDocumentHarness(model: model, url: url))
        let window = try makeWindow(host: host)
        defer { window.close() }
        let pdfView = try await waitForPDFView(in: window)
        let originalDocument = try XCTUnwrap(pdfView.document)
        let originalPage = try XCTUnwrap(originalDocument.page(at: 0))
        let originalBounds = originalPage.bounds(for: .mediaBox)

        for isDark in [false, true, false] {
            model.isDark = isDark
            try await settle(window)
            let image = try screenshot(window, name: "pdf-document-\(isDark ? "dark" : "light")")
            let paperPoint = pdfView.convert(CGPoint(x: 40, y: 40), from: originalPage)
            let markPoint = pdfView.convert(CGPoint(x: 120, y: 120), from: originalPage)
            XCTAssertTrue(pdfView.bounds.contains(paperPoint))
            XCTAssertTrue(pdfView.bounds.contains(markPoint))
            try assertPaperAndMark(
                image,
                paperPoint: pdfView.convert(paperPoint, to: window),
                markPoint: pdfView.convert(markPoint, to: window),
                isDark: isDark
            )
            XCTAssertTrue(pdfView.document === originalDocument, "Appearance changes must preserve the loaded PDF document")
            XCTAssertTrue(descendants(window).compactMap { $0 as? PDFView }.first === pdfView,
                "Appearance changes must preserve the native PDF view")
            XCTAssertTrue(pdfView.currentPage === originalPage)
            XCTAssertEqual(originalPage.bounds(for: .mediaBox), originalBounds)
            XCTAssertEqual(originalDocument.string?.trimmingCharacters(in: .whitespacesAndNewlines), "Display-only PDF")
            XCTAssertEqual(try Data(contentsOf: url), originalBytes, "Dark display must leave the source file byte-for-byte unchanged")
        }
    }

    func testMountedExportPreviewNavigationChromeFollowsLiveAppearanceChanges() async throws {
        let previousValue = UserDefaults.standard.object(forKey: appearanceKey)
        defer { restoreAppearance(previousValue) }
        UserDefaults.standard.set("light", forKey: appearanceKey)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-preview-appearance-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try writePaperPDF(in: directory)
        let originalBytes = try Data(contentsOf: url)
        let exportedPDF = ExportedPDF(url: url, chartTitle: "Export Preview", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: 1,
            fileSizeBytes: originalBytes.count, exportedAt: Date(timeIntervalSince1970: 123))
        let host = UIHostingController(rootView: PDFExportPreviewView(exportedPDF: exportedPDF))
        let window = try makeWindow(host: host)
        defer { window.close() }
        let pdfView = try await waitForPDFView(in: window)
        let originalDocument = try XCTUnwrap(pdfView.document)

        for isDark in [false, true, false] {
            UserDefaults.standard.set(isDark ? "dark" : "light", forKey: appearanceKey)
            try await settle(window, frames: 12)
            let navigationBar = try XCTUnwrap(descendants(window).compactMap { $0 as? UINavigationBar }
                .first { $0.window === window && !$0.isHidden && $0.alpha > 0 && $0.bounds.height > 0 })
            let title = try XCTUnwrap(descendants(navigationBar).compactMap { $0 as? UILabel }
                .first { $0.text == exportedPDF.navigationTitle && !$0.isHidden && $0.alpha > 0 },
                "The export preview must keep its native title visible during appearance changes")
            XCTAssertGreaterThan(title.bounds.width, 0)
            XCTAssertGreaterThan(title.bounds.height, 0)
            let image = try screenshot(window, name: "export-preview-chrome-\(isDark ? "dark" : "light")")
            let backgroundPoint = navigationBar.convert(
                CGPoint(x: navigationBar.bounds.maxX - 8, y: navigationBar.bounds.midY), to: window)
            try assertRGB(image, at: backgroundPoint, equals: isDark ? 0 : 1,
                message: "The export navigation bar must follow the selected appearance after a live switch")
            let titleFrame = title.convert(title.bounds, to: window)
            XCTAssertGreaterThan(try contrastingPixelCount(image, in: titleFrame, isDark: isDark), 10,
                "The native title must actually render readable text against the selected navigation background")
            XCTAssertTrue(pdfView.document === originalDocument)
            XCTAssertTrue(descendants(window).contains { $0 === pdfView })
            XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        }
    }

    func testChartPDFExportKeepsLightPaperWhileAppAppearanceIsDark() async throws {
        let previousValue = UserDefaults.standard.object(forKey: appearanceKey)
        defer { restoreAppearance(previousValue) }
        UserDefaults.standard.set("dark", forKey: appearanceKey)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var chart = Chart.blank(title: "Appearance Export Proof", measureCount: 4, layoutStyle: .simpleChordSheet)
        chart.stylePreset = .plainWhite
        let originalChart = chart
        let exportedPDF = try await PDFChartExporter(exportDirectory: directory).exportPDF(for: chart)
        let bytes = try Data(contentsOf: exportedPDF.url)
        let pdfAttachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "com.adobe.pdf")
        pdfAttachment.name = "synthetic-appearance-export-remains-light.pdf"
        pdfAttachment.lifetime = .keepAlways
        add(pdfAttachment)
        let document = try XCTUnwrap(PDFDocument(data: bytes))
        let page = try XCTUnwrap(document.page(at: 0))
        let image = renderPDFPage(page)
        attach(image, name: "export-remains-light-with-dark-app-appearance")
        try assertRGB(image, at: CGPoint(x: 24, y: 24), equals: 1,
            message: "Screen appearance must not change exported PDF paper")
        XCTAssertTrue(document.string?.contains("Appearance Export Proof") == true)
        XCTAssertEqual(chart, originalChart, "Display appearance must not mutate chart data")
        UserDefaults.standard.set("light", forKey: appearanceKey)
        XCTAssertEqual(try Data(contentsOf: exportedPDF.url), bytes)
    }

    private func makeWindow<Content: View>(host: UIHostingController<Content>) throws -> DocumentAppearanceWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "Mounted display checks require a foreground scene")
        let window = DocumentAppearanceWindow(windowScene: scene)
        window.previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 800)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        XCTAssertTrue(window.isKeyWindow)
        return window
    }

    private func settle(_ window: UIWindow, frames: Int = 4) async throws {
        // Yield several frames so SwiftUI's effect and PDFKit's tiled content
        // are committed before capture. Source layer.render omits these effects.
        for _ in 0..<frames {
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func waitForPDFView(in window: UIWindow) async throws -> PDFView {
        for _ in 0..<30 {
            window.layoutIfNeeded()
            if let pdfView = descendants(window).compactMap({ $0 as? PDFView }).first,
               pdfView.document != nil, pdfView.currentPage != nil {
                try await settle(window)
                return pdfView
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(descendants(window).compactMap { $0 as? PDFView }.first,
            "The real PDFDocumentView must mount a readable native PDFView")
    }

    private func screenshot(_ window: UIWindow, name: String) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var captured = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            captured = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        attach(image, name: name)
        XCTAssertTrue(captured, "The mounted hierarchy must be captured with its display effects")
        return image
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertPaperAndMark(_ image: UIImage, paperPoint: CGPoint, markPoint: CGPoint, isDark: Bool) throws {
        try assertRGB(image, at: paperPoint, equals: isDark ? 0 : 1,
            message: "Paper must be \(isDark ? "dark" : "light") in the mounted document")
        try assertRGB(image, at: markPoint, equals: isDark ? 1 : 0,
            message: "Document marks must stay visible against \(isDark ? "dark" : "light") paper")
    }

    private func assertRGB(_ image: UIImage, at point: CGPoint, equals expected: Double, message: String) throws {
        let cgImage = try XCTUnwrap(image.cgImage)
        let rect = CGRect(x: floor(point.x * image.scale) - 1, y: floor(point.y * image.scale) - 1, width: 3, height: 3)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)).contains(rect), message)
        let sample = try XCTUnwrap(cgImage.cropping(to: rect), message)
        var rgba = [UInt8](repeating: 0, count: 3 * 3 * 4)
        var rendered = false
        rgba.withUnsafeMutableBytes { buffer in
            if let context = CGContext(data: buffer.baseAddress, width: 3, height: 3,
                bitsPerComponent: 8, bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) {
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 3, height: 3))
                rendered = true
            }
        }
        XCTAssertTrue(rendered)
        for component in 0..<3 {
            let average = (0..<9).reduce(0.0) { $0 + Double(rgba[$1 * 4 + component]) } / (9 * 255)
            XCTAssertEqual(average, expected, accuracy: 0.14, "\(message), RGB channel \(component)")
        }
    }

    private func contrastingPixelCount(_ image: UIImage, in frame: CGRect, isDark: Bool) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage)
        let sampleFrame = CGRect(x: frame.minX * image.scale, y: frame.minY * image.scale,
            width: frame.width * image.scale, height: frame.height * image.scale).integral
        let sample = try XCTUnwrap(cgImage.cropping(to: sampleFrame))
        let width = sample.width
        let height = sample.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var rendered = false
        rgba.withUnsafeMutableBytes { buffer in
            if let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) {
                context.draw(sample, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
                rendered = true
            }
        }
        XCTAssertTrue(rendered)
        return (0..<(width * height)).filter { index in
            let luminance = (Double(rgba[index * 4]) + Double(rgba[index * 4 + 1]) + Double(rgba[index * 4 + 2])) / (3 * 255)
            return isDark ? luminance > 0.7 : luminance < 0.3
        }.count
    }

    private func writePaperPDF(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bounds = CGRect(x: 0, y: 0, width: 240, height: 240)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            renderer.beginPage()
            UIColor.white.setFill()
            UIBezierPath(rect: bounds).fill()
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(x: 80, y: 80, width: 80, height: 80)).fill()
            NSString(string: "Display-only PDF").draw(at: CGPoint(x: 24, y: 200), withAttributes: [
                .font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black
            ])
        }
        let url = directory.appendingPathComponent("display-only.pdf")
        try data.write(to: url)
        return url
    }

    private func renderPDFPage(_ page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: bounds.size))
            renderer.cgContext.translateBy(x: -bounds.minX, y: bounds.height + bounds.minY)
            renderer.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: renderer.cgContext)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func restoreAppearance(_ previousValue: Any?) {
        if let previousValue {
            UserDefaults.standard.set(previousValue, forKey: appearanceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: appearanceKey)
        }
    }
}

@MainActor
private final class DocumentAppearanceModel: ObservableObject {
    @Published var isDark = false
}

@MainActor
private final class NativeDocumentRecorder {
    var views: [NativeDocumentPaperView] = []
}

private struct NativeDocumentHarness: View {
    @ObservedObject var model: DocumentAppearanceModel
    let recorder: NativeDocumentRecorder

    var body: some View {
        NativeDocumentPaper(recorder: recorder)
            .frame(width: 320, height: 240)
            .ichartDocumentDisplayAppearance(isDark: model.isDark)
    }
}

private struct PersistedNativeDocumentHarness: View {
    let recorder: NativeDocumentRecorder

    var body: some View {
        NativeDocumentPaper(recorder: recorder)
            .frame(width: 320, height: 240)
            .ichartDocumentDisplayAppearance()
    }
}

private struct PDFDocumentHarness: View {
    @ObservedObject var model: DocumentAppearanceModel
    let url: URL

    var body: some View {
        PDFDocumentView(url: url)
            .frame(width: 400, height: 400)
            .ichartDocumentDisplayAppearance(isDark: model.isDark)
    }
}

@MainActor
private final class PencilKitDocumentRecorder {
    var canvases: [PKCanvasView] = []
}

private struct PencilKitDocumentHarness: View {
    @ObservedObject var model: DocumentAppearanceModel
    let recorder: PencilKitDocumentRecorder

    var body: some View {
        PencilKitDocumentPaper(recorder: recorder)
            .frame(width: 320, height: 240)
            .ichartDocumentDisplayAppearance(isDark: model.isDark)
    }
}

private struct PencilKitDocumentPaper: UIViewRepresentable {
    let recorder: PencilKitDocumentRecorder

    func makeUIView(context: Context) -> UIView {
        let paper = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        paper.backgroundColor = .white
        paper.isOpaque = true
        let canvas = PKCanvasView(frame: paper.bounds)
        LeadSheetLiveInkCanvasAppearancePolicy.configure(canvas)
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.contentSize = paper.bounds.size
        canvas.isScrollEnabled = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.drawingPolicy = .anyInput
        canvas.tool = LeadSheetPersistentInkColorPolicy.inkingTool(width: 6)
        let points = stride(from: 80, through: 240, by: 20).enumerated().map { index, x in
            PKStrokePoint(location: CGPoint(x: CGFloat(x), y: 120), timeOffset: TimeInterval(index) * 0.05,
                size: CGSize(width: 14, height: 14), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        canvas.drawing = PKDrawing(strokes: [PKStroke(
            ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 123))
        )])
        paper.addSubview(canvas)
        recorder.canvases.append(canvas)
        return paper
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

private struct NativeDocumentPaper: UIViewRepresentable {
    let recorder: NativeDocumentRecorder

    func makeUIView(context: Context) -> NativeDocumentPaperView {
        let view = NativeDocumentPaperView()
        recorder.views.append(view)
        return view
    }

    func updateUIView(_ view: NativeDocumentPaperView, context: Context) {}
}

private final class NativeDocumentPaperView: UIView {
    let paperColor = UIColor.white
    let markColor = UIColor.black

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = paperColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        paperColor.setFill()
        UIBezierPath(rect: bounds).fill()
        markColor.setFill()
        UIBezierPath(rect: CGRect(x: 80, y: 90, width: 160, height: 60)).fill()
    }
}

@MainActor
private final class DocumentAppearanceWindow: UIWindow {
    weak var previousKeyWindow: UIWindow?

    func close() {
        isHidden = true
        rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}
#endif

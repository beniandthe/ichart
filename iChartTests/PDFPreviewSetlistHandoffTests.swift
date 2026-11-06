#if canImport(UIKit) && canImport(PDFKit)
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class PDFPreviewSetlistHandoffTests: XCTestCase {
    func testSavedPreviewShowsLabeledActionAndOpensSetlistChooserWithoutChangingThePDF() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try fixturePDF(in: root)
        let pdfStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("PDF Library"))
        let saved = try pdfStore.save(exported, source: .chartExport)
        let itemID = try XCTUnwrap(pdfStore.itemID(forExportedURL: saved.url))
        let setlistStore = IChartPDFSetlistStore(baseDirectory: root.appendingPathComponent("Setlists"))
        let setlist = try setlistStore.create(name: "Tonight")
        let beforePDF = try Data(contentsOf: saved.url)
        let beforeLibrary = pdfStore.items
        let host = UIHostingController(rootView: PDFExportPreviewView(
            exportedPDF: saved, source: .chartExport, pdfItemID: itemID)
            .environmentObject(pdfStore)
            .environmentObject(setlistStore)
            .environmentObject(ChartLibraryStore(charts: []))
            .environment(\.accessibilityEnabled, true))
        let window = try mount(host)
        defer { close(window) }

        let action = try await node("Add to Setlist", in: window, buttonsOnly: true)
        let guidance = try await node("Read this saved PDF, Share it, or add it to a setlist.", in: window)
        assertVisible(action, in: window)
        assertVisible(guidance, in: window)
        XCTAssertTrue(try NativeAccessibilityLookup.matching(saved.fileSizeText, in: window).isEmpty,
            "Saved PDF previews show reading metadata without displaying a file size")
        XCTAssertGreaterThan(action.frame(in: window).width, 100,
            "The saved-PDF action must display its text rather than collapse to a toolbar icon")
        XCTAssertGreaterThanOrEqual(action.frame(in: window).minY, guidance.frame(in: window).minY,
            "The labeled action belongs with the summary instruction")
        try activate(action)

        let chooserTitle = try await node("Choose a setlist", in: window)
        assertVisible(chooserTitle, in: window)
        let destination = try await node("Add to Tonight", in: window, buttonsOnly: true)
        assertVisible(destination, in: window)
        XCTAssertEqual(setlistStore.setlist(id: setlist.id)?.entries, [],
            "Opening the chooser must not add the PDF before a destination is selected")
        try activate(destination)
        for _ in 0..<40 {
            if setlistStore.setlist(id: setlist.id)?.entries.count == 1 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(setlistStore.setlist(id: setlist.id)?.entries.map(\.pdfItemID), [itemID])
        XCTAssertEqual(try Data(contentsOf: saved.url), beforePDF)
        XCTAssertEqual(pdfStore.items, beforeLibrary)
    }

    func testUnsavedPreviewHasNoAddToSetlistActionAndNeedsNoLibraryEnvironment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try fixturePDF(in: root)
        let host = UIHostingController(rootView: PDFExportPreviewView(exportedPDF: exported)
            .environment(\.accessibilityEnabled, true))
        let window = try mount(host)
        defer { close(window) }
        _ = try await node("Check this reading copy, then Share it.", in: window)
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Add to Setlist", in: window,
            buttonsOnly: true).isEmpty)
        XCTAssertNotNil(try NativeAccessibilityLookup.matching("Share", in: window, buttonsOnly: true).first)
        XCTAssertTrue(try NativeAccessibilityLookup.matching(exported.fileSizeText, in: window).isEmpty,
            "Export previews keep file size out of the reading interface")
        XCTAssertEqual(try Data(contentsOf: exported.url).count, exported.fileSizeBytes)
    }

    private func fixturePDF(in root: URL) throws -> ExportedPDF {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            NSString(string: "Disposable PDF handoff fixture").draw(at: CGPoint(x: 40, y: 40),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        }
        let url = root.appendingPathComponent("Handoff.pdf")
        try data.write(to: url)
        return ExportedPDF(url: url, chartTitle: "Handoff", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0,
            pageCount: 1, fileSizeBytes: data.count, exportedAt: .now)
    }

    private func mount<Content: View>(_ host: UIHostingController<Content>) throws -> PDFHandoffTestWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = PDFHandoffTestWindow(windowScene: scene)
        window.previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func close(_ window: PDFHandoffTestWindow) {
        window.rootViewController?.dismiss(animated: false)
        window.endEditing(true)
        window.isHidden = true
        window.rootViewController = nil
        window.previousKeyWindow?.makeKeyAndVisible()
    }

    private func node(_ label: String, in window: UIWindow, buttonsOnly: Bool = false) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<60 {
            window.layoutIfNeeded()
            if let match = try NativeAccessibilityLookup.matching(label, in: window,
                buttonsOnly: buttonsOnly).first { return match }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let nodes = try NativeAccessibilityLookup.nodes(in: window)
        let diagnostic = XCTAttachment(string: nodes.map { $0.element.accessibilityLabel ?? "-" }.joined(separator: "\n"))
        diagnostic.name = "PDF handoff missing \(label)"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        return try XCTUnwrap(nodes.first { $0.element.accessibilityLabel == label }, "Missing \(label)")
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
        if let button = node.element as? UIButton { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(node.element.accessibilityActivate(), "The visible action must be operable") }
    }

    private func assertVisible(_ node: NativeAccessibilityLookup.Node, in window: UIWindow) {
        let frame = node.frame(in: window)
        XCTAssertFalse(frame.isEmpty)
        XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(frame), "\(node.element.accessibilityLabel ?? "Action") must be visible")
    }
}

@MainActor
private final class PDFHandoffTestWindow: UIWindow {
    weak var previousKeyWindow: UIWindow?
}
#endif

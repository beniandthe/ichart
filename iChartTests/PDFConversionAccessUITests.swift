#if canImport(UIKit) && canImport(PDFKit)
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class PDFConversionAccessUITests: XCTestCase {
    func testBasicPersonalPDFRemainsReadableAndShareableWhileConversionIsDisabled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try fixturePDF(in: root)
        let original = try Data(contentsOf: exported.url)
        let access = PDFConversionAccessModel()
        access.unavailableMessage = "Create Editable Chart requires Pro. Your saved PDFs stay available."
        let host = UIHostingController(rootView: PDFConversionPreviewHarness(exported: exported, access: access)
            .environment(\.accessibilityEnabled, true))
        let window = try mount(host)
        defer { close(window) }

        let conversion = try await node(identifier: "pdf.preview.create-editable-chart", in: window, buttonsOnly: true)
        XCTAssertFalse(conversion.isEnabled)
        let guidance = try await node(identifier: "pdf.preview.conversion-guidance", in: window)
        XCTAssertEqual(guidance.element.accessibilityLabel, access.unavailableMessage)
        assertVisible(conversion, in: window)
        assertVisible(guidance, in: window)
        let share = try await node(label: "Share", in: window, buttonsOnly: true)
        let addToSetlist = try await node(label: "Add to Setlist", in: window, buttonsOnly: true)
        XCTAssertTrue(share.isEnabled)
        XCTAssertTrue(addToSetlist.isEnabled)
        let pdfView = try await readablePDF(in: window)
        XCTAssertEqual(pdfView.document?.pageCount, 1)
        XCTAssertTrue(pdfView.isUserInteractionEnabled)

        attemptActivation(conversion)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(try NativeAccessibilityLookup.nodes(in: window).allSatisfy {
            $0.identifier != "pdf.editable-chart.select-measure.1"
        }, "A disabled conversion must not open a review")
        XCTAssertTrue(access.savedCharts.isEmpty)

        try activateToolbarButton("Share", node: share, in: host)
        for _ in 0..<60 {
            if activityController(in: host) != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(activityController(in: host), "Basic must retain the ordinary PDF Share flow")
        XCTAssertEqual(try Data(contentsOf: exported.url), original)
        XCTAssertTrue(access.savedCharts.isEmpty)
    }

    func testOpenReviewRetainsCorrectionWhenAccessIsRevokedAndResavesAfterRestoration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try fixturePDF(in: root)
        let original = try Data(contentsOf: exported.url)
        let access = PDFConversionAccessModel()
        let host = UIHostingController(rootView: PDFConversionPreviewHarness(exported: exported, access: access)
            .environment(\.accessibilityEnabled, true))
        let window = try mount(host)
        defer { close(window) }

        let conversion = try await node(identifier: "pdf.preview.create-editable-chart", in: window, buttonsOnly: true)
        try activate(conversion)
        let firstMeasure = try await node(identifier: "pdf.editable-chart.select-measure.1", in: window, buttonsOnly: true)
        XCTAssertTrue(try NativeAccessibilityLookup.nodes(in: window).allSatisfy {
            $0.identifier != "pdf.editable-chart.measure.1"
        }, "The preview opens as measures, with the text editor available on selection")
        try activate(firstMeasure)
        let input = try await measureField(in: window)
        XCTAssertEqual(input.text, "Cmaj7")
        input.text = "Ebmaj7"
        input.sendActions(for: .editingChanged)
        _ = try await node(identifier: "pdf.editable-chart.save", in: window, buttonsOnly: true, enabled: true)

        access.unavailableMessage = "Create Editable Chart requires Pro. Your saved PDFs stay available."
        let blockedSave = try await node(identifier: "pdf.editable-chart.save", in: window, buttonsOnly: true, enabled: false)
        let guidance = try await node(label: "\(try XCTUnwrap(access.unavailableMessage)) Your review is kept here while this screen stays open.", in: window)
        XCTAssertTrue(guidance.element.accessibilityLabel?.contains("Your review is kept here") == true)
        let blockedInput = try await measureField(in: window)
        XCTAssertEqual(blockedInput.text, "Ebmaj7",
            "A plan change must retain the correction already entered in this review")
        attemptActivation(blockedSave)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(access.savedCharts.isEmpty, "Revocation must prevent the save callback")

        access.unavailableMessage = nil
        let restoredSave = try await node(identifier: "pdf.editable-chart.save", in: window, buttonsOnly: true, enabled: true)
        let restoredInput = try await measureField(in: window)
        XCTAssertEqual(restoredInput.text, "Ebmaj7")
        try activate(restoredSave)
        for _ in 0..<60 {
            if !access.savedCharts.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(access.savedCharts.count, 1)
        let saved = try XCTUnwrap(access.savedCharts.first)
        XCTAssertEqual(saved.sourcePDFLibraryItemID, access.sourceID)
        XCTAssertEqual(saved.measures.flatMap(\.chordEvents).map(\.symbol),
            [try ChordSymbolParser.parse("Ebmaj7")])
        XCTAssertEqual(try Data(contentsOf: exported.url), original)
    }

    private func fixturePDF(in root: URL) throws -> ExportedPDF {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            for (index, line) in ["Conversion Access", "| Cmaj7 |"].enumerated() {
                NSString(string: line).draw(at: CGPoint(x: 40, y: CGFloat(40 + index * 40)),
                    withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)])
            }
        }
        let url = root.appendingPathComponent("Conversion Access.pdf")
        try data.write(to: url)
        return ExportedPDF(url: url, chartTitle: "Conversion Access", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0,
            pageCount: 1, fileSizeBytes: data.count, exportedAt: .now)
    }

    private func mount<Content: View>(_ host: UIHostingController<Content>) throws -> PDFConversionTestWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = PDFConversionTestWindow(windowScene: scene)
        window.previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func close(_ window: PDFConversionTestWindow) {
        window.rootViewController?.dismiss(animated: false)
        window.endEditing(true)
        window.isHidden = true
        window.rootViewController = nil
        window.previousKeyWindow?.makeKeyAndVisible()
    }

    private func node(identifier: String? = nil, label: String? = nil, in window: UIWindow,
                      buttonsOnly: Bool = false, enabled: Bool? = nil) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<60 {
            window.layoutIfNeeded()
            let matches = try NativeAccessibilityLookup.nodes(in: window).filter { node in
                (identifier == nil || node.identifier == identifier)
                    && (label == nil || node.element.accessibilityLabel == label)
                    && (!buttonsOnly || node.isButton)
                    && (enabled == nil || node.isEnabled == enabled)
                    && !node.frame(in: window).intersection(window.bounds).isEmpty
            }
            if let match = matches.first { return match }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let nodes = try NativeAccessibilityLookup.nodes(in: window)
        let diagnostic = XCTAttachment(string: nodes.map {
            "\($0.identifier ?? "-") \($0.element.accessibilityLabel ?? "-") enabled=\($0.isEnabled)"
        }.joined(separator: "\n"))
        diagnostic.name = "PDF conversion missing control"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        return try XCTUnwrap(nil as NativeAccessibilityLookup.Node?,
            "Missing \(identifier ?? label ?? "control") enabled=\(String(describing: enabled))")
    }

    private func measureField(in window: UIWindow) async throws -> IChartTypedUITextField {
        let found = try await node(identifier: "pdf.editable-chart.measure.1", in: window)
        return try XCTUnwrap(found.element as? IChartTypedUITextField)
    }

    private func readablePDF(in window: UIWindow) async throws -> PDFView {
        for _ in 0..<60 {
            if let pdfView = try NativeAccessibilityLookup.nodes(in: window).compactMap({ $0.element as? PDFView })
                .first(where: { $0.document != nil }) { return pdfView }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(nil as PDFView?, "The ordinary PDF must remain readable")
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
        if let button = node.element as? UIButton { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(node.element.accessibilityActivate()) }
    }

    private func activateToolbarButton(_ label: String, node: NativeAccessibilityLookup.Node,
                                       in controller: UIViewController) throws {
        func controllers(_ controller: UIViewController) -> [UIViewController] {
            [controller] + controller.children.flatMap(controllers)
        }
        let items = controllers(controller).flatMap { controller -> [UIBarButtonItem] in
            let navigationItem = (controller as? UINavigationController)?.navigationBar.topItem
                ?? controller.navigationItem
            return (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? [])
        }
        if let item = items.first(where: { $0.title == label || $0.accessibilityLabel == label }),
           let action = item.action {
            XCTAssertTrue(UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil))
        } else if let control = node.owner as? UIControl {
            control.sendActions(for: .touchUpInside)
        } else {
            try activate(node)
        }
    }

    private func attemptActivation(_ node: NativeAccessibilityLookup.Node) {
        if let button = node.element as? UIButton { button.sendActions(for: .touchUpInside) }
        else { _ = node.element.accessibilityActivate() }
    }

    private func activityController(in controller: UIViewController) -> UIActivityViewController? {
        if let activity = controller as? UIActivityViewController { return activity }
        if let presented = controller.presentedViewController, let activity = activityController(in: presented) {
            return activity
        }
        return controller.children.lazy.compactMap { self.activityController(in: $0) }.first
    }

    private func assertVisible(_ node: NativeAccessibilityLookup.Node, in window: UIWindow) {
        let frame = node.frame(in: window)
        XCTAssertFalse(frame.isEmpty)
        XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(frame))
    }
}

@MainActor
private final class PDFConversionAccessModel: ObservableObject {
    let sourceID = UUID()
    @Published var unavailableMessage: String?
    var savedCharts: [Chart] = []
}

@MainActor
private struct PDFConversionPreviewHarness: View {
    let exported: ExportedPDF
    @ObservedObject var access: PDFConversionAccessModel

    var body: some View {
        PDFExportPreviewView(exportedPDF: exported, source: .personalImport,
            pdfItemID: access.sourceID, editableChartConversionUnavailableMessage: access.unavailableMessage,
            onSaveEditableChart: { chart in
                access.savedCharts.append(chart)
                return true
            })
    }
}

@MainActor
private final class PDFConversionTestWindow: UIWindow {
    weak var previousKeyWindow: UIWindow?
}
#endif

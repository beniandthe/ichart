#if canImport(UIKit)
import Combine
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class SetlistReaderTests: XCTestCase {
    func testSongNavigationPreservesEntryOrderDuplicatesAndBoundaries() {
        let entries = [UUID(), UUID(), UUID()]
        XCTAssertEqual(IChartSetlistReaderNavigation.index(in: entries, selectedID: entries[1]), 1)
        XCTAssertEqual(IChartSetlistReaderNavigation.adjacentID(in: entries, selectedID: entries[1], by: -1), entries[0])
        XCTAssertEqual(IChartSetlistReaderNavigation.adjacentID(in: entries, selectedID: entries[1], by: 1), entries[2])
        XCTAssertNil(IChartSetlistReaderNavigation.adjacentID(in: entries, selectedID: entries[0], by: -1))
        XCTAssertNil(IChartSetlistReaderNavigation.adjacentID(in: entries, selectedID: entries[2], by: 1))
        XCTAssertNil(IChartSetlistReaderNavigation.index(in: [], selectedID: nil))
    }

    func testSongSelectionSurvivesReorderAndMovesToNextPositionAfterRemoval() {
        let entries = [UUID(), UUID(), UUID()]
        XCTAssertEqual(
            IChartSetlistReaderNavigation.selectionAfterChange(from: entries, to: Array(entries.reversed()), selectedID: entries[1]),
            entries[1]
        )
        XCTAssertEqual(
            IChartSetlistReaderNavigation.selectionAfterChange(from: entries, to: [entries[0], entries[2]], selectedID: entries[1]),
            entries[2]
        )
        XCTAssertEqual(
            IChartSetlistReaderNavigation.selectionAfterChange(from: entries, to: [entries[0]], selectedID: entries[2]),
            entries[0]
        )
        XCTAssertNil(IChartSetlistReaderNavigation.selectionAfterChange(from: entries, to: [], selectedID: entries[0]))
    }

    func testPDFReaderResetsPageForNewSongEvenWhenItReferencesSamePDF() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try writePDF(title: "Same PDF", pageCount: 2, in: directory)
        let model = ReaderHarnessModel(url: source)
        let host = UIHostingController(rootView: ReaderHarness(model: model))
        let window = try makeWindow(host: host)
        defer { window.close() }
        let pdfView = try await waitForPDFView(in: host.view)
        let firstDocument = try XCTUnwrap(pdfView.document)
        pdfView.go(to: try XCTUnwrap(firstDocument.page(at: 1)))
        XCTAssertEqual(pdfView.currentPage, firstDocument.page(at: 1))

        model.unrelatedUpdate += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(pdfView.document === firstDocument)
        XCTAssertEqual(pdfView.currentPage, firstDocument.page(at: 1), "An unchanged song preserves its current PDF page")

        model.songID = UUID()
        try await waitForDocumentChange(in: pdfView, previous: firstDocument)
        let nextDocument = try XCTUnwrap(pdfView.document)
        XCTAssertFalse(nextDocument === firstDocument)
        XCTAssertEqual(pdfView.currentPage, nextDocument.page(at: 0), "A repeated PDF is a separate song and starts at page one")

        let secondURL = try writePDF(title: "Different PDF", pageCount: 2, in: directory)
        model.url = secondURL
        model.songID = UUID()
        try await waitForDocumentChange(in: pdfView, previous: nextDocument)
        let secondDocument = try XCTUnwrap(pdfView.document)
        XCTAssertEqual(secondDocument.documentURL, secondURL)
        XCTAssertEqual(pdfView.currentPage, secondDocument.page(at: 0))
    }

    func testMissingOrCorruptPDFClearsPreviousDocumentAndReportsUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try writePDF(title: "Readable", pageCount: 1, in: directory)
        let model = ReaderHarnessModel(url: source)
        let host = UIHostingController(rootView: ReaderHarness(model: model))
        let window = try makeWindow(host: host)
        defer { window.close() }
        let pdfView = try await waitForPDFView(in: host.view)
        XCTAssertNotNil(pdfView.document)
        model.url = directory.appendingPathComponent("missing.pdf")
        model.songID = UUID()
        try await waitForUnavailable(model)
        XCTAssertNil(pdfView.document)

        let corrupt = directory.appendingPathComponent("corrupt.pdf")
        try Data("invalid PDF".utf8).write(to: corrupt)
        model.unavailable = false
        model.url = corrupt
        model.songID = UUID()
        try await waitForUnavailable(model)
        XCTAssertNil(pdfView.document)
    }

    func testPerformanceReaderDropsForumPDFWhenAccessChangesWithoutDeletingSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try writePDF(title: "Forum Song", pageCount: 1, in: directory)
        let pdfStore = IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library", isDirectory: true))
        let saved = try pdfStore.save(ExportedPDF(url: source, chartTitle: "Forum Song", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: 1,
            fileSizeBytes: try Data(contentsOf: source).count, exportedAt: .now), source: .forumDownload)
        let setlistStore = IChartPDFSetlistStore(baseDirectory: directory.appendingPathComponent("Setlists", isDirectory: true))
        let setlist = try setlistStore.create(name: "Gig")
        let entry = try setlistStore.add(pdfItem: try XCTUnwrap(pdfStore.items.first), to: setlist.id)
        let chartStore = ChartLibraryStore(charts: [], entitlements: AppEntitlements(subscription: .activePro()))
        let reader = IChartSetlistPerformanceReader(setlistID: setlist.id, startingEntryID: entry.id)
            .environmentObject(setlistStore).environmentObject(pdfStore).environmentObject(chartStore)
        let host = UIHostingController(rootView: reader)
        let window = try makeWindow(host: host)
        defer { window.close() }
        let pdfView = try await waitForPDFView(in: host.view)
        XCTAssertNotNil(pdfView.document)

        chartStore.entitlements = AppEntitlements(subscription: .proGrace(graceEndsAt: .now.addingTimeInterval(60)))
        try await waitForUnavailableReader(in: window)
        XCTAssertNil(pdfView.document, "Even a transition-retained PDF view must release revoked content")
        XCTAssertTrue(descendants(window).compactMap { $0 as? PDFView }.allSatisfy { $0.document == nil },
            "Revoked access must leave no readable PDF document in the presented hierarchy")
        XCTAssertEqual(setlistStore.setlist(id: setlist.id)?.entries, [entry])
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.url.path), "Changing access must not delete the source PDF")
    }

    func testSetlistNameUsesNativeFieldWithoutSavingDraftChanges() async throws {
        var savedName: String?
        let sheet = IChartSetlistNameSheet(title: "Rename Setlist", initialName: "Friday Gig", saveTitle: "Save") { savedName = $0 }
        let host = UIHostingController(rootView: sheet)
        let window = try makeWindow(host: host)
        defer { window.close() }
        var nameField: IChartTypedUITextField?
        for _ in 0..<20 {
            nameField = descendants(host.view).compactMap { $0 as? IChartTypedUITextField }.first { $0.placeholder == "Setlist Name" }
            if nameField != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let field = try XCTUnwrap(nameField)
        XCTAssertEqual(field.text, "Friday Gig")
        XCTAssertEqual(field.autocapitalizationType, .words)
        field.text = "Saturday Gig"
        field.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(field.text, "Saturday Gig")
        XCTAssertNil(savedName, "Editing a setlist name remains a draft until Save")
    }

    func testLibrarySetlistControlsVisibleWithHiddenOuterNavigation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let setlistStore = IChartPDFSetlistStore(baseDirectory: directory.appendingPathComponent("Setlists", isDirectory: true))
        let setlist = try setlistStore.create(name: "Friday Show")
        let pdfStore = IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library", isDirectory: true))
        let chartStore = ChartLibraryStore(charts: [])

        for (path, expectedTitle) in [([], "Setlists"), ([setlist.id], "Friday Show")] {
            let content = NavigationStack {
                HStack(spacing: 0) {
                    Color(uiColor: .secondarySystemBackground).frame(width: 180)
                    SetlistsView(initialPath: path)
                        .environmentObject(setlistStore)
                        .environmentObject(pdfStore)
                        .environmentObject(chartStore)
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            let host = UIHostingController(rootView: content)
            let window = try makeWindow(host: host)
            defer { window.close() }
            let titleIdentifier = path.isEmpty ? "setlists.title" : "setlists.detail.title"
            var titleLabel: UILabel?
            for _ in 0..<40 {
                window.layoutIfNeeded()
                titleLabel = descendants(window).compactMap { $0 as? UILabel }
                    .first { $0.accessibilityIdentifier == titleIdentifier && $0.text == expectedTitle && isVisible($0) }
                if titleLabel != nil { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            attachScreenshot(window, name: "Setlists content controls - \(expectedTitle)")
            XCTAssertNotNil(titleLabel, "The workspace must visibly render \(expectedTitle)")
            XCTAssertTrue(descendants(window).compactMap { $0 as? UINavigationBar }.filter(isVisible).isEmpty,
                "Setlist headers must not expose an extra blank outer navigation bar")
            let expectedControlIDs = path.isEmpty ? ["setlists.create"] : ["setlists.back", "setlists.reorder", "setlists.songs.add"]
            for identifier in expectedControlIDs {
                let button = try XCTUnwrap(descendants(window).compactMap { $0 as? UIButton }
                    .first { $0.accessibilityIdentifier == identifier && isVisible($0) }, "The \(identifier) control must remain visible")
                XCTAssertGreaterThanOrEqual(button.bounds.height, 44, "The \(identifier) control must retain a usable touch target")
                XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
            }
            XCTAssertFalse(descendants(window).compactMap { $0 as? UIButton }.contains {
                $0.accessibilityIdentifier == "setlists.perform" || $0.configuration?.title == "Perform" || $0.title(for: .normal) == "Perform"
            }, "Song rows open the reader; there must be no redundant Perform control")
            if !path.isEmpty {
                let back = try XCTUnwrap(descendants(window).compactMap { $0 as? UIButton }
                    .first { $0.accessibilityIdentifier == "setlists.back" })
                let addButtons = descendants(window).compactMap { $0 as? UIButton }
                    .filter { $0.accessibilityIdentifier == "setlists.songs.add" }
                XCTAssertEqual(addButtons.count, 1, "Add PDFs must have one centralized control, including in an empty setlist")
                let add = try XCTUnwrap(addButtons.first)
                let edit = try XCTUnwrap(descendants(window).compactMap { $0 as? UIButton }
                    .first { $0.accessibilityIdentifier == "setlists.reorder" })
                let backFrame = back.convert(back.bounds, to: window)
                for button in [add, edit] {
                    let frame = button.convert(button.bounds, to: window)
                    XCTAssertEqual(frame.midY, backFrame.midY, accuracy: 1, "Add PDFs and Edit must occupy the same top band as Back")
                }
                back.sendActions(for: .touchUpInside)
                for _ in 0..<40 {
                    if descendants(window).compactMap({ $0 as? UILabel }).contains(where: {
                        $0.accessibilityIdentifier == "setlists.title" && $0.text == "Setlists" && isVisible($0)
                    }) { break }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                XCTAssertTrue(descendants(window).compactMap { $0 as? UILabel }.contains {
                    $0.accessibilityIdentifier == "setlists.title" && $0.text == "Setlists" && isVisible($0)
                }, "Back must return to the root setlist list without relying on hidden navigation chrome")
            }
        }
    }

    func testFullScreenReaderNavigatesPastMissingSongAndBackInStoredOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdfStore = IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library", isDirectory: true))
        var items: [IChartPDFLibraryItem] = []
        for title in ["Song A", "Missing Song", "Song B"] {
            let source = try writePDF(title: title, pageCount: 2, in: directory)
            _ = try pdfStore.save(ExportedPDF(url: source, chartTitle: title, layoutStyle: .simpleChordSheet,
                transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: 2,
                fileSizeBytes: try Data(contentsOf: source).count, exportedAt: .now), source: .chartExport)
            items.append(try XCTUnwrap(pdfStore.items.first { $0.displayTitle == title }))
        }
        let setlistStore = IChartPDFSetlistStore(baseDirectory: directory.appendingPathComponent("Setlists", isDirectory: true))
        let setlist = try setlistStore.create(name: "Stage Set")
        let entries = try setlistStore.add(pdfItems: items + [items[0]], to: setlist.id)
        try pdfStore.delete(items[1])
        let model = FullScreenReaderHarnessModel(selectedID: entries[0].id)
        let host = UIHostingController(rootView: FullScreenReaderHarness(model: model, setlistID: setlist.id)
            .environmentObject(setlistStore).environmentObject(pdfStore).environmentObject(ChartLibraryStore(charts: [])))
        let window = try makeWindow(host: host)
        defer { window.close() }
        _ = try await waitForPDFView(in: window)
        try await waitForFullScreenPresentation(host: host, in: window)
        XCTAssertNotNil(host.presentedViewController, "The performance reader must actually be presented full screen")
        let firstPrevious = try readerButton(in: window, identifier: "setlists.reader.previous")
        XCTAssertFalse(firstPrevious.isEnabled, "Previous is disabled at the first song")
        try readerButton(in: window, identifier: "setlists.reader.next").sendActions(for: .touchUpInside)
        try await waitForUnavailableReader(in: window)
        XCTAssertNotNil(host.presentedViewController, "Missing songs retain the performance reader presentation")
        attachScreenshot(window, name: "Setlist performance reader - missing song with Previous and Next")
        for identifier in ["setlists.reader.previous", "setlists.reader.next"] {
            XCTAssertTrue(try readerButton(in: window, identifier: identifier).isEnabled, "Missing songs must retain usable \(identifier)")
        }
        XCTAssertEqual(descendants(window).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "setlists.reader.position" }?.text, "2 of 4")

        try readerButton(in: window, identifier: "setlists.reader.next").sendActions(for: .touchUpInside)
        let nextView = try await waitForPDFView(in: window)
        XCTAssertTrue(nextView.document?.string?.contains("Song B") == true)
        XCTAssertEqual(nextView.currentPage, nextView.document?.page(at: 0))
        try readerButton(in: window, identifier: "setlists.reader.previous").sendActions(for: .touchUpInside)
        try await waitForUnavailableReader(in: window)
        try readerButton(in: window, identifier: "setlists.reader.previous").sendActions(for: .touchUpInside)
        let previousView = try await waitForPDFView(in: window)
        XCTAssertTrue(previousView.document?.string?.contains("Song A") == true)
        XCTAssertEqual(setlistStore.setlist(id: setlist.id)?.entries, entries)
    }

    private func writePDF(title: String, pageCount: Int, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                NSString(string: "\(title) Page \(page + 1)").draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        let url = directory.appendingPathComponent(title + ".pdf")
        try data.write(to: url)
        return url
    }

    private func makeWindow<Content: View>(host: UIHostingController<Content>) throws -> SetlistTestWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "A foreground scene is required to exercise real SwiftUI presentation")
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = SetlistTestWindow(windowScene: scene)
        window.previousKeyWindow = previousKeyWindow
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1_180)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        XCTAssertTrue(window.isKeyWindow, "The owning scene window must be key for full-screen presentation and navigation")
        return window
    }

    private func waitForUnavailableReader(in window: UIWindow) async throws {
        for _ in 0..<40 {
            window.layoutIfNeeded()
            if unavailableTitle(in: window) != nil,
               descendants(window).compactMap({ $0 as? PDFView }).allSatisfy({ $0.document == nil }) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(unavailableTitle(in: window),
            "The presented reader must render its unavailable state, not merely remove a PDF view")
        XCTAssertTrue(descendants(window).compactMap { $0 as? PDFView }.allSatisfy { $0.document == nil })
    }

    private func unavailableTitle(in window: UIWindow) -> UILabel? {
        descendants(window).compactMap { $0 as? UILabel }.first {
            $0.accessibilityIdentifier == "setlists.reader.unavailable" && $0.text == "Unavailable PDF" && isVisible($0)
        }
    }

    private func readerButton(in window: UIWindow, identifier: String) throws -> UIButton {
        try XCTUnwrap(descendants(window).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == identifier && isVisible($0)
        }, "The presented reader must display \(identifier)")
    }

    private func isVisible(_ view: UIView) -> Bool {
        guard view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return false }
        var ancestor: UIView? = view
        while let current = ancestor {
            if current.isHidden || current.alpha == 0 { return false }
            ancestor = current.superview
        }
        return true
    }

    private func attachScreenshot(_ window: UIWindow, name: String) {
        let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func waitForPDFView(in view: UIView) async throws -> PDFView {
        for _ in 0..<20 {
            if let pdf = descendants(view).compactMap({ $0 as? PDFView }).first, pdf.document != nil { return pdf }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(descendants(view).compactMap { $0 as? PDFView }.first)
    }

    private func waitForFullScreenPresentation<Content: View>(host: UIHostingController<Content>, in window: UIWindow) async throws {
        var settledSamples = 0
        for _ in 0..<60 {
            window.layoutIfNeeded()
            if let presented = host.presentedViewController, presented.view.window === window,
               !presented.isBeingPresented, presented.transitionCoordinator == nil {
                let frame = presented.view.convert(presented.view.bounds, to: window)
                if abs(frame.minX - window.bounds.minX) < 1, abs(frame.minY - window.bounds.minY) < 1,
                   abs(frame.width - window.bounds.width) < 1, abs(frame.height - window.bounds.height) < 1 {
                    settledSamples += 1
                    if settledSamples >= 3 { return }
                } else { settledSamples = 0 }
            } else { settledSamples = 0 }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "SetlistReaderTests", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "The full-screen reader must finish presenting and cover its owning window before actions or screenshots"])
    }

    private func waitForDocumentChange(in view: PDFView, previous: PDFDocument) async throws {
        for _ in 0..<20 {
            if let document = view.document, document !== previous { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func waitForUnavailable(_ model: ReaderHarnessModel) async throws {
        for _ in 0..<20 {
            if model.unavailable { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(model.unavailable)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}

@MainActor
private final class SetlistTestWindow: UIWindow {
    weak var previousKeyWindow: UIWindow?

    func close() {
        rootViewController?.dismiss(animated: false)
        rootViewController?.view.endEditing(true)
        isHidden = true
        rootViewController = nil
        previousKeyWindow?.makeKeyAndVisible()
    }
}

@MainActor
private final class ReaderHarnessModel: ObservableObject {
    @Published var url: URL
    @Published var songID = UUID()
    @Published var unrelatedUpdate = 0
    var unavailable = false
    init(url: URL) { self.url = url }
}

private struct ReaderHarness: View {
    @ObservedObject var model: ReaderHarnessModel
    var body: some View {
        VStack {
            Text("\(model.unrelatedUpdate)")
            IChartSetlistPDFDocumentView(url: model.url, songID: model.songID) { model.unavailable = true }
        }
    }
}

@MainActor
private final class FullScreenReaderHarnessModel: ObservableObject {
    @Published var selectedID: UUID
    init(selectedID: UUID) { self.selectedID = selectedID }
}

private struct FullScreenReaderHarness: View {
    @ObservedObject var model: FullScreenReaderHarnessModel
    let setlistID: UUID
    @State private var showingReader = false

    var body: some View {
        Text("Setlist host")
            .fullScreenCover(isPresented: $showingReader) {
                IChartSetlistPerformanceReader(setlistID: setlistID, startingEntryID: model.selectedID)
                    .id(model.selectedID)
            }
            .task { showingReader = true }
    }
}
#endif

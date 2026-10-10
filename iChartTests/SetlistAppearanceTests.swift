#if canImport(UIKit)
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class SetlistAppearanceTests: XCTestCase {
    func testWorkspaceAndDetailFollowAppAppearanceWhenDeviceAppearanceDiffers() async throws {
        let fixture = try SetlistAppearanceFixture()
        defer { fixture.close() }

        for (mode, deviceStyle, expectedStyle) in [("dark", UIUserInterfaceStyle.light, UIUserInterfaceStyle.dark),
                                                   ("light", .dark, .light)] {
            fixture.defaults.set(mode, forKey: "iChartHomeAppearanceMode")
            for path in [[], [fixture.setlist.id]] {
                let view = NavigationStack {
                    SetlistsView(initialPath: path)
                        .environmentObject(fixture.setlistStore)
                        .environmentObject(fixture.pdfStore)
                        .environmentObject(fixture.chartStore)
                        .toolbar(.hidden, for: .navigationBar)
                }
                .defaultAppStorage(fixture.defaults)
                let host = UIHostingController(rootView: view)
                let window = try makeWindow(host: host, deviceStyle: deviceStyle)
                defer { window.close() }
                let titleID = path.isEmpty ? "setlists.title" : "setlists.detail.title"
                let title: UILabel = try await waitForView(in: window) {
                    $0.accessibilityIdentifier == titleID && $0.traitCollection.userInterfaceStyle == expectedStyle
                }
                assertReadableLabel(title, in: expectedStyle)
                let controlIDs = path.isEmpty ? ["setlists.create"] : ["setlists.back", "setlists.songs.add", "setlists.reorder"]
                for identifier in controlIDs {
                    let button: UIButton = try await waitForView(in: window) { $0.accessibilityIdentifier == identifier }
                    XCTAssertEqual(button.traitCollection.userInterfaceStyle, expectedStyle, identifier)
                }
                let list: UICollectionView = try await waitForView(in: window) { _ in true }
                XCTAssertEqual(list.traitCollection.userInterfaceStyle, expectedStyle, "List rows must follow the app appearance")
                attachScreenshot(window, name: "Setlists \(mode) - \(path.isEmpty ? "list" : "detail")")

                if path.isEmpty && mode == "dark" {
                    fixture.defaults.set("light", forKey: "iChartHomeAppearanceMode")
                    let updatedTitle: UILabel = try await waitForView(in: window) {
                        $0.accessibilityIdentifier == titleID && $0.traitCollection.userInterfaceStyle == .light
                    }
                    assertReadableLabel(updatedTitle, in: .light)
                    fixture.defaults.set(mode, forKey: "iChartHomeAppearanceMode")
                }
            }
        }
    }

    func testSetlistNameFieldUsesAppAppearanceAgainstOppositeDeviceAppearance() async throws {
        let fixture = try SetlistAppearanceFixture()
        defer { fixture.close() }
        for (mode, deviceStyle, expectedStyle) in [("dark", UIUserInterfaceStyle.light, UIUserInterfaceStyle.dark),
                                                   ("light", .dark, .light)] {
            fixture.defaults.set(mode, forKey: "iChartHomeAppearanceMode")
            let view = IChartSetlistNameSheet(title: "Rename Setlist", initialName: "Friday Gig", saveTitle: "Save") { _ in }
                .defaultAppStorage(fixture.defaults)
            let host = UIHostingController(rootView: view)
            let window = try makeWindow(host: host, deviceStyle: deviceStyle)
            defer { window.close() }
            let field: IChartTypedUITextField = try await waitForView(in: window) {
                $0.placeholder == "Setlist Name" && $0.traitCollection.userInterfaceStyle == expectedStyle
            }
            XCTAssertEqual(field.text, "Friday Gig")
            let navigationBar: UINavigationBar = try await waitForView(in: window) { $0.topItem?.title == "Rename Setlist" }
            XCTAssertEqual(navigationBar.traitCollection.userInterfaceStyle, expectedStyle)
            attachScreenshot(window, name: "Setlist \(mode) name sheet")
        }
    }

    func testPresentedPDFPickerAndReaderChromeRetainSelectedDarkAppearance() async throws {
        let fixture = try SetlistAppearanceFixture()
        defer { fixture.close() }
        fixture.defaults.set("dark", forKey: "iChartHomeAppearanceMode")

        let detail = SetlistsView(initialPath: [fixture.setlist.id])
            .environmentObject(fixture.setlistStore)
            .environmentObject(fixture.pdfStore)
            .environmentObject(fixture.chartStore)
            .defaultAppStorage(fixture.defaults)
        let detailHost = UIHostingController(rootView: detail)
        let detailWindow = try makeWindow(host: detailHost, deviceStyle: .light)
        defer { detailWindow.close() }
        let add: UIButton = try await waitForView(in: detailWindow) { $0.accessibilityIdentifier == "setlists.songs.add" }
        add.sendActions(for: .touchUpInside)
        try await waitForPresentation(host: detailHost, in: detailWindow)
        let picker = try XCTUnwrap(detailHost.presentedViewController?.view)
        let pickerBar: UINavigationBar = try await waitForView(in: picker) { $0.topItem?.title == "Add PDFs" }
        XCTAssertEqual(pickerBar.traitCollection.userInterfaceStyle, .dark)
        let pickerList: UICollectionView = try await waitForView(in: picker) { _ in true }
        XCTAssertEqual(pickerList.traitCollection.userInterfaceStyle, .dark)
        attachScreenshot(detailWindow, name: "Setlist dark presented Add PDFs picker")
        detailHost.dismiss(animated: false)
        detailWindow.close()

        let entry = try fixture.setlistStore.add(pdfItem: fixture.missingPDF, to: fixture.setlist.id)
        let reader = SetlistAppearanceReaderHarness(setlistID: fixture.setlist.id, entryID: entry.id)
            .environmentObject(fixture.setlistStore)
            .environmentObject(fixture.pdfStore)
            .environmentObject(fixture.chartStore)
            .defaultAppStorage(fixture.defaults)
            .environment(\.accessibilityEnabled, true)
        let readerHost = UIHostingController(rootView: reader)
        let readerWindow = try makeWindow(host: readerHost, deviceStyle: .light)
        defer { readerWindow.close() }
        try await waitForPresentation(host: readerHost, in: readerWindow, fullScreen: true)
        let unavailable: UILabel = try await waitForView(in: readerWindow) { $0.accessibilityIdentifier == "setlists.reader.unavailable" }
        XCTAssertEqual(unavailable.traitCollection.userInterfaceStyle, .dark)
        assertReadableLabel(unavailable, in: .dark)
        let position: UILabel = try await waitForView(in: readerWindow) { $0.accessibilityIdentifier == "setlists.reader.position" }
        XCTAssertEqual(position.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(position.text, "1 of 1")
        for identifier in ["setlists.reader.previous", "setlists.reader.next"] {
            let button: UIButton = try await waitForView(in: readerWindow) { $0.accessibilityIdentifier == identifier }
            XCTAssertEqual(button.traitCollection.userInterfaceStyle, .dark, identifier)
        }
        let readerBar: UINavigationBar = try await waitForView(in: readerWindow) { $0.topItem?.title == "Missing Song" }
        XCTAssertEqual(readerBar.traitCollection.userInterfaceStyle, .dark)
        attachScreenshot(readerWindow, name: "Setlist dark full-screen reader chrome")
    }

    func testMountedPDFPageInvertsOnAppearanceChangeWithoutRewritingOrReloadingDocument() async throws {
        let fixture = try SetlistAppearanceFixture()
        defer { fixture.close() }
        fixture.defaults.set("light", forKey: "iChartHomeAppearanceMode")
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.cgContext.fill(bounds)
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(x: 72, y: 360, width: 80, height: 80))
            NSString(string: "Setlist appearance PDF").draw(at: CGPoint(x: 36, y: 36),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
        }
        let source = fixture.directory.appendingPathComponent("appearance.pdf")
        try data.write(to: source)
        let saved = try fixture.pdfStore.save(ExportedPDF(url: source, chartTitle: "Appearance PDF", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: 1, fileSizeBytes: data.count, exportedAt: .now), source: .chartExport)
        let item = try XCTUnwrap(fixture.pdfStore.items.first)
        let entry = try fixture.setlistStore.add(pdfItem: item, to: fixture.setlist.id)
        let savedData = try Data(contentsOf: saved.url)
        let reader = SetlistAppearanceReaderHarness(setlistID: fixture.setlist.id, entryID: entry.id)
            .environmentObject(fixture.setlistStore)
            .environmentObject(fixture.pdfStore)
            .environmentObject(fixture.chartStore)
            .defaultAppStorage(fixture.defaults)
            .environment(\.accessibilityEnabled, true)
        let host = UIHostingController(rootView: reader)
        let window = try makeWindow(host: host, deviceStyle: .light)
        defer { window.close() }
        try await waitForPresentation(host: host, in: window, fullScreen: true)
        let pdfView: PDFView = try await waitForView(in: window) { $0.document != nil && $0.scaleFactor > 0 }
        let document = try XCTUnwrap(pdfView.document)
        let page = try XCTUnwrap(document.page(at: 0))
        let paperPoint = pdfView.convert(pdfView.convert(CGPoint(x: 306, y: 396), from: page), to: window)
        let inkPoint = pdfView.convert(pdfView.convert(CGPoint(x: 112, y: 396), from: page), to: window)
        XCTAssertTrue(window.bounds.contains(paperPoint))
        XCTAssertTrue(window.bounds.contains(inkPoint))
        let navigationBar: UINavigationBar = try await waitForView(in: window) { $0.topItem?.title == "Appearance PDF" }
        let lightTitle: UILabel = try await waitForView(in: navigationBar) { $0.text == "Appearance PDF" }
        assertReadableLabel(lightTitle, in: .light)
        attachScreenshot(window, name: "Setlist light reader before toolbar item lookup")
        let doneItem = try await waitForToolbarItem("Done", in: navigationBar, window: window)
        let setlistNameItem = try await waitForToolbarItem("Friday Gig", in: navigationBar, window: window)
        let toolbarBackgroundPoints = [doneItem, setlistNameItem].map { item in
            CGPoint(x: item.frame.midX, y: item.frame.minY + 5)
        }
        let navigationFrame = navigationBar.convert(navigationBar.bounds, to: window)
        let navigationBackgroundPoint = CGPoint(x: navigationFrame.minX + navigationFrame.width * 0.3, y: navigationFrame.midY)
        let light = try await waitForPDFPixels(in: window, paperPoint: paperPoint, inkPoint: inkPoint, dark: false,
            navigationBackgroundPoint: navigationBackgroundPoint, toolbarBackgroundPoints: toolbarBackgroundPoints)
        XCTAssertGreaterThan(try brightness(at: navigationBackgroundPoint, in: light), 0.75,
            "Light reader navigation background must display light")
        attachScreenshot(light, name: "Setlist light mounted PDF page")

        fixture.defaults.set("dark", forKey: "iChartHomeAppearanceMode")
        let position: UILabel = try await waitForView(in: window) {
            $0.accessibilityIdentifier == "setlists.reader.position" && $0.traitCollection.userInterfaceStyle == .dark
        }
        XCTAssertEqual(position.text, "1 of 1")
        let darkTitle: UILabel = try await waitForView(in: navigationBar) {
            $0.text == "Appearance PDF" && $0.traitCollection.userInterfaceStyle == .dark
        }
        assertReadableLabel(darkTitle, in: .dark)
        let dark = try await waitForPDFPixels(in: window, paperPoint: paperPoint, inkPoint: inkPoint, dark: true,
            navigationBackgroundPoint: navigationBackgroundPoint, toolbarBackgroundPoints: toolbarBackgroundPoints)
        XCTAssertLessThan(try brightness(at: navigationBackgroundPoint, in: dark), 0.25,
            "Changing to dark mode must update the navigation background with the PDF and reader controls")
        for (item, point) in zip([doneItem, setlistNameItem], toolbarBackgroundPoints) {
            XCTAssertEqual(item.view.traitCollection.userInterfaceStyle, .dark, "Reader toolbar items must receive native dark traits")
            XCTAssertLessThan(try brightness(at: point, in: dark), 0.4,
                "Reader toolbar item backdrops must be dark enough for their light text")
        }
        attachScreenshot(dark, name: "Setlist dark mounted PDF page")
        XCTAssertTrue(pdfView.document === document, "Changing display appearance must preserve the loaded document")
        XCTAssertEqual(pdfView.currentPage, page)
        XCTAssertEqual(try Data(contentsOf: saved.url), savedData, "Dark display must preserve saved PDF bytes")
        XCTAssertEqual(try Data(contentsOf: source), data, "Dark display must preserve the original PDF bytes")
    }

    private func makeWindow<Content: View>(host: UIHostingController<Content>, deviceStyle: UIUserInterfaceStyle) throws -> SetlistAppearanceWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = SetlistAppearanceWindow(windowScene: scene)
        window.previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        window.overrideUserInterfaceStyle = deviceStyle
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1_180)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        return window
    }

    private func waitForView<T: UIView>(in root: UIView, matching: (T) -> Bool) async throws -> T {
        for _ in 0..<60 {
            root.window?.layoutIfNeeded()
            if let view = descendants(root).compactMap({ $0 as? T }).first(where: { isVisible($0) && matching($0) }) { return view }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        recordLookupFailure(in: root, description: "Expected visible \(T.self) did not appear")
        throw NSError(domain: "SetlistAppearanceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected visible \(T.self) did not appear"])
    }

    private func waitForToolbarItem(_ title: String, in bar: UINavigationBar, window: UIWindow) async throws -> (view: UIView, frame: CGRect) {
        for _ in 0..<60 {
            window.layoutIfNeeded()
            let views = descendants(bar).filter(isVisible)
            var titleFrames: [CGRect] = []
            for node in try NativeAccessibilityLookup.nodes(in: bar) {
                let view = node.element as? UIView
                let button = view as? UIButton
                if (view as? UILabel)?.text == title || node.element.accessibilityLabel == title ||
                    button?.configuration?.title == title || button?.title(for: .normal) == title {
                    let frame = node.frame(in: window)
                    if frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
                       !frame.isEmpty, !frame.intersection(window.bounds).isEmpty { titleFrames.append(frame) }
                }
            }
            let candidates = views.compactMap { view -> (view: UIView, frame: CGRect)? in
                let frame = view.convert(view.bounds, to: window)
                guard frame.height >= 30, frame.height <= 64,
                    titleFrames.contains(where: { !$0.isEmpty && frame.insetBy(dx: -1, dy: -1).contains($0) }) else { return nil }
                return (view, frame)
            }
            if let item = candidates.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) { return item }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        recordLookupFailure(in: bar, description: "Missing rendered toolbar item: \(title)")
        throw NSError(domain: "SetlistAppearanceTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing rendered toolbar item: \(title)"])
    }

    private func recordLookupFailure(in root: UIView, description: String) {
        if let window = root.window { attachScreenshot(window, name: "Setlist toolbar lookup failure") }
        let details = descendants(root).filter(isVisible).map { view in
            "\(type(of: view)): label=\(view.accessibilityLabel ?? "nil"), text=\((view as? UILabel)?.text ?? "nil"), frame=\(view.bounds)"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: "\(description)\n\(details)")
        attachment.name = "Setlist native toolbar lookup diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail(description)
    }

    private func waitForPresentation<Content: View>(host: UIHostingController<Content>, in window: UIWindow, fullScreen: Bool = false) async throws {
        var settledSamples = 0
        for _ in 0..<60 {
            window.layoutIfNeeded()
            if let presented = host.presentedViewController, presented.view.window === window,
               !presented.isBeingPresented, presented.transitionCoordinator == nil {
                let frame = presented.view.convert(presented.view.bounds, to: window)
                let coversWindow = abs(frame.minX - window.bounds.minX) < 1 && abs(frame.minY - window.bounds.minY) < 1 &&
                    abs(frame.width - window.bounds.width) < 1 && abs(frame.height - window.bounds.height) < 1
                if !fullScreen || coversWindow {
                    settledSamples += 1
                    if settledSamples >= 3 { return }
                } else { settledSamples = 0 }
            } else { settledSamples = 0 }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "SetlistAppearanceTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Setlist presentation did not finish"])
    }

    private func assertReadableLabel(_ label: UILabel, in style: UIUserInterfaceStyle) {
        let color = label.textColor.resolvedColor(with: label.traitCollection)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let brightness = (red + green + blue) / 3
        if style == .dark { XCTAssertGreaterThan(brightness, 0.75, "Dark appearance must show light title text") }
        else { XCTAssertLessThan(brightness, 0.25, "Light appearance must show dark title text") }
    }

    private func attachScreenshot(_ window: UIWindow, name: String) {
        attachScreenshot(snapshot(window), name: name)
    }

    private func snapshot(_ window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func attachScreenshot(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForPDFPixels(in window: UIWindow, paperPoint: CGPoint, inkPoint: CGPoint, dark: Bool,
        navigationBackgroundPoint: CGPoint? = nil, toolbarBackgroundPoints: [CGPoint] = []) async throws -> UIImage {
        var image = snapshot(window)
        for _ in 0..<40 {
            image = snapshot(window)
            let paper = try brightness(at: paperPoint, in: image)
            let ink = try brightness(at: inkPoint, in: image)
            let navigation = try navigationBackgroundPoint.map { try brightness(at: $0, in: image) }
            let navigationMatches = navigation.map { dark ? $0 < 0.25 : $0 > 0.75 } ?? true
            let toolbarMatches = try toolbarBackgroundPoints.allSatisfy {
                let value = try brightness(at: $0, in: image)
                return dark ? value < 0.4 : value > 0.6
            }
            if navigationMatches && toolbarMatches && (dark ? (paper < 0.15 && ink > 0.85) : (paper > 0.85 && ink < 0.15)) { return image }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let paper = try brightness(at: paperPoint, in: image)
        let ink = try brightness(at: inkPoint, in: image)
        if dark {
            XCTAssertLessThan(paper, 0.15, "Mounted PDF paper must display dark")
            XCTAssertGreaterThan(ink, 0.85, "Mounted PDF ink must display light")
        } else {
            XCTAssertGreaterThan(paper, 0.85, "Mounted PDF paper must display light")
            XCTAssertLessThan(ink, 0.15, "Mounted PDF ink must display dark")
        }
        return image
    }

    private func brightness(at point: CGPoint, in image: UIImage) throws -> CGFloat {
        let source = try XCTUnwrap(image.cgImage)
        let pixel = try XCTUnwrap(source.cropping(to: CGRect(x: point.x * image.scale, y: point.y * image.scale, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (CGFloat(bytes[0]) + CGFloat(bytes[1]) + CGFloat(bytes[2])) / (3 * 255)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private func isVisible(_ view: UIView) -> Bool {
        guard view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return false }
        var ancestor: UIView? = view
        while let current = ancestor {
            if current.isHidden || current.alpha == 0 { return false }
            ancestor = current.superview
        }
        return true
    }
}

@MainActor
private final class SetlistAppearanceFixture {
    let directory: URL
    let defaultsSuite: String
    let defaults: UserDefaults
    let setlistStore: IChartPDFSetlistStore
    let pdfStore: IChartPDFLibraryStore
    let chartStore = ChartLibraryStore(charts: [])
    let setlist: IChartPDFSetlist
    let missingPDF = IChartPDFLibraryItem(id: UUID(), source: .chartExport, fileName: "missing.pdf", displayTitle: "Missing Song",
        layoutStyle: .simpleChordSheet, transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: 1,
        fileSizeBytes: 100, createdAt: .now, relativePath: "Exports/missing.pdf")

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "SetlistAppearanceTests.\(UUID().uuidString)"
        let store = IChartPDFSetlistStore(baseDirectory: root.appendingPathComponent("Setlists"))
        directory = root
        defaultsSuite = suite
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        setlistStore = store
        pdfStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("PDF Library"))
        setlist = try store.create(name: "Friday Gig")
    }

    func close() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class SetlistAppearanceWindow: UIWindow {
    weak var previousKeyWindow: UIWindow?

    func close() {
        rootViewController?.dismiss(animated: false)
        rootViewController?.view.endEditing(true)
        isHidden = true
        rootViewController = nil
        previousKeyWindow?.makeKeyAndVisible()
    }
}

private struct SetlistAppearanceReaderHarness: View {
    let setlistID: UUID
    let entryID: UUID
    @State private var showingReader = false

    var body: some View {
        Text("Setlist host")
            .fullScreenCover(isPresented: $showingReader) {
                IChartSetlistPerformanceReader(setlistID: setlistID, startingEntryID: entryID)
            }
            .task { showingReader = true }
    }
}
#endif

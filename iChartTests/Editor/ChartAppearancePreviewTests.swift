#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChartAppearancePreviewTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testSampleUsesChartStyleAndDoesNotCopyOrChangeAuthoredContent() throws {
        for style in styles {
            var source = Chart.blank(title: "Private chart content", measureCount: 5, layoutStyle: style)
            source.pageHandwrittenNotationData = Data([1, 2, 3])
            source.pageHandwrittenChordData = Data([4, 5, 6])
            let original = source

            let sample = ChartAppearancePreviewPolicy.sampleChart(for: source)

            XCTAssertEqual(source, original)
            XCTAssertEqual(sample.layoutStyle, style)
            XCTAssertEqual(sample.measures.count, 2)
            XCTAssertNotEqual(sample.id, source.id)
            XCTAssertTrue(Set(sample.measures.map(\.id)).isDisjoint(with: source.measures.map(\.id)))
            XCTAssertEqual(sample.measures.flatMap(\.chordEvents).map { $0.symbol.displayText }, ["C△7", "G7"])
            XCTAssertNil(sample.pageHandwrittenNotationData)
            XCTAssertNil(sample.pageHandwrittenChordData)
            XCTAssertTrue(sample.measures.flatMap(\.chordEvents).allSatisfy { $0.sourceInkData == nil })
            XCTAssertEqual(sample.roadmapObjects.filter { $0.type == .repeatSpan }.count, 1)
            XCTAssertEqual(sample.roadmapObjects.filter { $0.type == .ending1 }.count, 1)
            XCTAssertEqual(sample.freeInkArticulations.map(\.kind), [.fermata])
        }
    }

    func testSampleCopiesAppearanceAndLaysOutRepresentativeContentForEachStyle() throws {
        for style in styles {
            for engraving in EngravingPreset.allCases {
                for readability in NotationReadabilityPreset.allCases {
                    var source = Chart.blank(title: "Preview appearance", layoutStyle: style)
                    source.engravingPreset = engraving
                    source.notationReadability = readability
                    source.repeatWings = readability == .performance
                    source.notationFont = .petaluma
                    source.typography = .default(for: .petaluma)
                    source.defaultClef = .treble
                    let sample = ChartAppearancePreviewPolicy.sampleChart(for: source)
                    let page = layout(sample)
                    let row = try XCTUnwrap(page.systems.first)

                    XCTAssertEqual(row.layoutStyle, style)
                    XCTAssertEqual(sample.notationReadability, source.notationReadability)
                    XCTAssertEqual(sample.repeatWings, source.repeatWings)
                    XCTAssertEqual(sample.notationFont, source.notationFont)
                    XCTAssertEqual(sample.typography, source.typography)
                    XCTAssertEqual(sample.engravingPreset, source.engravingPreset)
                    XCTAssertEqual(sample.staffSystemDensity, source.staffSystemDensity)
                    XCTAssertEqual(sample.staffStyle, source.staffStyle)
                    XCTAssertEqual(sample.defaultClef, source.defaultClef)
                    XCTAssertEqual(row.measures.flatMap(\.chordLayouts).count, 2)
                    XCTAssertFalse(row.measures.flatMap(\.repeatMarkerLayouts).isEmpty)
                    XCTAssertEqual(row.endingLayouts.count, 1)
                    let mark = try XCTUnwrap(sample.freeInkArticulations.first)
                    XCTAssertNotNil(FreeInkArticulationPlacement.target(for: mark, chart: sample, pageLayout: page))
                    if style == .simpleChordSheet {
                        XCTAssertTrue(row.measures.flatMap(\.noteLayouts).isEmpty)
                        XCTAssertNil(row.clefFrame)
                    } else {
                        XCTAssertFalse(row.staffLineYPositions.isEmpty)
                        XCTAssertNotNil(row.clefFrame)
                        XCTAssertNotNil(row.timeSignatureFrame)
                        XCTAssertTrue(row.measures.flatMap(\.noteLayouts).contains { $0.symbolStyle == .quarterRest })
                        XCTAssertTrue(sample.measures.allSatisfy {
                            $0.rhythmMap?.fitsExactly(in: sample.defaultMeter) == true
                        })
                    }
                }
            }
        }
    }

    func testNativePreviewChangesStyleAndKeepsTheSampleWithinItsImage() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let view = NotationReadabilityPreviewView(frame: CGRect(x: 0, y: 0, width: 640, height: 118))
        var images = [ChartLayoutStyle: Data]()
        for style in styles {
            for readability in NotationReadabilityPreset.allCases {
                var source = Chart.blank(title: "Live preview", layoutStyle: style)
                source.notationReadability = readability
                source.repeatWings = readability == .performance
                let original = source
                view.applyAppearance(from: source)
                let image = previewImage(view)

                XCTAssertEqual(source, original)
                XCTAssertEqual(view.chart.layoutStyle, style)
                XCTAssertGreaterThan(try darkPixels(in: image), 100)
                XCTAssertEqual(try darkPixels(in: image, region: CGRect(x: 0, y: 0, width: 640, height: 1)), 0)
                XCTAssertEqual(try darkPixels(in: image, region: CGRect(x: 0, y: 117, width: 640, height: 1)), 0)
                images[style] = try XCTUnwrap(image.pngData())
                attach(image, name: "Engraving preview \(style.rawValue) \(readability.rawValue)")
            }
        }
        XCTAssertNotEqual(images[.simpleChordSheet], images[.rhythmSectionSheet])
    }

    func testNormalEngravingSheetShowsStyleGuidanceAndPreviewWithoutChangingTheChart() async throws {
        for style in styles {
            let source = Chart.blank(title: "Engraving entry", layoutStyle: style)
            let original = source
            let helperTexts = [ChartAppearancePanel.engraving.instructionTitle,
                ChartAppearancePanel.engraving.instruction(for: style),
                "Changes apply immediately to this chart and its exported PDF."]
            let previewLabel = ChartAppearancePreviewPolicy.accessibilityLabel(for: source)
            let host = UIHostingController(rootView: ChartAppearanceSheetView(chart: .constant(source), panel: .engraving)
                .environment(\.sizeCategory, .large)
                .environment(\.accessibilityEnabled, true))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.endEditing(true)
                window.isHidden = true
                window.rootViewController = nil
                previousWindow?.makeKey()
            }
            var nodes = [NativeAccessibilityLookup.Node]()
            var hasRequiredContent = false
            for _ in 0..<80 {
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                nodes = try NativeAccessibilityLookup.nodes(in: host.view)
                let hasHelper = helperTexts.allSatisfy { text in
                    nodes.contains {
                        !$0.isButton && $0.element.accessibilityLabel?.contains(text) == true
                            && !$0.frame(in: window).isEmpty
                    }
                }
                let hasPreview = nodes.contains {
                    $0.element.accessibilityLabel == previewLabel && !$0.frame(in: window).isEmpty
                }
                let hasDone = nodes.contains {
                    $0.isButton && $0.isEnabled && $0.element.accessibilityLabel == "Done"
                        && !$0.frame(in: window).isEmpty
                }
                hasRequiredContent = hasHelper && hasPreview && hasDone
                    && window.isKeyWindow && host.view.window === window
                if hasRequiredContent { break }
                // UIKit's preview can exist before SwiftUI has published the
                // helper and toolbar AX elements. Wait for the complete screen.
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard hasRequiredContent else {
                let observed = nodes.compactMap { node -> String? in
                    let label = node.element.accessibilityLabel ?? ""
                    let identifier = (node.element as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? ""
                    guard !label.isEmpty || !identifier.isEmpty else { return nil }
                    return "\(identifier) | \(label) | \(node.frame(in: window))"
                }.joined(separator: "\n")
                attach(windowImage(window), name: "Incomplete engraving sheet \(style.rawValue)")
                attachMountDiagnostics(window: window, hostView: host.view, nodes: nodes, style: style)
                XCTFail("Engraving sheet did not publish its helper, preview, and Done. Observed accessibility content:\n\(observed)")
                throw AppearanceSheetMountError.incompleteContent
            }
            let helperNodes = try helperTexts.map { text in
                try XCTUnwrap(nodes.first {
                    !$0.isButton && $0.element.accessibilityLabel?.contains(text) == true
                }, "The visible appearance helper must explain \(text)")
            }
            let helperFrame = helperNodes.reduce(CGRect.null) { $0.union($1.frame(in: window)) }
            let preview = try XCTUnwrap(nodes.first {
                $0.element.accessibilityLabel == previewLabel
            })
            let done = try XCTUnwrap(nodes.first { $0.isButton && $0.element.accessibilityLabel == "Done" })
            let viewport = window.bounds.insetBy(dx: -1, dy: -1)
            XCTAssertTrue(viewport.contains(helperFrame))
            XCTAssertTrue(viewport.contains(preview.frame(in: window)))
            XCTAssertTrue(viewport.contains(done.frame(in: window)))
            XCTAssertLessThanOrEqual(helperFrame.maxY, preview.frame(in: window).minY + 1)
            XCTAssertEqual(source, original)
            attach(windowImage(window), name: "Engraving sheet \(style.rawValue)")
        }
    }

    private enum AppearanceSheetMountError: Error { case incompleteContent }

    private func layout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 720, height: 1_100))
    }

    private func previewImage(_ view: NotationReadabilityPreviewView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(view.bounds)
            view.draw(view.bounds)
        }
    }

    private func windowImage(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func attachMountDiagnostics(window: UIWindow, hostView: UIView,
        nodes: [NativeAccessibilityLookup.Node], style: ChartLayoutStyle) {
        func scrollViews(in view: UIView) -> [UIScrollView] {
            let current = (view as? UIScrollView).map { [$0] } ?? []
            return current + view.subviews.flatMap { scrollViews(in: $0) }
        }
        let lines = [
            "Synthetic layout: \(style.rawValue)",
            "Window key: \(window.isKeyWindow); hidden: \(window.isHidden); bounds: \(window.bounds)",
            "Host attached: \(hostView.window === window); frame: \(hostView.frame); bounds: \(hostView.bounds)"
        ] + scrollViews(in: hostView).map {
            "Scroll \(type(of: $0)): frame=\($0.frame), offset=\($0.contentOffset), content=\($0.contentSize), inset=\($0.adjustedContentInset)"
        } + nodes.map {
            "Node \(type(of: $0.element)): label=\(String(reflecting: $0.element.accessibilityLabel)), button=\($0.isButton), frame=\($0.frame(in: window))"
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "Engraving sheet mount metadata \(style.rawValue)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func darkPixels(in image: UIImage, region: CGRect? = nil) throws -> Int {
        let full = try XCTUnwrap(image.cgImage)
        let cgImage: CGImage
        if let region { cgImage = try XCTUnwrap(full.cropping(to: region.integral)) }
        else { cgImage = full }
        var bytes = [UInt8](repeating: 255, count: cgImage.width * cgImage.height)
        let drew = bytes.withUnsafeMutableBytes { data -> Bool in
            guard let context = CGContext(data: data.baseAddress,
                width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
                bytesPerRow: cgImage.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return true
        }
        XCTAssertTrue(drew)
        return bytes.filter { $0 < 100 }.count
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif

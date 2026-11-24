#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Public regression coverage uses an invented chart. A private saved chart may
/// be supplied locally; its bytes, IDs and handwriting are never fixture data.
@MainActor
final class WriteRepeatFeedbackReplayTests: XCTestCase {
    private let editorPageSize = CGSize(width: 1180, height: 1500)
    private let pdfPageSize = CGSize(width: 932, height: 1100)

    func testPopulatedOpenTailStaysOutsideTheClosingRepeatInEditorAndPDF() async throws {
        let chart = try syntheticChart()
        let repeatObject = try XCTUnwrap(chart.roadmapObjects.last { $0.type == .repeatSpan })
        let original = chart
        let proof = try assertClosingRepeatExcludesPopulatedOpenTail(chart, repeatObject: repeatObject,
            pageSize: editorPageSize)
        _ = try assertClosingRepeatExcludesPopulatedOpenTail(chart, repeatObject: repeatObject,
            pageSize: pdfPageSize)
        try await retainProofs(chart: chart, proof: proof, label: "synthetic-repeat-open-tail")
        XCTAssertEqual(chart, original)
    }

    func testSavedManualWidthTailKeepsItsLeftBarlineInEditorAndPDF() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Sized blank outside a repeat", measureCount: 14, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            chart.systems = [0..<4, 4..<8, 8..<14].enumerated().map { index, range in
                ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced,
                    measures: range.map { offset in
                        var measure = chart.measures[offset]
                        measure.manualLayoutWidth = 96
                        measure.authoringState = offset == ids.index(before: ids.endIndex) ? .open : .committed
                        return measure
                    })
            }
            let endID = ids[12]
            let followingID = ids[13]
            for (offset, chord) in [(0.05, "C"), (0.55, "F")] {
                XCTAssertTrue(chart.appendRecognizedChord(try ChordSymbolParser.parse(chord), rawInput: chord,
                    to: endID, atFraction: offset))
            }
            let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: endID, endMeasureID: endID))
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart))
            let following = try XCTUnwrap(reopened.measure(id: followingID))
            XCTAssertTrue(following.chordEvents.isEmpty)
            XCTAssertFalse(following.isExplicitlyAddedOpenMeasure)
            XCTAssertEqual(reopened.roadmapObject(id: repeatID)?.endMeasureID, endID)
            try await assertBarlineInEditorAndPDF(reopened, measureID: followingID, edge: .leading)
        }
    }

    func testInsideInsertionShowsClosingRepeatOnTheOpenMeasureInEditorAndPDF() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.draft(title: "Open measure inside a repeat", layoutStyle: style)
            chart.completeInitialSetup(title: chart.title, key: .cMajor,
                meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
                startingMeasureCount: 2)
            let endID = try XCTUnwrap(chart.measures.last?.id)
            let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: endID, endMeasureID: endID))
            let insertedID = try XCTUnwrap(chart.insertOneMeasureAfterForEditing(endID, extendingRepeat: repeatID))
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart))
            XCTAssertEqual(reopened.measure(id: insertedID)?.authoringState, .open)
            XCTAssertEqual(reopened.roadmapObject(id: repeatID)?.endMeasureID, insertedID)
            try await assertBarlineInEditorAndPDF(reopened, measureID: insertedID, edge: .leading)
            try await assertBarlineInEditorAndPDF(reopened, measureID: insertedID, edge: .trailing)
        }
    }

    func testMeasureOutsideARepeatKeepsItsLeftBarlineWhenMovedToTheNextRow() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Repeat at the previous row", measureCount: 3, layoutStyle: style)
            let endID = chart.measures[2].id
            _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: endID, endMeasureID: endID))
            let insertedID = try XCTUnwrap(chart.insertOneMeasureAfterForEditing(endID))
            XCTAssertTrue(chart.insertSystemBreak(before: insertedID))
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: editorPageSize)
            let lastRow = try XCTUnwrap(layout.systems.last)
            XCTAssertEqual(lastRow.measures.first?.sourceMeasureID, insertedID)
            try await assertBarlineInEditorAndPDF(chart, measureID: insertedID, edge: .leading)
        }
    }

    private func assertBarlineInEditorAndPDF(
        _ chart: Chart,
        measureID: UUID,
        edge: LeadSheetRepeatMarkerLayout.Edge
    ) async throws {
        func target(in layout: LeadSheetPageLayout) throws -> (LeadSheetSystemLayout, LeadSheetMeasureLayout) {
            let system = try XCTUnwrap(layout.systems.first { $0.measures.contains { $0.sourceMeasureID == measureID } })
            return (system, try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measureID }))
        }

        func assertBarline(in image: UIImage, layout: LeadSheetPageLayout, offset: CGPoint = .zero) throws {
            let (system, measure) = try target(in: layout)
            let x: CGFloat
            switch edge {
            case .leading:
                x = measure.leadingBarlineX
            case .trailing:
                let marker = try XCTUnwrap(measure.repeatMarkerLayouts.first { $0.edge == .trailing })
                let metrics = LeadSheetRepeatReadabilityMetrics(chart: chart, staffHeight: marker.frame.height)
                x = LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                    after: measure, in: system, paperFrame: layout.paperFrame(for: system), layoutStyle: chart.layoutStyle
                ) ?? marker.frame.midX + metrics.separation / 2
            }
            let strip = CGRect(
                x: x + offset.x - 1,
                y: measure.staffFrame.minY + offset.y + 3,
                width: 2,
                height: measure.staffFrame.height - 6
            )
            let pixels = try darkPixelCount(image, in: strip)
            XCTAssertGreaterThan(pixels, Int(strip.height * image.scale),
                "The barline must be drawn at the expected \(edge) boundary in \(chart.layoutStyle)")
        }

        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let editorLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: editorPageSize)
        let native = nativeCanvasImage(chart: chart, size: editorPageSize, mode: .measureEdit, scale: 2)
        try assertBarline(in: native, layout: editorLayout)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exported = try await PDFChartExporter(exportDirectory: directory).exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exported.url))
        let pdfWidth = LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart) ?? pdfPageSize.width
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: pdfWidth, height: pdfPageSize.height))
        let (system, _) = try target(in: layout)
        let pageLayout = try XCTUnwrap(layout.pages.first { $0.systemIDs.contains(system.id) })
        let page = try XCTUnwrap(document.page(at: pageLayout.index))
        try assertBarline(in: pdfPageImage(page, scale: 2), layout: layout,
            offset: CGPoint(x: -pageLayout.frame.minX, y: -pageLayout.frame.minY))
    }

    func testProvidedSavedChartKeepsItsFollowingOpenMeasureOutsideRepeat() async throws {
        guard let path = environment("ICHART_REPEAT_FEEDBACK_CHART_PATH") else {
            throw XCTSkip("Provide a local authorized saved Chart JSON through ICHART_REPEAT_FEEDBACK_CHART_PATH")
        }
        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let sourceBytes = try Data(contentsOf: sourceURL)
        defer {
            XCTAssertEqual(try? Data(contentsOf: sourceURL), sourceBytes,
                "Replay and visual export must never modify the provided chart file")
        }
        let chart = try ChartPersistenceCoders.decoder.decode(Chart.self, from: sourceBytes)
        XCTAssertEqual(chart.layoutStyle, .simpleChordSheet)
        let repeatObject = try XCTUnwrap(chart.roadmapObjects.last { object in
            guard object.type == .repeatSpan, let endID = object.endMeasureID,
                  let endPosition = chart.measures.firstIndex(where: { $0.id == endID }),
                  chart.measures.indices.contains(endPosition + 1) else { return false }
            let following = chart.measures[endPosition + 1]
            return following.authoringState == .open
                && (!following.chordEvents.isEmpty || following.manualLayoutWidth != nil
                    || following.isExplicitlyAddedOpenMeasure)
        })
        let start = try XCTUnwrap(chart.measure(id: repeatObject.startMeasureID))
        let end = try XCTUnwrap(repeatObject.endMeasureID.flatMap { chart.measure(id: $0) })
        let endPosition = try XCTUnwrap(chart.measures.firstIndex { $0.id == end.id })
        let following = chart.measures[endPosition + 1]
        XCTAssertEqual(start.index, try expectedIndex("ICHART_REPEAT_FEEDBACK_START_INDEX", fallback: 5))
        XCTAssertEqual(end.index, try expectedIndex("ICHART_REPEAT_FEEDBACK_END_INDEX", fallback: 6))
        XCTAssertEqual(following.index, try expectedIndex("ICHART_REPEAT_FEEDBACK_FOLLOWING_INDEX", fallback: 7))
        XCTAssertNotEqual(repeatObject.endMeasureID, following.id)
        let original = chart
        if following.chordEvents.isEmpty {
            try await assertBarlineInEditorAndPDF(chart, measureID: following.id, edge: .leading)
        } else {
            let proof = try assertClosingRepeatExcludesPopulatedOpenTail(chart, repeatObject: repeatObject,
                pageSize: editorPageSize)
            _ = try assertClosingRepeatExcludesPopulatedOpenTail(chart, repeatObject: repeatObject,
                pageSize: pdfPageSize)
            try await retainProofs(chart: chart, proof: proof, label: "provided-repeat-open-tail")
        }
        XCTAssertEqual(chart, original, "Only value rendering is authorized for the provided chart")
    }

    private struct BoundaryProof {
        var layout: LeadSheetPageLayout
        var system: LeadSheetSystemLayout
        var end: LeadSheetMeasureLayout
        var following: LeadSheetMeasureLayout
        var markerFrame: CGRect
    }

    private func assertClosingRepeatExcludesPopulatedOpenTail(
        _ chart: Chart, repeatObject: RoadmapObject, pageSize: CGSize
    ) throws -> BoundaryProof {
        let endID = try XCTUnwrap(repeatObject.endMeasureID)
        let endPosition = try XCTUnwrap(chart.measures.firstIndex { $0.id == endID })
        let followingModel = try XCTUnwrap(chart.measures.dropFirst(endPosition + 1).first)
        XCTAssertEqual(followingModel.authoringState, .open)
        XCTAssertFalse(followingModel.chordEvents.isEmpty)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let system = try XCTUnwrap(layout.systems.first { $0.measures.contains { $0.sourceMeasureID == endID } })
        let end = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == endID })
        let following = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == followingModel.id })
        XCTAssertNotNil(following.sourceMeasureID, "A real open musical measure is not synthetic continuation space")
        XCTAssertTrue(following.isOpen)
        XCTAssertFalse(following.chordLayouts.isEmpty, "The following open measure has visible musical content")
        XCTAssertEqual(end.staffFrame.maxX, following.staffFrame.minX, accuracy: 0.001)
        let markers = LeadSheetRepeatBoundaryPolicy.repeatMarkers(after: end, before: following)
        let marker = try XCTUnwrap(markers.first { $0.edge == .trailing && $0.roadmapObjectID == repeatObject.id })
        let paper = layout.paperFrame(for: system)
        let boundary = LeadSheetSimpleChordTerminalBarlineGeometry.renderedBoundary(after: end,
            before: following, excludingRepeatMarkerIDs: [], in: system, paperFrame: paper,
            layoutStyle: chart.layoutStyle)
        guard case .repeatBoundary(let renderedMarkers, let trailingLineX) = boundary else {
            XCTFail("The interior close must use the repeat boundary renderer")
            return BoundaryProof(layout: layout, system: system, end: end, following: following, markerFrame: .zero)
        }
        XCTAssertTrue(renderedMarkers.contains { $0.id == marker.id })
        if following.preservesOpenMeasureBoundary {
            XCTAssertEqual(try XCTUnwrap(trailingLineX), following.leadingBarlineX, accuracy: 0.001)
        } else {
            XCTAssertNil(trailingLineX)
        }
        XCTAssertNil(LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(after: end,
            in: system, paperFrame: paper, layoutStyle: chart.layoutStyle))
        let markerFrame = LeadSheetSimpleChordTerminalBarlineGeometry.renderedRepeatMarkerFrame(marker,
            after: end, in: system, paperFrame: paper, layoutStyle: chart.layoutStyle)
        let metrics = LeadSheetRepeatReadabilityMetrics(chart: chart, staffHeight: marker.frame.height)
        let expectedMarkerCenter = trailingLineX.map { $0 - metrics.separation / 2 } ?? end.staffFrame.maxX
        XCTAssertEqual(markerFrame.midX, expectedMarkerCenter, accuracy: 0.001)
        let followingChord = try XCTUnwrap(following.chordLayouts.first)
        XCTAssertLessThan(markerFrame.maxX, followingChord.frame.minX,
            "The closing repeat must precede the following chord")
        let targets = RepeatSpanRenderedEditHitTargetProvider().hitTargets(in: RenderedEditContext(
            pageLayout: layout, layoutStyle: chart.layoutStyle))
        let closingTarget = try XCTUnwrap(targets.first {
            $0.objectID == .repeatSpan(repeatObject.id) && $0.frame.contains(markerFrame)
        })
        XCTAssertEqual(closingTarget.frame.midX, markerFrame.midX, accuracy: 0.001)
        XCTAssertLessThan(closingTarget.frame.maxX, followingChord.frame.midX,
            "The repeat inspector target must stay on the interior boundary")
        return BoundaryProof(layout: layout, system: system, end: end, following: following, markerFrame: markerFrame)
    }

    private func syntheticChart() throws -> Chart {
        var chart = Chart.blank(title: "Repeat before an open chord", measureCount: 7, layoutStyle: .simpleChordSheet)
        let ids = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: ids[3]))
        for systemIndex in chart.systems.indices {
            for measureIndex in chart.systems[systemIndex].measures.indices {
                let index = chart.systems[systemIndex].measures[measureIndex].index
                chart.systems[systemIndex].measures[measureIndex].manualLayoutWidth = index == 3 ? 300 : 120
                chart.systems[systemIndex].measures[measureIndex].authoringState = index == 7 ? .open : .committed
            }
        }
        for (index, text) in [(0, "C"), (1, "D"), (3, "Bb"), (4, "Db"), (5, "Eb"), (6, "Ab")] {
            XCTAssertTrue(chart.appendRecognizedChord(try ChordSymbolParser.parse(text), rawInput: text,
                to: ids[index], atFraction: 0.15))
        }
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[1]))
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[4], endMeasureID: ids[5]))
        return chart
    }

    private func retainProofs(chart: Chart, proof: BoundaryProof, label: String) async throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let configuredOutput = environment("ICHART_REPEAT_FEEDBACK_QA_OUTPUT")
        let base = configuredOutput.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = base.appendingPathComponent(label, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { if configuredOutput == nil { try? FileManager.default.removeItem(at: base) } }
        let native = nativeCanvasImage(chart: chart, size: editorPageSize)
        attach(native, name: "\(label)-native")
        try XCTUnwrap(native.pngData()).write(to: directory.appendingPathComponent("native-page.png"))
        let boundaryRegion = CGRect(x: proof.end.staffFrame.maxX - 8, y: proof.end.staffFrame.minY + 3,
            width: 16, height: max(1, proof.end.staffFrame.height - 6))
        XCTAssertGreaterThan(try darkPixelCount(native, in: boundaryRegion), Int(proof.end.staffFrame.height / 2),
            "The native canvas must paint the close at the interior musical boundary")
        let rowCrop = proof.system.frame.insetBy(dx: -12, dy: -16).intersection(CGRect(origin: .zero, size: native.size))
        if let cropped = native.cgImage?.cropping(to: rowCrop.integral) {
            let row = UIImage(cgImage: cropped)
            attach(row, name: "\(label)-native-row")
            try XCTUnwrap(row.pngData()).write(to: directory.appendingPathComponent("native-row.png"))
        }
        let exported = try await PDFChartExporter(exportDirectory: directory).exportPDF(for: chart)
        let pdfBytes = try Data(contentsOf: exported.url)
        let pdf = XCTAttachment(data: pdfBytes, uniformTypeIdentifier: "com.adobe.pdf")
        pdf.name = "\(label).pdf"
        pdf.lifetime = .keepAlways
        add(pdf)
        let document = try XCTUnwrap(PDFDocument(data: pdfBytes))
        XCTAssertGreaterThan(document.pageCount, 0)
        let followingID = try XCTUnwrap(proof.following.sourceMeasureID)
        let followingText = try XCTUnwrap(chart.measure(id: followingID)?.chordEvents.first?.symbol.displayText)
        XCTAssertPDFExtractedTextContains(document.string ?? "", visibleChordText: followingText)
        for index in 0..<document.pageCount {
            let page = try XCTUnwrap(document.page(at: index))
            let image = pdfPageImage(page)
            attach(image, name: "\(label)-pdf-page-\(index + 1)")
            try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent("pdf-page-\(index + 1).png"))
        }
    }

    private func nativeCanvasImage(
        chart: Chart, size: CGSize, mode: EditorCanvasMode = .browse, scale: CGFloat = 1
    ) -> UIImage {
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: size))
        view.recognizesChordInk = false
        view.chart = chart
        view.interactionMode = mode
        view.overrideUserInterfaceStyle = .light
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            view.draw(view.bounds)
        }
    }

    private func pdfPageImage(_ page: PDFPage, scale: CGFloat = 1) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private func darkPixelCount(_ image: UIImage, in region: CGRect) throws -> Int {
        let scaledRegion = region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale))
        let cropped = try XCTUnwrap(image.cgImage?.cropping(to: scaledRegion.integral))
        var pixels = [UInt8](repeating: 255, count: cropped.width * cropped.height)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: cropped.width, height: cropped.height,
                bitsPerComponent: 8, bytesPerRow: cropped.width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
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

    private func expectedIndex(_ key: String, fallback: Int) throws -> Int {
        guard let value = environment(key) else { return fallback }
        let parsed = try XCTUnwrap(Int(value), "\(key) must be an integer")
        XCTAssertGreaterThan(parsed, 0)
        return parsed
    }

    private func environment(_ key: String) -> String? {
        let values = ProcessInfo.processInfo.environment
        return [key, "TEST_RUNNER_\(key)"].compactMap { values[$0] }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
#endif

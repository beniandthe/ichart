#if canImport(UIKit)
import Foundation
import PDFKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class FinalCueTextExportCompletenessTests: XCTestCase {
    func testModeratePerformanceCueKeepsItsEnteredEndingInBothSheetStyles() async throws {
        try await assertCueExportIsComplete(
            "First time softly, second time build into the final chorus",
            label: "moderate-performance-cue"
        )
    }

    func testTwoLinePerformanceCueKeepsBothEnteredLinesInBothSheetStyles() async throws {
        try await assertCueExportIsComplete(
            "First time softly\nSecond time build into the final chorus",
            label: "two-line-performance-cue"
        )
    }

    func testShortCueKeepsPreferredFontAndExplicitScaleForBothStylesAndFonts() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for fontFamily in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var chart = Chart.blank(title: "Short Cue Typography", measureCount: 1, layoutStyle: style)
                chart.setMatchedFontFamily(fontFamily)
                let measureID = try XCTUnwrap(chart.measures.first?.id)
                let cueID = try XCTUnwrap(chart.addCueText("Horns enter", anchorMeasureID: measureID))
                for scale in [0.75, 1.0, 1.8] {
                    XCTAssertTrue(chart.updateCueText(cueID, scale: scale))
                    let cue = try XCTUnwrap(chart.cueText(id: cueID))
                    let renderer = LeadSheetNotationRenderer(chart: chart)
                    let font = renderer.cueTextFont(emphasis: .normal, scale: CGFloat(scale))
                    XCTAssertEqual(font.pointSize, (style == .rhythmSectionSheet ? 14 : 13.5) * CGFloat(scale), accuracy: 0.001)
                    let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: 1_100))
                    let measure = try XCTUnwrap(layout.systems.first?.measures.first)
                    let metrics = renderer.cueTextRenderMetrics(for: cue, maximumWidth: measure.staffFrame.width - 12)
                    XCTAssertEqual(metrics.lineCount, 1, "A short cue should retain its preferred font on one line")
                    let renderedCue = try XCTUnwrap(measure.cueTextLayouts.first)
                    XCTAssertEqual(renderedCue.scale, CGFloat(scale))
                    XCTAssertGreaterThan(renderedCue.frame.minY, measure.staffFrame.maxY)
                }
            }
        }
    }

    func testWrappedCueStacksAndMovedScaledCuesKeepPageAndStaffClearance() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for fontFamily in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                for density in StaffSystemDensity.allCases {
                    var chart = Chart.blank(title: "Performance Cue Clearance", measureCount: 12, layoutStyle: style)
                    chart.setMatchedFontFamily(fontFamily)
                    chart.setStaffSystemDensity(density)
                    chart.systems = chart.measures.enumerated().map { index, measure in
                        ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced, measures: [measure])
                    }
                    let cueFreeLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: 1_100))
                    let firstID = chart.measures[0].id
                    let aboveID = try XCTUnwrap(chart.addCueText("First time softly\nBuild into the chorus", anchorMeasureID: firstID, position: .above))
                    XCTAssertTrue(chart.updateCueText(aboveID, scale: 1.25, verticalOffset: -12))
                    let stackedMeasureID = chart.measures[3].id
                    let longID = try XCTUnwrap(chart.addCueText("Bring the horns in softly after the guitar solo", anchorMeasureID: stackedMeasureID, position: .below))
                    XCTAssertTrue(chart.updateCueText(longID, scale: 1.25))
                    XCTAssertTrue(chart.moveCueText(longID, to: stackedMeasureID, atFraction: 0.25, verticalOffset: 12))
                    let shortID = try XCTUnwrap(chart.addCueText("Horns enter", anchorMeasureID: stackedMeasureID, position: .below))
                    XCTAssertTrue(chart.updateCueText(shortID, scale: 0.75, verticalOffset: 12))
                    _ = try XCTUnwrap(chart.addCueText("Repeat softly, then build into the final chorus", anchorMeasureID: chart.measures[11].id, position: .below))
                    let originalChart = chart
                    let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: 1_100))
                    XCTAssertGreaterThan(layout.pages.count, 1)
                    let originalMeasures = Dictionary(uniqueKeysWithValues: cueFreeLayout.systems.flatMap(\.measures).compactMap { measure in
                        measure.sourceMeasureID.map { ($0, measure) }
                    })
                    for page in layout.pages {
                        let systems = layout.systems.filter { page.systemIDs.contains($0.id) }
                        for system in systems {
                            for measure in system.measures {
                                if let sourceID = measure.sourceMeasureID, let originalMeasure = originalMeasures[sourceID] {
                                    XCTAssertEqual(measure.staffFrame.size, originalMeasure.staffFrame.size)
                                    XCTAssertEqual(measure.chordBandFrame.size, originalMeasure.chordBandFrame.size)
                                }
                                for cue in measure.cueTextLayouts {
                                    XCTAssertTrue(page.frame.contains(cue.frame))
                                    XCTAssertLessThanOrEqual(cue.frame.maxY, page.frame.maxY - 54)
                                    XCTAssertFalse(cue.frame.intersects(measure.staffFrame), "Wrapped above/below cues must clear the staff or chord grid")
                                }
                            }
                        }
                        for (previous, next) in zip(systems, systems.dropFirst()) {
                            XCTAssertGreaterThanOrEqual(next.spacingContentBounds(for: chart).minY - previous.spacingContentBounds(for: chart).maxY, 8 - 0.01)
                        }
                    }
                    let stackedMeasure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == stackedMeasureID })
                    let longCue = try XCTUnwrap(stackedMeasure.cueTextLayouts.first { $0.id == longID })
                    let shortCue = try XCTUnwrap(stackedMeasure.cueTextLayouts.first { $0.id == shortID })
                    XCTAssertGreaterThanOrEqual(shortCue.frame.minY - longCue.frame.maxY, 3 - 0.01)
                    XCTAssertEqual(longCue.beatFraction, 0.25)
                    XCTAssertEqual(longCue.verticalOffset, 12)
                    XCTAssertEqual(longCue.scale, 1.25)
                    XCTAssertGreaterThan(try XCTUnwrap(layout.systems.first).spacingContentBounds(for: chart).minY, layout.header.handwrittenFrame.maxY)
                    XCTAssertEqual(chart, originalChart, "Layout must preserve entered text, scale, and moved anchors")
                }
            }
        }
    }

    func testBelowCueClearsPaintedQuarterStemsFlagsAndBeamsWithoutChangingNotation() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let rhythmMaps: [[RhythmValue]] = [
            [.quarter, .quarter, .quarter, .quarter],
            [.sixteenth, .sixteenthRest, .eighthRest, .quarter, .eighth, .eighth, .quarter]
        ]
        for fontFamily in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
            for (index, rhythmMap) in rhythmMaps.enumerated() {
                var chart = Chart.blank(title: "Rhythm Cue Clearance", measureCount: 4, layoutStyle: .rhythmSectionSheet)
                chart.setMatchedFontFamily(fontFamily)
                let measureID = chart.measures[1].id
                XCTAssertTrue(chart.setMeasureRhythmMap(rhythmMap, for: measureID))
                let originalLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: 1_100))
                let originalMeasure = try XCTUnwrap(originalLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let cueID = try XCTUnwrap(chart.addCueText("Horns enter", anchorMeasureID: measureID, position: .below))
                let originalChart = chart
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: 1_100))
                let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let cue = try XCTUnwrap(measure.cueTextLayouts.first { $0.id == cueID })
                let renderer = LeadSheetNotationRenderer(chart: chart)
                let paintedBounds = measure.noteLayouts.map { renderer.notePaintedBounds($0) }
                let paintedBottom = try XCTUnwrap(paintedBounds.map(\.maxY).max())
                XCTAssertGreaterThan(paintedBottom, measure.staffFrame.maxY + 9.9, "This fixture must include the downward stems that used to enter the cue frame")
                XCTAssertGreaterThanOrEqual(cue.frame.minY - paintedBottom, 5 - 0.01)
                XCTAssertFalse(paintedBounds.contains { $0.intersects(cue.frame) })
                XCTAssertEqual(measure.noteLayouts.count, originalMeasure.noteLayouts.count)
                // Layout-only note IDs are regenerated by each pass. Compare
                // every other field while keeping all geometry assertions.
                let normalizedNotes = zip(measure.noteLayouts, originalMeasure.noteLayouts).map { current, original in
                    var normalized = current
                    normalized.id = original.id
                    return normalized
                }
                XCTAssertEqual(normalizedNotes, originalMeasure.noteLayouts, "Cue clearance must not change the note positions, stems, flags, or beams")
                if index == 0 {
                    XCTAssertEqual(measure.noteLayouts.count, 4)
                } else {
                    XCTAssertTrue(measure.noteLayouts.contains { $0.flagStyle == .double && $0.beamEndPoint == nil }, "The fixture must paint an isolated double flag")
                    XCTAssertTrue(measure.noteLayouts.contains { $0.beamEndPoint != nil }, "The fixture must paint a beam")
                }
                XCTAssertEqual(chart, originalChart)
            }
        }
    }

    private func assertCueExportIsComplete(_ enteredText: String, label: String) async throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let output = try proofOutputDirectory(label: label)
        defer {
            if !output.keepArtifacts {
                try? FileManager.default.removeItem(at: output.url)
            }
        }

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
          for fontFamily in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
            var chart = Chart.blank(title: "Performance Cue Export", measureCount: 4, layoutStyle: layoutStyle)
            chart.setMatchedFontFamily(fontFamily)
            let measureIDs = chart.measures.map(\.id)
            for (measureID, chordText) in zip(measureIDs, ["Cmaj7", "A-7", "D-7", "G7"]) {
                if layoutStyle == .rhythmSectionSheet {
                    XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
                }
                XCTAssertTrue(chart.appendRecognizedChord(
                    try ChordSymbolParser.parse(chordText), rawInput: chordText,
                    to: measureID, atFraction: 0.05
                ))
            }
            let cueID = try XCTUnwrap(chart.addCueText(
                enteredText, anchorMeasureID: measureIDs[1], position: .below, emphasis: .normal
            ))
            let originalChart = chart
            let layout = LeadSheetPageLayoutEngine.pageLayout(
                for: chart, pageSize: CGSize(width: 932, height: 1_100)
            )
            let system = try XCTUnwrap(layout.systems.first { system in
                system.measures.contains { $0.sourceMeasureID == measureIDs[1] }
            })
            let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measureIDs[1] })
            let cue = try XCTUnwrap(measure.cueTextLayouts.first { $0.id == cueID })
            let paper = try XCTUnwrap(layout.pages.first { $0.systemIDs.contains(system.id) })
            XCTAssertEqual(cue.text, enteredText, "The entered cue must remain complete in the layout")
            XCTAssertTrue(paper.frame.contains(cue.frame), "The cue must remain inside its paper page")
            if layoutStyle == .rhythmSectionSheet {
                let renderer = LeadSheetNotationRenderer(chart: chart)
                let paintedBottom = try XCTUnwrap(measure.noteLayouts.map { renderer.notePaintedBounds($0).maxY }.max())
                XCTAssertGreaterThanOrEqual(cue.frame.minY - paintedBottom, 5 - 0.01,
                    "The exported cue frame must clear the actual note and stem paint bounds")
            }

            let directory = output.url.appendingPathComponent("\(layoutStyle.rawValue)-\(fontFamily.rawValue)", isDirectory: true)
            let exported = try await PDFChartExporter(exportDirectory: directory).exportPDF(for: chart)
            let bytes = try Data(contentsOf: exported.url)
            let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "com.adobe.pdf")
            attachment.name = "\(label)-\(layoutStyle.rawValue)-\(fontFamily.rawValue).pdf"
            attachment.lifetime = .keepAlways
            add(attachment)

            let document = try XCTUnwrap(PDFDocument(data: bytes))
            XCTAssertEqual(document.pageCount, layout.pages.count)
            let pageIndex = try XCTUnwrap(layout.pages.firstIndex { $0.systemIDs.contains(system.id) })
            let page = try XCTUnwrap(document.page(at: pageIndex))
            let pageText = page.string ?? ""
            let normalizedText = pageText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let normalizedCue = enteredText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            XCTAssertTrue(normalizedText.contains(normalizedCue),
                "\(layoutStyle) omitted entered cue text or its ending. Exported text: \(normalizedText)")
            XCTAssertTrue(normalizedText.contains("final chorus"),
                "\(layoutStyle) must retain the performance instruction's final words")

            let endingRange = (pageText as NSString).range(of: "chorus")
            if endingRange.location != NSNotFound, let endingSelection = page.selection(for: endingRange) {
                let endingBounds = endingSelection.bounds(for: page)
                let pageBounds = page.bounds(for: .mediaBox)
                let cuePDFFrame = CGRect(
                    x: cue.frame.minX - paper.frame.minX,
                    y: paper.frame.maxY - cue.frame.maxY,
                    width: cue.frame.width,
                    height: cue.frame.height
                )
                XCTAssertTrue(endingBounds.width > 0 && endingBounds.height > 0,
                    "The cue ending must have visible text geometry")
                XCTAssertTrue(pageBounds.contains(endingBounds), "The cue ending must remain on its PDF page")
                XCTAssertTrue(cuePDFFrame.insetBy(dx: -2, dy: -2).contains(endingBounds),
                    "The cue ending must render inside the production cue frame: \(endingBounds) vs \(cuePDFFrame)")
            } else {
                XCTFail("\(layoutStyle) has no exported text geometry for the entered cue's ending")
            }
            XCTAssertEqual(chart, originalChart, "Export must preserve the entered cue and chart")
          }
        }
    }

    private func proofOutputDirectory(label: String) throws -> (url: URL, keepArtifacts: Bool) {
        let environment = ProcessInfo.processInfo.environment
        let configuredPath = ["ICHART_FINAL_CUE_EXPORT_PROOF_DIR", "TEST_RUNNER_ICHART_FINAL_CUE_EXPORT_PROOF_DIR"]
            .compactMap { environment[$0] }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let baseURL = configuredPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = baseURL.appendingPathComponent(label, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, configuredPath != nil)
    }
}
#endif

import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class CueTextFreeVerticalPlacementLayoutTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testExplicitManualCueTravelsBeyondLegacyLimitWithoutMovingMusicOrPages() throws {
        for style in styles {
            for density in StaffSystemDensity.allCases {
                var chart = try fixture(style: style)
                chart.setStaffSystemDensity(density)
                let ownerID = chart.measures[2].id
                let cueID = try XCTUnwrap(chart.addCueText("Move this cue", anchorMeasureID: ownerID, position: .below))
                let before = plan(chart)
                let initial = try cue(cueID, in: before)
                let system = try system(ownerID, in: before)
                let paper = before.paperFrame(for: system)
                let top = max(paper.minY + 4, before.header.handwrittenFrame.maxY + 4)
                for request in [-180.0, 180.0] {
                    var moved = chart
                    XCTAssertTrue(moved.setCueTextManualVerticalOffset(cueID, to: request))
                    let after = plan(moved)
                    let displayed = try cue(cueID, in: after)
                    let expectedY = min(max(initial.frame.minY + CGFloat(request), top),
                        paper.maxY - 54 - initial.frame.height)
                    XCTAssertEqual(displayed.frame.minY, expectedY, accuracy: 0.0001)
                    XCTAssertEqual(displayed.verticalOffsetFromDefault,
                        expectedY - initial.frame.minY, accuracy: 0.0001)
                    XCTAssertEqual(displayed.frame.minX, initial.frame.minX, accuracy: 0.0001)
                    XCTAssertEqual(displayed.frame.size, initial.frame.size)
                    assertFixedMusic(after, before, chart: chart)
                    XCTAssertEqual(moved.measures.map(\.chordEvents), chart.measures.map(\.chordEvents))
                    XCTAssertEqual(moved.measures.map(\.rhythmMap), chart.measures.map(\.rhythmMap))
                    if request > 0 {
                        XCTAssertGreaterThan(displayed.verticalOffsetFromDefault, 72,
                            "An explicit drag must use the paper beyond the old local 72-point range")
                    }
                }
            }
        }
    }

    func testExplicitPlacementCanCrossAChordAndStaffWhileLegacyOffsetsRemainConstrained() throws {
        for style in styles {
            var chart = try fixture(style: style)
            let ownerID = chart.measures[2].id
            let cueID = try XCTUnwrap(chart.addCueText("Across the music", anchorMeasureID: ownerID, position: .below))
            let before = plan(chart)
            let initial = try cue(cueID, in: before)
            let owner = try measure(ownerID, in: before)
            let chord = try XCTUnwrap(owner.chordLayouts.first)
            let request = Double(chord.naturalFrame.midY - initial.frame.height / 2 - initial.frame.minY)
            var legacy = chart
            XCTAssertTrue(legacy.setCueTextVerticalOffset(cueID, to: request))
            XCTAssertNil(legacy.cueText(id: cueID)?.manualVerticalOffset)
            let legacyFrame = try cue(cueID, in: plan(legacy)).frame

            XCTAssertTrue(chart.setCueTextManualVerticalOffset(cueID, to: request))
            let manual = plan(chart)
            let displayed = try cue(cueID, in: manual)
            XCTAssertEqual(displayed.frame.midY, chord.naturalFrame.midY, accuracy: 0.0001)
            XCTAssertTrue(displayed.frame.intersects(chord.naturalFrame),
                "Manual placement must cross printed music instead of treating the chord as a movement fence")
            XCTAssertNotEqual(displayed.frame.minY, legacyFrame.minY)
            assertFixedMusic(manual, before, chart: chart)
        }
    }

    func testFreePreviewUsesFrozenGeometryAndMatchesCommitAcrossLargeOffsets() throws {
        for style in styles {
            var chart = try fixture(style: style)
            let ownerID = chart.measures[2].id
            let cueID = try XCTUnwrap(chart.addCueText("Frozen preview", anchorMeasureID: ownerID,
                position: .below, atFraction: 0.375))
            let before = plan(chart)
            let owner = try measure(ownerID, in: before)
            let placement = CueTextHorizontalPlacement(region: .measure, fraction: 0.413,
                wrapWidth: Double(max(1, owner.staffFrame.width - 12)))
            let template = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreviewTemplate(chart: chart,
                sourcePageLayout: before, cueID: cueID, targetMeasureID: ownerID,
                fraction: 0.375, horizontalPlacement: placement))
            for offset in [-10_000.0, -180, -80, 0, 80, 180, 10_000] {
                let preview = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreview(chart: chart,
                    sourcePageLayout: before, cueID: cueID, targetMeasureID: ownerID,
                    fraction: 0.375, verticalOffset: offset, horizontalPlacement: placement,
                    template: template, usesFreeVerticalPlacement: true))
                var committed = chart
                XCTAssertTrue(committed.moveCueText(cueID, to: ownerID, atFraction: 0.375,
                    horizontalPlacement: placement, manualVerticalOffset: offset))
                let after = plan(committed)
                let rendered = try cue(cueID, in: after)
                assertFrame(preview.frame, rendered.frame)
                assertFrame(preview.hitFrame, rendered.hitFrame)
                XCTAssertEqual(preview.verticalOffsetFromDefault, rendered.verticalOffsetFromDefault, accuracy: 0.0001)
                assertFixedMusic(after, before, chart: chart)
            }
            XCTAssertNil(chart.cueText(id: cueID)?.manualVerticalOffset)
        }
    }

    func testManualPlacementStopsAtActualHeaderAndFooterOnItsOwningPaper() throws {
        for style in styles {
            for atEnd in [false, true] {
                var chart = try fixture(style: style, measureCount: 30)
                let ownerID = atEnd ? try XCTUnwrap(chart.measures.last?.id) : chart.measures[2].id
                let cueID = try XCTUnwrap(chart.addCueText("Paper limits", anchorMeasureID: ownerID, position: .below))
                let before = plan(chart)
                let originalSystem = try system(ownerID, in: before)
                let page = try XCTUnwrap(before.pages.first { $0.systemIDs.contains(originalSystem.id) })
                if atEnd { XCTAssertFalse(page.includesHeader, "The fixture must exercise a continuation paper page") }
                for offset in [-1_000_000.0, 1_000_000] {
                    var moved = chart
                    XCTAssertTrue(moved.setCueTextManualVerticalOffset(cueID, to: offset))
                    let after = plan(moved)
                    let displayed = try cue(cueID, in: after)
                    let minimumY = page.includesHeader
                        ? max(page.frame.minY + 4, after.header.handwrittenFrame.maxY + 4)
                        : page.frame.minY + 4
                    if offset < 0 {
                        XCTAssertEqual(displayed.frame.minY, minimumY, accuracy: 0.0001)
                    } else {
                        XCTAssertEqual(displayed.frame.maxY, page.frame.maxY - 54, accuracy: 0.0001)
                    }
                    XCTAssertTrue(page.frame.insetBy(dx: -0.001, dy: -0.001).contains(displayed.frame))
                    assertFixedMusic(after, before, chart: chart)
                }
            }
        }
    }

    func testSavedManualOffsetAndSharedDocumentPlanSurviveReopen() throws {
        for style in styles {
            var chart = try fixture(style: style)
            let ownerID = chart.measures[2].id
            let cueID = try XCTUnwrap(chart.addCueText("Saved position", anchorMeasureID: ownerID,
                position: .below, emphasis: .strong, atFraction: 0.625))
            chart.pageHandwrittenNotationData = Data([0x35, 0x67, 0x91])
            chart.sourcePDFLibraryItemID = UUID()
            let before = plan(chart)
            XCTAssertTrue(chart.setCueTextManualVerticalOffset(cueID, to: 240))
            let saved = plan(chart)
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart))
            XCTAssertEqual(reopened.cueText(id: cueID), chart.cueText(id: cueID))
            XCTAssertEqual(reopened.cueText(id: cueID)?.manualVerticalOffset, 240)
            XCTAssertEqual(reopened.cueText(id: cueID)?.verticalOffset, 72,
                "The legacy mirror remains bounded for older builds without limiting the current placement")
            XCTAssertEqual(reopened.pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
            XCTAssertEqual(reopened.sourcePDFLibraryItemID, chart.sourcePDFLibraryItemID)
            XCTAssertEqual(reopened.measures.map(\.chordEvents), chart.measures.map(\.chordEvents))
            let after = plan(reopened)
            assertFixedMusic(after, before, chart: chart)
            XCTAssertEqual(try cue(cueID, in: after), try cue(cueID, in: saved))
            XCTAssertEqual(try cue(cueID, in: plan(reopened, viewportHeight: 2400)), try cue(cueID, in: saved))
            let template = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreviewTemplate(chart: reopened,
                sourcePageLayout: after, cueID: cueID, targetMeasureID: ownerID, fraction: 0.625))
            let preview = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreview(chart: reopened,
                sourcePageLayout: after, cueID: cueID, targetMeasureID: ownerID,
                fraction: 0.625, verticalOffset: 240, template: template))
            assertFrame(preview.frame, try cue(cueID, in: saved).frame)
        }
    }

    private func fixture(style: ChartLayoutStyle, measureCount: Int = 12) throws -> Chart {
        var chart = Chart.blank(title: "Free cue movement", measureCount: measureCount, layoutStyle: style)
        let measures = chart.measures
        chart.systems = stride(from: 0, to: measures.count, by: 2).enumerated().map { index, start in
            ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced,
                measures: Array(measures[start..<min(start + 2, measures.count)]))
        }
        for measure in chart.measures {
            if style == .rhythmSectionSheet {
                XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measure.id))
            }
            _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("C7"),
                rawInput: "C7", to: measure.id, atFraction: 0,
                sourceInkData: Data([0x17, 0x39, 0x55]), sourceCandidateSignature: ["C7"]))
        }
        return chart
    }

    private func plan(_ chart: Chart, viewportHeight: CGFloat = 1100) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: viewportHeight))
    }

    private func cue(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetCueTextLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.cueTextLayouts).first { $0.id == id })
    }

    private func measure(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func system(_ ownerID: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetSystemLayout {
        try XCTUnwrap(layout.systems.first { $0.measures.contains { $0.sourceMeasureID == ownerID } })
    }

    private func assertFrame(_ actual: CGRect, _ expected: CGRect,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
    }

    private func assertFixedMusic(_ actual: LeadSheetPageLayout, _ expected: LeadSheetPageLayout, chart: Chart,
                                  file: StaticString = #filePath, line: UInt = #line) {
        // Packing and note engraving create fresh layout-only UUIDs. Compare
        // persistent measure ownership and the geometry the renderer paints.
        XCTAssertEqual(actual.pages.map(\.index), expected.pages.map(\.index), file: file, line: line)
        XCTAssertEqual(actual.pages.map(\.frame), expected.pages.map(\.frame), file: file, line: line)
        XCTAssertEqual(actual.pages.map(\.includesHeader), expected.pages.map(\.includesHeader), file: file, line: line)
        func measuresByPaper(_ layout: LeadSheetPageLayout) -> [[UUID]] {
            layout.pages.map { page in
                layout.systems.filter { page.systemIDs.contains($0.id) }
                    .flatMap(\.measures).compactMap(\.sourceMeasureID)
            }
        }
        XCTAssertEqual(measuresByPaper(actual), measuresByPaper(expected), file: file, line: line)
        XCTAssertEqual(actual.systems.map(\.frame), expected.systems.map(\.frame), file: file, line: line)
        XCTAssertEqual(actual.systems.map(\.staffLineYPositions), expected.systems.map(\.staffLineYPositions), file: file, line: line)
        XCTAssertEqual(actual.systems.flatMap(\.measures).map(\.staffFrame),
            expected.systems.flatMap(\.measures).map(\.staffFrame), file: file, line: line)
        XCTAssertEqual(actual.systems.flatMap(\.measures).map(\.chordLayouts),
            expected.systems.flatMap(\.measures).map(\.chordLayouts), file: file, line: line)
        XCTAssertEqual(actual.systems.flatMap(\.measures).map { $0.noteLayouts.map { $0.paintedBounds(for: chart) } },
            expected.systems.flatMap(\.measures).map { $0.noteLayouts.map { $0.paintedBounds(for: chart) } },
            file: file, line: line)
        XCTAssertEqual(actual.systems.map(\.endingLayouts), expected.systems.map(\.endingLayouts), file: file, line: line)
        XCTAssertEqual(actual.systems.map(\.roadmapMarkerLayouts), expected.systems.map(\.roadmapMarkerLayouts), file: file, line: line)
    }
}

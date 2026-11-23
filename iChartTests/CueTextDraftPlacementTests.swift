import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class CueTextDraftPlacementTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testNewCueUsesChosenMeasureAndItsMeterWhenSnappingTheSelectedAnchor() throws {
        for style in styles {
            for position in [CuePosition.above, .below] {
                var chart = Chart.blank(title: "Selected cue anchor", measureCount: 4, layoutStyle: style)
                let ids = chart.measures.map(\.id)
                chart.systems[0].measures[2].meterOverride = Meter(numerator: 6, denominator: 8)
                let originalEvents = chart.measures.map(\.chordEvents)
                let cueID = try XCTUnwrap(chart.addCueText("  Horns enter  ", anchorMeasureID: ids[2],
                    position: position, emphasis: .strong, atFraction: 0.10))

                let cue = try XCTUnwrap(chart.cueText(id: cueID))
                XCTAssertEqual(cue.anchorMeasureID, ids[2])
                XCTAssertEqual(try XCTUnwrap(cue.beatFraction), 1.0 / 12.0, accuracy: 1e-12)
                XCTAssertEqual(cue.position, position)
                XCTAssertEqual(cue.emphasis, .strong)
                XCTAssertEqual(cue.text, "Horns enter")
                XCTAssertEqual(cue.rawInput, "Horns enter")
                XCTAssertEqual(chart.measure(id: ids[2])?.cueTextIDs, [cueID])
                XCTAssertTrue(chart.measures.filter { $0.id != ids[2] }.allSatisfy(\.cueTextIDs.isEmpty))
                XCTAssertEqual(chart.measures.map(\.chordEvents), originalEvents)
            }
        }
    }

    func testEditingTextRetainsAllPlacementAndAppearanceMetadataIncludingSavedEdgePositions() throws {
        for style in styles {
            for position in CuePosition.allCases {
                var chart = Chart.blank(title: "Retained cue edit", measureCount: 4, layoutStyle: style)
                let ids = chart.measures.map(\.id)
                let cueID = try XCTUnwrap(chart.addCueText("Old instruction", anchorMeasureID: ids[2],
                    position: position, emphasis: .strong, atFraction: 0.38))
                XCTAssertTrue(chart.updateCueText(cueID, scale: 1.5, verticalOffset: -17.25))
                let otherID = try XCTUnwrap(chart.addCueText("Keep this cue", anchorMeasureID: ids[1],
                    position: .below, emphasis: .subtle, atFraction: 0.75))
                let before = try XCTUnwrap(chart.cueText(id: cueID))
                let otherBefore = try XCTUnwrap(chart.cueText(id: otherID))
                let referencesBefore = chart.measures.map(\.cueTextIDs)

                XCTAssertTrue(chart.updateCueText(cueID, text: "  First pass softly\nThen horns enter  "))

                let edited = try XCTUnwrap(chart.cueText(id: cueID))
                var expected = before
                expected.text = "First pass softly\nThen horns enter"
                expected.rawInput = expected.text
                XCTAssertEqual(edited, expected,
                    "Editing the words must retain ID, measure, beat anchor, offset, position, scale and emphasis")
                XCTAssertEqual(chart.cueText(id: otherID), otherBefore)
                XCTAssertEqual(chart.measures.map(\.cueTextIDs), referencesBefore)
                XCTAssertEqual(edited.beatFraction, 0.375)
            }
        }
    }

    func testInvalidAddOrBlankEditLeavesTheExistingChartAndCueUnchanged() throws {
        for style in styles {
            var chart = Chart.blank(title: "Rejected cue drafts", measureCount: 3, layoutStyle: style)
            let target = chart.measures[1].id
            let cueID = try XCTUnwrap(chart.addCueText("Retained instruction", anchorMeasureID: target,
                position: .above, atFraction: 0.25))
            XCTAssertTrue(chart.updateCueText(cueID, scale: 1.25, emphasis: .strong, verticalOffset: 12))
            let before = chart

            XCTAssertNil(chart.addCueText("  \n  ", anchorMeasureID: target, position: .below, atFraction: 0.5))
            XCTAssertEqual(chart, before)
            XCTAssertNil(chart.addCueText("Wrong target", anchorMeasureID: UUID(), position: .below, atFraction: 0.5))
            XCTAssertEqual(chart, before)
            XCTAssertFalse(chart.updateCueText(cueID, text: "  \n  "))
            XCTAssertEqual(chart, before)
        }
    }

    func testEditedCueSavesAndReopensWithItsSelectedAnchorAndAllExistingMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for style in styles {
            var chart = try musicFixture(style: style, density: .standard)
            let measureID = chart.measures[3].id
            let cueID = try XCTUnwrap(chart.addCueText("Initial instruction", anchorMeasureID: measureID,
                position: .below, emphasis: .strong, atFraction: 0.625))
            XCTAssertTrue(chart.updateCueText(cueID, scale: 1.375, verticalOffset: 18.5))
            XCTAssertTrue(chart.updateCueText(cueID, text: "  Guitar rests\nHorns answer  "))
            let cueBefore = try XCTUnwrap(chart.cueText(id: cueID))
            let repository = FileChartRepository(url: root.appendingPathComponent("\(style.rawValue)-library.json"))
            try repository.saveSnapshot(ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id,
                entitlements: .free))

            let saved = try XCTUnwrap(repository.loadSnapshot())
            let reopened = try XCTUnwrap(saved.charts.first)
            XCTAssertEqual(saved.selectedChartID, chart.id)
            XCTAssertEqual(reopened, chart)
            XCTAssertEqual(reopened.cueText(id: cueID), cueBefore)
            XCTAssertEqual(reopened.measure(id: measureID)?.cueTextIDs, [cueID])
            XCTAssertEqual(reopened.measures.map(\.chordEvents), chart.measures.map(\.chordEvents))
            XCTAssertEqual(reopened.measures.map(\.rhythmMap), chart.measures.map(\.rhythmMap))
            assertSameDocumentPlan(documentPlan(reopened), documentPlan(chart))
        }
    }

    func testBelowCuePreservesNoteGeometryAndSharedFixedPaperPlanAtEveryDensityInBothStyles() throws {
        for style in styles {
            for density in StaffSystemDensity.allCases {
                var chart = try musicFixture(style: style, density: density)
                let original = chart
                let measureID = chart.measures[3].id
                let before = documentPlan(chart)
                let beforeMeasure = try measure(measureID, in: before)
                let cueID = try XCTUnwrap(chart.addCueText("Keep the notes clear\nThen return softly",
                    anchorMeasureID: measureID, position: .below, emphasis: .strong, atFraction: 0.25))
                XCTAssertTrue(chart.updateCueText(cueID, scale: 1.5, verticalOffset: 18))
                let authored = chart
                let plan = documentPlan(chart)
                let afterMeasure = try measure(measureID, in: plan)
                let cue = try XCTUnwrap(afterMeasure.cueTextLayouts.first { $0.id == cueID })
                let noteBottom = afterMeasure.noteLayouts.reduce(afterMeasure.staffFrame.maxY) {
                    max($0, $1.paintedBounds(for: chart).maxY)
                }

                XCTAssertEqual(cue.text, "Keep the notes clear\nThen return softly")
                XCTAssertEqual(cue.position, .below)
                XCTAssertEqual(cue.beatFraction, 0.25)
                XCTAssertGreaterThanOrEqual(cue.frame.minY, noteBottom + 5 - 0.001)
                XCTAssertFalse(cue.frame.intersects(afterMeasure.staffFrame))
                XCTAssertFalse(afterMeasure.noteLayouts.contains { $0.paintedBounds(for: chart).intersects(cue.frame) })
                XCTAssertEqual(afterMeasure.staffFrame.size, beforeMeasure.staffFrame.size)
                XCTAssertEqual(afterMeasure.chordBandFrame.size, beforeMeasure.chordBandFrame.size)
                XCTAssertEqual(afterMeasure.noteLayouts.count, beforeMeasure.noteLayouts.count)
                XCTAssertEqual(afterMeasure.noteLayouts.count, style == .rhythmSectionSheet ? 4 : 0)
                let dx = afterMeasure.staffFrame.minX - beforeMeasure.staffFrame.minX
                let dy = afterMeasure.staffFrame.minY - beforeMeasure.staffFrame.minY
                for (afterNote, beforeNote) in zip(afterMeasure.noteLayouts, beforeMeasure.noteLayouts) {
                    assertFrame(afterNote.noteheadFrame, equals: beforeNote.noteheadFrame.offsetBy(dx: dx, dy: dy))
                    assertFrame(afterNote.paintedBounds(for: chart),
                        equals: beforeNote.paintedBounds(for: original).offsetBy(dx: dx, dy: dy))
                }
                XCTAssertEqual(chart.measures.map(\.chordEvents), original.measures.map(\.chordEvents))
                XCTAssertEqual(chart.measures.map(\.rhythmMap), original.measures.map(\.rhythmMap))
                assertPaperAndSystemClearance(plan, chart: chart)

                let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(chart))
                assertSameDocumentPlan(documentPlan(reopened), plan)
                assertSameDocumentPlan(documentPlan(reopened, viewportHeight: 2800), plan)
                XCTAssertEqual(chart, authored, "Measuring the canvas/export document plan must not rewrite saved cues")
            }
        }
    }

    func testLegacyCueWithoutOptionalPlacementFieldsRetainsCompatibleDefaults() throws {
        let measureID = UUID()
        let original = CueText(id: UUID(), text: "Legacy cue", anchorMeasureID: measureID,
            position: .leadingEdge, emphasis: .subtle, rawInput: "Legacy cue")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "scale")
        object.removeValue(forKey: "beatFraction")
        object.removeValue(forKey: "verticalOffset")
        let restored = try JSONDecoder().decode(CueText.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.scale, CueText.defaultScale)
        XCTAssertNil(restored.beatFraction)
        XCTAssertEqual(restored.verticalOffset, 0)
    }

    func testFrozenCuePreviewWithSameAnchorAndOffsetExactlyMatchesResolvedLayout() throws {
        for style in styles {
            let configurations: [(Double?, Double)] = [(nil, 0), (0.375, -18), (0.12345, 7)]
            for (fraction, offset) in configurations {
                let fixture = try annotationFixture(style: style, fraction: fraction, verticalOffset: offset)
                let chart = fixture.chart
                let plan = documentPlan(chart)
                let originalPlan = plan
                let originalChart = chart
                let cue = try XCTUnwrap(chart.cueText(id: fixture.cueID))
                let displayed = try XCTUnwrap(plan.systems.flatMap(\.measures).flatMap(\.cueTextLayouts)
                    .first { $0.id == cue.id })
                XCTAssertTrue(plan.systems.contains { !$0.endingLayouts.isEmpty && !$0.roadmapMarkerLayouts.isEmpty },
                    "This fixture must include unresolved ending/form obstacles alongside the wrapped cue")
                XCTAssertEqual(cue.scale, 1.5)
                XCTAssertTrue(cue.text.contains("\n"))
                XCTAssertEqual(cue.beatFraction, fraction)

                let preview = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreview(chart: chart,
                    sourcePageLayout: plan, cueID: cue.id, targetMeasureID: cue.anchorMeasureID,
                    fraction: cue.beatFraction, verticalOffset: cue.verticalOffset))

                XCTAssertEqual(preview, displayed,
                    "A no-op projection must neither double-apply collision offsets nor resnap a saved fractional anchor")
                XCTAssertEqual(chart, originalChart)
                XCTAssertEqual(plan, originalPlan)
            }
        }
    }

    func testFrozenCuePreviewRejectsMissingCueOrTargetWithoutChangingSourceValues() throws {
        for style in styles {
            let fixture = try annotationFixture(style: style, fraction: 0.25, verticalOffset: -12)
            let chart = fixture.chart
            let plan = documentPlan(chart)
            let originalChart = chart
            let originalPlan = plan
            let cue = try XCTUnwrap(chart.cueText(id: fixture.cueID))

            XCTAssertNil(LeadSheetPageLayoutEngine.cueTextMovePreview(chart: chart,
                sourcePageLayout: plan, cueID: UUID(), targetMeasureID: cue.anchorMeasureID,
                fraction: 0.5, verticalOffset: 12))
            XCTAssertNil(LeadSheetPageLayoutEngine.cueTextMovePreview(chart: chart,
                sourcePageLayout: plan, cueID: cue.id, targetMeasureID: UUID(),
                fraction: 0.5, verticalOffset: 12))
            XCTAssertEqual(chart, originalChart)
            XCTAssertEqual(plan, originalPlan)
        }
    }

    func testFrozenPreviewAfterDiscreteMeasureMoveMatchesTheNewFullDocumentLayout() throws {
        for style in styles {
            var fixture = try annotationFixture(style: style, fraction: 0.25, verticalOffset: -12)
            let cueBefore = try XCTUnwrap(fixture.chart.cueText(id: fixture.cueID))
            let targetID = fixture.chart.measures[4].id
            XCTAssertNotEqual(targetID, cueBefore.anchorMeasureID)
            let roadmapBefore = fixture.chart.roadmapObjects
            XCTAssertTrue(fixture.chart.moveCueText(cueBefore.id, to: targetID,
                atFraction: 0.625, verticalOffset: 22))
            let refreshed = documentPlan(fixture.chart)
            let cue = try XCTUnwrap(fixture.chart.cueText(id: cueBefore.id))
            let displayed = try XCTUnwrap(refreshed.systems.flatMap(\.measures).flatMap(\.cueTextLayouts)
                .first { $0.id == cue.id })

            let preview = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreview(chart: fixture.chart,
                sourcePageLayout: refreshed, cueID: cue.id, targetMeasureID: cue.anchorMeasureID,
                fraction: cue.beatFraction, verticalOffset: cue.verticalOffset))

            XCTAssertEqual(preview, displayed)
            XCTAssertEqual(cue.anchorMeasureID, targetID)
            XCTAssertEqual(cue.beatFraction, 0.625)
            XCTAssertEqual(cue.text, cueBefore.text)
            XCTAssertEqual(cue.scale, cueBefore.scale)
            XCTAssertEqual(cue.emphasis, cueBefore.emphasis)
            XCTAssertEqual(fixture.chart.roadmapObjects, roadmapBefore)
            XCTAssertFalse(fixture.chart.measure(id: cueBefore.anchorMeasureID)?.cueTextIDs.contains(cue.id) == true)
            XCTAssertTrue(fixture.chart.measure(id: targetID)?.cueTextIDs.contains(cue.id) == true)
        }
    }

    private func annotationFixture(style: ChartLayoutStyle, fraction: Double?, verticalOffset: Double)
        throws -> (chart: Chart, cueID: UUID) {
        var chart = Chart.blank(title: "Frozen cue annotations", measureCount: 6, layoutStyle: style)
        chart.setStaffSystemDensity(.dense)
        let measures = chart.measures
        chart.systems = stride(from: 0, to: measures.count, by: 3).enumerated().map { index, start in
            ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced,
                measures: Array(measures[start..<start + 3]))
        }
        let anchor = measures[0].id
        let cueID = try XCTUnwrap(chart.addCueText("Muted attack\nBuild into the chorus", anchorMeasureID: anchor,
            position: .above, emphasis: .strong, atFraction: fraction))
        let cueIndex = try XCTUnwrap(chart.cueTexts.firstIndex { $0.id == cueID })
        // A loaded chart may contain a precise legacy fraction that predates
        // the current add/move grid. Previewing it must preserve that value.
        chart.cueTexts[cueIndex].beatFraction = fraction
        XCTAssertTrue(chart.updateCueText(cueID, scale: 1.5, verticalOffset: verticalOffset))
        _ = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: anchor, endMeasureID: measures[1].id,
            displayText: "First pass only", endStyle: .open))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: anchor, displayText: "Fine on cue"))
        return (chart, cueID)
    }

    private func musicFixture(style: ChartLayoutStyle, density: StaffSystemDensity) throws -> Chart {
        var chart = Chart.blank(title: "Cue document plan", measureCount: 12, layoutStyle: style)
        chart.setStaffSystemDensity(density)
        chart.systems = chart.measures.enumerated().map { index, measure in
            ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced, measures: [measure])
        }
        for measure in chart.measures {
            if style == .rhythmSectionSheet {
                XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measure.id))
            }
            _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("Cmaj7"),
                rawInput: "Cmaj7", to: measure.id, atFraction: 0))
        }
        return chart
    }

    // ChartPDFRenderer uses this same fixed document width and minimum canvas
    // height. These portable checks cover its shared layout inputs and plan;
    // native PDF text/paint assertions live in FinalCueTextExportCompletenessTests.
    private func documentPlan(_ chart: Chart, viewportHeight: CGFloat = 1100) -> LeadSheetPageLayout {
        let width = LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart)
            ?? LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth
        return LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: width, height: viewportHeight))
    }

    private func measure(_ id: UUID, in plan: LeadSheetPageLayout) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(plan.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func measureIDsByPage(_ plan: LeadSheetPageLayout) -> [[UUID]] {
        plan.pages.map { page in
            plan.systems.filter { page.systemIDs.contains($0.id) }.flatMap(\.measures).compactMap(\.sourceMeasureID)
        }
    }

    private func assertSameDocumentPlan(_ actual: LeadSheetPageLayout, _ expected: LeadSheetPageLayout,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.pages.map(\.frame), expected.pages.map(\.frame), file: file, line: line)
        XCTAssertEqual(measureIDsByPage(actual), measureIDsByPage(expected), file: file, line: line)
        XCTAssertEqual(actual.systems.map(\.frame), expected.systems.map(\.frame), file: file, line: line)
        XCTAssertEqual(actual.systems.flatMap(\.measures).map(\.staffFrame),
            expected.systems.flatMap(\.measures).map(\.staffFrame), file: file, line: line)
        XCTAssertEqual(actual.systems.flatMap(\.measures).flatMap(\.cueTextLayouts),
            expected.systems.flatMap(\.measures).flatMap(\.cueTextLayouts), file: file, line: line)
    }

    private func assertFrame(_ actual: CGRect, equals expected: CGRect,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
    }

    private func assertPaperAndSystemClearance(_ plan: LeadSheetPageLayout, chart: Chart,
                                               file: StaticString = #filePath, line: UInt = #line) {
        for page in plan.pages {
            let systems = plan.systems.filter { page.systemIDs.contains($0.id) }
            for system in systems {
                let content = system.spacingContentBounds(for: chart)
                XCTAssertGreaterThanOrEqual(content.minY, page.frame.minY, file: file, line: line)
                XCTAssertLessThanOrEqual(content.maxY, page.frame.maxY - 54 + 0.001, file: file, line: line)
                for cue in system.measures.flatMap(\.cueTextLayouts) {
                    XCTAssertTrue(page.frame.contains(cue.frame), file: file, line: line)
                }
            }
            for (previous, next) in zip(systems, systems.dropFirst()) {
                XCTAssertGreaterThanOrEqual(next.spacingContentBounds(for: chart).minY
                    - previous.spacingContentBounds(for: chart).maxY, 8 - 0.001, file: file, line: line)
            }
        }
    }
}

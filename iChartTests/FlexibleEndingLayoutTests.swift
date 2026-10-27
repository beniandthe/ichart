import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class FlexibleEndingLayoutTests: XCTestCase {
    func testLegacyShortLabelsKeepCompactFramesAndSourceAnchors() throws {
        for style in ChartLayoutStyle.allCases {
            for density in StaffSystemDensity.allCases {
                for readability in NotationReadabilityPreset.allCases {
                    var chart = chart(style: style, density: density, count: 4)
                    chart.notationReadability = readability
                    let ids = chart.measures.map(\.id)
                    for (type, position, text) in [(RoadmapType.ending1, 0, "1."), (.ending2, 2, "2.")] {
                        _ = try XCTUnwrap(chart.addEndingSpan(type, startMeasureID: ids[position], endMeasureID: ids[position + 1]))
                        let layout = pageLayout(chart)
                        let ending = try XCTUnwrap(layout.systems.flatMap(\.endingLayouts).first { $0.text == text })
                        let measures = layout.systems.flatMap(\.measures)
                        let first = try XCTUnwrap(measures.first { $0.sourceMeasureID == ids[position] })
                        XCTAssertEqual(ending.frame.height, readability.endingHeight, accuracy: 0.001)
                        XCTAssertEqual(ending.frame.minX, first.staffFrame.minX + 4, accuracy: 0.001)
                        XCTAssertEqual(ending.labelLineCount, 1)
                        XCTAssertEqual(ending.laneIndex, 0)
                        XCTAssertTrue(ending.showsLeadingHook)
                        XCTAssertTrue(ending.showsTrailingHook)
                    }
                }
            }
        }
    }

    func testCustomLabelCanUseMoreThanSeventyPointsOfItsSpan() throws {
        var chart = chart(style: .simpleChordSheet, density: .standard, count: 2)
        let id = try addEnding("1–3, 5, 7–9, 11", from: 0, through: 1, to: &chart)
        let ending = try XCTUnwrap(pageLayout(chart).systems.flatMap(\.endingLayouts).first { $0.roadmapObjectID == id })
        XCTAssertGreaterThan(ending.labelFrame.width, 70)
        XCTAssertEqual(ending.labelFrame.width, ending.frame.width - 12, accuracy: 0.001)
        XCTAssertEqual(ending.text, "1–3, 5, 7–9, 11")
        XCTAssertTrue(ending.occupiedFrame.contains(ending.labelFrame))
    }

    func testLongOneMeasureLabelClearsPointAndSectionLabelsAtEveryDensity() throws {
        let text = "1, 2, 3, 4, 5, 6, 7, 8, 9, 10 then return to the introduction on the leader's cue"
        for style in ChartLayoutStyle.allCases {
            for density in StaffSystemDensity.allCases {
                var chart = chart(style: style, density: density, count: 16, perRow: 8)
                chart.notationReadability = .performance
                chart.repeatWings = true
                chart.addSectionLabel(text: "A")
                let firstID = chart.measures[0].id
                _ = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: firstID))
                _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: firstID, endMeasureID: chart.measures[7].id))
                let endingID = try addEnding(text, from: 0, through: 0, to: &chart)
                let originalSystems = chart.systems
                let layout = pageLayout(chart)
                let system = try XCTUnwrap(layout.systems.first)
                let ending = try XCTUnwrap(system.endingLayouts.first { $0.roadmapObjectID == endingID })
                let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == firstID })
                let metrics = LeadSheetEndingTextLayout.metrics(text: text, width: ending.labelFrame.width, chart: chart)
                XCTAssertGreaterThan(ending.labelLineCount, 1)
                XCTAssertGreaterThan(ending.frame.height, chart.notationReadability.endingHeight)
                XCTAssertGreaterThanOrEqual(ending.labelFrame.height + 0.001, metrics.height)
                XCTAssertTrue(ending.frame.contains(ending.labelFrame))
                XCTAssertFalse(ending.frame.intersects(try XCTUnwrap(system.sectionTextFrame)))
                for marker in system.roadmapMarkerLayouts {
                    XCTAssertFalse(ending.frame.intersects(LeadSheetRoadmapMarkerLabelGeometry.labelFrame(for: marker)))
                }
                let contentTop = style == .simpleChordSheet ? measure.staffFrame.minY : measure.chordBandFrame.minY
                XCTAssertLessThanOrEqual(ending.occupiedFrame.maxY + 4, contentTop + 0.001)
                XCTAssertEqual(chart.systems, originalSystems)
                XCTAssertEqual(chart.staffSystemDensity, density)
                assertPageClearance(layout, chart: chart)
            }
        }
    }

    func testCustomLabelTextMetricsFitAllSelectableFontFamilies() throws {
        for font in ChartFontFamilyPreset.selectableCases {
            for readability in NotationReadabilityPreset.allCases {
                var chart = chart(style: .leadSheet, density: .standard, count: 1)
                chart.setMatchedFontFamily(font)
                chart.notationReadability = readability
                let text = "Play again quietly"
                _ = try addEnding(text, from: 0, through: 0, to: &chart)
                let ending = try XCTUnwrap(pageLayout(chart).systems.first?.endingLayouts.first)
                let metrics = LeadSheetEndingTextLayout.metrics(text: text, width: ending.labelFrame.width, chart: chart)
                XCTAssertGreaterThanOrEqual(ending.labelFrame.height + 0.001, metrics.height, font.rawValue)
                XCTAssertTrue(ending.frame.contains(ending.labelFrame))
            }
        }
    }

    func testOverlappingSpansUseCreationOrderedLanesAndSurviveReopen() throws {
        for style in ChartLayoutStyle.allCases {
            var chart = chart(style: style, density: .dense, count: 8)
            let first = try addEnding("1, 3, 5", from: 0, through: 5, to: &chart)
            let second = try addEnding("2, 4, 6", from: 0, through: 5, type: .ending2, to: &chart)
            let third = try addEnding("7, 8", from: 2, through: 3, type: .ending1, to: &chart)
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
            for source in [chart, reopened] {
                let layout = pageLayout(source)
                for system in layout.systems {
                    let endings = system.endingLayouts
                    for ending in endings {
                        XCTAssertEqual(ending.laneIndex, ending.roadmapObjectID == first ? 0 : (ending.roadmapObjectID == second ? 1 : 2))
                    }
                    for (index, ending) in endings.enumerated() {
                        for other in endings.dropFirst(index + 1) {
                            XCTAssertFalse(ending.occupiedFrame.intersects(other.occupiedFrame))
                        }
                    }
                }
                XCTAssertTrue(layout.systems.flatMap(\.endingLayouts).contains { $0.roadmapObjectID == third })
                assertPageClearance(layout, chart: source)
            }
        }
    }

    func testEndingAcrossSystemsAndPagesKeepsLabelAndHookOwnership() throws {
        for style in ChartLayoutStyle.allCases {
            for density in StaffSystemDensity.allCases {
                for endStyle in [EndingEndStyle.open, .closed] {
                    var chart = chart(style: style, density: density, count: 48)
                    let endingID = try addEnding("1–3, 5", from: 0, through: 47, to: &chart)
                    let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == endingID })
                    chart.roadmapObjects[index].endingEndStyle = endStyle
                    let layout = pageLayout(chart)
                    XCTAssertGreaterThan(layout.pages.count, 1)
                    let segments = layout.systems.flatMap(\.endingLayouts).filter { $0.roadmapObjectID == endingID }
                    XCTAssertGreaterThan(segments.count, 1)
                    for (index, segment) in segments.enumerated() {
                        XCTAssertEqual(segment.showsText, index == 0)
                        XCTAssertEqual(segment.showsLeadingHook, index == 0)
                        XCTAssertEqual(segment.showsTrailingHook, index == segments.count - 1 && endStyle == .closed)
                        XCTAssertEqual(segment.labelFrame.isEmpty, index != 0)
                    }
                    assertPageClearance(layout, chart: chart)
                }
            }
        }
    }

    private func chart(style: ChartLayoutStyle, density: StaffSystemDensity, count: Int, perRow: Int = 2) -> Chart {
        var chart = Chart.blank(title: "Flexible endings", measureCount: count, layoutStyle: style)
        chart.engravingPreset = .balanced
        chart.staffSystemDensity = density
        let measures = chart.measures
        chart.systems = stride(from: 0, to: measures.count, by: perRow).enumerated().map { index, start in
            ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced, measures: Array(measures[start..<min(start + perRow, measures.count)]))
        }
        for systemIndex in chart.systems.indices {
            for measureIndex in chart.systems[systemIndex].measures.indices {
                chart.systems[systemIndex].measures[measureIndex].manualLayoutWidth = 96
            }
        }
        return chart
    }

    private func addEnding(_ text: String, from first: Int, through last: Int, type: RoadmapType = .ending1, to chart: inout Chart) throws -> UUID {
        let id = try XCTUnwrap(chart.addEndingSpan(type, startMeasureID: chart.measures[first].id, endMeasureID: chart.measures[last].id))
        let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == id })
        chart.roadmapObjects[index].displayText = text
        return id
    }

    private func pageLayout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: 1100))
    }

    private func assertPageClearance(_ layout: LeadSheetPageLayout, chart: Chart, file: StaticString = #filePath, line: UInt = #line) {
        for page in layout.pages {
            let systems = layout.systems.filter { page.systemIDs.contains($0.id) }
            for system in systems {
                let bounds = system.spacingContentBounds(for: chart)
                XCTAssertGreaterThanOrEqual(bounds.minY, page.frame.minY, file: file, line: line)
                XCTAssertLessThanOrEqual(bounds.maxY, page.frame.maxY - 54 + 0.001, file: file, line: line)
            }
            for (previous, next) in zip(systems, systems.dropFirst()) {
                XCTAssertLessThanOrEqual(previous.spacingContentBounds(for: chart).maxY + 0.001, next.spacingContentBounds(for: chart).minY, file: file, line: line)
            }
        }
    }
}

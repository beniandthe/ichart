import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class StaffSystemDensityTests: XCTestCase {
    func testStandardRetainsOriginalEngravingGeometryAndFirstPageCapacity() throws {
        let originalMetrics: [(EngravingPreset, CGFloat, CGFloat, Int)] = [
            (.compact, 124, 18, 5),
            (.balanced, 132, 22, 5),
            (.wide, 156, 26, 4),
            (.bold, 137, 24, 5)
        ]
        for style in ChartLayoutStyle.allCases {
            for (preset, height, gap, capacity) in originalMetrics {
                var chart = makeChart(style: style)
                chart.engravingPreset = preset
                let layout = pageLayout(chart)
                let firstSystem = try XCTUnwrap(layout.systems.first)
                let secondSystem = try XCTUnwrap(layout.systems.dropFirst().first)
                XCTAssertEqual(chart.staffSystemDensity, .standard)
                XCTAssertEqual(firstSystem.frame.minY, 186, accuracy: 0.001)
                XCTAssertEqual(firstSystem.frame.height, height, accuracy: 0.001)
                XCTAssertEqual(secondSystem.frame.minY - firstSystem.frame.maxY, gap, accuracy: 0.001)
                XCTAssertEqual(layout.pages.first?.systemIDs.count, capacity)
            }
        }
    }

    func testCloserAndDenseFitMoreCompactSystemsWithoutShrinkingStaffOrChordLanes() throws {
        for style in ChartLayoutStyle.allCases {
            var chart = makeChart(style: style)
            let standard = pageLayout(chart)
            chart.setStaffSystemDensity(.close)
            let closer = pageLayout(chart)
            chart.setStaffSystemDensity(.dense)
            let dense = pageLayout(chart)

            XCTAssertEqual(standard.pages.first?.systemIDs.count, 5)
            XCTAssertEqual(closer.pages.first?.systemIDs.count, 6)
            XCTAssertEqual(dense.pages.first?.systemIDs.count, 7)
            for layout in [closer, dense] {
                let originalMeasure = try XCTUnwrap(standard.systems.first?.measures.first)
                let newMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
                XCTAssertEqual(newMeasure.staffFrame.size, originalMeasure.staffFrame.size)
                XCTAssertEqual(newMeasure.chordBandFrame.size, originalMeasure.chordBandFrame.size)
                XCTAssertEqual(newMeasure.writableFrame.size, originalMeasure.writableFrame.size)
                XCTAssertEqual(layout.systems.first?.staffLineYPositions.count, standard.systems.first?.staffLineYPositions.count)
                XCTAssertEqual(layout.header, standard.header)
                assertSystemClearance(layout, chart: chart)
            }
        }
    }

    func testDenseLeavesRoomForBelowCueRatherThanPullingItIntoStaff() throws {
        for style in ChartLayoutStyle.allCases {
            var chart = makeChart(style: style)
            chart.setStaffSystemDensity(.dense)
            let measureID = chart.measures[0].id
            let cueID = try XCTUnwrap(chart.addCueText("Play lightly", anchorMeasureID: measureID, position: .below))
            let layout = pageLayout(chart)
            let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
            let cue = try XCTUnwrap(firstMeasure.cueTextLayouts.first { $0.id == cueID })
            XCTAssertEqual(cue.frame.minY, firstMeasure.staffFrame.maxY + 5, accuracy: 0.001)
            XCTAssertLessThanOrEqual(cue.frame.maxY + 4, firstMeasure.frame.maxY)
            assertSystemClearance(layout, chart: chart)
        }
    }

    func testDenseReservesMovedCueAndScaledRoadmapClearanceAtHeaderAndPageBreaks() throws {
        for style in ChartLayoutStyle.allCases {
            var chart = makeChart(style: style)
            chart.setStaffSystemDensity(.dense)
            for (index, measure) in chart.measures.enumerated() {
                if index.isMultiple(of: 2) {
                    let cueID = try XCTUnwrap(chart.addCueText("Continue softly", anchorMeasureID: measure.id, position: .below))
                    XCTAssertTrue(chart.updateCueText(
                        cueID,
                        text: "Continue softly",
                        scale: CueText.maximumScale,
                        emphasis: .strong,
                        verticalOffset: CueText.maximumVerticalOffset
                    ))
                } else {
                    let markerID = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measure.id))
                    XCTAssertTrue(chart.resizePointRoadmapMarker(markerID, byScaleDelta: 10))
                }
            }
            let firstCueID = try XCTUnwrap(chart.addCueText("From here", anchorMeasureID: chart.measures[0].id, position: .above))
            XCTAssertTrue(chart.updateCueText(firstCueID, text: "From here", verticalOffset: CueText.minimumVerticalOffset))
            let layout = pageLayout(chart)
            XCTAssertGreaterThan(layout.pages.count, 1)
            let firstSystem = try XCTUnwrap(layout.systems.first)
            XCTAssertGreaterThan(firstSystem.spacingContentBounds(for: chart).minY, layout.header.handwrittenFrame.maxY)
            assertSystemClearance(layout, chart: chart)
        }
    }

    func testDenseReservesActualTrebleClefFlagsAndBeamsAcrossNotationFonts() throws {
        for font in NotationFontPreset.allCases {
            for preset in EngravingPreset.allCases {
                var chart = makeChart(style: .rhythmSectionSheet)
                chart.setNotationFont(font)
                chart.setEngravingPreset(preset)
                chart.defaultClef = .treble
                chart.hasExplicitClefSelection = true
                chart.setStaffSystemDensity(.dense)
                // One exact 4/4 bar: an isolated sixteenth flag, rests, and a
                // beamed pair of eighths. An underfilled map has no rendered slots.
                let rhythm: [RhythmValue] = [
                    .sixteenth, .sixteenthRest, .eighthRest, .quarter, .eighth, .eighth, .quarter
                ]
                for measure in chart.measures {
                    XCTAssertTrue(chart.setMeasureRhythmMap(rhythm, for: measure.id))
                    let savedMeasure = try XCTUnwrap(chart.measure(id: measure.id))
                    XCTAssertEqual(savedMeasure.rhythmMap?.status(for: chart.defaultMeter), .exact)
                }
                let layout = pageLayout(chart)
                let notes = layout.systems.flatMap(\.measures).flatMap(\.noteLayouts)
                XCTAssertEqual(notes.count, chart.measures.count * rhythm.count)
                XCTAssertTrue(notes.contains { $0.beamEndPoint != nil })
                XCTAssertTrue(notes.contains { $0.beamEndPoint == nil && $0.flagStyle == .double })
                assertSystemClearance(layout, chart: chart)
            }
        }
    }

    func testDenseRetainsEndingChordAndHeaderClearance() throws {
        var chart = makeChart(style: .rhythmSectionSheet)
        chart.setStaffSystemDensity(.dense)
        for measure in chart.measures {
            _ = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: measure.id, endMeasureID: measure.id))
            XCTAssertTrue(chart.appendRecognizedChord(try ChordSymbolParser.parse("Bb7"), rawInput: "Bb7", to: measure.id, atFraction: 0.05))
        }
        let layout = pageLayout(chart)
        for system in layout.systems {
            let measure = try XCTUnwrap(system.measures.first)
            let ending = try XCTUnwrap(system.endingLayouts.first)
            let chord = try XCTUnwrap(measure.chordLayouts.first)
            XCTAssertLessThanOrEqual(ending.frame.maxY, measure.chordBandFrame.minY)
            XCTAssertGreaterThanOrEqual(chord.frame.minY, measure.chordBandFrame.minY)
            XCTAssertLessThan(chord.frame.maxY, measure.staffFrame.minY)
        }
        assertSystemClearance(layout, chart: chart)
    }

    func testDensePaginationAndCanvasEstimateStayIndependentOfViewportHeight() {
        var chart = makeChart(style: .rhythmSectionSheet, systemCount: 24)
        chart.setStaffSystemDensity(.dense)
        let short = pageLayout(chart, height: 1_100)
        let tall = pageLayout(chart, height: 3_200)
        XCTAssertEqual(short.systems.map(\.frame), tall.systems.map(\.frame))
        XCTAssertEqual(short.pages.map(\.systemIDs.count), tall.pages.map(\.systemIDs.count))
        XCTAssertEqual(
            LeadSheetPageLayoutEngine.estimatedCanvasHeight(for: chart, pageSize: CGSize(width: 932, height: 1_100)),
            short.pageBounds.height,
            accuracy: 0.001
        )
    }

    func testDenseKeepsExplicitPageBreakAndMeasureOrder() {
        var chart = makeChart(style: .rhythmSectionSheet)
        chart.systems[4].startsNewPage = true
        chart.setStaffSystemDensity(.dense)
        let layout = pageLayout(chart)
        let firstPage = layout.pages[0]
        let secondPage = layout.pages[1]
        XCTAssertEqual(firstPage.systemIDs.count, 4)
        let secondPageFirstSystem = layout.systems.first { secondPage.systemIDs.contains($0.id) }
        XCTAssertEqual(secondPageFirstSystem?.measures.first?.sourceMeasureID, chart.measures[4].id)
        XCTAssertEqual(layout.systems.flatMap(\.measures).compactMap(\.sourceMeasureID), chart.measures.map(\.id))
        assertSystemClearance(layout, chart: chart)
    }

    func testLegacyChartWithoutDensityKeepsSavedLayoutAndInkCoordinateSpaces() throws {
        var chart = makeChart(style: .rhythmSectionSheet)
        chart.pageHandwrittenNotationData = Data([1, 2, 3])
        chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 932, height: 2_400)
        let originalLayout = pageLayout(chart)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(chart)) as? [String: Any])
        object.removeValue(forKey: "staffSystemDensity")
        let legacy = try JSONDecoder().decode(Chart.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.staffSystemDensity, .standard)
        XCTAssertEqual(legacy.pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
        XCTAssertEqual(legacy.pageHandwrittenNotationCoordinateSpace, chart.pageHandwrittenNotationCoordinateSpace)
        XCTAssertEqual(pageLayout(legacy).systems.map(\.frame), originalLayout.systems.map(\.frame))
    }

    func testExplicitDensityPersistsWithoutMutatingPageInkMeasureInkOrAnchors() throws {
        var chart = makeChart(style: .rhythmSectionSheet)
        let coordinateSpace = PersistentInkCoordinateSpace(width: 932, height: 2_400)
        chart.pageHandwrittenNotationData = Data([1, 2, 3])
        chart.pageHandwrittenNotationCoordinateSpace = coordinateSpace
        chart.pageHandwrittenChordData = Data([4, 5, 6])
        chart.pageHandwrittenChordCoordinateSpace = coordinateSpace
        chart.pageHandwrittenHeaderData = Data([7, 8, 9])
        chart.pageHandwrittenHeaderCoordinateSpace = coordinateSpace
        chart.systems[0].measures[0].handwrittenRhythmicNotationData = Data([10, 11, 12])
        let original = chart
        chart.setStaffSystemDensity(.dense)
        _ = pageLayout(chart)
        let restored = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
        XCTAssertEqual(restored.staffSystemDensity, .dense)
        XCTAssertEqual(restored.systems, original.systems)
        XCTAssertEqual(restored.pageHandwrittenNotationData, original.pageHandwrittenNotationData)
        XCTAssertEqual(restored.pageHandwrittenNotationCoordinateSpace, original.pageHandwrittenNotationCoordinateSpace)
        XCTAssertEqual(restored.pageHandwrittenChordData, original.pageHandwrittenChordData)
        XCTAssertEqual(restored.pageHandwrittenChordCoordinateSpace, original.pageHandwrittenChordCoordinateSpace)
        XCTAssertEqual(restored.pageHandwrittenHeaderData, original.pageHandwrittenHeaderData)
        XCTAssertEqual(restored.pageHandwrittenHeaderCoordinateSpace, original.pageHandwrittenHeaderCoordinateSpace)
    }

    private func makeChart(style: ChartLayoutStyle, systemCount: Int = 12) -> Chart {
        var chart = Chart.blank(title: "Density", measureCount: systemCount, layoutStyle: style)
        chart.engravingPreset = .compact
        chart.systems = chart.measures.enumerated().map { index, measure in
            ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced, measures: [measure])
        }
        return chart
    }

    private func pageLayout(_ chart: Chart, height: CGFloat = 1_100) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: height))
    }

    private func assertSystemClearance(_ layout: LeadSheetPageLayout, chart: Chart, file: StaticString = #filePath, line: UInt = #line) {
        for page in layout.pages {
            let systems = layout.systems.filter { page.systemIDs.contains($0.id) }
            for system in systems {
                let bounds = system.spacingContentBounds(for: chart)
                XCTAssertGreaterThanOrEqual(bounds.minY, page.frame.minY, file: file, line: line)
                XCTAssertLessThanOrEqual(bounds.maxY, page.frame.maxY - 54, file: file, line: line)
            }
            for (previous, next) in zip(systems, systems.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    next.spacingContentBounds(for: chart).minY - previous.spacingContentBounds(for: chart).maxY,
                    8,
                    file: file,
                    line: line
                )
            }
        }
    }
}

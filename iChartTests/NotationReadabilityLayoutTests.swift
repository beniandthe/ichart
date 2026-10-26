import CoreGraphics
import XCTest
@testable import iChart

final class NotationReadabilityLayoutTests: XCTestCase {
    private let pageSize = CGSize(width: 1180, height: 1500)

    func testStandardReadabilityPreservesLegacyRepeatBoundsInEveryLayout() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            var chart = Chart.blank(title: "Standard repeats", measureCount: 1, layoutStyle: layoutStyle)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureID, endMeasureID: measureID))

            let measure = try firstMeasure(in: chart)
            let staffSpace = max(CGFloat(1), measure.staffFrame.height / 4)
            let expectedWidth = layoutStyle == .simpleChordSheet
                ? max(CGFloat(8), staffSpace * 0.95)
                : max(CGFloat(12), staffSpace * 1.6)

            XCTAssertEqual(chart.notationReadability, .standard)
            XCTAssertFalse(chart.repeatWings)
            XCTAssertEqual(measure.repeatMarkerLayouts.count, 2)
            for marker in measure.repeatMarkerLayouts {
                XCTAssertEqual(marker.frame.width, expectedWidth, accuracy: 0.001)
                XCTAssertEqual(marker.frame.height, measure.staffFrame.height, accuracy: 0.001)
                XCTAssertEqual(marker.verticalOutset, 0)
                XCTAssertEqual(marker.occupiedFrame, marker.frame)
            }
        }
    }

    func testPerformanceWingedRepeatBoundsContainDecorationsWithoutChangingStaffAnchors() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            for engraving in EngravingPreset.allCases {
                var chart = Chart.blank(title: "Winged repeats", measureCount: 1, layoutStyle: layoutStyle)
                chart.notationReadability = .performance
                chart.repeatWings = true
                chart.engravingPreset = engraving
                let measureID = try XCTUnwrap(chart.measures.first?.id)
                _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureID, endMeasureID: measureID))

                let measure = try firstMeasure(in: chart)
                let metrics = LeadSheetRepeatReadabilityMetrics(chart: chart, staffHeight: measure.staffFrame.height)
                XCTAssertGreaterThan(metrics.verticalOutset, 0)
                for marker in measure.repeatMarkerLayouts {
                    let anchorX = marker.edge == .leading ? measure.staffFrame.minX : measure.staffFrame.maxX
                    XCTAssertEqual(marker.frame.midX, anchorX, accuracy: 0.001)
                    XCTAssertEqual(marker.frame.minY, measure.staffFrame.minY, accuracy: 0.001)
                    XCTAssertEqual(marker.frame.height, measure.staffFrame.height, accuracy: 0.001)
                    XCTAssertGreaterThanOrEqual(marker.frame.width + 0.001, metrics.horizontalExtent * 2)
                    XCTAssertLessThanOrEqual(marker.occupiedFrame.minY, measure.staffFrame.minY - metrics.verticalOutset + 0.001)
                    XCTAssertGreaterThanOrEqual(marker.occupiedFrame.maxY, measure.staffFrame.maxY + metrics.verticalOutset - 0.001)
                }
            }
        }
    }

    func testWingedCombinedBoundaryRetainsOnePairOfBarsAndBothRepeatDirections() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            var chart = Chart.blank(title: "Adjacent repeats", measureCount: 4, layoutStyle: layoutStyle)
            chart.notationReadability = .performance
            chart.repeatWings = true
            let measureIDs = chart.measures.map(\.id)
            _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[1]))
            _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[2], endMeasureID: measureIDs[3]))
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            let measures = layout.systems.flatMap(\.measures)
            let left = try XCTUnwrap(measures.first { $0.sourceMeasureID == measureIDs[1] })
            let right = try XCTUnwrap(measures.first { $0.sourceMeasureID == measureIDs[2] })
            let markers = LeadSheetRepeatBoundaryPolicy.repeatMarkers(after: left, before: right)

            XCTAssertEqual(markers.count, 2)
            XCTAssertEqual(Set(markers.map(\.edge)), [.leading, .trailing])
            XCTAssertEqual(LeadSheetRepeatBoundaryPolicy.visibleBarlineCount(for: markers), 2)
            XCTAssertFalse(LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(after: left, before: right))
            XCTAssertTrue(markers.allSatisfy { $0.occupiedFrame.height > $0.frame.height })
        }
    }

    func testPerformanceEndingAcrossSystemBreakPreservesHookOwnershipAndReadableHeight() throws {
        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Ending across systems", measureCount: 4, layoutStyle: layoutStyle)
            chart.notationReadability = .performance
            chart.repeatWings = true
            let measureIDs = chart.measures.map(\.id)
            XCTAssertTrue(chart.insertSystemBreak(before: measureIDs[2]))
            let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))
            _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))

            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            let segments = layout.systems.flatMap(\.endingLayouts).filter { $0.roadmapObjectID == endingID }
            XCTAssertEqual(segments.count, 2)
            let first = try XCTUnwrap(segments.first)
            let last = try XCTUnwrap(segments.last)
            XCTAssertTrue(first.showsText)
            XCTAssertTrue(first.showsLeadingHook)
            XCTAssertFalse(first.showsTrailingHook)
            XCTAssertFalse(last.showsText)
            XCTAssertFalse(last.showsLeadingHook)
            XCTAssertTrue(last.showsTrailingHook)
            for segment in segments {
                XCTAssertEqual(segment.frame.height, 26, accuracy: 0.001)
                let system = try XCTUnwrap(layout.systems.first { $0.index == segment.systemIndex })
                for measure in system.measures where measure.sourceMeasureID != nil {
                    let contentTop = layoutStyle == .simpleChordSheet ? measure.staffFrame.minY : measure.chordBandFrame.minY
                    XCTAssertLessThanOrEqual(segment.frame.maxY, contentTop)
                    for marker in measure.repeatMarkerLayouts {
                        XCTAssertFalse(segment.frame.intersects(marker.occupiedFrame))
                    }
                }
            }
        }
    }

    func testPerformanceLeadSheetEndingContinuesAcrossNaturalSystemWraps() throws {
        var chart = Chart.blank(title: "Lead sheet ending", measureCount: 8, layoutStyle: .leadSheet)
        chart.notationReadability = .performance
        chart.repeatWings = true
        let measureIDs = chart.measures.map(\.id)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: measureIDs[0], endMeasureID: measureIDs[7]))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 740, height: 1500))
        let segments = layout.systems.flatMap(\.endingLayouts).filter { $0.roadmapObjectID == endingID }

        XCTAssertGreaterThan(segments.count, 1)
        for (index, segment) in segments.enumerated() {
            XCTAssertEqual(segment.showsText, index == 0)
            XCTAssertEqual(segment.showsLeadingHook, index == 0)
            XCTAssertEqual(segment.showsTrailingHook, index == segments.count - 1)
            XCTAssertEqual(segment.frame.height, 26, accuracy: 0.001)
            let system = try XCTUnwrap(layout.systems.first { $0.index == segment.systemIndex })
            let measure = try XCTUnwrap(system.measures.first)
            XCTAssertLessThanOrEqual(segment.frame.maxY, measure.chordBandFrame.minY)
        }
    }

    func testPerformancePointMarkersScaleTheirFramesAndKeepChordClearance() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            var chart = Chart.blank(title: "Readable navigation", measureCount: 1, layoutStyle: layoutStyle)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            _ = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureID))
            let standard = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            let standardMarker = try XCTUnwrap(standard.systems.first?.roadmapMarkerLayouts.first)
            chart.notationReadability = .performance
            let performance = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            let system = try XCTUnwrap(performance.systems.first)
            let marker = try XCTUnwrap(system.roadmapMarkerLayouts.first)
            let measure = try XCTUnwrap(system.measures.first)

            XCTAssertEqual(marker.scale, standardMarker.scale * 1.18, accuracy: 0.001)
            XCTAssertGreaterThan(marker.frame.height, standardMarker.frame.height)
            let contentTop = layoutStyle == .simpleChordSheet ? measure.staffFrame.minY : measure.chordBandFrame.minY
            XCTAssertLessThanOrEqual(marker.frame.maxY, contentTop)
        }
    }

    func testSimpleChordSlotsReserveBothSidesOfWingedRepeatMeasure() throws {
        var chart = Chart.blank(title: "Dense repeat measure", measureCount: 4, layoutStyle: .simpleChordSheet)
        chart.notationReadability = .performance
        chart.repeatWings = true
        let measureID = chart.measures[1].id
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureID, endMeasureID: measureID))
        let chordTexts = ["C", "F", "G7", "C"]
        for (index, text) in chordTexts.enumerated() {
            XCTAssertTrue(chart.appendRecognizedChord(
                try ChordSymbolParser.parse(text),
                rawInput: text,
                to: measureID,
                atFraction: Double(index) / Double(chordTexts.count)
            ))
        }
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
        let leading = try XCTUnwrap(measure.repeatMarkerLayouts.first { $0.edge == .leading })
        let trailing = try XCTUnwrap(measure.repeatMarkerLayouts.first { $0.edge == .trailing })
        let firstChord = try XCTUnwrap(measure.chordLayouts.first)
        let lastChord = try XCTUnwrap(measure.chordLayouts.last)

        XCTAssertEqual(measure.chordLayouts.map(\.text), chordTexts)
        XCTAssertGreaterThanOrEqual(firstChord.frame.minX, leading.occupiedFrame.maxX)
        XCTAssertLessThanOrEqual(lastChord.frame.maxX, trailing.occupiedFrame.minX)
        XCTAssertTrue(measure.chordLayouts.allSatisfy { !$0.frame.intersects(leading.occupiedFrame) && !$0.frame.intersects(trailing.occupiedFrame) })
    }

    #if canImport(UIKit)
    func testTerminalRepeatInspectorHitAreaIncludesWingExtensions() throws {
        var chart = Chart.blank(title: "Terminal repeat target", measureCount: 4, layoutStyle: .simpleChordSheet)
        chart.notationReadability = .performance
        chart.repeatWings = true
        let measureIDs = chart.measures.map(\.id)
        let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measureIDs[3] })
        let marker = try XCTUnwrap(measure.repeatMarkerLayouts.first { $0.edge == .trailing })
        let renderedFrame = LeadSheetSimpleChordTerminalBarlineGeometry.renderedRepeatMarkerFrame(
            marker,
            after: measure,
            in: system,
            paperFrame: layout.paperFrame(for: system),
            layoutStyle: chart.layoutStyle
        )
        let targets = RepeatSpanRenderedEditHitTargetProvider().hitTargets(in: RenderedEditContext(
            pageLayout: layout,
            layoutStyle: chart.layoutStyle
        ))

        XCTAssertLessThan(renderedFrame.minY, marker.frame.minY)
        XCTAssertGreaterThan(renderedFrame.maxY, marker.frame.maxY)
        XCTAssertTrue(targets.contains { $0.objectID == .repeatSpan(repeatID) && $0.frame.contains(renderedFrame) })
    }
    #endif

    func testLegacyReadabilityDefaultsPreserveDensityAndLayoutAfterReopen() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            for density in StaffSystemDensity.allCases {
                var chart = try densityProofChart(layoutStyle: layoutStyle)
                chart.staffSystemDensity = density
                let before = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(chart)) as? [String: Any])
                json.removeValue(forKey: "notationReadability")
                json.removeValue(forKey: "repeatWings")
                let reopened = try JSONDecoder().decode(Chart.self, from: JSONSerialization.data(withJSONObject: json))
                let after = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)

                XCTAssertEqual(reopened.staffSystemDensity, density)
                XCTAssertEqual(reopened.notationReadability, .standard)
                XCTAssertFalse(reopened.repeatWings)
                XCTAssertEqual(after.pageBounds, before.pageBounds)
                XCTAssertEqual(after.pages.map(\.frame), before.pages.map(\.frame))
                XCTAssertEqual(after.systems.map(\.frame), before.systems.map(\.frame))
                XCTAssertEqual(after.systems.flatMap(\.measures).map(\.staffFrame), before.systems.flatMap(\.measures).map(\.staffFrame))
                XCTAssertEqual(after.systems.flatMap(\.measures).map(\.chordBandFrame), before.systems.flatMap(\.measures).map(\.chordBandFrame))
                XCTAssertEqual(after.systems.flatMap(\.measures).flatMap(\.chordLayouts), before.systems.flatMap(\.measures).flatMap(\.chordLayouts))
                XCTAssertEqual(after.systems.flatMap(\.measures).flatMap(\.repeatMarkerLayouts), before.systems.flatMap(\.measures).flatMap(\.repeatMarkerLayouts))
            }
        }
    }

    func testPerformanceWingsRespectAllDensitySettingsWithoutShrinkingNotation() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            var chart = try densityProofChart(layoutStyle: layoutStyle)
            chart.notationReadability = .performance
            chart.repeatWings = true
            let standardSpacing = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            let originalMeasure = try XCTUnwrap(standardSpacing.systems.first?.measures.first)
            let originalChord = try XCTUnwrap(originalMeasure.chordLayouts.first)
            for density in StaffSystemDensity.allCases {
                chart.staffSystemDensity = density
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                let measure = try XCTUnwrap(layout.systems.first?.measures.first)
                let chord = try XCTUnwrap(measure.chordLayouts.first)

                XCTAssertEqual(chart.staffSystemDensity, density)
                XCTAssertEqual(measure.staffFrame.height, originalMeasure.staffFrame.height, accuracy: 0.001)
                XCTAssertEqual(chord.renderFontSize, originalChord.renderFontSize)
                XCTAssertEqual(chord.frame.height, originalChord.frame.height, accuracy: 0.001)
                for page in layout.pages {
                    let systems = layout.systems.filter { page.systemIDs.contains($0.id) }
                    for (previous, next) in zip(systems, systems.dropFirst()) {
                        XCTAssertLessThanOrEqual(
                            previous.spacingContentBounds(for: chart).maxY + 0.5,
                            next.spacingContentBounds(for: chart).minY + 0.001,
                            "Readable notation must clear the next system at \(density)."
                        )
                    }
                }
            }
        }
    }

    func testPerformanceNavigationLabelBoundsClearChordsAtEveryDensity() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            for density in StaffSystemDensity.allCases {
                var chart = try densityProofChart(layoutStyle: layoutStyle)
                chart.staffSystemDensity = density
                chart.notationReadability = .performance
                chart.repeatWings = true
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                for system in layout.systems {
                    for marker in system.roadmapMarkerLayouts {
                        let frame = LeadSheetRoadmapMarkerLabelGeometry.labelFrame(for: marker)
                        let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == marker.anchorMeasureID })
                        let contentTop = layoutStyle == .simpleChordSheet ? measure.staffFrame.minY : measure.chordBandFrame.minY
                        XCTAssertLessThanOrEqual(frame.maxY, contentTop + 0.001)
                    }
                }
            }
        }
    }

    private func densityProofChart(layoutStyle: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Readable density", measureCount: 8, layoutStyle: layoutStyle)
        chart.engravingPreset = .balanced
        let measureIDs = chart.measures.map(\.id)
        if layoutStyle != .leadSheet {
            for index in [2, 4, 6] {
                XCTAssertTrue(chart.insertSystemBreak(before: measureIDs[index]))
            }
        }
        for measureID in measureIDs {
            XCTAssertTrue(chart.appendRecognizedChord(
                try ChordSymbolParser.parse("Cmaj7"), rawInput: "Cmaj7", to: measureID, atFraction: 0.1
            ))
        }
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))
        _ = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: measureIDs[2], endMeasureID: measureIDs[3]))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: measureIDs[0]))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.dsAlCoda, anchorMeasureID: measureIDs[5]))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureIDs[6]))
        return chart
    }

    private func firstMeasure(in chart: Chart) throws -> LeadSheetMeasureLayout {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        return try XCTUnwrap(layout.systems.first?.measures.first)
    }
}

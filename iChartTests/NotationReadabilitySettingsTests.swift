import Foundation
import XCTest
@testable import iChart

final class NotationReadabilitySettingsTests: XCTestCase {
    func testReadabilityOptionsSurviveChartRoundTrip() throws {
        var chart = Chart.blank(title: "Readable repeats", measureCount: 2)
        chart.staffSystemDensity = .dense
        chart.notationReadability = .performance
        chart.repeatWings = true
        let measureIDs = chart.measures.map(\.id)
        chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[1])
        chart.addEndingSpan(.ending1, startMeasureID: measureIDs[1], endMeasureID: measureIDs[1])

        let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))

        XCTAssertEqual(reopened.notationReadability, .performance)
        XCTAssertTrue(reopened.repeatWings)
        XCTAssertEqual(reopened.systems, chart.systems)
        XCTAssertEqual(reopened.roadmapObjects, chart.roadmapObjects)
        XCTAssertEqual(reopened.engravingPreset, chart.engravingPreset)
        XCTAssertEqual(reopened.staffSystemDensity, .dense)
    }

    func testLegacyChartWithoutReadabilityKeysKeepsCurrentAppearance() throws {
        var chart = Chart.blank(title: "Legacy appearance")
        chart.staffSystemDensity = .close
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(chart)) as? [String: Any]
        )
        json.removeValue(forKey: "notationReadability")
        json.removeValue(forKey: "repeatWings")

        let reopened = try JSONDecoder().decode(
            Chart.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertEqual(reopened.notationReadability, .standard)
        XCTAssertFalse(reopened.repeatWings)
        XCTAssertEqual(reopened.staffSystemDensity, .close)
        XCTAssertEqual(reopened.engravingPreset, chart.engravingPreset)
        XCTAssertEqual(reopened.systems, chart.systems)
    }

    func testReadabilityEditsPreserveMusicAndGlobalEngraving() {
        var chart = ChartSamples.straightAheadSwing
        chart.updatedAt = Date(timeIntervalSince1970: 100)
        let systems = chart.systems
        let roadmapObjects = chart.roadmapObjects
        let engraving = chart.engravingPreset

        chart.setNotationReadability(.performance)
        chart.setRepeatWings(true)

        XCTAssertEqual(chart.systems, systems)
        XCTAssertEqual(chart.roadmapObjects, roadmapObjects)
        XCTAssertEqual(chart.engravingPreset, engraving)
        XCTAssertGreaterThan(chart.updatedAt, Date(timeIntervalSince1970: 100))

        let lastEdit = chart.updatedAt
        chart.setNotationReadability(.performance)
        chart.setRepeatWings(true)
        XCTAssertEqual(chart.updatedAt, lastEdit)
    }

    func testReadabilityUpgradePreservesEveryInkLayerAndSystemDensity() throws {
        for density in StaffSystemDensity.allCases {
            var chart = ChartSamples.straightAheadSwing
            chart.staffSystemDensity = density
            let pageInk = Data([1, 3, 5, 7])
            let headerInk = Data([2, 4, 6, 8])
            let chordInk = Data([7, 5, 3, 1])
            let rhythmInk = Data([8, 6, 4, 2])
            let coordinateSpace = PersistentInkCoordinateSpace(width: 1180, height: 1500)
            chart.pageHandwrittenNotationData = pageInk
            chart.pageHandwrittenNotationCoordinateSpace = coordinateSpace
            chart.pageHandwrittenHeaderData = headerInk
            chart.pageHandwrittenHeaderCoordinateSpace = coordinateSpace
            chart.pageHandwrittenChordData = chordInk
            chart.pageHandwrittenChordCoordinateSpace = coordinateSpace
            chart.systems[0].measures[0].handwrittenRhythmicNotationData = rhythmInk
            chart.systems[0].measures[0].handwrittenRhythmicNotationCoordinateSpace = coordinateSpace
            let systems = chart.systems
            let roadmap = chart.roadmapObjects

            chart.setNotationReadability(.performance)
            chart.setRepeatWings(true)
            let reopened = try ChartPersistenceCoders.decoder.decode(
                Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart)
            )

            XCTAssertEqual(reopened.staffSystemDensity, density)
            XCTAssertEqual(reopened.systems, systems)
            XCTAssertEqual(reopened.roadmapObjects, roadmap)
            XCTAssertEqual(reopened.pageHandwrittenNotationData, pageInk)
            XCTAssertEqual(reopened.pageHandwrittenHeaderData, headerInk)
            XCTAssertEqual(reopened.pageHandwrittenChordData, chordInk)
            XCTAssertEqual(reopened.pageHandwrittenNotationCoordinateSpace, coordinateSpace)
            XCTAssertEqual(reopened.pageHandwrittenHeaderCoordinateSpace, coordinateSpace)
            XCTAssertEqual(reopened.pageHandwrittenChordCoordinateSpace, coordinateSpace)
            XCTAssertEqual(reopened.notationReadability, .performance)
            XCTAssertTrue(reopened.repeatWings)
        }
    }
}

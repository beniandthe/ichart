import Foundation
import XCTest
@testable import iChart

final class NotationReadabilitySettingsTests: XCTestCase {
    func testReadabilityOptionsSurviveChartRoundTrip() throws {
        var chart = Chart.blank(title: "Readable repeats", measureCount: 2)
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
    }

    func testLegacyChartWithoutReadabilityKeysKeepsCurrentAppearance() throws {
        let chart = Chart.blank(title: "Legacy appearance")
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
}

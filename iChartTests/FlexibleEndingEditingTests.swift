import Foundation
import XCTest
@testable import iChart

final class FlexibleEndingEditingTests: XCTestCase {
    func testLegacyEndingsWithoutStyleKeyKeepTheirLabelsAndClosedEnds() throws {
        var chart = Chart.blank(title: "Legacy endings", measureCount: 2)
        let ids = chart.measures.map(\.id)
        let firstID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1]))
        let secondID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: ChartPersistenceCoders.encoder.encode(chart)) as? [String: Any])
        var objects = try XCTUnwrap(json["roadmapObjects"] as? [[String: Any]])
        for index in objects.indices {
            objects[index].removeValue(forKey: "endingEndStyle")
        }
        json["roadmapObjects"] = objects
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self, from: JSONSerialization.data(withJSONObject: json))
        let first = try XCTUnwrap(reopened.roadmapObject(id: firstID))
        let second = try XCTUnwrap(reopened.roadmapObject(id: secondID))

        XCTAssertEqual(first.type, .ending1)
        XCTAssertEqual(second.type, .ending2)
        XCTAssertNil(first.endingEndStyle)
        XCTAssertNil(second.endingEndStyle)
        XCTAssertEqual(first.resolvedEndingDisplayText, "1.")
        XCTAssertEqual(second.resolvedEndingDisplayText, "2.")
        XCTAssertEqual(first.resolvedEndingEndStyle, .closed)
        XCTAssertEqual(second.resolvedEndingEndStyle, .closed)
        XCTAssertEqual(reopened.systems, chart.systems)
    }

    func testCustomPassListsRangesAndTextRoundTripWithoutNewEndingTypes() throws {
        var chart = Chart.blank(title: "Flexible endings", measureCount: 2)
        let ids = chart.measures.map(\.id)
        let cases: [(input: String, normalized: String, style: EndingEndStyle)] = [
            (" 1,2,3 \n", "1,2,3", .closed),
            ("1–3,5", "1–3,5", .open),
            (" \tOn   cue \n", "On cue", .closed)
        ]
        var endingIDs: [UUID] = []
        for item in cases {
            endingIDs.append(try XCTUnwrap(chart.addEndingSpan(
                .ending1, startMeasureID: ids[0], endMeasureID: ids[1],
                displayText: item.input, endStyle: item.style
            )))
        }
        let reopened = try roundTrip(chart)
        for (id, item) in zip(endingIDs, cases) {
            let ending = try XCTUnwrap(reopened.roadmapObject(id: id))
            XCTAssertEqual(ending.type, .ending1)
            XCTAssertEqual(ending.displayText, item.normalized)
            XCTAssertEqual(ending.resolvedEndingDisplayText, item.normalized)
            XCTAssertEqual(ending.resolvedEndingEndStyle, item.style)
            XCTAssertEqual(ending.rawInput, item.normalized)
        }
        XCTAssertEqual(reopened, chart)
    }

    func testCreationDeduplicatesEffectiveLabelStyleAndBoundsWithoutTimestampChanges() throws {
        var chart = Chart.blank(title: "Ending identity", measureCount: 3)
        let ids = chart.measures.map(\.id)
        let initial = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1]))
        chart.updatedAt = Date(timeIntervalSince1970: 100)
        let checkpoint = chart

        XCTAssertEqual(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1], displayText: " \n1.\t", endStyle: .closed), initial)
        XCTAssertEqual(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1], displayText: "1.", endStyle: .closed), initial)
        XCTAssertEqual(chart, checkpoint)

        let open = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1], endStyle: .open))
        let custom = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1], displayText: "1,2,3."))
        let otherRange = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[1], endMeasureID: ids[2], displayText: "1,2,3."))
        XCTAssertEqual(Set([initial, open, custom, otherRange]).count, 4)
        XCTAssertEqual(chart.roadmapObjects.count, 4)
        XCTAssertGreaterThan(chart.updatedAt, checkpoint.updatedAt)
    }

    func testEditingDetailsMovesTheSameEndingAndPreservesAllNonEndingChartData() throws {
        for density in StaffSystemDensity.allCases {
            var chart = makeChartWithInk(density: density)
            let ids = chart.measures.map(\.id)
            let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1], displayText: "1–3,5.", endStyle: .open))
            let otherID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1]))
            let before = chart
            let otherBefore = try XCTUnwrap(chart.roadmapObject(id: otherID))

            XCTAssertTrue(chart.updateEndingDetails(endingID, startMeasureID: ids[2], endMeasureID: ids[3], displayText: "  6–8,\n On   cue  ", endStyle: .closed))
            let edited = try XCTUnwrap(chart.roadmapObject(id: endingID))
            XCTAssertEqual(edited.id, endingID)
            XCTAssertEqual(edited.type, .ending1)
            XCTAssertEqual(edited.startMeasureID, ids[2])
            XCTAssertEqual(edited.endMeasureID, ids[3])
            XCTAssertEqual(edited.resolvedEndingDisplayText, "6–8, On cue")
            XCTAssertEqual(edited.resolvedEndingEndStyle, .closed)
            XCTAssertEqual(chart.roadmapObject(id: otherID), otherBefore)
            XCTAssertFalse(chart.measure(id: ids[0])!.roadmapObjectIDs.contains(endingID))
            XCTAssertFalse(chart.measure(id: ids[1])!.roadmapObjectIDs.contains(endingID))
            XCTAssertTrue(chart.measure(id: ids[2])!.roadmapObjectIDs.contains(endingID))
            XCTAssertTrue(chart.measure(id: ids[3])!.roadmapObjectIDs.contains(endingID))
            assertNonEndingContentEqual(before, chart)
            XCTAssertEqual(try roundTrip(chart), chart)
        }
    }

    func testBoundaryOnlyEditRetainsCustomLabelStyleAndIdentity() throws {
        var chart = Chart.blank(title: "Move ending", measureCount: 4)
        let ids = chart.measures.map(\.id)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1], displayText: "1–3,5.", endStyle: .open))
        let original = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertTrue(chart.updateEndingSpan(endingID, startMeasureID: ids[2], endMeasureID: ids[3]))
        let moved = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertEqual(moved.id, original.id)
        XCTAssertEqual(moved.displayText, original.displayText)
        XCTAssertEqual(moved.endingEndStyle, original.endingEndStyle)
        XCTAssertEqual(moved.rawInput, original.rawInput)
    }

    func testDetailsRangeOnlyEditDoesNotRewriteLegacyLabelOrStyleStorage() throws {
        var chart = Chart.blank(title: "Move legacy ending", measureCount: 4)
        let ids = chart.measures.map(\.id)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1]))
        let original = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertTrue(chart.updateEndingDetails(endingID, startMeasureID: ids[2], endMeasureID: ids[3], displayText: "2.", endStyle: .closed))
        let moved = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertNil(moved.displayText)
        XCTAssertNil(moved.endingEndStyle)
        XCTAssertEqual(moved.rawInput, original.rawInput)
        XCTAssertEqual(moved.id, original.id)
    }

    func testSemanticNoOpPreservesLegacyStorageAndTimestamp() throws {
        var chart = Chart.blank(title: "No-op ending", measureCount: 2)
        let ids = chart.measures.map(\.id)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1]))
        chart.updatedAt = Date(timeIntervalSince1970: 100)
        let original = chart
        XCTAssertFalse(chart.updateEndingDetails(endingID, startMeasureID: ids[0], endMeasureID: ids[1], displayText: " \n2.\t", endStyle: .closed))
        XCTAssertEqual(chart, original)
        XCTAssertFalse(chart.updateEndingDetails(endingID, startMeasureID: ids[0], endMeasureID: ids[1], displayText: nil, endStyle: .closed))
        XCTAssertEqual(chart, original)

        XCTAssertTrue(chart.updateEndingDetails(endingID, startMeasureID: ids[0], endMeasureID: ids[1], displayText: "On cue", endStyle: .open))
        let custom = chart
        XCTAssertFalse(chart.updateEndingDetails(endingID, startMeasureID: ids[0], endMeasureID: ids[1], displayText: " On   cue\n", endStyle: .open))
        XCTAssertEqual(chart, custom)
    }

    func testBlankLabelRestoresTheLegacyTypeDefault() throws {
        var chart = Chart.blank(title: "Restore ending label", measureCount: 2)
        let ids = chart.measures.map(\.id)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1], displayText: "On cue", endStyle: .open))
        XCTAssertTrue(chart.updateEndingDetails(endingID, startMeasureID: ids[0], endMeasureID: ids[1], displayText: " \n\t", endStyle: .closed))
        let ending = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertNil(ending.displayText)
        XCTAssertEqual(ending.resolvedEndingDisplayText, "2.")
        XCTAssertEqual(ending.resolvedEndingEndStyle, .closed)
    }

    func testInvalidDetailsLeaveTheEntireChartUnchanged() throws {
        var chart = makeChartWithInk(density: .dense)
        let ids = chart.measures.map(\.id)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1]))
        let markerID = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: ids[0]))
        let original = chart
        for (objectID, startID, endID) in [
            (UUID(), ids[0], ids[1]),
            (markerID, ids[0], ids[1]),
            (endingID, UUID(), ids[1]),
            (endingID, ids[0], UUID()),
            (endingID, ids[3], ids[0])
        ] {
            XCTAssertFalse(chart.updateEndingDetails(objectID, startMeasureID: startID, endMeasureID: endID, displayText: "3.", endStyle: .open))
            XCTAssertEqual(chart, original)
        }
    }

    func testDeletingOneEndingLeavesOtherEndingOnSharedBoundsAndInkIntact() throws {
        var chart = makeChartWithInk(density: .close)
        let ids = chart.measures.map(\.id)
        let removeID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1], displayText: "1–3.", endStyle: .closed))
        let keepID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1], displayText: "4.", endStyle: .open))
        let before = chart
        let keptEnding = try XCTUnwrap(chart.roadmapObject(id: keepID))
        XCTAssertTrue(chart.deleteRoadmapObject(removeID))
        XCTAssertNil(chart.roadmapObject(id: removeID))
        XCTAssertEqual(chart.roadmapObject(id: keepID), keptEnding)
        for id in [ids[0], ids[1]] {
            XCTAssertEqual(chart.measure(id: id)!.roadmapObjectIDs, [keepID])
        }
        assertNonEndingContentEqual(before, chart)
    }

    private func roundTrip(_ chart: Chart) throws -> Chart {
        try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
    }

    private func makeChartWithInk(density: StaffSystemDensity) -> Chart {
        var chart = Chart.blank(title: "Saved ending chart", measureCount: 4, layoutStyle: .simpleChordSheet)
        chart.staffSystemDensity = density
        let space = PersistentInkCoordinateSpace(width: 1180, height: 1500)
        chart.pageHandwrittenNotationData = Data([1, 2, 3])
        chart.pageHandwrittenNotationCoordinateSpace = space
        chart.pageHandwrittenHeaderData = Data([4, 5, 6])
        chart.pageHandwrittenHeaderCoordinateSpace = space
        chart.pageHandwrittenChordData = Data([7, 8, 9])
        chart.pageHandwrittenChordCoordinateSpace = space
        chart.systems[0].measures[0].handwrittenRhythmicNotationData = Data([9, 8, 7])
        chart.systems[0].measures[0].handwrittenRhythmicNotationCoordinateSpace = space
        return chart
    }

    private func assertNonEndingContentEqual(_ before: Chart, _ after: Chart, file: StaticString = #filePath, line: UInt = #line) {
        let endingIDs = Set((before.roadmapObjects + after.roadmapObjects).filter { $0.type.isEnding }.map(\.id))
        func withoutEndings(_ chart: Chart) -> Chart {
            var result = chart
            result.roadmapObjects.removeAll { $0.type.isEnding }
            for system in result.systems.indices {
                for measure in result.systems[system].measures.indices {
                    result.systems[system].measures[measure].roadmapObjectIDs.removeAll { endingIDs.contains($0) }
                }
            }
            result.updatedAt = .distantPast
            return result
        }
        XCTAssertEqual(withoutEndings(before), withoutEndings(after), file: file, line: line)
    }
}

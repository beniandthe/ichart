import XCTest
@testable import SmartChart

final class ChartEditingTests: XCTestCase {
    func testAddCueTextUpdatesChartAndMeasure() {
        var chart = Chart.blank(title: "Test Chart")

        chart.addCueText("hits")

        XCTAssertEqual(chart.cueTexts.count, 1)
        XCTAssertEqual(chart.cueTexts.first?.text, "hits")
        XCTAssertEqual(chart.systems[0].measures[0].cueTextIDs, [chart.cueTexts[0].id])
    }

    func testAddCueTextCanAttachToSelectedMeasureWithPositionAndEmphasis() throws {
        var chart = Chart.blank(title: "Cue Text", measureCount: 3)
        let targetMeasureID = chart.measures[1].id

        let cueTextID = try XCTUnwrap(
            chart.addCueText(
                "  tacet  ",
                anchorMeasureID: targetMeasureID,
                position: .above,
                emphasis: .strong
            )
        )

        let cueText = try XCTUnwrap(chart.cueText(id: cueTextID))
        XCTAssertEqual(cueText.text, "tacet")
        XCTAssertEqual(cueText.rawInput, "tacet")
        XCTAssertEqual(cueText.anchorMeasureID, targetMeasureID)
        XCTAssertEqual(cueText.position, .above)
        XCTAssertEqual(cueText.emphasis, .strong)
        XCTAssertEqual(chart.measure(id: targetMeasureID)?.cueTextIDs, [cueTextID])
        XCTAssertTrue(chart.measure(id: chart.measures[0].id)?.cueTextIDs.isEmpty == true)
    }

    func testAddCueTextRejectsEmptyOrMissingMeasure() {
        var chart = Chart.blank(title: "Cue Text", measureCount: 1)

        XCTAssertNil(chart.addCueText("   "))
        XCTAssertNil(chart.addCueText("hits", anchorMeasureID: UUID()))
        XCTAssertTrue(chart.cueTexts.isEmpty)
        XCTAssertTrue(chart.measures.allSatisfy(\.cueTextIDs.isEmpty))
    }

    func testDeleteCueTextsAttachedToMeasureClearsBackReferences() throws {
        var chart = Chart.blank(title: "Cue Text", measureCount: 2)
        let firstMeasureID = chart.measures[0].id
        let secondMeasureID = chart.measures[1].id
        let firstCueID = try XCTUnwrap(chart.addCueText("stop time", anchorMeasureID: firstMeasureID))
        let secondCueID = try XCTUnwrap(chart.addCueText("build", anchorMeasureID: secondMeasureID))

        XCTAssertEqual(chart.deleteCueTexts(attachedTo: firstMeasureID), 1)

        XCTAssertNil(chart.cueText(id: firstCueID))
        XCTAssertNotNil(chart.cueText(id: secondCueID))
        XCTAssertTrue(chart.measure(id: firstMeasureID)?.cueTextIDs.isEmpty == true)
        XCTAssertEqual(chart.measure(id: secondMeasureID)?.cueTextIDs, [secondCueID])
    }

    func testAddRoadmapObjectUpdatesChartAndMeasure() {
        var chart = Chart.blank(title: "Test Chart")

        chart.addRoadmapObject(.dcAlFine)

        XCTAssertEqual(chart.roadmapObjects.count, 1)
        XCTAssertEqual(chart.roadmapObjects.first?.type, .dcAlFine)
        XCTAssertEqual(chart.systems[0].measures[0].roadmapObjectIDs, [chart.roadmapObjects[0].id])
    }

    func testAddPointRoadmapMarkerCreatesMeasureAttachedNavigationMarker() throws {
        var chart = Chart.blank(title: "Roadmap Markers", measureCount: 2)
        let targetMeasureID = chart.measures[1].id

        let markerID = try XCTUnwrap(
            chart.addPointRoadmapMarker(.segno, anchorMeasureID: targetMeasureID)
        )

        let marker = try XCTUnwrap(chart.roadmapObject(id: markerID))
        XCTAssertEqual(marker.type, .segno)
        XCTAssertEqual(marker.startMeasureID, targetMeasureID)
        XCTAssertNil(marker.endMeasureID)
        XCTAssertEqual(marker.placement, .snappedTop)
        XCTAssertEqual(marker.rawInput, RoadmapType.segno.defaultDisplayText)
        XCTAssertEqual(chart.measure(id: targetMeasureID)?.roadmapObjectIDs, [markerID])
        XCTAssertTrue(chart.measure(id: chart.measures[0].id)?.roadmapObjectIDs.isEmpty == true)
    }

    func testPointRoadmapMarkersRejectSpanAndDeferredTypes() {
        var chart = Chart.blank(title: "Roadmap Markers", measureCount: 1)
        let measureID = chart.measures[0].id

        XCTAssertNil(chart.addPointRoadmapMarker(.repeatSpan, anchorMeasureID: measureID))
        XCTAssertNil(chart.addPointRoadmapMarker(.ending1, anchorMeasureID: measureID))
        XCTAssertNil(chart.addPointRoadmapMarker(.vampCount, anchorMeasureID: measureID))
        XCTAssertNil(chart.addPointRoadmapMarker(.fine, anchorMeasureID: UUID()))
        XCTAssertTrue(chart.roadmapObjects.isEmpty)
        XCTAssertTrue(chart.measures.allSatisfy(\.roadmapObjectIDs.isEmpty))
    }

    func testPointRoadmapMarkersAvoidDuplicateSameTypeAtSameMeasure() throws {
        var chart = Chart.blank(title: "Roadmap Markers", measureCount: 1)
        let measureID = chart.measures[0].id

        let firstMarkerID = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: measureID))
        let secondMarkerID = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: measureID))
        let thirdMarkerID = try XCTUnwrap(chart.addPointRoadmapMarker(.noChord, anchorMeasureID: measureID))

        XCTAssertEqual(firstMarkerID, secondMarkerID)
        XCTAssertNotEqual(firstMarkerID, thirdMarkerID)
        XCTAssertEqual(chart.roadmapObjects.count, 2)
        XCTAssertEqual(Set(chart.pointRoadmapMarkerIDs(attachedTo: measureID)), [firstMarkerID, thirdMarkerID])
    }

    func testDeletePointRoadmapMarkersAttachedToMeasureClearsBackReferences() throws {
        var chart = Chart.blank(title: "Roadmap Markers", measureCount: 2)
        let firstMeasureID = chart.measures[0].id
        let secondMeasureID = chart.measures[1].id
        let firstMarkerID = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: firstMeasureID))
        let secondMarkerID = try XCTUnwrap(chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: secondMeasureID))

        XCTAssertEqual(chart.deletePointRoadmapMarkers(attachedTo: firstMeasureID), 1)

        XCTAssertNil(chart.roadmapObject(id: firstMarkerID))
        XCTAssertNotNil(chart.roadmapObject(id: secondMarkerID))
        XCTAssertTrue(chart.measure(id: firstMeasureID)?.roadmapObjectIDs.isEmpty == true)
        XCTAssertEqual(chart.measure(id: secondMeasureID)?.roadmapObjectIDs, [secondMarkerID])
    }

    func testPointRoadmapMarkersAutoLinkToDirectionalTargets() throws {
        var chart = Chart.blank(title: "Roadmap Links", measureCount: 5)
        let measureIDs = chart.measures.map(\.id)
        let codaID = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureIDs[4]))
        let segnoID = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: measureIDs[0]))
        let fineID = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: measureIDs[1]))

        let toCodaID = try XCTUnwrap(chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: measureIDs[2]))
        let dsID = try XCTUnwrap(chart.addPointRoadmapMarker(.dsAlCoda, anchorMeasureID: measureIDs[3]))
        let dcFineID = try XCTUnwrap(chart.addPointRoadmapMarker(.dcAlFine, anchorMeasureID: measureIDs[4]))

        XCTAssertEqual(chart.roadmapObject(id: toCodaID)?.linkedTargetID, codaID)
        XCTAssertEqual(chart.roadmapObject(id: dsID)?.linkedTargetID, segnoID)
        XCTAssertEqual(chart.roadmapObject(id: dcFineID)?.linkedTargetID, fineID)
    }

    func testPointRoadmapMarkersCanLinkAfterTargetAppears() throws {
        var chart = Chart.blank(title: "Roadmap Links", measureCount: 3)
        let measureIDs = chart.measures.map(\.id)
        let toCodaID = try XCTUnwrap(chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: measureIDs[0]))

        XCTAssertNil(chart.roadmapObject(id: toCodaID)?.linkedTargetID)

        let codaID = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureIDs[2]))

        XCTAssertEqual(chart.linkPointRoadmapMarkers(attachedTo: measureIDs[0]), 1)
        XCTAssertEqual(chart.roadmapObject(id: toCodaID)?.linkedTargetID, codaID)
        XCTAssertEqual(chart.linkPointRoadmapMarkers(attachedTo: measureIDs[0]), 0)
    }

    func testPointRoadmapLinksRejectInvalidTargetsAndCanClear() throws {
        var chart = Chart.blank(title: "Roadmap Links", measureCount: 3)
        let measureIDs = chart.measures.map(\.id)
        let segnoID = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: measureIDs[0]))
        let fineID = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: measureIDs[1]))
        let toCodaID = try XCTUnwrap(chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: measureIDs[2]))
        let dcFineID = try XCTUnwrap(chart.addPointRoadmapMarker(.dcAlFine, anchorMeasureID: measureIDs[2]))

        XCTAssertFalse(chart.linkRoadmapObject(toCodaID, to: segnoID))
        XCTAssertEqual(chart.roadmapObject(id: dcFineID)?.linkedTargetID, fineID)
        XCTAssertTrue(chart.clearRoadmapLink(dcFineID))
        XCTAssertTrue(chart.linkRoadmapObject(dcFineID, to: fineID))
        XCTAssertEqual(chart.roadmapObject(id: dcFineID)?.linkedTargetID, fineID)
        XCTAssertEqual(chart.clearRoadmapLinks(attachedTo: measureIDs[2]), 1)
        XCTAssertNil(chart.roadmapObject(id: dcFineID)?.linkedTargetID)
    }

    func testDeletingLinkedTargetClearsSourceLink() throws {
        var chart = Chart.blank(title: "Roadmap Links", measureCount: 3)
        let measureIDs = chart.measures.map(\.id)
        let codaID = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureIDs[2]))
        let toCodaID = try XCTUnwrap(chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: measureIDs[0]))

        XCTAssertEqual(chart.roadmapObject(id: toCodaID)?.linkedTargetID, codaID)
        XCTAssertEqual(chart.deletePointRoadmapMarkers(attachedTo: measureIDs[2]), 1)

        XCTAssertNotNil(chart.roadmapObject(id: toCodaID))
        XCTAssertNil(chart.roadmapObject(id: codaID))
        XCTAssertNil(chart.roadmapObject(id: toCodaID)?.linkedTargetID)
    }

    func testDeletingMeasureWithLinkedTargetClearsSourceLink() throws {
        var chart = Chart.blank(title: "Roadmap Links", measureCount: 3)
        let measureIDs = chart.measures.map(\.id)
        let codaID = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureIDs[2]))
        let toCodaID = try XCTUnwrap(chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: measureIDs[0]))

        XCTAssertEqual(chart.roadmapObject(id: toCodaID)?.linkedTargetID, codaID)
        XCTAssertTrue(chart.deleteMeasure(id: measureIDs[2]))

        XCTAssertNil(chart.roadmapObject(id: codaID))
        XCTAssertNil(chart.roadmapObject(id: toCodaID)?.linkedTargetID)
    }

    func testAddRepeatSpanCreatesSingleObjectAttachedToBoundaryMeasures() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let startMeasureID = chart.measures[1].id
        let middleMeasureID = chart.measures[2].id
        let endMeasureID = chart.measures[3].id

        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        XCTAssertEqual(chart.roadmapObjects.count, 1)
        let repeatSpan = try XCTUnwrap(chart.roadmapObject(id: repeatID))
        XCTAssertEqual(repeatSpan.type, .repeatSpan)
        XCTAssertEqual(repeatSpan.startMeasureID, startMeasureID)
        XCTAssertEqual(repeatSpan.endMeasureID, endMeasureID)
        XCTAssertEqual(repeatSpan.placement, .snappedTop)
        XCTAssertTrue(chart.measure(id: startMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
        XCTAssertTrue(chart.measure(id: endMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
        XCTAssertFalse(chart.measure(id: middleMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
    }

    func testAddRepeatSpanSupportsOneMeasureRepeatWithoutDuplicateBackReference() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureID, endMeasureID: measureID)
        )

        XCTAssertEqual(chart.roadmapObjects.count, 1)
        XCTAssertEqual(chart.measure(id: measureID)?.roadmapObjectIDs, [repeatID])
    }

    func testAddRepeatSpanRejectsMissingOrInvertedMeasures() {
        var chart = Chart.blank(title: "Repeats", measureCount: 3)
        let firstMeasureID = chart.measures[0].id
        let lastMeasureID = chart.measures[2].id

        XCTAssertNil(chart.addRepeatSpan(startMeasureID: lastMeasureID, endMeasureID: firstMeasureID))
        XCTAssertNil(chart.addRepeatSpan(startMeasureID: firstMeasureID, endMeasureID: UUID()))
        XCTAssertTrue(chart.roadmapObjects.isEmpty)
        XCTAssertTrue(chart.measures.allSatisfy(\.roadmapObjectIDs.isEmpty))
    }

    func testAddRepeatSpanReturnsExistingSpanForSameBoundaryMeasures() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 2)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[1].id
        let firstRepeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        let secondRepeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        XCTAssertEqual(secondRepeatID, firstRepeatID)
        XCTAssertEqual(chart.roadmapObjects.count, 1)
        XCTAssertEqual(chart.measure(id: startMeasureID)?.roadmapObjectIDs, [firstRepeatID])
        XCTAssertEqual(chart.measure(id: endMeasureID)?.roadmapObjectIDs, [firstRepeatID])
    }

    func testUpdateRepeatSpanMovesBoundaryBackReferences() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 4)
        let firstMeasureID = chart.measures[0].id
        let secondMeasureID = chart.measures[1].id
        let thirdMeasureID = chart.measures[2].id
        let fourthMeasureID = chart.measures[3].id
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: firstMeasureID, endMeasureID: secondMeasureID)
        )

        XCTAssertTrue(
            chart.updateRepeatSpan(
                repeatID,
                startMeasureID: thirdMeasureID,
                endMeasureID: fourthMeasureID
            )
        )

        let repeatSpan = try XCTUnwrap(chart.roadmapObject(id: repeatID))
        XCTAssertEqual(repeatSpan.startMeasureID, thirdMeasureID)
        XCTAssertEqual(repeatSpan.endMeasureID, fourthMeasureID)
        XCTAssertFalse(chart.measure(id: firstMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
        XCTAssertFalse(chart.measure(id: secondMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
        XCTAssertTrue(chart.measure(id: thirdMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
        XCTAssertTrue(chart.measure(id: fourthMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
    }

    func testDeleteRoadmapObjectClearsMeasureBackReferences() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 2)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[1].id
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        XCTAssertTrue(chart.deleteRoadmapObject(repeatID))

        XCTAssertNil(chart.roadmapObject(id: repeatID))
        XCTAssertTrue(chart.measure(id: startMeasureID)?.roadmapObjectIDs.isEmpty == true)
        XCTAssertTrue(chart.measure(id: endMeasureID)?.roadmapObjectIDs.isEmpty == true)
    }

    func testDeleteRepeatSpansAttachedToBoundaryMeasureClearsBackReferences() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 3)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[2].id
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        XCTAssertEqual(chart.repeatSpanIDs(attachedTo: startMeasureID), [repeatID])
        XCTAssertEqual(chart.deleteRepeatSpans(attachedTo: startMeasureID), 1)

        XCTAssertNil(chart.roadmapObject(id: repeatID))
        XCTAssertTrue(chart.measure(id: startMeasureID)?.roadmapObjectIDs.isEmpty == true)
        XCTAssertTrue(chart.measure(id: endMeasureID)?.roadmapObjectIDs.isEmpty == true)
    }

    func testDeleteRepeatSpansDoesNotRemoveInteriorSpan() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 3)
        let startMeasureID = chart.measures[0].id
        let middleMeasureID = chart.measures[1].id
        let endMeasureID = chart.measures[2].id
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        XCTAssertTrue(chart.repeatSpanIDs(attachedTo: middleMeasureID).isEmpty)
        XCTAssertEqual(chart.deleteRepeatSpans(attachedTo: middleMeasureID), 0)

        XCTAssertNotNil(chart.roadmapObject(id: repeatID))
        XCTAssertTrue(chart.measure(id: startMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
        XCTAssertTrue(chart.measure(id: endMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
    }

    func testDeleteRepeatSpansRemovesAllBoundaryRepeatsAtMeasure() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 3)
        let firstMeasureID = chart.measures[0].id
        let secondMeasureID = chart.measures[1].id
        let thirdMeasureID = chart.measures[2].id
        let firstRepeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: firstMeasureID, endMeasureID: secondMeasureID)
        )
        let secondRepeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: secondMeasureID, endMeasureID: thirdMeasureID)
        )

        XCTAssertEqual(
            Set(chart.repeatSpanIDs(attachedTo: secondMeasureID)),
            [firstRepeatID, secondRepeatID]
        )
        XCTAssertEqual(chart.deleteRepeatSpans(attachedTo: secondMeasureID), 2)

        XCTAssertTrue(chart.roadmapObjects.isEmpty)
        XCTAssertTrue(chart.measures.allSatisfy(\.roadmapObjectIDs.isEmpty))
    }

    func testRepeatSpanAnchorsSurviveInsertionByMeasureID() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 3)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[2].id
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        let insertedID = chart.insertMeasureAtBeginning()

        let repeatSpan = try XCTUnwrap(chart.roadmapObject(id: repeatID))
        XCTAssertEqual(chart.measures.first?.id, insertedID)
        XCTAssertEqual(repeatSpan.startMeasureID, startMeasureID)
        XCTAssertEqual(repeatSpan.endMeasureID, endMeasureID)
        XCTAssertTrue(chart.measure(id: startMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
        XCTAssertTrue(chart.measure(id: endMeasureID)?.roadmapObjectIDs.contains(repeatID) == true)
    }

    func testAddEndingSpanCreatesTypedSpanAttachedToBoundaryMeasures() throws {
        var chart = Chart.blank(title: "Endings", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let startMeasureID = chart.measures[1].id
        let middleMeasureID = chart.measures[2].id
        let endMeasureID = chart.measures[3].id

        let endingID = try XCTUnwrap(
            chart.addEndingSpan(.ending1, startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        let ending = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertEqual(ending.type, .ending1)
        XCTAssertEqual(ending.startMeasureID, startMeasureID)
        XCTAssertEqual(ending.endMeasureID, endMeasureID)
        XCTAssertEqual(ending.placement, .snappedTop)
        XCTAssertEqual(ending.rawInput, RoadmapType.ending1.defaultDisplayText)
        XCTAssertTrue(chart.measure(id: startMeasureID)?.roadmapObjectIDs.contains(endingID) == true)
        XCTAssertTrue(chart.measure(id: endMeasureID)?.roadmapObjectIDs.contains(endingID) == true)
        XCTAssertFalse(chart.measure(id: middleMeasureID)?.roadmapObjectIDs.contains(endingID) == true)
    }

    func testEndingSpansRejectMissingInvertedOrNonEndingTypes() {
        var chart = Chart.blank(title: "Endings", measureCount: 3)
        let firstMeasureID = chart.measures[0].id
        let lastMeasureID = chart.measures[2].id

        XCTAssertNil(chart.addEndingSpan(.ending1, startMeasureID: lastMeasureID, endMeasureID: firstMeasureID))
        XCTAssertNil(chart.addEndingSpan(.ending2, startMeasureID: firstMeasureID, endMeasureID: UUID()))
        XCTAssertNil(chart.addEndingSpan(.repeatSpan, startMeasureID: firstMeasureID, endMeasureID: lastMeasureID))
        XCTAssertTrue(chart.roadmapObjects.isEmpty)
        XCTAssertTrue(chart.measures.allSatisfy(\.roadmapObjectIDs.isEmpty))
    }

    func testFirstAndSecondEndingsCanShareTheSameRange() throws {
        var chart = Chart.blank(title: "Endings", measureCount: 2)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[1].id

        let firstEndingID = try XCTUnwrap(
            chart.addEndingSpan(.ending1, startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )
        let secondEndingID = try XCTUnwrap(
            chart.addEndingSpan(.ending2, startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )
        let duplicateFirstEndingID = try XCTUnwrap(
            chart.addEndingSpan(.ending1, startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        XCTAssertNotEqual(firstEndingID, secondEndingID)
        XCTAssertEqual(duplicateFirstEndingID, firstEndingID)
        XCTAssertEqual(chart.roadmapObjects.count, 2)
        XCTAssertEqual(Set(chart.endingSpanIDs(attachedTo: startMeasureID)), [firstEndingID, secondEndingID])
        XCTAssertEqual(Set(chart.measure(id: endMeasureID)?.roadmapObjectIDs ?? []), [firstEndingID, secondEndingID])
    }

    func testDeleteEndingSpansAttachedToBoundaryMeasureClearsBackReferences() throws {
        var chart = Chart.blank(title: "Endings", measureCount: 3)
        let startMeasureID = chart.measures[0].id
        let middleMeasureID = chart.measures[1].id
        let endMeasureID = chart.measures[2].id
        let endingID = try XCTUnwrap(
            chart.addEndingSpan(.ending2, startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        XCTAssertTrue(chart.endingSpanIDs(attachedTo: middleMeasureID).isEmpty)
        XCTAssertEqual(chart.deleteEndingSpans(attachedTo: middleMeasureID), 0)
        XCTAssertNotNil(chart.roadmapObject(id: endingID))
        XCTAssertEqual(chart.deleteEndingSpans(attachedTo: endMeasureID), 1)

        XCTAssertNil(chart.roadmapObject(id: endingID))
        XCTAssertTrue(chart.measure(id: startMeasureID)?.roadmapObjectIDs.isEmpty == true)
        XCTAssertTrue(chart.measure(id: endMeasureID)?.roadmapObjectIDs.isEmpty == true)
    }

    func testUpdateEndingSpanMovesBoundaryBackReferences() throws {
        var chart = Chart.blank(title: "Endings", measureCount: 4)
        let firstMeasureID = chart.measures[0].id
        let secondMeasureID = chart.measures[1].id
        let thirdMeasureID = chart.measures[2].id
        let fourthMeasureID = chart.measures[3].id
        let endingID = try XCTUnwrap(
            chart.addEndingSpan(.ending1, startMeasureID: firstMeasureID, endMeasureID: secondMeasureID)
        )

        XCTAssertTrue(
            chart.updateEndingSpan(
                endingID,
                startMeasureID: thirdMeasureID,
                endMeasureID: fourthMeasureID
            )
        )

        let ending = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertEqual(ending.startMeasureID, thirdMeasureID)
        XCTAssertEqual(ending.endMeasureID, fourthMeasureID)
        XCTAssertFalse(chart.measure(id: firstMeasureID)?.roadmapObjectIDs.contains(endingID) == true)
        XCTAssertFalse(chart.measure(id: secondMeasureID)?.roadmapObjectIDs.contains(endingID) == true)
        XCTAssertTrue(chart.measure(id: thirdMeasureID)?.roadmapObjectIDs.contains(endingID) == true)
        XCTAssertTrue(chart.measure(id: fourthMeasureID)?.roadmapObjectIDs.contains(endingID) == true)
    }

    func testDeleteRepeatBoundaryMeasureDeletesWholeRepeatSpan() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 3)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[2].id
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        XCTAssertTrue(chart.deleteMeasure(id: startMeasureID))

        XCTAssertNil(chart.roadmapObject(id: repeatID))
        XCTAssertTrue(chart.roadmapObjects.isEmpty)
        XCTAssertEqual(chart.measures.count, 2)
        XCTAssertTrue(chart.measures.allSatisfy(\.roadmapObjectIDs.isEmpty))
    }

    func testDeleteMeasureRemovesAttachedLabelsSymbolsAndObjects() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 3, layoutStyle: .simpleChordSheet)
        let firstMeasureID = chart.measures[0].id
        let thirdMeasureID = chart.measures[2].id
        chart.addSectionLabel(text: "A")
        chart.addCueText("stop time")
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: firstMeasureID, endMeasureID: thirdMeasureID)
        )
        let symbolID = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: firstMeasureID,
                lane: .aboveMeasure,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                drawingData: Data([1, 2, 3])
            )
        )

        XCTAssertTrue(chart.deleteMeasure(id: firstMeasureID))

        XCTAssertNil(chart.roadmapObject(id: repeatID))
        XCTAssertNil(chart.freehandSymbol(id: symbolID))
        XCTAssertTrue(chart.sectionLabels.isEmpty)
        XCTAssertTrue(chart.cueTexts.isEmpty)
        XCTAssertTrue(chart.roadmapObjects.isEmpty)
        XCTAssertTrue(chart.freehandSymbols.isEmpty)
        XCTAssertEqual(chart.measures.count, 2)
    }

    func testDeleteMeasurePreservesOneMeasureMinimum() throws {
        var chart = Chart.blank(title: "Repeats", measureCount: 1)
        let onlyMeasureID = try XCTUnwrap(chart.measures.first?.id)

        XCTAssertFalse(chart.deleteMeasure(id: onlyMeasureID))

        XCTAssertEqual(chart.measures.count, 1)
    }

    func testDocumentKeyTransposesForBbView() {
        let displayedKey = DocumentKey.cMajor.transposed(for: .bb)

        XCTAssertEqual(displayedKey.tonic, .d)
        XCTAssertEqual(displayedKey.accidental, .natural)
        XCTAssertEqual(displayedKey.mode, .major)
    }

    func testDocumentKeyConcertViewPreservesWrittenEnharmonicSpelling() {
        let writtenKey = DocumentKey(tonic: .c, accidental: .flat, mode: .major)
        let displayedKey = writtenKey.transposed(for: .concert)

        XCTAssertEqual(displayedKey.tonic, .c)
        XCTAssertEqual(displayedKey.accidental, .flat)
        XCTAssertEqual(displayedKey.displayText, "Cb major")
    }

    func testCompleteInitialSetupStoresPromptSelections() {
        var chart = Chart.draft(title: "New Chart")

        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .bFlatMajor,
            meter: Meter(numerator: 6, denominator: 8),
            staffStyle: .fiveLine
        )

        XCTAssertEqual(chart.title, "Pocket Groove")
        XCTAssertEqual(chart.documentKey, .bFlatMajor)
        XCTAssertEqual(chart.defaultMeter, Meter(numerator: 6, denominator: 8))
        XCTAssertEqual(chart.staffStyle, .fiveLine)
        XCTAssertEqual(chart.defaultClef, .treble)
        XCTAssertTrue(chart.hasCompletedInitialSetup)
        XCTAssertEqual(chart.systems.count, 1)
        XCTAssertEqual(chart.systems[0].spacingMode, .automatic)
        XCTAssertEqual(chart.systems[0].measures.count, 1)
        XCTAssertEqual(chart.systems[0].measures[0].authoringState, .open)
        XCTAssertEqual(chart.systems[0].measures[0].beatGridPreset, .simple)
    }

    func testCompleteInitialSetupAppliesStartingMeasureCountAndLayoutDefaults() {
        var chart = Chart.draft(title: "Pocket Chart", layoutStyle: .rhythmSectionSheet)

        chart.completeInitialSetup(
            title: "Pocket Chart",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 8,
            clef: .bass
        )

        XCTAssertEqual(chart.defaultClef, .bass)
        XCTAssertEqual(chart.systems.count, 1)
        XCTAssertEqual(chart.systems[0].spacingMode, .relaxed)
        XCTAssertEqual(chart.measures.count, 8)
        XCTAssertTrue(chart.measures.allSatisfy { $0.beatGridPreset == .eighthSubdivision })
        XCTAssertTrue(chart.measures.dropLast().allSatisfy { $0.authoringState == .committed })
        XCTAssertEqual(chart.measures.last?.authoringState, .open)
    }

    func testCompleteInitialSetupNeverCreatesZeroStartingMeasures() {
        var chart = Chart.draft(title: "No Zero Measures", layoutStyle: .simpleChordSheet)

        chart.completeInitialSetup(
            title: "No Zero Measures",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 0
        )

        XCTAssertEqual(chart.systems.count, 1)
        XCTAssertEqual(chart.measures.count, 1)
        XCTAssertEqual(chart.measures[0].authoringState, .open)
    }

    func testDraftStoresSelectedLayoutStyleAndDefaults() {
        let chordSheet = Chart.draft(title: "Quick Roadmap", layoutStyle: .simpleChordSheet)
        let rhythmSheet = Chart.draft(title: "Pocket Chart", layoutStyle: .rhythmSectionSheet)
        let leadSheet = Chart.draft(title: "Lead Sheet", layoutStyle: .leadSheet)

        XCTAssertEqual(chordSheet.layoutStyle, .simpleChordSheet)
        XCTAssertEqual(chordSheet.engravingPreset, .compact)
        XCTAssertEqual(chordSheet.stylePreset, .cleanStudio)
        XCTAssertEqual(rhythmSheet.layoutStyle, .rhythmSectionSheet)
        XCTAssertEqual(rhythmSheet.engravingPreset, .wide)
        XCTAssertEqual(rhythmSheet.stylePreset, .gigSheet)
        XCTAssertEqual(leadSheet.layoutStyle, .leadSheet)
        XCTAssertEqual(leadSheet.engravingPreset, .balanced)
        XCTAssertEqual(leadSheet.stylePreset, .cleanStudio)
    }

    func testLayoutProfilesDefineSeparateChartStructureContracts() {
        let chordProfile = ChartLayoutStyle.simpleChordSheet.profile
        let rhythmProfile = ChartLayoutStyle.rhythmSectionSheet.profile
        let leadProfile = ChartLayoutStyle.leadSheet.profile

        XCTAssertEqual(chordProfile.toolbarEmphasis, .chordRoadmap)
        XCTAssertEqual(chordProfile.primaryToolFocus, [.chordEntry, .sectionRoadmap, .measureLayout, .appearance])
        XCTAssertEqual(chordProfile.setupPolicy.includesKeySelection, false)
        XCTAssertEqual(chordProfile.setupPolicy.includesTimeSignatureSelection, true)
        XCTAssertEqual(chordProfile.setupPolicy.includesStartingMeasureSelection, true)
        XCTAssertEqual(chordProfile.setupPolicy.clefOptions, [])
        XCTAssertEqual(chordProfile.notationLanePolicy, .chordGrid)
        XCTAssertEqual(chordProfile.freehandSymbolLanes, [.aboveMeasure, .belowMeasure])
        XCTAssertTrue(chordProfile.allowsFreehandSymbolInk)
        XCTAssertFalse(chordProfile.allowsRhythmicNotationInk)
        XCTAssertFalse(chordProfile.allowsUserFacingRhythmNoteEditing)
        XCTAssertEqual(chordProfile.measureDefaults.initialMeasureCount, 1)
        XCTAssertEqual(chordProfile.measureDefaults.preferredMeasuresPerSystem, 4)
        XCTAssertEqual(chordProfile.measureDefaults.maximumMeasuresPerSystem, 20)
        XCTAssertEqual(chordProfile.measureDefaults.systemSpacingMode, .compact)
        XCTAssertEqual(chordProfile.measureDefaults.beatGridPreset, .simple)

        XCTAssertEqual(rhythmProfile.toolbarEmphasis, .rhythmAndHits)
        XCTAssertEqual(rhythmProfile.primaryToolFocus, [.chordEntry, .rhythmNotation, .cueText, .measureLayout])
        XCTAssertEqual(rhythmProfile.setupPolicy.includesKeySelection, false)
        XCTAssertEqual(rhythmProfile.setupPolicy.includesTimeSignatureSelection, true)
        XCTAssertEqual(rhythmProfile.setupPolicy.includesStartingMeasureSelection, true)
        XCTAssertEqual(rhythmProfile.setupPolicy.clefOptions, [])
        XCTAssertEqual(rhythmProfile.notationLanePolicy, .rhythmHits)
        XCTAssertEqual(rhythmProfile.freehandSymbolLanes, [.belowMeasure])
        XCTAssertTrue(rhythmProfile.allowsFreehandSymbolInk)
        XCTAssertTrue(rhythmProfile.allowsRhythmicNotationInk)
        XCTAssertFalse(rhythmProfile.allowsUserFacingRhythmNoteEditing)
        XCTAssertEqual(rhythmProfile.measureDefaults.initialMeasureCount, 8)
        XCTAssertEqual(rhythmProfile.measureDefaults.preferredMeasuresPerSystem, 3)
        XCTAssertNil(rhythmProfile.measureDefaults.maximumMeasuresPerSystem)
        XCTAssertEqual(rhythmProfile.measureDefaults.systemSpacingMode, .relaxed)
        XCTAssertEqual(rhythmProfile.measureDefaults.beatGridPreset, .eighthSubdivision)

        XCTAssertEqual(leadProfile.toolbarEmphasis, .leadSheetPage)
        XCTAssertEqual(leadProfile.primaryToolFocus, [.pageSetup, .chordEntry, .rhythmNotation, .appearance])
        XCTAssertEqual(leadProfile.setupPolicy.includesKeySelection, true)
        XCTAssertEqual(leadProfile.setupPolicy.includesTimeSignatureSelection, true)
        XCTAssertEqual(leadProfile.setupPolicy.includesStartingMeasureSelection, true)
        XCTAssertEqual(leadProfile.setupPolicy.clefOptions, [.treble, .bass])
        XCTAssertEqual(leadProfile.notationLanePolicy, .leadSheetStaff)
        XCTAssertEqual(leadProfile.freehandSymbolLanes, [])
        XCTAssertFalse(leadProfile.allowsFreehandSymbolInk)
        XCTAssertTrue(leadProfile.allowsRhythmicNotationInk)
        XCTAssertTrue(leadProfile.allowsUserFacingRhythmNoteEditing)
        XCTAssertEqual(leadProfile.measureDefaults.initialMeasureCount, 4)
        XCTAssertEqual(leadProfile.measureDefaults.preferredMeasuresPerSystem, 4)
        XCTAssertNil(leadProfile.measureDefaults.maximumMeasuresPerSystem)
        XCTAssertEqual(leadProfile.measureDefaults.systemSpacingMode, .automatic)
        XCTAssertEqual(leadProfile.measureDefaults.beatGridPreset, .simple)
    }

    func testLayoutProfilesOwnDefaultsWithoutBranchingRendererYet() {
        let profiles = ChartLayoutStyle.allCases.map(\.profile)
        let rendererRoutes = Set(profiles.map(\.rendererRoute))

        XCTAssertEqual(rendererRoutes, [.currentLeadSheetRenderer])
        XCTAssertEqual(ChartLayoutStyle.simpleChordSheet.defaultStylePreset, ChartLayoutStyle.simpleChordSheet.profile.defaultStylePreset)
        XCTAssertEqual(ChartLayoutStyle.simpleChordSheet.defaultEngravingPreset, ChartLayoutStyle.simpleChordSheet.profile.defaultEngravingPreset)
        XCTAssertEqual(ChartLayoutStyle.rhythmSectionSheet.defaultStylePreset, ChartLayoutStyle.rhythmSectionSheet.profile.defaultStylePreset)
        XCTAssertEqual(ChartLayoutStyle.rhythmSectionSheet.defaultEngravingPreset, ChartLayoutStyle.rhythmSectionSheet.profile.defaultEngravingPreset)
        XCTAssertEqual(ChartLayoutStyle.leadSheet.defaultStylePreset, ChartLayoutStyle.leadSheet.profile.defaultStylePreset)
        XCTAssertEqual(ChartLayoutStyle.leadSheet.defaultEngravingPreset, ChartLayoutStyle.leadSheet.profile.defaultEngravingPreset)
    }

    func testLayoutMeasureDefaultsAndBlankChartsNeverAllowZeroMeasures() {
        let sanitizedDefaults = ChartLayoutMeasureDefaults(
            initialMeasureCount: 0,
            preferredMeasuresPerSystem: 0,
            maximumMeasuresPerSystem: 0,
            systemSpacingMode: .compact,
            beatGridPreset: .simple
        )
        let blankChart = Chart.blank(title: "No Zero Measures", measureCount: 0)
        let rhythmChart = Chart.blank(
            title: "Rhythm Defaults",
            measureCount: 2,
            layoutStyle: .rhythmSectionSheet
        )

        XCTAssertEqual(sanitizedDefaults.initialMeasureCount, 1)
        XCTAssertEqual(sanitizedDefaults.preferredMeasuresPerSystem, 1)
        XCTAssertEqual(sanitizedDefaults.maximumMeasuresPerSystem, 1)
        XCTAssertTrue(ChartLayoutStyle.allCases.allSatisfy { $0.profile.measureDefaults.initialMeasureCount >= 1 })
        XCTAssertEqual(blankChart.measures.count, 1)
        XCTAssertEqual(rhythmChart.systems[0].spacingMode, .relaxed)
        XCTAssertTrue(rhythmChart.measures.allSatisfy { $0.beatGridPreset == .eighthSubdivision })
    }

    func testSimpleChordSheetManualSystemBreakSplitsAndRemovesRows() throws {
        var chart = Chart.blank(title: "Manual Rows", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.canInsertSimpleSystemBreak(before: measureIDs[4]))
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))

        XCTAssertEqual(chart.systems.count, 2)
        XCTAssertEqual(chart.systems.map { $0.measures.map(\.id) }, [
            Array(measureIDs[0..<4]),
            Array(measureIDs[4..<6])
        ])
        XCTAssertEqual(chart.systems[0].lineBreakRule, .automatic)
        XCTAssertEqual(chart.systems[1].lineBreakRule, .forced)
        XCTAssertFalse(chart.canInsertSimpleSystemBreak(before: measureIDs[4]))
        XCTAssertTrue(chart.canRemoveSimpleSystemBreak(before: measureIDs[4]))

        XCTAssertTrue(chart.removeSimpleSystemBreak(before: measureIDs[4]))

        XCTAssertEqual(chart.systems.count, 1)
        XCTAssertEqual(chart.measures.map(\.id), measureIDs)
        XCTAssertEqual(chart.systems[0].lineBreakRule, .automatic)
    }

    func testSimpleChordSheetInsertionsPreserveManualBreakByMeasureIdentity() throws {
        var chart = Chart.blank(title: "Manual Rows", measureCount: 4, layoutStyle: .simpleChordSheet)
        let originalMeasureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.insertSimpleSystemBreak(before: originalMeasureIDs[2]))
        let insertedID = chart.insertMeasureAtBeginning()

        XCTAssertEqual(chart.systems.count, 2)
        XCTAssertEqual(chart.systems[0].measures.map(\.id), [
            insertedID,
            originalMeasureIDs[0],
            originalMeasureIDs[1]
        ])
        XCTAssertEqual(chart.systems[1].measures.map(\.id), Array(originalMeasureIDs[2..<4]))
        XCTAssertEqual(chart.systems[1].lineBreakRule, .forced)
        XCTAssertEqual(chart.measures.map(\.index), Array(1...5))
    }

    func testSimpleChordSheetMeasureCapStartsAutomaticNewSystem() throws {
        var chart = Chart.blank(title: "Manual Rows", measureCount: 20, layoutStyle: .simpleChordSheet)

        let appendedID = chart.appendMeasure()

        XCTAssertEqual(chart.systems.count, 2)
        XCTAssertEqual(chart.systems[0].measures.count, 20)
        XCTAssertEqual(chart.systems[1].measures.count, 1)
        XCTAssertEqual(chart.systems[1].measures.first?.id, appendedID)
        XCTAssertEqual(chart.systems[1].lineBreakRule, .automatic)
        XCTAssertEqual(chart.measures.map(\.index), Array(1...21))
    }

    func testNonSimpleChartsRejectSimpleSystemBreakControls() throws {
        var chart = Chart.blank(title: "Rhythm Rows", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let secondMeasureID = try XCTUnwrap(chart.measures.dropFirst().first?.id)

        XCTAssertFalse(chart.canInsertSimpleSystemBreak(before: secondMeasureID))
        XCTAssertFalse(chart.insertSimpleSystemBreak(before: secondMeasureID))
        XCTAssertFalse(chart.removeSimpleSystemBreak(before: secondMeasureID))
        XCTAssertEqual(chart.systems.count, 1)
    }

    func testAppearanceSettersUpdateDocumentAppearanceChoices() {
        var chart = Chart.blank(title: "Test Chart")

        chart.setStylePreset(.gigSheet)
        chart.setNotationFont(.finaleJazz)
        chart.setEngravingPreset(.wide)

        XCTAssertEqual(chart.stylePreset, .gigSheet)
        XCTAssertEqual(chart.notationFont, .finaleJazz)
        XCTAssertEqual(chart.engravingPreset, .wide)
    }

    func testChartDecodingDefaultsMissingAppearanceFieldsForOlderSnapshots() throws {
        let chart = Chart.blank(title: "Older Snapshot")
        let encodedData = try JSONEncoder().encode(chart)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        object.removeValue(forKey: "layoutStyle")
        object.removeValue(forKey: "notationFont")
        object.removeValue(forKey: "engravingPreset")
        object.removeValue(forKey: "defaultClef")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decodedChart = try JSONDecoder().decode(Chart.self, from: legacyData)

        XCTAssertEqual(decodedChart.layoutStyle, .leadSheet)
        XCTAssertEqual(decodedChart.notationFont, .petaluma)
        XCTAssertEqual(decodedChart.engravingPreset, .balanced)
        XCTAssertEqual(decodedChart.defaultClef, .treble)
    }

    func testChordEventDecodingDefaultsMissingSourceCandidateSignature() throws {
        var chart = Chart.blank(title: "Older Chord Snapshot", key: .cMajor, measureCount: 1)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = try XCTUnwrap(ChordRecognitionCompendium.match("C")?.symbol)
        _ = chart.appendRecognizedChordEvent(
            symbol,
            rawInput: "C",
            to: measureID,
            atFraction: 0.05,
            sourceInkData: Data([1, 2, 3])
        )
        let encodedData = try JSONEncoder().encode(chart)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        var systems = try XCTUnwrap(object["systems"] as? [[String: Any]])
        var firstSystem = try XCTUnwrap(systems.first)
        var measures = try XCTUnwrap(firstSystem["measures"] as? [[String: Any]])
        var firstMeasure = try XCTUnwrap(measures.first)
        var chordEvents = try XCTUnwrap(firstMeasure["chordEvents"] as? [[String: Any]])
        var firstChordEvent = try XCTUnwrap(chordEvents.first)
        firstChordEvent.removeValue(forKey: "sourceCandidateSignature")
        chordEvents[0] = firstChordEvent
        firstMeasure["chordEvents"] = chordEvents
        measures[0] = firstMeasure
        firstSystem["measures"] = measures
        systems[0] = firstSystem
        object["systems"] = systems
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decodedChart = try JSONDecoder().decode(Chart.self, from: legacyData)

        XCTAssertEqual(decodedChart.measures.first?.chordEvents.first?.sourceCandidateSignature, [])
    }

    func testNotationGlyphCatalogProvidesSemanticSmuflSymbols() {
        XCTAssertEqual(NotationGlyphCatalog.trebleClef, "\u{E050}")
        XCTAssertEqual(NotationGlyphCatalog.bassClef, "\u{E062}")
        XCTAssertEqual(NotationGlyphCatalog.noteheadWhole, "\u{E0A2}")
        XCTAssertEqual(NotationGlyphCatalog.noteheadHalf, "\u{E0A3}")
        XCTAssertEqual(NotationGlyphCatalog.noteheadBlack, "\u{E0A4}")
        XCTAssertEqual(NotationGlyphCatalog.slashNotehead, "\u{E100}")
        XCTAssertEqual(NotationGlyphCatalog.slashWholeNotehead, "\u{E102}")
        XCTAssertEqual(NotationGlyphCatalog.slashHalfNotehead, "\u{E103}")
        XCTAssertEqual(NotationGlyphCatalog.augmentationDot, "\u{E1E7}")
        XCTAssertEqual(NotationGlyphCatalog.flag8thUp, "\u{E240}")
        XCTAssertEqual(NotationGlyphCatalog.flag8thDown, "\u{E241}")
        XCTAssertEqual(NotationGlyphCatalog.wholeRest, "\u{E4E3}")
        XCTAssertEqual(NotationGlyphCatalog.halfRest, "\u{E4E4}")
        XCTAssertEqual(NotationGlyphCatalog.quarterRest, "\u{E4E5}")
        XCTAssertEqual(NotationGlyphCatalog.eighthRest, "\u{E4E6}")
        XCTAssertEqual(NotationGlyphCatalog.accidentalFlat, "\u{E260}")
        XCTAssertEqual(NotationGlyphCatalog.accidentalSharp, "\u{E262}")
        XCTAssertEqual(NotationGlyphCatalog.timeSignatureDigit(4), "\u{E084}")
        XCTAssertNil(NotationGlyphCatalog.timeSignatureDigit(12))
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .trebleClef), NotationGlyphCatalog.trebleClef)
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .bassClef), NotationGlyphCatalog.bassClef)
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .accidentalFlat), NotationGlyphCatalog.accidentalFlat)
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .accidentalSharp), NotationGlyphCatalog.accidentalSharp)
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .noteheadBlack), NotationGlyphCatalog.noteheadBlack)
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .timeSignatureDigit(4)), "\u{E084}")
        XCTAssertNil(NotationGlyphCatalog.glyph(for: .timeSignatureDigit(12)))
        XCTAssertEqual(NotationGlyphCatalog.pointSize(for: .trebleClef, staffSpace: 10.5), 42, accuracy: 0.001)
    }

    func testNotationFontPresetsExposeOfficialSmuflEngravingDefaults() {
        XCTAssertEqual(NotationFontPreset.bravura.smuflEngravingDefaults.staffLineThickness, 0.13)
        XCTAssertEqual(NotationFontPreset.finaleJazz.smuflEngravingDefaults.stemThickness, 0.15)
        XCTAssertEqual(NotationFontPreset.leland.smuflEngravingDefaults.thickBarlineThickness, 0.55)
        XCTAssertEqual(NotationFontPreset.finaleEngraver.smuflEngravingDefaults.tieMidpointThickness, 0.25)
    }

    func testSetPageHandwrittenNotationDrawingStoresAndClearsRawInk() {
        var chart = Chart.draft(title: "New Chart")
        let drawingData = Data([4, 3, 2, 1])

        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(drawingData))
        XCTAssertEqual(chart.pageHandwrittenNotationData, drawingData)
        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(nil))
        XCTAssertNil(chart.pageHandwrittenNotationData)
    }

    func testSetPageHandwrittenChordDrawingStoresSeparatelyFromFreeHandInk() {
        var chart = Chart.draft(title: "New Chart")
        let freeHandData = Data([4, 3, 2, 1])
        let chordData = Data([8, 7, 6, 5])

        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(freeHandData))
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(chordData))
        XCTAssertEqual(chart.pageHandwrittenNotationData, freeHandData)
        XCTAssertEqual(chart.pageHandwrittenChordData, chordData)
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(nil))
        XCTAssertNil(chart.pageHandwrittenChordData)
        XCTAssertEqual(chart.pageHandwrittenNotationData, freeHandData)
    }

    func testSetMeasureHandwrittenRhythmicNotationDrawingStoresAndClearsRawInk() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let drawingData = Data([9, 8, 7, 6])

        XCTAssertTrue(chart.setMeasureHandwrittenRhythmicNotationDrawing(drawingData, for: measureID))
        XCTAssertEqual(chart.measure(id: measureID)?.handwrittenRhythmicNotationData, drawingData)
        XCTAssertTrue(chart.setMeasureHandwrittenRhythmicNotationDrawing(nil, for: measureID))
        XCTAssertNil(chart.measure(id: measureID)?.handwrittenRhythmicNotationData)
    }

    func testAddFreehandSymbolStoresSimpleAboveBelowMeasureInkObjects() throws {
        var chart = Chart.blank(title: "Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let drawingData = Data([9, 7, 5, 3])
        let frame = FreehandSymbolNormalizedFrame(x: 0.1, y: 0.2, width: 0.35, height: 0.4)

        let aboveID = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureID,
                lane: .aboveMeasure,
                normalizedFrame: frame,
                drawingData: drawingData
            )
        )
        let belowID = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureID,
                lane: .belowMeasure,
                normalizedFrame: frame,
                drawingData: drawingData
            )
        )

        let aboveSymbol = try XCTUnwrap(chart.freehandSymbol(id: aboveID))
        let belowSymbol = try XCTUnwrap(chart.freehandSymbol(id: belowID))
        XCTAssertEqual(aboveSymbol.anchorMeasureID, measureID)
        XCTAssertEqual(aboveSymbol.lane, .aboveMeasure)
        XCTAssertEqual(aboveSymbol.drawingData, drawingData)
        XCTAssertEqual(aboveSymbol.zIndex, 0)
        XCTAssertEqual(belowSymbol.lane, .belowMeasure)
        XCTAssertEqual(belowSymbol.zIndex, 1)
    }

    func testFreehandSymbolsFollowLayoutProfileLanesAndRejectEmptyDrawingData() throws {
        var simpleChart = Chart.blank(title: "Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        var rhythmChart = Chart.blank(title: "Pocket", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        var leadChart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let simpleMeasureID = try XCTUnwrap(simpleChart.measures.first?.id)
        let rhythmMeasureID = try XCTUnwrap(rhythmChart.measures.first?.id)
        let leadMeasureID = try XCTUnwrap(leadChart.measures.first?.id)
        let frame = FreehandSymbolNormalizedFrame(x: 0, y: 0, width: 0.5, height: 0.5)

        XCTAssertNil(
            simpleChart.addFreehandSymbol(
                anchorMeasureID: simpleMeasureID,
                lane: .aboveMeasure,
                normalizedFrame: frame,
                drawingData: Data()
            )
        )
        XCTAssertNil(
            rhythmChart.addFreehandSymbol(
                anchorMeasureID: rhythmMeasureID,
                lane: .aboveMeasure,
                normalizedFrame: frame,
                drawingData: Data([1])
            )
        )
        let rhythmSymbolID = try XCTUnwrap(
            rhythmChart.addFreehandSymbol(
                anchorMeasureID: rhythmMeasureID,
                lane: .belowMeasure,
                normalizedFrame: frame,
                drawingData: Data([1])
            )
        )
        XCTAssertNil(
            leadChart.addFreehandSymbol(
                anchorMeasureID: leadMeasureID,
                lane: .aboveMeasure,
                normalizedFrame: frame,
                drawingData: Data([1])
            )
        )
        XCTAssertTrue(simpleChart.freehandSymbols.isEmpty)
        XCTAssertEqual(rhythmChart.freehandSymbols.map(\.lane), [.belowMeasure])
        XCTAssertTrue(
            rhythmChart.moveFreehandSymbol(
                rhythmSymbolID,
                to: FreehandSymbolNormalizedFrame(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
            )
        )
        XCTAssertTrue(rhythmChart.deleteFreehandSymbol(rhythmSymbolID))
        XCTAssertTrue(rhythmChart.freehandSymbols.isEmpty)
        XCTAssertTrue(leadChart.freehandSymbols.isEmpty)
    }

    func testMoveAndDeleteFreehandSymbolUpdatesSimpleInkObject() throws {
        var chart = Chart.blank(title: "Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let originalFrame = FreehandSymbolNormalizedFrame(x: 0.1, y: 0.2, width: 0.35, height: 0.4)
        let movedFrame = FreehandSymbolNormalizedFrame(x: 0.45, y: 0.25, width: 0.30, height: 0.35)
        let symbolID = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureID,
                lane: .aboveMeasure,
                normalizedFrame: originalFrame,
                drawingData: Data([4, 5, 6])
            )
        )

        XCTAssertTrue(chart.moveFreehandSymbol(symbolID, to: movedFrame))
        XCTAssertEqual(chart.freehandSymbol(id: symbolID)?.normalizedFrame, movedFrame)
        XCTAssertTrue(chart.deleteFreehandSymbol(symbolID))
        XCTAssertNil(chart.freehandSymbol(id: symbolID))
        XCTAssertTrue(chart.freehandSymbols.isEmpty)
    }

    func testInsertMeasureAtBeginningReindexesWithoutDroppingExistingMeasures() throws {
        var chart = Chart.blank(title: "Pocket", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let originalFirstID = try XCTUnwrap(chart.measures.first?.id)
        let originalSecondID = try XCTUnwrap(chart.measures.last?.id)
        chart.addSectionLabel(text: "A")

        let insertedID = chart.insertMeasureAtBeginning()

        XCTAssertEqual(chart.measures.count, 3)
        XCTAssertEqual(chart.measures.map(\.index), [1, 2, 3])
        XCTAssertEqual(chart.measures.first?.id, insertedID)
        XCTAssertEqual(chart.measures[1].id, originalFirstID)
        XCTAssertEqual(chart.measures[2].id, originalSecondID)
        XCTAssertEqual(chart.measures.first?.beatGridPreset, .eighthSubdivision)
        XCTAssertEqual(chart.measure(id: originalFirstID)?.index, 2)
        XCTAssertEqual(chart.sectionLabels.first?.anchorMeasureID, originalFirstID)
    }

    func testSetMeasureRhythmMapStoresAndClearsQuantizedRhythm() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.quarter, .quarter, .quarter, .quarter],
                drawingData: Data([1, 2, 3]),
                for: measureID
            )
        )
        XCTAssertEqual(
            chart.measure(id: measureID)?.rhythmMap?.values,
            [.quarter, .quarter, .quarter, .quarter]
        )

        XCTAssertTrue(chart.clearMeasureRhythmicNotation(for: measureID, clearRhythmMap: true))
        XCTAssertNil(chart.measure(id: measureID)?.rhythmMap)
    }

    func testSetLeadSheetPitchedNotesStoresExactRhythmAndClampedStaffPositions() throws {
        var chart = Chart.draft(title: "Lead", layoutStyle: .leadSheet)
        chart.completeInitialSetup(
            title: "Lead",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        XCTAssertTrue(
            chart.setLeadSheetPitchedNotes(
                [
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: -2)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 4)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 8)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 12))
                ],
                for: measureID
            )
        )

        let measure = try XCTUnwrap(chart.measure(id: measureID))
        XCTAssertEqual(measure.rhythmMap?.values, [.quarter, .quarter, .quarter, .quarter])
        XCTAssertEqual(measure.pitchedNoteEvents.map(\.rhythmSlotIndex), [0, 1, 2, 3])
        XCTAssertEqual(measure.pitchedNoteEvents.map(\.staffPosition.staffStep), [0, 4, 8, 8])
        XCTAssertNil(measure.handwrittenRhythmicNotationData)

        XCTAssertTrue(chart.clearMeasureRhythmicNotation(for: measureID, clearRhythmMap: true))
        XCTAssertTrue(chart.measure(id: measureID)?.pitchedNoteEvents.isEmpty == true)
    }

    func testSetLeadSheetPitchedNotesRejectsNonLeadSheetAndUnsupportedDurations() throws {
        var rhythmChart = Chart.blank(title: "Pocket", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let rhythmMeasureID = try XCTUnwrap(rhythmChart.measures.first?.id)
        XCTAssertFalse(
            rhythmChart.setLeadSheetPitchedNotes(
                [LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 4))],
                for: rhythmMeasureID
            )
        )

        var leadChart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let leadMeasureID = try XCTUnwrap(leadChart.measures.first?.id)
        XCTAssertFalse(
            leadChart.setLeadSheetPitchedNotes(
                [
                    LeadSheetPitchedNoteInput(rhythmValue: .slash, staffPosition: LeadSheetStaffPosition(staffStep: 4)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 4)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 4)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 4))
                ],
                for: leadMeasureID
            )
        )
        XCTAssertFalse(
            leadChart.setLeadSheetPitchedNotes(
                [
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 4)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 4))
                ],
                for: leadMeasureID
            )
        )
        XCTAssertTrue(leadChart.measure(id: leadMeasureID)?.pitchedNoteEvents.isEmpty == true)
    }

    func testSetLeadSheetRhythmMapAllowsMixedNotesAndRestsWithPitchedSlotsOnly() throws {
        var chart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        XCTAssertTrue(
            chart.setLeadSheetRhythmMap(
                [.quarter, .quarterRest, .quarter, .quarterRest],
                pitchedNotes: [
                    LeadSheetPitchedNoteSlotInput(
                        rhythmSlotIndex: 0,
                        staffPosition: LeadSheetStaffPosition(staffStep: 1)
                    ),
                    LeadSheetPitchedNoteSlotInput(
                        rhythmSlotIndex: 2,
                        staffPosition: LeadSheetStaffPosition(staffStep: 7)
                    )
                ],
                for: measureID
            )
        )

        let measure = try XCTUnwrap(chart.measure(id: measureID))
        XCTAssertEqual(measure.rhythmMap?.values, [.quarter, .quarterRest, .quarter, .quarterRest])
        XCTAssertEqual(measure.pitchedNoteEvents.map(\.rhythmSlotIndex), [0, 2])
        XCTAssertEqual(measure.pitchedNoteEvents.map(\.staffPosition.staffStep), [1, 7])

        XCTAssertFalse(
            chart.setLeadSheetRhythmMap(
                [.quarter, .quarterRest, .quarter, .quarterRest],
                pitchedNotes: [
                    LeadSheetPitchedNoteSlotInput(
                        rhythmSlotIndex: 1,
                        staffPosition: LeadSheetStaffPosition(staffStep: 4)
                    )
                ],
                for: measureID
            ),
            "Rest slots cannot carry pitched-note events"
        )
        XCTAssertFalse(
            chart.setLeadSheetRhythmMap(
                [.quarter, .quarterRest, .quarter, .quarterRest],
                pitchedNotes: [
                    LeadSheetPitchedNoteSlotInput(
                        rhythmSlotIndex: 0,
                        staffPosition: LeadSheetStaffPosition(staffStep: 4)
                    )
                ],
                for: measureID
            ),
            "Every note-capable Lead Sheet rhythm slot needs a pitched-note event"
        )
    }

    func testAppendRecognizedChordAddsCleanChordSymbolAtRequestedFraction() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = try XCTUnwrap(BasicMajorChordCompendium.match("Db")?.symbol)
        let sourceInkData = Data([1, 9, 7, 5])

        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                symbol,
                rawInput: "D flat",
                to: measureID,
                atFraction: 0.55,
                sourceInkData: sourceInkData,
                sourceCandidateSignature: ["Db", "D"]
            )
        )

        let chord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(chord.id, chordID)
        XCTAssertEqual(chord.symbol.displayText, "Db")
        XCTAssertEqual(chord.rawInput, "D flat")
        XCTAssertEqual(chord.sourceInkData, sourceInkData)
        XCTAssertEqual(chord.sourceCandidateSignature, ["Db", "D"])
        XCTAssertEqual(chord.startPosition.displayText, "3")
    }

    func testReplaceChordEventUpdatesSymbolWithoutMovingPlacementOrInkSource() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let sourceInkData = Data([9, 8, 7])
        let initialSymbol = try XCTUnwrap(ChordRecognitionCompendium.match("Bb/A")?.symbol)
        let correctedSymbol = try XCTUnwrap(ChordRecognitionCompendium.match("Db/A")?.symbol)
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                initialSymbol,
                rawInput: "Bb/A",
                to: measureID,
                atFraction: 0.55,
                sourceInkData: sourceInkData,
                sourceCandidateSignature: ["Bb/A", "Db/A"]
            )
        )

        XCTAssertTrue(chart.replaceChordEvent(chordID, with: correctedSymbol, rawInput: "Db/A"))

        let chord = try XCTUnwrap(chart.chordEvent(id: chordID))
        XCTAssertEqual(chord.symbol.displayText, "Db/A")
        XCTAssertEqual(chord.rawInput, "Db/A")
        XCTAssertEqual(chord.sourceInkData, sourceInkData)
        XCTAssertEqual(chord.sourceCandidateSignature, ["Bb/A", "Db/A"])
        XCTAssertEqual(chord.startPosition.displayText, "3")
        XCTAssertEqual(chart.measureContainingChordEvent(id: chordID)?.id, measureID)
    }

    func testChordWritingLoopOnDisposableTestChartCommitsStructuredChords() throws {
        var chart = Chart.blank(title: "Chord Writing Test Chart", measureCount: 8)
        let chordLoopCases = [
            (written: "C", expected: "C"),
            (written: "Bb7", expected: "Bb7"),
            (written: "F#-11", expected: "F#-11"),
            (written: "Db7b9", expected: "Db7(b9)"),
            (written: "G/B", expected: "G/B")
        ]

        for (index, chordCase) in chordLoopCases.enumerated() {
            let measureID = chart.measures[index].id
            let inkData = Data("ink-\(chordCase.written)".utf8)
            let match = try XCTUnwrap(ChordRecognitionCompendium.match(chordCase.written))

            XCTAssertTrue(chart.setPageHandwrittenChordDrawing(inkData))
            let chordID = try XCTUnwrap(
                chart.commitRecognizedChordInk(
                    match.symbol,
                    rawInput: chordCase.written,
                    to: measureID,
                    atFraction: 0.05,
                    sourceInkData: inkData,
                    sourceCandidateSignature: [chordCase.expected]
                ),
                chordCase.written
            )

            let chord = try XCTUnwrap(chart.chordEvent(id: chordID))
            XCTAssertEqual(chord.symbol.displayText, chordCase.expected)
            XCTAssertEqual(chord.rawInput, chordCase.written)
            XCTAssertEqual(chord.sourceInkData, inkData)
            XCTAssertEqual(chord.sourceCandidateSignature, [chordCase.expected])
            XCTAssertEqual(chord.startPosition.displayText, "1")
            XCTAssertNil(chart.pageHandwrittenChordData)
        }
    }

    func testRecognizedChordInkCommitKeepsInkWhenMeasureIsUnavailable() throws {
        var chart = Chart.blank(title: "Chord Writing Test Chart", measureCount: 1)
        let inkData = Data("ink-C".utf8)
        let match = try XCTUnwrap(ChordRecognitionCompendium.match("C"))

        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(inkData))
        XCTAssertNil(
            chart.commitRecognizedChordInk(
                match.symbol,
                rawInput: "C",
                to: UUID(),
                atFraction: 0.05,
                sourceInkData: inkData
            )
        )

        XCTAssertEqual(chart.pageHandwrittenChordData, inkData)
        XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
    }

    func testDeleteChordEventRemovesRenderedChordFromMeasure() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)
        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "C", to: measureID, atFraction: 0.03))
        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)

        XCTAssertTrue(chart.deleteChordEvent(chordID))

        XCTAssertTrue(chart.measure(id: measureID)?.chordEvents.isEmpty == true)
        XCTAssertFalse(chart.deleteChordEvent(chordID))
    }

    func testMoveChordEventSnapsExistingChordToRequestedBeat() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = ChordSymbol(root: .f, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)
        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "F", to: measureID, atFraction: 0.03))
        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)

        XCTAssertTrue(chart.moveChordEvent(chordID, to: measureID, atFraction: 0.68))

        let movedChord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(movedChord.id, chordID)
        XCTAssertEqual(movedChord.startPosition.displayText, "4")
        XCTAssertNil(movedChord.mappedRhythmSlotIndex)
    }

    func testMoveChordEventSnapsExistingChordToRhythmSlot() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
        let symbol = ChordSymbol(root: .g, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)
        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "G", to: measureID, atFraction: 0.03))
        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)

        XCTAssertTrue(chart.moveChordEvent(chordID, to: measureID, atFraction: 0.62))

        let movedChord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(movedChord.startPosition.displayText, "3")
        XCTAssertEqual(movedChord.mappedRhythmSlotIndex, 2)
        XCTAssertEqual(movedChord.duration, .quarter)
    }

    func testReplaceMeasureRhythmValueUpdatesSelectedSlotWhenMeasureStillFits() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.dottedQuarter, .eighth, .half],
                drawingData: Data([1, 2, 3]),
                for: measureID
            )
        )

        let result = chart.replaceMeasureRhythmValue(.eighthRest, at: 1, in: measureID)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(chart.measure(id: measureID)?.rhythmMap?.values, [.dottedQuarter, .eighthRest, .half])
        XCTAssertNil(chart.measure(id: measureID)?.rhythmMap?.drawingData)
    }

    func testReplaceMeasureRhythmValueAllowsSlashWhenDurationStillFits() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.quarter, .quarter, .quarter, .quarter],
                for: measureID
            )
        )

        let result = chart.replaceMeasureRhythmValue(.slash, at: 1, in: measureID)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(chart.measure(id: measureID)?.rhythmMap?.values, [.quarter, .slash, .quarter, .quarter])
    }

    func testReplaceMeasureRhythmValueRejectsChangesThatBreakMeterLength() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.quarter, .quarter, .quarter, .quarter],
                for: measureID
            )
        )

        let result = chart.replaceMeasureRhythmValue(.half, at: 0, in: measureID)

        XCTAssertEqual(result, .invalidMeterFit(.overflow(1)))
        XCTAssertEqual(chart.measure(id: measureID)?.rhythmMap?.values, [.quarter, .quarter, .quarter, .quarter])
    }

    func testSetMeasureManualLayoutWidthStoresClampedOverride() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        let appliedLargeWidth = try XCTUnwrap(chart.setMeasureManualLayoutWidth(680, for: measureID))
        XCTAssertEqual(appliedLargeWidth, Measure.maximumManualLayoutWidth)
        XCTAssertEqual(chart.measure(id: measureID)?.manualLayoutWidth, Double(Measure.maximumManualLayoutWidth))

        let appliedSmallWidth = try XCTUnwrap(chart.setMeasureManualLayoutWidth(44, for: measureID))
        XCTAssertEqual(appliedSmallWidth, Measure.minimumManualLayoutWidth)
        XCTAssertEqual(chart.measure(id: measureID)?.manualLayoutWidth, Double(Measure.minimumManualLayoutWidth))

        _ = chart.setMeasureManualLayoutWidth(nil, for: measureID)
        XCTAssertNil(chart.measure(id: measureID)?.manualLayoutWidth)
    }

    func testCommitOpenMeasureMarksCurrentMeasureCommittedAndAppendsNextOpenMeasure() {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let appendedOpenMeasureID = chart.commitOpenMeasure()

        XCTAssertNotNil(appendedOpenMeasureID)
        XCTAssertEqual(chart.measures.count, 2)
        XCTAssertEqual(chart.measures[0].authoringState, .committed)
        XCTAssertEqual(chart.measures[1].authoringState, .open)
        XCTAssertEqual(chart.measures[1].index, 2)
    }

    func testResolvedAuthoringMeasurePreservesValidPreferredMeasure() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let openMeasureID = try XCTUnwrap(chart.commitOpenMeasure())

        XCTAssertEqual(
            chart.resolvedAuthoringMeasureID(preferredMeasureID: firstMeasureID),
            firstMeasureID
        )
        XCTAssertNotEqual(firstMeasureID, openMeasureID)
    }

    func testResolvedAuthoringMeasureFallsBackToOpenMeasureThenLastMeasure() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let openMeasureID = try XCTUnwrap(chart.commitOpenMeasure())

        XCTAssertEqual(
            chart.resolvedAuthoringMeasureID(preferredMeasureID: UUID()),
            openMeasureID
        )

        chart.systems[0].measures[1].authoringState = .committed
        XCTAssertEqual(chart.resolvedAuthoringMeasureID(), openMeasureID)
        XCTAssertNotEqual(firstMeasureID, openMeasureID)
    }

    func testPositionOpenMeasureAfterCommittedMeasureMovesBlankOpenSlotBehindSelection() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        let trailingOpenMeasureID = try XCTUnwrap(chart.commitOpenMeasure())

        let repositionedOpenMeasureID = try XCTUnwrap(chart.positionOpenMeasure(after: firstMeasureID))

        XCTAssertEqual(repositionedOpenMeasureID, trailingOpenMeasureID)
        XCTAssertEqual(chart.measures.map(\.id), [firstMeasureID, trailingOpenMeasureID, secondMeasureID])
        XCTAssertEqual(chart.measure(id: trailingOpenMeasureID)?.authoringState, .open)
        XCTAssertEqual(chart.measure(id: secondMeasureID)?.authoringState, .committed)
    }

    func testPositionOpenMeasureKeepsNonBlankOpenMeasureInPlace() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        let trailingOpenMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        chart.systems[0].measures[2].chordEvents = [demoChordEvent(root: .c)]

        let resolvedOpenMeasureID = try XCTUnwrap(chart.positionOpenMeasure(after: firstMeasureID))

        XCTAssertEqual(resolvedOpenMeasureID, trailingOpenMeasureID)
        XCTAssertEqual(chart.measures.map(\.id), [firstMeasureID, secondMeasureID, trailingOpenMeasureID])
        XCTAssertEqual(chart.measure(id: trailingOpenMeasureID)?.authoringState, .open)
        XCTAssertEqual(chart.measure(id: secondMeasureID)?.authoringState, .committed)
    }

    func testPositionOpenMeasureKeepsOpenMeasureWithFreehandSymbolInPlace() throws {
        var chart = Chart.draft(title: "New Chart", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Roadmap",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        let trailingOpenMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        XCTAssertNotNil(
            chart.addFreehandSymbol(
                anchorMeasureID: trailingOpenMeasureID,
                lane: .aboveMeasure,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                drawingData: Data([1, 2, 3])
            )
        )

        let resolvedOpenMeasureID = try XCTUnwrap(chart.positionOpenMeasure(after: firstMeasureID))

        XCTAssertEqual(resolvedOpenMeasureID, trailingOpenMeasureID)
        XCTAssertEqual(chart.measures.map(\.id), [firstMeasureID, secondMeasureID, trailingOpenMeasureID])
        XCTAssertEqual(chart.measure(id: trailingOpenMeasureID)?.authoringState, .open)
        XCTAssertNotNil(chart.freehandSymbols.first { $0.anchorMeasureID == trailingOpenMeasureID })
    }

    func testPositionOpenMeasureReanchorsAnnotationsWhenLaterMeasureShiftsSystems() throws {
        let firstSystemID = UUID()
        let secondSystemID = UUID()
        let measure1 = makeMeasure(index: 1)
        let measure2 = makeMeasure(index: 2)
        let measure3 = makeMeasure(index: 3)
        let annotatedMeasure = makeMeasure(index: 4, barlineAfter: .double)
        let laterMeasure = makeMeasure(index: 5)
        let openMeasure = makeMeasure(index: 6, authoringState: .open)

        var chart = Chart(
            id: UUID(),
            title: "Anchored Chart",
            chartType: .chordChart,
            documentKey: .cMajor,
            documentFont: .classic,
            defaultTranspositionView: .concert,
            defaultMeter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            hasCompletedInitialSetup: true,
            systems: [
                ChartSystem(
                    id: firstSystemID,
                    index: 0,
                    spacingMode: .automatic,
                    lineBreakRule: .automatic,
                    measures: [measure1, measure2, measure3, annotatedMeasure]
                ),
                ChartSystem(
                    id: secondSystemID,
                    index: 1,
                    spacingMode: .automatic,
                    lineBreakRule: .automatic,
                    measures: [laterMeasure, openMeasure]
                )
            ],
            sectionLabels: [
                SectionLabel(
                    id: UUID(),
                    text: "B",
                    type: .sectionName,
                    anchorMeasureID: annotatedMeasure.id,
                    anchorSystemID: firstSystemID,
                    rawInput: "B"
                )
            ],
            cueTexts: [],
            roadmapObjects: [
                RoadmapObject(
                    id: UUID(),
                    type: .dc,
                    startMeasureID: annotatedMeasure.id,
                    endMeasureID: nil,
                    anchorSystemID: firstSystemID,
                    placement: .floatingTop,
                    displayText: nil,
                    count: nil,
                    linkedTargetID: nil,
                    rawInput: "D.C."
                )
            ],
            stylePreset: .cleanStudio,
            createdAt: .now,
            updatedAt: .now
        )

        let repositionedOpenMeasureID = try XCTUnwrap(chart.positionOpenMeasure(after: measure1.id))

        XCTAssertEqual(repositionedOpenMeasureID, openMeasure.id)
        XCTAssertEqual(chart.measures[0].id, measure1.id)
        XCTAssertEqual(chart.measures[1].id, openMeasure.id)
        XCTAssertEqual(chart.measure(id: annotatedMeasure.id)?.index, 5)
        XCTAssertEqual(chart.sectionLabels.first?.anchorSystemID, secondSystemID)
        XCTAssertEqual(chart.roadmapObjects.first?.anchorSystemID, secondSystemID)
    }

    func testApplyMeterChangeToNextTimeSignaturePersistsIntoFutureMeasures() throws {
        var chart = Chart.draft(title: "Time Changes")
        chart.completeInitialSetup(
            title: "Time Changes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())

        let changedMeasureID = try XCTUnwrap(
            chart.applyMeterChange(
                Meter(numerator: 3, denominator: 4),
                after: firstMeasureID,
                scope: .toNextTimeSignature
            )
        )
        let appendedMeasureID = try XCTUnwrap(chart.commitOpenMeasure())

        XCTAssertEqual(changedMeasureID, secondMeasureID)
        XCTAssertNil(chart.measure(id: firstMeasureID)?.meterOverride)
        XCTAssertEqual(chart.measure(id: secondMeasureID)?.meterOverride, Meter(numerator: 3, denominator: 4))
        XCTAssertEqual(chart.measure(id: appendedMeasureID)?.meterOverride, Meter(numerator: 3, denominator: 4))
    }

    func testApplyMeterChangeFixedMeasureCountRestoresSourceMeterAfterSpecifiedSpan() throws {
        var chart = Chart.draft(title: "Time Changes")
        chart.completeInitialSetup(
            title: "Time Changes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.applyMeterChange(
            Meter(numerator: 3, denominator: 4),
            after: firstMeasureID,
            scope: .fixedMeasureCount(1)
        )

        XCTAssertEqual(chart.measures.count, 3)
        XCTAssertEqual(chart.measures[1].meterOverride, Meter(numerator: 3, denominator: 4))
        XCTAssertEqual(chart.measures[2].meterOverride, Meter(numerator: 3, denominator: 4))

        let revertedMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        XCTAssertNil(chart.measure(id: revertedMeasureID)?.meterOverride)
    }

    func testApplyMeterChangeToEndOfPieceOverridesLaterTimeSignatures() throws {
        var chart = Chart.draft(title: "Time Changes")
        chart.completeInitialSetup(
            title: "Time Changes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        _ = chart.commitOpenMeasure()

        _ = chart.applyMeterChange(
            Meter(numerator: 5, denominator: 4),
            after: secondMeasureID,
            scope: .toNextTimeSignature
        )
        _ = chart.applyMeterChange(
            Meter(numerator: 3, denominator: 4),
            after: firstMeasureID,
            scope: .toEndOfPiece
        )

        XCTAssertEqual(chart.measures[1].meterOverride, Meter(numerator: 3, denominator: 4))
        XCTAssertEqual(chart.measures[2].meterOverride, Meter(numerator: 3, denominator: 4))
        XCTAssertTrue(chart.timeSignatureChanges.allSatisfy { $0.afterMeasureID == firstMeasureID })
    }

    private func makeMeasure(
        index: Int,
        barlineAfter: BarlineType = .single,
        authoringState: MeasureAuthoringState = .committed
    ) -> Measure {
        Measure(
            id: UUID(),
            index: index,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: barlineAfter,
            chordEvents: [],
            cueTextIDs: [],
            roadmapObjectIDs: [],
            authoringState: authoringState
        )
    }

    private func demoChordEvent(root: ChordRoot) -> ChordEvent {
        ChordEvent(
            id: UUID(),
            symbol: ChordSymbol(root: root, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
            duration: .quarter,
            rhythmPlacement: .belowChord,
            tieOut: false,
            hitStyle: .none,
            rawInput: nil
        )
    }
}

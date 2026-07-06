import XCTest
@testable import iChart

final class ChartEditingTests: XCTestCase {
    func testAddCueTextUpdatesChartAndMeasure() {
        var chart = Chart.blank(title: "Test Chart")

        chart.addCueText("hits")

        XCTAssertEqual(chart.cueTexts.count, 1)
        XCTAssertEqual(chart.cueTexts.first?.text, "hits")
        XCTAssertEqual(chart.cueTexts.first?.scale, CueText.defaultScale)
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

    func testCueTextCanUpdateResizeAndDeleteSingleObject() throws {
        var chart = Chart.blank(title: "Cue Text", measureCount: 1)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let cueTextID = try XCTUnwrap(chart.addCueText("hits", anchorMeasureID: measureID))

        XCTAssertTrue(
            chart.updateCueText(
                cueTextID,
                text: "  stop time  ",
                scale: CueText.maximumScale + 4,
                emphasis: .strong,
                position: .above,
                verticalOffset: CueText.maximumVerticalOffset + 40
            )
        )

        var cueText = try XCTUnwrap(chart.cueText(id: cueTextID))
        XCTAssertEqual(cueText.text, "stop time")
        XCTAssertEqual(cueText.rawInput, "stop time")
        XCTAssertEqual(cueText.scale, CueText.maximumScale)
        XCTAssertEqual(cueText.verticalOffset, CueText.maximumVerticalOffset)
        XCTAssertEqual(cueText.emphasis, .strong)
        XCTAssertEqual(cueText.position, .above)
        XCTAssertEqual(chart.measure(id: measureID)?.cueTextIDs, [cueTextID])

        XCTAssertTrue(chart.resizeCueText(cueTextID, byScaleDelta: -10))
        cueText = try XCTUnwrap(chart.cueText(id: cueTextID))
        XCTAssertEqual(cueText.scale, CueText.minimumScale)

        XCTAssertFalse(chart.updateCueText(cueTextID, text: "   "))
        XCTAssertTrue(chart.deleteCueText(cueTextID))
        XCTAssertNil(chart.cueText(id: cueTextID))
        XCTAssertTrue(chart.measure(id: measureID)?.cueTextIDs.isEmpty == true)
        XCTAssertFalse(chart.deleteCueText(cueTextID))
    }

    func testCueTextMoveSnapsToPlacementSubdivisionAndUpdatesMeasureBackReferences() throws {
        var chart = Chart.blank(title: "Cue Text", measureCount: 2)
        let measureIDs = chart.measures.map(\.id)
        let cueTextID = try XCTUnwrap(chart.addCueText("hits", anchorMeasureID: measureIDs[0]))

        XCTAssertTrue(
            chart.moveCueText(
                cueTextID,
                to: measureIDs[1],
                atFraction: 0.38,
                verticalOffset: -22
            )
        )

        let cueText = try XCTUnwrap(chart.cueText(id: cueTextID))
        XCTAssertEqual(cueText.anchorMeasureID, measureIDs[1])
        XCTAssertEqual(try XCTUnwrap(cueText.beatFraction), 0.375, accuracy: 0.0001)
        XCTAssertEqual(cueText.verticalOffset, -22)
        XCTAssertTrue(chart.measure(id: measureIDs[0])?.cueTextIDs.isEmpty == true)
        XCTAssertEqual(chart.measure(id: measureIDs[1])?.cueTextIDs, [cueTextID])
    }

    func testCueTextMoveUsesSixteenthPlacementSubdivisionForEighthNoteMeter() throws {
        var chart = Chart.blank(title: "Cue Text", measureCount: 1)
        chart.defaultMeter = Meter(numerator: 6, denominator: 8)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let cueTextID = try XCTUnwrap(chart.addCueText("hits", anchorMeasureID: measureID))

        XCTAssertTrue(chart.moveCueText(cueTextID, to: measureID, atFraction: 0.10))

        let cueText = try XCTUnwrap(chart.cueText(id: cueTextID))
        XCTAssertEqual(try XCTUnwrap(cueText.beatFraction), 1.0 / 12.0, accuracy: 0.0001)
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

    func testMovePointRoadmapMarkerRelocatesMeasureBackReferences() throws {
        var chart = Chart.blank(title: "Roadmap Markers", measureCount: 3)
        let measureIDs = chart.measures.map(\.id)
        let markerID = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: measureIDs[0]))
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[1])
        )

        XCTAssertTrue(chart.movePointRoadmapMarker(markerID, to: measureIDs[2]))

        let marker = try XCTUnwrap(chart.roadmapObject(id: markerID))
        XCTAssertEqual(marker.startMeasureID, measureIDs[2])
        XCTAssertEqual(marker.anchorSystemID, chart.systems[0].id)
        XCTAssertTrue(chart.measure(id: measureIDs[0])?.roadmapObjectIDs.contains(markerID) == false)
        XCTAssertEqual(chart.measure(id: measureIDs[2])?.roadmapObjectIDs, [markerID])
        XCTAssertFalse(chart.movePointRoadmapMarker(markerID, to: measureIDs[2]))
        XCTAssertFalse(chart.movePointRoadmapMarker(repeatID, to: measureIDs[2]))
        XCTAssertFalse(chart.movePointRoadmapMarker(markerID, to: UUID()))
    }

    func testMovePointRoadmapMarkerHorizontallyClampsWithinMeasure() throws {
        var chart = Chart.blank(title: "Roadmap Markers", measureCount: 2)
        let measureIDs = chart.measures.map(\.id)
        let markerID = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: measureIDs[0]))
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[1])
        )

        XCTAssertTrue(chart.movePointRoadmapMarkerHorizontally(markerID, toNormalizedOffset: 1.4))
        XCTAssertEqual(chart.roadmapObject(id: markerID)?.horizontalOffsetWithinMeasure, 1)
        XCTAssertFalse(chart.movePointRoadmapMarkerHorizontally(markerID, toNormalizedOffset: 1))
        XCTAssertTrue(chart.movePointRoadmapMarkerHorizontally(markerID, toNormalizedOffset: -0.25))
        XCTAssertEqual(chart.roadmapObject(id: markerID)?.horizontalOffsetWithinMeasure, 0)
        XCTAssertFalse(chart.movePointRoadmapMarkerHorizontally(repeatID, toNormalizedOffset: 0.5))
        XCTAssertFalse(chart.movePointRoadmapMarkerHorizontally(UUID(), toNormalizedOffset: 0.5))
        XCTAssertFalse(chart.movePointRoadmapMarkerHorizontally(markerID, toNormalizedOffset: .nan))
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

    func testInsertMeasureAfterSelectedAddsMeasureWithoutMovingTrailingOpenMeasure() throws {
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

        let insertedID = try XCTUnwrap(chart.insertMeasure(after: firstMeasureID))

        XCTAssertEqual(chart.measures.map(\.id), [
            firstMeasureID,
            insertedID,
            secondMeasureID,
            trailingOpenMeasureID
        ])
        XCTAssertEqual(chart.measure(id: insertedID)?.authoringState, .committed)
        XCTAssertEqual(chart.measure(id: trailingOpenMeasureID)?.authoringState, .open)
        XCTAssertEqual(chart.measures.map(\.index), Array(1...4))
    }

    func testInsertMeasureStackAfterSelectedAddsChosenMeasuresWithoutMovingTrailingOpenMeasure() throws {
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

        let insertedIDs = try XCTUnwrap(chart.insertMeasures(after: firstMeasureID, count: 3))

        XCTAssertEqual(chart.measures.map(\.id), [
            firstMeasureID,
            insertedIDs[0],
            insertedIDs[1],
            insertedIDs[2],
            secondMeasureID,
            trailingOpenMeasureID
        ])
        XCTAssertEqual(insertedIDs.count, 3)
        XCTAssertTrue(insertedIDs.allSatisfy { chart.measure(id: $0)?.authoringState == .committed })
        XCTAssertEqual(chart.measure(id: trailingOpenMeasureID)?.authoringState, .open)
        XCTAssertEqual(chart.measures.map(\.index), Array(1...6))
    }

    func testInsertMeasureStackRejectsZeroCountAndMissingAnchor() throws {
        var chart = Chart.blank(title: "Stack Gate", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)

        XCTAssertNil(chart.insertMeasures(after: measureIDs[0], count: 0))
        XCTAssertNil(chart.insertMeasures(after: UUID(), count: 4))
        XCTAssertEqual(chart.measures.map(\.id), measureIDs)
        XCTAssertEqual(chart.measures.map(\.index), [1, 2])
    }

    func testInsertMeasureStackAfterOpenAnchorLeavesTrailingOpenMeasure() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let openAnchorID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertEqual(chart.measure(id: openAnchorID)?.authoringState, .open)

        let trailingOpenMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        let insertedIDs = try XCTUnwrap(chart.insertMeasures(after: openAnchorID, count: 2))

        XCTAssertEqual(chart.measures.map(\.id), [
            openAnchorID,
            insertedIDs[0],
            insertedIDs[1],
            trailingOpenMeasureID
        ])
        XCTAssertEqual(chart.measure(id: openAnchorID)?.authoringState, .committed)
        XCTAssertTrue(insertedIDs.allSatisfy { chart.measure(id: $0)?.authoringState == .committed })
        XCTAssertEqual(chart.measures.last?.authoringState, .open)
        XCTAssertEqual(chart.measures.map(\.index), Array(1...4))
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
                lane: .chartArea,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                measureRelativeFrame: FreehandSymbolMeasureFrame(offsetX: 12, offsetY: 18, width: 24, height: 18),
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

        XCTAssertFalse(chart.canDeleteMeasure(id: onlyMeasureID))
        XCTAssertFalse(chart.deleteMeasure(id: onlyMeasureID))

        XCTAssertEqual(chart.measures.count, 1)
    }

    func testCanDeleteMeasureRequiresExistingMeasureAndSpareMeasure() throws {
        var chart = Chart.blank(title: "Delete Gate", measureCount: 2)
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.measures.last?.id)

        XCTAssertTrue(chart.canDeleteMeasure(id: firstMeasureID))
        XCTAssertFalse(chart.canDeleteMeasure(id: UUID()))

        XCTAssertTrue(chart.deleteMeasure(id: secondMeasureID))
        XCTAssertFalse(chart.canDeleteMeasure(id: firstMeasureID))
    }

    func testDeleteMeasureRangeRemovesSelectedRangeStacks() throws {
        var chart = Chart.blank(title: "Range Delete", measureCount: 5, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        let keptMarkerID = try XCTUnwrap(
            chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: measureIDs[0])
        )
        let deletedMarkerID = try XCTUnwrap(
            chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureIDs[3])
        )
        XCTAssertEqual(chart.linkPointRoadmapMarkers(attachedTo: measureIDs[0]), 1)
        XCTAssertEqual(chart.roadmapObject(id: keptMarkerID)?.linkedTargetID, deletedMarkerID)
        let deletedRepeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[1], endMeasureID: measureIDs[3])
        )
        let deletedCueID = try XCTUnwrap(
            chart.addCueText("break", anchorMeasureID: measureIDs[3])
        )
        let deletedFreehandID = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureIDs[3],
                lane: .chartArea,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.1, y: 0.2, width: 0.2, height: 0.2),
                measureRelativeFrame: FreehandSymbolMeasureFrame(offsetX: 12, offsetY: 8, width: 22, height: 18),
                drawingData: Data([9, 8, 7])
            )
        )
        let keptFreehandID = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureIDs[4],
                lane: .chartArea,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.1, y: 0.2, width: 0.2, height: 0.2),
                measureRelativeFrame: FreehandSymbolMeasureFrame(offsetX: 12, offsetY: 8, width: 22, height: 18),
                drawingData: Data([9, 8, 7])
            )
        )
        let deletedChordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                ChordSymbol(root: .c, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
                rawInput: "C7",
                to: measureIDs[2],
                atFraction: 0.1
            )
        )
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureIDs[2]))

        XCTAssertTrue(chart.canDeleteMeasures(from: measureIDs[3], through: measureIDs[2]))
        XCTAssertTrue(chart.deleteMeasures(from: measureIDs[3], through: measureIDs[2]))

        XCTAssertEqual(chart.measures.map(\.id), [measureIDs[0], measureIDs[1], measureIDs[4]])
        XCTAssertNil(chart.roadmapObject(id: deletedMarkerID))
        XCTAssertNil(chart.roadmapObject(id: deletedRepeatID))
        XCTAssertNil(chart.cueText(id: deletedCueID))
        XCTAssertNil(chart.freehandSymbol(id: deletedFreehandID))
        XCTAssertNotNil(chart.freehandSymbol(id: keptFreehandID))
        XCTAssertNil(chart.chordEvent(id: deletedChordID))
        XCTAssertNil(chart.roadmapObject(id: keptMarkerID)?.linkedTargetID)
        XCTAssertTrue(chart.measures.allSatisfy { $0.roadmapObjectIDs.allSatisfy { $0 == keptMarkerID } })
        XCTAssertTrue(chart.measures.allSatisfy(\.cueTextIDs.isEmpty))
        XCTAssertEqual(chart.measures.map(\.index), [1, 2, 3])
    }

    func testDeleteMeasureRangePreservesOneMeasureMinimum() throws {
        var chart = Chart.blank(title: "Range Delete Gate", measureCount: 3, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)

        XCTAssertFalse(chart.canDeleteMeasures(from: measureIDs[0], through: measureIDs[2]))
        XCTAssertFalse(chart.deleteMeasures(from: measureIDs[0], through: measureIDs[2]))
        XCTAssertEqual(chart.measures.map(\.id), measureIDs)
        XCTAssertEqual(chart.measures.map(\.index), [1, 2, 3])

        XCTAssertTrue(chart.canDeleteMeasures(from: measureIDs[0], through: measureIDs[1]))
        XCTAssertTrue(chart.deleteMeasures(from: measureIDs[0], through: measureIDs[1]))

        XCTAssertEqual(chart.measures.map(\.id), [measureIDs[2]])
        XCTAssertEqual(chart.measures.map(\.index), [1])
        XCTAssertFalse(chart.canDeleteMeasures(from: measureIDs[2], through: measureIDs[2]))
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

    func testInstrumentTranspositionViewsExposeInstrumentLabelsAndIntervals() {
        XCTAssertEqual(TranspositionView.concert.displayText, "Concert")
        XCTAssertEqual(TranspositionView.concert.intervalDisplayText, "No transpose")
        XCTAssertEqual(TranspositionView.bb.displayText, "Bb Horn")
        XCTAssertEqual(TranspositionView.bb.intervalDisplayText, "+M2")
        XCTAssertEqual(TranspositionView.eb.displayText, "Eb Horn")
        XCTAssertEqual(TranspositionView.eb.intervalDisplayText, "+M6")
        XCTAssertEqual(TranspositionView.f.displayText, "F Horn")
        XCTAssertEqual(TranspositionView.f.intervalDisplayText, "+P5")
    }

    func testChordTranspositionSemitonesNormalizeForChartDisplay() {
        var chart = Chart.blank(title: "Transposition", measureCount: 1, layoutStyle: .simpleChordSheet)

        chart.setChordTranspositionSemitones(14)

        XCTAssertEqual(chart.chordTranspositionSemitones, 2)
        XCTAssertEqual(chart.chordTranspositionDisplayText, "+M2")

        chart.transposeChordsByHalfSteps(-3)

        XCTAssertEqual(chart.chordTranspositionSemitones, 11)
        XCTAssertEqual(chart.chordTranspositionDisplayText, "+M7")
    }

    func testInstrumentTranspositionPresetResetsManualOffset() {
        var chart = Chart.blank(title: "Transposition", measureCount: 1, layoutStyle: .simpleChordSheet)

        chart.setChordTranspositionSemitones(5)
        chart.setInstrumentTranspositionView(.bb)

        XCTAssertEqual(chart.defaultTranspositionView, .bb)
        XCTAssertEqual(chart.chordTranspositionSemitones, 0)
        XCTAssertEqual(chart.libraryTranspositionText, "Bb Horn")
    }

    func testDisplayedChordSymbolAppliesChartTranspositionWithoutMutatingSourceChord() throws {
        var chart = Chart.blank(title: "Transposition", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let sourceSymbol = try ChordSymbolParser.parse("G/B")
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                sourceSymbol,
                rawInput: "G/B",
                to: measureID,
                atFraction: 0.05,
                sourceInkData: Data([1, 2, 3]),
                sourceCandidateSignature: ["G/B"]
            )
        )

        chart.setChordTranspositionSemitones(1)

        let storedChord = try XCTUnwrap(chart.chordEvent(id: chordID))
        XCTAssertEqual(storedChord.symbol.displayText, "G/B")
        XCTAssertEqual(storedChord.rawInput, "G/B")
        XCTAssertEqual(chart.displayedChordSymbol(for: storedChord).displayText, "G#/C")
    }

    func testDisplayedChordSymbolPreservesAccidentalFamilyForFlatChordTransposition() throws {
        var chart = Chart.blank(title: "Transposition", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let sourceSymbol = try ChordSymbolParser.parse("Db7(b9)/Ab")
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                sourceSymbol,
                rawInput: "Db7(b9)/Ab",
                to: measureID,
                atFraction: 0.05
            )
        )

        chart.setChordTranspositionSemitones(2)

        let storedChord = try XCTUnwrap(chart.chordEvent(id: chordID))
        XCTAssertEqual(chart.displayedChordSymbol(for: storedChord).displayText, "Eb7(b9)/Bb")
        XCTAssertEqual(storedChord.symbol.displayText, "Db7(b9)/Ab")
    }

    func testLegacyChartDecodingDefaultsChordTranspositionToWritten() throws {
        let chart = Chart.blank(title: "Legacy", measureCount: 1, layoutStyle: .simpleChordSheet)
        let encodedChart = try JSONEncoder().encode(chart)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedChart) as? [String: Any])

        object.removeValue(forKey: "chordTranspositionSemitones")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decodedChart = try JSONDecoder().decode(Chart.self, from: legacyData)

        XCTAssertEqual(decodedChart.chordTranspositionSemitones, 0)
        XCTAssertEqual(decodedChart.chordTranspositionDisplayText, "Written")
    }

    func testLegacyChartDecodingDefaultsHeaderInputModeToTyped() throws {
        let chart = Chart.blank(title: "Legacy Header", measureCount: 1, layoutStyle: .simpleChordSheet)
        let encodedChart = try JSONEncoder().encode(chart)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedChart) as? [String: Any])

        object.removeValue(forKey: "headerInputMode")
        object.removeValue(forKey: "pageHandwrittenHeaderData")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decodedChart = try JSONDecoder().decode(Chart.self, from: legacyData)

        XCTAssertEqual(decodedChart.headerInputMode, .typed)
        XCTAssertNil(decodedChart.pageHandwrittenHeaderData)
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
        XCTAssertEqual(chart.measures.first?.barlineAfter, .single)
        XCTAssertTrue(chart.measures.allSatisfy { $0.beatGridPreset == .eighthSubdivision })
        XCTAssertTrue(chart.measures.dropLast().allSatisfy { $0.authoringState == .committed })
        XCTAssertEqual(chart.measures.last?.authoringState, .open)
    }

    func testRenderedClefUsesBassForRhythmSectionAndDefaultForLeadSheets() {
        var rhythmChart = Chart.blank(title: "Pocket", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        var leadChart = Chart.blank(title: "Lead", measureCount: 4, layoutStyle: .leadSheet)

        rhythmChart.defaultClef = .treble
        leadChart.defaultClef = .treble

        XCTAssertEqual(rhythmChart.renderedClef, .bass)
        XCTAssertEqual(leadChart.renderedClef, .treble)

        leadChart.defaultClef = .bass

        XCTAssertEqual(leadChart.renderedClef, .bass)
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
        XCTAssertEqual(chart.measures[0].barlineAfter, .single)
    }

    func testCompleteInitialSetupStoresSelectedSheetStyle() {
        var chordChart = Chart.draft(title: "Staff Chords", layoutStyle: .simpleChordSheet)
        var rhythmChart = Chart.draft(title: "Plain Rhythm", layoutStyle: .rhythmSectionSheet)

        chordChart.completeInitialSetup(
            title: chordChart.title,
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            stylePreset: .gigSheet
        )
        rhythmChart.completeInitialSetup(
            title: rhythmChart.title,
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            stylePreset: .rehearsalDraft
        )

        XCTAssertEqual(chordChart.stylePreset, .gigSheet)
        XCTAssertEqual(rhythmChart.stylePreset, .rehearsalDraft)
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

    func testStylePresetsUseLayoutSpecificSheetLabels() {
        XCTAssertEqual(StylePreset.cleanStudio.sheetDisplayText(for: .simpleChordSheet), "Real Book")
        XCTAssertEqual(StylePreset.gigSheet.sheetDisplayText(for: .simpleChordSheet), "Staff Paper")
        XCTAssertEqual(StylePreset.plainWhite.sheetDisplayText(for: .simpleChordSheet), "White")
        XCTAssertEqual(StylePreset.rehearsalDraft.sheetDisplayText(for: .simpleChordSheet), "White Staff")

        XCTAssertEqual(StylePreset.cleanStudio.sheetDisplayText(for: .rhythmSectionSheet), "Paper")
        XCTAssertEqual(StylePreset.gigSheet.sheetDisplayText(for: .rhythmSectionSheet), "Warm Paper")
        XCTAssertEqual(StylePreset.rehearsalDraft.sheetDisplayText(for: .rhythmSectionSheet), "White")
        XCTAssertEqual(
            StylePreset.sheetPresets(for: .simpleChordSheet),
            [.cleanStudio, .gigSheet, .plainWhite, .rehearsalDraft]
        )
        XCTAssertEqual(StylePreset.sheetPresets(for: .rhythmSectionSheet), [.cleanStudio, .gigSheet, .rehearsalDraft])
    }

    func testLayoutProfilesDefineSeparateChartStructureContracts() {
        let chordProfile = ChartLayoutStyle.simpleChordSheet.profile
        let rhythmProfile = ChartLayoutStyle.rhythmSectionSheet.profile
        let leadProfile = ChartLayoutStyle.leadSheet.profile

        XCTAssertEqual(chordProfile.toolbarEmphasis, .chordRoadmap)
        XCTAssertEqual(chordProfile.primaryToolFocus, [.chordEntry, .sectionRoadmap, .cueText, .measureLayout, .appearance])
        XCTAssertEqual(chordProfile.setupPolicy.includesKeySelection, false)
        XCTAssertEqual(chordProfile.setupPolicy.includesTimeSignatureSelection, true)
        XCTAssertEqual(chordProfile.setupPolicy.includesStartingMeasureSelection, true)
        XCTAssertEqual(chordProfile.setupPolicy.clefOptions, [])
        XCTAssertEqual(chordProfile.notationLanePolicy, .chordGrid)
        XCTAssertEqual(chordProfile.freehandSymbolLanes, [.chartArea])
        XCTAssertTrue(chordProfile.allowsFreehandSymbolInk)
        XCTAssertFalse(chordProfile.allowsRhythmicNotationInk)
        XCTAssertFalse(chordProfile.allowsUserFacingRhythmNoteEditing)
        XCTAssertEqual(chordProfile.measureDefaults.initialMeasureCount, 1)
        XCTAssertEqual(chordProfile.measureDefaults.preferredMeasuresPerSystem, 4)
        XCTAssertEqual(chordProfile.measureDefaults.maximumMeasuresPerSystem, 20)
        XCTAssertEqual(chordProfile.measureDefaults.systemSpacingMode, .compact)
        XCTAssertEqual(chordProfile.measureDefaults.beatGridPreset, .simple)

        XCTAssertEqual(rhythmProfile.toolbarEmphasis, .rhythmAndHits)
        XCTAssertEqual(rhythmProfile.primaryToolFocus, [.chordEntry, .rhythmNotation, .sectionRoadmap, .cueText, .measureLayout, .appearance])
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
        XCTAssertEqual(blankChart.measures.first?.barlineAfter, .double)
        XCTAssertEqual(rhythmChart.systems[0].spacingMode, .relaxed)
        XCTAssertEqual(rhythmChart.measures.first?.barlineAfter, .single)
        XCTAssertTrue(rhythmChart.measures.allSatisfy { $0.beatGridPreset == .eighthSubdivision })
    }

    func testFirstMeasureDoesNotForceTrailingDoubleBarlineAfterInsertAndDelete() throws {
        var chart = Chart.blank(title: "Double Start", measureCount: 3, layoutStyle: .rhythmSectionSheet)
        let originalFirstID = try XCTUnwrap(chart.measures.first?.id)
        let originalSecondID = chart.measures[1].id

        XCTAssertEqual(chart.measure(id: originalFirstID)?.barlineAfter, .single)
        XCTAssertEqual(chart.measure(id: originalSecondID)?.barlineAfter, .single)

        let insertedID = chart.insertMeasureAtBeginning()
        XCTAssertEqual(chart.measures.first?.id, insertedID)
        XCTAssertEqual(chart.measures.first?.barlineAfter, .single)

        XCTAssertTrue(chart.deleteMeasure(id: insertedID))
        XCTAssertEqual(chart.measures.first?.id, originalFirstID)
        XCTAssertEqual(chart.measure(id: originalFirstID)?.barlineAfter, .single)

        XCTAssertTrue(chart.deleteMeasure(id: originalFirstID))
        XCTAssertEqual(chart.measures.first?.id, originalSecondID)
        XCTAssertEqual(chart.measure(id: originalSecondID)?.barlineAfter, .single)
    }

    func testCommitOpenMeasureCanCreateDoubleBarlineMeasure() throws {
        var chart = Chart.draft(title: "Open Double", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Open Double",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 2
        )
        let openMeasureID = try XCTUnwrap(chart.measures.last?.id)

        let nextOpenMeasureID = try XCTUnwrap(chart.commitOpenMeasure(barlineAfter: .double))

        XCTAssertEqual(chart.measure(id: openMeasureID)?.authoringState, .committed)
        XCTAssertEqual(chart.measure(id: openMeasureID)?.barlineAfter, .double)
        XCTAssertEqual(chart.measure(id: nextOpenMeasureID)?.authoringState, .open)
        XCTAssertEqual(chart.measure(id: nextOpenMeasureID)?.barlineAfter, .single)
    }

    func testChartInitializationPreservesFirstMeasureTrailingBarline() {
        let chart = Chart(
            id: UUID(),
            title: "Legacy Single Start",
            chartType: .chordChart,
            documentKey: .cMajor,
            documentFont: .classic,
            defaultTranspositionView: .concert,
            defaultMeter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            systems: [
                ChartSystem(
                    id: UUID(),
                    index: 0,
                    spacingMode: .automatic,
                    lineBreakRule: .automatic,
                    measures: [
                        makeMeasure(index: 1, barlineAfter: .single),
                        makeMeasure(index: 2, barlineAfter: .single)
                    ]
                )
            ],
            sectionLabels: [],
            cueTexts: [],
            roadmapObjects: [],
            stylePreset: .rehearsalDraft,
            createdAt: .now,
            updatedAt: .now
        )

        XCTAssertEqual(chart.measures.first?.barlineAfter, .single)
        XCTAssertEqual(chart.measures.last?.barlineAfter, .single)
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

    func testRhythmSectionManualSystemBreakSplitsAndRemovesRows() throws {
        var chart = Chart.blank(title: "Rhythm Rows", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        let secondMeasureID = try XCTUnwrap(measureIDs.dropFirst().first)

        XCTAssertFalse(chart.canInsertSystemBreak(before: measureIDs[0]))
        XCTAssertTrue(chart.canInsertSystemBreak(before: secondMeasureID))
        XCTAssertTrue(chart.insertSystemBreak(before: secondMeasureID))

        XCTAssertEqual(chart.systems.count, 2)
        XCTAssertEqual(chart.systems[0].measures.map(\.id), [measureIDs[0]])
        XCTAssertEqual(chart.systems[1].measures.map(\.id), Array(measureIDs[1..<4]))
        XCTAssertEqual(chart.systems[1].lineBreakRule, .forced)
        XCTAssertFalse(chart.canInsertSystemBreak(before: secondMeasureID))
        XCTAssertTrue(chart.canRemoveSystemBreak(before: secondMeasureID))
        XCTAssertTrue(chart.removeSystemBreak(before: secondMeasureID))

        XCTAssertEqual(chart.systems.count, 1)
        XCTAssertEqual(chart.measures.map(\.id), measureIDs)
        XCTAssertEqual(chart.systems[0].lineBreakRule, .automatic)
    }

    func testSimpleNamedSystemBreakControlsRemainSimpleOnly() throws {
        var chart = Chart.blank(title: "Rhythm Rows", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let secondMeasureID = try XCTUnwrap(chart.measures.dropFirst().first?.id)

        XCTAssertFalse(chart.canInsertSimpleSystemBreak(before: secondMeasureID))
        XCTAssertFalse(chart.insertSimpleSystemBreak(before: secondMeasureID))
        XCTAssertFalse(chart.removeSimpleSystemBreak(before: secondMeasureID))
        XCTAssertEqual(chart.systems.count, 1)
    }

    func testLeadSheetRejectsManualSystemBreakControlsForNow() throws {
        var chart = Chart.blank(title: "Lead Rows", measureCount: 4, layoutStyle: .leadSheet)
        let secondMeasureID = try XCTUnwrap(chart.measures.dropFirst().first?.id)

        XCTAssertFalse(chart.canInsertSystemBreak(before: secondMeasureID))
        XCTAssertFalse(chart.insertSystemBreak(before: secondMeasureID))
        XCTAssertFalse(chart.removeSystemBreak(before: secondMeasureID))
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

    func testFinaleJazzUsesLowercaseSafeChordTextFace() {
        XCTAssertEqual(NotationFontPreset.finaleJazz.textPostScriptName, "FinaleJazzText")
        XCTAssertEqual(NotationFontPreset.finaleJazz.chordTextPostScriptName, "FinaleJazzTextLowercase")
        XCTAssertEqual(NotationFontPreset.petaluma.chordTextPostScriptName, NotationFontPreset.petaluma.textPostScriptName)
    }

    func testFinaleAshSettersNormalizeToLowercaseSafeFinaleJazz() {
        var chart = Chart.blank(title: "Ash Fonts")

        chart.setNotationFont(.finaleAsh)
        chart.setMatchedFontFamily(.finaleAsh)
        chart.setChordFontOverride(.finaleAsh)
        chart.setHeaderFontOverride(.finaleAsh)
        chart.setTextFontOverride(.finaleAsh)

        XCTAssertEqual(chart.notationFont, .finaleJazz)
        XCTAssertEqual(chart.typography.matchedSet, .finaleJazz)
        XCTAssertEqual(chart.typography.chordOverride, .finaleJazz)
        XCTAssertEqual(chart.typography.headerOverride, .finaleJazz)
        XCTAssertEqual(chart.typography.textOverride, .finaleJazz)
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
        XCTAssertEqual(NotationGlyphCatalog.sixteenthRest, "\u{E4E7}")
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

    func testSetPageHandwrittenHeaderDrawingStoresSeparatelyFromPageAndChordInk() {
        var chart = Chart.draft(title: "New Chart")
        let pageInkData = Data([4, 3, 2, 1])
        let headerInkData = Data([1, 3, 5, 7])
        let chordInkData = Data([8, 7, 6, 5])

        chart.setHeaderInputMode(.handwritten)

        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(pageInkData))
        XCTAssertTrue(chart.setPageHandwrittenHeaderDrawing(headerInkData))
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(chordInkData))
        XCTAssertEqual(chart.headerInputMode, .handwritten)
        XCTAssertEqual(chart.pageHandwrittenNotationData, pageInkData)
        XCTAssertEqual(chart.pageHandwrittenHeaderData, headerInkData)
        XCTAssertEqual(chart.pageHandwrittenChordData, chordInkData)

        XCTAssertTrue(chart.setPageHandwrittenHeaderDrawing(nil))
        XCTAssertNil(chart.pageHandwrittenHeaderData)
        XCTAssertEqual(chart.pageHandwrittenNotationData, pageInkData)
        XCTAssertEqual(chart.pageHandwrittenChordData, chordInkData)
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

    func testAddFreehandSymbolStoresSimpleMeasureAttachedFloatingInkObject() throws {
        var chart = Chart.blank(title: "Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let drawingData = Data([9, 7, 5, 3])
        let normalizedFrame = FreehandSymbolNormalizedFrame(x: 0.1, y: 0.2, width: 0.35, height: 0.4)
        let measureRelativeFrame = FreehandSymbolMeasureFrame(offsetX: -12, offsetY: 18, width: 42, height: 16)

        let symbolID = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureID,
                lane: .chartArea,
                normalizedFrame: normalizedFrame,
                measureRelativeFrame: measureRelativeFrame,
                drawingData: drawingData
            )
        )

        let symbol = try XCTUnwrap(chart.freehandSymbol(id: symbolID))
        XCTAssertEqual(symbol.anchorMeasureID, measureID)
        XCTAssertEqual(symbol.lane, .chartArea)
        XCTAssertEqual(symbol.normalizedFrame, normalizedFrame)
        XCTAssertEqual(symbol.measureRelativeFrame, measureRelativeFrame)
        XCTAssertEqual(symbol.drawingData, drawingData)
        XCTAssertEqual(symbol.zIndex, 0)
    }

    func testFreehandSymbolsFollowLayoutProfileLanesAndRejectEmptyDrawingData() throws {
        var simpleChart = Chart.blank(title: "Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        var rhythmChart = Chart.blank(title: "Pocket", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        var leadChart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let simpleMeasureID = try XCTUnwrap(simpleChart.measures.first?.id)
        let rhythmMeasureID = try XCTUnwrap(rhythmChart.measures.first?.id)
        let leadMeasureID = try XCTUnwrap(leadChart.measures.first?.id)
        let frame = FreehandSymbolNormalizedFrame(x: 0, y: 0, width: 0.5, height: 0.5)
        let measureRelativeFrame = FreehandSymbolMeasureFrame(offsetX: 4, offsetY: 6, width: 20, height: 12)

        XCTAssertNil(
            simpleChart.addFreehandSymbol(
                anchorMeasureID: simpleMeasureID,
                lane: .chartArea,
                normalizedFrame: frame,
                drawingData: Data()
            )
        )
        XCTAssertNil(
            simpleChart.addFreehandSymbol(
                anchorMeasureID: simpleMeasureID,
                lane: .chartArea,
                normalizedFrame: frame,
                drawingData: Data([1])
            )
        )
        XCTAssertNil(
            simpleChart.addFreehandSymbol(
                anchorMeasureID: simpleMeasureID,
                lane: .aboveMeasure,
                normalizedFrame: frame,
                drawingData: Data([1])
            )
        )
        let simpleSymbolID = try XCTUnwrap(
            simpleChart.addFreehandSymbol(
                anchorMeasureID: simpleMeasureID,
                lane: .chartArea,
                normalizedFrame: frame,
                measureRelativeFrame: measureRelativeFrame,
                drawingData: Data([1])
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
                lane: .chartArea,
                normalizedFrame: frame,
                measureRelativeFrame: measureRelativeFrame,
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
        XCTAssertEqual(simpleChart.freehandSymbols.map(\.id), [simpleSymbolID])
        XCTAssertEqual(simpleChart.freehandSymbols.map(\.lane), [.chartArea])
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
        var chart = Chart.blank(title: "Roadmap", measureCount: 2, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        let normalizedFrame = FreehandSymbolNormalizedFrame(x: 0.1, y: 0.2, width: 0.35, height: 0.4)
        let originalFrame = FreehandSymbolMeasureFrame(offsetX: -10, offsetY: 20, width: 48, height: 18)
        let movedFrame = FreehandSymbolMeasureFrame(offsetX: 18, offsetY: 28, width: 48, height: 18)
        let symbolID = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureIDs[0],
                lane: .chartArea,
                normalizedFrame: normalizedFrame,
                measureRelativeFrame: originalFrame,
                drawingData: Data([4, 5, 6])
            )
        )

        XCTAssertFalse(chart.moveFreehandSymbol(symbolID, to: normalizedFrame))
        XCTAssertTrue(chart.moveFreehandSymbol(symbolID, to: movedFrame, anchorMeasureID: measureIDs[1]))
        XCTAssertEqual(chart.freehandSymbol(id: symbolID)?.anchorMeasureID, measureIDs[1])
        XCTAssertEqual(chart.freehandSymbol(id: symbolID)?.measureRelativeFrame, movedFrame)
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

    func testMoveChordEventSnapsExistingChordToRequestedPlacementSubdivision() throws {
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
        XCTAssertEqual(movedChord.startPosition.displayText, "3&")
        XCTAssertEqual(movedChord.startPosition.subdivisionsPerBeat, 2)
        XCTAssertNil(movedChord.mappedRhythmSlotIndex)
    }

    func testSimpleChordSheetFirstChordAlwaysStartsAtBeatOne() throws {
        var chart = Chart.blank(title: "Simple Chords", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)

        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "C", to: measureID, atFraction: 0.72))

        let chord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(chord.startPosition.displayText, "1")
        XCTAssertNil(chord.mappedRhythmSlotIndex)
    }

    func testRhythmSectionFirstChordWithoutRhythmStartsAtBeatOneButCanMove() throws {
        var chart = Chart.blank(title: "Rhythm Chords", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)

        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "C", to: measureID, atFraction: 0.72))

        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
        let insertedChord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(insertedChord.startPosition.displayText, "1")
        XCTAssertNil(insertedChord.mappedRhythmSlotIndex)

        XCTAssertTrue(chart.moveChordEvent(chordID, to: measureID, atFraction: 0.68))

        let movedChord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(movedChord.startPosition.displayText, "3&")
        XCTAssertNil(movedChord.mappedRhythmSlotIndex)
    }

    func testSimpleChordSheetSecondChordAutomaticallyStartsAtBeatThree() throws {
        var chart = Chart.blank(title: "Simple Chords", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let firstSymbol = ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)
        let secondSymbol = ChordSymbol(root: .f, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)

        XCTAssertTrue(chart.appendRecognizedChord(firstSymbol, rawInput: "C", to: measureID, atFraction: 0.72))
        XCTAssertTrue(chart.appendRecognizedChord(secondSymbol, rawInput: "F", to: measureID, atFraction: 0.08))

        let chords = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents)
        XCTAssertEqual(chords.map(\.startPosition.displayText), ["1", "3"])
        XCTAssertTrue(chords.allSatisfy { $0.mappedRhythmSlotIndex == nil })
    }

    func testSimpleChordSheetAppendAfterExistingLaterBeatKeepsWrittenOrder() throws {
        var chart = Chart.blank(title: "Simple Chords", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let firstSymbol = try ChordSymbolParser.parse("C-7")
        let secondSymbol = try ChordSymbolParser.parse("D-7")

        XCTAssertTrue(chart.appendRecognizedChord(firstSymbol, rawInput: "C-7", to: measureID, atFraction: 0.05))
        let firstChordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
        XCTAssertTrue(chart.moveChordEvent(firstChordID, to: measureID, atFraction: 0.62))
        XCTAssertTrue(chart.appendRecognizedChord(secondSymbol, rawInput: "D-7", to: measureID, atFraction: 0.86))

        let chords = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents)
        XCTAssertEqual(chords.map(\.rawInput), ["C-7", "D-7"])
        XCTAssertEqual(chords.map(\.startPosition.displayText), ["3&", "4"])
        XCTAssertTrue(chords.allSatisfy { $0.mappedRhythmSlotIndex == nil })
    }

    func testSimpleChordSheetMoveSnapsChordToRequestedPlacementSubdivisionWithoutChangingSizeManually() throws {
        var chart = Chart.blank(title: "Simple Chords", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = ChordSymbol(root: .f, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)
        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "F", to: measureID, atFraction: 0.03))
        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)

        XCTAssertTrue(chart.moveChordEvent(chordID, to: measureID, atFraction: 0.68))

        let movedChord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(movedChord.id, chordID)
        XCTAssertEqual(movedChord.startPosition.displayText, "3&")
        XCTAssertEqual(movedChord.duration, .quarter)
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
                lane: .chartArea,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                measureRelativeFrame: FreehandSymbolMeasureFrame(offsetX: 10, offsetY: 12, width: 30, height: 18),
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

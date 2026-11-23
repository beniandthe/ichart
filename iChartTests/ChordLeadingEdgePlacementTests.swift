import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class ChordLeadingEdgePlacementTests: XCTestCase {
    func testVisualMovementStartsAtContentEdgeWhileBeatOneGuideKeepsItsInset() {
        let reference = CGRect(x: 100, y: 200, width: 300, height: 40)
        let movement = LeadSheetChordPlacementGuidePolicy.visualMovementFrame(
            referenceFrame: reference, leadingRepeatMarkerMaxX: nil, meterChangeFrame: nil)
        let guides = LeadSheetChordPlacementGuidePolicy.guideFrame(
            referenceFrame: reference, leadingRepeatMarkerMaxX: nil, meterChangeFrame: nil)

        XCTAssertEqual(movement, reference)
        XCTAssertEqual(guides.minX, reference.minX + 12, accuracy: 0.0001)
        XCTAssertEqual(guides.maxX, reference.maxX, accuracy: 0.0001)
        XCTAssertEqual(LeadSheetChordPlacementGuidePolicy.guideXs(
            for: Meter(numerator: 4, denominator: 4), in: guides).first,
            guides.minX)
    }

    func testDragCanReachLeadingContentEdgeWithoutChangingLegacyResolverCallers() {
        let reference = CGRect(x: 100, y: 200, width: 300, height: 40)
        let meter = Meter(numerator: 4, denominator: 4)
        let guides = LeadSheetChordPlacementGuidePolicy.guideFrame(
            referenceFrame: reference, leadingRepeatMarkerMaxX: nil, meterChangeFrame: nil)
        let movement = LeadSheetChordPlacementGuidePolicy.visualMovementFrame(
            referenceFrame: reference, leadingRepeatMarkerMaxX: nil, meterChangeFrame: nil)

        for scale in [CGFloat(0.5), 1, 2] {
            for distanceFromEdge in [CGFloat(0), 1] {
                let rawFraction = Double(distanceFromEdge / reference.width)
                let resolved = LeadSheetChordPlacementGuidePolicy.resolvedDragFraction(
                    rawFraction: rawFraction, initialX: guides.minX,
                    screenPointsPerDisplayedPoint: scale, referenceFrame: reference,
                    guideFrame: guides, meter: meter, visualMovementFrame: movement)
                XCTAssertEqual(reference.minX + reference.width * CGFloat(resolved.fraction),
                    reference.minX + distanceFromEdge, accuracy: 0.0001)
                XCTAssertNil(resolved.activeGuideX,
                    "Moving left from beat one must not snap straight back to that same guide")
            }
        }

        let legacy = LeadSheetChordPlacementGuidePolicy.resolvedDragFraction(
            rawFraction: 0, initialX: guides.minX, screenPointsPerDisplayedPoint: 1,
            referenceFrame: reference, guideFrame: guides, meter: meter)
        XCTAssertEqual(reference.minX + reference.width * CGFloat(legacy.fraction), guides.minX,
            accuracy: 0.0001, "Direct callers without the new movement frame retain their bounds")
    }

    func testVisualMovementStillReservesLeadingRepeatAndMeterArtifacts() {
        let reference = CGRect(x: 100, y: 200, width: 300, height: 40)
        let meterFrame = CGRect(x: 108, y: 200, width: 35, height: 40)
        let reservations: [(CGFloat?, CGRect?, CGFloat)] = [
            (136, nil, 142),
            (nil, meterFrame, 149),
            (136, meterFrame, 149)
        ]
        for (repeatMaxX, meterChange, expectedMinX) in reservations {
            let movement = LeadSheetChordPlacementGuidePolicy.visualMovementFrame(
                referenceFrame: reference, leadingRepeatMarkerMaxX: repeatMaxX,
                meterChangeFrame: meterChange)
            let guides = LeadSheetChordPlacementGuidePolicy.guideFrame(
                referenceFrame: reference, leadingRepeatMarkerMaxX: repeatMaxX,
                meterChangeFrame: meterChange)
            let resolved = LeadSheetChordPlacementGuidePolicy.resolvedDragFraction(
                rawFraction: -0.5, initialX: guides.minX, screenPointsPerDisplayedPoint: 1,
                referenceFrame: reference, guideFrame: guides,
                meter: Meter(numerator: 4, denominator: 4), visualMovementFrame: movement)

            XCTAssertEqual(movement.minX, expectedMinX, accuracy: 0.0001)
            XCTAssertEqual(reference.minX + reference.width * CGFloat(resolved.fraction), expectedMinX,
                accuracy: 0.0001)
            XCTAssertEqual(movement.maxX, reference.maxX, accuracy: 0.0001)
        }
    }

    func testManualLeadingPlacementSavesAndReopensInBothStylesWithoutChangingMusicalOrInkFields() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for width in [CGFloat(820), 1180] {
                let seed = try fixture(style: style)
                let initial = try measureLayout(for: seed.chart, id: seed.measureID, width: width)
                let originalEvent = try XCTUnwrap(seed.chart.chordEvent(id: seed.chordID))
                let originalEventJSON = try jsonObject(originalEvent)
                let originalChartKeys = Set(try jsonObject(seed.chart).keys)

                for distanceFromEdge in [CGFloat(0), 1] {
                    var chart = seed.chart
                    let fraction = Double(distanceFromEdge / initial.chordBandFrame.width)
                    XCTAssertTrue(chart.moveChordEventInCommittedChordLane(seed.chordID,
                        to: seed.measureID, atFraction: 0, visualFraction: fraction,
                        preserveMusicalPlacement: true, allowsLeadingVisualInset: true))
                    let moved = try XCTUnwrap(chart.chordEvent(id: seed.chordID))
                    var expectedEvent = originalEvent
                    expectedEvent.manualVisualLaneFraction = fraction
                    expectedEvent.manualVisualAllowsLeadingInset = true
                    XCTAssertEqual(moved, expectedEvent,
                        "Only manual visual placement may change; beat, duration and source receipt stay intact")
                    XCTAssertEqual(moved.sourceInkData, Data([0x31, 0x57, 0x92]))

                    var movedJSON = try jsonObject(moved)
                    let encodedFraction = try XCTUnwrap(
                        movedJSON.removeValue(forKey: "manualVisualLaneFraction") as? Double)
                    XCTAssertEqual(encodedFraction, fraction, accuracy: 1e-12)
                    XCTAssertEqual(movedJSON.removeValue(forKey: "manualVisualAllowsLeadingInset") as? Bool, true)
                    XCTAssertEqual(movedJSON as NSDictionary, originalEventJSON as NSDictionary)
                    XCTAssertEqual(Set(try jsonObject(chart).keys), originalChartKeys,
                        "The change must not add chart schema fields")

                    let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                        from: ChartPersistenceCoders.encoder.encode(chart))
                    XCTAssertEqual(reopened, chart)
                    let displayed = try measureLayout(for: reopened, id: seed.measureID, width: width)
                    let chord = try XCTUnwrap(displayed.chordLayouts.first { $0.id == seed.chordID })
                    let guide = LeadSheetChordPlacementGuidePolicy.guideFrame(
                        for: displayed, referenceFrame: displayed.chordBandFrame)
                    let movement = LeadSheetChordPlacementGuidePolicy.visualMovementFrame(
                        for: displayed, referenceFrame: displayed.chordBandFrame)
                    XCTAssertEqual(displayed.chordBandFrame, initial.chordBandFrame)
                    XCTAssertEqual(movement.minX, displayed.chordBandFrame.minX, accuracy: 0.0001)
                    XCTAssertEqual(chord.frame.minX, movement.minX + distanceFromEdge, accuracy: 0.0001)
                    XCTAssertLessThan(chord.frame.minX, guide.minX)
                    XCTAssertGreaterThan(chord.frame.minX, displayed.leadingBarlineX)
                    XCTAssertTrue(chord.usesManualVisualPlacement)
                    XCTAssertEqual(chord.frame.minX, chord.fitFrame.minX, accuracy: 0.0001)
                }
            }
        }
    }

    func testActualRepeatAndMeterLayoutsKeepLeadingVisualOverridesOutsideReservedArtifacts() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for (hasRepeat, hasMeter) in [(true, false), (false, true), (true, true)] {
                var seed = try fixture(style: style)
                let ids = seed.chart.measures.map(\.id)
                if hasRepeat {
                    _ = try XCTUnwrap(seed.chart.addRepeatSpan(startMeasureID: ids[1], endMeasureID: ids[2]))
                }
                if hasMeter {
                    _ = try XCTUnwrap(seed.chart.applyMeterChange(Meter(numerator: 3, denominator: 4),
                        startingAt: seed.measureID, scope: .toEndOfPiece))
                }
                XCTAssertTrue(seed.chart.moveChordEventInCommittedChordLane(seed.chordID,
                    to: seed.measureID, atFraction: 0, visualFraction: 0,
                    preserveMusicalPlacement: true, allowsLeadingVisualInset: true))
                let displayed = try measureLayout(for: seed.chart, id: seed.measureID)
                let chord = try XCTUnwrap(displayed.chordLayouts.first { $0.id == seed.chordID })
                let movement = LeadSheetChordPlacementGuidePolicy.visualMovementFrame(
                    for: displayed, referenceFrame: displayed.chordBandFrame)
                XCTAssertEqual(chord.frame.minX, movement.minX, accuracy: 0.0001)
                if hasRepeat {
                    let repeatMaxX = try XCTUnwrap(displayed.repeatMarkerLayouts
                        .filter { $0.edge == .leading }.map(\.occupiedFrame.maxX).max())
                    XCTAssertGreaterThanOrEqual(chord.frame.minX + 0.0001,
                        repeatMaxX + LeadSheetChordPlacementGuidePolicy.artifactGap)
                }
                if hasMeter {
                    let meter = try XCTUnwrap(displayed.meterChangeFrame)
                    XCTAssertGreaterThanOrEqual(chord.frame.minX + 0.0001,
                        meter.maxX + LeadSheetChordPlacementGuidePolicy.artifactGap)
                }
            }
        }
    }

    func testFirstRhythmMeasureCannotMoveIntoClefKeyOrTimeSignatureGutter() throws {
        var seed = try fixture(style: .rhythmSectionSheet, targetIndex: 0, key: .dMajor)
        XCTAssertTrue(seed.chart.moveChordEventInCommittedChordLane(seed.chordID,
            to: seed.measureID, atFraction: 0, visualFraction: 0,
            preserveMusicalPlacement: true, allowsLeadingVisualInset: true))
        let page = LeadSheetPageLayoutEngine.pageLayout(for: seed.chart,
            pageSize: CGSize(width: 900, height: 1400))
        let system = try XCTUnwrap(page.systems.first)
        let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == seed.measureID })
        let clef = try XCTUnwrap(system.clefFrame)
        let time = try XCTUnwrap(system.timeSignatureFrame)
        XCTAssertFalse(system.keySignatureLayouts.isEmpty)
        let signatureMaxX = ([clef.maxX, time.maxX] + system.keySignatureLayouts.map(\.frame.maxX)).max()!
        let chord = try XCTUnwrap(measure.chordLayouts.first { $0.id == seed.chordID })
        XCTAssertGreaterThanOrEqual(measure.staffFrame.minX, signatureMaxX)
        XCTAssertEqual(chord.frame.minX, measure.chordBandFrame.minX, accuracy: 0.0001)
        XCTAssertGreaterThan(chord.frame.minX, signatureMaxX)
    }

    func testOrdinaryDownbeatPlacementKeepsGuideInsetAndNeedsExplicitVisualOverrideToMoveLeft() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let seed = try fixture(style: style)
            let event = try XCTUnwrap(seed.chart.chordEvent(id: seed.chordID))
            XCTAssertEqual(event.startPosition, BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1))
            XCTAssertNil(event.manualVisualLaneFraction)
            let initial = try measureLayout(for: seed.chart, id: seed.measureID)
            let defaultChord = try XCTUnwrap(initial.chordLayouts.first { $0.id == seed.chordID })
            let guides = LeadSheetChordPlacementGuidePolicy.guideFrame(
                for: initial, referenceFrame: initial.chordBandFrame)
            XCTAssertEqual(guides.minX, initial.chordBandFrame.minX + 12, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(defaultChord.frame.minX, guides.minX - 0.0001)
            XCTAssertEqual(initial.chordBandFrame.minX - initial.leadingBarlineX,
                style == .simpleChordSheet ? 1 : 3, accuracy: 0.0001)
            if style == .simpleChordSheet {
                XCTAssertEqual(defaultChord.frame.minX, guides.minX, accuracy: 0.0001)
            }
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(seed.chart))
            let reopenedMeasure = try measureLayout(for: reopened, id: seed.measureID)
            XCTAssertEqual(reopenedMeasure.chordLayouts.first { $0.id == seed.chordID }, defaultChord)
        }
    }

    func testLegacyAutomaticLeadingFractionKeepsOldGuideClampAndOmitsNewIntentFieldOnReencode() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var seed = try fixture(style: style)
            seed.chart.systems[0].measures[1].chordEvents[0].manualVisualLaneFraction = 0
            let event = try XCTUnwrap(seed.chart.chordEvent(id: seed.chordID))
            XCTAssertNil(event.manualVisualAllowsLeadingInset)
            let originalJSON = try jsonObject(event)
            XCTAssertNil(originalJSON["manualVisualAllowsLeadingInset"])

            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(seed.chart))
            let reopenedEvent = try XCTUnwrap(reopened.chordEvent(id: seed.chordID))
            XCTAssertNil(reopenedEvent.manualVisualAllowsLeadingInset)
            XCTAssertEqual(try jsonObject(reopenedEvent) as NSDictionary, originalJSON as NSDictionary,
                "Old automatic placement must not acquire a manual movement intent during decoding")
            let displayed = try measureLayout(for: reopened, id: seed.measureID)
            let guide = LeadSheetChordPlacementGuidePolicy.guideFrame(
                for: displayed, referenceFrame: displayed.chordBandFrame)
            let chord = try XCTUnwrap(displayed.chordLayouts.first { $0.id == seed.chordID })
            XCTAssertEqual(chord.frame.minX, guide.minX, accuracy: 0.0001,
                "Existing automatic chords with a raw leading fraction retain their old rendered position")
        }
    }

    private func fixture(style: ChartLayoutStyle, targetIndex: Int = 1,
                         key: DocumentKey = .cMajor) throws -> (chart: Chart, measureID: UUID, chordID: UUID) {
        var chart = Chart.blank(title: "Leading chord placement", key: key, measureCount: 4, layoutStyle: style)
        let measureID = chart.measures[targetIndex].id
        let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("G7"),
            rawInput: "G7", to: measureID, atFraction: 0,
            sourceInkData: Data([0x31, 0x57, 0x92]), sourceCandidateSignature: ["G7", "G"]))
        return (chart, measureID, chordID)
    }

    private func measureLayout(for chart: Chart, id: UUID, width: CGFloat = 900) throws -> LeadSheetMeasureLayout {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: width, height: 1400))
        return try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: ChartPersistenceCoders.encoder.encode(value)) as? [String: Any])
    }
}

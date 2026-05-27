import XCTest
@testable import SmartChart

final class MeasureRhythmMappingTests: XCTestCase {
    func testSingleChordAtMeasureStartWithoutRhythmMapAutoFillsMeasure() {
        let meter = Meter(numerator: 3, denominator: 4)
        let measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .c, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
                    duration: .quarter,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: nil
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let placements = measure.renderedChordPlacements(defaultMeter: meter)

        XCTAssertEqual(placements.count, 1)
        XCTAssertTrue(placements[0].isAutoFill)
        XCTAssertEqual(placements[0].startPosition.beat, 1)
        XCTAssertEqual(placements[0].durationDisplayText, "whole measure")
        XCTAssertEqual(placements[0].effectiveWholeNoteLength, meter.measureLengthInWholeNotes)
    }

    func testSingleChordWithoutRhythmMapHonorsWrittenBeatWhenNotAtMeasureStart() {
        let meter = Meter(numerator: 4, denominator: 4)
        let measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .c, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 3, subdivision: 0, subdivisionsPerBeat: 1),
                    duration: .quarter,
                    rhythmPlacement: .aboveChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: nil
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let placements = measure.renderedChordPlacements(defaultMeter: meter)

        XCTAssertEqual(placements.count, 1)
        XCTAssertFalse(placements[0].isAutoFill)
        XCTAssertEqual(placements[0].startPosition.displayText, "3")
        XCTAssertEqual(placements[0].durationDisplayText, "quarter")
    }

    func testRhythmMapResolvesAndSnapsChordPlacements() {
        let meter = Meter(numerator: 4, denominator: 4)
        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [
                demoChord(root: .c),
                demoChord(root: .f),
                demoChord(root: .g)
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )
        measure.setRhythmMap([.quarter, .quarter, .half])

        let placements = measure.renderedChordPlacements(defaultMeter: meter)

        XCTAssertEqual(placements.map(\.startPosition.displayText), ["1", "2", "3"])
        XCTAssertEqual(placements.map(\.durationDisplayText), ["quarter", "quarter", "half"])
        XCTAssertTrue(placements.allSatisfy { $0.isRhythmMapped })
    }

    func testExplicitRhythmSlotAssignmentPinsChordToChosenSlot() throws {
        let meter = Meter(numerator: 4, denominator: 4)
        let firstChord = demoChord(root: .c)
        var secondChord = demoChord(root: .g)
        secondChord.mappedRhythmSlotIndex = 2

        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [firstChord, secondChord],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )
        measure.setRhythmMap([.quarter, .quarter, .half])

        let placements = measure.renderedChordPlacements(defaultMeter: meter)
        let firstPlacement = try XCTUnwrap(placements.first(where: { $0.chordEvent.id == firstChord.id }))
        let secondPlacement = try XCTUnwrap(placements.first(where: { $0.chordEvent.id == secondChord.id }))

        XCTAssertEqual(firstPlacement.resolvedRhythmSlotIndex, 0)
        XCTAssertFalse(firstPlacement.isExplicitRhythmSlotAssignment)
        XCTAssertEqual(secondPlacement.resolvedRhythmSlotIndex, 2)
        XCTAssertTrue(secondPlacement.isExplicitRhythmSlotAssignment)
        XCTAssertEqual(secondPlacement.startPosition.displayText, "3")
    }

    func testRhythmMapInvalidatesWhenMeterNoLongerMatches() {
        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [demoChord(root: .c), demoChord(root: .f)],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )
        measure.setRhythmMap([.quarter, .quarter, .quarter, .quarter])

        XCTAssertNil(measure.resolvedRhythmSlots(defaultMeter: Meter(numerator: 3, denominator: 4)))

        let issues = MeasureTimingValidator.issues(
            in: measure,
            defaultMeter: Meter(numerator: 3, denominator: 4)
        )

        XCTAssertTrue(issues.contains(where: { $0.kind == .invalidRhythmMap }))
    }

    func testRhythmMapStatusReportsUnderfilledAndOverflowBeats() {
        let meter = Meter(numerator: 4, denominator: 4)

        let underfilled = MeasureRhythmMap(values: [.half])
        let overflow = MeasureRhythmMap(values: [.whole, .quarter])

        XCTAssertEqual(underfilled.status(for: meter), .underfilled(2))
        XCTAssertEqual(overflow.status(for: meter), .overflow(1))
    }

    func testSuggestedChordInsertionUsesNextOpenRhythmSlot() {
        let meter = Meter(numerator: 4, denominator: 4)
        var secondChord = demoChord(root: .f)
        secondChord.mappedRhythmSlotIndex = 1

        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [demoChord(root: .c), secondChord],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )
        measure.setRhythmMap([.quarter, .quarter, .half])

        let suggestion = measure.suggestedChordInsertion(defaultMeter: meter)

        XCTAssertEqual(suggestion.mappedRhythmSlotIndex, 2)
        XCTAssertEqual(suggestion.startPosition.displayText, "3")
        XCTAssertEqual(suggestion.duration, .half)
    }

    func testSuggestedChordInsertionAtFractionUsesNearestAvailableRhythmSlot() {
        let meter = Meter(numerator: 4, denominator: 4)
        var occupiedChord = demoChord(root: .c)
        occupiedChord.mappedRhythmSlotIndex = 1

        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [occupiedChord],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )
        measure.setRhythmMap([.quarter, .quarter, .half])

        let suggestion = measure.suggestedChordInsertion(atFraction: 0.70, defaultMeter: meter)

        XCTAssertEqual(suggestion.mappedRhythmSlotIndex, 2)
        XCTAssertEqual(suggestion.startPosition.displayText, "3")
        XCTAssertEqual(suggestion.duration, .half)
    }

    func testSuggestedChordInsertionAtFractionUsesRhythmSlotAttackForLongSlots() {
        let meter = Meter(numerator: 4, denominator: 4)
        let measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            rhythmMap: MeasureRhythmMap(values: [.quarter, .quarter, .half]),
            barlineAfter: .single,
            chordEvents: [],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let suggestion = measure.suggestedChordInsertion(atFraction: 0.52, defaultMeter: meter)

        XCTAssertEqual(suggestion.mappedRhythmSlotIndex, 2)
        XCTAssertEqual(suggestion.startPosition.displayText, "3")
        XCTAssertEqual(suggestion.duration, .half)
    }

    func testSuggestedChordInsertionExcludingChordKeepsCurrentSlotAvailable() {
        let meter = Meter(numerator: 4, denominator: 4)
        let firstChord = demoChord(root: .c)
        let secondChord = demoChord(root: .f)

        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [firstChord, secondChord],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )
        measure.setRhythmMap([.quarter, .quarter, .half])

        let suggestion = measure.suggestedChordInsertion(
            atFraction: 0.08,
            defaultMeter: meter,
            excluding: firstChord.id
        )

        XCTAssertEqual(suggestion.mappedRhythmSlotIndex, 0)
        XCTAssertEqual(suggestion.startPosition.displayText, "1")
    }

    func testSuggestedChordInsertionUsesNextOpenDownbeatWithoutRhythmMap() {
        let meter = Meter(numerator: 4, denominator: 4)
        var firstChord = demoChord(root: .c)
        firstChord.startPosition = BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2)
        var secondChord = demoChord(root: .f)
        secondChord.startPosition = BeatPosition(beat: 3, subdivision: 0, subdivisionsPerBeat: 2)

        let measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [firstChord, secondChord],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let suggestion = measure.suggestedChordInsertion(defaultMeter: meter)

        XCTAssertNil(suggestion.mappedRhythmSlotIndex)
        XCTAssertEqual(suggestion.startPosition.displayText, "2")
        XCTAssertEqual(suggestion.duration, .quarter)
    }

    func testSuggestedChordInsertionAtFractionQuantizesToNearestBeatWithoutRhythmMap() {
        let meter = Meter(numerator: 4, denominator: 4)
        let measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let suggestion = measure.suggestedChordInsertion(atFraction: 0.61, defaultMeter: meter)

        XCTAssertNil(suggestion.mappedRhythmSlotIndex)
        XCTAssertEqual(suggestion.startPosition.displayText, "3")
        XCTAssertEqual(suggestion.startPosition.subdivisionsPerBeat, 1)
        XCTAssertEqual(suggestion.duration, .quarter)
    }

    func testSuggestedChordInsertionAtLeadingEdgeSnapsToFirstBeatWithoutRhythmMap() {
        let meter = Meter(numerator: 4, denominator: 4)
        let measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let suggestion = measure.suggestedChordInsertion(atFraction: 0.03, defaultMeter: meter)

        XCTAssertNil(suggestion.mappedRhythmSlotIndex)
        XCTAssertEqual(suggestion.startPosition.displayText, "1")
        XCTAssertEqual(suggestion.startPosition.subdivisionsPerBeat, 1)
        XCTAssertEqual(suggestion.duration, .quarter)
    }

    func testAppendChordEventUsesSuggestedMappedPlacement() throws {
        let meter = Meter(numerator: 4, denominator: 4)
        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [demoChord(root: .c)],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )
        measure.setRhythmMap([.quarter, .quarter, .half])

        measure.appendChordEvent(
            symbol: ChordSymbol(root: .g, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
            rawInput: "G7",
            defaultMeter: meter
        )

        let appended = try XCTUnwrap(measure.chordEvents.last)
        XCTAssertEqual(appended.mappedRhythmSlotIndex, 1)
        XCTAssertEqual(appended.startPosition.displayText, "2")
        XCTAssertEqual(appended.rhythmPlacement, .aboveChord)
    }

    func testAppendChordEventUsesExplicitPositionalSuggestion() throws {
        let suggestion = MeasureChordInsertionSuggestion(
            startPosition: BeatPosition(beat: 4, subdivision: 1, subdivisionsPerBeat: 2),
            duration: .quarter,
            mappedRhythmSlotIndex: nil
        )
        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        measure.appendChordEvent(
            symbol: ChordSymbol(root: .a, accidental: .flat, quality: "maj7", extensions: [], alterations: [], slashBass: nil),
            rawInput: "Abmaj7",
            suggestion: suggestion
        )

        let appended = try XCTUnwrap(measure.chordEvents.last)
        XCTAssertEqual(appended.startPosition.displayText, "4&")
        XCTAssertEqual(appended.mappedRhythmSlotIndex, nil)
        XCTAssertEqual(appended.rhythmPlacement, .inline)
    }

    private func demoChord(root: ChordRoot) -> ChordEvent {
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

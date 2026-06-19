import XCTest
@testable import iChart

final class MeasureTimingValidatorTests: XCTestCase {
    func testDetectsOverlappingChordEvents() {
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
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .half,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: nil
                ),
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .f, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 2, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .half,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: nil
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let issues = MeasureTimingValidator.issues(in: measure, defaultMeter: meter)

        XCTAssertTrue(issues.contains(where: { $0.kind == .overlappingEvents }))
    }

    func testDetectsChordThatRunsPastMeasureEnd() {
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
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .quarter,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: nil
                ),
                ChordEvent(
                    id: UUID(),
                    symbol: ChordSymbol(root: .g, accidental: .natural, quality: "13", extensions: [], alterations: [], slashBass: nil),
                    startPosition: BeatPosition(beat: 4, subdivision: 0, subdivisionsPerBeat: 2),
                    duration: .half,
                    rhythmPlacement: .belowChord,
                    tieOut: false,
                    hitStyle: .none,
                    rawInput: nil
                )
            ],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )

        let issues = MeasureTimingValidator.issues(in: measure, defaultMeter: meter)

        XCTAssertTrue(issues.contains(where: { $0.kind == .eventExceedsMeasure }))
    }

    func testDetectsConflictingExplicitRhythmSlotAssignments() {
        let meter = Meter(numerator: 4, denominator: 4)
        var firstChord = ChordEvent(
            id: UUID(),
            symbol: ChordSymbol(root: .c, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
            duration: .quarter,
            rhythmPlacement: .belowChord,
            tieOut: false,
            hitStyle: .none,
            rawInput: nil
        )
        var secondChord = ChordEvent(
            id: UUID(),
            symbol: ChordSymbol(root: .f, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
            startPosition: BeatPosition(beat: 2, subdivision: 0, subdivisionsPerBeat: 2),
            duration: .quarter,
            rhythmPlacement: .belowChord,
            tieOut: false,
            hitStyle: .none,
            rawInput: nil
        )
        firstChord.mappedRhythmSlotIndex = 1
        secondChord.mappedRhythmSlotIndex = 1

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

        let issues = MeasureTimingValidator.issues(in: measure, defaultMeter: meter)

        XCTAssertTrue(issues.contains(where: { $0.kind == .conflictingRhythmSlotAssignment }))
    }

    func testDetectsStaleRhythmSlotAssignmentAfterBeatMapChanges() {
        let meter = Meter(numerator: 4, denominator: 4)
        var chord = ChordEvent(
            id: UUID(),
            symbol: ChordSymbol(root: .c, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
            duration: .quarter,
            rhythmPlacement: .belowChord,
            tieOut: false,
            hitStyle: .none,
            rawInput: nil
        )
        chord.mappedRhythmSlotIndex = 3

        var measure = Measure(
            id: UUID(),
            index: 1,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: .single,
            chordEvents: [chord],
            cueTextIDs: [],
            roadmapObjectIDs: []
        )
        measure.setRhythmMap([.half, .half])

        let issues = MeasureTimingValidator.issues(in: measure, defaultMeter: meter)

        XCTAssertTrue(issues.contains(where: { $0.kind == .staleRhythmSlotAssignment }))
    }
}

import Foundation

struct MeasureTimingIssue: Identifiable, Hashable {
    enum Kind: Hashable {
        case invalidStartPosition
        case eventExceedsMeasure
        case overlappingEvents
        case invalidRhythmMap
        case excessChordsForRhythmMap
        case conflictingRhythmSlotAssignment
        case staleRhythmSlotAssignment
    }

    var id = UUID()
    var kind: Kind
    var measureID: UUID
    var chordEventID: UUID?
    var message: String
}

enum MeasureTimingValidator {
    static func issues(in measure: Measure, defaultMeter: Meter) -> [MeasureTimingIssue] {
        let meter = measure.resolvedMeter(defaultMeter: defaultMeter)
        let measureCapacity = meter.measureLengthInWholeNotes
        var issues: [MeasureTimingIssue] = []

        if measure.rhythmMap != nil,
           let resolvedSlots = measure.resolvedRhythmSlots(defaultMeter: defaultMeter) {
            let validRhythmSlotIndices = Set(resolvedSlots.indices)
            let explicitAssignments = measure.chordEvents.compactMap { event -> (ChordEvent, Int)? in
                guard let mappedRhythmSlotIndex = event.mappedRhythmSlotIndex else {
                    return nil
                }

                return (event, mappedRhythmSlotIndex)
            }

            for (event, mappedRhythmSlotIndex) in explicitAssignments where !validRhythmSlotIndices.contains(mappedRhythmSlotIndex) {
                issues.append(
                    MeasureTimingIssue(
                        kind: .staleRhythmSlotAssignment,
                        measureID: measure.id,
                        chordEventID: event.id,
                        message: "Chord \(event.symbol.displayText) is tied to a rhythm position that changed."
                    )
                )
            }

            let assignmentCounts = Dictionary(
                grouping: explicitAssignments.filter { validRhythmSlotIndices.contains($0.1) },
                by: { $0.1 }
            )

            for (slotIndex, assignments) in assignmentCounts where assignments.count > 1 {
                let slot = resolvedSlots[slotIndex]
                issues.append(
                    MeasureTimingIssue(
                        kind: .conflictingRhythmSlotAssignment,
                        measureID: measure.id,
                        chordEventID: assignments.last?.0.id,
                        message: "More than one chord is tied to rhythm position \(slotIndex + 1) (\(slot.startPosition.displayText) · \(slot.duration.displayText))."
                    )
                )
            }

            if measure.chordEvents.count > resolvedSlots.count {
                issues.append(
                    MeasureTimingIssue(
                        kind: .excessChordsForRhythmMap,
                        measureID: measure.id,
                        chordEventID: measure.chordEvents.dropFirst(resolvedSlots.count).first?.id,
                        message: "This rhythm has \(resolvedSlots.count) chord position\(resolvedSlots.count == 1 ? "" : "s"), so extra chords will not snap cleanly."
                    )
                )
            }
        } else if measure.rhythmMap != nil {
            issues.append(
                MeasureTimingIssue(
                    kind: .invalidRhythmMap,
                    measureID: measure.id,
                    chordEventID: nil,
                    message: "The rhythm sketch does not add up to \(meter.displayText), so it stays inactive until it fits the full measure."
                )
            )
        }

        let sortedPlacements = measure.renderedChordPlacements(defaultMeter: defaultMeter).sorted {
            offset(for: $0.startPosition, meter: meter) < offset(for: $1.startPosition, meter: meter)
        }
        var previousPlacementEnd: Double?

        for placement in sortedPlacements {
            guard let startOffset = placement.startPosition.startOffset(in: meter) else {
                issues.append(
                    MeasureTimingIssue(
                        kind: .invalidStartPosition,
                        measureID: measure.id,
                        chordEventID: placement.chordEvent.id,
                        message: "Chord \(placement.chordEvent.symbol.displayText) has an invalid beat position for \(meter.displayText)."
                    )
                )
                continue
            }

            let eventEnd = startOffset + placement.effectiveWholeNoteLength

            if eventEnd > measureCapacity + 0.0001 {
                issues.append(
                    MeasureTimingIssue(
                        kind: .eventExceedsMeasure,
                        measureID: measure.id,
                        chordEventID: placement.chordEvent.id,
                        message: "Chord \(placement.chordEvent.symbol.displayText) runs past the end of the measure."
                    )
                )
            }

            if let previousPlacementEnd,
               startOffset < previousPlacementEnd - 0.0001 {
                issues.append(
                    MeasureTimingIssue(
                        kind: .overlappingEvents,
                        measureID: measure.id,
                        chordEventID: placement.chordEvent.id,
                        message: "Chord \(placement.chordEvent.symbol.displayText) overlaps a previous chord event."
                    )
                )
            }

            previousPlacementEnd = max(previousPlacementEnd ?? 0, eventEnd)
        }

        return issues
    }

    private static func offset(for beatPosition: BeatPosition, meter: Meter) -> Double {
        beatPosition.startOffset(in: meter) ?? .greatestFiniteMagnitude
    }
}

import Foundation

struct MeasureRhythmMap: Codable, Hashable {
    var values: [RhythmValue]
    var drawingData: Data? = nil

    var totalWholeNoteLength: Double {
        values.reduce(0) { $0 + $1.wholeNoteLength }
    }

    func totalWholeNoteLength(in meter: Meter) -> Double {
        values.reduce(0) { $0 + $1.wholeNoteLength(in: meter) }
    }

    func status(for meter: Meter) -> MeasureRhythmMapStatus {
        guard !values.isEmpty else {
            return .empty
        }

        let resolvedTotalLength = totalWholeNoteLength(in: meter)
        let delta = resolvedTotalLength - meter.measureLengthInWholeNotes

        if abs(delta) < 0.0001 {
            return resolvedSlots(for: meter) == nil
                ? .invalidSubdivision
                : .exact
        }

        let beatDelta = abs(delta) / meter.beatUnitWholeNoteLength
        return delta < 0 ? .underfilled(beatDelta) : .overflow(beatDelta)
    }

    func fitsExactly(in meter: Meter) -> Bool {
        if case .exact = status(for: meter) {
            return true
        }

        return false
    }

    func resolvedSlots(for meter: Meter) -> [MeasureRhythmSlot]? {
        guard !values.isEmpty,
              abs(totalWholeNoteLength(in: meter) - meter.measureLengthInWholeNotes) < 0.0001 else {
            return nil
        }

        var offset: Double = 0
        var slots: [MeasureRhythmSlot] = []

        for (index, value) in values.enumerated() {
            guard let startPosition = BeatPosition(offsetInWholeNotes: offset, meter: meter) else {
                return nil
            }

            slots.append(
                MeasureRhythmSlot(
                    index: index,
                    startPosition: startPosition,
                    duration: value
                )
            )
            offset += value.wholeNoteLength(in: meter)
        }

        guard abs(offset - meter.measureLengthInWholeNotes) < 0.0001 else {
            return nil
        }

        return slots
    }
}

enum MeasureRhythmMapStatus: Hashable {
    case empty
    case underfilled(Double)
    case exact
    case overflow(Double)
    case invalidSubdivision
}

enum RhythmicNotationCompendium {
    static let supportedValues: Set<RhythmValue> = [
        .slash,
        .quarter,
        .half,
        .whole,
        .sixteenth,
        .sixteenthRest,
        .eighth,
        .dottedQuarter,
        .dottedHalf,
        .eighthRest,
        .quarterRest,
        .halfRest,
        .wholeRest
    ]

    static func accepts(_ values: [RhythmValue], in meter: Meter) -> Bool {
        guard !values.isEmpty,
              values.allSatisfy(supportedValues.contains) else {
            return false
        }

        let rhythmMap = MeasureRhythmMap(values: values)
        guard case .exact = rhythmMap.status(for: meter) else {
            return false
        }

        return rhythmMap.resolvedSlots(for: meter) != nil
    }
}

struct MeasureRhythmSlot: Identifiable, Hashable {
    let index: Int
    let startPosition: BeatPosition
    let duration: RhythmValue

    var id: Int { index }
    var isPlayable: Bool { !duration.isRest && duration != .tiedContinuation }
}

struct MeasureChordPlacement: Identifiable, Hashable {
    let chordEvent: ChordEvent
    let startPosition: BeatPosition
    let duration: RhythmValue?
    let effectiveWholeNoteLength: Double
    let durationDisplayText: String
    let resolvedRhythmSlotIndex: Int?
    let isRhythmMapped: Bool
    let isExplicitRhythmSlotAssignment: Bool
    let isAutoFill: Bool

    var id: UUID { chordEvent.id }
}

struct MeasureRhythmSlotOccupancy: Identifiable, Hashable {
    let slot: MeasureRhythmSlot
    let placements: [MeasureChordPlacement]

    var id: Int { slot.id }
    var primaryPlacement: MeasureChordPlacement? { placements.first }
    var hasConflict: Bool { placements.count > 1 }
}

struct MeasureChordInsertionSuggestion: Hashable {
    let startPosition: BeatPosition
    let duration: RhythmValue
    let mappedRhythmSlotIndex: Int?

    var isRhythmMapped: Bool {
        mappedRhythmSlotIndex != nil
    }
}

extension Measure {
    func resolvedRhythmSlots(defaultMeter: Meter) -> [MeasureRhythmSlot]? {
        rhythmMap?.resolvedSlots(for: resolvedMeter(defaultMeter: defaultMeter))
    }

    func rhythmSlotOccupancies(defaultMeter: Meter) -> [MeasureRhythmSlotOccupancy]? {
        guard let slots = resolvedRhythmSlots(defaultMeter: defaultMeter) else {
            return nil
        }

        let placementsBySlotIndex = Dictionary(grouping: renderedChordPlacements(defaultMeter: defaultMeter)) {
            $0.resolvedRhythmSlotIndex
        }

        return slots.map { slot in
            MeasureRhythmSlotOccupancy(
                slot: slot,
                placements: placementsBySlotIndex[.some(slot.index)] ?? []
            )
        }
    }

    func explicitlyAssignedRhythmSlotIndices(
        defaultMeter: Meter,
        excluding chordEventID: UUID? = nil
    ) -> Set<Int> {
        guard let slots = resolvedRhythmSlots(defaultMeter: defaultMeter) else {
            return []
        }

        let validIndices = Set(slots.indices.filter { slots[$0].isPlayable })
        return Set(
            chordEvents.compactMap { event in
                guard event.id != chordEventID,
                      let mappedRhythmSlotIndex = event.mappedRhythmSlotIndex,
                      validIndices.contains(mappedRhythmSlotIndex) else {
                    return nil
                }

                return mappedRhythmSlotIndex
            }
        )
    }

    func nextUnoccupiedRhythmSlotIndex(defaultMeter: Meter) -> Int? {
        guard let slots = resolvedRhythmSlots(defaultMeter: defaultMeter) else {
            return nil
        }

        let occupiedSlotIndices = Set(
            renderedChordPlacements(defaultMeter: defaultMeter).compactMap(\.resolvedRhythmSlotIndex)
        )
        return slots.indices.first {
            slots[$0].isPlayable && !occupiedSlotIndices.contains($0)
        }
    }

    func suggestedChordInsertion(
        defaultMeter: Meter,
        excluding chordEventID: UUID? = nil
    ) -> MeasureChordInsertionSuggestion {
        suggestedChordInsertion(
            atFraction: nil,
            defaultMeter: defaultMeter,
            excluding: chordEventID
        )
    }

    func suggestedChordInsertion(
        atFraction fraction: Double?,
        defaultMeter: Meter,
        excluding chordEventID: UUID? = nil
    ) -> MeasureChordInsertionSuggestion {
        let meter = resolvedMeter(defaultMeter: defaultMeter)
        let renderedPlacements = renderedChordPlacements(defaultMeter: defaultMeter)

        if let slots = resolvedRhythmSlots(defaultMeter: defaultMeter),
           !slots.isEmpty {
            let occupiedSlotIndices = Set(
                renderedPlacements
                    .filter { $0.chordEvent.id != chordEventID }
                    .compactMap(\.resolvedRhythmSlotIndex)
            )
            let candidateIndices = slots.indices.filter {
                slots[$0].isPlayable && !occupiedSlotIndices.contains($0)
            }
            let searchIndices = candidateIndices.isEmpty ? Array(slots.indices) : candidateIndices

            if let fraction,
               let resolvedIndex = nearestRhythmSlotIndex(
                    for: fraction,
                    among: searchIndices,
                    slots: slots,
                    meter: meter
               ),
               let slot = slots[safe: resolvedIndex] {
                return MeasureChordInsertionSuggestion(
                    startPosition: slot.startPosition,
                    duration: slot.duration,
                    mappedRhythmSlotIndex: resolvedIndex
                )
            }

            if let nextSlotIndex = candidateIndices.first ?? slots.indices.first,
               let slot = slots[safe: nextSlotIndex] {
                return MeasureChordInsertionSuggestion(
                    startPosition: slot.startPosition,
                    duration: slot.duration,
                    mappedRhythmSlotIndex: nextSlotIndex
                )
            }
        }

        if let fraction {
            let quantizedPosition = quantizedBeatPosition(
                for: fraction,
                meter: meter,
                subdivisionsPerBeat: 1
            )
            return MeasureChordInsertionSuggestion(
                startPosition: quantizedPosition,
                duration: .quarter,
                mappedRhythmSlotIndex: nil
            )
        }

        if let nextSlotIndex = nextUnoccupiedRhythmSlotIndex(defaultMeter: defaultMeter),
           let slot = resolvedRhythmSlots(defaultMeter: defaultMeter)?[safe: nextSlotIndex] {
            return MeasureChordInsertionSuggestion(
                startPosition: slot.startPosition,
                duration: slot.duration,
                mappedRhythmSlotIndex: nextSlotIndex
            )
        }

        let occupiedBeats = Set<Int>(
            chordEvents.compactMap { event in
                guard event.id != chordEventID,
                      event.startPosition.subdivision == 0 else {
                    return nil
                }

                return event.startPosition.beat
            }
        )
        let nextBeat = (1...max(1, meter.numerator)).first { !occupiedBeats.contains($0) }
            ?? min(max(1, meter.numerator), max(1, chordEvents.count + 1))

        return MeasureChordInsertionSuggestion(
            startPosition: BeatPosition(beat: nextBeat, subdivision: 0, subdivisionsPerBeat: 2),
            duration: .quarter,
            mappedRhythmSlotIndex: nil
        )
    }

    @discardableResult
    mutating func appendChordEvent(
        symbol: ChordSymbol,
        rawInput: String?,
        defaultMeter: Meter,
        hitStyle: HitStyle = .none
    ) -> UUID {
        let suggestion = suggestedChordInsertion(defaultMeter: defaultMeter)
        return appendChordEvent(
            symbol: symbol,
            rawInput: rawInput,
            suggestion: suggestion,
            hitStyle: hitStyle
        )
    }

    @discardableResult
    mutating func appendChordEvent(
        symbol: ChordSymbol,
        rawInput: String?,
        suggestion: MeasureChordInsertionSuggestion,
        hitStyle: HitStyle = .none,
        sourceInkData: Data? = nil,
        sourceCandidateSignature: [String] = []
    ) -> UUID {
        let chordEventID = UUID()
        chordEvents.append(
            ChordEvent(
                id: chordEventID,
                symbol: symbol,
                startPosition: suggestion.startPosition,
                duration: suggestion.duration,
                rhythmPlacement: suggestion.isRhythmMapped ? .aboveChord : .inline,
                mappedRhythmSlotIndex: suggestion.mappedRhythmSlotIndex,
                tieOut: false,
                hitStyle: hitStyle,
                rawInput: rawInput,
                sourceInkData: sourceInkData,
                sourceCandidateSignature: sourceCandidateSignature
            )
        )
        return chordEventID
    }

    private func nearestRhythmSlotIndex(
        for fraction: Double,
        among indices: [Int],
        slots: [MeasureRhythmSlot],
        meter: Meter
    ) -> Int? {
        let clampedFraction = min(max(fraction, 0), 0.9999)

        return indices.min { lhs, rhs in
            guard let lhsSlot = slots[safe: lhs],
                  let rhsSlot = slots[safe: rhs] else {
                return lhs < rhs
            }

            let lhsDistance = abs(slotAttackFraction(lhsSlot, meter: meter) - clampedFraction)
            let rhsDistance = abs(slotAttackFraction(rhsSlot, meter: meter) - clampedFraction)

            if abs(lhsDistance - rhsDistance) > 0.0001 {
                return lhsDistance < rhsDistance
            }

            return lhs < rhs
        }
    }

    private func slotAttackFraction(_ slot: MeasureRhythmSlot, meter: Meter) -> Double {
        slot.startPosition.startOffset(in: meter)
            .map { $0 / meter.measureLengthInWholeNotes }
            ?? 0
    }

    private func quantizedBeatPosition(
        for fraction: Double,
        meter: Meter,
        subdivisionsPerBeat: Int
    ) -> BeatPosition {
        let clampedFraction = min(max(fraction, 0), 0.9999)
        let totalSubdivisions = max(1, meter.numerator * subdivisionsPerBeat)
        let rawSubdivisionIndex = Int((clampedFraction * Double(totalSubdivisions)).rounded())
        let subdivisionIndex = min(max(0, rawSubdivisionIndex), totalSubdivisions - 1)
        let beat = subdivisionIndex / subdivisionsPerBeat + 1
        let subdivision = subdivisionIndex % subdivisionsPerBeat

        return BeatPosition(
            beat: beat,
            subdivision: subdivision,
            subdivisionsPerBeat: subdivisionsPerBeat
        )
    }

    func renderedChordPlacements(defaultMeter: Meter) -> [MeasureChordPlacement] {
        let meter = resolvedMeter(defaultMeter: defaultMeter)

        if let slots = resolvedRhythmSlots(defaultMeter: defaultMeter),
           !slots.isEmpty {
            let explicitlyReservedSlotIndices = explicitlyAssignedRhythmSlotIndices(defaultMeter: defaultMeter)
            var automaticallyAvailableSlotIndices = slots.indices.filter {
                slots[$0].isPlayable && !explicitlyReservedSlotIndices.contains($0)
            }

            return chordEvents.map { event in
                if let mappedRhythmSlotIndex = event.mappedRhythmSlotIndex,
                   slots.indices.contains(mappedRhythmSlotIndex),
                   slots[mappedRhythmSlotIndex].isPlayable {
                    return mappedPlacement(
                        for: event,
                        in: slots[mappedRhythmSlotIndex],
                        meter: meter,
                        slotIndex: mappedRhythmSlotIndex,
                        isExplicit: true
                    )
                }

                if let nextAutomaticSlotIndex = automaticallyAvailableSlotIndices.first {
                    automaticallyAvailableSlotIndices.removeFirst()
                    return mappedPlacement(
                        for: event,
                        in: slots[nextAutomaticSlotIndex],
                        meter: meter,
                        slotIndex: nextAutomaticSlotIndex,
                        isExplicit: false
                    )
                }

                return rawPlacement(for: event, meter: meter)
            }
        }

        if chordEvents.count == 1,
           let onlyChord = chordEvents.first,
           isMeasureStart(onlyChord.startPosition, in: meter) {
            return [
                MeasureChordPlacement(
                    chordEvent: onlyChord,
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
                    duration: nil,
                    effectiveWholeNoteLength: meter.measureLengthInWholeNotes,
                    durationDisplayText: "whole measure",
                    resolvedRhythmSlotIndex: nil,
                    isRhythmMapped: false,
                    isExplicitRhythmSlotAssignment: false,
                    isAutoFill: true
                )
            ]
        }

        return chordEvents.map { rawPlacement(for: $0, meter: meter) }
    }

    private func isMeasureStart(_ position: BeatPosition, in meter: Meter) -> Bool {
        guard let offset = position.startOffset(in: meter) else {
            return false
        }

        return abs(offset) < 0.0001
    }

    mutating func setRhythmMap(_ values: [RhythmValue], drawingData: Data? = nil) {
        rhythmMap = MeasureRhythmMap(values: values, drawingData: drawingData)
    }

    mutating func clearInvalidRhythmSlotAssignments(defaultMeter: Meter) {
        let slots = resolvedRhythmSlots(defaultMeter: defaultMeter)
        let playableIndices = slots.map { slots in
            Set(slots.indices.filter { slots[$0].isPlayable })
        } ?? []
        let pitchedNoteIndices = slots.map { slots in
            Set(slots.indices.filter { slots[$0].duration.supportsPitchedLeadSheetNote })
        } ?? []

        chordEvents = chordEvents.map { chordEvent in
            guard let mappedRhythmSlotIndex = chordEvent.mappedRhythmSlotIndex,
                  !playableIndices.contains(mappedRhythmSlotIndex) else {
                return chordEvent
            }

            var chordEvent = chordEvent
            chordEvent.mappedRhythmSlotIndex = nil
            return chordEvent
        }

        pitchedNoteEvents = pitchedNoteEvents.filter { pitchedNoteIndices.contains($0.rhythmSlotIndex) }
    }

    private func rawPlacement(for event: ChordEvent, meter: Meter) -> MeasureChordPlacement {
        MeasureChordPlacement(
            chordEvent: event,
            startPosition: event.startPosition,
            duration: event.duration,
            effectiveWholeNoteLength: event.duration.wholeNoteLength(in: meter),
            durationDisplayText: event.duration.displayText,
            resolvedRhythmSlotIndex: nil,
            isRhythmMapped: false,
            isExplicitRhythmSlotAssignment: false,
            isAutoFill: false
        )
    }

    private func mappedPlacement(
        for event: ChordEvent,
        in slot: MeasureRhythmSlot,
        meter: Meter,
        slotIndex: Int,
        isExplicit: Bool
    ) -> MeasureChordPlacement {
        MeasureChordPlacement(
            chordEvent: event,
            startPosition: slot.startPosition,
            duration: slot.duration,
            effectiveWholeNoteLength: slot.duration.wholeNoteLength(in: meter),
            durationDisplayText: slot.duration.displayText,
            resolvedRhythmSlotIndex: slotIndex,
            isRhythmMapped: true,
            isExplicitRhythmSlotAssignment: isExplicit,
            isAutoFill: false
        )
    }
}

extension RhythmValue {
    var supportsPitchedLeadSheetNote: Bool {
        switch self {
        case .sixteenth, .eighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole:
            return true
        case .slash, .sixteenthRest, .eighthRest, .quarterRest, .halfRest, .wholeRest, .tiedContinuation:
            return false
        }
    }

    static var sketchPalette: [RhythmValue] {
        [.slash, .sixteenth, .eighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole]
    }

    static var singularEditPalette: [RhythmValue] {
        [
            .whole,
            .dottedHalf,
            .half,
            .dottedQuarter,
            .slash,
            .quarter,
            .eighth,
            .sixteenth,
            .wholeRest,
            .halfRest,
            .quarterRest,
            .sixteenthRest,
            .eighthRest
        ]
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

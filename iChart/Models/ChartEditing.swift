import CoreGraphics
import Foundation

extension Chart {
    func resolvedAuthoringMeasureID(preferredMeasureID: UUID? = nil) -> UUID? {
        if let preferredMeasureID,
           measure(id: preferredMeasureID) != nil {
            return preferredMeasureID
        }

        return measures.first(where: { $0.authoringState == .open })?.id
            ?? measures.last?.id
    }

    mutating func completeInitialSetup(
        title: String,
        key: DocumentKey,
        meter: Meter,
        staffStyle: StaffStyle,
        startingMeasureCount: Int = 1,
        clef: ChartClef = .treble,
        stylePreset: StylePreset? = nil
    ) {
        self.title = title
        documentKey = key
        defaultMeter = meter
        self.staffStyle = staffStyle
        defaultClef = clef
        if let stylePreset {
            self.stylePreset = stylePreset
        }
        timeSignatureChanges = []
        ensureInitialSystem()
        if measures.isEmpty {
            let measureDefaults = layoutStyle.profile.measureDefaults
            systems[0].spacingMode = measureDefaults.systemSpacingMode
            systems[0].measures = Self.makeInitialMeasures(
                count: startingMeasureCount,
                measureDefaults: measureDefaults
            )
        }
        hasCompletedInitialSetup = true
        updatedAt = .now
    }

    mutating func setStylePreset(_ preset: StylePreset) {
        stylePreset = preset
        updatedAt = .now
    }

    mutating func setNotationFont(_ preset: NotationFontPreset) {
        notationFont = preset
        updatedAt = .now
    }

    mutating func setMatchedFontFamily(_ preset: ChartFontFamilyPreset) {
        typography.matchedSet = preset
        notationFont = preset.notationFont
        updatedAt = .now
    }

    mutating func setChordFontOverride(_ preset: ChartFontFamilyPreset?) {
        typography.chordOverride = preset
        updatedAt = .now
    }

    mutating func setHeaderFontOverride(_ preset: ChartFontFamilyPreset?) {
        typography.headerOverride = preset
        updatedAt = .now
    }

    mutating func setTextFontOverride(_ preset: ChartFontFamilyPreset?) {
        typography.textOverride = preset
        updatedAt = .now
    }

    mutating func setEngravingPreset(_ preset: EngravingPreset) {
        engravingPreset = preset
        updatedAt = .now
    }

    mutating func setHeaderInputMode(_ mode: ChartHeaderInputMode) {
        guard headerInputMode != mode else {
            return
        }

        headerInputMode = mode
        updatedAt = .now
    }

    mutating func setTranspositionView(_ view: TranspositionView) {
        defaultTranspositionView = view
        updatedAt = .now
    }

    mutating func setChordTranspositionSemitones(_ semitones: Int) {
        let normalizedSemitones = Self.normalizedChordTranspositionSemitones(semitones)
        guard chordTranspositionSemitones != normalizedSemitones else {
            return
        }

        chordTranspositionSemitones = normalizedSemitones
        updatedAt = .now
    }

    mutating func transposeChordsByHalfSteps(_ delta: Int) {
        setChordTranspositionSemitones(chordTranspositionSemitones + delta)
    }

    @discardableResult
    mutating func setMeasureManualLayoutWidth(_ width: CGFloat?, for measureID: UUID) -> CGFloat? {
        guard let location = measureLocation(id: measureID) else {
            return nil
        }

        let normalizedWidth = width.map { Measure.clampedManualLayoutWidth($0) }
        let normalizedStoredWidth = normalizedWidth.map(Double.init)
        guard systems[location.systemIndex].measures[location.measureIndex].manualLayoutWidth != normalizedStoredWidth else {
            return normalizedWidth
        }

        systems[location.systemIndex].measures[location.measureIndex].manualLayoutWidth = normalizedStoredWidth
        updatedAt = .now
        return normalizedWidth
    }

    func canInsertSystemBreak(before measureID: UUID) -> Bool {
        guard supportsManualSystemBreaks,
              let flatMeasureIndex = measures.firstIndex(where: { $0.id == measureID }) else {
            return false
        }

        return flatMeasureIndex > 0
            && !currentForcedSystemBreakStartIDs().contains(measureID)
    }

    func canRemoveSystemBreak(before measureID: UUID) -> Bool {
        guard supportsManualSystemBreaks,
              let location = measureLocation(id: measureID),
              location.systemIndex > 0,
              location.measureIndex == 0,
              systems[location.systemIndex].lineBreakRule == .forced else {
            return false
        }

        guard layoutStyle == .simpleChordSheet else {
            return true
        }

        let mergedMeasureCount = systems[location.systemIndex - 1].measures.count
            + systems[location.systemIndex].measures.count
        return mergedMeasureCount <= simpleSystemMeasureCap
    }

    @discardableResult
    mutating func insertSystemBreak(before measureID: UUID) -> Bool {
        guard canInsertSystemBreak(before: measureID) else {
            return false
        }

        var forcedBreakStartIDs = currentForcedSystemBreakStartIDs()
        forcedBreakStartIDs.insert(measureID)
        rebuildSystems(using: measures, forcedBreakStartIDsOverride: forcedBreakStartIDs)
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func removeSystemBreak(before measureID: UUID) -> Bool {
        guard canRemoveSystemBreak(before: measureID) else {
            return false
        }

        var forcedBreakStartIDs = currentForcedSystemBreakStartIDs()
        forcedBreakStartIDs.remove(measureID)
        rebuildSystems(using: measures, forcedBreakStartIDsOverride: forcedBreakStartIDs)
        updatedAt = .now
        return true
    }

    func canInsertSimpleSystemBreak(before measureID: UUID) -> Bool {
        layoutStyle == .simpleChordSheet
            && canInsertSystemBreak(before: measureID)
    }

    func canRemoveSimpleSystemBreak(before measureID: UUID) -> Bool {
        layoutStyle == .simpleChordSheet
            && canRemoveSystemBreak(before: measureID)
    }

    @discardableResult
    mutating func insertSimpleSystemBreak(before measureID: UUID) -> Bool {
        guard layoutStyle == .simpleChordSheet else {
            return false
        }

        return insertSystemBreak(before: measureID)
    }

    @discardableResult
    mutating func removeSimpleSystemBreak(before measureID: UUID) -> Bool {
        guard layoutStyle == .simpleChordSheet else {
            return false
        }

        return removeSystemBreak(before: measureID)
    }

    @discardableResult
    mutating func applyMeterChange(
        _ meter: Meter,
        after measureID: UUID,
        scope: TimeSignatureApplicationScope
    ) -> UUID? {
        guard let location = measureLocation(id: measureID) else {
            return nil
        }

        let sourceIndex = flattenedMeasureIndex(for: location)
        let requiredFollowingMeasures: Int
        switch scope {
        case .fixedMeasureCount(let additionalMeasureCount):
            requiredFollowingMeasures = max(1, additionalMeasureCount + 1)
        case .toEndOfPiece, .toNextTimeSignature:
            requiredFollowingMeasures = 1
        }

        ensureMeasuresExist(afterMeasureAt: sourceIndex, count: requiredFollowingMeasures)

        let refreshedMeasures = measures
        guard refreshedMeasures.indices.contains(sourceIndex + 1) else {
            return nil
        }

        let sourceMeasureID = refreshedMeasures[sourceIndex].id
        let sourceMeter = effectiveMeter(for: refreshedMeasures[sourceIndex])

        setTimeSignatureChange(after: sourceMeasureID, meter: meter)

        switch scope {
        case .toNextTimeSignature:
            break
        case .toEndOfPiece:
            removeTimeSignatureChanges(afterMeasureIndexGreaterThan: sourceIndex)
        case .fixedMeasureCount(let additionalMeasureCount):
            let lastAffectedIndex = min(sourceIndex + additionalMeasureCount + 1, measures.count - 1)
            removeTimeSignatureChanges(afterMeasureIndexIn: (sourceIndex + 1)..<lastAffectedIndex)

            let lastAffectedMeasureID = measures[lastAffectedIndex].id
            let existingBoundaryChange = timeSignatureChange(after: lastAffectedMeasureID)
            if existingBoundaryChange?.meter == meter || existingBoundaryChange == nil {
                setTimeSignatureChange(after: lastAffectedMeasureID, meter: sourceMeter)
            }
        }

        rebuildSystems(using: measures)
        updatedAt = .now
        let changedMeasureIndex = sourceIndex + 1
        return measures.indices.contains(changedMeasureIndex)
            ? measures[changedMeasureIndex].id
            : nil
    }

    @discardableResult
    mutating func appendMeasure(
        authoringState: MeasureAuthoringState = .committed,
        barlineAfter: BarlineType = .single
    ) -> UUID {
        let newMeasure = Self.makeMeasure(
            index: measures.count + 1,
            authoringState: authoringState,
            barlineAfter: barlineAfter,
            beatGridPreset: layoutStyle.profile.measureDefaults.beatGridPreset
        )
        appendPreparedMeasure(newMeasure)
        updatedAt = .now
        return newMeasure.id
    }

    @discardableResult
    mutating func insertMeasureAtBeginning(
        authoringState: MeasureAuthoringState = .committed,
        barlineAfter: BarlineType = .single
    ) -> UUID {
        let newMeasure = Self.makeMeasure(
            index: 1,
            authoringState: authoringState,
            barlineAfter: barlineAfter,
            beatGridPreset: layoutStyle.profile.measureDefaults.beatGridPreset
        )
        insertPreparedMeasure(newMeasure, at: 0)
        updatedAt = .now
        return newMeasure.id
    }

    @discardableResult
    mutating func insertMeasure(
        after measureID: UUID,
        authoringState: MeasureAuthoringState = .committed,
        barlineAfter: BarlineType = .single
    ) -> UUID? {
        guard let targetLocation = measureLocation(id: measureID) else {
            return nil
        }

        let newMeasure = Self.makeMeasure(
            index: flattenedMeasureIndex(for: targetLocation) + 2,
            authoringState: authoringState,
            barlineAfter: barlineAfter,
            beatGridPreset: layoutStyle.profile.measureDefaults.beatGridPreset
        )
        insertPreparedMeasure(newMeasure, after: targetLocation)
        updatedAt = .now
        return newMeasure.id
    }

    @discardableResult
    mutating func insertMeasures(
        after measureID: UUID,
        count: Int,
        authoringState: MeasureAuthoringState = .committed,
        barlineAfter: BarlineType = .single
    ) -> [UUID]? {
        guard count > 0,
              let targetLocation = measureLocation(id: measureID) else {
            return nil
        }

        let insertionIndex = flattenedMeasureIndex(for: targetLocation) + 1
        let newMeasures = (0..<count).map { offset in
            Self.makeMeasure(
                index: insertionIndex + offset + 1,
                authoringState: authoringState,
                barlineAfter: barlineAfter,
                beatGridPreset: layoutStyle.profile.measureDefaults.beatGridPreset
            )
        }
        insertPreparedMeasures(newMeasures, at: insertionIndex)
        updatedAt = .now
        return newMeasures.map(\.id)
    }

    func canDeleteMeasure(id measureID: UUID) -> Bool {
        measures.count > 1 && measureLocation(id: measureID) != nil
    }

    func canDeleteMeasures(from startMeasureID: UUID, through endMeasureID: UUID) -> Bool {
        guard let deletionRange = deletionRange(from: startMeasureID, through: endMeasureID) else {
            return false
        }

        return deletionRange.count < measures.count
    }

    @discardableResult
    mutating func deleteMeasure(id measureID: UUID) -> Bool {
        guard canDeleteMeasure(id: measureID),
              let location = measureLocation(id: measureID) else {
            return false
        }

        removeMeasure(at: location)
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func deleteMeasures(from startMeasureID: UUID, through endMeasureID: UUID) -> Bool {
        guard canDeleteMeasures(from: startMeasureID, through: endMeasureID),
              let deletionRange = deletionRange(from: startMeasureID, through: endMeasureID) else {
            return false
        }

        removeMeasures(in: deletionRange)
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func setPageHandwrittenNotationDrawing(_ drawingData: Data?) -> Bool {
        let normalizedData = drawingData?.isEmpty == true ? nil : drawingData
        guard pageHandwrittenNotationData != normalizedData else {
            return false
        }

        pageHandwrittenNotationData = normalizedData
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func setPageHandwrittenHeaderDrawing(_ drawingData: Data?) -> Bool {
        let normalizedData = drawingData?.isEmpty == true ? nil : drawingData
        guard pageHandwrittenHeaderData != normalizedData else {
            return false
        }

        pageHandwrittenHeaderData = normalizedData
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func setPageHandwrittenChordDrawing(_ drawingData: Data?) -> Bool {
        let normalizedData = drawingData?.isEmpty == true ? nil : drawingData
        guard pageHandwrittenChordData != normalizedData else {
            return false
        }

        pageHandwrittenChordData = normalizedData
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func setMeasureHandwrittenRhythmicNotationDrawing(
        _ drawingData: Data?,
        for measureID: UUID
    ) -> Bool {
        guard let location = measureLocation(id: measureID) else {
            return false
        }

        let normalizedData = drawingData?.isEmpty == true ? nil : drawingData
        guard systems[location.systemIndex].measures[location.measureIndex].handwrittenRhythmicNotationData != normalizedData else {
            return false
        }

        systems[location.systemIndex].measures[location.measureIndex].handwrittenRhythmicNotationData = normalizedData
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func setMeasureRhythmMap(
        _ values: [RhythmValue]?,
        drawingData: Data? = nil,
        for measureID: UUID
    ) -> Bool {
        guard let location = measureLocation(id: measureID) else {
            return false
        }

        let normalizedMap = values.map { MeasureRhythmMap(values: $0, drawingData: drawingData) }
        guard systems[location.systemIndex].measures[location.measureIndex].rhythmMap != normalizedMap else {
            return false
        }

        systems[location.systemIndex].measures[location.measureIndex].rhythmMap = normalizedMap
        systems[location.systemIndex].measures[location.measureIndex]
            .clearInvalidRhythmSlotAssignments(defaultMeter: defaultMeter)
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func setLeadSheetPitchedNotes(
        _ notes: [LeadSheetPitchedNoteInput],
        for measureID: UUID
    ) -> Bool {
        guard !notes.isEmpty,
              notes.allSatisfy({ $0.rhythmValue.supportsPitchedLeadSheetNote }) else {
            return false
        }

        let values = notes.map(\.rhythmValue)
        let slotInputs = notes.enumerated().map { index, note in
            LeadSheetPitchedNoteSlotInput(
                rhythmSlotIndex: index,
                staffPosition: note.staffPosition,
                sourceInkData: note.sourceInkData
            )
        }
        return setLeadSheetRhythmMap(values, pitchedNotes: slotInputs, for: measureID)
    }

    @discardableResult
    mutating func setLeadSheetRhythmMap(
        _ values: [RhythmValue],
        pitchedNotes: [LeadSheetPitchedNoteSlotInput],
        for measureID: UUID
    ) -> Bool {
        guard layoutStyle == .leadSheet,
              !values.isEmpty,
              let location = measureLocation(id: measureID) else {
            return false
        }

        var measure = systems[location.systemIndex].measures[location.measureIndex]
        let meter = measure.resolvedMeter(defaultMeter: defaultMeter)
        let rhythmMap = MeasureRhythmMap(values: values)
        guard RhythmicNotationCompendium.accepts(values, in: meter),
              let slots = rhythmMap.resolvedSlots(for: meter) else {
            return false
        }
        let uniqueSlotIndices = Set(pitchedNotes.map(\.rhythmSlotIndex))
        let noteSlotIndices = Set(slots.indices.filter {
            slots[$0].duration.supportsPitchedLeadSheetNote
        })
        guard uniqueSlotIndices.count == pitchedNotes.count,
              uniqueSlotIndices == noteSlotIndices,
              pitchedNotes.allSatisfy({ input in
                slots.indices.contains(input.rhythmSlotIndex)
                    && slots[input.rhythmSlotIndex].duration.supportsPitchedLeadSheetNote
              }) else {
            return false
        }

        let pitchedNoteEvents = pitchedNotes
            .sorted { $0.rhythmSlotIndex < $1.rhythmSlotIndex }
            .map { note in
            LeadSheetPitchedNoteEvent(
                rhythmSlotIndex: note.rhythmSlotIndex,
                staffPosition: note.staffPosition,
                sourceInkData: note.sourceInkData?.isEmpty == true ? nil : note.sourceInkData
            )
        }
        guard measure.rhythmMap != rhythmMap || measure.pitchedNoteEvents != pitchedNoteEvents else {
            return false
        }

        measure.rhythmMap = rhythmMap
        measure.pitchedNoteEvents = pitchedNoteEvents
        measure.handwrittenRhythmicNotationData = nil
        measure.clearInvalidRhythmSlotAssignments(defaultMeter: defaultMeter)
        systems[location.systemIndex].measures[location.measureIndex] = measure
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func replaceMeasureRhythmValue(
        _ rhythmValue: RhythmValue,
        at noteIndex: Int,
        in measureID: UUID
    ) -> MeasureRhythmReplacementResult {
        guard RhythmValue.singularEditPalette.contains(rhythmValue) else {
            return .unsupportedRhythmValue
        }

        guard let location = measureLocation(id: measureID) else {
            return .missingMeasure
        }

        var measure = systems[location.systemIndex].measures[location.measureIndex]
        guard var values = measure.rhythmMap?.values else {
            return .missingRhythmMap
        }

        guard values.indices.contains(noteIndex) else {
            return .invalidNoteIndex
        }

        values[noteIndex] = rhythmValue
        let replacementMap = MeasureRhythmMap(values: values)
        let meter = measure.resolvedMeter(defaultMeter: defaultMeter)
        let replacementStatus = replacementMap.status(for: meter)

        guard case .exact = replacementStatus else {
            return .invalidMeterFit(replacementStatus)
        }

        guard replacementMap.resolvedSlots(for: meter) != nil else {
            return .invalidMeterFit(.invalidSubdivision)
        }

        guard measure.rhythmMap != replacementMap else {
            return .unchanged
        }

        measure.rhythmMap = replacementMap
        measure.clearInvalidRhythmSlotAssignments(defaultMeter: defaultMeter)
        systems[location.systemIndex].measures[location.measureIndex] = measure
        updatedAt = .now
        return .applied
    }

    @discardableResult
    mutating func appendRecognizedChord(
        _ symbol: ChordSymbol,
        rawInput: String?,
        to measureID: UUID,
        atFraction fraction: Double?,
        sourceInkData: Data? = nil,
        sourceCandidateSignature: [String] = []
    ) -> Bool {
        appendRecognizedChordEvent(
            symbol,
            rawInput: rawInput,
            to: measureID,
            atFraction: fraction,
            sourceInkData: sourceInkData,
            sourceCandidateSignature: sourceCandidateSignature
        ) != nil
    }

    @discardableResult
    mutating func appendRecognizedChordEvent(
        _ symbol: ChordSymbol,
        rawInput: String?,
        to measureID: UUID,
        atFraction fraction: Double?,
        sourceInkData: Data? = nil,
        sourceCandidateSignature: [String] = []
    ) -> UUID? {
        guard let location = measureLocation(id: measureID) else {
            return nil
        }

        var measure = systems[location.systemIndex].measures[location.measureIndex]
        let suggestion = chordInsertionSuggestion(
            for: measure,
            atFraction: fraction,
            excluding: nil,
            mode: .append
        )
        let chordEventID = measure.appendChordEvent(
            symbol: symbol,
            rawInput: rawInput,
            suggestion: suggestion,
            sourceInkData: sourceInkData,
            sourceCandidateSignature: sourceCandidateSignature
        )

        systems[location.systemIndex].measures[location.measureIndex] = measure
        updatedAt = .now
        return chordEventID
    }

    @discardableResult
    mutating func commitRecognizedChordInk(
        _ symbol: ChordSymbol,
        rawInput: String?,
        to measureID: UUID,
        atFraction fraction: Double?,
        sourceInkData: Data,
        sourceCandidateSignature: [String] = []
    ) -> UUID? {
        guard let chordEventID = appendRecognizedChordEvent(
            symbol,
            rawInput: rawInput,
            to: measureID,
            atFraction: fraction,
            sourceInkData: sourceInkData,
            sourceCandidateSignature: sourceCandidateSignature
        ) else {
            return nil
        }

        _ = setPageHandwrittenChordDrawing(nil)
        return chordEventID
    }

    @discardableResult
    mutating func replaceChordEvent(
        _ chordEventID: UUID,
        with symbol: ChordSymbol,
        rawInput: String?
    ) -> Bool {
        guard let location = chordEventLocation(id: chordEventID) else {
            return false
        }

        systems[location.systemIndex]
            .measures[location.measureIndex]
            .chordEvents[location.chordIndex]
            .symbol = symbol
        systems[location.systemIndex]
            .measures[location.measureIndex]
            .chordEvents[location.chordIndex]
            .rawInput = rawInput
        updatedAt = .now
        return true
    }

    func chordEvent(id chordEventID: UUID) -> ChordEvent? {
        chordEventLocation(id: chordEventID).map {
            systems[$0.systemIndex].measures[$0.measureIndex].chordEvents[$0.chordIndex]
        }
    }

    func measureContainingChordEvent(id chordEventID: UUID) -> Measure? {
        chordEventLocation(id: chordEventID).map {
            systems[$0.systemIndex].measures[$0.measureIndex]
        }
    }

    @discardableResult
    mutating func deleteChordEvent(_ chordEventID: UUID) -> Bool {
        for systemIndex in systems.indices {
            for measureIndex in systems[systemIndex].measures.indices {
                guard let chordIndex = systems[systemIndex].measures[measureIndex].chordEvents.firstIndex(where: { $0.id == chordEventID }) else {
                    continue
                }

                systems[systemIndex].measures[measureIndex].chordEvents.remove(at: chordIndex)
                updatedAt = .now
                return true
            }
        }

        return false
    }

    @discardableResult
    mutating func moveChordEvent(
        _ chordEventID: UUID,
        to targetMeasureID: UUID,
        atFraction fraction: Double?
    ) -> Bool {
        guard let sourceLocation = chordEventLocation(id: chordEventID),
              let targetLocation = measureLocation(id: targetMeasureID) else {
            return false
        }

        var chordEvent = systems[sourceLocation.systemIndex]
            .measures[sourceLocation.measureIndex]
            .chordEvents[sourceLocation.chordIndex]

        if sourceLocation.systemIndex == targetLocation.systemIndex,
           sourceLocation.measureIndex == targetLocation.measureIndex {
            var measure = systems[targetLocation.systemIndex].measures[targetLocation.measureIndex]
            let suggestion = chordInsertionSuggestion(
                for: measure,
                atFraction: fraction,
                excluding: chordEventID,
                mode: .move
            )
            chordEvent.apply(suggestion: suggestion)
            measure.chordEvents[sourceLocation.chordIndex] = chordEvent
            systems[targetLocation.systemIndex].measures[targetLocation.measureIndex] = measure
            updatedAt = .now
            return true
        }

        systems[sourceLocation.systemIndex]
            .measures[sourceLocation.measureIndex]
            .chordEvents
            .remove(at: sourceLocation.chordIndex)

        var targetMeasure = systems[targetLocation.systemIndex].measures[targetLocation.measureIndex]
        let suggestion = chordInsertionSuggestion(
            for: targetMeasure,
            atFraction: fraction,
            excluding: nil,
            mode: .move
        )
        chordEvent.apply(suggestion: suggestion)
        targetMeasure.chordEvents.append(chordEvent)
        systems[targetLocation.systemIndex].measures[targetLocation.measureIndex] = targetMeasure
        updatedAt = .now
        return true
    }

    private enum ChordInsertionMode: Equatable {
        case append
        case move
    }

    private func chordInsertionSuggestion(
        for measure: Measure,
        atFraction fraction: Double?,
        excluding chordEventID: UUID?,
        mode: ChordInsertionMode
    ) -> MeasureChordInsertionSuggestion {
        if layoutStyle == .rhythmSectionSheet,
           measure.rhythmMap == nil,
           mode == .append,
           measure.chordEvents.filter({ $0.id != chordEventID }).isEmpty {
            return beatOneChordInsertionSuggestion()
        }

        guard layoutStyle == .simpleChordSheet,
              measure.rhythmMap == nil,
              mode == .append else {
            return measure.suggestedChordInsertion(
                atFraction: fraction,
                defaultMeter: defaultMeter,
                excluding: chordEventID
            )
        }

        return simpleChordSheetAutomaticChordInsertionSuggestion(
            for: measure,
            atFraction: fraction,
            excluding: chordEventID
        )
    }

    private func simpleChordSheetAutomaticChordInsertionSuggestion(
        for measure: Measure,
        atFraction fraction: Double?,
        excluding chordEventID: UUID?
    ) -> MeasureChordInsertionSuggestion {
        let meter = measure.resolvedMeter(defaultMeter: defaultMeter)
        let beatCount = max(1, meter.numerator)
        let occupiedBeats = Set<Int>(
            measure.chordEvents.compactMap { event in
                guard event.id != chordEventID else {
                    return nil
                }

                return event.startPosition.beat
            }
        )
        let availableBeats = (1...beatCount).filter { !occupiedBeats.contains($0) }
        let preferredBeatOrder = simpleChordSheetPreferredBeatOrder(for: meter)

        guard !occupiedBeats.isEmpty else {
            return simpleChordSheetChordInsertionSuggestion(onBeat: 1)
        }

        if let fraction,
           let locationBeat = simpleChordSheetLocationBeat(for: fraction, meter: meter) {
            if !occupiedBeats.contains(locationBeat) {
                return simpleChordSheetChordInsertionSuggestion(onBeat: locationBeat)
            }

            if occupiedBeats == [1],
               let midpointBeat = preferredBeatOrder.dropFirst().first(where: { !occupiedBeats.contains($0) }) {
                return simpleChordSheetChordInsertionSuggestion(onBeat: midpointBeat)
            }

            let writesAfterOccupiedBeat = fraction >= simpleChordSheetAttackFraction(
                forBeat: locationBeat,
                meter: meter
            )
            let directionalBeats = writesAfterOccupiedBeat
                ? availableBeats.filter { $0 > locationBeat }
                : Array(availableBeats.filter { $0 < locationBeat }.reversed())

            if let directionalBeat = directionalBeats.first {
                return simpleChordSheetChordInsertionSuggestion(onBeat: directionalBeat)
            }

            if let nearestBeat = availableBeats.min(by: { lhs, rhs in
                abs(lhs - locationBeat) < abs(rhs - locationBeat)
            }) {
                return simpleChordSheetChordInsertionSuggestion(onBeat: nearestBeat)
            }
        }

        let preferredBeat = simpleChordSheetPreferredBeatOrder(for: meter)
            .first { !occupiedBeats.contains($0) }
            ?? 1

        return simpleChordSheetChordInsertionSuggestion(onBeat: preferredBeat)
    }

    private func simpleChordSheetChordInsertionSuggestion(onBeat beat: Int) -> MeasureChordInsertionSuggestion {
        MeasureChordInsertionSuggestion(
            startPosition: BeatPosition(beat: beat, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .quarter,
            mappedRhythmSlotIndex: nil
        )
    }

    private func beatOneChordInsertionSuggestion() -> MeasureChordInsertionSuggestion {
        MeasureChordInsertionSuggestion(
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .quarter,
            mappedRhythmSlotIndex: nil
        )
    }

    private func simpleChordSheetLocationBeat(for fraction: Double, meter: Meter) -> Int? {
        let beatCount = max(1, meter.numerator)
        guard beatCount > 0 else {
            return nil
        }

        let clampedFraction = min(max(fraction, 0), 0.9999)
        let rawBeatIndex = Int((clampedFraction * Double(beatCount)).rounded())
        return min(max(0, rawBeatIndex), beatCount - 1) + 1
    }

    private func simpleChordSheetAttackFraction(forBeat beat: Int, meter: Meter) -> Double {
        let beatCount = max(1, meter.numerator)
        return Double(min(max(1, beat), beatCount) - 1) / Double(beatCount)
    }

    private func simpleChordSheetPreferredBeatOrder(for meter: Meter) -> [Int] {
        let beatCount = max(1, meter.numerator)
        let midpointBeat = min(beatCount, max(1, beatCount / 2 + 1))
        var orderedBeats = [1]
        if midpointBeat != 1 {
            orderedBeats.append(midpointBeat)
        }

        orderedBeats.append(
            contentsOf: (1...beatCount).filter { beat in
                !orderedBeats.contains(beat)
            }
        )
        return orderedBeats
    }

    @discardableResult
    mutating func clearMeasureRhythmicNotation(
        for measureID: UUID,
        clearRhythmMap: Bool
    ) -> Bool {
        guard let location = measureLocation(id: measureID) else {
            return false
        }

        var didChange = false
        if systems[location.systemIndex].measures[location.measureIndex].handwrittenRhythmicNotationData != nil {
            systems[location.systemIndex].measures[location.measureIndex].handwrittenRhythmicNotationData = nil
            didChange = true
        }

        if clearRhythmMap,
           systems[location.systemIndex].measures[location.measureIndex].rhythmMap != nil {
            systems[location.systemIndex].measures[location.measureIndex].rhythmMap = nil
            systems[location.systemIndex].measures[location.measureIndex]
                .clearInvalidRhythmSlotAssignments(defaultMeter: defaultMeter)
            didChange = true
        }

        if didChange {
            updatedAt = .now
        }

        return didChange
    }

    @discardableResult
    mutating func addFreehandSymbol(
        anchorMeasureID: UUID,
        lane: FreehandSymbolLane,
        normalizedFrame: FreehandSymbolNormalizedFrame,
        measureRelativeFrame: FreehandSymbolMeasureFrame? = nil,
        drawingData: Data
    ) -> UUID? {
        guard layoutStyle.profile.freehandSymbolLanes.contains(lane),
              measureLocation(id: anchorMeasureID) != nil,
              !drawingData.isEmpty else {
            return nil
        }

        switch lane {
        case .chartArea:
            guard let measureRelativeFrame,
                  measureRelativeFrame.width > 0,
                  measureRelativeFrame.height > 0 else {
                return nil
            }
        case .aboveMeasure, .belowMeasure:
            guard normalizedFrame.width > 0,
                  normalizedFrame.height > 0 else {
                return nil
            }
        }

        let symbolID = UUID()
        let nextZIndex = (freehandSymbols.map(\.zIndex).max() ?? -1) + 1
        freehandSymbols.append(
            FreehandSymbol(
                id: symbolID,
                anchorMeasureID: anchorMeasureID,
                lane: lane,
                normalizedFrame: normalizedFrame,
                measureRelativeFrame: measureRelativeFrame,
                drawingData: drawingData,
                zIndex: nextZIndex
            )
        )
        updatedAt = .now
        return symbolID
    }

    func freehandSymbol(id symbolID: UUID) -> FreehandSymbol? {
        freehandSymbols.first { $0.id == symbolID }
    }

    @discardableResult
    mutating func moveFreehandSymbol(
        _ symbolID: UUID,
        to normalizedFrame: FreehandSymbolNormalizedFrame
    ) -> Bool {
        guard normalizedFrame.width > 0,
              normalizedFrame.height > 0,
              let symbolIndex = freehandSymbols.firstIndex(where: { $0.id == symbolID }),
              freehandSymbols[symbolIndex].lane != .chartArea,
              layoutStyle.profile.freehandSymbolLanes.contains(freehandSymbols[symbolIndex].lane),
              measureLocation(id: freehandSymbols[symbolIndex].anchorMeasureID) != nil,
              freehandSymbols[symbolIndex].normalizedFrame != normalizedFrame else {
            return false
        }

        freehandSymbols[symbolIndex].normalizedFrame = normalizedFrame
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func moveFreehandSymbol(
        _ symbolID: UUID,
        to measureRelativeFrame: FreehandSymbolMeasureFrame,
        anchorMeasureID: UUID
    ) -> Bool {
        guard measureRelativeFrame.width > 0,
              measureRelativeFrame.height > 0,
              let symbolIndex = freehandSymbols.firstIndex(where: { $0.id == symbolID }),
              freehandSymbols[symbolIndex].lane == .chartArea,
              layoutStyle.profile.freehandSymbolLanes.contains(.chartArea),
              measureLocation(id: anchorMeasureID) != nil else {
            return false
        }

        let currentSymbol = freehandSymbols[symbolIndex]
        guard currentSymbol.anchorMeasureID != anchorMeasureID
            || currentSymbol.measureRelativeFrame != measureRelativeFrame else {
            return false
        }

        freehandSymbols[symbolIndex].anchorMeasureID = anchorMeasureID
        freehandSymbols[symbolIndex].measureRelativeFrame = measureRelativeFrame
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func deleteFreehandSymbol(_ symbolID: UUID) -> Bool {
        guard let symbolIndex = freehandSymbols.firstIndex(where: { $0.id == symbolID }),
              layoutStyle.profile.freehandSymbolLanes.contains(freehandSymbols[symbolIndex].lane) else {
            return false
        }

        freehandSymbols.remove(at: symbolIndex)
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func commitOpenMeasure(barlineAfter: BarlineType? = nil) -> UUID? {
        guard let location = openMeasureLocation() else {
            return nil
        }

        systems[location.systemIndex].measures[location.measureIndex].authoringState = .committed
        if let barlineAfter {
            systems[location.systemIndex].measures[location.measureIndex].barlineAfter = barlineAfter
        }
        let newMeasure = Self.makeMeasure(
            index: measures.count + 1,
            authoringState: .open,
            beatGridPreset: layoutStyle.profile.measureDefaults.beatGridPreset
        )
        insertPreparedMeasure(newMeasure, after: location)
        updatedAt = .now
        return newMeasure.id
    }

    @discardableResult
    mutating func positionOpenMeasure(after measureID: UUID) -> UUID? {
        guard let targetLocation = measureLocation(id: measureID) else {
            return nil
        }

        if systems[targetLocation.systemIndex].measures[targetLocation.measureIndex].authoringState == .open {
            return commitOpenMeasure()
        }

        let openMeasure: Measure
        if let openLocation = openMeasureLocation() {
            if flattenedMeasureIndex(for: openLocation) == flattenedMeasureIndex(for: targetLocation) + 1 {
                return systems[openLocation.systemIndex].measures[openLocation.measureIndex].id
            }

            guard isBlankOpenMeasure(at: openLocation) else {
                return systems[openLocation.systemIndex].measures[openLocation.measureIndex].id
            }

            openMeasure = systems[openLocation.systemIndex].measures[openLocation.measureIndex]
            removeMeasure(at: openLocation)
        } else {
            openMeasure = Self.makeMeasure(
                index: measures.count + 1,
                authoringState: .open,
                beatGridPreset: layoutStyle.profile.measureDefaults.beatGridPreset
            )
        }

        guard let refreshedTargetLocation = measureLocation(id: measureID) else {
            return nil
        }

        insertPreparedMeasure(openMeasure, after: refreshedTargetLocation)
        updatedAt = .now
        return openMeasure.id
    }

    mutating func addSectionLabel(text: String, type: SectionLabelType = .sectionName) {
        guard let firstSystem = systems.first,
              let firstMeasure = firstSystem.measures.first else {
            return
        }

        sectionLabels.append(
            SectionLabel(
                id: UUID(),
                text: text,
                type: type,
                anchorMeasureID: firstMeasure.id,
                anchorSystemID: firstSystem.id,
                rawInput: text
            )
        )

        updatedAt = .now
    }

    @discardableResult
    mutating func addCueText(
        _ text: String,
        anchorMeasureID: UUID? = nil,
        position: CuePosition = .below,
        emphasis: CueEmphasis = .normal
    ) -> UUID? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return nil
        }

        let resolvedMeasureID = anchorMeasureID ?? systems.first?.measures.first?.id
        guard let resolvedMeasureID,
              measureLocation(id: resolvedMeasureID) != nil else {
            return nil
        }

        let cue = CueText(
            id: UUID(),
            text: normalizedText,
            anchorMeasureID: resolvedMeasureID,
            position: position,
            emphasis: emphasis,
            rawInput: normalizedText
        )

        cueTexts.append(cue)
        attachCueText(cue.id, to: resolvedMeasureID)
        updatedAt = .now
        return cue.id
    }

    @discardableResult
    mutating func updateCueText(
        _ cueTextID: UUID,
        text: String? = nil,
        scale: Double? = nil,
        emphasis: CueEmphasis? = nil,
        position: CuePosition? = nil
    ) -> Bool {
        guard let cueTextIndex = cueTexts.firstIndex(where: { $0.id == cueTextID }) else {
            return false
        }

        if let text {
            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else {
                return false
            }

            cueTexts[cueTextIndex].text = normalizedText
            cueTexts[cueTextIndex].rawInput = normalizedText
        }

        if let scale {
            cueTexts[cueTextIndex].scale = CueText.clampedScale(scale)
        }

        if let emphasis {
            cueTexts[cueTextIndex].emphasis = emphasis
        }

        if let position {
            cueTexts[cueTextIndex].position = position
        }

        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func resizeCueText(_ cueTextID: UUID, byScaleDelta delta: Double) -> Bool {
        guard let cueText = cueText(id: cueTextID) else {
            return false
        }

        return updateCueText(cueTextID, scale: cueText.scale + delta)
    }

    @discardableResult
    mutating func moveCueText(
        _ cueTextID: UUID,
        to targetMeasureID: UUID,
        atFraction fraction: Double?
    ) -> Bool {
        guard let cueTextIndex = cueTexts.firstIndex(where: { $0.id == cueTextID }),
              let targetLocation = measureLocation(id: targetMeasureID) else {
            return false
        }

        let targetMeasure = systems[targetLocation.systemIndex].measures[targetLocation.measureIndex]
        let snappedFraction = snappedCueTextBeatFraction(
            CueText.clampedBeatFraction(fraction),
            in: targetMeasure
        )
        let previousMeasureID = cueTexts[cueTextIndex].anchorMeasureID

        cueTexts[cueTextIndex].anchorMeasureID = targetMeasureID
        cueTexts[cueTextIndex].beatFraction = snappedFraction

        if previousMeasureID != targetMeasureID {
            removeCueTextIDFromMeasures(cueTextID)
            attachCueText(cueTextID, to: targetMeasureID)
        }

        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func deleteCueText(_ cueTextID: UUID) -> Bool {
        guard let cueTextIndex = cueTexts.firstIndex(where: { $0.id == cueTextID }) else {
            return false
        }

        cueTexts.remove(at: cueTextIndex)
        removeCueTextIDFromMeasures(cueTextID)
        updatedAt = .now
        return true
    }

    func cueText(id cueTextID: UUID) -> CueText? {
        cueTexts.first { $0.id == cueTextID }
    }

    func cueTextIDs(attachedTo measureID: UUID) -> [UUID] {
        cueTexts
            .filter { $0.anchorMeasureID == measureID }
            .map(\.id)
    }

    private func snappedCueTextBeatFraction(_ fraction: Double?, in measure: Measure) -> Double? {
        guard let fraction else {
            return nil
        }

        let meter = measure.resolvedMeter(defaultMeter: defaultMeter)
        return MeasurePlacementGrid.snappedFraction(fraction, in: meter)
    }

    @discardableResult
    mutating func deleteCueTexts(attachedTo measureID: UUID) -> Int {
        let cueTextIDs = cueTextIDs(attachedTo: measureID)
        guard !cueTextIDs.isEmpty else {
            return 0
        }

        let cueTextIDSet = Set(cueTextIDs)
        cueTexts.removeAll { cueTextIDSet.contains($0.id) }
        for cueTextID in cueTextIDs {
            removeCueTextIDFromMeasures(cueTextID)
        }
        updatedAt = .now
        return cueTextIDs.count
    }

    mutating func addRoadmapObject(_ type: RoadmapType, displayText: String? = nil) {
        guard !systems.isEmpty, !systems[0].measures.isEmpty else {
            return
        }

        if type.isPointMarker {
            _ = addPointRoadmapMarker(
                type,
                anchorMeasureID: systems[0].measures[0].id,
                displayText: displayText
            )
            return
        }

        let roadmap = RoadmapObject(
            id: UUID(),
            type: type,
            startMeasureID: systems[0].measures[0].id,
            endMeasureID: nil,
            anchorSystemID: systems[0].id,
            placement: .floatingTop,
            displayText: displayText,
            count: nil,
            linkedTargetID: nil,
            rawInput: displayText ?? type.defaultDisplayText
        )
        roadmapObjects.append(roadmap)
        systems[0].measures[0].roadmapObjectIDs.append(roadmap.id)

        updatedAt = .now
    }

    @discardableResult
    mutating func addPointRoadmapMarker(
        _ type: RoadmapType,
        anchorMeasureID: UUID? = nil,
        displayText: String? = nil,
        count: Int? = nil
    ) -> UUID? {
        let normalizedDisplayText = displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayText = normalizedDisplayText?.isEmpty == false ? normalizedDisplayText : nil
        guard type.isPointMarker,
              let resolvedMeasureID = anchorMeasureID ?? systems.first?.measures.first?.id,
              let location = measureLocation(id: resolvedMeasureID) else {
            return nil
        }

        if let existingMarker = roadmapObjects.first(where: {
            $0.type == type
                && $0.startMeasureID == resolvedMeasureID
                && $0.endMeasureID == nil
                && $0.displayText == resolvedDisplayText
                && $0.count == count
        }) {
            if existingMarker.linkedTargetID == nil {
                _ = linkRoadmapObjectToSuggestedTarget(existingMarker.id)
            }
            return existingMarker.id
        }

        var marker = RoadmapObject(
            id: UUID(),
            type: type,
            startMeasureID: resolvedMeasureID,
            endMeasureID: nil,
            anchorSystemID: systems[location.systemIndex].id,
            placement: .snappedTop,
            displayText: resolvedDisplayText,
            count: count,
            linkedTargetID: nil,
            rawInput: resolvedDisplayText ?? type.defaultDisplayText
        )
        marker.linkedTargetID = suggestedRoadmapTargetID(for: marker)

        roadmapObjects.append(marker)
        attachRoadmapObject(marker.id, to: resolvedMeasureID)
        updatedAt = .now
        return marker.id
    }

    func roadmapObject(id roadmapObjectID: UUID) -> RoadmapObject? {
        roadmapObjects.first { $0.id == roadmapObjectID }
    }

    func canLinkRoadmapObject(_ sourceID: UUID, to targetID: UUID) -> Bool {
        guard let source = roadmapObject(id: sourceID),
              let target = roadmapObject(id: targetID) else {
            return false
        }

        return canLinkRoadmapObject(source, to: target)
    }

    func suggestedRoadmapTargetID(for roadmapObjectID: UUID) -> UUID? {
        guard let source = roadmapObject(id: roadmapObjectID) else {
            return nil
        }

        return suggestedRoadmapTargetID(for: source)
    }

    @discardableResult
    mutating func linkRoadmapObject(_ sourceID: UUID, to targetID: UUID) -> Bool {
        guard let sourceIndex = roadmapObjects.firstIndex(where: { $0.id == sourceID }),
              canLinkRoadmapObject(roadmapObjects[sourceIndex], to: targetID) else {
            return false
        }

        guard roadmapObjects[sourceIndex].linkedTargetID != targetID else {
            return false
        }

        roadmapObjects[sourceIndex].linkedTargetID = targetID
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func linkRoadmapObjectToSuggestedTarget(_ sourceID: UUID) -> Bool {
        guard let targetID = suggestedRoadmapTargetID(for: sourceID) else {
            return false
        }

        return linkRoadmapObject(sourceID, to: targetID)
    }

    @discardableResult
    mutating func linkPointRoadmapMarkers(attachedTo measureID: UUID) -> Int {
        let markerIDs = pointRoadmapMarkerIDs(attachedTo: measureID)
        var linkedCount = 0

        for markerID in markerIDs where linkRoadmapObjectToSuggestedTarget(markerID) {
            linkedCount += 1
        }

        return linkedCount
    }

    @discardableResult
    mutating func clearRoadmapLink(_ sourceID: UUID) -> Bool {
        guard let sourceIndex = roadmapObjects.firstIndex(where: { $0.id == sourceID }),
              roadmapObjects[sourceIndex].linkedTargetID != nil else {
            return false
        }

        roadmapObjects[sourceIndex].linkedTargetID = nil
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func clearRoadmapLinks(attachedTo measureID: UUID) -> Int {
        let markerIDs = pointRoadmapMarkerIDs(attachedTo: measureID)
        var clearedCount = 0

        for markerID in markerIDs where clearRoadmapLink(markerID) {
            clearedCount += 1
        }

        return clearedCount
    }

    @discardableResult
    mutating func addRepeatSpan(startMeasureID: UUID, endMeasureID: UUID) -> UUID? {
        guard let startLocation = measureLocation(id: startMeasureID),
              let endLocation = measureLocation(id: endMeasureID),
              flattenedMeasureIndex(for: startLocation) <= flattenedMeasureIndex(for: endLocation) else {
            return nil
        }

        if let existingRepeatSpan = roadmapObjects.first(where: {
            $0.type == .repeatSpan
                && $0.startMeasureID == startMeasureID
                && $0.endMeasureID == endMeasureID
        }) {
            return existingRepeatSpan.id
        }

        let repeatSpan = RoadmapObject(
            id: UUID(),
            type: .repeatSpan,
            startMeasureID: startMeasureID,
            endMeasureID: endMeasureID,
            anchorSystemID: systems[startLocation.systemIndex].id,
            placement: .snappedTop,
            displayText: nil,
            count: nil,
            linkedTargetID: nil,
            rawInput: RoadmapType.repeatSpan.defaultDisplayText
        )

        roadmapObjects.append(repeatSpan)
        attachRoadmapObject(repeatSpan.id, to: startMeasureID)
        attachRoadmapObject(repeatSpan.id, to: endMeasureID)
        updatedAt = .now
        return repeatSpan.id
    }

    @discardableResult
    mutating func addEndingSpan(
        _ type: RoadmapType,
        startMeasureID: UUID,
        endMeasureID: UUID
    ) -> UUID? {
        guard type.isEnding,
              let startLocation = measureLocation(id: startMeasureID),
              let endLocation = measureLocation(id: endMeasureID),
              flattenedMeasureIndex(for: startLocation) <= flattenedMeasureIndex(for: endLocation) else {
            return nil
        }

        if let existingEndingSpan = roadmapObjects.first(where: {
            $0.type == type
                && $0.startMeasureID == startMeasureID
                && $0.endMeasureID == endMeasureID
        }) {
            return existingEndingSpan.id
        }

        let endingSpan = RoadmapObject(
            id: UUID(),
            type: type,
            startMeasureID: startMeasureID,
            endMeasureID: endMeasureID,
            anchorSystemID: systems[startLocation.systemIndex].id,
            placement: .snappedTop,
            displayText: nil,
            count: nil,
            linkedTargetID: nil,
            rawInput: type.defaultDisplayText
        )

        roadmapObjects.append(endingSpan)
        attachRoadmapObject(endingSpan.id, to: startMeasureID)
        attachRoadmapObject(endingSpan.id, to: endMeasureID)
        updatedAt = .now
        return endingSpan.id
    }

    @discardableResult
    mutating func updateRepeatSpan(
        _ roadmapObjectID: UUID,
        startMeasureID: UUID,
        endMeasureID: UUID
    ) -> Bool {
        guard let roadmapObjectIndex = roadmapObjects.firstIndex(where: { $0.id == roadmapObjectID }),
              roadmapObjects[roadmapObjectIndex].type == .repeatSpan,
              let startLocation = measureLocation(id: startMeasureID),
              let endLocation = measureLocation(id: endMeasureID),
              flattenedMeasureIndex(for: startLocation) <= flattenedMeasureIndex(for: endLocation) else {
            return false
        }

        var repeatSpan = roadmapObjects[roadmapObjectIndex]
        guard repeatSpan.startMeasureID != startMeasureID
            || repeatSpan.endMeasureID != endMeasureID
            || repeatSpan.anchorSystemID != systems[startLocation.systemIndex].id else {
            return false
        }

        repeatSpan.startMeasureID = startMeasureID
        repeatSpan.endMeasureID = endMeasureID
        repeatSpan.anchorSystemID = systems[startLocation.systemIndex].id
        roadmapObjects[roadmapObjectIndex] = repeatSpan
        removeRoadmapObjectIDFromMeasures(roadmapObjectID)
        attachRoadmapObject(roadmapObjectID, to: startMeasureID)
        attachRoadmapObject(roadmapObjectID, to: endMeasureID)
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func updateEndingSpan(
        _ roadmapObjectID: UUID,
        startMeasureID: UUID,
        endMeasureID: UUID
    ) -> Bool {
        guard let roadmapObjectIndex = roadmapObjects.firstIndex(where: { $0.id == roadmapObjectID }),
              roadmapObjects[roadmapObjectIndex].type.isEnding,
              let startLocation = measureLocation(id: startMeasureID),
              let endLocation = measureLocation(id: endMeasureID),
              flattenedMeasureIndex(for: startLocation) <= flattenedMeasureIndex(for: endLocation) else {
            return false
        }

        var endingSpan = roadmapObjects[roadmapObjectIndex]
        guard endingSpan.startMeasureID != startMeasureID
            || endingSpan.endMeasureID != endMeasureID
            || endingSpan.anchorSystemID != systems[startLocation.systemIndex].id else {
            return false
        }

        endingSpan.startMeasureID = startMeasureID
        endingSpan.endMeasureID = endMeasureID
        endingSpan.anchorSystemID = systems[startLocation.systemIndex].id
        roadmapObjects[roadmapObjectIndex] = endingSpan
        removeRoadmapObjectIDFromMeasures(roadmapObjectID)
        attachRoadmapObject(roadmapObjectID, to: startMeasureID)
        attachRoadmapObject(roadmapObjectID, to: endMeasureID)
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func deleteRoadmapObject(_ roadmapObjectID: UUID) -> Bool {
        guard let roadmapObjectIndex = roadmapObjects.firstIndex(where: { $0.id == roadmapObjectID }) else {
            return false
        }

        roadmapObjects.remove(at: roadmapObjectIndex)
        removeRoadmapObjectIDFromMeasures(roadmapObjectID)
        clearRoadmapLinks(toDeletedRoadmapObjectIDs: [roadmapObjectID])
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func movePointRoadmapMarker(_ roadmapObjectID: UUID, to anchorMeasureID: UUID) -> Bool {
        guard let roadmapObjectIndex = roadmapObjects.firstIndex(where: { $0.id == roadmapObjectID }),
              roadmapObjects[roadmapObjectIndex].type.isPointMarker,
              roadmapObjects[roadmapObjectIndex].endMeasureID == nil,
              let location = measureLocation(id: anchorMeasureID) else {
            return false
        }

        guard roadmapObjects[roadmapObjectIndex].startMeasureID != anchorMeasureID else {
            return false
        }

        roadmapObjects[roadmapObjectIndex].startMeasureID = anchorMeasureID
        roadmapObjects[roadmapObjectIndex].anchorSystemID = systems[location.systemIndex].id
        roadmapObjects[roadmapObjectIndex].placement = .snappedTop
        roadmapObjects[roadmapObjectIndex].linkedTargetID = suggestedRoadmapTargetID(
            for: roadmapObjects[roadmapObjectIndex]
        )
        removeRoadmapObjectIDFromMeasures(roadmapObjectID)
        attachRoadmapObject(roadmapObjectID, to: anchorMeasureID)
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func movePointRoadmapMarkerHorizontally(
        _ roadmapObjectID: UUID,
        toNormalizedOffset offset: Double
    ) -> Bool {
        guard let roadmapObjectIndex = roadmapObjects.firstIndex(where: { $0.id == roadmapObjectID }),
              roadmapObjects[roadmapObjectIndex].type.isPointMarker,
              roadmapObjects[roadmapObjectIndex].endMeasureID == nil,
              measureLocation(id: roadmapObjects[roadmapObjectIndex].startMeasureID) != nil else {
            return false
        }

        let clampedOffset = RoadmapObject.clampedHorizontalOffset(offset)
        guard roadmapObjects[roadmapObjectIndex].resolvedHorizontalOffsetWithinMeasure != clampedOffset else {
            return false
        }

        roadmapObjects[roadmapObjectIndex].horizontalOffsetWithinMeasure = clampedOffset
        updatedAt = .now
        return true
    }

    func repeatSpanIDs(attachedTo measureID: UUID) -> [UUID] {
        roadmapObjects
            .filter {
                $0.type == .repeatSpan
                    && ($0.startMeasureID == measureID || $0.endMeasureID == measureID)
            }
            .map(\.id)
    }

    func endingSpanIDs(attachedTo measureID: UUID) -> [UUID] {
        roadmapObjects
            .filter {
                $0.type.isEnding
                    && ($0.startMeasureID == measureID || $0.endMeasureID == measureID)
            }
            .map(\.id)
    }

    func pointRoadmapMarkerIDs(attachedTo measureID: UUID) -> [UUID] {
        roadmapObjects
            .filter {
                $0.type.isPointMarker
                    && $0.startMeasureID == measureID
                    && $0.endMeasureID == nil
            }
            .map(\.id)
    }

    @discardableResult
    mutating func deleteRepeatSpans(attachedTo measureID: UUID) -> Int {
        let repeatSpanIDs = repeatSpanIDs(attachedTo: measureID)
        guard !repeatSpanIDs.isEmpty else {
            return 0
        }

        let repeatSpanIDSet = Set(repeatSpanIDs)
        roadmapObjects.removeAll { repeatSpanIDSet.contains($0.id) }
        for repeatSpanID in repeatSpanIDs {
            removeRoadmapObjectIDFromMeasures(repeatSpanID)
        }
        clearRoadmapLinks(toDeletedRoadmapObjectIDs: repeatSpanIDSet)
        updatedAt = .now
        return repeatSpanIDs.count
    }

    @discardableResult
    mutating func deleteEndingSpans(attachedTo measureID: UUID) -> Int {
        let endingSpanIDs = endingSpanIDs(attachedTo: measureID)
        guard !endingSpanIDs.isEmpty else {
            return 0
        }

        let endingSpanIDSet = Set(endingSpanIDs)
        roadmapObjects.removeAll { endingSpanIDSet.contains($0.id) }
        for endingSpanID in endingSpanIDs {
            removeRoadmapObjectIDFromMeasures(endingSpanID)
        }
        clearRoadmapLinks(toDeletedRoadmapObjectIDs: endingSpanIDSet)
        updatedAt = .now
        return endingSpanIDs.count
    }

    @discardableResult
    mutating func deletePointRoadmapMarkers(attachedTo measureID: UUID) -> Int {
        let markerIDs = pointRoadmapMarkerIDs(attachedTo: measureID)
        guard !markerIDs.isEmpty else {
            return 0
        }

        let markerIDSet = Set(markerIDs)
        roadmapObjects.removeAll { markerIDSet.contains($0.id) }
        for markerID in markerIDs {
            removeRoadmapObjectIDFromMeasures(markerID)
        }
        clearRoadmapLinks(toDeletedRoadmapObjectIDs: markerIDSet)
        updatedAt = .now
        return markerIDs.count
    }

    func measure(id: UUID) -> Measure? {
        measureLocation(id: id).map { systems[$0.systemIndex].measures[$0.measureIndex] }
    }

    private func measureLocation(id: UUID) -> (systemIndex: Int, measureIndex: Int)? {
        for (systemIndex, system) in systems.enumerated() {
            if let measureIndex = system.measures.firstIndex(where: { $0.id == id }) {
                return (systemIndex, measureIndex)
            }
        }

        return nil
    }

    private func chordEventLocation(id: UUID) -> (systemIndex: Int, measureIndex: Int, chordIndex: Int)? {
        for (systemIndex, system) in systems.enumerated() {
            for (measureIndex, measure) in system.measures.enumerated() {
                if let chordIndex = measure.chordEvents.firstIndex(where: { $0.id == id }) {
                    return (systemIndex, measureIndex, chordIndex)
                }
            }
        }

        return nil
    }

    private mutating func ensureInitialSystem() {
        guard systems.isEmpty else {
            return
        }

        systems = [
            ChartSystem(
                id: UUID(),
                index: 0,
                spacingMode: .automatic,
                lineBreakRule: .automatic,
                measures: []
            )
        ]
    }

    private static func makeMeasure(
        index: Int,
        authoringState: MeasureAuthoringState,
        barlineAfter: BarlineType = .single,
        beatGridPreset: BeatGridPreset = .simple
    ) -> Measure {
        Measure(
            id: UUID(),
            index: index,
            meterOverride: nil,
            beatGridPreset: beatGridPreset,
            barlineAfter: barlineAfter,
            chordEvents: [],
            cueTextIDs: [],
            roadmapObjectIDs: [],
            authoringState: authoringState
        )
    }

    private static func makeInitialMeasures(
        count: Int,
        measureDefaults: ChartLayoutMeasureDefaults
    ) -> [Measure] {
        let normalizedCount = max(1, count)
        return (1...normalizedCount).map { index in
            Self.makeMeasure(
                index: index,
                authoringState: index == normalizedCount ? .open : .committed,
                beatGridPreset: measureDefaults.beatGridPreset
            )
        }
    }

    private func openMeasureLocation() -> (systemIndex: Int, measureIndex: Int)? {
        for systemIndex in systems.indices.reversed() {
            if let measureIndex = systems[systemIndex].measures.lastIndex(where: { $0.authoringState == .open }) {
                return (systemIndex, measureIndex)
            }
        }

        return nil
    }

    private func lastMeasureLocation() -> (systemIndex: Int, measureIndex: Int)? {
        guard let systemIndex = systems.indices.last,
              let measureIndex = systems[systemIndex].measures.indices.last else {
            return nil
        }

        return (systemIndex, measureIndex)
    }

    private func isBlankOpenMeasure(
        at location: (systemIndex: Int, measureIndex: Int)
    ) -> Bool {
        let measure = systems[location.systemIndex].measures[location.measureIndex]
        guard measure.authoringState == .open else {
            return false
        }

        return measure.chordEvents.isEmpty
            && measure.rhythmMap == nil
            && measure.handwrittenRhythmicNotationData == nil
            && !freehandSymbols.contains { $0.anchorMeasureID == measure.id }
            && measure.cueTextIDs.isEmpty
            && measure.roadmapObjectIDs.isEmpty
    }

    private var simpleSystemMeasureCap: Int {
        layoutStyle.profile.measureDefaults.maximumMeasuresPerSystem ?? Int.max
    }

    private var supportsManualSystemBreaks: Bool {
        layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet
    }

    private func currentForcedSystemBreakStartIDs() -> Set<UUID> {
        Set(
            systems
                .dropFirst()
                .filter { $0.lineBreakRule == .forced }
                .compactMap(\.measures.first?.id)
        )
    }

    private mutating func removeMeasure(
        at location: (systemIndex: Int, measureIndex: Int)
    ) {
        let removalIndex = flattenedMeasureIndex(for: location)
        removeMeasures(in: removalIndex..<(removalIndex + 1))
    }

    private mutating func removeMeasures(in removalRange: Range<Int>) {
        var flattenedMeasures = measures
        let clampedLowerBound = min(max(removalRange.lowerBound, 0), flattenedMeasures.count)
        let clampedUpperBound = min(max(removalRange.upperBound, clampedLowerBound), flattenedMeasures.count)
        guard clampedLowerBound < clampedUpperBound else {
            return
        }

        let removedMeasures = Array(flattenedMeasures[clampedLowerBound..<clampedUpperBound])
        flattenedMeasures.removeSubrange(clampedLowerBound..<clampedUpperBound)
        for removedMeasure in removedMeasures {
            removeAnnotations(attachedTo: removedMeasure, fromRemainingMeasures: &flattenedMeasures)
        }
        rebuildSystems(using: flattenedMeasures)
    }

    private mutating func normalizeSystemIndices() {
        for systemIndex in systems.indices {
            systems[systemIndex].index = systemIndex
        }
    }

    private mutating func appendPreparedMeasure(_ newMeasure: Measure) {
        insertPreparedMeasure(newMeasure, after: lastMeasureLocation())
    }

    private mutating func insertPreparedMeasure(_ newMeasure: Measure, at insertionIndex: Int) {
        ensureInitialSystem()
        var flattenedMeasures = measures
        let clampedIndex = min(max(insertionIndex, 0), flattenedMeasures.count)
        flattenedMeasures.insert(newMeasure, at: clampedIndex)
        rebuildSystems(using: flattenedMeasures)
    }

    private mutating func insertPreparedMeasures(_ newMeasures: [Measure], at insertionIndex: Int) {
        guard !newMeasures.isEmpty else {
            return
        }

        ensureInitialSystem()
        var flattenedMeasures = measures
        let clampedIndex = min(max(insertionIndex, 0), flattenedMeasures.count)
        flattenedMeasures.insert(contentsOf: newMeasures, at: clampedIndex)
        rebuildSystems(using: flattenedMeasures)
    }

    private mutating func insertPreparedMeasure(
        _ newMeasure: Measure,
        after location: (systemIndex: Int, measureIndex: Int)?
    ) {
        ensureInitialSystem()
        let insertionIndex = location.map { flattenedMeasureIndex(for: $0) + 1 } ?? measures.count
        var flattenedMeasures = measures
        flattenedMeasures.insert(newMeasure, at: min(max(insertionIndex, 0), flattenedMeasures.count))
        rebuildSystems(using: flattenedMeasures)
    }

    private func flattenedMeasureIndex(
        for location: (systemIndex: Int, measureIndex: Int)
    ) -> Int {
        let precedingMeasureCount = systems[..<location.systemIndex]
            .reduce(into: 0) { partialResult, system in
                partialResult += system.measures.count
            }

        return precedingMeasureCount + location.measureIndex
    }

    private func flattenedMeasureIndex(id measureID: UUID) -> Int? {
        measureLocation(id: measureID).map { flattenedMeasureIndex(for: $0) }
    }

    private func deletionRange(from startMeasureID: UUID, through endMeasureID: UUID) -> Range<Int>? {
        guard let startIndex = flattenedMeasureIndex(id: startMeasureID),
              let endIndex = flattenedMeasureIndex(id: endMeasureID) else {
            return nil
        }

        let lowerBound = min(startIndex, endIndex)
        let upperBound = max(startIndex, endIndex) + 1
        return lowerBound..<upperBound
    }

    private mutating func attachCueText(_ cueTextID: UUID, to measureID: UUID) {
        guard let location = measureLocation(id: measureID),
              !systems[location.systemIndex].measures[location.measureIndex].cueTextIDs.contains(cueTextID) else {
            return
        }

        systems[location.systemIndex].measures[location.measureIndex].cueTextIDs.append(cueTextID)
    }

    private mutating func removeCueTextIDFromMeasures(_ cueTextID: UUID) {
        for systemIndex in systems.indices {
            for measureIndex in systems[systemIndex].measures.indices {
                systems[systemIndex].measures[measureIndex].cueTextIDs.removeAll { $0 == cueTextID }
            }
        }
    }

    private mutating func attachRoadmapObject(_ roadmapObjectID: UUID, to measureID: UUID) {
        guard let location = measureLocation(id: measureID),
              !systems[location.systemIndex].measures[location.measureIndex].roadmapObjectIDs.contains(roadmapObjectID) else {
            return
        }

        systems[location.systemIndex].measures[location.measureIndex].roadmapObjectIDs.append(roadmapObjectID)
    }

    private mutating func removeRoadmapObjectIDFromMeasures(_ roadmapObjectID: UUID) {
        for systemIndex in systems.indices {
            for measureIndex in systems[systemIndex].measures.indices {
                systems[systemIndex].measures[measureIndex].roadmapObjectIDs.removeAll { $0 == roadmapObjectID }
            }
        }
    }

    private func canLinkRoadmapObject(_ source: RoadmapObject, to targetID: UUID) -> Bool {
        guard let target = roadmapObject(id: targetID) else {
            return false
        }

        return canLinkRoadmapObject(source, to: target)
    }

    private func canLinkRoadmapObject(_ source: RoadmapObject, to target: RoadmapObject) -> Bool {
        source.id != target.id
            && source.type.isPointMarker
            && target.type.isPointMarker
            && source.endMeasureID == nil
            && target.endMeasureID == nil
            && source.type.linkTargetTypes.contains(target.type)
    }

    private func suggestedRoadmapTargetID(for source: RoadmapObject) -> UUID? {
        guard source.type.isPointMarker,
              !source.type.linkTargetTypes.isEmpty,
              let sourceLocation = measureLocation(id: source.startMeasureID) else {
            return nil
        }

        let sourceMeasureIndex = flattenedMeasureIndex(for: sourceLocation)
        let candidates = roadmapObjects.compactMap { candidate -> (id: UUID, distance: Int, isPreferredDirection: Bool)? in
            guard canLinkRoadmapObject(source, to: candidate),
                  let targetLocation = measureLocation(id: candidate.startMeasureID) else {
                return nil
            }

            let targetMeasureIndex = flattenedMeasureIndex(for: targetLocation)
            let distance = abs(targetMeasureIndex - sourceMeasureIndex)
            let isPreferredDirection: Bool
            switch source.type.linkTargetSearchDirection {
            case .before:
                isPreferredDirection = targetMeasureIndex < sourceMeasureIndex
            case .after:
                isPreferredDirection = targetMeasureIndex > sourceMeasureIndex
            case .nearest:
                isPreferredDirection = true
            }

            return (candidate.id, distance, isPreferredDirection)
        }

        return candidates
            .sorted {
                if $0.isPreferredDirection != $1.isPreferredDirection {
                    return $0.isPreferredDirection && !$1.isPreferredDirection
                }

                return $0.distance < $1.distance
            }
            .first?
            .id
    }

    private mutating func clearRoadmapLinks(toDeletedRoadmapObjectIDs deletedIDs: Set<UUID>) {
        guard !deletedIDs.isEmpty else {
            return
        }

        for roadmapObjectIndex in roadmapObjects.indices
            where roadmapObjects[roadmapObjectIndex].linkedTargetID.map(deletedIDs.contains) == true {
            roadmapObjects[roadmapObjectIndex].linkedTargetID = nil
        }
    }

    private mutating func removeAnnotations(
        attachedTo removedMeasure: Measure,
        fromRemainingMeasures remainingMeasures: inout [Measure]
    ) {
        let removedMeasureID = removedMeasure.id
        var removedCueTextIDs = Set(removedMeasure.cueTextIDs)
        removedCueTextIDs.formUnion(
            cueTexts
                .filter { $0.anchorMeasureID == removedMeasureID }
                .map(\.id)
        )

        var removedRoadmapObjectIDs = Set(removedMeasure.roadmapObjectIDs)
        removedRoadmapObjectIDs.formUnion(
            roadmapObjects
                .filter {
                    $0.startMeasureID == removedMeasureID
                        || $0.endMeasureID == removedMeasureID
                }
                .map(\.id)
        )

        sectionLabels.removeAll { $0.anchorMeasureID == removedMeasureID }
        cueTexts.removeAll {
            $0.anchorMeasureID == removedMeasureID || removedCueTextIDs.contains($0.id)
        }
        roadmapObjects.removeAll { removedRoadmapObjectIDs.contains($0.id) }
        clearRoadmapLinks(toDeletedRoadmapObjectIDs: removedRoadmapObjectIDs)
        freehandSymbols.removeAll { $0.anchorMeasureID == removedMeasureID }

        for measureIndex in remainingMeasures.indices {
            remainingMeasures[measureIndex].cueTextIDs.removeAll { removedCueTextIDs.contains($0) }
            remainingMeasures[measureIndex].roadmapObjectIDs.removeAll { removedRoadmapObjectIDs.contains($0) }
        }
    }

    private func effectiveMeter(for measure: Measure) -> Meter {
        measure.meterOverride ?? defaultMeter
    }

    private mutating func rebuildSystems(
        using flattenedMeasures: [Measure],
        forcedBreakStartIDsOverride: Set<UUID>? = nil
    ) {
        ensureInitialSystem()

        let systemTemplates = systems.map {
            (id: $0.id, spacingMode: $0.spacingMode, lineBreakRule: $0.lineBreakRule)
        }
        timeSignatureChanges = normalizedTimeSignatureChanges(for: flattenedMeasures)

        var normalizedMeasures = synchronizedMeterOverrides(in: flattenedMeasures)
        for measureIndex in normalizedMeasures.indices {
            normalizedMeasures[measureIndex].index = measureIndex + 1
        }
        if supportsManualSystemBreaks {
            let forcedBreakStartIDs = forcedBreakStartIDsOverride
                ?? currentForcedSystemBreakStartIDs(in: normalizedMeasures)
            rebuildManualSystemBreakSystems(
                using: normalizedMeasures,
                systemTemplates: systemTemplates,
                forcedBreakStartIDs: forcedBreakStartIDs,
                measureCap: layoutStyle == .simpleChordSheet ? simpleSystemMeasureCap : nil
            )
            return
        }

        if normalizedMeasures.isEmpty {
            let template = systemTemplates.first ?? (UUID(), .automatic, .automatic)
            systems = [
                ChartSystem(
                    id: template.0,
                    index: 0,
                    spacingMode: template.1,
                    lineBreakRule: template.2,
                    measures: []
                )
            ]
            normalizeSystemIndices()
            normalizeAnchorsToSystems()
            return
        }

        var rebuiltSystems: [ChartSystem] = []
        var cursor = 0
        var systemIndex = 0
        while cursor < normalizedMeasures.count {
            let chunkEnd = min(cursor + 4, normalizedMeasures.count)
            let measuresChunk = Array(normalizedMeasures[cursor..<chunkEnd])
            let template = systemTemplates.indices.contains(systemIndex)
                ? systemTemplates[systemIndex]
                : (UUID(), .automatic, .automatic)

            rebuiltSystems.append(
                ChartSystem(
                    id: template.0,
                    index: systemIndex,
                    spacingMode: template.1,
                    lineBreakRule: template.2,
                    measures: measuresChunk
                )
            )
            cursor = chunkEnd
            systemIndex += 1
        }

        systems = rebuiltSystems
        normalizeSystemIndices()
        normalizeAnchorsToSystems()
    }

    private func currentForcedSystemBreakStartIDs(in normalizedMeasures: [Measure]) -> Set<UUID> {
        let measureIDs = Set(normalizedMeasures.map(\.id))
        return Set(
            systems
                .dropFirst()
                .filter { $0.lineBreakRule == .forced }
                .compactMap { system in
                    system.measures.first { measureIDs.contains($0.id) }?.id
                }
        )
    }

    private mutating func rebuildManualSystemBreakSystems(
        using normalizedMeasures: [Measure],
        systemTemplates: [(id: UUID, spacingMode: SpacingMode, lineBreakRule: LineBreakRule)],
        forcedBreakStartIDs: Set<UUID>,
        measureCap: Int?
    ) {
        let defaultSpacingMode = layoutStyle.profile.measureDefaults.systemSpacingMode
        var rebuiltSystems: [ChartSystem] = []
        var currentMeasures: [Measure] = []
        var currentLineBreakRule: LineBreakRule = .automatic

        func flushCurrentSystem() {
            guard !currentMeasures.isEmpty else {
                return
            }

            let systemIndex = rebuiltSystems.count
            let template = systemTemplates.indices.contains(systemIndex)
                ? systemTemplates[systemIndex]
                : (UUID(), defaultSpacingMode, currentLineBreakRule)
            rebuiltSystems.append(
                ChartSystem(
                    id: template.0,
                    index: systemIndex,
                    spacingMode: template.1,
                    lineBreakRule: systemIndex == 0 ? .automatic : currentLineBreakRule,
                    measures: currentMeasures
                )
            )
            currentMeasures = []
            currentLineBreakRule = .automatic
        }

        for measure in normalizedMeasures {
            if !currentMeasures.isEmpty && forcedBreakStartIDs.contains(measure.id) {
                flushCurrentSystem()
                currentLineBreakRule = .forced
            }

            if let measureCap,
               !currentMeasures.isEmpty,
               currentMeasures.count >= measureCap {
                flushCurrentSystem()
            }

            currentMeasures.append(measure)
        }

        flushCurrentSystem()

        if rebuiltSystems.isEmpty {
            let template = systemTemplates.first ?? (UUID(), defaultSpacingMode, .automatic)
            rebuiltSystems = [
                ChartSystem(
                    id: template.0,
                    index: 0,
                    spacingMode: template.1,
                    lineBreakRule: .automatic,
                    measures: []
                )
            ]
        }

        systems = rebuiltSystems
        normalizeSystemIndices()
        normalizeAnchorsToSystems()
    }

    private mutating func ensureMeasuresExist(afterMeasureAt sourceIndex: Int, count requiredFollowingMeasures: Int) {
        guard requiredFollowingMeasures > 0 else {
            return
        }

        while measures.count - sourceIndex - 1 < requiredFollowingMeasures {
            if let lastMeasure = measures.last,
               lastMeasure.authoringState == .open {
                _ = commitOpenMeasure()
            } else {
                _ = appendMeasure(authoringState: .open)
            }
        }
    }

    private func timeSignatureChange(after measureID: UUID) -> TimeSignatureChange? {
        timeSignatureChanges.first(where: { $0.afterMeasureID == measureID })
    }

    private mutating func setTimeSignatureChange(after measureID: UUID, meter: Meter) {
        timeSignatureChanges.removeAll { $0.afterMeasureID == measureID }
        timeSignatureChanges.append(
            TimeSignatureChange(
                id: UUID(),
                afterMeasureID: measureID,
                meter: meter
            )
        )
    }

    private mutating func removeTimeSignatureChanges(afterMeasureIndexGreaterThan index: Int) {
        let measureIDs = Array(measures.suffix(from: max(index + 1, 0))).map(\.id)
        let measureIDSet = Set(measureIDs)
        timeSignatureChanges.removeAll { measureIDSet.contains($0.afterMeasureID) }
    }

    private mutating func removeTimeSignatureChanges(afterMeasureIndexIn range: Range<Int>) {
        guard !range.isEmpty else {
            return
        }

        let lowerBound = max(range.lowerBound, 0)
        let upperBound = min(range.upperBound, measures.count)
        guard lowerBound < upperBound else {
            return
        }

        let measureIDSet = Set(measures[lowerBound..<upperBound].map(\.id))
        timeSignatureChanges.removeAll { measureIDSet.contains($0.afterMeasureID) }
    }

    private func normalizedTimeSignatureChanges(for flattenedMeasures: [Measure]) -> [TimeSignatureChange] {
        let validMeasureIDs = Set(flattenedMeasures.map(\.id))
        var normalizedChanges: [TimeSignatureChange] = []

        for change in timeSignatureChanges where validMeasureIDs.contains(change.afterMeasureID) {
            normalizedChanges.removeAll { $0.afterMeasureID == change.afterMeasureID }
            normalizedChanges.append(change)
        }

        return normalizedChanges
    }

    private func synchronizedMeterOverrides(in flattenedMeasures: [Measure]) -> [Measure] {
        guard !flattenedMeasures.isEmpty else {
            return flattenedMeasures
        }

        let meterByAnchorMeasureID = Dictionary(
            uniqueKeysWithValues: normalizedTimeSignatureChanges(for: flattenedMeasures)
                .map { ($0.afterMeasureID, $0.meter) }
        )

        var activeMeter = defaultMeter
        return flattenedMeasures.enumerated().map { measureIndex, sourceMeasure in
            if measureIndex > 0,
               let changedMeter = meterByAnchorMeasureID[flattenedMeasures[measureIndex - 1].id] {
                activeMeter = changedMeter
            }

            var measure = sourceMeasure
            measure.meterOverride = activeMeter == defaultMeter ? nil : activeMeter
            return measure
        }
    }

    private mutating func normalizeAnchorsToSystems() {
        let systemIDByMeasureID = systems.reduce(into: [UUID: UUID]()) { partialResult, system in
            for measure in system.measures {
                partialResult[measure.id] = system.id
            }
        }

        for sectionLabelIndex in sectionLabels.indices {
            guard let systemID = systemIDByMeasureID[sectionLabels[sectionLabelIndex].anchorMeasureID] else {
                continue
            }

            sectionLabels[sectionLabelIndex].anchorSystemID = systemID
        }

        for roadmapObjectIndex in roadmapObjects.indices {
            let startMeasureID = roadmapObjects[roadmapObjectIndex].startMeasureID
            let endMeasureID = roadmapObjects[roadmapObjectIndex].endMeasureID
            let resolvedSystemID = systemIDByMeasureID[startMeasureID]
                ?? endMeasureID.flatMap { systemIDByMeasureID[$0] }

            guard let resolvedSystemID else {
                continue
            }

            roadmapObjects[roadmapObjectIndex].anchorSystemID = resolvedSystemID
        }
    }
}

enum MeasureRhythmReplacementResult: Hashable {
    case applied
    case unchanged
    case missingMeasure
    case missingRhythmMap
    case invalidNoteIndex
    case unsupportedRhythmValue
    case invalidMeterFit(MeasureRhythmMapStatus)

    var didApply: Bool {
        switch self {
        case .applied, .unchanged:
            return true
        case .missingMeasure, .missingRhythmMap, .invalidNoteIndex, .unsupportedRhythmValue, .invalidMeterFit:
            return false
        }
    }
}

import CoreGraphics
import Foundation

extension Chart {
    mutating func completeInitialSetup(
        title: String,
        key: DocumentKey,
        meter: Meter,
        staffStyle: StaffStyle
    ) {
        self.title = title
        documentKey = key
        defaultMeter = meter
        self.staffStyle = staffStyle
        timeSignatureChanges = []
        ensureInitialSystem()
        if measures.isEmpty {
            systems[0].measures = [
                Self.makeMeasure(index: 1, authoringState: .open)
            ]
        }
        hasCompletedInitialSetup = true
        updatedAt = .now
    }

    mutating func setDocumentFont(_ preset: ChartFontPreset) {
        documentFont = preset
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

    mutating func setEngravingPreset(_ preset: EngravingPreset) {
        engravingPreset = preset
        updatedAt = .now
    }

    mutating func setDocumentKey(_ key: DocumentKey) {
        documentKey = key
        updatedAt = .now
    }

    mutating func setTranspositionView(_ view: TranspositionView) {
        defaultTranspositionView = view
        updatedAt = .now
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
            barlineAfter: barlineAfter
        )
        appendPreparedMeasure(newMeasure)
        updatedAt = .now
        return newMeasure.id
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
    mutating func commitOpenMeasure() -> UUID? {
        guard let location = openMeasureLocation() else {
            return nil
        }

        systems[location.systemIndex].measures[location.measureIndex].authoringState = .committed
        let newMeasure = Self.makeMeasure(index: measures.count + 1, authoringState: .open)
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
            openMeasure = Self.makeMeasure(index: measures.count + 1, authoringState: .open)
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

    mutating func addCueText(_ text: String) {
        guard !systems.isEmpty, !systems[0].measures.isEmpty else {
            return
        }

        let firstMeasure = systems[0].measures[0]
        let cue = CueText(
            id: UUID(),
            text: text,
            anchorMeasureID: firstMeasure.id,
            position: .below,
            emphasis: .normal,
            rawInput: text
        )

        cueTexts.append(
            cue
        )
        systems[0].measures[0].cueTextIDs.append(cue.id)

        updatedAt = .now
    }

    mutating func addRoadmapObject(_ type: RoadmapType, displayText: String? = nil) {
        guard !systems.isEmpty, !systems[0].measures.isEmpty else {
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
        barlineAfter: BarlineType = .single
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
            && measure.cueTextIDs.isEmpty
            && measure.roadmapObjectIDs.isEmpty
    }

    private mutating func removeMeasure(
        at location: (systemIndex: Int, measureIndex: Int)
    ) {
        let removalIndex = flattenedMeasureIndex(for: location)
        var flattenedMeasures = measures
        guard flattenedMeasures.indices.contains(removalIndex) else {
            return
        }

        flattenedMeasures.remove(at: removalIndex)
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

    private func effectiveMeter(for measure: Measure) -> Meter {
        measure.meterOverride ?? defaultMeter
    }

    private mutating func rebuildSystems(using flattenedMeasures: [Measure]) {
        ensureInitialSystem()

        let systemTemplates = systems.map {
            (id: $0.id, spacingMode: $0.spacingMode, lineBreakRule: $0.lineBreakRule)
        }
        timeSignatureChanges = normalizedTimeSignatureChanges(for: flattenedMeasures)

        var normalizedMeasures = synchronizedMeterOverrides(in: flattenedMeasures)
        for measureIndex in normalizedMeasures.indices {
            normalizedMeasures[measureIndex].index = measureIndex + 1
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

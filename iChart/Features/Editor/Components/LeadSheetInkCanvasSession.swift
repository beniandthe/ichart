#if canImport(UIKit)
import Foundation
import PencilKit
import UIKit

enum LeadSheetPassiveInkPersistencePolicy {
    static let defaultIdleDelay: TimeInterval = 0.95
    static let denseInkStrokeThreshold = 48
    static let maximumIdleDelay: TimeInterval = 1.65

    static func idleDelay(
        for activeInkScope: LeadSheetActiveInkScope?,
        strokeCount: Int = 0
    ) -> TimeInterval {
        guard activeInkScope?.persistsDrawingData == true,
              strokeCount > denseInkStrokeThreshold else {
            return defaultIdleDelay
        }

        let denseStrokeProgress = min(
            1,
            Double(strokeCount - denseInkStrokeThreshold) / 64
        )
        return defaultIdleDelay
            + (maximumIdleDelay - defaultIdleDelay) * denseStrokeProgress
    }
}

enum LeadSheetSavedInkCanvasReloadPolicy {
    static let geometrySettleDelay: TimeInterval = 0.05

    static func targetCoordinateSpacesAreEquivalent(
        sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        currentTargetCoordinateSpace: PersistentInkCoordinateSpace?,
        proposedTargetCoordinateSpace: PersistentInkCoordinateSpace?
    ) -> Bool {
        relevantTargetCoordinateSpace(
            currentTargetCoordinateSpace,
            sourceCoordinateSpace: sourceCoordinateSpace
        ) == relevantTargetCoordinateSpace(
            proposedTargetCoordinateSpace,
            sourceCoordinateSpace: sourceCoordinateSpace
        )
    }

    private static func relevantTargetCoordinateSpace(
        _ targetCoordinateSpace: PersistentInkCoordinateSpace?,
        sourceCoordinateSpace: PersistentInkCoordinateSpace?
    ) -> PersistentInkCoordinateSpace? {
        guard var targetCoordinateSpace else {
            return nil
        }

        // A newly rendered chord cannot own ink that was saved before that
        // chord existed. Ignore target-only chord anchors in the passive-canvas
        // cache key so rendering a chord does not reproject every saved page
        // stroke. Matching source chord anchors, measure anchors, and page size
        // remain authoritative and still invalidate the cache when they move.
        let sourceChordIDs = Set(
            (sourceCoordinateSpace?.chordAnchors ?? []).map(\.chordID)
        )
        let relevantChordAnchors = (targetCoordinateSpace.chordAnchors ?? []).filter {
            sourceChordIDs.contains($0.chordID)
        }
        targetCoordinateSpace.chordAnchors = relevantChordAnchors.isEmpty
            ? nil
            : relevantChordAnchors
        return targetCoordinateSpace
    }
}

struct LeadSheetSavedInkCanvasState: Equatable {
    let drawingData: Data
    let sourceCoordinateSpace: PersistentInkCoordinateSpace?
    let targetCoordinateSpace: PersistentInkCoordinateSpace?
    let frame: CGRect

    static func == (
        lhs: LeadSheetSavedInkCanvasState,
        rhs: LeadSheetSavedInkCanvasState
    ) -> Bool {
        lhs.drawingData == rhs.drawingData
            && lhs.sourceCoordinateSpace == rhs.sourceCoordinateSpace
            && lhs.frame == rhs.frame
            && LeadSheetSavedInkCanvasReloadPolicy.targetCoordinateSpacesAreEquivalent(
                sourceCoordinateSpace: lhs.sourceCoordinateSpace,
                currentTargetCoordinateSpace: lhs.targetCoordinateSpace,
                proposedTargetCoordinateSpace: rhs.targetCoordinateSpace
            )
    }
}

struct LeadSheetSavedInkPreparationRequest {
    var drawingData: Data
    var sourceCoordinateSpace: PersistentInkCoordinateSpace?
    var targetCoordinateSpace: PersistentInkCoordinateSpace?
}

struct LeadSheetSavedInkPreparationResult {
    var drawing: PKDrawing
    var strokeCount: Int
    var durationMilliseconds: Double
}

enum LeadSheetSavedInkPreparation {
    static func prepare(
        _ request: LeadSheetSavedInkPreparationRequest
    ) -> LeadSheetSavedInkPreparationResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let drawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            from: request.drawingData,
            sourceCoordinateSpace: request.sourceCoordinateSpace,
            targetCoordinateSpace: request.targetCoordinateSpace
        ) ?? PKDrawing()
        return LeadSheetSavedInkPreparationResult(
            drawing: drawing,
            strokeCount: drawing.strokes.count,
            durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
    }
}

final class LeadSheetSavedInkPreparationSession {
    private let queue: DispatchQueue
    private let operationLock = NSLock()
    private var activeOperationID: UUID?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(
        request: LeadSheetSavedInkPreparationRequest,
        after delay: TimeInterval,
        completion: @escaping (LeadSheetSavedInkPreparationResult) -> Void
    ) {
        let operationID = beginOperation()
        queue.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            guard let self,
                  self.isActive(operationID) else {
                return
            }
            let result = LeadSheetSavedInkPreparation.prepare(request)
            guard self.isActive(operationID) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard self?.finishOperation(operationID) == true else {
                    return
                }
                completion(result)
            }
        }
    }

    func cancelPendingWork() {
        operationLock.lock()
        activeOperationID = nil
        operationLock.unlock()
    }

    private func beginOperation() -> UUID {
        let operationID = UUID()
        operationLock.lock()
        activeOperationID = operationID
        operationLock.unlock()
        return operationID
    }

    private func isActive(_ operationID: UUID) -> Bool {
        operationLock.lock()
        defer { operationLock.unlock() }
        return activeOperationID == operationID
    }

    private func finishOperation(_ operationID: UUID) -> Bool {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard activeOperationID == operationID else {
            return false
        }
        activeOperationID = nil
        return true
    }
}

struct LeadSheetInkSerializationRequest {
    var drawing: PKDrawing
    var normalizesPersistentInk: Bool
    var capturesSnapshot: Bool
    var knownStrokeCount: Int? = nil
}

struct LeadSheetInkSerializationResult {
    var serialization: LeadSheetPersistentInkSerialization
    var inkSnapshot: LeadSheetInkDrawingSnapshot?
    var strokeCount: Int
    var durationMilliseconds: Double
}

struct LeadSheetInkSerializationCache {
    private struct Entry {
        var drawingRevision: UInt64
        var scopeIdentity: LeadSheetActiveInkScope.Identity
        var serialization: LeadSheetPersistentInkSerialization
    }

    private var entry: Entry?

    mutating func record(
        _ serialization: LeadSheetPersistentInkSerialization,
        drawingRevision: UInt64,
        scopeIdentity: LeadSheetActiveInkScope.Identity
    ) {
        entry = Entry(
            drawingRevision: drawingRevision,
            scopeIdentity: scopeIdentity,
            serialization: serialization
        )
    }

    func serialization(
        drawingRevision: UInt64,
        scopeIdentity: LeadSheetActiveInkScope.Identity
    ) -> LeadSheetPersistentInkSerialization? {
        guard let entry,
              entry.drawingRevision == drawingRevision,
              entry.scopeIdentity == scopeIdentity else {
            return nil
        }

        return entry.serialization
    }

    mutating func invalidate() {
        entry = nil
    }
}

enum LeadSheetInkSerialization {
    static func serialize(
        _ request: LeadSheetInkSerializationRequest
    ) -> LeadSheetInkSerializationResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let strokeCount = request.knownStrokeCount ?? request.drawing.strokes.count
        let serialization: LeadSheetPersistentInkSerialization
        if request.normalizesPersistentInk {
            serialization = LeadSheetPersistentInkColorPolicy.serialization(for: request.drawing)
        } else {
            serialization = LeadSheetPersistentInkSerialization(
                drawingData: strokeCount == 0 ? nil : request.drawing.dataRepresentation(),
                normalizationNeeded: false
            )
        }
        return LeadSheetInkSerializationResult(
            serialization: serialization,
            inkSnapshot: request.capturesSnapshot
                ? LeadSheetInkDrawingSnapshot(drawing: request.drawing)
                : nil,
            strokeCount: strokeCount,
            durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
    }
}

final class LeadSheetInkSerializationSession {
    private let queue: DispatchQueue
    private let operationLock = NSLock()
    private var activeOperationID: UUID?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(
        request: LeadSheetInkSerializationRequest,
        completion: @escaping (LeadSheetInkSerializationResult) -> Void
    ) {
        let operationID = beginOperation()
        queue.async { [weak self] in
            guard let self,
                  self.isActive(operationID) else {
                return
            }
            let result = LeadSheetInkSerialization.serialize(request)
            guard self.isActive(operationID) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard self?.finishOperation(operationID) == true else {
                    return
                }
                completion(result)
            }
        }
    }

    func cancelPendingWork() {
        operationLock.lock()
        activeOperationID = nil
        operationLock.unlock()
    }

    private func beginOperation() -> UUID {
        let operationID = UUID()
        operationLock.lock()
        activeOperationID = operationID
        operationLock.unlock()
        return operationID
    }

    private func isActive(_ operationID: UUID) -> Bool {
        operationLock.lock()
        defer { operationLock.unlock() }
        return activeOperationID == operationID
    }

    private func finishOperation(_ operationID: UUID) -> Bool {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard activeOperationID == operationID else {
            return false
        }
        activeOperationID = nil
        return true
    }
}

struct LeadSheetInkDrawingSnapshot: Equatable {
    private struct StrokeSignature: Equatable {
        var pointCount: Int
        var bounds: CGRect
        var sampledPoints: [CGPoint]
    }

    private var strokeSignatures: [StrokeSignature]

    init?(drawing: PKDrawing) {
        let signatures = drawing.strokes.compactMap { stroke -> StrokeSignature? in
            let path = stroke.path
            let pointCount = path.count
            guard pointCount > 0 else {
                return nil
            }

            let sampleOffsets = Set([
                0,
                pointCount / 4,
                pointCount / 2,
                (pointCount * 3) / 4,
                pointCount - 1
            ]).sorted()
            let sampledPoints = sampleOffsets.map { offset in
                let index = path.index(path.startIndex, offsetBy: offset)
                return Self.rounded(path[index].location)
            }

            return StrokeSignature(
                pointCount: pointCount,
                bounds: Self.rounded(stroke.renderBounds),
                sampledPoints: sampledPoints
            )
        }

        guard !signatures.isEmpty else {
            return nil
        }

        strokeSignatures = signatures
    }

    init(testValues: [Int]) {
        strokeSignatures = testValues.map { value in
            StrokeSignature(
                pointCount: value,
                bounds: CGRect(x: value, y: value, width: value, height: value),
                sampledPoints: [
                    CGPoint(x: value, y: value),
                    CGPoint(x: value + 1, y: value + 1)
                ]
            )
        }
    }

    private static func rounded(_ point: CGPoint) -> CGPoint {
        CGPoint(x: rounded(point.x), y: rounded(point.y))
    }

    private static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rounded(rect.origin.x),
            y: rounded(rect.origin.y),
            width: rounded(rect.size.width),
            height: rounded(rect.size.height)
        )
    }

    private static func rounded(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

struct LeadSheetPersistedInkSnapshot: Equatable {
    var inkSnapshot: LeadSheetInkDrawingSnapshot?
    var coordinateSpace: PersistentInkCoordinateSpace?
}

enum LeadSheetInkPersistenceDedupePolicy {
    static func shouldSkipPersistence(
        activeInkScope: LeadSheetActiveInkScope,
        currentSnapshot: LeadSheetPersistedInkSnapshot,
        lastPersistedSnapshot: LeadSheetPersistedInkSnapshot?
    ) -> Bool {
        guard activeInkScope.persistsDrawingData,
              LeadSheetInkAuthoringSessionRole.resolve(activeInkScope: activeInkScope) == .passive,
              let lastPersistedSnapshot else {
            return false
        }

        return currentSnapshot == lastPersistedSnapshot
    }
}

struct LeadSheetInkPipelineMetrics {
    private static let flushEventThreshold = 40
    private static let flushInterval: TimeInterval = 5

    private var drawingChangeCount = 0
    private var scheduledWorkCount = 0
    private var syncLoadCount = 0
    private var persistenceAttemptCount = 0
    private var skippedPersistenceCount = 0
    private var manualEraseSampleCount = 0
    private var manualEraseCandidateCount = 0
    private var manualEraseRemovedStrokeCount = 0
    private var maxStrokeCount = 0
    private var maxPersistedBytes = 0
    private var maxPersistenceDurationMilliseconds = 0.0
    private var maxManualEraseDurationMilliseconds = 0.0
    private var lastFlushUptime = ProcessInfo.processInfo.systemUptime

    mutating func recordDrawingChange(strokeCount: Int) {
        drawingChangeCount += 1
        maxStrokeCount = max(maxStrokeCount, strokeCount)
        flushIfNeeded(reason: "drawing_change")
    }

    mutating func recordScheduledWork(strokeCount: Int) {
        scheduledWorkCount += 1
        maxStrokeCount = max(maxStrokeCount, strokeCount)
        flushIfNeeded(reason: "scheduled_work")
    }

    mutating func recordSyncLoad(strokeCount: Int) {
        syncLoadCount += 1
        maxStrokeCount = max(maxStrokeCount, strokeCount)
        flushIfNeeded(reason: "sync_load")
    }

    mutating func recordPersistence(
        strokeCount: Int,
        bytes: Int,
        durationMilliseconds: Double
    ) {
        persistenceAttemptCount += 1
        maxStrokeCount = max(maxStrokeCount, strokeCount)
        maxPersistedBytes = max(maxPersistedBytes, bytes)
        maxPersistenceDurationMilliseconds = max(maxPersistenceDurationMilliseconds, durationMilliseconds)
        flushIfNeeded(reason: "persistence")
    }

    mutating func recordSkippedPersistence(strokeCount: Int) {
        skippedPersistenceCount += 1
        maxStrokeCount = max(maxStrokeCount, strokeCount)
        flushIfNeeded(reason: "skipped_persistence")
    }

    mutating func recordManualErase(
        strokeCount: Int,
        candidateCount: Int,
        removedStrokeCount: Int,
        durationMilliseconds: Double
    ) {
        manualEraseSampleCount += 1
        manualEraseCandidateCount += candidateCount
        manualEraseRemovedStrokeCount += removedStrokeCount
        maxStrokeCount = max(maxStrokeCount, strokeCount)
        maxManualEraseDurationMilliseconds = max(
            maxManualEraseDurationMilliseconds,
            durationMilliseconds
        )
        flushIfNeeded(reason: "manual_erase")
    }

    mutating func flush(reason: String) {
        guard hasEvents else {
            return
        }

        IChartPerformanceTrace.record(
            "ink.pipeline.aggregate",
            metadata: [
                "reason": reason,
                "drawing_changes": "\(drawingChangeCount)",
                "scheduled_work": "\(scheduledWorkCount)",
                "sync_loads": "\(syncLoadCount)",
                "persistence_attempts": "\(persistenceAttemptCount)",
                "skipped_persistence": "\(skippedPersistenceCount)",
                "erase_samples": "\(manualEraseSampleCount)",
                "erase_candidates": "\(manualEraseCandidateCount)",
                "erase_removed_strokes": "\(manualEraseRemovedStrokeCount)",
                "max_strokes": "\(maxStrokeCount)",
                "max_bytes": "\(maxPersistedBytes)",
                "max_persist_ms": String(format: "%.2f", maxPersistenceDurationMilliseconds),
                "max_erase_ms": String(format: "%.2f", maxManualEraseDurationMilliseconds)
            ]
        )
        reset()
    }

    private var hasEvents: Bool {
        drawingChangeCount > 0
            || scheduledWorkCount > 0
            || syncLoadCount > 0
            || persistenceAttemptCount > 0
            || skippedPersistenceCount > 0
            || manualEraseSampleCount > 0
    }

    private mutating func flushIfNeeded(reason: String) {
        let eventCount = drawingChangeCount
            + scheduledWorkCount
            + syncLoadCount
            + persistenceAttemptCount
            + skippedPersistenceCount
            + manualEraseSampleCount
        let now = ProcessInfo.processInfo.systemUptime
        guard eventCount >= Self.flushEventThreshold
                || now - lastFlushUptime >= Self.flushInterval else {
            return
        }

        flush(reason: reason)
    }

    private mutating func reset() {
        drawingChangeCount = 0
        scheduledWorkCount = 0
        syncLoadCount = 0
        persistenceAttemptCount = 0
        skippedPersistenceCount = 0
        manualEraseSampleCount = 0
        manualEraseCandidateCount = 0
        manualEraseRemovedStrokeCount = 0
        maxStrokeCount = 0
        maxPersistedBytes = 0
        maxPersistenceDurationMilliseconds = 0
        maxManualEraseDurationMilliseconds = 0
        lastFlushUptime = ProcessInfo.processInfo.systemUptime
    }
}

enum LeadSheetInkAuthoringSessionRole: Hashable {
    case chord
    case rhythm
    case passive

    static func resolve(
        activeInkScope: LeadSheetActiveInkScope,
        interactionMode: EditorCanvasMode
    ) -> LeadSheetInkAuthoringSessionRole? {
        guard let role = resolve(activeInkScope: activeInkScope),
              role.isEnabled(in: interactionMode) else {
            return nil
        }

        return role
    }

    static func resolve(activeInkScope: LeadSheetActiveInkScope) -> LeadSheetInkAuthoringSessionRole? {
        switch activeInkScope {
        case .chords:
            return .chord
        case .rhythmicMeasure:
            return .rhythm
        case .page, .header:
            return .passive
        case .noteSelection:
            return nil
        }
    }

    func isEnabled(in interactionMode: EditorCanvasMode) -> Bool {
        switch self {
        case .chord:
            return interactionMode.allowsChordInkEditing
        case .rhythm:
            return interactionMode.allowsDirectRhythmicNotationInk
        case .passive:
            return interactionMode.allowsPassiveInkPersistence
        }
    }
}

struct LeadSheetInkAuthoringSessionState {
    private var dirtyRoles: Set<LeadSheetInkAuthoringSessionRole> = []

    mutating func markDirty(_ role: LeadSheetInkAuthoringSessionRole) {
        dirtyRoles.insert(role)
    }

    mutating func clear(_ role: LeadSheetInkAuthoringSessionRole) {
        dirtyRoles.remove(role)
    }

    func isDirty(_ role: LeadSheetInkAuthoringSessionRole) -> Bool {
        dirtyRoles.contains(role)
    }
}

struct LeadSheetPendingPersistedInk: Equatable {
    var drawingData: Data?
    var coordinateSpace: PersistentInkCoordinateSpace?
}

enum LeadSheetPendingPersistedInkPolicy {
    static func shouldApplyPendingInk(
        incomingInk: LeadSheetPendingPersistedInk,
        pendingInk: LeadSheetPendingPersistedInk
    ) -> Bool {
        incomingInk != pendingInk
    }

    static func shouldRetainPendingInk(
        incomingInk: LeadSheetPendingPersistedInk,
        pendingInk: LeadSheetPendingPersistedInk
    ) -> Bool {
        incomingInk != pendingInk
    }

    static func shouldRecordEraseTombstone(
        activeInkScope: LeadSheetActiveInkScope,
        drawingData: Data?,
        isDirtyAuthoringRole: Bool
    ) -> Bool {
        activeInkScope.persistsDrawingData
            && drawingData == nil
            && isDirtyAuthoringRole
    }
}

struct LeadSheetActiveInkEraseQueryResult {
    var strokeIndices: Set<Int>
    var candidateCount: Int
    var totalStrokeCount: Int
}

struct LeadSheetActiveInkErasePreparationResult {
    var spatialIndex: LeadSheetActiveInkEraseSpatialIndex
    var strokeCount: Int
    var durationMilliseconds: Double
    var preparedOnMainThread: Bool
}

struct LeadSheetActiveInkErasePreparationIdentity: Equatable {
    var drawingRevision: UInt64
    var scopeIdentity: LeadSheetActiveInkScope.Identity
}

final class LeadSheetActiveInkErasePreparationSession {
    private let queue: DispatchQueue
    private let operationLock = NSLock()
    private var activeOperationID: UUID?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(
        drawing: PKDrawing,
        completion: @escaping (LeadSheetActiveInkErasePreparationResult) -> Void
    ) {
        let operationID = beginOperation()
        queue.async { [weak self] in
            guard let self,
                  self.isActive(operationID) else {
                return
            }
            let startedAt = ProcessInfo.processInfo.systemUptime
            let preparedOnMainThread = Thread.isMainThread
            let spatialIndex = LeadSheetActiveInkEraseSpatialIndex(drawing: drawing)
            let result = LeadSheetActiveInkErasePreparationResult(
                spatialIndex: spatialIndex,
                strokeCount: spatialIndex.strokeCount,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000,
                preparedOnMainThread: preparedOnMainThread
            )
            guard self.isActive(operationID) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard self?.finishOperation(operationID) == true else {
                    return
                }
                completion(result)
            }
        }
    }

    func cancelPendingWork() {
        operationLock.lock()
        activeOperationID = nil
        operationLock.unlock()
    }

    private func beginOperation() -> UUID {
        let operationID = UUID()
        operationLock.lock()
        activeOperationID = operationID
        operationLock.unlock()
        return operationID
    }

    private func isActive(_ operationID: UUID) -> Bool {
        operationLock.lock()
        defer { operationLock.unlock() }
        return activeOperationID == operationID
    }

    private func finishOperation(_ operationID: UUID) -> Bool {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard activeOperationID == operationID else {
            return false
        }
        activeOperationID = nil
        return true
    }
}

struct LeadSheetActiveInkEraseSpatialIndex {
    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    private static let cellSize: CGFloat = 72

    // Cell membership uses stable IDs from the original drawing. During one
    // erase gesture, surviving strokes keep those IDs even though their
    // PKDrawing array indices shift. That lets us remove strokes incrementally
    // without rebuilding every renderBounds/cell entry between touch samples.
    private var strokes: [PKStroke]
    private var activeStrokeIDs: [Int]
    private var currentIndexByStrokeID: [Int: Int]
    private var strokeIDsByCell: [Cell: [Int]]

    init(drawing: PKDrawing, radius: CGFloat = LeadSheetActiveInkErasePolicy.eraseRadius) {
        strokes = drawing.strokes
        activeStrokeIDs = Array(strokes.indices)
        currentIndexByStrokeID = Dictionary(
            uniqueKeysWithValues: strokes.indices.map { ($0, $0) }
        )
        strokeIDsByCell = [:]
        strokeIDsByCell.reserveCapacity(strokes.count * 2)

        for (strokeID, stroke) in strokes.enumerated() {
            let searchableBounds = stroke.renderBounds.insetBy(dx: -radius, dy: -radius)
            for cell in Self.cells(intersecting: searchableBounds) {
                strokeIDsByCell[cell, default: []].append(strokeID)
            }
        }
    }

    var strokeCount: Int {
        activeStrokeIDs.count
    }

    mutating func removeStrokes(at currentIndices: Set<Int>) {
        guard !currentIndices.isEmpty else {
            return
        }

        let removedStrokeIDs = Set(currentIndices.compactMap { currentIndex in
            activeStrokeIDs.indices.contains(currentIndex)
                ? activeStrokeIDs[currentIndex]
                : nil
        })
        guard !removedStrokeIDs.isEmpty else {
            return
        }

        activeStrokeIDs.removeAll { removedStrokeIDs.contains($0) }
        currentIndexByStrokeID.removeAll(keepingCapacity: true)
        currentIndexByStrokeID.reserveCapacity(activeStrokeIDs.count)
        for (currentIndex, strokeID) in activeStrokeIDs.enumerated() {
            currentIndexByStrokeID[strokeID] = currentIndex
        }
    }

    func query(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        radius: CGFloat = LeadSheetActiveInkErasePolicy.eraseRadius
    ) -> LeadSheetActiveInkEraseQueryResult {
        let eraseBounds = LeadSheetActiveInkErasePolicy.eraseBounds(
            from: startPoint,
            to: endPoint,
            radius: radius
        )
        let candidateStrokeIDs = Set(
            Self.cells(intersecting: eraseBounds).flatMap { cell in
                strokeIDsByCell[cell] ?? []
            }
        )
        let activeCandidateStrokeIDs = Set(candidateStrokeIDs.filter { strokeID in
            currentIndexByStrokeID[strokeID] != nil
        })
        let erasedStrokeIDs = LeadSheetActiveInkErasePolicy.strokeIndicesToErase(
            in: strokes,
            candidateIndices: activeCandidateStrokeIDs,
            from: startPoint,
            to: endPoint,
            radius: radius
        )
        let erasedCurrentIndices = Set(erasedStrokeIDs.compactMap { strokeID in
            currentIndexByStrokeID[strokeID]
        })
        return LeadSheetActiveInkEraseQueryResult(
            strokeIndices: erasedCurrentIndices,
            candidateCount: activeCandidateStrokeIDs.count,
            totalStrokeCount: activeStrokeIDs.count
        )
    }

    private static func cells(intersecting rect: CGRect) -> [Cell] {
        let bounds = rect.standardized
        guard !bounds.isNull,
              !bounds.isEmpty,
              !bounds.isInfinite,
              bounds.minX.isFinite,
              bounds.maxX.isFinite,
              bounds.minY.isFinite,
              bounds.maxY.isFinite else {
            return []
        }

        let minimumX = Int(floor(bounds.minX / cellSize))
        let maximumX = Int(floor(bounds.maxX / cellSize))
        let minimumY = Int(floor(bounds.minY / cellSize))
        let maximumY = Int(floor(bounds.maxY / cellSize))
        var cells = [Cell]()
        cells.reserveCapacity((maximumX - minimumX + 1) * (maximumY - minimumY + 1))
        for y in minimumY...maximumY {
            for x in minimumX...maximumX {
                cells.append(Cell(x: x, y: y))
            }
        }
        return cells
    }
}

enum LeadSheetActiveInkErasePolicy {
    static let eraseRadius: CGFloat = 18

    static func strokeIndicesToErase(
        in drawing: PKDrawing,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        radius: CGFloat = eraseRadius
    ) -> Set<Int> {
        let strokes = drawing.strokes
        return strokeIndicesToErase(
            in: strokes,
            candidateIndices: Set(strokes.indices),
            from: startPoint,
            to: endPoint,
            radius: radius
        )
    }

    static func eraseBounds(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        radius: CGFloat = eraseRadius
    ) -> CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        ).insetBy(dx: -radius, dy: -radius)
    }

    static func strokeIndicesToErase(
        in strokes: [PKStroke],
        candidateIndices: Set<Int>,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        radius: CGFloat = eraseRadius
    ) -> Set<Int> {
        let eraseBounds = eraseBounds(
            from: startPoint,
            to: endPoint,
            radius: radius
        )

        return Set(candidateIndices.compactMap { index in
            guard strokes.indices.contains(index) else {
                return nil
            }
            let stroke = strokes[index]
            guard stroke.renderBounds.insetBy(dx: -radius, dy: -radius).intersects(eraseBounds),
                  strokeIntersectsEraseSegment(stroke, from: startPoint, to: endPoint, radius: radius) else {
                return nil
            }

            return index
        })
    }

    private static func strokeIntersectsEraseSegment(
        _ stroke: PKStroke,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        radius: CGFloat
    ) -> Bool {
        var pointIterator = stroke.path.makeIterator()
        guard let firstPoint = pointIterator.next()?.location else {
            return false
        }

        let threshold = radius * radius
        if distanceSquared(from: firstPoint, toSegmentStart: startPoint, segmentEnd: endPoint) <= threshold {
            return true
        }

        var previousPoint = firstPoint
        while let point = pointIterator.next()?.location {
            if distanceSquared(from: point, toSegmentStart: startPoint, segmentEnd: endPoint) <= threshold
                || distanceSquared(from: startPoint, toSegmentStart: previousPoint, segmentEnd: point) <= threshold
                || distanceSquared(from: endPoint, toSegmentStart: previousPoint, segmentEnd: point) <= threshold {
                return true
            }

            previousPoint = point
        }

        return false
    }

    private static func distanceSquared(
        from point: CGPoint,
        toSegmentStart startPoint: CGPoint,
        segmentEnd endPoint: CGPoint
    ) -> CGFloat {
        let segmentX = endPoint.x - startPoint.x
        let segmentY = endPoint.y - startPoint.y
        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY
        guard segmentLengthSquared > 0 else {
            return squaredDistance(from: point, to: startPoint)
        }

        let rawProjection = ((point.x - startPoint.x) * segmentX + (point.y - startPoint.y) * segmentY)
            / segmentLengthSquared
        let projection = min(1, max(0, rawProjection))
        let closestPoint = CGPoint(
            x: startPoint.x + projection * segmentX,
            y: startPoint.y + projection * segmentY
        )
        return squaredDistance(from: point, to: closestPoint)
    }

    private static func squaredDistance(from firstPoint: CGPoint, to secondPoint: CGPoint) -> CGFloat {
        let dx = firstPoint.x - secondPoint.x
        let dy = firstPoint.y - secondPoint.y
        return dx * dx + dy * dy
    }
}

enum LeadSheetInkAuthoringSessionPolicy {
    static func shouldPreserveActiveCanvas(
        activeInkScope: LeadSheetActiveInkScope,
        interactionMode: EditorCanvasMode,
        sessionState: LeadSheetInkAuthoringSessionState,
        currentDrawingData: Data?,
        desiredDrawingData: Data?
    ) -> Bool {
        guard currentDrawingData != desiredDrawingData,
              let role = LeadSheetInkAuthoringSessionRole.resolve(
                activeInkScope: activeInkScope,
                interactionMode: interactionMode
              ) else {
            return false
        }

        return sessionState.isDirty(role)
    }

    static func canUseScheduledSnapshot(
        currentInkSnapshot: LeadSheetInkDrawingSnapshot?,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) -> Bool {
        guard currentInkSnapshot != nil || scheduledInkSnapshot != nil else {
            return true
        }
        guard let currentInkSnapshot,
              let scheduledInkSnapshot else {
            return false
        }

        return currentInkSnapshot == scheduledInkSnapshot
    }
}

enum LeadSheetInkCanvasSyncPolicy {
    static func shouldPersistOutgoingCanvas(
        previousActiveInkScope: LeadSheetActiveInkScope?,
        nextActiveInkScope: LeadSheetActiveInkScope?
    ) -> Bool {
        guard let previousActiveInkScope,
              previousActiveInkScope.persistsDrawingData else {
            return false
        }

        return previousActiveInkScope.identity != nextActiveInkScope?.identity
    }

    static func shouldPreserveDirtyActiveCanvas(
        activeInkScope: LeadSheetActiveInkScope,
        interactionMode: EditorCanvasMode,
        sessionState: LeadSheetInkAuthoringSessionState,
        didSwitchInkScope: Bool = false
    ) -> Bool {
        guard !didSwitchInkScope,
              let role = LeadSheetInkAuthoringSessionRole.resolve(
                activeInkScope: activeInkScope,
                interactionMode: interactionMode
              ) else {
            return false
        }

        return sessionState.isDirty(role)
    }

    static func shouldReprojectActiveCanvas(
        currentScopeIdentity: LeadSheetActiveInkScope.Identity?,
        targetScopeIdentity: LeadSheetActiveInkScope.Identity,
        shouldPreserveDirtyActiveCanvas: Bool
    ) -> Bool {
        guard !shouldPreserveDirtyActiveCanvas else {
            return false
        }

        // A hidden canvas deliberately keeps its last drawing long enough for
        // persistence, but that drawing does not belong to a newly activated
        // scope. Reproject only when the resident pixels are already known to
        // represent the target scope; the normal model load below will install
        // the correct drawing for a fresh or switched scope.
        return currentScopeIdentity == targetScopeIdentity
    }

    static func shouldLoadIncomingCanvasDirectly(
        currentScopeIdentity: LeadSheetActiveInkScope.Identity?,
        targetScopeIdentity: LeadSheetActiveInkScope.Identity
    ) -> Bool {
        // A hidden/reused PKCanvasView can still contain hundreds of strokes
        // from Page or Chord mode after its trusted scope identity is cleared.
        // Do not serialize or snapshot those stale strokes merely to prove they
        // differ from the incoming scope. Prepare the incoming model drawing
        // once and install it directly.
        currentScopeIdentity != targetScopeIdentity
    }

    static func shouldPreserveActiveCanvas(
        activeInkScope: LeadSheetActiveInkScope,
        interactionMode: EditorCanvasMode,
        sessionState: LeadSheetInkAuthoringSessionState,
        currentDrawingData: Data?,
        desiredDrawingData: Data?,
        didSwitchInkScope: Bool = false
    ) -> Bool {
        guard !didSwitchInkScope else {
            return false
        }

        return LeadSheetInkAuthoringSessionPolicy.shouldPreserveActiveCanvas(
            activeInkScope: activeInkScope,
            interactionMode: interactionMode,
            sessionState: sessionState,
            currentDrawingData: currentDrawingData,
            desiredDrawingData: desiredDrawingData
        )
    }

    static func shouldTreatCanvasAsSynced(
        currentInkSnapshot: LeadSheetInkDrawingSnapshot?,
        desiredDrawingData: Data?
    ) -> Bool {
        guard let desiredDrawingData else {
            return currentInkSnapshot == nil
        }

        guard let desiredDrawing = try? PKDrawing(data: desiredDrawingData) else {
            return false
        }

        return LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
            currentInkSnapshot: currentInkSnapshot,
            scheduledInkSnapshot: LeadSheetInkDrawingSnapshot(drawing: desiredDrawing)
        )
    }
}

enum LeadSheetLiveInkNormalizationPolicy {
    static func shouldNormalizeLiveCanvas(
        activeInkRole: LeadSheetInkAuthoringSessionRole?,
        sessionState: LeadSheetInkAuthoringSessionState
    ) -> Bool {
        guard let activeInkRole,
              activeInkRole != .passive else {
            return false
        }

        return !sessionState.isDirty(activeInkRole)
    }
}
#endif

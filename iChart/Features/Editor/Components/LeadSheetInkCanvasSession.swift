#if canImport(UIKit)
import Foundation
import PencilKit
import UIKit

enum LeadSheetPassiveInkPersistencePolicy {
    static let defaultIdleDelay: TimeInterval = 0.95

    static func idleDelay(for activeInkScope: LeadSheetActiveInkScope?) -> TimeInterval {
        return defaultIdleDelay
    }
}

enum LeadSheetInkResponsivenessPolicy {
    static let storageKey = "iChartInkResponsivenessValue"
    static let defaultValue = 0.5
    static let minimumValue = 0.0
    static let maximumValue = 1.0
    static let step = 0.05

    static func normalized(_ value: Double) -> Double {
        min(max(value, minimumValue), maximumValue)
    }

    static func inputCoalescingDelay(for value: Double) -> TimeInterval {
        let normalizedValue = normalized(value)
        return 0.004 + (normalizedValue * 0.026)
    }
}

struct LeadSheetInkDrawingSnapshot: Equatable {
    private struct StrokeSignature: Equatable {
        var pointCount: Int
        var bounds: CGRect
        var pathLength: CGFloat
        var startPoint: CGPoint
        var endPoint: CGPoint
    }

    private var strokeSignatures: [StrokeSignature]

    init?(drawing: PKDrawing) {
        let signatures = drawing.strokes.compactMap { stroke -> StrokeSignature? in
            let points = Array(stroke.path).map(\.location)
            guard !points.isEmpty else {
                return nil
            }

            let bounds = points.reduce(into: CGRect.null) { partialResult, point in
                partialResult = partialResult.union(CGRect(origin: point, size: .zero))
            }
            let pathLength = points.count < 2
                ? CGFloat.zero
                : zip(points, points.dropFirst()).reduce(CGFloat.zero) { partialResult, segment in
                    partialResult + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
                }

            return StrokeSignature(
                pointCount: points.count,
                bounds: Self.rounded(bounds),
                pathLength: Self.rounded(pathLength),
                startPoint: Self.rounded(points.first ?? .zero),
                endPoint: Self.rounded(points.last ?? .zero)
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
                pathLength: CGFloat(value),
                startPoint: CGPoint(x: value, y: value),
                endPoint: CGPoint(x: value + 1, y: value + 1)
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
    private var maxStrokeCount = 0
    private var maxPersistedBytes = 0
    private var maxPersistenceDurationMilliseconds = 0.0
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
                "max_strokes": "\(maxStrokeCount)",
                "max_bytes": "\(maxPersistedBytes)",
                "max_persist_ms": String(format: "%.2f", maxPersistenceDurationMilliseconds)
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
    }

    private mutating func flushIfNeeded(reason: String) {
        let eventCount = drawingChangeCount
            + scheduledWorkCount
            + syncLoadCount
            + persistenceAttemptCount
            + skippedPersistenceCount
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
        maxStrokeCount = 0
        maxPersistedBytes = 0
        maxPersistenceDurationMilliseconds = 0
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

enum LeadSheetActiveInkErasePolicy {
    static let eraseRadius: CGFloat = 18

    static func strokeIndicesToErase(
        in drawing: PKDrawing,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        radius: CGFloat = eraseRadius
    ) -> Set<Int> {
        let eraseBounds = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        ).insetBy(dx: -radius, dy: -radius)

        return Set(drawing.strokes.enumerated().compactMap { index, stroke in
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
        let points = Array(stroke.path).map(\.location)
        guard let firstPoint = points.first else {
            return false
        }

        let threshold = radius * radius
        if distanceSquared(from: firstPoint, toSegmentStart: startPoint, segmentEnd: endPoint) <= threshold {
            return true
        }

        var previousPoint = firstPoint
        for point in points.dropFirst() {
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

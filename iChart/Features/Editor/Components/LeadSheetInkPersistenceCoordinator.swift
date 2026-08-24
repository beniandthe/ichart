#if canImport(UIKit)
import Foundation

struct LeadSheetInkPersistenceCoordinator {
    private var pendingPersistedInkByScopeIdentity: [LeadSheetActiveInkScope.Identity: LeadSheetPendingPersistedInk] = [:]
    private var lastPersistedInkSnapshotByScopeIdentity: [LeadSheetActiveInkScope.Identity: LeadSheetPersistedInkSnapshot] = [:]
    private var pipelineMetrics = LeadSheetInkPipelineMetrics()

    mutating func recordDrawingChange(strokeCount: Int) {
        pipelineMetrics.recordDrawingChange(strokeCount: strokeCount)
    }

    mutating func recordScheduledWork(strokeCount: Int) {
        pipelineMetrics.recordScheduledWork(strokeCount: strokeCount)
    }

    mutating func recordSyncLoad(strokeCount: Int) {
        pipelineMetrics.recordSyncLoad(strokeCount: strokeCount)
    }

    mutating func recordPersistence(
        strokeCount: Int,
        bytes: Int,
        durationMilliseconds: Double
    ) {
        pipelineMetrics.recordPersistence(
            strokeCount: strokeCount,
            bytes: bytes,
            durationMilliseconds: durationMilliseconds
        )
    }

    mutating func recordSkippedPersistence(strokeCount: Int) {
        pipelineMetrics.recordSkippedPersistence(strokeCount: strokeCount)
    }

    mutating func chartByApplyingPendingPersistedInk(to incomingChart: Chart) -> Chart {
        guard !pendingPersistedInkByScopeIdentity.isEmpty else {
            return incomingChart
        }

        var resolvedChart = incomingChart
        for (scopeIdentity, pendingInk) in pendingPersistedInkByScopeIdentity {
            let incomingInk = LeadSheetPendingPersistedInk(
                drawingData: scopeIdentity.drawingData(in: resolvedChart),
                coordinateSpace: scopeIdentity.drawingCoordinateSpace(in: resolvedChart)
            )

            guard LeadSheetPendingPersistedInkPolicy.shouldRetainPendingInk(
                incomingInk: incomingInk,
                pendingInk: pendingInk
            ) else {
                pendingPersistedInkByScopeIdentity[scopeIdentity] = nil
                continue
            }

            guard LeadSheetPendingPersistedInkPolicy.shouldApplyPendingInk(
                incomingInk: incomingInk,
                pendingInk: pendingInk
            ),
                  let updatedChart = scopeIdentity.chartByPersistingDrawingData(
                    pendingInk.drawingData,
                    coordinateSpace: pendingInk.coordinateSpace,
                    in: resolvedChart
                  ) else {
                pendingPersistedInkByScopeIdentity[scopeIdentity] = nil
                continue
            }

            resolvedChart = updatedChart
        }

        return resolvedChart
    }

    func shouldSkipPersistence(
        activeInkScope: LeadSheetActiveInkScope,
        currentSnapshot: LeadSheetPersistedInkSnapshot
    ) -> Bool {
        LeadSheetInkPersistenceDedupePolicy.shouldSkipPersistence(
            activeInkScope: activeInkScope,
            currentSnapshot: currentSnapshot,
            lastPersistedSnapshot: lastPersistedInkSnapshotByScopeIdentity[activeInkScope.identity]
        )
    }

    mutating func recordPendingPersistedInk(
        activeInkScope: LeadSheetActiveInkScope,
        drawingData: Data?,
        coordinateSpace: PersistentInkCoordinateSpace?
    ) {
        guard activeInkScope.persistsDrawingData else {
            return
        }

        pendingPersistedInkByScopeIdentity[activeInkScope.identity] = LeadSheetPendingPersistedInk(
            drawingData: drawingData,
            coordinateSpace: coordinateSpace
        )
    }

    mutating func recordPersistedSnapshot(
        activeInkScope: LeadSheetActiveInkScope,
        inkSnapshot: LeadSheetInkDrawingSnapshot?,
        coordinateSpace: PersistentInkCoordinateSpace?
    ) {
        guard activeInkScope.persistsDrawingData else {
            return
        }

        lastPersistedInkSnapshotByScopeIdentity[activeInkScope.identity] = LeadSheetPersistedInkSnapshot(
            inkSnapshot: inkSnapshot,
            coordinateSpace: coordinateSpace
        )
    }
}
#endif

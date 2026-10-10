#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit

enum ChordInkRecognitionTargetLifecycleStage: Int, Hashable {
    case collecting
    case stable
    case frozen
    case committed
}

struct ChordInkRecognitionTargetOwnership: Hashable {
    var preparedStrokes: [InkStroke]
}

struct ChordInkRecognitionFrozenTargetIdentity: Hashable {
    var anchor: ChordInkDraftAnchor
    var ownership: ChordInkRecognitionTargetOwnership
}

struct ChordInkRecognitionTargetLifecycle: Hashable {
    var generationID: UUID
    var anchor: ChordInkDraftAnchor
    var ownership: ChordInkRecognitionTargetOwnership
    var stage: ChordInkRecognitionTargetLifecycleStage

    var frozenTargetIdentity: ChordInkRecognitionFrozenTargetIdentity {
        ChordInkRecognitionFrozenTargetIdentity(
            anchor: anchor,
            ownership: ownership
        )
    }

    func advanced(to nextStage: ChordInkRecognitionTargetLifecycleStage) -> Self? {
        guard nextStage == stage
                || nextStage.rawValue == stage.rawValue + 1 else {
            return nil
        }

        var advanced = self
        advanced.stage = nextStage
        return advanced
    }
}

struct ChordInkRecognitionSessionRequest {
    var requestID: UUID
    var scheduledAt: Date
    var requestedDelay: TimeInterval
    var strokes: [InkStroke]
    var drawingData: Data
    var target: (measureID: UUID, fraction: Double)
    var visualOrder: Double? = nil
    var laneLocation: ChordInkDraftLaneLocation? = nil
    var layoutPageSize: CGSize? = nil
    var options: ChordInkRecognitionOptions
    var evaluationContext: PersonalInkEvaluationContext? = nil
    var requiresEditReview: Bool = false
    /// A located target excluded by recognition's load/evidence limits still
    /// owns visible ink and can be corrected manually. Never run the reader,
    /// personal matcher, cache, or learned comparison for this request.
    var requiresManualReviewOnly: Bool = false

    var collectingTargetLifecycle: ChordInkRecognitionTargetLifecycle {
        ChordInkRecognitionTargetLifecycle(
            generationID: requestID,
            anchor: ChordInkDraftAnchor(
                measureID: target.measureID,
                laneLocation: laneLocation,
                visualOrder: visualOrder,
                fraction: target.fraction
            ),
            ownership: ChordInkRecognitionTargetOwnership(preparedStrokes: strokes),
            stage: .collecting
        )
    }
}

struct ChordInkRecognitionProposalPayload {
    var requestID: UUID
    var result: ChordInkRecognitionResult
    var strokes: [InkStroke]
    var drawingData: Data
    var target: (measureID: UUID, fraction: Double)
    var visualOrder: Double? = nil
    var laneLocation: ChordInkDraftLaneLocation? = nil
    var layoutPageSize: CGSize? = nil
    var targetLifecycle: ChordInkRecognitionTargetLifecycle? = nil
    var timing: ChordInkRecognitionTiming
    var evaluationPrediction: PersonalInkEvaluationPrediction? = nil
    var requiresManualReviewOnly: Bool = false
}

enum ChordInkRecognitionPreparationOutcome {
    case ready(requests: [ChordInkRecognitionSessionRequest], usesBatch: Bool)
    case cancelled
    case invalidDrawingData
    case noVisibleStrokes
    case noRecognitionData
    case skippedWeakBatchTargets
    case skippedSingleTarget
    case noTarget
}

struct ChordInkRecognitionPreparationRequest {
    var requestID: UUID
    var scheduledAt: Date
    var requestedDelay: TimeInterval
    var drawingData: Data
    var chordFrame: CGRect
    var pageLayout: LeadSheetPageLayout?
    var flow: ChordInkRecognitionFlow
    var options: ChordInkRecognitionOptions
    var layoutStyle: ChartLayoutStyle
    var editOwnership: ChordInkEditedTargetOwnership = .init()
    /// Local evaluation only. Production preparation does not retain a source copy.
    var capturesEvaluationSource: Bool = false
}

/// Evidence from the same preparation pass that produced the target requests.
/// Drawing bytes have the normalization of the request; they are not a new
/// serialization or a claim of original, unnormalized PencilKit blob identity.
struct ChordInkRecognitionPreparedSource {
    var normalizedDrawingData: Data
    var chordFrame: CGRect
    var pageLayout: LeadSheetPageLayout?
    var visibleStrokes: [InkStroke]
    var recognitionVisibleFragmentIndices: [Int]
    var ownership: ChordInkTargetOwnershipSnapshot
    var outcome: String

    var pageBounds: CGRect? { pageLayout?.pageBounds }
    var recognitionStrokes: [InkStroke] {
        recognitionVisibleFragmentIndices.map { visibleStrokes[$0] }
    }
}

struct ChordInkRecognitionPreparationResult {
    var requestID: UUID
    var outcome: ChordInkRecognitionPreparationOutcome
    var barlines: [DraftBarline]
    var sourceStrokeCount: Int
    var recognitionStrokeCount: Int
    var visibleStrokeCount: Int
    var ignoredInvisibleStrokeCount: Int
    var rawBatchTargetCount: Int
    var boundedBatchTargetCount: Int
    var durationMilliseconds: Double
    var ownershipSnapshot: ChordInkTargetOwnershipSnapshot? = nil
    /// Compact alternatives for observation/evaluation. Production continues
    /// to consume only `outcome`.
    var boundaryHypothesisSet: LeadSheetChordInkBoundaryHypothesisSet? = nil
    var nextEditOwnership: ChordInkEditedTargetOwnership? = nil
    var evaluationSource: ChordInkRecognitionPreparedSource? = nil
}

enum ChordInkRecognitionPreparation {
    private struct EvaluationSourceInputs {
        var visibleStrokes: [InkStroke]
        var recognitionVisibleFragmentIndices: [Int]
    }

    static func prepare(
        _ request: ChordInkRecognitionPreparationRequest,
        shouldContinue: () -> Bool = { true }
    ) -> ChordInkRecognitionPreparationResult {
        var sourceInputs: EvaluationSourceInputs?
        var preparation = prepareOnce(
            request,
            shouldContinue: shouldContinue,
            evaluationSourceInputs: &sourceInputs
        )
        if request.capturesEvaluationSource,
           let sourceInputs,
           let ownership = preparation.ownershipSnapshot,
           let outcome = evaluationSourceOutcome(for: preparation.outcome) {
            preparation.evaluationSource = ChordInkRecognitionPreparedSource(
                normalizedDrawingData: request.drawingData,
                chordFrame: request.chordFrame,
                pageLayout: request.pageLayout,
                visibleStrokes: sourceInputs.visibleStrokes,
                recognitionVisibleFragmentIndices: sourceInputs.recognitionVisibleFragmentIndices,
                ownership: ownership,
                outcome: outcome
            )
        }
        return preparation
    }

    private static func prepareOnce(
        _ request: ChordInkRecognitionPreparationRequest,
        shouldContinue: () -> Bool,
        evaluationSourceInputs: inout EvaluationSourceInputs?
    ) -> ChordInkRecognitionPreparationResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard shouldContinue() else {
            return result(
                requestID: request.requestID,
                outcome: .cancelled,
                startedAt: startedAt
            )
        }
        guard let sourceDrawing = try? PKDrawing(data: request.drawingData) else {
            return result(
                requestID: request.requestID,
                outcome: .invalidDrawingData,
                startedAt: startedAt
            )
        }
        let sourceStrokeCount = sourceDrawing.strokes.count

        let visibleSourceContext = ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(
            from: sourceDrawing
        )
        guard shouldContinue() else {
            return result(
                requestID: request.requestID,
                outcome: .cancelled,
                startedAt: startedAt,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count
            )
        }
        let visibleSourceDrawing = visibleSourceContext.drawing
        guard let sourceStrokes = PencilKitInkAdapter.inkStrokes(
            from: visibleSourceDrawing,
            shouldContinue: shouldContinue
        ) else {
            return result(
                requestID: request.requestID,
                outcome: .cancelled,
                startedAt: startedAt
            )
        }
        if request.capturesEvaluationSource {
            evaluationSourceInputs = EvaluationSourceInputs(
                visibleStrokes: sourceStrokes,
                recognitionVisibleFragmentIndices: Array(sourceStrokes.indices)
            )
        }
        if request.flow == .draftPreview,
           visibleSourceContext.visibleStrokeCount == 0 {
            return result(
                requestID: request.requestID,
                outcome: .noVisibleStrokes,
                startedAt: startedAt,
                sourceStrokeCount: sourceStrokeCount,
                visibleStrokeCount: 0,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
                ownershipSnapshot: ChordInkTargetOwnershipSnapshot(
                    sourcePencilStrokeCount: sourceStrokeCount,
                    visibleFragmentSourceStrokeIndices: visibleSourceContext.originalStrokeIndices,
                    barlineVisibleFragmentIndices: [],
                    targetVisibleFragmentIndices: []
                )
            )
        }

        let visibleBarlineRecognition: ChordDraftBarlineRecognition
        if request.flow == .draftPreview {
            let rawVisibleBarlineRecognition = ChordDraftBarlineRecognizer.recognize(
                strokes: sourceStrokes,
                chordFrame: request.chordFrame,
                pageLayout: request.pageLayout
            )
            visibleBarlineRecognition = visibleSourceContext
                .barlineRecognitionWithUnambiguousSourceStrokes(
                    rawVisibleBarlineRecognition
                )
        } else {
            visibleBarlineRecognition = ChordDraftBarlineRecognition(
                barlines: [],
                strokeIndices: []
            )
        }
        let barlineRecognition = request.flow == .draftPreview
            ? visibleSourceContext.remappedBarlineRecognition(visibleBarlineRecognition)
            : visibleBarlineRecognition
        guard shouldContinue() else {
            return result(
                requestID: request.requestID,
                outcome: .cancelled,
                startedAt: startedAt,
                sourceStrokeCount: sourceStrokeCount,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count
            )
        }
        let recognitionDrawing = request.flow == .draftPreview
            ? visibleSourceDrawing.removingStrokes(
                at: visibleBarlineRecognition.strokeIndices
            )
            : visibleSourceDrawing
        let recognitionVisibleFragmentIndices = sourceStrokes.indices.filter { index in
            request.flow != .draftPreview
                || !visibleBarlineRecognition.strokeIndices.contains(index)
        }
        evaluationSourceInputs?.recognitionVisibleFragmentIndices = recognitionVisibleFragmentIndices
        let recognitionStrokes = recognitionVisibleFragmentIndices.map { sourceStrokes[$0] }
        let recognitionStrokeCount = recognitionStrokes.count
        let targetlessOwnershipSnapshot = ownershipSnapshot(
            sourcePencilStrokeCount: sourceStrokeCount,
            visibleFragmentSourceStrokeIndices: visibleSourceContext.originalStrokeIndices,
            barlineVisibleFragmentIndices: visibleBarlineRecognition.strokeIndices,
            recognitionVisibleFragmentIndices: recognitionVisibleFragmentIndices,
            targetRecognitionStrokeIndices: []
        )
        // The source data was normalized before this preparation request was
        // created. The recognition drawing also expands any bitmap-erased mask
        // into independent visible fragments so targeting, saved source ink,
        // and semantic correction evidence all describe what the musician can
        // still see rather than the erased underlying path.
        let recognitionDrawingData = recognitionStrokeCount == 0
            ? nil
            : recognitionDrawing.dataRepresentation()
        guard let recognitionDrawingData else {
            return result(
                requestID: request.requestID,
                outcome: .noRecognitionData,
                startedAt: startedAt,
                barlines: barlineRecognition.barlines,
                sourceStrokeCount: sourceStrokeCount,
                recognitionStrokeCount: recognitionStrokeCount,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
                ownershipSnapshot: targetlessOwnershipSnapshot
            )
        }

        guard shouldContinue() else {
            return result(
                requestID: request.requestID,
                outcome: .cancelled,
                startedAt: startedAt,
                barlines: barlineRecognition.barlines,
                sourceStrokeCount: sourceStrokeCount,
                recognitionStrokeCount: recognitionStrokeCount,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count
            )
        }

        let batchTargetingResult = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: recognitionDrawing,
            chordFrame: request.chordFrame,
            pageLayout: request.pageLayout,
            draftBarlines: request.flow == .draftPreview ? barlineRecognition.barlines : [],
            preparedInkStrokes: recognitionStrokes,
            shouldContinue: shouldContinue
        )
        guard !batchTargetingResult.isCancelled,
              shouldContinue() else {
            return result(
                requestID: request.requestID,
                outcome: .cancelled,
                startedAt: startedAt,
                barlines: barlineRecognition.barlines,
                sourceStrokeCount: sourceStrokeCount,
                recognitionStrokeCount: recognitionStrokeCount,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count
            )
        }
        // Edit recovery must also see a collapse from two chords to a single
        // fallback target; otherwise that route silently discards a restored split.
        var proposedTargets = batchTargetingResult.targets
        if request.flow == .draftPreview, proposedTargets.count <= 1,
           let anchor = LeadSheetChordInkRecognitionTargeting.target(
                for: recognitionDrawing, chordFrame: request.chordFrame, pageLayout: request.pageLayout) {
            proposedTargets = [.init(measureID: anchor.measureID, fraction: anchor.fraction,
                visualOrder: LeadSheetChordInkRecognitionTargeting.visualOrder(
                    for: recognitionDrawing, chordFrame: request.chordFrame, pageLayout: request.pageLayout) ?? 0,
                laneLocation: LeadSheetChordInkRecognitionTargeting.laneLocation(
                    for: recognitionDrawing, chordFrame: request.chordFrame, pageLayout: request.pageLayout),
                recognitionStrokeIndices: Array(recognitionStrokes.indices), strokes: recognitionStrokes,
                drawingData: recognitionDrawingData, drawing: recognitionDrawing)]
        }
        let edited = request.flow == .draftPreview && !proposedTargets.isEmpty
            ? ChordInkEditedTargetPreparation.resolve(
                proposedTargets, ownership: request.editOwnership,
                visibleStrokes: sourceStrokes, recognitionStrokes: recognitionStrokes,
                recognitionDrawing: recognitionDrawing, chordFrame: request.chordFrame,
                pageLayout: request.pageLayout)
            : nil
        let usesBatchTargeting = batchTargetingResult.targets.count > 1 || (edited?.targets.count ?? 0) > 1
        let batchTargets = usesBatchTargeting ? (edited?.targets ?? batchTargetingResult.targets) : batchTargetingResult.targets
        var targetingDiagnostics = batchTargetingResult.diagnostics
        var boundaryHypothesisSet = batchTargetingResult.boundaryHypothesisSet
        if usesBatchTargeting && batchTargets.map(\.recognitionStrokeIndices) != proposedTargets.map(\.recognitionStrokeIndices) {
            targetingDiagnostics.selectedRoute = "edit_continuity"
            targetingDiagnostics.selectedClusterCount = batchTargets.count
            if let partition = LeadSheetChordInkBoundaryHypothesis(route: .editContinuity,
                recognitionStrokeCount: recognitionStrokeCount,
                targetRecognitionStrokeIndices: batchTargets.map(\.recognitionStrokeIndices)) {
                boundaryHypothesisSet = LeadSheetChordInkBoundaryHypothesisSet(
                    recognitionStrokeCount: recognitionStrokeCount,
                    candidates: [partition] + (boundaryHypothesisSet?.hypotheses ?? []))
            }
        }
        let boundedBatchTargets = ChordInkDraftPreviewRecognitionLoadPolicy.boundedBatchTargets(
            batchTargets,
            flow: request.flow
        )
        ChordDraftPreviewDeviceDiagnostics.recordTargeting(
            flow: request.flow,
            sourceStrokeCount: sourceStrokeCount,
            recognitionStrokeCount: recognitionStrokeCount,
            visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
            ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
            barlineCount: barlineRecognition.barlines.count,
            rawBatchTargets: batchTargets,
            boundedBatchTargets: boundedBatchTargets,
            targetingDiagnostics: targetingDiagnostics,
            layoutStyle: request.layoutStyle
        )

        if usesBatchTargeting {
            if boundedBatchTargets.isEmpty {
                ChordDraftPreviewDeviceDiagnostics.recordNoTarget(
                    flow: request.flow,
                    stage: "review_only_batch_targets",
                    recognitionStrokeCount: recognitionStrokeCount,
                    rawBatchTargetCount: batchTargets.count,
                    boundedBatchTargetCount: boundedBatchTargets.count,
                    layoutStyle: request.layoutStyle
                )
            }

            let admittedStrokeGroups = Set(boundedBatchTargets.map(\.recognitionStrokeIndices))
            let sessionRequests = batchTargets.map { batchTarget in
                ChordInkRecognitionSessionRequest(
                    requestID: request.requestID,
                    scheduledAt: request.scheduledAt,
                    requestedDelay: request.requestedDelay,
                    strokes: batchTarget.strokes,
                    drawingData: batchTarget.drawingData,
                    target: (batchTarget.measureID, batchTarget.fraction),
                    visualOrder: batchTarget.visualOrder,
                    laneLocation: batchTarget.laneLocation,
                    layoutPageSize: request.pageLayout?.pageBounds.size,
                    options: request.options,
                    requiresEditReview: batchTarget.requiresEditReview,
                    requiresManualReviewOnly: !admittedStrokeGroups.contains(batchTarget.recognitionStrokeIndices)
                )
            }
            return result(
                requestID: request.requestID,
                outcome: .ready(requests: sessionRequests, usesBatch: true),
                startedAt: startedAt,
                barlines: barlineRecognition.barlines,
                sourceStrokeCount: sourceStrokeCount,
                recognitionStrokeCount: recognitionStrokeCount,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
                rawBatchTargetCount: batchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count,
                ownershipSnapshot: ownershipSnapshot(
                    sourcePencilStrokeCount: sourceStrokeCount,
                    visibleFragmentSourceStrokeIndices: visibleSourceContext.originalStrokeIndices,
                    barlineVisibleFragmentIndices: visibleBarlineRecognition.strokeIndices,
                    recognitionVisibleFragmentIndices: recognitionVisibleFragmentIndices,
                    targetRecognitionStrokeIndices: batchTargets.map(
                        \.recognitionStrokeIndices
                    )
                ),
                boundaryHypothesisSet: boundaryHypothesisSet,
                nextEditOwnership: edited?.nextOwnership
            )
        }

        let shouldRecognizeSingleTarget = ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
            strokes: recognitionStrokes,
            flow: request.flow
        )
        if !shouldRecognizeSingleTarget {
            ChordDraftPreviewDeviceDiagnostics.recordNoTarget(
                flow: request.flow,
                stage: "review_only_single_target",
                recognitionStrokeCount: recognitionStrokes.count,
                rawBatchTargetCount: batchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count,
                layoutStyle: request.layoutStyle
            )
        }

        guard let target = LeadSheetChordInkRecognitionTargeting.target(
            for: recognitionDrawing,
            chordFrame: request.chordFrame,
            pageLayout: request.pageLayout
        ) else {
            ChordDraftPreviewDeviceDiagnostics.recordNoTarget(
                flow: request.flow,
                stage: "no_target",
                recognitionStrokeCount: recognitionStrokeCount,
                rawBatchTargetCount: batchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count,
                layoutStyle: request.layoutStyle
            )
            return result(
                requestID: request.requestID,
                outcome: .noTarget,
                startedAt: startedAt,
                barlines: barlineRecognition.barlines,
                sourceStrokeCount: sourceStrokeCount,
                recognitionStrokeCount: recognitionStrokeCount,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
                rawBatchTargetCount: batchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count,
                ownershipSnapshot: targetlessOwnershipSnapshot,
                boundaryHypothesisSet: boundaryHypothesisSet
            )
        }

        var sessionRequest = ChordInkRecognitionSessionRequest(
            requestID: request.requestID,
            scheduledAt: request.scheduledAt,
            requestedDelay: request.requestedDelay,
            strokes: recognitionStrokes,
            drawingData: recognitionDrawingData,
            target: target,
            visualOrder: LeadSheetChordInkRecognitionTargeting.visualOrder(
                for: recognitionDrawing,
                chordFrame: request.chordFrame,
                pageLayout: request.pageLayout
            ),
            laneLocation: LeadSheetChordInkRecognitionTargeting.laneLocation(
                for: recognitionDrawing,
                chordFrame: request.chordFrame,
                pageLayout: request.pageLayout
            ),
            layoutPageSize: request.pageLayout?.pageBounds.size,
            options: request.options
        )
        sessionRequest.requiresEditReview = edited?.targets.first?.requiresEditReview ?? false
        sessionRequest.requiresManualReviewOnly = !shouldRecognizeSingleTarget
        ChordDraftPreviewDeviceDiagnostics.recordSingleTarget(
            flow: request.flow,
            request: sessionRequest,
            layoutStyle: request.layoutStyle
        )
        return result(
            requestID: request.requestID,
            outcome: .ready(requests: [sessionRequest], usesBatch: false),
            startedAt: startedAt,
            barlines: barlineRecognition.barlines,
            sourceStrokeCount: sourceStrokeCount,
            recognitionStrokeCount: recognitionStrokeCount,
            visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
            ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
            rawBatchTargetCount: batchTargets.count,
            boundedBatchTargetCount: boundedBatchTargets.count,
            ownershipSnapshot: ownershipSnapshot(
                sourcePencilStrokeCount: sourceStrokeCount,
                visibleFragmentSourceStrokeIndices: visibleSourceContext.originalStrokeIndices,
                barlineVisibleFragmentIndices: visibleBarlineRecognition.strokeIndices,
                recognitionVisibleFragmentIndices: recognitionVisibleFragmentIndices,
                targetRecognitionStrokeIndices: [Array(recognitionStrokes.indices)]
            ),
            boundaryHypothesisSet: boundaryHypothesisSet,
            nextEditOwnership: edited?.nextOwnership
        )
    }

    private static func evaluationSourceOutcome(
        for outcome: ChordInkRecognitionPreparationOutcome
    ) -> String? {
        switch outcome {
        case .ready: return "ready"
        case .noVisibleStrokes: return "noVisibleStrokes"
        case .noRecognitionData: return "noRecognitionData"
        case .skippedWeakBatchTargets: return "skippedWeakBatchTargets"
        case .skippedSingleTarget: return "skippedSingleTarget"
        case .noTarget: return "noTarget"
        case .cancelled, .invalidDrawingData: return nil
        }
    }

    private static func ownershipSnapshot(
        sourcePencilStrokeCount: Int,
        visibleFragmentSourceStrokeIndices: [Int],
        barlineVisibleFragmentIndices: Set<Int>,
        recognitionVisibleFragmentIndices: [Int],
        targetRecognitionStrokeIndices: [[Int]]
    ) -> ChordInkTargetOwnershipSnapshot? {
        var targetVisibleFragmentIndices: [[Int]] = []
        targetVisibleFragmentIndices.reserveCapacity(targetRecognitionStrokeIndices.count)
        for targetIndices in targetRecognitionStrokeIndices {
            guard targetIndices.allSatisfy({
                recognitionVisibleFragmentIndices.indices.contains($0)
            }) else {
                return nil
            }
            targetVisibleFragmentIndices.append(
                targetIndices.map { recognitionVisibleFragmentIndices[$0] }
            )
        }

        return ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: sourcePencilStrokeCount,
            visibleFragmentSourceStrokeIndices: visibleFragmentSourceStrokeIndices,
            barlineVisibleFragmentIndices: Array(barlineVisibleFragmentIndices),
            targetVisibleFragmentIndices: targetVisibleFragmentIndices
        )
    }

    private static func result(
        requestID: UUID,
        outcome: ChordInkRecognitionPreparationOutcome,
        startedAt: TimeInterval,
        barlines: [DraftBarline] = [],
        sourceStrokeCount: Int = 0,
        recognitionStrokeCount: Int = 0,
        visibleStrokeCount: Int = 0,
        ignoredInvisibleStrokeCount: Int = 0,
        rawBatchTargetCount: Int = 0,
        boundedBatchTargetCount: Int = 0,
        ownershipSnapshot: ChordInkTargetOwnershipSnapshot? = nil,
        boundaryHypothesisSet: LeadSheetChordInkBoundaryHypothesisSet? = nil,
        nextEditOwnership: ChordInkEditedTargetOwnership? = nil
    ) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparationResult(
            requestID: requestID,
            outcome: outcome,
            barlines: barlines,
            sourceStrokeCount: sourceStrokeCount,
            recognitionStrokeCount: recognitionStrokeCount,
            visibleStrokeCount: visibleStrokeCount,
            ignoredInvisibleStrokeCount: ignoredInvisibleStrokeCount,
            rawBatchTargetCount: rawBatchTargetCount,
            boundedBatchTargetCount: boundedBatchTargetCount,
            durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000,
            ownershipSnapshot: ownershipSnapshot,
            boundaryHypothesisSet: boundaryHypothesisSet,
            nextEditOwnership: nextEditOwnership
        )
    }
}

final class ChordInkRecognitionPreparationSession {
    private let queue: DispatchQueue
    private let operationLock = NSLock()
    private var activeOperationID: UUID?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(
        request: ChordInkRecognitionPreparationRequest,
        completion: @escaping (ChordInkRecognitionPreparationResult) -> Void
    ) {
        let operationID = beginOperation()
        queue.async { [weak self] in
            guard let self,
                  self.isActive(operationID) else {
                return
            }
            let result = ChordInkRecognitionPreparation.prepare(request) { [weak self] in
                self?.isActive(operationID) == true
            }
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

final class ChordInkRecognitionSession {
    private struct CacheKey: Hashable {
        var strokes: [InkStroke]
        var options: ChordInkRecognitionOptions
    }

    private static let maximumCachedResultCount = 192

    private let queue: DispatchQueue
    private let recognizer: ChordInkRecognizing
    private let personalProfile: PersonalInkProfileStore?
    private let allowsPersonalInk: Bool
    private let operationLock = NSLock()
    private var activeOperationID: UUID?
    private var cachedResults: [CacheKey: ChordInkRecognitionResult] = [:]
    private var personalResults: [CacheKey: ChordInkRecognitionResult] = [:]
    private var cacheInsertionOrder: [CacheKey] = []

    init(
        queue: DispatchQueue,
        recognizer: ChordInkRecognizing,
        personalProfile: PersonalInkProfileStore? = nil,
        allowsPersonalInk: Bool = HandwritingPersonalizationProductPolicy.isAvailable
    ) {
        self.queue = queue
        self.recognizer = recognizer
        self.personalProfile = personalProfile
        self.allowsPersonalInk = allowsPersonalInk
    }

    func start(
        request: ChordInkRecognitionSessionRequest,
        completion: @escaping (ChordInkRecognitionProposalPayload) -> Void
    ) {
        let operationID = beginOperation()
        let recognizer = recognizer
        queue.async { [weak self] in
            guard let self,
                  self.isActive(operationID) else {
                return
            }
            let recognitionStartedAt = Date()
            let cachedRecognition = self.recognitionResult(for: request, recognizer: recognizer)
            let recognitionFinishedAt = Date()
            let payload = ChordInkRecognitionProposalPayload(
                requestID: request.requestID,
                result: cachedRecognition.result,
                strokes: request.strokes,
                drawingData: request.drawingData,
                target: request.target,
                visualOrder: request.visualOrder,
                laneLocation: request.laneLocation,
                layoutPageSize: request.layoutPageSize,
                targetLifecycle: request.collectingTargetLifecycle.advanced(to: .stable),
                timing: ChordInkRecognitionTiming(
                    scheduledAt: request.scheduledAt,
                    requestedDelay: request.requestedDelay,
                    recognitionStartedAt: recognitionStartedAt,
                    recognitionFinishedAt: recognitionFinishedAt,
                    strokeCount: request.strokes.count,
                    cacheHit: cachedRecognition.cacheHit
                ),
                evaluationPrediction: cachedRecognition.evaluation,
                requiresManualReviewOnly: request.requiresManualReviewOnly
            )

            guard self.isActive(operationID) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard self?.finishOperation(operationID) == true else {
                    return
                }
                completion(payload)
            }
        }
    }

    func startBatch(
        requests: [ChordInkRecognitionSessionRequest],
        completion: @escaping ([ChordInkRecognitionProposalPayload]) -> Void
    ) {
        guard !requests.isEmpty else {
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

        let operationID = beginOperation()
        let recognizer = recognizer
        queue.async { [weak self] in
            guard let self,
                  self.isActive(operationID) else {
                return
            }
            var payloads: [ChordInkRecognitionProposalPayload] = []
            payloads.reserveCapacity(requests.count)
            for request in requests {
                guard self.isActive(operationID) else {
                    return
                }
                let recognitionStartedAt = Date()
                let cachedRecognition = self.recognitionResult(for: request, recognizer: recognizer)
                let recognitionFinishedAt = Date()
                payloads.append(ChordInkRecognitionProposalPayload(
                    requestID: request.requestID,
                    result: cachedRecognition.result,
                    strokes: request.strokes,
                    drawingData: request.drawingData,
                    target: request.target,
                    visualOrder: request.visualOrder,
                    laneLocation: request.laneLocation,
                    layoutPageSize: request.layoutPageSize,
                    targetLifecycle: request.collectingTargetLifecycle.advanced(to: .stable),
                    timing: ChordInkRecognitionTiming(
                        scheduledAt: request.scheduledAt,
                        requestedDelay: request.requestedDelay,
                        recognitionStartedAt: recognitionStartedAt,
                        recognitionFinishedAt: recognitionFinishedAt,
                        strokeCount: request.strokes.count,
                        cacheHit: cachedRecognition.cacheHit
                    ),
                    evaluationPrediction: cachedRecognition.evaluation,
                    requiresManualReviewOnly: request.requiresManualReviewOnly
                ))
            }

            guard self.isActive(operationID) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard self?.finishOperation(operationID) == true else {
                    return
                }
                completion(payloads)
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

    private func recognitionResult(
        for request: ChordInkRecognitionSessionRequest,
        recognizer: ChordInkRecognizing
    ) -> (result: ChordInkRecognitionResult, cacheHit: Bool, evaluation: PersonalInkEvaluationPrediction?) {
        if request.requiresManualReviewOnly {
            let unread = ChordInkRecognitionResult(
                rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0,
                requiresEditReview: true,
                metrics: ChordInkRecognitionMetrics(strokeCount: request.strokes.count)
            )
            return (unread, false, nil)
        }
        // Recognition consumes only the prepared strokes and options. PencilKit
        // may reserialize an unchanged drawing with different archive metadata,
        // so raw drawing bytes make a valid cache miss every time an earlier
        // chord is revisited in a growing row. Key the cache by the exact
        // recognition input instead; request.drawingData still flows through
        // the payload for persistence and correction evidence.
        let key = CacheKey(strokes: request.strokes, options: request.options)
        let profile = allowsPersonalInk
            ? (request.evaluationContext?.profile ?? personalProfile?.snapshot())
            : nil
        if let result = cachedResults[key] {
            let adapted = scoped(personalized(result, key: key, profile: profile), to: request)
            return (adapted, true, evaluationPrediction(base: scoped(result, to: request), adapted: adapted, request: request))
        }

        let result = recognizer.recognize(
            strokes: request.strokes,
            options: request.options
        )
        cachedResults[key] = result
        cacheInsertionOrder.append(key)
        if cacheInsertionOrder.count > Self.maximumCachedResultCount {
            let expiredKey = cacheInsertionOrder.removeFirst()
            cachedResults[expiredKey] = nil
            personalResults[expiredKey] = nil
        }
        let adapted = scoped(personalized(result, key: key, profile: profile), to: request)
        return (adapted, false, evaluationPrediction(base: scoped(result, to: request), adapted: adapted, request: request))
    }

    private func scoped(_ result: ChordInkRecognitionResult,
                        to request: ChordInkRecognitionSessionRequest) -> ChordInkRecognitionResult {
        var result = result
        result.requiresEditReview = request.requiresEditReview
        return result
    }

    private func evaluationPrediction(base: ChordInkRecognitionResult, adapted: ChordInkRecognitionResult,
                                      request: ChordInkRecognitionSessionRequest) -> PersonalInkEvaluationPrediction? {
        guard allowsPersonalInk,
              let context = request.evaluationContext else { return nil }
        let baseDecision = ChordInkRecognitionPolicy.decision(for: base)
        let selection = ChordInkRenderResolutionPolicy.personalSelection(for: adapted)
        return .init(runID: context.runID,
                     baseline: base.match?.displayText ?? ChordInkRenderResolutionPolicy.candidateTexts(for: base).first,
                     personalized: selection.text,
                     baselineAction: baseDecision.action.rawValue,
                     personalizedAction: selection.prefersPersonal ? "confirm" : baseDecision.action.rawValue,
                     knownInk: context.profile.wasAlreadyLearned(strokes: request.strokes),
                     personalSuggestion: adapted.personalSuggestion,
                     personalArbitration: selection.disposition.rawValue,
                     baselineRecognitionAction: ChordInkRecognitionPolicy.recognitionEvidenceDecision(for: base).action.rawValue)
    }

    private func personalized(_ result: ChordInkRecognitionResult, key: CacheKey,
                              profile: PersonalInkSnapshot?) -> ChordInkRecognitionResult {
        guard let profile else { return result }
        if let cached = personalResults[key], cached.personalizationRevision == profile.profile.revision {
            return cached
        }
        let personalized = profile.applying(to: result, strokes: key.strokes)
        personalResults[key] = personalized
        return personalized
    }
}
#endif

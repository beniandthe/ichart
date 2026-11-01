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
    /// A located target excluded by the primary reader's load/evidence limits
    /// still owns its ink. Manual reads skip recognition/personalization;
    /// automatic entry may ask its separately bounded fallback providers.
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

/// Shared census identity for the incremental reader and its draft state.
/// Archive bytes and request generations may change while the actual target
/// input stays identical; review and evaluation scopes may not be reused.
struct ChordInkRecognitionIncrementalTargetKey: Hashable {
    var target: ChordInkRecognitionFrozenTargetIdentity
    var options: ChordInkRecognitionOptions
    var requiresEditReview: Bool
    var requiresManualReviewOnly: Bool
    var evaluationRunID: UUID?
    var evaluationProfileRevision: UUID?

    init(request: ChordInkRecognitionSessionRequest) {
        target = request.collectingTargetLifecycle.frozenTargetIdentity
        options = request.options
        requiresEditReview = request.requiresEditReview
        requiresManualReviewOnly = request.requiresManualReviewOnly
        evaluationRunID = request.evaluationContext?.runID
        evaluationProfileRevision = request.evaluationContext?.profile.profile.revision
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
    var endings: [DraftEnding] = []
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

        let visibleSourceContext = request.flow == .draftPreview
            ? ChordInkDraftVisibleStrokePolicy.repeatAwareVisibleDrawingContext(
                from: sourceDrawing, chordFrame: request.chordFrame, pageLayout: request.pageLayout)
            : ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(from: sourceDrawing)
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

        let visibleEndingRecognition: ChordDraftEndingRecognition
        if request.flow == .draftPreview {
            visibleEndingRecognition = visibleSourceContext.endingRecognitionWithUnambiguousSourceStrokes(
                ChordDraftEndingRecognizer.recognize(strokes: sourceStrokes,
                    chordFrame: request.chordFrame, pageLayout: request.pageLayout)
            )
        } else {
            visibleEndingRecognition = ChordDraftEndingRecognition(endings: [], strokeIndices: [])
        }
        let endingRecognition = visibleSourceContext.remappedEndingRecognition(visibleEndingRecognition)
        let visibleBarlineRecognition: ChordDraftBarlineRecognition
        if request.flow == .draftPreview {
            let rawVisibleBarlineRecognition = ChordDraftEndingRecognizer.recognizeBarlinesExcludingEndings(
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
        let structuralFragmentIndices = visibleBarlineRecognition.strokeIndices
            .union(visibleEndingRecognition.strokeIndices)
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
                at: structuralFragmentIndices
            )
            : visibleSourceDrawing
        let recognitionVisibleFragmentIndices = sourceStrokes.indices.filter { index in
            request.flow != .draftPreview
                || !structuralFragmentIndices.contains(index)
        }
        evaluationSourceInputs?.recognitionVisibleFragmentIndices = recognitionVisibleFragmentIndices
        let recognitionStrokes = recognitionVisibleFragmentIndices.map { sourceStrokes[$0] }
        let recognitionStrokeCount = recognitionStrokes.count
        let targetlessOwnershipSnapshot = ownershipSnapshot(
            sourcePencilStrokeCount: sourceStrokeCount,
            visibleFragmentSourceStrokeIndices: visibleSourceContext.originalStrokeIndices,
            barlineVisibleFragmentIndices: structuralFragmentIndices,
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
                endings: endingRecognition.endings,
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
                endings: endingRecognition.endings,
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
                endings: endingRecognition.endings,
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
                endings: endingRecognition.endings,
                sourceStrokeCount: sourceStrokeCount,
                recognitionStrokeCount: recognitionStrokeCount,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
                rawBatchTargetCount: batchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count,
                ownershipSnapshot: ownershipSnapshot(
                    sourcePencilStrokeCount: sourceStrokeCount,
                    visibleFragmentSourceStrokeIndices: visibleSourceContext.originalStrokeIndices,
                    barlineVisibleFragmentIndices: structuralFragmentIndices,
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
                endings: endingRecognition.endings,
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
            endings: endingRecognition.endings,
            sourceStrokeCount: sourceStrokeCount,
            recognitionStrokeCount: recognitionStrokeCount,
            visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
            ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
            rawBatchTargetCount: batchTargets.count,
            boundedBatchTargetCount: boundedBatchTargets.count,
            ownershipSnapshot: ownershipSnapshot(
                sourcePencilStrokeCount: sourceStrokeCount,
                visibleFragmentSourceStrokeIndices: visibleSourceContext.originalStrokeIndices,
                barlineVisibleFragmentIndices: structuralFragmentIndices,
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
        endings: [DraftEnding] = [],
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
            endings: endings,
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

    /// Request/archive generations are envelopes, not target identity. A
    /// neighbor's new ink must not cancel this target's unchanged exact input.
    private struct IncrementalKey: Hashable {
        var target: ChordInkRecognitionIncrementalTargetKey
        var liveProfileRevision: UUID?
    }

    private struct IncrementalRead {
        var result: ChordInkRecognitionResult
        var timing: ChordInkRecognitionTiming
        var evaluation: PersonalInkEvaluationPrediction?
    }

    private struct IncrementalEntry {
        var workID: UUID
        var censusID: UUID
        var request: ChordInkRecognitionSessionRequest
        var read: IncrementalRead?
        var publicationCount = 0
    }

    private struct FallbackCacheKey: Hashable {
        var source: CacheKey
        var providerVersion: String
    }

    private struct FallbackRead {
        var scores: [ChordInkCandidateScore]
        var evidence: [ChordInkRecognitionFallbackEvidence]
        var computedMilliseconds: Double
    }

    private struct FallbackProgress {
        var providerIndex = 0
        var completedAttempts = 0
        var providerMilliseconds: Double = 0
        var computedMilliseconds: Double = 0
        var evidence: [ChordInkRecognitionFallbackEvidence] = []
    }

    private struct FallbackTechnicalState {
        var attemptCount: Int
        var durationMilliseconds: Double
        /// nil is an unresolved technical failure; an empty array is a
        /// successful retry which actually found no supported candidate.
        var completedScores: [ChordInkCandidateScore]?
    }

    private static let automaticFallbackRetryDelay: TimeInterval = 0.1

    private static let maximumCachedResultCount = 192

    private let queue: DispatchQueue
    private let recognizer: ChordInkRecognizing
    private let automaticFallbackRecognizers: [any ChordInkAutomaticFallbackRecognizing]
    private let automaticFallbackQueue: DispatchQueue
    private let automaticFallbackVersion: String
    private let personalProfile: PersonalInkProfileStore?
    private let allowsPersonalInk: Bool
    private let operationLock = NSLock()
    private var activeOperationID: UUID?
    private var incrementalEntries: [IncrementalKey: IncrementalEntry] = [:]
    private var incrementalTargetHandler: ((ChordInkRecognitionProposalPayload) -> Void)?
    private var cachedResults: [CacheKey: ChordInkRecognitionResult] = [:]
    private var personalResults: [CacheKey: ChordInkRecognitionResult] = [:]
    private var cacheInsertionOrder: [CacheKey] = []
    // Confined to the independent serial fallback worker. Neither these
    // values nor fallback suggestions enter the primary/manual cache.
    private var fallbackResults: [FallbackCacheKey: FallbackRead] = [:]
    private var fallbackInsertionOrder: [FallbackCacheKey] = []
    // Separate from semantic recognition exhaustion. Cancelling/recreating a
    // work envelope for identical ink must not replenish an engine's budget.
    private var fallbackTechnicalStates: [FallbackCacheKey: [Int: FallbackTechnicalState]] = [:]
    private var fallbackTechnicalInsertionOrder: [FallbackCacheKey] = []

    init(
        queue: DispatchQueue,
        recognizer: ChordInkRecognizing,
        personalProfile: PersonalInkProfileStore? = nil,
        allowsPersonalInk: Bool = HandwritingPersonalizationProductPolicy.isAvailable,
        automaticFallbackRecognizers: [any ChordInkAutomaticFallbackRecognizing] = [],
        automaticFallbackQueue: DispatchQueue? = nil
    ) {
        self.queue = queue
        self.recognizer = recognizer
        self.personalProfile = personalProfile
        self.allowsPersonalInk = allowsPersonalInk
        self.automaticFallbackRecognizers = automaticFallbackRecognizers
        self.automaticFallbackQueue = automaticFallbackQueue
            ?? DispatchQueue(label: "com.ichart.automatic-chord-fallback.\(UUID())", qos: .userInitiated)
        self.automaticFallbackVersion = ChordInkAutomaticFallbackProviders.pipelineVersion + ":"
            + automaticFallbackRecognizers.map { "\($0.identifier)@\($0.version)" }.joined(separator: ";")
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

    /// Reconcile one current, complete target census. Call on the main thread.
    /// Each new target uses the same serial recognition queue/cache as manual
    /// work, but publishes independently instead of waiting for its neighbors.
    /// Completed/queued reads survive unchanged input in a later census; their
    /// payloads always carry the latest request envelope and source ownership.
    func startIncremental(
        requests: [ChordInkRecognitionSessionRequest],
        onTarget: @escaping (ChordInkRecognitionProposalPayload) -> Void
    ) {
        precondition(Thread.isMainThread)
        let censusID = UUID()
        let liveProfileRevision = allowsPersonalInk ? personalProfile?.snapshot().profile.revision : nil
        var orderedKeys: [IncrementalKey] = []
        var currentRequests: [IncrementalKey: ChordInkRecognitionSessionRequest] = [:]
        for request in requests {
            let key = IncrementalKey(
                target: ChordInkRecognitionIncrementalTargetKey(request: request),
                liveProfileRevision: request.evaluationContext == nil ? liveProfileRevision : nil
            )
            if currentRequests[key] == nil { orderedKeys.append(key) }
            currentRequests[key] = request
        }

        var newWork: [(IncrementalKey, UUID)] = []
        var completedWork: [(IncrementalKey, UUID)] = []
        operationLock.lock()
        activeOperationID = nil
        incrementalTargetHandler = onTarget
        incrementalEntries = incrementalEntries.filter { currentRequests[$0.key] != nil }
        for key in orderedKeys {
            guard let request = currentRequests[key] else { continue }
            if var existing = incrementalEntries[key] {
                existing.censusID = censusID
                existing.request = request
                incrementalEntries[key] = existing
                if existing.read != nil { completedWork.append((key, existing.workID)) }
            } else {
                let workID = UUID()
                incrementalEntries[key] = IncrementalEntry(workID: workID, censusID: censusID,
                    request: request, read: nil)
                newWork.append((key, workID))
            }
        }
        operationLock.unlock()

        for (key, workID) in completedWork {
            DispatchQueue.main.async { [weak self] in
                self?.publishIncrementalTarget(key: key, workID: workID, censusID: censusID)
            }
        }
        for (key, workID) in newWork {
            queue.async { [weak self] in
                guard let self,
                      let request = self.incrementalRequest(key: key, workID: workID) else { return }
                let startedAt = Date()
                let recognized = self.recognitionResult(for: request, recognizer: self.recognizer)
                let read = IncrementalRead(result: recognized.result,
                    timing: ChordInkRecognitionTiming(scheduledAt: request.scheduledAt,
                        requestedDelay: request.requestedDelay, recognitionStartedAt: startedAt,
                        recognitionFinishedAt: Date(), strokeCount: request.strokes.count,
                        cacheHit: recognized.cacheHit), evaluation: recognized.evaluation)
                if !self.automaticFallbackRecognizers.isEmpty,
                   !ChordInkAutomaticFallbackCandidatePolicy.hasCandidate(read.result),
                   ChordInkAutomaticFallbackCandidatePolicy.sourceIsUsable(request.strokes, maximumStrokeCount: 128) {
                    // Leave this target collecting while its separate worker
                    // runs. The primary queue immediately advances to the
                    // next target; a slow fallback cannot hold its neighbors.
                    self.scheduleAutomaticFallback(read, request: request, key: key, workID: workID)
                } else {
                    self.finishIncrementalRead(read, key: key, workID: workID)
                }
            }
        }
    }

    private func scheduleAutomaticFallback(
        _ primaryRead: IncrementalRead, request: ChordInkRecognitionSessionRequest,
        key: IncrementalKey, workID: UUID
    ) {
        automaticFallbackQueue.async { [weak self] in
            guard let self else { return }
            guard self.incrementalRequest(key: key, workID: workID) != nil else { return }
            let cacheKey = FallbackCacheKey(source: CacheKey(strokes: request.strokes, options: request.options),
                providerVersion: self.automaticFallbackVersion)
            if let cached = self.fallbackResults[cacheKey] {
                self.finishAutomaticFallback(cached, primaryRead: primaryRead, key: key,
                    workID: workID, cacheHit: true)
            } else {
                self.continueAutomaticFallback(primaryRead, request: request, key: key,
                    workID: workID, cacheKey: cacheKey, progress: FallbackProgress())
            }
        }
    }

    /// Confined to the fallback worker. A delayed retry releases that worker
    /// so other current targets can finish while one engine is unavailable.
    private func continueAutomaticFallback(
        _ primaryRead: IncrementalRead, request: ChordInkRecognitionSessionRequest,
        key: IncrementalKey, workID: UUID, cacheKey: FallbackCacheKey,
        progress: FallbackProgress
    ) {
        let isCurrent = { [weak self] in self?.incrementalRequest(key: key, workID: workID) != nil }
        guard isCurrent() else { return }
        if let cached = fallbackResults[cacheKey] {
            finishAutomaticFallback(cached, primaryRead: primaryRead, key: key,
                workID: workID, cacheHit: true)
            return
        }
        let providers = Array(automaticFallbackRecognizers.prefix(4))
        guard providers.indices.contains(progress.providerIndex) else {
            cacheAndFinishAutomaticFallback(FallbackRead(scores: [], evidence: progress.evidence,
                computedMilliseconds: progress.computedMilliseconds),
                primaryRead: primaryRead, key: key, workID: workID, cacheKey: cacheKey)
            return
        }
        let provider = providers[progress.providerIndex]
        var next = progress
        if let technical = fallbackTechnicalStates[cacheKey]?[progress.providerIndex] {
            next.completedAttempts = technical.attemptCount
            next.providerMilliseconds = technical.durationMilliseconds
            if let completedScores = technical.completedScores {
                finishAutomaticFallbackProvider(completedScores, outcome: .completed,
                    primaryRead: primaryRead, request: request, key: key, workID: workID,
                    cacheKey: cacheKey, progress: next, provider: provider)
                return
            }
            if technical.attemptCount >= 2 {
                finishAutomaticFallbackProvider([], outcome: .technicalFailure,
                    primaryRead: primaryRead, request: request, key: key, workID: workID,
                    cacheKey: cacheKey, progress: next, provider: provider)
                return
            }
        }
        let startedAt = ProcessInfo.processInfo.systemUptime
        let attempt = provider.recognizeAttempt(strokes: request.strokes, options: request.options,
            isCurrent: isCurrent)
        guard isCurrent() else { return }
        next.completedAttempts += 1
        let elapsedMilliseconds = max(0, (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
        next.providerMilliseconds += elapsedMilliseconds
        next.computedMilliseconds += elapsedMilliseconds
        let candidates: [ChordInkCandidateScore]
        let outcome: ChordInkRecognitionFallbackEvidence.Outcome
        switch attempt {
        case .cancelled:
            return
        case .technicalFailure where next.completedAttempts == 1:
            // One retry belongs to the exact prepared source/options/provider
            // version. A cancelled envelope cannot replenish that budget.
            // Obsolete or cancelled calls never enter this technical state.
            setFallbackTechnicalState(.init(attemptCount: next.completedAttempts,
                durationMilliseconds: next.providerMilliseconds, completedScores: nil),
                cacheKey: cacheKey, providerIndex: next.providerIndex)
            let retryProgress = next
            automaticFallbackQueue.asyncAfter(deadline: .now() + Self.automaticFallbackRetryDelay) { [weak self] in
                self?.continueAutomaticFallback(primaryRead, request: request, key: key,
                    workID: workID, cacheKey: cacheKey, progress: retryProgress)
            }
            return
        case .technicalFailure:
            candidates = []
            outcome = .technicalFailure
            setFallbackTechnicalState(.init(attemptCount: next.completedAttempts,
                durationMilliseconds: next.providerMilliseconds, completedScores: nil),
                cacheKey: cacheKey, providerIndex: next.providerIndex)
        case .completed(let result):
            candidates = result.map(ChordInkAutomaticFallbackCandidatePolicy.candidateScores(for:)) ?? []
            outcome = .completed
            if fallbackTechnicalStates[cacheKey]?[next.providerIndex] != nil {
                setFallbackTechnicalState(.init(attemptCount: next.completedAttempts,
                    durationMilliseconds: next.providerMilliseconds, completedScores: candidates),
                    cacheKey: cacheKey, providerIndex: next.providerIndex)
            }
        }
        finishAutomaticFallbackProvider(candidates, outcome: outcome, primaryRead: primaryRead,
            request: request, key: key, workID: workID, cacheKey: cacheKey,
            progress: next, provider: provider)
    }

    private func setFallbackTechnicalState(
        _ state: FallbackTechnicalState, cacheKey: FallbackCacheKey, providerIndex: Int
    ) {
        if fallbackTechnicalStates[cacheKey] == nil {
            fallbackTechnicalInsertionOrder.append(cacheKey)
            if fallbackTechnicalInsertionOrder.count > Self.maximumCachedResultCount {
                fallbackTechnicalStates[fallbackTechnicalInsertionOrder.removeFirst()] = nil
            }
        }
        fallbackTechnicalStates[cacheKey, default: [:]][providerIndex] = state
    }

    private func finishAutomaticFallbackProvider(
        _ candidates: [ChordInkCandidateScore], outcome: ChordInkRecognitionFallbackEvidence.Outcome,
        primaryRead: IncrementalRead, request: ChordInkRecognitionSessionRequest,
        key: IncrementalKey, workID: UUID, cacheKey: FallbackCacheKey,
        progress: FallbackProgress, provider: any ChordInkAutomaticFallbackRecognizing
    ) {
        var next = progress
        next.evidence.append(ChordInkRecognitionFallbackEvidence(engineIdentifier: provider.identifier,
            engineVersion: provider.version, candidateTexts: candidates.compactMap(\.displayText),
            durationMilliseconds: next.providerMilliseconds, outcome: outcome,
            attemptCount: next.completedAttempts))
        if !candidates.isEmpty {
            cacheAndFinishAutomaticFallback(FallbackRead(scores: candidates, evidence: next.evidence,
                computedMilliseconds: next.computedMilliseconds),
                primaryRead: primaryRead, key: key, workID: workID, cacheKey: cacheKey)
            return
        }
        next.providerIndex += 1
        next.completedAttempts = 0
        next.providerMilliseconds = 0
        continueAutomaticFallback(primaryRead, request: request, key: key,
            workID: workID, cacheKey: cacheKey, progress: next)
    }

    private func cacheAndFinishAutomaticFallback(
        _ recovered: FallbackRead, primaryRead: IncrementalRead,
        key: IncrementalKey, workID: UUID, cacheKey: FallbackCacheKey
    ) {
        guard incrementalRequest(key: key, workID: workID) != nil else { return }
        // A real candidate can be reused; successful exhaustion can too. A
        // terminal engine failure is local diagnostic evidence, never a
        // negative recognition cache entry for a later source operation.
        if !recovered.scores.isEmpty || recovered.evidence.allSatisfy({ $0.outcome == .completed }) {
            fallbackResults[cacheKey] = recovered
            fallbackInsertionOrder.append(cacheKey)
            if fallbackInsertionOrder.count > Self.maximumCachedResultCount {
                fallbackResults[fallbackInsertionOrder.removeFirst()] = nil
            }
        }
        finishAutomaticFallback(recovered, primaryRead: primaryRead, key: key,
            workID: workID, cacheHit: false)
    }

    private func finishAutomaticFallback(
        _ recovered: FallbackRead, primaryRead: IncrementalRead,
        key: IncrementalKey, workID: UUID, cacheHit: Bool
    ) {
        guard incrementalRequest(key: key, workID: workID) != nil else { return }
        var read = primaryRead
        // The primary answer and its trust remain unchanged, including an
        // empty answer. Only actual supported fallback suggestions append.
        read.result.reviewCandidateScores.append(contentsOf: recovered.scores)
        read.result.fallbackEvidence = recovered.evidence
        if !cacheHit {
            // Replayed technical status retains its original evidence timing;
            // it must not pretend that those earlier engine calls ran again.
            read.result.metrics.totalMilliseconds += recovered.computedMilliseconds
        }
        read.timing.recognitionFinishedAt = Date()
        read.timing.cacheHit = primaryRead.timing.cacheHit && cacheHit
        // Retain the terminal status for this work identity so unchanged
        // censuses cannot replenish its bounded retry budget indefinitely.
        finishIncrementalRead(read, key: key, workID: workID)
    }

    private func finishIncrementalRead(_ read: IncrementalRead, key: IncrementalKey, workID: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.operationLock.lock()
            guard var entry = self.incrementalEntries[key], entry.workID == workID else {
                self.operationLock.unlock()
                return
            }
            entry.read = read
            self.incrementalEntries[key] = entry
            self.operationLock.unlock()
            self.publishIncrementalTarget(key: key, workID: workID)
        }
    }

    /// Input changes reconcile the census instead. Use this for a chart/scope,
    /// mode or workflow change which invalidates every pending target.
    func cancelIncrementalWork() {
        operationLock.lock()
        incrementalEntries.removeAll()
        incrementalTargetHandler = nil
        operationLock.unlock()
    }

    private func incrementalRequest(key: IncrementalKey, workID: UUID) -> ChordInkRecognitionSessionRequest? {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard let entry = incrementalEntries[key], entry.workID == workID else { return nil }
        return entry.request
    }

    private func publishIncrementalTarget(key: IncrementalKey, workID: UUID, censusID: UUID? = nil) {
        precondition(Thread.isMainThread)
        operationLock.lock()
        guard var entry = incrementalEntries[key], entry.workID == workID,
              censusID == nil || entry.censusID == censusID,
              let read = entry.read,
              let onTarget = incrementalTargetHandler else {
            operationLock.unlock()
            return
        }
        let request = entry.request
        var timing = read.timing
        // Read timing belongs to the original target operation; a newer
        // neighbor's scheduledAt may be later than this read's start/finish.
        // Replayed completed reads are cache reuse, with current provenance.
        if entry.publicationCount > 0 { timing.cacheHit = true }
        entry.publicationCount += 1
        incrementalEntries[key] = entry
        operationLock.unlock()
        onTarget(ChordInkRecognitionProposalPayload(requestID: request.requestID,
            result: read.result, strokes: request.strokes, drawingData: request.drawingData,
            target: request.target, visualOrder: request.visualOrder,
            laneLocation: request.laneLocation, layoutPageSize: request.layoutPageSize,
            targetLifecycle: request.collectingTargetLifecycle.advanced(to: .stable),
            timing: timing, evaluationPrediction: read.evaluation,
            requiresManualReviewOnly: request.requiresManualReviewOnly))
    }

    func cancelPendingWork() {
        operationLock.lock()
        activeOperationID = nil
        incrementalEntries.removeAll()
        incrementalTargetHandler = nil
        operationLock.unlock()
    }

    /// A changed automatic census supersedes legacy page-wide work while
    /// keeping unchanged incremental targets alive for reconciliation.
    func cancelBatchWork() {
        operationLock.lock()
        activeOperationID = nil
        operationLock.unlock()
    }

    private func beginOperation() -> UUID {
        let operationID = UUID()
        operationLock.lock()
        activeOperationID = operationID
        incrementalEntries.removeAll()
        incrementalTargetHandler = nil
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

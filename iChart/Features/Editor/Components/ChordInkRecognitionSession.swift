#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit

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
    var timing: ChordInkRecognitionTiming
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
}

enum ChordInkRecognitionPreparation {
    static func prepare(
        _ request: ChordInkRecognitionPreparationRequest,
        shouldContinue: () -> Bool = { true }
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
        if request.flow == .draftPreview,
           visibleSourceContext.visibleStrokeCount == 0 {
            return result(
                requestID: request.requestID,
                outcome: .noVisibleStrokes,
                startedAt: startedAt,
                sourceStrokeCount: sourceStrokeCount,
                visibleStrokeCount: 0,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count
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
        let recognitionStrokes = request.flow == .draftPreview
            ? sourceStrokes.enumerated().compactMap { index, stroke in
                visibleBarlineRecognition.strokeIndices.contains(index) ? nil : stroke
            }
            : sourceStrokes
        let recognitionStrokeCount = recognitionStrokes.count
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
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count
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
        let batchTargets = batchTargetingResult.targets
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
            targetingDiagnostics: batchTargetingResult.diagnostics,
            layoutStyle: request.layoutStyle
        )

        if batchTargets.count > 1 {
            guard !boundedBatchTargets.isEmpty else {
                ChordDraftPreviewDeviceDiagnostics.recordNoTarget(
                    flow: request.flow,
                    stage: "skip_weak_batch_targets",
                    recognitionStrokeCount: recognitionStrokeCount,
                    rawBatchTargetCount: batchTargets.count,
                    boundedBatchTargetCount: boundedBatchTargets.count,
                    layoutStyle: request.layoutStyle
                )
                return result(
                    requestID: request.requestID,
                    outcome: .skippedWeakBatchTargets,
                    startedAt: startedAt,
                    barlines: barlineRecognition.barlines,
                    sourceStrokeCount: sourceStrokeCount,
                    recognitionStrokeCount: recognitionStrokeCount,
                    visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                    ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
                    rawBatchTargetCount: batchTargets.count,
                    boundedBatchTargetCount: boundedBatchTargets.count
                )
            }

            let sessionRequests = boundedBatchTargets.map { batchTarget in
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
                    options: request.options
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
                boundedBatchTargetCount: boundedBatchTargets.count
            )
        }

        guard ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
            strokes: recognitionStrokes,
            flow: request.flow
        ) else {
            ChordDraftPreviewDeviceDiagnostics.recordNoTarget(
                flow: request.flow,
                stage: "skip_single_target",
                recognitionStrokeCount: recognitionStrokes.count,
                rawBatchTargetCount: batchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count,
                layoutStyle: request.layoutStyle
            )
            return result(
                requestID: request.requestID,
                outcome: .skippedSingleTarget,
                startedAt: startedAt,
                barlines: barlineRecognition.barlines,
                sourceStrokeCount: sourceStrokeCount,
                recognitionStrokeCount: recognitionStrokeCount,
                visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
                ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
                rawBatchTargetCount: batchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count
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
                boundedBatchTargetCount: boundedBatchTargets.count
            )
        }

        let sessionRequest = ChordInkRecognitionSessionRequest(
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
            boundedBatchTargetCount: boundedBatchTargets.count
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
        boundedBatchTargetCount: Int = 0
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
            durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
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
    private let operationLock = NSLock()
    private var activeOperationID: UUID?
    private var cachedResults: [CacheKey: ChordInkRecognitionResult] = [:]
    private var cacheInsertionOrder: [CacheKey] = []

    init(
        queue: DispatchQueue,
        recognizer: ChordInkRecognizing
    ) {
        self.queue = queue
        self.recognizer = recognizer
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
                timing: ChordInkRecognitionTiming(
                    scheduledAt: request.scheduledAt,
                    requestedDelay: request.requestedDelay,
                    recognitionStartedAt: recognitionStartedAt,
                    recognitionFinishedAt: recognitionFinishedAt,
                    strokeCount: request.strokes.count,
                    cacheHit: cachedRecognition.cacheHit
                )
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
                    timing: ChordInkRecognitionTiming(
                        scheduledAt: request.scheduledAt,
                        requestedDelay: request.requestedDelay,
                        recognitionStartedAt: recognitionStartedAt,
                        recognitionFinishedAt: recognitionFinishedAt,
                        strokeCount: request.strokes.count,
                        cacheHit: cachedRecognition.cacheHit
                    )
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
    ) -> (result: ChordInkRecognitionResult, cacheHit: Bool) {
        // Recognition consumes only the prepared strokes and options. PencilKit
        // may reserialize an unchanged drawing with different archive metadata,
        // so raw drawing bytes make a valid cache miss every time an earlier
        // chord is revisited in a growing row. Key the cache by the exact
        // recognition input instead; request.drawingData still flows through
        // the payload for persistence and correction evidence.
        let key = CacheKey(strokes: request.strokes, options: request.options)
        if let result = cachedResults[key] {
            return (result, true)
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
        }
        return (result, false)
    }
}
#endif

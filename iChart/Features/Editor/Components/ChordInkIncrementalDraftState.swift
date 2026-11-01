#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// Current target ownership and independent recognition completions. A census
/// replaces source claims immediately; a result can update only its exact
/// current request. Unread collecting entries still represent their source.
struct ChordInkIncrementalDraftState {
    private struct Entry {
        var request: ChordInkRecognitionSessionRequest
        var completedPayload: ChordInkRecognitionProposalPayload?

        var identity: ChordInkRecognitionIncrementalTargetKey {
            ChordInkRecognitionIncrementalTargetKey(request: request)
        }
        var targetIdentity: ChordInkRecognitionFrozenTargetIdentity {
            request.collectingTargetLifecycle.frozenTargetIdentity
        }
    }

    private var entries: [Entry] = []
    private var contextRevision: UUID?

    /// Ordered as prepared, including explicit placeholders for every target
    /// whose reader has not completed. No target disappears while a neighbor
    /// is still being read.
    var payloads: [ChordInkRecognitionProposalPayload] {
        entries.map { $0.completedPayload ?? Self.collectingPayload(for: $0.request) }
    }

    var pendingRequests: [ChordInkRecognitionSessionRequest] {
        entries.compactMap { $0.completedPayload == nil ? $0.request : nil }
    }

    /// Call only after preparation has accepted the current live drawing
    /// revision and geometry. Replacing an entry's ink or options invalidates
    /// its completed interpretation; unrelated exact targets retain theirs.
    @discardableResult
    mutating func acceptCensus(
        _ requests: [ChordInkRecognitionSessionRequest],
        contextRevision: UUID? = nil
    ) -> [ChordInkRecognitionProposalPayload] {
        if self.contextRevision != contextRevision {
            entries.removeAll()
        }
        self.contextRevision = contextRevision
        let previous = Dictionary(grouping: entries, by: \.identity)
        let incomingCounts = Dictionary(grouping: requests, by: {
            ChordInkRecognitionIncrementalTargetKey(request: $0)
        }).mapValues(\.count)
        entries = requests.map { request in
            let identity = ChordInkRecognitionIncrementalTargetKey(request: request)
            guard incomingCounts[identity] == 1,
                  let matches = previous[identity], matches.count == 1,
                  let completed = matches[0].completedPayload else {
                return Entry(request: request)
            }
            return Entry(request: request, completedPayload: Self.rebound(completed, to: request))
        }
        return payloads
    }

    /// A result from an old census cannot overwrite changed or removed ink.
    /// Ambiguous duplicate ownership also refuses the completion so that the
    /// complete-source safety gate remains in control.
    @discardableResult
    mutating func accept(
        _ payload: ChordInkRecognitionProposalPayload
    ) -> [ChordInkRecognitionProposalPayload]? {
        guard let lifecycle = payload.targetLifecycle,
              lifecycle.stage == .stable || lifecycle.stage == .frozen else { return nil }
        let indices = entries.indices.filter { index in
            let entry = entries[index]
            return entry.request.requestID == payload.requestID
                && entry.targetIdentity == lifecycle.frozenTargetIdentity
                && entry.request.strokes == payload.strokes
                && entry.request.requiresManualReviewOnly == payload.requiresManualReviewOnly
        }
        guard indices.count == 1, let index = indices.first else { return nil }
        entries[index].completedPayload = Self.rebound(payload, to: entries[index].request,
            isReused: false)
        return payloads
    }

    /// Automatic source consumption changes the live census synchronously.
    /// Remove consumed claims before an old incremental callback can publish
    /// them again. The canvas still revalidates all retained source itself.
    mutating func retainTargets(in remainingState: ChordPreviewState) {
        let retained = Set(remainingState.draftChords.compactMap {
            $0.targetLifecycle?.frozenTargetIdentity
        })
        entries.removeAll { !retained.contains($0.targetIdentity) }
    }

    mutating func reset() {
        entries.removeAll()
        contextRevision = nil
    }

    private static func collectingPayload(
        for request: ChordInkRecognitionSessionRequest
    ) -> ChordInkRecognitionProposalPayload {
        ChordInkRecognitionProposalPayload(
            requestID: request.requestID,
            result: ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil,
                confidence: 0, requiresEditReview: request.requiresEditReview,
                metrics: ChordInkRecognitionMetrics(strokeCount: request.strokes.count)),
            strokes: request.strokes,
            drawingData: request.drawingData,
            target: request.target,
            visualOrder: request.visualOrder,
            laneLocation: request.laneLocation,
            layoutPageSize: request.layoutPageSize,
            targetLifecycle: request.collectingTargetLifecycle,
            timing: ChordInkRecognitionTiming(scheduledAt: request.scheduledAt,
                requestedDelay: request.requestedDelay, recognitionStartedAt: request.scheduledAt,
                recognitionFinishedAt: request.scheduledAt, strokeCount: request.strokes.count),
            requiresManualReviewOnly: request.requiresManualReviewOnly
        )
    }

    private static func rebound(
        _ payload: ChordInkRecognitionProposalPayload,
        to request: ChordInkRecognitionSessionRequest,
        isReused: Bool = true
    ) -> ChordInkRecognitionProposalPayload {
        var rebound = payload
        rebound.requestID = request.requestID
        rebound.strokes = request.strokes
        rebound.drawingData = request.drawingData
        rebound.target = request.target
        rebound.visualOrder = request.visualOrder
        rebound.laneLocation = request.laneLocation
        rebound.layoutPageSize = request.layoutPageSize
        rebound.targetLifecycle = request.collectingTargetLifecycle.advanced(to: .stable)
        rebound.requiresManualReviewOnly = request.requiresManualReviewOnly
        if isReused {
            rebound.timing = ChordInkRecognitionTiming(scheduledAt: request.scheduledAt,
                requestedDelay: request.requestedDelay, recognitionStartedAt: request.scheduledAt,
                recognitionFinishedAt: request.scheduledAt, strokeCount: request.strokes.count,
                cacheHit: true)
            // The retained result is not a new evaluation prediction.
            rebound.evaluationPrediction = nil
        }
        return rebound
    }
}
#endif

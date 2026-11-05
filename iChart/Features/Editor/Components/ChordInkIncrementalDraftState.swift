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
        let request = entries[index].request
        var completed = Self.rebound(payload, to: request, isReused: false)
        if payload.drawingData != request.drawingData
            || lifecycle.generationID != request.requestID || payload.timing.cacheHit {
            completed.readerRetryProof = nil
        }
        entries[index].completedPayload = completed
        return payloads
    }

    /// A receipt belongs to one freshly read target and the new event actually
    /// appended for it. Normal rendering may still use cached candidates.
    func readerRetryProofs(
        for outcome: ChordInkDraftRenderCoordinator.AutomaticOutcome,
        state: ChordPreviewState,
        originalChart: Chart,
        consent currentConsent: @autoclosure () -> IChartTelemetryConsentSnapshot
    ) -> [ChordInkReaderRetryProof] {
        guard entries.contains(where: { $0.completedPayload?.readerRetryProof != nil }),
              !outcome.result.didRejectIncompleteSourceCoverage,
              outcome.result.unresolvedDraftIDs.isEmpty,
              originalChart.id == outcome.chart.id else { return [] }
        let consent = currentConsent()
        guard consent.isGranted else { return [] }

        let originalEventIDs = Set(originalChart.measures.flatMap(\.chordEvents).map(\.id))
        let renderedEventIDs = Set(outcome.result.renderedChordIDs)
        let renderMap = outcome.result.renderedChordIDsByDraftID
        guard renderedEventIDs.count == outcome.result.renderedChordIDs.count,
              renderMap.count == renderedEventIDs.count,
              Set(renderMap.values) == renderedEventIDs else { return [] }
        let events = Dictionary(grouping: outcome.chart.measures.flatMap(\.chordEvents), by: \.id)
        return state.draftChords.compactMap { draft in
            guard outcome.consumedDraftIDs.contains(draft.id),
                  !draft.isStale, draft.selectedText == nil, let lifecycle = draft.targetLifecycle,
                  let selectedText = ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft),
                  let eventID = renderMap[draft.id], !originalEventIDs.contains(eventID),
                  let matches = events[eventID], matches.count == 1, let event = matches.first,
                  event.rawInput == selectedText, event.sourceInkData == draft.drawingData else { return nil }
            let matchingEntries = entries.filter { $0.targetIdentity == lifecycle.frozenTargetIdentity }
            guard matchingEntries.count == 1, let payload = matchingEntries.first?.completedPayload,
                  payload.requestID == lifecycle.generationID, payload.drawingData == draft.drawingData,
                  payload.result == draft.recognitionResult,
                  let proof = payload.readerRetryProof, proof.consent == consent,
                  Self.retrySupplied(selectedText, result: payload.result, proof: proof),
                  let pipeline = payload.result.fallbackPipelineVersion(for: selectedText),
                  event.sourceRecognitionPipelineVersion == pipeline else { return nil }
            return proof
        }
    }

    private static func retrySupplied(
        _ selectedText: String,
        result: ChordInkRecognitionResult,
        proof: ChordInkReaderRetryProof
    ) -> Bool {
        let vision = ChordInkVisionAutomaticFallbackRecognizer()
        guard let selected = ChordRecognitionCompendium.match(selectedText)?.displayText,
              let winner = result.fallbackEvidence.last, winner.outcome == .completed,
              winner.engineIdentifier == vision.identifier, winner.engineVersion == vision.version,
              winner.attemptCount == 2, proof.supportedCandidateCount > 0,
              proof.supportedCandidateCount <= result.reviewCandidateScores.count,
              result.reviewCandidateScores.suffix(proof.supportedCandidateCount).compactMap(\.displayText)
                == winner.candidateTexts,
              winner.candidateTexts.count == proof.supportedCandidateCount,
              winner.candidateTexts.contains(selected) else { return false }

        // The worker appends the first provider's supported output as one
        // suffix. Equal text from primary, personal or older fallback evidence
        // is ambiguous even if the winning provider also returned it.
        let otherScores = result.candidateScores
            + result.reviewCandidateScores.dropLast(proof.supportedCandidateCount)
        var otherTexts = [result.match?.displayText, result.personalSuggestion?.text].compactMap { $0 }
        otherTexts += result.rawCandidates + result.reviewRootAlternatives
        otherTexts += otherScores.flatMap { [$0.text, $0.displayText].compactMap { $0 } }
        otherTexts += result.fallbackEvidence.dropLast().flatMap(\.candidateTexts)
        return !otherTexts.contains { ChordRecognitionCompendium.match($0)?.displayText == selected }
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

    mutating func discardReaderRetryProofs() {
        for index in entries.indices {
            entries[index].completedPayload?.readerRetryProof = nil
        }
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
            rebound.readerRetryProof = nil
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

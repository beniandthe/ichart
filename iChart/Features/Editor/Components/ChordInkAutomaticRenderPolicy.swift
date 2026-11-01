#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// Completion timing, source isolation, and the user's automatic entry choice.
/// Choosing an editable guess never changes the recognizer's trust decision.
enum ChordInkAutomaticRenderPolicy {
    static let idleDelay: TimeInterval = 1.2
    // A first vertical stroke can still acquire a second stroke, repeat dots,
    // or an ending label. Structural ink keeps the full shared pause instead
    // of using horizontal chord separation as an early completion signal.
    static let structuralIdleDelay: TimeInterval = 2
    static let spaceDelay: TimeInterval = 0.35
    static let minimumChordGap: CGFloat = 24

    static func requiredIdleDelay(for state: ChordPreviewState) -> TimeInterval {
        state.draftBarlines.isEmpty && state.draftEndings.isEmpty ? idleDelay : structuralIdleDelay
    }

    static func isTrusted(_ draft: ChordInkDraft) -> Bool {
        guard !draft.isStale,
              !draft.requiresManualReviewOnly,
              let lifecycle = draft.targetLifecycle,
              lifecycle.stage == .stable || lifecycle.stage == .frozen,
              let decision = draft.recognitionDecision,
              decision.action == .trusted,
              let acceptedText = decision.acceptedText,
              draft.previewText == acceptedText,
              draft.isRenderable else { return false }
        return true
    }

    /// Automatic mode puts the current best supported read onto the chart so
    /// it can be edited there. Confidence and confirmation remain diagnostic
    /// evidence; neither is promoted to trust or recorded as user acceptance.
    static func automaticCandidateText(for draft: ChordInkDraft) -> String? {
        guard !draft.isStale, let lifecycle = draft.targetLifecycle,
              lifecycle.stage == .stable || lifecycle.stage == .frozen else { return nil }
        if let selected = draft.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !selected.isEmpty {
            // Never replace an explicit invalid edit with a different guess.
            return ChordInkRenderResolutionPolicy.bestCandidateText(preferredTexts: [selected], candidateTexts: [])
        }
        var candidates = draft.candidateTexts
        if let result = draft.recognitionResult {
            let ranked = result.candidateScores.sorted { $0.confidence > $1.confidence }
            let review = result.reviewCandidateScores.sorted { $0.confidence > $1.confidence }
            for score in ranked + review {
                if let text = score.displayText { candidates.append(text) }
                candidates.append(score.text)
            }
            candidates.append(contentsOf: result.rawCandidates)
        }
        return ChordInkRenderResolutionPolicy.bestCandidateText(
            preferredTexts: [draft.bestCandidateText, draft.recognitionResult?.match?.displayText],
            candidateTexts: candidates)
    }

    static func elapsedSinceInput(now: Date, lastInputAt: Date?) -> TimeInterval? {
        guard let lastInputAt else { return nil }
        let elapsed = now.timeIntervalSince(lastInputAt)
        return elapsed.isFinite && elapsed >= 0 ? elapsed : nil
    }

    /// A target may finish before the idle deadline when later ink has moved
    /// into a separate region. Any unrepresented nearby slash, bass, accidental
    /// or extension keeps the target as ink, even after the idle deadline.
    static func isSpatiallyIsolated(
        originalStrokeIndices: Set<Int>,
        source: PKDrawing,
        pageSize: CGSize?,
        requiresLaterInk: Bool
    ) -> Bool {
        guard !originalStrokeIndices.isEmpty,
              originalStrokeIndices.allSatisfy(source.strokes.indices.contains) else { return false }
        let visible = source.strokes.enumerated().compactMap { index, stroke -> (Int, CGRect)? in
            let fragments = PencilKitInkAdapter.visibleStrokeFragments(from: stroke)
            guard !fragments.isEmpty else { return nil }
            let bounds = fragments.reduce(CGRect.null) { $0.union($1.renderBounds) }.standardized
            guard !bounds.isNull, !bounds.isInfinite,
                  bounds.minX.isFinite, bounds.minY.isFinite,
                  bounds.maxX.isFinite, bounds.maxY.isFinite else { return nil }
            return (index, bounds)
        }
        guard let newestIndex = visible.last?.0 else { return false }
        if requiresLaterInk, originalStrokeIndices.contains(newestIndex) { return false }
        let ownedBounds = visible.filter { originalStrokeIndices.contains($0.0) }
            .reduce(CGRect.null) { $0.union($1.1) }
        guard !ownedBounds.isNull else { return false }
        let pageScale = pageSize.map { $0.width.isFinite && $0.width > 0 ? $0.width / 900 : 1 } ?? 1
        let requiredGap = minimumChordGap * pageScale
        let neighbors = visible.filter { !originalStrokeIndices.contains($0.0) }
        if requiresLaterInk, neighbors.isEmpty { return false }
        return neighbors.allSatisfy { _, bounds in
            let horizontalGap = max(bounds.minX - ownedBounds.maxX, ownedBounds.minX - bounds.maxX)
            // Raised extensions and lowered slash bass may have a large
            // vertical gap while still belonging to this chord. Only a
            // horizontal word gap is sufficient without a verified lane ID.
            return horizontalGap >= requiredGap
        }
    }
}
#endif

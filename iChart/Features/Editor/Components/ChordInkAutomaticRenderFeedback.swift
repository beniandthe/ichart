#if canImport(UIKit) && canImport(PencilKit)
import Foundation

enum ChordInkAutomaticRenderReason: String, Equatable {
    case waiting, reading, recognitionReview, noRead, needsSpace
    case needsSourceRefresh, repeatReview, endingReview, placementUnavailable, barlinePlacementUnavailable
    case unrepresentedInk, restoredInk, adjacentWriting, triangleQualityReview

    var userMessage: String {
        switch self {
        case .waiting: return "Finish writing the chord or leave space before the next chord."
        case .reading: return "Reading your writing…"
        case .recognitionReview: return "Check this chord before rendering it."
        case .noRead: return "This chord could not be read. Review or rewrite it."
        case .needsSpace: return "The rendered chord would overlap writing or another chord. Move or rewrite it with more space."
        case .needsSourceRefresh: return "Your writing changed. Review the latest ink or rewrite it."
        case .repeatReview: return "Finish or correct the repeat signs. Use Fix Writing for help."
        case .endingReview: return "Choose the ending label and measure range, then render the bracket."
        case .placementUnavailable: return "This chord could not be placed safely. Review or rewrite it."
        case .barlinePlacementUnavailable: return "This barline could not be placed. Erase it or redraw it where there is room."
        case .unrepresentedInk: return "Some writing could not be matched to a chord or chart mark. Review or rewrite it."
        case .restoredInk: return "Review this saved writing, or continue writing to render automatically."
        case .adjacentWriting: return "Finish or review the nearby writing so these chords can be separated."
        case .triangleQualityReview: return "The triangle is unclear. Enter the chord you meant or rewrite it."
        }
    }

    var isActionable: Bool { self != .waiting && self != .reading }
}

struct ChordInkAutomaticRenderFeedback: Equatable {
    var reasonsByDraftID: [UUID: ChordInkAutomaticRenderReason] = [:]
    var globalReason: ChordInkAutomaticRenderReason?

    func retainingDraftIDs(_ ids: Set<UUID>, keepsGlobalReason: Bool = true) -> Self {
        Self(reasonsByDraftID: reasonsByDraftID.filter { ids.contains($0.key) },
            globalReason: keepsGlobalReason ? globalReason : nil)
    }

    mutating func set(_ reason: ChordInkAutomaticRenderReason, for ids: Set<UUID>, globallyIfEmpty: Bool = true) {
        for id in ids { reasonsByDraftID[id] = reason }
        if ids.isEmpty && globallyIfEmpty { globalReason = reason }
    }

    static func baseline(for state: ChordPreviewState) -> Self {
        Self(reasonsByDraftID: Dictionary(state.draftChords.map {
            ($0.id, ChordInkAutomaticFeedbackPolicy.recognitionReason(for: $0))
        }, uniquingKeysWith: { first, _ in first }),
            globalReason: ChordDraftRepeatReviewPolicy.hasIncompleteRepeat(in: state) ? .repeatReview : nil)
    }
}

struct ChordInkAutomaticActivity: Equatable {
    enum Phase: String { case waiting, reading, settled, restored, empty }
    var chartID: UUID
    var sourceRevision: UInt64
    var hasSourceInk: Bool
    var phase: Phase
    var pendingTargetCount: Int
    var inputAt: Date?
    var renderReadyAt: Date? = nil
    var feedback: ChordInkAutomaticRenderFeedback = .init()
}

enum ChordInkAutomaticFeedbackPolicy {
    static let readingTimeout: TimeInterval = 3

    static func recognitionReason(for draft: ChordInkDraft) -> ChordInkAutomaticRenderReason {
        if draft.isStale { return .needsSourceRefresh }
        if draft.targetLifecycle?.stage == .collecting { return .reading }
        if draft.recognitionResult?.requiresTriangleQualityReview == true, draft.previewText == nil {
            return .triangleQualityReview
        }
        if ChordInkAutomaticRenderPolicy.isTrusted(draft) { return .waiting }
        // Automatic mode can recover supported score/raw evidence that the
        // preview has not selected yet. Report the same eligibility used by
        // the render attempt without changing confidence or reader trust.
        return ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft) != nil
            ? .recognitionReview : .noRead
    }

    static func isReadingOverdue(_ activity: ChordInkAutomaticActivity, now: Date) -> Bool {
        guard activity.hasSourceInk, activity.phase == .reading,
              let inputAt = activity.inputAt ?? activity.renderReadyAt else { return false }
        return now.timeIntervalSince(inputAt) >= readingTimeout
    }
}
#endif

import Foundation

/// One label-agnostic policy shared by chart review, comparison and evaluation.
/// A corrected personal example does not establish the identity of a fresh
/// target. Keep any differing native reading as the default for explicit review.
enum PersonalInkArbitrationPolicy {
    static let version = "baseline-preserved-v3-personal-alternatives"

    enum Disposition: String, Codable {
        // correctedReview remains decodable for historical evaluation evidence.
        case baselineOnly, agreement, protectedBaseline, alternative, correctedReview, personalRecovery
    }

    struct Selection {
        var text: String?
        var disposition: Disposition
        var prefersPersonal: Bool { disposition == .correctedReview || disposition == .personalRecovery }
    }

    static func select(baselineText: String?, baselineTrusted: Bool,
                       suggestion: ChordInkPersonalSuggestion?) -> Selection {
        guard let suggestion, suggestion.distance.isFinite, suggestion.distance >= 0,
              suggestion.supportingExampleCount > 0,
              ChordRecognitionCompendium.match(suggestion.text)?.displayText == suggestion.text else {
            return Selection(text: baselineText, disposition: .baselineOnly)
        }
        if suggestion.text == baselineText { return Selection(text: baselineText, disposition: .agreement) }
        if baselineTrusted { return Selection(text: baselineText, disposition: .protectedBaseline) }
        if baselineText == nil { return Selection(text: suggestion.text, disposition: .personalRecovery) }
        return Selection(text: baselineText, disposition: .alternative)
    }
}

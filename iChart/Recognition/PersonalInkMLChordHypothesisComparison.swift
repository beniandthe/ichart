import Foundation

/// Complete-token hypotheses conditional on the supplied proposed groups and
/// their reading order. They are not ownership resolutions or accepted reads.
struct PersonalInkMLChordHypothesisComparison: Codable, Equatable {
    static let version = "complete-token-ml-hypotheses-v1"
    let version: String
    let generic: PersonalInkMLChordComposer.Result
    let personal: PersonalInkMLChordComposer.Result
    let anchored: PersonalInkMLChordComposer.Result?
    let assuranceNote: String

    static func make(prediction: PersonalInkLearnedComparison.Prediction,
                     sourceStrokeCount: Int) throws -> Self {
        // Never give the intentionally unresolved selective route a chord by
        // bypassing its stop-before-query-encoding boundary.
        guard prediction.ownership == nil else { throw PersonalInkMLChordComposer.Failure.invalidPartition }
        let composer = PersonalInkMLChordComposer()
        let generic = try composer.compose(sourceStrokeCount: sourceStrokeCount,
            orderedColumns: prediction.glyphs.map {
                .init(originalStrokeIndexes: $0.originalStrokeIndexes, ranks: $0.generic)
            })
        let personal = try composer.compose(sourceStrokeCount: sourceStrokeCount,
            orderedColumns: prediction.glyphs.map {
                .init(originalStrokeIndexes: $0.originalStrokeIndexes, ranks: $0.personal)
            })
        let anchored: PersonalInkMLChordComposer.Result?
        if let ranks = prediction.anchored?.glyphRanks {
            guard ranks.count == prediction.glyphs.count else { throw PersonalInkMLChordComposer.Failure.invalidColumnCount }
            anchored = try composer.compose(sourceStrokeCount: sourceStrokeCount,
                orderedColumns: zip(prediction.glyphs, ranks).map {
                    .init(originalStrokeIndexes: $0.0.originalStrokeIndexes, ranks: $0.1)
                })
        } else { anchored = nil }
        return Self(version: Self.version, generic: generic, personal: personal, anchored: anchored,
            assuranceNote: "Conditional on unverified proposed groups and reading order. Grammar-valid alternatives are hypotheses, not trusted reads. Historical top-1 predictions and scores are unchanged.")
    }
}

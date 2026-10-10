import Foundation

/// Ink-only evidence at the grouping boundary. A complete index partition
/// establishes preservation, not which strokes belong to the same symbol.
struct PersonalInkOwnershipAssessment: Codable, Equatable {
    static let currentVersion = "ink-only-geometry-ownership-v1"
    // This is the existing learned-comparison group limit, not a confidence
    // threshold or an expected owner count.
    static let maximumGroupCount = 16

    enum Disposition: String, Codable { case unresolved }
    enum Reason: String, Codable { case uncalibratedGeometryProposal }
    enum Failure: LocalizedError {
        case invalidSourceCount, invalidPartition, invalidEvidence
        var errorDescription: String? {
            switch self {
            case .invalidSourceCount: return "Ownership evidence needs a supported, nonempty original input."
            case .invalidPartition: return "The proposal must preserve every original stroke exactly once."
            case .invalidEvidence: return "This ownership evidence version or disposition is unsupported."
            }
        }
    }

    let version: String
    let disposition: Disposition
    let reason: Reason
    let sourceStrokeCount: Int
    let proposedGroups: [[Int]]
    let hasCompleteCoverage: Bool

    /// Deliberately accepts no profile, answer, expected count, ranks or text.
    /// There is no calibrated/resolved constructor in this policy version.
    static func assess(sourceStrokeCount: Int, proposedGroups: [[Int]]) throws -> Self {
        try validate(sourceStrokeCount: sourceStrokeCount, proposedGroups: proposedGroups)
        return Self(sourceStrokeCount: sourceStrokeCount, proposedGroups: proposedGroups)
    }

    private init(sourceStrokeCount: Int, proposedGroups: [[Int]]) {
        version = Self.currentVersion
        disposition = .unresolved
        reason = .uncalibratedGeometryProposal
        self.sourceStrokeCount = sourceStrokeCount
        self.proposedGroups = proposedGroups
        hasCompleteCoverage = true
    }

    private static func validate(sourceStrokeCount: Int, proposedGroups: [[Int]]) throws {
        guard (1...ChordInkFeatureSchema.maximumStrokeCount).contains(sourceStrokeCount) else {
            throw Failure.invalidSourceCount
        }
        guard !proposedGroups.isEmpty, proposedGroups.count <= maximumGroupCount,
              proposedGroups.allSatisfy({ !$0.isEmpty }) else { throw Failure.invalidPartition }
        let indexes = proposedGroups.flatMap { $0 }
        guard indexes.count == sourceStrokeCount,
              indexes.allSatisfy({ (0..<sourceStrokeCount).contains($0) }),
              Set(indexes).count == sourceStrokeCount else { throw Failure.invalidPartition }
        // Keep both supplied orders. The lossless proposer supplies original
        // source-index order within groups, not wrapper or feature-point order.
    }

    private enum CodingKeys: String, CodingKey {
        case version, disposition, reason, sourceStrokeCount, proposedGroups, hasCompleteCoverage
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(String.self, forKey: .version)
        let disposition = try values.decode(Disposition.self, forKey: .disposition)
        let reason = try values.decode(Reason.self, forKey: .reason)
        guard version == Self.currentVersion, disposition == .unresolved,
              reason == .uncalibratedGeometryProposal,
              try values.decode(Bool.self, forKey: .hasCompleteCoverage) else { throw Failure.invalidEvidence }
        self = try Self.assess(sourceStrokeCount: values.decode(Int.self, forKey: .sourceStrokeCount),
            proposedGroups: values.decode([[Int]].self, forKey: .proposedGroups))
    }
}

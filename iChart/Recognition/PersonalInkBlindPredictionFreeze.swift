import Foundation
import CryptoKit

/// An engineering evaluation artifact made from source ink before any truth
/// join. A complete partition only establishes structural coverage; this type
/// makes no claim that a group owns a glyph or that a top choice is accepted.
/// No prompt, intended label, truth annotation, or chord composition enters
/// this API. The caller supplies an already frozen fit and independently
/// verified runtime/code commitments; their digest spelling is checked here.
struct PersonalInkBlindPredictionFreeze: Encodable, Equatable {
    static let currentVersion = "blind-ink-prediction-freeze-v1"
    static let engineeringArtifactKind = "engineering-only-blind-evaluation-v1"
    static let maximumPacketBytes = 4 * 1_024 * 1_024
    static let maximumStrokeCount = 256
    static let maximumPointsPerStroke = 8_192
    static let maximumTotalPointCount = 32_768

    enum Failure: Error, Equatable {
        case invalidCommitment(field: String)
        case packetBudgetExceeded
        case invalidPacket
        case invalidSuppliedPartition
        case sourceChanged
    }

    struct Glyph: Encodable, Equatable {
        let originalStrokeIndexes: [Int]
        let sharedTop1: String?
        let personalTop1: String?

        private enum CodingKeys: String, CodingKey {
            case originalStrokeIndexes, sharedTop1, personalTop1
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(originalStrokeIndexes, forKey: .originalStrokeIndexes)
            // encode(Optional) emits an explicit null instead of omitting it.
            try container.encode(sharedTop1, forKey: .sharedTop1)
            try container.encode(personalTop1, forKey: .personalTop1)
        }
    }

    struct Arm: Encodable, Equatable {
        enum Outcome: String, Encodable, Equatable { case read; case invalidInk = "invalid-ink" }
        let outcome: Outcome
        let glyphs: [Glyph]

        static let invalidInk = Arm(outcome: .invalidInk, glyphs: [])
    }

    let version: String
    let artifactKind: String
    let sourcePacketSHA256: String
    let ownershipReceiptSHA256: String?
    let sourceStrokeCount: Int
    let encoderIdentity: String
    let profileSHA256: String
    let runtimeSHA256: String
    let codeSHA256: String
    let automatic: Arm
    let supplied: Arm?

    /// Uses the same model's supplied-original-group seam for both arms. The
    /// profile provider allows a caller to detect an opt-out or exact profile
    /// mutation during inference, including changes without a revision bump.
    static func freeze(
        sourcePacketData: Data,
        suppliedOriginalIndexGroups: [[Int]]? = nil,
        ownershipReceiptSHA256: String?,
        runtimeSHA256: String,
        codeSHA256: String,
        model: PersonalInkLearnedComparison,
        currentProfile: () -> PersonalInkProfile
    ) throws -> Self {
        try validateDigest(runtimeSHA256, field: "runtimeSHA256")
        try validateDigest(codeSHA256, field: "codeSHA256")
        if let ownershipReceiptSHA256 {
            try validateDigest(ownershipReceiptSHA256, field: "ownershipReceiptSHA256")
        }
        let frozenProfile = try checkedProfile(model: model, currentProfile: currentProfile)
        let packet = try decodeBoundedPacket(sourcePacketData)
        let source = packet.preparedStrokes()
        // Reject a malformed supplied partition before either arm can encode.
        // More than 16 complete groups is a model no-read, not lost coverage.
        if let groups = suppliedOriginalIndexGroups {
            guard isCompletePartition(groups, sourceStrokeCount: source.count) else {
                throw Failure.invalidSuppliedPartition
            }
        }
        let profileEncoder = JSONEncoder()
        profileEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let profileDigest = digest(try profileEncoder.encode(frozenProfile))

        let sourceRepresentable: Bool
        do {
            _ = try ChordInkPreparedFeatureGeometry.prepare(strokes: source)
            sourceRepresentable = true
        } catch is ChordInkFeatureEncodingError {
            sourceRepresentable = false
        }
        _ = try checkedProfile(model: model, currentProfile: currentProfile)

        let automatic: Arm
        if sourceRepresentable {
            // Freeze the existing losslessSourceV2 grouping construction
            // exactly: recomputed grouping bounds, no creation offsets, and
            // original points (including their timing availability). Query
            // inputs below always come from the exact original packet.
            let geometry = source.map { InkStroke(points: $0.points) }
            let groups = StrokeClusterer(wrapperPolicy: .preserveOriginalInk)
                .indexedClusters(geometry).map { $0.originalIndexes.sorted() }
            automatic = try readArm(source: source, groups: groups, model: model,
                profile: frozenProfile)
        } else {
            automatic = .invalidInk
        }
        _ = try checkedProfile(model: model, currentProfile: currentProfile)

        let supplied: Arm?
        if let groups = suppliedOriginalIndexGroups {
            supplied = sourceRepresentable
                ? try readArm(source: source, groups: groups.map { $0.sorted() },
                    model: model, profile: frozenProfile)
                : .invalidInk
        } else {
            supplied = nil
        }
        _ = try checkedProfile(model: model, currentProfile: currentProfile)
        // Packet bytes, not floating-point Equatable, preserve signed zero and
        // NaN timing payloads when checking source immutability after inference.
        guard try ChordInkCanonicalTrajectoryPacket(strokes: source).canonicalData()
                == sourcePacketData else { throw Failure.sourceChanged }
        guard model.profile == frozenProfile else {
            throw PersonalInkLearnedComparison.Failure.staleProfile
        }
        return Self(version: currentVersion, artifactKind: engineeringArtifactKind,
            sourcePacketSHA256: digest(sourcePacketData),
            ownershipReceiptSHA256: ownershipReceiptSHA256,
            sourceStrokeCount: source.count, encoderIdentity: model.encoderIdentity,
            profileSHA256: profileDigest, runtimeSHA256: runtimeSHA256,
            codeSHA256: codeSHA256, automatic: automatic, supplied: supplied)
    }

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey {
        case version, artifactKind, sourcePacketSHA256, ownershipReceiptSHA256
        case sourceStrokeCount, encoderIdentity, profileSHA256, runtimeSHA256
        case codeSHA256, automatic, supplied
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(artifactKind, forKey: .artifactKind)
        try container.encode(sourcePacketSHA256, forKey: .sourcePacketSHA256)
        try container.encode(ownershipReceiptSHA256, forKey: .ownershipReceiptSHA256)
        try container.encode(sourceStrokeCount, forKey: .sourceStrokeCount)
        try container.encode(encoderIdentity, forKey: .encoderIdentity)
        try container.encode(profileSHA256, forKey: .profileSHA256)
        try container.encode(runtimeSHA256, forKey: .runtimeSHA256)
        try container.encode(codeSHA256, forKey: .codeSHA256)
        try container.encode(automatic, forKey: .automatic)
        try container.encode(supplied, forKey: .supplied)
    }

    private static func readArm(source: [InkStroke], groups: [[Int]],
                                model: PersonalInkLearnedComparison,
                                profile: PersonalInkProfile) throws -> Arm {
        guard (1...16).contains(groups.count),
              isCompletePartition(groups, sourceStrokeCount: source.count) else {
            return .invalidInk
        }
        do {
            let reading = try model.readSuppliedOriginalGroups(source,
                originalIndexGroups: groups, currentProfile: profile)
            return Arm(outcome: .read, glyphs: reading.glyphs.map { glyph in
                Glyph(originalStrokeIndexes: glyph.originalStrokeIndexes.sorted(),
                    sharedTop1: glyph.generic.first?.label,
                    personalTop1: glyph.personal.first?.label)
            })
        } catch PersonalInkLearnedComparison.Failure.invalidInk {
            return .invalidInk
        } catch is ChordInkFeatureEncodingError {
            // Typed geometry/representation no-reads retain the whole attempt.
            // Technical encoder failures and invalidEncoder propagate instead.
            return .invalidInk
        }
    }

    private static func checkedProfile(model: PersonalInkLearnedComparison,
                                       currentProfile: () -> PersonalInkProfile) throws
        -> PersonalInkProfile {
        let current = currentProfile()
        guard current.isEnabled else { throw PersonalInkLearnedComparison.Failure.disabled }
        guard current == model.profile else {
            throw PersonalInkLearnedComparison.Failure.staleProfile
        }
        return current
    }

    private static func isCompletePartition(_ groups: [[Int]], sourceStrokeCount: Int) -> Bool {
        guard groups.allSatisfy({ !$0.isEmpty }) else { return false }
        let indexes = groups.flatMap { $0 }
        return indexes.count == sourceStrokeCount
            && indexes.allSatisfy { (0..<sourceStrokeCount).contains($0) }
            && Set(indexes).count == sourceStrokeCount
    }

    private static func validateDigest(_ value: String, field: String) throws {
        guard value.utf8.count == 64, value.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }) else { throw Failure.invalidCommitment(field: field) }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Check byte and nested-array budgets before the lossless packet decoder
    /// materializes any points. Array counts are inspected without decoding
    /// point values; canonical validation still occurs in the packet decoder.
    static func decodeBoundedPacket(_ data: Data) throws -> ChordInkCanonicalTrajectoryPacket {
        guard data.count <= maximumPacketBytes else { throw Failure.packetBudgetExceeded }
        let decoder = JSONDecoder()
        decoder.userInfo[budgetKey] = DecodeBudget()
        do {
            _ = try decoder.decode(PacketBudget.self, from: data)
            return try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(data)
        } catch Failure.packetBudgetExceeded {
            throw Failure.packetBudgetExceeded
        } catch {
            throw Failure.invalidPacket
        }
    }

    private static let budgetKey = CodingUserInfoKey(rawValue: "blindInkPredictionFreezeBudget")!
    private final class DecodeBudget { var totalPoints = 0 }

    private struct PacketBudget: Decodable {
        private enum CodingKeys: String, CodingKey { case strokes }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var strokes = try container.nestedUnkeyedContainer(forKey: .strokes)
            guard let count = strokes.count else { throw Failure.invalidPacket }
            guard count <= maximumStrokeCount else { throw Failure.packetBudgetExceeded }
            while !strokes.isAtEnd { _ = try strokes.decode(StrokeBudget.self) }
        }
    }

    private struct StrokeBudget: Decodable {
        private enum CodingKeys: String, CodingKey { case points }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let points = try container.nestedUnkeyedContainer(forKey: .points)
            guard let count = points.count,
                  let budget = decoder.userInfo[budgetKey] as? DecodeBudget else {
                throw Failure.invalidPacket
            }
            guard count <= maximumPointsPerStroke,
                  count <= maximumTotalPointCount - budget.totalPoints else {
                throw Failure.packetBudgetExceeded
            }
            budget.totalPoints += count
        }
    }
}

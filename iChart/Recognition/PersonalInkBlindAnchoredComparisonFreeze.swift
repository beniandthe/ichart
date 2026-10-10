import Foundation
import CryptoKit

/// Offline, source-bound comparison on exactly the legacy freeze's groups.
/// Ranks are the same reader's returned top three, not probabilities, ownership
/// truth, chord acceptance, or native live results. Freeze-v1 remains unchanged.
struct PersonalInkBlindAnchoredComparisonFreeze: Encodable, Equatable {
    static let currentVersion = "blind-ink-anchored-comparison-freeze-v1"

    enum Failure: Error, Equatable { case invalidReading, legacyTop1Mismatch, sourceChanged }
    enum AnchorStatus: String, Encodable, Equatable { case available, unavailable }

    struct Glyph: Encodable, Equatable {
        let originalStrokeIndexes: [Int]
        let sharedRanks: [PersonalInkLearnedComparison.Rank]
        let originalResidualRanks: [PersonalInkLearnedComparison.Rank]
        let anchoredRanks: [PersonalInkLearnedComparison.Rank]?
        var sharedTop1: String? { sharedRanks.first?.label }
        var originalResidualTop1: String? { originalResidualRanks.first?.label }
        var anchoredTop1: String? { anchoredRanks?.first?.label }

        private enum CodingKeys: String, CodingKey {
            case originalStrokeIndexes, sharedRanks, originalResidualRanks, anchoredRanks
            case sharedTop1, originalResidualTop1, anchoredTop1
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(originalStrokeIndexes, forKey: .originalStrokeIndexes)
            try container.encode(sharedRanks, forKey: .sharedRanks)
            try container.encode(originalResidualRanks, forKey: .originalResidualRanks)
            try container.encode(anchoredRanks, forKey: .anchoredRanks)
            try container.encode(sharedTop1, forKey: .sharedTop1)
            try container.encode(originalResidualTop1, forKey: .originalResidualTop1)
            try container.encode(anchoredTop1, forKey: .anchoredTop1)
        }
    }

    struct Arm: Encodable, Equatable {
        let outcome: PersonalInkBlindPredictionFreeze.Arm.Outcome
        let anchorStatus: AnchorStatus
        let glyphs: [Glyph]
    }

    let version = Self.currentVersion
    let artifactKind = "engineering-only-anchored-comparison-v1"
    let nativeLiveResult = false
    let accuracyMeasured = false
    let glyphOwnershipVerified = false
    let trainingEligible = false
    let predictionChronologyVerified = false
    let rankingScope = "same-reader-returned-top-three"
    let legacyFreeze: PersonalInkBlindPredictionFreeze
    let legacyCanonicalData: Data
    let legacyCanonicalSHA256: String
    let automatic: Arm
    let supplied: Arm?

    static func freeze(
        sourcePacketData: Data,
        suppliedOriginalIndexGroups: [[Int]]? = nil,
        ownershipReceiptSHA256: String?,
        runtimeSHA256: String,
        codeSHA256: String,
        model: PersonalInkLearnedComparison,
        currentProfile: () -> PersonalInkProfile
    ) throws -> Self {
        let profile = currentProfile()
        guard profile.isEnabled else { throw PersonalInkLearnedComparison.Failure.disabled }
        guard profile == model.profile else { throw PersonalInkLearnedComparison.Failure.staleProfile }
        let profileData = try canonical(profile)
        try checkProfile(model, currentProfile, profileData)
        let legacy = try PersonalInkBlindPredictionFreeze.freeze(
            sourcePacketData: sourcePacketData, suppliedOriginalIndexGroups: suppliedOriginalIndexGroups,
            ownershipReceiptSHA256: ownershipReceiptSHA256, runtimeSHA256: runtimeSHA256,
            codeSHA256: codeSHA256, model: model, currentProfile: currentProfile)
        let legacyData = try legacy.canonicalData()
        let packet = try PersonalInkBlindPredictionFreeze.decodeBoundedPacket(sourcePacketData)
        let source = packet.preparedStrokes()

        func read(_ legacyArm: PersonalInkBlindPredictionFreeze.Arm) throws -> Arm {
            try checkProfile(model, currentProfile, profileData)
            let result: Arm
            if legacyArm.outcome == .invalidInk {
                guard legacyArm.glyphs.isEmpty else { throw Failure.invalidReading }
                result = Arm(outcome: .invalidInk,
                    anchorStatus: model.anchoredAvailable ? .available : .unavailable, glyphs: [])
            } else {
                // No new grouping, whole-head query, composition or fallback.
                let reading = try model.readSuppliedOriginalGroups(source,
                    originalIndexGroups: legacyArm.glyphs.map(\.originalStrokeIndexes),
                    currentProfile: profile)
                result = try align(legacyArm: legacyArm, reading: reading,
                    sourceStrokeCount: source.count, encoderIdentity: model.encoderIdentity,
                    anchoredAvailable: model.anchoredAvailable)
            }
            try checkProfile(model, currentProfile, profileData)
            return result
        }
        let automatic = try read(legacy.automatic)
        let supplied = try legacy.supplied.map(read)
        try checkProfile(model, currentProfile, profileData)
        guard try ChordInkCanonicalTrajectoryPacket(strokes: source).canonicalData() == sourcePacketData,
              try legacy.canonicalData() == legacyData else { throw Failure.sourceChanged }
        return Self(legacyFreeze: legacy, legacyCanonicalData: legacyData,
            legacyCanonicalSHA256: digest(legacyData), automatic: automatic, supplied: supplied)
    }

    /// Defensive alignment is independently testable with synthetic readings.
    /// Complete coverage is structural only; it never certifies glyph ownership.
    static func align(legacyArm: PersonalInkBlindPredictionFreeze.Arm,
                      reading: PersonalInkLearnedComparison.GroupIdentityReading,
                      sourceStrokeCount: Int, encoderIdentity: String,
                      anchoredAvailable: Bool) throws -> Arm {
        let groups = legacyArm.glyphs.map(\.originalStrokeIndexes)
        let indexes = groups.flatMap { $0 }
        guard legacyArm.outcome == .read, (1...16).contains(groups.count),
              groups.allSatisfy({ !$0.isEmpty && $0 == $0.sorted() && Set($0).count == $0.count }),
              indexes.count == sourceStrokeCount, Set(indexes) == Set(0..<sourceStrokeCount),
              reading.sourceStrokeCount == sourceStrokeCount, reading.encoderIdentity == encoderIdentity,
              reading.glyphs.map(\.originalStrokeIndexes) == groups,
              anchoredAvailable == (reading.anchoredGlyphRanks != nil),
              reading.anchoredGlyphRanks.map({ $0.count == groups.count }) ?? true else {
            throw Failure.invalidReading
        }
        let glyphs = try reading.glyphs.enumerated().map { index, glyph -> Glyph in
            let anchored = reading.anchoredGlyphRanks?[index]
            guard validRanks(glyph.generic), validRanks(glyph.personal),
                  anchored.map(validRanks) ?? true else { throw Failure.invalidReading }
            guard glyph.generic.first?.label == legacyArm.glyphs[index].sharedTop1,
                  glyph.personal.first?.label == legacyArm.glyphs[index].personalTop1 else {
                throw Failure.legacyTop1Mismatch
            }
            return Glyph(originalStrokeIndexes: glyph.originalStrokeIndexes,
                sharedRanks: glyph.generic, originalResidualRanks: glyph.personal, anchoredRanks: anchored)
        }
        return Arm(outcome: .read, anchorStatus: anchoredAvailable ? .available : .unavailable, glyphs: glyphs)
    }

    private static func validRanks(_ ranks: [PersonalInkLearnedComparison.Rank]) -> Bool {
        guard ranks.count <= 3, Set(ranks.map(\.label)).count == ranks.count,
              ranks.allSatisfy({ $0.label.count == 1 && $0.score.isFinite }) else { return false }
        return zip(ranks, ranks.dropFirst()).allSatisfy {
            $0.0.score > $0.1.score || ($0.0.score == $0.1.score && $0.0.label < $0.1.label)
        }
    }

    private static func checkProfile(_ model: PersonalInkLearnedComparison,
                                     _ provider: () -> PersonalInkProfile, _ expected: Data) throws {
        let current = provider()
        guard current.isEnabled else { throw PersonalInkLearnedComparison.Failure.disabled }
        guard current == model.profile, try canonical(current) == expected,
              try canonical(model.profile) == expected else {
            throw PersonalInkLearnedComparison.Failure.staleProfile
        }
    }

    func canonicalData() throws -> Data { try Self.canonical(self) }
    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private enum CodingKeys: String, CodingKey {
        case version, artifactKind, nativeLiveResult, accuracyMeasured, glyphOwnershipVerified
        case trainingEligible, predictionChronologyVerified, rankingScope
        case legacyFreeze, legacyCanonicalData, legacyCanonicalSHA256, automatic, supplied
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(artifactKind, forKey: .artifactKind)
        try container.encode(nativeLiveResult, forKey: .nativeLiveResult)
        try container.encode(accuracyMeasured, forKey: .accuracyMeasured)
        try container.encode(glyphOwnershipVerified, forKey: .glyphOwnershipVerified)
        try container.encode(trainingEligible, forKey: .trainingEligible)
        try container.encode(predictionChronologyVerified, forKey: .predictionChronologyVerified)
        try container.encode(rankingScope, forKey: .rankingScope)
        try container.encode(legacyFreeze, forKey: .legacyFreeze)
        try container.encode(legacyCanonicalData, forKey: .legacyCanonicalData)
        try container.encode(legacyCanonicalSHA256, forKey: .legacyCanonicalSHA256)
        try container.encode(automatic, forKey: .automatic)
        try container.encode(supplied, forKey: .supplied)
    }
}

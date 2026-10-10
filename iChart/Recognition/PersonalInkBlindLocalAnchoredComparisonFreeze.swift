import Foundation
import CryptoKit

/// Separate offline comparison, never native recognition or an acceptance API.
/// Supplied partitions are diagnostic routing, not certified glyph ownership.
/// No intended text, expected count, truth annotation or lower-rank rescue input.
struct PersonalInkBlindLocalAnchoredComparisonFreeze: Encodable, Equatable {
    static let currentVersion = "blind-ink-local-anchored-comparison-freeze-v1"
    enum Failure: Error, Equatable {
        case invalidCommitment(field: String), invalidSuppliedPartition, invalidReading, sourceChanged
    }
    struct Arm: Encodable, Equatable {
        enum Outcome: String, Encodable, Equatable { case read; case invalidInk = "invalid-ink" }
        let outcome: Outcome
        let reading: PersonalInkLocalAnchoredComparison.Reading?
        static let invalidInk = Arm(outcome: .invalidInk, reading: nil)
        private enum CodingKeys: String, CodingKey { case outcome, reading }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(outcome, forKey: .outcome)
            try c.encode(reading, forKey: .reading)
        }
    }

    let version = Self.currentVersion
    let artifactKind = "engineering-only-local-anchored-comparison-v1"
    let nativeLiveResult = false
    let ownershipVerified = false
    let accuracyMeasured = false
    let trainingEligible = false
    let predictionChronologyVerified = false
    let automaticPolicy = PersonalInkLearnedComparison.Grouping.losslessSourceV2.rawValue
    let rankingScope = "full-shared-linear-anchored-local-anchored-vocabulary"
    let sourceCanonicalData: Data
    let sourcePacketSHA256: String
    let sourceStrokeCount: Int
    let encoderIdentity: String
    let vocabulary: [String]
    let modelIdentity: PersonalInkLocalAnchoredComparison.ModelIdentity
    let profileSHA256: String
    let runtimeSHA256: String
    let codeSHA256: String
    let ownershipReceiptSHA256: String?
    let support: PersonalInkLocalAnchoredComparison.SupportProjection
    let supportCanonicalData: Data
    let supportCanonicalSHA256: String
    let automatic: Arm
    let supplied: Arm?

    static func freeze(sourcePacketData: Data, suppliedOriginalIndexGroups: [[Int]]? = nil,
                       ownershipReceiptSHA256: String?, runtimeSHA256: String, codeSHA256: String,
                       model: PersonalInkLocalAnchoredComparison,
                       currentProfile: () -> PersonalInkProfile) throws -> Self {
        try validateDigest(runtimeSHA256, field: "runtimeSHA256")
        try validateDigest(codeSHA256, field: "codeSHA256")
        if let ownershipReceiptSHA256 { try validateDigest(ownershipReceiptSHA256, field: "ownershipReceiptSHA256") }
        let profile = currentProfile()
        let profileData = try canonical(profile)
        try checkProfile(model, currentProfile, profileData)
        let packet = try PersonalInkBlindPredictionFreeze.decodeBoundedPacket(sourcePacketData)
        let source = packet.preparedStrokes()
        // Validate both arms' routing BEFORE either can query the encoder.
        if let groups = suppliedOriginalIndexGroups, !isCompletePartition(groups, count: source.count) {
            throw Failure.invalidSuppliedPartition
        }
        try validateSupport(model.support, model: model)
        let supportData = try canonical(model.support)
        let sourceDigest = digest(sourcePacketData)
        let representable: Bool
        do { _ = try ChordInkPreparedFeatureGeometry.prepare(strokes: source); representable = true }
        catch is ChordInkFeatureEncodingError { representable = false }
        try checkProfile(model, currentProfile, profileData)

        func read(_ groups: [[Int]]) throws -> Arm {
            try checkProfile(model, currentProfile, profileData)
            guard representable, (1...16).contains(groups.count), isCompletePartition(groups, count: source.count) else {
                return .invalidInk
            }
            let reading: PersonalInkLocalAnchoredComparison.Reading
            do {
                reading = try model.readSuppliedOriginalGroups(source, originalIndexGroups: groups,
                    currentProfile: currentProfile)
            } catch PersonalInkLearnedComparison.Failure.invalidInk {
                try checkProfile(model, currentProfile, profileData)
                return .invalidInk
            } catch is ChordInkFeatureEncodingError {
                try checkProfile(model, currentProfile, profileData)
                return .invalidInk
            }
            try validateReading(reading, groups: groups.map { $0.sorted() }, sourceStrokeCount: source.count,
                sourceSHA256: sourceDigest, model: model)
            try checkProfile(model, currentProfile, profileData)
            return Arm(outcome: .read, reading: reading)
        }
        // This exact construction is the existing losslessSourceV2 policy:
        // original point timing, recomputed grouping bounds, no creation offset.
        let groups = representable ? StrokeClusterer(wrapperPolicy: .preserveOriginalInk)
            .indexedClusters(source.map { InkStroke(points: $0.points) }).map { $0.originalIndexes.sorted() } : []
        let automatic = try read(groups)
        let supplied = try suppliedOriginalIndexGroups.map(read)
        try checkProfile(model, currentProfile, profileData)
        guard try ChordInkCanonicalTrajectoryPacket(strokes: source).canonicalData() == sourcePacketData,
              try canonical(model.support) == supportData else { throw Failure.sourceChanged }
        return Self(sourceCanonicalData: sourcePacketData, sourcePacketSHA256: sourceDigest,
            sourceStrokeCount: source.count, encoderIdentity: model.encoderIdentity, vocabulary: model.vocabulary,
            modelIdentity: model.modelIdentity,
            profileSHA256: digest(profileData), runtimeSHA256: runtimeSHA256, codeSHA256: codeSHA256,
            ownershipReceiptSHA256: ownershipReceiptSHA256, support: model.support,
            supportCanonicalData: supportData, supportCanonicalSHA256: digest(supportData),
            automatic: automatic, supplied: supplied)
    }

    /// Full-domain validation, independently usable by synthetic contract tests.
    static func validateReading(_ reading: PersonalInkLocalAnchoredComparison.Reading,
                                groups: [[Int]], sourceStrokeCount: Int, sourceSHA256: String,
                                model: PersonalInkLocalAnchoredComparison) throws {
        guard (1...16).contains(groups.count), isCompletePartition(groups, count: sourceStrokeCount),
              groups.allSatisfy({ $0 == $0.sorted() }), reading.sourceStrokeCount == sourceStrokeCount,
              reading.version == PersonalInkLocalAnchoredComparison.version,
              reading.modelIdentity == model.modelIdentity,
              try canonical(reading.modelIdentity) == canonical(model.modelIdentity),
              reading.sourceInkSHA256 == sourceSHA256, reading.encoderIdentity == model.encoderIdentity,
              reading.profileRevision == model.profile.revision, reading.profileGeneration == model.profile.generation,
              reading.support == model.support, try canonical(reading.support) == canonical(model.support),
              reading.controlLearnerVersion == PersonalInkAnchoredResidualHead.version,
              reading.localLearnerVersion == PersonalInkLocalAnchoredResidualHead.version,
              reading.glyphs.map(\.originalStrokeIndexes) == groups else { throw Failure.invalidReading }
        for glyph in reading.glyphs {
            guard validEmbedding(glyph.embedding), validBase(glyph.baseScores, count: model.vocabulary.count),
                  glyph.embeddingSHA256 == vectorDigest(glyph.embedding),
                  glyph.baseScoresSHA256 == vectorDigest(glyph.baseScores),
                  validRanks(glyph.sharedRanks, vocabulary: model.vocabulary),
                  validRanks(glyph.controlRanks, vocabulary: model.vocabulary),
                  validRanks(glyph.localRanks, vocabulary: model.vocabulary) else { throw Failure.invalidReading }
            let base = Dictionary(uniqueKeysWithValues: zip(model.vocabulary, glyph.baseScores))
            guard glyph.sharedRanks.allSatisfy({ base[$0.label] == $0.score }) else { throw Failure.invalidReading }
        }
        guard reading.sharedChord == PersonalInkLearnedComparison.compose(reading.glyphs.map { $0.sharedRanks.first?.label }),
              reading.controlChord == PersonalInkLearnedComparison.compose(reading.glyphs.map { $0.controlRanks.first?.label }),
              reading.localChord == PersonalInkLearnedComparison.compose(reading.glyphs.map { $0.localRanks.first?.label }) else {
            throw Failure.invalidReading
        }
    }

    private static func validateSupport(_ support: PersonalInkLocalAnchoredComparison.SupportProjection,
                                        model: PersonalInkLocalAnchoredComparison) throws {
        let profile = model.profile, vocabulary = model.vocabulary
        let examples = profile.examples.filter { $0.kind == .glyph }.sorted { $0.id.uuidString < $1.id.uuidString }
        let counts = Dictionary(grouping: examples, by: \.label).mapValues(\.count)
        guard support.profileSHA256 == (try digest(canonical(profile))),
              validModelIdentity(model.modelIdentity),
              support.sha256 == (try support.recomputedSHA256()),
              support.encoderIdentity == model.encoderIdentity,
              support.vocabularySHA256 == (try digest(canonical(vocabulary))),
              support.canonicalAnchorBankSHA256 == model.modelIdentity.canonicalAnchorBankSHA256,
              model.modelIdentity.encoderIdentity == model.encoderIdentity,
              model.modelIdentity.comparisonVersion == PersonalInkLocalAnchoredComparison.version,
              model.modelIdentity.profileSHA256 == support.profileSHA256,
              model.modelIdentity.completeVocabularySHA256 == support.vocabularySHA256,
              model.modelIdentity.supportSHA256 == support.sha256,
              support.supportExampleCount == examples.count, support.distinctLabelCount == counts.count,
              support.labelCounts == counts, support.ignoredWholeChordCount == profile.examples.count - examples.count,
              support.trackedExampleIDs == examples.filter({ $0.learningProvenance != nil }).map(\.id),
              support.untrackedExampleIDs == examples.filter({ $0.learningProvenance == nil }).map(\.id),
              support.lessons.map(\.exampleID) == examples.map(\.id) else { throw Failure.invalidReading }
        try validateDigest(support.sha256, field: "support.sha256")
        for (lesson, example) in zip(support.lessons, examples) {
            guard lesson.label == example.label, lesson.source == example.source, vocabulary.contains(lesson.label),
                  lesson.hasLearningProvenance == (example.learningProvenance != nil),
                  lesson.hasVerifiedSymbolOrigin == (example.verifiedSymbolOrigin != nil),
                  lesson.storedInkSHA256 == (try digest(ChordInkCanonicalTrajectoryPacket(strokes: example.recognitionInput).canonicalData())),
                  lesson.originalInputSHA256 == example.learningProvenance?.originalInputSHA256,
                  lesson.intakeSessionID == example.learningProvenance?.context.sessionID,
                  validEmbedding(lesson.embedding), validBase(lesson.baseScores, count: vocabulary.count),
                  lesson.embeddingSHA256 == vectorDigest(lesson.embedding),
                  lesson.baseScoresSHA256 == vectorDigest(lesson.baseScores) else { throw Failure.invalidReading }
        }
    }
    private static func validModelIdentity(_ identity: PersonalInkLocalAnchoredComparison.ModelIdentity) -> Bool {
        guard identity.controlLearnerVersion == PersonalInkAnchoredResidualHead.version,
              identity.localLearnerVersion == PersonalInkLocalAnchoredResidualHead.version,
              identity.localKernelWidthBitPattern == String(format: "%016llx", PersonalInkLocalAnchoredResidualHead.kernelWidth.bitPattern),
              identity.regularizationBitPattern == String(format: "%016llx", PersonalInkLocalAnchoredResidualHead.regularization.bitPattern) else {
            return false
        }
        if identity.runtimeKind == PersonalInkLocalAnchoredComparison.protocolRuntimeKind {
            return identity.pinnedAnchorArtifactSHA256 == nil && identity.pinnedManifestArtifactSHA256 == nil
        }
        #if DEBUG && canImport(CoreML)
        if identity.runtimeKind == PersonalInkLocalAnchoredComparison.pinnedRuntimeKind {
            return identity.pinnedAnchorArtifactSHA256 == PersonalInkVisualEncoder.anchorSHA256
                && identity.pinnedManifestArtifactSHA256 == PersonalInkVisualEncoder.anchoredManifestSHA256
        }
        #endif
        return false
    }
    private static func validEmbedding(_ values: [Double]) -> Bool {
        values.count == 128 && values.allSatisfy(\.isFinite)
            && abs(values.reduce(0) { $0 + $1 * $1 } - 1) <= 1e-3
    }
    private static func validBase(_ values: [Double], count: Int) -> Bool {
        values.count == count && values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 })
            && abs(values.reduce(0, +) - 1) <= 1e-8
    }
    private static func validRanks(_ ranks: [PersonalInkLocalAnchoredComparison.Rank], vocabulary: [String]) -> Bool {
        guard ranks.count == vocabulary.count, Set(ranks.map(\.label)) == Set(vocabulary),
              ranks.allSatisfy({ $0.score.isFinite }) else { return false }
        return zip(ranks, ranks.dropFirst()).allSatisfy {
            $0.0.score > $0.1.score || ($0.0.score == $0.1.score && $0.0.label < $0.1.label)
        }
    }
    private static func isCompletePartition(_ groups: [[Int]], count: Int) -> Bool {
        let indexes = groups.flatMap { $0 }
        return count >= 0 && groups.allSatisfy({ !$0.isEmpty }) && indexes.count == count
            && indexes.allSatisfy({ (0..<count).contains($0) }) && Set(indexes).count == count
    }
    private static func checkProfile(_ model: PersonalInkLocalAnchoredComparison,
                                     _ provider: () -> PersonalInkProfile, _ expected: Data) throws {
        let current = provider()
        guard current.isEnabled else { throw PersonalInkLearnedComparison.Failure.disabled }
        guard current == model.profile, try canonical(current) == expected,
              try canonical(model.profile) == expected else { throw PersonalInkLearnedComparison.Failure.staleProfile }
    }
    private static func validateDigest(_ value: String, field: String) throws {
        guard value.utf8.count == 64, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw Failure.invalidCommitment(field: field)
        }
    }
    private static func vectorDigest(_ values: [Double]) -> String {
        var data = Data()
        for value in values {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return digest(data)
    }
    func canonicalData() throws -> Data { try Self.canonical(self) }
    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private enum CodingKeys: String, CodingKey {
        case version, artifactKind, nativeLiveResult, ownershipVerified, accuracyMeasured, trainingEligible
        case predictionChronologyVerified, automaticPolicy, rankingScope, sourceCanonicalData, sourcePacketSHA256
        case sourceStrokeCount, encoderIdentity, vocabulary, modelIdentity, profileSHA256, runtimeSHA256, codeSHA256
        case ownershipReceiptSHA256, support, supportCanonicalData, supportCanonicalSHA256, automatic, supplied
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version); try c.encode(artifactKind, forKey: .artifactKind)
        try c.encode(nativeLiveResult, forKey: .nativeLiveResult); try c.encode(ownershipVerified, forKey: .ownershipVerified)
        try c.encode(accuracyMeasured, forKey: .accuracyMeasured); try c.encode(trainingEligible, forKey: .trainingEligible)
        try c.encode(predictionChronologyVerified, forKey: .predictionChronologyVerified)
        try c.encode(automaticPolicy, forKey: .automaticPolicy); try c.encode(rankingScope, forKey: .rankingScope)
        try c.encode(sourceCanonicalData, forKey: .sourceCanonicalData); try c.encode(sourcePacketSHA256, forKey: .sourcePacketSHA256)
        try c.encode(sourceStrokeCount, forKey: .sourceStrokeCount); try c.encode(encoderIdentity, forKey: .encoderIdentity)
        try c.encode(vocabulary, forKey: .vocabulary); try c.encode(profileSHA256, forKey: .profileSHA256)
        try c.encode(modelIdentity, forKey: .modelIdentity)
        try c.encode(runtimeSHA256, forKey: .runtimeSHA256); try c.encode(codeSHA256, forKey: .codeSHA256)
        try c.encode(ownershipReceiptSHA256, forKey: .ownershipReceiptSHA256); try c.encode(support, forKey: .support)
        try c.encode(supportCanonicalData, forKey: .supportCanonicalData)
        try c.encode(supportCanonicalSHA256, forKey: .supportCanonicalSHA256)
        try c.encode(automatic, forKey: .automatic); try c.encode(supplied, forKey: .supplied)
    }
}

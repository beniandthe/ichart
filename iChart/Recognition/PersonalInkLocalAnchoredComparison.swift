import CryptoKit
import Foundation

/// Offline comparison between the existing linear anchored residual and the
/// fixed local-RBF anchored residual. This type deliberately has no automatic
/// grouping, rendering, profile-writing, acceptance, or live-reader API.
struct PersonalInkLocalAnchoredComparison {
    static let version = "personal-local-anchored-comparison-v1"
    static let pinnedRuntimeKind = "pinned-personal-visual-encoder"
    static let protocolRuntimeKind = "protocol-supplied-comparison-encoder"

    typealias Rank = PersonalInkLearnedComparison.Rank
    typealias Failure = PersonalInkLearnedComparison.Failure

    struct SupportLesson: Codable, Equatable {
        let exampleID: UUID
        let label: String
        let source: PersonalInkExampleSource
        let storedInkSHA256: String
        let originalInputSHA256: String?
        let intakeSessionID: UUID?
        let embedding: [Double]
        let baseScores: [Double]
        let embeddingSHA256: String
        let baseScoresSHA256: String
        let hasLearningProvenance: Bool
        let hasVerifiedSymbolOrigin: Bool
    }

    struct SupportProjection: Codable, Equatable {
        let profileSHA256: String
        let encoderIdentity: String
        let vocabularySHA256: String
        let canonicalAnchorBankSHA256: String
        let lessons: [SupportLesson]
        let supportExampleCount: Int
        let distinctLabelCount: Int
        let labelCounts: [String: Int]
        let ignoredWholeChordCount: Int
        let trackedExampleIDs: [UUID]
        let untrackedExampleIDs: [UUID]
        let assuranceNote: String
        let sha256: String

        func recomputedSHA256() throws -> String {
            try PersonalInkLocalAnchoredComparison.digestJSON(Payload(
                profileSHA256: profileSHA256,
                encoderIdentity: encoderIdentity,
                vocabularySHA256: vocabularySHA256,
                canonicalAnchorBankSHA256: canonicalAnchorBankSHA256,
                lessons: lessons,
                supportExampleCount: supportExampleCount,
                distinctLabelCount: distinctLabelCount,
                labelCounts: labelCounts,
                ignoredWholeChordCount: ignoredWholeChordCount,
                trackedExampleIDs: trackedExampleIDs,
                untrackedExampleIDs: untrackedExampleIDs,
                assuranceNote: assuranceNote
            ))
        }

        fileprivate struct Payload: Codable {
            let profileSHA256: String
            let encoderIdentity: String
            let vocabularySHA256: String
            let canonicalAnchorBankSHA256: String
            let lessons: [SupportLesson]
            let supportExampleCount: Int
            let distinctLabelCount: Int
            let labelCounts: [String: Int]
            let ignoredWholeChordCount: Int
            let trackedExampleIDs: [UUID]
            let untrackedExampleIDs: [UUID]
            let assuranceNote: String
        }
    }

    struct ModelIdentity: Codable, Equatable {
        let comparisonVersion: String
        let runtimeKind: String
        let encoderIdentity: String
        let profileSHA256: String
        let publicVocabularySHA256: String
        let completeVocabularySHA256: String
        let canonicalAnchorBankSHA256: String
        let pinnedAnchorArtifactSHA256: String?
        let pinnedManifestArtifactSHA256: String?
        let supportSHA256: String
        let controlLearnerVersion: String
        let localLearnerVersion: String
        let localKernelWidthBitPattern: String
        let regularizationBitPattern: String
    }

    struct Glyph: Codable, Equatable {
        let originalStrokeIndexes: [Int]
        let embedding: [Double]
        let baseScores: [Double]
        let embeddingSHA256: String
        let baseScoresSHA256: String
        let sharedRanks: [Rank]
        let controlRanks: [Rank]
        let localRanks: [Rank]

        /// Full ranks above remain part of the frozen comparison receipt. These
        /// computed projections are the only reader-facing rank collections.
        var sharedChordDomainRanks: [Rank] {
            ChordRecognitionDomain.projectTopRanked(sharedRanks) { $0.label }
        }

        var controlChordDomainRanks: [Rank] {
            ChordRecognitionDomain.projectTopRanked(controlRanks) { $0.label }
        }

        var localChordDomainRanks: [Rank] {
            ChordRecognitionDomain.projectTopRanked(localRanks) { $0.label }
        }
    }

    /// Identity is conditional on the caller-supplied original-stroke
    /// partition. Nothing here establishes that the groups are true glyphs.
    struct Reading: Codable, Equatable {
        let version: String
        let modelIdentity: ModelIdentity
        let encoderIdentity: String
        let profileRevision: UUID
        let profileGeneration: UUID
        let sourceStrokeCount: Int
        let sourceInkSHA256: String
        let support: SupportProjection
        let controlLearnerVersion: String
        let localLearnerVersion: String
        let sharedChord: String?
        let controlChord: String?
        let localChord: String?
        let glyphs: [Glyph]
        let assuranceNote: String
    }

    let profile: PersonalInkProfile
    let encoderIdentity: String
    let vocabulary: [String]
    let support: SupportProjection
    let modelIdentity: ModelIdentity

    private let encoder: PersonalInkVisualEncoding
    private let publicVocabulary: [String]
    private let anchorBank: PersonalInkAnchorBank
    private let context: PersonalInkResidualHead.Context
    private let control: PersonalInkAnchoredResidualHead
    private let local: PersonalInkLocalAnchoredResidualHead

    /// Test/research seam. Its model identity explicitly states that the
    /// encoder is protocol-supplied; callers must not present that as verified
    /// package/manifest lineage.
    init(profile: PersonalInkProfile, encoder: PersonalInkVisualEncoding) throws {
        try self.init(profile: profile, encoder: encoder, runtimeKind: Self.protocolRuntimeKind,
                      pinnedAnchorArtifactSHA256: nil, pinnedManifestArtifactSHA256: nil)
    }

#if DEBUG && canImport(CoreML)
    /// The offline real-runtime path. `PersonalInkVisualEncoder` has already
    /// verified its pinned manifest, Core ML package, metadata, vocabulary and
    /// public-anchor artifact before this initializer can be called.
    init(profile: PersonalInkProfile, encoder: PersonalInkVisualEncoder) throws {
        try self.init(profile: profile, encoder: encoder, runtimeKind: Self.pinnedRuntimeKind,
                      pinnedAnchorArtifactSHA256: PersonalInkVisualEncoder.anchorSHA256,
                      pinnedManifestArtifactSHA256: PersonalInkVisualEncoder.anchoredManifestSHA256)
    }
#endif

    private init(profile: PersonalInkProfile, encoder: PersonalInkVisualEncoding,
                 runtimeKind: String, pinnedAnchorArtifactSHA256: String?,
                 pinnedManifestArtifactSHA256: String?) throws {
        guard profile.isEnabled else { throw Failure.disabled }
        try Self.validate(profile: profile)
        guard !encoder.identity.isEmpty,
              (2...512).contains(encoder.vocabulary.count),
              Set(encoder.vocabulary).count == encoder.vocabulary.count,
              encoder.vocabulary.allSatisfy({ $0.count == 1 }),
              let bank = encoder.anchorBank,
              bank.vocabulary == encoder.vocabulary,
              bank.features.count == encoder.vocabulary.count,
              bank.features.allSatisfy(Self.validUnitFeature) else {
            throw Failure.invalidEncoder
        }

        let frozenEncoderIdentity = encoder.identity
        let frozenPublicVocabulary = encoder.vocabulary
        let frozenContext = PersonalInkResidualHead.Context(
            isEnabled: true,
            profileRevision: profile.revision,
            encoderIdentity: frozenEncoderIdentity
        )

        let examples = profile.examples.sorted { $0.id.uuidString < $1.id.uuidString }
        let glyphExamples = examples.filter { $0.kind == .glyph }
        let wholeChordExamples = examples.filter { $0.kind == .chord }
        let novel = Set(glyphExamples.map(\.label)).subtracting(frozenPublicVocabulary).sorted()
        let completeVocabulary = frozenPublicVocabulary + novel

        let profileSHA256: String
        let publicVocabularySHA256: String
        let completeVocabularySHA256: String
        let canonicalAnchorBankSHA256: String
        do {
            profileSHA256 = try Self.digestJSON(profile)
            publicVocabularySHA256 = try Self.digestJSON(frozenPublicVocabulary)
            completeVocabularySHA256 = try Self.digestJSON(completeVocabulary)
            canonicalAnchorBankSHA256 = try Self.digestJSON(bank)
        } catch { throw Failure.invalidProfile }

        // Freeze every exact glyph input commitment before the first model
        // call. Whole-chord examples are counted but never encoded or aligned.
        let glyphInputs: [(PersonalInkExample, String)]
        do {
            glyphInputs = try glyphExamples.map {
                ($0, Self.digest(try ChordInkCanonicalTrajectoryPacket(strokes: $0.recognitionInput).canonicalData()))
            }
        } catch { throw Failure.invalidProfile }

        try Self.requireEncoderState(encoder, identity: frozenEncoderIdentity,
                                     vocabulary: frozenPublicVocabulary, bank: bank)
        var supportLessons: [SupportLesson] = []
        var headLessons: [PersonalInkResidualHead.Lesson] = []
        for (example, sourceSHA256) in glyphInputs {
            try Self.requireEncoderState(encoder, identity: frozenEncoderIdentity,
                                         vocabulary: frozenPublicVocabulary, bank: bank)
            let encoded = try Self.checked(encoder.encode(example.recognitionInput),
                                           vocabularyCount: frozenPublicVocabulary.count)
            try Self.requireEncoderState(encoder, identity: frozenEncoderIdentity,
                                         vocabulary: frozenPublicVocabulary, bank: bank)
            let base = try Self.baseScores(encoded, padding: novel.count)
            supportLessons.append(.init(
                exampleID: example.id,
                label: example.label,
                source: example.source,
                storedInkSHA256: sourceSHA256,
                originalInputSHA256: example.learningProvenance?.originalInputSHA256,
                intakeSessionID: example.learningProvenance?.context.sessionID,
                embedding: encoded.embedding,
                baseScores: base,
                embeddingSHA256: Self.digestVector(encoded.embedding),
                baseScoresSHA256: Self.digestVector(base),
                hasLearningProvenance: example.learningProvenance != nil,
                hasVerifiedSymbolOrigin: example.verifiedSymbolOrigin != nil
            ))
            headLessons.append(.init(label: example.label, features: encoded.embedding,
                                     baseScores: base))
        }
        try Self.requireEncoderState(encoder, identity: frozenEncoderIdentity,
                                     vocabulary: frozenPublicVocabulary, bank: bank)

        let labelCounts = Dictionary(grouping: glyphExamples, by: \.label).mapValues(\.count)
        let tracked = glyphExamples.filter { $0.learningProvenance != nil }.map(\.id)
        let untracked = glyphExamples.filter { $0.learningProvenance == nil }.map(\.id)
        let assurance = untracked.isEmpty
            ? "All support lessons carry validated local intake metadata; it does not verify writer identity, consent, freshness, or independence."
            : "Some support lessons have no local intake metadata. Their acquisition, consent, writer, session, freshness, and independence remain untracked."
        let supportPayload = SupportProjection.Payload(
            profileSHA256: profileSHA256,
            encoderIdentity: frozenEncoderIdentity,
            vocabularySHA256: completeVocabularySHA256,
            canonicalAnchorBankSHA256: canonicalAnchorBankSHA256,
            lessons: supportLessons,
            supportExampleCount: supportLessons.count,
            distinctLabelCount: labelCounts.count,
            labelCounts: labelCounts,
            ignoredWholeChordCount: wholeChordExamples.count,
            trackedExampleIDs: tracked,
            untrackedExampleIDs: untracked,
            assuranceNote: assurance
        )
        let supportSHA256: String
        do { supportSHA256 = try Self.digestJSON(supportPayload) }
        catch { throw Failure.invalidProfile }
        let frozenSupport = SupportProjection(
            profileSHA256: supportPayload.profileSHA256,
            encoderIdentity: supportPayload.encoderIdentity,
            vocabularySHA256: supportPayload.vocabularySHA256,
            canonicalAnchorBankSHA256: supportPayload.canonicalAnchorBankSHA256,
            lessons: supportPayload.lessons,
            supportExampleCount: supportPayload.supportExampleCount,
            distinctLabelCount: supportPayload.distinctLabelCount,
            labelCounts: supportPayload.labelCounts,
            ignoredWholeChordCount: supportPayload.ignoredWholeChordCount,
            trackedExampleIDs: supportPayload.trackedExampleIDs,
            untrackedExampleIDs: supportPayload.untrackedExampleIDs,
            assuranceNote: supportPayload.assuranceNote,
            sha256: supportSHA256
        )
        guard try frozenSupport.recomputedSHA256() == frozenSupport.sha256 else {
            throw Failure.invalidProfile
        }

        let frozenControl = try PersonalInkAnchoredResidualHead(
            context: frozenContext, vocabulary: completeVocabulary, featureCount: 128,
            lessons: headLessons, bank: bank
        )
        let frozenLocal = try PersonalInkLocalAnchoredResidualHead(
            context: frozenContext, vocabulary: completeVocabulary, featureCount: 128,
            lessons: headLessons, bank: bank
        )
        let frozenModelIdentity = ModelIdentity(
            comparisonVersion: Self.version,
            runtimeKind: runtimeKind,
            encoderIdentity: frozenEncoderIdentity,
            profileSHA256: profileSHA256,
            publicVocabularySHA256: publicVocabularySHA256,
            completeVocabularySHA256: completeVocabularySHA256,
            canonicalAnchorBankSHA256: canonicalAnchorBankSHA256,
            pinnedAnchorArtifactSHA256: pinnedAnchorArtifactSHA256,
            pinnedManifestArtifactSHA256: pinnedManifestArtifactSHA256,
            supportSHA256: supportSHA256,
            controlLearnerVersion: PersonalInkAnchoredResidualHead.version,
            localLearnerVersion: PersonalInkLocalAnchoredResidualHead.version,
            localKernelWidthBitPattern: Self.hexBits(PersonalInkLocalAnchoredResidualHead.kernelWidth),
            regularizationBitPattern: Self.hexBits(PersonalInkLocalAnchoredResidualHead.regularization)
        )

        self.profile = profile
        self.encoder = encoder
        encoderIdentity = frozenEncoderIdentity
        publicVocabulary = frozenPublicVocabulary
        vocabulary = completeVocabulary
        anchorBank = bank
        context = frozenContext
        support = frozenSupport
        control = frozenControl
        local = frozenLocal
        modelIdentity = frozenModelIdentity
    }

    /// Reads only the exact original partition supplied by the caller. All
    /// source and group geometry is validated before any query-group encoding.
    func readSuppliedOriginalGroups(
        _ strokes: [InkStroke],
        originalIndexGroups: [[Int]],
        currentProfile: () -> PersonalInkProfile
    ) throws -> Reading {
        try requireCurrentProfile(currentProfile)
        try requireEncoderState()
        do { _ = try ChordInkPreparedFeatureGeometry.prepare(strokes: strokes) }
        catch is ChordInkFeatureEncodingError { throw Failure.invalidInk }
        guard (1...16).contains(originalIndexGroups.count),
              originalIndexGroups.allSatisfy({ !$0.isEmpty }) else { throw Failure.invalidInk }
        let indexes = originalIndexGroups.flatMap { $0 }
        guard indexes.count == strokes.count,
              indexes.allSatisfy({ strokes.indices.contains($0) }),
              Set(indexes).count == strokes.count else { throw Failure.invalidInk }

        let orderedGroups = originalIndexGroups.map { $0.sorted() }
        let inputs = orderedGroups.map { group in group.map { strokes[$0] } }
        do {
            for input in inputs { _ = try ChordInkPreparedFeatureGeometry.prepare(strokes: input) }
        } catch is ChordInkFeatureEncodingError { throw Failure.invalidInk }
        let sourceSHA256: String
        do {
            sourceSHA256 = Self.digest(try ChordInkCanonicalTrajectoryPacket(strokes: strokes).canonicalData())
        } catch { throw Failure.invalidInk }

        try requireCurrentProfile(currentProfile)
        try requireEncoderState()
        var glyphs: [Glyph] = []
        for (group, input) in zip(orderedGroups, inputs) {
            try requireCurrentProfile(currentProfile)
            try requireEncoderState()
            let encoded = try Self.checked(encoder.encode(input), vocabularyCount: publicVocabulary.count)
            try requireEncoderState()
            try requireCurrentProfile(currentProfile)
            let base = try Self.baseScores(encoded, padding: vocabulary.count - publicVocabulary.count)
            let sharedRanks = Self.rank(labels: vocabulary, scores: base)
            let controlRanks = try control.rankedCandidates(
                features: encoded.embedding, baseScores: base, currentContext: context
            ).map { Rank(label: $0.label, score: $0.score) }
            let localRanks = try local.rankedCandidates(
                features: encoded.embedding, baseScores: base, currentContext: context
            ).map { Rank(label: $0.label, score: $0.score) }
            guard Self.validRanks(sharedRanks, vocabulary: vocabulary),
                  Self.validRanks(controlRanks, vocabulary: vocabulary),
                  Self.validRanks(localRanks, vocabulary: vocabulary) else {
                throw Failure.invalidEncoder
            }
            glyphs.append(.init(
                originalStrokeIndexes: group,
                embedding: encoded.embedding,
                baseScores: base,
                embeddingSHA256: Self.digestVector(encoded.embedding),
                baseScoresSHA256: Self.digestVector(base),
                sharedRanks: sharedRanks,
                controlRanks: controlRanks,
                localRanks: localRanks
            ))
        }
        try requireCurrentProfile(currentProfile)
        try requireEncoderState()
        guard try support.recomputedSHA256() == support.sha256 else { throw Failure.invalidProfile }
        return .init(
            version: Self.version,
            modelIdentity: modelIdentity,
            encoderIdentity: encoderIdentity,
            profileRevision: profile.revision,
            profileGeneration: profile.generation,
            sourceStrokeCount: strokes.count,
            sourceInkSHA256: sourceSHA256,
            support: support,
            controlLearnerVersion: PersonalInkAnchoredResidualHead.version,
            localLearnerVersion: PersonalInkLocalAnchoredResidualHead.version,
            sharedChord: PersonalInkLearnedComparison.compose(glyphs.map { $0.sharedChordDomainRanks.first?.label }),
            controlChord: PersonalInkLearnedComparison.compose(glyphs.map { $0.controlChordDomainRanks.first?.label }),
            localChord: PersonalInkLearnedComparison.compose(glyphs.map { $0.localChordDomainRanks.first?.label }),
            glyphs: glyphs,
            assuranceNote: "Comparison-only conditional identity. Supplied groups are not ownership evidence; ranks are uncalibrated and cannot authorize rendering."
        )
    }

    private func requireCurrentProfile(_ provider: () -> PersonalInkProfile) throws {
        let current = provider()
        guard current.isEnabled else { throw Failure.disabled }
        guard current == profile else { throw Failure.staleProfile }
    }

    private func requireEncoderState() throws {
        try Self.requireEncoderState(encoder, identity: encoderIdentity,
                                     vocabulary: publicVocabulary, bank: anchorBank)
    }

    private static func requireEncoderState(_ encoder: PersonalInkVisualEncoding,
                                            identity: String, vocabulary: [String],
                                            bank: PersonalInkAnchorBank) throws {
        guard encoder.identity == identity, encoder.vocabulary == vocabulary,
              encoder.anchorBank == bank else { throw Failure.invalidEncoder }
    }

    private static func validate(profile: PersonalInkProfile) throws {
        guard profile.version == 1,
              profile.examples.count <= PersonalInkProfile.maximumExamples,
              Set(profile.examples.map(\.id)).count == profile.examples.count else {
            throw Failure.invalidProfile
        }
        let byID = Dictionary(uniqueKeysWithValues: profile.examples.map { ($0.id, $0) })
        for example in profile.examples {
            let validLabel = example.kind == .glyph
                ? PersonalInkProfile.glyphLabels.contains(example.label)
                : ChordRecognitionCompendium.match(example.label)?.displayText == example.label
            guard validLabel, example.hasValidRecognitionInput else {
                throw Failure.invalidProfile
            }
            if let provenance = example.learningProvenance {
                do { try provenance.validate(example: example) }
                catch { throw Failure.invalidProfile }
            }
            guard let origin = example.verifiedSymbolOrigin else { continue }
            guard example.kind == .glyph,
                  let parent = byID[origin.chordExampleID], parent.kind == .chord,
                  parent.label == origin.chordLabel,
                  !origin.originalStrokeIndexes.isEmpty,
                  origin.originalStrokeIndexes.allSatisfy(parent.recognitionInput.indices.contains),
                  Set(origin.originalStrokeIndexes).count == origin.originalStrokeIndexes.count,
                  Self.matchesVerifiedOrigin(example: example, parent: parent,
                    indexes: origin.originalStrokeIndexes.sorted()) else { throw Failure.invalidProfile }
        }
    }

    private static func matchesVerifiedOrigin(example: PersonalInkExample,
                                              parent: PersonalInkExample,
                                              indexes: [Int]) -> Bool {
        let selected = indexes.map { parent.recognitionInput[$0] }
        if let recognitionStrokes = example.recognitionStrokes {
            return recognitionStrokes == selected
        }
        return PersonalInkShape(strokes: selected)?.normalizedStrokes == example.strokes
    }

    private static func checked(_ value: PersonalInkVisualFeatures,
                                vocabularyCount: Int) throws -> PersonalInkVisualFeatures {
        guard value.embedding.count == 128,
              value.genericLogits.count == vocabularyCount,
              validUnitFeature(value.embedding),
              value.genericLogits.allSatisfy(\.isFinite) else { throw Failure.invalidEncoder }
        return value
    }

    private static func validUnitFeature(_ values: [Double]) -> Bool {
        values.count == 128 && values.allSatisfy(\.isFinite)
            && abs(values.reduce(0) { $0 + $1 * $1 } - 1) <= 1e-3
    }

    private static func baseScores(_ value: PersonalInkVisualFeatures, padding: Int) throws -> [Double] {
        try PersonalInkResidualHead.normalizedScores(logits: value.genericLogits)
            + Array(repeating: 0, count: padding)
    }

    private static func rank(labels: [String], scores: [Double]) -> [Rank] {
        zip(labels, scores).map { Rank(label: $0, score: $1) }.sorted {
            $0.score == $1.score ? $0.label < $1.label : $0.score > $1.score
        }
    }

    private static func validRanks(_ ranks: [Rank], vocabulary: [String]) -> Bool {
        ranks.count == vocabulary.count
            && Set(ranks.map(\.label)) == Set(vocabulary)
            && ranks.allSatisfy { $0.score.isFinite }
            && zip(ranks, ranks.dropFirst()).allSatisfy { previous, next in
                previous.score > next.score
                    || (previous.score == next.score && previous.label < next.label)
            }
    }

    private static func digestVector(_ values: [Double]) -> String {
        var data = Data(capacity: values.count * MemoryLayout<UInt64>.size)
        for value in values {
            var bits = value.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return digest(data)
    }

    private static func digestJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return digest(try encoder.encode(value))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hexBits(_ value: Double) -> String {
        String(format: "%016llx", value.bitPattern)
    }
}

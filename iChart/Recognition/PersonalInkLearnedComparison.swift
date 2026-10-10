import Foundation
import CryptoKit

/// The learned comparison deliberately has no render/acceptance API. Its ranks
/// remain hypotheses, including when a string happens to parse as a chord.
protocol PersonalInkVisualEncoding {
    var identity: String { get }
    var vocabulary: [String] { get }
    var anchorBank: PersonalInkAnchorBank? { get }
    func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures
}

extension PersonalInkVisualEncoding {
    var anchorBank: PersonalInkAnchorBank? { nil }
}

struct PersonalInkVisualFeatures {
    let embedding: [Double]
    let genericLogits: [Double]
}

struct PersonalInkLearnedComparison {
    /// Keep the installed experiment reproducible while evaluating a lossless
    /// path separately. Neither option changes live recognition or model weights.
    enum Grouping: String, Codable, CaseIterable {
        case legacyGeometryV1 = "geometry-semantic-wrappers-v1"
        case losslessSourceV2 = "geometry-lossless-source-groups-v2"
        case selectiveLosslessOwnershipV3 = "selective-lossless-ownership-v3"
    }
    struct Rank: Codable, Equatable { let label: String; let score: Double }
    struct Glyph: Codable, Equatable {
        let originalStrokeIndexes: [Int]
        /// Frozen research receipts retain the raw model ranks above. Reader
        /// surfaces must use these domain projections so an unrelated class
        /// can never be displayed or replaced by a lower-ranked chord glyph.
        let generic: [Rank]
        let personal: [Rank]

        var genericChordDomainRanks: [Rank] {
            ChordRecognitionDomain.projectTopRanked(generic) { $0.label }
        }

        var personalChordDomainRanks: [Rank] {
            ChordRecognitionDomain.projectTopRanked(personal) { $0.label }
        }
    }
    /// Identity conditional on a supplied structural partition. It carries no
    /// ownership resolution, confidence or complete-chord acceptance state.
    struct GroupIdentityReading: Codable, Equatable {
        let sourceStrokeCount: Int
        let encoderIdentity: String
        let glyphs: [Glyph]
        let anchoredGlyphRanks: [[Rank]]?

        /// `anchoredGlyphRanks` is the full forensic receipt. This projection is
        /// the only anchored ranking intended for reader presentation.
        var anchoredChordDomainRanks: [[Rank]]? {
            anchoredGlyphRanks?.map {
                ChordRecognitionDomain.projectTopRanked($0) { $0.label }
            }
        }
    }
    /// A separate, opt-in research receipt. Historical top-three predictions,
    /// personal residual ranks and scorecards are not substituted or changed.
    struct CanonicalProbabilityIdentityReading: Codable, Equatable {
        let sourceStrokeCount: Int
        let encoderIdentity: String
        let genericVocabulary: [String]
        let columns: [PersonalInkMLCanonicalProbabilityDecoder.Column]
        let hypotheses: PersonalInkMLCanonicalProbabilityDecoder.Result
    }
    struct Prediction: Codable, Equatable {
        let genericChord: String?
        let personalChord: String?
        let glyphs: [Glyph]
        // A closed-set ranking over explicitly taught whole chords. It is NOT
        // an accepted read: unfamiliar ink also has a highest-scoring label.
        let wholeChordRanks: [Rank]
        let knownInk: Bool
        // Optional preserves decoding of earlier comparison reports/artifacts.
        let anchored: AnchoredPrediction?
        // Absent in historical modes; a proposal is not a recognized symbol.
        var ownership: PersonalInkOwnershipAssessment? = nil

        /// Additive reader projection; the stored ranks and Codable report stay
        /// unchanged. Contextual fragments are presented only when every group
        /// participates in one complete grammar-valid chord.
        var chordDomainPresentationLabels: ChordDomainPresentationLabels {
            let genericRanks = glyphs.map(\.genericChordDomainRanks)
            let personalRanks = glyphs.map(\.personalChordDomainRanks)
            let anchoredLabels = anchored.map { anchored in
                PersonalInkLearnedComparison.presentationLabels(
                    from: anchored.chordDomainGlyphRanks,
                    expectedGroupCount: glyphs.count
                )
            }
            return ChordDomainPresentationLabels(
                generic: PersonalInkLearnedComparison.presentationLabels(
                    from: genericRanks,
                    expectedGroupCount: glyphs.count
                ),
                personal: PersonalInkLearnedComparison.presentationLabels(
                    from: personalRanks,
                    expectedGroupCount: glyphs.count
                ),
                anchored: anchoredLabels
            )
        }
    }
    struct ChordDomainPresentationLabels: Equatable {
        let generic: [String?]
        let personal: [String?]
        let anchored: [String?]?
    }
    struct AnchoredPrediction: Codable, Equatable {
        let learnerVersion: String
        let chord: String?
        let glyphRanks: [[Rank]]

        /// Additive and computed so earlier Codable reports remain unchanged.
        var chordDomainGlyphRanks: [[Rank]] {
            glyphRanks.map {
                ChordRecognitionDomain.projectTopRanked($0) { $0.label }
            }
        }
    }
    enum Failure: LocalizedError {
        case disabled, invalidProfile, invalidEncoder, invalidInk, staleProfile, incompleteRun, ambiguousRun, unsupportedHypothesisGrouping, invalidFrozenLineage
        var errorDescription: String? {
            switch self {
            case .disabled: return "Personal learning is off. No learned comparison was run."
            case .invalidProfile: return "The saved profile cannot be used for this comparison. It was not changed."
            case .invalidEncoder: return "The learned comparison model is missing or incompatible. Standard recognition is unchanged."
            case .invalidInk: return "This capture cannot be compared without its complete original ink."
            case .staleProfile: return "The profile changed or was disabled during comparison. Run it again."
            case .incompleteRun: return "Finish and label this saved chart test before comparing models."
            case .ambiguousRun: return "This saved test has duplicate record identifiers. Its original data was kept; comparison cannot align the answers safely."
            case .unsupportedHypothesisGrouping: return "Complete-symbol alternatives require the separate lossless source grouping route. Ownership remains unverified."
            case .invalidFrozenLineage: return "The saved intake summary does not match this test's frozen profile. Original evidence was kept; no comparison was run."
            }
        }
    }

    let profile: PersonalInkProfile
    let encoderIdentity: String
    let glyphLessonCount: Int
    let wholeChordLessonCount: Int
    let missingPersonalSymbols: [String]
    let grouping: Grouping
    private let encoder: PersonalInkVisualEncoding
    private let context: PersonalInkResidualHead.Context
    private let glyphHead: PersonalInkResidualHead
    private let anchoredHead: PersonalInkAnchoredResidualHead?
    private let wholeHead: PersonalInkBalancedRidge.Model?
    var anchoredAvailable: Bool { anchoredHead != nil }

    init(profile: PersonalInkProfile, encoder: PersonalInkVisualEncoding,
         grouping: Grouping = .legacyGeometryV1) throws {
        guard profile.isEnabled else { throw Failure.disabled }
        guard profile.version == 1, profile.examples.count <= PersonalInkProfile.maximumExamples,
              Set(profile.examples.map(\.id)).count == profile.examples.count,
              profile.examples.allSatisfy({ example in
                  (example.kind == .glyph ? PersonalInkProfile.glyphLabels.contains(example.label)
                   : ChordRecognitionCompendium.match(example.label)?.displayText == example.label)
                  && example.hasValidRecognitionInput
              }) else { throw Failure.invalidProfile }
        guard !encoder.identity.isEmpty, (2...512).contains(encoder.vocabulary.count),
              Set(encoder.vocabulary).count == encoder.vocabulary.count,
              encoder.vocabulary.allSatisfy({ $0.count == 1 }) else { throw Failure.invalidEncoder }
        self.profile = profile
        self.encoder = encoder
        self.grouping = grouping
        encoderIdentity = encoder.identity
        context = .init(isEnabled: true, profileRevision: profile.revision, encoderIdentity: encoder.identity)
        let examples = profile.examples.sorted { $0.id.uuidString < $1.id.uuidString }
        let glyphExamples = examples.filter { $0.kind == .glyph }
        let chordExamples = examples.filter { $0.kind == .chord }
        glyphLessonCount = glyphExamples.count
        wholeChordLessonCount = chordExamples.count
        missingPersonalSymbols = PersonalInkSetupCatalog.missingSymbols(in: profile).map(\.label)
        // New musical symbols need explicit symbol lessons, not guessed labels
        // extracted from a whole-chord correction. They start with zero generic
        // mass and acquire weights through the same residual fit as other labels.
        let novel = Set(glyphExamples.map(\.label)).subtracting(encoder.vocabulary).sorted()
        let vocabulary = encoder.vocabulary + novel
        let lessons = try glyphExamples.map { example -> PersonalInkResidualHead.Lesson in
            let encoded = try Self.checked(encoder.encode(example.recognitionInput), vocabularyCount: encoder.vocabulary.count)
            return .init(label: example.label, features: encoded.embedding,
                         baseScores: try Self.baseScores(encoded, padding: novel.count))
        }
        glyphHead = try PersonalInkResidualHead(context: context, vocabulary: vocabulary, featureCount: 128, lessons: lessons)
        if let bank = encoder.anchorBank {
            guard bank.vocabulary == encoder.vocabulary else { throw Failure.invalidEncoder }
            anchoredHead = try .init(context: context, vocabulary: vocabulary, featureCount: 128, lessons: lessons, bank: bank)
        } else { anchoredHead = nil }
        if Set(chordExamples.map(\.label)).count >= 2 {
            wholeHead = try PersonalInkBalancedRidge.fit(
                features: chordExamples.map { try Self.checked(encoder.encode($0.recognitionInput), vocabularyCount: encoder.vocabulary.count).embedding },
                labels: chordExamples.map(\.label), regularization: 0.1)
        } else { wholeHead = nil }
    }

    func predict(_ strokes: [InkStroke], currentProfile: PersonalInkProfile) throws -> Prediction {
        try predict(strokes, currentProfile: currentProfile, grouping: grouping)
    }

    /// Route a single frozen fit through different ownership policies. The
    /// override changes grouping only; neither route refits or learns a lesson.
    func predict(_ strokes: [InkStroke], currentProfile: PersonalInkProfile,
                 grouping: Grouping) throws -> Prediction {
        // Exact profile equality also catches mutations which forgot to advance
        // the revision. A frozen historical run passes its own immutable profile.
        guard currentProfile.isEnabled else { throw Failure.disabled }
        guard currentProfile == profile else { throw Failure.staleProfile }
        guard PersonalInkShape(strokes: strokes) != nil else { throw Failure.invalidInk }
        let lossless = grouping != .legacyGeometryV1
        if lossless {
            // Do not bypass source geometry validation by rebuilding bounds.
            // Invalid/oversized ink is a failed attempt, not a partial read.
            do { _ = try ChordInkPreparedFeatureGeometry.prepare(strokes: strokes) }
            catch is ChordInkFeatureEncodingError { throw Failure.invalidInk }
        }
        // Geometry-only grouping is retained explicitly in both versions: a
        // wrapper repair must not also change cross-stroke timing heuristics.
        let geometry = strokes.map { InkStroke(points: $0.points) }
        let clusterer = StrokeClusterer(wrapperPolicy: lossless
            ? .preserveOriginalInk : .semanticNormalization)
        let clusters = clusterer.indexedClusters(geometry)
        guard !clusters.isEmpty, clusters.count <= 16,
              clusters.flatMap(\.originalIndexes).sorted() == Array(strokes.indices) else { throw Failure.invalidInk }
        if grouping == .selectiveLosslessOwnershipV3 {
            let ownership: PersonalInkOwnershipAssessment
            do {
                ownership = try .assess(sourceStrokeCount: strokes.count,
                    proposedGroups: clusters.map { $0.originalIndexes.sorted() })
            } catch { throw Failure.invalidInk }
            // Structural coverage is not calibrated ownership. Stop before
            // ANY query-group or whole-chord encoding, even with personal or
            // anchored lessons. Legacy hypotheses remain in the paired arm.
            return Prediction(genericChord: nil, personalChord: nil, glyphs: [],
                wholeChordRanks: [], knownInk: PersonalInkSnapshot(profile: profile)
                    .wasAlreadyLearned(strokes: strokes), anchored: nil, ownership: ownership)
        }
        var anchoredRanks: [[Rank]] = []
        let glyphs = try clusters.map { indexed -> Glyph in
            let indexes = lossless
                ? indexed.originalIndexes.sorted() : indexed.originalIndexes
            let input = lossless
                ? indexes.map { strokes[$0] } : indexed.cluster.strokes
            let reading = try readGroup(input, originalStrokeIndexes: indexes)
            if let anchored = reading.anchored { anchoredRanks.append(anchored) }
            return reading.glyph
        }
        var whole: [Rank] = []
        if let wholeHead {
            let feature = try Self.checked(encoder.encode(strokes), vocabularyCount: encoder.vocabulary.count).embedding
            whole = Array(Self.rank(labels: wholeHead.labels, scores: wholeHead.weights.map { weight in
                zip(weight, feature).reduce(0) { $0 + $1.0 * $1.1 }
            }).prefix(3))
        }
        let anchoredChordDomainRanks = anchoredRanks.map {
            ChordRecognitionDomain.projectTopRanked($0) { $0.label }
        }
        return Prediction(genericChord: Self.compose(glyphs.map { $0.genericChordDomainRanks.first?.label }),
                          personalChord: Self.compose(glyphs.map { $0.personalChordDomainRanks.first?.label }),
                          glyphs: glyphs, wholeChordRanks: whole,
                          knownInk: PersonalInkSnapshot(profile: profile).wasAlreadyLearned(strokes: strokes),
                          anchored: anchoredHead == nil ? nil : .init(learnerVersion: PersonalInkAnchoredResidualHead.version,
                              chord: Self.compose(anchoredChordDomainRanks.map { $0.first?.label }), glyphRanks: anchoredRanks))
    }

    /// Research identity seam only: supplied groups are not certified owners.
    /// All structural validation precedes encoding. No answer, expected count,
    /// prompt or label is accepted; no grouping, whole-head rescue or chord
    /// composition runs here, and the frozen fit is not changed.
    func readSuppliedOriginalGroups(_ strokes: [InkStroke], originalIndexGroups: [[Int]],
                                   currentProfile: PersonalInkProfile) throws -> GroupIdentityReading {
        try validateSuppliedOriginalGroups(strokes, originalIndexGroups: originalIndexGroups,
            currentProfile: currentProfile)
        var anchoredRanks: [[Rank]] = []
        let glyphs = try originalIndexGroups.map { group -> Glyph in
            // Preserve incoming group order, but restore acquisition order
            // inside each group using the exact original stroke values.
            let ordered = group.sorted()
            let reading = try readGroup(ordered.map { strokes[$0] }, originalStrokeIndexes: ordered)
            if let anchored = reading.anchored { anchoredRanks.append(anchored) }
            return reading.glyph
        }
        return GroupIdentityReading(sourceStrokeCount: strokes.count, encoderIdentity: encoderIdentity,
            glyphs: glyphs, anchoredGlyphRanks: anchoredHead == nil ? nil : anchoredRanks)
    }

    /// Full generic-distribution composition conditional on explicitly supplied
    /// groups. This does not resolve ownership, accept a chord, learn a label,
    /// or turn personal correction scores into probabilities. The selective
    /// unresolved-ownership route must not use this seam to bypass its stop.
    func readSuppliedOriginalCanonicalHypotheses(_ strokes: [InkStroke], originalIndexGroups: [[Int]],
        currentProfile: PersonalInkProfile, maximumExaminedSequences: Int = 4_096,
        maximumReturnedCandidates: Int = 16) throws -> CanonicalProbabilityIdentityReading {
        guard grouping == .losslessSourceV2 else { throw Failure.unsupportedHypothesisGrouping }
        try validateSuppliedOriginalGroups(strokes, originalIndexGroups: originalIndexGroups,
            currentProfile: currentProfile)
        guard (1...PersonalInkMLCanonicalProbabilityDecoder.maximumSearchBudget).contains(maximumExaminedSequences),
              (1...PersonalInkMLCanonicalProbabilityDecoder.maximumCandidateBudget).contains(maximumReturnedCandidates) else {
            throw PersonalInkMLCanonicalProbabilityDecoder.Failure.invalidSearchLimits
        }
        let columns = try originalIndexGroups.map { group -> PersonalInkMLCanonicalProbabilityDecoder.Column in
            let ordered = group.sorted()
            let features = try Self.checked(encoder.encode(ordered.map { strokes[$0] }),
                vocabularyCount: encoder.vocabulary.count)
            let probabilities = try Self.baseScores(features, padding: 0)
            return .init(originalStrokeIndexes: ordered,
                probabilities: zip(encoder.vocabulary, probabilities).map {
                    .init($0.0, probability: $0.1)
                })
        }
        let hypotheses = try PersonalInkMLCanonicalProbabilityDecoder().decode(
            sourceStrokeCount: strokes.count, orderedColumns: columns,
            maximumExaminedSequences: maximumExaminedSequences,
            maximumReturnedCandidates: maximumReturnedCandidates)
        return .init(sourceStrokeCount: strokes.count, encoderIdentity: encoderIdentity,
            genericVocabulary: encoder.vocabulary, columns: columns, hypotheses: hypotheses)
    }

    private func validateSuppliedOriginalGroups(_ strokes: [InkStroke], originalIndexGroups: [[Int]],
                                               currentProfile: PersonalInkProfile) throws {
        guard currentProfile.isEnabled else { throw Failure.disabled }
        guard currentProfile == profile else { throw Failure.staleProfile }
        // Diagnostic point/zero-extent glyphs are valid raster inputs. They do
        // not establish whole-chord or personal-lesson quality, so the stricter
        // shape gate used by those historical routes does not apply here.
        do { _ = try ChordInkPreparedFeatureGeometry.prepare(strokes: strokes) }
        catch is ChordInkFeatureEncodingError { throw Failure.invalidInk }
        guard (1...16).contains(originalIndexGroups.count),
              originalIndexGroups.allSatisfy({ !$0.isEmpty }) else { throw Failure.invalidInk }
        let indexes = originalIndexGroups.flatMap { $0 }
        guard indexes.count == strokes.count,
              indexes.allSatisfy({ strokes.indices.contains($0) }),
              Set(indexes).count == strokes.count else { throw Failure.invalidInk }
    }

    /// One unchanged ranking path for historical predictions and conditional
    /// identity reads. The caller chooses the input; legacy wrapper strokes
    /// remain untouched, while lossless callers supply original stroke values.
    private func readGroup(_ input: [InkStroke], originalStrokeIndexes: [Int]) throws
        -> (glyph: Glyph, anchored: [Rank]?) {
        let encoded = try Self.checked(encoder.encode(input), vocabularyCount: encoder.vocabulary.count)
        let base = try Self.baseScores(encoded, padding: glyphHead.vocabulary.count - encoder.vocabulary.count)
        let generic = Self.rank(labels: encoder.vocabulary, scores: Array(base.prefix(encoder.vocabulary.count)))
        let personal = try glyphHead.rankedCandidates(features: encoded.embedding, baseScores: base, currentContext: context)
            .map { Rank(label: $0.label, score: $0.score) }
        let anchored: [Rank]?
        if let anchoredHead {
            let ranks = try anchoredHead.rankedCandidates(features: encoded.embedding, baseScores: base, currentContext: context)
            anchored = Array(ranks.prefix(3)).map { Rank(label: $0.label, score: $0.score) }
        } else { anchored = nil }
        return (Glyph(originalStrokeIndexes: originalStrokeIndexes,
            generic: Array(generic.prefix(3)), personal: Array(personal.prefix(3))), anchored)
    }

    static func compose(_ labels: [String?]) -> String? {
        guard !labels.isEmpty, labels.allSatisfy({ $0 != nil }) else { return nil }
        let tokens = labels.compactMap { $0 }
        guard tokens.allSatisfy(ChordRecognitionDomain.isAllowedGlyphToken) else {
            return nil
        }
        // Only exact top choices; never search lower ranks using grammar or an
        // intended answer. The setup-label catalog is not a grammar whitelist:
        // generic letters in "maj", "sus" etc. must remain available to compose.
        // Recognition must consume every token. Use the complete-input parser;
        // chord-domain filtering is not permission to shorten a written chord.
        return (try? ChordSymbolParser.parse(tokens.joined()))?.displayText
    }

    private static func presentationLabels(
        from projectedRanks: [[Rank]],
        expectedGroupCount: Int
    ) -> [String?] {
        guard projectedRanks.count == expectedGroupCount else {
            return Array(repeating: nil, count: expectedGroupCount)
        }
        let labels = projectedRanks.map { $0.first?.label }
        guard compose(labels) != nil else {
            return Array(repeating: nil, count: expectedGroupCount)
        }
        return labels
    }
    private static func checked(_ value: PersonalInkVisualFeatures, vocabularyCount: Int) throws -> PersonalInkVisualFeatures {
        guard value.embedding.count == 128, value.genericLogits.count == vocabularyCount,
              value.embedding.allSatisfy(\.isFinite), value.genericLogits.allSatisfy(\.isFinite),
              abs(value.embedding.reduce(0) { $0 + $1 * $1 } - 1) <= 1e-3 else { throw Failure.invalidEncoder }
        return value
    }
    private static func baseScores(_ value: PersonalInkVisualFeatures, padding: Int) throws -> [Double] {
        try PersonalInkResidualHead.normalizedScores(logits: value.genericLogits) + Array(repeating: 0, count: padding)
    }
    private static func rank(labels: [String], scores: [Double]) -> [Rank] {
        zip(labels, scores).map { Rank(label: $0, score: $1) }.sorted {
            $0.score == $1.score ? $0.label < $1.label : $0.score > $1.score
        }
    }
}

/// Saved-run prediction and scoring are deliberately separate: labels cannot
/// reach the model fit or inference API, and today's profile is never substituted
/// for the run's pre-test profile. Neither this report nor its caller teaches.
struct PersonalInkLearnedRunReport: Codable {
    struct Row: Codable, Identifiable {
        let id: UUID
        let prediction: PersonalInkLearnedComparison.Prediction?
        let exclusion: String?
        var intended: String? = nil
        var recordedBaseline: String? = nil
        var recordedPersonalized: String? = nil
        // Separate hypotheses, never substituted into the historical top-1
        // prediction or its scorecard. Nil preserves older report decoding.
        var completeTokenHypotheses: PersonalInkMLChordHypothesisComparison? = nil
    }
    var id = UUID()
    var createdAt = Date()
    let runID: UUID
    let sourceRunSHA256: String
    let encoderIdentity: String
    let profileRevision: UUID
    let glyphLessonCount: Int
    let wholeChordLessonCount: Int
    let rows: [Row]
    // Additive fields keep earlier reports readable without inventing scores.
    var chartStyle: String? = nil
    var phase: PersonalInkEvaluationRun.Phase? = nil
    var profileGeneration: UUID? = nil
    // Exact stored run-start metadata, never inferred from the live profile or
    // backfilled for an older run whose support intake is unknown.
    var profileLineage: PersonalInkProfileLineageSummary? = nil
    var originalLearnerVersion: String? = nil
    var groupingVersion: String? = nil
    var evaluationSourceVersion: String? = nil
    var evaluationSourceSHA256: String? = nil
    var scorecard: PersonalInkLearnedScorecard? = nil
    var ownershipPairID: UUID? = nil
    // Preserve the requested method even when every row is unsupported.
    var completeTokenHypothesisVersion: String? = nil

    static func compare(_ run: PersonalInkEvaluationRun, encoder: PersonalInkVisualEncoding,
                        grouping: PersonalInkLearnedComparison.Grouping = .legacyGeometryV1,
                        includesCompleteTokenHypotheses: Bool = false) throws -> Self {
        try validateRun(run)
        guard !includesCompleteTokenHypotheses || grouping == .losslessSourceV2 else {
            throw PersonalInkLearnedComparison.Failure.unsupportedHypothesisGrouping
        }
        let model = try PersonalInkLearnedComparison(profile: run.profile, encoder: encoder, grouping: grouping)
        return try compare(run, model: model, grouping: grouping,
                           includesCompleteTokenHypotheses: includesCompleteTokenHypotheses)
    }

    static func validateRun(_ run: PersonalInkEvaluationRun) throws {
        guard run.status == .complete else { throw PersonalInkLearnedComparison.Failure.incompleteRun }
        guard Set(run.records.map(\.id)).count == run.records.count else {
            throw PersonalInkLearnedComparison.Failure.ambiguousRun
        }
        if let frozen = run.profileLineage {
            // Reconstruct solely to validate the stored account against its
            // own frozen source. Do not replace it or invent legacy metadata.
            guard frozen == PersonalInkProfileLineageSummary(profile: run.profile, querySessionID: run.id) else {
                throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
            }
        }
    }

    /// Shared by the paired route after one frozen profile fit. Labels remain
    /// in post-inference rows/scorecards, never in predict or ownership assess.
    static func compare(_ run: PersonalInkEvaluationRun, model: PersonalInkLearnedComparison,
                        grouping: PersonalInkLearnedComparison.Grouping,
                        preservesKnownInkExclusions: Bool = false,
                        includesCompleteTokenHypotheses: Bool = false) throws -> Self {
        try validateRun(run)
        guard !includesCompleteTokenHypotheses || grouping == .losslessSourceV2 else {
            throw PersonalInkLearnedComparison.Failure.unsupportedHypothesisGrouping
        }
        guard model.profile == run.profile else { throw PersonalInkLearnedComparison.Failure.staleProfile }
        let rows = try run.records.map { record -> Row in
            func row(_ prediction: PersonalInkLearnedComparison.Prediction?, _ exclusion: String?) throws -> Row {
                var result = Row(id: record.id, prediction: prediction, exclusion: exclusion)
                if includesCompleteTokenHypotheses, let prediction, let exact = record.recognitionStrokes {
                    result.completeTokenHypotheses = try .make(prediction: prediction, sourceStrokeCount: exact.count)
                }
                // Intended labels enter only after the complete search above.
                result.intended = record.intended
                result.recordedBaseline = record.baseline
                result.recordedPersonalized = record.personalized
                return result
            }
            guard let exact = record.recognitionStrokes else {
                return try row(nil, "Original recognition input was not saved in this older test.")
            }
            guard !record.groupingIssue || grouping == .selectiveLosslessOwnershipV3 else {
                return try row(nil, "Incorrect grouping; not scored as one chord.")
            }
            let prediction: PersonalInkLearnedComparison.Prediction
            do { prediction = try model.predict(exact, currentProfile: run.profile, grouping: grouping) }
            catch PersonalInkLearnedComparison.Failure.invalidInk {
                // A fresh complete attempt unsupported by segmentation remains
                // a failed read in the denominator, not an omitted attempt.
                if record.groupingIssue { return try row(nil, "Incorrect grouping; not scored as one chord.") }
                // Paired evidence must retain the source capture's known-ink
                // scoring exclusion even when inference rejects its input.
                // Leave historical standalone report output unchanged.
                if preservesKnownInkExclusions && record.knownInk {
                    return try row(nil, "Matches previously learned ink; not a fresh sample.")
                }
                return try row(nil, "Input or segmentation unsupported; counted as a failed complete read when this is a labeled fresh chord.")
            }
            // Capture-level grouping mistakes remain a separate scoring
            // exclusion. They do not erase a new ink-only ownership proposal.
            if record.groupingIssue { return try row(prediction, "Incorrect grouping; not scored as one chord.") }
            return try row(prediction, record.knownInk || prediction.knownInk ? "Matches previously learned ink; not a fresh sample." : nil)
        }
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try jsonEncoder.encode(run)).map { String(format: "%02x", $0) }.joined()
        var report = Self(runID: run.id, sourceRunSHA256: digest, encoderIdentity: model.encoderIdentity, profileRevision: run.profile.revision,
                          glyphLessonCount: model.glyphLessonCount, wholeChordLessonCount: model.wholeChordLessonCount, rows: rows)
        report.chartStyle = run.style
        report.phase = run.phase
        report.profileGeneration = run.profile.generation
        report.profileLineage = run.profileLineage
        report.originalLearnerVersion = PersonalInkResidualHead.version
        report.groupingVersion = grouping.rawValue
        report.completeTokenHypothesisVersion = includesCompleteTokenHypotheses
            ? PersonalInkMLChordHypothesisComparison.version : nil
        report.evaluationSourceVersion = "evaluation-evidence-v1"
        report.evaluationSourceSHA256 = try evaluationSourceDigest(run)
        report.scorecard = PersonalInkLearnedScorecard(run: run, rows: rows, anchoredAvailable: model.anchoredAvailable,
            ownershipAvailable: grouping == .selectiveLosslessOwnershipV3)
        return report
    }

    /// Teaching receipts are later activity, not a change to the frozen test.
    /// Keep the original whole-run digest above; give this projection its own
    /// version and digest rather than changing an existing field's meaning.
    static func evaluationSourceDigest(_ run: PersonalInkEvaluationRun) throws -> String {
        var evidence = run
        evidence.teachingReceipt = nil
        for index in evidence.records.indices { evidence.records[index].taught = false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = Data("evaluation-evidence-v1\n".utf8) + (try encoder.encode(evidence))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Separate append-only local evidence. Never overwrite the source journal,
    /// profile, or an earlier comparison, even when rerunning the same test.
    func save(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: directory.appendingPathComponent("\(id.uuidString).json"), options: .withoutOverwriting)
    }
}

/// Post-inference scoring only. Every method uses the same eligible attempts;
/// the intended labels never enter model fitting, ranking, or assembly.
struct PersonalInkLearnedScorecard: Codable, Equatable {
    enum Method: String, Codable {
        case recordedBaseline, recordedPersonalized, sharedML, personalML, anchoredML
        var title: String {
            switch self {
            case .recordedBaseline: return "Standard app"
            case .recordedPersonalized: return "App + examples"
            case .sharedML: return "Shared ML"
            case .personalML: return "ML + examples (original)"
            case .anchoredML: return "ML + examples (new)"
            }
        }
        var reference: Method? {
            switch self {
            case .recordedPersonalized: return .recordedBaseline
            case .personalML, .anchoredML: return .sharedML
            default: return nil
            }
        }
    }
    struct Score: Codable, Equatable, Identifiable {
        let method: Method
        let correct: Int
        let wrongReads: Int
        let noReads: Int
        let improvements: Int?
        let regressions: Int?
        let trustedWrongReads: Int?
        var id: String { method.rawValue }
    }
    let expectedChordCount: Int?
    let capturedCount: Int
    let eligibleCount: Int
    let missingCount: Int
    let groupingIssueCount: Int
    let knownInkCount: Int
    let missingOriginalInputCount: Int
    let invalidLabelCount: Int
    let unsupportedInputCount: Int
    let wholeChartDenominator: Int?
    let scores: [Score]
    var ownershipUnresolvedCount: Int? = nil

    init(run: PersonalInkEvaluationRun, rows: [PersonalInkLearnedRunReport.Row], anchoredAvailable: Bool,
         ownershipAvailable: Bool = false) {
        // compare() has already rejected duplicate record IDs. This initializer
        // consumes its predictions; it cannot call a recognizer or teach.
        let aligned = zip(run.records, rows).filter { $0.id == $1.id }
        func validLabel(_ record: PersonalInkEvaluationRecord) -> Bool {
            guard let label = record.intended, let parsed = try? ChordSymbolParser.parse(label) else { return false }
            return parsed.displayText == label
        }
        func known(_ record: PersonalInkEvaluationRecord, _ row: PersonalInkLearnedRunReport.Row) -> Bool {
            record.knownInk || row.prediction?.knownInk == true
        }
        let eligible = aligned.filter { record, row in
            validLabel(record) && !record.groupingIssue && !known(record, row) && record.recognitionStrokes != nil
        }
        expectedChordCount = run.expectedChordCount
        capturedCount = run.records.count
        eligibleCount = eligible.count
        missingCount = run.missingCount
        groupingIssueCount = run.records.filter(\.groupingIssue).count
        knownInkCount = aligned.filter { known($0, $1) }.count
        missingOriginalInputCount = run.records.filter { $0.recognitionStrokes == nil }.count
        invalidLabelCount = run.records.filter { !validLabel($0) }.count
        unsupportedInputCount = eligible.filter { $1.prediction == nil }.count
        ownershipUnresolvedCount = ownershipAvailable
            ? eligible.filter { $1.prediction?.ownership?.disposition == .unresolved }.count : nil
        if let written = run.expectedChordCount, (1...64).contains(written),
           written >= run.records.count, eligible.count == run.records.count, aligned.count == run.records.count {
            wholeChartDenominator = written
        } else { wholeChartDenominator = nil }

        func read(_ method: Method, _ record: PersonalInkEvaluationRecord, _ row: PersonalInkLearnedRunReport.Row) -> String? {
            switch method {
            case .recordedBaseline: return record.baseline
            case .recordedPersonalized: return record.personalized
            case .sharedML: return row.prediction?.genericChord
            case .personalML: return row.prediction?.personalChord
            case .anchoredML: return row.prediction?.anchored?.chord
            }
        }
        let methods: [Method] = [.recordedBaseline, .recordedPersonalized, .sharedML, .personalML] + (anchoredAvailable ? [.anchoredML] : [])
        scores = methods.map { method in
            let correct = eligible.filter { read(method, $0, $1) == $0.intended }.count
            let noReads = eligible.filter { read(method, $0, $1) == nil }.count
            let gains = method.reference.map { reference in
                eligible.filter { read(reference, $0, $1) != $0.intended && read(method, $0, $1) == $0.intended }.count
            }
            let harms = method.reference.map { reference in
                eligible.filter { read(reference, $0, $1) == $0.intended && read(method, $0, $1) != $0.intended }.count
            }
            let trustedWrong: Int?
            switch method {
            case .recordedBaseline:
                trustedWrong = eligible.filter { record, _ in
                    record.baselineAction == "trusted" && record.baseline != nil && record.baseline != record.intended
                }.count
            case .recordedPersonalized:
                trustedWrong = eligible.filter { record, _ in
                    record.personalizedAction == "trusted" && record.personalized != nil && record.personalized != record.intended
                }.count
            default: trustedWrong = nil
            }
            return Score(method: method, correct: correct, wrongReads: eligible.count - correct - noReads, noReads: noReads,
                         improvements: gains, regressions: harms, trustedWrongReads: trustedWrong)
        }
    }
}

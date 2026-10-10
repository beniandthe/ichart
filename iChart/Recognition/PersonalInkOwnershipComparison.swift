import Foundation

/// One append-only comparison receipt, not two independently published files.
/// Both arms use the same frozen fit; unresolved ownership never teaches or
/// turns a closed-set identity ranking into an accepted chord.
struct PersonalInkOwnershipComparisonReport: Codable {
    static let currentVersion = "personal-selective-ownership-pair-v1"
    enum Failure: LocalizedError {
        case mismatchedReports
        var errorDescription: String? {
            "The paired comparisons do not share the same frozen input, profile, model and scoring eligibility. Neither report was saved."
        }
    }

    let version: String
    let id: UUID
    let createdAt: Date
    let runID: UUID
    let legacy: PersonalInkLearnedRunReport
    let selective: PersonalInkLearnedRunReport

    init(legacy: PersonalInkLearnedRunReport, selective: PersonalInkLearnedRunReport) throws {
        try Self.validate(legacy: legacy, selective: selective)
        let pairID = legacy.ownershipPairID ?? UUID()
        var boundLegacy = legacy
        var boundSelective = selective
        boundLegacy.ownershipPairID = pairID
        boundSelective.ownershipPairID = pairID
        version = Self.currentVersion
        id = pairID
        createdAt = Date()
        runID = legacy.runID
        self.legacy = boundLegacy
        self.selective = boundSelective
    }

    static func compare(_ run: PersonalInkEvaluationRun, encoder: PersonalInkVisualEncoding) throws -> Self {
        try PersonalInkLearnedRunReport.validateRun(run)
        let model = try PersonalInkLearnedComparison(profile: run.profile, encoder: encoder)
        let legacy = try PersonalInkLearnedRunReport.compare(run, model: model, grouping: .legacyGeometryV1,
            preservesKnownInkExclusions: true)
        let selective = try PersonalInkLearnedRunReport.compare(run, model: model, grouping: .selectiveLosslessOwnershipV3,
            preservesKnownInkExclusions: true)
        return try Self(legacy: legacy, selective: selective)
    }

    private static func validDigest(_ digest: String) -> Bool {
        digest.count == 64 && digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static let unsupportedExclusion = "Input or segmentation unsupported; counted as a failed complete read when this is a labeled fresh chord."

    /// Reconstruct the scored set from saved row evidence rather than trusting
    /// an aggregate total. Unsupported fresh input is still eligible; missing,
    /// capture-grouping and known-ink exclusions are not. Unknown states fail
    /// closed instead of silently inventing eligibility for a historical row.
    private static func eligibleRows(_ report: PersonalInkLearnedRunReport) throws -> [PersonalInkLearnedRunReport.Row] {
        try report.rows.filter { row in
            let excluded: Bool
            switch row.exclusion {
            case nil:
                guard row.prediction != nil else { throw Failure.mismatchedReports }
                excluded = false
            case unsupportedExclusion:
                guard row.prediction == nil else { throw Failure.mismatchedReports }
                excluded = false
            case "Original recognition input was not saved in this older test.":
                guard row.prediction == nil else { throw Failure.mismatchedReports }
                excluded = true
            case "Incorrect grouping; not scored as one chord.",
                 "Matches previously learned ink; not a fresh sample.":
                excluded = true
            default: throw Failure.mismatchedReports
            }
            guard !excluded, row.prediction?.knownInk != true,
                  let intended = row.intended, let parsed = try? ChordSymbolParser.parse(intended) else { return false }
            return parsed.displayText == intended
        }
    }

    private static func validate(legacy: PersonalInkLearnedRunReport, selective: PersonalInkLearnedRunReport) throws {
        guard legacy.id != selective.id,
              legacy.runID == selective.runID,
              validDigest(legacy.sourceRunSHA256), legacy.sourceRunSHA256 == selective.sourceRunSHA256,
              !legacy.encoderIdentity.isEmpty, legacy.encoderIdentity == selective.encoderIdentity,
              legacy.profileRevision == selective.profileRevision,
              legacy.profileGeneration != nil, legacy.profileGeneration == selective.profileGeneration,
              legacy.profileLineage == selective.profileLineage,
              legacy.glyphLessonCount >= 0, legacy.glyphLessonCount == selective.glyphLessonCount,
              legacy.wholeChordLessonCount >= 0, legacy.wholeChordLessonCount == selective.wholeChordLessonCount,
              legacy.chartStyle != nil, legacy.chartStyle == selective.chartStyle,
              legacy.phase != nil, legacy.phase == selective.phase,
              legacy.originalLearnerVersion == PersonalInkResidualHead.version,
              legacy.originalLearnerVersion == selective.originalLearnerVersion,
              legacy.groupingVersion == PersonalInkLearnedComparison.Grouping.legacyGeometryV1.rawValue,
              selective.groupingVersion == PersonalInkLearnedComparison.Grouping.selectiveLosslessOwnershipV3.rawValue,
              legacy.evaluationSourceVersion == "evaluation-evidence-v1",
              legacy.evaluationSourceVersion == selective.evaluationSourceVersion,
              let sourceDigest = legacy.evaluationSourceSHA256, validDigest(sourceDigest),
              sourceDigest == selective.evaluationSourceSHA256,
              legacy.ownershipPairID == selective.ownershipPairID,
              legacy.rows.map(\.id) == selective.rows.map(\.id),
              Set(legacy.rows.map(\.id)).count == legacy.rows.count,
              let oldScore = legacy.scorecard, let newScore = selective.scorecard,
              oldScore.ownershipUnresolvedCount == nil,
              newScore.ownershipUnresolvedCount != nil,
              oldScore.expectedChordCount == newScore.expectedChordCount,
              oldScore.capturedCount == newScore.capturedCount,
              oldScore.capturedCount == legacy.rows.count,
              newScore.capturedCount == selective.rows.count,
              oldScore.eligibleCount == newScore.eligibleCount,
              oldScore.missingCount == newScore.missingCount,
              oldScore.groupingIssueCount == newScore.groupingIssueCount,
              oldScore.knownInkCount == newScore.knownInkCount,
              oldScore.missingOriginalInputCount == newScore.missingOriginalInputCount,
              oldScore.invalidLabelCount == newScore.invalidLabelCount,
              oldScore.wholeChartDenominator == newScore.wholeChartDenominator,
              oldScore.scores.map(\.method) == newScore.scores.map(\.method) else { throw Failure.mismatchedReports }
        for (old, new) in zip(legacy.rows, selective.rows) {
            guard old.intended == new.intended, old.recordedBaseline == new.recordedBaseline,
                  old.recordedPersonalized == new.recordedPersonalized,
                  old.prediction?.ownership == nil else { throw Failure.mismatchedReports }
            // Missing/capture-grouping/known-ink exclusions must identify the
            // same rows, not merely produce equal aggregate denominators. A
            // fresh unsupported attempt may instead have an unresolved proposal.
            let freshDifference = (old.prediction == nil && old.exclusion == unsupportedExclusion
                && new.prediction?.knownInk == false && new.exclusion == nil)
                || (new.prediction == nil && new.exclusion == unsupportedExclusion
                    && old.prediction?.knownInk == false && old.exclusion == nil)
            guard old.exclusion == new.exclusion || freshDifference else { throw Failure.mismatchedReports }
            if let oldPrediction = old.prediction, let newPrediction = new.prediction {
                guard oldPrediction.knownInk == newPrediction.knownInk else { throw Failure.mismatchedReports }
            }
            if let prediction = new.prediction {
                guard prediction.ownership != nil, prediction.genericChord == nil,
                      prediction.personalChord == nil, prediction.anchored == nil,
                      prediction.glyphs.isEmpty, prediction.wholeChordRanks.isEmpty else { throw Failure.mismatchedReports }
            }
        }
        for (old, new) in zip(oldScore.scores, newScore.scores) {
            if old.method == .recordedBaseline || old.method == .recordedPersonalized {
                guard old == new else { throw Failure.mismatchedReports }
            } else {
                guard new.correct == 0, new.wrongReads == 0,
                      new.noReads == newScore.eligibleCount else { throw Failure.mismatchedReports }
            }
        }
        let oldEligible = try eligibleRows(legacy)
        let newEligible = try eligibleRows(selective)
        let unresolved = newEligible.filter { $0.prediction?.ownership?.disposition == .unresolved }.count
        let unsupported = newEligible.filter { $0.prediction == nil }.count
        guard oldEligible.map(\.id) == newEligible.map(\.id),
              oldScore.eligibleCount == oldEligible.count, newScore.eligibleCount == newEligible.count,
              oldScore.unsupportedInputCount == oldEligible.filter({ $0.prediction == nil }).count,
              newScore.ownershipUnresolvedCount == unresolved,
              newScore.unsupportedInputCount == unsupported,
              unsupported + unresolved == newEligible.count else { throw Failure.mismatchedReports }
    }

    private enum CodingKeys: String, CodingKey { case version, id, createdAt, runID, legacy, selective }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(String.self, forKey: .version)
        let id = try values.decode(UUID.self, forKey: .id)
        let runID = try values.decode(UUID.self, forKey: .runID)
        let legacy = try values.decode(PersonalInkLearnedRunReport.self, forKey: .legacy)
        let selective = try values.decode(PersonalInkLearnedRunReport.self, forKey: .selective)
        guard version == Self.currentVersion, id == legacy.ownershipPairID,
              id == selective.ownershipPairID, runID == legacy.runID else { throw Failure.mismatchedReports }
        try Self.validate(legacy: legacy, selective: selective)
        self.version = version
        self.id = id
        self.createdAt = try values.decode(Date.self, forKey: .createdAt)
        self.runID = runID
        self.legacy = legacy
        self.selective = selective
    }

    /// Write complete bytes first, then exclusively publish their filesystem
    /// link. A failed write/link cannot publish a partial pair or replace an
    /// existing receipt. Hidden staging files are cleaned on every exit path.
    func save(in directory: URL) throws {
        guard version == Self.currentVersion, runID == legacy.runID,
              id == legacy.ownershipPairID, id == selective.ownershipPairID else { throw Failure.mismatchedReports }
        try Self.validate(legacy: legacy, selective: selective)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".\(id.uuidString).\(UUID().uuidString).staging")
        defer { try? manager.removeItem(at: staging) }
        try data.write(to: staging, options: .withoutOverwriting)
        try manager.linkItem(at: staging, to: directory.appendingPathComponent("\(id.uuidString).json"))
    }
}

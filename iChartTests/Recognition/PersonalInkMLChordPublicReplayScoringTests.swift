import Foundation
import CryptoKit
import XCTest
@testable import iChart

final class PersonalInkMLChordPublicReplayScoringTests: XCTestCase {
    func testProvidedFrozenPublicCompleteTokenPredictionsAreScoredSeparately() throws {
        let env = ProcessInfo.processInfo.environment
        guard let inputPath = env["ICHART_PUBLIC_COMPLETE_TOKEN_INPUT"],
              let predictionPath = env["ICHART_PUBLIC_COMPLETE_TOKEN_PREDICTIONS"],
              let scorePath = env["ICHART_PUBLIC_COMPLETE_TOKEN_SCORE"] else {
            throw XCTSkip("Provide the pinned public input, completed immutable prediction packet and new score path")
        }
        guard [inputPath, predictionPath, scorePath].allSatisfy({ !$0.isEmpty }) else {
            throw PublicCompleteTokenScore.Failure.binding
        }
        let inputURL = PublicCompleteTokenScore.resolved(inputPath)
        let predictionURL = PublicCompleteTokenScore.resolved(predictionPath)
        let scoreURL = PublicCompleteTokenScore.resolved(scorePath)
        try PublicCompleteTokenScore.validateOutput(scoreURL, input: inputURL, predictions: predictionURL)
        // Read and freeze the complete prediction packet before opening labels.
        let predictionData = try Data(contentsOf: predictionURL)
        let packet = try JSONDecoder().decode(PersonalInkMLChordPublicRankReplay.Packet.self,
            from: predictionData)
        let inputData = try Data(contentsOf: inputURL)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let sources = try PersonalInkMLChordPublicRankReplay.sourceIdentity(repositoryRoot: root)
        let labeled = try PublicCompleteTokenScore.validate(packet, inputData: inputData,
            inputPath: inputURL.path, sourceFiles: sources, requirePublicCounts: true)
        let report = PublicCompleteTokenScore.score(packet, labeled: labeled,
            predictionSHA256: PersonalInkMLChordPublicRankReplay.digest(predictionData))
        guard try Data(contentsOf: inputURL) == inputData,
              try Data(contentsOf: predictionURL) == predictionData,
              try PersonalInkMLChordPublicRankReplay.sourceIdentity(repositoryRoot: root) == sources else {
            throw PublicCompleteTokenScore.Failure.immutableInput
        }
        try PublicCompleteTokenScore.save(report, at: scoreURL, input: inputURL, predictions: predictionURL)
        XCTAssertEqual(report.rows.count, 3_104)
        XCTAssertEqual(report.totals.values.reduce(0) { $0 + $1.allRows }, 6_208,
            "Two routes are paired observations of 3,104 source rows")
        print("PUBLIC_COMPLETE_TOKEN_SCORE rows=3104 pairedRoutes=true selected=first-retained-candidate onlyObservedPublicDiagnostic=true")
    }

    func testRetainedCandidateCoverageCannotChooseThePrimaryHypothesis() throws {
        let fixture = try PublicCompleteTokenScore.fixture(expected: "C", ranks: ["D", "C"], candidates: ["D", "C"])
        let report = try PublicCompleteTokenScore.checkedSyntheticScore(fixture)
        let counts = try XCTUnwrap(report.totals["isolatedPoints32/sourceOwner"])
        XCTAssertEqual(counts.fixedFirstWrong, 1)
        XCTAssertEqual(counts.fixedFirstCorrect, 0)
        XCTAssertEqual(counts.anyRetainedCanonicalCoverage, 1)
        XCTAssertEqual(counts.rawExactFirstCandidate, 0)
        XCTAssertEqual(report.rows[0].sourceOwner.firstCandidateText, "D")
    }

    func testParserIneligibleSourceHypothesesAreWarningsAndRawCaseStaysSeparate() throws {
        let negative = try PublicCompleteTokenScore.checkedSyntheticScore(
            PublicCompleteTokenScore.fixture(expected: "α", ranks: ["C"], candidates: ["C"]))
        let warning = try XCTUnwrap(negative.totals["isolatedPoints32/sourceOwner"])
        XCTAssertEqual(warning.parserIneligible, 1)
        XCTAssertEqual(warning.parserIneligibleFirstHypothesisPresent, 1)
        XCTAssertEqual(warning.fixedFirstCorrect, 0)
        XCTAssertEqual(warning.fixedFirstWrong, 0)
        XCTAssertEqual(negative.rows[0].sourceOwner.fixedFirstOutcome, "parser-ineligible-source")
        let alias = try PublicCompleteTokenScore.checkedSyntheticScore(
            PublicCompleteTokenScore.fixture(expected: "c", ranks: ["C"], candidates: ["C"]))
        let aliasCounts = try XCTUnwrap(alias.totals["isolatedPoints32/sourceOwner"])
        XCTAssertEqual(aliasCounts.fixedFirstCorrect, 1)
        XCTAssertEqual(aliasCounts.rawExactOriginalTop1, 0)
        XCTAssertEqual(aliasCounts.rawExactFirstCandidate, 0)
    }

    func testFailuresStayInTheAllRowAndParserEligibleDenominators() throws {
        let report = try PublicCompleteTokenScore.checkedSyntheticScore(
            PublicCompleteTokenScore.fixture(expected: "C", ranks: ["C"], candidates: [], failure: "synthetic retained failure"))
        for counts in report.totals.values {
            XCTAssertEqual(counts.allRows, 1)
            XCTAssertEqual(counts.parserEligible, 1)
            XCTAssertEqual(counts.failures, 1)
            XCTAssertEqual(counts.fixedFirstNoHypothesis, 1)
            XCTAssertEqual(counts.pairedHarms, 1)
        }
        XCTAssertEqual(report.rows.count, 1)
        XCTAssertEqual(report.byWriter["synthetic-observed-writer"]?.values.first?.allRows, 1)
    }

    func testCompleteSourceOverComposerStrokeLimitRemainsAFailureRow() throws {
        let report = try PublicCompleteTokenScore.checkedSyntheticScore(
            PublicCompleteTokenScore.fixture(expected: "C", ranks: ["C"], candidates: [],
                failure: "invalidSourceStrokeCount", sourceStrokeCount: 65))
        for counts in report.totals.values {
            XCTAssertEqual(counts.allRows, 1)
            XCTAssertEqual(counts.failures, 1)
            XCTAssertEqual(counts.fixedFirstNoHypothesis, 1)
        }
        XCTAssertEqual(report.rows[0].sourceOwnerGroups, [Array(0..<65)])
    }

    func testRowSetRankAndInputBindingMismatchesAreRejected() throws {
        let fixture = try PublicCompleteTokenScore.fixture(expected: "C", ranks: ["C"], candidates: ["C"])
        let packet = fixture.packet
        let duplicate = PersonalInkMLChordPublicRankReplay.Packet(version: packet.version,
            metadata: packet.metadata, rows: packet.rows + packet.rows)
        XCTAssertThrowsError(try PublicCompleteTokenScore.validate(duplicate, inputData: fixture.data,
            inputPath: fixture.path, sourceFiles: fixture.sources, requirePublicCounts: false))
        let missing = PersonalInkMLChordPublicRankReplay.Packet(version: packet.version,
            metadata: packet.metadata, rows: [])
        XCTAssertThrowsError(try PublicCompleteTokenScore.validate(missing, inputData: fixture.data,
            inputPath: fixture.path, sourceFiles: fixture.sources, requirePublicCounts: false))
        XCTAssertThrowsError(try PublicCompleteTokenScore.validate(packet, inputData: fixture.data + Data(" ".utf8),
            inputPath: fixture.path, sourceFiles: fixture.sources, requirePublicCounts: false))
        let reading = packet.rows[0].sourceOwner
        let changed = PersonalInkMLChordPublicRankReplay.FrozenReading(sourceStrokeCount: reading.sourceStrokeCount,
            encoderIdentity: reading.encoderIdentity, columns: reading.columns, originalTop1Tokens: ["D"],
            legacyGreedyText: reading.legacyGreedyText, composerResult: reading.composerResult, failure: reading.failure)
        let changedRow = PersonalInkMLChordPublicRankReplay.Row(id: packet.rows[0].id, arm: packet.rows[0].arm,
            sourceOwner: changed, automatic: packet.rows[0].automatic)
        XCTAssertThrowsError(try PublicCompleteTokenScore.validate(
            .init(version: packet.version, metadata: packet.metadata, rows: [changedRow]),
            inputData: fixture.data, inputPath: fixture.path, sourceFiles: fixture.sources, requirePublicCounts: false))
    }

    func testScoreOutputIsExclusiveAndSourceBytesStayImmutable() throws {
        let fixture = try PublicCompleteTokenScore.fixture(expected: "C", ranks: ["C"], candidates: ["C"])
        let report = try PublicCompleteTokenScore.checkedSyntheticScore(fixture)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("synthetic-source.json")
        let predictions = directory.appendingPathComponent("synthetic-predictions.json")
        let output = directory.appendingPathComponent("synthetic-score.json")
        let predictionsData = try PublicCompleteTokenScore.canonical(fixture.packet)
        try fixture.data.write(to: input, options: .withoutOverwriting)
        try predictionsData.write(to: predictions, options: .withoutOverwriting)
        XCTAssertThrowsError(try PublicCompleteTokenScore.save(report, at: input, input: input, predictions: predictions))
        try PublicCompleteTokenScore.save(report, at: output, input: input, predictions: predictions)
        let first = try Data(contentsOf: output)
        XCTAssertThrowsError(try PublicCompleteTokenScore.save(report, at: output, input: input, predictions: predictions))
        XCTAssertEqual(try Data(contentsOf: output), first)
        XCTAssertEqual(try Data(contentsOf: input), fixture.data)
        XCTAssertEqual(try Data(contentsOf: predictions), predictionsData)
    }
}

private enum PublicCompleteTokenScore {
    typealias Replay = PersonalInkMLChordPublicRankReplay
    typealias Composer = PersonalInkMLChordComposer
    static let pinnedInputSHA256 = "c4b6acc6caf76e0f7d0af9ee8036cd672673f1690e790fee3dcf14fea329c01b"
    static let pinnedComposerSHA256 = "d2988c65de55ee43e8462cbee5063c532f27c43a479c2c1f9307acb92562d288"
    enum Failure: Error { case binding, rowSet, reading, sourceMetadata, output, immutableInput }

    /// The labels and writer identifiers exist only in this scoring projection.
    struct LabeledInput: Codable {
        let version, sourceSHA256: String
        let sourceRecords, evaluatedRecords, evaluatedWriters, reservedWriterTransformsOrInference: Int
        let codeSHA256, runtimeFilesSHA256: [String: String]
        let runtimeSHA256, encoderIdentity, vocabularySHA256: String
        let profileRevision: UUID
        let profileEnabled: Bool
        let glyphLessonCount, wholeChordLessonCount, parserRuns, wholeChordInferenceRuns: Int
        let rows: [LabeledRow]
    }
    struct LabeledRow: Codable {
        let id: String
        let arm: Replay.Arm
        let expectedTokens, writers: [String]
        let sourceInputSHA256, sourceOwnerGroupsSHA256, automaticGroupsSHA256: String
        let sourceOwnerReadingSHA256, automaticReadingSHA256: String
        let sourceOwnerGroups, automaticGroups: [[Int]]
        let sourceOwnerReading, automaticReading: PersonalInkLearnedComparison.GroupIdentityReading
    }
    struct RouteScore: Codable {
        let originalTop1Tokens: [String?]
        let firstCandidateTokens: [String]?
        let firstCandidateText, legacyGreedyText: String?
        let rawExactOriginalTop1, rawExactFirstCandidate, greedyCanonicalCorrect: Bool
        let fixedFirstOutcome: String
        let pairedOutcome: String?
        let anyRetainedCanonicalCoverage, parserIneligibleFirstHypothesisPresent: Bool
        let exactSourceOwnerPartition, sourceOwnerReadingOrder: Bool
        let canonicalMatchWithWrongPartition, canonicalMatchWithWrongOrder: Bool
        let failure: String?
        let searchComplete, omittedCandidates: Bool?
    }
    struct RowScore: Codable {
        let id: String
        let arm: Replay.Arm
        let expectedTokens, writers: [String]
        let sourceOwnerGroups, automaticGroups: [[Int]]
        let expectedCanonical: String?
        let sourceOwner, automatic: RouteScore
    }
    struct Counts: Codable {
        var allRows = 0, parserEligible = 0, parserIneligible = 0
        var rawExactOriginalTop1 = 0, rawExactFirstCandidate = 0, greedyCanonicalCorrect = 0
        var fixedFirstCorrect = 0, fixedFirstWrong = 0, fixedFirstNoHypothesis = 0
        var pairedGains = 0, pairedHarms = 0, pairedBothCorrect = 0, pairedNeitherCorrect = 0
        var anyRetainedCanonicalCoverage = 0, parserIneligibleFirstHypothesisPresent = 0
        var failures = 0, incompleteSearch = 0, omittedCandidates = 0
        var exactSourceOwnerPartition = 0, sourceOwnerReadingOrder = 0
        var canonicalMatchWithWrongPartition = 0, canonicalMatchWithWrongOrder = 0
        mutating func add(_ score: RouteScore, eligible: Bool) {
            allRows += 1; parserEligible += eligible ? 1 : 0; parserIneligible += eligible ? 0 : 1
            rawExactOriginalTop1 += score.rawExactOriginalTop1 ? 1 : 0
            rawExactFirstCandidate += score.rawExactFirstCandidate ? 1 : 0
            greedyCanonicalCorrect += score.greedyCanonicalCorrect ? 1 : 0
            fixedFirstCorrect += score.fixedFirstOutcome == "correct" ? 1 : 0
            fixedFirstWrong += score.fixedFirstOutcome == "wrong" ? 1 : 0
            fixedFirstNoHypothesis += score.fixedFirstOutcome == "no-hypothesis" ? 1 : 0
            pairedGains += score.pairedOutcome == "gain" ? 1 : 0
            pairedHarms += score.pairedOutcome == "harm" ? 1 : 0
            pairedBothCorrect += score.pairedOutcome == "both-correct" ? 1 : 0
            pairedNeitherCorrect += score.pairedOutcome == "neither-correct" ? 1 : 0
            anyRetainedCanonicalCoverage += score.anyRetainedCanonicalCoverage ? 1 : 0
            parserIneligibleFirstHypothesisPresent += score.parserIneligibleFirstHypothesisPresent ? 1 : 0
            failures += score.failure == nil ? 0 : 1
            incompleteSearch += score.searchComplete == false ? 1 : 0
            omittedCandidates += score.omittedCandidates == true ? 1 : 0
            exactSourceOwnerPartition += score.exactSourceOwnerPartition ? 1 : 0
            sourceOwnerReadingOrder += score.sourceOwnerReadingOrder ? 1 : 0
            canonicalMatchWithWrongPartition += score.canonicalMatchWithWrongPartition ? 1 : 0
            canonicalMatchWithWrongOrder += score.canonicalMatchWithWrongOrder ? 1 : 0
        }
    }
    struct Report: Codable {
        var version = "public-complete-token-score-v1"
        var scope = "Observed public isolated-character and adjacent-character diagnostic; parser eligibility is not real chord intent, product accuracy, fresh writers or personalization. Routes are paired and writers/constructions are correlated. No hypothesis is accepted or rendered."
        var selection = "Fixed first retained candidate; any-retained coverage is separate evidence"
        let inputSHA256, predictionsSHA256: String
        let predictionMetadata: Replay.Metadata
        let totals: [String: Counts]
        let byWriter: [String: [String: Counts]]
        let rows: [RowScore]
    }

    static func validate(_ packet: Replay.Packet, inputData: Data, inputPath: String,
                         sourceFiles: [String: String], requirePublicCounts: Bool) throws -> LabeledInput {
        // Validate the blind source projection and frozen ranks before decoding
        // expected tokens. This scorer never replays or recomposes predictions.
        let blind = try Replay.decodeBlind(inputData)
        if requirePublicCounts {
            guard Replay.digest(inputData) == pinnedInputSHA256 else { throw Failure.binding }
            try Replay.validateProvidedInput(blind)
        }
        let metadata = try Replay.makeMetadata(input: blind, inputPath: inputPath,
            inputSHA256: Replay.digest(inputData), sourceFilesSHA256: sourceFiles)
        guard packet.version == "public-complete-token-predictions-v1", packet.metadata == metadata,
              packet.metadata.composerSourceSHA256 == pinnedComposerSHA256 else { throw Failure.binding }
        guard Set(packet.rows.map(\.id)).count == packet.rows.count,
              Set(blind.rows.map(\.id)).count == blind.rows.count,
              Set(packet.rows.map(\.id)) == Set(blind.rows.map(\.id)) else { throw Failure.rowSet }
        if requirePublicCounts {
            guard packet.rows.count == 3_104,
                  packet.rows.filter({ $0.arm == .isolatedPoints32 }).count == 1_552,
                  packet.rows.filter({ $0.arm == .adjacentSecond32Gap8 }).count == 1_552 else { throw Failure.rowSet }
        }
        let byID = Dictionary(uniqueKeysWithValues: blind.rows.map { ($0.id, $0) })
        for row in packet.rows {
            guard let source = byID[row.id], source.arm == row.arm else { throw Failure.rowSet }
            guard source.sourceOwnerReading.sourceStrokeCount == source.automaticReading.sourceStrokeCount,
                  source.sourceOwnerReading.encoderIdentity == blind.encoderIdentity,
                  source.automaticReading.encoderIdentity == blind.encoderIdentity else { throw Failure.sourceMetadata }
            try validateReading(row.sourceOwner, source: source.sourceOwnerReading)
            try validateReading(row.automatic, source: source.automaticReading)
        }
        let labeled = try JSONDecoder().decode(LabeledInput.self, from: inputData)
        guard Set(labeled.rows.map(\.id)).count == labeled.rows.count,
              Set(labeled.rows.map(\.id)) == Set(packet.rows.map(\.id)) else { throw Failure.rowSet }
        for row in labeled.rows {
            guard let source = byID[row.id], row.arm == source.arm,
                  !row.expectedTokens.isEmpty, row.expectedTokens.count == row.sourceOwnerGroups.count,
                  row.writers.count == row.expectedTokens.count, Set(row.writers).count == 1,
                  isDigest(row.sourceInputSHA256),
                  try legacyDigest(row.sourceOwnerGroups) == row.sourceOwnerGroupsSHA256,
                  try legacyDigest(row.automaticGroups) == row.automaticGroupsSHA256,
                  try legacyDigest(row.sourceOwnerReading) == row.sourceOwnerReadingSHA256,
                  try legacyDigest(row.automaticReading) == row.automaticReadingSHA256,
                  row.sourceOwnerGroups == source.sourceOwnerReading.glyphs.map(\.originalStrokeIndexes),
                  row.automaticGroups == source.automaticReading.glyphs.map(\.originalStrokeIndexes),
                  row.sourceOwnerReading.sourceStrokeCount == source.sourceOwnerReading.sourceStrokeCount,
                  row.automaticReading.sourceStrokeCount == source.automaticReading.sourceStrokeCount,
                  row.sourceOwnerReading.encoderIdentity == source.sourceOwnerReading.encoderIdentity,
                  row.automaticReading.encoderIdentity == source.automaticReading.encoderIdentity,
                  row.sourceOwnerReading.glyphs.map(\.generic) == source.sourceOwnerReading.glyphs.map(\.generic),
                  row.automaticReading.glyphs.map(\.generic) == source.automaticReading.glyphs.map(\.generic) else {
                throw Failure.sourceMetadata
            }
        }
        return labeled
    }

    static func validateReading(_ frozen: Replay.FrozenReading, source: Replay.BlindReading) throws {
        let columns = source.glyphs.map { Composer.Column(originalStrokeIndexes: $0.originalStrokeIndexes, ranks: $0.generic) }
        guard (1...ChordInkFeatureSchema.maximumStrokeCount).contains(source.sourceStrokeCount),
              (1...16).contains(columns.count),
              columns.allSatisfy({ !$0.originalStrokeIndexes.isEmpty && $0.originalStrokeIndexes == $0.originalStrokeIndexes.sorted()
                  && (1...3).contains($0.ranks.count) && $0.ranks.allSatisfy({ $0.score.isFinite }) }),
              columns.flatMap(\.originalStrokeIndexes).sorted() == Array(0..<source.sourceStrokeCount),
              frozen.sourceStrokeCount == source.sourceStrokeCount,
              frozen.encoderIdentity == source.encoderIdentity, frozen.columns == columns,
              frozen.originalTop1Tokens == source.glyphs.map({ $0.generic.first?.label }),
              (frozen.failure == nil) == (frozen.composerResult != nil) else { throw Failure.reading }
        guard let result = frozen.composerResult else {
            guard frozen.failure?.isEmpty == false else { throw Failure.reading }
            return
        }
        guard (1...64).contains(source.sourceStrokeCount), (1...16).contains(columns.count),
              result.version == Composer.version, result.maximumExaminedSequences == 4_096,
              result.tiePolicy == Composer.tiePolicy, result.candidates.count <= 3,
              result.totalSequenceCount == columns.reduce(1, { $0 * $1.ranks.count }),
              result.examinedSequenceCount == min(4_096, result.totalSequenceCount),
              result.searchComplete == (result.examinedSequenceCount == result.totalSequenceCount),
              result.truncated == (!result.searchComplete || result.omittedCandidates),
              (0...result.examinedSequenceCount).contains(result.rejectedCompleteSequenceCount) else { throw Failure.reading }
        for candidate in result.candidates {
            guard candidate.tokens.count == columns.count, candidate.selectedRankIndexes.count == columns.count,
                  candidate.originalStrokeIndexGroups == columns.map({ $0.originalStrokeIndexes.sorted() }) else { throw Failure.reading }
            var rawScore = 0.0
            for index in columns.indices {
                let rankIndex = candidate.selectedRankIndexes[index]
                guard columns[index].ranks.indices.contains(rankIndex),
                      columns[index].ranks[rankIndex].label == candidate.tokens[index] else { throw Failure.reading }
                rawScore += columns[index].ranks[rankIndex].score
            }
            guard rawScore.isFinite, candidate.rawAdditiveScore == rawScore else { throw Failure.reading }
        }
    }

    static func score(_ packet: Replay.Packet, labeled: LabeledInput, predictionSHA256: String) -> Report {
        let byID = Dictionary(uniqueKeysWithValues: labeled.rows.map { ($0.id, $0) })
        var totals: [String: Counts] = [:], writers: [String: [String: Counts]] = [:], rows: [RowScore] = []
        for row in packet.rows {
            let source = byID[row.id]!
            // This is the only parser call in the scoring path: source expected
            // tokens establish a parser-eligible diagnostic subset after freeze.
            let canonical = (try? ChordSymbolParser.parse(source.expectedTokens.joined()))?.displayText
            let owner = route(row.sourceOwner, expected: source.expectedTokens, canonical: canonical, owners: source.sourceOwnerGroups)
            let automatic = route(row.automatic, expected: source.expectedTokens, canonical: canonical, owners: source.sourceOwnerGroups)
            for (name, routeScore) in [("sourceOwner", owner), ("automatic", automatic)] {
                let key = row.arm.rawValue + "/" + name
                totals[key, default: .init()].add(routeScore, eligible: canonical != nil)
                for writer in Set(source.writers) {
                    writers[writer, default: [:]][key, default: .init()].add(routeScore, eligible: canonical != nil)
                }
            }
            rows.append(RowScore(id: row.id, arm: row.arm, expectedTokens: source.expectedTokens,
                writers: source.writers, sourceOwnerGroups: source.sourceOwnerGroups,
                automaticGroups: source.automaticGroups, expectedCanonical: canonical,
                sourceOwner: owner, automatic: automatic))
        }
        return Report(inputSHA256: packet.metadata.inputSHA256, predictionsSHA256: predictionSHA256,
            predictionMetadata: packet.metadata, totals: totals, byWriter: writers, rows: rows)
    }

    static func route(_ reading: Replay.FrozenReading, expected: [String], canonical: String?, owners: [[Int]]) -> RouteScore {
        let first = reading.composerResult?.candidates.first
        let eligible = canonical != nil
        let correct = eligible && first?.text == canonical
        let greedy = eligible && reading.legacyGreedyText == canonical
        let groups = reading.columns.map { $0.originalStrokeIndexes.sorted() }
        let partition = canonicalGroups(groups) == canonicalGroups(owners)
        let order = groups == owners.map { $0.sorted() }
        let pair = eligible ? (correct ? (greedy ? "both-correct" : "gain") : (greedy ? "harm" : "neither-correct")) : nil
        return RouteScore(originalTop1Tokens: reading.originalTop1Tokens, firstCandidateTokens: first?.tokens,
            firstCandidateText: first?.text, legacyGreedyText: reading.legacyGreedyText,
            rawExactOriginalTop1: reading.originalTop1Tokens == expected.map(Optional.some),
            rawExactFirstCandidate: first?.tokens == expected, greedyCanonicalCorrect: greedy,
            fixedFirstOutcome: !eligible ? "parser-ineligible-source" : (first == nil ? "no-hypothesis" : (correct ? "correct" : "wrong")),
            pairedOutcome: pair,
            anyRetainedCanonicalCoverage: eligible && (reading.composerResult?.candidates.contains { $0.text == canonical } ?? false),
            parserIneligibleFirstHypothesisPresent: !eligible && first != nil,
            exactSourceOwnerPartition: partition, sourceOwnerReadingOrder: order,
            canonicalMatchWithWrongPartition: correct && !partition, canonicalMatchWithWrongOrder: correct && !order,
            failure: reading.failure, searchComplete: reading.composerResult?.searchComplete,
            omittedCandidates: reading.composerResult?.omittedCandidates)
    }

    static func canonicalGroups(_ groups: [[Int]]) -> [[Int]] {
        groups.map { $0.sorted() }.sorted { $0.lexicographicallyPrecedes($1) }
    }
    static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func legacyDigest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Replay.digest(try encoder.encode(value))
    }
    static func resolved(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() }
    static func validateOutput(_ output: URL, input: URL, predictions: URL) throws {
        let target = resolved(output.path), source = resolved(input.path), frozen = resolved(predictions.path)
        guard source != frozen, target != source, target != frozen,
              !FileManager.default.fileExists(atPath: target.path) else { throw Failure.output }
    }
    static func save(_ report: Report, at output: URL, input: URL, predictions: URL) throws {
        try validateOutput(output, input: input, predictions: predictions)
        try canonical(report).write(to: output, options: .withoutOverwriting)
    }

    struct Fixture { let data: Data; let path: String; let sources: [String: String]; let packet: Replay.Packet }
    static func fixture(expected: String, ranks labels: [String], candidates: [String],
                        failure: String? = nil, sourceStrokeCount: Int = 1) throws -> Fixture {
        let ranks = labels.enumerated().map { PersonalInkLearnedComparison.Rank(label: $0.element, score: Double(labels.count - $0.offset)) }
        let encoder = "synthetic-generic-public-replay"
        let groups = [Array(0..<sourceStrokeCount)]
        let sourceReading = PersonalInkLearnedComparison.GroupIdentityReading(sourceStrokeCount: sourceStrokeCount,
            encoderIdentity: encoder, glyphs: [.init(originalStrokeIndexes: groups[0], generic: ranks, personal: ranks)], anchoredGlyphRanks: nil)
        let source = LabeledRow(id: "synthetic-row", arm: .isolatedPoints32, expectedTokens: [expected],
            writers: ["synthetic-observed-writer"], sourceInputSHA256: String(repeating: "a", count: 64),
            sourceOwnerGroupsSHA256: try legacyDigest(groups), automaticGroupsSHA256: try legacyDigest(groups),
            sourceOwnerReadingSHA256: try legacyDigest(sourceReading), automaticReadingSHA256: try legacyDigest(sourceReading),
            sourceOwnerGroups: groups, automaticGroups: groups, sourceOwnerReading: sourceReading, automaticReading: sourceReading)
        let runtimeFiles = ["synthetic-runtime": String(repeating: "b", count: 64)]
        let input = LabeledInput(version: "public-conditional-identity-v1", sourceSHA256: String(repeating: "c", count: 64),
            sourceRecords: 1, evaluatedRecords: 1, evaluatedWriters: 1, reservedWriterTransformsOrInference: 0,
            codeSHA256: [:], runtimeFilesSHA256: runtimeFiles, runtimeSHA256: try legacyDigest(runtimeFiles),
            encoderIdentity: encoder, vocabularySHA256: String(repeating: "d", count: 64), profileRevision: UUID(),
            profileEnabled: true, glyphLessonCount: 0, wholeChordLessonCount: 0, parserRuns: 0, wholeChordInferenceRuns: 0, rows: [source])
        let data = try canonical(input), path = "/synthetic/source.json"
        let sources = ["iChart/Recognition/PersonalInkMLChordComposer.swift": pinnedComposerSHA256]
        let metadata = try Replay.makeMetadata(input: Replay.decodeBlind(data), inputPath: path,
            inputSHA256: Replay.digest(data), sourceFilesSHA256: sources)
        let retained = candidates.map { token -> Composer.Candidate in
            let index = labels.firstIndex(of: token)!
            return .init(text: token, tokens: [token], selectedRankIndexes: [index],
                originalStrokeIndexGroups: groups, rawAdditiveScore: ranks[index].score)
        }
        let result = failure == nil ? Composer.Result(version: Composer.version, candidates: retained,
            examinedSequenceCount: labels.count, totalSequenceCount: labels.count, searchComplete: true,
            truncated: false, rejectedCompleteSequenceCount: labels.count - retained.count,
            maximumExaminedSequences: 4_096, assuranceNote: "Synthetic conditional hypotheses only",
            omittedCandidates: false, tiePolicy: Composer.tiePolicy) : nil
        let frozen = Replay.FrozenReading(sourceStrokeCount: sourceStrokeCount, encoderIdentity: encoder,
            columns: [.init(originalStrokeIndexes: groups[0], ranks: ranks)], originalTop1Tokens: [labels.first],
            legacyGreedyText: labels.first, composerResult: result, failure: failure)
        let packet = Replay.Packet(version: "public-complete-token-predictions-v1", metadata: metadata,
            rows: [.init(id: source.id, arm: source.arm, sourceOwner: frozen, automatic: frozen)])
        return Fixture(data: data, path: path, sources: sources, packet: packet)
    }
    static func checkedSyntheticScore(_ fixture: Fixture) throws -> Report {
        let labeled = try validate(fixture.packet, inputData: fixture.data, inputPath: fixture.path,
            sourceFiles: fixture.sources, requirePublicCounts: false)
        return score(fixture.packet, labeled: labeled, predictionSHA256: Replay.digest(try canonical(fixture.packet)))
    }
}

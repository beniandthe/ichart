#if DEBUG && canImport(CoreML)
import CoreML
import CryptoKit
import XCTest
@testable import iChart

/// Bounded component evidence on already-observed public development writers.
/// This is not a recognizer, ownership resolver, fresh-writer gate, or product
/// accuracy claim. Expected text enters only after both readings are frozen.
final class PersonalInkConditionalPublicIdentityTests: XCTestCase {
    func testProvidedPublicConditionalIdentityWithPinnedRuntime() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sourcePath = env["ICHART_PUBLIC_GROUPING_DATASET"],
              let runtimePath = env["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"],
              let reportPath = env["ICHART_PUBLIC_CONDITIONAL_IDENTITY_REPORT"] else {
            throw XCTSkip("Provide the pinned UJI source, PersonalInkVisualEncoder runtime, and append-only report path")
        }
        guard [sourcePath, runtimePath, reportPath].allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { throw PublicGlyphOwnership.Failure.invalidInput }

        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL.resolvingSymlinksInPath()
        let runtimeURL = URL(fileURLWithPath: runtimePath).standardizedFileURL.resolvingSymlinksInPath()
        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL.resolvingSymlinksInPath()
        try ConditionalPublicIdentity.validateOutput(reportURL, source: sourceURL, runtime: runtimeURL)

        let sourceBytes = try Data(contentsOf: sourceURL)
        let runtimeIdentity = try ConditionalPublicIdentity.runtimeIdentity(runtimeURL)
        let codeIdentity = try ConditionalPublicIdentity.codeIdentity()
        guard PublicGlyphOwnership.digest(sourceBytes) == PublicGlyphOwnership.sourceSHA256,
              codeIdentity[ConditionalPublicPairConstructor.retainedSourcePath]
                == ConditionalPublicPairConstructor.retainedSourceSHA256,
              let text = String(data: sourceBytes, encoding: .utf8) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }

        let all = try UJIPersonalRootInput.parse(text)
        let selected = try PublicGlyphOwnership.developmentRecords(all)
        let pairs = try ConditionalPublicPairConstructor.pairs(selected)
        guard selected.count == 1_552, pairs.count == 1_552,
              selected.allSatisfy({ $0.writer.hasPrefix("trn_") }),
              pairs.allSatisfy({ $0.first.writer == $0.second.writer
                  && $0.first.session == $0.second.session }) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }

        var profile = PersonalInkProfile()
        profile.isEnabled = true
        guard profile.examples.isEmpty else { throw PublicGlyphOwnership.Failure.invalidInput }
        let encoder = try PersonalInkVisualEncoder(directory: runtimeURL)
        let sourceVocabulary = Set(selected.map(\.label))
        guard encoder.vocabulary.count == 97, Set(encoder.vocabulary).count == 97,
              Set(encoder.vocabulary) == sourceVocabulary else {
            throw PersonalInkLearnedComparison.Failure.invalidEncoder
        }
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder,
                                                       grouping: .losslessSourceV2)
        guard model.glyphLessonCount == 0, model.wholeChordLessonCount == 0 else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }

        var isolated = ConditionalPublicIdentity.Summary(arm: .isolatedPoints32)
        var adjacent = ConditionalPublicIdentity.Summary(arm: .adjacentSecond32Gap8)
        var rows: [ConditionalPublicIdentity.Row] = []
        rows.reserveCapacity(3_104)

        for sample in selected {
            let strokes = try PublicGlyphOwnership.transform(sample.strokes, arm: .points32)
            let owners = [Array(strokes.indices)]
            let row = try ConditionalPublicIdentity.evaluate(
                arm: .isolatedPoints32, records: [sample], strokes: strokes,
                sourceOwnerGroups: owners, zeroExtentSourceGlyphs:
                    ConditionalPublicIdentity.zeroExtentCount(strokes: strokes, groups: owners),
                model: model, profile: profile)
            isolated.add(row)
            rows.append(row)
        }

        let pairArm = ConditionalPublicPairConstructor.selectedArm
        for pair in pairs {
            let input = try ConditionalPublicPairConstructor.compose(
                pair.first.strokes, pair.second.strokes, arm: pairArm)
            let owners = [Array(0..<input.firstStrokeCount),
                          Array(input.firstStrokeCount..<input.strokes.count)]
            let row = try ConditionalPublicIdentity.evaluate(
                arm: .adjacentSecond32Gap8, records: [pair.first, pair.second],
                strokes: input.strokes, sourceOwnerGroups: owners,
                zeroExtentSourceGlyphs: input.zeroExtentCharacters,
                model: model, profile: profile)
            adjacent.add(row)
            rows.append(row)
        }

        try ConditionalPublicIdentity.validate(isolated: isolated, adjacent: adjacent, rows: rows)
        let report = ConditionalPublicIdentity.Report(
            sourceSHA256: PublicGlyphOwnership.sourceSHA256,
            sourceRecords: all.count,
            evaluatedRecords: selected.count,
            codeSHA256: codeIdentity,
            runtimeFilesSHA256: runtimeIdentity,
            runtimeSHA256: try ConditionalPublicIdentity.digest(runtimeIdentity),
            encoderIdentity: encoder.identity,
            vocabulary: encoder.vocabulary,
            vocabularySHA256: PublicGlyphOwnership.digest(Data(encoder.vocabulary.joined(separator: "\n").utf8)),
            profileRevision: profile.revision,
            summaries: [isolated, adjacent],
            rows: rows)

        guard testRun?.failureCount == 0,
              try Data(contentsOf: sourceURL) == sourceBytes,
              try ConditionalPublicIdentity.runtimeIdentity(runtimeURL) == runtimeIdentity,
              try ConditionalPublicIdentity.codeIdentity() == codeIdentity,
              !FileManager.default.fileExists(atPath: reportURL.path) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let json = JSONEncoder()
        json.outputFormatting = [.prettyPrinted, .sortedKeys]
        try json.encode(report).write(to: reportURL, options: .withoutOverwriting)
        print("PUBLIC_CONDITIONAL_IDENTITY isolated=1552 adjacent=1552 encoder=\(encoder.identity) genericOnly=true parserRuns=0")
    }

    func testCopiedPairConstructorIsHashBoundAndMatchesFrozenGoldens() throws {
        let root = ConditionalPublicIdentity.repositoryRoot()
        let retained = root.appendingPathComponent(ConditionalPublicPairConstructor.retainedSourcePath)
        XCTAssertEqual(PublicGlyphOwnership.digest(try Data(contentsOf: retained)),
                       ConditionalPublicPairConstructor.retainedSourceSHA256)
        XCTAssertEqual(ConditionalPublicPairConstructor.constructorVersion, "public-pair-v1")
        XCTAssertEqual(ConditionalPublicPairConstructor.selectedArm.identity, "second32-gap8.0")
        XCTAssertEqual(ConditionalPublicPairConstructor.firstDimension, 32)
        XCTAssertEqual(ConditionalPublicPairConstructor.bottomAlignment, 32)

        let first = [InkStroke(points: [
            InkPoint(x: -5, y: 2, timeOffset: 0),
            InkPoint(x: -5, y: 2, timeOffset: nil),
            InkPoint(x: 5, y: 7, timeOffset: 0.2)
        ], bounds: InkBounds(minX: -6, minY: 1, maxX: 6, maxY: 8), creationTimeOffset: 3)]
        let second = [InkStroke(points: [InkPoint(x: 1, y: 1), InkPoint(x: 5, y: 5)])]
        let input = try ConditionalPublicPairConstructor.compose(
            first, second, arm: ConditionalPublicPairConstructor.selectedArm)
        XCTAssertEqual(input.firstStrokeCount, 1)
        XCTAssertEqual(input.zeroExtentCharacters, 0)
        XCTAssertEqual(input.strokes.map(\.points), [
            [InkPoint(x: 0, y: 16, timeOffset: 0),
             InkPoint(x: 0, y: 16, timeOffset: nil),
             InkPoint(x: 32, y: 32, timeOffset: 0.2)],
            [InkPoint(x: 40, y: 0), InkPoint(x: 72, y: 32)]
        ])
        XCTAssertEqual(input.strokes[0].bounds,
                       InkBounds(minX: -3.2, minY: 12.8, maxX: 35.2, maxY: 35.2))
        XCTAssertEqual(input.strokes[1].bounds,
                       InkBounds(minX: 40, minY: 0, maxX: 72, maxY: 32))
        XCTAssertEqual(input.strokes[0].creationTimeOffset, 3)
        XCTAssertNil(input.strokes[1].creationTimeOffset)

        let labels = (33..<127).map { String(UnicodeScalar($0)!) } + ["α", "β", "γ"]
        let stroke = InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 1, y: 1)])
        let records = labels.map {
            UJIPersonalRootInput(writer: "trn_UJI_W00", session: 1, label: $0, strokes: [stroke])
        }
        let pairs = try ConditionalPublicPairConstructor.pairs(records)
        XCTAssertEqual(pairs.count, 97)
        XCTAssertEqual(pairs.first?.first.identity, "trn_UJI_W00-1-t")
        XCTAssertEqual(pairs.first?.second.identity, "trn_UJI_W00-1-z")
        XCTAssertEqual(pairs.last?.first.identity, "trn_UJI_W00-1-J")
        XCTAssertEqual(pairs.last?.second.identity, "trn_UJI_W00-1-t")
        XCTAssertEqual(Set(pairs.map { $0.first.identity }), Set(records.map(\.identity)))
        XCTAssertEqual(Set(pairs.map { $0.second.identity }), Set(records.map(\.identity)))
    }

    func testSuppliedPartitionsValidateBeforeEncodingAndPreserveExactOriginalMetadata() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        let encoder = ConditionalIdentityRecordingEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let source = [
            InkStroke(points: [InkPoint(x: 0, y: 0, timeOffset: 0), InkPoint(x: 2, y: 2, timeOffset: 0.1)],
                      bounds: InkBounds(minX: -1, minY: -2, maxX: 3, maxY: 4), creationTimeOffset: 7),
            InkStroke(points: [InkPoint(x: 4, y: 0), InkPoint(x: 6, y: 2)], creationTimeOffset: 8),
            InkStroke(points: [InkPoint(x: 8, y: 0), InkPoint(x: 10, y: 2)], creationTimeOffset: 9)
        ]
        let invalidPartitions: [[[Int]]] = [
            [], [[0], [0, 1, 2]], [[0], [1]], [[0], [], [1, 2]], [[-1], [0, 1, 2]]
        ]
        for invalid in invalidPartitions {
            XCTAssertThrowsError(try model.readSuppliedOriginalGroups(
                source, originalIndexGroups: invalid, currentProfile: profile)) { error in
                Self.expect(error, .invalidInk)
            }
            XCTAssertTrue(encoder.inputs.isEmpty, "An invalid partition must fail before encoding")
        }
        let reading = try model.readSuppliedOriginalGroups(
            source, originalIndexGroups: [[2, 0], [1]], currentProfile: profile)
        XCTAssertEqual(reading.sourceStrokeCount, 3)
        XCTAssertEqual(reading.encoderIdentity, encoder.identity)
        XCTAssertEqual(reading.glyphs.map(\.originalStrokeIndexes), [[0, 2], [1]])
        XCTAssertEqual(encoder.inputs, [[source[0], source[2]], [source[1]]])
        XCTAssertEqual(encoder.inputs[0][0].bounds, source[0].bounds)
        XCTAssertEqual(encoder.inputs[0][0].creationTimeOffset, 7)
        XCTAssertEqual(encoder.inputs[0][0].points.map(\.timeOffset), source[0].points.map(\.timeOffset))
    }

    func testSuppliedReadSharesRankingIsProfileBoundAndNeverRunsWholeChordHead() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        let encoder = ConditionalIdentityRecordingEncoder()
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let source = [
            InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 10, y: 10)]),
            InkStroke(points: [InkPoint(x: 0, y: 10), InkPoint(x: 10, y: 0)])
        ]
        let automatic = PublicGlyphOwnership.group(source, policy: .preserveOriginalInk)
        XCTAssertEqual(automatic.map { $0.originalIndexes.sorted() }, [[0, 1]])
        let legacyBefore = try model.predict(source, currentProfile: profile, grouping: .legacyGeometryV1)
        let losslessBefore = try model.predict(source, currentProfile: profile, grouping: .losslessSourceV2)
        let selectiveBefore = try model.predict(source, currentProfile: profile, grouping: .selectiveLosslessOwnershipV3)
        let supplied = try model.readSuppliedOriginalGroups(
            source, originalIndexGroups: [[1, 0]], currentProfile: profile)
        let legacyAfter = try model.predict(source, currentProfile: profile, grouping: .legacyGeometryV1)
        let losslessAfter = try model.predict(source, currentProfile: profile, grouping: .losslessSourceV2)
        let selectiveAfter = try model.predict(source, currentProfile: profile, grouping: .selectiveLosslessOwnershipV3)
        XCTAssertEqual(supplied.glyphs, losslessBefore.glyphs)
        XCTAssertEqual(legacyBefore, legacyAfter)
        XCTAssertEqual(losslessBefore, losslessAfter)
        XCTAssertEqual(selectiveBefore, selectiveAfter)
        XCTAssertTrue(selectiveBefore.glyphs.isEmpty)
        XCTAssertNotNil(selectiveBefore.ownership)

        var disabled = profile
        disabled.isEnabled = false
        XCTAssertThrowsError(try model.readSuppliedOriginalGroups(
            source, originalIndexGroups: [[0, 1]], currentProfile: disabled)) { error in
            Self.expect(error, .disabled)
        }
        var stale = profile
        stale.revision = UUID()
        XCTAssertThrowsError(try model.readSuppliedOriginalGroups(
            source, originalIndexGroups: [[0, 1]], currentProfile: stale)) { error in
            Self.expect(error, .staleProfile)
        }

        var chordProfile = PersonalInkProfile()
        chordProfile.isEnabled = true
        chordProfile.examples = [
            PersonalInkExample(kind: .chord, label: "C",
                strokes: [InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 0, y: 12)])], source: .practice),
            PersonalInkExample(kind: .chord, label: "D",
                strokes: [InkStroke(points: [InkPoint(x: 20, y: 0), InkPoint(x: 20, y: 12)])], source: .practice)
        ]
        let wholeEncoder = ConditionalIdentityRecordingEncoder()
        let modelWithWholeHead = try PersonalInkLearnedComparison(profile: chordProfile, encoder: wholeEncoder)
        XCTAssertEqual(modelWithWholeHead.wholeChordLessonCount, 2)
        wholeEncoder.inputs.removeAll()
        let twoGroups = chordProfile.examples.flatMap(\.strokes)
        _ = try modelWithWholeHead.readSuppliedOriginalGroups(
            twoGroups, originalIndexGroups: [[1], [0]], currentProfile: chordProfile)
        XCTAssertEqual(wholeEncoder.inputs, [[twoGroups[1]], [twoGroups[0]]],
                       "The supplied-group seam must encode each group once and never encode the whole chord")
    }

    func testTokenSequenceMetricDoesNotConflateOwnership() throws {
        let score = try ConditionalPublicIdentity.score(
            expected: ["A", "B"],
            sourceOwnerGroups: [[0, 2], [1, 3]],
            automaticGroups: [[0, 1], [2, 3]],
            oracleTokens: ["A", "B"],
            automaticTokens: ["A", "B"])
        XCTAssertFalse(score.exactOwnerPartition)
        XCTAssertFalse(score.orderedOwnerCorrespondence)
        XCTAssertTrue(score.automaticIdentity.isEmpty,
                      "No automatic group exactly equals either source owner")
        XCTAssertTrue(score.oracleOrderedTop1Exact)
        XCTAssertTrue(score.automaticOrderedTop1Exact,
                      "Ordered token equality is reported independently from ownership")
        XCTAssertEqual(score.pairedOutcome, .bothCorrect)
    }

    private static func expect(_ error: Error, _ expected: PersonalInkLearnedComparison.Failure,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard let failure = error as? PersonalInkLearnedComparison.Failure else {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
            return
        }
        switch (failure, expected) {
        case (.invalidInk, .invalidInk), (.disabled, .disabled), (.staleProfile, .staleProfile): break
        default: XCTFail("Unexpected failure: \(failure)", file: file, line: line)
        }
    }
}

private enum ConditionalPublicIdentity {
    enum Arm: String, Codable { case isolatedPoints32, adjacentSecond32Gap8 }
    enum PairOutcome: String, Codable { case bothCorrect, oracleOnly, automaticOnly, bothWrong }

    struct AutomaticIdentity: Codable {
        var automaticGroupIndex: Int
        var sourceOwnerIndex: Int
        var expected: String
        var predicted: String
        var correct: Bool
    }

    struct Score {
        var oracleGlyphCorrect: [Bool]
        var automaticIdentity: [AutomaticIdentity]
        var exactOwnerPartition: Bool
        var orderedOwnerCorrespondence: Bool
        var oracleOrderedTop1Exact: Bool
        var automaticOrderedTop1Exact: Bool
        var pairedOutcome: PairOutcome
    }

    struct Row: Codable {
        var id: String
        var arm: Arm
        var sourceIDs: [String]
        var writers: [String]
        var sessions: [Int]
        var sourceInputSHA256: String
        var sourceOwnerGroupsSHA256: String
        var automaticGroupsSHA256: String
        var sourceOwnerReadingSHA256: String
        var automaticReadingSHA256: String
        var sourceOwnerGroups: [[Int]]
        var automaticGroups: [[Int]]
        var sourceOwnerReading: PersonalInkLearnedComparison.GroupIdentityReading
        var automaticReading: PersonalInkLearnedComparison.GroupIdentityReading
        var expectedTokens: [String]
        var oracleTop1Tokens: [String]
        var automaticTop1Tokens: [String]
        var oracleGlyphCorrect: [Bool]
        var automaticIdentity: [AutomaticIdentity]
        var exactOwnerPartition: Bool
        var orderedOwnerCorrespondence: Bool
        var oracleOrderedTop1Exact: Bool
        var automaticOrderedTop1Exact: Bool
        var pairedOutcome: PairOutcome
        var zeroExtentSourceGlyphs: Int
    }

    struct IdentityCounts: Codable {
        var ownerGlyphs = 0
        var oracleTop1Correct = 0
        var automaticIdentityEligible = 0
        var automaticTop1Correct = 0
        mutating func add(oracleCorrect: Bool, automaticCorrect: Bool?) {
            ownerGlyphs += 1
            oracleTop1Correct += oracleCorrect ? 1 : 0
            if let automaticCorrect {
                automaticIdentityEligible += 1
                automaticTop1Correct += automaticCorrect ? 1 : 0
            }
        }
    }

    struct QueryCounts: Codable {
        var queries = 0
        var automaticGroups = 0
        var exactOwnerPartitions = 0
        var orderedOwnerCorrespondences = 0
        var oracleOrderedTop1Exact = 0
        var automaticOrderedTop1Exact = 0
        var bothCorrect = 0
        var oracleOnly = 0
        var automaticOnly = 0
        var bothWrong = 0
        var zeroExtentSourceGlyphs = 0
        mutating func add(_ row: Row) {
            queries += 1
            automaticGroups += row.automaticGroups.count
            exactOwnerPartitions += row.exactOwnerPartition ? 1 : 0
            orderedOwnerCorrespondences += row.orderedOwnerCorrespondence ? 1 : 0
            oracleOrderedTop1Exact += row.oracleOrderedTop1Exact ? 1 : 0
            automaticOrderedTop1Exact += row.automaticOrderedTop1Exact ? 1 : 0
            zeroExtentSourceGlyphs += row.zeroExtentSourceGlyphs
            switch row.pairedOutcome {
            case .bothCorrect: bothCorrect += 1
            case .oracleOnly: oracleOnly += 1
            case .automaticOnly: automaticOnly += 1
            case .bothWrong: bothWrong += 1
            }
        }
    }

    struct WriterCounts: Codable {
        var query = QueryCounts()
        var identity = IdentityCounts()
    }

    struct Summary: Codable {
        var arm: Arm
        var query = QueryCounts()
        var identity = IdentityCounts()
        var byWriter: [String: WriterCounts] = [:]
        var byLabel: [String: IdentityCounts] = [:]

        mutating func add(_ row: Row) {
            query.add(row)
            let writer = row.writers[0]
            var writerCounts = byWriter[writer, default: .init()]
            writerCounts.query.add(row)
            let automaticByOwner = Dictionary(uniqueKeysWithValues:
                row.automaticIdentity.map { ($0.sourceOwnerIndex, $0.correct) })
            for ownerIndex in row.expectedTokens.indices {
                let oracleCorrect = row.oracleGlyphCorrect[ownerIndex]
                let automaticCorrect = automaticByOwner[ownerIndex]
                identity.add(oracleCorrect: oracleCorrect, automaticCorrect: automaticCorrect)
                writerCounts.identity.add(oracleCorrect: oracleCorrect, automaticCorrect: automaticCorrect)
                var labelCounts = byLabel[row.expectedTokens[ownerIndex], default: .init()]
                labelCounts.add(oracleCorrect: oracleCorrect, automaticCorrect: automaticCorrect)
                byLabel[row.expectedTokens[ownerIndex]] = labelCounts
            }
            byWriter[writer] = writerCounts
        }
    }

    struct PairConstructorReceipt: Codable {
        var copiedFrom = ConditionalPublicPairConstructor.retainedSourcePath
        var retainedSourceSHA256 = ConditionalPublicPairConstructor.retainedSourceSHA256
        var version = ConditionalPublicPairConstructor.constructorVersion
        var firstDimension = ConditionalPublicPairConstructor.firstDimension
        var secondDimension = ConditionalPublicPairConstructor.selectedArm.secondDimension
        var gap = ConditionalPublicPairConstructor.selectedArm.gap
        var bottomAlignment = ConditionalPublicPairConstructor.bottomAlignment
    }

    struct Report: Codable {
        var version = "public-conditional-identity-v1"
        var scope = "Observed public development writers; conditional component diagnostic only, not ownership or fresh-writer accuracy"
        var sourceSHA256: String
        var sourceRecords: Int
        var evaluatedRecords: Int
        var evaluatedWriters = 8
        var reservedWritersParsedForStrictSelectionOnly = 20
        var reservedWriterTransformsOrInference = 0
        var labels = 97
        var sessions = [1, 2]
        var codeSHA256: [String: String]
        var runtimeFilesSHA256: [String: String]
        var runtimeSHA256: String
        var encoderIdentity: String
        var vocabulary: [String]
        var vocabularySHA256: String
        var profileRevision: UUID
        var profileEnabled = true
        var glyphLessonCount = 0
        var wholeChordLessonCount = 0
        var primaryIdentityRoute = "generic top-1 only"
        var automaticIdentityEligibility = "Only groups whose source indexes exactly equal one frozen source owner"
        var tokenComparison = "Exact ordered top-1 tokens before parsing"
        var parserRuns = 0
        var wholeChordInferenceRuns = 0
        var pairConstructor = PairConstructorReceipt()
        var summaries: [Summary]
        var rows: [Row]
    }

    static func evaluate(arm: Arm, records: [UJIPersonalRootInput], strokes: [InkStroke],
                         sourceOwnerGroups: [[Int]], zeroExtentSourceGlyphs: Int,
                         model: PersonalInkLearnedComparison, profile: PersonalInkProfile) throws -> Row {
        guard !records.isEmpty, records.count == sourceOwnerGroups.count,
              Set(records.map(\.writer)).count == 1 else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        try validatePartition(sourceOwnerGroups, strokeCount: strokes.count)
        let automaticGroups = PublicGlyphOwnership.group(strokes, policy: .preserveOriginalInk)
            .map { $0.originalIndexes.sorted() }
        try validatePartition(automaticGroups, strokeCount: strokes.count)

        // These two values are frozen before any expected glyph text is read.
        let sourceReading = try model.readSuppliedOriginalGroups(
            strokes, originalIndexGroups: sourceOwnerGroups, currentProfile: profile)
        let automaticReading = try model.readSuppliedOriginalGroups(
            strokes, originalIndexGroups: automaticGroups, currentProfile: profile)
        guard sourceReading.sourceStrokeCount == strokes.count,
              automaticReading.sourceStrokeCount == strokes.count,
              sourceReading.encoderIdentity == model.encoderIdentity,
              automaticReading.encoderIdentity == model.encoderIdentity,
              sourceReading.glyphs.map(\.originalStrokeIndexes) == sourceOwnerGroups,
              automaticReading.glyphs.map(\.originalStrokeIndexes) == automaticGroups,
              sourceReading.glyphs.allSatisfy({ $0.generic.first != nil }),
              automaticReading.glyphs.allSatisfy({ $0.generic.first != nil }) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }

        // Post-inference scoring begins here. Text never flows back into either
        // partition or reading API.
        let expected = records.map(\.label)
        let oracleTokens = sourceReading.glyphs.map { $0.generic[0].label }
        let automaticTokens = automaticReading.glyphs.map { $0.generic[0].label }
        let metrics = try Self.score(expected: expected, sourceOwnerGroups: sourceOwnerGroups,
            automaticGroups: automaticGroups, oracleTokens: oracleTokens,
            automaticTokens: automaticTokens)
        let sourceIDs = records.map(\.identity)
        let idPayload = arm.rawValue + "\n" + sourceIDs.joined(separator: "\n")
        return Row(id: PublicGlyphOwnership.digest(Data(idPayload.utf8)), arm: arm,
            sourceIDs: sourceIDs, writers: records.map(\.writer), sessions: records.map(\.session),
            sourceInputSHA256: try digest(strokes),
            sourceOwnerGroupsSHA256: try digest(sourceOwnerGroups),
            automaticGroupsSHA256: try digest(automaticGroups),
            sourceOwnerReadingSHA256: try digest(sourceReading),
            automaticReadingSHA256: try digest(automaticReading),
            sourceOwnerGroups: sourceOwnerGroups, automaticGroups: automaticGroups,
            sourceOwnerReading: sourceReading, automaticReading: automaticReading,
            expectedTokens: expected, oracleTop1Tokens: oracleTokens,
            automaticTop1Tokens: automaticTokens, oracleGlyphCorrect: metrics.oracleGlyphCorrect,
            automaticIdentity: metrics.automaticIdentity,
            exactOwnerPartition: metrics.exactOwnerPartition,
            orderedOwnerCorrespondence: metrics.orderedOwnerCorrespondence,
            oracleOrderedTop1Exact: metrics.oracleOrderedTop1Exact,
            automaticOrderedTop1Exact: metrics.automaticOrderedTop1Exact,
            pairedOutcome: metrics.pairedOutcome, zeroExtentSourceGlyphs: zeroExtentSourceGlyphs)
    }

    static func score(expected: [String], sourceOwnerGroups: [[Int]], automaticGroups: [[Int]],
                      oracleTokens: [String], automaticTokens: [String]) throws -> Score {
        guard expected.count == sourceOwnerGroups.count,
              oracleTokens.count == sourceOwnerGroups.count,
              automaticTokens.count == automaticGroups.count else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let oracleCorrect = zip(oracleTokens, expected).map { pair in pair.0 == pair.1 }
        let ownerSets = sourceOwnerGroups.map(Set.init)
        var automaticIdentity: [AutomaticIdentity] = []
        for groupIndex in automaticGroups.indices {
            let group = Set(automaticGroups[groupIndex])
            guard let ownerIndex = ownerSets.firstIndex(of: group) else { continue }
            let predicted = automaticTokens[groupIndex]
            automaticIdentity.append(.init(automaticGroupIndex: groupIndex, sourceOwnerIndex: ownerIndex,
                expected: expected[ownerIndex], predicted: predicted,
                correct: predicted == expected[ownerIndex]))
        }
        let exactPartition = canonical(automaticGroups) == canonical(sourceOwnerGroups)
        let orderedOwners = automaticGroups == sourceOwnerGroups
        let oracleSequenceCorrect = oracleTokens == expected
        // Token-sequence equality is a separate observation from ownership.
        // A structurally wrong grouping must not be silently relabeled as an
        // identity miss; ownership remains explicit in the adjacent fields.
        let automaticSequenceCorrect = automaticTokens == expected
        let outcome: PairOutcome
        switch (oracleSequenceCorrect, automaticSequenceCorrect) {
        case (true, true): outcome = .bothCorrect
        case (true, false): outcome = .oracleOnly
        case (false, true): outcome = .automaticOnly
        case (false, false): outcome = .bothWrong
        }
        return Score(oracleGlyphCorrect: oracleCorrect, automaticIdentity: automaticIdentity,
            exactOwnerPartition: exactPartition, orderedOwnerCorrespondence: orderedOwners,
            oracleOrderedTop1Exact: oracleSequenceCorrect,
            automaticOrderedTop1Exact: automaticSequenceCorrect, pairedOutcome: outcome)
    }

    static func validatePartition(_ groups: [[Int]], strokeCount: Int) throws {
        let indexes = groups.flatMap { $0 }
        guard (1...16).contains(groups.count), groups.allSatisfy({ !$0.isEmpty }),
              indexes.count == strokeCount, indexes.allSatisfy({ (0..<strokeCount).contains($0) }),
              Set(indexes).count == strokeCount else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
    }

    static func canonical(_ groups: [[Int]]) -> [[Int]] {
        groups.map { $0.sorted() }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    static func zeroExtentCount(strokes: [InkStroke], groups: [[Int]]) -> Int {
        groups.filter { group in
            let bounds = InkBounds.enclosing(group.flatMap { strokes[$0].points })
            return bounds.width == 0 && bounds.height == 0
        }.count
    }

    static func validate(isolated: Summary, adjacent: Summary, rows: [Row]) throws {
        guard isolated.arm == .isolatedPoints32, adjacent.arm == .adjacentSecond32Gap8,
              rows.count == 3_104, Set(rows.map(\.id)).count == rows.count,
              isolated.query.queries == 1_552, isolated.identity.ownerGlyphs == 1_552,
              isolated.byWriter.count == 8, isolated.byLabel.count == 97,
              isolated.byWriter.values.allSatisfy({ $0.query.queries == 194 && $0.identity.ownerGlyphs == 194 }),
              isolated.byLabel.values.allSatisfy({ $0.ownerGlyphs == 16 }),
              adjacent.query.queries == 1_552, adjacent.identity.ownerGlyphs == 3_104,
              adjacent.byWriter.count == 8, adjacent.byLabel.count == 97,
              adjacent.byWriter.values.allSatisfy({ $0.query.queries == 194 && $0.identity.ownerGlyphs == 388 }),
              adjacent.byLabel.values.allSatisfy({ $0.ownerGlyphs == 32 }),
              rows.allSatisfy({ $0.sourceOwnerReading.encoderIdentity == $0.automaticReading.encoderIdentity }) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
    }

    static func validateOutput(_ report: URL, source: URL, runtime: URL) throws {
        let reportPath = report.path, sourcePath = source.path, runtimePath = runtime.path
        guard report != source, report != runtime,
              !reportPath.hasPrefix(runtimePath + "/"),
              !sourcePath.hasPrefix(reportPath + "/"),
              !runtimePath.hasPrefix(reportPath + "/"),
              !FileManager.default.fileExists(atPath: reportPath) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
    }

    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    static func codeIdentity() throws -> [String: String] {
        let files = [
            "docs/personal-conditional-identity-protocol-2026-09-30.md",
            "iChart/Recognition/ChordInkPersonalization.swift",
            "iChart/Recognition/PersonalInkLearnedComparison.swift",
            "iChart/Recognition/PersonalInkVisualEncoder.swift",
            "iChart/Recognition/PersonalInkResidualHead.swift",
            "iChart/Recognition/PersonalInkAnchoredResidualHead.swift",
            "iChart/Recognition/StrokeClusterer.swift",
            "iChart/Recognition/StrokeClustererSupport.swift",
            "iChart/Recognition/InkTrajectoryTypes.swift",
            "iChart/Recognition/InkTypes.swift",
            "iChart/Recognition/Learned/ChordInkRasterizer.swift",
            "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
            "iChartTests/Recognition/PersonalInkPublicGroupingTests.swift",
            "iChartTests/Recognition/PersonalInkPublicPairGroupingTests.swift",
            "iChartTests/Recognition/PersonalInkPublicRootBenchmarkTests.swift",
            "iChartTests/Recognition/PersonalInkConditionalPublicIdentityTests.swift"
        ]
        let root = repositoryRoot()
        return try Dictionary(uniqueKeysWithValues: files.map { path in
            (path, PublicGlyphOwnership.digest(try Data(contentsOf: root.appendingPathComponent(path))))
        })
    }

    static func runtimeIdentity(_ directory: URL) throws -> [String: String] {
        let rootProperties = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootProperties.isDirectory == true, rootProperties.isSymbolicLink != true,
              let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        var result: [String: String] = [:]
        for case let name as String in enumerator {
            let url = directory.appendingPathComponent(name)
            let properties = try url.resourceValues(forKeys:
                [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isSymbolicLink != true else { throw PublicGlyphOwnership.Failure.invalidInput }
            if properties.isDirectory == true { continue }
            guard properties.isRegularFile == true, (properties.fileSize ?? Int.max) < 4_000_000 else {
                throw PublicGlyphOwnership.Failure.invalidInput
            }
            result[name] = PublicGlyphOwnership.digest(try Data(contentsOf: url))
        }
        guard !result.isEmpty, result.count < 64 else { throw PublicGlyphOwnership.Failure.invalidInput }
        return result
    }

    static func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return PublicGlyphOwnership.digest(try encoder.encode(value))
    }
}

/// Byte-for-byte algorithm copy of the retained file-private constructor.
/// The retained source is never edited and its file hash is a hard gate.
private enum ConditionalPublicPairConstructor {
    static let retainedSourcePath = "iChartTests/Recognition/PersonalInkPublicPairGroupingTests.swift"
    static let retainedSourceSHA256 = "f9ff1c85220f8402559c84e4a70c730693ef344af91086d3c4b78db196cd3162"
    static let constructorVersion = "public-pair-v1"
    static let firstDimension = 32.0
    static let bottomAlignment = 32.0

    struct Arm: Codable {
        var secondDimension: Double
        var gap: Double
        var identity: String { "second\(Int(secondDimension))-gap\(gap)" }
    }
    static let selectedArm = Arm(secondDimension: 32, gap: 8)

    struct Pair {
        var first: UJIPersonalRootInput
        var second: UJIPersonalRootInput
    }

    static func pairs(_ source: [UJIPersonalRootInput]) throws -> [Pair] {
        guard !source.isEmpty, Set(source.map(\.identity)).count == source.count,
              source.allSatisfy({ $0.writer.hasPrefix("trn_") && [1, 2].contains($0.session) }) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let batches = Dictionary(grouping: source) { "\($0.writer)/\($0.session)" }
        guard batches.values.allSatisfy({ $0.count == 97 && Set($0.map(\.label)).count == 97 }) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        return batches.keys.sorted().flatMap { key in
            let ordered = batches[key]!.sorted {
                let lhs = PublicGlyphOwnership.digest(Data(("public-pair-v1:" + $0.identity).utf8))
                let rhs = PublicGlyphOwnership.digest(Data(("public-pair-v1:" + $1.identity).utf8))
                return lhs == rhs ? $0.identity < $1.identity : lhs < rhs
            }
            return ordered.indices.map { Pair(first: ordered[$0], second: ordered[($0 + 1) % ordered.count]) }
        }
    }

    struct Input {
        var strokes: [InkStroke]
        var firstStrokeCount: Int
        var zeroExtentCharacters: Int
    }

    static func affine(_ source: [InkStroke], scale: Double = 1, dx: Double, dy: Double) -> [InkStroke] {
        source.map { stroke in
            var output = stroke
            output.points = stroke.points.map { point in
                var translated = point
                translated.x = point.x * scale + dx
                translated.y = point.y * scale + dy
                return translated
            }
            output.bounds = InkBounds(minX: stroke.bounds.minX * scale + dx,
                minY: stroke.bounds.minY * scale + dy,
                maxX: stroke.bounds.maxX * scale + dx, maxY: stroke.bounds.maxY * scale + dy)
            return output
        }
    }

    static func compose(_ first: [InkStroke], _ second: [InkStroke], arm: Arm) throws -> Input {
        guard [16.0, 32.0].contains(arm.secondDimension), [3.2, 8.0, 16.0].contains(arm.gap) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let normalizedFirst = try PublicGlyphOwnership.transform(first, arm: .points32)
        let second32 = try PublicGlyphOwnership.transform(second, arm: .points32)
        let second32Bounds = InkBounds.enclosing(second32.flatMap(\.points))
        let secondScale = max(second32Bounds.width, second32Bounds.height) > 0 ? arm.secondDimension / 32 : 1
        let normalizedSecond = affine(second32, scale: secondScale, dx: 0, dy: 0)
        let firstBounds = InkBounds.enclosing(normalizedFirst.flatMap(\.points))
        let secondBounds = InkBounds.enclosing(normalizedSecond.flatMap(\.points))
        let left = affine(normalizedFirst, dx: -firstBounds.minX, dy: 32 - firstBounds.maxY)
        let right = affine(normalizedSecond, dx: firstBounds.width + arm.gap - secondBounds.minX,
            dy: 32 - secondBounds.maxY)
        let combinedStrokes: [InkStroke] = left + right
        let zeroExtentCharacters: Int = [firstBounds, secondBounds].reduce(into: 0) { count, bounds in
            if bounds.width == 0 && bounds.height == 0 { count += 1 }
        }
        return Input(strokes: combinedStrokes, firstStrokeCount: left.count,
            zeroExtentCharacters: zeroExtentCharacters)
    }
}

private final class ConditionalIdentityRecordingEncoder: PersonalInkVisualEncoding {
    let identity = "conditional-identity-recording-encoder-v1"
    let vocabulary = (33..<127).map { String(UnicodeScalar($0)!) } + ["α", "β", "γ"]
    let anchorBank: PersonalInkAnchorBank? = nil
    var inputs: [[InkStroke]] = []

    func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
        inputs.append(strokes)
        var embedding = Array(repeating: 0.0, count: 128)
        let marker = Int(abs(strokes.first?.points.first?.x ?? 0).rounded()) % embedding.count
        embedding[marker] = 1
        let logits = vocabulary.indices.map { Double($0) / Double(vocabulary.count) }
        return .init(embedding: embedding, genericLogits: logits)
    }
}
#endif

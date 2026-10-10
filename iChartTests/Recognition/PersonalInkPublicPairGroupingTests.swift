import XCTest
@testable import iChart

/// Fixed synthetic compositions of public development ink, not chord accuracy.
final class PersonalInkPublicPairGroupingTests: XCTestCase {
    func testProvidedPublicDevelopmentAdjacentCharacterOwnership() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sourcePath = env["ICHART_PUBLIC_GROUPING_DATASET"] else {
            throw XCTSkip("Provide the pinned public UJI source for the adjacent-character diagnostic")
        }
        guard !sourcePath.isEmpty, let reportPath = env["ICHART_PUBLIC_PAIR_GROUPING_REPORT"],
              !reportPath.isEmpty else { throw PublicGlyphOwnership.Failure.invalidInput }
        let sourceURL = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath()
        let reportURL = URL(fileURLWithPath: reportPath).resolvingSymlinksInPath()
        guard sourceURL != reportURL, !FileManager.default.fileExists(atPath: reportURL.path) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let bytes = try Data(contentsOf: sourceURL)
        defer {
            do { XCTAssertEqual(try Data(contentsOf: sourceURL), bytes, "Public source changed") }
            catch { XCTFail("Could not verify unchanged public source: \(error)") }
        }
        let code = try PublicPairOwnership.codeIdentity()
        defer {
            do { XCTAssertEqual(try PublicPairOwnership.codeIdentity(), code, "Diagnostic sources changed") }
            catch { XCTFail("Could not verify diagnostic sources: \(error)") }
        }
        guard PublicGlyphOwnership.digest(bytes) == PublicGlyphOwnership.sourceSHA256,
              let text = String(data: bytes, encoding: .utf8) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let all = try UJIPersonalRootInput.parse(text)
        let selected = try PublicGlyphOwnership.developmentRecords(all)
        let pairs = try PublicPairOwnership.pairs(selected)
        var summaries: [String: PublicPairOwnership.Summary] = [:]
        var failures: [PublicPairOwnership.FailedPair] = []
        for pair in pairs {
            for arm in PublicPairOwnership.Arm.all {
                let input = try PublicPairOwnership.compose(pair.first.strokes, pair.second.strokes, arm: arm)
                for policy in PublicGlyphOwnership.Policy.allCases {
                    // No identities, labels or expected owners enter partitioning.
                    let groups = PublicGlyphOwnership.group(input.strokes, policy: policy)
                    let owners = [Array(0..<input.firstStrokeCount),
                        Array(input.firstStrokeCount..<input.strokes.count)]
                    let result = try PublicPairOwnership.score(input.strokes, groups: groups, policy: policy,
                        owners: owners, zeroExtentCharacters: input.zeroExtentCharacters)
                    let key = "\(policy.rawValue)/\(arm.identity)"
                    var summary = summaries[key] ?? .init(policy: policy.rawValue, arm: arm)
                    summary.counts.add(result)
                    summary.byWriter[pair.first.writer, default: .init()].add(result)
                    summaries[key] = summary
                    if !result.exactTwoOwnerMatch || result.source.modelInputMismatchGroups > 0 {
                        failures.append(.init(sourceIDs: [pair.first.identity, pair.second.identity],
                            policy: policy.rawValue, arm: arm.identity, expectedOwners: owners,
                            groupStrokeIndexes: groups.map(\.originalIndexes), result: result))
                    }
                }
            }
        }
        let ordered = summaries.values.sorted {
            ($0.policy, $0.arm.identity) < ($1.policy, $1.arm.identity)
        }
        XCTAssertEqual(pairs.count, 1_552)
        XCTAssertEqual(ordered.count, 12)
        for summary in ordered {
            XCTAssertEqual(summary.counts.pairs, 1_552)
            XCTAssertEqual(summary.byWriter.count, 8)
            XCTAssertTrue(summary.byWriter.values.allSatisfy { $0.pairs == 194 })
        }
        guard testRun?.failureCount == 0, try Data(contentsOf: sourceURL) == bytes,
              try PublicPairOwnership.codeIdentity() == code else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let report = PublicPairOwnership.Report(sourceSHA256: PublicGlyphOwnership.sourceSHA256,
            codeSHA256: code, sourceRecords: all.count, evaluatedRecords: selected.count,
            pairs: pairs.count, summaries: ordered, failedPairs: failures)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: .withoutOverwriting)
        for summary in ordered {
            print("PUBLIC_PAIR_OWNERSHIP policy=\(summary.policy) arm=\(summary.arm.identity) pairs=\(summary.counts.pairs) exact=\(summary.counts.exactTwoOwnerMatches) mergedGroups=\(summary.counts.falseMergedGroups) splitOwners=\(summary.counts.falseSplitOwners)")
        }
    }

    func testPairArmsPreserveGeometryMetadataAndZeroExtentWithoutInventedInk() throws {
        let first = [InkStroke(points: [InkPoint(x: -5, y: 2, timeOffset: 0),
            InkPoint(x: -5, y: 2, timeOffset: nil), InkPoint(x: 5, y: 7, timeOffset: 0.2)],
            bounds: InkBounds(minX: -6, minY: 1, maxX: 6, maxY: 8), creationTimeOffset: 3)]
        let second = [InkStroke(points: [InkPoint(x: 1, y: 1), InkPoint(x: 5, y: 5)])]
        for arm in PublicPairOwnership.Arm.all {
            let input = try PublicPairOwnership.compose(first, second, arm: arm)
            let left = InkBounds.enclosing(input.strokes[0].points)
            let right = InkBounds.enclosing(input.strokes[1].points)
            XCTAssertEqual(input.firstStrokeCount, 1)
            XCTAssertEqual(input.strokes.map { $0.points.count }, [3, 2])
            XCTAssertEqual(max(left.width, left.height), 32, accuracy: 1e-12)
            XCTAssertEqual(max(right.width, right.height), arm.secondDimension, accuracy: 1e-12)
            XCTAssertEqual(right.minX - left.maxX, arm.gap, accuracy: 1e-12)
            XCTAssertEqual(left.maxY, 32, accuracy: 1e-12)
            XCTAssertEqual(right.maxY, 32, accuracy: 1e-12)
            XCTAssertEqual(input.strokes[0].points.map(\.timeOffset), first[0].points.map(\.timeOffset))
            XCTAssertEqual(input.strokes[0].creationTimeOffset, 3)
            XCTAssertNil(input.strokes[1].creationTimeOffset)
            XCTAssertEqual(input.strokes[0].bounds.minX, -3.2, accuracy: 1e-12)
            XCTAssertEqual(input.strokes[0].bounds.maxY, 35.2, accuracy: 1e-12)
            XCTAssertEqual(input.zeroExtentCharacters, 0)
        }
        let dot = [InkStroke(points: [InkPoint(x: 9, y: 9), InkPoint(x: 9, y: 9)])]
        let arm = try XCTUnwrap(PublicPairOwnership.Arm.all.first)
        let input = try PublicPairOwnership.compose(first, dot, arm: arm)
        XCTAssertEqual(input.zeroExtentCharacters, 1)
        XCTAssertEqual(input.strokes[1].points.count, 2)
        XCTAssertEqual(input.strokes[1].points[0], input.strokes[1].points[1])
        XCTAssertEqual(input.strokes[1].points[0].y, 32)
        XCTAssertThrowsError(try PublicPairOwnership.compose([], second, arm: arm))
    }

    func testCorrectGroupCountCannotHideCrossOwnerMergesAndSplits() throws {
        let source = (0..<4).map { InkStroke(points: [InkPoint(x: Double($0), y: 0)]) }
        func groups(_ indexes: [[Int]]) -> [IndexedInkCluster] {
            indexes.map { .init(cluster: InkCluster(strokes: $0.map { source[$0] }), originalIndexes: $0) }
        }
        let owners = [[0, 1], [2, 3]]
        let wrong = try PublicPairOwnership.score(source, groups: groups([[0], [1, 2, 3]]),
            policy: .preserveOriginalInk, owners: owners)
        XCTAssertEqual(wrong.source.groupCount, 2)
        XCTAssertTrue(wrong.source.exactIndexPartition)
        XCTAssertFalse(wrong.exactTwoOwnerMatch)
        XCTAssertEqual(wrong.falseMergedGroups, 1)
        XCTAssertEqual(wrong.falseSplitOwners, 1)
        let correct = try PublicPairOwnership.score(source, groups: groups(owners),
            policy: .preserveOriginalInk, owners: owners)
        XCTAssertTrue(correct.exactTwoOwnerMatch)
        XCTAssertEqual(correct.falseMergedGroups, 0)
        XCTAssertEqual(correct.falseSplitOwners, 0)
        XCTAssertThrowsError(try PublicPairOwnership.score(source, groups: groups(owners),
            policy: .preserveOriginalInk, owners: [[0], [1, 2]]))
    }

    func testCyclicSelectionCoversEveryDevelopmentRecordAndExcludesReservedWriters() throws {
        let writers = (0..<40).map { String(format: "trn_UJI_W%02d", $0) }
            + (0..<20).map { String(format: "tst_UPV_W%02d", $0) }
        let stroke = InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 10, y: 10)])
        let all: [UJIPersonalRootInput] = writers.flatMap { writer in
            [1, 2].flatMap { session in
                (33..<130).map { value in
                    UJIPersonalRootInput(writer: writer, session: session,
                        label: String(UnicodeScalar(value)!), strokes: [stroke])
                }
            }
        }
        let development = try PublicGlyphOwnership.developmentRecords(all)
        let pairs = try PublicPairOwnership.pairs(development)
        XCTAssertEqual(pairs.count, 1_552)
        XCTAssertEqual(Set(pairs.map { $0.first.identity }), Set(development.map(\.identity)))
        XCTAssertEqual(Set(pairs.map { $0.second.identity }), Set(development.map(\.identity)))
        XCTAssertTrue(pairs.allSatisfy {
            $0.first.writer.hasPrefix("trn_") && $0.first.writer == $0.second.writer
                && $0.first.session == $0.second.session && $0.first.identity != $0.second.identity
        })
        let writer = try XCTUnwrap(pairs.first?.first.writer)
        let ordered = development.filter { $0.writer == writer && $0.session == 1 }.sorted {
            PublicGlyphOwnership.digest(Data(("public-pair-v1:" + $0.identity).utf8))
                < PublicGlyphOwnership.digest(Data(("public-pair-v1:" + $1.identity).utf8))
        }
        for index in ordered.indices {
            let pair = try XCTUnwrap(pairs.first { $0.first.identity == ordered[index].identity })
            XCTAssertEqual(pair.second.identity, ordered[(index + 1) % ordered.count].identity)
        }
        XCTAssertThrowsError(try PublicPairOwnership.pairs(all))
    }
}

private enum PublicPairOwnership {
    struct Arm: Codable {
        var secondDimension: Double
        var gap: Double
        var identity: String { "second\(Int(secondDimension))-gap\(gap)" }
        static let all = [16.0, 32.0].flatMap { dimension in
            [3.2, 8.0, 16.0].map { Arm(secondDimension: dimension, gap: $0) }
        }
    }
    struct Pair {
        var first: UJIPersonalRootInput
        var second: UJIPersonalRootInput
    }
    static func codeIdentity() throws -> [String: String] {
        var code = try PublicGlyphOwnership.codeIdentity()
        code["iChartTests/Recognition/PersonalInkPublicPairGroupingTests.swift"] =
            PublicGlyphOwnership.digest(try Data(contentsOf: URL(fileURLWithPath: #filePath)))
        return code
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
        return Input(strokes: left + right, firstStrokeCount: left.count,
            zeroExtentCharacters: [firstBounds, secondBounds].filter { $0.width == 0 && $0.height == 0 }.count)
    }
    struct Result: Codable {
        var source: PublicGlyphOwnership.Result
        var exactTwoOwnerMatch: Bool
        var falseMergedGroups: Int
        var falseSplitOwners: Int
        var zeroExtentCharacters: Int
    }
    static func score(_ source: [InkStroke], groups: [IndexedInkCluster], policy: PublicGlyphOwnership.Policy,
                      owners: [[Int]], zeroExtentCharacters: Int = 0) throws -> Result {
        let indexes = owners.flatMap { $0 }
        guard owners.count == 2, owners.allSatisfy({ !$0.isEmpty }),
              indexes.sorted() == Array(source.indices) else { throw PublicGlyphOwnership.Failure.invalidInput }
        let ownerSets = owners.map { Set($0) }
        let groupedSets = groups.map { Set($0.originalIndexes) }
        let ownership = PublicGlyphOwnership.score(source, groups: groups, policy: policy, expectedGroups: owners)
        return Result(source: ownership, exactTwoOwnerMatch: ownership.matchesExpectedGroups,
            falseMergedGroups: groupedSets.filter { group in
                ownerSets.allSatisfy { !$0.isDisjoint(with: group) }
            }.count,
            falseSplitOwners: ownerSets.filter { owner in
                groupedSets.filter { !$0.isDisjoint(with: owner) }.count > 1
            }.count, zeroExtentCharacters: zeroExtentCharacters)
    }
    struct Counts: Codable {
        var pairs = 0, groupCount = 0, twoGroupCount = 0, exactTwoOwnerMatches = 0
        var falseMergedGroups = 0, falseMergedPairs = 0, falseSplitOwners = 0, falseSplitPairs = 0
        var missingIndexes = 0, duplicateIndexes = 0, invalidIndexes = 0
        var exactIndexPartitions = 0, modelInputMismatchGroups = 0, exactOwnersAndModelInputs = 0
        var zeroExtentCharacters = 0
        mutating func add(_ result: Result) {
            pairs += 1
            groupCount += result.source.groupCount
            twoGroupCount += result.source.groupCount == 2 ? 1 : 0
            exactTwoOwnerMatches += result.exactTwoOwnerMatch ? 1 : 0
            falseMergedGroups += result.falseMergedGroups
            falseMergedPairs += result.falseMergedGroups > 0 ? 1 : 0
            falseSplitOwners += result.falseSplitOwners
            falseSplitPairs += result.falseSplitOwners > 0 ? 1 : 0
            missingIndexes += result.source.missingIndexes
            duplicateIndexes += result.source.duplicateIndexes
            invalidIndexes += result.source.invalidIndexes
            exactIndexPartitions += result.source.exactIndexPartition ? 1 : 0
            modelInputMismatchGroups += result.source.modelInputMismatchGroups
            exactOwnersAndModelInputs += result.exactTwoOwnerMatch && result.source.modelInputMismatchGroups == 0 ? 1 : 0
            zeroExtentCharacters += result.zeroExtentCharacters
        }
    }
    struct Summary: Codable {
        var policy: String
        var arm: Arm
        var counts = Counts()
        var byWriter: [String: Counts] = [:]
    }
    struct FailedPair: Codable {
        var sourceIDs: [String]
        var policy: String
        var arm: String
        var expectedOwners: [[Int]]
        var groupStrokeIndexes: [[Int]]
        var result: Result
    }
    struct Report: Codable {
        var version = "public-adjacent-character-ownership-v1"
        var scope = "Fixed public development compositions; not real-world chords or representative spacing"
        var sourceSHA256: String
        var codeSHA256: [String: String]
        var sourceRecords: Int
        var evaluatedRecords: Int
        var pairs: Int
        var evaluatedWriters = 8
        var reservedWritersNotGroupedOrRasterized = 20
        var firstDimension = 32
        var bottomAlignment = 32
        var zeroExtentNormalization = "Translate only without invented extent; zero-extent characters explicitly counted"
        var rasterChecks = 0
        var classificationAndPersonalizationRuns = 0
        var summaries: [Summary]
        var failedPairs: [FailedPair]
    }
}

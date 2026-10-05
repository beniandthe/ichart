import XCTest
import CryptoKit
@testable import iChart

/// Component measurement only: no classifier, profile, private ink or accuracy gate.
final class PersonalInkPublicGroupingTests: XCTestCase {
    func testProvidedPublicDevelopmentGlyphOwnership() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sourcePath = env["ICHART_PUBLIC_GROUPING_DATASET"] else {
            throw XCTSkip("Provide the pinned public UJI source for the isolated-glyph diagnostic")
        }
        guard !sourcePath.isEmpty, let reportPath = env["ICHART_PUBLIC_GROUPING_REPORT"],
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
        guard PublicGlyphOwnership.digest(bytes) == PublicGlyphOwnership.sourceSHA256,
              let text = String(data: bytes, encoding: .utf8) else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let all = try UJIPersonalRootInput.parse(text)
        let selected = try PublicGlyphOwnership.developmentRecords(all)
        let codeIdentity = try PublicGlyphOwnership.codeIdentity()
        defer {
            do { XCTAssertEqual(try PublicGlyphOwnership.codeIdentity(), codeIdentity, "Diagnostic sources changed") }
            catch { XCTFail("Could not verify diagnostic source identity: \(error)") }
        }
        var summaries: [String: PublicGlyphOwnership.Summary] = [:]
        var failures: [PublicGlyphOwnership.FailedRecord] = []
        for sample in selected {
            for arm in PublicGlyphOwnership.Arm.allCases {
                let source = try PublicGlyphOwnership.transform(sample.strokes, arm: arm)
                // Cache one original raster per record at the declared 32pt arm.
                let sourceRaster = arm == .points32
                    ? try ChordInkRasterizer.rasterize(strokes: source).pixels : nil
                for policy in PublicGlyphOwnership.Policy.allCases {
                    let groups = PublicGlyphOwnership.group(source, policy: policy)
                    var result = PublicGlyphOwnership.score(source, groups: groups, policy: policy)
                    if result.oneCompleteGroup, let sourceRaster {
                        result.rasterChecked = true
                        do {
                            let input = try XCTUnwrap(PublicGlyphOwnership.encoderInput(
                                source, group: groups[0], policy: policy))
                            result.rasterMismatch = try ChordInkRasterizer.rasterize(strokes: input).pixels != sourceRaster
                        } catch {
                            result.rasterEncodingFailed = true
                        }
                    }
                    // The expected character enters reporting only after grouping,
                    // ownership and encoder-input checks have all been fixed.
                    let key = "\(policy.rawValue)/\(arm.rawValue)"
                    var summary = summaries[key] ?? .init(policy: policy.rawValue, arm: arm.rawValue)
                    summary.counts.add(result)
                    summary.byLabel[sample.label, default: .init()].add(result)
                    summary.byWriter[sample.writer, default: .init()].add(result)
                    summaries[key] = summary
                    if !result.oneCompleteGroup || result.modelInputMismatchGroups > 0
                        || result.rasterMismatch || result.rasterEncodingFailed {
                        failures.append(.init(sourceID: sample.identity, policy: policy.rawValue,
                            arm: arm.rawValue, groupStrokeIndexes: groups.map(\.originalIndexes), result: result))
                    }
                }
            }
        }
        let ordered = summaries.values.sorted {
            ($0.policy, $0.arm) < ($1.policy, $1.arm)
        }
        XCTAssertEqual(ordered.count, 8)
        for summary in ordered {
            XCTAssertEqual(summary.counts.records, 1_552)
            XCTAssertEqual(summary.byLabel.count, 97)
            XCTAssertEqual(summary.byWriter.count, 8)
            XCTAssertTrue(summary.byLabel.values.allSatisfy { $0.records == 16 })
            XCTAssertTrue(summary.byWriter.values.allSatisfy { $0.records == 194 })
        }
        guard testRun?.failureCount == 0, try Data(contentsOf: sourceURL) == bytes else {
            throw PublicGlyphOwnership.Failure.invalidInput
        }
        let report = PublicGlyphOwnership.Report(sourceSHA256: PublicGlyphOwnership.sourceSHA256,
            sourceRecords: all.count, evaluatedRecords: selected.count, codeSHA256: codeIdentity,
            summaries: ordered, failedRecords: failures)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: .withoutOverwriting)
        for summary in ordered {
            print("PUBLIC_GLYPH_OWNERSHIP policy=\(summary.policy) arm=\(summary.arm) records=\(summary.counts.records) complete=\(summary.counts.oneCompleteGroup) inputMismatchGroups=\(summary.counts.modelInputMismatchGroups) rasterChecks=\(summary.counts.rasterChecks)")
        }
    }

    func testAffineArmsPreservePointOrderStrokeBoundariesBoundsAndTiming() throws {
        let source = [InkStroke(points: [
            InkPoint(x: -5, y: 2, timeOffset: 0),
            InkPoint(x: -5, y: 2, timeOffset: nil),
            InkPoint(x: 5, y: 7, timeOffset: 0.2)
        ], bounds: InkBounds(minX: -6, minY: 1, maxX: 6, maxY: 8), creationTimeOffset: 3),
            InkStroke(points: [InkPoint(x: 0, y: 4, timeOffset: nil)])]
        XCTAssertEqual(try PublicGlyphOwnership.transform(source, arm: .raw), source)
        for arm in PublicGlyphOwnership.Arm.allCases where arm != .raw {
            let output = try PublicGlyphOwnership.transform(source, arm: arm)
            let dimension = try XCTUnwrap(arm.dimension)
            XCTAssertEqual(output.count, source.count)
            XCTAssertEqual(output.map { $0.points.count }, [3, 1])
            XCTAssertEqual(output[0].points.map(\.timeOffset), source[0].points.map(\.timeOffset))
            XCTAssertEqual(output[0].creationTimeOffset, 3)
            XCTAssertNil(output[1].creationTimeOffset)
            XCTAssertEqual(output[0].points[0].x, 0)
            XCTAssertEqual(output[0].points[2].x, dimension)
            XCTAssertEqual(output[0].points[2].y, dimension / 2)
            XCTAssertEqual(output[0].bounds.minX, -dimension / 10)
            XCTAssertEqual(output[0].bounds.maxY, dimension * 0.6, accuracy: 1e-12)
        }
        XCTAssertThrowsError(try PublicGlyphOwnership.transform([], arm: .points32))
        XCTAssertThrowsError(try PublicGlyphOwnership.transform(
            [InkStroke(points: [InkPoint(x: .nan, y: 0)])], arm: .raw))
        let dot = [InkStroke(points: [InkPoint(x: 7, y: -3), InkPoint(x: 7, y: -3)])]
        let movedDot = try PublicGlyphOwnership.transform(dot, arm: .points32)
        XCTAssertEqual(movedDot[0].points, [InkPoint(x: 0, y: 0), InkPoint(x: 0, y: 0)])
        let dotGroups = PublicGlyphOwnership.group(movedDot, policy: .preserveOriginalInk)
        XCTAssertTrue(PublicGlyphOwnership.score(movedDot, groups: dotGroups, policy: .preserveOriginalInk).zeroExtent)
    }

    func testOwnershipScorerRejectsEqualCountWrongPartitionsAndInvalidIndexes() {
        let source = (0..<4).map { InkStroke(points: [InkPoint(x: Double($0), y: 0)]) }
        func groups(_ indexes: [[Int]]) -> [IndexedInkCluster] {
            indexes.map { .init(cluster: InkCluster(strokes: $0.compactMap {
                source.indices.contains($0) ? source[$0] : nil
            }), originalIndexes: $0) }
        }
        let wrong = PublicGlyphOwnership.score(source, groups: groups([[0], [1, 2, 3]]),
            policy: .preserveOriginalInk, expectedGroups: [[0, 1], [2, 3]])
        XCTAssertTrue(wrong.exactIndexPartition)
        XCTAssertFalse(wrong.matchesExpectedGroups)
        XCTAssertFalse(wrong.oneCompleteGroup)
        let invalid = PublicGlyphOwnership.score(source, groups: groups([[0, 1, 1, 3, 99, -1]]),
            policy: .preserveOriginalInk)
        XCTAssertEqual(invalid.missingIndexes, 1)
        XCTAssertEqual(invalid.duplicateIndexes, 1)
        XCTAssertEqual(invalid.invalidIndexes, 2)
        XCTAssertFalse(invalid.oneCompleteGroup)
        XCTAssertEqual(invalid.modelInputMismatchGroups, 1)
        var altered = groups([[0, 1, 2, 3]])
        altered[0].cluster.strokes[0].bounds.maxX += 1
        let legacy = PublicGlyphOwnership.score(source, groups: altered, policy: .semanticNormalization)
        let lossless = PublicGlyphOwnership.score(source, groups: altered, policy: .preserveOriginalInk)
        XCTAssertTrue(legacy.oneCompleteGroup)
        XCTAssertEqual(legacy.modelInputMismatchGroups, 1)
        XCTAssertEqual(lossless.modelInputMismatchGroups, 0)
    }

    func testPartitionsAndScoringDoNotReceiveExpectedLabels() throws {
        let input = "WORD A trn_UJI_W03-01\nNUMSTROKES 2\nPOINTS 2 # 0 0 10 10\nPOINTS 2 # 0 10 10 0\n"
        let a = try XCTUnwrap(UJIPersonalRootInput.parse(input).first)
        let z = try XCTUnwrap(UJIPersonalRootInput.parse(input.replacingOccurrences(of: "WORD A", with: "WORD z")).first)
        XCTAssertNotEqual(a.label, z.label)
        for policy in PublicGlyphOwnership.Policy.allCases {
            let first = PublicGlyphOwnership.group(a.strokes, policy: policy)
            let second = PublicGlyphOwnership.group(z.strokes, policy: policy)
            XCTAssertEqual(first, second)
            XCTAssertEqual(PublicGlyphOwnership.score(a.strokes, groups: first, policy: policy),
                           PublicGlyphOwnership.score(z.strokes, groups: second, policy: policy))
        }
    }

    func testSharedParserAndHashSelectionKeepReservedWritersOut() throws {
        let writers = (0..<40).map { String(format: "trn_UJI_W%02d", $0) }
            + (0..<20).map { String(format: "tst_UPV_W%02d", $0) }
        let text = writers.map { "WORD A \($0)-01\nNUMSTROKES 1\nPOINTS 2 # 0 0 10 10\n" }.joined()
        let parsed = try UJIPersonalRootInput.parse(text)
        let selected = try PublicGlyphOwnership.developmentWriters(parsed.map(\.writer))
        XCTAssertEqual(selected.count, 8)
        XCTAssertTrue(selected.allSatisfy { $0.hasPrefix("trn_") })
        XCTAssertEqual(selected, try PublicGlyphOwnership.developmentWriters(Array(writers.reversed())))
        let expected = writers.filter { $0.hasPrefix("trn_") }.sorted {
            PublicGlyphOwnership.digest(Data(("personal-encoder-v1:" + $0).utf8))
                < PublicGlyphOwnership.digest(Data(("personal-encoder-v1:" + $1).utf8))
        }
        XCTAssertEqual(selected, Array(expected.prefix(8)))
        XCTAssertThrowsError(try PublicGlyphOwnership.developmentRecords(parsed))
        XCTAssertThrowsError(try UJIPersonalRootInput.parse(text + text))
        XCTAssertThrowsError(try UJIPersonalRootInput.parse(text.replacingOccurrences(of: "POINTS 2 #", with: "POINTS 3 #")))
    }
}

enum PublicGlyphOwnership {
    static let sourceSHA256 = "cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61"
    enum Failure: Error { case invalidInput }
    enum Policy: String, CaseIterable, Codable {
        case semanticNormalization, preserveOriginalInk
    }
    enum Arm: String, CaseIterable {
        case raw, points24, points32, points48
        var dimension: Double? {
            switch self {
            case .raw: return nil
            case .points24: return 24
            case .points32: return 32
            case .points48: return 48
            }
        }
    }
    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func codeIdentity() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let files = ["iChart/Recognition/StrokeClusterer.swift", "iChart/Recognition/StrokeClustererSupport.swift",
            "iChart/Recognition/InkTrajectoryTypes.swift", "iChart/Recognition/InkTypes.swift",
            "iChart/Recognition/Learned/ChordInkRasterizer.swift", "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
            "iChartTests/Recognition/PersonalInkPublicGroupingTests.swift",
            "iChartTests/Recognition/PersonalInkPublicRootBenchmarkTests.swift"]
        return try Dictionary(uniqueKeysWithValues: files.map { path in
            (path, digest(try Data(contentsOf: root.appendingPathComponent(path))))
        })
    }
    static func developmentWriters(_ source: [String]) throws -> [String] {
        let writers = Set(source)
        let training = writers.filter { $0.hasPrefix("trn_") }
        let reserved = writers.filter { $0.hasPrefix("tst_") }
        guard writers.count == 60, training.count == 40, reserved.count == 20 else {
            throw Failure.invalidInput
        }
        return Array(training.sorted {
            let lhs = digest(Data(("personal-encoder-v1:" + $0).utf8))
            let rhs = digest(Data(("personal-encoder-v1:" + $1).utf8))
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }.prefix(8))
    }
    static func developmentRecords(_ all: [UJIPersonalRootInput]) throws -> [UJIPersonalRootInput] {
        let byWriter = Dictionary(grouping: all, by: \.writer)
        let vocabulary = Set(all.map(\.label))
        guard all.count == 11_640, Set(all.map(\.identity)).count == all.count,
              vocabulary.count == 97, byWriter.count == 60,
              byWriter.values.allSatisfy({ samples in
                  samples.count == 194 && [1, 2].allSatisfy { session in
                      Set(samples.filter { $0.session == session }.map(\.label)) == vocabulary
                  }
              }) else { throw Failure.invalidInput }
        let writers = Set(try developmentWriters(Array(byWriter.keys)))
        let selected = all.filter { writers.contains($0.writer) }.sorted { $0.identity < $1.identity }
        guard selected.count == 1_552, selected.allSatisfy({ $0.writer.hasPrefix("trn_") }) else {
            throw Failure.invalidInput
        }
        return selected
    }
    static func transform(_ source: [InkStroke], arm: Arm) throws -> [InkStroke] {
        guard !source.isEmpty, source.allSatisfy({ stroke in
            !stroke.points.isEmpty && stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
                && [stroke.bounds.minX, stroke.bounds.minY, stroke.bounds.maxX, stroke.bounds.maxY].allSatisfy(\.isFinite)
                && stroke.bounds.minX <= stroke.bounds.maxX && stroke.bounds.minY <= stroke.bounds.maxY
        }) else { throw Failure.invalidInput }
        guard let dimension = arm.dimension else { return source }
        let bounds = InkBounds.enclosing(source.flatMap(\.points))
        let span = max(bounds.width, bounds.height)
        guard span.isFinite else { throw Failure.invalidInput }
        // A valid point glyph cannot acquire positive extent without inventing
        // ink. Translate it only; retain it in every denominator and flag it.
        let scale = span > 0 ? dimension / span : 1
        return source.map { stroke in
            var transformed = stroke
            transformed.points = stroke.points.map { point in
                var output = point
                output.x = (point.x - bounds.minX) * scale
                output.y = (point.y - bounds.minY) * scale
                return output
            }
            transformed.bounds = InkBounds(minX: (stroke.bounds.minX - bounds.minX) * scale,
                minY: (stroke.bounds.minY - bounds.minY) * scale,
                maxX: (stroke.bounds.maxX - bounds.minX) * scale,
                maxY: (stroke.bounds.maxY - bounds.minY) * scale)
            return transformed
        }
    }
    static func group(_ strokes: [InkStroke], policy: Policy) -> [IndexedInkCluster] {
        // Same geometry-only grouping as PersonalInkLearnedComparison.predict.
        StrokeClusterer(wrapperPolicy: policy == .preserveOriginalInk
            ? .preserveOriginalInk : .semanticNormalization)
            .indexedClusters(strokes.map { InkStroke(points: $0.points) })
    }
    static func encoderInput(_ source: [InkStroke], group: IndexedInkCluster, policy: Policy) -> [InkStroke]? {
        guard group.originalIndexes.allSatisfy({ source.indices.contains($0) }) else { return nil }
        return policy == .preserveOriginalInk
            ? group.originalIndexes.sorted().map { source[$0] } : group.cluster.strokes
    }
    struct Result: Codable, Equatable {
        var groupCount: Int
        var missingIndexes: Int
        var duplicateIndexes: Int
        var invalidIndexes: Int
        var exactIndexPartition: Bool
        var matchesExpectedGroups: Bool
        var oneCompleteGroup: Bool
        var modelInputMismatchGroups: Int
        var zeroExtent: Bool
        var rasterChecked = false
        var rasterMismatch = false
        var rasterEncodingFailed = false
    }
    static func score(_ source: [InkStroke], groups: [IndexedInkCluster], policy: Policy,
                      expectedGroups: [[Int]]? = nil) -> Result {
        let indexes = groups.flatMap(\.originalIndexes)
        let valid = indexes.filter { source.indices.contains($0) }
        let missing = Set(source.indices).subtracting(valid).count
        let duplicates = valid.count - Set(valid).count
        let invalid = indexes.count - valid.count
        let exact = missing == 0 && duplicates == 0 && invalid == 0
        func canonical(_ partitions: [[Int]]) -> [[Int]] {
            partitions.map { $0.sorted() }.sorted { $0.lexicographicallyPrecedes($1) }
        }
        let expected = expectedGroups ?? [Array(source.indices)]
        let bounds = InkBounds.enclosing(source.flatMap(\.points))
        let mismatches = groups.filter { group in
            guard let actual = encoderInput(source, group: group, policy: policy) else { return true }
            return actual != group.originalIndexes.sorted().map { source[$0] }
        }.count
        return Result(groupCount: groups.count, missingIndexes: missing, duplicateIndexes: duplicates,
            invalidIndexes: invalid, exactIndexPartition: exact,
            matchesExpectedGroups: exact && canonical(groups.map(\.originalIndexes)) == canonical(expected),
            oneCompleteGroup: groups.count == 1 && exact, modelInputMismatchGroups: mismatches,
            zeroExtent: bounds.width == 0 && bounds.height == 0)
    }
    struct Counts: Codable {
        var records = 0, groupCount = 0, oneCompleteGroup = 0, splitRecords = 0, emptyRecords = 0
        var missingIndexes = 0, duplicateIndexes = 0, invalidIndexes = 0
        var exactIndexPartition = 0, modelInputMismatchGroups = 0, completeExactModelInput = 0
        var rasterChecks = 0, rasterMismatches = 0, rasterEncodingFailures = 0
        var zeroExtent = 0
        mutating func add(_ result: Result) {
            records += 1
            groupCount += result.groupCount
            oneCompleteGroup += result.oneCompleteGroup ? 1 : 0
            splitRecords += result.groupCount > 1 ? 1 : 0
            emptyRecords += result.groupCount == 0 ? 1 : 0
            missingIndexes += result.missingIndexes
            duplicateIndexes += result.duplicateIndexes
            invalidIndexes += result.invalidIndexes
            exactIndexPartition += result.exactIndexPartition ? 1 : 0
            modelInputMismatchGroups += result.modelInputMismatchGroups
            zeroExtent += result.zeroExtent ? 1 : 0
            completeExactModelInput += result.oneCompleteGroup && result.modelInputMismatchGroups == 0 ? 1 : 0
            rasterChecks += result.rasterChecked ? 1 : 0
            rasterMismatches += result.rasterMismatch ? 1 : 0
            rasterEncodingFailures += result.rasterEncodingFailed ? 1 : 0
        }
    }
    struct Summary: Codable {
        var policy: String
        var arm: String
        var counts = Counts()
        var byLabel: [String: Counts] = [:]
        var byWriter: [String: Counts] = [:]
    }
    struct FailedRecord: Codable {
        var sourceID: String
        var policy: String
        var arm: String
        var groupStrokeIndexes: [[Int]]
        var result: Result
    }
    struct Report: Codable {
        var version = "public-isolated-glyph-ownership-v1"
        var scope = "Development isolated-character ownership; not classification, adjacent-glyph or product accuracy"
        var sourceSHA256: String
        var sourceRecords: Int
        var evaluatedRecords: Int
        var codeSHA256: [String: String]
        var evaluatedWriters = 8
        var reservedWritersNotGroupedOrRasterized = 20
        var labels = 97
        var sessions = [1, 2]
        var rasterArm = "points32; only complete groups; no classifier inference"
        var rawCoordinateInterpretation = "Source-unit diagnostic, not app-scale geometry"
        var zeroExtentNormalization = "Valid zero-extent glyphs translate to origin with scale1; positive target dimension is not attainable without invented ink"
        var summaries: [Summary]
        var failedRecords: [FailedRecord]
    }
}

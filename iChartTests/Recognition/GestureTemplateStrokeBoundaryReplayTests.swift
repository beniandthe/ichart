import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Comparison-only replay over the previously observed standard ink archive.
///
/// The opt-in freeze decodes only `strokes`. Fixture expectations are joined by
/// a separate host-side scorer after this attachment has been published.
final class GestureTemplateStrokeBoundaryReplayTests: XCTestCase {
    private static let packetVersion = "gesture-template-stroke-boundary-replay-v1"
    private static let attachmentName = "gesture-template-stroke-boundary-replay-v1.json"
    private static let expectedFixtureCount = 660
    private static let expectedSourceInventorySHA256 =
        "d1a7e076a6040619a6ac8a0450c20c89888ff42885fdc2f6b82e38e1e645a874"
    private static let protocolSHA256 =
        "a6251f091e2796f5355f229eb8fb20b57ed4f76eade0f85ae96ec474f3746cd7"

    func testSourceOnlyProjectionIgnoresExpectedGlyphFieldsAndUsesCanonicalInventoryFrame() throws {
        let stroke = InkStroke(points: [
            InkPoint(x: 2, y: 3, timeOffset: 0),
            InkPoint(x: 8, y: 15, timeOffset: 0.1),
            InkPoint(x: 13, y: 4, timeOffset: 0.2)
        ])
        let first = InkFixtureDocument(
            name: "truth-one",
            expectedDisplayText: "C",
            expectedClusterCount: 1,
            expectedTopGlyphs: ["C"],
            strokes: [stroke]
        )
        let second = InkFixtureDocument(
            name: "truth-two",
            expectedDisplayText: "not-a-chord",
            expectedClusterCount: 99,
            expectedTopGlyphs: ["poison", "labels"],
            strokes: [stroke]
        )

        let firstBytes = try Self.canonical(first)
        let secondBytes = try Self.canonical(second)
        XCTAssertNotEqual(Self.sha256(firstBytes), Self.sha256(secondBytes))

        let firstSource = try JSONDecoder().decode(SourceOnlyFixture.self, from: firstBytes)
        let secondSource = try JSONDecoder().decode(SourceOnlyFixture.self, from: secondBytes)
        XCTAssertEqual(firstSource, secondSource)

        let clusters = StrokeClusterer().indexedClusters(firstSource.strokes)
        let secondClusters = StrokeClusterer().indexedClusters(secondSource.strokes)
        XCTAssertEqual(clusters, secondClusters)
        let templates = [GestureTemplate(text: "C", strokes: [stroke])]
        for mode in [GestureTemplateNormalizationMode.legacyJoinedPath, .preserveStrokeBoundaries] {
            var configuration = GestureTemplateRecognizerConfiguration.chordGlyphs
            configuration.normalizationMode = mode
            let recognizer = GestureTemplateRecognizer(configuration: configuration)
            XCTAssertEqual(
                recognizer.rankedCandidates(for: clusters[0].cluster, templates: templates),
                recognizer.rankedCandidates(for: secondClusters[0].cluster, templates: templates)
            )
        }

        let zero = String(repeating: "0", count: 64)
        let one = String(repeating: "1", count: 64)
        let inventory = [
            SourceInventoryEntry(name: "A.json", sha256: zero),
            SourceInventoryEntry(name: "B.json", sha256: one)
        ]
        XCTAssertEqual(
            String(decoding: try Self.canonical(inventory), as: UTF8.self),
            "[{\"name\":\"A.json\",\"sha256\":\"\(zero)\"},{\"name\":\"B.json\",\"sha256\":\"\(one)\"}]"
        )
    }

    func testFreezePairedLegacyAndStrokeBoundaryRanksForStandardArchive() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to freeze the full paired replay."
        )

        // Establish the immutable universe before either recognizer is created.
        let repositoryRoot = Self.repositoryRoot()
        let loadedSources = try Self.loadSourceOnlyFixtures()
        let sourceInventory = loadedSources.map(\.inventory)
        guard sourceInventory.count == Self.expectedFixtureCount,
              Self.sha256(try Self.canonical(sourceInventory)) == Self.expectedSourceInventorySHA256 else {
            throw ReplayFailure.changedFixtureUniverse
        }
        let codeSHA256 = try Self.codeIdentity(repositoryRoot: repositoryRoot)
        guard codeSHA256["docs/gesture-stroke-boundary-comparison-2026-10-03.md"] == Self.protocolSHA256 else {
            throw ReplayFailure.changedProtocol
        }

        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let templateBankSHA256 = try Self.sha256(
            Self.canonical(templates.map { TemplateCommitment(text: $0.text, strokes: $0.strokes) })
        )
        var legacyConfiguration = GestureTemplateRecognizerConfiguration.chordGlyphs
        legacyConfiguration.normalizationMode = .legacyJoinedPath
        var candidateConfiguration = GestureTemplateRecognizerConfiguration.chordGlyphs
        candidateConfiguration.normalizationMode = .preserveStrokeBoundaries
        let legacy = GestureTemplateRecognizer(configuration: legacyConfiguration)
        let candidate = GestureTemplateRecognizer(configuration: candidateConfiguration)
        let clusterer = StrokeClusterer()

        var frozenFixtures: [FrozenFixture] = []
        frozenFixtures.reserveCapacity(loadedSources.count)
        for (sourceOrdinal, loaded) in loadedSources.enumerated() {
            try Self.validateFiniteGeometry(loaded.fixture.strokes)
            let indexedClusters = clusterer.indexedClusters(loaded.fixture.strokes)
            let allOwnedIndexes = indexedClusters.flatMap(\.originalIndexes)
            let frequencies = Dictionary(grouping: allOwnedIndexes, by: { $0 }).mapValues(\.count)
            let outOfRange = frequencies.keys
                .filter { !(0..<loaded.fixture.strokes.count).contains($0) }
                .sorted()
            let duplicates = frequencies
                .filter { $0.value > 1 }
                .map(\.key)
                .sorted()
            guard outOfRange.isEmpty, duplicates.isEmpty else {
                throw ReplayFailure.invalidClusterOwnership(loaded.inventory.name)
            }
            let missing = Array(0..<loaded.fixture.strokes.count)
                .filter { frequencies[$0] == nil }

            let fixtureID = Self.sha256(try Self.canonical(loaded.inventory))
            var frozenClusters: [FrozenCluster] = []
            frozenClusters.reserveCapacity(indexedClusters.count)
            for (clusterIndex, indexedCluster) in indexedClusters.enumerated() {
                let commitment = ClusterCommitment(
                    originalStrokeIndexes: indexedCluster.originalIndexes,
                    strokes: indexedCluster.cluster.strokes,
                    bounds: indexedCluster.cluster.bounds,
                    startTimeOffset: indexedCluster.cluster.startTimeOffset,
                    endTimeOffset: indexedCluster.cluster.endTimeOffset,
                    recognitionHints: indexedCluster.cluster.recognitionHints?.map(\.rawValue).sorted() ?? []
                )
                let clusterSHA256 = Self.sha256(try Self.canonical(commitment))
                let clusterID = Self.sha256(
                    Data("\(fixtureID)|\(clusterIndex)|\(clusterSHA256)".utf8)
                )
                let legacyRanks = try Self.freezeRanks(
                    legacy.rankedCandidates(for: indexedCluster.cluster, templates: templates)
                )
                let candidateRanks = try Self.freezeRanks(
                    candidate.rankedCandidates(for: indexedCluster.cluster, templates: templates)
                )
                frozenClusters.append(FrozenCluster(
                    clusterIndex: clusterIndex,
                    clusterID: clusterID,
                    clusterSHA256: clusterSHA256,
                    originalStrokeIndexes: indexedCluster.originalIndexes,
                    strokeCount: indexedCluster.cluster.strokes.count,
                    pointCount: indexedCluster.cluster.strokes.reduce(0) { $0 + $1.points.count },
                    legacyRanks: legacyRanks,
                    candidateRanks: candidateRanks
                ))
            }

            frozenFixtures.append(FrozenFixture(
                fixtureID: fixtureID,
                sourceOrdinal: sourceOrdinal,
                fixtureFileName: loaded.inventory.name,
                fixtureFileSHA256: loaded.inventory.sha256,
                sourceStrokesSHA256: Self.sha256(try Self.canonical(loaded.fixture.strokes)),
                originalStrokeCount: loaded.fixture.strokes.count,
                actualClusterCount: frozenClusters.count,
                missingOriginalStrokeIndexes: missing,
                duplicateOriginalStrokeIndexes: duplicates,
                outOfRangeOriginalStrokeIndexes: outOfRange,
                clusters: frozenClusters
            ))
        }

        let configuration = GestureConfigurationCommitment(
            samplePointCount: legacyConfiguration.samplePointCount,
            aspectRatioWeight: legacyConfiguration.aspectRatioWeight,
            strokeCountWeight: legacyConfiguration.strokeCountWeight
        )
        let clustererConfiguration = ClustererConfigurationCommitment(
            maxTimeGap: clusterer.configuration.maxTimeGap,
            maxHorizontalGapRatio: clusterer.configuration.maxHorizontalGapRatio,
            maxVerticalOverlapMissRatio: clusterer.configuration.maxVerticalOverlapMissRatio,
            smallModifierSizeRatio: clusterer.configuration.smallModifierSizeRatio,
            wrapperPolicy: "semanticNormalization"
        )
        let packet = Packet(
            version: Self.packetVersion,
            artifactKind: "comparison-only-existing-standard-ink-fixture-replay",
            protocolSHA256: Self.protocolSHA256,
            sourceInventorySHA256: Self.expectedSourceInventorySHA256,
            sourceFixtureCount: loadedSources.count,
            sourceInventory: sourceInventory,
            truthFieldsDecoded: false,
            expectedGlyphsSerialized: false,
            modes: Modes(legacy: "legacyJoinedPath", candidate: "preserveStrokeBoundaries"),
            recognizerConfiguration: configuration,
            clustererConfiguration: clustererConfiguration,
            templateCount: templates.count,
            templateBankSHA256: templateBankSHA256,
            codeSHA256: codeSHA256,
            fixtures: frozenFixtures
        )
        let packetData = try Self.canonical(packet)

        // Recognition must not outlive the exact source/code/template snapshot.
        guard try Self.sourceInventory() == sourceInventory,
              try Self.codeIdentity(repositoryRoot: repositoryRoot) == codeSHA256,
              try Self.sha256(Self.canonical(
                ChordGlyphTemplateLibrary.initialTemplates.map {
                    TemplateCommitment(text: $0.text, strokes: $0.strokes)
                }
              )) == templateBankSHA256,
              testRun?.failureCount == 0 else {
            throw ReplayFailure.changedDuringReplay
        }

        let attachment = XCTAttachment(data: packetData, uniformTypeIdentifier: "public.json")
        attachment.name = Self.attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
        print(
            "GESTURE_STROKE_BOUNDARY_REPLAY fixtures=\(frozenFixtures.count) "
                + "clusters=\(frozenFixtures.reduce(0) { $0 + $1.clusters.count }) "
                + "packetSHA256=\(Self.sha256(packetData)) truthJoins=0"
        )
    }
}

private extension GestureTemplateStrokeBoundaryReplayTests {
    enum ReplayFailure: Error {
        case changedFixtureUniverse
        case changedProtocol
        case invalidGeometry
        case invalidClusterOwnership(String)
        case invalidRanks
        case changedDuringReplay
    }

    struct SourceOnlyFixture: Decodable, Equatable {
        let strokes: [InkStroke]
    }

    struct LoadedSource {
        let inventory: SourceInventoryEntry
        let fixture: SourceOnlyFixture
    }

    struct SourceInventoryEntry: Codable, Equatable {
        let name: String
        let sha256: String
    }

    struct TemplateCommitment: Codable {
        let text: String
        let strokes: [InkStroke]
    }

    struct ClusterCommitment: Codable {
        let originalStrokeIndexes: [Int]
        let strokes: [InkStroke]
        let bounds: InkBounds
        let startTimeOffset: TimeInterval?
        let endTimeOffset: TimeInterval?
        let recognitionHints: [String]
    }

    struct FrozenRank: Codable, Equatable {
        let rank: Int
        let text: String
        let confidence: Double
        let source: String
    }

    struct FrozenCluster: Codable {
        let clusterIndex: Int
        let clusterID: String
        let clusterSHA256: String
        let originalStrokeIndexes: [Int]
        let strokeCount: Int
        let pointCount: Int
        let legacyRanks: [FrozenRank]
        let candidateRanks: [FrozenRank]
    }

    struct FrozenFixture: Codable {
        let fixtureID: String
        let sourceOrdinal: Int
        let fixtureFileName: String
        let fixtureFileSHA256: String
        let sourceStrokesSHA256: String
        let originalStrokeCount: Int
        let actualClusterCount: Int
        let missingOriginalStrokeIndexes: [Int]
        let duplicateOriginalStrokeIndexes: [Int]
        let outOfRangeOriginalStrokeIndexes: [Int]
        let clusters: [FrozenCluster]
    }

    struct Modes: Codable {
        let legacy: String
        let candidate: String
    }

    struct GestureConfigurationCommitment: Codable {
        let samplePointCount: Int
        let aspectRatioWeight: Double
        let strokeCountWeight: Double
    }

    struct ClustererConfigurationCommitment: Codable {
        let maxTimeGap: TimeInterval
        let maxHorizontalGapRatio: Double
        let maxVerticalOverlapMissRatio: Double
        let smallModifierSizeRatio: Double
        let wrapperPolicy: String
    }

    struct Packet: Codable {
        let version: String
        let artifactKind: String
        let protocolSHA256: String
        let sourceInventorySHA256: String
        let sourceFixtureCount: Int
        let sourceInventory: [SourceInventoryEntry]
        let truthFieldsDecoded: Bool
        let expectedGlyphsSerialized: Bool
        let modes: Modes
        let recognizerConfiguration: GestureConfigurationCommitment
        let clustererConfiguration: ClustererConfigurationCommitment
        let templateCount: Int
        let templateBankSHA256: String
        let codeSHA256: [String: String]
        let fixtures: [FrozenFixture]
    }

    static let codePaths = [
        "docs/gesture-stroke-boundary-comparison-2026-10-03.md",
        "iChart/Recognition/ChordGlyphTemplateLibrary.swift",
        "iChart/Recognition/GestureTemplateRecognizer.swift",
        "iChart/Recognition/InkTrajectoryTypes.swift",
        "iChart/Recognition/InkTypes.swift",
        "iChart/Recognition/StrokeClusterer.swift",
        "iChart/Recognition/StrokeClustererSupport.swift",
        "iChart/Shared/ChordNotation/ChordRecognitionDomain.swift",
        "iChartTests/Recognition/GestureTemplateStrokeBoundaryReplayTests.swift"
    ]

    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    static func fixtureDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Ink")
            .standardizedFileURL
    }

    static func fixtureURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: fixtureDirectory(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            guard url.pathExtension == "json" else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        .sorted {
            $0.lastPathComponent.utf8.lexicographicallyPrecedes($1.lastPathComponent.utf8)
        }
    }

    static func loadSourceOnlyFixtures() throws -> [LoadedSource] {
        try fixtureURLs().map { url in
            let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
            return LoadedSource(
                inventory: SourceInventoryEntry(
                    name: url.lastPathComponent,
                    sha256: sha256(bytes)
                ),
                fixture: try JSONDecoder().decode(SourceOnlyFixture.self, from: bytes)
            )
        }
    }

    static func sourceInventory() throws -> [SourceInventoryEntry] {
        try fixtureURLs().map { url in
            SourceInventoryEntry(
                name: url.lastPathComponent,
                sha256: sha256(try Data(contentsOf: url, options: [.mappedIfSafe]))
            )
        }
    }

    static func codeIdentity(repositoryRoot: URL) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: codePaths.map { relativePath in
            let url = repositoryRoot.appendingPathComponent(relativePath)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { throw ReplayFailure.changedDuringReplay }
            return (relativePath, sha256(try Data(contentsOf: url, options: [.mappedIfSafe])))
        })
    }

    static func validateFiniteGeometry(_ strokes: [InkStroke]) throws {
        for stroke in strokes {
            let bounds = stroke.bounds
            guard bounds.minX.isFinite, bounds.minY.isFinite,
                  bounds.maxX.isFinite, bounds.maxY.isFinite,
                  bounds.minX <= bounds.maxX, bounds.minY <= bounds.maxY,
                  stroke.creationTimeOffset?.isFinite != false else {
                throw ReplayFailure.invalidGeometry
            }
            for point in stroke.points {
                guard point.x.isFinite, point.y.isFinite,
                      point.timeOffset?.isFinite != false else {
                    throw ReplayFailure.invalidGeometry
                }
            }
        }
    }

    static func freezeRanks(_ candidates: [GlyphCandidate]) throws -> [FrozenRank] {
        guard candidates.allSatisfy({
            !$0.text.isEmpty && $0.confidence.isFinite
                && (0...1).contains($0.confidence)
                && ChordRecognitionDomain.isAllowedGlyphToken($0.text)
        }), Set(candidates.map(\.text)).count == candidates.count else {
            throw ReplayFailure.invalidRanks
        }
        for pair in zip(candidates, candidates.dropFirst()) {
            guard pair.0.confidence > pair.1.confidence
                    || pair.0.confidence == pair.1.confidence && pair.0.text < pair.1.text else {
                throw ReplayFailure.invalidRanks
            }
        }
        return candidates.enumerated().map { index, candidate in
            FrozenRank(
                rank: index + 1,
                text: candidate.text,
                confidence: candidate.confidence,
                source: candidate.source.rawValue
            )
        }
    }

    static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

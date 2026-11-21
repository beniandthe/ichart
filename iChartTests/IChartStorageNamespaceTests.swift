import Foundation
import XCTest
@testable import iChart

final class IChartStorageNamespaceTests: XCTestCase {
    func testPublicPathsAndAuthKeysRetainTheirExactLocations() {
        let root = URL(fileURLWithPath: "/synthetic/Library/Application Support", isDirectory: true)
        XCTAssertEqual(IChartStorageNamespace.scopedDirectory(root, mode: .publicApp), root)
        for key in ["iChart.supabase.session.v1", "supabase.session", "iChart.pending-auth-flow.v1"] {
            XCTAssertEqual(IChartStorageNamespace.authStorageKey(key, mode: .publicApp), key)
            XCTAssertNotEqual(IChartStorageNamespace.authStorageKey(key, mode: .internalStaging), key)
        }
        if !IChartStorageNamespace.isInternalStaging {
            XCTAssertTrue(IChartStorageNamespace.defaults === UserDefaults.standard)
        }
    }

    func testStagingScopesEveryRootIncludingFallbackTemporaryStorage() {
        let roots = ["/synthetic/Library/Application Support", "/synthetic/Library/Caches", "/synthetic/tmp"]
        for path in roots {
            let root = URL(fileURLWithPath: path, isDirectory: true)
            let staging = IChartStorageNamespace.scopedDirectory(root, mode: .internalStaging)
            XCTAssertEqual(staging.deletingLastPathComponent(), root)
            XCTAssertEqual(staging.lastPathComponent, IChartStorageNamespace.stagingDirectoryName)
            XCTAssertNotEqual(staging, root)
        }
        #if ICHART_STAGING_STOREKIT_PRODUCTS
        XCTAssertTrue(IChartStorageNamespace.isInternalStaging)
        XCTAssertNotEqual(IChartStorageNamespace.defaults, UserDefaults.standard)
        #else
        XCTAssertFalse(IChartStorageNamespace.isInternalStaging)
        #endif
    }

    func testActualLiveResolversScopeFailedSupportAndMissingCachesFallbacks() {
        let root = URL(fileURLWithPath: "/synthetic/fallback", isDirectory: true)
        let manager = IsolationFallbackFileManager(root: root)
        let expected = IChartStorageNamespace.scopedDirectory(root)
        XCTAssertEqual(IChartStorageNamespace.applicationSupportDirectory(fileManager: manager), expected)
        XCTAssertEqual(IChartStorageNamespace.cachesDirectory(fileManager: manager), expected)
        XCTAssertEqual(IChartStorageNamespace.temporaryDirectory(fileManager: manager), expected)
    }

    func testFreshStagingRepositoryDoesNotImportOrRewritePublicChartsInkProjectsOrSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let publicRoot = IChartStorageNamespace.scopedDirectory(root, mode: .publicApp)
        let stagingRoot = IChartStorageNamespace.scopedDirectory(root, mode: .internalStaging)
        let relativeLibrary = "iChart/library-state.json"
        let publicURL = publicRoot.appendingPathComponent(relativeLibrary)
        let stagingURL = stagingRoot.appendingPathComponent(relativeLibrary)
        var chart = Chart.blank(title: "Synthetic public fixture", layoutStyle: .simpleChordSheet)
        chart.pageHandwrittenChordData = Data([1, 4, 9, 16])
        chart.pageHandwrittenNotationData = Data([2, 6, 12])
        chart.freeInkArticulations = [.init(kind: .fermata, sourceInkData: Data([3, 8, 15]))]
        let original = ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id, entitlements: .free,
            projects: [.init(title: "Synthetic project", chartIDs: [chart.id])])
        let publicRepository = FileChartRepository(url: publicURL)
        try publicRepository.saveSnapshot(original)
        let originalBytes = try Data(contentsOf: publicURL)
        let stagingRepository = FileChartRepository(url: stagingURL)
        XCTAssertNil(try stagingRepository.loadSnapshot(), "Staging must begin empty without probing the public library")
        try stagingRepository.saveSnapshot(.empty)
        XCTAssertEqual(try stagingRepository.loadSnapshot(), .empty)
        XCTAssertEqual(try Data(contentsOf: publicURL), originalBytes)
        XCTAssertEqual(try publicRepository.loadSnapshot(), original)
    }

    func testStagingFileWritesAndCleanupLeavePublicPDFFilesSetlistsAndOtherStoresUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = IChartStorageNamespace.scopedDirectory(root, mode: .internalStaging)
        let relativePaths = ["iChart/PDF Library/fixture.pdf", "iChart/PDF Library/pdf-library.json",
                             "iChart/Setlists/pdf-setlists.json", "iChart/chord-ink-correction-memory.json",
                             "iChart/telemetry-queue.jsonl", "PersonalHandwriting/profile-v1.json"]
        let original = Data("original synthetic bytes".utf8)
        for relative in relativePaths {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: url)
            let stagingURL = staging.appendingPathComponent(relative)
            XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
            try FileManager.default.createDirectory(at: stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("QA fixture".utf8).write(to: stagingURL)
        }
        try FileManager.default.removeItem(at: staging)
        for relative in relativePaths {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(relative)), original)
        }
    }
}

private final class IsolationFallbackFileManager: FileManager, @unchecked Sendable {
    private enum Failure: Error { case unavailable }
    private let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    override var temporaryDirectory: URL { root }

    override func url(for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        throw Failure.unavailable
    }

    override func urls(for directory: FileManager.SearchPathDirectory,
                       in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        []
    }
}

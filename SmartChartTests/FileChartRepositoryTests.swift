import XCTest
@testable import SmartChart

final class FileChartRepositoryTests: XCTestCase {
    func testLoadSnapshotReturnsNilWhenFileDoesNotExist() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        XCTAssertNil(try repository.loadSnapshot())
    }

    func testRoundTripsSnapshotToDisk() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )
        let snapshot = ChartLibrarySnapshot(
            charts: ChartSamples.previewCharts,
            selectedChartID: ChartSamples.previewCharts.last?.id,
            entitlements: AppEntitlements(activePlan: .proLifetime)
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try repository.saveSnapshot(snapshot)
        let loadedSnapshot = try XCTUnwrap(repository.loadSnapshot())

        XCTAssertEqual(loadedSnapshot, snapshot)
    }

    func testRoundTripsSnapshotWhenPathContainsSpaces() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )
        let snapshot = ChartLibrarySnapshot(
            charts: [Chart.blank(title: "Chord Writing Test Chart", key: .cMajor)],
            selectedChartID: nil,
            entitlements: AppEntitlements(activePlan: .free)
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory.deletingLastPathComponent())
        }

        try repository.saveSnapshot(snapshot)
        let loadedSnapshot = try XCTUnwrap(repository.loadSnapshot())

        XCTAssertEqual(loadedSnapshot, snapshot)
    }
}

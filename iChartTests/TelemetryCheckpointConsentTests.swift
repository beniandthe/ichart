#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TelemetryCheckpointConsentTests: XCTestCase {
    func testCheckpointAuthorizationAndPublicationStayDisabledWhenConsented() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-no-checkpoint-\(UUID())"))
        defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
        var writes = 0
        let consent = IChartTelemetryConsentStore(defaults: defaults, writeDiagnosticFile: { _, _ in writes += 1 })
        XCTAssertTrue(consent.snapshot.isGranted)
        XCTAssertNil(consent.checkpointAuthorization())
        let authorization = ChartPersistenceDiagnosticAuthorization(identity: "synthetic-only", generation: 0)
        XCTAssertFalse(try consent.publishDiagnosticCheckpoint(Data([1]),
            to: FileManager.default.temporaryDirectory.appendingPathComponent("unused.experience-checkpoint.json"),
            authorization: authorization))
        XCTAssertEqual(writes, 0)
    }

    func testLegacyCheckpointCleanupRunsOffMainAndPreservesSyntheticLibraryBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("basic-checkpoint-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appendingPathComponent("library.json")
        let checkpoint = ChartPersistenceContractDiagnostics.checkpointURL(for: library)
        let fixture = Data([0, 1, 2, 3, 4])
        try fixture.write(to: library)
        try Data([9, 9]).write(to: checkpoint)
        let entered = expectation(description: "utility cleanup entered")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let suiteName = "basic-checkpoint-cleanup-\(UUID())"
        let consent = try await MainActor.run {
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            return IChartTelemetryConsentStore(defaults: defaults, diagnosticFileURLs: [checkpoint], removeDiagnosticFile: { url in
                XCTAssertFalse(Thread.isMainThread)
                entered.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else { throw CocoaError(.fileWriteUnknown) }
                try FileManager.default.removeItem(at: url)
            })
        }
        await fulfillment(of: [entered], timeout: 2)
        let mainReturned = expectation(description: "main remains available while cleanup is held")
        DispatchQueue.main.async { mainReturned.fulfill() }
        await fulfillment(of: [mainReturned], timeout: 1)
        release.signal()
        await consent.waitForPendingPersistence()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.path))
        XCTAssertEqual(try Data(contentsOf: library), fixture)
    }

    func testRegisteringAChartFileCannotTurnItIntoACleanupTarget() async throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-library-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: library) }
        let bytes = Data([4, 3, 2, 1])
        try bytes.write(to: library)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-cleanup-boundary-\(UUID())"))
        let consent = IChartTelemetryConsentStore(defaults: defaults, diagnosticFileURLs: [library])
        consent.registerDiagnosticFile(library)
        consent.retryDiagnosticCleanup()
        await consent.waitForPendingPersistence()
        XCTAssertEqual(try Data(contentsOf: library), bytes)
    }
}
#endif

import Foundation
import XCTest

#if canImport(UIKit)
@testable import iChart

final class TelemetryCheckpointConsentTests: XCTestCase {
    private enum Failure: Error { case cleanup }

    private func temporaryLibrary() throws -> (directory: URL, library: URL, checkpoint: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = directory.appendingPathComponent("library-state.json")
        try Data("private chart and ink bytes".utf8).write(to: library)
        return (directory, library, ChartPersistenceContractDiagnostics.checkpointURL(for: library))
    }

    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "iChart-checkpoint-consent-\(UUID().uuidString)"))
    }

    func testWithdrawalRemovesOnlyCheckpointWithoutConfiguredTelemetryService() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let libraryBefore = try Data(contentsOf: files.library)
        let consent = IChartTelemetryConsentStore(defaults: try defaults(), diagnosticFileURLs: [files.checkpoint])
        consent.setConsentGranted(true)
        let authorization = try XCTUnwrap(consent.checkpointAuthorization())
        XCTAssertTrue(try consent.publishDiagnosticCheckpoint(Data([1, 2, 3]), to: files.checkpoint, authorization: authorization))

        consent.setConsentGranted(false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: files.checkpoint.path))
        XCTAssertEqual(try Data(contentsOf: files.library), libraryBefore)
        XCTAssertNil(consent.checkpointAuthorization())
        XCTAssertFalse(consent.requiresDiagnosticCleanup)
    }

    func testOptedOutStartupRemovesLeftoverCheckpointWithoutNetworkConfiguration() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let libraryBefore = try Data(contentsOf: files.library)
        try Data([1, 2, 3]).write(to: files.checkpoint)

        let consent = IChartTelemetryConsentStore(defaults: try defaults(), diagnosticFileURLs: [files.checkpoint])

        XCTAssertFalse(consent.snapshot.isGranted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.checkpoint.path))
        XCTAssertEqual(try Data(contentsOf: files.library), libraryBefore)
    }

    func testGrantedRelaunchKeepsCheckpointUnderStableInstallationIdentity() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let preferences = try defaults()
        let first = IChartTelemetryConsentStore(defaults: preferences, diagnosticFileURLs: [files.checkpoint])
        first.setConsentGranted(true)
        let authorization = try XCTUnwrap(first.checkpointAuthorization())
        XCTAssertTrue(try first.publishDiagnosticCheckpoint(Data([1]), to: files.checkpoint, authorization: authorization))

        let relaunched = IChartTelemetryConsentStore(defaults: preferences, diagnosticFileURLs: [files.checkpoint])

        XCTAssertEqual(try XCTUnwrap(relaunched.checkpointAuthorization()).identity, authorization.identity)
        XCTAssertEqual(try Data(contentsOf: files.checkpoint), Data([1]))
        XCTAssertFalse(relaunched.requiresDiagnosticCleanup)
    }

    func testBackgroundPayloadCannotBePublishedAfterWithdrawalOrAnotherOptIn() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let consent = IChartTelemetryConsentStore(defaults: try defaults(), diagnosticFileURLs: [files.checkpoint])
        consent.setConsentGranted(true)
        let oldAuthorization = try XCTUnwrap(consent.checkpointAuthorization())

        consent.setConsentGranted(false)
        XCTAssertFalse(try consent.publishDiagnosticCheckpoint(Data([1]), to: files.checkpoint, authorization: oldAuthorization))
        consent.setConsentGranted(true)
        let newAuthorization = try XCTUnwrap(consent.checkpointAuthorization())
        XCTAssertNotEqual(oldAuthorization, newAuthorization)
        XCTAssertFalse(try consent.publishDiagnosticCheckpoint(Data([1]), to: files.checkpoint, authorization: oldAuthorization))
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.checkpoint.path))
        XCTAssertTrue(try consent.publishDiagnosticCheckpoint(Data([2]), to: files.checkpoint, authorization: newAuthorization))
        XCTAssertEqual(try Data(contentsOf: files.checkpoint), Data([2]))
    }

    func testGenerationRejectsOldPayloadEvenIfInstallationIdentifierIsRestored() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let preferences = try defaults()
        let consent = IChartTelemetryConsentStore(defaults: preferences, diagnosticFileURLs: [files.checkpoint])
        consent.setConsentGranted(true)
        let oldAuthorization = try XCTUnwrap(consent.checkpointAuthorization())
        consent.setConsentGranted(false)
        consent.setConsentGranted(true)
        preferences.set(oldAuthorization.identity, forKey: IChartTelemetryConsentStore.installationIDPreferenceKey)

        let restoredIdentityAuthorization = try XCTUnwrap(consent.checkpointAuthorization())

        XCTAssertEqual(oldAuthorization.identity, restoredIdentityAuthorization.identity)
        XCTAssertNotEqual(oldAuthorization.generation, restoredIdentityAuthorization.generation)
        XCTAssertFalse(try consent.publishDiagnosticCheckpoint(Data([1]), to: files.checkpoint, authorization: oldAuthorization))
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.checkpoint.path))
    }

    func testWithdrawalWaitsForAdmittedCheckpointWriteAndThenRemovesIt() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let libraryBefore = try Data(contentsOf: files.library)
        let writerEntered = DispatchSemaphore(value: 0)
        let releaseWriter = DispatchSemaphore(value: 0)
        let publisherFinished = expectation(description: "publisher finished")
        let withdrawalFinished = expectation(description: "withdrawal finished")
        let consent = IChartTelemetryConsentStore(
            defaults: try defaults(), diagnosticFileURLs: [files.checkpoint],
            writeDiagnosticFile: { data, url in
                writerEntered.signal()
                guard releaseWriter.wait(timeout: .now() + 5) == .success else {
                    throw NSError(domain: "CheckpointWriteTimeout", code: 1)
                }
                try data.write(to: url, options: .atomic)
            }
        )
        consent.setConsentGranted(true)
        let authorization = try XCTUnwrap(consent.checkpointAuthorization())
        DispatchQueue.global().async {
            defer { publisherFinished.fulfill() }
            XCTAssertTrue((try? consent.publishDiagnosticCheckpoint(
                Data([1, 2, 3]), to: files.checkpoint, authorization: authorization
            )) == true)
        }
        XCTAssertEqual(writerEntered.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async {
            consent.setConsentGranted(false)
            withdrawalFinished.fulfill()
        }
        releaseWriter.signal()
        wait(for: [publisherFinished, withdrawalFinished], timeout: 5)

        XCTAssertFalse(consent.snapshot.isGranted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.checkpoint.path))
        XCTAssertEqual(try Data(contentsOf: files.library), libraryBefore)
    }

    func testFailedWithdrawalCleanupPersistsAndBlocksPublicationUntilRetrySucceeds() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        var shouldFailCleanup = false
        let preferences = try defaults()
        let consent = IChartTelemetryConsentStore(
            defaults: preferences, diagnosticFileURLs: [files.checkpoint], removeDiagnosticFile: { url in
                if shouldFailCleanup { throw Failure.cleanup }
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        )
        consent.setConsentGranted(true)
        let authorization = try XCTUnwrap(consent.checkpointAuthorization())
        XCTAssertTrue(try consent.publishDiagnosticCheckpoint(Data([1]), to: files.checkpoint, authorization: authorization))
        shouldFailCleanup = true

        consent.setConsentGranted(false)
        consent.setConsentGranted(true)

        XCTAssertTrue(consent.requiresDiagnosticCleanup)
        XCTAssertNil(consent.checkpointAuthorization())
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.checkpoint.path))
        shouldFailCleanup = false
        consent.retryDiagnosticCleanup()
        XCTAssertFalse(consent.requiresDiagnosticCleanup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.checkpoint.path))
        let freshAuthorization = try XCTUnwrap(consent.checkpointAuthorization())
        XCTAssertTrue(try consent.publishDiagnosticCheckpoint(Data([2]), to: files.checkpoint, authorization: freshAuthorization))
    }

    func testFailedCleanupIsRetriedOnNextStoreInitialization() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let preferences = try defaults()
        let first = IChartTelemetryConsentStore(
            defaults: preferences, diagnosticFileURLs: [files.checkpoint], removeDiagnosticFile: { _ in throw Failure.cleanup }
        )
        try Data([1]).write(to: files.checkpoint)
        first.setConsentGranted(false)
        XCTAssertTrue(first.requiresDiagnosticCleanup)

        let relaunched = IChartTelemetryConsentStore(defaults: preferences, diagnosticFileURLs: [files.checkpoint])

        XCTAssertFalse(relaunched.requiresDiagnosticCleanup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.checkpoint.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.library.path))
    }

    func testDirectPreferenceWithdrawalAlsoCleansCheckpointBeforeOldWriterCanPublish() throws {
        let files = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let preferences = try defaults()
        let consent = IChartTelemetryConsentStore(defaults: preferences, diagnosticFileURLs: [files.checkpoint])
        consent.setConsentGranted(true)
        let authorization = try XCTUnwrap(consent.checkpointAuthorization())
        XCTAssertTrue(try consent.publishDiagnosticCheckpoint(Data([1]), to: files.checkpoint, authorization: authorization))

        preferences.removeObject(forKey: IChartTelemetryConsentStore.preferenceKey)

        XCTAssertFalse(try consent.publishDiagnosticCheckpoint(Data([2]), to: files.checkpoint, authorization: authorization))
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.checkpoint.path))
    }
}
#endif

import Foundation
import XCTest
@testable import iChart

final class ChartPersistenceContractDiagnosticsTests: XCTestCase {
    private enum Failure: Error { case save, load }

    private final class Repository: ChartRepository {
        var loaded: ChartLibrarySnapshot?
        var loadError: Error?
        var saveError: Error?
        var loadCount = 0

        func loadSnapshot() throws -> ChartLibrarySnapshot? {
            loadCount += 1
            if let loadError { throw loadError }
            return loaded
        }

        func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {
            if let saveError { throw saveError }
            loaded = snapshot
        }
    }

    private func snapshot(bytes: [UInt8] = [1, 2, 3]) -> ChartLibrarySnapshot {
        var chart = Chart.blank(title: "Private title must never be telemetry", measureCount: 2)
        chart.pageHandwrittenNotationData = Data(bytes)
        return ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id, entitlements: .free)
    }

    func testSummaryCountsAttachmentsAndBytesWithoutTreatingDraftConsumptionAsLoss() {
        var value = snapshot()
        value.charts[0].pageHandwrittenHeaderData = Data([4, 5])
        value.charts[0].systems[0].measures[0].handwrittenRhythmicNotationData = Data([6, 7, 8, 9])
        let summaries = ChartExperienceContractSummary.capture(value)

        XCTAssertEqual(summaries.first { $0.scope == "page" }?.count, 1)
        XCTAssertEqual(summaries.first { $0.scope == "page" }?.bytes, 3)
        XCTAssertEqual(summaries.first { $0.scope == "header" }?.bytes, 2)
        XCTAssertEqual(summaries.first { $0.scope == "rhythm" }?.bytes, 4)
        XCTAssertEqual(summaries.first { $0.scope == "chords" }?.count, 0)
        XCTAssertFalse(summaries.contains { $0.contentDigest.contains(value.charts[0].title) })
    }

    func testSameRevisionSameLengthSourceReplacementIsViolation() {
        let expected = snapshot()
        var actual = expected
        actual.charts[0].pageHandwrittenNotationData = Data([9, 8, 7])
        let check = ChartExperienceContractSummary.checks(
            expected: ChartExperienceContractSummary.capture(expected),
            actual: ChartExperienceContractSummary.capture(actual), operationID: UUID()
        ).first { $0.scope == "page" }

        XCTAssertEqual(check?.outcome, "violated")
        XCTAssertEqual(check?.reason, "reopen_mismatch")
        XCTAssertEqual(check?.expectedBytes, check?.actualBytes)
        XCTAssertEqual(check?.contentMatches, false)
    }

    func testNewerEditedRevisionAndExplicitDeletionAreUnknownInsteadOfLoss() {
        let expected = snapshot()
        var actual = expected
        actual.charts[0].pageHandwrittenNotationData = nil
        actual.charts[0].updatedAt = expected.charts[0].updatedAt.addingTimeInterval(1)
        let editedChecks = ChartExperienceContractSummary.checks(
            expected: ChartExperienceContractSummary.capture(expected),
            actual: ChartExperienceContractSummary.capture(actual), operationID: UUID()
        )
        let deletionChecks = ChartExperienceContractSummary.checks(
            expected: ChartExperienceContractSummary.capture(expected), actual: [], operationID: UUID()
        )

        XCTAssertTrue(editedChecks.allSatisfy { $0.outcome == "unknown" && $0.reason == "baseline_changed" })
        XCTAssertTrue(deletionChecks.allSatisfy { $0.outcome == "unknown" })
        XCTAssertTrue(editedChecks.allSatisfy { $0.contentMatches == nil })
    }

    func testReadbackSamplesPassesButNeverSuppressesObservedSaveFailures() {
        let value = snapshot()
        let repository = Repository()
        repository.loaded = value
        var events: [ChartPersistenceContractCheck] = []
        var now: TimeInterval = 1
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "installation", clock: { now }, isEnabled: { true }, record: { events.append($0) }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)
        now = 2
        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)
        diagnostics.didSave(value, repository: repository, error: Failure.save, durationMilliseconds: 3)

        XCTAssertEqual(repository.loadCount, 1)
        XCTAssertEqual(events.map(\.reason), ["save_completed", "readback_matches", "save_failed"])
        XCTAssertEqual(events.last?.outcome, "violated")
    }

    func testReadbackFailureIsUnknownAndDoesNotTurnSuccessfulSaveIntoDataLoss() {
        let value = snapshot()
        let repository = Repository()
        repository.loadError = Failure.load
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)

        XCTAssertEqual(events.map(\.reason), ["save_completed", "readback_failed"])
        XCTAssertEqual(events.last?.outcome, "unknown")
    }

    func testDifferentValidReadbackRevisionIsUnknown() {
        let value = snapshot()
        var newer = value
        newer.charts[0].updatedAt = value.charts[0].updatedAt.addingTimeInterval(1)
        newer.charts[0].pageHandwrittenNotationData = nil
        let repository = Repository()
        repository.loaded = newer
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)

        XCTAssertEqual(events.last?.outcome, "unknown")
        XCTAssertEqual(events.last?.reason, "baseline_changed")
        XCTAssertNil(events.last?.contentMatches)
    }

    func testOlderDurableReadbackAfterSuccessfulSaveIsViolation() {
        let value = snapshot()
        var older = value
        older.charts[0].updatedAt = value.charts[0].updatedAt.addingTimeInterval(-1)
        older.charts[0].pageHandwrittenNotationData = nil
        let repository = Repository()
        repository.loaded = older
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)

        XCTAssertEqual(events.last?.outcome, "violated")
        XCTAssertEqual(events.last?.reason, "readback_mismatch")
        XCTAssertEqual(events.last?.contentMatches, false)
    }

    func testMissingExpectedChartInDurableReadbackIsViolation() {
        let value = snapshot()
        let repository = Repository()
        repository.loaded = .empty
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)

        XCTAssertEqual(events.last?.outcome, "violated")
        XCTAssertEqual(events.last?.reason, "readback_mismatch")
        XCTAssertEqual(events.last?.expectedCount, 1)
        XCTAssertEqual(events.last?.actualCount, 0)
        XCTAssertEqual(events.last?.contentMatches, false)
    }

    func testMixedOlderAndNewerDurableReadbackIsViolation() {
        var value = snapshot()
        value.charts.append(Chart.blank(title: "Second private chart"))
        var mixed = value
        mixed.charts[0].updatedAt = value.charts[0].updatedAt.addingTimeInterval(-1)
        mixed.charts[1].updatedAt = value.charts[1].updatedAt.addingTimeInterval(1)
        let repository = Repository()
        repository.loaded = mixed
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)

        XCTAssertEqual(events.last?.outcome, "violated")
        XCTAssertEqual(events.last?.reason, "readback_mismatch")
        XCTAssertEqual(events.last?.contentMatches, false)
    }

    func testNoConsentProducesNoEventsReadbackOrCheckpoint() {
        let value = snapshot()
        let repository = Repository()
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "installation", isEnabled: { false }, record: { events.append($0) }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)
        diagnostics.didLoad(value, error: nil, durationMilliseconds: 3)

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(repository.loadCount, 0)
    }

    func testConsentIdentityChangeDuringReadbackDropsOldObservation() {
        let value = snapshot()
        let repository = Repository()
        repository.loaded = value
        var identity = "first-opt-in"
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "unused", currentIdentity: { identity }, isEnabled: { true }, record: {
                events.append($0)
                if $0.reason == "save_completed" { identity = "second-opt-in" }
            }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)

        XCTAssertEqual(events.map(\.reason), ["save_completed"])
    }

    func testConsentGenerationChangeWithSameIdentityRejectsOldBackgroundOperation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        let value = snapshot()
        try repository.saveSnapshot(value)
        let libraryBytes = try Data(contentsOf: repository.url)
        var authorization = ChartPersistenceDiagnosticAuthorization(identity: "same-installation", generation: 1)
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            fileURL: repository.url, identity: "unused", currentAuthorization: { authorization },
            isEnabled: { true }, record: {
                events.append($0)
                if $0.reason == "readback_matches" { authorization.generation = 2 }
            }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)

        XCTAssertEqual(events.map(\.reason), ["save_completed", "readback_matches"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ChartPersistenceContractDiagnostics.checkpointURL(for: repository.url).path
        ))
        XCTAssertEqual(try Data(contentsOf: repository.url), libraryBytes)
    }

    func testAppCheckpointPublisherReceivesCapturedAuthorizationAndEncodedPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        let value = snapshot()
        try repository.saveSnapshot(value)
        let authorization = ChartPersistenceDiagnosticAuthorization(identity: "installation", generation: 7)
        var published: ChartPersistenceContractDiagnostics.Checkpoint?
        let diagnostics = ChartPersistenceContractDiagnostics(
            fileURL: repository.url, identity: "unused", currentAuthorization: { authorization },
            publishCheckpoint: { data, url, suppliedAuthorization in
                XCTAssertEqual(suppliedAuthorization, authorization)
                XCTAssertEqual(url, ChartPersistenceContractDiagnostics.checkpointURL(for: repository.url))
                published = try JSONDecoder().decode(ChartPersistenceContractDiagnostics.Checkpoint.self, from: data)
                return false
            }, isEnabled: { true }, record: { _ in }
        )

        diagnostics.didSave(value, repository: repository, error: nil, durationMilliseconds: 3)

        XCTAssertEqual(published?.identity, authorization.identity)
        XCTAssertEqual(published?.chartCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ChartPersistenceContractDiagnostics.checkpointURL(for: repository.url).path
        ), "The portable helper must not bypass a rejecting app publisher")
    }

    func testCheckpointDetectsSameRevisionLossAfterDiskFileChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        let expected = snapshot()
        try repository.saveSnapshot(expected)
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            fileURL: repository.url, identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )
        diagnostics.didSave(expected, repository: repository, error: nil, durationMilliseconds: 3)
        XCTAssertTrue(events.contains { $0.reason == "readback_matches" })
        events.removeAll()

        var damaged = expected
        damaged.charts[0].pageHandwrittenNotationData = nil
        try repository.saveSnapshot(damaged)
        let reopened = try repository.loadSnapshot()
        diagnostics.didLoad(reopened, error: nil, durationMilliseconds: 3)

        XCTAssertTrue(events.contains { $0.scope == "page" && $0.outcome == "violated" && $0.reason == "reopen_mismatch" })
        XCTAssertTrue(events.contains { $0.scope == "library" && $0.reason == "baseline_changed" })
    }

    func testStaleCheckpointAfterNewerSuccessfulSaveDoesNotReportLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        let expected = snapshot()
        try repository.saveSnapshot(expected)
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            fileURL: repository.url, identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )
        diagnostics.didSave(expected, repository: repository, error: nil, durationMilliseconds: 3)
        var edited = expected
        edited.charts[0].updatedAt = expected.charts[0].updatedAt.addingTimeInterval(1)
        edited.charts[0].pageHandwrittenNotationData = nil
        try repository.saveSnapshot(edited)
        events.removeAll()
        diagnostics.didLoad(try repository.loadSnapshot(), error: nil, durationMilliseconds: 3)

        XCTAssertFalse(events.contains { $0.outcome == "violated" })
        XCTAssertTrue(events.contains { $0.reason == "baseline_changed" })
    }

    func testMissingLibraryAfterKnownSuccessfulSaveIsNotFirstLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        let expected = snapshot()
        try repository.saveSnapshot(expected)
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            fileURL: repository.url, identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )
        diagnostics.didSave(expected, repository: repository, error: nil, durationMilliseconds: 3)
        try FileManager.default.removeItem(at: repository.url)
        events.removeAll()

        diagnostics.didLoad(try repository.loadSnapshot(), error: nil, durationMilliseconds: 3)

        let check = try XCTUnwrap(events.first { $0.contractID == "chart.load" })
        XCTAssertEqual(check.outcome, "violated")
        XCTAssertEqual(check.reason, "load_failed")
        XCTAssertEqual(check.expectedCount, 1)
        XCTAssertEqual(check.actualCount, 0)
        XCTAssertEqual(check.contentMatches, false)
        XCTAssertFalse(events.contains { $0.reason == "first_launch" })
    }

    func testMissingLibraryWithoutCheckpointIsLegitimateFirstLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            fileURL: repository.url, identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )

        diagnostics.didLoad(try repository.loadSnapshot(), error: nil, durationMilliseconds: 3)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.reason, "first_launch")
        XCTAssertEqual(events.first?.outcome, "passed")
    }

    func testCheckpointFromDifferentConsentIdentityDoesNotDiagnoseMissingLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        let expected = snapshot()
        try repository.saveSnapshot(expected)
        let priorDiagnostics = ChartPersistenceContractDiagnostics(
            fileURL: repository.url, identity: "previous-opt-in", isEnabled: { true }, record: { _ in }
        )
        priorDiagnostics.didSave(expected, repository: repository, error: nil, durationMilliseconds: 3)
        try FileManager.default.removeItem(at: repository.url)
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            fileURL: repository.url, identity: "new-opt-in", isEnabled: { true }, record: { events.append($0) }
        )

        diagnostics.didLoad(try repository.loadSnapshot(), error: nil, durationMilliseconds: 3)

        XCTAssertFalse(events.contains { $0.outcome == "violated" })
        XCTAssertEqual(events.first?.reason, "first_launch")
    }

    func testActualSynchronousSaveFailureRecordsWithoutChangingLibraryBehavior() {
        let repository = Repository()
        repository.saveError = Failure.save
        var events: [ChartPersistenceContractCheck] = []
        let diagnostics = ChartPersistenceContractDiagnostics(
            identity: "installation", isEnabled: { true }, record: { events.append($0) }
        )
        let value = snapshot()
        let store = ChartLibraryStore(
            charts: value.charts, repository: repository, persistenceDiagnostics: diagnostics
        )

        store.selectedChartID = value.charts[0].id

        XCTAssertEqual(events.last?.reason, "save_failed")
        XCTAssertEqual(store.charts, value.charts)
        guard case .failed = store.persistenceStatus else { return XCTFail("Save failure must remain visible") }
    }
}

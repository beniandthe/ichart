#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TelemetryColdLaunchTests: XCTestCase {
    override func tearDown() {
        IChartTelemetry.configure(nil)
        super.tearDown()
    }

    func testColdLoadPreservesSyntheticChartAndInkWithoutTelemetryOrCheckpoints() throws {
        IChartTelemetry.configure(nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        var chart = Chart.blank(title: "Synthetic cold load fixture")
        chart.pageHandwrittenNotationData = Data([1, 2, 3, 4])
        let snapshot = ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id, entitlements: .free)
        try repository.saveSnapshot(snapshot)
        let libraryBefore = try Data(contentsOf: repository.url)

        let loaded = ChartLibraryStore.live(repository: repository)

        XCTAssertEqual(loaded.charts, snapshot.charts)
        XCTAssertEqual(loaded.selectedChartID, chart.id)
        XCTAssertEqual(loaded.initialLoadOutcome?.succeeded, true)
        XCTAssertEqual(try Data(contentsOf: repository.url), libraryBefore)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["library.json"],
            "Loading must not create chart fingerprints, diagnostic checkpoints, or ink readbacks")
    }

    func testStartupLoadFailureCanBeReportedAfterOptionalTelemetryInitializationUsingOnlyScalars() async throws {
        IChartTelemetry.configure(nil)
        let repository = TelemetryColdLaunchFailingRepository()
        let loaded = ChartLibraryStore.live(repository: repository)
        let outcome = try XCTUnwrap(loaded.initialLoadOutcome)
        XCTAssertFalse(outcome.succeeded)
        XCTAssertGreaterThanOrEqual(outcome.durationMilliseconds, 0)
        guard case .failed = loaded.persistenceStatus else {
            return XCTFail("A real library read failure must remain visible independently of telemetry")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-cold-load-\(UUID())"))
        let installationID = UUID()
        defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
        defaults.set(installationID.uuidString, forKey: IChartTelemetryConsentStore.installationIDPreferenceKey)
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        // This case exercises reporting for an already-consented installation.
        // Creating its first identity during the event would introduce a
        // preference-projection transition into best-effort admission instead.
        await consent.waitForPendingPersistence()
        XCTAssertEqual(consent.installationID(for: consent.snapshot), installationID)
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("telemetry.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryColdLaunchOfflineProtocol.self]
        let appended = expectation(description: "fixed load failure admitted after deferred startup")
        let recordingStages = TelemetryColdLaunchRecordingStages()
        let service = IChartTelemetryService(
            endpointURL: URL(string: "https://telemetry.invalid/ingest")!, publishableKey: "test",
            sessionStore: nil, queueStore: queue, consentStore: consent,
            urlSession: URLSession(configuration: configuration),
            recordingObserver: { trace in
                recordingStages.record(trace)
                if trace.stage == .queueAppended && trace.eventName == "app.error" { appended.fulfill() }
            }
        )
        IChartTelemetry.configure(service)
        await service.initialize()

        ChartLibraryStore.recordBasicLoadOutcome(outcome)

        await fulfillment(of: [appended], timeout: 2)
        let events = try queue.loadEvents()
        let event = try XCTUnwrap(events.first, recordingStages.failureDescription)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.eventName, "app.error")
        XCTAssertEqual(event.installationID, installationID)
        XCTAssertEqual(event.properties["source"], .string("library_load"))
        XCTAssertEqual(event.properties["result"], .string("failed"))
        XCTAssertEqual(event.properties["error_code"], .string("library_load_failed"))
        XCTAssertEqual(event.properties["build_source"], .string(IChartTelemetryBuildSource.value))
        XCTAssertEqual(Set(event.properties.keys), ["source", "result", "error_code", "duration_ms", "build_source"])
        let encoded = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
        XCTAssertFalse(encoded.contains("PRIVATE_SYNTHETIC_ERROR_TEXT"))
        XCTAssertEqual(repository.saveAttempts, 0,
            "Telemetry must not attempt to repair or overwrite a failed library load")
    }

    func testBlockedTelemetryStorageCannotDelaySyntheticLibrarySaveAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-save-isolation-\(UUID())"))
        defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
        let gate = TelemetryColdLaunchStorageGate()
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("diagnostics/queue.json"),
            fileManager: TelemetryColdLaunchBlockingFileManager(gate: gate))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryColdLaunchOfflineProtocol.self]
        let service = IChartTelemetryService(endpointURL: URL(string: "https://telemetry.invalid/ingest")!,
            publishableKey: "test", sessionStore: nil, queueStore: queue, installationID: UUID(),
            consentStore: IChartTelemetryConsentStore(defaults: defaults),
            urlSession: URLSession(configuration: configuration))
        IChartTelemetry.configure(service)
        await service.initialize()
        let blockedDiagnostic = Task.detached {
            await service.record("app.error", properties: ["error_code": .string("save_error")])
        }
        defer { gate.release() }
        XCTAssertTrue(gate.waitUntilEntered(), "The test must hold actual optional queue I/O")

        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        var chart = Chart.blank(title: "Synthetic save fixture", layoutStyle: .rhythmSectionSheet)
        let chordBytes = Data([0x10, 0x20, 0x30])
        chart.setPageHandwrittenChordDrawing(chordBytes)
        chart.pageHandwrittenNotationData = Data([0x40, 0x50])
        let store = ChartLibraryStore(charts: [chart], selectedChartID: chart.id, repository: repository)
        let saved = expectation(description: "real library save finishes while optional diagnostics is held")
        store.onSnapshotSaved = { _ in saved.fulfill() }
        await MainActor.run { store.charts[0].title = "Synthetic saved edit" }
        await fulfillment(of: [saved], timeout: 2)

        let reopened = try XCTUnwrap(try repository.loadSnapshot())
        XCTAssertEqual(reopened.charts[0].title, "Synthetic saved edit")
        XCTAssertEqual(reopened.charts[0].id, chart.id)
        XCTAssertEqual(reopened.charts[0].measures, chart.measures)
        XCTAssertEqual(reopened.charts[0].pageHandwrittenChordData, chordBytes)
        XCTAssertEqual(reopened.charts[0].pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
        XCTAssertEqual(reopened.selectedChartID, chart.id)

        gate.release()
        await blockedDiagnostic.value
    }
}

/// Bounded fixed stage/denial names only; no event properties or identity values.
private final class TelemetryColdLaunchRecordingStages: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [String] = []

    func record(_ trace: IChartTelemetryRecordingTrace) {
        lock.lock()
        defer { lock.unlock() }
        guard stages.count < 32 else { return }
        let denial = trace.admissionDenial.map { ":" + $0.rawValue } ?? ""
        stages.append(trace.stage.rawValue + denial)
    }

    var failureDescription: String {
        lock.lock()
        defer { lock.unlock() }
        return "Fixed load error was not queued. Actor stages: "
            + (stages.isEmpty ? "none observed" : stages.joined(separator: ", "))
    }
}

private final class TelemetryColdLaunchStorageGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var hasBlocked = false
    func block() throws {
        lock.lock()
        let shouldBlock = !hasBlocked
        hasBlocked = true
        lock.unlock()
        guard shouldBlock else { return }
        entered.signal()
        guard released.wait(timeout: .now() + 8) == .success else { throw CocoaError(.fileWriteUnknown) }
    }
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 3) == .success }
    func release() { released.signal() }
}

private final class TelemetryColdLaunchBlockingFileManager: FileManager, @unchecked Sendable {
    private let gate: TelemetryColdLaunchStorageGate
    init(gate: TelemetryColdLaunchStorageGate) { self.gate = gate; super.init() }
    override func createDirectory(at url: URL, withIntermediateDirectories: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        try gate.block()
        try super.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: attributes)
    }
}

private final class TelemetryColdLaunchFailingRepository: ChartRepository {
    var savesSnapshotsOffMainThread = false
    private(set) var saveAttempts = 0
    func loadSnapshot() throws -> ChartLibrarySnapshot? {
        throw NSError(domain: "PRIVATE_SYNTHETIC_ERROR_TEXT", code: 1)
    }
    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws { saveAttempts += 1 }
}

private final class TelemetryColdLaunchOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif

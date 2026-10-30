#if canImport(UIKit)
import CryptoKit
import Foundation
import XCTest
@testable import iChart

final class TelemetryColdLaunchTests: XCTestCase {
    func testConfiguredRealLibraryColdLoadQueuesChartAndNonemptyInkReopenEvidence() async throws {
        let consent = IChartTelemetryConsentStore.shared
        _ = consent.snapshot
        let preferences = UserDefaults.standard
        let savedPreferences = preferences.dictionaryRepresentation().filter { $0.key.hasPrefix("iChart.telemetry.") }
        let standardCheckpoint = ChartPersistenceContractDiagnostics.checkpointURL(for: FileChartRepository.live().url)
        let savedStandardCheckpoint = try? Data(contentsOf: standardCheckpoint)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            IChartTelemetry.configure(nil)
            // Invalidate any delayed test tasks before restoring this test
            // process's exact prior preferences and diagnostic checkpoint.
            consent.setConsentGranted(false)
            restoreTelemetryPreferences(savedPreferences, in: preferences)
            _ = consent.snapshot
            restoreTelemetryPreferences(savedPreferences, in: preferences)
            if let savedStandardCheckpoint {
                try? savedStandardCheckpoint.write(to: standardCheckpoint, options: .atomic)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        consent.setConsentGranted(true)
        let authorization = try XCTUnwrap(consent.checkpointAuthorization())
        let repository = FileChartRepository(url: directory.appendingPathComponent("library.json"))
        var chart = Chart.blank(title: "Private cold launch fixture")
        chart.pageHandwrittenNotationData = Data([1, 2, 3, 4])
        let snapshot = ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id, entitlements: .free)
        try repository.saveSnapshot(snapshot)
        let libraryBefore = try Data(contentsOf: repository.url)
        let checkpoint = ChartPersistenceContractDiagnostics.Checkpoint(
            identity: authorization.identity,
            fileDigest: SHA256.hash(data: libraryBefore).map { String(format: "%02x", $0) }.joined(),
            chartCount: 1, summaries: ChartExperienceContractSummary.capture(snapshot)
        )
        let checkpointURL = ChartPersistenceContractDiagnostics.checkpointURL(for: repository.url)
        XCTAssertTrue(try consent.publishDiagnosticCheckpoint(
            JSONEncoder().encode(checkpoint), to: checkpointURL, authorization: authorization
        ))
        let queueURL = directory.appendingPathComponent("telemetry.json")
        let queue = IChartTelemetryQueueStore(url: queueURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryColdLaunchOfflineProtocol.self]
        let service = IChartTelemetryService(
            endpointURL: URL(string: "https://telemetry.invalid/ingest")!, publishableKey: "test",
            sessionStore: nil, queueStore: queue, consentStore: consent,
            urlSession: URLSession(configuration: configuration)
        )

        // Match the application startup ordering and exercise the actual
        // app-only adapter, rather than injecting a diagnostics recorder.
        IChartTelemetry.configure(service)
        let loaded = ChartLibraryStore.live(repository: repository)
        XCTAssertEqual(loaded.charts, snapshot.charts)
        let events = try await coldLoadEvents(at: queueURL)
        let load = try XCTUnwrap(events.first { $0.properties["contract_id"] == .string("chart.load") })
        let ink = try XCTUnwrap(events.first {
            $0.properties["contract_id"] == .string("ink.reopen_preservation") && $0.properties["scope"] == .string("page")
        })

        XCTAssertEqual(load.properties["outcome"], .string("passed"))
        XCTAssertEqual(load.properties["actual_count"], .int(1))
        XCTAssertEqual(ink.properties["outcome"], .string("passed"))
        XCTAssertEqual(ink.properties["actual_count"], .int(1))
        XCTAssertEqual(ink.properties["actual_bytes"], .int(4))
        XCTAssertEqual(load.installationID.uuidString.lowercased(), authorization.identity)
        XCTAssertEqual(ink.installationID, load.installationID)
        XCTAssertEqual(ink.sessionID, load.sessionID)
        XCTAssertNotNil(ink.properties["chart_reference"])
        let encodedEvents = try JSONEncoder().encode(events)
        let text = String(decoding: encodedEvents, as: UTF8.self)
        XCTAssertFalse(text.contains(chart.title))
        XCTAssertFalse(text.lowercased().contains(chart.id.uuidString.lowercased()))
        XCTAssertFalse(text.contains(checkpoint.fileDigest))
        XCTAssertTrue(checkpoint.summaries.allSatisfy { !text.contains($0.contentDigest) })
        XCTAssertEqual(try Data(contentsOf: repository.url), libraryBefore)

        IChartTelemetry.configure(nil)
        consent.setConsentGranted(false)
        await service.consentDidChange()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path))
        // The real bridge's captured authorization cannot publish after this
        // consent generation has ended, even if the test opts in again.
        consent.setConsentGranted(true)
        XCTAssertFalse(try consent.publishDiagnosticCheckpoint(Data([9]), to: checkpointURL, authorization: authorization))
    }

    private func coldLoadEvents(at url: URL) async throws -> [IChartTelemetryEvent] {
        struct Queue: Decodable { var events: [IChartTelemetryEvent] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var events: [IChartTelemetryEvent] = []
        for _ in 0..<60 {
            if let data = try? Data(contentsOf: url), let queue = try? decoder.decode(Queue.self, from: data) {
                events = queue.events
                if events.contains(where: { $0.properties["contract_id"] == .string("chart.load") }) && events.contains(where: {
                    $0.properties["contract_id"] == .string("ink.reopen_preservation") && $0.properties["scope"] == .string("page")
                }) { return events }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The configured cold-load bridge did not queue both chart and nonempty ink evidence")
        return events
    }

    private func restoreTelemetryPreferences(_ saved: [String: Any], in preferences: UserDefaults) {
        for key in preferences.dictionaryRepresentation().keys where key.hasPrefix("iChart.telemetry.") {
            preferences.removeObject(forKey: key)
        }
        for (key, value) in saved { preferences.set(value, forKey: key) }
    }
}

private final class TelemetryColdLaunchOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif

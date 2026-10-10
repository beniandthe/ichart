import Foundation
import XCTest
@testable import iChart

final class PerformanceTracePrivacyTests: XCTestCase {
    private let legacy = #"{"timestamp":"2026-10-07T18:00:00Z","processUptimeSeconds":98765,"name":"app.bootstrap.end","durationMilliseconds":42.5,"metadata":{"flow":"bootstrap","systemUptime":"98765"},"appVersion":"1.2.1","buildNumber":"74","unexpectedPrivateField":"never export this"}"#

    func testLegacyExportDropsRawUptimeAndUnknownFieldsButPreservesTiming() throws {
        let data = try IChartPerformanceTraceReportSanitizer.sanitize(Data((legacy + "\n").utf8))
        let event = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(event["processUptimeSeconds"])
        XCTAssertNil(event["unexpectedPrivateField"])
        XCTAssertEqual(event["durationMilliseconds"] as? Double, 42.5)
        XCTAssertEqual(event["name"] as? String, "app.bootstrap.end")
        let metadata = try XCTUnwrap(event["metadata"] as? [String: String])
        XCTAssertEqual(metadata, ["flow": "bootstrap"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("98765"))
    }

    func testMalformedAndPartialLinesAreNeverForwardedAsRawText() throws {
        let input = Data(("not-json private information\n" + legacy + "\n{partial\n").utf8)
        let data = try IChartPerformanceTraceReportSanitizer.sanitize(input)
        XCTAssertEqual(data.split(separator: 0x0A).count, 1)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private information"))
        XCTAssertTrue(try IChartPerformanceTraceReportSanitizer.sanitize(Data("bad".utf8)).isEmpty)
    }

    func testExplicitReportPreservesDiagnosticContextNotJustTiming() throws {
        let input = #"{"timestamp":"2026-10-09T22:00:00Z","name":"synthetic.failure","durationMilliseconds":12,"metadata":{"reason":"synthetic error context","identifier":"synthetic-id"},"appVersion":"1.2.1","buildNumber":"75"}"#
        let data = try IChartPerformanceTraceReportSanitizer.sanitize(Data(input.utf8))
        let event = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try XCTUnwrap(event["metadata"] as? [String: String])
        XCTAssertEqual(metadata, ["reason": "synthetic error context", "identifier": "synthetic-id"])
    }

    func testExportUsesSanitizedSnapshotAndLeavesLocalLegacySourceIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("performance-trace.jsonl")
        let source = Data((legacy + "\n").utf8)
        try source.write(to: sourceURL)
        let recorder = IChartPerformanceTraceRecorder(url: sourceURL)
        let exportedURL = try recorder.exportReport()
        XCTAssertNotEqual(exportedURL, sourceURL)
        XCTAssertEqual(try Data(contentsOf: sourceURL), source)
        XCTAssertFalse(try String(contentsOf: exportedURL).contains("processUptimeSeconds"))
        XCTAssertTrue(try String(contentsOf: exportedURL).contains("durationMilliseconds"))
    }

    func testFreshEventsHaveNoRawUptimeProperty() throws {
        let event = IChartPerformanceTraceEvent(timestamp: Date(), name: "test.end",
            durationMilliseconds: 17, metadata: [:], appVersion: "1.2.1", buildNumber: "74")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        XCTAssertNil(object["processUptimeSeconds"])
        XCTAssertEqual(object["durationMilliseconds"] as? Double, 17)
    }
}

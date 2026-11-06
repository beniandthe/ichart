import Foundation
import XCTest
@testable import iChart

final class ChartCloudContentIdentityTests: XCTestCase {
    func testIdentityMatchesCloudPayloadAndIgnoresOnlyBackupBookkeeping() throws {
        var chart = Chart.blank(title: "Saved chart")
        chart.updatedAt = Date(timeIntervalSinceReferenceDate: 10_000)
        chart.pageHandwrittenChordData = Data([1, 2, 3, 4])
        let digest = try ChartCloudContentIdentity.sha256(for: chart)
        XCTAssertEqual(digest, try ChartCloudContentIdentity.sha256(for: IChartJSONValue.chartPayload(for: chart)))
        XCTAssertTrue(ChartCloudContentIdentity.isValidSHA256(digest))

        var acknowledged = chart
        acknowledged.markBackedUpToCloud(ownerID: UUID(), at: Date(timeIntervalSinceReferenceDate: 11_000))
        acknowledged.cloudBackupStatus.acknowledgedContentSHA256 = digest
        XCTAssertEqual(try ChartCloudContentIdentity.sha256(for: acknowledged), digest)
        XCTAssertTrue(ChartCloudContentIdentity.matchesContent(chart, acknowledged))

        acknowledged.title = "Edited with the same timestamp"
        XCTAssertEqual(chart.updatedAt, acknowledged.updatedAt)
        XCTAssertNotEqual(try ChartCloudContentIdentity.sha256(for: acknowledged), digest)
        XCTAssertFalse(ChartCloudContentIdentity.matchesContent(chart, acknowledged))
    }

    func testInkChangesChangeIdentityEvenWhenTimestampDoesNot() throws {
        var chart = Chart.blank(title: "Ink")
        chart.pageHandwrittenNotationData = Data([7, 8, 9])
        let original = chart
        let digest = try ChartCloudContentIdentity.sha256(for: chart)
        chart.pageHandwrittenNotationData = Data([7, 8, 10])
        XCTAssertEqual(chart.updatedAt, original.updatedAt)
        XCTAssertNotEqual(try ChartCloudContentIdentity.sha256(for: chart), digest)
        XCTAssertFalse(ChartCloudContentIdentity.matchesContent(original, chart))
    }

    func testSavedAcknowledgmentRoundTripsAndLegacyMetadataHasNoAcknowledgment() throws {
        var chart = Chart.blank(title: "Acknowledged")
        let digest = try ChartCloudContentIdentity.sha256(for: chart)
        chart.markBackedUpToCloud(ownerID: UUID(), at: Date(timeIntervalSinceReferenceDate: 12_000))
        chart.cloudBackupStatus.acknowledgedContentSHA256 = digest
        let encoded = try ChartPersistenceCoders.encoder.encode(chart)
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self, from: encoded)
        XCTAssertEqual(reopened.cloudBackupStatus.acknowledgedContentSHA256, digest)
        XCTAssertEqual(try ChartCloudContentIdentity.sha256(for: reopened), digest)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var status = try XCTUnwrap(object["cloudBackupStatus"] as? [String: Any])
        status.removeValue(forKey: "acknowledgedContentSHA256")
        object["cloudBackupStatus"] = status
        let legacy = try ChartPersistenceCoders.decoder.decode(Chart.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.cloudBackupStatus.acknowledgedContentSHA256)
        XCTAssertEqual(try ChartCloudContentIdentity.sha256(for: legacy), digest)
    }

    func testInvalidOrMissingAcknowledgmentsAreNotTrusted() {
        for value in [nil, "", String(repeating: "a", count: 63), String(repeating: "A", count: 64), String(repeating: "z", count: 64)] as [String?] {
            XCTAssertFalse(ChartCloudContentIdentity.isValidSHA256(value))
        }
        XCTAssertTrue(ChartCloudContentIdentity.isValidSHA256(String(repeating: "0", count: 64)))
    }
}

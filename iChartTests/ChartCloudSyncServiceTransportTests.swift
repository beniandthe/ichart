#if canImport(Supabase)
import Foundation
import Supabase
import XCTest
@testable import iChart

final class ChartCloudSyncServiceTransportTests: XCTestCase {
    func testRestorePagesMoreThanOneThousandDocumentsAndReadsOnlyRequiredSnapshots() async throws {
        let fixture = CloudTransportFixture()
        let hot = fixture.chart(2_000, title: "Hot")
        let cold = fixture.chart(2_001, title: "Cold")
        let activeCharts = [hot, cold] + (2..<105).map { fixture.chart(2_000 + $0, title: "Current \($0)") }
        fixture.documents = (1...1_005).map { fixture.document(fixture.id($0), snapshotID: nil, deleted: true) }
            + activeCharts.enumerated().map { fixture.document($0.element.id, snapshotID: fixture.id(8_000 + $0.offset)) }
        fixture.snapshots = try (1...1_205).map { version in
            try fixture.snapshot(hot, id: fixture.id(10_000 + version), version: version)
        } + activeCharts.enumerated().map { try fixture.snapshot($0.element, id: fixture.id(8_000 + $0.offset), version: $0.offset == 1 ? 1 : 2_000) }
        // Simulate a server cap lower than the requested page size as well.
        fixture.serverRowCap = 37
        let connection = fixture.connection()
        defer { connection.close() }

        let remote = try await ChartCloudRemoteSnapshotReader(client: connection.client).read(ownerID: fixture.ownerID)

        XCTAssertEqual(Set(remote.charts.map(\.id)), Set(activeCharts.map(\.id)))
        XCTAssertEqual(remote.deletionTombstones.count, 1_005)
        XCTAssertGreaterThan(fixture.documentReads, 10)
        XCTAssertEqual(fixture.unboundedSnapshotReads, 0)
        XCTAssertEqual(fixture.returnedSnapshotRows, 105)
        XCTAssertTrue(remote.charts.allSatisfy { ChartCloudContentIdentity.isValidSHA256($0.cloudBackupStatus.acknowledgedContentSHA256) })
    }

    func testLegacyDocumentReadsOneLatestRevisionAndMissingSnapshotFailsClosed() async throws {
        let fixture = CloudTransportFixture()
        let chart = fixture.chart(2_000, title: "Legacy")
        fixture.documents = [fixture.document(chart.id, snapshotID: nil)]
        fixture.snapshots = try [fixture.snapshot(chart, id: fixture.id(8_000), version: 1), fixture.snapshot(chart, id: fixture.id(8_001), version: 2)]
        let connection = fixture.connection()
        defer { connection.close() }

        let remote = try await ChartCloudRemoteSnapshotReader(client: connection.client).read(ownerID: fixture.ownerID)
        XCTAssertEqual(remote.charts.map(\.id), [chart.id])
        XCTAssertEqual(fixture.returnedSnapshotRows, 1)
        XCTAssertEqual(fixture.unboundedSnapshotReads, 0)

        fixture.documents = [fixture.document(chart.id, snapshotID: fixture.id(9_999))]
        do {
            _ = try await ChartCloudRemoteSnapshotReader(client: connection.client).read(ownerID: fixture.ownerID)
            XCTFail("A missing required snapshot must not become a successful partial restore")
        } catch let error as ChartCloudSyncStageError {
            XCTAssertEqual(error.stage, .readingSnapshots)
            XCTAssertTrue(error.underlyingError is ChartCloudRemoteReadError)
        }
    }

    func testRestoreRejectsSnapshotOwnerChartAndPayloadIdentityMismatches() async throws {
        for corruption in ["owner", "chart", "payload"] {
            let fixture = CloudTransportFixture()
            let chart = fixture.chart(2_000, title: "Protected")
            fixture.documents = [fixture.document(chart.id, snapshotID: fixture.id(8_000))]
            fixture.snapshots = try [fixture.snapshot(chart, id: fixture.id(8_000), version: 1)]
            fixture.corruption = corruption
            let connection = fixture.connection()
            defer { connection.close() }
            do {
                _ = try await ChartCloudRemoteSnapshotReader(client: connection.client).read(ownerID: fixture.ownerID)
                XCTFail("Invalid snapshot identity must fail closed: \(corruption)")
            } catch let error as ChartCloudSyncStageError {
                XCTAssertTrue(error.underlyingError is ChartCloudRemoteReadError)
            }
        }
    }

    func testLegacyRemotePayloadIsAcknowledgedBeforeNormalizationAndUploadedOnce() async throws {
        let fixture = CloudTransportFixture()
        let original = fixture.chart(2_000, title: "Legacy normalization")
        var row = try fixture.snapshot(original, id: fixture.id(8_000), version: 1)
        var payload = try XCTUnwrap(row["chart_json"] as? [String: Any])
        payload.removeValue(forKey: "headerInputMode")
        payload["chordTranspositionSemitones"] = 2
        row["chart_json"] = payload
        fixture.documents = [fixture.document(original.id, snapshotID: fixture.id(8_000))]
        fixture.snapshots = [row]
        let storedPayload = try JSONDecoder().decode(IChartJSONValue.self,
            from: JSONSerialization.data(withJSONObject: payload))
        let storedDigest = try ChartCloudContentIdentity.sha256(for: storedPayload)
        let connection = fixture.connection()
        defer { connection.close() }

        let remote = try await ChartCloudRemoteSnapshotReader(client: connection.client).read(ownerID: fixture.ownerID)
        var chart = try XCTUnwrap(remote.charts.first)
        XCTAssertEqual(chart.headerInputMode, .typed)
        XCTAssertEqual(chart.chordTranspositionSemitones, 0)
        XCTAssertEqual(chart.cloudBackupStatus.acknowledgedContentSHA256, storedDigest)
        let normalizedDigest = try ChartCloudContentIdentity.sha256(for: chart)
        XCTAssertNotEqual(normalizedDigest, storedDigest)

        let service = ChartCloudSyncService(client: connection.client, currentUserIDProvider: { fixture.ownerID })
        let uploaded = try await service.pushLocalSnapshot(fixture.library(chart))
        XCTAssertTrue(uploaded.didPerformRemoteWrites)
        XCTAssertEqual(uploaded.backedUpChartIDs, [chart.id])
        XCTAssertEqual(uploaded.acknowledgedContentSHA256ByChartID[chart.id], normalizedDigest)
        XCTAssertEqual(fixture.snapshotWrites, 1)
        chart.markBackedUpToCloud(ownerID: fixture.ownerID, at: uploaded.lastRemoteBackupAt)
        chart.cloudBackupStatus.acknowledgedContentSHA256 = uploaded.acknowledgedContentSHA256ByChartID[chart.id]
        let requestCount = fixture.requestCount

        let unchanged = try await service.pushLocalSnapshot(fixture.library(chart))
        XCTAssertFalse(unchanged.didPerformRemoteWrites)
        XCTAssertEqual(fixture.snapshotWrites, 1)
        XCTAssertEqual(fixture.requestCount, requestCount)
    }

    func testAcknowledgedContentSurvivesReopenAndUnchangedBackupPerformsNoHTTP() async throws {
        let fixture = CloudTransportFixture()
        var chart = fixture.chart(2_000, title: "Acknowledged")
        let connection = fixture.connection()
        defer { connection.close() }
        let service = ChartCloudSyncService(client: connection.client, currentUserIDProvider: { fixture.ownerID })

        let first = try await service.pushLocalSnapshot(fixture.library(chart))
        XCTAssertTrue(first.didPerformRemoteWrites)
        XCTAssertEqual(first.backedUpChartIDs, [chart.id])
        XCTAssertEqual(fixture.requestCount, 4)
        XCTAssertEqual(fixture.snapshotWrites, 1)
        chart.markBackedUpToCloud(ownerID: fixture.ownerID, at: first.lastRemoteBackupAt)
        chart.cloudBackupStatus.acknowledgedContentSHA256 = try XCTUnwrap(first.acknowledgedContentSHA256ByChartID[chart.id])
        chart = try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))

        let second = try await service.pushLocalSnapshot(fixture.library(chart))
        XCTAssertFalse(second.didPerformRemoteWrites)
        XCTAssertTrue(second.backedUpChartIDs.isEmpty)
        XCTAssertEqual(second.lastRemoteBackupAt, first.lastRemoteBackupAt)
        XCTAssertEqual(fixture.requestCount, 4)
        XCTAssertEqual(fixture.snapshotWrites, 1)

        // A content change must upload even when updatedAt did not change.
        chart.title = "Edited without advancing the clock"
        chart.pageHandwrittenChordData = Data([1, 4, 9])
        let third = try await service.pushLocalSnapshot(fixture.library(chart))
        XCTAssertTrue(third.didPerformRemoteWrites)
        XCTAssertEqual(third.backedUpChartIDs, [chart.id])
        XCTAssertEqual(fixture.snapshotWrites, 2)
        XCTAssertNotEqual(third.acknowledgedContentSHA256ByChartID[chart.id], first.acknowledgedContentSHA256ByChartID[chart.id])
    }

    func testMissingLegacyOrMalformedAcknowledgmentRequiresUpload() async throws {
        for storedDigest in [nil, "bad", String(repeating: "A", count: 64)] as [String?] {
            let fixture = CloudTransportFixture()
            var chart = fixture.chart(2_000, title: "Legacy backup")
            chart.markBackedUpToCloud(ownerID: fixture.ownerID, at: Date(timeIntervalSinceReferenceDate: 15_000))
            chart.cloudBackupStatus.acknowledgedContentSHA256 = storedDigest
            let connection = fixture.connection()
            defer { connection.close() }
            let service = ChartCloudSyncService(client: connection.client, currentUserIDProvider: { fixture.ownerID })
            let result = try await service.pushLocalSnapshot(fixture.library(chart))
            XCTAssertTrue(result.didPerformRemoteWrites)
            XCTAssertEqual(fixture.snapshotWrites, 1)
            XCTAssertTrue(ChartCloudContentIdentity.isValidSHA256(result.acknowledgedContentSHA256ByChartID[chart.id]))
        }
    }

    func testExplicitBackupRepairsRemoteAbsenceEvenWhenLocalContentWasAcknowledged() async throws {
        let fixture = CloudTransportFixture()
        var chart = fixture.chart(2_000, title: "Explicit backup")
        let digest = try ChartCloudContentIdentity.sha256(for: chart)
        chart.markBackedUpToCloud(ownerID: fixture.ownerID, at: Date(timeIntervalSinceReferenceDate: 15_000))
        chart.cloudBackupStatus.acknowledgedContentSHA256 = digest
        let connection = fixture.connection()
        defer { connection.close() }
        let service: any ChartCloudSyncServicing = ChartCloudSyncService(client: connection.client, currentUserIDProvider: { fixture.ownerID })

        let automatic = try await service.pushLocalSnapshot(fixture.library(chart), forceRemoteWrite: false, onProgress: nil)
        XCTAssertFalse(automatic.didPerformRemoteWrites)
        XCTAssertEqual(fixture.requestCount, 0)
        let explicit = try await service.pushLocalSnapshot(fixture.library(chart), forceRemoteWrite: true, onProgress: nil)
        XCTAssertTrue(explicit.didPerformRemoteWrites)
        XCTAssertEqual(explicit.backedUpChartIDs, [chart.id])
        XCTAssertEqual(fixture.snapshotWrites, 1)
        XCTAssertEqual(fixture.requestCount, 4)
    }

    func testAConflictingRevisionOrUnlinkedSnapshotIsNeverAcknowledged() async throws {
        for failure in ["collision", "link"] {
            let fixture = CloudTransportFixture()
            let chart = fixture.chart(2_000, title: "Write verification")
            fixture.writeFailure = failure
            let connection = fixture.connection()
            defer { connection.close() }
            let service = ChartCloudSyncService(client: connection.client, currentUserIDProvider: { fixture.ownerID })
            do {
                _ = try await service.pushLocalSnapshot(fixture.library(chart))
                XCTFail("An unverified write must not return an acknowledgment")
            } catch let error as ChartCloudSyncStageError {
                XCTAssertEqual(error.stage, failure == "collision" ? .resolvingSnapshot : .linkingSnapshot)
            }
        }
    }

    func testEmptyUnbackedLibraryDoesNotInventAFreshBackupClock() async throws {
        let fixture = CloudTransportFixture()
        let connection = fixture.connection()
        defer { connection.close() }
        let service = ChartCloudSyncService(client: connection.client, currentUserIDProvider: { fixture.ownerID })
        let snapshot = ChartLibrarySnapshot(charts: [], selectedChartID: nil, entitlements: .free)
        let result = try await service.pushLocalSnapshot(snapshot)
        XCTAssertFalse(result.didPerformRemoteWrites)
        XCTAssertEqual(result.lastRemoteBackupAt, .distantPast)
        XCTAssertEqual(fixture.requestCount, 0)
    }

    func testEmptyRestorePreservesOptionalBackupDateWithoutPersistingSentinel() async throws {
        for priorDate in [nil, Date(timeIntervalSinceReferenceDate: 15_000)] as [Date?] {
            let fixture = CloudTransportFixture()
            let connection = fixture.connection()
            defer { connection.close() }
            let service = ChartCloudSyncService(client: connection.client, currentUserIDProvider: { fixture.ownerID })
            let snapshot = ChartLibrarySnapshot(charts: [], selectedChartID: nil, entitlements: .free,
                cloudMetadata: ChartCloudMetadata(lastRemoteBackupAt: priorDate))

            let outcome = try await service.restoreFromCloud(localSnapshot: snapshot)
            XCTAssertEqual(outcome.syncResult.lastRemoteBackupAt, priorDate)
            XCTAssertEqual(outcome.syncResult.snapshot.cloudMetadata.lastRemoteBackupAt, priorDate)
            XCTAssertEqual(outcome.syncResult.snapshot.cloudMetadata.ownerID, fixture.ownerID)
            XCTAssertEqual(outcome.backedUpChartCount, 0)
            XCTAssertEqual(outcome.tombstonedChartCount, 0)
            XCTAssertEqual(fixture.requestCount, 1)
            XCTAssertEqual(fixture.snapshotWrites, 0)
            let reopened = try ChartPersistenceCoders.decoder.decode(ChartLibrarySnapshot.self,
                from: ChartPersistenceCoders.encoder.encode(outcome.syncResult.snapshot))
            XCTAssertEqual(reopened.cloudMetadata.lastRemoteBackupAt, priorDate)
        }
    }
}

private final class CloudTransportFixture: @unchecked Sendable {
    let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000999999")!
    var documents: [[String: Any]] = []
    var snapshots: [[String: Any]] = []
    var serverRowCap = 1_000
    var corruption: String?
    var writeFailure: String?
    private let lock = NSLock()
    private(set) var documentReads = 0
    private(set) var unboundedSnapshotReads = 0
    private(set) var returnedSnapshotRows = 0
    private(set) var requestCount = 0
    private(set) var snapshotWrites = 0

    func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))! }
    func chart(_ value: Int, title: String) -> Chart {
        var chart = Chart.blank(title: title, measureCount: 1)
        chart.id = id(value)
        chart.updatedAt = Date(timeIntervalSinceReferenceDate: 10_000)
        return chart
    }
    func library(_ chart: Chart) -> ChartLibrarySnapshot { ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id, entitlements: .free) }
    func document(_ id: UUID, snapshotID: UUID?, deleted: Bool = false) -> [String: Any] {
        ["id": id.uuidString, "owner_id": ownerID.uuidString, "title": "Fixture", "layout_style": "simpleChordSheet", "latest_snapshot_id": snapshotID.map { $0.uuidString as Any } ?? NSNull(), "deleted_at": deleted ? ("2026-11-01T00:00:00.000Z" as Any) : NSNull(), "remote_revision": 1, "updated_at": "2026-11-02T00:00:00.000Z"]
    }
    func snapshot(_ chart: Chart, id: UUID, version: Int) throws -> [String: Any] {
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(IChartJSONValue.chartPayload(for: chart)))
        return ["id": id.uuidString, "chart_id": chart.id.uuidString, "owner_id": ownerID.uuidString, "version": version, "chart_json": payload, "created_at": "2026-11-02T00:00:00.000Z"]
    }

    func connection() -> CloudTestConnection {
        let host = UUID().uuidString.lowercased() + ".invalid"
        CloudFixtureURLProtocol.install(host: host, handler: respond)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(supabaseURL: URL(string: "https://" + host)!, supabaseKey: "fixture-key", options: .init(auth: .init(storage: CloudTestAuthStorage(), autoRefreshToken: false, accessToken: { "fixture-token" }), global: .init(session: session)))
        return CloudTestConnection(client: client, session: session, host: host)
    }

    private func respond(_ request: URLRequest) throws -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        let url = request.url!
        let filters = Dictionary(grouping: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [], by: \.name)
            .mapValues { $0.map { $0.value ?? "" } }
        let query = filters.mapValues { $0.last ?? "" }
        let method = request.httpMethod ?? "GET"
        let table = url.lastPathComponent
        var rows: [[String: Any]]
        if method == "POST" {
            var body = try bodyObject(request)
            if table == "chart_documents" {
                if let index = documents.firstIndex(where: { sameID($0["id"], body["id"]) }) { documents[index].merge(body) { _, new in new } }
                else { documents.append(body) }
            } else if table == "chart_snapshots" {
                snapshotWrites += 1
                if writeFailure == "collision" {
                    body["id"] = id(8_888).uuidString
                    var payload = body["chart_json"] as! [String: Any]
                    payload["title"] = "Another device's different content"
                    body["chart_json"] = payload
                }
                snapshots.append(body)
            } else { throw URLError(.unsupportedURL) }
            return (201, Data("[]".utf8))
        }
        if method == "PATCH", table == "chart_documents" {
            if writeFailure == "link" { return (200, Data("[]".utf8)) }
            let body = try bodyObject(request)
            guard let index = documents.firstIndex(where: { matches($0, key: "id", query: filters) }) else { return (200, Data("[]".utf8)) }
            documents[index].merge(body) { _, new in new }
            return (200, try JSONSerialization.data(withJSONObject: [documents[index]]))
        }
        guard method == "GET", ["chart_documents", "chart_snapshots"].contains(table) else { throw URLError(.unsupportedURL) }
        if table == "chart_documents" { documentReads += 1; rows = documents }
        else {
            if query["id"] == nil && query["chart_id"] == nil { unboundedSnapshotReads += 1 }
            rows = snapshots
        }
        rows = rows.filter { matches($0, key: "owner_id", query: filters) && matches($0, key: "id", query: filters) && matches($0, key: "chart_id", query: filters) && matches($0, key: "version", query: filters) }
        if query["order"]?.hasPrefix("version.desc") == true {
            rows.sort { ($0["version"] as! NSNumber).int64Value > ($1["version"] as! NSNumber).int64Value }
        } else { rows.sort { canonicalID($0["id"]) < canonicalID($1["id"]) } }
        rows = Array(rows.prefix(min(Int(query["limit"] ?? "1000") ?? 1_000, serverRowCap)))
        if table == "chart_snapshots" {
            returnedSnapshotRows += rows.count
            if !rows.isEmpty {
                if corruption == "owner" { rows[0]["owner_id"] = id(777_777).uuidString }
                if corruption == "chart" { rows[0]["chart_id"] = id(777_777).uuidString }
                if corruption == "payload" {
                    var payload = rows[0]["chart_json"] as! [String: Any]
                    payload["id"] = id(777_777).uuidString
                    rows[0]["chart_json"] = payload
                }
            }
        }
        return (200, try JSONSerialization.data(withJSONObject: rows))
    }

    private func bodyObject(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var result = Data(); var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                result.append(contentsOf: buffer.prefix(count))
            }
            data = result
        } else { throw URLError(.cannotDecodeRawData) }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private func canonicalID(_ value: Any?) -> String { (value as? String).flatMap(UUID.init(uuidString:))?.uuidString ?? "" }
    private func sameID(_ lhs: Any?, _ rhs: Any?) -> Bool { canonicalID(lhs) == canonicalID(rhs) }
    private func matches(_ row: [String: Any], key: String, query: [String: [String]]) -> Bool {
        guard let filters = query[key] else { return true }
        return filters.allSatisfy { matches(row, key: key, filter: $0) }
    }
    private func matches(_ row: [String: Any], key: String, filter: String) -> Bool {
        if key == "version", filter.hasPrefix("eq.") { return (row[key] as? NSNumber)?.int64Value == Int64(filter.dropFirst(3)) }
        if filter.hasPrefix("eq.") { return canonicalID(row[key]) == canonicalID(String(filter.dropFirst(3))) }
        if filter.hasPrefix("gt.") { return canonicalID(row[key]) > canonicalID(String(filter.dropFirst(3))) }
        if filter.hasPrefix("in.("), filter.hasSuffix(")") {
            let values = filter.dropFirst(4).dropLast().split(separator: ",").map { canonicalID(String($0).replacingOccurrences(of: "\"", with: "")) }
            return values.contains(canonicalID(row[key]))
        }
        return false
    }
}

private struct CloudTestConnection {
    let client: SupabaseClient
    let session: URLSession
    let host: String
    func close() { session.invalidateAndCancel(); CloudFixtureURLProtocol.remove(host: host) }
}

private struct CloudTestAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}

private final class CloudFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest) throws -> (Int, Data)] = [:]
    static func install(host: String, handler: @escaping (URLRequest) throws -> (Int, Data)) { lock.lock(); handlers[host] = handler; lock.unlock() }
    static func remove(host: String) { lock.lock(); handlers.removeValue(forKey: host); lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let handler = Self.handlers[request.url!.host!]; Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"] )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif

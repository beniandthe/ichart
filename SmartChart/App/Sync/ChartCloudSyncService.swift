import Foundation
import Supabase

enum ChartSyncState: Equatable {
    case unconfigured
    case signedOut
    case offline
    case syncing
    case synced(Date)
    case failed(String)

    var displayText: String {
        switch self {
        case .unconfigured:
            return "Cloud backup unavailable"
        case .signedOut:
            return "Sign in to back up"
        case .offline:
            return "Offline"
        case .syncing:
            return "Syncing"
        case .synced(let date):
            return "Synced \(date.formatted(date: .omitted, time: .shortened))"
        case .failed:
            return "Sync needs attention"
        }
    }

    var detailText: String {
        switch self {
        case .unconfigured:
            return "Add Supabase configuration to enable cloud backup."
        case .signedOut:
            return "Charts stay local until you sign in."
        case .offline:
            return "Local edits are saved. Reconnect to back up."
        case .syncing:
            return "Checking cloud backup and uploading local changes."
        case .synced:
            return "Charts are backed up."
        case .failed(let message):
            return message
        }
    }

    var systemImageName: String {
        switch self {
        case .unconfigured:
            return "icloud.slash"
        case .signedOut:
            return "person.crop.circle.badge.exclamationmark"
        case .offline:
            return "wifi.slash"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .synced:
            return "icloud.and.arrow.up.fill"
        case .failed:
            return "exclamationmark.icloud"
        }
    }

    var manualSyncTitle: String {
        switch self {
        case .unconfigured:
            return "Unavailable"
        case .signedOut:
            return "Sign In First"
        case .offline, .failed:
            return "Retry Sync"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Sync Now"
        }
    }

    var manualSyncSystemImageName: String {
        switch self {
        case .offline:
            return "wifi.exclamationmark"
        case .failed:
            return "arrow.clockwise"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        default:
            return "arrow.triangle.2.circlepath"
        }
    }

    var allowsManualSync: Bool {
        switch self {
        case .offline, .synced, .failed:
            return true
        case .unconfigured, .signedOut, .syncing:
            return false
        }
    }

    var manualSyncDisabledReason: String? {
        switch self {
        case .unconfigured:
            return "Cloud backup is not configured in this build."
        case .signedOut:
            return "Sign in to enable cloud backup."
        case .syncing:
            return nil
        case .offline, .synced, .failed:
            return nil
        }
    }
}

actor ChartCloudSyncService {
    private let client: SupabaseClient
    private let sessionProvider: any IChartSupabaseSessionProviding
    private var lastIssuedRevision: Int64 = 0

    init(client: SupabaseClient, sessionProvider: any IChartSupabaseSessionProviding) {
        self.client = client
        self.sessionProvider = sessionProvider
    }

    func bootstrap(localSnapshot: ChartLibrarySnapshot) async throws -> ChartCloudSyncResult {
        try await syncNow(localSnapshot: localSnapshot)
    }

    func syncNow(localSnapshot: ChartLibrarySnapshot) async throws -> ChartCloudSyncResult {
        let ownerID = try await currentUserID()
        let scopedLocalSnapshot = ChartCloudMerge.localSnapshotForSync(localSnapshot, ownerID: ownerID)
        let remoteLibrary = try await pullRemoteSnapshot(ownerID: ownerID)
        let mergedSnapshot = ChartCloudMerge.mergedSnapshot(
            local: scopedLocalSnapshot,
            remote: remoteLibrary,
            ownerID: ownerID
        )
        let lastBackupAt: Date
        let snapshotToReturn: ChartLibrarySnapshot
        do {
            lastBackupAt = try await pushLocalSnapshot(mergedSnapshot, ownerID: ownerID)
            snapshotToReturn = mergedSnapshot
        } catch {
            guard Self.shouldRestoreRemoteForLegacyOwnerlessSnapshot(
                after: error,
                localSnapshot: localSnapshot,
                scopedLocalSnapshot: scopedLocalSnapshot
            ) else {
                throw error
            }

            let ownerScopedEmptySnapshot = ChartCloudMerge.emptySnapshotForOwner(
                basedOn: localSnapshot,
                ownerID: ownerID
            )
            let remoteOnlySnapshot = ChartCloudMerge.mergedSnapshot(
                local: ownerScopedEmptySnapshot,
                remote: remoteLibrary,
                ownerID: ownerID
            )
            lastBackupAt = try await pushLocalSnapshot(remoteOnlySnapshot, ownerID: ownerID)
            snapshotToReturn = remoteOnlySnapshot
        }

        var updatedSnapshot = snapshotToReturn
        updatedSnapshot.cloudMetadata.lastRemoteBackupAt = lastBackupAt
        updatedSnapshot.cloudMetadata.lastSyncAt = Date()
        updatedSnapshot.cloudMetadata.ownerID = ownerID
        return ChartCloudSyncResult(snapshot: updatedSnapshot, lastRemoteBackupAt: lastBackupAt)
    }

    @discardableResult
    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot) async throws -> ChartCloudPushResult {
        let ownerID = try await currentUserID()
        let scopedSnapshot = ChartCloudMerge.localSnapshotForSync(snapshot, ownerID: ownerID)
        let lastBackupAt = try await pushLocalSnapshot(scopedSnapshot, ownerID: ownerID)
        return ChartCloudPushResult(ownerID: ownerID, lastRemoteBackupAt: lastBackupAt)
    }

    @discardableResult
    private func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, ownerID: UUID) async throws -> Date {
        for chart in snapshot.charts {
            try await push(chart: chart, ownerID: ownerID)
        }

        for tombstone in snapshot.deletionTombstones {
            if snapshot.charts.contains(where: { $0.id == tombstone.chartID }) {
                continue
            }

            try await push(tombstone: tombstone, ownerID: ownerID)
        }

        return Date()
    }

    func pullRemoteSnapshot() async throws -> ChartCloudRemoteLibrary {
        let ownerID = try await currentUserID()
        return try await pullRemoteSnapshot(ownerID: ownerID)
    }

    private func pullRemoteSnapshot(ownerID: UUID) async throws -> ChartCloudRemoteLibrary {
        let documents: [ChartCloudDocumentRow] = try await client
            .from("chart_documents")
            .select()
            .eq("owner_id", value: ownerID)
            .execute()
            .value
        let snapshots: [ChartCloudSnapshotRow] = try await client
            .from("chart_snapshots")
            .select()
            .eq("owner_id", value: ownerID)
            .order("version", ascending: false)
            .execute()
            .value
        let snapshotsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let snapshotsByChartID = Dictionary(grouping: snapshots, by: \.chartID)
        var charts: [Chart] = []
        var tombstones: [ChartDeletionTombstone] = []

        for document in documents {
            if let deletedAt = document.deletedAtDate {
                tombstones.append(ChartDeletionTombstone(chartID: document.id, deletedAt: deletedAt))
                continue
            }

            let snapshot = document.latestSnapshotID.flatMap { snapshotsByID[$0] }
                ?? snapshotsByChartID[document.id]?.first

            if let snapshot {
                charts.append(try snapshot.chartJSON.decodeChart())
            }
        }

        let newestDocumentUpdate = documents.compactMap(\.updatedAtDate).max()
        let newestSnapshotUpdate = snapshots.compactMap(\.createdAtDate).max()
        let lastBackupAt = [newestDocumentUpdate, newestSnapshotUpdate].compactMap { $0 }.max()

        return ChartCloudRemoteLibrary(
            charts: charts,
            deletionTombstones: tombstones,
            lastRemoteBackupAt: lastBackupAt
        )
    }

    private func push(chart: Chart, ownerID: UUID) async throws {
        let revision = nextRevision(after: chart.updatedAt)
        let clientUpdatedAt = Self.remoteTimestamp(from: chart.updatedAt)
        let document = ChartCloudDocumentUpsert(
            id: chart.id,
            ownerID: ownerID,
            title: chart.title,
            layoutStyle: chart.layoutStyle.rawValue,
            deletedAt: nil,
            remoteRevision: revision,
            clientUpdatedAt: clientUpdatedAt
        )
        let proposedSnapshotID = UUID()

        try await client
            .from("chart_documents")
            .upsert(document, onConflict: "id")
            .execute()
        let snapshot = ChartCloudSnapshotInsert(
            id: proposedSnapshotID,
            chartID: chart.id,
            ownerID: ownerID,
            version: revision,
            chartJSON: try IChartJSONValue.chartPayload(for: chart),
            clientUpdatedAt: clientUpdatedAt
        )
        try await client
            .from("chart_snapshots")
            .upsert(snapshot, onConflict: "chart_id,version", ignoreDuplicates: true)
            .execute()
        let resolvedSnapshotID = try await existingSnapshotID(chartID: chart.id, version: revision) ?? proposedSnapshotID
        let update = ChartCloudDocumentLatestSnapshotUpdate(
            title: chart.title,
            layoutStyle: chart.layoutStyle.rawValue,
            latestSnapshotID: resolvedSnapshotID,
            deletedAt: nil,
            remoteRevision: revision,
            clientUpdatedAt: clientUpdatedAt,
            lastSnapshotAt: Self.remoteTimestamp(from: Date())
        )
        try await client
            .from("chart_documents")
            .update(update)
            .eq("id", value: chart.id)
            .execute()
    }

    private func existingSnapshotID(chartID: UUID, version: Int64) async throws -> UUID? {
        let rows: [ChartCloudSnapshotIdentityRow] = try await client
            .from("chart_snapshots")
            .select("id")
            .eq("chart_id", value: chartID)
            .eq("version", value: String(version))
            .execute()
            .value

        return rows.first?.id
    }

    private func push(tombstone: ChartDeletionTombstone, ownerID: UUID) async throws {
        let revision = nextRevision(after: tombstone.deletedAt)
        let deletedAt = Self.remoteTimestamp(from: tombstone.deletedAt)
        let document = ChartCloudDocumentUpsert(
            id: tombstone.chartID,
            ownerID: ownerID,
            title: "Deleted Chart",
            layoutStyle: ChartLayoutStyle.leadSheet.rawValue,
            deletedAt: deletedAt,
            remoteRevision: revision,
            clientUpdatedAt: deletedAt
        )

        try await client
            .from("chart_documents")
            .upsert(document, onConflict: "id")
            .execute()
        try await client
            .from("chart_documents")
            .update(
                ChartCloudDocumentDeletionUpdate(
                    latestSnapshotID: nil,
                    deletedAt: deletedAt,
                    remoteRevision: revision,
                    clientUpdatedAt: deletedAt
                )
            )
            .eq("id", value: tombstone.chartID)
            .execute()
    }

    private func currentUserID() async throws -> UUID {
        try await sessionProvider.currentUserID()
    }

    private func nextRevision(after date: Date) -> Int64 {
        let proposedRevision = max(
            Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        )
        let revision = max(proposedRevision, lastIssuedRevision + 1)
        lastIssuedRevision = revision
        return revision
    }

    private static func remoteTimestamp(from date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    private static func shouldRestoreRemoteForLegacyOwnerlessSnapshot(
        after error: Error,
        localSnapshot: ChartLibrarySnapshot,
        scopedLocalSnapshot: ChartLibrarySnapshot
    ) -> Bool {
        localSnapshot.cloudMetadata.ownerID == nil
            && localSnapshot.cloudMetadata.lastRemoteBackupAt != nil
            && scopedLocalSnapshot.cloudMetadata.ownerID == nil
            && isPermissionDeniedError(error)
    }

    private static func isPermissionDeniedError(_ error: Error) -> Bool {
        if let postgrestError = error as? PostgrestError {
            let text = normalizedErrorText(
                postgrestError.message,
                postgrestError.detail,
                postgrestError.hint,
                postgrestError.code
            )
            return isPermissionDeniedText(text)
        }

        if let authError = error as? AuthError {
            return isPermissionDeniedText(normalizedErrorText(authError.localizedDescription))
        }

        return isPermissionDeniedText(normalizedErrorText(error.localizedDescription))
    }

    private static func isPermissionDeniedText(_ text: String) -> Bool {
        text.contains("permission denied")
            || text.contains("row-level security")
            || text.contains("rls")
            || text.contains("403")
    }

    private static func normalizedErrorText(_ values: String?...) -> String {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct ChartCloudDocumentRow: Decodable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let layoutStyle: String
    let latestSnapshotID: UUID?
    let deletedAt: String?
    let remoteRevision: Int64
    let clientUpdatedAt: String?
    let createdAt: String?
    let updatedAt: String?

    var deletedAtDate: Date? { ChartCloudDateParser.date(from: deletedAt) }
    var updatedAtDate: Date? { ChartCloudDateParser.date(from: updatedAt) }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case layoutStyle = "layout_style"
        case latestSnapshotID = "latest_snapshot_id"
        case deletedAt = "deleted_at"
        case remoteRevision = "remote_revision"
        case clientUpdatedAt = "client_updated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct ChartCloudSnapshotRow: Decodable {
    let id: UUID
    let chartID: UUID
    let ownerID: UUID
    let version: Int64
    let chartJSON: IChartJSONValue
    let clientUpdatedAt: String?
    let createdAt: String?

    var createdAtDate: Date? { ChartCloudDateParser.date(from: createdAt) }

    enum CodingKeys: String, CodingKey {
        case id
        case chartID = "chart_id"
        case ownerID = "owner_id"
        case version
        case chartJSON = "chart_json"
        case clientUpdatedAt = "client_updated_at"
        case createdAt = "created_at"
    }
}

private struct ChartCloudSnapshotIdentityRow: Decodable {
    let id: UUID
}

private struct ChartCloudDocumentUpsert: Encodable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let layoutStyle: String
    let deletedAt: String?
    let remoteRevision: Int64
    let clientUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case layoutStyle = "layout_style"
        case deletedAt = "deleted_at"
        case remoteRevision = "remote_revision"
        case clientUpdatedAt = "client_updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ownerID, forKey: .ownerID)
        try container.encode(title, forKey: .title)
        try container.encode(layoutStyle, forKey: .layoutStyle)
        if let deletedAt {
            try container.encode(deletedAt, forKey: .deletedAt)
        } else {
            try container.encodeNil(forKey: .deletedAt)
        }
        try container.encode(remoteRevision, forKey: .remoteRevision)
        try container.encodeIfPresent(clientUpdatedAt, forKey: .clientUpdatedAt)
    }
}

private struct ChartCloudSnapshotInsert: Encodable {
    let id: UUID
    let chartID: UUID
    let ownerID: UUID
    let version: Int64
    let chartJSON: IChartJSONValue
    let clientUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case chartID = "chart_id"
        case ownerID = "owner_id"
        case version
        case chartJSON = "chart_json"
        case clientUpdatedAt = "client_updated_at"
    }
}

private struct ChartCloudDocumentLatestSnapshotUpdate: Encodable {
    let title: String
    let layoutStyle: String
    let latestSnapshotID: UUID
    let deletedAt: String?
    let remoteRevision: Int64
    let clientUpdatedAt: String?
    let lastSnapshotAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case layoutStyle = "layout_style"
        case latestSnapshotID = "latest_snapshot_id"
        case deletedAt = "deleted_at"
        case remoteRevision = "remote_revision"
        case clientUpdatedAt = "client_updated_at"
        case lastSnapshotAt = "last_snapshot_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(layoutStyle, forKey: .layoutStyle)
        try container.encode(latestSnapshotID, forKey: .latestSnapshotID)
        if let deletedAt {
            try container.encode(deletedAt, forKey: .deletedAt)
        } else {
            try container.encodeNil(forKey: .deletedAt)
        }
        try container.encode(remoteRevision, forKey: .remoteRevision)
        try container.encodeIfPresent(clientUpdatedAt, forKey: .clientUpdatedAt)
        try container.encodeIfPresent(lastSnapshotAt, forKey: .lastSnapshotAt)
    }
}

private struct ChartCloudDocumentDeletionUpdate: Encodable {
    let latestSnapshotID: UUID?
    let deletedAt: String
    let remoteRevision: Int64
    let clientUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case latestSnapshotID = "latest_snapshot_id"
        case deletedAt = "deleted_at"
        case remoteRevision = "remote_revision"
        case clientUpdatedAt = "client_updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let latestSnapshotID {
            try container.encode(latestSnapshotID, forKey: .latestSnapshotID)
        } else {
            try container.encodeNil(forKey: .latestSnapshotID)
        }
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(remoteRevision, forKey: .remoteRevision)
        try container.encodeIfPresent(clientUpdatedAt, forKey: .clientUpdatedAt)
    }
}

private enum ChartCloudDateParser {
    static func date(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        return fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

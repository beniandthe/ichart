import Foundation
import Supabase

struct ChartCloudRestoreOutcome {
    let syncResult: ChartCloudSyncResult
    let remoteChartCount: Int
    let backedUpChartCount: Int
    let tombstonedChartCount: Int
}

protocol ChartCloudSyncServicing: Sendable {
    func restoreFromCloud(localSnapshot: ChartLibrarySnapshot, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudRestoreOutcome
    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudPushResult
    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, forceRemoteWrite: Bool, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudPushResult
}

extension ChartCloudSyncServicing {
    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, forceRemoteWrite: Bool, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudPushResult {
        try await pushLocalSnapshot(snapshot, onProgress: onProgress)
    }
}

actor ChartCloudSyncService: ChartCloudSyncServicing {
    private let client: SupabaseClient
    private let currentUserIDProvider: () async throws -> UUID
    private var lastIssuedRevision: Int64 = 0

    init(client: SupabaseClient, sessionRefresher: IChartSupabaseSessionRefresher) {
        self.client = client
        self.currentUserIDProvider = { try await sessionRefresher.refreshIfNeeded().user.id }
    }

    init(client: SupabaseClient, currentUserIDProvider: @escaping () async throws -> UUID) {
        self.client = client
        self.currentUserIDProvider = currentUserIDProvider
    }

    func restoreFromCloud(localSnapshot: ChartLibrarySnapshot, onProgress: ChartCloudSyncProgressHandler? = nil) async throws -> ChartCloudRestoreOutcome {
        let ownerID = try await currentUserID(onProgress: onProgress)
        let scopedLocalSnapshot = ChartCloudMerge.localSnapshotForSync(localSnapshot, ownerID: ownerID)
        let remoteLibrary = try await pullRemoteSnapshot(ownerID: ownerID, onProgress: onProgress)
        await onProgress?(.mergingCharts)
        let mergedSnapshot = ChartCloudMerge.mergedSnapshot(
            local: scopedLocalSnapshot,
            remote: remoteLibrary,
            ownerID: ownerID
        )
        let backupOutcome: ChartCloudPushOutcome
        let snapshotToReturn: ChartLibrarySnapshot
        do {
            let backupSnapshot = ChartCloudMerge.snapshotForCloudBackup(mergedSnapshot, ownerID: ownerID)
            backupOutcome = try await pushLocalSnapshot(backupSnapshot, ownerID: ownerID, onProgress: onProgress)
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
            await onProgress?(.mergingCharts)
            let remoteOnlySnapshot = ChartCloudMerge.mergedSnapshot(
                local: ownerScopedEmptySnapshot,
                remote: remoteLibrary,
                ownerID: ownerID
            )
            let backupSnapshot = ChartCloudMerge.snapshotForCloudBackup(remoteOnlySnapshot, ownerID: ownerID)
            backupOutcome = try await pushLocalSnapshot(backupSnapshot, ownerID: ownerID, onProgress: onProgress)
            snapshotToReturn = remoteOnlySnapshot
        }

        var updatedSnapshot = snapshotToReturn
        for index in updatedSnapshot.charts.indices {
            let id = updatedSnapshot.charts[index].id
            guard backupOutcome.backedUpChartIDs.contains(id),
                  let digest = backupOutcome.acknowledgedContentSHA256ByChartID[id] else { continue }
            updatedSnapshot.charts[index].markBackedUpToCloud(ownerID: ownerID, at: backupOutcome.lastBackupAt)
            updatedSnapshot.charts[index].cloudBackupStatus.acknowledgedContentSHA256 = digest
        }
        // The private push result uses a sentinel when an empty library has no
        // prior backup. A read-only restore must preserve the optional date.
        let lastRemoteBackupAt = backupOutcome.didPerformRemoteWrites
            ? backupOutcome.lastBackupAt
            : updatedSnapshot.cloudMetadata.lastRemoteBackupAt
        updatedSnapshot.cloudMetadata.lastRemoteBackupAt = lastRemoteBackupAt
        updatedSnapshot.cloudMetadata.lastSyncAt = Date()
        updatedSnapshot.cloudMetadata.ownerID = ownerID
        return ChartCloudRestoreOutcome(
            syncResult: ChartCloudSyncResult(snapshot: updatedSnapshot, lastRemoteBackupAt: lastRemoteBackupAt),
            remoteChartCount: remoteLibrary.charts.count,
            backedUpChartCount: backupOutcome.backedUpChartIDs.count,
            tombstonedChartCount: backupOutcome.tombstonedChartIDs.count
        )
    }

    @discardableResult
    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, onProgress: ChartCloudSyncProgressHandler? = nil) async throws -> ChartCloudPushResult {
        try await pushLocalSnapshot(snapshot, forceRemoteWrite: false, onProgress: onProgress)
    }

    @discardableResult
    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, forceRemoteWrite: Bool, onProgress: ChartCloudSyncProgressHandler? = nil) async throws -> ChartCloudPushResult {
        let ownerID = try await currentUserID(onProgress: onProgress)
        let scopedSnapshot = ChartCloudMerge.localSnapshotForSync(snapshot, ownerID: ownerID)
        let backupSnapshot = ChartCloudMerge.snapshotForCloudBackup(scopedSnapshot, ownerID: ownerID)
        let outcome = try await pushLocalSnapshot(backupSnapshot, ownerID: ownerID, forceRemoteWrite: forceRemoteWrite, onProgress: onProgress)
        return ChartCloudPushResult(
            ownerID: ownerID,
            lastRemoteBackupAt: outcome.lastBackupAt,
            backedUpChartIDs: outcome.backedUpChartIDs,
            tombstonedChartIDs: outcome.tombstonedChartIDs,
            acknowledgedContentSHA256ByChartID: outcome.acknowledgedContentSHA256ByChartID,
            didPerformRemoteWrites: outcome.didPerformRemoteWrites
        )
    }

    @discardableResult
    private func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, ownerID: UUID, forceRemoteWrite: Bool = false, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudPushOutcome {
        var backedUpChartIDs: Set<Chart.ID> = []
        var tombstonedChartIDs: Set<Chart.ID> = []
        var acknowledgedContentSHA256ByChartID: [Chart.ID: String] = [:]
        var wroteCloudData = false

        for chart in snapshot.charts {
            let outcome = try await push(chart: chart, ownerID: ownerID, forceRemoteWrite: forceRemoteWrite, onProgress: onProgress)
            if outcome.wroteSnapshot { backedUpChartIDs.insert(chart.id) }
            acknowledgedContentSHA256ByChartID[chart.id] = outcome.contentSHA256
            wroteCloudData = wroteCloudData || outcome.wroteSnapshot
        }

        for tombstone in snapshot.deletionTombstones {
            if snapshot.charts.contains(where: { $0.id == tombstone.chartID }) {
                continue
            }

            try await push(tombstone: tombstone, ownerID: ownerID, onProgress: onProgress)
            tombstonedChartIDs.insert(tombstone.chartID)
            wroteCloudData = true
        }

        return ChartCloudPushOutcome(
            lastBackupAt: wroteCloudData ? Date() : snapshot.cloudMetadata.lastRemoteBackupAt
                ?? snapshot.charts.compactMap(\.cloudBackupStatus.lastBackedUpAt).max() ?? .distantPast,
            backedUpChartIDs: backedUpChartIDs,
            tombstonedChartIDs: tombstonedChartIDs,
            acknowledgedContentSHA256ByChartID: acknowledgedContentSHA256ByChartID,
            didPerformRemoteWrites: wroteCloudData
        )
    }

    func pullRemoteSnapshot() async throws -> ChartCloudRemoteLibrary {
        let ownerID = try await currentUserID(onProgress: nil)
        return try await pullRemoteSnapshot(ownerID: ownerID, onProgress: nil)
    }

    private func pullRemoteSnapshot(ownerID: UUID, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudRemoteLibrary {
        try await ChartCloudRemoteSnapshotReader(client: client).read(ownerID: ownerID, onProgress: onProgress)
    }

    private func push(chart: Chart, ownerID: UUID, forceRemoteWrite: Bool, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudChartPushOutcome {
        let chartPayload = try await ChartCloudSyncStageReporting.perform(.encodingSnapshot, onProgress: onProgress) {
            try IChartJSONValue.chartPayload(for: chart)
        }
        let digest = try ChartCloudContentIdentity.sha256(for: chartPayload)
        if !forceRemoteWrite, chart.cloudBackupStatus.ownerID == ownerID,
           chart.cloudBackupStatus.lastBackedUpAt != nil,
           ChartCloudContentIdentity.isValidSHA256(chart.cloudBackupStatus.acknowledgedContentSHA256),
           chart.cloudBackupStatus.acknowledgedContentSHA256 == digest {
            return ChartCloudChartPushOutcome(contentSHA256: digest, wroteSnapshot: false)
        }
        try Task.checkCancellation()
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

        try await ChartCloudSyncStageReporting.perform(.writingDocument, onProgress: onProgress) {
            try await client
                .from("chart_documents")
                .upsert(document, onConflict: "id")
                .execute()
        }
        let snapshot = ChartCloudSnapshotInsert(
            id: proposedSnapshotID,
            chartID: chart.id,
            ownerID: ownerID,
            version: revision,
            chartJSON: chartPayload,
            clientUpdatedAt: clientUpdatedAt
        )
        try await ChartCloudSyncStageReporting.perform(.writingSnapshot, onProgress: onProgress) {
            try await client
                .from("chart_snapshots")
                .upsert(snapshot, onConflict: "chart_id,version", ignoreDuplicates: true)
                .execute()
        }
        let resolvedSnapshotID = try await ChartCloudSyncStageReporting.perform(.resolvingSnapshot, onProgress: onProgress) {
            try await existingSnapshotID(chartID: chart.id, version: revision)
        } ?? proposedSnapshotID
        if resolvedSnapshotID != proposedSnapshotID {
            // A simultaneous device may have inserted the same millisecond
            // revision. Never acknowledge or link a different payload.
            let rows: [ChartCloudSnapshotRow] = try await ChartCloudSyncStageReporting.perform(.resolvingSnapshot, onProgress: onProgress) {
                try await client.from("chart_snapshots").select().eq("id", value: resolvedSnapshotID)
                    .eq("owner_id", value: ownerID).execute().value
            }
            guard rows.count == 1, let row = rows.first,
                  row.chartID == chart.id, row.ownerID == ownerID,
                  try ChartCloudContentIdentity.sha256(for: row.chartJSON) == digest else {
                throw ChartCloudSyncStageError(stage: .resolvingSnapshot, underlyingError: ChartCloudRemoteReadError.invalidSnapshot)
            }
        }
        let update = ChartCloudDocumentLatestSnapshotUpdate(
            title: chart.title,
            layoutStyle: chart.layoutStyle.rawValue,
            latestSnapshotID: resolvedSnapshotID,
            deletedAt: nil,
            remoteRevision: revision,
            clientUpdatedAt: clientUpdatedAt,
            lastSnapshotAt: Self.remoteTimestamp(from: Date())
        )
        let linkedRows: [ChartCloudDocumentLinkReceipt] = try await ChartCloudSyncStageReporting.perform(.linkingSnapshot, onProgress: onProgress) {
            try await client
                .from("chart_documents")
                .update(update)
                .eq("id", value: chart.id)
                .eq("owner_id", value: ownerID)
                .select("id,owner_id,latest_snapshot_id")
                .execute()
                .value
        }
        guard linkedRows.count == 1, let linked = linkedRows.first,
              linked.id == chart.id, linked.ownerID == ownerID, linked.latestSnapshotID == resolvedSnapshotID else {
            throw ChartCloudSyncStageError(stage: .linkingSnapshot, underlyingError: ChartCloudRemoteReadError.missingSnapshot)
        }
        try Task.checkCancellation()
        return ChartCloudChartPushOutcome(contentSHA256: digest, wroteSnapshot: true)
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

    private func push(tombstone: ChartDeletionTombstone, ownerID: UUID, onProgress: ChartCloudSyncProgressHandler?) async throws {
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

        try await ChartCloudSyncStageReporting.perform(.writingDeletion, onProgress: onProgress) {
            try await client
                .from("chart_documents")
                .upsert(document, onConflict: "id")
                .execute()
        }
        try await ChartCloudSyncStageReporting.perform(.writingDeletion, onProgress: onProgress) {
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
    }

    private func currentUserID(onProgress: ChartCloudSyncProgressHandler?) async throws -> UUID {
        try await ChartCloudSyncStageReporting.perform(.preparingSession, onProgress: onProgress) {
            try await currentUserIDProvider()
        }
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
        if let stagedError = error as? ChartCloudSyncStageError {
            return isPermissionDeniedError(stagedError.underlyingError)
        }
        if let postgrestError = error as? PostgrestError {
            let text = normalizedErrorText(
                postgrestError.message,
                postgrestError.details,
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

/// Reads the current cloud library without downloading every historical ink
/// archive. Stable keyset pages also avoid the server's per-response row cap.
struct ChartCloudRemoteSnapshotReader {
    let client: SupabaseClient
    static let pageSize = 100

    func read(ownerID: UUID, onProgress: ChartCloudSyncProgressHandler? = nil) async throws -> ChartCloudRemoteLibrary {
        let documents = try await readDocuments(ownerID: ownerID, onProgress: onProgress)
        let activeDocuments = documents.filter { $0.deletedAt == nil }
        let requiredIDs = Set(activeDocuments.compactMap(\.latestSnapshotID)).sorted { $0.uuidString < $1.uuidString }
        var snapshotsByID: [UUID: ChartCloudSnapshotRow] = [:]

        for start in stride(from: 0, to: requiredIDs.count, by: Self.pageSize) {
            let ids = Array(requiredIDs[start..<min(start + Self.pageSize, requiredIDs.count)])
            let rows = try await readRequiredSnapshots(ids: ids, ownerID: ownerID, onProgress: onProgress)
            for row in rows { snapshotsByID[row.id] = row }
        }

        var charts: [Chart] = []
        var tombstones: [ChartDeletionTombstone] = []
        var snapshotDates: [Date] = []
        await onProgress?(.decodingCharts)
        for document in documents {
            try Task.checkCancellation()
            if document.deletedAt != nil {
                guard let deletedAt = document.deletedAtDate else {
                    throw readError(.invalidDocument, stage: .readingDocuments)
                }
                tombstones.append(ChartDeletionTombstone(chartID: document.id, deletedAt: deletedAt))
                continue
            }
            let snapshot: ChartCloudSnapshotRow
            if let id = document.latestSnapshotID {
                guard let required = snapshotsByID[id] else {
                    throw readError(.missingSnapshot, stage: .readingSnapshots)
                }
                snapshot = required
            } else {
                // Older documents may predate the latest-snapshot pointer.
                // Fetch only their newest revision, never the owner's history.
                snapshot = try await readLegacyLatestSnapshot(documentID: document.id, ownerID: ownerID, onProgress: onProgress)
            }
            guard snapshot.ownerID == ownerID, snapshot.chartID == document.id else {
                throw readError(.invalidSnapshot, stage: .readingSnapshots)
            }
            var chart = try await ChartCloudSyncStageReporting.perform(.decodingCharts, onProgress: nil) {
                try snapshot.chartJSON.decodeChart()
            }
            guard chart.id == document.id else {
                throw readError(.invalidSnapshot, stage: .decodingCharts)
            }
            // A decoder can migrate defaults, notation or ink. Acknowledge the
            // stored payload so changed decoded content uploads once on backup.
            let digest = try ChartCloudContentIdentity.sha256(for: snapshot.chartJSON)
            chart.markBackedUpToCloud(ownerID: ownerID, at: document.updatedAtDate ?? snapshot.createdAtDate ?? Date())
            chart.cloudBackupStatus.acknowledgedContentSHA256 = digest
            charts.append(chart)
            if let createdAt = snapshot.createdAtDate { snapshotDates.append(createdAt) }
        }
        let lastBackupAt = [documents.compactMap(\.updatedAtDate).max(), snapshotDates.max()].compactMap { $0 }.max()
        return ChartCloudRemoteLibrary(charts: charts, deletionTombstones: tombstones, lastRemoteBackupAt: lastBackupAt)
    }

    private func readDocuments(ownerID: UUID, onProgress: ChartCloudSyncProgressHandler?) async throws -> [ChartCloudDocumentRow] {
        var documents: [ChartCloudDocumentRow] = []
        var cursor: UUID?
        while true {
            try Task.checkCancellation()
            let after = cursor
            let page: [ChartCloudDocumentRow] = try await ChartCloudSyncStageReporting.perform(.readingDocuments, onProgress: onProgress) {
                var query = client.from("chart_documents").select().eq("owner_id", value: ownerID)
                if let after { query = query.gt("id", value: after) }
                return try await query.order("id").limit(Self.pageSize).execute().value
            }
            try Task.checkCancellation()
            guard !page.isEmpty else { break }
            var previous = cursor?.uuidString
            for document in page {
                guard document.ownerID == ownerID, previous.map({ document.id.uuidString > $0 }) ?? true else {
                    throw readError(.invalidDocument, stage: .readingDocuments)
                }
                previous = document.id.uuidString
            }
            documents.append(contentsOf: page)
            cursor = page.last?.id
        }
        return documents
    }

    private func readRequiredSnapshots(ids: [UUID], ownerID: UUID, onProgress: ChartCloudSyncProgressHandler?) async throws -> [ChartCloudSnapshotRow] {
        var remaining = Set(ids)
        var rows: [ChartCloudSnapshotRow] = []
        var cursor: UUID?
        while !remaining.isEmpty {
            try Task.checkCancellation()
            let after = cursor
            let page: [ChartCloudSnapshotRow] = try await ChartCloudSyncStageReporting.perform(.readingSnapshots, onProgress: onProgress) {
                var query = client.from("chart_snapshots").select().eq("owner_id", value: ownerID).in("id", values: ids.map(\.uuidString))
                if let after { query = query.gt("id", value: after) }
                return try await query.order("id").limit(Self.pageSize).execute().value
            }
            try Task.checkCancellation()
            guard !page.isEmpty else { throw readError(.missingSnapshot, stage: .readingSnapshots) }
            var previous = cursor?.uuidString
            for row in page {
                guard row.ownerID == ownerID, remaining.remove(row.id) != nil,
                      previous.map({ row.id.uuidString > $0 }) ?? true else {
                    throw readError(.invalidSnapshot, stage: .readingSnapshots)
                }
                previous = row.id.uuidString
            }
            rows.append(contentsOf: page)
            cursor = page.last?.id
        }
        return rows
    }

    private func readLegacyLatestSnapshot(documentID: UUID, ownerID: UUID, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudSnapshotRow {
        let rows: [ChartCloudSnapshotRow] = try await ChartCloudSyncStageReporting.perform(.readingSnapshots, onProgress: onProgress) {
            try await client.from("chart_snapshots").select().eq("owner_id", value: ownerID).eq("chart_id", value: documentID)
                .order("version", ascending: false).order("id", ascending: false).limit(1).execute().value
        }
        try Task.checkCancellation()
        guard rows.count == 1, let row = rows.first else {
            throw readError(.missingSnapshot, stage: .readingSnapshots)
        }
        return row
    }

    private func readError(_ error: ChartCloudRemoteReadError, stage: ChartCloudSyncStage) -> ChartCloudSyncStageError {
        ChartCloudSyncStageError(stage: stage, underlyingError: error)
    }
}

enum ChartCloudRemoteReadError: Error {
    case invalidDocument
    case missingSnapshot
    case invalidSnapshot
}

private struct ChartCloudPushOutcome {
    var lastBackupAt: Date
    var backedUpChartIDs: Set<Chart.ID>
    var tombstonedChartIDs: Set<Chart.ID>
    var acknowledgedContentSHA256ByChartID: [Chart.ID: String]
    var didPerformRemoteWrites: Bool
}

private struct ChartCloudChartPushOutcome {
    var contentSHA256: String
    var wroteSnapshot: Bool
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

private struct ChartCloudDocumentLinkReceipt: Decodable {
    let id: UUID
    let ownerID: UUID
    let latestSnapshotID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case latestSnapshotID = "latest_snapshot_id"
    }
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

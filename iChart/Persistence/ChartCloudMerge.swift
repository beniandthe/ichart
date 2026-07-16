import Foundation

struct ChartCloudSyncResult: Equatable {
    var snapshot: ChartLibrarySnapshot
    var lastRemoteBackupAt: Date?
}

struct ChartCloudPushResult: Equatable {
    var ownerID: UUID
    var lastRemoteBackupAt: Date
    var backedUpChartIDs: Set<Chart.ID>
    var tombstonedChartIDs: Set<Chart.ID>
}

struct ChartCloudRemoteLibrary: Equatable {
    var charts: [Chart]
    var deletionTombstones: [ChartDeletionTombstone]
    var lastRemoteBackupAt: Date?
}

enum ChartCloudMerge {
    static func mergedSnapshot(
        local: ChartLibrarySnapshot,
        remote: ChartCloudRemoteLibrary,
        ownerID: UUID? = nil,
        now: Date = Date()
    ) -> ChartLibrarySnapshot {
        var chartsByID: [Chart.ID: Chart] = Dictionary(uniqueKeysWithValues: local.charts.map { ($0.id, $0) })
        let localTombstones = newestTombstones(local.deletionTombstones)
        let remoteTombstones = newestTombstones(remote.deletionTombstones)
        let allChartIDs = Set(local.charts.map(\.id))
            .union(remote.charts.map(\.id))
            .union(localTombstones.keys)
            .union(remoteTombstones.keys)

        for chartID in allChartIDs {
            let localChart = local.charts.first { $0.id == chartID }
            let remoteChart = remote.charts.first { $0.id == chartID }
            let localDeletedAt = localTombstones[chartID]?.deletedAt
            let remoteDeletedAt = remoteTombstones[chartID]?.deletedAt
            let newestDeletion = [localDeletedAt, remoteDeletedAt].compactMap { $0 }.max()
            let newestActiveUpdate = [localChart?.updatedAt, remoteChart?.updatedAt].compactMap { $0 }.max()

            if let newestDeletion,
               newestDeletion >= (newestActiveUpdate ?? .distantPast) {
                chartsByID.removeValue(forKey: chartID)
                continue
            }

            if let localChart, let remoteChart {
                chartsByID[chartID] = remoteChart.updatedAt > localChart.updatedAt ? remoteChart : localChart
            } else if let remoteChart {
                chartsByID[chartID] = remoteChart
            } else if let localChart {
                chartsByID[chartID] = localChart
            }
        }

        let mergedCharts = Array(chartsByID.values)
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

                return lhs.updatedAt > rhs.updatedAt
            }
        let mergedTombstones = newestTombstones(local.deletionTombstones + remote.deletionTombstones)
            .values
            .sorted { $0.deletedAt > $1.deletedAt }
        let selectedChartID = mergedCharts.contains { $0.id == local.selectedChartID }
            ? local.selectedChartID
            : mergedCharts.first?.id

        return ChartLibrarySnapshot(
            charts: mergedCharts,
            selectedChartID: selectedChartID,
            entitlements: local.entitlements,
            deletionTombstones: mergedTombstones,
            cloudMetadata: ChartCloudMetadata(
                ownerID: ownerID ?? local.cloudMetadata.ownerID,
                lastSyncAt: now,
                lastRemoteBackupAt: remote.lastRemoteBackupAt ?? local.cloudMetadata.lastRemoteBackupAt
            ),
            projects: local.projects
        )
    }

    static func localSnapshotForSync(
        _ snapshot: ChartLibrarySnapshot,
        ownerID: UUID
    ) -> ChartLibrarySnapshot {
        guard let previousOwnerID = snapshot.cloudMetadata.ownerID,
              previousOwnerID != ownerID else {
            return snapshot
        }

        return emptySnapshotForOwner(basedOn: snapshot, ownerID: ownerID)
    }

    static func snapshotForCloudBackup(
        _ snapshot: ChartLibrarySnapshot,
        ownerID: UUID
    ) -> ChartLibrarySnapshot {
        ChartLibrarySnapshot(
            charts: snapshot.charts.filter { $0.shouldBackUpToCloud(for: ownerID) },
            selectedChartID: snapshot.selectedChartID,
            entitlements: snapshot.entitlements,
            deletionTombstones: snapshot.deletionTombstones.filter(\.shouldSyncToCloud),
            cloudMetadata: snapshot.cloudMetadata,
            projects: snapshot.projects
        )
    }

    static func emptySnapshotForOwner(
        basedOn snapshot: ChartLibrarySnapshot,
        ownerID: UUID
    ) -> ChartLibrarySnapshot {
        ChartLibrarySnapshot(
            charts: [],
            selectedChartID: nil,
            entitlements: snapshot.entitlements,
            deletionTombstones: [],
            cloudMetadata: ChartCloudMetadata(ownerID: ownerID)
        )
    }

    private static func newestTombstones(
        _ tombstones: [ChartDeletionTombstone]
    ) -> [Chart.ID: ChartDeletionTombstone] {
        Dictionary(grouping: tombstones, by: \.chartID).compactMapValues { grouped in
            grouped.max { $0.deletedAt < $1.deletedAt }
        }
    }
}

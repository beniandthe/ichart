import Foundation

struct ChartLibrarySnapshot: Codable, Hashable {
    var charts: [Chart]
    var selectedChartID: Chart.ID?
    var entitlements: AppEntitlements
    var deletionTombstones: [ChartDeletionTombstone]
    var cloudMetadata: ChartCloudMetadata
    var projects: [ChartProject]

    init(
        charts: [Chart],
        selectedChartID: Chart.ID?,
        entitlements: AppEntitlements,
        deletionTombstones: [ChartDeletionTombstone] = [],
        cloudMetadata: ChartCloudMetadata = ChartCloudMetadata(),
        projects: [ChartProject] = []
    ) {
        self.charts = charts
        self.selectedChartID = selectedChartID
        self.entitlements = entitlements
        self.deletionTombstones = deletionTombstones
        self.cloudMetadata = cloudMetadata
        self.projects = projects
    }

    static var preview: ChartLibrarySnapshot {
        let charts = ChartSamples.previewCharts
        return ChartLibrarySnapshot(
            charts: charts,
            selectedChartID: charts.first?.id,
            entitlements: .free
        )
    }

    static var empty: ChartLibrarySnapshot {
        ChartLibrarySnapshot(
            charts: [],
            selectedChartID: nil,
            entitlements: .free
        )
    }

    private enum CodingKeys: String, CodingKey {
        case charts
        case selectedChartID
        case entitlements
        case deletionTombstones
        case cloudMetadata
        case projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        charts = try container.decode([Chart].self, forKey: .charts)
        selectedChartID = try container.decodeIfPresent(Chart.ID.self, forKey: .selectedChartID)
        entitlements = try container.decode(AppEntitlements.self, forKey: .entitlements)
        deletionTombstones = try container.decodeIfPresent(
            [ChartDeletionTombstone].self,
            forKey: .deletionTombstones
        ) ?? []
        cloudMetadata = try container.decodeIfPresent(
            ChartCloudMetadata.self,
            forKey: .cloudMetadata
        ) ?? ChartCloudMetadata()
        projects = try container.decodeIfPresent([ChartProject].self, forKey: .projects) ?? []
    }
}

struct ChartDeletionTombstone: Codable, Hashable, Identifiable {
    var chartID: Chart.ID
    var deletedAt: Date

    var id: Chart.ID { chartID }
}

struct ChartCloudMetadata: Codable, Hashable {
    var ownerID: UUID?
    var lastSyncAt: Date?
    var lastRemoteBackupAt: Date?

    init(ownerID: UUID? = nil, lastSyncAt: Date? = nil, lastRemoteBackupAt: Date? = nil) {
        self.ownerID = ownerID
        self.lastSyncAt = lastSyncAt
        self.lastRemoteBackupAt = lastRemoteBackupAt
    }
}

protocol ChartRepository {
    var savesSnapshotsOffMainThread: Bool { get }

    func loadSnapshot() throws -> ChartLibrarySnapshot?
    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws
}

extension ChartRepository {
    var savesSnapshotsOffMainThread: Bool { false }
}

struct InMemoryChartRepository: ChartRepository {
    var snapshot: ChartLibrarySnapshot = .preview

    func loadSnapshot() throws -> ChartLibrarySnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {
        _ = snapshot
    }
}

struct FileChartRepository: ChartRepository {
    let url: URL
    private let fileManager: FileManager

    var savesSnapshotsOffMainThread: Bool { true }

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func loadSnapshot() throws -> ChartLibrarySnapshot? {
        guard fileManager.fileExists(atPath: url.fileSystemPath) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try ChartPersistenceCoders.decoder.decode(ChartLibrarySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try ChartPersistenceCoders.encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}

private extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
    }
}

extension FileChartRepository {
    static func live(fileManager: FileManager = .default) -> FileChartRepository {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL.appendingPathComponent("iChart", isDirectory: true)
        let snapshotURL = baseDirectory.appendingPathComponent("library-state.json")

        return FileChartRepository(url: snapshotURL, fileManager: fileManager)
    }
}

enum ChartPersistenceCoders {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let interval = try container.decode(Double.self)
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        return decoder
    }()
}

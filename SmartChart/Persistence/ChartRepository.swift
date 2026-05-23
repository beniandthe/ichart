import Foundation

struct ChartLibrarySnapshot: Codable, Hashable {
    var charts: [Chart]
    var selectedChartID: Chart.ID?
    var entitlements: AppEntitlements

    static var preview: ChartLibrarySnapshot {
        let charts = ChartSamples.previewCharts
        return ChartLibrarySnapshot(
            charts: charts,
            selectedChartID: charts.first?.id,
            entitlements: .free
        )
    }
}

protocol ChartRepository {
    func loadSnapshot() throws -> ChartLibrarySnapshot?
    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws
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

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func loadSnapshot() throws -> ChartLibrarySnapshot? {
        guard fileManager.fileExists(atPath: url.fileSystemPath) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(ChartLibrarySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try Self.encoder.encode(snapshot)
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

        let baseDirectory = applicationSupportURL.appendingPathComponent("SmartChart", isDirectory: true)
        let snapshotURL = baseDirectory.appendingPathComponent("library-state.json")

        return FileChartRepository(url: snapshotURL, fileManager: fileManager)
    }
}

private extension FileChartRepository {
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

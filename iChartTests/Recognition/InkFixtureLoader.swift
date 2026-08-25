import Foundation
@testable import iChart

typealias InkFixture = InkFixtureDocument

enum InkFixtureLoader {
    static let fullInkFixtureArchiveEnvironmentVariable = "ICHART_FULL_INK_FIXTURES"

    static let defaultRegressionFixtureNames = [
        "C",
        "Bb",
        "FSharp",
        "CMinor",
        "CMinor7",
        "Db7b9",
        "GSlashB",
        "C7Flat5",
        "C7Sharp5",
        "C7Sharp9",
        "C7Flat13",
        "C7Sharp11",
        "C7alt",
        "C7sus",
        "CMinor6",
        "C6Captured01",
        "C9Captured01",
        "CMinorMajor7"
    ]

    static let trustAcceptanceFixtureNames = uniqueFixtureNames(defaultRegressionFixtureNames + [
        "A",
        "B",
        "D",
        "E",
        "F",
        "G",
        "ACaptured01",
        "BCaptured01",
        "DCaptured01",
        "ECaptured01",
        "FCaptured01",
        "GCaptured01",
        "DFlatCaptured01",
        "DFlatMinorCaptured01",
        "DFlat7susCaptured03",
        "EFlatCaptured01",
        "FSharpCaptured01",
        "BFlatMinor7Captured01",
        "FSharp7Captured01",
        "GSlashBCaptured01",
        "DSlashFSharpCaptured01",
        "FSlashACaptured01",
        "BFlatSlashDCaptured01",
        "CMajor7",
        "CMajor7Captured01",
        "CMajor9Captured01",
        "C7susCaptured03",
        "GsusCaptured01",
        "FSharpsus4Captured03",
        "C7Flat9Captured01",
        "C7Sharp11Captured01",
        "C7altCaptured03",
        "ChordRepeatCaptured01"
    ])

    static var shouldRunFullInkFixtureArchiveTests: Bool {
        guard let value = ProcessInfo.processInfo.environment[fullInkFixtureArchiveEnvironmentVariable] else {
            return false
        }

        return ["1", "true", "yes"].contains(value.lowercased())
    }

    static func load(_ name: String, file: StaticString = #filePath) throws -> InkFixture {
        let corpus = try fixtureCorpus(relativeTo: file)
        if let fixture = corpus.fixturesByFilename[name] {
            return fixture
        }

        let fixtureURL = fixturesDirectoryURL(relativeTo: file)
            .appendingPathComponent("\(name).json")
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            userInfo: [NSFilePathErrorKey: fixtureURL.path]
        )
    }

    static func loadAll(file: StaticString = #filePath) throws -> [InkFixture] {
        try fixtureCorpus(relativeTo: file).fixtures
    }

    static func loadDefaultRegressionFixtures(file: StaticString = #filePath) throws -> [InkFixture] {
        let corpus = try fixtureCorpus(relativeTo: file)
        return try defaultRegressionFixtureNames.map { fixtureName in
            guard let fixture = corpus.fixturesByFilename[fixtureName] else {
                let fixtureURL = fixturesDirectoryURL(relativeTo: file)
                    .appendingPathComponent("\(fixtureName).json")
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoSuchFileError,
                    userInfo: [NSFilePathErrorKey: fixtureURL.path]
                )
            }
            return fixture
        }
    }

    static func loadTrustAcceptanceFixtures(file: StaticString = #filePath) throws -> [InkFixture] {
        let corpus = try fixtureCorpus(relativeTo: file)
        return try trustAcceptanceFixtureNames.map { fixtureName in
            guard let fixture = corpus.fixturesByFilename[fixtureName] else {
                let fixtureURL = fixturesDirectoryURL(relativeTo: file)
                    .appendingPathComponent("\(fixtureName).json")
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoSuchFileError,
                    userInfo: [NSFilePathErrorKey: fixtureURL.path]
                )
            }
            return fixture
        }
    }

    static func fixtureNames(file: StaticString = #filePath) throws -> [String] {
        try fixtureCorpus(relativeTo: file).fixtureNames
    }

    private static let cacheLock = NSLock()
    private static var fixtureCorpusCache: [String: FixtureCorpus] = [:]

    private static func fixtureCorpus(relativeTo file: StaticString) throws -> FixtureCorpus {
        let directoryURL = fixturesDirectoryURL(relativeTo: file).standardizedFileURL
        let cacheKey = directoryURL.path

        cacheLock.lock()
        if let cachedCorpus = fixtureCorpusCache[cacheKey] {
            cacheLock.unlock()
            return cachedCorpus
        }
        cacheLock.unlock()

        let loadedCorpus = try loadFixtureCorpus(from: directoryURL)

        cacheLock.lock()
        if let cachedCorpus = fixtureCorpusCache[cacheKey] {
            cacheLock.unlock()
            return cachedCorpus
        }
        fixtureCorpusCache[cacheKey] = loadedCorpus
        cacheLock.unlock()

        return loadedCorpus
    }

    private static func loadFixtureCorpus(from directoryURL: URL) throws -> FixtureCorpus {
        let fixtureURLs = try fixtureURLs(in: directoryURL)
        var fixtures: [InkFixture] = []
        var fixtureNames: [String] = []
        var fixturesByFilename: [String: InkFixture] = [:]

        fixtures.reserveCapacity(fixtureURLs.count)
        fixtureNames.reserveCapacity(fixtureURLs.count)
        fixturesByFilename.reserveCapacity(fixtureURLs.count)

        for fixtureURL in fixtureURLs {
            let data = try Data(contentsOf: fixtureURL)
            let fixture = try JSONDecoder().decode(InkFixture.self, from: data)
            let fixtureName = fixtureURL.deletingPathExtension().lastPathComponent

            fixtures.append(fixture)
            fixtureNames.append(fixtureName)
            fixturesByFilename[fixtureName] = fixture
        }

        return FixtureCorpus(
            fixtures: fixtures,
            fixtureNames: fixtureNames,
            fixturesByFilename: fixturesByFilename
        )
    }

    private static func fixtureURLs(in directoryURL: URL) throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    private static func fixturesDirectoryURL(relativeTo file: StaticString) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Ink")
    }

    private static func uniqueFixtureNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { name in
            seen.insert(name).inserted
        }
    }
}

private struct FixtureCorpus {
    let fixtures: [InkFixture]
    let fixtureNames: [String]
    let fixturesByFilename: [String: InkFixture]
}

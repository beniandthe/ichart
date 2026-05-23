import Foundation
@testable import SmartChart

typealias InkFixture = InkFixtureDocument

enum InkFixtureLoader {
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
}

private struct FixtureCorpus {
    let fixtures: [InkFixture]
    let fixtureNames: [String]
    let fixturesByFilename: [String: InkFixture]
}

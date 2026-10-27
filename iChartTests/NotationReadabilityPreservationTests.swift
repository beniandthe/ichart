import Foundation
import XCTest
@testable import iChart

/// Optional local upgrade gate. Private device data stays in ignored `.build`;
/// failure messages identify field paths and never include chart contents.
final class NotationReadabilityPreservationTests: XCTestCase {
    func testLocalSnapshotReopensWithoutLosingExistingFields() throws {
        let library = try fixtureLibraryDirectory()
        let sourceURL = library.appendingPathComponent("Application Support/iChart/library-state.json")
        let sourceData = try Data(contentsOf: sourceURL)
        let originalJSON = try JSONSerialization.jsonObject(with: sourceData)
        let snapshot = try XCTUnwrap(FileChartRepository(url: sourceURL).loadSnapshot())
        let rawCharts = try chartObjects(in: originalJSON)

        XCTAssertFalse(rawCharts.isEmpty, "The local preservation snapshot must contain charts.")
        XCTAssertEqual(snapshot.charts.count, rawCharts.count)
        XCTAssertEqual(Set(snapshot.charts.map(\.id)).count, rawCharts.count)
        for (chart, rawChart) in zip(snapshot.charts, rawCharts) {
            XCTAssertEqual(chart.notationReadability.rawValue, rawChart["notationReadability"] as? String ?? "standard")
            XCTAssertEqual(chart.repeatWings, rawChart["repeatWings"] as? Bool ?? false)
        }

        let temporaryDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let savedURL = temporaryDirectory.appendingPathComponent("library-state.json")
        let repository = FileChartRepository(url: savedURL)
        try repository.saveSnapshot(snapshot)
        let reopened = try XCTUnwrap(repository.loadSnapshot())
        XCTAssertTrue(reopened == snapshot, "The persisted snapshot changed during save/reopen.")

        let savedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: savedURL))
        assertSameJSON(originalJSON, savedJSON, allowsNewDefaultAppearance: true)
        XCTAssertTrue(try Data(contentsOf: sourceURL) == sourceData, "The fixture must remain read-only.")
    }

    func testChangingReadabilityOnLocalSnapshotPreservesMusicInkAndDensity() throws {
        let library = try fixtureLibraryDirectory()
        let sourceURL = library.appendingPathComponent("Application Support/iChart/library-state.json")
        let sourceData = try Data(contentsOf: sourceURL)
        let originalJSON = try JSONSerialization.jsonObject(with: sourceData)
        var snapshot = try XCTUnwrap(FileChartRepository(url: sourceURL).loadSnapshot())
        for index in snapshot.charts.indices {
            snapshot.charts[index].setNotationReadability(.performance)
            snapshot.charts[index].setRepeatWings(true)
        }

        let temporaryDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let savedURL = temporaryDirectory.appendingPathComponent("library-state.json")
        let repository = FileChartRepository(url: savedURL)
        try repository.saveSnapshot(snapshot)
        let reopened = try XCTUnwrap(repository.loadSnapshot())
        XCTAssertEqual(reopened.charts.count, try chartObjects(in: originalJSON).count)
        XCTAssertTrue(reopened.charts.allSatisfy { $0.notationReadability == .performance && $0.repeatWings })
        XCTAssertTrue(reopened == snapshot, "Readability choices changed during save/reopen.")

        let savedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: savedURL))
        assertSameJSON(
            try removingAppearanceEditFields(from: originalJSON),
            try removingAppearanceEditFields(from: savedJSON)
        )
        XCTAssertTrue(try Data(contentsOf: sourceURL) == sourceData, "The fixture must remain read-only.")
    }

#if canImport(UIKit)
    func testLocalPDFAndSetlistManifestsRetainIdentityMetadataAndDocumentBytes() throws {
        let library = try fixtureLibraryDirectory()
        let pdfDirectory = library.appendingPathComponent("Application Support/iChart/PDF Library", isDirectory: true)
        let manifestURL = pdfDirectory.appendingPathComponent("pdf-library.json")
        let sourceData = try Data(contentsOf: manifestURL)
        let items = try ChartPersistenceCoders.decoder.decode([IChartPDFLibraryItem].self, from: sourceData)
        let reencodedData = try ChartPersistenceCoders.encoder.encode(items)
        let reopened = try ChartPersistenceCoders.decoder.decode([IChartPDFLibraryItem].self, from: reencodedData)
        XCTAssertFalse(items.isEmpty, "The local PDF preservation fixture must contain documents.")
        XCTAssertTrue(items == reopened, "PDF identity or metadata changed during round trip.")
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        assertSameJSON(
            try JSONSerialization.jsonObject(with: sourceData),
            try JSONSerialization.jsonObject(with: reencodedData)
        )

        let temporaryDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let allowedPrefix = pdfDirectory.standardizedFileURL.path + "/"
        for (index, item) in items.enumerated() {
            let sourceURL = item.url(relativeTo: pdfDirectory).standardizedFileURL
            guard sourceURL.path.hasPrefix(allowedPrefix) else {
                XCTFail("PDF item [\(index)] has a path outside the local fixture.")
                return
            }
            let document = try Data(contentsOf: sourceURL)
            XCTAssertEqual(document.count, item.fileSizeBytes, "PDF item [\(index)] byte count changed.")
            XCTAssertTrue(document.starts(with: Data("%PDF".utf8)), "PDF item [\(index)] is not a PDF document.")
            let copiedURL = temporaryDirectory.appendingPathComponent("document-\(index).pdf")
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: copiedURL)
            XCTAssertTrue(try Data(contentsOf: copiedURL) == document, "PDF item [\(index)] bytes changed in the saved copy.")
            XCTAssertTrue(try Data(contentsOf: sourceURL) == document, "The source PDF fixture must remain read-only.")
        }
        XCTAssertTrue(try Data(contentsOf: manifestURL) == sourceData, "The PDF manifest fixture must remain read-only.")

        let setlistURL = library.appendingPathComponent("Application Support/iChart/Setlists/pdf-setlists.json")
        if FileManager.default.fileExists(atPath: setlistURL.path) {
            let setlistData = try Data(contentsOf: setlistURL)
            let setlists = try ChartPersistenceCoders.decoder.decode(SetlistManifest.self, from: setlistData)
            let savedSetlistData = try ChartPersistenceCoders.encoder.encode(setlists)
            assertSameJSON(
                try JSONSerialization.jsonObject(with: setlistData),
                try JSONSerialization.jsonObject(with: savedSetlistData)
            )
            let documentIDs = Set(items.map(\.id))
            XCTAssertEqual(Set(setlists.setlists.map(\.id)).count, setlists.setlists.count)
            XCTAssertTrue(
                setlists.setlists.flatMap(\.entries).allSatisfy { documentIDs.contains($0.pdfItemID) },
                "A saved setlist reference is missing from the preserved PDF library."
            )
            XCTAssertTrue(try Data(contentsOf: setlistURL) == setlistData, "The setlist fixture must remain read-only.")
        }
    }

    private struct SetlistManifest: Codable {
        let version: Int
        let setlists: [IChartPDFSetlist]
    }
#endif

    private func fixtureLibraryDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appendingPathComponent(".build/notation-preservation-fixtures", isDirectory: true)
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Optional local device-snapshot fixture is not present.")
        }
        return fixture.appendingPathComponent("Library", isDirectory: true)
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func chartObjects(in object: Any) throws -> [[String: Any]] {
        let snapshot = try XCTUnwrap(object as? [String: Any])
        return try XCTUnwrap(snapshot["charts"] as? [[String: Any]])
    }

    private func removingAppearanceEditFields(from object: Any) throws -> [String: Any] {
        var snapshot = try XCTUnwrap(object as? [String: Any])
        var charts = try chartObjects(in: object)
        for index in charts.indices {
            for key in ["notationReadability", "repeatWings", "updatedAt"] {
                charts[index].removeValue(forKey: key)
            }
        }
        snapshot["charts"] = charts
        return snapshot
    }

    private func assertSameJSON(
        _ expected: Any,
        _ actual: Any,
        allowsNewDefaultAppearance: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let paths = differencePaths(expected, actual, path: "$", allowsNewDefaultAppearance: allowsNewDefaultAppearance)
        XCTAssertTrue(paths.isEmpty, "Persisted fields changed at: \(paths.prefix(20).joined(separator: ", "))", file: file, line: line)
    }

    private func differencePaths(
        _ expected: Any,
        _ actual: Any,
        path: String,
        allowsNewDefaultAppearance: Bool
    ) -> [String] {
        if let expected = expected as? [String: Any], let actual = actual as? [String: Any] {
            var paths: [String] = []
            let isChart = path.range(of: #"^\$\.charts\[\d+\]$"#, options: .regularExpression) != nil
            for key in Set(expected.keys).union(actual.keys).sorted() {
                let fieldPath = path + "." + key
                guard let expectedValue = expected[key], let actualValue = actual[key] else {
                    if allowsNewDefaultAppearance, isChart, expected[key] == nil {
                        if key == "notationReadability", actual[key] as? String == "standard" { continue }
                        if key == "repeatWings", actual[key] as? Bool == false { continue }
                    }
                    paths.append(fieldPath)
                    continue
                }
                paths += differencePaths(expectedValue, actualValue, path: fieldPath, allowsNewDefaultAppearance: allowsNewDefaultAppearance)
            }
            return paths
        }
        if let expected = expected as? [Any], let actual = actual as? [Any] {
            guard expected.count == actual.count else { return [path + ".count"] }
            return zip(expected, actual).enumerated().flatMap { index, pair in
                differencePaths(pair.0, pair.1, path: "\(path)[\(index)]", allowsNewDefaultAppearance: allowsNewDefaultAppearance)
            }
        }
        return (expected as? NSObject)?.isEqual(actual) == true ? [] : [path]
    }
}

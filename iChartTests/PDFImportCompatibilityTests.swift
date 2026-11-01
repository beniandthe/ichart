import Foundation
import XCTest

#if canImport(PDFKit)
import CoreGraphics
import PDFKit
@testable import iChart

@MainActor
final class PDFImportCompatibilityTests: XCTestCase {
    func testLegacyLibraryAndSetlistUpgradePreserveIdentifiersMetadataAndBytes() throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.remove() }
        let legacyItems = try legacyDecoder().decode([LegacyPDFLibraryItem].self, from: fixture.legacyManifest)
        XCTAssertEqual(Set(legacyItems.map(\.id)), [fixture.exportID, fixture.forumID])

        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertNil(store.recoveryErrorMessage)
        assertLegacyItemsPreserved(legacyItems, in: store, fixture: fixture)
        let setlists = IChartPDFSetlistStore(baseDirectory: fixture.setlists)
        XCTAssertNil(setlists.loadError)
        let setlist = try XCTUnwrap(setlists.setlist(id: fixture.setlistID))
        XCTAssertEqual(setlist.entries.map(\.id), [fixture.exportEntryID, fixture.forumEntryID])
        XCTAssertEqual(setlist.resolvedEntries(in: store.items).compactMap(\.pdfItem).map(\.id),
                       [fixture.exportID, fixture.forumID])
        // A supported forward upgrade does not rewrite an already valid legacy
        // manifest or the setlist which refers to those exact library IDs.
        XCTAssertEqual(try Data(contentsOf: fixture.libraryManifestURL), fixture.legacyManifest)
        XCTAssertEqual(try Data(contentsOf: fixture.setlistManifestURL), fixture.legacySetlistManifest)
    }

    func testImportedSchemaHasExplicitOldDecoderBoundaryAndRetainsEverythingAcrossReopen() async throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.remove() }
        let legacyItems = try legacyDecoder().decode([LegacyPDFLibraryItem].self, from: fixture.legacyManifest)
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let imported = try await store.importPDF(from: fixture.inputURL, title: "Customer Paper Chart")
        let importedURL = try XCTUnwrap(store.exportedPDF(for: imported)).url
        let setlists = IChartPDFSetlistStore(baseDirectory: fixture.setlists)
        let newEntry = try setlists.add(pdfItem: imported, to: fixture.setlistID)
        try setlists.moveEntries(in: fixture.setlistID, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        let expectedSetlists = setlists.setlists
        let mixedManifest = try Data(contentsOf: fixture.libraryManifestURL)
        let mixedSetlistManifest = try Data(contentsOf: fixture.setlistManifestURL)

        // This deliberately pins the supported boundary: installing the old
        // binary over an imported container is unsupported. Do not disguise
        // imports or fabricate native metadata to make this assertion pass.
        XCTAssertThrowsError(try legacyDecoder().decode([LegacyPDFLibraryItem].self, from: mixedManifest)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected the frozen legacy source enum to reject personalImport; got \(error).")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "source")
        }

        try FileManager.default.removeItem(at: fixture.inputURL)
        let reopened = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let reopenedSetlists = IChartPDFSetlistStore(baseDirectory: fixture.setlists)
        XCTAssertNil(reopened.recoveryErrorMessage)
        XCTAssertNil(reopenedSetlists.loadError)
        XCTAssertEqual(Set(reopened.items.map(\.id)), [fixture.exportID, fixture.forumID, imported.id])
        assertLegacyItemsPreserved(legacyItems, in: reopened, fixture: fixture)
        XCTAssertEqual(reopened.items.first { $0.id == imported.id }, imported)
        XCTAssertNil(imported.layoutStyle)
        XCTAssertNil(imported.transpositionView)
        XCTAssertNil(imported.chordTranspositionSemitones)
        XCTAssertEqual(try Data(contentsOf: importedURL), fixture.pdfBytes)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: importedURL)).pageCount, 2)
        XCTAssertEqual(reopenedSetlists.setlists, expectedSetlists)
        let restoredSetlist = try XCTUnwrap(reopenedSetlists.setlist(id: fixture.setlistID))
        XCTAssertEqual(restoredSetlist.entries.map(\.id), [newEntry.id, fixture.exportEntryID, fixture.forumEntryID])
        XCTAssertEqual(restoredSetlist.resolvedEntries(in: reopened.items).compactMap(\.pdfItem).map(\.id),
                       [imported.id, fixture.exportID, fixture.forumID])
        XCTAssertEqual(try Data(contentsOf: fixture.libraryManifestURL), mixedManifest)
        XCTAssertEqual(try Data(contentsOf: fixture.setlistManifestURL), mixedSetlistManifest)
    }

    func testChangingOnlySourceCannotBridgeMissingNativeMetadataToOldDecoder() async throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.remove() }
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let imported = try await store.importPDF(from: fixture.inputURL)
        let originalManifest = try Data(contentsOf: fixture.libraryManifestURL)
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: originalManifest) as? [[String: Any]])
        let index = try XCTUnwrap(objects.firstIndex { ($0["id"] as? String) == imported.id.uuidString })
        XCTAssertEqual(objects[index]["source"] as? String, "personalImport")
        XCTAssertNil(objects[index]["layoutStyle"])
        XCTAssertNil(objects[index]["transpositionView"])
        XCTAssertNil(objects[index]["chordTranspositionSemitones"])

        // Diagnose the second independent incompatibility in memory only. The
        // original truthful manifest and imported PDF are never modified.
        objects[index]["source"] = "chartExport"
        let sourceOnlyProjection = try JSONSerialization.data(withJSONObject: objects)
        XCTAssertThrowsError(try legacyDecoder().decode([LegacyPDFLibraryItem].self, from: sourceOnlyProjection)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("Expected required legacy native metadata to be absent; got \(error).")
            }
            XCTAssertEqual(key.stringValue, "layoutStyle")
        }
        XCTAssertEqual(try Data(contentsOf: fixture.libraryManifestURL), originalManifest)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.exportedPDF(for: imported)).url), fixture.pdfBytes)
        let reopened = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertNil(reopened.recoveryErrorMessage)
        XCTAssertEqual(reopened.items.first { $0.id == imported.id }?.source, .personalImport)
    }

    private func assertLegacyItemsPreserved(
        _ legacyItems: [LegacyPDFLibraryItem],
        in store: IChartPDFLibraryStore,
        fixture: CompatibilityFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for old in legacyItems {
            guard let item = store.items.first(where: { $0.id == old.id }) else {
                XCTFail("Missing legacy item \(old.id).", file: file, line: line)
                continue
            }
            XCTAssertEqual(item.source.rawValue, old.source.rawValue, file: file, line: line)
            XCTAssertEqual(item.fileName, old.fileName, file: file, line: line)
            XCTAssertEqual(item.displayTitle, old.displayTitle, file: file, line: line)
            XCTAssertEqual(item.layoutStyle?.rawValue, old.layoutStyle.rawValue, file: file, line: line)
            XCTAssertEqual(item.transpositionView?.rawValue, old.transpositionView.rawValue, file: file, line: line)
            XCTAssertEqual(item.chordTranspositionSemitones, old.chordTranspositionSemitones, file: file, line: line)
            XCTAssertEqual(item.pageCount, old.pageCount, file: file, line: line)
            XCTAssertEqual(item.fileSizeBytes, old.fileSizeBytes, file: file, line: line)
            XCTAssertEqual(item.createdAt, old.createdAt, file: file, line: line)
            XCTAssertEqual(item.relativePath, old.relativePath, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: item.url(relativeTo: fixture.library)), fixture.pdfBytes,
                           file: file, line: line)
        }
    }

    private func legacyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Frozen ChartPersistenceCoders.decoder behavior from 5b5fe710.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
        }
        return decoder
    }
}

// The persisted field types and raw-value enums below are frozen from
// 5b5fe710:iChart/Services/PDFLibraryStore.swift and Models/Chart.swift.
// Keep them independent of current app model changes so a forward-upgrade test
// cannot accidentally start claiming compatibility with a changed old decoder.
private struct LegacyPDFLibraryItem: Decodable {
    let id: UUID
    let source: LegacyPDFLibrarySource
    let fileName: String
    let displayTitle: String
    let layoutStyle: LegacyChartLayoutStyle
    let transpositionView: LegacyTranspositionView
    let chordTranspositionSemitones: Int
    let pageCount: Int
    let fileSizeBytes: Int
    let createdAt: Date
    let relativePath: String
}

private enum LegacyPDFLibrarySource: String, Decodable {
    case chartExport
    case forumDownload
}

private enum LegacyChartLayoutStyle: String, Decodable {
    case simpleChordSheet
    case rhythmSectionSheet
    case leadSheet
}

private enum LegacyTranspositionView: String, Decodable {
    case concert
    case bb
    case eb
    case f
}

private struct CompatibilityFixture {
    let root: URL
    let pdfBytes: Data
    let exportID = UUID()
    let forumID = UUID()
    let setlistID = UUID()
    let exportEntryID = UUID()
    let forumEntryID = UUID()

    var library: URL { root.appendingPathComponent("library", isDirectory: true) }
    var setlists: URL { root.appendingPathComponent("setlists", isDirectory: true) }
    var inputURL: URL { root.appendingPathComponent("Paper Chart.pdf") }
    var libraryManifestURL: URL { library.appendingPathComponent("pdf-library.json") }
    var setlistManifestURL: URL { setlists.appendingPathComponent("pdf-setlists.json") }

    var legacyManifest: Data {
        Data("""
        [{"id":"\(forumID.uuidString)","source":"forumDownload","fileName":"Legacy Forum.pdf",
          "displayTitle":"Legacy Forum","layoutStyle":"rhythmSectionSheet","transpositionView":"bb",
          "chordTranspositionSemitones":2,"pageCount":2,"fileSizeBytes":\(pdfBytes.count),"createdAt":200,
          "relativePath":"Forum Downloads/Legacy Forum.pdf"},
         {"id":"\(exportID.uuidString)","source":"chartExport","fileName":"Legacy Export.pdf",
          "displayTitle":"Legacy Export","layoutStyle":"simpleChordSheet","transpositionView":"concert",
          "chordTranspositionSemitones":0,"pageCount":2,"fileSizeBytes":\(pdfBytes.count),"createdAt":100,
          "relativePath":"Exports/Legacy Export.pdf"}]
        """.utf8)
    }

    var legacySetlistManifest: Data {
        Data("""
        {"version":1,"setlists":[{"id":"\(setlistID.uuidString)","name":"Legacy Gig",
         "entries":[{"id":"\(exportEntryID.uuidString)","pdfItemID":"\(exportID.uuidString)","displayTitle":"Legacy Export"},
                    {"id":"\(forumEntryID.uuidString)","pdfItemID":"\(forumID.uuidString)","displayTitle":"Legacy Forum"}],
         "createdAt":50,"updatedAt":50}]}
        """.utf8)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for pageIndex in 0..<2 {
            context.beginPDFPage(nil)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.stroke(CGRect(x: 32, y: 32, width: CGFloat(120 + pageIndex * 40), height: 160))
            context.endPDFPage()
        }
        context.closePDF()
        pdfBytes = data as Data
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Exports"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Forum Downloads"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: setlists, withIntermediateDirectories: true)
        try pdfBytes.write(to: inputURL)
        try pdfBytes.write(to: library.appendingPathComponent("Exports/Legacy Export.pdf"))
        try pdfBytes.write(to: library.appendingPathComponent("Forum Downloads/Legacy Forum.pdf"))
        try legacyManifest.write(to: libraryManifestURL)
        try legacySetlistManifest.write(to: setlistManifestURL)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
#endif

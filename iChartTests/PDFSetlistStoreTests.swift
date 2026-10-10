import Combine
import Foundation
import XCTest
@testable import iChart

@MainActor
final class PDFSetlistStoreTests: XCTestCase {
    private enum RecordingError: Error { case write }

    private final class RecordingWriter {
        var fails = false
        func write(_ data: Data, to url: URL) throws {
            if fails { throw RecordingError.write }
            try data.write(to: url, options: .atomic)
        }
    }

    func testMissingManifestStartsEmptyWithoutWritingAnything() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        XCTAssertTrue(store.setlists.isEmpty)
        XCTAssertNil(store.loadError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testNamedSetlistsRoundTripAndRenameKeepsIdentity() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let first = try store.create(name: "  Friday Night  ")
        let second = try store.create(name: "Saturday Night")
        try store.rename(setlistID: first.id, to: "  Friday Late Set\n")

        XCTAssertEqual(store.setlists.map(\.id), [second.id, first.id])
        XCTAssertEqual(store.setlist(id: first.id)?.name, "Friday Late Set")
        XCTAssertEqual(store.setlist(id: first.id)?.createdAt, first.createdAt)
        XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: root).setlists, store.setlists)
    }

    func testBatchAddPreservesOrderAndRepeatedSongsHaveIndependentEntryIDs() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let setlist = try store.create(name: "Encore")
        let firstSong = pdfItem(title: "First Song")
        let secondSong = pdfItem(title: "Second Song")
        let entries = try store.add(pdfItems: [firstSong, secondSong, firstSong], to: setlist.id)

        XCTAssertEqual(entries.map(\.pdfItemID), [firstSong.id, secondSong.id, firstSong.id])
        XCTAssertEqual(Set(entries.map(\.id)).count, 3)
        try store.remove(entryID: entries[0].id, from: setlist.id)
        XCTAssertEqual(store.setlist(id: setlist.id)?.entries, Array(entries.dropFirst()))
        XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: root).setlists, store.setlists)
    }

    func testReorderUsesSwiftUIOffsetSemanticsInBothDirections() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let setlist = try store.create(name: "Song Order")
        let entries = try store.add(pdfItems: ["A", "B", "C", "D", "E"].map { pdfItem(title: $0) }, to: setlist.id)
        try store.moveEntries(in: setlist.id, fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(store.setlist(id: setlist.id)?.entries.map(\.id), [1, 3, 0, 2, 4].map { entries[$0].id })
        try store.moveEntries(in: setlist.id, fromOffsets: IndexSet([3, 4]), toOffset: 0)
        XCTAssertEqual(store.setlist(id: setlist.id)?.entries.map(\.id), [2, 4, 1, 3, 0].map { entries[$0].id })
        try store.removeEntries(at: IndexSet([0, 3]), from: setlist.id)
        XCTAssertEqual(store.setlist(id: setlist.id)?.entries.map(\.id), [4, 1, 0].map { entries[$0].id })
        XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: root).setlists, store.setlists)
    }

    func testInvalidEditsLeaveStateAndManifestUnchanged() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let setlist = try store.create(name: "Valid")
        _ = try store.add(pdfItem: pdfItem(title: "Song"), to: setlist.id)
        let before = store.setlists
        let data = try Data(contentsOf: manifest(in: root))

        XCTAssertThrowsError(try store.create(name: " \n"))
        XCTAssertThrowsError(try store.rename(setlistID: setlist.id, to: ""))
        XCTAssertThrowsError(try store.rename(setlistID: UUID(), to: "Missing"))
        XCTAssertThrowsError(try store.remove(entryID: UUID(), from: setlist.id))
        XCTAssertThrowsError(try store.removeEntries(at: IndexSet(integer: 2), from: setlist.id))
        XCTAssertThrowsError(try store.moveEntries(in: setlist.id, fromOffsets: IndexSet(integer: 0), toOffset: 2))
        XCTAssertThrowsError(try store.moveEntries(in: setlist.id, fromOffsets: IndexSet(integer: 1), toOffset: 0))
        XCTAssertThrowsError(try store.delete(setlistID: UUID()))
        XCTAssertEqual(store.setlists, before)
        XCTAssertEqual(try Data(contentsOf: manifest(in: root)), data)
    }

    func testEveryWriteFailurePreservesPublishedStateManifestAndReopenedData() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = RecordingWriter()
        let store = IChartPDFSetlistStore(baseDirectory: root, writeManifest: writer.write)
        let setlist = try store.create(name: "Original")
        let song = pdfItem(title: "Original Song")
        let entries = try store.add(pdfItems: [song, pdfItem(title: "Second")], to: setlist.id)
        let before = store.setlists
        let data = try Data(contentsOf: manifest(in: root))
        var publicationCount = 0
        let observation = store.$setlists.dropFirst().sink { _ in publicationCount += 1 }
        defer { observation.cancel() }
        writer.fails = true
        let mutations: [() throws -> Void] = [
            { _ = try store.create(name: "Failed Create") },
            { try store.rename(setlistID: setlist.id, to: "Failed Rename") },
            { _ = try store.add(pdfItem: song, to: setlist.id) },
            { _ = try store.add(pdfItems: [song, song], to: setlist.id) },
            { try store.remove(entryID: entries[0].id, from: setlist.id) },
            { try store.removeEntries(at: IndexSet(integer: 0), from: setlist.id) },
            { try store.moveEntries(in: setlist.id, fromOffsets: IndexSet(integer: 0), toOffset: 2) },
            { try store.delete(setlistID: setlist.id) }
        ]
        for mutation in mutations {
            XCTAssertThrowsError(try mutation()) { error in
                XCTAssertTrue(error is RecordingError)
            }
            XCTAssertEqual(store.setlists, before)
            XCTAssertEqual(publicationCount, 0)
            XCTAssertEqual(try Data(contentsOf: manifest(in: root)), data)
            XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: root).setlists, before)
        }
        writer.fails = false
        try store.rename(setlistID: setlist.id, to: "Recovered")
        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(store.setlist(id: setlist.id)?.name, "Recovered")
        XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: root).setlists, store.setlists)
    }

    func testDirectoryCreationFailureDoesNotPublishNewSetlist() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockedDirectory = root.appendingPathComponent("blocked")
        let blocker = Data("This is a file".utf8)
        try blocker.write(to: blockedDirectory)
        let store = IChartPDFSetlistStore(baseDirectory: blockedDirectory)
        XCTAssertThrowsError(try store.create(name: "Unwritten"))
        XCTAssertTrue(store.setlists.isEmpty)
        XCTAssertEqual(try Data(contentsOf: blockedDirectory), blocker)
    }

    func testUnreadableManifestBlocksWritesAndFailedReloadKeepsExistingSetlists() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let setlist = try store.create(name: "Preserved")
        let savedData = try Data(contentsOf: manifest(in: root))
        let corruptData = Data("{unfinished".utf8)
        try corruptData.write(to: manifest(in: root), options: .atomic)
        XCTAssertThrowsError(try store.reload())
        XCTAssertEqual(store.setlists, [setlist])
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.rename(setlistID: setlist.id, to: "Must Not Overwrite"))
        let reopened = IChartPDFSetlistStore(baseDirectory: root)
        XCTAssertNotNil(reopened.loadError)
        XCTAssertThrowsError(try reopened.create(name: "Must Not Overwrite"))
        XCTAssertEqual(try Data(contentsOf: manifest(in: root)), corruptData)

        try savedData.write(to: manifest(in: root), options: .atomic)
        try store.reload()
        XCTAssertNil(store.loadError)
        try store.rename(setlistID: setlist.id, to: "Recovered")
        XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: root).setlists, store.setlists)
    }

    func testUnsupportedManifestVersionIsNotOverwritten() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data("{\"version\":2,\"setlists\":[]}".utf8)
        try data.write(to: manifest(in: root))
        let store = IChartPDFSetlistStore(baseDirectory: root)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.create(name: "Must Not Overwrite"))
        XCTAssertEqual(try Data(contentsOf: manifest(in: root)), data)
    }

    func testDuplicateSetlistAndEntryIdentifiersBlockManifestWrites() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let setlist = try store.create(name: "Original")
        _ = try store.add(pdfItem: pdfItem(title: "Song"), to: setlist.id)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: manifest(in: root))
        ) as? [String: Any])
        var original = try XCTUnwrap((object["setlists"] as? [[String: Any]])?.first)
        let entry = try XCTUnwrap((original["entries"] as? [[String: Any]])?.first)
        let duplicateSetlists = [original, original]
        original["entries"] = [entry, entry]
        for setlists in [duplicateSetlists, [original]] {
            object["setlists"] = setlists
            let data = try JSONSerialization.data(withJSONObject: object)
            try data.write(to: manifest(in: root), options: .atomic)
            let reopened = IChartPDFSetlistStore(baseDirectory: root)
            XCTAssertNotNil(reopened.loadError)
            XCTAssertThrowsError(try reopened.create(name: "Must Not Overwrite"))
            XCTAssertEqual(try Data(contentsOf: manifest(in: root)), data)
        }
    }

    func testMissingPDFReferencesKeepOrderAndResolveAgainAfterReopen() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let setlist = try store.create(name: "Missing Song")
        let first = pdfItem(title: "First Song")
        let second = pdfItem(title: "Second Song")
        let entries = try store.add(pdfItems: [first, second, first], to: setlist.id)
        let reopened = try XCTUnwrap(IChartPDFSetlistStore(baseDirectory: root).setlist(id: setlist.id))
        let partial = reopened.resolvedEntries(in: [second])
        XCTAssertEqual(partial.map(\.id), entries.map(\.id))
        XCTAssertNil(partial[0].pdfItem)
        XCTAssertEqual(partial[0].displayTitle, "First Song")
        XCTAssertEqual(partial[1].pdfItem, second)
        XCTAssertNil(partial[2].pdfItem)
        XCTAssertEqual(reopened.entries, entries)

        let returned = pdfItem(id: first.id, title: "First Song Renamed")
        let resolved = reopened.resolvedEntries(in: [returned, second])
        XCTAssertEqual(resolved.map(\.id), entries.map(\.id))
        XCTAssertEqual(resolved.map(\.pdfItem), [returned, second, returned])
        XCTAssertEqual(resolved.map(\.displayTitle), ["First Song Renamed", "Second Song", "First Song Renamed"])
    }

    func testRemovingEntryAndDeletingSetlistNeverDeletesPDFLibraryFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("Song.pdf")
        let pdfData = Data("%PDF-1.7\n% setlist test\n".utf8)
        try pdfData.write(to: sourceURL)
        let pdfStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("PDF Library"))
        let saved = try pdfStore.save(ExportedPDF(
            url: sourceURL, chartTitle: "Song", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0,
            pageCount: 1, fileSizeBytes: pdfData.count, exportedAt: Date()
        ), source: .chartExport)
        let item = try XCTUnwrap(pdfStore.items.first)
        let setlistStore = IChartPDFSetlistStore(baseDirectory: root.appendingPathComponent("Setlists"))
        let setlist = try setlistStore.create(name: "Gig")
        let entries = try setlistStore.add(pdfItems: [item, item], to: setlist.id)
        try setlistStore.remove(entryID: entries[0].id, from: setlist.id)
        XCTAssertEqual(try Data(contentsOf: saved.url), pdfData)
        try setlistStore.delete(setlistID: setlist.id)
        XCTAssertEqual(try Data(contentsOf: saved.url), pdfData)
        XCTAssertEqual(pdfStore.items, [item])
        XCTAssertTrue(IChartPDFSetlistStore(baseDirectory: root.appendingPathComponent("Setlists")).setlists.isEmpty)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func manifest(in root: URL) -> URL {
        root.appendingPathComponent("pdf-setlists.json")
    }

    private func pdfItem(id: UUID = UUID(), title: String) -> IChartPDFLibraryItem {
        IChartPDFLibraryItem(
            id: id, source: .chartExport, fileName: "\(title).pdf", displayTitle: title,
            layoutStyle: .simpleChordSheet, transpositionView: .concert,
            chordTranspositionSemitones: 0, pageCount: 1, fileSizeBytes: 25,
            createdAt: Date(timeIntervalSinceReferenceDate: 10), relativePath: "Exports/\(title).pdf"
        )
    }
}

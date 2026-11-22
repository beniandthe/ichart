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

    func testCreateWithSelectedPDFsSavesOneCompleteSetlist() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var writes = 0
        let store = IChartPDFSetlistStore(baseDirectory: root, writeManifest: { data, url in
            writes += 1
            try data.write(to: url, options: .atomic)
        })
        let songs = [pdfItem(title: "First"), pdfItem(title: "Second")]
        let setlist = try store.create(name: "  Tonight  ", pdfItems: songs)
        XCTAssertEqual(writes, 1, "Create and add must not leave an empty setlist if a later write fails")
        XCTAssertEqual(setlist.name, "Tonight")
        XCTAssertEqual(setlist.entries.map(\.pdfItemID), songs.map(\.id))
        XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: root).setlists, [setlist])
    }

    func testReplaceKeepsEntryIdentityAndPositionAndChangesOnlyItsPDFReference() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let original = pdfItem(title: "Unavailable Original")
        let other = pdfItem(title: "Other Song")
        let setlist = try store.create(name: "Gig", pdfItems: [original, other, original])
        let replacement = pdfItem(title: "Working Copy")
        try store.replace(entryID: setlist.entries[0].id, in: setlist.id, with: replacement)
        let updated = try XCTUnwrap(store.setlist(id: setlist.id))
        XCTAssertEqual(updated.entries.map(\.id), setlist.entries.map(\.id))
        XCTAssertEqual(updated.entries.map(\.pdfItemID), [replacement.id, other.id, original.id])
        XCTAssertEqual(updated.entries[0].displayTitle, replacement.displayTitle)
        XCTAssertEqual(updated.entries[1...], setlist.entries[1...])
        XCTAssertEqual(updated.createdAt, setlist.createdAt)
        XCTAssertEqual(IChartPDFSetlistStore(baseDirectory: root).setlists, [updated])
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
        XCTAssertThrowsError(try store.replace(entryID: UUID(), in: setlist.id, with: pdfItem(title: "Replacement")))
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
            { _ = try store.create(name: "Failed With Songs", pdfItems: [song]) },
            { try store.rename(setlistID: setlist.id, to: "Failed Rename") },
            { _ = try store.add(pdfItem: song, to: setlist.id) },
            { _ = try store.add(pdfItems: [song, song], to: setlist.id) },
            { try store.replace(entryID: entries[0].id, in: setlist.id, with: self.pdfItem(title: "Replacement")) },
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

    func testUnreadableOptionalCloudMetadataKeepsOfflineSetlistsEditableAndPreservesMetadata() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let list = try store.create(name: "Offline set")
        let url = manifest(in: root)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let opaque = ["future_format": "preserve this account state"]
        json["cloudCheckpoints"] = opaque
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let reopened = IChartPDFSetlistStore(baseDirectory: root)
        XCTAssertNil(reopened.loadError)
        XCTAssertTrue(reopened.cloudMetadataUnavailable)
        XCTAssertEqual(reopened.setlists, [list])
        try reopened.rename(setlistID: list.id, to: "Edited offline")
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(saved["cloudCheckpoints"] as? [String: String], opaque)
        XCTAssertEqual(reopened.setlists.first?.name, "Edited offline")
        XCTAssertThrowsError(try reopened.applyCloudMerge([], ownerID: UUID(),
            checkpoint: .init(revision: 1, setlists: [], pdfs: []), expectedLocal: reopened.setlists))
    }

    func testCloudCheckpointPreservesUnrelatedLocalSetlistsAndAccountOwnership() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let local = try store.create(name: "Local only")
        let owner = UUID()
        let remote = IChartPDFSetlist(name: "Cloud set")
        try store.applyCloudMerge([remote], ownerID: owner,
            checkpoint: .init(revision: 2, setlists: [remote], pdfs: []), expectedLocal: store.setlists)
        XCTAssertEqual(Set(store.setlists.map(\.id)), [local.id, remote.id])
        XCTAssertEqual(store.cloudSetlists(for: owner, enrollingUnowned: false), [remote])
        XCTAssertTrue(store.cloudSetlists(for: UUID(), enrollingUnowned: false).isEmpty)
        let reopened = IChartPDFSetlistStore(baseDirectory: root)
        XCTAssertEqual(reopened.cloudCheckpoints[owner]?.revision, 2)
        XCTAssertEqual(reopened.cloudOwners[remote.id], owner)
        XCTAssertNil(reopened.cloudOwners[local.id])
    }

    func testCloudMergeRejectsNewerLocalEditsWithoutChangingTheManifest() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IChartPDFSetlistStore(baseDirectory: root)
        let local = try store.create(name: "Original")
        let snapshot = store.setlists
        try store.rename(setlistID: local.id, to: "New local edit")
        let before = try Data(contentsOf: manifest(in: root))
        XCTAssertThrowsError(try store.applyCloudMerge(snapshot, ownerID: UUID(),
            checkpoint: .init(revision: 1, setlists: snapshot, pdfs: []), expectedLocal: snapshot))
        XCTAssertEqual(try Data(contentsOf: manifest(in: root)), before)
        XCTAssertEqual(store.setlists.first?.name, "New local edit")
    }

    func testThreeWaySetlistMergeKeepsIndependentEditsAndRequiresConflictResolution() {
        let a = IChartPDFSetlist(name: "A")
        let b = IChartPDFSetlist(name: "B")
        var localA = a
        localA.name = "Local A"
        var remoteB = b
        remoteB.name = "Remote B"
        let independent = IChartPDFSetlistCloudMerge(local: [localA, b], remote: [a, remoteB], baseline: [a, b])
        XCTAssertTrue(independent.conflictingIDs.isEmpty)
        XCTAssertEqual(Set(independent.resolved().map(\.name)), ["Local A", "Remote B"])
        var remoteA = a
        remoteA.name = "Remote A"
        let conflict = IChartPDFSetlistCloudMerge(local: [localA], remote: [remoteA], baseline: [a])
        XCTAssertEqual(conflict.conflictingIDs, [a.id])
        XCTAssertEqual(conflict.resolved(.local), [localA])
        XCTAssertEqual(conflict.resolved(.cloud), [remoteA])
        let copies = conflict.resolved(.both)
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(Set(copies.map(\.id)).count, 2)
        XCTAssertTrue(copies.contains(remoteA))
    }

    func testCloudPDFManifestRejectsMissingReferencesAndInvalidHash() throws {
        let item = pdfItem(title: "Song")
        let list = IChartPDFSetlist(name: "Gig", entries: [.init(pdfItemID: item.id, displayTitle: "Song")])
        XCTAssertThrowsError(try IChartPDFSetlistCloudValidation.validate(.init(setlists: [list], pdfs: [])))
        XCTAssertThrowsError(try IChartPDFSetlistCloudValidation.validate(.init(setlists: [list],
            pdfs: [.init(item: item, sha256: "not a hash")])))
        let document = IChartPDFSetlistCloudDocument(setlists: [], pdfs: [])
        let encoded = try ChartPersistenceCoders.encoder.encode(document)
        XCTAssertEqual(try ChartPersistenceCoders.decoder.decode(IChartPDFSetlistCloudDocument.self, from: encoded), document)
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

#if canImport(UIKit)
import UIKit
import Supabase

@MainActor
final class PDFSetlistCloudSyncTests: XCTestCase {
    func testPinnedSupabaseCodersPreserveSubsecondManifestTimestamps() throws {
        struct Parameters: Encodable { let manifest: IChartJSONValue }
        let timestamp = Date(timeIntervalSinceReferenceDate: 817_234_567.123456)
        let list = IChartPDFSetlist(name: "Timestamp", createdAt: timestamp, updatedAt: timestamp)
        let document = IChartPDFSetlistCloudDocument(setlists: [list], pdfs: [])
        let payload = try IChartPDFSetlistCloudValidation.payload(document)
        let wire = try PostgrestClient.Configuration.jsonEncoder.encode(Parameters(manifest: payload))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        let manifest = try XCTUnwrap(object["manifest"] as? [String: Any])
        let rows = try XCTUnwrap(manifest["setlists"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["createdAt"] as? Double, timestamp.timeIntervalSinceReferenceDate)
        let response = try PostgrestClient.Configuration.jsonEncoder.encode(
            IChartPDFSetlistCloudEnvelope(version: 3, manifest: document))
        let decoded = try PostgrestClient.Configuration.jsonDecoder.decode(IChartPDFSetlistCloudEnvelope.self, from: response)
        XCTAssertEqual(decoded.manifest, document)
    }

    func testLinkedPDFBacksUpRestoresOnSecondDeviceAndRemainsReadableAfterAccessEnds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
            context.beginPage()
            NSString(string: "Offline setlist PDF").draw(at: CGPoint(x: 10, y: 10), withAttributes: nil)
        }
        let source = directory.appendingPathComponent("Source.pdf")
        try data.write(to: source)
        let pdfsA = IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("A/PDFs"))
        _ = try pdfsA.save(.init(url: source, chartTitle: "Song", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: 1,
            fileSizeBytes: data.count, exportedAt: .now), source: .chartExport)
        let item = try XCTUnwrap(pdfsA.items.first)
        let listsA = IChartPDFSetlistStore(baseDirectory: directory.appendingPathComponent("A/Setlists"))
        let original = try listsA.create(name: "Tour", pdfItems: [item])
        let owner = UUID()
        let service = PDFSetlistCloudFakeService()
        let syncA = IChartPDFSetlistCloudSyncStore(service: service)
        syncA.attach(setlistStore: listsA, pdfStore: pdfsA)
        syncA.updateAccess(ownerID: owner, canSync: true)
        syncA.backUpNow()
        try await finish(syncA)
        XCTAssertEqual(listsA.cloudCheckpoints[owner]?.setlists, [original])
        let pdfRootB = directory.appendingPathComponent("B/PDFs")
        let listRootB = directory.appendingPathComponent("B/Setlists")
        let pdfsB = IChartPDFLibraryStore(baseDirectory: pdfRootB)
        let existingSource = directory.appendingPathComponent("BSource/Source.pdf")
        try FileManager.default.createDirectory(at: existingSource.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let existingData = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
            context.beginPage()
            NSString(string: "Device B local PDF").draw(at: CGPoint(x: 10, y: 10), withAttributes: nil)
        }
        try existingData.write(to: existingSource)
        let existingPDF = try pdfsB.save(.init(url: existingSource, chartTitle: "Other Song",
            layoutStyle: .simpleChordSheet, transpositionView: .concert, chordTranspositionSemitones: 0,
            pageCount: 1, fileSizeBytes: existingData.count, exportedAt: .now), source: .chartExport)
        let existingItem = try XCTUnwrap(pdfsB.items.first)
        XCTAssertEqual(existingItem.fileName, item.fileName)
        let listsB = IChartPDFSetlistStore(baseDirectory: listRootB)
        let syncB = IChartPDFSetlistCloudSyncStore(service: service)
        syncB.attach(setlistStore: listsB, pdfStore: pdfsB)
        syncB.updateAccess(ownerID: owner, canSync: true)
        syncB.restoreFromCloud()
        try await finish(syncB)
        XCTAssertEqual(listsB.setlists, [original])
        let restored = try XCTUnwrap(pdfsB.items.first { $0.id == item.id })
        XCTAssertEqual(pdfsB.items.count, 2)
        XCTAssertNotEqual(restored.fileName, item.fileName)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(pdfsB.exportedPDF(for: restored)).url), data)
        let restoredCloudVersion = await service.commitCount()
        syncB.backUpNow()
        try await finish(syncB)
        syncA.backUpNow()
        try await finish(syncA)
        let cloudVersionAfterRepeat = await service.commitCount()
        XCTAssertEqual(cloudVersionAfterRepeat, restoredCloudVersion)
        XCTAssertEqual(try Data(contentsOf: existingPDF.url), existingData)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(pdfsB.exportedPDF(for: restored)).url), data)
        syncB.updateAccess(ownerID: nil, canSync: false)
        let reopenedPDFs = IChartPDFLibraryStore(baseDirectory: pdfRootB)
        let reopenedLists = IChartPDFSetlistStore(baseDirectory: listRootB)
        XCTAssertEqual(reopenedLists.setlists, [original])
        let cached = try XCTUnwrap(reopenedPDFs.items.first { $0.id == item.id })
        XCTAssertEqual(reopenedPDFs.items.count, 2)
        XCTAssertNotNil(reopenedPDFs.items.first { $0.id == existingItem.id })
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopenedPDFs.exportedPDF(for: cached)).url), data)
        XCTAssertEqual(try Data(contentsOf: existingPDF.url), existingData)
    }

    func testExplicitBackupEnrollsLocalSetlistsAndRepeatedSyncMakesNoNewCloudVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lists = IChartPDFSetlistStore(baseDirectory: directory.appendingPathComponent("Setlists"))
        let pdfs = IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDFs"))
        let local = try lists.create(name: "Tonight")
        let owner = UUID()
        let service = PDFSetlistCloudFakeService()
        let sync = IChartPDFSetlistCloudSyncStore(service: service)
        sync.attach(setlistStore: lists, pdfStore: pdfs)
        sync.updateAccess(ownerID: owner, canSync: true)
        sync.backUpNow()
        try await finish(sync)
        XCTAssertEqual(lists.cloudOwners[local.id], owner)
        let commitsAfterStep1 = await service.commitCount()
        XCTAssertEqual(commitsAfterStep1, 1)
        sync.backUpNow()
        try await finish(sync)
        let commitsAfterStep2 = await service.commitCount()
        XCTAssertEqual(commitsAfterStep2, 1)
        let otherOwner = UUID()
        sync.updateAccess(ownerID: otherOwner, canSync: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(lists.setlists, [local])
        XCTAssertEqual(lists.cloudOwners[local.id], owner)
        XCTAssertNil(lists.automaticCloudOwnerID)
        XCTAssertTrue(lists.cloudSetlists(for: otherOwner, enrollingUnowned: false).isEmpty)
    }

    func testConcurrentCloudEditsRequireAChoiceAndKeepBothPreservesEachVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lists = IChartPDFSetlistStore(baseDirectory: directory.appendingPathComponent("Setlists"))
        let pdfs = IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDFs"))
        let original = try lists.create(name: "Gig")
        let owner = UUID()
        let service = PDFSetlistCloudFakeService()
        let sync = IChartPDFSetlistCloudSyncStore(service: service)
        sync.attach(setlistStore: lists, pdfStore: pdfs)
        sync.updateAccess(ownerID: owner, canSync: true)
        sync.backUpNow()
        try await finish(sync)
        try lists.rename(setlistID: original.id, to: "Local Gig")
        var remote = original
        remote.name = "Remote Gig"
        await service.configure(remote: .init(version: 2,
            manifest: .init(setlists: [remote], pdfs: [])), holdsFetch: false)
        sync.backUpNow()
        try await finish(sync)
        XCTAssertTrue(sync.pendingConflict)
        XCTAssertEqual(lists.setlists.first?.name, "Local Gig")
        // SwiftUI dismisses a dialog before delivering its action.
        sync.dismissConflictPresentation()
        sync.resolveConflicts(.both)
        try await finish(sync)
        XCTAssertFalse(sync.pendingConflict)
        XCTAssertEqual(Set(lists.setlists.map(\.name)), ["Remote Gig", "Local Gig (Local copy)"])
        XCTAssertEqual(Set(lists.setlists.map(\.id)).count, 2)
    }

    func testAccountChangeAndExpiryKeepLocalSetlistsAndInvalidateAnInFlightRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lists = IChartPDFSetlistStore(baseDirectory: directory.appendingPathComponent("Setlists"))
        let pdfs = IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDFs"))
        let local = try lists.create(name: "Keep offline")
        let remote = IChartPDFSetlist(name: "Remote account")
        let service = PDFSetlistCloudFakeService()
        await service.configure(remote: .init(version: 1, manifest: .init(setlists: [remote], pdfs: [])), holdsFetch: true)
        let sync = IChartPDFSetlistCloudSyncStore(service: service)
        sync.attach(setlistStore: lists, pdfStore: pdfs)
        sync.updateAccess(ownerID: UUID(), canSync: true)
        sync.restoreFromCloud()
        for _ in 0..<50 {
            if await service.isHolding() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        sync.updateAccess(ownerID: nil, canSync: false)
        await service.resumeFetch()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(sync.isWorking)
        XCTAssertEqual(lists.setlists, [local])
        XCTAssertTrue(lists.cloudOwners.isEmpty)
        let commitsAfterStep3 = await service.commitCount()
        XCTAssertEqual(commitsAfterStep3, 0)
    }

    func testNewLocalEditDuringCloudReadIsKeptAndCanBeRetried() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lists = IChartPDFSetlistStore(baseDirectory: directory.appendingPathComponent("Setlists"))
        let pdfs = IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDFs"))
        let local = try lists.create(name: "First name")
        let service = PDFSetlistCloudFakeService()
        await service.configure(remote: .init(version: 0, manifest: nil), holdsFetch: true)
        let sync = IChartPDFSetlistCloudSyncStore(service: service)
        sync.attach(setlistStore: lists, pdfStore: pdfs)
        sync.updateAccess(ownerID: UUID(), canSync: true)
        sync.backUpNow()
        for _ in 0..<50 {
            if await service.isHolding() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try lists.rename(setlistID: local.id, to: "Latest edit")
        await service.resumeFetch()
        try await finish(sync)
        XCTAssertEqual(lists.setlists.first?.name, "Latest edit")
        let commitsAfterStep4 = await service.commitCount()
        XCTAssertEqual(commitsAfterStep4, 0)
        sync.backUpNow()
        try await finish(sync)
        let commitsAfterStep5 = await service.commitCount()
        XCTAssertEqual(commitsAfterStep5, 1)
        XCTAssertEqual(lists.setlists.first?.name, "Latest edit")
    }

    private func finish(_ sync: IChartPDFSetlistCloudSyncStore) async throws {
        for _ in 0..<100 {
            if !sync.isWorking { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The local fake cloud operation must finish")
    }
}

private actor PDFSetlistCloudFakeService: IChartPDFSetlistCloudServicing {
    private var remote = IChartPDFSetlistCloudEnvelope(version: 0, manifest: nil)
    private var commits = 0
    private var holdsFetch = false
    private var pdfData: [String: Data] = [:]
    private var continuation: CheckedContinuation<Void, Never>?

    func configure(remote: IChartPDFSetlistCloudEnvelope, holdsFetch: Bool) {
        self.remote = remote
        self.holdsFetch = holdsFetch
    }
    func isHolding() -> Bool { continuation != nil }
    func resumeFetch() {
        holdsFetch = false
        continuation?.resume()
        continuation = nil
    }
    func commitCount() -> Int { commits }
    func fetch(ownerID: UUID) async throws -> IChartPDFSetlistCloudEnvelope {
        if holdsFetch { await withCheckedContinuation { continuation = $0 } }
        return remote
    }
    func download(_ pdf: IChartPDFSetlistCloudPDF, ownerID: UUID) async throws -> Data {
        guard let data = pdfData[pdf.sha256] else { throw IChartPDFSetlistCloudError.missingPDF }
        return data
    }
    func upload(_ pdf: IChartPDFSetlistCloudPDF, data: Data, ownerID: UUID) async throws {
        try IChartPDFSetlistCloudValidation.validate(data, for: pdf)
        pdfData[pdf.sha256] = data
    }
    func commit(_ document: IChartPDFSetlistCloudDocument, expectedVersion: Int64,
        ownerID: UUID) async throws -> IChartPDFSetlistCloudEnvelope {
        guard expectedVersion == remote.version else { throw IChartPDFSetlistCloudError.cloudChanged }
        commits += 1
        remote = .init(version: remote.version + 1, manifest: document)
        return remote
    }
}
#endif

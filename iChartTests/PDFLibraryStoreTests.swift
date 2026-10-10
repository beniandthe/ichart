import Foundation
import XCTest
@testable import iChart

@MainActor
final class PDFLibraryStoreTests: XCTestCase {
    func testSavesChartExportsInPersistentPDFLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = root
            .appendingPathComponent("source", isDirectory: true)
            .appendingPathComponent("My Chart.pdf", isDirectory: false)
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("%PDF-1.7\n% iChart test\n".utf8).write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library", isDirectory: true))
        let exportedPDF = ExportedPDF(
            url: sourceURL,
            chartTitle: "My Chart",
            layoutStyle: .simpleChordSheet,
            transpositionView: .concert,
            chordTranspositionSemitones: 0,
            pageCount: 3,
            fileSizeBytes: 23,
            exportedAt: Date(timeIntervalSinceReferenceDate: 10)
        )

        let savedPDF = try store.save(exportedPDF, source: .chartExport)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items(for: .chartExport).count, 1)
        XCTAssertEqual(store.items(for: .forumDownload).count, 0)
        XCTAssertEqual(savedPDF.chartTitle, "My Chart")
        XCTAssertEqual(savedPDF.pageCount, 3)
        XCTAssertEqual(savedPDF.pageCountText, "3 pages")
        XCTAssertEqual(store.items.first?.pageCount, 3)
        XCTAssertEqual(store.items.first?.pageCountText, "3 pages")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPDF.url.path(percentEncoded: false)))

        let reloadedStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library", isDirectory: true))
        XCTAssertEqual(reloadedStore.items.count, 1)
        let reloadedPDF = try XCTUnwrap(reloadedStore.exportedPDF(for: reloadedStore.items[0]))
        XCTAssertEqual(reloadedPDF.pageCount, 3)
        XCTAssertEqual(reloadedPDF.pageCountText, "3 pages")
    }

    func testDuplicatePDFNamesAreKeptAsSeparateLibraryItems() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = root.appendingPathComponent("Duplicate.pdf", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("%PDF-1.7\n% iChart test\n".utf8).write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library", isDirectory: true))
        let exportedPDF = ExportedPDF(
            url: sourceURL,
            chartTitle: "Duplicate",
            layoutStyle: .rhythmSectionSheet,
            transpositionView: .bb,
            chordTranspositionSemitones: 2,
            pageCount: 1,
            fileSizeBytes: 23,
            exportedAt: Date(timeIntervalSinceReferenceDate: 10)
        )

        let first = try store.save(exportedPDF, source: .forumDownload)
        let second = try store.save(exportedPDF, source: .forumDownload)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items(for: .forumDownload).count, 2)
        XCTAssertNotEqual(first.url.lastPathComponent, second.url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path(percentEncoded: false)))
    }

    func testInactiveSubscriptionRemovesForumDownloadsButKeepsChartExports() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = root.appendingPathComponent("Source.pdf", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("%PDF-1.7\n% iChart test\n".utf8).write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let libraryDirectory = root.appendingPathComponent("library", isDirectory: true)
        let store = IChartPDFLibraryStore(baseDirectory: libraryDirectory)
        let exportedPDF = ExportedPDF(
            url: sourceURL,
            chartTitle: "Forum Tune",
            layoutStyle: .simpleChordSheet,
            transpositionView: .concert,
            chordTranspositionSemitones: 0,
            pageCount: 1,
            fileSizeBytes: 23,
            exportedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let chartExport = try store.save(exportedPDF, source: .chartExport)
        let forumDownload = try store.save(exportedPDF, source: .forumDownload)

        let removedCount = store.removeForumDownloadsIfInactive(for: .basic)

        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.source, .chartExport)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chartExport.url.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: forumDownload.url.path(percentEncoded: false)))

        let reloadedStore = IChartPDFLibraryStore(baseDirectory: libraryDirectory)
        XCTAssertEqual(reloadedStore.items.count, 1)
        XCTAssertEqual(reloadedStore.items.first?.source, .chartExport)
    }

    func testGraceHidesForumDownloadsWithoutDeleting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = root.appendingPathComponent("Grace.pdf", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("%PDF-1.7\n% iChart test\n".utf8).write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library", isDirectory: true))
        let exportedPDF = ExportedPDF(
            url: sourceURL,
            chartTitle: "Grace Tune",
            layoutStyle: .rhythmSectionSheet,
            transpositionView: .concert,
            chordTranspositionSemitones: 0,
            pageCount: 1,
            fileSizeBytes: 23,
            exportedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let forumDownload = try store.save(exportedPDF, source: .forumDownload)

        XCTAssertEqual(
            store.removeForumDownloadsIfInactive(
                for: .proGrace(graceEndsAt: Date(timeIntervalSinceReferenceDate: 200))
            ),
            0
        )
        XCTAssertTrue(store.visibleItems(for: .proGrace(graceEndsAt: Date(timeIntervalSinceReferenceDate: 200))).isEmpty)
        XCTAssertEqual(store.removeForumDownloadsIfInactive(for: .unavailable), 0)
        XCTAssertTrue(store.visibleItems(for: .unavailable).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: forumDownload.url.path(percentEncoded: false)))
    }

    func testDeletingPDFLibraryItemRemovesFileAndManifestEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = root.appendingPathComponent("Delete Me.pdf", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("%PDF-1.7\n% iChart test\n".utf8).write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library", isDirectory: true))
        let exportedPDF = ExportedPDF(
            url: sourceURL,
            chartTitle: "Delete Me",
            layoutStyle: .simpleChordSheet,
            transpositionView: .concert,
            chordTranspositionSemitones: 0,
            pageCount: 1,
            fileSizeBytes: 23,
            exportedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        _ = try store.save(exportedPDF, source: .chartExport)
        let item = try XCTUnwrap(store.items.first)
        let savedURL = item.url(relativeTo: root.appendingPathComponent("library", isDirectory: true))

        try store.delete(item)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path(percentEncoded: false)))

        let reloadedStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library", isDirectory: true))
        XCTAssertTrue(reloadedStore.items.isEmpty)
    }

    func testBatchDeletionUsesExactConfirmedIDsAndPreservesUnselectedFiles() throws {
        let fixture = try deletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let confirmedIDs = Set(fixture.originalItems.prefix(2).map(\.id))
        let addedPDF = try fixture.store.save(fixture.sourcePDF, source: .chartExport)
        let addedItem = try XCTUnwrap(fixture.store.items.first { $0.fileName == addedPDF.fileName })
        let keep = fixture.originalItems[2]
        let keepURL = try XCTUnwrap(fixture.store.exportedPDF(for: keep)).url
        let keepBytes = try Data(contentsOf: keepURL)
        let sourceBytes = try Data(contentsOf: fixture.sourcePDF.url)

        XCTAssertEqual(try fixture.store.deleteItems(ids: confirmedIDs.union([UUID()])), 2)
        XCTAssertEqual(Set(fixture.store.items.map(\.id)), [keep.id, addedItem.id])
        for item in fixture.originalItems.prefix(2) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: item.url(relativeTo: fixture.library).path))
        }
        XCTAssertEqual(try Data(contentsOf: keepURL), keepBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: addedPDF.url.path))
        XCTAssertEqual(try Data(contentsOf: fixture.sourcePDF.url), sourceBytes)
        let reloaded = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertEqual(reloaded.items, fixture.store.items)
    }

    func testBatchDeletionWithEmptyOrUnknownIDsDoesNotRewriteManifest() throws {
        let fixture = try deletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = fixture.library.appendingPathComponent("pdf-library.json")
        let before = try Data(contentsOf: manifest)
        XCTAssertEqual(try fixture.store.deleteItems(ids: []), 0)
        XCTAssertEqual(try fixture.store.deleteItems(ids: [UUID()]), 0)
        XCTAssertEqual(fixture.store.items, fixture.originalItems)
        XCTAssertEqual(try Data(contentsOf: manifest), before)
    }

    func testBatchMoveFailureRestoresEveryFileAndLeavesManifestUnchanged() throws {
        let manager = DeletionFailureFileManager()
        let fixture = try deletionFixture(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = fixture.library.appendingPathComponent("pdf-library.json")
        let before = try Data(contentsOf: manifest)
        let bytes = try fixture.originalItems.map { try Data(contentsOf: $0.url(relativeTo: fixture.library)) }
        manager.failMoveFrom = fixture.originalItems[1].url(relativeTo: fixture.library).path

        XCTAssertThrowsError(try fixture.store.deleteItems(ids: Set(fixture.originalItems.prefix(2).map(\.id))))
        XCTAssertEqual(fixture.store.items, fixture.originalItems)
        XCTAssertEqual(try Data(contentsOf: manifest), before)
        for (index, item) in fixture.originalItems.enumerated() {
            XCTAssertEqual(try Data(contentsOf: item.url(relativeTo: fixture.library)), bytes[index])
        }
        let reloaded = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertEqual(reloaded.items, fixture.originalItems)
        XCTAssertNil(reloaded.recoveryErrorMessage)
    }

    func testBatchManifestFailureRestoresEveryFileAndPublishedItem() throws {
        let manager = DeletionFailureFileManager()
        let fixture = try deletionFixture(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = fixture.library.appendingPathComponent("pdf-library.json")
        let before = try Data(contentsOf: manifest)
        let bytes = try fixture.originalItems.map { try Data(contentsOf: $0.url(relativeTo: fixture.library)) }
        manager.failCreateAt = fixture.library.path

        XCTAssertThrowsError(try fixture.store.deleteItems(ids: Set(fixture.originalItems.map(\.id))))
        XCTAssertEqual(fixture.store.items, fixture.originalItems)
        XCTAssertEqual(try Data(contentsOf: manifest), before)
        for (index, item) in fixture.originalItems.enumerated() {
            XCTAssertEqual(try Data(contentsOf: item.url(relativeTo: fixture.library)), bytes[index])
        }
    }

    func testFailedRollbackRetainsJournalAndReloadRecoversBeforePruningMissingEntries() throws {
        let manager = DeletionFailureFileManager()
        let fixture = try deletionFixture(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = fixture.library.appendingPathComponent("pdf-library.json")
        let before = try Data(contentsOf: manifest)
        manager.failCreateAt = fixture.library.path
        manager.failRestoreMoves = true

        XCTAssertThrowsError(try fixture.store.deleteItems(ids: Set(fixture.originalItems.prefix(2).map(\.id)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("recoverable"))
        }
        XCTAssertEqual(fixture.store.items, fixture.originalItems)
        XCTAssertEqual(try Data(contentsOf: manifest), before)
        XCTAssertNotNil(fixture.store.recoveryErrorMessage)
        let failedReload = IChartPDFLibraryStore(baseDirectory: fixture.library, fileManager: manager)
        XCTAssertEqual(failedReload.items, fixture.originalItems, "Staged files must not be pruned from the manifest")
        XCTAssertNotNil(failedReload.recoveryErrorMessage)

        manager.failCreateAt = nil
        manager.failRestoreMoves = false
        failedReload.reload()
        XCTAssertNil(failedReload.recoveryErrorMessage)
        XCTAssertEqual(failedReload.items, fixture.originalItems)
        XCTAssertTrue(fixture.originalItems.allSatisfy {
            FileManager.default.fileExists(atPath: $0.url(relativeTo: fixture.library).path)
        })
        XCTAssertEqual(try Data(contentsOf: manifest), before)
    }

    func testCommittedCleanupFailureIsExplicitAndReloadRetriesWithoutRestoringDeletedItems() throws {
        let manager = DeletionFailureFileManager()
        let fixture = try deletionFixture(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        manager.failTransactionCleanup = true
        let removed = fixture.originalItems[0]
        XCTAssertThrowsError(try fixture.store.deleteItems(ids: [removed.id])) { error in
            guard let deletionError = error as? IChartPDFLibraryDeletionError,
                  case .cleanupFailed(let count, _) = deletionError else {
                return XCTFail("Expected an explicit committed-cleanup error")
            }
            XCTAssertEqual(count, 1)
            XCTAssertTrue(error.localizedDescription.contains("deleted from the library"))
        }
        XCTAssertEqual(fixture.store.items, fixture.originalItems.filter { $0.id != removed.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: removed.url(relativeTo: fixture.library).path))
        manager.failTransactionCleanup = false
        let reloaded = IChartPDFLibraryStore(baseDirectory: fixture.library, fileManager: manager)
        XCTAssertEqual(reloaded.items, fixture.store.items)
        XCTAssertNil(reloaded.recoveryErrorMessage)
        let staging = fixture.library.appendingPathComponent(".deletions")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    func testMalformedManifestPreservesStagedFilesAndLastReadableItems() throws {
        let manager = DeletionFailureFileManager()
        let fixture = try deletionFixture(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manifest = fixture.library.appendingPathComponent("pdf-library.json")
        let originalManifest = try Data(contentsOf: manifest)
        manager.failCreateAt = fixture.library.path
        manager.failRestoreMoves = true
        XCTAssertThrowsError(try fixture.store.deleteItems(ids: [fixture.originalItems[0].id]))
        let staging = fixture.library.appendingPathComponent(".deletions")
        let directories = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        let transactionDirectory = try XCTUnwrap(directories.first)
        let retainedURL = transactionDirectory.appendingPathComponent("\(fixture.originalItems[0].id.uuidString).pdf")
        let retainedBytes = try Data(contentsOf: retainedURL)
        try Data("invalid synthetic manifest".utf8).write(to: manifest, options: .atomic)
        manager.failCreateAt = nil
        manager.failRestoreMoves = false

        let reloaded = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertNotNil(reloaded.recoveryErrorMessage)
        XCTAssertEqual(try Data(contentsOf: retainedURL), retainedBytes)
        fixture.store.reload()
        XCTAssertEqual(fixture.store.items, fixture.originalItems)
        XCTAssertNotNil(fixture.store.recoveryErrorMessage)
        XCTAssertThrowsError(try fixture.store.deleteItems(ids: [fixture.originalItems[0].id]))
        XCTAssertEqual(try Data(contentsOf: retainedURL), retainedBytes)
        XCTAssertThrowsError(try fixture.store.save(fixture.sourcePDF, source: .chartExport))
        XCTAssertEqual(fixture.store.removeForumDownloadsIfInactive(for: .basic), 0)
        XCTAssertEqual(try Data(contentsOf: retainedURL), retainedBytes)

        try FileManager.default.removeItem(at: manifest)
        let missingManifestStore = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertNotNil(missingManifestStore.recoveryErrorMessage)
        XCTAssertEqual(try Data(contentsOf: retainedURL), retainedBytes)
        fixture.store.reload()
        XCTAssertEqual(fixture.store.items, fixture.originalItems)
        XCTAssertNotNil(fixture.store.recoveryErrorMessage)

        try originalManifest.write(to: manifest, options: .atomic)
        reloaded.reload()
        XCTAssertNil(reloaded.recoveryErrorMessage)
        XCTAssertEqual(reloaded.items, fixture.originalItems)
        XCTAssertEqual(try Data(contentsOf: fixture.originalItems[0].url(relativeTo: fixture.library)), retainedBytes)
    }

    func testSecondStoreAdditionsArePreservedByConfirmedIDDeletion() throws {
        let fixture = try deletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let secondStore = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let added = try secondStore.save(fixture.sourcePDF, source: .forumDownload)
        let addedID = try XCTUnwrap(secondStore.items.first { $0.relativePath == "Forum Downloads/" + added.fileName }?.id)

        XCTAssertEqual(try fixture.store.deleteItems(ids: [fixture.originalItems[0].id]), 1)
        XCTAssertTrue(fixture.store.items.contains { $0.id == addedID })
        XCTAssertTrue(FileManager.default.fileExists(atPath: added.url.path))
        XCTAssertEqual(IChartPDFLibraryStore(baseDirectory: fixture.library).items, fixture.store.items)
    }

    func testSymlinkedTransactionDirectoryIsNeverTraversedOrDeleted() throws {
        let fixture = try deletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("unselected", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("keep.txt")
        try Data("synthetic untouched file".utf8).write(to: sentinel)
        let staging = fixture.library.appendingPathComponent(".deletions", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let link = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let reloaded = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertNotNil(reloaded.recoveryErrorMessage)
        XCTAssertThrowsError(try reloaded.deleteItems(ids: [fixture.originalItems[0].id]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(reloaded.items, fixture.originalItems)
    }

    func testUnexpectedRecoveryFolderFilePreventsCleanupAndPreservesAllBytes() throws {
        let manager = DeletionFailureFileManager()
        let fixture = try deletionFixture(fileManager: manager)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        manager.failCreateAt = fixture.library.path
        manager.failRestoreMoves = true
        XCTAssertThrowsError(try fixture.store.deleteItems(ids: [fixture.originalItems[0].id]))
        let staging = fixture.library.appendingPathComponent(".deletions")
        let directory = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).first)
        let unselected = directory.appendingPathComponent("keep.txt")
        let unselectedBytes = Data("unselected synthetic recovery file".utf8)
        try unselectedBytes.write(to: unselected)
        let retained = directory.appendingPathComponent("\(fixture.originalItems[0].id.uuidString).pdf")
        let retainedBytes = try Data(contentsOf: retained)

        let reloaded = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertNotNil(reloaded.recoveryErrorMessage)
        XCTAssertEqual(reloaded.items, fixture.originalItems)
        XCTAssertEqual(try Data(contentsOf: unselected), unselectedBytes)
        XCTAssertEqual(try Data(contentsOf: retained), retainedBytes)
    }

    func testDeletingMissingSelectedFileCanRemoveItsStaleManifestEntry() throws {
        let fixture = try deletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let missing = fixture.originalItems[0]
        try FileManager.default.removeItem(at: missing.url(relativeTo: fixture.library))
        XCTAssertEqual(try fixture.store.deleteItems(ids: [missing.id]), 1)
        XCTAssertEqual(fixture.store.items, fixture.originalItems.filter { $0.id != missing.id })
        XCTAssertEqual(IChartPDFLibraryStore(baseDirectory: fixture.library).items, fixture.store.items)
    }

    func testInvalidManifestPathCannotDeleteAnOutsideFile() throws {
        let fixture = try deletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = fixture.originalItems[0]
        let unsafe = IChartPDFLibraryItem(id: item.id, source: item.source, fileName: item.fileName,
            displayTitle: item.displayTitle, layoutStyle: item.layoutStyle, transpositionView: item.transpositionView,
            chordTranspositionSemitones: item.chordTranspositionSemitones, pageCount: item.pageCount,
            fileSizeBytes: item.fileSizeBytes, createdAt: item.createdAt, relativePath: "../Source.pdf")
        let manifest = fixture.library.appendingPathComponent("pdf-library.json")
        let encoded = try ChartPersistenceCoders.encoder.encode([unsafe])
        try encoded.write(to: manifest, options: .atomic)
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let before = try Data(contentsOf: fixture.sourcePDF.url)

        XCTAssertThrowsError(try store.deleteItems(ids: [unsafe.id]))
        XCTAssertEqual(store.items, [unsafe])
        XCTAssertEqual(try Data(contentsOf: fixture.sourcePDF.url), before)
        XCTAssertEqual(try Data(contentsOf: manifest), encoded)
    }

    func testUnselectedItemSharingFilePreventsDeletingItsFile() throws {
        let fixture = try deletionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = fixture.originalItems[0]
        let alias = IChartPDFLibraryItem(id: UUID(), source: item.source, fileName: item.fileName,
            displayTitle: "Unselected copy", layoutStyle: item.layoutStyle, transpositionView: item.transpositionView,
            chordTranspositionSemitones: item.chordTranspositionSemitones, pageCount: item.pageCount,
            fileSizeBytes: item.fileSizeBytes, createdAt: item.createdAt, relativePath: item.relativePath)
        let manifest = fixture.library.appendingPathComponent("pdf-library.json")
        try ChartPersistenceCoders.encoder.encode([item, alias]).write(to: manifest, options: .atomic)
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let before = try Data(contentsOf: item.url(relativeTo: fixture.library))

        XCTAssertThrowsError(try store.deleteItems(ids: [item.id]))
        XCTAssertEqual(Set(store.items.map(\.id)), [item.id, alias.id])
        XCTAssertEqual(try Data(contentsOf: item.url(relativeTo: fixture.library)), before)
    }

    private struct DeletionFixture {
        var root: URL
        var library: URL
        var sourcePDF: ExportedPDF
        var store: IChartPDFLibraryStore
        var originalItems: [IChartPDFLibraryItem]
    }

    private func deletionFixture(fileManager: FileManager = .default) throws -> DeletionFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("Source.pdf")
        try Data("%PDF-1.7\n% synthetic deletion fixture\n".utf8).write(to: sourceURL)
        let pdf = ExportedPDF(url: sourceURL, chartTitle: "Synthetic deletion fixture", layoutStyle: .simpleChordSheet,
            transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: 1, fileSizeBytes: 37,
            exportedAt: Date(timeIntervalSinceReferenceDate: 1))
        let library = root.appendingPathComponent("library", isDirectory: true)
        let store = IChartPDFLibraryStore(baseDirectory: library, fileManager: fileManager)
        _ = try store.save(pdf, source: .chartExport)
        _ = try store.save(pdf, source: .forumDownload)
        _ = try store.save(pdf, source: .chartExport)
        return DeletionFixture(root: root, library: library, sourcePDF: pdf, store: store, originalItems: store.items)
    }
}

private final class DeletionFailureFileManager: FileManager, @unchecked Sendable {
    var failMoveFrom: String?
    var failCreateAt: String?
    var failRestoreMoves = false
    var failTransactionCleanup = false

    private var injectedError: NSError {
        NSError(domain: "PDFLibraryStoreTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Injected synthetic file-operation failure."])
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.path == failMoveFrom || (failRestoreMoves && srcURL.path.contains("/.deletions/")) {
            throw injectedError
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        if url.path == failCreateAt { throw injectedError }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    override func removeItem(at URL: URL) throws {
        if failTransactionCleanup && URL.path.contains("/.deletions/") { throw injectedError }
        try super.removeItem(at: URL)
    }
}

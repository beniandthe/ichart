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
            pageCount: 1,
            fileSizeBytes: 23,
            exportedAt: Date(timeIntervalSinceReferenceDate: 10)
        )

        let savedPDF = try store.save(exportedPDF, source: .chartExport)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items(for: .chartExport).count, 1)
        XCTAssertEqual(store.items(for: .forumDownload).count, 0)
        XCTAssertEqual(savedPDF.chartTitle, "My Chart")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPDF.url.path(percentEncoded: false)))

        let reloadedStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library", isDirectory: true))
        XCTAssertEqual(reloadedStore.items.count, 1)
        XCTAssertNotNil(reloadedStore.exportedPDF(for: reloadedStore.items[0]))
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

        store.delete(item)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path(percentEncoded: false)))

        let reloadedStore = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library", isDirectory: true))
        XCTAssertTrue(reloadedStore.items.isEmpty)
    }
}

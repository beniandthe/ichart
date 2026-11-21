import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import iChart

@MainActor
final class PDFLibraryCloudRestoreTests: XCTestCase {
    func testRestoringPersonalAndForumPDFsPreservesReferencesAndOriginalBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = IChartPDFLibraryStore(baseDirectory: fixture.root.appendingPathComponent("first-library"))
        let personal = try await source.importPDF(from: fixture.pdf)
        let firstCopy = try XCTUnwrap(source.exportedPDF(for: personal))
        _ = try source.save(firstCopy, source: .forumDownload)
        let forum = try XCTUnwrap(source.items.first { $0.source == .forumDownload })
        let setlistStore = IChartPDFSetlistStore(baseDirectory: fixture.root.appendingPathComponent("setlists"))
        let setlist = try setlistStore.create(name: "Gig")
        _ = try setlistStore.add(pdfItems: [forum, personal], to: setlist.id)

        let destination = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let existing = try await destination.importPDF(from: fixture.pdf)
        try destination.mergeCloudItems([personal, forum], files: [personal.id: fixture.pdf, forum.id: fixture.pdf])
        try destination.mergeCloudItems([personal, forum], files: [personal.id: fixture.pdf, forum.id: fixture.pdf])
        try FileManager.default.removeItem(at: fixture.pdf)

        let reopened = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertEqual(reopened.items.count, 3)
        XCTAssertEqual(reopened.items.first { $0.id == existing.id }, existing)
        let order = try XCTUnwrap(setlistStore.setlist(id: setlist.id)).resolvedEntries(in: reopened.items)
        XCTAssertEqual(order.compactMap(\.pdfItem?.id), [forum.id, personal.id])
        for item in order.compactMap(\.pdfItem) {
            let pdf = try XCTUnwrap(reopened.exportedPDF(for: item))
            XCTAssertEqual(try Data(contentsOf: pdf.url), fixture.bytes)
            XCTAssertEqual(PDFDocument(url: pdf.url)?.pageCount, 1)
        }
    }

    func testMissingOrConflictingRestoreLeavesExistingPDFAndManifestIntact() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let destination = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let saved = try await destination.importPDF(from: fixture.pdf)
        let separate = IChartPDFLibraryStore(baseDirectory: fixture.root.appendingPathComponent("remote"))
        let newItem = try await separate.importPDF(from: fixture.pdf)
        let badFile = fixture.root.appendingPathComponent("Corrupt.pdf")
        try Data("different bytes".utf8).write(to: badFile)

        XCTAssertThrowsError(
            try destination.mergeCloudItems([newItem, saved], files: [newItem.id: fixture.pdf, saved.id: badFile])
        )
        XCTAssertEqual(destination.items, [saved])
        let reopened = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertEqual(reopened.items, [saved])
        let savedURL = try XCTUnwrap(reopened.exportedPDF(for: saved)).url
        XCTAssertEqual(try Data(contentsOf: savedURL), fixture.bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            atPath: savedURL.deletingLastPathComponent().path
        ), [saved.fileName])
    }

    private struct Fixture {
        let root: URL
        let library: URL
        let pdf: URL
        let bytes: Data

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            library = root.appendingPathComponent("restored")
            pdf = root.appendingPathComponent("Song.pdf")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var page = CGRect(x: 0, y: 0, width: 200, height: 200)
            let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &page, nil))
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 10, y: 10, width: 50, height: 6))
            context.endPDFPage()
            context.closePDF()
            bytes = try Data(contentsOf: pdf)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

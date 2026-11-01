import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import iChart

@MainActor
final class PDFImportTests: XCTestCase {
    func testImportedOriginalSurvivesSourceRemovalAndMixedSetlistReload() async throws {
        let fixture = try Fixture(pageCount: 2)
        defer { fixture.remove() }
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let export = try store.save(fixture.exportedPDF, source: .chartExport)
        let exportItem = try XCTUnwrap(store.items.first)
        let imported = try await store.importPDF(from: fixture.source, title: "  Customer chart  ")
        let importedURL = try XCTUnwrap(store.exportedPDF(for: imported)).url
        XCTAssertEqual(imported.source, .personalImport)
        XCTAssertEqual(imported.displayTitle, "Customer chart")
        XCTAssertEqual(imported.pageCount, 2)
        XCTAssertEqual(imported.fileSizeBytes, fixture.bytes.count)
        XCTAssertNil(imported.layoutStyle)
        XCTAssertNil(imported.transpositionView)
        XCTAssertNil(imported.chordTranspositionSemitones)
        XCTAssertNil(imported.transpositionText)
        XCTAssertNil(store.exportedPDF(for: imported)?.transpositionText)
        XCTAssertNotEqual(importedURL, fixture.source)
        XCTAssertEqual(try Data(contentsOf: importedURL), fixture.bytes)

        let setlists = IChartPDFSetlistStore(baseDirectory: fixture.setlists)
        let setlist = try setlists.create(name: "Offline rehearsal")
        let entries = try setlists.add(pdfItems: [exportItem, imported], to: setlist.id)
        try setlists.moveEntries(in: setlist.id, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        try FileManager.default.removeItem(at: fixture.source)

        let reopened = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let reopenedSetlists = IChartPDFSetlistStore(baseDirectory: fixture.setlists)
        XCTAssertNil(reopened.recoveryErrorMessage)
        XCTAssertEqual(reopened.items, store.items)
        let restored = try XCTUnwrap(reopenedSetlists.setlist(id: setlist.id))
        XCTAssertEqual(restored.entries.map(\.id), [entries[1].id, entries[0].id])
        let resolved = restored.resolvedEntries(in: reopened.visibleItems(for: .basic))
        XCTAssertEqual(resolved.compactMap(\.pdfItem).map(\.id), [imported.id, exportItem.id])
        let retained = try XCTUnwrap(reopened.exportedPDF(for: imported))
        XCTAssertEqual(try Data(contentsOf: retained.url), fixture.bytes)
        XCTAssertEqual(try Data(contentsOf: export.url), fixture.bytes)
        let document = try XCTUnwrap(PDFDocument(url: retained.url))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertNotNil(document.page(at: 0))
        XCTAssertNotNil(document.page(at: 1))
    }

    func testDuplicateNamesPreserveSeparateItemsAndOriginalBytes() async throws {
        let fixture = try Fixture(pageCount: 1)
        defer { fixture.remove() }
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let first = try await store.importPDF(from: fixture.source)
        let second = try await store.importPDF(from: fixture.source, title: "   ")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.fileName, "Paper Chart.pdf")
        XCTAssertEqual(second.fileName, "Paper Chart 2.pdf")
        XCTAssertEqual(first.displayTitle, "Paper Chart")
        XCTAssertEqual(second.displayTitle, "Paper Chart")
        for item in [first, second] {
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.exportedPDF(for: item)).url), fixture.bytes)
        }
    }

    func testLegacyManifestKeepsIDsAndNativeMetadataWhenPersonalPDFIsAdded() async throws {
        let fixture = try Fixture(pageCount: 1)
        defer { fixture.remove() }
        let legacyID = UUID()
        let exportDirectory = fixture.library.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try fixture.bytes.write(to: exportDirectory.appendingPathComponent("Legacy.pdf"))
        let legacyManifest = """
        [{"id":"\(legacyID.uuidString)","source":"chartExport","fileName":"Legacy.pdf",
          "displayTitle":"Legacy native export","layoutStyle":"rhythmSectionSheet",
          "transpositionView":"bb","chordTranspositionSemitones":2,"pageCount":1,
          "fileSizeBytes":\(fixture.bytes.count),"createdAt":100,
          "relativePath":"Exports/Legacy.pdf"}]
        """
        try Data(legacyManifest.utf8).write(to: fixture.manifest)
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertNil(store.recoveryErrorMessage)
        let original = try XCTUnwrap(store.items.first)
        XCTAssertEqual(original.id, legacyID)
        XCTAssertEqual(original.layoutStyle, .rhythmSectionSheet)
        XCTAssertEqual(original.transpositionView, .bb)
        XCTAssertEqual(original.chordTranspositionSemitones, 2)
        XCTAssertNotNil(original.transpositionText)
        let imported = try await store.importPDF(from: fixture.source)
        let reloaded = IChartPDFLibraryStore(baseDirectory: fixture.library)
        XCTAssertEqual(reloaded.items.first(where: { $0.id == legacyID }), original)
        XCTAssertEqual(reloaded.items.first(where: { $0.id == imported.id }), imported)
        XCTAssertNil(imported.layoutStyle)
    }

    func testPersonalImportsStayAvailableAcrossEveryBillingStateAndPaidPolicy() async throws {
        let fixture = try Fixture(pageCount: 1)
        defer { fixture.remove() }
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let item = try await store.importPDF(from: fixture.source)
        for status in IChartSubscriptionStatus.allCases {
            let entitlement = IChartSubscriptionEntitlement(status: status)
            XCTAssertEqual(store.removeForumDownloadsIfInactive(for: entitlement, accessPolicy: .paidSubscription), 0)
            XCTAssertEqual(store.visibleItems(for: entitlement, accessPolicy: .paidSubscription), [item])
        }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.exportedPDF(for: item)).url), fixture.bytes)
    }

    func testCorruptEmptyAndWrongTypeInputsDoNotPublishOrWriteManifest() async throws {
        let fixture = try Fixture(pageCount: 1)
        defer { fixture.remove() }
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        for (name, bytes, expected) in [
            ("Corrupt.pdf", Data("%PDF-1.7\nthis is not a PDF document".utf8), IChartPDFImportError.unreadablePDF),
            ("Empty.pdf", Data(), .unreadablePDF),
            ("Screenshot.png", fixture.bytes, .notPDF)
        ] {
            let source = fixture.root.appendingPathComponent(name)
            try bytes.write(to: source)
            do {
                _ = try await store.importPDF(from: source)
                XCTFail("Expected \(name) to be rejected.")
            } catch {
                XCTAssertEqual(error as? IChartPDFImportError, expected)
            }
        }
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPasswordProtectedPDFIsRejectedWithoutChangingOriginal() async throws {
        let fixture = try Fixture(pageCount: 1)
        defer { fixture.remove() }
        let document = try XCTUnwrap(PDFDocument(data: fixture.bytes))
        let encrypted = try XCTUnwrap(document.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "secret",
            PDFDocumentWriteOption.ownerPasswordOption: "owner-secret"
        ]))
        let source = fixture.root.appendingPathComponent("Locked.pdf")
        try encrypted.write(to: source)
        XCTAssertTrue(try XCTUnwrap(PDFDocument(url: source)).isLocked)
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        do {
            _ = try await store.importPDF(from: source)
            XCTFail("Expected password protection to be rejected.")
        } catch {
            XCTAssertEqual(error as? IChartPDFImportError, .encryptedPDF)
        }
        XCTAssertEqual(try Data(contentsOf: source), encrypted)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testByteAndPageLimitsRejectBeforeLibraryCommit() async throws {
        let fixture = try Fixture(pageCount: 2)
        defer { fixture.remove() }
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library)
        let maximumBytes = fixture.bytes.count - 1
        do {
            _ = try await store.importPDF(from: fixture.source, limits: IChartPDFImportLimits(
                maximumFileSizeBytes: maximumBytes, maximumPageCount: 10
            ))
            XCTFail("Expected byte limit rejection.")
        } catch {
            XCTAssertEqual(error as? IChartPDFImportError, .fileTooLarge(maximumBytes: maximumBytes))
        }
        do {
            _ = try await store.importPDF(from: fixture.source, limits: IChartPDFImportLimits(
                maximumFileSizeBytes: fixture.bytes.count, maximumPageCount: 1
            ))
            XCTFail("Expected page limit rejection.")
        } catch {
            XCTAssertEqual(error as? IChartPDFImportError, .tooManyPages(maximum: 1))
        }
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testManifestFailureRollsBackOwnedCopyAndLeavesPublishedLibraryUnchanged() async throws {
        let fixture = try Fixture(pageCount: 2)
        defer { fixture.remove() }
        let manager = ImportFailureFileManager()
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library, fileManager: manager)
        _ = try store.save(fixture.exportedPDF, source: .chartExport)
        let originalItems = store.items
        let originalManifest = try Data(contentsOf: fixture.manifest)
        manager.failCreateAt = fixture.library.path
        do {
            _ = try await store.importPDF(from: fixture.source)
            XCTFail("Expected manifest failure.")
        } catch { }
        XCTAssertEqual(store.items, originalItems)
        XCTAssertEqual(try Data(contentsOf: fixture.manifest), originalManifest)
        let imports = fixture.library.appendingPathComponent("Imports")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imports.path), [])
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.bytes)
        XCTAssertEqual(IChartPDFLibraryStore(baseDirectory: fixture.library).items, originalItems)
    }

    func testCanceledPreparationDoesNotCommitAndDiscardsStagingCopy() async throws {
        let fixture = try Fixture(pageCount: 2)
        defer { fixture.remove() }
        let manager = ImportFailureFileManager()
        let copied = expectation(description: "Background staging copied source")
        manager.holdCopyFrom = fixture.source.path
        manager.onCopyHeld = { copied.fulfill() }
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library, fileManager: manager)
        let task = Task { try await store.importPDF(from: fixture.source) }
        defer { manager.releaseCopy.signal() }
        await fulfillment(of: [copied], timeout: 5)
        task.cancel()
        manager.releaseCopy.signal()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
        let stagingURL = try XCTUnwrap(manager.heldDestination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.bytes)
    }

    func testImportMergesNewerDiskItemsCreatedWhilePreparationIsSuspended() async throws {
        let fixture = try Fixture(pageCount: 2)
        defer { fixture.remove() }
        let manager = ImportFailureFileManager()
        let copied = expectation(description: "Background copy held")
        manager.holdCopyFrom = fixture.source.path
        manager.onCopyHeld = { copied.fulfill() }
        let staleStore = IChartPDFLibraryStore(baseDirectory: fixture.library, fileManager: manager)
        let task = Task { try await staleStore.importPDF(from: fixture.source) }
        defer { manager.releaseCopy.signal() }
        await fulfillment(of: [copied], timeout: 5)
        let secondStore = IChartPDFLibraryStore(baseDirectory: fixture.library)
        _ = try secondStore.save(fixture.exportedPDF, source: .chartExport)
        let interveningItem = try XCTUnwrap(secondStore.items.first)
        manager.releaseCopy.signal()
        let imported = try await task.value
        XCTAssertEqual(Set(staleStore.items.map(\.id)), [interveningItem.id, imported.id])
        XCTAssertEqual(IChartPDFLibraryStore(baseDirectory: fixture.library).items, staleStore.items)
    }

    func testImportDoesNotResurrectItemDeletedWhilePreparationIsSuspended() async throws {
        let fixture = try Fixture(pageCount: 2)
        defer { fixture.remove() }
        let manager = ImportFailureFileManager()
        let store = IChartPDFLibraryStore(baseDirectory: fixture.library, fileManager: manager)
        _ = try store.save(fixture.exportedPDF, source: .chartExport)
        let deleted = try XCTUnwrap(store.items.first)
        let copied = expectation(description: "Background copy held")
        manager.holdCopyFrom = fixture.source.path
        manager.onCopyHeld = { copied.fulfill() }
        let task = Task { try await store.importPDF(from: fixture.source) }
        defer { manager.releaseCopy.signal() }
        await fulfillment(of: [copied], timeout: 5)
        let secondStore = IChartPDFLibraryStore(baseDirectory: fixture.library)
        try secondStore.delete(deleted)
        manager.releaseCopy.signal()
        let imported = try await task.value
        XCTAssertEqual(store.items, [imported])
        XCTAssertEqual(IChartPDFLibraryStore(baseDirectory: fixture.library).items, [imported])
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleted.url(relativeTo: fixture.library).path))
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let bytes: Data
        let pageCount: Int
        var library: URL { root.appendingPathComponent("library", isDirectory: true) }
        var setlists: URL { root.appendingPathComponent("setlists", isDirectory: true) }
        var manifest: URL { library.appendingPathComponent("pdf-library.json") }

        var exportedPDF: ExportedPDF {
            ExportedPDF(url: source, chartTitle: "Native export", layoutStyle: .simpleChordSheet,
                        transpositionView: .concert, chordTranspositionSemitones: 0, pageCount: pageCount,
                        fileSizeBytes: bytes.count, exportedAt: Date(timeIntervalSinceReferenceDate: 1))
        }

        init(pageCount: Int) throws {
            self.pageCount = pageCount
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            source = root.appendingPathComponent("Paper Chart.pdf")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let data = NSMutableData()
            let consumer = try XCTUnwrap(CGDataConsumer(data: data))
            var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
            let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
            for index in 0..<pageCount {
                context.beginPDFPage(nil)
                context.setStrokeColor(CGColor(gray: 0, alpha: 1))
                context.stroke(CGRect(x: 32, y: 32, width: CGFloat(100 + index * 20), height: 100))
                context.endPDFPage()
            }
            context.closePDF()
            bytes = data as Data
            try bytes.write(to: source)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

private final class ImportFailureFileManager: FileManager, @unchecked Sendable {
    var failCreateAt: String?
    var holdCopyFrom: String?
    var onCopyHeld: (() -> Void)?
    var heldDestination: URL?
    let releaseCopy = DispatchSemaphore(value: 0)

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        if url.path == failCreateAt {
            throw NSError(domain: "PDFImportTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Injected manifest directory failure."])
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try super.copyItem(at: srcURL, to: dstURL)
        if srcURL.path == holdCopyFrom {
            heldDestination = dstURL
            onCopyHeld?()
            _ = releaseCopy.wait(timeout: .now() + 10)
        }
    }
}

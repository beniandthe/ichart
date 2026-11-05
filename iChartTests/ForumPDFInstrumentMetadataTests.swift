#if canImport(UIKit) && canImport(PDFKit)
import Foundation
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ForumPDFInstrumentMetadataTests: XCTestCase {
    func testLegacyForumItemWithoutStyleShowsUnknownViewInPreviewButPersonalImportDoesNot() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = try await PDFChartExporter(exportDirectory: root).exportPDF(
            for: Chart.blank(title: "Legacy PDF preview", measureCount: 1, layoutStyle: .simpleChordSheet))
        let legacy = IChartPDFLibraryItem(id: UUID(), source: .forumDownload, fileName: exported.fileName,
            displayTitle: "Legacy PDF preview", layoutStyle: nil, transpositionView: .concert,
            chordTranspositionSemitones: 0, pageCount: exported.pageCount, fileSizeBytes: exported.fileSizeBytes,
            createdAt: .now, relativePath: exported.fileName)
        XCTAssertEqual(legacy.transpositionText, "Instrument view unknown")
        let reopened = legacy.exportedPDF(relativeTo: root)
        XCTAssertNil(reopened.layoutStyle)
        XCTAssertNil(reopened.transpositionView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        for source in [IChartPDFLibrarySource.forumDownload, .personalImport] {
            let previous = scene.windows.first(where: \.isKeyWindow)
            let host = UIHostingController(rootView: PDFExportPreviewView(exportedPDF: reopened, source: source))
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previous?.makeKeyAndVisible()
            }
            var nodes = [NativeAccessibilityLookup.Node]()
            for _ in 0..<40 {
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                nodes = try NativeAccessibilityLookup.nodes(in: window)
                let hasSummary = nodes.contains { $0.element.accessibilityLabel == reopened.pageCountText }
                let expectedLabel = source == .forumDownload ? "Instrument view unknown" : "Original PDF"
                if hasSummary, nodes.contains(where: { $0.element.accessibilityLabel == expectedLabel }) { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertTrue(nodes.contains { $0.element.accessibilityLabel == reopened.pageCountText })
            let unknown = nodes.filter { $0.element.accessibilityLabel == "Instrument view unknown" }
            if source == .forumDownload {
                let label = try XCTUnwrap(unknown.first)
                let labelFrame = label.frame(in: window)
                XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(labelFrame))
                let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: window.traitCollection)
                let font = UIFont.systemFont(ofSize: caption.pointSize, weight: .semibold)
                let text = "Instrument view unknown" as NSString
                let naturalWidth = text.size(withAttributes: [.font: font]).width
                XCTAssertLessThan(labelFrame.width, naturalWidth,
                    "This adaptive-grid fixture must actually require wrapping the full label")
                let requiredBounds = text.boundingRect(
                    with: CGSize(width: labelFrame.width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
                XCTAssertGreaterThanOrEqual(labelFrame.height + 1, ceil(requiredBounds.height),
                    "The rendered label must have room for all preferred-caption text rather than a clipped accessibility label")
                XCTAssertGreaterThanOrEqual(labelFrame.height + 1, font.lineHeight * 2,
                    "A single scaled or ellipsized line must fail this wrapping regression")
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "FIX-011 legacy forum preview with unknown style and view"
                attachment.lifetime = .keepAlways
                add(attachment)
            } else {
                XCTAssertTrue(unknown.isEmpty, "Personal imports keep their metadata-free presentation")
            }
            let done = try XCTUnwrap(nodes.first { $0.isButton && $0.element.accessibilityLabel == "Done" })
            XCTAssertTrue(done.isEnabled)
            XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(done.frame(in: window)))
        }
    }

    func testForumPDFRoundTripPreservesPublisherViewForBothStylesAndEveryInstrument() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for view in TranspositionView.instrumentOptions {
                let root = temporaryDirectory()
                defer { try? FileManager.default.removeItem(at: root) }
                var chart = Chart.blank(title: "Forum publisher view \(style.rawValue) \(view.rawValue)",
                    measureCount: 4, layoutStyle: style)
                chart.defaultTranspositionView = view
                let measureID = try XCTUnwrap(chart.measures.first?.id)
                XCTAssertNotNil(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("C7"),
                    rawInput: "C7", to: measureID, atFraction: 0.1))
                let original = chart
                let post = post(style: style)
                let exporter = PDFChartExporter(exportDirectory: root.appendingPathComponent("exports"))
                let exported = try await exporter.exportPDF(for: chart, context: .init(forumCredit: .init(
                    creatorDisplayName: "Publisher", forumPostID: post.id,
                    exportedAt: Date(timeIntervalSinceReferenceDate: 800_000_000))))
                let data = try Data(contentsOf: exported.url)
                let snapshot = try XCTUnwrap(ForumPDFInstrumentSnapshot.validated(in: data,
                    postID: post.id, layoutStyle: style))
                XCTAssertEqual(snapshot.transpositionView, view)
                XCTAssertEqual(snapshot.chordTranspositionSemitones, chart.chordTranspositionSemitones)

                let downloaded = IChartForumPDFMetadata.downloadedPDF(data: data, url: exported.url, post: post)
                XCTAssertEqual(downloaded.transpositionView, view)
                XCTAssertEqual(downloaded.chordTranspositionSemitones, chart.chordTranspositionSemitones)
                XCTAssertEqual(downloaded.transpositionText, view.displayText)
                XCTAssertEqual(downloaded.pageCount, exported.pageCount)
                XCTAssertEqual(try Data(contentsOf: downloaded.url), data,
                    "Metadata recovery must not re-export or transpose the fixed PDF")

                let libraryURL = root.appendingPathComponent("library")
                let store = IChartPDFLibraryStore(baseDirectory: libraryURL)
                let saved = try store.save(downloaded, source: .forumDownload)
                let reloaded = IChartPDFLibraryStore(baseDirectory: libraryURL)
                let item = try XCTUnwrap(reloaded.items.first)
                XCTAssertEqual(item.forumInstrumentSnapshotVersion, ForumPDFInstrumentSnapshot.currentVersion)
                XCTAssertEqual(item.transpositionText, view.displayText)
                let reopened = try XCTUnwrap(reloaded.exportedPDF(for: item))
                XCTAssertEqual(reopened.transpositionView, view)
                XCTAssertEqual(reopened.transpositionText, view.displayText)
                XCTAssertEqual(try Data(contentsOf: saved.url), data)
                XCTAssertEqual(try Data(contentsOf: reopened.url), data)
                XCTAssertEqual(chart, original)
                if view == .bb {
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
                    attachment.name = "FIX-011 \(style.rawValue) publisher Bb view"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testForumPDFSnapshotPreservesAdditionalChordTransposition() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            var chart = Chart.blank(title: "Additional transpose", measureCount: 1, layoutStyle: style)
            chart.defaultTranspositionView = .eb
            chart.chordTranspositionSemitones = 3
            let post = post(style: style)
            let exported = try await PDFChartExporter(exportDirectory: root).exportPDF(for: chart,
                context: .init(forumCredit: .init(creatorDisplayName: "Publisher", forumPostID: post.id, exportedAt: .now)))
            let downloaded = IChartForumPDFMetadata.downloadedPDF(data: try Data(contentsOf: exported.url),
                url: exported.url, post: post)
            XCTAssertEqual(downloaded.transpositionView, .eb)
            XCTAssertEqual(downloaded.chordTranspositionSemitones, 3)
            XCTAssertEqual(downloaded.transpositionText, "Eb Horn · \(Chart.intervalDisplayText(forNormalizedSemitones: 3))")
        }
    }

    func testLegacyForumPDFHasUnknownViewAndPersonalExportStillHasNoForumMetadata() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            var chart = Chart.blank(title: "Legacy forum PDF", measureCount: 1, layoutStyle: style)
            chart.defaultTranspositionView = .bb
            let exported = try await PDFChartExporter(exportDirectory: root).exportPDF(for: chart)
            let data = try Data(contentsOf: exported.url)
            XCTAssertNil(PDFDocument(data: data)?.documentAttributes?[PDFDocumentAttribute.subjectAttribute])
            XCTAssertEqual(exported.transpositionText, "Bb Horn")
            let downloaded = IChartForumPDFMetadata.downloadedPDF(data: data, url: exported.url, post: post(style: style))
            XCTAssertNil(downloaded.transpositionView)
            XCTAssertNil(downloaded.chordTranspositionSemitones)
            XCTAssertEqual(downloaded.transpositionText, "Instrument view unknown")
            let store = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library"))
            let saved = try store.save(downloaded, source: .forumDownload)
            XCTAssertEqual(saved.transpositionText, "Instrument view unknown")
            XCTAssertEqual(store.items.first?.transpositionText, "Instrument view unknown")
            XCTAssertEqual(try Data(contentsOf: saved.url), data)
        }
    }

    func testLegacySavedForumConcertGuessIsUnknownWithoutRewritingItsManifestOrPDF() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pdfURL = root.appendingPathComponent("Forum Downloads/Legacy.pdf")
        try FileManager.default.createDirectory(at: pdfURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("%PDF-1.4\n% legacy fixture\n".utf8)
        try data.write(to: pdfURL)
        let item = IChartPDFLibraryItem(id: UUID(), source: .forumDownload, fileName: "Legacy.pdf",
            displayTitle: "Legacy", layoutStyle: .simpleChordSheet, transpositionView: .concert,
            chordTranspositionSemitones: 0, pageCount: 1, fileSizeBytes: data.count,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000), relativePath: "Forum Downloads/Legacy.pdf")
        let manifest = try ChartPersistenceCoders.encoder.encode([item])
        try manifest.write(to: root.appendingPathComponent("pdf-library.json"))
        let store = IChartPDFLibraryStore(baseDirectory: root)
        let loaded = try XCTUnwrap(store.items.first)
        XCTAssertEqual(loaded.transpositionText, "Instrument view unknown")
        XCTAssertNil(loaded.forumInstrumentSnapshotVersion)
        XCTAssertEqual(loaded.transpositionView, .concert, "Preserve the old record while declining to display its guess")
        XCTAssertEqual(store.exportedPDF(for: loaded)?.transpositionText, "Instrument view unknown")
        XCTAssertEqual(try Data(contentsOf: pdfURL), data)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("pdf-library.json")), manifest)
    }

    func testSnapshotRejectsWrongPostStyleVersionViewAndSemitoneMetadata() throws {
        let chart = Chart.blank(title: "Bound snapshot", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let id = UUID()
        let snapshot = ForumPDFInstrumentSnapshot(chart: chart, forumPostID: id)
        XCTAssertNotNil(ForumPDFInstrumentSnapshot.validated(subject: snapshot.subjectText,
            postID: id, layoutStyle: .rhythmSectionSheet))
        XCTAssertNil(ForumPDFInstrumentSnapshot.validated(subject: snapshot.subjectText,
            postID: UUID(), layoutStyle: .rhythmSectionSheet))
        XCTAssertNil(ForumPDFInstrumentSnapshot.validated(subject: snapshot.subjectText,
            postID: id, layoutStyle: .simpleChordSheet))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        for (key, values) in ["version": [2, 0], "chordTranspositionSemitones": [-1, 12, Int.max]] {
            for value in values {
                var mutated = fields
                mutated[key] = value
                let subject = ForumPDFInstrumentSnapshot.subjectPrefix
                    + (try JSONSerialization.data(withJSONObject: mutated)).base64EncodedString()
                XCTAssertNil(ForumPDFInstrumentSnapshot.validated(subject: subject, postID: id, layoutStyle: chart.layoutStyle))
            }
        }
        fields["transpositionView"] = "unrecognized-instrument"
        let unknownView = ForumPDFInstrumentSnapshot.subjectPrefix
            + (try JSONSerialization.data(withJSONObject: fields)).base64EncodedString()
        XCTAssertNil(ForumPDFInstrumentSnapshot.validated(subject: unknownView, postID: id, layoutStyle: chart.layoutStyle))
        for subject in [nil, "Concert", ForumPDFInstrumentSnapshot.subjectPrefix + "not-base64",
            String(repeating: "x", count: 2_049)] {
            XCTAssertNil(ForumPDFInstrumentSnapshot.validated(subject: subject, postID: id, layoutStyle: chart.layoutStyle))
        }
    }

    func testMismatchedEmbeddedSnapshotIsUnknownOnDownloadAndCannotBeMarkedKnownOnSave() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var chart = Chart.blank(title: "Wrong post snapshot", measureCount: 1, layoutStyle: .simpleChordSheet)
        chart.defaultTranspositionView = .bb
        let exported = try await PDFChartExporter(exportDirectory: root).exportPDF(for: chart,
            context: .init(forumCredit: .init(creatorDisplayName: "Publisher", forumPostID: UUID(), exportedAt: .now)))
        let data = try Data(contentsOf: exported.url)
        let downloaded = IChartForumPDFMetadata.downloadedPDF(data: data, url: exported.url,
            post: post(style: .simpleChordSheet))
        XCTAssertEqual(downloaded.transpositionText, "Instrument view unknown")
        let store = IChartPDFLibraryStore(baseDirectory: root.appendingPathComponent("library"))
        let saved = try store.save(downloaded, source: .forumDownload)
        XCTAssertNil(store.items.first?.forumInstrumentSnapshotVersion)
        XCTAssertEqual(saved.transpositionText, "Instrument view unknown")
        XCTAssertEqual(try Data(contentsOf: saved.url), data)
    }

    func testPersonalImportsKeepTheirExistingMetadataFreePresentation() {
        let imported = ExportedPDF(url: URL(fileURLWithPath: "/tmp/imported.pdf"), chartTitle: "Imported",
            layoutStyle: nil, transpositionView: nil, chordTranspositionSemitones: nil,
            pageCount: 1, fileSizeBytes: 100, exportedAt: .now)
        XCTAssertNil(imported.transpositionText)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func post(style: ChartLayoutStyle) -> ForumChartPost {
        ForumChartPost(id: UUID(), songID: UUID(), ownerID: UUID(), chartTitle: "Publisher snapshot",
            arrangerCredit: "Arranger", creatorDisplayName: "Publisher", tags: [], versionNote: nil,
            layoutStyle: style, pdfStoragePath: "fixture.pdf", status: .published,
            voteUpCount: 0, voteDownCount: 0, reportCount: 0, rankingScore: 0, publishedAt: .now)
    }
}
#endif

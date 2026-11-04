import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Publisher-supplied display metadata carried by the fixed forum PDF itself.
/// The post/style binding prevents applying one snapshot's hints to another
/// post. It is descriptive metadata, not proof of publisher identity.
struct ForumPDFInstrumentSnapshot: Codable, Equatable {
    static let currentVersion = 1
    static let subjectPrefix = "iChart forum instrument snapshot: "
    static let unknownViewText = "Instrument view unknown"

    let version: Int
    let forumPostID: UUID
    let layoutStyle: ChartLayoutStyle
    let transpositionView: TranspositionView
    let chordTranspositionSemitones: Int

    init(chart: Chart, forumPostID: UUID) {
        version = Self.currentVersion
        self.forumPostID = forumPostID
        layoutStyle = chart.layoutStyle
        transpositionView = chart.defaultTranspositionView
        chordTranspositionSemitones = Chart.normalizedChordTranspositionSemitones(chart.chordTranspositionSemitones)
    }

    var subjectText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return Self.subjectPrefix + data.base64EncodedString()
    }

    static func validated(
        subject: String?, postID: UUID? = nil, layoutStyle: ChartLayoutStyle?
    ) -> Self? {
        guard let subject, subject.utf8.count <= 2_048,
              subject.hasPrefix(subjectPrefix),
              let data = Data(base64Encoded: String(subject.dropFirst(subjectPrefix.count))),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.version == currentVersion,
              postID.map({ $0 == snapshot.forumPostID }) ?? true,
              layoutStyle == snapshot.layoutStyle,
              (0..<12).contains(snapshot.chordTranspositionSemitones) else { return nil }
        return snapshot
    }

    static func validated(
        in pdfData: Data, postID: UUID? = nil, layoutStyle: ChartLayoutStyle?
    ) -> Self? {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: pdfData), document.pageCount > 0 else { return nil }
        return validated(subject: document.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String,
            postID: postID, layoutStyle: layoutStyle)
        #else
        return nil
        #endif
    }
}

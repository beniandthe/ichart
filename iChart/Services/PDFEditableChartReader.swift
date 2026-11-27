import Foundation
import PDFKit
import CoreGraphics

enum PDFEditableChartReadError: LocalizedError, Equatable {
    case unavailable
    case noSelectableText
    case noSelectableTextOnPage(Int)
    case unsupportedStaffPage(Int)
    case noStaffChords

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "This PDF cannot be opened for conversion."
        case .noSelectableText:
            "This PDF has no selectable text. Use a printed chord chart saved as a text PDF."
        case .noSelectableTextOnPage(let page):
            "PDF page \(page) has no selectable text. Try a text PDF with selectable chords on every page. Your original PDF is unchanged."
        case .unsupportedStaffPage(let page):
            "iChart couldn't find complete measure rows on PDF page \(page). Try a text PDF with clear measure dividers and one column of music. Your original PDF is unchanged."
        case .noStaffChords:
            "iChart found the measures but couldn't find chord labels."
        }
    }
}

enum PDFEditableChartReader {
    static func read(from url: URL, title: String) async throws -> PDFEditableChartDraft {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
                throw PDFEditableChartReadError.unavailable
            }
            return try read(document, title: title)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func read(_ document: PDFDocument, title: String) throws -> PDFEditableChartDraft {
        var rows: [[String]] = []
        var pageNumbers: [Int] = []
        var drawnBarlineRows: Set<Int> = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let pageNumber = index + 1
            let pageDraft = try autoreleasepool {
                guard let page = document.page(at: index) else {
                    throw PDFEditableChartReadError.unsupportedStaffPage(pageNumber)
                }
                guard let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw document.pageCount == 1
                        ? PDFEditableChartReadError.noSelectableText
                        : PDFEditableChartReadError.noSelectableTextOnPage(pageNumber)
                }
                return try readPage(page, text: text, pageNumber: pageNumber, title: title)
            }
            if pageDraft.usesDrawnBarlines {
                drawnBarlineRows.formUnion(rows.count..<(rows.count + pageDraft.rows.count))
            }
            rows.append(contentsOf: pageDraft.rows)
            pageNumbers.append(contentsOf: repeatElement(pageNumber, count: pageDraft.rows.count))
        }
        guard rows.contains(where: { $0.contains { !$0.isEmpty } }) else {
            throw PDFEditableChartReadError.noStaffChords
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return PDFEditableChartDraft(title: trimmedTitle.isEmpty ? "Imported Chart" : trimmedTitle,
            rows: rows, staffPageNumbers: drawnBarlineRows.count == rows.count ? pageNumbers : nil,
            pdfPageNumbers: pageNumbers, drawnBarlineRows: drawnBarlineRows)
    }

    private struct PageDraft {
        let rows: [[String]]
        let usesDrawnBarlines: Bool
    }

    private static func readPage(_ page: PDFPage, text: String, pageNumber: Int, title: String) throws -> PageDraft {
        if let rows = try IRealPDFMeasureReader.read(from: page, text: text) {
            return PageDraft(rows: rows, usesDrawnBarlines: true)
        }
        if text.contains("|") {
            let gridText = try PDFStaffChordReader.textRemovingOverprintedGlyphs(text, from: page)
            if let grid = try? PDFEditableChartDraft.read(title: title, pages: [gridText]) {
                return PageDraft(rows: grid.rows, usesDrawnBarlines: false)
            }
        }
        let systems: [PDFStaffSystemGeometry]
        do {
            systems = try PDFStaffBarlineDetector.detect(in: page)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PDFEditableChartReadError.unsupportedStaffPage(pageNumber)
        }
        guard !systems.isEmpty else {
            throw PDFEditableChartReadError.unsupportedStaffPage(pageNumber)
        }
        let rows = try PDFStaffChordReader.read(from: page, systems: systems)
        return PageDraft(rows: rows, usesDrawnBarlines: true)
    }
}

/// Branded iReal Pro PDFs can expose a separate accessibility text label for
/// each measure. These labels avoid ambiguities in the notation font's text.
private enum IRealPDFMeasureReader {
    // PDFKit may join two marked runs without a separator ("Bar LineBar 2").
    private static let measureLabel = try! NSRegularExpression(pattern: #"Bar ([0-9]+),[ \t]*"#)
    private static let endOfLabel = try! NSRegularExpression(pattern:
        #"(?i)(?:(?:opening|closing) (?:repeat|double|final) )?bar line|(?:first|second|third|fourth) ending|made with iReal Pro"#)
    private static let spokenChord = try! NSRegularExpression(pattern:
        #"^[ \t]*('[A-G]'|[a-g])(?: (Flat|Sharp))?(?: (Half Diminished|Diminished|Augmented|Minor|Major))?(?: (13|11|9|7|6|5|4|2))?(?:[ \t]*(Sus(?:2|4)?))?(?: Over ('[A-G]'|[a-g])(?: (Flat|Sharp))?)?"#)

    private struct Measure {
        let chordText: String
        let frame: CGRect
    }

    static func read(from page: PDFPage, text: String) throws -> [[String]]? {
        guard text.contains("Made with iReal Pro") else { return nil }
        let source = text as NSString
        let labels = measureLabel.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !labels.isEmpty else { return nil }
        let barNumbers = labels.map { source.substring(with: $0.range(at: 1)) }
        let originalDescriptions = invisibleMeasureDescriptions(in: page, barNumbers: barNumbers)

        var measures: [Measure] = []
        for (index, label) in labels.enumerated() {
            try Task.checkCancellation()
            guard let frame = page.selection(for: label.range)?.bounds(for: page).standardized,
                  !frame.isEmpty, [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            else { return nil }

            let start = NSMaxRange(label.range)
            let end = index + 1 < labels.count ? labels[index + 1].range.location : source.length
            let tail = NSRange(location: start, length: end - start)
            let terminator = endOfLabel.firstMatch(in: text, range: tail)?.range.location ?? end
            let description = (originalDescriptions[barNumbers[index]]
                ?? source.substring(with: NSRange(location: start, length: terminator - start)))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let chordText = chords(in: description) ?? "[\(description)]"
            measures.append(Measure(chordText: chordText, frame: frame))
        }

        var rows: [[Measure]] = []
        for measure in measures.sorted(by: { $0.frame.minY > $1.frame.minY }) {
            if let first = rows.last?.first,
               first.frame.minY - measure.frame.minY <= min(first.frame.height, measure.frame.height) * 0.85 {
                rows[rows.count - 1].append(measure)
            } else {
                rows.append([measure])
            }
        }
        // The accessibility bar numbers can skip across alternate endings.
        // The label positions preserve the displayed, unexpanded chart order.
        return rows.map { row in
            row.sorted(by: { $0.frame.minX < $1.frame.minX }).map(\.chordText)
        }
    }

    private static func invisibleMeasureDescriptions(in page: PDFPage, barNumbers: [String]) -> [String: String] {
        guard let reference = page.pageRef else { return [:] }
        var descriptions: [String: String] = [:]
        var activeBar: String?
        for text in InvisibleText.read(reference) {
            let span = text as NSString
            let range = NSRange(location: 0, length: span.length)
            var start = 0
            if let label = measureLabel.firstMatch(in: text, options: .anchored, range: range) {
                let bar = span.substring(with: label.range(at: 1))
                guard descriptions[bar] == nil else { return [:] }
                descriptions[bar] = ""
                activeBar = bar
                start = NSMaxRange(label.range)
            }
            guard let bar = activeBar else { continue }
            let rest = NSRange(location: start, length: span.length - start)
            let end = endOfLabel.firstMatch(in: text, range: rest)?.range.location
            descriptions[bar, default: ""] += " " + span.substring(with:
                NSRange(location: start, length: (end ?? span.length) - start))
            if end != nil { activeBar = nil }
        }
        // PDFKit provides positions, but its reading order can mix headings
        // into the speech labels. Prefer the original spans when their bar IDs
        // match every positioned measure one for one.
        return descriptions.count == barNumbers.count
            && Set(descriptions.keys) == Set(barNumbers) ? descriptions : [:]
    }

    private static func chords(in description: String) -> String? {
        let source = description as NSString
        var remaining = NSRange(location: 0, length: source.length)
        var result: [String] = []
        while remaining.length > 0 {
            let tail = source.substring(with: remaining)
            guard let match = spokenChord.firstMatch(in: tail, range: NSRange(location: 0, length: remaining.length))
            else { return nil }

            let chord = tail as NSString
            func capture(_ index: Int) -> String {
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : chord.substring(with: range)
            }
            let pitch = pitchName(capture(1), accidental: capture(2))
            let bassPitch = capture(6)
            let bass = bassPitch.isEmpty ? "" : "/" + pitchName(bassPitch, accidental: capture(7))
            let suffix: String
            switch capture(3) {
            case "Minor": suffix = "m"
            case "Major": suffix = capture(4).isEmpty ? "" : "maj"
            case "Diminished": suffix = "°"
            case "Half Diminished": suffix = "ø"
            case "Augmented": suffix = "+"
            default: suffix = ""
            }
            let token = pitch + suffix + capture(4) + capture(5).lowercased() + bass
            guard PDFEditableChartDraft.parsedChordToken(token) != nil else { return nil }
            result.append(token)
            remaining.location += match.range.length
            remaining.length -= match.range.length
        }
        return result.joined(separator: " ")
    }

    private static func pitchName(_ pitch: String, accidental: String) -> String {
        let accidentalText: String
        switch accidental {
        case "Flat": accidentalText = "b"
        case "Sharp": accidentalText = "#"
        default: accidentalText = ""
        }
        return pitch.trimmingCharacters(in: CharacterSet(charactersIn: "'")).uppercased() + accidentalText
    }

    private final class InvisibleText {
        var mode: CGPDFInteger = 0
        var savedModes: [CGPDFInteger] = []
        var spans: [String] = []

        static func read(_ page: CGPDFPage) -> [String] {
            let reader = InvisibleText()
            guard let operators = CGPDFOperatorTableCreate() else { return [] }
            defer { CGPDFOperatorTableRelease(operators) }
            CGPDFOperatorTableSetCallback(operators, "q") { _, info in
                guard let info else { return }
                let reader = Unmanaged<InvisibleText>.fromOpaque(info).takeUnretainedValue()
                reader.savedModes.append(reader.mode)
            }
            CGPDFOperatorTableSetCallback(operators, "Q") { _, info in
                guard let info else { return }
                let reader = Unmanaged<InvisibleText>.fromOpaque(info).takeUnretainedValue()
                if let mode = reader.savedModes.popLast() { reader.mode = mode }
            }
            CGPDFOperatorTableSetCallback(operators, "Tr") { scanner, info in
                guard let info else { return }
                let reader = Unmanaged<InvisibleText>.fromOpaque(info).takeUnretainedValue()
                var mode: CGPDFInteger = 0
                if CGPDFScannerPopInteger(scanner, &mode) { reader.mode = mode }
            }
            CGPDFOperatorTableSetCallback(operators, "Tj") { scanner, info in
                guard let info else { return }
                let reader = Unmanaged<InvisibleText>.fromOpaque(info).takeUnretainedValue()
                var value: CGPDFStringRef?
                if reader.mode == 3, CGPDFScannerPopString(scanner, &value),
                   let value, let text = CGPDFStringCopyTextString(value) as String? {
                    reader.spans.append(text)
                }
            }
            let stream = CGPDFContentStreamCreateWithPage(page)
            defer { CGPDFContentStreamRelease(stream) }
            let scanner = CGPDFScannerCreate(stream, operators, Unmanaged.passUnretained(reader).toOpaque())
            defer { CGPDFScannerRelease(scanner) }
            return CGPDFScannerScan(scanner) ? reader.spans : []
        }
    }
}

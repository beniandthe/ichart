import Foundation

/// The editable chord fields and their original PDF row order.
struct PDFEditableChartDraft: Sendable {
    var title: String
    var rows: [[String]]
    var staffPageNumbers: [Int]? = nil
    var pdfPageNumbers: [Int]? = nil
    var drawnBarlineRows: Set<Int>? = nil

    var usesDrawnBarlines: Bool {
        drawnBarlineRows.map { !$0.isEmpty } ?? (staffPageNumbers != nil)
    }

    func usesDrawnBarlines(inRow rowIndex: Int) -> Bool {
        drawnBarlineRows?.contains(rowIndex) ?? usesDrawnBarlines
    }

    func sourcePageNumber(forRow rowIndex: Int) -> Int? {
        guard let pages = sourcePageNumbers, pages.indices.contains(rowIndex) else { return nil }
        return pages[rowIndex]
    }

    func rowLabel(_ rowIndex: Int) -> String {
        guard let pages = sourcePageNumbers, let page = sourcePageNumber(forRow: rowIndex) else {
            return "Row \(rowIndex + 1)"
        }
        let rowOnPage = pages.prefix(rowIndex + 1).count { $0 == page }
        return "PDF page \(page) · Row \(rowOnPage)"
    }

    private var sourcePageNumbers: [Int]? { pdfPageNumbers ?? staffPageNumbers }

    func reviewIssue(forMeasure text: String, rowIndex: Int? = nil) -> String? {
        let preservesEmptyMeasure = rowIndex.map { usesDrawnBarlines(inRow: $0) } ?? usesDrawnBarlines
        if preservesEmptyMeasure && Self.chordTokens(in: text).isEmpty { return nil }
        return Self.issue(forMeasure: text)
    }

    func previewText(forMeasure text: String, rowIndex: Int? = nil) -> String {
        guard reviewIssue(forMeasure: text, rowIndex: rowIndex) == nil else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Self.chordTokens(in: text).compactMap(Self.parsedChordToken)
            .map(\.displayText).joined(separator: "   ")
    }

    static func read(title: String, pages: [String]) throws -> Self {
        guard pages.count == 1 else { throw PDFEditableChartDraftError.singlePageRequired }
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = pages[0].components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var rows: [[String]] = []
        var hasTitle = false
        var hasMeter = false

        for line in lines {
            if rows.isEmpty, !hasTitle, normalizedHeader(line) == normalizedHeader(resolvedTitle) {
                hasTitle = true
                continue
            }
            if rows.isEmpty, !hasMeter, line == "4/4" {
                hasMeter = true
                continue
            }
            guard line.contains("|") else { throw PDFEditableChartDraftError.unsupportedStructure }
            guard !containsRepeatStructure(line) else { throw PDFEditableChartDraftError.unsupportedStructure }
            var measures = line.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if measures.first?.isEmpty == true { measures.removeFirst() }
            if measures.last?.isEmpty == true { measures.removeLast() }
            let maximumMeasures = ChartLayoutStyle.simpleChordSheet.profile.measureDefaults.maximumMeasuresPerSystem
                ?? Int.max
            guard !measures.isEmpty, measures.count <= maximumMeasures else {
                throw PDFEditableChartDraftError.unsupportedStructure
            }
            rows.append(measures)
        }

        guard !rows.isEmpty else { throw PDFEditableChartDraftError.noChordRows }
        return Self(title: resolvedTitle.isEmpty ? "Imported Chart" : resolvedTitle, rows: rows)
    }

    static func issue(forMeasure text: String) -> String? {
        let tokens = chordTokens(in: text)
        guard !tokens.isEmpty else { return "Enter the chord or chords for this measure." }
        guard !text.contains(where: { $0.isNewline }), !text.contains("|") else {
            return "Keep this measure on one line and enter chords without barlines."
        }
        guard !containsRepeatStructure(text) else {
            return "Enter the chords for this measure. Repeat notation needs to be added on the chart."
        }
        guard tokens.count <= 4 else { return "Use up to four space-separated chords in this 4/4 measure." }
        guard tokens.allSatisfy({ parsedChordToken($0) != nil }) else {
            return "Check each chord and separate chords with spaces."
        }
        return nil
    }

    static func parsedChordToken(_ token: String) -> ChordSymbol? {
        guard let symbol = try? ChordSymbolParser.parse(normalizedChordToken(token)),
              symbol.kind == .rooted else { return nil }
        return symbol
    }

    static func normalizedChordToken(_ token: String) -> String {
        // Some music fonts expose their drawing codes in the PDF text layer.
        let fontNormalized = token.replacingOccurrences(of: "Œ„Š", with: "maj")
        return String(fontNormalized.map { character in
            switch character {
            case "©": "#"
            case "¨": "b"
            case "‹": "m"
            case "−", "⁻": "-"
            case "⁺": "+"
            case "∕", "⁄": "/"
            case "⁽": "("
            case "⁾": ")"
            case "⁰": "0"
            case "¹": "1"
            case "²": "2"
            case "³": "3"
            case "⁴": "4"
            case "⁵": "5"
            case "⁶": "6"
            case "⁷": "7"
            case "⁸": "8"
            case "⁹": "9"
            default: character
            }
        })
    }

    func makeChart(sourcePDFLibraryItemID: UUID) throws -> Chart {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedTitle.isEmpty, !rows.isEmpty, rows.allSatisfy({ !$0.isEmpty }) else {
            throw PDFEditableChartDraftError.noChordRows
        }
        let maximumMeasures = ChartLayoutStyle.simpleChordSheet.profile.measureDefaults.maximumMeasuresPerSystem
            ?? Int.max
        guard rows.allSatisfy({ $0.count <= maximumMeasures }) else {
            throw PDFEditableChartDraftError.unsupportedStructure
        }
        for (rowIndex, row) in rows.enumerated() {
            for (measureIndex, text) in row.enumerated() {
                if let issue = reviewIssue(forMeasure: text, rowIndex: rowIndex) {
                    throw PDFEditableChartDraftError.invalidMeasure(row: rowIndex + 1,
                        measure: measureIndex + 1, issue: issue)
                }
            }
        }

        var chart = Chart.blank(title: resolvedTitle, measureCount: rows.flatMap { $0 }.count,
            layoutStyle: .simpleChordSheet)
        chart.sourcePDFLibraryItemID = sourcePDFLibraryItemID
        let initialMeasures = chart.measures
        var measureIndex = 0
        chart.systems = try rows.enumerated().map { rowIndex, row in
            let usesDrawnBarlines = usesDrawnBarlines(inRow: rowIndex)
            let measures = try row.map { text in
                var measure = initialMeasures[measureIndex]
                measureIndex += 1
                if usesDrawnBarlines { measure.authoringState = .committed }
                let tokens = Self.chordTokens(in: text)
                for (chordIndex, token) in tokens.enumerated() {
                    let quarterBeatNumerator = 4 * chordIndex
                    let position = BeatPosition(beat: quarterBeatNumerator / tokens.count + 1,
                        subdivision: quarterBeatNumerator % tokens.count, subdivisionsPerBeat: tokens.count)
                    let suggestion = MeasureChordInsertionSuggestion(startPosition: position,
                        duration: .slash, mappedRhythmSlotIndex: nil)
                    let normalizedToken = Self.normalizedChordToken(token)
                    _ = measure.appendChordEvent(symbol: try ChordSymbolParser.parse(normalizedToken),
                        spellingIntent: usesDrawnBarlines ? .explicit : .automatic,
                        rawInput: normalizedToken, suggestion: suggestion)
                }
                return measure
            }
            return ChartSystem(id: UUID(), index: rowIndex,
                spacingMode: chart.layoutStyle.profile.measureDefaults.systemSpacingMode,
                lineBreakRule: rowIndex == 0 ? .automatic : .forced, measures: measures)
        }
        return chart
    }

    private static func chordTokens(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func normalizedHeader(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func containsRepeatStructure(_ text: String) -> Bool {
        text.contains(":") || text.contains("%") || text.contains("./.")
            || text.contains("𝄆") || text.contains("𝄇") || text.contains("𝄋") || text.contains("𝄌")
    }
}

enum PDFEditableChartDraftError: LocalizedError {
    case singlePageRequired
    case noChordRows
    case unsupportedStructure
    case invalidMeasure(row: Int, measure: Int, issue: String)

    var errorDescription: String? {
        switch self {
        case .singlePageRequired:
            return "iChart couldn't read this chord grid. Use a PDF with selectable chords and clear barlines."
        case .noChordRows:
            return "iChart couldn't find any chord rows in this PDF."
        case .unsupportedStructure:
            return "Use a 4/4 chord grid with clear barlines. Add repeats after saving the editable chart."
        case let .invalidMeasure(row, measure, issue):
            return "Row \(row), measure \(measure). \(issue)"
        }
    }
}

import Foundation

/// A reviewable chord grid extracted from the selectable text of one PDF page.
struct PDFEditableChartDraft: Sendable {
    var title: String
    var rows: [[String]]

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
        guard tokens.allSatisfy({ (try? ChordSymbolParser.parse($0)) != nil }) else {
            return "Check each chord and separate chords with spaces."
        }
        return nil
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
                if let issue = Self.issue(forMeasure: text) {
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
            let measures = try row.map { text in
                var measure = initialMeasures[measureIndex]
                measureIndex += 1
                let tokens = Self.chordTokens(in: text)
                for (chordIndex, token) in tokens.enumerated() {
                    let quarterBeatNumerator = 4 * chordIndex
                    let position = BeatPosition(beat: quarterBeatNumerator / tokens.count + 1,
                        subdivision: quarterBeatNumerator % tokens.count, subdivisionsPerBeat: tokens.count)
                    let suggestion = MeasureChordInsertionSuggestion(startPosition: position,
                        duration: .slash, mappedRhythmSlotIndex: nil)
                    _ = measure.appendChordEvent(symbol: try ChordSymbolParser.parse(token),
                        rawInput: token, suggestion: suggestion)
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
            return "Choose a one-page PDF with selectable chord text."
        case .noChordRows:
            return "No chord rows were found. Use a PDF with selectable chords separated by | barlines."
        case .unsupportedStructure:
            return "Use a one-page chord grid with | barlines and optional 4/4. Lyrics, repeats, and other structures need a different import."
        case let .invalidMeasure(row, measure, issue):
            return "Row \(row), measure \(measure). \(issue)"
        }
    }
}

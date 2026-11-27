import Foundation
import XCTest
@testable import iChart

final class PDFEditableChartDraftTests: XCTestCase {
    func testReadsExplicitBarlineRowsAndMatchingTitleWithoutChangingCells() throws {
        let draft = try PDFEditableChartDraft.read(title: "Blue Room", pages: ["""
            BLUE  ROOM
            4/4
            | Bb∆7 | Dm7   G7 | Cmaj7 |
            F7 | E?7 | G7 C7
            """])

        XCTAssertEqual(draft.title, "Blue Room")
        XCTAssertEqual(draft.rows, [["Bb∆7", "Dm7   G7", "Cmaj7"], ["F7", "E?7", "G7 C7"]])
        XCTAssertNil(PDFEditableChartDraft.issue(forMeasure: draft.rows[0][0]))
        XCTAssertNotNil(PDFEditableChartDraft.issue(forMeasure: draft.rows[1][1]))
        XCTAssertThrowsError(try draft.makeChart(sourcePDFLibraryItemID: UUID()))
    }

    func testEmptyAndQuestionableMeasuresRemainForCorrectionBeforeSaving() throws {
        var draft = try PDFEditableChartDraft.read(title: "Review me", pages: ["| C | | not-a-chord |"])
        XCTAssertEqual(draft.rows, [["C", "", "not-a-chord"]])
        XCTAssertNotNil(PDFEditableChartDraft.issue(forMeasure: draft.rows[0][1]))
        XCTAssertNotNil(PDFEditableChartDraft.issue(forMeasure: draft.rows[0][2]))
        XCTAssertThrowsError(try draft.makeChart(sourcePDFLibraryItemID: UUID()))

        draft.rows[0][1] = "Fm7"
        draft.rows[0][2] = "Bb7"
        let chart = try draft.makeChart(sourcePDFLibraryItemID: UUID())
        XCTAssertEqual(chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["C", "Fm7", "Bb7"])
    }

    func testCreatesSimpleFourFourChartWithOriginalRowsAndEvenlyTimedChords() throws {
        let draft = try PDFEditableChartDraft.read(title: "A grid", pages: ["""
            | C | Dm7 G7 |
            | C F G | Am D7 G7 C |
            """])
        let sourceID = UUID()
        let chart = try draft.makeChart(sourcePDFLibraryItemID: sourceID)

        XCTAssertEqual(chart.title, "A grid")
        XCTAssertEqual(chart.layoutStyle, .simpleChordSheet)
        XCTAssertEqual(chart.defaultMeter, Meter(numerator: 4, denominator: 4))
        XCTAssertTrue(chart.hasCompletedInitialSetup)
        XCTAssertEqual(chart.sourcePDFLibraryItemID, sourceID)
        XCTAssertEqual(chart.systems.map { $0.measures.count }, [2, 2])
        XCTAssertEqual(chart.systems.map(\.lineBreakRule), [.automatic, .forced])
        XCTAssertEqual(chart.measures.map(\.index), [1, 2, 3, 4])
        XCTAssertEqual(chart.measures.map { $0.chordEvents.map(\.rawInput) },
            [["C"], ["Dm7", "G7"], ["C", "F", "G"], ["Am", "D7", "G7", "C"]])
        for measure in chart.measures {
            for (index, chord) in measure.chordEvents.enumerated() {
                XCTAssertEqual(try XCTUnwrap(chord.startPosition.startOffset(in: chart.defaultMeter)),
                    Double(index) / Double(measure.chordEvents.count), accuracy: 0.000001)
                XCTAssertNil(chord.sourceInkData)
            }
        }
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        XCTAssertEqual(reopened, chart)
    }

    func testRejectsUnsupportedStructureInsteadOfDroppingTextOrInferringMeasures() {
        for pages in [
            ["| C |", "| F |"],
            ["A lyric line\n| C |"],
            ["Wrong title\n| C |"],
            ["3/4\n| C |"],
            ["|: C | F :|"],
            ["| C | % |"],
            ["C F G"],
            [""]
        ] {
            XCTAssertThrowsError(try PDFEditableChartDraft.read(title: "Title", pages: pages),
                "Unsupported extraction must keep the user in the source PDF flow")
        }
    }

    func testMeasureReviewUsesTheProductionParserAndRejectsRepeatAndOversizedCells() {
        for text in ["C", "Bb∆7", "F#m7b5", "C6/9", "Dm7 G7", "C/E F G7 C"] {
            XCTAssertNil(PDFEditableChartDraft.issue(forMeasure: text), text)
        }
        for text in ["", " ", "C | G", "C\nG", "%", "./.", "|: C", "C F G Am D7", "C?7"] {
            XCTAssertNotNil(PDFEditableChartDraft.issue(forMeasure: text), text)
        }
    }

    func testPDFGlyphsAreReadyForReviewAndSaveWithTheirMusicalMeaning() throws {
        let draft = try PDFEditableChartDraft.read(title: "Printed symbols", pages: [
            "| B♭∆⁷ | C⁷⁽♯⁹⁾ | FŒ„Š⁷∕A |\n| G¨‹⁷ | EØ⁷ | A−⁷ C©⁷ |"
        ])
        let expected = try ["Bb∆7", "C7(#9)", "Fmaj7/A", "Gbm7", "Eø7", "A-7", "C#7"]
            .map(ChordSymbolParser.parse)

        XCTAssertEqual(draft.rows[0], ["B♭∆⁷", "C⁷⁽♯⁹⁾", "FŒ„Š⁷∕A"])
        XCTAssertTrue(draft.rows.flatMap { $0 }.allSatisfy { draft.reviewIssue(forMeasure: $0) == nil })
        XCTAssertEqual(draft.previewText(forMeasure: draft.rows[0][0]), "Bb△7")
        XCTAssertEqual(draft.previewText(forMeasure: draft.rows[1][2]), "A-7   C#7")
        let chart = try draft.makeChart(sourcePDFLibraryItemID: UUID())
        XCTAssertEqual(chart.measures.flatMap(\.chordEvents).map(\.symbol), expected)
    }

    func testUnexpectedGlyphsStayAsSourceTextUntilCorrected() {
        let draft = PDFEditableChartDraft(title: "Source", rows: [])
        for source in ["DDmm77", "FFŒŒ„„ŠŠ77", "F�7", "C7??", "A/Bb/C", "•/•"] {
            XCTAssertNotNil(draft.reviewIssue(forMeasure: source), source)
            XCTAssertEqual(draft.previewText(forMeasure: source), source)
        }
    }

    func testMixedPDFRowsUseTheirOwnBlankAndSpellingRules() throws {
        var draft = PDFEditableChartDraft(title: "Mixed", rows: [["C#", ""], ["C#", ""], ["G"]],
            pdfPageNumbers: [1, 2, 2], drawnBarlineRows: [1, 2])

        XCTAssertEqual(draft.rowLabel(0), "PDF page 1 · Row 1")
        XCTAssertEqual(draft.rowLabel(2), "PDF page 2 · Row 2")
        XCTAssertEqual(draft.sourcePageNumber(forRow: 1), 2)
        XCTAssertNotNil(draft.reviewIssue(forMeasure: "", rowIndex: 0))
        XCTAssertNil(draft.reviewIssue(forMeasure: "", rowIndex: 1))
        XCTAssertThrowsError(try draft.makeChart(sourcePDFLibraryItemID: UUID()))

        draft.rows[0][1] = "D"
        let chart = try draft.makeChart(sourcePDFLibraryItemID: UUID())
        XCTAssertEqual(chart.measures.map { $0.chordEvents.count }, [1, 1, 1, 0, 1])
        XCTAssertEqual(chart.measures[0].chordEvents[0].spellingIntent, .automatic)
        XCTAssertEqual(chart.measures[2].chordEvents[0].spellingIntent, .explicit)
    }

    func testDraftEditedToAnInvalidGridCannotCreateAnEmptyOrUnsupportedChart() throws {
        for rows in [[], [[]], [["C", "G", ""]]] as [[[String]]] {
            let draft = PDFEditableChartDraft(title: "Draft", rows: rows)
            XCTAssertThrowsError(try draft.makeChart(sourcePDFLibraryItemID: UUID()))
        }
        let blankTitle = PDFEditableChartDraft(title: " \n ", rows: [["C"]])
        XCTAssertThrowsError(try blankTitle.makeChart(sourcePDFLibraryItemID: UUID()))
    }
}

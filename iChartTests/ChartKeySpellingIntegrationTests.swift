import XCTest
@testable import iChart

final class ChartKeySpellingIntegrationTests: XCTestCase {
    func testFreshExplicitChartInsertionHasItsEffectiveKeyScopeAndImportedExplicitTextDoesNot() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Explicit insertions", key: .cMajor,
                measureCount: 2, layoutStyle: style)
            let measureIDs = chart.measures.map(\.id)
            chart.keyChanges = [KeyChange(measureID: measureIDs[1], key: .dFlatMajor)]
            let automaticID = try XCTUnwrap(chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("F#"), rawInput: "F#", to: measureIDs[1], atFraction: 0))
            let explicitID = try XCTUnwrap(chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("F#"), rawInput: "F#", to: measureIDs[1],
                atFraction: 0.5, spellingIntent: .explicit))
            let automatic = try XCTUnwrap(chart.chordEvent(id: automaticID))
            let manual = try XCTUnwrap(chart.chordEvent(id: explicitID))
            XCTAssertNil(automatic.spellingOverrideKey)
            XCTAssertEqual(manual.spellingOverrideKey, .dFlatMajor)
            XCTAssertEqual(chart.displayedChordSymbol(for: automatic, in: measureIDs[1]),
                try ChordSymbolParser.parse("Gb"))
            XCTAssertEqual(chart.displayedChordSymbol(for: manual, in: measureIDs[1]),
                try ChordSymbolParser.parse("F#"))
            XCTAssertEqual(try reopen(chart), chart)
        }

        var imported = try PDFEditableChartDraft(title: "PDF source spellings",
            rows: [["F#", "A#m"]], staffPageNumbers: [1]).makeChart(sourcePDFLibraryItemID: UUID())
        imported.documentKey = .dFlatMajor
        XCTAssertTrue(imported.measures.flatMap(\.chordEvents).allSatisfy {
            $0.spellingIntent == .explicit && $0.spellingOverrideKey == nil
        })
        try assertDisplayed(imported, equals: ["Gb", "Bbm"])
    }

    func testExistingUnscopedExplicitChordsFollowTheCurrentKeyWithoutMutatingTheirSources() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = try fixture(style: style, key: .dFlatMajor,
                chords: ["C#", "A#m", "F#", "D#m/G#"])
            for index in chart.systems[0].measures.indices {
                chart.systems[0].measures[index].chordEvents[0].spellingIntent = .explicit
                chart.systems[0].measures[index].chordEvents[0].spellingOverrideSource = .userSelection
                chart.systems[0].measures[index].chordEvents[0].spellingOverrideKey = nil
            }
            let original = chart
            try assertDisplayed(chart, equals: ["Db", "Bbm", "Gb", "Ebm/Ab"])
            XCTAssertEqual(chart, original, "Displaying a saved chart must preserve its source records")
            let reopened = try reopen(chart)
            try assertDisplayed(reopened, equals: ["Db", "Bbm", "Gb", "Ebm/Ab"])
            XCTAssertEqual(reopened.measures.map(\.chordEvents), chart.measures.map(\.chordEvents))
        }
    }

    func testManualSpellingChoiceIsScopedToItsKeyAndEnharmonicKeyChangesClearIt() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = try fixture(style: style, key: .dFlatMajor, chords: ["Gb"])
            let eventID = try XCTUnwrap(chart.measures.first?.chordEvents.first?.id)
            XCTAssertTrue(chart.replaceChordEvent(eventID,
                with: try ChordSymbolParser.parse("F#"), rawInput: "F#"))
            XCTAssertEqual(chart.chordEvent(id: eventID)?.spellingOverrideKey, .dFlatMajor)
            try assertDisplayed(chart, equals: ["F#"])
            let selected = try reopen(chart)
            try assertDisplayed(selected, equals: ["F#"])

            XCTAssertTrue(chart.setDocumentKey(.cSharpMajor))
            XCTAssertNil(chart.chordEvent(id: eventID)?.spellingOverrideKey)
            try assertDisplayed(chart, equals: ["F#"])
            XCTAssertTrue(chart.setDocumentKey(.dFlatMajor))
            try assertDisplayed(chart, equals: ["Gb"])
            XCTAssertEqual(chart.chordEvent(id: eventID)?.id, eventID)
            XCTAssertEqual(chart.chordEvent(id: eventID)?.symbol,
                try ChordSymbolParser.parse("Gb"))
        }
    }

    func testDisplayedManualCorrectionsPreserveConcertPitchesInBbAndEbViews() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            for (view, chosen) in [(TranspositionView.bb, "D#m/A#"), (.eb, "A#m/E#")] {
                var chart = try fixture(style: style, key: .cMajor, chords: ["Dbm/Ab"])
                let original = try XCTUnwrap(chart.measures.first?.chordEvents.first)
                let measureID = try XCTUnwrap(chart.measures.first?.id)
                chart.setInstrumentTranspositionView(view)
                let choice = try ChordSymbolParser.parse(chosen)
                XCTAssertTrue(chart.replaceDisplayedChordEvent(original.id, with: choice, rawInput: chosen))
                let stored = try XCTUnwrap(chart.chordEvent(id: original.id))
                XCTAssertEqual(rootPitch(stored.symbol), rootPitch(original.symbol))
                XCTAssertEqual(bassPitch(stored.symbol), bassPitch(original.symbol))
                XCTAssertEqual(stored.symbol.quality, original.symbol.quality)
                XCTAssertEqual(stored.spellingOverrideKey, .cMajor)
                XCTAssertEqual(chart.displayedChordSymbol(for: stored, in: measureID), choice)
                let reopened = try reopen(chart)
                XCTAssertEqual(reopened, chart)
                XCTAssertEqual(reopened.displayedChordSymbol(
                    for: try XCTUnwrap(reopened.chordEvent(id: original.id)), in: measureID), choice)
                chart.setInstrumentTranspositionView(.concert)
                XCTAssertEqual(rootPitch(try XCTUnwrap(chart.chordEvent(id: original.id)).symbol),
                    rootPitch(original.symbol))
            }
        }
    }

    func testChordOnlyHalfStepsKeepTheKeyAndUseItsSpellingWithoutChangingOtherEventData() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = try fixture(style: style, key: .dFlatMajor, chords: ["Am7/E"])
            chart.systems[0].measures[0].chordEvents[0].sourceInkData = Data([1, 2, 3, 4])
            chart.systems[0].measures[0].chordEvents[0].sourceCandidateSignature = ["Am7/E", "A7/E"]
            chart.systems[0].measures[0].chordEvents[0].manualDisplayWidth = 90
            let original = try XCTUnwrap(chart.measures.first?.chordEvents.first)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            let frameIntent = chart.measure(id: measureID)?.paperLayout
            chart.transposeChordsByHalfSteps(1)
            let stored = try XCTUnwrap(chart.chordEvent(id: original.id))
            XCTAssertEqual(chart.documentKey, .dFlatMajor)
            XCTAssertEqual(stored.symbol, try ChordSymbolParser.parse("Bbm7/F"))
            XCTAssertEqual(stored.sourceInkData, original.sourceInkData)
            XCTAssertEqual(stored.sourceCandidateSignature, original.sourceCandidateSignature)
            XCTAssertEqual(stored.manualDisplayWidth, original.manualDisplayWidth)
            XCTAssertEqual(stored.startPosition, original.startPosition)
            XCTAssertEqual(stored.duration, original.duration)
            XCTAssertEqual(stored.rhythmPlacement, original.rhythmPlacement)
            XCTAssertEqual(stored.tieOut, original.tieOut)
            XCTAssertEqual(stored.hitStyle, original.hitStyle)
            XCTAssertEqual(chart.measure(id: measureID)?.paperLayout, frameIntent)
            XCTAssertEqual(chart.chordTranspositionSemitones, 0)
        }
    }

    func testLegacyOffsetBakesOnceUsingEachMeasuresCurrentKey() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = try fixture(style: style, key: .dFlatMajor, chords: ["Am", "G"])
            let ids = chart.measures.map(\.id)
            chart.keyChanges = [KeyChange(measureID: ids[1], key: .fSharpMajor)]
            let originalIDs = chart.measures.flatMap(\.chordEvents).map(\.id)
            var encoded = try XCTUnwrap(JSONSerialization.jsonObject(
                with: ChartPersistenceCoders.encoder.encode(chart)) as? [String: Any])
            encoded["chordTranspositionSemitones"] = 1
            let migrated = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: JSONSerialization.data(withJSONObject: encoded))
            XCTAssertEqual(migrated.documentKey, .dFlatMajor)
            XCTAssertEqual(migrated.keyChanges, chart.keyChanges)
            XCTAssertEqual(migrated.measures.flatMap(\.chordEvents).map(\.id), originalIDs)
            XCTAssertEqual(migrated.chordTranspositionSemitones, 0)
            XCTAssertEqual(migrated.measures[0].chordEvents[0].symbol,
                try ChordSymbolParser.parse("Bbm"))
            XCTAssertEqual(migrated.measures[1].chordEvents[0].symbol,
                try ChordSymbolParser.parse("G#"))
            XCTAssertEqual(try reopen(migrated), migrated)
        }
    }

    private func fixture(style: ChartLayoutStyle, key: DocumentKey, chords: [String]) throws -> Chart {
        var chart = Chart.blank(title: "Disposable key spelling", key: key,
            measureCount: chords.count, layoutStyle: style)
        let ids = chart.measures.map(\.id)
        for (index, text) in chords.enumerated() {
            XCTAssertNotNil(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse(text),
                rawInput: text, to: ids[index], atFraction: 0))
        }
        return chart
    }

    private func assertDisplayed(_ chart: Chart, equals expected: [String],
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let events = chart.measures.flatMap { measure in
            measure.chordEvents.map { chart.displayedChordSymbol(for: $0, in: measure.id) }
        }
        XCTAssertEqual(events, try expected.map(ChordSymbolParser.parse), file: file, line: line)
    }

    private func rootPitch(_ symbol: ChordSymbol) -> Int {
        ChordPitch(root: symbol.root, accidental: symbol.accidental).semitone
    }

    private func bassPitch(_ symbol: ChordSymbol) -> Int? {
        symbol.slashBass.flatMap(ChordPitch.parse)?.semitone
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
    }
}

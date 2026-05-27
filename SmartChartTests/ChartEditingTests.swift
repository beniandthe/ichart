import XCTest
@testable import SmartChart

final class ChartEditingTests: XCTestCase {
    func testAddCueTextUpdatesChartAndMeasure() {
        var chart = Chart.blank(title: "Test Chart")

        chart.addCueText("hits")

        XCTAssertEqual(chart.cueTexts.count, 1)
        XCTAssertEqual(chart.cueTexts.first?.text, "hits")
        XCTAssertEqual(chart.systems[0].measures[0].cueTextIDs, [chart.cueTexts[0].id])
    }

    func testAddRoadmapObjectUpdatesChartAndMeasure() {
        var chart = Chart.blank(title: "Test Chart")

        chart.addRoadmapObject(.dcAlFine)

        XCTAssertEqual(chart.roadmapObjects.count, 1)
        XCTAssertEqual(chart.roadmapObjects.first?.type, .dcAlFine)
        XCTAssertEqual(chart.systems[0].measures[0].roadmapObjectIDs, [chart.roadmapObjects[0].id])
    }

    func testDocumentKeyTransposesForBbView() {
        let displayedKey = DocumentKey.cMajor.transposed(for: .bb)

        XCTAssertEqual(displayedKey.tonic, .d)
        XCTAssertEqual(displayedKey.accidental, .natural)
        XCTAssertEqual(displayedKey.mode, .major)
    }

    func testDocumentKeyConcertViewPreservesWrittenEnharmonicSpelling() {
        let writtenKey = DocumentKey(tonic: .c, accidental: .flat, mode: .major)
        let displayedKey = writtenKey.transposed(for: .concert)

        XCTAssertEqual(displayedKey.tonic, .c)
        XCTAssertEqual(displayedKey.accidental, .flat)
        XCTAssertEqual(displayedKey.displayText, "Cb major")
    }

    func testCompleteInitialSetupStoresPromptSelections() {
        var chart = Chart.draft(title: "New Chart")

        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .bFlatMajor,
            meter: Meter(numerator: 6, denominator: 8),
            staffStyle: .fiveLine
        )

        XCTAssertEqual(chart.title, "Pocket Groove")
        XCTAssertEqual(chart.documentKey, .bFlatMajor)
        XCTAssertEqual(chart.defaultMeter, Meter(numerator: 6, denominator: 8))
        XCTAssertEqual(chart.staffStyle, .fiveLine)
        XCTAssertTrue(chart.hasCompletedInitialSetup)
        XCTAssertEqual(chart.systems.count, 1)
        XCTAssertEqual(chart.systems[0].measures.count, 1)
        XCTAssertEqual(chart.systems[0].measures[0].authoringState, .open)
    }

    func testAppearanceSettersUpdateDocumentAppearanceChoices() {
        var chart = Chart.blank(title: "Test Chart")

        chart.setStylePreset(.gigSheet)
        chart.setNotationFont(.finaleJazz)
        chart.setEngravingPreset(.wide)

        XCTAssertEqual(chart.stylePreset, .gigSheet)
        XCTAssertEqual(chart.notationFont, .finaleJazz)
        XCTAssertEqual(chart.engravingPreset, .wide)
    }

    func testChartDecodingDefaultsMissingAppearanceFieldsForOlderSnapshots() throws {
        let chart = Chart.blank(title: "Older Snapshot")
        let encodedData = try JSONEncoder().encode(chart)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        object.removeValue(forKey: "notationFont")
        object.removeValue(forKey: "engravingPreset")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decodedChart = try JSONDecoder().decode(Chart.self, from: legacyData)

        XCTAssertEqual(decodedChart.notationFont, .petaluma)
        XCTAssertEqual(decodedChart.engravingPreset, .balanced)
    }

    func testChordEventDecodingDefaultsMissingSourceCandidateSignature() throws {
        var chart = Chart.blank(title: "Older Chord Snapshot", key: .cMajor, measureCount: 1)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = try XCTUnwrap(ChordRecognitionCompendium.match("C")?.symbol)
        _ = chart.appendRecognizedChordEvent(
            symbol,
            rawInput: "C",
            to: measureID,
            atFraction: 0.05,
            sourceInkData: Data([1, 2, 3])
        )
        let encodedData = try JSONEncoder().encode(chart)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        var systems = try XCTUnwrap(object["systems"] as? [[String: Any]])
        var firstSystem = try XCTUnwrap(systems.first)
        var measures = try XCTUnwrap(firstSystem["measures"] as? [[String: Any]])
        var firstMeasure = try XCTUnwrap(measures.first)
        var chordEvents = try XCTUnwrap(firstMeasure["chordEvents"] as? [[String: Any]])
        var firstChordEvent = try XCTUnwrap(chordEvents.first)
        firstChordEvent.removeValue(forKey: "sourceCandidateSignature")
        chordEvents[0] = firstChordEvent
        firstMeasure["chordEvents"] = chordEvents
        measures[0] = firstMeasure
        firstSystem["measures"] = measures
        systems[0] = firstSystem
        object["systems"] = systems
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decodedChart = try JSONDecoder().decode(Chart.self, from: legacyData)

        XCTAssertEqual(decodedChart.measures.first?.chordEvents.first?.sourceCandidateSignature, [])
    }

    func testNotationGlyphCatalogProvidesSemanticSmuflSymbols() {
        XCTAssertEqual(NotationGlyphCatalog.trebleClef, "\u{E050}")
        XCTAssertEqual(NotationGlyphCatalog.noteheadWhole, "\u{E0A2}")
        XCTAssertEqual(NotationGlyphCatalog.noteheadHalf, "\u{E0A3}")
        XCTAssertEqual(NotationGlyphCatalog.noteheadBlack, "\u{E0A4}")
        XCTAssertEqual(NotationGlyphCatalog.slashNotehead, "\u{E100}")
        XCTAssertEqual(NotationGlyphCatalog.slashWholeNotehead, "\u{E102}")
        XCTAssertEqual(NotationGlyphCatalog.slashHalfNotehead, "\u{E103}")
        XCTAssertEqual(NotationGlyphCatalog.augmentationDot, "\u{E1E7}")
        XCTAssertEqual(NotationGlyphCatalog.flag8thUp, "\u{E240}")
        XCTAssertEqual(NotationGlyphCatalog.flag8thDown, "\u{E241}")
        XCTAssertEqual(NotationGlyphCatalog.wholeRest, "\u{E4E3}")
        XCTAssertEqual(NotationGlyphCatalog.halfRest, "\u{E4E4}")
        XCTAssertEqual(NotationGlyphCatalog.quarterRest, "\u{E4E5}")
        XCTAssertEqual(NotationGlyphCatalog.eighthRest, "\u{E4E6}")
        XCTAssertEqual(NotationGlyphCatalog.timeSignatureDigit(4), "\u{E084}")
        XCTAssertNil(NotationGlyphCatalog.timeSignatureDigit(12))
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .trebleClef), NotationGlyphCatalog.trebleClef)
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .noteheadBlack), NotationGlyphCatalog.noteheadBlack)
        XCTAssertEqual(NotationGlyphCatalog.glyph(for: .timeSignatureDigit(4)), "\u{E084}")
        XCTAssertNil(NotationGlyphCatalog.glyph(for: .timeSignatureDigit(12)))
        XCTAssertEqual(NotationGlyphCatalog.pointSize(for: .trebleClef, staffSpace: 10.5), 42, accuracy: 0.001)
    }

    func testNotationFontPresetsExposeOfficialSmuflEngravingDefaults() {
        XCTAssertEqual(NotationFontPreset.bravura.smuflEngravingDefaults.staffLineThickness, 0.13)
        XCTAssertEqual(NotationFontPreset.finaleJazz.smuflEngravingDefaults.stemThickness, 0.15)
        XCTAssertEqual(NotationFontPreset.leland.smuflEngravingDefaults.thickBarlineThickness, 0.55)
        XCTAssertEqual(NotationFontPreset.finaleEngraver.smuflEngravingDefaults.tieMidpointThickness, 0.25)
    }

    func testSetPageHandwrittenNotationDrawingStoresAndClearsRawInk() {
        var chart = Chart.draft(title: "New Chart")
        let drawingData = Data([4, 3, 2, 1])

        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(drawingData))
        XCTAssertEqual(chart.pageHandwrittenNotationData, drawingData)
        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(nil))
        XCTAssertNil(chart.pageHandwrittenNotationData)
    }

    func testSetPageHandwrittenChordDrawingStoresSeparatelyFromFreeHandInk() {
        var chart = Chart.draft(title: "New Chart")
        let freeHandData = Data([4, 3, 2, 1])
        let chordData = Data([8, 7, 6, 5])

        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(freeHandData))
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(chordData))
        XCTAssertEqual(chart.pageHandwrittenNotationData, freeHandData)
        XCTAssertEqual(chart.pageHandwrittenChordData, chordData)
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(nil))
        XCTAssertNil(chart.pageHandwrittenChordData)
        XCTAssertEqual(chart.pageHandwrittenNotationData, freeHandData)
    }

    func testSetMeasureHandwrittenRhythmicNotationDrawingStoresAndClearsRawInk() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let drawingData = Data([9, 8, 7, 6])

        XCTAssertTrue(chart.setMeasureHandwrittenRhythmicNotationDrawing(drawingData, for: measureID))
        XCTAssertEqual(chart.measure(id: measureID)?.handwrittenRhythmicNotationData, drawingData)
        XCTAssertTrue(chart.setMeasureHandwrittenRhythmicNotationDrawing(nil, for: measureID))
        XCTAssertNil(chart.measure(id: measureID)?.handwrittenRhythmicNotationData)
    }

    func testSetMeasureRhythmMapStoresAndClearsQuantizedRhythm() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.quarter, .quarter, .quarter, .quarter],
                drawingData: Data([1, 2, 3]),
                for: measureID
            )
        )
        XCTAssertEqual(
            chart.measure(id: measureID)?.rhythmMap?.values,
            [.quarter, .quarter, .quarter, .quarter]
        )

        XCTAssertTrue(chart.clearMeasureRhythmicNotation(for: measureID, clearRhythmMap: true))
        XCTAssertNil(chart.measure(id: measureID)?.rhythmMap)
    }

    func testAppendRecognizedChordAddsCleanChordSymbolAtRequestedFraction() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = try XCTUnwrap(BasicMajorChordCompendium.match("Db")?.symbol)
        let sourceInkData = Data([1, 9, 7, 5])

        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                symbol,
                rawInput: "D flat",
                to: measureID,
                atFraction: 0.55,
                sourceInkData: sourceInkData,
                sourceCandidateSignature: ["Db", "D"]
            )
        )

        let chord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(chord.id, chordID)
        XCTAssertEqual(chord.symbol.displayText, "Db")
        XCTAssertEqual(chord.rawInput, "D flat")
        XCTAssertEqual(chord.sourceInkData, sourceInkData)
        XCTAssertEqual(chord.sourceCandidateSignature, ["Db", "D"])
        XCTAssertEqual(chord.startPosition.displayText, "3")
    }

    func testReplaceChordEventUpdatesSymbolWithoutMovingPlacementOrInkSource() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let sourceInkData = Data([9, 8, 7])
        let initialSymbol = try XCTUnwrap(ChordRecognitionCompendium.match("Bb/A")?.symbol)
        let correctedSymbol = try XCTUnwrap(ChordRecognitionCompendium.match("Db/A")?.symbol)
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                initialSymbol,
                rawInput: "Bb/A",
                to: measureID,
                atFraction: 0.55,
                sourceInkData: sourceInkData,
                sourceCandidateSignature: ["Bb/A", "Db/A"]
            )
        )

        XCTAssertTrue(chart.replaceChordEvent(chordID, with: correctedSymbol, rawInput: "Db/A"))

        let chord = try XCTUnwrap(chart.chordEvent(id: chordID))
        XCTAssertEqual(chord.symbol.displayText, "Db/A")
        XCTAssertEqual(chord.rawInput, "Db/A")
        XCTAssertEqual(chord.sourceInkData, sourceInkData)
        XCTAssertEqual(chord.sourceCandidateSignature, ["Bb/A", "Db/A"])
        XCTAssertEqual(chord.startPosition.displayText, "3")
        XCTAssertEqual(chart.measureContainingChordEvent(id: chordID)?.id, measureID)
    }

    func testChordWritingLoopOnDisposableTestChartCommitsStructuredChords() throws {
        var chart = Chart.blank(title: "Chord Writing Test Chart", measureCount: 8)
        let chordLoopCases = [
            (written: "C", expected: "C"),
            (written: "Bb7", expected: "Bb7"),
            (written: "F#-11", expected: "F#-11"),
            (written: "Db7b9", expected: "Db7(b9)"),
            (written: "G/B", expected: "G/B")
        ]

        for (index, chordCase) in chordLoopCases.enumerated() {
            let measureID = chart.measures[index].id
            let inkData = Data("ink-\(chordCase.written)".utf8)
            let match = try XCTUnwrap(ChordRecognitionCompendium.match(chordCase.written))

            XCTAssertTrue(chart.setPageHandwrittenChordDrawing(inkData))
            let chordID = try XCTUnwrap(
                chart.commitRecognizedChordInk(
                    match.symbol,
                    rawInput: chordCase.written,
                    to: measureID,
                    atFraction: 0.05,
                    sourceInkData: inkData,
                    sourceCandidateSignature: [chordCase.expected]
                ),
                chordCase.written
            )

            let chord = try XCTUnwrap(chart.chordEvent(id: chordID))
            XCTAssertEqual(chord.symbol.displayText, chordCase.expected)
            XCTAssertEqual(chord.rawInput, chordCase.written)
            XCTAssertEqual(chord.sourceInkData, inkData)
            XCTAssertEqual(chord.sourceCandidateSignature, [chordCase.expected])
            XCTAssertEqual(chord.startPosition.displayText, "1")
            XCTAssertNil(chart.pageHandwrittenChordData)
        }
    }

    func testRecognizedChordInkCommitKeepsInkWhenMeasureIsUnavailable() throws {
        var chart = Chart.blank(title: "Chord Writing Test Chart", measureCount: 1)
        let inkData = Data("ink-C".utf8)
        let match = try XCTUnwrap(ChordRecognitionCompendium.match("C"))

        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(inkData))
        XCTAssertNil(
            chart.commitRecognizedChordInk(
                match.symbol,
                rawInput: "C",
                to: UUID(),
                atFraction: 0.05,
                sourceInkData: inkData
            )
        )

        XCTAssertEqual(chart.pageHandwrittenChordData, inkData)
        XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
    }

    func testDeleteChordEventRemovesRenderedChordFromMeasure() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)
        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "C", to: measureID, atFraction: 0.03))
        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)

        XCTAssertTrue(chart.deleteChordEvent(chordID))

        XCTAssertTrue(chart.measure(id: measureID)?.chordEvents.isEmpty == true)
        XCTAssertFalse(chart.deleteChordEvent(chordID))
    }

    func testMoveChordEventSnapsExistingChordToRequestedBeat() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = ChordSymbol(root: .f, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)
        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "F", to: measureID, atFraction: 0.03))
        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)

        XCTAssertTrue(chart.moveChordEvent(chordID, to: measureID, atFraction: 0.68))

        let movedChord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(movedChord.id, chordID)
        XCTAssertEqual(movedChord.startPosition.displayText, "4")
        XCTAssertNil(movedChord.mappedRhythmSlotIndex)
    }

    func testMoveChordEventSnapsExistingChordToRhythmSlot() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
        let symbol = ChordSymbol(root: .g, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil)
        XCTAssertTrue(chart.appendRecognizedChord(symbol, rawInput: "G", to: measureID, atFraction: 0.03))
        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)

        XCTAssertTrue(chart.moveChordEvent(chordID, to: measureID, atFraction: 0.62))

        let movedChord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        XCTAssertEqual(movedChord.startPosition.displayText, "3")
        XCTAssertEqual(movedChord.mappedRhythmSlotIndex, 2)
        XCTAssertEqual(movedChord.duration, .quarter)
    }

    func testReplaceMeasureRhythmValueUpdatesSelectedSlotWhenMeasureStillFits() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.dottedQuarter, .eighth, .half],
                drawingData: Data([1, 2, 3]),
                for: measureID
            )
        )

        let result = chart.replaceMeasureRhythmValue(.eighthRest, at: 1, in: measureID)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(chart.measure(id: measureID)?.rhythmMap?.values, [.dottedQuarter, .eighthRest, .half])
        XCTAssertNil(chart.measure(id: measureID)?.rhythmMap?.drawingData)
    }

    func testReplaceMeasureRhythmValueAllowsSlashWhenDurationStillFits() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.quarter, .quarter, .quarter, .quarter],
                for: measureID
            )
        )

        let result = chart.replaceMeasureRhythmValue(.slash, at: 1, in: measureID)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(chart.measure(id: measureID)?.rhythmMap?.values, [.quarter, .slash, .quarter, .quarter])
    }

    func testReplaceMeasureRhythmValueRejectsChangesThatBreakMeterLength() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.quarter, .quarter, .quarter, .quarter],
                for: measureID
            )
        )

        let result = chart.replaceMeasureRhythmValue(.half, at: 0, in: measureID)

        XCTAssertEqual(result, .invalidMeterFit(.overflow(1)))
        XCTAssertEqual(chart.measure(id: measureID)?.rhythmMap?.values, [.quarter, .quarter, .quarter, .quarter])
    }

    func testSetMeasureManualLayoutWidthStoresClampedOverride() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        let appliedLargeWidth = try XCTUnwrap(chart.setMeasureManualLayoutWidth(680, for: measureID))
        XCTAssertEqual(appliedLargeWidth, Measure.maximumManualLayoutWidth)
        XCTAssertEqual(chart.measure(id: measureID)?.manualLayoutWidth, Double(Measure.maximumManualLayoutWidth))

        let appliedSmallWidth = try XCTUnwrap(chart.setMeasureManualLayoutWidth(44, for: measureID))
        XCTAssertEqual(appliedSmallWidth, Measure.minimumManualLayoutWidth)
        XCTAssertEqual(chart.measure(id: measureID)?.manualLayoutWidth, Double(Measure.minimumManualLayoutWidth))

        _ = chart.setMeasureManualLayoutWidth(nil, for: measureID)
        XCTAssertNil(chart.measure(id: measureID)?.manualLayoutWidth)
    }

    func testCommitOpenMeasureMarksCurrentMeasureCommittedAndAppendsNextOpenMeasure() {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let appendedOpenMeasureID = chart.commitOpenMeasure()

        XCTAssertNotNil(appendedOpenMeasureID)
        XCTAssertEqual(chart.measures.count, 2)
        XCTAssertEqual(chart.measures[0].authoringState, .committed)
        XCTAssertEqual(chart.measures[1].authoringState, .open)
        XCTAssertEqual(chart.measures[1].index, 2)
    }

    func testPositionOpenMeasureAfterCommittedMeasureMovesBlankOpenSlotBehindSelection() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        let trailingOpenMeasureID = try XCTUnwrap(chart.commitOpenMeasure())

        let repositionedOpenMeasureID = try XCTUnwrap(chart.positionOpenMeasure(after: firstMeasureID))

        XCTAssertEqual(repositionedOpenMeasureID, trailingOpenMeasureID)
        XCTAssertEqual(chart.measures.map(\.id), [firstMeasureID, trailingOpenMeasureID, secondMeasureID])
        XCTAssertEqual(chart.measure(id: trailingOpenMeasureID)?.authoringState, .open)
        XCTAssertEqual(chart.measure(id: secondMeasureID)?.authoringState, .committed)
    }

    func testPositionOpenMeasureKeepsNonBlankOpenMeasureInPlace() throws {
        var chart = Chart.draft(title: "New Chart")
        chart.completeInitialSetup(
            title: "Pocket Groove",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        let trailingOpenMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        chart.systems[0].measures[2].chordEvents = [demoChordEvent(root: .c)]

        let resolvedOpenMeasureID = try XCTUnwrap(chart.positionOpenMeasure(after: firstMeasureID))

        XCTAssertEqual(resolvedOpenMeasureID, trailingOpenMeasureID)
        XCTAssertEqual(chart.measures.map(\.id), [firstMeasureID, secondMeasureID, trailingOpenMeasureID])
        XCTAssertEqual(chart.measure(id: trailingOpenMeasureID)?.authoringState, .open)
        XCTAssertEqual(chart.measure(id: secondMeasureID)?.authoringState, .committed)
    }

    func testPositionOpenMeasureReanchorsAnnotationsWhenLaterMeasureShiftsSystems() throws {
        let firstSystemID = UUID()
        let secondSystemID = UUID()
        let measure1 = makeMeasure(index: 1)
        let measure2 = makeMeasure(index: 2)
        let measure3 = makeMeasure(index: 3)
        let annotatedMeasure = makeMeasure(index: 4, barlineAfter: .double)
        let laterMeasure = makeMeasure(index: 5)
        let openMeasure = makeMeasure(index: 6, authoringState: .open)

        var chart = Chart(
            id: UUID(),
            title: "Anchored Chart",
            chartType: .chordChart,
            documentKey: .cMajor,
            documentFont: .classic,
            defaultTranspositionView: .concert,
            defaultMeter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            hasCompletedInitialSetup: true,
            systems: [
                ChartSystem(
                    id: firstSystemID,
                    index: 0,
                    spacingMode: .automatic,
                    lineBreakRule: .automatic,
                    measures: [measure1, measure2, measure3, annotatedMeasure]
                ),
                ChartSystem(
                    id: secondSystemID,
                    index: 1,
                    spacingMode: .automatic,
                    lineBreakRule: .automatic,
                    measures: [laterMeasure, openMeasure]
                )
            ],
            sectionLabels: [
                SectionLabel(
                    id: UUID(),
                    text: "B",
                    type: .sectionName,
                    anchorMeasureID: annotatedMeasure.id,
                    anchorSystemID: firstSystemID,
                    rawInput: "B"
                )
            ],
            cueTexts: [],
            roadmapObjects: [
                RoadmapObject(
                    id: UUID(),
                    type: .dc,
                    startMeasureID: annotatedMeasure.id,
                    endMeasureID: nil,
                    anchorSystemID: firstSystemID,
                    placement: .floatingTop,
                    displayText: nil,
                    count: nil,
                    linkedTargetID: nil,
                    rawInput: "D.C."
                )
            ],
            stylePreset: .cleanStudio,
            createdAt: .now,
            updatedAt: .now
        )

        let repositionedOpenMeasureID = try XCTUnwrap(chart.positionOpenMeasure(after: measure1.id))

        XCTAssertEqual(repositionedOpenMeasureID, openMeasure.id)
        XCTAssertEqual(chart.measures[0].id, measure1.id)
        XCTAssertEqual(chart.measures[1].id, openMeasure.id)
        XCTAssertEqual(chart.measure(id: annotatedMeasure.id)?.index, 5)
        XCTAssertEqual(chart.sectionLabels.first?.anchorSystemID, secondSystemID)
        XCTAssertEqual(chart.roadmapObjects.first?.anchorSystemID, secondSystemID)
    }

    func testApplyMeterChangeToNextTimeSignaturePersistsIntoFutureMeasures() throws {
        var chart = Chart.draft(title: "Time Changes")
        chart.completeInitialSetup(
            title: "Time Changes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())

        let changedMeasureID = try XCTUnwrap(
            chart.applyMeterChange(
                Meter(numerator: 3, denominator: 4),
                after: firstMeasureID,
                scope: .toNextTimeSignature
            )
        )
        let appendedMeasureID = try XCTUnwrap(chart.commitOpenMeasure())

        XCTAssertEqual(changedMeasureID, secondMeasureID)
        XCTAssertNil(chart.measure(id: firstMeasureID)?.meterOverride)
        XCTAssertEqual(chart.measure(id: secondMeasureID)?.meterOverride, Meter(numerator: 3, denominator: 4))
        XCTAssertEqual(chart.measure(id: appendedMeasureID)?.meterOverride, Meter(numerator: 3, denominator: 4))
    }

    func testApplyMeterChangeFixedMeasureCountRestoresSourceMeterAfterSpecifiedSpan() throws {
        var chart = Chart.draft(title: "Time Changes")
        chart.completeInitialSetup(
            title: "Time Changes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.applyMeterChange(
            Meter(numerator: 3, denominator: 4),
            after: firstMeasureID,
            scope: .fixedMeasureCount(1)
        )

        XCTAssertEqual(chart.measures.count, 3)
        XCTAssertEqual(chart.measures[1].meterOverride, Meter(numerator: 3, denominator: 4))
        XCTAssertEqual(chart.measures[2].meterOverride, Meter(numerator: 3, denominator: 4))

        let revertedMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        XCTAssertNil(chart.measure(id: revertedMeasureID)?.meterOverride)
    }

    func testApplyMeterChangeToEndOfPieceOverridesLaterTimeSignatures() throws {
        var chart = Chart.draft(title: "Time Changes")
        chart.completeInitialSetup(
            title: "Time Changes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        _ = chart.commitOpenMeasure()

        _ = chart.applyMeterChange(
            Meter(numerator: 5, denominator: 4),
            after: secondMeasureID,
            scope: .toNextTimeSignature
        )
        _ = chart.applyMeterChange(
            Meter(numerator: 3, denominator: 4),
            after: firstMeasureID,
            scope: .toEndOfPiece
        )

        XCTAssertEqual(chart.measures[1].meterOverride, Meter(numerator: 3, denominator: 4))
        XCTAssertEqual(chart.measures[2].meterOverride, Meter(numerator: 3, denominator: 4))
        XCTAssertTrue(chart.timeSignatureChanges.allSatisfy { $0.afterMeasureID == firstMeasureID })
    }

    private func makeMeasure(
        index: Int,
        barlineAfter: BarlineType = .single,
        authoringState: MeasureAuthoringState = .committed
    ) -> Measure {
        Measure(
            id: UUID(),
            index: index,
            meterOverride: nil,
            beatGridPreset: .simple,
            barlineAfter: barlineAfter,
            chordEvents: [],
            cueTextIDs: [],
            roadmapObjectIDs: [],
            authoringState: authoringState
        )
    }

    private func demoChordEvent(root: ChordRoot) -> ChordEvent {
        ChordEvent(
            id: UUID(),
            symbol: ChordSymbol(root: root, accidental: .natural, quality: "7", extensions: [], alterations: [], slashBass: nil),
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
            duration: .quarter,
            rhythmPlacement: .belowChord,
            tieOut: false,
            hitStyle: .none,
            rawInput: nil
        )
    }
}

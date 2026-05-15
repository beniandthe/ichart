import CoreGraphics
import XCTest
@testable import SmartChart

final class LeadSheetPageLayoutTests: XCTestCase {
    func testFiveLineLayoutCreatesCenteredPaperAndHeader() {
        let chart = ChartSamples.straightAheadSwing

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1180, height: 1500)
        )

        XCTAssertGreaterThan(layout.paperFrame.width, 600)
        XCTAssertLessThan(layout.paperFrame.minX, layout.pageBounds.midX)
        XCTAssertGreaterThan(layout.paperFrame.maxX, layout.pageBounds.midX)
        XCTAssertTrue(layout.paperFrame.contains(layout.header.titleFrame))
        XCTAssertTrue(layout.header.titleFrame.midX > layout.paperFrame.minX)
    }

    func testFiveLineLayoutPlacesChordTextAboveStaffWithoutImplicitNotes() throws {
        let chart = ChartSamples.straightAheadSwing

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1180, height: 1500)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let firstChord = try XCTUnwrap(firstMeasure.chordLayouts.first)

        XCTAssertLessThan(firstChord.frame.maxY, firstMeasure.staffFrame.minY)
        XCTAssertTrue(firstMeasure.noteLayouts.isEmpty)
    }

    func testChordLayoutsSnapToBeatGridWhenMeasureHasNoRhythmMap() throws {
        var chart = makeBlankLeadSheet()
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.appendRecognizedChord(
                ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil),
                rawInput: "C",
                to: measureID,
                atFraction: 0.03
            )
        )
        XCTAssertTrue(
            chart.appendRecognizedChord(
                ChordSymbol(root: .f, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil),
                rawInput: "F",
                to: measureID,
                atFraction: 0.62
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = firstMeasure.chordLayouts

        XCTAssertEqual(chordLayouts.map(\.text), ["C", "F"])
        let usableWidth = firstMeasure.staffFrame.width - 16
        let beatStep = usableWidth / 4
        XCTAssertEqual(chordLayouts[0].frame.midX, firstMeasure.staffFrame.minX + 8 + beatStep * 0.5, accuracy: 0.001)
        XCTAssertEqual(chordLayouts[1].frame.midX, firstMeasure.staffFrame.minX + 8 + beatStep * 2.5, accuracy: 0.001)
        XCTAssertTrue(firstMeasure.noteLayouts.isEmpty)
    }

    func testChordLayoutsLeaveRoomForExtendedChordSymbolsAroundBeatAnchor() throws {
        var chart = makeBlankLeadSheet()
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let symbol = try ChordSymbolParser.parse("Db7(#11)/F#")
        XCTAssertTrue(
            chart.appendRecognizedChord(
                symbol,
                rawInput: "Db7(#11)/F#",
                to: measureID,
                atFraction: 0.03
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayout = try XCTUnwrap(firstMeasure.chordLayouts.first)
        let usableWidth = firstMeasure.staffFrame.width - 16
        let beatStep = usableWidth / 4
        let beatAttackX = firstMeasure.staffFrame.minX + 8 + beatStep * 0.5

        XCTAssertEqual(chordLayout.text, "Db7(#11)/F#")
        XCTAssertGreaterThanOrEqual(chordLayout.frame.width, 100)
        XCTAssertLessThanOrEqual(chordLayout.frame.minX, beatAttackX)
        XCTAssertGreaterThanOrEqual(chordLayout.frame.maxX, beatAttackX)
        XCTAssertGreaterThanOrEqual(chordLayout.frame.minX, firstMeasure.chordBandFrame.minX)
        XCTAssertLessThanOrEqual(chordLayout.frame.maxX, firstMeasure.chordBandFrame.maxX)
    }

    func testChordLayoutsAlignWithRhythmAttackCentersWhenMeasureHasRhythmMap() throws {
        var chart = makeBlankLeadSheet()
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.quarter, .quarter, .quarter, .quarter],
            for: measureID
        )
        XCTAssertTrue(
            chart.appendRecognizedChord(
                ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil),
                rawInput: "C",
                to: measureID,
                atFraction: 0.03
            )
        )
        XCTAssertTrue(
            chart.appendRecognizedChord(
                ChordSymbol(root: .g, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil),
                rawInput: "G",
                to: measureID,
                atFraction: 0.62
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)

        XCTAssertEqual(firstMeasure.chordLayouts.map(\.text), ["C", "G"])
        XCTAssertEqual(firstMeasure.noteLayouts.count, 4)
        XCTAssertEqual(firstMeasure.chordLayouts[0].frame.midX, firstMeasure.noteLayouts[0].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[1].frame.midX, firstMeasure.noteLayouts[2].noteheadFrame.midX, accuracy: 0.001)
    }

    func testLeadSheetLayoutUsesExpandedChordWritingBandWithoutOverlappingPriorSystem() throws {
        var chart = makeBlankLeadSheet()
        _ = chart.commitOpenMeasure()
        _ = chart.commitOpenMeasure()
        _ = chart.commitOpenMeasure()

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondSystem = try XCTUnwrap(layout.systems.last)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let secondMeasure = try XCTUnwrap(secondSystem.measures.first)

        XCTAssertGreaterThanOrEqual(firstMeasure.chordBandFrame.height, 44)
        XCTAssertLessThan(firstMeasure.chordBandFrame.maxY, firstMeasure.staffFrame.minY)
        XCTAssertGreaterThan(secondMeasure.chordBandFrame.minY, firstMeasure.staffFrame.maxY)
    }

    func testOpenFiveLineMeasureUsesSingleOpenMeasureWidthAndNoCommittedBarline() throws {
        var chart = Chart.draft(title: "Blank Lead Sheet")
        chart.completeInitialSetup(
            title: "Blank Lead Sheet",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)

        XCTAssertTrue(firstMeasure.isOpen)
        XCTAssertEqual(firstSystem.measures.count, 1)
        XCTAssertGreaterThan(firstMeasure.frame.width, 220)
        XCTAssertLessThan(firstMeasure.frame.width, 280)
        XCTAssertLessThan(firstSystem.frame.width, layout.paperFrame.width * 0.55)
        XCTAssertLessThanOrEqual(abs(firstMeasure.trailingBarlineFrame.midX - firstSystem.frame.maxX), 12)
        XCTAssertTrue(firstMeasure.noteLayouts.isEmpty)
    }

    func testEngravingPresetChangesDefaultMeasureSpacing() throws {
        var compactChart = makeBlankLeadSheet()
        compactChart.setEngravingPreset(.compact)
        var wideChart = makeBlankLeadSheet()
        wideChart.setEngravingPreset(.wide)

        let compactLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: compactChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let wideLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: wideChart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let compactMeasure = try XCTUnwrap(compactLayout.systems.first?.measures.first)
        let wideMeasure = try XCTUnwrap(wideLayout.systems.first?.measures.first)

        XCTAssertLessThan(compactMeasure.frame.width, wideMeasure.frame.width)
    }

    func testLeadSheetLayoutKeepsGrowingMeasuresOnFirstSystemBeforeWrapping() throws {
        var chart = makeBlankLeadSheet()
        _ = chart.commitOpenMeasure()
        _ = chart.commitOpenMeasure()

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertEqual(layout.systems.count, 1)

        let firstSystem = try XCTUnwrap(layout.systems.first)
        XCTAssertEqual(firstSystem.measures.count, 3)
        XCTAssertGreaterThan(firstSystem.frame.width, 520)
        XCTAssertLessThan(firstSystem.frame.width, layout.paperFrame.width)
        XCTAssertTrue(firstSystem.measures[2].isOpen)
        XCTAssertLessThan(firstSystem.measures[0].frame.width, firstSystem.measures[2].frame.width)
    }

    func testLeadSheetLayoutWrapsOpenMeasureOntoNextSystemWhenLineFills() throws {
        var chart = makeBlankLeadSheet()
        _ = chart.commitOpenMeasure()
        _ = chart.commitOpenMeasure()
        _ = chart.commitOpenMeasure()

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertEqual(layout.systems.count, 2)

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondSystem = try XCTUnwrap(layout.systems.last)

        XCTAssertEqual(firstSystem.measures.count, 3)
        XCTAssertEqual(secondSystem.measures.count, 1)
        XCTAssertTrue(secondSystem.measures[0].isOpen)
        XCTAssertGreaterThan(secondSystem.measures[0].frame.width, 220)
        XCTAssertLessThan(secondSystem.frame.width, layout.paperFrame.width * 0.5)
    }

    func testLeadSheetLayoutHonorsManualMeasureWidthOverride() throws {
        var chart = makeBlankLeadSheet()
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureManualLayoutWidth(320, for: measureID)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        XCTAssertGreaterThan(firstMeasure.frame.width, 300)
        XCTAssertLessThan(firstSystem.frame.width, layout.paperFrame.width * 0.7)
    }

    func testLeadSheetLayoutWrapsEarlierWhenCommittedMeasureIsStretched() throws {
        var chart = makeBlankLeadSheet()
        let firstOpenID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.commitOpenMeasure()
        _ = chart.commitOpenMeasure()
        _ = chart.commitOpenMeasure()
        _ = chart.setMeasureManualLayoutWidth(400, for: firstOpenID)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertEqual(layout.systems.count, 2)
        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondSystem = try XCTUnwrap(layout.systems.last)
        XCTAssertEqual(firstSystem.measures.count, 2)
        XCTAssertEqual(secondSystem.measures.count, 2)
    }

    func testLeadSheetLayoutShowsTrailingMeterChangeAtEndOfSelectedMeasure() throws {
        var chart = makeBlankLeadSheet()
        _ = chart.commitOpenMeasure()
        let thirdMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        _ = chart.applyMeterChange(
            Meter(numerator: 3, denominator: 4),
            after: thirdMeasureID,
            scope: .toNextTimeSignature
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let trailingChangeMeasure = try XCTUnwrap(firstSystem.measures.last)

        XCTAssertEqual(trailingChangeMeasure.sourceMeasureID, thirdMeasureID)
        XCTAssertEqual(trailingChangeMeasure.trailingMeterChange, Meter(numerator: 3, denominator: 4))
        XCTAssertNotNil(trailingChangeMeasure.trailingMeterChangeFrame)
    }

    func testLeadSheetLayoutRendersQuantizedRhythmMapAsSlashNotation() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.quarter, .quarter, .eighth, .eighth, .quarterRest],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)

        XCTAssertEqual(firstMeasure.noteLayouts.count, 5)
        XCTAssertEqual(firstMeasure.noteLayouts[0].symbolStyle, .slash)
        XCTAssertEqual(firstMeasure.noteLayouts[2].symbolStyle, .slash)
        XCTAssertNotNil(firstMeasure.noteLayouts[2].beamEndPoint)
        XCTAssertEqual(firstMeasure.noteLayouts[2].flagStyle, .none)
        XCTAssertEqual(firstMeasure.noteLayouts[3].flagStyle, .none)
        XCTAssertEqual(firstMeasure.noteLayouts[4].symbolStyle, .quarterRest)
    }

    func testLeadSheetLayoutRendersSlashPlaceholdersAsStemlessBeatSlots() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.slash, .eighth, .eighth, .half],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let slashPlaceholder = try XCTUnwrap(firstMeasure.noteLayouts.first)

        XCTAssertEqual(slashPlaceholder.symbolStyle, .slash)
        XCTAssertEqual(slashPlaceholder.noteheadSymbol, .slashNotehead)
        XCTAssertNil(slashPlaceholder.stemStart)
        XCTAssertNil(slashPlaceholder.stemEnd)
        XCTAssertEqual(slashPlaceholder.flagStyle, .none)

        let usableWidth = firstMeasure.staffFrame.width - 16
        let beatStep = usableWidth / 4
        XCTAssertEqual(slashPlaceholder.noteheadFrame.midX, firstMeasure.staffFrame.minX + 8 + beatStep * 0.5, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.noteLayouts[1].noteheadFrame.midX, firstMeasure.staffFrame.minX + 8 + beatStep * 1.25, accuracy: 0.001)
    }

    func testLeadSheetLayoutKeepsRestGlyphsUprightInsideStaffBody() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.eighthRest, .eighthRest, .quarterRest, .halfRest],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let restLayouts = firstMeasure.noteLayouts

        XCTAssertEqual(restLayouts.map(\.symbolStyle), [.eighthRest, .eighthRest, .quarterRest, .halfRest])
        let topLineY = try XCTUnwrap(firstSystem.staffLineYPositions.first)
        let bottomLineY = try XCTUnwrap(firstSystem.staffLineYPositions.last)
        let lineSpacing = (bottomLineY - topLineY) / 4
        let staffMidY = (topLineY + bottomLineY) / 2
        let eighthRest = restLayouts[0]
        let quarterRest = restLayouts[2]

        XCTAssertGreaterThan(eighthRest.noteheadFrame.minY, topLineY)
        XCTAssertLessThan(eighthRest.noteheadFrame.maxY, bottomLineY + 2)
        XCTAssertNil(eighthRest.stemStart)
        XCTAssertNil(eighthRest.stemEnd)
        XCTAssertGreaterThan(quarterRest.noteheadFrame.minY, topLineY + lineSpacing * 0.5)
        XCTAssertLessThan(quarterRest.noteheadFrame.maxY, bottomLineY + 2)
        XCTAssertEqual(quarterRest.noteheadFrame.midY, staffMidY, accuracy: lineSpacing * 0.75)
        XCTAssertNil(quarterRest.stemStart)
        XCTAssertNil(quarterRest.stemEnd)
    }

    func testLeadSheetLayoutUsesDownwardStemsForRhythmicSlashNotation() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.quarter, .eighth, .eighth, .half],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let stemmedSlashNotes = firstMeasure.noteLayouts.filter {
            $0.symbolStyle == .slash && $0.stemStart != nil
        }

        XCTAssertEqual(stemmedSlashNotes.count, 4)
        for note in stemmedSlashNotes {
            let stemStart = try XCTUnwrap(note.stemStart)
            let stemEnd = try XCTUnwrap(note.stemEnd)
            XCTAssertFalse(note.stemGoesUp)
            XCTAssertLessThan(stemStart.x, note.noteheadFrame.midX)
            XCTAssertGreaterThan(stemStart.y, note.noteheadFrame.midY)
            XCTAssertGreaterThan(stemEnd.y, stemStart.y)
        }
    }

    func testLeadSheetLayoutCentersQuarterRhythmsInFourFourBeatLanes() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.quarter, .quarter, .quarter, .quarter],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let centers = firstMeasure.noteLayouts.map(\.noteheadFrame.midX)

        XCTAssertEqual(centers.count, 4)
        let usableWidth = firstMeasure.staffFrame.width - 16
        let expectedStep = usableWidth / 4
        XCTAssertEqual(centers[0], firstMeasure.staffFrame.minX + 8 + expectedStep * 0.5, accuracy: 0.001)
        XCTAssertEqual(centers[1] - centers[0], expectedStep, accuracy: 0.001)
        XCTAssertEqual(centers[2] - centers[1], expectedStep, accuracy: 0.001)
        XCTAssertEqual(centers[3] - centers[2], expectedStep, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.staffFrame.maxX - centers[3], centers[0] - firstMeasure.staffFrame.minX, accuracy: 0.001)
    }

    func testLeadSheetLayoutCentersQuarterRhythmsInThreeFourBeatLanes() throws {
        var chart = Chart.draft(title: "Three Four")
        chart.completeInitialSetup(
            title: "Three Four",
            key: .cMajor,
            meter: Meter(numerator: 3, denominator: 4),
            staffStyle: .fiveLine
        )
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.quarter, .quarter, .quarter],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let centers = firstMeasure.noteLayouts.map(\.noteheadFrame.midX)

        XCTAssertEqual(centers.count, 3)
        let usableWidth = firstMeasure.staffFrame.width - 16
        let expectedStep = usableWidth / 3
        XCTAssertEqual(centers[0], firstMeasure.staffFrame.minX + 8 + expectedStep * 0.5, accuracy: 0.001)
        XCTAssertEqual(centers[1] - centers[0], expectedStep, accuracy: 0.001)
        XCTAssertEqual(centers[2] - centers[1], expectedStep, accuracy: 0.001)
    }

    func testLeadSheetLayoutPlacesLongRhythmsAtTheirStartingBeatLanes() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.half, .half],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let centers = firstMeasure.noteLayouts.map(\.noteheadFrame.midX)

        XCTAssertEqual(centers.count, 2)
        let usableWidth = firstMeasure.staffFrame.width - 16
        let beatStep = usableWidth / 4
        XCTAssertEqual(centers[0], firstMeasure.staffFrame.minX + 8 + beatStep * 0.5, accuracy: 0.001)
        XCTAssertEqual(centers[1], firstMeasure.staffFrame.minX + 8 + beatStep * 2.5, accuracy: 0.001)
    }

    func testLeadSheetLayoutDoesNotBeamEighthNotesAcrossBeatBoundary() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.dottedQuarter, .eighth, .eighth, .dottedQuarter],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)

        XCTAssertNil(firstMeasure.noteLayouts[1].beamEndPoint)
        XCTAssertEqual(firstMeasure.noteLayouts[1].flagStyle, .single)
        XCTAssertNil(firstMeasure.noteLayouts[2].beamEndPoint)
        XCTAssertEqual(firstMeasure.noteLayouts[2].flagStyle, .single)
    }

    func testLeadSheetLayoutUsesSmuflNoteheadBoundsAndStemAnchors() throws {
        var chart = makeBlankLeadSheet()
        chart.setNotationFont(.petaluma)
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.eighth, .eighth, .quarter, .half],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let firstNote = try XCTUnwrap(layout.systems.first?.measures.first?.noteLayouts.first)
        let symbol = try XCTUnwrap(firstNote.noteheadSymbol)
        let metrics = try XCTUnwrap(SmuflFontMetadataStore.metrics(for: symbol, in: chart.notationFont))
        let boundingBox = try XCTUnwrap(metrics.boundingBox)
        let stemAnchor = try XCTUnwrap(metrics.anchor(named: "stemDownNW"))
        let stemStart = try XCTUnwrap(firstNote.stemStart)
        let smuflScale = firstNote.staffSpace * CGFloat(chart.engravingPreset.glyphScale)
        let boxCenter = boundingBox.center

        XCTAssertEqual(symbol, .slashNotehead)
        XCTAssertEqual(firstNote.noteheadFrame.width, CGFloat(boundingBox.width) * smuflScale, accuracy: 0.001)
        XCTAssertEqual(firstNote.noteheadFrame.height, CGFloat(boundingBox.height) * smuflScale, accuracy: 0.001)
        XCTAssertEqual(
            stemStart.x,
            firstNote.noteheadFrame.midX + CGFloat(stemAnchor.x - boxCenter.x) * smuflScale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            stemStart.y,
            firstNote.noteheadFrame.midY - CGFloat(stemAnchor.y - boxCenter.y) * smuflScale,
            accuracy: 0.001
        )
    }

    func testLeadSheetLayoutTurnsEditedBeamedEighthIntoCleanStandaloneEighth() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.eighth, .eighth, .quarter, .half],
            for: firstMeasureID
        )

        let result = chart.replaceMeasureRhythmValue(.eighthRest, at: 0, in: firstMeasureID)
        XCTAssertEqual(result, .applied)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let noteLayouts = try XCTUnwrap(layout.systems.first?.measures.first?.noteLayouts)

        XCTAssertEqual(noteLayouts.map(\.symbolStyle), [.eighthRest, .slash, .slash, .slash])
        XCTAssertNil(noteLayouts[0].stemStart)
        XCTAssertNil(noteLayouts[0].stemEnd)
        XCTAssertNil(noteLayouts[0].beamEndPoint)
        XCTAssertNil(noteLayouts[1].beamEndPoint)
        XCTAssertEqual(noteLayouts[1].flagStyle, .single)
    }

    func testLeadSheetLayoutResolvesLassoSelectionToSingleNote() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.quarter, .quarter, .quarter, .quarter],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let firstNote = try XCTUnwrap(layout.systems.first?.measures.first?.noteLayouts.first)
        let lassoFrame = firstNote.noteheadFrame.insetBy(dx: -18, dy: -18)
        let selection = try XCTUnwrap(layout.noteSelection(in: lassoFrame))

        XCTAssertEqual(selection.measureID, firstMeasureID)
        XCTAssertEqual(selection.noteIndex, 0)
    }

    func testLeadSheetLayoutSelectsIndividualNoteInsideBeamedEighthPair() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.eighth, .eighth, .quarter, .half],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let noteLayouts = try XCTUnwrap(layout.systems.first?.measures.first?.noteLayouts)
        let firstBeamedNote = noteLayouts[0]
        let secondBeamedNote = noteLayouts[1]

        XCTAssertNotNil(firstBeamedNote.beamEndPoint)
        XCTAssertNil(secondBeamedNote.beamEndPoint)
        XCTAssertLessThan(firstBeamedNote.selectionFrame.maxX, secondBeamedNote.noteheadFrame.minX)

        let lassoFrame = secondBeamedNote.noteheadFrame.insetBy(dx: -18, dy: -18)
        let selection = try XCTUnwrap(layout.noteSelection(in: lassoFrame))

        XCTAssertEqual(selection.measureID, firstMeasureID)
        XCTAssertEqual(selection.noteIndex, 1)
    }

    func testLeadSheetLayoutDoesNotSelectNoteFromGreyAreaLasso() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.quarter, .quarter, .quarter, .quarter],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let outsidePaperLasso = CGRect(x: 10, y: 10, width: 40, height: 40)

        XCTAssertNil(layout.noteSelection(in: outsidePaperLasso))
    }

    private func makeBlankLeadSheet() -> Chart {
        var chart = Chart.draft(title: "Blank Lead Sheet")
        chart.completeInitialSetup(
            title: "Blank Lead Sheet",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine
        )
        return chart
    }
}

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
        XCTAssertEqual(layout.header.titleFrame.midX, layout.paperFrame.midX, accuracy: 0.001)
    }

    func testHeaderUsesCenteredTitleAndSingleMetadataRow() throws {
        let chart = ChartSamples.straightAheadSwing

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1180, height: 1500)
        )

        let styleNoteFrame = try XCTUnwrap(layout.header.styleNoteFrame)
        let keyFrame = try XCTUnwrap(layout.header.keyFrame)
        let meterFrame = try XCTUnwrap(layout.header.meterFrame)
        let composerFrame = try XCTUnwrap(layout.header.composerFrame)
        let centerMetadataFrame = keyFrame.union(meterFrame)

        XCTAssertEqual(layout.header.titleFrame.midX, layout.paperFrame.midX, accuracy: 0.001)
        XCTAssertGreaterThan(styleNoteFrame.minY, layout.header.titleFrame.maxY)
        XCTAssertEqual(styleNoteFrame.midY, composerFrame.midY, accuracy: 0.001)
        XCTAssertEqual(centerMetadataFrame.midY, composerFrame.midY, accuracy: 0.001)
        XCTAssertEqual(centerMetadataFrame.midX, layout.header.frame.midX, accuracy: 0.001)
        XCTAssertLessThan(styleNoteFrame.maxX, centerMetadataFrame.minX)
        XCTAssertLessThan(centerMetadataFrame.maxX, composerFrame.minX)
    }

    func testSimpleChordSheetHeaderUsesCompactChartTitleTreatment() throws {
        var chart = Chart.blank(
            title: "Almost Like Being In Love",
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        chart.styleNote = "(Medium Swing)"
        chart.composerCredit = "Frederick Loewe"

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let styleNoteFrame = try XCTUnwrap(layout.header.styleNoteFrame)
        let composerFrame = try XCTUnwrap(layout.header.composerFrame)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertNil(layout.header.meterFrame)
        XCTAssertEqual(layout.header.titleFrame.midX, layout.paperFrame.midX, accuracy: 0.001)
        XCTAssertLessThan(layout.header.titleFrame.height, 44)
        XCTAssertEqual(styleNoteFrame.midY, composerFrame.midY, accuracy: 0.001)
        XCTAssertLessThan(styleNoteFrame.maxX, layout.header.titleFrame.minX + layout.header.titleFrame.width * 0.34)
        XCTAssertGreaterThan(composerFrame.minX, layout.header.titleFrame.maxX - layout.header.titleFrame.width * 0.34)
    }

    func testNarrowEditorWidthKeepsPaperInsideVisiblePageBounds() {
        let chart = Chart.blank(title: "Chord Writing Test Chart", key: .cMajor, measureCount: 8)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 772, height: 1200)
        )

        XCTAssertEqual(layout.pageBounds.width, 772)
        XCTAssertGreaterThanOrEqual(layout.paperFrame.minX, layout.pageBounds.minX)
        XCTAssertLessThanOrEqual(layout.paperFrame.maxX, layout.pageBounds.maxX)
        XCTAssertTrue(layout.paperFrame.contains(layout.header.titleFrame))
        XCTAssertEqual(layout.header.titleFrame.width, layout.paperFrame.width)
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

    func testSimpleChordSheetLayoutUsesBlankMeasureSpaceWithInitialMeterGutter() throws {
        var chart = Chart.blank(title: "Simple Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        XCTAssertTrue(
            chart.appendRecognizedChord(
                ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil),
                rawInput: "C",
                to: measureID,
                atFraction: 0.48
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let firstChord = try XCTUnwrap(firstMeasure.chordLayouts.first)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertNil(layout.header.meterFrame)
        XCTAssertTrue(firstSystem.staffLineYPositions.isEmpty)
        XCTAssertNil(firstSystem.clefFrame)
        let timeSignatureFrame = try XCTUnwrap(firstSystem.timeSignatureFrame)
        XCTAssertGreaterThan(firstMeasure.frame.minX, firstSystem.frame.minX)
        XCTAssertLessThan(timeSignatureFrame.maxX, firstMeasure.frame.minX)
        XCTAssertEqual(firstMeasure.frame.minX - firstSystem.frame.minX, 42, accuracy: 0.001)
        XCTAssertNil(firstMeasure.freehandAboveFrame)
        XCTAssertNil(firstMeasure.freehandBelowFrame)
        XCTAssertTrue(firstMeasure.staffFrame.contains(firstMeasure.chordBandFrame))
        XCTAssertGreaterThanOrEqual(firstMeasure.staffFrame.height, 56)
        XCTAssertGreaterThan(firstMeasure.staffFrame.height, firstMeasure.chordBandFrame.height)
        XCTAssertGreaterThanOrEqual(firstChord.frame.minY, firstMeasure.staffFrame.minY)
        XCTAssertLessThanOrEqual(firstChord.frame.maxY, firstMeasure.staffFrame.maxY)
        XCTAssertGreaterThanOrEqual(firstChord.fitFrame.width, 46)
        XCTAssertTrue(firstMeasure.noteLayouts.isEmpty)
    }

    func testSimpleChordSheetSingleChordUsesMeasureFitFrame() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("C", to: measureID, in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayout = try XCTUnwrap(firstMeasure.chordLayouts.first)

        XCTAssertEqual(chordLayout.frame.minX, firstMeasure.chordBandFrame.minX + 6, accuracy: 0.001)
        XCTAssertEqual(chordLayout.fitFrame.minX, firstMeasure.chordBandFrame.minX + 6, accuracy: 0.001)
        XCTAssertGreaterThan(chordLayout.fitFrame.width, firstMeasure.chordBandFrame.width * 0.9)
        XCTAssertLessThan(chordLayout.frame.width, chordLayout.fitFrame.width * 0.55)
        XCTAssertEqual(chordLayout.frame.height, chordLayout.fitFrame.height, accuracy: 0.001)
        XCTAssertLessThanOrEqual(chordLayout.frame.maxX, firstMeasure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetSingleLongChordLeavesBeatThreeWritingSpace() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Bb△7", to: measureID, in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayout = try XCTUnwrap(firstMeasure.chordLayouts.first)
        let trailingWritingWidth = firstMeasure.chordBandFrame.maxX - chordLayout.frame.maxX

        XCTAssertEqual(chordLayout.fitFrame.minX, firstMeasure.chordBandFrame.minX + 6, accuracy: 0.001)
        XCTAssertGreaterThan(chordLayout.fitFrame.width, firstMeasure.chordBandFrame.width * 0.9)
        XCTAssertLessThanOrEqual(chordLayout.frame.maxX, firstMeasure.chordBandFrame.midX + 20)
        XCTAssertGreaterThan(trailingWritingWidth, firstMeasure.chordBandFrame.width * 0.38)
        XCTAssertGreaterThan(chordLayout.frame.width, CGFloat(30))
    }

    func testSimpleChordSheetMultipleChordsFitMeasureSegments() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("C", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("D7", to: measureID, in: &chart, atFraction: 0.62)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = firstMeasure.chordLayouts
        let chordEvents = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents)

        XCTAssertEqual(chordLayouts.map(\.text), ["C", "D7"])
        XCTAssertEqual(chordEvents.map(\.startPosition.displayText), ["1", "3"])
        XCTAssertLessThanOrEqual(chordLayouts[0].fitFrame.maxX, firstMeasure.chordBandFrame.midX)
        XCTAssertGreaterThanOrEqual(chordLayouts[1].fitFrame.minX, firstMeasure.chordBandFrame.midX)
        XCTAssertEqual(chordLayouts[0].fitFrame.width, chordLayouts[1].fitFrame.width, accuracy: 0.001)
        XCTAssertLessThan(chordLayouts[0].frame.width, chordLayouts[0].fitFrame.width)
        XCTAssertLessThan(chordLayouts[1].frame.width, chordLayouts[1].fitFrame.width)
    }

    func testSimpleChordSheetTwoChordMeasureDoesNotCompressWhenChordMoves() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Bb△7", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("C-7", to: measureID, in: &chart, atFraction: 0.86)

        let initialLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let initialMeasure = try XCTUnwrap(initialLayout.systems.first?.measures.first)
        let initialChordLayouts = initialMeasure.chordLayouts
        let secondChordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.last?.id)

        XCTAssertEqual(initialChordLayouts.map(\.text), ["Bb△7", "C-7"])
        XCTAssertTrue(initialChordLayouts.allSatisfy { $0.horizontalCompressionScale == 1 })

        XCTAssertTrue(chart.moveChordEvent(secondChordID, to: measureID, atFraction: 0.38))

        let movedLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let movedMeasure = try XCTUnwrap(movedLayout.systems.first?.measures.first)
        let movedChordLayouts = movedMeasure.chordLayouts

        XCTAssertEqual(movedChordLayouts.map(\.text), ["Bb△7", "C-7"])
        XCTAssertTrue(movedChordLayouts.allSatisfy { $0.horizontalCompressionScale == 1 })
        XCTAssertEqual(movedChordLayouts[0].frame.width, initialChordLayouts[0].frame.width, accuracy: 0.001)
        XCTAssertEqual(movedChordLayouts[1].frame.width, initialChordLayouts[1].frame.width, accuracy: 0.001)
    }

    func testSimpleChordSheetChordFramesUseUniversalTypographyAcrossChordFonts() throws {
        var referenceChart = Chart.blank(title: "Simple Chord Fit", measureCount: 4, layoutStyle: .simpleChordSheet)
        let referenceMeasureID = try XCTUnwrap(referenceChart.measures.first?.id)
        try appendChord("Bb△7", to: referenceMeasureID, in: &referenceChart, atFraction: 0.05)
        try appendChord("C-7", to: referenceMeasureID, in: &referenceChart, atFraction: 0.62)

        let referenceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: referenceChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let referenceMeasure = try XCTUnwrap(referenceLayout.systems.first?.measures.first)
        let referenceFrames = referenceMeasure.chordLayouts.map(\.frame)

        for chordFont in [ChartFontFamilyPreset.finaleJazz, .museJazz, .finaleBroadway, .bravura] {
            var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 4, layoutStyle: .simpleChordSheet)
            chart.setChordFontOverride(chordFont)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            try appendChord("Bb△7", to: measureID, in: &chart, atFraction: 0.05)
            try appendChord("C-7", to: measureID, in: &chart, atFraction: 0.62)

            let layout = LeadSheetPageLayoutEngine.pageLayout(
                for: chart,
                pageSize: CGSize(width: 900, height: 1400)
            )
            let measure = try XCTUnwrap(layout.systems.first?.measures.first)
            let frames = measure.chordLayouts.map(\.frame)

            XCTAssertEqual(frames.count, referenceFrames.count)
            for (frame, referenceFrame) in zip(frames, referenceFrames) {
                XCTAssertEqual(frame.minX, referenceFrame.minX, accuracy: 0.001)
                XCTAssertEqual(frame.width, referenceFrame.width, accuracy: 0.001)
                XCTAssertEqual(frame.height, referenceFrame.height, accuracy: 0.001)
            }
        }
    }

    func testSimpleChordSheetThreeOrMoreChordsDivideFullMeasureEvenly() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Bb△7", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("C-7", to: measureID, in: &chart, atFraction: 0.62)
        try appendChord("D7", to: measureID, in: &chart, atFraction: 0.86)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = firstMeasure.chordLayouts
        let chordEvents = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents)

        XCTAssertEqual(chordLayouts.map(\.text), ["Bb△7", "C-7", "D7"])
        XCTAssertEqual(chordEvents.map(\.startPosition.displayText), ["1", "3", "4"])
        XCTAssertLessThan(chordLayouts[0].horizontalCompressionScale, 1)
        XCTAssertGreaterThan(chordLayouts[0].horizontalCompressionScale, 0.45)

        for (index, chordLayout) in chordLayouts.enumerated() {
            XCTAssertEqual(
                chordLayout.horizontalCompressionScale,
                chordLayouts[0].horizontalCompressionScale,
                accuracy: 0.001
            )
            XCTAssertEqual(chordLayout.fitFrame, chordLayout.frame)
            if index > 0 {
                XCTAssertGreaterThan(chordLayout.frame.minX, chordLayouts[index - 1].frame.maxX)
            }
        }

        let gaps = simpleChordMeasureGaps(for: chordLayouts, in: firstMeasure.chordBandFrame)
        XCTAssertTrue(gaps.allSatisfy { $0 > 0 })
        for gap in gaps.dropFirst() {
            XCTAssertEqual(gap, gaps[0], accuracy: 0.001)
        }

        let sharedScale = chordLayouts[0].horizontalCompressionScale
        let widthsByText = Dictionary(uniqueKeysWithValues: chordLayouts.map { ($0.text, $0.frame.width) })
        let lastChordID = try XCTUnwrap(chordEvents.last?.id)
        XCTAssertTrue(chart.moveChordEvent(lastChordID, to: measureID, atFraction: 0.38))

        let movedLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let movedMeasure = try XCTUnwrap(movedLayout.systems.first?.measures.first)
        let movedChordLayouts = movedMeasure.chordLayouts

        XCTAssertEqual(movedChordLayouts.count, 3)
        for chordLayout in movedChordLayouts {
            XCTAssertEqual(chordLayout.horizontalCompressionScale, sharedScale, accuracy: 0.001)
            XCTAssertEqual(chordLayout.fitFrame, chordLayout.frame)
            XCTAssertEqual(chordLayout.frame.width, try XCTUnwrap(widthsByText[chordLayout.text]), accuracy: 0.001)
        }
        let movedGaps = simpleChordMeasureGaps(for: movedChordLayouts, in: movedMeasure.chordBandFrame)
        for gap in movedGaps.dropFirst() {
            XCTAssertEqual(gap, movedGaps[0], accuracy: 0.001)
        }
    }

    func testSimpleChordSheetLaterBeatAppendRendersAfterExistingChord() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("C-7", to: measureID, in: &chart, atFraction: 0.05)
        let firstChordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
        XCTAssertTrue(chart.moveChordEvent(firstChordID, to: measureID, atFraction: 0.62))
        try appendChord("D-7", to: measureID, in: &chart, atFraction: 0.86)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = firstMeasure.chordLayouts
        let chordEvents = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents)

        XCTAssertEqual(chordEvents.map(\.startPosition.displayText), ["3", "4"])
        XCTAssertEqual(chordLayouts.map(\.text), ["C-7", "D-7"])
        XCTAssertGreaterThan(chordLayouts[1].fitFrame.minX, chordLayouts[0].fitFrame.minX)
    }

    func testSimpleChordSheetMeterGutterAlignsAcrossRows() throws {
        var chart = Chart.blank(title: "Manual Rows", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondSystem = try XCTUnwrap(layout.systems.last)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let secondRowFirstMeasure = try XCTUnwrap(secondSystem.measures.first)

        XCTAssertEqual(firstSystem.measures.count, 4)
        XCTAssertEqual(secondSystem.measures.count, 2)
        XCTAssertNotNil(firstSystem.timeSignatureFrame)
        XCTAssertNil(secondSystem.timeSignatureFrame)
        XCTAssertEqual(firstMeasure.frame.minX - firstSystem.frame.minX, 42, accuracy: 0.001)
        XCTAssertEqual(secondRowFirstMeasure.frame.minX - secondSystem.frame.minX, 42, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.frame.minX, secondRowFirstMeasure.frame.minX, accuracy: 0.001)
    }

    func testSimpleChordSheetManualSystemBreakControlsRenderedRows() throws {
        var chart = Chart.blank(title: "Manual Rows", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertEqual(layout.systems.count, 2)
        XCTAssertEqual(layout.systems[0].measures.compactMap(\.sourceMeasureID), Array(measureIDs[0..<4]))
        XCTAssertEqual(layout.systems[1].measures.compactMap(\.sourceMeasureID), Array(measureIDs[4..<6]))
        XCTAssertTrue(layout.systems.allSatisfy { $0.staffLineYPositions.isEmpty })
        XCTAssertTrue(layout.systems.allSatisfy { $0.frame.width <= layout.paperFrame.width })
    }

    func testSimpleChordSheetDefaultMeasuresUseEqualRowWidths() throws {
        let chart = Chart.blank(title: "Even Grid", measureCount: 6, layoutStyle: .simpleChordSheet)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let widths = firstSystem.measures.map(\.frame.width)
        let firstWidth = try XCTUnwrap(widths.first)

        XCTAssertEqual(firstSystem.measures.count, 6)
        XCTAssertTrue(
            widths.allSatisfy { abs($0 - firstWidth) <= 0.001 },
            "Default Simple measures should share equal row width until the user applies a manual width."
        )
    }

    func testSimpleChordSheetManualWidthActsAsProportionalRowWeight() throws {
        var chart = Chart.blank(title: "Weighted Grid", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        _ = chart.setMeasureManualLayoutWidth(280, for: measureIDs[1])

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let widths = firstSystem.measures.map(\.frame.width)

        XCTAssertEqual(firstSystem.measures.count, 4)
        XCTAssertGreaterThan(widths[1], widths[0])
        XCTAssertEqual(widths[0], widths[2], accuracy: 0.001)
        XCTAssertEqual(widths[2], widths[3], accuracy: 0.001)
        XCTAssertLessThanOrEqual(firstSystem.measures.last?.frame.maxX ?? 0, firstSystem.frame.maxX + 0.001)
    }

    func testSimpleChordSheetAllowsSixteenMeasuresOnOneManualRow() throws {
        let chart = Chart.blank(title: "Dense Grid", measureCount: 16, layoutStyle: .simpleChordSheet)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let lastMeasure = try XCTUnwrap(firstSystem.measures.last)

        XCTAssertEqual(layout.systems.count, 1)
        XCTAssertEqual(firstSystem.measures.count, 16)
        XCTAssertLessThanOrEqual(lastMeasure.frame.maxX, firstSystem.frame.maxX + 0.001)
        XCTAssertGreaterThan(firstSystem.measures[0].frame.width, 20)
        XCTAssertTrue(firstSystem.staffLineYPositions.isEmpty)
    }

    func testSimpleChordSheetRowCapCreatesNextRenderedSystem() throws {
        let chart = Chart.blank(title: "Capped Grid", measureCount: 21, layoutStyle: .simpleChordSheet)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertEqual(layout.systems.map { $0.measures.count }, [20, 1])
        XCTAssertTrue(layout.systems.allSatisfy { $0.staffLineYPositions.isEmpty })
    }

    func testRhythmSectionSheetLayoutOmitsKeyHeaderButKeepsStaffSystem() throws {
        let chart = Chart.blank(title: "Pocket", measureCount: 4, layoutStyle: .rhythmSectionSheet)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertNotNil(layout.header.meterFrame)
        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertNotNil(firstSystem.clefFrame)
        XCTAssertNotNil(firstSystem.timeSignatureFrame)
        XCTAssertTrue(firstSystem.keySignatureLayouts.isEmpty)
        XCTAssertNil(try XCTUnwrap(firstSystem.measures.first).freehandAboveFrame)
        XCTAssertNotNil(try XCTUnwrap(firstSystem.measures.first).freehandBelowFrame)
    }

    func testRhythmSectionCueTextRendersBelowSelectedMeasure() throws {
        var chart = Chart.blank(title: "Hits", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let measureID = chart.measures[1].id
        let cueTextID = try XCTUnwrap(
            chart.addCueText("stop time", anchorMeasureID: measureID, position: .below)
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let measure = try XCTUnwrap(layout.systems.first?.measures.first { $0.sourceMeasureID == measureID })
        let cueTextLayout = try XCTUnwrap(measure.cueTextLayouts.first)

        XCTAssertEqual(cueTextLayout.id, cueTextID)
        XCTAssertEqual(cueTextLayout.text, "stop time")
        XCTAssertEqual(cueTextLayout.position, .below)
        XCTAssertGreaterThan(cueTextLayout.frame.minY, measure.staffFrame.maxY)
        XCTAssertLessThanOrEqual(cueTextLayout.frame.maxX, measure.staffFrame.maxX)
    }

    func testSimpleChordSheetCueTextRendersAsSecondaryMeasureText() throws {
        var chart = Chart.blank(title: "Simple Cue", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = try XCTUnwrap(
            chart.addCueText("freely", anchorMeasureID: measureID, position: .above, emphasis: .subtle)
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(firstSystem.measures.first)
        let cueTextLayout = try XCTUnwrap(measure.cueTextLayouts.first)

        XCTAssertTrue(firstSystem.staffLineYPositions.isEmpty)
        XCTAssertEqual(cueTextLayout.text, "freely")
        XCTAssertEqual(cueTextLayout.emphasis, .subtle)
        XCTAssertTrue(measure.frame.contains(CGPoint(x: cueTextLayout.frame.midX, y: cueTextLayout.frame.midY)))
        XCTAssertLessThan(cueTextLayout.frame.midY, measure.staffFrame.midY)
    }

    func testSimpleChordSheetRepeatSpanAddsCompactEdgeMarkers() throws {
        var chart = Chart.blank(title: "Simple Repeats", measureCount: 2, layoutStyle: .simpleChordSheet)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[1].id
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let startMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == startMeasureID })
        let endMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == endMeasureID })
        let startMarker = try XCTUnwrap(startMeasure.repeatMarkerLayouts.first)
        let endMarker = try XCTUnwrap(endMeasure.repeatMarkerLayouts.first)

        XCTAssertTrue(firstSystem.staffLineYPositions.isEmpty)
        XCTAssertNil(firstSystem.roadmapText)
        XCTAssertNil(firstSystem.roadmapTextFrame)
        XCTAssertEqual(startMarker.roadmapObjectID, repeatID)
        XCTAssertEqual(startMarker.edge, .leading)
        XCTAssertEqual(startMarker.frame.midX, startMeasure.staffFrame.minX, accuracy: 0.001)
        XCTAssertEqual(startMarker.frame.midX, try XCTUnwrap(firstSystem.measures.first?.frame.minX), accuracy: 0.001)
        XCTAssertEqual(endMarker.roadmapObjectID, repeatID)
        XCTAssertEqual(endMarker.edge, .trailing)
        XCTAssertEqual(endMarker.frame.midX, endMeasure.staffFrame.maxX, accuracy: 0.001)
    }

    func testRhythmSectionRepeatSpanAddsNotationEdgeMarkers() throws {
        var chart = Chart.blank(title: "Rhythm Repeats", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[1].id
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let startMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == startMeasureID })
        let endMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == endMeasureID })
        let startMarker = try XCTUnwrap(startMeasure.repeatMarkerLayouts.first)
        let endMarker = try XCTUnwrap(endMeasure.repeatMarkerLayouts.first)

        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertNil(firstSystem.roadmapText)
        XCTAssertNil(firstSystem.roadmapTextFrame)
        XCTAssertEqual(startMarker.edge, .leading)
        XCTAssertEqual(startMarker.frame.minY, startMeasure.staffFrame.minY, accuracy: 0.001)
        XCTAssertEqual(startMarker.frame.maxY, startMeasure.staffFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(endMarker.edge, .trailing)
        XCTAssertEqual(endMarker.frame.minY, endMeasure.staffFrame.minY, accuracy: 0.001)
        XCTAssertEqual(endMarker.frame.maxY, endMeasure.staffFrame.maxY, accuracy: 0.001)
    }

    func testOneMeasureRepeatSpanAddsLeadingAndTrailingMarkersToSameMeasure() throws {
        var chart = Chart.blank(title: "One Bar Repeat", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureID, endMeasureID: measureID)
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let measure = try XCTUnwrap(layout.systems.first?.measures.first)

        XCTAssertEqual(Set(measure.repeatMarkerLayouts.map(\.edge)), [.leading, .trailing])
        XCTAssertEqual(measure.repeatMarkerLayouts.count, 2)
    }

    func testSimpleChordSheetEndingSpanAddsCompactBracketAboveBlankMeasureSpace() throws {
        var chart = Chart.blank(title: "Simple Endings", measureCount: 2, layoutStyle: .simpleChordSheet)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[1].id
        let endingID = try XCTUnwrap(
            chart.addEndingSpan(.ending1, startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let endingLayout = try XCTUnwrap(firstSystem.endingLayouts.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == startMeasureID })
        let secondMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == endMeasureID })

        XCTAssertTrue(firstSystem.staffLineYPositions.isEmpty)
        XCTAssertNil(firstSystem.roadmapText)
        XCTAssertNil(firstSystem.roadmapTextFrame)
        XCTAssertEqual(endingLayout.roadmapObjectID, endingID)
        XCTAssertEqual(endingLayout.type, .ending1)
        XCTAssertEqual(endingLayout.text, "1.")
        XCTAssertTrue(endingLayout.showsLeadingHook)
        XCTAssertTrue(endingLayout.showsTrailingHook)
        XCTAssertLessThanOrEqual(endingLayout.frame.maxY, firstMeasure.staffFrame.minY)
        XCTAssertEqual(endingLayout.frame.minX, firstMeasure.staffFrame.minX + 4, accuracy: 0.001)
        XCTAssertEqual(endingLayout.frame.maxX, secondMeasure.staffFrame.maxX - 4, accuracy: 0.001)
    }

    func testRhythmSectionEndingSpanReservesBracketSpaceAboveChordLane() throws {
        var chart = Chart.blank(title: "Rhythm Endings", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let startMeasureID = chart.measures[0].id
        let endMeasureID = chart.measures[1].id
        _ = try XCTUnwrap(
            chart.addEndingSpan(.ending2, startMeasureID: startMeasureID, endMeasureID: endMeasureID)
        )
        try appendChord("C7", to: startMeasureID, in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let endingLayout = try XCTUnwrap(firstSystem.endingLayouts.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == startMeasureID })
        let chordLayout = try XCTUnwrap(firstMeasure.chordLayouts.first)

        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertNil(firstSystem.roadmapText)
        XCTAssertNil(firstSystem.roadmapTextFrame)
        XCTAssertEqual(endingLayout.type, .ending2)
        XCTAssertEqual(endingLayout.text, "2.")
        XCTAssertLessThanOrEqual(endingLayout.frame.maxY, firstMeasure.chordBandFrame.minY)
        XCTAssertGreaterThanOrEqual(chordLayout.frame.minY, firstMeasure.chordBandFrame.minY)
        XCTAssertLessThan(firstMeasure.chordBandFrame.maxY, firstMeasure.staffFrame.minY)
    }

    func testSimpleChordSheetPointRoadmapMarkerRendersAboveBlankMeasureSpace() throws {
        var chart = Chart.blank(title: "Simple Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let markerID = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: measureID))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let markerLayout = try XCTUnwrap(firstSystem.roadmapMarkerLayouts.first)

        XCTAssertTrue(firstSystem.staffLineYPositions.isEmpty)
        XCTAssertNil(firstSystem.roadmapText)
        XCTAssertNil(firstSystem.roadmapTextFrame)
        XCTAssertEqual(markerLayout.roadmapObjectID, markerID)
        XCTAssertEqual(markerLayout.type, .fine)
        XCTAssertEqual(markerLayout.text, "Fine")
        XCTAssertLessThanOrEqual(markerLayout.frame.maxY, firstMeasure.staffFrame.minY)
        XCTAssertEqual(markerLayout.frame.minX, firstMeasure.staffFrame.minX + 6, accuracy: 0.001)
    }

    func testRhythmSectionPointRoadmapMarkerReservesSpaceAboveChordLane() throws {
        var chart = Chart.blank(title: "Rhythm Roadmap", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.dsAlCoda, anchorMeasureID: measureID))
        try appendChord("C7", to: measureID, in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let markerLayout = try XCTUnwrap(firstSystem.roadmapMarkerLayouts.first)
        let chordLayout = try XCTUnwrap(firstMeasure.chordLayouts.first)

        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertNil(firstSystem.roadmapText)
        XCTAssertNil(firstSystem.roadmapTextFrame)
        XCTAssertEqual(markerLayout.text, "D.S. al Coda")
        XCTAssertLessThanOrEqual(markerLayout.frame.maxY, firstMeasure.chordBandFrame.minY)
        XCTAssertGreaterThanOrEqual(chordLayout.frame.minY, firstMeasure.chordBandFrame.minY)
        XCTAssertLessThan(firstMeasure.chordBandFrame.maxY, firstMeasure.staffFrame.minY)
    }

    func testRhythmSectionSheetPreservesCurrentRhythmAndChordWorkflow() throws {
        var chart = Chart.blank(title: "Pocket", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
        XCTAssertTrue(
            chart.appendRecognizedChord(
                try ChordSymbolParser.parse("C"),
                rawInput: "C",
                to: measureID,
                atFraction: 0.03
            )
        )
        XCTAssertTrue(
            chart.appendRecognizedChord(
                try ChordSymbolParser.parse("G"),
                rawInput: "G",
                to: measureID,
                atFraction: 0.62
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertNotNil(layout.header.meterFrame)
        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertNotNil(firstSystem.clefFrame)
        XCTAssertNotNil(firstSystem.timeSignatureFrame)
        XCTAssertTrue(firstSystem.keySignatureLayouts.isEmpty)
        XCTAssertNil(firstMeasure.freehandAboveFrame)
        XCTAssertNotNil(firstMeasure.freehandBelowFrame)
        XCTAssertLessThan(firstMeasure.chordBandFrame.maxY, firstMeasure.staffFrame.minY)
        XCTAssertEqual(firstMeasure.noteLayouts.count, 4)
        XCTAssertEqual(firstMeasure.chordLayouts.map(\.text), ["C", "G"])
        XCTAssertEqual(firstMeasure.chordLayouts[0].frame.midX, firstMeasure.noteLayouts[0].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[1].frame.midX, firstMeasure.noteLayouts[2].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[0].snapGuideTarget.x, firstMeasure.noteLayouts[0].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[1].snapGuideTarget.x, firstMeasure.noteLayouts[2].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertTrue(layout.freehandSymbolLayouts(for: chart).isEmpty)
    }

    func testSimpleChordSheetExportReadinessKeepsStructuredObjectsReadable() throws {
        var chart = Chart.blank(title: "Simple Export Proof", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        chart.addSectionLabel(text: "Intro")
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))
        _ = try XCTUnwrap(chart.addCueText("freely", anchorMeasureID: measureIDs[1], position: .above, emphasis: .subtle))
        _ = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureIDs[0],
                lane: .chartArea,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.1, y: 0.1, width: 0.3, height: 0.4),
                measureRelativeFrame: FreehandSymbolMeasureFrame(offsetX: 16, offsetY: -22, width: 44, height: 18),
                drawingData: Data([1, 2, 3])
            )
        )
        try appendChord("C", to: measureIDs[0], in: &chart, atFraction: 0.05)
        try appendChord("F", to: measureIDs[1], in: &chart, atFraction: 0.05)
        try appendChord("G/B", to: measureIDs[2], in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == measureIDs[0] })
        let secondMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == measureIDs[1] })
        let cueTextLayout = try XCTUnwrap(secondMeasure.cueTextLayouts.first)
        let freehandLayout = try XCTUnwrap(layout.freehandSymbolLayouts(for: chart).first)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertTrue(layout.systems.allSatisfy(\.staffLineYPositions.isEmpty))
        XCTAssertEqual(firstSystem.sectionText, "Intro")
        XCTAssertEqual(firstSystem.measures.flatMap(\.chordLayouts).map(\.text), ["C", "F", "G/B"])
        XCTAssertEqual(firstMeasure.repeatMarkerLayouts.first?.edge, .leading)
        XCTAssertEqual(firstSystem.measures.last?.repeatMarkerLayouts.first?.edge, .trailing)
        XCTAssertEqual(cueTextLayout.text, "freely")
        XCTAssertTrue(secondMeasure.frame.contains(CGPoint(x: cueTextLayout.frame.midX, y: cueTextLayout.frame.midY)))
        XCTAssertEqual(freehandLayout.symbol.lane, .chartArea)
        XCTAssertEqual(freehandLayout.laneFrame, layout.paperFrame)
        XCTAssertTrue(layout.paperFrame.contains(freehandLayout.frame))
        XCTAssertEqual(freehandLayout.frame.minX, firstMeasure.frame.minX + 16, accuracy: 0.001)
        XCTAssertEqual(freehandLayout.frame.minY, firstMeasure.frame.minY - 22, accuracy: 0.001)
    }

    func testRhythmSectionExportReadinessKeepsProfessionalHitChartHierarchy() throws {
        var chart = Chart.blank(title: "Rhythm Export Proof", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        chart.addSectionLabel(text: "A")
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))
        _ = try XCTUnwrap(chart.addCueText("stop time", anchorMeasureID: measureIDs[1], position: .below))
        _ = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureIDs[2],
                lane: .belowMeasure,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.2, y: 0.2, width: 0.25, height: 0.35),
                drawingData: Data([4, 5, 6])
            )
        )
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureIDs[0]))
        XCTAssertTrue(chart.setMeasureRhythmMap([.dottedHalf, .eighth, .eighth], for: measureIDs[1]))
        try appendChord("C7", to: measureIDs[0], in: &chart, atFraction: 0.05)
        try appendChord("F7", to: measureIDs[1], in: &chart, atFraction: 0.05)
        try appendChord("G7sus", to: measureIDs[2], in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let allMeasures = layout.systems.flatMap(\.measures)
        let firstMeasure = try XCTUnwrap(allMeasures.first { $0.sourceMeasureID == measureIDs[0] })
        let secondMeasure = try XCTUnwrap(allMeasures.first { $0.sourceMeasureID == measureIDs[1] })
        let thirdMeasure = try XCTUnwrap(allMeasures.first { $0.sourceMeasureID == measureIDs[2] })
        let fourthMeasure = try XCTUnwrap(allMeasures.first { $0.sourceMeasureID == measureIDs[3] })
        let cueTextLayout = try XCTUnwrap(secondMeasure.cueTextLayouts.first)
        let freehandLayout = try XCTUnwrap(layout.freehandSymbolLayouts(for: chart).first)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertNotNil(layout.header.meterFrame)
        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertEqual(firstSystem.sectionText, "A")
        XCTAssertEqual(allMeasures.flatMap(\.chordLayouts).map(\.text), ["C7", "F7", "G7sus"])
        XCTAssertEqual(firstMeasure.repeatMarkerLayouts.first?.edge, .leading)
        XCTAssertEqual(fourthMeasure.repeatMarkerLayouts.first?.edge, .trailing)
        XCTAssertEqual(firstMeasure.noteLayouts.count, 4)
        XCTAssertEqual(secondMeasure.noteLayouts.count, 3)
        XCTAssertTrue(firstSystem.measures.flatMap(\.chordLayouts).allSatisfy { $0.frame.maxY < firstMeasure.staffFrame.minY })
        XCTAssertGreaterThan(cueTextLayout.frame.minY, secondMeasure.staffFrame.maxY)
        XCTAssertFalse(cueTextLayout.frame.intersects(secondMeasure.staffFrame))
        XCTAssertTrue(try XCTUnwrap(thirdMeasure.freehandBelowFrame).contains(freehandLayout.frame))
        XCTAssertFalse(thirdMeasure.chordBandFrame.intersects(freehandLayout.frame))
        XCTAssertFalse(thirdMeasure.staffFrame.intersects(freehandLayout.frame))
    }

    func testRhythmSectionFreehandSymbolLayoutsResolveBelowStaffOnly() throws {
        var chart = Chart.blank(title: "Pocket", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let belowFrame = FreehandSymbolNormalizedFrame(x: 0.15, y: 0.2, width: 0.4, height: 0.5)

        XCTAssertNotNil(
            chart.addFreehandSymbol(
                anchorMeasureID: measureID,
                lane: .belowMeasure,
                normalizedFrame: belowFrame,
                drawingData: Data([4, 5, 6])
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let symbolLayout = try XCTUnwrap(layout.freehandSymbolLayouts(for: chart).first)
        let expectedBelowLane = try XCTUnwrap(firstMeasure.freehandBelowFrame)

        XCTAssertNil(firstMeasure.freehandAboveFrame)
        XCTAssertTrue(expectedBelowLane.contains(symbolLayout.frame))
        XCTAssertFalse(firstMeasure.chordBandFrame.intersects(symbolLayout.frame))
        XCTAssertFalse(firstMeasure.staffFrame.intersects(symbolLayout.frame))
    }

    func testSimpleFreehandSymbolLayoutsResolveAsMeasureAttachedChartAreaInk() throws {
        var chart = Chart.blank(title: "Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let normalizedFrame = FreehandSymbolNormalizedFrame(x: 0.2, y: 0.1, width: 0.3, height: 0.4)
        let measureRelativeFrame = FreehandSymbolMeasureFrame(offsetX: -14, offsetY: -22, width: 46, height: 18)

        XCTAssertNotNil(
            chart.addFreehandSymbol(
                anchorMeasureID: measureID,
                lane: .chartArea,
                normalizedFrame: normalizedFrame,
                measureRelativeFrame: measureRelativeFrame,
                drawingData: Data([1, 2, 3])
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let symbolLayouts = layout.freehandSymbolLayouts(for: chart)
        XCTAssertEqual(symbolLayouts.count, 1)
        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let resolvedSymbol = try XCTUnwrap(symbolLayouts.first)

        XCTAssertNil(firstMeasure.freehandAboveFrame)
        XCTAssertNil(firstMeasure.freehandBelowFrame)
        XCTAssertEqual(resolvedSymbol.symbol.lane, .chartArea)
        XCTAssertEqual(resolvedSymbol.laneFrame, layout.paperFrame)
        XCTAssertTrue(layout.paperFrame.contains(resolvedSymbol.frame))
        XCTAssertEqual(resolvedSymbol.frame.minX, firstMeasure.frame.minX - 14, accuracy: 0.001)
        XCTAssertEqual(resolvedSymbol.frame.minY, firstMeasure.frame.minY - 22, accuracy: 0.001)
        XCTAssertEqual(resolvedSymbol.frame.width, 46, accuracy: 0.001)
        XCTAssertEqual(resolvedSymbol.frame.height, 18, accuracy: 0.001)
    }

    func testLeadSheetLayoutKeepsKeyHeaderAndLeadingNotation() throws {
        let chart = Chart.blank(title: "Lead", measureCount: 4, layoutStyle: .leadSheet)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)

        XCTAssertNotNil(layout.header.keyFrame)
        XCTAssertNotNil(layout.header.meterFrame)
        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertNotNil(firstSystem.clefFrame)
        XCTAssertNotNil(firstSystem.timeSignatureFrame)
        XCTAssertTrue(firstSystem.keySignatureLayouts.isEmpty)
        XCTAssertNil(try XCTUnwrap(firstSystem.measures.first).freehandAboveFrame)
        XCTAssertNil(try XCTUnwrap(firstSystem.measures.first).freehandBelowFrame)
    }

    func testLeadSheetLayoutPlacesKeySignatureBeforeFirstMeasure() throws {
        let chart = Chart.blank(
            title: "Lead Key",
            key: DocumentKey(tonic: .d, accidental: .natural, mode: .major),
            measureCount: 4,
            layoutStyle: .leadSheet
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let clefFrame = try XCTUnwrap(firstSystem.clefFrame)
        let timeSignatureFrame = try XCTUnwrap(firstSystem.timeSignatureFrame)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)

        XCTAssertEqual(firstSystem.keySignatureLayouts.map(\.symbol), [.accidentalSharp, .accidentalSharp])
        XCTAssertGreaterThan(try XCTUnwrap(firstSystem.keySignatureLayouts.first).frame.minX, clefFrame.maxX)
        XCTAssertLessThan(try XCTUnwrap(firstSystem.keySignatureLayouts.last).frame.maxX, timeSignatureFrame.minX)
        XCTAssertLessThan(timeSignatureFrame.maxX, firstMeasure.frame.minX)
    }

    func testLeadSheetBassClefKeySignatureUsesBassPositions() throws {
        let key = DocumentKey(tonic: .d, accidental: .natural, mode: .major)
        var trebleChart = Chart.draft(title: "Treble", key: key, layoutStyle: .leadSheet)
        trebleChart.completeInitialSetup(
            title: "Treble",
            key: key,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 4,
            clef: .treble
        )
        var bassChart = Chart.draft(title: "Bass", key: key, layoutStyle: .leadSheet)
        bassChart.completeInitialSetup(
            title: "Bass",
            key: key,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 4,
            clef: .bass
        )

        let trebleLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: trebleChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let bassLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: bassChart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let trebleSharp = try XCTUnwrap(trebleLayout.systems.first?.keySignatureLayouts.first)
        let bassSharp = try XCTUnwrap(bassLayout.systems.first?.keySignatureLayouts.first)

        XCTAssertEqual(trebleSharp.symbol, .accidentalSharp)
        XCTAssertEqual(bassSharp.symbol, .accidentalSharp)
        XCTAssertEqual(trebleSharp.staffOffset, 0, accuracy: 0.001)
        XCTAssertEqual(bassSharp.staffOffset, 1, accuracy: 0.001)
        XCTAssertGreaterThan(bassSharp.frame.midY, trebleSharp.frame.midY)
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

    func testLeadSheetLayoutShowsMeterChangeInsideChangedMeasure() throws {
        var chart = makeBlankLeadSheet()
        _ = chart.commitOpenMeasure()
        let thirdMeasureID = try XCTUnwrap(chart.commitOpenMeasure())
        let changedMeasureID = try XCTUnwrap(chart.applyMeterChange(
            Meter(numerator: 3, denominator: 4),
            after: thirdMeasureID,
            scope: .toNextTimeSignature
        ))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let allMeasures = layout.systems.flatMap(\.measures)
        let changedMeasure = try XCTUnwrap(
            allMeasures.first { $0.sourceMeasureID == changedMeasureID }
        )
        let previousMeasure = try XCTUnwrap(
            allMeasures.first { $0.sourceMeasureID == thirdMeasureID }
        )
        let meterFrame = try XCTUnwrap(changedMeasure.meterChangeFrame)

        XCTAssertNil(previousMeasure.meterChange)
        XCTAssertEqual(changedMeasure.meterChange, Meter(numerator: 3, denominator: 4))
        XCTAssertGreaterThan(meterFrame.minX, changedMeasure.frame.minX)
        XCTAssertLessThan(meterFrame.maxX, changedMeasure.frame.midX)
    }

    func testSimpleChordSheetLayoutShowsMeterChangeInsideChangedGridCell() throws {
        var chart = Chart.blank(title: "Simple Time", measureCount: 3, layoutStyle: .simpleChordSheet)
        let secondMeasureID = chart.measures[1].id
        let changedMeasureID = try XCTUnwrap(chart.applyMeterChange(
            Meter(numerator: 3, denominator: 4),
            after: secondMeasureID,
            scope: .toNextTimeSignature
        ))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let sourceMeasure = try XCTUnwrap(
            firstSystem.measures.first { $0.sourceMeasureID == secondMeasureID }
        )
        let changedMeasure = try XCTUnwrap(
            firstSystem.measures.first { $0.sourceMeasureID == changedMeasureID }
        )
        let meterFrame = try XCTUnwrap(changedMeasure.meterChangeFrame)

        XCTAssertNil(sourceMeasure.meterChange)
        XCTAssertEqual(changedMeasure.meterChange, Meter(numerator: 3, denominator: 4))
        XCTAssertTrue(changedMeasure.staffFrame.intersects(meterFrame))
        XCTAssertGreaterThan(meterFrame.minX, changedMeasure.frame.minX)
        XCTAssertLessThan(meterFrame.maxX, changedMeasure.frame.midX)
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

    func testLeadSheetLayoutRendersPitchedNotesOnStaffPositions() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.setLeadSheetPitchedNotes(
                [
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 0)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 2)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 4)),
                    LeadSheetPitchedNoteInput(rhythmValue: .quarter, staffPosition: LeadSheetStaffPosition(staffStep: 8))
                ],
                for: firstMeasureID
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let staffSpace = firstSystem.staffLineYPositions[1] - firstSystem.staffLineYPositions[0]
        let topLineY = firstSystem.staffLineYPositions[0]

        XCTAssertEqual(firstMeasure.noteLayouts.count, 4)
        XCTAssertEqual(firstMeasure.noteLayouts.map(\.symbolStyle), Array(repeating: .pitchedNote, count: 4))
        XCTAssertEqual(firstMeasure.noteLayouts.map(\.noteheadSymbol), Array(repeating: .noteheadBlack, count: 4))
        XCTAssertEqual(firstMeasure.noteLayouts[0].noteheadFrame.midY, topLineY, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.noteLayouts[1].noteheadFrame.midY, topLineY + staffSpace, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.noteLayouts[2].noteheadFrame.midY, topLineY + staffSpace * 2, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.noteLayouts[3].noteheadFrame.midY, topLineY + staffSpace * 4, accuracy: 0.001)
        XCTAssertFalse(firstMeasure.noteLayouts[0].stemGoesUp)
        XCTAssertTrue(firstMeasure.noteLayouts[3].stemGoesUp)
    }

    func testLeadSheetLayoutRendersMixedPitchedNotesAndRests() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(
            chart.setLeadSheetRhythmMap(
                [.quarter, .quarterRest, .quarter, .quarterRest],
                pitchedNotes: [
                    LeadSheetPitchedNoteSlotInput(
                        rhythmSlotIndex: 0,
                        staffPosition: LeadSheetStaffPosition(staffStep: 1)
                    ),
                    LeadSheetPitchedNoteSlotInput(
                        rhythmSlotIndex: 2,
                        staffPosition: LeadSheetStaffPosition(staffStep: 7)
                    )
                ],
                for: firstMeasureID
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        XCTAssertEqual(
            firstMeasure.noteLayouts.map(\.symbolStyle),
            [.pitchedNote, .quarterRest, .pitchedNote, .quarterRest]
        )
        XCTAssertEqual(firstMeasure.noteLayouts[0].noteheadSymbol, .noteheadBlack)
        XCTAssertNil(firstMeasure.noteLayouts[1].noteheadSymbol)
        XCTAssertEqual(firstMeasure.noteLayouts[2].noteheadSymbol, .noteheadBlack)
        XCTAssertNil(firstMeasure.noteLayouts[3].noteheadSymbol)
    }

    func testRhythmSectionLayoutKeepsRhythmMapAsSlashNotationWhenLeadPitchEventsExistOnlyOnLeadSheets() throws {
        var chart = Chart.blank(title: "Pocket", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        XCTAssertEqual(firstMeasure.noteLayouts.map(\.symbolStyle), Array(repeating: .slash, count: 4))
        XCTAssertEqual(firstMeasure.noteLayouts.map(\.noteheadSymbol), Array(repeating: .slashNotehead, count: 4))
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

    private func appendChord(
        _ text: String,
        to measureID: UUID,
        in chart: inout Chart,
        atFraction fraction: Double
    ) throws {
        XCTAssertTrue(
            chart.appendRecognizedChord(
                try ChordSymbolParser.parse(text),
                rawInput: text,
                to: measureID,
                atFraction: fraction
            )
        )
    }

    private func simpleChordMeasureGaps(
        for chordLayouts: [LeadSheetChordLayout],
        in chordBandFrame: CGRect
    ) -> [CGFloat] {
        guard let firstChord = chordLayouts.first,
              let lastChord = chordLayouts.last else {
            return []
        }

        var gaps = [firstChord.frame.minX - chordBandFrame.minX]
        for (leftChord, rightChord) in zip(chordLayouts, chordLayouts.dropFirst()) {
            gaps.append(rightChord.frame.minX - leftChord.frame.maxX)
        }
        gaps.append(chordBandFrame.maxX - lastChord.frame.maxX)
        return gaps
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

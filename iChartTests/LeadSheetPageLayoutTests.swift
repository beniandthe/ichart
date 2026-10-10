import CoreGraphics
import XCTest
@testable import iChart

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
        let meterFrame = try XCTUnwrap(layout.header.meterFrame)
        let composerFrame = try XCTUnwrap(layout.header.composerFrame)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertEqual(layout.header.titleFrame.midX, layout.paperFrame.midX, accuracy: 0.001)
        XCTAssertGreaterThan(styleNoteFrame.minY, layout.header.titleFrame.maxY)
        XCTAssertEqual(styleNoteFrame.midY, composerFrame.midY, accuracy: 0.001)
        XCTAssertEqual(meterFrame.midY, composerFrame.midY, accuracy: 0.001)
        XCTAssertEqual(meterFrame.midX, layout.header.frame.midX, accuracy: 0.001)
        XCTAssertLessThan(styleNoteFrame.maxX, meterFrame.minX)
        XCTAssertLessThan(meterFrame.maxX, composerFrame.minX)
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
            pageSize: CGSize(width: 760, height: 1400)
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

    func testHeaderLayoutProvidesWritableHandwrittenHeaderFrame() {
        var chart = Chart.blank(
            title: "Handwritten Header",
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        chart.setHeaderInputMode(.handwritten)
        chart.styleNote = "Medium Swing"
        chart.composerCredit = "Composer"

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let firstSystemFrame = layout.systems.first?.frame ?? .zero

        XCTAssertTrue(layout.paperFrame.contains(layout.header.handwrittenFrame))
        XCTAssertTrue(layout.header.handwrittenFrame.contains(layout.header.titleFrame))
        XCTAssertGreaterThan(layout.header.handwrittenFrame.height, layout.header.titleFrame.height)
        XCTAssertLessThan(layout.header.handwrittenFrame.maxY, firstSystemFrame.minY)
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

    func testAppendPageCreatesSeparatePaperWithCompactTopMargin() throws {
        var chart = Chart.blank(
            title: "Two Page Simple Sheet",
            measureCount: 8,
            layoutStyle: .simpleChordSheet
        )
        let firstNewMeasureID = try XCTUnwrap(chart.appendPage())

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let firstPaperPage = try XCTUnwrap(layout.pages.first)
        let secondPaperPage = try XCTUnwrap(layout.pages.dropFirst().first)
        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondPageSystem = try XCTUnwrap(
            layout.systems.first { system in
                system.measures.contains { $0.sourceMeasureID == firstNewMeasureID }
            }
        )
        let firstPageTopGap = firstSystem.frame.minY - firstPaperPage.frame.minY
        let secondPageTopGap = secondPageSystem.frame.minY - secondPaperPage.frame.minY

        XCTAssertEqual(layout.pages.count, 2)
        XCTAssertEqual(secondPaperPage.frame.minY - firstPaperPage.frame.maxY, 28, accuracy: 0.001)
        XCTAssertEqual(layout.paperFrame(for: secondPageSystem), secondPaperPage.frame)
        XCTAssertEqual(secondPaperPage.systemIDs, [secondPageSystem.id])
        XCTAssertEqual(secondPageSystem.measures.map(\.sourceMeasureID), [firstNewMeasureID])
        XCTAssertEqual(secondPageSystem.measures.first?.barlineAfter, .double)

        #if canImport(UIKit)
        let secondPageMeasure = try XCTUnwrap(secondPageSystem.measures.first)
        let secondPageBoundary = LeadSheetSimpleChordTerminalBarlineGeometry.renderedBoundary(
            after: secondPageMeasure,
            before: nil,
            excludingRepeatMarkerIDs: [],
            in: secondPageSystem,
            paperFrame: secondPaperPage.frame,
            layoutStyle: chart.layoutStyle
        )
        let secondPageTerminalBarlineFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: secondPageSystem,
                paperFrame: secondPaperPage.frame,
                layoutStyle: chart.layoutStyle
            )
        )
        guard case .normalBarline(.double, let renderedBarlineFrame) = secondPageBoundary else {
            return XCTFail("Expected one starter measure with a final page-end barline.")
        }
        XCTAssertEqual(renderedBarlineFrame, secondPageTerminalBarlineFrame)
        XCTAssertGreaterThan(
            renderedBarlineFrame.midX,
            secondPageMeasure.trailingBarlineFrame.midX + 1
        )
        #endif

        XCTAssertFalse(secondPaperPage.includesHeader)
        XCTAssertFalse(secondPaperPage.frame.intersects(layout.header.frame))
        XCTAssertLessThan(secondPageTopGap, 60)
        XCTAssertGreaterThan(firstPageTopGap, secondPageTopGap + 80)
        XCTAssertGreaterThanOrEqual(layout.pageBounds.height, secondPaperPage.frame.maxY + 30)
    }

    func testThirtyTwoMeasureRhythmChartAutomaticallyPaginatesWithoutStretchingPaper() throws {
        let chart = Chart.blank(
            title: "Fixed Rhythm Pages",
            measureCount: 32,
            layoutStyle: .rhythmSectionSheet
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 2_400)
        )

        XCTAssertGreaterThan(layout.pages.count, 1)
        XCTAssertEqual(layout.pages.map(\.frame.height), Array(repeating: 1_040, count: layout.pages.count))

        let renderedMeasureIDs = layout.systems
            .flatMap(\.measures)
            .compactMap(\.sourceMeasureID)
        XCTAssertEqual(renderedMeasureIDs, chart.measures.map(\.id))

        for page in layout.pages {
            let pageSystems = layout.systems.filter { page.systemIDs.contains($0.id) }
            XCTAssertFalse(pageSystems.isEmpty)
            for system in pageSystems {
                XCTAssertGreaterThanOrEqual(system.frame.minY, page.frame.minY)
                XCTAssertLessThanOrEqual(system.frame.maxY, page.frame.maxY - 54)
                XCTAssertEqual(system.staffLineYPositions.count, 5)
                XCTAssertGreaterThan(system.measures.last?.staffFrame.maxX ?? 0, system.measures.first?.staffFrame.minX ?? 0)
            }
        }
    }

    func testDenseSimpleChordChartAutomaticallyPaginatesWithoutStretchingPaper() {
        let chart = Chart.blank(
            title: "Fixed Simple Pages",
            measureCount: 140,
            layoutStyle: .simpleChordSheet
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 2_400)
        )

        XCTAssertGreaterThan(layout.pages.count, 1)
        XCTAssertEqual(layout.pages.map(\.frame.height), Array(repeating: 1_040, count: layout.pages.count))
        XCTAssertEqual(
            layout.systems.flatMap(\.measures).compactMap(\.sourceMeasureID),
            chart.measures.map(\.id)
        )
        XCTAssertTrue(layout.systems.allSatisfy(\.staffLineYPositions.isEmpty))
        for page in layout.pages {
            let pageSystems = layout.systems.filter { page.systemIDs.contains($0.id) }
            XCTAssertFalse(pageSystems.isEmpty)
            XCTAssertTrue(pageSystems.allSatisfy { $0.frame.maxY <= page.frame.maxY - 54 })
        }
    }

    func testAutomaticPaginationIsIndependentOfViewportHeight() {
        let chart = Chart.blank(
            title: "Stable Rhythm Pages",
            measureCount: 32,
            layoutStyle: .rhythmSectionSheet
        )

        let compactViewportLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_100)
        )
        let tallViewportLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 3_200)
        )

        XCTAssertEqual(compactViewportLayout.pages.count, tallViewportLayout.pages.count)
        XCTAssertEqual(compactViewportLayout.pages.map(\.frame.height), tallViewportLayout.pages.map(\.frame.height))
        let compactMeasureIDsByPage = compactViewportLayout.pages.map { page in
            compactViewportLayout.systems
                .filter { page.systemIDs.contains($0.id) }
                .flatMap(\.measures)
                .compactMap(\.sourceMeasureID)
        }
        let tallMeasureIDsByPage = tallViewportLayout.pages.map { page in
            tallViewportLayout.systems
                .filter { page.systemIDs.contains($0.id) }
                .flatMap(\.measures)
                .compactMap(\.sourceMeasureID)
        }
        XCTAssertEqual(compactMeasureIDsByPage, tallMeasureIDsByPage)
        XCTAssertEqual(compactViewportLayout.systems.map(\.frame), tallViewportLayout.systems.map(\.frame))
    }

    func testPaperExpandsToLandscapeViewportWidth() {
        let chart = Chart.blank(title: "Landscape Writing Space", measureCount: 8, layoutStyle: .rhythmSectionSheet)

        let portraitLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let landscapeLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1366, height: 1024)
        )

        XCTAssertGreaterThan(landscapeLayout.paperFrame.width, portraitLayout.paperFrame.width)
        XCTAssertGreaterThan(landscapeLayout.paperFrame.width, 1200)
        XCTAssertGreaterThanOrEqual(landscapeLayout.paperFrame.minX, landscapeLayout.pageBounds.minX)
        XCTAssertLessThanOrEqual(landscapeLayout.paperFrame.maxX, landscapeLayout.pageBounds.maxX)
    }

    func testPaperAndSystemMarginsStayConsistentAcrossOrientation() throws {
        let chart = Chart.blank(
            title: "Stable Margins",
            measureCount: 4,
            layoutStyle: .rhythmSectionSheet
        )
        let portraitLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 880, height: 1_400)
        )
        let landscapeLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1_346, height: 1_024)
        )
        let portraitSystem = try XCTUnwrap(portraitLayout.systems.first)
        let landscapeSystem = try XCTUnwrap(landscapeLayout.systems.first)

        XCTAssertEqual(portraitLayout.paperFrame.minX, 24, accuracy: 0.001)
        XCTAssertEqual(landscapeLayout.paperFrame.minX, 24, accuracy: 0.001)
        XCTAssertEqual(portraitSystem.frame.minX - portraitLayout.paperFrame.minX, 34, accuracy: 0.001)
        XCTAssertEqual(landscapeSystem.frame.minX - landscapeLayout.paperFrame.minX, 34, accuracy: 0.001)
        XCTAssertEqual(portraitLayout.paperFrame.maxX - portraitSystem.frame.maxX, 34, accuracy: 0.001)
        XCTAssertEqual(landscapeLayout.paperFrame.maxX - landscapeSystem.frame.maxX, 34, accuracy: 0.001)
    }

    func testSimpleChordSheetPaperAndSystemMarginsStayConsistentAcrossOrientation() throws {
        let chart = Chart.blank(
            title: "Stable Simple Margins",
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        let portraitLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 880, height: 1_400)
        )
        let landscapeLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1_346, height: 1_024)
        )
        let portraitSystem = try XCTUnwrap(portraitLayout.systems.first)
        let landscapeSystem = try XCTUnwrap(landscapeLayout.systems.first)

        XCTAssertEqual(portraitLayout.paperFrame.minX, 24, accuracy: 0.001)
        XCTAssertEqual(landscapeLayout.paperFrame.minX, 24, accuracy: 0.001)
        XCTAssertEqual(portraitSystem.frame.minX - portraitLayout.paperFrame.minX, 34, accuracy: 0.001)
        XCTAssertEqual(landscapeSystem.frame.minX - landscapeLayout.paperFrame.minX, 34, accuracy: 0.001)
        XCTAssertEqual(portraitLayout.paperFrame.maxX - portraitSystem.frame.maxX, 34, accuracy: 0.001)
        XCTAssertEqual(landscapeLayout.paperFrame.maxX - landscapeSystem.frame.maxX, 34, accuracy: 0.001)
    }

    func testRhythmSectionRowsStretchAcrossLandscapePaper() throws {
        let chart = Chart.blank(title: "Full Row Rhythm", measureCount: 4, layoutStyle: .rhythmSectionSheet)

        let portraitLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let landscapeLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1366, height: 1024)
        )

        let portraitMeasure = try XCTUnwrap(portraitLayout.systems.first?.measures.first)
        let landscapeSystem = try XCTUnwrap(landscapeLayout.systems.first)
        let firstLandscapeMeasure = try XCTUnwrap(landscapeSystem.measures.first)
        let lastLandscapeMeasure = try XCTUnwrap(landscapeSystem.measures.last)

        XCTAssertEqual(landscapeSystem.frame.width, landscapeLayout.paperFrame.width - 68, accuracy: 0.001)
        XCTAssertGreaterThan(firstLandscapeMeasure.staffFrame.width, portraitMeasure.staffFrame.width)
        XCTAssertGreaterThan(firstLandscapeMeasure.staffFrame.width, 250)
        XCTAssertGreaterThan(firstLandscapeMeasure.frame.width, firstLandscapeMeasure.staffFrame.width)
        XCTAssertEqual(firstLandscapeMeasure.staffFrame.width, lastLandscapeMeasure.frame.width, accuracy: 0.001)
        XCTAssertEqual(lastLandscapeMeasure.frame.maxX, landscapeSystem.frame.maxX - 6, accuracy: 0.001)
    }

    func testRhythmSectionChordWritingFrameCoversFullAboveStaffLane() throws {
        let chart = Chart.blank(title: "Full Chord Lane", measureCount: 4, layoutStyle: .rhythmSectionSheet)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )

        let measure = try XCTUnwrap(layout.systems.first?.measures.first)

        XCTAssertEqual(measure.chordWritingFrame.minY, measure.frame.minY, accuracy: 0.001)
        XCTAssertGreaterThan(measure.chordWritingFrame.height, measure.chordBandFrame.height)
        XCTAssertTrue(measure.chordWritingFrame.contains(measure.chordBandFrame))
        XCTAssertGreaterThanOrEqual(measure.chordWritingFrame.maxY, measure.staffFrame.minY)
    }

    func testEstimatedSystemCountRespondsToViewportWidth() {
        let chart = Chart.blank(title: "Adaptive Rows", measureCount: 12, layoutStyle: .rhythmSectionSheet)

        let portraitSystemCount = LeadSheetPageLayoutEngine.estimatedSystemCount(
            for: chart,
            pageWidth: 760
        )
        let landscapeSystemCount = LeadSheetPageLayoutEngine.estimatedSystemCount(
            for: chart,
            pageWidth: 1366
        )

        XCTAssertGreaterThan(portraitSystemCount, landscapeSystemCount)
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

    func testChordLayoutsSnapToPlacementGridWhenMeasureHasNoRhythmMap() throws {
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
        XCTAssertEqual(chordLayouts[1].frame.midX, firstMeasure.staffFrame.minX + 8 + beatStep * 3, accuracy: 0.001)
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
        XCTAssertEqual(chordLayout.frame.size, chordLayout.naturalFrame.size)
        XCTAssertEqual(chordLayout.renderFontSize, ChartTypographyResolver.structuredChordPrimaryFontSize)
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
        XCTAssertGreaterThanOrEqual(timeSignatureFrame.height, 56)
        XCTAssertGreaterThan(firstMeasure.frame.minX, firstSystem.frame.minX)
        XCTAssertLessThan(timeSignatureFrame.maxX, firstMeasure.frame.minX)
        XCTAssertEqual(firstMeasure.frame.minX - firstSystem.frame.minX, 58, accuracy: 0.001)
        XCTAssertTrue(firstMeasure.staffFrame.contains(firstMeasure.chordBandFrame))
        XCTAssertGreaterThanOrEqual(firstMeasure.staffFrame.height, 56)
        XCTAssertGreaterThan(firstMeasure.staffFrame.height, firstMeasure.chordBandFrame.height)
        XCTAssertGreaterThanOrEqual(firstChord.frame.minY, firstMeasure.staffFrame.minY)
        XCTAssertLessThanOrEqual(firstChord.frame.maxY, firstMeasure.staffFrame.maxY)
        XCTAssertEqual(firstChord.frame, firstChord.naturalFrame)
        XCTAssertEqual(firstChord.renderFontSize, ChartTypographyResolver.simpleChordPrimaryFontSize)
        XCTAssertTrue(firstMeasure.noteLayouts.isEmpty)
    }

    func testFirstChartMeasureUsesLeadingDoubleBarlineWithoutTrailingMutation() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let chart = Chart.blank(title: "Leading Double", measureCount: 3, layoutStyle: layoutStyle)
            let layout = LeadSheetPageLayoutEngine.pageLayout(
                for: chart,
                pageSize: CGSize(width: 900, height: 1400)
            )
            let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
            let secondMeasure = try XCTUnwrap(layout.systems.first?.measures.dropFirst().first)

            XCTAssertEqual(firstMeasure.leadingBarline, .double)
            XCTAssertEqual(firstMeasure.barlineAfter, .single)
            XCTAssertNil(secondMeasure.leadingBarline)
        }
    }

    func testFreshSimpleChordSheetKeepsOpenLaneWithoutRightBarline() throws {
        var chart = Chart.draft(title: "Open Chord Lane", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Chord Lane",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)

        XCTAssertEqual(firstMeasure.leadingBarline, .double)
        XCTAssertTrue(firstMeasure.isOpen)
        XCTAssertFalse(
            LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(
                after: firstMeasure,
                before: nil
            )
        )
        XCTAssertGreaterThan(firstMeasure.chordBandFrame.width, layout.paperFrame.width * 0.68)
        XCTAssertGreaterThan(firstMeasure.chordBandFrame.maxX, layout.paperFrame.maxX - 52)
    }

    #if canImport(UIKit)
    func testSimpleChordSheetTerminalDisplayFrameExtendsOpenMeasureToLaneStop() throws {
        var chart = Chart.draft(title: "Terminal Chord Lane", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Terminal Chord Lane",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.first)
        let laneFrame = try XCTUnwrap(
            LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: layout.paperFrame
            )
        )
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let displayMeasure = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
            measure,
            in: system,
            paperFrame: layout.paperFrame,
            layoutStyle: chart.layoutStyle
        )

        XCTAssertTrue(measure.isOpen)
        XCTAssertEqual(terminalFrame.midX, laneFrame.maxX - 1, accuracy: 0.001)
        XCTAssertGreaterThan(displayMeasure.frame.maxX, measure.frame.maxX)
        XCTAssertEqual(displayMeasure.frame.maxX, terminalFrame.midX, accuracy: 0.001)
        XCTAssertEqual(displayMeasure.trailingBarlineFrame, terminalFrame)

        let terminalTap = CGPoint(
            x: (measure.frame.maxX + displayMeasure.frame.maxX) / 2,
            y: displayMeasure.frame.midY
        )
        let tappedMeasure = LeadSheetCanvasInteractionTargeting.measure(
            at: terminalTap,
            in: layout,
            layoutStyle: chart.layoutStyle
        )
        XCTAssertEqual(tappedMeasure?.sourceMeasureID, measure.sourceMeasureID)
    }

    func testSimpleChordSheetTerminalSpanSelectsCommittedRowEndMeasure() throws {
        var chart = Chart.blank(title: "Committed Row End", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.last)
        let laneFrame = try XCTUnwrap(
            LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: layout.paperFrame
            )
        )
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let displayMeasure = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
            measure,
            in: system,
            paperFrame: layout.paperFrame,
            layoutStyle: chart.layoutStyle
        )

        XCTAssertFalse(measure.isOpen)
        XCTAssertGreaterThan(terminalFrame.midX, measure.frame.maxX)
        XCTAssertEqual(displayMeasure.frame.maxX, terminalFrame.midX, accuracy: 0.001)
        XCTAssertEqual(displayMeasure.trailingBarlineFrame, terminalFrame)
        XCTAssertTrue(
            LeadSheetSimpleChordTerminalBarlineGeometry.usesTerminalBarlineAsTrailingBoundary(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertFalse(
            LeadSheetSimpleChordTerminalBarlineGeometry.shouldDrawStandaloneTerminalBarline(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )

        let terminalTap = CGPoint(
            x: (measure.frame.maxX + terminalFrame.midX) / 2,
            y: laneFrame.midY
        )
        XCTAssertFalse(
            LeadSheetSimpleChordTerminalBarlineGeometry.containsTerminalFiller(
                terminalTap,
                in: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let tappedMeasure = LeadSheetCanvasInteractionTargeting.measure(
            at: terminalTap,
            in: layout,
            layoutStyle: chart.layoutStyle
        )
        XCTAssertEqual(tappedMeasure?.sourceMeasureID, measure.sourceMeasureID)
    }

    func testSimpleChordSheetRepeatEndedTerminalMeasureDoesNotCreateTerminalFiller() throws {
        var chart = Chart.blank(title: "Repeat End Row", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.last)
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let displayMeasure = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
            measure,
            in: system,
            paperFrame: layout.paperFrame,
            layoutStyle: chart.layoutStyle
        )
        let terminalTap = CGPoint(
            x: (measure.frame.maxX + terminalFrame.midX) / 2,
            y: measure.frame.midY
        )

        XCTAssertFalse(measure.repeatMarkerLayouts.isEmpty)
        XCTAssertGreaterThan(terminalFrame.midX, measure.frame.maxX)
        XCTAssertEqual(displayMeasure.frame, measure.frame)
        XCTAssertNil(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalFillerFrame(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertFalse(
            LeadSheetSimpleChordTerminalBarlineGeometry.containsTerminalFiller(
                terminalTap,
                in: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertNil(
            LeadSheetCanvasInteractionTargeting.measure(
                at: terminalTap,
                in: layout,
                layoutStyle: chart.layoutStyle
            )
        )
    }

    func testSimpleChordSheetTerminalRepeatUsesTerminalBarlineAsRightmostRepeatBarline() throws {
        var chart = Chart.blank(title: "Terminal Repeat", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3])
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let terminalMeasure = try XCTUnwrap(firstSystem.measures.last)
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let trailingMarker = try XCTUnwrap(
            terminalMeasure.repeatMarkerLayouts.first { $0.edge == .trailing }
        )

        XCTAssertEqual(trailingMarker.roadmapObjectID, repeatID)
        XCTAssertEqual(terminalMeasure.sourceMeasureID, measureIDs[3])
        XCTAssertGreaterThan(terminalFrame.midX, trailingMarker.frame.midX)
        XCTAssertTrue(
            LeadSheetSimpleChordTerminalBarlineGeometry.usesTerminalBarlineAsTrailingRepeatBoundary(
                for: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let terminalTrailingRepeatLineX = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                after: terminalMeasure,
                in: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertEqual(
            terminalTrailingRepeatLineX,
            terminalFrame.midX,
            accuracy: 0.001
        )
        XCTAssertFalse(
            LeadSheetSimpleChordTerminalBarlineGeometry.shouldDrawStandaloneTerminalBarline(
                for: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertNil(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalFillerFrame(
                for: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
    }

    func testSimpleChordSheetMidRowRepeatDoesNotUseTerminalBarline() throws {
        var chart = Chart.blank(title: "Mid Row Repeat", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[2])
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let repeatEndMeasure = try XCTUnwrap(
            firstSystem.measures.first { $0.sourceMeasureID == measureIDs[2] }
        )
        let terminalCommittedMeasure = try XCTUnwrap(
            firstSystem.measures.first { $0.sourceMeasureID == measureIDs[3] }
        )
        let trailingMarker = try XCTUnwrap(
            repeatEndMeasure.repeatMarkerLayouts.first { $0.edge == .trailing }
        )

        XCTAssertEqual(trailingMarker.roadmapObjectID, repeatID)
        XCTAssertNil(
            terminalCommittedMeasure.repeatMarkerLayouts.first { $0.edge == .trailing }
        )
        XCTAssertFalse(
            LeadSheetSimpleChordTerminalBarlineGeometry.usesTerminalBarlineAsTrailingRepeatBoundary(
                for: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertNil(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                after: repeatEndMeasure,
                in: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
    }

    func testSimpleChordSheetTerminalRepeatTreatsTinyTrailingSpacerAsTerminalPadding() throws {
        let repeatMeasureID = UUID()
        let spacerMeasureID = UUID()
        let repeatID = UUID()
        let repeatStaffFrame = CGRect(x: 120, y: 220, width: 320, height: 84)
        let spacerStaffFrame = CGRect(x: 442, y: 220, width: 20, height: 84)
        let repeatMeasure = LeadSheetMeasureLayout(
            id: repeatMeasureID,
            sourceMeasureID: repeatMeasureID,
            chordInkTargetMeasureID: repeatMeasureID,
            index: 1,
            frame: repeatStaffFrame.insetBy(dx: -2, dy: -12),
            staffFrame: repeatStaffFrame,
            chordBandFrame: repeatStaffFrame,
            writableFrame: repeatStaffFrame.insetBy(dx: 2, dy: 2),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [
                LeadSheetRepeatMarkerLayout(
                    roadmapObjectID: repeatID,
                    edge: .trailing,
                    frame: CGRect(x: repeatStaffFrame.maxX - 4, y: repeatStaffFrame.minY, width: 8, height: repeatStaffFrame.height)
                )
            ],
            cueTextLayouts: [],
            leadingBarline: .single,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: repeatStaffFrame.maxX, y: repeatStaffFrame.minY, width: 1.6, height: repeatStaffFrame.height),
            isOpen: false
        )
        let spacerMeasure = LeadSheetMeasureLayout(
            id: spacerMeasureID,
            sourceMeasureID: nil,
            chordInkTargetMeasureID: nil,
            index: 2,
            frame: spacerStaffFrame.insetBy(dx: -2, dy: -12),
            staffFrame: spacerStaffFrame,
            chordBandFrame: spacerStaffFrame,
            writableFrame: spacerStaffFrame.insetBy(dx: 2, dy: 2),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: nil,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: spacerStaffFrame.maxX, y: spacerStaffFrame.minY, width: 1.6, height: spacerStaffFrame.height),
            isOpen: true
        )
        let system = LeadSheetSystemLayout(
            id: UUID(),
            index: 1,
            frame: CGRect(x: 118, y: 208, width: 344, height: 108),
            staffLineYPositions: [],
            clefFrame: nil,
            keySignatureLayouts: [],
            keyTextFrame: nil,
            keyText: nil,
            timeSignatureFrame: nil,
            sectionTextFrame: nil,
            sectionText: nil,
            roadmapTextFrame: nil,
            roadmapText: nil,
            roadmapMarkerLayouts: [],
            endingLayouts: [],
            measures: [repeatMeasure, spacerMeasure]
        )
        let paperFrame = CGRect(x: 80, y: 120, width: 400, height: 700)
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: .simpleChordSheet
            )
        )

        XCTAssertGreaterThan(terminalFrame.midX, repeatMeasure.trailingBarlineFrame.midX)
        XCTAssertEqual(
            try XCTUnwrap(
                LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                    after: repeatMeasure,
                    in: system,
                    paperFrame: paperFrame,
                    layoutStyle: .simpleChordSheet
                )
            ),
            terminalFrame.midX,
            accuracy: 0.001
        )
        XCTAssertNil(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                after: spacerMeasure,
                in: system,
                paperFrame: paperFrame,
                layoutStyle: .simpleChordSheet
            )
        )
        XCTAssertFalse(
            LeadSheetSimpleChordTerminalBarlineGeometry.shouldDrawStandaloneTerminalBarline(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: .simpleChordSheet
            )
        )
    }

    func testSimpleChordSheetTerminalRepeatDoesNotConsumeTerminalAcrossCommittedBlankMeasure() throws {
        let repeatMeasureID = UUID()
        let blankMeasureID = UUID()
        let repeatID = UUID()
        let repeatStaffFrame = CGRect(x: 120, y: 220, width: 280, height: 84)
        let blankStaffFrame = CGRect(x: 400, y: 220, width: 120, height: 84)
        let repeatMeasure = LeadSheetMeasureLayout(
            id: repeatMeasureID,
            sourceMeasureID: repeatMeasureID,
            chordInkTargetMeasureID: repeatMeasureID,
            index: 1,
            frame: repeatStaffFrame.insetBy(dx: -2, dy: -12),
            staffFrame: repeatStaffFrame,
            chordBandFrame: repeatStaffFrame,
            writableFrame: repeatStaffFrame.insetBy(dx: 2, dy: 2),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [
                LeadSheetRepeatMarkerLayout(
                    roadmapObjectID: repeatID,
                    edge: .trailing,
                    frame: CGRect(x: repeatStaffFrame.maxX - 4, y: repeatStaffFrame.minY, width: 8, height: repeatStaffFrame.height)
                )
            ],
            cueTextLayouts: [],
            leadingBarline: .single,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: repeatStaffFrame.maxX, y: repeatStaffFrame.minY, width: 1.6, height: repeatStaffFrame.height),
            isOpen: false
        )
        let blankMeasure = LeadSheetMeasureLayout(
            id: blankMeasureID,
            sourceMeasureID: blankMeasureID,
            chordInkTargetMeasureID: blankMeasureID,
            index: 2,
            frame: blankStaffFrame.insetBy(dx: -2, dy: -12),
            staffFrame: blankStaffFrame,
            chordBandFrame: blankStaffFrame,
            writableFrame: blankStaffFrame.insetBy(dx: 2, dy: 2),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: nil,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: blankStaffFrame.maxX, y: blankStaffFrame.minY, width: 1.6, height: blankStaffFrame.height),
            isOpen: false
        )
        let system = LeadSheetSystemLayout(
            id: UUID(),
            index: 1,
            frame: CGRect(x: 118, y: 208, width: 402, height: 108),
            staffLineYPositions: [],
            clefFrame: nil,
            keySignatureLayouts: [],
            keyTextFrame: nil,
            keyText: nil,
            timeSignatureFrame: nil,
            sectionTextFrame: nil,
            sectionText: nil,
            roadmapTextFrame: nil,
            roadmapText: nil,
            roadmapMarkerLayouts: [],
            endingLayouts: [],
            measures: [repeatMeasure, blankMeasure]
        )
        let paperFrame = CGRect(x: 80, y: 120, width: 620, height: 700)
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: .simpleChordSheet
            )
        )

        XCTAssertGreaterThan(terminalFrame.midX, blankMeasure.trailingBarlineFrame.midX)
        XCTAssertNil(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                after: repeatMeasure,
                in: system,
                paperFrame: paperFrame,
                layoutStyle: .simpleChordSheet
            )
        )

        let repeatBoundary = LeadSheetSimpleChordTerminalBarlineGeometry.renderedBoundary(
            after: repeatMeasure,
            before: blankMeasure,
            excludingRepeatMarkerIDs: [],
            in: system,
            paperFrame: paperFrame,
            layoutStyle: .simpleChordSheet
        )
        guard case .repeatBoundary(_, let terminalTrailingLineX) = repeatBoundary else {
            return XCTFail("Expected repeat boundary before committed blank measure.")
        }
        XCTAssertNil(terminalTrailingLineX)

        let blankBoundary = LeadSheetSimpleChordTerminalBarlineGeometry.renderedBoundary(
            after: blankMeasure,
            before: nil,
            excludingRepeatMarkerIDs: [],
            in: system,
            paperFrame: paperFrame,
            layoutStyle: .simpleChordSheet
        )
        guard case .normalBarline(_, let barlineFrame) = blankBoundary else {
            return XCTFail("Expected committed blank measure to keep its terminal barline.")
        }
        XCTAssertEqual(barlineFrame, terminalFrame)
    }

    func testSimpleChordSheetTerminalRepeatIgnoresTrailingOpenAuthoringLane() throws {
        var chart = Chart.draft(title: "Terminal Repeat Open Lane", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Terminal Repeat Open Lane",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 5
        )
        let measureIDs = chart.measures.map(\.id)
        XCTAssertEqual(chart.measures.map(\.authoringState), [
            .committed,
            .committed,
            .committed,
            .committed,
            .open
        ])
        let repeatID = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3])
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let repeatEndMeasure = try XCTUnwrap(
            firstSystem.measures.first { $0.sourceMeasureID == measureIDs[3] }
        )
        let openMeasure = try XCTUnwrap(
            firstSystem.measures.first { $0.sourceMeasureID == measureIDs[4] }
        )
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let trailingMarker = try XCTUnwrap(
            repeatEndMeasure.repeatMarkerLayouts.first { $0.edge == .trailing }
        )
        let terminalTrailingRepeatLineX = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                after: repeatEndMeasure,
                in: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )

        XCTAssertTrue(openMeasure.isOpen)
        XCTAssertGreaterThan(terminalFrame.midX, trailingMarker.frame.midX)
        XCTAssertEqual(trailingMarker.roadmapObjectID, repeatID)
        XCTAssertEqual(terminalTrailingRepeatLineX, terminalFrame.midX, accuracy: 0.001)
        XCTAssertNil(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                after: openMeasure,
                in: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertFalse(
            LeadSheetSimpleChordTerminalBarlineGeometry.shouldDrawStandaloneTerminalBarline(
                for: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertNil(
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalFillerFrame(
                for: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
    }

    func testChordToolLayoutAddsOpenContinuationLanesWithoutChangingDefaultEngraving() throws {
        var chart = Chart.draft(title: "Open Chord Lanes", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Chord Lanes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageSize = CGSize(width: 900, height: 1400)

        let defaultLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let chordToolLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )

        XCTAssertEqual(defaultLayout.systems.count, 1)
        XCTAssertGreaterThan(chordToolLayout.systems.count, defaultLayout.systems.count)
        XCTAssertEqual(chordToolLayout.systems.first?.measures.first?.sourceMeasureID, openMeasureID)

        let continuationMeasure = try XCTUnwrap(chordToolLayout.systems.dropFirst().first?.measures.first)
        XCTAssertNil(continuationMeasure.sourceMeasureID)
        XCTAssertEqual(continuationMeasure.chordInkTargetMeasureID, openMeasureID)
        XCTAssertTrue(continuationMeasure.isOpen)
        XCTAssertFalse(
            LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(
                after: continuationMeasure,
                before: nil
            )
        )

        let inputFrames = LeadSheetActiveInkScope.chordWritingInputFrames(for: chordToolLayout)
        XCTAssertEqual(inputFrames.count, chordToolLayout.systems.count)
        XCTAssertGreaterThan(inputFrames.last?.minY ?? 0, inputFrames.first?.maxY ?? 0)
    }
    #endif

    func testFineChordVisualMovesPreserveMusicInkAndMeasureGeometryAfterReopenForBothStyles() throws {
        let pageSize = CGSize(width: 900, height: 1_400)
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for chordCount in [1, 3] {
                var original = Chart.blank(title: "Fine Chord Placement", measureCount: 4, layoutStyle: style)
                original.setEngravingPreset(.compact)
                let measureID = try XCTUnwrap(original.measures.first?.id)
                for measure in original.measures {
                    _ = original.setMeasureManualLayoutWidth(128, for: measure.id)
                }
                if style == .rhythmSectionSheet {
                    XCTAssertTrue(original.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
                }
                for (index, text) in ["B7", "G△7", "A-9"].prefix(chordCount).enumerated() {
                    try appendChord(text, to: measureID, in: &original, atFraction: Double(index) / 4)
                }
                let chordIndex = chordCount == 1 ? 0 : 1
                let chordID = original.systems[0].measures[0].chordEvents[chordIndex].id
                let sourceInk = Data([0x49, 0x4E, 0x4B, 0x01])
                original.systems[0].measures[0].chordEvents[chordIndex].sourceInkData = sourceInk
                original.pageHandwrittenChordData = sourceInk
                original.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
                original.systems[0].measures[0].handwrittenRhythmicNotationData = sourceInk
                original.systems[0].measures[0].handwrittenRhythmicNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 128, height: 72)
                let baseline = LeadSheetPageLayoutEngine.pageLayout(for: original, pageSize: pageSize)
                let baselineMeasure = try XCTUnwrap(baseline.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let originalChord = try XCTUnwrap(baselineMeasure.chordLayouts.first { $0.id == chordID })
                let offsets: [CGFloat] = chordCount == 1 ? [0.2, 1.25] : [-1.25, -0.2, 0.2, 1.25]
                for offset in offsets {
                    var chart = original
                    let targetX = originalChord.frame.minX + offset
                    let visualFraction = Double((targetX - baselineMeasure.chordBandFrame.minX) / baselineMeasure.chordBandFrame.width)
                    XCTAssertTrue(chart.moveChordEventInCommittedChordLane(
                        chordID, to: measureID, atFraction: 0.9999,
                        visualFraction: visualFraction, preserveMusicalPlacement: true
                    ))
                    var expected = original
                    expected.systems[0].measures[0].chordEvents[chordIndex].manualVisualLaneFraction = visualFraction
                    expected.updatedAt = chart.updatedAt
                    XCTAssertEqual(chart, expected, "Fine dragging must change only the visual field and timestamp")
                    let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
                    XCTAssertEqual(reopened.chordEvent(id: chordID)?.sourceInkData, sourceInk)
                    XCTAssertEqual(reopened.pageHandwrittenChordData, sourceInk)
                    XCTAssertEqual(reopened.measure(id: measureID)?.handwrittenRhythmicNotationData, sourceInk)
                    XCTAssertEqual(reopened.measure(id: measureID)?.chordEvents.map(\.id), original.measure(id: measureID)?.chordEvents.map(\.id))
                    let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
                    XCTAssertEqual(layout.systems.flatMap(\.measures).map(\.frame), baseline.systems.flatMap(\.measures).map(\.frame))
                    let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                    XCTAssertEqual(measure.staffFrame, baselineMeasure.staffFrame)
                    XCTAssertEqual(measure.noteLayouts.map(\.noteheadFrame), baselineMeasure.noteLayouts.map(\.noteheadFrame))
                    let moved = try XCTUnwrap(measure.chordLayouts.first { $0.id == chordID })
                    XCTAssertTrue(moved.usesManualVisualPlacement)
                    XCTAssertEqual(moved.frame.minX, targetX, accuracy: 0.001, "\(style), \(offset)pt")
                    XCTAssertEqual(moved.fitFrame.minX, targetX, accuracy: 0.001)
                    XCTAssertEqual(moved.snapGuideTarget.x, targetX, accuracy: 0.001)
                    XCTAssertGreaterThan(moved.frame.width, 0)
                    XCTAssertEqual(moved.frame.size, moved.naturalFrame.size)
                    XCTAssertEqual(moved.renderFontSize, moved.baseFontSize)
                }
            }
        }
    }

    func testUserChordCompressionChangesOnlyWidthWithoutChangingHeightFontMusicInkOrNeighbours() throws {
        let pageSize = CGSize(width: 900, height: 1_400)
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for font in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var original = Chart.blank(title: "Manual Chord Scale", measureCount: 4, layoutStyle: style)
                original.setMatchedFontFamily(font)
                let measureID = try XCTUnwrap(original.measures.first?.id)
                if style == .rhythmSectionSheet {
                    XCTAssertTrue(original.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
                }
                for (index, text) in ["Bbmaj7(#11)/D", "G7", "D-7"].enumerated() {
                    try appendChord(text, to: measureID, in: &original, atFraction: Double(index) / 4)
                }
                let chordID = original.systems[0].measures[0].chordEvents[1].id
                XCTAssertTrue(original.moveChordEventInCommittedChordLane(
                    chordID, to: measureID, atFraction: nil,
                    visualFraction: 0.4, preserveMusicalPlacement: true
                ))
                let sourceInk = Data([0x49, 0x4E, 0x4B, 0x69])
                original.systems[0].measures[0].chordEvents[1].sourceInkData = sourceInk
                original.pageHandwrittenChordData = sourceInk
                original.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
                original.systems[0].measures[0].handwrittenRhythmicNotationData = sourceInk
                original.systems[0].measures[0].handwrittenRhythmicNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 128, height: 72)
                let originalLayout = LeadSheetPageLayoutEngine.pageLayout(for: original, pageSize: pageSize)
                let originalMeasure = try XCTUnwrap(originalLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let unscaled = try XCTUnwrap(originalMeasure.chordLayouts.first { $0.id == chordID })
                for scale in [0.35, 0.5, 0.8, 1.0] {
                    var chart = original
                    XCTAssertEqual(chart.setChordEventManualHorizontalScale(scale, for: chordID), scale)
                    var expected = original
                    expected.systems[0].measures[0].chordEvents[1].manualHorizontalScale = scale
                    expected.updatedAt = chart.updatedAt
                    XCTAssertEqual(chart, expected, "Sizing may change only the authored scale and timestamp")
                    let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
                    XCTAssertEqual(reopened, chart)
                    let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
                    XCTAssertEqual(layout.systems.map(\.frame), originalLayout.systems.map(\.frame))
                    XCTAssertEqual(layout.systems.flatMap(\.measures).map(\.frame), originalLayout.systems.flatMap(\.measures).map(\.frame))
                    let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                    XCTAssertEqual(measure.staffFrame, originalMeasure.staffFrame)
                    XCTAssertEqual(measure.noteLayouts.map(\.noteheadFrame), originalMeasure.noteLayouts.map(\.noteheadFrame))
                    let resized = try XCTUnwrap(measure.chordLayouts.first { $0.id == chordID })
                    XCTAssertEqual(resized.naturalFrame, unscaled.naturalFrame)
                    XCTAssertEqual(resized.frame.minX, unscaled.frame.minX, accuracy: 0.001)
                    XCTAssertEqual(resized.frame.midY, unscaled.frame.midY, accuracy: 0.001)
                    XCTAssertEqual(resized.frame.width, unscaled.naturalFrame.width * CGFloat(scale), accuracy: 0.001)
                    XCTAssertEqual(resized.frame.height, unscaled.naturalFrame.height, accuracy: 0.001)
                    XCTAssertEqual(resized.renderFontSize, resized.baseFontSize)
                    XCTAssertEqual(resized.fitFrame, resized.frame)
                    XCTAssertEqual(resized.horizontalCompressionScale, CGFloat(scale))
                    XCTAssertTrue(resized.usesManualHorizontalScale)
                    XCTAssertFalse(resized.usesManualDisplayScale)
                    for neighbour in measure.chordLayouts where neighbour.id != chordID {
                        XCTAssertEqual(neighbour, try XCTUnwrap(originalMeasure.chordLayouts.first { $0.id == neighbour.id }))
                    }
                }
            }
        }
    }

    func testResetChordWidthRestoresNaturalSizeAndPreservesPlacementMusicInkAndGeometryAfterReopen() throws {
        func normalizingGeneratedLayoutIDs(
            _ layout: LeadSheetPageLayout,
            to reference: LeadSheetPageLayout
        ) -> LeadSheetPageLayout {
            var normalized = layout
            var systemIDs: [UUID: UUID] = [:]
            XCTAssertEqual(normalized.systems.count, reference.systems.count)
            for systemIndex in normalized.systems.indices where reference.systems.indices.contains(systemIndex) {
                systemIDs[normalized.systems[systemIndex].id] = reference.systems[systemIndex].id
                normalized.systems[systemIndex].id = reference.systems[systemIndex].id
                XCTAssertEqual(normalized.systems[systemIndex].measures.count, reference.systems[systemIndex].measures.count)
                for measureIndex in normalized.systems[systemIndex].measures.indices
                    where reference.systems[systemIndex].measures.indices.contains(measureIndex) {
                    let referenceMeasure = reference.systems[systemIndex].measures[measureIndex]
                    // Real measure/chord IDs remain exact. Only continuation
                    // measures and these fixtures' derived rhythm-map/rest
                    // note layouts receive a fresh ID on every layout pass.
                    if normalized.systems[systemIndex].measures[measureIndex].sourceMeasureID == nil {
                        normalized.systems[systemIndex].measures[measureIndex].id = referenceMeasure.id
                    }
                    XCTAssertEqual(normalized.systems[systemIndex].measures[measureIndex].noteLayouts.count, referenceMeasure.noteLayouts.count)
                    for noteIndex in normalized.systems[systemIndex].measures[measureIndex].noteLayouts.indices
                        where referenceMeasure.noteLayouts.indices.contains(noteIndex) {
                        normalized.systems[systemIndex].measures[measureIndex].noteLayouts[noteIndex].id = referenceMeasure.noteLayouts[noteIndex].id
                    }
                }
            }
            for pageIndex in normalized.pages.indices {
                normalized.pages[pageIndex].systemIDs = normalized.pages[pageIndex].systemIDs.map { systemIDs[$0] ?? $0 }
            }
            return normalized
        }

        let pageSize = CGSize(width: 900, height: 1_400)
        let sizingOverrides: [(horizontal: Double?, width: Double?, legacyScale: Double?)] = [
            (0.55, nil, nil),
            (1, nil, nil),
            (nil, 24, nil),
            (nil, nil, 0.45),
            (nil, 132, 2),
            (0.6, 18, 3)
        ]
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for font in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var naturalChart = Chart.blank(title: "Reset Chord Width", measureCount: 8, layoutStyle: style)
                naturalChart.setMatchedFontFamily(font)
                let measureID = try XCTUnwrap(naturalChart.measures.first?.id)
                if style == .rhythmSectionSheet {
                    XCTAssertTrue(naturalChart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
                }
                for (index, text) in ["G7", "Bbmaj7(#11)/D", "D-7"].enumerated() {
                    try appendChord(text, to: measureID, in: &naturalChart, atFraction: Double(index) / 4)
                }
                let chordID = naturalChart.systems[0].measures[0].chordEvents[1].id
                XCTAssertTrue(naturalChart.moveChordEventInCommittedChordLane(
                    chordID, to: measureID, atFraction: nil,
                    visualFraction: 0.41234567, preserveMusicalPlacement: true
                ))
                naturalChart.systems[0].measures[0].chordEvents[1].tieOut = true
                naturalChart.systems[0].measures[0].chordEvents[1].hitStyle = .accent
                naturalChart.systems[0].measures[0].chordEvents[1].sourceCandidateSignature = ["Bbmaj7(#11)/D"]
                naturalChart.systems[0].measures[0].chordEvents[1].sourceRecognitionPipelineVersion = "reset-width-fixture"
                let sourceInk = Data([0x49, 0x4E, 0x4B, 0x52])
                naturalChart.systems[0].measures[0].chordEvents[1].sourceInkData = sourceInk
                naturalChart.pageHandwrittenChordData = sourceInk
                naturalChart.systems[0].measures[0].handwrittenRhythmicNotationData = sourceInk
                naturalChart.systems[0].measures[0].handwrittenRhythmicNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 128, height: 72)
                let naturalLayout = LeadSheetPageLayoutEngine.pageLayout(for: naturalChart, pageSize: pageSize)
                let naturalMeasure = try XCTUnwrap(naturalLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let naturalChord = try XCTUnwrap(naturalMeasure.chordLayouts.first { $0.id == chordID })
                naturalChart.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(
                    width: 900, height: 1_400,
                    measureAnchors: [try XCTUnwrap(PersistentInkMeasureAnchor(measureID: measureID, frame: naturalMeasure.frame))],
                    chordAnchors: [try XCTUnwrap(PersistentInkChordAnchor(
                        measureID: measureID, chordID: chordID,
                        frame: naturalChord.frame, registrationPoint: naturalChord.snapGuideTarget
                    ))]
                )

                for sizing in sizingOverrides {
                    var chart = naturalChart
                    chart.systems[0].measures[0].chordEvents[1].manualHorizontalScale = sizing.horizontal
                    chart.systems[0].measures[0].chordEvents[1].manualDisplayWidth = sizing.width
                    chart.systems[0].measures[0].chordEvents[1].manualDisplayScale = sizing.legacyScale
                    let beforeReset = chart
                    let beforeLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                    let beforeChord = try XCTUnwrap(beforeLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == chordID })
                    XCTAssertEqual(chart, beforeReset, "Reading legacy sizing must preserve the stored overrides")
                    XCTAssertTrue(EditorChordWidthAdjustmentPolicy.canResetWidth(of: try XCTUnwrap(chart.chordEvent(id: chordID))))
                    XCTAssertTrue(EditorChordWidthAdjustmentPolicy.resetWidth(for: chordID, in: &chart))
                    var expected = naturalChart
                    expected.updatedAt = chart.updatedAt
                    XCTAssertEqual(chart, expected, "Reset may clear sizing fields and update the timestamp only")
                    let resetEvent = try XCTUnwrap(chart.chordEvent(id: chordID))
                    XCTAssertNil(resetEvent.manualHorizontalScale)
                    XCTAssertNil(resetEvent.manualDisplayWidth)
                    XCTAssertNil(resetEvent.manualDisplayScale)
                    XCTAssertEqual(resetEvent.manualVisualLaneFraction, 0.41234567)
                    XCTAssertFalse(EditorChordWidthAdjustmentPolicy.canResetWidth(of: resetEvent))

                    let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
                    XCTAssertEqual(reopened, chart)
                    let resetLayout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
                    XCTAssertEqual(normalizingGeneratedLayoutIDs(resetLayout, to: naturalLayout), naturalLayout)
                    let resetChord = try XCTUnwrap(resetLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == chordID })
                    XCTAssertEqual(resetChord.frame, resetChord.naturalFrame)
                    XCTAssertEqual(resetChord.horizontalCompressionScale, 1)
                    XCTAssertEqual(resetChord.frame.minX, beforeChord.frame.minX, accuracy: 0.001)
                    XCTAssertEqual(resetChord.frame.midY, beforeChord.frame.midY, accuracy: 0.001)
                    XCTAssertEqual(resetChord.frame.height, beforeChord.frame.height, accuracy: 0.001)
                    XCTAssertEqual(resetChord.renderFontSize, beforeChord.renderFontSize)
                    XCTAssertTrue(resetChord.usesManualVisualPlacement)
                    XCTAssertFalse(resetChord.usesManualHorizontalScale)
                    XCTAssertFalse(resetChord.usesManualDisplayWidth)
                    XCTAssertFalse(resetChord.usesManualDisplayScale)
                    var expectedLayout = beforeLayout
                    for systemIndex in expectedLayout.systems.indices {
                        for measureIndex in expectedLayout.systems[systemIndex].measures.indices {
                            let chordIndex = expectedLayout.systems[systemIndex].measures[measureIndex].chordLayouts.firstIndex { $0.id == chordID }
                            if let chordIndex {
                                expectedLayout.systems[systemIndex].measures[measureIndex].chordLayouts[chordIndex] = resetChord
                            }
                        }
                    }
                    XCTAssertEqual(normalizingGeneratedLayoutIDs(resetLayout, to: expectedLayout), expectedLayout, "Every neighboring chord, measure, staff, writing lane, and page must remain fixed")
                    let afterReset = chart
                    XCTAssertFalse(EditorChordWidthAdjustmentPolicy.resetWidth(for: chordID, in: &chart))
                    XCTAssertEqual(chart, afterReset, "A second reset must not change the timestamp")
                }
            }
        }
    }

    func testResetChordWidthWithoutOverrideOrForUnknownChordDoesNotMutateChart() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "No Width Override", measureCount: 4, layoutStyle: style)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            try appendChord("C7", to: measureID, in: &chart, atFraction: 0)
            let chord = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
            let original = chart
            XCTAssertFalse(EditorChordWidthAdjustmentPolicy.canResetWidth(of: chord))
            XCTAssertFalse(EditorChordWidthAdjustmentPolicy.resetWidth(for: chord.id, in: &chart))
            XCTAssertEqual(chart, original)
            XCTAssertFalse(EditorChordWidthAdjustmentPolicy.resetWidth(for: UUID(), in: &chart))
            XCTAssertEqual(chart, original)
        }
    }

    func testResetLegacyChordWidthWithoutFinePlacementKeepsVisibleLeftEdgeAfterReopen() throws {
        let pageSize = CGSize(width: 760, height: 1_400)
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for font in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var chart = Chart.blank(title: "Reset Legacy Chord Width", measureCount: 4, layoutStyle: style)
                chart.setMatchedFontFamily(font)
                let measureID = try XCTUnwrap(chart.measures.first?.id)
                if style == .rhythmSectionSheet {
                    XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
                }
                for (text, fraction) in zip(["G7", "Bbmaj7(#11)/D", "D-7"], [0.0, 0.5, 0.75]) {
                    try appendChord(text, to: measureID, in: &chart, atFraction: fraction)
                }
                let chordID = chart.systems[0].measures[0].chordEvents[1].id
                XCTAssertEqual(chart.setChordEventManualDisplayWidth(24, for: chordID), 24)
                let sourceInk = Data([0x49, 0x4E, 0x4B, 0x4C])
                chart.systems[0].measures[0].chordEvents[1].sourceInkData = sourceInk
                chart.pageHandwrittenChordData = sourceInk
                chart.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 760, height: 1_400)
                let original = chart
                let beforeLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                let beforeMeasure = try XCTUnwrap(beforeLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let beforeChord = try XCTUnwrap(beforeMeasure.chordLayouts.first { $0.id == chordID })
                XCTAssertNil(chart.chordEvent(id: chordID)?.manualVisualLaneFraction)

                XCTAssertTrue(EditorChordWidthAdjustmentPolicy.resetWidth(for: chordID, in: &chart, pageSize: pageSize))
                var expected = original
                expected.systems[0].measures[0].chordEvents[1].manualDisplayWidth = nil
                if style == .rhythmSectionSheet {
                    expected.systems[0].measures[0].chordEvents[1].manualVisualLaneFraction = Double(
                        (beforeChord.frame.minX - beforeMeasure.chordBandFrame.minX) / beforeMeasure.chordBandFrame.width
                    )
                }
                expected.updatedAt = chart.updatedAt
                XCTAssertEqual(chart, expected, "Legacy reset may clear width, freeze the Rhythm left edge, and update the timestamp only")
                let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
                XCTAssertEqual(reopened, chart)
                XCTAssertEqual(reopened.chordEvent(id: chordID)?.sourceInkData, sourceInk)
                XCTAssertEqual(reopened.pageHandwrittenChordData, sourceInk)
                XCTAssertEqual(reopened.pageHandwrittenChordCoordinateSpace, original.pageHandwrittenChordCoordinateSpace)
                let resetLayout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
                let resetMeasure = try XCTUnwrap(resetLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let resetChord = try XCTUnwrap(resetMeasure.chordLayouts.first { $0.id == chordID })
                XCTAssertEqual(resetChord.frame.minX, beforeChord.frame.minX, accuracy: 0.001)
                XCTAssertEqual(resetChord.frame.midY, beforeChord.frame.midY, accuracy: 0.001)
                XCTAssertEqual(resetChord.frame.height, beforeChord.frame.height, accuracy: 0.001)
                XCTAssertEqual(resetChord.renderFontSize, beforeChord.renderFontSize)
                XCTAssertEqual(resetChord.frame, resetChord.naturalFrame)
                XCTAssertEqual(resetChord.horizontalCompressionScale, 1)
                XCTAssertFalse(resetChord.usesManualDisplayWidth)
                XCTAssertEqual(resetMeasure.frame, beforeMeasure.frame)
                XCTAssertEqual(resetMeasure.staffFrame, beforeMeasure.staffFrame)
                for neighbor in resetMeasure.chordLayouts where neighbor.id != chordID {
                    XCTAssertEqual(neighbor, try XCTUnwrap(beforeMeasure.chordLayouts.first { $0.id == neighbor.id }))
                }
            }
        }
    }

    func testCrowdedChordAnchorsNeverAutomaticallyChangeTextSizeInEitherStyle() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "No Automatic Chord Size", measureCount: 4, layoutStyle: style)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            for (index, text) in ["Bbmaj7(#11)/D", "Eb/G", "F-7", "Db7(#11)/F#"].enumerated() {
                try appendChord(text, to: measureID, in: &chart, atFraction: Double(index) / 4)
            }
            let ids = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.map(\.id))
            for id in ids {
                XCTAssertTrue(chart.moveChordEventInCommittedChordLane(
                    id, to: measureID, atFraction: nil,
                    visualFraction: 0.7, preserveMusicalPlacement: true
                ))
            }
            let stored = chart
            let baseline = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 760, height: 1_400))
            let baselineMeasure = try XCTUnwrap(baseline.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
            let expectedSize = style == .simpleChordSheet
                ? ChartTypographyResolver.simpleChordPrimaryFontSize
                : ChartTypographyResolver.structuredChordPrimaryFontSize
            for chord in baselineMeasure.chordLayouts {
                XCTAssertEqual(chord.renderFontSize, expectedSize)
                XCTAssertEqual(chord.frame.size, chord.naturalFrame.size)
                XCTAssertEqual(chord.fitFrame, chord.frame)
                XCTAssertEqual(chord.frame.minX, baselineMeasure.chordBandFrame.minX + baselineMeasure.chordBandFrame.width * 0.7, accuracy: 0.001)
            }
            XCTAssertEqual(chart, stored, "Layout is read-only, even when all labels share one authored anchor")
            XCTAssertEqual(chart.setChordEventManualHorizontalScale(0.5, for: ids[0]), 0.5)
            let resized = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 760, height: 1_400))
            let resizedMeasure = try XCTUnwrap(resized.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
            for chord in resizedMeasure.chordLayouts {
                let old = try XCTUnwrap(baselineMeasure.chordLayouts.first { $0.id == chord.id })
                if chord.id == ids[0] {
                    XCTAssertEqual(chord.renderFontSize, expectedSize)
                    XCTAssertEqual(chord.frame.width, old.frame.width * 0.5, accuracy: 0.001)
                    XCTAssertEqual(chord.frame.height, old.frame.height, accuracy: 0.001)
                } else {
                    XCTAssertEqual(chord, old)
                }
            }
        }
    }

    func testEveryChordResizeIncludingLegacyWidthConversionLeavesOtherChordAnchorsUntouched() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for resizedIndex in 0..<3 {
                var original = Chart.blank(title: "Independent Size Edits", measureCount: 4, layoutStyle: style)
                let measureID = try XCTUnwrap(original.measures.first?.id)
                for (index, text) in ["Bbmaj7(#11)/D", "G7", "D-7"].enumerated() {
                    try appendChord(text, to: measureID, in: &original, atFraction: Double(index) / 4)
                }
                let ids = try XCTUnwrap(original.measure(id: measureID)?.chordEvents.map(\.id))
                for legacyWidth in [Double?.none, 24, 132, 360] {
                    var baselineChart = original
                    _ = baselineChart.setChordEventManualDisplayWidth(legacyWidth, for: ids[resizedIndex])
                    let pageSize = CGSize(width: 760, height: 1_400)
                    let baseline = LeadSheetPageLayoutEngine.pageLayout(for: baselineChart, pageSize: pageSize)
                    let baselineMeasure = try XCTUnwrap(baseline.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                    let selected = try XCTUnwrap(baselineMeasure.chordLayouts.first { $0.id == ids[resizedIndex] })
                    for scale in [0.35, 0.7, 1.0] {
                        var chart = baselineChart
                        let visualFraction = Double((selected.frame.minX - baselineMeasure.chordBandFrame.minX) / baselineMeasure.chordBandFrame.width)
                        XCTAssertTrue(chart.moveChordEventInCommittedChordLane(
                            ids[resizedIndex], to: measureID, atFraction: nil,
                            visualFraction: visualFraction, preserveMusicalPlacement: true
                        ))
                        XCTAssertEqual(chart.setChordEventManualHorizontalScale(scale, for: ids[resizedIndex]), scale)
                        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                        let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                        XCTAssertEqual(measure.frame, baselineMeasure.frame)
                        XCTAssertEqual(measure.staffFrame, baselineMeasure.staffFrame)
                        for chord in measure.chordLayouts {
                            let old = try XCTUnwrap(baselineMeasure.chordLayouts.first { $0.id == chord.id })
                            if chord.id == selected.id {
                                XCTAssertEqual(chord.frame.minX, old.frame.minX, accuracy: 0.001)
                                XCTAssertEqual(chord.frame.midY, old.frame.midY, accuracy: 0.001)
                                XCTAssertEqual(chord.frame.width, chord.naturalFrame.width * CGFloat(scale), accuracy: 0.001)
                                XCTAssertEqual(chord.frame.height, old.frame.height, accuracy: 0.001)
                                XCTAssertEqual(chord.renderFontSize, old.renderFontSize)
                            } else {
                                XCTAssertEqual(chord, old, "\(style), chord \(resizedIndex), legacy width \(String(describing: legacyWidth)), scale \(scale)")
                            }
                        }
                        XCTAssertEqual(chart.measure(id: measureID)?.chordEvents.map(\.startPosition), baselineChart.measure(id: measureID)?.chordEvents.map(\.startPosition))
                        XCTAssertNil(chart.chordEvent(id: ids[resizedIndex])?.manualDisplayWidth)
                        XCTAssertNil(chart.chordEvent(id: ids[resizedIndex])?.manualDisplayScale)
                    }
                }
            }
        }
    }

    func testManualChordHorizontalScaleIsOptionalCodableBoundedAndReplacesLegacySizingOnlyAfterAnExplicitEdit() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Legacy Manual Sizing", measureCount: 1, layoutStyle: style)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            try appendChord("C7", to: measureID, in: &chart, atFraction: 0)
            let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
            let plain = try XCTUnwrap(chart.chordEvent(id: chordID))
            let plainObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
            XCTAssertNil(plainObject["manualHorizontalScale"])
            XCTAssertNil(try JSONDecoder().decode(ChordEvent.self, from: JSONEncoder().encode(plain)).manualHorizontalScale)
            for width in [24.0, 132.0, 360.0] {
                XCTAssertEqual(chart.setChordEventManualDisplayWidth(width, for: chordID), width)
                let saved = try JSONEncoder().encode(chart)
                let reopened = try JSONDecoder().decode(Chart.self, from: saved)
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: CGSize(width: 900, height: 1_400))
                let chord = try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == chordID })
                let horizontalScale = CGFloat(ChordEvent.clampedManualHorizontalScale(width / Double(chord.naturalFrame.width)))
                XCTAssertEqual(chord.frame.width, chord.naturalFrame.width * horizontalScale, accuracy: 0.001)
                XCTAssertEqual(chord.frame.height, chord.naturalFrame.height)
                XCTAssertEqual(chord.renderFontSize, chord.baseFontSize)
                XCTAssertEqual(chord.horizontalCompressionScale, horizontalScale)
                XCTAssertEqual(reopened.chordEvent(id: chordID)?.manualDisplayWidth, width)
                XCTAssertNil(reopened.chordEvent(id: chordID)?.manualDisplayScale)
                XCTAssertNil(reopened.chordEvent(id: chordID)?.manualHorizontalScale)
                XCTAssertEqual(reopened, chart, "Legacy sizing is interpreted without rewriting chart data")
            }
            // Existing build-69 proportional values are parked in saved data;
            // their horizontal interpretation must never scale chord height.
            for oldScale in [0.1, 0.7, 1.4, 32.0] {
                chart.systems[0].measures[0].chordEvents[0].manualDisplayScale = oldScale
                let saved = try JSONEncoder().encode(chart)
                let reopened = try JSONDecoder().decode(Chart.self, from: saved)
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: CGSize(width: 900, height: 1_400))
                let chord = try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == chordID })
                let horizontalScale = CGFloat(ChordEvent.clampedManualHorizontalScale(oldScale))
                XCTAssertEqual(chord.frame.width, chord.naturalFrame.width * horizontalScale, accuracy: 0.001)
                XCTAssertEqual(chord.frame.height, chord.naturalFrame.height)
                XCTAssertEqual(chord.renderFontSize, chord.baseFontSize)
                XCTAssertEqual(chord.horizontalCompressionScale, horizontalScale)
                XCTAssertEqual(reopened, chart)
                XCTAssertEqual(reopened.chordEvent(id: chordID)?.manualDisplayScale, oldScale)
                XCTAssertEqual(reopened.chordEvent(id: chordID)?.manualDisplayWidth, 360)
                XCTAssertNil(reopened.chordEvent(id: chordID)?.manualHorizontalScale)
            }
            let beforeEdit = chart
            XCTAssertEqual(chart.setChordEventManualHorizontalScale(0.6, for: chordID), 0.6)
            var expected = beforeEdit
            expected.systems[0].measures[0].chordEvents[0].manualDisplayWidth = nil
            expected.systems[0].measures[0].chordEvents[0].manualDisplayScale = nil
            expected.systems[0].measures[0].chordEvents[0].manualHorizontalScale = 0.6
            expected.updatedAt = chart.updatedAt
            XCTAssertEqual(chart, expected)
            XCTAssertNil(chart.chordEvent(id: chordID)?.manualDisplayWidth)
            XCTAssertNil(chart.chordEvent(id: chordID)?.manualDisplayScale)
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
            XCTAssertEqual(reopened.chordEvent(id: chordID)?.manualHorizontalScale, 0.6)
            XCTAssertEqual(chart.setChordEventManualHorizontalScale(0, for: chordID), ChordEvent.minimumManualHorizontalScale)
            XCTAssertEqual(chart.setChordEventManualHorizontalScale(100, for: chordID), ChordEvent.maximumManualHorizontalScale)
            XCTAssertEqual(chart.setChordEventManualHorizontalScale(.nan, for: chordID), 1)
            XCTAssertEqual(chart.setChordEventManualHorizontalScale(.infinity, for: chordID), 1)
            XCTAssertNil(chart.setChordEventManualHorizontalScale(nil, for: chordID))
            XCTAssertNil(chart.chordEvent(id: chordID)?.manualHorizontalScale)
            let resetLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_400))
            let reset = try XCTUnwrap(resetLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == chordID })
            XCTAssertEqual(reset.frame, reset.naturalFrame)
            XCTAssertEqual(reset.horizontalCompressionScale, 1)
        }
    }

    func testExplicitChordHorizontalCompressionTakesPriorityWithoutMigratingOtherSavedSizing() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Width Compression Priority", measureCount: 1, layoutStyle: style)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            try appendChord("Bbmaj7(#11)/D", to: measureID, in: &chart, atFraction: 0.5)
            let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
            chart.systems[0].measures[0].chordEvents[0].manualDisplayWidth = 18
            chart.systems[0].measures[0].chordEvents[0].manualDisplayScale = 3
            chart.systems[0].measures[0].chordEvents[0].manualHorizontalScale = 0.6
            let before = chart
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: CGSize(width: 900, height: 1_400))
            let chord = try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == chordID })
            XCTAssertEqual(chord.horizontalCompressionScale, 0.6)
            XCTAssertEqual(chord.frame.width, chord.naturalFrame.width * 0.6, accuracy: 0.001)
            XCTAssertEqual(chord.frame.height, chord.naturalFrame.height)
            XCTAssertEqual(chord.renderFontSize, chord.baseFontSize)
            XCTAssertTrue(chord.usesManualHorizontalScale)
            XCTAssertEqual(reopened, before, "Interpreting saved fields must not migrate any chart data")
        }
    }

    func testChordHorizontalCompressionInitializationAndDecodeEnforceFixedBounds() throws {
        var chart = Chart.blank(title: "Width Compression Bounds", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("D7", to: measureID, in: &chart, atFraction: 0)
        let original = try XCTUnwrap(chart.measures.first?.chordEvents.first)
        let encoded = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (requested, expected) in [(-10.0, 0.35), (0.0, 0.35), (0.35, 0.35), (0.8, 0.8), (1.0, 1.0), (8.0, 1.0)] {
            var withScale = object
            withScale["manualHorizontalScale"] = requested
            let decoded = try JSONDecoder().decode(ChordEvent.self, from: JSONSerialization.data(withJSONObject: withScale))
            XCTAssertEqual(decoded.manualHorizontalScale, expected)
            let initialized = ChordEvent(
                id: original.id, symbol: original.symbol,
                startPosition: original.startPosition, duration: original.duration,
                rhythmPlacement: original.rhythmPlacement, tieOut: original.tieOut,
                hitStyle: original.hitStyle, rawInput: original.rawInput,
                manualHorizontalScale: requested
            )
            XCTAssertEqual(initialized.manualHorizontalScale, expected)
        }
        XCTAssertEqual(ChordEvent.clampedManualHorizontalScale(.nan), 1)
        XCTAssertEqual(ChordEvent.clampedManualHorizontalScale(.infinity), 1)
        XCTAssertEqual(ChordEvent.clampedManualHorizontalScale(-.infinity), 1)
    }

    func testManualVisualChordFractionIsOptionalCodableAndLegacyJSONRemainsUnchanged() throws {
        var chart = Chart.blank(title: "Legacy Visual Placement", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("B7", to: measureID, in: &chart, atFraction: 0)
        let event = try XCTUnwrap(chart.measures.first?.chordEvents.first)
        let legacyData = try JSONEncoder().encode(event)
        let legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        XCTAssertNil(legacyObject["manualVisualLaneFraction"])
        let decodedLegacy = try JSONDecoder().decode(ChordEvent.self, from: legacyData)
        XCTAssertNil(decodedLegacy.manualVisualLaneFraction)
        XCTAssertEqual(decodedLegacy, event)
        let legacyReencoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decodedLegacy)) as? [String: Any])
        XCTAssertEqual(legacyReencoded as NSDictionary, legacyObject as NSDictionary)

        var positioned = event
        positioned.manualVisualLaneFraction = 0.41234567
        let positionedData = try JSONEncoder().encode(positioned)
        var positionedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: positionedData) as? [String: Any])
        XCTAssertEqual(positionedObject.removeValue(forKey: "manualVisualLaneFraction") as? Double, 0.41234567)
        XCTAssertEqual(positionedObject as NSDictionary, legacyObject as NSDictionary)
        XCTAssertEqual(try JSONDecoder().decode(ChordEvent.self, from: positionedData), positioned)
        for (fraction, expected) in [(-1.0, 0.0), (2.0, 0.9999)] {
            var object = legacyObject
            object["manualVisualLaneFraction"] = fraction
            let decoded = try JSONDecoder().decode(ChordEvent.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(try XCTUnwrap(decoded.manualVisualLaneFraction), expected, accuracy: 0.000001)
        }
    }

    func testMusicalAndCrossMeasureChordMovesReplaceOrClearPriorVisualOverride() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Visual and Musical Move", measureCount: 2, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            if style == .rhythmSectionSheet {
                for id in ids { XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: id)) }
            }
            try appendChord("C7", to: ids[0], in: &chart, atFraction: 0)
            let chordID = try XCTUnwrap(chart.measures.first?.chordEvents.first?.id)
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: ids[0], atFraction: 0, visualFraction: 0.1234, preserveMusicalPlacement: true))
            let originalPosition = try XCTUnwrap(chart.chordEvent(id: chordID)?.startPosition)
            XCTAssertTrue(chart.moveChordEvent(chordID, to: ids[0], atFraction: 0.75))
            XCTAssertNil(chart.chordEvent(id: chordID)?.manualVisualLaneFraction)
            XCTAssertNotEqual(chart.chordEvent(id: chordID)?.startPosition, originalPosition)
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: ids[0], atFraction: 0.25, visualFraction: 0.321))
            XCTAssertEqual(chart.chordEvent(id: chordID)?.manualVisualLaneFraction, 0.321)
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: ids[1], atFraction: 0.5, visualFraction: 0.456, preserveMusicalPlacement: true))
            XCTAssertEqual(chart.measureContainingChordEvent(id: chordID)?.id, ids[1])
            XCTAssertEqual(chart.chordEvent(id: chordID)?.manualVisualLaneFraction, 0.456)
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: ids[1], atFraction: 0.75))
            XCTAssertNil(chart.chordEvent(id: chordID)?.manualVisualLaneFraction)
        }
    }

    func testFineChordVisualPlacementKeepsChosenSizeAndIdenticalAuthoredAnchorsFinite() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var original = Chart.blank(title: "Fine Neighbour Fitting", measureCount: 4, layoutStyle: style)
            let measureID = try XCTUnwrap(original.measures.first?.id)
            try appendChord("Db7(#11)/F#", to: measureID, in: &original, atFraction: 0)
            try appendChord("B7", to: measureID, in: &original, atFraction: 0.5)
            let ids = try XCTUnwrap(original.measure(id: measureID)?.chordEvents.map(\.id))
            let pageSize = CGSize(width: 900, height: 1_400)
            let baseline = LeadSheetPageLayoutEngine.pageLayout(for: original, pageSize: pageSize)
            for rightFraction in [0.401, 0.4] {
                var chart = original
                XCTAssertTrue(chart.moveChordEventInCommittedChordLane(ids[0], to: measureID, atFraction: 0, visualFraction: 0.4, preserveMusicalPlacement: true))
                XCTAssertTrue(chart.moveChordEventInCommittedChordLane(ids[1], to: measureID, atFraction: 0.5, visualFraction: rightFraction, preserveMusicalPlacement: true))
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                XCTAssertEqual(layout.systems.flatMap(\.measures).map(\.frame), baseline.systems.flatMap(\.measures).map(\.frame))
                let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let left = try XCTUnwrap(measure.chordLayouts.first { $0.id == ids[0] })
                let right = try XCTUnwrap(measure.chordLayouts.first { $0.id == ids[1] })
                XCTAssertEqual(left.frame.minX, measure.chordBandFrame.minX + measure.chordBandFrame.width * 0.4, accuracy: 0.001)
                XCTAssertEqual(right.frame.minX, measure.chordBandFrame.minX + measure.chordBandFrame.width * CGFloat(rightFraction), accuracy: 0.001)
                for chord in [left, right] {
                    XCTAssertTrue(chord.frame.width.isFinite)
                    XCTAssertGreaterThan(chord.frame.width, 0)
                    XCTAssertEqual(chord.frame.size, chord.naturalFrame.size)
                    XCTAssertEqual(chord.renderFontSize, chord.baseFontSize)
                }
                if rightFraction > 0.4 {
                    XCTAssertGreaterThan(left.frame.maxX, right.frame.minX, "A close authored anchor must not silently shrink its neighbour")
                } else {
                    // Coincident authored anchors cannot be made readable
                    // without violating one user's exact chosen position.
                    XCTAssertEqual(left.frame.minX, right.frame.minX, accuracy: 0.001)
                }
            }
        }
    }

    func testFineChordVisualPlacementRespectsRepeatMeterAndMeasureBounds() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Fine Chord Safe Bounds", measureCount: 3, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[1], endMeasureID: ids[2]))
            _ = try XCTUnwrap(chart.applyMeterChange(Meter(numerator: 3, denominator: 4), after: ids[0], scope: .toEndOfPiece))
            try appendChord("C7", to: ids[1], in: &chart, atFraction: 0)
            let chordID = try XCTUnwrap(chart.measure(id: ids[1])?.chordEvents.first?.id)
            for fraction in [0.0, 0.9999] {
                XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: ids[1], atFraction: 0, visualFraction: fraction, preserveMusicalPlacement: true))
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_400))
                let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == ids[1] })
                let guideFrame = LeadSheetChordPlacementGuidePolicy.guideFrame(for: measure, referenceFrame: measure.chordBandFrame)
                let chord = try XCTUnwrap(measure.chordLayouts.first)
                XCTAssertGreaterThanOrEqual(chord.frame.minX, guideFrame.minX - 0.001)
                XCTAssertLessThan(chord.frame.minX, measure.chordBandFrame.maxX)
                XCTAssertEqual(chord.frame.size, chord.naturalFrame.size)
                XCTAssertEqual(chord.renderFontSize, chord.baseFontSize)
                XCTAssertTrue(chord.frame.width.isFinite)
                XCTAssertEqual(chord.frame.minX, fraction == 0 ? guideFrame.minX : measure.chordBandFrame.maxX - 1, accuracy: 0.001)
            }
        }
    }

    func testSimpleChordSheetCommittedLoneChordMoveRendersOnNearestBeatGuide() throws {
        var chart = Chart.draft(title: "Open Lane Move", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Lane Move",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("C"),
                rawInput: "C",
                to: measureID,
                atFraction: 0.05
            )
        )

        XCTAssertTrue(
            chart.moveChordEventInCommittedChordLane(
                chordID,
                to: measureID,
                atFraction: 0.86
            )
        )

        let movedLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let movedMeasure = try XCTUnwrap(movedLayout.systems.first?.measures.first)
        let movedChord = try XCTUnwrap(movedMeasure.chordLayouts.first)
        let movedEvent = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        let guideXs = try simpleChordPlacementGuideXs(for: movedMeasure, in: chart)
        let lastGuideX = try XCTUnwrap(guideXs.last)

        XCTAssertEqual(movedChord.fitFrame.minX, lastGuideX, accuracy: 0.001)
        XCTAssertEqual(movedChord.frame.minX, lastGuideX, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(movedEvent.manualLaneFraction), 0.86, accuracy: 0.0001)
        XCTAssertGreaterThan(movedEvent.startPosition.subdivisionsPerBeat, 2)
        XCTAssertLessThanOrEqual(movedChord.frame.maxX, movedMeasure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetInitiallyRecognizedLoneChordStillUsesFirstNormalizedSlot() throws {
        var chart = Chart.draft(title: "Initial Lone Chord", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Initial Lone Chord",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("C"),
                rawInput: "C",
                to: measureID,
                atFraction: 0.86
            )
        )
        _ = chart.setChordEventManualLaneFraction(0.86, for: chordID)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chord = try XCTUnwrap(measure.chordLayouts.first)
        let event = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
        let firstGuideX = try XCTUnwrap(
            try simpleChordPlacementGuideXs(for: measure, in: chart).first
        )

        XCTAssertEqual(event.startPosition.subdivisionsPerBeat, 1)
        XCTAssertEqual(chord.fitFrame.minX, firstGuideX, accuracy: 0.001)
        XCTAssertEqual(chord.frame.minX, firstGuideX, accuracy: 0.001)
    }

    func testSimpleChordSheetThirdChordMovedToBeatFourStaysThereAfterSaveAndReopen() throws {
        var chart = Chart.blank(title: "Three Chord Drag", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("C", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("F", to: measureID, in: &chart, atFraction: 0.30)
        try appendChord("G", to: measureID, in: &chart, atFraction: 0.55)
        let thirdChordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.last?.id)

        XCTAssertTrue(
            chart.moveChordEventInCommittedChordLane(
                thirdChordID,
                to: measureID,
                atFraction: 0.9999
            )
        )

        let savedData = try JSONEncoder().encode(chart)
        let reopenedChart = try JSONDecoder().decode(Chart.self, from: savedData)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: reopenedChart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = measure.chordLayouts
        let guideXs = try simpleChordPlacementGuideXs(for: measure, in: reopenedChart)
        let reopenedThirdChord = try XCTUnwrap(reopenedChart.chordEvent(id: thirdChordID))

        XCTAssertEqual(chordLayouts.map(\.text), ["C", "F", "G"])
        XCTAssertEqual(chordLayouts[0].fitFrame.minX, guideXs[0], accuracy: 0.001)
        XCTAssertGreaterThan(chordLayouts[1].fitFrame.minX, chordLayouts[0].fitFrame.minX)
        XCTAssertLessThan(chordLayouts[1].fitFrame.minX, guideXs[3])
        XCTAssertEqual(chordLayouts[2].fitFrame.minX, guideXs[3], accuracy: 0.001)
        XCTAssertEqual(chordLayouts[2].frame.minX, guideXs[3], accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(reopenedThirdChord.manualLaneFraction), 0.9999, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(chordLayouts[2].frame.maxX, measure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetManualChordPlacementRendersSingleChordAtNearestBoundedEdge() throws {
        var leftChart = Chart.blank(title: "Tight Left", measureCount: 1, layoutStyle: .simpleChordSheet)
        let leftMeasureID = try XCTUnwrap(leftChart.measures.first?.id)
        let leftChordID = try XCTUnwrap(
            leftChart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("Bb-7"),
                rawInput: "Bb-7",
                to: leftMeasureID,
                atFraction: 0.1
            )
        )
        XCTAssertTrue(
            leftChart.moveChordEventInCommittedChordLane(
                leftChordID,
                to: leftMeasureID,
                atFraction: 0
            )
        )

        let leftLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: leftChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let leftMeasure = try XCTUnwrap(leftLayout.systems.first?.measures.first)
        let leftChord = try XCTUnwrap(leftMeasure.chordLayouts.first)
        let leftGuideX = try XCTUnwrap(simpleChordPlacementGuideXs(for: leftMeasure, in: leftChart).first)
        let leftEvent = try XCTUnwrap(leftChart.measure(id: leftMeasureID)?.chordEvents.first)

        XCTAssertEqual(leftChord.frame.minX, leftGuideX, accuracy: 0.001)
        XCTAssertEqual(leftChord.fitFrame.minX, leftGuideX, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(leftEvent.manualLaneFraction), 0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(leftChord.frame.minX, leftMeasure.frame.minX)

        var rightChart = Chart.blank(title: "Tight Right", measureCount: 1, layoutStyle: .simpleChordSheet)
        let rightMeasureID = try XCTUnwrap(rightChart.measures.first?.id)
        let rightChordID = try XCTUnwrap(
            rightChart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("A7sus"),
                rawInput: "A7sus",
                to: rightMeasureID,
                atFraction: 0.1
            )
        )
        XCTAssertTrue(
            rightChart.moveChordEventInCommittedChordLane(
                rightChordID,
                to: rightMeasureID,
                atFraction: 0.9999
            )
        )

        let rightLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: rightChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let rightMeasure = try XCTUnwrap(rightLayout.systems.first?.measures.first)
        let rightChord = try XCTUnwrap(rightMeasure.chordLayouts.first)
        let rightFirstGuideX = try XCTUnwrap(simpleChordPlacementGuideXs(for: rightMeasure, in: rightChart).first)
        let rightEvent = try XCTUnwrap(rightChart.measure(id: rightMeasureID)?.chordEvents.first)

        XCTAssertGreaterThan(rightChord.frame.minX, rightFirstGuideX)
        XCTAssertEqual(rightChord.frame.size, rightChord.naturalFrame.size)
        XCTAssertEqual(rightChord.fitFrame, rightChord.frame)
        XCTAssertEqual(try XCTUnwrap(rightEvent.manualLaneFraction), 0.9999, accuracy: 0.0001)
        XCTAssertLessThan(rightChord.frame.minX, rightMeasure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetSingleChordUsesFirstPlacementSlotAndNaturalTextBox() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("C", to: measureID, in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayout = try XCTUnwrap(firstMeasure.chordLayouts.first)
        let firstGuideX = try XCTUnwrap(simpleChordPlacementGuideXs(for: firstMeasure, in: chart).first)

        XCTAssertEqual(chordLayout.fitFrame.minX, firstGuideX, accuracy: 0.001)
        XCTAssertEqual(chordLayout.fitFrame, chordLayout.frame)
        XCTAssertEqual(chordLayout.frame, chordLayout.naturalFrame)
        XCTAssertEqual(chordLayout.renderFontSize, ChartTypographyResolver.simpleChordPrimaryFontSize)
        XCTAssertEqual(chordLayout.snapGuideTarget.x, chordLayout.fitFrame.minX, accuracy: 0.001)
        XCTAssertLessThanOrEqual(chordLayout.frame.maxX, firstMeasure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetSingleLongChordKeepsConfiguredSizeAndTightVisibleFrame() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 4, layoutStyle: .simpleChordSheet)
        let emptyChart = chart
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Bb△7", to: measureID, in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayout = try XCTUnwrap(firstMeasure.chordLayouts.first)
        let firstGuideX = try XCTUnwrap(simpleChordPlacementGuideXs(for: firstMeasure, in: chart).first)

        XCTAssertEqual(chordLayout.fitFrame.minX, firstGuideX, accuracy: 0.001)
        XCTAssertEqual(chordLayout.fitFrame, chordLayout.frame)
        XCTAssertEqual(chordLayout.frame, chordLayout.naturalFrame)
        XCTAssertEqual(chordLayout.renderFontSize, ChartTypographyResolver.simpleChordPrimaryFontSize)
        #if canImport(UIKit)
        let chosenSize = LeadSheetNotationRenderer(chart: chart).chordRenderSize(
            for: chordLayout,
            primaryFontSize: ChartTypographyResolver.simpleChordPrimaryFontSize
        )
        XCTAssertEqual(chordLayout.frame.width, chosenSize.width, accuracy: 0.001)
        XCTAssertEqual(chordLayout.frame.height, chosenSize.height, accuracy: 0.001)
        #endif
        let emptyLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: emptyChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        XCTAssertEqual(layout.systems.flatMap(\.measures).map(\.frame), emptyLayout.systems.flatMap(\.measures).map(\.frame))
        XCTAssertEqual(layout.systems.flatMap(\.measures).map(\.staffFrame), emptyLayout.systems.flatMap(\.measures).map(\.staffFrame))
        XCTAssertGreaterThan(chordLayout.frame.width, CGFloat(40))
    }

    func testSimpleChordSheetLegacyManualWidthIsBoundedHorizontalCompressionAtTheDefaultHeight() throws {
        var wideChart = Chart.blank(title: "Simple Chord Width", measureCount: 1, layoutStyle: .simpleChordSheet)
        let wideMeasureID = try XCTUnwrap(wideChart.measures.first?.id)
        try appendChord("Cmaj7", to: wideMeasureID, in: &wideChart, atFraction: 0.05)
        let wideChordID = try XCTUnwrap(wideChart.measure(id: wideMeasureID)?.chordEvents.first?.id)
        _ = wideChart.setChordEventManualDisplayWidth(132, for: wideChordID)

        let wideLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: wideChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let wideChordLayout = try XCTUnwrap(wideLayout.systems.first?.measures.first?.chordLayouts.first)

        var narrowChart = Chart.blank(title: "Simple Chord Width", measureCount: 1, layoutStyle: .simpleChordSheet)
        let narrowMeasureID = try XCTUnwrap(narrowChart.measures.first?.id)
        try appendChord("Cmaj7", to: narrowMeasureID, in: &narrowChart, atFraction: 0.05)
        let narrowChordID = try XCTUnwrap(narrowChart.measure(id: narrowMeasureID)?.chordEvents.first?.id)
        _ = narrowChart.setChordEventManualDisplayWidth(24, for: narrowChordID)

        let narrowLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: narrowChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let narrowChordLayout = try XCTUnwrap(narrowLayout.systems.first?.measures.first?.chordLayouts.first)

        let wideScale = CGFloat(ChordEvent.clampedManualHorizontalScale(132 / Double(wideChordLayout.naturalFrame.width)))
        let narrowScale = CGFloat(ChordEvent.clampedManualHorizontalScale(24 / Double(narrowChordLayout.naturalFrame.width)))
        XCTAssertEqual(wideChordLayout.frame.width, wideChordLayout.naturalFrame.width * wideScale, accuracy: 0.001)
        XCTAssertEqual(narrowChordLayout.frame.width, narrowChordLayout.naturalFrame.width * narrowScale, accuracy: 0.001)
        XCTAssertEqual(wideChordLayout.frame.height, wideChordLayout.naturalFrame.height)
        XCTAssertEqual(narrowChordLayout.frame.height, narrowChordLayout.naturalFrame.height)
        XCTAssertEqual(wideChordLayout.renderFontSize, wideChordLayout.baseFontSize)
        XCTAssertEqual(narrowChordLayout.renderFontSize, narrowChordLayout.baseFontSize)
        XCTAssertEqual(narrowChart.chordEvent(id: narrowChordID)?.manualDisplayWidth, 24)
        XCTAssertGreaterThan(wideChordLayout.frame.width, narrowChordLayout.frame.width)
        XCTAssertEqual(wideChordLayout.frame.minX, narrowChordLayout.frame.minX, accuracy: 0.001)
    }

    func testRhythmSectionManualChordDisplayWidthSurvivesLayoutAndReopen() throws {
        var chart = Chart.blank(title: "Rhythm Chord Width", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Cmaj7", to: measureID, in: &chart, atFraction: 0.50)
        let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
        XCTAssertEqual(chart.setChordEventManualDisplayWidth(96, for: chordID), 96)

        let savedData = try JSONEncoder().encode(chart)
        let reopenedChart = try JSONDecoder().decode(Chart.self, from: savedData)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: reopenedChart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayout = try XCTUnwrap(measure.chordLayouts.first)
        let reopenedChord = try XCTUnwrap(reopenedChart.chordEvent(id: chordID))

        let horizontalScale = CGFloat(ChordEvent.clampedManualHorizontalScale(96 / Double(chordLayout.naturalFrame.width)))
        XCTAssertEqual(chordLayout.frame.width, chordLayout.naturalFrame.width * horizontalScale, accuracy: 0.001)
        XCTAssertEqual(chordLayout.fitFrame.width, chordLayout.frame.width)
        XCTAssertEqual(chordLayout.frame.height, chordLayout.naturalFrame.height)
        XCTAssertEqual(chordLayout.renderFontSize, chordLayout.baseFontSize)
        XCTAssertEqual(try XCTUnwrap(reopenedChord.manualDisplayWidth), 96, accuracy: 0.001)
        XCTAssertLessThanOrEqual(chordLayout.frame.maxX, measure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetMultipleChordsKeepGuideStartsAndNaturalTextBoxes() throws {
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
        let guideXs = try simpleChordPlacementGuideXs(for: firstMeasure, in: chart)
        let firstGuideX = try XCTUnwrap(guideXs.first)
        let midpointGuideX = try XCTUnwrap(guideXs.dropFirst(2).first)
        XCTAssertEqual(chordLayouts[0].fitFrame.minX, firstGuideX, accuracy: 0.001)
        XCTAssertEqual(chordLayouts[1].fitFrame.minX, midpointGuideX, accuracy: 0.001)
        for chordLayout in chordLayouts {
            XCTAssertEqual(chordLayout.fitFrame, chordLayout.frame)
            XCTAssertEqual(chordLayout.frame, chordLayout.naturalFrame)
            XCTAssertEqual(chordLayout.renderFontSize, ChartTypographyResolver.simpleChordPrimaryFontSize)
        }
    }

    func testSimpleChordSheetRenderedChordsUsePlacementGuideSlots() throws {
        var chart = Chart.blank(title: "Simple Chord Slots", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let chordTexts = ["C", "D", "E", "F"]

        for (index, text) in chordTexts.enumerated() {
            let chordID = try XCTUnwrap(
                chart.appendRecognizedChordEvent(
                    try ChordSymbolParser.parse(text),
                    rawInput: text,
                    to: measureID,
                    atFraction: Double(index) / Double(chordTexts.count)
                )
            )
            _ = chart.setChordEventManualLaneFraction(Double(index) / Double(chordTexts.count), for: chordID)
        }

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = measure.chordLayouts
        let guideXs = try simpleChordPlacementGuideXs(for: measure, in: chart)

        XCTAssertEqual(chordLayouts.map(\.text), chordTexts)
        XCTAssertEqual(chordLayouts.count, guideXs.count)
        for (chordLayout, guideX) in zip(chordLayouts, guideXs) {
            XCTAssertEqual(chordLayout.fitFrame.minX, guideX, accuracy: 0.001)
            XCTAssertEqual(chordLayout.frame.minX, guideX, accuracy: 0.001)
        }
    }

    func testSimpleChordSheetOverflowChordsDistributeEvenlyFromFirstSlot() throws {
        var chart = Chart.blank(title: "Simple Chord Overflow Slots", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let chordTexts = ["C", "D", "E", "F", "G", "A"]

        for (index, text) in chordTexts.enumerated() {
            let fraction = Double(index) / Double(chordTexts.count)
            let chordID = try XCTUnwrap(
                chart.appendRecognizedChordEvent(
                    try ChordSymbolParser.parse(text),
                    rawInput: text,
                    to: measureID,
                    atFraction: fraction
                )
            )
            _ = chart.setChordEventManualLaneFraction(fraction, for: chordID)
        }

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1400, height: 1400)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = measure.chordLayouts
        let guideFrame = LeadSheetChordPlacementGuidePolicy.guideFrame(
            for: measure,
            referenceFrame: measure.chordBandFrame
        )
        let firstSlotX = try XCTUnwrap(simpleChordPlacementGuideXs(for: measure, in: chart).first)
        let expectedSpacing = (guideFrame.maxX - firstSlotX) / CGFloat(chordTexts.count)
        let expectedStarts = chordTexts.indices.map { index in
            firstSlotX + expectedSpacing * CGFloat(index)
        }

        XCTAssertEqual(chordLayouts.map(\.text), chordTexts)
        for (chordLayout, expectedStart) in zip(chordLayouts, expectedStarts) {
            XCTAssertEqual(chordLayout.fitFrame.minX, expectedStart, accuracy: 0.001)
            XCTAssertEqual(chordLayout.frame.minX, expectedStart, accuracy: 0.001)
        }
    }

    func testSimpleChordSheetSingleChordBeatSubdivisionsPreserveSavedPositionsWithoutMovingRenderSlot() throws {
        var chart = Chart.blank(title: "Simple Beat Placement", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        let targetFractions = [0.05, 0.26, 0.38, 0.51, 0.74, 0.86]
        let expectedPositions = ["1", "2", "2&", "3", "4", "4&"]

        for (measureID, fraction) in zip(measureIDs, targetFractions) {
            try appendChord("C", to: measureID, in: &chart, atFraction: 0.05)
            let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
            if fraction > 0.05 {
                XCTAssertTrue(chart.moveChordEvent(chordID, to: measureID, atFraction: fraction))
            }
        }

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let measures = Array(layout.systems.flatMap(\.measures).prefix(measureIDs.count))
        let chordLayouts = try measures.map { measure in
            try XCTUnwrap(measure.chordLayouts.first)
        }
        let savedPositions = try measureIDs.map { measureID in
            try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.startPosition.displayText)
        }

        XCTAssertEqual(savedPositions, expectedPositions)
        XCTAssertEqual(chordLayouts.map(\.text), Array(repeating: "C", count: measureIDs.count))

        for (measure, chordLayout) in zip(measures, chordLayouts) {
            let firstGuideX = try XCTUnwrap(simpleChordPlacementGuideXs(for: measure, in: chart).first)
            XCTAssertEqual(chordLayout.fitFrame.minX, firstGuideX, accuracy: 0.001)
            XCTAssertEqual(chordLayout.frame.minX, firstGuideX, accuracy: 0.001)
        }

        let lastMeasure = try XCTUnwrap(measures.last)
        let lastChord = try XCTUnwrap(chordLayouts.last)
        XCTAssertLessThan(lastChord.fitFrame.minX, lastMeasure.chordBandFrame.midX)
        XCTAssertLessThanOrEqual(lastChord.frame.maxX, lastMeasure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetLateSingleLongChordKeepsFirstRenderSlot() throws {
        var chart = Chart.blank(title: "Simple Late Chord Fit", measureCount: 3, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        let chordText = "Db7(#11)/F#"

        try appendChord(chordText, to: measureIDs[0], in: &chart, atFraction: 0.05)
        try appendChord(chordText, to: measureIDs[1], in: &chart, atFraction: 0.05)
        try appendChord(chordText, to: measureIDs[2], in: &chart, atFraction: 0.05)

        let lateFractions = [0.62, 0.86]
        for (measureID, fraction) in zip(measureIDs.dropFirst(), lateFractions) {
            let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
            XCTAssertTrue(chart.moveChordEvent(chordID, to: measureID, atFraction: fraction))
        }

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let chordLayouts = layout.systems
            .flatMap(\.measures)
            .prefix(3)
            .compactMap(\.chordLayouts.first)

        XCTAssertEqual(chordLayouts.map(\.text), Array(repeating: chordText, count: 3))
        let beatOneWidth = try XCTUnwrap(chordLayouts.first?.frame.width)
        let lateWidths = chordLayouts.dropFirst().map(\.frame.width)

        for width in lateWidths {
            XCTAssertGreaterThan(width, CGFloat(18))
        }

        for (measure, chordLayout) in zip(layout.systems.flatMap(\.measures).prefix(3), chordLayouts) {
            let firstGuideX = try XCTUnwrap(simpleChordPlacementGuideXs(for: measure, in: chart).first)
            XCTAssertEqual(chordLayout.fitFrame.minX, firstGuideX, accuracy: 0.001)
            XCTAssertEqual(chordLayout.frame.minX, firstGuideX, accuracy: 0.001)
        }
        XCTAssertEqual(chordLayouts[2].frame.width, beatOneWidth, accuracy: 0.001)
        XCTAssertLessThanOrEqual(chordLayouts[2].frame.maxX, layout.systems.flatMap(\.measures)[2].chordBandFrame.maxX)
    }

    func testSimpleChordSheetRendersOneTimeAppliedChordTransposition() throws {
        var chart = Chart.blank(title: "Simple Chord Transpose", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Bb△7", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("C-7", to: measureID, in: &chart, atFraction: 0.62)
        try appendChord("G/B", to: measureID, in: &chart, atFraction: 0.86)

        chart.setChordTranspositionSemitones(2)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)

        XCTAssertEqual(firstMeasure.chordLayouts.map(\.text), ["C△7", "D-7", "A/C#"])
        XCTAssertEqual(chart.measure(id: measureID)?.chordEvents.map(\.symbol.displayText), ["C△7", "D-7", "A/C#"])
        XCTAssertEqual(chart.chordTranspositionSemitones, 0)
        XCTAssertEqual(firstMeasure.chordLayouts.count, 3)
        XCTAssertTrue(firstMeasure.chordLayouts.allSatisfy { $0.horizontalCompressionScale == firstMeasure.chordLayouts[0].horizontalCompressionScale })
    }

    func testSimpleChordSheetTwoChordMeasureReflowsToBeatSegmentsWhenChordMoves() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 6, layoutStyle: .simpleChordSheet)
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
            pageSize: CGSize(width: 760, height: 1400)
        )
        let movedMeasure = try XCTUnwrap(movedLayout.systems.first?.measures.first)
        let movedChordLayouts = movedMeasure.chordLayouts

        XCTAssertEqual(movedChordLayouts.map(\.text), ["Bb△7", "C-7"])
        XCTAssertTrue(movedChordLayouts.allSatisfy { $0.horizontalCompressionScale == 1 })
        XCTAssertEqual(movedChordLayouts[0].frame.minX, movedChordLayouts[0].fitFrame.minX, accuracy: 0.001)
        XCTAssertEqual(movedChordLayouts[1].frame.minX, movedChordLayouts[1].fitFrame.minX, accuracy: 0.001)
        XCTAssertEqual(movedChordLayouts[0].frame.width, initialChordLayouts[0].frame.width, accuracy: 0.001)
        XCTAssertGreaterThan(movedChordLayouts[0].frame.width, 0)
        XCTAssertTrue(movedChordLayouts.allSatisfy { $0.renderFontSize == ChartTypographyResolver.simpleChordPrimaryFontSize })
    }

    func testSimpleChordSheetAdjacentLongChordsKeepConfiguredSizeWithoutAutomaticFitting() throws {
        var chart = Chart.blank(title: "Balanced Chord Collision", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let chordText = "Db7(#11)/F#"
        try appendChord(chordText, to: measureID, in: &chart, atFraction: 0.05)
        try appendChord(chordText, to: measureID, in: &chart, atFraction: 0.86)
        let secondChordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.last?.id)

        XCTAssertTrue(chart.moveChordEvent(secondChordID, to: measureID, atFraction: 0.38))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 760, height: 1400)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = measure.chordLayouts

        XCTAssertEqual(chordLayouts.map(\.text), [chordText, chordText])
        XCTAssertTrue(chordLayouts.allSatisfy { $0.frame == $0.naturalFrame && $0.renderFontSize == ChartTypographyResolver.simpleChordPrimaryFontSize })
        XCTAssertEqual(chordLayouts[1].frame.width, chordLayouts[0].frame.width, accuracy: 0.001)
        XCTAssertGreaterThan(chordLayouts.map(\.frame.width).min() ?? 0, 20)
        XCTAssertEqual(measure.frame.width, try XCTUnwrap(layout.systems.first?.measures.dropFirst().first?.frame.width), accuracy: 0.001)
        XCTAssertLessThan(chordLayouts[1].frame.minX, measure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetAdjacentUnevenChordsKeepNaturalWidthsWithoutAutomaticFitting() throws {
        var chart = Chart.blank(title: "Weighted Chord Collision", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Db7#11/F#", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("C-7", to: measureID, in: &chart, atFraction: 0.86)
        let secondChordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.last?.id)

        XCTAssertTrue(chart.moveChordEvent(secondChordID, to: measureID, atFraction: 0.26))

        let movedLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 760, height: 1400)
        )
        let movedMeasure = try XCTUnwrap(movedLayout.systems.first?.measures.first)
        let movedChordLayouts = movedMeasure.chordLayouts

        XCTAssertEqual(movedChordLayouts.map(\.text), ["Db7(#11)/F#", "C-7"])
        XCTAssertTrue(movedChordLayouts.allSatisfy { $0.frame == $0.naturalFrame && $0.renderFontSize == ChartTypographyResolver.simpleChordPrimaryFontSize })
        XCTAssertGreaterThan(movedChordLayouts[0].frame.width, movedChordLayouts[1].frame.width)
        XCTAssertGreaterThan(movedChordLayouts[1].frame.width, 10)
        XCTAssertEqual(movedMeasure.frame.width, try XCTUnwrap(movedLayout.systems.first?.measures.dropFirst().first?.frame.width), accuracy: 0.001)
    }

    func testSimpleChordSheetAdjacentShortChordsDoNotInflateMeasureLane() throws {
        var chart = Chart.blank(title: "Adjacent Short Chords", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("B-", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("C7", to: measureID, in: &chart, atFraction: 0.86)
        let secondChordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.last?.id)

        XCTAssertTrue(chart.moveChordEvent(secondChordID, to: measureID, atFraction: 0.13))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 760, height: 1400)
        )
        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let secondMeasure = try XCTUnwrap(firstSystem.measures.dropFirst().first)
        let chordLayouts = firstMeasure.chordLayouts
        let chordEvents = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents)

        XCTAssertEqual(chordEvents.map(\.startPosition.displayText), ["1", "1&"])
        XCTAssertEqual(chordLayouts.map(\.text), ["B-", "C7"])
        XCTAssertEqual(firstMeasure.frame.width, secondMeasure.frame.width, accuracy: 0.001)
        XCTAssertTrue(chordLayouts.allSatisfy { $0.frame == $0.naturalFrame && $0.renderFontSize == ChartTypographyResolver.simpleChordPrimaryFontSize })
        XCTAssertLessThanOrEqual(chordLayouts[1].frame.maxX, firstMeasure.chordBandFrame.maxX)
    }

    func testSimpleChordSheetChordFontsKeepConfiguredPointSizeAndMeasuredNaturalBounds() throws {
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

        for chordFont in [ChartFontFamilyPreset.finaleJazz, .museJazz, .finaleBroadway, .leland] {
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
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
            }
            XCTAssertTrue(measure.chordLayouts.allSatisfy { $0.frame == $0.naturalFrame && $0.renderFontSize == ChartTypographyResolver.simpleChordPrimaryFontSize })
        }
    }

    func testSimpleChordSheetThreeOrMoreChordsStayOnBeatAnchors() throws {
        var chart = Chart.blank(title: "Simple Chord Fit", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Bb△7", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("C-7", to: measureID, in: &chart, atFraction: 0.62)
        try appendChord("D7", to: measureID, in: &chart, atFraction: 0.86)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 760, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = firstMeasure.chordLayouts
        let chordEvents = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents)

        XCTAssertEqual(chordLayouts.map(\.text), ["Bb△7", "C-7", "D7"])
        XCTAssertEqual(chordEvents.map(\.startPosition.displayText), ["1", "3", "4"])
        XCTAssertTrue(chordLayouts.allSatisfy { $0.horizontalCompressionScale == 1 })

        for chordLayout in chordLayouts {
            XCTAssertEqual(chordLayout.frame.minX, chordLayout.fitFrame.minX, accuracy: 0.001)
            XCTAssertEqual(chordLayout.frame, chordLayout.naturalFrame)
            XCTAssertEqual(chordLayout.renderFontSize, ChartTypographyResolver.simpleChordPrimaryFontSize)
        }
        let lastChordID = try XCTUnwrap(chordEvents.last?.id)
        XCTAssertTrue(chart.moveChordEvent(lastChordID, to: measureID, atFraction: 0.38))

        let movedLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 760, height: 1400)
        )
        let movedMeasure = try XCTUnwrap(movedLayout.systems.first?.measures.first)
        let movedChordLayouts = movedMeasure.chordLayouts

        XCTAssertEqual(movedChordLayouts.count, 3)
        for chordLayout in movedChordLayouts {
            XCTAssertEqual(chordLayout.frame.minX, chordLayout.fitFrame.minX, accuracy: 0.001)
        }
    }

    func testSimpleChordSheetDenseSlashChordMeasureKeepsEvenMeasuresAndUserControlledTextSizes() throws {
        var chart = Chart.blank(title: "Be Blessed", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("Abmaj7", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("Eb/G", to: measureID, in: &chart, atFraction: 0.38)
        try appendChord("F-7", to: measureID, in: &chart, atFraction: 0.62)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 760, height: 1400)
        )

        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let secondMeasure = try XCTUnwrap(layout.systems.first?.measures.dropFirst().first)
        let chordLayouts = measure.chordLayouts

        XCTAssertEqual(chordLayouts.map(\.text), ["Ab△7", "Eb/G", "F-7"])
        XCTAssertEqual(chordLayouts.count, 3)
        XCTAssertEqual(measure.frame.width, secondMeasure.frame.width, accuracy: 0.001)
        XCTAssertTrue(chordLayouts.allSatisfy { $0.frame.minX >= measure.chordBandFrame.minX })
        XCTAssertTrue(chordLayouts.allSatisfy { $0.frame.minX < measure.chordBandFrame.maxX })
        XCTAssertTrue(chordLayouts.allSatisfy { $0.frame == $0.naturalFrame && $0.renderFontSize == ChartTypographyResolver.simpleChordPrimaryFontSize })
        XCTAssertGreaterThan(chordLayouts.map(\.frame.width).min() ?? 0, 0)

        let originalChart = chart
        let firstChordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first?.id)
        XCTAssertEqual(chart.setChordEventManualHorizontalScale(0.4, for: firstChordID), 0.4)
        let resizedLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 760, height: 1_400))
        let resizedMeasure = try XCTUnwrap(resizedLayout.systems.first?.measures.first)
        XCTAssertEqual(resizedMeasure.frame, measure.frame)
        XCTAssertEqual(resizedMeasure.chordLayouts[0].frame.width, chordLayouts[0].frame.width * 0.4, accuracy: 0.001)
        XCTAssertEqual(resizedMeasure.chordLayouts.dropFirst().map(\.frame), chordLayouts.dropFirst().map(\.frame))
        XCTAssertEqual(chart.measure(id: measureID)?.chordEvents.map(\.startPosition), originalChart.measure(id: measureID)?.chordEvents.map(\.startPosition))
    }

    func testSavedFourChordManualRowKeepsRequestedWidthsAndPreservesStoredGeometry() throws {
        var chart = Chart.blank(title: "Four Chord Saved Row", measureCount: 4, layoutStyle: .simpleChordSheet)
        chart.setMatchedFontFamily(.finaleBroadway)
        let measureIDs = chart.measures.map(\.id)
        let widths = [128.16774193548386, 128.16774193548386, 128.16774193548386, 108.29677419354839]
        for (measureID, width) in zip(measureIDs, widths) {
            _ = chart.setMeasureManualLayoutWidth(CGFloat(width), for: measureID)
        }
        let texts = ["B7", "G△7", "A-9", "D-7"]
        let fractions = [0.0744336569579288, 0.3065149136577708, 0.5044323078636984, 0.5376766091051806]
        for (text, fraction) in zip(texts, fractions) {
            let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse(text), rawInput: text, to: measureIDs[0], atFraction: fraction
            ))
            _ = chart.setChordEventManualLaneFraction(fraction, for: chordID)
        }
        let lastChordID = try XCTUnwrap(chart.measure(id: measureIDs[0])?.chordEvents.last?.id)
        _ = chart.setChordEventManualDisplayWidth(18, for: lastChordID)
        let savedPositions = [
            BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
            BeatPosition(beat: 2, subdivision: 14, subdivisionsPerBeat: 64),
            BeatPosition(beat: 3, subdivision: 0, subdivisionsPerBeat: 1),
            BeatPosition(beat: 3, subdivision: 10, subdivisionsPerBeat: 64)
        ]
        for index in savedPositions.indices {
            chart.systems[0].measures[0].chordEvents[index].startPosition = savedPositions[index]
        }
        let originalChart = chart
        var emptyChart = chart
        emptyChart.systems[0].measures[0].chordEvents = []
        var originalNormalizedSnaps: [CGFloat]?

        for pageWidth in [CGFloat(760), 900] {
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: pageWidth, height: 1_400))
            let system = try XCTUnwrap(layout.systems.first)
            let measure = try XCTUnwrap(system.measures.first)
            let neighbor = try XCTUnwrap(system.measures.dropFirst().first)
            let emptyLayout = LeadSheetPageLayoutEngine.pageLayout(for: emptyChart, pageSize: CGSize(width: pageWidth, height: 1_400))
            XCTAssertEqual(system.measures.map(\.frame), try XCTUnwrap(emptyLayout.systems.first).measures.map(\.frame))
            XCTAssertEqual(measure.frame.width, neighbor.frame.width, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(system.measures.last).frame.width / measure.frame.width, widths[3] / widths[0], accuracy: 0.001)
            let guideFrame = LeadSheetChordPlacementGuidePolicy.guideFrame(for: measure, referenceFrame: measure.chordBandFrame)
            let normalizedSnaps = measure.chordLayouts.map { ($0.snapGuideTarget.x - guideFrame.minX) / guideFrame.width }
            if let originalNormalizedSnaps {
                for (original, current) in zip(originalNormalizedSnaps, normalizedSnaps) {
                    XCTAssertEqual(current, original, accuracy: 0.001)
                }
            } else {
                originalNormalizedSnaps = normalizedSnaps
            }
            XCTAssertEqual(system.measures.compactMap(\.sourceMeasureID), measureIDs)
            XCTAssertEqual(measure.chordLayouts.map(\.text), texts)
            let legacyChord = try XCTUnwrap(measure.chordLayouts.last)
            let legacyScale = CGFloat(ChordEvent.clampedManualHorizontalScale(18 / Double(legacyChord.naturalFrame.width)))
            XCTAssertEqual(legacyChord.frame.width, legacyChord.naturalFrame.width * legacyScale, accuracy: 0.001)
            XCTAssertEqual(legacyChord.frame.height, legacyChord.naturalFrame.height)
            XCTAssertEqual(legacyChord.renderFontSize, legacyChord.baseFontSize)
            for chord in measure.chordLayouts {
                XCTAssertEqual(chord.frame.minX, chord.snapGuideTarget.x, accuracy: 0.001)
                XCTAssertEqual(chord.fitFrame.minX, chord.snapGuideTarget.x, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(chord.frame.minX, measure.chordBandFrame.minX)
                XCTAssertLessThan(chord.frame.minX, measure.chordBandFrame.maxX)
                if chord.id != lastChordID {
                    XCTAssertEqual(chord.frame, chord.naturalFrame)
                    XCTAssertEqual(chord.renderFontSize, ChartTypographyResolver.simpleChordPrimaryFontSize)
                }
            }
        }
        XCTAssertEqual(chart, originalChart)
        XCTAssertEqual(chart.measure(id: measureIDs[0])?.chordEvents.map(\.startPosition), savedPositions)
        XCTAssertEqual(chart.chordEvent(id: lastChordID)?.manualDisplayWidth, 18)
    }

    func testFourComplexChordMeasureNeverAutomaticallyShrinksOrWidensEitherSheetStyle() throws {
        let texts = ["Ab△7", "Eb/G", "F-7", "Db7(#11)/F#"]
        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Complex Four Chord Row", measureCount: 4, layoutStyle: layoutStyle)
            let emptyChart = chart
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            for (index, text) in texts.enumerated() {
                try appendChord(text, to: measureID, in: &chart, atFraction: Double(index) / 4)
            }
            for pageWidth in [CGFloat(760), 900] {
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: pageWidth, height: 1_400))
                let emptyLayout = LeadSheetPageLayoutEngine.pageLayout(for: emptyChart, pageSize: CGSize(width: pageWidth, height: 1_400))
                XCTAssertEqual(layout.systems.flatMap(\.measures).map(\.frame), emptyLayout.systems.flatMap(\.measures).map(\.frame))
                let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                XCTAssertEqual(measure.chordLayouts.map(\.text), texts)
                for chord in measure.chordLayouts {
                    XCTAssertGreaterThan(chord.frame.width, 0)
                    XCTAssertGreaterThanOrEqual(chord.frame.minX, measure.chordBandFrame.minX)
                    XCTAssertLessThan(chord.frame.minX, measure.chordBandFrame.maxX)
                    XCTAssertEqual(chord.frame, chord.naturalFrame)
                    XCTAssertEqual(chord.renderFontSize, chord.baseFontSize)
                }
            }
        }
    }

    func testRhythmSectionDenseChordTranspositionAndEqualWidthKeyChangeKeepGeometryStable() throws {
        var chart = Chart.blank(title: "Stable Dense Rhythm Geometry", key: .gMajor, measureCount: 8, layoutStyle: .rhythmSectionSheet)
        chart.setEngravingPreset(.compact)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
        for (index, text) in ["Db7(#11)/F#", "Bbmaj7", "F-7/C", "G7(b9)"].enumerated() {
            try appendChord(text, to: measureID, in: &chart, atFraction: Double(index) / 4)
        }

        for pageWidth in [CGFloat(760), 900] {
            let pageSize = CGSize(width: pageWidth, height: 1_400)
            let originalLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            let originalRows = originalLayout.systems.map { $0.measures.compactMap(\.sourceMeasureID) }
            let originalMeasures = Dictionary(uniqueKeysWithValues: originalLayout.systems.flatMap(\.measures).compactMap { measure in
                measure.sourceMeasureID.map { ($0, measure) }
            })
            let denseMeasure = try XCTUnwrap(originalMeasures[measureID])
            XCTAssertEqual(denseMeasure.chordLayouts.count, 4)
            XCTAssertEqual(denseMeasure.noteLayouts.count, 4)

            func assertStableGeometry(_ candidate: Chart, label: String) throws {
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: candidate, pageSize: pageSize)
                XCTAssertEqual(layout.systems.map { $0.measures.compactMap(\.sourceMeasureID) }, originalRows, label)
                for measure in layout.systems.flatMap(\.measures) {
                    guard let measureID = measure.sourceMeasureID else { continue }
                    let original = try XCTUnwrap(originalMeasures[measureID])
                    XCTAssertEqual(measure.frame, original.frame, label)
                    XCTAssertEqual(measure.staffFrame, original.staffFrame, label)
                    XCTAssertEqual(measure.noteLayouts.count, original.noteLayouts.count, label)
                    for (actual, expected) in zip(measure.noteLayouts, original.noteLayouts) {
                        XCTAssertEqual(actual.noteheadFrame.midX, expected.noteheadFrame.midX, accuracy: 0.001, label)
                        XCTAssertEqual(actual.noteheadFrame.midY, expected.noteheadFrame.midY, accuracy: 0.001, label)
                    }
                    let originalChords = Dictionary(uniqueKeysWithValues: original.chordLayouts.map { ($0.id, $0) })
                    XCTAssertEqual(Set(measure.chordLayouts.map(\.id)), Set(originalChords.keys), label)
                    for chord in measure.chordLayouts {
                        let originalChord = try XCTUnwrap(originalChords[chord.id])
                        XCTAssertEqual(chord.snapGuideTarget.x, originalChord.snapGuideTarget.x, accuracy: 0.001, label)
                        XCTAssertEqual(chord.snapGuideTarget.y, originalChord.snapGuideTarget.y, accuracy: 0.001, label)
                        let slot = try XCTUnwrap(candidate.chordEvent(id: chord.id)?.mappedRhythmSlotIndex)
                        XCTAssertTrue(measure.noteLayouts.indices.contains(slot), label)
                        if measure.noteLayouts.indices.contains(slot) {
                            XCTAssertEqual(chord.snapGuideTarget.x, measure.noteLayouts[slot].noteheadFrame.midX, accuracy: 0.001, label)
                        }
                    }
                }
            }

            for semitones in 0..<12 {
                var candidate = chart
                candidate.transposeChordsByHalfSteps(semitones)
                try assertStableGeometry(candidate, label: "Chord transpose +\(semitones), page \(pageWidth)")
            }
            var changedKey = chart
            XCTAssertTrue(changedKey.setDisplayedDocumentKey(.fMajor))
            let changedLayout = LeadSheetPageLayoutEngine.pageLayout(for: changedKey, pageSize: pageSize)
            XCTAssertEqual(originalLayout.systems.first?.keySignatureLayouts.count, 1)
            XCTAssertEqual(changedLayout.systems.first?.keySignatureLayouts.count, 1)
            try assertStableGeometry(changedKey, label: "G major to F major, page \(pageWidth)")
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

        XCTAssertEqual(chordEvents.map(\.startPosition.displayText), ["3&", "4"])
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
        XCTAssertEqual(firstMeasure.frame.minX - firstSystem.frame.minX, 58, accuracy: 0.001)
        XCTAssertEqual(secondRowFirstMeasure.frame.minX - secondSystem.frame.minX, 58, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.frame.minX, secondRowFirstMeasure.frame.minX, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.frame.width, secondRowFirstMeasure.frame.width, accuracy: 0.001)
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

    func testSimpleChordSheetManualSystemBreakKeepsStandardMeasureWidthOnShortRows() throws {
        var chart = Chart.blank(title: "Short Simple Rows", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[3]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondSystem = try XCTUnwrap(layout.systems.last)
        let firstRowMeasure = try XCTUnwrap(firstSystem.measures.first)
        let shortRowMeasure = try XCTUnwrap(secondSystem.measures.first)

        XCTAssertEqual(firstSystem.measures.count, 3)
        XCTAssertEqual(secondSystem.measures.count, 1)
        XCTAssertEqual(firstRowMeasure.frame.width, shortRowMeasure.frame.width, accuracy: 0.001)
        XCTAssertLessThan(shortRowMeasure.trailingBarlineFrame.maxX, firstSystem.frame.maxX)
        XCTAssertLessThan(secondSystem.frame.width, firstSystem.frame.width)
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

    #if canImport(UIKit)
    func testSimpleChordSheetEqualRowManualWidthMakesShortRowVisuallyEven() throws {
        var chart = Chart.blank(title: "Equal Short Row", measureCount: 3, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        _ = chart.setMeasureManualLayoutWidth(320, for: measureIDs[0])
        _ = chart.setMeasureManualLayoutWidth(120, for: measureIDs[1])
        _ = chart.setMeasureManualLayoutWidth(220, for: measureIDs[2])

        let unevenLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let unevenSystem = try XCTUnwrap(unevenLayout.systems.first)
        let equalizedWidths = LeadSheetSimpleChordRowEqualizationPolicy.manualLayoutWidths(
            for: unevenSystem,
            in: unevenLayout,
            chart: chart
        )
        for (measureID, width) in equalizedWidths {
            _ = chart.setMeasureManualLayoutWidth(width, for: measureID)
        }

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let displayedMeasures = firstSystem.measures.map { measure in
            LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                measure,
                in: firstSystem,
                paperFrame: layout.paperFrame,
                layoutStyle: .simpleChordSheet
            )
        }
        let visibleWidths = displayedMeasures.map(\.frame.width)
        let firstVisibleWidth = try XCTUnwrap(visibleWidths.first)
        let lastMeasure = try XCTUnwrap(firstSystem.measures.last)

        XCTAssertEqual(firstSystem.measures.count, 3)
        XCTAssertTrue(visibleWidths.allSatisfy { abs($0 - firstVisibleWidth) <= 1.5 })
        XCTAssertLessThan(lastMeasure.frame.width, firstSystem.measures[0].frame.width)
    }

    func testRhythmSectionEqualRowUsesMusicalBodyWidthsWithoutLeadingSignatureReserve() throws {
        var chart = Chart.blank(title: "Even Rhythm Row", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        for (measureID, width) in zip(measureIDs, [100, 120, 140, 160]) {
            _ = chart.setMeasureManualLayoutWidth(CGFloat(width), for: measureID)
        }

        let unevenLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let unevenSystem = try XCTUnwrap(unevenLayout.systems.first)
        let equalizedWidths = LeadSheetRhythmSectionRowEqualizationPolicy.manualLayoutWidths(
            for: unevenSystem,
            in: unevenLayout,
            chart: chart
        )
        for (measureID, width) in equalizedWidths {
            _ = chart.setMeasureManualLayoutWidth(width, for: measureID)
        }

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let system = try XCTUnwrap(layout.systems.first)
        let bodyWidths = system.measures.map(\.staffFrame.width)
        let firstBodyWidth = try XCTUnwrap(bodyWidths.first)

        XCTAssertEqual(equalizedWidths.count, 4)
        XCTAssertTrue(bodyWidths.allSatisfy { abs($0 - firstBodyWidth) <= 0.001 })
        XCTAssertEqual(system.frame.maxX, layout.paperFrame.maxX - 34, accuracy: 0.001)
        XCTAssertGreaterThan(
            try XCTUnwrap(system.measures.first?.frame.width),
            firstBodyWidth,
            "The first outer frame may include the leading signature, but its stored musical body width must not."
        )
    }

    func testJoinRowMovesOnlySelectedMeasureUpAndEqualizesDestinationRow() throws {
        var chart = Chart.blank(title: "Join Rhythm Row", measureCount: 6, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        let selectedMeasureID = measureIDs[4]
        XCTAssertTrue(chart.insertSystemBreak(before: selectedMeasureID))

        let beforeLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let equalizedWidths = LeadSheetJoinRowEqualizationPolicy.manualLayoutWidths(
            startingAt: selectedMeasureID,
            in: beforeLayout,
            chart: chart
        )

        XCTAssertEqual(Set(equalizedWidths.keys), Set(measureIDs[0...4]))
        XCTAssertTrue(chart.joinRow(startingAt: selectedMeasureID, equalizedManualWidths: equalizedWidths))

        let afterLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1_366, height: 1_024)
        )
        XCTAssertEqual(afterLayout.systems[0].measures.compactMap(\.sourceMeasureID), Array(measureIDs[0...4]))
        XCTAssertEqual(afterLayout.systems[1].measures.compactMap(\.sourceMeasureID), [measureIDs[5]])
        let destinationWidths = afterLayout.systems[0].measures.map(\.staffFrame.width)
        let firstWidth = try XCTUnwrap(destinationWidths.first)
        XCTAssertTrue(destinationWidths.allSatisfy { abs($0 - firstWidth) <= 0.001 })
        XCTAssertEqual(afterLayout.systems[0].frame.maxX, afterLayout.paperFrame.maxX - 34, accuracy: 0.001)
    }

    func testSimpleChordSheetJoinRowMovesOnlySelectedMeasureAndEqualizesDestinationRow() throws {
        var chart = Chart.blank(title: "Join Simple Row", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        let selectedMeasureID = measureIDs[4]
        try appendChord("Bb7", to: selectedMeasureID, in: &chart, atFraction: 0.25)
        let selectedChordID = try XCTUnwrap(chart.measure(id: selectedMeasureID)?.chordEvents.first?.id)
        XCTAssertTrue(chart.insertSystemBreak(before: selectedMeasureID))

        let beforeLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let equalizedWidths = LeadSheetJoinRowEqualizationPolicy.manualLayoutWidths(
            startingAt: selectedMeasureID,
            in: beforeLayout,
            chart: chart
        )

        XCTAssertEqual(Set(equalizedWidths.keys), Set(measureIDs[0...4]))
        XCTAssertTrue(chart.joinRow(startingAt: selectedMeasureID, equalizedManualWidths: equalizedWidths))
        XCTAssertEqual(chart.chordEvent(id: selectedChordID)?.symbol.displayText, "Bb7")

        let afterLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1_366, height: 1_024)
        )
        XCTAssertEqual(afterLayout.systems[0].measures.compactMap(\.sourceMeasureID), Array(measureIDs[0...4]))
        XCTAssertEqual(afterLayout.systems[1].measures.compactMap(\.sourceMeasureID), [measureIDs[5]])
        let destinationWidths = afterLayout.systems[0].measures.map(\.frame.width)
        let firstWidth = try XCTUnwrap(destinationWidths.first)
        XCTAssertTrue(destinationWidths.allSatisfy { abs($0 - firstWidth) <= 0.001 })
        XCTAssertEqual(afterLayout.systems[0].frame.maxX, afterLayout.paperFrame.maxX - 34, accuracy: 0.001)
    }

    func testMoveMeasureToRowBelowEqualizesBothRhythmRows() throws {
        var chart = Chart.blank(title: "Move Down Rhythm", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        let selectedMeasureID = measureIDs[3]
        XCTAssertTrue(chart.insertSystemBreak(before: measureIDs[4]))

        let beforeLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let plan = try XCTUnwrap(
            LeadSheetMoveMeasureToRowBelowPolicy.plan(
                for: selectedMeasureID,
                in: beforeLayout,
                chart: chart
            )
        )

        XCTAssertEqual(plan.sourceRowMeasureIDs, Array(measureIDs[0..<3]))
        XCTAssertEqual(plan.destinationRowMeasureIDs, Array(measureIDs[3..<8]))
        XCTAssertEqual(Set(plan.equalizedManualWidths.keys), Set(measureIDs))
        XCTAssertTrue(
            chart.moveMeasureToRowBelow(
                selectedMeasureID,
                nextRowStartingAt: plan.nextRowFirstMeasureID,
                equalizedManualWidths: plan.equalizedManualWidths
            )
        )

        let afterLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        XCTAssertEqual(afterLayout.systems[0].measures.compactMap(\.sourceMeasureID), Array(measureIDs[0..<3]))
        XCTAssertEqual(afterLayout.systems[1].measures.compactMap(\.sourceMeasureID), Array(measureIDs[3..<8]))
        for system in afterLayout.systems.prefix(2) {
            let bodyWidths = system.measures.map(\.staffFrame.width)
            let firstBodyWidth = try XCTUnwrap(bodyWidths.first)
            XCTAssertTrue(bodyWidths.allSatisfy { abs($0 - firstBodyWidth) <= 0.001 })
            XCTAssertEqual(system.frame.maxX, afterLayout.paperFrame.maxX - 34, accuracy: 0.001)
        }
    }

    func testSimpleChordSheetMoveMeasureToRowBelowPreservesChordAndEqualizesBothRows() throws {
        var chart = Chart.blank(title: "Move Down Simple", measureCount: 8, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        let selectedMeasureID = measureIDs[3]
        try appendChord("C7", to: selectedMeasureID, in: &chart, atFraction: 0.25)
        let selectedChordID = try XCTUnwrap(chart.measure(id: selectedMeasureID)?.chordEvents.first?.id)
        XCTAssertTrue(chart.insertSystemBreak(before: measureIDs[4]))

        let beforeLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let plan = try XCTUnwrap(
            LeadSheetMoveMeasureToRowBelowPolicy.plan(
                for: selectedMeasureID,
                in: beforeLayout,
                chart: chart
            )
        )

        XCTAssertEqual(plan.sourceRowMeasureIDs, Array(measureIDs[0..<3]))
        XCTAssertEqual(plan.destinationRowMeasureIDs, Array(measureIDs[3..<8]))
        XCTAssertTrue(
            chart.moveMeasureToRowBelow(
                selectedMeasureID,
                nextRowStartingAt: plan.nextRowFirstMeasureID,
                equalizedManualWidths: plan.equalizedManualWidths
            )
        )
        XCTAssertEqual(chart.chordEvent(id: selectedChordID)?.symbol.displayText, "C7")

        let afterLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        XCTAssertEqual(afterLayout.systems[0].measures.compactMap(\.sourceMeasureID), Array(measureIDs[0..<3]))
        XCTAssertEqual(afterLayout.systems[1].measures.compactMap(\.sourceMeasureID), Array(measureIDs[3..<8]))
        for system in afterLayout.systems.prefix(2) {
            let widths = system.measures.map(\.frame.width)
            let firstWidth = try XCTUnwrap(widths.first)
            XCTAssertTrue(widths.allSatisfy { abs($0 - firstWidth) <= 0.001 })
            XCTAssertEqual(system.frame.maxX, afterLayout.paperFrame.maxX - 34, accuracy: 0.001)
        }
    }

    func testMoveMeasureToRowBelowRequiresLastMeasureAndSamePage() throws {
        var chart = Chart.blank(title: "Move Down Guard", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSystemBreak(before: measureIDs[4]))
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )

        XCTAssertNil(
            LeadSheetMoveMeasureToRowBelowPolicy.plan(
                for: measureIDs[2],
                in: layout,
                chart: chart
            )
        )

        var pageChart = Chart.blank(title: "Move Down Page Guard", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let previousPageLastMeasureID = try XCTUnwrap(pageChart.measures.last?.id)
        _ = try XCTUnwrap(pageChart.appendPage())
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: pageChart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        XCTAssertNil(
            LeadSheetMoveMeasureToRowBelowPolicy.plan(
                for: previousPageLastMeasureID,
                in: pageLayout,
                chart: pageChart
            )
        )
    }

    func testRhythmSectionEditableMeasureFrameExcludesLeadingSignatureReserve() throws {
        let chart = Chart.blank(title: "Rhythm Selection", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let editableMeasure = LeadSheetMeasureResizeGeometry.editableMeasureLayout(
            firstMeasure,
            layoutStyle: chart.layoutStyle
        )

        XCTAssertEqual(editableMeasure.frame.minX, firstMeasure.staffFrame.minX, accuracy: 0.001)
        XCTAssertEqual(editableMeasure.frame.width, firstMeasure.staffFrame.width, accuracy: 0.001)
        XCTAssertLessThan(editableMeasure.frame.width, firstMeasure.frame.width)
        XCTAssertEqual(
            LeadSheetMeasureResizeGeometry.handleFrames(for: editableMeasure).left.midX,
            firstMeasure.staffFrame.minX,
            accuracy: 0.001
        )
    }
    #endif

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

    func testRhythmSectionSheetLayoutOmitsKeyHeaderAndKeepsStaffContext() throws {
        let chart = Chart.blank(title: "Pocket", measureCount: 4, layoutStyle: .rhythmSectionSheet)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertNil(layout.header.meterFrame)
        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        let clefFrame = try XCTUnwrap(firstSystem.clefFrame)
        let timeSignatureFrame = try XCTUnwrap(firstSystem.timeSignatureFrame)
        XCTAssertGreaterThanOrEqual(timeSignatureFrame.height, 56)
        XCTAssertTrue(firstSystem.keySignatureLayouts.isEmpty)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let secondMeasure = try XCTUnwrap(firstSystem.measures.dropFirst().first)
        let leadingExtensionWidth = firstMeasure.staffFrame.minX - firstMeasure.frame.minX
        XCTAssertEqual(firstMeasure.frame.minX, firstSystem.frame.minX, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(firstMeasure.staffFrame.minX, timeSignatureFrame.maxX + 8)
        XCTAssertLessThanOrEqual(
            firstMeasure.staffFrame.minX - timeSignatureFrame.maxX,
            24,
            "The first Rhythm Section setup should leave readable time-signature spacing without a fake measure."
        )
        XCTAssertLessThanOrEqual(
            leadingExtensionWidth,
            90,
            "Rhythm Section setup should stay compact instead of reserving the old fake-measure lane."
        )
        XCTAssertEqual(firstMeasure.frame.width, firstMeasure.staffFrame.width + leadingExtensionWidth, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.staffFrame.width, secondMeasure.frame.width, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.leadingBarlineX, firstMeasure.staffFrame.minX, accuracy: 0.001)
        XCTAssertEqual(clefFrame.minX - firstMeasure.frame.minX, 8, accuracy: 0.001)
        XCTAssertEqual(clefFrame.midY + 2, firstMeasure.staffFrame.midY, accuracy: 0.001)
        XCTAssertEqual(timeSignatureFrame.midY, firstMeasure.staffFrame.midY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(firstMeasure.staffFrame.minX - timeSignatureFrame.maxX, 6)
        XCTAssertLessThan(timeSignatureFrame.maxX, firstMeasure.leadingBarlineX)
        XCTAssertEqual(firstMeasure.chordBandFrame.minY, firstMeasure.frame.minY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(firstMeasure.chordBandFrame.minX, firstMeasure.staffFrame.minX)
        XCTAssertEqual(firstMeasure.chordWritingFrame.minX, firstMeasure.staffFrame.minX + 2, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordWritingFrame.width, firstMeasure.staffFrame.width - 4, accuracy: 0.001)
    }

    func testRhythmSectionManualSystemBreakControlsRenderedRows() throws {
        var chart = Chart.blank(title: "Pocket Rows", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.insertSystemBreak(before: measureIDs[2]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertEqual(layout.systems.count, 2)
        XCTAssertEqual(layout.systems[0].measures.compactMap(\.sourceMeasureID), Array(measureIDs[0..<2]))
        XCTAssertEqual(layout.systems[1].measures.compactMap(\.sourceMeasureID), Array(measureIDs[2..<4]))
        XCTAssertTrue(layout.systems.allSatisfy { $0.staffLineYPositions.count == 5 })
        XCTAssertTrue(layout.systems.allSatisfy { $0.frame.width <= layout.paperFrame.width })
        let firstRowFirstMeasure = try XCTUnwrap(layout.systems[0].measures.first)
        let firstRowLastMeasure = try XCTUnwrap(layout.systems[0].measures.last)
        let secondRowFirstMeasure = try XCTUnwrap(layout.systems[1].measures.first)
        let secondRowLastMeasure = try XCTUnwrap(layout.systems[1].measures.last)
        let firstRowLeadingExtensionWidth = firstRowFirstMeasure.staffFrame.minX - firstRowFirstMeasure.frame.minX
        let secondRowLeadingExtensionWidth = secondRowFirstMeasure.staffFrame.minX - secondRowFirstMeasure.frame.minX
        XCTAssertEqual(
            firstRowFirstMeasure.frame.minX,
            secondRowFirstMeasure.frame.minX,
            accuracy: 0.001
        )
        XCTAssertEqual(firstRowFirstMeasure.staffFrame.width, secondRowFirstMeasure.staffFrame.width, accuracy: 0.001)
        XCTAssertEqual(firstRowLastMeasure.staffFrame.width, secondRowLastMeasure.staffFrame.width, accuracy: 0.001)
        XCTAssertLessThan(
            secondRowLeadingExtensionWidth,
            firstRowLeadingExtensionWidth,
            "Continuation Rhythm Section stanzas should not inherit the wider first-row time-signature setup lane."
        )
        let continuationClefFrame = try XCTUnwrap(layout.systems[1].clefFrame)
        XCTAssertGreaterThanOrEqual(secondRowFirstMeasure.staffFrame.minX, continuationClefFrame.maxX + 8)
        XCTAssertLessThanOrEqual(
            secondRowFirstMeasure.staffFrame.minX - continuationClefFrame.maxX,
            12,
            "The continuation leading barline should read as the start of the stanza's first real measure."
        )
        XCTAssertEqual(secondRowFirstMeasure.leadingBarlineX, secondRowFirstMeasure.staffFrame.minX, accuracy: 0.001)
        XCTAssertNil(layout.systems[1].timeSignatureFrame)
    }

    func testRhythmSectionKeyChangeKeepsRenderedMeasureRowsStable() throws {
        var chart = Chart.blank(
            title: "Nadie Layout Regression",
            key: .gMajor,
            measureCount: 22,
            layoutStyle: .rhythmSectionSheet
        )
        let measureIDs = chart.measures.map(\.id)
        let manualWidths: [CGFloat] =
            Array(repeating: 106.8, count: 8)
            + Array(repeating: 101.32, count: 5)
            + Array(repeating: 286, count: 2)
            + Array(repeating: 124.4, count: 5)
            + [269.5, 263.5]

        for (measureID, width) in zip(measureIDs, manualWidths) {
            XCTAssertNotNil(chart.setMeasureManualLayoutWidth(width, for: measureID))
        }
        for breakIndex in [4, 8, 13, 15] {
            XCTAssertTrue(chart.insertSystemBreak(before: measureIDs[breakIndex]))
        }

        let pageSize = CGSize(width: 800, height: 2_168)
        let originalLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize
        )
        let originalRows = originalLayout.systems.map {
            $0.measures.compactMap(\.sourceMeasureID)
        }
        let expectedRows = [
            Array(measureIDs[0..<4]),
            Array(measureIDs[4..<8]),
            Array(measureIDs[8..<13]),
            Array(measureIDs[13..<15]),
            Array(measureIDs[15..<20]),
            Array(measureIDs[20..<22])
        ]
        XCTAssertEqual(originalRows, expectedRows)

        XCTAssertTrue(chart.setDisplayedDocumentKey(.cFlatMajor))
        let changedKeyLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize
        )
        let changedKeyRows = changedKeyLayout.systems.map {
            $0.measures.compactMap(\.sourceMeasureID)
        }

        XCTAssertEqual(changedKeyRows, originalRows)
        XCTAssertEqual(changedKeyLayout.systems.first?.keySignatureLayouts.count, 7)
        for (originalSystem, changedKeySystem) in zip(
            originalLayout.systems,
            changedKeyLayout.systems
        ) {
            XCTAssertEqual(changedKeySystem.frame.minY, originalSystem.frame.minY, accuracy: 0.001)
            XCTAssertLessThanOrEqual(
                changedKeySystem.frame.maxX,
                changedKeyLayout.paperFrame.maxX - 34 + 0.001
            )
        }
    }

    func testRhythmSectionManualSystemBreakKeepsStandardMeasureWidthOnShortRows() throws {
        var chart = Chart.blank(title: "Pocket Rows", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.insertSystemBreak(before: measureIDs[3]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondSystem = try XCTUnwrap(layout.systems.dropFirst().first)
        let standardWidth = try XCTUnwrap(firstSystem.measures.first?.staffFrame.width)
        let shortRowMeasure = try XCTUnwrap(secondSystem.measures.first)

        XCTAssertEqual(firstSystem.measures.count, 3)
        XCTAssertEqual(secondSystem.measures.count, 1)
        XCTAssertTrue(
            firstSystem.measures.allSatisfy { abs($0.staffFrame.width - standardWidth) <= 0.001 },
            "The first Rhythm Section system establishes the default measure width."
        )
        XCTAssertEqual(shortRowMeasure.staffFrame.width, standardWidth, accuracy: 0.001)
        XCTAssertGreaterThan(shortRowMeasure.frame.width, standardWidth)
        XCTAssertLessThan(
            shortRowMeasure.trailingBarlineFrame.midX,
            firstSystem.measures.last?.trailingBarlineFrame.midX ?? .zero,
            "A short manual Rhythm Section row should keep standard measure width instead of stretching."
        )
    }

    func testRhythmSectionSectionLabelsReserveRehearsalMarkSpaceAboveChordLane() throws {
        var chart = Chart.blank(title: "Hits", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        chart.addSectionLabel(text: "B")
        try appendChord("C7", to: firstMeasureID, in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first)
        let sectionTextFrame = try XCTUnwrap(firstSystem.sectionTextFrame)
        let chordLayout = try XCTUnwrap(firstMeasure.chordLayouts.first)
        let expectedChordRenderOffset = CGFloat(16.0 / 3.0)

        XCTAssertEqual(firstSystem.sectionText, "B")
        XCTAssertEqual(sectionTextFrame.height, 20, accuracy: 0.001)
        XCTAssertLessThanOrEqual(sectionTextFrame.maxY, firstMeasure.chordBandFrame.minY)
        XCTAssertEqual(firstMeasure.chordBandFrame.minY, firstMeasure.frame.minY + 22, accuracy: 0.001)
        XCTAssertEqual(chordLayout.frame.midY, firstMeasure.chordBandFrame.midY + expectedChordRenderOffset, accuracy: 0.001)
        XCTAssertEqual(chordLayout.fitFrame, chordLayout.frame)
        XCTAssertEqual(chordLayout.frame, chordLayout.naturalFrame)
        XCTAssertLessThan(firstMeasure.chordBandFrame.maxY, firstMeasure.staffFrame.minY)
        XCTAssertGreaterThan(firstMeasure.staffFrame.minY - firstMeasure.chordBandFrame.maxY, 5)
        XCTAssertGreaterThanOrEqual(chordLayout.frame.minY, firstMeasure.chordBandFrame.minY)
        XCTAssertFalse(sectionTextFrame.intersects(firstMeasure.staffFrame))
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
        XCTAssertLessThan(cueTextLayout.frame.width, measure.staffFrame.width)
        XCTAssertTrue(cueTextLayout.hitFrame.contains(cueTextLayout.frame))
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
        XCTAssertLessThan(cueTextLayout.frame.width, measure.staffFrame.width)
        XCTAssertTrue(cueTextLayout.hitFrame.contains(cueTextLayout.frame))
    }

    func testCueTextLayoutFollowsMovedBeatFraction() throws {
        var chart = Chart.blank(title: "Moved Cue", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let cueTextID = try XCTUnwrap(
            chart.addCueText("hits", anchorMeasureID: measureID, position: .above)
        )
        XCTAssertTrue(chart.moveCueText(cueTextID, to: measureID, atFraction: 0.52))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let cueTextLayout = try XCTUnwrap(measure.cueTextLayouts.first)
        let expectedBeatThreeX = measure.staffFrame.minX + measure.staffFrame.width * 0.5

        XCTAssertEqual(cueTextLayout.id, cueTextID)
        XCTAssertEqual(try XCTUnwrap(cueTextLayout.beatFraction), 0.5, accuracy: 0.0001)
        XCTAssertEqual(cueTextLayout.frame.minX, expectedBeatThreeX, accuracy: 1)
    }

    func testCueTextLayoutAppliesMovedVerticalOffset() throws {
        var chart = Chart.blank(title: "Moved Cue", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let cueTextID = try XCTUnwrap(
            chart.addCueText("hits", anchorMeasureID: measureID, position: .above)
        )
        let originalLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let originalCueTextLayout = try XCTUnwrap(originalLayout.systems.first?.measures.first?.cueTextLayouts.first)

        XCTAssertTrue(chart.moveCueText(cueTextID, to: measureID, atFraction: nil, verticalOffset: 24))
        let movedLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let movedCueTextLayout = try XCTUnwrap(movedLayout.systems.first?.measures.first?.cueTextLayouts.first)

        XCTAssertEqual(movedCueTextLayout.id, cueTextID)
        XCTAssertEqual(movedCueTextLayout.verticalOffset, 24)
        XCTAssertEqual(movedCueTextLayout.frame.minY - originalCueTextLayout.frame.minY, 24, accuracy: 0.5)
        XCTAssertEqual(movedCueTextLayout.hitFrame.minY - originalCueTextLayout.hitFrame.minY, 24, accuracy: 0.5)
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
        XCTAssertLessThan(startMarker.frame.width, startMeasure.staffFrame.height * 0.28)
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

    func testRepeatStartBoundarySuppressesPreviousNormalBarline() throws {
        var chart = Chart.blank(title: "Repeat Start", measureCount: 3, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[1], endMeasureID: measureIDs[2])
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == measureIDs[0] })
        let repeatStartMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == measureIDs[1] })
        let boundaryMarkers = LeadSheetRepeatBoundaryPolicy.repeatMarkers(
            after: firstMeasure,
            before: repeatStartMeasure
        )

        XCTAssertTrue(firstMeasure.repeatMarkerLayouts.isEmpty)
        XCTAssertEqual(boundaryMarkers.map(\.edge), [.leading])
        XCTAssertEqual(LeadSheetRepeatBoundaryPolicy.visibleBarlineCount(for: boundaryMarkers), 2)
        XCTAssertFalse(
            LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(
                after: firstMeasure,
                before: repeatStartMeasure
            )
        )
    }

    func testAdjacentRepeatEndStartCombinesIntoOneTwoLineBoundary() throws {
        var chart = Chart.blank(title: "Adjacent Repeats", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[1])
        )
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[2], endMeasureID: measureIDs[3])
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let repeatEndMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == measureIDs[1] })
        let repeatStartMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == measureIDs[2] })
        let boundaryMarkers = LeadSheetRepeatBoundaryPolicy.repeatMarkers(
            after: repeatEndMeasure,
            before: repeatStartMeasure
        )

        XCTAssertEqual(Set(boundaryMarkers.map(\.edge)), [.leading, .trailing])
        XCTAssertEqual(boundaryMarkers.count, 2)
        XCTAssertEqual(LeadSheetRepeatBoundaryPolicy.visibleBarlineCount(for: boundaryMarkers), 2)
        XCTAssertFalse(
            LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(
                after: repeatEndMeasure,
                before: repeatStartMeasure
            )
        )
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

    func testRhythmMeasureRepeatRendersCenteredMeasureLevelSymbol() throws {
        var chart = Chart.blank(title: "Measure Repeat", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap([.measureRepeat], for: measureID)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let noteLayout = try XCTUnwrap(measure.noteLayouts.first)

        XCTAssertEqual(measure.noteLayouts.count, 1)
        XCTAssertEqual(noteLayout.symbolStyle, .measureRepeat)
        XCTAssertNil(noteLayout.noteheadSymbol)
        XCTAssertNil(noteLayout.stemStart)
        XCTAssertNil(noteLayout.stemEnd)
        XCTAssertEqual(noteLayout.noteheadFrame.midX, measure.staffFrame.midX, accuracy: 0.001)
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
        XCTAssertEqual(endingLayout.frame.height, 20, accuracy: 0.001)
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
        XCTAssertEqual(endingLayout.frame.height, 20, accuracy: 0.001)
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
        XCTAssertEqual(markerLayout.frame.height, 34, accuracy: 0.001)
        XCTAssertEqual(markerLayout.movementFrame.minX, firstMeasure.staffFrame.minX + 6, accuracy: 0.001)
        XCTAssertLessThan(markerLayout.frame.width, firstMeasure.staffFrame.width)
    }

    func testSimpleChordSheetPointRoadmapMarkerHorizontalOffsetMovesWithinMeasureSpace() throws {
        var chart = Chart.blank(title: "Simple Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let markerID = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureID))

        XCTAssertTrue(chart.movePointRoadmapMarkerHorizontally(markerID, toNormalizedOffset: 1))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let markerLayout = try XCTUnwrap(firstSystem.roadmapMarkerLayouts.first)

        XCTAssertEqual(markerLayout.roadmapObjectID, markerID)
        XCTAssertEqual(markerLayout.frame.maxX, markerLayout.movementFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(markerLayout.frame.width, 42, accuracy: 0.001)
        XCTAssertEqual(markerLayout.frame.height, 44, accuracy: 0.001)
        XCTAssertEqual(markerLayout.movementFrame.height, 44, accuracy: 0.001)
        XCTAssertLessThan(markerLayout.frame.width, markerLayout.movementFrame.width)
    }

    func testSimpleChordSheetPointRoadmapMarkerScaleChangesMarkerFrame() throws {
        var chart = Chart.blank(title: "Simple Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let markerID = try XCTUnwrap(chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureID))

        XCTAssertTrue(chart.resizePointRoadmapMarker(markerID, byScaleDelta: RoadmapObject.scaleStep))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let markerLayout = try XCTUnwrap(layout.systems.first?.roadmapMarkerLayouts.first)

        XCTAssertEqual(markerLayout.roadmapObjectID, markerID)
        XCTAssertEqual(markerLayout.scale, CGFloat(RoadmapObject.defaultScale + RoadmapObject.scaleStep), accuracy: 0.001)
        XCTAssertEqual(markerLayout.frame.width, 42 * markerLayout.scale, accuracy: 0.001)
        XCTAssertEqual(markerLayout.frame.height, 44 * markerLayout.scale, accuracy: 0.001)
    }

    func testSimpleChordSheetInlineCodaRoadmapMarkerHasGlyphSafeHeight() throws {
        var chart = Chart.blank(title: "Simple Roadmap", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.toCoda, anchorMeasureID: measureID))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let markerLayout = try XCTUnwrap(firstSystem.roadmapMarkerLayouts.first)

        XCTAssertEqual(markerLayout.text, "To \(NotationGlyphCatalog.coda)")
        XCTAssertEqual(markerLayout.frame.height, 44, accuracy: 0.001)
        XCTAssertGreaterThan(markerLayout.frame.width, 42)
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
        XCTAssertEqual(markerLayout.text, "D.S. al \(NotationGlyphCatalog.coda)")
        XCTAssertLessThanOrEqual(markerLayout.frame.maxY, firstMeasure.chordBandFrame.minY)
        XCTAssertEqual(markerLayout.frame.height, 32, accuracy: 0.001)
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
        XCTAssertNil(layout.header.meterFrame)
        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertNotNil(firstSystem.clefFrame)
        XCTAssertNotNil(firstSystem.timeSignatureFrame)
        XCTAssertTrue(firstSystem.keySignatureLayouts.isEmpty)
        XCTAssertLessThan(firstMeasure.chordBandFrame.maxY, firstMeasure.staffFrame.minY)
        XCTAssertEqual(firstMeasure.chordBandFrame.minY, firstMeasure.frame.minY, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[0].frame.midY, firstMeasure.chordBandFrame.midY + CGFloat(16.0 / 3.0), accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[0].fitFrame, firstMeasure.chordLayouts[0].frame)
        XCTAssertEqual(firstMeasure.chordLayouts[0].frame, firstMeasure.chordLayouts[0].naturalFrame)
        XCTAssertEqual(firstMeasure.noteLayouts.count, 4)
        XCTAssertEqual(firstMeasure.chordLayouts.map(\.text), ["C", "G"])
        XCTAssertEqual(firstMeasure.chordLayouts[0].frame.midX, firstMeasure.noteLayouts[0].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[1].frame.midX, firstMeasure.noteLayouts[2].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[0].snapGuideTarget.x, firstMeasure.noteLayouts[0].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(firstMeasure.chordLayouts[1].snapGuideTarget.x, firstMeasure.noteLayouts[2].noteheadFrame.midX, accuracy: 0.001)
    }

    func testRhythmSectionDenseOpeningChordsClearSetupAndKeepChosenTextSize() throws {
        var chart = Chart.blank(title: "Be Blessed", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
        try appendChord("Ab△7", to: measureID, in: &chart, atFraction: 0.03)
        try appendChord("Eb△7", to: measureID, in: &chart, atFraction: 0.30)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordLayouts = firstMeasure.chordLayouts

        XCTAssertEqual(chordLayouts.map(\.text), ["Ab△7", "Eb△7"])
        XCTAssertGreaterThanOrEqual(
            chordLayouts[0].frame.minX - firstMeasure.leadingBarlineX,
            16,
            "A wide beat-one Rhythm Section chord should not visually crowd the opening barline."
        )
        XCTAssertTrue(chordLayouts.allSatisfy { $0.frame == $0.naturalFrame && $0.renderFontSize == ChartTypographyResolver.structuredChordPrimaryFontSize })
        XCTAssertEqual(chordLayouts[0].snapGuideTarget.x, firstMeasure.noteLayouts[0].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(chordLayouts[1].snapGuideTarget.x, firstMeasure.noteLayouts[1].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertGreaterThan(
            chordLayouts[0].frame.midX,
            chordLayouts[0].snapGuideTarget.x,
            "The visible chord may shift right to stay readable while the rhythm snap remains on beat one."
        )
    }

    func testRhythmSectionSheetRendersOneTimeAppliedChordTranspositionWithoutMovingSnaps() throws {
        var chart = Chart.blank(title: "Pocket Transpose", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
        try appendChord("C", to: measureID, in: &chart, atFraction: 0.03)
        try appendChord("G/B", to: measureID, in: &chart, atFraction: 0.62)

        let writtenLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let writtenMeasure = try XCTUnwrap(writtenLayout.systems.first?.measures.first)
        let writtenSnapTargets = writtenMeasure.chordLayouts.map(\.snapGuideTarget.x)

        chart.setChordTranspositionSemitones(1)

        let transposedLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let transposedMeasure = try XCTUnwrap(transposedLayout.systems.first?.measures.first)

        XCTAssertEqual(transposedMeasure.chordLayouts.map(\.text), ["C#", "G#/C"])
        XCTAssertEqual(chart.measure(id: measureID)?.chordEvents.map(\.symbol.displayText), ["C#", "G#/C"])
        XCTAssertEqual(chart.chordTranspositionSemitones, 0)
        for (transposedTarget, writtenTarget) in zip(
            transposedMeasure.chordLayouts.map(\.snapGuideTarget.x),
            writtenSnapTargets
        ) {
            XCTAssertEqual(transposedTarget, writtenTarget, accuracy: 0.001)
        }
        XCTAssertEqual(transposedMeasure.chordLayouts[0].frame.midX, transposedMeasure.noteLayouts[0].noteheadFrame.midX, accuracy: 0.001)
        XCTAssertEqual(transposedMeasure.chordLayouts[1].frame.midX, transposedMeasure.noteLayouts[2].noteheadFrame.midX, accuracy: 0.001)
    }

    func testSimpleChordSheetExportReadinessKeepsStructuredObjectsReadable() throws {
        var chart = Chart.blank(title: "Simple Export Proof", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        chart.addSectionLabel(text: "Intro")
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))
        _ = try XCTUnwrap(chart.addCueText("freely", anchorMeasureID: measureIDs[1], position: .above, emphasis: .subtle))
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

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertTrue(layout.systems.allSatisfy(\.staffLineYPositions.isEmpty))
        XCTAssertEqual(firstSystem.sectionText, "Intro")
        XCTAssertEqual(firstSystem.measures.flatMap(\.chordLayouts).map(\.text), ["C", "F", "G/B"])
        XCTAssertEqual(firstMeasure.repeatMarkerLayouts.first?.edge, .leading)
        XCTAssertEqual(firstSystem.measures.last?.repeatMarkerLayouts.first?.edge, .trailing)
        XCTAssertEqual(cueTextLayout.text, "freely")
        XCTAssertTrue(secondMeasure.frame.contains(CGPoint(x: cueTextLayout.frame.midX, y: cueTextLayout.frame.midY)))
    }

    func testRhythmSectionExportReadinessKeepsProfessionalHitChartHierarchy() throws {
        var chart = Chart.blank(title: "Rhythm Export Proof", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        chart.addSectionLabel(text: "A")
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3]))
        _ = try XCTUnwrap(chart.addCueText("stop time", anchorMeasureID: measureIDs[1], position: .below))
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
        let fourthMeasure = try XCTUnwrap(allMeasures.first { $0.sourceMeasureID == measureIDs[3] })
        let sectionTextFrame = try XCTUnwrap(firstSystem.sectionTextFrame)
        let cueTextLayout = try XCTUnwrap(secondMeasure.cueTextLayouts.first)

        XCTAssertNil(layout.header.keyFrame)
        XCTAssertNil(layout.header.meterFrame)
        XCTAssertEqual(firstSystem.staffLineYPositions.count, 5)
        XCTAssertEqual(firstSystem.sectionText, "A")
        XCTAssertLessThanOrEqual(sectionTextFrame.maxY, firstMeasure.chordBandFrame.minY)
        XCTAssertGreaterThan(firstMeasure.staffFrame.minY - firstMeasure.chordBandFrame.maxY, 5)
        XCTAssertEqual(allMeasures.flatMap(\.chordLayouts).map(\.text), ["C7", "F7", "G7sus"])
        XCTAssertEqual(firstMeasure.repeatMarkerLayouts.first?.edge, .leading)
        XCTAssertEqual(fourthMeasure.repeatMarkerLayouts.first?.edge, .trailing)
        XCTAssertEqual(firstMeasure.noteLayouts.count, 4)
        XCTAssertEqual(secondMeasure.noteLayouts.count, 3)
        XCTAssertTrue(firstSystem.measures.flatMap(\.chordLayouts).allSatisfy { $0.frame.maxY < firstMeasure.staffFrame.minY })
        XCTAssertGreaterThan(cueTextLayout.frame.minY, secondMeasure.staffFrame.maxY)
        XCTAssertFalse(cueTextLayout.frame.intersects(secondMeasure.staffFrame))
    }

    func testLeadSheetLayoutOmitsKeyHeaderAndKeepsLeadingNotation() throws {
        let chart = Chart.blank(title: "Lead", measureCount: 4, layoutStyle: .leadSheet)

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

    func testInstrumentTranspositionDrivesDisplayedKeySignatureWithoutRowText() throws {
        var leadChart = Chart.blank(
            title: "Transposed Lead Key",
            key: .cMajor,
            measureCount: 4,
            layoutStyle: .leadSheet
        )
        leadChart.setInstrumentTranspositionView(.bb)

        let leadLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: leadChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let leadSystem = try XCTUnwrap(leadLayout.systems.first)

        XCTAssertEqual(leadChart.displayedDocumentKey, .dMajor)
        XCTAssertEqual(leadSystem.keySignatureLayouts.map(\.symbol), [.accidentalSharp, .accidentalSharp])

        var simpleChart = Chart.blank(
            title: "Transposed Simple Key",
            key: .bFlatMajor,
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        simpleChart.setInstrumentTranspositionView(.bb)

        let simpleLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: simpleChart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertEqual(simpleChart.displayedDocumentKey, .cMajor)
        XCTAssertNil(simpleLayout.systems.first?.keyText)
        XCTAssertNil(simpleLayout.systems.first?.keyTextFrame)
    }

    func testDisplayedChordLayoutsFollowKeyAndInstrumentChanges() throws {
        var chart = Chart.blank(
            title: "Displayed Chords",
            key: .dMajor,
            measureCount: 1,
            layoutStyle: .simpleChordSheet
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("Db7/F"),
                rawInput: "Db7/F",
                to: measureID,
                atFraction: 0.1
            )
        )

        var layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        XCTAssertEqual(layout.systems.first?.measures.first?.chordLayouts.map(\.text), ["C#7/F"])

        XCTAssertTrue(chart.setDisplayedDocumentKey(.eFlatMajor))
        layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        XCTAssertEqual(layout.systems.first?.measures.first?.chordLayouts.map(\.text), ["D7/Gb"])

        chart.setInstrumentTranspositionView(.bb)
        layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        XCTAssertEqual(chart.displayedDocumentKey, .fMajor)
        XCTAssertEqual(layout.systems.first?.measures.first?.chordLayouts.map(\.text), ["E7/Ab"])
    }

    func testSimpleChordSheetKeyAndChordTranspositionKeepDenseMeasureGeometryStable() throws {
        var chart = Chart.blank(
            title: "Stable Transposed Grid",
            key: .cMajor,
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        try appendChord("C", to: measureID, in: &chart, atFraction: 0.05)
        try appendChord("E/G", to: measureID, in: &chart, atFraction: 0.3)
        try appendChord("G/B", to: measureID, in: &chart, atFraction: 0.55)
        try appendChord("B7/D#", to: measureID, in: &chart, atFraction: 0.8)

        let pageSize = CGSize(width: 900, height: 1_400)
        let originalLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let originalRows = originalLayout.systems.map {
            $0.measures.compactMap(\.sourceMeasureID)
        }
        let originalMeasureFrames = Dictionary(
            uniqueKeysWithValues: originalLayout.systems.flatMap(\.measures).compactMap { measure in
                measure.sourceMeasureID.map { ($0, measure.frame) }
            }
        )

        var keyChangedChart = chart
        XCTAssertTrue(keyChangedChart.setDisplayedDocumentKey(.cSharpMajor))
        var chordTransposedChart = chart
        chordTransposedChart.transposeChordsByHalfSteps(1)

        for (label, candidate) in [
            ("key", keyChangedChart),
            ("transpose", chordTransposedChart)
        ] {
            let candidateLayout = LeadSheetPageLayoutEngine.pageLayout(
                for: candidate,
                pageSize: pageSize
            )
            XCTAssertEqual(
                candidateLayout.systems.map { $0.measures.compactMap(\.sourceMeasureID) },
                originalRows,
                "\(label) changed Simple Sheet row membership."
            )
            for measure in candidateLayout.systems.flatMap(\.measures) {
                let measureID = try XCTUnwrap(measure.sourceMeasureID)
                let originalFrame = try XCTUnwrap(originalMeasureFrames[measureID])
                XCTAssertEqual(
                    measure.frame,
                    originalFrame,
                    "\(label) redistributed Simple Sheet measure geometry."
                )
            }
        }
    }

    func testSimpleChordSheetOmitsKeyTextAtEveryRowStart() throws {
        var chart = Chart.blank(
            title: "Simple Keys",
            key: .bFlatMajor,
            measureCount: 6,
            layoutStyle: .simpleChordSheet
        )
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.setKeyChange(.dMajor, atStartOf: measureIDs[3]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertEqual(layout.systems.count, 2)
        XCTAssertTrue(layout.systems.allSatisfy { $0.keyText == nil })
        XCTAssertTrue(layout.systems.allSatisfy { $0.keyTextFrame == nil })
        XCTAssertTrue(layout.systems.allSatisfy(\.keySignatureLayouts.isEmpty))
        XCTAssertEqual(layout.systems[0].measures.first?.sourceMeasureID, measureIDs[0])
        XCTAssertEqual(layout.systems[1].measures.first?.sourceMeasureID, measureIDs[3])
    }

    func testRhythmSectionShowsKeySignatureAtEveryRowAndModulationStartsNewRow() throws {
        var chart = Chart.blank(
            title: "Rhythm Keys",
            key: .dMajor,
            measureCount: 6,
            layoutStyle: .rhythmSectionSheet
        )
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.setKeyChange(.eFlatMajor, atStartOf: measureIDs[3]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondSystem = try XCTUnwrap(layout.systems.dropFirst().first)

        XCTAssertEqual(firstSystem.measures.first?.sourceMeasureID, measureIDs[0])
        XCTAssertEqual(secondSystem.measures.first?.sourceMeasureID, measureIDs[3])
        XCTAssertEqual(firstSystem.keySignatureLayouts.map(\.symbol), [.accidentalSharp, .accidentalSharp])
        XCTAssertEqual(
            secondSystem.keySignatureLayouts.map(\.symbol),
            [.accidentalFlat, .accidentalFlat, .accidentalFlat]
        )
        XCTAssertNotNil(firstSystem.clefFrame)
        XCTAssertNotNil(secondSystem.clefFrame)
        XCTAssertNil(firstSystem.keyText)
        XCTAssertNil(secondSystem.keyText)
    }

    func testLeadSheetContinuationSystemsCarryActiveKeySignature() throws {
        let chart = Chart.blank(
            title: "Lead Continuation Keys",
            key: .bFlatMajor,
            measureCount: 8,
            layoutStyle: .leadSheet
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertGreaterThan(layout.systems.count, 1)
        XCTAssertTrue(layout.systems.allSatisfy { $0.clefFrame != nil })
        XCTAssertTrue(layout.systems.allSatisfy { $0.keySignatureLayouts.map(\.symbol) == [.accidentalFlat, .accidentalFlat] })
        XCTAssertNotNil(layout.systems.first?.timeSignatureFrame)
        XCTAssertTrue(layout.systems.dropFirst().allSatisfy { $0.timeSignatureFrame == nil })
    }

    func testLeadSheetKeyChangeStartsVisibleKeySignatureSystem() throws {
        var chart = Chart.blank(
            title: "Lead Modulation Keys",
            key: .dMajor,
            measureCount: 6,
            layoutStyle: .leadSheet
        )
        let measureIDs = chart.measures.map(\.id)

        XCTAssertTrue(chart.setKeyChange(.eFlatMajor, atStartOf: measureIDs[2]))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let firstSystem = try XCTUnwrap(layout.systems.first)
        let secondSystem = try XCTUnwrap(layout.systems.dropFirst().first)

        XCTAssertEqual(firstSystem.measures.first?.sourceMeasureID, measureIDs[0])
        XCTAssertEqual(secondSystem.measures.first?.sourceMeasureID, measureIDs[2])
        XCTAssertEqual(firstSystem.keySignatureLayouts.map(\.symbol), [.accidentalSharp, .accidentalSharp])
        XCTAssertEqual(
            secondSystem.keySignatureLayouts.map(\.symbol),
            [.accidentalFlat, .accidentalFlat, .accidentalFlat]
        )
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

    func testRhythmSectionTrebleClefSetupUsesTrebleKeySignaturePositions() throws {
        let key = DocumentKey(tonic: .d, accidental: .natural, mode: .major)
        var chart = Chart.draft(title: "Treble Rhythm", key: key, layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Treble Rhythm",
            key: key,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 4,
            clef: .treble
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let firstSharp = try XCTUnwrap(layout.systems.first?.keySignatureLayouts.first)

        XCTAssertEqual(chart.renderedClef, .treble)
        XCTAssertEqual(firstSharp.symbol, .accidentalSharp)
        XCTAssertEqual(firstSharp.staffOffset, 0, accuracy: 0.001)
    }

    func testRhythmSectionTrebleClefFlatKeySignatureUsesTreblePositions() throws {
        let key = DocumentKey(tonic: .e, accidental: .flat, mode: .major)
        var chart = Chart.draft(title: "Treble Flats", key: key, layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Treble Flats",
            key: key,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 4,
            clef: .treble
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let flats = try XCTUnwrap(layout.systems.first?.keySignatureLayouts)
        let topLineY = try XCTUnwrap(layout.systems.first?.staffLineYPositions.first)

        XCTAssertEqual(chart.renderedClef, .treble)
        XCTAssertEqual(flats.map(\.symbol), [.accidentalFlat, .accidentalFlat, .accidentalFlat])
        XCTAssertEqual(flats.map(\.staffOffset), [2, 0.5, 2.5])
        zip(
            flats.map { ($0.frame.midY - topLineY) / $0.staffSpace },
            [CGFloat(1.5), 0, 2]
        ).forEach { actual, expected in
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
        XCTAssertLessThan(flats[1].frame.midY, flats[0].frame.midY)
    }

    func testRhythmSectionKeySignaturePositionsCoverAllAccidentalCountsInBothClefs() throws {
        let sharpKeys: [DocumentKey] = [
            .gMajor, .dMajor, .aMajor, .eMajor, .bMajor, .fSharpMajor, .cSharpMajor
        ]
        let flatKeys: [DocumentKey] = [
            .fMajor, .bFlatMajor, .eFlatMajor, .aFlatMajor, .dFlatMajor, .gFlatMajor, .cFlatMajor
        ]

        let expected: [(clef: ChartClef, sharps: [CGFloat], flats: [CGFloat])] = [
            (
                clef: .treble,
                sharps: [0, 1.5, -0.5, 1, 2.5, 0.5, 2],
                flats: [2, 0.5, 2.5, 1, 3, 1.5, 3.5]
            ),
            (
                clef: .bass,
                sharps: [1, 2.5, 4, 2, 0, 1.5, 3],
                flats: [3, 1.5, 0, 2, 4, 2.5, 1]
            )
        ]

        for clefExpectation in expected {
            for (index, key) in sharpKeys.enumerated() {
                try assertRhythmSectionKeySignature(
                    key: key,
                    clef: clefExpectation.clef,
                    expectedSymbol: .accidentalSharp,
                    expectedStaffOffsets: Array(clefExpectation.sharps.prefix(index + 1)),
                    expectedFrameCenterOffsets: Array(clefExpectation.sharps.prefix(index + 1))
                )
            }

            for (index, key) in flatKeys.enumerated() {
                let staffOffsets = Array(clefExpectation.flats.prefix(index + 1))
                try assertRhythmSectionKeySignature(
                    key: key,
                    clef: clefExpectation.clef,
                    expectedSymbol: .accidentalFlat,
                    expectedStaffOffsets: staffOffsets,
                    expectedFrameCenterOffsets: staffOffsets.map { $0 - 0.5 }
                )
            }
        }
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
        XCTAssertGreaterThanOrEqual(meterFrame.height, 54)
        XCTAssertGreaterThan(meterFrame.minX, changedMeasure.frame.minX)
        XCTAssertLessThan(meterFrame.maxX, changedMeasure.frame.midX)
    }

    func testSimpleChordSheetLocalMeterChangeReservesChordBodyLane() throws {
        var chart = Chart.blank(title: "Simple Time Chord Lane", measureCount: 3, layoutStyle: .simpleChordSheet)
        let secondMeasureID = chart.measures[1].id
        _ = chart.applyMeterChange(
            Meter(numerator: 3, denominator: 4),
            startingAt: secondMeasureID,
            scope: .toNextTimeSignature
        )
        try appendChord("C△7", to: secondMeasureID, in: &chart, atFraction: 0.05)

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstSystem = try XCTUnwrap(layout.systems.first)
        let changedMeasure = try XCTUnwrap(
            firstSystem.measures.first { $0.sourceMeasureID == secondMeasureID }
        )
        let meterFrame = try XCTUnwrap(changedMeasure.meterChangeFrame)
        let chordLayout = try XCTUnwrap(changedMeasure.chordLayouts.first)

        XCTAssertEqual(changedMeasure.meterChange, Meter(numerator: 3, denominator: 4))
        XCTAssertGreaterThanOrEqual(changedMeasure.chordBandFrame.minX, meterFrame.maxX + 8)
        XCTAssertGreaterThanOrEqual(chordLayout.frame.minX, changedMeasure.chordBandFrame.minX)
        XCTAssertFalse(chordLayout.frame.intersects(meterFrame))
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

    func testLeadSheetLayoutMarksTrailingBeamedSixteenthWithSecondaryBeamCue() throws {
        var chart = makeBlankLeadSheet()
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureRhythmMap(
            [.eighth, .sixteenth, .sixteenth, .dottedHalf],
            for: firstMeasureID
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let noteLayouts = firstMeasure.noteLayouts

        XCTAssertEqual(noteLayouts.map(\.symbolStyle), [.slash, .slash, .slash, .slash])
        XCTAssertNotNil(noteLayouts[0].beamEndPoint)
        XCTAssertEqual(noteLayouts[0].flagStyle, .none)
        XCTAssertNotNil(noteLayouts[1].beamEndPoint)
        XCTAssertEqual(noteLayouts[1].flagStyle, .double)
        XCTAssertNil(noteLayouts[2].beamEndPoint)
        XCTAssertEqual(noteLayouts[2].flagStyle, .secondaryBackward)
    }

    func testRhythmSectionDottedEighthSixteenthGroupKeepsTrailingSecondaryBeamCue() throws {
        var chart = Chart.blank(title: "Pocket", measureCount: 6, layoutStyle: .rhythmSectionSheet)
        let targetMeasureID = chart.measures[5].id
        XCTAssertTrue(chart.setMeasureRhythmMap(
            [.dottedQuarter, .eighth, .dottedEighth, .sixteenth, .quarter],
            for: targetMeasureID
        ))

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let targetMeasure = try XCTUnwrap(
            layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == targetMeasureID }
        )
        let noteLayouts = targetMeasure.noteLayouts

        XCTAssertEqual(noteLayouts.map(\.symbolStyle), [.slash, .slash, .slash, .slash, .slash])
        XCTAssertNotNil(noteLayouts[2].dotFrame)
        XCTAssertNotNil(noteLayouts[2].beamEndPoint)
        XCTAssertEqual(noteLayouts[2].flagStyle, .none)
        XCTAssertNil(noteLayouts[3].beamEndPoint)
        XCTAssertEqual(noteLayouts[3].flagStyle, .secondaryBackward)
        XCTAssertFalse(noteLayouts[3].stemGoesUp)
        let trailingStemStart = try XCTUnwrap(noteLayouts[3].stemStart)
        let trailingStemEnd = try XCTUnwrap(noteLayouts[3].stemEnd)
        XCTAssertGreaterThan(trailingStemEnd.y, trailingStemStart.y)
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

    private func assertRhythmSectionKeySignature(
        key: DocumentKey,
        clef: ChartClef,
        expectedSymbol: NotationGlyphCatalog.Symbol,
        expectedStaffOffsets: [CGFloat],
        expectedFrameCenterOffsets: [CGFloat],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var chart = Chart.draft(title: "Key Signature", key: key, layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Key Signature",
            key: key,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 4,
            clef: clef
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let system = try XCTUnwrap(layout.systems.first, file: file, line: line)
        let keySignatureLayouts = system.keySignatureLayouts
        let topLineY = try XCTUnwrap(system.staffLineYPositions.first, file: file, line: line)

        XCTAssertEqual(keySignatureLayouts.count, expectedStaffOffsets.count, file: file, line: line)
        XCTAssertEqual(
            keySignatureLayouts.map(\.symbol),
            Array(repeating: expectedSymbol, count: expectedStaffOffsets.count),
            file: file,
            line: line
        )
        XCTAssertEqual(keySignatureLayouts.map(\.staffOffset), expectedStaffOffsets, file: file, line: line)

        zip(
            keySignatureLayouts.map { ($0.frame.midY - topLineY) / $0.staffSpace },
            expectedFrameCenterOffsets
        ).forEach { actual, expected in
            XCTAssertEqual(actual, expected, accuracy: 0.001, file: file, line: line)
        }
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

    private func simpleChordPlacementGuideXs(
        for measureLayout: LeadSheetMeasureLayout,
        in chart: Chart,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [CGFloat] {
        let measureID = try XCTUnwrap(measureLayout.sourceMeasureID, file: file, line: line)
        let measure = try XCTUnwrap(chart.measure(id: measureID), file: file, line: line)
        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let guideFrame = LeadSheetChordPlacementGuidePolicy.guideFrame(
            for: measureLayout,
            referenceFrame: measureLayout.chordBandFrame
        )
        return LeadSheetChordPlacementGuidePolicy.guideXs(for: meter, in: guideFrame)
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

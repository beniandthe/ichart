import CoreGraphics
import XCTest
@testable import iChart
#if canImport(UIKit)
import PDFKit
import UIKit
#endif

final class LeadSheetNotationRendererTests: XCTestCase {
#if canImport(UIKit)
    func testChordTextFittingReducesAllTypographyProportionallyWithoutHorizontalCompression() {
        let uniformlyReduced = LeadSheetChordTextFitting.fit(
            availableWidth: 110,
            preferredRootFontSize: 46,
            minimumRootFontSize: 12,
            preferredNaturalWidth: 142
        )
        XCTAssertGreaterThan(uniformlyReduced.rootFontSize, 32)
        XCTAssertLessThan(uniformlyReduced.rootFontSize, 46)
        XCTAssertEqual(uniformlyReduced.horizontalScale, 1, accuracy: 0.001)
        XCTAssertLessThanOrEqual(uniformlyReduced.renderedWidth, 110.001)
        XCTAssertTrue(uniformlyReduced.meetsReadableMinimum)

        let smallerProportionalFit = LeadSheetChordTextFitting.fit(
            availableWidth: 80,
            preferredRootFontSize: 46,
            minimumRootFontSize: 12,
            preferredNaturalWidth: 142
        )
        XCTAssertEqual(smallerProportionalFit.rootFontSize, 46 * 80 / 142, accuracy: 0.001)
        XCTAssertEqual(smallerProportionalFit.horizontalScale, 1, accuracy: 0.001)
        XCTAssertEqual(smallerProportionalFit.renderedWidth, 80, accuracy: 0.001)
        XCTAssertTrue(smallerProportionalFit.meetsReadableMinimum)
    }

    func testChordTextFittingReportsImpossibleWidthWithoutCallingItReadable() {
        let fit = LeadSheetChordTextFitting.fit(
            availableWidth: 18,
            preferredRootFontSize: 46,
            minimumRootFontSize: 12,
            preferredNaturalWidth: 142
        )

        XCTAssertEqual(fit.rootFontSize, 46 * 18 / 142, accuracy: 0.001)
        XCTAssertFalse(fit.meetsReadableMinimum)
        XCTAssertGreaterThan(fit.minimumReadableWidth, 18)
        XCTAssertEqual(fit.horizontalScale, 1, accuracy: 0.001)
        XCTAssertEqual(fit.renderedWidth, 18, accuracy: 0.001)

        for invalidWidth in [CGFloat.zero, -1, .nan, .infinity] {
            let invalidFit = LeadSheetChordTextFitting.fit(
                availableWidth: invalidWidth,
                preferredRootFontSize: 46,
                minimumRootFontSize: 12,
                preferredNaturalWidth: 142
            )
            XCTAssertFalse(invalidFit.meetsReadableMinimum)
            XCTAssertTrue(invalidFit.rootFontSize.isFinite)
            XCTAssertTrue(invalidFit.horizontalScale.isFinite)
            XCTAssertTrue(invalidFit.renderedWidth.isFinite)
        }
    }

    @MainActor
    func testChosenChordCompressionKeepsFixedFontsAndIgnoresNarrowFramesAndNeighborCohorts() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let symbol = try ChordSymbolParser.parse("Dbmaj7(#11)/F#")
        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for fontFamily in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var chart = Chart.blank(title: "Manual Sizing", measureCount: 1, layoutStyle: layoutStyle)
                chart.setMatchedFontFamily(fontFamily)
                let renderer = LeadSheetNotationRenderer(chart: chart)
                let configuredSize = layoutStyle == .simpleChordSheet
                    ? ChartTypographyResolver.simpleChordPrimaryFontSize
                    : ChartTypographyResolver.structuredChordPrimaryFontSize
                let layouts = [CGFloat(0.35), 0.65, 1].map { scale in
                    LeadSheetChordLayout(
                        id: UUID(), text: symbol.displayText, symbol: symbol,
                        frame: CGRect(x: 0, y: 0, width: 1, height: 1),
                        horizontalCompressionScale: scale,
                        renderFontSize: configuredSize,
                        snapGuideTarget: .zero
                    )
                }
                XCTAssertEqual(renderer.fittedChordLayouts(layouts), layouts, "A neighboring chord must not override an explicit size")
                for layout in layouts {
                    let fit = renderer.chordRenderFit(for: layout)
                    XCTAssertEqual(fit.rootFontSize, configuredSize, accuracy: 0.001)
                    XCTAssertEqual(fit.horizontalScale, layout.horizontalCompressionScale)
                    XCTAssertEqual(fit.renderedWidth, fit.naturalWidth * layout.horizontalCompressionScale, accuracy: 0.001)
                    XCTAssertGreaterThan(fit.renderedWidth, layout.frame.width, "Overflow is not an instruction to shrink the chord")
                }
                var defaultLayout = try XCTUnwrap(layouts.first)
                defaultLayout.renderFontSize = configuredSize * 0.5
                XCTAssertEqual(renderer.chordRenderFit(for: defaultLayout).rootFontSize, configuredSize)
                for invalidScale in [CGFloat.nan, .infinity, -1, 4] {
                    defaultLayout.horizontalCompressionScale = invalidScale
                    let fit = renderer.chordRenderFit(for: defaultLayout)
                    XCTAssertEqual(fit.rootFontSize, configuredSize)
                    XCTAssertTrue((0.35...1).contains(fit.horizontalScale))
                }
            }
        }
    }

    @MainActor
    func testManualChordCompressionPersistsAndExportsNarrowerWidthWithIdenticalHeightInBothStylesAndFonts() async throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let scales = [0.35, 0.65, 1.0]
        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for fontFamily in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var chart = Chart.blank(title: "Manual Chord Compression", measureCount: 3, layoutStyle: layoutStyle)
                chart.setEngravingPreset(.compact)
                chart.setMatchedFontFamily(fontFamily)
                chart.systems = chart.measures.enumerated().map { index, measure in
                    ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced, measures: [measure])
                }
                for (index, scale) in scales.enumerated() {
                    let measureID = chart.systems[index].measures[0].id
                    if layoutStyle == .rhythmSectionSheet {
                        XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
                    }
                    try appendFittingChords(["Dbmaj7(#11)/F#"], fractions: [0.15], to: measureID, in: &chart)
                    chart.systems[index].measures[0].chordEvents[0].manualHorizontalScale = scale
                }
                let restored = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
                XCTAssertEqual(restored.measures.map { $0.chordEvents[0].manualHorizontalScale }, scales.map(Optional.some))
                let pageSize = CGSize(width: 932, height: 1_100)
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: restored, pageSize: pageSize)
                let renderer = LeadSheetNotationRenderer(chart: restored)
                let configuredSize = layoutStyle == .simpleChordSheet
                    ? ChartTypographyResolver.simpleChordPrimaryFontSize
                    : ChartTypographyResolver.structuredChordPrimaryFontSize
                let chords = try restored.measures.map { measure -> LeadSheetChordLayout in
                    let measureLayout = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measure.id })
                    return try XCTUnwrap(measureLayout.chordLayouts.first)
                }
                var renderedBounds: [CGRect] = []
                for (chord, scale) in zip(chords, scales) {
                    XCTAssertEqual(chord.renderFontSize, configuredSize)
                    let naturalSize = renderer.chordRenderSize(for: chord, primaryFontSize: configuredSize)
                    XCTAssertEqual(chord.frame.width, naturalSize.width * CGFloat(scale), accuracy: 1.5)
                    XCTAssertEqual(chord.frame.height, naturalSize.height, accuracy: 1.5)
                    let fit = renderer.chordRenderFit(for: chord)
                    XCTAssertEqual(fit.rootFontSize, configuredSize, accuracy: 0.001)
                    XCTAssertEqual(fit.horizontalScale, CGFloat(scale), accuracy: 0.001)
                    let bounds = try renderedChordBounds(chord, renderer: renderer)
                    renderedBounds.append(bounds)
                    try assertNativePDFChordTypographyMatchesChosenSize(
                        chord, renderer: renderer, layoutStyle: layoutStyle,
                        rootSize: configuredSize
                    )
                    let symbol = try XCTUnwrap(chord.symbol)
                    let roles = Set(ChartTypographyResolver.chordTokens(for: symbol).map(\.role))
                    XCTAssertTrue(roles.contains(.primaryText))
                    XCTAssertTrue(roles.contains(.suffixText))
                    XCTAssertTrue(roles.contains(.slashBassText))
                }
                XCTAssertLessThan(renderedBounds[0].width, renderedBounds[1].width)
                XCTAssertLessThan(renderedBounds[1].width, renderedBounds[2].width)
                for (bounds, scale) in zip(renderedBounds, scales) {
                    XCTAssertEqual(bounds.width, renderedBounds[2].width * CGFloat(scale), accuracy: 1)
                    XCTAssertEqual(bounds.height, renderedBounds[2].height, accuracy: 1)
                    XCTAssertEqual(bounds.minY, renderedBounds[2].minY, accuracy: 1)
                    XCTAssertEqual(bounds.maxY, renderedBounds[2].maxY, accuracy: 1)
                }
                try await saveDenseRenderProofIfRequested(
                    chart: restored,
                    label: "manual-chord-compression-\(layoutStyle.rawValue)-\(fontFamily.rawValue)",
                    expectedChords: chords.map(\.text)
                )
            }
        }
    }

    @MainActor
    func testWidthOnlyCompressionIncludesMusicSymbolsSlashBassAndFallbackTextWithoutMovingItsAnchor() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for fontFamily in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var chart = Chart.blank(title: "Complete Chord Compression", measureCount: 1, layoutStyle: layoutStyle)
                chart.setMatchedFontFamily(fontFamily)
                let renderer = LeadSheetNotationRenderer(chart: chart)
                let configuredSize = layoutStyle == .simpleChordSheet
                    ? ChartTypographyResolver.simpleChordPrimaryFontSize
                    : ChartTypographyResolver.structuredChordPrimaryFontSize
                let symbols = try ["Dbmaj7(#11)/F#", "Cdim7/G", "Cm7(b5)/Bb"].map { try ChordSymbolParser.parse($0) }
                let variants = symbols.map { ($0.displayText, Optional.some($0)) } + [("F-7/C", nil)]
                for (text, symbol) in variants {
                    var natural = LeadSheetChordLayout(
                        id: UUID(), text: text, symbol: symbol,
                        frame: CGRect(x: 71.25, y: 113.75, width: 1, height: 1),
                        renderFontSize: configuredSize, usesManualVisualPlacement: true,
                        snapGuideTarget: CGPoint(x: 71.25, y: 113.75)
                    )
                    let size = renderer.chordRenderSize(for: natural, primaryFontSize: configuredSize)
                    natural.frame.size = size
                    let baseline = try renderedChordBounds(natural, renderer: renderer)
                    for scale in [CGFloat(0.35), 0.65] {
                        var compressed = natural
                        compressed.horizontalCompressionScale = scale
                        compressed.frame.size.width = size.width * scale
                        let bounds = try renderedChordBounds(compressed, renderer: renderer)
                        XCTAssertEqual(bounds.width, baseline.width * scale, accuracy: 1)
                        XCTAssertEqual(bounds.height, baseline.height, accuracy: 1)
                        XCTAssertEqual(bounds.minY, baseline.minY, accuracy: 1)
                        XCTAssertEqual(bounds.maxY, baseline.maxY, accuracy: 1)
                        XCTAssertEqual(compressed.frame.minX, natural.frame.minX)
                        XCTAssertEqual(compressed.frame.midY, natural.frame.midY)
                        XCTAssertEqual(compressed.snapGuideTarget, natural.snapGuideTarget)
                        try assertNativePDFChordTypographyMatchesChosenSize(
                            compressed, renderer: renderer, layoutStyle: layoutStyle, rootSize: configuredSize
                        )
                    }
                }
            }
        }
    }

    @MainActor
    func testFineChordPlacementPersistsAndExportsWithTheSameVisualAnchorInBothStyles() async throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for fontFamily in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var chart = Chart.blank(title: "Fine Chord Placement", measureCount: 4, layoutStyle: layoutStyle)
                chart.setEngravingPreset(.compact)
                chart.setMatchedFontFamily(fontFamily)
                let measureID = try XCTUnwrap(chart.measures.first?.id)
                if layoutStyle == .rhythmSectionSheet {
                    XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
                }
                try appendFittingChords(["C7", "Fmaj7", "G-7"], fractions: [0.05, 0.35, 0.65], to: measureID, in: &chart)
                // This is the export renderer's layout canvas, not a separate
                // test-only drawing geometry.
                let pageSize = CGSize(width: 932, height: 1_100)
                let before = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                let beforeMeasure = try XCTUnwrap(before.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let chordID = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents[1].id)
                let beforeChord = try XCTUnwrap(beforeMeasure.chordLayouts.first { $0.id == chordID })
                let sourceChord = try XCTUnwrap(chart.chordEvent(id: chordID))
                let intendedLeftX = beforeChord.frame.minX + 1.25
                let visualFraction = Double((intendedLeftX - beforeMeasure.chordBandFrame.minX) / beforeMeasure.chordBandFrame.width)
                XCTAssertTrue(chart.moveChordEventInCommittedChordLane(
                    chordID, to: measureID, atFraction: visualFraction,
                    visualFraction: visualFraction, preserveMusicalPlacement: true
                ))
                let restored = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
                let after = LeadSheetPageLayoutEngine.pageLayout(for: restored, pageSize: pageSize)
                let afterMeasure = try XCTUnwrap(after.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                XCTAssertEqual(after.systems.flatMap(\.measures).map(\.frame), before.systems.flatMap(\.measures).map(\.frame))
                let renderer = LeadSheetNotationRenderer(chart: restored)
                let fitted = renderer.fittedChordLayouts(afterMeasure.chordLayouts)
                let moved = try XCTUnwrap(fitted.first { $0.id == chordID })
                XCTAssertTrue(moved.usesManualVisualPlacement)
                XCTAssertEqual(moved.frame.minX, intendedLeftX, accuracy: 0.001)
                var expectedChord = sourceChord
                expectedChord.manualVisualLaneFraction = visualFraction
                XCTAssertEqual(restored.chordEvent(id: chordID), expectedChord)
                for chordLayout in fitted {
                    try assertWidthOnlyChordRender(chordLayout, in: afterMeasure, renderer: renderer, context: "fine placement, \(layoutStyle), \(fontFamily)")
                }
                try await saveDenseRenderProofIfRequested(
                    chart: restored,
                    label: "fine-chord-placement-\(layoutStyle.rawValue)-\(fontFamily.rawValue)",
                    expectedChords: fitted.map(\.text)
                )
            }
        }
    }

    @MainActor
    func testSavedFourChordMeasureKeepsLegacyManualSizeWithoutShrinkingOtherChords() async throws {
        let originalChart = try savedFourChordFittingChart()
        let measureID = try XCTUnwrap(originalChart.measures.first?.id)
        let lastChordID = try XCTUnwrap(originalChart.measures.first?.chordEvents.last?.id)

        XCTAssertEqual(originalChart.chordEvent(id: lastChordID)?.manualDisplayWidth, 18)
        for fontFamily in ChartFontFamilyPreset.selectableCases {
            var chart = originalChart
            chart.setMatchedFontFamily(fontFamily)
            for pageWidth in [CGFloat(760), 900] {
                let layout = LeadSheetPageLayoutEngine.pageLayout(
                    for: chart,
                    pageSize: CGSize(width: pageWidth, height: 1_400)
                )
                let measure = try XCTUnwrap(
                    layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID }
                )
                XCTAssertEqual(measure.chordLayouts.map(\.text), ["B7", "G△7", "A-9", "D-7"])
                try assertMeasureGeometryMatchesChordlessChart(chart, layout: layout, pageWidth: pageWidth)
                let renderer = LeadSheetNotationRenderer(chart: chart)
                let fittedLayouts = renderer.fittedChordLayouts(measure.chordLayouts)
                let automaticSizes = fittedLayouts.filter { !$0.usesManualDisplayWidth }.map { renderer.chordRenderFit(for: $0).rootFontSize }
                XCTAssertEqual(automaticSizes.count, 3)
                for size in automaticSizes {
                    XCTAssertEqual(size, ChartTypographyResolver.simpleChordPrimaryFontSize, accuracy: 0.001)
                }
                for chordLayout in fittedLayouts {
                    try assertWidthOnlyChordRender(
                        chordLayout,
                        in: measure,
                        renderer: renderer,
                        context: "saved fixture, \(fontFamily), width \(pageWidth)"
                    )
                }
                XCTAssertEqual(chart.chordEvent(id: lastChordID)?.manualDisplayWidth, 18)
                try await saveDenseRenderProofIfRequested(
                    chart: chart,
                    label: "saved-four-chords-\(fontFamily.rawValue)-\(Int(pageWidth))",
                    expectedChords: measure.chordLayouts.map(\.text)
                )
            }
        }
    }

    @MainActor
    func testSavedFourChordSizeResetKeepsGeometryAndRestoresConfiguredSizeWithoutAutoFit() async throws {
        let manualChart = try savedFourChordFittingChart()
        let measureID = try XCTUnwrap(manualChart.measures.first?.id)
        var automaticChart = manualChart
        automaticChart.systems[0].measures[0].chordEvents[3].manualDisplayWidth = nil
        var expectedChart = manualChart
        expectedChart.systems[0].measures[0].chordEvents[3].manualDisplayWidth = nil
        XCTAssertEqual(automaticChart, expectedChart)
        XCTAssertEqual(manualChart.systems[0].measures[0].chordEvents[3].manualDisplayWidth, 18)

        for fontFamily in ChartFontFamilyPreset.selectableCases {
            var chart = automaticChart
            chart.setMatchedFontFamily(fontFamily)
            for pageWidth in [CGFloat(760), 900] {
                let pageSize = CGSize(width: pageWidth, height: 1_400)
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                let originalLayout = LeadSheetPageLayoutEngine.pageLayout(for: manualChart, pageSize: pageSize)
                XCTAssertEqual(layout.systems.flatMap(\.measures).map(\.frame), originalLayout.systems.flatMap(\.measures).map(\.frame))
                try assertMeasureGeometryMatchesChordlessChart(chart, layout: layout, pageWidth: pageWidth)
                let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                let originalMeasure = try XCTUnwrap(originalLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
                XCTAssertEqual(measure.chordLayouts.map(\.snapGuideTarget), originalMeasure.chordLayouts.map(\.snapGuideTarget))
                XCTAssertEqual(chart.systems[0].measures[0].chordEvents.map(\.startPosition), manualChart.systems[0].measures[0].chordEvents.map(\.startPosition))
                let renderer = LeadSheetNotationRenderer(chart: chart)
                let fittedLayouts = renderer.fittedChordLayouts(measure.chordLayouts)
                XCTAssertEqual(fittedLayouts.map(\.text), ["B7", "G△7", "A-9", "D-7"])
                XCTAssertTrue(fittedLayouts.allSatisfy { !$0.usesManualDisplayWidth })
                let configuredSize = ChartTypographyResolver.simpleChordPrimaryFontSize
                for chordLayout in fittedLayouts {
                    XCTAssertEqual(renderer.chordRenderFit(for: chordLayout).rootFontSize, configuredSize, accuracy: 0.001)
                    try assertWidthOnlyChordRender(chordLayout, in: measure, renderer: renderer, context: "automatic saved fixture, \(fontFamily), \(pageWidth)")
                }
                if fontFamily == .finaleBroadway || fontFamily == .petaluma {
                    try await saveDenseRenderProofIfRequested(
                        chart: chart,
                        label: "saved-four-chords-automatic-\(fontFamily.rawValue)-\(Int(pageWidth))",
                        expectedChords: fittedLayouts.map(\.text)
                    )
                }
            }
        }
    }

    @MainActor
    func testFourComplexChordsKeepMeasureWidthsAndConfiguredTypographyEvenWhenCrowded() async throws {
        let chordTexts = ["Db7(#11)/F#", "Bbmaj7", "F-7/C", "G7(b9)"]
        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var originalChart = Chart.blank(
                title: "Dense Complex Chord Fitting",
                measureCount: 4,
                layoutStyle: layoutStyle
            )
            originalChart.setEngravingPreset(.compact)
            let measureID = try XCTUnwrap(originalChart.measures.first?.id)
            if layoutStyle == .rhythmSectionSheet {
                XCTAssertTrue(originalChart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measureID))
            }
            try appendFittingChords(chordTexts, fractions: [0, 0.25, 0.5, 0.75], to: measureID, in: &originalChart)

            for fontFamily in ChartFontFamilyPreset.selectableCases {
                var chart = originalChart
                chart.setMatchedFontFamily(fontFamily)
                for pageWidth in [CGFloat(760), 900] {
                    let layout = LeadSheetPageLayoutEngine.pageLayout(
                        for: chart,
                        pageSize: CGSize(width: pageWidth, height: 1_400)
                    )
                    let measure = try XCTUnwrap(
                        layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID }
                    )
                    XCTAssertEqual(measure.chordLayouts.count, 4)
                    XCTAssertEqual(Set(measure.chordLayouts.map(\.id)), Set(chart.measure(id: measureID)?.chordEvents.map(\.id) ?? []))
                    try assertMeasureGeometryMatchesChordlessChart(chart, layout: layout, pageWidth: pageWidth)
                    let renderer = LeadSheetNotationRenderer(chart: chart)
                    let fittedLayouts = renderer.fittedChordLayouts(measure.chordLayouts)
                    let configuredSize = layoutStyle == .simpleChordSheet
                        ? ChartTypographyResolver.simpleChordPrimaryFontSize
                        : ChartTypographyResolver.structuredChordPrimaryFontSize
                    for chordLayout in fittedLayouts {
                        XCTAssertEqual(renderer.chordRenderFit(for: chordLayout).rootFontSize, configuredSize, accuracy: 0.001)
                        try assertWidthOnlyChordRender(
                            chordLayout,
                            in: measure,
                            renderer: renderer,
                            context: "\(layoutStyle), \(fontFamily), width \(pageWidth)"
                        )
                        // At configured size these authored placements can
                        // overlap. Verify every complete chord and its chosen
                        // typography in an isolated native PDF, rather than
                        // treating interleaved full-page extraction as a missing
                        // glyph or silently restoring automatic fitting.
                        try assertNativePDFChordTypographyMatchesChosenSize(
                            chordLayout, renderer: renderer, layoutStyle: layoutStyle,
                            rootSize: configuredSize
                        )
                    }
                    try await saveDenseRenderProofIfRequested(
                        chart: chart,
                        label: "complex-four-chords-\(layoutStyle.rawValue)-\(fontFamily.rawValue)-\(Int(pageWidth))",
                        expectedChords: [] // Preserve visibly crowded export for inspection; not a readability claim.
                    )
                }
            }
        }
    }

    private func savedFourChordFittingChart() throws -> Chart {
        var chart = Chart.blank(title: "Saved Four Chord Fitting", measureCount: 5, layoutStyle: .simpleChordSheet)
        chart.setEngravingPreset(.compact)
        chart.setMatchedFontFamily(.finaleBroadway)
        let measureIDs = chart.measures.map(\.id)
        for (measureID, width) in zip(measureIDs, [128.16774193548386, 128.16774193548386, 128.16774193548386, 108.29677419354839, 96]) {
            _ = chart.setMeasureManualLayoutWidth(CGFloat(width), for: measureID)
        }
        var measures = chart.measures
        measures[4].authoringState = .open
        chart.systems = [
            ChartSystem(id: UUID(), index: 0, spacingMode: .automatic, lineBreakRule: .forced, measures: Array(measures.prefix(4))),
            ChartSystem(id: UUID(), index: 1, spacingMode: .automatic, lineBreakRule: .forced, measures: [measures[4]])
        ]
        try appendFittingChords(
            ["B7", "G△7", "A-9", "D-7"],
            fractions: [0.0744336569579288, 0.3065149136577708, 0.5044323078636984, 0.5376766091051806],
            to: measureIDs[0],
            in: &chart
        )
        let savedPositions = [
            BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
            BeatPosition(beat: 2, subdivision: 14, subdivisionsPerBeat: 64),
            BeatPosition(beat: 3, subdivision: 0, subdivisionsPerBeat: 1),
            BeatPosition(beat: 3, subdivision: 10, subdivisionsPerBeat: 64)
        ]
        for (index, position) in savedPositions.enumerated() {
            chart.systems[0].measures[0].chordEvents[index].startPosition = position
        }
        let lastChordID = try XCTUnwrap(chart.measure(id: measureIDs[0])?.chordEvents.last?.id)
        _ = chart.setChordEventManualDisplayWidth(18, for: lastChordID)
        return chart
    }

    private func appendFittingChords(
        _ texts: [String],
        fractions: [Double],
        to measureID: UUID,
        in chart: inout Chart
    ) throws {
        XCTAssertEqual(texts.count, fractions.count)
        for (text, fraction) in zip(texts, fractions) {
            let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse(text), rawInput: text, to: measureID, atFraction: fraction
            ))
            if chart.layoutStyle == .simpleChordSheet {
                _ = chart.setChordEventManualLaneFraction(fraction, for: chordID)
            }
        }
    }

    @MainActor
    private func assertWidthOnlyChordRender(
        _ chordLayout: LeadSheetChordLayout,
        in measure: LeadSheetMeasureLayout,
        renderer: LeadSheetNotationRenderer,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let message = "\(context), \(chordLayout.text)"
        let fit = renderer.chordRenderFit(for: chordLayout)
        XCTAssertGreaterThan(fit.rootFontSize, 0, message, file: file, line: line)
        XCTAssertTrue(fit.rootFontSize.isFinite, message, file: file, line: line)
        XCTAssertEqual(fit.horizontalScale, chordLayout.horizontalCompressionScale, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(fit.meetsReadableMinimum, fit.rootFontSize + 0.001 >= ChartTypographyResolver.minimumPracticalChordPrimaryFontSize, message, file: file, line: line)
        XCTAssertEqual(fit.renderedWidth, chordLayout.frame.width, accuracy: 1.5, message, file: file, line: line)
        let pixelBounds = try renderedChordBounds(chordLayout, renderer: renderer)
        let naturalSize = renderer.chordRenderSize(for: chordLayout, primaryFontSize: fit.rootFontSize)
        let padding: CGFloat = 8
        XCTAssertGreaterThan(pixelBounds.width, 1, message, file: file, line: line)
        XCTAssertGreaterThan(pixelBounds.height, 1, message, file: file, line: line)
        XCTAssertGreaterThanOrEqual(pixelBounds.minX, padding - 1.5, message, file: file, line: line)
        XCTAssertLessThanOrEqual(pixelBounds.maxX, padding + fit.renderedWidth + 1.5, message, file: file, line: line)
        XCTAssertGreaterThanOrEqual(pixelBounds.minY, padding - 1.5, message, file: file, line: line)
        XCTAssertLessThanOrEqual(pixelBounds.maxY, padding + naturalSize.height + 1.5, message, file: file, line: line)
    }

    @MainActor
    private func renderedChordBounds(_ chordLayout: LeadSheetChordLayout, renderer: LeadSheetNotationRenderer) throws -> CGRect {
        let rootSize = renderer.chordRenderFit(for: chordLayout).rootFontSize
        let naturalSize = renderer.chordRenderSize(for: chordLayout, primaryFontSize: rootSize)
        let renderedSize = CGSize(width: naturalSize.width * chordLayout.horizontalCompressionScale, height: naturalSize.height)
        let padding: CGFloat = 8
        var localLayout = chordLayout
        localLayout.frame = CGRect(origin: CGPoint(x: padding, y: padding), size: renderedSize)
        localLayout.fitFrame = localLayout.frame
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: renderedSize.width + padding * 2, height: renderedSize.height + padding * 2),
            format: format
        ).image { _ in renderer.drawChord(localLayout) }
        return try opaquePixelBounds(in: image)
    }

    @MainActor
    private func assertNativePDFChordTypographyMatchesChosenSize(
        _ chordLayout: LeadSheetChordLayout,
        renderer: LeadSheetNotationRenderer,
        layoutStyle: ChartLayoutStyle,
        rootSize: CGFloat
    ) throws {
        let padding: CGFloat = 8
        let naturalSize = renderer.chordRenderSize(for: chordLayout, primaryFontSize: rootSize)
        let renderedSize = CGSize(width: naturalSize.width * chordLayout.horizontalCompressionScale, height: naturalSize.height)
        var localLayout = chordLayout
        localLayout.frame = CGRect(origin: CGPoint(x: padding, y: padding), size: renderedSize)
        localLayout.fitFrame = localLayout.frame
        let data = UIGraphicsPDFRenderer(bounds: CGRect(
            x: 0, y: 0, width: renderedSize.width + padding * 2, height: renderedSize.height + padding * 2
        )).pdfData { context in
            context.beginPage()
            renderer.drawChord(localLayout)
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        let documentText = document.string ?? ""
        let captured = try ChordPDFTextTransformCapture.result(in: data)
        let transforms = captured.metrics
        let tokens = chordLayout.symbol.map { ChartTypographyResolver.chordTokens(for: $0) } ?? []
        let missingPathSymbols = tokens.filter { $0.role == .musicSymbol && !documentText.contains($0.text) }
        if missingPathSymbols.isEmpty {
            XCTAssertPDFExtractedTextContains(documentText, visibleChordText: chordLayout.text)
        } else {
            // Vector symbols intentionally have no PDF text operator. Require
            // their actual stroked paths in this isolated chord export, while
            // still requiring all root, suffix, alteration, and bass text.
            let textTokens = tokens.filter { $0.role != .musicSymbol }.map(\.text).joined()
            XCTAssertPDFExtractedTextContains(documentText, visibleChordText: textTokens)
            XCTAssertGreaterThanOrEqual(captured.strokedPathCount, missingPathSymbols.count, "Every non-extractable music symbol must have a rendered vector path")
        }
        let suffixSize = layoutStyle == .simpleChordSheet
            ? ChartTypographyResolver.simpleChordSuffixFontSize(primarySize: rootSize)
            : ChartTypographyResolver.structuredChordSuffixFontSize(primarySize: rootSize)
        let bassSize = layoutStyle == .simpleChordSheet
            ? ChartTypographyResolver.simpleChordSlashBassFontSize(primarySize: rootSize)
            : ChartTypographyResolver.structuredChordSlashBassFontSize(primarySize: rootSize)
        let roles = chordLayout.symbol.map {
            Set(ChartTypographyResolver.chordTokens(for: $0).map(\.role))
        } ?? [.primaryText, .suffixText]
        var expectedSizes = [rootSize]
        if roles.contains(.suffixText) { expectedSizes.append(suffixSize) }
        if roles.contains(.slashBassText) { expectedSizes.append(bassSize) }
        XCTAssertFalse(transforms.isEmpty, "Native PDF must retain actual text operators, not a screenshot")
        for expectedSize in expectedSizes {
            XCTAssertTrue(
                transforms.contains { abs($0.verticalPointSize - expectedSize) < 0.1 },
                "Native PDF must include fixed root, suffix, and slash-bass vertical font transforms; expected \(expectedSize), got \(transforms.map(\.verticalPointSize))"
            )
        }
        // PDFKit's attributed-font pointSize averages the transformed x/y
        // magnitudes (46 at 35% width becomes 31.05), so it cannot prove fixed
        // height. The native operators retain independent horizontal/vertical
        // magnitudes and are the correct evidence for width-only compression.
        for transform in transforms {
            XCTAssertEqual(transform.horizontalToVerticalRatio, chordLayout.horizontalCompressionScale, accuracy: 0.001)
            XCTAssertTrue(expectedSizes.contains { abs($0 - transform.verticalPointSize) < 0.1 }, "PDF vertical text transform must preserve a configured font height: \(transform.verticalPointSize)")
        }
    }

    private func assertMeasureGeometryMatchesChordlessChart(_ chart: Chart, layout: LeadSheetPageLayout, pageWidth: CGFloat) throws {
        var chordless = chart
        for systemIndex in chordless.systems.indices {
            for measureIndex in chordless.systems[systemIndex].measures.indices {
                chordless.systems[systemIndex].measures[measureIndex].chordEvents = []
            }
        }
        let reference = LeadSheetPageLayoutEngine.pageLayout(for: chordless, pageSize: CGSize(width: pageWidth, height: 1_400))
        XCTAssertEqual(layout.systems.map { $0.measures.compactMap(\.sourceMeasureID) }, reference.systems.map { $0.measures.compactMap(\.sourceMeasureID) })
        for (measure, emptyMeasure) in zip(layout.systems.flatMap(\.measures), reference.systems.flatMap(\.measures)) {
            XCTAssertEqual(measure.frame, emptyMeasure.frame, "Chord text must never change measure width")
            XCTAssertEqual(measure.staffFrame, emptyMeasure.staffFrame)
            XCTAssertEqual(measure.trailingBarlineFrame, emptyMeasure.trailingBarlineFrame)
        }
    }

    @MainActor
    private func saveDenseRenderProofIfRequested(chart: Chart, label: String, expectedChords: [String]) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = ["ICHART_DENSE_RENDER_PROOF_DIR", "TEST_RUNNER_ICHART_DENSE_RENDER_PROOF_DIR"]
            .compactMap({ environment[$0] })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(label, isDirectory: true)
        let exported = try await PDFChartExporter(exportDirectory: directory).exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exported.url))
        for chord in expectedChords {
            XCTAssertPDFExtractedTextContains(document.string ?? "", visibleChordText: chord)
        }
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent("pdf-preview.png"))
    }

    func testSecondaryBeamOffsetMovesTowardNoteheads() {
        let beamThickness: CGFloat = 4

        XCTAssertGreaterThan(
            LeadSheetNotationRenderer.secondaryBeamOffset(stemGoesUp: true, beamThickness: beamThickness),
            0
        )
        XCTAssertLessThan(
            LeadSheetNotationRenderer.secondaryBeamOffset(stemGoesUp: false, beamThickness: beamThickness),
            0
        )
    }

    @MainActor
    func testRoadmapCodaHasMatchedVisualSizeInBroadwayAndPetalumaForBothSheetStyles() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for markerScale in [CGFloat(RoadmapObject.minimumScale), CGFloat(RoadmapObject.maximumScale)] {
                let broadwayBounds = try roadmapGlyphBounds(
                    glyph: NotationGlyphCatalog.coda,
                    notationFont: .finaleBroadway,
                    layoutStyle: layoutStyle,
                    markerScale: markerScale
                )
                let petalumaBounds = try roadmapGlyphBounds(
                    glyph: NotationGlyphCatalog.coda,
                    notationFont: .petaluma,
                    layoutStyle: layoutStyle,
                    markerScale: markerScale
                )

                XCTAssertEqual(
                    broadwayBounds.height,
                    petalumaBounds.height,
                    accuracy: max(0.5, broadwayBounds.height * 0.04),
                    "Expected matched coda height for \(layoutStyle) at marker scale \(markerScale)"
                )
                let markerFrameHeight = (layoutStyle == .simpleChordSheet ? CGFloat(44) : 32) * markerScale
                XCTAssertGreaterThan(broadwayBounds.height, markerFrameHeight * 0.38)
                XCTAssertLessThan(broadwayBounds.height, markerFrameHeight * 0.62)
                XCTAssertGreaterThan(petalumaBounds.height, markerFrameHeight * 0.38)
                XCTAssertLessThan(petalumaBounds.height, markerFrameHeight * 0.62)
            }
        }

        XCTAssertGreaterThan(
            LeadSheetRoadmapMarkerTypography.notationSymbolNormalizationScale(
                for: NotationGlyphCatalog.coda,
                notationFont: .finaleBroadway
            ),
            1.2
        )
        XCTAssertLessThan(
            LeadSheetRoadmapMarkerTypography.notationSymbolNormalizationScale(
                for: NotationGlyphCatalog.coda,
                notationFont: .petaluma
            ),
            0.75
        )
    }

    @MainActor
    func testRenderedRoadmapCodaHasMatchedVisualSizeInBroadwayAndPetalumaForBothSheetStyles() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for markerScale in [CGFloat(RoadmapObject.minimumScale), CGFloat(RoadmapObject.maximumScale)] {
                let broadwayBounds = try renderedRoadmapMarkerBounds(
                    type: .codaMarker,
                    notationFont: .finaleBroadway,
                    layoutStyle: layoutStyle,
                    markerScale: markerScale
                )
                let petalumaBounds = try renderedRoadmapMarkerBounds(
                    type: .codaMarker,
                    notationFont: .petaluma,
                    layoutStyle: layoutStyle,
                    markerScale: markerScale
                )

                XCTAssertEqual(
                    broadwayBounds.height,
                    petalumaBounds.height,
                    accuracy: max(1, broadwayBounds.height * 0.06),
                    "Expected the fully rendered Coda to have matched height for \(layoutStyle) at marker scale \(markerScale)"
                )
            }
        }
    }

    @MainActor
    func testRenderedRoadmapSegnoHasMatchedVisualSizeInBroadwayAndPetalumaForBothSheetStyles() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for markerScale in [CGFloat(RoadmapObject.minimumScale), CGFloat(RoadmapObject.maximumScale)] {
                let broadwayBounds = try renderedRoadmapMarkerBounds(
                    type: .segno,
                    notationFont: .finaleBroadway,
                    layoutStyle: layoutStyle,
                    markerScale: markerScale
                )
                let petalumaBounds = try renderedRoadmapMarkerBounds(
                    type: .segno,
                    notationFont: .petaluma,
                    layoutStyle: layoutStyle,
                    markerScale: markerScale
                )

                XCTAssertEqual(
                    broadwayBounds.height,
                    petalumaBounds.height,
                    accuracy: max(1, broadwayBounds.height * 0.06),
                    "Expected the fully rendered Segno to have matched height for \(layoutStyle) at marker scale \(markerScale)"
                )
            }
        }
    }

    @MainActor
    func testRoadmapSegnoHasMatchedVisualSizeInBroadwayAndPetalumaForBothSheetStyles() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()

        for layoutStyle in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let broadwayBounds = try roadmapGlyphBounds(
                glyph: NotationGlyphCatalog.segno,
                notationFont: .finaleBroadway,
                layoutStyle: layoutStyle,
                markerScale: CGFloat(RoadmapObject.maximumScale)
            )
            let petalumaBounds = try roadmapGlyphBounds(
                glyph: NotationGlyphCatalog.segno,
                notationFont: .petaluma,
                layoutStyle: layoutStyle,
                markerScale: CGFloat(RoadmapObject.maximumScale)
            )

            XCTAssertEqual(
                broadwayBounds.height,
                petalumaBounds.height,
                accuracy: max(0.5, broadwayBounds.height * 0.04),
                "Expected matched segno height for \(layoutStyle)"
            )
            let markerFrameHeight = (layoutStyle == .simpleChordSheet ? CGFloat(44) : 32)
                * CGFloat(RoadmapObject.maximumScale)
            XCTAssertGreaterThan(broadwayBounds.height, markerFrameHeight * 0.38)
            XCTAssertLessThan(broadwayBounds.height, markerFrameHeight * 0.62)
            XCTAssertGreaterThan(petalumaBounds.height, markerFrameHeight * 0.38)
            XCTAssertLessThan(petalumaBounds.height, markerFrameHeight * 0.62)
        }
    }

    @MainActor
    private func roadmapGlyphBounds(
        glyph: String,
        notationFont: NotationFontPreset,
        layoutStyle: ChartLayoutStyle,
        markerScale: CGFloat
    ) throws -> CGRect {
        let baseFontSize = LeadSheetRoadmapMarkerTypography.baseFontSize(
            layoutStyle: layoutStyle,
            type: glyph == NotationGlyphCatalog.coda ? .codaMarker : .segno,
            scale: markerScale
        )
        let pointSize = LeadSheetRoadmapMarkerTypography.notationSymbolPointSize(
            for: glyph,
            baseFontSize: baseFontSize,
            notationFont: notationFont
        )
        let font = try XCTUnwrap(UIFont(name: notationFont.postScriptName, size: pointSize))
        let path = try XCTUnwrap(NotationGlyphPathCache.path(for: glyph, font: font))
        return path.boundingBoxOfPath
    }

    @MainActor
    private func renderedRoadmapMarkerBounds(
        type: RoadmapType,
        notationFont: NotationFontPreset,
        layoutStyle: ChartLayoutStyle,
        markerScale: CGFloat
    ) throws -> CGRect {
        var chart = Chart.blank(
            title: "Roadmap Marker Rendering",
            measureCount: 1,
            layoutStyle: layoutStyle
        )
        chart.notationFont = notationFont

        let baseWidth: CGFloat = layoutStyle == .simpleChordSheet ? 42 : 28
        let baseHeight: CGFloat = layoutStyle == .simpleChordSheet ? 44 : 32
        let markerFrame = CGRect(
            x: 32,
            y: 32,
            width: baseWidth * markerScale,
            height: baseHeight * markerScale
        )
        let markerLayout = LeadSheetRoadmapMarkerLayout(
            roadmapObjectID: UUID(),
            type: type,
            text: type.defaultDisplayText,
            frame: markerFrame,
            movementFrame: markerFrame,
            anchorMeasureID: try XCTUnwrap(chart.measures.first?.id),
            scale: markerScale
        )
        let labelFrame = LeadSheetRoadmapMarkerLabelGeometry.labelFrame(for: markerLayout)
        let canvasSize = CGSize(
            width: max(160, labelFrame.maxX + 32),
            height: max(160, labelFrame.maxY + 32)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
            LeadSheetNotationRenderer(chart: chart).drawRoadmapMarker(markerLayout)
        }

        return try opaquePixelBounds(in: image)
    }

    private func opaquePixelBounds(in image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                guard alpha > 8 else {
                    continue
                }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        XCTAssertGreaterThanOrEqual(maxX, minX)
        XCTAssertGreaterThanOrEqual(maxY, minY)
        let imageScale = image.scale
        return CGRect(
            x: CGFloat(minX) / imageScale,
            y: CGFloat(minY) / imageScale,
            width: CGFloat(maxX - minX + 1) / imageScale,
            height: CGFloat(maxY - minY + 1) / imageScale
        )
    }
#endif

    func testBarlineMetricsStayIndependentFromJazzFontEngravingDefaults() {
        let staffSpace: CGFloat = 24
        let structuralThinWidth = LeadSheetBarlineMetrics.thinWidth(
            staffSpace: staffSpace,
            strokeScale: 1
        )
        let museJazzFontThinWidth = CGFloat(
            NotationFontPreset.museJazz.smuflEngravingDefaults.thinBarlineThickness
        ) * staffSpace

        XCTAssertLessThan(structuralThinWidth, museJazzFontThinWidth)
        XCTAssertEqual(
            structuralThinWidth,
            LeadSheetBarlineMetrics.thinWidth(staffSpace: staffSpace, strokeScale: 1),
            accuracy: 0.001
        )
    }

    func testSimpleRepeatDotsClearBarlinesWhileMarkersStayCompact() {
        let staffSpace: CGFloat = 24
        let lineWidth = LeadSheetBarlineMetrics.repeatLineWidth(
            staffSpace: staffSpace,
            strokeScale: 1,
            layoutStyle: .simpleChordSheet
        )
        let dotRadius = LeadSheetBarlineMetrics.repeatDotRadius(
            staffSpace: staffSpace,
            layoutStyle: .simpleChordSheet
        )
        let dotOffset = LeadSheetBarlineMetrics.repeatDotOffset(
            thinLineWidth: lineWidth,
            dotRadius: dotRadius,
            staffSpace: staffSpace,
            layoutStyle: .simpleChordSheet
        )
        let simpleSeparation = LeadSheetBarlineMetrics.repeatSeparation(
            staffSpace: staffSpace,
            layoutStyle: .simpleChordSheet
        )

        XCTAssertGreaterThan(dotOffset - dotRadius, lineWidth / 2)
        XCTAssertLessThan(simpleSeparation, LeadSheetBarlineMetrics.separation(staffSpace: staffSpace))
    }

    func testRepeatLineWidthUsesMatchedStructuralBarlines() {
        let staffSpace: CGFloat = 24
        let thinLineWidth = LeadSheetBarlineMetrics.thinWidth(
            staffSpace: staffSpace,
            strokeScale: 1
        )
        let simpleLineWidth = LeadSheetBarlineMetrics.repeatLineWidth(
            staffSpace: staffSpace,
            strokeScale: 1,
            layoutStyle: .simpleChordSheet
        )
        let rhythmLineWidth = LeadSheetBarlineMetrics.repeatLineWidth(
            staffSpace: staffSpace,
            strokeScale: 1,
            layoutStyle: .rhythmSectionSheet
        )

        XCTAssertEqual(simpleLineWidth, max(thinLineWidth * 1.65, 1.55), accuracy: 0.001)
        XCTAssertEqual(rhythmLineWidth, thinLineWidth, accuracy: 0.001)
        XCTAssertLessThan(rhythmLineWidth, LeadSheetBarlineMetrics.thickWidth(staffSpace: staffSpace, strokeScale: 1))
    }

    #if canImport(UIKit)
    func testRhythmLeadingRepeatKeepsStaffLinesBehindSetupNotation() throws {
        var chart = Chart.blank(
            title: "Rhythm Repeat Staff",
            key: .dFlatMajor,
            measureCount: 4,
            layoutStyle: .rhythmSectionSheet
        )
        let measureIDs = chart.measures.map(\.id)
        XCTAssertNotNil(
            chart.addRepeatSpan(
                startMeasureID: try XCTUnwrap(measureIDs.first),
                endMeasureID: try XCTUnwrap(measureIDs.last)
            )
        )

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
        )
        let system = try XCTUnwrap(layout.systems.first)
        let span = LeadSheetStaffLineGeometry.horizontalSpan(
            for: system,
            layoutStyle: chart.layoutStyle
        )

        XCTAssertEqual(system.staffLineYPositions.count, 5)
        XCTAssertGreaterThan(span.maxX - span.minX, system.frame.width * 0.7)
        XCTAssertTrue(span.minX.isFinite)
        XCTAssertTrue(span.maxX.isFinite)
        let clefFrame = try XCTUnwrap(system.clefFrame)
        let firstKeyFrame = try XCTUnwrap(system.keySignatureLayouts.first?.frame)
        let timeSignatureFrame = try XCTUnwrap(system.timeSignatureFrame)
        let leadingRepeatFrame = try XCTUnwrap(
            system.measures.first?.repeatMarkerLayouts.first(where: { $0.edge == .leading })?.frame
        )
        XCTAssertEqual(span.minX, system.frame.minX, accuracy: 0.001)
        XCTAssertLessThanOrEqual(span.minX, clefFrame.minX)
        XCTAssertLessThanOrEqual(span.minX, firstKeyFrame.minX)
        XCTAssertLessThanOrEqual(span.minX, timeSignatureFrame.minX)
        XCTAssertGreaterThan(leadingRepeatFrame.minX, span.minX)
    }
    #endif
}

#if canImport(UIKit)
/// Reads native text operators so a width-only bitmap result cannot hide a
/// proportional font resize in PDF export. Coordinates may be flipped by PDF's
/// drawing context; magnitudes distinguish horizontal and vertical scaling.
private final class ChordPDFTextTransformCapture {
    struct Metric {
        var horizontalToVerticalRatio: CGFloat
        var verticalPointSize: CGFloat
    }

    struct Result {
        var metrics: [Metric]
        var strokedPathCount: Int
    }

    private var graphicsTransform = CGAffineTransform.identity
    private var graphicsStack: [(CGAffineTransform, CGFloat, CGFloat)] = []
    private var textTransform = CGAffineTransform.identity
    private var fontPointSize: CGFloat = 0
    private var textHorizontalScale: CGFloat = 1
    private var recorded: [Metric] = []
    private var strokedPathCount = 0

    private static func state(_ info: UnsafeMutableRawPointer?) -> ChordPDFTextTransformCapture? {
        info.map { Unmanaged<ChordPDFTextTransformCapture>.fromOpaque($0).takeUnretainedValue() }
    }

    private static func popTransform(_ scanner: CGPDFScannerRef) -> CGAffineTransform? {
        var values = [CGFloat](repeating: 0, count: 6)
        for index in (0..<6).reversed() {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
            values[index] = CGFloat(value)
        }
        return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }

    private func record() {
        let transform = textTransform.concatenating(graphicsTransform)
        let horizontalMagnitude = hypot(transform.a, transform.b) * textHorizontalScale
        let verticalMagnitude = hypot(transform.c, transform.d)
        guard fontPointSize > 0, verticalMagnitude > 0 else { return }
        recorded.append(Metric(
            horizontalToVerticalRatio: horizontalMagnitude / verticalMagnitude,
            verticalPointSize: fontPointSize * verticalMagnitude
        ))
    }

    static func result(in data: Data) throws -> Result {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        let table = try XCTUnwrap(CGPDFOperatorTableCreate())
        let capture = ChordPDFTextTransformCapture()
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let state = ChordPDFTextTransformCapture.state(info) else { return }
            state.graphicsStack.append((state.graphicsTransform, state.fontPointSize, state.textHorizontalScale))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let state = ChordPDFTextTransformCapture.state(info), let saved = state.graphicsStack.popLast() else { return }
            (state.graphicsTransform, state.fontPointSize, state.textHorizontalScale) = saved
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let state = ChordPDFTextTransformCapture.state(info), let transform = ChordPDFTextTransformCapture.popTransform(scanner) else { return }
            state.graphicsTransform = transform.concatenating(state.graphicsTransform)
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            guard let state = ChordPDFTextTransformCapture.state(info), let transform = ChordPDFTextTransformCapture.popTransform(scanner) else { return }
            state.textTransform = transform
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            guard let state = ChordPDFTextTransformCapture.state(info) else { return }
            var pointSize: CGPDFReal = 0
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopNumber(scanner, &pointSize), CGPDFScannerPopName(scanner, &name) else { return }
            state.fontPointSize = CGFloat(pointSize)
        }
        CGPDFOperatorTableSetCallback(table, "Tz") { scanner, info in
            guard let state = ChordPDFTextTransformCapture.state(info) else { return }
            var percentage: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &percentage) else { return }
            state.textHorizontalScale = CGFloat(percentage) / 100
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string) else { return }
            ChordPDFTextTransformCapture.state(info)?.record()
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array) else { return }
            ChordPDFTextTransformCapture.state(info)?.record()
        }
        for strokeOperator in ["S", "s", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, strokeOperator) { _, info in
                ChordPDFTextTransformCapture.state(info)?.strokedPathCount += 1
            }
        }
        let stream = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(capture).toOpaque())
        XCTAssertTrue(CGPDFScannerScan(scanner), "The native PDF text-transform stream must scan successfully")
        return Result(metrics: capture.recorded, strokedPathCount: capture.strokedPathCount)
    }
}
#endif

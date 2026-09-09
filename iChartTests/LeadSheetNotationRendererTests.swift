import CoreGraphics
import XCTest
@testable import iChart
#if canImport(UIKit)
import UIKit
#endif

final class LeadSheetNotationRendererTests: XCTestCase {
#if canImport(UIKit)
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
}

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

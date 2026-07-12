import CoreGraphics
import XCTest
@testable import iChart

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
}

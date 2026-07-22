import XCTest
@testable import iChart

final class RhythmRecognitionContextRulesTests: XCTestCase {
    func testDottedQuarterEighthEighthDottedQuarterSplitsEighthsAtFourFourCenter() {
        let values: [RhythmValue] = [.dottedQuarter, .eighth, .eighth, .dottedQuarter]
        let boundaries = RhythmRecognitionContextRules.beamBoundaries(
            for: values,
            meter: Meter(numerator: 4, denominator: 4)
        )
        let centerBoundary = boundaries.first { $0.boundaryIndex == 2 }

        XCTAssertEqual(centerBoundary?.offsetInWholeNotes, 0.5)
        XCTAssertTrue(centerBoundary?.reasons.contains(.protectedMeterBoundary) == true)
        XCTAssertFalse(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 2,
                in: values,
                meter: Meter(numerator: 4, denominator: 4)
            )
        )
        XCTAssertTrue(
            RhythmRecognitionContextRules.hasProtectedBeamableBoundary(
                in: values,
                meter: Meter(numerator: 4, denominator: 4)
            )
        )
    }

    func testAdjacentEighthsInsideSameFourFourHalfCanBeam() {
        let values: [RhythmValue] = [.quarter, .eighth, .eighth, .quarter, .quarter]

        XCTAssertTrue(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 2,
                in: values,
                meter: Meter(numerator: 4, denominator: 4)
            )
        )
        XCTAssertFalse(
            RhythmRecognitionContextRules.hasProtectedBeamableBoundary(
                in: values,
                meter: Meter(numerator: 4, denominator: 4)
            )
        )
    }

    func testFourFourBlocksEighthBeamAcrossEveryBeatBoundary() {
        let values: [RhythmValue] = [.eighthRest, .eighth, .eighth, .eighth, .half]
        let meter = Meter(numerator: 4, denominator: 4)

        XCTAssertFalse(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 2,
                in: values,
                meter: meter
            )
        )

        let boundary = RhythmRecognitionContextRules.beamBoundaries(
            for: values,
            meter: meter
        ).first { $0.boundaryIndex == 2 }
        XCTAssertEqual(boundary?.offsetInWholeNotes, 0.25)
        XCTAssertTrue(boundary?.reasons.contains(.protectedMeterBoundary) == true)
    }

    func testFourFourBeamsShortNoteRunsInsideOneBeatOnly() {
        let values: [RhythmValue] = [
            .sixteenth,
            .sixteenth,
            .sixteenth,
            .sixteenth,
            .sixteenth,
            .sixteenth,
            .sixteenth,
            .sixteenth
        ]
        let meter = Meter(numerator: 4, denominator: 4)

        XCTAssertTrue(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 1,
                in: values,
                meter: meter
            )
        )
        XCTAssertTrue(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 3,
                in: values,
                meter: meter
            )
        )
        XCTAssertFalse(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 4,
                in: values,
                meter: meter
            )
        )
        XCTAssertTrue(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 5,
                in: values,
                meter: meter
            )
        )
    }

    func testCompoundMeterGroupsEighthsByDottedQuarterBeats() {
        let values: [RhythmValue] = [.eighth, .eighth, .eighth, .eighth, .eighth, .eighth]
        let meter = Meter(numerator: 6, denominator: 8)

        XCTAssertTrue(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 1,
                in: values,
                meter: meter
            )
        )
        XCTAssertTrue(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 2,
                in: values,
                meter: meter
            )
        )
        XCTAssertFalse(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 3,
                in: values,
                meter: meter
            )
        )
        XCTAssertTrue(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 4,
                in: values,
                meter: meter
            )
        )
    }

    func testRestsBreakDefaultBeamContext() {
        let values: [RhythmValue] = [.eighth, .eighthRest, .eighth]
        let boundaries = RhythmRecognitionContextRules.beamBoundaries(
            for: values,
            meter: Meter(numerator: 4, denominator: 4)
        )

        XCTAssertTrue(boundaries.allSatisfy { $0.reasons.contains(.rest) })
        XCTAssertFalse(
            RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: 1,
                in: values,
                meter: Meter(numerator: 4, denominator: 4)
            )
        )
    }
}

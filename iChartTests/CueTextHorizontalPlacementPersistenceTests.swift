import XCTest
@testable import iChart

final class CueTextHorizontalPlacementPersistenceTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testPlacementBoundsAreFiniteAndDecodedFractionsAreNormalized() throws {
        for region in [CueTextHorizontalPlacement.Region.measure, .leadingMargin, .trailingMargin] {
            XCTAssertEqual(CueTextHorizontalPlacement(region: region, fraction: -0.5).fraction, 0)
            XCTAssertEqual(CueTextHorizontalPlacement(region: region, fraction: 1.5).fraction, 1)
            for invalid in [Double.nan, .infinity, -.infinity] {
                XCTAssertEqual(CueTextHorizontalPlacement(region: region, fraction: invalid).fraction, 0)
                XCTAssertNil(CueTextHorizontalPlacement(region: region, fraction: 0.5, wrapWidth: invalid).wrapWidth)
            }
            let data = try JSONSerialization.data(withJSONObject: ["region": region.rawValue, "fraction": 1.7])
            let decoded = try JSONDecoder().decode(CueTextHorizontalPlacement.self, from: data)
            XCTAssertEqual(decoded.region, region)
            XCTAssertEqual(decoded.fraction, 1)
        }
    }

    func testNewPlacementRoundTripsWithLegacyFallbackAndOldCuesDecodeWithoutIt() throws {
        for style in styles {
            for region in [CueTextHorizontalPlacement.Region.measure, .leadingMargin, .trailingMargin] {
                var chart = Chart.blank(title: "Persistent cue position", measureCount: 2, layoutStyle: style)
                let cueID = try XCTUnwrap(chart.addCueText("Cue", anchorMeasureID: chart.measures[1].id,
                    position: .above, atFraction: 0.625))
                let index = try XCTUnwrap(chart.cueTexts.firstIndex { $0.id == cueID })
                chart.cueTexts[index].horizontalPlacement = .init(region: region, fraction: 0.413, wrapWidth: 142)
                let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(chart))
                XCTAssertEqual(reopened, chart)
                let cueData = try JSONEncoder().encode(chart.cueTexts[index])
                let oldReader = try JSONDecoder().decode(LegacyCuePosition.self, from: cueData)
                XCTAssertEqual(oldReader.id, cueID)
                XCTAssertEqual(oldReader.anchorMeasureID, chart.measures[1].id)
                XCTAssertEqual(oldReader.beatFraction, 0.625, "Older readers keep the stored measure fallback")
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: cueData) as? [String: Any])
                object.removeValue(forKey: "horizontalPlacement")
                let legacy = try JSONDecoder().decode(CueText.self,
                    from: JSONSerialization.data(withJSONObject: object))
                XCTAssertNil(legacy.horizontalPlacement)
                XCTAssertEqual(legacy.beatFraction, 0.625)
            }
        }
    }

    func testVerticalEditsKeepExactLegacyAndExplicitPlacementAndDiscreteMovesClearOverride() throws {
        for style in styles {
            var chart = Chart.blank(title: "Independent cue axes", layoutStyle: style)
            let measureID = chart.measures[0].id
            let cueID = try XCTUnwrap(chart.addCueText("Cue", anchorMeasureID: measureID, atFraction: 0.375))
            let index = try XCTUnwrap(chart.cueTexts.firstIndex { $0.id == cueID })
            chart.cueTexts[index].beatFraction = 0.37123
            let margin = CueTextHorizontalPlacement(region: .leadingMargin, fraction: 0.6)
            chart.cueTexts[index].horizontalPlacement = margin
            XCTAssertTrue(chart.updateCueText(cueID, verticalOffset: -12))
            XCTAssertTrue(chart.setCueTextVerticalOffset(cueID, to: 24))
            XCTAssertEqual(chart.cueText(id: cueID)?.beatFraction, 0.37123)
            XCTAssertEqual(chart.cueText(id: cueID)?.horizontalPlacement, margin)
            let continuous = CueTextHorizontalPlacement(region: .measure, fraction: 0.417)
            XCTAssertTrue(chart.moveCueText(cueID, to: measureID, atFraction: 0.417,
                horizontalPlacement: continuous))
            XCTAssertEqual(chart.cueText(id: cueID)?.beatFraction, 0.375)
            XCTAssertEqual(chart.cueText(id: cueID)?.horizontalPlacement, continuous)
            XCTAssertTrue(chart.moveCueText(cueID, to: measureID, atFraction: 0.625))
            XCTAssertEqual(chart.cueText(id: cueID)?.beatFraction, 0.625)
            XCTAssertNil(chart.cueText(id: cueID)?.horizontalPlacement)
        }
    }

    func testExplicitMeasureAndMarginPlacementsSurviveSplitAndJoinWithoutLosingReferences() throws {
        for style in styles {
            var chart = Chart.blank(title: "Structural cue positions", measureCount: 2, layoutStyle: style)
            let measureID = chart.measures[0].id
            let measureCue = try XCTUnwrap(chart.addCueText("Inside", anchorMeasureID: measureID, atFraction: 0.8))
            let leadingCue = try XCTUnwrap(chart.addCueText("Before row", anchorMeasureID: measureID, atFraction: 0))
            let trailingCue = try XCTUnwrap(chart.addCueText("After row", anchorMeasureID: measureID, atFraction: 0.9999))
            let leading = CueTextHorizontalPlacement(region: .leadingMargin, fraction: 0.2)
            let trailing = CueTextHorizontalPlacement(region: .trailingMargin, fraction: 0.7)
            for (id, placement, fallback) in [
                (measureCue, CueTextHorizontalPlacement(region: .measure, fraction: 0.8, wrapWidth: 142), 0.8),
                (leadingCue, leading, 0), (trailingCue, trailing, 0.9999)
            ] {
                XCTAssertTrue(chart.moveCueText(id, to: measureID, atFraction: fallback, horizontalPlacement: placement))
            }
            XCTAssertTrue(chart.setCueTextManualVerticalOffset(measureCue, to: 186.75))
            let rightID: UUID
            if style == .simpleChordSheet {
                rightID = try XCTUnwrap(chart.splitSimpleChordMeasure(measureID, atFraction: 0.5))
            } else {
                rightID = try XCTUnwrap(chart.splitCommittedRhythmSectionMeasure(measureID, atFraction: 0.5, sourceWidth: 200))
            }
            XCTAssertEqual(chart.cueText(id: leadingCue)?.anchorMeasureID, measureID)
            XCTAssertEqual(chart.cueText(id: leadingCue)?.horizontalPlacement, leading)
            XCTAssertEqual(chart.cueText(id: trailingCue)?.anchorMeasureID, rightID)
            XCTAssertEqual(chart.cueText(id: trailingCue)?.horizontalPlacement, trailing)
            XCTAssertEqual(chart.cueText(id: measureCue)?.anchorMeasureID, rightID)
            XCTAssertEqual(try XCTUnwrap(chart.cueText(id: measureCue)?.horizontalPlacement?.fraction), 0.6, accuracy: 0.0001)
            XCTAssertTrue(chart.joinMeasure(after: measureID, sourceMeasureWidths: [measureID: 100, rightID: 100]))
            XCTAssertEqual(try XCTUnwrap(chart.cueText(id: measureCue)?.horizontalPlacement?.fraction), 0.8, accuracy: 0.0001)
            XCTAssertEqual(chart.cueText(id: measureCue)?.horizontalPlacement?.wrapWidth, 142)
            XCTAssertEqual(chart.cueText(id: measureCue)?.manualVerticalOffset, 186.75)
            XCTAssertEqual(chart.cueText(id: measureCue)?.verticalOffset, 72)
            XCTAssertEqual(chart.cueText(id: leadingCue)?.horizontalPlacement, leading)
            XCTAssertEqual(chart.cueText(id: trailingCue)?.horizontalPlacement, trailing)
            XCTAssertEqual(Set(try XCTUnwrap(chart.measure(id: measureID)).cueTextIDs), Set([measureCue, leadingCue, trailingCue]))
            XCTAssertTrue(chart.cueTexts.allSatisfy { $0.anchorMeasureID == measureID })
        }
    }

    func testFreeVerticalOffsetPersistsWithLegacyFallbackAndContentEditsKeepBothAxes() throws {
        for style in styles {
            for offset in [-245.25, 186.75] {
                var chart = Chart.blank(title: "Free cue height", measureCount: 2, layoutStyle: style)
                let cueID = try XCTUnwrap(chart.addCueText("Cue", anchorMeasureID: chart.measures[0].id,
                    position: .above, atFraction: 0.375))
                let index = try XCTUnwrap(chart.cueTexts.firstIndex { $0.id == cueID })
                chart.cueTexts[index].beatFraction = 0.37123
                let placement = CueTextHorizontalPlacement(region: .measure, fraction: 0.413, wrapWidth: 142)
                chart.cueTexts[index].horizontalPlacement = placement
                XCTAssertTrue(chart.setCueTextManualVerticalOffset(cueID, to: offset))
                XCTAssertTrue(chart.updateCueText(cueID, text: "Changed words", scale: 1.25, emphasis: .strong))
                let cue = try XCTUnwrap(chart.cueText(id: cueID))
                XCTAssertEqual(cue.manualVerticalOffset, offset)
                XCTAssertEqual(cue.verticalOffset, CueText.clampedVerticalOffset(offset))
                XCTAssertEqual(cue.horizontalPlacement, placement)
                XCTAssertEqual(cue.beatFraction, 0.37123)
                let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(chart))
                XCTAssertEqual(reopened, chart)
                let cueData = try JSONEncoder().encode(cue)
                let oldReader = try JSONDecoder().decode(LegacyCuePosition.self, from: cueData)
                XCTAssertEqual(oldReader.verticalOffset, CueText.clampedVerticalOffset(offset))
                XCTAssertEqual(oldReader.beatFraction, 0.37123)
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: cueData) as? [String: Any])
                object.removeValue(forKey: "manualVerticalOffset")
                let withoutManual = try JSONDecoder().decode(CueText.self,
                    from: JSONSerialization.data(withJSONObject: object))
                XCTAssertNil(withoutManual.manualVerticalOffset)
                XCTAssertEqual(withoutManual.verticalOffset, cue.verticalOffset,
                    "Opening a historical cue keeps its existing constrained position")
            }
        }
    }

    func testCombinedFreeMotionIsAtomicAndLegacyVerticalActionsStillResetFreeY() throws {
        for style in styles {
            var chart = Chart.blank(title: "Free cue motion", measureCount: 2, layoutStyle: style)
            let firstID = chart.measures[0].id
            let secondID = chart.measures[1].id
            let cueID = try XCTUnwrap(chart.addCueText("Cue", anchorMeasureID: firstID, atFraction: 0.25))
            let placement = CueTextHorizontalPlacement(region: .trailingMargin, fraction: 0.43, wrapWidth: 128)
            XCTAssertTrue(chart.moveCueText(cueID, to: secondID, atFraction: 0.9999,
                horizontalPlacement: placement, manualVerticalOffset: 224.5))
            XCTAssertEqual(chart.cueText(id: cueID)?.manualVerticalOffset, 224.5)
            XCTAssertEqual(chart.cueText(id: cueID)?.verticalOffset, 72)
            XCTAssertEqual(chart.cueText(id: cueID)?.horizontalPlacement, placement)
            let beforeInvalid = chart
            for invalid in [Double.nan, .infinity, -.infinity] {
                XCTAssertFalse(chart.setCueTextManualVerticalOffset(cueID, to: invalid))
                XCTAssertFalse(chart.moveCueText(cueID, to: firstID, atFraction: 0.5,
                    horizontalPlacement: .init(region: .measure, fraction: 0.5), manualVerticalOffset: invalid))
                XCTAssertEqual(chart, beforeInvalid, "Invalid Y must not partially change X, anchors, or timestamps")
            }
            XCTAssertFalse(chart.setCueTextManualVerticalOffset(cueID, to: 224.5))
            XCTAssertEqual(chart, beforeInvalid, "An equal free Y must not create a save")
            XCTAssertTrue(chart.moveCueText(cueID, to: secondID, atFraction: 0.5,
                horizontalPlacement: .init(region: .measure, fraction: 0.513)))
            XCTAssertEqual(chart.cueText(id: cueID)?.manualVerticalOffset, 224.5,
                "An X-only move preserves Y when both Y arguments are omitted")
            XCTAssertTrue(chart.setCueTextVerticalOffset(cueID, to: 72))
            XCTAssertNil(chart.cueText(id: cueID)?.manualVerticalOffset)
            XCTAssertEqual(chart.cueText(id: cueID)?.verticalOffset, 72)
            XCTAssertTrue(chart.setCueTextManualVerticalOffset(cueID, to: -250))
            XCTAssertTrue(chart.updateCueText(cueID, verticalOffset: 0))
            XCTAssertNil(chart.cueText(id: cueID)?.manualVerticalOffset)
            XCTAssertEqual(chart.cueText(id: cueID)?.verticalOffset, 0)
        }
    }

    func testManualVerticalInitializerAndDecoderRejectOnlyNonfiniteValues() throws {
        let cue = CueText(id: UUID(), text: "Cue", anchorMeasureID: UUID(), position: .below,
            emphasis: .normal, manualVerticalOffset: -240.5)
        XCTAssertEqual(cue.manualVerticalOffset, -240.5)
        XCTAssertEqual(cue.verticalOffset, -72)
        let invalid = CueText(id: UUID(), text: "Cue", anchorMeasureID: UUID(), position: .above,
            emphasis: .normal, verticalOffset: 18, manualVerticalOffset: .nan)
        XCTAssertNil(invalid.manualVerticalOffset)
        XCTAssertEqual(invalid.verticalOffset, 18)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cue)) as? [String: Any])
        object["manualVerticalOffset"] = "NaN"
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let decoded = try decoder.decode(CueText.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.manualVerticalOffset)
        XCTAssertEqual(decoded.verticalOffset, -72)
    }

    private struct LegacyCuePosition: Decodable {
        let id: UUID
        let anchorMeasureID: UUID
        let beatFraction: Double?
        let verticalOffset: Double
    }
}

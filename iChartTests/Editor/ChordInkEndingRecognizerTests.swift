#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkEndingRecognizerTests: XCTestCase {
    func testConnectedOpenAndClosedBracketsAcrossActualChartLanes() throws {
        for style in ChartLayoutStyle.allCases {
            let fixture = try Fixture(style: style)
            for closed in [false, true] {
                let strokes = fixture.bracket(closed: closed)
                let result = fixture.recognize(strokes)
                let ending = try XCTUnwrap(result.endings.first, "\(style), closed=\(closed)")
                XCTAssertEqual(result.endings.count, 1)
                XCTAssertEqual(ending.endStyle, closed ? .closed : .open)
                XCTAssertEqual(result.strokeIndices, Set(strokes.indices))
                XCTAssertEqual(ending.sourceStrokeGeometry, strokes)
                XCTAssertEqual(ending.start.laneLocation.fraction, 0.18, accuracy: 0.001)
                XCTAssertEqual(ending.end.laneLocation.fraction, 0.72, accuracy: 0.001)
                XCTAssertEqual(ending.start.laneLocation.systemIndex, fixture.system.index)
                XCTAssertTrue(ending.label.isEmpty)
                XCTAssertFalse(ending.isReviewed)
                XCTAssertFalse(ending.isRenderable)
            }
        }
    }

    func testDetachedRoofAndHooksHaveCompleteSourceOwnership() throws {
        let fixture = try Fixture()
        for closed in [false, true] {
            let strokes = fixture.bracket(closed: closed, detached: true)
            let result = fixture.recognize(strokes)
            let ending = try XCTUnwrap(result.endings.first)
            XCTAssertEqual(result.endings.count, 1)
            XCTAssertEqual(ending.endStyle, closed ? .closed : .open)
            XCTAssertEqual(ending.sourceStrokeIndices, Set(strokes.indices))
        }
    }

    func testExactCustomLabelInkAndTinyPunctuationAreOwnedWithoutGuessingText() throws {
        let fixture = try Fixture()
        let label = [
            fixture.stroke([fixture.point(0.24, 0.22), fixture.point(0.25, 0.40)]),
            fixture.stroke([fixture.point(0.27, 0.39)]),
            fixture.stroke([fixture.point(0.29, 0.23), fixture.point(0.33, 0.23), fixture.point(0.30, 0.40)]),
            fixture.stroke([fixture.point(0.36, 0.30), fixture.point(0.40, 0.30)])
        ]
        let source = fixture.bracket() + label
        let ending = try XCTUnwrap(fixture.recognize(source).endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, Set(source.indices))
        XCTAssertEqual(ending.sourceStrokeGeometry, source)
        XCTAssertTrue(ending.label.isEmpty, "Geometry must not invent a pass list from ink.")
    }

    func testLowerChordInkInsideTheSpanRemainsUnclaimed() throws {
        let fixture = try Fixture()
        let bracket = fixture.bracket()
        let chord = fixture.stroke([
            fixture.point(0.40, 0.62), fixture.point(0.36, 0.75),
            fixture.point(0.40, 0.88), fixture.point(0.43, 0.75)
        ])
        let result = fixture.recognize(bracket + [chord])
        XCTAssertEqual(result.endings.count, 1)
        XCTAssertEqual(result.strokeIndices, Set(bracket.indices))
    }

    func testLabelCrossingHeaderBoundaryRejectsRatherThanSplittingOrStealingIt() throws {
        let fixture = try Fixture()
        let crossing = fixture.stroke([fixture.point(0.30, 0.22), fixture.point(0.33, 0.68)])
        let result = fixture.recognize(fixture.bracket() + [crossing])
        XCTAssertTrue(result.endings.isEmpty)
        XCTAssertTrue(result.strokeIndices.isEmpty)
    }

    func testAHorizontalDashOrRoofWithOnlyARightHookIsNotAnEnding() throws {
        let fixture = try Fixture()
        let roof = fixture.stroke([fixture.point(0.18, 0.12), fixture.point(0.72, 0.12)])
        let rightOnly = fixture.stroke([
            fixture.point(0.18, 0.12), fixture.point(0.72, 0.12), fixture.point(0.72, 0.34)
        ])
        XCTAssertTrue(fixture.recognize([roof]).endings.isEmpty)
        XCTAssertTrue(fixture.recognize([rightOnly]).endings.isEmpty)
    }

    func testChordCapsBoxesAndLowBracketsDoNotBecomeEndings() throws {
        let fixture = try Fixture()
        let cap = fixture.stroke([
            fixture.point(0.18, 0.34), fixture.point(0.18, 0.12), fixture.point(0.21, 0.12)
        ])
        let box = fixture.stroke([
            fixture.point(0.18, 0.34), fixture.point(0.18, 0.12), fixture.point(0.72, 0.12),
            fixture.point(0.72, 0.34), fixture.point(0.18, 0.34)
        ])
        let diagonal = fixture.stroke([
            fixture.point(0.18, 0.34), fixture.point(0.18, 0.12), fixture.point(0.72, 0.12),
            fixture.point(0.18, 0.34)
        ])
        let low = fixture.stroke([
            fixture.point(0.18, 0.80), fixture.point(0.18, 0.58), fixture.point(0.72, 0.58)
        ])
        for strokes in [[cap], [box], [diagonal], [low]] {
            XCTAssertTrue(fixture.recognize(strokes).endings.isEmpty)
        }
    }

    func testReversedStrokeDirectionsAndInputOrderPreserveGeometry() throws {
        let fixture = try Fixture()
        let source = fixture.bracket(closed: true, detached: true)
        for reversedInput in [false, true] {
            let order = reversedInput ? Array(source.reversed()) : source
            let reversedPaths = order.map { InkStroke(points: Array($0.points.reversed())) }
            let ending = try XCTUnwrap(fixture.recognize(reversedPaths).endings.first)
            XCTAssertEqual(ending.endStyle, .closed)
            XCTAssertEqual(ending.sourceStrokeIndices, Set(source.indices))
            XCTAssertEqual(ending.sourceStrokeGeometry, reversedPaths)
        }
    }

    func testSeparateEndingsRetainSeparateOwnedGroups() throws {
        let fixture = try Fixture()
        let first = fixture.bracket(start: 0.10, end: 0.37, closed: true)
        let second = fixture.bracket(start: 0.55, end: 0.85, closed: false)
        let result = fixture.recognize(first + second)
        XCTAssertEqual(result.endings.count, 2)
        XCTAssertEqual(result.endings.map(\.endStyle), [.closed, .open])
        XCTAssertTrue(result.endings[0].sourceStrokeIndices.isDisjoint(with: result.endings[1].sourceStrokeIndices))
        XCTAssertEqual(result.strokeIndices, Set((first + second).indices))
    }

    func testOverlappingBracketsAndDuplicateHookClaimsRemainInk() throws {
        let fixture = try Fixture()
        let overlapping = fixture.bracket(start: 0.18, end: 0.72)
            + fixture.bracket(start: 0.35, end: 0.82)
        XCTAssertTrue(fixture.recognize(overlapping).endings.isEmpty)
        var duplicated = fixture.bracket(closed: false, detached: true)
        duplicated.append(duplicated[1])
        XCTAssertTrue(fixture.recognize(duplicated).endings.isEmpty)
    }

    func testBarlineWrapperExcludesEndingInkAndRemapsOriginalSourceIndices() throws {
        let fixture = try Fixture()
        let bracket = fixture.bracket(closed: true, detached: true)
        let bar = fixture.stroke([fixture.point(0.84, 0.07), fixture.point(0.84, 0.93)])
        let source = bracket + [bar]
        let result = ChordDraftEndingRecognizer.recognizeBarlinesExcludingEndings(
            strokes: source, chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        XCTAssertEqual(result.barlines.count, 1)
        XCTAssertEqual(result.strokeIndices, [bracket.count])
        XCTAssertEqual(result.barlines.first?.sourceStrokeIndex, bracket.count)
        XCTAssertEqual(result.barlines.first?.ownedSourceStrokeIndices, [bracket.count])
    }

    func testCombinedStructureRecognitionKeepsEndingAndBarlineOwnershipAcrossChartStyles() throws {
        for style in ChartLayoutStyle.allCases {
            let fixture = try Fixture(style: style)
            for detached in [false, true] {
                let bracket = fixture.bracket(closed: true, detached: detached)
                let bar = fixture.stroke([fixture.point(0.84, 0.07), fixture.point(0.84, 0.93)])
                let chord = fixture.stroke([
                    fixture.point(0.44, 0.62), fixture.point(0.40, 0.75),
                    fixture.point(0.44, 0.88), fixture.point(0.47, 0.75)
                ])
                let source = bracket + [bar, chord]
                let result = ChordDraftEndingRecognizer.recognizeStructure(
                    strokes: source, chordFrame: fixture.chordFrame, pageLayout: fixture.layout)

                let ending = try XCTUnwrap(result.endings.endings.first, "\(style), detached=\(detached)")
                XCTAssertEqual(result.endings.endings.count, 1)
                XCTAssertEqual(result.endings.strokeIndices, Set(bracket.indices))
                XCTAssertEqual(ending.sourceStrokeGeometry, bracket)
                XCTAssertEqual(ending.endStyle, .closed)
                XCTAssertEqual(result.barlines.barlines.count, 1)
                XCTAssertEqual(result.barlines.strokeIndices, [bracket.count])
                XCTAssertEqual(result.barlines.barlines.first?.ownedSourceStrokeIndices, [bracket.count])
                let recognizedBarline = try XCTUnwrap(result.barlines.barlines.first)
                XCTAssertEqual(recognizedBarline.sourceStrokeIndex, bracket.count)
                // Plain barlines retain ink by original source index; only
                // multi-stroke endpoint-tap groups cache their geometry.
                let ownedInk = recognizedBarline.ownedSourceStrokeIndices.sorted().compactMap {
                    source.indices.contains($0) ? source[$0] : nil
                }
                XCTAssertEqual(ownedInk, [bar])
                XCTAssertTrue(result.endings.strokeIndices.isDisjoint(with: result.barlines.strokeIndices))
                XCTAssertFalse(result.endings.strokeIndices.contains(source.count - 1))
                XCTAssertFalse(result.barlines.strokeIndices.contains(source.count - 1))
            }
        }
    }

    func testCombinedStructureRetainsRawEndingClaimsBeforeOriginalStrokeAmbiguityFiltering() throws {
        for style in ChartLayoutStyle.allCases {
            let fixture = try Fixture(style: style)
            let bracket = fixture.bracket(closed: true, detached: true)
            let bar = fixture.stroke([fixture.point(0.84, 0.07), fixture.point(0.84, 0.93)])
            let source = bracket + [bar]
            let result = ChordDraftEndingRecognizer.recognizeStructure(
                strokes: source, chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
            // Two visible fragments can share one bitmap-erased original
            // stroke. Such an ending is not safely removable, but its raw
            // hooks/label must still be excluded from barline recognition.
            let context = ChordInkDraftVisibleDrawingContext(drawing: fixture.drawing(source),
                originalStrokeIndices: [0, 0, 1, 2], invisibleStrokeIndices: [])
            let safeEndings = context.endingRecognitionWithUnambiguousSourceStrokes(result.endings)
            let safeBarlines = context.barlineRecognitionWithUnambiguousSourceStrokes(result.barlines)

            XCTAssertEqual(result.endings.strokeIndices, Set(bracket.indices))
            XCTAssertEqual(result.barlines.strokeIndices, [bracket.count])
            XCTAssertTrue(safeEndings.endings.isEmpty)
            XCTAssertTrue(safeEndings.strokeIndices.isEmpty)
            XCTAssertEqual(context.remappedBarlineRecognition(safeBarlines).strokeIndices, [2])
            XCTAssertEqual(result.endings.endings.first?.sourceStrokeGeometry, bracket)
        }
    }

    func testFullHeightEndpointAndInteriorBarsStaySeparateFromTheEnding() throws {
        let fixture = try Fixture()
        let bracket = fixture.bracket()
        let bars = [CGFloat(0.18), 0.45, 0.72].map { x in
            fixture.stroke([fixture.point(x, 0.07), fixture.point(x, 0.93)])
        }
        let source = bracket + bars
        let ending = try XCTUnwrap(fixture.recognize(source).endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, Set(bracket.indices))
        let barlines = ChordDraftEndingRecognizer.recognizeBarlinesExcludingEndings(
            strokes: source, chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        XCTAssertEqual(barlines.barlines.count, 3)
        XCTAssertEqual(barlines.strokeIndices, Set(bracket.count..<source.count))
    }





    func testShortVerticalEndingNumeralNearBoundaryIsNotARepeatDot() throws {
        let fixture = try Fixture()
        let x = fixture.point(0.18, 0).x + 16
        let numeral = fixture.stroke([
            CGPoint(x: x, y: fixture.point(0, 0.22).y),
            CGPoint(x: x, y: fixture.point(0, 0.34).y)
        ])
        let bar = fixture.stroke([fixture.point(0.18, 0.07), fixture.point(0.18, 0.93)])
        let bracket = fixture.bracket()
        let source = bracket + [numeral, bar]
        let ending = try XCTUnwrap(fixture.recognize(source).endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, Set(0..<(bracket.count + 1)))
        XCTAssertEqual(ending.sourceStrokeGeometry, bracket + [numeral])
        XCTAssertTrue(ending.label.isEmpty, "The short stem is retained for label review without guessing its text.")
        XCTAssertLessThan(try XCTUnwrap(ending.roofReviewFrame).maxY, CGFloat(numeral.bounds.minY),
            "Roof review taps must stay above the supported handwritten label.")
    }

    func testTranslatedCanvasOriginPreservesBothEndpointsAndOwnership() throws {
        let fixture = try Fixture()
        let source = fixture.bracket()
        let offset = CGPoint(x: 53, y: -29)
        let translated = source.map { stroke in
            InkStroke(points: stroke.points.map {
                InkPoint(x: $0.x - offset.x, y: $0.y - offset.y, timeOffset: $0.timeOffset)
            })
        }
        let result = ChordDraftEndingRecognizer.recognize(strokes: translated,
            chordFrame: fixture.chordFrame.offsetBy(dx: offset.x, dy: offset.y), pageLayout: fixture.layout)
        let ending = try XCTUnwrap(result.endings.first)
        XCTAssertEqual(ending.start.laneLocation.fraction, 0.18, accuracy: 0.001)
        XCTAssertEqual(ending.end.laneLocation.fraction, 0.72, accuracy: 0.001)
        XCTAssertEqual(result.strokeIndices, Set(source.indices))
    }

    func testNoLayoutAndNonfiniteInputNeverClaimSource() throws {
        let fixture = try Fixture()
        XCTAssertTrue(ChordDraftEndingRecognizer.recognize(strokes: fixture.bracket(),
            chordFrame: fixture.chordFrame, pageLayout: nil).endings.isEmpty)
        let invalid = InkStroke(points: [InkPoint(x: .nan, y: 1, timeOffset: nil)])
        XCTAssertTrue(fixture.recognize(fixture.bracket() + [invalid]).endings.isEmpty)
    }

    func testMildlySlopedRoofsDoNotRequireAnExactlyHorizontalTopStrip() throws {
        let fixture = try Fixture()
        for rise: CGFloat in [-0.08, 0.08] {
            let source = [fixture.stroke([
                fixture.point(0.18, 0.38), fixture.point(0.18, 0.16),
                fixture.point(0.72, 0.16 + rise), fixture.point(0.72, 0.38 + rise)
            ])]
            let ending = try XCTUnwrap(fixture.recognize(source).endings.first)
            XCTAssertEqual(ending.endStyle, .closed)
            XCTAssertEqual(ending.sourceStrokeGeometry, source)
            let hit = try XCTUnwrap(ending.roofReviewFrame)
            let rightRoof = fixture.point(0.72, 0.16 + rise)
            XCTAssertTrue(hit.contains(CGPoint(x: rightRoof.x - fixture.chordFrame.minX,
                y: rightRoof.y - fixture.chordFrame.minY)))
        }
    }

    func testWavyRoofAndRoundedCornersRetainTheCompleteOriginalStroke() throws {
        let fixture = try Fixture()
        let left = fixture.point(0.18, 0.12), right = fixture.point(0.72, 0.20)
        var points = [CGPoint(x: left.x + 2, y: left.y + fixture.lane.height * 0.22),
            CGPoint(x: left.x, y: left.y + 5), CGPoint(x: left.x + 4, y: left.y)]
        for index in 1...24 {
            let t = CGFloat(index) / 24
            points.append(CGPoint(x: left.x + (right.x - left.x) * t,
                y: left.y + (right.y - left.y) * t + sin(t * .pi * 2) * fixture.lane.height * 0.035))
        }
        points += [CGPoint(x: right.x, y: right.y + 4),
            CGPoint(x: right.x - 2, y: right.y + fixture.lane.height * 0.22)]
        let source = [fixture.stroke(points)]
        let ending = try XCTUnwrap(fixture.recognize(source).endings.first)
        XCTAssertEqual(ending.endStyle, .closed)
        XCTAssertEqual(ending.sourceStrokeIndices, [0])
        XCTAssertEqual(ending.sourceStrokeGeometry, source)
    }

    func testRoofCanJoinASeparateFullHeightDrawnBarWithoutTakingItsSource() throws {
        let fixture = try Fixture()
        let bar = fixture.stroke([fixture.point(0.18, 0.07), fixture.point(0.18, 0.93)])
        let roof = fixture.stroke([
            CGPoint(x: fixture.point(0.18, 0.12).x + 8, y: fixture.point(0, 0.12).y), fixture.point(0.72, 0.16)
        ])
        let source = [bar, roof]
        let ending = try XCTUnwrap(fixture.recognize(source).endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, [1])
        let bars = ChordDraftEndingRecognizer.recognizeBarlinesExcludingEndings(
            strokes: source, chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        XCTAssertEqual(bars.strokeIndices, [0])
    }

    func testRoofWithSmallGapCanAttachToAnExistingPrintedBoundary() throws {
        let fixture = try Fixture()
        let boundary = try XCTUnwrap(fixture.system.measures.first).frame.minX
        let roof = fixture.stroke([
            CGPoint(x: boundary + 11, y: fixture.point(0, 0.12).y), fixture.point(0.72, 0.16)
        ])
        let ending = try XCTUnwrap(fixture.recognize([roof]).endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, [0])
        XCTAssertEqual(ending.endStyle, .open)
    }

    func testTerminalRepeatAttachmentAllowsASmallOvershootAtTheVisibleRowEdge() throws {
        let fixture = try Fixture(repeatAtEnd: true)
        let measure = try XCTUnwrap(fixture.system.measures.last { !$0.repeatMarkerLayouts.isEmpty })
        let marker = try XCTUnwrap(measure.repeatMarkerLayouts.first { $0.edge == .trailing })
        let rendered = LeadSheetSimpleChordTerminalBarlineGeometry.renderedRepeatMarkerFrame(marker,
            after: measure, in: fixture.system, paperFrame: fixture.layout.paperFrame(for: fixture.system),
            layoutStyle: .simpleChordSheet)
        let boundary = try XCTUnwrap(fixture.system.measures.first).frame.minX
        let roof = fixture.stroke([
            CGPoint(x: boundary + 8, y: fixture.point(0, 0.12).y),
            CGPoint(x: rendered.maxX + 7, y: fixture.point(0, 0.16).y)
        ])
        let ending = try XCTUnwrap(fixture.recognize([roof]).endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, [0])
    }

    func testSingleStrokeFullBarAndRoofOwnsSourceOnceOnlyAtExistingBoundary() throws {
        let fixture = try Fixture()
        let existing = try XCTUnwrap(fixture.system.measures.first).frame.minX + 5
        let combined = fixture.stroke([
            CGPoint(x: existing, y: fixture.point(0, 0.93).y),
            CGPoint(x: existing, y: fixture.point(0, 0.12).y), fixture.point(0.72, 0.16)
        ])
        let ending = try XCTUnwrap(fixture.recognize([combined]).endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, [0])
        XCTAssertLessThan(try XCTUnwrap(ending.roofReviewFrame).height, fixture.lane.height * 0.5,
            "A full-height connected leg must not make the review target cover the label or chords.")
        let bars = ChordDraftEndingRecognizer.recognizeBarlinesExcludingEndings(
            strokes: [combined], chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        XCTAssertTrue(bars.strokeIndices.isEmpty)

        let unanchored = fixture.stroke([
            fixture.point(0.18, 0.93), fixture.point(0.18, 0.12), fixture.point(0.72, 0.16)
        ])
        XCTAssertTrue(fixture.recognize([unanchored]).endings.isEmpty,
            "A new barline cannot share one original source index with an ending.")
    }

    func testSlopedClosedBoxAndLargeRoofNoiseStillAbstain() throws {
        let fixture = try Fixture()
        let box = fixture.stroke([
            fixture.point(0.18, 0.38), fixture.point(0.18, 0.12), fixture.point(0.72, 0.20),
            fixture.point(0.72, 0.46), fixture.point(0.18, 0.38)
        ])
        let noise = fixture.stroke([
            fixture.point(0.18, 0.34), fixture.point(0.18, 0.12), fixture.point(0.35, 0.38),
            fixture.point(0.52, 0.02), fixture.point(0.72, 0.12)
        ])
        XCTAssertTrue(fixture.recognize([box]).endings.isEmpty)
        XCTAssertTrue(fixture.recognize([noise]).endings.isEmpty)
    }

    private struct Fixture {
        let layout: LeadSheetPageLayout
        let system: LeadSheetSystemLayout
        let chordFrame: CGRect
        let lane: CGRect

        init(style: ChartLayoutStyle = .simpleChordSheet, repeatAtEnd: Bool = false) throws {
            var chart = Chart.blank(title: "Ending detector fixture", measureCount: 4, layoutStyle: style)
            if repeatAtEnd {
                let ids = chart.measures.map(\.id)
                _ = chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[ids.count - 1])
            }
            let generated = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: CGSize(width: 1180, height: 1500), includesChordInkContinuationLanes: true)
            let first = try XCTUnwrap(generated.systems.first)
            layout = generated
            system = first
            chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: generated)
            lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: first, paperFrame: generated.paperFrame(for: first)))
        }

        func point(_ xFraction: CGFloat, _ yFraction: CGFloat) -> CGPoint {
            CGPoint(x: lane.minX + lane.width * xFraction, y: lane.minY + lane.height * yFraction)
        }

        func bracket(start: CGFloat = 0.18, end: CGFloat = 0.72,
            closed: Bool = true, detached: Bool = false) -> [InkStroke] {
            if detached {
                var source = [stroke([point(start, 0.12), point(end, 0.12)]),
                    stroke([point(start, 0.12), point(start, 0.34)])]
                if closed { source.append(stroke([point(end, 0.12), point(end, 0.34)])) }
                return source
            }
            var points = [point(start, 0.34), point(start, 0.12), point(end, 0.12)]
            if closed { points.append(point(end, 0.34)) }
            return [stroke(points)]
        }

        func stroke(_ points: [CGPoint]) -> InkStroke {
            let source = PKStroke(ink: PKInk(.pen, color: .black),
                path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                    PKStrokePoint(location: CGPoint(x: point.x - chordFrame.minX, y: point.y - chordFrame.minY),
                        timeOffset: Double(index) * 0.01, size: CGSize(width: 1.4, height: 1.4),
                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }, creationDate: Date(timeIntervalSinceReferenceDate: 100)), mask: nil)
            return PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: [source]))[0]
        }

        func recognize(_ strokes: [InkStroke]) -> ChordDraftEndingRecognition {
            ChordDraftEndingRecognizer.recognize(strokes: strokes, chordFrame: chordFrame, pageLayout: layout)
        }

        func drawing(_ strokes: [InkStroke]) -> PKDrawing {
            PKDrawing(strokes: strokes.map { stroke in
                PKStroke(ink: PKInk(.pen, color: .black),
                    path: PKStrokePath(controlPoints: stroke.points.map { point in
                        PKStrokePoint(location: CGPoint(x: point.x, y: point.y),
                            timeOffset: point.timeOffset ?? 0, size: CGSize(width: 1.4, height: 1.4),
                            opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    }, creationDate: Date(timeIntervalSinceReferenceDate: 100)), mask: nil)
            })
        }
    }
}
#endif

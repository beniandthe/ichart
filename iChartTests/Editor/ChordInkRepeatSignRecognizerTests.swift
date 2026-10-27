#if canImport(UIKit)
import CoreGraphics
import PencilKit
import XCTest
@testable import iChart

final class ChordInkRepeatSignRecognizerTests: XCTestCase {
    func testSingleAndDoubleBarsRecognizeBothDirectionsInActualChartLanes() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            for bars in [1, 2] {
                for kind in [DraftBarlineKind.repeatStart, .repeatEnd, .repeatBoth] {
                    let fixture = try Fixture(layoutStyle: layoutStyle)
                    let strokes = fixture.sign(kind: kind, barCount: bars)
                    let result = fixture.recognize(strokes)
                    let draft = try XCTUnwrap(result.barlines.first, "\(layoutStyle), \(kind), \(bars) bars")

                    XCTAssertEqual(result.barlines.count, 1)
                    XCTAssertEqual(draft.kind, kind)
                    XCTAssertTrue(draft.isRenderable)
                    XCTAssertEqual(result.strokeIndices, Set(strokes.indices))
                    XCTAssertEqual(draft.ownedSourceStrokeIndices, Set(strokes.indices))
                    XCTAssertEqual(draft.sourceStrokeGeometry, strokes)
                    XCTAssertEqual(draft.laneFraction, 0.45, accuracy: 0.001)
                    XCTAssertEqual(draft.laneLocation?.systemIndex, fixture.system.index)
                }
            }
        }
    }

    func testBoundaryUsesTheCenterOfBarsRatherThanDotSide() throws {
        let fixture = try Fixture(layoutStyle: .simpleChordSheet)
        for kind in [DraftBarlineKind.repeatStart, .repeatEnd, .repeatBoth] {
            let result = fixture.recognize(fixture.sign(kind: kind, barCount: 2, fraction: 0.63))
            XCTAssertEqual(try XCTUnwrap(result.barlines.first).laneFraction, 0.63, accuracy: 0.001)
        }
    }

    func testWorkflowSizedEightPointBarsAndTenPointDotOffsetsAcrossLayouts() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let x = fixture.boundaryX(fraction: 0.65)
            let strokes = [
                fixture.bar(atX: x - 4), fixture.bar(atX: x + 4),
                fixture.dot(atX: x - 14, y: fixture.barMidY - 10, stationary: true),
                fixture.dot(atX: x - 14, y: fixture.barMidY + 10, stationary: true)
            ]
            let result = fixture.recognize(strokes)
            XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd], layoutStyle.rawValue)
            XCTAssertEqual(result.strokeIndices, Set(strokes.indices), layoutStyle.rawValue)
            XCTAssertEqual(try XCTUnwrap(result.barlines.first).laneFraction, 0.65, accuracy: 0.001)
        }
    }

    func testInputOrderAndStrokeDirectionDoNotChangeTheSignOrLoseOwnership() throws {
        let fixture = try Fixture(layoutStyle: .rhythmSectionSheet)
        let original = fixture.sign(kind: .repeatBoth, barCount: 2)
        let orders = [original, Array(original.reversed()), Array(original.dropFirst()) + [original[0]]]
        for ordered in orders {
            for reversePaths in [false, true] {
                let strokes = ordered.map { stroke in
                    InkStroke(points: reversePaths ? Array(stroke.points.reversed()) : stroke.points)
                }
                let before = strokes
                let result = fixture.recognize(strokes)
                let sign = try XCTUnwrap(result.barlines.first)
                XCTAssertEqual(result.barlines.count, 1)
                XCTAssertEqual(sign.kind, .repeatBoth)
                XCTAssertEqual(sign.laneFraction, 0.45, accuracy: 0.001)
                XCTAssertEqual(sign.ownedSourceStrokeIndices, Set(strokes.indices))
                XCTAssertEqual(sign.sourceStrokeGeometry, strokes)
                XCTAssertEqual(strokes, before)
            }
        }
    }

    func testStationaryPencilKitTapDotsAreClaimedDespiteZeroPathBounds() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let input = fixture.sign(kind: .repeatEnd, barCount: 2, stationaryDots: true)
            let drawing = PKDrawing(strokes: input.enumerated().map { index, stroke in
                PKStroke(
                    ink: PKInk(.pen, color: .black),
                    path: PKStrokePath(controlPoints: stroke.points.enumerated().map { offset, point in
                        PKStrokePoint(location: CGPoint(x: point.x, y: point.y), timeOffset: Double(offset) * 0.01,
                            size: CGSize(width: 1.4, height: 1.4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    }, creationDate: Date(timeIntervalSinceReferenceDate: Double(index))),
                    mask: nil
                )
            })
            let strokes = PencilKitInkAdapter.inkStrokes(from: drawing)
            XCTAssertEqual(strokes.count, 4)
            XCTAssertTrue(strokes.suffix(2).allSatisfy { $0.points.count == 1 && $0.bounds.width == 0 && $0.bounds.height == 0 })
            let result = fixture.recognize(strokes)
            XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd])
            XCTAssertEqual(result.strokeIndices, Set(strokes.indices))
        }
    }

    func testNormalBarsAndDistantChordInkRemainUnclaimed() throws {
        let fixture = try Fixture(layoutStyle: .leadSheet)
        var strokes = fixture.sign(kind: .repeatStart, barCount: 2, fraction: 0.28)
        let signIndices = Set(strokes.indices)
        strokes.append(fixture.bar(atX: fixture.lane.minX + fixture.lane.width * 0.8))
        strokes.append(fixture.body(minX: fixture.lane.minX + fixture.lane.width * 0.55))
        let result = fixture.recognize(strokes)

        XCTAssertEqual(result.barlines.map(\.kind), [.repeatStart])
        XCTAssertEqual(result.strokeIndices, signIndices)
        XCTAssertTrue(fixture.recognize([strokes[4]]).barlines.isEmpty, "A plain bar is not a repeat sign.")
    }

    func testDistinctSignsInOneLaneHaveDisjointCompleteSourceGroups() throws {
        let fixture = try Fixture(layoutStyle: .simpleChordSheet)
        let start = fixture.sign(kind: .repeatStart, barCount: 2, fraction: 0.25)
        let end = fixture.sign(kind: .repeatEnd, barCount: 1, fraction: 0.75)
        let result = fixture.recognize(start + end)

        XCTAssertEqual(result.barlines.map(\.kind), [.repeatStart, .repeatEnd])
        XCTAssertEqual(result.strokeIndices, Set((start + end).indices))
        XCTAssertTrue(result.barlines[0].ownedSourceStrokeIndices.isDisjoint(with: result.barlines[1].ownedSourceStrokeIndices))
    }

    func testMissingCrowdedMisalignedAndOffCenterDotsDoNotClaimAnyInk() throws {
        let fixture = try Fixture(layoutStyle: .simpleChordSheet)
        let sign = fixture.sign(kind: .repeatEnd, barCount: 1, stationaryDots: true)
        let x = fixture.boundaryX(fraction: 0.45) - fixture.barHeight * 0.12
        let badGroups = [
            [sign[0]],
            Array(sign.dropLast()),
            Array(sign.dropFirst()),
            sign + [fixture.dot(atX: x, y: fixture.barMidY, stationary: true)],
            [sign[0], fixture.dot(atX: x, y: fixture.barMidY - fixture.barHeight * 0.12, stationary: true),
             fixture.dot(atX: x - fixture.barHeight * 0.15, y: fixture.barMidY + fixture.barHeight * 0.12, stationary: true)],
            [sign[0], fixture.dot(atX: x, y: fixture.barMinY + fixture.barHeight * 0.2, stationary: true),
             fixture.dot(atX: x, y: fixture.barMinY + fixture.barHeight * 0.4, stationary: true)]
        ]
        for strokes in badGroups {
            let result = fixture.recognize(strokes)
            XCTAssertTrue(result.barlines.isEmpty)
            XCTAssertTrue(result.strokeIndices.isEmpty)
        }
    }

    func testHorizontalDashPairsAndPercentSlashCannotBecomeRepeats() throws {
        let fixture = try Fixture(layoutStyle: .leadSheet)
        let x = fixture.boundaryX(fraction: 0.45)
        let dotsX = x - fixture.barHeight * 0.16
        let dashes = [-CGFloat(0.12), CGFloat(0.12)].map { offset in
            fixture.stroke([
                CGPoint(x: dotsX - fixture.barHeight * 0.065, y: fixture.barMidY + fixture.barHeight * offset),
                CGPoint(x: dotsX + fixture.barHeight * 0.065, y: fixture.barMidY + fixture.barHeight * offset)
            ])
        }
        XCTAssertTrue(fixture.recognize([fixture.bar(atX: x)] + dashes).barlines.isEmpty)
        let slash = fixture.stroke([
            CGPoint(x: x - fixture.barHeight * 0.3, y: fixture.barMaxY),
            CGPoint(x: x + fixture.barHeight * 0.3, y: fixture.barMinY)
        ])
        let taps = fixture.sign(kind: .repeatEnd, barCount: 1, stationaryDots: true).suffix(2)
        XCTAssertTrue(fixture.recognize([slash] + Array(taps)).barlines.isEmpty)
    }

    func testConnectedLetterBodyOrNumeralCapVetoesARepeatLikeStem() throws {
        let fixture = try Fixture(layoutStyle: .simpleChordSheet)
        let sign = fixture.sign(kind: .repeatStart, barCount: 1)
        let x = fixture.boundaryX(fraction: 0.45)
        let connectedBody = fixture.body(minX: x)
        let numeralCap = fixture.stroke([
            CGPoint(x: x - fixture.barHeight * 0.18, y: fixture.barMinY + fixture.barHeight * 0.12),
            CGPoint(x: x, y: fixture.barMinY)
        ])
        for neighbor in [connectedBody, numeralCap] {
            let result = fixture.recognize(sign + [neighbor])
            XCTAssertTrue(result.barlines.isEmpty)
            XCTAssertTrue(result.strokeIndices.isEmpty)
        }
    }

    func testThreeNearbyVerticalStrokesAreNotSilentlyReducedToOneRepeat() throws {
        let fixture = try Fixture(layoutStyle: .rhythmSectionSheet)
        let sign = fixture.sign(kind: .repeatEnd, barCount: 2)
        let third = fixture.bar(atX: fixture.boundaryX(fraction: 0.45) + fixture.barHeight * 0.135)
        XCTAssertTrue(fixture.recognize(sign + [third]).barlines.isEmpty)
    }

    func testLocalCanvasTranslationDoesNotChangeDirectionOrBoundary() throws {
        let fixture = try Fixture(layoutStyle: .leadSheet)
        let original = fixture.sign(kind: .repeatBoth, barCount: 2)
        let shift = CGPoint(x: 53, y: -29)
        let shifted = original.map { stroke in
            InkStroke(points: stroke.points.map {
                InkPoint(x: $0.x - shift.x, y: $0.y - shift.y, timeOffset: $0.timeOffset)
            })
        }
        let result = ChordDraftRepeatSignRecognizer.recognize(
            strokes: shifted,
            chordFrame: fixture.chordFrame.offsetBy(dx: shift.x, dy: shift.y),
            pageLayout: fixture.layout
        )
        XCTAssertEqual(result.barlines.map(\.kind), [.repeatBoth])
        XCTAssertEqual(try XCTUnwrap(result.barlines.first).laneFraction, 0.45, accuracy: 0.001)
        XCTAssertEqual(result.strokeIndices, Set(shifted.indices))
    }

    func testNoLayoutAndMalformedGeometryFailWithoutClaimingSource() throws {
        let fixture = try Fixture(layoutStyle: .simpleChordSheet)
        let strokes = fixture.sign(kind: .repeatEnd, barCount: 1)
        XCTAssertTrue(ChordDraftRepeatSignRecognizer.recognize(strokes: strokes, chordFrame: fixture.chordFrame, pageLayout: nil).barlines.isEmpty)
        let invalid = InkStroke(points: [InkPoint(x: .nan, y: 4, timeOffset: nil)])
        XCTAssertTrue(fixture.recognize(strokes + [invalid]).barlines.isEmpty)
    }

    private struct Fixture {
        let layout: LeadSheetPageLayout
        let system: LeadSheetSystemLayout
        let chordFrame: CGRect
        let lane: CGRect

        init(layoutStyle: ChartLayoutStyle) throws {
            var chart = Chart.blank(title: "Repeat detector fixture", measureCount: 4, layoutStyle: layoutStyle)
            chart.engravingPreset = .balanced
            let generated = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 1180, height: 1500), includesChordInkContinuationLanes: true)
            let firstSystem = try XCTUnwrap(generated.systems.first)
            layout = generated
            system = firstSystem
            lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: firstSystem, paperFrame: generated.paperFrame(for: firstSystem)))
            chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: generated)
        }

        var barMinY: CGFloat { lane.minY + lane.height * 0.07 }
        var barMaxY: CGFloat { lane.maxY - lane.height * 0.07 }
        var barHeight: CGFloat { barMaxY - barMinY }
        var barMidY: CGFloat { (barMinY + barMaxY) / 2 }

        func boundaryX(fraction: CGFloat) -> CGFloat { lane.minX + lane.width * fraction }

        func sign(kind: DraftBarlineKind, barCount: Int, fraction: CGFloat = 0.45, stationaryDots: Bool = false) -> [InkStroke] {
            let centerX = boundaryX(fraction: fraction)
            let separation = barCount == 2 ? barHeight * 0.09 : 0
            var result = barCount == 2
                ? [bar(atX: centerX - separation / 2), bar(atX: centerX + separation / 2)]
                : [bar(atX: centerX)]
            let sides: [CGFloat]
            switch kind {
            case .repeatStart: sides = [1]
            case .repeatEnd: sides = [-1]
            case .repeatBoth: sides = [-1, 1]
            case .single: sides = []
            }
            for side in sides {
                let x = centerX + side * (separation / 2 + barHeight * 0.12)
                result += [
                    dot(atX: x, y: barMidY - barHeight * 0.12, stationary: stationaryDots),
                    dot(atX: x, y: barMidY + barHeight * 0.12, stationary: stationaryDots)
                ]
            }
            return result
        }

        func bar(atX x: CGFloat) -> InkStroke {
            stroke([CGPoint(x: x, y: barMinY), CGPoint(x: x, y: barMidY), CGPoint(x: x, y: barMaxY)])
        }

        func dot(atX x: CGFloat, y: CGFloat, stationary: Bool) -> InkStroke {
            if stationary { return stroke([CGPoint(x: x, y: y)]) }
            let radius = max(0.5, barHeight * 0.015)
            return stroke([
                CGPoint(x: x - radius, y: y), CGPoint(x: x, y: y - radius),
                CGPoint(x: x + radius, y: y), CGPoint(x: x, y: y + radius), CGPoint(x: x - radius, y: y)
            ])
        }

        func body(minX: CGFloat) -> InkStroke {
            stroke([
                CGPoint(x: minX, y: barMinY + barHeight * 0.08),
                CGPoint(x: minX + barHeight * 0.32, y: barMinY + barHeight * 0.25),
                CGPoint(x: minX, y: barMidY),
                CGPoint(x: minX + barHeight * 0.32, y: barMinY + barHeight * 0.75),
                CGPoint(x: minX, y: barMaxY - barHeight * 0.08)
            ])
        }

        func stroke(_ points: [CGPoint]) -> InkStroke {
            InkStroke(points: points.enumerated().map { index, point in
                InkPoint(x: point.x - chordFrame.minX, y: point.y - chordFrame.minY, timeOffset: Double(index) * 0.01)
            })
        }

        func recognize(_ strokes: [InkStroke]) -> ChordDraftBarlineRecognition {
            ChordDraftRepeatSignRecognizer.recognize(strokes: strokes, chordFrame: chordFrame, pageLayout: layout)
        }
    }
}
#endif

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

    func testReconstructedScreenshotRepeatGeometryRecognizesInEveryLayout() throws {
        // These paths reconstruct the proportions visible in IMG_0320/0321
        // and the November 5 follow-up screenshot.
        // They do not contain the original PencilKit paths, pen-up history, or
        // timestamps, and cannot establish that every original stroke was read.
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            for trace in ScreenshotRepeatTrace.examples {
                let strokes = fixture.reconstructedScreenshotSign(trace)
                let result = fixture.recognize(strokes)
                let context = "\(trace.imageName), \(trace.kind), \(layoutStyle)"

                XCTAssertEqual(result.barlines.map(\.kind), [trace.kind], context)
                XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), context)
                XCTAssertEqual(result.strokeIndices, Set(strokes.indices), context)
                XCTAssertEqual(result.barlines.first?.sourceStrokeGeometry, strokes, context)
            }
        }
    }

    func testReconstructedScreenshotPairsKeepBothCompleteSignsAndAllSources() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            for imageName in ["IMG_0320", "IMG_0321", "Screenshot_2026-11-05_061142"] {
                let traces = ScreenshotRepeatTrace.examples.filter { $0.imageName == imageName }
                let start = fixture.reconstructedScreenshotSign(traces[0], fraction: 0.25)
                let end = fixture.reconstructedScreenshotSign(traces[1], fraction: 0.65)
                // Reverse the stroke delivery order as well: visual pairing is
                // independent of which end of a sign the user draws first.
                for strokes in [start + end, Array((start + end).reversed())] {
                    let result = fixture.recognize(strokes)
                    let context = "\(imageName), \(layoutStyle)"
                    XCTAssertEqual(result.barlines.map(\.kind), [.repeatStart, .repeatEnd], context)
                    XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), context)
                    XCTAssertEqual(result.strokeIndices, Set(strokes.indices), context)
                    if result.barlines.count == 2 {
                        XCTAssertTrue(result.barlines[0].ownedSourceStrokeIndices
                            .isDisjoint(with: result.barlines[1].ownedSourceStrokeIndices), context)
                    }
                }
            }
        }
    }

    func testReconstructedScreenshot0321ChordBetweenRepeatsDoesNotVetoClearSeventhGap() throws {
        // Black-pixel bounds in IMG_0321 are x1047...1069 for the seventh,
        // x1104...1115 for the repeat dots, and y996...1171 for the bars.
        // The visible 35-pixel gap is about 20% of bar height. These sampled
        // paths approximate the drawing; original PencilKit paths are absent.
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let traces = ScreenshotRepeatTrace.examples.filter { $0.imageName == "IMG_0321" }
            let scale = fixture.lane.height / 319
            let anchorX = fixture.boundaryX(fraction: 0.25)
            func translate(_ point: CGPoint) -> CGPoint {
                CGPoint(x: anchorX + (point.x - 786.5) * scale,
                    y: fixture.lane.minY + (point.y - 924) * scale)
            }
            func sourceStroke(_ points: [CGPoint]) -> InkStroke {
                fixture.stroke(points.map(translate))
            }
            func sourceDot(x: CGFloat, y: CGFloat, radius: CGFloat) -> InkStroke {
                sourceStroke([
                    CGPoint(x: x - radius, y: y), CGPoint(x: x, y: y - radius),
                    CGPoint(x: x + radius, y: y), CGPoint(x: x, y: y + radius),
                    CGPoint(x: x - radius, y: y)
                ])
            }
            let start = fixture.reconstructedScreenshotSign(traces[0], fraction: 0.25)
            let chord = [
                sourceStroke([CGPoint(x: 954, y: 1125), CGPoint(x: 950, y: 1053),
                    CGPoint(x: 976, y: 1044), CGPoint(x: 982, y: 1053),
                    CGPoint(x: 961, y: 1074), CGPoint(x: 992, y: 1084),
                    CGPoint(x: 996, y: 1106), CGPoint(x: 978, y: 1125), CGPoint(x: 954, y: 1125)]),
                sourceStroke([CGPoint(x: 999, y: 1008), CGPoint(x: 1008, y: 1042),
                    CGPoint(x: 1021, y: 1031), CGPoint(x: 1027, y: 1041), CGPoint(x: 1014, y: 1049)]),
                sourceStroke([CGPoint(x: 1047, y: 994), CGPoint(x: 1069, y: 992),
                    CGPoint(x: 1068, y: 1004), CGPoint(x: 1053, y: 1035)])
            ]
            let end = traces[1].bars.map(sourceStroke) + [
                sourceDot(x: 1110, y: 1067, radius: 6),
                sourceDot(x: 1111, y: 1104, radius: 4)
            ]
            let strokes = start + chord + end
            let result = fixture.recognize(strokes)
            XCTAssertEqual(result.barlines.map(\.kind), [.repeatStart, .repeatEnd], layoutStyle.rawValue)
            XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), layoutStyle.rawValue)
            XCTAssertEqual(result.strokeIndices, Set(0..<4).union(7..<11), layoutStyle.rawValue)
            XCTAssertTrue(result.strokeIndices.isDisjoint(with: Set(4..<7)),
                "The complete Bb7 drawing must remain available to chord recognition.")
        }
    }

    func testComparableBodyInsideRepeatClearanceStillVetoesStructuralClaim() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let sign = fixture.contractSign()
            let bounds = InkBounds.enclosing(sign.map(\.bounds))
            let barBounds = sign[0].bounds
            let height = barBounds.height
            let right = bounds.minX - height * 0.10
            let body = InkStroke(points: [
                InkPoint(x: right - height * 0.25, y: barBounds.minY + height * 0.30, timeOffset: nil),
                InkPoint(x: right, y: barBounds.minY + height * 0.40, timeOffset: nil),
                InkPoint(x: right - height * 0.25, y: barBounds.minY + height * 0.65, timeOffset: nil)
            ])
            let result = fixture.recognize(sign + [body])
            XCTAssertTrue(result.barlines.isEmpty, layoutStyle.rawValue)
            XCTAssertTrue(result.strokeIndices.isEmpty, layoutStyle.rawValue)
        }
    }

    func testCompleteHalfLaneRepeatDoesNotRelaxOrdinaryBarlineCoverage() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let strokes = fixture.contractSign(heightRatio: 0.50)

            XCTAssertNil(ChordDraftBarlineRecognizer.candidate(
                for: strokes[0], chordFrame: fixture.chordFrame, pageLayout: fixture.layout),
                "Repeat evidence can admit a shorter bar without changing the plain-bar drawing rule.")
            let result = fixture.recognize(strokes)
            XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd], layoutStyle.rawValue)
            XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), layoutStyle.rawValue)
            XCTAssertEqual(result.strokeIndices, Set(strokes.indices), layoutStyle.rawValue)
        }
    }

    func testRepeatDrawingContractAcceptsHeightSpacingAndDotVariationAcrossLayouts() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let cases: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                // Height/lane, double-bar gap/height, dot x skew/height,
                // dot-pair vertical offset/height, dot separation/height.
                (0.50, 0.09, 0, 0, 0.24),
                (0.60, 0.28, 0.06, 0.04, 0.30),
                (0.86, 0.35, 0, 0, 0.24),
                (0.86, 0.09, 0.18, 0, 0.24),
                (0.86, 0.09, 0, 0.22, 0.24),
                (0.86, 0.09, 0, -0.22, 0.24),
                (0.86, 0.09, 0, 0, 0.12),
                (0.86, 0.09, 0, 0, 0.62),
                (1.35, 0.09, 0, 0, 0.24)
            ]
            for (height, gap, skew, offset, separation) in cases {
                let strokes = fixture.contractSign(heightRatio: height, barGapRatio: gap,
                    dotSkewRatio: skew, pairOffsetRatio: offset, dotSeparationRatio: separation)
                let result = fixture.recognize(strokes)
                let context = "\(layoutStyle): height \(height), gap \(gap), skew \(skew), offset \(offset), separation \(separation)"
                XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd], context)
                XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), context)
                XCTAssertEqual(result.strokeIndices, Set(strokes.indices), context)
            }
        }
    }

    func testRepeatDrawingContractCannotRenderOutsideLimits() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let cases = [
                fixture.contractSign(heightRatio: 0.49),
                fixture.contractSign(heightRatio: 1.36),
                fixture.contractSign(barGapRatio: 0.36),
                fixture.contractSign(dotSkewRatio: 0.20),
                fixture.contractSign(pairOffsetRatio: 0.24),
                fixture.contractSign(dotSeparationRatio: 0.10),
                fixture.contractSign(dotSeparationRatio: 0.64)
            ]
            for (index, strokes) in cases.enumerated() {
                let result = fixture.recognize(strokes)
                let context = "\(layoutStyle), outside-limit case \(index)"
                XCTAssertTrue(result.barlines.filter(\.isRenderable).isEmpty, context)
                if index >= 2 {
                    // A clear bar and nearby dot pair still represents repeat
                    // intent. Keep all of it out of chord recognition while
                    // asking the user to finish or rewrite the repeat.
                    XCTAssertEqual(result.barlines.map(\.ambiguity), [.incompleteRepeat], context)
                    XCTAssertEqual(result.strokeIndices, Set(strokes.indices), context)
                } else {
                    XCTAssertTrue(result.barlines.isEmpty, context)
                    XCTAssertTrue(result.strokeIndices.isEmpty, context)
                }
            }
        }
    }

    func testRepeatContractUsesLaneAndBarProportionsAcrossPageSizes() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            for pageWidth in [CGFloat(590), 1180, 2360] {
                let fixture = try Fixture(layoutStyle: layoutStyle,
                    pageSize: CGSize(width: pageWidth, height: pageWidth * 1.27))
                let strokes = fixture.contractSign(heightRatio: 0.60, barGapRatio: 0.28,
                    dotSkewRatio: 0.06, pairOffsetRatio: 0.04, dotSeparationRatio: 0.30)
                let result = fixture.recognize(strokes)
                XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd], "\(layoutStyle), \(pageWidth)")
                XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), "\(layoutStyle), \(pageWidth)")
                XCTAssertEqual(result.strokeIndices, Set(strokes.indices), "\(layoutStyle), \(pageWidth)")
                for trace in ScreenshotRepeatTrace.examples {
                    let reconstructed = fixture.reconstructedScreenshotSign(trace)
                    let screenshotResult = fixture.recognize(reconstructed)
                    let context = "\(trace.imageName), \(trace.kind), \(layoutStyle), \(pageWidth)"
                    XCTAssertEqual(screenshotResult.barlines.map(\.kind), [trace.kind], context)
                    XCTAssertTrue(screenshotResult.barlines.allSatisfy(\.isRenderable), context)
                    XCTAssertEqual(screenshotResult.strokeIndices, Set(reconstructed.indices), context)
                }
            }
        }
    }

    func testWobblyBarsAndUnevenDotPairKeepEveryOriginalStroke() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            var strokes = fixture.contractSign(heightRatio: 0.72, barGapRatio: 0.28,
                dotSkewRatio: 0.12, pairOffsetRatio: 0.10)
            for barIndex in 0..<2 {
                let first = try XCTUnwrap(strokes[barIndex].points.first)
                let last = try XCTUnwrap(strokes[barIndex].points.last)
                let height = last.y - first.y
                strokes[barIndex] = InkStroke(points: [
                    first,
                    InkPoint(x: first.x + height * 0.025, y: first.y + height * 0.25, timeOffset: 0.01),
                    InkPoint(x: first.x - height * 0.025, y: first.y + height * 0.50, timeOffset: 0.02),
                    InkPoint(x: first.x + height * 0.020, y: first.y + height * 0.75, timeOffset: 0.03),
                    last
                ])
            }
            let result = fixture.recognize(strokes)
            XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd], layoutStyle.rawValue)
            XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), layoutStyle.rawValue)
            XCTAssertEqual(result.strokeIndices, Set(strokes.indices), layoutStyle.rawValue)
            XCTAssertEqual(result.barlines.first?.sourceStrokeGeometry, strokes, layoutStyle.rawValue)
        }
    }

    func testRetracedUpperAndLowerDotsRemainTwoRegionsWithAllSourceStrokes() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            for kind in [DraftBarlineKind.repeatStart, .repeatEnd, .repeatBoth] {
                let original = fixture.sign(kind: kind, barCount: 2)
                let variants = [
                    original + [original[2]],
                    original + [original[3]],
                    original + [original[2], original[3]],
                    original + Array(original.dropFirst(2)) + Array(original.dropFirst(2))
                ]
                for (variant, source) in variants.enumerated() {
                    for strokes in [source, Array(source.reversed()), Array(source.dropFirst()) + [source[0]]] {
                        let result = fixture.recognize(strokes)
                        let context = "\(layoutStyle), \(kind), retrace \(variant)"
                        XCTAssertEqual(result.barlines.map(\.kind), [kind], context)
                        XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), context)
                        XCTAssertEqual(result.strokeIndices, Set(strokes.indices), context)
                        XCTAssertEqual(result.barlines.first?.sourceStrokeGeometry, strokes, context)
                    }
                }
            }
        }
    }

    func testFollowUpScreenshotDotsCanBeRetracedWithoutChangingTheVisibleSign() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            for trace in ScreenshotRepeatTrace.examples where trace.imageName == "Screenshot_2026-11-05_061142" {
                let original = fixture.reconstructedScreenshotSign(trace)
                let variants = [
                    original,
                    original + [original[2]],
                    original + [original[3]],
                    original + [original[2], original[3]]
                ]
                for (variant, source) in variants.enumerated() {
                    for strokes in [source, Array(source.reversed())] {
                        let result = fixture.recognize(strokes)
                        let context = "\(layoutStyle), \(trace.kind), screenshot retrace \(variant)"
                        XCTAssertEqual(result.barlines.map(\.kind), [trace.kind], context)
                        XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), context)
                        XCTAssertEqual(result.strokeIndices, Set(strokes.indices), context)
                        XCTAssertEqual(result.barlines.first?.sourceStrokeGeometry, strokes, context)
                    }
                }
            }
        }
    }

    func testCompactCrossedAndHatchedDotStrokesRecognizeAsTwoVisibleRegions() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let original = fixture.contractSign()
            let height = original[0].bounds.height
            let upper = try XCTUnwrap(original[2].points.first)
            let lower = try XCTUnwrap(original[3].points.first)
            func line(_ a: InkPoint, _ b: InkPoint) -> InkStroke { InkStroke(points: [a, b]) }
            func cross(at center: InkPoint) -> [InkStroke] {
                let radius = height * 0.045
                return [
                    line(InkPoint(x: center.x - radius, y: center.y, timeOffset: nil),
                        InkPoint(x: center.x + radius, y: center.y, timeOffset: nil)),
                    line(InkPoint(x: center.x, y: center.y - radius, timeOffset: nil),
                        InkPoint(x: center.x, y: center.y + radius, timeOffset: nil))
                ]
            }
            func hatch(at center: InkPoint) -> [InkStroke] {
                (-2...2).map { row in
                    let y = center.y + Double(row) * height * 0.015
                    return line(InkPoint(x: center.x - height * 0.045, y: y, timeOffset: nil),
                        InkPoint(x: center.x + height * 0.045, y: y, timeOffset: nil))
                }
            }
            let source = Array(original.prefix(2)) + cross(at: upper) + hatch(at: lower)
            for strokes in [source, Array(source.reversed())] {
                let result = fixture.recognize(strokes)
                XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd], layoutStyle.rawValue)
                XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), layoutStyle.rawValue)
                XCTAssertEqual(result.strokeIndices, Set(strokes.indices), layoutStyle.rawValue)
                XCTAssertEqual(result.barlines.first?.sourceStrokeGeometry, strokes, layoutStyle.rawValue)
            }
        }
    }

    func testLongBoundedDotFillDoesNotFailBecauseOfInvisibleTravelDistance() throws {
        for layoutStyle in ChartLayoutStyle.allCases {
            let fixture = try Fixture(layoutStyle: layoutStyle)
            let original = fixture.contractSign()
            let height = original[0].bounds.height
            let centers = try original.suffix(2).map { try XCTUnwrap($0.points.first) }
            let filledDots = centers.map { center in
                InkStroke(points: (0...160).map { index in
                    // Repeatedly filling one compact region changes path
                    // length, while keeping its visible extent unchanged.
                    let angle = Double(index) * .pi / 8
                    return InkPoint(x: center.x + cos(angle) * height * 0.04,
                        y: center.y + sin(angle) * height * 0.04, timeOffset: Double(index) * 0.001)
                })
            }
            XCTAssertTrue(filledDots.allSatisfy { stroke in
                zip(stroke.points, stroke.points.dropFirst()).reduce(0.0) { length, segment in
                    length + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
                } > height * 0.75
            })
            let source = Array(original.prefix(2)) + filledDots
            for strokes in [source, Array(source.reversed())] {
                let result = fixture.recognize(strokes)
                XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd], layoutStyle.rawValue)
                XCTAssertTrue(result.barlines.allSatisfy(\.isRenderable), layoutStyle.rawValue)
                XCTAssertEqual(result.strokeIndices, Set(strokes.indices), layoutStyle.rawValue)
                XCTAssertEqual(result.barlines.first?.sourceStrokeGeometry, strokes, layoutStyle.rawValue)
            }
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

    func testIncompleteDotGroupsRemainNonrenderableAndRetainSourceInk() throws {
        let fixture = try Fixture(layoutStyle: .simpleChordSheet)
        let sign = fixture.sign(kind: .repeatEnd, barCount: 1, stationaryDots: true)
        let x = fixture.boundaryX(fraction: 0.45) - fixture.barHeight * 0.12
        let badGroups = [
            [sign[0]],
            Array(sign.dropLast()),
            Array(sign.dropFirst()),
            sign + [fixture.dot(atX: x, y: fixture.barMidY, stationary: true)],
            [sign[0], fixture.dot(atX: x, y: fixture.barMidY - fixture.barHeight * 0.12, stationary: true),
             fixture.dot(atX: x - fixture.barHeight * 0.30, y: fixture.barMidY + fixture.barHeight * 0.12, stationary: true)],
            [sign[0], fixture.dot(atX: x, y: fixture.barMinY + fixture.barHeight * 0.12, stationary: true),
             fixture.dot(atX: x, y: fixture.barMinY + fixture.barHeight * 0.25, stationary: true)]
        ]
        for (index, strokes) in badGroups.enumerated() {
            let result = fixture.recognize(strokes)
            XCTAssertTrue(result.barlines.filter(\.isRenderable).isEmpty)
            if index == 0 || index == 2 {
                XCTAssertTrue(result.barlines.isEmpty, "Bars without dots, or dots without bars, do not establish repeat intent.")
                XCTAssertTrue(result.strokeIndices.isEmpty)
            } else {
                XCTAssertEqual(result.barlines.map(\.ambiguity), [.incompleteRepeat])
                XCTAssertEqual(result.strokeIndices, Set(strokes.indices))
            }
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

    private struct ScreenshotRepeatTrace {
        let imageName: String
        let laneTop: CGFloat
        let laneBottom: CGFloat
        let bars: [[CGPoint]]
        let dots: [CGPoint]
        let kind: DraftBarlineKind
        var dotRadii: [CGSize]? = nil

        static let examples: [Self] = [
            .init(imageName: "IMG_0320", laneTop: 927, laneBottom: 1062, bars: [
                [CGPoint(x: 412, y: 950), CGPoint(x: 410, y: 973), CGPoint(x: 412, y: 1005), CGPoint(x: 417, y: 1055)],
                [CGPoint(x: 431, y: 953), CGPoint(x: 432, y: 986), CGPoint(x: 432, y: 1027), CGPoint(x: 436, y: 1047)]
            ], dots: [CGPoint(x: 456, y: 984), CGPoint(x: 462, y: 1012)], kind: .repeatStart),
            .init(imageName: "IMG_0320", laneTop: 927, laneBottom: 1062, bars: [
                [CGPoint(x: 651, y: 946), CGPoint(x: 650, y: 980), CGPoint(x: 651, y: 1016), CGPoint(x: 650, y: 1046)],
                [CGPoint(x: 678, y: 951), CGPoint(x: 676, y: 985), CGPoint(x: 679, y: 1015), CGPoint(x: 677, y: 1042)]
            ], dots: [CGPoint(x: 633, y: 977), CGPoint(x: 632, y: 1014)], kind: .repeatEnd),
            .init(imageName: "IMG_0321", laneTop: 924, laneBottom: 1243, bars: [
                [CGPoint(x: 777, y: 994), CGPoint(x: 775, y: 1020), CGPoint(x: 777, y: 1054), CGPoint(x: 776, y: 1090), CGPoint(x: 777, y: 1155), CGPoint(x: 775, y: 1180)],
                [CGPoint(x: 797, y: 994), CGPoint(x: 795, y: 1021), CGPoint(x: 796, y: 1054), CGPoint(x: 796, y: 1090), CGPoint(x: 794, y: 1125), CGPoint(x: 798, y: 1166)]
            ], dots: [CGPoint(x: 822, y: 1051), CGPoint(x: 827, y: 1102)], kind: .repeatStart),
            .init(imageName: "IMG_0321", laneTop: 924, laneBottom: 1243, bars: [
                [CGPoint(x: 1126, y: 997), CGPoint(x: 1128, y: 1040), CGPoint(x: 1128, y: 1080), CGPoint(x: 1133, y: 1171)],
                [CGPoint(x: 1143, y: 1007), CGPoint(x: 1144, y: 1045), CGPoint(x: 1144, y: 1084), CGPoint(x: 1148, y: 1170)]
            ], dots: [CGPoint(x: 1110, y: 1067), CGPoint(x: 1111, y: 1104)], kind: .repeatEnd),
            // Follow-up screenshot after build 139. Dot extents are sampled
            // from black-pixel bounds; stroke contacts cannot be inferred.
            .init(imageName: "Screenshot_2026-11-05_061142", laneTop: 917, laneBottom: 1238, bars: [
                [CGPoint(x: 1026, y: 964), CGPoint(x: 1022, y: 1001), CGPoint(x: 1019, y: 1048),
                 CGPoint(x: 1022, y: 1084), CGPoint(x: 1019, y: 1125), CGPoint(x: 1022, y: 1166), CGPoint(x: 1026, y: 1192)],
                [CGPoint(x: 1049, y: 978), CGPoint(x: 1045, y: 995), CGPoint(x: 1045, y: 1033),
                 CGPoint(x: 1048, y: 1073), CGPoint(x: 1048, y: 1107), CGPoint(x: 1045, y: 1131), CGPoint(x: 1051, y: 1188)]
            ], dots: [CGPoint(x: 1077, y: 1064), CGPoint(x: 1085, y: 1119)], kind: .repeatStart,
                dotRadii: [CGSize(width: 5, height: 7), CGSize(width: 10, height: 9)]),
            .init(imageName: "Screenshot_2026-11-05_061142", laneTop: 917, laneBottom: 1238, bars: [
                [CGPoint(x: 1502, y: 976), CGPoint(x: 1498, y: 1009), CGPoint(x: 1495, y: 1048),
                 CGPoint(x: 1497, y: 1090), CGPoint(x: 1497, y: 1139), CGPoint(x: 1494, y: 1196)],
                [CGPoint(x: 1519, y: 981), CGPoint(x: 1517, y: 1028), CGPoint(x: 1518, y: 1081),
                 CGPoint(x: 1517, y: 1130), CGPoint(x: 1518, y: 1183)]
            ], dots: [CGPoint(x: 1463.5, y: 1046.5), CGPoint(x: 1464, y: 1111.5)], kind: .repeatEnd,
                dotRadii: [CGSize(width: 8.5, height: 8.5), CGSize(width: 7, height: 7.5)])
        ]
    }

    private struct Fixture {
        let layout: LeadSheetPageLayout
        let system: LeadSheetSystemLayout
        let chordFrame: CGRect
        let lane: CGRect

        init(layoutStyle: ChartLayoutStyle, pageSize: CGSize = CGSize(width: 1180, height: 1500)) throws {
            var chart = Chart.blank(title: "Repeat detector fixture", measureCount: 4, layoutStyle: layoutStyle)
            chart.engravingPreset = .balanced
            let generated = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize, includesChordInkContinuationLanes: true)
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

        func reconstructedScreenshotSign(_ trace: ScreenshotRepeatTrace, fraction: CGFloat = 0.45) -> [InkStroke] {
            let scale = lane.height / (trace.laneBottom - trace.laneTop)
            let allBarX = trace.bars.flatMap { $0.map(\.x) }
            let sourceCenterX = ((allBarX.min() ?? 0) + (allBarX.max() ?? 0)) / 2
            func translate(_ point: CGPoint) -> CGPoint {
                CGPoint(x: boundaryX(fraction: fraction) + (point.x - sourceCenterX) * scale,
                    y: lane.minY + (point.y - trace.laneTop) * scale)
            }
            // The reconstruction uses one small closed path for each visible
            // dot. Original stroke count is deliberately not inferred here.
            let reconstructedDots = trace.dots.enumerated().map { index, center in
                let point = translate(center)
                let sampledRadius = trace.dotRadii?[index] ?? CGSize(width: 2, height: 2)
                let radiusX = max(0.25, sampledRadius.width * scale)
                let radiusY = max(0.25, sampledRadius.height * scale)
                return stroke([
                    CGPoint(x: point.x - radiusX, y: point.y),
                    CGPoint(x: point.x, y: point.y - radiusY),
                    CGPoint(x: point.x + radiusX, y: point.y),
                    CGPoint(x: point.x, y: point.y + radiusY),
                    CGPoint(x: point.x - radiusX, y: point.y)
                ])
            }
            return trace.bars.map { stroke($0.map(translate)) } + reconstructedDots
        }

        func contractSign(
            heightRatio: CGFloat = 0.86,
            barGapRatio: CGFloat = 0.09,
            dotSkewRatio: CGFloat = 0,
            pairOffsetRatio: CGFloat = 0,
            dotSeparationRatio: CGFloat = 0.24
        ) -> [InkStroke] {
            let height = lane.height * heightRatio
            let centerX = boundaryX(fraction: 0.45)
            let top = lane.midY - height / 2
            let bottom = lane.midY + height / 2
            let gap = height * barGapRatio
            let leftBarX = centerX - gap / 2
            let rightBarX = centerX + gap / 2
            let dotsX = leftBarX - height * 0.16
            let pairY = lane.midY + height * pairOffsetRatio
            return [
                stroke([CGPoint(x: leftBarX, y: top), CGPoint(x: leftBarX, y: bottom)]),
                stroke([CGPoint(x: rightBarX, y: top), CGPoint(x: rightBarX, y: bottom)]),
                stroke([CGPoint(x: dotsX, y: pairY - height * dotSeparationRatio / 2)]),
                stroke([CGPoint(x: dotsX - height * dotSkewRatio,
                    y: pairY + height * dotSeparationRatio / 2)])
            ]
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

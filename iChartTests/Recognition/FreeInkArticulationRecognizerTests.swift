import XCTest
@testable import iChart

final class FreeInkArticulationRecognizerTests: XCTestCase {
    func testAccentAcceptsEitherPenDirectionAndSmallJoinGap() {
        let chevron = [(0.0, 0.0), (12, 3.3), (24, 7), (13, 10.4), (0, 14)]
        let upperLeg = [(0.0, 0.0), (11, 3), (24, 6.5)]
        let lowerLeg = [(0.5, 14.0), (12, 10.2), (23, 7.5)]

        for scale in [0.25, 1, 3.0] {
            let forward = stroke(chevron, scale: scale)
            let backward = stroke(Array(chevron.reversed()), scale: scale)
            let upper = stroke(upperLeg, scale: scale)
            let lower = stroke(Array(lowerLeg.reversed()), scale: scale)
            XCTAssertEqual(FreeInkArticulationRecognizer.recognize([forward]), .accent)
            XCTAssertEqual(FreeInkArticulationRecognizer.recognize([backward]), .accent)
            XCTAssertEqual(FreeInkArticulationRecognizer.recognize([lower, upper]), .accent)
        }
    }

    func testFermataAcceptsEitherPenDirectionAndDotOrder() {
        let arch = [(0.0, 11.0), (3, 6), (7, 2), (12, 0), (18, 1.5), (23, 5.3), (26, 10)]
        let dot = [(12.4, 7.5), (13, 7.8), (12.8, 8)]

        for scale in [0.25, 1, 3.0] {
            let forward = stroke(arch, scale: scale)
            let backward = stroke(Array(arch.reversed()), scale: scale)
            let centerDot = stroke(dot, scale: scale)
            XCTAssertEqual(FreeInkArticulationRecognizer.recognize([forward, centerDot]), .fermata)
            XCTAssertEqual(FreeInkArticulationRecognizer.recognize([centerDot, backward]), .fermata)
            XCTAssertEqual(FreeInkArticulationRecognizer.recognize([forward, stroke([(13, 9)], scale: scale)]), .fermata)
        }
    }

    func testMarcatoAcceptsAnUprightCaretWithOneOrTwoStrokes() {
        let caret = [(0.0, 14.0), (4.5, 7), (9, 0), (13.5, 6.5), (18, 13.4)]
        let left = [(0.0, 14.0), (4.5, 7), (8.7, 0)]
        let right = [(9.5, 0.6), (14, 6.8), (18, 13.4)]

        for points in [caret, Array(caret.reversed())] {
            let candidate = FreeInkArticulationRecognizer.automaticCandidate(
                in: [stroke(points)], eligibleStrokeIndices: [0]
            )
            XCTAssertEqual(candidate?.kind, .marcato)
            XCTAssertEqual(candidate?.indices, [0])
        }
        for pair in [[left, Array(right.reversed())], [right, Array(left.reversed())]] {
            let candidate = FreeInkArticulationRecognizer.automaticCandidate(
                in: [stroke(pair[0], creationTimeOffset: 1, duration: 0.2),
                     stroke(pair[1], creationTimeOffset: 1.35, duration: 0.2)],
                eligibleStrokeIndices: [0, 1]
            )
            XCTAssertEqual(candidate?.kind, .marcato)
            XCTAssertEqual(candidate?.indices, [0, 1])
        }
    }

    func testMarcatoAbstainsOnAnAmbiguousCaretOrNearbyWriting() {
        let caret = stroke([(0, 14), (4.5, 7), (9, 0), (13.5, 6.5), (18, 13.4)])
        let dot = stroke([(9, 9)])
        let crossbar = stroke([(4, 9), (14, 9)])
        let inverted = stroke([(0, 0), (4.5, 7), (9, 14), (13.5, 7.5), (18, 0)])
        let wideGap = [stroke([(0, 14), (7, 0)]), stroke([(11, 0), (18, 14)])]
        XCTAssertNil(FreeInkArticulationRecognizer.recognize(wideGap))
        XCTAssertNil(FreeInkArticulationRecognizer.recognize([inverted]))
        for strokes in [[caret, dot], [dot, caret], [crossbar, caret], [caret, crossbar]] {
            XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(
                in: strokes, eligibleStrokeIndices: [0, 1]
            ))
        }
    }

    func testMarcatoAcceptsApexStartWithOneRetracedLeg() {
        // Normalized centerline of the build 117 miss. The writer drew down
        // the shorter leg, retraced to the tip, and drew the longer leg.
        let points = [(4.67, 0.0), (3.77, 1.27), (2.76, 2.33), (0.90, 4.50), (0, 5.72),
            (1.43, 4.13), (2.33, 2.81), (2.97, 1.69), (4.14, 0.05), (5.09, 1.38),
            (5.57, 2.59), (6.05, 3.97), (6.47, 5.40), (7.58, 8.31), (8.86, 9.69)]
        let mirrored = points.map { x, y in (8.86 - x, y) }
        for motion in [points, Array(points.reversed()), mirrored, Array(mirrored.reversed())] {
            let candidate = FreeInkArticulationRecognizer.automaticCandidate(
                in: [stroke(motion)], eligibleStrokeIndices: [0]
            )
            XCTAssertEqual(candidate?.kind, .marcato)
            XCTAssertEqual(candidate?.indices, [0])
        }

        let falseRetrace = [(6.8, 0.0), (4.3, 2.1), (2.1, 4.0)] + Array(points.dropFirst(4))
        let sameSide = Array(points.prefix(9)) + [(3.2, 2.8), (2, 5.8), (1, 9.7)]
        XCTAssertNil(FreeInkArticulationRecognizer.recognize([stroke(falseRetrace)]))
        XCTAssertNil(FreeInkArticulationRecognizer.recognize([stroke(sameSide)]))

        let caret = stroke(points)
        let dot = stroke([(4.5, 6)])
        for strokes in [[caret, dot], [dot, caret]] {
            XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(
                in: strokes, eligibleStrokeIndices: [0, 1]
            ))
        }
    }

    func testRejectsPartialMarksAndAmbiguousSelections() {
        let arch = stroke([(0, 11), (3, 6), (7, 2), (12, 0), (18, 1.5), (23, 5.3), (26, 10)])
        let caret = stroke([(0, 11), (6, 5.5), (12, 0), (19, 5.5), (26, 11)])
        let dot = stroke([(13, 8)])
        let dash = stroke([(10, 8), (17, 8)])
        let accent = stroke([(0, 0), (12, 3.3), (24, 7), (13, 10.4), (0, 14)])

        let rejectedSelections = [
            [], [arch], [arch, stroke([(25, 8)])], [arch, stroke([(13, -3)])],
            [arch, dash], [caret, dot], [arch, dot, accent], [accent, dot],
            [stroke([(24, 0), (0, 7), (24, 14)])],
            [stroke([(0, 0), (12, 9), (24, 12), (12, 15), (0, 24)])],
            [stroke([(0, 0), (24, 7)]), stroke([(0, 14), (23, 11)])],
            [stroke([(0, 0), (24, 0), (24, 14)])],
            [stroke([(0, 0), (.infinity, 7), (0, 14)])]
        ]

        for (index, selection) in rejectedSelections.enumerated() {
            XCTAssertNil(FreeInkArticulationRecognizer.recognize(selection), "Selection \(index)")
        }
    }

    func testAutomaticAccentUsesOnlyTheNewestIsolatedStroke() {
        let oldNote = stroke([(56, 26), (57, 13), (57, 5)])
        let accent = stroke([(0, 0), (12, 3.3), (24, 7), (13, 10.4), (0, 14)])

        let result = FreeInkArticulationRecognizer.automaticCandidate(in: [oldNote, accent], eligibleStrokeIndices: [1])
        XCTAssertEqual(result?.kind, .accent)
        XCTAssertEqual(result?.indices, [1])
        XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(in: [oldNote, accent], eligibleStrokeIndices: [0]))
        XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(in: [accent, oldNote], eligibleStrokeIndices: [0, 1]))
    }

    func testAutomaticAccentAcceptsOneRoundedLegOrAnUnevenTip() {
        let rounded = [(0.0, 0.0), (12, 6.1), (24, 7), (12, 11), (0, 14)]
        let uneven = [(0.0, 0.0), (12, 1.5), (24, 3.4), (12, 8.7), (0, 14)]
        for points in [rounded, uneven] {
            for direction in [points, Array(points.reversed())] {
                let candidate = FreeInkArticulationRecognizer.automaticCandidate(
                    in: [stroke(direction)], eligibleStrokeIndices: [0]
                )
                XCTAssertEqual(candidate?.kind, .accent)
                XCTAssertEqual(candidate?.indices, [0])
            }
        }

        let overbent = [(0.0, 0.0), (12, 7.4), (24, 7), (12, 11), (0, 14)]
        let tooUneven = [(0.0, 0.0), (12, 1), (24, 2.7), (12, 8), (0, 14)]
        for points in [overbent, tooUneven] {
            XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(
                in: [stroke(points)], eligibleStrokeIndices: [0]
            ))
        }
    }

    func testAutomaticAccentAcceptsShortRetraceAtTheOpenEndOfAnUnevenChevron() {
        // Approximate a shallow upper leg with a short Pencil retrace at
        // its open end. The right tip is still shared by two straight legs.
        let points = [(8.0, 0.0), (5.5, 0.1), (3.1, 0.6), (6, 1), (10.8, 1.3),
            (13.3, 2.2), (10, 5.4), (6.6, 8), (0, 12)]

        for chevron in [points, Array(points.reversed())] {
            let result = FreeInkArticulationRecognizer.automaticCandidate(
                in: [stroke(chevron)], eligibleStrokeIndices: [0]
            )
            XCTAssertEqual(result?.kind, .accent)
            XCTAssertEqual(result?.indices, [0])
        }

        let excessiveRetrace = [(12.5, 0.0)] + Array(points.dropFirst())
        let leftChevron = points.map { x, y in (13.3 - x, y) }
        let caret = points.map { x, y in (y, 13.3 - x) }
        for otherMark in [excessiveRetrace, leftChevron, caret] {
            XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(
                in: [stroke(otherMark)], eligibleStrokeIndices: [0]
            ))
        }
    }

    func testAutomaticTwoStrokeMarkRequiresFreshContiguousStrokesWrittenTogether() {
        let arch = stroke([(0, 11), (3, 6), (7, 2), (12, 0), (18, 1.5), (23, 5.3), (26, 10)],
            creationTimeOffset: 1, duration: 0.31)
        let dot = stroke([(13, 8)], creationTimeOffset: 1.58)
        let distantStroke = stroke([(70, 22), (80, 22)], creationTimeOffset: 1.2)

        let result = FreeInkArticulationRecognizer.automaticCandidate(in: [arch, dot], eligibleStrokeIndices: [0, 1])
        XCTAssertEqual(result?.kind, .fermata)
        XCTAssertEqual(result?.indices, [0, 1])
        XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(in: [arch, dot], eligibleStrokeIndices: [1]))
        XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(
            in: [arch, distantStroke, dot], eligibleStrokeIndices: [0, 2]
        ))
        let lateDot = stroke([(13, 8)], creationTimeOffset: 2.0)
        XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(in: [arch, lateDot], eligibleStrokeIndices: [0, 1]))
    }

    func testAutomaticMarkLeavesNearbyOlderAndFreshOrdinaryInkAlone() {
        let accent = stroke([(0, 0), (12, 3.3), (24, 7), (13, 10.4), (0, 14)])
        let nearbySlash = stroke([(28, 1), (26, 11)])
        XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(
            in: [nearbySlash, accent], eligibleStrokeIndices: [1]
        ))
        XCTAssertNil(FreeInkArticulationRecognizer.automaticCandidate(
            in: [nearbySlash, accent], eligibleStrokeIndices: [0, 1]
        ))
    }

    private func stroke(
        _ points: [(Double, Double)],
        scale: Double = 1,
        creationTimeOffset: TimeInterval? = nil,
        duration: TimeInterval? = nil
    ) -> InkStroke {
        InkStroke(points: points.enumerated().map { index, point in
            InkPoint(x: point.0 * scale + 80, y: point.1 * scale + 40,
                timeOffset: duration.map { $0 * Double(index) / Double(max(points.count - 1, 1)) })
        }, creationTimeOffset: creationTimeOffset)
    }
}

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

    private func stroke(_ points: [(Double, Double)], scale: Double = 1) -> InkStroke {
        InkStroke(points: points.map { x, y in
            InkPoint(x: x * scale + 80, y: y * scale + 40, timeOffset: nil)
        })
    }
}

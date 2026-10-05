#if canImport(UIKit)
import XCTest
import PencilKit
@testable import iChart

final class ChordInkEditedTargetPreparationTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 600, height: 300)
    private func stroke(_ points: [CGPoint], time: Double) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(
            controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.02,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1,
                    azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSince1970: time)))
    }
    private var original: [PKStroke] {
        [stroke([CGPoint(x: 10, y: 10), CGPoint(x: 22, y: 40)], time: 1),
         stroke([CGPoint(x: 28, y: 12), CGPoint(x: 50, y: 36)], time: 2)]
    }
    private var replacement: PKStroke {
        stroke([CGPoint(x: 30, y: 18), CGPoint(x: 46, y: 30)], time: 90)
    }
    private func seededOwnership() -> ChordInkEditedTargetOwnership {
        let input = PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: original))
        return ChordInkEditedTargetOwnership().resolving([.init(lane: 0, strokes: input)],
                                                       visibleStrokes: input).next
    }

    func testBridgePreservesExactVisiblePencilKitInkAndExhaustiveIndexPartition() throws {
        let drawing = PKDrawing(strokes: [original[0], replacement])
        let ink = PencilKitInkAdapter.inkStrokes(from: drawing)
        let measureID = UUID()
        let targets = ink.indices.map { index in
            let single = PKDrawing(strokes: [drawing.strokes[index]])
            return LeadSheetChordInkRecognitionBatchTarget(measureID: measureID, fraction: 0.2,
                visualOrder: 0.2, laneLocation: .init(systemIndex: 0, fraction: 0.2),
                recognitionStrokeIndices: [index], strokes: [ink[index]],
                drawingData: single.dataRepresentation(), drawing: single)
        }
        let result = ChordInkEditedTargetPreparation.resolve(targets, ownership: seededOwnership(),
            visibleStrokes: ink, recognitionStrokes: ink, recognitionDrawing: drawing,
            chordFrame: frame, pageLayout: nil)
        XCTAssertEqual(result.targets.count, 1)
        let target = try XCTUnwrap(result.targets.first)
        XCTAssertEqual(target.recognitionStrokeIndices, [0, 1])
        XCTAssertEqual(target.strokes, ink)
        XCTAssertTrue(target.requiresEditReview)
        let saved = try PKDrawing(data: target.drawingData)
        XCTAssertEqual(PencilKitInkAdapter.inkStrokes(from: saved), ink)
        XCTAssertEqual(saved.strokes.map(\.randomSeed), drawing.strokes.map(\.randomSeed))
        XCTAssertEqual(saved.strokes.map(\.transform), drawing.strokes.map(\.transform))
        XCTAssertEqual(saved.strokes.map { $0.path.creationDate }, drawing.strokes.map { $0.path.creationDate })
    }

    func testBridgeDoesNotGuessWhenRecognitionIndicesDisagreeWithVisibleInk() {
        let drawing = PKDrawing(strokes: [original[0], replacement])
        let ink = PencilKitInkAdapter.inkStrokes(from: drawing)
        let target = LeadSheetChordInkRecognitionBatchTarget(measureID: UUID(), fraction: 0,
            visualOrder: 0, laneLocation: .init(systemIndex: 0, fraction: 0),
            recognitionStrokeIndices: [99], strokes: ink, drawingData: drawing.dataRepresentation(), drawing: drawing)
        let result = ChordInkEditedTargetPreparation.resolve([target], ownership: seededOwnership(),
            visibleStrokes: ink, recognitionStrokes: ink, recognitionDrawing: drawing,
            chordFrame: frame, pageLayout: nil)
        XCTAssertEqual(result.targets.count, 1)
        XCTAssertEqual(result.targets[0].drawingData, target.drawingData)
        XCTAssertTrue(result.targets[0].requiresEditReview)
    }

    func testBridgeSplitsMixedTargetWithoutChangingAnyPencilKitStroke() throws {
        let neighbor = stroke([CGPoint(x: 80, y: 12), CGPoint(x: 95, y: 42)], time: 3)
        let initial = PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: original + [neighbor]))
        let ownership = ChordInkEditedTargetOwnership().resolving([
            .init(lane: 0, strokes: Array(initial.prefix(2))), .init(lane: 0, strokes: [initial[2]])
        ], visibleStrokes: initial).next
        let drawing = PKDrawing(strokes: [original[0], neighbor, replacement])
        let input = PencilKitInkAdapter.inkStrokes(from: drawing)
        let mixed = LeadSheetChordInkRecognitionBatchTarget(measureID: UUID(), fraction: 0.2,
            visualOrder: 0.2, laneLocation: .init(systemIndex: 0, fraction: 0.2),
            recognitionStrokeIndices: [0, 1, 2], strokes: input,
            drawingData: drawing.dataRepresentation(), drawing: drawing)
        let output = ChordInkEditedTargetPreparation.resolve([mixed], ownership: ownership,
            visibleStrokes: input, recognitionStrokes: input, recognitionDrawing: drawing,
            chordFrame: frame, pageLayout: nil)
        XCTAssertEqual(output.targets.map(\.recognitionStrokeIndices), [[0, 2], [1]])
        XCTAssertEqual(output.targets.map(\.requiresEditReview), [true, false])
        for target in output.targets {
            let indices = target.recognitionStrokeIndices
            XCTAssertEqual(target.strokes, indices.map { input[$0] })
            let saved = try PKDrawing(data: target.drawingData)
            XCTAssertEqual(saved.strokes.map(\.randomSeed), indices.map { drawing.strokes[$0].randomSeed })
            XCTAssertEqual(saved.strokes.map(\.transform), indices.map { drawing.strokes[$0].transform })
            XCTAssertEqual(saved.strokes.map { $0.path.creationDate }, indices.map { drawing.strokes[$0].path.creationDate })
            for (restored, index) in zip(saved.strokes, indices) {
                XCTAssertEqual(restored.path.map(\.location), drawing.strokes[index].path.map(\.location))
                XCTAssertEqual(restored.path.map(\.force), drawing.strokes[index].path.map(\.force))
            }
        }
    }

    func testSessionResetsForChartLayoutStyleAndExplicitClearAndIgnoresStaleScope() {
        let base = ChordInkEditedTargetSessionState.Scope(chartID: UUID(), chordFrame: frame,
                                                        pageLayout: nil, layoutStyle: .simpleChordSheet)
        var scopes = [base, base, base]
        scopes[0].chartID = UUID()
        scopes[1].chordFrame.origin.x += 30
        scopes[2].layoutStyle = .rhythmSectionSheet
        let erased = PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: [original[0]]))
        for changed in scopes {
            var state = ChordInkEditedTargetSessionState()
            _ = state.snapshot(in: base)
            state.accept(seededOwnership(), in: base)
            XCTAssertEqual(state.snapshot(in: base).resolving([.init(lane: 0, strokes: erased)], visibleStrokes: erased).requiresReview, [0])
            _ = state.snapshot(in: changed)
            state.accept(seededOwnership(), in: base)
            XCTAssertTrue(state.snapshot(in: changed).resolving([.init(lane: 0, strokes: erased)], visibleStrokes: erased).requiresReview.isEmpty)
            state.accept(seededOwnership(), in: changed)
            state.reset()
            XCTAssertTrue(state.snapshot(in: changed).resolving([.init(lane: 0, strokes: erased)], visibleStrokes: erased).requiresReview.isEmpty)
        }
    }
}
#endif

#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkEvaluationSourcePreparationTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testOptInRetainsExactRequestAndMixedBarlineOwnershipInBothStyles() throws {
        for style in styles {
            let fixture = try layoutFixture(style)
            let lane = fixture.lanes[0]
            let center = localCenter(lane, frame: fixture.frame)
            let line = stroke(points: [
                CGPoint(x: center.x, y: center.y - lane.height * 0.4),
                CGPoint(x: center.x, y: center.y + lane.height * 0.4)
            ], creation: 101)
            let drawing = PKDrawing(strokes: [
                diagonal(at: CGPoint(x: center.x - 100, y: center.y), creation: 100),
                line,
                diagonal(at: CGPoint(x: center.x + 100, y: center.y), creation: 102)
            ])
            let request = makeRequest(drawing, fixture: fixture, style: style)
            let result = ChordInkRecognitionPreparation.prepare(request)
            let source = try XCTUnwrap(result.evaluationSource, style.rawValue)
            XCTAssertEqual(source.normalizedDrawingData, request.drawingData)
            XCTAssertEqual(source.chordFrame, request.chordFrame)
            XCTAssertEqual(source.pageLayout, fixture.layout)
            XCTAssertEqual(source.pageBounds, fixture.layout.pageBounds)
            XCTAssertEqual(source.outcome, "ready")
            XCTAssertEqual(source.ownership.sourcePencilStrokeCount, 3)
            XCTAssertEqual(source.ownership.visibleFragmentSourceStrokeIndices, [0, 1, 2])
            XCTAssertEqual(source.ownership.barlineVisibleFragmentIndices, [1])
            XCTAssertEqual(source.recognitionVisibleFragmentIndices, [0, 2])
            XCTAssertEqual(result.recognitionStrokeCount, 2)
            XCTAssertEqual(result.barlines.map(\.sourceStrokeIndex), [1])
            XCTAssertTrue(source.ownership.unassignedVisibleFragmentIndices.isEmpty)
            try assertExhaustiveSource(result, request: request)
        }
    }

    func testAllBarlineInputRetainsSourceWithoutRecognitionDataInBothStyles() throws {
        for style in styles {
            let fixture = try layoutFixture(style)
            let lane = fixture.lanes[0]
            let center = localCenter(lane, frame: fixture.frame)
            let drawing = PKDrawing(strokes: [stroke(points: [
                CGPoint(x: center.x, y: center.y - lane.height * 0.4),
                CGPoint(x: center.x, y: center.y + lane.height * 0.4)
            ])])
            let request = makeRequest(drawing, fixture: fixture, style: style)
            let result = ChordInkRecognitionPreparation.prepare(request)
            guard case .noRecognitionData = result.outcome else {
                XCTFail("Expected all-barline preparation in \(style.rawValue)"); continue
            }
            let source = try XCTUnwrap(result.evaluationSource)
            XCTAssertEqual(source.outcome, "noRecognitionData")
            XCTAssertEqual(source.visibleStrokes.count, 1)
            XCTAssertEqual(source.ownership.barlineVisibleFragmentIndices, [0])
            XCTAssertTrue(source.recognitionVisibleFragmentIndices.isEmpty)
            XCTAssertTrue(source.recognitionStrokes.isEmpty)
            XCTAssertTrue(source.ownership.targetGroups.isEmpty)
            XCTAssertTrue(source.ownership.unassignedVisibleFragmentIndices.isEmpty)
            try assertExhaustiveSource(result, request: request)
        }
    }

    func testOversizedLocatedTargetRetainsReviewOnlySourceInBothStyles() throws {
        for style in styles {
            let fixture = try layoutFixture(style)
            let first = localCenter(fixture.lanes[0], frame: fixture.frame)
            let second = localCenter(fixture.lanes[1], frame: fixture.frame)
            let oversized = (0..<17).map { diagonal(at: second, creation: 101 + Double($0) * 0.1) }
            let drawing = PKDrawing(strokes: [diagonal(at: first)] + oversized)
            let request = makeRequest(drawing, fixture: fixture, style: style)
            let result = ChordInkRecognitionPreparation.prepare(request)
            guard case .ready(let requests, let usesBatch) = result.outcome else {
                XCTFail("Expected the admitted target in \(style.rawValue)"); continue
            }
            XCTAssertTrue(usesBatch)
            XCTAssertEqual(result.rawBatchTargetCount, 2)
            XCTAssertEqual(result.boundedBatchTargetCount, 1)
            XCTAssertEqual(requests.count, 2)
            XCTAssertEqual(requests.map(\.requiresManualReviewOnly), [false, true])
            let source = try XCTUnwrap(result.evaluationSource)
            XCTAssertEqual(source.visibleStrokes.count, 18)
            XCTAssertEqual(source.recognitionVisibleFragmentIndices, Array(0..<18))
            XCTAssertEqual(source.ownership.targetGroups.map(\.visibleFragmentIndices), [[0], Array(1..<18)])
            XCTAssertTrue(source.ownership.unassignedVisibleFragmentIndices.isEmpty)
            try assertExhaustiveSource(result, request: request)
        }
    }

    func testAllOversizedLocatedTargetsRemainReviewOnlyWithoutRecognitionAdmissionInBothStyles() throws {
        for style in styles {
            let fixture = try layoutFixture(style)
            let drawing = PKDrawing(strokes: fixture.lanes.prefix(2).enumerated().flatMap { laneIndex, lane in
                (0..<17).map { diagonal(at: localCenter(lane, frame: fixture.frame),
                                       creation: 100 + Double(laneIndex * 17 + $0) * 0.1) }
            })
            let request = makeRequest(drawing, fixture: fixture, style: style)
            let result = ChordInkRecognitionPreparation.prepare(request)
            guard case .ready(let requests, let usesBatch) = result.outcome else {
                XCTFail("Expected both oversized targets to remain reviewable in \(style.rawValue)"); continue
            }
            XCTAssertTrue(usesBatch)
            XCTAssertEqual(requests.count, 2)
            XCTAssertTrue(requests.allSatisfy(\.requiresManualReviewOnly))
            XCTAssertEqual(result.rawBatchTargetCount, 2)
            XCTAssertEqual(result.boundedBatchTargetCount, 0)
            let source = try XCTUnwrap(result.evaluationSource)
            XCTAssertEqual(source.outcome, "ready")
            XCTAssertEqual(source.visibleStrokes.count, 34)
            XCTAssertEqual(source.recognitionVisibleFragmentIndices, Array(0..<34))
            XCTAssertEqual(source.ownership.targetGroups.map(\.visibleFragmentIndices), [Array(0..<17), Array(17..<34)])
            XCTAssertTrue(source.ownership.unassignedVisibleFragmentIndices.isEmpty)
            try assertExhaustiveSource(result, request: request)
        }
    }

    func testBitmapIslandsRetainOneToManyOriginalMappingInBothStyles() throws {
        for style in styles {
            let fixture = try layoutFixture(style)
            let centers = fixture.lanes.prefix(2).map { localCenter($0, frame: fixture.frame) }
            let mask = UIBezierPath()
            for center in centers {
                mask.append(UIBezierPath(rect: CGRect(x: center.x - 28, y: center.y - 28, width: 56, height: 56)))
            }
            let drawing = PKDrawing(strokes: [stroke(points: centers.flatMap { center in
                [CGPoint(x: center.x - 12, y: center.y - 20), CGPoint(x: center.x + 12, y: center.y + 20)]
            }, mask: mask)])
            let request = makeRequest(drawing, fixture: fixture, style: style)
            let result = ChordInkRecognitionPreparation.prepare(request)
            let source = try XCTUnwrap(result.evaluationSource)
            XCTAssertEqual(source.outcome, "ready")
            XCTAssertEqual(source.ownership.sourcePencilStrokeCount, 1)
            XCTAssertEqual(source.ownership.visibleFragmentSourceStrokeIndices, [0, 0])
            XCTAssertEqual(source.visibleStrokes.count, 2)
            XCTAssertEqual(source.recognitionVisibleFragmentIndices, [0, 1])
            XCTAssertEqual(source.ownership.targetGroups.map(\.visibleFragmentIndices), [[0], [1]])
            XCTAssertTrue(source.ownership.barlineVisibleFragmentIndices.isEmpty)
            XCTAssertTrue(source.ownership.unassignedVisibleFragmentIndices.isEmpty)
            try assertExhaustiveSource(result, request: request)
        }
    }

    func testEmptyAndFullyErasedInputRetainNoVisibleSourceInBothStyles() throws {
        for style in styles {
            let fixture = try layoutFixture(style)
            let hidden = diagonal(at: localCenter(fixture.lanes[0], frame: fixture.frame),
                                  mask: UIBezierPath(rect: CGRect(x: -500, y: -500, width: 20, height: 20)))
            for drawing in [PKDrawing(), PKDrawing(strokes: [hidden])] {
                let request = makeRequest(drawing, fixture: fixture, style: style)
                let result = ChordInkRecognitionPreparation.prepare(request)
                guard case .noVisibleStrokes = result.outcome else {
                    XCTFail("Expected no visible input in \(style.rawValue)"); continue
                }
                let source = try XCTUnwrap(result.evaluationSource)
                XCTAssertEqual(source.outcome, "noVisibleStrokes")
                XCTAssertEqual(source.ownership.sourcePencilStrokeCount, drawing.strokes.count)
                XCTAssertTrue(source.visibleStrokes.isEmpty)
                XCTAssertTrue(source.recognitionVisibleFragmentIndices.isEmpty)
                XCTAssertTrue(source.ownership.targetGroups.isEmpty)
                try assertExhaustiveSource(result, request: request)
            }
        }
    }

    func testWeakLocatedSingleTargetIsReviewOnlyButMissingLayoutKeepsTargetlessOwnership() throws {
        let fixture = try layoutFixture(.simpleChordSheet)
        let center = localCenter(fixture.lanes[0], frame: fixture.frame)
        let weak = PKDrawing(strokes: [stroke(points: [
            CGPoint(x: center.x - 3, y: center.y - 3), CGPoint(x: center.x + 3, y: center.y + 3)
        ])])
        let weakRequest = makeRequest(weak, fixture: fixture, style: .simpleChordSheet)
        let skipped = ChordInkRecognitionPreparation.prepare(weakRequest)
        guard case .ready(let requests, let usesBatch) = skipped.outcome else {
            XCTFail("Expected weak single target to remain reviewable"); return
        }
        XCTAssertFalse(usesBatch)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].requiresManualReviewOnly)
        let skippedSource = try XCTUnwrap(skipped.evaluationSource)
        XCTAssertEqual(skippedSource.outcome, "ready")
        XCTAssertEqual(skippedSource.ownership.targetGroups.map(\.visibleFragmentIndices), [[0]])
        XCTAssertTrue(skippedSource.ownership.unassignedVisibleFragmentIndices.isEmpty)
        try assertExhaustiveSource(skipped, request: weakRequest)

        var missingLayout = makeRequest(PKDrawing(strokes: [diagonal(at: center)]),
                                        fixture: fixture, style: .simpleChordSheet)
        missingLayout.pageLayout = nil
        let missing = ChordInkRecognitionPreparation.prepare(missingLayout)
        guard case .noTarget = missing.outcome else { XCTFail("Expected missing-layout target failure"); return }
        let missingSource = try XCTUnwrap(missing.evaluationSource)
        XCTAssertEqual(missingSource.outcome, "noTarget")
        XCTAssertNil(missingSource.pageBounds)
        XCTAssertEqual(missingSource.ownership.unassignedVisibleFragmentIndices, [0])
        try assertExhaustiveSource(missing, request: missingLayout)
    }

    func testOptOutHasNoSourceAndKeepsExactProductionTargetInputsInBothStyles() throws {
        for style in styles {
            let fixture = try layoutFixture(style)
            let drawing = PKDrawing(strokes: fixture.lanes.prefix(2).map { diagonal(at: localCenter($0, frame: fixture.frame)) })
            var request = makeRequest(drawing, fixture: fixture, style: style)
            request.capturesEvaluationSource = false
            let optOut = ChordInkRecognitionPreparation.prepare(request)
            XCTAssertNil(optOut.evaluationSource)
            request.capturesEvaluationSource = true
            let optIn = ChordInkRecognitionPreparation.prepare(request)
            guard case .ready(let originalRequests, let originalBatch) = optOut.outcome,
                  case .ready(let capturedRequests, let capturedBatch) = optIn.outcome else {
                XCTFail("Expected equivalent ready preparation in \(style.rawValue)"); continue
            }
            XCTAssertEqual(originalBatch, capturedBatch)
            XCTAssertEqual(originalRequests.map(\.strokes), capturedRequests.map(\.strokes))
            XCTAssertEqual(originalRequests.map { $0.target.measureID }, capturedRequests.map { $0.target.measureID })
            XCTAssertEqual(originalRequests.map { $0.target.fraction }, capturedRequests.map { $0.target.fraction })
            XCTAssertEqual(optOut.ownershipSnapshot, optIn.ownershipSnapshot)
            XCTAssertEqual(optOut.recognitionStrokeCount, optIn.recognitionStrokeCount)
            XCTAssertEqual(optOut.rawBatchTargetCount, optIn.rawBatchTargetCount)
            XCTAssertEqual(optOut.boundedBatchTargetCount, optIn.boundedBatchTargetCount)
            XCTAssertNotNil(optIn.evaluationSource)
        }
    }

    func testCancelledAndInvalidDrawingRequestsNeverRetainSource() throws {
        let fixture = try layoutFixture(.simpleChordSheet)
        let drawing = PKDrawing(strokes: [diagonal(at: localCenter(fixture.lanes[0], frame: fixture.frame))])
        let request = makeRequest(drawing, fixture: fixture, style: .simpleChordSheet)
        let immediatelyCancelled = ChordInkRecognitionPreparation.prepare(request, shouldContinue: { false })
        guard case .cancelled = immediatelyCancelled.outcome else { XCTFail("Expected cancellation"); return }
        XCTAssertNil(immediatelyCancelled.evaluationSource)
        var calls = 0
        let laterCancelled = ChordInkRecognitionPreparation.prepare(request) { calls += 1; return calls < 6 }
        guard case .cancelled = laterCancelled.outcome else { XCTFail("Expected cancellation after source conversion"); return }
        XCTAssertNil(laterCancelled.evaluationSource)
        var invalid = request
        invalid.drawingData = Data("invalid PencilKit drawing".utf8)
        let rejected = ChordInkRecognitionPreparation.prepare(invalid)
        guard case .invalidDrawingData = rejected.outcome else { XCTFail("Expected invalid drawing"); return }
        XCTAssertNil(rejected.evaluationSource)
    }

    private struct Fixture {
        let layout: LeadSheetPageLayout
        let frame: CGRect
        let lanes: [CGRect]
    }

    private func layoutFixture(_ style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.draft(title: "Synthetic evaluation source", layoutStyle: style)
        chart.completeInitialSetup(title: "Synthetic evaluation source", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 8)
        XCTAssertTrue(chart.insertSystemBreak(before: chart.measures[4].id))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_200))
        let lanes = LeadSheetActiveInkScope.chordWritingInputFrames(for: layout)
        guard lanes.count >= 2 else { throw NSError(domain: "Evaluation source fixture requires two lanes", code: 1) }
        return Fixture(layout: layout, frame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), lanes: lanes)
    }

    private func makeRequest(_ drawing: PKDrawing, fixture: Fixture,
                             style: ChartLayoutStyle) -> ChordInkRecognitionPreparationRequest {
        ChordInkRecognitionPreparationRequest(requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            drawingData: drawing.dataRepresentation(), chordFrame: fixture.frame, pageLayout: fixture.layout,
            flow: .draftPreview, options: .live, layoutStyle: style, capturesEvaluationSource: true)
    }

    private func localCenter(_ lane: CGRect, frame: CGRect) -> CGPoint {
        CGPoint(x: lane.midX - frame.minX, y: lane.midY - frame.minY)
    }

    private func diagonal(at center: CGPoint, creation: Double = 100, mask: UIBezierPath? = nil) -> PKStroke {
        stroke(points: [CGPoint(x: center.x - 12, y: center.y - 15),
                        CGPoint(x: center.x + 12, y: center.y + 15)], creation: creation, mask: mask)
    }

    private func stroke(points: [CGPoint], creation: Double = 100, mask: UIBezierPath? = nil) -> PKStroke {
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.05, size: CGSize(width: 2, height: 2),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSince1970: creation)), mask: mask)
    }

    private func assertExhaustiveSource(_ result: ChordInkRecognitionPreparationResult,
                                        request: ChordInkRecognitionPreparationRequest,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try XCTUnwrap(result.evaluationSource, file: file, line: line)
        let original = try PKDrawing(data: request.drawingData)
        let visible = ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(from: original)
        XCTAssertEqual(source.normalizedDrawingData, request.drawingData, file: file, line: line)
        XCTAssertEqual(source.ownership, result.ownershipSnapshot, file: file, line: line)
        XCTAssertEqual(source.ownership.sourcePencilStrokeCount, original.strokes.count, file: file, line: line)
        XCTAssertEqual(source.ownership.visibleFragmentSourceStrokeIndices, visible.originalStrokeIndices, file: file, line: line)
        XCTAssertEqual(source.visibleStrokes, PencilKitInkAdapter.inkStrokes(from: visible.drawing), file: file, line: line)
        XCTAssertEqual(source.recognitionStrokes.count, result.recognitionStrokeCount, file: file, line: line)
        let partition = source.ownership.barlineVisibleFragmentIndices
            + source.ownership.targetGroups.flatMap(\.visibleFragmentIndices)
            + source.ownership.unassignedVisibleFragmentIndices
        XCTAssertEqual(partition.sorted(), Array(source.visibleStrokes.indices), file: file, line: line)
        XCTAssertEqual(Set(partition).count, partition.count, file: file, line: line)
        XCTAssertEqual(source.recognitionVisibleFragmentIndices,
            source.visibleStrokes.indices.filter { !source.ownership.barlineVisibleFragmentIndices.contains($0) }, file: file, line: line)
        if case .ready(let requests, _) = result.outcome {
            XCTAssertEqual(source.ownership.targetGroups.count, requests.count, file: file, line: line)
            for (group, target) in zip(source.ownership.targetGroups, requests) {
                XCTAssertEqual(group.visibleFragmentIndices.map { source.visibleStrokes[$0] }, target.strokes, file: file, line: line)
            }
        }
    }
}
#endif

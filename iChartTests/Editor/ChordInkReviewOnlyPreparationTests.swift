#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkReviewOnlyPreparationTests: XCTestCase {
    func testOversizedLocatedBatchBypassesReaderAndPreservesSourceForManualReviewInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try makeFixture(style)
            let drawing = PKDrawing(strokes: fixture.centers.prefix(2).enumerated().flatMap { lane, center in
                (0..<17).map { diagonal(center, creation: Double(lane * 17 + $0)) }
            })
            let preparation = ChordInkRecognitionPreparation.prepare(request(drawing, fixture: fixture, style: style))
            guard case .ready(let requests, let batch) = preparation.outcome else {
                XCTFail("Located oversized ink must remain reviewable"); continue
            }
            XCTAssertTrue(batch)
            XCTAssertEqual(preparation.rawBatchTargetCount, 2)
            XCTAssertEqual(preparation.boundedBatchTargetCount, 0, "Recognition's load ceiling is unchanged")
            XCTAssertEqual(requests.count, 2)
            try assertReviewOnly(requests, drawing: drawing, chart: fixture.chart)
        }
    }

    func testWeakAndOversizedLocatedSingleTargetsBypassReaderInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try makeFixture(style)
            let center = try XCTUnwrap(fixture.centers.first)
            let weak = stroke([CGPoint(x: center.x - 3, y: center.y - 3),
                               CGPoint(x: center.x + 3, y: center.y + 3)], creation: 1)
            for strokes in [[weak], (0..<17).map { diagonal(center, creation: Double($0)) }] {
                let drawing = PKDrawing(strokes: strokes)
                let preparation = ChordInkRecognitionPreparation.prepare(request(drawing, fixture: fixture, style: style))
                guard case .ready(let requests, let batch) = preparation.outcome else {
                    XCTFail("Located excluded single target must remain reviewable"); continue
                }
                XCTAssertFalse(batch)
                XCTAssertEqual(requests.count, 1)
                XCTAssertEqual(preparation.boundedBatchTargetCount, 0)
                try assertReviewOnly(requests, drawing: drawing, chart: fixture.chart)
            }
        }
    }

    func testUnlocatedWeakInkIsStillNoTargetRatherThanInventedPlacement() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try makeFixture(style)
            let center = try XCTUnwrap(fixture.centers.first)
            let drawing = PKDrawing(strokes: [stroke([CGPoint(x: center.x - 3, y: center.y - 3),
                CGPoint(x: center.x + 3, y: center.y + 3)], creation: 1)])
            var input = request(drawing, fixture: fixture, style: style)
            input.pageLayout = nil
            let source = input.drawingData
            let preparation = ChordInkRecognitionPreparation.prepare(input)
            guard case .noTarget = preparation.outcome else {
                XCTFail("Missing placement cannot become an invented manual chord slot"); continue
            }
            XCTAssertEqual(input.drawingData, source)
            XCTAssertEqual(preparation.ownershipSnapshot?.targetGroups.count, 0)
            XCTAssertEqual(preparation.ownershipSnapshot?.unassignedVisibleFragmentIndices, [0])
        }
    }

    private func assertReviewOnly(_ requests: [ChordInkRecognitionSessionRequest], drawing: PKDrawing,
                                 chart: Chart, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(requests.allSatisfy(\.requiresManualReviewOnly), file: file, line: line)
        let reader = UnexpectedReader()
        let session = ChordInkRecognitionSession(queue: .init(label: "manual-only-preparation"), recognizer: reader)
        let done = expectation(description: "Review-only payloads")
        var payloads: [ChordInkRecognitionProposalPayload] = []
        session.startBatch(requests: requests) { payloads = $0; done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(reader.callCount, 0, file: file, line: line)
        XCTAssertEqual(payloads.count, requests.count, file: file, line: line)
        let drafts = try payloads.map { payload -> ChordInkDraft in
            XCTAssertNil(payload.result.match, file: file, line: line)
            XCTAssertEqual(payload.result.confidence, 0, file: file, line: line)
            XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: payload.result).action, .confirm, file: file, line: line)
            XCTAssertNil(payload.result.personalSuggestion, file: file, line: line)
            XCTAssertNil(payload.evaluationPrediction, file: file, line: line)
            XCTAssertFalse(payload.timing.cacheHit, file: file, line: line)
            XCTAssertTrue(payload.requiresManualReviewOnly, file: file, line: line)
            let index = try XCTUnwrap(chart.measure(id: payload.target.measureID)?.index, file: file, line: line)
            return ChordInkDraft(input: ChordInkDraftInput(measureID: payload.target.measureID, measureIndex: index,
                targetFraction: payload.target.fraction, visualOrder: payload.visualOrder,
                laneLocation: payload.laneLocation, layoutPageSize: payload.layoutPageSize,
                drawingData: payload.drawingData, candidateTexts: [], bestCandidateText: nil,
                confidence: payload.result.confidence, strokeCount: payload.strokes.count,
                recognitionResult: payload.result, recognitionDecision: ChordInkRecognitionPolicy.decision(for: payload.result),
                requiresManualReviewOnly: payload.requiresManualReviewOnly))
        }
        var chart = chart
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let originalSource = chart.pageHandwrittenChordData
        let state = ChordPreviewState(draftChords: drafts)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state), file: file, line: line)
        let review = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state), file: file, line: line)
        XCTAssertEqual(review.confirmations.count, requests.count, file: file, line: line)
        XCTAssertTrue(review.confirmations.allSatisfy { $0.bestCandidateText == nil }, file: file, line: line)
        let labels = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, "D7") })
        let repaired = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: review,
            candidateTextByDraftID: labels), file: file, line: line)
        XCTAssertTrue(repaired.canRenderAllDraftChords, file: file, line: line)
        XCTAssertTrue(repaired.draftChords.allSatisfy { $0.recognitionResult?.match == nil }, file: file, line: line)
        XCTAssertEqual(chart.pageHandwrittenChordData, originalSource, file: file, line: line)
        XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty), file: file, line: line)
    }

    private struct Fixture {
        let chart: Chart
        let layout: LeadSheetPageLayout
        let frame: CGRect
        let centers: [CGPoint]
    }

    private func makeFixture(_ style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.draft(title: "Manual-only preparation", layoutStyle: style)
        chart.completeInitialSetup(title: "Manual-only preparation", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 8)
        XCTAssertTrue(chart.insertSystemBreak(before: chart.measures[4].id))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1200))
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lanes = LeadSheetActiveInkScope.chordWritingInputFrames(for: layout)
        XCTAssertGreaterThanOrEqual(lanes.count, 2)
        return Fixture(chart: chart, layout: layout, frame: frame,
            centers: lanes.map { CGPoint(x: $0.midX - frame.minX, y: $0.midY - frame.minY) })
    }

    private func request(_ drawing: PKDrawing, fixture: Fixture, style: ChartLayoutStyle) -> ChordInkRecognitionPreparationRequest {
        .init(requestID: UUID(), scheduledAt: Date(), requestedDelay: 0, drawingData: drawing.dataRepresentation(),
            chordFrame: fixture.frame, pageLayout: fixture.layout, flow: .draftPreview, options: .live, layoutStyle: style)
    }

    private func diagonal(_ center: CGPoint, creation: Double) -> PKStroke {
        stroke([CGPoint(x: center.x - 12, y: center.y - 15), CGPoint(x: center.x + 12, y: center.y + 15)], creation: creation)
    }

    private func stroke(_ points: [CGPoint], creation: Double) -> PKStroke {
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.05, size: CGSize(width: 2, height: 2),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSince1970: creation)))
    }
}

private final class UnexpectedReader: ChordInkRecognizing {
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        lock.lock(); calls += 1; lock.unlock()
        return ChordInkRecognitionResult(rawCandidates: ["C"], glyphCandidates: [],
            match: ChordRecognitionCompendium.match("C"), confidence: 4.6)
    }
}
#endif

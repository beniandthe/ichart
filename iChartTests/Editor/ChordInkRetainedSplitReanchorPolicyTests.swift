#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkRetainedSplitReanchorPolicyTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_400)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testRetargetsExactRetainedSourceAfterSplitAndPreservesCorrectionsInBothStyles() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let before = try state(for: fixture.drawing, layout: fixture.original, frame: fixture.frame, style: style)
            let after = try XCTUnwrap(reanchor(before, fixture))
            let canonical = try state(for: fixture.drawing, layout: fixture.destination,
                frame: fixture.frame, style: style)
            XCTAssertEqual(after.draftChords.count, 2)
            for (old, fresh) in zip(before.draftChords, after.draftChords) {
                XCTAssertEqual(fresh.id, old.id)
                XCTAssertEqual(fresh.drawingData, old.drawingData)
                XCTAssertEqual(fresh.selectedText, old.selectedText)
                XCTAssertEqual(fresh.candidateTexts, old.candidateTexts)
                XCTAssertEqual(fresh.bestCandidateText, old.bestCandidateText)
                XCTAssertEqual(fresh.recognitionResult, old.recognitionResult)
                XCTAssertEqual(fresh.confidence, old.confidence)
                XCTAssertEqual(fresh.measureID, fixture.rightID)
                XCTAssertEqual(fresh.measureIndex, 2)
                XCTAssertNotEqual(fresh.measureID, old.measureID)
                XCTAssertEqual(fresh.targetLifecycle?.stage, .collecting)
                XCTAssertNotEqual(fresh.targetLifecycle?.generationID, old.targetLifecycle?.generationID)
                XCTAssertEqual(fresh.targetLifecycle?.anchor, fresh.anchor)
                XCTAssertNil(ChordInkAutomaticRenderPolicy.automaticCandidateText(for: fresh),
                    "A stale frozen result must not render before the new owner is reacquired")
                let source = try PKDrawing(data: fresh.drawingData)
                let matches = canonical.draftChords.filter { draft in
                    guard let preparedSource = try? PKDrawing(data: draft.drawingData) else { return false }
                    return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                        expected: source, current: preparedSource)
                }
                XCTAssertEqual(matches.count, 1)
                let target = try XCTUnwrap(matches.first)
                XCTAssertEqual(fresh.targetFraction, target.targetFraction,
                    "The full shipping preparation pass supplies the canonical destination fraction")
                XCTAssertEqual(fresh.laneLocation, target.laneLocation)
            }
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: fixture.drawing, current: fixture.drawing))
        }
    }

    func testRejectsChangedOrDuplicateSourceOwnershipInBothStyles() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let before = try state(for: fixture.drawing, layout: fixture.original, frame: fixture.frame, style: style)
            var changed = fixture
            let changedStroke = PKDrawing(strokes: [fixture.drawing.strokes[0]])
                .transformed(using: CGAffineTransform(translationX: 1, y: 0)).strokes[0]
            changed.drawing = PKDrawing(strokes: [changedStroke] + Array(fixture.drawing.strokes.dropFirst()))
            XCTAssertNil(reanchor(before, changed))
            var duplicate = before
            var extra = try XCTUnwrap(before.draftChords.first)
            extra.id = UUID()
            duplicate.draftChords.append(extra)
            XCTAssertNil(reanchor(duplicate, fixture))
        }
    }

    func testRejectsFullPreparationSplittingAnOldCombinedOwnerInBothStyles() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let single = try draft(for: fixture.drawing, layout: fixture.original, frame: fixture.frame)
            let before = ChordPreviewState(draftChords: [single], layoutPageSize: pageSize)
            XCTAssertNil(reanchor(before, fixture),
                "Old correction text cannot be copied to either half of a newly split source group")
        }
    }

    func testRejectsFullPreparationMergingPreviouslySeparateOwnersInBothStyles() throws {
        for style in styles {
            var fixture = try makeFixture(style)
            let lane = try XCTUnwrap(fixture.original.systems.first?.measures.first?.chordWritingFrame)
            let origin = CGPoint(x: lane.minX + lane.width * 0.65 - fixture.frame.minX,
                y: lane.minY + 8 - fixture.frame.minY)
            let left = stroke([CGPoint(x: origin.x + 20, y: origin.y),
                CGPoint(x: origin.x + 5, y: origin.y),
                CGPoint(x: origin.x, y: origin.y + 5),
                CGPoint(x: origin.x, y: origin.y + 20),
                CGPoint(x: origin.x + 5, y: origin.y + 25),
                CGPoint(x: origin.x + 20, y: origin.y + 25)], seed: 21)
            let arm = stroke([CGPoint(x: origin.x + 8, y: origin.y + 12),
                CGPoint(x: origin.x + 22, y: origin.y + 12)], seed: 22)
            fixture.drawing = PKDrawing(strokes: [left, arm])
            let fresh = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: .now,
                requestedDelay: 0, drawingData: fixture.drawing.dataRepresentation(), chordFrame: fixture.frame,
                pageLayout: fixture.destination, flow: .draftPreview, options: .live, layoutStyle: style))
            XCTAssertTrue(fresh.barlines.isEmpty)
            XCTAssertTrue(fresh.endings.isEmpty)
            guard case .ready(let requests, _) = fresh.outcome else {
                XCTFail("The merge fixture must be recognized as chord source")
                throw NSError(domain: "RetainedSplitFixture", code: 2)
            }
            XCTAssertEqual(requests.count, 1,
                "This control must exercise an actual fresh merge, rather than structural refusal")
            let drafts = try [left, arm].map { try draft(for: PKDrawing(strokes: [$0]),
                layout: fixture.original, frame: fixture.frame) }
            let before = ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
            XCTAssertNil(reanchor(before, fixture),
                "Two old correction rows cannot claim one newly merged source group")
        }
    }

    func testRejectsInputRegionOrPhysicalStaffMovementInBothStyles() throws {
        for style in styles {
            var fixture = try makeFixture(style)
            let before = try state(for: fixture.drawing, layout: fixture.original, frame: fixture.frame, style: style)
            fixture.destination.pageBounds.size.width += 1
            XCTAssertNil(reanchor(before, fixture))
            fixture = try makeFixture(style)
            let sameSource = try state(for: fixture.drawing, layout: fixture.original, frame: fixture.frame, style: style)
            // The input region remains identical; the staff-row invariant is
            // independently required before source can take a new anchor.
            fixture.destination.systems[0].staffLineYPositions.append(999)
            XCTAssertEqual(LeadSheetActiveInkScope.chordWritingRegion(for: fixture.original),
                LeadSheetActiveInkScope.chordWritingRegion(for: fixture.destination))
            XCTAssertNil(reanchor(sameSource, fixture))
        }
    }

    private struct Fixture {
        var original: LeadSheetPageLayout
        var destination: LeadSheetPageLayout
        var frame: CGRect
        var drawing: PKDrawing
        var rightID: UUID
        var style: ChartLayoutStyle
    }

    private func makeFixture(_ style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.draft(title: "Retained split source", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: .init(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        let id = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertNotNil(chart.setMeasureManualLayoutWidth(600, for: id))
        let original = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: original)
        let measure = try XCTUnwrap(original.systems.flatMap(\.measures).first { $0.chordInkTargetMeasureID == id })
        let y = measure.chordWritingFrame.minY + 8 - frame.minY
        let x = measure.chordWritingFrame.minX - frame.minX
        let fractions: [CGFloat] = [0.61, 0.84]
        let drawing = PKDrawing(strokes: fractions.enumerated().map { index, fraction in
            let origin = CGPoint(x: x + measure.chordWritingFrame.width * fraction, y: y)
            return stroke([CGPoint(x: origin.x + 20, y: origin.y), origin,
                CGPoint(x: origin.x, y: origin.y + 27),
                CGPoint(x: origin.x + 20, y: origin.y + 27),
                CGPoint(x: origin.x + 20, y: origin.y + 14),
                CGPoint(x: origin.x + 10, y: origin.y + 14)], seed: UInt32(10 + index))
        })
        let rightID = try XCTUnwrap(style == .simpleChordSheet
            ? chart.splitSimpleChordMeasure(id, atFraction: 0.4)
            : chart.splitOpenRhythmSectionMeasure(id, atFraction: 0.4))
        let destination = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        XCTAssertEqual(LeadSheetActiveInkScope.chordWritingRegion(for: original),
            LeadSheetActiveInkScope.chordWritingRegion(for: destination))
        return Fixture(original: original, destination: destination, frame: frame, drawing: drawing,
            rightID: rightID, style: style)
    }

    private func state(for drawing: PKDrawing, layout: LeadSheetPageLayout, frame: CGRect,
        style: ChartLayoutStyle) throws -> ChordPreviewState {
        let prepared = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: .now,
            requestedDelay: 0, drawingData: drawing.dataRepresentation(), chordFrame: frame,
            pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: style))
        guard case .ready(let requests, _) = prepared.outcome else {
            XCTFail("The fixture must prepare real retained chord requests")
            throw NSError(domain: "RetainedSplitFixture", code: 1)
        }
        XCTAssertEqual(requests.count, 2)
        return ChordPreviewState(draftChords: requests.map { request in
            ChordInkDraft(input: .init(measureID: request.target.measureID, measureIndex: 1,
                targetFraction: request.target.fraction, visualOrder: request.visualOrder,
                laneLocation: request.laneLocation, layoutPageSize: pageSize,
                drawingData: request.drawingData, candidateTexts: ["G7"], bestCandidateText: "G7",
                confidence: 4.5, strokeCount: request.strokes.count,
                targetLifecycle: request.collectingTargetLifecycle.advanced(to: .stable)), selectedText: "Gmaj7")
        }, layoutPageSize: pageSize)
    }

    private func draft(for drawing: PKDrawing, layout: LeadSheetPageLayout, frame: CGRect) throws -> ChordInkDraft {
        let target = try XCTUnwrap(LeadSheetChordInkRecognitionTargeting.target(
            for: drawing, chordFrame: frame, pageLayout: layout))
        let lane = LeadSheetChordInkRecognitionTargeting.laneLocation(for: drawing, chordFrame: frame, pageLayout: layout)
        return ChordInkDraft(input: .init(measureID: target.measureID, measureIndex: 1,
            targetFraction: target.fraction, laneLocation: lane, layoutPageSize: pageSize,
            drawingData: drawing.dataRepresentation(), candidateTexts: ["G7"], bestCandidateText: "G7",
            confidence: 4.5, strokeCount: drawing.strokes.count), selectedText: "Gmaj7")
    }

    private func reanchor(_ state: ChordPreviewState, _ fixture: Fixture) -> ChordPreviewState? {
        ChordInkRetainedSplitReanchorPolicy.reanchored(state: state, drawing: fixture.drawing,
            originalLayout: fixture.original, destinationLayout: fixture.destination,
            sourceFrame: fixture.frame, layoutStyle: fixture.style)
    }

    private func stroke(_ locations: [CGPoint], seed: UInt32) -> PKStroke {
        let points = locations.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif

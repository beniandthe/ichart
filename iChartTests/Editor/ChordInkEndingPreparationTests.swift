#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkEndingPreparationTests: XCTestCase {
    func testEndingOnlyPreparationPublishesBracketWithoutCreatingChordRequests() throws {
        let fixture = try fixture()
        let drawing = PKDrawing(strokes: [bracket(in: fixture)])
        let prepared = prepare(drawing, fixture: fixture)
        XCTAssertEqual(prepared.endings.count, 1)
        XCTAssertTrue(prepared.barlines.isEmpty)
        XCTAssertEqual(prepared.recognitionStrokeCount, 0)
        guard case .noRecognitionData = prepared.outcome else {
            return XCTFail("An ending-only draft must still publish without chord recognition: \(prepared.outcome)")
        }
        let ending = try XCTUnwrap(prepared.endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, [0])
        XCTAssertFalse(ending.isReviewed)
        XCTAssertEqual(prepared.ownershipSnapshot?.barlineVisibleFragmentIndices, [0])
        XCTAssertEqual(prepared.ownershipSnapshot?.unassignedVisibleFragmentIndices, [])
    }

    func testEndingBracketAndLabelSourcesAreExcludedBeforeChordTargeting() throws {
        let fixture = try fixture()
        let chord = try rootStrokes(in: fixture)
        let sources = [bracket(in: fixture), labelStroke(in: fixture)]
        let prepared = prepare(PKDrawing(strokes: chord + sources), fixture: fixture)
        let ending = try XCTUnwrap(prepared.endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, Set(chord.count..<(chord.count + sources.count)))
        XCTAssertTrue(prepared.barlines.isEmpty, "Bracket hooks and label numerals must not become barlines.")
        XCTAssertEqual(prepared.recognitionStrokeCount, chord.count)
        guard case .ready(let requests, _) = prepared.outcome else {
            return XCTFail("Expected the untouched chord sources to reach targeting: \(prepared.outcome)")
        }
        XCTAssertEqual(requests.flatMap(\.strokes), PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: chord)))
        XCTAssertEqual(prepared.ownershipSnapshot?.unassignedVisibleFragmentIndices, [])
    }

    func testTinyLabelPunctuationKeepsItsOriginalOwnershipInPreparation() throws {
        let fixture = try fixture()
        let point = localPoint(in: fixture, xFraction: 0.30, yFraction: 0.25)
        let punctuation = stroke([point], size: 1.2)
        XCTAssertFalse(ChordInkDraftVisibleStrokePolicy.isVisible(punctuation))
        let prepared = prepare(PKDrawing(strokes: [bracket(in: fixture), punctuation]), fixture: fixture)
        let ending = try XCTUnwrap(prepared.endings.first)
        XCTAssertEqual(ending.sourceStrokeIndices, [0, 1])
        XCTAssertEqual(prepared.visibleStrokeCount, 2)
        XCTAssertEqual(prepared.recognitionStrokeCount, 0)
    }

    func testTapToConfirmFlowDoesNotAcquireEndingDraftSemantics() throws {
        let fixture = try fixture()
        let prepared = prepare(PKDrawing(strokes: [bracket(in: fixture)]), fixture: fixture, flow: .tapToConfirm)
        XCTAssertTrue(prepared.endings.isEmpty)
        XCTAssertEqual(prepared.recognitionStrokeCount, 1)
    }

    func testEndingSourceOwnershipRemapsAllOriginalIndices() throws {
        let fixture = try fixture()
        var ending = try XCTUnwrap(prepare(PKDrawing(strokes: [bracket(in: fixture)]), fixture: fixture).endings.first)
        ending.sourceStrokeIndices = [0, 1]
        let context = ChordInkDraftVisibleDrawingContext(
            drawing: PKDrawing(strokes: [bracket(in: fixture), labelStroke(in: fixture)]),
            originalStrokeIndices: [2, 5], invisibleStrokeIndices: [0, 1, 3, 4])
        let recognition = ChordDraftEndingRecognition(endings: [ending], strokeIndices: [0, 1])
        let remapped = context.remappedEndingRecognition(context.endingRecognitionWithUnambiguousSourceStrokes(recognition))
        XCTAssertEqual(remapped.endings.first?.sourceStrokeIndices, [2, 5])
        XCTAssertEqual(remapped.strokeIndices, [2, 5])
        XCTAssertTrue(remapped.strokeIndices.isDisjoint(with: context.invisibleStrokeIndices))
    }

    func testEndingCannotOwnOneFragmentOfAnOriginalStrokeWithOtherVisibleFragments() throws {
        let fixture = try fixture()
        var ending = try XCTUnwrap(prepare(PKDrawing(strokes: [bracket(in: fixture)]), fixture: fixture).endings.first)
        ending.sourceStrokeIndices = [0]
        let context = ChordInkDraftVisibleDrawingContext(
            drawing: PKDrawing(strokes: [bracket(in: fixture), labelStroke(in: fixture)]),
            originalStrokeIndices: [0, 0], invisibleStrokeIndices: [])
        let safe = context.endingRecognitionWithUnambiguousSourceStrokes(
            ChordDraftEndingRecognition(endings: [ending], strokeIndices: [0]))
        XCTAssertTrue(safe.endings.isEmpty)
        XCTAssertTrue(safe.strokeIndices.isEmpty)
    }

    func testEndingHighlightUsesOneFullCanvasOriginAndIncludesSourceLabel() throws {
        let fixture = try fixture()
        let prepared = prepare(PKDrawing(strokes: [bracket(in: fixture), labelStroke(in: fixture)]), fixture: fixture)
        let ending = try XCTUnwrap(prepared.endings.first)
        let frame = try XCTUnwrap(ChordDraftEndingPresentationPolicy.sourceHighlightFrame(
            for: ending, sourceOrigin: fixture.chordFrame.origin))
        let bounds = InkBounds.enclosing(ending.sourceStrokeGeometry.map(\.bounds))
        XCTAssertEqual(frame.minX, CGFloat(bounds.minX) + fixture.chordFrame.minX - 3, accuracy: 0.001)
        XCTAssertEqual(frame.minY, CGFloat(bounds.minY) + fixture.chordFrame.minY - 3, accuracy: 0.001)
        XCTAssertEqual(frame.maxX, CGFloat(bounds.maxX) + fixture.chordFrame.minX + 3, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, CGFloat(bounds.maxY) + fixture.chordFrame.minY + 3, accuracy: 0.001)
    }

    func testEndingReviewHitTargetKeepsLaterLabelInputWritable() throws {
        let fixture = try fixture()
        // Detection can finish before the writer adds the label. Its preview
        // must not intercept a new Pencil stroke begun inside this bracket.
        let ending = try XCTUnwrap(prepare(PKDrawing(strokes: [bracket(in: fixture)]), fixture: fixture).endings.first)
        let hitFrame = try XCTUnwrap(ChordDraftEndingPresentationPolicy.reviewHitFrame(
            for: ending, sourceOrigin: fixture.chordFrame.origin))
        let outline = try XCTUnwrap(ChordDraftEndingPresentationPolicy.sourceHighlightFrame(
            for: ending, sourceOrigin: fixture.chordFrame.origin))
        let sourceBounds = InkBounds.enclosing(ending.sourceStrokeGeometry.map(\.bounds))
        let roofY = CGFloat(sourceBounds.minY) + fixture.chordFrame.minY
        let nearestLabelY = roofY + max(3.5, fixture.lane.height * 0.055)
        XCTAssertTrue(hitFrame.contains(CGPoint(x: outline.midX, y: roofY)), "The roof remains a review target")
        XCTAssertTrue(hitFrame.contains(CGPoint(x: outline.midX, y: roofY - 8)))
        XCTAssertFalse(hitFrame.contains(CGPoint(x: outline.midX, y: nearestLabelY)),
            "Even the nearest supported label point must reach the writing canvas")
        for point in labelStroke(in: fixture).path {
            let pagePoint = CGPoint(x: point.location.x + fixture.chordFrame.minX,
                y: point.location.y + fixture.chordFrame.minY)
            XCTAssertTrue(outline.contains(pagePoint), "This label lies inside the full source outline")
            XCTAssertFalse(hitFrame.contains(pagePoint), "An existing preview must not swallow later label input")
        }
        var detached = ending
        let leftX = sourceBounds.minX
        detached.sourceStrokeGeometry.append(InkStroke(points: [
            InkPoint(x: leftX, y: sourceBounds.minY - 4, timeOffset: nil),
            InkPoint(x: leftX, y: sourceBounds.minY + 12, timeOffset: nil)]))
        let detachedHit = try XCTUnwrap(ChordDraftEndingPresentationPolicy.reviewHitFrame(
            for: detached, sourceOrigin: fixture.chordFrame.origin))
        XCTAssertTrue(detachedHit.contains(CGPoint(x: outline.midX, y: roofY)),
            "A hook starting above the roof must not move the roof review target")
        XCTAssertFalse(detachedHit.contains(CGPoint(x: outline.midX, y: nearestLabelY)))
    }

    func testReviewedLabelDoesNotCauseDetectorRepublishButChangedGeometryDoes() throws {
        let fixture = try fixture()
        let drawing = PKDrawing(strokes: [bracket(in: fixture)])
        let detected = try XCTUnwrap(prepare(drawing, fixture: fixture).endings.first)
        var reviewed = detected
        reviewed.label = "1–3, 5"
        reviewed.isReviewed = true
        reviewed.endStyle = .open
        XCTAssertTrue(ChordDraftEndingPresentationPolicy.detectedContentMatches([reviewed], [detected]))
        var moved = detected
        moved.sourceStrokeGeometry[0].points[0].x += 2
        XCTAssertFalse(ChordDraftEndingPresentationPolicy.detectedContentMatches([reviewed], [moved]))
    }

    func testDetectedSlopedAndWavyRoofReviewTargetsFollowTheirEndsAndLeaveLabelsWritable() throws {
        let fixture = try fixture()
        let left = localPoint(in: fixture, xFraction: 0.20, yFraction: 0.12)
        let right = localPoint(in: fixture, xFraction: 0.65, yFraction: 0.20)
        for wavy in [false, true] {
            let roof = (0...24).map { index -> CGPoint in
                let t = CGFloat(index) / 24
                return CGPoint(x: left.x + (right.x - left.x) * t,
                    y: left.y + (right.y - left.y) * t
                        + (wavy ? sin(t * .pi * 2) * fixture.lane.height * 0.035 : 0))
            }
            let bracket = stroke([CGPoint(x: left.x, y: left.y + fixture.lane.height * 0.22)]
                + roof + [CGPoint(x: right.x, y: right.y + fixture.lane.height * 0.22)])
            let ending = try XCTUnwrap(prepare(PKDrawing(strokes: [bracket]), fixture: fixture).endings.first)
            let fitted = try XCTUnwrap(ending.roofReviewFrame)
            let hit = try XCTUnwrap(ChordDraftEndingPresentationPolicy.reviewHitFrame(
                for: ending, sourceOrigin: fixture.chordFrame.origin))
            XCTAssertEqual(hit, fitted.offsetBy(dx: fixture.chordFrame.minX, dy: fixture.chordFrame.minY))
            for point in roof {
                let pagePoint = CGPoint(x: point.x + fixture.chordFrame.minX, y: point.y + fixture.chordFrame.minY)
                XCTAssertTrue(hit.contains(pagePoint), "Both endpoints and the middle of a \(wavy ? "wavy" : "sloped") roof remain tappable")
            }
            // Detector maxY is half a point above the first supported label
            // position. Start 0.1 point inside that band to avoid floating-point
            // edge rounding. Exercise actual later input rather than a hand-made
            // ending payload so the hit/detection contracts stay aligned.
            let label = stroke([CGPoint(x: fitted.midX, y: fitted.maxY + 0.6),
                CGPoint(x: fitted.midX + 2, y: fitted.maxY + 0.6 + fixture.lane.height * 0.10)])
            let afterLabel = prepare(PKDrawing(strokes: [bracket, label]), fixture: fixture)
            XCTAssertEqual(try XCTUnwrap(afterLabel.endings.first).sourceStrokeIndices, [0, 1])
            XCTAssertEqual(afterLabel.recognitionStrokeCount, 0)
            for point in label.path {
                XCTAssertFalse(hit.contains(CGPoint(x: point.location.x + fixture.chordFrame.minX,
                    y: point.location.y + fixture.chordFrame.minY)), "Supported label input reaches PencilKit")
            }
        }
    }

    func testDetectedRoofJoinedToExistingFullHeightLegDoesNotCaptureChordOrLabelInterior() throws {
        let fixture = try fixture()
        let measure = try XCTUnwrap(fixture.layout.systems.first?.measures.first)
        let left = CGPoint(x: measure.frame.minX + 5 - fixture.chordFrame.minX,
            y: fixture.lane.minY + fixture.lane.height * 0.12 - fixture.chordFrame.minY)
        let right = localPoint(in: fixture, xFraction: 0.65, yFraction: 0.16)
        let lowLeg = CGPoint(x: left.x, y: fixture.lane.minY + fixture.lane.height * 0.93 - fixture.chordFrame.minY)
        let bracket = stroke([lowLeg, left, right])
        let ending = try XCTUnwrap(prepare(PKDrawing(strokes: [bracket]), fixture: fixture).endings.first)
        let fitted = try XCTUnwrap(ending.roofReviewFrame)
        let hit = try XCTUnwrap(ChordDraftEndingPresentationPolicy.reviewHitFrame(
            for: ending, sourceOrigin: fixture.chordFrame.origin))
        let outline = try XCTUnwrap(ChordDraftEndingPresentationPolicy.sourceHighlightFrame(
            for: ending, sourceOrigin: fixture.chordFrame.origin))
        XCTAssertLessThan(hit.height, fixture.lane.height * 0.5)
        for point in [left, CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2), right] {
            XCTAssertTrue(hit.contains(CGPoint(x: point.x + fixture.chordFrame.minX, y: point.y + fixture.chordFrame.minY)))
        }
        let chordPoint = CGPoint(x: outline.midX, y: fixture.lane.minY + fixture.lane.height * 0.73)
        XCTAssertTrue(outline.contains(chordPoint), "The original tall leg extends the full source outline")
        XCTAssertFalse(hit.contains(chordPoint), "The review target must ignore the connected full-height leg")
        let label = stroke([CGPoint(x: fitted.midX, y: fitted.maxY + 0.6),
            CGPoint(x: fitted.midX + 2, y: fitted.maxY + 0.6 + fixture.lane.height * 0.10)])
        let afterLabel = prepare(PKDrawing(strokes: [bracket, label]), fixture: fixture)
        XCTAssertEqual(try XCTUnwrap(afterLabel.endings.first).sourceStrokeIndices, [0, 1])
        for point in label.path {
            XCTAssertFalse(hit.contains(CGPoint(x: point.location.x + fixture.chordFrame.minX,
                y: point.location.y + fixture.chordFrame.minY)))
        }
    }

    func testRemovingOtherStructuralInkRemapsEndingIndicesWithoutDiscardingReviewedLabel() throws {
        let fixture = try fixture()
        var ending = try XCTUnwrap(prepare(PKDrawing(strokes: [bracket(in: fixture)]), fixture: fixture).endings.first)
        ending.sourceStrokeIndices = [2, 4]
        ending.label = "On cue"
        ending.isReviewed = true
        let remapped = try XCTUnwrap(ChordDraftEndingPresentationPolicy.remappingSourceIndices([ending], afterRemoving: [0, 3]).first)
        XCTAssertEqual(remapped.sourceStrokeIndices, [1, 2])
        XCTAssertEqual(remapped.sourceStrokeGeometry, ending.sourceStrokeGeometry)
        XCTAssertEqual(remapped.label, "On cue")
        XCTAssertTrue(remapped.isReviewed)
        XCTAssertTrue(ChordDraftEndingPresentationPolicy.remappingSourceIndices([ending], afterRemoving: [2]).isEmpty)
    }

    private struct Fixture {
        var chart: Chart
        var layout: LeadSheetPageLayout
        var chordFrame: CGRect
        var lane: CGRect
    }

    private func fixture() throws -> Fixture {
        var chart = Chart.draft(title: "Ending preparation", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor, meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine, startingMeasureCount: 1)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 900, height: 1_400), includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        return Fixture(chart: chart, layout: layout, chordFrame: region.frame, lane: try XCTUnwrap(region.inputFrames.first))
    }

    private func localPoint(in fixture: Fixture, xFraction: CGFloat, yFraction: CGFloat) -> CGPoint {
        CGPoint(x: fixture.lane.minX + fixture.lane.width * xFraction - fixture.chordFrame.minX,
            y: fixture.lane.minY + fixture.lane.height * yFraction - fixture.chordFrame.minY)
    }

    private func bracket(in fixture: Fixture) -> PKStroke {
        stroke([localPoint(in: fixture, xFraction: 0.20, yFraction: 0.30),
            localPoint(in: fixture, xFraction: 0.20, yFraction: 0.08),
            localPoint(in: fixture, xFraction: 0.65, yFraction: 0.08),
            localPoint(in: fixture, xFraction: 0.65, yFraction: 0.30)])
    }

    private func labelStroke(in fixture: Fixture) -> PKStroke {
        stroke([localPoint(in: fixture, xFraction: 0.27, yFraction: 0.17),
            localPoint(in: fixture, xFraction: 0.28, yFraction: 0.16),
            localPoint(in: fixture, xFraction: 0.28, yFraction: 0.29)])
    }

    private func rootStrokes(in fixture: Fixture) throws -> [PKStroke] {
        let template = try XCTUnwrap(ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == "C" })
        return template.strokes.map { ink in
            stroke(ink.points.map { point in
                CGPoint(x: fixture.lane.minX + 40 + CGFloat(point.x) * 0.72 - fixture.chordFrame.minX,
                    y: fixture.lane.minY + fixture.lane.height * 0.73 + CGFloat(point.y - 36) * 0.6 - fixture.chordFrame.minY)
            })
        }
    }

    private func prepare(_ drawing: PKDrawing, fixture: Fixture,
        flow: ChordInkRecognitionFlow = .draftPreview) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(ChordInkRecognitionPreparationRequest(
            requestID: UUID(), scheduledAt: Date(), requestedDelay: 0, drawingData: drawing.dataRepresentation(),
            chordFrame: fixture.chordFrame, pageLayout: fixture.layout, flow: flow, options: .live,
            layoutStyle: fixture.chart.layoutStyle))
    }

    private func stroke(_ points: [CGPoint], size: CGFloat = 3) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.05,
                size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }
}
#endif

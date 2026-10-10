#if canImport(UIKit)
import XCTest
import PencilKit
@testable import iChart

/// Row ownership is a layout invariant, not a writer-specific recognition rule.
/// Templates here are synthetic geometry, not an accuracy benchmark.
final class ChordInkRowIsolationTests: XCTestCase {
    /// Local captured trajectories reconstructed as PencilKit input in each
    /// layout. This verifies preparation/ownership, not OCR accuracy or timing.
    func testProvidedEditTraceReconstructsPreparationInBothStyles() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_EDIT_NEIGHBOR_TRACE"] else {
            throw XCTSkip("Supply an authorized local edit trace")
        }
        let events = try ChordDraftPreviewDeviceDiagnosticRecorder(url: URL(fileURLWithPath: path)).loadEvents()
        let passes = events.filter { $0.layoutStyle == ChartLayoutStyle.simpleChordSheet.rawValue && $0.stage == "finish_batch" }
        let pair = try XCTUnwrap(zip(passes, passes.dropFirst()).first { before, after in
            before.payloads.count == 3 && after.payloads.count == 2 &&
            after.payloads[0].strokeCount > before.payloads[0].strokeCount
        })
        let previous = try pair.0.payloads.map { try XCTUnwrap($0.inkStrokes) }
        let current = try pair.1.payloads.map { try XCTUnwrap($0.inkStrokes) }
        let bounds = InkBounds.enclosing(previous.flatMap { $0 }.flatMap(\.points))
        var collapsedSingle = 0, collapsedBatch = 0
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let (layout, frame, lanes) = try fixture(style)
            let lane = lanes[0]
            let scale = min(1, (Double(lane.height) - 8) / bounds.height)
            func drawing(_ ink: [InkStroke]) -> PKDrawing {
                PKDrawing(strokes: ink.sorted { ($0.creationTimeOffset ?? 0) < ($1.creationTimeOffset ?? 0) }.map { stroke in
                    PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: stroke.points.map { point in
                        PKStrokePoint(location: CGPoint(
                            x: Double(lane.minX - frame.minX) + 40 + (point.x - bounds.minX) * scale,
                            y: Double(lane.midY - frame.minY) + (point.y - bounds.minY - bounds.height / 2) * scale),
                            timeOffset: point.timeOffset ?? 0, size: CGSize(width: 2, height: 2),
                            opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    }, creationDate: Date(timeIntervalSince1970: stroke.creationTimeOffset ?? 0)))
                })
            }
            func prepare(_ drawing: PKDrawing, _ ownership: ChordInkEditedTargetOwnership = .init()) throws
                -> (ChordInkRecognitionPreparationResult, [ChordInkRecognitionSessionRequest]) {
                let prepared = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: .now,
                    requestedDelay: 0, drawingData: drawing.dataRepresentation(), chordFrame: frame,
                    pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: style, editOwnership: ownership))
                guard case .ready(let requests, _) = prepared.outcome else {
                    XCTFail("Expected preparation: \(prepared.outcome)"); throw NSError(domain: "Edit replay", code: 1)
                }
                return (prepared, requests)
            }
            for includeThird in [false, true] {
                let oldDrawing = drawing(Array(previous.prefix(includeThird ? 3 : 2)).flatMap { $0 })
                let newDrawing = drawing(Array(current.prefix(includeThird ? 2 : 1)).flatMap { $0 })
                let (seed, initial) = try prepare(oldDrawing)
                XCTAssertEqual(initial.count, includeThird ? 3 : 2, style.rawValue)
                let (_, baseline) = try prepare(newDrawing)
                if baseline.count < initial.count {
                    if baseline.count == 1 { collapsedSingle += 1 } else { collapsedBatch += 1 }
                }
                let (resolved, requests) = try prepare(newDrawing, XCTUnwrap(seed.nextEditOwnership))
                XCTAssertEqual(requests.count, initial.count, style.rawValue)
                XCTAssertEqual(requests.map(\.requiresEditReview), includeThird ? [false, true, false] : [false, true])
                XCTAssertEqual(requests.first?.strokes.map(\.points), initial.first?.strokes.map(\.points))
                if includeThird { XCTAssertEqual(requests.last?.strokes.map(\.points), initial.last?.strokes.map(\.points)) }
                let ownership = try XCTUnwrap(resolved.ownershipSnapshot)
                XCTAssertTrue(ownership.unassignedVisibleFragmentIndices.isEmpty)
                XCTAssertEqual(ownership.targetGroups.flatMap(\.visibleFragmentIndices).sorted(), Array(newDrawing.strokes.indices))
                XCTAssertEqual(requests.flatMap(\.strokes).count, newDrawing.strokes.count)
            }
        }
        // Removing the third chord can make the base grouper choose a different
        // route that already preserves both owners. Do not claim a one-target
        // collapse from this recording when none was reproduced.
        XCTAssertGreaterThan(collapsedBatch, 0, "Exercise the recorded multi-target collapse")
        print("EDIT_RECONSTRUCTION: \(collapsedSingle) single, \(collapsedBatch) batch collapses; both layouts checked")
    }

    func testRealPreparationPreservesEditedChordAndNeighborInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let (layout, frame, lanes) = try fixture(style)
            let root = try glyph("C", lane: lanes[0], frame: frame, x: 70, time: 0)
            // Library suffix coordinates already include a horizontal offset
            // (7 starts at x=87, C at x=12). Position it beside the root, not a
            // second offset-sized gap away. This is a synthetic flow fixture.
            let suffix = try glyph("7", lane: lanes[0], frame: frame, x: 45, time: 0.4)
            let neighbor = try glyph("G", lane: lanes[1], frame: frame, x: 70, time: 2)
            func prepare(_ ink: [PKStroke], ownership: ChordInkEditedTargetOwnership = .init()) throws
                -> (ChordInkRecognitionPreparationResult, [ChordInkRecognitionSessionRequest]) {
                let result = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: Date(),
                    requestedDelay: 0, drawingData: PKDrawing(strokes: ink).dataRepresentation(), chordFrame: frame,
                    pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: style, editOwnership: ownership))
                guard case .ready(let requests, _) = result.outcome else {
                    XCTFail("Expected prepared input, got \(result.outcome)"); throw NSError(domain: "Preparation", code: 1)
                }
                return (result, requests)
            }
            let (initial, originalRequests) = try prepare(root + suffix + neighbor)
            XCTAssertEqual(originalRequests.count, 2, style.rawValue)
            XCTAssertEqual(originalRequests.first?.strokes.count, root.count + suffix.count)
            XCTAssertTrue(originalRequests.allSatisfy { !$0.requiresEditReview })
            let (erased, erasedRequests) = try prepare(root + neighbor, ownership: XCTUnwrap(initial.nextEditOwnership))
            XCTAssertEqual(erasedRequests.count, 2)
            XCTAssertEqual(erasedRequests.map(\.requiresEditReview), [true, false])
            let replacement = try glyph("7", lane: lanes[0], frame: frame, x: 43, time: 90)
            let (rejoined, rewritten) = try prepare(root + neighbor + replacement, ownership: XCTUnwrap(erased.nextEditOwnership))
            XCTAssertEqual(rewritten.count, 2, style.rawValue)
            XCTAssertEqual(rewritten.map(\.requiresEditReview), [true, false])
            XCTAssertEqual(rewritten.first?.strokes.count, root.count + replacement.count)
            XCTAssertEqual(rewritten.last?.strokes, originalRequests.last?.strokes)
            XCTAssertEqual(rewritten.reduce(0) { $0 + $1.strokes.count }, root.count + neighbor.count + replacement.count)
            let partition = try XCTUnwrap(rejoined.ownershipSnapshot)
            XCTAssertTrue(partition.unassignedVisibleFragmentIndices.isEmpty)
            XCTAssertEqual(partition.targetGroups.map(\.visibleFragmentIndices), [[0, 2], [1]])
            XCTAssertEqual(rejoined.boundaryHypothesisSet?.hypotheses.first?.route, .editContinuity)
            let (_, undone) = try prepare(root + suffix + neighbor, ownership: XCTUnwrap(erased.nextEditOwnership))
            XCTAssertTrue(undone.allSatisfy { !$0.requiresEditReview })
        }
    }

    func testFirstChordOnNextRowKeepsEarlierRowPartitionInBothChartStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let (layout, frame, lanes) = try fixture(style)
            let firstRow = try glyph("C", lane: lanes[0], frame: frame, x: 70, time: 0)
                + glyph("G", lane: lanes[0], frame: frame, x: 185, time: 1)
            let before = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
                for: PKDrawing(strokes: firstRow), chordFrame: frame, pageLayout: layout)
            XCTAssertEqual(before.diagnostics.selectedRoute, "lane_root_sequence", style.rawValue)
            XCTAssertEqual(before.targets.count, 2)
            for root in ["A", "B", "C", "D", "E", "F", "G"] {
                let next = try glyph(root, lane: lanes[1], frame: frame, x: 70, time: 2)
                let after = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
                    for: PKDrawing(strokes: firstRow + next), chordFrame: frame, pageLayout: layout)
                XCTAssertEqual(after.diagnostics.selectedRoute, "lane_root_sequence", "\(style): \(root)")
                XCTAssertEqual(after.targets.count, 3, "\(style): \(root)")
                XCTAssertEqual(Array(after.targets.prefix(2)).map(\.recognitionStrokeIndices), before.targets.map(\.recognitionStrokeIndices))
                XCTAssertEqual(Array(after.targets.prefix(2)).map(\.strokes), before.targets.map(\.strokes))
                XCTAssertEqual(after.targets.last?.recognitionStrokeIndices, Array(firstRow.count..<(firstRow.count + next.count)))
            }
        }
    }

    func testOneCompleteChordPerRowDoesNotNeedArtificialWithinRowSplits() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let (layout, frame, lanes) = try fixture(style)
            let drawing = PKDrawing(strokes: try glyph("C", lane: lanes[0], frame: frame, x: 70, time: 0)
                + glyph("G", lane: lanes[1], frame: frame, x: 70, time: 1))
            let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(for: drawing, chordFrame: frame, pageLayout: layout)
            XCTAssertEqual(result.diagnostics.selectedRoute, "lane_root_sequence")
            XCTAssertEqual(result.targets.map(\.recognitionStrokeIndices), [[0], [1]])
            XCTAssertEqual(result.targets.compactMap(\.laneLocation).map(\.systemIndex), [0, 1])
        }
    }

    private func fixture(_ style: ChartLayoutStyle) throws -> (LeadSheetPageLayout, CGRect, [CGRect]) {
        var chart = Chart.draft(title: "Synthetic row ownership", layoutStyle: style)
        chart.completeInitialSetup(title: "Synthetic row ownership", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 8)
        XCTAssertTrue(chart.insertSystemBreak(before: chart.measures[4].id))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1200))
        let lanes = LeadSheetActiveInkScope.chordWritingInputFrames(for: layout)
        guard lanes.count >= 2 else { throw NSError(domain: "Row fixture needs two systems", code: 1) }
        return (layout, LeadSheetActiveInkScope.chordWritingFrame(for: layout), lanes)
    }

    private func glyph(_ text: String, lane: CGRect, frame: CGRect, x: Double, time: Double) throws -> [PKStroke] {
        let template = try XCTUnwrap(ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text })
        return template.strokes.enumerated().map { index, stroke in
            let points = stroke.points.enumerated().map { pointIndex, point in
                PKStrokePoint(location: CGPoint(x: lane.minX - frame.minX + x + point.x * 0.65,
                                                y: lane.midY - frame.minY + (point.y - 36) * 0.65),
                    timeOffset: Double(pointIndex) * 0.02, size: CGSize(width: 2, height: 2),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: .black),
                path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: time + Double(index) * 0.15)))
        }
    }
}
#endif

#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Completion must follow the finished target, not a page-wide pause caused
/// by unrelated later writing. Uses real source preparation/ownership and the
/// normal guarded automatic transaction; recognition text is a controlled read.
@MainActor
final class ChordInkAutomaticCadencePolicyTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 500)

    func testCompletedChordRendersBeforeSharedIdleWhileUnrelatedBarlineStaysInk() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style)
            let geometry = try geometry(chart)
            let first = try XCTUnwrap(geometry.layout.systems.first?.measures.first)
            let last = try XCTUnwrap(geometry.layout.systems.first?.measures.last)
            let chord = chordStroke(at: first.chordWritingFrame.midX, row: 0, geometry: geometry, seed: 1)
            let bar = barline(at: last.staffFrame.midX, row: 0, geometry: geometry, seed: 2)
            let source = normalized([chord, bar])
            let state = try preparedState(source, in: &chart, geometry: geometry)
            XCTAssertEqual(state.draftBarlines.count, 1)
            XCTAssertEqual(state.draftChords.count, 1)
            let completed = try XCTUnwrap(state.draftChords.first)
            let boundary = try XCTUnwrap(state.draftBarlines.first)
            XCTAssertNotEqual(completed.measureID, boundary.measureID)
            XCTAssertTrue(ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: [0],
                source: source, pageSize: pageSize, requiresLaterInk: true))

            let result = try XCTUnwrap(attempt(chart, state: state, source: source, geometry: geometry).outcome,
                "A pending barline in another measure must not impose its shared idle on a completed chord")
            XCTAssertEqual(result.result.renderedChordCount, 1)
            XCTAssertEqual(result.result.renderedBarlineCount, 0)
            XCTAssertEqual(result.chart.measures.map(\.id), chart.measures.map(\.id))
            XCTAssertEqual(result.remainingState.draftBarlines.map(\.id), state.draftBarlines.map(\.id))
            try assertRetained(normalized([bar]), in: result)
        }
    }

    func testCompletedChordRendersBeforeSharedIdleWhileUnrelatedEndingStaysInk() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style)
            let geometry = try geometry(chart)
            let first = try XCTUnwrap(geometry.layout.systems.first?.measures.first)
            let last = try XCTUnwrap(geometry.layout.systems.first?.measures.last)
            let chord = chordStroke(at: first.chordWritingFrame.midX, row: 0, geometry: geometry, seed: 10)
            let bracket = ending(over: last, row: 0, geometry: geometry, seed: 11)
            let source = normalized([chord] + bracket)
            let state = try preparedState(source, in: &chart, geometry: geometry)
            XCTAssertEqual(state.draftEndings.count, 1)
            XCTAssertEqual(state.draftChords.count, 1)
            let completed = try XCTUnwrap(state.draftChords.first)
            let pendingEnding = try XCTUnwrap(state.draftEndings.first)
            XCTAssertNotEqual(completed.measureID, pendingEnding.start.measureID)

            let result = try XCTUnwrap(attempt(chart, state: state, source: source, geometry: geometry).outcome,
                "An unrelated bracket awaiting its own completion must not hold the finished chord")
            XCTAssertEqual(result.result.renderedChordCount, 1)
            XCTAssertEqual(result.result.renderedEndingCount, 0)
            XCTAssertTrue(result.chart.roadmapObjects.isEmpty)
            XCTAssertEqual(result.remainingState.draftEndings.map(\.id), state.draftEndings.map(\.id))
            XCTAssertFalse(try XCTUnwrap(result.remainingState.draftEndings.first).isReviewed)
            try assertRetained(normalized(bracket), in: result)
        }
    }

    func testStructuralDependencyInTheSameMeasureKeepsChordAndSourcePending() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style)
            let geometry = try geometry(chart)
            let measure = try XCTUnwrap(geometry.layout.systems.first?.measures.first)
            let chord = chordStroke(at: measure.chordWritingFrame.minX + 35, row: 0,
                geometry: geometry, seed: 20)
            let bar = barline(at: measure.chordWritingFrame.maxX - 18, row: 0,
                geometry: geometry, seed: 21)
            let source = normalized([chord, bar])
            let state = try preparedState(source, in: &chart, geometry: geometry)
            XCTAssertEqual(state.draftBarlines.count, 1)
            XCTAssertEqual(state.draftChords.count, 1)
            let completed = try XCTUnwrap(state.draftChords.first)
            let boundary = try XCTUnwrap(state.draftBarlines.first)
            XCTAssertEqual(completed.measureID, boundary.measureID)
            XCTAssertTrue(ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: [0],
                source: source, pageSize: pageSize, requiresLaterInk: true),
                "This control must reach the structural dependency check rather than fail word separation")
            let original = chart
            let bytes = source.dataRepresentation()
            XCTAssertNil(attempt(chart, state: state, source: source, geometry: geometry).outcome)
            XCTAssertEqual(chart, original)
            XCTAssertEqual(source.dataRepresentation(), bytes)
        }
    }

    func testMatureBarlineAndPrecedingChordRenderWhileLaterSameMeasureInkStaysCollecting() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style, measureCount: 1)
            let geometry = try geometry(chart)
            let measure = try XCTUnwrap(geometry.layout.systems.first?.measures.first)
            let frame = try XCTUnwrap(geometry.lanes.first)
            let old = chordStroke(at: frame.minX + frame.width * 0.08, row: 0, geometry: geometry, seed: 60)
            let boundaryX = frame.minX + frame.width * 0.37
            let boundary = barline(at: boundaryX, row: 0, geometry: geometry, seed: 61)
            let later = chordStroke(at: frame.minX + frame.width * 0.56, row: 0, geometry: geometry, seed: 62)
            let source = normalized([old, boundary, later])
            var state = try preparedState(source, in: &chart, geometry: geometry, readableMeasureIDs: [])
            XCTAssertEqual(state.draftBarlines.count, 1)
            XCTAssertEqual(state.draftChords.count, 2)
            let oldSource = normalized([old])
            let oldIndex = try XCTUnwrap(state.draftChords.firstIndex { draft in
                guard let drawing = try? PKDrawing(data: draft.drawingData) else { return false }
                return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: oldSource, current: drawing)
            })
            state.draftChords[oldIndex].bestCandidateText = "C"
            state.draftChords[oldIndex].candidateTexts = ["C"]
            state.draftChords[oldIndex].targetLifecycle = state.draftChords[oldIndex].targetLifecycle?.advanced(to: .stable)
            let bar = try XCTUnwrap(state.draftBarlines.first)
            XCTAssertEqual(bar.measureID, measure.sourceMeasureID)
            XCTAssertTrue(state.draftChords.allSatisfy { $0.measureID == bar.measureID },
                "Both written words must still belong to the original unsplit open measure")
            let original = chart
            XCTAssertNil(attempt(chart, state: state, source: source, geometry: geometry,
                matureStructuralIDs: []).outcome, "A fresh structural mark keeps its own complete grace")
            XCTAssertNil(attempt(chart, state: state, source: source, geometry: geometry,
                matureStructuralIDs: [bar.id], isUsingTool: true).outcome,
                "An aged mark still must never replace the active Pencil stroke")
            let changed = normalized([old, barline(at: boundaryX, row: 0, geometry: geometry, seed: 63), later])
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: changed))
            let maturity = ChordInkStructuralMaturityTracker()
            _ = maturity.observe(chartID: chart.id, state: state, drawing: source, now: inputAt.addingTimeInterval(-3))
            let changedMatureIDs = maturity.observe(chartID: chart.id, state: state, drawing: changed, now: inputAt)
            XCTAssertTrue(changedMatureIDs.isEmpty,
                "The live maturity binding must discard the age of replaced structural ink")
            XCTAssertNil(attempt(chart, state: state, source: changed, geometry: geometry,
                matureStructuralIDs: changedMatureIDs).outcome, "Changed structural source starts its own full grace")
            XCTAssertEqual(chart, original)

            let result = try XCTUnwrap(attempt(chart, state: state, source: source, geometry: geometry,
                matureStructuralIDs: [bar.id]).outcome,
                "The unchanged aged barline and completed earlier chord may commit while G remains collecting")
            XCTAssertEqual(result.result.renderedBarlineCount, 1)
            XCTAssertEqual(result.result.renderedChordCount, 1)
            XCTAssertEqual(result.chart.measures.count, 2)
            XCTAssertEqual(result.chart.measures.first?.id, chart.measures.first?.id)
            let event = try XCTUnwrap(result.chart.measures.flatMap(\.chordEvents).first)
            XCTAssertEqual(event.rawInput, "C")
            let receipt = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: oldSource, current: receipt))
            XCTAssertTrue(result.remainingState.draftBarlines.isEmpty)
            let retained = try XCTUnwrap(result.remainingState.draftChords.first)
            XCTAssertEqual(result.remainingState.draftChords.count, 1)
            XCTAssertEqual(retained.targetLifecycle?.stage, .collecting)
            XCTAssertEqual(retained.measureID, result.chart.measures.last?.id,
                "The exact retained G source must be freshly anchored into the measure created around it")
            try assertRetained(normalized([later]), in: result)
            let idleResult = try XCTUnwrap(attempt(chart, state: state, source: source, geometry: geometry,
                matureStructuralIDs: [bar.id], elapsed: 2.1).outcome,
                "A later collecting reader must not disable the safe combined transaction after global idle")
            XCTAssertEqual(idleResult.result.renderedBarlineCount, 1)
            XCTAssertEqual(idleResult.result.renderedChordCount, 1)
            XCTAssertEqual(idleResult.chart.measures.first?.id, chart.measures.first?.id)
            XCTAssertEqual(idleResult.remainingState.draftChords.first?.measureID, idleResult.chart.measures.last?.id)
            XCTAssertEqual(idleResult.remainingState.draftChords.first?.targetLifecycle?.stage, .collecting)
            try assertRetained(normalized([later]), in: idleResult)
        }
    }

    func testLaterInkInVerifiedDifferentRowCompletesOnlyTheOlderChordBeforeIdle() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style, rows: true)
            let geometry = try geometry(chart)
            let firstSystem = try XCTUnwrap(geometry.layout.systems.first)
            let nextSystem = try XCTUnwrap(geometry.layout.systems.dropFirst().first)
            let first = try XCTUnwrap(firstSystem.measures.first)
            let second = try XCTUnwrap(nextSystem.measures.first)
            let x = max(first.chordWritingFrame.minX, second.chordWritingFrame.minX) + 35
            let earlier = chordStroke(at: x, row: 0, geometry: geometry, seed: 30)
            let later = chordStroke(at: x, row: 1, geometry: geometry, seed: 31)
            let source = normalized([earlier, later])
            var state = try preparedState(source, in: &chart, geometry: geometry,
                readableMeasureIDs: Set(first.sourceMeasureID.map { [$0] } ?? []))
            XCTAssertEqual(state.draftChords.count, 2)
            XCTAssertEqual(Set(state.draftChords.map(\.measureID)).count, 2)
            XCTAssertFalse(ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: [0],
                source: source, pageSize: pageSize, requiresLaterInk: true),
                "Horizontal overlap must exercise the verified-row completion path")
            let result = try XCTUnwrap(attempt(chart, state: state, source: source, geometry: geometry).outcome,
                "A verified later writing row should complete an older isolated target before global idle")
            XCTAssertEqual(result.result.renderedChordCount, 1)
            XCTAssertEqual(result.chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["C"])
            XCTAssertEqual(result.remainingState.draftChords.count, 1)
            XCTAssertEqual(result.remainingState.draftChords.first?.targetLifecycle?.stage, .collecting)
            try assertRetained(normalized([later]), in: result)

            // The same row separation must not make the newest target mature.
            state = try preparedState(source, in: &chart, geometry: geometry,
                readableMeasureIDs: Set(second.sourceMeasureID.map { [$0] } ?? []))
            XCTAssertNil(attempt(chart, state: state, source: source, geometry: geometry).outcome,
                "The latest target can still acquire a suffix; earlier ink on another row does not finish it")
        }
    }

    func testMixedSameRowGapAndLaterVerifiedRowCompleteTheOlderChord() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style, rows: true)
            let geometry = try geometry(chart)
            let firstSystem = try XCTUnwrap(geometry.layout.systems.first)
            let nextSystem = try XCTUnwrap(geometry.layout.systems.dropFirst().first)
            let first = try XCTUnwrap(firstSystem.measures.first)
            let distant = try XCTUnwrap(firstSystem.measures.last)
            let nextRow = try XCTUnwrap(nextSystem.measures.first)
            let x = max(first.chordWritingFrame.minX, nextRow.chordWritingFrame.minX) + 35
            let completed = chordStroke(at: x, row: 0, geometry: geometry, seed: 50)
            let sameRowLater = chordStroke(at: distant.chordWritingFrame.maxX - 35,
                row: 0, geometry: geometry, seed: 51)
            let nextRowLater = chordStroke(at: x, row: 1, geometry: geometry, seed: 52)
            let source = normalized([completed, sameRowLater, nextRowLater])
            let state = try preparedState(source, in: &chart, geometry: geometry,
                readableMeasureIDs: Set(first.sourceMeasureID.map { [$0] } ?? []))
            XCTAssertEqual(state.draftChords.count, 3)
            XCTAssertFalse(ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: [0],
                source: source, pageSize: pageSize, requiresLaterInk: true),
                "Later-row ink overlaps horizontally, while same-row ink prevents the global all-other-rows alternative")

            let result = try XCTUnwrap(attempt(chart, state: state, source: source, geometry: geometry).outcome,
                "Each retained fragment may be separated horizontally OR belong to another verified writing row")
            XCTAssertEqual(result.result.renderedChordCount, 1)
            XCTAssertEqual(result.chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["C"])
            XCTAssertEqual(result.chart.measures.map(\.id), chart.measures.map(\.id))
            XCTAssertEqual(result.remainingState.draftChords.count, 2)
            XCTAssertTrue(result.remainingState.draftChords.allSatisfy { $0.targetLifecycle?.stage == .collecting })
            XCTAssertEqual(Set(result.remainingState.draftChords.map(\.measureID)),
                Set([distant.sourceMeasureID, nextRow.sourceMeasureID].compactMap { $0 }))
            try assertRetained(normalized([sameRowLater, nextRowLater]), in: result)
        }
    }

    func testNearbySameRowSuffixDoesNotBecomeIndependentThroughRowCompletion() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let chart = makeChart(style, rows: true)
            let geometry = try geometry(chart)
            let system = try XCTUnwrap(geometry.layout.systems.first)
            let measure = try XCTUnwrap(system.measures.first)
            let x = measure.chordWritingFrame.minX + 35
            let root = normalized([chordStroke(at: x, row: 0, geometry: geometry, seed: 40)])
            let suffix = normalized([chordStroke(at: x + 10, row: 0, geometry: geometry, seed: 41,
                verticalOffset: 7)])
            let source = normalized(root.strokes + suffix.strokes)
            let draft = try draft(root, in: chart, geometry: geometry, text: "C")
            let state = ChordPreviewState(draftChords: [draft], layoutPageSize: pageSize)
            XCTAssertFalse(ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: [0],
                source: source, pageSize: pageSize, requiresLaterInk: true))
            XCTAssertNil(attempt(chart, state: state, source: source, geometry: geometry).outcome,
                "A lowered/raised nearby suffix is not a verified independent writing row")
        }
    }

    private struct Geometry {
        let layout: LeadSheetPageLayout
        let frame: CGRect
        let lanes: [CGRect]
    }

    private func makeChart(_ style: ChartLayoutStyle, rows: Bool = false, measureCount: Int? = nil) -> Chart {
        var chart = Chart.draft(title: "Automatic cadence", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
            startingMeasureCount: measureCount ?? (rows ? 4 : 3))
        if rows {
            XCTAssertTrue(chart.insertSystemBreak(before: chart.measures[2].id))
        }
        return chart
    }

    private func geometry(_ chart: Chart) throws -> Geometry {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let lanes = try layout.systems.map { system in
            try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system, paperFrame: layout.paperFrame(for: system)))
        }
        return Geometry(layout: layout, frame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), lanes: lanes)
    }

    private func preparedState(_ source: PKDrawing, in chart: inout Chart, geometry: Geometry,
        readableMeasureIDs: Set<UUID>? = nil) throws -> ChordPreviewState {
        _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation(),
            coordinateSpace: PersistentInkCoordinateSpace(size: geometry.frame.size))
        let prepared = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: inputAt,
            requestedDelay: 0, drawingData: source.dataRepresentation(), chordFrame: geometry.frame,
            pageLayout: geometry.layout, flow: .draftPreview, options: .live, layoutStyle: chart.layoutStyle))
        var state = ChordPreviewState(draftBarlines: prepared.barlines, draftEndings: prepared.endings,
            layoutPageSize: pageSize)
        if case .ready(let requests, _) = prepared.outcome {
            state.replaceDraftChords(with: requests.map { request in
                let text = readableMeasureIDs == nil || readableMeasureIDs!.contains(request.target.measureID) ? "C" : nil
                return ChordInkDraftInput(measureID: request.target.measureID,
                    measureIndex: (chart.measures.firstIndex { $0.id == request.target.measureID } ?? 0) + 1,
                    targetFraction: request.target.fraction, visualOrder: request.visualOrder,
                    laneLocation: request.laneLocation, layoutPageSize: pageSize, drawingData: request.drawingData,
                    candidateTexts: text.map { [$0] } ?? [], bestCandidateText: text,
                    confidence: text == nil ? 0 : 4.5, strokeCount: request.strokes.count,
                    targetLifecycle: request.collectingTargetLifecycle.advanced(to: text == nil ? .collecting : .stable))
            })
        }
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state),
            "The fixture must use a complete real current-source census")
        return state
    }

    private func draft(_ drawing: PKDrawing, in chart: Chart, geometry: Geometry, text: String) throws -> ChordInkDraft {
        let target = try XCTUnwrap(LeadSheetChordInkRecognitionTargeting.target(for: drawing,
            chordFrame: geometry.frame, pageLayout: geometry.layout))
        var input = ChordInkDraftInput(measureID: target.measureID,
            measureIndex: try XCTUnwrap(chart.measure(id: target.measureID)).index,
            targetFraction: target.fraction, laneLocation: LeadSheetChordInkRecognitionTargeting.laneLocation(
                for: drawing, chordFrame: geometry.frame, pageLayout: geometry.layout),
            layoutPageSize: pageSize, drawingData: drawing.dataRepresentation(), candidateTexts: [text],
            bestCandidateText: text, confidence: 4.5, strokeCount: drawing.strokes.count)
        input.targetLifecycle = ChordInkRecognitionTargetLifecycle(generationID: UUID(), anchor: input.anchor,
            ownership: .init(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: drawing)), stage: .stable)
        return ChordInkDraft(input: input)
    }

    private func attempt(_ chart: Chart, state: ChordPreviewState, source: PKDrawing,
        geometry: Geometry, matureStructuralIDs: Set<UUID> = [],
        isUsingTool: Bool = false, elapsed: TimeInterval = 0.05) -> ChordInkDraftRenderCoordinator.AutomaticAttempt {
        ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: geometry.frame.size),
            now: inputAt.addingTimeInterval(elapsed), lastInputAt: inputAt, isUsingTool: isUsingTool,
            allowsImmediateSpatialCompletion: true, sourcePageLayout: geometry.layout, sourceChordFrame: geometry.frame,
            matureStructuralIDs: matureStructuralIDs)
    }

    private func assertRetained(_ expected: PKDrawing, in result: ChordInkDraftRenderCoordinator.AutomaticOutcome) throws {
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: result.drawing))
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(result.chart))
        let saved = try PKDrawing(data: XCTUnwrap(reopened.pageHandwrittenChordData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: saved))
        XCTAssertEqual(reopened, result.chart)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: reopened, state: result.remainingState))
    }

    private func chordStroke(at pageX: CGFloat, row: Int, geometry: Geometry, seed: Int,
        verticalOffset: CGFloat = 0) -> PKStroke {
        let center = CGPoint(x: pageX - geometry.frame.minX,
            y: geometry.lanes[row].midY - geometry.frame.minY + verticalOffset)
        return stroke([CGPoint(x: center.x - 6, y: center.y - 5), CGPoint(x: center.x + 6, y: center.y + 5),
            CGPoint(x: center.x - 6, y: center.y + 5), CGPoint(x: center.x + 6, y: center.y - 5)], seed: seed)
    }

    private func barline(at pageX: CGFloat, row: Int, geometry: Geometry, seed: Int) -> PKStroke {
        let x = pageX - geometry.frame.minX
        let lane = geometry.lanes[row]
        return stroke([CGPoint(x: x, y: lane.minY + lane.height * 0.08 - geometry.frame.minY),
            CGPoint(x: x, y: lane.maxY - lane.height * 0.08 - geometry.frame.minY)], seed: seed)
    }

    private func ending(over measure: LeadSheetMeasureLayout, row: Int, geometry: Geometry, seed: Int) -> [PKStroke] {
        let left = measure.staffFrame.minX + 3 - geometry.frame.minX
        let right = measure.staffFrame.maxX - 3 - geometry.frame.minX
        let lane = geometry.lanes[row]
        let top = lane.minY + lane.height * 0.12 - geometry.frame.minY
        return [stroke([CGPoint(x: left, y: top + lane.height * 0.2), CGPoint(x: left, y: top)], seed: seed),
            stroke([CGPoint(x: left, y: top), CGPoint(x: right, y: top)], seed: seed + 1)]
    }

    private func normalized(_ strokes: [PKStroke]) -> PKDrawing {
        LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes))
    }

    private func stroke(_ points: [CGPoint], seed: Int) -> PKStroke {
        let path = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 2.5, height: 2.5),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: path, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
    }
}
#endif

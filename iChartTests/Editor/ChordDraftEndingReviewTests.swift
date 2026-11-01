#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordDraftEndingReviewTests: XCTestCase {
    func testArbitraryLabelsAreNormalizedWithoutChangingTheirMeaning() throws {
        let (chart, state) = try fixture()
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        for (input, expected) in [("1–3, 5", "1–3, 5"), ("  On\n cue  ", "On cue"), ("Last time (x4)", "Last time (x4)")] {
            let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(
                for: request, chart: chart, currentState: state, label: input, endStyle: .open))
            XCTAssertEqual(reviewed.draftEndings[0].label, expected)
            XCTAssertTrue(reviewed.draftEndings[0].isRenderable)
            XCTAssertEqual(reviewed.draftEndings[0].reviewedSourceInkData, request.sourceEndingDrawingData)
            XCTAssertEqual(reviewed.draftEndings[0].endStyle, .open)
            XCTAssertEqual(reviewed.draftEndings[0].identitySignature, state.draftEndings[0].identitySignature)
            XCTAssertEqual(reviewed.draftEndings[1], state.draftEndings[1])
            XCTAssertEqual(reviewed.draftChords, state.draftChords)
            XCTAssertEqual(reviewed.draftBarlines, state.draftBarlines)
            XCTAssertEqual(chart, request.chartSnapshot)
        }
        XCTAssertFalse(state.draftEndings[0].isReviewed)
    }

    func testBlankLabelCannotBeApproved() throws {
        let (chart, state) = try fixture()
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        for text in ["", " \n\t  "] {
            XCTAssertNil(ChordDraftEndingReviewPolicy.reviewedState(
                for: request, chart: chart, currentState: state, label: text, endStyle: .closed))
        }
        XCTAssertTrue(state.draftEndings.allSatisfy { !$0.isReviewed })
    }

    func testRequestSkipsApprovedEndingsButAllowsEditingAnExplicitEnding() throws {
        let (chart, state) = try fixture()
        let first = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(
            for: first, chart: chart, currentState: state, label: "1, 3", endStyle: .closed))
        let next = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: reviewed))
        XCTAssertEqual(next.endingID, state.draftEndings[1].id)
        let edit = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(
            for: chart, state: reviewed, endingID: first.endingID, continuesRendering: false))
        XCTAssertEqual(edit.ending.label, "1, 3")
        XCTAssertFalse(edit.continuesRendering)
        XCTAssertNil(ChordDraftEndingReviewPolicy.request(for: chart, state: state, endingID: UUID()))
    }

    func testCancellingReviewLeavesDraftAndInkByteForByteUnchanged() throws {
        let (chart, state) = try fixture()
        let originalChart = chart
        let originalState = state
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        // Back to Ink discards the sheet's temporary text without applying it.
        XCTAssertEqual(request.state, originalState)
        XCTAssertEqual(state, originalState)
        XCTAssertEqual(chart, originalChart)
        XCTAssertEqual(chart.pageHandwrittenChordData, request.sourceDrawingData)
        XCTAssertFalse(state.draftEndings[0].isRenderable)
    }

    func testEveryReviewedSourceAndDraftChangeInvalidatesApproval() throws {
        let (chart, state) = try fixture()
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        var variants = [ChordPreviewState]()
        var changed = state
        changed.draftEndings[0].sourceStrokeGeometry[0].points[0].x += 0.1
        variants.append(changed)
        changed = state
        changed.draftEndings[0].sourceStrokeIndices.insert(99)
        variants.append(changed)
        changed = state
        changed.draftEndings[0].start.fraction += 0.01
        variants.append(changed)
        changed = state
        changed.draftEndings[0].end.laneLocation.fraction -= 0.01
        variants.append(changed)
        changed = state
        changed.draftEndings[1].endStyle = .open
        variants.append(changed)
        changed = state
        changed.draftEndings[0].id = UUID()
        variants.append(changed)
        changed = state
        changed.layoutPageSize = CGSize(width: 901, height: 1400)
        variants.append(changed)
        changed = state
        changed.draftBarlines.append(DraftBarline(
            measureID: chart.measures[0].id, measureIndex: 0, fraction: 0.3,
            metrics: .init(height: 60, width: 1, angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 0.8)))
        variants.append(changed)
        changed = state
        changed.draftChords.append(ChordInkDraft(input: .init(
            measureID: chart.measures[0].id, measureIndex: 0, targetFraction: 0.2,
            drawingData: Data(), candidateTexts: ["C"], bestCandidateText: "C", confidence: 1, strokeCount: 1)))
        variants.append(changed)
        for stale in variants {
            XCTAssertNil(ChordDraftEndingReviewPolicy.reviewedState(
                for: request, chart: chart, currentState: stale, label: "3.", endStyle: .closed))
        }
        changed = state
        changed.updatedAt = Date(timeIntervalSince1970: 100)
        XCTAssertNotNil(ChordDraftEndingReviewPolicy.reviewedState(
            for: request, chart: chart, currentState: changed, label: "3.", endStyle: .closed),
            "A preview bookkeeping timestamp does not alter the reviewed content.")
    }

    func testChangedChartRangeContextAndSourceCannotReuseAReview() throws {
        let (chart, state) = try fixture()
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        var variants = [Chart]()
        var changed = chart
        changed.pageHandwrittenChordData = PKDrawing().dataRepresentation()
        variants.append(changed)
        changed = chart
        changed.pageHandwrittenChordCoordinateSpace = .init(width: 901, height: 1400)
        variants.append(changed)
        changed = chart
        changed.id = UUID()
        variants.append(changed)
        changed = chart
        changed.layoutStyle = .rhythmSectionSheet
        variants.append(changed)
        changed = chart
        changed.systems[0].startsNewPage = true
        variants.append(changed)
        changed = chart
        changed.systems[0].measures.swapAt(0, 1)
        variants.append(changed)
        changed = chart
        changed.repeatWings.toggle()
        variants.append(changed)
        for stale in variants {
            XCTAssertNil(ChordDraftEndingReviewPolicy.reviewedState(
                for: request, chart: stale, currentState: state, label: "On cue", endStyle: .open))
        }
    }

    func testOwnedInkPreviewContainsOnlyTheChosenEndingAndRequestRejectsMissingSource() throws {
        let (chart, state) = try fixture()
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        let drawing = try PKDrawing(data: request.sourceEndingDrawingData)
        XCTAssertEqual(drawing.strokes.count, 1)
        let complete = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertEqual(complete.strokes.count, 2)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [complete.strokes[0]]), current: drawing))
        var changed = state
        changed.draftEndings[0].sourceStrokeIndices = [99]
        XCTAssertNil(ChordDraftEndingReviewPolicy.request(for: chart, state: changed))
        changed = state
        changed.draftEndings[0].sourceStrokeIndices = []
        XCTAssertNil(ChordDraftEndingReviewPolicy.request(for: chart, state: changed))
        changed = state
        changed.draftEndings.append(changed.draftEndings[0])
        XCTAssertNil(ChordDraftEndingReviewPolicy.request(for: chart, state: changed))
        var missing = chart
        missing.pageHandwrittenChordData = nil
        XCTAssertNil(ChordDraftEndingReviewPolicy.request(for: missing, state: state))
    }

    func testChordBatchCannotApproveChangedEndingGeometryOrLabels() throws {
        let (chart, initialState) = try fixture()
        var state = initialState
        let chord = ChordInkDraft(input: .init(
            measureID: chart.measures[0].id, measureIndex: 0, targetFraction: 0.2,
            drawingData: Data(), candidateTexts: ["C"], bestCandidateText: "C", confidence: 0.7, strokeCount: 1))
        state.draftChords = [chord]
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let mutations: [(inout DraftEnding) -> Void] = [
            { $0.label = "1, 3" },
            { $0.endStyle = .open },
            { $0.isReviewed = true },
            { $0.end.fraction -= 0.1 },
            { $0.sourceStrokeGeometry[0].points[0].x += 0.1 }
        ]
        for mutation in mutations {
            var changed = state
            mutation(&changed.draftEndings[0])
            let result = ChordInkDraftReviewPolicy.validation(
                from: changed, batch: batch, candidateTextByDraftID: [chord.id: "C"])
            guard case .failure(let reason) = result else {
                return XCTFail("A chord approval must not carry changed endings through Render")
            }
            XCTAssertEqual(reason, .endingsChanged)
        }
        let unchanged = try ChordInkDraftReviewPolicy.validation(
            from: state, batch: batch, candidateTextByDraftID: [chord.id: "C"]).get()
        XCTAssertEqual(unchanged.draftEndings, state.draftEndings,
            "Chord review preserves the ending's existing approval state; it cannot approve its label.")
        XCTAssertTrue(unchanged.draftEndings.allSatisfy { !$0.isReviewed })
    }

    func testBeginningRepeatConfirmationRejectsAnyChangedEndingSnapshot() throws {
        let (chart, initialState) = try fixture()
        var state = initialState
        state.draftBarlines = [DraftBarline(
            measureID: chart.measures[0].id, measureIndex: 0, fraction: 0.8,
            sourceStrokeIndex: 0,
            metrics: .init(height: 60, width: 1, angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 0.8),
            kind: .repeatEnd)]
        let request = try XCTUnwrap(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: state))
        var changed = state
        changed.draftEndings[0].label = "On cue"
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: chart, currentState: changed))
        changed = state
        changed.draftEndings[0].end.laneLocation.fraction -= 0.1
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: chart, currentState: changed))
        changed = state
        changed.draftEndings.removeLast()
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: chart, currentState: changed))
        let confirmed = try XCTUnwrap(ChordDraftRepeatReviewPolicy.confirmedState(
            for: request, chart: chart, currentState: state))
        XCTAssertTrue(confirmed.draftBarlines[0].repeatFromBeginningConfirmed)
        XCTAssertEqual(confirmed.draftEndings, state.draftEndings)
    }

    func testExplicitMeasureChoiceCommitsAnUnsnappedBracketWithoutRedrawingInk() throws {
        let (originalChart, state) = try unsnappedFixture()
        let ending = try XCTUnwrap(state.draftEndings.first)
        XCTAssertNil(originalChart.draftEndingMeasureRange(for: ending, state: state))
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: originalChart, state: state))
        XCTAssertNil(request.measureRange)
        XCTAssertEqual(request.availableMeasureCount, 4)
        let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(
            for: request, chart: originalChart, currentState: state,
            label: "On cue", endStyle: .open, measureRange: 2...3))
        XCTAssertEqual(reviewed.draftEndings[0].reviewedMeasureRange, 2...3)
        XCTAssertEqual(reviewed.draftEndings[0].sourceStrokeGeometry, ending.sourceStrokeGeometry)
        XCTAssertEqual(reviewed.draftEndings[0].start, ending.start)
        XCTAssertEqual(reviewed.draftEndings[0].end, ending.end)
        XCTAssertEqual(originalChart.draftEndingMeasureRange(for: reviewed.draftEndings[0], state: reviewed), 2...3)
        XCTAssertNil(ChordDraftEndingReviewPolicy.firstEndingNeedingReview(chart: originalChart, state: reviewed))
        var rendered = originalChart
        let result = rendered.commitChordInkDraftBatch(reviewed)
        XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(result.renderedEndingCount, 1)
        let object = try XCTUnwrap(rendered.roadmapObjects.first { $0.type.isEnding })
        XCTAssertEqual(object.startMeasureID, originalChart.measures[1].id)
        XCTAssertEqual(object.endMeasureID, originalChart.measures[2].id)
        XCTAssertEqual(object.resolvedEndingDisplayText, "On cue")
        XCTAssertNil(rendered.pageHandwrittenChordData)
        XCTAssertEqual(originalChart.pageHandwrittenChordData, request.sourceDrawingData,
            "The original chart and source remain value snapshots during review and staging")
    }

    func testMissingOrOutOfBoundsMeasureChoiceCannotApproveAnUnmappedEnding() throws {
        let (chart, state) = try unsnappedFixture()
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        XCTAssertNil(ChordDraftEndingReviewPolicy.reviewedState(
            for: request, chart: chart, currentState: state, label: "3.", endStyle: .closed))
        for invalid in [0...1, 1...5, -2...0] {
            XCTAssertNil(ChordDraftEndingReviewPolicy.reviewedState(
                for: request, chart: chart, currentState: state, label: "3.", endStyle: .closed,
                measureRange: invalid))
        }
        XCTAssertNotNil(ChordDraftEndingReviewPolicy.reviewedState(
            for: request, chart: chart, currentState: state, label: "3.", endStyle: .closed,
            measureRange: 4...4))
        XCTAssertTrue(state.draftEndings.allSatisfy { $0.reviewedMeasureRange == nil && !$0.isReviewed })
        XCTAssertEqual(chart, request.chartSnapshot)
    }

    func testRangeContextRejectsBarlineChartSourceAndRequiredRowChanges() throws {
        let (chart, state) = try fixture()
        let context = try XCTUnwrap(ChordDraftEndingRangeReviewContext.capture(chart: chart, state: state))
        XCTAssertTrue(context.matches(chart: chart, state: state))
        var changedChart = chart
        changedChart.title += " changed"
        XCTAssertFalse(context.matches(chart: changedChart, state: state))
        changedChart = chart
        changedChart.systems[0].measures.swapAt(0, 1)
        XCTAssertFalse(context.matches(chart: changedChart, state: state))
        changedChart = chart
        changedChart.pageHandwrittenChordCoordinateSpace = .init(width: 901, height: 1400)
        XCTAssertFalse(context.matches(chart: changedChart, state: state),
            "Coordinate metadata belongs to the approved range even if source paths are unchanged")
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let original = source.strokes[0]
        var replaced = source.strokes
        replaced[0] = PKStroke(ink: original.ink,
            path: PKStrokePath(controlPoints: Array(original.path),
                creationDate: original.path.creationDate.addingTimeInterval(1)),
            transform: original.transform, mask: original.mask, randomSeed: original.randomSeed)
        changedChart = chart
        changedChart.pageHandwrittenChordData = PKDrawing(strokes: replaced).dataRepresentation()
        XCTAssertFalse(context.matches(chart: changedChart, state: state),
            "Identical geometry with a new source chronology requires review")
        var changedState = state
        changedState.draftBarlines = [DraftBarline(
            measureID: chart.measures[0].id, measureIndex: 0, fraction: 0.4,
            laneLocation: .init(systemIndex: 0, fraction: 0.4), sourceStrokeIndex: 0,
            metrics: .init(height: 60, width: 1, angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 0.8))]
        XCTAssertFalse(context.matches(chart: chart, state: changedState))
        let withBarline = try XCTUnwrap(ChordDraftEndingRangeReviewContext.capture(chart: chart, state: changedState))
        changedState.draftBarlines[0].fraction += 0.000001
        XCTAssertFalse(withBarline.matches(chart: chart, state: changedState),
            "A fraction change inside one identity bucket still invalidates an ordinal approval")
        changedState = state
        changedState.draftEndings[0].end.laneLocation.systemIndex = 1
        XCTAssertFalse(context.matches(chart: chart, state: changedState))
        changedState = state
        changedState.layoutPageSize = CGSize(width: 901, height: 1400)
        XCTAssertFalse(context.matches(chart: chart, state: changedState))
    }

    func testRangeContextAllowsPenNormalizationAndChordTextCorrection() throws {
        let (chart, initialState) = try fixture()
        var state = initialState
        state.draftChords = [ChordInkDraft(input: .init(
            measureID: chart.measures[0].id, measureIndex: 0, targetFraction: 0.2,
            laneLocation: .init(systemIndex: 0, fraction: 0.2), drawingData: Data(),
            candidateTexts: ["C"], bestCandidateText: "C", confidence: 0.7, strokeCount: 1))]
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        let approved = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(
            for: request, chart: chart, currentState: state, label: "1–3, 5", endStyle: .closed))
        let context = try XCTUnwrap(approved.draftEndings[0].reviewedRangeContext)
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: approved))
        let corrected = try ChordInkDraftReviewPolicy.validation(
            from: approved, batch: batch, candidateTextByDraftID: [approved.draftChords[0].id: "D7"]).get()
        XCTAssertTrue(context.matches(chart: chart, state: corrected))
        XCTAssertEqual(chart.draftEndingMeasureRange(for: corrected.draftEndings[0], state: corrected), 1...2)
        var normalizedChart = chart
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let normalized = source.strokes.map {
            PKStroke(ink: PKInk(.marker, color: .red), path: $0.path,
                transform: $0.transform, mask: $0.mask, randomSeed: $0.randomSeed)
        }
        normalizedChart.pageHandwrittenChordData = PKDrawing(strokes: normalized).dataRepresentation()
        normalizedChart.updatedAt = chart.updatedAt.addingTimeInterval(2)
        XCTAssertTrue(context.matches(chart: normalizedChart, state: corrected),
            "Encoding/color normalization and bookkeeping time do not change the approved measures")
    }

    func testStaleRangeReopensReviewWithoutSilentlyRevertingToInference() throws {
        let (chart, state) = try fixture()
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        let approved = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(
            for: request, chart: chart, currentState: state, label: "On cue", endStyle: .open,
            measureRange: 2...3))
        var changedChart = chart
        changedChart.title += " changed"
        XCTAssertNil(changedChart.draftEndingMeasureRange(for: approved.draftEndings[0], state: approved))
        XCTAssertEqual(changedChart.draftEndingMeasureRange(
            for: approved.draftEndings[0], state: approved, ignoringReviewedRange: true), 1...2)
        XCTAssertEqual(ChordDraftEndingReviewPolicy.firstEndingNeedingReview(
            chart: changedChart, state: approved)?.id, approved.draftEndings[0].id)
        let reopened = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: changedChart, state: approved))
        XCTAssertEqual(reopened.ending.label, "On cue")
        XCTAssertEqual(reopened.measureRange, 1...2,
            "A fresh inference can be offered for explicit reapproval, never silently substituted at commit")
        XCTAssertNil(ChordDraftEndingReviewPolicy.reviewedState(
            for: request, chart: changedChart, currentState: approved,
            label: "On cue", endStyle: .open, measureRange: 2...3))
    }

    private func unsnappedFixture() throws -> (Chart, ChordPreviewState) {
        let (base, baseState) = try fixture()
        var chart = base
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: try XCTUnwrap(baseState.layoutPageSize), includesChordInkContinuationLanes: true)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let original = try PKDrawing(data: XCTUnwrap(base.pageHandwrittenChordData)).strokes[0]
        var points = original.path.map(\.location)
        points[0].x += 50
        points[1].x += 50
        points[2].x -= 50
        points[3].x -= 50
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [stroke(points)]).dataRepresentation())
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.repeatAwareVisibleDrawingContext(
            from: source, chordFrame: frame, pageLayout: layout)
        let detection = ChordDraftEndingRecognizer.recognize(
            strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing), chordFrame: frame, pageLayout: layout)
        var state = ChordPreviewState()
        state.layoutPageSize = baseState.layoutPageSize
        state.replaceDraftEndings(with: context.remappedEndingRecognition(
            context.endingRecognitionWithUnambiguousSourceStrokes(detection)).endings)
        XCTAssertEqual(state.draftEndings.count, 1)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        return (chart, state)
    }

    private func fixture() throws -> (Chart, ChordPreviewState) {
        var chart = Chart.blank(title: "Ending review", measureCount: 4, layoutStyle: .simpleChordSheet)
        let pageSize = CGSize(width: 900, height: 1400)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system,
            paperFrame: layout.paperFrame(for: system)))
        let top = lane.minY + lane.height * 0.1 - chordFrame.minY
        let hook = lane.height * 0.22
        var endpoints: [(start: DraftEndingEndpoint, end: DraftEndingEndpoint)] = []
        let strokes = (0..<2).map { index -> PKStroke in
            let first = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(system.measures[index * 2],
                in: system, paperFrame: layout.paperFrame(for: system), layoutStyle: chart.layoutStyle)
            let last = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(system.measures[index * 2 + 1],
                in: system, paperFrame: layout.paperFrame(for: system), layoutStyle: chart.layoutStyle)
            let left = first.frame.minX + 1
            let right = last.frame.maxX - 1
            endpoints.append((
                .init(measureID: chart.measures[index * 2].id, measureIndex: index * 2, fraction: 0,
                    laneLocation: .init(systemIndex: system.index, fraction: Double((left - lane.minX) / lane.width))),
                .init(measureID: chart.measures[index * 2 + 1].id, measureIndex: index * 2 + 1, fraction: 0.9999,
                    laneLocation: .init(systemIndex: system.index, fraction: Double((right - lane.minX) / lane.width)))
            ))
            return stroke([CGPoint(x: left - chordFrame.minX, y: top + hook),
                CGPoint(x: left - chordFrame.minX, y: top), CGPoint(x: right - chordFrame.minX, y: top),
                CGPoint(x: right - chordFrame.minX, y: top + hook)], seed: UInt32(index))
        }
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: strokes).dataRepresentation())
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.draftEndings = strokes.indices.map { index in
            DraftEnding(start: endpoints[index].start, end: endpoints[index].end,
                layoutPageSize: pageSize, sourceStrokeIndices: [index],
                sourceStrokeGeometry: PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: [strokes[index]])),
                endStyle: .closed)
        }
        XCTAssertEqual(chart.draftEndingMeasureRange(for: state.draftEndings[0], state: state), 1...2)
        XCTAssertEqual(chart.draftEndingMeasureRange(for: state.draftEndings[1], state: state), 3...4)
        return (chart, state)
    }

    private func stroke(_ points: [CGPoint], seed: UInt32 = 7) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif

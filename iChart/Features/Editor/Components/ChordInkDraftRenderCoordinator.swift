#if canImport(UIKit) && canImport(PencilKit)
import PencilKit

/// Synchronous bridge to the canvas owner. Capturing live ink, preparing the
/// chart, and consuming the canvas can happen in one main-thread callback.
@MainActor
final class ChordInkDraftRenderCoordinator {
    struct Outcome {
        let chart: Chart
        let result: ChordInkDraftBatchRenderResult

        var canConsumeSource: Bool {
            !result.didRejectIncompleteSourceCoverage
                && result.unresolvedDraftIDs.isEmpty
                && (result.renderedChordCount > 0 || result.renderedBarlineCount > 0 || result.renderedEndingCount > 0)
        }
    }

    var renderer: ((Chart, ChordPreviewState) -> Outcome?)?
    struct AutomaticOutcome {
        let chart: Chart
        let drawing: PKDrawing
        let remainingState: ChordPreviewState
        let result: ChordInkDraftBatchRenderResult
        let consumedDraftIDs: Set<UUID>
    }

    struct AutomaticAttempt {
        var outcome: AutomaticOutcome? = nil
        var feedback: ChordInkAutomaticRenderFeedback
    }

    var automaticRenderer: ((Chart, ChordPreviewState, Date, Date?) -> AutomaticOutcome?)?
    var automaticAttempter: ((Chart, ChordPreviewState, Date, Date?) -> AutomaticAttempt)?
    var reviewedAutomaticAttempter: ((Chart, ChordPreviewState) -> AutomaticAttempt)?
    var automaticCensusReplayer: (() -> Bool)?
    private(set) var lastAutomaticAttempt: AutomaticAttempt?
    struct RewriteOutcome {
        let chart: Chart
        let drawing: PKDrawing
    }

    var rewriter: ((Chart, ChordPreviewState, ChordInkDraft) -> RewriteOutcome?)?
    // Actual PencilKit input callbacks, not summed recognizer compute time.
    var lastInputAt: Date?
    // A fresh automatic census of existing ink can finish without fabricating
    // a Pencil callback. This deadline never enters pen timing diagnostics.
    var renderSessionReadyAt: Date?
    var automaticRenderReferenceAt: Date? { lastInputAt ?? renderSessionReadyAt }

    init() {}

    func invalidateAutomaticFeedback() {
        lastAutomaticAttempt = nil
    }

    @discardableResult
    func replayCurrentAutomaticChordCensus() -> Bool {
        automaticCensusReplayer?() ?? false
    }

    func render(chart: Chart, state: ChordPreviewState) -> Outcome? {
        renderer?(chart, state)
    }

    func renderAutomatically(
        chart: Chart, state: ChordPreviewState, now: Date = .now, lastInputAt: Date?
    ) -> AutomaticOutcome? {
        attemptAutomatically(chart: chart, state: state, now: now, lastInputAt: lastInputAt).outcome
    }

    func attemptAutomatically(
        chart: Chart, state: ChordPreviewState, now: Date = .now, lastInputAt: Date?
    ) -> AutomaticAttempt {
        let attempt = automaticAttempter?(chart, state, now, lastInputAt)
            ?? AutomaticAttempt(outcome: automaticRenderer?(chart, state, now, lastInputAt),
                feedback: .baseline(for: state))
        lastAutomaticAttempt = attempt
        return attempt
    }

    func attemptReviewedAutomatically(chart: Chart, state: ChordPreviewState) -> AutomaticAttempt {
        let attempt = reviewedAutomaticAttempter?(chart, state)
            ?? AutomaticAttempt(feedback: .init(globalReason: .placementUnavailable))
        lastAutomaticAttempt = attempt
        return attempt
    }

    func renderReviewedAutomatically(chart: Chart, state: ChordPreviewState) -> Outcome? {
        attemptReviewedAutomatically(chart: chart, state: state).outcome.map { Outcome(chart: $0.chart, result: $0.result) }
    }

    func rewrite(chart: Chart, state: ChordPreviewState, draft: ChordInkDraft) -> RewriteOutcome? {
        rewriter?(chart, state, draft)
    }

    static func prepareRewrite(
        chart: Chart, state: ChordPreviewState, draft: ChordInkDraft, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?
    ) -> RewriteOutcome? {
        guard let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, in: state, source: currentDrawing),
              let remaining = plan.rewrittenDrawing(ifCurrentSource: currentDrawing) else { return nil }
        let serialization = LeadSheetPersistentInkColorPolicy.serialization(for: remaining)
        var updatedChart = chart
        _ = updatedChart.setPageHandwrittenChordDrawing(
            remaining.strokes.isEmpty ? nil : serialization.drawingData,
            coordinateSpace: remaining.strokes.isEmpty ? nil : coordinateSpace,
            assumesNormalizedPersistentInk: true
        )
        return RewriteOutcome(chart: updatedChart, drawing: remaining)
    }

    /// Stages automatic changes against exact, uniquely owned live strokes.
    /// Partial rendering uses the ordinary complete-coverage transaction on
    /// only its selected source, then restores every unconsumed source stroke.
    /// The coverage check itself is never weakened for automatic mode.
    static func prepareAutomatic(
        chart: Chart,
        state: ChordPreviewState,
        currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?,
        now: Date,
        lastInputAt: Date?,
        isUsingTool: Bool,
        allowsImmediateSpatialCompletion: Bool = false,
        sourcePageLayout: LeadSheetPageLayout? = nil,
        sourceChordFrame: CGRect? = nil
    ) -> AutomaticOutcome? {
        prepareAutomaticAttempt(chart: chart, state: state, currentDrawing: currentDrawing,
            coordinateSpace: coordinateSpace, now: now, lastInputAt: lastInputAt, isUsingTool: isUsingTool,
            allowsImmediateSpatialCompletion: allowsImmediateSpatialCompletion,
            sourcePageLayout: sourcePageLayout, sourceChordFrame: sourceChordFrame).outcome
    }

    static func prepareAutomaticAttempt(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?, now: Date, lastInputAt: Date?, isUsingTool: Bool,
        allowsImmediateSpatialCompletion: Bool = false,
        sourcePageLayout: LeadSheetPageLayout? = nil, sourceChordFrame: CGRect? = nil
    ) -> AutomaticAttempt {
        var feedback = ChordInkAutomaticRenderFeedback.baseline(for: state)
        var renderState = state
        for index in renderState.draftChords.indices {
            guard let candidate = ChordInkAutomaticRenderPolicy.automaticCandidateText(for: renderState.draftChords[index]) else {
                continue
            }
            // This transient workflow choice leaves the original result,
            // confidence, decision, ownership, and user-selection fields alone.
            renderState.draftChords[index].bestCandidateText = candidate
            if !renderState.draftChords[index].candidateTexts.contains(candidate) {
                renderState.draftChords[index].candidateTexts.append(candidate)
            }
        }
        let outcome = prepareAutomaticOutcome(chart: chart, state: renderState, currentDrawing: currentDrawing,
            coordinateSpace: coordinateSpace, now: now, lastInputAt: lastInputAt, isUsingTool: isUsingTool,
            allowsImmediateSpatialCompletion: allowsImmediateSpatialCompletion,
            sourcePageLayout: sourcePageLayout, sourceChordFrame: sourceChordFrame, feedback: &feedback)
        if let outcome {
            feedback = feedback.retainingDraftIDs(Set(outcome.remainingState.draftChords.map(\.id)),
                keepsGlobalReason: !outcome.drawing.strokes.isEmpty)
        }
        return AutomaticAttempt(outcome: outcome, feedback: feedback)
    }

    private static func prepareAutomaticOutcome(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?, now: Date, lastInputAt: Date?, isUsingTool: Bool,
        allowsImmediateSpatialCompletion: Bool,
        sourcePageLayout: LeadSheetPageLayout?, sourceChordFrame: CGRect?,
        feedback: inout ChordInkAutomaticRenderFeedback
    ) -> AutomaticOutcome? {
        // Structural-only failures use the global status route; per-draft
        // status cards are chord-specific.
        let allIDs = Set(state.draftChords.map(\.id))
        guard !isUsingTool else { feedback.set(.waiting, for: allIDs); return nil }
        guard !currentDrawing.strokes.isEmpty else {
            if !state.isEmpty { feedback.set(.needsSourceRefresh, for: allIDs) }
            return nil
        }
        guard !state.isEmpty else { feedback.globalReason = .unrepresentedInk; return nil }
        guard let elapsed = ChordInkAutomaticRenderPolicy.elapsedSinceInput(now: now, lastInputAt: lastInputAt) else {
            feedback.globalReason = .restoredInk; return nil
        }
        guard allowsImmediateSpatialCompletion || elapsed >= ChordInkAutomaticRenderPolicy.spaceDelay else { return nil }
        let isIdle = elapsed >= ChordInkAutomaticRenderPolicy.requiredIdleDelay(for: state)
        guard let sourceLayout = sourcePageLayout ?? state.layoutPageSize.map({
            LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: $0,
                includesChordInkContinuationLanes: true)
        }) else { feedback.set(.placementUnavailable, for: allIDs); return nil }
        let sourceFrame = sourceChordFrame ?? LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)

        // Barlines can materialize measures and alter chord placement. Commit
        // them only with the entire current source after the full idle pause.
        // Repeat-from-beginning confirmation remains an explicit user choice.
        if isIdle,
           state.draftChords.allSatisfy({ ChordInkAutomaticRenderPolicy.automaticCandidateText(for: $0) != nil }),
           state.unresolvedBarlineCount == 0,
           state.unresolvedEndingCount == 0,
           ChordDraftRepeatReviewPolicy.blockingMessage(for: state) == nil,
           ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: state) == nil {
            var committed = state
            committed.markRenderableDraftsCommitted(updatedAt: now)
            let complete = prepare(chart: chart, state: committed,
                currentDrawing: currentDrawing, coordinateSpace: coordinateSpace,
                automaticContinuationSourceLayout: sourceLayout)
            var failureReason = ChordInkAutomaticRenderReason.placementUnavailable
            if complete.canConsumeSource,
               let positionedChart = automaticallyPositionedChart(originalChart: chart,
                preparedChart: complete.chart, state: state, result: complete.result,
                remainingDrawing: PKDrawing(), sourceLayout: sourceLayout, sourceFrame: sourceFrame,
                failureReason: &failureReason) {
                return AutomaticOutcome(chart: positionedChart, drawing: PKDrawing(),
                    remainingState: ChordPreviewState(), result: complete.result,
                    consumedDraftIDs: Set(state.draftChords.map(\.id) + state.draftBarlines.map(\.id) + state.draftEndings.map(\.id)))
            }
            if complete.canConsumeSource {
                feedback.set(failureReason, for: allIDs)
            } else if complete.result.hasUnplacedPlainBarline(in: committed) {
                feedback.globalReason = .barlinePlacementUnavailable
            } else {
                feedback.set(complete.result.didRejectIncompleteSourceCoverage ? .needsSourceRefresh : .placementUnavailable,
                    for: allIDs)
            }
        }

        // Retaining a barline while committing only its neighbors could put
        // those chords into measures which the later barline will split.
        guard state.draftBarlines.isEmpty && state.draftEndings.isEmpty else {
            if !isIdle {
                feedback.set(.waiting, for: allIDs)
            } else if ChordDraftRepeatReviewPolicy.blockingMessage(for: state) != nil
                || ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: state) != nil {
                feedback.globalReason = .repeatReview
            } else if state.unresolvedEndingCount > 0 {
                feedback.globalReason = .endingReview
            } else if isIdle, state.unresolvedBarlineCount > 0 {
                feedback.globalReason = .placementUnavailable
            }
            return nil
        }
        // Every current fragment must first have a target assigned by the
        // existing grouping pipeline. A wide gap in unrepresented new ink
        // cannot tell the next root from a widely spaced slash or extension.
        // Bind coverage to live source, never the chart's older saved bytes.
        let liveSerialization = LeadSheetPersistentInkColorPolicy.serialization(for: currentDrawing)
        var liveSourceChart = chart
        _ = liveSourceChart.setPageHandwrittenChordDrawing(
            liveSerialization.drawingData, coordinateSpace: coordinateSpace,
            assumesNormalizedPersistentInk: true)
        guard ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: liveSourceChart, state: state) else {
            let invalidIDs = Set(state.draftChords.filter {
                ChordInkDraftLocalRewritePolicy.plan(for: $0, in: state, source: currentDrawing) == nil
            }.map(\.id))
            if invalidIDs.isEmpty { feedback.globalReason = .unrepresentedInk }
            else { feedback.set(.needsSourceRefresh, for: invalidIDs); feedback.globalReason = .needsSourceRefresh }
            return nil
        }
        var selectedDrafts: [ChordInkDraft] = []
        var selectedIndices = Set<Int>()
        var candidatePlans: [(ChordInkDraft, Set<Int>)] = []
        for draft in state.draftChords where ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft) != nil {
            guard let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, in: state, source: currentDrawing),
                  selectedIndices.isDisjoint(with: plan.originalStrokeIndices) else {
                feedback.reasonsByDraftID[draft.id] = .needsSourceRefresh
                continue
            }
            guard ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(
                    originalStrokeIndices: plan.originalStrokeIndices, source: currentDrawing,
                    pageSize: state.layoutPageSize, requiresLaterInk: !isIdle
                  ) else {
                if isIdle { feedback.reasonsByDraftID[draft.id] = .adjacentWriting }
                continue
            }
            selectedDrafts.append(draft)
            selectedIndices.formUnion(plan.originalStrokeIndices)
            candidatePlans.append((draft, plan.originalStrokeIndices))
        }
        guard !selectedDrafts.isEmpty else { return nil }
        var combinedFailure = ChordInkAutomaticRenderReason.placementUnavailable
        if let combined = preparePartialAutomatic(chart: chart, state: state,
            currentDrawing: currentDrawing, coordinateSpace: coordinateSpace, now: now,
            selectedDrafts: selectedDrafts, selectedIndices: selectedIndices,
            sourceLayout: sourceLayout, sourceFrame: sourceFrame, failureReason: &combinedFailure) { return combined }
        feedback.set(combinedFailure, for: Set(selectedDrafts.map(\.id)))
        // A wide label may be unsafe while a different completed chord still
        // fits. Retain the conflicting source and let one safe target finish;
        // the next census will reassess all remaining targets independently.
        if candidatePlans.count > 1 {
            // A failed combined transaction does not prove each remaining
            // target has the same collision. Record individual refusals only.
            for draft in selectedDrafts {
                feedback.reasonsByDraftID[draft.id] = ChordInkAutomaticFeedbackPolicy.recognitionReason(for: draft)
            }
            for (draft, indices) in candidatePlans {
                var singleFailure = ChordInkAutomaticRenderReason.placementUnavailable
                if let single = preparePartialAutomatic(chart: chart, state: state,
                    currentDrawing: currentDrawing, coordinateSpace: coordinateSpace, now: now,
                    selectedDrafts: [draft], selectedIndices: indices,
                    sourceLayout: sourceLayout, sourceFrame: sourceFrame, failureReason: &singleFailure) { return single }
                feedback.reasonsByDraftID[draft.id] = singleFailure
            }
        }
        return nil
    }

    /// Explicit review fixes the requested text; it does not grant permission
    /// to erase changed ink or to return to beat-snapped automatic placement.
    static func prepareReviewedAutomaticAttempt(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?, isUsingTool: Bool,
        sourcePageLayout: LeadSheetPageLayout? = nil, sourceChordFrame: CGRect? = nil
    ) -> AutomaticAttempt {
        var feedback = ChordInkAutomaticRenderFeedback.baseline(for: state)
        let ids = Set(state.draftChords.map(\.id))
        guard !isUsingTool else { feedback.set(.waiting, for: ids); return .init(feedback: feedback) }
        guard ChordDraftRepeatReviewPolicy.blockingMessage(for: state) == nil,
              ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: state) == nil else {
            feedback.globalReason = .repeatReview
            return .init(feedback: feedback)
        }
        var committed = state
        committed.markRenderableDraftsCommitted()
        guard let sourceLayout = sourcePageLayout ?? state.layoutPageSize.map({
            LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: $0, includesChordInkContinuationLanes: true)
        }) else { feedback.set(.placementUnavailable, for: ids); return .init(feedback: feedback) }
        let prepared = prepare(chart: chart, state: committed, currentDrawing: currentDrawing,
            coordinateSpace: coordinateSpace, automaticContinuationSourceLayout: sourceLayout)
        guard prepared.canConsumeSource else {
            if prepared.result.hasUnplacedPlainBarline(in: committed) {
                feedback.globalReason = .barlinePlacementUnavailable
            } else {
                feedback.set(prepared.result.didRejectIncompleteSourceCoverage ? .needsSourceRefresh : .placementUnavailable, for: ids)
            }
            return .init(feedback: feedback)
        }
        let frame = sourceChordFrame ?? LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        var refusal = ChordInkAutomaticRenderReason.placementUnavailable
        guard let positioned = automaticallyPositionedChart(originalChart: chart,
            preparedChart: prepared.chart, state: committed, result: prepared.result,
            remainingDrawing: PKDrawing(), sourceLayout: sourceLayout, sourceFrame: frame,
            failureReason: &refusal) else {
            feedback.set(refusal, for: ids)
            return .init(feedback: feedback)
        }
        return .init(outcome: AutomaticOutcome(chart: positioned, drawing: PKDrawing(),
            remainingState: ChordPreviewState(), result: prepared.result,
            consumedDraftIDs: Set(state.draftChords.map(\.id) + state.draftBarlines.map(\.id) + state.draftEndings.map(\.id))), feedback: .init())
    }

    private static func preparePartialAutomatic(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?, now: Date,
        selectedDrafts: [ChordInkDraft], selectedIndices: Set<Int>,
        sourceLayout: LeadSheetPageLayout, sourceFrame: CGRect,
        failureReason: inout ChordInkAutomaticRenderReason
    ) -> AutomaticOutcome? {
        let selectedSource = PKDrawing(strokes: currentDrawing.strokes.enumerated().compactMap { index, stroke in
            selectedIndices.contains(index) ? stroke : nil
        })
        let remaining = PKDrawing(strokes: currentDrawing.strokes.enumerated().compactMap { index, stroke in
            selectedIndices.contains(index) ? nil : stroke
        })
        var selectedState = ChordPreviewState(draftChords: selectedDrafts, layoutPageSize: state.layoutPageSize)
        selectedState.markRenderableDraftsCommitted(updatedAt: now)
        let prepared = prepare(chart: chart, state: selectedState,
            currentDrawing: selectedSource, coordinateSpace: coordinateSpace,
            automaticContinuationSourceLayout: sourceLayout)
        guard prepared.canConsumeSource else {
            failureReason = prepared.result.didRejectIncompleteSourceCoverage ? .needsSourceRefresh : .placementUnavailable
            return nil
        }

        let serialization = LeadSheetPersistentInkColorPolicy.serialization(for: remaining)
        var updatedChart = prepared.chart
        _ = updatedChart.setPageHandwrittenChordDrawing(
            remaining.strokes.isEmpty ? nil : serialization.drawingData,
            coordinateSpace: remaining.strokes.isEmpty ? nil : coordinateSpace,
            assumesNormalizedPersistentInk: true)
        guard let positionedChart = automaticallyPositionedChart(originalChart: chart,
            preparedChart: updatedChart, state: selectedState, result: prepared.result,
            remainingDrawing: remaining, sourceLayout: sourceLayout, sourceFrame: sourceFrame,
            failureReason: &failureReason) else { return nil }
        let consumedIDs = Set(selectedDrafts.map(\.id))
        var remainingState = state
        remainingState.draftChords.removeAll { consumedIDs.contains($0.id) }
        remainingState.updatedAt = now
        return AutomaticOutcome(chart: positionedChart, drawing: remaining,
            remainingState: remainingState, result: prepared.result, consumedDraftIDs: consumedIDs)
    }

    /// Musical placement still comes from the normal commit. Only automatic
    /// rendering pins the glyph's visual left edge to the source which it
    /// consumes, using the existing persisted visual placement field.
    private static func automaticallyPositionedChart(
        originalChart: Chart, preparedChart: Chart, state: ChordPreviewState,
        result: ChordInkDraftBatchRenderResult, remainingDrawing: PKDrawing,
        sourceLayout: LeadSheetPageLayout, sourceFrame: CGRect,
        failureReason: inout ChordInkAutomaticRenderReason
    ) -> Chart? {
        var positioned = preparedChart
        let destinationLayout = LeadSheetPageLayoutEngine.pageLayout(for: positioned,
            pageSize: sourceLayout.pageBounds.size, includesChordInkContinuationLanes: true)
        let beforeGlyphs = sourceLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
        let structuralSourceIDs = Set(state.draftBarlines.map(\.measureID))
        // A later barline redistributes already-rendered automatic chords.
        // Preserve their visible page positions using the new segment's actual
        // chord band, while the model split retains event/source identity and
        // independently decides the correct musical measure.
        let pinnedExistingIDs = originalChart.measures.filter { structuralSourceIDs.contains($0.id) }
            .flatMap(\.chordEvents).filter { $0.manualVisualLaneFraction != nil }.map(\.id)
        for id in pinnedExistingIDs {
            let sourceGlyphs = beforeGlyphs.filter { $0.id == id }
            guard sourceGlyphs.count == 1, let sourceGlyph = sourceGlyphs.first,
                  let destinationMeasure = positioned.measures.first(where: { measure in
                      measure.chordEvents.contains { $0.id == id }
                  }), let destination = destinationLayout.systems.flatMap(\.measures).first(where: {
                      $0.sourceMeasureID == destinationMeasure.id
                  }), destination.chordBandFrame.width > 0 else { return nil }
            if destination.chordLayouts.contains(where: {
                $0.id == id && sameFrame($0.naturalFrame, sourceGlyph.naturalFrame)
            }) { continue }
            let fraction = Double((sourceGlyph.naturalFrame.minX - destination.chordBandFrame.minX)
                / destination.chordBandFrame.width)
            guard fraction.isFinite, fraction >= -0.001, fraction <= 1,
                  positioned.moveChordEventInCommittedChordLane(id, to: destinationMeasure.id,
                    atFraction: nil, visualFraction: fraction, preserveMusicalPlacement: true) else {
                failureReason = .needsSpace
                return nil
            }
        }
        var unclaimedDrafts = state.draftChords
        for eventID in result.renderedChordIDs {
            guard let destinationMeasure = positioned.measures.first(where: { measure in
                measure.chordEvents.contains { $0.id == eventID }
            }), let event = destinationMeasure.chordEvents.first(where: { $0.id == eventID }),
               let eventSource = event.sourceInkData.flatMap({ try? PKDrawing(data: $0) }),
               let destination = destinationLayout.systems.flatMap(\.measures).first(where: {
                   $0.sourceMeasureID == destinationMeasure.id
               }), destination.chordBandFrame.width > 0 else { return nil }
            // Archive normalization can change bytes. Match exact visible
            // paths/chronology/transform/seed, never bounds or chord text.
            let matches = unclaimedDrafts.indices.filter { index in
                guard let drawing = try? PKDrawing(data: unclaimedDrafts[index].drawingData) else { return false }
                return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: eventSource, current: drawing)
            }
            guard matches.count == 1, let index = matches.first,
                  let drawing = try? PKDrawing(data: unclaimedDrafts[index].drawingData),
                  let bounds = visibleInkFrames(drawing).reduce(nil as CGRect?, { union, frame in
                      union.map { $0.union(frame) } ?? frame
                  }) else { return nil }
            unclaimedDrafts.remove(at: index)
            let sourceLeftPageX = bounds.minX + sourceFrame.minX
            let fraction = Double((sourceLeftPageX - destination.chordBandFrame.minX) / destination.chordBandFrame.width)
            guard fraction.isFinite,
                  positioned.moveChordEventInCommittedChordLane(eventID, to: destinationMeasure.id,
                    atFraction: nil, visualFraction: fraction, preserveMusicalPlacement: true) else { return nil }
        }

        let finalLayout = LeadSheetPageLayoutEngine.pageLayout(for: positioned,
            pageSize: sourceLayout.pageBounds.size, includesChordInkContinuationLanes: true)
        let remainingFrames = visibleInkFrames(remainingDrawing).map {
            $0.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
        }
        if !remainingFrames.isEmpty {
            // Changing the live canvas region may reproject retained source.
            // Do not guess its prospective location during this transaction.
            let finalSourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: finalLayout)
            guard sameFrame(sourceFrame, finalSourceFrame) else { failureReason = .needsSourceRefresh; return nil }
        }
        let afterGlyphs = finalLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
        let newIDs = Set(result.renderedChordIDs)
        for glyph in afterGlyphs {
            let frame = glyph.naturalFrame.union(glyph.frame)
            let isNew = newIDs.contains(glyph.id)
            let hadSameGeometry = beforeGlyphs.contains { previous in
                previous.id == glyph.id && sameFrame(previous.naturalFrame.union(previous.frame), frame)
            }
            // An unrelated existing overlap does not authorize changing ink,
            // and does not block a target whose transaction leaves it alone.
            guard isNew || !hadSameGeometry else { continue }
            guard !remainingFrames.contains(where: { overlaps(frame, $0) }) else { failureReason = .needsSpace; return nil }
            if isNew {
                guard !afterGlyphs.contains(where: { other in
                    other.id != glyph.id && overlaps(frame, other.naturalFrame.union(other.frame))
                }) else { failureReason = .needsSpace; return nil }
            }
        }
        return positioned
    }

    private static func visibleInkFrames(_ drawing: PKDrawing) -> [CGRect] {
        drawing.strokes.flatMap { PencilKitInkAdapter.visibleStrokeFragments(from: $0) }.compactMap { stroke in
            let frame = stroke.renderBounds.standardized
            guard !frame.isNull, !frame.isInfinite, !frame.isEmpty,
                  frame.minX.isFinite, frame.minY.isFinite, frame.maxX.isFinite, frame.maxY.isFinite else { return nil }
            return frame
        }
    }

    private static func sameFrame(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 0.01 && abs(first.minY - second.minY) < 0.01
            && abs(first.width - second.width) < 0.01 && abs(first.height - second.height) < 0.01
    }

    private static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        let intersection = first.insetBy(dx: -1, dy: -1).intersection(second)
        return !intersection.isNull && intersection.width > 0.5 && intersection.height > 0.5
    }

    /// Prepare exclusively from current live ink, never a cached chart ink
    /// snapshot. This value transaction does not clear or otherwise touch a
    /// canvas. Any rejected, empty, or partial commit returns the original
    /// chart, including its original source bytes, metadata, and timestamps.
    static func prepare(
        chart: Chart,
        state: ChordPreviewState,
        currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?,
        automaticContinuationSourceLayout: LeadSheetPageLayout? = nil
    ) -> Outcome {
        // The Chart coverage API intentionally accepts nil stored ink because
        // no stored source is erased. That shortcut must not let stale drafts
        // render after the live canvas has become empty.
        guard !currentDrawing.strokes.isEmpty else {
            return Outcome(chart: chart, result: ChordInkDraftBatchRenderResult(
                renderedChordIDs: [], renderedBarlineIDs: [], unresolvedDraftIDs: [],
                didRejectIncompleteSourceCoverage: !state.isEmpty
            ))
        }

        let serialization = LeadSheetPersistentInkColorPolicy.serialization(for: currentDrawing)
        var preparedChart = chart
        _ = preparedChart.setPageHandwrittenChordDrawing(
            serialization.drawingData,
            coordinateSpace: coordinateSpace,
            assumesNormalizedPersistentInk: true
        )
        let result = preparedChart.commitChordInkDraftBatch(state,
            automaticContinuationSourceLayout: automaticContinuationSourceLayout)
        let outcome = Outcome(chart: preparedChart, result: result)
        return outcome.canConsumeSource ? outcome : Outcome(chart: chart, result: result)
    }
}
#endif

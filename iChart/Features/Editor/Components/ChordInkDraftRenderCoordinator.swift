#if canImport(UIKit) && canImport(PencilKit)
import PencilKit

/// Synchronous bridge to the canvas owner. Capturing live ink, preparing the
/// chart, and consuming the canvas can happen in one main-thread callback.
@MainActor
final class ChordInkDraftRenderCoordinator {
    struct Outcome {
        let chart: Chart
        let result: ChordInkDraftBatchRenderResult
        var retainedDraft: RetainedDraft? = nil

        var canConsumeSource: Bool {
            !result.didRejectIncompleteSourceCoverage
                && result.unresolvedDraftIDs.isEmpty
                && (result.renderedChordCount > 0 || result.renderedBarlineCount > 0 || result.renderedEndingCount > 0)
        }
    }

    struct RetainedDraft {
        let state: ChordPreviewState
        let drawing: PKDrawing
    }

    var renderer: ((Chart, ChordPreviewState) -> Outcome?)?
    var independentChordRenderer: ((Chart, ChordPreviewState, Set<UUID>) -> Outcome?)?
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
    var manualPreviewPreparer: (() -> Bool)?
    var manualPreviewDrawingProvider: (() -> PKDrawing?)?
    /// Read-only source snapshot for pausing and resuming local help. It does
    /// not prepare recognition, grant a render, or consume source ink.
    var sourceDrawingProvider: (() -> PKDrawing?)?
    private(set) var lastAutomaticAttempt: AutomaticAttempt?
    struct RewriteOutcome {
        let chart: Chart
        let drawing: PKDrawing
    }

    var rewriter: ((Chart, ChordPreviewState, ChordInkDraft) -> RewriteOutcome?)?
    // Actual PencilKit input callbacks, not summed recognizer compute time.
    var lastInputAt: Date? {
        didSet { if lastInputAt == nil { structuralMaturity.reset() } }
    }
    let structuralMaturity = ChordInkStructuralMaturityTracker()
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

    @discardableResult
    func prepareManualPreviewForReview() -> Bool {
        manualPreviewPreparer?() ?? false
    }

    func render(chart: Chart, state: ChordPreviewState) -> Outcome? {
        renderer?(chart, state)
    }

    func renderIndependentChords(chart: Chart, state: ChordPreviewState, excludingChordIDs: Set<UUID> = []) -> Outcome? {
        independentChordRenderer?(chart, state, excludingChordIDs)
    }

    func currentManualPreviewDrawing() -> PKDrawing? {
        manualPreviewDrawingProvider?()
    }

    func currentSourceDrawing() -> PKDrawing? {
        sourceDrawingProvider?()
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
        attemptReviewedAutomatically(chart: chart, state: state).outcome.map(Self.explicitOutcome)
    }

    static func explicitOutcome(_ outcome: AutomaticOutcome) -> Outcome {
        Outcome(chart: outcome.chart, result: outcome.result,
            retainedDraft: outcome.drawing.strokes.isEmpty
                ? nil : RetainedDraft(state: outcome.remainingState, drawing: outcome.drawing))
    }

    static func prepareManual(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?,
        sourcePageLayout: LeadSheetPageLayout? = nil, sourceChordFrame: CGRect? = nil
    ) -> Outcome {
        let full = prepare(chart: chart, state: state, currentDrawing: currentDrawing,
            coordinateSpace: coordinateSpace)
        guard !full.canConsumeSource else { return full }
        return prepareIndependentChords(chart: chart, state: state, currentDrawing: currentDrawing,
            coordinateSpace: coordinateSpace, sourcePageLayout: sourcePageLayout, sourceChordFrame: sourceChordFrame)
            ?? full
    }

    static func prepareIndependentChords(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?, usesAutomaticPositioning: Bool = false,
        sourcePageLayout: LeadSheetPageLayout? = nil, sourceChordFrame: CGRect? = nil,
        excludingChordIDs: Set<UUID> = []
    ) -> Outcome? {
        guard let sourceLayout = sourcePageLayout ?? state.layoutPageSize.map({
            LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: $0, includesChordInkContinuationLanes: true)
        }) else { return nil }
        var feedback = ChordInkAutomaticRenderFeedback.baseline(for: state)
        let sourceFrame = sourceChordFrame ?? LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        let partial = prepareIndependentStructuralOutcome(chart: chart, state: state, currentDrawing: currentDrawing,
            coordinateSpace: coordinateSpace, now: .now, usesAutomaticPositioning: usesAutomaticPositioning,
            sourceLayout: sourceLayout, sourceFrame: sourceFrame)
            ?? prepareIndependentOutcome(chart: chart, state: state, currentDrawing: currentDrawing,
                coordinateSpace: coordinateSpace, now: .now, isIdle: true,
                usesAutomaticPositioning: usesAutomaticPositioning,
                sourceLayout: sourceLayout, sourceFrame: sourceFrame,
                isEligible: { !excludingChordIDs.contains($0.id) && explicitlyRenderable($0) }, feedback: &feedback)
        return partial.map(explicitOutcome)
    }

    private static func explicitlyRenderable(_ draft: ChordInkDraft) -> Bool {
        !draft.isStale && draft.isRenderable && (!draft.requiresConfirmation || draft.selectedText != nil)
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
        sourcePageLayout: LeadSheetPageLayout? = nil, sourceChordFrame: CGRect? = nil,
        matureStructuralIDs: Set<UUID> = []
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
            sourcePageLayout: sourcePageLayout, sourceChordFrame: sourceChordFrame,
            matureStructuralIDs: matureStructuralIDs, feedback: &feedback)
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
        matureStructuralIDs: Set<UUID>,
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

        // A fully ready source may commit together after the shared pause.
        // The independent paths below retain unfinished targets and validate
        // any structural dependencies before consuming their exact source.
        if isIdle,
           state.draftChords.allSatisfy({ ChordInkAutomaticRenderPolicy.automaticCandidateText(for: $0) != nil }),
           state.unresolvedBarlineCount == 0,
           state.unresolvedEndingCount == 0 {
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

        // Structural ink still gets its full recognition pause. Independent
        // chords in unaffected measures can finish while those marks remain
        // ink; their transaction also preserves every retained writing lane.
        if !state.draftBarlines.isEmpty || !state.draftEndings.isEmpty {
            if !isIdle {
                feedback.set(.waiting, for: allIDs)
            } else if state.unresolvedEndingCount > 0 {
                feedback.globalReason = .endingReview
            } else if isIdle, state.unresolvedBarlineCount > 0 {
                feedback.globalReason = .placementUnavailable
            }
        }
        if (isIdle || !matureStructuralIDs.isEmpty), let structural = prepareIndependentStructuralOutcome(chart: chart, state: state,
            currentDrawing: currentDrawing, coordinateSpace: coordinateSpace, now: now,
            usesAutomaticPositioning: true, sourceLayout: sourceLayout, sourceFrame: sourceFrame,
            eligibleStructuralIDs: isIdle ? nil : matureStructuralIDs,
            includesCompletedPrecedingChords: true) {
            return structural
        }
        return prepareIndependentOutcome(chart: chart, state: state, currentDrawing: currentDrawing,
            coordinateSpace: coordinateSpace, now: now, isIdle: isIdle, usesAutomaticPositioning: true,
            sourceLayout: sourceLayout, sourceFrame: sourceFrame,
            isEligible: { ChordInkAutomaticRenderPolicy.automaticCandidateText(for: $0) != nil },
            feedback: &feedback)
    }

    /// Potential actions for the toolbar. The live transaction still checks
    /// source ownership, structural placement, and retained page geometry.
    static func independentlyRenderableStructuralIDs(in state: ChordPreviewState) -> Set<UUID> {
        structuralSelections(in: state).reduce(into: Set<UUID>()) { $0.formUnion($1) }
    }

    private static func structuralSelections(in state: ChordPreviewState) -> [Set<UUID>] {
        let plain = state.draftBarlines.filter(\.isRenderable)
        let barlineIDs = Set(plain.map(\.id))
        // Reviewed ending ordinals belong to their complete original split
        // plan. Selecting every barline keeps that plan intact.
        let endings = Set(state.draftBarlines.map(\.id)).isSubset(of: barlineIDs)
            ? state.draftEndings.filter(\.isRenderable) : []
        let all = barlineIDs.union(endings.map(\.id))
        guard !all.isEmpty else { return [] }
        var selections = [all]
        selections.append(contentsOf: plain.map { Set([$0.id]) })
        if state.draftBarlines.isEmpty {
            selections.append(contentsOf: endings.map { Set([$0.id]) })
        }
        var seen = Set<Set<UUID>>()
        return selections.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func prepareIndependentStructuralOutcome(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?, now: Date, usesAutomaticPositioning: Bool,
        sourceLayout: LeadSheetPageLayout, sourceFrame: CGRect,
        eligibleStructuralIDs: Set<UUID>? = nil, includesCompletedPrecedingChords: Bool = false
    ) -> AutomaticOutcome? {
        let selections = structuralSelections(in: state).filter { selection in
            eligibleStructuralIDs.map { selection.isSubset(of: $0) } ?? true
        }
        guard !selections.isEmpty, !currentDrawing.strokes.isEmpty else { return nil }
        var liveChart = chart
        let serialization = LeadSheetPersistentInkColorPolicy.serialization(for: currentDrawing)
        _ = liveChart.setPageHandwrittenChordDrawing(serialization.drawingData,
            coordinateSpace: coordinateSpace, assumesNormalizedPersistentInk: true)
        guard ChordInkDraftSourceCoveragePolicy.hasValidRepresentedCoverage(chart: liveChart, state: state) else { return nil }
        var rejectedStructuralIDs = Set<UUID>()
        for selection in selections where selection.isDisjoint(with: rejectedStructuralIDs) {
            let barlines = state.draftBarlines.filter { selection.contains($0.id) }
            let endings = state.draftEndings.filter { selection.contains($0.id) }
            let indices = barlines.reduce(into: Set<Int>()) { $0.formUnion($1.ownedSourceStrokeIndices) }
                .union(endings.reduce(into: Set<Int>()) { $0.formUnion($1.sourceStrokeIndices) })
            guard !indices.isEmpty, indices.allSatisfy(currentDrawing.strokes.indices.contains) else { continue }
            var plans: [([ChordInkDraft], Set<Int>)] = []
            if includesCompletedPrecedingChords {
                // The split and its completed left-hand chords may need one
                // transaction. Later/unfinished chords remain exact source.
                let precedes = barlines.map(\.visualOrder).min()
                let measureIDs = Set(barlines.map(\.measureID))
                let drafts = state.draftChords.filter { draft in
                    guard measureIDs.contains(draft.measureID),
                          let precedes, let order = draft.visualOrder ?? draft.laneLocation?.visualOrder,
                          order < precedes,
                          ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft) != nil,
                          ChordInkDraftLocalRewritePolicy.plan(for: draft, in: state, source: currentDrawing) != nil
                    else { return false }
                    return true
                }
                let combined = drafts.reduce(into: indices) { selected, draft in
                    if let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, in: state, source: currentDrawing) {
                        selected.formUnion(plan.originalStrokeIndices)
                    }
                }
                if !drafts.isEmpty { plans.append((drafts, combined)) }
            }
            plans.append(([], indices))
            for (selectedDrafts, selectedIndices) in plans {
                let isolated = usesAutomaticPositioning
                    ? isIndependentFromOtherWriting(indices: selectedIndices, source: currentDrawing,
                        pageSize: state.layoutPageSize, layout: sourceLayout, sourceFrame: sourceFrame,
                        requiresLaterInk: false)
                    : (ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: selectedIndices,
                        source: currentDrawing, pageSize: state.layoutPageSize, requiresLaterInk: false)
                        || isOnSeparateWritingRow(indices: selectedIndices, source: currentDrawing,
                            layout: sourceLayout, sourceFrame: sourceFrame))
                guard isolated else { continue }
                var failure = ChordInkAutomaticRenderReason.placementUnavailable
                if let outcome = preparePartial(chart: chart, state: state, currentDrawing: currentDrawing,
                    coordinateSpace: coordinateSpace, now: now, selectedDrafts: selectedDrafts, selectedIndices: selectedIndices,
                    usesAutomaticPositioning: usesAutomaticPositioning, selectedBarlines: barlines,
                    selectedEndings: endings, sourceLayout: sourceLayout, sourceFrame: sourceFrame,
                    failureReason: &failure, onRejectedResult: { result in
                        rejectedStructuralIDs.formUnion(result.unresolvedDraftIDs)
                    }) { return outcome }
            }
        }
        return nil
    }

    private static func prepareIndependentOutcome(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?, now: Date, isIdle: Bool,
        usesAutomaticPositioning: Bool, sourceLayout: LeadSheetPageLayout, sourceFrame: CGRect,
        isEligible: (ChordInkDraft) -> Bool, feedback: inout ChordInkAutomaticRenderFeedback
    ) -> AutomaticOutcome? {
        guard !currentDrawing.strokes.isEmpty, state.draftChords.contains(where: isEligible) else { return nil }
        // Every represented target must still claim its exact live source
        // once. Other fragments stay in the retained drawing; the spacing
        // and geometry checks below keep that writing independent of this
        // selection. Bind claims to live ink rather than older saved bytes.
        let liveSerialization = LeadSheetPersistentInkColorPolicy.serialization(for: currentDrawing)
        var liveSourceChart = chart
        _ = liveSourceChart.setPageHandwrittenChordDrawing(
            liveSerialization.drawingData, coordinateSpace: coordinateSpace,
            assumesNormalizedPersistentInk: true)
        guard ChordInkDraftSourceCoveragePolicy.hasValidRepresentedCoverage(chart: liveSourceChart, state: state) else {
            let invalidIDs = Set(state.draftChords.filter {
                ChordInkDraftLocalRewritePolicy.plan(for: $0, in: state, source: currentDrawing) == nil
            }.map(\.id))
            if invalidIDs.isEmpty { feedback.globalReason = .unrepresentedInk }
            else { feedback.set(.needsSourceRefresh, for: invalidIDs); feedback.globalReason = .needsSourceRefresh }
            return nil
        }
        guard let blockedMeasures = retainedStructureMeasureIDs(chart: chart, state: state,
            drawing: currentDrawing, layout: sourceLayout, sourceFrame: sourceFrame) else { return nil }
        var selectedDrafts: [ChordInkDraft] = []
        var selectedIndices = Set<Int>()
        var candidatePlans: [(ChordInkDraft, Set<Int>)] = []
        for draft in state.draftChords where isEligible(draft) {
            guard !blockedMeasures.contains(draft.measureID) else {
                feedback.reasonsByDraftID[draft.id] = isIdle ? .placementUnavailable : .waiting
                continue
            }
            if !blockedMeasures.isEmpty,
               !sourceLayout.systems.flatMap(\.measures).contains(where: { $0.sourceMeasureID == draft.measureID }) {
                continue
            }
            guard let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, in: state, source: currentDrawing),
                  selectedIndices.isDisjoint(with: plan.originalStrokeIndices) else {
                feedback.reasonsByDraftID[draft.id] = .needsSourceRefresh
                continue
            }
            let isolated = usesAutomaticPositioning
                ? isIndependentFromOtherWriting(indices: plan.originalStrokeIndices,
                    source: currentDrawing, pageSize: state.layoutPageSize,
                    layout: sourceLayout, sourceFrame: sourceFrame, requiresLaterInk: !isIdle)
                : (ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: plan.originalStrokeIndices,
                    source: currentDrawing, pageSize: state.layoutPageSize, requiresLaterInk: !isIdle)
                    || (isIdle && isOnSeparateWritingRow(indices: plan.originalStrokeIndices,
                        source: currentDrawing, layout: sourceLayout, sourceFrame: sourceFrame)))
            guard isolated else {
                if isIdle { feedback.reasonsByDraftID[draft.id] = .adjacentWriting }
                continue
            }
            selectedDrafts.append(draft)
            selectedIndices.formUnion(plan.originalStrokeIndices)
            candidatePlans.append((draft, plan.originalStrokeIndices))
        }
        guard !selectedDrafts.isEmpty else { return nil }
        var combinedFailure = ChordInkAutomaticRenderReason.placementUnavailable
        if let combined = preparePartial(chart: chart, state: state,
            currentDrawing: currentDrawing, coordinateSpace: coordinateSpace, now: now,
            selectedDrafts: selectedDrafts, selectedIndices: selectedIndices, usesAutomaticPositioning: usesAutomaticPositioning,
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
                if let single = preparePartial(chart: chart, state: state,
                    currentDrawing: currentDrawing, coordinateSpace: coordinateSpace, now: now,
                    selectedDrafts: [draft], selectedIndices: indices, usesAutomaticPositioning: usesAutomaticPositioning,
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
        var committed = state
        committed.markRenderableDraftsCommitted()
        guard let sourceLayout = sourcePageLayout ?? state.layoutPageSize.map({
            LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: $0, includesChordInkContinuationLanes: true)
        }) else { feedback.set(.placementUnavailable, for: ids); return .init(feedback: feedback) }
        let frame = sourceChordFrame ?? LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        func independentAttempt() -> AutomaticAttempt {
            let partial = prepareIndependentStructuralOutcome(chart: chart, state: state,
                currentDrawing: currentDrawing, coordinateSpace: coordinateSpace, now: .now,
                usesAutomaticPositioning: true, sourceLayout: sourceLayout, sourceFrame: frame)
                ?? prepareIndependentOutcome(chart: chart, state: state, currentDrawing: currentDrawing,
                    coordinateSpace: coordinateSpace, now: .now, isIdle: true, usesAutomaticPositioning: true,
                    sourceLayout: sourceLayout, sourceFrame: frame,
                    isEligible: explicitlyRenderable, feedback: &feedback)
            if let partial {
                feedback = feedback.retainingDraftIDs(Set(partial.remainingState.draftChords.map(\.id)),
                    keepsGlobalReason: !partial.drawing.strokes.isEmpty)
            }
            return .init(outcome: partial, feedback: feedback)
        }
        let prepared = prepare(chart: chart, state: committed, currentDrawing: currentDrawing,
            coordinateSpace: coordinateSpace, automaticContinuationSourceLayout: sourceLayout)
        guard prepared.canConsumeSource else {
            if prepared.result.hasUnplacedPlainBarline(in: committed) {
                feedback.globalReason = .barlinePlacementUnavailable
            } else {
                feedback.set(prepared.result.didRejectIncompleteSourceCoverage ? .needsSourceRefresh : .placementUnavailable, for: ids)
            }
            return independentAttempt()
        }
        var refusal = ChordInkAutomaticRenderReason.placementUnavailable
        guard let positioned = automaticallyPositionedChart(originalChart: chart,
            preparedChart: prepared.chart, state: committed, result: prepared.result,
            remainingDrawing: PKDrawing(), sourceLayout: sourceLayout, sourceFrame: frame,
            failureReason: &refusal) else {
            feedback.set(refusal, for: ids)
            return independentAttempt()
        }
        return .init(outcome: AutomaticOutcome(chart: positioned, drawing: PKDrawing(),
            remainingState: ChordPreviewState(), result: prepared.result,
            consumedDraftIDs: Set(state.draftChords.map(\.id) + state.draftBarlines.map(\.id) + state.draftEndings.map(\.id))), feedback: .init())
    }

    private static func preparePartial(
        chart: Chart, state: ChordPreviewState, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?, now: Date,
        selectedDrafts: [ChordInkDraft], selectedIndices: Set<Int>, usesAutomaticPositioning: Bool,
        selectedBarlines: [DraftBarline] = [], selectedEndings: [DraftEnding] = [],
        sourceLayout: LeadSheetPageLayout, sourceFrame: CGRect,
        failureReason: inout ChordInkAutomaticRenderReason,
        onRejectedResult: ((ChordInkDraftBatchRenderResult) -> Void)? = nil
    ) -> AutomaticOutcome? {
        let consumedIDs = Set(selectedDrafts.map(\.id) + selectedBarlines.map(\.id) + selectedEndings.map(\.id))
        let retainedChords = state.draftChords.filter { !consumedIDs.contains($0.id) }
        let selectedMeasureIDs = Set(selectedDrafts.map(\.measureID) + selectedBarlines.map(\.measureID)
            + selectedEndings.flatMap { [$0.start.measureID, $0.end.measureID] })
        guard unrepresentedInkIsIndependent(of: selectedMeasureIDs, state: state, drawing: currentDrawing,
            layout: sourceLayout, sourceFrame: sourceFrame) else {
            failureReason = .unrepresentedInk
            return nil
        }
        // An earlier retained chord in an empty rhythm measure must keep its
        // opportunity to claim beat one. An independent later measure may
        // still render, or a selected chord to the left can render first.
        if chart.layoutStyle == .rhythmSectionSheet,
           selectedDrafts.contains(where: { draft in
               chart.measure(id: draft.measureID)?.chordEvents.isEmpty == true
                   && retainedChords.contains(where: { retained in
                       guard retained.measureID == draft.measureID else { return false }
                       guard let retainedFraction = retained.targetFraction,
                             let selectedFraction = draft.targetFraction else { return true }
                       return retainedFraction <= selectedFraction
                   })
           }) { return nil }
        let selectedSource = PKDrawing(strokes: currentDrawing.strokes.enumerated().compactMap { index, stroke in
            selectedIndices.contains(index) ? stroke : nil
        })
        let remaining = PKDrawing(strokes: currentDrawing.strokes.enumerated().compactMap { index, stroke in
            selectedIndices.contains(index) ? nil : stroke
        })
        let withheldIndices = Set(currentDrawing.strokes.indices).subtracting(selectedIndices)
        let remappedBarlines = ChordDraftBarlineDeletionPolicy.remappingSourceIndices(
            selectedBarlines, afterRemoving: withheldIndices)
        let remappedEndings = ChordDraftEndingPresentationPolicy.remappingSourceIndices(
            selectedEndings, afterRemoving: withheldIndices)
        guard remappedBarlines.count == selectedBarlines.count,
              remappedEndings.count == selectedEndings.count else { return nil }
        var selectedState = ChordPreviewState(draftChords: selectedDrafts,
            draftBarlines: remappedBarlines, draftEndings: remappedEndings, layoutPageSize: state.layoutPageSize)
        selectedState.markRenderableDraftsCommitted(updatedAt: now)
        if !selectedEndings.isEmpty {
            var liveChart = chart
            _ = liveChart.setPageHandwrittenChordDrawing(currentDrawing.dataRepresentation(), coordinateSpace: coordinateSpace)
            guard selectedEndings.allSatisfy({ $0.reviewedRangeContext?.matches(chart: liveChart, state: state) == true })
                else { return nil }
            var selectedChart = chart
            _ = selectedChart.setPageHandwrittenChordDrawing(selectedSource.dataRepresentation(), coordinateSpace: coordinateSpace)
            guard let context = ChordDraftEndingRangeReviewContext.capture(chart: selectedChart, state: selectedState)
                else { return nil }
            for index in selectedState.draftEndings.indices {
                selectedState.draftEndings[index].reviewedRangeContext = context
            }
        }
        let prepared = prepare(chart: chart, state: selectedState,
            currentDrawing: selectedSource, coordinateSpace: coordinateSpace,
            automaticContinuationSourceLayout: usesAutomaticPositioning ? sourceLayout : nil)
        guard prepared.canConsumeSource else {
            onRejectedResult?(prepared.result)
            failureReason = prepared.result.didRejectIncompleteSourceCoverage ? .needsSourceRefresh : .placementUnavailable
            return nil
        }

        let serialization = LeadSheetPersistentInkColorPolicy.serialization(for: remaining)
        var updatedChart = prepared.chart
        _ = updatedChart.setPageHandwrittenChordDrawing(
            remaining.strokes.isEmpty ? nil : serialization.drawingData,
            coordinateSpace: remaining.strokes.isEmpty ? nil : coordinateSpace,
            assumesNormalizedPersistentInk: true)
        if usesAutomaticPositioning {
            guard let positioned = automaticallyPositionedChart(originalChart: chart,
                preparedChart: updatedChart, state: selectedState, result: prepared.result,
                remainingDrawing: remaining, sourceLayout: sourceLayout, sourceFrame: sourceFrame,
                failureReason: &failureReason) else { return nil }
            updatedChart = positioned
        }
        var remainingState = state
        remainingState.draftChords = retainedChords
        remainingState.draftBarlines.removeAll { consumedIDs.contains($0.id) }
        remainingState.draftEndings.removeAll { consumedIDs.contains($0.id) }
        if !remaining.strokes.isEmpty {
            let destination = LeadSheetPageLayoutEngine.pageLayout(for: updatedChart,
                pageSize: sourceLayout.pageBounds.size, includesChordInkContinuationLanes: true)
            let sourceRegion = LeadSheetActiveInkScope.chordWritingRegion(for: sourceLayout)
            let destinationRegion = LeadSheetActiveInkScope.chordWritingRegion(for: destination)
            guard sourceRegion == destinationRegion,
                  retainsUnrepresentedInkGeometry(state: state, drawing: currentDrawing,
                    source: sourceLayout, destination: destination, sourceFrame: sourceFrame) else {
                failureReason = .needsSourceRefresh
                return nil
            }
            if !retainsMeasureGeometry(in: remainingState, source: sourceLayout, destination: destination) {
                // A divider keeps the original measure ID on its left. Ink
                // on the right needs a fresh canonical target, even though its
                // physical writing lane and exact strokes have not moved.
                guard usesAutomaticPositioning, !selectedBarlines.isEmpty, selectedEndings.isEmpty,
                      let reanchored = ChordInkRetainedSplitReanchorPolicy.reanchored(
                        state: remainingState, drawing: remaining, originalLayout: sourceLayout,
                        destinationLayout: destination, sourceFrame: sourceFrame, layoutStyle: chart.layoutStyle)
                else { failureReason = .needsSourceRefresh; return nil }
                remainingState = reanchored
            }
            for index in remainingState.draftChords.indices {
                guard let measure = destination.systems.flatMap(\.measures).first(where: {
                    $0.chordInkTargetMeasureID == remainingState.draftChords[index].measureID
                }) else { failureReason = .needsSourceRefresh; return nil }
                remainingState.draftChords[index].measureIndex = measure.index
            }
            guard rebaseRetainedStructuralDrafts(&remainingState, removing: selectedIndices,
                    drawing: remaining, layout: destination, sourceFrame: sourceFrame) else {
                failureReason = .needsSourceRefresh
                return nil
            }
            preserveIndependentEndingApprovals(in: &remainingState, originalState: state,
                originalChart: chart, updatedChart: updatedChart, originalDrawing: currentDrawing,
                coordinateSpace: coordinateSpace)
            guard ChordInkDraftSourceCoveragePolicy.hasValidRepresentedCoverage(chart: updatedChart, state: remainingState) else {
                failureReason = .needsSourceRefresh
                return nil
            }
            if !usesAutomaticPositioning,
               !validateGlyphPlacement(result: prepared.result, remainingDrawing: remaining,
                    sourceLayout: sourceLayout, finalLayout: destination, sourceFrame: sourceFrame,
                    failureReason: &failureReason) { return nil }
        }
        remainingState.updatedAt = now
        return AutomaticOutcome(chart: updatedChart, drawing: remaining,
            remainingState: remainingState, result: prepared.result, consumedDraftIDs: consumedIDs)
    }


    /// Structural changes stay pending. A chord outside those measures can
    /// render only if its commit leaves every retained writing lane in place.
    private static func retainedStructureMeasureIDs(
        chart: Chart, state: ChordPreviewState, drawing: PKDrawing,
        layout: LeadSheetPageLayout, sourceFrame: CGRect
    ) -> Set<UUID>? {
        let measureIDs = chart.measures.map(\.id)
        var blocked = Set<UUID>()
        for barline in state.draftBarlines {
            let indices = barline.ownedSourceStrokeIndices
            guard let lane = barline.laneLocation,
                  let system = layout.systems.first(where: { $0.index == lane.systemIndex }),
                  !indices.isEmpty, indices.allSatisfy(drawing.strokes.indices.contains) else { return nil }
            // A plain one-stroke divider only carries an original index.
            // The live ownership check above verifies it before use here.
            let frames = indices.flatMap { PencilKitInkAdapter.visibleStrokeFragments(from: drawing.strokes[$0]) }
                .map(\.renderBounds)
            guard frames.count == indices.count,
                  frames.allSatisfy({ $0.minX.isFinite && $0.maxX.isFinite }) else { return nil }
            let bounds = frames.reduce(CGRect.null) { $0.union($1) }
            let minX = bounds.minX + sourceFrame.minX
            let maxX = bounds.maxX + sourceFrame.minX
            let touchedMeasures = system.measures.filter { measure in
                measure.frame.maxX + 2 >= minX && measure.frame.minX - 2 <= maxX
            }.compactMap(\.sourceMeasureID)
            // A row-end mark or a synthetic continuation can create a new
            // measure. Without a real source measure the dependency is unknown.
            guard touchedMeasures.contains(barline.measureID) else { return nil }
            blocked.formUnion(touchedMeasures)
        }
        for ending in state.draftEndings {
            if let range = ending.reviewedMeasureRange {
                guard range.lowerBound > 0, range.upperBound <= measureIDs.count else { return nil }
                blocked.formUnion(measureIDs[(range.lowerBound - 1)..<range.upperBound])
            }
            guard let start = measureIDs.firstIndex(of: ending.start.measureID),
                  let end = measureIDs.firstIndex(of: ending.end.measureID) else { return nil }
            blocked.formUnion(measureIDs[min(start, end)...max(start, end)])
        }
        return blocked
    }

    /// Each retained fragment needs either the normal horizontal word gap
    /// or a different verified writing row. Mixing those two kinds of safe
    /// neighbors must not make an older completed chord wait for global idle.
    private static func isIndependentFromOtherWriting(
        indices: Set<Int>, source: PKDrawing, pageSize: CGSize?,
        layout: LeadSheetPageLayout, sourceFrame: CGRect, requiresLaterInk: Bool
    ) -> Bool {
        if ChordInkAutomaticRenderPolicy.isSpatiallyIsolated(originalStrokeIndices: indices,
            source: source, pageSize: pageSize, requiresLaterInk: requiresLaterInk) { return true }
        guard !indices.isEmpty, indices.allSatisfy(source.strokes.indices.contains) else { return false }
        var visible: [(index: Int, bounds: CGRect)] = []
        for (index, stroke) in source.strokes.enumerated() {
            for fragment in PencilKitInkAdapter.visibleStrokeFragments(from: stroke) {
                let bounds = fragment.renderBounds.standardized
                    .offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
                guard !bounds.isNull, !bounds.isInfinite,
                      bounds.minX.isFinite, bounds.minY.isFinite,
                      bounds.maxX.isFinite, bounds.maxY.isFinite else { return false }
                visible.append((index, bounds))
            }
        }
        guard let newestIndex = visible.last?.index,
              !requiresLaterInk || !indices.contains(newestIndex) else { return false }
        let owned = visible.filter { indices.contains($0.index) }
        let other = visible.filter { !indices.contains($0.index) }
        guard !owned.isEmpty, !other.isEmpty else { return false }
        let rows = LeadSheetActiveInkScope.chordWritingRegion(for: layout).inputFrames
        guard let row = rows.first(where: { frame in owned.allSatisfy { frame.contains($0.bounds) } }) else { return false }
        let ownedBounds = owned.reduce(CGRect.null) { $0.union($1.bounds) }
        let pageScale = pageSize.map { $0.width.isFinite && $0.width > 0 ? $0.width / 900 : 1 } ?? 1
        let requiredGap = ChordInkAutomaticRenderPolicy.minimumChordGap * pageScale
        return other.allSatisfy { fragment in
            let bounds = fragment.bounds
            let horizontalGap = max(bounds.minX - ownedBounds.maxX, ownedBounds.minX - bounds.maxX)
            return horizontalGap >= requiredGap
                || (!row.intersects(bounds) && rows.contains(where: { $0.contains(bounds) }))
        }
    }

    private static func isOnSeparateWritingRow(
        indices: Set<Int>, source: PKDrawing, layout: LeadSheetPageLayout, sourceFrame: CGRect
    ) -> Bool {
        let rows = LeadSheetActiveInkScope.chordWritingRegion(for: layout).inputFrames
        let pageBounds = source.strokes.map { $0.renderBounds.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY) }
        let owned = indices.sorted().map { pageBounds[$0] }
        let other = pageBounds.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
        guard let row = rows.first(where: { frame in owned.allSatisfy(frame.contains) }), !other.isEmpty else { return false }
        return other.allSatisfy { bounds in
            !row.intersects(bounds) && rows.contains(where: { $0.contains(bounds) })
        }
    }

    private static func retainsMeasureGeometry(
        in state: ChordPreviewState, source: LeadSheetPageLayout, destination: LeadSheetPageLayout
    ) -> Bool {
        let retainedIDs = Set(state.draftChords.map(\.measureID) + state.draftBarlines.map(\.measureID)
            + state.draftEndings.flatMap { [$0.start.measureID, $0.end.measureID] })
        func measures(_ layout: LeadSheetPageLayout, id: UUID) -> [LeadSheetMeasureLayout] {
            layout.systems.flatMap(\.measures).filter { $0.chordInkTargetMeasureID == id }
        }
        return retainedIDs.allSatisfy { id in
            let before = measures(source, id: id)
            let after = measures(destination, id: id)
            return !before.isEmpty && before.count == after.count
                && zip(before, after).allSatisfy { prior, current in
                    prior.sourceMeasureID == current.sourceMeasureID
                        && prior.chordWritingFrame == current.chordWritingFrame && prior.staffFrame == current.staffFrame
                }
        }
    }

    private static func unrepresentedInkIsIndependent(
        of selectedMeasureIDs: Set<UUID>, state: ChordPreviewState, drawing: PKDrawing,
        layout: LeadSheetPageLayout, sourceFrame: CGRect
    ) -> Bool {
        let represented = representedSourceIndices(state: state, drawing: drawing)
        let measures = layout.systems.flatMap(\.measures)
        let rows = LeadSheetActiveInkScope.chordWritingRegion(for: layout).inputFrames
        let selectedRows = layout.systems.filter { system in
            system.measures.contains { measure in
                measure.sourceMeasureID.map(selectedMeasureIDs.contains) == true
                    || measure.chordInkTargetMeasureID.map(selectedMeasureIDs.contains) == true
            }
        }.compactMap { system in
            LeadSheetActiveInkScope.chordWritingSystemInputFrame(for: system, paperFrame: layout.paperFrame(for: system))
        }
        return drawing.strokes.enumerated().filter { !represented.contains($0.offset) }.allSatisfy { indexed in
            PencilKitInkAdapter.visibleStrokeFragments(from: indexed.element).allSatisfy { fragment in
                let bounds = fragment.renderBounds.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
                let owners = measures.filter { $0.chordWritingFrame.contains(bounds) }
                if owners.count == 1, let owner = owners.first,
                   let id = owner.sourceMeasureID ?? owner.chordInkTargetMeasureID {
                    return !selectedMeasureIDs.contains(id)
                }
                let containingRows = rows.filter { $0.contains(bounds) }
                return containingRows.count == 1 && !selectedRows.contains(containingRows[0])
            }
        }
    }

    private static func representedSourceIndices(state: ChordPreviewState, drawing: PKDrawing) -> Set<Int> {
        var represented = Set<Int>()
        for draft in state.draftChords {
            if let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, in: state, source: drawing) {
                represented.formUnion(plan.originalStrokeIndices)
            }
        }
        for barline in state.draftBarlines { represented.formUnion(barline.ownedSourceStrokeIndices) }
        for ending in state.draftEndings { represented.formUnion(ending.sourceStrokeIndices) }
        return represented
    }

    private static func retainsUnrepresentedInkGeometry(
        state: ChordPreviewState, drawing: PKDrawing,
        source: LeadSheetPageLayout, destination: LeadSheetPageLayout, sourceFrame: CGRect
    ) -> Bool {
        let represented = representedSourceIndices(state: state, drawing: drawing)
        let unknown = drawing.strokes.enumerated().filter { !represented.contains($0.offset) }
        let beforeMeasures = source.systems.flatMap(\.measures)
        let afterMeasures = destination.systems.flatMap(\.measures)
        return unknown.allSatisfy { indexed in
            let frames = PencilKitInkAdapter.visibleStrokeFragments(from: indexed.element).map {
                $0.renderBounds.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
            }
            return frames.allSatisfy { bounds in
                let owners = beforeMeasures.filter { $0.chordWritingFrame.contains(bounds) }
                guard owners.count == 1, let owner = owners.first, let id = owner.sourceMeasureID else {
                    // Ink outside every writing lane stays in the same canvas
                    // coordinates. A boundary-touching owner remains ambiguous.
                    return !LeadSheetActiveInkScope.chordWritingRegion(for: source).inputFrames.contains {
                        $0.intersects(bounds)
                    }
                }
                let matches = afterMeasures.filter { $0.sourceMeasureID == id }
                return matches.count == 1 && matches[0].chordWritingFrame == owner.chordWritingFrame
                    && matches[0].staffFrame == owner.staffFrame
            }
        }
    }

    private static func preserveIndependentEndingApprovals(
        in remainingState: inout ChordPreviewState, originalState: ChordPreviewState,
        originalChart: Chart, updatedChart: Chart, originalDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?
    ) {
        // A chord-only commit may change the chart and source snapshot while
        // leaving the reviewed measure range and every structural mark intact.
        guard originalChart.measures.map(\.id) == updatedChart.measures.map(\.id),
              Set(originalState.draftBarlines.map(\.id)) == Set(remainingState.draftBarlines.map(\.id)) else { return }
        var liveOriginal = originalChart
        _ = liveOriginal.setPageHandwrittenChordDrawing(originalDrawing.dataRepresentation(), coordinateSpace: coordinateSpace)
        let approved = originalState.draftEndings.filter {
            $0.isReviewed && $0.reviewedMeasureRange != nil
                && $0.reviewedRangeContext?.matches(chart: liveOriginal, state: originalState) == true
        }
        guard !approved.isEmpty else { return }
        var preservedIDs = Set<UUID>()
        for index in remainingState.draftEndings.indices {
            guard let prior = approved.first(where: { $0.id == remainingState.draftEndings[index].id }),
                  sameEndpointPlacement(prior.start, remainingState.draftEndings[index].start),
                  sameEndpointPlacement(prior.end, remainingState.draftEndings[index].end) else { continue }
            remainingState.draftEndings[index].isReviewed = true
            remainingState.draftEndings[index].reviewedSourceInkData = prior.reviewedSourceInkData
            remainingState.draftEndings[index].reviewedMeasureRange = prior.reviewedMeasureRange
            preservedIDs.insert(prior.id)
        }
        guard let context = ChordDraftEndingRangeReviewContext.capture(chart: updatedChart, state: remainingState)
            else { return }
        for index in remainingState.draftEndings.indices where preservedIDs.contains(remainingState.draftEndings[index].id) {
            remainingState.draftEndings[index].reviewedRangeContext = context
        }
    }

    private static func sameEndpointPlacement(_ first: DraftEndingEndpoint, _ second: DraftEndingEndpoint) -> Bool {
        first.measureID == second.measureID && first.fraction == second.fraction
            && first.laneLocation == second.laneLocation
    }

    private static func rebaseRetainedStructuralDrafts(
        _ state: inout ChordPreviewState, removing consumed: Set<Int>,
        drawing: PKDrawing, layout: LeadSheetPageLayout, sourceFrame: CGRect
    ) -> Bool {
        guard !state.draftBarlines.isEmpty || !state.draftEndings.isEmpty else { return true }
        let context = ChordInkDraftVisibleStrokePolicy.structuralVisibleDrawingContext(
            from: drawing, chordFrame: sourceFrame, pageLayout: layout)
        let strokes = PencilKitInkAdapter.inkStrokes(from: context.drawing)
        let structures = ChordDraftEndingRecognizer.recognizeStructure(
            strokes: strokes, chordFrame: sourceFrame, pageLayout: layout)
        let barlines = structures.barlines
        let endings = structures.endings
        let detectedBarlines = context.remappedBarlineRecognition(
            context.barlineRecognitionWithUnambiguousSourceStrokes(barlines)).barlines
        let detectedEndings = context.remappedEndingRecognition(
            context.endingRecognitionWithUnambiguousSourceStrokes(endings)).endings
        let remappedBarlines = ChordDraftBarlineDeletionPolicy.remappingSourceIndices(
            state.draftBarlines, afterRemoving: consumed)
        let remappedEndings = ChordDraftEndingPresentationPolicy.remappingSourceIndices(
            state.draftEndings, afterRemoving: consumed)
        guard remappedBarlines.count == state.draftBarlines.count,
              remappedEndings.count == state.draftEndings.count else { return false }
        var updatedBarlines: [DraftBarline] = []
        for prior in remappedBarlines {
            let matches = detectedBarlines.filter {
                $0.ownedSourceStrokeIndices == prior.ownedSourceStrokeIndices && $0.measureID == prior.measureID
                    && $0.kind == prior.kind && $0.laneLocation == prior.laneLocation
                    && $0.fraction == prior.fraction && $0.metrics == prior.metrics
            }
            guard matches.count == 1, var detected = matches.first else { return false }
            detected.id = prior.id
            updatedBarlines.append(detected)
        }
        var updatedEndings: [DraftEnding] = []
        for prior in remappedEndings {
            let matches = detectedEndings.filter {
                $0.sourceStrokeIndices == prior.sourceStrokeIndices
                    && sameEndpointPlacement($0.start, prior.start) && sameEndpointPlacement($0.end, prior.end)
                    && $0.detectedEndStyle == prior.detectedEndStyle
            }
            guard matches.count == 1, var detected = matches.first else { return false }
            detected.id = prior.id
            // Keep a typed label, but an approval still belongs to its chart and source snapshot.
            detected.label = prior.label
            detected.endStyle = prior.endStyle
            updatedEndings.append(detected)
        }
        state.draftBarlines = updatedBarlines
        state.draftEndings = updatedEndings
        return true
    }

    /// Musical placement comes from the normal commit. Automatic rendering
    /// pins glyphs to their source when the commit did not anchor them to beat 1.
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
        // Preserve multi-chord positions using the new segment's actual band.
        // A lone chord deliberately anchored to its new downbeat must retain
        // that model decision instead of returning to its old paper position.
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
            if destinationMeasure.chordEvents.count == 1,
               let event = destinationMeasure.chordEvents.first,
               event.anchorsToMeasureStart, event.manualVisualLaneFraction == nil {
                continue
            }
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
            guard matches.count == 1, let index = matches.first else { return nil }
            let draft = unclaimedDrafts.remove(at: index)
            if event.anchorsToMeasureStart { continue }
            guard let drawing = try? PKDrawing(data: draft.drawingData),
                  let bounds = visibleInkFrames(drawing).reduce(nil as CGRect?, { union, frame in
                      union.map { $0.union(frame) } ?? frame
                  }) else { return nil }
            let sourceLeftPageX = bounds.minX + sourceFrame.minX
            // A later chord can use its beat guide when pinning it to the
            // handwriting would crowd the first chord on the downbeat.
            if let downbeat = destinationMeasure.chordEvents.first,
               downbeat.anchorsToMeasureStart,
               downbeat.manualVisualLaneFraction == nil,
               let glyph = destination.chordLayouts.first(where: { $0.id == downbeat.id }),
               sourceLeftPageX < max(glyph.frame.maxX, glyph.naturalFrame.maxX) + 2 {
                continue
            }
            let fraction = Double((sourceLeftPageX - destination.chordBandFrame.minX) / destination.chordBandFrame.width)
            guard fraction.isFinite,
                  positioned.moveChordEventInCommittedChordLane(eventID, to: destinationMeasure.id,
                    atFraction: nil, visualFraction: fraction, preserveMusicalPlacement: true) else { return nil }
        }

        let finalLayout = LeadSheetPageLayoutEngine.pageLayout(for: positioned,
            pageSize: sourceLayout.pageBounds.size, includesChordInkContinuationLanes: true)
        guard validateGlyphPlacement(result: result, remainingDrawing: remainingDrawing,
            sourceLayout: sourceLayout, finalLayout: finalLayout, sourceFrame: sourceFrame,
            failureReason: &failureReason) else { return nil }
        return positioned
    }

    private static func validateGlyphPlacement(
        result: ChordInkDraftBatchRenderResult, remainingDrawing: PKDrawing,
        sourceLayout: LeadSheetPageLayout, finalLayout: LeadSheetPageLayout, sourceFrame: CGRect,
        failureReason: inout ChordInkAutomaticRenderReason
    ) -> Bool {
        let beforeGlyphs = sourceLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
        let remainingFrames = visibleInkFrames(remainingDrawing).map {
            $0.offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
        }
        if !remainingFrames.isEmpty {
            // Changing the live canvas region may reproject retained source.
            // Do not guess its prospective location during this transaction.
            let finalSourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: finalLayout)
            guard sameFrame(sourceFrame, finalSourceFrame) else { failureReason = .needsSourceRefresh; return false }
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
            guard !remainingFrames.contains(where: { overlaps(frame, $0) }) else { failureReason = .needsSpace; return false }
            if isNew {
                guard !afterGlyphs.contains(where: { other in
                    other.id != glyph.id && overlaps(frame, other.naturalFrame.union(other.frame))
                }) else { failureReason = .needsSpace; return false }
            }
        }
        return true
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

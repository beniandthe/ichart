#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkAutomaticFeedbackTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_200)
    private let now = Date(timeIntervalSinceReferenceDate: 100)

    func testCollectingTargetBecomesRenderingForSupportedUncertainReadWithoutOpeningReview() throws {
        let chart = makeChart()
        var draft = makeDraft(chart, text: nil, trusted: false)
        draft.targetLifecycle?.stage = .collecting
        XCTAssertEqual(ChordInkAutomaticFeedbackPolicy.recognitionReason(for: draft), .reading)
        let reading = activity(chart, phase: .reading, pending: 1, age: 0.3)
        let pendingStatus = try XCTUnwrap(status(draft, activity: reading))
        XCTAssertTrue(pendingStatus.isReading)
        XCTAssertFalse(pendingStatus.canReview)

        let uncertain = makeDraft(chart, text: "Bb", trusted: false)
        XCTAssertTrue(uncertain.isRenderable, "Supported text is distinct from a trusted automatic decision")
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(uncertain))
        XCTAssertEqual(ChordInkAutomaticFeedbackPolicy.recognitionReason(for: uncertain), .recognitionReview)
        let settled = activity(chart, phase: .settled, age: 2)
        let result = try XCTUnwrap(status(uncertain, activity: settled))
        XCTAssertTrue(result.isReading)
        XCTAssertFalse(result.canReview)
        XCTAssertEqual(result.title, "Rendering Bb…")
        XCTAssertEqual(result.accessibilityLabel, "Rendering Bb")
    }

    func testCompletedNoReadOffersFixActionAndDoesNotRemainReading() throws {
        let chart = makeChart()
        let draft = makeDraft(chart, text: nil, trusted: false)
        XCTAssertFalse(draft.isRenderable)
        XCTAssertEqual(ChordInkAutomaticFeedbackPolicy.recognitionReason(for: draft), .noRead)
        let result = try XCTUnwrap(status(draft, activity: activity(chart, phase: .settled, age: 2)))
        XCTAssertFalse(result.isReading)
        XCTAssertTrue(result.canReview)
        XCTAssertEqual(result.accessibilityLabel, "No supported read. Fix writing")
    }

    func testSupportedScoreAndRawEvidenceUsesAutomaticCandidateFeedbackWithoutPromotingTrust() {
        let chart = makeChart()
        for scored in [true, false] {
            var draft = makeDraft(chart, text: nil, trusted: false)
            draft.recognitionResult = .init(rawCandidates: scored ? ["unreadable"] : ["unreadable", "D/F#"],
                glyphCandidates: [], match: nil, confidence: 0,
                candidateScores: scored ? [.init(text: "D/F#", displayText: "D/F#", confidence: 0.01)] : [])
            let original = draft
            XCTAssertFalse(draft.isRenderable)
            XCTAssertEqual(ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft), "D/F#")
            XCTAssertEqual(ChordInkAutomaticFeedbackPolicy.recognitionReason(for: draft), .recognitionReview)
            XCTAssertEqual(draft, original)
            XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(draft))
            XCTAssertNil(draft.selectedText)
        }
    }

    func testStructuralReviewRetainsSupportedCandidateAndSourceWithoutReportingAutomaticNoRead() throws {
        for scored in [true, false] {
            for ending in [true, false] {
                var chart = makeChart()
                let chordSource = PKDrawing(strokes: [stroke(106, width: 22, top: 48, bottom: 80, seed: 1)])
                let structuralSource = PKDrawing(strokes: [stroke(600, width: 0, top: 0, bottom: 90, seed: 2)])
                let source = PKDrawing(strokes: chordSource.strokes + structuralSource.strokes)
                _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation())
                var draft = makeDraft(chart, text: nil, trusted: false, drawing: chordSource)
                draft.recognitionResult = .init(rawCandidates: scored ? [] : ["D/F#"], glyphCandidates: [],
                    match: nil, confidence: 0,
                    candidateScores: scored ? [.init(text: "D/F#", displayText: "D/F#", confidence: 0.01)] : [])
                XCTAssertFalse(draft.isRenderable)
                var state = ChordPreviewState(draftChords: [draft], layoutPageSize: pageSize)
                if ending {
                    let start = DraftEndingEndpoint(measureID: chart.measures[0].id, measureIndex: 1,
                        fraction: 0.1, laneLocation: .init(systemIndex: 0, fraction: 0.1))
                    let end = DraftEndingEndpoint(measureID: chart.measures[0].id, measureIndex: 1,
                        fraction: 0.9, laneLocation: .init(systemIndex: 0, fraction: 0.9))
                    state.draftEndings = [DraftEnding(start: start, end: end, layoutPageSize: pageSize,
                        sourceStrokeIndices: [1],
                        sourceStrokeGeometry: PencilKitInkAdapter.inkStrokes(from: structuralSource),
                        endStyle: .closed)]
                } else {
                    state.draftBarlines = [DraftBarline(measureID: chart.measures[0].id, measureIndex: 1,
                        fraction: 0.9, sourceStrokeIndex: 1,
                        metrics: .init(height: 90, width: 0, angleDegreesFromVertical: 0,
                            straightness: 1, laneCoverage: 0.9), kind: .repeatEnd)]
                }
                let originalChart = chart
                let originalState = state
                let originalSource = source.dataRepresentation()
                let sourceLayout = layout(chart)
                let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
                let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
                    currentDrawing: source, coordinateSpace: .init(size: frame.size), now: now,
                    lastInputAt: now.addingTimeInterval(-4), isUsingTool: false,
                    sourcePageLayout: sourceLayout, sourceChordFrame: frame)
                XCTAssertNil(attempt.outcome)
                XCTAssertEqual(attempt.feedback.reasonsByDraftID[draft.id], .recognitionReview)
                XCTAssertEqual(attempt.feedback.globalReason, ending ? .endingReview : .repeatReview)
                XCTAssertNil(completion(chart, feedback: attempt.feedback, strokeCount: source.strokes.count))
                XCTAssertEqual(chart, originalChart)
                XCTAssertEqual(state, originalState)
                XCTAssertEqual(source.dataRepresentation(), originalSource)
            }
        }
    }

    func testBlockingStructuralReviewTakesPrecedenceOverAnUnrelatedExhaustedChordReason() {
        let chart = makeChart()
        let draft = makeDraft(chart, text: nil, trusted: false)
        XCTAssertNil(ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft))
        XCTAssertEqual(ChordInkAutomaticFeedbackPolicy.recognitionReason(for: draft), .noRead)
        for reason: ChordInkAutomaticRenderReason in [.endingReview, .repeatReview] {
            let feedback = ChordInkAutomaticRenderFeedback(reasonsByDraftID: [draft.id: .noRead],
                globalReason: reason)
            XCTAssertNil(completion(chart, feedback: feedback, strokeCount: 2))
        }
        let actualNoRead = completion(chart,
            feedback: .init(reasonsByDraftID: [draft.id: .noRead]), strokeCount: 1)
        XCTAssertEqual(actualNoRead?["reason"], .string("automatic_no_read"),
            "A genuinely exhausted current input still reports friction when structural review does not block it")
        XCTAssertEqual(actualNoRead?["retained_stroke_count"], .int(1))
    }

    func testStaleOrSourceRefreshFeedbackNeverPresentsTheOldChordAsACurrentRead() throws {
        let chart = makeChart()
        var stale = makeDraft(chart, text: "Bb", trusted: false)
        stale.isStale = true
        XCTAssertEqual(ChordInkAutomaticFeedbackPolicy.recognitionReason(for: stale), .needsSourceRefresh)
        let staleStatus = try XCTUnwrap(status(stale, activity: activity(chart, phase: .settled, age: 2)))
        XCTAssertTrue(staleStatus.canReview)
        XCTAssertFalse(staleStatus.accessibilityLabel.contains("Bb"))

        let old = makeDraft(chart, text: "Bb", trusted: false)
        let changed = ChordInkAutomaticRenderFeedback(reasonsByDraftID: [old.id: .needsSourceRefresh])
        let refreshed = try XCTUnwrap(status(old, activity: activity(chart, phase: .reading, pending: 1, age: 0.2),
            feedback: changed))
        XCTAssertFalse(refreshed.accessibilityLabel.contains("Bb"),
            "A previous read cannot survive current-source invalidation as a usable suggestion")
    }

    func testNewWaitingRevisionWithholdsBothOldTrustedAndOldUncertainText() throws {
        let chart = makeChart()
        let waiting = activity(chart, phase: .waiting, age: 0.4)
        for draft in [makeDraft(chart, text: "G", trusted: true), makeDraft(chart, text: "Bb", trusted: false)] {
            let result = try XCTUnwrap(status(draft, activity: waiting))
            XCTAssertTrue(result.isReading)
            XCTAssertFalse(result.canReview)
            XCTAssertEqual(result.accessibilityLabel, "Writing chord")
            XCTAssertFalse(result.title.contains("G"))
            XCTAssertFalse(result.title.contains("Bb"))
        }
    }

    func testLongActiveStrokeStaysWritingAndUnarmedReadingIsSavedSourceRatherThanAnInstantTimeout() throws {
        let chart = makeChart()
        let draft = makeDraft(chart, text: "Bb", trusted: false)
        let writing = activity(chart, phase: .waiting, pending: 1, age: 4)
        let target = try XCTUnwrap(status(draft, activity: writing))
        XCTAssertEqual(target.accessibilityLabel, "Writing chord")
        XCTAssertFalse(target.canReview)
        let global = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(activity: writing,
            feedback: .init(), hasSourceInk: true, now: now))
        XCTAssertFalse(global.canReview)
        XCTAssertFalse(global.title.localizedCaseInsensitiveContains("still reading"))
        let unarmed = activity(chart, phase: .reading, pending: 1, age: nil)
        let saved = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(activity: unarmed,
            feedback: .init(), hasSourceInk: true, now: now))
        XCTAssertFalse(saved.canReview)
        XCTAssertTrue(saved.isReading)
        XCTAssertFalse(saved.title.localizedCaseInsensitiveContains("still reading"))
    }

    func testRealProspectiveCollisionReportsNeedsSpaceForTrustedTarget() throws {
        let chart = makeChart()
        let first = PKDrawing(strokes: [stroke(106, width: 22, top: 48, bottom: 80, seed: 1)])
        let neighbor = PKDrawing(strokes: [stroke(159, width: 26, top: 0, bottom: 90, seed: 2)])
        let trusted = makeDraft(chart, text: "Cmaj7/E", trusted: true, drawing: first, fraction: 0.15)
        let collecting = makeDraft(chart, text: nil, trusted: false, drawing: neighbor, fraction: 0.3)
        let state = ChordPreviewState(draftChords: [trusted, collecting], layoutPageSize: pageSize)
        let source = PKDrawing(strokes: first.strokes + neighbor.strokes)
        let sourceLayout = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: frame.size),
            now: now, lastInputAt: now.addingTimeInterval(-2), isUsingTool: false,
            allowsImmediateSpatialCompletion: true, sourcePageLayout: sourceLayout, sourceChordFrame: frame)
        XCTAssertTrue(ChordInkAutomaticRenderPolicy.isTrusted(trusted))
        XCTAssertNil(attempt.outcome)
        XCTAssertEqual(attempt.feedback.reasonsByDraftID[trusted.id], .needsSpace,
            "The UI must use the actual placement refusal rather than infer success from supported text")
        let result = try XCTUnwrap(status(trusted, activity: activity(chart, phase: .settled, age: 2),
            feedback: attempt.feedback))
        XCTAssertTrue(result.canReview)
        XCTAssertTrue(result.accessibilityLabel.localizedCaseInsensitiveContains("space"))
    }

    func testNewUnrepresentedSourceCannotBeMisreportedAsAPredictiveGlyphCollision() throws {
        let chart = makeChart()
        let draft = makeDraft(chart, text: "G", trusted: true)
        let state = ChordPreviewState(draftChords: [draft], layoutPageSize: pageSize)
        let known = try PKDrawing(data: draft.drawingData)
        let current = PKDrawing(strokes: known.strokes + [stroke(300, width: 20, top: 48, bottom: 80, seed: 3)])
        let sourceLayout = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
            currentDrawing: current, coordinateSpace: PersistentInkCoordinateSpace(size: frame.size),
            now: now, lastInputAt: now.addingTimeInterval(-2), isUsingTool: false,
            allowsImmediateSpatialCompletion: true, sourcePageLayout: sourceLayout, sourceChordFrame: frame)
        XCTAssertNil(attempt.outcome)
        let reasons = Set(attempt.feedback.reasonsByDraftID.values.map(\.rawValue)
            + [attempt.feedback.globalReason?.rawValue].compactMap { $0 })
        XCTAssertFalse(reasons.contains(ChordInkAutomaticRenderReason.needsSpace.rawValue))
        XCTAssertFalse(reasons.isDisjoint(with: [ChordInkAutomaticRenderReason.unrepresentedInk.rawValue,
            ChordInkAutomaticRenderReason.needsSourceRefresh.rawValue]))
    }

    func testNoTargetOffersRecoveryWhileRestoredSourceRemainsReading() throws {
        let chart = makeChart()
        let unknown = ChordInkAutomaticRenderFeedback(globalReason: .unrepresentedInk)
        let noTarget = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
            activity: activity(chart, phase: .settled, age: 2), feedback: unknown,
            hasSourceInk: true, now: now))
        XCTAssertTrue(noTarget.canReview)
        XCTAssertFalse(noTarget.isReading)
        XCTAssertFalse(noTarget.detail.isEmpty)

        let restored = activity(chart, phase: .restored, age: nil)
        let saved = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
            activity: restored, feedback: .init(globalReason: .restoredInk), hasSourceInk: true, now: now))
        XCTAssertFalse(saved.canReview)
        XCTAssertTrue(saved.isReading)
        XCTAssertEqual(saved.title, "Reading saved writing…")
    }

    func testOverduePendingFallbackRemainsReadingAndNeverOffersBatchReview() throws {
        let chart = makeChart()
        let fresh = activity(chart, phase: .reading, pending: 1, age: 0.3)
        let overdue = activity(chart, phase: .reading, pending: 1, age: 4)
        XCTAssertFalse(ChordInkAutomaticFeedbackPolicy.isReadingOverdue(fresh, now: now))
        XCTAssertTrue(ChordInkAutomaticFeedbackPolicy.isReadingOverdue(overdue, now: now))
        let draft = makeDraft(chart, text: nil, trusted: false, collecting: true)
        let freshStatus = try XCTUnwrap(status(draft, activity: fresh))
        XCTAssertTrue(freshStatus.isReading)
        XCTAssertFalse(freshStatus.canReview)
        let overdueStatus = try XCTUnwrap(status(draft, activity: overdue))
        XCTAssertFalse(overdueStatus.canReview,
            "A pending fallback reader must not redirect normal automatic entry into batch review")
        XCTAssertTrue(overdueStatus.isReading)
        let global = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(activity: overdue,
            feedback: .init(), hasSourceInk: true, now: now))
        XCTAssertFalse(global.canReview)
        XCTAssertTrue(global.isReading)
    }

    func testAutomaticPresentationIsSuppressedInManualWorkflow() {
        let chart = makeChart()
        let draft = makeDraft(chart, text: "Bb", trusted: false)
        let current = activity(chart, phase: .settled, age: 2)
        XCTAssertNil(ChordInkAutomaticFeedbackPresentationPolicy.status(for: draft, activity: current,
            feedback: .baseline(for: .init(draftChords: [draft], layoutPageSize: pageSize)),
            now: now, manualRenderWithPreview: true))
        XCTAssertNil(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(activity: current,
            feedback: .init(globalReason: .unrepresentedInk), hasSourceInk: true,
            now: now, manualRenderWithPreview: true))
    }

    func testExplicitlyReviewedUncertainBbUsesAutomaticSourceAnchorWithoutAnArmedTimerOrTrust() throws {
        let chart = makeChart()
        let draft = makeDraft(chart, text: "Bb", trusted: false)
        let source = try PKDrawing(data: draft.drawingData)
        let state = ChordPreviewState(draftChords: [draft], layoutPageSize: pageSize)
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let reviewed = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
            candidateTextByDraftID: [draft.id: "Bb"]))
        XCTAssertEqual(reviewed.draftChords.map(\.id), state.draftChords.map(\.id))
        XCTAssertEqual(reviewed.draftChords[0].selectedText, "Bb")
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(reviewed.draftChords[0]))
        let sourceLayout = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        let attempt = ChordInkDraftRenderCoordinator.prepareReviewedAutomaticAttempt(chart: chart,
            state: reviewed, currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: frame.size),
            isUsingTool: false, sourcePageLayout: sourceLayout, sourceChordFrame: frame)
        let outcome = try XCTUnwrap(attempt.outcome)
        let event = try XCTUnwrap(outcome.chart.measures.flatMap(\.chordEvents).first)
        let glyph = try XCTUnwrap(layout(outcome.chart).systems.flatMap(\.measures).flatMap(\.chordLayouts)
            .first { $0.id == event.id })
        XCTAssertEqual(event.rawInput, "Bb")
        XCTAssertEqual(glyph.naturalFrame.minX, source.bounds.minX + frame.minX, accuracy: 2,
            "Reviewing automatic ink must not route back through legacy beat-guide placement")
        XCTAssertNotNil(event.manualVisualLaneFraction)
        XCTAssertEqual(outcome.consumedDraftIDs, [draft.id])
        XCTAssertTrue(outcome.drawing.strokes.isEmpty)
        XCTAssertNil(outcome.chart.pageHandwrittenChordData)
    }

    func testReviewedAutomaticCollisionRejectsWholeTransactionWithoutChangingChartOrInk() throws {
        var chart = makeChart()
        let first = PKDrawing(strokes: [stroke(106, width: 22, top: 48, bottom: 80, seed: 1)])
        let second = PKDrawing(strokes: [stroke(159, width: 26, top: 48, bottom: 80, seed: 2)])
        let source = PKDrawing(strokes: first.strokes + second.strokes)
        _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation())
        let drafts = [makeDraft(chart, text: "Cmaj7/E", trusted: false, drawing: first, fraction: 0.15),
            makeDraft(chart, text: "Bb", trusted: false, drawing: second, fraction: 0.3)]
        let state = ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let reviewed = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
            candidateTextByDraftID: [drafts[0].id: "Cmaj7/E", drafts[1].id: "Bb"]))
        let originalChart = chart
        let originalBytes = source.dataRepresentation()
        let sourceLayout = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        let attempt = ChordInkDraftRenderCoordinator.prepareReviewedAutomaticAttempt(chart: chart,
            state: reviewed, currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: frame.size),
            isUsingTool: false, sourcePageLayout: sourceLayout, sourceChordFrame: frame)
        XCTAssertNil(attempt.outcome)
        XCTAssertEqual(attempt.feedback.reasonsByDraftID[drafts[0].id], .needsSpace)
        XCTAssertEqual(chart, originalChart)
        XCTAssertEqual(source.dataRepresentation(), originalBytes)
        XCTAssertEqual(chart.pageHandwrittenChordData, originalChart.pageHandwrittenChordData)
    }

    func testReviewedAutomaticSourceChangeRejectsOldEntryWithoutConsumingCurrentInk() throws {
        var chart = makeChart()
        let draft = makeDraft(chart, text: "Bb", trusted: false)
        let state = ChordPreviewState(draftChords: [draft], layoutPageSize: pageSize)
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let reviewed = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
            candidateTextByDraftID: [draft.id: "Bb"]))
        let changed = PKDrawing(strokes: [stroke(107, width: 22, top: 48, bottom: 80, seed: 1)])
        _ = chart.setPageHandwrittenChordDrawing(changed.dataRepresentation())
        let sourceLayout = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        let originalChart = chart
        let originalBytes = changed.dataRepresentation()
        let attempt = ChordInkDraftRenderCoordinator.prepareReviewedAutomaticAttempt(chart: chart,
            state: reviewed, currentDrawing: changed, coordinateSpace: PersistentInkCoordinateSpace(size: frame.size),
            isUsingTool: false, sourcePageLayout: sourceLayout, sourceChordFrame: frame)
        XCTAssertNil(attempt.outcome)
        XCTAssertEqual(attempt.feedback.reasonsByDraftID[draft.id], .needsSourceRefresh)
        XCTAssertEqual(chart, originalChart)
        XCTAssertEqual(changed.dataRepresentation(), originalBytes)
        XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
    }

    func testVisibleReviewSuspendsUnsolicitedAutoButConfirmedBbStillConsumesExactLiveSource() throws {
        let chart = makeChart()
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize),
            chordInkRecognizer: FeedbackHostRecognizer())
        view.chart = chart
        view.interactionMode = .chordEntry
        view.manualRenderWithPreview = false
        let coordinator = ChordInkDraftRenderCoordinator()
        view.chordDraftRenderCoordinator = coordinator
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: CGRect(origin: .zero, size: pageSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            view.recognizesChordInk = false
            window.isHidden = true
            window.rootViewController = nil
        }
        view.layoutIfNeeded()
        let canvas = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        let source = PKDrawing(strokes: [stroke(106, width: 22, top: 48, bottom: 80, seed: 1)])
        canvas.drawing = source
        view.canvasViewDrawingDidChange(canvas)
        let draft = makeDraft(view.chart, text: "Bb", trusted: false, drawing: source)
        let state = ChordPreviewState(draftChords: [draft], layoutPageSize: pageSize)
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let reviewed = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
            candidateTextByDraftID: [draft.id: "Bb"]))
        let trusted = makeDraft(view.chart, text: "Bb", trusted: true, drawing: source)
        let trustedState = ChordPreviewState(draftChords: [trusted], layoutPageSize: pageSize)
        let lifecycle = try XCTUnwrap(trusted.targetLifecycle)
        let request = ChordInkRecognitionSessionRequest(requestID: UUID(), scheduledAt: now,
            requestedDelay: 0, strokes: lifecycle.ownership.preparedStrokes,
            drawingData: trusted.drawingData, target: (trusted.measureID, trusted.targetFraction ?? 0),
            layoutPageSize: pageSize, options: .live)
        XCTAssertTrue(view.installAutomaticChordCensus([request], forInkRevision: view.automaticChordInputRevision))
        XCTAssertTrue(view.hasCurrentAutomaticChordCensus)
        view.chordPreviewState = reviewed
        coordinator.lastInputAt = now.addingTimeInterval(-2)
        view.isInteractionSuspended = true
        let before = canvas.drawing.dataRepresentation()

        XCTAssertNil(view.attemptChordDraftAutomatically(chart: view.chart, state: trustedState,
            now: now, lastInputAt: coordinator.lastInputAt).outcome,
            "An open review must keep unsolicited automatic mutation suspended")
        XCTAssertEqual(canvas.drawing.dataRepresentation(), before)

        // Presenting a review intentionally disarms the automatic clock. Its
        // explicit Render action remains valid while interaction is suspended.
        coordinator.lastInputAt = nil
        let attempt = view.attemptReviewedChordDraftAutomatically(chart: view.chart, state: reviewed)
        let outcome = try XCTUnwrap(attempt.outcome)
        XCTAssertTrue(view.isInteractionSuspended)
        XCTAssertEqual(outcome.result.renderedChordCount, 1)
        let event = try XCTUnwrap(view.chart.measures.flatMap(\.chordEvents).first)
        XCTAssertEqual(event.rawInput, "Bb")
        let committedSource = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: committedSource))
        XCTAssertTrue(canvas.drawing.strokes.isEmpty)
        XCTAssertNil(view.chart.pageHandwrittenChordData)
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout(chart))
        let glyph = try XCTUnwrap(layout(view.chart).systems.flatMap(\.measures).flatMap(\.chordLayouts)
            .first { $0.id == event.id })
        XCTAssertEqual(glyph.naturalFrame.minX, source.bounds.minX + sourceFrame.minX, accuracy: 2)
    }

    func testCancellingReviewReplaysLateUncertainReadWithoutNewInputAndRejectsReplayAfterSourceChange() async throws {
        let started = expectation(description: "Reader began before review opened")
        let completedWhileOpen = expectation(description: "Canvas retained a result ignored by the open review")
        let recognizer = FeedbackBlockingRecognizer(onStarted: { started.fulfill() })
        let chart = makeChart()
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize), chordInkRecognizer: recognizer)
        view.chart = chart
        view.interactionMode = .chordEntry
        view.manualRenderWithPreview = false
        let coordinator = ChordInkDraftRenderCoordinator()
        view.chordDraftRenderCoordinator = coordinator
        coordinator.automaticCensusReplayer = { [weak view] in view?.replayCurrentAutomaticChordCensus() ?? false }
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: CGRect(origin: .zero, size: pageSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            view.onChordInkDraftPreviewChanged = nil
            recognizer.release.signal()
            view.recognizesChordInk = false
            window.isHidden = true
            window.rootViewController = nil
        }
        view.layoutIfNeeded()
        let canvas = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        var panelOpen = false
        var deliveredToEditor: [[ChordInkRecognitionProposalPayload]] = []
        var observedLateCompletion = false
        view.onChordInkDraftPreviewChanged = { payloads in
            if panelOpen {
                if !observedLateCompletion, payloads.contains(where: {
                    $0.result.match?.displayText == "Bb" && $0.targetLifecycle?.stage == .stable
                }) {
                    observedLateCompletion = true
                    completedWhileOpen.fulfill()
                }
                return // Matches EditorView's open-review update guard.
            }
            deliveredToEditor.append(payloads)
        }
        let source = PKDrawing(strokes: [stroke(106, width: 22, top: 48, bottom: 80, seed: 1)])
        view.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = source
        view.canvasViewDrawingDidChange(canvas)
        view.canvasViewDidEndUsingTool(canvas)
        await fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(deliveredToEditor.last?.first?.targetLifecycle?.stage, .collecting)
        panelOpen = true
        view.isInteractionSuspended = true
        coordinator.lastInputAt = nil // Opening review disarms automatic deadlines.
        recognizer.release.signal()
        await fulfillment(of: [completedWhileOpen], timeout: 5)
        XCTAssertEqual(deliveredToEditor.last?.first?.targetLifecycle?.stage, .collecting,
            "The editor must still have its old collecting state while review is open")
        let retainedBytes = canvas.drawing.dataRepresentation()
        let revision = view.automaticChordInputRevision

        panelOpen = false
        view.isInteractionSuspended = false
        XCTAssertTrue(coordinator.replayCurrentAutomaticChordCensus())
        let replayed = try XCTUnwrap(deliveredToEditor.last?.first)
        XCTAssertEqual(replayed.result.match?.displayText, "Bb")
        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: replayed.result).action, .confirm)
        XCTAssertEqual(replayed.targetLifecycle?.stage, .stable)
        XCTAssertEqual(recognizer.calls, 1, "Returning to writing replays the stored interpretation without a new read")
        XCTAssertNil(coordinator.lastInputAt, "Replay must not arm another automatic deadline")
        XCTAssertEqual(view.automaticChordInputRevision, revision)
        XCTAssertEqual(canvas.drawing.dataRepresentation(), retainedBytes)
        XCTAssertTrue(view.chart.measures.allSatisfy(\.chordEvents.isEmpty))

        let publications = deliveredToEditor.count
        canvas.drawing = PKDrawing(strokes: [stroke(107, width: 22, top: 48, bottom: 80, seed: 1)])
        view.canvasViewDrawingDidChange(canvas)
        XCTAssertFalse(coordinator.replayCurrentAutomaticChordCensus(),
            "A late result from a different live source revision cannot be replayed")
        XCTAssertEqual(deliveredToEditor.count, publications)
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
    }

    func testOptionalCapturedThreeStrokeSourceWithFrozenBbSuggestionIsUncertainNotTrusted() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appendingPathComponent(".build/auto-render96-unresolved-2026-10-30/app-support/library-state.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Optional local unresolved-source fixture is not present")
        }
        let bytes = try Data(contentsOf: fixture)
        let snapshot = try XCTUnwrap(try FileChartRepository(url: fixture).loadSnapshot())
        let chart = try XCTUnwrap(snapshot.charts.filter { $0.pageHandwrittenChordData != nil }
            .max(by: { $0.updatedAt < $1.updatedAt }))
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertEqual(source.strokes.count, 3)
        // These are the frozen observed candidates, not a new recognition run.
        // No private profile/correction state is loaded or accuracy claimed.
        let candidates = ["Bb", "Db", "B°", "D°"]
        let result = ChordInkRecognitionResult(rawCandidates: candidates, glyphCandidates: [],
            match: ChordRecognitionCompendium.match("Bb"), confidence: 0,
            candidateScores: candidates.map { ChordInkCandidateScore(text: $0, displayText: $0, confidence: 0) })
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        XCTAssertEqual(decision.action, .confirm)
        var draft = makeDraft(chart, text: "Bb", trusted: false, drawing: source)
        draft.recognitionResult = result
        draft.recognitionDecision = decision
        draft.primaryDecision = decision
        draft.candidateTexts = candidates
        XCTAssertTrue(draft.isRenderable)
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(draft))
        XCTAssertEqual(ChordInkAutomaticFeedbackPolicy.recognitionReason(for: draft), .recognitionReview)
        let presentation = try XCTUnwrap(status(draft, activity: activity(chart, phase: .settled, age: 2)))
        XCTAssertEqual(presentation.accessibilityLabel, "Rendering Bb")
        XCTAssertFalse(presentation.canReview)
        XCTAssertEqual(try Data(contentsOf: fixture), bytes)
    }

    private func status(_ draft: ChordInkDraft, activity: ChordInkAutomaticActivity,
        feedback: ChordInkAutomaticRenderFeedback? = nil) -> ChordInkAutomaticFeedbackPresentation? {
        ChordInkAutomaticFeedbackPresentationPolicy.status(for: draft, activity: activity,
            feedback: feedback ?? .baseline(for: .init(draftChords: [draft], layoutPageSize: pageSize)), now: now)
    }

    private func activity(_ chart: Chart, phase: ChordInkAutomaticActivity.Phase,
        pending: Int = 0, age: TimeInterval?) -> ChordInkAutomaticActivity {
        .init(chartID: chart.id, sourceRevision: 1, hasSourceInk: true, phase: phase,
            pendingTargetCount: pending, inputAt: age.map { now.addingTimeInterval(-$0) })
    }

    private func completion(_ chart: Chart, feedback: ChordInkAutomaticRenderFeedback,
        strokeCount: Int) -> IChartTelemetryProperties? {
        var current = activity(chart, phase: .settled, age: 4)
        current.feedback = feedback
        return ChordInkAutomaticRenderTelemetry.completionProperties(isEnabled: true,
            chart: chart, mode: .automatic, activity: current, now: now, isForeground: true,
            foregroundObservationDuration: 3.1, remainingStrokeCount: strokeCount, madeProgress: false)
    }

    private func makeChart() -> Chart {
        var chart = Chart.draft(title: "Automatic feedback", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func layout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize, includesChordInkContinuationLanes: true)
    }

    private func makeDraft(_ chart: Chart, text: String?, trusted: Bool, drawing: PKDrawing? = nil,
        fraction: Double = 0.15, collecting: Bool = false) -> ChordInkDraft {
        let drawing = drawing ?? PKDrawing(strokes: [stroke(106, width: 22, top: 48, bottom: 80, seed: 1)])
        let decision = ChordInkRecognitionDecision(action: trusted ? .trusted : .confirm,
            acceptedText: trusted ? text : nil, reason: "Frozen test decision", isCloseRace: false,
            competingCandidateText: nil, confidenceGap: nil)
        let result = ChordInkRecognitionResult(rawCandidates: text.map { [$0] } ?? [], glyphCandidates: [],
            match: text.flatMap(ChordRecognitionCompendium.match), confidence: trusted ? 4.5 : 0)
        var input = ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: chart.measures[0].index,
            targetFraction: fraction, layoutPageSize: pageSize, drawingData: drawing.dataRepresentation(),
            candidateTexts: text.map { [$0] } ?? [], bestCandidateText: text, confidence: trusted ? 4.5 : 0,
            strokeCount: drawing.strokes.count, recognitionResult: result,
            primaryDecision: decision, recognitionDecision: decision)
        input.targetLifecycle = .init(generationID: UUID(), anchor: input.anchor,
            ownership: .init(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: drawing)),
            stage: collecting ? .collecting : .frozen)
        return ChordInkDraft(input: input)
    }

    private func stroke(_ x: CGFloat, width: CGFloat, top: CGFloat, bottom: CGFloat, seed: UInt32) -> PKStroke {
        let points = [CGPoint(x: x, y: bottom), CGPoint(x: x + width, y: top)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: now), transform: .identity,
            mask: nil, randomSeed: seed)
    }
}

private final class FeedbackHostRecognizer: ChordInkRecognizing {
    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        .init(rawCandidates: ["Bb"], glyphCandidates: [], match: ChordRecognitionCompendium.match("Bb"),
            confidence: 4.5, candidateScores: [.init(text: "Bb", displayText: "Bb", confidence: 4.5)])
    }
}

private final class FeedbackBlockingRecognizer: ChordInkRecognizing {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let onStarted: () -> Void
    private var callCount = 0
    var calls: Int { lock.withLock { callCount } }
    init(onStarted: @escaping () -> Void) { self.onStarted = onStarted }
    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        let first = lock.withLock { callCount += 1; return callCount == 1 }
        if first {
            onStarted()
            _ = release.wait(timeout: .now() + 15)
        }
        return .init(rawCandidates: ["Bb", "Db"], glyphCandidates: [],
            match: ChordRecognitionCompendium.match("Bb"), confidence: 0,
            candidateScores: [.init(text: "Bb", displayText: "Bb", confidence: 0),
                .init(text: "Db", displayText: "Db", confidence: 0)])
    }
}
#endif

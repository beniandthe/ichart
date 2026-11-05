#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkIncrementalDraftStateTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let time = Date(timeIntervalSinceReferenceDate: 100)

    func testCompletedFRemainsWhileGCollectsNewInkAndOldGResultIsRejected() throws {
        let chart = chart()
        let f = drawing([stroke(10)])
        let g = drawing([stroke(110)])
        let first = requests(chart, drawings: [f, g])
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus(first)
        let completedF = payload(first[0], text: "F")
        XCTAssertNotNil(census.accept(completedF))

        let changedG = drawing(g.strokes + [stroke(130)])
        let second = requests(chart, drawings: [f, changedG])
        let current = census.acceptCensus(second)

        XCTAssertEqual(current.count, 2)
        XCTAssertEqual(current[0].result.match?.displayText, "F")
        XCTAssertEqual(current[0].requestID, second[0].requestID)
        XCTAssertEqual(current[0].targetLifecycle?.stage, .stable)
        XCTAssertTrue(current[0].timing.cacheHit)
        XCTAssertEqual(current[0].drawingData, second[0].drawingData)
        XCTAssertEqual(current[1].strokes, second[1].strokes)
        XCTAssertTrue(current[1].result.rawCandidates.isEmpty)
        XCTAssertEqual(current[1].targetLifecycle?.stage, .collecting)
        XCTAssertFalse(current[1].requiresManualReviewOnly)
        XCTAssertEqual(census.pendingRequests.count, 1)
        XCTAssertEqual(census.pendingRequests.first?.strokes, second[1].strokes)
        XCTAssertNil(census.accept(payload(first[1], text: "G")))
        XCTAssertEqual(census.payloads[0].result, completedF.result)
    }

    func testChangedFInkDiscardsItsInterpretationAndPreservesUnchangedG() throws {
        let chart = chart()
        let f = drawing([stroke(10)])
        let g = drawing([stroke(110)])
        let first = requests(chart, drawings: [f, g])
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus(first)
        census.accept(payload(first[0], text: "F"))
        census.accept(payload(first[1], text: "G"))

        let editedF = drawing(f.strokes + [stroke(28)])
        let second = requests(chart, drawings: [editedF, g])
        let current = census.acceptCensus(second)
        XCTAssertNil(current[0].result.match)
        XCTAssertEqual(current[0].targetLifecycle?.stage, .collecting)
        XCTAssertEqual(current[0].strokes, second[0].strokes)
        XCTAssertEqual(current[1].result.match?.displayText, "G")
        XCTAssertNil(census.accept(payload(first[0], text: "F")))
        XCTAssertNil(census.payloads[0].result.match)
    }

    func testCollectingPlaceholderOwnsInkWithoutFreezingOrBecomingManualOnly() throws {
        let chart = chart()
        let request = try XCTUnwrap(requests(chart, drawings: [drawing([stroke(110)])]).first)
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus([request])
        var preview = previewState(chart, payloads: census.payloads)
        let collecting = try XCTUnwrap(preview.draftChords.first)
        XCTAssertEqual(collecting.targetLifecycle?.stage, .collecting)
        XCTAssertFalse(collecting.requiresManualReviewOnly)
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(collecting))
        XCTAssertNil(collecting.previewText)

        let completed = try XCTUnwrap(census.accept(payload(request, text: "G")))
        // The automatic editor replaces its census drafts; it does not ask
        // the manual UI reducer to preserve an obsolete frozen preview.
        preview.draftChords.removeAll()
        preview.replaceDraftChords(with: inputs(chart, payloads: completed))
        let read = try XCTUnwrap(preview.draftChords.first)
        XCTAssertEqual(read.targetLifecycle?.stage, .frozen)
        XCTAssertFalse(read.requiresManualReviewOnly)
        XCTAssertEqual(read.previewText, "G")
        XCTAssertTrue(ChordInkAutomaticRenderPolicy.isTrusted(read))
    }

    func testCensusRepresentsEveryMaskedFragmentAndTinyManualRecoveryTarget() throws {
        var chart = chart()
        let mask = UIBezierPath()
        mask.append(UIBezierPath(rect: CGRect(x: -2, y: -8, width: 16, height: 16)))
        mask.append(UIBezierPath(rect: CGRect(x: 36, y: -8, width: 16, height: 16)))
        let masked = stroke(points: stride(from: 0, through: 50, by: 10).map {
            CGPoint(x: CGFloat($0), y: 0)
        }, mask: mask)
        let tiny = stroke(points: [CGPoint(x: 160, y: 10), CGPoint(x: 160.5, y: 10.5)],
            transform: CGAffineTransform(scaleX: 0.1, y: 0.1), size: 0.5)
        _ = chart.setPageHandwrittenChordDrawing(drawing([masked, tiny]).dataRepresentation())
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let fragments = source.strokes.flatMap(PencilKitInkAdapter.visibleStrokeFragments)
        XCTAssertEqual(fragments.count, 3)
        var prepared = requests(chart, drawings: fragments.map { drawing([$0]) })
        prepared[2].requiresManualReviewOnly = true
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus(prepared)
        XCTAssertEqual(census.payloads.count, 3)
        XCTAssertTrue(census.payloads[2].requiresManualReviewOnly)
        XCTAssertTrue(census.payloads.allSatisfy { $0.targetLifecycle?.stage == .collecting })
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
            state: previewState(chart, payloads: census.payloads)))

        census.acceptCensus(Array(prepared.dropLast()))
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
            state: previewState(chart, payloads: census.payloads)),
            "A tiny unrepresented fragment must remain a failed coverage gate")
    }

    func testConsumingFRemovesItsClaimAndLateCompletionCannotRestoreIt() throws {
        let chart = chart()
        let prepared = requests(chart, drawings: [drawing([stroke(10)]), drawing([stroke(110)])])
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus(prepared)
        census.accept(payload(prepared[0], text: "F"))
        let fullState = previewState(chart, payloads: census.payloads)
        let remaining = ChordPreviewState(draftChords: [fullState.draftChords[1]], layoutPageSize: pageSize)
        census.retainTargets(in: remaining)

        XCTAssertEqual(census.payloads.count, 1)
        XCTAssertEqual(census.payloads[0].strokes, prepared[1].strokes)
        XCTAssertNil(census.accept(payload(prepared[0], text: "F")))
        XCTAssertEqual(census.payloads.count, 1)
        XCTAssertEqual(census.accept(payload(prepared[1], text: "G"))?.first?.result.match?.displayText, "G")
        census.reset()
        XCTAssertTrue(census.payloads.isEmpty)
        XCTAssertTrue(census.pendingRequests.isEmpty)
    }

    func testOptionsReviewRequirementsAndEvaluationScopeInvalidateRetainedRead() throws {
        let chart = chart()
        let original = try XCTUnwrap(requests(chart, drawings: [drawing([stroke(10)])]).first)
        var variants = [ChordInkRecognitionSessionRequest]()
        var options = original
        options.options = .includingSymbolLedgerDiagnostics
        variants.append(options)
        var edited = original
        edited.requiresEditReview = true
        variants.append(edited)
        var manual = original
        manual.requiresManualReviewOnly = true
        variants.append(manual)
        var evaluation = original
        evaluation.evaluationContext = .init(runID: UUID(), profile: PersonalInkSnapshot(profile: .init()))
        variants.append(evaluation)
        for var variant in variants {
            var census = ChordInkIncrementalDraftState()
            census.acceptCensus([original])
            census.accept(payload(original, text: "F"))
            variant.requestID = UUID()
            let current = census.acceptCensus([variant])
            XCTAssertEqual(current.first?.targetLifecycle?.stage, .collecting)
            XCTAssertNil(current.first?.result.match)
            XCTAssertEqual(census.pendingRequests.count, 1)
            XCTAssertNil(census.accept(payload(original, text: "F")))
        }
    }

    func testLocalProfileRevisionChangeDiscardsRetainedInterpretations() throws {
        let chart = chart()
        let first = requests(chart, drawings: [drawing([stroke(10)])])
        let profileRevision = UUID()
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus(first, contextRevision: profileRevision)
        census.accept(payload(first[0], text: "F"))

        let next = requests(chart, drawings: [drawing([stroke(10)])])
        XCTAssertEqual(census.acceptCensus(next, contextRevision: profileRevision)
            .first?.result.match?.displayText, "F")
        let changed = census.acceptCensus(next, contextRevision: UUID())
        XCTAssertNil(changed.first?.result.match)
        XCTAssertEqual(changed.first?.targetLifecycle?.stage, .collecting)
        XCTAssertEqual(census.pendingRequests.count, 1)
    }

    func testEvaluationProfileChangeWithinSameRunInvalidatesRetainedRead() throws {
        let chart = chart()
        var first = requests(chart, drawings: [drawing([stroke(10)])])
        let runID = UUID()
        first[0].evaluationContext = .init(runID: runID, profile: PersonalInkSnapshot(profile: .init()))
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus(first)
        census.accept(payload(first[0], text: "F"))
        var changed = first
        changed[0].requestID = UUID()
        changed[0].evaluationContext = .init(runID: runID, profile: PersonalInkSnapshot(profile: .init()))
        let current = census.acceptCensus(changed)
        XCTAssertNil(current.first?.result.match)
        XCTAssertEqual(current.first?.targetLifecycle?.stage, .collecting)
    }

    func testGroupingMergeAndDuplicateClaimsCannotReuseAnEarlierSubsetRead() throws {
        let chart = chart()
        let first = requests(chart, drawings: [drawing([stroke(10)]), drawing([stroke(110)])])
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus(first)
        census.accept(payload(first[0], text: "F"))
        let combined = drawing([stroke(10), stroke(110)])
        let merged = requests(chart, drawings: [combined])
        let current = census.acceptCensus(merged)
        XCTAssertEqual(current.count, 1)
        XCTAssertNil(current.first?.result.match)
        XCTAssertNil(census.accept(payload(first[0], text: "F")))

        let duplicate = try XCTUnwrap(merged.first)
        census.acceptCensus([duplicate, duplicate])
        XCTAssertNil(census.accept(payload(duplicate, text: "F")))
        XCTAssertTrue(census.payloads.allSatisfy { $0.targetLifecycle?.stage == .collecting })
        XCTAssertEqual(census.payloads.count, 2,
            "Ambiguous duplicate claims stay visible to complete-source coverage; they are not silently deduplicated")
    }

    @MainActor
    func testFreshReaderRetryProofFollowsOnlyItsSelectedAutomaticEvent() async throws {
        let fixture = try readerRetryFixture()
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus([fixture.request])
        let state = previewState(fixture.chart, payloads: try XCTUnwrap(census.accept(fixture.payload)))
        let outcome = try automaticRetryOutcome(chart: fixture.chart, state: state, source: fixture.source)
        let draft = try XCTUnwrap(state.draftChords.first)
        let event = try XCTUnwrap(outcome.chart.measures.flatMap(\.chordEvents).first)

        XCTAssertEqual(outcome.result.renderedChordIDsByDraftID[draft.id], event.id)
        XCTAssertEqual(event.rawInput, "C7")
        XCTAssertEqual(event.sourceInkData, draft.drawingData)
        XCTAssertEqual(census.readerRetryProofs(for: outcome, state: state, originalChart: fixture.chart,
            consent: fixture.consent), [fixture.proof])
        XCTAssertTrue(census.readerRetryProofs(for: outcome, state: state, originalChart: fixture.chart,
            consent: fixture.laterConsent).isEmpty)

        // An explicit edit is not reader recovery even when the text is equal.
        var manuallySelected = state
        manuallySelected.draftChords[0].selectedText = "C7"
        XCTAssertTrue(census.readerRetryProofs(for: outcome, state: manuallySelected,
            originalChart: fixture.chart, consent: fixture.consent).isEmpty)
        var stale = state
        stale.draftChords[0].isStale = true
        XCTAssertTrue(census.readerRetryProofs(for: outcome, state: stale,
            originalChart: fixture.chart, consent: fixture.consent).isEmpty)
        XCTAssertTrue(census.readerRetryProofs(for: outcome, state: state,
            originalChart: outcome.chart, consent: fixture.consent).isEmpty,
            "An existing event cannot masquerade as the new automatic commit")
    }

    @MainActor
    func testEqualIndependentCandidateDoesNotInheritRetryProof() async throws {
        let fixture = try readerRetryFixture()
        var payload = fixture.payload
        payload.result.reviewCandidateScores.insert(.init(text: "C7", displayText: "C7", confidence: 1),
            at: 0)
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus([fixture.request])
        let state = previewState(fixture.chart, payloads: try XCTUnwrap(census.accept(payload)))
        let outcome = try automaticRetryOutcome(chart: fixture.chart, state: state, source: fixture.source)
        XCTAssertEqual(outcome.chart.measures.flatMap(\.chordEvents).first?.rawInput, "C7")
        XCTAssertTrue(census.readerRetryProofs(for: outcome, state: state, originalChart: fixture.chart,
            consent: fixture.consent).isEmpty)
    }

    @MainActor
    func testRetryProofCannotSurviveReplayWrongArchiveOrFailedTransaction() async throws {
        let fixture = try readerRetryFixture()
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus([fixture.request])
        let state = previewState(fixture.chart, payloads: try XCTUnwrap(census.accept(fixture.payload)))
        let outcome = try automaticRetryOutcome(chart: fixture.chart, state: state, source: fixture.source)

        var failedResult = outcome.result
        failedResult.didRejectIncompleteSourceCoverage = true
        let failedOutcome = ChordInkDraftRenderCoordinator.AutomaticOutcome(chart: outcome.chart,
            drawing: outcome.drawing, remainingState: outcome.remainingState, result: failedResult,
            consumedDraftIDs: outcome.consumedDraftIDs)
        XCTAssertTrue(census.readerRetryProofs(for: failedOutcome, state: state,
            originalChart: fixture.chart, consent: fixture.consent).isEmpty)

        var cached = fixture.payload
        cached.timing.cacheHit = true
        XCTAssertNil(census.accept(cached)?.first?.readerRetryProof)
        var wrongArchive = fixture.payload
        wrongArchive.drawingData = drawing([stroke(160)]).dataRepresentation()
        XCTAssertNil(census.accept(wrongArchive)?.first?.readerRetryProof)

        XCTAssertEqual(census.accept(fixture.payload)?.first?.readerRetryProof, fixture.proof)
        var newerCensus = fixture.request
        newerCensus.requestID = UUID()
        XCTAssertNil(census.acceptCensus([newerCensus]).first?.readerRetryProof)
        XCTAssertNil(census.accept(fixture.payload))
        XCTAssertTrue(census.readerRetryProofs(for: outcome, state: state, originalChart: fixture.chart,
            consent: fixture.consent).isEmpty)
    }

    private struct ReaderRetryFixture {
        let chart: Chart
        let source: PKDrawing
        let request: ChordInkRecognitionSessionRequest
        let payload: ChordInkRecognitionProposalPayload
        let proof: ChordInkReaderRetryProof
        let consent: IChartTelemetryConsentSnapshot
        let laterConsent: IChartTelemetryConsentSnapshot
    }

    private func readerRetryFixture() throws -> ReaderRetryFixture {
        let chart = chart()
        let source = drawing([stroke(110)])
        let request = try XCTUnwrap(requests(chart, drawings: [source]).first)
        let suite = "iChart-retry-draft-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consentStore = IChartTelemetryConsentStore(defaults: defaults)
        consentStore.setConsentGranted(true)
        let consent = consentStore.cachedSnapshotForScheduling
        consentStore.setConsentGranted(false)
        consentStore.setConsentGranted(true)
        let proof = ChordInkReaderRetryProof(episodeID: UUID(), failedAttemptMilliseconds: 6,
            recoveredAttemptMilliseconds: 9, supportedCandidateCount: 1, consent: consent)
        let vision = ChordInkVisionAutomaticFallbackRecognizer()
        var payload = payload(request, text: "C7")
        payload.result = .init(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0,
            reviewCandidateScores: [.init(text: "C7", displayText: "C7", confidence: 1)],
            fallbackEvidence: [.init(engineIdentifier: vision.identifier,
                engineVersion: vision.version, candidateTexts: ["C7"], durationMilliseconds: 15, attemptCount: 2)])
        payload.readerRetryProof = proof
        return ReaderRetryFixture(chart: chart, source: source, request: request, payload: payload,
            proof: proof, consent: consent, laterConsent: consentStore.cachedSnapshotForScheduling)
    }

    @MainActor
    private func automaticRetryOutcome(
        chart: Chart, state: ChordPreviewState, source: PKDrawing
    ) throws -> ChordInkDraftRenderCoordinator.AutomaticOutcome {
        try XCTUnwrap(ChordInkDraftRenderCoordinator.prepareAutomatic(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: pageSize),
            now: time.addingTimeInterval(4), lastInputAt: time, isUsingTool: false))
    }

    private func requests(
        _ chart: Chart, drawings: [PKDrawing], requestID: UUID = UUID()
    ) -> [ChordInkRecognitionSessionRequest] {
        drawings.map { source in
            let normalized = LeadSheetPersistentInkColorPolicy.normalizedDrawing(source)
            let x = normalized.strokes.first?.renderBounds.minX ?? 0
            return ChordInkRecognitionSessionRequest(requestID: requestID, scheduledAt: time,
                requestedDelay: 0, strokes: PencilKitInkAdapter.inkStrokes(from: normalized),
                drawingData: normalized.dataRepresentation(), target: (chart.measures[0].id, Double(x / 900)),
                layoutPageSize: pageSize, options: .live)
        }
    }

    private func payload(
        _ request: ChordInkRecognitionSessionRequest, text: String
    ) -> ChordInkRecognitionProposalPayload {
        ChordInkRecognitionProposalPayload(requestID: request.requestID,
            result: ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
                match: ChordRecognitionCompendium.match(text), confidence: 4.5),
            strokes: request.strokes, drawingData: request.drawingData, target: request.target,
            visualOrder: request.visualOrder, laneLocation: request.laneLocation,
            layoutPageSize: request.layoutPageSize,
            targetLifecycle: request.collectingTargetLifecycle.advanced(to: .stable),
            timing: ChordInkRecognitionTiming(scheduledAt: time, requestedDelay: 0,
                recognitionStartedAt: time, recognitionFinishedAt: time, strokeCount: request.strokes.count),
            requiresManualReviewOnly: request.requiresManualReviewOnly)
    }

    private func previewState(
        _ chart: Chart, payloads: [ChordInkRecognitionProposalPayload]
    ) -> ChordPreviewState {
        var state = ChordPreviewState()
        state.replaceDraftChords(with: inputs(chart, payloads: payloads))
        return state
    }

    private func inputs(
        _ chart: Chart, payloads: [ChordInkRecognitionProposalPayload]
    ) -> [ChordInkDraftInput] {
        payloads.map { payload in
            let decision = ChordInkRecognitionPolicy.decision(for: payload.result)
            return ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: payload.target.fraction, visualOrder: payload.visualOrder,
                laneLocation: payload.laneLocation, layoutPageSize: payload.layoutPageSize,
                drawingData: payload.drawingData, candidateTexts: payload.result.rawCandidates,
                bestCandidateText: decision.acceptedText, confidence: payload.result.confidence,
                strokeCount: payload.strokes.count, recognitionResult: payload.result,
                primaryDecision: decision, recognitionDecision: decision,
                targetLifecycle: payload.targetLifecycle, requiresManualReviewOnly: payload.requiresManualReviewOnly)
        }
    }

    private func chart() -> Chart {
        var chart = Chart.draft(title: "Incremental draft census", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func drawing(_ strokes: [PKStroke]) -> PKDrawing {
        LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes))
    }

    private func stroke(_ x: CGFloat) -> PKStroke {
        stroke(points: [CGPoint(x: x, y: 10), CGPoint(x: x + 14, y: 30)])
    }

    private func stroke(
        points: [CGPoint], mask: UIBezierPath? = nil, transform: CGAffineTransform = .identity,
        size: CGFloat = 3
    ) -> PKStroke {
        let values = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: values, creationDate: time),
            transform: transform, mask: mask, randomSeed: 17)
    }
}
#endif

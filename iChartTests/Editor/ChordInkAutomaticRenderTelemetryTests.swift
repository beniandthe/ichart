#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkAutomaticRenderTelemetryTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)

    func testPartialRenderAccountsForBothArchivedAndIntentionallyRetainedSource() throws {
        let f = try fixture()
        let result = assess(f)
        XCTAssertEqual(result.outcome, "passed")
        XCTAssertEqual(result.reason, "render_complete")
        XCTAssertEqual(result.expectedCount, 2)
        XCTAssertEqual(result.actualCount, 2)
        let values = try XCTUnwrap(properties(f))
        XCTAssertEqual(values["source_stroke_count"], .int(2))
        XCTAssertEqual(values["consumed_stroke_count"], .int(1))
        XCTAssertEqual(values["retained_stroke_count"], .int(1))
    }

    func testFullAutomaticRenderHasNoRetainedSource() throws {
        let f = try fixture(elapsed: 2)
        XCTAssertEqual(f.outcome.drawing.strokes.count, 0)
        XCTAssertEqual(assess(f).outcome, "passed")
        let values = try XCTUnwrap(properties(f))
        XCTAssertEqual(values["consumed_stroke_count"], .int(2))
        XCTAssertEqual(values["retained_stroke_count"], .int(0))
    }

    func testMissingRetainedStrokeIsAContentViolation() throws {
        let f = try fixture()
        let result = assess(f, drawing: PKDrawing())
        XCTAssertEqual(result.reason, "render_retained_source_changed")
        XCTAssertEqual(result.contentMatches, false)
        XCTAssertEqual(result.outcome, "violated")
    }

    func testMovedRetainedStrokeIsDetectedEvenWhenStrokeAndPointCountsMatch() throws {
        let f = try fixture()
        let moved = f.outcome.drawing.transformed(using: CGAffineTransform(translationX: 20, y: 0))
        let result = assess(f, drawing: moved)
        XCTAssertEqual(result.reason, "render_retained_source_changed")
        XCTAssertEqual(result.expectedCount, result.actualCount)
        XCTAssertEqual(result.contentMatches, false)
    }

    func testDuplicatedRetainedStrokeIsNotConfusedWithConsumedInkLeftBehind() throws {
        let f = try fixture()
        let duplicated = PKDrawing(strokes: f.outcome.drawing.strokes + f.outcome.drawing.strokes)
        XCTAssertEqual(assess(f, drawing: duplicated).reason, "render_retained_source_changed")
    }

    func testConsumedStrokeStillOnLiveCanvasIsSeparateCleanupFailure() throws {
        let f = try fixture()
        let result = assess(f, drawing: f.source)
        XCTAssertEqual(result.reason, "render_consumed_source_remaining")
        XCTAssertEqual(result.expectedCount, 1)
        XCTAssertEqual(result.actualCount, 2)
        XCTAssertEqual(result.contentMatches, false)
    }

    func testPersistedRetainedSourceMustMatchLiveRetention() throws {
        let f = try fixture()
        var broken = f.outcome.chart
        broken.pageHandwrittenChordData = nil
        let changed = replacement(f, chart: broken)
        let result = ChordInkAutomaticRenderTelemetry.assessment(originalChart: f.chart, state: f.state,
            sourceDrawing: f.source, outcome: changed, observedChart: broken, observedDrawing: f.outcome.drawing)
        XCTAssertEqual(result.reason, "render_retained_source_changed")
    }

    func testMissingAndMutatedCommittedSourceReceiptsAreDetected() throws {
        let f = try fixture()
        for receipt in [nil, Optional(PKDrawing(strokes: [stroke(300)]).dataRepresentation())] {
            var broken = f.outcome.chart
            broken.systems[0].measures[0].chordEvents[0].sourceInkData = receipt
            let changed = replacement(f, chart: broken)
            let result = ChordInkAutomaticRenderTelemetry.assessment(originalChart: f.chart, state: f.state,
                sourceDrawing: f.source, outcome: changed, observedChart: broken, observedDrawing: f.outcome.drawing)
            XCTAssertEqual(result.reason, "render_source_missing")
            XCTAssertEqual(result.contentMatches, false)
        }
    }

    func testApplyingADifferentChartFromPreparedOutcomeCannotPass() throws {
        let f = try fixture()
        XCTAssertEqual(assess(f, chart: f.chart).reason, "render_source_missing")
    }

    func testSafeRefusalAndRefusalThatMutatesCanvasHaveDifferentOutcomes() throws {
        let f = try fixture()
        let safe = ChordInkAutomaticRenderTelemetry.assessment(originalChart: f.chart, state: f.state,
            sourceDrawing: f.source, outcome: nil, observedChart: f.chart, observedDrawing: f.source)
        XCTAssertEqual(safe.outcome, "protected_rejection")
        XCTAssertEqual(safe.contentMatches, true)
        let missing = ChordInkAutomaticRenderTelemetry.assessment(originalChart: f.chart, state: f.state,
            sourceDrawing: f.source, outcome: nil, observedChart: f.chart, observedDrawing: PKDrawing())
        XCTAssertEqual(missing.reason, "render_rejected_mutated")
        XCTAssertEqual(missing.outcome, "violated")
    }

    func testRefusalThatMutatesChartIsDetectedWithUnchangedInk() throws {
        let f = try fixture()
        var mutated = f.chart
        mutated.title = "Changed by rejected operation"
        let result = ChordInkAutomaticRenderTelemetry.assessment(originalChart: f.chart, state: f.state,
            sourceDrawing: f.source, outcome: nil, observedChart: mutated, observedDrawing: f.source)
        XCTAssertEqual(result.reason, "render_rejected_mutated")
    }

    func testRepeatedIdenticalStrokeOwnershipIsCountedWithMultiplicity() throws {
        var chart = makeChart()
        let originalChart = chart
        let drawing = normalized([stroke(10), stroke(10)])
        let state = makeState(chart, drawing)
        let sourceData = PKDrawing(strokes: [drawing.strokes[0]]).dataRepresentation()
        let eventID = try XCTUnwrap(chart.appendRecognizedChordEvent(
            ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil),
            rawInput: nil, to: chart.measures[0].id, atFraction: 0.3, sourceInkData: sourceData))
        _ = chart.setPageHandwrittenChordDrawing(sourceData, coordinateSpace: .init(size: pageSize),
            assumesNormalizedPersistentInk: true)
        var remaining = state
        remaining.draftChords.removeFirst()
        let outcome = ChordInkDraftRenderCoordinator.AutomaticOutcome(chart: chart,
            drawing: PKDrawing(strokes: [drawing.strokes[1]]), remainingState: remaining,
            result: .init(renderedChordIDs: [eventID], renderedBarlineIDs: [], unresolvedDraftIDs: []),
            consumedDraftIDs: [state.draftChords[0].id])
        let result = ChordInkAutomaticRenderTelemetry.assessment(originalChart: originalChart,
            state: state, sourceDrawing: drawing, outcome: outcome,
            observedChart: chart, observedDrawing: outcome.drawing)
        XCTAssertEqual(result.outcome, "passed")
        let leftover = ChordInkAutomaticRenderTelemetry.assessment(originalChart: originalChart,
            state: state, sourceDrawing: drawing, outcome: outcome,
            observedChart: chart, observedDrawing: drawing)
        XCTAssertEqual(leftover.reason, "render_consumed_source_remaining")
    }

    func testOrdinaryStructuralBarlineIsIntentionalConsumptionWithoutArchive() {
        let chart = makeChart()
        let source = normalized([stroke(10)])
        let barline = DraftBarline(measureID: chart.measures[0].id, measureIndex: 1, fraction: 0.5,
            sourceStrokeIndex: 0, metrics: .init(height: 50, width: 0, angleDegreesFromVertical: 0,
                straightness: 1, laneCoverage: 0.9), kind: .single)
        let state = ChordPreviewState(draftBarlines: [barline], layoutPageSize: pageSize)
        let outcome = ChordInkDraftRenderCoordinator.AutomaticOutcome(chart: chart, drawing: PKDrawing(),
            remainingState: .init(), result: .init(renderedChordIDs: [], renderedBarlineIDs: [barline.id], unresolvedDraftIDs: []),
            consumedDraftIDs: [barline.id])
        XCTAssertEqual(ChordInkAutomaticRenderTelemetry.assessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: outcome, observedChart: chart, observedDrawing: PKDrawing()).outcome, "passed")
    }

    func testDiagnosticsOffNeverEvaluatesSourceOrObservedClosures() throws {
        let f = try fixture()
        var inspected = 0
        func source() -> PKDrawing { inspected += 1; return f.source }
        func chart() -> Chart { inspected += 1; return f.chart }
        XCTAssertNil(ChordInkAutomaticRenderTelemetry.transactionProperties(isEnabled: false,
            originalChart: f.chart, state: f.state, sourceDrawing: source(), outcome: f.outcome,
            observedChart: chart(), observedDrawing: source(), mode: .automatic))
        XCTAssertEqual(inspected, 0)
    }

    func testPointComparisonRunsOnUtilityQueueWithoutHoppingToMainActor() async throws {
        let f = try fixture()
        let compared = expectation(description: "Automatic source assessment completed off main thread")
        DispatchQueue.global(qos: .utility).async {
            var inspectedOffMain = false
            func source() -> PKDrawing {
                inspectedOffMain = !Thread.isMainThread
                return f.source
            }
            let values = ChordInkAutomaticRenderTelemetry.transactionProperties(isEnabled: true,
                originalChart: f.chart, state: f.state, sourceDrawing: source(), outcome: f.outcome,
                observedChart: f.outcome.chart, observedDrawing: f.outcome.drawing, mode: .automatic)
            XCTAssertTrue(inspectedOffMain)
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(values?["outcome"], .string("passed"))
            compared.fulfill()
        }
        await fulfillment(of: [compared], timeout: 5)
    }

    func testCompletionFrictionRequiresSettledForegroundIdleAndPositiveRetainedSource() throws {
        let chart = makeChart()
        let valid = completion(chart: chart, reason: .noRead)
        XCTAssertEqual(valid?["contract_id"], .string("ink.automatic_render_completion"))
        XCTAssertEqual(valid?["outcome"], .string("protected_rejection"))
        XCTAssertEqual(valid?["reason"], .string("automatic_no_read"))
        XCTAssertNil(valid?["content_matches"], "Workflow friction does not assert preservation or loss")
        XCTAssertNil(completion(chart: chart, reason: .noRead, foreground: false))
        XCTAssertNil(completion(chart: chart, reason: .noRead, enabled: false))
        XCTAssertNil(completion(chart: chart, reason: .noRead, activeDuration: 2.9))
        XCTAssertNil(completion(chart: chart, reason: .noRead, idleDuration: 2.9))
        XCTAssertNil(completion(chart: chart, reason: .noRead, count: 0))
        XCTAssertNil(completion(chart: chart, reason: .noRead, madeProgress: true))
        XCTAssertNil(completion(chart: chart, reason: .noRead, phase: .reading))
    }

    func testWaitingReadingRestoredRepeatAndSourceRefreshDoNotCreateFriction() {
        for reason: ChordInkAutomaticRenderReason in [.waiting, .reading, .restoredInk, .needsSourceRefresh] {
            XCTAssertNil(completion(chart: makeChart(), reason: reason))
        }
    }

    func testSupportedCompletionReasonsHaveBoundedContentFreeCodes() {
        let reasons: [ChordInkAutomaticRenderReason] = [.noRead, .recognitionReview, .needsSpace,
            .placementUnavailable, .unrepresentedInk, .adjacentWriting]
        for reason in reasons {
            let values = completion(chart: makeChart(), reason: reason)
            XCTAssertNotNil(values)
            XCTAssertNil(values?["draft_id"])
            XCTAssertNil(values?["chord_text"])
            XCTAssertNil(values?["drawing_data"])
        }
    }

    func testAdmissionDeduplicatesSameRevisionAndResetsOnNewSourceOrChart() {
        var admission = ChordInkAutomaticRenderTelemetry.Admission()
        let chart = UUID()
        XCTAssertTrue(admission.admit(chartID: chart, sourceRevision: 1, mode: .automatic, reason: "render_unresolved"))
        XCTAssertFalse(admission.admit(chartID: chart, sourceRevision: 1, mode: .automatic, reason: "render_unresolved"))
        XCTAssertTrue(admission.admit(chartID: chart, sourceRevision: 1, mode: .reviewedAutomatic, reason: "render_unresolved"))
        XCTAssertTrue(admission.admit(chartID: chart, sourceRevision: 2, mode: .automatic, reason: "render_unresolved"))
        XCTAssertTrue(admission.admit(chartID: UUID(), sourceRevision: 2, mode: .automatic, reason: "render_unresolved"))
        admission.reset()
        XCTAssertTrue(admission.admit(chartID: chart, sourceRevision: 1, mode: .automatic, reason: "render_unresolved"))
    }

    func testNativeGeneratedSanitizedEnvelopesProvideEndToEndFixtureAttachment() throws {
        let f = try fixture()
        let installation = UUID().uuidString.lowercased()
        let session = UUID().uuidString.lowercased()
        var cases: [[String: Any]] = []
        func add(_ name: String, _ input: IChartTelemetryProperties?, createsTask: Bool) throws {
            guard var input else {
                cases.append(["fixture": name, "event_emitted": false, "creates_task": false])
                return
            }
            input["build_source"] = .string("debug_build")
            let values = IChartTelemetryPrivacy.sanitizedProperties(input, forEventName: "feature.contract_checked")
            XCTAssertTrue(IChartTelemetryPrivacy.hasRequiredContractFields(values))
            XCTAssertEqual(values, input)
            let scalar = try JSONSerialization.jsonObject(with: JSONEncoder().encode(values))
            cases.append(["fixture": name, "event_emitted": true, "creates_task": createsTask,
                "event": ["client_event_id": UUID().uuidString.lowercased(), "event_name": "feature.contract_checked",
                    "installation_id": installation, "session_id": session, "platform": "iPadOS",
                    "app_version": "internal-verification", "build_number": "0", "properties": scalar]])
        }
        try add("partial_pass", properties(f), createsTask: false)
        try add("retained_moved", properties(f,
            drawing: f.outcome.drawing.transformed(using: CGAffineTransform(translationX: 20, y: 0))), createsTask: true)
        try add("retained_lost", properties(f, drawing: PKDrawing()), createsTask: true)
        try add("consumed_remaining", properties(f, drawing: f.source), createsTask: true)
        try add("safe_refusal", ChordInkAutomaticRenderTelemetry.transactionProperties(isEnabled: true,
            originalChart: f.chart, state: f.state, sourceDrawing: f.source, outcome: nil,
            observedChart: f.chart, observedDrawing: f.source, mode: .automatic), createsTask: false)
        try add("settled_no_read", completion(chart: f.chart, reason: .noRead), createsTask: true)
        for reason: ChordInkAutomaticRenderReason in [.waiting, .reading, .restoredInk] {
            try add("control_" + reason.rawValue, completion(chart: f.chart, reason: reason), createsTask: false)
        }
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "scope": "Native synthetic fixtures; content-free telemetry only", "cases": cases], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "automatic-render-telemetry-native-e2e-fixtures"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }

    private struct Fixture {
        var chart: Chart
        var source: PKDrawing
        var state: ChordPreviewState
        var outcome: ChordInkDraftRenderCoordinator.AutomaticOutcome
    }

    private func fixture(elapsed: TimeInterval = 0.4) throws -> Fixture {
        let chart = makeChart()
        let source = normalized([stroke(10), stroke(110)])
        let state = makeState(chart, source)
        let outcome = try XCTUnwrap(ChordInkDraftRenderCoordinator.prepareAutomatic(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: .init(size: pageSize), now: inputAt.addingTimeInterval(elapsed),
            lastInputAt: inputAt, isUsingTool: false))
        return Fixture(chart: chart, source: source, state: state, outcome: outcome)
    }

    private func assess(_ f: Fixture, chart: Chart? = nil, drawing: PKDrawing? = nil) -> LeadSheetInkFeatureContract.Assessment {
        ChordInkAutomaticRenderTelemetry.assessment(originalChart: f.chart, state: f.state, sourceDrawing: f.source,
            outcome: f.outcome, observedChart: chart ?? f.outcome.chart, observedDrawing: drawing ?? f.outcome.drawing)
    }

    private func properties(_ f: Fixture, drawing: PKDrawing? = nil) -> IChartTelemetryProperties? {
        ChordInkAutomaticRenderTelemetry.transactionProperties(isEnabled: true, originalChart: f.chart,
            state: f.state, sourceDrawing: f.source, outcome: f.outcome, observedChart: f.outcome.chart,
            observedDrawing: drawing ?? f.outcome.drawing, mode: .automatic)
    }

    private func replacement(_ f: Fixture, chart: Chart) -> ChordInkDraftRenderCoordinator.AutomaticOutcome {
        .init(chart: chart, drawing: f.outcome.drawing, remainingState: f.outcome.remainingState,
            result: f.outcome.result, consumedDraftIDs: f.outcome.consumedDraftIDs)
    }

    private func completion(chart: Chart, reason: ChordInkAutomaticRenderReason,
        foreground: Bool = true, enabled: Bool = true, activeDuration: TimeInterval = 3,
        idleDuration: TimeInterval = 3, count: Int = 2, madeProgress: Bool = false,
        phase: ChordInkAutomaticActivity.Phase = .settled) -> IChartTelemetryProperties? {
        let activity = ChordInkAutomaticActivity(chartID: chart.id, sourceRevision: 5, hasSourceInk: true,
            phase: phase, pendingTargetCount: 0, inputAt: inputAt, feedback: .init(globalReason: reason))
        return ChordInkAutomaticRenderTelemetry.completionProperties(isEnabled: enabled,
            chart: chart, mode: .automatic, activity: activity, now: inputAt.addingTimeInterval(idleDuration),
            isForeground: foreground, foregroundObservationDuration: activeDuration, remainingStrokeCount: count,
            madeProgress: madeProgress)
    }

    private func makeChart() -> Chart {
        var chart = Chart.draft(title: "Synthetic telemetry fixture", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: "Synthetic telemetry fixture", key: .cMajor,
            meter: .init(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func makeState(_ chart: Chart, _ drawing: PKDrawing) -> ChordPreviewState {
        let drafts = drawing.strokes.enumerated().map { index, stroke in
            var input = ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: Double(index + 1) / Double(drawing.strokes.count + 1), layoutPageSize: pageSize,
                drawingData: PKDrawing(strokes: [stroke]).dataRepresentation(), candidateTexts: ["C"],
                bestCandidateText: "C", confidence: 4.5, strokeCount: 1,
                recognitionDecision: ChordInkRecognitionDecision(action: .trusted, acceptedText: "C",
                    reason: "Synthetic trusted fixture", isCloseRace: false, competingCandidateText: nil, confidenceGap: nil))
            input.targetLifecycle = ChordInkRecognitionTargetLifecycle(generationID: UUID(), anchor: input.anchor,
                ownership: .init(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: [stroke]))), stage: .frozen)
            return ChordInkDraft(input: input)
        }
        return ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
    }

    private func normalized(_ strokes: [PKStroke]) -> PKDrawing {
        LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes))
    }

    private func stroke(_ x: CGFloat) -> PKStroke {
        let points = [CGPoint(x: x, y: 10), CGPoint(x: x + 14, y: 30)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: .init(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: .init(.pen, color: .black),
            path: .init(controlPoints: points, creationDate: inputAt), transform: .identity, mask: nil, randomSeed: 17)
    }
}
#endif

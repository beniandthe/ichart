#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Synthetic source comparisons and callback timing only. These checks make
/// no claim about recognition accuracy or PencilKit's final rasterized pixels.
@MainActor
final class LeadSheetInkAuthoringTelemetryTests: XCTestCase {
    func testAppendingSourcePreservesEveryCompletedBaselineFragment() throws {
        let baseline = PKDrawing(strokes: [stroke(10), stroke(70)])
        let current = PKDrawing(strokes: baseline.strokes + [stroke(140)])
        let values = try XCTUnwrap(source(baseline, current))
        XCTAssertEqual(values["contract_id"], .string("ink.authoring_integrity"))
        XCTAssertEqual(values["operation"], .string("write"))
        XCTAssertEqual(values["outcome"], .string("passed"))
        XCTAssertEqual(values["reason"], .string("authoring_source_preserved"))
        XCTAssertEqual(values["expected_count"], .int(2))
        XCTAssertEqual(values["actual_count"], .int(2))
        XCTAssertEqual(values["source_stroke_count"], .int(3))
        XCTAssertEqual(values["retained_stroke_count"], .int(2))
        XCTAssertEqual(values["content_matches"], .bool(true))
    }

    func testLostCompletedSourceIsDetectedWhileNewInkIsPresent() throws {
        let baseline = PKDrawing(strokes: [stroke(10), stroke(70)])
        let current = PKDrawing(strokes: [baseline.strokes[1], stroke(140)])
        let values = try XCTUnwrap(source(baseline, current))
        XCTAssertEqual(values["outcome"], .string("violated"))
        XCTAssertEqual(values["reason"], .string("authoring_completed_source_missing"))
        XCTAssertEqual(values["expected_count"], .int(2))
        XCTAssertEqual(values["actual_count"], .int(1))
        XCTAssertEqual(values["content_matches"], .bool(false))
        XCTAssertEqual(current.strokes.count, baseline.strokes.count,
            "Equal stroke counts must not conceal replacement of completed source")
    }

    func testMovedCompletedSourceWithEqualStrokeAndPointCountsIsDetected() throws {
        let baseline = PKDrawing(strokes: [stroke(10), stroke(70)])
        let current = baseline.transformed(using: CGAffineTransform(translationX: 3, y: 0))
        let values = try XCTUnwrap(source(baseline, current))
        XCTAssertEqual(values["outcome"], .string("violated"))
        XCTAssertEqual(values["actual_count"], .int(0))
        XCTAssertEqual(values["content_matches"], .bool(false))
        XCTAssertEqual(current.strokes.reduce(0) { $0 + $1.path.count },
            baseline.strokes.reduce(0) { $0 + $1.path.count })
    }

    func testBaselineMultiplicityRequiresBothIdenticalCompletedStrokes() throws {
        let repeated = stroke(10)
        let baseline = PKDrawing(strokes: [repeated, repeated])
        let missing = try XCTUnwrap(source(baseline, PKDrawing(strokes: [repeated, stroke(90)])))
        XCTAssertEqual(missing["expected_count"], .int(2))
        XCTAssertEqual(missing["actual_count"], .int(1))
        XCTAssertEqual(missing["outcome"], .string("violated"))
        let intact = try XCTUnwrap(source(baseline, PKDrawing(strokes: [repeated, repeated, stroke(90)])))
        XCTAssertEqual(intact["actual_count"], .int(2))
        XCTAssertEqual(intact["outcome"], .string("passed"))
    }

    func testMaskedVisibleFragmentsRemainComparableWhenNewInkIsAppended() throws {
        let mask = UIBezierPath()
        mask.append(UIBezierPath(rect: CGRect(x: -2, y: -8, width: 16, height: 16)))
        mask.append(UIBezierPath(rect: CGRect(x: 36, y: -8, width: 16, height: 16)))
        let points = stride(from: 0, through: 50, by: 10).map { CGPoint(x: CGFloat($0), y: 0) }
        let baseline = PKDrawing(strokes: [stroke(points: points, mask: mask)])
        let values = try XCTUnwrap(source(baseline, PKDrawing(strokes: baseline.strokes + [stroke(100)])))
        XCTAssertEqual(values["outcome"], .string("passed"))
        XCTAssertEqual(values["content_matches"], .bool(true))
        XCTAssertEqual(values["expected_count"], values["actual_count"])
        XCTAssertEqual(values["retained_stroke_count"], .int(1),
            "Raw stroke-object accounting stays separate from visible fragments")
    }

    func testChangingInkColorAndTypeWithoutChangingSourceGeometryIsNotLoss() throws {
        let original = stroke(10)
        let normalized = PKStroke(ink: PKInk(.marker, color: .red), path: original.path,
            transform: original.transform, mask: original.mask, randomSeed: original.randomSeed)
        let values = try XCTUnwrap(source(PKDrawing(strokes: [original]), PKDrawing(strokes: [normalized, stroke(90)])))
        XCTAssertEqual(values["outcome"], .string("passed"))
        XCTAssertEqual(values["content_matches"], .bool(true))
    }

    func testNoKnownCompletedBaselineDoesNotInventPassingCoverage() {
        XCTAssertNil(source(PKDrawing(), PKDrawing(strokes: [stroke(10)])))
    }

    func testFullyMaskedBaselineRemainsUnknownRatherThanInventingVisibleCoverage() {
        let hiddenMask = UIBezierPath(rect: CGRect(x: 500, y: 500, width: 20, height: 20))
        let baseline = PKDrawing(strokes: [stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)],
            mask: hiddenMask)])
        XCTAssertNil(source(baseline, PKDrawing(strokes: baseline.strokes + [stroke(80)])))
    }

    func testDiagnosticsOffAndIncomparableContextDoNotInspectSourceClosures() {
        let chart = chart()
        var inspections = 0
        func drawing() -> PKDrawing { inspections += 1; return PKDrawing(strokes: [stroke(10)]) }
        XCTAssertNil(LeadSheetInkAuthoringTelemetry.sourceProperties(isEnabled: false, chart: chart,
            scope: "chords", completedBaseline: drawing(), currentDrawing: drawing(), isComparable: true))
        XCTAssertNil(LeadSheetInkAuthoringTelemetry.sourceProperties(isEnabled: true, chart: chart,
            scope: "chords", completedBaseline: drawing(), currentDrawing: drawing(), isComparable: false))
        XCTAssertNil(LeadSheetInkAuthoringTelemetry.sourceProperties(isEnabled: true, chart: chart,
            scope: "arbitrary private text", completedBaseline: drawing(), currentDrawing: drawing(), isComparable: true))
        XCTAssertEqual(inspections, 0)
    }

    func testSourceComparisonRunsOnUtilityQueueWithoutMainActorHop() async {
        let fixtureChart = chart()
        let baseline = PKDrawing(strokes: [stroke(10)])
        let current = PKDrawing(strokes: baseline.strokes + [stroke(90)])
        let completed = expectation(description: "Completed source checked off main thread")
        DispatchQueue.global(qos: .utility).async {
            func drawing(_ value: PKDrawing) -> PKDrawing {
                XCTAssertFalse(Thread.isMainThread)
                return value
            }
            let values = LeadSheetInkAuthoringTelemetry.sourceProperties(isEnabled: true, chart: fixtureChart,
                scope: "chords", completedBaseline: drawing(baseline), currentDrawing: drawing(current), isComparable: true)
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(values?["outcome"], .string("passed"))
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
    }

    func testSourcePropertiesContainOnlyTechnicalComparisons() throws {
        let fixtureChart = chart()
        let baseline = PKDrawing(strokes: [stroke(10)])
        let values = try XCTUnwrap(LeadSheetInkAuthoringTelemetry.sourceProperties(isEnabled: true,
            chart: fixtureChart, scope: "page", completedBaseline: baseline, currentDrawing: baseline,
            isComparable: true, operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!))
        let text = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        XCTAssertFalse(text.contains(fixtureChart.title))
        XCTAssertFalse(text.lowercased().contains(fixtureChart.id.uuidString.lowercased()))
        for key in ["drawing_data", "raw_ink", "points", "chord_text", "chart_title", "chart_id"] {
            XCTAssertNil(values[key])
        }
        XCTAssertEqual(values["scope"], .string("page"))
    }

    func testZeroCallbacksIsUnknownEvenWhenPassingCoverageWasRequested() {
        let window = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        XCTAssertNil(responsiveness(window, allowsPassing: true))
        XCTAssertEqual(window.observedCallbackCount, 0)
        XCTAssertEqual(window.slowCallbackCount, 0)
    }

    func testNormalCallbacksDoNotEmitUnsampledPassOrInventStall() throws {
        var window = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        for value in [0, 3.5, 99.999] { window.observe(durationMilliseconds: value) }
        XCTAssertNil(responsiveness(window))
        let sampled = try XCTUnwrap(responsiveness(window, allowsPassing: true))
        XCTAssertEqual(sampled["contract_id"], .string("ink.authoring_responsiveness"))
        XCTAssertEqual(sampled["operation"], .string("write"))
        XCTAssertEqual(sampled["reason"], .string("authoring_responsive"))
        XCTAssertEqual(sampled["outcome"], .string("passed"))
        XCTAssertEqual(window.observedCallbackCount, 3)
        XCTAssertEqual(window.slowCallbackCount, 0)
        XCTAssertEqual(window.maximumDurationMilliseconds, 99.999, accuracy: 0.000001)
    }

    func testThreeOneHundredMillisecondCallbacksEmitFriction() throws {
        var window = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        for value in [100, 149.25, 100] { window.observe(durationMilliseconds: value) }
        let values = try XCTUnwrap(responsiveness(window))
        XCTAssertEqual(values["outcome"], .string("violated"))
        XCTAssertEqual(values["reason"], .string("authoring_callback_stalled"))
        XCTAssertEqual(values["expected_count"], .int(0))
        XCTAssertEqual(values["actual_count"], .int(3))
        XCTAssertEqual(values["duration_ms"], .double(149.25))
        XCTAssertNil(values["content_matches"], "Latency does not assert source loss or rasterization failure")
    }

    func testTwoSlowCallbacksBelowSevereThresholdRemainBelowStallGate() {
        var window = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        window.observe(durationMilliseconds: 100)
        window.observe(durationMilliseconds: 499.999)
        XCTAssertNil(responsiveness(window))
        XCTAssertEqual(window.slowCallbackCount, 2)
    }

    func testSingleFiveHundredMillisecondCallbackEmitsStall() throws {
        var window = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        window.observe(durationMilliseconds: 500)
        let values = try XCTUnwrap(responsiveness(window))
        XCTAssertEqual(values["actual_count"], .int(1))
        XCTAssertEqual(values["duration_ms"], .double(500))
        XCTAssertEqual(values["reason"], .string("authoring_callback_stalled"))
    }

    func testInvalidCallbackDurationsNeverBecomeMeasuredZeroOrFailure() {
        var window = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        for value in [-1, -.infinity, .infinity, .nan, 86_400_000.001] {
            window.observe(durationMilliseconds: value)
        }
        XCTAssertEqual(window.observedCallbackCount, 0)
        XCTAssertEqual(window.slowCallbackCount, 0)
        XCTAssertEqual(window.maximumDurationMilliseconds, 0)
        XCTAssertNil(responsiveness(window, allowsPassing: true))
        window.observe(durationMilliseconds: 12)
        window.observe(durationMilliseconds: .nan)
        XCTAssertEqual(window.observedCallbackCount, 1)
        XCTAssertEqual(window.maximumDurationMilliseconds, 12)
    }

    func testDisabledOrInvalidScopeResponsivenessDoesNotEmit() {
        var window = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        window.observe(durationMilliseconds: 600)
        XCTAssertNil(LeadSheetInkAuthoringTelemetry.responsivenessProperties(isEnabled: false,
            chart: chart(), scope: "chords", window: window))
        XCTAssertNil(LeadSheetInkAuthoringTelemetry.responsivenessProperties(isEnabled: true,
            chart: chart(), scope: "freehand private label", window: window))
    }

    func testNativeAuthoringPropertiesProvideContentFreeEndToEndFixtureAttachment() throws {
        let fixtureChart = chart()
        let baseline = PKDrawing(strokes: [stroke(10), stroke(70)])
        let appended = PKDrawing(strokes: baseline.strokes + [stroke(140)])
        let replaced = PKDrawing(strokes: [baseline.strokes[1], stroke(140)])
        let moved = baseline.transformed(using: CGAffineTransform(translationX: 3, y: 0))
        let installationID = UUID().uuidString.lowercased()
        let sessionID = UUID().uuidString.lowercased()
        var cases: [[String: Any]] = []
        func add(_ name: String, _ input: IChartTelemetryProperties?, createsTask: Bool) throws {
            guard var values = input else {
                cases.append(["fixture": name, "event_emitted": false, "creates_task": false])
                return
            }
            values["build_source"] = .string("debug_build")
            let scalars = try JSONSerialization.jsonObject(with: JSONEncoder().encode(values))
            cases.append(["fixture": name, "event_emitted": true, "creates_task": createsTask,
                "event": ["client_event_id": UUID().uuidString.lowercased(),
                    "event_name": "feature.contract_checked", "installation_id": installationID,
                    "session_id": sessionID, "app_version": "internal-verification",
                    "build_number": "0", "platform": "iPadOS", "properties": scalars]])
        }
        try add("source_append_pass", source(baseline, appended), createsTask: false)
        try add("source_missing", source(baseline, replaced), createsTask: true)
        try add("source_moved_same_counts", source(baseline, moved), createsTask: true)
        var repeatedSlow = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        for value in [100.0, 125.0, 100.0] { repeatedSlow.observe(durationMilliseconds: value) }
        try add("authoring_slow_repeated", responsiveness(repeatedSlow), createsTask: true)
        var singleStall = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        singleStall.observe(durationMilliseconds: 500)
        try add("authoring_single_stall", responsiveness(singleStall), createsTask: true)
        var responsive = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        responsive.observe(durationMilliseconds: 4)
        try add("sampled_responsive_pass", responsiveness(responsive, allowsPassing: true), createsTask: false)
        try add("incomparable_control", LeadSheetInkAuthoringTelemetry.sourceProperties(isEnabled: true,
            chart: fixtureChart, scope: "chords", completedBaseline: baseline, currentDrawing: replaced,
            isComparable: false), createsTask: false)
        try add("diagnostics_off_control", LeadSheetInkAuthoringTelemetry.sourceProperties(isEnabled: false,
            chart: fixtureChart, scope: "chords", completedBaseline: baseline, currentDrawing: replaced,
            isComparable: true), createsTask: false)
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "scope": "Native synthetic authoring properties; no source content", "cases": cases],
            options: [.prettyPrinted, .sortedKeys])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(fixtureChart.title))
        XCTAssertFalse(text.lowercased().contains(fixtureChart.id.uuidString.lowercased()))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "authoring-telemetry-native-e2e-fixtures"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }

    func testStableExpectedAuthoringCanvasHiddenWithSourceIsVisibilityViolation() throws {
        let values = try XCTUnwrap(visibility(hidden: true))
        XCTAssertEqual(values["contract_id"], .string("ink.live_canvas_visibility"))
        XCTAssertEqual(values["operation"], .string("write"))
        XCTAssertEqual(values["outcome"], .string("violated"))
        XCTAssertEqual(values["reason"], .string("authoring_canvas_invisible"))
        XCTAssertEqual(values["expected_count"], .int(1))
        XCTAssertEqual(values["actual_count"], .int(0))
        XCTAssertEqual(values["content_matches"], .bool(false))
        XCTAssertEqual(values["source_stroke_count"], .int(2))
        XCTAssertEqual(values["duration_ms"], .double(500))
    }

    func testCanvasTransparencyThresholdIsInclusiveAndSeparateFromVisibleSampling() throws {
        for alpha in [0.0, 0.009, 0.01] {
            let values = try XCTUnwrap(visibility(alpha: alpha))
            XCTAssertEqual(values["outcome"], .string("violated"))
            XCTAssertEqual(values["reason"], .string("authoring_canvas_invisible"))
        }
        XCTAssertNil(visibility(alpha: 0.010001))
        let visible = try XCTUnwrap(visibility(alpha: 0.010001, allowsPassing: true))
        XCTAssertEqual(visible["outcome"], .string("passed"))
        XCTAssertEqual(visible["reason"], .string("authoring_canvas_visible"))
        XCTAssertEqual(visible["actual_count"], .int(1))
        XCTAssertEqual(visible["content_matches"], .bool(true))
    }

    func testVisibleAuthoringCanvasEmitsOnlyRequestedSampledCoverage() throws {
        XCTAssertNil(visibility())
        let values = try XCTUnwrap(visibility(allowsPassing: true))
        XCTAssertEqual(values["outcome"], .string("passed"))
        XCTAssertEqual(values["expected_count"], .int(1))
        XCTAssertEqual(values["actual_count"], .int(1))
    }

    func testVisibilityRequiresKnownStableForegroundAuthoringContext() {
        XCTAssertNil(visibility(enabled: false, hidden: true))
        XCTAssertNil(visibility(expected: false, hidden: true))
        XCTAssertNil(visibility(comparable: false, hidden: true))
        XCTAssertNil(visibility(foreground: false, hidden: true))
        XCTAssertNil(visibility(hasWindow: false, hidden: true))
        XCTAssertNil(visibility(finiteGeometry: false, hidden: true))
        XCTAssertNil(visibility(intersectsViewport: false, hidden: true))
        XCTAssertNil(visibility(stableCount: 1, hidden: true))
        XCTAssertNil(visibility(stableDuration: 0.499999, hidden: true))
        XCTAssertNil(visibility(scope: "private unsupported scope", hidden: true))
    }

    func testVisibilityInvalidCountsDurationsAndAlphaRemainUnknown() {
        for count in [0, -1, 1_000_000_000_001] {
            XCTAssertNil(visibility(sourceCount: count, hidden: true))
        }
        for count in [0, -1, 1_000_000_000_001] {
            XCTAssertNil(visibility(stableCount: count, hidden: true))
        }
        for duration in [-1.0, .nan, .infinity, -.infinity, 86_400.001] {
            XCTAssertNil(visibility(stableDuration: duration, hidden: true))
        }
        for alpha in [-0.001, 1.001, .nan, .infinity, -.infinity] {
            XCTAssertNil(visibility(hidden: true, alpha: alpha))
        }
    }

    func testVisibilityEnvelopeDoesNotContainGeometryContentOrRawChartIdentity() throws {
        let fixtureChart = chart()
        let values = try XCTUnwrap(LeadSheetInkAuthoringTelemetry.visibilityProperties(isEnabled: true,
            chart: fixtureChart, scope: "header", sourceStrokeCount: 2,
            expectsVisibleAuthoringCanvas: true, isComparable: true, isForeground: true, hasWindow: true,
            hasFiniteNonemptyGeometry: true, intersectsVisibleViewport: true, isHidden: true,
            alpha: 1, stableObservationCount: 2, stableDuration: 0.5))
        let text = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        XCTAssertFalse(text.contains(fixtureChart.title))
        XCTAssertFalse(text.lowercased().contains(fixtureChart.id.uuidString.lowercased()))
        for key in ["drawing_data", "points", "bounds", "frame", "viewport", "chart_id", "chord_text", "alpha"] {
            XCTAssertNil(values[key])
        }
        XCTAssertEqual(values["scope"], .string("header"))
    }

    func testNativeVisibilityPropertiesProvideContentFreeFixtureAttachment() throws {
        let installationID = UUID().uuidString.lowercased()
        let sessionID = UUID().uuidString.lowercased()
        var cases: [[String: Any]] = []
        func add(_ name: String, _ input: IChartTelemetryProperties?, createsTask: Bool) throws {
            guard var values = input else {
                cases.append(["fixture": name, "event_emitted": false, "creates_task": false])
                return
            }
            values["build_source"] = .string("debug_build")
            let scalar = try JSONSerialization.jsonObject(with: JSONEncoder().encode(values))
            cases.append(["fixture": name, "event_emitted": true, "creates_task": createsTask,
                "event": ["client_event_id": UUID().uuidString.lowercased(),
                    "event_name": "feature.contract_checked", "installation_id": installationID,
                    "session_id": sessionID, "app_version": "internal-verification", "build_number": "0",
                    "platform": "iPadOS", "properties": scalar]])
        }
        try add("visible_canvas_pass", visibility(allowsPassing: true), createsTask: false)
        try add("hidden_canvas", visibility(hidden: true), createsTask: true)
        try add("transparent_canvas", visibility(alpha: 0.01), createsTask: true)
        try add("zero_source_control", visibility(sourceCount: 0, hidden: true), createsTask: false)
        try add("outside_viewport_control", visibility(intersectsViewport: false, hidden: true), createsTask: false)
        try add("transition_control", visibility(stableDuration: 0.4, hidden: true), createsTask: false)
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "scope": "Native synthetic canvas configuration observations; not rasterization proof", "cases": cases],
            options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "live-canvas-visibility-native-e2e-fixtures"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }

    func testDeferredCoalescerKeepsOnlyActiveAndLatestPendingObservation() async {
        let coalescer = LeadSheetInkAuthoringTelemetry.DeferredObservationCoalescer()
        let recorder = AuthoringTelemetryCoalescerRecorder()
        let releaseFirst = DispatchSemaphore(value: 0)
        let firstStarted = expectation(description: "First observation is active")
        let submissionsFinished = expectation(description: "Pending observations submitted without waiting for work")
        let firstFinished = expectation(description: "First observation finished")
        let latestFinished = expectation(description: "Only latest pending observation ran")
        defer { releaseFirst.signal() }

        DispatchQueue.global(qos: .utility).async {
            coalescer.submit {
                recorder.begin(1)
                firstStarted.fulfill()
                XCTAssertEqual(releaseFirst.wait(timeout: .now() + 5), .success)
                recorder.end()
                coalescer.complete()
                firstFinished.fulfill()
            }
        }
        await fulfillment(of: [firstStarted], timeout: 5)
        DispatchQueue.global(qos: .utility).async {
            for id in [2, 3] {
                coalescer.submit {
                    recorder.begin(id)
                    XCTFail("Replaced pending observation must not run")
                    recorder.end()
                    coalescer.complete()
                }
            }
            coalescer.submit {
                recorder.begin(4)
                recorder.store(coalescer.coalescedObservationCount, for: "coalesced")
                recorder.end()
                coalescer.complete()
                latestFinished.fulfill()
            }
            submissionsFinished.fulfill()
        }
        await fulfillment(of: [submissionsFinished], timeout: 5)
        releaseFirst.signal()
        await fulfillment(of: [firstFinished, latestFinished], timeout: 5)
        XCTAssertEqual(recorder.snapshot.ids, [1, 4])
        XCTAssertEqual(recorder.snapshot.maximumActive, 1)
        XCTAssertEqual(recorder.snapshot.values["coalesced"], 2)
    }

    func testDeferredCoalescerRunsWorkOutsideLockAndAllowsReentrantCompletion() async {
        let coalescer = LeadSheetInkAuthoringTelemetry.DeferredObservationCoalescer()
        let recorder = AuthoringTelemetryCoalescerRecorder()
        let completed = expectation(description: "Reentrant work and subsequent fresh submission complete")
        completed.expectedFulfillmentCount = 3
        DispatchQueue.global(qos: .utility).async {
            coalescer.complete() // An idle completion is harmless.
            coalescer.submit {
                recorder.begin(1)
                XCTAssertEqual(coalescer.coalescedObservationCount, 0)
                coalescer.submit {
                    recorder.begin(2)
                    XCTAssertEqual(coalescer.coalescedObservationCount, 0)
                    recorder.end()
                    coalescer.complete()
                    completed.fulfill()
                }
                recorder.end()
                coalescer.complete()
                completed.fulfill()
            }
            coalescer.submit {
                recorder.begin(3)
                XCTAssertEqual(coalescer.coalescedObservationCount, 0)
                recorder.end()
                coalescer.complete()
                completed.fulfill()
            }
            coalescer.complete()
        }
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(recorder.snapshot.ids, [1, 2, 3])
        XCTAssertEqual(recorder.snapshot.maximumActive, 1)
    }

    func testReplacingPendingObservationReleasesCapturedSnapshotOutsideLock() async {
        let coalescer = LeadSheetInkAuthoringTelemetry.DeferredObservationCoalescer()
        let recorder = AuthoringTelemetryCoalescerRecorder()
        let releaseFirst = DispatchSemaphore(value: 0)
        let firstStarted = expectation(description: "Initial observation blocks on utility queue")
        let replacementFinished = expectation(description: "Pending snapshot replaced")
        let snapshotReleased = expectation(description: "Replaced snapshot released outside coalescer lock")
        let latestFinished = expectation(description: "Replacement observation ran")
        defer { releaseFirst.signal() }
        DispatchQueue.global(qos: .utility).async {
            coalescer.submit {
                firstStarted.fulfill()
                XCTAssertEqual(releaseFirst.wait(timeout: .now() + 5), .success)
                coalescer.complete()
            }
        }
        await fulfillment(of: [firstStarted], timeout: 5)
        DispatchQueue.global(qos: .utility).async {
            var snapshot: AuthoringTelemetrySnapshotLifetimeProbe? = .init {
                // This getter takes the same lock as submit. Releasing a
                // capture while that lock is held would deadlock this test.
                recorder.store(coalescer.coalescedObservationCount, for: "release_count")
                snapshotReleased.fulfill()
            }
            weak var weakSnapshot = snapshot
            coalescer.submit { [captured = snapshot!] in
                withExtendedLifetime(captured) {}
                XCTFail("The superseded snapshot must never be inspected")
                coalescer.complete()
            }
            snapshot = nil
            XCTAssertNotNil(weakSnapshot)
            coalescer.submit {
                coalescer.complete()
                latestFinished.fulfill()
            }
            XCTAssertNil(weakSnapshot)
            replacementFinished.fulfill()
        }
        await fulfillment(of: [replacementFinished, snapshotReleased], timeout: 5)
        XCTAssertEqual(recorder.snapshot.values["release_count"], 1)
        releaseFirst.signal()
        await fulfillment(of: [latestFinished], timeout: 5)
    }

    private func visibility(enabled: Bool = true, scope: String = "chords", sourceCount: Int = 2,
        expected: Bool = true, comparable: Bool = true, foreground: Bool = true, hasWindow: Bool = true,
        finiteGeometry: Bool = true, intersectsViewport: Bool = true, stableCount: Int = 2,
        stableDuration: TimeInterval = 0.5, hidden: Bool = false, alpha: Double = 1,
        allowsPassing: Bool = false) -> IChartTelemetryProperties? {
        LeadSheetInkAuthoringTelemetry.visibilityProperties(isEnabled: enabled, chart: chart(), scope: scope,
            sourceStrokeCount: sourceCount, expectsVisibleAuthoringCanvas: expected, isComparable: comparable,
            isForeground: foreground, hasWindow: hasWindow, hasFiniteNonemptyGeometry: finiteGeometry,
            intersectsVisibleViewport: intersectsViewport, isHidden: hidden, alpha: alpha,
            stableObservationCount: stableCount, stableDuration: stableDuration,
            allowsPassingObservation: allowsPassing)
    }

    private func source(_ baseline: PKDrawing, _ current: PKDrawing) -> IChartTelemetryProperties? {
        LeadSheetInkAuthoringTelemetry.sourceProperties(isEnabled: true, chart: chart(), scope: "chords",
            completedBaseline: baseline, currentDrawing: current, isComparable: true)
    }

    private func responsiveness(_ window: LeadSheetInkAuthoringTelemetry.CallbackWindow,
        allowsPassing: Bool = false) -> IChartTelemetryProperties? {
        LeadSheetInkAuthoringTelemetry.responsivenessProperties(isEnabled: true, chart: chart(),
            scope: "chords", window: window, allowsPassingObservation: allowsPassing)
    }

    private func chart() -> Chart {
        var value = Chart.draft(title: "Private synthetic authoring fixture", layoutStyle: .simpleChordSheet)
        value.completeInitialSetup(title: "Private synthetic authoring fixture", key: .cMajor,
            meter: .init(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return value
    }

    private func stroke(_ x: CGFloat) -> PKStroke {
        stroke(points: [CGPoint(x: x, y: 10), CGPoint(x: x + 14, y: 30)])
    }

    private func stroke(points: [CGPoint], mask: UIBezierPath? = nil) -> PKStroke {
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: .init(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: .init(.pen, color: .black),
            path: .init(controlPoints: controls, creationDate: Date(timeIntervalSinceReferenceDate: 100)),
            transform: .identity, mask: mask, randomSeed: 17)
    }
}

private final class AuthoringTelemetryCoalescerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [Int] = []
    private var active = 0
    private var maximumActive = 0
    private var values: [String: Int] = [:]

    func begin(_ id: Int) {
        lock.lock()
        ids.append(id)
        active += 1
        maximumActive = max(maximumActive, active)
        lock.unlock()
    }

    func end() {
        lock.lock()
        active -= 1
        lock.unlock()
    }

    func store(_ value: Int, for key: String) {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    var snapshot: (ids: [Int], maximumActive: Int, values: [String: Int]) {
        lock.lock()
        defer { lock.unlock() }
        return (ids, maximumActive, values)
    }
}

private final class AuthoringTelemetrySnapshotLifetimeProbe: @unchecked Sendable {
    private let onDeinit: @Sendable () -> Void

    init(onDeinit: @escaping @Sendable () -> Void) { self.onDeinit = onDeinit }
    deinit { onDeinit() }
}
#endif

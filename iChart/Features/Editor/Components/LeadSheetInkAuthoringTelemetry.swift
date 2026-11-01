#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// Local append-only authoring observations. The canvas owner supplies an
/// explicitly completed baseline and invalidates comparability for erasure,
/// undo, render/rewrite, scope changes, normalization or reprojection.
/// These checks cannot establish a pixel-only PencilKit rendering dropout.
enum LeadSheetInkAuthoringTelemetry {
    private static let supportedScopes: Set<String> = ["page", "header", "chords", "rhythm"]
    private static let maximumCount = 1_000_000_000_000
    private static let maximumDurationMilliseconds: Double = 86_400_000

    /// Bounds deferred source inspection to one active observation and one
    /// latest pending observation. Intermediate observations are deliberately
    /// coalesced; this does not claim coverage of every pen event.
    ///
    /// Each invoked work item must call `complete()` exactly once, including
    /// work rejected because its captured consent generation became stale.
    final class DeferredObservationCoalescer: @unchecked Sendable {
        private typealias Work = @Sendable () -> Void
        private let lock = NSLock()
        private var isInFlight = false
        private var pending: Work?
        private var coalescedCount = 0

        var coalescedObservationCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return coalescedCount
        }

        func submit(_ work: @escaping @Sendable () -> Void) {
            // Retain a replaced closure until after unlocking. Snapshot release
            // and user-owned deinitializers must not run under this lock either.
            var replaced: Work?
            lock.lock()
            if isInFlight {
                replaced = pending
                if replaced != nil {
                    coalescedCount = min(LeadSheetInkAuthoringTelemetry.maximumCount, coalescedCount + 1)
                }
                pending = work
                lock.unlock()
                withExtendedLifetime(replaced) {}
                return
            }
            isInFlight = true
            lock.unlock()
            work()
        }

        func complete() {
            let next: Work?
            lock.lock()
            guard isInFlight else {
                lock.unlock()
                return
            }
            next = pending
            pending = nil
            if next == nil { isInFlight = false }
            lock.unlock()
            // `isInFlight` remains set when handing off to pending work. A new
            // submit during this call can only replace the one pending slot.
            next?()
        }
    }

    /// Call through the consent-generation-bound deferred diagnostic path.
    /// Nothing, including source enumeration, occurs while disabled or when
    /// the caller cannot prove a comparable completed-source context.
    static func sourceProperties(
        isEnabled: Bool,
        chart: Chart,
        scope: String,
        completedBaseline: @autoclosure () -> PKDrawing,
        currentDrawing: @autoclosure () -> PKDrawing,
        isComparable: Bool,
        operationID: UUID = UUID()
    ) -> IChartTelemetryProperties? {
        guard isEnabled, isComparable, supportedScopes.contains(scope) else { return nil }
        let baseline = completedBaseline()
        guard !baseline.strokes.isEmpty else { return nil }
        let current = currentDrawing()
        guard let containment = ChordInkAutomaticRenderTelemetry.completedSourceContainment(
            baseline: baseline, current: current),
              (1...maximumCount).contains(containment.expectedCount),
              (0...maximumCount).contains(containment.matchedCount),
              baseline.strokes.count <= maximumCount, current.strokes.count <= maximumCount else { return nil }
        let preserved = containment.expectedCount == containment.matchedCount
        var values = properties(
            contractID: "ink.authoring_integrity", operationID: operationID,
            outcome: preserved ? "passed" : "violated",
            reason: preserved ? "authoring_source_preserved" : "authoring_completed_source_missing",
            chart: chart, scope: scope,
            expectedCount: containment.expectedCount, actualCount: containment.matchedCount)
        values["content_matches"] = .bool(preserved)
        // Raw drawing-object counts are separate from visible fragment counts.
        values["source_stroke_count"] = .int(current.strokes.count)
        values["retained_stroke_count"] = .int(baseline.strokes.count)
        return values
    }

    /// The hot callback path only updates these scalar counters. A separate
    /// pen-end observation decides whether to record the bounded window.
    struct CallbackWindow: Equatable {
        private(set) var observedCallbackCount = 0
        private(set) var slowCallbackCount = 0
        private(set) var maximumDurationMilliseconds: Double = 0

        mutating func observe(durationMilliseconds: Double) {
            guard durationMilliseconds.isFinite,
                  (0...LeadSheetInkAuthoringTelemetry.maximumDurationMilliseconds).contains(durationMilliseconds),
                  observedCallbackCount < LeadSheetInkAuthoringTelemetry.maximumCount else { return }
            observedCallbackCount += 1
            if durationMilliseconds >= 100 {
                slowCallbackCount = min(LeadSheetInkAuthoringTelemetry.maximumCount, slowCallbackCount + 1)
            }
            maximumDurationMilliseconds = max(maximumDurationMilliseconds, durationMilliseconds)
        }

        var hasObservedStall: Bool {
            observedCallbackCount > 0 && (slowCallbackCount >= 3 || maximumDurationMilliseconds >= 500)
        }
    }

    /// An observed slow callback is workflow friction, not proof of source
    /// loss, recognition accuracy or complete end-to-end pen latency. Success
    /// observations require caller sampling, so every pen gesture does not
    /// automatically add a telemetry event.
    static func responsivenessProperties(
        isEnabled: Bool,
        chart: Chart,
        scope: String,
        window: CallbackWindow,
        allowsPassingObservation: Bool = false,
        operationID: UUID = UUID()
    ) -> IChartTelemetryProperties? {
        guard isEnabled, supportedScopes.contains(scope), window.observedCallbackCount > 0,
              window.observedCallbackCount <= maximumCount,
              (0...window.observedCallbackCount).contains(window.slowCallbackCount),
              window.maximumDurationMilliseconds.isFinite,
              (0...maximumDurationMilliseconds).contains(window.maximumDurationMilliseconds),
              window.hasObservedStall || allowsPassingObservation else { return nil }
        var values = properties(
            contractID: "ink.authoring_responsiveness", operationID: operationID,
            outcome: window.hasObservedStall ? "violated" : "passed",
            reason: window.hasObservedStall ? "authoring_callback_stalled" : "authoring_responsive",
            chart: chart, scope: scope, expectedCount: 0, actualCount: window.slowCallbackCount)
        values["duration_ms"] = .double(window.maximumDurationMilliseconds)
        return values
    }

    /// Checks application-level visibility after two stable observations. The
    /// owner captures effective hidden/opacity state without drawing pixels.
    /// Missing attachment, geometry or viewport context stays unknown; this
    /// cannot prove that PencilKit rasterized every expected source fragment.
    static func visibilityProperties(
        isEnabled: Bool,
        chart: Chart,
        scope: String,
        sourceStrokeCount: Int,
        expectsVisibleAuthoringCanvas: Bool,
        isComparable: Bool,
        isForeground: Bool,
        hasWindow: Bool,
        hasFiniteNonemptyGeometry: Bool,
        intersectsVisibleViewport: Bool,
        isHidden: Bool,
        alpha: Double,
        stableObservationCount: Int,
        stableDuration: TimeInterval,
        allowsPassingObservation: Bool = false,
        operationID: UUID = UUID()
    ) -> IChartTelemetryProperties? {
        guard isEnabled, supportedScopes.contains(scope), expectsVisibleAuthoringCanvas,
              isComparable, isForeground, hasWindow, hasFiniteNonemptyGeometry,
              intersectsVisibleViewport,
              (1...maximumCount).contains(sourceStrokeCount),
              (2...maximumCount).contains(stableObservationCount),
              alpha.isFinite, (0...1).contains(alpha),
              stableDuration.isFinite,
              (0.5...maximumDurationMilliseconds / 1_000).contains(stableDuration) else { return nil }
        let isInvisible = isHidden || alpha <= 0.01
        guard isInvisible || allowsPassingObservation else { return nil }
        var values = properties(
            contractID: "ink.live_canvas_visibility", operationID: operationID,
            outcome: isInvisible ? "violated" : "passed",
            reason: isInvisible ? "authoring_canvas_invisible" : "authoring_canvas_visible",
            chart: chart, scope: scope, expectedCount: 1, actualCount: isInvisible ? 0 : 1)
        values["content_matches"] = .bool(!isInvisible)
        values["source_stroke_count"] = .int(sourceStrokeCount)
        values["duration_ms"] = .double(stableDuration * 1_000)
        return values
    }

    private static func properties(
        contractID: String,
        operationID: UUID,
        outcome: String,
        reason: String,
        chart: Chart,
        scope: String,
        expectedCount: Int,
        actualCount: Int
    ) -> IChartTelemetryProperties {
        [
            "contract_id": .string(contractID), "contract_version": .int(1),
            "operation_id": .string(operationID.uuidString.lowercased()),
            "operation": .string("write"), "outcome": .string(outcome),
            "reason": .string(reason), "scope": .string(scope),
            "layout_style": .string(chart.layoutStyle.rawValue),
            "expected_count": .int(expectedCount), "actual_count": .int(actualCount)
        ]
    }
}
#endif

#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import XCTest
@testable import iChart

final class LeadSheetInkTelemetryLifecycleTests: XCTestCase {
    private struct Context: Equatable {
        var chart = 1
        var scope = "page"
        var consentGeneration = 1
        var coordinateEpoch = 1
    }
    private struct Snapshot: Equatable {
        var context = Context()
        var sourceRevision = 1
        var sourceCount = 2
        var hidden = false
    }
    private typealias Authoring = LeadSheetInkTelemetryLifecycle.AuthoringOperation<Context>
    private typealias Visibility = LeadSheetInkTelemetryLifecycle.StableVisibility<Snapshot>

    func testFinalDrawingCallbackAfterToolEndBelongsToOriginalOperation() throws {
        var lifecycle = Authoring()
        let context = Context()
        let operationID = UUID()
        let ticket = lifecycle.begin(context: context, operationID: operationID)
        XCTAssertTrue(lifecycle.recordCallback(ticket: ticket, context: context, durationMilliseconds: 12))
        XCTAssertTrue(lifecycle.end(ticket: ticket, context: context))
        let finalCallbackTicket = try XCTUnwrap(lifecycle.callbackTicket(context: context))
        XCTAssertEqual(finalCallbackTicket, ticket)
        XCTAssertTrue(lifecycle.recordCallback(ticket: finalCallbackTicket, context: context,
            durationMilliseconds: 140))
        let completed = try XCTUnwrap(lifecycle.finish(ticket: ticket, context: context))
        XCTAssertEqual(completed.ticket.operationID, operationID)
        XCTAssertEqual(completed.context, context)
        XCTAssertEqual(completed.callbacks.observedCallbackCount, 2)
        XCTAssertEqual(completed.callbacks.slowCallbackCount, 1)
        XCTAssertEqual(completed.callbacks.maximumDurationMilliseconds, 140)
        XCTAssertNil(lifecycle.callbackTicket(context: context))
    }

    func testCallbackCapturedAtEntryCanFinishAfterToolEnd() throws {
        var lifecycle = Authoring()
        let context = Context()
        let ticket = lifecycle.begin(context: context)
        let callbackTicket = try XCTUnwrap(lifecycle.callbackTicket(context: context))
        XCTAssertTrue(lifecycle.end(ticket: ticket, context: context))
        XCTAssertTrue(lifecycle.recordCallback(ticket: callbackTicket, context: context,
            durationMilliseconds: 501))
        let completed = try XCTUnwrap(lifecycle.finish(ticket: ticket, context: context))
        XCTAssertTrue(completed.callbacks.hasObservedStall)
        XCTAssertEqual(completed.callbacks.observedCallbackCount, 1)
    }

    func testActiveOperationCannotBeFinalizedBeforeToolEnd() throws {
        var lifecycle = Authoring()
        let context = Context()
        let ticket = lifecycle.begin(context: context)
        XCTAssertNil(lifecycle.finish(ticket: ticket, context: context))
        XCTAssertFalse(lifecycle.isSettling(ticket: ticket, context: context))
        XCTAssertTrue(lifecycle.end(ticket: ticket, context: context))
        XCTAssertTrue(lifecycle.isSettling(ticket: ticket, context: context))
        XCTAssertNotNil(lifecycle.finish(ticket: ticket, context: context))
    }

    func testNewPenOperationRejectsPriorCallbackAndFinalizerEvenWhenOperationIDIsReused() throws {
        var lifecycle = Authoring()
        let context = Context()
        let operationID = UUID()
        let prior = lifecycle.begin(context: context, operationID: operationID)
        XCTAssertTrue(lifecycle.end(ticket: prior, context: context))
        let current = lifecycle.begin(context: context, operationID: operationID)
        XCTAssertNotEqual(prior, current)
        XCTAssertFalse(lifecycle.recordCallback(ticket: prior, context: context, durationMilliseconds: 700))
        XCTAssertNil(lifecycle.finish(ticket: prior, context: context))
        XCTAssertTrue(lifecycle.recordCallback(ticket: current, context: context, durationMilliseconds: 8))
        XCTAssertTrue(lifecycle.end(ticket: current, context: context))
        let completed = try XCTUnwrap(lifecycle.finish(ticket: current, context: context))
        XCTAssertEqual(completed.callbacks.observedCallbackCount, 1)
        XCTAssertEqual(completed.callbacks.maximumDurationMilliseconds, 8)
    }

    func testScopeCoordinateAndConsentChangesCannotAdoptCapturedCallback() {
        let context = Context()
        for changed in [Context(chart: 2), Context(scope: "chords"),
                        Context(consentGeneration: 2), Context(coordinateEpoch: 2)] {
            var lifecycle = Authoring()
            let ticket = lifecycle.begin(context: context)
            XCTAssertNil(lifecycle.callbackTicket(context: changed))
            XCTAssertFalse(lifecycle.recordCallback(ticket: ticket, context: changed, durationMilliseconds: 8))
            XCTAssertFalse(lifecycle.end(ticket: ticket, context: changed))
            XCTAssertNil(lifecycle.finish(ticket: ticket, context: changed))
        }
    }

    func testInvalidationDiscardsLateCallbackAndPendingFinalization() {
        var lifecycle = Authoring()
        let context = Context()
        let ticket = lifecycle.begin(context: context)
        XCTAssertTrue(lifecycle.end(ticket: ticket, context: context))
        lifecycle.invalidate()
        XCTAssertNil(lifecycle.callbackTicket(context: context))
        XCTAssertFalse(lifecycle.recordCallback(ticket: ticket, context: context, durationMilliseconds: 8))
        XCTAssertNil(lifecycle.finish(ticket: ticket, context: context))
    }

    func testNoCallbacksOrInvalidTimingsDoNotInventAnObservedCallback() throws {
        var lifecycle = Authoring()
        let context = Context()
        let ticket = lifecycle.begin(context: context)
        for duration in [-1.0, Double.nan, Double.infinity, -Double.infinity, 86_400_001] {
            XCTAssertFalse(lifecycle.recordCallback(ticket: ticket, context: context,
                durationMilliseconds: duration))
        }
        XCTAssertTrue(lifecycle.end(ticket: ticket, context: context))
        let completed = try XCTUnwrap(lifecycle.finish(ticket: ticket, context: context))
        XCTAssertEqual(completed.callbacks.observedCallbackCount, 0)
        XCTAssertFalse(completed.callbacks.hasObservedStall)
        XCTAssertNil(LeadSheetInkAuthoringTelemetry.responsivenessProperties(isEnabled: true,
            chart: .draft(title: "Synthetic lifecycle"), scope: "page", window: completed.callbacks,
            allowsPassingObservation: true, operationID: ticket.operationID))
    }

    func testToolEndAndFinalizationAreAdmittedOnce() {
        var lifecycle = Authoring()
        let context = Context()
        let ticket = lifecycle.begin(context: context)
        XCTAssertTrue(lifecycle.end(ticket: ticket, context: context))
        XCTAssertFalse(lifecycle.end(ticket: ticket, context: context))
        XCTAssertNotNil(lifecycle.finish(ticket: ticket, context: context))
        XCTAssertNil(lifecycle.finish(ticket: ticket, context: context))
    }

    func testIdenticalLayoutUpdatesDoNotRestartVisibilityDeadline() throws {
        var lifecycle = Visibility()
        let snapshot = Snapshot()
        let ticket = try scheduled(lifecycle.update(snapshot: snapshot, at: 10))
        for now in [10.05, 10.1, 10.2, 10.29] {
            XCTAssertEqual(lifecycle.update(snapshot: snapshot, at: now), .unchanged)
        }
        XCTAssertEqual(try scheduled(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 10.3)), ticket)
        for now in [10.35, 10.4, 10.5, 10.59] {
            XCTAssertEqual(lifecycle.update(snapshot: snapshot, at: now), .unchanged)
        }
        let ready = try readyObservation(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 10.6))
        XCTAssertEqual(ready.ticket, ticket)
        XCTAssertEqual(ready.stableObservationCount, 3)
        XCTAssertEqual(ready.stableDuration, 0.6, accuracy: 0.000_001)
    }

    func testChangedSourceSnapshotReplacesDeadlineAndRejectsOldTimer() throws {
        var lifecycle = Visibility()
        let first = Snapshot()
        let original = try scheduled(lifecycle.update(snapshot: first, at: 0))
        var changed = first
        changed.sourceCount = 3
        changed.sourceRevision = 2
        let replacement = try scheduled(lifecycle.update(snapshot: changed, at: 0.2))
        XCTAssertNotEqual(original, replacement)
        XCTAssertEqual(lifecycle.sample(ticket: original, currentSnapshot: changed, at: 0.3), .ignored)
        _ = try scheduled(lifecycle.sample(ticket: replacement, currentSnapshot: changed, at: 0.5))
        let observed = try readyObservation(lifecycle.sample(ticket: replacement, currentSnapshot: changed, at: 0.8))
        XCTAssertEqual(observed.snapshot, changed)
        XCTAssertEqual(observed.stableDuration, 0.6, accuracy: 0.000_001)
    }

    func testFinalCallbackDiscoveredByTimerRearmsWithoutNeedingAnotherLayout() throws {
        var lifecycle = Visibility()
        let first = Snapshot()
        let original = try scheduled(lifecycle.update(snapshot: first, at: 0))
        var settled = first
        settled.sourceCount = 3
        settled.sourceRevision = 2
        let replacement = try scheduled(lifecycle.sample(ticket: original, currentSnapshot: settled, at: 0.3))
        XCTAssertNotEqual(original, replacement)
        _ = try scheduled(lifecycle.sample(ticket: replacement, currentSnapshot: settled, at: 0.6))
        let observed = try readyObservation(lifecycle.sample(ticket: replacement, currentSnapshot: settled, at: 0.9))
        XCTAssertEqual(observed.snapshot, settled)
        XCTAssertEqual(observed.stableObservationCount, 3)
    }

    func testEarlyTimerDoesNotInventASecondStableObservation() throws {
        var lifecycle = Visibility()
        let snapshot = Snapshot()
        let ticket = try scheduled(lifecycle.update(snapshot: snapshot, at: 0))
        if case .schedule(let sameTicket, let remaining) = lifecycle.sample(ticket: ticket,
            currentSnapshot: snapshot, at: 0.1) {
            XCTAssertEqual(sameTicket, ticket)
            XCTAssertEqual(remaining, 0.2, accuracy: 0.000_001)
        } else { XCTFail("An early actual timer must wait for the rest of its interval") }
        _ = try scheduled(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 0.3))
        _ = try scheduled(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 0.59))
        let observed = try readyObservation(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 0.6))
        XCTAssertEqual(observed.stableObservationCount, 3)
        XCTAssertEqual(observed.stableDuration, 0.6, accuracy: 0.000_001)
    }

    func testUnavailableCanvasCancelsAndDoesNotAdoptOldTimerAfterReturn() throws {
        var lifecycle = Visibility()
        let snapshot = Snapshot()
        let old = try scheduled(lifecycle.update(snapshot: snapshot, at: 0))
        XCTAssertEqual(lifecycle.sample(ticket: old, currentSnapshot: nil, at: 0.3), .cancelled)
        let current = try scheduled(lifecycle.update(snapshot: snapshot, at: 1))
        XCTAssertNotEqual(old, current)
        XCTAssertEqual(lifecycle.sample(ticket: old, currentSnapshot: snapshot, at: 1.3), .ignored)
    }

    func testConsentRegrantRequiresEntirelyNewVisibilityDwell() throws {
        var lifecycle = Visibility()
        let original = Snapshot()
        let old = try scheduled(lifecycle.update(snapshot: original, at: 0))
        _ = try scheduled(lifecycle.sample(ticket: old, currentSnapshot: original, at: 0.3))
        var regranted = original
        regranted.context.consentGeneration = 2
        let current = try scheduled(lifecycle.update(snapshot: regranted, at: 0.4))
        XCTAssertEqual(lifecycle.sample(ticket: old, currentSnapshot: regranted, at: 0.6), .ignored)
        _ = try scheduled(lifecycle.sample(ticket: current, currentSnapshot: regranted, at: 0.7))
        let observed = try readyObservation(lifecycle.sample(ticket: current, currentSnapshot: regranted, at: 1))
        XCTAssertEqual(observed.snapshot.context.consentGeneration, 2)
        XCTAssertEqual(observed.stableDuration, 0.6, accuracy: 0.000_001)
    }

    func testCompletedVisibilityDoesNotEmitAgainForIdenticalLayout() throws {
        var lifecycle = Visibility()
        let snapshot = Snapshot()
        let ticket = try scheduled(lifecycle.update(snapshot: snapshot, at: 0))
        _ = try scheduled(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 0.3))
        _ = try readyObservation(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 0.6))
        XCTAssertEqual(lifecycle.update(snapshot: snapshot, at: 1), .unchanged)
        XCTAssertEqual(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 2), .unchanged)
        var changed = snapshot
        changed.hidden = true
        XCTAssertNotEqual(try scheduled(lifecycle.update(snapshot: changed, at: 2)), ticket)
    }

    func testInvalidationMakesPreviouslyScheduledVisibilityTimerHarmless() throws {
        var lifecycle = Visibility()
        let snapshot = Snapshot()
        let ticket = try scheduled(lifecycle.update(snapshot: snapshot, at: 0))
        lifecycle.invalidate()
        XCTAssertEqual(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: 0.3), .ignored)
    }

    func testNonfiniteOrBackwardsClockCancelsInsteadOfClaimingStableCoverage() throws {
        for time in [Double.nan, .infinity, -.infinity, 9] {
            var lifecycle = Visibility()
            let snapshot = Snapshot()
            let ticket = try scheduled(lifecycle.update(snapshot: snapshot, at: 10))
            XCTAssertEqual(lifecycle.sample(ticket: ticket, currentSnapshot: snapshot, at: time), .cancelled)
        }
    }

    private func scheduled(_ action: Visibility.Action, file: StaticString = #filePath,
                           line: UInt = #line) throws -> Visibility.Ticket {
        guard case .schedule(let ticket, let delay) = action else {
            XCTFail("Expected a pending real observation", file: file, line: line)
            throw Failure.unexpectedAction
        }
        XCTAssertGreaterThan(delay, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(delay, 0.3, file: file, line: line)
        return ticket
    }

    private func readyObservation(_ action: Visibility.Action, file: StaticString = #filePath,
                       line: UInt = #line) throws -> Visibility.Observation {
        guard case .ready(let observation) = action else {
            XCTFail("Expected three genuinely spaced stable observations", file: file, line: line)
            throw Failure.unexpectedAction
        }
        return observation
    }
    private enum Failure: Error { case unexpectedAction }
}
#endif

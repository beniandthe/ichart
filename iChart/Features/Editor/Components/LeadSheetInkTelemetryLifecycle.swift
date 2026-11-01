#if canImport(UIKit) && canImport(PencilKit)
import Foundation

/// Scheduling state only. The canvas owner retains the source drawing and the
/// original diagnostic authorization, supplies their exact context, and checks
/// that authorization again before publishing. Neither helper creates timings,
/// source comparisons, callbacks, timers, or telemetry events.
enum LeadSheetInkTelemetryLifecycle {
    /// The owner finishes a settling operation after a bounded main-queue turn.
    /// A callback captures its ticket on entry and records its real elapsed cost
    /// on exit, so a final drawing callback after tool-end is still attributable.
    struct AuthoringOperation<Context: Equatable> {
        struct Ticket: Equatable {
            let operationID: UUID
            fileprivate let identity: UUID
        }

        struct Completed {
            let ticket: Ticket
            let context: Context
            let callbacks: LeadSheetInkAuthoringTelemetry.CallbackWindow
        }

        private enum Phase: Equatable { case active, settling }
        private struct Observation {
            let ticket: Ticket
            let context: Context
            var phase: Phase = .active
            var callbacks = LeadSheetInkAuthoringTelemetry.CallbackWindow()
        }
        private var observation: Observation?

        /// Finish any valid prior settling operation before beginning the next.
        /// Replacing an unfinished observation invalidates its ticket; a later
        /// callback can never be counted in a newly begun operation by that ticket.
        @discardableResult
        mutating func begin(context: Context, operationID: UUID = UUID()) -> Ticket {
            let ticket = Ticket(operationID: operationID, identity: UUID())
            observation = Observation(ticket: ticket, context: context)
            return ticket
        }

        func callbackTicket(context: Context) -> Ticket? {
            guard let observation, observation.context == context else { return nil }
            return observation.ticket
        }

        @discardableResult
        mutating func recordCallback(ticket: Ticket, context: Context,
                                     durationMilliseconds: Double) -> Bool {
            guard var current = observation, current.ticket == ticket,
                  current.context == context else { return false }
            let priorCount = current.callbacks.observedCallbackCount
            current.callbacks.observe(durationMilliseconds: durationMilliseconds)
            guard current.callbacks.observedCallbackCount > priorCount else { return false }
            observation = current
            return true
        }

        @discardableResult
        mutating func end(ticket: Ticket, context: Context) -> Bool {
            guard var current = observation, current.ticket == ticket,
                  current.context == context, current.phase == .active else { return false }
            current.phase = .settling
            observation = current
            return true
        }

        func isSettling(ticket: Ticket, context: Context) -> Bool {
            guard let current = observation else { return false }
            return current.ticket == ticket && current.context == context && current.phase == .settling
        }

        mutating func finish(ticket: Ticket, context: Context) -> Completed? {
            guard let current = observation, current.ticket == ticket,
                  current.context == context, current.phase == .settling else { return nil }
            observation = nil
            return Completed(ticket: current.ticket, context: current.context, callbacks: current.callbacks)
        }

        mutating func invalidate() { observation = nil }
    }

    /// A snapshot must include the owner/scope/source and original consent epoch
    /// as well as its visibility geometry. Identical layout notifications retain
    /// the existing deadline; a genuinely changed snapshot gets its own ticket.
    struct StableVisibility<Snapshot: Equatable> {
        struct Ticket: Equatable {
            let operationID: UUID
            fileprivate let identity: UUID
        }

        struct Observation: Equatable {
            let ticket: Ticket
            let snapshot: Snapshot
            let stableObservationCount: Int
            let stableDuration: TimeInterval
        }

        enum Action: Equatable {
            case unchanged
            case cancelled
            case ignored
            case schedule(ticket: Ticket, after: TimeInterval)
            case ready(Observation)
        }

        private struct Pending {
            let ticket: Ticket
            let snapshot: Snapshot
            let startedAt: TimeInterval
            var sampledAt: TimeInterval
            var count = 1
            var completed = false
        }
        private var pending: Pending?
        private let interval: TimeInterval = 0.3
        private let requiredCount = 3
        private let clockTolerance: TimeInterval = 0.000_000_001

        mutating func update(snapshot: Snapshot?, at now: TimeInterval) -> Action {
            guard let snapshot, now.isFinite else { return cancel() }
            if let pending {
                guard now >= pending.sampledAt else { return cancel() }
                if pending.snapshot == snapshot { return .unchanged }
            }
            return start(snapshot: snapshot, at: now)
        }

        /// Called only after an actual timer fires. If the current snapshot has
        /// changed since scheduling, rearm from that real observation rather
        /// than dropping coverage and hoping for another layout notification.
        mutating func sample(ticket: Ticket, currentSnapshot: Snapshot?, at now: TimeInterval) -> Action {
            guard var current = pending, current.ticket == ticket else { return .ignored }
            guard let currentSnapshot, now.isFinite, now >= current.sampledAt else { return cancel() }
            guard current.snapshot == currentSnapshot else {
                return start(snapshot: currentSnapshot, at: now)
            }
            guard !current.completed else { return .unchanged }
            let remaining = interval - (now - current.sampledAt)
            if remaining > clockTolerance {
                return .schedule(ticket: current.ticket, after: remaining)
            }
            current.sampledAt = now
            current.count += 1
            let elapsed = now - current.startedAt
            if current.count >= requiredCount && elapsed + clockTolerance >= interval * Double(requiredCount - 1) {
                current.completed = true
                pending = current
                return .ready(Observation(ticket: current.ticket, snapshot: current.snapshot,
                    stableObservationCount: current.count, stableDuration: elapsed))
            }
            pending = current
            return .schedule(ticket: current.ticket, after: interval)
        }

        mutating func invalidate() { pending = nil }

        private mutating func start(snapshot: Snapshot, at now: TimeInterval) -> Action {
            let ticket = Ticket(operationID: UUID(), identity: UUID())
            pending = Pending(ticket: ticket, snapshot: snapshot, startedAt: now, sampledAt: now)
            return .schedule(ticket: ticket, after: interval)
        }

        private mutating func cancel() -> Action {
            pending = nil
            return .cancelled
        }
    }
}
#endif

import Foundation

struct IChartTelemetryConsentSnapshot: Equatable, Sendable {
    let isGranted: Bool
    fileprivate let generation: UInt64
}

/// Only the current, explicitly selected consent value enables diagnostics.
/// The generation also distinguishes withdrawal followed by another opt-in.
final class IChartTelemetryConsentStore: @unchecked Sendable {
    static let shared = IChartTelemetryConsentStore()
    static let preferenceKey = "iChart.telemetry.consent-version"
    static let currentVersion = "telemetry-consent-v1"
    static let installationIDPreferenceKey = "iChart.telemetry.installation-id.v1"
    private static let queueResetRequiredPreferenceKey = "iChart.telemetry.queue-reset-required.v1"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var observedVersion: String?
    private var generation: UInt64 = 0
    private var queueResetRequired: Bool
    private var cachedInstallationID: UUID?
    private var pendingPersistence: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observedVersion = defaults.string(forKey: Self.preferenceKey)
        queueResetRequired = defaults.bool(forKey: Self.queueResetRequiredPreferenceKey)
        cachedInstallationID = observedVersion == Self.currentVersion
            ? defaults.string(forKey: Self.installationIDPreferenceKey).flatMap(UUID.init(uuidString:))
            : nil
        if observedVersion != Self.currentVersion {
            defaults.removeObject(forKey: Self.installationIDPreferenceKey)
        }
    }

    var snapshot: IChartTelemetryConsentSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    var requiresQueueReset: Bool {
        lock.lock()
        defer { lock.unlock() }
        return queueResetRequired
    }

    @MainActor
    func setConsentGranted(_ isGranted: Bool) {
        lock.lock()
        let version = isGranted ? Self.currentVersion : nil
        if observedVersion != version {
            generation &+= 1
        }
        observedVersion = version
        if !isGranted {
            queueResetRequired = true
            cachedInstallationID = nil
        }
        let consent = snapshotLocked()
        lock.unlock()

        // UserDefaults can synchronously notify SwiftUI. Never perform a
        // preference read or write while holding the consent state lock.
        if let version {
            defaults.set(version, forKey: Self.preferenceKey)
        } else {
            // Persist this before withdrawing consent. If the app terminates
            // before actor cleanup, a later opt-in must not revive the queue.
            defaults.set(true, forKey: Self.queueResetRequiredPreferenceKey)
            guard snapshot == consent else { return }
            defaults.removeObject(forKey: Self.preferenceKey)
            guard snapshot == consent else { return }
            defaults.removeObject(forKey: Self.installationIDPreferenceKey)
        }
    }

    func installationID(for consent: IChartTelemetryConsentSnapshot) -> UUID? {
        lock.lock()
        guard consent.isGranted, snapshotLocked() == consent else {
            lock.unlock()
            return nil
        }
        if let cachedInstallationID {
            lock.unlock()
            return cachedInstallationID
        }
        let id = UUID()
        cachedInstallationID = id
        lock.unlock()
        enqueuePersistence { [self] in
            guard shouldPersistInstallationID(id, matching: consent) else { return }
            defaults.set(id.uuidString, forKey: Self.installationIDPreferenceKey)
        }
        return id
    }

    /// Keep queue changes and request starts atomic with respect to withdrawal.
    func performIfGranted<Value>(
        matching consent: IChartTelemetryConsentSnapshot,
        _ operation: () throws -> Value
    ) rethrows -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard consent.isGranted, snapshotLocked() == consent else { return nil }
        return try operation()
    }

    func clearQueuedEvents(
        matching consent: IChartTelemetryConsentSnapshot,
        _ clearQueue: () throws -> Void
    ) rethrows -> Bool {
        lock.lock()
        guard snapshotLocked() == consent else {
            lock.unlock()
            return false
        }
        do {
            try clearQueue()
        } catch {
            lock.unlock()
            throw error
        }
        queueResetRequired = false
        lock.unlock()
        enqueuePersistence { [self] in
            guard shouldPersistClearedQueueReset(matching: consent) else { return }
            defaults.removeObject(forKey: Self.queueResetRequiredPreferenceKey)
        }
        return true
    }

    /// Wait for writes already scheduled by this store. Normal telemetry queue
    /// operations never wait on preference persistence; relaunch checks can.
    func waitForPendingPersistence() async {
        if let pending = currentPersistenceTask() { await pending.value }
    }

    private func snapshotLocked() -> IChartTelemetryConsentSnapshot {
        IChartTelemetryConsentSnapshot(
            isGranted: observedVersion == Self.currentVersion,
            generation: generation
        )
    }

    private func shouldPersistInstallationID(_ id: UUID, matching consent: IChartTelemetryConsentSnapshot) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return consent.isGranted && snapshotLocked() == consent && cachedInstallationID == id
    }

    private func shouldPersistClearedQueueReset(matching consent: IChartTelemetryConsentSnapshot) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked() == consent && !queueResetRequired
    }

    private func enqueuePersistence(_ operation: @escaping @MainActor @Sendable () -> Void) {
        lock.lock()
        let previous = pendingPersistence
        pendingPersistence = Task { @MainActor in
            await previous?.value
            operation()
        }
        lock.unlock()
    }

    private func currentPersistenceTask() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return pendingPersistence
    }
}

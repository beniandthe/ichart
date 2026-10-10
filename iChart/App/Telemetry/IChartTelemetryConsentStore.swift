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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observedVersion = defaults.string(forKey: Self.preferenceKey)
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
        return defaults.bool(forKey: Self.queueResetRequiredPreferenceKey)
    }

    func setConsentGranted(_ isGranted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let version = isGranted ? Self.currentVersion : nil
        if defaults.string(forKey: Self.preferenceKey) != version {
            generation &+= 1
        }
        observedVersion = version
        if let version {
            defaults.set(version, forKey: Self.preferenceKey)
        } else {
            // Persist this before withdrawing consent. If the app terminates
            // before actor cleanup, a later opt-in must not revive the queue.
            defaults.set(true, forKey: Self.queueResetRequiredPreferenceKey)
            defaults.removeObject(forKey: Self.preferenceKey)
            defaults.removeObject(forKey: Self.installationIDPreferenceKey)
        }
    }

    func installationID(for consent: IChartTelemetryConsentSnapshot) -> UUID? {
        performIfGranted(matching: consent) {
            if let storedValue = defaults.string(forKey: Self.installationIDPreferenceKey),
               let id = UUID(uuidString: storedValue) {
                return id
            }
            let id = UUID()
            defaults.set(id.uuidString, forKey: Self.installationIDPreferenceKey)
            return id
        }
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
        defer { lock.unlock() }
        guard snapshotLocked() == consent else { return false }
        try clearQueue()
        defaults.removeObject(forKey: Self.queueResetRequiredPreferenceKey)
        return true
    }

    private func snapshotLocked() -> IChartTelemetryConsentSnapshot {
        let version = defaults.string(forKey: Self.preferenceKey)
        if version != observedVersion {
            observedVersion = version
            generation &+= 1
            if version != Self.currentVersion {
                defaults.set(true, forKey: Self.queueResetRequiredPreferenceKey)
                defaults.removeObject(forKey: Self.installationIDPreferenceKey)
            }
        }
        return IChartTelemetryConsentSnapshot(
            isGranted: version == Self.currentVersion,
            generation: generation
        )
    }
}

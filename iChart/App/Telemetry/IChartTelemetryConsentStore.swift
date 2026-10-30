import Foundation

struct IChartTelemetryConsentSnapshot: Equatable, Sendable {
    let isGranted: Bool
    fileprivate let generation: UInt64
}

/// Only the current, explicitly selected consent value enables diagnostics.
/// The generation also distinguishes withdrawal followed by another opt-in.
final class IChartTelemetryConsentStore: @unchecked Sendable {
    static let shared = IChartTelemetryConsentStore(diagnosticFileURLs: [
        ChartPersistenceContractDiagnostics.checkpointURL(for: FileChartRepository.live().url)
    ])
    static let preferenceKey = "iChart.telemetry.consent-version"
    static let currentVersion = "telemetry-consent-v1"
    static let installationIDPreferenceKey = "iChart.telemetry.installation-id.v1"
    private static let queueResetRequiredPreferenceKey = "iChart.telemetry.queue-reset-required.v1"
    private static let diagnosticCleanupRequiredPreferenceKey = "iChart.telemetry.checkpoint-reset-required.v1"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var observedVersion: String?
    private var generation: UInt64 = 0
    private var diagnosticFileURLs: Set<URL>
    private let removeDiagnosticFile: (URL) throws -> Void
    private let writeDiagnosticFile: (Data, URL) throws -> Void

    init(
        defaults: UserDefaults = .standard,
        diagnosticFileURLs: [URL] = [],
        removeDiagnosticFile: @escaping (URL) throws -> Void = { url in
            do { try FileManager.default.removeItem(at: url) }
            catch let error as CocoaError where error.code == .fileNoSuchFile { return }
        },
        writeDiagnosticFile: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.defaults = defaults
        self.diagnosticFileURLs = Set(diagnosticFileURLs.map(\.standardizedFileURL))
        self.removeDiagnosticFile = removeDiagnosticFile
        self.writeDiagnosticFile = writeDiagnosticFile
        observedVersion = defaults.string(forKey: Self.preferenceKey)
        if observedVersion != Self.currentVersion {
            defaults.removeObject(forKey: Self.installationIDPreferenceKey)
            defaults.set(true, forKey: Self.diagnosticCleanupRequiredPreferenceKey)
        }
        if defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey) {
            retryDiagnosticCleanupLocked()
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

    var requiresDiagnosticCleanup: Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey)
    }

    /// Registration also removes a leftover when diagnostics are disabled.
    /// The shared store registers the standard library path at startup, so this
    /// does not depend on a configured network telemetry service.
    func registerDiagnosticFile(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        diagnosticFileURLs.insert(url.standardizedFileURL)
        if !snapshotLocked().isGranted {
            defaults.set(true, forKey: Self.diagnosticCleanupRequiredPreferenceKey)
        }
        if defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey) {
            retryDiagnosticCleanupLocked()
        }
    }

    func retryDiagnosticCleanup() {
        lock.lock()
        defer { lock.unlock() }
        if !snapshotLocked().isGranted {
            defaults.set(true, forKey: Self.diagnosticCleanupRequiredPreferenceKey)
        }
        if defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey) {
            retryDiagnosticCleanupLocked()
        }
    }

    /// Captured before background readback/hash work. A generation is never
    /// persisted in the checkpoint; its stable identity remains usable after a
    /// normal app launch without permitting an old in-flight write after opt-in.
    func checkpointAuthorization() -> ChartPersistenceDiagnosticAuthorization? {
        lock.lock()
        defer { lock.unlock() }
        let consent = snapshotLocked()
        guard consent.isGranted,
              !defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey) else { return nil }
        return ChartPersistenceDiagnosticAuthorization(
            identity: installationIDLocked().uuidString.lowercased(), generation: consent.generation
        )
    }

    /// Only a small pre-encoded checkpoint is written while holding this lock.
    /// Withdrawal invalidates the generation and removes the file under the
    /// same lock, so it cannot return before an admitted write is removed.
    @discardableResult
    func publishDiagnosticCheckpoint(
        _ data: Data, to url: URL, authorization: ChartPersistenceDiagnosticAuthorization
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        diagnosticFileURLs.insert(url.standardizedFileURL)
        let consent = snapshotLocked()
        guard consent.isGranted,
              consent.generation == authorization.generation,
              !defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey),
              defaults.string(forKey: Self.installationIDPreferenceKey)?.lowercased() == authorization.identity else {
            return false
        }
        try writeDiagnosticFile(data, url)
        return true
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
            defaults.set(true, forKey: Self.diagnosticCleanupRequiredPreferenceKey)
            defaults.removeObject(forKey: Self.preferenceKey)
            defaults.removeObject(forKey: Self.installationIDPreferenceKey)
            retryDiagnosticCleanupLocked()
        }
    }

    func installationID(for consent: IChartTelemetryConsentSnapshot) -> UUID? {
        performIfGranted(matching: consent) {
            installationIDLocked()
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
                defaults.set(true, forKey: Self.diagnosticCleanupRequiredPreferenceKey)
                defaults.removeObject(forKey: Self.installationIDPreferenceKey)
            }
        }
        if defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey) {
            retryDiagnosticCleanupLocked()
        }
        return IChartTelemetryConsentSnapshot(
            isGranted: version == Self.currentVersion,
            generation: generation
        )
    }

    private func installationIDLocked() -> UUID {
        if let storedValue = defaults.string(forKey: Self.installationIDPreferenceKey),
           let id = UUID(uuidString: storedValue) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.installationIDPreferenceKey)
        return id
    }

    private func retryDiagnosticCleanupLocked() {
        var failed = false
        for url in diagnosticFileURLs {
            do { try removeDiagnosticFile(url) }
            catch { failed = true }
        }
        // Keep the marker across app exits until every registered file has been
        // removed. A later opt-in cannot make failed cleanup look successful.
        defaults.set(failed, forKey: Self.diagnosticCleanupRequiredPreferenceKey)
    }
}

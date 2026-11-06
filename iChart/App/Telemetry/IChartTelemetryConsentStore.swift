import Foundation

struct IChartTelemetryConsentSnapshot: Equatable, Sendable {
    let isGranted: Bool
    fileprivate let generation: UInt64
}

enum IChartTelemetryConsentAdmissionDenial: String, Sendable {
    case preferenceProjectionInProgress
    case capturedConsentNotGranted
    case consentChanged
}

/// Only the current, explicitly selected consent value enables diagnostics.
/// The generation also distinguishes withdrawal followed by another opt-in.
final class IChartTelemetryConsentStore: @unchecked Sendable {
    static let shared = IChartTelemetryConsentStore(cleansLegacyLiveCheckpoint: true)
    static let preferenceKey = "iChart.telemetry.consent-version"
    static let currentVersion = "telemetry-consent-v1"
    static let installationIDPreferenceKey = "iChart.telemetry.installation-id.v1"
    private static let queueResetRequiredPreferenceKey = "iChart.telemetry.queue-reset-required.v1"
    private static let diagnosticCleanupRequiredPreferenceKey = "iChart.telemetry.checkpoint-reset-required.v1"

    private let lock = NSLock()
    private let diagnosticCleanupQueue = DispatchQueue(label: "com.ichart.retired-diagnostic-cleanup", qos: .utility)
    // Scheduling must never wait for the authoritative lock, which also orders
    // queue/checkpoint disk writes with consent withdrawal. This lock protects
    // only a two-field copy; code holding it never acquires `lock` or does I/O.
    private let schedulingLock = NSLock()
    private var schedulingSnapshot: IChartTelemetryConsentSnapshot
    private var pendingSchedulingTransition: IChartTelemetryConsentSnapshot?
    private let defaults: UserDefaults
    private var observedVersion: String?
    private var generation: UInt64 = 0
    private var stateRevision: UInt64 = 0
    private var projectedStateRevision: UInt64 = 0
    private var preferenceWriteDepth = 0
    private var preferenceAuthorizationBlockDepth = 0
    private var pendingConsentProjectionGeneration: UInt64?
    private var queueResetRequired: Bool
    private var diagnosticCleanupRequired: Bool
    private var cachedInstallationID: UUID?
    private var diagnosticFileURLs: Set<URL>
    private let removeDiagnosticFile: (URL) throws -> Void
    private let cleansLegacyLiveCheckpoint: Bool

    init(
        defaults: UserDefaults = .standard,
        diagnosticFileURLs: [URL] = [],
        removeDiagnosticFile: @escaping (URL) throws -> Void = { url in
            do { try FileManager.default.removeItem(at: url) }
            catch let error as CocoaError where error.code == .fileNoSuchFile { return }
        },
        writeDiagnosticFile: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        },
        cleansLegacyLiveCheckpoint: Bool = false
    ) {
        self.defaults = defaults
        self.diagnosticFileURLs = Set(diagnosticFileURLs.filter(Self.isLegacyCheckpoint).map(\.standardizedFileURL))
        self.removeDiagnosticFile = removeDiagnosticFile
        self.cleansLegacyLiveCheckpoint = cleansLegacyLiveCheckpoint
        let version = defaults.string(forKey: Self.preferenceKey)
        let persistedInstallationID = defaults.string(forKey: Self.installationIDPreferenceKey)
        let persistedDiagnosticCleanup = defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey)
        observedVersion = version
        queueResetRequired = defaults.bool(forKey: Self.queueResetRequiredPreferenceKey)
        diagnosticCleanupRequired = persistedDiagnosticCleanup
        cachedInstallationID = version == Self.currentVersion
            ? persistedInstallationID.flatMap(UUID.init(uuidString:)) : nil
        schedulingSnapshot = IChartTelemetryConsentSnapshot(
            isGranted: version == Self.currentVersion, generation: 0
        )
        if !self.diagnosticFileURLs.isEmpty { diagnosticCleanupRequired = true }
        if diagnosticCleanupRequired != persistedDiagnosticCleanup { stateRevision &+= 1 }
        if diagnosticCleanupRequired { scheduleLegacyCleanup() }
        // Most launches require no preference change. A no-op main projection
        // would block unrelated admission and could wait behind queue/file I/O.
        // Startup cleanup which did change preferences remains asynchronous:
        // main may be waiting for this shared static initialization to finish.
        let removesUnconsentedIdentity = version != Self.currentVersion && persistedInstallationID != nil
        if removesUnconsentedIdentity || diagnosticCleanupRequired != persistedDiagnosticCleanup {
            persistCurrentState(asynchronously: true)
        }
    }

    var snapshot: IChartTelemetryConsentSnapshot {
        schedulingLock.lock()
        let pending = pendingSchedulingTransition
        schedulingLock.unlock()
        if let pending { return pending }
        refreshPersistedState()
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    /// Advisory capture for caller-side scheduling, never authorization to
    /// persist or send. The service revalidates this exact generation against
    /// `snapshot` before handling a scheduled event or request.
    var cachedSnapshotForScheduling: IChartTelemetryConsentSnapshot {
        schedulingLock.lock()
        defer { schedulingLock.unlock() }
        return schedulingSnapshot
    }

    func trySnapshotForScheduling() -> IChartTelemetryConsentSnapshot? {
        guard schedulingLock.try() else { return nil }
        defer { schedulingLock.unlock() }
        return schedulingSnapshot
    }

    var requiresQueueReset: Bool {
        lock.lock()
        defer { lock.unlock() }
        return queueResetRequired
    }

    var requiresDiagnosticCleanup: Bool {
        lock.lock()
        defer { lock.unlock() }
        return diagnosticCleanupRequired
    }

    /// Registration also removes a leftover when diagnostics are disabled.
    /// The shared store registers the standard library path at startup, so this
    /// does not depend on a configured network telemetry service.
    /// Only retired checkpoint sidecars are eligible for cleanup. Charts and
    /// their source ink are never a cleanup target, even for an invalid caller.
    private static func isLegacyCheckpoint(_ url: URL) -> Bool {
        url.isFileURL && url.lastPathComponent.hasSuffix(".experience-checkpoint.json")
    }

    func registerDiagnosticFile(_ url: URL) {
        guard Self.isLegacyCheckpoint(url) else { return }
        lock.lock()
        diagnosticFileURLs.insert(url.standardizedFileURL)
        diagnosticCleanupRequired = true
        stateRevision &+= 1
        lock.unlock()
        retryDiagnosticCleanup()
    }

    private func scheduleLegacyCleanup() {
        if cleansLegacyLiveCheckpoint {
            diagnosticCleanupQueue.async { [self] in
                registerDiagnosticFile(ChartPersistenceContractDiagnostics.checkpointURL(for: FileChartRepository.live().url))
            }
        } else { retryDiagnosticCleanup() }
    }

    func retryDiagnosticCleanup() {
        diagnosticCleanupQueue.async { [self] in
            lock.lock()
            guard preferenceAuthorizationBlockDepth == 0 else {
                lock.unlock()
                diagnosticCleanupQueue.asyncAfter(deadline: .now() + 0.01) { [self] in retryDiagnosticCleanup() }
                return
            }
            if diagnosticCleanupRequired { retryDiagnosticCleanupLocked() }
            stateRevision &+= 1
            lock.unlock()
            persistCurrentState(asynchronously: true)
        }
    }

    /// Content checkpoint collection has been retired for every consent state.
    func checkpointAuthorization() -> ChartPersistenceDiagnosticAuthorization? { nil }

    @discardableResult
    func publishDiagnosticCheckpoint(
        _ data: Data, to url: URL, authorization: ChartPersistenceDiagnosticAuthorization
    ) throws -> Bool { false }

    /// Publish withdrawal before any optional disk work. The reset marker is
    /// persisted before the selected value so a crash/regrant cannot revive an
    /// old queue. A pending transition never waits on the I/O admission lock.
    func setConsentGranted(_ isGranted: Bool) {
        schedulingLock.lock()
        let previous = schedulingSnapshot
        let transition = IChartTelemetryConsentSnapshot(isGranted: isGranted,
            generation: previous.generation &+ 1)
        schedulingSnapshot = transition
        pendingSchedulingTransition = transition
        schedulingLock.unlock()

        let projectSelection = { [self] in
            guard cachedSnapshotForScheduling == transition else { return }
            defaults.set(true, forKey: Self.queueResetRequiredPreferenceKey)
            guard cachedSnapshotForScheduling == transition else { return }
            defaults.removeObject(forKey: Self.installationIDPreferenceKey)
            guard cachedSnapshotForScheduling == transition else { return }
            if isGranted { defaults.set(Self.currentVersion, forKey: Self.preferenceKey) }
            else { defaults.removeObject(forKey: Self.preferenceKey) }
        }
        if Thread.isMainThread { projectSelection() }
        else { DispatchQueue.main.async(execute: projectSelection) }

        diagnosticCleanupQueue.async { [self] in
            lock.lock()
            guard cachedSnapshotForScheduling == transition else { lock.unlock(); return }
            observedVersion = isGranted ? Self.currentVersion : nil
            generation = transition.generation
            queueResetRequired = true
            cachedInstallationID = nil
            if !isGranted { diagnosticCleanupRequired = true }
            stateRevision &+= 1
            pendingConsentProjectionGeneration = transition.generation
            schedulingLock.lock()
            if pendingSchedulingTransition == transition { pendingSchedulingTransition = nil }
            schedulingLock.unlock()
            lock.unlock()
            persistCurrentState(consentTransition: transition, asynchronously: true)
            if !isGranted {
                // Only the known optional sidecar is eligible. Resolving it is
                // deferred until actual withdrawal or a retained cleanup marker.
                scheduleLegacyCleanup()
            }
        }
    }

    func installationID(for consent: IChartTelemetryConsentSnapshot) -> UUID? {
        refreshPersistedState()
        lock.lock()
        guard consent.isGranted, snapshotLocked() == consent else {
            lock.unlock()
            return nil
        }
        let existingID = cachedInstallationID
        // A preference callback may arrive synchronously on another thread.
        // Reads fail closed instead of waiting for the writer to persist a new
        // identity while that writer is waiting for the callback to return.
        guard existingID != nil || preferenceAuthorizationBlockDepth == 0 else {
            lock.unlock()
            return nil
        }
        let id = existingID ?? UUID()
        if existingID == nil {
            cachedInstallationID = id
            stateRevision &+= 1
        }
        lock.unlock()
        if existingID == nil { persistCurrentState() }
        lock.lock()
        defer { lock.unlock() }
        guard snapshotLocked() == consent, cachedInstallationID == id else { return nil }
        return id
    }

    /// Keep queue changes and request starts atomic with respect to withdrawal.
    func performIfGranted<Value>(
        matching consent: IChartTelemetryConsentSnapshot,
        onDenied: ((IChartTelemetryConsentAdmissionDenial) -> Void)? = nil,
        _ operation: () throws -> Value
    ) rethrows -> Value? {
        guard trySnapshotForScheduling() == consent else {
            onDenied?(.consentChanged)
            return nil
        }
        refreshPersistedState()
        lock.lock()
        let denial: IChartTelemetryConsentAdmissionDenial?
        if preferenceAuthorizationBlockDepth != 0 {
            denial = .preferenceProjectionInProgress
        } else if !consent.isGranted {
            denial = .capturedConsentNotGranted
        } else if snapshotLocked() != consent || trySnapshotForScheduling() != consent {
            denial = .consentChanged
        } else {
            denial = nil
        }
        if let denial {
            lock.unlock()
            // Capture the reason atomically, but permit a diagnostic callback
            // to read this store without reentering its authoritative lock.
            onDenied?(denial)
            return nil
        }
        defer { lock.unlock() }
        return try operation()
    }

    func clearQueuedEvents(
        matching consent: IChartTelemetryConsentSnapshot,
        _ clearQueue: () throws -> Void
    ) rethrows -> Bool {
        refreshPersistedState()
        lock.lock()
        guard preferenceAuthorizationBlockDepth == 0, snapshotLocked() == consent,
              trySnapshotForScheduling() == consent else {
            lock.unlock()
            return false
        }
        do { try clearQueue() }
        catch {
            lock.unlock()
            throw error
        }
        queueResetRequired = false
        stateRevision &+= 1
        lock.unlock()
        persistCurrentState()
        return true
    }

    private func snapshotLocked() -> IChartTelemetryConsentSnapshot {
        IChartTelemetryConsentSnapshot(
            isGranted: observedVersion == Self.currentVersion, generation: generation
        )
    }

    /// Observe direct preference withdrawal without reading UserDefaults while
    /// holding the authoritative lock. A concurrent supported transition or a
    /// synchronous callback from our own write invalidates this read.
    private func refreshPersistedState() {
        lock.lock()
        let revision = stateRevision
        let mayReadPreferences = preferenceWriteDepth == 0
        lock.unlock()
        guard mayReadPreferences else { return }
        schedulingLock.lock()
        let hasPendingTransition = pendingSchedulingTransition != nil
        schedulingLock.unlock()
        guard !hasPendingTransition else { return }
        let version = defaults.string(forKey: Self.preferenceKey)
        let persistedID = defaults.string(forKey: Self.installationIDPreferenceKey).flatMap(UUID.init(uuidString:))
        let persistedQueueReset = defaults.bool(forKey: Self.queueResetRequiredPreferenceKey)
        let persistedDiagnosticCleanup = defaults.bool(forKey: Self.diagnosticCleanupRequiredPreferenceKey)
        lock.lock()
        schedulingLock.lock()
        let transitionIsPending = pendingSchedulingTransition != nil
        schedulingLock.unlock()
        guard preferenceWriteDepth == 0, stateRevision == revision, !transitionIsPending else {
            lock.unlock()
            return
        }
        var changed = false
        // A pending identity/reset projection may still be using older disk
        // values. Only explicit consent transitions suppress version refresh:
        // a routine projection must never hide direct preference revocation.
        let ordinaryStateIsProjected = projectedStateRevision == revision
        if ordinaryStateIsProjected, queueResetRequired != persistedQueueReset {
            queueResetRequired = persistedQueueReset
            changed = true
        }
        if ordinaryStateIsProjected, diagnosticCleanupRequired != persistedDiagnosticCleanup {
            diagnosticCleanupRequired = persistedDiagnosticCleanup
            changed = true
        }
        if pendingConsentProjectionGeneration == nil, version != observedVersion {
            observedVersion = version
            generation &+= 1
            updateSchedulingSnapshotLocked(isGranted: version == Self.currentVersion)
            if version != Self.currentVersion {
                queueResetRequired = true
                diagnosticCleanupRequired = true
                cachedInstallationID = nil
            } else {
                cachedInstallationID = persistedID
            }
            changed = true
        } else if ordinaryStateIsProjected, version == Self.currentVersion, cachedInstallationID != persistedID {
            cachedInstallationID = persistedID
            changed = true
        }
        if changed { stateRevision &+= 1 }
        lock.unlock()
        if changed { persistCurrentState() }
    }

    /// UserDefaults can synchronously notify SwiftUI on main. Every write runs
    /// on main after releasing the authoritative lock, so a background writer
    /// cannot hold a preference lock while main tries to withdraw consent.
    /// Only an explicit transition may change the selected consent preference.
    private func persistCurrentState(
        consentTransition: IChartTelemetryConsentSnapshot? = nil,
        asynchronously: Bool = false,
        deferredConsent: IChartTelemetryConsentSnapshot? = nil
    ) {
        let queuedConsent = deferredConsent ?? cachedSnapshotForScheduling
        let project = { [self] in
            do {
                // Withdrawal publishes this mirror before checkpoint cleanup.
                // Obsolete startup work must not wait on that cleanup on main.
                guard cachedSnapshotForScheduling == queuedConsent else { return }
                guard lock.try() else {
                    // Even an unchanged epoch can be retrying cleanup. Wait off
                    // main, then retry against that same captured startup epoch.
                    DispatchQueue.global(qos: .utility).async { [self] in
                        lock.lock()
                        let isCurrent = snapshotLocked() == queuedConsent
                        lock.unlock()
                        if isCurrent {
                            persistCurrentState(consentTransition: consentTransition,
                                                asynchronously: true, deferredConsent: queuedConsent)
                        }
                    }
                    return
                }
            }
            guard snapshotLocked() == queuedConsent else { lock.unlock(); return }
            // Establish the block under the successful try-lock; a separate
            // preflight unlock would allow I/O to start before this boundary.
            preferenceAuthorizationBlockDepth += 1
            lock.unlock()
            defer {
                lock.lock()
                preferenceAuthorizationBlockDepth -= 1
                lock.unlock()
            }
            if consentTransition == nil { refreshPersistedState() }
            lock.lock()
            let consent = snapshotLocked()
            let version = observedVersion
            preferenceWriteDepth += 1
            lock.unlock()
            func projectOrdinaryState() -> UInt64? {
                while true {
                    lock.lock()
                    // A newer consent epoch owns its own projection. An old
                    // transition must never resume writing after that change.
                    if let consentTransition, snapshotLocked() != consentTransition {
                        lock.unlock()
                        return nil
                    }
                    let revision = stateRevision
                    let queueReset = queueResetRequired
                    let diagnosticCleanup = diagnosticCleanupRequired
                    let installationID = cachedInstallationID
                    lock.unlock()
                    func stillCurrent() -> Bool {
                        lock.lock()
                        defer { lock.unlock() }
                        return stateRevision == revision
                    }
                    guard stillCurrent() else { continue }
                    defaults.set(queueReset, forKey: Self.queueResetRequiredPreferenceKey)
                    guard stillCurrent() else { continue }
                    defaults.set(diagnosticCleanup, forKey: Self.diagnosticCleanupRequiredPreferenceKey)
                    guard stillCurrent() else { continue }
                    if let installationID {
                        defaults.set(installationID.uuidString, forKey: Self.installationIDPreferenceKey)
                    } else {
                        defaults.removeObject(forKey: Self.installationIDPreferenceKey)
                    }
                    // Cleanup or registration may change ordinary fields while
                    // retaining the consent epoch. Recapture them before the
                    // transition can remove consent without a durable reset.
                    if stillCurrent() { return revision }
                }
            }
            let projectedRevision = projectOrdinaryState()
            if let consentTransition {
                lock.lock()
                let mayProjectTransition = snapshotLocked() == consentTransition
                    && pendingConsentProjectionGeneration == consentTransition.generation
                lock.unlock()
                if mayProjectTransition {
                    if let version { defaults.set(version, forKey: Self.preferenceKey) }
                    else { defaults.removeObject(forKey: Self.preferenceKey) }
                }
            }
            lock.lock()
            preferenceWriteDepth -= 1
            if let projectedRevision, stateRevision == projectedRevision {
                projectedStateRevision = projectedRevision
            }
            if let consentTransition,
               pendingConsentProjectionGeneration == consentTransition.generation,
               snapshotLocked() == consent {
                pendingConsentProjectionGeneration = nil
            }
            lock.unlock()
            // A direct preference withdrawal inside a notification must win
            // over this projection before another operation can be admitted.
            refreshPersistedState()
        }
        if asynchronously { DispatchQueue.main.async(execute: project) }
        else if Thread.isMainThread { project() }
        else { DispatchQueue.main.async(execute: project) }
    }

    /// Wait for projections queued by initialization before a relaunch/readback
    /// assertion. Normal consent mutations remain synchronously durable.
    func waitForPendingPersistence() async {
        await withCheckedContinuation { continuation in
            diagnosticCleanupQueue.async { continuation.resume() }
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Call only while holding `lock`; the scheduling reader never takes it.
    private func updateSchedulingSnapshotLocked(isGranted: Bool) {
        schedulingLock.lock()
        if pendingSchedulingTransition == nil {
            schedulingSnapshot = IChartTelemetryConsentSnapshot(isGranted: isGranted, generation: generation)
        }
        schedulingLock.unlock()
    }

    private func retryDiagnosticCleanupLocked() {
        var failed = false
        for url in diagnosticFileURLs {
            do { try removeDiagnosticFile(url) }
            catch { failed = true }
        }
        // Keep the marker across app exits until every registered file has been
        // removed. A later opt-in cannot make failed cleanup look successful.
        diagnosticCleanupRequired = failed
    }
}

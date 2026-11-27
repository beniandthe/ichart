import Combine
import Foundation

/// Voluntary beta membership, never an Apple purchase or subscription receipt.
/// Cache entries are scoped to the account and kept outside shared chart JSON.
@MainActor
final class IChartBetaProStore: ObservableObject {
    @Published private(set) var ownerID: UUID?
    @Published private(set) var isEnrolled = false
    @Published private(set) var freeProAccess = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingNotice: IChartBetaProNotice?
    @Published private(set) var status: IChartBetaProStatus?
    @Published private(set) var productAccessStatus: IChartProductAccessStatus?
    @Published private(set) var resolvedAccessPolicy: IChartProductAccessPolicy
    @Published private(set) var isAccessChecking: Bool
    @Published private(set) var hasFreshProductAccess = false
    @Published private(set) var accessStatusMessage: String?
    let isCoordinatedActivation: Bool

    var canOfferPaidPurchases: Bool {
        guard isCoordinatedActivation else { return IChartProductAccessPolicy.current.offersPaidPurchases }
        return !isOffline && ownerID != nil && hasFreshProductAccess
            && productAccessStatus?.eligible == true && productAccessStatus?.phase == .paid
    }

    private let service: (any IChartBetaProService)?
    private let defaults: UserDefaults
    private var isOffline = false
    private var generation: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskID: UUID?
    private var sessionRecoveryTask: Task<Void, Never>?
    private var sessionRecoveryTaskID: UUID?
    // Only authenticated responses observed in this process establish a floor.
    // A corrupt persisted revision must not suppress a fresh server response.
    private var lastServerRevision: Int64?
    private var lastServerNow: Date?
    private var acceptedProductResponseCounter: UInt64 = 0

    init(service: (any IChartBetaProService)?, defaults: UserDefaults = IChartStorageNamespace.defaults,
         isCoordinatedActivation: Bool = IChartProductAccessPolicy.usesCoordinatedActivation) {
        self.service = service
        self.defaults = defaults
        self.isCoordinatedActivation = isCoordinatedActivation
        resolvedAccessPolicy = isCoordinatedActivation || IChartProductAccessPolicy.current.isFreeBeta
            ? .betaBasic : .current
        isAccessChecking = isCoordinatedActivation
        accessStatusMessage = isCoordinatedActivation ? "Checking plan access. Your saved work is available." : nil
    }

    /// Apply synchronously before other services observe a new account.
    /// Refresh is explicit so callers can update feature gates before awaiting.
    func authStateChanged(ownerID nextOwnerID: UUID?, isOffline nextOffline: Bool = false) {
        guard ownerID != nextOwnerID || isOffline != nextOffline else { return }
        let previousOwner = ownerID
        let previousProductStatus = productAccessStatus
        if previousOwner != nextOwnerID {
            lastServerRevision = nil
            lastServerNow = nil
        }
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskID = nil
        // A new auth phase needs its own recovery attempt, even for the same
        // owner. Do not cancel the old task: it may be initiating this very
        // offline-to-online transition. Its ID cannot clear a newer attempt.
        sessionRecoveryTask = nil
        sessionRecoveryTaskID = nil
        ownerID = nextOwnerID
        isOffline = nextOffline
        isWorking = false
        errorMessage = nil
        status = nil
        pendingNotice = nil
        if isCoordinatedActivation {
            hasFreshProductAccess = false
            isAccessChecking = true
            accessStatusMessage = nextOffline
                ? "Connect to refresh plan access. Your saved work is available."
                : "Checking plan access. Your saved work is available."
            let retained = previousOwner == nextOwnerID ? previousProductStatus : nil
            productAccessStatus = nextOwnerID.flatMap { owner in retained ?? cachedProductStatus(ownerID: owner) }
            // A same-owner legacy beta choice can retain local tools during an
            // offline upgrade. It is not a v2 phase, fresh service grant or sale.
            let legacyLocalPolicy: IChartProductAccessPolicy = nextOwnerID.flatMap { owner in
                cachedBool("access", ownerID: owner)
            } == true ? .freeAllFeatures : .betaBasic
            resolvedAccessPolicy = IChartProductAccessResolver.resolve(status: productAccessStatus, fallback: legacyLocalPolicy)
            status = productAccessStatus?.betaStatus
            isEnrolled = productAccessStatus?.participating ?? true
            freeProAccess = productAccessStatus?.freeProAccess ?? false
            if nextOwnerID == nil {
                productAccessStatus = nil
                resolvedAccessPolicy = .betaBasic
                status = nil
                isEnrolled = false
                freeProAccess = false
            }
            return
        }
        guard let nextOwnerID else {
            isEnrolled = false
            freeProAccess = false
            resolvedAccessPolicy = IChartProductAccessPolicy.current.isFreeBeta ? .betaBasic : .current
            return
        }
        isEnrolled = cachedBool("participating", ownerID: nextOwnerID) ?? true
        freeProAccess = cachedBool("access", ownerID: nextOwnerID) ?? isEnrolled
        resolvedAccessPolicy = IChartProductAccessPolicy.current.isFreeBeta
            ? (freeProAccess ? .freeAllFeatures : .betaBasic) : .current
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        guard let requestOwner = ownerID, !isOffline, let service, !isWorking else { return }
        generation &+= 1
        let requestGeneration = generation
        let acceptedResponseAtStart = acceptedProductResponseCounter
        let requestID = UUID()
        isWorking = true
        errorMessage = nil
        // The store owns the request. A backgrounded view may cancel its waiter,
        // but the next foreground waiter must still receive this current read.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.refreshTaskID == requestID {
                    self.refreshTask = nil
                    self.refreshTaskID = nil
                }
                if self.isCurrent(requestOwner, requestGeneration) { self.isWorking = false }
            }
            do {
                if self.isCoordinatedActivation {
                    let response = try await service.fetchProductAccessStatus(for: requestOwner)
                    guard self.isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return }
                    try self.applyProductAccess(response, expectedOwner: requestOwner)
                } else {
                    let response = try await service.fetchStatus(for: requestOwner)
                    guard self.isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return }
                    try self.apply(response, expectedOwner: requestOwner)
                }
            } catch {
                guard self.isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return }
                if self.isCoordinatedActivation {
                    if self.acceptedProductResponseCounter == acceptedResponseAtStart,
                       (error as? IChartBetaProServiceError) != .staleProductAccess {
                        self.markProductAccessUnavailable()
                    }
                } else {
                    self.errorMessage = "Could not refresh your free Pro settings. This iPad is still using your last confirmed setting. Try again when connected."
                }
            }
        }
        refreshTaskID = requestID
        refreshTask = task
        await task.value
    }

    /// The app supplies real session recovery followed by synchronous account /
    /// access-policy synchronization. Only then may a read reconcile membership.
    /// This never repeats a possibly committed participation mutation.
    func retryAfterSessionRecovery(_ recoverSession: @escaping @MainActor () async -> Void) async {
        if let sessionRecoveryTask {
            await sessionRecoveryTask.value
            return
        }
        guard let requestOwner = ownerID else { return }
        // Never mistake an in-flight mutation for a refresh to be coalesced.
        guard !isWorking else {
            if let refreshTask { await refreshTask.value }
            return
        }
        let requestID = UUID()
        let task = Task { @MainActor [weak self] in
            defer {
                if self?.sessionRecoveryTaskID == requestID {
                    self?.sessionRecoveryTask = nil
                    self?.sessionRecoveryTaskID = nil
                }
            }
            await recoverSession()
            guard let self, self.ownerID == requestOwner else { return }
            await self.refresh()
        }
        sessionRecoveryTaskID = requestID
        sessionRecoveryTask = task
        await task.value
    }

    /// Success means the current owner's server response confirmed the choice.
    /// Failed, offline, or stale requests never pretend membership was saved.
    @discardableResult
    func setParticipating(_ participating: Bool) async -> Bool {
        guard let requestOwner = ownerID else {
            errorMessage = "Sign in to change your free Pro settings."
            return false
        }
        return await setParticipating(participating, for: requestOwner)
    }

    /// UI actions must pass the owner captured when the button/dialog opened.
    /// A stale action is silently discarded instead of changing a new account.
    @discardableResult
    func setParticipating(_ participating: Bool, for requestOwner: UUID) async -> Bool {
        guard ownerID == requestOwner else { return false }
        if isCoordinatedActivation && (!hasFreshProductAccess || productAccessStatus?.phase != .freeBeta) {
            errorMessage = "Refresh plan access before changing free Pro participation. Your saved work is kept."
            return false
        }
        guard !isOffline, let service else {
            errorMessage = "Connect to the internet to save this choice. Your last saved choice is unchanged."
            return false
        }
        guard !isWorking else { return false }
        generation &+= 1
        let requestGeneration = generation
        let acceptedResponseAtStart = acceptedProductResponseCounter
        isWorking = true
        errorMessage = nil
        defer { if isCurrent(requestOwner, requestGeneration) { isWorking = false } }
        do {
            let response = try await service.setParticipation(participating, for: requestOwner)
            guard isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return false }
            guard response.participating == participating else {
                throw IChartBetaProServiceError.participationNotConfirmed
            }
            if isCoordinatedActivation {
                let productResponse = try await service.fetchProductAccessStatus(for: requestOwner)
                guard isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return false }
                guard productResponse.participating == participating else {
                    throw IChartBetaProServiceError.participationNotConfirmed
                }
                try applyProductAccess(productResponse, expectedOwner: requestOwner)
            } else {
                try apply(response, expectedOwner: requestOwner)
            }
            return true
        } catch {
            guard isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return false }
            if isCoordinatedActivation, acceptedProductResponseCounter == acceptedResponseAtStart {
                markProductAccessUnavailable()
            }
            errorMessage = "Could not confirm your Pro choice. This iPad is still using your last confirmed setting. Reconnect to check your account."
            return false
        }
    }

    func acknowledgeNotice(_ noticeID: String) {
        guard let ownerID else { return }
        acknowledgeNotice(noticeID, for: ownerID)
    }

    func acknowledgeNotice(_ noticeID: String, for expectedOwnerID: UUID) {
        guard let ownerID, ownerID == expectedOwnerID, status?.ownerID == ownerID,
              pendingNotice?.id == noticeID else { return }
        defaults.set(noticeID, forKey: cacheKey("seenNotice", ownerID: ownerID))
        pendingNotice = nil
    }

    func acknowledgeNotice() {
        guard let noticeID = pendingNotice?.id else { return }
        acknowledgeNotice(noticeID)
    }

    private func apply(_ response: IChartBetaProStatus, expectedOwner: UUID) throws {
        guard response.ownerID == expectedOwner else { throw IChartBetaProServiceError.accountChanged }
        guard response.hasConsistentAccess else { throw IChartBetaProServiceError.inconsistentStatus }
        status = response
        isEnrolled = response.participating
        freeProAccess = response.freeProAccess
        resolvedAccessPolicy = IChartProductAccessPolicy.current.isFreeBeta
            ? (freeProAccess ? .freeAllFeatures : .betaBasic) : .current
        defaults.set(response.participating, forKey: cacheKey("participating", ownerID: expectedOwner))
        defaults.set(response.freeProAccess, forKey: cacheKey("access", ownerID: expectedOwner))
        let seenNotice = defaults.string(forKey: cacheKey("seenNotice", ownerID: expectedOwner))
        pendingNotice = response.notice.flatMap { $0.id == seenNotice ? nil : $0 }
    }

    /// A checkout never reuses a cached or coalesced foreground read. The owner
    /// and generation are checked again after this independent authenticated RPC.
    func authorizePaidCheckout(expectedOwnerID: UUID) async -> Bool {
        guard isCoordinatedActivation else { return IChartProductAccessPolicy.current.offersPaidPurchases }
        guard ownerID == expectedOwnerID, !isOffline, let service else { return false }
        let requestGeneration = generation
        let acceptedResponseAtStart = acceptedProductResponseCounter
        do {
            let response = try await service.fetchProductAccessStatus(for: expectedOwnerID)
            guard isCurrent(expectedOwnerID, requestGeneration), !Task.isCancelled else { return false }
            try applyProductAccess(response, expectedOwner: expectedOwnerID)
            return canOfferPaidPurchases
        } catch {
            guard isCurrent(expectedOwnerID, requestGeneration) else { return false }
            // An older in-flight read cannot revoke freshness established by a
            // newer response, but it can never authorize this checkout.
            if acceptedProductResponseCounter == acceptedResponseAtStart,
               (error as? IChartBetaProServiceError) != .staleProductAccess {
                markProductAccessUnavailable()
            }
            return false
        }
    }

    private func applyProductAccess(_ response: IChartProductAccessStatus, expectedOwner: UUID) throws {
        guard response.ownerID == expectedOwner else { throw IChartBetaProServiceError.accountChanged }
        guard response.isRecognizedAndConsistent else { throw IChartBetaProServiceError.inconsistentStatus }
        if let revision = lastServerRevision {
            guard response.policyRevision >= revision else { throw IChartBetaProServiceError.staleProductAccess }
            if response.policyRevision == revision, let serverNow = lastServerNow,
               response.serverNow < serverNow { throw IChartBetaProServiceError.staleProductAccess }
        }
        acceptedProductResponseCounter &+= 1
        lastServerRevision = response.policyRevision
        lastServerNow = response.serverNow
        productAccessStatus = response
        status = response.betaStatus
        isEnrolled = response.participating
        freeProAccess = response.freeProAccess
        resolvedAccessPolicy = IChartProductAccessResolver.resolve(status: response, fallback: resolvedAccessPolicy)
        hasFreshProductAccess = true
        isAccessChecking = false
        accessStatusMessage = nil
        errorMessage = nil
        if let data = try? JSONEncoder().encode(response) {
            defaults.set(data, forKey: productCacheKey(ownerID: expectedOwner))
        }
        let seenNotice = defaults.string(forKey: cacheKey("seenNotice", ownerID: expectedOwner))
        pendingNotice = response.betaStatus.notice.flatMap { $0.id == seenNotice ? nil : $0 }
    }

    private func markProductAccessUnavailable() {
        hasFreshProductAccess = false
        isAccessChecking = true
        accessStatusMessage = "Plan access could not be refreshed. Your saved work and last confirmed local access are kept. Try again when connected."
        errorMessage = accessStatusMessage
    }

    private func cachedProductStatus(ownerID: UUID) -> IChartProductAccessStatus? {
        guard let data = defaults.data(forKey: productCacheKey(ownerID: ownerID)), data.count <= 65_536,
              let response = try? JSONDecoder().decode(IChartProductAccessStatus.self, from: data),
              response.ownerID == ownerID, response.isRecognizedAndConsistent else { return nil }
        return response
    }

    private func productCacheKey(ownerID: UUID) -> String {
        "iChart.productAccess.v1.\(IChartStorageNamespace.productAccessCacheProjectRef).\(ownerID.uuidString.lowercased())"
    }

    private func isCurrent(_ requestOwner: UUID, _ requestGeneration: UInt64) -> Bool {
        ownerID == requestOwner && generation == requestGeneration
    }

    private func cachedBool(_ field: String, ownerID: UUID) -> Bool? {
        defaults.object(forKey: cacheKey(field, ownerID: ownerID)) as? Bool
    }

    private func cacheKey(_ field: String, ownerID: UUID) -> String {
        "iChart.betaPro.v1.\(ownerID.uuidString.lowercased()).\(field)"
    }
}

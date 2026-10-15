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

    private let service: (any IChartBetaProService)?
    private let defaults: UserDefaults
    private var isOffline = false
    private var generation: UInt64 = 0

    init(service: (any IChartBetaProService)?, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    /// Apply synchronously before other services observe a new account.
    /// Refresh is explicit so callers can update feature gates before awaiting.
    func authStateChanged(ownerID nextOwnerID: UUID?, isOffline nextOffline: Bool = false) {
        guard ownerID != nextOwnerID || isOffline != nextOffline else { return }
        generation &+= 1
        ownerID = nextOwnerID
        isOffline = nextOffline
        isWorking = false
        errorMessage = nil
        status = nil
        pendingNotice = nil
        guard let nextOwnerID else {
            isEnrolled = false
            freeProAccess = false
            return
        }
        isEnrolled = cachedBool("participating", ownerID: nextOwnerID) ?? true
        freeProAccess = cachedBool("access", ownerID: nextOwnerID) ?? isEnrolled
    }

    func refresh() async {
        guard let requestOwner = ownerID, !isOffline, let service, !isWorking else { return }
        generation &+= 1
        let requestGeneration = generation
        isWorking = true
        errorMessage = nil
        defer { if isCurrent(requestOwner, requestGeneration) { isWorking = false } }
        do {
            let response = try await service.fetchStatus(for: requestOwner)
            guard isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return }
            try apply(response, expectedOwner: requestOwner)
        } catch {
            guard isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return }
            errorMessage = "Could not refresh your free Pro settings. Your last saved choice is unchanged. Try again when connected."
        }
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
        guard !isOffline, let service else {
            errorMessage = "Connect to the internet to save this choice. Your last saved choice is unchanged."
            return false
        }
        guard !isWorking else { return false }
        generation &+= 1
        let requestGeneration = generation
        isWorking = true
        errorMessage = nil
        defer { if isCurrent(requestOwner, requestGeneration) { isWorking = false } }
        do {
            let response = try await service.setParticipation(participating, for: requestOwner)
            guard isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return false }
            guard response.participating == participating else {
                throw IChartBetaProServiceError.participationNotConfirmed
            }
            try apply(response, expectedOwner: requestOwner)
            return true
        } catch {
            guard isCurrent(requestOwner, requestGeneration), !Task.isCancelled else { return false }
            errorMessage = "Your free Pro choice could not be saved. Your last saved choice is unchanged. Please try again."
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
        defaults.set(response.participating, forKey: cacheKey("participating", ownerID: expectedOwner))
        defaults.set(response.freeProAccess, forKey: cacheKey("access", ownerID: expectedOwner))
        let seenNotice = defaults.string(forKey: cacheKey("seenNotice", ownerID: expectedOwner))
        pendingNotice = response.notice.flatMap { $0.id == seenNotice ? nil : $0 }
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

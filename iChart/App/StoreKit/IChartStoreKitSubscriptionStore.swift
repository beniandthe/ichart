import Foundation
import StoreKit
import Supabase
#if canImport(UIKit)
import UIKit
#endif

enum IChartStoreKitSubscriptionState: Equatable {
    case idle
    case loading
    case claiming
    case purchasing
    case restoring
    case managing
    case ready
    case localPreviewActive
    case unavailable(String)

    var isWorking: Bool {
        switch self {
        case .loading, .claiming, .purchasing, .restoring, .managing:
            return true
        case .idle, .ready, .localPreviewActive, .unavailable:
            return false
        }
    }

    var statusText: String? {
        switch self {
        case .idle, .ready:
            return nil
        case .loading:
            return "Checking subscription..."
        case .claiming:
            return "Verifying subscription with iChart..."
        case .purchasing:
            return "Opening purchase..."
        case .restoring:
            return "Restoring purchases..."
        case .managing:
            return "Opening subscription management..."
        case .localPreviewActive:
            #if DEBUG && targetEnvironment(simulator)
            return "Pro preview is active on this device."
            #else
            return nil
            #endif
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
final class IChartStoreKitSubscriptionStore: ObservableObject {
    private static let pendingComplimentaryPurchaseKey = "iChartPendingComplimentaryPurchase.v1"

    @Published private(set) var products: [Product] = []
    @Published private(set) var productOptions: [IChartStoreKitProductOption] = []
    @Published private(set) var entitlement: IChartSubscriptionEntitlement
    @Published private(set) var state: IChartStoreKitSubscriptionState = .idle
    @Published private(set) var complimentaryOffers: [IChartComplimentaryOffer] = []
    @Published private(set) var complimentaryOfferStatuses: [IChartComplimentaryOfferStatus] = []

    private let productIDs: [String]
    private let subscriptionClaimService: IChartStoreKitSubscriptionClaiming?
    private var productsByID: [String: Product] = [:]
    private var transactionUpdatesTask: Task<Void, Never>?
    private var complimentaryAttemptIDsByProduct: [String: UUID] = [:]
    private var complimentaryPurchaseInFlight = false

    private init(
        productIDs: [String] = IChartStoreKitProductCatalog.proProductIDs,
        entitlement: IChartSubscriptionEntitlement = .basic,
        subscriptionClaimService: IChartStoreKitSubscriptionClaiming? = nil
    ) {
        self.productIDs = productIDs
        self.entitlement = entitlement
        self.subscriptionClaimService = subscriptionClaimService
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    static func live(clients: IChartSupabaseClients? = nil) -> IChartStoreKitSubscriptionStore {
        let claimService = clients.map {
            IChartSupabaseStoreKitSubscriptionClaimService(
                authClient: $0.authClient,
                dataClient: $0.dataClient,
                sessionStore: $0.sessionStore
            )
        }
        return IChartStoreKitSubscriptionStore(subscriptionClaimService: claimService)
    }

    func bootstrap() async {
        removeLegacyDebugSignedTransactionCapture()

        guard !productIDs.isEmpty else {
            entitlement = .unavailable
            state = .unavailable("Pro subscriptions are temporarily unavailable.")
            return
        }

        await loadProducts()
        await recoverUnfinishedTransactions()
        listenForTransactionUpdates()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        await refreshEntitlements(preferredSignedTransactionInfo: nil)
    }

    private func refreshEntitlements(preferredSignedTransactionInfo: String?) async {
        complimentaryOffers = []
        complimentaryOfferStatuses = []
        complimentaryAttemptIDsByProduct = [:]
        state = .loading
        let expectedOwnerID = try? await subscriptionClaimService?.appAccountToken()
        let localEvaluation = await evaluateLocalStoreKitEntitlements(
            preferredSignedTransactionInfo: preferredSignedTransactionInfo
        )

        if let subscriptionClaimService {
            if localEvaluation.signedTransactionInfo != nil { state = .claiming }
            let resolution = await IChartSubscriptionAccessRecovery.resolve(
                expectedOwnerID: expectedOwnerID,
                signedTransactionInfo: localEvaluation.signedTransactionInfo,
                service: subscriptionClaimService,
                now: Date()
            )
            switch resolution {
            case .verified(let verifiedEntitlement, _):
                entitlement = verifiedEntitlement
                state = .ready
            case .noRemoteSubscription:
                entitlement = IChartStoreKitEntitlementResolver.serverBackedEntitlement(
                    remoteEntitlement: nil,
                    localEntitlement: localEvaluation.entitlement
                )
                state = .ready
            case .unavailable(let claimFailed):
                if !claimFailed,
                   let fallbackEntitlement = IChartStoreKitEntitlementResolver.serverBackedFallbackForRemoteFailure(
                       localEntitlement: localEvaluation.entitlement
                   ) {
                    entitlement = fallbackEntitlement
                    state = .ready
                } else {
                    applyClaimFailureFallback(localEvaluation.entitlement)
                }
            }
            await refreshComplimentaryOffers()
            return
        }

        entitlement = localEvaluation.entitlement
        state = localEvaluation.state
        await refreshComplimentaryOffers()
    }

    private func evaluateLocalStoreKitEntitlements(
        preferredSignedTransactionInfo: String?
    ) async -> StoreKitEntitlementEvaluation {
        let now = Date()

        var activeProExpiration: Date?
        var sawExpiredProTransaction = false
        var latestSignedTransactionInfo = preferredSignedTransactionInfo

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  IChartStoreKitProductCatalog.isProProductID(transaction.productID) else {
                continue
            }

            if transaction.revocationDate != nil {
                sawExpiredProTransaction = true
                continue
            }

            if let expirationDate = transaction.expirationDate {
                if expirationDate > Date() {
                    activeProExpiration = max(activeProExpiration ?? expirationDate, expirationDate)
                    latestSignedTransactionInfo = result.jwsRepresentation
                } else {
                    sawExpiredProTransaction = true
                }
            } else {
                activeProExpiration = .distantFuture
                latestSignedTransactionInfo = result.jwsRepresentation
            }
        }

        let entitlement = IChartStoreKitEntitlementResolver.entitlement(
            hasActiveProSubscription: activeProExpiration != nil,
            sawExpiredProTransaction: sawExpiredProTransaction,
            accessEndsAt: activeProExpiration == .distantFuture ? nil : activeProExpiration,
            verifiedAt: now
        )

        return StoreKitEntitlementEvaluation(
            entitlement: entitlement,
            signedTransactionInfo: activeProExpiration == nil ? nil : latestSignedTransactionInfo,
            state: .ready
        )
    }

    func purchase(_ product: Product) async {
        state = .purchasing
        let startedAt = Date()
        IChartTelemetry.record(
            "subscription.purchase_started",
            properties: ["target": .string(product.id)]
        )

        do {
            let purchaseOptions = try await storeKitPurchaseOptions()
            let result = try await product.purchase(options: purchaseOptions)

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    entitlement = .unavailable
                    state = .unavailable("Purchase could not be verified.")
                    IChartTelemetry.record(
                        "subscription.purchase_failed",
                        properties: [
                            "target": .string(product.id),
                            "error_code": .string("unverified_transaction"),
                            "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                        ]
                    )
                    return
                }

                let signedTransactionInfo = verification.jwsRepresentation
                await transaction.finish()
                await refreshEntitlements(preferredSignedTransactionInfo: signedTransactionInfo)
                IChartTelemetry.record(
                    "subscription.purchase_succeeded",
                    properties: [
                        "target": .string(product.id),
                        "plan": .string(entitlement.effectivePlan.rawValue),
                        "subscription_status": .string(entitlement.status.rawValue),
                        "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                    ]
                )
            case .pending:
                state = .unavailable("Purchase is pending approval.")
                IChartTelemetry.record(
                    "subscription.purchase_failed",
                    properties: [
                        "target": .string(product.id),
                        "error_code": .string("pending"),
                        "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                    ]
                )
            case .userCancelled:
                state = .ready
                IChartTelemetry.record(
                    "subscription.purchase_failed",
                    properties: [
                        "target": .string(product.id),
                        "error_code": .string("user_cancelled"),
                        "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                    ]
                )
            @unknown default:
                entitlement = .unavailable
                state = .unavailable("Purchase status is unavailable.")
                IChartTelemetry.record(
                    "subscription.purchase_failed",
                    properties: [
                        "target": .string(product.id),
                        "error_code": .string("unknown_result"),
                        "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                    ]
                )
            }
        } catch {
            entitlement = .unavailable
            state = .unavailable("Purchase failed. Try again from Settings.")
            IChartTelemetry.record(
                "subscription.purchase_failed",
                properties: [
                    "target": .string(product.id),
                    "error_code": .string("purchase_error"),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                ]
            )
        }
    }

    func purchase(_ option: IChartStoreKitProductOption) async {
        if let product = productsByID[option.id] {
            await purchase(product)
            return
        }

        #if DEBUG && targetEnvironment(simulator)
        state = .purchasing
        applyLocalPreview(.activePro(verifiedAt: Date()))
        #else
        entitlement = .unavailable
        state = .unavailable("Pro subscriptions could not be loaded.")
        #endif
    }

    @discardableResult
    func purchaseComplimentaryOffer(_ displayedOffer: IChartComplimentaryOffer) async -> Bool {
        guard !complimentaryPurchaseInFlight,
              complimentaryOffers.contains(displayedOffer),
              let subscriptionClaimService else {
            state = .unavailable("The complimentary offer is no longer available. Refresh and try again.")
            return false
        }

        state = .purchasing
        complimentaryPurchaseInFlight = true
        defer { complimentaryPurchaseInFlight = false }

        let startedAt = Date()
        let attemptID = UUID()
        var applePurchaseAttempted = false
        var applePurchaseAccepted = false
        IChartTelemetry.record(
            "subscription.purchase_started",
            properties: [
                "target": .string(displayedOffer.productID),
                "flow": .string("complimentary"),
                "result": .string(displayedOffer.activation.rawValue)
            ]
        )

        do {
            guard let accountID = try await subscriptionClaimService.appAccountToken() else {
                throw ComplimentaryPurchaseError.missingAccount
            }

            let fetched = try await Product.products(for: [displayedOffer.productID])
            guard fetched.count == 1,
                  let product = fetched.first,
                  product.id == displayedOffer.productID else {
                throw ComplimentaryPurchaseError.productUnavailable
            }

            let signedHistory = await latestVerifiedSignedTransactionInfo(for: product.id)
            let statusResponse = try await subscriptionClaimService.complimentaryOffer(
                request: IChartComplimentaryOfferServerRequest(
                    action: .status,
                    productID: product.id,
                    signedTransactionInfo: signedHistory
                )
            )
            guard let resolved = await resolvedComplimentaryOffer(
                response: statusResponse,
                product: product
            ), resolved == displayedOffer else {
                throw ComplimentaryPurchaseError.offerChanged
            }

            let previousAttemptID = statusResponse.attemptID.flatMap(UUID.init(uuidString:))
                ?? complimentaryAttemptIDsByProduct[product.id]
            guard try await subscriptionClaimService.appAccountToken() == accountID else {
                throw ComplimentaryPurchaseError.accountChanged
            }

            // Once this request is dispatched, a lost response can still have
            // prepared the attempt on the server. A later explicit tap always
            // creates a new attempt and discovers this one through status.
            complimentaryAttemptIDsByProduct[product.id] = attemptID
            let preparedResponse = try await subscriptionClaimService.complimentaryOffer(
                request: IChartComplimentaryOfferServerRequest(
                    action: .prepare,
                    productID: product.id,
                    signedTransactionInfo: signedHistory,
                    attemptID: attemptID,
                    previousAttemptID: previousAttemptID
                )
            )
            guard let authorization = IChartComplimentaryOfferPolicy.preparedAuthorization(
                response: preparedResponse,
                displayedOffer: displayedOffer,
                attemptID: attemptID
            ) else {
                throw ComplimentaryPurchaseError.authorizationRejected
            }
            guard try await subscriptionClaimService.appAccountToken() == accountID else {
                throw ComplimentaryPurchaseError.accountChanged
            }

            var purchaseOptions: Set<Product.PurchaseOption> = [.appAccountToken(accountID)]
            if let signature = authorization.signature {
                guard let offerID = authorization.offer.offerID,
                      let nonce = UUID(uuidString: signature.nonce),
                      let signatureData = Data(base64Encoded: signature.signature) else {
                    throw ComplimentaryPurchaseError.authorizationRejected
                }
                purchaseOptions.insert(.promotionalOffer(
                    offerID: offerID,
                    keyID: signature.keyID,
                    nonce: nonce,
                    signature: signatureData,
                    timestamp: signature.timestamp
                ))
            }

            guard savePendingComplimentaryPurchase(IChartPendingComplimentaryPurchase(
                accountID: accountID,
                productID: product.id,
                attemptID: attemptID,
                decision: displayedOffer.decision,
                offerID: displayedOffer.offerID
            )) else {
                throw ComplimentaryPurchaseError.pendingContextUnavailable
            }

            applePurchaseAttempted = true
            let result = try await product.purchase(options: purchaseOptions)
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == product.id,
                      transaction.appAccountToken == accountID else {
                    throw ComplimentaryPurchaseError.unverifiedTransaction
                }
                applePurchaseAccepted = true
                guard try await subscriptionClaimService.appAccountToken() == accountID else {
                    // Do not finish: StoreKit can redeliver the verified
                    // transaction after the original account is restored.
                    throw ComplimentaryPurchaseError.accountChanged
                }

                let signedTransactionInfo = verification.jwsRepresentation
                guard let claimedEntitlement = try await subscriptionClaimService.claim(
                    signedTransactionInfo: signedTransactionInfo,
                    expectedOwnerID: accountID
                ) else {
                    throw ComplimentaryPurchaseError.claimRejected
                }
                guard try await subscriptionClaimService.appAccountToken() == accountID else {
                    throw ComplimentaryPurchaseError.accountChanged
                }
                // An accepted, same-owner ordinary claim establishes access even
                // if campaign confirmation is pending. It does not finish the gift.
                entitlement = claimedEntitlement
                let confirmedResponse = try await subscriptionClaimService.complimentaryOffer(
                    request: IChartComplimentaryOfferServerRequest(
                        action: .confirm,
                        productID: product.id,
                        signedTransactionInfo: signedTransactionInfo,
                        attemptID: attemptID
                    )
                )
                guard IChartComplimentaryOfferPolicy.matchesConfirmedCampaign(
                    confirmedResponse,
                    offer: displayedOffer,
                    attemptID: attemptID
                ) else {
                    // Leave the transaction unfinished so a transient server
                    // failure never becomes an unconfirmed local success.
                    throw ComplimentaryPurchaseError.confirmationRejected
                }
                guard try await subscriptionClaimService.appAccountToken() == accountID else {
                    // Confirmation is attributed to the original app account;
                    // never finish it after the signed-in account changes.
                    throw ComplimentaryPurchaseError.accountChanged
                }

                await transaction.finish()
                removePendingComplimentaryPurchase(attemptID: attemptID)
                complimentaryAttemptIDsByProduct[product.id] = nil
                await refreshEntitlements(preferredSignedTransactionInfo: signedTransactionInfo)
                IChartTelemetry.record(
                    "subscription.purchase_succeeded",
                    properties: [
                        "target": .string(product.id),
                        "flow": .string("complimentary"),
                        "result": .string(displayedOffer.activation.rawValue),
                        "plan": .string(entitlement.effectivePlan.rawValue),
                        "subscription_status": .string(entitlement.status.rawValue),
                        "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                    ]
                )
                return true
            case .pending:
                complimentaryOffers.removeAll { $0.productID == product.id }
                state = .unavailable("Apple is still reviewing this offer. No paid purchase was made.")
                recordComplimentaryFailure(
                    "pending", target: product.id, activation: displayedOffer.activation, startedAt: startedAt
                )
                return false
            case .userCancelled:
                removePendingComplimentaryPurchase(attemptID: attemptID)
                state = .ready
                recordComplimentaryFailure(
                    "user_cancelled", target: product.id, activation: displayedOffer.activation, startedAt: startedAt
                )
                return false
            @unknown default:
                state = .unavailable("The complimentary offer status is unavailable. No paid purchase was made.")
                recordComplimentaryFailure(
                    "unknown_result", target: product.id, activation: displayedOffer.activation, startedAt: startedAt
                )
                return false
            }
        } catch let error as ComplimentaryPurchaseError {
            if applePurchaseAttempted {
                complimentaryOffers.removeAll { $0.productID == displayedOffer.productID }
            }
            state = .unavailable(
                applePurchaseAccepted
                    ? "Apple accepted the offer, but iChart confirmation is pending. It will retry without buying again."
                    : error.userMessage
            )
            recordComplimentaryFailure(
                error.telemetryCode,
                target: displayedOffer.productID,
                activation: displayedOffer.activation,
                startedAt: startedAt
            )
            return false
        } catch {
            if applePurchaseAttempted {
                complimentaryOffers.removeAll { $0.productID == displayedOffer.productID }
            }
            state = .unavailable(
                applePurchaseAccepted
                    ? "Apple accepted the offer, but iChart confirmation is pending. It will retry without buying again."
                    : "The complimentary offer could not be verified. No paid purchase was made."
            )
            recordComplimentaryFailure(
                "campaign_error",
                target: displayedOffer.productID,
                activation: displayedOffer.activation,
                startedAt: startedAt
            )
            return false
        }
    }

    func restorePurchases() async {
        state = .restoring
        let startedAt = Date()
        IChartTelemetry.record("subscription.restore_started")

        do {
            try await AppStore.sync()
            await refreshEntitlements(preferredSignedTransactionInfo: nil)
            IChartTelemetry.record(
                "subscription.restore_succeeded",
                properties: [
                    "plan": .string(entitlement.effectivePlan.rawValue),
                    "subscription_status": .string(entitlement.status.rawValue),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                ]
            )
        } catch {
            entitlement = .unavailable
            state = .unavailable("Restore failed. Try again when you are online.")
            IChartTelemetry.record(
                "subscription.restore_failed",
                properties: [
                    "error_code": .string("restore_error"),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
                ]
            )
        }
    }

    func manageSubscriptions() async {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            state = .unavailable("Subscription management is unavailable from this window.")
            return
        }

        state = .managing

        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await refreshEntitlements(preferredSignedTransactionInfo: nil)
        } catch {
            state = .unavailable("Could not open subscription management.")
        }
        #else
        state = .unavailable("Subscription management is unavailable on this platform.")
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    func applyLocalPreview(_ entitlement: IChartSubscriptionEntitlement) {
        self.entitlement = entitlement
        state = entitlement.status == .proActive ? .localPreviewActive : .ready
    }
    #endif

    private func refreshComplimentaryOffers() async {
        complimentaryOffers = []
        complimentaryOfferStatuses = []
        complimentaryAttemptIDsByProduct = [:]

        guard let subscriptionClaimService, !products.isEmpty else {
            return
        }

        do {
            guard let initialAccountID = try await subscriptionClaimService.appAccountToken() else {
                return
            }

            var refreshedOffers: [IChartComplimentaryOffer] = []
            var refreshedStatuses: [IChartComplimentaryOfferStatus] = []
            var refreshedAttempts: [String: UUID] = [:]
            var acknowledgedPendingPurchases: [IChartPendingComplimentaryPurchase] = []
            var enabledCampaignID: String?

            for product in products {
                let signedHistory = await latestVerifiedSignedTransactionInfo(for: product.id)
                let response = try await subscriptionClaimService.complimentaryOffer(
                    request: IChartComplimentaryOfferServerRequest(
                        action: .status,
                        productID: product.id,
                        signedTransactionInfo: signedHistory
                    )
                )

                guard response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion else {
                    return
                }

                if response.enabled {
                    if let enabledCampaignID, enabledCampaignID != response.campaignID {
                        return
                    }
                    enabledCampaignID = response.campaignID
                }

                if response.productID != product.id {
                    // A status lookup may report an already scheduled or
                    // redeemed benefit on the user's other Pro product. It is
                    // display-only: a mismatched response can never authorize
                    // a new purchase or a crossgrade.
                    guard let status = IChartComplimentaryOfferPolicy.confirmedStatus(response: response),
                          productsByID[status.productID] != nil else {
                        return
                    }
                    if !refreshedStatuses.contains(where: { $0.id == status.id }) {
                        refreshedStatuses.append(status)
                    }
                    continue
                }

                if let attemptID = response.attemptID.flatMap(UUID.init(uuidString:)),
                   response.state == .available || response.state == .prepared {
                    refreshedAttempts[product.id] = attemptID
                }

                if let status = IChartComplimentaryOfferPolicy.confirmedStatus(response: response) {
                    if !refreshedStatuses.contains(where: { $0.id == status.id }) {
                        refreshedStatuses.append(status)
                    }
                    if response.recoveryOnly == true,
                       let pending = pendingComplimentaryPurchase(),
                       IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(
                           response,
                           pending: pending,
                           accountID: initialAccountID,
                           productID: product.id
                       ) {
                        acknowledgedPendingPurchases.append(pending)
                    }
                    continue
                }

                if let offer = await resolvedComplimentaryOffer(response: response, product: product) {
                    refreshedOffers.append(offer)
                }
            }

            guard try await subscriptionClaimService.appAccountToken() == initialAccountID else {
                return
            }

            // Status can acknowledge an already verified scheduled purchase even
            // when StoreKit has no unfinished transaction. Clearing this local
            // marker is separate from, and never substitutes for, transaction.finish().
            for pending in acknowledgedPendingPurchases {
                guard pendingComplimentaryPurchase() == pending else {
                    continue
                }
                removePendingComplimentaryPurchase(attemptID: pending.attemptID)
            }

            complimentaryOffers = refreshedOffers.sorted { lhs, rhs in
                (productIDs.firstIndex(of: lhs.productID) ?? Int.max)
                    < (productIDs.firstIndex(of: rhs.productID) ?? Int.max)
            }
            complimentaryOfferStatuses = refreshedStatuses.sorted { $0.productID < $1.productID }
            complimentaryAttemptIDsByProduct = refreshedAttempts
        } catch {
            // Campaign failure is fail-closed and does not alter a paid
            // entitlement or expose an ordinary full-price fallback as free.
            complimentaryOffers = []
            complimentaryOfferStatuses = []
            complimentaryAttemptIDsByProduct = [:]
        }
    }

    private func resolvedComplimentaryOffer(
        response: IChartComplimentaryOfferServerResponse,
        product: Product
    ) async -> IChartComplimentaryOffer? {
        guard let subscription = product.subscription else {
            return nil
        }

        if response.decision == .scheduledPromotional {
            guard await hasActiveVerifiedEntitlement(for: product.id) else {
                return nil
            }
        }

        let storeKitOffer: Product.SubscriptionOffer
        let offerKind: IChartComplimentaryOfferProductMetadata.OfferKind
        let appleIntroEligible: Bool
        switch response.decision {
        case .introductory:
            guard let introductoryOffer = subscription.introductoryOffer else {
                return nil
            }
            storeKitOffer = introductoryOffer
            offerKind = .introductory
            appleIntroEligible = await subscription.isEligibleForIntroOffer
        case .promotional, .scheduledPromotional:
            guard let requestedID = response.offerID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !requestedID.isEmpty,
                  let promotionalOffer = subscription.promotionalOffers.first(where: { $0.id == requestedID }) else {
                return nil
            }
            storeKitOffer = promotionalOffer
            offerKind = .promotional
            appleIntroEligible = false
        case .ineligible:
            return nil
        }

        let metadata = IChartComplimentaryOfferProductMetadata(
            productID: product.id,
            productDisplayName: product.displayName,
            renewalDisplayPrice: product.displayPrice,
            renewalPeriod: complimentaryPeriod(subscription.subscriptionPeriod),
            offerID: storeKitOffer.id,
            offerKind: offerKind,
            offerPrice: storeKitOffer.price,
            offerDisplayPrice: storeKitOffer.displayPrice,
            offerPeriod: complimentaryPeriod(storeKitOffer.period),
            offerPeriodCount: storeKitOffer.periodCount,
            paymentMode: storeKitOffer.paymentMode == .freeTrial ? .freeTrial : .other
        )
        return IChartComplimentaryOfferPolicy.availableOffer(
            response: response,
            metadata: metadata,
            appleIntroEligible: appleIntroEligible
        )
    }

    private func complimentaryPeriod(
        _ period: Product.SubscriptionPeriod
    ) -> IChartComplimentaryOfferProductMetadata.Period {
        switch period.unit {
        case .day: return .days(period.value)
        case .week: return .weeks(period.value)
        case .month: return .months(period.value)
        case .year: return .years(period.value)
        @unknown default: return .other
        }
    }

    private func latestVerifiedSignedTransactionInfo(for productID: String) async -> String? {
        guard let result = await Transaction.latest(for: productID),
              case .verified = result else {
            return nil
        }
        return result.jwsRepresentation
    }

    private func hasActiveVerifiedEntitlement(for productID: String) async -> Bool {
        guard let result = await Transaction.currentEntitlement(for: productID),
              case .verified(let transaction) = result,
              transaction.revocationDate == nil else {
            return false
        }

        guard let expirationDate = transaction.expirationDate else {
            return true
        }
        return expirationDate > Date()
    }

    private func recordComplimentaryFailure(
        _ code: String,
        target: String,
        activation: IChartComplimentaryOfferActivation,
        startedAt: Date
    ) {
        IChartTelemetry.record(
            "subscription.purchase_failed",
            properties: [
                "target": .string(target),
                "flow": .string("complimentary"),
                "result": .string(activation.rawValue),
                "error_code": .string(code),
                "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000)
            ]
        )
    }

    private func recoverUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  IChartStoreKitProductCatalog.isProProductID(transaction.productID) else {
                continue
            }

            let resolution = await complimentaryTransactionResolution(
                verification: result,
                transaction: transaction
            )
            guard resolution != .retryLater else {
                continue
            }
            await transaction.finish()
            if resolution == .confirmedCampaign {
                removePendingComplimentaryPurchase(matching: transaction)
            }
        }
    }

    private func complimentaryTransactionResolution(
        verification: VerificationResult<Transaction>,
        transaction: Transaction
    ) async -> ComplimentaryTransactionResolution {
        let offerKind: IChartComplimentaryTransactionOfferKind?
        switch transaction.offerType {
        case .some(.introductory): offerKind = .introductory
        case .some(.promotional): offerKind = .promotional
        case .some: offerKind = .other
        case .none: offerKind = nil
        }
        guard IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: transaction.productID,
            appAccountToken: transaction.appAccountToken,
            offerKind: offerKind,
            offerID: transaction.offerID,
            pending: pendingComplimentaryPurchase()
        ) else {
            return .notCampaign
        }
        guard let subscriptionClaimService else {
            return .retryLater
        }

        do {
            guard let accountID = try await subscriptionClaimService.appAccountToken(),
                  transaction.appAccountToken == accountID else {
                return .retryLater
            }
            let signedTransactionInfo = verification.jwsRepresentation
            let status = try await subscriptionClaimService.complimentaryOffer(
                request: IChartComplimentaryOfferServerRequest(
                    action: .status,
                    productID: transaction.productID,
                    signedTransactionInfo: signedTransactionInfo
                )
            )
            guard status.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion,
                  status.productID == transaction.productID else {
                return .retryLater
            }
            guard try await subscriptionClaimService.appAccountToken() == accountID else {
                return .retryLater
            }

            if status.recoveryOnly == true {
                let pending = pendingComplimentaryPurchase()
                guard IChartComplimentaryTransactionPolicy.matchesPendingContext(
                    productID: transaction.productID,
                    appAccountToken: transaction.appAccountToken,
                    offerKind: offerKind,
                    offerID: transaction.offerID,
                    pending: pending
                ), IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(
                    status,
                    pending: pending,
                    accountID: accountID,
                    productID: transaction.productID
                ), try await subscriptionClaimService.appAccountToken() == accountID else {
                    return .retryLater
                }
                guard pendingComplimentaryPurchase() == pending else {
                    return .retryLater
                }
                return .confirmedCampaign
            }

            if IChartComplimentaryOfferPolicy.confirmedStatus(response: status) != nil {
                return .confirmedCampaign
            }

            if let attemptID = IChartComplimentaryOfferPolicy.recoverablePreparedAttempt(
                response: status,
                productID: transaction.productID
            ) {
                guard let claimedEntitlement = try await subscriptionClaimService.claim(
                    signedTransactionInfo: signedTransactionInfo,
                    expectedOwnerID: accountID
                ),
                      try await subscriptionClaimService.appAccountToken() == accountID else {
                    return .retryLater
                }
                entitlement = claimedEntitlement
                let confirmed = try await subscriptionClaimService.complimentaryOffer(
                    request: IChartComplimentaryOfferServerRequest(
                        action: .confirm,
                        productID: transaction.productID,
                        signedTransactionInfo: signedTransactionInfo,
                        attemptID: attemptID
                    )
                )
                guard IChartComplimentaryOfferPolicy.matchesRecoveredConfirmation(
                    confirmed,
                    prepared: status,
                    attemptID: attemptID
                ), try await subscriptionClaimService.appAccountToken() == accountID else {
                    return .retryLater
                }
                return .confirmedCampaign
            }

            return .retryLater
        } catch {
            return .retryLater
        }
    }

    private func pendingComplimentaryPurchase() -> IChartPendingComplimentaryPurchase? {
        guard let data = UserDefaults.standard.data(
            forKey: Self.pendingComplimentaryPurchaseKey
        ) else {
            return nil
        }
        return try? JSONDecoder().decode(IChartPendingComplimentaryPurchase.self, from: data)
    }

    private func savePendingComplimentaryPurchase(
        _ pending: IChartPendingComplimentaryPurchase
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(pending) else {
            return false
        }
        UserDefaults.standard.set(data, forKey: Self.pendingComplimentaryPurchaseKey)
        return true
    }

    private func removePendingComplimentaryPurchase(attemptID: UUID) {
        guard pendingComplimentaryPurchase()?.attemptID == attemptID else {
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingComplimentaryPurchaseKey)
    }

    private func removePendingComplimentaryPurchase(matching transaction: Transaction) {
        guard let pending = pendingComplimentaryPurchase() else {
            return
        }
        let kind: IChartComplimentaryTransactionOfferKind?
        switch transaction.offerType {
        case .some(.introductory): kind = .introductory
        case .some(.promotional): kind = .promotional
        case .some: kind = .other
        case .none: kind = nil
        }
        guard IChartComplimentaryTransactionPolicy.matchesPendingContext(
            productID: transaction.productID,
            appAccountToken: transaction.appAccountToken,
            offerKind: kind,
            offerID: transaction.offerID,
            pending: pending
        ) else {
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingComplimentaryPurchaseKey)
    }

    private func loadProducts() async {
        do {
            let fetchedProducts = try await Product.products(for: productIDs)
            products = fetchedProducts.sorted { lhs, rhs in
                (productIDs.firstIndex(of: lhs.id) ?? Int.max) < (productIDs.firstIndex(of: rhs.id) ?? Int.max)
            }
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            let recurringPrices = products.compactMap { product -> IChartStoreKitRecurringPrice? in
                guard product.type == .autoRenewable, let subscription = product.subscription else { return nil }
                let period = subscription.subscriptionPeriod
                let comparablePeriod: IChartStoreKitRecurringPrice.Period
                switch period.unit {
                case .month: comparablePeriod = .months(period.value)
                case .year: comparablePeriod = .years(period.value)
                default: comparablePeriod = .other
                }
                return IChartStoreKitRecurringPrice(productID: product.id, price: product.price,
                                                   currencyCode: product.priceFormatStyle.currencyCode,
                                                   period: comparablePeriod)
            }
            productOptions = products.map { product in
                IChartStoreKitProductOption(
                    id: product.id,
                    displayName: product.displayName,
                    description: product.description,
                    displayPrice: product.displayPrice,
                    valueBadge: IChartStoreKitProductCatalog.valueBadge(for: product.id, recurringPrices: recurringPrices)
                )
            }

            #if DEBUG && targetEnvironment(simulator)
            if productOptions.isEmpty {
                productOptions = localStoreKitProductOptions()
            }
            #endif
        } catch {
            products = []
            productsByID = [:]
            productOptions = localStoreKitProductOptionsAfterFailedLoad()
            state = .unavailable("Pro subscriptions could not be loaded.")
        }
    }

    private func localStoreKitProductOptionsAfterFailedLoad() -> [IChartStoreKitProductOption] {
        #if DEBUG && targetEnvironment(simulator)
        return localStoreKitProductOptions()
        #else
        return []
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private func localStoreKitProductOptions() -> [IChartStoreKitProductOption] {
        let options = IChartStoreKitProductCatalog.localPreviewProductOptions
            .filter { productIDs.contains($0.id) }

        return options.sorted { lhs, rhs in
            (productIDs.firstIndex(of: lhs.id) ?? Int.max) < (productIDs.firstIndex(of: rhs.id) ?? Int.max)
        }
    }
    #endif

    private func listenForTransactionUpdates() {
        guard transactionUpdatesTask == nil else {
            return
        }

        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else {
                    return
                }

                guard case .verified(let transaction) = result else {
                    self?.markTransactionVerificationUnavailable()
                    continue
                }

                if IChartStoreKitProductCatalog.isProProductID(transaction.productID) {
                    // The explicit campaign purchase path must confirm its
                    // attempt with the server before this transaction is
                    // finished. Its direct purchase result is authoritative.
                    guard self?.complimentaryPurchaseInFlight != true else {
                        continue
                    }
                    guard let self else { return }
                    let resolution = await self.complimentaryTransactionResolution(
                        verification: result,
                        transaction: transaction
                    )
                    guard resolution != .retryLater else {
                        self.state = .unavailable("A verified purchase is awaiting iChart confirmation. It will retry without charging again.")
                        continue
                    }
                    let signedTransactionInfo = result.jwsRepresentation
                    await transaction.finish()
                    if resolution == .confirmedCampaign {
                        self.removePendingComplimentaryPurchase(matching: transaction)
                    }
                    await self.refreshEntitlements(preferredSignedTransactionInfo: signedTransactionInfo)
                }
            }
        }
    }

    private func applyClaimFailureFallback(_ localEntitlement: IChartSubscriptionEntitlement) {
        #if DEBUG && targetEnvironment(simulator)
        entitlement = localEntitlement
        state = localEntitlement.status == .proActive
            ? .localPreviewActive
            : .unavailable("Subscription could not be verified. Try again when you are online.")
        #else
        entitlement = .unavailable
        state = .unavailable("Subscription could not be verified with iChart. Try again when you are online.")
        #endif
    }

    private func markTransactionVerificationUnavailable() {
        entitlement = .unavailable
        state = .unavailable("Subscription transaction could not be verified.")
    }

    private func removeLegacyDebugSignedTransactionCapture() {
        do {
            let supportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let debugURL = supportURL
                .appendingPathComponent("iChart", isDirectory: true)
                .appendingPathComponent("debug-last-storekit-transaction.jws")
            if FileManager.default.fileExists(atPath: debugURL.path) {
                try FileManager.default.removeItem(at: debugURL)
            }
        } catch {
            // Best-effort cleanup for a sandbox diagnostic artifact from local QA.
        }
    }

    private func storeKitPurchaseOptions() async throws -> Set<Product.PurchaseOption> {
        guard let subscriptionClaimService,
              let appAccountToken = try await subscriptionClaimService.appAccountToken() else {
            throw ComplimentaryPurchaseError.missingAccount
        }

        return [.appAccountToken(appAccountToken)]
    }
}

private enum ComplimentaryPurchaseError: Error {
    case missingAccount
    case accountChanged
    case productUnavailable
    case offerChanged
    case authorizationRejected
    case pendingContextUnavailable
    case unverifiedTransaction
    case claimRejected
    case confirmationRejected

    var telemetryCode: String {
        switch self {
        case .missingAccount: return "missing_account"
        case .accountChanged: return "account_changed"
        case .productUnavailable: return "product_unavailable"
        case .offerChanged: return "offer_changed"
        case .authorizationRejected: return "authorization_rejected"
        case .pendingContextUnavailable: return "pending_context_unavailable"
        case .unverifiedTransaction: return "unverified_transaction"
        case .claimRejected: return "claim_rejected"
        case .confirmationRejected: return "confirmation_rejected"
        }
    }

    var userMessage: String {
        switch self {
        case .missingAccount:
            return "Sign in to verify the complimentary offer. No paid purchase was made."
        case .accountChanged:
            return "The signed-in account changed. The offer was not completed."
        case .productUnavailable:
            return "Apple's complimentary offer details are unavailable. No paid purchase was made."
        case .offerChanged:
            return "The complimentary offer changed. Refresh and review the current Apple terms."
        case .authorizationRejected:
            return "The complimentary offer could not be authorized. No paid purchase was made."
        case .pendingContextUnavailable:
            return "The complimentary offer could not be prepared safely. No paid purchase was made."
        case .unverifiedTransaction:
            return "Apple returned an unverified transaction. The offer was not completed."
        case .claimRejected:
            return "The verified Apple purchase could not be linked to this iChart account yet. It will retry without charging again."
        case .confirmationRejected:
            return "The complimentary offer could not be confirmed with iChart. Try again later."
        }
    }
}

private struct StoreKitEntitlementEvaluation {
    let entitlement: IChartSubscriptionEntitlement
    let signedTransactionInfo: String?
    let state: IChartStoreKitSubscriptionState
}

private enum ComplimentaryTransactionResolution: Equatable {
    case notCampaign
    case confirmedCampaign
    case retryLater
}

private protocol IChartStoreKitSubscriptionClaiming: IChartSubscriptionAccessClaiming {
    func complimentaryOffer(
        request: IChartComplimentaryOfferServerRequest
    ) async throws -> IChartComplimentaryOfferServerResponse
}

private struct IChartSupabaseStoreKitSubscriptionClaimService: IChartStoreKitSubscriptionClaiming {
    let authClient: SupabaseClient
    let dataClient: SupabaseClient
    let sessionStore: IChartSupabaseSessionStore

    func appAccountToken() async throws -> UUID? {
        try await refreshedSession().user.id
    }

    func claim(
        signedTransactionInfo: String,
        expectedOwnerID: UUID
    ) async throws -> IChartSubscriptionEntitlement? {
        let session = try await refreshedSession()
        guard session.user.id == expectedOwnerID else {
            throw IChartSubscriptionAccessRecovery.ValidationError.accountChanged
        }
        let ownerClient = try authenticatedDataClient(for: session)
        let response: StoreKitSubscriptionClaimResponse = try await ownerClient.functions.invoke(
            "storekit-subscription-claims",
            options: FunctionInvokeOptions(
                method: .post,
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: StoreKitSubscriptionClaimRequest(signedTransactionInfo: signedTransactionInfo)
            )
        )

        return try IChartSubscriptionAccessRecovery.validatedEntitlement(
            record: response.subscription,
            expectedOwnerID: expectedOwnerID,
            authenticatedRequestOwnerID: session.user.id,
            currentOwnerID: try await authClient.auth.session.user.id,
            accepted: response.accepted,
            now: Date()
        )
    }

    func loadRemoteSubscriptionEntitlement(
        now: Date,
        expectedOwnerID: UUID
    ) async throws -> IChartSubscriptionEntitlement? {
        let session = try await refreshedSession()
        guard session.user.id == expectedOwnerID else {
            throw IChartSubscriptionAccessRecovery.ValidationError.accountChanged
        }
        let ownerClient = try authenticatedDataClient(for: session)
        let rows: [IChartRemoteSubscriptionRecord] = try await ownerClient
            .from("subscriptions")
            .select()
            .eq("owner_id", value: expectedOwnerID.uuidString)
            .limit(1)
            .execute()
            .value

        return try IChartSubscriptionAccessRecovery.validatedEntitlement(
            record: rows.first,
            expectedOwnerID: expectedOwnerID,
            authenticatedRequestOwnerID: session.user.id,
            currentOwnerID: try await authClient.auth.session.user.id,
            now: now
        )
    }

    private func authenticatedDataClient(for session: Session) throws -> SupabaseClient {
        guard let configuration = IChartSupabaseConfiguration.current() else {
            throw IChartSubscriptionAccessRecovery.ValidationError.configurationUnavailable
        }
        // The shared client's token provider can change during an await. This
        // request-local client pins the genuine session without storing credentials
        // or changing the app's auth client / campaign transport.
        let pinnedAccessToken = session.accessToken
        return SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(auth: .init(
                storage: IChartSubscriptionRequestLocalStorage(),
                autoRefreshToken: false,
                accessToken: { pinnedAccessToken }
            ))
        )
    }

    func complimentaryOffer(
        request: IChartComplimentaryOfferServerRequest
    ) async throws -> IChartComplimentaryOfferServerResponse {
        let session = try await refreshedSession()
        #if DEBUG
        if request.action == .status,
           IChartComplimentaryOfferQADiagnostics.currentConfiguration() != nil {
            // Observe the existing request using its actual bearer-session
            // owner, not an owner sampled around the entire refresh loop.
            do {
                let response: IChartComplimentaryOfferServerResponse = try await invokeComplimentaryOffer(
                    request, session: session
                )
                let finalAccountID = try? await authClient.auth.session.user.id
                IChartComplimentaryOfferQADiagnostics.record(
                    responses: [IChartComplimentaryOfferQADiagnostics.sanitizedResponse(
                        response, requestedProductID: request.productID
                    )],
                    initialAccountID: session.user.id,
                    finalAccountID: finalAccountID
                )
                IChartComplimentaryOfferQADiagnostics.recordPendingChecks(
                    response, requestedProductID: request.productID,
                    initialAccountID: session.user.id, finalAccountID: finalAccountID
                )
                return response
            } catch {
                let finalAccountID = try? await authClient.auth.session.user.id
                IChartComplimentaryOfferQADiagnostics.record(
                    responses: [IChartComplimentaryOfferQADiagnostics.sanitizedRequestError(
                        error, requestedProductID: request.productID
                    )],
                    initialAccountID: session.user.id,
                    finalAccountID: finalAccountID
                )
                throw error
            }
        }
        #endif
        return try await invokeComplimentaryOffer(request, session: session)
    }

    private func invokeComplimentaryOffer(
        _ request: IChartComplimentaryOfferServerRequest,
        session: Session
    ) async throws -> IChartComplimentaryOfferServerResponse {
        let ownerClient = try authenticatedDataClient(for: session)
        let response: IChartComplimentaryOfferServerResponse = try await ownerClient.functions.invoke(
            "storekit-complimentary-offers",
            options: FunctionInvokeOptions(
                method: .post,
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: request
            )
        )
        guard try await authClient.auth.session.user.id == session.user.id else {
            throw IChartSubscriptionAccessRecovery.ValidationError.accountChanged
        }
        return response
    }

    private func refreshedSession() async throws -> Session {
        let session = try await authClient.auth.session
        await sessionStore.update(session)
        return session
    }
}

private struct IChartSubscriptionRequestLocalStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}

private struct StoreKitSubscriptionClaimRequest: Encodable {
    let signedTransactionInfo: String
}

private struct StoreKitSubscriptionClaimResponse: Decodable {
    let accepted: Bool
    let appStoreStatus: String?
    let stored: Bool?
    let mappingStatus: String?
    let subscription: IChartRemoteSubscriptionRecord?

    private enum CodingKeys: String, CodingKey {
        case accepted
        case appStoreStatus = "app_store_status"
        case stored
        case mappingStatus = "mapping_status"
        case subscription
    }
}

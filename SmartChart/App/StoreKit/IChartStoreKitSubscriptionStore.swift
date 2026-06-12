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

    var statusText: String {
        switch self {
        case .idle:
            return "Subscription check ready."
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
        case .ready:
            return "Subscription check complete."
        case .localPreviewActive:
            return "Local Pro preview active for simulator QA."
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
final class IChartStoreKitSubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var productOptions: [IChartStoreKitProductOption] = []
    @Published private(set) var entitlement: IChartSubscriptionEntitlement
    @Published private(set) var state: IChartStoreKitSubscriptionState = .idle

    private let productIDs: [String]
    private let subscriptionClaimService: IChartStoreKitSubscriptionClaiming?
    private var productsByID: [String: Product] = [:]
    private var transactionUpdatesTask: Task<Void, Never>?

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
        let claimService = clients.map { IChartSupabaseStoreKitSubscriptionClaimService(client: $0.dataClient) }
        return IChartStoreKitSubscriptionStore(subscriptionClaimService: claimService)
    }

    func bootstrap() async {
        guard !productIDs.isEmpty else {
            entitlement = .unavailable
            state = .unavailable("StoreKit products are not configured.")
            return
        }

        listenForTransactionUpdates()
        await loadProducts()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        await refreshEntitlements(preferredSignedTransactionInfo: nil)
    }

    private func refreshEntitlements(preferredSignedTransactionInfo: String?) async {
        state = .loading
        let localEvaluation = await evaluateLocalStoreKitEntitlements(
            preferredSignedTransactionInfo: preferredSignedTransactionInfo
        )

        if let subscriptionClaimService {
            if let signedTransactionInfo = localEvaluation.signedTransactionInfo {
                state = .claiming

                do {
                    if let claimedEntitlement = try await subscriptionClaimService.claim(
                        signedTransactionInfo: signedTransactionInfo
                    ) {
                        entitlement = claimedEntitlement
                        state = .ready
                        return
                    }
                } catch {
                    applyClaimFailureFallback(localEvaluation.entitlement)
                    return
                }
            }

            do {
                if let remoteEntitlement = try await subscriptionClaimService.loadRemoteSubscriptionEntitlement(
                    now: Date()
                ) {
                    entitlement = remoteEntitlement
                    state = .ready
                    return
                }
            } catch {
                if localEvaluation.entitlement.status != .proActive {
                    entitlement = localEvaluation.entitlement
                    state = .ready
                    return
                }

                applyClaimFailureFallback(localEvaluation.entitlement)
                return
            }
        }

        entitlement = localEvaluation.entitlement
        state = localEvaluation.state
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

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    entitlement = .unavailable
                    state = .unavailable("Purchase could not be verified.")
                    return
                }

                let signedTransactionInfo = verification.jwsRepresentation
                await transaction.finish()
                await refreshEntitlements(preferredSignedTransactionInfo: signedTransactionInfo)
            case .pending:
                state = .unavailable("Purchase is pending approval.")
            case .userCancelled:
                state = .ready
            @unknown default:
                entitlement = .unavailable
                state = .unavailable("Purchase status is unavailable.")
            }
        } catch {
            entitlement = .unavailable
            state = .unavailable("Purchase failed. Try again from Settings.")
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
        state = .unavailable("StoreKit products could not be loaded.")
        #endif
    }

    func restorePurchases() async {
        state = .restoring

        do {
            try await AppStore.sync()
            await refreshEntitlements(preferredSignedTransactionInfo: nil)
        } catch {
            entitlement = .unavailable
            state = .unavailable("Restore failed. Try again when you are online.")
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

    #if DEBUG || targetEnvironment(simulator)
    func applyLocalPreview(_ entitlement: IChartSubscriptionEntitlement) {
        self.entitlement = entitlement
        state = entitlement.status == .proActive ? .localPreviewActive : .ready
    }
    #endif

    private func loadProducts() async {
        do {
            let fetchedProducts = try await Product.products(for: productIDs)
            products = fetchedProducts.sorted { lhs, rhs in
                (productIDs.firstIndex(of: lhs.id) ?? Int.max) < (productIDs.firstIndex(of: rhs.id) ?? Int.max)
            }
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            productOptions = products.map { product in
                IChartStoreKitProductOption(
                    id: product.id,
                    displayName: product.displayName,
                    description: product.description,
                    displayPrice: product.displayPrice,
                    valueBadge: IChartStoreKitProductCatalog.valueBadge(for: product.id)
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
            state = .unavailable("StoreKit products could not be loaded.")
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
        guard let configurationURL = Bundle.main.url(
            forResource: IChartStoreKitProductCatalog.localStoreKitConfigurationFileName,
            withExtension: nil
        ),
              let data = try? Data(contentsOf: configurationURL),
              let configuration = try? JSONDecoder().decode(LocalStoreKitConfiguration.self, from: data) else {
            return []
        }

        let options = configuration.subscriptionGroups
            .flatMap(\.subscriptions)
            .filter { productIDs.contains($0.productID) }
            .map { subscription in
                IChartStoreKitProductOption(
                    id: subscription.productID,
                    displayName: subscription.localizedDisplayName,
                    description: subscription.localizedDescription,
                    displayPrice: subscription.localizedDisplayPrice,
                    valueBadge: IChartStoreKitProductCatalog.valueBadge(for: subscription.productID)
                )
            }

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
                    let signedTransactionInfo = result.jwsRepresentation
                    await transaction.finish()
                    await self?.refreshEntitlements(preferredSignedTransactionInfo: signedTransactionInfo)
                }
            }
        }
    }

    private func applyClaimFailureFallback(_ localEntitlement: IChartSubscriptionEntitlement) {
        #if DEBUG && targetEnvironment(simulator)
        entitlement = localEntitlement
        state = localEntitlement.status == .proActive
            ? .localPreviewActive
            : .unavailable("Subscription server verification is unavailable. Using local simulator entitlement.")
        #else
        entitlement = .unavailable
        state = .unavailable("Subscription could not be verified with iChart. Try again when you are online.")
        #endif
    }

    private func markTransactionVerificationUnavailable() {
        entitlement = .unavailable
        state = .unavailable("Subscription transaction could not be verified.")
    }
}

private struct StoreKitEntitlementEvaluation {
    let entitlement: IChartSubscriptionEntitlement
    let signedTransactionInfo: String?
    let state: IChartStoreKitSubscriptionState
}

private protocol IChartStoreKitSubscriptionClaiming: Sendable {
    func claim(signedTransactionInfo: String) async throws -> IChartSubscriptionEntitlement?
    func loadRemoteSubscriptionEntitlement(now: Date) async throws -> IChartSubscriptionEntitlement?
}

private struct IChartSupabaseStoreKitSubscriptionClaimService: IChartStoreKitSubscriptionClaiming {
    let client: SupabaseClient

    func claim(signedTransactionInfo: String) async throws -> IChartSubscriptionEntitlement? {
        let response: StoreKitSubscriptionClaimResponse = try await client.functions.invoke(
            "storekit-subscription-claims",
            options: FunctionInvokeOptions(
                method: .post,
                body: StoreKitSubscriptionClaimRequest(signedTransactionInfo: signedTransactionInfo)
            )
        )

        return response.subscription?.entitlement()
    }

    func loadRemoteSubscriptionEntitlement(now: Date) async throws -> IChartSubscriptionEntitlement? {
        let rows: [IChartRemoteSubscriptionRecord] = try await client
            .from("subscriptions")
            .select()
            .limit(1)
            .execute()
            .value

        return rows.first?.entitlement(now: now)
    }
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

#if DEBUG && targetEnvironment(simulator)
private struct LocalStoreKitConfiguration: Decodable {
    struct SubscriptionGroup: Decodable {
        let subscriptions: [Subscription]
    }

    struct Subscription: Decodable {
        struct Localization: Decodable {
            let description: String
            let displayName: String
        }

        let productID: String
        let displayPrice: String
        let localizations: [Localization]
        let referenceName: String

        var localizedDisplayName: String {
            localizations.first?.displayName ?? referenceName
        }

        var localizedDescription: String {
            localizations.first?.description ?? ""
        }

        var localizedDisplayPrice: String {
            displayPrice.hasPrefix("$") ? displayPrice : "$\(displayPrice)"
        }
    }

    let subscriptionGroups: [SubscriptionGroup]
}
#endif

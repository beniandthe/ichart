import Foundation
import StoreKit

enum IChartStoreKitSubscriptionState: Equatable {
    case idle
    case loading
    case purchasing
    case restoring
    case ready
    case localPreviewActive
    case unavailable(String)

    var isWorking: Bool {
        switch self {
        case .loading, .purchasing, .restoring:
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
        case .purchasing:
            return "Opening purchase..."
        case .restoring:
            return "Restoring purchases..."
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
    private var productsByID: [String: Product] = [:]
    private var transactionUpdatesTask: Task<Void, Never>?

    init(
        productIDs: [String] = IChartStoreKitProductCatalog.proProductIDs,
        entitlement: IChartSubscriptionEntitlement = .basic
    ) {
        self.productIDs = productIDs
        self.entitlement = entitlement
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    static func live() -> IChartStoreKitSubscriptionStore {
        IChartStoreKitSubscriptionStore()
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
        state = .loading

        var activeProExpiration: Date?
        var sawExpiredProTransaction = false

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
                } else {
                    sawExpiredProTransaction = true
                }
            } else {
                activeProExpiration = .distantFuture
            }
        }

        entitlement = IChartStoreKitEntitlementResolver.entitlement(
            hasActiveProSubscription: activeProExpiration != nil,
            sawExpiredProTransaction: sawExpiredProTransaction,
            verifiedAt: Date()
        )

        state = .ready
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

                await transaction.finish()
                await refreshEntitlements()
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
            await refreshEntitlements()
        } catch {
            entitlement = .unavailable
            state = .unavailable("Restore failed. Try again when you are online.")
        }
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
                    displayPrice: product.displayPrice
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
                    displayPrice: subscription.localizedDisplayPrice
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
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    private func markTransactionVerificationUnavailable() {
        entitlement = .unavailable
        state = .unavailable("Subscription transaction could not be verified.")
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

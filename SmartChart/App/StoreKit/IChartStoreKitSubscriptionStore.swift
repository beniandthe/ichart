import Foundation
import StoreKit

enum IChartStoreKitSubscriptionState: Equatable {
    case idle
    case loading
    case purchasing
    case restoring
    case ready
    case unavailable(String)

    var isWorking: Bool {
        switch self {
        case .loading, .purchasing, .restoring:
            return true
        case .idle, .ready, .unavailable:
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
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
final class IChartStoreKitSubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var entitlement: IChartSubscriptionEntitlement
    @Published private(set) var state: IChartStoreKitSubscriptionState = .idle

    private let productIDs: [String]
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

    private func loadProducts() async {
        do {
            let fetchedProducts = try await Product.products(for: productIDs)
            products = fetchedProducts.sorted { lhs, rhs in
                (productIDs.firstIndex(of: lhs.id) ?? Int.max) < (productIDs.firstIndex(of: rhs.id) ?? Int.max)
            }
        } catch {
            products = []
            state = .unavailable("StoreKit products could not be loaded.")
        }
    }

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

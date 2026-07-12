import Foundation

struct IChartRemoteSubscriptionRecord: Decodable, Equatable {
    enum Provider: String, Decodable {
        case none
        case storekit
        case stripe
        case manual
    }

    enum AppStoreStatus: String, Decodable {
        case active
        case grace
        case billingRetry = "billing_retry"
        case expired
        case revoked
        case refunded
    }

    let ownerID: UUID
    let plan: IChartPlan
    let status: String
    let provider: Provider
    let storeKitProductID: String?
    let storeKitOriginalTransactionID: String?
    let storeKitEnvironment: String?
    let appStoreStatus: AppStoreStatus?
    let appStoreAutoRenewStatus: Bool?
    let entitlementExpiresAt: String?
    let gracePeriodExpiresAt: String?
    let cloudRetentionDeadline: String?
    let cloudRetentionDeletedAt: String?
    let revokedAt: String?
    let lastVerifiedAt: String?

    func entitlement(now: Date = Date()) -> IChartSubscriptionEntitlement {
        let verifiedAt = Self.date(from: lastVerifiedAt)

        if provider == .storekit {
            guard let storeKitProductID,
                  IChartStoreKitProductCatalog.isProProductID(storeKitProductID) else {
                return .basic
            }

            if Self.date(from: revokedAt) != nil {
                return .proExpired(verifiedAt: verifiedAt)
            }

            switch appStoreStatus {
            case .active:
                if let expiresAt = Self.date(from: entitlementExpiresAt),
                   expiresAt <= now {
                    return .proExpired(verifiedAt: verifiedAt)
                }

                return .activePro(
                    accessEndsAt: Self.date(from: entitlementExpiresAt),
                    willAutoRenew: appStoreAutoRenewStatus,
                    verifiedAt: verifiedAt
                )
            case .grace, .billingRetry:
                if let graceEndsAt = Self.date(from: gracePeriodExpiresAt),
                   graceEndsAt > now {
                    return .proGrace(graceEndsAt: graceEndsAt, verifiedAt: verifiedAt)
                }

                return .proExpired(verifiedAt: verifiedAt)
            case .expired, .revoked, .refunded:
                return .proExpired(verifiedAt: verifiedAt)
            case nil:
                break
            }
        }

        if plan == .studioSubscription && status == "active" {
            return .activePro(verifiedAt: verifiedAt)
        }

        if plan == .studioSubscription || status == "expired" {
            return .proExpired(verifiedAt: verifiedAt)
        }

        return .basic
    }

    private enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case plan
        case status
        case provider
        case storeKitProductID = "storekit_product_id"
        case storeKitOriginalTransactionID = "storekit_original_transaction_id"
        case storeKitEnvironment = "storekit_environment"
        case appStoreStatus = "app_store_status"
        case appStoreAutoRenewStatus = "app_store_auto_renew_status"
        case entitlementExpiresAt = "entitlement_expires_at"
        case gracePeriodExpiresAt = "grace_period_expires_at"
        case cloudRetentionDeadline = "cloud_retention_deadline"
        case cloudRetentionDeletedAt = "cloud_retention_deleted_at"
        case revokedAt = "revoked_at"
        case lastVerifiedAt = "last_verified_at"
    }

    private static func date(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        return fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

import Foundation

/// Product access is independent of verified Apple billing history.
///
/// The current release includes all shipped features without a purchase,
/// trial, expiry, or automatic conversion to a paid subscription. Account
/// authentication and server-side ownership checks still apply to services.
/// This immutable shipping choice is not read from preferences, account
/// receipts, or saved library files. The paid policy is retained explicitly
/// for contract tests and a separately reviewed future product change.
enum IChartProductAccessPolicy: Hashable {
    case freeAllFeatures
    case paidSubscription

    static let current: Self = .freeAllFeatures

    var includesAllFeatures: Bool { self == .freeAllFeatures }
    var offersPaidPurchases: Bool { self == .paidSubscription }
}

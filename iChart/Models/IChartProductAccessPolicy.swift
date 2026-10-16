import Foundation

/// Product access is independent of verified Apple billing history.
///
/// The current release includes all shipped features without a purchase,
/// trial, expiry, or automatic conversion to a paid subscription. Account
/// authentication and server-side ownership checks still apply to services.
/// The shipping phase is not read from billing receipts or saved library
/// files. During Beta an account may voluntarily use Basic without changing
/// its Apple billing history, and may rejoin free Pro. The paid policy remains
/// explicit for contract tests and a separately reviewed future product change.
enum IChartProductAccessPolicy: Hashable {
    case freeAllFeatures
    case betaBasic
    case paidSubscription

    static let current: Self = .freeAllFeatures

    var includesAllFeatures: Bool { self == .freeAllFeatures }
    var isFreeBeta: Bool { self != .paidSubscription }
    var offersPaidPurchases: Bool { self == .paidSubscription }
}

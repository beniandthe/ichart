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

    #if ICHART_PAID_SUBSCRIPTION
    static let current: Self = .paidSubscription
    #else
    static let current: Self = .freeAllFeatures
    #endif

    /// This build can follow the reviewed server phase; fixed free and QA lanes
    /// keep their existing semantics and never become paid through an RPC.
    #if ICHART_PAID_SUBSCRIPTION && !ICHART_STAGING_STOREKIT_PRODUCTS && !ICHART_LOCAL_PLAN_QA && !ICHART_LOCAL_QA_PLAN_PREVIEW
    static let usesCoordinatedActivation = true
    #else
    static let usesCoordinatedActivation = false
    #endif

    var includesAllFeatures: Bool { self == .freeAllFeatures }
    var isFreeBeta: Bool { self != .paidSubscription }
    var offersPaidPurchases: Bool { self == .paidSubscription }
}

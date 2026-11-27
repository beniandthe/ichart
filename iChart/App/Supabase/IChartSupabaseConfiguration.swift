import Foundation

struct IChartSupabaseConfiguration: Equatable {
    static let urlInfoKey = "SupabaseURL"
    static let publishableKeyInfoKey = "SupabasePublishableKey"
    static let legacyAnonKeyInfoKey = "SupabaseAnonKey"
    static let urlEnvironmentKey = "SUPABASE_URL"
    static let publishableKeyEnvironmentKey = "SUPABASE_PUBLISHABLE_KEY"
    static let legacyAnonKeyEnvironmentKey = "SUPABASE_ANON_KEY"

    let url: URL
    let publishableKey: String

    static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> IChartSupabaseConfiguration? {
        #if ICHART_PAID_SUBSCRIPTION && !ICHART_STAGING_STOREKIT_PRODUCTS
        // A production paid package is pinned to its reviewed bundle inputs.
        // Launch-time QA overrides must never redirect purchases or account data.
        let configuredURL = configuredValue(bundle.object(forInfoDictionaryKey: urlInfoKey) as? String)
        let configuredKey = configuredValue(bundle.object(forInfoDictionaryKey: publishableKeyInfoKey) as? String)
        #else
        let configuredURL = configuredValue(
            environment[urlEnvironmentKey],
            bundle.object(forInfoDictionaryKey: urlInfoKey) as? String
        )
        let configuredKey = configuredValue(
            environment[publishableKeyEnvironmentKey],
            environment[legacyAnonKeyEnvironmentKey],
            bundle.object(forInfoDictionaryKey: publishableKeyInfoKey) as? String,
            bundle.object(forInfoDictionaryKey: legacyAnonKeyInfoKey) as? String
        )
        #endif
        guard let urlString = configuredURL,
              let url = URL(string: urlString),
              let key = configuredKey else {
            return nil
        }

        #if ICHART_PAID_SUBSCRIPTION && !ICHART_STAGING_STOREKIT_PRODUCTS
        guard url.absoluteString == "https://pausvvwoazbvmzyrebwl.supabase.co",
              key.range(of: #"^sb_publishable_[A-Za-z0-9_-]{16,}$"#, options: .regularExpression) != nil else {
            return nil
        }
        #elseif ICHART_STAGING_STOREKIT_PRODUCTS
        // An internal build must never attach its isolated QA data to the
        // public backend, including through launch-time environment overrides.
        guard url.absoluteString == "https://gfqpbikqvdgtjjgxrkgo.supabase.co",
              key.range(of: #"^sb_publishable_[A-Za-z0-9_-]{16,}$"#, options: .regularExpression) != nil else {
            return nil
        }
        #endif

        return IChartSupabaseConfiguration(url: url, publishableKey: key)
    }

    private static func configuredValue(_ candidates: String?...) -> String? {
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("$("),
                  !trimmed.hasPrefix("your-"),
                  !trimmed.hasPrefix("replace-")
            else {
                continue
            }

            return trimmed
        }

        return nil
    }
}

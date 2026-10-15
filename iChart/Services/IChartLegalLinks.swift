import Foundation

enum IChartLegalLinks {
    static let privacyURL = URL(string: "https://useichart.com/privacy.html")!
    static let termsURL = URL(string: "https://useichart.com/terms.html")!
    static let subscriptionNotice = "Subscriptions renew automatically unless cancelled. Manage or cancel your subscription through your Apple account."
    static let freeProTitle = "Pro — Free During Beta"
    static let freeProNotice = "Your account starts with Pro, free while iChart is in beta. Leave or rejoin Pro at any time in Settings. No subscription or payment is required during beta."
    static let betaBasicTitle = "Basic"
    static let betaBasicNotice = "You're using Basic. Pro is free during beta, and you can rejoin at any time. Your existing charts and downloads are kept."
    static let futurePricingNotice = "We'll give you advance notice in the app before beta ends and Pro moves to paid subscriptions. You can choose Basic at any time. Free access will not automatically become a charge: you must choose and confirm a new paid subscription with Apple."
    static let existingBillingNotice = "Changing Pro access here does not cancel an existing Apple subscription or issue a refund. Use Manage My Subscription to manage or cancel Apple billing."
    static let diagnosticsNotice = "Optional. Share app usage, reliability counts, timings, and error categories with iChart, along with app/device details and random installation/session identifiers. When signed in, reports can be linked to your iChart account identifier. No chart text, chords, handwriting, PDFs, or screenshots are included."
    static let diagnosticsWithdrawalNotice = "Turn this off at any time to stop collection and sending, and clear unsent diagnostics from this iPad. A request already sent may finish. This does not delete reports already received; contact support@useichart.com for deletion requests. Your app features and subscription are unaffected."
}

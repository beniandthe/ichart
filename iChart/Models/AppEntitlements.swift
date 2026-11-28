import Foundation

enum IChartPlan: String, Codable, CaseIterable, Hashable {
    case free
    case proLifetime
    case studioSubscription

    var displayText: String {
        switch self {
        case .free:
            return "Basic"
        case .proLifetime:
            return "Pro"
        case .studioSubscription:
            return "Pro"
        }
    }

}

enum EntitledFeature: String, Codable, CaseIterable, Hashable {
    case unlimitedLocalCharts
    case pdfExport
    case documentTransposition
    case fontPresets
    case roadmapNotationTools
    case advancedRhythmEditing
    case syncedChartOrganization
    case cloudBackup
    case forums
    case sharedBandLibraries
    case setlistsAndVersionHistory
    case aiRecognitionCleanup
    case projects

    var displayText: String {
        switch self {
        case .unlimitedLocalCharts:
            return "Unlimited Local Charts"
        case .pdfExport:
            return "PDF Export"
        case .documentTransposition:
            return "Instrument Transposition"
        case .fontPresets:
            return "Font Presets"
        case .roadmapNotationTools:
            return "Repeats And Coda"
        case .advancedRhythmEditing:
            return "Rhythm Editing"
        case .syncedChartOrganization:
            return "Cloud Backup And Restore"
        case .cloudBackup:
            return "Cloud Backup"
        case .forums:
            return "Forums"
        case .sharedBandLibraries:
            return "Community Chart Library"
        case .setlistsAndVersionHistory:
            return "Project Organization"
        case .aiRecognitionCleanup:
            return "Handwriting Recognition"
        case .projects:
            return "Projects"
        }
    }

    var upgradeMessage: String {
        switch self {
        case .pdfExport:
            return "PDF export is included in Basic because exporting charts is core to the local writing workflow."
        case .documentTransposition:
            return "Instrument transposition is included in Basic because readable gig charts are core to iChart."
        case .fontPresets:
            return "Pro adds Petaluma, MuseJazz, and Finale Jazz. You can keep using any font already saved in a chart."
        case .roadmapNotationTools:
            return "Repeats and Coda are included in Basic because chart navigation is essential chart work."
        case .advancedRhythmEditing:
            return "Rhythm-aware editing is included in Basic because rhythm charts are a core iChart format."
        case .unlimitedLocalCharts:
            return "Unlimited local chart capacity is part of the Pro account experience."
        case .projects:
            return "Pro lets you organize Projects and duplicate variants. You can still open, edit, and export charts in your saved Projects."
        case .forums:
            return "A verified account can browse and read Forums. Pro adds new PDF downloads, posts, votes, and comments."
        case .syncedChartOrganization,
             .cloudBackup,
             .sharedBandLibraries,
             .setlistsAndVersionHistory,
             .aiRecognitionCleanup:
            return "This is reserved for active Pro because it depends on account, cloud backup, or Forums service."
        }
    }
}

extension EntitledFeature: Identifiable {
    var id: String { rawValue }
}

struct AppEntitlements: Codable, Hashable {
    static let recommendedBasicChartLimit = 3
    static let recommendedFreeChartLimit = recommendedBasicChartLimit
    static let free = AppEntitlements(activePlan: .free)

    // Persist the last applied billing projection. Runtime admission below
    // evaluates known paid-through bounds again instead of trusting this cache.
    private(set) var activePlan: IChartPlan
    private(set) var subscription: IChartSubscriptionEntitlement
    // Runtime product policy, deliberately excluded from persisted billing data.
    let accessPolicy: IChartProductAccessPolicy

    init(
        activePlan: IChartPlan,
        subscription: IChartSubscriptionEntitlement? = nil,
        accessPolicy: IChartProductAccessPolicy = .current
    ) {
        let resolvedSubscription = subscription ?? IChartSubscriptionEntitlement.legacyStatus(for: activePlan)
        self.activePlan = resolvedSubscription.effectivePlan
        self.subscription = resolvedSubscription
        self.accessPolicy = accessPolicy
    }

    init(
        subscription: IChartSubscriptionEntitlement,
        accessPolicy: IChartProductAccessPolicy = .current
    ) {
        self.activePlan = subscription.effectivePlan
        self.subscription = subscription
        self.accessPolicy = accessPolicy
    }

    mutating func applySubscription(_ subscription: IChartSubscriptionEntitlement) {
        self.subscription = subscription
        activePlan = subscription.effectivePlan
    }

    mutating func applyLegacyPlan(_ plan: IChartPlan) {
        applySubscription(IChartSubscriptionEntitlement.legacyStatus(for: plan))
    }

    /// A clock-explicit projection for presentation or publication. Reading
    /// access decisions does not rewrite the saved billing evidence.
    func evaluated(at now: Date) -> AppEntitlements {
        AppEntitlements(subscription: subscription.evaluated(at: now), accessPolicy: accessPolicy)
    }

    var localChartLimit: Int? {
        localChartLimit(at: Date())
    }

    func localChartLimit(at now: Date) -> Int? {
        guard !accessPolicy.includesAllFeatures else { return nil }
        if accessPolicy == .betaBasic {
            return Self.recommendedBasicChartLimit
        }

        let currentSubscription = subscription.evaluated(at: now)
        switch currentSubscription.status {
        case .proActive, .proGrace, .legacyLocalPro:
            return nil
        case .basic, .proExpired, .unavailable:
            break
        }

        switch currentSubscription.effectivePlan {
        case .free:
            return Self.recommendedFreeChartLimit
        case .proLifetime, .studioSubscription:
            return nil
        }
    }

    var canConvertPDFToEditableChart: Bool { canConvertPDFToEditableChart(at: Date()) }

    func canConvertPDFToEditableChart(at now: Date) -> Bool { includesPremiumLocalTools(at: now) }

    var canUsePremiumFonts: Bool { canUsePremiumFonts(at: Date()) }

    func canUsePremiumFonts(at now: Date) -> Bool { includesPremiumLocalTools(at: now) }

    var canSyncPDFSetlists: Bool {
        canSyncPDFSetlists(at: Date())
    }

    func canSyncPDFSetlists(at now: Date) -> Bool {
        accessPolicy == .paidSubscription && subscription.evaluated(at: now).status == .proActive
    }

    private func includesPremiumLocalTools(at now: Date) -> Bool {
        let status = subscription.evaluated(at: now).status
        return accessPolicy.includesAllFeatures
            || (accessPolicy == .paidSubscription
                && (status == .proActive || status == .proGrace))
    }

    func includes(_ feature: EntitledFeature, at now: Date = Date()) -> Bool {
        guard !accessPolicy.includesAllFeatures else { return true }
        if accessPolicy == .betaBasic {
            return Self.basicIncludes(feature)
        }

        let currentSubscription = subscription.evaluated(at: now)
        if currentSubscription.status == .proGrace {
            switch feature {
            case .unlimitedLocalCharts,
                 .pdfExport,
                 .documentTransposition,
                 .fontPresets,
                 .roadmapNotationTools,
                 .advancedRhythmEditing,
                 .projects:
                return true
            case .syncedChartOrganization,
                 .cloudBackup,
                 .forums,
                 .sharedBandLibraries,
                 .setlistsAndVersionHistory,
                 .aiRecognitionCleanup:
                return false
            }
        }

        switch currentSubscription.effectivePlan {
        case .free:
            return Self.basicIncludes(feature)
        case .proLifetime:
            switch feature {
            case .unlimitedLocalCharts,
                 .pdfExport,
                 .documentTransposition,
                 .fontPresets,
                 .roadmapNotationTools,
                 .advancedRhythmEditing:
                return true
            case .syncedChartOrganization,
                 .cloudBackup,
                 .forums,
                 .sharedBandLibraries,
                 .setlistsAndVersionHistory,
                 .aiRecognitionCleanup,
                 .projects:
                return false
            }
        case .studioSubscription:
            return true
        }
    }

    private static func basicIncludes(_ feature: EntitledFeature) -> Bool {
        switch feature {
        case .pdfExport,
             .documentTransposition,
             .fontPresets,
             .roadmapNotationTools,
             .advancedRhythmEditing:
            return true
        case .unlimitedLocalCharts,
             .syncedChartOrganization,
             .cloudBackup,
             .forums,
             .sharedBandLibraries,
             .setlistsAndVersionHistory,
             .aiRecognitionCleanup,
             .projects:
            return false
        }
    }

    func canCreateChart(currentChartCount: Int, at now: Date = Date()) -> Bool {
        guard let localChartLimit = localChartLimit(at: now) else {
            return true
        }

        return currentChartCount < localChartLimit
    }

    func remainingLocalChartSlots(currentChartCount: Int, at now: Date = Date()) -> Int? {
        guard let localChartLimit = localChartLimit(at: now) else {
            return nil
        }

        return max(0, localChartLimit - currentChartCount)
    }

    func chartCapacityText(currentChartCount: Int, at now: Date = Date()) -> String {
        if let localChartLimit = localChartLimit(at: now) {
            let remainingSlots = remainingLocalChartSlots(currentChartCount: currentChartCount, at: now) ?? 0

            if remainingSlots == 0 {
                if accessPolicy == .betaBasic {
                    return "Basic creation limit reached. Existing charts stay editable; rejoin free Pro in Settings to add more."
                }
                return "Basic creation limit reached. Keep editing your saved charts, or upgrade to Pro to create more."
            }

            return "\(remainingSlots) of \(localChartLimit) Basic chart slots left."
        }

        return "Unlimited local charts."
    }

    private enum CodingKeys: String, CodingKey {
        case activePlan
        case subscription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPlan = try container.decode(IChartPlan.self, forKey: .activePlan)
        let decodedSubscription = try container.decodeIfPresent(
            IChartSubscriptionEntitlement.self,
            forKey: .subscription
        ) ?? IChartSubscriptionEntitlement.legacyStatus(for: decodedPlan)
        self.init(activePlan: decodedPlan, subscription: decodedSubscription)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activePlan, forKey: .activePlan)
        try container.encode(subscription, forKey: .subscription)
    }
}

import Foundation

enum SmartChartPlan: String, Codable, CaseIterable, Hashable {
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
            return "Transposition Views"
        case .fontPresets:
            return "Font Presets"
        case .roadmapNotationTools:
            return "Special Notation Tools"
        case .advancedRhythmEditing:
            return "Advanced Rhythm Editing"
        case .syncedChartOrganization:
            return "Cross-Device Organization"
        case .cloudBackup:
            return "Cloud Backup"
        case .forums:
            return "Forums"
        case .sharedBandLibraries:
            return "Shared Band Libraries"
        case .setlistsAndVersionHistory:
            return "Setlists and Version History"
        case .aiRecognitionCleanup:
            return "AI-Assisted Cleanup"
        case .projects:
            return "Projects"
        }
    }

    var upgradeMessage: String {
        switch self {
        case .pdfExport:
            return "PDF export is included in Basic because exporting charts is core to the local writing workflow."
        case .documentTransposition:
            return "Transposition views are included in Basic because readable gig charts are core to iChart."
        case .fontPresets:
            return "Font presets are included in Basic because local chart appearance is part of the writing tool."
        case .roadmapNotationTools:
            return "Special notation tools are included in Basic because roadmap editing is essential chart work."
        case .advancedRhythmEditing:
            return "Rhythm-aware editing is included in Basic because rhythm charts are a core iChart format."
        case .unlimitedLocalCharts:
            return "Unlimited local chart capacity is part of the Pro account experience."
        case .projects:
            return "Projects are reserved for active Pro so one song can hold multiple section charts, keys, and variants together."
        case .syncedChartOrganization,
             .cloudBackup,
             .forums,
             .sharedBandLibraries,
             .setlistsAndVersionHistory,
             .aiRecognitionCleanup:
            return "This is reserved for active Pro because it depends on ongoing cloud service value."
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

    private(set) var activePlan: SmartChartPlan
    private(set) var subscription: IChartSubscriptionEntitlement

    init(
        activePlan: SmartChartPlan,
        subscription: IChartSubscriptionEntitlement? = nil
    ) {
        let resolvedSubscription = subscription ?? IChartSubscriptionEntitlement.legacyStatus(for: activePlan)
        self.activePlan = resolvedSubscription.effectivePlan
        self.subscription = resolvedSubscription
    }

    init(subscription: IChartSubscriptionEntitlement) {
        self.activePlan = subscription.effectivePlan
        self.subscription = subscription
    }

    mutating func applySubscription(_ subscription: IChartSubscriptionEntitlement) {
        self.subscription = subscription
        activePlan = subscription.effectivePlan
    }

    mutating func applyLegacyPlan(_ plan: SmartChartPlan) {
        applySubscription(IChartSubscriptionEntitlement.legacyStatus(for: plan))
    }

    var localChartLimit: Int? {
        switch activePlan {
        case .free:
            return Self.recommendedFreeChartLimit
        case .proLifetime, .studioSubscription:
            return nil
        }
    }

    func includes(_ feature: EntitledFeature) -> Bool {
        switch activePlan {
        case .free:
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

    func canCreateChart(currentChartCount: Int) -> Bool {
        guard let localChartLimit else {
            return true
        }

        return currentChartCount < localChartLimit
    }

    func remainingLocalChartSlots(currentChartCount: Int) -> Int? {
        guard let localChartLimit else {
            return nil
        }

        return max(0, localChartLimit - currentChartCount)
    }

    func chartCapacityText(currentChartCount: Int) -> String {
        if let localChartLimit {
            let remainingSlots = remainingLocalChartSlots(currentChartCount: currentChartCount) ?? 0

            if remainingSlots == 0 {
                return "Basic limit reached: \(localChartLimit) local charts. Pro removes the cap."
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
        let decodedPlan = try container.decode(SmartChartPlan.self, forKey: .activePlan)
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

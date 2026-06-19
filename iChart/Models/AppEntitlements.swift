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
            return "Font presets are included in Basic because local chart appearance is part of the writing tool."
        case .roadmapNotationTools:
            return "Repeats and Coda are included in Basic because chart navigation is essential chart work."
        case .advancedRhythmEditing:
            return "Rhythm-aware editing is included in Basic because rhythm charts are a core iChart format."
        case .unlimitedLocalCharts:
            return "Unlimited local chart capacity is part of the Pro account experience."
        case .projects:
            return "Projects are reserved for active Pro so one song can hold multiple section charts and variants together."
        case .syncedChartOrganization,
             .cloudBackup,
             .forums,
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

    private(set) var activePlan: IChartPlan
    private(set) var subscription: IChartSubscriptionEntitlement

    init(
        activePlan: IChartPlan,
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

    mutating func applyLegacyPlan(_ plan: IChartPlan) {
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

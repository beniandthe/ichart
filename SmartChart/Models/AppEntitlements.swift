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

    var activePlan: SmartChartPlan

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
                 .aiRecognitionCleanup:
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
                 .aiRecognitionCleanup:
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
}

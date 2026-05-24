import Foundation

enum SmartChartPlan: String, Codable, CaseIterable, Hashable {
    case free
    case proLifetime
    case studioSubscription

    var displayText: String {
        switch self {
        case .free:
            return "Free"
        case .proLifetime:
            return "Pro"
        case .studioSubscription:
            return "Studio"
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
            return "PDF export is part of Pro so the free tier can stay easy to try while clean shareable output remains part of the owned local tool."
        case .documentTransposition:
            return "Concert, Bb, and Eb views are part of Pro because they are core ownership features for working charts."
        case .fontPresets:
            return "Additional document-wide font presets live in Pro along with the rest of the full local authoring tool."
        case .roadmapNotationTools:
            return "Special notation tools such as Coda, Segno, and D.S./D.C. are part of the Pro authoring tier."
        case .advancedRhythmEditing:
            return "More advanced rhythm-aware editing belongs in Pro so the free tier stays lightweight while serious chart work stays permanently unlocked."
        case .unlimitedLocalCharts:
            return "Unlimited local chart ownership is part of the one-time Pro unlock, not a subscription."
        case .syncedChartOrganization,
             .cloudBackup,
             .sharedBandLibraries,
             .setlistsAndVersionHistory,
             .aiRecognitionCleanup:
            return "This is reserved for a later Studio subscription because it depends on real ongoing-service value."
        }
    }
}

extension EntitledFeature: Identifiable {
    var id: String { rawValue }
}

struct AppEntitlements: Codable, Hashable {
    static let recommendedFreeChartLimit = 5
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
            return false
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
                return "Free limit reached: \(localChartLimit) local charts. Pro removes the cap and adds export."
            }

            return "\(remainingSlots) of \(localChartLimit) free chart slots left."
        }

        return "Unlimited local charts."
    }
}

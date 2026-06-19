import Foundation

enum IChartSubscriptionStatus: String, Codable, CaseIterable, Hashable {
    case basic
    case proActive
    case proGrace
    case proExpired
    case unavailable
    case legacyLocalPro
}

struct IChartSubscriptionEntitlement: Codable, Hashable {
    var status: IChartSubscriptionStatus
    var graceEndsAt: Date?
    var lastVerifiedAt: Date?

    init(
        status: IChartSubscriptionStatus,
        graceEndsAt: Date? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.status = status
        self.graceEndsAt = graceEndsAt
        self.lastVerifiedAt = lastVerifiedAt
    }

    static let basic = IChartSubscriptionEntitlement(status: .basic)
    static let unavailable = IChartSubscriptionEntitlement(status: .unavailable)
    static let legacyLocalPro = IChartSubscriptionEntitlement(status: .legacyLocalPro)

    static func activePro(verifiedAt: Date? = nil) -> IChartSubscriptionEntitlement {
        IChartSubscriptionEntitlement(status: .proActive, lastVerifiedAt: verifiedAt)
    }

    static func proGrace(
        graceEndsAt: Date,
        verifiedAt: Date? = nil
    ) -> IChartSubscriptionEntitlement {
        IChartSubscriptionEntitlement(
            status: .proGrace,
            graceEndsAt: graceEndsAt,
            lastVerifiedAt: verifiedAt
        )
    }

    static func proExpired(verifiedAt: Date? = nil) -> IChartSubscriptionEntitlement {
        IChartSubscriptionEntitlement(status: .proExpired, lastVerifiedAt: verifiedAt)
    }

    static func legacyStatus(for plan: IChartPlan) -> IChartSubscriptionEntitlement {
        switch plan {
        case .free:
            return .basic
        case .proLifetime:
            return .legacyLocalPro
        case .studioSubscription:
            return .activePro()
        }
    }

    var effectivePlan: IChartPlan {
        switch status {
        case .basic, .proGrace, .proExpired, .unavailable:
            return .free
        case .legacyLocalPro:
            return .proLifetime
        case .proActive:
            return .studioSubscription
        }
    }

    var displayTitle: String {
        switch status {
        case .basic:
            return "Basic"
        case .proActive:
            return "Pro Active"
        case .proGrace:
            return "Pro Grace"
        case .proExpired:
            return "Pro Expired"
        case .unavailable:
            return "Plan Check Unavailable"
        case .legacyLocalPro:
            return "Legacy Local Pro"
        }
    }

    var detailText: String {
        switch status {
        case .basic:
            return "Local authoring, export, account recovery, and up to 3 local charts."
        case .proActive:
            return "Unlimited local charts, cloud backup and restore, and Forums access."
        case .proGrace:
            if let graceEndsAt {
                return "Cloud backup is paused. Remote backups remain through \(graceEndsAt.formatted(date: .abbreviated, time: .omitted))."
            }

            return "Cloud backup is paused during the grace period. Remote backups remain temporarily recoverable."
        case .proExpired:
            return "Pro is inactive. Cloud backup and Forums are locked until Pro is restored."
        case .unavailable:
            return "Subscription status could not be verified, so the app is using Basic limits locally."
        case .legacyLocalPro:
            return "Legacy local Pro keeps unlimited local chart creation, but cloud services still require active Pro."
        }
    }

    var cloudAccessText: String {
        switch status {
        case .proActive:
            return "Available"
        case .proGrace:
            return "Paused during grace"
        case .basic:
            return "Requires Pro"
        case .proExpired:
            return "Restore Pro"
        case .unavailable:
            return "Unavailable"
        case .legacyLocalPro:
            return "Requires active Pro"
        }
    }

    var forumsAccessText: String {
        switch status {
        case .proActive:
            return "Available"
        case .proGrace:
            return "Requires active Pro"
        case .basic:
            return "Requires Pro"
        case .proExpired:
            return "Restore Pro"
        case .unavailable:
            return "Unavailable"
        case .legacyLocalPro:
            return "Requires active Pro"
        }
    }

    var allowsForumDownloadAccess: Bool {
        switch status {
        case .proActive, .proGrace:
            return true
        case .basic, .proExpired, .unavailable, .legacyLocalPro:
            return false
        }
    }

    var shouldRemoveForumDownloads: Bool {
        switch status {
        case .basic, .proExpired, .legacyLocalPro:
            return true
        case .proActive, .proGrace, .unavailable:
            return false
        }
    }

    var badgeText: String {
        switch status {
        case .basic:
            return "Basic"
        case .proActive:
            return "Pro"
        case .proGrace:
            return "Grace"
        case .proExpired:
            return "Expired"
        case .unavailable:
            return "Offline"
        case .legacyLocalPro:
            return "Legacy"
        }
    }

    var systemImageName: String {
        switch status {
        case .basic:
            return "person.crop.circle"
        case .proActive:
            return "star.circle.fill"
        case .proGrace:
            return "clock.badge.exclamationmark"
        case .proExpired:
            return "exclamationmark.circle"
        case .unavailable:
            return "wifi.slash"
        case .legacyLocalPro:
            return "clock.arrow.circlepath"
        }
    }

    func resolvedForLibraryApplication(
        currentLibraryEntitlement: IChartSubscriptionEntitlement
    ) -> IChartSubscriptionEntitlement {
        guard currentLibraryEntitlement.status == .legacyLocalPro,
              status != .proActive else {
            return self
        }

        return currentLibraryEntitlement
    }
}

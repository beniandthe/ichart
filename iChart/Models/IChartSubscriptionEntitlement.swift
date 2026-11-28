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
    var accessEndsAt: Date?
    var willAutoRenew: Bool?
    var lastVerifiedAt: Date?

    init(
        status: IChartSubscriptionStatus,
        graceEndsAt: Date? = nil,
        accessEndsAt: Date? = nil,
        willAutoRenew: Bool? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.status = status
        self.graceEndsAt = graceEndsAt
        self.accessEndsAt = accessEndsAt
        self.willAutoRenew = willAutoRenew
        self.lastVerifiedAt = lastVerifiedAt
    }

    static let basic = IChartSubscriptionEntitlement(status: .basic)
    static let unavailable = IChartSubscriptionEntitlement(status: .unavailable)
    static let legacyLocalPro = IChartSubscriptionEntitlement(status: .legacyLocalPro)

    static func activePro(
        accessEndsAt: Date? = nil,
        willAutoRenew: Bool? = nil,
        verifiedAt: Date? = nil
    ) -> IChartSubscriptionEntitlement {
        IChartSubscriptionEntitlement(
            status: .proActive,
            accessEndsAt: accessEndsAt,
            willAutoRenew: willAutoRenew,
            lastVerifiedAt: verifiedAt
        )
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

    /// A known paid-through boundary, independent of renewal intent or the local clock.
    /// Nil retains the existing unbounded legacy/debug snapshot behavior.
    var accessDeadline: Date? {
        switch status {
        case .proActive:
            return accessEndsAt
        case .proGrace:
            return graceEndsAt
        case .basic, .proExpired, .unavailable, .legacyLocalPro:
            return nil
        }
    }

    /// Re-evaluate cached authority at the point of use without inventing a new
    /// verification time or changing the original paid-through evidence.
    func evaluated(at now: Date) -> IChartSubscriptionEntitlement {
        guard let accessDeadline, accessDeadline <= now else { return self }
        var expired = self
        expired.status = .proExpired
        return expired
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
            return "Create up to 3 local charts. Keep editing and exporting all your saved charts."
        case .proActive:
            if willAutoRenew == false, let accessEndsAt {
                return "Pro remains active until \(accessEndsAt.formatted(date: .abbreviated, time: .omitted)). Cloud backup, restore, and Forum participation stay available until then."
            }

            return "Unlimited local charts, cloud backup and restore, and Forum participation."
        case .proGrace:
            if let graceEndsAt {
                return "Local Pro tools remain available through \(graceEndsAt.formatted(date: .abbreviated, time: .omitted)). Cloud backup, new Forum downloads, and Forum participation are paused during grace."
            }

            return "Local Pro tools remain available during billing grace. Cloud backup, new Forum downloads, and Forum participation are paused during grace."
        case .proExpired:
            return "Pro is inactive. Your saved charts, PDFs, and setlists remain available on this device."
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
        status == .proActive ? "Read, download, and participate" : "Browse and read"
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
        currentLibraryEntitlement: IChartSubscriptionEntitlement,
        at now: Date = Date()
    ) -> IChartSubscriptionEntitlement {
        let current = evaluated(at: now)
        guard currentLibraryEntitlement.status == .legacyLocalPro,
              current.status != .proActive else {
            return current
        }

        return currentLibraryEntitlement
    }
}

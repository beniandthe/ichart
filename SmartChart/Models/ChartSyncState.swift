import Foundation

enum ChartSyncState: Equatable {
    case unconfigured
    case signedOut
    case requiresPro
    case offline
    case syncing
    case synced(Date)
    case failed(String)

    var displayText: String {
        switch self {
        case .unconfigured:
            return "Cloud backup unavailable"
        case .signedOut:
            return "Sign in to back up"
        case .requiresPro:
            return "Cloud backup requires Pro"
        case .offline:
            return "Offline"
        case .syncing:
            return "Syncing"
        case .synced(let date):
            return "Synced \(date.formatted(date: .omitted, time: .shortened))"
        case .failed:
            return "Sync needs attention"
        }
    }

    var detailText: String {
        switch self {
        case .unconfigured:
            return "Add Supabase configuration to enable cloud backup."
        case .signedOut:
            return "Charts stay local until you sign in."
        case .requiresPro:
            return "Charts are saved locally. Upgrade to Pro to back up and restore from cloud."
        case .offline:
            return "Local edits are saved. Reconnect to back up."
        case .syncing:
            return "Checking cloud backup and uploading local changes."
        case .synced:
            return "Charts are backed up."
        case .failed(let message):
            return message
        }
    }

    var systemImageName: String {
        switch self {
        case .unconfigured:
            return "icloud.slash"
        case .signedOut:
            return "person.crop.circle.badge.exclamationmark"
        case .requiresPro:
            return "lock.icloud"
        case .offline:
            return "wifi.slash"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .synced:
            return "icloud.and.arrow.up.fill"
        case .failed:
            return "exclamationmark.icloud"
        }
    }

    var manualSyncTitle: String {
        switch self {
        case .unconfigured:
            return "Unavailable"
        case .signedOut:
            return "Sign In First"
        case .requiresPro:
            return "Requires Pro"
        case .offline, .failed:
            return "Retry Sync"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Sync Now"
        }
    }

    var manualSyncSystemImageName: String {
        switch self {
        case .offline:
            return "wifi.exclamationmark"
        case .failed:
            return "arrow.clockwise"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        default:
            return "arrow.triangle.2.circlepath"
        }
    }

    var allowsManualSync: Bool {
        switch self {
        case .offline, .synced, .failed:
            return true
        case .unconfigured, .signedOut, .requiresPro, .syncing:
            return false
        }
    }

    var manualSyncDisabledReason: String? {
        switch self {
        case .unconfigured:
            return "Cloud backup is not configured in this build."
        case .signedOut:
            return "Sign in to enable cloud backup."
        case .requiresPro:
            return "Cloud backup and restore require Pro."
        case .syncing:
            return nil
        case .offline, .synced, .failed:
            return nil
        }
    }
}

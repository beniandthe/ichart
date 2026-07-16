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
            return "Backing up"
        case .synced:
            return "Cloud backup active"
        case .failed:
            return "Cloud backup needs attention"
        }
    }

    var detailText: String {
        switch self {
        case .unconfigured:
            return "Cloud backup is unavailable right now."
        case .signedOut:
            return "Charts stay local until you sign in."
        case .requiresPro:
            return "Upgrade to Pro to back up and restore from cloud."
        case .offline:
            return "Reconnect to back up."
        case .syncing:
            return "Backing up eligible local charts."
        case .synced:
            return "Back Up Now includes this iPad's local charts in cloud backup. Restore only when you want cloud charts added here."
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
            return "Try Again"
        case .syncing:
            return "Backing Up"
        case .synced:
            return "Back Up Now"
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
            return "Cloud backup is unavailable right now."
        case .signedOut:
            return "Sign in to enable cloud backup and restore."
        case .requiresPro:
            return "Cloud backup and restore require Pro."
        case .syncing:
            return nil
        case .offline, .synced, .failed:
            return nil
        }
    }

    var allowsCloudRestore: Bool {
        switch self {
        case .synced, .failed:
            return true
        case .unconfigured, .signedOut, .requiresPro, .offline, .syncing:
            return false
        }
    }

    var cloudRestoreDisabledReason: String? {
        switch self {
        case .unconfigured:
            return "Cloud restore is unavailable right now."
        case .signedOut:
            return "Sign in to restore charts from cloud."
        case .requiresPro:
            return "Cloud backup and restore require Pro."
        case .offline:
            return "Reconnect to restore charts from cloud."
        case .syncing:
            return nil
        case .synced, .failed:
            return nil
        }
    }
}

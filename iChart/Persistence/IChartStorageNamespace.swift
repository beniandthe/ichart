import Foundation

/// Internal StoreKit staging keeps its app-owned files, preferences and auth
/// keys separate. The ordinary build retains its exact existing locations.
/// This boundary never migrates, copies, deletes or falls back to public data.
enum IChartStorageNamespace {
    enum Mode {
        case publicApp
        case internalStaging
    }

    #if ICHART_STAGING_STOREKIT_PRODUCTS
    static let mode: Mode = .internalStaging
    #else
    static let mode: Mode = .publicApp
    #endif

    static let stagingDirectoryName = "iChart Internal Staging FIX036"
    static let stagingDefaultsSuiteName = "com.ichart.app.internal-staging.fix036"
    static let stagingAuthKeyPrefix = "internal-staging.fix036."

    static var isInternalStaging: Bool { mode == .internalStaging }

    static let defaults: UserDefaults = {
        switch mode {
        case .publicApp:
            return .standard
        case .internalStaging:
            guard let isolated = UserDefaults(suiteName: stagingDefaultsSuiteName) else {
                preconditionFailure("Internal staging preferences are unavailable.")
            }
            return isolated
        }
    }()

    static func scopedDirectory(_ root: URL, mode: Mode = mode) -> URL {
        switch mode {
        case .publicApp:
            return root
        case .internalStaging:
            return root.appendingPathComponent(stagingDirectoryName, isDirectory: true)
        }
    }

    static func authStorageKey(_ key: String, mode: Mode = mode) -> String {
        mode == .internalStaging ? stagingAuthKeyPrefix + key : key
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return scopedDirectory(root)
    }

    static func cachesDirectory(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return scopedDirectory(root)
    }

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        scopedDirectory(fileManager.temporaryDirectory)
    }
}

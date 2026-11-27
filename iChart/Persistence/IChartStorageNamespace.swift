import Foundation

/// Internal StoreKit staging keeps its app-owned files, preferences and auth
/// keys separate. The ordinary build retains its exact existing locations.
/// This boundary never migrates, copies, deletes or falls back to public data.
enum IChartStorageNamespace {
    enum Mode {
        case publicApp
        case internalStaging
        case coordinatedStagingQA
    }

    #if ICHART_COORDINATED_STAGING_QA
    static let mode: Mode = .coordinatedStagingQA
    #else
    #if ICHART_STAGING_STOREKIT_PRODUCTS
    static let mode: Mode = .internalStaging
    #else
    static let mode: Mode = .publicApp
    #endif
    #endif

    static let stagingDirectoryName = "iChart Internal Staging FIX036"
    static let stagingDefaultsSuiteName = "com.ichart.app.internal-staging.fix036"
    static let stagingAuthKeyPrefix = "internal-staging.fix036."

    static let coordinatedQADirectoryName = "iChart Coordinated QA yiuxduqhhbucsmooevxz"
    static let coordinatedQADefaultsSuiteName = "com.ichart.app.coordinated-qa.yiuxduqhhbucsmooevxz"
    static let coordinatedQAAuthKeyPrefix = "coordinated-qa.yiuxduqhhbucsmooevxz."

    static var isInternalStaging: Bool { mode != .publicApp }
    static var activeDefaultsSuiteName: String? {
        switch mode {
        case .publicApp: return nil
        case .internalStaging: return stagingDefaultsSuiteName
        case .coordinatedStagingQA: return coordinatedQADefaultsSuiteName
        }
    }

    static var productAccessCacheProjectRef: String {
        switch mode {
        case .publicApp: return "pausvvwoazbvmzyrebwl"
        case .internalStaging: return "gfqpbikqvdgtjjgxrkgo"
        case .coordinatedStagingQA: return "yiuxduqhhbucsmooevxz"
        }
    }

    static let defaults: UserDefaults = {
        switch mode {
        case .publicApp:
            return .standard
        case .internalStaging:
            guard let scopedDefaults = UserDefaults(suiteName: stagingDefaultsSuiteName) else {
                preconditionFailure("Internal staging preferences are unavailable.")
            }
            return scopedDefaults
        case .coordinatedStagingQA:
            guard let scopedDefaults = UserDefaults(suiteName: coordinatedQADefaultsSuiteName) else {
                preconditionFailure("Coordinated QA preferences are unavailable.")
            }
            return scopedDefaults
        }
    }()

    static func scopedDirectory(_ root: URL, mode: Mode = mode) -> URL {
        switch mode {
        case .publicApp:
            return root
        case .internalStaging:
            return root.appendingPathComponent(stagingDirectoryName, isDirectory: true)
        case .coordinatedStagingQA:
            return root.appendingPathComponent(coordinatedQADirectoryName, isDirectory: true)
        }
    }

    static func authStorageKey(_ key: String, mode: Mode = mode) -> String {
        if mode == .coordinatedStagingQA { return coordinatedQAAuthKeyPrefix + key }
        return originalAuthStorageKey(key, mode: mode)
    }

    private static func originalAuthStorageKey(_ key: String, mode: Mode) -> String {
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

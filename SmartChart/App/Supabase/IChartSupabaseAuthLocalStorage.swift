import Foundation
import Supabase

struct IChartSupabaseAuthLocalStorage: AuthLocalStorage {
    private let primary: any AuthLocalStorage
    private let fallback: IChartUserDefaultsAuthLocalStorage
    private let allowsInsecureFallback: Bool

    init(
        primary: any AuthLocalStorage = KeychainLocalStorage(),
        fallback: IChartUserDefaultsAuthLocalStorage = IChartUserDefaultsAuthLocalStorage(),
        allowsInsecureFallback: Bool = Self.defaultAllowsInsecureFallback
    ) {
        self.primary = primary
        self.fallback = fallback
        self.allowsInsecureFallback = allowsInsecureFallback
    }

    func store(key: String, value: Data) throws {
        do {
            try primary.store(key: key, value: value)
            try? fallback.remove(key: key)
        } catch {
            guard allowsInsecureFallback else {
                throw error
            }

            try fallback.store(key: key, value: value)
        }
    }

    func retrieve(key: String) throws -> Data? {
        do {
            if let value = try primary.retrieve(key: key) {
                return value
            }
        } catch {
            guard allowsInsecureFallback else {
                throw error
            }
        }

        guard allowsInsecureFallback else {
            return nil
        }

        return try fallback.retrieve(key: key)
    }

    func remove(key: String) throws {
        try? primary.remove(key: key)
        try fallback.remove(key: key)
    }

    private static var defaultAllowsInsecureFallback: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

final class IChartUserDefaultsAuthLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func store(key: String, value: Data) throws {
        defaults.set(value, forKey: namespaced(key))
    }

    func retrieve(key: String) throws -> Data? {
        defaults.data(forKey: namespaced(key))
    }

    func remove(key: String) throws {
        defaults.removeObject(forKey: namespaced(key))
    }

    private func namespaced(_ key: String) -> String {
        "iChart.supabase.auth.\(key)"
    }
}

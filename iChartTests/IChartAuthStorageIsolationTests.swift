#if canImport(UIKit)
import Foundation
import Supabase
import XCTest
@testable import iChart

final class IChartAuthStorageIsolationTests: XCTestCase {
    private let authKeys = [
        "iChart.supabase.session.v1",
        "iChart.pending-verification-email.v1",
        "iChart.pending-auth-flow.v1",
        "supabase.session",
        "supabase.auth.token",
        "sb-pausvvwoazbvmzyrebwl-auth-token",
        "sb-gfqpbikqvdgtjjgxrkgo-auth-token",
        "sb-gfqpbikqvdgtjjgxrkgo-auth-token-code-verifier"
    ]

    func testAllAuthKeysUseTheSelectedNamespaceForReadWriteAndRemoval() throws {
        let suiteName = "IChartAuthStorageIsolationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = Data("synthetic production session".utf8)
        let staging = Data("synthetic staging session".utf8)
        let primary = IsolationAuthStorage(values: Dictionary(uniqueKeysWithValues: authKeys.map { ($0, original) }))
        let storage = IChartSupabaseAuthLocalStorage(
            primary: primary,
            fallback: IChartUserDefaultsAuthLocalStorage(defaults: defaults),
            allowsInsecureFallback: false
        )

        for key in authKeys {
            let scoped = IChartStorageNamespace.authStorageKey(key)
            if IChartStorageNamespace.isInternalStaging {
                XCTAssertNotEqual(scoped, key)
                XCTAssertNil(try storage.retrieve(key: key))
            } else {
                XCTAssertEqual(scoped, key)
                XCTAssertEqual(try storage.retrieve(key: key), original)
            }

            try storage.store(key: key, value: staging)
            XCTAssertEqual(try storage.retrieve(key: key), staging)
            XCTAssertEqual(try primary.retrieve(key: scoped), staging)
            try storage.remove(key: key)
            XCTAssertNil(try storage.retrieve(key: key))
            if IChartStorageNamespace.isInternalStaging {
                XCTAssertEqual(try primary.retrieve(key: key), original)
            }
        }
    }

    func testFallbackUsesScopedKeysAndNeverImportsUnscopedValues() throws {
        let suiteName = "IChartAuthStorageIsolationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = Data("synthetic old fallback".utf8)
        let replacement = Data("synthetic new fallback".utf8)
        let fallback = IChartUserDefaultsAuthLocalStorage(defaults: defaults)
        let storage = IChartSupabaseAuthLocalStorage(
            primary: IsolationAuthStorage(fails: true),
            fallback: fallback,
            allowsInsecureFallback: true
        )
        let key = "supabase.session"
        let originalDefaultsKey = "iChart.supabase.auth.\(key)"
        defaults.set(original, forKey: originalDefaultsKey)

        if IChartStorageNamespace.isInternalStaging {
            XCTAssertNil(try storage.retrieve(key: key))
        } else {
            XCTAssertEqual(try storage.retrieve(key: key), original)
        }
        try storage.store(key: key, value: replacement)
        XCTAssertEqual(try storage.retrieve(key: key), replacement)
        try storage.remove(key: key)
        XCTAssertNil(try storage.retrieve(key: key))
        if IChartStorageNamespace.isInternalStaging {
            XCTAssertEqual(defaults.data(forKey: originalDefaultsKey), original)
        }
    }

    func testDisallowedFallbackDoesNotReadOrWriteFallbackSessions() throws {
        let suiteName = "IChartAuthStorageIsolationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fallback = IChartUserDefaultsAuthLocalStorage(defaults: defaults)
        let key = "iChart.supabase.session.v1"
        let scoped = IChartStorageNamespace.authStorageKey(key)
        let original = Data("synthetic fallback".utf8)
        try fallback.store(key: scoped, value: original)
        let storage = IChartSupabaseAuthLocalStorage(
            primary: IsolationAuthStorage(fails: true),
            fallback: fallback,
            allowsInsecureFallback: false
        )

        XCTAssertThrowsError(try storage.retrieve(key: key))
        XCTAssertThrowsError(try storage.store(key: key, value: Data()))
        XCTAssertEqual(try fallback.retrieve(key: scoped), original)
    }

    func testStagingNetworkingHasNoSharedPersistentStores() {
        let session = IChartSupabaseClientFactory.networkSession
        if IChartStorageNamespace.isInternalStaging {
            XCTAssertFalse(session === URLSession.shared)
            XCTAssertNil(session.configuration.urlCache)
            XCTAssertNil(session.configuration.httpCookieStorage)
            XCTAssertNil(session.configuration.urlCredentialStorage)
            XCTAssertFalse(session.configuration.httpShouldSetCookies)
        } else {
            XCTAssertTrue(session === URLSession.shared)
        }
    }
}

private final class IsolationAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private enum StorageError: Error { case unavailable }
    private let lock = NSLock()
    private var values: [String: Data]
    private let fails: Bool

    init(values: [String: Data] = [:], fails: Bool = false) {
        self.values = values
        self.fails = fails
    }

    func store(key: String, value: Data) throws {
        guard !fails else { throw StorageError.unavailable }
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        guard !fails else { throw StorageError.unavailable }
        return lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        guard !fails else { throw StorageError.unavailable }
        lock.withLock { values[key] = nil }
    }
}
#endif

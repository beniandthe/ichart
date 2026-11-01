#if canImport(UIKit)
import Foundation
import Supabase
import XCTest
@testable import iChart

@MainActor
final class AuthStoreOfflineRestoreTests: XCTestCase {
    func testCachedVerifiedSessionRemainsLocallyAvailableWhenProfileIsOfflineThenReconnects() async {
        let service = OfflineRestoreAccountService()
        service.profileResult = .failure(URLError(.notConnectedToInternet))
        let store = makeStore(service)

        await store.bootstrap()

        XCTAssertEqual(store.state, .temporarilyOffline(service.session))
        XCTAssertNil(store.profile)
        XCTAssertFalse(store.needsAccountIdentityCompletion)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.statusMessage, "Account is offline. Local charts remain available.")
        XCTAssertEqual(service.profileRequests, [service.session.id])
        XCTAssertEqual(service.signOutCalls, 0)

        let profile = service.completeProfile
        service.profileResult = .success(profile)
        await store.refreshSession()

        XCTAssertEqual(store.state, .signedIn(service.session))
        XCTAssertEqual(store.profile, profile)
        XCTAssertTrue(store.hasCompleteAccountIdentity)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(service.restoreCalls, 2)
        XCTAssertEqual(service.signOutCalls, 0)
    }

    func testWrappedTransportFailureAndBridgedNSErrorUseSameOfflineRecovery() async {
        for error in [
            NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue),
            NSError(domain: "ProfileTransport", code: 1, userInfo: [
                NSUnderlyingErrorKey: URLError(.networkConnectionLost) as NSError
            ])
        ] {
            let service = OfflineRestoreAccountService()
            service.profileResult = .failure(error)
            let store = makeStore(service)
            await store.bootstrap()
            XCTAssertEqual(store.state, .temporarilyOffline(service.session))
            XCTAssertNil(store.errorMessage)
        }
    }

    func testNoRecoveredSessionRemainsSignedOutAndDoesNotFetchProfile() async {
        let service = OfflineRestoreAccountService()
        service.restoreResult = .success(.signedOut)
        let store = makeStore(service)
        await store.bootstrap()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(service.profileRequests.isEmpty)
    }

    func testAuthorizationAndNonconnectivityProfileFailuresDoNotBypassAccountGate() async {
        for error: Error in [
            NSError(domain: "ProfileHTTP", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"]),
            NSError(domain: "ProfileHTTP", code: 403, userInfo: [NSLocalizedDescriptionKey: "Forbidden"]),
            NSError(domain: "ProfileHTTP", code: 401, userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet)]),
            URLError(.userAuthenticationRequired),
            IChartAuthError.profileUnavailable,
            NSError(domain: "ProfileDecode", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The internet connection appears to be offline."
            ])
        ] {
            let service = OfflineRestoreAccountService()
            service.profileResult = .failure(error)
            let store = makeStore(service)
            await store.bootstrap()
            XCTAssertEqual(store.state, .signedOut)
            XCTAssertNil(store.profile)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testMissingProfileStillRequiresIdentityCompletion() async {
        let service = OfflineRestoreAccountService()
        service.profileResult = .success(nil)
        let store = makeStore(service)
        await store.bootstrap()
        XCTAssertEqual(store.state, .signedIn(service.session))
        XCTAssertTrue(store.needsAccountIdentityCompletion)
        XCTAssertNil(store.profile)
        XCTAssertNil(store.errorMessage)
    }

    func testUnverifiedRecoveredSessionCannotUseProfileConnectivityFallback() async {
        let service = OfflineRestoreAccountService()
        let unverified = IChartAccountSession(id: service.session.id, email: service.session.email,
                                             phone: nil, isEmailVerified: false)
        service.restoreResult = .success(.signedIn(unverified))
        service.profileResult = .failure(URLError(.notConnectedToInternet))
        let store = makeStore(service)
        await store.bootstrap()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNotNil(store.errorMessage)
    }

    func testMalformedSessionRestoreDoesNotBecomeOfflineAccess() async {
        let service = OfflineRestoreAccountService()
        service.restoreResult = .failure(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid saved session")))
        let store = makeStore(service)
        await store.bootstrap()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(service.profileRequests.isEmpty)
    }

    func testAlreadyOfflineSessionSkipsProfileRequest() async {
        let service = OfflineRestoreAccountService()
        service.restoreResult = .success(.temporarilyOffline(service.session))
        service.profileResult = .failure(URLError(.notConnectedToInternet))
        let store = makeStore(service)
        await store.bootstrap()
        XCTAssertEqual(store.state, .temporarilyOffline(service.session))
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(service.profileRequests.isEmpty)
    }

    func testInteractiveSignInDoesNotUseRestorationOnlyFallback() async {
        let service = OfflineRestoreAccountService()
        service.profileResult = .failure(URLError(.notConnectedToInternet))
        let store = makeStore(service)
        await store.signIn(email: "musician@example.com", password: "fixture-password")
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.profile)
        XCTAssertNotNil(store.errorMessage)
    }

    func testInteractiveSignupDoesNotUseRestorationOnlyFallback() async {
        let service = OfflineRestoreAccountService()
        service.profileResult = .failure(URLError(.notConnectedToInternet))
        let store = makeStore(service)
        await store.createAccount(email: "musician@example.com", password: "fixture-password",
                                  firstName: "Test", lastName: "Musician")
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.profile)
        XCTAssertNotNil(store.errorMessage)
    }

    private func makeStore(_ service: OfflineRestoreAccountService) -> IChartAuthStore {
        IChartAuthStore(service: service, pendingVerificationEmailStorage: OfflineRestoreMemoryStorage())
    }
}

@MainActor
private final class OfflineRestoreAccountService: IChartAccountServicing {
    let isConfigured = true
    let session = IChartAccountSession(id: UUID(), email: "musician@example.com", phone: nil, isEmailVerified: true)
    var restoreResult: Result<IChartAuthState, Error>?
    var profileResult: Result<IChartUserProfile?, Error> = .success(nil)
    var profileRequests: [UUID] = []
    var restoreCalls = 0
    var signOutCalls = 0

    var completeProfile: IChartUserProfile {
        IChartUserProfile(id: session.id, email: session.email, firstName: "Test", lastName: "Musician")
    }

    func restoreSession() async throws -> IChartAuthState {
        restoreCalls += 1
        return try restoreResult?.get() ?? .signedIn(session)
    }
    func loadProfile(for userID: UUID) async throws -> IChartUserProfile? {
        profileRequests.append(userID)
        return try profileResult.get()
    }
    func signUp(email: String, password: String, firstName: String?, lastName: String?, redirectURL: URL) async throws -> IChartAuthState {
        .signedIn(session)
    }
    func signIn(email: String, password: String) async throws -> IChartAuthState { .signedIn(session) }
    func signOut() async throws { signOutCalls += 1 }
    func deleteAccount() async throws { throw IChartAuthError.profileUnavailable }
    func resendVerificationEmail(email: String, redirectURL: URL) async throws {}
    func requestPasswordReset(email: String, redirectURL: URL) async throws {}
    func handleAuthCallback(url: URL) async throws -> IChartAuthState { .signedIn(session) }
    func updatePassword(_ password: String) async throws -> IChartAuthState { .signedIn(session) }
    func completeProfileIdentity(for userID: UUID, firstName: String, lastName: String) async throws -> IChartUserProfile {
        completeProfile
    }
}

private final class OfflineRestoreMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }
    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
#endif

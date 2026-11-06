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

    func testOlderBootstrapResultCannotSignBackInAfterNewerSignOut() async {
        let service = OfflineRestoreAccountService()
        let store = makeStore(service)
        service.holdsRestore = true
        let started = expectation(description: "Old bootstrap waiting in noncooperative service")
        service.onRestoreStarted = { started.fulfill() }
        let bootstrap = Task { await store.bootstrap() }
        await fulfillment(of: [started], timeout: 30)

        await store.signOut()
        service.releaseRestore()
        await bootstrap.value

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.profile)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.statusMessage, "Signed out.")
        XCTAssertFalse(store.isWorking)
    }

    func testOlderProfileLoadCannotReplaceNewerAccountStateOrProfile() async {
        let service = OfflineRestoreAccountService()
        let store = makeStore(service)
        service.heldProfileIDs.insert(service.session.id)
        let started = expectation(description: "Old account profile load held")
        service.onProfileStarted = { id in if id == service.session.id { started.fulfill() } }
        let bootstrap = Task { await store.bootstrap() }
        await fulfillment(of: [started], timeout: 30)
        let newer = configureNewAccount(on: service)

        await store.signIn(email: "newer@example.invalid", password: "fixture-password")
        service.releaseProfile(service.session.id)
        await bootstrap.value

        XCTAssertEqual(store.state, .signedIn(newer.session))
        XCTAssertEqual(store.profile, newer.profile)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.statusMessage, "Signed in.")
        XCTAssertFalse(store.isWorking)
    }

    func testOlderBootstrapFailureCannotOverwriteNewerSignInStatusOrError() async {
        let service = OfflineRestoreAccountService()
        service.restoreResult = .failure(URLError(.timedOut))
        service.holdsRestore = true
        let store = makeStore(service)
        let started = expectation(description: "Old failing bootstrap held")
        service.onRestoreStarted = { started.fulfill() }
        let bootstrap = Task { await store.bootstrap() }
        await fulfillment(of: [started], timeout: 30)
        let newer = configureNewAccount(on: service)

        await store.signIn(email: "newer@example.invalid", password: "fixture-password")
        service.releaseRestore()
        await bootstrap.value

        XCTAssertEqual(store.state, .signedIn(newer.session))
        XCTAssertEqual(store.profile, newer.profile)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.statusMessage, "Signed in.")
    }

    func testOlderCompletionCannotClearNewerSignOutBusyState() async {
        let service = OfflineRestoreAccountService()
        service.holdsRestore = true
        let store = makeStore(service)
        let restoring = expectation(description: "Old restore held")
        service.onRestoreStarted = { restoring.fulfill() }
        let bootstrap = Task { await store.bootstrap() }
        await fulfillment(of: [restoring], timeout: 30)
        service.holdsSignOut = true
        let signingOut = expectation(description: "New sign-out held")
        service.onSignOutStarted = { signingOut.fulfill() }
        let signOut = Task { await store.signOut() }
        await fulfillment(of: [signingOut], timeout: 30)

        service.releaseRestore()
        await bootstrap.value

        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.profile)
        service.releaseSignOut()
        await signOut.value
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.statusMessage, "Signed out.")
    }

    func testReturningToSignInInvalidatesAnOlderProfileLoad() async {
        let service = OfflineRestoreAccountService()
        service.heldProfileIDs.insert(service.session.id)
        let store = makeStore(service)
        let started = expectation(description: "Profile request held before returning to sign-in")
        service.onProfileStarted = { _ in started.fulfill() }
        let bootstrap = Task { await store.bootstrap() }
        await fulfillment(of: [started], timeout: 30)

        store.returnToSignIn()
        service.releaseProfile(service.session.id)
        await bootstrap.value

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.profile)
        XCTAssertNil(store.statusMessage)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isWorking)
    }

    func testOlderProfileEditCannotReplaceNewAccountProfile() async {
        let service = OfflineRestoreAccountService()
        service.profileResult = .success(service.completeProfile)
        let store = makeStore(service)
        await store.bootstrap()
        service.holdsProfileCompletion = true
        let started = expectation(description: "Old account profile edit held")
        service.onProfileCompletionStarted = { started.fulfill() }
        let profileEdit = Task { await store.completeProfileIdentity(firstName: "Updated", lastName: "Fixture") }
        await fulfillment(of: [started], timeout: 30)
        let newer = configureNewAccount(on: service)

        await store.signIn(email: "newer@example.invalid", password: "fixture-password")
        service.releaseProfileCompletion()
        await profileEdit.value

        XCTAssertEqual(store.state, .signedIn(newer.session))
        XCTAssertEqual(store.profile, newer.profile)
        XCTAssertEqual(store.statusMessage, "Signed in.")
    }

    private func configureNewAccount(on service: OfflineRestoreAccountService) -> (session: IChartAccountSession, profile: IChartUserProfile) {
        let session = IChartAccountSession(id: UUID(), email: "newer@example.invalid", phone: nil, isEmailVerified: true)
        let profile = IChartUserProfile(id: session.id, email: session.email, firstName: "New", lastName: "Fixture")
        service.signInResult = .signedIn(session)
        service.profileResults[session.id] = .success(profile)
        return (session, profile)
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
    var signInResult: IChartAuthState?
    var profileResults: [UUID: Result<IChartUserProfile?, Error>] = [:]
    var holdsRestore = false
    var holdsSignOut = false
    var holdsProfileCompletion = false
    var heldProfileIDs = Set<UUID>()
    var onRestoreStarted: (() -> Void)?
    var onSignOutStarted: (() -> Void)?
    var onProfileStarted: ((UUID) -> Void)?
    var onProfileCompletionStarted: (() -> Void)?
    private var restoreContinuation: CheckedContinuation<Void, Never>?
    private var signOutContinuation: CheckedContinuation<Void, Never>?
    private var profileCompletionContinuation: CheckedContinuation<Void, Never>?
    private var profileContinuations = [UUID: CheckedContinuation<Void, Never>]()

    var completeProfile: IChartUserProfile {
        IChartUserProfile(id: session.id, email: session.email, firstName: "Test", lastName: "Musician")
    }

    func restoreSession() async throws -> IChartAuthState {
        restoreCalls += 1
        let result = restoreResult ?? .success(.signedIn(session))
        onRestoreStarted?()
        if holdsRestore { await withCheckedContinuation { restoreContinuation = $0 } }
        return try result.get()
    }
    func loadProfile(for userID: UUID) async throws -> IChartUserProfile? {
        profileRequests.append(userID)
        let result = profileResults[userID] ?? profileResult
        onProfileStarted?(userID)
        if heldProfileIDs.contains(userID) { await withCheckedContinuation { profileContinuations[userID] = $0 } }
        return try result.get()
    }
    func signUp(email: String, password: String, firstName: String?, lastName: String?, redirectURL: URL) async throws -> IChartAuthState {
        .signedIn(session)
    }
    func signIn(email: String, password: String) async throws -> IChartAuthState { signInResult ?? .signedIn(session) }
    func signOut() async throws {
        signOutCalls += 1
        onSignOutStarted?()
        if holdsSignOut { await withCheckedContinuation { signOutContinuation = $0 } }
    }
    func deleteAccount() async throws { throw IChartAuthError.profileUnavailable }
    func resendVerificationEmail(email: String, redirectURL: URL) async throws {}
    func requestPasswordReset(email: String, redirectURL: URL) async throws {}
    func handleAuthCallback(url: URL) async throws -> IChartAuthState { .signedIn(session) }
    func updatePassword(_ password: String) async throws -> IChartAuthState { .signedIn(session) }
    func completeProfileIdentity(for userID: UUID, firstName: String, lastName: String) async throws -> IChartUserProfile {
        let result = completeProfile
        onProfileCompletionStarted?()
        if holdsProfileCompletion { await withCheckedContinuation { profileCompletionContinuation = $0 } }
        return result
    }

    func releaseRestore() { holdsRestore = false; restoreContinuation?.resume(); restoreContinuation = nil }
    func releaseSignOut() { holdsSignOut = false; signOutContinuation?.resume(); signOutContinuation = nil }
    func releaseProfileCompletion() { holdsProfileCompletion = false; profileCompletionContinuation?.resume(); profileCompletionContinuation = nil }
    func releaseProfile(_ userID: UUID) { heldProfileIDs.remove(userID); profileContinuations.removeValue(forKey: userID)?.resume() }
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

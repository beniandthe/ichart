import Combine
import Foundation
import Supabase

struct IChartAccountSession: Equatable, Identifiable {
    let id: UUID
    let email: String?
    let phone: String?
    let isEmailVerified: Bool
}

enum IChartAuthState: Equatable {
    case unconfigured
    case signedOut
    case temporarilyOffline(IChartAccountSession)
    case pendingEmailVerification(email: String)
    case passwordRecovery(IChartAccountSession)
    case signedIn(IChartAccountSession)

    var statusText: String {
        switch self {
        case .unconfigured:
            return "Account services offline"
        case .signedOut:
            return "Signed out"
        case .temporarilyOffline:
            return "Temporarily offline"
        case .pendingEmailVerification:
            return "Verify email"
        case .passwordRecovery:
            return "Set new password"
        case .signedIn(let session):
            return session.isEmailVerified ? "Verified" : "Signed in"
        }
    }

    var signedInSession: IChartAccountSession? {
        guard case .signedIn(let session) = self else {
            return nil
        }

        return session
    }
}

struct IChartUserProfile: Codable, Equatable {
    let id: UUID
    var email: String?
    var phone: String?
    var mailingAddress: String?
    var paymentSummary: String?
    var stripeCustomerID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case phone
        case mailingAddress = "mailing_address"
        case paymentSummary = "payment_summary"
        case stripeCustomerID = "stripe_customer_id"
    }
}

private struct IChartUserProfileUpdate: Encodable {
    let id: UUID
    var email: String?
    var phone: String?
    var mailingAddress: String?
    var paymentSummary: String?

    init(profile: IChartUserProfile) {
        id = profile.id
        email = profile.email
        phone = profile.phone
        mailingAddress = profile.mailingAddress
        paymentSummary = profile.paymentSummary
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case phone
        case mailingAddress = "mailing_address"
        case paymentSummary = "payment_summary"
    }
}

enum IChartAuthError: LocalizedError {
    case invalidAuthCallback

    var errorDescription: String? {
        switch self {
        case .invalidAuthCallback:
            return "This sign-in link is not an iChart account callback."
        }
    }
}

private protocol IChartAccountServicing {
    var isConfigured: Bool { get }
    func restoreSession() async throws -> IChartAuthState
    func signUp(email: String, password: String) async throws -> IChartAuthState
    func signIn(email: String, password: String) async throws -> IChartAuthState
    func signOut() async throws
    func resendVerificationEmail(email: String) async throws
    func requestPasswordReset(email: String) async throws
    func handleAuthCallback(url: URL) async throws -> IChartAuthState
    func updatePassword(_ password: String) async throws -> IChartAuthState
    func loadProfile(for userID: UUID) async throws -> IChartUserProfile?
    func saveProfile(_ profile: IChartUserProfile) async throws -> IChartUserProfile
}

@MainActor
final class IChartAuthStore: ObservableObject {
    @Published private(set) var state: IChartAuthState
    @Published private(set) var profile: IChartUserProfile?
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let service: IChartAccountServicing
    private var hasBootstrapped = false
    private static let pendingVerificationEmailKey = "iChartPendingVerificationEmail"

    private init(service: IChartAccountServicing) {
        self.service = service
        state = service.isConfigured ? .signedOut : .unconfigured
    }

    static func live(clients: IChartSupabaseClients?) -> IChartAuthStore {
        guard let clients else {
            return IChartAuthStore(service: IChartUnconfiguredAccountService())
        }

        return IChartAuthStore(
            service: IChartSupabaseAccountService(
                authClient: clients.authClient,
                dataClient: clients.dataClient,
                sessionStore: clients.sessionStore
            )
        )
    }

    func bootstrap() async {
        guard !hasBootstrapped else {
            return
        }

        hasBootstrapped = true
        await refreshSession()
    }

    func refreshSession() async {
        await run("Account session refreshed.") {
            var restoredState = try await service.restoreSession()
            if case .signedOut = restoredState,
               let email = rememberedPendingVerificationEmail {
                restoredState = .pendingEmailVerification(email: email)
            }
            try await applyAuthState(restoredState)
        }
    }

    func createAccount(email: String, password: String) async {
        await run("Account created. Check your email to finish verification.") {
            let nextState = try await service.signUp(email: email, password: password)
            try await applyAuthState(nextState)
        }
    }

    func signIn(email: String, password: String) async {
        await run("Signed in.") {
            let nextState = try await service.signIn(email: email, password: password)
            try await applyAuthState(nextState)
        }
    }

    func signOut() async {
        await run("Signed out.") {
            try await service.signOut()
            state = service.isConfigured ? .signedOut : .unconfigured
            profile = nil
            rememberPendingVerificationEmailIfNeeded()
        }
    }

    func returnToSignIn() {
        guard service.isConfigured else {
            state = .unconfigured
            return
        }

        state = .signedOut
        profile = nil
        statusMessage = nil
        errorMessage = nil
        rememberPendingVerificationEmailIfNeeded()
    }

    func resendVerificationEmail() async {
        guard case .pendingEmailVerification(let email) = state else {
            return
        }

        await run("Verification email sent.") {
            try await service.resendVerificationEmail(email: email)
        }
    }

    func requestPasswordReset(email: String) async {
        await run("Password reset email sent.") {
            try await service.requestPasswordReset(email: email)
        }
    }

    func handleAuthCallback(url: URL) async {
        guard IChartSupabaseClientFactory.isAuthCallbackURL(url) else {
            return
        }

        await run("Account session refreshed.") {
            let nextState = try await service.handleAuthCallback(url: url)
            try await applyAuthState(nextState)
        }
    }

    func updatePassword(_ password: String) async {
        await run("Password updated. You're signed in.") {
            let nextState = try await service.updatePassword(password)
            try await applyAuthState(nextState)
        }
    }

    func dismissPasswordRecovery() async {
        guard case .passwordRecovery(let session) = state else {
            return
        }

        await run("Signed in.") {
            try await applyAuthState(.signedIn(session))
        }
    }

    func saveProfile(
        email: String,
        phone: String,
        mailingAddress: String,
        paymentSummary: String
    ) async {
        guard let session = state.signedInSession else {
            errorMessage = "Sign in before saving profile info."
            return
        }

        let profile = IChartUserProfile(
            id: session.id,
            email: sanitized(email) ?? session.email,
            phone: sanitized(phone) ?? session.phone,
            mailingAddress: sanitized(mailingAddress),
            paymentSummary: sanitized(paymentSummary),
            stripeCustomerID: self.profile?.stripeCustomerID
        )

        await run("Profile saved.") {
            self.profile = try await service.saveProfile(profile)
        }
    }

    private func applyAuthState(_ nextState: IChartAuthState) async throws {
        let nextProfile = try await loadedProfile(for: nextState)
        state = nextState
        profile = nextProfile
        rememberPendingVerificationEmailIfNeeded()
    }

    private func loadedProfile(for authState: IChartAuthState) async throws -> IChartUserProfile? {
        guard case .signedIn(let session) = authState else {
            return nil
        }

        return try await service.loadProfile(for: session.id)
    }

    private func run(_ successMessage: String, operation: () async throws -> Void) async {
        guard service.isConfigured else {
            state = .unconfigured
            statusMessage = nil
            errorMessage = nil
            return
        }

        isWorking = true
        errorMessage = nil
        statusMessage = nil

        do {
            try await operation()
            if case .temporarilyOffline = state {
                statusMessage = "Account is offline. Local charts remain available."
            } else if case .passwordRecovery = state {
                statusMessage = "Enter a new password to finish reset."
            } else {
                statusMessage = successMessage
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isWorking = false
    }

    private func sanitized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var rememberedPendingVerificationEmail: String? {
        let email = UserDefaults.standard.string(forKey: Self.pendingVerificationEmailKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? nil : email
    }

    private func rememberPendingVerificationEmailIfNeeded() {
        if case .pendingEmailVerification(let email) = state {
            UserDefaults.standard.set(email, forKey: Self.pendingVerificationEmailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingVerificationEmailKey)
        }
    }
}

private struct IChartUnconfiguredAccountService: IChartAccountServicing {
    let isConfigured = false

    func restoreSession() async throws -> IChartAuthState {
        .unconfigured
    }

    func signUp(email: String, password: String) async throws -> IChartAuthState {
        .unconfigured
    }

    func signIn(email: String, password: String) async throws -> IChartAuthState {
        .unconfigured
    }

    func signOut() async throws {}

    func resendVerificationEmail(email: String) async throws {}

    func requestPasswordReset(email: String) async throws {}

    func handleAuthCallback(url: URL) async throws -> IChartAuthState {
        .unconfigured
    }

    func updatePassword(_ password: String) async throws -> IChartAuthState {
        .unconfigured
    }

    func loadProfile(for userID: UUID) async throws -> IChartUserProfile? {
        nil
    }

    func saveProfile(_ profile: IChartUserProfile) async throws -> IChartUserProfile {
        profile
    }
}

private struct IChartSupabaseAccountService: IChartAccountServicing {
    let isConfigured = true
    private let authClient: SupabaseClient
    private let dataClient: SupabaseClient
    private let sessionStore: IChartSupabaseSessionStore
    private let persistentSessionStore: IChartSupabasePersistentSessionStore

    init(
        authClient: SupabaseClient,
        dataClient: SupabaseClient,
        sessionStore: IChartSupabaseSessionStore,
        persistentSessionStore: IChartSupabasePersistentSessionStore = IChartSupabasePersistentSessionStore()
    ) {
        self.authClient = authClient
        self.dataClient = dataClient
        self.sessionStore = sessionStore
        self.persistentSessionStore = persistentSessionStore
    }

    func restoreSession() async throws -> IChartAuthState {
        do {
            let session = try await authClient.auth.session
            return try await restoreState(from: session)
        } catch {
            return try await restoreStoredSession()
        }
    }

    func signUp(email: String, password: String) async throws -> IChartAuthState {
        let response = try await authClient.auth.signUp(
            email: normalized(email),
            password: password,
            redirectTo: IChartSupabaseClientFactory.authCallbackURL
        )

        if let session = response.session {
            try await persistSession(session)
            return state(for: session.user)
        }

        let user = response.user
        if user.emailConfirmedAt == nil {
            return .pendingEmailVerification(email: user.email ?? normalized(email))
        }

        let session = try await authClient.auth.signIn(
            email: normalized(email),
            password: password
        )
        try await persistSession(session)
        return state(for: session.user)
    }

    func signIn(email: String, password: String) async throws -> IChartAuthState {
        let session = try await authClient.auth.signIn(
            email: normalized(email),
            password: password
        )

        try await persistSession(session)
        return state(for: session.user)
    }

    func signOut() async throws {
        try await authClient.auth.signOut()
        try? persistentSessionStore.clear()
        await sessionStore.clear()
    }

    func resendVerificationEmail(email: String) async throws {
        try await authClient.auth.resend(
            email: normalized(email),
            type: .signup,
            emailRedirectTo: IChartSupabaseClientFactory.authCallbackURL
        )
    }

    func requestPasswordReset(email: String) async throws {
        try await authClient.auth.resetPasswordForEmail(
            normalized(email),
            redirectTo: IChartSupabaseClientFactory.authCallbackURL
        )
    }

    func handleAuthCallback(url: URL) async throws -> IChartAuthState {
        guard IChartSupabaseClientFactory.isAuthCallbackURL(url) else {
            throw IChartAuthError.invalidAuthCallback
        }

        let callbackType = callbackType(from: url)
        if let tokenHashCallback = tokenHashCallback(from: url) {
            let response = try await authClient.auth.verifyOTP(
                tokenHash: tokenHashCallback.tokenHash,
                type: tokenHashCallback.type
            )

            guard let session = response.session else { return .signedOut }

            try await persistSession(session)
            return authState(for: session.user, callbackType: callbackType)
        }

        let session = try await authClient.auth.session(from: url)
        try await persistSession(session)
        return authState(for: session.user, callbackType: callbackType)
    }

    func updatePassword(_ password: String) async throws -> IChartAuthState {
        let updatedUser = try await authClient.auth.update(user: UserAttributes(password: password))
        let session = try await authClient.auth.session
        try await persistSession(session)
        return state(for: updatedUser)
    }

    func loadProfile(for userID: UUID) async throws -> IChartUserProfile? {
        let profiles: [IChartUserProfile] = try await dataClient
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .execute()
            .value

        return profiles.first
    }

    func saveProfile(_ profile: IChartUserProfile) async throws -> IChartUserProfile {
        let update = IChartUserProfileUpdate(profile: profile)
        let profiles: [IChartUserProfile] = try await dataClient
            .from("profiles")
            .upsert(update, onConflict: "id")
            .select()
            .execute()
            .value

        return profiles.first ?? profile
    }

    private func accountSession(for user: User) -> IChartAccountSession {
        IChartAccountSession(
            id: user.id,
            email: user.email,
            phone: user.phone,
            isEmailVerified: user.emailConfirmedAt != nil || user.confirmedAt != nil
        )
    }

    private func state(for user: User) -> IChartAuthState {
        .signedIn(accountSession(for: user))
    }

    private func authState(for user: User, callbackType: String?) -> IChartAuthState {
        if callbackType == "recovery" {
            return .passwordRecovery(accountSession(for: user))
        }

        return state(for: user)
    }

    private func persistSession(_ session: Session) async throws {
        let persistedSession = try await authClient.auth.setSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken
        )
        try persistentSessionStore.store(persistedSession)
        await sessionStore.update(persistedSession)
    }

    private func restoreState(from session: Session) async throws -> IChartAuthState {
        try persistentSessionStore.store(session)
        await sessionStore.update(session)
        return state(for: session.user)
    }

    private func restoreStoredSession() async throws -> IChartAuthState {
        let storedSession: Session?
        do {
            storedSession = try persistentSessionStore.load()
        } catch {
            try? persistentSessionStore.clear()
            await sessionStore.clear()
            return .signedOut
        }

        guard let session = storedSession else {
            await sessionStore.clear()
            return .signedOut
        }

        do {
            let restoredSession = try await authClient.auth.setSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
            return try await restoreState(from: restoredSession)
        } catch {
            if Self.isConnectivityError(error) {
                await sessionStore.update(session)
                return .temporarilyOffline(accountSession(for: session.user))
            }

            try? persistentSessionStore.clear()
            await sessionStore.clear()
            return .signedOut
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isConnectivityError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [
                .notConnectedToInternet,
                .networkConnectionLost,
                .cannotFindHost,
                .cannotConnectToHost,
                .timedOut
            ].contains(urlError.code)
        }

        let text = error.localizedDescription.lowercased()
        return text.contains("not connected")
            || text.contains("network connection")
            || text.contains("cannot find host")
            || text.contains("cannot connect")
            || text.contains("could not connect")
            || text.contains("timed out")
    }

    private func tokenHashCallback(from url: URL) -> (tokenHash: String, type: EmailOTPType)? {
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let tokenHash = queryItems.first(where: { $0.name == "token_hash" })?.value,
              !tokenHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let rawType = queryItems.first(where: { $0.name == "type" })?.value
        return (tokenHash, emailOTPType(from: rawType) ?? .email)
    }

    private func callbackType(from url: URL) -> String? {
        if let queryType = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "type" })?
            .value {
            return normalized(queryType)
        }

        guard let fragment = url.fragment,
              let fragmentItems = URLComponents(string: "https://ichart.local/callback?\(fragment)")?.queryItems,
              let fragmentType = fragmentItems.first(where: { $0.name == "type" })?.value
        else {
            return nil
        }

        return normalized(fragmentType)
    }

    private func emailOTPType(from value: String?) -> EmailOTPType? {
        switch normalized(value ?? "") {
        case "signup":
            return .signup
        case "invite":
            return .invite
        case "magiclink":
            return .magiclink
        case "recovery":
            return .recovery
        case "email_change":
            return .emailChange
        case "email":
            return .email
        default:
            return nil
        }
    }
}

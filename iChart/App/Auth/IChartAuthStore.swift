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
            return "Account unavailable"
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
    var firstName: String?
    var lastName: String?
    var paymentSummary: String?
    var stripeCustomerID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case phone
        case firstName = "first_name"
        case lastName = "last_name"
        case paymentSummary = "payment_summary"
        case stripeCustomerID = "stripe_customer_id"
    }
}

private struct IChartUserProfileUpdate: Encodable {
    let id: UUID
    var email: String?
    var phone: String?
    var paymentSummary: String?

    init(profile: IChartUserProfile) {
        id = profile.id
        email = profile.email
        phone = profile.phone
        paymentSummary = profile.paymentSummary
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case phone
        case paymentSummary = "payment_summary"
    }
}

enum IChartAuthError: LocalizedError {
    case invalidAuthCallback
    case unexpectedAuthCallback
    case expiredAuthCallback

    var errorDescription: String? {
        switch self {
        case .invalidAuthCallback:
            return "This sign-in link is not an iChart account callback."
        case .unexpectedAuthCallback:
            return "Open the latest iChart account email from this device."
        case .expiredAuthCallback:
            return "This account link expired. Request a new email from iChart."
        }
    }
}

private enum IChartPendingAuthFlowKind: String, Codable {
    case signup
    case recovery
}

private struct IChartPendingAuthFlow: Codable {
    let kind: IChartPendingAuthFlowKind
    let expectedEmail: String?
    let nonce: UUID
    let createdAt: Date

    func replacingExpectedEmail(_ email: String) -> IChartPendingAuthFlow {
        IChartPendingAuthFlow(
            kind: kind,
            expectedEmail: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            nonce: nonce,
            createdAt: createdAt
        )
    }
}

private protocol IChartAccountServicing {
    var isConfigured: Bool { get }
    func restoreSession() async throws -> IChartAuthState
    func signUp(
        email: String,
        password: String,
        firstName: String?,
        lastName: String?,
        phone: String?,
        redirectURL: URL
    ) async throws -> IChartAuthState
    func signIn(email: String, password: String) async throws -> IChartAuthState
    func signOut() async throws
    func resendVerificationEmail(email: String, redirectURL: URL) async throws
    func requestPasswordReset(email: String, redirectURL: URL) async throws
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
    private let pendingVerificationEmailStorage: any AuthLocalStorage
    private var hasBootstrapped = false
    private static let pendingVerificationEmailKey = "iChart.pending-verification-email.v1"
    private static let pendingAuthFlowKey = "iChart.pending-auth-flow.v1"
    private static let legacyPendingVerificationEmailKey = "iChartPendingVerificationEmail"
    private static let pendingAuthFlowLifetime: TimeInterval = 60 * 60

    private init(
        service: IChartAccountServicing,
        pendingVerificationEmailStorage: any AuthLocalStorage = IChartSupabaseAuthLocalStorage(
            allowsInsecureFallback: false
        )
    ) {
        self.service = service
        self.pendingVerificationEmailStorage = pendingVerificationEmailStorage
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
        await restoreSession(successMessage: nil)
    }

    func refreshSession() async {
        await restoreSession(successMessage: "Account session refreshed.")
    }

    private func restoreSession(successMessage: String?) async {
        await run(successMessage) {
            var restoredState = try await service.restoreSession()
            if case .signedOut = restoredState,
               let email = rememberedPendingVerificationEmail {
                restoredState = .pendingEmailVerification(email: email)
            }
            try await applyAuthState(restoredState)
        }
    }

    func createAccount(
        email: String,
        password: String,
        firstName: String? = nil,
        lastName: String? = nil,
        phone: String? = nil
    ) async {
        await run("Account created. Check your email to finish verification.") {
            let pendingFlow = try storePendingAuthFlow(kind: .signup, expectedEmail: email)
            let nextState: IChartAuthState
            do {
                nextState = try await service.signUp(
                    email: email,
                    password: password,
                    firstName: sanitized(firstName ?? ""),
                    lastName: sanitized(lastName ?? ""),
                    phone: sanitized(phone ?? ""),
                    redirectURL: IChartSupabaseClientFactory.authCallbackURL(flowNonce: pendingFlow.nonce)
                )
            } catch {
                clearPendingAuthFlow()
                throw error
            }
            try await applyAuthState(nextState)
            if case .pendingEmailVerification(let pendingEmail) = nextState {
                try storePendingAuthFlow(pendingFlow.replacingExpectedEmail(pendingEmail))
            } else {
                clearPendingAuthFlow()
            }
        }
    }

    func signIn(email: String, password: String) async {
        await run("Signed in.") {
            let nextState = try await service.signIn(email: email, password: password)
            try await applyAuthState(nextState)
            clearPendingAuthFlow()
        }
    }

    func signOut() async {
        await run("Signed out.") {
            try await service.signOut()
            state = service.isConfigured ? .signedOut : .unconfigured
            profile = nil
            clearPendingAuthFlow()
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
            let pendingFlow = try storePendingAuthFlow(kind: .signup, expectedEmail: email)
            do {
                try await service.resendVerificationEmail(
                    email: email,
                    redirectURL: IChartSupabaseClientFactory.authCallbackURL(flowNonce: pendingFlow.nonce)
                )
            } catch {
                clearPendingAuthFlow()
                throw error
            }
        }
    }

    func requestPasswordReset(email: String) async {
        await run("Password reset email sent.") {
            let pendingFlow = try storePendingAuthFlow(kind: .recovery, expectedEmail: email)
            do {
                try await service.requestPasswordReset(
                    email: email,
                    redirectURL: IChartSupabaseClientFactory.authCallbackURL(flowNonce: pendingFlow.nonce)
                )
            } catch {
                clearPendingAuthFlow()
                throw error
            }
        }
    }

    func handleAuthCallback(url: URL) async {
        guard IChartSupabaseClientFactory.isAuthCallbackURL(url) else {
            return
        }

        await run("Account session refreshed.") {
            try validatePendingAuthFlow(for: url)
            let nextState = try await service.handleAuthCallback(url: url)
            try await applyAuthState(nextState)
            clearPendingAuthFlow()
        }
    }

    func updatePassword(_ password: String) async {
        await run("Password updated. You're signed in.") {
            let nextState = try await service.updatePassword(password)
            try await applyAuthState(nextState)
            clearPendingAuthFlow()
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
        phone: String
    ) async {
        guard let session = state.signedInSession else {
            errorMessage = "Sign in before saving profile info."
            return
        }

        let profile = IChartUserProfile(
            id: session.id,
            email: sanitized(email) ?? session.email,
            phone: sanitized(phone) ?? session.phone,
            firstName: self.profile?.firstName,
            lastName: self.profile?.lastName,
            paymentSummary: self.profile?.paymentSummary,
            stripeCustomerID: self.profile?.stripeCustomerID
        )

        await run("Profile updated.") {
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

    private func run(_ successMessage: String?, operation: () async throws -> Void) async {
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
            } else if let successMessage {
                statusMessage = successMessage
            } else {
                statusMessage = nil
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
        if let storedEmail = try? pendingVerificationEmailStorage.retrieve(key: Self.pendingVerificationEmailKey),
           let email = String(data: storedEmail, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }

        guard let legacyEmail = UserDefaults.standard.string(forKey: Self.legacyPendingVerificationEmailKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyEmail.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.legacyPendingVerificationEmailKey)
            return nil
        }

        try? pendingVerificationEmailStorage.store(
            key: Self.pendingVerificationEmailKey,
            value: Data(legacyEmail.utf8)
        )
        UserDefaults.standard.removeObject(forKey: Self.legacyPendingVerificationEmailKey)
        return legacyEmail
    }

    private func rememberPendingVerificationEmailIfNeeded() {
        if case .pendingEmailVerification(let email) = state {
            try? pendingVerificationEmailStorage.store(
                key: Self.pendingVerificationEmailKey,
                value: Data(email.utf8)
            )
            UserDefaults.standard.removeObject(forKey: Self.legacyPendingVerificationEmailKey)
        } else {
            try? pendingVerificationEmailStorage.remove(key: Self.pendingVerificationEmailKey)
            UserDefaults.standard.removeObject(forKey: Self.legacyPendingVerificationEmailKey)
        }
    }

    @discardableResult
    private func storePendingAuthFlow(
        kind: IChartPendingAuthFlowKind,
        expectedEmail: String?
    ) throws -> IChartPendingAuthFlow {
        let flow = IChartPendingAuthFlow(
            kind: kind,
            expectedEmail: sanitized(expectedEmail ?? "")?.lowercased(),
            nonce: UUID(),
            createdAt: Date()
        )
        try storePendingAuthFlow(flow)
        return flow
    }

    private func storePendingAuthFlow(_ flow: IChartPendingAuthFlow) throws {
        try pendingVerificationEmailStorage.store(
            key: Self.pendingAuthFlowKey,
            value: JSONEncoder().encode(flow)
        )
    }

    private func clearPendingAuthFlow() {
        try? pendingVerificationEmailStorage.remove(key: Self.pendingAuthFlowKey)
    }

    private func validatePendingAuthFlow(for url: URL) throws {
        guard let flow = try loadedPendingAuthFlow() else {
            throw IChartAuthError.unexpectedAuthCallback
        }

        guard Date().timeIntervalSince(flow.createdAt) <= Self.pendingAuthFlowLifetime else {
            clearPendingAuthFlow()
            throw IChartAuthError.expiredAuthCallback
        }

        guard callbackFlowNonce(from: url) == flow.nonce else {
            clearPendingAuthFlow()
            throw IChartAuthError.unexpectedAuthCallback
        }

        guard pendingAuthFlowKind(from: url) == flow.kind else {
            clearPendingAuthFlow()
            throw IChartAuthError.unexpectedAuthCallback
        }

        if let expectedEmail = flow.expectedEmail,
           let callbackEmail = callbackEmail(from: url),
           callbackEmail.caseInsensitiveCompare(expectedEmail) != .orderedSame {
            clearPendingAuthFlow()
            throw IChartAuthError.unexpectedAuthCallback
        }
    }

    private func loadedPendingAuthFlow() throws -> IChartPendingAuthFlow? {
        guard let data = try pendingVerificationEmailStorage.retrieve(key: Self.pendingAuthFlowKey) else {
            return nil
        }

        return try JSONDecoder().decode(IChartPendingAuthFlow.self, from: data)
    }

    private func pendingAuthFlowKind(from url: URL) -> IChartPendingAuthFlowKind? {
        switch callbackType(from: url) {
        case "signup", "email":
            return .signup
        case "recovery":
            return .recovery
        default:
            return nil
        }
    }

    private func callbackType(from url: URL) -> String? {
        if let queryType = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "type" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !queryType.isEmpty {
            return queryType
        }

        guard let fragment = url.fragment,
              let fragmentItems = URLComponents(string: "https://ichart.local/callback?\(fragment)")?.queryItems,
              let fragmentType = fragmentItems.first(where: { $0.name == "type" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !fragmentType.isEmpty
        else {
            return nil
        }

        return fragmentType
    }

    private func callbackEmail(from url: URL) -> String? {
        let queryEmail = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "email" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let queryEmail, !queryEmail.isEmpty {
            return queryEmail
        }

        guard let fragment = url.fragment,
              let fragmentItems = URLComponents(string: "https://ichart.local/callback?\(fragment)")?.queryItems,
              let fragmentEmail = fragmentItems.first(where: { $0.name == "email" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !fragmentEmail.isEmpty
        else {
            return nil
        }

        return fragmentEmail
    }

    private func callbackFlowNonce(from url: URL) -> UUID? {
        if let queryNonce = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "flow_nonce" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let nonce = UUID(uuidString: queryNonce) {
            return nonce
        }

        guard let fragment = url.fragment,
              let fragmentItems = URLComponents(string: "https://ichart.local/callback?\(fragment)")?.queryItems,
              let fragmentNonce = fragmentItems.first(where: { $0.name == "flow_nonce" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }

        return UUID(uuidString: fragmentNonce)
    }
}

private struct IChartUnconfiguredAccountService: IChartAccountServicing {
    let isConfigured = false

    func restoreSession() async throws -> IChartAuthState {
        .unconfigured
    }

    func signUp(
        email: String,
        password: String,
        firstName: String?,
        lastName: String?,
        phone: String?,
        redirectURL: URL
    ) async throws -> IChartAuthState {
        .unconfigured
    }

    func signIn(email: String, password: String) async throws -> IChartAuthState {
        .unconfigured
    }

    func signOut() async throws {}

    func resendVerificationEmail(email: String, redirectURL: URL) async throws {}

    func requestPasswordReset(email: String, redirectURL: URL) async throws {}

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

    func signUp(
        email: String,
        password: String,
        firstName: String?,
        lastName: String?,
        phone: String?,
        redirectURL: URL
    ) async throws -> IChartAuthState {
        let response = try await authClient.auth.signUp(
            email: normalized(email),
            password: password,
            data: signupMetadata(firstName: firstName, lastName: lastName, phone: phone),
            redirectTo: redirectURL
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

    func resendVerificationEmail(email: String, redirectURL: URL) async throws {
        try await authClient.auth.resend(
            email: normalized(email),
            type: .signup,
            emailRedirectTo: redirectURL
        )
    }

    func requestPasswordReset(email: String, redirectURL: URL) async throws {
        try await authClient.auth.resetPasswordForEmail(
            normalized(email),
            redirectTo: redirectURL
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

    private func signupMetadata(firstName: String?, lastName: String?, phone: String?) -> [String: AnyJSON] {
        var metadata: [String: AnyJSON] = [:]

        if let firstName = firstName.map(normalized), !firstName.isEmpty {
            metadata["first_name"] = .string(firstName)
        }

        if let lastName = lastName.map(normalized), !lastName.isEmpty {
            metadata["last_name"] = .string(lastName)
        }

        if let phone = phone.map(normalized), !phone.isEmpty {
            metadata["phone"] = .string(phone)
        }

        return metadata
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
              let tokenHash = tokenHashValue(from: queryItems),
              !tokenHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let rawType = queryItems.first(where: { $0.name == "type" })?.value
        return (tokenHash, emailOTPType(from: rawType) ?? .email)
    }

    private func tokenHashValue(from queryItems: [URLQueryItem]) -> String? {
        queryItems.first(where: { $0.name == "token_hash" })?.value
            ?? queryItems.first(where: { $0.name == "token" })?.value
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

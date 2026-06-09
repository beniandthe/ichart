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
    case pendingEmailVerification(email: String)
    case signedIn(IChartAccountSession)

    var statusText: String {
        switch self {
        case .unconfigured:
            return "Account services offline"
        case .signedOut:
            return "Signed out"
        case .pendingEmailVerification:
            return "Verify email"
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

private protocol IChartAccountServicing {
    var isConfigured: Bool { get }
    func restoreSession() async throws -> IChartAuthState
    func signUp(email: String, password: String) async throws -> IChartAuthState
    func signIn(email: String, password: String) async throws -> IChartAuthState
    func signOut() async throws
    func resendVerificationEmail(email: String) async throws
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

    private init(service: IChartAccountServicing) {
        self.service = service
        state = service.isConfigured ? .signedOut : .unconfigured
    }

    static func live() -> IChartAuthStore {
        guard let configuration = IChartSupabaseConfiguration.current() else {
            return IChartAuthStore(service: IChartUnconfiguredAccountService())
        }

        return IChartAuthStore(service: IChartSupabaseAccountService(configuration: configuration))
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
            let restoredState = try await service.restoreSession()
            state = restoredState
            try await loadProfileIfSignedIn()
        }
    }

    func createAccount(email: String, password: String) async {
        await run("Account created. Check your email to finish verification.") {
            state = try await service.signUp(email: email, password: password)
            try await loadProfileIfSignedIn()
        }
    }

    func signIn(email: String, password: String) async {
        await run("Signed in.") {
            state = try await service.signIn(email: email, password: password)
            try await loadProfileIfSignedIn()
        }
    }

    func signOut() async {
        await run("Signed out.") {
            try await service.signOut()
            state = service.isConfigured ? .signedOut : .unconfigured
            profile = nil
        }
    }

    func resendVerificationEmail() async {
        guard case .pendingEmailVerification(let email) = state else {
            return
        }

        await run("Verification email sent.") {
            try await service.resendVerificationEmail(email: email)
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

    private func loadProfileIfSignedIn() async throws {
        guard let session = state.signedInSession else {
            profile = nil
            return
        }

        profile = try await service.loadProfile(for: session.id)
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
            statusMessage = successMessage
        } catch {
            errorMessage = error.localizedDescription
        }

        isWorking = false
    }

    private func sanitized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    func loadProfile(for userID: UUID) async throws -> IChartUserProfile? {
        nil
    }

    func saveProfile(_ profile: IChartUserProfile) async throws -> IChartUserProfile {
        profile
    }
}

private struct IChartSupabaseAccountService: IChartAccountServicing {
    let isConfigured = true
    private let client: SupabaseClient

    init(configuration: IChartSupabaseConfiguration) {
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
    }

    func restoreSession() async throws -> IChartAuthState {
        if let currentUser = client.auth.currentUser {
            return state(for: currentUser)
        }

        do {
            let session = try await client.auth.session
            return state(for: session.user)
        } catch {
            return .signedOut
        }
    }

    func signUp(email: String, password: String) async throws -> IChartAuthState {
        let response = try await client.auth.signUp(
            email: normalized(email),
            password: password
        )

        if let session = response.session {
            return state(for: session.user)
        }

        let user = response.user
        if user.emailConfirmedAt == nil {
            return .pendingEmailVerification(email: user.email ?? normalized(email))
        }

        return state(for: user)
    }

    func signIn(email: String, password: String) async throws -> IChartAuthState {
        let session = try await client.auth.signIn(
            email: normalized(email),
            password: password
        )

        return state(for: session.user)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func resendVerificationEmail(email: String) async throws {
        try await client.auth.resend(email: normalized(email), type: .signup)
    }

    func loadProfile(for userID: UUID) async throws -> IChartUserProfile? {
        let profiles: [IChartUserProfile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .execute()
            .value

        return profiles.first
    }

    func saveProfile(_ profile: IChartUserProfile) async throws -> IChartUserProfile {
        let profiles: [IChartUserProfile] = try await client
            .from("profiles")
            .upsert(profile, onConflict: "id")
            .select()
            .execute()
            .value

        return profiles.first ?? profile
    }

    private func state(for user: User) -> IChartAuthState {
        .signedIn(
            IChartAccountSession(
                id: user.id,
                email: user.email,
                phone: user.phone,
                isEmailVerified: user.emailConfirmedAt != nil || user.confirmedAt != nil
            )
        )
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

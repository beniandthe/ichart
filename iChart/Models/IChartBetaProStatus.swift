import Foundation

struct IChartBetaProStatus: Codable, Equatable, Sendable {
    let ownerID: UUID
    let policyID: String
    let betaAvailable: Bool
    let eligible: Bool
    let participating: Bool
    let freeProAccess: Bool
    var noticeID: String? = nil
    var noticeTitle: String? = nil
    var noticeBody: String? = nil
    var betaEndingAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case policyID = "policy_id"
        case betaAvailable = "beta_available"
        case eligible, participating
        case freeProAccess = "free_pro_access"
        case noticeID = "notice_id"
        case noticeTitle = "notice_title"
        case noticeBody = "notice_body"
        case betaEndingAt = "beta_ending_at"
    }

    var notice: IChartBetaProNotice? {
        guard let id = noticeID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              let title = noticeTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let body = noticeBody?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
        return IChartBetaProNotice(id: id, ownerID: ownerID, title: title, body: body, betaEndingAt: betaEndingAt)
    }

    var hasConsistentAccess: Bool {
        freeProAccess == (betaAvailable && eligible && participating)
    }
}

struct IChartBetaProNotice: Identifiable, Equatable, Sendable {
    let id: String
    let ownerID: UUID
    let title: String
    let body: String
    let betaEndingAt: String?
}

/// The expected owner is checked before sending a mutation, not only after it.
/// The server still derives the actual row owner from its authenticated session.
protocol IChartBetaProService {
    func fetchStatus(for ownerID: UUID) async throws -> IChartBetaProStatus
    func setParticipation(_ participating: Bool, for ownerID: UUID) async throws -> IChartBetaProStatus
}

enum IChartBetaProServiceError: Error {
    case accountChanged
    case inconsistentStatus
    case participationNotConfirmed
}

import Foundation

/// Release phase is server product policy, never proof of an Apple purchase.
enum IChartProductAccessPhase: Equatable, Hashable, Sendable {
    case freeBeta
    case paid
    case unsupported(String)

    init(rawValue: String) {
        switch rawValue {
        case "free_beta": self = .freeBeta
        case "paid": self = .paid
        default: self = .unsupported(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .freeBeta: return "free_beta"
        case .paid: return "paid"
        case .unsupported(let value): return value
        }
    }
}

struct IChartProductAccessStatus: Codable, Equatable, Sendable {
    static let expectedPolicyID = "ichart-product-access-v1"
    let schemaVersion: Int
    let ownerID: UUID
    let policyID: String
    let phase: IChartProductAccessPhase
    let policyRevision: Int64
    let serverNow: Date
    let policyUpdatedAt: Date
    let betaAvailable: Bool
    let eligible: Bool
    let participating: Bool
    let freeProAccess: Bool
    var noticeID: String? = nil
    var noticeTitle: String? = nil
    var noticeBody: String? = nil
    var betaEndingAt: String? = nil

    init(schemaVersion: Int = 1, ownerID: UUID, policyID: String,
         phase: IChartProductAccessPhase, policyRevision: Int64,
         serverNow: Date, policyUpdatedAt: Date,
         betaAvailable: Bool, eligible: Bool, participating: Bool, freeProAccess: Bool,
         noticeID: String? = nil, noticeTitle: String? = nil,
         noticeBody: String? = nil, betaEndingAt: String? = nil) {
        self.schemaVersion = schemaVersion
        self.ownerID = ownerID
        self.policyID = policyID
        self.phase = phase
        self.policyRevision = policyRevision
        self.serverNow = serverNow
        self.policyUpdatedAt = policyUpdatedAt
        self.betaAvailable = betaAvailable
        self.eligible = eligible
        self.participating = participating
        self.freeProAccess = freeProAccess
        self.noticeID = noticeID
        self.noticeTitle = noticeTitle
        self.noticeBody = noticeBody
        self.betaEndingAt = betaEndingAt
    }

    var betaStatus: IChartBetaProStatus {
        IChartBetaProStatus(ownerID: ownerID, policyID: policyID,
                           betaAvailable: betaAvailable, eligible: eligible,
                           participating: participating, freeProAccess: freeProAccess,
                           noticeID: noticeID, noticeTitle: noticeTitle,
                           noticeBody: noticeBody, betaEndingAt: betaEndingAt)
    }

    var isRecognizedAndConsistent: Bool {
        guard schemaVersion == 1, policyRevision >= 1,
              policyID == Self.expectedPolicyID,
              serverNow.timeIntervalSince1970.isFinite,
              policyUpdatedAt.timeIntervalSince1970.isFinite,
              policyUpdatedAt <= serverNow,
              betaStatus.hasConsistentAccess else { return false }
        switch phase {
        case .freeBeta: return betaAvailable
        case .paid: return !betaAvailable && !freeProAccess
        case .unsupported: return false
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", ownerID = "owner_id", policyID = "policy_id"
        case phase, policyRevision = "policy_revision", serverNow = "server_now", policyUpdatedAt = "policy_updated_at"
        case betaAvailable = "beta_available", eligible, participating, freeProAccess = "free_pro_access"
        case noticeID = "notice_id", noticeTitle = "notice_title", noticeBody = "notice_body", betaEndingAt = "beta_ending_at"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        ownerID = try values.decode(UUID.self, forKey: .ownerID)
        policyID = try values.decode(String.self, forKey: .policyID)
        phase = IChartProductAccessPhase(rawValue: try values.decode(String.self, forKey: .phase))
        policyRevision = try values.decode(Int64.self, forKey: .policyRevision)
        serverNow = try Self.decodeDate(values, key: .serverNow)
        policyUpdatedAt = try Self.decodeDate(values, key: .policyUpdatedAt)
        betaAvailable = try values.decode(Bool.self, forKey: .betaAvailable)
        eligible = try values.decode(Bool.self, forKey: .eligible)
        participating = try values.decode(Bool.self, forKey: .participating)
        freeProAccess = try values.decode(Bool.self, forKey: .freeProAccess)
        noticeID = try values.decodeIfPresent(String.self, forKey: .noticeID)
        noticeTitle = try values.decodeIfPresent(String.self, forKey: .noticeTitle)
        noticeBody = try values.decodeIfPresent(String.self, forKey: .noticeBody)
        betaEndingAt = try values.decodeIfPresent(String.self, forKey: .betaEndingAt)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(ownerID, forKey: .ownerID)
        try values.encode(policyID, forKey: .policyID)
        try values.encode(phase.rawValue, forKey: .phase)
        try values.encode(policyRevision, forKey: .policyRevision)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try values.encode(formatter.string(from: serverNow), forKey: .serverNow)
        try values.encode(formatter.string(from: policyUpdatedAt), forKey: .policyUpdatedAt)
        try values.encode(betaAvailable, forKey: .betaAvailable)
        try values.encode(eligible, forKey: .eligible)
        try values.encode(participating, forKey: .participating)
        try values.encode(freeProAccess, forKey: .freeProAccess)
        try values.encodeIfPresent(noticeID, forKey: .noticeID)
        try values.encodeIfPresent(noticeTitle, forKey: .noticeTitle)
        try values.encodeIfPresent(noticeBody, forKey: .noticeBody)
        try values.encodeIfPresent(betaEndingAt, forKey: .betaEndingAt)
    }

    private static func decodeDate(_ values: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date {
        let string = try values.decode(String.self, forKey: key)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Expected a finite ISO-8601 server timestamp.")
        }
        return date
    }
}

enum IChartProductAccessResolver {
    /// Runtime phase cannot apply another account's verified Apple history.
    /// The existing ownerless legacy-local right remains a device-local floor.
    static func billingForLibrary(subscription: IChartSubscriptionEntitlement,
                                  verifiedOwnerID: UUID?, currentOwnerID: UUID?,
                                  currentLibraryEntitlement: IChartSubscriptionEntitlement) -> IChartSubscriptionEntitlement {
        let ownerBound = currentOwnerID != nil && currentOwnerID == verifiedOwnerID
            ? subscription : (currentOwnerID == nil ? .basic : .unavailable)
        return ownerBound.resolvedForLibraryApplication(currentLibraryEntitlement: currentLibraryEntitlement)
    }

    static func resolve(status: IChartProductAccessStatus?, fallback: IChartProductAccessPolicy) -> IChartProductAccessPolicy {
        guard let status, status.isRecognizedAndConsistent else { return fallback }
        switch status.phase {
        case .freeBeta: return status.freeProAccess ? .freeAllFeatures : .betaBasic
        case .paid: return .paidSubscription
        case .unsupported: return fallback
        }
    }
}

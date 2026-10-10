import Foundation

enum RecognitionStudyConsentContractError: Error, Equatable {
    case fixedValueMismatch(field: String, expected: String, actual: String)
    case invalidIdentifier(field: String, value: String)
    case invalidHTTPSURL(String)
    case invalidStatus(String)
    case invalidTimestamp(field: String)
    case invalidLedgerEpoch
    case rawStrokeDonationNotAuthorized
    case consentStateMismatch
    case responseTooLarge(maximum: Int, actual: Int)
}

enum RecognitionStudyConsentStatus:
    String,
    Encodable,
    Equatable,
    Hashable,
    Sendable
{
    case notAccepted = "not-accepted"
    case active
    case withdrawn
}

struct RecognitionStudyConsentPolicy: Encodable, Equatable, Sendable {
    static let currentSchemaVersion =
        "recognition-study-consent-policy-v1"
    static let requiredScope = "chord-recognition-research-v1"

    let schemaVersion: RecognitionStudyPrintableASCII
    let presentationID: RecognitionStudyPrintableASCII
    let presentationSHA256: RecognitionStudySHA256
    let consentDocumentURL: String
    let consentLedgerVersion: RecognitionStudyPrintableASCII
    let consentTextVersion: RecognitionStudyPrintableASCII
    let privacyNoticeVersion: RecognitionStudyPrintableASCII
    let dataUsePolicyVersion: RecognitionStudyPrintableASCII
    let retentionPolicyVersion: RecognitionStudyPrintableASCII
    let scope: RecognitionStudyPrintableASCII
    let rawStrokeDonationRequired: Bool

    fileprivate init(wire: RecognitionStudyConsentWire.Policy) throws {
        schemaVersion = wire.schemaVersion
        presentationID = wire.presentationID
        presentationSHA256 = wire.presentationSHA256
        consentDocumentURL = wire.consentDocumentURL
        consentLedgerVersion = wire.consentLedgerVersion
        consentTextVersion = wire.consentTextVersion
        privacyNoticeVersion = wire.privacyNoticeVersion
        dataUsePolicyVersion = wire.dataUsePolicyVersion
        retentionPolicyVersion = wire.retentionPolicyVersion
        scope = wire.scope
        rawStrokeDonationRequired = wire.rawStrokeDonationRequired
        try validateContract()
    }

    func validateContract() throws {
        try requireConsentFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "currentPolicy.schemaVersion"
        )
        try requireConsentIdentifier(
            presentationID,
            field: "currentPolicy.presentationID"
        )
        for (value, field) in [
            (consentLedgerVersion, "currentPolicy.consentLedgerVersion"),
            (consentTextVersion, "currentPolicy.consentTextVersion"),
            (privacyNoticeVersion, "currentPolicy.privacyNoticeVersion"),
            (dataUsePolicyVersion, "currentPolicy.dataUsePolicyVersion"),
            (retentionPolicyVersion, "currentPolicy.retentionPolicyVersion")
        ] {
            try requireConsentIdentifier(value, field: field)
        }
        try requireConsentFixed(
            scope,
            expected: Self.requiredScope,
            field: "currentPolicy.scope"
        )
        guard rawStrokeDonationRequired else {
            throw RecognitionStudyConsentContractError
                .rawStrokeDonationNotAuthorized
        }
        try requireConsentHTTPSURL(consentDocumentURL)
    }
}

struct RecognitionStudyConsentRecordSummary:
    Encodable,
    Equatable,
    Sendable
{
    static let currentSchemaVersion =
        "recognition-study-consent-record-summary-v1"
    private static let maximumSafeJSONInteger: Int64 =
        9_007_199_254_740_991

    let schemaVersion: RecognitionStudyPrintableASCII
    let consentRecordID: RecognitionStudyCanonicalUUID
    let consentRecordSHA256: RecognitionStudySHA256
    let consentLedgerEpoch: UInt64
    let consentLedgerVersion: RecognitionStudyPrintableASCII
    let consentTextVersion: RecognitionStudyPrintableASCII
    let privacyNoticeVersion: RecognitionStudyPrintableASCII
    let dataUsePolicyVersion: RecognitionStudyPrintableASCII
    let retentionPolicyVersion: RecognitionStudyPrintableASCII
    let scope: RecognitionStudyPrintableASCII
    let rawStrokeDonationAuthorized: Bool
    let status: RecognitionStudyConsentStatus
    let acceptedAtUnixMilliseconds: Int64
    let withdrawnAtUnixMilliseconds: Int64?

    fileprivate init(
        wire: RecognitionStudyConsentWire.RecordSummary
    ) throws {
        schemaVersion = wire.schemaVersion
        consentRecordID = wire.consentRecordID
        consentRecordSHA256 = wire.consentRecordSHA256
        consentLedgerEpoch = wire.consentLedgerEpoch
        consentLedgerVersion = wire.consentLedgerVersion
        consentTextVersion = wire.consentTextVersion
        privacyNoticeVersion = wire.privacyNoticeVersion
        dataUsePolicyVersion = wire.dataUsePolicyVersion
        retentionPolicyVersion = wire.retentionPolicyVersion
        scope = wire.scope
        rawStrokeDonationAuthorized = wire.rawStrokeDonationAuthorized
        guard let decodedStatus = RecognitionStudyConsentStatus(
            rawValue: wire.status
        ), decodedStatus != .notAccepted else {
            throw RecognitionStudyConsentContractError
                .invalidStatus(wire.status)
        }
        status = decodedStatus
        acceptedAtUnixMilliseconds = wire.acceptedAtUnixMilliseconds
        withdrawnAtUnixMilliseconds = wire.withdrawnAtUnixMilliseconds
        try validateContract()
    }

    func validateContract() throws {
        try requireConsentFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "consent.schemaVersion"
        )
        guard consentLedgerEpoch > 0,
              consentLedgerEpoch <= UInt64(Self.maximumSafeJSONInteger) else {
            throw RecognitionStudyConsentContractError.invalidLedgerEpoch
        }
        for (value, field) in [
            (consentLedgerVersion, "consent.consentLedgerVersion"),
            (consentTextVersion, "consent.consentTextVersion"),
            (privacyNoticeVersion, "consent.privacyNoticeVersion"),
            (dataUsePolicyVersion, "consent.dataUsePolicyVersion"),
            (retentionPolicyVersion, "consent.retentionPolicyVersion")
        ] {
            try requireConsentIdentifier(value, field: field)
        }
        try requireConsentFixed(
            scope,
            expected: RecognitionStudyConsentPolicy.requiredScope,
            field: "consent.scope"
        )
        guard rawStrokeDonationAuthorized else {
            throw RecognitionStudyConsentContractError
                .rawStrokeDonationNotAuthorized
        }
        try requireConsentTimestamp(
            acceptedAtUnixMilliseconds,
            field: "consent.acceptedAtUnixMilliseconds"
        )
        switch status {
        case .active:
            guard withdrawnAtUnixMilliseconds == nil else {
                throw RecognitionStudyConsentContractError
                    .consentStateMismatch
            }
        case .withdrawn:
            guard let withdrawnAtUnixMilliseconds else {
                throw RecognitionStudyConsentContractError
                    .consentStateMismatch
            }
            try requireConsentTimestamp(
                withdrawnAtUnixMilliseconds,
                field: "consent.withdrawnAtUnixMilliseconds"
            )
            guard withdrawnAtUnixMilliseconds
                    >= acceptedAtUnixMilliseconds else {
                throw RecognitionStudyConsentContractError
                    .consentStateMismatch
            }
        case .notAccepted:
            throw RecognitionStudyConsentContractError
                .invalidStatus(status.rawValue)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case acceptedAtUnixMilliseconds
        case consentLedgerEpoch
        case consentLedgerVersion
        case consentRecordID
        case consentRecordSHA256
        case consentTextVersion
        case dataUsePolicyVersion
        case privacyNoticeVersion
        case rawStrokeDonationAuthorized
        case retentionPolicyVersion
        case schemaVersion
        case scope
        case status
        case withdrawnAtUnixMilliseconds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            acceptedAtUnixMilliseconds,
            forKey: .acceptedAtUnixMilliseconds
        )
        try container.encode(consentLedgerEpoch, forKey: .consentLedgerEpoch)
        try container.encode(consentLedgerVersion, forKey: .consentLedgerVersion)
        try container.encode(consentRecordID, forKey: .consentRecordID)
        try container.encode(consentRecordSHA256, forKey: .consentRecordSHA256)
        try container.encode(consentTextVersion, forKey: .consentTextVersion)
        try container.encode(dataUsePolicyVersion, forKey: .dataUsePolicyVersion)
        try container.encode(privacyNoticeVersion, forKey: .privacyNoticeVersion)
        try container.encode(
            rawStrokeDonationAuthorized,
            forKey: .rawStrokeDonationAuthorized
        )
        try container.encode(
            retentionPolicyVersion,
            forKey: .retentionPolicyVersion
        )
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(scope, forKey: .scope)
        try container.encode(status, forKey: .status)
        if let withdrawnAtUnixMilliseconds {
            try container.encode(
                withdrawnAtUnixMilliseconds,
                forKey: .withdrawnAtUnixMilliseconds
            )
        } else {
            try container.encodeNil(forKey: .withdrawnAtUnixMilliseconds)
        }
    }
}

struct RecognitionStudyConsentResponse:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let currentSchemaVersion =
        "recognition-study-consent-response-v1"
    static let maximumCanonicalJSONByteCount = 32 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let status: RecognitionStudyConsentStatus
    let replayed: Bool
    let currentPolicy: RecognitionStudyConsentPolicy?
    let consent: RecognitionStudyConsentRecordSummary?

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyConsentWire.Response.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(wire: RecognitionStudyConsentWire.Response) throws {
        schemaVersion = wire.schemaVersion
        guard let decodedStatus = RecognitionStudyConsentStatus(
            rawValue: wire.status
        ) else {
            throw RecognitionStudyConsentContractError
                .invalidStatus(wire.status)
        }
        status = decodedStatus
        replayed = wire.replayed
        currentPolicy = try wire.currentPolicy.map(
            RecognitionStudyConsentPolicy.init(wire:)
        )
        consent = try wire.consent.map(
            RecognitionStudyConsentRecordSummary.init(wire:)
        )
        try validateContract()
    }

    func validateContract() throws {
        try requireConsentFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "schemaVersion"
        )
        try currentPolicy?.validateContract()
        try consent?.validateContract()
        switch status {
        case .notAccepted:
            guard consent == nil else {
                throw RecognitionStudyConsentContractError
                    .consentStateMismatch
            }
        case .active, .withdrawn:
            guard consent?.status == status else {
                throw RecognitionStudyConsentContractError
                    .consentStateMismatch
            }
        }
    }

    func validateAcceptance(of policy: RecognitionStudyConsentPolicy) throws {
        try validateContract()
        try policy.validateContract()
        guard status == .active,
              let consent,
              currentPolicy == policy,
              consent.consentLedgerVersion == policy.consentLedgerVersion,
              consent.consentTextVersion == policy.consentTextVersion,
              consent.privacyNoticeVersion == policy.privacyNoticeVersion,
              consent.dataUsePolicyVersion == policy.dataUsePolicyVersion,
              consent.retentionPolicyVersion == policy.retentionPolicyVersion,
              consent.scope == policy.scope else {
            throw RecognitionStudyConsentContractError
                .consentStateMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case consent
        case currentPolicy
        case replayed
        case schemaVersion
        case status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let consent {
            try container.encode(consent, forKey: .consent)
        } else {
            try container.encodeNil(forKey: .consent)
        }
        if let currentPolicy {
            try container.encode(currentPolicy, forKey: .currentPolicy)
        } else {
            try container.encodeNil(forKey: .currentPolicy)
        }
        try container.encode(replayed, forKey: .replayed)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
    }
}

struct RecognitionStudyConsentStatusRequest: Encodable, Sendable {
    static let currentSchemaVersion =
        "recognition-study-consent-status-request-v1"
    static let maximumCanonicalJSONByteCount = 4 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII

    init() throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
    }

    func canonicalData() throws -> Data {
        try encodeConsentRequest(self)
    }
}

struct RecognitionStudyConsentAcceptRequest: Encodable, Sendable {
    static let currentSchemaVersion =
        "recognition-study-consent-accept-request-v1"
    static let maximumCanonicalJSONByteCount = 4 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let clientRequestID: RecognitionStudyCanonicalUUID
    let explicitRawStrokeDonationAuthorization: Bool
    let presentationID: RecognitionStudyPrintableASCII
    let presentationSHA256: RecognitionStudySHA256

    init(
        clientRequestID: UUID,
        policy: RecognitionStudyConsentPolicy
    ) throws {
        try policy.validateContract()
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        self.clientRequestID = RecognitionStudyCanonicalUUID(clientRequestID)
        explicitRawStrokeDonationAuthorization = true
        presentationID = policy.presentationID
        presentationSHA256 = policy.presentationSHA256
    }

    func canonicalData() throws -> Data {
        try encodeConsentRequest(self)
    }
}

struct RecognitionStudyConsentWithdrawRequest: Encodable, Sendable {
    static let currentSchemaVersion =
        "recognition-study-consent-withdraw-request-v1"
    static let maximumCanonicalJSONByteCount = 4 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let clientRequestID: RecognitionStudyCanonicalUUID
    let consentRecordID: RecognitionStudyCanonicalUUID

    init(clientRequestID: UUID, consentRecordID: UUID) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        self.clientRequestID = RecognitionStudyCanonicalUUID(clientRequestID)
        self.consentRecordID = RecognitionStudyCanonicalUUID(consentRecordID)
    }

    func canonicalData() throws -> Data {
        try encodeConsentRequest(self)
    }
}

fileprivate enum RecognitionStudyConsentWire {
    struct Policy: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let presentationID: RecognitionStudyPrintableASCII
        let presentationSHA256: RecognitionStudySHA256
        let consentDocumentURL: String
        let consentLedgerVersion: RecognitionStudyPrintableASCII
        let consentTextVersion: RecognitionStudyPrintableASCII
        let privacyNoticeVersion: RecognitionStudyPrintableASCII
        let dataUsePolicyVersion: RecognitionStudyPrintableASCII
        let retentionPolicyVersion: RecognitionStudyPrintableASCII
        let scope: RecognitionStudyPrintableASCII
        let rawStrokeDonationRequired: Bool
    }

    struct RecordSummary: Decodable {
        let acceptedAtUnixMilliseconds: Int64
        let consentLedgerEpoch: UInt64
        let consentLedgerVersion: RecognitionStudyPrintableASCII
        let consentRecordID: RecognitionStudyCanonicalUUID
        let consentRecordSHA256: RecognitionStudySHA256
        let consentTextVersion: RecognitionStudyPrintableASCII
        let dataUsePolicyVersion: RecognitionStudyPrintableASCII
        let privacyNoticeVersion: RecognitionStudyPrintableASCII
        let rawStrokeDonationAuthorized: Bool
        let retentionPolicyVersion: RecognitionStudyPrintableASCII
        let schemaVersion: RecognitionStudyPrintableASCII
        let scope: RecognitionStudyPrintableASCII
        let status: String
        let withdrawnAtUnixMilliseconds: Int64?
    }

    struct Response: Decodable {
        let consent: RecordSummary?
        let currentPolicy: Policy?
        let replayed: Bool
        let schemaVersion: RecognitionStudyPrintableASCII
        let status: String
    }
}

private func encodeConsentRequest<Value: Encodable>(
    _ value: Value
) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    guard data.count <= 4 * 1024 else {
        throw RecognitionStudyConsentContractError.responseTooLarge(
            maximum: 4 * 1024,
            actual: data.count
        )
    }
    return data
}

private func requireConsentFixed(
    _ value: RecognitionStudyPrintableASCII,
    expected: String,
    field: String
) throws {
    guard value.rawValue == expected else {
        throw RecognitionStudyConsentContractError.fixedValueMismatch(
            field: field,
            expected: expected,
            actual: value.rawValue
        )
    }
}

private func requireConsentIdentifier(
    _ value: RecognitionStudyPrintableASCII,
    field: String
) throws {
    let scalars = value.rawValue.unicodeScalars
    let startsCorrectly = scalars.first.map {
        (48...57).contains($0.value) || (97...122).contains($0.value)
    } ?? false
    let allAllowed = scalars.allSatisfy {
        (48...57).contains($0.value)
            || (97...122).contains($0.value)
            || $0.value == 45
            || $0.value == 46
            || $0.value == 95
    }
    guard startsCorrectly,
          allAllowed,
          value.rawValue.utf8.count <= 128 else {
        throw RecognitionStudyConsentContractError.invalidIdentifier(
            field: field,
            value: value.rawValue
        )
    }
}

private func requireConsentHTTPSURL(_ rawValue: String) throws {
    guard let components = URLComponents(string: rawValue),
          components.scheme?.lowercased() == "https",
          components.host?.isEmpty == false,
          components.user == nil,
          components.password == nil,
          components.fragment == nil,
          components.url?.absoluteString == rawValue else {
        throw RecognitionStudyConsentContractError.invalidHTTPSURL(rawValue)
    }
}

private func requireConsentTimestamp(
    _ value: Int64,
    field: String
) throws {
    guard value >= 0, value <= 9_007_199_254_740_991 else {
        throw RecognitionStudyConsentContractError.invalidTimestamp(
            field: field
        )
    }
}

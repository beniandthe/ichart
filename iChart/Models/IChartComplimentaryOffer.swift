import Foundation

enum IChartComplimentaryOfferDecision: String, Codable, Equatable, Sendable {
    case introductory
    case promotional
    case scheduledPromotional
    case ineligible
}

enum IChartComplimentaryOfferActivation: String, Codable, Equatable, Sendable {
    case immediate
    case nextBillingEvent
}

enum IChartComplimentaryOfferServerState: String, Codable, Equatable, Sendable {
    case available
    case prepared
    case scheduled
    case redeemed
    case unavailable
}

struct IChartComplimentaryOfferServerSignature: Codable, Equatable, Sendable {
    let keyID: String
    let nonce: String
    let signature: String
    let timestamp: Int
}

struct IChartComplimentaryOfferServerResponse: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let campaignID: String
    let enabled: Bool
    let decision: IChartComplimentaryOfferDecision
    let productID: String
    let offerID: String?
    let activation: IChartComplimentaryOfferActivation?
    let state: IChartComplimentaryOfferServerState
    let serverTime: String
    let accessStartsAt: String?
    let accessEndsAt: String?
    let estimatedAccessEndsAt: String?
    let accessEndsAtIsEstimated: Bool?
    let reason: String?
    let signature: IChartComplimentaryOfferServerSignature?
    let attemptID: String?
    let canPrepare: Bool?
    var recoveryOnly: Bool? = nil
    var pendingVerificationChecks: [String: Bool]? = nil
    var pendingDiscountCategory: String? = nil
}

enum IChartComplimentaryOfferServerAction: String, Codable, Equatable, Sendable {
    case status
    case prepare
    case confirm
}

struct IChartComplimentaryOfferServerRequest: Encodable, Equatable, Sendable {
    let schemaVersion: Int
    let action: IChartComplimentaryOfferServerAction
    let productID: String
    let signedTransactionInfo: String?
    let attemptID: String?
    let previousAttemptID: String?

    init(
        action: IChartComplimentaryOfferServerAction,
        productID: String,
        signedTransactionInfo: String? = nil,
        attemptID: UUID? = nil,
        previousAttemptID: UUID? = nil
    ) {
        self.schemaVersion = IChartComplimentaryOfferServerResponse.schemaVersion
        self.action = action
        self.productID = productID
        self.signedTransactionInfo = signedTransactionInfo
        self.attemptID = attemptID?.uuidString.lowercased()
        self.previousAttemptID = previousAttemptID?.uuidString.lowercased()
    }
}

struct IChartComplimentaryOfferProductMetadata: Equatable, Sendable {
    enum OfferKind: Equatable, Sendable {
        case introductory
        case promotional
    }

    enum PaymentMode: Equatable, Sendable {
        case freeTrial
        case other
    }

    enum Period: Equatable, Sendable {
        case days(Int)
        case weeks(Int)
        case months(Int)
        case years(Int)
        case other

        var renewalDescription: String? {
            switch self {
            case .days(1): return "day"
            case .days(let count) where count > 1: return "\(count) days"
            case .weeks(1): return "week"
            case .weeks(let count) where count > 1: return "\(count) weeks"
            case .months(1): return "month"
            case .months(let count) where count > 1: return "\(count) months"
            case .years(1): return "year"
            case .years(let count) where count > 1: return "\(count) years"
            case .days, .weeks, .months, .years, .other: return nil
            }
        }
    }

    let productID: String
    let productDisplayName: String
    let renewalDisplayPrice: String
    let renewalPeriod: Period
    let offerID: String?
    let offerKind: OfferKind
    let offerPrice: Decimal
    let offerDisplayPrice: String
    let offerPeriod: Period
    let offerPeriodCount: Int
    let paymentMode: PaymentMode
}

struct IChartComplimentaryOffer: Equatable, Identifiable, Sendable {
    var id: String { productID }

    let campaignID: String
    let productID: String
    let offerID: String?
    let decision: IChartComplimentaryOfferDecision
    let activation: IChartComplimentaryOfferActivation
    let productDisplayName: String
    let offerDisplayPrice: String
    let renewalDisplayPrice: String
    let renewalPeriodDescription: String

    var actionTitle: String {
        activation == .nextBillingEvent
            ? "Review Free Month at Renewal"
            : "Review One Month Free"
    }

    var detailText: String {
        if activation == .nextBillingEvent {
            return "Your current paid term stays in place. Apple will show the free month scheduled for the next billing event, followed by \(renewalDisplayPrice) per \(renewalPeriodDescription) unless canceled."
        }

        return "\(offerDisplayPrice) for one month, then \(renewalDisplayPrice) per \(renewalPeriodDescription) unless canceled. Apple will show the terms for your approval."
    }
}

struct IChartComplimentaryOfferPurchaseAuthorization: Equatable, Sendable {
    let offer: IChartComplimentaryOffer
    let attemptID: UUID
    let signature: IChartComplimentaryOfferServerSignature?
}

struct IChartComplimentaryOfferStatus: Equatable, Identifiable, Sendable {
    var id: String { "\(campaignID):\(productID):\(state.rawValue)" }

    let campaignID: String
    let productID: String
    let state: IChartComplimentaryOfferServerState
    let serverTime: Date
    let accessStartsAt: Date
    let accessEndsAt: Date?
    let estimatedAccessEndsAt: Date?

    var detailText: String {
        switch state {
        case .scheduled:
            return "Your current paid term stays in place. The complimentary month is scheduled to begin \(accessStartsAt.formatted(date: .abbreviated, time: .omitted))."
        case .redeemed:
            guard let accessEndsAt else { return "" }
            if serverTime >= accessEndsAt {
                return "Your complimentary month ended \(accessEndsAt.formatted(date: .abbreviated, time: .omitted))."
            }
            return "Your complimentary month is active through \(accessEndsAt.formatted(date: .abbreviated, time: .omitted))."
        case .available, .prepared, .unavailable:
            return ""
        }
    }
}

enum IChartComplimentaryTransactionOfferKind: String, Codable, Equatable, Sendable {
    case introductory
    case promotional
    case other
}

struct IChartPendingComplimentaryPurchase: Codable, Equatable, Sendable {
    static let version = 1

    let version: Int
    let accountID: UUID
    let productID: String
    let attemptID: UUID
    let decision: IChartComplimentaryOfferDecision
    let offerID: String?

    init(
        accountID: UUID,
        productID: String,
        attemptID: UUID,
        decision: IChartComplimentaryOfferDecision,
        offerID: String?
    ) {
        self.version = Self.version
        self.accountID = accountID
        self.productID = productID
        self.attemptID = attemptID
        self.decision = decision
        self.offerID = offerID
    }
}

enum IChartComplimentaryTransactionPolicy {
    static let promotionalOfferIDs: Set<String> = [
        "ichart_complimentary_monthly_1m_v1",
        "ichart_complimentary_annual_1m_v1"
    ]

    static func requiresCampaignResolution(
        productID: String,
        appAccountToken: UUID?,
        offerKind: IChartComplimentaryTransactionOfferKind?,
        offerID: String?,
        pending: IChartPendingComplimentaryPurchase?
    ) -> Bool {
        guard IChartStoreKitProductCatalog.isProProductID(productID) else {
            return false
        }

        if let offerID, promotionalOfferIDs.contains(offerID) {
            return true
        }

        return matchesPendingContext(
            productID: productID,
            appAccountToken: appAccountToken,
            offerKind: offerKind,
            offerID: offerID,
            pending: pending
        )
    }

    static func matchesPendingContext(
        productID: String,
        appAccountToken: UUID?,
        offerKind: IChartComplimentaryTransactionOfferKind?,
        offerID: String?,
        pending: IChartPendingComplimentaryPurchase?
    ) -> Bool {
        guard IChartStoreKitProductCatalog.isProProductID(productID),
              let pending,
              pending.version == IChartPendingComplimentaryPurchase.version,
              pending.productID == productID,
              pending.accountID == appAccountToken else {
            return false
        }

        switch pending.decision {
        case .introductory:
            return offerKind == .introductory && offerID == nil && pending.offerID == nil
        case .promotional:
            return offerKind == .promotional
                && offerID == pending.offerID
                && offerID.map(promotionalOfferIDs.contains) == true
        case .scheduledPromotional:
            let matchingKnownOffer = pending.offerID.map(promotionalOfferIDs.contains) == true
            let purchasedWithOffer = offerKind == .promotional && offerID == pending.offerID
            let currentPaidTermAwaitingScheduledBenefit = offerKind == nil && offerID == nil
            return matchingKnownOffer
                && (purchasedWithOffer || currentPaidTermAwaitingScheduledBenefit)
        case .ineligible:
            return false
        }
    }
}

enum IChartComplimentaryOfferPolicy {
    static func availableOffer(
        response: IChartComplimentaryOfferServerResponse,
        metadata: IChartComplimentaryOfferProductMetadata,
        appleIntroEligible: Bool
    ) -> IChartComplimentaryOffer? {
        guard response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion,
              response.enabled,
              response.recoveryOnly != true,
              response.canPrepare != false,
              response.state == .available || response.state == .prepared,
              !response.campaignID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validDate(response.serverTime) != nil,
              response.productID == metadata.productID,
              IChartStoreKitProductCatalog.isProProductID(response.productID),
              metadata.offerPrice == .zero,
              metadata.paymentMode == .freeTrial,
              metadata.offerPeriod == .months(1),
              metadata.offerPeriodCount == 1,
              !metadata.offerDisplayPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !metadata.productDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !metadata.renewalDisplayPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let renewalPeriodDescription = metadata.renewalPeriod.renewalDescription,
              response.signature == nil
        else {
            return nil
        }
        if response.state == .prepared, normalizedUUID(response.attemptID) == nil {
            return nil
        }

        let activation: IChartComplimentaryOfferActivation
        switch response.decision {
        case .introductory:
            guard appleIntroEligible,
                  metadata.offerKind == .introductory,
                  response.offerID == nil,
                  metadata.offerID == nil,
                  response.activation == .immediate else {
                return nil
            }
            activation = .immediate
        case .promotional:
            guard metadata.offerKind == .promotional,
                  let responseOfferID = normalized(response.offerID),
                  responseOfferID == normalized(metadata.offerID),
                  response.activation == .immediate else {
                return nil
            }
            activation = .immediate
        case .scheduledPromotional:
            guard metadata.offerKind == .promotional,
                  let responseOfferID = normalized(response.offerID),
                  responseOfferID == normalized(metadata.offerID),
                  response.activation == .nextBillingEvent else {
                return nil
            }
            activation = .nextBillingEvent
        case .ineligible:
            return nil
        }

        return IChartComplimentaryOffer(
            campaignID: response.campaignID,
            productID: response.productID,
            offerID: normalized(response.offerID),
            decision: response.decision,
            activation: activation,
            productDisplayName: metadata.productDisplayName,
            offerDisplayPrice: metadata.offerDisplayPrice,
            renewalDisplayPrice: metadata.renewalDisplayPrice,
            renewalPeriodDescription: renewalPeriodDescription
        )
    }

    static func preparedAuthorization(
        response: IChartComplimentaryOfferServerResponse,
        displayedOffer: IChartComplimentaryOffer,
        attemptID: UUID
    ) -> IChartComplimentaryOfferPurchaseAuthorization? {
        guard response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion,
              response.enabled,
              response.recoveryOnly != true,
              response.canPrepare != false,
              response.state == .prepared,
              response.campaignID == displayedOffer.campaignID,
              response.productID == displayedOffer.productID,
              response.decision == displayedOffer.decision,
              response.activation == displayedOffer.activation,
              normalized(response.offerID) == normalized(displayedOffer.offerID),
              normalizedUUID(response.attemptID) == attemptID,
              validDate(response.serverTime) != nil
        else {
            return nil
        }

        switch displayedOffer.decision {
        case .introductory:
            guard response.signature == nil,
                  displayedOffer.offerID == nil,
                  displayedOffer.activation == .immediate else {
                return nil
            }
            return IChartComplimentaryOfferPurchaseAuthorization(
                offer: displayedOffer,
                attemptID: attemptID,
                signature: nil
            )
        case .promotional, .scheduledPromotional:
            guard let signature = response.signature,
                  !signature.keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  UUID(uuidString: signature.nonce) != nil,
                  let signatureData = Data(base64Encoded: signature.signature),
                  validDERSignature(signatureData),
                  signature.timestamp > 0 else {
                return nil
            }
            return IChartComplimentaryOfferPurchaseAuthorization(
                offer: displayedOffer,
                attemptID: attemptID,
                signature: signature
            )
        case .ineligible:
            return nil
        }
    }

    static func matchesConfirmedCampaign(
        _ response: IChartComplimentaryOfferServerResponse,
        offer: IChartComplimentaryOffer,
        attemptID: UUID
    ) -> Bool {
        guard response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion,
              (response.enabled && response.recoveryOnly != true)
                || isDisabledRecoveryOnlyScheduledResponse(response),
              response.campaignID == offer.campaignID,
              response.productID == offer.productID,
              response.decision == offer.decision,
              response.activation == offer.activation,
              normalized(response.offerID) == normalized(offer.offerID),
              normalizedUUID(response.attemptID) == attemptID,
              response.signature == nil,
              validDate(response.serverTime) != nil else {
            return false
        }

        switch response.state {
        case .scheduled:
            guard offer.activation == .nextBillingEvent,
                  validScheduledDates(response) != nil else {
                return false
            }
            return true
        case .redeemed:
            return validRedeemedDates(response) != nil
        case .available, .prepared, .unavailable:
            return false
        }
    }

    static func confirmedStatus(
        response: IChartComplimentaryOfferServerResponse
    ) -> IChartComplimentaryOfferStatus? {
        guard response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion,
              (response.enabled && response.recoveryOnly != true)
                || isDisabledRecoveryOnlyScheduledResponse(response),
              IChartStoreKitProductCatalog.isProProductID(response.productID),
              !response.campaignID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let serverTime = validDate(response.serverTime),
              response.signature == nil else {
            return nil
        }

        let start: Date
        let end: Date?
        let estimatedEnd: Date?
        switch response.state {
        case .scheduled:
            guard response.decision == .scheduledPromotional,
                  response.activation == .nextBillingEvent,
                  normalized(response.offerID) != nil,
                  let dates = validScheduledDates(response) else {
                return nil
            }
            start = dates.start
            end = nil
            estimatedEnd = dates.estimatedEnd
        case .redeemed:
            guard response.decision != .ineligible,
                  response.activation != nil,
                  let dates = validRedeemedDates(response) else {
                return nil
            }
            start = dates.start
            end = dates.end
            estimatedEnd = nil
        case .available, .prepared, .unavailable:
            return nil
        }

        return IChartComplimentaryOfferStatus(
            campaignID: response.campaignID,
            productID: response.productID,
            state: response.state,
            serverTime: serverTime,
            accessStartsAt: start,
            accessEndsAt: end,
            estimatedAccessEndsAt: estimatedEnd
        )
    }

    /// A displayable disabled recovery result may finish ONLY the same owner's
    /// existing, locally pending purchase with the server's current attempt ID.
    /// This validates campaign completion, never an ordinary access entitlement.
    static func matchesConfirmedPurchase(
        _ response: IChartComplimentaryOfferServerResponse,
        pending: IChartPendingComplimentaryPurchase?,
        accountID: UUID,
        productID: String
    ) -> Bool {
        guard isDisabledRecoveryOnlyScheduledResponse(response),
              let pending,
              pending.version == IChartPendingComplimentaryPurchase.version,
              pending.accountID == accountID,
              pending.productID == productID,
              response.productID == productID,
              pending.decision == response.decision,
              pending.offerID == response.offerID,
              normalizedUUID(response.attemptID) == pending.attemptID else {
            return false
        }
        return true
    }

    static func recoverablePreparedAttempt(
        response: IChartComplimentaryOfferServerResponse,
        productID: String
    ) -> UUID? {
        guard response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion,
              response.enabled,
              response.recoveryOnly != true,
              response.state == .prepared,
              response.productID == productID,
              IChartStoreKitProductCatalog.isProProductID(productID),
              !response.campaignID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validDate(response.serverTime) != nil,
              response.signature == nil,
              let attemptID = normalizedUUID(response.attemptID) else {
            return nil
        }

        switch response.decision {
        case .introductory:
            guard response.activation == .immediate,
                  normalized(response.offerID) == nil else {
                return nil
            }
        case .promotional:
            guard response.activation == .immediate,
                  normalized(response.offerID) != nil else {
                return nil
            }
        case .scheduledPromotional:
            guard response.activation == .nextBillingEvent,
                  normalized(response.offerID) != nil else {
                return nil
            }
        case .ineligible:
            return nil
        }
        return attemptID
    }

    static func matchesRecoveredConfirmation(
        _ confirmed: IChartComplimentaryOfferServerResponse,
        prepared: IChartComplimentaryOfferServerResponse,
        attemptID: UUID
    ) -> Bool {
        guard recoverablePreparedAttempt(response: prepared, productID: prepared.productID) == attemptID,
              confirmed.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion,
              confirmed.enabled,
              confirmed.recoveryOnly != true,
              confirmed.campaignID == prepared.campaignID,
              confirmed.productID == prepared.productID,
              confirmed.decision == prepared.decision,
              confirmed.activation == prepared.activation,
              normalized(confirmed.offerID) == normalized(prepared.offerID),
              normalizedUUID(confirmed.attemptID) == attemptID,
              confirmed.signature == nil,
              validDate(confirmed.serverTime) != nil else {
            return false
        }

        if prepared.activation == .nextBillingEvent {
            // Billing can complete between the prepared-status lookup and its
            // confirmation. Accept only the same bound attempt with actual
            // completed dates; a renewal estimate is never redemption evidence.
            switch confirmed.state {
            case .scheduled:
                return validScheduledDates(confirmed) != nil
            case .redeemed:
                return validRedeemedDates(confirmed) != nil
            case .available, .prepared, .unavailable:
                return false
            }
        }
        return confirmed.state == .redeemed && validRedeemedDates(confirmed) != nil
    }

    private static func isDisabledRecoveryOnlyScheduledResponse(
        _ response: IChartComplimentaryOfferServerResponse
    ) -> Bool {
        let expectedOfferID: String
        switch response.productID {
        case IChartStoreKitProductCatalog.proMonthlyProductID:
            expectedOfferID = "ichart_complimentary_monthly_1m_v1"
        case IChartStoreKitProductCatalog.proAnnualProductID:
            expectedOfferID = "ichart_complimentary_annual_1m_v1"
        default:
            return false
        }
        return response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion
            && !response.enabled
            && response.recoveryOnly == true
            && response.canPrepare == false
            && response.campaignID == "ichart-complimentary-pro-1m-v1"
            && response.offerID == expectedOfferID
            && response.decision == .scheduledPromotional
            && response.activation == .nextBillingEvent
            && response.state == .scheduled
            && normalizedUUID(response.attemptID) != nil
            && validDate(response.serverTime) != nil
            && validScheduledDates(response) != nil
            && response.signature == nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedUUID(_ value: String?) -> UUID? {
        guard let value = normalized(value) else { return nil }
        return UUID(uuidString: value)
    }

    private static func validDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value)
    }

    private static func validDERSignature(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 8,
              bytes[0] == 0x30,
              Int(bytes[1]) == bytes.count - 2 else {
            return false
        }

        var index = 2
        for _ in 0..<2 {
            guard index + 2 <= bytes.count,
                  bytes[index] == 0x02 else {
                return false
            }
            let length = Int(bytes[index + 1])
            index += 2
            guard length > 0, index + length <= bytes.count else {
                return false
            }
            index += length
        }
        return index == bytes.count
    }

    private static func validScheduledDates(
        _ response: IChartComplimentaryOfferServerResponse
    ) -> (start: Date, estimatedEnd: Date)? {
        guard response.accessEndsAt == nil,
              response.accessEndsAtIsEstimated == true,
              let start = validDate(response.accessStartsAt),
              let estimatedEnd = validDate(response.estimatedAccessEndsAt),
              estimatedEnd > start else {
            return nil
        }
        return (start, estimatedEnd)
    }

    private static func validRedeemedDates(
        _ response: IChartComplimentaryOfferServerResponse
    ) -> (start: Date, end: Date)? {
        guard response.accessEndsAtIsEstimated != true,
              response.estimatedAccessEndsAt == nil,
              let start = validDate(response.accessStartsAt),
              let end = validDate(response.accessEndsAt),
              end > start else {
            return nil
        }
        return (start, end)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

#if DEBUG
import Foundation
import Supabase

enum IChartComplimentaryOfferQADiagnostics {
    struct Configuration: Equatable {
        let runID: UUID
        let expectedOwnerID: UUID

        fileprivate init(runID: UUID, expectedOwnerID: UUID) {
            self.runID = runID
            self.expectedOwnerID = expectedOwnerID
        }
    }

    struct SanitizedResponse: Equatable {
        let metadata: [String: String]

        fileprivate init(metadata: [String: String]) {
            self.metadata = metadata
        }
    }

    enum Failure: String {
        case serviceUnavailable = "service_unavailable"
        case productsUnavailable = "products_unavailable"
        case sessionUnavailable = "session_unavailable"
        case accountMismatch = "account_mismatch"
        case statusRequestFailed = "status_request_failed"
        case responseValidationFailed = "response_validation_failed"
    }

    static func configuration(environment: [String: String]) -> Configuration? {
        guard environment["ICHART_COMPLIMENTARY_QA_STATUS_TRACE"] == "1",
              let runID = canonicalUUID(environment["ICHART_COMPLIMENTARY_QA_RUN_ID"]),
              let ownerID = canonicalUUID(environment["ICHART_COMPLIMENTARY_QA_OWNER_ID"]),
              runID != ownerID else {
            return nil
        }
        return Configuration(runID: runID, expectedOwnerID: ownerID)
    }

    static func currentConfiguration(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Configuration? {
        #if targetEnvironment(simulator)
        return nil
        #else
        return configuration(environment: environment)
        #endif
    }

    static func sanitizedResponse(
        _ response: IChartComplimentaryOfferServerResponse,
        requestedProductID: String
    ) -> SanitizedResponse {
        let product = productName(requestedProductID)
        return SanitizedResponse(metadata: [
            "action": "status",
            "product": product,
            "schema_match": boolean(response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion),
            "campaign_match": boolean(response.campaignID == "ichart-complimentary-pro-1m-v1"),
            "product_match": boolean(product != "unknown" && response.productID == requestedProductID),
            "enabled": boolean(response.enabled),
            "decision": response.decision.rawValue,
            "state": response.state.rawValue,
            "activation": response.activation?.rawValue ?? "none",
            "reason": response.reason.flatMap { knownReasons.contains($0) ? $0 : nil } ?? "other",
            "signature_present": boolean(response.signature != nil),
            "attempt_present": boolean(response.attemptID != nil)
        ])
    }

    static func sanitizedHTTPError(
        data: Data,
        statusCode: Int,
        requestedProductID: String
    ) -> SanitizedResponse? {
        guard data.count <= 65_536,
              let response = try? JSONDecoder().decode(IChartComplimentaryOfferServerResponse.self, from: data) else {
            return nil
        }
        var metadata = sanitizedResponse(response, requestedProductID: requestedProductID).metadata
        metadata["http_status"] = knownHTTPErrorStatuses.contains(statusCode) ? String(statusCode) : "other"
        return SanitizedResponse(metadata: metadata)
    }

    static func sanitizedPendingChecks(
        _ response: IChartComplimentaryOfferServerResponse,
        requestedProductID: String
    ) -> SanitizedResponse? {
        guard response.schemaVersion == IChartComplimentaryOfferServerResponse.schemaVersion,
              response.campaignID == "ichart-complimentary-pro-1m-v1",
              productName(requestedProductID) != "unknown",
              response.productID == requestedProductID,
              !response.enabled, response.state == .unavailable,
              response.reason == "campaign_disabled", response.signature == nil,
              response.attemptID == nil, response.canPrepare != true,
              let checks = response.pendingVerificationChecks,
              Set(checks.keys) == pendingCheckKeys else { return nil }
        return SanitizedResponse(metadata: checks.mapValues(boolean))
    }

    static func recordPendingChecks(
        _ response: IChartComplimentaryOfferServerResponse,
        requestedProductID: String,
        initialAccountID: UUID,
        finalAccountID: UUID?
    ) {
        guard let sanitized = sanitizedPendingChecks(response, requestedProductID: requestedProductID) else { return }
        for metadata in metadataForRecording(
            responses: [sanitized], configuration: currentConfiguration(),
            initialAccountID: initialAccountID, finalAccountID: finalAccountID
        ) {
            IChartPerformanceTrace.record("subscription.complimentary_qa_pending_checks", metadata: metadata)
        }
        guard let category = sanitizedPendingDiscount(response, requestedProductID: requestedProductID) else { return }
        for metadata in metadataForRecording(
            responses: [category], configuration: currentConfiguration(),
            initialAccountID: initialAccountID, finalAccountID: finalAccountID
        ) {
            IChartPerformanceTrace.record("subscription.complimentary_qa_pending_discount", metadata: metadata)
        }
    }

    static func sanitizedPendingDiscount(
        _ response: IChartComplimentaryOfferServerResponse,
        requestedProductID: String
    ) -> SanitizedResponse? {
        guard sanitizedPendingChecks(response, requestedProductID: requestedProductID) != nil,
              let category = response.pendingDiscountCategory,
              pendingDiscountCategories.contains(category) else { return nil }
        return SanitizedResponse(metadata: ["action": "status", "product": productName(requestedProductID),
            "discount_category": category])
    }

    static let pendingDiscountCategories: Set<String> = [
        "free_trial", "pay_as_you_go", "pay_up_front", "one_time",
        "missing", "null_value", "invalid_type", "other_string"
    ]

    static let pendingCheckKeys: Set<String> = [
        "status_active", "unrevoked", "unexpired", "current_product_match", "renewal_product_match",
        "configured_offer_match", "free_trial", "one_month", "zero_price", "auto_renew_on",
        "renewal_date_valid", "discount_present", "period_present", "price_present", "price_positive",
        "renewal_date_present"
    ]

    // Never record an error description, response body, URL, decoding path or
    // NSError userInfo. Only fixed categories from the pinned SDK/Foundation
    // enter the explicitly opted-in QA trace.
    static func sanitizedRequestError(
        _ error: Error,
        requestedProductID: String
    ) -> SanitizedResponse {
        var metadata = [
            "action": "status",
            "product": productName(requestedProductID),
            "failure": Failure.statusRequestFailed.rawValue
        ]
        if let functionError = error as? FunctionsError {
            switch functionError {
            case .relayError:
                metadata["error_category"] = "function_relay"
            case let .httpError(code, data):
                if let response = sanitizedHTTPError(
                    data: data, statusCode: code, requestedProductID: requestedProductID
                ) {
                    metadata = response.metadata
                    metadata["failure"] = Failure.statusRequestFailed.rawValue
                    metadata["error_category"] = "function_http"
                    metadata["response_shape"] = "offer_response"
                } else {
                    metadata["error_category"] = "function_http"
                    metadata["http_status"] = knownHTTPErrorStatuses.contains(code) ? String(code) : "other"
                    metadata["response_shape"] = data.count > 65_536 ? "oversized" : "non_offer_response"
                }
            }
        } else if let decodingError = error as? DecodingError {
            metadata["error_category"] = "response_decoding"
            switch decodingError {
            case .dataCorrupted: metadata["error_detail"] = "data_corrupted"
            case .keyNotFound: metadata["error_detail"] = "key_not_found"
            case .typeMismatch: metadata["error_detail"] = "type_mismatch"
            case .valueNotFound: metadata["error_detail"] = "value_not_found"
            @unknown default: metadata["error_detail"] = "other"
            }
        } else if error is CancellationError {
            metadata["error_category"] = "cancelled"
        } else {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                metadata["error_category"] = "network"
                switch nsError.code {
                case NSURLErrorTimedOut: metadata["error_detail"] = "timeout"
                case NSURLErrorNotConnectedToInternet: metadata["error_detail"] = "offline"
                case NSURLErrorNetworkConnectionLost: metadata["error_detail"] = "connection_lost"
                case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                    metadata["error_detail"] = "name_resolution"
                case NSURLErrorCannotConnectToHost: metadata["error_detail"] = "connection_failed"
                case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                     NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                     NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
                     NSURLErrorClientCertificateRequired:
                    metadata["error_detail"] = "tls"
                case NSURLErrorCancelled: metadata["error_detail"] = "cancelled"
                default: metadata["error_detail"] = "other"
                }
            } else {
                metadata["error_category"] = "unknown"
            }
        }
        return SanitizedResponse(metadata: metadata)
    }

    static func record(
        responses: [SanitizedResponse],
        initialAccountID: UUID,
        finalAccountID: UUID?
    ) {
        for metadata in metadataForRecording(
            responses: responses,
            configuration: currentConfiguration(),
            initialAccountID: initialAccountID,
            finalAccountID: finalAccountID
        ) {
            IChartPerformanceTrace.record("subscription.complimentary_qa_status", metadata: metadata)
        }
    }

    static func recordFailure(
        _ reason: Failure,
        initialAccountID: UUID?,
        finalAccountID: UUID?
    ) {
        guard let metadata = metadataForFailure(
            reason,
            configuration: currentConfiguration(),
            initialAccountID: initialAccountID,
            finalAccountID: finalAccountID
        ) else {
            return
        }
        IChartPerformanceTrace.record("subscription.complimentary_qa_status", metadata: metadata)
    }

    // Pure preparation keeps unit tests away from the on-device recorder and session.
    static func metadataForRecording(
        responses: [SanitizedResponse],
        configuration: Configuration?,
        initialAccountID: UUID,
        finalAccountID: UUID?
    ) -> [[String: String]] {
        guard let configuration,
              configuration.runID != initialAccountID,
              configuration.runID != finalAccountID else {
            return []
        }
        guard initialAccountID == configuration.expectedOwnerID,
              finalAccountID == configuration.expectedOwnerID else {
            return [failureMetadata(.accountMismatch, configuration: configuration, ownerMatches: false)]
        }
        return responses.map { response in
            var metadata = response.metadata
            metadata["run_id"] = configuration.runID.uuidString.lowercased()
            metadata["owner_match"] = "true"
            return metadata
        }
    }

    static func metadataForFailure(
        _ reason: Failure,
        configuration: Configuration?,
        initialAccountID: UUID?,
        finalAccountID: UUID?
    ) -> [String: String]? {
        guard let configuration,
              configuration.runID != initialAccountID,
              configuration.runID != finalAccountID else {
            return nil
        }
        let ownerMatches = initialAccountID == configuration.expectedOwnerID
            && finalAccountID == configuration.expectedOwnerID
        return failureMetadata(
            ownerMatches ? reason : .accountMismatch,
            configuration: configuration,
            ownerMatches: ownerMatches
        )
    }

    private static func failureMetadata(
        _ reason: Failure,
        configuration: Configuration,
        ownerMatches: Bool
    ) -> [String: String] {
        [
            "action": "status",
            "run_id": configuration.runID.uuidString.lowercased(),
            "owner_match": boolean(ownerMatches),
            "failure": reason.rawValue
        ]
    }

    private static func productName(_ productID: String) -> String {
        switch productID {
        case IChartStoreKitProductCatalog.proMonthlyProductID: return "monthly"
        case IChartStoreKitProductCatalog.proAnnualProductID: return "annual"
        default: return "unknown"
        }
    }

    private static func canonicalUUID(_ value: String?) -> UUID? {
        guard let value, value.count == 36, let uuid = UUID(uuidString: value),
              uuid.uuidString.lowercased() == value.lowercased() else {
            return nil
        }
        return uuid
    }

    private static func boolean(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static let knownHTTPErrorStatuses: Set<Int> = [
        400, 401, 403, 404, 405, 409, 413, 429, 500, 502, 503, 504
    ]

    private static let knownReasons: Set<String> = [
        "active_subscription_same_product_required",
        "ambiguous_active_subscription",
        "apple_offer_not_yet_confirmed",
        "campaign_already_used",
        "campaign_already_used_on_other_product",
        "campaign_benefit_conflict",
        "campaign_disabled",
        "campaign_ended",
        "campaign_environment_mismatch",
        "campaign_not_available",
        "campaign_not_configured",
        "campaign_not_started",
        "campaign_verification_unavailable",
        "conflicting_or_unknown_renewal_offer",
        "conflicting_renewal_offer",
        "invalid_request",
        "method_not_allowed",
        "pending_campaign_offer_not_verifiable",
        "prepared_recovery_only",
        "purchase_attempt_conflict",
        "purchase_attempt_not_current",
        "purchase_attempt_stale",
        "request_too_large",
        "sandbox_qa_not_configured",
        "signed_in_account_required",
        "subscription_state_changed_before_preparation",
        "subscription_state_inconsistent",
        "subscription_state_requires_resolution",
        "transaction_ownership_or_scope_mismatch",
        "verified_offer_terms_mismatch",
        "verified_subscription_claim_required"
    ]
}
#endif

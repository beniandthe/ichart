#if DEBUG && canImport(UIKit) && canImport(Supabase)
import Foundation
import Supabase
import XCTest
@testable import iChart

final class IChartComplimentaryOfferQADiagnosticsTests: XCTestCase {
    private typealias Diagnostics = IChartComplimentaryOfferQADiagnostics

    private let runID = UUID(uuidString: "ABCDEF12-3456-4789-8ABC-DEF123456789")!
    private let ownerID = UUID(uuidString: "FEDCBA98-7654-4321-8FED-CBA987654321")!
    private let otherOwnerID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let monthlyID = IChartStoreKitProductCatalog.proMonthlyProductID
    private let annualID = IChartStoreKitProductCatalog.proAnnualProductID

    func testConfigurationRequiresExactOptInFlag() {
        for flag in [nil, "", "0", "true", "2", " 1", "1\n"] as [String?] {
            var environment = validEnvironment()
            environment["ICHART_COMPLIMENTARY_QA_STATUS_TRACE"] = flag
            XCTAssertNil(Diagnostics.configuration(environment: environment), "flag=\(String(describing: flag))")
        }
    }

    func testConfigurationRequiresBothUUIDFieldsAndDistinctRunAndOwner() {
        for key in ["ICHART_COMPLIMENTARY_QA_RUN_ID", "ICHART_COMPLIMENTARY_QA_OWNER_ID"] {
            var environment = validEnvironment()
            environment.removeValue(forKey: key)
            XCTAssertNil(Diagnostics.configuration(environment: environment))
        }

        var duplicate = validEnvironment()
        duplicate["ICHART_COMPLIMENTARY_QA_RUN_ID"] = ownerID.uuidString.lowercased()
        XCTAssertNil(Diagnostics.configuration(environment: duplicate))
    }

    func testConfigurationRejectsMalformedAndNoncanonicalUUIDFields() {
        let malformed = [
            "", "not-a-uuid", runID.uuidString.replacingOccurrences(of: "-", with: ""),
            "{\(runID.uuidString)}", " \(runID.uuidString)", "\(runID.uuidString) ",
            "\(runID.uuidString)\n", "\(runID.uuidString)extra"
        ]
        for key in ["ICHART_COMPLIMENTARY_QA_RUN_ID", "ICHART_COMPLIMENTARY_QA_OWNER_ID"] {
            for value in malformed {
                var environment = validEnvironment()
                environment[key] = value
                XCTAssertNil(Diagnostics.configuration(environment: environment), "key=\(key), value=\(value)")
            }
        }
    }

    func testConfigurationParsesCanonicalUUIDsWithoutCaseChangingIdentity() throws {
        let upper = try configuration()
        var lowerEnvironment = validEnvironment()
        lowerEnvironment["ICHART_COMPLIMENTARY_QA_RUN_ID"] = runID.uuidString.lowercased()
        lowerEnvironment["ICHART_COMPLIMENTARY_QA_OWNER_ID"] = ownerID.uuidString.lowercased()
        let lower = try XCTUnwrap(Diagnostics.configuration(environment: lowerEnvironment))

        XCTAssertEqual(upper, lower)
        XCTAssertEqual(upper.runID, runID)
        XCTAssertEqual(upper.expectedOwnerID, ownerID)
    }

    func testSimulatorCannotActivateRuntimeConfiguration() throws {
        #if targetEnvironment(simulator)
        XCTAssertNil(Diagnostics.currentConfiguration(environment: validEnvironment()))
        #else
        XCTAssertEqual(Diagnostics.currentConfiguration(environment: validEnvironment()), try configuration())
        #endif
    }

    func testEnabledFutureStartResponseProducesOnlyFixedMetadata() {
        let sanitized = Diagnostics.sanitizedResponse(
            response(reason: "campaign_not_started"),
            requestedProductID: monthlyID
        )

        XCTAssertEqual(sanitized.metadata, [
            "action": "status", "product": "monthly", "schema_match": "true",
            "campaign_match": "true", "product_match": "true", "enabled": "true",
            "decision": "ineligible", "state": "unavailable", "activation": "none",
            "reason": "campaign_not_started", "signature_present": "false", "attempt_present": "false"
        ])
        XCTAssertEqual(sanitized.metadata.count, 12)
        XCTAssertLessThanOrEqual(sanitized.metadata.count, 18)
    }

    func testPendingChecksAreFixedBooleansBoundToDisabledStatus() throws {
        var value = response(enabled: false, reason: "campaign_disabled")
        value.pendingVerificationChecks = Dictionary(uniqueKeysWithValues: Diagnostics.pendingCheckKeys.map { ($0, false) })
        let sanitized = try XCTUnwrap(Diagnostics.sanitizedPendingChecks(value, requestedProductID: monthlyID))
        XCTAssertEqual(sanitized.metadata.count, 16)
        XCTAssertEqual(Set(sanitized.metadata.keys), Diagnostics.pendingCheckKeys)
        XCTAssertTrue(sanitized.metadata.values.allSatisfy { $0 == "false" })
        let recorded = Diagnostics.metadataForRecording(responses: [sanitized], configuration: try configuration(),
            initialAccountID: ownerID, finalAccountID: ownerID)
        XCTAssertEqual(recorded.first?.count, 18)
        let decoded = try JSONDecoder().decode(IChartComplimentaryOfferServerResponse.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.pendingVerificationChecks, value.pendingVerificationChecks)
        XCTAssertNil(IChartComplimentaryOfferPolicy.recoverablePreparedAttempt(response: decoded, productID: monthlyID))
        XCTAssertNil(IChartComplimentaryOfferPolicy.confirmedStatus(response: decoded))
    }

    func testPendingChecksRejectUntrustedKeysAndBindingMismatches() {
        let valid = Dictionary(uniqueKeysWithValues: Diagnostics.pendingCheckKeys.map { ($0, true) })
        for checks in [nil, [:], ["private-token": true], valid.merging(["extra-private-string": false]) { _, new in new }] {
            var value = response(enabled: false, reason: "campaign_disabled")
            value.pendingVerificationChecks = checks
            XCTAssertNil(Diagnostics.sanitizedPendingChecks(value, requestedProductID: monthlyID))
        }
        for initial in [response(), response(schemaVersion: 99, enabled: false, reason: "campaign_disabled"),
            response(campaignID: "private", enabled: false, reason: "campaign_disabled"),
            response(enabled: false, productID: annualID, reason: "campaign_disabled"),
            response(enabled: false, reason: "other"), response(enabled: false, reason: "campaign_disabled", attemptID: runID.uuidString)] {
            var value = initial; value.pendingVerificationChecks = valid
            XCTAssertNil(Diagnostics.sanitizedPendingChecks(value, requestedProductID: monthlyID))
        }
    }

    func testPendingDiscountCategoryIsBoundedAndDoesNotAuthorizeRecovery() throws {
        var value = response(enabled: false, reason: "campaign_disabled")
        value.pendingVerificationChecks = Dictionary(uniqueKeysWithValues: Diagnostics.pendingCheckKeys.map { ($0, true) })
        for category in Diagnostics.pendingDiscountCategories {
            value.pendingDiscountCategory = category
            let sanitized = try XCTUnwrap(Diagnostics.sanitizedPendingDiscount(value, requestedProductID: monthlyID))
            XCTAssertEqual(sanitized.metadata, ["action": "status", "product": "monthly", "discount_category": category])
            let decoded = try JSONDecoder().decode(IChartComplimentaryOfferServerResponse.self, from: JSONEncoder().encode(value))
            XCTAssertEqual(decoded.pendingDiscountCategory, category)
            XCTAssertNil(IChartComplimentaryOfferPolicy.confirmedStatus(response: decoded))
            XCTAssertNil(IChartComplimentaryOfferPolicy.recoverablePreparedAttempt(response: decoded, productID: monthlyID))
        }
        for category in [nil, "", "FREE_TRIAL", "private-raw-value"] as [String?] {
            value.pendingDiscountCategory = category
            XCTAssertNil(Diagnostics.sanitizedPendingDiscount(value, requestedProductID: monthlyID))
        }
        var enabled = response(enabled: true, reason: "campaign_disabled")
        enabled.pendingDiscountCategory = "free_trial"
        enabled.pendingVerificationChecks = value.pendingVerificationChecks
        XCTAssertNil(Diagnostics.sanitizedPendingDiscount(enabled, requestedProductID: monthlyID))
        value.pendingDiscountCategory = "free_trial"
        value.pendingVerificationChecks = nil
        XCTAssertNil(Diagnostics.sanitizedPendingDiscount(value, requestedProductID: monthlyID))
    }

    func testProductCategoryUsesRequestedProductAndUnknownCannotMatch() {
        let annualRequest = Diagnostics.sanitizedResponse(response(), requestedProductID: annualID)
        XCTAssertEqual(annualRequest.metadata["product"], "annual")
        XCTAssertEqual(annualRequest.metadata["product_match"], "false")

        let unknown = "private-requested-product"
        let unknownRequest = Diagnostics.sanitizedResponse(response(productID: unknown), requestedProductID: unknown)
        XCTAssertEqual(unknownRequest.metadata["product"], "unknown")
        XCTAssertEqual(unknownRequest.metadata["product_match"], "false")
        XCTAssertFalse(unknownRequest.metadata.values.contains(unknown))
    }

    func testKnownVerificationReasonsRemainFixedAndMissingReasonBecomesOther() {
        for reason in ["transaction_ownership_or_scope_mismatch", "campaign_verification_unavailable"] {
            XCTAssertEqual(
                Diagnostics.sanitizedResponse(response(reason: reason), requestedProductID: monthlyID).metadata["reason"],
                reason
            )
        }
        XCTAssertEqual(
            Diagnostics.sanitizedResponse(response(reason: nil), requestedProductID: monthlyID).metadata["reason"],
            "other"
        )
    }

    func testUntrustedResponseStringsNeverEnterMetadata() {
        let campaign = "private-campaign-string"
        let product = "private-product-string"
        let reason = "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzZWNyZXQiOiJzeW50aGV0aWMifQ.synthetic-signature"
        let offer = "private-offer-string"
        let time = "private-server-time-string"
        let signature = IChartComplimentaryOfferServerSignature(
            keyID: "private-key-id", nonce: "33333333-3333-4333-8333-333333333333",
            signature: "eyJhbGciOiJFUzI1NiJ9.eyJzaWduZWQiOiJzeW50aGV0aWMifQ.synthetic-signature", timestamp: 123
        )
        let attempt = "22222222-2222-4222-8222-222222222222"
        let sanitized = Diagnostics.sanitizedResponse(
            response(schemaVersion: 99, campaignID: campaign, enabled: false, productID: product,
                     offerID: offer, serverTime: time, reason: reason, signature: signature, attemptID: attempt),
            requestedProductID: monthlyID
        )

        XCTAssertEqual(sanitized.metadata["schema_match"], "false")
        XCTAssertEqual(sanitized.metadata["campaign_match"], "false")
        XCTAssertEqual(sanitized.metadata["product_match"], "false")
        XCTAssertEqual(sanitized.metadata["enabled"], "false")
        XCTAssertEqual(sanitized.metadata["reason"], "other")
        XCTAssertEqual(sanitized.metadata["signature_present"], "true")
        XCTAssertEqual(sanitized.metadata["attempt_present"], "true")
        XCTAssertEqual(sanitized.metadata.count, 12)
        let recordedText = sanitized.metadata.description
        for value in [campaign, product, reason, offer, time, signature.keyID, signature.nonce, signature.signature, attempt] {
            XCTAssertFalse(recordedText.contains(value), "Untrusted response field leaked: \(value)")
        }
    }

    func testStableExpectedAccountAddsOnlyRunCorrelationAndOwnerMatch() throws {
        let sanitized = Diagnostics.sanitizedResponse(response(), requestedProductID: monthlyID)
        let records = Diagnostics.metadataForRecording(
            responses: [sanitized], configuration: try configuration(),
            initialAccountID: ownerID, finalAccountID: ownerID
        )
        var expected = sanitized.metadata
        expected["run_id"] = runID.uuidString.lowercased()
        expected["owner_match"] = "true"

        XCTAssertEqual(records, [expected])
        XCTAssertLessThanOrEqual(try XCTUnwrap(records.first).count, 18)
        XCTAssertFalse(records.description.lowercased().contains(ownerID.uuidString.lowercased()))
        XCTAssertFalse(records.description.contains("owner_id"))
    }

    func testDisabledConfigurationProducesNoResponseOrFailureRecords() {
        let sanitized = Diagnostics.sanitizedResponse(response(), requestedProductID: monthlyID)
        XCTAssertEqual(Diagnostics.metadataForRecording(
            responses: [sanitized], configuration: nil, initialAccountID: ownerID, finalAccountID: ownerID
        ), [])
        XCTAssertNil(Diagnostics.metadataForFailure(
            .statusRequestFailed, configuration: nil, initialAccountID: ownerID, finalAccountID: ownerID
        ))
    }

    func testSwitchedMissingOrUnexpectedAccountRefusesAllResponseMetadata() throws {
        let config = try configuration()
        let responses = [
            Diagnostics.sanitizedResponse(response(), requestedProductID: monthlyID),
            Diagnostics.sanitizedResponse(response(productID: annualID), requestedProductID: annualID)
        ]
        for (initial, final) in [
            (ownerID, nil), (ownerID, otherOwnerID), (otherOwnerID, ownerID), (otherOwnerID, otherOwnerID)
        ] as [(UUID, UUID?)] {
            XCTAssertEqual(Diagnostics.metadataForRecording(
                responses: responses, configuration: config, initialAccountID: initial, finalAccountID: final
            ), [accountMismatchMetadata()])
        }
    }

    func testStableAccountFailureCodesHaveBoundedMetadataAndNoOwnerIdentity() throws {
        let config = try configuration()
        let failures: [Diagnostics.Failure] = [
            .serviceUnavailable, .productsUnavailable, .sessionUnavailable,
            .accountMismatch, .statusRequestFailed, .responseValidationFailed
        ]
        for failure in failures {
            let record = try XCTUnwrap(Diagnostics.metadataForFailure(
                failure, configuration: config, initialAccountID: ownerID, finalAccountID: ownerID
            ))
            XCTAssertEqual(record, [
                "action": "status", "run_id": runID.uuidString.lowercased(),
                "owner_match": "true", "failure": failure.rawValue
            ])
            XCTAssertFalse(record.description.lowercased().contains(ownerID.uuidString.lowercased()))
        }
    }

    func testFailureAlwaysReportsAccountMismatchWhenAccountCannotBeBound() throws {
        let config = try configuration()
        for (initial, final) in [
            (nil, nil), (nil, ownerID), (ownerID, nil), (ownerID, otherOwnerID),
            (otherOwnerID, ownerID), (otherOwnerID, otherOwnerID)
        ] as [(UUID?, UUID?)] {
            XCTAssertEqual(Diagnostics.metadataForFailure(
                .statusRequestFailed, configuration: config, initialAccountID: initial, finalAccountID: final
            ), accountMismatchMetadata())
        }
    }

    func testRunCorrelationCannotExposeAnAccountUUIDAsTheRunTag() throws {
        let config = try configuration()
        let sanitized = Diagnostics.sanitizedResponse(response(), requestedProductID: monthlyID)
        for (initial, final) in [
            (runID, ownerID), (ownerID, runID), (runID, nil), (runID, runID)
        ] as [(UUID, UUID?)] {
            XCTAssertEqual(Diagnostics.metadataForRecording(
                responses: [sanitized], configuration: config, initialAccountID: initial, finalAccountID: final
            ), [])
            XCTAssertNil(Diagnostics.metadataForFailure(
                .statusRequestFailed, configuration: config, initialAccountID: initial, finalAccountID: final
            ))
        }
        XCTAssertNil(Diagnostics.metadataForFailure(
            .sessionUnavailable, configuration: config, initialAccountID: nil, finalAccountID: runID
        ))
    }

    func testTypedHTTP503ErrorRetainsOnlyBoundedStatusAndKnownReason() throws {
        let data = try JSONEncoder().encode(response(reason: "campaign_verification_unavailable"))
        let sanitized = try XCTUnwrap(Diagnostics.sanitizedHTTPError(
            data: data, statusCode: 503, requestedProductID: monthlyID
        ))
        XCTAssertEqual(sanitized.metadata["reason"], "campaign_verification_unavailable")
        XCTAssertEqual(sanitized.metadata["http_status"], "503")
        XCTAssertEqual(sanitized.metadata["product"], "monthly")

        let records = Diagnostics.metadataForRecording(
            responses: [sanitized], configuration: try configuration(),
            initialAccountID: ownerID, finalAccountID: ownerID
        )
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record["run_id"], runID.uuidString.lowercased())
        XCTAssertEqual(record["owner_match"], "true")
        XCTAssertLessThanOrEqual(record.count, 18)
        XCTAssertFalse(record.description.lowercased().contains(ownerID.uuidString.lowercased()))
    }

    func testMalformedEmptyAndNonresponseHTTPErrorBodiesProduceNoMetadata() {
        let bodies = [
            Data(),
            Data("not-json private-body-sentinel".utf8),
            Data("{".utf8),
            Data("null".utf8),
            Data("[]".utf8),
            Data("{}".utf8),
            Data("{\"reason\":\"campaign_verification_unavailable\",\"private_field\":\"private-body-sentinel\"}".utf8)
        ]
        for data in bodies {
            XCTAssertNil(Diagnostics.sanitizedHTTPError(
                data: data, statusCode: 503, requestedProductID: monthlyID
            ))
        }
    }

    func testOversizedTypedHTTPErrorBodyProducesNoMetadata() throws {
        var data = try JSONEncoder().encode(response(reason: "campaign_verification_unavailable"))
        XCTAssertLessThan(data.count, 65_536)
        data.append(Data(repeating: 0x20, count: 65_536 - data.count))
        XCTAssertEqual(data.count, 65_536)
        XCTAssertNotNil(Diagnostics.sanitizedHTTPError(
            data: data, statusCode: 503, requestedProductID: monthlyID
        ))

        data.append(0x20)
        XCTAssertEqual(data.count, 65_537)
        XCTAssertNil(Diagnostics.sanitizedHTTPError(
            data: data, statusCode: 503, requestedProductID: monthlyID
        ))
    }

    func testNonallowlistedHTTPStatusCodesNormalizeToOther() throws {
        let data = try JSONEncoder().encode(response(reason: "campaign_verification_unavailable"))
        for statusCode in [200, 418, -1] {
            let sanitized = try XCTUnwrap(Diagnostics.sanitizedHTTPError(
                data: data, statusCode: statusCode, requestedProductID: monthlyID
            ))
            XCTAssertEqual(sanitized.metadata["http_status"], "other")
            XCTAssertEqual(sanitized.metadata["reason"], "campaign_verification_unavailable")
        }
    }

    func testRequestHTTPFailureKeepsStatusEvenWhenGatewayBodyIsNotOfferSchema() {
        let sentinel = "private-body-url-token-sentinel"
        for body in [Data(), Data("not-json \(sentinel)".utf8), Data("{\"message\":\"\(sentinel)\"}".utf8)] {
            let result = Diagnostics.sanitizedRequestError(
                FunctionsError.httpError(code: 401, data: body), requestedProductID: monthlyID
            )
            XCTAssertEqual(result.metadata, [
                "action": "status", "product": "monthly", "failure": "status_request_failed",
                "error_category": "function_http", "http_status": "401", "response_shape": "non_offer_response"
            ])
            XCTAssertFalse(result.metadata.description.contains(sentinel))
        }
    }

    func testRequestHTTPFailureRetainsTypedReasonWithoutLeakingBody() throws {
        let result = Diagnostics.sanitizedRequestError(
            FunctionsError.httpError(code: 503, data: try JSONEncoder().encode(
                response(reason: "campaign_verification_unavailable")
            )), requestedProductID: monthlyID
        )
        XCTAssertEqual(result.metadata["http_status"], "503")
        XCTAssertEqual(result.metadata["reason"], "campaign_verification_unavailable")
        XCTAssertEqual(result.metadata["error_category"], "function_http")
        XCTAssertEqual(result.metadata["response_shape"], "offer_response")
        let record = try XCTUnwrap(Diagnostics.metadataForRecording(
            responses: [result], configuration: try configuration(),
            initialAccountID: ownerID, finalAccountID: ownerID
        ).first)
        XCTAssertLessThanOrEqual(record.count, 18)
    }

    func testRequestOversizedBodyAndUnknownHTTPStatusRemainBounded() {
        let result = Diagnostics.sanitizedRequestError(
            FunctionsError.httpError(code: 418, data: Data(repeating: 0x20, count: 65_537)),
            requestedProductID: "private-product-sentinel"
        )
        XCTAssertEqual(result.metadata["response_shape"], "oversized")
        XCTAssertEqual(result.metadata["http_status"], "other")
        XCTAssertEqual(result.metadata["product"], "unknown")
        XCTAssertFalse(result.metadata.description.contains("private-product-sentinel"))
    }

    func testRequestRelayAndCancellationHaveDistinctFixedCategories() {
        for (error, category) in [
            (FunctionsError.relayError as Error, "function_relay"),
            (CancellationError() as Error, "cancelled")
        ] {
            let result = Diagnostics.sanitizedRequestError(error, requestedProductID: monthlyID)
            XCTAssertEqual(result.metadata["error_category"], category)
            XCTAssertNil(result.metadata["http_status"])
            XCTAssertNil(result.metadata["error_detail"])
        }
    }

    func testRequestNetworkBucketsNeverIncludeNSErrorUserInfoOrDescriptions() {
        let cases: [(Int, String)] = [
            (NSURLErrorTimedOut, "timeout"), (NSURLErrorNotConnectedToInternet, "offline"),
            (NSURLErrorNetworkConnectionLost, "connection_lost"),
            (NSURLErrorCannotFindHost, "name_resolution"), (NSURLErrorDNSLookupFailed, "name_resolution"),
            (NSURLErrorCannotConnectToHost, "connection_failed"),
            (NSURLErrorSecureConnectionFailed, "tls"), (NSURLErrorServerCertificateUntrusted, "tls"),
            (NSURLErrorCancelled, "cancelled"), (987654, "other")
        ]
        for (code, detail) in cases {
            let error = NSError(domain: NSURLErrorDomain, code: code, userInfo: [
                NSLocalizedDescriptionKey: "private-description-sentinel",
                NSURLErrorFailingURLErrorKey: URL(string: "https://private-sentinel.invalid/?token=secret")!,
                NSUnderlyingErrorKey: NSError(domain: "private-underlying-sentinel", code: 44)
            ])
            let result = Diagnostics.sanitizedRequestError(error, requestedProductID: monthlyID)
            XCTAssertEqual(result.metadata["error_category"], "network")
            XCTAssertEqual(result.metadata["error_detail"], detail)
            XCTAssertFalse(result.metadata.description.contains("private"))
            XCTAssertFalse(result.metadata.description.contains("secret"))
        }
    }

    func testRequestDecodingBucketsNeverIncludeKeysPathsTypesOrDescriptions() {
        enum PrivateKey: String, CodingKey {
            case privateSentinel = "private-key-sentinel"
        }
        let context = DecodingError.Context(codingPath: [PrivateKey.privateSentinel], debugDescription: "private-description-sentinel")
        let cases: [(Error, String)] = [
            (DecodingError.dataCorrupted(context), "data_corrupted"),
            (DecodingError.keyNotFound(PrivateKey.privateSentinel, context), "key_not_found"),
            (DecodingError.typeMismatch(String.self, context), "type_mismatch"),
            (DecodingError.valueNotFound(String.self, context), "value_not_found")
        ]
        for (error, detail) in cases {
            let result = Diagnostics.sanitizedRequestError(error, requestedProductID: monthlyID)
            XCTAssertEqual(result.metadata["error_category"], "response_decoding")
            XCTAssertEqual(result.metadata["error_detail"], detail)
            XCTAssertFalse(result.metadata.description.contains("private"))
        }
    }

    func testRequestUnknownErrorsDoNotPassThroughDomainsOrCodes() {
        let result = Diagnostics.sanitizedRequestError(
            NSError(domain: "private-domain-sentinel", code: NSURLErrorTimedOut, userInfo: [
                NSLocalizedDescriptionKey: "private-description-sentinel"
            ]), requestedProductID: monthlyID
        )
        XCTAssertEqual(result.metadata["error_category"], "unknown")
        XCTAssertNil(result.metadata["error_detail"])
        XCTAssertFalse(result.metadata.description.contains("private"))
    }

    func testRequestFailureCategoryIsSuppressedOnOwnerMismatchAndWithoutOptIn() throws {
        let result = Diagnostics.sanitizedRequestError(
            FunctionsError.httpError(code: 401, data: Data()), requestedProductID: monthlyID
        )
        XCTAssertEqual(Diagnostics.metadataForRecording(
            responses: [result], configuration: try configuration(),
            initialAccountID: ownerID, finalAccountID: otherOwnerID
        ), [accountMismatchMetadata()])
        XCTAssertEqual(Diagnostics.metadataForRecording(
            responses: [result], configuration: nil,
            initialAccountID: ownerID, finalAccountID: ownerID
        ), [])
    }

    private func validEnvironment() -> [String: String] {
        [
            "ICHART_COMPLIMENTARY_QA_STATUS_TRACE": "1",
            "ICHART_COMPLIMENTARY_QA_RUN_ID": runID.uuidString,
            "ICHART_COMPLIMENTARY_QA_OWNER_ID": ownerID.uuidString
        ]
    }

    private func configuration() throws -> Diagnostics.Configuration {
        try XCTUnwrap(Diagnostics.configuration(environment: validEnvironment()))
    }

    private func accountMismatchMetadata() -> [String: String] {
        [
            "action": "status", "run_id": runID.uuidString.lowercased(),
            "owner_match": "false", "failure": "account_mismatch"
        ]
    }

    private func response(
        schemaVersion: Int = 1,
        campaignID: String = "ichart-complimentary-pro-1m-v1",
        enabled: Bool = true,
        productID: String? = nil,
        offerID: String? = nil,
        serverTime: String = "2026-10-09T12:00:00Z",
        reason: String? = "campaign_not_started",
        signature: IChartComplimentaryOfferServerSignature? = nil,
        attemptID: String? = nil
    ) -> IChartComplimentaryOfferServerResponse {
        IChartComplimentaryOfferServerResponse(
            schemaVersion: schemaVersion, campaignID: campaignID, enabled: enabled,
            decision: .ineligible, productID: productID ?? monthlyID, offerID: offerID,
            activation: nil, state: .unavailable, serverTime: serverTime,
            accessStartsAt: nil, accessEndsAt: nil, estimatedAccessEndsAt: nil,
            accessEndsAtIsEstimated: nil, reason: reason, signature: signature,
            attemptID: attemptID, canPrepare: false
        )
    }
}
#endif

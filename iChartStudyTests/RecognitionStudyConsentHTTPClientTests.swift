import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyConsentHTTPClientTests: XCTestCase {
    func testStrictStatusResponseRoundTripsExplicitNulls() throws {
        let data = notAcceptedResponseData()
        let response = try RecognitionStudyConsentResponse
            .decodeCanonicalData(data)

        XCTAssertEqual(response.status, .notAccepted)
        XCTAssertNil(response.consent)
        XCTAssertNotNil(response.currentPolicy)
        XCTAssertFalse(response.replayed)
        XCTAssertEqual(try response.canonicalData(), data)
    }

    func testStrictResponseRejectsUnknownFieldsUnsafeURLAndStateMismatch() throws {
        let canonical = String(decoding: notAcceptedResponseData(), as: UTF8.self)
        XCTAssertThrowsError(
            try RecognitionStudyConsentResponse.decodeCanonicalData(
                Data(" \(canonical)".utf8)
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyConsentResponse.decodeCanonicalData(
                Data(
                    (String(canonical.dropLast()) + ",\"groundTruth\":\"C7\"}")
                        .utf8
                )
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyConsentResponse.decodeCanonicalData(
                Data(
                    canonical.replacingOccurrences(
                        of: "https://useichart.com/legal/recognition-study-v1.json",
                        with: "http://useichart.com/legal/recognition-study-v1.json"
                    ).utf8
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyConsentContractError,
                .invalidHTTPSURL(
                    "http://useichart.com/legal/recognition-study-v1.json"
                )
            )
        }
        XCTAssertThrowsError(
            try RecognitionStudyConsentResponse.decodeCanonicalData(
                Data(
                    canonical.replacingOccurrences(
                        of: "\"status\":\"not-accepted\"",
                        with: "\"status\":\"active\""
                    ).utf8
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyConsentContractError,
                .consentStateMismatch
            )
        }
    }

    func testConsentRequestsHaveExactCanonicalBytes() throws {
        let status = try RecognitionStudyConsentStatusRequest().canonicalData()
        XCTAssertEqual(
            String(decoding: status, as: UTF8.self),
            #"{"schemaVersion":"recognition-study-consent-status-request-v1"}"#
        )

        let policy = try currentPolicy()
        let requestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000002")
        )
        let accept = try RecognitionStudyConsentAcceptRequest(
            clientRequestID: requestID,
            policy: policy
        ).canonicalData()
        XCTAssertEqual(
            String(decoding: accept, as: UTF8.self),
            #"{"clientRequestID":"10000000-0000-4000-8000-000000000002","explicitRawStrokeDonationAuthorization":true,"presentationID":"raw-stroke-research-pilot-v1","presentationSHA256":"abababababababababababababababababababababababababababababababab","schemaVersion":"recognition-study-consent-accept-request-v1"}"#
        )

        let recordID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")
        )
        let withdraw = try RecognitionStudyConsentWithdrawRequest(
            clientRequestID: requestID,
            consentRecordID: recordID
        ).canonicalData()
        XCTAssertEqual(
            String(decoding: withdraw, as: UTF8.self),
            #"{"clientRequestID":"10000000-0000-4000-8000-000000000002","consentRecordID":"10000000-0000-4000-8000-000000000003","schemaVersion":"recognition-study-consent-withdraw-request-v1"}"#
        )
    }

    func testStatusRequestIsAuthenticatedAndReturnsOnlyReviewedPolicy() async throws {
        let configuration = try makeConfiguration()
        let transport = RecognitionStudyConsentHTTPStub(responses: [
            response(
                configuration: configuration,
                statusCode: 200,
                body: notAcceptedResponseData()
            )
        ])
        let client = RecognitionStudyConsentHTTPClient(
            configuration: configuration,
            transport: transport
        )

        let result = try await client.status(accessToken: "access-token")

        XCTAssertEqual(result.status, .notAccepted)
        XCTAssertEqual(
            result.currentPolicy?.presentationID.rawValue,
            "raw-stroke-research-pilot-v1"
        )
        let sent = try XCTUnwrap(transport.capturedRequests.first)
        XCTAssertEqual(sent.request.url, configuration.consentURL)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(
            sent.request.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-token"
        )
        XCTAssertEqual(
            sent.request.value(forHTTPHeaderField: "apikey"),
            "publishable-test-key"
        )
        XCTAssertEqual(
            sent.request.value(forHTTPHeaderField: "Accept"),
            RecognitionStudyConsentHTTPClient.mediaType
        )
        XCTAssertEqual(
            sent.request.httpBody,
            try RecognitionStudyConsentStatusRequest().canonicalData()
        )
        XCTAssertEqual(
            sent.maximumResponseByteCount,
            RecognitionStudyConsentResponse.maximumCanonicalJSONByteCount
        )
    }

    func testAcceptBindsExactPolicyAndReplayStatus() async throws {
        let configuration = try makeConfiguration()
        let policy = try currentPolicy()
        let requestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000002")
        )
        let transport = RecognitionStudyConsentHTTPStub(responses: [
            response(
                configuration: configuration,
                statusCode: 201,
                body: activeResponseData(replayed: false)
            )
        ])
        let client = RecognitionStudyConsentHTTPClient(
            configuration: configuration,
            transport: transport
        )

        let result = try await client.accept(
            policy: policy,
            clientRequestID: requestID,
            accessToken: "access-token"
        )

        XCTAssertEqual(result.status, .active)
        XCTAssertEqual(result.currentPolicy, policy)
        XCTAssertEqual(
            transport.capturedRequests.first?.request.httpBody,
            try RecognitionStudyConsentAcceptRequest(
                clientRequestID: requestID,
                policy: policy
            ).canonicalData()
        )

        let replayTransport = RecognitionStudyConsentHTTPStub(responses: [
            response(
                configuration: configuration,
                statusCode: 200,
                body: activeResponseData(replayed: true)
            )
        ])
        let replayResult = try await RecognitionStudyConsentHTTPClient(
            configuration: configuration,
            transport: replayTransport
        ).accept(
            policy: policy,
            clientRequestID: requestID,
            accessToken: "access-token"
        )
        XCTAssertTrue(replayResult.replayed)
    }

    func testAcceptRejectsChangedPolicyAndContradictoryReplayStatus() async throws {
        let configuration = try makeConfiguration()
        let policy = try currentPolicy()
        let changedPolicyBody = activeResponseData(replayed: false)
            .replacingOccurrences(
                of: "privacy-notice-v1",
                with: "privacy-notice-v2"
            )
        let changedPolicyTransport = RecognitionStudyConsentHTTPStub(
            responses: [
                response(
                    configuration: configuration,
                    statusCode: 201,
                    body: changedPolicyBody
                )
            ]
        )

        do {
            _ = try await RecognitionStudyConsentHTTPClient(
                configuration: configuration,
                transport: changedPolicyTransport
            ).accept(
                policy: policy,
                clientRequestID: UUID(),
                accessToken: "access-token"
            )
            XCTFail("Expected changed policy to fail.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyConsentContractError,
                .consentStateMismatch
            )
        }

        let statusMismatchTransport = RecognitionStudyConsentHTTPStub(
            responses: [
                response(
                    configuration: configuration,
                    statusCode: 200,
                    body: activeResponseData(replayed: false)
                )
            ]
        )
        do {
            _ = try await RecognitionStudyConsentHTTPClient(
                configuration: configuration,
                transport: statusMismatchTransport
            ).accept(
                policy: policy,
                clientRequestID: UUID(),
                accessToken: "access-token"
            )
            XCTFail("Expected replay/status mismatch to fail.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyCaptureHTTPError,
                .consentReplayStatusMismatch
            )
        }
    }

    func testWithdrawRequiresExactRecordAndWithdrawnState() async throws {
        let configuration = try makeConfiguration()
        let recordID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")
        )
        let transport = RecognitionStudyConsentHTTPStub(responses: [
            response(
                configuration: configuration,
                statusCode: 200,
                body: withdrawnResponseData()
            )
        ])
        let client = RecognitionStudyConsentHTTPClient(
            configuration: configuration,
            transport: transport
        )

        let result = try await client.withdraw(
            consentRecordID: recordID,
            clientRequestID: UUID(),
            accessToken: "access-token"
        )

        XCTAssertEqual(result.status, .withdrawn)
        XCTAssertEqual(result.consent?.consentRecordID.uuid, recordID)
        XCTAssertEqual(
            result.consent?.withdrawnAtUnixMilliseconds,
            1_800_000_100_000
        )
    }

    private func makeConfiguration()
        throws -> RecognitionStudyCaptureHTTPConfiguration
    {
        try RecognitionStudyCaptureHTTPConfiguration(
            baseURL: try XCTUnwrap(URL(string: "https://study.invalid")),
            publishableKey: "publishable-test-key",
            timeoutInterval: 17
        )
    }

    private func currentPolicy() throws -> RecognitionStudyConsentPolicy {
        try XCTUnwrap(
            RecognitionStudyConsentResponse.decodeCanonicalData(
                notAcceptedResponseData()
            ).currentPolicy
        )
    }

    private func response(
        configuration: RecognitionStudyCaptureHTTPConfiguration,
        statusCode: Int,
        body: Data
    ) -> RecognitionStudyCaptureHTTPResponse {
        RecognitionStudyCaptureHTTPResponse(
            url: configuration.consentURL,
            statusCode: statusCode,
            contentType: RecognitionStudyConsentHTTPClient.mediaType,
            cacheControl: "private, no-store",
            body: body
        )
    }

    private func policyJSON() -> String {
        #"{"consentDocumentURL":"https://useichart.com/legal/recognition-study-v1.json","consentLedgerVersion":"consent-ledger-v1","consentTextVersion":"consent-text-v1","dataUsePolicyVersion":"raw-stroke-research-v1","presentationID":"raw-stroke-research-pilot-v1","presentationSHA256":"abababababababababababababababababababababababababababababababab","privacyNoticeVersion":"privacy-notice-v1","rawStrokeDonationRequired":true,"retentionPolicyVersion":"retention-12-months-v1","schemaVersion":"recognition-study-consent-policy-v1","scope":"chord-recognition-research-v1"}"#
    }

    private func consentJSON(
        status: String,
        ledgerEpoch: Int,
        withdrawnAt: String
    ) -> String {
        #"{"acceptedAtUnixMilliseconds":1800000000000,"consentLedgerEpoch":\#(ledgerEpoch),"consentLedgerVersion":"consent-ledger-v1","consentRecordID":"10000000-0000-4000-8000-000000000003","consentRecordSHA256":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd","consentTextVersion":"consent-text-v1","dataUsePolicyVersion":"raw-stroke-research-v1","privacyNoticeVersion":"privacy-notice-v1","rawStrokeDonationAuthorized":true,"retentionPolicyVersion":"retention-12-months-v1","schemaVersion":"recognition-study-consent-record-summary-v1","scope":"chord-recognition-research-v1","status":"\#(status)","withdrawnAtUnixMilliseconds":\#(withdrawnAt)}"#
    }

    private func notAcceptedResponseData() -> Data {
        Data(
            #"{"consent":null,"currentPolicy":\#(policyJSON()),"replayed":false,"schemaVersion":"recognition-study-consent-response-v1","status":"not-accepted"}"#.utf8
        )
    }

    private func activeResponseData(replayed: Bool) -> Data {
        Data(
            #"{"consent":\#(consentJSON(status: "active", ledgerEpoch: 8, withdrawnAt: "null")),"currentPolicy":\#(policyJSON()),"replayed":\#(replayed),"schemaVersion":"recognition-study-consent-response-v1","status":"active"}"#.utf8
        )
    }

    private func withdrawnResponseData() -> Data {
        Data(
            #"{"consent":\#(consentJSON(status: "withdrawn", ledgerEpoch: 9, withdrawnAt: "1800000100000")),"currentPolicy":\#(policyJSON()),"replayed":false,"schemaVersion":"recognition-study-consent-response-v1","status":"withdrawn"}"#.utf8
        )
    }
}

private final class RecognitionStudyConsentHTTPStub:
    RecognitionStudyCaptureHTTPTransport,
    @unchecked Sendable
{
    struct CapturedRequest {
        let request: URLRequest
        let maximumResponseByteCount: Int
    }

    private let lock = NSLock()
    private var responses: [RecognitionStudyCaptureHTTPResponse]
    private var captured: [CapturedRequest] = []

    init(responses: [RecognitionStudyCaptureHTTPResponse]) {
        self.responses = responses
    }

    var capturedRequests: [CapturedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    func send(
        _ request: URLRequest,
        maximumResponseByteCount: Int
    ) async throws -> RecognitionStudyCaptureHTTPResponse {
        try dequeueResponse(
            for: request,
            maximumResponseByteCount: maximumResponseByteCount
        )
    }

    private func dequeueResponse(
        for request: URLRequest,
        maximumResponseByteCount: Int
    ) throws -> RecognitionStudyCaptureHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        captured.append(
            CapturedRequest(
                request: request,
                maximumResponseByteCount: maximumResponseByteCount
            )
        )
        guard !responses.isEmpty else {
            throw URLError(.cannotConnectToHost)
        }
        return responses.removeFirst()
    }
}

private extension Data {
    func replacingOccurrences(
        of target: String,
        with replacement: String
    ) -> Data {
        Data(
            String(decoding: self, as: UTF8.self)
                .replacingOccurrences(of: target, with: replacement)
                .utf8
        )
    }
}

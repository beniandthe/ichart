import Foundation

struct RecognitionStudyConsentHTTPClient: Sendable {
    static let mediaType =
        "application/vnd.ichart.recognition-study-consent+json"

    private let configuration: RecognitionStudyCaptureHTTPConfiguration
    private let transport: any RecognitionStudyCaptureHTTPTransport

    init(
        configuration: RecognitionStudyCaptureHTTPConfiguration,
        transport: any RecognitionStudyCaptureHTTPTransport =
            RecognitionStudyBoundedURLSessionTransport()
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    func status(accessToken: String) async throws
        -> RecognitionStudyConsentResponse
    {
        let body = try RecognitionStudyConsentStatusRequest().canonicalData()
        let (response, decoded) = try await perform(
            body: body,
            accessToken: accessToken,
            acceptedStatusCodes: [200]
        )
        guard !decoded.replayed else {
            throw RecognitionStudyCaptureHTTPError
                .consentReplayStatusMismatch
        }
        guard response.statusCode == 200 else {
            throw RecognitionStudyCaptureHTTPError.unexpectedStatusCode(
                response.statusCode
            )
        }
        return decoded
    }

    func accept(
        policy: RecognitionStudyConsentPolicy,
        clientRequestID: UUID,
        accessToken: String
    ) async throws -> RecognitionStudyConsentResponse {
        let body = try RecognitionStudyConsentAcceptRequest(
            clientRequestID: clientRequestID,
            policy: policy
        ).canonicalData()
        let (response, decoded) = try await perform(
            body: body,
            accessToken: accessToken,
            acceptedStatusCodes: [200, 201]
        )
        try decoded.validateAcceptance(of: policy)
        let expectedStatus = decoded.replayed ? 200 : 201
        guard response.statusCode == expectedStatus else {
            throw RecognitionStudyCaptureHTTPError
                .consentReplayStatusMismatch
        }
        return decoded
    }

    func withdraw(
        consentRecordID: UUID,
        clientRequestID: UUID,
        accessToken: String
    ) async throws -> RecognitionStudyConsentResponse {
        let body = try RecognitionStudyConsentWithdrawRequest(
            clientRequestID: clientRequestID,
            consentRecordID: consentRecordID
        ).canonicalData()
        let (_, decoded) = try await perform(
            body: body,
            accessToken: accessToken,
            acceptedStatusCodes: [200]
        )
        guard decoded.status == .withdrawn,
              decoded.consent?.consentRecordID.uuid == consentRecordID else {
            throw RecognitionStudyConsentContractError
                .consentStateMismatch
        }
        return decoded
    }

    private func perform(
        body: Data,
        accessToken: String,
        acceptedStatusCodes: Set<Int>
    ) async throws -> (
        RecognitionStudyCaptureHTTPResponse,
        RecognitionStudyConsentResponse
    ) {
        let request = try authenticatedRequest(
            body: body,
            accessToken: accessToken
        )
        let response = try await transport.send(
            request,
            maximumResponseByteCount:
                RecognitionStudyConsentResponse.maximumCanonicalJSONByteCount
        )
        guard response.url == configuration.consentURL else {
            throw RecognitionStudyCaptureHTTPError.unexpectedResponseURL
        }
        guard acceptedStatusCodes.contains(response.statusCode) else {
            throw RecognitionStudyCaptureHTTPError.unexpectedStatusCode(
                response.statusCode
            )
        }
        guard response.contentType?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased() == Self.mediaType else {
            throw RecognitionStudyCaptureHTTPError.unexpectedContentType(
                expected: Self.mediaType,
                actual: response.contentType
            )
        }
        let cacheDirectives = response.cacheControl?
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            } ?? []
        guard cacheDirectives.contains("no-store") else {
            throw RecognitionStudyCaptureHTTPError.responseMayBeCached
        }
        return (
            response,
            try RecognitionStudyConsentResponse.decodeCanonicalData(
                response.body
            )
        )
    }

    private func authenticatedRequest(
        body: Data,
        accessToken: String
    ) throws -> URLRequest {
        try RecognitionStudyCaptureHTTPConfiguration
            .validateAccessToken(accessToken)
        var request = URLRequest(
            url: configuration.consentURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: configuration.timeoutInterval
        )
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            configuration.publishableKey,
            forHTTPHeaderField: "apikey"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(Self.mediaType, forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }
}

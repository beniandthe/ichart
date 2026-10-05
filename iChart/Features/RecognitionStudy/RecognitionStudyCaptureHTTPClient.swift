import Foundation

enum RecognitionStudyCaptureHTTPError: Error, Equatable {
    case invalidBaseURL
    case invalidCredential(field: String)
    case invalidTimeoutInterval
    case nonHTTPResponse
    case responseBodyTooLarge(maximum: Int, actualAtLeast: Int)
    case unexpectedResponseURL
    case unexpectedStatusCode(Int)
    case unexpectedContentType(expected: String, actual: String?)
    case responseMayBeCached
    case missingResponseHeader(String)
    case responseHeaderMismatch(String)
    case receiptReplayStatusMismatch
    case consentReplayStatusMismatch
}

struct RecognitionStudyCaptureHTTPConfiguration: Sendable {
    static let grantPath =
        "functions/v1/recognition-study-capture-grant"
    static let uploadPath =
        "functions/v1/recognition-study-capture-upload"
    static let consentPath =
        "functions/v1/recognition-study-consent"

    let grantURL: URL
    let uploadURL: URL
    let consentURL: URL
    let publishableKey: String
    let timeoutInterval: TimeInterval

    init(
        baseURL: URL,
        publishableKey: String,
        timeoutInterval: TimeInterval = 30
    ) throws {
        guard let components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ), components.scheme?.lowercased() == "https",
           components.host?.isEmpty == false,
           components.user == nil,
           components.password == nil,
           components.query == nil,
           components.fragment == nil,
           components.path.isEmpty || components.path == "/" else {
            throw RecognitionStudyCaptureHTTPError.invalidBaseURL
        }
        try Self.validateCredential(
            publishableKey,
            field: "publishableKey"
        )
        guard timeoutInterval.isFinite,
              timeoutInterval >= 1,
              timeoutInterval <= 120 else {
            throw RecognitionStudyCaptureHTTPError.invalidTimeoutInterval
        }

        var canonicalBaseComponents = components
        canonicalBaseComponents.path = "/"
        guard let canonicalBaseURL = canonicalBaseComponents.url else {
            throw RecognitionStudyCaptureHTTPError.invalidBaseURL
        }
        grantURL = canonicalBaseURL.appendingPathComponent(Self.grantPath)
        uploadURL = canonicalBaseURL.appendingPathComponent(Self.uploadPath)
        consentURL = canonicalBaseURL.appendingPathComponent(Self.consentPath)
        self.publishableKey = publishableKey
        self.timeoutInterval = timeoutInterval
    }

    static func validateAccessToken(_ accessToken: String) throws {
        try validateCredential(accessToken, field: "accessToken")
    }

    private static func validateCredential(
        _ value: String,
        field: String
    ) throws {
        guard !value.isEmpty,
              value.utf8.count <= 8 * 1024,
              value.unicodeScalars.allSatisfy({
                  (0x21...0x7E).contains($0.value)
              }) else {
            throw RecognitionStudyCaptureHTTPError.invalidCredential(
                field: field
            )
        }
    }
}

struct RecognitionStudyCaptureHTTPResponse: Sendable {
    let url: URL?
    let statusCode: Int
    let contentType: String?
    let cacheControl: String?
    let authorityArtifactSHA256: String?
    let captureReceiptID: String?
    let body: Data

    init(
        url: URL?,
        statusCode: Int,
        contentType: String?,
        cacheControl: String?,
        authorityArtifactSHA256: String? = nil,
        captureReceiptID: String? = nil,
        body: Data
    ) {
        self.url = url
        self.statusCode = statusCode
        self.contentType = contentType
        self.cacheControl = cacheControl
        self.authorityArtifactSHA256 = authorityArtifactSHA256
        self.captureReceiptID = captureReceiptID
        self.body = body
    }

    init(httpResponse: HTTPURLResponse, body: Data) {
        self.init(
            url: httpResponse.url,
            statusCode: httpResponse.statusCode,
            contentType: httpResponse.value(
                forHTTPHeaderField: "Content-Type"
            ),
            cacheControl: httpResponse.value(
                forHTTPHeaderField: "Cache-Control"
            ),
            authorityArtifactSHA256: httpResponse.value(
                forHTTPHeaderField: "X-IChart-Authority-Artifact-SHA256"
            ),
            captureReceiptID: httpResponse.value(
                forHTTPHeaderField: "X-IChart-Capture-Receipt-ID"
            ),
            body: body
        )
    }
}

protocol RecognitionStudyCaptureHTTPTransport: Sendable {
    func send(
        _ request: URLRequest,
        maximumResponseByteCount: Int
    ) async throws -> RecognitionStudyCaptureHTTPResponse
}

/// A bounded, no-redirect URLSession transport. The body is consumed as an
/// async byte stream so a hostile or misconfigured endpoint cannot force an
/// unbounded response allocation before the contract limit is enforced.
final class RecognitionStudyBoundedURLSessionTransport:
    RecognitionStudyCaptureHTTPTransport,
    @unchecked Sendable
{
    private let noRedirectDelegate = RecognitionStudyNoRedirectDelegate()
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func send(
        _ request: URLRequest,
        maximumResponseByteCount: Int
    ) async throws -> RecognitionStudyCaptureHTTPResponse {
        precondition(maximumResponseByteCount > 0)
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: noRedirectDelegate
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecognitionStudyCaptureHTTPError.nonHTTPResponse
        }
        let expectedLength = httpResponse.expectedContentLength
        if expectedLength > Int64(maximumResponseByteCount) {
            throw RecognitionStudyCaptureHTTPError.responseBodyTooLarge(
                maximum: maximumResponseByteCount,
                actualAtLeast: Self.boundedInt(expectedLength)
            )
        }

        var body = Data()
        if expectedLength > 0 {
            body.reserveCapacity(Int(expectedLength))
        }
        for try await byte in bytes {
            guard body.count < maximumResponseByteCount else {
                throw RecognitionStudyCaptureHTTPError.responseBodyTooLarge(
                    maximum: maximumResponseByteCount,
                    actualAtLeast: maximumResponseByteCount == Int.max
                        ? Int.max
                        : maximumResponseByteCount + 1
                )
            }
            body.append(byte)
        }
        return RecognitionStudyCaptureHTTPResponse(
            httpResponse: httpResponse,
            body: body
        )
    }

    private static func boundedInt(_ value: Int64) -> Int {
        value > Int64(Int.max) ? Int.max : Int(value)
    }
}

final class RecognitionStudyNoRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct RecognitionStudyCaptureGrantHTTPResult: Sendable {
    let verifiedGrant: RecognitionStudyVerifiedCaptureGrant
    let replayed: Bool
}

struct RecognitionStudyCaptureHTTPClient: Sendable {
    static let grantMediaType =
        "application/vnd.ichart.recognition-study-capture-grant+json"
    static let receiptMediaType =
        "application/vnd.ichart.recognition-study-capture-receipt+json"

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

    func requestGrant(
        clientRequestID: UUID,
        accessToken: String,
        trustedPublicKeysByID: [String: Data],
        validationUnixSeconds: Int64,
        actualBundleIdentifier: String,
        actualBuildNumber: String
    ) async throws -> RecognitionStudyCaptureGrantHTTPResult {
        let body = try RecognitionStudyCaptureGrantRequest(
            clientRequestID: clientRequestID
        ).canonicalData()
        let request = try authenticatedRequest(
            url: configuration.grantURL,
            accessToken: accessToken,
            accept: Self.grantMediaType,
            body: body
        )
        let response = try await transport.send(
            request,
            maximumResponseByteCount:
                RecognitionStudySignedCaptureGrant
                    .maximumCanonicalJSONByteCount
        )
        try validateSuccessfulResponse(
            response,
            expectedURL: configuration.grantURL,
            expectedContentType: Self.grantMediaType
        )
        let grant = try RecognitionStudySignedCaptureGrant
            .decodeCanonicalData(response.body)
        let artifactDigest = try grant.signedArtifactSHA256().rawValue
        guard let responseDigest = response.authorityArtifactSHA256 else {
            throw RecognitionStudyCaptureHTTPError.missingResponseHeader(
                "X-IChart-Authority-Artifact-SHA256"
            )
        }
        guard responseDigest == artifactDigest else {
            throw RecognitionStudyCaptureHTTPError.responseHeaderMismatch(
                "X-IChart-Authority-Artifact-SHA256"
            )
        }
        let verifiedGrant = try RecognitionStudyVerifiedCaptureGrant.verify(
            grant,
            trustedPublicKeysByID: trustedPublicKeysByID,
            validationUnixSeconds: validationUnixSeconds,
            actualBundleIdentifier: actualBundleIdentifier,
            actualBuildNumber: actualBuildNumber
        )
        return RecognitionStudyCaptureGrantHTTPResult(
            verifiedGrant: verifiedGrant,
            replayed: response.statusCode == 200
        )
    }

    func uploadCapture(
        verifiedGrant: RecognitionStudyVerifiedCaptureGrant,
        ticket: RecognitionStudyCaptureGrantPromptTicket,
        envelope: RecognitionStudyAuthorizedCaptureEnvelope,
        packet: ChordInkCanonicalTrajectoryPacket,
        accessToken: String
    ) async throws -> RecognitionStudyCaptureReceipt {
        let preparedUpload = try RecognitionStudyPreparedCaptureUpload(
            verifiedGrant: verifiedGrant,
            ticket: ticket,
            envelope: envelope,
            packet: packet
        )
        return try await uploadPreparedCapture(
            preparedUpload,
            accessToken: accessToken
        )
    }

    /// Sends exactly the immutable bytes produced while the grant was valid.
    /// This is the only retry path: it cannot substitute a new packet,
    /// envelope, grant, or credential into a pending capture.
    func uploadPreparedCapture(
        _ preparedUpload: RecognitionStudyPreparedCaptureUpload,
        accessToken: String
    ) async throws -> RecognitionStudyCaptureReceipt {
        let request = try authenticatedRequest(
            url: configuration.uploadURL,
            accessToken: accessToken,
            accept: Self.receiptMediaType,
            body: preparedUpload.canonicalRequestBody
        )
        let response = try await transport.send(
            request,
            maximumResponseByteCount:
                RecognitionStudyCaptureReceipt.maximumCanonicalJSONByteCount
        )
        try validateSuccessfulResponse(
            response,
            expectedURL: configuration.uploadURL,
            expectedContentType: Self.receiptMediaType
        )
        let receipt = try RecognitionStudyCaptureReceipt
            .decodeCanonicalData(response.body)
        try receipt.validateBinding(
            envelope: preparedUpload.envelope,
            packet: preparedUpload.packet
        )
        let expectedStatus = receipt.replayed ? 200 : 201
        guard response.statusCode == expectedStatus else {
            throw RecognitionStudyCaptureHTTPError
                .receiptReplayStatusMismatch
        }
        guard let responseReceiptID = response.captureReceiptID else {
            throw RecognitionStudyCaptureHTTPError.missingResponseHeader(
                "X-IChart-Capture-Receipt-ID"
            )
        }
        guard responseReceiptID == receipt.receiptID.rawValue else {
            throw RecognitionStudyCaptureHTTPError.responseHeaderMismatch(
                "X-IChart-Capture-Receipt-ID"
            )
        }
        return receipt
    }

    private func authenticatedRequest(
        url: URL,
        accessToken: String,
        accept: String,
        body: Data
    ) throws -> URLRequest {
        try RecognitionStudyCaptureHTTPConfiguration
            .validateAccessToken(accessToken)
        var request = URLRequest(
            url: url,
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
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func validateSuccessfulResponse(
        _ response: RecognitionStudyCaptureHTTPResponse,
        expectedURL: URL,
        expectedContentType: String
    ) throws {
        guard response.url == expectedURL else {
            throw RecognitionStudyCaptureHTTPError.unexpectedResponseURL
        }
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw RecognitionStudyCaptureHTTPError.unexpectedStatusCode(
                response.statusCode
            )
        }
        guard response.contentType?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased() == expectedContentType else {
            throw RecognitionStudyCaptureHTTPError.unexpectedContentType(
                expected: expectedContentType,
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
    }
}

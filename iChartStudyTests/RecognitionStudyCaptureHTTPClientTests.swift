import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyCaptureHTTPClientTests: XCTestCase {
    func testConfigurationRequiresPinnedHTTPSOriginAndSafeCredentials() throws {
        XCTAssertThrowsError(
            try RecognitionStudyCaptureHTTPConfiguration(
                baseURL: try XCTUnwrap(
                    URL(string: "http://study.invalid")
                ),
                publishableKey: "publishable-test-key"
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureHTTPError,
                .invalidBaseURL
            )
        }
        XCTAssertThrowsError(
            try RecognitionStudyCaptureHTTPConfiguration(
                baseURL: try XCTUnwrap(
                    URL(string: "https://study.invalid/untrusted/path")
                ),
                publishableKey: "publishable-test-key"
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudyCaptureHTTPConfiguration(
                baseURL: try XCTUnwrap(
                    URL(string: "https://study.invalid")
                ),
                publishableKey: "bad\nkey"
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureHTTPError,
                .invalidCredential(field: "publishableKey")
            )
        }

        let configuration = try makeConfiguration()
        XCTAssertEqual(
            configuration.grantURL.absoluteString,
            "https://study.invalid/functions/v1/recognition-study-capture-grant"
        )
        XCTAssertEqual(
            configuration.uploadURL.absoluteString,
            "https://study.invalid/functions/v1/recognition-study-capture-upload"
        )
    }

    func testGrantRequestAuthenticatesAndVerifiesExactAuthorityArtifact() async throws {
        let configuration = try makeConfiguration()
        let grant = try signedGrant()
        let transport = RecognitionStudyCaptureHTTPStub(responses: [
            RecognitionStudyCaptureHTTPResponse(
                url: configuration.grantURL,
                statusCode: 201,
                contentType: RecognitionStudyCaptureHTTPClient.grantMediaType,
                cacheControl: "private, no-store",
                authorityArtifactSHA256: try grant
                    .signedArtifactSHA256().rawValue,
                body: Data(TestGrant.validArtifact.utf8)
            )
        ])
        let client = RecognitionStudyCaptureHTTPClient(
            configuration: configuration,
            transport: transport
        )
        let requestID = try XCTUnwrap(
            UUID(uuidString: "66666666-6666-4666-8666-666666666666")
        )

        let result = try await client.requestGrant(
            clientRequestID: requestID,
            accessToken: "access-token",
            trustedPublicKeysByID: [
                TestGrant.signingKeyID: try publicKey()
            ],
            validationUnixSeconds: TestGrant.validationTime,
            actualBundleIdentifier: TestGrant.bundleIdentifier,
            actualBuildNumber: "51"
        )

        XCTAssertFalse(result.replayed)
        XCTAssertEqual(
            result.verifiedGrant.payload.authorizationID.rawValue,
            "11111111-1111-4111-8111-111111111111"
        )
        let sent = try XCTUnwrap(transport.capturedRequests.first)
        XCTAssertEqual(sent.request.url, configuration.grantURL)
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
            RecognitionStudyCaptureHTTPClient.grantMediaType
        )
        XCTAssertEqual(
            sent.request.value(forHTTPHeaderField: "Accept-Encoding"),
            "identity"
        )
        XCTAssertEqual(
            sent.request.httpBody,
            try RecognitionStudyCaptureGrantRequest(
                clientRequestID: requestID
            ).canonicalData()
        )
        XCTAssertEqual(
            sent.maximumResponseByteCount,
            RecognitionStudySignedCaptureGrant.maximumCanonicalJSONByteCount
        )
        XCTAssertEqual(sent.request.timeoutInterval, 17, accuracy: 0.001)
    }

    func testGrantRequestRejectsInvalidTokenBeforeTransport() async throws {
        let configuration = try makeConfiguration()
        let transport = RecognitionStudyCaptureHTTPStub(responses: [])
        let client = RecognitionStudyCaptureHTTPClient(
            configuration: configuration,
            transport: transport
        )

        do {
            _ = try await client.requestGrant(
                clientRequestID: UUID(),
                accessToken: "bad\r\ntoken",
                trustedPublicKeysByID: [:],
                validationUnixSeconds: TestGrant.validationTime,
                actualBundleIdentifier: TestGrant.bundleIdentifier,
                actualBuildNumber: "51"
            )
            XCTFail("Expected credential validation to fail.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyCaptureHTTPError,
                .invalidCredential(field: "accessToken")
            )
        }
        XCTAssertTrue(transport.capturedRequests.isEmpty)
    }

    func testGrantResponseRejectsRedirectedOriginAndHeaderMismatch() async throws {
        let configuration = try makeConfiguration()
        let grant = try signedGrant()
        let redirectedTransport = RecognitionStudyCaptureHTTPStub(responses: [
            RecognitionStudyCaptureHTTPResponse(
                url: URL(string: "https://other.invalid/grant"),
                statusCode: 201,
                contentType: RecognitionStudyCaptureHTTPClient.grantMediaType,
                cacheControl: "no-store",
                authorityArtifactSHA256: try grant
                    .signedArtifactSHA256().rawValue,
                body: Data(TestGrant.validArtifact.utf8)
            )
        ])
        let redirectedClient = RecognitionStudyCaptureHTTPClient(
            configuration: configuration,
            transport: redirectedTransport
        )
        await XCTAssertThrowsHTTPError(
            .unexpectedResponseURL,
            from: redirectedClient
        )

        let mismatchedHeaderTransport = RecognitionStudyCaptureHTTPStub(
            responses: [
                RecognitionStudyCaptureHTTPResponse(
                    url: configuration.grantURL,
                    statusCode: 201,
                    contentType:
                        RecognitionStudyCaptureHTTPClient.grantMediaType,
                    cacheControl: "no-store",
                    authorityArtifactSHA256: String(repeating: "0", count: 64),
                    body: Data(TestGrant.validArtifact.utf8)
                )
            ]
        )
        let mismatchedHeaderClient = RecognitionStudyCaptureHTTPClient(
            configuration: configuration,
            transport: mismatchedHeaderTransport
        )
        await XCTAssertThrowsHTTPError(
            .responseHeaderMismatch(
                "X-IChart-Authority-Artifact-SHA256"
            ),
            from: mismatchedHeaderClient
        )
    }

    func testUploadAuthenticatesAndReturnsOnlyBoundReceipt() async throws {
        let fixture = try makeCaptureFixture()
        let configuration = try makeConfiguration()
        let receipt = try receiptData(
            fixture: fixture,
            replayed: false,
            grantCompleted: false
        )
        let transport = RecognitionStudyCaptureHTTPStub(responses: [
            RecognitionStudyCaptureHTTPResponse(
                url: configuration.uploadURL,
                statusCode: 201,
                contentType: RecognitionStudyCaptureHTTPClient.receiptMediaType,
                cacheControl: "no-store",
                captureReceiptID: "77777777-7777-4777-8777-777777777777",
                body: receipt
            )
        ])
        let client = RecognitionStudyCaptureHTTPClient(
            configuration: configuration,
            transport: transport
        )

        let result = try await client.uploadCapture(
            verifiedGrant: fixture.verifiedGrant,
            ticket: fixture.ticket,
            envelope: fixture.envelope,
            packet: fixture.packet,
            accessToken: "access-token"
        )

        XCTAssertFalse(result.replayed)
        XCTAssertFalse(result.grantCompleted)
        XCTAssertEqual(
            result.captureAuthorizationID,
            fixture.envelope.captureAuthorizationID
        )
        let sent = try XCTUnwrap(transport.capturedRequests.first)
        XCTAssertEqual(sent.request.url, configuration.uploadURL)
        XCTAssertEqual(
            sent.request.httpBody,
            try RecognitionStudyCaptureUploadRequest(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                envelope: fixture.envelope,
                packet: fixture.packet
            ).canonicalData()
        )
        XCTAssertEqual(
            sent.maximumResponseByteCount,
            RecognitionStudyCaptureReceipt.maximumCanonicalJSONByteCount
        )
    }

    func testPreparedUploadRetrySendsTheOriginalBodyWithoutRebuildingGrant() async throws {
        let fixture = try makeCaptureFixture()
        let prepared = try RecognitionStudyPreparedCaptureUpload(
            verifiedGrant: fixture.verifiedGrant,
            ticket: fixture.ticket,
            envelope: fixture.envelope,
            packet: fixture.packet
        )
        let restored = try RecognitionStudyPreparedCaptureUpload(
            restoringCanonicalRequestBody: prepared.canonicalRequestBody,
            canonicalEnvelopeData: fixture.envelope.canonicalData(),
            canonicalPacketData: fixture.packet.canonicalData()
        )
        let configuration = try makeConfiguration()
        let transport = RecognitionStudyCaptureHTTPStub(responses: [
            RecognitionStudyCaptureHTTPResponse(
                url: configuration.uploadURL,
                statusCode: 200,
                contentType: RecognitionStudyCaptureHTTPClient.receiptMediaType,
                cacheControl: "no-store",
                captureReceiptID: "77777777-7777-4777-8777-777777777777",
                body: try receiptData(
                    fixture: fixture,
                    replayed: true,
                    grantCompleted: false
                )
            )
        ])
        let client = RecognitionStudyCaptureHTTPClient(
            configuration: configuration,
            transport: transport
        )

        let receipt = try await client.uploadPreparedCapture(
            restored,
            accessToken: "fresh-access-token"
        )

        XCTAssertTrue(receipt.replayed)
        let sent = try XCTUnwrap(transport.capturedRequests.first)
        XCTAssertEqual(sent.request.httpBody, prepared.canonicalRequestBody)
        XCTAssertEqual(
            sent.request.value(forHTTPHeaderField: "Authorization"),
            "Bearer fresh-access-token"
        )
    }

    func testUploadRejectsStatusThatContradictsReceiptReplayState() async throws {
        let fixture = try makeCaptureFixture()
        let configuration = try makeConfiguration()
        let transport = RecognitionStudyCaptureHTTPStub(responses: [
            RecognitionStudyCaptureHTTPResponse(
                url: configuration.uploadURL,
                statusCode: 200,
                contentType: RecognitionStudyCaptureHTTPClient.receiptMediaType,
                cacheControl: "no-store",
                captureReceiptID: "77777777-7777-4777-8777-777777777777",
                body: try receiptData(
                    fixture: fixture,
                    replayed: false,
                    grantCompleted: false
                )
            )
        ])
        let client = RecognitionStudyCaptureHTTPClient(
            configuration: configuration,
            transport: transport
        )

        do {
            _ = try await client.uploadCapture(
                verifiedGrant: fixture.verifiedGrant,
                ticket: fixture.ticket,
                envelope: fixture.envelope,
                packet: fixture.packet,
                accessToken: "access-token"
            )
            XCTFail("Expected replay/status mismatch to fail.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyCaptureHTTPError,
                .receiptReplayStatusMismatch
            )
        }
    }

    func testBoundedURLSessionTransportStopsOversizedResponse() async throws {
        RecognitionStudyCaptureHTTPURLProtocolStub.body = Data(
            repeating: UInt8(ascii: "x"),
            count: 9
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [
            RecognitionStudyCaptureHTTPURLProtocolStub.self
        ]
        let transport = RecognitionStudyBoundedURLSessionTransport(
            configuration: sessionConfiguration
        )
        let request = URLRequest(
            url: try XCTUnwrap(URL(string: "https://study.invalid/test"))
        )

        do {
            _ = try await transport.send(
                request,
                maximumResponseByteCount: 8
            )
            XCTFail("Expected response body limit to fail.")
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyCaptureHTTPError,
                .responseBodyTooLarge(maximum: 8, actualAtLeast: 9)
            )
        }
    }

    func testNoRedirectDelegateAlwaysRejectsRedirectRequest() throws {
        let originalURL = try XCTUnwrap(
            URL(string: "https://study.invalid/original")
        )
        let redirectURL = try XCTUnwrap(
            URL(string: "https://other.invalid/redirect")
        )
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: originalURL,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": redirectURL.absoluteString]
            )
        )
        let task = URLSession.shared.dataTask(with: originalURL)
        let completion = expectation(description: "redirect decision")
        let delegate = RecognitionStudyNoRedirectDelegate()

        delegate.urlSession(
            .shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirectURL)
        ) { followedRequest in
            XCTAssertNil(followedRequest)
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)
    }

    private func XCTAssertThrowsHTTPError(
        _ expected: RecognitionStudyCaptureHTTPError,
        from client: RecognitionStudyCaptureHTTPClient,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await client.requestGrant(
                clientRequestID: UUID(),
                accessToken: "access-token",
                trustedPublicKeysByID: [
                    TestGrant.signingKeyID: try publicKey()
                ],
                validationUnixSeconds: TestGrant.validationTime,
                actualBundleIdentifier: TestGrant.bundleIdentifier,
                actualBuildNumber: "51"
            )
            XCTFail("Expected request to fail.", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? RecognitionStudyCaptureHTTPError,
                expected,
                file: file,
                line: line
            )
        }
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

    private func signedGrant() throws -> RecognitionStudySignedCaptureGrant {
        try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
            Data(TestGrant.validArtifact.utf8)
        )
    }

    private func publicKey() throws -> Data {
        try XCTUnwrap(Data(base64Encoded: TestGrant.publicKeyBase64))
    }

    private struct CaptureFixture {
        let verifiedGrant: RecognitionStudyVerifiedCaptureGrant
        let ticket: RecognitionStudyCaptureGrantPromptTicket
        let packet: ChordInkCanonicalTrajectoryPacket
        let envelope: RecognitionStudyAuthorizedCaptureEnvelope
    }

    private func makeCaptureFixture() throws -> CaptureFixture {
        let verifiedGrant = try RecognitionStudyVerifiedCaptureGrant.verify(
            signedGrant(),
            trustedPublicKeysByID: [TestGrant.signingKeyID: try publicKey()],
            validationUnixSeconds: TestGrant.validationTime,
            actualBundleIdentifier: TestGrant.bundleIdentifier,
            actualBuildNumber: "51"
        )
        let ticket = verifiedGrant.payload.captureTickets[0]
        let packet = try ChordInkCanonicalTrajectoryPacket(strokes: [
            InkStroke(
                points: [InkPoint(x: 1, y: 2, timeOffset: 0.25)],
                creationTimeOffset: 0
            )
        ])
        let envelope = try RecognitionStudyAuthorizedCaptureEnvelope(
            verifiedGrant: verifiedGrant,
            ticket: ticket,
            clientAppContext: RecognitionStudyClientAppContext(
                appVersion: "1.0",
                buildNumber: "51",
                operatingSystemMajorVersion: 26,
                operatingSystemMinorVersion: 0
            ),
            clientObservedSurface: RecognitionStudyPresentedSurface(
                presentedChartStyle: .simpleChordSheet,
                clientObservedOrientation: .portrait,
                canvasWidth: 768,
                canvasHeight: 1024,
                presentedPaceInstruction: .natural,
                presentedSizeInstruction: .normal,
                presentedConstructionInstruction: .rootFirst
            ),
            clientCapturedAtUnixMilliseconds: 1_800_000_200_000,
            packet: packet
        )
        return CaptureFixture(
            verifiedGrant: verifiedGrant,
            ticket: ticket,
            packet: packet,
            envelope: envelope
        )
    }

    private func receiptData(
        fixture: CaptureFixture,
        replayed: Bool,
        grantCompleted: Bool
    ) throws -> Data {
        let packetData = try fixture.packet.canonicalData()
        let envelopeDigest = RecognitionStudySHA256(
            digesting: try fixture.envelope.canonicalData()
        ).rawValue
        let packetDigest = RecognitionStudySHA256(
            digesting: packetData
        ).rawValue
        let text = #"{"accepted":true,"canonicalPacketByteCount":\#(packetData.count),"canonicalPacketSHA256":"\#(packetDigest)","captureAuthorizationID":"44444444-4444-4444-8444-444444444444","envelopeSHA256":"\#(envelopeDigest)","grantCompleted":\#(grantCompleted),"receiptID":"77777777-7777-4777-8777-777777777777","receivedAtUnixMilliseconds":1800000201000,"replayed":\#(replayed),"schemaVersion":"recognition-study-capture-receipt-v1"}"#
        return Data(text.utf8)
    }
}

private final class RecognitionStudyCaptureHTTPStub:
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

private final class RecognitionStudyCaptureHTTPURLProtocolStub: URLProtocol {
    static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

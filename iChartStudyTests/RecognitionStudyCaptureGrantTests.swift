import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyCaptureGrantTests: XCTestCase {
    func testStaticGoldenVectorVerifiesAndBindsExactCanonicalBytes() throws {
        let artifactData = data(CaptureGrantVectors.validArtifact)
        let grant = try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
            artifactData
        )

        XCTAssertEqual(try grant.canonicalData(), artifactData)
        XCTAssertEqual(
            String(decoding: try grant.payload.canonicalData(), as: UTF8.self),
            CaptureGrantVectors.validPayload
        )
        XCTAssertEqual(
            grant.signatureBase64.base64Value,
            CaptureGrantVectors.validSignatureBase64
        )
        XCTAssertEqual(
            try grant.signedArtifactSHA256().rawValue,
            CaptureGrantVectors.validArtifactSHA256
        )

        let payload = try grant.verify(
            trustedPublicKeysByID: [
                CaptureGrantVectors.signingKeyID:
                    try XCTUnwrap(
                        Data(base64Encoded: CaptureGrantVectors.publicKeyBase64)
                    )
            ],
            validationUnixSeconds: 1_800_000_200
        )
        XCTAssertEqual(payload.expectedCaptureCount, 2)
        XCTAssertEqual(payload.captureTickets.map(\.ordinal), [0, 1])
        XCTAssertEqual(
            payload.captureTickets.map { $0.promptID.rawValue },
            ["isolated-c-seven", "row-b-flat-seven-e-flat-seven"]
        )
    }

    func testStaticTamperedExpiredAndWrongKeyVectorsFailClosed() throws {
        let publicKey = try XCTUnwrap(
            Data(base64Encoded: CaptureGrantVectors.publicKeyBase64)
        )
        let trustedKeys = [CaptureGrantVectors.signingKeyID: publicKey]

        let tampered = try RecognitionStudySignedCaptureGrant
            .decodeCanonicalData(data(CaptureGrantVectors.tamperedArtifact))
        XCTAssertThrowsError(
            try tampered.verify(
                trustedPublicKeysByID: trustedKeys,
                validationUnixSeconds: 1_800_000_200
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureGrantContractError,
                .signatureVerificationFailed
            )
        }

        let expired = try RecognitionStudySignedCaptureGrant
            .decodeCanonicalData(data(CaptureGrantVectors.expiredArtifact))
        XCTAssertThrowsError(
            try expired.verify(
                trustedPublicKeysByID: trustedKeys,
                validationUnixSeconds: 1_800_000_200
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureGrantContractError,
                .authorizationExpired
            )
        }

        let valid = try RecognitionStudySignedCaptureGrant
            .decodeCanonicalData(data(CaptureGrantVectors.validArtifact))
        let wrongKey = try XCTUnwrap(
            Data(base64Encoded: CaptureGrantVectors.wrongPublicKeyBase64)
        )
        XCTAssertThrowsError(
            try valid.verify(
                trustedPublicKeysByID: [
                    CaptureGrantVectors.signingKeyID: wrongKey
                ],
                validationUnixSeconds: 1_800_000_200
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureGrantContractError,
                .signatureVerificationFailed
            )
        }
    }

    func testVerificationRequiresTrustedKeyAndFixedValidityWindow() throws {
        let grant = try RecognitionStudySignedCaptureGrant
            .decodeCanonicalData(data(CaptureGrantVectors.validArtifact))
        let publicKey = try XCTUnwrap(
            Data(base64Encoded: CaptureGrantVectors.publicKeyBase64)
        )

        XCTAssertThrowsError(
            try grant.verify(
                trustedPublicKeysByID: [:],
                validationUnixSeconds: 1_800_000_200
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureGrantContractError,
                .untrustedSigningKey(CaptureGrantVectors.signingKeyID)
            )
        }
        XCTAssertThrowsError(
            try grant.verify(
                trustedPublicKeysByID: [
                    CaptureGrantVectors.signingKeyID: publicKey
                ],
                validationUnixSeconds: 1_800_000_099
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureGrantContractError,
                .authorizationNotYetValid
            )
        }
        XCTAssertNoThrow(
            try grant.verify(
                trustedPublicKeysByID: [
                    CaptureGrantVectors.signingKeyID: publicKey
                ],
                validationUnixSeconds: 1_800_000_100
            )
        )
        XCTAssertThrowsError(
            try grant.verify(
                trustedPublicKeysByID: [
                    CaptureGrantVectors.signingKeyID: publicKey
                ],
                validationUnixSeconds: 1_800_003_600
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureGrantContractError,
                .authorizationExpired
            )
        }
    }

    func testStrictDecodeRejectsUnknownAndNoncanonicalJSON() throws {
        let canonical = CaptureGrantVectors.validArtifact

        XCTAssertThrowsError(
            try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
                data(" \(canonical)")
            )
        )
        XCTAssertThrowsError(
            try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
                data(String(canonical.dropLast()) + ",\"unknown\":true}")
            )
        )

        let nestedUnknown = try mutateCanonicalArtifact { artifact in
            var payload = try object(artifact, key: "payload")
            var client = try object(payload, key: "clientRequirements")
            client["accountID"] = "must-not-survive"
            payload["clientRequirements"] = client
            artifact["payload"] = payload
        }
        XCTAssertThrowsError(
            try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
                nestedUnknown
            )
        )

        let oversized = Data(
            repeating: UInt8(ascii: "{"),
            count: RecognitionStudySignedCaptureGrant
                .maximumCanonicalJSONByteCount + 1
        )
        XCTAssertThrowsError(
            try RecognitionStudySignedCaptureGrant.decodeCanonicalData(oversized)
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCanonicalValueError,
                .canonicalJSONTooLarge(
                    maximumByteCount: RecognitionStudySignedCaptureGrant
                        .maximumCanonicalJSONByteCount,
                    actualByteCount: oversized.count
                )
            )
        }
    }

    func testDisplayTextAcceptsNFCNotationAndRejectsNoncanonicalUnicode() throws {
        let nfcArtifact = try mutateCanonicalArtifact { artifact in
            var payload = try object(artifact, key: "payload")
            var tickets = try objects(payload, key: "captureTickets")
            tickets[0]["displayText"] = "D♭△9"
            payload["captureTickets"] = tickets
            artifact["payload"] = payload
        }
        let decoded = try RecognitionStudySignedCaptureGrant
            .decodeCanonicalData(nfcArtifact)
        XCTAssertEqual(
            decoded.payload.captureTickets[0].displayText.rawValue,
            "D♭△9"
        )

        let decomposedArtifact = try mutateCanonicalArtifact { artifact in
            var payload = try object(artifact, key: "payload")
            var tickets = try objects(payload, key: "captureTickets")
            tickets[0]["displayText"] = "e\u{301}"
            payload["captureTickets"] = tickets
            artifact["payload"] = payload
        }
        XCTAssertThrowsError(
            try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
                decomposedArtifact
            )
        ) { error in
            XCTAssertEqual(
                error as? RecognitionStudyCaptureGrantContractError,
                .invalidDisplayText
            )
        }

        for disallowed in ["\u{105C0}", "\u{10FFFF}", "🙂"] {
            let artifact = try mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var tickets = try objects(payload, key: "captureTickets")
                tickets[0]["displayText"] = disallowed
                payload["captureTickets"] = tickets
                artifact["payload"] = payload
            }
            XCTAssertThrowsError(
                try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
                    artifact
                )
            ) { error in
                XCTAssertEqual(
                    error as? RecognitionStudyCaptureGrantContractError,
                    .invalidDisplayText
                )
            }
        }
    }

    func testPromptPlanMustBeOneCompleteOrderedUniquePlan() throws {
        let invalidArtifacts = try [
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                payload["expectedCaptureCount"] = 3
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var tickets = try objects(payload, key: "captureTickets")
                tickets[1]["ordinal"] = 0
                payload["captureTickets"] = tickets
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var tickets = try objects(payload, key: "captureTickets")
                tickets[1]["captureAuthorizationID"] =
                    tickets[0]["captureAuthorizationID"]
                payload["captureTickets"] = tickets
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var tickets = try objects(payload, key: "captureTickets")
                tickets[1]["promptID"] = tickets[0]["promptID"]
                payload["captureTickets"] = tickets
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                payload["expectedCaptureCount"] = 0
                payload["captureTickets"] = []
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var tickets = try objects(payload, key: "captureTickets")
                tickets[0]["captureAuthorizationID"] =
                    payload["authorizationID"]
                payload["captureTickets"] = tickets
                artifact["payload"] = payload
            }
        ]

        for artifact in invalidArtifacts {
            XCTAssertThrowsError(
                try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
                    artifact
                )
            )
        }
    }

    func testGrantRequiresOrderedWindowExpectedClientAndConsentPolicies() throws {
        let invalidArtifacts = try [
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                payload["issuedAtUnixSeconds"] = 1_800_000_101
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                payload["expiresAtUnixSeconds"] = 1_800_000_100
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var client = try object(payload, key: "clientRequirements")
                client["expectedBundleIdentifier"] = "com.ichart.app"
                payload["clientRequirements"] = client
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var client = try object(payload, key: "clientRequirements")
                client["minimumBuildNumber"] = 0
                payload["clientRequirements"] = client
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                payload["authorizationEpoch"] = 9_007_199_254_740_992 as UInt64
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                payload["expiresAtUnixSeconds"] = 9_007_199_254_740_992 as UInt64
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var client = try object(payload, key: "clientRequirements")
                client["captureContractVersion"] = "engineering-dry-run-v1"
                payload["clientRequirements"] = client
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var consent = try object(payload, key: "consentBinding")
                consent["rawStrokeDonationAuthorized"] = false
                payload["consentBinding"] = consent
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var consent = try object(payload, key: "consentBinding")
                consent["consentLedgerEpoch"] = 0
                payload["consentBinding"] = consent
                artifact["payload"] = payload
            },
            mutateCanonicalArtifact { artifact in
                var payload = try object(artifact, key: "payload")
                var consent = try object(payload, key: "consentBinding")
                consent["retentionPolicyVersion"] = "Not Versioned"
                payload["consentBinding"] = consent
                artifact["payload"] = payload
            }
        ]

        for artifact in invalidArtifacts {
            XCTAssertThrowsError(
                try RecognitionStudySignedCaptureGrant.decodeCanonicalData(
                    artifact
                )
            )
        }
    }

    func testGrantWireContainsNoParticipantRoleTruthOrEligibilityAuthority() throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: data(CaptureGrantVectors.validArtifact)
            ) as? [String: Any]
        )
        let keys = recursiveKeys(object).map { $0.lowercased() }

        for forbidden in [
            "writer", "person", "hmac", "account", "split", "role",
            "groundtruth", "canonicalLabel", "corpuseligible",
            "modelsupervision", "evaluationeligible"
        ] {
            XCTAssertFalse(
                keys.contains { $0.contains(forbidden.lowercased()) },
                "Signed grant unexpectedly exposes authority field \(forbidden)."
            )
        }
    }

    private func data(_ value: String) -> Data {
        Data(value.utf8)
    }

    private func mutateCanonicalArtifact(
        _ mutate: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var artifact = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: data(CaptureGrantVectors.validArtifact)
            ) as? [String: Any]
        )
        try mutate(&artifact)
        return try JSONSerialization.data(
            withJSONObject: artifact,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func object(
        _ parent: [String: Any],
        key: String
    ) throws -> [String: Any] {
        try XCTUnwrap(parent[key] as? [String: Any])
    }

    private func objects(
        _ parent: [String: Any],
        key: String
    ) throws -> [[String: Any]] {
        try XCTUnwrap(parent[key] as? [[String: Any]])
    }

    private func recursiveKeys(_ value: Any) -> [String] {
        if let object = value as? [String: Any] {
            return object.keys.flatMap { key in
                [key] + recursiveKeys(object[key] as Any)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(recursiveKeys)
        }
        return []
    }
}

private enum CaptureGrantVectors {
    static let signingKeyID = "study-authority-test-v1"
    static let publicKeyBase64 =
        "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ="
    static let wrongPublicKeyBase64 =
        "5/FioQvsVZr+oZXk3OhLaVaNXSywlj60RsBoXisX8vA="
    static let validSignatureBase64 =
        "Su0SaxTyWXz0O7bsxux5GkrKu9aBwJMg6I+GriIRHha7fuACjMzRq/e72QLlubuKqCTqzaQ1XuAq1K7XnuZDCA=="
    static let validArtifactSHA256 =
        "0adad335a1454c11f0b0c98951461f4c8bb71ea3fc6f0d68f1675a201a66e0e1"

    static let validPayload = #"{"artifactKind":"externally-authorized-session-grant-v1","authorizationEpoch":9,"authorizationID":"11111111-1111-4111-8111-111111111111","captureTickets":[{"captureAuthorizationID":"44444444-4444-4444-8444-444444444444","displayText":"C7","ordinal":0,"presentedChartStyle":"simple-chord-sheet","presentedConstruction":"root-first","presentedPace":"natural","presentedSize":"normal","promptID":"isolated-c-seven","promptKind":"isolated-chord","requestedOrientation":"portrait"},{"captureAuthorizationID":"55555555-5555-4555-8555-555555555555","displayText":"Bb7 | Eb7","ordinal":1,"presentedChartStyle":"rhythm-section-sheet","presentedConstruction":"mixed-or-retraced","presentedPace":"fast","presentedSize":"small","promptID":"row-b-flat-seven-e-flat-seven","promptKind":"realistic-row","requestedOrientation":"landscape"}],"clientRequirements":{"captureContractVersion":"recognition-study-authorized-capture-v1","expectedBundleIdentifier":"com.ichart.recognitionstudy","minimumBuildNumber":51},"collectionProtocolVersion":"writer-independent-capture-v2","consentBinding":{"consentLedgerEpoch":7,"consentLedgerVersion":"consent-ledger-v1","consentRecordID":"33333333-3333-4333-8333-333333333333","consentRecordSHA256":"abababababababababababababababababababababababababababababababab","consentTextVersion":"consent-text-v1","dataUsePolicyVersion":"raw-stroke-research-v1","privacyNoticeVersion":"privacy-notice-v1","rawStrokeDonationAuthorized":true,"retentionPolicyVersion":"retention-12-months-v1","schemaVersion":"recognition-study-consent-binding-v1","scope":"chord-recognition-research-v1"},"datasetVersion":"writer-pilot-2026-01","expectedCaptureCount":2,"expiresAtUnixSeconds":1800003600,"issuedAtUnixSeconds":1800000000,"notBeforeUnixSeconds":1800000100,"promptPlanVersion":"pilot-prompts-v1","schemaVersion":"recognition-study-capture-grant-v1","serviceSessionID":"22222222-2222-4222-8222-222222222222"}"#

    static let validArtifact = #"{"payload":{"artifactKind":"externally-authorized-session-grant-v1","authorizationEpoch":9,"authorizationID":"11111111-1111-4111-8111-111111111111","captureTickets":[{"captureAuthorizationID":"44444444-4444-4444-8444-444444444444","displayText":"C7","ordinal":0,"presentedChartStyle":"simple-chord-sheet","presentedConstruction":"root-first","presentedPace":"natural","presentedSize":"normal","promptID":"isolated-c-seven","promptKind":"isolated-chord","requestedOrientation":"portrait"},{"captureAuthorizationID":"55555555-5555-4555-8555-555555555555","displayText":"Bb7 | Eb7","ordinal":1,"presentedChartStyle":"rhythm-section-sheet","presentedConstruction":"mixed-or-retraced","presentedPace":"fast","presentedSize":"small","promptID":"row-b-flat-seven-e-flat-seven","promptKind":"realistic-row","requestedOrientation":"landscape"}],"clientRequirements":{"captureContractVersion":"recognition-study-authorized-capture-v1","expectedBundleIdentifier":"com.ichart.recognitionstudy","minimumBuildNumber":51},"collectionProtocolVersion":"writer-independent-capture-v2","consentBinding":{"consentLedgerEpoch":7,"consentLedgerVersion":"consent-ledger-v1","consentRecordID":"33333333-3333-4333-8333-333333333333","consentRecordSHA256":"abababababababababababababababababababababababababababababababab","consentTextVersion":"consent-text-v1","dataUsePolicyVersion":"raw-stroke-research-v1","privacyNoticeVersion":"privacy-notice-v1","rawStrokeDonationAuthorized":true,"retentionPolicyVersion":"retention-12-months-v1","schemaVersion":"recognition-study-consent-binding-v1","scope":"chord-recognition-research-v1"},"datasetVersion":"writer-pilot-2026-01","expectedCaptureCount":2,"expiresAtUnixSeconds":1800003600,"issuedAtUnixSeconds":1800000000,"notBeforeUnixSeconds":1800000100,"promptPlanVersion":"pilot-prompts-v1","schemaVersion":"recognition-study-capture-grant-v1","serviceSessionID":"22222222-2222-4222-8222-222222222222"},"schemaVersion":"recognition-study-signed-capture-grant-v1","signatureBase64":"Su0SaxTyWXz0O7bsxux5GkrKu9aBwJMg6I+GriIRHha7fuACjMzRq/e72QLlubuKqCTqzaQ1XuAq1K7XnuZDCA==","signingKeyID":"study-authority-test-v1"}"#

    static let tamperedArtifact = validArtifact.replacingOccurrences(
        of: "\"displayText\":\"C7\"",
        with: "\"displayText\":\"D7\""
    )

    static let expiredArtifact = #"{"payload":{"artifactKind":"externally-authorized-session-grant-v1","authorizationEpoch":9,"authorizationID":"11111111-1111-4111-8111-111111111111","captureTickets":[{"captureAuthorizationID":"44444444-4444-4444-8444-444444444444","displayText":"C7","ordinal":0,"presentedChartStyle":"simple-chord-sheet","presentedConstruction":"root-first","presentedPace":"natural","presentedSize":"normal","promptID":"isolated-c-seven","promptKind":"isolated-chord","requestedOrientation":"portrait"},{"captureAuthorizationID":"55555555-5555-4555-8555-555555555555","displayText":"Bb7 | Eb7","ordinal":1,"presentedChartStyle":"rhythm-section-sheet","presentedConstruction":"mixed-or-retraced","presentedPace":"fast","presentedSize":"small","promptID":"row-b-flat-seven-e-flat-seven","promptKind":"realistic-row","requestedOrientation":"landscape"}],"clientRequirements":{"captureContractVersion":"recognition-study-authorized-capture-v1","expectedBundleIdentifier":"com.ichart.recognitionstudy","minimumBuildNumber":51},"collectionProtocolVersion":"writer-independent-capture-v2","consentBinding":{"consentLedgerEpoch":7,"consentLedgerVersion":"consent-ledger-v1","consentRecordID":"33333333-3333-4333-8333-333333333333","consentRecordSHA256":"abababababababababababababababababababababababababababababababab","consentTextVersion":"consent-text-v1","dataUsePolicyVersion":"raw-stroke-research-v1","privacyNoticeVersion":"privacy-notice-v1","rawStrokeDonationAuthorized":true,"retentionPolicyVersion":"retention-12-months-v1","schemaVersion":"recognition-study-consent-binding-v1","scope":"chord-recognition-research-v1"},"datasetVersion":"writer-pilot-2026-01","expectedCaptureCount":2,"expiresAtUnixSeconds":1600003600,"issuedAtUnixSeconds":1600000000,"notBeforeUnixSeconds":1600000100,"promptPlanVersion":"pilot-prompts-v1","schemaVersion":"recognition-study-capture-grant-v1","serviceSessionID":"22222222-2222-4222-8222-222222222222"},"schemaVersion":"recognition-study-signed-capture-grant-v1","signatureBase64":"tVMJjU6eZ27/vVUU6/HtSSyyvi0daHMyTSZ8vysnt7AHLDjgEnS+celcKfL6VDrAVnNk3gkgx5w1RJ4DcA3RDg==","signingKeyID":"study-authority-test-v1"}"#
}

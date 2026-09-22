import XCTest
@testable import iChart

final class ChordInkSelectiveDecisionPolicyTests: XCTestCase {
    private let policy = ChordInkSelectiveDecisionPolicy()
    private let decisionDigest = String(repeating: "f", count: 64)

    func testSelectiveArtifactValidatesAndRoundTrips() throws {
        let setup = authorizedSetup()
        let calibrationResolution = ChordInkCalibrationResolution.resolve(
            artifact: setup.calibration,
            manifest: setup.manifest
        )
        guard case .validated(let calibration) = calibrationResolution else {
            return XCTFail("Expected validated calibration")
        }
        guard case .learnedCandidate(let receipt) = setup.route.authority else {
            return XCTFail("Expected sealed learned-candidate authority")
        }

        let validated = try setup.selective.validate(
            manifest: setup.manifest,
            calibration: calibration,
            sealedGateReceipt: receipt
        )
        XCTAssertEqual(validated.artifact, setup.selective)

        let encoded = try JSONEncoder().encode(setup.selective)
        XCTAssertEqual(
            try JSONDecoder().decode(ChordInkSelectiveDecisionArtifact.self, from: encoded),
            setup.selective
        )
    }

    func testHighCalibratedSupportAndMarginAutoAcceptWithSealedAuthority() throws {
        let setup = authorizedSetup()
        let result = decodeResult(
            candidates: [
                (try notation("C△7"), rawLogScore(forCalibratedSupport: 0.97)),
                (try notation("G7"), rawLogScore(forCalibratedSupport: 0.10))
            ],
            noReadSupport: 0.05
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: setup.selective,
            routeDecision: setup.route
        )

        XCTAssertEqual(decision.disposition, .autoAccept(try notation("C△7")))
        XCTAssertEqual(decision.metrics?.topCandidateSupport ?? -1, 0.97, accuracy: 1e-12)
        XCTAssertEqual(decision.metrics?.topCandidateMargin ?? -1, 0.87, accuracy: 1e-12)
    }

    func testAutoAcceptIsImpossibleWithoutSealedGateAuthority() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let calibration = calibration()
        let route = ChordInkLearnedRouterPolicy().decision(
            requestedMode: .learnedCandidate,
            manifest: manifest,
            calibrationArtifact: calibration,
            sealedGateReceipt: nil
        )
        let result = decodeResult(
            candidates: [(try notation("C"), rawLogScore(forCalibratedSupport: 0.99))],
            noReadSupport: 0.01
        )

        let decision = policy.decision(
            for: result,
            manifest: manifest,
            calibrationArtifact: calibration,
            selectiveArtifact: selectiveArtifact(),
            routeDecision: route
        )

        XCTAssertEqual(
            decision.disposition,
            .candidateReview(
                primary: try notation("C"),
                alternatives: [],
                reason: .selectiveAuthorityUnavailable
            )
        )
    }

    func testAutoAcceptIsImpossibleWithoutValidatedCalibration() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let route = ChordInkLearnedRouterPolicy().decision(
            requestedMode: .learnedCandidate,
            manifest: manifest,
            calibrationArtifact: nil,
            sealedGateReceipt: ChordInkLearnedTestFactory.receipt()
        )
        let result = decodeResult(
            candidates: [(try notation("C"), rawLogScore(forCalibratedSupport: 0.99))],
            noReadSupport: 0.01
        )

        let decision = policy.decision(
            for: result,
            manifest: manifest,
            calibrationArtifact: nil,
            selectiveArtifact: selectiveArtifact(),
            routeDecision: route
        )

        XCTAssertEqual(
            decision.disposition,
            .candidateReview(
                primary: try notation("C"),
                alternatives: [],
                reason: .calibrationUnavailable
            )
        )
        XCTAssertNil(decision.metrics)
    }

    func testModerateEvidenceRequiresConfirmation() throws {
        let setup = authorizedSetup()
        let result = decodeResult(
            candidates: [
                (try notation("Bb-7"), rawLogScore(forCalibratedSupport: 0.80)),
                (try notation("Bb7"), rawLogScore(forCalibratedSupport: 0.30))
            ],
            noReadSupport: 0.10
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: setup.selective,
            routeDecision: setup.route
        )

        XCTAssertEqual(
            decision.disposition,
            .confirm(
                primary: try notation("Bb-7"),
                alternatives: [try notation("Bb7")]
            )
        )
    }

    func testCloseRaceBecomesCandidateReview() throws {
        let setup = authorizedSetup()
        let result = decodeResult(
            candidates: [
                (try notation("B"), rawLogScore(forCalibratedSupport: 0.50)),
                (try notation("G"), rawLogScore(forCalibratedSupport: 0.45))
            ],
            noReadSupport: 0.10
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: setup.selective,
            routeDecision: setup.route
        )

        XCTAssertEqual(
            decision.disposition,
            .candidateReview(
                primary: try notation("B"),
                alternatives: [try notation("G")],
                reason: .belowConfirmThreshold
            )
        )
        XCTAssertEqual(decision.metrics?.topCandidateMargin ?? -1, 0.05, accuracy: 1e-12)
    }

    func testStrongNoReadEvidenceWinsOverCandidate() throws {
        let setup = authorizedSetup()
        let result = decodeResult(
            candidates: [(try notation("D"), rawLogScore(forCalibratedSupport: 0.40))],
            noReadSupport: 0.90
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: setup.selective,
            routeDecision: setup.route
        )

        XCTAssertEqual(decision.disposition, .noRead(.modelPreferredNoRead))
    }

    func testCandidateBelowReviewFloorBecomesNoRead() throws {
        let setup = authorizedSetup()
        let result = decodeResult(
            candidates: [(try notation("D"), rawLogScore(forCalibratedSupport: 0.10))],
            noReadSupport: 0.10
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: setup.selective,
            routeDecision: setup.route
        )

        XCTAssertEqual(
            decision.disposition,
            .noRead(.candidateSupportBelowReviewFloor)
        )
    }

    func testNoCandidatesProducesNoRead() {
        let setup = authorizedSetup()
        let result = decodeResult(candidates: [], noReadSupport: 0.95)

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: setup.selective,
            routeDecision: setup.route
        )

        XCTAssertEqual(decision.disposition, .noRead(.noCandidates))
        XCTAssertEqual(decision.metrics?.noReadSupport ?? -1, 0.95, accuracy: 1e-12)
    }

    func testInvalidScoresFailClosedToHumanReview() throws {
        let setup = authorizedSetup()
        let result = ChordInkLearnedDecodeResult(
            candidates: [
                ChordInkLearnedDecodedCandidate(
                    notation: try notation("C"),
                    rawJointLogScore: 0.01
                )
            ],
            noReadLogScore: log(0.01)
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: setup.selective,
            routeDecision: setup.route
        )

        XCTAssertEqual(
            decision.disposition,
            .candidateReview(
                primary: try notation("C"),
                alternatives: [],
                reason: .invalidDecodeScores
            )
        )
        XCTAssertNil(decision.metrics)
    }

    func testTruncatedCandidateListIsNeverRenormalized() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let calibration = calibration(temperature: 1)
        let receipt = ChordInkLearnedTestFactory.receipt()
        let route = ChordInkLearnedRouterPolicy().decision(
            requestedMode: .learnedCandidate,
            manifest: manifest,
            calibrationArtifact: calibration,
            sealedGateReceipt: receipt
        )
        let result = decodeResult(
            candidates: [
                (try notation("C"), log(0.40)),
                (try notation("D"), log(0.30))
            ],
            noReadSupport: 0.10,
            temperature: 1
        )

        let decision = policy.decision(
            for: result,
            manifest: manifest,
            calibrationArtifact: calibration,
            selectiveArtifact: selectiveArtifact(),
            routeDecision: route
        )

        XCTAssertEqual(decision.metrics?.topCandidateSupport ?? -1, 0.40, accuracy: 1e-12)
        XCTAssertEqual(decision.metrics?.candidates[1].calibratedSupport ?? -1, 0.30, accuracy: 1e-12)
        XCTAssertEqual(decision.metrics?.noReadSupport ?? -1, 0.10, accuracy: 1e-12)
        XCTAssertEqual(decision.metrics?.topCandidateMargin ?? -1, 0.10, accuracy: 1e-12)
    }

    func testArtifactBoundToDifferentReceiptCannotAuthorizeThresholds() throws {
        let setup = authorizedSetup()
        let invalidArtifact = selectiveArtifact(
            sealedGateReceiptDigest: String(repeating: "0", count: 64)
        )
        let result = decodeResult(
            candidates: [(try notation("C"), rawLogScore(forCalibratedSupport: 0.99))],
            noReadSupport: 0.01
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: invalidArtifact,
            routeDecision: setup.route
        )

        XCTAssertEqual(
            decision.disposition,
            .candidateReview(
                primary: try notation("C"),
                alternatives: [],
                reason: .selectiveAuthorityUnavailable
            )
        )
    }

    func testNonMonotonicThresholdArtifactFailsClosed() throws {
        let setup = authorizedSetup()
        let invalidArtifact = selectiveArtifact(
            thresholds: ChordInkSelectiveDecisionThresholds(
                autoAcceptMinimumTopSupport: 0.70,
                autoAcceptMinimumMargin: 0.10,
                confirmMinimumTopSupport: 0.90,
                confirmMinimumMargin: 0.20,
                candidateReviewMinimumTopSupport: 0.20,
                noReadMinimumSupport: 0.80
            )
        )
        let result = decodeResult(
            candidates: [(try notation("C"), rawLogScore(forCalibratedSupport: 0.99))],
            noReadSupport: 0.01
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: invalidArtifact,
            routeDecision: setup.route
        )

        guard case .candidateReview(_, _, .selectiveAuthorityUnavailable) = decision.disposition else {
            return XCTFail("Invalid thresholds must not authorize a selective decision")
        }
    }

    func testThresholdsSelectedAfterSealedEvaluationFailClosed() throws {
        let setup = authorizedSetup()
        let invalidArtifact = selectiveArtifact(predeclared: false)
        let result = decodeResult(
            candidates: [(try notation("C"), rawLogScore(forCalibratedSupport: 0.99))],
            noReadSupport: 0.01
        )

        let decision = policy.decision(
            for: result,
            manifest: setup.manifest,
            calibrationArtifact: setup.calibration,
            selectiveArtifact: invalidArtifact,
            routeDecision: setup.route
        )

        guard case .candidateReview(_, _, .selectiveAuthorityUnavailable) = decision.disposition else {
            return XCTFail("Post-evaluation threshold selection must not authorize output")
        }
    }

    private func authorizedSetup() -> (
        manifest: ChordInkModelArtifactManifest,
        calibration: ChordInkCalibrationArtifact,
        selective: ChordInkSelectiveDecisionArtifact,
        route: ChordInkLearnedRouteDecision
    ) {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let calibration = calibration()
        let receipt = ChordInkLearnedTestFactory.receipt()
        return (
            manifest,
            calibration,
            selectiveArtifact(),
            ChordInkLearnedRouterPolicy().decision(
                requestedMode: .learnedCandidate,
                manifest: manifest,
                calibrationArtifact: calibration,
                sealedGateReceipt: receipt
            )
        )
    }

    private func calibration(temperature: Double = 1.25) -> ChordInkCalibrationArtifact {
        ChordInkCalibrationArtifact(
            calibrationArtifactSHA256: ChordInkLearnedTestFactory.calibrationDigest,
            manifestArtifactSHA256: ChordInkLearnedTestFactory.manifestDigest,
            modelArtifactSHA256: ChordInkLearnedTestFactory.modelDigest,
            temperature: temperature,
            wasIndependentlyFitted: true,
            usedWriterDisjointData: true,
            fitDatasetIdentifier: "writer-disjoint-calibration-v1",
            independentFitReceiptSHA256: ChordInkLearnedTestFactory.fitReceiptDigest
        )
    }

    private func selectiveArtifact(
        sealedGateReceiptDigest: String = ChordInkLearnedTestFactory.gateReceiptDigest,
        predeclared: Bool = true,
        thresholds: ChordInkSelectiveDecisionThresholds = ChordInkSelectiveDecisionThresholds(
            autoAcceptMinimumTopSupport: 0.90,
            autoAcceptMinimumMargin: 0.50,
            confirmMinimumTopSupport: 0.70,
            confirmMinimumMargin: 0.25,
            candidateReviewMinimumTopSupport: 0.20,
            noReadMinimumSupport: 0.80
        )
    ) -> ChordInkSelectiveDecisionArtifact {
        ChordInkSelectiveDecisionArtifact(
            decisionArtifactSHA256: decisionDigest,
            manifestArtifactSHA256: ChordInkLearnedTestFactory.manifestDigest,
            modelArtifactSHA256: ChordInkLearnedTestFactory.modelDigest,
            calibrationArtifactSHA256: ChordInkLearnedTestFactory.calibrationDigest,
            sealedGateReceiptSHA256: sealedGateReceiptDigest,
            evaluationProtocolIdentifier: "predeclared-writer-independent-v1",
            thresholdsWerePredeclaredBeforeSealedEvaluation: predeclared,
            usedWriterDisjointThresholdSelectionData: true,
            thresholdSelectionDatasetIdentifier: "writer-disjoint-threshold-selection-v1",
            thresholds: thresholds
        )
    }

    private func decodeResult(
        candidates: [(ChordNotation, Double)],
        noReadSupport: Double,
        temperature: Double = 1.25
    ) -> ChordInkLearnedDecodeResult {
        ChordInkLearnedDecodeResult(
            candidates: candidates.map {
                ChordInkLearnedDecodedCandidate(
                    notation: $0.0,
                    rawJointLogScore: $0.1
                )
            },
            noReadLogScore: rawLogScore(
                forCalibratedSupport: noReadSupport,
                temperature: temperature
            )
        )
    }

    private func rawLogScore(
        forCalibratedSupport support: Double,
        temperature: Double = 1.25
    ) -> Double {
        let calibratedLogit = log(support / (1 - support))
        let rawLogit = calibratedLogit * temperature
        let rawProbability = 1 / (1 + exp(-rawLogit))
        return log(rawProbability)
    }

    private func notation(_ canonical: String) throws -> ChordNotation {
        try ChordNotation.parseCanonical(canonical)
    }
}

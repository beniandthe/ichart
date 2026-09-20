import CryptoKit
import XCTest

final class WriterIndependentEvaluationReceiptTests: XCTestCase {
    private lazy var signingKey = Curve25519.Signing.PrivateKey()
    private lazy var freshnessSigningKey = Curve25519.Signing.PrivateKey()

    func testValidAggregateOnlyReceiptPassesBoundSealedPilotGate() throws {
        let gate = pilotGate()
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        let expected = try expectation(gate: gate)

        XCTAssertEqual(
            WriterIndependentEvaluationReceiptValidator.issues(
                in: receipt,
                trustedSigningPublicKeysByID: trustedSigningKeys
            ),
            []
        )
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: expected,
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ),
            []
        )

        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(receipt), encoding: .utf8))
        XCTAssertFalse(json.contains("strokes"))
        XCTAssertFalse(json.contains("chordText"))
        XCTAssertFalse(json.contains("expectedDisplayText"))
        XCTAssertFalse(json.contains("sampleID"))
        XCTAssertFalse(json.contains("writerID"))
    }

    func testTenZeroErrorWritersCannotProveSubHalfPercentTrustedRisk() throws {
        var strictGate = pilotGate()
        strictGate.maximumTrustedRiskUpperBound = 0.005
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: strictGate)
        let failures = WriterIndependentRecognitionGateEvaluator.failures(
            for: receipt,
            expected: try expectation(gate: strictGate),
            trustedSigningPublicKeysByID: trustedSigningKeys,
            gate: strictGate
        )

        XCTAssertTrue(failures.map(\.code).contains(.trustedRisk))
        XCTAssertGreaterThan(
            failures.first(where: { $0.code == .trustedRisk })?.observed ?? 0,
            0.005
        )
    }

    func testTenOfTenWritersCannotProveHighWriterPassProbability() throws {
        var strictGate = pilotGate()
        strictGate.minimumWriterPassProbabilityLowerBound = 0.90
        let failures = WriterIndependentRecognitionGateEvaluator.failures(
            for: try signedReceipt(aggregate: passingAggregate(), gate: strictGate),
            expected: try expectation(gate: strictGate),
            trustedSigningPublicKeysByID: trustedSigningKeys,
            gate: strictGate
        )

        let observed = failures.first(where: { $0.code == .writerPassProbability })?.observed
        XCTAssertEqual(try XCTUnwrap(observed), 0.6451950121, accuracy: 0.0000001)
    }

    func testRejectEverythingCannotPassThroughPerfectObservedRisk() throws {
        var aggregate = passingAggregate()
        aggregate.trustedLegibleCount = 0
        aggregate.trustedWrongLegibleCount = 0
        aggregate.confirmationCount = 700
        aggregate.candidateReviewCount = 200
        aggregate.noReadCount = 100
        aggregate.writerOutcomeSummaries = (0..<10).map { index in
            WriterIndependentWriterOutcomeSummary(
                writerCommitmentSHA256: sha256(5_000 + index),
                legibleValidCount: 100,
                exactCorrectCount: 92,
                topThreeCorrectCount: 98,
                trustedLegibleCount: 0,
                trustedWrongLegibleCount: 0
            )
        }
        aggregate.strata = aggregate.strata.map { stratum in
            var updated = stratum
            updated.trustedLegibleCount = 0
            updated.trustedWrongLegibleCount = 0
            return updated
        }
        let gate = pilotGate()
        let codes = WriterIndependentRecognitionGateEvaluator.failures(
            for: try signedReceipt(aggregate: aggregate, gate: gate),
            expected: try expectation(gate: gate),
            trustedSigningPublicKeysByID: trustedSigningKeys,
            gate: gate
        ).map(\.code)

        XCTAssertTrue(codes.contains(.trustedCoverage))
        XCTAssertTrue(codes.contains(.minimumWriterCoverage))
    }

    func testReceiptValidatorRejectsInconsistentCountsAndMissingSignature() throws {
        var aggregate = passingAggregate()
        aggregate.independentHumanCaptureCount = 1
        aggregate.topThreeCorrectCount = aggregate.legibleValidCount + 1
        aggregate.trustedWrongLegibleCount = aggregate.trustedLegibleCount + 1
        let gate = pilotGate()
        var receipt = try signedReceipt(aggregate: aggregate, gate: gate)
        receipt.signatureBase64 = ""

        XCTAssertEqual(
            WriterIndependentEvaluationReceiptValidator.issues(
                in: receipt,
                trustedSigningPublicKeysByID: trustedSigningKeys
            ).map(\.code),
            [.impossibleOutcomeCount, .missingSignature, .populationCountMismatch, .stratumPartitionMismatch, .writerSummaryMismatch]
        )
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: try expectation(gate: gate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ).map(\.code),
            [.invalidReceipt]
        )
    }

    func testPayloadMutationInvalidatesCryptographicSignature() throws {
        let gate = pilotGate()
        var receipt = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        receipt.payload.aggregate.exactCorrectCount -= 1

        XCTAssertEqual(
            WriterIndependentEvaluationReceiptValidator.issues(
                in: receipt,
                trustedSigningPublicKeysByID: trustedSigningKeys
            ).map(\.code),
            [.invalidSignature, .stratumPartitionMismatch, .writerSummaryMismatch]
        )
    }

    func testUnknownSigningKeyCannotPass() throws {
        let gate = pilotGate()
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        let otherKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation

        XCTAssertEqual(
            WriterIndependentEvaluationReceiptValidator.issues(
                in: receipt,
                trustedSigningPublicKeysByID: ["other-key": otherKey]
            ).map(\.code),
            [.unknownSigningKey]
        )
    }

    func testGateRejectsWrongSplitAndExpectedArtifactIdentity() throws {
        let gate = pilotGate()
        let receipt = try signedReceipt(
            aggregate: passingAggregate(),
            gate: gate,
            split: .calibration
        )
        var expected = try expectation(gate: gate)
        expected.recognizerArtifactSHA256 = sha256(999)

        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: expected,
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ).map(\.code),
            [.receiptIdentityMismatch, .wrongEvaluationSplit]
        )
    }

    func testGateReconcilesAggregateCountsToExpectedSealedManifest() throws {
        let gate = pilotGate()
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        var expected = try expectation(gate: gate)
        expected.independentHumanCaptureCount -= 1

        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: expected,
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ).map(\.code),
            [.sealedPopulationMismatch]
        )
    }

    func testGateDefinitionIsBoundByIDHashAndSignature() throws {
        let signedGate = pilotGate()
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: signedGate)
        var substitutedGate = signedGate
        substitutedGate.maximumTrustedRiskUpperBound = 0.9

        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: try expectation(gate: signedGate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: substitutedGate
            ).map(\.code),
            [.gateDefinitionMismatch]
        )
    }

    func testInvalidGateThresholdsFailClosed() throws {
        let validGate = pilotGate()
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: validGate)
        var invalidGate = validGate
        invalidGate.minimumTrustedCoverage = .nan

        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: try expectation(gate: validGate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: invalidGate
            ).map(\.code),
            [.invalidGate]
        )

        var invalidAlpha = validGate
        invalidAlpha.overallFamilyWiseAlpha = 0
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: try expectation(gate: validGate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: invalidAlpha
            ).map(\.code),
            [.invalidGate]
        )

        var unsupportedMethod = validGate
        unsupportedMethod.uncertaintyMethodVersion = "unreviewed-method"
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: try expectation(gate: validGate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: unsupportedMethod
            ).map(\.code),
            [.invalidGate]
        )

        var oneWriterGate = validGate
        oneWriterGate.minimumIndependentWriters = 1
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: try expectation(gate: validGate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: oneWriterGate
            ).map(\.code),
            [.invalidGate]
        )

        var zeroSamplesPerWriterGate = validGate
        zeroSamplesPerWriterGate.minimumEvaluableHumanSamplesPerWriter = 0
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: try expectation(gate: validGate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: zeroSamplesPerWriterGate
            ).map(\.code),
            [.invalidGate]
        )
    }

    func testPerWriterSufficientStatisticsMustReconcileToAggregate() throws {
        var aggregate = passingAggregate()
        aggregate.writerOutcomeSummaries[0].exactCorrectCount -= 1
        let gate = pilotGate()
        let receipt = try signedReceipt(aggregate: aggregate, gate: gate)

        XCTAssertEqual(
            WriterIndependentEvaluationReceiptValidator.issues(
                in: receipt,
                trustedSigningPublicKeysByID: trustedSigningKeys
            ).map(\.code),
            [.writerSummaryMismatch]
        )
    }

    func testTrustedCorrectCountCannotExceedExactCorrectCount() throws {
        var aggregate = passingAggregate()
        aggregate.trustedLegibleCount = 950
        aggregate.trustedWrongLegibleCount = 0
        aggregate.confirmationCount = 20
        aggregate.candidateReviewCount = 20
        aggregate.noReadCount = 10
        let gate = pilotGate()
        let receipt = try signedReceipt(aggregate: aggregate, gate: gate)

        XCTAssertEqual(
            WriterIndependentEvaluationReceiptValidator.issues(
                in: receipt,
                trustedSigningPublicKeysByID: trustedSigningKeys
            ).map(\.code),
            [.impossibleOutcomeCount, .stratumPartitionMismatch, .writerSummaryMismatch]
        )
    }

    func testOneTrustedWrongReadFailsTheZeroWrongPilotRule() throws {
        var aggregate = passingAggregate()
        aggregate.trustedWrongLegibleCount = 1
        aggregate.writerOutcomeSummaries[0].trustedWrongLegibleCount = 1
        for dimension in [
            WriterIndependentEvaluationStratumDimension.overall,
            .chartStyle,
            .deviceClass,
            .orientation,
            .pace,
            .sizeBucket,
            .handedness,
            .pencilExperience,
            .constructionVariation
        ] {
            if let index = aggregate.strata.firstIndex(where: {
                $0.key.population == .naturalFrequency && $0.key.dimension == dimension
            }) {
                aggregate.strata[index].trustedWrongLegibleCount = 1
            }
        }
        let gate = pilotGate()

        let codes = WriterIndependentRecognitionGateEvaluator.failures(
            for: try signedReceipt(aggregate: aggregate, gate: gate),
            expected: try expectation(gate: gate),
            trustedSigningPublicKeysByID: trustedSigningKeys,
            gate: gate
        ).map(\.code)

        XCTAssertTrue(codes.contains(.trustedWrong))
    }

    func testMissingOrFailingPreregisteredStratumCannotPass() throws {
        var missing = passingAggregate()
        missing.strata.removeAll { $0.key.dimension == .component && $0.key.value == "slash-bass" }
        let gate = pilotGate()
        XCTAssertTrue(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: try signedReceipt(aggregate: missing, gate: gate),
                expected: try expectation(gate: gate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ).map(\.code).contains(.stratumPopulationMismatch)
        )

        var failing = passingAggregate()
        let componentIndex = try XCTUnwrap(
            failing.strata.firstIndex { $0.key.dimension == .component && $0.key.value == "slash-bass" }
        )
        failing.strata[componentIndex].exactCorrectCount = 400
        XCTAssertTrue(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: try signedReceipt(aggregate: failing, gate: gate),
                expected: try expectation(gate: gate),
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ).map(\.code).contains(.stratumAccuracy)
        )
    }

    func testDuplicateAndImpossibleStrataFailWithoutTrapping() throws {
        let gate = pilotGate()
        var duplicate = passingAggregate()
        duplicate.strata.append(duplicate.strata[0])
        let duplicateCodes = WriterIndependentEvaluationReceiptValidator.issues(
            in: try signedReceipt(aggregate: duplicate, gate: gate),
            trustedSigningPublicKeysByID: trustedSigningKeys
        ).map(\.code)
        XCTAssertTrue(duplicateCodes.contains(.duplicateStratum))
        XCTAssertTrue(duplicateCodes.contains(.stratumPartitionMismatch))

        var impossible = passingAggregate()
        let chartIndex = try XCTUnwrap(
            impossible.strata.firstIndex { $0.key.dimension == .chartStyle }
        )
        impossible.strata[chartIndex].humanSampleCount += 1
        XCTAssertTrue(
            WriterIndependentEvaluationReceiptValidator.issues(
                in: try signedReceipt(aggregate: impossible, gate: gate),
                trustedSigningPublicKeysByID: trustedSigningKeys
            ).map(\.code).contains(.stratumPartitionMismatch)
        )
    }

    func testDatasetComponentHashesAreBoundToCommitmentAndExpectation() throws {
        let gate = pilotGate()
        var tampered = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        tampered.payload.evaluationManifestSHA256 = sha256(999)
        let receiptCodes = WriterIndependentEvaluationReceiptValidator.issues(
            in: tampered,
            trustedSigningPublicKeysByID: trustedSigningKeys
        ).map(\.code)
        XCTAssertTrue(receiptCodes.contains(.datasetCommitmentMismatch))
        XCTAssertTrue(receiptCodes.contains(.invalidSignature))

        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        var expected = try expectation(gate: gate)
        expected.provenanceSnapshotSHA256 = sha256(998)
        XCTAssertTrue(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: expected,
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ).map(\.code).contains(.receiptIdentityMismatch)
        )

        var substitutedGroundTruth = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        substitutedGroundTruth.payload.groundTruthSnapshotSHA256 = sha256(997)
        let groundTruthCodes = WriterIndependentEvaluationReceiptValidator.issues(
            in: substitutedGroundTruth,
            trustedSigningPublicKeysByID: trustedSigningKeys
        ).map(\.code)
        XCTAssertTrue(groundTruthCodes.contains(.datasetCommitmentMismatch))
        XCTAssertTrue(groundTruthCodes.contains(.invalidSignature))

        var staleGroundTruthExpectation = try expectation(gate: gate)
        staleGroundTruthExpectation.groundTruthRegistryEpoch -= 1
        XCTAssertTrue(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: staleGroundTruthExpectation,
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ).map(\.code).contains(.receiptIdentityMismatch)
        )
    }

    func testWriterCommitmentsMustBeUniqueAndMatchSignedRoot() throws {
        let gate = pilotGate()
        var duplicate = passingAggregate()
        duplicate.writerOutcomeSummaries[1].writerCommitmentSHA256 =
            duplicate.writerOutcomeSummaries[0].writerCommitmentSHA256
        XCTAssertEqual(
            WriterIndependentEvaluationReceiptValidator.issues(
                in: try signedReceipt(aggregate: duplicate, gate: gate),
                trustedSigningPublicKeysByID: trustedSigningKeys
            ).map(\.code),
            [.stratumWriterCoverageMismatch, .writerCommitmentMismatch]
        )
    }

    func testHardStratumCannotBeSatisfiedByOneProlificWriter() throws {
        let gate = pilotGate()
        var aggregate = passingAggregate()
        let fastIndex = try XCTUnwrap(
            aggregate.strata.firstIndex {
                $0.key.dimension == .pace && $0.key.value == WriterIndependentEvaluationPace.fast.rawValue
            }
        )
        aggregate.strata[fastIndex].writerCommitmentsSHA256 = [writerCommitments[0]]
        var expected = try expectation(gate: gate)
        let expectedIndex = try XCTUnwrap(
            expected.expectedStrata.firstIndex { $0.key == aggregate.strata[fastIndex].key }
        )
        expected.expectedStrata[expectedIndex].independentWriterCount = 1
        expected.expectedStrata[expectedIndex].writerMembershipMerkleRootSHA256 =
            aggregate.strata[fastIndex].writerMembershipMerkleRootSHA256

        let failures = WriterIndependentRecognitionGateEvaluator.failures(
            for: try signedReceipt(aggregate: aggregate, gate: gate),
            expected: expected,
            trustedSigningPublicKeysByID: trustedSigningKeys,
            gate: gate
        ).map(\.code)

        XCTAssertTrue(failures.contains(.insufficientStratumWriters))
    }

    func testGateCannotOmitAnyMandatoryProtocolStratum() throws {
        let validGate = pilotGate()
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: validGate)

        for mandatoryKey in WriterIndependentEvaluationProtocolContract.requiredStratumKeys {
            var incompleteGate = validGate
            incompleteGate.requiredStrata.removeAll { $0.key == mandatoryKey }
            XCTAssertEqual(
                WriterIndependentRecognitionGateEvaluator.failures(
                    for: receipt,
                    expected: try expectation(gate: validGate),
                    trustedSigningPublicKeysByID: trustedSigningKeys,
                    gate: incompleteGate
                ).map(\.code),
                [.invalidGate],
                "Gate unexpectedly accepted omission of \(mandatoryKey)."
            )
        }
    }

    func testCanonicalPayloadAndGateEncodingAreStable() throws {
        let gate = pilotGate()
        let payload = try signedReceipt(aggregate: passingAggregate(), gate: gate).payload

        XCTAssertEqual(try payload.canonicalData(), try payload.canonicalData())
        XCTAssertEqual(
            try JSONDecoder().decode(WriterIndependentEvaluationReceiptPayload.self, from: payload.canonicalData()),
            payload
        )
        XCTAssertEqual(try gate.definitionSHA256(), try gate.definitionSHA256())
    }

    func testPooledWilsonDiagnosticDoesNotTreatZeroObservedErrorsAsZeroRisk() {
        let upper = WriterIndependentRecognitionGateEvaluator.pooledWilsonUpperBound(successes: 0, trials: 600)

        XCTAssertGreaterThan(upper, 0)
        XCTAssertLessThan(upper, 0.01)
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.pooledWilsonUpperBound(successes: 0, trials: 0),
            1
        )
    }

    func testWriterClusterBoundUsesWritersRatherThanPseudoreplicatedAttempts() {
        let summaries = passingAggregate().writerOutcomeSummaries
        let bounds = WriterIndependentRecognitionGateEvaluator
            .writerClusterBonferroniEmpiricalBernsteinBounds(
                summaries: summaries,
                overallFamilyWiseAlpha: 0.05
            )

        XCTAssertGreaterThan(bounds.trustedRiskUpperBound, 0)
        XCTAssertGreaterThan(bounds.trustedRiskUpperBound, 0.5)
        XCTAssertLessThan(bounds.exactAccuracyLowerBound, 0.92)
        XCTAssertLessThan(bounds.topThreeAccuracyLowerBound, 0.98)

        let oneWriter = WriterIndependentRecognitionGateEvaluator
            .writerClusterBonferroniEmpiricalBernsteinBounds(
                summaries: [summaries[0]],
                overallFamilyWiseAlpha: 0.05
            )
        XCTAssertEqual(oneWriter.exactAccuracyLowerBound, 0)
        XCTAssertEqual(oneWriter.topThreeAccuracyLowerBound, 0)
        XCTAssertEqual(oneWriter.trustedRiskUpperBound, 1)
    }

    func testExactWriterPassProbabilityLowerBoundHandlesEdges() {
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.oneSidedClopperPearsonLowerBound(
                successes: 10,
                trials: 10,
                alpha: 0.05
            ),
            0.7411344491,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.oneSidedClopperPearsonLowerBound(
                successes: 0,
                trials: 10,
                alpha: 0.05
            ),
            0
        )
        XCTAssertEqual(
            WriterIndependentRecognitionGateEvaluator.oneSidedClopperPearsonLowerBound(
                successes: 1,
                trials: 0,
                alpha: 0.05
            ),
            0
        )
        let nineOfTen = WriterIndependentRecognitionGateEvaluator.oneSidedClopperPearsonLowerBound(
            successes: 9,
            trials: 10,
            alpha: 0.05
        )
        XCTAssertEqual(nineOfTen, 0.6058366976, accuracy: 0.0000001)
    }

    func testWriterPassPredicateFailureLowersPopulationGuarantee() throws {
        var aggregate = passingAggregate()
        aggregate.writerOutcomeSummaries[0].exactCorrectCount = 84
        aggregate.writerOutcomeSummaries[1].exactCorrectCount = 100
        aggregate.writerOutcomeSummaries[0].topThreeCorrectCount = 96
        aggregate.writerOutcomeSummaries[1].topThreeCorrectCount = 100

        var gate = pilotGate()
        gate.minimumWriterPassProbabilityLowerBound = 0.70
        let failures = WriterIndependentRecognitionGateEvaluator.failures(
            for: try signedReceipt(aggregate: aggregate, gate: gate),
            expected: try expectation(gate: gate),
            trustedSigningPublicKeysByID: trustedSigningKeys,
            gate: gate
        )
        XCTAssertTrue(failures.map(\.code).contains(.writerPassProbability))
    }

    func testWriterPassPredicateTreatsNoTrustedPredictionsAsFailure() {
        var summary = passingAggregate().writerOutcomeSummaries[0]
        summary.trustedLegibleCount = 0
        summary.trustedWrongLegibleCount = 0

        XCTAssertFalse(
            WriterIndependentRecognitionGateEvaluator.writerPasses(
                summary,
                gate: pilotGate()
            )
        )
    }

    func testMoreAttemptsFromSameWritersDoNotTightenWriterClusterBound() {
        let summaries = passingAggregate().writerOutcomeSummaries
        let repeatedAttempts = summaries.map { summary in
            WriterIndependentWriterOutcomeSummary(
                writerCommitmentSHA256: summary.writerCommitmentSHA256,
                legibleValidCount: summary.legibleValidCount * 10,
                exactCorrectCount: summary.exactCorrectCount * 10,
                topThreeCorrectCount: summary.topThreeCorrectCount * 10,
                trustedLegibleCount: summary.trustedLegibleCount * 10,
                trustedWrongLegibleCount: summary.trustedWrongLegibleCount * 10
            )
        }

        let original = WriterIndependentRecognitionGateEvaluator
            .writerClusterBonferroniEmpiricalBernsteinBounds(
                summaries: summaries,
                overallFamilyWiseAlpha: 0.05
            )
        let repeated = WriterIndependentRecognitionGateEvaluator
            .writerClusterBonferroniEmpiricalBernsteinBounds(
                summaries: repeatedAttempts,
                overallFamilyWiseAlpha: 0.05
            )
        XCTAssertEqual(original.exactAccuracyLowerBound, repeated.exactAccuracyLowerBound)
        XCTAssertEqual(original.topThreeAccuracyLowerBound, repeated.topThreeAccuracyLowerBound)
        XCTAssertEqual(original.trustedRiskUpperBound, repeated.trustedRiskUpperBound)
    }

    func testAnyWriterWithoutTrustedPredictionsMakesPilotRiskBoundConservative() {
        var summaries = passingAggregate().writerOutcomeSummaries
        summaries[0].trustedLegibleCount = 0
        summaries[0].trustedWrongLegibleCount = 0
        let bounds = WriterIndependentRecognitionGateEvaluator
            .writerClusterBonferroniEmpiricalBernsteinBounds(
                summaries: summaries,
                overallFamilyWiseAlpha: 0.05
            )

        XCTAssertEqual(bounds.trustedRiskUpperBound, 1)
    }

    func testEvaluationAuthorizationAndFirstAttemptAreIdentityBound() throws {
        let gate = pilotGate()
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        var expected = try expectation(gate: gate)
        expected.evaluationAuthorizationID = "different-authorization"
        XCTAssertTrue(
            WriterIndependentRecognitionGateEvaluator.failures(
                for: receipt,
                expected: expected,
                trustedSigningPublicKeysByID: trustedSigningKeys,
                gate: gate
            ).map(\.code).contains(.receiptIdentityMismatch)
        )

        var replay = receipt
        replay.payload.evaluationAttemptOrdinal = 2
        let codes = WriterIndependentEvaluationReceiptValidator.issues(
            in: replay,
            trustedSigningPublicKeysByID: trustedSigningKeys
        ).map(\.code)
        XCTAssertTrue(codes.contains(.invalidCount))
        XCTAssertTrue(codes.contains(.invalidSignature))
    }

    func testConsumptionBoundaryRejectsSecondIndependentlySignedOrdinalOneReceipt() throws {
        let gate = pilotGate()
        let first = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        var secondAggregate = passingAggregate()
        secondAggregate.stablePreviewP95Milliseconds += 1
        let second = try signedReceipt(aggregate: secondAggregate, gate: gate)
        XCTAssertEqual(first.payload.evaluationAttemptOrdinal, 1)
        XCTAssertEqual(second.payload.evaluationAttemptOrdinal, 1)
        XCTAssertNotEqual(first.signatureBase64, second.signatureBase64)

        let ledger = WriterIndependentEvaluationAuthorizationLedger(
            maximumFamilyWiseAlphaByHoldoutID: [holdoutID: 0.05]
        )
        XCTAssertNil(ledger.register(authorization(for: first, gate: gate)))
        let checkpoint = try signedFreshnessCheckpoint(for: first)
        let firstResult = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: first,
            expected: try expectation(gate: gate),
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: checkpoint,
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertTrue(firstResult.passed)

        let replay = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: second,
            expected: try expectation(gate: gate),
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: checkpoint,
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(replay.gateFailures, [])
        XCTAssertEqual(replay.consumptionFailures.map(\.code), [.authorizationAlreadyConsumed])
        XCTAssertFalse(replay.authorizationConsumed)
        XCTAssertFalse(replay.passed)
    }

    func testNewAuthorizationCannotOverspendTheSameHoldoutAfterSnapshotRotation() throws {
        var gate = pilotGate()
        gate.overallFamilyWiseAlpha = 0.03
        let firstID = "sealed-authorization-alpha-a"
        let secondID = "sealed-authorization-alpha-b"
        let first = try signedReceipt(
            aggregate: passingAggregate(),
            gate: gate,
            authorizationID: firstID
        )
        let second = try signedReceipt(
            aggregate: passingAggregate(),
            gate: gate,
            authorizationID: secondID,
            provenanceHashSeed: 14
        )
        let ledger = WriterIndependentEvaluationAuthorizationLedger(
            maximumFamilyWiseAlphaByHoldoutID: [holdoutID: 0.05]
        )
        XCTAssertNil(ledger.register(authorization(for: first, gate: gate)))
        XCTAssertNil(ledger.register(authorization(for: second, gate: gate)))
        let firstCheckpoint = try signedFreshnessCheckpoint(for: first)

        XCTAssertTrue(
            WriterIndependentEvaluationConsumptionBoundary.consume(
                receipt: first,
                expected: try expectation(gate: gate, authorizationID: firstID),
                trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
                gate: gate,
                freshnessCheckpoint: firstCheckpoint,
                trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
                currentUnixSeconds: consumptionTime,
                authorizationLedger: ledger
            ).passed
        )
        let overspend = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: second,
            expected: try expectation(
                gate: gate,
                authorizationID: secondID,
                provenanceHashSeed: 14
            ),
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: try signedFreshnessCheckpoint(for: second),
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(overspend.gateFailures, [])
        XCTAssertEqual(overspend.consumptionFailures.map(\.code), [.holdoutAlphaBudgetExceeded])
        XCTAssertFalse(overspend.authorizationConsumed)
    }

    func testConsumptionRequiresCurrentSignedProvenanceAndGroundTruthCheckpoint() throws {
        let gate = pilotGate()
        let receipt = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        let expected = try expectation(gate: gate)
        let ledger = WriterIndependentEvaluationAuthorizationLedger(
            maximumFamilyWiseAlphaByHoldoutID: [holdoutID: 0.05]
        )
        XCTAssertNil(ledger.register(authorization(for: receipt, gate: gate)))

        var expiredProvenance = freshnessPayload(for: receipt)
        expiredProvenance.provenanceValidUntilUnixSeconds = consumptionTime
        let expiredResult = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: receipt,
            expected: expected,
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: try signedFreshnessCheckpoint(payload: expiredProvenance),
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(expiredResult.consumptionFailures.map(\.code), [.staleOrRevokedProvenance])

        var revokedProvenance = freshnessPayload(for: receipt)
        revokedProvenance.provenanceState = .revoked
        let revokedResult = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: receipt,
            expected: expected,
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: try signedFreshnessCheckpoint(payload: revokedProvenance),
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(revokedResult.consumptionFailures.map(\.code), [.staleOrRevokedProvenance])

        var revokedGroundTruth = freshnessPayload(for: receipt)
        revokedGroundTruth.groundTruthState = .revoked
        let groundTruthResult = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: receipt,
            expected: expected,
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: try signedFreshnessCheckpoint(payload: revokedGroundTruth),
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(groundTruthResult.consumptionFailures.map(\.code), [.staleOrRevokedGroundTruth])

        var tamperedCheckpoint = try signedFreshnessCheckpoint(for: receipt)
        tamperedCheckpoint.payload.checkpointID = "tampered-after-signing"
        let tamperedResult = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: receipt,
            expected: expected,
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: tamperedCheckpoint,
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(tamperedResult.consumptionFailures.map(\.code), [.invalidFreshnessCheckpoint])

        XCTAssertTrue(
            WriterIndependentEvaluationConsumptionBoundary.consume(
                receipt: receipt,
                expected: expected,
                trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
                gate: gate,
                freshnessCheckpoint: try signedFreshnessCheckpoint(for: receipt),
                trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
                currentUnixSeconds: consumptionTime,
                authorizationLedger: ledger
            ).passed
        )
    }

    func testFailingGateStillConsumesAuthorizationAndPreventsSelectiveReplay() throws {
        let gate = pilotGate()
        var failingAggregate = passingAggregate()
        failingAggregate.stablePreviewP95Milliseconds = 1_101
        let failingReceipt = try signedReceipt(aggregate: failingAggregate, gate: gate)
        let passingReceipt = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        let ledger = WriterIndependentEvaluationAuthorizationLedger(
            maximumFamilyWiseAlphaByHoldoutID: [holdoutID: 0.05]
        )
        XCTAssertNil(ledger.register(authorization(for: failingReceipt, gate: gate)))
        let checkpoint = try signedFreshnessCheckpoint(for: failingReceipt)

        let failure = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: failingReceipt,
            expected: try expectation(gate: gate),
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: checkpoint,
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(failure.gateFailures.map(\.code), [.stablePreviewLatency])
        XCTAssertTrue(failure.authorizationConsumed)
        XCTAssertFalse(failure.passed)

        let selectiveReplay = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: passingReceipt,
            expected: try expectation(gate: gate),
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: checkpoint,
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(selectiveReplay.consumptionFailures.map(\.code), [.authorizationAlreadyConsumed])
    }

    func testAuthenticMalformedReceiptStillConsumesAuthorization() throws {
        let gate = pilotGate()
        var malformedAggregate = passingAggregate()
        malformedAggregate.recognitionComputeP95Milliseconds = -1
        let malformed = try signedReceipt(aggregate: malformedAggregate, gate: gate)
        let passing = try signedReceipt(aggregate: passingAggregate(), gate: gate)
        let ledger = WriterIndependentEvaluationAuthorizationLedger(
            maximumFamilyWiseAlphaByHoldoutID: [holdoutID: 0.05]
        )
        XCTAssertNil(ledger.register(authorization(for: malformed, gate: gate)))
        let checkpoint = try signedFreshnessCheckpoint(for: malformed)

        let malformedResult = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: malformed,
            expected: try expectation(gate: gate),
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: checkpoint,
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(malformedResult.gateFailures.map(\.code), [.invalidReceipt])
        XCTAssertTrue(malformedResult.authorizationConsumed)
        XCTAssertFalse(malformedResult.passed)

        let retry = WriterIndependentEvaluationConsumptionBoundary.consume(
            receipt: passing,
            expected: try expectation(gate: gate),
            trustedEvaluationSigningPublicKeysByID: trustedSigningKeys,
            gate: gate,
            freshnessCheckpoint: checkpoint,
            trustedFreshnessSigningPublicKeysByID: trustedFreshnessKeys,
            currentUnixSeconds: consumptionTime,
            authorizationLedger: ledger
        )
        XCTAssertEqual(retry.consumptionFailures.map(\.code), [.authorizationAlreadyConsumed])
    }

    private var trustedSigningKeys: [String: Data] {
        ["evaluation-key-v1": signingKey.publicKey.rawRepresentation]
    }

    private var trustedFreshnessKeys: [String: Data] {
        ["freshness-authority-key-v1": freshnessSigningKey.publicKey.rawRepresentation]
    }

    private var consumptionTime: Int64 { 1_800_000_000 }
    private var holdoutID: String { "sealed-writer-cohort-pilot-v1" }

    private func signedReceipt(
        aggregate: WriterIndependentEvaluationAggregate,
        gate: WriterIndependentRecognitionGate,
        split: WriterIndependentEvaluationSplit = .sealedTest,
        authorizationID: String = "sealed-authorization-0001",
        provenanceHashSeed: Int = 11
    ) throws -> SignedWriterIndependentEvaluationReceipt {
        let manifestHash = sha256(10)
        let provenanceHash = sha256(provenanceHashSeed)
        let groundTruthRoot = sha256(12)
        let groundTruthSnapshotHash = sha256(13)
        let writerRoot = WriterIndependentMerkleCommitment.root(
            strings: aggregate.writerOutcomeSummaries.map(\.writerCommitmentSHA256)
        )
        let payload = WriterIndependentEvaluationReceiptPayload(
            evaluationProtocolVersion: WriterIndependentEvaluationProtocolContract.currentVersion,
            evaluationSplit: split,
            evaluationAuthorizationID: authorizationID,
            evaluationAttemptOrdinal: 1,
            datasetVersion: "writer-study-pilot-v1",
            datasetMerkleRootSHA256: WriterIndependentEvaluationReceiptPayload.datasetCommitmentSHA256(
                evaluationManifestSHA256: manifestHash,
                provenanceSnapshotSHA256: provenanceHash,
                groundTruthSnapshotSHA256: groundTruthSnapshotHash,
                groundTruthMerkleRootSHA256: groundTruthRoot
            ),
            evaluationManifestSHA256: manifestHash,
            provenanceSnapshotSHA256: provenanceHash,
            groundTruthRegistryVersion: "ground-truth-registry-v1",
            groundTruthRegistryEpoch: 11,
            groundTruthSnapshotSHA256: groundTruthSnapshotHash,
            groundTruthMerkleRootSHA256: groundTruthRoot,
            recognizerArtifactSHA256: sha256(2),
            evaluatorArtifactSHA256: sha256(3),
            latencyDeviceClass: "oldest-supported",
            pipelineVersion: "shadow-candidate-v1",
            calibrationVersion: "calibration-v1",
            metricDefinitionVersion: "writer-clustered-selective-risk-v1",
            gateDefinitionID: gate.definitionID,
            gateDefinitionSHA256: try gate.definitionSHA256(),
            writerCommitmentSchemeVersion: "receipt-hmac-sha256-v1",
            writerCommitmentMerkleRootSHA256: writerRoot,
            aggregate: aggregate
        )
        let signature = try signingKey.signature(for: payload.canonicalData())
        return SignedWriterIndependentEvaluationReceipt(
            payload: payload,
            signingKeyID: "evaluation-key-v1",
            signatureBase64: signature.base64EncodedString()
        )
    }

    private func expectation(
        gate: WriterIndependentRecognitionGate,
        authorizationID: String = "sealed-authorization-0001",
        provenanceHashSeed: Int = 11
    ) throws -> WriterIndependentEvaluationExpectation {
        let manifestHash = sha256(10)
        let provenanceHash = sha256(provenanceHashSeed)
        let groundTruthRoot = sha256(12)
        let groundTruthSnapshotHash = sha256(13)
        let aggregate = passingAggregate()
        return WriterIndependentEvaluationExpectation(
            evaluationProtocolVersion: WriterIndependentEvaluationProtocolContract.currentVersion,
            requiredSplit: .sealedTest,
            evaluationAuthorizationID: authorizationID,
            evaluationAttemptOrdinal: 1,
            independentWriterCount: 10,
            independentHumanCaptureCount: 1_050,
            datasetVersion: "writer-study-pilot-v1",
            datasetMerkleRootSHA256: WriterIndependentEvaluationReceiptPayload.datasetCommitmentSHA256(
                evaluationManifestSHA256: manifestHash,
                provenanceSnapshotSHA256: provenanceHash,
                groundTruthSnapshotSHA256: groundTruthSnapshotHash,
                groundTruthMerkleRootSHA256: groundTruthRoot
            ),
            evaluationManifestSHA256: manifestHash,
            provenanceSnapshotSHA256: provenanceHash,
            groundTruthRegistryVersion: "ground-truth-registry-v1",
            groundTruthRegistryEpoch: 11,
            groundTruthSnapshotSHA256: groundTruthSnapshotHash,
            groundTruthMerkleRootSHA256: groundTruthRoot,
            recognizerArtifactSHA256: sha256(2),
            evaluatorArtifactSHA256: sha256(3),
            latencyDeviceClass: "oldest-supported",
            pipelineVersion: "shadow-candidate-v1",
            calibrationVersion: "calibration-v1",
            metricDefinitionVersion: "writer-clustered-selective-risk-v1",
            writerCommitmentSchemeVersion: "receipt-hmac-sha256-v1",
            writerCommitmentMerkleRootSHA256: WriterIndependentMerkleCommitment.root(
                strings: aggregate.writerOutcomeSummaries.map(\.writerCommitmentSHA256)
            ),
            expectedStrata: expectedStrata.map {
                WriterIndependentExpectedStratum(
                    key: $0.key,
                    independentWriterCount: $0.independentWriterCount,
                    writerMembershipMerkleRootSHA256: $0.writerMembershipMerkleRootSHA256,
                    humanSampleCount: $0.humanSampleCount
                )
            },
            gateDefinitionID: gate.definitionID,
            gateDefinitionSHA256: try gate.definitionSHA256()
        )
    }

    private func authorization(
        for receipt: SignedWriterIndependentEvaluationReceipt,
        gate: WriterIndependentRecognitionGate
    ) -> WriterIndependentEvaluationAuthorization {
        WriterIndependentEvaluationAuthorization(
            authorizationID: receipt.payload.evaluationAuthorizationID,
            evaluationProtocolVersion: receipt.payload.evaluationProtocolVersion,
            holdoutID: holdoutID,
            datasetMerkleRootSHA256: receipt.payload.datasetMerkleRootSHA256,
            recognizerArtifactSHA256: receipt.payload.recognizerArtifactSHA256,
            evaluatorArtifactSHA256: receipt.payload.evaluatorArtifactSHA256,
            gateDefinitionSHA256: receipt.payload.gateDefinitionSHA256,
            familyWiseAlpha: gate.overallFamilyWiseAlpha
        )
    }

    private func freshnessPayload(
        for receipt: SignedWriterIndependentEvaluationReceipt
    ) -> WriterIndependentEvaluationFreshnessCheckpointPayload {
        WriterIndependentEvaluationFreshnessCheckpointPayload(
            checkpointID: "freshness-checkpoint-0001",
            issuedAtUnixSeconds: consumptionTime - 60,
            expiresAtUnixSeconds: consumptionTime + 60,
            provenanceSnapshotSHA256: receipt.payload.provenanceSnapshotSHA256,
            provenanceValidUntilUnixSeconds: consumptionTime + 3_600,
            provenanceState: .current,
            groundTruthRegistryVersion: receipt.payload.groundTruthRegistryVersion,
            groundTruthRegistryEpoch: receipt.payload.groundTruthRegistryEpoch,
            groundTruthSnapshotSHA256: receipt.payload.groundTruthSnapshotSHA256,
            groundTruthMerkleRootSHA256: receipt.payload.groundTruthMerkleRootSHA256,
            groundTruthValidUntilUnixSeconds: consumptionTime + 3_600,
            groundTruthState: .current
        )
    }

    private func signedFreshnessCheckpoint(
        for receipt: SignedWriterIndependentEvaluationReceipt
    ) throws -> SignedWriterIndependentEvaluationFreshnessCheckpoint {
        try signedFreshnessCheckpoint(payload: freshnessPayload(for: receipt))
    }

    private func signedFreshnessCheckpoint(
        payload: WriterIndependentEvaluationFreshnessCheckpointPayload
    ) throws -> SignedWriterIndependentEvaluationFreshnessCheckpoint {
        let signature = try freshnessSigningKey.signature(for: payload.canonicalData())
        return SignedWriterIndependentEvaluationFreshnessCheckpoint(
            payload: payload,
            signingKeyID: "freshness-authority-key-v1",
            signatureBase64: signature.base64EncodedString()
        )
    }

    private func passingAggregate() -> WriterIndependentEvaluationAggregate {
        WriterIndependentEvaluationAggregate(
            independentWriterCount: 10,
            independentHumanCaptureCount: 1_050,
            syntheticDerivativeStressCount: 0,
            legibleValidCount: 1_000,
            humanAmbiguousOrNegativeCount: 40,
            executionErrorCount: 5,
            technicalInvalidCount: 5,
            exactCorrectCount: 920,
            topThreeCorrectCount: 980,
            trustedLegibleCount: 700,
            trustedWrongLegibleCount: 0,
            confirmationCount: 170,
            candidateReviewCount: 100,
            noReadCount: 30,
            falseTrustedAmbiguousOrNegativeCount: 0,
            ownershipTruePositiveCount: 990,
            ownershipFalsePositiveCount: 5,
            ownershipFalseNegativeCount: 5,
            frozenTargetMutationCount: 0,
            writerOutcomeSummaries: (0..<10).map { index in
                WriterIndependentWriterOutcomeSummary(
                    writerCommitmentSHA256: sha256(5_000 + index),
                    legibleValidCount: 100,
                    exactCorrectCount: 92,
                    topThreeCorrectCount: 98,
                    trustedLegibleCount: 70,
                    trustedWrongLegibleCount: 0
                )
            },
            strata: expectedStrata,
            expectedCalibrationError: 0.025,
            brierScore: 0.07,
            recognitionComputeP95Milliseconds: 90,
            stablePreviewP95Milliseconds: 850
        )
    }

    private func pilotGate() -> WriterIndependentRecognitionGate {
        WriterIndependentRecognitionGate(
            definitionID: "sealed-falsification-pilot-v1",
            evaluationProtocolVersion: WriterIndependentEvaluationProtocolContract.currentVersion,
            uncertaintyMethodVersion: WriterIndependentRecognitionGateEvaluator
                .supportedUncertaintyMethodVersion,
            overallFamilyWiseAlpha: 0.05,
            writerPassPredicateVersion: WriterIndependentRecognitionGateEvaluator
                .supportedWriterPassPredicateVersion,
            minimumWriterPassLegibleCount: 60,
            minimumWriterPassExactAccuracy: 0.85,
            minimumWriterPassTopThreeAccuracy: 0.95,
            minimumWriterPassTrustedCoverage: 0.35,
            maximumWriterPassTrustedWrongCount: 0,
            maximumWriterPassTrustedRisk: 0.005,
            writerPassProbabilityMethodVersion: WriterIndependentRecognitionGateEvaluator
                .supportedWriterPassProbabilityMethodVersion,
            minimumWriterPassProbabilityLowerBound: 0.60,
            minimumIndependentWriters: 10,
            minimumLegibleSamples: 900,
            minimumAmbiguousOrNegativeSamples: 20,
            minimumEvaluableHumanSamplesPerWriter: 60,
            minimumExactAccuracyLowerBound: 0,
            minimumTopThreeAccuracyLowerBound: 0,
            maximumTrustedRiskUpperBound: 1,
            minimumTrustedCoverage: 0.55,
            minimumWriterMacroExactAccuracy: 0.90,
            minimumWriterTrustedCoverage: 0.35,
            minimumOwnershipF1: 0.98,
            maximumExpectedCalibrationError: 0.05,
            maximumBrierScore: 0.10,
            maximumTechnicalFailureRate: 0.02,
            maximumTrustedWrongLegibleCount: 0,
            maximumFalseTrustedAmbiguousOrNegativeCount: 0,
            maximumFrozenTargetMutationCount: 0,
            maximumRecognitionComputeP95Milliseconds: 150,
            maximumStablePreviewP95Milliseconds: 1_100,
            requiredStrata: expectedStrata.map { stratum in
                WriterIndependentEvaluationStratumRequirement(
                    key: stratum.key,
                    minimumIndependentWriterCount: 5,
                    minimumHumanSampleCount: 100,
                    minimumLegibleSampleCount: 80,
                    minimumExactAccuracy: 0.85,
                    minimumTrustedCoverage: 0.35,
                    maximumTrustedWrongLegibleCount: 0
                )
            }
        )
    }

    private var expectedStrata: [WriterIndependentEvaluationStratumAggregate] {
        var rows: [WriterIndependentEvaluationStratumAggregate] = [
            stratumAggregate(.naturalFrequency, .overall, "all", 550, 520, 478, 364),
            stratumAggregate(.familyBalanced, .overall, "all", 500, 480, 442, 336)
        ]

        let familyNames = ["major", "minor", "dominant", "altered", "slash-bass"]
        let familyExact = [89, 89, 88, 88, 88]
        let familyTrusted = [68, 67, 67, 67, 67]
        for index in familyNames.indices {
            rows.append(stratumAggregate(
                .familyBalanced,
                .chordFamily,
                familyNames[index],
                100,
                96,
                familyExact[index],
                familyTrusted[index]
            ))
        }

        let componentNames = ["root", "accidental", "quality", "extension", "alteration", "slash-bass", "repeat"]
        let componentExact = [476, 470, 465, 460, 455, 450, 468]
        for index in componentNames.indices {
            rows.append(stratumAggregate(
                .familyBalanced,
                .component,
                componentNames[index],
                500,
                480,
                componentExact[index],
                336
            ))
        }

        rows.append(stratumAggregate(.naturalFrequency, .chartStyle, "simple-chord-sheet", 275, 260, 239, 182))
        rows.append(stratumAggregate(.naturalFrequency, .chartStyle, "rhythm-section-sheet", 275, 260, 239, 182))
        rows.append(stratumAggregate(.naturalFrequency, .deviceClass, "oldest-supported", 275, 260, 239, 182))
        rows.append(stratumAggregate(.naturalFrequency, .deviceClass, "current-reference", 275, 260, 239, 182))
        rows.append(stratumAggregate(.naturalFrequency, .orientation, "portrait", 275, 260, 239, 182))
        rows.append(stratumAggregate(.naturalFrequency, .orientation, "landscape", 275, 260, 239, 182))
        appendNaturalThreeWayPartition(
            to: &rows,
            dimension: .pace,
            names: ["natural", "fast", "careful"]
        )
        appendNaturalThreeWayPartition(
            to: &rows,
            dimension: .sizeBucket,
            names: ["small", "normal", "large"]
        )
        rows.append(stratumAggregate(.naturalFrequency, .handedness, "left", 275, 260, 239, 182))
        rows.append(stratumAggregate(.naturalFrequency, .handedness, "right", 275, 260, 239, 182))
        rows.append(stratumAggregate(.naturalFrequency, .pencilExperience, "novice", 275, 260, 239, 182))
        rows.append(stratumAggregate(.naturalFrequency, .pencilExperience, "experienced", 275, 260, 239, 182))
        appendNaturalThreeWayPartition(
            to: &rows,
            dimension: .constructionVariation,
            names: ["rootFirst", "modifierFirst", "mixedOrRetraced"]
        )
        return rows
    }

    private func appendNaturalThreeWayPartition(
        to rows: inout [WriterIndependentEvaluationStratumAggregate],
        dimension: WriterIndependentEvaluationStratumDimension,
        names: [String]
    ) {
        let human = [184, 183, 183]
        let legible = [174, 173, 173]
        let exact = [160, 159, 159]
        let trusted = [122, 121, 121]
        for index in names.indices {
            rows.append(stratumAggregate(
                .naturalFrequency,
                dimension,
                names[index],
                human[index],
                legible[index],
                exact[index],
                trusted[index]
            ))
        }
    }

    private func stratumAggregate(
        _ population: WriterIndependentEvaluationPopulation,
        _ dimension: WriterIndependentEvaluationStratumDimension,
        _ value: String,
        _ human: Int,
        _ legible: Int,
        _ exact: Int,
        _ trusted: Int
    ) -> WriterIndependentEvaluationStratumAggregate {
        WriterIndependentEvaluationStratumAggregate(
            key: stratum(population, dimension, value),
            writerCommitmentsSHA256: writerCommitments,
            humanSampleCount: human,
            legibleValidCount: legible,
            exactCorrectCount: exact,
            trustedLegibleCount: trusted,
            trustedWrongLegibleCount: 0
        )
    }

    private var requiredStratumKeys: [WriterIndependentEvaluationStratumKey] {
        expectedStrata.map(\.key)
    }

    private var writerCommitments: [String] {
        (0..<10).map { sha256(5_000 + $0) }
    }

    private func stratum(
        _ population: WriterIndependentEvaluationPopulation,
        _ dimension: WriterIndependentEvaluationStratumDimension,
        _ value: String
    ) -> WriterIndependentEvaluationStratumKey {
        WriterIndependentEvaluationStratumKey(
            population: population,
            dimension: dimension,
            value: value
        )
    }

    private func sha256(_ value: Int) -> String {
        String(format: "%064x", value)
    }
}

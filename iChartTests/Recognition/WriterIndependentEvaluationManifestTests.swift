import CryptoKit
import XCTest
@testable import iChart

final class WriterIndependentEvaluationManifestTests: XCTestCase {
    private lazy var provenanceSigningKey = Curve25519.Signing.PrivateKey()
    private lazy var groundTruthSigningKey = Curve25519.Signing.PrivateKey()

    func testValidWriterDisjointManifestPassesValidation() {
        let development = sample(seed: 1, writer: 1, session: 1, split: .development)
        let calibration = sample(seed: 2, writer: 2, session: 2, split: .calibration)
        let sealed = sample(seed: 3, writer: 3, session: 3, split: .sealedTest)
        let manifest = manifest([development, calibration, sealed])

        XCTAssertEqual(
            validationIssues(manifest),
            []
        )
        XCTAssertEqual(
            WriterIndependentEvaluationManifestValidator.independentWriterCounts(in: manifest),
            [.development: 1, .calibration: 1, .sealedTest: 1]
        )
    }

    func testWriterAndSessionCannotCrossSplits() {
        let first = sample(seed: 1, writer: 1, session: 1, split: .development)
        let second = sample(seed: 2, writer: 1, session: 1, split: .sealedTest)

        XCTAssertEqual(
            issueCodes(manifest([first, second])),
            [.personCrossesGlobalSplits, .sessionCrossesSplits, .writerCrossesSplits]
        )
    }

    func testSessionCannotContainMultipleWriters() {
        let first = sample(seed: 1, writer: 1, session: 1, split: .development)
        let second = sample(seed: 2, writer: 2, session: 1, split: .development)

        XCTAssertEqual(
            issueCodes(manifest([first, second])),
            [.sessionCrossesGlobalPersons, .sessionCrossesWriters]
        )
    }

    func testDerivativeKeepsLineageAndDoesNotIncreaseIndependentCount() {
        let parent = sample(seed: 1, writer: 1, session: 1, split: .calibration)
        var derivative = sample(seed: 2, writer: 1, session: 1, split: .calibration)
        derivative.sourceKind = .syntheticDerivative
        derivative.parentSampleID = parent.sampleID
        derivative.labelRecordID = parent.labelRecordID
        derivative.consentRecordID = parent.consentRecordID
        derivative.geometryLeakageClusterID = parent.geometryLeakageClusterID
        derivative.leakageCheckVersion = parent.leakageCheckVersion
        let value = manifest([parent, derivative])

        XCTAssertEqual(
            validationIssues(value),
            []
        )
        XCTAssertEqual(
            WriterIndependentEvaluationManifestValidator.independentHumanCaptureCounts(in: value),
            [.calibration: 1]
        )
    }

    func testDerivativeCannotCrossWriterSplitSessionLabelOrConsent() {
        let parent = sample(seed: 1, writer: 1, session: 1, split: .development)
        var derivative = sample(seed: 2, writer: 2, session: 2, split: .sealedTest)
        derivative.sourceKind = .syntheticDerivative
        derivative.parentSampleID = parent.sampleID

        XCTAssertTrue(issueCodes(manifest([parent, derivative])).contains(.derivativeLineageMismatch))
    }

    func testDerivativeRequiresExistingParent() {
        var derivative = sample(seed: 1, writer: 1, session: 1, split: .development)
        derivative.sourceKind = .syntheticDerivative
        derivative.parentSampleID = UUID(uuidString: "00000000-0000-0000-0000-000000000999")!

        XCTAssertEqual(issueCodes(manifest([derivative])), [.derivativeParentMissing])
    }

    func testHumanCaptureCannotHaveParentAndDerivativeCannotOmitOne() {
        var human = sample(seed: 1, writer: 1, session: 1, split: .development)
        human.parentSampleID = UUID(uuidString: "00000000-0000-0000-0000-000000000999")!
        var derivative = sample(seed: 2, writer: 2, session: 2, split: .development)
        derivative.sourceKind = .syntheticDerivative

        XCTAssertEqual(
            issueCodes(manifest([human, derivative])),
            [.derivativeMissingParent, .humanCaptureHasParent]
        )
    }

    func testDuplicateGeometryAndIdentifiersAreRejected() {
        let first = sample(seed: 1, writer: 1, session: 1, split: .development)
        var second = sample(seed: 2, writer: 2, session: 2, split: .calibration)
        second.sampleID = first.sampleID
        second.labelRecordID = first.labelRecordID
        second.strokePayloadSHA256 = first.strokePayloadSHA256

        XCTAssertEqual(
            issueCodes(manifest([first, second])),
            [
                .duplicateLabelRecordID,
                .duplicatePayload,
                .duplicateProvenanceRecord,
                .duplicateSampleID,
                .sampleMissingFromCohortRegistry,
                .sampleMissingFromCohortRegistry
            ]
        )
    }

    func testRequiredHashesAndMetadataAreValidated() {
        var value = sample(seed: 1, writer: 1, session: 1, split: .development)
        value.writerIDHash = "writer-one"
        value.strokePayloadSHA256 = "ink"
        value.captureProtocolVersion = " "

        XCTAssertEqual(
            issueCodes(manifest([value])),
            [
                .invalidStrokePayloadHash,
                .invalidWriterIDHash,
                .invalidWriterIDHash,
                .missingMetadata,
                .unsupportedEvaluationProtocol
            ]
        )
    }

    func testSchemaAndDatasetIdentityAreRequired() {
        var value = manifest([sample(seed: 1, writer: 1, session: 1, split: .development)])
        value.schemaVersion = 999
        value.datasetVersion = " "

        XCTAssertEqual(
            issueCodes(value),
            [.missingDatasetVersion, .provenanceContentCommitmentMismatch, .unsupportedSchemaVersion]
        )
    }

    func testDerivativeCyclesAreRejected() {
        var first = sample(seed: 1, writer: 1, session: 1, split: .development)
        var second = sample(seed: 2, writer: 1, session: 1, split: .development)
        first.sourceKind = .syntheticDerivative
        first.parentSampleID = second.sampleID
        second.sourceKind = .syntheticDerivative
        second.parentSampleID = first.sampleID
        second.labelRecordID = first.labelRecordID
        second.consentRecordID = first.consentRecordID
        second.geometryLeakageClusterID = first.geometryLeakageClusterID

        let codes = issueCodes(manifest([first, second]))
        XCTAssertEqual(codes.filter { $0 == .derivativeCycle }.count, 2)
        XCTAssertFalse(codes.contains(.derivativeLineageMismatch))
    }

    func testManifestRoundTripsWithoutExposingChordLabelsOrInk() throws {
        let value = manifest([
            sample(seed: 1, writer: 1, session: 1, split: .development),
            sample(seed: 2, writer: 2, session: 2, split: .sealedTest)
        ])
        let encoded = try JSONEncoder().encode(value)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(try JSONDecoder().decode(WriterIndependentEvaluationManifest.self, from: encoded), value)
        XCTAssertFalse(json.contains("expectedDisplayText"))
        XCTAssertFalse(json.contains("strokes"))
        XCTAssertFalse(json.contains("chordText"))
    }

    func testLegacyArchiveIsNeverAnEvaluationDenominator() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)

        XCTAssertFalse(fixtures.isEmpty)
        XCTAssertEqual(LegacyInkFixtureCorpusPolicy.datasetVersion, "legacy-regression-v1")
        XCTAssertEqual(LegacyInkFixtureCorpusPolicy.provenance, "unknown")
        XCTAssertFalse(LegacyInkFixtureCorpusPolicy.evaluationEligible)
    }

    func testUppercaseWriterHashCannotBypassWriterSplitBoundary() {
        let first = sample(seed: 1, writer: 10, session: 1, split: .development)
        var second = sample(seed: 2, writer: 10, session: 2, split: .sealedTest)
        second.writerIDHash = first.writerIDHash.uppercased()

        let codes = issueCodes(manifest([first, second]))
        XCTAssertTrue(codes.contains(.invalidWriterIDHash))
        XCTAssertTrue(codes.contains(.writerCrossesSplits))
    }

    func testConsentMustBeActiveAndBoundToWriterScopeAndDataset() {
        let value = manifest([sample(seed: 1, writer: 1, session: 1, split: .development)])
        var provenance = provenancePayload(for: value)
        provenance.consentRecords[0].isActive = false
        provenance.consentRecords[0].writerIDHash = sha256(999)
        provenance.consentRecords[0].researchScopes = []
        provenance.consentRecords[0].datasetVersions = ["some-other-dataset"]

        XCTAssertEqual(
            validationIssues(value, provenance: signedProvenance(payload: provenance)).map(\.code),
            [
                .consentDatasetMismatch,
                .consentScopeMismatch,
                .consentWriterMismatch,
                .inactiveConsent,
                .provenanceContentCommitmentMismatch
            ]
        )
    }

    func testConsentCannotBeReusedForAnotherManifestWriter() {
        let first = sample(seed: 1, writer: 1, session: 1, split: .development)
        var second = sample(seed: 2, writer: 2, session: 2, split: .development)
        second.consentRecordID = first.consentRecordID
        let value = manifest([first, second])

        let codes = validationIssues(value).map(\.code)
        XCTAssertTrue(codes.contains(.consentCrossesWriters))
        XCTAssertTrue(codes.contains(.consentWriterMismatch))
    }

    func testNearDuplicateClusterCannotInflateHumansOrCrossBoundaries() {
        let first = sample(seed: 1, writer: 1, session: 1, split: .development)
        var second = sample(seed: 2, writer: 2, session: 2, split: .sealedTest)
        second.geometryLeakageClusterID = first.geometryLeakageClusterID

        XCTAssertEqual(
            issueCodes(manifest([first, second])),
            [.cohortRegistryLeakageBoundary, .duplicateHumanGeometryCluster, .geometryClusterCrossesBoundary]
        )
    }

    func testManifestMustBindToSignedProvenanceRoots() {
        var value = manifest([sample(seed: 1, writer: 1, session: 1, split: .development)])
        let provenance = signedProvenance(for: value)
        value.cohortRegistryMerkleRootSHA256 = "not-a-hash"

        XCTAssertEqual(
            validationIssues(value, provenance: provenance).map(\.code),
            [.missingRegistryIdentity, .provenanceIdentityMismatch]
        )
    }

    func testTamperedOrUnknownProvenanceSignatureFailsClosed() {
        let value = manifest([sample(seed: 1, writer: 1, session: 1, split: .development)])
        var provenance = signedProvenance(for: value)
        provenance.payload.consentRecords[0].isActive = false

        XCTAssertEqual(validationIssues(value, provenance: provenance).map(\.code), [.invalidProvenanceSnapshot])
        XCTAssertEqual(
            WriterIndependentEvaluationManifestValidator.issues(
                in: value,
                provenanceSnapshot: signedProvenance(for: value),
                trustedProvenancePublicKeysByID: [
                    "other-key": Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
                ],
                expectedProvenance: provenanceExpectation(for: signedProvenance(for: value))
            ).map(\.code),
            [.invalidProvenanceSnapshot]
        )
    }

    func testSignedRegistryRejectsMintedClusterAndDenylistedOrMissingPayload() {
        var value = manifest([sample(seed: 1, writer: 1, session: 1, split: .development)])
        var provenancePayload = self.provenancePayload(for: value)
        let signedOriginal = signedProvenance(payload: provenancePayload)
        value.samples[0].geometryLeakageClusterID = uuid(999)
        XCTAssertEqual(
            validationIssues(value, provenance: signedOriginal).map(\.code),
            [.cohortRegistryRecordMismatch]
        )

        value = manifest([sample(seed: 1, writer: 1, session: 1, split: .development)])
        provenancePayload = self.provenancePayload(for: value)
        provenancePayload.cohortRecords[0].eligibility = .legacyOrTemplateDenylisted
        XCTAssertEqual(
            validationIssues(value, provenance: signedProvenance(payload: provenancePayload)).map(\.code),
            [
                .cohortRegistryCompletenessMismatch,
                .cohortRegistryDenylisted,
                .provenanceContentCommitmentMismatch
            ]
        )

        provenancePayload = self.provenancePayload(for: value)
        provenancePayload.cohortRecords = []
        XCTAssertEqual(
            validationIssues(value, provenance: signedProvenance(payload: provenancePayload)).map(\.code),
            [
                .cohortRegistryCompletenessMismatch,
                .provenanceContentCommitmentMismatch,
                .sampleMissingFromCohortRegistry
            ]
        )
    }

    func testSignedRegistryPreventsFavorableSliceRelabeling() {
        var value = manifest([sample(seed: 1, writer: 1, session: 1, split: .sealedTest)])
        let provenance = signedProvenance(for: value)
        value.samples[0].chartStyle = .leadSheet
        value.samples[0].orientation = .landscape
        value.samples[0].pace = .careful
        value.samples[0].sizeBucket = .large

        XCTAssertEqual(
            validationIssues(value, provenance: provenance).map(\.code),
            [.cohortRegistryRecordMismatch]
        )
    }

    func testSignedRegistryCompletenessPreventsEligibleSampleCherryPicking() {
        let value = manifest([
            sample(seed: 1, writer: 1, session: 1, split: .development),
            sample(seed: 2, writer: 2, session: 2, split: .sealedTest)
        ])
        let provenance = signedProvenance(for: value)
        var subset = value
        subset.samples.removeFirst()

        XCTAssertTrue(
            validationIssues(subset, provenance: provenance)
                .map(\.code)
                .contains(.cohortRegistryCompletenessMismatch)
        )
    }

    func testSignedRegistryDetectsLeakageAgainstAnUnselectedCohortOrLegacyRow() {
        var value = manifest([sample(seed: 1, writer: 1, session: 1, split: .sealedTest)])
        var payload = provenancePayload(for: value)
        var external = payload.cohortRecords[0]
        external.sampleID = uuid(999)
        external.datasetVersion = "other-cohort-v1"
        external.strokePayloadSHA256 = sha256(999)
        external.writerIDHash = sha256(999)
        external.captureSessionID = uuid(998)
        external.split = .development
        external.labelRecordID = uuid(997)
        external.consentRecordID = uuid(996)
        payload.cohortRecords.append(external)
        payload = recomputingRoots(payload)
        value.cohortRegistryMerkleRootSHA256 = payload.cohortRegistryMerkleRootSHA256

        XCTAssertTrue(
            validationIssues(value, provenance: signedProvenance(payload: payload))
                .map(\.code)
                .contains(.cohortRegistryLeakageBoundary)
        )
    }

    func testSelectedRowCannotShareAClusterWithQuarantinedRegistryInk() {
        var value = manifest([sample(seed: 1, writer: 1, session: 1, split: .sealedTest)])
        var payload = provenancePayload(for: value)
        var quarantined = payload.cohortRecords[0]
        quarantined.sampleID = uuid(999)
        quarantined.datasetVersion = "quarantine-v1"
        quarantined.strokePayloadSHA256 = sha256(999)
        quarantined.writerIDHash = sha256(999)
        quarantined.personLinkageHMACSHA256 = sha256(998)
        quarantined.captureSessionID = uuid(997)
        quarantined.labelRecordID = uuid(996)
        quarantined.consentRecordID = uuid(995)
        quarantined.eligibility = .quarantined
        payload.cohortRecords.append(quarantined)
        payload = recomputingRoots(payload)
        value.cohortRegistryMerkleRootSHA256 = payload.cohortRegistryMerkleRootSHA256

        XCTAssertTrue(
            validationIssues(value, provenance: signedProvenance(payload: payload))
                .map(\.code)
                .contains(.cohortRegistryLeakageBoundary)
        )
    }

    func testCurrentCheckpointAndExpiryPreventConsentSnapshotReplay() {
        let value = manifest([sample(seed: 1, writer: 1, session: 1, split: .sealedTest)])
        let oldSnapshot = signedProvenance(for: value)
        var currentPayload = oldSnapshot.payload
        currentPayload.consentLedgerEpoch += 1
        currentPayload.consentRecords[0].isActive = false
        currentPayload = recomputingRoots(currentPayload)
        let currentSnapshot = signedProvenance(payload: currentPayload)

        XCTAssertEqual(
            WriterIndependentEvaluationManifestValidator.issues(
                in: value,
                provenanceSnapshot: oldSnapshot,
                trustedProvenancePublicKeysByID: trustedProvenanceKeys,
                expectedProvenance: provenanceExpectation(for: currentSnapshot)
            ).map(\.code),
            [.staleProvenanceSnapshot]
        )

        var expiredPayload = oldSnapshot.payload
        expiredPayload.expiresAtUnixSeconds = 1_700_000_001
        expiredPayload = recomputingRoots(expiredPayload)
        let expired = signedProvenance(payload: expiredPayload)
        XCTAssertTrue(
            WriterIndependentEvaluationManifestValidator.issues(
                in: value,
                provenanceSnapshot: expired,
                trustedProvenancePublicKeysByID: trustedProvenanceKeys,
                expectedProvenance: provenanceExpectation(for: expired)
            ).map(\.code).contains(.staleProvenanceSnapshot)
        )
    }

    func testGlobalPersonLinkageRejectsCrossDatasetRoleReuseWithoutGeometryCollision() {
        var value = manifest([sample(seed: 1, writer: 1, session: 1, split: .sealedTest)])
        var payload = provenancePayload(for: value)
        var historical = payload.cohortRecords[0]
        historical.sampleID = uuid(991)
        historical.datasetVersion = "historical-training-v1"
        historical.strokePayloadSHA256 = sha256(991)
        historical.writerIDHash = sha256(991)
        historical.captureSessionID = uuid(992)
        historical.split = .development
        historical.labelRecordID = uuid(993)
        historical.consentRecordID = uuid(994)
        historical.geometryLeakageClusterID = uuid(995)
        payload.cohortRecords.append(historical)
        payload = recomputingRoots(payload)
        value.cohortRegistryMerkleRootSHA256 = payload.cohortRegistryMerkleRootSHA256
        let snapshot = signedProvenance(payload: payload)

        XCTAssertTrue(
            WriterIndependentEvaluationManifestValidator.issues(
                in: value,
                provenanceSnapshot: snapshot,
                trustedProvenancePublicKeysByID: trustedProvenanceKeys,
                expectedProvenance: provenanceExpectation(for: snapshot)
            ).map(\.code).contains(.personCrossesGlobalSplits)
        )
    }

    func testSignedGroundTruthRequiresCompleteIndependentFrozenLabels() {
        let value = manifest([
            sample(seed: 1, writer: 1, session: 1, split: .sealedTest),
            sample(seed: 2, writer: 2, session: 2, split: .sealedTest)
        ])
        let valid = signedGroundTruth(for: value)
        XCTAssertEqual(groundTruthIssues(value, registry: valid), [])

        var incompletePayload = valid.payload
        incompletePayload.records.removeLast()
        incompletePayload = recomputingGroundTruthRoot(incompletePayload)
        let incomplete = signedGroundTruth(payload: incompletePayload)
        XCTAssertTrue(
            groundTruthIssues(value, registry: incomplete).map(\.code).contains(.completenessMismatch)
        )

        var dependentPayload = valid.payload
        dependentPayload.records[0].secondReaderHMACSHA256 =
            dependentPayload.records[0].firstReaderHMACSHA256
        dependentPayload = recomputingGroundTruthRoot(dependentPayload)
        let dependent = signedGroundTruth(payload: dependentPayload)
        XCTAssertTrue(
            groundTruthIssues(value, registry: dependent).map(\.code).contains(.readersNotIndependent)
        )

        var staleRootPayload = valid.payload
        staleRootPayload.records[0].legibility = .humanAmbiguousOrNegative
        let staleRoot = signedGroundTruth(payload: staleRootPayload)
        XCTAssertTrue(
            groundTruthIssues(value, registry: staleRoot).map(\.code).contains(.contentCommitmentMismatch)
        )

        var signatureTampered = valid
        signatureTampered.payload.records[0].isFrozen = false
        XCTAssertEqual(
            groundTruthIssues(value, registry: signatureTampered).map(\.code),
            [.invalidSignature]
        )
    }

    func testGroundTruthDisagreementRequiresAdjudicationAndFrozenLegibility() {
        let value = manifest([sample(seed: 1, writer: 1, session: 1, split: .sealedTest)])
        var payload = groundTruthPayload(for: value)
        payload.records[0].secondReaderLabelCommitmentSHA256 = sha256(880)
        payload.records[0].adjudicatorHMACSHA256 = nil
        payload.records[0].adjudicatedLabelCommitmentSHA256 = nil
        payload.records[0].isFrozen = false
        payload = recomputingGroundTruthRoot(payload)
        let issues = groundTruthIssues(value, registry: signedGroundTruth(payload: payload)).map(\.code)

        XCTAssertTrue(issues.contains(.adjudicationRequired))
        XCTAssertTrue(issues.contains(.labelNotFrozen))

        var dependentAdjudicationPayload = payload
        dependentAdjudicationPayload.records[0].adjudicatorHMACSHA256 =
            dependentAdjudicationPayload.records[0].firstReaderHMACSHA256
        dependentAdjudicationPayload.records[0].adjudicatedLabelCommitmentSHA256 = sha256(881)
        dependentAdjudicationPayload.records[0].finalLabelCommitmentSHA256 = sha256(881)
        dependentAdjudicationPayload = recomputingGroundTruthRoot(dependentAdjudicationPayload)
        XCTAssertTrue(
            groundTruthIssues(
                value,
                registry: signedGroundTruth(payload: dependentAdjudicationPayload)
            ).map(\.code).contains(.invalidAdjudication)
        )
    }

    func testGroundTruthCurrentCheckpointAndExpiryPreventReplay() {
        let value = manifest([sample(seed: 1, writer: 1, session: 1, split: .sealedTest)])
        let old = signedGroundTruth(for: value)
        var currentPayload = old.payload
        currentPayload.registryEpoch += 1
        currentPayload.records[0].isEvaluationEligible = false
        currentPayload = recomputingGroundTruthRoot(currentPayload)
        let current = signedGroundTruth(payload: currentPayload)

        let staleIssues = WriterIndependentGroundTruthRegistryValidator.issues(
            in: old,
            for: value,
            trustedSigningPublicKeysByID: trustedGroundTruthKeys,
            expected: WriterIndependentGroundTruthExpectation(
                registryVersion: current.payload.registryVersion,
                merkleRootSHA256: current.payload.merkleRootSHA256,
                minimumRegistryEpoch: current.payload.registryEpoch,
                validationUnixSeconds: 1_800_000_000
            )
        ).map(\.code)
        XCTAssertTrue(staleIssues.contains(.staleRegistry))

        var expiredPayload = old.payload
        expiredPayload.expiresAtUnixSeconds = 1_700_000_001
        expiredPayload = recomputingGroundTruthRoot(expiredPayload)
        let expired = signedGroundTruth(payload: expiredPayload)
        XCTAssertTrue(
            groundTruthIssues(value, registry: expired).map(\.code).contains(.staleRegistry)
        )
    }

    private func manifest(
        _ samples: [WriterIndependentEvaluationSample]
    ) -> WriterIndependentEvaluationManifest {
        var value = WriterIndependentEvaluationManifest(
            datasetVersion: "writer-study-pilot-v1",
            cohortRegistryVersion: "all-cohorts-and-legacy-v1",
            cohortRegistryMerkleRootSHA256: sha256(0),
            consentLedgerSnapshotVersion: "consent-snapshot-v1",
            consentLedgerMerkleRootSHA256: sha256(0),
            samples: samples
        )
        let provenance = provenancePayload(for: value)
        value.cohortRegistryMerkleRootSHA256 = try! provenance.computedCohortRegistryMerkleRootSHA256()
        value.consentLedgerMerkleRootSHA256 = try! provenance.computedConsentLedgerMerkleRootSHA256()
        return value
    }

    private func issueCodes(
        _ manifest: WriterIndependentEvaluationManifest
    ) -> [WriterIndependentEvaluationValidationIssue.Code] {
        validationIssues(manifest).map(\.code)
    }

    private var trustedProvenanceKeys: [String: Data] {
        ["collection-service-key-v1": provenanceSigningKey.publicKey.rawRepresentation]
    }

    private func validationIssues(
        _ manifest: WriterIndependentEvaluationManifest,
        provenance: SignedWriterIndependentProvenanceSnapshot? = nil
    ) -> [WriterIndependentEvaluationValidationIssue] {
        let snapshot = provenance ?? signedProvenance(for: manifest)
        return WriterIndependentEvaluationManifestValidator.issues(
            in: manifest,
            provenanceSnapshot: snapshot,
            trustedProvenancePublicKeysByID: trustedProvenanceKeys,
            expectedProvenance: provenanceExpectation(for: snapshot)
        )
    }

    private func provenanceExpectation(
        for snapshot: SignedWriterIndependentProvenanceSnapshot,
        validationUnixSeconds: Int64 = 1_800_000_000
    ) -> WriterIndependentProvenanceExpectation {
        WriterIndependentProvenanceExpectation(
            cohortRegistryVersion: snapshot.payload.cohortRegistryVersion,
            cohortRegistryMerkleRootSHA256: snapshot.payload.cohortRegistryMerkleRootSHA256,
            minimumCohortRegistryEpoch: snapshot.payload.cohortRegistryEpoch,
            consentLedgerSnapshotVersion: snapshot.payload.consentLedgerSnapshotVersion,
            consentLedgerMerkleRootSHA256: snapshot.payload.consentLedgerMerkleRootSHA256,
            minimumConsentLedgerEpoch: snapshot.payload.consentLedgerEpoch,
            validationUnixSeconds: validationUnixSeconds
        )
    }

    private func signedProvenance(
        for manifest: WriterIndependentEvaluationManifest
    ) -> SignedWriterIndependentProvenanceSnapshot {
        signedProvenance(payload: provenancePayload(for: manifest))
    }

    private func recomputingRoots(
        _ payload: WriterIndependentProvenanceSnapshotPayload
    ) -> WriterIndependentProvenanceSnapshotPayload {
        var value = payload
        value.consentLedgerMerkleRootSHA256 = try! value.computedConsentLedgerMerkleRootSHA256()
        value.cohortRegistryMerkleRootSHA256 = try! value.computedCohortRegistryMerkleRootSHA256()
        return value
    }

    private func signedProvenance(
        payload: WriterIndependentProvenanceSnapshotPayload
    ) -> SignedWriterIndependentProvenanceSnapshot {
        let signature = try! provenanceSigningKey.signature(for: payload.canonicalData())
        return SignedWriterIndependentProvenanceSnapshot(
            payload: payload,
            signingKeyID: "collection-service-key-v1",
            signatureBase64: signature.base64EncodedString()
        )
    }

    private func provenancePayload(
        for manifest: WriterIndependentEvaluationManifest
    ) -> WriterIndependentProvenanceSnapshotPayload {
        let consentsByID = Dictionary(
            manifest.samples.map { sample in
                (
                    sample.consentRecordID,
                    WriterIndependentResearchConsentRecord(
                        consentRecordID: sample.consentRecordID,
                        writerIDHash: sample.writerIDHash,
                        personLinkageHMACSHA256: personLinkage(for: sample.writerIDHash),
                        isActive: true,
                        researchScopes: [.chordRecognitionEvaluation],
                        datasetVersions: [manifest.datasetVersion]
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        return WriterIndependentProvenanceSnapshotPayload(
            cohortRegistryVersion: manifest.cohortRegistryVersion,
            cohortRegistryMerkleRootSHA256: manifest.cohortRegistryMerkleRootSHA256,
            cohortRegistryEpoch: 7,
            consentLedgerSnapshotVersion: manifest.consentLedgerSnapshotVersion,
            consentLedgerMerkleRootSHA256: manifest.consentLedgerMerkleRootSHA256,
            consentLedgerEpoch: 8,
            issuedAtUnixSeconds: 1_700_000_000,
            expiresAtUnixSeconds: 1_900_000_000,
            consentRecords: consentsByID.values.sorted { $0.consentRecordID.uuidString < $1.consentRecordID.uuidString },
            cohortRecords: manifest.samples.map { sample in
                WriterIndependentCohortRegistryRecord(
                    sampleID: sample.sampleID,
                    datasetVersion: manifest.datasetVersion,
                    strokePayloadSHA256: sample.strokePayloadSHA256,
                    writerIDHash: sample.writerIDHash,
                    personLinkageHMACSHA256: personLinkage(for: sample.writerIDHash),
                    captureSessionID: sample.captureSessionID,
                    sourceKind: sample.sourceKind,
                    parentSampleID: sample.parentSampleID,
                    split: sample.split,
                    captureProtocolVersion: sample.captureProtocolVersion,
                    chartStyle: sample.chartStyle,
                    orientation: sample.orientation,
                    pace: sample.pace,
                    sizeBucket: sample.sizeBucket,
                    handedness: sample.handedness,
                    pencilExperience: sample.pencilExperience,
                    constructionVariation: sample.constructionVariation,
                    deviceClass: sample.deviceClass,
                    appBuild: sample.appBuild,
                    pipelineVersion: sample.pipelineVersion,
                    labelRecordID: sample.labelRecordID,
                    consentRecordID: sample.consentRecordID,
                    geometryLeakageClusterID: sample.geometryLeakageClusterID,
                    leakageCheckVersion: sample.leakageCheckVersion,
                    eligibility: .evaluationEligible
                )
            }
        )
    }

    private var trustedGroundTruthKeys: [String: Data] {
        ["ground-truth-service-key-v1": groundTruthSigningKey.publicKey.rawRepresentation]
    }

    private func groundTruthIssues(
        _ manifest: WriterIndependentEvaluationManifest,
        registry: SignedWriterIndependentGroundTruthRegistry
    ) -> [WriterIndependentGroundTruthValidationIssue] {
        WriterIndependentGroundTruthRegistryValidator.issues(
            in: registry,
            for: manifest,
            trustedSigningPublicKeysByID: trustedGroundTruthKeys,
            expected: WriterIndependentGroundTruthExpectation(
                registryVersion: registry.payload.registryVersion,
                merkleRootSHA256: registry.payload.merkleRootSHA256,
                minimumRegistryEpoch: registry.payload.registryEpoch,
                validationUnixSeconds: 1_800_000_000
            )
        )
    }

    private func signedGroundTruth(
        for manifest: WriterIndependentEvaluationManifest
    ) -> SignedWriterIndependentGroundTruthRegistry {
        signedGroundTruth(payload: groundTruthPayload(for: manifest))
    }

    private func signedGroundTruth(
        payload: WriterIndependentGroundTruthRegistryPayload
    ) -> SignedWriterIndependentGroundTruthRegistry {
        let signature = try! groundTruthSigningKey.signature(for: payload.canonicalData())
        return SignedWriterIndependentGroundTruthRegistry(
            payload: payload,
            signingKeyID: "ground-truth-service-key-v1",
            signatureBase64: signature.base64EncodedString()
        )
    }

    private func groundTruthPayload(
        for manifest: WriterIndependentEvaluationManifest
    ) -> WriterIndependentGroundTruthRegistryPayload {
        var payload = WriterIndependentGroundTruthRegistryPayload(
            registryVersion: "ground-truth-registry-v1",
            merkleRootSHA256: sha256(0),
            registryEpoch: 11,
            issuedAtUnixSeconds: 1_700_000_000,
            expiresAtUnixSeconds: 1_900_000_000,
            records: manifest.samples
                .filter { $0.sourceKind == .consentedHumanCapture }
                .map { sample in
                    let committedLabel = hash("label|\(sample.labelRecordID.uuidString)")
                    return WriterIndependentGroundTruthRecord(
                        sampleID: sample.sampleID,
                        labelRecordID: sample.labelRecordID,
                        datasetVersion: manifest.datasetVersion,
                        isEvaluationEligible: true,
                        promptedIntentCommitmentSHA256: hash("prompt|\(sample.labelRecordID.uuidString)"),
                        writerConfirmedIntentCommitmentSHA256: hash("writer|\(sample.labelRecordID.uuidString)"),
                        firstReaderHMACSHA256: sha256(60_001),
                        firstReaderLabelCommitmentSHA256: committedLabel,
                        secondReaderHMACSHA256: sha256(60_002),
                        secondReaderLabelCommitmentSHA256: committedLabel,
                        adjudicatorHMACSHA256: nil,
                        adjudicatedLabelCommitmentSHA256: nil,
                        finalLabelCommitmentSHA256: committedLabel,
                        legibility: .legibleValid,
                        isFrozen: true
                    )
                }
        )
        payload = recomputingGroundTruthRoot(payload)
        return payload
    }

    private func recomputingGroundTruthRoot(
        _ payload: WriterIndependentGroundTruthRegistryPayload
    ) -> WriterIndependentGroundTruthRegistryPayload {
        var value = payload
        value.merkleRootSHA256 = try! value.computedMerkleRootSHA256()
        return value
    }

    private func sample(
        seed: Int,
        writer: Int,
        session: Int,
        split: WriterIndependentEvaluationSplit
    ) -> WriterIndependentEvaluationSample {
        WriterIndependentEvaluationSample(
            sampleID: uuid(seed),
            writerIDHash: sha256(writer),
            captureSessionID: uuid(10_000 + session),
            sourceKind: .consentedHumanCapture,
            parentSampleID: nil,
            split: split,
            captureProtocolVersion: WriterIndependentEvaluationProtocolContract.currentVersion,
            chartStyle: seed.isMultiple(of: 2) ? .rhythmSectionSheet : .simpleChordSheet,
            orientation: seed.isMultiple(of: 2) ? .landscape : .portrait,
            pace: .natural,
            sizeBucket: .normal,
            handedness: writer.isMultiple(of: 2) ? .left : .right,
            pencilExperience: writer.isMultiple(of: 2) ? .novice : .experienced,
            constructionVariation: seed.isMultiple(of: 2) ? .modifierFirst : .rootFirst,
            deviceClass: "oldest-supported",
            appBuild: "1.2.1-51",
            pipelineVersion: "legacy-v19-shadow",
            strokePayloadSHA256: sha256(100_000 + seed),
            geometryLeakageClusterID: uuid(30_000 + seed),
            leakageCheckVersion: "geometry-and-legacy-denylist-v1",
            labelRecordID: uuid(20_000 + seed),
            consentRecordID: uuid(40_000 + writer)
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func sha256(_ value: Int) -> String {
        String(format: "%064x", value)
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func personLinkage(for writerIDHash: String) -> String {
        SHA256.hash(data: Data("person-linkage|\(writerIDHash)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

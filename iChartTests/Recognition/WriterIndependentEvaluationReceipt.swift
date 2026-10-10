import CryptoKit
import Foundation

/// Aggregate-only output from the isolated evaluator.
///
/// The payload is useful only after an Ed25519 signature is verified against a
/// trusted key supplied outside the receipt and every expected artifact identity
/// is matched. Raw ink, labels, sample IDs, and writer IDs never belong here.
struct WriterIndependentEvaluationReceiptPayload: Codable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var evaluationProtocolVersion: String
    var evaluationSplit: WriterIndependentEvaluationSplit
    /// A one-use authorization issued outside the evaluator. Signature and
    /// identity checks bind it here; an external ledger must atomically consume
    /// it because this aggregate-only receipt cannot enforce one-time use.
    var evaluationAuthorizationID: String
    var evaluationAttemptOrdinal: Int
    var datasetVersion: String
    var datasetMerkleRootSHA256: String
    var evaluationManifestSHA256: String
    var provenanceSnapshotSHA256: String
    var groundTruthRegistryVersion: String
    var groundTruthRegistryEpoch: UInt64
    var groundTruthSnapshotSHA256: String
    var groundTruthMerkleRootSHA256: String
    var recognizerArtifactSHA256: String
    var evaluatorArtifactSHA256: String
    var latencyDeviceClass: String
    var pipelineVersion: String
    var calibrationVersion: String
    var metricDefinitionVersion: String
    var gateDefinitionID: String
    var gateDefinitionSHA256: String
    var writerCommitmentSchemeVersion: String
    var writerCommitmentMerkleRootSHA256: String
    var aggregate: WriterIndependentEvaluationAggregate

    init(
        schemaVersion: Int = currentSchemaVersion,
        evaluationProtocolVersion: String,
        evaluationSplit: WriterIndependentEvaluationSplit,
        evaluationAuthorizationID: String,
        evaluationAttemptOrdinal: Int,
        datasetVersion: String,
        datasetMerkleRootSHA256: String,
        evaluationManifestSHA256: String,
        provenanceSnapshotSHA256: String,
        groundTruthRegistryVersion: String,
        groundTruthRegistryEpoch: UInt64,
        groundTruthSnapshotSHA256: String,
        groundTruthMerkleRootSHA256: String,
        recognizerArtifactSHA256: String,
        evaluatorArtifactSHA256: String,
        latencyDeviceClass: String,
        pipelineVersion: String,
        calibrationVersion: String,
        metricDefinitionVersion: String,
        gateDefinitionID: String,
        gateDefinitionSHA256: String,
        writerCommitmentSchemeVersion: String,
        writerCommitmentMerkleRootSHA256: String,
        aggregate: WriterIndependentEvaluationAggregate
    ) {
        self.schemaVersion = schemaVersion
        self.evaluationProtocolVersion = evaluationProtocolVersion
        self.evaluationSplit = evaluationSplit
        self.evaluationAuthorizationID = evaluationAuthorizationID
        self.evaluationAttemptOrdinal = evaluationAttemptOrdinal
        self.datasetVersion = datasetVersion
        self.datasetMerkleRootSHA256 = datasetMerkleRootSHA256
        self.evaluationManifestSHA256 = evaluationManifestSHA256
        self.provenanceSnapshotSHA256 = provenanceSnapshotSHA256
        self.groundTruthRegistryVersion = groundTruthRegistryVersion
        self.groundTruthRegistryEpoch = groundTruthRegistryEpoch
        self.groundTruthSnapshotSHA256 = groundTruthSnapshotSHA256
        self.groundTruthMerkleRootSHA256 = groundTruthMerkleRootSHA256
        self.recognizerArtifactSHA256 = recognizerArtifactSHA256
        self.evaluatorArtifactSHA256 = evaluatorArtifactSHA256
        self.latencyDeviceClass = latencyDeviceClass
        self.pipelineVersion = pipelineVersion
        self.calibrationVersion = calibrationVersion
        self.metricDefinitionVersion = metricDefinitionVersion
        self.gateDefinitionID = gateDefinitionID
        self.gateDefinitionSHA256 = gateDefinitionSHA256
        self.writerCommitmentSchemeVersion = writerCommitmentSchemeVersion
        self.writerCommitmentMerkleRootSHA256 = writerCommitmentMerkleRootSHA256
        self.aggregate = aggregate
    }

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func datasetCommitmentSHA256(
        evaluationManifestSHA256: String,
        provenanceSnapshotSHA256: String,
        groundTruthSnapshotSHA256: String,
        groundTruthMerkleRootSHA256: String
    ) -> String {
        let components = [
            "manifest:\(evaluationManifestSHA256.lowercased())",
            "provenance:\(provenanceSnapshotSHA256.lowercased())",
            "ground-truth-snapshot:\(groundTruthSnapshotSHA256.lowercased())",
            "ground-truth:\(groundTruthMerkleRootSHA256.lowercased())"
        ]
        return WriterIndependentMerkleCommitment.root(strings: components)
    }
}

struct SignedWriterIndependentEvaluationReceipt: Codable, Hashable {
    var payload: WriterIndependentEvaluationReceiptPayload
    var signingKeyID: String
    var signatureBase64: String
}

/// Sufficient statistics for one sealed writer, intentionally without a writer
/// identifier. The gate recomputes trust bounds from these rows instead of
/// accepting an evaluator-authored confidence number.
struct WriterIndependentWriterOutcomeSummary: Codable, Hashable {
    /// Receipt-scoped keyed commitment; never a stable writer identifier.
    var writerCommitmentSHA256: String
    var legibleValidCount: Int
    var exactCorrectCount: Int
    var topThreeCorrectCount: Int
    var trustedLegibleCount: Int
    var trustedWrongLegibleCount: Int
}

enum WriterIndependentEvaluationPopulation: String, Codable, Hashable, CaseIterable {
    case naturalFrequency
    case familyBalanced
}

enum WriterIndependentEvaluationStratumDimension: String, Codable, Hashable {
    case overall
    case chordFamily
    case component
    case chartStyle
    case deviceClass
    case orientation
    case pace
    case sizeBucket
    case handedness
    case pencilExperience
    case constructionVariation
}

struct WriterIndependentEvaluationStratumKey: Codable, Hashable {
    var population: WriterIndependentEvaluationPopulation
    var dimension: WriterIndependentEvaluationStratumDimension
    var value: String
}

struct WriterIndependentEvaluationStratumAggregate: Codable, Hashable {
    var key: WriterIndependentEvaluationStratumKey
    /// Receipt-scoped HMAC commitments for every distinct writer represented in
    /// this slice. These are not stable writer identifiers.
    var writerCommitmentsSHA256: [String]
    var humanSampleCount: Int
    var legibleValidCount: Int
    var exactCorrectCount: Int
    var trustedLegibleCount: Int
    var trustedWrongLegibleCount: Int

    var independentWriterCount: Int { Set(writerCommitmentsSHA256).count }
    var writerMembershipMerkleRootSHA256: String {
        WriterIndependentMerkleCommitment.root(strings: writerCommitmentsSHA256)
    }

    var exactAccuracy: Double { ratio(exactCorrectCount, legibleValidCount) }
    var trustedCoverage: Double { ratio(trustedLegibleCount, legibleValidCount) }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

struct WriterIndependentEvaluationAggregate: Codable, Hashable {
    /// Counts only original consented human captures in the sealed split.
    var independentWriterCount: Int
    var independentHumanCaptureCount: Int
    /// Reported for stress-test visibility, never used as an accuracy denominator.
    var syntheticDerivativeStressCount: Int
    var legibleValidCount: Int
    var humanAmbiguousOrNegativeCount: Int
    var executionErrorCount: Int
    var technicalInvalidCount: Int
    var exactCorrectCount: Int
    var topThreeCorrectCount: Int
    var trustedLegibleCount: Int
    var trustedWrongLegibleCount: Int
    var confirmationCount: Int
    var candidateReviewCount: Int
    var noReadCount: Int
    var falseTrustedAmbiguousOrNegativeCount: Int

    var ownershipTruePositiveCount: Int
    var ownershipFalsePositiveCount: Int
    var ownershipFalseNegativeCount: Int
    var frozenTargetMutationCount: Int

    /// The gate validates these rows against the aggregate and recomputes its
    /// preregistered writer-balanced uncertainty bounds itself.
    var writerOutcomeSummaries: [WriterIndependentWriterOutcomeSummary]
    /// Every population/slice required by the preregistered gate must appear.
    /// Missing difficult families or capture conditions therefore fail closed.
    var strata: [WriterIndependentEvaluationStratumAggregate]
    var expectedCalibrationError: Double
    var brierScore: Double
    var recognitionComputeP95Milliseconds: Double
    var stablePreviewP95Milliseconds: Double

    var exactAccuracy: Double {
        ratio(exactCorrectCount, legibleValidCount)
    }

    var topThreeAccuracy: Double {
        ratio(topThreeCorrectCount, legibleValidCount)
    }

    var trustedRisk: Double {
        ratio(trustedWrongLegibleCount, trustedLegibleCount)
    }

    var trustedCoverage: Double {
        ratio(trustedLegibleCount, legibleValidCount)
    }

    var technicalFailureRate: Double {
        ratio(executionErrorCount + technicalInvalidCount, independentHumanCaptureCount)
    }

    var ownershipF1: Double {
        let denominator = 2 * ownershipTruePositiveCount
            + ownershipFalsePositiveCount
            + ownershipFalseNegativeCount
        return ratio(2 * ownershipTruePositiveCount, denominator)
    }

    var writerMacroExactAccuracy: Double {
        guard !writerOutcomeSummaries.isEmpty else { return 0 }
        return writerOutcomeSummaries
            .map { ratio($0.exactCorrectCount, $0.legibleValidCount) }
            .reduce(0, +) / Double(writerOutcomeSummaries.count)
    }

    var minimumWriterTrustedCoverage: Double {
        writerOutcomeSummaries
            .map { ratio($0.trustedLegibleCount, $0.legibleValidCount) }
            .min() ?? 0
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

struct WriterIndependentEvaluationReceiptIssue: Hashable {
    enum Code: String, Hashable {
        case unsupportedSchemaVersion
        case unsupportedEvaluationProtocol
        case missingIdentity
        case invalidHash
        case datasetCommitmentMismatch
        case invalidCount
        case populationCountMismatch
        case legibleDispositionMismatch
        case impossibleOutcomeCount
        case writerSummaryMismatch
        case writerCommitmentMismatch
        case invalidStratum
        case duplicateStratum
        case stratumPartitionMismatch
        case stratumWriterCoverageMismatch
        case invalidMetric
        case missingSignature
        case unknownSigningKey
        case invalidSignature
    }

    var code: Code
    var detail: String
}

enum WriterIndependentEvaluationReceiptValidator {
    static func signatureIsValid(
        _ receipt: SignedWriterIndependentEvaluationReceipt,
        trustedSigningPublicKeysByID: [String: Data]
    ) -> Bool {
        signatureIssue(
            in: receipt,
            trustedSigningPublicKeysByID: trustedSigningPublicKeysByID
        ) == nil
    }

    static func issues(
        in receipt: SignedWriterIndependentEvaluationReceipt,
        trustedSigningPublicKeysByID: [String: Data]
    ) -> [WriterIndependentEvaluationReceiptIssue] {
        let payload = receipt.payload
        let aggregate = payload.aggregate
        var issues: [WriterIndependentEvaluationReceiptIssue] = []

        if payload.schemaVersion != WriterIndependentEvaluationReceiptPayload.currentSchemaVersion {
            issues.append(issue(.unsupportedSchemaVersion, "Unsupported receipt schema version."))
        }
        if payload.evaluationProtocolVersion != WriterIndependentEvaluationProtocolContract.currentVersion {
            issues.append(issue(
                .unsupportedEvaluationProtocol,
                "The receipt must use the current preregistered writer-independent evaluation protocol."
            ))
        }
        let requiredIdentity = [
            payload.evaluationProtocolVersion,
            payload.evaluationAuthorizationID,
            payload.datasetVersion,
            payload.groundTruthRegistryVersion,
            payload.latencyDeviceClass,
            payload.pipelineVersion,
            payload.calibrationVersion,
            payload.metricDefinitionVersion,
            payload.gateDefinitionID,
            payload.writerCommitmentSchemeVersion
        ]
        if requiredIdentity.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(issue(.missingIdentity, "Evaluation, dataset, pipeline, calibration, metric, and gate identities are required."))
        }
        let hashes = [
            payload.datasetMerkleRootSHA256,
            payload.evaluationManifestSHA256,
            payload.provenanceSnapshotSHA256,
            payload.groundTruthSnapshotSHA256,
            payload.groundTruthMerkleRootSHA256,
            payload.recognizerArtifactSHA256,
            payload.evaluatorArtifactSHA256,
            payload.gateDefinitionSHA256,
            payload.writerCommitmentMerkleRootSHA256
        ]
        if hashes.contains(where: { !isSHA256($0) }) {
            issues.append(issue(.invalidHash, "Dataset, recognizer, evaluator, and gate hashes must be SHA-256 values."))
        }
        let computedDatasetCommitment = WriterIndependentEvaluationReceiptPayload.datasetCommitmentSHA256(
            evaluationManifestSHA256: payload.evaluationManifestSHA256,
            provenanceSnapshotSHA256: payload.provenanceSnapshotSHA256,
            groundTruthSnapshotSHA256: payload.groundTruthSnapshotSHA256,
            groundTruthMerkleRootSHA256: payload.groundTruthMerkleRootSHA256
        )
        if payload.datasetMerkleRootSHA256.lowercased() != computedDatasetCommitment {
            issues.append(issue(
                .datasetCommitmentMismatch,
                "The dataset commitment must be recomputed from the bound manifest, provenance snapshot, and protected ground-truth root."
            ))
        }

        if let signatureIssue = signatureIssue(
            in: receipt,
            trustedSigningPublicKeysByID: trustedSigningPublicKeysByID
        ) {
            issues.append(signatureIssue)
        }

        let counts = [
            aggregate.independentWriterCount,
            aggregate.independentHumanCaptureCount,
            aggregate.syntheticDerivativeStressCount,
            aggregate.legibleValidCount,
            aggregate.humanAmbiguousOrNegativeCount,
            aggregate.executionErrorCount,
            aggregate.technicalInvalidCount,
            aggregate.exactCorrectCount,
            aggregate.topThreeCorrectCount,
            aggregate.trustedLegibleCount,
            aggregate.trustedWrongLegibleCount,
            aggregate.confirmationCount,
            aggregate.candidateReviewCount,
            aggregate.noReadCount,
            aggregate.falseTrustedAmbiguousOrNegativeCount,
            aggregate.ownershipTruePositiveCount,
            aggregate.ownershipFalsePositiveCount,
            aggregate.ownershipFalseNegativeCount,
            aggregate.frozenTargetMutationCount
        ]
        if counts.contains(where: { $0 < 0 }) {
            issues.append(issue(.invalidCount, "Aggregate counts cannot be negative."))
        }
        if payload.evaluationAttemptOrdinal != 1 {
            issues.append(issue(
                .invalidCount,
                "A sealed evaluation receipt must be the first and only attempt for its externally consumed authorization."
            ))
        }

        let writerCounts = aggregate.writerOutcomeSummaries.flatMap {
            [
                $0.legibleValidCount,
                $0.exactCorrectCount,
                $0.topThreeCorrectCount,
                $0.trustedLegibleCount,
                $0.trustedWrongLegibleCount
            ]
        }
        if writerCounts.contains(where: { $0 < 0 }) {
            issues.append(issue(.invalidCount, "Per-writer sufficient statistics cannot be negative."))
        }
        let writerCommitments = aggregate.writerOutcomeSummaries.map(\.writerCommitmentSHA256)
        let computedWriterRoot = WriterIndependentMerkleCommitment.root(strings: writerCommitments)
        if writerCommitments.contains(where: { !isCanonicalSHA256($0) })
            || Set(writerCommitments).count != writerCommitments.count
            || computedWriterRoot != payload.writerCommitmentMerkleRootSHA256.lowercased() {
            issues.append(issue(
                .writerCommitmentMismatch,
                "Each per-writer row requires one unique receipt-scoped commitment matching the signed commitment root."
            ))
        }
        let stratumCounts = aggregate.strata.flatMap {
            [
                $0.humanSampleCount,
                $0.legibleValidCount,
                $0.exactCorrectCount,
                $0.trustedLegibleCount,
                $0.trustedWrongLegibleCount
            ]
        }
        if stratumCounts.contains(where: { $0 < 0 }) {
            issues.append(issue(.invalidCount, "Stratum counts cannot be negative."))
        }

        let classifiedPopulation = aggregate.legibleValidCount
            + aggregate.humanAmbiguousOrNegativeCount
            + aggregate.executionErrorCount
            + aggregate.technicalInvalidCount
        if classifiedPopulation != aggregate.independentHumanCaptureCount {
            issues.append(issue(
                .populationCountMismatch,
                "Human population categories must sum to independentHumanCaptureCount; derivatives remain separate."
            ))
        }

        let legibleDispositions = aggregate.trustedLegibleCount
            + aggregate.confirmationCount
            + aggregate.candidateReviewCount
            + aggregate.noReadCount
        if legibleDispositions != aggregate.legibleValidCount {
            issues.append(issue(.legibleDispositionMismatch, "Legible dispositions must partition legibleValidCount."))
        }

        let trustedCorrectCount = aggregate.trustedLegibleCount - aggregate.trustedWrongLegibleCount
        if aggregate.exactCorrectCount > aggregate.legibleValidCount
            || aggregate.topThreeCorrectCount > aggregate.legibleValidCount
            || aggregate.topThreeCorrectCount < aggregate.exactCorrectCount
            || aggregate.trustedWrongLegibleCount > aggregate.trustedLegibleCount
            || trustedCorrectCount > aggregate.exactCorrectCount
            || aggregate.falseTrustedAmbiguousOrNegativeCount > aggregate.humanAmbiguousOrNegativeCount
            || aggregate.independentWriterCount > aggregate.independentHumanCaptureCount {
            issues.append(issue(.impossibleOutcomeCount, "Outcome counts exceed or contradict their denominators."))
        }


        let summariesArePossible = aggregate.writerOutcomeSummaries.allSatisfy { summary in
            summary.exactCorrectCount <= summary.legibleValidCount
                && summary.topThreeCorrectCount <= summary.legibleValidCount
                && summary.topThreeCorrectCount >= summary.exactCorrectCount
                && summary.trustedLegibleCount <= summary.legibleValidCount
                && summary.trustedWrongLegibleCount <= summary.trustedLegibleCount
                && summary.trustedLegibleCount - summary.trustedWrongLegibleCount <= summary.exactCorrectCount
        }
        let summaryTotals = aggregate.writerOutcomeSummaries.reduce(
            into: WriterIndependentWriterOutcomeSummary(
                writerCommitmentSHA256: "",
                legibleValidCount: 0,
                exactCorrectCount: 0,
                topThreeCorrectCount: 0,
                trustedLegibleCount: 0,
                trustedWrongLegibleCount: 0
            )
        ) { totals, summary in
            totals.legibleValidCount += summary.legibleValidCount
            totals.exactCorrectCount += summary.exactCorrectCount
            totals.topThreeCorrectCount += summary.topThreeCorrectCount
            totals.trustedLegibleCount += summary.trustedLegibleCount
            totals.trustedWrongLegibleCount += summary.trustedWrongLegibleCount
        }
        if aggregate.writerOutcomeSummaries.count != aggregate.independentWriterCount
            || !summariesArePossible
            || summaryTotals.legibleValidCount != aggregate.legibleValidCount
            || summaryTotals.exactCorrectCount != aggregate.exactCorrectCount
            || summaryTotals.topThreeCorrectCount != aggregate.topThreeCorrectCount
            || summaryTotals.trustedLegibleCount != aggregate.trustedLegibleCount
            || summaryTotals.trustedWrongLegibleCount != aggregate.trustedWrongLegibleCount {
            issues.append(issue(
                .writerSummaryMismatch,
                "Anonymous per-writer sufficient statistics must be possible, have one row per sealed writer, and exactly reconcile to aggregate legible outcomes."
            ))
        }

        if Set(aggregate.strata.map(\.key)).count != aggregate.strata.count {
            issues.append(issue(.duplicateStratum, "Each population and stratum key may appear only once."))
        }
        if aggregate.strata.contains(where: { stratum in
            stratum.key.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || stratum.writerCommitmentsSHA256.contains(where: { !isCanonicalSHA256($0) })
                || Set(stratum.writerCommitmentsSHA256).count != stratum.writerCommitmentsSHA256.count
                || (stratum.humanSampleCount > 0 && stratum.writerCommitmentsSHA256.isEmpty)
                || stratum.legibleValidCount > stratum.humanSampleCount
                || stratum.exactCorrectCount > stratum.legibleValidCount
                || stratum.trustedLegibleCount > stratum.legibleValidCount
                || stratum.trustedWrongLegibleCount > stratum.trustedLegibleCount
                || stratum.trustedLegibleCount - stratum.trustedWrongLegibleCount > stratum.exactCorrectCount
        }) {
            issues.append(issue(.invalidStratum, "Strata require a nonempty identity and internally possible outcome counts."))
        }

        let overallGroups = Dictionary(
            grouping: aggregate.strata.filter { $0.key.dimension == .overall },
            by: \.key.population
        )
        let overallByPopulation = overallGroups.compactMapValues { strata in
            strata.count == 1 ? strata[0] : nil
        }
        let overallTotals = overallByPopulation.values.reduce(
            into: (human: 0, legible: 0, exact: 0, trusted: 0, trustedWrong: 0)
        ) { totals, stratum in
            totals.human += stratum.humanSampleCount
            totals.legible += stratum.legibleValidCount
            totals.exact += stratum.exactCorrectCount
            totals.trusted += stratum.trustedLegibleCount
            totals.trustedWrong += stratum.trustedWrongLegibleCount
        }
        var partitionsMatch = overallByPopulation.count == WriterIndependentEvaluationPopulation.allCases.count
            && overallTotals.human == aggregate.independentHumanCaptureCount
            && overallTotals.legible == aggregate.legibleValidCount
            && overallTotals.exact == aggregate.exactCorrectCount
            && overallTotals.trusted == aggregate.trustedLegibleCount
            && overallTotals.trustedWrong == aggregate.trustedWrongLegibleCount
        let partitionedDimensions: Set<WriterIndependentEvaluationStratumDimension> = [
            .chordFamily, .chartStyle, .deviceClass, .orientation, .pace, .sizeBucket,
            .handedness, .pencilExperience, .constructionVariation
        ]
        let partitionGroups = Dictionary(
            grouping: aggregate.strata.filter { partitionedDimensions.contains($0.key.dimension) },
            by: { "\($0.key.population.rawValue)|\($0.key.dimension.rawValue)" }
        )
        for strata in partitionGroups.values {
            guard let population = strata.first?.key.population,
                  let overall = overallByPopulation[population] else {
                partitionsMatch = false
                continue
            }
            let totals = strata.reduce(
                into: (human: 0, legible: 0, exact: 0, trusted: 0, trustedWrong: 0)
            ) { value, stratum in
                value.human += stratum.humanSampleCount
                value.legible += stratum.legibleValidCount
                value.exact += stratum.exactCorrectCount
                value.trusted += stratum.trustedLegibleCount
                value.trustedWrong += stratum.trustedWrongLegibleCount
            }
            if totals.human != overall.humanSampleCount
                || totals.legible != overall.legibleValidCount
                || totals.exact != overall.exactCorrectCount
                || totals.trusted != overall.trustedLegibleCount
                || totals.trustedWrong != overall.trustedWrongLegibleCount {
                partitionsMatch = false
            }
        }
        let componentStrataAreBounded = aggregate.strata
            .filter { $0.key.dimension == .component }
            .allSatisfy { stratum in
                guard let overall = overallByPopulation[stratum.key.population] else { return false }
                return stratum.humanSampleCount <= overall.humanSampleCount
                    && stratum.legibleValidCount <= overall.legibleValidCount
                    && stratum.trustedLegibleCount <= overall.trustedLegibleCount
                    && stratum.trustedWrongLegibleCount <= overall.trustedWrongLegibleCount
            }
        partitionsMatch = partitionsMatch && componentStrataAreBounded
        if !partitionsMatch {
            issues.append(issue(
                .stratumPartitionMismatch,
                "Population overalls must reconcile to the sealed aggregate and every mutually exclusive slice dimension must partition its population overall."
            ))
        }

        let receiptWriterCommitments = Set(writerCommitments)
        let overallWriterUnion = Set(
            overallByPopulation.values.flatMap(\.writerCommitmentsSHA256)
        )
        var writerCoverageMatches = overallWriterUnion == receiptWriterCommitments
        for stratum in aggregate.strata {
            if !Set(stratum.writerCommitmentsSHA256).isSubset(of: receiptWriterCommitments) {
                writerCoverageMatches = false
            }
        }
        for strata in partitionGroups.values {
            guard let population = strata.first?.key.population,
                  let overall = overallByPopulation[population] else {
                writerCoverageMatches = false
                continue
            }
            let union = Set(strata.flatMap(\.writerCommitmentsSHA256))
            if union != Set(overall.writerCommitmentsSHA256) {
                writerCoverageMatches = false
            }
        }
        if !writerCoverageMatches {
            issues.append(issue(
                .stratumWriterCoverageMismatch,
                "Stratum writer commitments must be unique, drawn from the sealed writer set, and cover each partitioned population."
            ))
        }

        let unitMetrics = [
            aggregate.writerMacroExactAccuracy,
            aggregate.minimumWriterTrustedCoverage,
            aggregate.expectedCalibrationError,
            aggregate.brierScore
        ]
        if unitMetrics.contains(where: { !$0.isFinite || !(0...1).contains($0) })
            || !aggregate.recognitionComputeP95Milliseconds.isFinite
            || !aggregate.stablePreviewP95Milliseconds.isFinite
            || aggregate.recognitionComputeP95Milliseconds < 0
            || aggregate.stablePreviewP95Milliseconds < 0 {
            issues.append(issue(
                .invalidMetric,
                "Rates and uncertainty bounds must be internally consistent and within zero and one; latencies must be finite and nonnegative."
            ))
        }

        return issues.sorted { $0.code.rawValue < $1.code.rawValue }
    }

    private static func signatureIssue(
        in receipt: SignedWriterIndependentEvaluationReceipt,
        trustedSigningPublicKeysByID: [String: Data]
    ) -> WriterIndependentEvaluationReceiptIssue? {
        let keyID = receipt.signingKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty,
              let signature = Data(base64Encoded: receipt.signatureBase64),
              !signature.isEmpty else {
            return issue(.missingSignature, "A key ID and nonempty base64 Ed25519 signature are required.")
        }
        guard let rawPublicKey = trustedSigningPublicKeysByID[keyID],
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey) else {
            return issue(.unknownSigningKey, "The receipt key ID is not present in the trusted evaluator keyring.")
        }
        guard let canonicalPayload = try? receipt.payload.canonicalData(),
              publicKey.isValidSignature(signature, for: canonicalPayload) else {
            return issue(.invalidSignature, "The receipt signature does not verify for its canonical payload.")
        }
        return nil
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...70, 97...102:
                return true
            default:
                return false
            }
        }
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102:
                return true
            default:
                return false
            }
        }
    }

    private static func issue(
        _ code: WriterIndependentEvaluationReceiptIssue.Code,
        _ detail: String
    ) -> WriterIndependentEvaluationReceiptIssue {
        WriterIndependentEvaluationReceiptIssue(code: code, detail: detail)
    }
}

struct WriterIndependentEvaluationStratumRequirement: Codable, Hashable {
    var key: WriterIndependentEvaluationStratumKey
    var minimumIndependentWriterCount: Int
    var minimumHumanSampleCount: Int
    var minimumLegibleSampleCount: Int
    var minimumExactAccuracy: Double
    var minimumTrustedCoverage: Double
    var maximumTrustedWrongLegibleCount: Int
}

struct WriterIndependentRecognitionGate: Codable, Hashable {
    var definitionID: String
    var evaluationProtocolVersion: String
    var uncertaintyMethodVersion: String
    /// Total one-sided error budget shared equally across the three mean-rate
    /// bounds and the future-writer pass-probability bound.
    var overallFamilyWiseAlpha: Double
    /// Preregistered user-level companion gate. A writer passes only when every
    /// predicate below passes; the population proportion is then bounded with
    /// the separately versioned exact one-sided binomial method using its share
    /// of the same overall error budget.
    var writerPassPredicateVersion: String
    var minimumWriterPassLegibleCount: Int
    var minimumWriterPassExactAccuracy: Double
    var minimumWriterPassTopThreeAccuracy: Double
    var minimumWriterPassTrustedCoverage: Double
    var maximumWriterPassTrustedWrongCount: Int
    var maximumWriterPassTrustedRisk: Double
    var writerPassProbabilityMethodVersion: String
    var minimumWriterPassProbabilityLowerBound: Double
    var minimumIndependentWriters: Int
    var minimumLegibleSamples: Int
    var minimumAmbiguousOrNegativeSamples: Int
    var minimumEvaluableHumanSamplesPerWriter: Int
    var minimumExactAccuracyLowerBound: Double
    var minimumTopThreeAccuracyLowerBound: Double
    var maximumTrustedRiskUpperBound: Double
    var minimumTrustedCoverage: Double
    var minimumWriterMacroExactAccuracy: Double
    var minimumWriterTrustedCoverage: Double
    var minimumOwnershipF1: Double
    var maximumExpectedCalibrationError: Double
    var maximumBrierScore: Double
    var maximumTechnicalFailureRate: Double
    var maximumTrustedWrongLegibleCount: Int
    var maximumFalseTrustedAmbiguousOrNegativeCount: Int
    var maximumFrozenTargetMutationCount: Int
    var maximumRecognitionComputeP95Milliseconds: Double
    var maximumStablePreviewP95Milliseconds: Double
    /// This signed, hash-bound list is the completeness contract. Omitted
    /// natural/balanced populations or difficult capture slices cannot pass.
    var requiredStrata: [WriterIndependentEvaluationStratumRequirement]

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func definitionSHA256() throws -> String {
        SHA256.hash(data: try canonicalData()).map { String(format: "%02x", $0) }.joined()
    }
}

struct WriterIndependentEvaluationExpectation: Hashable {
    var evaluationProtocolVersion: String
    var requiredSplit: WriterIndependentEvaluationSplit
    var evaluationAuthorizationID: String
    var evaluationAttemptOrdinal: Int
    var independentWriterCount: Int
    var independentHumanCaptureCount: Int
    var datasetVersion: String
    var datasetMerkleRootSHA256: String
    var evaluationManifestSHA256: String
    var provenanceSnapshotSHA256: String
    var groundTruthRegistryVersion: String
    var groundTruthRegistryEpoch: UInt64
    var groundTruthSnapshotSHA256: String
    var groundTruthMerkleRootSHA256: String
    var recognizerArtifactSHA256: String
    var evaluatorArtifactSHA256: String
    var latencyDeviceClass: String
    var pipelineVersion: String
    var calibrationVersion: String
    var metricDefinitionVersion: String
    var writerCommitmentSchemeVersion: String
    var writerCommitmentMerkleRootSHA256: String
    var expectedStrata: [WriterIndependentExpectedStratum]
    var gateDefinitionID: String
    var gateDefinitionSHA256: String
}

struct WriterIndependentExpectedStratum: Hashable {
    var key: WriterIndependentEvaluationStratumKey
    var independentWriterCount: Int
    var writerMembershipMerkleRootSHA256: String
    var humanSampleCount: Int
}

/// A short-lived, externally signed attestation of the provenance and label
/// snapshots that are current at receipt-consumption time. The evaluator cannot
/// mint this checkpoint and the receipt cannot extend its validity window.
struct WriterIndependentEvaluationFreshnessCheckpointPayload: Codable, Hashable {
    static let currentSchemaVersion = 1

    enum SnapshotState: String, Codable, Hashable {
        case current
        case revoked
    }

    var schemaVersion: Int
    var checkpointID: String
    var issuedAtUnixSeconds: Int64
    var expiresAtUnixSeconds: Int64
    var provenanceSnapshotSHA256: String
    var provenanceValidUntilUnixSeconds: Int64
    var provenanceState: SnapshotState
    var groundTruthRegistryVersion: String
    var groundTruthRegistryEpoch: UInt64
    var groundTruthSnapshotSHA256: String
    var groundTruthMerkleRootSHA256: String
    var groundTruthValidUntilUnixSeconds: Int64
    var groundTruthState: SnapshotState

    init(
        schemaVersion: Int = currentSchemaVersion,
        checkpointID: String,
        issuedAtUnixSeconds: Int64,
        expiresAtUnixSeconds: Int64,
        provenanceSnapshotSHA256: String,
        provenanceValidUntilUnixSeconds: Int64,
        provenanceState: SnapshotState,
        groundTruthRegistryVersion: String,
        groundTruthRegistryEpoch: UInt64,
        groundTruthSnapshotSHA256: String,
        groundTruthMerkleRootSHA256: String,
        groundTruthValidUntilUnixSeconds: Int64,
        groundTruthState: SnapshotState
    ) {
        self.schemaVersion = schemaVersion
        self.checkpointID = checkpointID
        self.issuedAtUnixSeconds = issuedAtUnixSeconds
        self.expiresAtUnixSeconds = expiresAtUnixSeconds
        self.provenanceSnapshotSHA256 = provenanceSnapshotSHA256
        self.provenanceValidUntilUnixSeconds = provenanceValidUntilUnixSeconds
        self.provenanceState = provenanceState
        self.groundTruthRegistryVersion = groundTruthRegistryVersion
        self.groundTruthRegistryEpoch = groundTruthRegistryEpoch
        self.groundTruthSnapshotSHA256 = groundTruthSnapshotSHA256
        self.groundTruthMerkleRootSHA256 = groundTruthMerkleRootSHA256
        self.groundTruthValidUntilUnixSeconds = groundTruthValidUntilUnixSeconds
        self.groundTruthState = groundTruthState
    }

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

struct SignedWriterIndependentEvaluationFreshnessCheckpoint: Codable, Hashable {
    var payload: WriterIndependentEvaluationFreshnessCheckpointPayload
    var signingKeyID: String
    var signatureBase64: String
}

/// One externally issued authorization for one frozen artifact/holdout/gate
/// inspection. The ledger spends alpha for failures as well as passes.
struct WriterIndependentEvaluationAuthorization: Hashable {
    var authorizationID: String
    var evaluationProtocolVersion: String
    /// Stable external identity for the physical holdout cohort. Unlike the
    /// dataset commitment, this must not rotate when provenance/label
    /// checkpoints are refreshed.
    var holdoutID: String
    var datasetMerkleRootSHA256: String
    var recognizerArtifactSHA256: String
    var evaluatorArtifactSHA256: String
    var gateDefinitionSHA256: String
    var familyWiseAlpha: Double
}

struct WriterIndependentEvaluationConsumptionFailure: Hashable {
    enum Code: String, Hashable {
        case invalidEvaluationEvidence
        case invalidFreshnessCheckpoint
        case staleOrRevokedProvenance
        case staleOrRevokedGroundTruth
        case invalidAuthorization
        case duplicateAuthorization
        case authorizationNotFound
        case authorizationIdentityMismatch
        case authorizationAlreadyConsumed
        case holdoutAlphaBudgetMissing
        case holdoutAlphaBudgetExceeded
    }

    var code: Code
    var detail: String
}

struct WriterIndependentEvaluationConsumptionResult: Hashable {
    var gateFailures: [WriterIndependentRecognitionGateFailure]
    var consumptionFailures: [WriterIndependentEvaluationConsumptionFailure]
    var authorizationConsumed: Bool

    var passed: Bool {
        authorizationConsumed && gateFailures.isEmpty && consumptionFailures.isEmpty
    }
}

/// Reference/test-support implementation of the external ledger contract. The
/// lock covers the budget check, alpha spend, and one-use transition together.
/// A production deployment still needs durable transactional storage.
final class WriterIndependentEvaluationAuthorizationLedger {
    private let lock = NSLock()
    private let maximumFamilyWiseAlphaByHoldoutID: [String: Double]
    private let invalidBudgetHoldoutIDs: Set<String>
    private var authorizationsByID: [String: WriterIndependentEvaluationAuthorization] = [:]
    private var consumedAuthorizationIDs: Set<String> = []
    private var spentFamilyWiseAlphaByHoldout: [String: Double] = [:]

    init(maximumFamilyWiseAlphaByHoldoutID: [String: Double]) {
        var normalized: [String: Double] = [:]
        var invalid: Set<String> = []
        for (holdoutID, budget) in maximumFamilyWiseAlphaByHoldoutID {
            let key = holdoutID.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized[key] != nil
                || key.isEmpty
                || !budget.isFinite
                || budget <= 0
                || budget >= 1 {
                invalid.insert(key)
            } else {
                normalized[key] = budget
            }
        }
        self.maximumFamilyWiseAlphaByHoldoutID = normalized
        self.invalidBudgetHoldoutIDs = invalid
    }

    @discardableResult
    func register(
        _ authorization: WriterIndependentEvaluationAuthorization
    ) -> WriterIndependentEvaluationConsumptionFailure? {
        lock.lock()
        defer { lock.unlock() }

        let holdoutID = authorization.holdoutID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorization.authorizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              authorization.evaluationProtocolVersion == WriterIndependentEvaluationProtocolContract.currentVersion,
              !holdoutID.isEmpty,
              authorization.holdoutID == holdoutID,
              Self.isCanonicalSHA256(authorization.datasetMerkleRootSHA256),
              Self.isCanonicalSHA256(authorization.recognizerArtifactSHA256),
              Self.isCanonicalSHA256(authorization.evaluatorArtifactSHA256),
              Self.isCanonicalSHA256(authorization.gateDefinitionSHA256),
              authorization.familyWiseAlpha.isFinite,
              authorization.familyWiseAlpha > 0,
              authorization.familyWiseAlpha < 1 else {
            return failure(.invalidAuthorization, "Authorization identity and alpha must be canonical.")
        }
        guard maximumFamilyWiseAlphaByHoldoutID[holdoutID] != nil,
              !invalidBudgetHoldoutIDs.contains(holdoutID) else {
            return failure(.holdoutAlphaBudgetMissing, "The holdout has no unique valid preregistered alpha budget.")
        }
        guard authorizationsByID[authorization.authorizationID] == nil else {
            return failure(.duplicateAuthorization, "An authorization ID can be registered only once.")
        }
        authorizationsByID[authorization.authorizationID] = authorization
        return nil
    }

    fileprivate func consume(
        payload: WriterIndependentEvaluationReceiptPayload,
        familyWiseAlpha: Double
    ) -> WriterIndependentEvaluationConsumptionFailure? {
        lock.lock()
        defer { lock.unlock() }

        guard let authorization = authorizationsByID[payload.evaluationAuthorizationID] else {
            return failure(.authorizationNotFound, "The receipt has no externally registered authorization.")
        }
        if consumedAuthorizationIDs.contains(authorization.authorizationID) {
            return failure(.authorizationAlreadyConsumed, "The one-use evaluation authorization was already consumed.")
        }
        let holdoutID = authorization.holdoutID
        guard authorization.evaluationProtocolVersion == payload.evaluationProtocolVersion,
              authorization.datasetMerkleRootSHA256.lowercased()
                == payload.datasetMerkleRootSHA256.lowercased(),
              authorization.recognizerArtifactSHA256.lowercased()
                == payload.recognizerArtifactSHA256.lowercased(),
              authorization.evaluatorArtifactSHA256.lowercased()
                == payload.evaluatorArtifactSHA256.lowercased(),
              authorization.gateDefinitionSHA256.lowercased()
                == payload.gateDefinitionSHA256.lowercased(),
              authorization.familyWiseAlpha == familyWiseAlpha else {
            return failure(.authorizationIdentityMismatch, "Authorization, holdout, artifacts, gate, and alpha must match the signed receipt.")
        }
        guard let maximumAlpha = maximumFamilyWiseAlphaByHoldoutID[holdoutID],
              !invalidBudgetHoldoutIDs.contains(holdoutID) else {
            return failure(.holdoutAlphaBudgetMissing, "The holdout has no unique valid preregistered alpha budget.")
        }
        let spentAlpha = spentFamilyWiseAlphaByHoldout[holdoutID, default: 0]
        guard spentAlpha + authorization.familyWiseAlpha <= maximumAlpha else {
            return failure(.holdoutAlphaBudgetExceeded, "Consuming this authorization would exceed the holdout's family-wise alpha budget.")
        }

        spentFamilyWiseAlphaByHoldout[holdoutID] = spentAlpha + authorization.familyWiseAlpha
        consumedAuthorizationIDs.insert(authorization.authorizationID)
        return nil
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102: true
            default: false
            }
        }
    }

    private func failure(
        _ code: WriterIndependentEvaluationConsumptionFailure.Code,
        _ detail: String
    ) -> WriterIndependentEvaluationConsumptionFailure {
        WriterIndependentEvaluationConsumptionFailure(code: code, detail: detail)
    }
}

struct WriterIndependentRecognitionGateFailure: Hashable {
    enum Code: String, Hashable {
        case invalidReceipt
        case invalidGate
        case wrongEvaluationSplit
        case receiptIdentityMismatch
        case gateDefinitionMismatch
        case sealedPopulationMismatch
        case stratumPopulationMismatch
        case insufficientWriters
        case insufficientLegibleSamples
        case insufficientAmbiguousOrNegativeSamples
        case insufficientPerWriterSamples
        case exactAccuracy
        case topThreeAccuracy
        case trustedRisk
        case trustedWrong
        case trustedCoverage
        case writerMacroAccuracy
        case minimumWriterCoverage
        case writerPassProbability
        case missingRequiredStratum
        case insufficientStratumSamples
        case insufficientStratumWriters
        case stratumAccuracy
        case stratumCoverage
        case stratumTrustedWrong
        case ownershipF1
        case calibrationError
        case brierScore
        case technicalFailureRate
        case ambiguousFalseTrust
        case frozenMutation
        case recognitionLatency
        case stablePreviewLatency
    }

    var code: Code
    var observed: Double?
    var required: Double?
}

enum WriterIndependentRecognitionGateEvaluator {
    static let oneSided95PercentZ = 1.6448536269514722
    static let supportedUncertaintyMethodVersion =
        "writer-cluster-four-claim-bonferroni-v2"
    static let supportedWriterPassPredicateVersion = "writer-pass-all-thresholds-v1"
    static let supportedWriterPassProbabilityMethodVersion =
        "clopper-pearson-one-sided-v1"

    static func evidenceIdentityIsValidForConsumption(
        _ payload: WriterIndependentEvaluationReceiptPayload,
        expected: WriterIndependentEvaluationExpectation,
        gate: WriterIndependentRecognitionGate
    ) -> Bool {
        guard gateIsValid(gate), let gateHash = try? gate.definitionSHA256() else { return false }
        return payload.evaluationSplit == expected.requiredSplit
            && matchesExpectedIdentity(payload, expected: expected)
            && payload.gateDefinitionID == gate.definitionID
            && payload.gateDefinitionID == expected.gateDefinitionID
            && payload.gateDefinitionSHA256.lowercased() == gateHash.lowercased()
            && payload.gateDefinitionSHA256.lowercased()
                == expected.gateDefinitionSHA256.lowercased()
    }

    static func failures(
        for receipt: SignedWriterIndependentEvaluationReceipt,
        expected: WriterIndependentEvaluationExpectation,
        trustedSigningPublicKeysByID: [String: Data],
        gate: WriterIndependentRecognitionGate
    ) -> [WriterIndependentRecognitionGateFailure] {
        guard WriterIndependentEvaluationReceiptValidator.issues(
            in: receipt,
            trustedSigningPublicKeysByID: trustedSigningPublicKeysByID
        ).isEmpty else {
            return [failure(.invalidReceipt)]
        }
        guard gateIsValid(gate), let gateHash = try? gate.definitionSHA256() else {
            return [failure(.invalidGate)]
        }

        let payload = receipt.payload
        var failures: [WriterIndependentRecognitionGateFailure] = []
        if payload.evaluationSplit != expected.requiredSplit {
            failures.append(failure(.wrongEvaluationSplit))
        }
        if !matchesExpectedIdentity(payload, expected: expected) {
            failures.append(failure(.receiptIdentityMismatch))
        }
        if payload.gateDefinitionID != gate.definitionID
            || payload.gateDefinitionID != expected.gateDefinitionID
            || payload.gateDefinitionSHA256.lowercased() != gateHash.lowercased()
            || payload.gateDefinitionSHA256.lowercased() != expected.gateDefinitionSHA256.lowercased() {
            failures.append(failure(.gateDefinitionMismatch))
        }
        guard failures.isEmpty else {
            return failures.sorted { $0.code.rawValue < $1.code.rawValue }
        }

        let value = payload.aggregate
        let bounds = writerClusterBonferroniEmpiricalBernsteinBounds(
            summaries: value.writerOutcomeSummaries,
            overallFamilyWiseAlpha: gate.overallFamilyWiseAlpha
        )
        if value.independentWriterCount != expected.independentWriterCount
            || value.independentHumanCaptureCount != expected.independentHumanCaptureCount {
            failures.append(failure(.sealedPopulationMismatch))
        }
        if value.independentWriterCount < gate.minimumIndependentWriters {
            failures.append(failure(
                .insufficientWriters,
                observed: Double(value.independentWriterCount),
                required: Double(gate.minimumIndependentWriters)
            ))
        }
        if value.legibleValidCount < gate.minimumLegibleSamples {
            failures.append(failure(
                .insufficientLegibleSamples,
                observed: Double(value.legibleValidCount),
                required: Double(gate.minimumLegibleSamples)
            ))
        }
        if value.humanAmbiguousOrNegativeCount < gate.minimumAmbiguousOrNegativeSamples {
            failures.append(failure(
                .insufficientAmbiguousOrNegativeSamples,
                observed: Double(value.humanAmbiguousOrNegativeCount),
                required: Double(gate.minimumAmbiguousOrNegativeSamples)
            ))
        }
        let minimumWriterSamples = value.writerOutcomeSummaries.map(\.legibleValidCount).min() ?? 0
        if minimumWriterSamples < gate.minimumEvaluableHumanSamplesPerWriter {
            failures.append(failure(
                .insufficientPerWriterSamples,
                observed: Double(minimumWriterSamples),
                required: Double(gate.minimumEvaluableHumanSamplesPerWriter)
            ))
        }
        if bounds.exactAccuracyLowerBound < gate.minimumExactAccuracyLowerBound {
            failures.append(failure(
                .exactAccuracy,
                observed: bounds.exactAccuracyLowerBound,
                required: gate.minimumExactAccuracyLowerBound
            ))
        }
        if bounds.topThreeAccuracyLowerBound < gate.minimumTopThreeAccuracyLowerBound {
            failures.append(failure(
                .topThreeAccuracy,
                observed: bounds.topThreeAccuracyLowerBound,
                required: gate.minimumTopThreeAccuracyLowerBound
            ))
        }
        if bounds.trustedRiskUpperBound > gate.maximumTrustedRiskUpperBound {
            failures.append(failure(
                .trustedRisk,
                observed: bounds.trustedRiskUpperBound,
                required: gate.maximumTrustedRiskUpperBound
            ))
        }
        if value.trustedWrongLegibleCount > gate.maximumTrustedWrongLegibleCount {
            failures.append(failure(
                .trustedWrong,
                observed: Double(value.trustedWrongLegibleCount),
                required: Double(gate.maximumTrustedWrongLegibleCount)
            ))
        }
        if value.trustedCoverage < gate.minimumTrustedCoverage {
            failures.append(failure(.trustedCoverage, observed: value.trustedCoverage, required: gate.minimumTrustedCoverage))
        }
        if value.writerMacroExactAccuracy < gate.minimumWriterMacroExactAccuracy {
            failures.append(failure(
                .writerMacroAccuracy,
                observed: value.writerMacroExactAccuracy,
                required: gate.minimumWriterMacroExactAccuracy
            ))
        }
        if value.minimumWriterTrustedCoverage < gate.minimumWriterTrustedCoverage {
            failures.append(failure(
                .minimumWriterCoverage,
                observed: value.minimumWriterTrustedCoverage,
                required: gate.minimumWriterTrustedCoverage
            ))
        }
        let passingWriterCount = value.writerOutcomeSummaries.filter {
            writerPasses($0, gate: gate)
        }.count
        let writerPassProbabilityLowerBound = oneSidedClopperPearsonLowerBound(
            successes: passingWriterCount,
            trials: value.writerOutcomeSummaries.count,
            alpha: gate.overallFamilyWiseAlpha / 4
        )
        if writerPassProbabilityLowerBound < gate.minimumWriterPassProbabilityLowerBound {
            failures.append(failure(
                .writerPassProbability,
                observed: writerPassProbabilityLowerBound,
                required: gate.minimumWriterPassProbabilityLowerBound
            ))
        }
        let expectedGroups = Dictionary(grouping: expected.expectedStrata, by: \.key)
        let receiptGroups = Dictionary(grouping: value.strata, by: \.key)
        let gateKeys = gate.requiredStrata.map(\.key)
        let expectedKeys = expected.expectedStrata.map(\.key)
        let expectationIsPossible = expected.expectedStrata.allSatisfy {
            $0.humanSampleCount >= 0
                && $0.independentWriterCount >= 0
                && isCanonicalSHA256ForGate($0.writerMembershipMerkleRootSHA256)
        }
            && Set(expectedKeys).count == expectedKeys.count
            && Set(gateKeys) == Set(expectedKeys)
            && Set(receiptGroups.keys) == Set(expectedKeys)
            && expectedGroups.allSatisfy { key, rows in
                rows.count == 1
                    && receiptGroups[key]?.count == 1
                    && receiptGroups[key]?[0].humanSampleCount == rows[0].humanSampleCount
                    && receiptGroups[key]?[0].independentWriterCount == rows[0].independentWriterCount
                    && receiptGroups[key]?[0].writerMembershipMerkleRootSHA256.lowercased()
                        == rows[0].writerMembershipMerkleRootSHA256.lowercased()
            }
        if !expectationIsPossible {
            failures.append(failure(.stratumPopulationMismatch))
        }
        let strataByKey = receiptGroups.compactMapValues { $0.count == 1 ? $0[0] : nil }
        for requirement in gate.requiredStrata {
            guard let stratum = strataByKey[requirement.key] else {
                failures.append(failure(.missingRequiredStratum))
                continue
            }
            if stratum.humanSampleCount < requirement.minimumHumanSampleCount
                || stratum.legibleValidCount < requirement.minimumLegibleSampleCount {
                failures.append(failure(
                    .insufficientStratumSamples,
                    observed: Double(min(stratum.humanSampleCount, stratum.legibleValidCount)),
                    required: Double(min(requirement.minimumHumanSampleCount, requirement.minimumLegibleSampleCount))
                ))
            }
            if stratum.independentWriterCount < requirement.minimumIndependentWriterCount {
                failures.append(failure(
                    .insufficientStratumWriters,
                    observed: Double(stratum.independentWriterCount),
                    required: Double(requirement.minimumIndependentWriterCount)
                ))
            }
            if stratum.exactAccuracy < requirement.minimumExactAccuracy {
                failures.append(failure(
                    .stratumAccuracy,
                    observed: stratum.exactAccuracy,
                    required: requirement.minimumExactAccuracy
                ))
            }
            if stratum.trustedCoverage < requirement.minimumTrustedCoverage {
                failures.append(failure(
                    .stratumCoverage,
                    observed: stratum.trustedCoverage,
                    required: requirement.minimumTrustedCoverage
                ))
            }
            if stratum.trustedWrongLegibleCount > requirement.maximumTrustedWrongLegibleCount {
                failures.append(failure(
                    .stratumTrustedWrong,
                    observed: Double(stratum.trustedWrongLegibleCount),
                    required: Double(requirement.maximumTrustedWrongLegibleCount)
                ))
            }
        }
        if value.ownershipF1 < gate.minimumOwnershipF1 {
            failures.append(failure(.ownershipF1, observed: value.ownershipF1, required: gate.minimumOwnershipF1))
        }
        if value.expectedCalibrationError > gate.maximumExpectedCalibrationError {
            failures.append(failure(
                .calibrationError,
                observed: value.expectedCalibrationError,
                required: gate.maximumExpectedCalibrationError
            ))
        }
        if value.brierScore > gate.maximumBrierScore {
            failures.append(failure(.brierScore, observed: value.brierScore, required: gate.maximumBrierScore))
        }
        if value.technicalFailureRate > gate.maximumTechnicalFailureRate {
            failures.append(failure(
                .technicalFailureRate,
                observed: value.technicalFailureRate,
                required: gate.maximumTechnicalFailureRate
            ))
        }
        if value.falseTrustedAmbiguousOrNegativeCount > gate.maximumFalseTrustedAmbiguousOrNegativeCount {
            failures.append(failure(
                .ambiguousFalseTrust,
                observed: Double(value.falseTrustedAmbiguousOrNegativeCount),
                required: Double(gate.maximumFalseTrustedAmbiguousOrNegativeCount)
            ))
        }
        if value.frozenTargetMutationCount > gate.maximumFrozenTargetMutationCount {
            failures.append(failure(
                .frozenMutation,
                observed: Double(value.frozenTargetMutationCount),
                required: Double(gate.maximumFrozenTargetMutationCount)
            ))
        }
        if value.recognitionComputeP95Milliseconds > gate.maximumRecognitionComputeP95Milliseconds {
            failures.append(failure(
                .recognitionLatency,
                observed: value.recognitionComputeP95Milliseconds,
                required: gate.maximumRecognitionComputeP95Milliseconds
            ))
        }
        if value.stablePreviewP95Milliseconds > gate.maximumStablePreviewP95Milliseconds {
            failures.append(failure(
                .stablePreviewLatency,
                observed: value.stablePreviewP95Milliseconds,
                required: gate.maximumStablePreviewP95Milliseconds
            ))
        }

        return failures.sorted { $0.code.rawValue < $1.code.rawValue }
    }

    /// Pooled Wilson bounds are retained only as a diagnostic sanity check. They
    /// are never the gate's generalization interval because attempts from one
    /// writer are correlated.
    static func pooledWilsonLowerBound(successes: Int, trials: Int) -> Double {
        pooledWilsonBounds(successes: successes, trials: trials).lower
    }

    static func pooledWilsonUpperBound(successes: Int, trials: Int) -> Double {
        pooledWilsonBounds(successes: successes, trials: trials).upper
    }

    /// One writer is one independent observation. The bound estimates the mean
    /// unseen-writer rate, not the worst-writer probability, and never pools
    /// correlated attempts. Bonferroni alpha/4 shares one one-sided error budget
    /// across exact accuracy, top-three accuracy, trusted risk, and the companion
    /// future-writer pass-probability bound. A writer with no trusted prediction
    /// contributes risk 1; n < 2 fails closed.
    static func writerClusterBonferroniEmpiricalBernsteinBounds(
        summaries: [WriterIndependentWriterOutcomeSummary],
        overallFamilyWiseAlpha: Double
    ) -> (
        exactAccuracyLowerBound: Double,
        topThreeAccuracyLowerBound: Double,
        trustedRiskUpperBound: Double
    ) {
        guard summaries.count >= 2,
              overallFamilyWiseAlpha.isFinite,
              overallFamilyWiseAlpha > 0,
              overallFamilyWiseAlpha < 1 else { return (0, 0, 1) }
        let exactRates = summaries.map { rate($0.exactCorrectCount, $0.legibleValidCount, empty: 0) }
        let topThreeRates = summaries.map { rate($0.topThreeCorrectCount, $0.legibleValidCount, empty: 0) }
        let trustedRiskRates = summaries.map {
            rate($0.trustedWrongLegibleCount, $0.trustedLegibleCount, empty: 1)
        }

        return (
            empiricalBernsteinBound(values: exactRates, overallFamilyWiseAlpha: overallFamilyWiseAlpha).lower,
            empiricalBernsteinBound(values: topThreeRates, overallFamilyWiseAlpha: overallFamilyWiseAlpha).lower,
            empiricalBernsteinBound(values: trustedRiskRates, overallFamilyWiseAlpha: overallFamilyWiseAlpha).upper
        )
    }

    /// Exact one-sided Clopper-Pearson lower bound for a binomial proportion.
    /// For k=n this is alpha^(1/n). With a .05 overall budget divided across
    /// four claims, ten of ten is only 0.6452.
    static func oneSidedClopperPearsonLowerBound(
        successes: Int,
        trials: Int,
        alpha: Double
    ) -> Double {
        guard trials > 0,
              successes > 0,
              successes <= trials,
              alpha.isFinite,
              alpha > 0,
              alpha < 1 else { return 0 }
        if successes == trials {
            return exp(log(alpha) / Double(trials))
        }

        var lower = 0.0
        var upper = 1.0
        for _ in 0..<100 {
            let candidate = (lower + upper) / 2
            if binomialUpperTail(
                successesAtLeast: successes,
                trials: trials,
                probability: candidate
            ) >= alpha {
                upper = candidate
            } else {
                lower = candidate
            }
        }
        return (lower + upper) / 2
    }

    static func writerPasses(
        _ summary: WriterIndependentWriterOutcomeSummary,
        gate: WriterIndependentRecognitionGate
    ) -> Bool {
        guard summary.legibleValidCount >= gate.minimumWriterPassLegibleCount else { return false }
        let exactAccuracy = rate(summary.exactCorrectCount, summary.legibleValidCount, empty: 0)
        let topThreeAccuracy = rate(summary.topThreeCorrectCount, summary.legibleValidCount, empty: 0)
        let trustedCoverage = rate(summary.trustedLegibleCount, summary.legibleValidCount, empty: 0)
        let trustedRisk = rate(
            summary.trustedWrongLegibleCount,
            summary.trustedLegibleCount,
            empty: 1
        )
        return exactAccuracy >= gate.minimumWriterPassExactAccuracy
            && topThreeAccuracy >= gate.minimumWriterPassTopThreeAccuracy
            && trustedCoverage >= gate.minimumWriterPassTrustedCoverage
            && summary.trustedWrongLegibleCount <= gate.maximumWriterPassTrustedWrongCount
            && trustedRisk <= gate.maximumWriterPassTrustedRisk
    }

    private static func binomialUpperTail(
        successesAtLeast: Int,
        trials: Int,
        probability: Double
    ) -> Double {
        if probability <= 0 { return 0 }
        if probability >= 1 { return 1 }
        let logProbability = log(probability)
        let logFailureProbability = log1p(-probability)
        var logCombination = 0.0
        if successesAtLeast > 0 {
            for index in 1...successesAtLeast {
                logCombination += log(Double(trials - successesAtLeast + index)) - log(Double(index))
            }
        }
        var successes = successesAtLeast
        var logMass = logCombination
            + Double(successes) * logProbability
            + Double(trials - successes) * logFailureProbability
        var logTail = logMass
        while successes < trials {
            logMass += log(Double(trials - successes))
                - log(Double(successes + 1))
                + logProbability
                - logFailureProbability
            logTail = logAddExp(logTail, logMass)
            successes += 1
        }
        return min(1, exp(logTail))
    }

    private static func logAddExp(_ lhs: Double, _ rhs: Double) -> Double {
        let maximum = max(lhs, rhs)
        guard maximum.isFinite else { return maximum }
        return maximum + log(exp(lhs - maximum) + exp(rhs - maximum))
    }

    private static func empiricalBernsteinBound(
        values: [Double],
        overallFamilyWiseAlpha: Double
    ) -> (lower: Double, upper: Double) {
        guard values.count >= 2,
              values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return (0, 1)
        }
        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        let sampleVariance = values
            .map { value in
                let delta = value - mean
                return delta * delta
            }
            .reduce(0, +) / (n - 1)
        let metricAlpha = overallFamilyWiseAlpha / 4
        let logTerm = log(2) - log(metricAlpha)
        let radius = sqrt(2 * sampleVariance * logTerm / n)
            + 7 * logTerm / (3 * (n - 1))
        return (max(0, mean - radius), min(1, mean + radius))
    }

    private static func rate(_ numerator: Int, _ denominator: Int, empty: Double) -> Double {
        guard denominator > 0 else { return empty }
        return Double(numerator) / Double(denominator)
    }

    private static func isCanonicalSHA256ForGate(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102: true
            default: false
            }
        }
    }

    private static func pooledWilsonBounds(successes: Int, trials: Int) -> (lower: Double, upper: Double) {
        guard trials > 0, successes >= 0, successes <= trials else { return (0, 1) }
        let n = Double(trials)
        let p = Double(successes) / n
        let z = oneSided95PercentZ
        let zSquared = z * z
        let denominator = 1 + zSquared / n
        let center = (p + zSquared / (2 * n)) / denominator
        let margin = z / denominator * sqrt(p * (1 - p) / n + zSquared / (4 * n * n))
        return (max(0, center - margin), min(1, center + margin))
    }

    private static func matchesExpectedIdentity(
        _ payload: WriterIndependentEvaluationReceiptPayload,
        expected: WriterIndependentEvaluationExpectation
    ) -> Bool {
        payload.evaluationProtocolVersion == expected.evaluationProtocolVersion
            && payload.evaluationAuthorizationID == expected.evaluationAuthorizationID
            && payload.evaluationAttemptOrdinal == expected.evaluationAttemptOrdinal
            && payload.datasetVersion == expected.datasetVersion
            && payload.datasetMerkleRootSHA256.lowercased() == expected.datasetMerkleRootSHA256.lowercased()
            && payload.evaluationManifestSHA256.lowercased() == expected.evaluationManifestSHA256.lowercased()
            && payload.provenanceSnapshotSHA256.lowercased() == expected.provenanceSnapshotSHA256.lowercased()
            && payload.groundTruthRegistryVersion == expected.groundTruthRegistryVersion
            && payload.groundTruthRegistryEpoch == expected.groundTruthRegistryEpoch
            && payload.groundTruthSnapshotSHA256.lowercased() == expected.groundTruthSnapshotSHA256.lowercased()
            && payload.groundTruthMerkleRootSHA256.lowercased() == expected.groundTruthMerkleRootSHA256.lowercased()
            && payload.recognizerArtifactSHA256.lowercased() == expected.recognizerArtifactSHA256.lowercased()
            && payload.evaluatorArtifactSHA256.lowercased() == expected.evaluatorArtifactSHA256.lowercased()
            && payload.latencyDeviceClass == expected.latencyDeviceClass
            && payload.pipelineVersion == expected.pipelineVersion
            && payload.calibrationVersion == expected.calibrationVersion
            && payload.metricDefinitionVersion == expected.metricDefinitionVersion
            && payload.writerCommitmentSchemeVersion == expected.writerCommitmentSchemeVersion
            && payload.writerCommitmentMerkleRootSHA256.lowercased()
                == expected.writerCommitmentMerkleRootSHA256.lowercased()
    }

    private static func gateIsValid(_ gate: WriterIndependentRecognitionGate) -> Bool {
        let nonnegativeCounts = [
            gate.minimumIndependentWriters,
            gate.minimumLegibleSamples,
            gate.minimumAmbiguousOrNegativeSamples,
            gate.minimumEvaluableHumanSamplesPerWriter,
            gate.minimumWriterPassLegibleCount,
            gate.maximumWriterPassTrustedWrongCount,
            gate.maximumTrustedWrongLegibleCount,
            gate.maximumFalseTrustedAmbiguousOrNegativeCount,
            gate.maximumFrozenTargetMutationCount
        ]
        let unitThresholds = [
            gate.minimumExactAccuracyLowerBound,
            gate.minimumTopThreeAccuracyLowerBound,
            gate.maximumTrustedRiskUpperBound,
            gate.minimumTrustedCoverage,
            gate.minimumWriterMacroExactAccuracy,
            gate.minimumWriterTrustedCoverage,
            gate.minimumOwnershipF1,
            gate.maximumExpectedCalibrationError,
            gate.maximumBrierScore,
            gate.maximumTechnicalFailureRate,
            gate.minimumWriterPassExactAccuracy,
            gate.minimumWriterPassTopThreeAccuracy,
            gate.minimumWriterPassTrustedCoverage,
            gate.maximumWriterPassTrustedRisk,
            gate.minimumWriterPassProbabilityLowerBound
        ]
        let latencies = [
            gate.maximumRecognitionComputeP95Milliseconds,
            gate.maximumStablePreviewP95Milliseconds
        ]
        let stratumKeys = gate.requiredStrata.map(\.key)
        let mandatoryKeys = WriterIndependentEvaluationProtocolContract.requiredStratumKeys
        let strataAreValid = !gate.requiredStrata.isEmpty
            && Set(stratumKeys).count == stratumKeys.count
            && mandatoryKeys.isSubset(of: Set(stratumKeys))
            && gate.requiredStrata.allSatisfy { requirement in
                !requirement.key.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && requirement.minimumIndependentWriterCount >= 2
                    && requirement.minimumHumanSampleCount >= 1
                    && requirement.minimumLegibleSampleCount >= 1
                    && requirement.maximumTrustedWrongLegibleCount >= 0
                    && requirement.minimumExactAccuracy.isFinite
                    && (0...1).contains(requirement.minimumExactAccuracy)
                    && requirement.minimumTrustedCoverage.isFinite
                    && (0...1).contains(requirement.minimumTrustedCoverage)
            }
        return !gate.definitionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && gate.evaluationProtocolVersion == WriterIndependentEvaluationProtocolContract.currentVersion
            && !gate.uncertaintyMethodVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && gate.uncertaintyMethodVersion == supportedUncertaintyMethodVersion
            && gate.overallFamilyWiseAlpha.isFinite
            && gate.overallFamilyWiseAlpha > 0
            && gate.overallFamilyWiseAlpha < 1
            && gate.writerPassPredicateVersion == supportedWriterPassPredicateVersion
            && gate.writerPassProbabilityMethodVersion == supportedWriterPassProbabilityMethodVersion
            && gate.minimumIndependentWriters >= 2
            && gate.minimumEvaluableHumanSamplesPerWriter >= 1
            && gate.minimumWriterPassLegibleCount >= 1
            && nonnegativeCounts.allSatisfy { $0 >= 0 }
            && unitThresholds.allSatisfy { $0.isFinite && (0...1).contains($0) }
            && latencies.allSatisfy { $0.isFinite && $0 >= 0 }
            && strataAreValid
    }

    private static func failure(
        _ code: WriterIndependentRecognitionGateFailure.Code,
        observed: Double? = nil,
        required: Double? = nil
    ) -> WriterIndependentRecognitionGateFailure {
        WriterIndependentRecognitionGateFailure(code: code, observed: observed, required: required)
    }
}

/// The only fail-closed entry point for treating a signed aggregate receipt as
/// consumed evidence. It requires fresh authority state and performs the
/// one-use/alpha transition atomically. Metric failures still spend the
/// authorization so a caller cannot inspect a holdout repeatedly and publish
/// only the favorable receipt.
enum WriterIndependentEvaluationConsumptionBoundary {
    static let maximumFreshnessCheckpointLifetimeSeconds: Int64 = 300

    static func consume(
        receipt: SignedWriterIndependentEvaluationReceipt,
        expected: WriterIndependentEvaluationExpectation,
        trustedEvaluationSigningPublicKeysByID: [String: Data],
        gate: WriterIndependentRecognitionGate,
        freshnessCheckpoint: SignedWriterIndependentEvaluationFreshnessCheckpoint,
        trustedFreshnessSigningPublicKeysByID: [String: Data],
        currentUnixSeconds: Int64,
        authorizationLedger: WriterIndependentEvaluationAuthorizationLedger
    ) -> WriterIndependentEvaluationConsumptionResult {
        let gateFailures = WriterIndependentRecognitionGateEvaluator.failures(
            for: receipt,
            expected: expected,
            trustedSigningPublicKeysByID: trustedEvaluationSigningPublicKeysByID,
            gate: gate
        )
        if !WriterIndependentEvaluationReceiptValidator.signatureIsValid(
            receipt,
            trustedSigningPublicKeysByID: trustedEvaluationSigningPublicKeysByID
        ) || !WriterIndependentRecognitionGateEvaluator.evidenceIdentityIsValidForConsumption(
            receipt.payload,
            expected: expected,
            gate: gate
        ) {
            return WriterIndependentEvaluationConsumptionResult(
                gateFailures: gateFailures,
                consumptionFailures: [failure(
                    .invalidEvaluationEvidence,
                    "Receipt signature, identity, split, and gate binding must validate before authorization consumption."
                )],
                authorizationConsumed: false
            )
        }

        guard checkpointIsAuthentic(
            freshnessCheckpoint,
            trustedPublicKeysByID: trustedFreshnessSigningPublicKeysByID
        ), checkpointEnvelopeIsValid(
            freshnessCheckpoint.payload,
            currentUnixSeconds: currentUnixSeconds
        ) else {
            return WriterIndependentEvaluationConsumptionResult(
                gateFailures: gateFailures,
                consumptionFailures: [failure(
                    .invalidFreshnessCheckpoint,
                    "A current, short-lived checkpoint signed by an allowlisted freshness authority is required."
                )],
                authorizationConsumed: false
            )
        }

        let checkpoint = freshnessCheckpoint.payload
        var freshnessFailures: [WriterIndependentEvaluationConsumptionFailure] = []
        if checkpoint.provenanceState != .current
            || checkpoint.provenanceValidUntilUnixSeconds <= currentUnixSeconds
            || checkpoint.provenanceSnapshotSHA256.lowercased()
                != receipt.payload.provenanceSnapshotSHA256.lowercased()
            || checkpoint.provenanceSnapshotSHA256.lowercased()
                != expected.provenanceSnapshotSHA256.lowercased() {
            freshnessFailures.append(failure(
                .staleOrRevokedProvenance,
                "The receipt must bind the currently authorized, unexpired consent/cohort provenance snapshot."
            ))
        }
        if checkpoint.groundTruthState != .current
            || checkpoint.groundTruthValidUntilUnixSeconds <= currentUnixSeconds
            || checkpoint.groundTruthRegistryVersion != receipt.payload.groundTruthRegistryVersion
            || checkpoint.groundTruthRegistryVersion != expected.groundTruthRegistryVersion
            || checkpoint.groundTruthRegistryEpoch != receipt.payload.groundTruthRegistryEpoch
            || checkpoint.groundTruthRegistryEpoch != expected.groundTruthRegistryEpoch
            || checkpoint.groundTruthSnapshotSHA256.lowercased()
                != receipt.payload.groundTruthSnapshotSHA256.lowercased()
            || checkpoint.groundTruthSnapshotSHA256.lowercased()
                != expected.groundTruthSnapshotSHA256.lowercased()
            || checkpoint.groundTruthMerkleRootSHA256.lowercased()
                != receipt.payload.groundTruthMerkleRootSHA256.lowercased()
            || checkpoint.groundTruthMerkleRootSHA256.lowercased()
                != expected.groundTruthMerkleRootSHA256.lowercased() {
            freshnessFailures.append(failure(
                .staleOrRevokedGroundTruth,
                "The receipt must bind the currently authorized, unexpired frozen-label registry."
            ))
        }
        if !freshnessFailures.isEmpty {
            return WriterIndependentEvaluationConsumptionResult(
                gateFailures: gateFailures,
                consumptionFailures: freshnessFailures.sorted { $0.code.rawValue < $1.code.rawValue },
                authorizationConsumed: false
            )
        }

        if let ledgerFailure = authorizationLedger.consume(
            payload: receipt.payload,
            familyWiseAlpha: gate.overallFamilyWiseAlpha
        ) {
            return WriterIndependentEvaluationConsumptionResult(
                gateFailures: gateFailures,
                consumptionFailures: [ledgerFailure],
                authorizationConsumed: false
            )
        }
        return WriterIndependentEvaluationConsumptionResult(
            gateFailures: gateFailures,
            consumptionFailures: [],
            authorizationConsumed: true
        )
    }

    private static func checkpointIsAuthentic(
        _ checkpoint: SignedWriterIndependentEvaluationFreshnessCheckpoint,
        trustedPublicKeysByID: [String: Data]
    ) -> Bool {
        let keyID = checkpoint.signingKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty,
              let signature = Data(base64Encoded: checkpoint.signatureBase64),
              !signature.isEmpty,
              let rawPublicKey = trustedPublicKeysByID[keyID],
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey),
              let canonicalPayload = try? checkpoint.payload.canonicalData() else {
            return false
        }
        return publicKey.isValidSignature(signature, for: canonicalPayload)
    }

    private static func checkpointEnvelopeIsValid(
        _ checkpoint: WriterIndependentEvaluationFreshnessCheckpointPayload,
        currentUnixSeconds: Int64
    ) -> Bool {
        let maximumExpiry = checkpoint.issuedAtUnixSeconds.addingReportingOverflow(
            maximumFreshnessCheckpointLifetimeSeconds
        )
        guard !maximumExpiry.overflow else { return false }
        let hashes = [
            checkpoint.provenanceSnapshotSHA256,
            checkpoint.groundTruthSnapshotSHA256,
            checkpoint.groundTruthMerkleRootSHA256
        ]
        return checkpoint.schemaVersion
                == WriterIndependentEvaluationFreshnessCheckpointPayload.currentSchemaVersion
            && !checkpoint.checkpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !checkpoint.groundTruthRegistryVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hashes.allSatisfy(isCanonicalSHA256)
            && checkpoint.issuedAtUnixSeconds <= currentUnixSeconds
            && checkpoint.expiresAtUnixSeconds > currentUnixSeconds
            && checkpoint.expiresAtUnixSeconds > checkpoint.issuedAtUnixSeconds
            && checkpoint.expiresAtUnixSeconds <= maximumExpiry.partialValue
            && checkpoint.provenanceValidUntilUnixSeconds > checkpoint.issuedAtUnixSeconds
            && checkpoint.groundTruthValidUntilUnixSeconds > checkpoint.issuedAtUnixSeconds
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102: true
            default: false
            }
        }
    }

    private static func failure(
        _ code: WriterIndependentEvaluationConsumptionFailure.Code,
        _ detail: String
    ) -> WriterIndependentEvaluationConsumptionFailure {
        WriterIndependentEvaluationConsumptionFailure(code: code, detail: detail)
    }
}

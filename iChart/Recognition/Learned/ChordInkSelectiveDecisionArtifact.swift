import Foundation

enum ChordInkSelectiveDecisionScoreContract {
    /// The calibrated input is the log probability of one decoded path versus
    /// every other possible outcome. It is converted to a binary logit before
    /// applying the independently fitted temperature.
    static let version = "joint-path-one-vs-rest-v1"
}

struct ChordInkSelectiveDecisionThresholds: Codable, Equatable, Sendable {
    let autoAcceptMinimumTopSupport: Double
    let autoAcceptMinimumMargin: Double
    let confirmMinimumTopSupport: Double
    let confirmMinimumMargin: Double
    let candidateReviewMinimumTopSupport: Double
    let noReadMinimumSupport: Double
}

enum ChordInkSelectiveDecisionArtifactValidationError: Error, Equatable, Sendable {
    case contractVersionMismatch(expected: String, actual: String)
    case scoreContractVersionMismatch(expected: String, actual: String)
    case invalidArtifactDigest
    case manifestDigestMismatch
    case modelDigestMismatch
    case calibrationDigestMismatch
    case sealedGateReceiptDigestMismatch
    case featureSchemaVersionMismatch
    case outputContractVersionMismatch
    case evaluationProtocolMismatch
    case thresholdsNotPredeclared
    case writerDisjointThresholdSelectionRequired
    case emptyThresholdSelectionDatasetIdentifier
    case nonFiniteThreshold(name: String)
    case thresholdOutOfRange(name: String)
    case nonMonotonicTopSupportThresholds
    case nonMonotonicMarginThresholds
}

/// Versioned selective policy emitted by the offline evaluation pipeline.
///
/// The artifact is deliberately separate from temperature calibration: the
/// calibration artifact estimates one-vs-rest support, while this artifact
/// records the thresholds that were selected before the sealed evaluation.
/// Its bindings prevent thresholds for one model/calibration/gate receipt from
/// authorizing another.
struct ChordInkSelectiveDecisionArtifact: Codable, Equatable, Sendable {
    static let contractVersion = "chord-ink-selective-decision-v1"

    let artifactContractVersion: String
    let decisionArtifactSHA256: String
    let manifestArtifactSHA256: String
    let modelArtifactSHA256: String
    let calibrationArtifactSHA256: String
    let sealedGateReceiptSHA256: String
    let featureSchemaVersion: String
    let outputContractVersion: String
    let scoreContractVersion: String
    let evaluationProtocolIdentifier: String
    let thresholdsWerePredeclaredBeforeSealedEvaluation: Bool
    let usedWriterDisjointThresholdSelectionData: Bool
    let thresholdSelectionDatasetIdentifier: String
    let thresholds: ChordInkSelectiveDecisionThresholds

    init(
        artifactContractVersion: String = Self.contractVersion,
        decisionArtifactSHA256: String,
        manifestArtifactSHA256: String,
        modelArtifactSHA256: String,
        calibrationArtifactSHA256: String,
        sealedGateReceiptSHA256: String,
        featureSchemaVersion: String = ChordInkFeatureSchema.version,
        outputContractVersion: String = ChordInkLearnedOutputContract.version,
        scoreContractVersion: String = ChordInkSelectiveDecisionScoreContract.version,
        evaluationProtocolIdentifier: String,
        thresholdsWerePredeclaredBeforeSealedEvaluation: Bool,
        usedWriterDisjointThresholdSelectionData: Bool,
        thresholdSelectionDatasetIdentifier: String,
        thresholds: ChordInkSelectiveDecisionThresholds
    ) {
        self.artifactContractVersion = artifactContractVersion
        self.decisionArtifactSHA256 = decisionArtifactSHA256
        self.manifestArtifactSHA256 = manifestArtifactSHA256
        self.modelArtifactSHA256 = modelArtifactSHA256
        self.calibrationArtifactSHA256 = calibrationArtifactSHA256
        self.sealedGateReceiptSHA256 = sealedGateReceiptSHA256
        self.featureSchemaVersion = featureSchemaVersion
        self.outputContractVersion = outputContractVersion
        self.scoreContractVersion = scoreContractVersion
        self.evaluationProtocolIdentifier = evaluationProtocolIdentifier
        self.thresholdsWerePredeclaredBeforeSealedEvaluation =
            thresholdsWerePredeclaredBeforeSealedEvaluation
        self.usedWriterDisjointThresholdSelectionData =
            usedWriterDisjointThresholdSelectionData
        self.thresholdSelectionDatasetIdentifier = thresholdSelectionDatasetIdentifier
        self.thresholds = thresholds
    }

    func validate(
        manifest: ChordInkModelArtifactManifest,
        calibration: ChordInkValidatedCalibrationArtifact,
        sealedGateReceipt: ChordInkValidatedSealedGateReceipt
    ) throws -> ChordInkValidatedSelectiveDecisionArtifact {
        guard artifactContractVersion == Self.contractVersion else {
            throw ChordInkSelectiveDecisionArtifactValidationError.contractVersionMismatch(
                expected: Self.contractVersion,
                actual: artifactContractVersion
            )
        }
        guard scoreContractVersion == ChordInkSelectiveDecisionScoreContract.version else {
            throw ChordInkSelectiveDecisionArtifactValidationError.scoreContractVersionMismatch(
                expected: ChordInkSelectiveDecisionScoreContract.version,
                actual: scoreContractVersion
            )
        }
        guard ChordInkArtifactDigest.isCanonicalSHA256(decisionArtifactSHA256) else {
            throw ChordInkSelectiveDecisionArtifactValidationError.invalidArtifactDigest
        }
        guard manifestArtifactSHA256 == manifest.manifestArtifactSHA256 else {
            throw ChordInkSelectiveDecisionArtifactValidationError.manifestDigestMismatch
        }
        guard modelArtifactSHA256 == manifest.modelArtifactSHA256 else {
            throw ChordInkSelectiveDecisionArtifactValidationError.modelDigestMismatch
        }
        guard calibrationArtifactSHA256 == calibration.artifact.calibrationArtifactSHA256 else {
            throw ChordInkSelectiveDecisionArtifactValidationError.calibrationDigestMismatch
        }
        let receipt = sealedGateReceipt.receipt
        guard sealedGateReceiptSHA256 == receipt.receiptArtifactSHA256 else {
            throw ChordInkSelectiveDecisionArtifactValidationError.sealedGateReceiptDigestMismatch
        }
        guard featureSchemaVersion == ChordInkFeatureSchema.version else {
            throw ChordInkSelectiveDecisionArtifactValidationError.featureSchemaVersionMismatch
        }
        guard outputContractVersion == ChordInkLearnedOutputContract.version else {
            throw ChordInkSelectiveDecisionArtifactValidationError.outputContractVersionMismatch
        }
        guard evaluationProtocolIdentifier == receipt.evaluationProtocolIdentifier else {
            throw ChordInkSelectiveDecisionArtifactValidationError.evaluationProtocolMismatch
        }
        guard thresholdsWerePredeclaredBeforeSealedEvaluation else {
            throw ChordInkSelectiveDecisionArtifactValidationError.thresholdsNotPredeclared
        }
        guard usedWriterDisjointThresholdSelectionData else {
            throw ChordInkSelectiveDecisionArtifactValidationError
                .writerDisjointThresholdSelectionRequired
        }
        guard !thresholdSelectionDatasetIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            throw ChordInkSelectiveDecisionArtifactValidationError
                .emptyThresholdSelectionDatasetIdentifier
        }

        try validateThresholds()
        return ChordInkValidatedSelectiveDecisionArtifact(artifact: self)
    }

    private func validateThresholds() throws {
        let values: [(String, Double)] = [
            ("auto_accept_minimum_top_support", thresholds.autoAcceptMinimumTopSupport),
            ("auto_accept_minimum_margin", thresholds.autoAcceptMinimumMargin),
            ("confirm_minimum_top_support", thresholds.confirmMinimumTopSupport),
            ("confirm_minimum_margin", thresholds.confirmMinimumMargin),
            ("candidate_review_minimum_top_support", thresholds.candidateReviewMinimumTopSupport),
            ("no_read_minimum_support", thresholds.noReadMinimumSupport)
        ]
        for (name, value) in values {
            guard value.isFinite else {
                throw ChordInkSelectiveDecisionArtifactValidationError.nonFiniteThreshold(
                    name: name
                )
            }
            guard (0...1).contains(value) else {
                throw ChordInkSelectiveDecisionArtifactValidationError.thresholdOutOfRange(
                    name: name
                )
            }
        }
        guard thresholds.autoAcceptMinimumTopSupport >= thresholds.confirmMinimumTopSupport,
              thresholds.confirmMinimumTopSupport
                >= thresholds.candidateReviewMinimumTopSupport else {
            throw ChordInkSelectiveDecisionArtifactValidationError
                .nonMonotonicTopSupportThresholds
        }
        guard thresholds.autoAcceptMinimumMargin >= thresholds.confirmMinimumMargin else {
            throw ChordInkSelectiveDecisionArtifactValidationError
                .nonMonotonicMarginThresholds
        }
    }
}

struct ChordInkValidatedSelectiveDecisionArtifact: Equatable, Sendable {
    let artifact: ChordInkSelectiveDecisionArtifact

    fileprivate init(artifact: ChordInkSelectiveDecisionArtifact) {
        self.artifact = artifact
    }
}

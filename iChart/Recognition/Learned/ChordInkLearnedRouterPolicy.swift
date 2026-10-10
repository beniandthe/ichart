import Foundation

enum ChordInkSealedGateReceiptValidationError: Error, Equatable, Sendable {
    case contractVersionMismatch(expected: String, actual: String)
    case invalidReceiptDigest
    case manifestDigestMismatch
    case modelDigestMismatch
    case calibrationDigestMismatch
    case featureSchemaVersionMismatch
    case outputContractVersionMismatch
    case emptyEvaluationProtocolIdentifier
    case emptySealedDatasetIdentifier
    case writerDisjointEvaluationRequired
    case datasetMustBeSealedBeforeEvaluation
    case predeclaredGatesDidNotPass
}
/// Receipt emitted by the offline, sealed evaluation process. The app does not
/// define accuracy thresholds; it only verifies that the artifact bound to the
/// installed model and calibration says every predeclared gate passed.
struct ChordInkSealedGateReceipt: Codable, Equatable, Sendable {
    static let contractVersion = "chord-ink-sealed-gate-receipt-v1"

    let receiptContractVersion: String
    let receiptArtifactSHA256: String
    let manifestArtifactSHA256: String
    let modelArtifactSHA256: String
    let calibrationArtifactSHA256: String
    let featureSchemaVersion: String
    let outputContractVersion: String
    let evaluationProtocolIdentifier: String
    let sealedDatasetIdentifier: String
    let usedWriterDisjointEvaluation: Bool
    let datasetWasSealedBeforeEvaluation: Bool
    let passedAllPredeclaredGates: Bool

    init(
        receiptContractVersion: String = Self.contractVersion,
        receiptArtifactSHA256: String,
        manifestArtifactSHA256: String,
        modelArtifactSHA256: String,
        calibrationArtifactSHA256: String,
        featureSchemaVersion: String = ChordInkFeatureSchema.version,
        outputContractVersion: String = ChordInkLearnedOutputContract.version,
        evaluationProtocolIdentifier: String,
        sealedDatasetIdentifier: String,
        usedWriterDisjointEvaluation: Bool,
        datasetWasSealedBeforeEvaluation: Bool,
        passedAllPredeclaredGates: Bool
    ) {
        self.receiptContractVersion = receiptContractVersion
        self.receiptArtifactSHA256 = receiptArtifactSHA256
        self.manifestArtifactSHA256 = manifestArtifactSHA256
        self.modelArtifactSHA256 = modelArtifactSHA256
        self.calibrationArtifactSHA256 = calibrationArtifactSHA256
        self.featureSchemaVersion = featureSchemaVersion
        self.outputContractVersion = outputContractVersion
        self.evaluationProtocolIdentifier = evaluationProtocolIdentifier
        self.sealedDatasetIdentifier = sealedDatasetIdentifier
        self.usedWriterDisjointEvaluation = usedWriterDisjointEvaluation
        self.datasetWasSealedBeforeEvaluation = datasetWasSealedBeforeEvaluation
        self.passedAllPredeclaredGates = passedAllPredeclaredGates
    }

    fileprivate func validate(
        manifest: ChordInkModelArtifactManifest,
        calibration: ChordInkValidatedCalibrationArtifact
    ) throws -> ChordInkValidatedSealedGateReceipt {
        guard receiptContractVersion == Self.contractVersion else {
            throw ChordInkSealedGateReceiptValidationError.contractVersionMismatch(
                expected: Self.contractVersion,
                actual: receiptContractVersion
            )
        }
        guard ChordInkArtifactDigest.isCanonicalSHA256(receiptArtifactSHA256) else {
            throw ChordInkSealedGateReceiptValidationError.invalidReceiptDigest
        }
        guard manifestArtifactSHA256 == manifest.manifestArtifactSHA256 else {
            throw ChordInkSealedGateReceiptValidationError.manifestDigestMismatch
        }
        guard modelArtifactSHA256 == manifest.modelArtifactSHA256 else {
            throw ChordInkSealedGateReceiptValidationError.modelDigestMismatch
        }
        guard calibrationArtifactSHA256 == calibration.artifact.calibrationArtifactSHA256 else {
            throw ChordInkSealedGateReceiptValidationError.calibrationDigestMismatch
        }
        guard featureSchemaVersion == ChordInkFeatureSchema.version else {
            throw ChordInkSealedGateReceiptValidationError.featureSchemaVersionMismatch
        }
        guard outputContractVersion == ChordInkLearnedOutputContract.version else {
            throw ChordInkSealedGateReceiptValidationError.outputContractVersionMismatch
        }
        guard !evaluationProtocolIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChordInkSealedGateReceiptValidationError.emptyEvaluationProtocolIdentifier
        }
        guard !sealedDatasetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChordInkSealedGateReceiptValidationError.emptySealedDatasetIdentifier
        }
        guard usedWriterDisjointEvaluation else {
            throw ChordInkSealedGateReceiptValidationError.writerDisjointEvaluationRequired
        }
        guard datasetWasSealedBeforeEvaluation else {
            throw ChordInkSealedGateReceiptValidationError.datasetMustBeSealedBeforeEvaluation
        }
        guard passedAllPredeclaredGates else {
            throw ChordInkSealedGateReceiptValidationError.predeclaredGatesDidNotPass
        }
        return ChordInkValidatedSealedGateReceipt(receipt: self)
    }
}

struct ChordInkValidatedSealedGateReceipt: Equatable, Sendable {
    let receipt: ChordInkSealedGateReceipt

    fileprivate init(receipt: ChordInkSealedGateReceipt) {
        self.receipt = receipt
    }
}

enum ChordInkRecognitionRouterMode: String, Codable, Equatable, Sendable {
    case legacyProduction
    case learnedShadow
    case learnedCandidate
}

enum ChordInkRecognitionAuthority: Equatable, Sendable {
    case legacy
    case learnedCandidate(ChordInkValidatedSealedGateReceipt)
}

enum ChordInkLearnedCandidateDenialReason: Equatable, Sendable {
    case invalidManifest
    case developmentSelectionNotBound
    case missingCalibration
    case invalidCalibration
    case missingSealedGateReceipt
    case invalidSealedGateReceipt
}

struct ChordInkLearnedRouteDecision: Equatable, Sendable {
    let requestedMode: ChordInkRecognitionRouterMode
    let effectiveMode: ChordInkRecognitionRouterMode
    let shouldExecuteLearnedRuntime: Bool
    let learnedMayAffectUI: Bool
    let learnedMayAffectPersistence: Bool
    let authority: ChordInkRecognitionAuthority
    let denialReason: ChordInkLearnedCandidateDenialReason?
}

/// Central fail-closed authority decision. Shadow output can be observed and
/// logged, but cannot alter previews, accepted symbols, or stored chart state.
struct ChordInkLearnedRouterPolicy {
    func decision(
        requestedMode: ChordInkRecognitionRouterMode,
        manifest: ChordInkModelArtifactManifest,
        calibrationArtifact: ChordInkCalibrationArtifact?,
        sealedGateReceipt: ChordInkSealedGateReceipt?
    ) -> ChordInkLearnedRouteDecision {
        if requestedMode == .legacyProduction {
            return ChordInkLearnedRouteDecision(
                requestedMode: requestedMode,
                effectiveMode: .legacyProduction,
                shouldExecuteLearnedRuntime: false,
                learnedMayAffectUI: false,
                learnedMayAffectPersistence: false,
                authority: .legacy,
                denialReason: nil
            )
        }

        do {
            try manifest.validate()
        } catch {
            return ChordInkLearnedRouteDecision(
                requestedMode: requestedMode,
                effectiveMode: .legacyProduction,
                shouldExecuteLearnedRuntime: false,
                learnedMayAffectUI: false,
                learnedMayAffectPersistence: false,
                authority: .legacy,
                denialReason: .invalidManifest
            )
        }

        if requestedMode == .learnedShadow {
            return observationalDecision(requestedMode: requestedMode, denialReason: nil)
        }

        guard manifest.trainingProvenance.developmentSelectionAuthority
                == .boundDevelopmentWriterComparisonV4 else {
            return observationalDecision(
                requestedMode: requestedMode,
                denialReason: .developmentSelectionNotBound
            )
        }

        let calibrationResolution = ChordInkCalibrationResolution.resolve(
            artifact: calibrationArtifact,
            manifest: manifest
        )
        let calibration: ChordInkValidatedCalibrationArtifact
        switch calibrationResolution {
        case .validated(let value):
            calibration = value
        case .unavailable(.missingArtifact):
            return observationalDecision(
                requestedMode: requestedMode,
                denialReason: .missingCalibration
            )
        case .unavailable:
            return observationalDecision(
                requestedMode: requestedMode,
                denialReason: .invalidCalibration
            )
        }

        guard let sealedGateReceipt else {
            return observationalDecision(
                requestedMode: requestedMode,
                denialReason: .missingSealedGateReceipt
            )
        }

        let validatedReceipt: ChordInkValidatedSealedGateReceipt
        do {
            validatedReceipt = try sealedGateReceipt.validate(
                manifest: manifest,
                calibration: calibration
            )
        } catch {
            return observationalDecision(
                requestedMode: requestedMode,
                denialReason: .invalidSealedGateReceipt
            )
        }

        return ChordInkLearnedRouteDecision(
            requestedMode: requestedMode,
            effectiveMode: .learnedCandidate,
            shouldExecuteLearnedRuntime: true,
            learnedMayAffectUI: true,
            learnedMayAffectPersistence: true,
            authority: .learnedCandidate(validatedReceipt),
            denialReason: nil
        )
    }

    private func observationalDecision(
        requestedMode: ChordInkRecognitionRouterMode,
        denialReason: ChordInkLearnedCandidateDenialReason?
    ) -> ChordInkLearnedRouteDecision {
        ChordInkLearnedRouteDecision(
            requestedMode: requestedMode,
            effectiveMode: .learnedShadow,
            shouldExecuteLearnedRuntime: true,
            learnedMayAffectUI: false,
            learnedMayAffectPersistence: false,
            authority: .legacy,
            denialReason: denialReason
        )
    }
}

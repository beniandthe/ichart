import Foundation

enum ChordInkCalibrationMethod: String, Codable, Equatable, Sendable {
    case temperatureScaling = "temperature_scaling"
}
enum ChordInkCalibrationValidationError: Error, Equatable, Sendable {
    case contractVersionMismatch(expected: String, actual: String)
    case invalidArtifactDigest
    case manifestDigestMismatch
    case modelDigestMismatch
    case featureSchemaVersionMismatch
    case outputContractVersionMismatch
    case invalidTemperature
    case independentFitRequired
    case writerDisjointFitRequired
    case emptyFitDatasetIdentifier
    case invalidFitReceiptDigest
}

/// Calibration metadata fitted outside the app. It contains no acceptance
/// threshold; gate thresholds belong to a predeclared evaluation protocol.
struct ChordInkCalibrationArtifact: Codable, Equatable, Sendable {
    static let contractVersion = "chord-ink-calibration-v1"

    let artifactContractVersion: String
    let calibrationArtifactSHA256: String
    let manifestArtifactSHA256: String
    let modelArtifactSHA256: String
    let featureSchemaVersion: String
    let outputContractVersion: String
    let method: ChordInkCalibrationMethod
    let temperature: Double
    let wasIndependentlyFitted: Bool
    let usedWriterDisjointData: Bool
    let fitDatasetIdentifier: String
    let independentFitReceiptSHA256: String

    init(
        artifactContractVersion: String = Self.contractVersion,
        calibrationArtifactSHA256: String,
        manifestArtifactSHA256: String,
        modelArtifactSHA256: String,
        featureSchemaVersion: String = ChordInkFeatureSchema.version,
        outputContractVersion: String = ChordInkLearnedOutputContract.version,
        method: ChordInkCalibrationMethod = .temperatureScaling,
        temperature: Double,
        wasIndependentlyFitted: Bool,
        usedWriterDisjointData: Bool,
        fitDatasetIdentifier: String,
        independentFitReceiptSHA256: String
    ) {
        self.artifactContractVersion = artifactContractVersion
        self.calibrationArtifactSHA256 = calibrationArtifactSHA256
        self.manifestArtifactSHA256 = manifestArtifactSHA256
        self.modelArtifactSHA256 = modelArtifactSHA256
        self.featureSchemaVersion = featureSchemaVersion
        self.outputContractVersion = outputContractVersion
        self.method = method
        self.temperature = temperature
        self.wasIndependentlyFitted = wasIndependentlyFitted
        self.usedWriterDisjointData = usedWriterDisjointData
        self.fitDatasetIdentifier = fitDatasetIdentifier
        self.independentFitReceiptSHA256 = independentFitReceiptSHA256
    }

    fileprivate func validate(
        for manifest: ChordInkModelArtifactManifest
    ) throws -> ChordInkValidatedCalibrationArtifact {
        guard artifactContractVersion == Self.contractVersion else {
            throw ChordInkCalibrationValidationError.contractVersionMismatch(
                expected: Self.contractVersion,
                actual: artifactContractVersion
            )
        }
        guard ChordInkArtifactDigest.isCanonicalSHA256(calibrationArtifactSHA256) else {
            throw ChordInkCalibrationValidationError.invalidArtifactDigest
        }
        guard manifestArtifactSHA256 == manifest.manifestArtifactSHA256 else {
            throw ChordInkCalibrationValidationError.manifestDigestMismatch
        }
        guard modelArtifactSHA256 == manifest.modelArtifactSHA256 else {
            throw ChordInkCalibrationValidationError.modelDigestMismatch
        }
        guard featureSchemaVersion == ChordInkFeatureSchema.version else {
            throw ChordInkCalibrationValidationError.featureSchemaVersionMismatch
        }
        guard outputContractVersion == ChordInkLearnedOutputContract.version else {
            throw ChordInkCalibrationValidationError.outputContractVersionMismatch
        }
        guard temperature.isFinite, temperature > 0 else {
            throw ChordInkCalibrationValidationError.invalidTemperature
        }
        guard wasIndependentlyFitted else {
            throw ChordInkCalibrationValidationError.independentFitRequired
        }
        guard usedWriterDisjointData else {
            throw ChordInkCalibrationValidationError.writerDisjointFitRequired
        }
        guard !fitDatasetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChordInkCalibrationValidationError.emptyFitDatasetIdentifier
        }
        guard ChordInkArtifactDigest.isCanonicalSHA256(independentFitReceiptSHA256) else {
            throw ChordInkCalibrationValidationError.invalidFitReceiptDigest
        }
        return ChordInkValidatedCalibrationArtifact(artifact: self)
    }
}

struct ChordInkValidatedCalibrationArtifact: Equatable, Sendable {
    let artifact: ChordInkCalibrationArtifact

    fileprivate init(artifact: ChordInkCalibrationArtifact) {
        self.artifact = artifact
    }
}

enum ChordInkCalibrationUnavailableReason: Equatable, Sendable {
    case missingArtifact
    case invalidManifest
    case invalidArtifact
}

enum ChordInkCalibrationResolution: Equatable, Sendable {
    case unavailable(ChordInkCalibrationUnavailableReason)
    case validated(ChordInkValidatedCalibrationArtifact)

    static func resolve(
        artifact: ChordInkCalibrationArtifact?,
        manifest: ChordInkModelArtifactManifest
    ) -> ChordInkCalibrationResolution {
        do {
            try manifest.validate()
        } catch {
            return .unavailable(.invalidManifest)
        }

        guard let artifact else {
            return .unavailable(.missingArtifact)
        }

        do {
            return .validated(try artifact.validate(for: manifest))
        } catch {
            return .unavailable(.invalidArtifact)
        }
    }
}

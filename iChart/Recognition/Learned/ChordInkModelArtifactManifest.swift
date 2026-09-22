import Foundation

enum ChordInkArtifactDigest {
    static func isCanonicalSHA256(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 64 && bytes.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

enum ChordInkNumericType: String, Codable, Equatable, Sendable {
    case float32
    case uint8
}

enum ChordInkTensorLayout: String, Codable, Equatable, Sendable {
    case batchSampleChannel = "BSC"
    case batchHeightWidthChannel = "BHWC"
    case batchClass = "BC"
}

enum ChordInkValueScaling: String, Codable, Equatable, Sendable {
    /// Values are passed without an affine transform.
    case identity

    /// Values already carry the channel-specific normalization performed by
    /// `ChordInkTrajectoryFeatureEncoder`; the adapter must not normalize them again.
    case trajectoryFeatureV1Channelwise
}

enum ChordInkValueSemantics: String, Codable, Equatable, Sendable {
    case trajectoryFeatureV1
    case binaryInkMask
    case rawLogit
}

struct ChordInkValueRangeContract: Codable, Equatable, Sendable {
    let minimumInclusive: Double?
    let maximumInclusive: Double?
    let allowedDiscreteValues: [Double]?
    let finiteValuesRequired: Bool
}

struct ChordInkChannelContract: Codable, Equatable, Sendable {
    let index: Int
    let name: String
    let range: ChordInkValueRangeContract
}

struct ChordInkTensorContract: Codable, Equatable, Sendable {
    let name: String
    let shape: [Int]
    let numericType: ChordInkNumericType
    let layout: ChordInkTensorLayout
    let scaling: ChordInkValueScaling
    let valueSemantics: ChordInkValueSemantics
    let range: ChordInkValueRangeContract
    let channels: [ChordInkChannelContract]
}

struct ChordInkOutputHeadContract: Codable, Equatable, Sendable {
    let name: String
    let shape: [Int]
    let labels: [String]
    let numericType: ChordInkNumericType
    let layout: ChordInkTensorLayout
    let scaling: ChordInkValueScaling
    let valueSemantics: ChordInkValueSemantics
    let range: ChordInkValueRangeContract
}

enum ChordInkModelManifestValidationError: Error, Equatable, Sendable {
    case contractVersionMismatch(expected: String, actual: String)
    case outputContractVersionMismatch(expected: String, actual: String)
    case emptyModelIdentifier
    case invalidManifestDigest
    case invalidModelDigest
    case invalidModelByteCount
    case featureSchemaVersionMismatch(expected: String, actual: String)
    case trajectoryContractMismatch(expected: ChordInkTensorContract, actual: ChordInkTensorContract)
    case rasterContractMismatch(expected: ChordInkTensorContract, actual: ChordInkTensorContract)
    case outputHeadsMismatch(expected: [ChordInkOutputHeadContract], actual: [ChordInkOutputHeadContract])
}

/// Serializable sidecar contract for a learned model artifact. A model whose
/// names, shapes, labels, or digests differ from this manifest must not run.
struct ChordInkModelArtifactManifest: Codable, Equatable, Sendable {
    static let contractVersion = "chord-ink-model-manifest-v2"
    static let trajectoryInputName = "trajectory"
    static let rasterInputName = "raster"

    let manifestContractVersion: String
    let outputContractVersion: String
    let modelIdentifier: String
    /// Detached digest supplied by the release envelope alongside the manifest
    /// bytes. It is not a self-hash calculated from this Codable field.
    let manifestArtifactSHA256: String
    let modelArtifactSHA256: String
    let modelArtifactByteCount: Int64
    let featureSchemaVersion: String
    let trajectoryInput: ChordInkTensorContract
    let rasterInput: ChordInkTensorContract
    let outputHeads: [ChordInkOutputHeadContract]

    init(
        manifestContractVersion: String = Self.contractVersion,
        outputContractVersion: String = ChordInkLearnedOutputContract.version,
        modelIdentifier: String,
        manifestArtifactSHA256: String,
        modelArtifactSHA256: String,
        modelArtifactByteCount: Int64,
        featureSchemaVersion: String = ChordInkFeatureSchema.version,
        trajectoryInput: ChordInkTensorContract = Self.expectedTrajectoryInput,
        rasterInput: ChordInkTensorContract = Self.expectedRasterInput,
        outputHeads: [ChordInkOutputHeadContract] = Self.expectedOutputHeads
    ) {
        self.manifestContractVersion = manifestContractVersion
        self.outputContractVersion = outputContractVersion
        self.modelIdentifier = modelIdentifier
        self.manifestArtifactSHA256 = manifestArtifactSHA256
        self.modelArtifactSHA256 = modelArtifactSHA256
        self.modelArtifactByteCount = modelArtifactByteCount
        self.featureSchemaVersion = featureSchemaVersion
        self.trajectoryInput = trajectoryInput
        self.rasterInput = rasterInput
        self.outputHeads = outputHeads
    }

    func validate() throws {
        guard manifestContractVersion == Self.contractVersion else {
            throw ChordInkModelManifestValidationError.contractVersionMismatch(
                expected: Self.contractVersion,
                actual: manifestContractVersion
            )
        }
        guard outputContractVersion == ChordInkLearnedOutputContract.version else {
            throw ChordInkModelManifestValidationError.outputContractVersionMismatch(
                expected: ChordInkLearnedOutputContract.version,
                actual: outputContractVersion
            )
        }
        guard !modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChordInkModelManifestValidationError.emptyModelIdentifier
        }
        guard ChordInkArtifactDigest.isCanonicalSHA256(manifestArtifactSHA256) else {
            throw ChordInkModelManifestValidationError.invalidManifestDigest
        }
        guard ChordInkArtifactDigest.isCanonicalSHA256(modelArtifactSHA256) else {
            throw ChordInkModelManifestValidationError.invalidModelDigest
        }
        guard modelArtifactByteCount > 0 else {
            throw ChordInkModelManifestValidationError.invalidModelByteCount
        }
        guard featureSchemaVersion == ChordInkFeatureSchema.version else {
            throw ChordInkModelManifestValidationError.featureSchemaVersionMismatch(
                expected: ChordInkFeatureSchema.version,
                actual: featureSchemaVersion
            )
        }
        guard trajectoryInput == Self.expectedTrajectoryInput else {
            throw ChordInkModelManifestValidationError.trajectoryContractMismatch(
                expected: Self.expectedTrajectoryInput,
                actual: trajectoryInput
            )
        }
        guard rasterInput == Self.expectedRasterInput else {
            throw ChordInkModelManifestValidationError.rasterContractMismatch(
                expected: Self.expectedRasterInput,
                actual: rasterInput
            )
        }
        guard outputHeads == Self.expectedOutputHeads else {
            throw ChordInkModelManifestValidationError.outputHeadsMismatch(
                expected: Self.expectedOutputHeads,
                actual: outputHeads
            )
        }
    }

    static let expectedTrajectoryInput = ChordInkTensorContract(
        name: trajectoryInputName,
        shape: ChordInkFeatureSchema.trajectoryShape,
        numericType: .float32,
        layout: .batchSampleChannel,
        scaling: .trajectoryFeatureV1Channelwise,
        valueSemantics: .trajectoryFeatureV1,
        range: ChordInkValueRangeContract(
            minimumInclusive: -sqrt(2),
            maximumInclusive: sqrt(2),
            allowedDiscreteValues: nil,
            finiteValuesRequired: true
        ),
        channels: expectedTrajectoryChannels
    )

    static let expectedRasterInput = ChordInkTensorContract(
        name: rasterInputName,
        shape: ChordInkLearnedOutputContract.rasterShape,
        numericType: .uint8,
        layout: .batchHeightWidthChannel,
        scaling: .identity,
        valueSemantics: .binaryInkMask,
        range: ChordInkValueRangeContract(
            minimumInclusive: Double(ChordInkFeatureSchema.rasterBackground),
            maximumInclusive: Double(ChordInkFeatureSchema.rasterForeground),
            allowedDiscreteValues: [
                Double(ChordInkFeatureSchema.rasterBackground),
                Double(ChordInkFeatureSchema.rasterForeground)
            ],
            finiteValuesRequired: true
        ),
        channels: [
            ChordInkChannelContract(
                index: 0,
                name: "ink_mask",
                range: ChordInkValueRangeContract(
                    minimumInclusive: Double(ChordInkFeatureSchema.rasterBackground),
                    maximumInclusive: Double(ChordInkFeatureSchema.rasterForeground),
                    allowedDiscreteValues: [
                        Double(ChordInkFeatureSchema.rasterBackground),
                        Double(ChordInkFeatureSchema.rasterForeground)
                    ],
                    finiteValuesRequired: true
                )
            )
        ]
    )

    static let expectedTrajectoryChannels: [ChordInkChannelContract] = [
        channel(.x, name: "x", minimum: -0.5, maximum: 0.5),
        channel(.y, name: "y", minimum: -0.5, maximum: 0.5),
        channel(.deltaX, name: "delta_x", minimum: -1, maximum: 1),
        channel(.deltaY, name: "delta_y", minimum: -1, maximum: 1),
        channel(.arcStep, name: "arc_step", minimum: 0, maximum: sqrt(2)),
        channel(
            .normalizedDeltaTime,
            name: "normalized_delta_time",
            minimum: 0,
            maximum: 1
        ),
        binaryChannel(.timingAvailable, name: "timing_available"),
        binaryChannel(.strokeStart, name: "stroke_start"),
        binaryChannel(.strokeEnd, name: "stroke_end"),
        binaryChannel(.valid, name: "valid")
    ]

    static let expectedOutputHeads: [ChordInkOutputHeadContract] = {
        var heads = [
            head(
                name: ChordInkLearnedOutputContract.validityHeadName,
                labels: ChordInkValidityFactorLabel.allCases.map(\.rawValue)
            ),
            head(
                name: ChordInkLearnedOutputContract.kindHeadName,
                labels: ChordInkKindFactorLabel.allCases.map(\.rawValue)
            ),
            head(
                name: ChordInkLearnedOutputContract.rootLetterHeadName,
                labels: ChordNotation.Letter.allCases.map(\.rawValue)
            ),
            head(
                name: ChordInkLearnedOutputContract.rootAccidentalHeadName,
                labels: ChordInkAccidentalFactorLabel.allCases.map(\.rawValue)
            ),
            head(
                name: ChordInkLearnedOutputContract.qualityHeadName,
                labels: ChordNotation.Form.allCases.map(\.rawValue)
            ),
            head(
                name: ChordInkLearnedOutputContract.extensionHeadName,
                labels: ChordInkExtensionFactorLabel.allCases.map(\.rawValue)
            )
        ]
        heads.append(
            head(
                name: ChordInkLearnedOutputContract.alterationHeadName,
                labels: ChordNotation.Alteration.allCases.map(\.rawValue)
            )
        )
        heads.append(contentsOf: [
            head(
                name: ChordInkLearnedOutputContract.slashPresenceHeadName,
                labels: ChordInkSlashPresenceFactorLabel.allCases.map(\.rawValue)
            ),
            head(
                name: ChordInkLearnedOutputContract.slashBassLetterHeadName,
                labels: ChordNotation.Letter.allCases.map(\.rawValue)
            ),
            head(
                name: ChordInkLearnedOutputContract.slashBassAccidentalHeadName,
                labels: ChordInkAccidentalFactorLabel.allCases.map(\.rawValue)
            )
        ])
        return heads
    }()

    private static func head(name: String, labels: [String]) -> ChordInkOutputHeadContract {
        ChordInkOutputHeadContract(
            name: name,
            shape: [1, labels.count],
            labels: labels,
            numericType: .float32,
            layout: .batchClass,
            scaling: .identity,
            valueSemantics: .rawLogit,
            range: ChordInkValueRangeContract(
                minimumInclusive: nil,
                maximumInclusive: nil,
                allowedDiscreteValues: nil,
                finiteValuesRequired: true
            )
        )
    }

    private static func channel(
        _ channel: ChordInkFeatureSchema.TrajectoryChannel,
        name: String,
        minimum: Double,
        maximum: Double,
        allowedValues: [Double]? = nil
    ) -> ChordInkChannelContract {
        ChordInkChannelContract(
            index: channel.rawValue,
            name: name,
            range: ChordInkValueRangeContract(
                minimumInclusive: minimum,
                maximumInclusive: maximum,
                allowedDiscreteValues: allowedValues,
                finiteValuesRequired: true
            )
        )
    }

    private static func binaryChannel(
        _ channel: ChordInkFeatureSchema.TrajectoryChannel,
        name: String
    ) -> ChordInkChannelContract {
        self.channel(
            channel,
            name: name,
            minimum: 0,
            maximum: 1,
            allowedValues: [0, 1]
        )
    }
}

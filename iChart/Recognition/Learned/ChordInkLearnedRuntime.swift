import Foundation

enum ChordInkLearnedRuntimeContractError: Error, Equatable, Sendable {
    case loadedManifestDigestMismatch(expected: String, actual: String)
    case loadedModelDigestMismatch(expected: String, actual: String)
    case loadedModelByteCountMismatch(expected: Int64, actual: Int64)
    case trajectoryShapeMismatch(expected: [Int], actual: [Int])
    case rasterShapeMismatch(expected: [Int], actual: [Int])
    case nonFiniteTrajectoryValue(index: Int)
    case trajectoryValueOutOfContract(sample: Int, channel: Int, value: Float)
    case rasterValueOutOfContract(index: Int, value: UInt8)
}

/// Identity verified by the platform adapter while loading the bundle. The
/// manifest digest comes from the detached release envelope; the model digest
/// and byte count are calculated from the model bytes actually loaded.
struct ChordInkLoadedModelArtifactIdentity: Equatable, Sendable {
    let manifestArtifactSHA256: String
    let modelArtifactSHA256: String
    let modelArtifactByteCount: Int64

    func validate(against manifest: ChordInkModelArtifactManifest) throws {
        guard manifestArtifactSHA256 == manifest.manifestArtifactSHA256 else {
            throw ChordInkLearnedRuntimeContractError.loadedManifestDigestMismatch(
                expected: manifest.manifestArtifactSHA256,
                actual: manifestArtifactSHA256
            )
        }
        guard modelArtifactSHA256 == manifest.modelArtifactSHA256 else {
            throw ChordInkLearnedRuntimeContractError.loadedModelDigestMismatch(
                expected: manifest.modelArtifactSHA256,
                actual: modelArtifactSHA256
            )
        }
        guard modelArtifactByteCount == manifest.modelArtifactByteCount else {
            throw ChordInkLearnedRuntimeContractError.loadedModelByteCountMismatch(
                expected: manifest.modelArtifactByteCount,
                actual: modelArtifactByteCount
            )
        }
    }
}

struct ChordInkLearnedModelInput: Equatable, Sendable {
    let trajectory: ChordInkTrajectoryFeatureTensor
    let raster: ChordInkRasterFeaturePlane

    func validate(for manifest: ChordInkModelArtifactManifest) throws {
        guard trajectory.shape == manifest.trajectoryInput.shape else {
            throw ChordInkLearnedRuntimeContractError.trajectoryShapeMismatch(
                expected: manifest.trajectoryInput.shape,
                actual: trajectory.shape
            )
        }
        let actualRasterShape = [1, raster.height, raster.width, 1]
        guard actualRasterShape == manifest.rasterInput.shape else {
            throw ChordInkLearnedRuntimeContractError.rasterShapeMismatch(
                expected: manifest.rasterInput.shape,
                actual: actualRasterShape
            )
        }
        if let index = trajectory.values.firstIndex(where: { !$0.isFinite }) {
            throw ChordInkLearnedRuntimeContractError.nonFiniteTrajectoryValue(index: index)
        }
        for sample in 0..<ChordInkFeatureSchema.trajectorySampleCount {
            for channel in manifest.trajectoryInput.channels {
                let flatIndex = sample * ChordInkFeatureSchema.trajectoryChannelCount
                    + channel.index
                let value = trajectory.values[flatIndex]
                guard Self.value(Double(value), satisfies: channel.range) else {
                    throw ChordInkLearnedRuntimeContractError.trajectoryValueOutOfContract(
                        sample: sample,
                        channel: channel.index,
                        value: value
                    )
                }
            }
        }
        for (index, pixel) in raster.pixels.enumerated() {
            guard Self.value(Double(pixel), satisfies: manifest.rasterInput.range) else {
                throw ChordInkLearnedRuntimeContractError.rasterValueOutOfContract(
                    index: index,
                    value: pixel
                )
            }
        }
    }

    private static func value(
        _ value: Double,
        satisfies range: ChordInkValueRangeContract
    ) -> Bool {
        if range.finiteValuesRequired, !value.isFinite {
            return false
        }
        if let minimum = range.minimumInclusive, value < minimum {
            return false
        }
        if let maximum = range.maximumInclusive, value > maximum {
            return false
        }
        if let allowedValues = range.allowedDiscreteValues,
           !allowedValues.contains(value) {
            return false
        }
        return true
    }
}

/// Runtime boundary implemented by a platform-specific model adapter. The
/// semantic layer does not import CoreML and cannot silently substitute a
/// different manifest.
protocol ChordInkLearnedModelRuntime {
    var manifest: ChordInkModelArtifactManifest { get }
    var loadedArtifactIdentity: ChordInkLoadedModelArtifactIdentity { get }

    func predict(
        input: ChordInkLearnedModelInput
    ) throws -> ChordInkLearnedFactorOutput
}

struct ChordInkLearnedInferenceEngine {
    private let decoder = ChordInkCompositionalDecoder()

    func predict<Runtime: ChordInkLearnedModelRuntime>(
        input: ChordInkLearnedModelInput,
        runtime: Runtime,
        maximumCandidateCount: Int = 3
    ) throws -> ChordInkLearnedDecodeResult {
        try runtime.manifest.validate()
        try runtime.loadedArtifactIdentity.validate(against: runtime.manifest)
        try input.validate(for: runtime.manifest)
        let output = try runtime.predict(input: input)
        return try decoder.decode(output, maximumCandidateCount: maximumCandidateCount)
    }
}

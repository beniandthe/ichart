import Foundation

@main
struct ChordInkCoreMLCrossRuntimeGate {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw GateError.invalidArguments
        }
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let compiledModelURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let detachedManifestSHA256 = CommandLine.arguments[3]
        let runtime = try ChordInkCoreMLModelRuntime.load(
            manifestURL: manifestURL,
            detachedManifestSHA256: detachedManifestSHA256,
            compiledModelURL: compiledModelURL
        )

        var trajectory = Array(
            repeating: Float.zero,
            count: ChordInkFeatureSchema.trajectorySampleCount
                * ChordInkFeatureSchema.trajectoryChannelCount
        )
        trajectory[0] = 0.1
        trajectory[1] = -0.1
        trajectory[6] = 1
        trajectory[7] = 1
        trajectory[8] = 1
        trajectory[9] = 1
        var raster = Array(
            repeating: ChordInkFeatureSchema.rasterBackground,
            count: ChordInkFeatureSchema.rasterWidth * ChordInkFeatureSchema.rasterHeight
        )
        raster[
            (ChordInkFeatureSchema.rasterHeight / 2) * ChordInkFeatureSchema.rasterWidth
                + ChordInkFeatureSchema.rasterWidth / 2
        ] = ChordInkFeatureSchema.rasterForeground

        let input = ChordInkLearnedModelInput(
            trajectory: ChordInkTrajectoryFeatureTensor(values: trajectory),
            raster: ChordInkRasterFeaturePlane(pixels: raster)
        )
        let output = try runtime.predict(input: input)
        guard output.contractVersion == ChordInkLearnedOutputContract.version else {
            throw GateError.outputContractMismatch
        }
        let heads: [[Double]] = [
            Array(output.validity.values.values),
            Array(output.kind.values.values),
            Array(output.rootLetter.values.values),
            Array(output.rootAccidental.values.values),
            Array(output.quality.values.values),
            Array(output.extensionTone.values.values),
            Array(output.alterations.values.values),
            Array(output.slashPresence.values.values),
            Array(output.slashBassLetter.values.values),
            Array(output.slashBassAccidental.values.values)
        ]
        guard heads.count == runtime.manifest.outputHeads.count,
              heads.flatMap({ $0 }).allSatisfy(\.isFinite) else {
            throw GateError.invalidOutput
        }
        let decoded = try ChordInkCompositionalDecoder().decode(
            output,
            maximumCandidateCount: 3
        )
        let payload: [String: Any] = [
            "candidate_count": decoded.candidates.count,
            "compute_units": runtime.manifest.inferenceComputeUnits.rawValue,
            "head_count": heads.count,
            "model_byte_count": runtime.loadedArtifactIdentity.modelArtifactByteCount,
            "model_sha256": runtime.loadedArtifactIdentity.modelArtifactSHA256,
            "ok": true,
            "schema_version": "chord-ink-coreml-cross-runtime-gate-v1"
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw GateError.invalidOutput
        }
        print(text)
    }

    enum GateError: Error {
        case invalidArguments
        case invalidOutput
        case outputContractMismatch
    }
}

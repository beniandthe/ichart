import XCTest
@testable import iChart

final class ChordInkLearnedRuntimeTests: XCTestCase {
    private final class FakeRuntime: ChordInkLearnedModelRuntime {
        let manifest: ChordInkModelArtifactManifest
        let loadedArtifactIdentity: ChordInkLoadedModelArtifactIdentity
        let output: ChordInkLearnedFactorOutput
        private(set) var predictionCount = 0

        init(
            manifest: ChordInkModelArtifactManifest,
            loadedArtifactIdentity: ChordInkLoadedModelArtifactIdentity? = nil,
            output: ChordInkLearnedFactorOutput
        ) {
            self.manifest = manifest
            self.loadedArtifactIdentity = loadedArtifactIdentity
                ?? ChordInkLoadedModelArtifactIdentity(
                    manifestArtifactSHA256: manifest.manifestArtifactSHA256,
                    modelArtifactSHA256: manifest.modelArtifactSHA256,
                    modelArtifactByteCount: manifest.modelArtifactByteCount
                )
            self.output = output
        }

        func predict(input: ChordInkLearnedModelInput) throws -> ChordInkLearnedFactorOutput {
            predictionCount += 1
            return output
        }
    }

    func testFakeRuntimeCrossesValidatedBoundaryAndDecodes() throws {
        let runtime = FakeRuntime(
            manifest: ChordInkLearnedTestFactory.manifest(),
            output: ChordInkLearnedTestFactory.output(root: .g, extensionTone: .seven)
        )

        let result = try ChordInkLearnedInferenceEngine().predict(
            input: ChordInkLearnedTestFactory.modelInput(),
            runtime: runtime
        )

        XCTAssertEqual(runtime.predictionCount, 1)
        XCTAssertEqual(result.candidates.first?.notation.canonicalDisplay, "G7")
    }

    func testInvalidManifestPreventsRuntimeExecution() {
        let invalidManifest = ChordInkModelArtifactManifest(
            modelIdentifier: "test-model-v1",
            manifestArtifactSHA256: "not-a-digest",
            modelArtifactSHA256: ChordInkLearnedTestFactory.modelDigest,
            modelArtifactByteCount: 42
        )
        let runtime = FakeRuntime(
            manifest: invalidManifest,
            output: ChordInkLearnedTestFactory.output()
        )

        XCTAssertThrowsError(
            try ChordInkLearnedInferenceEngine().predict(
                input: ChordInkLearnedTestFactory.modelInput(),
                runtime: runtime
            )
        )
        XCTAssertEqual(runtime.predictionCount, 0)
    }

    func testNonFiniteFeaturePreventsRuntimeExecution() {
        let runtime = FakeRuntime(
            manifest: ChordInkLearnedTestFactory.manifest(),
            output: ChordInkLearnedTestFactory.output()
        )
        let count = ChordInkFeatureSchema.trajectorySampleCount
            * ChordInkFeatureSchema.trajectoryChannelCount
        var values = Array(repeating: Float.zero, count: count)
        values[17] = .nan

        XCTAssertThrowsError(
            try ChordInkLearnedInferenceEngine().predict(
                input: ChordInkLearnedTestFactory.modelInput(trajectoryValues: values),
                runtime: runtime
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedRuntimeContractError,
                .nonFiniteTrajectoryValue(index: 17)
            )
        }
        XCTAssertEqual(runtime.predictionCount, 0)
    }

    func testOutOfRangeTrajectoryChannelPreventsRuntimeExecution() {
        let runtime = FakeRuntime(
            manifest: ChordInkLearnedTestFactory.manifest(),
            output: ChordInkLearnedTestFactory.output()
        )
        let count = ChordInkFeatureSchema.trajectorySampleCount
            * ChordInkFeatureSchema.trajectoryChannelCount
        var values = Array(repeating: Float.zero, count: count)
        values[ChordInkFeatureSchema.TrajectoryChannel.x.rawValue] = 0.75

        XCTAssertThrowsError(
            try ChordInkLearnedInferenceEngine().predict(
                input: ChordInkLearnedTestFactory.modelInput(trajectoryValues: values),
                runtime: runtime
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedRuntimeContractError,
                .trajectoryValueOutOfContract(
                    sample: 0,
                    channel: ChordInkFeatureSchema.TrajectoryChannel.x.rawValue,
                    value: 0.75
                )
            )
        }
        XCTAssertEqual(runtime.predictionCount, 0)
    }

    func testNonBinaryRasterPreventsRuntimeExecution() {
        let runtime = FakeRuntime(
            manifest: ChordInkLearnedTestFactory.manifest(),
            output: ChordInkLearnedTestFactory.output()
        )
        let base = ChordInkLearnedTestFactory.modelInput()
        var pixels = base.raster.pixels
        pixels[7] = 127
        let input = ChordInkLearnedModelInput(
            trajectory: base.trajectory,
            raster: ChordInkRasterFeaturePlane(pixels: pixels)
        )

        XCTAssertThrowsError(
            try ChordInkLearnedInferenceEngine().predict(
                input: input,
                runtime: runtime
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedRuntimeContractError,
                .rasterValueOutOfContract(index: 7, value: 127)
            )
        }
        XCTAssertEqual(runtime.predictionCount, 0)
    }

    func testLoadedModelDigestMismatchPreventsRuntimeExecution() {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let runtime = FakeRuntime(
            manifest: manifest,
            loadedArtifactIdentity: ChordInkLoadedModelArtifactIdentity(
                manifestArtifactSHA256: manifest.manifestArtifactSHA256,
                modelArtifactSHA256: String(repeating: "f", count: 64),
                modelArtifactByteCount: manifest.modelArtifactByteCount
            ),
            output: ChordInkLearnedTestFactory.output()
        )

        XCTAssertThrowsError(
            try ChordInkLearnedInferenceEngine().predict(
                input: ChordInkLearnedTestFactory.modelInput(),
                runtime: runtime
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedRuntimeContractError,
                .loadedModelDigestMismatch(
                    expected: manifest.modelArtifactSHA256,
                    actual: String(repeating: "f", count: 64)
                )
            )
        }
        XCTAssertEqual(runtime.predictionCount, 0)
    }

    func testRuntimeOutputWithWrongVersionFailsAfterSingleInference() {
        let runtime = FakeRuntime(
            manifest: ChordInkLearnedTestFactory.manifest(),
            output: ChordInkLearnedTestFactory.output(contractVersion: "future-output")
        )

        XCTAssertThrowsError(
            try ChordInkLearnedInferenceEngine().predict(
                input: ChordInkLearnedTestFactory.modelInput(),
                runtime: runtime
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedDecodeError,
                .outputContractVersionMismatch(
                    expected: ChordInkLearnedOutputContract.version,
                    actual: "future-output"
                )
            )
        }
        XCTAssertEqual(runtime.predictionCount, 1)
    }
}

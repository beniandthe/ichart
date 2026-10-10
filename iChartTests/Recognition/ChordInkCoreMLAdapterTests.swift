import CoreML
import CoreVideo
import XCTest
@testable import iChart

final class ChordInkCoreMLAdapterTests: XCTestCase {
    func testRuntimeUsesTheSameCPUOnlyPathAsExportParityAndCalibration() {
        XCTAssertEqual(ChordInkCoreMLModelRuntime.requiredComputeUnits, .cpuOnly)
    }

    func testExactModelDescriptionContractPassesPreflight() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()

        XCTAssertNoThrow(
            try ChordInkCoreMLModelRuntime.validateModelDescription(
                exactDescription(for: manifest),
                against: manifest
            )
        )
    }

    func testDescriptionRejectsMissingAndAdditionalInputNames() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let exact = exactDescription(for: manifest)
        let actualInputs = [
            manifest.trajectoryInput.name: exact.inputs[manifest.trajectoryInput.name]!,
            "unexpected": exact.inputs[manifest.rasterInput.name]!
        ]

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.validateModelDescription(
                ChordInkCoreMLModelDescriptionSnapshot(
                    inputs: actualInputs,
                    outputs: exact.outputs
                ),
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .inputNamesMismatch(
                    expected: ["raster", "trajectory"],
                    actual: ["trajectory", "unexpected"]
                )
            )
        }
    }

    func testDescriptionRejectsTrajectoryShapeMismatch() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let exact = exactDescription(for: manifest)
        var inputs = exact.inputs
        inputs[manifest.trajectoryInput.name] = .multiArray(
            shape: [1, 255, 10],
            dataType: .float32,
            isOptional: false
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.validateModelDescription(
                ChordInkCoreMLModelDescriptionSnapshot(
                    inputs: inputs,
                    outputs: exact.outputs
                ),
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .featureShapeMismatch(
                    name: "trajectory",
                    expected: [1, 256, 10],
                    actual: [1, 255, 10]
                )
            )
        }
    }

    func testDescriptionRejectsOutputDataTypeMismatch() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let exact = exactDescription(for: manifest)
        let head = try XCTUnwrap(manifest.outputHeads.first)
        var outputs = exact.outputs
        outputs[head.name] = .multiArray(
            shape: head.shape,
            dataType: .float16,
            isOptional: false
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.validateModelDescription(
                ChordInkCoreMLModelDescriptionSnapshot(
                    inputs: exact.inputs,
                    outputs: outputs
                ),
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .featureDataTypeMismatch(
                    name: head.name,
                    expected: .float32,
                    actual: .float16
                )
            )
        }
    }

    func testDescriptionRejectsUndeclaredOutputShape() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let exact = exactDescription(for: manifest)
        let head = try XCTUnwrap(manifest.outputHeads.first)
        var outputs = exact.outputs
        outputs[head.name] = .multiArray(
            shape: [],
            dataType: .float32,
            isOptional: false
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.validateModelDescription(
                ChordInkCoreMLModelDescriptionSnapshot(
                    inputs: exact.inputs,
                    outputs: outputs
                ),
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .featureShapeMismatch(
                    name: head.name,
                    expected: head.shape,
                    actual: []
                )
            )
        }
    }

    func testDescriptionRejectsOptionalFeature() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let exact = exactDescription(for: manifest)
        var inputs = exact.inputs
        inputs[manifest.trajectoryInput.name] = .multiArray(
            shape: manifest.trajectoryInput.shape,
            dataType: .float32,
            isOptional: true
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.validateModelDescription(
                ChordInkCoreMLModelDescriptionSnapshot(
                    inputs: inputs,
                    outputs: exact.outputs
                ),
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .featureOptionalityMismatch(
                    name: "trajectory",
                    expected: false,
                    actual: true
                )
            )
        }
    }

    func testDescriptionRejectsRasterPixelFormatMismatch() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let exact = exactDescription(for: manifest)
        var inputs = exact.inputs
        inputs[manifest.rasterInput.name] = .image(
            width: ChordInkFeatureSchema.rasterWidth,
            height: ChordInkFeatureSchema.rasterHeight,
            pixelFormat: kCVPixelFormatType_32BGRA,
            isOptional: false
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.validateModelDescription(
                ChordInkCoreMLModelDescriptionSnapshot(
                    inputs: inputs,
                    outputs: exact.outputs
                ),
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .imagePixelFormatMismatch(
                    name: "raster",
                    expected: kCVPixelFormatType_OneComponent8,
                    actual: kCVPixelFormatType_32BGRA
                )
            )
        }
    }

    func testDescriptionRejectsFeatureCategoryMismatch() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let exact = exactDescription(for: manifest)
        var inputs = exact.inputs
        inputs[manifest.rasterInput.name] = .multiArray(
            shape: manifest.rasterInput.shape,
            dataType: .float32,
            isOptional: false
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.validateModelDescription(
                ChordInkCoreMLModelDescriptionSnapshot(
                    inputs: inputs,
                    outputs: exact.outputs
                ),
                against: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .featureTypeMismatch(
                    name: "raster",
                    expected: .image,
                    actual: .multiArray
                )
            )
        }
    }

    func testInputProviderPreservesTrajectoryAndBinaryRasterBytes() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let trajectoryCount = ChordInkFeatureSchema.trajectorySampleCount
            * ChordInkFeatureSchema.trajectoryChannelCount
        var trajectoryValues = Array(repeating: Float.zero, count: trajectoryCount)
        trajectoryValues[0] = 0.25
        trajectoryValues[1] = -0.25
        trajectoryValues[7] = 1
        trajectoryValues[9] = 1
        var pixels = Array(
            repeating: ChordInkFeatureSchema.rasterBackground,
            count: ChordInkFeatureSchema.rasterWidth * ChordInkFeatureSchema.rasterHeight
        )
        pixels[0] = ChordInkFeatureSchema.rasterForeground
        pixels[ChordInkFeatureSchema.rasterWidth + 3] = ChordInkFeatureSchema.rasterForeground
        let input = ChordInkLearnedModelInput(
            trajectory: ChordInkTrajectoryFeatureTensor(values: trajectoryValues),
            raster: ChordInkRasterFeaturePlane(pixels: pixels)
        )

        let provider = try ChordInkCoreMLModelRuntime.makeInputProvider(
            input: input,
            manifest: manifest
        )
        let trajectory = try XCTUnwrap(
            provider.featureValue(for: manifest.trajectoryInput.name)?.multiArrayValue
        )
        XCTAssertEqual(trajectory.shape.map(\.intValue), manifest.trajectoryInput.shape)
        XCTAssertEqual(trajectory.dataType, .float32)
        XCTAssertEqual(trajectory[0].floatValue, 0.25)
        XCTAssertEqual(trajectory[1].floatValue, -0.25)
        XCTAssertEqual(trajectory[7].floatValue, 1)

        let pixelBuffer = try XCTUnwrap(
            provider.featureValue(for: manifest.rasterInput.name)?.imageBufferValue
        )
        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), ChordInkFeatureSchema.rasterWidth)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), ChordInkFeatureSchema.rasterHeight)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_OneComponent8)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        XCTAssertEqual(baseAddress[0], ChordInkFeatureSchema.rasterForeground)
        XCTAssertEqual(
            baseAddress[bytesPerRow + 3],
            ChordInkFeatureSchema.rasterForeground
        )
        XCTAssertEqual(baseAddress[4], ChordInkFeatureSchema.rasterBackground)
    }

    func testInputProviderRejectsNonBinaryRasterBeforeCoreML() {
        let manifest = ChordInkLearnedTestFactory.manifest()
        var pixels = Array(
            repeating: ChordInkFeatureSchema.rasterBackground,
            count: ChordInkFeatureSchema.rasterWidth * ChordInkFeatureSchema.rasterHeight
        )
        pixels[9] = 128
        let input = ChordInkLearnedModelInput(
            trajectory: ChordInkLearnedTestFactory.modelInput().trajectory,
            raster: ChordInkRasterFeaturePlane(pixels: pixels)
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.makeInputProvider(
                input: input,
                manifest: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedRuntimeContractError,
                .rasterValueOutOfContract(index: 9, value: 128)
            )
        }
    }

    func testOutputProviderMapsEveryHeadInManifestLabelOrder() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let provider = try outputProvider(manifest: manifest)

        let output = try ChordInkCoreMLModelRuntime.factorOutput(
            from: provider,
            manifest: manifest
        )

        XCTAssertEqual(output.validity.values[.noRead], 0)
        XCTAssertEqual(output.validity.values[.notation], 1)
        XCTAssertEqual(output.rootLetter.values[.g], 6)
        XCTAssertEqual(output.rootAccidental.values[.flat], 2)
        XCTAssertEqual(output.quality.values[.minor], 1)
        XCTAssertEqual(output.extensionTone.values[.sixNine], 8)
        XCTAssertEqual(output.alterations.values[.flatThirteen], 6)
        XCTAssertEqual(output.slashPresence.values[.present], 1)
        XCTAssertEqual(output.slashBassLetter.values[.b], 1)
        XCTAssertEqual(output.slashBassAccidental.values[.sharp], 1)
    }

    func testOutputProviderRejectsNonFiniteLogit() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let head = try XCTUnwrap(manifest.outputHeads.first)
        let provider = try outputProvider(
            manifest: manifest,
            overrides: [head.name: [.nan, 0]]
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.factorOutput(
                from: provider,
                manifest: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .nonFiniteOutput(name: head.name, index: 0)
            )
        }
    }

    func testOutputProviderRejectsWrongNumericType() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()
        let head = try XCTUnwrap(manifest.outputHeads.first)
        let provider = try outputProvider(
            manifest: manifest,
            dataTypeOverrides: [head.name: .double]
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.factorOutput(
                from: provider,
                manifest: manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .outputDataTypeMismatch(
                    name: head.name,
                    expected: .float32,
                    actual: .float64
                )
            )
        }
    }

    func testCompiledModelFingerprintBindsPathsAndBytesDeterministically() throws {
        let directory = try makeTemporaryCompiledModelDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("model.mil"))
        try Data([4, 5]).write(to: nested.appendingPathComponent("weight.bin"))

        let first = try ChordInkCoreMLModelRuntime.fingerprintCompiledModel(at: directory)
        let second = try ChordInkCoreMLModelRuntime.fingerprintCompiledModel(at: directory)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.byteCount, 5)
        XCTAssertEqual(
            first.sha256,
            "3bae040a19029d3dd9595e36ac9b96f1c427005f668e050122bae5946caf3a21"
        )

        try Data([4, 6]).write(to: nested.appendingPathComponent("weight.bin"))
        let changed = try ChordInkCoreMLModelRuntime.fingerprintCompiledModel(at: directory)
        XCTAssertEqual(changed.byteCount, first.byteCount)
        XCTAssertNotEqual(changed.sha256, first.sha256)
    }

    func testVerifiedIdentityRejectsDetachedManifestAndCompiledModelMismatch() throws {
        let directory = try makeTemporaryCompiledModelDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("model.mil"))
        let fingerprint = try ChordInkCoreMLModelRuntime.fingerprintCompiledModel(at: directory)
        let manifest = ChordInkModelArtifactManifest(
            modelIdentifier: "test-coreml-model",
            manifestArtifactSHA256: ChordInkLearnedTestFactory.manifestDigest,
            modelArtifactSHA256: fingerprint.sha256,
            modelArtifactByteCount: fingerprint.byteCount,
            trainingProvenance: ChordInkLearnedTestFactory.trainingProvenance()
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.verifiedArtifactIdentity(
                manifest: manifest,
                detachedManifestSHA256: String(repeating: "f", count: 64),
                compiledModelURL: directory
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedRuntimeContractError,
                .loadedManifestDigestMismatch(
                    expected: ChordInkLearnedTestFactory.manifestDigest,
                    actual: String(repeating: "f", count: 64)
                )
            )
        }

        try Data([9, 2, 3]).write(to: directory.appendingPathComponent("model.mil"))
        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.verifiedArtifactIdentity(
                manifest: manifest,
                detachedManifestSHA256: ChordInkLearnedTestFactory.manifestDigest,
                compiledModelURL: directory
            )
        ) { error in
            guard case .loadedModelDigestMismatch =
                    error as? ChordInkLearnedRuntimeContractError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testVerifiedIdentityRejectsCompiledModelByteCountMismatch() throws {
        let directory = try makeTemporaryCompiledModelDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("model.mil"))
        let fingerprint = try ChordInkCoreMLModelRuntime.fingerprintCompiledModel(at: directory)
        let manifest = ChordInkModelArtifactManifest(
            modelIdentifier: "test-coreml-model",
            manifestArtifactSHA256: ChordInkLearnedTestFactory.manifestDigest,
            modelArtifactSHA256: fingerprint.sha256,
            modelArtifactByteCount: fingerprint.byteCount + 1,
            trainingProvenance: ChordInkLearnedTestFactory.trainingProvenance()
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.verifiedArtifactIdentity(
                manifest: manifest,
                detachedManifestSHA256: ChordInkLearnedTestFactory.manifestDigest,
                compiledModelURL: directory
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedRuntimeContractError,
                .loadedModelByteCountMismatch(
                    expected: fingerprint.byteCount + 1,
                    actual: fingerprint.byteCount
                )
            )
        }
    }

    func testCompiledModelFingerprintRejectsSymbolicLinks() throws {
        let directory = try makeTemporaryCompiledModelDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.bin")
        try Data([1]).write(to: target)
        let link = directory.appendingPathComponent("linked.bin")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.fingerprintCompiledModel(at: directory)
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .compiledModelArtifactContainsSymbolicLink(path: "linked.bin")
            )
        }
    }

    func testBundleLoaderFailsClosedWhenResourcesAreMissing() {
        let randomName = "missing-\(UUID().uuidString)"

        XCTAssertThrowsError(
            try ChordInkCoreMLModelRuntime.load(
                resources: .init(
                    manifestName: randomName,
                    compiledModelName: randomName
                ),
                detachedManifestSHA256: ChordInkLearnedTestFactory.manifestDigest,
                bundle: Bundle(for: Self.self)
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordInkCoreMLAdapterError,
                .missingResource(name: randomName, extension: "json")
            )
        }
    }
}

private extension ChordInkCoreMLAdapterTests {
    func exactDescription(
        for manifest: ChordInkModelArtifactManifest
    ) -> ChordInkCoreMLModelDescriptionSnapshot {
        let inputs: [String: ChordInkCoreMLFeatureDescriptionSnapshot] = [
            manifest.trajectoryInput.name: .multiArray(
                shape: manifest.trajectoryInput.shape,
                dataType: .float32,
                isOptional: false
            ),
            manifest.rasterInput.name: .image(
                width: ChordInkFeatureSchema.rasterWidth,
                height: ChordInkFeatureSchema.rasterHeight,
                pixelFormat: kCVPixelFormatType_OneComponent8,
                isOptional: false
            )
        ]
        let outputs = Dictionary(
            uniqueKeysWithValues: manifest.outputHeads.map { head in
                (
                    head.name,
                    ChordInkCoreMLFeatureDescriptionSnapshot.multiArray(
                        shape: head.shape,
                        dataType: .float32,
                        isOptional: false
                    )
                )
            }
        )
        return ChordInkCoreMLModelDescriptionSnapshot(
            inputs: inputs,
            outputs: outputs
        )
    }

    func outputProvider(
        manifest: ChordInkModelArtifactManifest,
        overrides: [String: [Double]] = [:],
        dataTypeOverrides: [String: MLMultiArrayDataType] = [:]
    ) throws -> MLDictionaryFeatureProvider {
        var features: [String: MLFeatureValue] = [:]
        for head in manifest.outputHeads {
            let dataType = dataTypeOverrides[head.name] ?? .float32
            let array = try MLMultiArray(
                shape: head.shape.map { NSNumber(value: $0) },
                dataType: dataType
            )
            let values = overrides[head.name]
                ?? head.labels.indices.map(Double.init)
            XCTAssertEqual(values.count, array.count)
            for (index, value) in values.enumerated() {
                array[index] = NSNumber(value: value)
            }
            features[head.name] = MLFeatureValue(multiArray: array)
        }
        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    func makeTemporaryCompiledModelDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathExtension("mlmodelc")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

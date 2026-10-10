import XCTest
@testable import iChart

final class ChordInkModelArtifactContractTests: XCTestCase {
    func testExactManifestValidatesAndRoundTrips() throws {
        let manifest = ChordInkLearnedTestFactory.manifest()

        XCTAssertNoThrow(try manifest.validate())
        XCTAssertEqual(manifest.manifestContractVersion, "chord-ink-model-manifest-v4")
        XCTAssertEqual(manifest.inferenceComputeUnits, .cpuOnly)
        XCTAssertTrue(manifest.exportParity.isValid)
        XCTAssertEqual(
            manifest.trainingProvenance.checkpointContractVersion,
            "chord-ink-training-checkpoint-v6"
        )
        XCTAssertEqual(
            manifest.trainingProvenance.modelArchitectureID,
            .dualViewV2LayoutPreserving
        )
        XCTAssertEqual(
            manifest.trainingProvenance.developmentSelectionAuthority,
            .unselectedDevelopmentTraining
        )
        XCTAssertNil(
            manifest.trainingProvenance.developmentSelectionReportSHA256
        )
        let data = try JSONEncoder().encode(manifest)
        XCTAssertEqual(try JSONDecoder().decode(ChordInkModelArtifactManifest.self, from: data), manifest)

        XCTAssertEqual(manifest.trajectoryInput.numericType, .float32)
        XCTAssertEqual(manifest.trajectoryInput.layout, .batchSampleChannel)
        XCTAssertEqual(manifest.trajectoryInput.scaling, .trajectoryFeatureV1Channelwise)
        XCTAssertEqual(manifest.trajectoryInput.valueSemantics, .trajectoryFeatureV1)
        XCTAssertEqual(manifest.trajectoryInput.channels.count, 10)
        XCTAssertEqual(
            manifest.trajectoryInput.channels[ChordInkFeatureSchema.TrajectoryChannel.x.rawValue].range,
            ChordInkValueRangeContract(
                minimumInclusive: -0.5,
                maximumInclusive: 0.5,
                allowedDiscreteValues: nil,
                finiteValuesRequired: true
            )
        )
        XCTAssertEqual(manifest.rasterInput.numericType, .uint8)
        XCTAssertEqual(manifest.rasterInput.layout, .batchHeightWidthChannel)
        XCTAssertEqual(manifest.rasterInput.scaling, .identity)
        XCTAssertEqual(manifest.rasterInput.valueSemantics, .binaryInkMask)
        XCTAssertEqual(manifest.rasterInput.range.allowedDiscreteValues, [0, 255])
        XCTAssertTrue(manifest.outputHeads.allSatisfy {
            $0.numericType == .float32
                && $0.layout == .batchClass
                && $0.scaling == .identity
                && $0.valueSemantics == .rawLogit
                && $0.range.minimumInclusive == nil
                && $0.range.maximumInclusive == nil
                && $0.range.finiteValuesRequired
        })

        let alterationHead = try XCTUnwrap(
            manifest.outputHeads.first {
                $0.name == ChordInkLearnedOutputContract.alterationHeadName
            }
        )
        XCTAssertEqual(alterationHead.shape, [1, 7])
        XCTAssertEqual(
            alterationHead.labels,
            ChordNotation.Alteration.allCases.map(\.rawValue)
        )
    }

    func testManifestRejectsReorderedLabelsEvenWhenShapeMatches() throws {
        var heads = ChordInkModelArtifactManifest.expectedOutputHeads
        let validity = try XCTUnwrap(heads.first)
        heads[0] = ChordInkOutputHeadContract(
            name: validity.name,
            shape: validity.shape,
            labels: validity.labels.reversed(),
            numericType: validity.numericType,
            layout: validity.layout,
            scaling: validity.scaling,
            valueSemantics: validity.valueSemantics,
            range: validity.range
        )
        let manifest = ChordInkLearnedTestFactory.manifest(outputHeads: heads)

        XCTAssertThrowsError(try manifest.validate()) { error in
            guard case .outputHeadsMismatch = error as? ChordInkModelManifestValidationError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testBoundDevelopmentSelectionDigestValidatesAndRoundTrips() throws {
        let manifest = ChordInkLearnedTestFactory.manifest(
            trainingProvenance: ChordInkLearnedTestFactory.trainingProvenance(
                developmentSelectionAuthority: .boundDevelopmentWriterComparisonV4,
                developmentSelectionReportSHA256: String(repeating: "2", count: 64)
            )
        )

        XCTAssertNoThrow(try manifest.validate())
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(
            ChordInkModelArtifactManifest.self,
            from: encoded
        )
        XCTAssertEqual(
            decoded.trainingProvenance.developmentSelectionReportSHA256,
            String(repeating: "2", count: 64)
        )
    }

    func testManifestRejectsInputNumericTypeLayoutOrScalingDrift() {
        let expected = ChordInkModelArtifactManifest.expectedTrajectoryInput
        let drifted = ChordInkTensorContract(
            name: expected.name,
            shape: expected.shape,
            numericType: .uint8,
            layout: .batchHeightWidthChannel,
            scaling: .identity,
            valueSemantics: .binaryInkMask,
            range: expected.range,
            channels: expected.channels
        )
        let manifest = ChordInkModelArtifactManifest(
            modelIdentifier: "test-model-v1",
            manifestArtifactSHA256: ChordInkLearnedTestFactory.manifestDigest,
            modelArtifactSHA256: ChordInkLearnedTestFactory.modelDigest,
            modelArtifactByteCount: 42,
            trainingProvenance: ChordInkLearnedTestFactory.trainingProvenance(),
            trajectoryInput: drifted
        )

        XCTAssertThrowsError(try manifest.validate()) { error in
            guard case .trajectoryContractMismatch = error as? ChordInkModelManifestValidationError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testManifestRejectsOutputNumericRangeDrift() throws {
        var heads = ChordInkModelArtifactManifest.expectedOutputHeads
        let validity = try XCTUnwrap(heads.first)
        heads[0] = ChordInkOutputHeadContract(
            name: validity.name,
            shape: validity.shape,
            labels: validity.labels,
            numericType: .float32,
            layout: .batchClass,
            scaling: .identity,
            valueSemantics: .rawLogit,
            range: ChordInkValueRangeContract(
                minimumInclusive: 0,
                maximumInclusive: 1,
                allowedDiscreteValues: nil,
                finiteValuesRequired: true
            )
        )

        XCTAssertThrowsError(
            try ChordInkLearnedTestFactory.manifest(outputHeads: heads).validate()
        ) { error in
            guard case .outputHeadsMismatch = error as? ChordInkModelManifestValidationError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testManifestRejectsNonASCIIDigest() {
        let unicodeDigits = String(repeating: "١", count: 64)
        let manifest = ChordInkModelArtifactManifest(
            modelIdentifier: "test-model-v1",
            manifestArtifactSHA256: unicodeDigits,
            modelArtifactSHA256: ChordInkLearnedTestFactory.modelDigest,
            modelArtifactByteCount: 1,
            trainingProvenance: ChordInkLearnedTestFactory.trainingProvenance()
        )

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? ChordInkModelManifestValidationError,
                .invalidManifestDigest
            )
        }
    }

    func testManifestRejectsUnverifiedCoreMLParityEvidence() {
        let manifest = ChordInkModelArtifactManifest(
            modelIdentifier: "test-model-v1",
            manifestArtifactSHA256: ChordInkLearnedTestFactory.manifestDigest,
            modelArtifactSHA256: ChordInkLearnedTestFactory.modelDigest,
            modelArtifactByteCount: 1,
            trainingProvenance: ChordInkLearnedTestFactory.trainingProvenance(),
            exportParity: ChordInkCoreMLExportParityEvidence(
                maximumAbsoluteError: 0.000_100_1
            )
        )

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? ChordInkModelManifestValidationError,
                .invalidExportParityEvidence
            )
        }
    }

    func testManifestRejectsInvalidTrainingProvenance() {
        let invalidCheckpointDigest = ChordInkTrainingProvenance(
            checkpointContractVersion: ChordInkTrainingProvenance.checkpointContractVersion,
            checkpointArtifactSHA256: "not-a-digest",
            checkpointArtifactByteCount: 1,
            modelArchitectureID: .dualViewV2LayoutPreserving,
            developmentRecordsSHA256: ChordInkLearnedTestFactory.developmentRecordsDigest,
            developmentSampleCount: 2,
            developmentWriterCount: 1,
            developmentSelectionAuthority: .unselectedDevelopmentTraining,
            developmentSelectionReportSHA256: nil
        )
        XCTAssertThrowsError(
            try ChordInkLearnedTestFactory.manifest(
                trainingProvenance: invalidCheckpointDigest
            ).validate()
        ) { error in
            XCTAssertEqual(
                error as? ChordInkModelManifestValidationError,
                .invalidCheckpointDigest
            )
        }

        let impossibleWriterCount = ChordInkTrainingProvenance(
            checkpointContractVersion: ChordInkTrainingProvenance.checkpointContractVersion,
            checkpointArtifactSHA256: ChordInkLearnedTestFactory.checkpointDigest,
            checkpointArtifactByteCount: 1,
            modelArchitectureID: .dualViewV2LayoutPreserving,
            developmentRecordsSHA256: ChordInkLearnedTestFactory.developmentRecordsDigest,
            developmentSampleCount: 1,
            developmentWriterCount: 2,
            developmentSelectionAuthority: .unselectedDevelopmentTraining,
            developmentSelectionReportSHA256: nil
        )
        XCTAssertThrowsError(
            try ChordInkLearnedTestFactory.manifest(
                trainingProvenance: impossibleWriterCount
            ).validate()
        ) { error in
            XCTAssertEqual(
                error as? ChordInkModelManifestValidationError,
                .invalidDevelopmentWriterCount
            )
        }

        let missingBoundSelectionDigest = ChordInkTrainingProvenance(
            checkpointContractVersion: ChordInkTrainingProvenance.checkpointContractVersion,
            checkpointArtifactSHA256: ChordInkLearnedTestFactory.checkpointDigest,
            checkpointArtifactByteCount: 1,
            modelArchitectureID: .dualViewV2LayoutPreserving,
            developmentRecordsSHA256: ChordInkLearnedTestFactory.developmentRecordsDigest,
            developmentSampleCount: 2,
            developmentWriterCount: 1,
            developmentSelectionAuthority: .boundDevelopmentWriterComparisonV4,
            developmentSelectionReportSHA256: nil
        )
        XCTAssertThrowsError(
            try ChordInkLearnedTestFactory.manifest(
                trainingProvenance: missingBoundSelectionDigest
            ).validate()
        ) { error in
            XCTAssertEqual(
                error as? ChordInkModelManifestValidationError,
                .invalidDevelopmentSelectionDigest
            )
        }
    }

    func testMissingCalibrationIsExplicitlyUnavailable() {
        XCTAssertEqual(
            ChordInkCalibrationResolution.resolve(
                artifact: nil,
                manifest: ChordInkLearnedTestFactory.manifest()
            ),
            .unavailable(.missingArtifact)
        )
    }

    func testCalibrationNotIndependentlyFittedFailsClosed() {
        XCTAssertEqual(
            ChordInkCalibrationResolution.resolve(
                artifact: ChordInkLearnedTestFactory.calibration(independentlyFitted: false),
                manifest: ChordInkLearnedTestFactory.manifest()
            ),
            .unavailable(.invalidArtifact)
        )
    }

    func testWriterOverlappingCalibrationFailsClosed() {
        XCTAssertEqual(
            ChordInkCalibrationResolution.resolve(
                artifact: ChordInkLearnedTestFactory.calibration(writerDisjoint: false),
                manifest: ChordInkLearnedTestFactory.manifest()
            ),
            .unavailable(.invalidArtifact)
        )
    }

    func testBoundIndependentCalibrationValidatesWithoutEmbeddingTrustThreshold() {
        let artifact = ChordInkLearnedTestFactory.calibration()
        let resolution = ChordInkCalibrationResolution.resolve(
            artifact: artifact,
            manifest: ChordInkLearnedTestFactory.manifest()
        )

        guard case .validated(let validated) = resolution else {
            return XCTFail("Expected validated calibration, got \(resolution)")
        }
        XCTAssertEqual(validated.artifact, artifact)
    }
}

import Foundation
@testable import iChart

enum ChordInkLearnedTestFactory {
    static let manifestDigest = String(repeating: "a", count: 64)
    static let modelDigest = String(repeating: "b", count: 64)
    static let calibrationDigest = String(repeating: "c", count: 64)
    static let fitReceiptDigest = String(repeating: "d", count: 64)
    static let gateReceiptDigest = String(repeating: "e", count: 64)
    static let checkpointDigest = String(repeating: "f", count: 64)
    static let developmentRecordsDigest = String(repeating: "1", count: 64)
    static let developmentSelectionReportDigest = String(repeating: "2", count: 64)

    static func trainingProvenance(
        architecture: ChordInkModelArchitectureID = .dualViewV2LayoutPreserving,
        developmentSelectionAuthority: ChordInkDevelopmentSelectionAuthority = .unselectedDevelopmentTraining,
        developmentSelectionReportSHA256: String? = nil
    ) -> ChordInkTrainingProvenance {
        ChordInkTrainingProvenance(
            checkpointContractVersion: ChordInkTrainingProvenance.checkpointContractVersion,
            checkpointArtifactSHA256: checkpointDigest,
            checkpointArtifactByteCount: 100,
            modelArchitectureID: architecture,
            developmentRecordsSHA256: developmentRecordsDigest,
            developmentSampleCount: 24,
            developmentWriterCount: 8,
            developmentSelectionAuthority: developmentSelectionAuthority,
            developmentSelectionReportSHA256: developmentSelectionReportSHA256
        )
    }

    static func manifest(
        outputHeads: [ChordInkOutputHeadContract] = ChordInkModelArtifactManifest.expectedOutputHeads,
        modelDigest: String = modelDigest,
        trainingProvenance: ChordInkTrainingProvenance = ChordInkLearnedTestFactory.trainingProvenance()
    ) -> ChordInkModelArtifactManifest {
        ChordInkModelArtifactManifest(
            modelIdentifier: "test-model-v1",
            manifestArtifactSHA256: manifestDigest,
            modelArtifactSHA256: modelDigest,
            modelArtifactByteCount: 42,
            trainingProvenance: trainingProvenance,
            outputHeads: outputHeads
        )
    }

    static func developmentSelectedManifest() -> ChordInkModelArtifactManifest {
        manifest(
            trainingProvenance: trainingProvenance(
                developmentSelectionAuthority: .boundDevelopmentWriterComparisonV4,
                developmentSelectionReportSHA256: developmentSelectionReportDigest
            )
        )
    }

    static func calibration(
        independentlyFitted: Bool = true,
        writerDisjoint: Bool = true,
        modelDigest: String = modelDigest
    ) -> ChordInkCalibrationArtifact {
        ChordInkCalibrationArtifact(
            calibrationArtifactSHA256: calibrationDigest,
            manifestArtifactSHA256: manifestDigest,
            modelArtifactSHA256: modelDigest,
            temperature: 1.25,
            wasIndependentlyFitted: independentlyFitted,
            usedWriterDisjointData: writerDisjoint,
            fitDatasetIdentifier: "writer-disjoint-calibration-v1",
            independentFitReceiptSHA256: fitReceiptDigest
        )
    }

    static func receipt(
        passed: Bool = true,
        writerDisjoint: Bool = true,
        sealedBeforeEvaluation: Bool = true,
        modelDigest: String = modelDigest
    ) -> ChordInkSealedGateReceipt {
        ChordInkSealedGateReceipt(
            receiptArtifactSHA256: gateReceiptDigest,
            manifestArtifactSHA256: manifestDigest,
            modelArtifactSHA256: modelDigest,
            calibrationArtifactSHA256: calibrationDigest,
            evaluationProtocolIdentifier: "predeclared-writer-independent-v1",
            sealedDatasetIdentifier: "sealed-evaluation-v1",
            usedWriterDisjointEvaluation: writerDisjoint,
            datasetWasSealedBeforeEvaluation: sealedBeforeEvaluation,
            passedAllPredeclaredGates: passed
        )
    }

    static func logits<Label>(
        preferred: Label,
        high: Double = 8,
        low: Double = -8
    ) -> ChordInkFactorLogits<Label>
    where Label: CaseIterable & Hashable & Sendable {
        ChordInkFactorLogits(
            Dictionary(uniqueKeysWithValues: Label.allCases.map { label in
                (label, label == preferred ? high : low)
            })
        )
    }

    static func tiedLogits<Label>(
        _ type: Label.Type
    ) -> ChordInkFactorLogits<Label>
    where Label: CaseIterable & Hashable & Sendable {
        ChordInkFactorLogits(
            Dictionary(uniqueKeysWithValues: Label.allCases.map { ($0, 0) })
        )
    }

    static func alterationLogits(
        selected: Set<ChordNotation.Alteration>,
        high: Double = 8,
        low: Double = -8
    ) -> ChordInkFactorLogits<ChordNotation.Alteration> {
        ChordInkFactorLogits(
            Dictionary(uniqueKeysWithValues: ChordNotation.Alteration.allCases.map { alteration in
                (alteration, selected.contains(alteration) ? high : low)
            })
        )
    }

    static func output(
        root: ChordNotation.Letter = .c,
        rootAccidental: ChordInkAccidentalFactorLabel = .natural,
        quality: ChordNotation.Form = .plain,
        extensionTone: ChordInkExtensionFactorLabel = .none,
        alterations: [ChordNotation.Alteration] = [],
        slashBassLetter: ChordNotation.Letter = .c,
        slashBassAccidental: ChordInkAccidentalFactorLabel = .natural,
        hasSlash: Bool = false,
        validity: ChordInkValidityFactorLabel = .notation,
        kind: ChordInkKindFactorLabel = .rooted,
        contractVersion: String = ChordInkLearnedOutputContract.version
    ) -> ChordInkLearnedFactorOutput {
        return ChordInkLearnedFactorOutput(
            contractVersion: contractVersion,
            validity: logits(preferred: validity),
            kind: logits(preferred: kind),
            rootLetter: logits(preferred: root),
            rootAccidental: logits(preferred: rootAccidental),
            quality: logits(preferred: quality),
            extensionTone: logits(preferred: extensionTone),
            alterations: alterationLogits(selected: Set(alterations)),
            slashPresence: logits(preferred: hasSlash ? .present : .none),
            slashBassLetter: logits(preferred: slashBassLetter),
            slashBassAccidental: logits(preferred: slashBassAccidental)
        )
    }

    static func modelInput(
        trajectoryValues: [Float]? = nil
    ) -> ChordInkLearnedModelInput {
        let trajectoryCount = ChordInkFeatureSchema.trajectorySampleCount
            * ChordInkFeatureSchema.trajectoryChannelCount
        return ChordInkLearnedModelInput(
            trajectory: ChordInkTrajectoryFeatureTensor(
                values: trajectoryValues ?? Array(repeating: 0, count: trajectoryCount)
            ),
            raster: ChordInkRasterFeaturePlane(
                pixels: Array(
                    repeating: ChordInkFeatureSchema.rasterBackground,
                    count: ChordInkFeatureSchema.rasterWidth * ChordInkFeatureSchema.rasterHeight
                )
            )
        )
    }
}

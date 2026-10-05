import CoreML
import CryptoKit
import Darwin
import Foundation

private let receiptSchemaVersion = "personal-dual-view-coreml-export-v1"
private let fixtureSchemaVersion = "personal-dual-view-coreml-parity-v1"
private let outputReceiptSchemaVersion = "personal-dual-view-swift-parity-receipt-v1"
private let featureSchemaVersion = "chord-ink-features-v1"
private let frozenFitSHA256 = "ce60efb539ce4d0897e0c339e6d1e1d90485ec07798aa1da499047482724a46f"
private let frozenProtocolSHA256 = "795b34713affc4ebeb85c9718faf56e6ac17c63f6dfb37105208a655015c0ad9"
private let modelScope = "research-runtime-parity-only-not-production"
private let frozenWeightSeed = 29
private let armOrder = ["rasterOnly", "trajectoryOnly", "dual"]
private let caseOrder = [
    "singlePoint",
    "horizontal",
    "vertical",
    "corner",
    "curve",
    "unequalMultiStroke",
    "reversedDirection",
    "reversedStrokeOrder",
    "timedMultiStroke",
    "retimedMultiStroke",
    "translatedMultiStroke",
    "scaledMultiStroke"
]
private let expectedSourcePaths: Set<String> = [
    "docs/personal-dual-view-glyph-protocol-2026-09-30.md",
    "docs/personal-dual-view-runtime-parity-protocol-2026-09-30.md",
    "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
    "recognition_ml/ichart_recognition_ml/research/personal_dual_view.py",
    "recognition_ml/ichart_recognition_ml/research/personal_dual_view_scoring.py",
    "recognition_ml/ichart_recognition_ml/research/personal_dual_view_export.py",
    "recognition_ml/tests/test_personal_dual_view.py",
    "recognition_ml/tests/test_personal_dual_view_scoring.py",
    "recognition_ml/tests/test_personal_dual_view_export.py",
    "recognition_ml/tests/PersonalDualViewCoreMLParityGate.swift",
    "iChart/Recognition/InkTrajectoryTypes.swift",
    "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
    "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
    "iChart/Recognition/Learned/ChordInkRasterizer.swift",
    "iChart/Recognition/Learned/ChordInkTrajectoryFeatureEncoder.swift"
]

@main
struct PersonalDualViewCoreMLParityGate {
    static func main() {
        do {
            let arguments = try Arguments.parse(CommandLine.arguments)
            let output = try run(arguments)
            try writeExclusive(output, to: arguments.outputReceiptURL)
            print(
                "Swift Core ML parity passed: \(output.predictionCount) predictions, "
                    + "\(output.outputScalarCount) runtime output scalars."
            )
        } catch {
            fputs("PersonalDualViewCoreMLParityGate failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ arguments: Arguments) throws -> GateOutputReceipt {
        try requireNewOutput(arguments.outputReceiptURL)
        let repositoryRoot = try requireCanonicalDirectory(
            arguments.repositoryRoot,
            context: "repository root"
        )
        let exportReceiptURL = try requireCanonicalRegularFile(
            arguments.exportReceiptURL,
            context: "export receipt"
        )
        let exportRoot = try requireCanonicalDirectory(
            exportReceiptURL.deletingLastPathComponent(),
            context: "export root"
        )
        let receiptData = try boundedData(
            at: exportReceiptURL,
            maximumByteCount: 2_000_000,
            context: "export receipt"
        )
        try require(
            sha256(receiptData) == arguments.detachedReceiptSHA256,
            "detached export receipt SHA-256 mismatch"
        )
        try StrictJSON.validate(receiptData, context: "export receipt")
        try ExportSchema.validateReceipt(receiptData)
        let receipt = try JSONDecoder().decode(ExportReceipt.self, from: receiptData)
        try validateReceipt(receipt)

        let receiptIdentity = FileIdentity(
            sha256: sha256(receiptData),
            byteCount: Int64(receiptData.count)
        )
        let sourceSnapshot = try validateSources(
            receipt.sourceArtifacts,
            repositoryRoot: repositoryRoot
        )

        let armBindings = Dictionary(
            uniqueKeysWithValues: receipt.arms.map { ($0.modelArm, $0) }
        )
        let detachedFixtureHashes = Dictionary(
            uniqueKeysWithValues: zip(armOrder, arguments.detachedFixtureSHA256s)
        )
        var fixtures: [String: ArmFixture] = [:]
        var fixtureIdentities: [String: FileIdentity] = [:]
        var packageIdentities: [String: PackageIdentity] = [:]
        var fixtureURLs: [String: URL] = [:]
        var packageURLs: [String: URL] = [:]

        for arm in armOrder {
            guard let binding = armBindings[arm],
                  let detachedFixtureSHA256 = detachedFixtureHashes[arm] else {
                throw GateFailure("missing arm binding for \(arm)")
            }
            let fixtureURL = try resolveRelativePath(
                binding.fixtureRelativePath,
                under: exportRoot,
                expectedKind: .regularFile,
                context: "\(arm) fixture"
            )
            let fixtureData = try boundedData(
                at: fixtureURL,
                maximumByteCount: 20_000_000,
                context: "\(arm) fixture"
            )
            let fixtureIdentity = FileIdentity(
                sha256: sha256(fixtureData),
                byteCount: Int64(fixtureData.count)
            )
            try require(
                fixtureIdentity.sha256 == detachedFixtureSHA256,
                "\(arm) detached fixture SHA-256 mismatch"
            )
            try require(
                fixtureIdentity.sha256 == binding.fixtureSHA256
                    && fixtureIdentity.byteCount == binding.fixtureByteCount,
                "\(arm) fixture identity differs from export receipt"
            )
            try StrictJSON.validate(fixtureData, context: "\(arm) fixture")
            try ExportSchema.validateFixture(fixtureData)
            let fixture = try JSONDecoder().decode(ArmFixture.self, from: fixtureData)
            try validateFixture(fixture, binding: binding)

            let packageURL = try resolveRelativePath(
                binding.modelPackageRelativePath,
                under: exportRoot,
                expectedKind: .directory,
                context: "\(arm) model package"
            )
            let packageIdentity = try fingerprintPackage(at: packageURL)
            try require(
                packageIdentity.treeSHA256 == binding.modelPackageTreeSHA256
                    && packageIdentity.byteCount == binding.modelPackageByteCount,
                "\(arm) model package identity differs from export receipt"
            )
            try require(
                fixture.modelPackageTreeSHA256 == packageIdentity.treeSHA256
                    && fixture.modelPackageByteCount == packageIdentity.byteCount,
                "\(arm) fixture model package identity mismatch"
            )

            fixtures[arm] = fixture
            fixtureIdentities[arm] = fixtureIdentity
            packageIdentities[arm] = packageIdentity
            fixtureURLs[arm] = fixtureURL
            packageURLs[arm] = packageURL
        }

        try validateCrossArmFixtures(fixtures)

        var cells: [CellReceipt] = []
        var maximums = MaximumErrors()
        for arm in armOrder {
            guard let fixture = fixtures[arm],
                  let packageURL = packageURLs[arm],
                  let binding = armBindings[arm] else {
                throw GateFailure("internal missing arm state for \(arm)")
            }
            let model = try loadModel(
                packageURL: packageURL,
                binding: binding,
                featureSchemaVersion: fixture.featureSchemaVersion
            )
            try validateModelDescription(model.modelDescription, fixture: fixture)
            for testCase in fixture.cases {
                let features = try recomputeFeatures(testCase)
                try validateFeatureEvidence(testCase.expected, features: features)
                try validateReferenceSet(testCase.expected, arm: arm)

                let base = try predict(
                    model: model,
                    trajectory: features.trajectory,
                    raster: features.rasterFloat32
                )
                let baseCell = try compare(
                    output: base,
                    torch: testCase.expected.torch,
                    python: testCase.expected.coreMLPython,
                    base: base,
                    tolerances: fixture.tolerances,
                    arm: arm,
                    caseID: testCase.caseID,
                    kind: "base"
                )
                cells.append(baseCell)
                maximums.include(baseCell)
                var timingTrajectory = features.trajectory
                for sample in 0..<ChordInkFeatureSchema.trajectorySampleCount {
                    timingTrajectory[
                        sample * ChordInkFeatureSchema.trajectoryChannelCount + 5
                    ] = Float(fixture.invarianceChecks.timingProbe.trajectoryChannel5)
                    timingTrajectory[
                        sample * ChordInkFeatureSchema.trajectoryChannelCount + 6
                    ] = Float(fixture.invarianceChecks.timingProbe.trajectoryChannel6)
                }
                let timingOutput = try predict(
                    model: model,
                    trajectory: timingTrajectory,
                    raster: features.rasterFloat32
                )
                let timingCell = try compare(
                    output: timingOutput,
                    torch: testCase.expected.timingProbe.torch,
                    python: testCase.expected.timingProbe.coreMLPython,
                    base: base,
                    tolerances: fixture.tolerances,
                    arm: arm,
                    caseID: testCase.caseID,
                    kind: "timingProbe"
                )
                cells.append(timingCell)
                maximums.include(timingCell)

                if arm != "dual" {
                    guard let inactive = testCase.expected.inactiveInputProbe else {
                        throw GateFailure("\(arm)/\(testCase.caseID) missing inactive-input evidence")
                    }
                    let inactiveTrajectory = arm == "rasterOnly"
                        ? Array(repeating: Float.zero, count: features.trajectory.count)
                        : features.trajectory
                    let inactiveRaster = arm == "trajectoryOnly"
                        ? Array(repeating: Float.zero, count: features.rasterFloat32.count)
                        : features.rasterFloat32
                    let inactiveOutput = try predict(
                        model: model,
                        trajectory: inactiveTrajectory,
                        raster: inactiveRaster
                    )
                    let inactiveCell = try compare(
                        output: inactiveOutput,
                        torch: inactive.torch,
                        python: inactive.coreMLPython,
                        base: base,
                        tolerances: fixture.tolerances,
                        arm: arm,
                        caseID: testCase.caseID,
                        kind: "inactiveInputProbe"
                    )
                    cells.append(inactiveCell)
                    maximums.include(inactiveCell)
                }
            }
        }

        try require(cells.filter { $0.predictionKind == "base" }.count == 36, "base prediction count mismatch")
        try require(cells.filter { $0.predictionKind == "timingProbe" }.count == 36, "timing prediction count mismatch")
        try require(cells.filter { $0.predictionKind == "inactiveInputProbe" }.count == 24, "inactive prediction count mismatch")
        try require(cells.count == 96, "total prediction count mismatch")
        try require(
            cells.allSatisfy { $0.outputScalarCount == 225 },
            "a prediction omitted output scalars"
        )
        let finalReceiptIdentity = try fileIdentity(at: exportReceiptURL)
        try require(
            finalReceiptIdentity == receiptIdentity,
            "export receipt changed during Swift execution"
        )
        try requireSourcesPreserved(sourceSnapshot)
        for arm in armOrder {
            guard let fixtureURL = fixtureURLs[arm],
                  let fixtureIdentity = fixtureIdentities[arm],
                  let packageURL = packageURLs[arm],
                  let packageIdentity = packageIdentities[arm] else {
                throw GateFailure("internal preservation state missing for \(arm)")
            }
            let finalFixtureIdentity = try fileIdentity(at: fixtureURL)
            try require(
                finalFixtureIdentity == fixtureIdentity,
                "\(arm) fixture changed during Swift execution"
            )
            let finalPackageIdentity = try fingerprintPackage(at: packageURL)
            try require(
                finalPackageIdentity == packageIdentity,
                "\(arm) package changed during Swift execution"
            )
        }

        let sourceByteCount = sourceSnapshot.values.reduce(Int64.zero) { $0 + $1.identity.byteCount }
        let fixtureByteCount = fixtureIdentities.values.reduce(Int64.zero) { $0 + $1.byteCount }
        let packageByteCount = packageIdentities.values.reduce(Int64.zero) { $0 + $1.byteCount }
        let outputScalarCount = cells.reduce(0) { $0 + $1.outputScalarCount }
        try require(outputScalarCount == 21_600, "runtime output scalar count mismatch")

        return GateOutputReceipt(
            schemaVersion: outputReceiptSchemaVersion,
            scope: modelScope,
            passed: true,
            exportReceiptSHA256: receiptIdentity.sha256,
            fixtureSHA256ByArm: fixtureIdentities.mapValues(\.sha256),
            modelPackageTreeSHA256ByArm: packageIdentities.mapValues(\.treeSHA256),
            caseCount: caseOrder.count,
            armCount: armOrder.count,
            basePredictionCount: 36,
            timingProbePredictionCount: 36,
            inactiveInputProbePredictionCount: 24,
            predictionCount: cells.count,
            outputScalarCount: outputScalarCount,
            runtimeReferenceScalarComparisonCount: cells.count * 225 * 2,
            runtimeInvarianceScalarComparisonCount: 60 * 225,
            fixtureReferenceScalarValidationCount: cells.count * 225,
            firstArgmaxComparisonCount: cells.count * 2 + 60,
            sourceArtifactCount: sourceSnapshot.count,
            sourceArtifactByteCount: sourceByteCount,
            fixtureCount: fixtureIdentities.count,
            fixtureByteCount: fixtureByteCount,
            modelPackageCount: packageIdentities.count,
            modelPackageByteCount: packageByteCount,
            sourceBytesPreserved: true,
            fixtureBytesPreserved: true,
            modelPackageBytesPreserved: true,
            maximumErrors: maximums,
            cells: cells
        )
    }
}

private struct Arguments {
    let repositoryRoot: URL
    let exportReceiptURL: URL
    let detachedReceiptSHA256: String
    let detachedFixtureSHA256s: [String]
    let outputReceiptURL: URL

    static func parse(_ values: [String]) throws -> Self {
        guard values.count == 8 else {
            throw GateFailure(
                "usage: gate <repo-root> <export-receipt.json> <receipt-sha256> "
                    + "<rasterOnly-fixture-sha256> <trajectoryOnly-fixture-sha256> "
                    + "<dual-fixture-sha256> <new-output-receipt.json>"
            )
        }
        for (index, value) in values[3...6].enumerated() {
            try requireSHA256(value, context: "detached digest argument \(index)")
        }
        return Self(
            repositoryRoot: URL(fileURLWithPath: values[1]),
            exportReceiptURL: URL(fileURLWithPath: values[2]),
            detachedReceiptSHA256: values[3],
            detachedFixtureSHA256s: Array(values[4...6]),
            outputReceiptURL: URL(fileURLWithPath: values[7])
        )
    }
}

private struct ExportReceipt: Decodable {
    let schemaVersion: String
    let featureSchemaVersion: String
    let sourceArtifacts: [SourceArtifact]
    let arms: [ArmBinding]
}

private struct SourceArtifact: Decodable {
    let relativePath: String
    let sha256: String
    let byteCount: Int64
}

private struct ArmBinding: Decodable {
    let modelArm: String
    let weightSeed: Int
    let fitSHA256: String
    let vocabularySHA256: String
    let weightsSHA256: String
    let fixtureRelativePath: String
    let fixtureSHA256: String
    let fixtureByteCount: Int64
    let modelPackageRelativePath: String
    let modelPackageTreeSHA256: String
    let modelPackageByteCount: Int64
}

private struct ArmFixture: Decodable {
    let schemaVersion: String
    let featureSchemaVersion: String
    let modelArm: String
    let weightSeed: Int
    let fitSHA256: String
    let vocabularySHA256: String
    let weightsSHA256: String
    let modelPackageRelativePath: String
    let modelPackageTreeSHA256: String
    let modelPackageByteCount: Int64
    let inputFeatures: [FeatureDescription]
    let outputFeatures: [FeatureDescription]
    let tolerances: Tolerances
    let cases: [FixtureCase]
    let invarianceChecks: InvarianceChecks
}

private struct FeatureDescription: Decodable, Equatable {
    let name: String
    let shape: [Int]
    let dataType: String
}

private struct Tolerances: Decodable, Equatable {
    let personalEmbeddingMaximumAbsoluteError: Double
    let genericLogitsMaximumAbsoluteError: Double
}

private struct InvarianceChecks: Decodable, Equatable {
    let timingProbe: TimingProbeConfiguration
    let inactiveInputProbe: InactiveInputProbeConfiguration
}

private struct TimingProbeConfiguration: Decodable, Equatable {
    let trajectoryChannel5: Double
    let trajectoryChannel6: Double
}

private struct InactiveInputProbeConfiguration: Decodable, Equatable {
    let zeroRasterForArms: [String]
    let zeroTrajectoryForArms: [String]
}

private struct FixtureCase: Decodable, Equatable {
    let caseID: String
    let rawStrokes: [RawStroke]
    let expected: ExpectedEvidence
}

private struct RawStroke: Decodable, Equatable {
    let creationTimeOffset: Double?
    let points: [RawPoint]
}

private struct RawPoint: Decodable, Equatable {
    let x: Double
    let y: Double
    let timeOffset: Double?
}

private struct ExpectedEvidence: Decodable, Equatable {
    let trajectoryFloat32LEBase64: String
    let trajectorySHA256: String
    let rasterUInt8Base64: String
    let rasterSHA256: String
    let rasterFloat32LEBase64: String
    let rasterFloat32SHA256: String
    let torch: ReferenceVector
    let coreMLPython: ReferenceVector
    let parity: ParityEvidence
    let timingProbe: ProbeEvidence
    let inactiveInputProbe: ProbeEvidence?
}

private struct ReferenceVector: Decodable, Equatable {
    let personalEmbedding: [Double]
    let genericLogits: [Double]
    let firstGenericArgmax: Int
}

private struct ParityEvidence: Decodable, Equatable {
    let embeddingMaximumAbsoluteError: Double
    let logitsMaximumAbsoluteError: Double
    let firstGenericArgmaxEqual: Bool
}

private struct ProbeEvidence: Decodable, Equatable {
    let torch: ReferenceVector
    let coreMLPython: ReferenceVector
    let parity: ParityEvidence
    let invariance: ProbeInvarianceEvidence
}

private struct ProbeInvarianceEvidence: Decodable, Equatable {
    let torchEmbeddingMaximumAbsoluteError: Double
    let torchLogitsMaximumAbsoluteError: Double
    let torchFirstGenericArgmaxEqual: Bool
    let coreMLPythonEmbeddingMaximumAbsoluteError: Double
    let coreMLPythonLogitsMaximumAbsoluteError: Double
    let coreMLPythonFirstGenericArgmaxEqual: Bool
}

private struct FileIdentity: Codable, Equatable {
    let sha256: String
    let byteCount: Int64
}

private struct PackageIdentity: Equatable {
    let treeSHA256: String
    let byteCount: Int64
    let fileCount: Int
}

private struct SourceSnapshot {
    let url: URL
    let identity: FileIdentity
}

private struct ComputedFeatures {
    let trajectory: [Float]
    let trajectoryBytes: Data
    let rasterUInt8: Data
    let rasterFloat32: [Float]
    let rasterFloat32Bytes: Data
}

private struct PredictionVector {
    let personalEmbedding: [Double]
    let genericLogits: [Double]

    var firstGenericArgmax: Int {
        genericLogits.indices.dropFirst().reduce(0) { best, index in
            genericLogits[index] > genericLogits[best] ? index : best
        }
    }

    var embeddingL2Norm: Double {
        sqrt(personalEmbedding.reduce(0) { $0 + $1 * $1 })
    }
}

private struct CellReceipt: Codable {
    let modelArm: String
    let caseID: String
    let predictionKind: String
    let outputScalarCount: Int
    let embeddingMaximumAbsoluteErrorVsTorch: Double
    let logitsMaximumAbsoluteErrorVsTorch: Double
    let embeddingMaximumAbsoluteErrorVsCoreMLPython: Double
    let logitsMaximumAbsoluteErrorVsCoreMLPython: Double
    let embeddingMaximumAbsoluteErrorVsRuntimeBase: Double
    let logitsMaximumAbsoluteErrorVsRuntimeBase: Double
    let runtimeEmbeddingL2Norm: Double
    let runtimeFirstGenericArgmax: Int
    let torchFirstGenericArgmax: Int
    let coreMLPythonFirstGenericArgmax: Int
    let firstGenericArgmaxMatchesTorch: Bool
    let firstGenericArgmaxMatchesCoreMLPython: Bool
    let firstGenericArgmaxMatchesRuntimeBase: Bool
}

private struct MaximumErrors: Codable {
    var embeddingVsTorch = 0.0
    var logitsVsTorch = 0.0
    var embeddingVsCoreMLPython = 0.0
    var logitsVsCoreMLPython = 0.0
    var embeddingVsRuntimeBase = 0.0
    var logitsVsRuntimeBase = 0.0

    mutating func include(_ cell: CellReceipt) {
        embeddingVsTorch = max(embeddingVsTorch, cell.embeddingMaximumAbsoluteErrorVsTorch)
        logitsVsTorch = max(logitsVsTorch, cell.logitsMaximumAbsoluteErrorVsTorch)
        embeddingVsCoreMLPython = max(
            embeddingVsCoreMLPython,
            cell.embeddingMaximumAbsoluteErrorVsCoreMLPython
        )
        logitsVsCoreMLPython = max(
            logitsVsCoreMLPython,
            cell.logitsMaximumAbsoluteErrorVsCoreMLPython
        )
        embeddingVsRuntimeBase = max(
            embeddingVsRuntimeBase,
            cell.embeddingMaximumAbsoluteErrorVsRuntimeBase
        )
        logitsVsRuntimeBase = max(
            logitsVsRuntimeBase,
            cell.logitsMaximumAbsoluteErrorVsRuntimeBase
        )
    }
}

private struct GateOutputReceipt: Codable {
    let schemaVersion: String
    let scope: String
    let passed: Bool
    let exportReceiptSHA256: String
    let fixtureSHA256ByArm: [String: String]
    let modelPackageTreeSHA256ByArm: [String: String]
    let caseCount: Int
    let armCount: Int
    let basePredictionCount: Int
    let timingProbePredictionCount: Int
    let inactiveInputProbePredictionCount: Int
    let predictionCount: Int
    let outputScalarCount: Int
    let runtimeReferenceScalarComparisonCount: Int
    let runtimeInvarianceScalarComparisonCount: Int
    let fixtureReferenceScalarValidationCount: Int
    let firstArgmaxComparisonCount: Int
    let sourceArtifactCount: Int
    let sourceArtifactByteCount: Int64
    let fixtureCount: Int
    let fixtureByteCount: Int64
    let modelPackageCount: Int
    let modelPackageByteCount: Int64
    let sourceBytesPreserved: Bool
    let fixtureBytesPreserved: Bool
    let modelPackageBytesPreserved: Bool
    let maximumErrors: MaximumErrors
    let cells: [CellReceipt]
}

private enum ExpectedPathKind {
    case regularFile
    case directory
}

private struct GateFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw GateFailure(message) }
}

private func requireSHA256(_ value: String, context: String) throws {
    try require(
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            },
        "\(context) is not canonical lowercase SHA-256"
    )
}

private func validateReceipt(_ receipt: ExportReceipt) throws {
    try require(receipt.schemaVersion == receiptSchemaVersion, "export receipt schema mismatch")
    try require(receipt.featureSchemaVersion == featureSchemaVersion, "feature schema mismatch")
    try require(receipt.sourceArtifacts.count == expectedSourcePaths.count, "source binding count mismatch")
    try require(receipt.arms.map(\.modelArm) == armOrder, "arm binding order mismatch")
    try require(Set(receipt.arms.map(\.modelArm)).count == armOrder.count, "duplicate arm binding")

    var vocabularyDigests: Set<String> = []
    var weightDigests: Set<String> = []
    for binding in receipt.arms {
        try require(binding.weightSeed == frozenWeightSeed, "\(binding.modelArm) weight seed mismatch")
        try require(binding.fitSHA256 == frozenFitSHA256, "\(binding.modelArm) fit receipt mismatch")
        try requireSHA256(binding.vocabularySHA256, context: "\(binding.modelArm) vocabulary digest")
        try requireSHA256(binding.weightsSHA256, context: "\(binding.modelArm) weight digest")
        try requireSHA256(binding.fixtureSHA256, context: "\(binding.modelArm) fixture digest")
        try requireSHA256(binding.modelPackageTreeSHA256, context: "\(binding.modelArm) package digest")
        try require(binding.fixtureByteCount > 0, "\(binding.modelArm) fixture is empty")
        try require(binding.modelPackageByteCount > 0, "\(binding.modelArm) package is empty")
        try require(
            binding.fixtureRelativePath == "fixtures/\(binding.modelArm).json",
            "\(binding.modelArm) fixture path mismatch"
        )
        try require(
            binding.modelPackageRelativePath == "models/\(binding.modelArm).mlpackage",
            "\(binding.modelArm) package path mismatch"
        )
        vocabularyDigests.insert(binding.vocabularySHA256)
        weightDigests.insert(binding.weightsSHA256)
    }
    try require(vocabularyDigests.count == 1, "arm vocabulary digests differ")
    try require(weightDigests.count == armOrder.count, "arm checkpoints are not distinct")
}

private func validateFixture(_ fixture: ArmFixture, binding: ArmBinding) throws {
    try require(fixture.schemaVersion == fixtureSchemaVersion, "\(binding.modelArm) fixture schema mismatch")
    try require(fixture.featureSchemaVersion == featureSchemaVersion, "\(binding.modelArm) feature schema mismatch")
    try require(fixture.modelArm == binding.modelArm, "fixture arm binding mismatch")
    try require(fixture.weightSeed == binding.weightSeed, "\(binding.modelArm) fixture seed mismatch")
    try require(fixture.fitSHA256 == binding.fitSHA256, "\(binding.modelArm) fixture fit mismatch")
    try require(fixture.vocabularySHA256 == binding.vocabularySHA256, "\(binding.modelArm) fixture vocabulary mismatch")
    try require(fixture.weightsSHA256 == binding.weightsSHA256, "\(binding.modelArm) fixture weight mismatch")
    try require(
        fixture.modelPackageRelativePath == binding.modelPackageRelativePath,
        "\(binding.modelArm) fixture package path mismatch"
    )
    try require(
        fixture.modelPackageTreeSHA256 == binding.modelPackageTreeSHA256
            && fixture.modelPackageByteCount == binding.modelPackageByteCount,
        "\(binding.modelArm) fixture package identity mismatch"
    )
    let expectedInputs = [
        FeatureDescription(name: "inkRaster", shape: [1, 1, 96, 256], dataType: "float32"),
        FeatureDescription(name: "inkTrajectory", shape: [1, 1, 256, 10], dataType: "float32")
    ]
    let expectedOutputs = [
        FeatureDescription(name: "genericLogits", shape: [1, 97], dataType: "float32"),
        FeatureDescription(name: "personalEmbedding", shape: [1, 128], dataType: "float32")
    ]
    try require(fixture.inputFeatures == expectedInputs, "\(binding.modelArm) input feature contract mismatch")
    try require(fixture.outputFeatures == expectedOutputs, "\(binding.modelArm) output feature contract mismatch")
    try require(
        fixture.tolerances == Tolerances(
            personalEmbeddingMaximumAbsoluteError: 0.0001,
            genericLogitsMaximumAbsoluteError: 0.001
        ),
        "\(binding.modelArm) tolerances changed"
    )
    try require(
        fixture.invarianceChecks == InvarianceChecks(
            timingProbe: TimingProbeConfiguration(
                trajectoryChannel5: 0.37,
                trajectoryChannel6: 1
            ),
            inactiveInputProbe: InactiveInputProbeConfiguration(
                zeroRasterForArms: ["trajectoryOnly"],
                zeroTrajectoryForArms: ["rasterOnly"]
            )
        ),
        "\(binding.modelArm) invariance probe contract mismatch"
    )
    try require(fixture.cases.map(\.caseID) == caseOrder, "\(binding.modelArm) case cohort mismatch")
    for testCase in fixture.cases {
        try validateRawCase(testCase, arm: binding.modelArm)
        if binding.modelArm == "dual" {
            try require(
                testCase.expected.inactiveInputProbe == nil,
                "dual fixture must not carry inactive-input evidence"
            )
        } else {
            try require(
                testCase.expected.inactiveInputProbe != nil,
                "\(binding.modelArm) fixture omitted inactive-input evidence"
            )
        }
    }
}

private func validateCrossArmFixtures(_ fixtures: [String: ArmFixture]) throws {
    guard let reference = fixtures[armOrder[0]] else {
        throw GateFailure("reference fixture missing")
    }
    for arm in armOrder.dropFirst() {
        guard let fixture = fixtures[arm] else { throw GateFailure("\(arm) fixture missing") }
        for index in caseOrder.indices {
            try require(
                fixture.cases[index].caseID == reference.cases[index].caseID
                    && fixture.cases[index].rawStrokes == reference.cases[index].rawStrokes,
                "\(arm)/\(caseOrder[index]) raw stroke fixture differs across arms"
            )
            let lhs = fixture.cases[index].expected
            let rhs = reference.cases[index].expected
            try require(
                lhs.trajectoryFloat32LEBase64 == rhs.trajectoryFloat32LEBase64
                    && lhs.trajectorySHA256 == rhs.trajectorySHA256
                    && lhs.rasterUInt8Base64 == rhs.rasterUInt8Base64
                    && lhs.rasterSHA256 == rhs.rasterSHA256
                    && lhs.rasterFloat32LEBase64 == rhs.rasterFloat32LEBase64
                    && lhs.rasterFloat32SHA256 == rhs.rasterFloat32SHA256,
                "\(arm)/\(caseOrder[index]) feature evidence differs across arms"
            )
        }
    }
}

private func validateRawCase(_ testCase: FixtureCase, arm: String) throws {
    try require(!testCase.rawStrokes.isEmpty, "\(arm)/\(testCase.caseID) has no strokes")
    var pointCount = 0
    for stroke in testCase.rawStrokes {
        try require(!stroke.points.isEmpty, "\(arm)/\(testCase.caseID) has an empty stroke")
        if let creationTimeOffset = stroke.creationTimeOffset {
            try require(creationTimeOffset.isFinite, "\(arm)/\(testCase.caseID) has nonfinite stroke time")
        }
        for point in stroke.points {
            pointCount += 1
            try require(point.x.isFinite && point.y.isFinite, "\(arm)/\(testCase.caseID) has nonfinite geometry")
            if let timeOffset = point.timeOffset {
                try require(timeOffset.isFinite, "\(arm)/\(testCase.caseID) has nonfinite point time")
            }
        }
    }
    try require(pointCount > 0 && pointCount <= 8_192, "\(arm)/\(testCase.caseID) point count invalid")
    try requireSHA256(testCase.expected.trajectorySHA256, context: "trajectory fixture digest")
    try requireSHA256(testCase.expected.rasterSHA256, context: "raster fixture digest")
    try requireSHA256(testCase.expected.rasterFloat32SHA256, context: "raster float fixture digest")
}

private func validateReferenceSet(_ expected: ExpectedEvidence, arm: String) throws {
    try validateVector(expected.torch, context: "\(arm) base Torch")
    try validateVector(expected.coreMLPython, context: "\(arm) base Python Core ML")
    try validateParity(
        expected.parity,
        lhs: expected.torch,
        rhs: expected.coreMLPython,
        context: "\(arm) base"
    )
    try validateVector(expected.timingProbe.torch, context: "\(arm) timing Torch")
    try validateVector(expected.timingProbe.coreMLPython, context: "\(arm) timing Python Core ML")
    try validateParity(
        expected.timingProbe.parity,
        lhs: expected.timingProbe.torch,
        rhs: expected.timingProbe.coreMLPython,
        context: "\(arm) timing"
    )
    try validateProbeInvariance(
        expected.timingProbe,
        baseTorch: expected.torch,
        basePython: expected.coreMLPython,
        context: "\(arm) timing"
    )
    if let inactive = expected.inactiveInputProbe {
        try validateVector(inactive.torch, context: "\(arm) inactive Torch")
        try validateVector(inactive.coreMLPython, context: "\(arm) inactive Python Core ML")
        try validateParity(
            inactive.parity,
            lhs: inactive.torch,
            rhs: inactive.coreMLPython,
            context: "\(arm) inactive"
        )
        try validateProbeInvariance(
            inactive,
            baseTorch: expected.torch,
            basePython: expected.coreMLPython,
            context: "\(arm) inactive"
        )
    }
}

private func validateVector(_ vector: ReferenceVector, context: String) throws {
    try require(vector.personalEmbedding.count == 128, "\(context) embedding count mismatch")
    try require(vector.genericLogits.count == 97, "\(context) logit count mismatch")
    try require(
        vector.personalEmbedding.allSatisfy(\.isFinite)
            && vector.genericLogits.allSatisfy(\.isFinite),
        "\(context) contains nonfinite values"
    )
    let norm = sqrt(vector.personalEmbedding.reduce(0) { $0 + $1 * $1 })
    try require(abs(norm - 1) <= 0.0001, "\(context) embedding is not unit-normalized")
    try require(
        firstArgmax(vector.genericLogits) == vector.firstGenericArgmax,
        "\(context) stored first argmax mismatch"
    )
}

private func validateParity(
    _ evidence: ParityEvidence,
    lhs: ReferenceVector,
    rhs: ReferenceVector,
    context: String
) throws {
    let embeddingError = maximumAbsoluteError(lhs.personalEmbedding, rhs.personalEmbedding)
    let logitsError = maximumAbsoluteError(lhs.genericLogits, rhs.genericLogits)
    try require(
        approximatelyEqual(embeddingError, evidence.embeddingMaximumAbsoluteError)
            && approximatelyEqual(logitsError, evidence.logitsMaximumAbsoluteError),
        "\(context) reported parity errors are stale"
    )
    try require(
        embeddingError <= 0.0001 && logitsError <= 0.001,
        "\(context) Python conversion parity exceeded tolerance"
    )
    let argmaxEqual = lhs.firstGenericArgmax == rhs.firstGenericArgmax
    try require(
        evidence.firstGenericArgmaxEqual && argmaxEqual,
        "\(context) Python first argmax differs"
    )
}

private func validateProbeInvariance(
    _ probe: ProbeEvidence,
    baseTorch: ReferenceVector,
    basePython: ReferenceVector,
    context: String
) throws {
    let torchEmbedding = maximumAbsoluteError(
        probe.torch.personalEmbedding,
        baseTorch.personalEmbedding
    )
    let torchLogits = maximumAbsoluteError(probe.torch.genericLogits, baseTorch.genericLogits)
    let pythonEmbedding = maximumAbsoluteError(
        probe.coreMLPython.personalEmbedding,
        basePython.personalEmbedding
    )
    let pythonLogits = maximumAbsoluteError(
        probe.coreMLPython.genericLogits,
        basePython.genericLogits
    )
    try require(
        approximatelyEqual(torchEmbedding, probe.invariance.torchEmbeddingMaximumAbsoluteError)
            && approximatelyEqual(torchLogits, probe.invariance.torchLogitsMaximumAbsoluteError)
            && approximatelyEqual(
                pythonEmbedding,
                probe.invariance.coreMLPythonEmbeddingMaximumAbsoluteError
            )
            && approximatelyEqual(
                pythonLogits,
                probe.invariance.coreMLPythonLogitsMaximumAbsoluteError
            ),
        "\(context) reported invariance errors are stale"
    )
    try require(
        torchEmbedding <= 0.0001 && pythonEmbedding <= 0.0001
            && torchLogits <= 0.001 && pythonLogits <= 0.001,
        "\(context) fixture invariance exceeded tolerance"
    )
    let torchArgmaxEqual = probe.torch.firstGenericArgmax == baseTorch.firstGenericArgmax
    let pythonArgmaxEqual = probe.coreMLPython.firstGenericArgmax
        == basePython.firstGenericArgmax
    try require(
        probe.invariance.torchFirstGenericArgmaxEqual && torchArgmaxEqual
            && probe.invariance.coreMLPythonFirstGenericArgmaxEqual && pythonArgmaxEqual,
        "\(context) fixture invariance changed first argmax"
    )
}

private func recomputeFeatures(_ testCase: FixtureCase) throws -> ComputedFeatures {
    let strokes = testCase.rawStrokes.map { stroke in
        InkStroke(
            points: stroke.points.map { point in
                InkPoint(x: point.x, y: point.y, timeOffset: point.timeOffset)
            },
            creationTimeOffset: stroke.creationTimeOffset
        )
    }
    let packet = try ChordInkCanonicalTrajectoryPacket(strokes: strokes)
    let trajectory = try ChordInkTrajectoryFeatureEncoder.encode(packet)
    let raster = try ChordInkRasterizer.rasterize(packet)
    let trajectoryBytes = float32LittleEndianData(trajectory.values)
    let rasterUInt8 = Data(raster.pixels)
    let rasterFloat32 = raster.pixels.map { Float($0) / Float(255) }
    let rasterFloat32Bytes = float32LittleEndianData(rasterFloat32)
    return ComputedFeatures(
        trajectory: trajectory.values,
        trajectoryBytes: trajectoryBytes,
        rasterUInt8: rasterUInt8,
        rasterFloat32: rasterFloat32,
        rasterFloat32Bytes: rasterFloat32Bytes
    )
}

private func validateFeatureEvidence(
    _ expected: ExpectedEvidence,
    features: ComputedFeatures
) throws {
    let trajectoryExpected = try canonicalBase64Data(
        expected.trajectoryFloat32LEBase64,
        expectedByteCount: 10_240,
        context: "trajectory float32 bytes"
    )
    let rasterExpected = try canonicalBase64Data(
        expected.rasterUInt8Base64,
        expectedByteCount: 24_576,
        context: "raster uint8 bytes"
    )
    let rasterFloatExpected = try canonicalBase64Data(
        expected.rasterFloat32LEBase64,
        expectedByteCount: 98_304,
        context: "raster float32 bytes"
    )
    try require(
        sha256(trajectoryExpected) == expected.trajectorySHA256
            && sha256(rasterExpected) == expected.rasterSHA256
            && sha256(rasterFloatExpected) == expected.rasterFloat32SHA256,
        "fixture feature bytes do not match their hashes"
    )
    try require(
        features.trajectoryBytes == trajectoryExpected
            && features.rasterUInt8 == rasterExpected
            && features.rasterFloat32Bytes == rasterFloatExpected,
        "actual app feature encoding differs from fixture"
    )
}

private func loadModel(
    packageURL: URL,
    binding: ArmBinding,
    featureSchemaVersion: String
) throws -> MLModel {
    let compiledURL: URL
    do {
        compiledURL = try MLModel.compileModel(at: packageURL)
    } catch {
        throw GateFailure("\(binding.modelArm) model package compilation failed")
    }
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuOnly
    let model: MLModel
    do {
        model = try MLModel(contentsOf: compiledURL, configuration: configuration)
    } catch {
        throw GateFailure("\(binding.modelArm) compiled model load failed")
    }
    let expectedMetadata = [
        "ichart.modelArm": binding.modelArm,
        "ichart.weightSeed": String(binding.weightSeed),
        "ichart.weightsSHA256": binding.weightsSHA256,
        "ichart.fitReceiptSHA256": binding.fitSHA256,
        "ichart.vocabularySHA256": binding.vocabularySHA256,
        "ichart.featureSchemaVersion": featureSchemaVersion,
        "ichart.scope": modelScope
    ]
    guard let metadata = model.modelDescription.metadata[.creatorDefinedKey]
        as? [String: String] else {
        throw GateFailure("\(binding.modelArm) creator-defined metadata is missing or malformed")
    }
    try require(metadata == expectedMetadata, "\(binding.modelArm) model metadata mismatch")
    return model
}

private func validateModelDescription(
    _ description: MLModelDescription,
    fixture: ArmFixture
) throws {
    let expectedInputs = Dictionary(uniqueKeysWithValues: fixture.inputFeatures.map { ($0.name, $0) })
    let expectedOutputs = Dictionary(uniqueKeysWithValues: fixture.outputFeatures.map { ($0.name, $0) })
    try require(
        Set(description.inputDescriptionsByName.keys) == Set(expectedInputs.keys),
        "\(fixture.modelArm) compiled model input names mismatch"
    )
    try require(
        Set(description.outputDescriptionsByName.keys) == Set(expectedOutputs.keys),
        "\(fixture.modelArm) compiled model output names mismatch"
    )
    let expectedFeatures = expectedInputs.merging(expectedOutputs) { _, rhs in rhs }
    for (name, expected) in expectedFeatures {
        let actual = description.inputDescriptionsByName[name]
            ?? description.outputDescriptionsByName[name]
        guard let actual else { throw GateFailure("\(fixture.modelArm) missing feature \(name)") }
        try require(!actual.isOptional, "\(fixture.modelArm)/\(name) unexpectedly optional")
        try require(actual.type == .multiArray, "\(fixture.modelArm)/\(name) is not multiArray")
        guard let constraint = actual.multiArrayConstraint else {
            throw GateFailure("\(fixture.modelArm)/\(name) lacks multiArray constraint")
        }
        try require(
            constraint.shape.map(\.intValue) == expected.shape,
            "\(fixture.modelArm)/\(name) shape mismatch"
        )
        try require(
            constraint.dataType == .float32 && expected.dataType == "float32",
            "\(fixture.modelArm)/\(name) is not float32"
        )
    }
}

private func predict(
    model: MLModel,
    trajectory: [Float],
    raster: [Float]
) throws -> PredictionVector {
    try require(trajectory.count == 2_560, "runtime trajectory scalar count mismatch")
    try require(raster.count == 24_576, "runtime raster scalar count mismatch")
    try require(
        trajectory.allSatisfy(\.isFinite) && raster.allSatisfy(\.isFinite),
        "runtime input contains nonfinite value"
    )
    let trajectoryArray = try makeMultiArray(
        shape: [1, 1, 256, 10],
        values: trajectory
    )
    let rasterArray = try makeMultiArray(
        shape: [1, 1, 96, 256],
        values: raster
    )
    let provider: MLDictionaryFeatureProvider
    do {
        provider = try MLDictionaryFeatureProvider(
            dictionary: [
                "inkTrajectory": MLFeatureValue(multiArray: trajectoryArray),
                "inkRaster": MLFeatureValue(multiArray: rasterArray)
            ]
        )
    } catch {
        throw GateFailure("Core ML input provider construction failed")
    }
    let prediction: any MLFeatureProvider
    do {
        prediction = try model.prediction(from: provider)
    } catch {
        throw GateFailure("CPU-only Core ML prediction failed")
    }
    try require(
        prediction.featureNames == Set(["personalEmbedding", "genericLogits"]),
        "Core ML prediction output names mismatch"
    )
    return PredictionVector(
        personalEmbedding: try outputValues(
            named: "personalEmbedding",
            shape: [1, 128],
            provider: prediction
        ),
        genericLogits: try outputValues(
            named: "genericLogits",
            shape: [1, 97],
            provider: prediction
        )
    )
}

private func makeMultiArray(shape: [Int], values: [Float]) throws -> MLMultiArray {
    let array: MLMultiArray
    do {
        array = try MLMultiArray(
            shape: shape.map { NSNumber(value: $0) },
            dataType: .float32
        )
    } catch {
        throw GateFailure("Core ML input multiArray allocation failed")
    }
    try require(array.count == values.count, "Core ML input allocation count mismatch")
    for (index, value) in values.enumerated() {
        array[index] = NSNumber(value: value)
    }
    return array
}

private func outputValues(
    named name: String,
    shape: [Int],
    provider: any MLFeatureProvider
) throws -> [Double] {
    guard let feature = provider.featureValue(for: name),
          !feature.isUndefined,
          feature.type == .multiArray,
          let array = feature.multiArrayValue else {
        throw GateFailure("Core ML output \(name) is missing or malformed")
    }
    try require(array.shape.map(\.intValue) == shape, "Core ML output \(name) shape mismatch")
    try require(array.dataType == .float32, "Core ML output \(name) is not float32")
    let values = (0..<array.count).map { array[$0].doubleValue }
    try require(values.allSatisfy(\.isFinite), "Core ML output \(name) contains nonfinite values")
    return values
}

private func compare(
    output: PredictionVector,
    torch: ReferenceVector,
    python: ReferenceVector,
    base: PredictionVector,
    tolerances: Tolerances,
    arm: String,
    caseID: String,
    kind: String
) throws -> CellReceipt {
    let embeddingVsTorch = maximumAbsoluteError(output.personalEmbedding, torch.personalEmbedding)
    let logitsVsTorch = maximumAbsoluteError(output.genericLogits, torch.genericLogits)
    let embeddingVsPython = maximumAbsoluteError(output.personalEmbedding, python.personalEmbedding)
    let logitsVsPython = maximumAbsoluteError(output.genericLogits, python.genericLogits)
    let embeddingVsBase = maximumAbsoluteError(output.personalEmbedding, base.personalEmbedding)
    let logitsVsBase = maximumAbsoluteError(output.genericLogits, base.genericLogits)
    let context = "\(arm)/\(caseID)/\(kind)"
    try require(
        embeddingVsTorch <= tolerances.personalEmbeddingMaximumAbsoluteError
            && embeddingVsPython <= tolerances.personalEmbeddingMaximumAbsoluteError,
        "\(context) embedding parity exceeded 1e-4"
    )
    try require(
        logitsVsTorch <= tolerances.genericLogitsMaximumAbsoluteError
            && logitsVsPython <= tolerances.genericLogitsMaximumAbsoluteError,
        "\(context) logit parity exceeded 1e-3"
    )
    if kind != "base" {
        try require(
            embeddingVsBase <= tolerances.personalEmbeddingMaximumAbsoluteError
                && logitsVsBase <= tolerances.genericLogitsMaximumAbsoluteError,
            "\(context) inactive-input invariance exceeded tolerance"
        )
    }
    try require(abs(output.embeddingL2Norm - 1) <= 0.0001, "\(context) embedding norm mismatch")
    let argmax = output.firstGenericArgmax
    let matchesTorch = argmax == torch.firstGenericArgmax
    let matchesPython = argmax == python.firstGenericArgmax
    let matchesBase = argmax == base.firstGenericArgmax
    try require(matchesTorch && matchesPython, "\(context) first argmax differs from reference")
    if kind != "base" {
        try require(matchesBase, "\(context) first argmax differs from runtime base")
    }
    return CellReceipt(
        modelArm: arm,
        caseID: caseID,
        predictionKind: kind,
        outputScalarCount: output.personalEmbedding.count + output.genericLogits.count,
        embeddingMaximumAbsoluteErrorVsTorch: embeddingVsTorch,
        logitsMaximumAbsoluteErrorVsTorch: logitsVsTorch,
        embeddingMaximumAbsoluteErrorVsCoreMLPython: embeddingVsPython,
        logitsMaximumAbsoluteErrorVsCoreMLPython: logitsVsPython,
        embeddingMaximumAbsoluteErrorVsRuntimeBase: embeddingVsBase,
        logitsMaximumAbsoluteErrorVsRuntimeBase: logitsVsBase,
        runtimeEmbeddingL2Norm: output.embeddingL2Norm,
        runtimeFirstGenericArgmax: argmax,
        torchFirstGenericArgmax: torch.firstGenericArgmax,
        coreMLPythonFirstGenericArgmax: python.firstGenericArgmax,
        firstGenericArgmaxMatchesTorch: matchesTorch,
        firstGenericArgmaxMatchesCoreMLPython: matchesPython,
        firstGenericArgmaxMatchesRuntimeBase: matchesBase
    )
}

private func firstArgmax(_ values: [Double]) -> Int {
    values.indices.dropFirst().reduce(0) { best, index in
        values[index] > values[best] ? index : best
    }
}

private func maximumAbsoluteError(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
    return zip(lhs, rhs).reduce(0) { maximum, pair in
        max(maximum, abs(pair.0 - pair.1))
    }
}

private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    lhs.isFinite && rhs.isFinite && abs(lhs - rhs) <= 1e-12
}

private func float32LittleEndianData(_ values: [Float]) -> Data {
    var data = Data(capacity: values.count * MemoryLayout<UInt32>.size)
    for value in values {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }
    return data
}

private func canonicalBase64Data(
    _ encoded: String,
    expectedByteCount: Int,
    context: String
) throws -> Data {
    guard let data = Data(base64Encoded: encoded),
          data.count == expectedByteCount,
          data.base64EncodedString() == encoded else {
        throw GateFailure("\(context) is not canonical base64 of expected size")
    }
    return data
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func fileIdentity(at url: URL) throws -> FileIdentity {
    let data = try boundedData(
        at: try requireCanonicalRegularFile(url, context: url.lastPathComponent),
        maximumByteCount: 100_000_000,
        context: url.lastPathComponent
    )
    return FileIdentity(sha256: sha256(data), byteCount: Int64(data.count))
}

private func boundedData(at url: URL, maximumByteCount: Int, context: String) throws -> Data {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let byteCount = attributes[.size] as? NSNumber,
          byteCount.int64Value >= 0,
          byteCount.int64Value <= maximumByteCount else {
        throw GateFailure("\(context) exceeds byte budget")
    }
    do {
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
        throw GateFailure("\(context) is unreadable")
    }
}

private func validateSources(
    _ artifacts: [SourceArtifact],
    repositoryRoot: URL
) throws -> [String: SourceSnapshot] {
    try require(Set(artifacts.map(\.relativePath)) == expectedSourcePaths, "source artifact paths mismatch")
    try require(Set(artifacts.map(\.relativePath)).count == artifacts.count, "duplicate source artifact")
    var snapshots: [String: SourceSnapshot] = [:]
    for artifact in artifacts {
        try requireSHA256(artifact.sha256, context: "source artifact digest")
        try require(artifact.byteCount > 0, "source artifact is empty")
        let url = try resolveRelativePath(
            artifact.relativePath,
            under: repositoryRoot,
            expectedKind: .regularFile,
            context: "source artifact \(artifact.relativePath)"
        )
        let identity = try fileIdentity(at: url)
        try require(
            identity.sha256 == artifact.sha256 && identity.byteCount == artifact.byteCount,
            "source artifact \(artifact.relativePath) identity mismatch"
        )
        snapshots[artifact.relativePath] = SourceSnapshot(url: url, identity: identity)
    }
    try require(
        snapshots["docs/personal-dual-view-runtime-parity-protocol-2026-09-30.md"]?.identity.sha256
            == frozenProtocolSHA256,
        "frozen runtime parity protocol digest mismatch"
    )
    return snapshots
}

private func requireSourcesPreserved(_ snapshots: [String: SourceSnapshot]) throws {
    for (path, snapshot) in snapshots {
        let finalIdentity = try fileIdentity(at: snapshot.url)
        try require(
            finalIdentity == snapshot.identity,
            "source artifact \(path) changed during Swift execution"
        )
    }
}

private func fingerprintPackage(at root: URL) throws -> PackageIdentity {
    let canonicalRoot = try requireCanonicalDirectory(root, context: "model package")
    let keys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey
    ]
    var enumerationFailed = false
    guard let enumerator = FileManager.default.enumerator(
        at: canonicalRoot,
        includingPropertiesForKeys: Array(keys),
        options: [],
        errorHandler: { _, _ in
            enumerationFailed = true
            return false
        }
    ) else {
        throw GateFailure("model package cannot be enumerated")
    }
    let rootPrefix = canonicalRoot.path.hasSuffix("/")
        ? canonicalRoot.path
        : canonicalRoot.path + "/"
    var files: [(String, URL, Int64)] = []
    for case let entry as URL in enumerator {
        let values = try entry.resourceValues(forKeys: keys)
        let relative = String(entry.standardizedFileURL.path.dropFirst(rootPrefix.count))
        if values.isSymbolicLink == true {
            throw GateFailure("model package contains symbolic link \(relative)")
        }
        if values.isDirectory == true { continue }
        guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize >= 0 else {
            throw GateFailure("model package contains unsupported entry \(relative)")
        }
        files.append((relative, entry, Int64(fileSize)))
    }
    try require(!enumerationFailed, "model package enumeration failed")
    files.sort { $0.0 < $1.0 }
    try require(!files.isEmpty, "model package contains no files")
    var treeHasher = SHA256()
    var byteCount: Int64 = 0
    for (relative, fileURL, expectedSize) in files {
        let identity = try streamFileIdentity(fileURL, expectedByteCount: expectedSize)
        treeHasher.update(data: Data(relative.utf8))
        treeHasher.update(data: Data([0]))
        treeHasher.update(data: Data(identity.sha256.utf8))
        treeHasher.update(data: Data([10]))
        byteCount += identity.byteCount
    }
    return PackageIdentity(
        treeSHA256: treeHasher.finalize().map { String(format: "%02x", $0) }.joined(),
        byteCount: byteCount,
        fileCount: files.count
    )
}

private func streamFileIdentity(_ url: URL, expectedByteCount: Int64) throws -> FileIdentity {
    let handle: FileHandle
    do {
        handle = try FileHandle(forReadingFrom: url)
    } catch {
        throw GateFailure("model package file is unreadable")
    }
    defer { try? handle.close() }
    var hasher = SHA256()
    var byteCount: Int64 = 0
    do {
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
            byteCount += Int64(chunk.count)
        }
    } catch {
        throw GateFailure("model package file read failed")
    }
    try require(byteCount == expectedByteCount, "model package changed while reading")
    return FileIdentity(
        sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
        byteCount: byteCount
    )
}

private func requireCanonicalDirectory(_ url: URL, context: String) throws -> URL {
    try require(url.path.hasPrefix("/"), "\(context) path must be absolute")
    let standardized = url.standardizedFileURL
    try require(standardized == url, "\(context) path must be canonical")
    try require(
        standardized.resolvingSymlinksInPath() == standardized,
        "\(context) symlinks are forbidden"
    )
    var isDirectory: ObjCBool = false
    try require(
        FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory)
            && isDirectory.boolValue,
        "\(context) is not a directory"
    )
    return standardized
}

private func requireCanonicalRegularFile(_ url: URL, context: String) throws -> URL {
    try require(url.path.hasPrefix("/"), "\(context) path must be absolute")
    let standardized = url.standardizedFileURL
    try require(standardized == url, "\(context) path must be canonical")
    try require(
        standardized.resolvingSymlinksInPath() == standardized,
        "\(context) symlinks are forbidden"
    )
    let values = try standardized.resourceValues(
        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
    )
    try require(
        values.isRegularFile == true && values.isSymbolicLink != true,
        "\(context) is not a regular file"
    )
    return standardized
}

private func resolveRelativePath(
    _ path: String,
    under root: URL,
    expectedKind: ExpectedPathKind,
    context: String
) throws -> URL {
    try require(
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\"),
        "\(context) has unsafe relative path"
    )
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    try require(
        components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." },
        "\(context) has unsafe path components"
    )
    let candidate = root.appendingPathComponent(path).standardizedFileURL
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    try require(candidate.path.hasPrefix(prefix), "\(context) escapes its root")
    switch expectedKind {
    case .regularFile:
        return try requireCanonicalRegularFile(candidate, context: context)
    case .directory:
        return try requireCanonicalDirectory(candidate, context: context)
    }
}

private func requireNewOutput(_ url: URL) throws {
    try require(url.path.hasPrefix("/"), "output receipt path must be absolute")
    let standardized = url.standardizedFileURL
    try require(standardized == url, "output receipt path must be canonical")
    try require(!FileManager.default.fileExists(atPath: url.path), "output receipt already exists")
    _ = try requireCanonicalDirectory(
        url.deletingLastPathComponent(),
        context: "output receipt parent"
    )
}

private func writeExclusive(_ receipt: GateOutputReceipt, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(receipt)
    do {
        try data.write(to: url, options: [.withoutOverwriting])
    } catch {
        throw GateFailure("output receipt could not be written exclusively")
    }
}

private enum ExportSchema {
    static func validateReceipt(_ data: Data) throws {
        let root = try object(try JSONSerialization.jsonObject(with: data), "export receipt")
        try keys(root, ["schemaVersion", "featureSchemaVersion", "sourceArtifacts", "arms"], "export receipt")
        for (index, artifact) in try array(root["sourceArtifacts"], "sourceArtifacts").enumerated() {
            try keys(
                try object(artifact, "sourceArtifacts[\(index)]"),
                ["relativePath", "sha256", "byteCount"],
                "sourceArtifacts[\(index)]"
            )
        }
        for (index, arm) in try array(root["arms"], "arms").enumerated() {
            try keys(
                try object(arm, "arms[\(index)]"),
                [
                    "modelArm", "weightSeed", "fitSHA256", "vocabularySHA256",
                    "weightsSHA256", "fixtureRelativePath", "fixtureSHA256",
                    "fixtureByteCount", "modelPackageRelativePath",
                    "modelPackageTreeSHA256", "modelPackageByteCount"
                ],
                "arms[\(index)]"
            )
        }
    }

    static func validateFixture(_ data: Data) throws {
        let root = try object(try JSONSerialization.jsonObject(with: data), "fixture")
        try keys(
            root,
            [
                "schemaVersion", "featureSchemaVersion", "modelArm", "weightSeed",
                "fitSHA256", "vocabularySHA256", "weightsSHA256",
                "modelPackageRelativePath", "modelPackageTreeSHA256",
                "modelPackageByteCount", "inputFeatures", "outputFeatures",
                "tolerances", "cases", "invarianceChecks"
            ],
            "fixture"
        )
        for listName in ["inputFeatures", "outputFeatures"] {
            for (index, value) in try array(root[listName], listName).enumerated() {
                try keys(
                    try object(value, "\(listName)[\(index)]"),
                    ["name", "shape", "dataType"],
                    "\(listName)[\(index)]"
                )
            }
        }
        try keys(
            try object(root["tolerances"], "tolerances"),
            ["personalEmbeddingMaximumAbsoluteError", "genericLogitsMaximumAbsoluteError"],
            "tolerances"
        )
        let invariance = try object(root["invarianceChecks"], "invarianceChecks")
        try keys(invariance, ["timingProbe", "inactiveInputProbe"], "invarianceChecks")
        try keys(
            try object(invariance["timingProbe"], "invarianceChecks.timingProbe"),
            ["trajectoryChannel5", "trajectoryChannel6"],
            "invarianceChecks.timingProbe"
        )
        try keys(
            try object(invariance["inactiveInputProbe"], "invarianceChecks.inactiveInputProbe"),
            ["zeroRasterForArms", "zeroTrajectoryForArms"],
            "invarianceChecks.inactiveInputProbe"
        )
        for (caseIndex, value) in try array(root["cases"], "cases").enumerated() {
            let testCase = try object(value, "cases[\(caseIndex)]")
            try keys(testCase, ["caseID", "rawStrokes", "expected"], "cases[\(caseIndex)]")
            for (strokeIndex, strokeValue) in try array(testCase["rawStrokes"], "rawStrokes").enumerated() {
                let stroke = try object(strokeValue, "rawStrokes[\(strokeIndex)]")
                try keys(stroke, ["creationTimeOffset", "points"], "raw stroke")
                for pointValue in try array(stroke["points"], "points") {
                    try keys(try object(pointValue, "point"), ["x", "y", "timeOffset"], "point")
                }
            }
            let expected = try object(testCase["expected"], "expected")
            try keys(
                expected,
                [
                    "trajectoryFloat32LEBase64", "trajectorySHA256",
                    "rasterUInt8Base64", "rasterSHA256", "rasterFloat32LEBase64",
                    "rasterFloat32SHA256", "torch", "coreMLPython", "parity",
                    "timingProbe", "inactiveInputProbe"
                ],
                "expected"
            )
            try validateVectorObject(expected["torch"], "expected.torch")
            try validateVectorObject(expected["coreMLPython"], "expected.coreMLPython")
            try validateParityObject(expected["parity"], "expected.parity")
            try validateProbeObject(expected["timingProbe"], "expected.timingProbe")
            if !(expected["inactiveInputProbe"] is NSNull) {
                try validateProbeObject(
                    expected["inactiveInputProbe"],
                    "expected.inactiveInputProbe"
                )
            }
        }
    }

    private static func validateVectorObject(_ value: Any?, _ context: String) throws {
        try keys(
            try object(value, context),
            ["personalEmbedding", "genericLogits", "firstGenericArgmax"],
            context
        )
    }

    private static func validateParityObject(_ value: Any?, _ context: String) throws {
        try keys(
            try object(value, context),
            [
                "embeddingMaximumAbsoluteError", "logitsMaximumAbsoluteError",
                "firstGenericArgmaxEqual"
            ],
            context
        )
    }

    private static func validateProbeObject(_ value: Any?, _ context: String) throws {
        let probe = try object(value, context)
        try keys(probe, ["torch", "coreMLPython", "parity", "invariance"], context)
        try validateVectorObject(probe["torch"], "\(context).torch")
        try validateVectorObject(probe["coreMLPython"], "\(context).coreMLPython")
        try validateParityObject(probe["parity"], "\(context).parity")
        try keys(
            try object(probe["invariance"], "\(context).invariance"),
            [
                "torchEmbeddingMaximumAbsoluteError", "torchLogitsMaximumAbsoluteError",
                "torchFirstGenericArgmaxEqual",
                "coreMLPythonEmbeddingMaximumAbsoluteError",
                "coreMLPythonLogitsMaximumAbsoluteError",
                "coreMLPythonFirstGenericArgmaxEqual"
            ],
            "\(context).invariance"
        )
    }

    private static func object(_ value: Any?, _ context: String) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw GateFailure("\(context) must be an object")
        }
        return object
    }

    private static func array(_ value: Any?, _ context: String) throws -> [Any] {
        guard let array = value as? [Any] else {
            throw GateFailure("\(context) must be an array")
        }
        return array
    }

    private static func keys(_ object: [String: Any], _ expected: Set<String>, _ context: String) throws {
        try require(Set(object.keys) == expected, "\(context) has missing or unknown fields")
    }
}

/// Foundation accepts repeated object keys. The gate rejects them before
/// decoding so a fixture cannot silently replace an earlier bound value.
private struct StrictJSON {
    private let bytes: [UInt8]
    private var index = 0

    static func validate(_ data: Data, context: String) throws {
        guard data.count <= 20_000_000 else { throw GateFailure("\(context) exceeds JSON budget") }
        var parser = StrictJSON(bytes: Array(data))
        try parser.skipWhitespace()
        try parser.parseValue(depth: 0)
        try parser.skipWhitespace()
        try require(parser.index == parser.bytes.count, "\(context) has trailing JSON bytes")
    }

    private mutating func parseValue(depth: Int) throws {
        try require(depth <= 128, "JSON nesting exceeds limit")
        try skipWhitespace()
        guard let byte = current else { throw GateFailure("truncated JSON") }
        switch byte {
        case 123: try parseObject(depth: depth + 1)
        case 91: try parseArray(depth: depth + 1)
        case 34: _ = try parseString()
        case 116: try consume("true")
        case 102: try consume("false")
        case 110: try consume("null")
        default: try parseNumber()
        }
    }

    private mutating func parseObject(depth: Int) throws {
        index += 1
        try skipWhitespace()
        if current == 125 { index += 1; return }
        var keys: Set<String> = []
        while true {
            try skipWhitespace()
            let key = try parseString()
            try require(keys.insert(key).inserted, "JSON object contains duplicate key \(key)")
            try skipWhitespace()
            try require(current == 58, "JSON object key lacks colon")
            index += 1
            try parseValue(depth: depth)
            try skipWhitespace()
            if current == 125 { index += 1; return }
            try require(current == 44, "JSON object lacks comma")
            index += 1
        }
    }

    private mutating func parseArray(depth: Int) throws {
        index += 1
        try skipWhitespace()
        if current == 93 { index += 1; return }
        while true {
            try parseValue(depth: depth)
            try skipWhitespace()
            if current == 93 { index += 1; return }
            try require(current == 44, "JSON array lacks comma")
            index += 1
        }
    }

    private mutating func parseString() throws -> String {
        try require(current == 34, "JSON object key is not a string")
        let start = index
        index += 1
        var escaped = false
        while let byte = current {
            if escaped {
                if byte == 117 {
                    index += 1
                    for _ in 0..<4 {
                        guard let hex = current,
                              (48...57).contains(hex) || (65...70).contains(hex)
                                || (97...102).contains(hex) else {
                            throw GateFailure("invalid JSON unicode escape")
                        }
                        index += 1
                    }
                    escaped = false
                    continue
                }
                try require([34, 47, 92, 98, 102, 110, 114, 116].contains(byte), "invalid JSON escape")
                escaped = false
                index += 1
                continue
            }
            if byte == 92 { escaped = true; index += 1; continue }
            if byte == 34 {
                index += 1
                let token = Data(bytes[start..<index])
                do {
                    return try JSONDecoder().decode(String.self, from: token)
                } catch {
                    throw GateFailure("invalid JSON string")
                }
            }
            try require(byte >= 32, "JSON string contains control byte")
            index += 1
        }
        throw GateFailure("unterminated JSON string")
    }

    private mutating func parseNumber() throws {
        let start = index
        if current == 45 { index += 1 }
        if current == 48 {
            index += 1
        } else {
            try require(current.map { (49...57).contains($0) } == true, "invalid JSON number")
            while current.map({ (48...57).contains($0) }) == true { index += 1 }
        }
        if current == 46 {
            index += 1
            try require(current.map { (48...57).contains($0) } == true, "invalid JSON fraction")
            while current.map({ (48...57).contains($0) }) == true { index += 1 }
        }
        if current == 101 || current == 69 {
            index += 1
            if current == 43 || current == 45 { index += 1 }
            try require(current.map { (48...57).contains($0) } == true, "invalid JSON exponent")
            while current.map({ (48...57).contains($0) }) == true { index += 1 }
        }
        try require(index > start, "invalid JSON value")
    }

    private mutating func consume(_ text: StaticString) throws {
        for byte in text.withUTF8Buffer({ Array($0) }) {
            try require(current == byte, "invalid JSON literal")
            index += 1
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = current, [9, 10, 13, 32].contains(byte) { index += 1 }
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }
}

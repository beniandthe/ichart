import CoreML
import CoreVideo
import CryptoKit
import Foundation

enum ChordInkCoreMLNumericDataType: Equatable, Sendable {
    case float16
    case float32
    case float64
    case int32
    case unsupported(rawValue: Int)

    init(_ dataType: MLMultiArrayDataType) {
        switch dataType {
        case .float16: self = .float16
        case .float32: self = .float32
        case .double: self = .float64
        case .int32: self = .int32
        default: self = .unsupported(rawValue: dataType.rawValue)
        }
    }
}

enum ChordInkCoreMLFeatureCategory: Equatable, Sendable {
    case multiArray
    case image
    case unsupported(rawValue: Int)
}

enum ChordInkCoreMLFeatureDescriptionSnapshot: Equatable, Sendable {
    case multiArray(
        shape: [Int],
        dataType: ChordInkCoreMLNumericDataType,
        isOptional: Bool
    )
    case image(
        width: Int,
        height: Int,
        pixelFormat: OSType,
        isOptional: Bool
    )
    case unsupported(
        typeRawValue: Int,
        isOptional: Bool
    )

    var category: ChordInkCoreMLFeatureCategory {
        switch self {
        case .multiArray: return .multiArray
        case .image: return .image
        case .unsupported(let typeRawValue, _):
            return .unsupported(rawValue: typeRawValue)
        }
    }

    var isOptional: Bool {
        switch self {
        case .multiArray(_, _, let isOptional),
             .image(_, _, _, let isOptional),
             .unsupported(_, let isOptional):
            return isOptional
        }
    }
}

struct ChordInkCoreMLModelDescriptionSnapshot: Equatable, Sendable {
    let inputs: [String: ChordInkCoreMLFeatureDescriptionSnapshot]
    let outputs: [String: ChordInkCoreMLFeatureDescriptionSnapshot]
}

struct ChordInkCompiledCoreMLArtifactFingerprint: Equatable, Sendable {
    let sha256: String
    let byteCount: Int64
}

enum ChordInkCoreMLAdapterError: Error, Equatable, Sendable {
    case missingResource(name: String, extension: String)
    case unreadableManifest
    case malformedManifest
    case compiledModelArtifactIsNotDirectory
    case compiledModelArtifactContainsSymbolicLink(path: String)
    case compiledModelArtifactContainsUnsupportedEntry(path: String)
    case compiledModelArtifactUnreadable(path: String)
    case compiledModelArtifactChangedWhileReading(path: String)
    case compiledModelLoadFailed
    case inputNamesMismatch(expected: [String], actual: [String])
    case outputNamesMismatch(expected: [String], actual: [String])
    case featureTypeMismatch(
        name: String,
        expected: ChordInkCoreMLFeatureCategory,
        actual: ChordInkCoreMLFeatureCategory
    )
    case featureOptionalityMismatch(name: String, expected: Bool, actual: Bool)
    case featureShapeMismatch(name: String, expected: [Int], actual: [Int])
    case featureDataTypeMismatch(
        name: String,
        expected: ChordInkCoreMLNumericDataType,
        actual: ChordInkCoreMLNumericDataType
    )
    case unsupportedMultiArrayNumericType(ChordInkNumericType)
    case imagePixelFormatMismatch(name: String, expected: OSType, actual: OSType)
    case trajectoryArrayAllocationFailed
    case pixelBufferAllocationFailed(status: CVReturn)
    case pixelBufferLockFailed(status: CVReturn)
    case pixelBufferHasInvalidLayout(bytesPerRow: Int, width: Int)
    case inputProviderConstructionFailed
    case predictionFailed
    case predictionOutputNamesMismatch(expected: [String], actual: [String])
    case missingOutput(name: String)
    case undefinedOutput(name: String)
    case outputTypeMismatch(name: String)
    case outputShapeMismatch(name: String, expected: [Int], actual: [Int])
    case outputDataTypeMismatch(
        name: String,
        expected: ChordInkCoreMLNumericDataType,
        actual: ChordInkCoreMLNumericDataType
    )
    case nonFiniteOutput(name: String, index: Int)
}

/// Platform boundary for the frozen learned-model contracts.
///
/// This adapter has no production authority. It will only construct a runtime
/// after validating the detached manifest identity, the exact compiled model
/// directory fingerprint, and the complete Core ML model description.
final class ChordInkCoreMLModelRuntime: ChordInkLearnedModelRuntime {
    struct BundleResources: Equatable, Sendable {
        let manifestName: String
        let compiledModelName: String

        init(manifestName: String, compiledModelName: String) {
            self.manifestName = manifestName
            self.compiledModelName = compiledModelName
        }
    }

    let manifest: ChordInkModelArtifactManifest
    let loadedArtifactIdentity: ChordInkLoadedModelArtifactIdentity

    private let model: MLModel

    static func load(
        resources: BundleResources,
        detachedManifestSHA256: String,
        bundle: Bundle = .main,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws -> ChordInkCoreMLModelRuntime {
        guard let manifestURL = bundle.url(
            forResource: resources.manifestName,
            withExtension: "json"
        ) else {
            throw ChordInkCoreMLAdapterError.missingResource(
                name: resources.manifestName,
                extension: "json"
            )
        }
        guard let compiledModelURL = bundle.url(
            forResource: resources.compiledModelName,
            withExtension: "mlmodelc"
        ) else {
            throw ChordInkCoreMLAdapterError.missingResource(
                name: resources.compiledModelName,
                extension: "mlmodelc"
            )
        }
        return try load(
            manifestURL: manifestURL,
            detachedManifestSHA256: detachedManifestSHA256,
            compiledModelURL: compiledModelURL,
            configuration: configuration
        )
    }

    static func load(
        manifestURL: URL,
        detachedManifestSHA256: String,
        compiledModelURL: URL,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws -> ChordInkCoreMLModelRuntime {
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        } catch {
            throw ChordInkCoreMLAdapterError.unreadableManifest
        }

        let manifest: ChordInkModelArtifactManifest
        do {
            manifest = try JSONDecoder().decode(
                ChordInkModelArtifactManifest.self,
                from: manifestData
            )
        } catch {
            throw ChordInkCoreMLAdapterError.malformedManifest
        }
        try manifest.validate()

        let loadedArtifactIdentity = try verifiedArtifactIdentity(
            manifest: manifest,
            detachedManifestSHA256: detachedManifestSHA256,
            compiledModelURL: compiledModelURL
        )

        let model: MLModel
        do {
            model = try MLModel(
                contentsOf: compiledModelURL,
                configuration: configuration
            )
        } catch {
            throw ChordInkCoreMLAdapterError.compiledModelLoadFailed
        }

        let snapshot = try modelDescriptionSnapshot(model.modelDescription)
        try validateModelDescription(snapshot, against: manifest)
        return ChordInkCoreMLModelRuntime(
            manifest: manifest,
            loadedArtifactIdentity: loadedArtifactIdentity,
            model: model
        )
    }

    private init(
        manifest: ChordInkModelArtifactManifest,
        loadedArtifactIdentity: ChordInkLoadedModelArtifactIdentity,
        model: MLModel
    ) {
        self.manifest = manifest
        self.loadedArtifactIdentity = loadedArtifactIdentity
        self.model = model
    }

    func predict(input: ChordInkLearnedModelInput) throws -> ChordInkLearnedFactorOutput {
        try manifest.validate()
        try loadedArtifactIdentity.validate(against: manifest)
        try input.validate(for: manifest)

        let provider = try Self.makeInputProvider(input: input, manifest: manifest)
        let outputProvider: any MLFeatureProvider
        do {
            outputProvider = try model.prediction(from: provider)
        } catch {
            throw ChordInkCoreMLAdapterError.predictionFailed
        }
        return try Self.factorOutput(from: outputProvider, manifest: manifest)
    }
}

extension ChordInkCoreMLModelRuntime {
    /// Fingerprints the exact compiled directory consumed by `MLModel`.
    ///
    /// The digest framing is versioned and deterministic: a magic prefix,
    /// followed by every regular file in ascending relative-path order, with
    /// each UTF-8 path and content length encoded as big-endian UInt64 values.
    /// `byteCount` is the sum of file content bytes. Symbolic links and special
    /// filesystem entries are rejected rather than followed.
    static func fingerprintCompiledModel(
        at directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChordInkCompiledCoreMLArtifactFingerprint {
        let rootURL = directoryURL.standardizedFileURL
        let rootValues: URLResourceValues
        do {
            rootValues = try rootURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw ChordInkCoreMLAdapterError.compiledModelArtifactIsNotDirectory
        }
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw ChordInkCoreMLAdapterError.compiledModelArtifactIsNotDirectory
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        var enumerationErrorPath: String?
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { url, _ in
                enumerationErrorPath = url.path
                return false
            }
        ) else {
            throw ChordInkCoreMLAdapterError.compiledModelArtifactIsNotDirectory
        }

        let rootPathPrefix = rootURL.path.hasSuffix("/")
            ? rootURL.path
            : rootURL.path + "/"
        var entries: [(relativePath: String, url: URL, size: Int)] = []

        for case let entryURL as URL in enumerator {
            let standardizedURL = entryURL.standardizedFileURL
            guard standardizedURL.path.hasPrefix(rootPathPrefix) else {
                throw ChordInkCoreMLAdapterError.compiledModelArtifactContainsUnsupportedEntry(
                    path: standardizedURL.lastPathComponent
                )
            }
            let relativePath = String(standardizedURL.path.dropFirst(rootPathPrefix.count))
            let values: URLResourceValues
            do {
                values = try standardizedURL.resourceValues(forKeys: keys)
            } catch {
                throw ChordInkCoreMLAdapterError.compiledModelArtifactUnreadable(
                    path: relativePath
                )
            }
            if values.isSymbolicLink == true {
                throw ChordInkCoreMLAdapterError.compiledModelArtifactContainsSymbolicLink(
                    path: relativePath
                )
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize >= 0 else {
                throw ChordInkCoreMLAdapterError.compiledModelArtifactContainsUnsupportedEntry(
                    path: relativePath
                )
            }
            entries.append((relativePath, standardizedURL, fileSize))
        }
        if let enumerationErrorPath {
            throw ChordInkCoreMLAdapterError.compiledModelArtifactUnreadable(
                path: enumerationErrorPath
            )
        }

        entries.sort { $0.relativePath < $1.relativePath }
        var hasher = SHA256()
        hasher.update(data: Data("ichart-compiled-coreml-directory-v1\0".utf8))
        var totalByteCount: Int64 = 0

        for entry in entries {
            let pathData = Data(entry.relativePath.utf8)
            update(&hasher, unsignedInteger: UInt64(pathData.count))
            hasher.update(data: pathData)
            update(&hasher, unsignedInteger: UInt64(entry.size))

            let fileHandle: FileHandle
            do {
                fileHandle = try FileHandle(forReadingFrom: entry.url)
            } catch {
                throw ChordInkCoreMLAdapterError.compiledModelArtifactUnreadable(
                    path: entry.relativePath
                )
            }
            defer { try? fileHandle.close() }

            var observedSize = 0
            do {
                while let chunk = try fileHandle.read(upToCount: 1_048_576), !chunk.isEmpty {
                    observedSize += chunk.count
                    hasher.update(data: chunk)
                }
            } catch {
                throw ChordInkCoreMLAdapterError.compiledModelArtifactUnreadable(
                    path: entry.relativePath
                )
            }
            guard observedSize == entry.size else {
                throw ChordInkCoreMLAdapterError.compiledModelArtifactChangedWhileReading(
                    path: entry.relativePath
                )
            }
            guard totalByteCount <= Int64.max - Int64(observedSize) else {
                throw ChordInkCoreMLAdapterError.compiledModelArtifactUnreadable(
                    path: entry.relativePath
                )
            }
            totalByteCount += Int64(observedSize)
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return ChordInkCompiledCoreMLArtifactFingerprint(
            sha256: digest,
            byteCount: totalByteCount
        )
    }

    static func verifiedArtifactIdentity(
        manifest: ChordInkModelArtifactManifest,
        detachedManifestSHA256: String,
        compiledModelURL: URL
    ) throws -> ChordInkLoadedModelArtifactIdentity {
        let fingerprint = try fingerprintCompiledModel(at: compiledModelURL)
        let identity = ChordInkLoadedModelArtifactIdentity(
            manifestArtifactSHA256: detachedManifestSHA256,
            modelArtifactSHA256: fingerprint.sha256,
            modelArtifactByteCount: fingerprint.byteCount
        )
        try identity.validate(against: manifest)
        return identity
    }

    static func modelDescriptionSnapshot(
        _ description: MLModelDescription
    ) throws -> ChordInkCoreMLModelDescriptionSnapshot {
        ChordInkCoreMLModelDescriptionSnapshot(
            inputs: try description.inputDescriptionsByName.mapValues(featureSnapshot),
            outputs: try description.outputDescriptionsByName.mapValues(featureSnapshot)
        )
    }

    static func validateModelDescription(
        _ snapshot: ChordInkCoreMLModelDescriptionSnapshot,
        against manifest: ChordInkModelArtifactManifest
    ) throws {
        // This validates the v2 numeric type, layout, scaling, value semantics,
        // ranges, and per-channel contracts before any Core ML metadata is
        // trusted. Model descriptions can expose shape/type, but not all of
        // those semantic bindings.
        try manifest.validate()
        let trajectoryDataType = try coreMLDataType(for: manifest.trajectoryInput.numericType)
        let outputDataTypes = try Dictionary(
            uniqueKeysWithValues: manifest.outputHeads.map { head in
                (head.name, try coreMLDataType(for: head.numericType))
            }
        )
        let expectedInputs: [String: ChordInkCoreMLFeatureDescriptionSnapshot] = [
            manifest.trajectoryInput.name: .multiArray(
                shape: manifest.trajectoryInput.shape,
                dataType: trajectoryDataType,
                isOptional: false
            ),
            manifest.rasterInput.name: .image(
                width: ChordInkFeatureSchema.rasterWidth,
                height: ChordInkFeatureSchema.rasterHeight,
                pixelFormat: kCVPixelFormatType_OneComponent8,
                isOptional: false
            )
        ]
        let expectedOutputs = Dictionary(
            uniqueKeysWithValues: manifest.outputHeads.map { head in
                (
                    head.name,
                    ChordInkCoreMLFeatureDescriptionSnapshot.multiArray(
                        shape: head.shape,
                        dataType: outputDataTypes[head.name]!,
                        isOptional: false
                    )
                )
            }
        )

        try validateNames(
            expected: expectedInputs.keys,
            actual: snapshot.inputs.keys,
            mismatch: ChordInkCoreMLAdapterError.inputNamesMismatch
        )
        try validateNames(
            expected: expectedOutputs.keys,
            actual: snapshot.outputs.keys,
            mismatch: ChordInkCoreMLAdapterError.outputNamesMismatch
        )
        for name in expectedInputs.keys.sorted() {
            try validateFeature(
                name: name,
                expected: expectedInputs[name]!,
                actual: snapshot.inputs[name]!
            )
        }
        for name in expectedOutputs.keys.sorted() {
            try validateFeature(
                name: name,
                expected: expectedOutputs[name]!,
                actual: snapshot.outputs[name]!
            )
        }
    }

    static func makeInputProvider(
        input: ChordInkLearnedModelInput,
        manifest: ChordInkModelArtifactManifest
    ) throws -> MLDictionaryFeatureProvider {
        try manifest.validate()
        try input.validate(for: manifest)

        let trajectory: MLMultiArray
        do {
            trajectory = try MLMultiArray(
                shape: manifest.trajectoryInput.shape.map { NSNumber(value: $0) },
                dataType: .float32
            )
        } catch {
            throw ChordInkCoreMLAdapterError.trajectoryArrayAllocationFailed
        }
        for (index, value) in input.trajectory.values.enumerated() {
            trajectory[index] = NSNumber(value: value)
        }

        let raster = try makeRasterPixelBuffer(input.raster)
        let features: [String: MLFeatureValue] = [
            manifest.trajectoryInput.name: MLFeatureValue(multiArray: trajectory),
            manifest.rasterInput.name: MLFeatureValue(pixelBuffer: raster)
        ]
        do {
            return try MLDictionaryFeatureProvider(dictionary: features)
        } catch {
            throw ChordInkCoreMLAdapterError.inputProviderConstructionFailed
        }
    }

    static func makeRasterPixelBuffer(
        _ raster: ChordInkRasterFeaturePlane
    ) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        let createStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            raster.width,
            raster.height,
            kCVPixelFormatType_OneComponent8,
            attributes,
            &optionalBuffer
        )
        guard createStatus == kCVReturnSuccess, let buffer = optionalBuffer else {
            throw ChordInkCoreMLAdapterError.pixelBufferAllocationFailed(status: createStatus)
        }

        let lockStatus = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw ChordInkCoreMLAdapterError.pixelBufferLockFailed(status: lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard bytesPerRow >= raster.width,
              let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw ChordInkCoreMLAdapterError.pixelBufferHasInvalidLayout(
                bytesPerRow: bytesPerRow,
                width: raster.width
            )
        }
        memset(baseAddress, 0, bytesPerRow * raster.height)
        raster.pixels.withUnsafeBytes { pixels in
            guard let pixelBaseAddress = pixels.baseAddress else { return }
            for row in 0..<raster.height {
                memcpy(
                    baseAddress.advanced(by: row * bytesPerRow),
                    pixelBaseAddress.advanced(by: row * raster.width),
                    raster.width
                )
            }
        }
        return buffer
    }

    static func factorOutput(
        from provider: any MLFeatureProvider,
        manifest: ChordInkModelArtifactManifest
    ) throws -> ChordInkLearnedFactorOutput {
        try manifest.validate()
        let expectedNames = manifest.outputHeads.map(\.name).sorted()
        let actualNames = provider.featureNames.sorted()
        guard expectedNames == actualNames else {
            throw ChordInkCoreMLAdapterError.predictionOutputNamesMismatch(
                expected: expectedNames,
                actual: actualNames
            )
        }

        return ChordInkLearnedFactorOutput(
            contractVersion: manifest.outputContractVersion,
            validity: try logits(
                named: ChordInkLearnedOutputContract.validityHeadName,
                labels: ChordInkValidityFactorLabel.allCases,
                provider: provider,
                manifest: manifest
            ),
            kind: try logits(
                named: ChordInkLearnedOutputContract.kindHeadName,
                labels: ChordInkKindFactorLabel.allCases,
                provider: provider,
                manifest: manifest
            ),
            rootLetter: try logits(
                named: ChordInkLearnedOutputContract.rootLetterHeadName,
                labels: ChordNotation.Letter.allCases,
                provider: provider,
                manifest: manifest
            ),
            rootAccidental: try logits(
                named: ChordInkLearnedOutputContract.rootAccidentalHeadName,
                labels: ChordInkAccidentalFactorLabel.allCases,
                provider: provider,
                manifest: manifest
            ),
            quality: try logits(
                named: ChordInkLearnedOutputContract.qualityHeadName,
                labels: ChordNotation.Form.allCases,
                provider: provider,
                manifest: manifest
            ),
            extensionTone: try logits(
                named: ChordInkLearnedOutputContract.extensionHeadName,
                labels: ChordInkExtensionFactorLabel.allCases,
                provider: provider,
                manifest: manifest
            ),
            alterations: try logits(
                named: ChordInkLearnedOutputContract.alterationHeadName,
                labels: ChordNotation.Alteration.allCases,
                provider: provider,
                manifest: manifest
            ),
            slashPresence: try logits(
                named: ChordInkLearnedOutputContract.slashPresenceHeadName,
                labels: ChordInkSlashPresenceFactorLabel.allCases,
                provider: provider,
                manifest: manifest
            ),
            slashBassLetter: try logits(
                named: ChordInkLearnedOutputContract.slashBassLetterHeadName,
                labels: ChordNotation.Letter.allCases,
                provider: provider,
                manifest: manifest
            ),
            slashBassAccidental: try logits(
                named: ChordInkLearnedOutputContract.slashBassAccidentalHeadName,
                labels: ChordInkAccidentalFactorLabel.allCases,
                provider: provider,
                manifest: manifest
            )
        )
    }
}

private extension ChordInkCoreMLModelRuntime {
    static func coreMLDataType(
        for numericType: ChordInkNumericType
    ) throws -> ChordInkCoreMLNumericDataType {
        switch numericType {
        case .float32:
            return .float32
        case .uint8:
            throw ChordInkCoreMLAdapterError.unsupportedMultiArrayNumericType(numericType)
        }
    }

    static func update(_ hasher: inout SHA256, unsignedInteger: UInt64) {
        var bigEndian = unsignedInteger.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            hasher.update(bufferPointer: bytes)
        }
    }

    static func featureSnapshot(
        _ feature: MLFeatureDescription
    ) throws -> ChordInkCoreMLFeatureDescriptionSnapshot {
        switch feature.type {
        case .multiArray:
            guard let constraint = feature.multiArrayConstraint else {
                return .unsupported(
                    typeRawValue: feature.type.rawValue,
                    isOptional: feature.isOptional
                )
            }
            return .multiArray(
                shape: constraint.shape.map(\.intValue),
                dataType: ChordInkCoreMLNumericDataType(constraint.dataType),
                isOptional: feature.isOptional
            )
        case .image:
            guard let constraint = feature.imageConstraint else {
                return .unsupported(
                    typeRawValue: feature.type.rawValue,
                    isOptional: feature.isOptional
                )
            }
            return .image(
                width: constraint.pixelsWide,
                height: constraint.pixelsHigh,
                pixelFormat: constraint.pixelFormatType,
                isOptional: feature.isOptional
            )
        default:
            return .unsupported(
                typeRawValue: feature.type.rawValue,
                isOptional: feature.isOptional
            )
        }
    }

    static func validateNames<Keys: Collection>(
        expected: Keys,
        actual: Keys,
        mismatch: ([String], [String]) -> ChordInkCoreMLAdapterError
    ) throws where Keys.Element == String {
        let expectedNames = expected.sorted()
        let actualNames = actual.sorted()
        guard expectedNames == actualNames else {
            throw mismatch(expectedNames, actualNames)
        }
    }

    static func validateFeature(
        name: String,
        expected: ChordInkCoreMLFeatureDescriptionSnapshot,
        actual: ChordInkCoreMLFeatureDescriptionSnapshot
    ) throws {
        guard expected.category == actual.category else {
            throw ChordInkCoreMLAdapterError.featureTypeMismatch(
                name: name,
                expected: expected.category,
                actual: actual.category
            )
        }
        guard expected.isOptional == actual.isOptional else {
            throw ChordInkCoreMLAdapterError.featureOptionalityMismatch(
                name: name,
                expected: expected.isOptional,
                actual: actual.isOptional
            )
        }

        switch (expected, actual) {
        case let (
            .multiArray(expectedShape, expectedType, _),
            .multiArray(actualShape, actualType, _)
        ):
            guard expectedShape == actualShape else {
                throw ChordInkCoreMLAdapterError.featureShapeMismatch(
                    name: name,
                    expected: expectedShape,
                    actual: actualShape
                )
            }
            guard expectedType == actualType else {
                throw ChordInkCoreMLAdapterError.featureDataTypeMismatch(
                    name: name,
                    expected: expectedType,
                    actual: actualType
                )
            }
        case let (
            .image(expectedWidth, expectedHeight, expectedPixelFormat, _),
            .image(actualWidth, actualHeight, actualPixelFormat, _)
        ):
            let expectedShape = [expectedHeight, expectedWidth]
            let actualShape = [actualHeight, actualWidth]
            guard expectedShape == actualShape else {
                throw ChordInkCoreMLAdapterError.featureShapeMismatch(
                    name: name,
                    expected: expectedShape,
                    actual: actualShape
                )
            }
            guard expectedPixelFormat == actualPixelFormat else {
                throw ChordInkCoreMLAdapterError.imagePixelFormatMismatch(
                    name: name,
                    expected: expectedPixelFormat,
                    actual: actualPixelFormat
                )
            }
        default:
            throw ChordInkCoreMLAdapterError.featureTypeMismatch(
                name: name,
                expected: expected.category,
                actual: actual.category
            )
        }
    }

    static func logits<Label>(
        named name: String,
        labels: [Label],
        provider: any MLFeatureProvider,
        manifest: ChordInkModelArtifactManifest
    ) throws -> ChordInkFactorLogits<Label>
    where Label: Hashable & Sendable {
        guard let head = manifest.outputHeads.first(where: { $0.name == name }) else {
            throw ChordInkCoreMLAdapterError.missingOutput(name: name)
        }
        guard let featureValue = provider.featureValue(for: name) else {
            throw ChordInkCoreMLAdapterError.missingOutput(name: name)
        }
        guard !featureValue.isUndefined else {
            throw ChordInkCoreMLAdapterError.undefinedOutput(name: name)
        }
        guard featureValue.type == .multiArray,
              let array = featureValue.multiArrayValue else {
            throw ChordInkCoreMLAdapterError.outputTypeMismatch(name: name)
        }
        let actualShape = array.shape.map(\.intValue)
        guard actualShape == head.shape else {
            throw ChordInkCoreMLAdapterError.outputShapeMismatch(
                name: name,
                expected: head.shape,
                actual: actualShape
            )
        }
        let actualDataType = ChordInkCoreMLNumericDataType(array.dataType)
        let expectedDataType = try coreMLDataType(for: head.numericType)
        guard actualDataType == expectedDataType else {
            throw ChordInkCoreMLAdapterError.outputDataTypeMismatch(
                name: name,
                expected: expectedDataType,
                actual: actualDataType
            )
        }
        guard labels.count == array.count else {
            throw ChordInkCoreMLAdapterError.outputShapeMismatch(
                name: name,
                expected: head.shape,
                actual: actualShape
            )
        }

        var values: [Label: Double] = [:]
        values.reserveCapacity(labels.count)
        for (index, label) in labels.enumerated() {
            let value = array[index].doubleValue
            guard value.isFinite else {
                throw ChordInkCoreMLAdapterError.nonFiniteOutput(
                    name: name,
                    index: index
                )
            }
            values[label] = value
        }
        return ChordInkFactorLogits(values)
    }
}

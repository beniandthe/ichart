#if DEBUG && canImport(CoreML)
import CoreML
import CryptoKit
import Foundation

/// An explicitly bundled, pinned development artifact. No downloads, profile
/// writes, alternative engine, dynamic model selection or production fallback.
final class PersonalInkVisualEncoder: PersonalInkVisualEncoding {
    static let manifestSHA256 = "4b60c912270201408123038ea6a1fe105a4462045d3d5760c62d7fcad1198e60"
    static let anchoredManifestSHA256 = "d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1"
    static let anchorSHA256 = "e1670f855301f2fdb7970d2a4d23a30ffd82e76a242347867751b6c4c78a76ed"
    struct Manifest: Decodable {
        let version: String
        let researchOnly: Bool
        let packageSHA256: String
        let weightsSHA256: String
        let vocabulary: [String]
        let featureCount: Int
        let anchorSHA256: String?
        let personalLearningVersion: String?
    }
    let identity: String
    let vocabulary: [String]
    let anchorBank: PersonalInkAnchorBank?
    private let model: MLModel

    static func bundledDirectory(bundle: Bundle = .main) -> URL? {
        guard let root = bundle.resourceURL?.appendingPathComponent("PersonalMLComparison"),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) else { return nil }
        return root
    }

    init(directory: URL) throws {
        let failure = PersonalInkLearnedComparison.Failure.invalidEncoder
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max < 32_768 else { throw failure }
        let data = try Data(contentsOf: manifestURL)
        guard [Self.manifestSHA256, Self.anchoredManifestSHA256].contains(Self.digest(data)) else { throw failure }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard ["personal-visual-comparison-v1", "personal-visual-comparison-v2"].contains(manifest.version), manifest.researchOnly,
              manifest.featureCount == 128, manifest.vocabulary.count == 97,
              Set(manifest.vocabulary).count == 97 else { throw failure }
        if manifest.version == "personal-visual-comparison-v2" {
            guard manifest.anchorSHA256 == Self.anchorSHA256,
                  manifest.personalLearningVersion == PersonalInkAnchoredResidualHead.version else { throw failure }
            let anchorURL = directory.appendingPathComponent("public-anchors.json")
            let properties = try anchorURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard properties.isSymbolicLink != true, (properties.fileSize ?? Int.max) < 1_000_000 else { throw failure }
            let anchorData = try Data(contentsOf: anchorURL)
            guard Self.digest(anchorData) == Self.anchorSHA256 else { throw failure }
            let bank = try JSONDecoder().decode(PersonalInkAnchorBank.self, from: anchorData)
            guard bank.vocabulary == manifest.vocabulary, bank.features.count == 97,
                  bank.features.allSatisfy({ row in row.count == 128 && row.allSatisfy(\.isFinite)
                      && abs(row.reduce(0) { $0 + $1 * $1 } - 1) <= 1e-3 }) else { throw failure }
            anchorBank = bank
        } else {
            guard manifest.anchorSHA256 == nil, manifest.personalLearningVersion == nil else { throw failure }
            anchorBank = nil
        }
        let package = directory.appendingPathComponent("PersonalVisualEncoderResearch.mlpackage")
        guard try Self.packageDigest(package) == manifest.packageSHA256 else { throw failure }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: MLModel.compileModel(at: package), configuration: configuration)
        let description = model.modelDescription
        guard Set(description.inputDescriptionsByName.keys) == ["inkRaster"],
              Set(description.outputDescriptionsByName.keys) == ["personalEmbedding", "genericLogits"],
              Self.valid(description.inputDescriptionsByName["inkRaster"], shape: [1, 1, 96, 256]),
              Self.valid(description.outputDescriptionsByName["personalEmbedding"], shape: [1, 128]),
              Self.valid(description.outputDescriptionsByName["genericLogits"], shape: [1, 97]),
              let metadata = description.metadata[.creatorDefinedKey] as? [String: String],
              metadata["ichart.scope"] == "personal-development-comparison-only",
              metadata["ichart.weights.sha256"] == manifest.weightsSHA256 else { throw failure }
        vocabulary = manifest.vocabulary
        let legacyIdentity = "\(manifest.version):\(manifest.packageSHA256):\(PersonalInkResidualHead.version)"
        identity = manifest.anchorSHA256.map { "\(legacyIdentity):\(PersonalInkAnchoredResidualHead.version):\($0)" } ?? legacyIdentity
    }

    func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
        let raster = try ChordInkRasterizer.rasterize(strokes: strokes)
        let input = try MLMultiArray(shape: [1, 1, 96, 256], dataType: .float32)
        for i in raster.pixels.indices { input[i] = NSNumber(value: Float(raster.pixels[i]) / 255) }
        let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["inkRaster": input]))
        return try .init(embedding: values(prediction, name: "personalEmbedding", count: 128),
                         genericLogits: values(prediction, name: "genericLogits", count: vocabulary.count))
    }

    private func values(_ prediction: MLFeatureProvider, name: String, count: Int) throws -> [Double] {
        guard let output = prediction.featureValue(for: name)?.multiArrayValue, output.count == count else {
            throw PersonalInkLearnedComparison.Failure.invalidEncoder
        }
        let result = (0..<count).map { output[$0].doubleValue }
        guard result.allSatisfy(\.isFinite) else { throw PersonalInkLearnedComparison.Failure.invalidEncoder }
        return result
    }
    private static func valid(_ description: MLFeatureDescription?, shape: [Int]) -> Bool {
        description?.multiArrayConstraint?.shape.map(\.intValue) == shape &&
        description?.multiArrayConstraint?.dataType == .float32
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func packageDigest(_ directory: URL) throws -> String {
        let failure = PersonalInkLearnedComparison.Failure.invalidEncoder
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let enumerator = FileManager.default.enumerator(atPath: directory.path) else { throw failure }
        var names: [String] = []
        for case let name as String in enumerator {
            let properties = try directory.appendingPathComponent(name)
                .resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isSymbolicLink != true, (properties.fileSize ?? 0) < 4_000_000 else { throw failure }
            if properties.isRegularFile == true { names.append(name) }
        }
        guard !names.isEmpty, names.count < 32 else { throw failure }
        var payload = Data()
        for name in names.sorted() {
            payload.append(Data(name.utf8)); payload.append(0)
            payload.append(Data(digest(try Data(contentsOf: directory.appendingPathComponent(name))).utf8)); payload.append(10)
        }
        return digest(payload)
    }
}
#endif

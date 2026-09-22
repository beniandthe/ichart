import Foundation
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyBuildBoundaryTests: XCTestCase {
    func testRuntimeIdentityHasNoProductionConfigurationOrLaunchInk() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.ichart.recognitionstudy")
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            "Recognition Study"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
            "RecognitionStudy"
        )
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes"))
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SupabaseURL"))
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey"))
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey"))
        let sceneManifest = Bundle.main.object(
            forInfoDictionaryKey: "UIApplicationSceneManifest"
        ) as? [String: Any]
        XCTAssertEqual(
            sceneManifest?["UIApplicationSupportsMultipleScenes"] as? Bool,
            false
        )
        XCTAssertNil(
            Bundle.main.url(
                forResource: "IChartCanonicalLaunchHandwriting",
                withExtension: "json"
            )
        )
    }

    func testProjectDefinesDedicatedAllowlistedStudyTargetsAndScheme() throws {
        let projectText = try sourceText(at: "project.yml")
        let targets = try section(
            in: projectText,
            after: "\ntargets:\n",
            before: "\nschemes:\n"
        )
        let productionTarget = try section(
            in: targets,
            after: "  iChart:\n",
            before: "  iChartTests:\n"
        )
        let studyTarget = try section(
            in: targets,
            after: "  RecognitionStudy:\n",
            before: "  RecognitionStudyTests:\n"
        )
        let studyTests = try XCTUnwrap(
            targets.components(separatedBy: "  RecognitionStudyTests:\n").last
        )
        let schemes = try XCTUnwrap(
            projectText.components(separatedBy: "\nschemes:\n").last
        )
        let studyScheme = try XCTUnwrap(
            schemes.components(separatedBy: "  RecognitionStudy:\n").last
        )

        XCTAssertFalse(projectText.contains("RecognitionStudy: debug"))
        XCTAssertFalse(projectText.contains("RECOGNITION_STUDY"))

        XCTAssertTrue(productionTarget.contains("PRODUCT_NAME: iChart"))
        XCTAssertTrue(productionTarget.contains("PRODUCT_BUNDLE_IDENTIFIER: com.ichart.app"))
        XCTAssertTrue(productionTarget.contains("- App/RecognitionStudyApp.swift"))
        XCTAssertTrue(productionTarget.contains("- Features/RecognitionStudy"))
        XCTAssertTrue(productionTarget.contains("- package: Supabase"))

        XCTAssertTrue(studyTarget.contains("type: application"))
        XCTAssertTrue(studyTarget.contains("PRODUCT_NAME: RecognitionStudy"))
        XCTAssertTrue(
            studyTarget.contains(
                "PRODUCT_BUNDLE_IDENTIFIER: com.ichart.recognitionstudy"
            )
        )
        XCTAssertTrue(
            studyTarget.contains(
                "path: iChart/Features/RecognitionStudy/Info.plist"
            )
        )
        XCTAssertFalse(studyTarget.contains("dependencies:"))
        XCTAssertFalse(studyTarget.contains("package:"))
        XCTAssertFalse(studyTarget.contains("Supabase"))
        XCTAssertFalse(studyTarget.contains("resources:"))
        XCTAssertFalse(studyTarget.contains("buildPhase: resources"))

        let studySources = try XCTUnwrap(
            studyTarget.components(separatedBy: "    sources:\n").last
        )
        XCTAssertEqual(
            sourcePaths(in: studySources),
            [
                "iChart/App/RecognitionStudyApp.swift",
                "iChart/Recognition/InkTrajectoryTypes.swift",
                "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
                "iChart/Recognition/PencilKitInkAdapter.swift",
                "iChart/Features/RecognitionStudy/RecognitionStudyCanonicalValues.swift",
                "iChart/Features/RecognitionStudy/RecognitionStudyCaptureModels.swift",
                "iChart/Features/RecognitionStudy/RecognitionStudyLocalCaptureStore.swift"
            ]
        )
        for forbiddenPath in [
            "iChart/Recognition/InkTypes.swift",
            "iChart/Recognition/ChordInkRecognizer.swift",
            "iChart/Features/Editor",
            "iChart/Services",
            "iChart/Resources"
        ] {
            XCTAssertFalse(
                sourcePaths(in: studySources).contains(forbiddenPath),
                "Study target must not include \(forbiddenPath)."
            )
        }

        XCTAssertTrue(studyTests.contains("type: bundle.unit-test"))
        XCTAssertTrue(
            studyTests.contains(
                "TEST_HOST: \"$(BUILT_PRODUCTS_DIR)/RecognitionStudy.app/RecognitionStudy\""
            )
        )
        XCTAssertTrue(studyTests.contains("- path: iChartStudyTests"))
        XCTAssertTrue(studyTests.contains("- target: RecognitionStudy"))
        XCTAssertFalse(studyTests.contains("- target: iChart"))

        XCTAssertTrue(studyScheme.contains("RecognitionStudy: all"))
        XCTAssertTrue(
            studyScheme.contains(
                "test:\n      config: Debug\n      targets:\n        - RecognitionStudyTests"
            )
        )
        XCTAssertFalse(studyScheme.contains("iChartTests"))
        XCTAssertFalse(studyScheme.contains("config: Release"))
        XCTAssertEqual(
            studyScheme.components(separatedBy: "config: Debug").count - 1,
            5
        )
    }

    func testDedicatedInfoAndPlaceholderContainNoProductionSystems() throws {
        let studyInfo = try sourceText(
            at: "iChart/Features/RecognitionStudy/Info.plist"
        )
        let studyEntry = try sourceText(at: "iChart/App/RecognitionStudyApp.swift")
        let productionEntry = try sourceText(at: "iChart/App/IChartApp.swift")
        let productionInfo = try sourceText(at: "iChart/App/Info.plist")

        XCTAssertFalse(studyInfo.contains("CFBundleURLTypes"))
        XCTAssertFalse(studyInfo.contains("Supabase"))
        XCTAssertFalse(studyInfo.contains("IChartCanonicalLaunchHandwriting"))
        XCTAssertTrue(
            studyInfo.contains(
                "<key>UIApplicationSupportsMultipleScenes</key>\n\t\t<false/>"
            )
        )
        XCTAssertTrue(productionInfo.contains("<string>iChart</string>"))
        XCTAssertTrue(productionInfo.contains("<string>ichart</string>"))
        XCTAssertFalse(productionInfo.contains("ICHART_DISPLAY_NAME"))
        XCTAssertFalse(productionInfo.contains("ICHART_URL_SCHEME"))

        XCTAssertEqual(
            studyEntry
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") },
            ["import SwiftUI"]
        )
        XCTAssertTrue(studyEntry.contains("@main\nstruct RecognitionStudyApp: App"))
        XCTAssertTrue(
            studyEntry.contains("RecognitionStudyEngineeringDryRunView()")
        )
        XCTAssertTrue(studyEntry.contains("Engineering dry run"))
        XCTAssertTrue(
            studyEntry.contains(
                "No study canvas or data collection is implemented in this build."
            )
        )
        XCTAssertFalse(productionEntry.contains("RECOGNITION_STUDY"))

        let forbiddenProductionReferences = [
            "AppRootView",
            "ChartLibraryStore",
            "Supabase",
            "IChartTelemetry",
            "IChartAuthStore",
            "ChartCloudSync",
            "StoreKit",
            "IChartForum",
            "PDFLibrary",
            "ChordInkUserCorrection",
            "ChordInkRecognizer",
            "EditorView"
        ]
        for reference in forbiddenProductionReferences {
            XCTAssertFalse(
                studyEntry.contains(reference),
                "Study entry must not construct or reference \(reference)."
            )
        }
    }

    func testTrajectoryTypesAreSeparatedFromRecognitionPolicyAndModels() throws {
        let trajectoryTypes = try sourceText(
            at: "iChart/Recognition/InkTrajectoryTypes.swift"
        )
        let recognitionTypes = try sourceText(at: "iChart/Recognition/InkTypes.swift")

        for declaration in [
            "struct InkPoint: Codable, Hashable",
            "struct InkBounds: Codable, Hashable",
            "struct InkStroke: Codable, Hashable"
        ] {
            XCTAssertTrue(trajectoryTypes.contains(declaration))
            XCTAssertFalse(recognitionTypes.contains(declaration))
        }

        for forbiddenDeclaration in [
            "InkCluster",
            "ChordInkBatchClusterer",
            "ChordInkRecognition",
            "ChordSymbol"
        ] {
            XCTAssertFalse(
                trajectoryTypes.contains(forbiddenDeclaration),
                "Shared trajectory types must not absorb \(forbiddenDeclaration)."
            )
        }
        XCTAssertTrue(recognitionTypes.contains("enum InkClusterRecognitionHint"))
    }

    func testStudyContractSourcesRemainOfflineAndUnwired() throws {
        let canonicalValues = try sourceText(
            at: "iChart/Features/RecognitionStudy/RecognitionStudyCanonicalValues.swift"
        )
        let captureModels = try sourceText(
            at: "iChart/Features/RecognitionStudy/RecognitionStudyCaptureModels.swift"
        )
        let combined = canonicalValues + "\n" + captureModels

        XCTAssertEqual(
            canonicalValues
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") },
            ["import CryptoKit", "import Foundation"]
        )
        XCTAssertEqual(
            captureModels
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") },
            ["import Foundation"]
        )

        for forbiddenReference in [
            "FileManager",
            "write(to:",
            "URLSession",
            "NWConnection",
            "Supabase",
            "Telemetry",
            "Export",
            "PKCanvasView",
            "PKDrawing",
            "ChordInkRecognizer",
            "WriterIndependentEvaluation",
            "RecognitionStudyLocalCaptureStore"
        ] {
            XCTAssertFalse(
                combined.contains(forbiddenReference),
                "Study contracts must not reference \(forbiddenReference)."
            )
        }

        let studyEntry = try sourceText(at: "iChart/App/RecognitionStudyApp.swift")
        XCTAssertFalse(studyEntry.contains("RecognitionStudyCaptureEnvelope"))
        XCTAssertFalse(studyEntry.contains("RecognitionStudyPresentedSurface"))
        XCTAssertFalse(studyEntry.contains("RecognitionStudyLocalCaptureStore"))
        XCTAssertFalse(studyEntry.contains("PencilKitInkAdapter"))
    }

    func testLocalStoreIsOfflineStudyOnlyAndHasNoGenericEnvelopeSaveAPI() throws {
        let store = try sourceText(
            at: "iChart/Features/RecognitionStudy/RecognitionStudyLocalCaptureStore.swift"
        )

        XCTAssertEqual(
            store
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") },
            ["import CryptoKit", "import Foundation"]
        )
        XCTAssertTrue(
            store.contains("actor RecognitionStudyLocalCaptureStore")
        )
        XCTAssertTrue(store.contains("func storeCapture("))
        XCTAssertTrue(store.contains(".localEngineeringDryRun("))
        XCTAssertFalse(store.contains(".reservedExternalOneUse("))
        XCTAssertFalse(store.contains("func save("))
        XCTAssertFalse(store.contains("save(envelope:"))

        for forbiddenReference in [
            "URLSession",
            "NWConnection",
            "Supabase",
            "Telemetry",
            "Export",
            "PKCanvasView",
            "PKDrawing",
            "ChordInkRecognizer",
            "WriterIndependentEvaluation"
        ] {
            XCTAssertFalse(
                store.contains(forbiddenReference),
                "The local store must not reference \(forbiddenReference)."
            )
        }

        for forbiddenSemanticKey in [
            "\"prompt\"",
            "\"chord\"",
            "\"label\"",
            "\"writer\"",
            "\"person\"",
            "\"handedness\"",
            "\"split\"",
            "\"consent\"",
            "\"eligibility\"",
            "\"leakage\"",
            "\"candidate\"",
            "\"confidence\"",
            "\"prediction\"",
            "\"trust\"",
            "rawDrawing"
        ] {
            XCTAssertFalse(
                store.contains(forbiddenSemanticKey),
                "The local store must not add \(forbiddenSemanticKey)."
            )
        }
    }

    func testCanonicalDocumentsAreEncodableOnlyAndDecodeThroughPrivateWires() throws {
        let canonicalValues = try sourceText(
            at: "iChart/Features/RecognitionStudy/RecognitionStudyCanonicalValues.swift"
        )
        let captureModels = try sourceText(
            at: "iChart/Features/RecognitionStudy/RecognitionStudyCaptureModels.swift"
        )

        XCTAssertTrue(
            canonicalValues.contains(
                "protocol RecognitionStudyCanonicalJSONDocument: Encodable {"
            )
        )
        XCTAssertTrue(
            canonicalValues.contains(
                "static func decodeCanonicalData(_ data: Data) throws -> Self"
            )
        )
        XCTAssertTrue(
            canonicalValues.contains(
                "static var maximumCanonicalJSONByteCount: Int { get }"
            )
        )
        XCTAssertFalse(
            canonicalValues.contains("maximumCanonicalJSONByteCount: Int?")
        )
        XCTAssertEqual(
            canonicalValues.components(
                separatedBy: "static var maximumCanonicalJSONByteCount"
            ).count - 1,
            1,
            "The protocol must not supply a default document-size cap."
        )
        XCTAssertFalse(
            canonicalValues.contains(
                "protocol RecognitionStudyCanonicalJSONDocument: Decodable"
            )
        )
        XCTAssertFalse(
            canonicalValues.contains(
                "protocol RecognitionStudyCanonicalJSONDocument: Codable"
            )
        )
        XCTAssertFalse(
            canonicalValues.contains("JSONDecoder().decode(Self.self")
        )
        XCTAssertFalse(canonicalValues.contains("decodeWireRepresentation"))
        XCTAssertFalse(captureModels.contains("decodeWireRepresentation"))
        XCTAssertFalse(captureModels.contains("JSONDecoder"))
        XCTAssertTrue(
            canonicalValues.contains("enum RecognitionStudyStrictCanonicalJSON")
        )
        XCTAssertTrue(
            canonicalValues.contains(
                "let wire = try JSONDecoder().decode(wireType, from: data)"
            )
        )
        XCTAssertTrue(canonicalValues.contains("try document.validateContract()"))
        XCTAssertTrue(
            canonicalValues.contains("guard try document.canonicalData() == data")
        )

        for documentName in [
            "RecognitionStudyAuthorizationBinding",
            "RecognitionStudyClientAppContext",
            "RecognitionStudySessionManifest",
            "RecognitionStudyPresentedSurface",
            "RecognitionStudyTrajectoryDescriptor",
            "RecognitionStudyCaptureEnvelope"
        ] {
            let header = try declarationHeader(
                in: captureModels,
                kind: "struct",
                named: documentName
            )
            XCTAssertTrue(
                header.contains("RecognitionStudyCanonicalJSONDocument"),
                "\(documentName) must use the encodable-only canonical document boundary."
            )
            XCTAssertFalse(
                header.contains("Decodable") || header.contains("Codable"),
                "\(documentName) must not be directly JSON-decodable."
            )
            XCTAssertFalse(
                captureModels.contains("extension \(documentName)"),
                "\(documentName) must not acquire decoding in an extension."
            )
        }

        for enumName in [
            "RecognitionStudyArtifactKind",
            "RecognitionStudyAuthorizationKind",
            "RecognitionStudyPresentedChartStyle",
            "RecognitionStudyObservedOrientation",
            "RecognitionStudyPresentedPaceInstruction",
            "RecognitionStudyPresentedSizeInstruction",
            "RecognitionStudyPresentedConstructionInstruction"
        ] {
            let header = try declarationHeader(
                in: captureModels,
                kind: "enum",
                named: enumName
            )
            XCTAssertTrue(header.contains("Encodable"))
            XCTAssertFalse(
                header.contains("Decodable") || header.contains("Codable"),
                "\(enumName) must not provide a direct decode path."
            )
        }

        XCTAssertFalse(captureModels.contains("init(from"))
        XCTAssertFalse(captureModels.contains("Codable"))
        XCTAssertEqual(
            captureModels.components(
                separatedBy: "static func decodeCanonicalData(_ data: Data) throws -> Self"
            ).count - 1,
            6,
            "Every canonical document must expose exactly one safe decode entry."
        )
        XCTAssertEqual(
            captureModels.components(separatedBy: "static func decode").count - 1,
            6,
            "Capture documents must not expose any raw decode method."
        )
        XCTAssertEqual(
            captureModels.components(
                separatedBy: "static let maximumCanonicalJSONByteCount: Int ="
            ).count - 1,
            6,
            "Every canonical capture document must declare an explicit cap."
        )
        let namedV1Limits = [
            (
                "maximumAuthorizationBindingV1CanonicalJSONByteCount",
                "8 * 1024"
            ),
            (
                "maximumClientAppContextV1CanonicalJSONByteCount",
                "8 * 1024"
            ),
            (
                "maximumSessionManifestV1CanonicalJSONByteCount",
                "32 * 1024"
            ),
            (
                "maximumPresentedSurfaceV1CanonicalJSONByteCount",
                "8 * 1024"
            ),
            (
                "maximumTrajectoryDescriptorV1CanonicalJSONByteCount",
                "8 * 1024"
            ),
            (
                "maximumCaptureEnvelopeV1CanonicalJSONByteCount",
                "64 * 1024"
            )
        ]
        for (limitName, valueExpression) in namedV1Limits {
            XCTAssertTrue(
                captureModels.contains(
                    "static let \(limitName) = \(valueExpression)"
                ),
                "Missing the explicit \(limitName) cap."
            )
            XCTAssertEqual(
                captureModels.components(separatedBy: limitName).count - 1,
                2,
                "\(limitName) must be declared once and bound to one document."
            )
        }
        XCTAssertEqual(
            captureModels.components(separatedBy: "fileprivate init(").count - 1,
            6,
            "Wire construction must remain file-private."
        )
        XCTAssertTrue(
            captureModels.contains(
                "fileprivate enum RecognitionStudyCaptureWire {"
            )
        )
        for wireName in [
            "AuthorizationBinding",
            "ClientAppContext",
            "SessionManifest",
            "PresentedSurface",
            "TrajectoryDescriptor",
            "CaptureEnvelope"
        ] {
            XCTAssertTrue(
                captureModels.contains("struct \(wireName): Decodable"),
                "Missing implementation-owned Decodable wire \(wireName)."
            )
        }
        XCTAssertEqual(
            captureModels.components(separatedBy: "Decodable").count - 1,
            6,
            "Only the six implementation-owned wire structs may be Decodable."
        )
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceText(at relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath))
    }

    private func section(
        in text: String,
        after startMarker: String,
        before endMarker: String
    ) throws -> String {
        let suffix = try XCTUnwrap(
            text.components(separatedBy: startMarker).dropFirst().first
        )
        return try XCTUnwrap(
            suffix.components(separatedBy: endMarker).first
        )
    }

    private func sourcePaths(in sources: String) -> [String] {
        sources
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { line in
                guard line.hasPrefix("- path: ") else {
                    return nil
                }
                return String(line.dropFirst("- path: ".count))
            }
    }

    private func declarationHeader(
        in source: String,
        kind: String,
        named name: String
    ) throws -> String {
        let marker = "\(kind) \(name)"
        let declarationStart = try XCTUnwrap(source.range(of: marker))
        let suffix = source[declarationStart.lowerBound...]
        let openingBrace = try XCTUnwrap(suffix.firstIndex(of: "{"))
        return String(suffix[..<openingBrace])
    }
}

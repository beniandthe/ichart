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
                "iChart/Recognition/PencilKitInkAdapter.swift"
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
}

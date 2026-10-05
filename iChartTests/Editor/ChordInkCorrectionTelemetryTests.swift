#if canImport(UIKit)
import XCTest
@testable import iChart

final class ChordInkCorrectionTelemetryTests: XCTestCase {
    func testCorrectionsUseOriginalReadVersionAndDoNotInventLegacyOrManualAttribution() {
        for version in [
            "maximum-trust-v13-2026-09-12",
            "maximum-trust-v32-chord-domain-v1-2026-10-03",
            ChordInkRecognitionPipelineIdentity.version
        ] {
            let properties = ChordInkCorrectionTelemetry.sourceProperties(
                hasSourceInk: true, sourceRecognitionPipelineVersion: version
            )
            XCTAssertEqual(properties["source"], .string("recognized_ink"))
            XCTAssertEqual(properties["recognition_pipeline_version"], .string(version))
            XCTAssertEqual(properties, IChartTelemetryPrivacy.sanitizedProperties(properties))
        }
        for unknownVersion in [
            nil, "", " \n\t", "writer@example.invalid", "private chart title",
            "D-7", "maximum-trust-v16-2026-09-12\nprivate content",
            "maximum-trust-v16-2026-09-12 private content",
            "maximum-trust-v34-private-chart-title-2026-10-03",
            "maximum-trust-v34-chord-only-scored-candidates-2026-10-03\nprivate content",
            "maximum-trust-v0-2026-10-03",
            "maximum-trust-v10000-2026-10-03",
            String(repeating: "private content", count: 100)
        ] as [String?] {
            let properties = ChordInkCorrectionTelemetry.sourceProperties(
                hasSourceInk: true, sourceRecognitionPipelineVersion: unknownVersion
            )
            XCTAssertEqual(properties, ["source": .string("recognized_ink")])
        }
        let manual = ChordInkCorrectionTelemetry.sourceProperties(
            hasSourceInk: false,
            sourceRecognitionPipelineVersion: ChordInkRecognitionPipelineIdentity.version
        )
        XCTAssertEqual(manual, ["source": .string("manual_entry")])
    }
}
#endif

#if canImport(UIKit)
import XCTest
@testable import iChart

final class ChordInkRecognitionPreparationTelemetryTests: XCTestCase {
    func testFailuresRemainContentFreeAndVersionedInBothChartStyles() throws {
        let outcomes: [ChordInkRecognitionPreparationOutcome] = [
            .invalidDrawingData, .skippedWeakBatchTargets, .skippedSingleTarget, .noTarget
        ]
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            for outcome in outcomes {
                let result = preparation(outcome)
                let properties = try XCTUnwrap(ChordInkRecognitionPreparationTelemetry.failureProperties(
                    for: result, flow: .draftPreview, layoutStyle: style
                ))
                XCTAssertEqual(properties["layout_style"], .string(style.rawValue))
                XCTAssertEqual(properties["recognition_pipeline_version"], .string(ChordInkRecognitionPipelineIdentity.version))
                XCTAssertEqual(properties["recognition_target_count"], .int(0))
                XCTAssertEqual(properties["stroke_count"], .int(3))
                XCTAssertEqual(properties["duration_ms"], .double(12.345))
                XCTAssertNil(properties["no_read_count"])
                XCTAssertEqual(properties, IChartTelemetryPrivacy.sanitizedProperties(properties))
                XCTAssertFalse(properties.values.contains(.string(result.requestID.uuidString)))
                XCTAssertNil(properties["drawing_data"])
                XCTAssertNil(properties["chart_title"])
            }
        }
    }

    func testExpectedEmptyCancelledAndReadyPreparationDoesNotReportFailure() {
        let outcomes: [ChordInkRecognitionPreparationOutcome] = [
            .cancelled, .noVisibleStrokes, .noRecognitionData, .ready(requests: [], usesBatch: false)
        ]
        for outcome in outcomes {
            XCTAssertNil(ChordInkRecognitionPreparationTelemetry.failureProperties(
                for: preparation(outcome), flow: .draftPreview, layoutStyle: .simpleChordSheet
            ))
        }
    }

    private func preparation(_ outcome: ChordInkRecognitionPreparationOutcome) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparationResult(
            requestID: UUID(), outcome: outcome, barlines: [],
            sourceStrokeCount: 3, recognitionStrokeCount: 3, visibleStrokeCount: 3,
            ignoredInvisibleStrokeCount: 0, rawBatchTargetCount: 0,
            boundedBatchTargetCount: 0, durationMilliseconds: 12.345
        )
    }
}
#endif

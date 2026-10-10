#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class ChordWritingWorkflowTelemetryTests: XCTestCase {
    private let batchID = UUID(uuidString: "D005CE18-075F-4B94-8175-835D20A1B5B9")!

    func testFinalReviewSeparatesChangedReadsFromRepairedNoReads() {
        let properties = ChordWritingWorkflowTelemetry.reviewProperties(
            batchID: batchID,
            observations: [
                .init(hadSupportedRead: true, didChangeRead: false),
                .init(hadSupportedRead: true, didChangeRead: true),
                .init(hadSupportedRead: false, didChangeRead: true),
                .init(hadSupportedRead: false, didChangeRead: false)
            ],
            durationMilliseconds: 2_345.6789
        )
        let sanitized = IChartTelemetryPrivacy.sanitizedProperties(properties)

        XCTAssertEqual(sanitized["writing_batch_id"], .string(batchID.uuidString.lowercased()))
        XCTAssertEqual(sanitized["reviewed_count"], .int(4))
        XCTAssertEqual(sanitized["changed_chord_count"], .int(1))
        XCTAssertEqual(sanitized["repaired_no_read_count"], .int(2))
        XCTAssertEqual(sanitized["review_duration_ms"], .double(2_345.679))
        XCTAssertEqual(sanitized.count, 5)
    }

    func testUnknownOrClockReversedLatencyRemainsUnknown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(ChordWritingWorkflowTelemetry.elapsedMilliseconds(from: nil, to: now))
        XCTAssertNil(ChordWritingWorkflowTelemetry.elapsedMilliseconds(from: now, to: now.addingTimeInterval(-1)))
        XCTAssertEqual(ChordWritingWorkflowTelemetry.elapsedMilliseconds(from: now, to: now.addingTimeInterval(0.5)), 500)
        for invalid in [-1, .nan, .infinity, 86_400_001] {
            let properties = ChordWritingWorkflowTelemetry.previewTimingProperties(
                batchID: batchID, lastStrokeToPreviewMilliseconds: invalid
            )
            XCTAssertEqual(Set(properties.keys), ["writing_batch_id"])
        }
    }

    func testOnlyContentFreeWorkflowScalarsSurvivePrivacyProjection() {
        let valid = IChartTelemetryPrivacy.sanitizedProperties([
            "writing_batch_id": .string(batchID.uuidString),
            "reviewed_count": .int(6),
            "changed_chord_count": .int(2),
            "repaired_no_read_count": .int(1),
            "last_stroke_to_preview_ms": .double(321.98765),
            "review_duration_ms": .int(3_200),
            "rewrite_outcome": .string("local"),
            "chart_id": .string(UUID().uuidString),
            "accepted_chord_text": .string("D/F#"),
            "drawing_data": .string("private")
        ])
        XCTAssertEqual(valid.count, 7)
        XCTAssertEqual(valid["last_stroke_to_preview_ms"], .double(321.988))
        XCTAssertEqual(valid["writing_batch_id"], .string(batchID.uuidString.lowercased()))
        XCTAssertNil(valid["chart_id"])
        XCTAssertNil(valid["accepted_chord_text"])
        XCTAssertNil(valid["drawing_data"])

        let invalid = IChartTelemetryPrivacy.sanitizedProperties([
            "writing_batch_id": .string("private chart title"),
            "reviewed_count": .string("C7"),
            "changed_chord_count": .bool(true),
            "repaired_no_read_count": .int(-1),
            "last_stroke_to_preview_ms": .string("private handwriting"),
            "review_duration_ms": .double(.infinity),
            "rewrite_outcome": .string("D/F#")
        ])
        XCTAssertTrue(invalid.isEmpty)
    }

    func testNewWorkflowFieldsRejectOutOfBoundsAndWrongNumericTypes() {
        for key in ["reviewed_count", "changed_chord_count", "repaired_no_read_count"] {
            for invalid in [IChartTelemetryValue.int(10_001), .double(1.5), .string("2")] {
                XCTAssertTrue(IChartTelemetryPrivacy.sanitizedProperties([key: invalid]).isEmpty)
            }
        }
        for key in ["last_stroke_to_preview_ms", "review_duration_ms"] {
            for invalid in [IChartTelemetryValue.int(-1), .double(.nan), .double(86_400_001)] {
                XCTAssertTrue(IChartTelemetryPrivacy.sanitizedProperties([key: invalid]).isEmpty)
            }
        }
        for invalidID in [batchID.uuidString + "\n", "00000000-0000-0000-0000-000000000000"] {
            XCTAssertTrue(IChartTelemetryPrivacy.sanitizedProperties([
                "writing_batch_id": .string(invalidID)
            ]).isEmpty)
        }
    }

    func testRewriteOutcomesStayDistinctAndUseFreshBatchCorrelation() {
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.preview_rewritten"))
        for outcome in [ChordWritingWorkflowTelemetry.RewriteOutcome.local, .page, .discard] {
            let properties = ChordWritingWorkflowTelemetry.rewriteProperties(batchID: batchID, outcome: outcome)
            XCTAssertEqual(IChartTelemetryPrivacy.sanitizedProperties(properties), properties)
            XCTAssertEqual(properties["rewrite_outcome"], .string(outcome.rawValue))
        }
        XCTAssertNotEqual(
            ChordWritingWorkflowTelemetry.batchProperties(batchID: batchID),
            ChordWritingWorkflowTelemetry.batchProperties(batchID: UUID())
        )
    }
}
#endif

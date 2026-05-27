#if canImport(UIKit)
import PencilKit
import XCTest
@testable import SmartChart

final class LeadSheetChordInkRecognitionSchedulingTests: XCTestCase {
    func testIdleDelayCurrentlyUsesConfiguredDefault() {
        XCTAssertEqual(
            LeadSheetChordInkRecognitionScheduling.idleDelay(
                for: PKDrawing(),
                defaultDelay: LeadSheetChordInkRecognitionScheduling.defaultIdleDelay
            ),
            0.75
        )
    }

    func testClearRootUsesShortContinuationGraceBeforeProposal() throws {
        let idleDelay = LeadSheetChordInkRecognitionScheduling.defaultIdleDelay
        let continuationGraceDelay = LeadSheetChordInkRecognitionScheduling.continuationGraceDelay(
            for: try recognitionResult(for: "C", confidence: 4.5),
            defaultDelay: LeadSheetChordInkRecognitionScheduling.defaultContinuationGraceDelay
        )
        let result = try recognitionResult(for: "C", confidence: 4.5)
        let drawingData = Data([0x43])
        let timing = recognitionTiming(requestedDelay: idleDelay, strokeCount: 1)

        XCTAssertTrue(
            LeadSheetChordInkRecognitionScheduling.shouldGiveContinuationGrace(
                previousDrawingData: nil,
                drawingData: drawingData,
                timing: timing,
                idleDelay: idleDelay,
                result: result
            )
        )
        XCTAssertEqual(continuationGraceDelay, 0.4, accuracy: 0.001)
        XCTAssertEqual(idleDelay + continuationGraceDelay, 1.15, accuracy: 0.001)
    }

    func testExtensionPrefixKeepsFullContinuationGrace() throws {
        let result = try recognitionResult(for: "A9", confidence: 4.5)

        XCTAssertTrue(
            LeadSheetChordInkRecognitionScheduling.shouldGiveContinuationGrace(
                previousDrawingData: nil,
                drawingData: Data([0x41, 0x39]),
                timing: recognitionTiming(
                    requestedDelay: LeadSheetChordInkRecognitionScheduling.defaultIdleDelay,
                    strokeCount: 4
                ),
                idleDelay: LeadSheetChordInkRecognitionScheduling.defaultIdleDelay,
                result: result
            )
        )
        XCTAssertEqual(
            LeadSheetChordInkRecognitionScheduling.continuationGraceDelay(
                for: result,
                defaultDelay: LeadSheetChordInkRecognitionScheduling.defaultContinuationGraceDelay
            ),
            1.2
        )
    }

    func testContinuationGraceDoesNotRepeatForSameDrawingData() throws {
        let result = try recognitionResult(for: "C", confidence: 4.5)
        let drawingData = Data([0x43])

        XCTAssertFalse(
            LeadSheetChordInkRecognitionScheduling.shouldGiveContinuationGrace(
                previousDrawingData: drawingData,
                drawingData: drawingData,
                timing: recognitionTiming(
                    requestedDelay: LeadSheetChordInkRecognitionScheduling.defaultIdleDelay,
                    strokeCount: 1
                ),
                idleDelay: LeadSheetChordInkRecognitionScheduling.defaultIdleDelay,
                result: result
            )
        )
    }

    func testSlashAndAlteredChordsDoNotUseContinuationGrace() throws {
        let timing = recognitionTiming(
            requestedDelay: LeadSheetChordInkRecognitionScheduling.defaultIdleDelay,
            strokeCount: 6
        )
        let drawingData = Data([0x01])

        for chord in ["G/B", "Db7(b9)"] {
            XCTAssertFalse(
                LeadSheetChordInkRecognitionScheduling.shouldGiveContinuationGrace(
                    previousDrawingData: nil,
                    drawingData: drawingData,
                    timing: timing,
                    idleDelay: LeadSheetChordInkRecognitionScheduling.defaultIdleDelay,
                    result: try recognitionResult(for: chord, confidence: 4.5)
                ),
                chord
            )
        }
    }

    private func recognitionResult(
        for text: String,
        confidence: Double
    ) throws -> ChordInkRecognitionResult {
        let match = try XCTUnwrap(ChordRecognitionCompendium.match(text), text)
        return ChordInkRecognitionResult(
            rawCandidates: [text],
            glyphCandidates: [],
            match: match,
            confidence: confidence,
            candidateScores: [
                ChordInkCandidateScore(
                    text: text,
                    displayText: match.displayText,
                    confidence: confidence
                )
            ]
        )
    }

    private func recognitionTiming(
        requestedDelay: TimeInterval,
        strokeCount: Int
    ) -> ChordInkRecognitionTiming {
        let scheduledAt = Date(timeIntervalSince1970: 0)
        let recognitionStartedAt = scheduledAt.addingTimeInterval(requestedDelay)
        return ChordInkRecognitionTiming(
            scheduledAt: scheduledAt,
            requestedDelay: requestedDelay,
            recognitionStartedAt: recognitionStartedAt,
            recognitionFinishedAt: recognitionStartedAt.addingTimeInterval(0.02),
            strokeCount: strokeCount,
            ocrCandidateCount: 0
        )
    }
}
#endif

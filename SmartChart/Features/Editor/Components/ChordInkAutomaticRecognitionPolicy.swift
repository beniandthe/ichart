import Foundation
import PencilKit

enum ChordInkAutomaticRecognitionPolicy {
    static let defaultIdleDelay: TimeInterval = 0.75
    static let defaultContinuationGraceDelay: TimeInterval = 1.2
    static let rootOnlyContinuationGraceDelay: TimeInterval = 0.4

    static func idleDelay(
        for _: PKDrawing,
        defaultDelay: TimeInterval
    ) -> TimeInterval {
        defaultDelay
    }

    static func continuationGraceDelay(
        for result: ChordInkRecognitionResult,
        defaultDelay: TimeInterval
    ) -> TimeInterval {
        guard let symbol = result.match?.symbol,
              symbol.extensions.isEmpty,
              symbol.alterations.isEmpty,
              symbol.slashBass == nil,
              result.confidence >= ChordInkRecognitionPolicy.autoRenderMinimumConfidence else {
            return defaultDelay
        }

        return min(defaultDelay, rootOnlyContinuationGraceDelay)
    }

    static func shouldGiveContinuationGrace(
        flow: ChordInkRecognitionFlow,
        previousDrawingData: Data?,
        drawingData: Data,
        timing: ChordInkRecognitionTiming,
        idleDelay: TimeInterval,
        result: ChordInkRecognitionResult
    ) -> Bool {
        guard flow.allowsContinuationGrace else {
            return false
        }

        return shouldGiveContinuationGrace(
            previousDrawingData: previousDrawingData,
            drawingData: drawingData,
            timing: timing,
            idleDelay: idleDelay,
            result: result
        )
    }

    static func shouldGiveContinuationGrace(
        previousDrawingData: Data?,
        drawingData: Data,
        timing: ChordInkRecognitionTiming,
        idleDelay: TimeInterval,
        result: ChordInkRecognitionResult
    ) -> Bool {
        guard previousDrawingData != drawingData,
              timing.requestedDelay <= idleDelay + 0.01,
              ChordInkContinuationGracePolicy.shouldWaitForPossibleContinuation(
                  result: result,
                  strokeCount: timing.strokeCount
              ) else {
            return false
        }

        return true
    }
}

@available(*, deprecated, renamed: "ChordInkAutomaticRecognitionPolicy")
typealias LeadSheetChordInkRecognitionScheduling = ChordInkAutomaticRecognitionPolicy

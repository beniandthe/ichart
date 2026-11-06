#if canImport(UIKit)
import Foundation

enum ChordInkRecognitionPreparationTelemetry {
    static func failureProperties(
        for result: ChordInkRecognitionPreparationResult,
        flow _: ChordInkRecognitionFlow,
        layoutStyle _: ChartLayoutStyle
    ) -> IChartTelemetryProperties? {
        let errorCode: String
        switch result.outcome {
        case .invalidDrawingData:
            errorCode = "invalid_drawing_data"
        case .skippedWeakBatchTargets:
            errorCode = "weak_batch_targets"
        case .skippedSingleTarget:
            errorCode = "weak_single_target"
        case .noTarget:
            errorCode = "no_recognition_target"
        case .ready, .cancelled, .noVisibleStrokes, .noRecognitionData:
            // Cancellation, erased ink and barline-only ink are not failed reads.
            return nil
        }

        // This is a preparation-attempt diagnostic, not an assertion about how
        // many intended chords were written. In particular, no target means an
        // unknown chord denominator; do not invent a no_read_count of one.
        return [
            "error_code": .string(errorCode),
            "duration_ms": .double(result.durationMilliseconds)
        ]
    }
}
#endif

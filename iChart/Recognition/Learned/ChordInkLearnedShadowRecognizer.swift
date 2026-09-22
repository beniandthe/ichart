import Foundation

/// One-way observational request emitted after the production recognizer has
/// made its decision. The observer has no return channel and therefore cannot
/// replace the result shown to the user or written to the chart.
struct ChordInkLearnedShadowRequest {
    let strokes: [InkStroke]
    let options: ChordInkRecognitionOptions
    let productionResult: ChordInkRecognitionResult
}

/// Implementations should enqueue work and return promptly. Learned inference,
/// calibration inspection, and aggregate diagnostics can live behind this
/// boundary without receiving recognition authority.
protocol ChordInkLearnedShadowObserving {
    func enqueue(_ request: ChordInkLearnedShadowRequest)
}

/// Additive seam around the current recognizer. It always returns the exact
/// production result before/independently of any learned shadow observation.
/// This wrapper is intentionally not constructed anywhere in production yet.
struct ChordInkLearnedShadowRecognizer<Production, Observer>: ChordInkRecognizing
where Production: ChordInkRecognizing, Observer: ChordInkLearnedShadowObserving {
    let production: Production
    let observer: Observer

    func recognize(
        strokes: [InkStroke],
        options: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        let result = production.recognize(strokes: strokes, options: options)
        observer.enqueue(
            ChordInkLearnedShadowRequest(
                strokes: strokes,
                options: options,
                productionResult: result
            )
        )
        return result
    }
}

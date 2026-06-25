#if canImport(UIKit)
import CoreGraphics
import Foundation

struct ChordInkRecognitionSessionRequest {
    var requestID: UUID
    var scheduledAt: Date
    var requestedDelay: TimeInterval
    var strokes: [InkStroke]
    var drawingData: Data
    var target: (measureID: UUID, fraction: Double)
    var options: ChordInkRecognitionOptions
    var ocrImageProvider: () -> CGImage?
}

struct ChordInkRecognitionProposalPayload {
    var requestID: UUID
    var result: ChordInkRecognitionResult
    var drawingData: Data
    var target: (measureID: UUID, fraction: Double)
    var timing: ChordInkRecognitionTiming
}

final class ChordInkRecognitionSession {
    private let queue: DispatchQueue
    private let recognizer: ChordInkRecognizing
    private let ocrCandidateProvider: ChordOCRCandidateProviding?

    init(
        queue: DispatchQueue,
        recognizer: ChordInkRecognizing,
        ocrCandidateProvider: ChordOCRCandidateProviding?
    ) {
        self.queue = queue
        self.recognizer = recognizer
        self.ocrCandidateProvider = ocrCandidateProvider
    }

    func start(
        request: ChordInkRecognitionSessionRequest,
        completion: @escaping (ChordInkRecognitionProposalPayload) -> Void
    ) {
        let recognizer = recognizer
        let ocrCandidateProvider = ocrCandidateProvider
        queue.async {
            let recognitionStartedAt = Date()
            var result = recognizer.recognize(
                strokes: request.strokes,
                options: request.options
            )
            let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
            if ChordRecognitionTrustArbiter.shouldRequestOCR(
                for: result,
                primaryDecision: primaryDecision
            ),
               let ocrCandidateProvider,
               let ocrImage = request.ocrImageProvider() {
                let ocrStartedAt = Date()
                result.ocrCandidates = ocrCandidateProvider.recognizeCandidates(in: ocrImage)
                result.metrics.ocrMilliseconds = Date().timeIntervalSince(ocrStartedAt) * 1_000
            }

            let recognitionFinishedAt = Date()
            let payload = ChordInkRecognitionProposalPayload(
                requestID: request.requestID,
                result: result,
                drawingData: request.drawingData,
                target: request.target,
                timing: ChordInkRecognitionTiming(
                    scheduledAt: request.scheduledAt,
                    requestedDelay: request.requestedDelay,
                    recognitionStartedAt: recognitionStartedAt,
                    recognitionFinishedAt: recognitionFinishedAt,
                    strokeCount: request.strokes.count,
                    ocrCandidateCount: result.ocrCandidates?.count ?? 0
                )
            )

            DispatchQueue.main.async {
                completion(payload)
            }
        }
    }

    func startBatch(
        requests: [ChordInkRecognitionSessionRequest],
        completion: @escaping ([ChordInkRecognitionProposalPayload]) -> Void
    ) {
        guard !requests.isEmpty else {
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

        let recognizer = recognizer
        let ocrCandidateProvider = ocrCandidateProvider
        queue.async {
            let payloads = requests.map { request in
                let recognitionStartedAt = Date()
                var result = recognizer.recognize(
                    strokes: request.strokes,
                    options: request.options
                )
                let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
                if ChordRecognitionTrustArbiter.shouldRequestOCR(
                    for: result,
                    primaryDecision: primaryDecision
                ),
                   let ocrCandidateProvider,
                   let ocrImage = request.ocrImageProvider() {
                    let ocrStartedAt = Date()
                    result.ocrCandidates = ocrCandidateProvider.recognizeCandidates(in: ocrImage)
                    result.metrics.ocrMilliseconds = Date().timeIntervalSince(ocrStartedAt) * 1_000
                }

                let recognitionFinishedAt = Date()
                return ChordInkRecognitionProposalPayload(
                    requestID: request.requestID,
                    result: result,
                    drawingData: request.drawingData,
                    target: request.target,
                    timing: ChordInkRecognitionTiming(
                        scheduledAt: request.scheduledAt,
                        requestedDelay: request.requestedDelay,
                        recognitionStartedAt: recognitionStartedAt,
                        recognitionFinishedAt: recognitionFinishedAt,
                        strokeCount: request.strokes.count,
                        ocrCandidateCount: result.ocrCandidates?.count ?? 0
                    )
                )
            }

            DispatchQueue.main.async {
                completion(payloads)
            }
        }
    }
}
#endif

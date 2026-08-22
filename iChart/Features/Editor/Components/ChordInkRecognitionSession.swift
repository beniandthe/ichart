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
    var visualOrder: Double? = nil
    var laneLocation: ChordInkDraftLaneLocation? = nil
    var layoutPageSize: CGSize? = nil
    var options: ChordInkRecognitionOptions
}

struct ChordInkRecognitionProposalPayload {
    var requestID: UUID
    var result: ChordInkRecognitionResult
    var drawingData: Data
    var target: (measureID: UUID, fraction: Double)
    var visualOrder: Double? = nil
    var laneLocation: ChordInkDraftLaneLocation? = nil
    var layoutPageSize: CGSize? = nil
    var timing: ChordInkRecognitionTiming
}

final class ChordInkRecognitionSession {
    private let queue: DispatchQueue
    private let recognizer: ChordInkRecognizing

    init(
        queue: DispatchQueue,
        recognizer: ChordInkRecognizing
    ) {
        self.queue = queue
        self.recognizer = recognizer
    }

    func start(
        request: ChordInkRecognitionSessionRequest,
        completion: @escaping (ChordInkRecognitionProposalPayload) -> Void
    ) {
        let recognizer = recognizer
        queue.async {
            let recognitionStartedAt = Date()
            let result = recognizer.recognize(
                strokes: request.strokes,
                options: request.options
            )
            let recognitionFinishedAt = Date()
            let payload = ChordInkRecognitionProposalPayload(
                requestID: request.requestID,
                result: result,
                drawingData: request.drawingData,
                target: request.target,
                visualOrder: request.visualOrder,
                laneLocation: request.laneLocation,
                layoutPageSize: request.layoutPageSize,
                timing: ChordInkRecognitionTiming(
                    scheduledAt: request.scheduledAt,
                    requestedDelay: request.requestedDelay,
                    recognitionStartedAt: recognitionStartedAt,
                    recognitionFinishedAt: recognitionFinishedAt,
                    strokeCount: request.strokes.count
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
        queue.async {
            let payloads = requests.map { request in
                let recognitionStartedAt = Date()
                let result = recognizer.recognize(
                    strokes: request.strokes,
                    options: request.options
                )
                let recognitionFinishedAt = Date()
                return ChordInkRecognitionProposalPayload(
                    requestID: request.requestID,
                    result: result,
                    drawingData: request.drawingData,
                    target: request.target,
                    visualOrder: request.visualOrder,
                    laneLocation: request.laneLocation,
                    layoutPageSize: request.layoutPageSize,
                    timing: ChordInkRecognitionTiming(
                        scheduledAt: request.scheduledAt,
                        requestedDelay: request.requestedDelay,
                        recognitionStartedAt: recognitionStartedAt,
                        recognitionFinishedAt: recognitionFinishedAt,
                        strokeCount: request.strokes.count
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

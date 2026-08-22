#if canImport(UIKit)
import XCTest
@testable import iChart

final class ChordInkRecognitionSessionTests: XCTestCase {
    func testSessionDeliversRecognitionPayloadOnMainThread() {
        let requestID = UUID()
        let target = (measureID: UUID(), fraction: 0.5)
        let drawingData = Data([0x01, 0x02, 0x03])
        let expectedResult = Self.result(for: "C", confidence: 4.5)
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-session.primary"),
            recognizer: StubChordInkRecognizer(results: [expectedResult])
        )
        let expectation = expectation(description: "recognition payload")

        session.start(
            request: ChordInkRecognitionSessionRequest(
                requestID: requestID,
                scheduledAt: Date(),
                requestedDelay: 0.1,
                strokes: [],
                drawingData: drawingData,
                target: target,
                options: .live
            )
        ) { payload in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(payload.requestID, requestID)
            XCTAssertEqual(payload.result.match?.displayText, "C")
            XCTAssertEqual(payload.drawingData, drawingData)
            XCTAssertEqual(payload.target.measureID, target.measureID)
            XCTAssertEqual(payload.target.fraction, target.fraction)
            XCTAssertEqual(payload.timing.strokeCount, 0)
            XCTAssertGreaterThanOrEqual(payload.timing.recognitionMilliseconds, 0)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testBatchSessionDeliversPayloadsInRequestOrder() {
        let firstRequestID = UUID()
        let secondRequestID = UUID()
        let firstTarget = (measureID: UUID(), fraction: 0.25)
        let secondTarget = (measureID: UUID(), fraction: 0.75)
        let recognizer = StubChordInkRecognizer(results: [
            Self.result(for: "C", confidence: 4.5),
            Self.result(for: "G/B", confidence: 4.4)
        ])
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-session.primary-batch"),
            recognizer: recognizer
        )
        let expectation = expectation(description: "batch recognition payload")

        session.startBatch(
            requests: [
                ChordInkRecognitionSessionRequest(
                    requestID: firstRequestID,
                    scheduledAt: Date(),
                    requestedDelay: 0,
                    strokes: [Self.stroke(offsetX: 0)],
                    drawingData: Data([0x01]),
                    target: firstTarget,
                    options: .live
                ),
                ChordInkRecognitionSessionRequest(
                    requestID: secondRequestID,
                    scheduledAt: Date(),
                    requestedDelay: 0,
                    strokes: [Self.stroke(offsetX: 10), Self.stroke(offsetX: 20)],
                    drawingData: Data([0x02]),
                    target: secondTarget,
                    options: .live
                )
            ]
        ) { payloads in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(payloads.map(\.requestID), [firstRequestID, secondRequestID])
            XCTAssertEqual(payloads.map { $0.result.match?.displayText }, ["C", "G/B"])
            XCTAssertEqual(payloads.map(\.timing.strokeCount), [1, 2])
            XCTAssertEqual(payloads[0].target.measureID, firstTarget.measureID)
            XCTAssertEqual(payloads[1].target.measureID, secondTarget.measureID)
            XCTAssertEqual(recognizer.receivedStrokeCounts, [1, 2])
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    private static func result(
        for text: String,
        confidence: Double
    ) -> ChordInkRecognitionResult {
        ChordInkRecognitionResult(
            rawCandidates: [text],
            glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text),
            confidence: confidence,
            candidateScores: [
                ChordInkCandidateScore(
                    text: text,
                    displayText: ChordRecognitionCompendium.match(text)?.displayText,
                    confidence: confidence
                )
            ]
        )
    }

    private static func stroke(offsetX: Double) -> InkStroke {
        InkStroke(points: [
            InkPoint(x: offsetX, y: 0, timeOffset: 0),
            InkPoint(x: offsetX + 4, y: 8, timeOffset: 0.1)
        ])
    }
}

private final class StubChordInkRecognizer: ChordInkRecognizing {
    private var results: [ChordInkRecognitionResult]
    private var nextResultIndex = 0
    private(set) var receivedStrokeCounts: [Int] = []

    init(results: [ChordInkRecognitionResult]) {
        self.results = results
    }

    func recognize(
        strokes: [InkStroke],
        options _: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        receivedStrokeCounts.append(strokes.count)
        defer {
            nextResultIndex += 1
        }
        return results[min(nextResultIndex, results.count - 1)]
    }
}
#endif

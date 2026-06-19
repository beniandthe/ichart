#if canImport(UIKit)
import CoreGraphics
import XCTest
@testable import iChart

final class ChordInkRecognitionSessionTests: XCTestCase {
    func testSessionDeliversRecognitionPayloadOnMainThread() {
        let target = (measureID: UUID(), fraction: 0.5)
        let drawingData = Data([0x01, 0x02, 0x03])
        let expectedResult = ChordInkRecognitionResult(
            rawCandidates: ["C"],
            glyphCandidates: [],
            match: ChordRecognitionCompendium.match("C"),
            confidence: 4.5
        )
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-session.no-ocr"),
            recognizer: StubChordInkRecognizer(result: expectedResult),
            ocrCandidateProvider: nil
        )
        let expectation = expectation(description: "recognition payload")

        session.start(
            request: ChordInkRecognitionSessionRequest(
                requestID: UUID(),
                scheduledAt: Date(),
                requestedDelay: 0.1,
                strokes: [],
                drawingData: drawingData,
                target: target,
                options: .live,
                ocrImageProvider: {
                    XCTFail("OCR image should not be requested without an OCR provider")
                    return nil
                }
            )
        ) { payload in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(payload.result.match?.displayText, "C")
            XCTAssertEqual(payload.drawingData, drawingData)
            XCTAssertEqual(payload.target.measureID, target.measureID)
            XCTAssertEqual(payload.target.fraction, target.fraction)
            XCTAssertEqual(payload.timing.strokeCount, 0)
            XCTAssertEqual(payload.timing.ocrCandidateCount, 0)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testSessionRequestsOCROnlyWhenTrustPolicyNeedsIt() {
        let ocrCandidate = ChordOCRCandidate.normalized(
            rawText: "C",
            confidence: 0.9,
            source: .testDouble
        )
        let ocrProvider = StubChordOCRCandidateProvider(candidates: [ocrCandidate])
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-session.ocr"),
            recognizer: StubChordInkRecognizer(
                result: ChordInkRecognitionResult(
                    rawCandidates: ["C"],
                    glyphCandidates: [],
                    match: ChordRecognitionCompendium.match("C"),
                    confidence: 1.0
                )
            ),
            ocrCandidateProvider: ocrProvider
        )
        var didRequestOCRImage = false
        let expectation = expectation(description: "ocr payload")

        session.start(
            request: ChordInkRecognitionSessionRequest(
                requestID: UUID(),
                scheduledAt: Date(),
                requestedDelay: 0.1,
                strokes: [],
                drawingData: Data(),
                target: (measureID: UUID(), fraction: 0),
                options: .live,
                ocrImageProvider: {
                    didRequestOCRImage = true
                    return Self.makeTestImage()
                }
            )
        ) { payload in
            XCTAssertTrue(didRequestOCRImage)
            XCTAssertEqual(ocrProvider.recognizeCallCount, 1)
            XCTAssertEqual(payload.result.ocrCandidates, [ocrCandidate])
            XCTAssertNotNil(payload.result.metrics.ocrMilliseconds)
            XCTAssertEqual(payload.timing.ocrCandidateCount, 1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testSessionSkipsOCRWhenPrimaryDecisionDoesNotNeedSidecarEvidence() {
        let ocrProvider = StubChordOCRCandidateProvider(candidates: [
            ChordOCRCandidate.normalized(
                rawText: "C",
                confidence: 0.9,
                source: .testDouble
            )
        ])
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-session.skip-ocr"),
            recognizer: StubChordInkRecognizer(
                result: ChordInkRecognitionResult(
                    rawCandidates: ["C"],
                    glyphCandidates: [],
                    match: ChordRecognitionCompendium.match("C"),
                    confidence: 4.5
                )
            ),
            ocrCandidateProvider: ocrProvider
        )
        let expectation = expectation(description: "no ocr payload")

        session.start(
            request: ChordInkRecognitionSessionRequest(
                requestID: UUID(),
                scheduledAt: Date(),
                requestedDelay: 0.1,
                strokes: [],
                drawingData: Data(),
                target: (measureID: UUID(), fraction: 0),
                options: .live,
                ocrImageProvider: {
                    XCTFail("OCR image should not be requested for a clear primary decision")
                    return Self.makeTestImage()
                }
            )
        ) { payload in
            XCTAssertEqual(ocrProvider.recognizeCallCount, 0)
            XCTAssertNil(payload.result.ocrCandidates)
            XCTAssertNil(payload.result.metrics.ocrMilliseconds)
            XCTAssertEqual(payload.timing.ocrCandidateCount, 0)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    private static func makeTestImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}

private struct StubChordInkRecognizer: ChordInkRecognizing {
    var result: ChordInkRecognitionResult

    func recognize(
        strokes _: [InkStroke],
        options _: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        result
    }
}

private final class StubChordOCRCandidateProvider: ChordOCRCandidateProviding {
    var candidates: [ChordOCRCandidate]
    var recognizeCallCount = 0

    init(candidates: [ChordOCRCandidate]) {
        self.candidates = candidates
    }

    func recognizeCandidates(in _: CGImage) -> [ChordOCRCandidate] {
        recognizeCallCount += 1
        return candidates
    }
}
#endif

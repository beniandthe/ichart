#if canImport(UIKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkRecognitionSessionTests: XCTestCase {
    func testReviewOnlyRequestBypassesRecognitionPersonalizationAndExistingCacheWithoutPoisoningIt() throws {
        let recognizer = StubChordInkRecognizer(results: [Self.result(for: "C", confidence: 4.5)])
        let session = ChordInkRecognitionSession(queue: .init(label: "review-only-cache"), recognizer: recognizer,
            allowsPersonalInk: true)
        var request = Self.request(strokeCount: 1)
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        try profile.learn(strokes: request.strokes, label: "G", kind: .chord, source: .explicitCorrection)
        request.evaluationContext = .init(runID: UUID(), profile: PersonalInkSnapshot(profile: profile))
        for (index, reviewOnly) in [false, true, false].enumerated() {
            request.requiresManualReviewOnly = reviewOnly
            let done = expectation(description: "review-only \(reviewOnly)")
            let expectedRequest = request
            session.start(request: request) { payload in
                XCTAssertEqual(payload.strokes, expectedRequest.strokes)
                XCTAssertEqual(payload.drawingData, expectedRequest.drawingData)
                XCTAssertEqual(payload.target.measureID, expectedRequest.target.measureID)
                XCTAssertEqual(payload.target.fraction, expectedRequest.target.fraction)
                XCTAssertEqual(payload.requiresManualReviewOnly, reviewOnly)
                if reviewOnly {
                    XCTAssertNil(payload.result.match)
                    XCTAssertEqual(payload.result.confidence, 0)
                    XCTAssertTrue(payload.result.rawCandidates.isEmpty)
                    XCTAssertTrue(payload.result.candidateScores.isEmpty)
                    XCTAssertNil(payload.result.personalSuggestion)
                    XCTAssertNil(payload.evaluationPrediction)
                    XCTAssertTrue(payload.result.requiresEditReview)
                    XCTAssertFalse(payload.timing.cacheHit)
                    XCTAssertEqual(payload.result.metrics.strokeCount, 1)
                } else {
                    XCTAssertEqual(payload.result.match?.displayText, "C")
                    XCTAssertNotNil(payload.evaluationPrediction)
                    XCTAssertEqual(payload.timing.cacheHit, index == 2)
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
        XCTAssertEqual(recognizer.receivedStrokeCounts, [1])
    }

    func testEditReviewIsRequestLocalEvenOnCacheHitsAndPairedEvaluation() {
        for flags in [[false, true, false], [true, false]] {
            let recognizer = StubChordInkRecognizer(results: [Self.result(for: "C", confidence: 4.5)])
            let session = ChordInkRecognitionSession(queue: .init(label: "edit-review-cache"), recognizer: recognizer,
                allowsPersonalInk: true)
            var request = Self.request(strokeCount: 1)
            request.evaluationContext = .init(runID: UUID(), profile: PersonalInkSnapshot(profile: .init()))
            for (index, requiresReview) in flags.enumerated() {
                request.requiresEditReview = requiresReview
                let done = expectation(description: "review flag \(requiresReview)")
                session.start(request: request) { payload in
                    XCTAssertEqual(payload.result.match?.displayText, "C")
                    XCTAssertEqual(payload.result.requiresEditReview, requiresReview)
                    XCTAssertEqual(payload.timing.cacheHit, index > 0)
                    let action = requiresReview ? "confirm" : "trusted"
                    XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: payload.result).action.rawValue, action)
                    XCTAssertEqual(payload.evaluationPrediction?.baselineAction, action)
                    XCTAssertEqual(payload.evaluationPrediction?.personalizedAction, action)
                    XCTAssertEqual(payload.evaluationPrediction?.baselineRecognitionAction, "trusted")
                    done.fulfill()
                }
                wait(for: [done], timeout: 3)
            }
            XCTAssertEqual(recognizer.receivedStrokeCounts, [1])
        }
    }

    func testEditReviewOnCacheHitCannotEnableAConflictingPersonalOverride() throws {
        var request = Self.request(strokeCount: 1)
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        try profile.learn(strokes: request.strokes, label: "G", kind: .chord, source: .explicitCorrection)
        request.evaluationContext = .init(runID: UUID(), profile: PersonalInkSnapshot(profile: profile))
        let recognizer = StubChordInkRecognizer(results: [Self.result(for: "C", confidence: 4.5)])
        let session = ChordInkRecognitionSession(queue: .init(label: "edit-personal-cache"), recognizer: recognizer,
            allowsPersonalInk: true)
        for (index, edited) in [false, true, false].enumerated() {
            request.requiresEditReview = edited
            let done = expectation(description: "edit and personal arbitration")
            session.start(request: request) { payload in
                XCTAssertEqual(payload.timing.cacheHit, index > 0)
                XCTAssertEqual(payload.result.personalSuggestion?.text, "G")
                XCTAssertEqual(payload.result.requiresEditReview, edited)
                XCTAssertEqual(payload.evaluationPrediction?.baseline, "C")
                XCTAssertEqual(payload.evaluationPrediction?.personalized, "C")
                XCTAssertEqual(payload.evaluationPrediction?.baselineRecognitionAction, "trusted")
                XCTAssertEqual(payload.evaluationPrediction?.personalArbitration, "protectedBaseline")
                XCTAssertEqual(payload.evaluationPrediction?.personalizedAction, edited ? "confirm" : "trusted")
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
        XCTAssertEqual(recognizer.receivedStrokeCounts, [1])
    }

    func testEvaluationUsesFrozenProfileAndRecordsBothPredictionsWithoutChangingNativeTrust() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        var request = Self.request(strokeCount: 1)
        var frozenProfile = PersonalInkProfile(); frozenProfile.isEnabled = true
        try frozenProfile.learn(strokes: request.strokes, label: "G", kind: .chord, source: .setup)
        let runID = UUID()
        request.evaluationContext = .init(runID: runID, profile: PersonalInkSnapshot(profile: frozenProfile))
        try store.update {
            $0.isEnabled = true
            try $0.learn(strokes: request.strokes, label: "A", kind: .chord, source: .setup)
        }
        let session = ChordInkRecognitionSession(queue: .init(label: "evaluation-frozen"),
            recognizer: StubChordInkRecognizer(results: [Self.result(for: "C", confidence: 4.5)]), personalProfile: store,
            allowsPersonalInk: true)
        let done = expectation(description: "paired evidence")
        session.start(request: request) { payload in
            XCTAssertEqual(payload.result.match?.displayText, "C")
            XCTAssertEqual(payload.result.personalSuggestion?.text, "G", "Must use frozen G, not newly learned A")
            XCTAssertEqual(payload.evaluationPrediction?.baseline, "C")
            XCTAssertEqual(payload.evaluationPrediction?.personalized, "C")
            XCTAssertEqual(payload.evaluationPrediction?.personalizedAction, "trusted")
            XCTAssertEqual(payload.evaluationPrediction?.personalSuggestion?.text, "G")
            XCTAssertEqual(payload.evaluationPrediction?.personalArbitration, "protectedBaseline")
            XCTAssertEqual(payload.evaluationPrediction?.runID, runID)
            XCTAssertEqual(payload.evaluationPrediction?.knownInk, true)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        request.evaluationContext = nil
        let normal = expectation(description: "normal profile restored")
        session.start(request: request) { payload in
            XCTAssertEqual(payload.result.personalSuggestion?.text, "A")
            XCTAssertNil(payload.evaluationPrediction)
            normal.fulfill()
        }
        wait(for: [normal], timeout: 3)
    }

    func testProfileChangesInvalidatePersonalChoicesWithoutRepeatingBaseRecognition() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let request = Self.request(strokeCount: 1)
        let recognizer = StubChordInkRecognizer(results: [Self.result(for: "C", confidence: 4.5)])
        let session = ChordInkRecognitionSession(queue: DispatchQueue(label: "personal-cache-test"), recognizer: recognizer,
            personalProfile: store, allowsPersonalInk: true)
        let first = expectation(description: "base")
        session.start(request: request) { payload in
            XCTAssertNil(payload.result.personalSuggestion)
            first.fulfill()
        }
        wait(for: [first], timeout: 2)
        try store.update {
            $0.isEnabled = true
            try $0.learn(strokes: request.strokes, label: "G", kind: .chord, source: .setup)
        }
        let second = expectation(description: "personalized")
        session.start(request: request) { payload in
            XCTAssertTrue(payload.timing.cacheHit)
            XCTAssertEqual(payload.result.match?.displayText, "C")
            XCTAssertEqual(payload.result.personalSuggestion?.text, "G")
            let pending = PendingChordInkConfirmation(measureID: request.target.measureID, measureIndex: 0,
                result: payload.result, drawingData: request.drawingData, targetFraction: 0,
                primaryDecision: ChordInkRecognitionPolicy.decision(for: payload.result),
                decision: ChordInkRenderResolutionPolicy.resolution(for: payload.result, drawingData: request.drawingData, correctionMemory: .init()).decision)
            XCTAssertEqual(pending.bestCandidateText, "C")
            second.fulfill()
        }
        wait(for: [second], timeout: 2)
        try store.reset()
        let third = expectation(description: "reset")
        session.start(request: request) { payload in
            XCTAssertNil(payload.result.personalSuggestion)
            XCTAssertTrue(payload.timing.cacheHit)
            third.fulfill()
        }
        wait(for: [third], timeout: 2)
        XCTAssertEqual(recognizer.receivedStrokeCounts, [1])
    }

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
            XCTAssertEqual(payload.targetLifecycle?.generationID, requestID)
            XCTAssertEqual(payload.targetLifecycle?.stage, .stable)
            XCTAssertEqual(payload.targetLifecycle?.anchor.measureID, target.measureID)
            XCTAssertEqual(payload.targetLifecycle?.ownership.preparedStrokes, [])
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

    func testStartingNewOperationSkipsPreviouslyQueuedRecognition() {
        let queue = DispatchQueue(label: "com.ichart.tests.chord-session.cancellation")
        queue.suspend()
        let recognizer = StubChordInkRecognizer(results: [
            Self.result(for: "G", confidence: 4.5)
        ])
        let session = ChordInkRecognitionSession(queue: queue, recognizer: recognizer)
        let obsoleteCompletion = expectation(description: "obsolete completion")
        obsoleteCompletion.isInverted = true
        let currentCompletion = expectation(description: "current completion")

        session.start(
            request: Self.request(strokeCount: 1)
        ) { _ in
            obsoleteCompletion.fulfill()
        }
        session.start(
            request: Self.request(strokeCount: 2)
        ) { payload in
            XCTAssertEqual(payload.timing.strokeCount, 2)
            currentCompletion.fulfill()
        }
        queue.resume()

        wait(for: [currentCompletion], timeout: 1)
        wait(for: [obsoleteCompletion], timeout: 0.25)
        XCTAssertEqual(recognizer.receivedStrokeCounts, [2])
    }

    func testCancellingPendingWorkSkipsQueuedRecognition() {
        let queue = DispatchQueue(label: "com.ichart.tests.chord-session.explicit-cancellation")
        queue.suspend()
        let recognizer = StubChordInkRecognizer(results: [
            Self.result(for: "D", confidence: 4.5)
        ])
        let session = ChordInkRecognitionSession(queue: queue, recognizer: recognizer)
        let completion = expectation(description: "cancelled completion")
        completion.isInverted = true

        session.start(request: Self.request(strokeCount: 1)) { _ in
            completion.fulfill()
        }
        session.cancelPendingWork()
        queue.resume()

        wait(for: [completion], timeout: 0.25)
        XCTAssertEqual(recognizer.receivedStrokeCounts, [])
    }

    func testCancellingBatchStopsRemainingTargetsAndDropsCompletion() {
        let firstRecognitionStarted = DispatchSemaphore(value: 0)
        let releaseFirstRecognition = DispatchSemaphore(value: 0)
        let recognizer = BlockingChordInkRecognizer(
            result: Self.result(for: "C", confidence: 4.5),
            firstRecognitionStarted: firstRecognitionStarted,
            releaseFirstRecognition: releaseFirstRecognition
        )
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-session.batch-cancellation"),
            recognizer: recognizer
        )
        let completion = expectation(description: "cancelled batch completion")
        completion.isInverted = true

        session.startBatch(
            requests: [
                Self.request(strokeCount: 1),
                Self.request(strokeCount: 2),
                Self.request(strokeCount: 3)
            ]
        ) { _ in
            completion.fulfill()
        }

        XCTAssertEqual(firstRecognitionStarted.wait(timeout: .now() + 1), .success)
        session.cancelPendingWork()
        releaseFirstRecognition.signal()

        wait(for: [completion], timeout: 0.25)
        XCTAssertEqual(recognizer.receivedStrokeCounts, [1])
    }

    func testSessionReusesRecognitionResultForUnchangedStrokesAfterArchiveReserialization() {
        let expectedResult = Self.result(for: "F#-7", confidence: 4.6)
        let recognizer = StubChordInkRecognizer(results: [expectedResult])
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-session.cache"),
            recognizer: recognizer
        )
        var firstRequest = Self.request(strokeCount: 3)
        firstRequest.drawingData = Data([0x01, 0x04, 0x09])
        var secondRequest = Self.request(strokeCount: 3)
        secondRequest.drawingData = Data([0x09, 0x04, 0x01])
        let firstCompletion = expectation(description: "first recognition")
        let secondCompletion = expectation(description: "cached recognition")

        session.start(request: firstRequest) { payload in
            XCTAssertFalse(payload.timing.cacheHit)
            firstCompletion.fulfill()
        }
        wait(for: [firstCompletion], timeout: 1)

        session.start(request: secondRequest) { payload in
            XCTAssertTrue(payload.timing.cacheHit)
            XCTAssertEqual(payload.result, expectedResult)
            secondCompletion.fulfill()
        }
        wait(for: [secondCompletion], timeout: 1)

        XCTAssertEqual(recognizer.receivedStrokeCounts, [3])
    }

    func testSessionDoesNotReuseRecognitionResultWhenArchiveBytesMatchButStrokesChange() {
        let firstResult = Self.result(for: "C", confidence: 4.6)
        let secondResult = Self.result(for: "G", confidence: 4.6)
        let recognizer = StubChordInkRecognizer(results: [firstResult, secondResult])
        let session = ChordInkRecognitionSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-session.semantic-cache"),
            recognizer: recognizer
        )
        let sharedArchiveBytes = Data([0x01, 0x04, 0x09])
        var firstRequest = Self.request(strokeCount: 1)
        firstRequest.drawingData = sharedArchiveBytes
        var secondRequest = Self.request(strokeCount: 2)
        secondRequest.drawingData = sharedArchiveBytes
        let firstCompletion = expectation(description: "first geometry")
        let secondCompletion = expectation(description: "different geometry")

        session.start(request: firstRequest) { payload in
            XCTAssertFalse(payload.timing.cacheHit)
            XCTAssertEqual(payload.result, firstResult)
            firstCompletion.fulfill()
        }
        wait(for: [firstCompletion], timeout: 1)

        session.start(request: secondRequest) { payload in
            XCTAssertFalse(payload.timing.cacheHit)
            XCTAssertEqual(payload.result, secondResult)
            secondCompletion.fulfill()
        }
        wait(for: [secondCompletion], timeout: 1)

        XCTAssertEqual(recognizer.receivedStrokeCounts, [1, 2])
    }

    func testPreparationSessionDropsCancelledQueuedWork() {
        let queue = DispatchQueue(label: "com.ichart.tests.chord-preparation.cancellation")
        queue.suspend()
        let session = ChordInkRecognitionPreparationSession(queue: queue)
        let completion = expectation(description: "cancelled preparation")
        completion.isInverted = true

        session.start(request: Self.invalidPreparationRequest()) { _ in
            completion.fulfill()
        }
        session.cancelPendingWork()
        queue.resume()

        wait(for: [completion], timeout: 0.25)
    }

    func testPreparationSessionDeliversResultOnMainThread() {
        let session = ChordInkRecognitionPreparationSession(
            queue: DispatchQueue(label: "com.ichart.tests.chord-preparation.delivery")
        )
        let completion = expectation(description: "preparation result")

        session.start(request: Self.invalidPreparationRequest()) { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case .invalidDrawingData = result.outcome else {
                return XCTFail("Expected invalid drawing data outcome")
            }
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
    }

    func testPreparationStopsBetweenExpensiveStagesWhenCancelled() {
        let drawing = PKDrawing(strokes: [Self.pkStroke()])
        var continuationChecks = 0
        let result = ChordInkRecognitionPreparation.prepare(
            Self.preparationRequest(drawingData: drawing.dataRepresentation())
        ) {
            continuationChecks += 1
            return continuationChecks < 3
        }

        guard case .cancelled = result.outcome else {
            return XCTFail("Expected preparation to stop at a cancellation checkpoint")
        }
        XCTAssertEqual(continuationChecks, 3)
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

    private static func request(strokeCount: Int) -> ChordInkRecognitionSessionRequest {
        ChordInkRecognitionSessionRequest(
            requestID: UUID(),
            scheduledAt: Date(),
            requestedDelay: 0,
            strokes: (0..<strokeCount).map { stroke(offsetX: Double($0 * 10)) },
            drawingData: Data([UInt8(strokeCount)]),
            target: (UUID(), 0.5),
            options: .live
        )
    }

    private static func invalidPreparationRequest() -> ChordInkRecognitionPreparationRequest {
        preparationRequest(drawingData: Data([0xFF, 0x00]))
    }

    private static func preparationRequest(drawingData: Data) -> ChordInkRecognitionPreparationRequest {
        ChordInkRecognitionPreparationRequest(
            requestID: UUID(),
            scheduledAt: Date(),
            requestedDelay: 0,
            drawingData: drawingData,
            chordFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            pageLayout: nil,
            flow: .draftPreview,
            options: .live,
            layoutStyle: .simpleChordSheet
        )
    }

    private static func pkStroke() -> PKStroke {
        let ink = PKInk(.pen, color: .black)
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 8, y: 8),
                timeOffset: 0,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 28, y: 38),
                timeOffset: 0.1,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        ]
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
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

private final class BlockingChordInkRecognizer: ChordInkRecognizing {
    private let result: ChordInkRecognitionResult
    private let firstRecognitionStarted: DispatchSemaphore
    private let releaseFirstRecognition: DispatchSemaphore
    private let lock = NSLock()
    private var strokeCounts: [Int] = []

    var receivedStrokeCounts: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return strokeCounts
    }

    init(
        result: ChordInkRecognitionResult,
        firstRecognitionStarted: DispatchSemaphore,
        releaseFirstRecognition: DispatchSemaphore
    ) {
        self.result = result
        self.firstRecognitionStarted = firstRecognitionStarted
        self.releaseFirstRecognition = releaseFirstRecognition
    }

    func recognize(
        strokes: [InkStroke],
        options _: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        lock.lock()
        strokeCounts.append(strokes.count)
        let isFirstRecognition = strokeCounts.count == 1
        lock.unlock()

        if isFirstRecognition {
            firstRecognitionStarted.signal()
            _ = releaseFirstRecognition.wait(timeout: .now() + 2)
        }
        return result
    }
}
#endif

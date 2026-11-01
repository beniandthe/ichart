#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class ChordInkIncrementalRecognitionSessionTests: XCTestCase {
    func testFinishedFPublishesWhileGRecognitionIsStillBlocked() {
        let recognizer = IncrementalBlockingRecognizer(blockingMarker: 100)
        defer { recognizer.release.signal() }
        let session = makeSession(recognizer)
        let measureID = UUID()
        let f = request(0, measureID: measureID, fraction: 0.25)
        let g = request(100, measureID: measureID, fraction: 0.75)
        let fDone = expectation(description: "F published before G finishes")
        let gDone = expectation(description: "G published after its read")
        var publications: [String] = []
        session.startIncremental(requests: [f, g]) { payload in
            XCTAssertTrue(Thread.isMainThread)
            publications.append(payload.result.match?.displayText ?? "?")
            if payload.target.fraction == f.target.fraction { fDone.fulfill() }
            else { gDone.fulfill() }
        }
        XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)
        wait(for: [fDone], timeout: 1)
        XCTAssertEqual(publications, ["F"])
        recognizer.release.signal()
        wait(for: [gDone], timeout: 1)
        XCTAssertEqual(publications, ["F", "G"])
        XCTAssertEqual(recognizer.markers, [0, 100])
    }

    func testChangingGKeepsFInFlightAndPublishesUsingLatestEnvelope() {
        let recognizer = IncrementalBlockingRecognizer(blockingMarker: 0)
        defer { recognizer.release.signal() }
        let session = makeSession(recognizer)
        let measureID = UUID()
        let firstF = request(0, measureID: measureID, fraction: 0.25)
        let firstG = request(100, measureID: measureID, fraction: 0.75)
        session.startIncremental(requests: [firstF, firstG]) { _ in
            XCTFail("An old census callback cannot receive the current target")
        }
        XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)
        var latestF = firstF
        latestF.requestID = UUID()
        latestF.drawingData = Data([9, 8, 7])
        latestF.target.fraction = 0.251 // Same anchor bucket, current geometry envelope.
        latestF.layoutPageSize = CGSize(width: 1_000, height: 1_400)
        latestF.scheduledAt = Date()
        let latestG = request(110, measureID: measureID, fraction: 0.75)
        let fDone = expectation(description: "unchanged F survives")
        let gDone = expectation(description: "changed G read")
        session.startIncremental(requests: [latestF, latestG]) { payload in
            if payload.target.fraction == latestF.target.fraction {
                XCTAssertEqual(payload.requestID, latestF.requestID)
                XCTAssertEqual(payload.drawingData, latestF.drawingData)
                XCTAssertEqual(payload.layoutPageSize, latestF.layoutPageSize)
                XCTAssertEqual(payload.targetLifecycle?.generationID, latestF.requestID)
                XCTAssertEqual(payload.targetLifecycle?.ownership.preparedStrokes, firstF.strokes)
                XCTAssertEqual(payload.targetLifecycle?.stage, .stable)
                XCTAssertGreaterThanOrEqual(payload.timing.idleMilliseconds, 0)
                fDone.fulfill()
            } else {
                XCTAssertEqual(payload.strokes, latestG.strokes)
                gDone.fulfill()
            }
        }
        recognizer.release.signal()
        wait(for: [fDone, gDone], timeout: 2)
        XCTAssertEqual(recognizer.markers, [0, 110], "Queued obsolete G must never enter the reader")
    }

    func testCompletedFIsReusedImmediatelyWhileChangedGRemainsBlocked() {
        let recognizer = IncrementalBlockingRecognizer(blockingMarker: 110)
        defer { recognizer.release.signal() }
        let session = makeSession(recognizer)
        let measureID = UUID()
        let f = request(0, measureID: measureID, fraction: 0.25)
        let g = request(100, measureID: measureID, fraction: 0.75)
        let first = expectation(description: "first census")
        first.expectedFulfillmentCount = 2
        session.startIncremental(requests: [f, g]) { _ in first.fulfill() }
        wait(for: [first], timeout: 1)
        var latestF = f
        latestF.requestID = UUID()
        latestF.drawingData = Data([0xAB])
        let changedG = request(110, measureID: measureID, fraction: 0.75)
        let reusedF = expectation(description: "completed F replayed")
        let changedGDone = expectation(description: "changed G")
        session.startIncremental(requests: [latestF, changedG]) { payload in
            if payload.target.fraction == latestF.target.fraction {
                XCTAssertEqual(payload.requestID, latestF.requestID)
                XCTAssertEqual(payload.drawingData, latestF.drawingData)
                XCTAssertTrue(payload.timing.cacheHit)
                reusedF.fulfill()
            } else { changedGDone.fulfill() }
        }
        XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)
        wait(for: [reusedF], timeout: 1)
        recognizer.release.signal()
        wait(for: [changedGDone], timeout: 1)
        XCTAssertEqual(recognizer.markers, [0, 100, 110])
    }

    func testEditingFDiscardsItsOldInflightReadAndPublishesOnlyCurrentSource() {
        let recognizer = IncrementalBlockingRecognizer(blockingMarker: 0)
        defer { recognizer.release.signal() }
        let session = makeSession(recognizer)
        let measureID = UUID()
        let old = request(0, measureID: measureID, fraction: 0.25)
        session.startIncremental(requests: [old]) { _ in XCTFail("Old F source must be dropped") }
        XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)
        let edited = request(10, measureID: measureID, fraction: 0.25)
        let done = expectation(description: "edited F")
        var publications = 0
        session.startIncremental(requests: [edited]) { payload in
            publications += 1
            XCTAssertEqual(payload.strokes, edited.strokes)
            XCTAssertEqual(payload.requestID, edited.requestID)
            XCTAssertEqual(payload.drawingData, edited.drawingData)
            done.fulfill()
        }
        recognizer.release.signal()
        wait(for: [done], timeout: 1)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(recognizer.markers, [0, 10])
    }

    func testIncrementalAndGlobalCancellationDropInflightCallback() {
        for cancelsAll in [false, true] {
            let recognizer = IncrementalBlockingRecognizer(blockingMarker: 0)
            defer { recognizer.release.signal() }
            let session = makeSession(recognizer)
            let unexpected = expectation(description: "cancelled callback \(cancelsAll)")
            unexpected.isInverted = true
            session.startIncremental(requests: [request(0, measureID: UUID(), fraction: 0.5)]) { _ in
                unexpected.fulfill()
            }
            XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)
            if cancelsAll { session.cancelPendingWork() }
            else { session.cancelIncrementalWork() }
            recognizer.release.signal()
            wait(for: [unexpected], timeout: 0.2)
        }
    }

    func testCancellingLegacyBatchWorkDoesNotCancelUnchangedIncrementalTarget() {
        let recognizer = IncrementalBlockingRecognizer(blockingMarker: 0)
        defer { recognizer.release.signal() }
        let session = makeSession(recognizer)
        let done = expectation(description: "incremental survives input batch invalidation")
        session.startIncremental(requests: [request(0, measureID: UUID(), fraction: 0.5)]) { _ in done.fulfill() }
        XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)
        session.cancelBatchWork()
        recognizer.release.signal()
        wait(for: [done], timeout: 1)
    }

    func testLegacyManualBatchStillWaitsForWholeBatchAndPreservesRequestOrder() {
        let recognizer = IncrementalBlockingRecognizer(blockingMarker: 100)
        defer { recognizer.release.signal() }
        let session = makeSession(recognizer)
        let measureID = UUID()
        let requests = [request(0, measureID: measureID, fraction: 0.25), request(100, measureID: measureID, fraction: 0.75)]
        let done = expectation(description: "manual batch")
        var delivered = false
        session.startBatch(requests: requests) { payloads in
            delivered = true
            XCTAssertEqual(payloads.map(\.requestID), requests.map(\.requestID))
            XCTAssertEqual(payloads.compactMap { $0.result.match?.displayText }, ["F", "G"])
            done.fulfill()
        }
        XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(delivered)
        recognizer.release.signal()
        wait(for: [done], timeout: 1)
    }

    func testSharedIdentityIncludesRecognitionReviewAndEvaluationScopesButNotArchiveEnvelope() {
        let first = request(0, measureID: UUID(), fraction: 0.25)
        let key = ChordInkRecognitionIncrementalTargetKey(request: first)
        var envelope = first
        envelope.requestID = UUID()
        envelope.drawingData = Data([99])
        envelope.scheduledAt = .distantFuture
        XCTAssertEqual(key, ChordInkRecognitionIncrementalTargetKey(request: envelope))
        var edited = first
        edited.requiresEditReview = true
        XCTAssertNotEqual(key, ChordInkRecognitionIncrementalTargetKey(request: edited))
        edited = first
        edited.requiresManualReviewOnly = true
        XCTAssertNotEqual(key, ChordInkRecognitionIncrementalTargetKey(request: edited))
        edited = first
        edited.options = .includingSymbolLedgerDiagnostics
        XCTAssertNotEqual(key, ChordInkRecognitionIncrementalTargetKey(request: edited))
        edited = first
        edited.target.measureID = UUID()
        XCTAssertNotEqual(key, ChordInkRecognitionIncrementalTargetKey(request: edited))
        edited = first
        edited.evaluationContext = PersonalInkEvaluationContext(runID: UUID(), profile: .init(profile: .init()))
        let evaluationKey = ChordInkRecognitionIncrementalTargetKey(request: edited)
        XCTAssertNotEqual(key, evaluationKey)
        edited.evaluationContext = PersonalInkEvaluationContext(runID: edited.evaluationContext!.runID,
            profile: .init(profile: .init()))
        XCTAssertNotEqual(evaluationKey, ChordInkRecognitionIncrementalTargetKey(request: edited))
    }

    func testChangingReviewScopeCannotPublishAnEarlierTrustedRead() {
        let recognizer = IncrementalBlockingRecognizer(blockingMarker: 0)
        defer { recognizer.release.signal() }
        let session = makeSession(recognizer)
        let original = request(0, measureID: UUID(), fraction: 0.25)
        session.startIncremental(requests: [original]) { _ in XCTFail("Earlier trust scope is obsolete") }
        XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)
        var reviewed = original
        reviewed.requestID = UUID()
        reviewed.requiresEditReview = true
        let done = expectation(description: "current review scope")
        session.startIncremental(requests: [reviewed]) { payload in
            XCTAssertEqual(payload.requestID, reviewed.requestID)
            XCTAssertTrue(payload.result.requiresEditReview)
            XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: payload.result).action, .confirm)
            XCTAssertTrue(payload.timing.cacheHit, "Base recognition may be reused; old trust scope may not")
            done.fulfill()
        }
        recognizer.release.signal()
        wait(for: [done], timeout: 1)
        XCTAssertEqual(recognizer.markers, [0])
    }

    func testLiveProfileRevisionChangeDropsInflightInterpretationAndReusesOnlyNativeRead() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileStore = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let originalRevision = profileStore.snapshot().profile.revision
        let recognizer = IncrementalBlockingRecognizer(blockingMarker: 0)
        defer { recognizer.release.signal() }
        let session = ChordInkRecognitionSession(queue: DispatchQueue(label: "ichart.tests.incremental.profile"),
            recognizer: recognizer, personalProfile: profileStore, allowsPersonalInk: true)
        let original = request(0, measureID: UUID(), fraction: 0.25)
        session.startIncremental(requests: [original]) { _ in
            XCTFail("The old live-profile interpretation must not publish in a new profile scope")
        }
        XCTAssertEqual(recognizer.started.wait(timeout: .now() + 1), .success)

        try profileStore.update { profile in
            profile.isEnabled = true
            try profile.learn(strokes: original.strokes, label: "G", kind: .chord, source: .explicitCorrection)
        }
        let currentRevision = profileStore.snapshot().profile.revision
        XCTAssertNotEqual(currentRevision, originalRevision)
        var current = original
        current.requestID = UUID()
        let done = expectation(description: "same target interpreted in the current live profile")
        var publications = 0
        session.startIncremental(requests: [current]) { payload in
            publications += 1
            XCTAssertEqual(payload.requestID, current.requestID)
            XCTAssertEqual(payload.result.personalizationRevision, currentRevision)
            XCTAssertEqual(payload.result.personalSuggestion?.text, "G")
            XCTAssertEqual(payload.result.match?.displayText, "F", "A personal suggestion cannot replace trusted native evidence")
            XCTAssertTrue(payload.timing.cacheHit, "Only unchanged native recognition may be reused across profile revisions")
            XCTAssertNil(payload.evaluationPrediction)
            done.fulfill()
        }
        recognizer.release.signal()
        wait(for: [done], timeout: 1)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(recognizer.markers, [0])
    }

    private func makeSession(_ recognizer: IncrementalBlockingRecognizer) -> ChordInkRecognitionSession {
        ChordInkRecognitionSession(queue: DispatchQueue(label: "ichart.tests.incremental.\(UUID())"),
            recognizer: recognizer, allowsPersonalInk: false)
    }

    private func request(_ marker: Double, measureID: UUID, fraction: Double) -> ChordInkRecognitionSessionRequest {
        ChordInkRecognitionSessionRequest(requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            strokes: [InkStroke(points: [InkPoint(x: marker, y: 0, timeOffset: 0),
                InkPoint(x: marker + 5, y: 10, timeOffset: 0.1)])],
            drawingData: Data([UInt8(marker)]), target: (measureID, fraction), options: .live)
    }
}

private final class IncrementalBlockingRecognizer: ChordInkRecognizing {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let blockingMarker: Int
    private let lock = NSLock()
    private var receivedMarkers: [Int] = []

    var markers: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return receivedMarkers
    }

    init(blockingMarker: Int) { self.blockingMarker = blockingMarker }

    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        let marker = Int(strokes.first?.points.first?.x ?? -1)
        lock.lock()
        receivedMarkers.append(marker)
        lock.unlock()
        if marker == blockingMarker {
            started.signal()
            _ = release.wait(timeout: .now() + 3)
        }
        let text = marker < 50 ? "F" : "G"
        return ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text), confidence: 4.5,
            candidateScores: [ChordInkCandidateScore(text: text, displayText: text, confidence: 4.5)])
    }
}
#endif

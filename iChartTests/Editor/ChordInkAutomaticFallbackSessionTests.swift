#if canImport(UIKit) && canImport(PencilKit) && canImport(Vision)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Deterministic provider doubles exercise scheduling and source authority.
/// They make no claim about the accuracy of native scales or Vision OCR.
@MainActor
final class ChordInkAutomaticFallbackSessionTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_200)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)

    func testSupportedPrimaryReadBypassesEveryFallback() async throws {
        let fallback = FallbackProviderDouble(identifier: "must-not-run") { _, _, _ in self.supported("G") }
        let primary = FallbackPrimaryDouble { _ in self.supported("Bb") }
        let session = makeSession(primary, fallback: [fallback])
        let request = request(x: 106)
        let done = expectation(description: "primary publication")
        var result: ChordInkRecognitionProposalPayload?
        session.startIncremental(requests: [request]) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
        let payload = try XCTUnwrap(result)
        XCTAssertEqual(payload.result.match?.displayText, "Bb")
        XCTAssertTrue(payload.result.fallbackEvidence.isEmpty)
        XCTAssertEqual(fallback.calls, 0)
        XCTAssertEqual(primary.calls, 1)
        XCTAssertEqual(payload.drawingData, request.drawingData)
    }

    func testFirstSupportedFallbackStopsChainAndPersistsItsProvenanceOnTheSourceOwningEditableEvent() async throws {
        let invalid = FallbackProviderDouble(identifier: "native-small") { _, _, _ in self.unread() }
        let recovered = FallbackProviderDouble(identifier: "vision-test", version: "vision-version-test") { _, _, _ in
            self.supported("D/F#")
        }
        let unused = FallbackProviderDouble(identifier: "must-not-run") { _, _, _ in self.supported("C") }
        let primaryRead = unread()
        let session = makeSession(FallbackPrimaryDouble { _ in primaryRead }, fallback: [invalid, recovered, unused])
        let chart = makeChart()
        let request = request(x: 106, measureID: chart.measures[0].id)
        let done = expectation(description: "fallback publication")
        var received: ChordInkRecognitionProposalPayload?
        session.startIncremental(requests: [request]) { received = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
        let payload = try XCTUnwrap(received)
        XCTAssertNil(payload.result.match, "Fallback must not rewrite the primary recognizer's answer")
        XCTAssertEqual(payload.result.confidence, primaryRead.confidence)
        XCTAssertEqual(payload.result.rawCandidates, primaryRead.rawCandidates)
        XCTAssertEqual(payload.result.fallbackEvidence.map(\.engineIdentifier), ["native-small", "vision-test"])
        XCTAssertEqual(payload.result.fallbackEvidence.map(\.candidateTexts), [[], ["D/F#"]])
        XCTAssertTrue(payload.result.fallbackEvidence.allSatisfy { $0.durationMilliseconds.isFinite && $0.durationMilliseconds >= 0 })
        XCTAssertEqual(invalid.calls, 1)
        XCTAssertEqual(recovered.calls, 1)
        XCTAssertEqual(unused.calls, 0)
        XCTAssertEqual(payload.strokes, request.strokes)
        XCTAssertEqual(payload.drawingData, request.drawingData)
        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: payload.result).action, .confirm)
        let draft = draft(payload, chart: chart)
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(draft))
        XCTAssertEqual(ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft), "D/F#")
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let outcome = try XCTUnwrap(ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart,
            state: .init(draftChords: [draft], layoutPageSize: pageSize),
            currentDrawing: PKDrawing(data: request.drawingData), coordinateSpace: .init(size: frame.size),
            now: inputAt.addingTimeInterval(2), lastInputAt: inputAt, isUsingTool: false,
            sourcePageLayout: layout, sourceChordFrame: frame).outcome)
        let id = try XCTUnwrap(outcome.result.renderedChordIDs.first)
        let event = try XCTUnwrap(outcome.chart.chordEvent(id: id))
        XCTAssertEqual(event.rawInput, "D/F#")
        let version = try XCTUnwrap(event.sourceRecognitionPipelineVersion)
        XCTAssertTrue(version.contains("vision-test"))
        XCTAssertTrue(version.contains("vision-version-test"))
        assertSameInk(try PKDrawing(data: request.drawingData), try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
        var corrected = outcome.chart
        let replacement = try XCTUnwrap(ChordRecognitionCompendium.match("D7"))
        XCTAssertTrue(corrected.replaceChordEvent(id, with: replacement.symbol, rawInput: "D7"))
        let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(corrected))
        let edited = try XCTUnwrap(reopened.chordEvent(id: id))
        XCTAssertEqual(edited.rawInput, "D7")
        XCTAssertEqual(edited.sourceRecognitionPipelineVersion, version)
        XCTAssertEqual(edited.startPosition, event.startPosition)
        XCTAssertEqual(edited.manualVisualLaneFraction, event.manualVisualLaneFraction)
        assertSameInk(try PKDrawing(data: request.drawingData), try PKDrawing(data: XCTUnwrap(edited.sourceInkData)))
    }

    func testBlockedFallbackDoesNotHoldTheAutomaticRenderOfASeparateSupportedPrimaryTarget() async throws {
        let started = expectation(description: "first target fallback blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let fallback = FallbackProviderDouble(identifier: "blocked") { _, _, _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 10)
            return self.supported("Bb")
        }
        let primary = FallbackPrimaryDouble { strokes in
            strokes.first!.bounds.minX < 200 ? self.unread() : self.supported("G")
        }
        let session = makeSession(primary, fallback: [fallback])
        let originalChart = makeChart()
        let measure = originalChart.measures[0].id
        let first = request(x: 106, measureID: measure)
        let neighbor = request(x: 300, measureID: measure, fraction: 0.5)
        let firstSource = try PKDrawing(data: first.drawingData)
        let neighborSource = try PKDrawing(data: neighbor.drawingData)
        var source = PKDrawing(strokes: firstSource.strokes + neighborSource.strokes)
        var chart = originalChart
        var census = ChordInkIncrementalDraftState()
        census.acceptCensus([first, neighbor])
        let neighborDone = expectation(description: "neighbor renders before blocked fallback finishes")
        let firstDone = expectation(description: "fallback target finally renders its own source")
        var delivered: [UUID] = []
        var neighborEvent: ChordEvent?
        var neighborFrame: CGRect?
        session.startIncremental(requests: [first, neighbor]) { payload in
            delivered.append(payload.requestID)
            do {
                let payloads = try XCTUnwrap(census.accept(payload))
                let state = ChordPreviewState(draftChords: payloads.map { self.draft($0, chart: chart) },
                    layoutPageSize: self.pageSize)
                let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: self.pageSize,
                    includesChordInkContinuationLanes: true)
                let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
                let outcome = try XCTUnwrap(ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart,
                    state: state, currentDrawing: source, coordinateSpace: .init(size: frame.size),
                    now: self.inputAt.addingTimeInterval(2), lastInputAt: self.inputAt, isUsingTool: false,
                    sourcePageLayout: sourceLayout, sourceChordFrame: frame).outcome)
                XCTAssertEqual(outcome.result.renderedChordCount, 1)
                let event = try XCTUnwrap(outcome.chart.chordEvent(id: XCTUnwrap(outcome.result.renderedChordIDs.first)))
                let finalLayout = LeadSheetPageLayoutEngine.pageLayout(for: outcome.chart, pageSize: self.pageSize,
                    includesChordInkContinuationLanes: true)
                let glyph = try XCTUnwrap(finalLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
                    .first { $0.id == event.id })
                if payload.requestID == neighbor.requestID {
                    XCTAssertEqual(event.rawInput, "G")
                    XCTAssertEqual(outcome.remainingState.draftChords.count, 1)
                    XCTAssertEqual(outcome.remainingState.draftChords.first?.targetLifecycle?.stage, .collecting)
                    self.assertSameInk(firstSource, outcome.drawing)
                    self.assertSameInk(firstSource, try PKDrawing(data: XCTUnwrap(outcome.chart.pageHandwrittenChordData)))
                    self.assertSameInk(neighborSource, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
                    let retainedPageFrames = firstSource.strokes.map {
                        $0.renderBounds.offsetBy(dx: frame.minX, dy: frame.minY)
                    }
                    XCTAssertFalse(retainedPageFrames.contains { glyph.frame.union(glyph.naturalFrame).intersects($0) })
                    neighborEvent = event
                    neighborFrame = glyph.naturalFrame
                } else {
                    XCTAssertEqual(event.rawInput, "Bb")
                    self.assertSameInk(firstSource, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
                    XCTAssertTrue(outcome.drawing.strokes.isEmpty)
                    XCTAssertNil(outcome.chart.pageHandwrittenChordData)
                    let existing = try XCTUnwrap(neighborEvent)
                    XCTAssertEqual(outcome.chart.chordEvent(id: existing.id), existing)
                    XCTAssertEqual(finalLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
                        .first { $0.id == existing.id }?.naturalFrame, neighborFrame)
                }
                chart = outcome.chart
                source = outcome.drawing
                census.retainTargets(in: outcome.remainingState)
            } catch {
                XCTFail("Independent source-bound automatic commit failed: \(error)")
            }
            if payload.requestID == neighbor.requestID { neighborDone.fulfill() } else { firstDone.fulfill() }
        }
        await fulfillment(of: [started, neighborDone], timeout: 2)
        XCTAssertEqual(delivered, [neighbor.requestID])
        XCTAssertEqual(chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["G"])
        assertSameInk(firstSource, source)
        release.signal()
        await fulfillment(of: [firstDone], timeout: 2)
        XCTAssertEqual(delivered, [neighbor.requestID, first.requestID])
        XCTAssertEqual(chart.measures.flatMap(\.chordEvents).count, 2)
        XCTAssertTrue(source.strokes.isEmpty)
        XCTAssertEqual(primary.calls, 2)
        XCTAssertEqual(fallback.calls, 1)
    }

    func testChangedSourceOptionsTargetProfileOrReviewScopeDropsBlockedFallbackBeforePublishingOrAdvancingItsChain() async throws {
        for change in 0..<5 {
            let started = expectation(description: "obsolete fallback \(change)")
            let release = DispatchSemaphore(value: 0)
            defer { release.signal() }
            let firstProvider = FallbackProviderDouble(identifier: "first") { call, _, _ in
                if call == 1 {
                    started.fulfill()
                    _ = release.wait(timeout: .now() + 10)
                    return self.unread()
                }
                return self.supported("B7")
            }
            let shouldNotRun = FallbackProviderDouble(identifier: "obsolete-chain") { _, _, _ in self.supported("C") }
            let session = makeSession(FallbackPrimaryDouble { _ in self.unread() }, fallback: [firstProvider, shouldNotRun])
            var original = request(x: 106)
            if change == 3 {
                original.evaluationContext = .init(runID: UUID(), profile: .init(profile: .init()))
            }
            session.startIncremental(requests: [original]) { _ in XCTFail("Obsolete source callback must not publish") }
            await fulfillment(of: [started], timeout: 2)
            var current = change == 0 ? request(x: 107, measureID: original.target.measureID) : original
            current.requestID = UUID()
            if change == 1 { current.options = .includingSymbolLedgerDiagnostics }
            if change == 2 { current.target.measureID = UUID() }
            if change == 3 {
                current.evaluationContext = .init(runID: original.evaluationContext!.runID,
                    profile: .init(profile: .init()))
            }
            if change == 4 { current.requiresEditReview = true }
            let done = expectation(description: "current scope \(change)")
            var publications = 0
            session.startIncremental(requests: [current]) { payload in
                publications += 1
                XCTAssertEqual(payload.requestID, current.requestID)
                XCTAssertEqual(payload.drawingData, current.drawingData)
                XCTAssertEqual(payload.strokes, current.strokes)
                XCTAssertEqual(payload.result.reviewCandidateScores.compactMap(\.displayText), ["B7"])
                done.fulfill()
            }
            release.signal()
            await fulfillment(of: [done], timeout: 2)
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(firstProvider.calls, 2)
            XCTAssertEqual(shouldNotRun.calls, 0, "An obsolete fallback must not start its next provider")
        }
    }

    func testUnchangedOwnedSourcePublishesFallbackWithLatestRequestGenerationWithoutRereading() async throws {
        let started = expectation(description: "unchanged fallback blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let fallback = FallbackProviderDouble(identifier: "unchanged") { _, _, _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 10)
            return self.supported("Bb")
        }
        let primary = FallbackPrimaryDouble { _ in self.unread() }
        let session = makeSession(primary, fallback: [fallback])
        let original = request(x: 106)
        session.startIncremental(requests: [original]) { _ in XCTFail("Superseded callback must not receive the read") }
        await fulfillment(of: [started], timeout: 2)
        var current = original
        current.requestID = UUID()
        current.scheduledAt = inputAt.addingTimeInterval(1)
        current.target.fraction = 0.151 // Same anchor bucket and exact source.
        let done = expectation(description: "latest source envelope")
        session.startIncremental(requests: [current]) { payload in
            XCTAssertEqual(payload.requestID, current.requestID)
            XCTAssertEqual(payload.targetLifecycle?.generationID, current.requestID)
            XCTAssertEqual(payload.target.fraction, current.target.fraction)
            XCTAssertEqual(payload.drawingData, current.drawingData)
            XCTAssertEqual(payload.strokes, current.strokes)
            done.fulfill()
        }
        release.signal()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(primary.calls, 1)
        XCTAssertEqual(fallback.calls, 1)
    }

    func testCancellationThenIdenticalSourceReentryCannotAcceptTheOldFallbackWorkID() async throws {
        for cancelAll in [false, true] {
            let started = expectation(description: "cancelled fallback \(cancelAll)")
            let release = DispatchSemaphore(value: 0)
            defer { release.signal() }
            let fallback = FallbackProviderDouble(identifier: "cancel-test") { call, _, _ in
                if call == 1 {
                    started.fulfill()
                    _ = release.wait(timeout: .now() + 10)
                    return self.supported("G")
                }
                return self.supported("C")
            }
            let session = makeSession(FallbackPrimaryDouble { _ in self.unread() }, fallback: [fallback])
            let original = request(x: 106)
            session.startIncremental(requests: [original]) { _ in XCTFail("Cancelled callback must not publish") }
            await fulfillment(of: [started], timeout: 2)
            if cancelAll { session.cancelPendingWork() } else { session.cancelIncrementalWork() }
            var current = original
            current.requestID = UUID()
            let done = expectation(description: "new work for identical source")
            var publications = 0
            session.startIncremental(requests: [current]) { payload in
                publications += 1
                XCTAssertEqual(payload.requestID, current.requestID)
                XCTAssertEqual(payload.result.reviewCandidateScores.compactMap(\.displayText), ["C"])
                done.fulfill()
            }
            release.signal()
            await fulfillment(of: [done], timeout: 2)
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(fallback.calls, 2)
        }
    }

    func testLocatedReviewOnlyTargetCanUseFallbackWithoutCallingTheSkippedPrimaryReader() async throws {
        let primary = FallbackPrimaryDouble { _ in XCTFail("Load-excluded target must not enter the primary reader"); return self.unread() }
        let fallback = FallbackProviderDouble(identifier: "located-source") { _, _, _ in self.supported("F-7") }
        let session = makeSession(primary, fallback: [fallback])
        var source = request(x: 106)
        source.requiresManualReviewOnly = true
        let done = expectation(description: "located fallback")
        session.startIncremental(requests: [source]) { payload in
            XCTAssertEqual(payload.drawingData, source.drawingData)
            XCTAssertEqual(payload.strokes, source.strokes)
            XCTAssertTrue(payload.requiresManualReviewOnly)
            XCTAssertEqual(payload.result.reviewCandidateScores.compactMap(\.displayText), ["F-7"])
            XCTAssertNil(payload.result.match)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(primary.calls, 0)
        XCTAssertEqual(fallback.calls, 1)
    }

    func testExhaustedBoundedChainCachesNoReadWithoutInventingAChordAndLeavesManualBatchUnchanged() async throws {
        let providers = (0..<5).map { index in
            FallbackProviderDouble(identifier: "unread-\(index)") { _, _, _ in self.unread() }
        }
        let primary = FallbackPrimaryDouble { _ in self.unread() }
        let session = makeSession(primary, fallback: providers)
        let source = request(x: 106)
        for replay in 0..<2 {
            let done = expectation(description: "exhausted fallback \(replay)")
            session.startIncremental(requests: [source]) { payload in
                XCTAssertNil(payload.result.match)
                XCTAssertTrue(payload.result.reviewCandidateScores.isEmpty)
                XCTAssertEqual(payload.result.fallbackEvidence.count, 4)
                XCTAssertTrue(payload.result.fallbackEvidence.allSatisfy { $0.candidateTexts.isEmpty })
                XCTAssertEqual(payload.drawingData, source.drawingData)
                XCTAssertEqual(payload.strokes, source.strokes)
                if replay == 1 { XCTAssertTrue(payload.timing.cacheHit) }
                done.fulfill()
            }
            await fulfillment(of: [done], timeout: 2)
            session.cancelIncrementalWork()
        }
        XCTAssertEqual(providers.map(\.calls), [1, 1, 1, 1, 0], "Attempts are bounded and exhaustion is cached")
        let manual = expectation(description: "legacy manual batch")
        session.startBatch(requests: [source]) { payloads in
            XCTAssertEqual(payloads.count, 1)
            XCTAssertTrue(payloads[0].result.fallbackEvidence.isEmpty)
            XCTAssertTrue(payloads[0].result.reviewCandidateScores.isEmpty)
            manual.fulfill()
        }
        await fulfillment(of: [manual], timeout: 2)
        XCTAssertEqual(providers.map(\.calls), [1, 1, 1, 1, 0], "Automatic fallback must not enter the manual flow/cache")
    }

    private func makeSession(_ primary: FallbackPrimaryDouble,
        fallback: [any ChordInkAutomaticFallbackRecognizing]) -> ChordInkRecognitionSession {
        ChordInkRecognitionSession(queue: DispatchQueue(label: "ichart.tests.primary.\(UUID())"),
            recognizer: primary, allowsPersonalInk: false, automaticFallbackRecognizers: fallback)
    }

    private func makeChart() -> Chart {
        var chart = Chart.draft(title: "Source-bound fallback", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func draft(_ payload: ChordInkRecognitionProposalPayload, chart: Chart) -> ChordInkDraft {
        let decision = ChordInkRecognitionPolicy.decision(for: payload.result)
        return ChordInkDraft(input: .init(measureID: payload.target.measureID,
            measureIndex: chart.measure(id: payload.target.measureID)!.index, targetFraction: payload.target.fraction,
            layoutPageSize: pageSize, drawingData: payload.drawingData,
            candidateTexts: ChordInkRenderResolutionPolicy.candidateTexts(for: payload.result), bestCandidateText: nil,
            confidence: payload.result.confidence, strokeCount: payload.strokes.count, recognitionResult: payload.result,
            primaryDecision: decision, recognitionDecision: decision, targetLifecycle: payload.targetLifecycle))
    }

    private func request(x: CGFloat, measureID: UUID = UUID(), fraction: Double = 0.15) -> ChordInkRecognitionSessionRequest {
        let points = [CGPoint(x: x, y: 80), CGPoint(x: x + 22, y: 48)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: inputAt), transform: .identity, mask: nil, randomSeed: 1)])
        return .init(requestID: UUID(), scheduledAt: inputAt, requestedDelay: 0,
            strokes: PencilKitInkAdapter.inkStrokes(from: drawing), drawingData: drawing.dataRepresentation(),
            target: (measureID, fraction), layoutPageSize: pageSize, options: .live)
    }

    private nonisolated func unread() -> ChordInkRecognitionResult {
        .init(rawCandidates: ["unreadable"], glyphCandidates: [], match: nil, confidence: 0)
    }

    private nonisolated func supported(_ text: String) -> ChordInkRecognitionResult {
        .init(rawCandidates: [text], glyphCandidates: [], match: ChordRecognitionCompendium.match(text), confidence: 0.2,
            candidateScores: [.init(text: text, displayText: ChordRecognitionCompendium.match(text)?.displayText, confidence: 0.2)])
    }

    private func assertSameInk(_ expected: PKDrawing, _ current: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: current),
            file: file, line: line)
    }
}

private final class FallbackPrimaryDouble: ChordInkRecognizing {
    private let lock = NSLock()
    private var count = 0
    private let body: ([InkStroke]) -> ChordInkRecognitionResult
    var calls: Int { lock.withLock { count } }
    init(_ body: @escaping ([InkStroke]) -> ChordInkRecognitionResult) { self.body = body }
    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        lock.withLock { count += 1 }
        return body(strokes)
    }
}

private final class FallbackProviderDouble: ChordInkAutomaticFallbackRecognizing {
    let identifier: String
    let version: String
    private let lock = NSLock()
    private var count = 0
    private let body: (Int, [InkStroke], @escaping () -> Bool) -> ChordInkRecognitionResult?
    var calls: Int { lock.withLock { count } }
    init(identifier: String, version: String = "test-v1",
        body: @escaping (Int, [InkStroke], @escaping () -> Bool) -> ChordInkRecognitionResult?) {
        self.identifier = identifier
        self.version = version
        self.body = body
    }
    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions,
        isCurrent: @escaping () -> Bool) -> ChordInkRecognitionResult? {
        let call = lock.withLock { count += 1; return count }
        return body(call, strokes, isCurrent)
    }
}
#endif

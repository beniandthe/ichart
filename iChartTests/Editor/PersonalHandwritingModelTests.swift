#if canImport(UIKit)
import PencilKit
import SwiftUI
import XCTest
@testable import iChart

@MainActor
final class PersonalHandwritingModelTests: XCTestCase {
    func testOverviewReloadsExamplesTaughtInTheSavedTestPanel() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let model = PersonalHandwritingModel(store: store, recognizer: WrongBaseline(),
            evaluationStore: PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json")))
        XCTAssertEqual(model.profile.examples.count, 0)
        try store.update { try $0.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing()), label: "A", kind: .chord, source: .explicitCorrection) }
        model.reloadProfile()
        XCTAssertEqual(model.profile.examples.count, 1)
    }

    func testExplicitExampleRemovalPersistsWithoutRewritingSavedEvaluation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: profileURL)
        try store.update {
            try $0.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing()), label: "A", kind: .glyph, source: .setup)
            try $0.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing(apexX: 12)), label: "A", kind: .glyph, source: .setup)
        }
        let frozen = store.snapshot().profile
        let selected = try XCTUnwrap(frozen.examples.first)
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
                                          pipeline: "test", profile: frozen)
        run.status = .complete
        let evaluationURL = folder.appendingPathComponent("evaluation.json")
        let journalData = try JSONEncoder().encode(PersonalInkEvaluationJournal(runs: [run]))
        try journalData.write(to: evaluationURL)
        let model = PersonalHandwritingModel(store: store, recognizer: WrongBaseline(),
            evaluationStore: PersonalInkEvaluationStore(url: evaluationURL))
        model.removeExample(id: selected.id)
        try await finish(model)
        XCTAssertEqual(model.profile.examples, Array(frozen.examples.dropFirst()))
        XCTAssertEqual(PersonalInkProfileStore(url: profileURL).snapshot().profile, model.profile)
        XCTAssertFalse(model.profile.isEnabled, "Removal must not opt a disabled profile in")
        XCTAssertEqual(model.profile.generation, frozen.generation)
        XCTAssertEqual(try Data(contentsOf: evaluationURL), journalData)
    }

    func testExampleRemovalCannotChangeProfileDuringActiveCapture() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try store.update {
            try $0.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing()), label: "A", kind: .glyph, source: .setup)
        }
        let frozen = store.snapshot().profile
        let evaluation = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
        let started = expectation(description: "capture started")
        evaluation.start(chartID: UUID(), style: "rhythmSectionSheet", phase: .beforeCorrections,
                         profile: frozen, pipeline: "test") { error in XCTAssertNil(error); started.fulfill() }
        await fulfillment(of: [started], timeout: 3)
        let model = PersonalHandwritingModel(store: store, recognizer: WrongBaseline(), evaluationStore: evaluation)
        model.removeExample(id: try XCTUnwrap(frozen.examples.first?.id))
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(store.snapshot().profile, frozen)
        XCTAssertEqual(model.profile, frozen)
    }

    func testQueuedSetupTeachingRejectsCaptureStartedBeforeWorkerEdit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: profileURL)
        try store.update {
            try $0.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing()), label: "A", kind: .glyph, source: .setup)
        }
        let frozen = store.snapshot().profile
        let savedBytes = try Data(contentsOf: profileURL)
        let evaluation = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
        let workQueue = DispatchQueue(label: "test.personal-handwriting.queued-setup")
        let model = PersonalHandwritingModel(store: store, recognizer: WrongBaseline(), evaluationStore: evaluation, workQueue: workQueue)
        var completed = false
        workQueue.suspend()
        var suspended = true
        defer { if suspended { workQueue.resume() } }
        model.learn(drawing(apexX: 12), label: "A", kind: .glyph, source: .setup) { completed = true }
        XCTAssertTrue(model.busy)
        XCTAssertFalse(evaluation.isCapturing)
        let started = expectation(description: "capture starts after setup teaching is queued")
        evaluation.start(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
            profile: frozen, pipeline: "test") { error in XCTAssertNil(error); started.fulfill() }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(evaluation.isCapturing)
        workQueue.resume(); suspended = false
        await drain(workQueue)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.error, PersonalInkEvaluationError.activeRun.localizedDescription)
        XCTAssertFalse(completed)
        XCTAssertFalse(model.learnedComparison)
        XCTAssertEqual(store.snapshot().profile, frozen)
        XCTAssertEqual(model.profile.revision, frozen.revision)
        XCTAssertEqual(model.profile.examples, frozen.examples)
        XCTAssertEqual(try Data(contentsOf: profileURL), savedBytes)
    }

    func testQueuedPracticeTeachingRejectsNewCaptureAndCanSucceedAfterStop() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: profileURL)
        try store.update {
            try $0.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing()), label: "A", kind: .glyph, source: .setup)
        }
        let evaluation = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
        let workQueue = DispatchQueue(label: "test.personal-handwriting.queued-practice")
        let model = PersonalHandwritingModel(store: store, recognizer: WrongBaseline(), evaluationStore: evaluation, workQueue: workQueue)
        model.compare(drawing(apexX: 12))
        try await finish(model)
        model.score(intendedText: "A")
        let frozen = store.snapshot().profile
        let savedBytes = try Data(contentsOf: profileURL)
        workQueue.suspend()
        var suspended = true
        defer { if suspended { workQueue.resume() } }
        model.learnComparison()
        XCTAssertTrue(model.busy)
        XCTAssertFalse(model.learnedComparison)
        let started = expectation(description: "capture starts after practice teaching is queued")
        evaluation.start(chartID: UUID(), style: "rhythmSectionSheet", phase: .beforeCorrections,
            profile: frozen, pipeline: "test") { error in XCTAssertNil(error); started.fulfill() }
        await fulfillment(of: [started], timeout: 3)
        let runID = try XCTUnwrap(evaluation.snapshot().journal.activeRun?.id)
        workQueue.resume(); suspended = false
        await drain(workQueue)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.error, PersonalInkEvaluationError.activeRun.localizedDescription)
        XCTAssertFalse(model.learnedComparison, "A rejected worker edit cannot run its success completion")
        XCTAssertEqual(model.comparison?.intendedText, "A")
        XCTAssertEqual(store.snapshot().profile, frozen)
        XCTAssertEqual(model.profile.revision, frozen.revision)
        XCTAssertEqual(model.profile.examples, frozen.examples)
        XCTAssertEqual(try Data(contentsOf: profileURL), savedBytes)
        let stopped = expectation(description: "capture stopped before retrying practice teaching")
        evaluation.stop(runID: runID) { error in XCTAssertNil(error); stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 3)
        XCTAssertFalse(evaluation.isCapturing)
        model.learnComparison()
        try await finish(model)
        XCTAssertTrue(model.learnedComparison)
        XCTAssertTrue(model.profile.isEnabled)
        XCTAssertEqual(model.profile.examples.count, frozen.examples.count + 1)
        XCTAssertNotEqual(model.profile.revision, frozen.revision)
        XCTAssertNotEqual(try Data(contentsOf: profileURL), savedBytes)
    }

    func testChartReviewLearningIsPausedDuringEvaluation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try profile.update { $0.isEnabled = true }
        let evaluation = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
        let started = expectation(description: "start capture")
        evaluation.start(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
                         profile: profile.snapshot().profile, pipeline: "test") { error in XCTAssertNil(error); started.fulfill() }
        await fulfillment(of: [started], timeout: 3)
        for source in [PersonalInkExampleSource.confirmedReview, .explicitCorrection] {
            let skipped = expectation(description: "no training during evaluation")
            PersonalInkLearning.record(text: "A", drawingData: drawing().dataRepresentation(), source: source,
                                       store: profile, evaluationStore: evaluation) { error in XCTAssertNil(error); skipped.fulfill() }
            await fulfillment(of: [skipped], timeout: 3)
        }
        for presented in ["A", "C"] {
            let skipped = expectation(description: "no review training during evaluation")
            PersonalInkLearning.recordReview(text: "A", presentedText: presented, drawingData: drawing().dataRepresentation(),
                                             store: profile, evaluationStore: evaluation) { error in
                XCTAssertNil(error); skipped.fulfill()
            }
            await fulfillment(of: [skipped], timeout: 3)
        }
        XCTAssertTrue(profile.snapshot().profile.examples.isEmpty)
    }

    func testReviewLearningUsesTheDisplayedDefaultNotTheNativeRead() async throws {
        let cases: [(native: String?, presented: String?, accepted: String, source: PersonalInkExampleSource)] = [
            ("C", "A", "A", .confirmedReview),
            ("C", "C", "A", .explicitCorrection),
            ("C", "A", "C", .explicitCorrection),
            (nil, nil, "A", .explicitCorrection)
        ]
        for item in cases {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
            let evaluation = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
            try store.update { $0.isEnabled = true }
            let result = ChordInkRecognitionResult(rawCandidates: item.native.map { [$0] } ?? [], glyphCandidates: [],
                match: item.native.flatMap { ChordRecognitionCompendium.match($0) }, confidence: 1)
            let decision = ChordInkRecognitionDecision(action: .confirm, acceptedText: item.presented,
                reason: "Test review", isCloseRace: false, competingCandidateText: nil, confidenceGap: nil)
            let confirmation = PendingChordInkConfirmation(measureID: UUID(), measureIndex: 0, result: result,
                drawingData: drawing().dataRepresentation(), targetFraction: 0,
                primaryDecision: ChordInkRecognitionPolicy.decision(for: result), decision: decision,
                candidateTexts: item.native == nil ? [] : ["C", "A"])
            XCTAssertEqual(confirmation.bestCandidateText, item.presented)
            let saved = expectation(description: "review example saved")
            PersonalInkLearning.recordReview(text: item.accepted, presentedText: confirmation.bestCandidateText,
                                             drawingData: confirmation.drawingData, store: store, evaluationStore: evaluation) { error in
                XCTAssertNil(error); saved.fulfill()
            }
            await fulfillment(of: [saved], timeout: 3)
            let snapshot = store.snapshot()
            XCTAssertEqual(snapshot.profile.examples.count, 1)
            XCTAssertEqual(snapshot.profile.examples.first?.source, item.source)
            XCTAssertEqual(snapshot.profile.examples.first?.label, item.accepted)
            let freshStrokes = PencilKitInkAdapter.inkStrokes(from: drawing(apexX: 10.5))
            let suggestion = try XCTUnwrap(snapshot.suggestion(strokes: freshStrokes))
            XCTAssertEqual(suggestion.text, item.accepted)
            XCTAssertEqual(suggestion.correctionSupportCount, item.source == .explicitCorrection ? 1 : 0)
            let uncertain = PersonalInkArbitrationPolicy.select(baselineText: "B", baselineTrusted: false, suggestion: suggestion)
            XCTAssertEqual(uncertain.text, "B")
            XCTAssertEqual(uncertain.disposition, .alternative)
            XCTAssertFalse(uncertain.prefersPersonal)
            XCTAssertEqual(PersonalInkArbitrationPolicy.select(baselineText: "B", baselineTrusted: true,
                                                              suggestion: suggestion).text, "B")
        }
    }

    func testBothKindsOfOrdinaryReviewLearningRespectOptOut() async throws {
        for enabled in [false, true] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
            let evaluation = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
            try store.update { $0.isEnabled = enabled; $0.learnsFromReviews = !enabled }
            for presented: String? in ["A", "C", nil] {
                let skipped = expectation(description: "review learning opted out")
                PersonalInkLearning.recordReview(text: "A", presentedText: presented, drawingData: drawing().dataRepresentation(),
                                                 store: store, evaluationStore: evaluation) { error in
                    XCTAssertNil(error); skipped.fulfill()
                }
                await fulfillment(of: [skipped], timeout: 3)
                XCTAssertTrue(store.snapshot().profile.examples.isEmpty)
            }
        }
    }

    func testPadReceivesTouchesThroughItsDecorativeBorderInsideScrollView() async throws {
        let root = ScrollView {
            PersonalHandwritingPad(drawing: .constant(PKDrawing()), clearID: UUID(), enabled: true)
                .padding(24)
        }
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 800))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let canvas = try XCTUnwrap(descendants(host.view).compactMap { $0 as? PKCanvasView }.first)
        XCTAssertTrue(canvas.isUserInteractionEnabled)
        XCTAssertFalse(canvas.isScrollEnabled)
        XCTAssertEqual(canvas.bounds.height, 180, accuracy: 1)
        let point = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: host.view)
        let hit = try XCTUnwrap(host.view.hitTest(point, with: nil))
        XCTAssertTrue(hit === canvas || hit.isDescendant(of: canvas), "Decorative SwiftUI views must not intercept handwriting: \(type(of: hit))")
        #if targetEnvironment(simulator)
        XCTAssertEqual(canvas.drawingPolicy, .anyInput)
        #else
        XCTAssertEqual(canvas.drawingPolicy, .pencilOnly)
        #endif
    }

    func testFreshComparisonIsLabelBlindAndScoringDoesNotTrainUntilExplicitlyTaught() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try store.update {
            try $0.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing()), label: "A", kind: .chord, source: .explicitCorrection)
        }
        let model = PersonalHandwritingModel(store: store, recognizer: WrongBaseline(),
                                             evaluationStore: PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json")))
        model.compare(drawing(apexX: 10.5))
        try await finish(model)
        let intake = try XCTUnwrap(model.comparison?.captureContext)
        XCTAssertEqual(intake.origin, .practice)
        XCTAssertNil(intake.chartStyle)
        XCTAssertEqual(model.comparison?.baseline, "C")
        XCTAssertEqual(model.comparison?.personalized, "C")
        XCTAssertEqual(model.comparison?.usedPersonalExample, false)
        XCTAssertEqual(model.comparison?.knownInk, false)
        XCTAssertFalse(model.profile.isEnabled, "Side-by-side preview must not silently enable chart personalization")
        model.score(intendedText: "A")
        XCTAssertEqual(model.scoredCount, 1)
        XCTAssertEqual(model.baselineCorrect, 0)
        XCTAssertEqual(model.personalizedCorrect, 0)
        XCTAssertEqual(store.snapshot().profile.examples.count, 1, "Scoring is not training")
        model.learnComparison()
        try await finish(model)
        XCTAssertEqual(store.snapshot().profile.examples.count, 2)
        let taught = try XCTUnwrap(store.snapshot().profile.examples.last)
        XCTAssertEqual(taught.learningProvenance?.context, intake)
        XCTAssertEqual(taught.learningProvenance?.originalInputSHA256,
                       try PersonalInkLearningProvenance.inputSHA256(strokes: XCTUnwrap(model.comparison?.strokes)))
        XCTAssertTrue(store.snapshot().profile.isEnabled)
        XCTAssertTrue(model.learnedComparison)
        model.learnComparison()
        XCTAssertEqual(store.snapshot().profile.examples.count, 2)
    }

    func testSavedInkIsExcludedFromFreshScoreAndPredictionDoesNotTeachItself() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try store.update {
            $0.isEnabled = true
            try $0.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing()), label: "A", kind: .glyph, source: .setup)
        }
        let model = PersonalHandwritingModel(store: store, recognizer: WrongBaseline(),
                                             evaluationStore: PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json")))
        model.compare(drawing())
        try await finish(model)
        XCTAssertEqual(model.comparison?.knownInk, true)
        model.score(intendedText: "A")
        XCTAssertEqual(model.scoredCount, 0)
        XCTAssertEqual(store.snapshot().profile.examples.count, 1)
    }

    func testReviewedInkLearnsOnlyWhenEnabledAndLearningOptInRemainsOn() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let data = drawing().dataRepresentation()
        let evaluation = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
        let disabled = expectation(description: "disabled")
        PersonalInkLearning.record(text: "A", drawingData: data, source: .confirmedReview, store: store, evaluationStore: evaluation) { error in
            XCTAssertNil(error); disabled.fulfill()
        }
        await fulfillment(of: [disabled], timeout: 2)
        XCTAssertTrue(store.snapshot().profile.examples.isEmpty)
        try store.update { $0.isEnabled = true; $0.learnsFromReviews = false }
        let notLearning = expectation(description: "learning disabled")
        PersonalInkLearning.record(text: "A", drawingData: data, source: .confirmedReview, store: store, evaluationStore: evaluation) { error in
            XCTAssertNil(error); notLearning.fulfill()
        }
        await fulfillment(of: [notLearning], timeout: 2)
        XCTAssertTrue(store.snapshot().profile.examples.isEmpty)
        let corrected = expectation(description: "explicit correction")
        PersonalInkLearning.record(text: "A", drawingData: data, source: .explicitCorrection, store: store, evaluationStore: evaluation) { error in
            XCTAssertNil(error); corrected.fulfill()
        }
        await fulfillment(of: [corrected], timeout: 3)
        XCTAssertEqual(store.snapshot().profile.examples.count, 1)
        XCTAssertEqual(store.snapshot().profile.examples.first?.source, .explicitCorrection)
    }

    func testSetupLessonsShareIntakeSessionButNotCaptureIdentity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let model = PersonalHandwritingModel(store: store, recognizer: WrongBaseline(),
            evaluationStore: PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json")))
        model.learn(drawing(), label: "A", kind: .glyph, source: .setup) {}
        try await finish(model)
        model.learn(drawing(apexX: 12), label: "A", kind: .glyph, source: .setup) {}
        try await finish(model)
        let lessons = store.snapshot().profile.examples
        XCTAssertEqual(lessons.count, 2)
        let first = try XCTUnwrap(lessons.first?.learningProvenance)
        let second = try XCTUnwrap(lessons.last?.learningProvenance)
        XCTAssertEqual(first.context.origin, .setup)
        XCTAssertEqual(second.context.origin, .setup)
        XCTAssertEqual(first.context.sessionID, second.context.sessionID)
        XCTAssertNotEqual(first.context.captureID, second.context.captureID)
        XCTAssertNil(first.context.chartStyle)
        try first.validate(storedInput: lessons[0].recognitionInput)
        try second.validate(storedInput: lessons[1].recognitionInput)
    }

    func testReviewIntakeIsPersistedOnlyAfterOptedInExplicitReview() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: profileURL)
        let evaluation = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
        try store.update { $0.isEnabled = true }
        let context = PersonalInkCaptureContext(sessionID: UUID(), origin: .chartReview,
            chartStyle: "rhythm-section-sheet")
        let data = drawing().dataRepresentation()
        let saved = expectation(description: "review saved with intake")
        PersonalInkLearning.recordReview(text: "A", presentedText: "C", drawingData: data,
            captureContext: context, store: store, evaluationStore: evaluation) { error in
                XCTAssertNil(error); saved.fulfill()
            }
        await fulfillment(of: [saved], timeout: 3)
        let lesson = try XCTUnwrap(PersonalInkProfileStore(url: profileURL).snapshot().profile.examples.first)
        XCTAssertEqual(lesson.learningProvenance?.context, context)
        XCTAssertEqual(lesson.source, .explicitCorrection)
        XCTAssertEqual(lesson.learningProvenance?.originalInputSHA256,
            try PersonalInkLearningProvenance.inputSHA256(strokes: PencilKitInkAdapter.inkStrokes(from: data)))
        try store.update { $0.learnsFromReviews = false }
        let skipped = expectation(description: "opt-out still wins")
        PersonalInkLearning.recordReview(text: "D", presentedText: "C", drawingData: data,
            captureContext: context, store: store, evaluationStore: evaluation) { error in
                XCTAssertNil(error); skipped.fulfill()
            }
        await fulfillment(of: [skipped], timeout: 3)
        XCTAssertEqual(store.snapshot().profile.examples, [lesson])
    }

    private func finish(_ model: PersonalHandwritingModel) async throws {
        for _ in 0..<300 where model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
    }

    private func drain(_ queue: DispatchQueue) async {
        let finished = expectation(description: "queued model result reached the main actor")
        queue.async { DispatchQueue.main.async { finished.fulfill() } }
        await fulfillment(of: [finished], timeout: 3)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private func drawing(apexX: CGFloat = 9) -> PKDrawing {
        let paths: [[CGPoint]] = [[CGPoint(x: 0, y: 28), CGPoint(x: apexX, y: 0), CGPoint(x: 18, y: 28)],
                                 [CGPoint(x: 4, y: 18), CGPoint(x: 14, y: 18)]]
        return PKDrawing(strokes: paths.map { points in
            PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 2, height: 2), opacity: 1,
                              force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSince1970: 0)))
        })
    }
}

private struct WrongBaseline: ChordInkRecognizing {
    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        XCTAssertFalse(Thread.isMainThread, "Comparison must stay off the live ink thread")
        return ChordInkRecognitionResult(rawCandidates: ["C"], glyphCandidates: [], match: ChordRecognitionCompendium.match("C"), confidence: 1)
    }
}
#endif

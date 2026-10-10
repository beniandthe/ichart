#if canImport(PencilKit) && canImport(UIKit)
import PencilKit
import UIKit
import XCTest
@testable import RecognitionStudy

final class RecognitionStudyCapturePresentationTests: XCTestCase {
    func testEngineeringDryRunPromptsExerciseEveryPresentedInstruction() {
        let prompts = RecognitionStudyCapturePrompt.engineeringDryRun

        XCTAssertEqual(Set(prompts.map(\.pace)), Set([
            .natural,
            .fast,
            .careful
        ]))
        XCTAssertEqual(Set(prompts.map(\.size)), Set([
            .small,
            .normal,
            .large
        ]))
        XCTAssertEqual(Set(prompts.map(\.construction)), Set([
            .rootFirst,
            .modifierFirst,
            .mixedOrRetraced
        ]))
        XCTAssertEqual(Set(prompts.map(\.chartStyle)), Set([
            .simpleChordSheet,
            .rhythmSectionSheet
        ]))
        XCTAssertEqual(Set(prompts.map(\.id)).count, prompts.count)
        XCTAssertFalse(prompts.contains { $0.chordText.isEmpty })
        XCTAssertFalse(prompts.contains { $0.displayChordText.isEmpty })
        XCTAssertFalse(prompts.contains { $0.instructionText.isEmpty })
        for prompt in prompts {
            XCTAssertEqual(
                try ChordNotation.parseCanonical(prompt.chordText).canonicalDisplay,
                prompt.chordText,
                "Prompt \(prompt.id) must persist strict canonical notation."
            )
        }
        XCTAssertEqual(
            prompts.first { $0.id == "bb-natural-small-root" }?.displayChordText,
            "B♭"
        )
        XCTAssertEqual(
            prompts.first { $0.id == "db-major-nine-careful-large-modifier" }?.displayChordText,
            "D♭△9"
        )
    }

    @MainActor
    func testEveryEngineeringPromptPersistsAnOutcomeAndCompletesThePass() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecognitionStudyCapturePresentationTests-\(UUID())",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "RecognitionStudyCapturePresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reference = RecognitionStudySessionReferenceStore(
            defaults: defaults,
            key: "complete-pass-test"
        )
        let prompts = RecognitionStudyCapturePrompt.engineeringDryRun
        let model = RecognitionStudyCaptureViewModel(
            prompts: prompts,
            sessionReferenceStore: reference,
            rootDirectoryProvider: { root }
        )
        await model.start()

        for (index, prompt) in prompts.enumerated() {
            XCTAssertEqual(model.promptIndex, index)
            XCTAssertEqual(model.currentPrompt, prompt)
            let didSubmit = await model.submit(
                drawing: Self.onePointDrawing(),
                canvasSize: CGSize(width: 400, height: 200),
                clientObservedOrientation: .portrait
            )
            XCTAssertTrue(didSubmit, "Capture failed for \(prompt.id).")
            let didRecord = await model.recordOutcomeAndAdvance(.asPrompted)
            XCTAssertTrue(
                didRecord,
                "Outcome failed for \(prompt.id)."
            )
        }

        XCTAssertEqual(model.phase, .completed)
        let sessionID = try XCTUnwrap(reference.load())
        let outcomeStore = try await RecognitionStudyLocalOutcomeStore.open(
            rootDirectory: root
        )
        let outcomes = try await outcomeStore.outcomes(
            localSessionID: sessionID
        )
        XCTAssertEqual(outcomes.count, prompts.count)
        XCTAssertEqual(
            outcomes.map(\.promptOutcome.intendedChord.rawValue),
            prompts.map(\.chordText)
        )
        XCTAssertTrue(
            outcomes.allSatisfy { outcome in
                guard let latency = outcome.baseRecognizerOutcome
                    .latencyMicroseconds else {
                    return false
                }
                return latency <= RecognitionStudyBaseRecognizerOutcome
                    .maximumLatencyMicroseconds
            }
        )
        XCTAssertEqual(
            model.completedSummary,
            RecognitionStudyPassSummary(
                outcomes: outcomes
            )
        )
        XCTAssertEqual(model.completedSummary?.totalCount, prompts.count)
        XCTAssertEqual(
            model.completedSummary?.eligibleComparisonCount,
            prompts.count
        )
        XCTAssertEqual(model.completedSummary?.exactCanonicalCandidateCount, 0)
        XCTAssertEqual(model.completedSummary?.differentOrInvalidCandidateCount, 0)
        XCTAssertEqual(model.completedSummary?.noCandidateCount, prompts.count)
        XCTAssertEqual(model.completedSummary?.writerMatchedPromptCount, prompts.count)
        XCTAssertEqual(model.completedSummary?.technicalFailureCount, 0)
    }

    @MainActor
    func testSummaryExcludesWriterErrorsAndAmbiguousInkFromComparison() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecognitionStudyCapturePresentationTests-\(UUID())",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "RecognitionStudyCapturePresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reference = RecognitionStudySessionReferenceStore(
            defaults: defaults,
            key: "excluded-comparison-test"
        )
        let model = RecognitionStudyCaptureViewModel(
            prompts: Array(
                RecognitionStudyCapturePrompt.engineeringDryRun.prefix(3)
            ),
            sessionReferenceStore: reference,
            rootDirectoryProvider: { root }
        )
        await model.start()

        for state in [
            RecognitionStudyWriterConfirmationState.asPrompted,
            .executionError,
            .humanAmbiguous
        ] {
            let didSubmit = await model.submit(
                drawing: Self.onePointDrawing(),
                canvasSize: CGSize(width: 400, height: 200),
                clientObservedOrientation: .portrait
            )
            XCTAssertTrue(didSubmit)
            let didRecord = await model.recordOutcomeAndAdvance(state)
            XCTAssertTrue(didRecord)
        }

        let summary = try XCTUnwrap(model.completedSummary)
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.eligibleComparisonCount, 1)
        XCTAssertEqual(summary.noCandidateCount, 1)
        XCTAssertEqual(summary.exactCanonicalCandidateCount, 0)
        XCTAssertEqual(summary.differentOrInvalidCandidateCount, 0)
        XCTAssertEqual(summary.writerMatchedPromptCount, 1)
        XCTAssertEqual(summary.executionErrorCount, 1)
        XCTAssertEqual(summary.humanAmbiguousCount, 1)
        XCTAssertEqual(summary.technicalFailureCount, 0)
    }

    func testLocalResultPresentationKeepsThreeTrustOutcomesDistinct() {
        let accepted = RecognitionStudyLocalResult.accepted(
            displayText: "C7",
            detail: "High-confidence local candidate."
        )
        let review = RecognitionStudyLocalResult.review(
            candidate: "C?",
            detail: "Ambiguous local candidate."
        )
        let noRead = RecognitionStudyLocalResult.noRead(
            detail: "No candidate passed the local gate."
        )

        XCTAssertEqual(accepted.title, "Accepted")
        XCTAssertEqual(accepted.displayText, "C7")
        XCTAssertEqual(review.title, "Needs review")
        XCTAssertEqual(review.displayText, "C?")
        XCTAssertEqual(noRead.title, "No read")
        XCTAssertNil(noRead.displayText)
    }

    @MainActor
    func testObservedOrientationUsesViewportRatherThanWideChordCanvas() {
        XCTAssertEqual(
            RecognitionStudyCaptureViewModel.observedOrientation(
                viewportSize: CGSize(width: 820, height: 1_180)
            ),
            .portrait
        )
        XCTAssertEqual(
            RecognitionStudyCaptureViewModel.observedOrientation(
                viewportSize: CGSize(width: 1_180, height: 820)
            ),
            .landscape
        )
    }

    func testSessionReferenceRequiresCanonicalUUIDText() throws {
        let suiteName = "RecognitionStudyCapturePresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reference = RecognitionStudySessionReferenceStore(
            defaults: defaults,
            key: "test-session"
        )
        let sessionID = UUID()

        reference.save(sessionID)
        XCTAssertEqual(reference.load(), sessionID)

        defaults.set(sessionID.uuidString.uppercased(), forKey: "test-session")
        XCTAssertNil(reference.load())
    }

    @MainActor
    func testRepeatedStartupResumesOneEmptyEngineeringSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecognitionStudyCapturePresentationTests-\(UUID())",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "RecognitionStudyCapturePresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reference = RecognitionStudySessionReferenceStore(
            defaults: defaults,
            key: "resume-test"
        )

        let first = RecognitionStudyCaptureViewModel(
            sessionReferenceStore: reference,
            rootDirectoryProvider: { root }
        )
        await first.start()
        XCTAssertEqual(first.phase, .ready)

        let second = RecognitionStudyCaptureViewModel(
            sessionReferenceStore: reference,
            rootDirectoryProvider: { root }
        )
        await second.start()
        XCTAssertEqual(second.phase, .ready)

        let sessions = root
            .appendingPathComponent(
                RecognitionStudyLocalCaptureStore.storeDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent("sessions", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(
            at: sessions,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(entries.count, 1)
    }

    @MainActor
    func testCompletedPassCanRotateToANewPersistentSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecognitionStudyCapturePresentationTests-\(UUID())",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "RecognitionStudyCapturePresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reference = RecognitionStudySessionReferenceStore(
            defaults: defaults,
            key: "new-pass-test"
        )
        let model = RecognitionStudyCaptureViewModel(
            prompts: [RecognitionStudyCapturePrompt.engineeringDryRun[0]],
            sessionReferenceStore: reference,
            rootDirectoryProvider: { root }
        )
        await model.start()
        let firstSession = try XCTUnwrap(reference.load())

        let drawing = PKDrawing(strokes: [
            PKStroke(
                ink: PKInk(.pen, color: .black),
                path: PKStrokePath(
                    controlPoints: [
                        PKStrokePoint(
                            location: CGPoint(x: 10, y: 10),
                            timeOffset: 0,
                            size: CGSize(width: 2, height: 2),
                            opacity: 1,
                            force: 1,
                            azimuth: 0,
                            altitude: .pi / 2
                        )
                    ],
                    creationDate: Date()
                )
            )
        ])
        let didSubmit = await model.submit(
            drawing: drawing,
            canvasSize: CGSize(width: 400, height: 200),
            clientObservedOrientation: .portrait
        )
        XCTAssertTrue(didSubmit)
        let didRecordOutcome = await model.recordOutcomeAndAdvance(
            .asPrompted
        )
        XCTAssertTrue(didRecordOutcome)
        XCTAssertEqual(model.phase, .completed)

        let didBeginNewPass = await model.beginNewPass()
        XCTAssertTrue(didBeginNewPass)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.promptIndex, 0)
        let secondSession = try XCTUnwrap(reference.load())
        XCTAssertNotEqual(firstSession, secondSession)

        let sessions = root
            .appendingPathComponent(
                RecognitionStudyLocalCaptureStore.storeDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent("sessions", isDirectory: true)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: sessions,
                includingPropertiesForKeys: nil
            ).count,
            2
        )

        let outcomeStore = try await RecognitionStudyLocalOutcomeStore.open(
            rootDirectory: root
        )
        let firstOutcomes = try await outcomeStore.outcomes(
            localSessionID: firstSession
        )
        XCTAssertEqual(firstOutcomes.count, 1)
        XCTAssertEqual(
            firstOutcomes[0].promptOutcome.writerConfirmationState,
            .asPrompted
        )
        XCTAssertEqual(
            firstOutcomes[0].dataUse,
            .localEngineeringOnlyNotCorpusEligibleV1
        )
    }

    @MainActor
    func testStartupResumesLastCaptureUntilWriterOutcomeIsRecorded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecognitionStudyCapturePresentationTests-\(UUID())",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "RecognitionStudyCapturePresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reference = RecognitionStudySessionReferenceStore(
            defaults: defaults,
            key: "pending-outcome-test"
        )
        let prompts = [RecognitionStudyCapturePrompt.engineeringDryRun[0]]
        let resultCallCounter = RecognitionStudyResultCallCounter()
        let resultProvider = RecognitionStudyCountingResultProvider(
            counter: resultCallCounter
        )
        let first = RecognitionStudyCaptureViewModel(
            prompts: prompts,
            resultProvider: resultProvider,
            sessionReferenceStore: reference,
            rootDirectoryProvider: { root }
        )
        await first.start()
        let didSubmit = await first.submit(
            drawing: Self.onePointDrawing(),
            canvasSize: CGSize(width: 400, height: 200),
            clientObservedOrientation: .portrait
        )
        XCTAssertTrue(didSubmit)
        XCTAssertEqual(first.phase, .reviewing)
        let callsAfterSubmit = await resultCallCounter.currentValue()
        XCTAssertEqual(callsAfterSubmit, 1)

        let resumed = RecognitionStudyCaptureViewModel(
            prompts: prompts,
            resultProvider: resultProvider,
            sessionReferenceStore: reference,
            rootDirectoryProvider: { root }
        )
        await resumed.start()

        XCTAssertEqual(resumed.phase, .reviewing)
        XCTAssertEqual(resumed.promptIndex, 0)
        XCTAssertNotNil(resumed.result)
        let callsAfterResume = await resultCallCounter.currentValue()
        XCTAssertEqual(callsAfterResume, 1)
        XCTAssertTrue(resumed.requiresTechnicalFailureExclusion)
        XCTAssertEqual(resumed.reviewPreview?.strokes.count, 1)
        XCTAssertEqual(
            resumed.reviewPreview?.sourceCanvasSize,
            CGSize(width: 400, height: 200)
        )
        let incorrectlyAccepted = await resumed.recordOutcomeAndAdvance(
            .asPrompted
        )
        XCTAssertFalse(incorrectlyAccepted)
        XCTAssertEqual(resumed.phase, .reviewing)
        let didRecordOutcome = await resumed.recordOutcomeAndAdvance(
            .technicalFailure
        )
        XCTAssertTrue(didRecordOutcome)
        XCTAssertEqual(resumed.phase, .completed)

        let sessionID = try XCTUnwrap(reference.load())
        let outcomeStore = try await RecognitionStudyLocalOutcomeStore.open(
            rootDirectory: root
        )
        let outcomes = try await outcomeStore.outcomes(
            localSessionID: sessionID
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(
            outcomes[0].promptOutcome.writerConfirmationState,
            .technicalFailure
        )
        XCTAssertEqual(outcomes[0].baseRecognizerOutcome.disposition, .notRun)
        XCTAssertNil(outcomes[0].baseRecognizerOutcome.latencyMicroseconds)
        XCTAssertEqual(resumed.completedSummary?.eligibleComparisonCount, 0)
        XCTAssertEqual(resumed.completedSummary?.technicalFailureCount, 1)
        XCTAssertEqual(resumed.completedSummary?.noCandidateCount, 0)
    }

    @MainActor
    func testProviderFailureCannotBeRecordedAsARecognitionNoRead() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecognitionStudyProviderFailureTests-\(UUID())",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "RecognitionStudyProviderFailureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reference = RecognitionStudySessionReferenceStore(
            defaults: defaults,
            key: "provider-failure-test"
        )
        let model = RecognitionStudyCaptureViewModel(
            prompts: [RecognitionStudyCapturePrompt.engineeringDryRun[0]],
            resultProvider: RecognitionStudyUnavailableResultProvider(),
            sessionReferenceStore: reference,
            rootDirectoryProvider: { root }
        )
        await model.start()
        let didSubmit = await model.submit(
            drawing: Self.onePointDrawing(),
            canvasSize: CGSize(width: 400, height: 200),
            clientObservedOrientation: .portrait
        )
        XCTAssertTrue(didSubmit)
        XCTAssertEqual(model.phase, .reviewing)
        XCTAssertTrue(model.requiresTechnicalFailureExclusion)
        XCTAssertEqual(model.result?.title, "Recognition unavailable")
        for state in [
            RecognitionStudyWriterConfirmationState.asPrompted,
            .executionError,
            .humanAmbiguous
        ] {
            let incorrectlyRecorded = await model.recordOutcomeAndAdvance(state)
            XCTAssertFalse(incorrectlyRecorded)
        }
        let didExclude = await model.recordOutcomeAndAdvance(.technicalFailure)
        XCTAssertTrue(didExclude)
        XCTAssertEqual(model.phase, .completed)
        let outcomeStore = try await RecognitionStudyLocalOutcomeStore.open(
            rootDirectory: root
        )
        let outcomes = try await outcomeStore.outcomes(
            localSessionID: XCTUnwrap(reference.load())
        )
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].baseRecognizerOutcome.disposition, .notRun)
        XCTAssertNil(outcomes[0].baseRecognizerOutcome.candidate)
        XCTAssertNil(outcomes[0].baseRecognizerOutcome.latencyMicroseconds)
        XCTAssertEqual(outcomes[0].promptOutcome.writerConfirmationState, .technicalFailure)
        XCTAssertEqual(model.completedSummary?.technicalFailureCount, 1)
        XCTAssertEqual(model.completedSummary?.eligibleComparisonCount, 0)
        XCTAssertEqual(model.completedSummary?.noCandidateCount, 0)
    }

    private static func onePointDrawing() -> PKDrawing {
        PKDrawing(strokes: [
            PKStroke(
                ink: PKInk(.pen, color: .black),
                path: PKStrokePath(
                    controlPoints: [
                        PKStrokePoint(
                            location: CGPoint(x: 10, y: 10),
                            timeOffset: 0,
                            size: CGSize(width: 2, height: 2),
                            opacity: 1,
                            force: 1,
                            azimuth: 0,
                            altitude: .pi / 2
                        )
                    ],
                    creationDate: Date()
                )
            )
        ])
    }
}

private actor RecognitionStudyResultCallCounter {
    private var value = 0

    func recordCall() {
        value += 1
    }

    func currentValue() -> Int {
        value
    }
}

private struct RecognitionStudyCountingResultProvider:
    RecognitionStudyLocalResultProviding
{
    let counter: RecognitionStudyResultCallCounter

    func result(
        for packet: ChordInkCanonicalTrajectoryPacket
    ) async -> RecognitionStudyLocalResult {
        await counter.recordCall()
        return .review(
            candidate: nil,
            detail: "Counting test provider."
        )
    }
}
#endif

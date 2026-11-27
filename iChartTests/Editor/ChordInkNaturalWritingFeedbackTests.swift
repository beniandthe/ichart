#if canImport(UIKit) && canImport(PencilKit)
import XCTest
@testable import iChart

@MainActor
final class ChordInkNaturalWritingFeedbackTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 100)

    func testGlobalPlacementReasonRemainsVisibleAlongsideChordDrafts() throws {
        let terminalReasons: [ChordInkAutomaticRenderReason] = [
            .needsSpace, .needsSourceRefresh, .placementUnavailable, .barlinePlacementUnavailable,
            .endingReview, .adjacentWriting, .unrepresentedInk
        ]
        for reason in terminalReasons {
            XCTAssertTrue(ChordInkAutomaticFeedbackPresentationPolicy.prefersGlobalStatus(for: reason),
                "A recognized chord must not hide the source's actual placement refusal")
            for phase in [ChordInkAutomaticActivity.Phase.settled, .reading, .restored] {
                let status = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
                    activity: activity(phase: phase, pending: phase == .reading ? 1 : 0, age: 4),
                    feedback: .init(globalReason: reason), hasSourceInk: true, now: now))
                XCTAssertFalse(status.isReading, "A known terminal reason must not promise progress: \(reason)")
                XCTAssertTrue(status.canReview)
                XCTAssertEqual(status.detail, reason.userMessage)
            }
        }
    }

    func testKnownRefusalIsVisibleBeforeTheSharedStructuralIdleDeadline() throws {
        for reason in [ChordInkAutomaticRenderReason.needsSpace, .needsSourceRefresh,
                       .placementUnavailable, .barlinePlacementUnavailable, .endingReview,
                       .adjacentWriting, .unrepresentedInk] {
            for phase in [ChordInkAutomaticActivity.Phase.settled, .reading] {
                let status = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
                    activity: activity(phase: phase, pending: phase == .reading ? 1 : 0, age: 0.5),
                    feedback: .init(globalReason: reason), hasSourceInk: true, now: now,
                    requiredIdleDelay: 2))
                XCTAssertFalse(status.isReading,
                    "A known refusal must remain visible when later writing restarts the shared clock")
                XCTAssertTrue(status.canReview)
                XCTAssertEqual(status.detail, reason.userMessage)
            }
        }
    }

    func testChordSpecificReasonsKeepTheirIndividualFeedback() {
        for reason in [ChordInkAutomaticRenderReason.waiting, .reading, .recognitionReview,
                       .noRead, .triangleQualityReview] {
            XCTAssertFalse(ChordInkAutomaticFeedbackPresentationPolicy.prefersGlobalStatus(for: reason))
        }
        XCTAssertFalse(ChordInkAutomaticFeedbackPresentationPolicy.prefersGlobalStatus(for: nil))
    }

    func testRetainedSavedInkIsNotAnIndefiniteReadWithoutActiveWork() throws {
        XCTAssertTrue(ChordInkAutomaticFeedbackPresentationPolicy.prefersGlobalStatus(for: .restoredInk))
        for phase in [ChordInkAutomaticActivity.Phase.restored, .settled] {
            let status = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
                activity: activity(phase: phase, pending: 0, age: nil),
                feedback: .init(globalReason: .restoredInk), hasSourceInk: true, now: now))
            XCTAssertFalse(status.isReading)
            XCTAssertTrue(status.canReview, "The existing optional Fix Writing action remains available")
            XCTAssertEqual(status.title, "Saved handwriting")
            XCTAssertFalse(status.detail.isEmpty)
        }
        let withoutActivity = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
            activity: nil, feedback: .init(globalReason: .restoredInk), hasSourceInk: true, now: now))
        XCTAssertFalse(withoutActivity.isReading, "No active read exists merely because its source was restored")
    }

    func testActiveSavedInkReadRemainsNonblockingEvenWhenOverdue() throws {
        for age in [0.3, 4, 60] {
            let active = activity(phase: .reading, pending: 1, age: age)
            let status = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
                activity: active, feedback: .init(globalReason: .restoredInk),
                hasSourceInk: true, now: now))
            XCTAssertTrue(status.isReading)
            XCTAssertFalse(status.canReview, "Time alone must not redirect active reading into a review flow")
        }
    }

    func testCompletedNoReadDoesNotClaimBackgroundWorkIsStillRunning() throws {
        let status = try XCTUnwrap(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
            activity: activity(phase: .settled, pending: 0, age: 4),
            feedback: .init(globalReason: .unrepresentedInk), hasSourceInk: true, now: now))
        XCTAssertFalse(status.isReading)
        XCTAssertTrue(status.canReview)
        XCTAssertEqual(status.detail, ChordInkAutomaticRenderReason.unrepresentedInk.userMessage)
    }

    func testManualModeAndEmptySourceDoNotShowAutomaticProgressOrRecovery() {
        for reason in [ChordInkAutomaticRenderReason.restoredInk, .placementUnavailable] {
            let feedback = ChordInkAutomaticRenderFeedback(globalReason: reason)
            XCTAssertNil(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
                activity: activity(phase: .settled, pending: 0, age: 4), feedback: feedback,
                hasSourceInk: true, now: now, manualRenderWithPreview: true))
            XCTAssertNil(ChordInkAutomaticFeedbackPresentationPolicy.globalStatus(
                activity: activity(phase: .empty, pending: 0, age: 4), feedback: feedback,
                hasSourceInk: false, now: now))
        }
    }

    func testPaperGuidanceKeepsCurrentMixedWritingAndManualControlsDistinctInBothStyles() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let automatic = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: false, usesPaperMeasureLayout: true)
            let manual = EditorCanvasMode.chordEntry.toolGuidance(
                layoutStyle: style, manualRenderWithPreview: true, usesPaperMeasureLayout: true)
            XCTAssertEqual(automatic.steps.count, 2, "No additional instruction row should move the writing canvas")
            XCTAssertEqual(manual.steps.count, 2)
            XCTAssertTrue(automatic.referenceText.contains("Write chords and barlines in the same pass"))
            XCTAssertTrue(automatic.referenceText.contains("unfinished writing stays on the page"))
            XCTAssertFalse(automatic.referenceText.contains("barlines on their own"))
            XCTAssertTrue(manual.steps[1].contains("Render Chords or Review & Render"))
            XCTAssertFalse(manual.referenceText.contains("Completed marks render while"))
            XCTAssertTrue(manual.referenceText.contains("Check the previews before rendering"))
        }
    }

    private func activity(phase: ChordInkAutomaticActivity.Phase, pending: Int,
        age: TimeInterval?) -> ChordInkAutomaticActivity {
        .init(chartID: UUID(), sourceRevision: 1, hasSourceInk: true, phase: phase,
            pendingTargetCount: pending, inputAt: age.map { now.addingTimeInterval(-$0) })
    }
}
#endif

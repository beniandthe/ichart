#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkReviewSnapshotDiagnosticTests: XCTestCase {
    func testRealSheetDismissAndReopenSubmitsOnlyTheCurrentBatchIDs() async throws {
        try await exerciseReplacement(dismissBeforeReplacement: true)
    }

    func testRealSheetNonNilReplacementSubmitsOnlyTheCurrentBatchIDs() async throws {
        try await exerciseReplacement(dismissBeforeReplacement: false)
    }

    func testEveryPreviewUpdateModeAndReviewCombinationUsesTheSameSuspensionRule() {
        let modes: [EditorCanvasMode] = [.browse, .measureEdit, .repeatEdit, .timeSignatureEdit,
            .rhythmicNotationEdit, .headerEntry, .chordEntry, .noteEdit, .freeHand, .textEdit]
        for mode in modes {
            for flags in 0..<8 {
                let single = flags & 1 != 0
                let batch = flags & 2 != 0
                let correction = flags & 4 != 0
                XCTAssertEqual(EditorChordDraftPreviewUpdatePolicy.allowsUpdate(mode: mode,
                    hasSingleReview: single, hasBatchReview: batch, hasCorrection: correction),
                    mode == .chordEntry && flags == 0,
                    "Chord/barline previews must suspend during any review or outside Write & Render: \(mode), \(flags)")
            }
        }
    }

    func testChordAndBarlineCallbacksBothCheckTheSharedReviewSuspensionPolicy() throws {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let editor = try String(contentsOf: projectRoot.appendingPathComponent("iChart/Features/Editor/EditorView.swift"))
        for (signature, mutation) in [
            ("private func handleChordInkDraftPreviewChanged(", "let previousDraftByAnchor"),
            ("private func handleChordInkDraftBarlinesChanged(", "let previousCount")
        ] {
            let start = try XCTUnwrap(editor.range(of: signature))
            let end = try XCTUnwrap(editor.range(of: mutation, range: start.upperBound..<editor.endIndex))
            let guardSource = String(editor[start.lowerBound..<end.lowerBound])
            XCTAssertTrue(guardSource.contains("guard EditorChordDraftPreviewUpdatePolicy.allowsUpdate("))
            XCTAssertTrue(guardSource.contains("mode: canvasMode"))
            XCTAssertTrue(guardSource.contains("hasSingleReview: pendingChordInkConfirmation != nil"))
            XCTAssertTrue(guardSource.contains("hasBatchReview: pendingChordInkBatchConfirmation != nil"))
            XCTAssertTrue(guardSource.contains("hasCorrection: pendingChordCorrection != nil"))
        }
        let sheetStart = try XCTUnwrap(editor.range(of: ".sheet(item: $pendingChordInkBatchConfirmation)"))
        let sheetEnd = try XCTUnwrap(editor.range(of: ".sheet(item: $pendingChordCorrection)",
                                                 range: sheetStart.upperBound..<editor.endIndex))
        XCTAssertTrue(editor[sheetStart.lowerBound..<sheetEnd.lowerBound].contains(".id(batch.id)"),
                      "Production must use the same batch identity boundary as the mounted regression harness")
    }

    private func exerciseReplacement(dismissBeforeReplacement: Bool) async throws {
        let first = batch(texts: ["C", "D7"])
        let second = batch(texts: ["F", "G7"])
        let frozenFirstInk = first.confirmations.map(\.drawingData)
        let frozenSecondInk = second.confirmations.map(\.drawingData)
        let state = ReviewPresentationState()
        let host = UIHostingController(rootView: ReviewPresentationHarness(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            state.batch = nil
            window.isHidden = true
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        state.batch = first
        let originalFields = try await waitForMountedReview(in: host, window: window,
                                                           expectedTexts: ["C", "D7"]).fields
        XCTAssertEqual(originalFields.count, 2)
        let edited = try XCTUnwrap(originalFields.first { $0.text == "C" })
        edited.text = "Eb7"
        edited.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        state.refreshCount += 1
        state.batch = first
        try await waitUntil { state.processedRefreshCount == state.refreshCount }
        let refreshed = try await waitForMountedReview(in: host, window: window,
                                                      expectedTexts: ["Eb7", "D7"])
        XCTAssertEqual(refreshed.fields.first { $0.text == "Eb7" }?.text, "Eb7",
                       "Refreshing the same batch must preserve its user's correction")
        if dismissBeforeReplacement {
            state.batch = nil
            try await waitUntil { host.presentedViewController == nil }
        } else {
            XCTAssertNil(mountedReview(in: host, window: window, expectedTexts: ["F", "G7"]),
                         "An already-presented sheet is not evidence that the replacement rows are mounted")
        }
        state.batch = second
        let replacement = try await waitForMountedReview(in: host, window: window,
                                                        expectedTexts: ["F", "G7"])
        let fields = replacement.fields
        XCTAssertEqual(fields.count, 2)
        // Change both seed values so a callback containing untouched defaults cannot pass.
        for (seed, correction) in [("F", "F7"), ("G7", "G9")] {
            let field = try XCTUnwrap(fields.first { $0.text == seed })
            field.text = correction
            field.sendActions(for: .editingChanged)
        }
        let corrected = try await waitForMountedReview(in: host, window: window,
                                                      expectedTexts: ["F7", "G9"])
        let render = try XCTUnwrap(descendants(corrected.view).compactMap { $0 as? PencilOnlyUIButton }
            .first { $0.accessibilityLabel == "Render All" })
        XCTAssertTrue(render.isEnabled, "All currently visible fields contain supported chords")
        XCTAssertTrue(state.accepted.isEmpty, "Editing cannot implicitly accept a review")
        render.sendActions(for: .touchUpInside)
        let accepted = try XCTUnwrap(state.accepted.last)
        let expectedIDs = Set(second.confirmations.map(\.id))
        let submittedIDs = Set(accepted.entries.keys)
        let report = "Path: \(dismissBeforeReplacement ? "nil then new batch" : "non-nil replacement"); "
            + "visible rows: \(fields.count); render enabled: \(render.isEnabled); "
            + "current IDs: \(expectedIDs.count); submitted IDs: \(submittedIDs.count); "
            + "stale IDs: \(submittedIDs.subtracting(expectedIDs).count); "
            + "callback belongs to current batch: \(accepted.batchID == second.id)"
        let attachment = XCTAttachment(string: report)
        attachment.name = "Mounted sheet review identity diagnostic"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(accepted.batchID, second.id, report)
        XCTAssertEqual(submittedIDs, expectedIDs, report)
        XCTAssertEqual(accepted.entries[second.confirmations[0].id], "F7")
        XCTAssertEqual(accepted.entries[second.confirmations[1].id], "G9")
        XCTAssertEqual(first.confirmations.map(\.drawingData), frozenFirstInk)
        XCTAssertEqual(second.confirmations.map(\.drawingData), frozenSecondInk)
        XCTAssertEqual(state.clearCount, 0, "This synthetic harness cannot clear chart ink or teach any profile")
    }

    private func batch(texts: [String]) -> PendingChordInkBatchConfirmation {
        let confirmations = texts.enumerated().map { index, text in
            let result = ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
                match: ChordRecognitionCompendium.match(text), confidence: 1)
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            return PendingChordInkConfirmation(measureID: UUID(), measureIndex: index, result: result,
                drawingData: Data([UInt8(index + 1)]), targetFraction: 0,
                primaryDecision: decision, decision: decision)
        }
        return PendingChordInkBatchConfirmation(confirmations: confirmations)
    }

    private func chordFields(in view: UIView?) -> [IChartTypedUITextField] {
        guard let view else { return [] }
        return descendants(view).compactMap { $0 as? IChartTypedUITextField }.filter { $0.placeholder == "Chord" }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private struct MountedReview {
        let view: UIView
        let fields: [IChartTypedUITextField]
    }

    private func mountedReview(in host: UIViewController, window: UIWindow,
                               expectedTexts: [String]) -> MountedReview? {
        // Reacquire the controller on every poll: SwiftUI may replace its contents or controller.
        guard let presented = host.presentedViewController,
              !presented.isBeingPresented, !presented.isBeingDismissed,
              let view = presented.viewIfLoaded, view.window === window else { return nil }
        view.layoutIfNeeded()
        let fields = chordFields(in: view)
        guard fields.count == expectedTexts.count,
              fields.allSatisfy({ $0.window === window && !$0.isHidden && $0.alpha > 0
                  && $0.bounds.width > 0 && $0.bounds.height > 0 }),
              fields.map({ $0.text ?? "" }).sorted() == expectedTexts.sorted() else { return nil }
        return MountedReview(view: view, fields: fields)
    }

    private func waitForMountedReview(in host: UIViewController, window: UIWindow,
                                      expectedTexts: [String], file: StaticString = #filePath,
                                      line: UInt = #line) async throws -> MountedReview {
        for _ in 0..<100 {
            if let mounted = mountedReview(in: host, window: window, expectedTexts: expectedTexts) {
                return mounted
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if let mounted = mountedReview(in: host, window: window, expectedTexts: expectedTexts) {
            return mounted
        }
        let presented = host.presentedViewController
        let fields = chordFields(in: presented?.viewIfLoaded)
        let report = "Expected chord fields: \(expectedTexts); found: \(fields.count); "
            + "presenting: \(presented?.isBeingPresented ?? false); "
            + "dismissing: \(presented?.isBeingDismissed ?? false); "
            + "sheet in test window: \(presented?.viewIfLoaded?.window === window); "
            + "fields: \(fields.map { "text=\($0.text ?? "<nil>"), bounds=\($0.bounds), inWindow=\($0.window === window)" })"
        let attachment = XCTAttachment(string: report)
        attachment.name = "Mounted sheet readiness timeout"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Abort before editing or rendering: zero or stale rows must never produce a false pass.
        return try XCTUnwrap(nil as MountedReview?, report, file: file, line: line)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<40 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        _ = try XCTUnwrap(predicate() ? true : nil,
                          "The native sheet presentation did not reach the requested state")
    }
}

@MainActor
private final class ReviewPresentationState: ObservableObject {
    @Published var batch: PendingChordInkBatchConfirmation?
    @Published var refreshCount = 0
    var processedRefreshCount = 0
    var accepted: [(batchID: UUID, entries: [UUID: String])] = []
    var clearCount = 0
}

private struct ReviewPresentationHarness: View {
    @ObservedObject var state: ReviewPresentationState

    var body: some View {
        Text("\(state.refreshCount)").hidden()
            .onChange(of: state.refreshCount) { _, count in
                state.processedRefreshCount = count
            }
            .sheet(item: $state.batch) { batch in
                ChordInkBatchConfirmationSheetView(batch: batch,
                    onAcceptAll: { state.accepted.append((batch.id, $0)) },
                    onClearAndRewrite: { state.clearCount += 1 },
                    onBackToInk: { state.batch = nil })
                    .id(batch.id)
            }
    }
}
#endif

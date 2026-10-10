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
        try await waitUntil { host.presentedViewController != nil }
        try await Task.sleep(nanoseconds: 400_000_000)
        let originalFields = chordFields(in: host.presentedViewController?.view)
        XCTAssertEqual(originalFields.count, 2)
        let edited = try XCTUnwrap(originalFields.first)
        edited.text = "Eb7"
        edited.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        state.refreshCount += 1
        state.batch = first
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(chordFields(in: host.presentedViewController?.view).first?.text, "Eb7",
                       "Refreshing the same batch must preserve its user's correction")
        if dismissBeforeReplacement {
            state.batch = nil
            try await waitUntil { host.presentedViewController == nil }
        }
        state.batch = second
        try await waitUntil { host.presentedViewController != nil }
        try await Task.sleep(nanoseconds: 500_000_000)
        let presentedView = try XCTUnwrap(host.presentedViewController?.view)
        let fields = chordFields(in: presentedView)
        XCTAssertEqual(fields.count, 2)
        for (field, text) in zip(fields, ["F", "G7"]) {
            field.text = text
            field.sendActions(for: .editingChanged)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let render = try XCTUnwrap(descendants(presentedView).compactMap { $0 as? PencilOnlyUIButton }
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
        XCTAssertEqual(accepted.entries[second.confirmations[0].id], "F")
        XCTAssertEqual(accepted.entries[second.confirmations[1].id], "G7")
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

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<40 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(predicate(), "The native sheet presentation did not reach the requested state")
    }
}

@MainActor
private final class ReviewPresentationState: ObservableObject {
    @Published var batch: PendingChordInkBatchConfirmation?
    @Published var refreshCount = 0
    var accepted: [(batchID: UUID, entries: [UUID: String])] = []
    var clearCount = 0
}

private struct ReviewPresentationHarness: View {
    @ObservedObject var state: ReviewPresentationState

    var body: some View {
        Text("\(state.refreshCount)").hidden().sheet(item: $state.batch) { batch in
            ChordInkBatchConfirmationSheetView(batch: batch,
                onAcceptAll: { state.accepted.append((batch.id, $0)) },
                onClearAndRewrite: { state.clearCount += 1 },
                onBackToInk: { state.batch = nil })
                .id(batch.id)
        }
    }
}
#endif

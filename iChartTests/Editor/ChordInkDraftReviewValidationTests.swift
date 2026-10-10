#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

final class ChordInkDraftReviewValidationTests: XCTestCase {
    func testValidReviewTrimsOnlyAcceptedTextAndPreservesTheSnapshotAndSource() throws {
        let state = fixture()
        let original = state
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        // The existing lexical boundary accepts surrounding ASCII spaces,
        // not raw newlines. UI submission trims newlines before this policy.
        let entries = labels(for: state, first: " C9 ", second: " D7 ")
        let reviewed = try ChordInkDraftReviewPolicy.validation(from: state, batch: batch,
            candidateTextByDraftID: entries).get()
        var expected = original
        expected.draftChords[0].selectedText = "C9"
        expected.draftChords[1].selectedText = "D7"
        XCTAssertEqual(reviewed, expected)
        XCTAssertEqual(state, original)
        XCTAssertEqual(batch.reviewedDraftState, original)
        XCTAssertEqual(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
            candidateTextByDraftID: entries), reviewed)
        XCTAssertEqual(ChordInkDraftReviewPolicy.reviewedState(from: state,
            candidateTextByDraftID: entries), reviewed)
        XCTAssertEqual(entries[state.draftChords[0].id], " C9 ")
        XCTAssertNil(original.draftChords[1].previewText,
            "Manual correction must not invent recognition evidence for an unread target")
        XCTAssertNil(reviewed.draftChords[1].recognitionResult?.match)
    }

    func testWrongReviewSourceAndMissingSnapshotHaveSeparateReasons() throws {
        let state = fixture()
        var batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        batch.source = .recognitionProposal
        assertRejected(.wrongReviewSource, state: state, batch: batch, entries: labels(for: state))
        batch.source = .draftPreview
        batch.reviewedDraftState = nil
        assertRejected(.missingSnapshot, state: state, batch: batch, entries: labels(for: state))
    }

    func testChangedDraftOrConfirmationCountIsRejected() throws {
        let state = fixture()
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        var changed = state
        changed.draftChords.removeLast()
        assertRejected(.draftCountChanged, state: changed, batch: batch, entries: labels(for: changed))
        let fewerConfirmations = PendingChordInkBatchConfirmation(
            confirmations: Array(batch.confirmations.prefix(1)), source: .draftPreview,
            reviewedDraftState: state)
        assertRejected(.draftCountChanged, state: state, batch: fewerConfirmations, entries: labels(for: state))
    }

    func testEntireDraftEqualityStillProtectsInkIDsOrderingAndRecognitionMetadata() throws {
        let state = fixture()
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let edits: [(inout ChordPreviewState) -> Void] = [
            { $0.draftChords[0].id = UUID() },
            { $0.draftChords[0].drawingData.append(99) },
            { $0.draftChords.reverse() },
            { $0.draftChords[0].confidence += 0.01 },
            { $0.draftChords[0].recognitionResult?.metrics.totalMilliseconds += 1 },
            { $0.draftChords[0].targetLifecycle?.generationID = UUID() },
            { $0.draftChords[0].selectedText = "C9" }
        ]
        for edit in edits {
            var changed = state
            edit(&changed)
            assertRejected(.draftsChanged, state: changed, batch: batch, entries: labels(for: changed))
        }
    }

    func testValidEntriesCannotRenderChangedBarlineOwnershipOrMetadata() throws {
        let state = fixture()
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let entries = labels(for: state)
        XCTAssertTrue(entries.values.allSatisfy { ChordRecognitionCompendium.match($0) != nil })
        let edits: [(inout ChordPreviewState) -> Void] = [
            { $0.draftBarlines[0].sourceStrokeIndex = 3 },
            { $0.draftBarlines[0].id = UUID() },
            { $0.draftBarlines[0].fraction = 0.9 },
            { $0.draftBarlines[0].metrics.height += 1 },
            { $0.draftBarlines[0].ambiguity = .tooClose },
            { $0.draftBarlines.removeAll() }
        ]
        for edit in edits {
            var changed = state
            edit(&changed)
            assertRejected(.barlinesChanged, state: changed, batch: batch, entries: entries)
        }
    }

    func testChangedPageLayoutIsRejectedEvenWithSupportedEntries() throws {
        let state = fixture()
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        var changed = state
        changed.layoutPageSize = CGSize(width: 1200, height: 900)
        assertRejected(.layoutChanged, state: changed, batch: batch, entries: labels(for: state))
    }

    func testConfirmationIdentityAndOrderMustMatchTheFrozenDrafts() throws {
        let state = fixture()
        let originalBatch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let reordered = PendingChordInkBatchConfirmation(
            confirmations: Array(originalBatch.confirmations.reversed()), source: .draftPreview,
            reviewedDraftState: state)
        assertRejected(.confirmationIDsChanged, state: state, batch: reordered, entries: labels(for: state))
    }

    func testEmptySnapshotDoesNotBecomeAnAcceptableReview() {
        let state = ChordPreviewState()
        let batch = PendingChordInkBatchConfirmation(confirmations: [], source: .draftPreview,
            reviewedDraftState: state)
        assertRejected(.emptyDraft, state: state, batch: batch, entries: [:])
        XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: state, candidateTextByDraftID: [:]))
    }

    func testMissingAndUnexpectedEntryIDsRemainStrictlyRejected() throws {
        let state = fixture()
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        var missing = labels(for: state)
        missing.removeValue(forKey: state.draftChords[1].id)
        assertRejected(.entryIDsChanged, state: state, batch: batch, entries: missing)
        XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: state, candidateTextByDraftID: missing))
        var extra = labels(for: state)
        extra[UUID()] = "G"
        assertRejected(.entryIDsChanged, state: state, batch: batch, entries: extra)
        XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: state, candidateTextByDraftID: extra))
    }

    func testEmptyAndUnsupportedEntriesHaveSeparateReasonsWithoutFallback() throws {
        let state = fixture()
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        for empty in ["", " \n \t "] {
            let entries = labels(for: state, first: empty)
            assertRejected(.emptyEntry, state: state, batch: batch, entries: entries)
            XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: state, candidateTextByDraftID: entries))
        }
        for unsupported in ["J", "ñ", "?", "not a chord", "C9\n"] {
            let entries = labels(for: state, first: unsupported)
            assertRejected(.unsupportedEntry, state: state, batch: batch, entries: entries)
            XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: state, candidateTextByDraftID: entries))
        }
    }

    func testTimestampOnlyChangeStillAcceptsTheSameSourceAndLabels() throws {
        let state = fixture()
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        var later = state
        later.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        let reviewed = try ChordInkDraftReviewPolicy.validation(from: later, batch: batch,
            candidateTextByDraftID: labels(for: state)).get()
        XCTAssertEqual(reviewed.updatedAt, later.updatedAt)
        XCTAssertEqual(reviewed.draftBarlines, state.draftBarlines)
        XCTAssertEqual(batch.reviewedDraftState, state)
    }

    func testCurrentBatchSubmissionDropsStaleKeysButKeepsMissingRowsEmpty() throws {
        let state = fixture()
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let staleID = UUID()
        var temporaryEntries = labels(for: state, first: " C9 \n", second: " D7 ")
        temporaryEntries[staleID] = "G"
        let originalTemporaryEntries = temporaryEntries
        let submission = ChordInkDraftReviewPolicy.submissionTexts(for: batch,
            candidateTextByDraftID: temporaryEntries)
        XCTAssertEqual(Set(submission.keys), Set(batch.confirmations.map(\.id)))
        XCTAssertNil(submission[staleID])
        XCTAssertEqual(submission[state.draftChords[0].id], "C9")
        XCTAssertEqual(submission[state.draftChords[1].id], "D7")
        _ = try ChordInkDraftReviewPolicy.validation(from: state, batch: batch,
            candidateTextByDraftID: submission).get()
        XCTAssertEqual(temporaryEntries, originalTemporaryEntries)

        temporaryEntries.removeValue(forKey: state.draftChords[0].id)
        let missingSubmission = ChordInkDraftReviewPolicy.submissionTexts(for: batch,
            candidateTextByDraftID: temporaryEntries)
        XCTAssertEqual(missingSubmission[state.draftChords[0].id], "")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(
            for: batch.confirmations.map { missingSubmission[$0.id] }), 1)
        assertRejected(.emptyEntry, state: state, batch: batch, entries: missingSubmission)
    }

    func testEveryDiagnosticCodeHasDistinctContentFreeRecoveryGuidance() {
        let rejections: [ChordInkDraftReviewRejection] = [
            .wrongReviewSource, .missingSnapshot, .draftCountChanged, .draftsChanged,
            .barlinesChanged, .layoutChanged, .confirmationIDsChanged, .emptyDraft,
            .entryIDsChanged, .emptyEntry, .unsupportedEntry
        ]
        XCTAssertEqual(Set(rejections.map(\.rawValue)).count, 11)
        XCTAssertEqual(Set(rejections.map(\.recoveryMessage)).count, 11)
        for rejection in rejections {
            XCTAssertFalse(rejection.recoveryMessage.isEmpty)
            XCTAssertFalse(rejection.recoveryMessage.contains("C9"))
            XCTAssertFalse(rejection.recoveryMessage.contains("D7"))
            XCTAssertFalse(rejection.recoveryMessage.contains("UUID"))
        }
    }

    private func assertRejected(
        _ reason: ChordInkDraftReviewRejection,
        state: ChordPreviewState,
        batch: PendingChordInkBatchConfirmation,
        entries: [UUID: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let originalState = state
        let originalSnapshot = batch.reviewedDraftState
        let originalEntries = entries
        switch ChordInkDraftReviewPolicy.validation(from: state, batch: batch,
            candidateTextByDraftID: entries) {
        case .success:
            XCTFail("Expected rejection: \(reason.rawValue)", file: file, line: line)
        case .failure(let actual):
            XCTAssertEqual(actual.rawValue, reason.rawValue, file: file, line: line)
        }
        XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
            candidateTextByDraftID: entries), file: file, line: line)
        XCTAssertEqual(state, originalState, file: file, line: line)
        XCTAssertEqual(batch.reviewedDraftState, originalSnapshot, file: file, line: line)
        XCTAssertEqual(entries, originalEntries, file: file, line: line)
    }

    private func labels(for state: ChordPreviewState, first: String = "C9", second: String = "D7") -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: state.draftChords.enumerated().map {
            ($0.element.id, $0.offset == 0 ? first : second)
        })
    }

    /// Validation treats drawing bytes as opaque source identity. These tests
    /// exercise review ownership and entry validation, not ink decoding or OCR.
    private func fixture() -> ChordPreviewState {
        let pageSize = CGSize(width: 900, height: 1400)
        let firstMeasureID = UUID()
        let secondMeasureID = UUID()
        let recognized = ChordInkRecognitionResult(rawCandidates: ["C7"], glyphCandidates: [],
            match: ChordRecognitionCompendium.match("C7"), confidence: 4.2)
        let unread = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [],
            match: nil, confidence: 0)
        let resultPairs = [(firstMeasureID, recognized), (secondMeasureID, unread)]
        let drafts = resultPairs.enumerated().map { index, pair -> ChordInkDraft in
            let input = ChordInkDraftInput(measureID: pair.0, measureIndex: index, targetFraction: 0.25,
                laneLocation: .init(systemIndex: 0, fraction: index == 0 ? 0.25 : 0.65),
                layoutPageSize: pageSize, drawingData: Data([UInt8(index + 1)]),
                candidateTexts: index == 0 ? ["C7"] : [], bestCandidateText: index == 0 ? "C7" : nil,
                confidence: pair.1.confidence, strokeCount: 1, recognitionResult: pair.1,
                recognitionDecision: ChordInkRecognitionPolicy.decision(for: pair.1))
            var draft = ChordInkDraft(input: input)
            draft.targetLifecycle = .init(generationID: UUID(), anchor: input.anchor,
                ownership: .init(preparedStrokes: [InkStroke(points: [
                    InkPoint(x: Double(index * 40), y: 10, timeOffset: 0),
                    InkPoint(x: Double(index * 40 + 20), y: 30, timeOffset: 0.1)
                ])]), stage: .frozen)
            return draft
        }
        let barline = DraftBarline(measureID: firstMeasureID, measureIndex: 0, fraction: 0.8,
            laneLocation: .init(systemIndex: 0, fraction: 0.8), layoutPageSize: pageSize,
            sourceStrokeIndex: 2, metrics: .init(height: 80, width: 2,
                angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 1))
        return ChordPreviewState(draftChords: drafts, draftBarlines: [barline],
            layoutPageSize: pageSize, updatedAt: Date(timeIntervalSinceReferenceDate: 100))
    }
}
#endif

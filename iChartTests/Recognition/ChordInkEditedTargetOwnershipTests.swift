import XCTest
import CryptoKit
@testable import iChart

final class ChordInkEditedTargetOwnershipTests: XCTestCase {
    private typealias Policy = ChordInkEditedTargetOwnership
    private typealias Target = Policy.Target
    // Abstract geometry only: these tests do not encode chord-specific glyphs.
    private let survivor = InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 10, y: 30)], creationTimeOffset: 2)
    private let removed = InkStroke(points: [InkPoint(x: 15, y: 5), InkPoint(x: 30, y: 25)], creationTimeOffset: 3)
    private let replacement = InkStroke(points: [InkPoint(x: 16, y: 12), InkPoint(x: 28, y: 20)], creationTimeOffset: 99)
    private let neighbor = InkStroke(points: [InkPoint(x: 50, y: 0), InkPoint(x: 60, y: 30)], creationTimeOffset: 4)
    private func target(_ strokes: [InkStroke], lane: Int = 0) -> Target { Target(lane: lane, strokes: strokes) }

    private func assertExhaustive(_ result: Policy.Resolution, _ proposed: [Target], file: StaticString = #filePath, line: UInt = #line) {
        let expected = proposed.indices.flatMap { target in proposed[target].strokes.indices.map {
            Policy.SourceStroke(targetIndex: target, strokeIndex: $0)
        } }
        let actual = result.sourceStrokes.flatMap { $0 }
        XCTAssertEqual(Set(actual), Set(expected), file: file, line: line)
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    }

    func testPartialEraseThenReplacementReusesOwnershipWithoutAnyLabelOrTiming() {
        let initial = [target([survivor, removed]), target([neighbor])]
        let state = Policy().resolving(initial).next
        for delay in [0.01, 1, 30, 600] {
            var resumed = replacement; resumed.creationTimeOffset = delay
            let proposed = [target([survivor]), target([resumed]), target([neighbor])]
            let result = state.resolving(proposed)
            XCTAssertEqual(result.sourceTargetIndices, [[0, 1], [2]])
            XCTAssertEqual(result.requiresReview, [0])
            assertExhaustive(result, proposed)
        }
    }

    func testEraseOnlySnapshotsKeepFootprintUntilReplacementOrFullErase() {
        var state = Policy().resolving([target([survivor, removed]), target([neighbor])]).next
        for _ in 0..<3 {
            let result = state.resolving([target([survivor]), target([neighbor])])
            XCTAssertEqual(result.sourceTargetIndices, [[0], [1]])
            XCTAssertEqual(result.requiresReview, [0]); state = result.next
        }
        let repaired = state.resolving([target([survivor]), target([replacement]), target([neighbor])])
        XCTAssertEqual(repaired.sourceTargetIndices, [[0, 1], [2]])
        let erased = state.resolving([target([neighbor])]).next
        let newInk = erased.resolving([target([survivor]), target([replacement]), target([neighbor])])
        XCTAssertEqual(newInk.sourceTargetIndices, [[0], [1], [2]])
        XCTAssertTrue(newInk.requiresReview.isEmpty)
    }

    func testAppendOnlyInputCannotActivateEditReattachment() {
        let state = Policy().resolving([target([survivor, removed])]).next
        let proposed = [target([survivor, removed]), target([replacement]), target([neighbor])]
        let result = state.resolving(proposed)
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1], [2]])
        XCTAssertTrue(result.requiresReview.isEmpty)
        assertExhaustive(result, proposed)
    }

    func testGrowingPenDownPathIsNotAnErase() {
        let state = Policy().resolving([target([survivor, removed])]).next
        let continued = InkStroke(points: removed.points + [InkPoint(x: 36, y: 30)], creationTimeOffset: 3)
        let result = state.resolving([target([survivor, continued])])
        XCTAssertTrue(result.requiresReview.isEmpty)
        XCTAssertEqual(result.sourceTargetIndices, [[0]])
    }

    func testTargetingOmissionCannotMasqueradeAsAnErase() {
        let state = Policy().resolving([target([survivor, removed])]).next
        let proposed = [target([survivor]), target([replacement])]
        let result = state.resolving(proposed, visibleStrokes: [survivor, removed, replacement])
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1]])
        XCTAssertTrue(result.requiresReview.isEmpty)
    }

    func testProposedInputNotPresentOnPageCannotAuthorizeAnEdit() {
        let state = Policy().resolving([target([survivor, removed])]).next
        let proposed = [target([survivor]), target([replacement])]
        let result = state.resolving(proposed, visibleStrokes: [survivor])
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1]])
        XCTAssertEqual(result.requiresReview, [0, 1])
    }

    func testNeighborAndOtherLaneInkAreNeverClaimedByAnEditedFootprint() {
        let state = Policy().resolving([target([survivor, removed]), target([neighbor])]).next
        let proposed = [target([survivor]), target([replacement], lane: 1), target([neighbor])]
        let result = state.resolving(proposed)
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1], [2]])
        XCTAssertEqual(result.requiresReview, [0])
        var outside = replacement; outside.points[1].x = 31
        let escaped = state.resolving([target([survivor]), target([outside]), target([neighbor])])
        XCTAssertEqual(escaped.sourceTargetIndices, [[0], [1], [2]])
    }

    func testUndoRestoresTheOriginalInputAndClearsEditReview() {
        let original = [target([survivor, removed]), target([neighbor])]
        let state = Policy().resolving(original).next.resolving([target([survivor]), target([neighbor])]).next
        let undone = state.resolving(original)
        XCTAssertEqual(undone.sourceTargetIndices, [[0], [1]])
        XCTAssertTrue(undone.requiresReview.isEmpty)
    }

    func testTimelineRebasingDoesNotInventRemovalOfUnchangedStrokes() {
        let state = Policy().resolving([target([survivor, removed])]).next
        var root = survivor; root.creationTimeOffset = 0
        var suffix = removed; suffix.creationTimeOffset = 1
        let unchanged = state.resolving([target([root, suffix])])
        XCTAssertTrue(unchanged.requiresReview.isEmpty)
        let changed = state.resolving([target([root]), target([replacement])])
        XCTAssertEqual(changed.sourceTargetIndices, [[0, 1]])
    }

    func testTranslationAndScaleOfWholeSequenceDoNotChangeResolution() {
        for scale in [0.25, 1, 4] {
            func transform(_ stroke: InkStroke) -> InkStroke {
                InkStroke(points: stroke.points.map { InkPoint(x: $0.x * scale + 700, y: $0.y * scale + 1100) })
            }
            let state = Policy().resolving([target([transform(survivor), transform(removed)])]).next
            let result = state.resolving([target([transform(survivor)]), target([transform(replacement)])])
            XCTAssertEqual(result.sourceTargetIndices, [[0, 1]])
        }
    }

    func testAmbiguousDuplicateStrokeIdentityDoesNotMerge() {
        let state = Policy().resolving([target([survivor, removed])]).next
        let proposed = [target([survivor]), target([survivor]), target([replacement])]
        let result = state.resolving(proposed)
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1], [2]])
        XCTAssertEqual(result.requiresReview, [0, 1, 2])
        assertExhaustive(result, proposed)
    }

    func testExistingNeighborInsideFootprintIsNotReassigned() {
        let state = Policy().resolving([target([survivor, removed]), target([replacement])]).next
        let result = state.resolving([target([survivor]), target([replacement])])
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1]])
        XCTAssertEqual(result.requiresReview, [0])
    }

    func testPreviouslyUnassignedInkIsNotAReplacementStroke() {
        let state = Policy().resolving([target([survivor, removed])],
                                      visibleStrokes: [survivor, removed, replacement]).next
        let result = state.resolving([target([survivor]), target([replacement])])
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1]])
        XCTAssertEqual(result.requiresReview, [0])
    }

    func testPartialOwnerMovedByTargetingToAnotherLaneStillRequiresReview() {
        let state = Policy().resolving([target([survivor, removed])]).next
        let result = state.resolving([target([survivor], lane: 1), target([replacement])])
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1]])
        XCTAssertEqual(result.requiresReview, [0])
    }

    func testPartiallyErasedOverlappingOwnersDoNotMergeAmbiguousReplacement() {
        let second = InkStroke(points: [InkPoint(x: 2, y: 1), InkPoint(x: 11, y: 30)])
        let secondRemoved = InkStroke(points: [InkPoint(x: 14, y: 7), InkPoint(x: 32, y: 23)])
        let state = Policy().resolving([target([survivor, removed]), target([second, secondRemoved])]).next
        let proposed = [target([survivor]), target([second]), target([replacement])]
        let result = state.resolving(proposed)
        XCTAssertEqual(result.sourceTargetIndices, [[0], [1], [2]])
        XCTAssertEqual(result.requiresReview, [0, 1, 2], "Ambiguous replacement also requires review")
        let stillAmbiguous = result.next.resolving(proposed)
        XCTAssertEqual(stillAmbiguous.sourceTargetIndices, [[0], [1], [2]])
        XCTAssertEqual(stillAmbiguous.requiresReview, [0, 1, 2])
        assertExhaustive(result, proposed)
    }

    func testMixedGroupRestoresAnUntouchedNeighborByExactStrokeOwnership() {
        for scale in [0.25, 1, 4] {
            for direction in [-1.0, 1.0] {
                func transform(_ ink: InkStroke) -> InkStroke {
                    InkStroke(points: ink.points.map { InkPoint(x: direction * $0.x * scale + 200,
                                                               y: $0.y * scale + 100) }, creationTimeOffset: 600)
                }
                let a = transform(survivor), b = transform(removed), c = transform(neighbor)
                // Extends vertically beyond the old glyph, still confined to
                // its horizontal footprint and overlapping its vertical span.
                let d = transform(InkStroke(points: [InkPoint(x: 18, y: -4), InkPoint(x: 28, y: 20)]))
                let state = Policy().resolving([target([a, b]), target([c])]).next
                let proposed = [target([c, a, d])]
                let result = state.resolving(proposed)
                let groups = result.sourceStrokes.map { $0.map { proposed[$0.targetIndex].strokes[$0.strokeIndex] } }
                XCTAssertEqual(Set(groups.map { Set($0.map(\.points)) }), Set([Set([a.points, d.points]), Set([c.points])]))
                XCTAssertEqual(result.requiresReview.count, 1)
                let reviewed = groups[result.requiresReview.first!]
                XCTAssertEqual(Set(reviewed.map(\.points)), Set([a.points, d.points]))
                assertExhaustive(result, proposed)
                let again = result.next.resolving(proposed)
                XCTAssertEqual(again.sourceStrokes, result.sourceStrokes)
                XCTAssertEqual(again.requiresReview, result.requiresReview)
            }
        }
    }

    func testMixedGroupDoesNotSplitWithoutUniquePriorEditOwnership() {
        let seeded = Policy().resolving([target([survivor, removed]), target([neighbor])]).next
        let outsiders = [
            InkStroke(points: [InkPoint(x: 25, y: 10), InkPoint(x: 51, y: 20)]),
            InkStroke(points: [InkPoint(x: 18, y: 100), InkPoint(x: 28, y: 110)])
        ]
        for outside in outsiders {
            let proposed = [target([survivor, neighbor, outside])]
            let result = seeded.resolving(proposed)
            XCTAssertEqual(result.sourceStrokes.count, 1)
            XCTAssertEqual(result.requiresReview, [0])
            assertExhaustive(result, proposed)
        }
        let appendOnly = [target([survivor, removed, neighbor, replacement])]
        XCTAssertEqual(seeded.resolving(appendOnly).sourceStrokes.count, 1)
        let otherLane = Policy().resolving([target([survivor, removed]), target([neighbor], lane: 1)]).next
        XCTAssertEqual(otherLane.resolving([target([survivor, neighbor, replacement])]).sourceStrokes.count, 1)
        let unknown = Policy().resolving([target([survivor, removed])], visibleStrokes: [survivor, removed, neighbor]).next
        XCTAssertEqual(unknown.resolving([target([survivor, neighbor, replacement])]).sourceStrokes.count, 1)
    }

    func testEmptyTargetRemainsFailClosedWithoutIndexingMissingStrokes() {
        let result = Policy().resolving([target([])])
        XCTAssertEqual(result.sourceStrokes, [[]])
        XCTAssertEqual(result.requiresReview, [0])
    }

    /// Historical trace replay proves only partition continuity, not chord
    /// accuracy. Device labels/actions are reported after the policy resolves.
    func testProvidedTraceChecksEditContinuityWithoutUsingChordLabels() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["ICHART_EDIT_OWNERSHIP_TRACE"] else { throw XCTSkip("Supply an authorized local device trace") }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        let events = try ChordDraftPreviewDeviceDiagnosticRecorder(url: url).loadEvents()
        var state = Policy()
        var rows: [[String: Any]] = []
        var partitionChanges: [[String: Any]] = []
        var snapshots = 0
        var omittedSnapshots = 0
        var scope: String?
        var visibleCount: Int?
        for event in events {
            let nextScope = "\(event.recognitionPipelineVersion ?? "unknown")/\(event.layoutStyle ?? "unknown")"
            if event.stage == "reset" || nextScope != scope {
                state = Policy(); visibleCount = nil; scope = nextScope
            }
            if let version = env["ICHART_EDIT_OWNERSHIP_PIPELINE"], event.recognitionPipelineVersion != version { continue }
            if event.stage == "targeting" { visibleCount = event.recognitionStrokeCount }
            guard event.stage == "finish_batch" || event.stage == "finish_single", !event.payloads.isEmpty else { continue }
            let targets = try event.payloads.map { payload in
                Target(lane: try XCTUnwrap(payload.laneSystemIndex), strokes: try XCTUnwrap(payload.inkStrokes))
            }
            let visible = targets.flatMap(\.strokes)
            // A dropped/unassigned target must not masquerade as an erase in a
            // replay that does not contain the whole-page PencilKit drawing.
            guard visibleCount == visible.count else {
                state = Policy(); omittedSnapshots += 1; continue
            }
            let result = state.resolving(targets, visibleStrokes: visible)
            assertExhaustive(result, targets)
            let identity = targets.indices.map { index in targets[index].strokes.indices.map {
                Policy.SourceStroke(targetIndex: index, strokeIndex: $0)
            } }
            if result.sourceStrokes != identity {
                partitionChanges.append(["timestamp": event.timestamp.timeIntervalSince1970,
                    "inputCounts": targets.map { $0.strokes.count },
                    "outputCounts": result.sourceStrokes.map(\.count),
                    "reviewedOutputIndices": result.requiresReview.sorted(),
                    "sourceStrokeIndices": result.sourceStrokes.map { $0.map { [$0.targetIndex, $0.strokeIndex] } }])
            }
            for (index, source) in result.sourceTargetIndices.enumerated() where result.requiresReview.contains(index) {
                rows.append(["timestamp": event.timestamp.timeIntervalSince1970, "sources": source,
                    "strokeCount": result.sourceStrokes[index].count,
                    "recordedReads": source.map { event.payloads[$0].acceptedText ?? "no-read" },
                    "recordedActions": source.map { event.payloads[$0].action }])
            }
            state = result.next; snapshots += 1
        }
        XCTAssertGreaterThan(snapshots, 0)
        if let expected = env["ICHART_EDIT_OWNERSHIP_EXPECTED_REVIEW_COUNT"] {
            XCTAssertEqual(rows.count, try XCTUnwrap(Int(expected)))
        }
        if let expected = env["ICHART_EDIT_OWNERSHIP_EXPECTED_CHANGED_COUNT"] {
            XCTAssertEqual(partitionChanges.count, try XCTUnwrap(Int(expected)))
        }
        let report: [String: Any] = ["scope": "label-blind historical ownership replay; not recognition accuracy or production behavior",
            "traceSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "snapshots": snapshots, "omittedIncompleteSnapshots": omittedSnapshots,
            "pipelineFilter": env["ICHART_EDIT_OWNERSHIP_PIPELINE"] ?? "all historical versions",
            "editedTargetsRequiringReview": rows, "partitionChanges": partitionChanges]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let output = env["ICHART_EDIT_OWNERSHIP_REPORT"] {
            let destination = URL(fileURLWithPath: output).resolvingSymlinksInPath()
            guard destination != url else { XCTFail("Cannot overwrite source trace"); return }
            try encoded.write(to: destination, options: .atomic)
        }
        XCTAssertEqual(try Data(contentsOf: url), data)
        print("EDIT_OWNERSHIP_REPORT\n\(String(decoding: encoded, as: UTF8.self))")
    }
}

private extension ChordInkEditedTargetOwnership {
    // Test convenience only; production callers must supply the actual page
    // input, never infer an erasure from a target disappearing.
    func resolving(_ proposed: [Target]) -> Resolution {
        resolving(proposed, visibleStrokes: proposed.flatMap(\.strokes))
    }
}

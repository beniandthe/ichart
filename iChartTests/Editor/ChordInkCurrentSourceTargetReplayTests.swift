#if canImport(UIKit) && canImport(PencilKit)
import CryptoKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Opt-in diagnostics for an authorized source capture. The decoder ignores
/// intended answers, predictions, profiles, and teaching examples. Recorded
/// ownership is compared only AFTER inference, never supplied to grouping.
final class ChordInkCurrentSourceTargetReplayTests: XCTestCase {
    func testProvidedCurrentSourceReportsTargetRouteAndRootAnchors() throws {
        try replayCurrentSource(checkConfirmedBoundaryRepair: false)
    }

    /// Development regression on writer-confirmed ink, not a fresh accuracy
    /// test. Expected ownership is checked after label-free live preparation.
    func testProvidedConfirmedRhythmSourceKeepsRaisedSuffixWithRoot() throws {
        try replayCurrentSource(checkConfirmedBoundaryRepair: true)
    }

    func testProvidedFreshSimpleSourceKeepsTemporalConstructionWithRoot() throws {
        try replayCurrentSource(checkConfirmedBoundaryRepair: false, checkFreshSimpleBoundaryRepair: true)
    }

    private func replayCurrentSource(checkConfirmedBoundaryRepair: Bool,
                                     checkFreshSimpleBoundaryRepair: Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        let names = ["ICHART_CURRENT_SOURCE_REPLAY_JOURNAL", "ICHART_CURRENT_SOURCE_REPLAY_RUN_ID",
                     "ICHART_CURRENT_SOURCE_REPLAY_LIBRARY"]
        guard names.allSatisfy({ env[$0] != nil }) else {
            throw XCTSkip("Supply an authorized source journal, run ID, and saved source-chart library")
        }
        guard names.allSatisfy({ !(env[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }) else {
            XCTFail("Replay configuration must be nonempty"); return
        }
        let journalURL = URL(fileURLWithPath: env[names[0]]!).standardizedFileURL.resolvingSymlinksInPath()
        let libraryURL = URL(fileURLWithPath: env[names[2]]!).standardizedFileURL.resolvingSymlinksInPath()
        let journalBytes = try Data(contentsOf: journalURL)
        let libraryBytes = try Data(contentsOf: libraryURL)
        defer {
            XCTAssertEqual(try? Data(contentsOf: journalURL), journalBytes, "Source journal is read-only")
            XCTAssertEqual(try? Data(contentsOf: libraryURL), libraryBytes, "Source chart is read-only")
        }
        let runID = try XCTUnwrap(UUID(uuidString: env[names[1]]!))
        struct SourceRun: Decodable {
            let id: UUID
            let chartID: UUID
            let style: String
            let sourceSnapshot: PersonalInkEvaluationSourceSnapshot
        }
        let run: SourceRun = try selectedObject(in: journalBytes, collection: "runs", id: runID)
        let source = run.sourceSnapshot
        if checkConfirmedBoundaryRepair {
            XCTAssertEqual(runID.uuidString, "EBE139C4-0C8D-4DF8-A7AF-7BF8A526E73E")
            XCTAssertEqual(sha(source.canonicalVisibleTrajectoryData),
                "b5893094b5d6e33ca19ccc9338b4e861b1cc25b13876a5d3bd216d7d9be5b61c")
            guard testRun?.failureCount == 0 else { return }
        }
        if checkFreshSimpleBoundaryRepair {
            XCTAssertEqual(runID.uuidString, "CEDFEE65-6EC5-44AE-B952-FCFCBFBD4F88")
            XCTAssertEqual(sha(source.canonicalVisibleTrajectoryData),
                "2adafba0667d01ae1f1cbeaf4d12c94111cebe1916d5d360be6c464917cd3892")
            guard testRun?.failureCount == 0 else { return }
        }
        // The chart is used only to recreate layout. Its text is never passed
        // to a recognizer. Select only the bound chart, not unrelated library data.
        let chart: Chart = try selectedObject(in: libraryBytes, collection: "charts", id: run.chartID)
        XCTAssertEqual(chart.layoutStyle.rawValue, run.style)
        let pageBounds = try XCTUnwrap(source.pageBounds)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageBounds.size,
            includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        XCTAssertEqual(layout.pageBounds, pageBounds)
        XCTAssertEqual(region.frame, source.chordFrame, "No scaling/reflow is allowed in source replay")
        XCTAssertEqual(layout.pages.map(\.index), source.pages.map(\.index))
        XCTAssertEqual(layout.pages.map(\.frame), source.pages.map(\.frame))
        let measures = layout.systems.flatMap(\.measures)
        XCTAssertEqual(measures.map(\.index), source.measures.map(\.index))
        XCTAssertEqual(measures.map(\.chordWritingFrame), source.measures.map(\.chordWritingFrame))
        XCTAssertEqual(measures.map { $0.chordInkTargetMeasureID ?? $0.sourceMeasureID },
                       source.measures.map(\.targetMeasureID))
        guard testRun?.failureCount == 0 else { return }

        let preparation = ChordInkRecognitionPreparation.prepare(.init(
            requestID: source.requestID, scheduledAt: Date(), requestedDelay: 0,
            drawingData: source.normalizedDrawingData, chordFrame: source.chordFrame,
            pageLayout: layout, flow: .draftPreview, options: .live,
            layoutStyle: chart.layoutStyle, capturesEvaluationSource: true))
        let replayed = try XCTUnwrap(preparation.evaluationSource)
        XCTAssertEqual(replayed.visibleStrokes, source.visibleStrokes)
        XCTAssertEqual(try ChordInkCanonicalTrajectoryPacket(strokes: replayed.visibleStrokes).canonicalData(),
                       source.canonicalVisibleTrajectoryData)
        try emit([
            "stage": "preparation", "runID": runID.uuidString,
            "sourceRequestID": source.requestID.uuidString, "sourceInkRevision": source.inkRevision,
            "sourceSHA256": sha(source.canonicalVisibleTrajectoryData),
            "outcome": replayed.outcome, "rawTargetCount": preparation.rawBatchTargetCount,
            "boundedTargetCount": preparation.boundedBatchTargetCount,
            "visibleFragmentGroups": replayed.ownership.targetGroups.map(\.visibleFragmentIndices),
            "unassignedVisibleFragmentIndices": replayed.ownership.unassignedVisibleFragmentIndices,
            "barlineVisibleFragmentIndices": replayed.ownership.barlineVisibleFragmentIndices,
            "sameRecordedPartition": replayed.ownership == source.ownership,
            "boundaryHypotheses": preparation.boundaryHypothesisSet?.hypotheses.map { hypothesis in
                ["route": hypothesis.route.rawValue,
                 "recognitionIndexGroups": hypothesis.targetRecognitionStrokeIndices,
                 "unassignedRecognitionIndices": hypothesis.unassignedRecognitionStrokeIndices] as [String: Any]
            } ?? [],
            "scope": "saved-source-diagnostic-not-fresh-accuracy-no-expected-label-input"
        ])
        if checkConfirmedBoundaryRepair {
            let recordedGroups = source.ownership.targetGroups.map(\.visibleFragmentIndices)
            XCTAssertEqual(recordedGroups.count, 9)
            guard recordedGroups.count == 9 else { return }
            // Inference has already finished. This writer-confirmed development
            // assertion is never passed into preparation or its route choice.
            let expectedGroups = Array(recordedGroups.prefix(6))
                + [(recordedGroups[6] + recordedGroups[7]).sorted(), recordedGroups[8]]
            XCTAssertEqual(replayed.ownership.targetGroups.map(\.visibleFragmentIndices), expectedGroups,
                "Keep the raised suffix with its preceding root; preserve every other chord")
            XCTAssertEqual(replayed.ownership.unassignedVisibleFragmentIndices,
                source.ownership.unassignedVisibleFragmentIndices)
            XCTAssertEqual(replayed.ownership.barlineVisibleFragmentIndices,
                source.ownership.barlineVisibleFragmentIndices)
            XCTAssertEqual(preparation.rawBatchTargetCount, expectedGroups.count)
            XCTAssertEqual(preparation.boundedBatchTargetCount, expectedGroups.count)
            let retainedIndices = replayed.ownership.targetGroups.flatMap(\.visibleFragmentIndices)
                + replayed.ownership.unassignedVisibleFragmentIndices
                + replayed.ownership.barlineVisibleFragmentIndices
            XCTAssertEqual(retainedIndices.count, replayed.visibleStrokes.count)
            XCTAssertEqual(Set(retainedIndices), Set(replayed.visibleStrokes.indices),
                "Every visible source fragment must remain accounted for exactly once")
        } else if checkFreshSimpleBoundaryRepair {
            // Known-source regression assertions occur AFTER inference. No
            // recorded partition, expected count, or chord label chose a route.
            let recordedGroups = source.ownership.targetGroups.map(\.visibleFragmentIndices)
            XCTAssertEqual(recordedGroups.count, 9)
            guard recordedGroups.count == 9 else { return }
            let expectedGroups = Array(recordedGroups.prefix(5))
                + [(recordedGroups[5] + recordedGroups[6]).sorted()]
                + Array(recordedGroups.suffix(2))
            XCTAssertEqual(replayed.ownership.targetGroups.map(\.visibleFragmentIndices), expectedGroups)
            XCTAssertEqual(preparation.rawBatchTargetCount, 8)
            XCTAssertEqual(preparation.boundedBatchTargetCount, 8)
            XCTAssertEqual(replayed.ownership.unassignedVisibleFragmentIndices,
                           source.ownership.unassignedVisibleFragmentIndices)
            XCTAssertEqual(replayed.ownership.barlineVisibleFragmentIndices,
                           source.ownership.barlineVisibleFragmentIndices)
            let retained = replayed.ownership.targetGroups.flatMap(\.visibleFragmentIndices)
                + replayed.ownership.unassignedVisibleFragmentIndices
                + replayed.ownership.barlineVisibleFragmentIndices
            XCTAssertEqual(retained.count, 57)
            XCTAssertEqual(Set(retained), Set(replayed.visibleStrokes.indices))
        } else {
            // A mismatch is a diagnostic failure, not permission to select a
            // route using recorded ownership or an intended chord answer.
            XCTAssertEqual(replayed.ownership, source.ownership,
                "Exact source replay must reproduce recorded ownership before causal interpretation")
        }
        guard testRun?.failureCount == 0 else { return }

        let originalDrawing = try PKDrawing(data: source.normalizedDrawingData)
        let visible = ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(from: originalDrawing)
        let visibleBarlineIndices = Set(replayed.ownership.barlineVisibleFragmentIndices)
        let recognitionDrawing = visible.drawing.removingStrokes(at: visibleBarlineIndices)
        let recognitionStrokes = replayed.recognitionStrokes
        let raw = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: recognitionDrawing, chordFrame: source.chordFrame, pageLayout: layout,
            draftBarlines: preparation.barlines, preparedInkStrokes: recognitionStrokes)
        let bounded = ChordInkDraftPreviewRecognitionLoadPolicy.boundedBatchTargets(raw.targets, flow: .draftPreview)
        try emit([
            "stage": "raw_targeting", "diagnostics": try jsonObject(raw.diagnostics),
            "rawVisibleFragmentGroups": raw.targets.map { target in
                target.recognitionStrokeIndices.map { replayed.recognitionVisibleFragmentIndices[$0] }
            },
            "boundedVisibleFragmentGroups": bounded.map { target in
                target.recognitionStrokeIndices.map { replayed.recognitionVisibleFragmentIndices[$0] }
            }
        ])
        if checkConfirmedBoundaryRepair {
            let recognizer = ChordInkMaximumTrustRecognizer()
            for (ordinal, target) in bounded.enumerated() {
                let result = recognizer.recognize(strokes: target.strokes, options: .live)
                try emit([
                    "stage": "post_repair_native_chord_diagnostic",
                    "targetOrdinal": ordinal,
                    "visibleIndices": target.recognitionStrokeIndices.map {
                        replayed.recognitionVisibleFragmentIndices[$0]
                    },
                    "match": result.match?.displayText as Any? ?? NSNull(),
                    "action": ChordInkRecognitionPolicy.decision(for: result).action.rawValue,
                    "scope": "writer-confirmed-development-replay-not-fresh-accuracy"
                ])
            }
        }

        // Optional causal diagnostic on ALL targets and adjacent pairs. This
        // reports parse/decision evidence; it never selects a boundary or
        // supplies an expected chord to inference.
        if env["ICHART_CURRENT_SOURCE_REPLAY_NATIVE_DIAGNOSTICS"] == "1" {
            let recognizer = ChordInkMaximumTrustRecognizer()
            let directRecognizer = ChordInkRecognizer(normalizesOversizedInput: false)
            for (ordinal, target) in bounded.enumerated() {
                let result = recognizer.recognize(strokes: target.strokes, options: .live)
                let direct = directRecognizer.recognize(strokes: target.strokes)
                try emit(["stage": "all_target_native_diagnostic", "targetOrdinal": ordinal,
                          "visibleIndices": target.recognitionStrokeIndices.map {
                              replayed.recognitionVisibleFragmentIndices[$0]
                          },
                          "match": result.match?.displayText as Any? ?? NSNull(),
                          "directMatch": direct.match?.displayText as Any? ?? NSNull(),
                          "directGlyphs": direct.acceptedGlyphCandidates.map(\.text),
                          "action": ChordInkRecognitionPolicy.decision(for: result).action.rawValue,
                          "scope": "saved-source-development-not-fresh-accuracy"])
                guard ordinal > 0 else { continue }
                let pair = bounded[ordinal - 1].strokes + target.strokes
                let combined = recognizer.recognize(strokes: pair, options: .live)
                let directCombined = directRecognizer.recognize(strokes: pair)
                try emit(["stage": "all_adjacent_pair_native_diagnostic",
                          "targetOrdinals": [ordinal - 1, ordinal],
                          "match": combined.match?.displayText as Any? ?? NSNull(),
                          "directMatch": directCombined.match?.displayText as Any? ?? NSNull(),
                          "directGlyphs": directCombined.acceptedGlyphCandidates.map(\.text),
                          "action": ChordInkRecognitionPolicy.decision(for: combined).action.rawValue,
                          "scope": "diagnostic-only-not-boundary-selection"])
            }
        }

        let lanes = layout.systems.compactMap { system -> (Int, CGRect)? in
            LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system,
                paperFrame: layout.paperFrame(for: system)).map { (system.index, $0) }
        }
        var rowStrokes = [Int: [(index: Int, stroke: InkStroke)]]()
        for visibleIndex in replayed.recognitionVisibleFragmentIndices {
            let stroke = replayed.visibleStrokes[visibleIndex]
            let bounds = CGRect(x: stroke.bounds.minX + Double(source.chordFrame.minX),
                y: stroke.bounds.minY + Double(source.chordFrame.minY),
                width: stroke.bounds.width, height: stroke.bounds.height)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let matches = lanes.compactMap { lane -> (Int, CGFloat)? in
                let expanded = lane.1.insetBy(dx: -8, dy: -10)
                let overlap = expanded.intersection(bounds)
                let area = overlap.isNull ? 0 : overlap.width * overlap.height
                return area > 0 || expanded.contains(center) ? (lane.0, area) : nil
            }
            guard let match = matches.max(by: { $0.1 < $1.1 }) else {
                XCTFail("Visible fragment \(visibleIndex) has no reproduced system lane"); continue
            }
            rowStrokes[match.0, default: []].append((visibleIndex, stroke))
        }
        guard testRun?.failureCount == 0 else { return }
        for systemIndex in rowStrokes.keys.sorted() {
            let row = try XCTUnwrap(rowStrokes[systemIndex])
            let ordered = ChordInkSequentialGrouper.orderedStrokesForRecognition(row)
            let groups = ChordInkSequentialGrouper().groups(for: ordered)
            try emit(["stage": "sequential_row", "systemIndex": systemIndex,
                      "sourceVisibleIndices": row.map(\.index),
                      "usableVisibleIndices": ordered.map(\.index),
                      "filteredVisibleIndices": row.filter { stroke in
                          !ordered.contains(where: { $0.index == stroke.index })
                      }.map(\.index),
                      "groups": groups.map(groupObject)])

            // Log pre-split glyph proposals, never call them final/root truth.
            // Reproduce the sequential recognizer's original stroke order.
            for local in StrokeClusterer().indexedClusters(ordered.map(\.stroke)) {
                let indexed = local.originalIndexes.map { ordered[$0] }.sorted { $0.index < $1.index }
                let cluster = InkCluster(strokes: indexed.map(\.stroke), bounds: local.cluster.bounds)
                let candidates = GestureTemplateRecognizer().rankedCandidates(
                    for: cluster, templates: ChordGlyphTemplateLibrary.initialTemplates, limit: 8)
                let matchingRootGroup = groups.firstIndex { $0.rootBounds == cluster.bounds }
                let previous = matchingRootGroup.flatMap { index in index > 0 ? groups[index - 1] : nil }
                let sourceByIndex = Dictionary(uniqueKeysWithValues: row.map { ($0.index, $0.stroke) })
                let previousEnd = previous?.strokeIndices.compactMap { sourceByIndex[$0]?.timelineEndTimeOffset }.max()
                let clusterStart = indexed.compactMap { $0.stroke.timelineStartTimeOffset }.min()
                let gap = previousEnd.flatMap { end in clusterStart.map { $0 - end } }
                let evidence = ChordInkSequentialRootStartDetector.evidence(in: candidates, cluster: cluster,
                    currentGroupBounds: previous?.rootBounds, previousGlyphWasSlashSeparator: false,
                    currentGroupContentBounds: previous?.bounds, timeGapFromCurrentGroup: gap)
                let timelessEvidence = ChordInkSequentialRootStartDetector.evidence(in: candidates, cluster: cluster,
                    currentGroupBounds: previous?.rootBounds, previousGlyphWasSlashSeparator: false,
                    currentGroupContentBounds: previous?.bounds, timeGapFromCurrentGroup: nil)
                try emit(["stage": "pre_fused_split_glyph_candidates", "systemIndex": systemIndex,
                          "visibleIndices": indexed.map(\.index), "bounds": boundsObject(cluster.bounds),
                          "matchesDeliveredRootBounds": matchingRootGroup != nil,
                          "precedingDeliveredRootBounds": previous.map { boundsObject($0.rootBounds) } as Any? ?? NSNull(),
                          "timeGapFromPrecedingDeliveredGroup": gap as Any? ?? NSNull(),
                          "rootStartProbeAssumesNoPrecedingSlash": true,
                          "rootStartEvidenceWithTiming": evidence.map(rootEvidenceObject) as Any? ?? NSNull(),
                          "rootStartEvidenceWithoutTiming": timelessEvidence.map(rootEvidenceObject) as Any? ?? NSNull(),
                          "candidates": candidates.map { candidate in
                              ["text": candidate.text, "confidence": candidate.confidence,
                               "source": candidate.source.rawValue] as [String: Any]
                          }])
            }

            // Generic whole-row ablation: remove timing from EVERY stroke,
            // retaining all geometry and source indices. No selected merge,
            // expected group, or intended label is supplied.
            let timeless = ordered.map { item -> (index: Int, stroke: InkStroke) in
                var stroke = item.stroke
                stroke.creationTimeOffset = nil
                stroke.points = stroke.points.map { point in
                    var point = point; point.timeOffset = nil; return point
                }
                return (item.index, stroke)
            }
            try emit(["stage": "whole_row_no_timing_ablation", "systemIndex": systemIndex,
                      "groups": ChordInkSequentialGrouper().groups(for: timeless).map(groupObject)])
        }
    }

    private func selectedObject<T: Decodable>(in data: Data, collection: String, id: UUID) throws -> T {
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(root[collection] as? [[String: Any]])
        let selected = entries.filter { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == id }
        XCTAssertEqual(selected.count, 1)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(selected.first)))
    }

    private func groupObject(_ group: ChordInkSequentialGroup) -> [String: Any] {
        ["visibleIndices": group.strokeIndices, "bounds": boundsObject(group.bounds),
         "rootBounds": boundsObject(group.rootBounds), "anchorReason": String(describing: group.anchorReason),
         "rootText": group.rootText as Any? ?? NSNull(),
         "rootConfidence": group.rootConfidence as Any? ?? NSNull(),
         "rootWasModifierLed": group.rootWasModifierLed]
    }

    private func boundsObject(_ bounds: InkBounds) -> [String: Double] {
        ["minX": bounds.minX, "minY": bounds.minY, "maxX": bounds.maxX, "maxY": bounds.maxY]
    }

    private func rootEvidenceObject(_ evidence: ChordInkSequentialRootStartEvidence) -> [String: Any] {
        ["text": evidence.text, "confidence": evidence.confidence, "wasModifierLed": evidence.wasModifierLed]
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private func emit(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        print("CURRENT_SOURCE_TARGET_REPLAY \(String(decoding: data, as: UTF8.self))")
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif

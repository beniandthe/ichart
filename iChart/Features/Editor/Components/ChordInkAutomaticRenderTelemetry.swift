#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// Read-only checks at the automatic transaction boundary. Source identities
/// exist only for this comparison; neither identities nor drawings are encoded.
enum ChordInkAutomaticRenderTelemetry {
    enum Mode: String { case automatic; case reviewedAutomatic = "reviewed_automatic" }

    /// Bounded to the current source revision. Repeated scheduling/refusal for
    /// the same unchanged input is one observation, not repeated incidents.
    struct Admission {
        private var chartID: UUID?
        private var sourceRevision: UInt64?
        private var keys = Set<String>()

        mutating func admit(chartID: UUID, sourceRevision: UInt64, mode: Mode, reason: String) -> Bool {
            if self.chartID != chartID || self.sourceRevision != sourceRevision {
                self.chartID = chartID
                self.sourceRevision = sourceRevision
                keys.removeAll(keepingCapacity: true)
            }
            // Only server-allowlisted reasons reach this helper in production.
            // A hard bound also protects against accidental arbitrary labels.
            guard keys.count < 32 else { return false }
            return keys.insert(mode.rawValue + ":" + reason).inserted
        }

        mutating func reset() {
            chartID = nil
            sourceRevision = nil
            keys.removeAll(keepingCapacity: true)
        }
    }

    static func transactionProperties(
        isEnabled: Bool,
        originalChart: Chart,
        state: ChordPreviewState,
        sourceDrawing: @autoclosure () -> PKDrawing,
        outcome: ChordInkDraftRenderCoordinator.AutomaticOutcome?,
        observedChart: @autoclosure () -> Chart,
        observedDrawing: @autoclosure () -> PKDrawing,
        mode: Mode,
        operationID: UUID = UUID()
    ) -> IChartTelemetryProperties? {
        // In particular, do not enumerate PencilKit points with diagnostics off.
        guard isEnabled else { return nil }
        let source = sourceDrawing()
        var values = properties(for: assessment(originalChart: originalChart, state: state,
            sourceDrawing: source, outcome: outcome,
            observedChart: observedChart(), observedDrawing: observedDrawing()),
            chart: originalChart, mode: mode, operationID: operationID)
        values["source_stroke_count"] = .int(source.strokes.count)
        // These counts describe the intended drawing objects; assessment above
        // is the single authority for exact source validity. Do not enumerate
        // all source points again merely to report inexpensive counts.
        if let outcome {
            values["retained_stroke_count"] = .int(outcome.drawing.strokes.count)
            if source.strokes.count >= outcome.drawing.strokes.count {
                values["consumed_stroke_count"] = .int(source.strokes.count - outcome.drawing.strokes.count)
            }
        } else if outcome == nil {
            values["retained_stroke_count"] = .int(source.strokes.count)
            values["consumed_stroke_count"] = .int(0)
        }
        return values
    }

    static func properties(
        for assessment: LeadSheetInkFeatureContract.Assessment,
        contractID: String = "ink.render_preservation",
        chart: Chart,
        mode: Mode,
        operationID: UUID = UUID(),
        durationMilliseconds: Double? = nil
    ) -> IChartTelemetryProperties {
        var values = LeadSheetInkFeatureContract.properties(for: assessment,
            contractID: contractID, chart: chart, scope: "chords", operationID: operationID)
        values["render_mode"] = .string(mode.rawValue)
        if let durationMilliseconds, durationMilliseconds.isFinite, durationMilliseconds >= 0 {
            values["duration_ms"] = .double(min(durationMilliseconds, 86_400_000))
        }
        return values
    }

    static func assessment(
        originalChart: Chart,
        state: ChordPreviewState,
        sourceDrawing: PKDrawing,
        outcome: ChordInkDraftRenderCoordinator.AutomaticOutcome?,
        observedChart: Chart,
        observedDrawing: PKDrawing
    ) -> LeadSheetInkFeatureContract.Assessment {
        guard let outcome else {
            let unchanged = originalChart == observedChart
                && ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: sourceDrawing, current: observedDrawing)
            return .init(outcome: unchanged ? "protected_rejection" : "violated",
                reason: unchanged ? "render_unresolved" : "render_rejected_mutated",
                expectedCount: sourceDrawing.strokes.count,
                actualCount: observedDrawing.strokes.count, contentMatches: unchanged)
        }

        func failure(_ reason: String, expected: Int, actual: Int) -> LeadSheetInkFeatureContract.Assessment {
            .init(outcome: "violated", reason: reason,
                expectedCount: expected, actualCount: actual, contentMatches: false)
        }
        guard let source = identities(sourceDrawing), let intendedRetained = identities(outcome.drawing),
              let actualRetained = identities(observedDrawing) else {
            return failure("render_retained_source_changed", expected: sourceDrawing.strokes.count,
                actual: observedDrawing.strokes.count)
        }

        let selectedChords = state.draftChords.filter { outcome.consumedDraftIDs.contains($0.id) }
        let selectedBarlines = state.draftBarlines.filter { outcome.consumedDraftIDs.contains($0.id) }
        let selectedEndings = state.draftEndings.filter { outcome.consumedDraftIDs.contains($0.id) }
        let knownIDs = Set(selectedChords.map(\.id) + selectedBarlines.map(\.id) + selectedEndings.map(\.id))
        guard knownIDs == outcome.consumedDraftIDs, !knownIDs.isEmpty else {
            return failure("render_source_missing", expected: sourceDrawing.strokes.count, actual: 0)
        }
        var chordSource: [Identity: Int] = [:]
        for draft in selectedChords {
            guard let drawing = try? PKDrawing(data: draft.drawingData),
                  let fragments = identities(drawing), !fragments.isEmpty else {
                return failure("render_source_missing", expected: sourceDrawing.strokes.count, actual: 0)
            }
            add(fragments, to: &chordSource)
        }
        var ordinarySource: [Identity: Int] = [:]
        var repeatSource: [Identity: Int] = [:]
        var endingSource: [Identity: Int] = [:]
        for barline in selectedBarlines {
            let indices = barline.ownedSourceStrokeIndices
            guard !indices.isEmpty, indices.allSatisfy({ sourceDrawing.strokes.indices.contains($0) }),
                  let fragments = identities(PKDrawing(strokes: indices.sorted().map { sourceDrawing.strokes[$0] })) else {
                return failure("render_source_missing", expected: sourceDrawing.strokes.count, actual: 0)
            }
            if barline.kind.isRepeat { add(fragments, to: &repeatSource) }
            else { add(fragments, to: &ordinarySource) }
        }
        for ending in selectedEndings {
            let indices = ending.sourceStrokeIndices
            guard !indices.isEmpty, indices.allSatisfy({ sourceDrawing.strokes.indices.contains($0) }),
                  let fragments = identities(PKDrawing(strokes: indices.sorted().map { sourceDrawing.strokes[$0] })),
                  !fragments.isEmpty else {
                return failure("render_source_missing", expected: sourceDrawing.strokes.count, actual: 0)
            }
            add(fragments, to: &endingSource)
        }
        var consumed = chordSource
        add(ordinarySource, to: &consumed)
        add(repeatSource, to: &consumed)
        add(endingSource, to: &consumed)
        guard !consumed.isEmpty, let expectedRetained = subtract(consumed, from: source) else {
            return failure("render_source_missing", expected: source.values.reduce(0, +), actual: 0)
        }

        let ids = Set(outcome.result.renderedChordIDs)
        let archivedChords = observedChart.measures.flatMap(\.chordEvents).filter { ids.contains($0.id) }
        var chordReceipts: [Identity: Int] = [:]
        var receiptsValid = archivedChords.count == ids.count && ids.count == selectedChords.count
        for chord in archivedChords {
            guard let data = chord.sourceInkData, let drawing = try? PKDrawing(data: data),
                  let fragments = identities(drawing), !fragments.isEmpty else {
                receiptsValid = false
                continue
            }
            add(fragments, to: &chordReceipts)
        }
        receiptsValid = receiptsValid && chordReceipts == chordSource
        let oldRoadmapIDs = Set(originalChart.roadmapObjects.map(\.id))
        let newRepeats = observedChart.roadmapObjects.filter {
            $0.type == .repeatSpan && !oldRoadmapIDs.contains($0.id)
        }
        var repeatReceipts: [Identity: Int] = [:]
        for repeatSpan in newRepeats {
            guard let data = repeatSpan.sourceInkData, let drawing = try? PKDrawing(data: data),
                  let fragments = identities(drawing), !fragments.isEmpty else {
                receiptsValid = false
                continue
            }
            add(fragments, to: &repeatReceipts)
        }
        // A combined repeat sign is intentionally attached to both spans.
        receiptsValid = receiptsValid && repeatSource.allSatisfy { repeatReceipts[$0.key, default: 0] >= $0.value }
            && repeatReceipts.keys.allSatisfy { repeatSource[$0] != nil }
        let newEndings = observedChart.roadmapObjects.filter {
            $0.type.isEnding && !oldRoadmapIDs.contains($0.id)
        }
        // Ending result IDs identify source drafts, while the committed
        // roadmap objects receive their own IDs. Match the new receipts by
        // exact local source identity instead of confusing these namespaces.
        let renderedEndingIDs = Set(outcome.result.renderedEndingIDs)
        receiptsValid = receiptsValid
            && renderedEndingIDs.count == outcome.result.renderedEndingCount
            && renderedEndingIDs == Set(selectedEndings.map(\.id))
            && newEndings.count == selectedEndings.count
        var endingReceipts: [Identity: Int] = [:]
        for ending in newEndings {
            guard let data = ending.sourceInkData, let drawing = try? PKDrawing(data: data),
                  let fragments = identities(drawing), !fragments.isEmpty else {
                receiptsValid = false
                continue
            }
            add(fragments, to: &endingReceipts)
        }
        receiptsValid = receiptsValid && endingReceipts == endingSource
        let existingChords = Dictionary(grouping: observedChart.measures.flatMap(\.chordEvents), by: \.id)
        let existingRoadmap = Dictionary(grouping: observedChart.roadmapObjects, by: \.id)
        receiptsValid = receiptsValid
            && originalChart.measures.flatMap(\.chordEvents).allSatisfy {
                existingChords[$0.id]?.count == 1 && existingChords[$0.id]?.first?.sourceInkData == $0.sourceInkData
            }
            && originalChart.roadmapObjects.allSatisfy {
                existingRoadmap[$0.id]?.count == 1 && existingRoadmap[$0.id]?.first?.sourceInkData == $0.sourceInkData
            }
        let persistedRetained: [Identity: Int]?
        if let data = observedChart.pageHandwrittenChordData {
            persistedRetained = (try? PKDrawing(data: data)).flatMap(identities)
        } else { persistedRetained = [:] }
        guard receiptsValid, observedChart == outcome.chart else {
            return failure("render_source_missing", expected: consumed.values.reduce(0, +),
                actual: chordReceipts.values.reduce(0, +) + repeatReceipts.values.reduce(0, +)
                    + endingReceipts.values.reduce(0, +) + ordinarySource.values.reduce(0, +))
        }
        // First account for all intended retained source. A leftover consumed
        // fragment is a separate cleanup failure, not missing retained ink.
        let retainsExpected = expectedRetained.allSatisfy { actualRetained[$0.key, default: 0] >= $0.value }
        if intendedRetained != expectedRetained || persistedRetained != expectedRetained || !retainsExpected {
            return failure("render_retained_source_changed", expected: expectedRetained.values.reduce(0, +),
                actual: actualRetained.values.reduce(0, +))
        }
        if actualRetained != expectedRetained {
            if let extra = subtract(expectedRetained, from: actualRetained),
               !extra.isEmpty, extra.allSatisfy({ consumed[$0.key, default: 0] >= $0.value }) {
                return failure("render_consumed_source_remaining", expected: expectedRetained.values.reduce(0, +),
                    actual: actualRetained.values.reduce(0, +))
            }
            return failure("render_retained_source_changed", expected: expectedRetained.values.reduce(0, +),
                actual: actualRetained.values.reduce(0, +))
        }
        return .init(outcome: "passed", reason: "render_complete",
            expectedCount: source.values.reduce(0, +),
            actualCount: consumed.values.reduce(0, +) + actualRetained.values.reduce(0, +), contentMatches: true)
    }

    /// This labels workflow friction only. A protected refusal neither proves
    /// recognition inaccuracy nor claims that source ink was lost.
    static func completionProperties(
        isEnabled: Bool,
        chart: Chart,
        mode: Mode,
        activity: ChordInkAutomaticActivity,
        now: Date,
        isForeground: Bool,
        foregroundObservationDuration: TimeInterval,
        remainingStrokeCount: Int,
        madeProgress: Bool,
        operationID: UUID = UUID()
    ) -> IChartTelemetryProperties? {
        guard isEnabled, isForeground, !madeProgress,
              activity.chartID == chart.id, activity.hasSourceInk,
              activity.phase == .settled, activity.pendingTargetCount == 0,
              remainingStrokeCount > 0,
              foregroundObservationDuration.isFinite, foregroundObservationDuration >= 3,
              let inputAt = activity.inputAt else { return nil }
        let idleDuration = now.timeIntervalSince(inputAt)
        guard idleDuration.isFinite, idleDuration >= 3 else { return nil }
        var reasons = Array(activity.feedback.reasonsByDraftID.values)
        if let reason = activity.feedback.globalReason { reasons.append(reason) }
        // Fixed priority makes a mixed refusal deterministic without exposing
        // target IDs or text. More detailed evidence remains on the device.
        let codes: [(ChordInkAutomaticRenderReason, String)] = [
            (.needsSpace, "automatic_needs_space"), (.placementUnavailable, "automatic_placement_unavailable"),
            (.unrepresentedInk, "automatic_unrepresented_ink"), (.adjacentWriting, "automatic_adjacent_writing"),
            (.noRead, "automatic_no_read"), (.recognitionReview, "automatic_recognition_review")
        ]
        guard let code = codes.first(where: { reasons.contains($0.0) })?.1 else { return nil }
        var values = properties(for: .init(outcome: "protected_rejection", reason: code,
            expectedCount: 0, actualCount: remainingStrokeCount),
            contractID: "ink.automatic_render_completion", chart: chart, mode: mode,
            operationID: operationID, durationMilliseconds: min(idleDuration, foregroundObservationDuration) * 1_000)
        values["retained_stroke_count"] = .int(remainingStrokeCount)
        return values
    }

    /// Counts only completed baseline fragments found in a later drawing.
    /// Appended source is allowed; duplicate baseline fragments retain their
    /// required multiplicity. Exact identities remain local to this call.
    struct SourceContainment: Equatable {
        var expectedCount: Int
        var matchedCount: Int
    }

    static func completedSourceContainment(baseline: PKDrawing, current: PKDrawing) -> SourceContainment? {
        guard let expected = identities(baseline), !expected.isEmpty,
              let actual = identities(current) else { return nil }
        return SourceContainment(expectedCount: expected.values.reduce(0, +),
            matchedCount: expected.reduce(0) { $0 + min($1.value, actual[$1.key, default: 0]) })
    }

    private static func add(_ source: [Identity: Int], to target: inout [Identity: Int]) {
        for (key, count) in source { target[key, default: 0] += count }
    }

    private static func subtract(_ removed: [Identity: Int], from source: [Identity: Int]) -> [Identity: Int]? {
        var result = source
        for (key, count) in removed {
            guard result[key, default: 0] >= count else { return nil }
            let remaining = result[key, default: 0] - count
            if remaining == 0 { result.removeValue(forKey: key) }
            else { result[key] = remaining }
        }
        return result
    }

    private static func identities(_ drawing: PKDrawing) -> [Identity: Int]? {
        var result: [Identity: Int] = [:]
        for stroke in drawing.strokes {
            guard Identity(stroke) != nil else { return nil }
            for fragment in PencilKitInkAdapter.visibleStrokeFragments(from: stroke) {
                guard let identity = Identity(fragment) else { return nil }
                result[identity, default: 0] += 1
            }
        }
        return result
    }

    private struct Identity: Hashable {
        var points: [[Double]]
        var creationTime: Double
        var transform: [Double]
        var randomSeed: UInt32

        init?(_ stroke: PKStroke) {
            guard !stroke.path.isEmpty else { return nil }
            points = stroke.path.map { point in
                let threshold: Double
                if #available(iOS 26.0, *) { threshold = Double(point.threshold) }
                else { threshold = 0 }
                return [Double(point.location.x), Double(point.location.y), Double(point.size.width),
                    Double(point.size.height), Double(point.force), Double(point.opacity),
                    Double(point.azimuth), Double(point.altitude), point.timeOffset,
                    Double(point.secondaryScale), threshold]
            }
            creationTime = stroke.path.creationDate.timeIntervalSinceReferenceDate
            let t = stroke.transform
            transform = [Double(t.a), Double(t.b), Double(t.c), Double(t.d), Double(t.tx), Double(t.ty)]
            randomSeed = stroke.randomSeed
            guard creationTime.isFinite, transform.allSatisfy(\.isFinite),
                  points.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { return nil }
        }
    }
}
#endif

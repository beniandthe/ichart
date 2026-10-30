#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// Read-only observations of the destructive render boundary and coordinate
/// conversion. No source data, identities, or geometry are sent to telemetry.
@MainActor
enum LeadSheetInkFeatureContract {
    struct Assessment: Equatable {
        var outcome: String
        var reason: String
        var expectedCount: Int
        var actualCount: Int
        var expectedPointCount: Int? = nil
        var actualPointCount: Int? = nil
        var contentMatches: Bool? = nil

        var telemetryProperties: IChartTelemetryProperties {
            var values: IChartTelemetryProperties = [
                "outcome": .string(outcome),
                "reason": .string(reason),
                "expected_count": .int(expectedCount),
                "actual_count": .int(actualCount)
            ]
            if let expectedPointCount { values["expected_point_count"] = .int(expectedPointCount) }
            if let actualPointCount { values["actual_point_count"] = .int(actualPointCount) }
            if let contentMatches { values["content_matches"] = .bool(contentMatches) }
            return values
        }
    }

    static func record(
        _ assessment: Assessment,
        contractID: String,
        chart: Chart,
        scope: String,
        operationID: UUID = UUID()
    ) {
        IChartTelemetry.record("feature.contract_checked", properties: properties(
            for: assessment, contractID: contractID, chart: chart, scope: scope, operationID: operationID
        ), chartID: chart.id)
    }

    static func properties(
        for assessment: Assessment,
        contractID: String,
        chart: Chart,
        scope: String,
        operationID: UUID = UUID()
    ) -> IChartTelemetryProperties {
        var properties = assessment.telemetryProperties
        properties["contract_id"] = .string(contractID)
        properties["contract_version"] = .int(1)
        properties["operation_id"] = .string(operationID.uuidString.lowercased())
        properties["operation"] = .string(contractID == "ink.rotation_preservation" ? "rotate" : "render")
        properties["scope"] = .string(scope)
        properties["layout_style"] = .string(chart.layoutStyle.rawValue)
        return properties
    }

    /// A guard that did not reach the canvas cannot establish source equality.
    /// It records a safe rejection or unavailable observation, never ink loss.
    static func recordRenderGuard(chart: Chart, reason: String, unavailable: Bool = false) {
        IChartTelemetry.record("feature.contract_checked", properties: renderGuardProperties(
            chart: chart, reason: reason, unavailable: unavailable
        ), chartID: chart.id)
    }

    static func renderGuardProperties(
        chart: Chart,
        reason: String,
        unavailable: Bool = false,
        operationID: UUID = UUID()
    ) -> IChartTelemetryProperties {
        [
            "contract_id": .string("ink.render_preservation"),
            "contract_version": .int(1),
            "operation_id": .string(operationID.uuidString.lowercased()),
            "operation": .string("render"),
            "outcome": .string(unavailable ? "unknown" : "protected_rejection"),
            "reason": .string(reason),
            "scope": .string("chords"),
            "layout_style": .string(chart.layoutStyle.rawValue)
        ]
    }

    static func renderAssessment(
        originalChart: Chart,
        state: ChordPreviewState,
        sourceDrawing: PKDrawing,
        outcome: ChordInkDraftRenderCoordinator.Outcome,
        remainingCanvasDrawing: PKDrawing
    ) -> Assessment {
        let expectedCount = sourceDrawing.strokes.count
        if !outcome.canConsumeSource {
            let unchanged = originalChart == outcome.chart
                && ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: sourceDrawing, current: remainingCanvasDrawing
                )
            let rejectionReason = outcome.result.didRejectIncompleteSourceCoverage
                ? "render_incomplete_coverage"
                : (outcome.result.unresolvedDraftIDs.isEmpty ? "render_empty" : "render_unresolved")
            return Assessment(
                outcome: unchanged ? "protected_rejection" : "violated",
                reason: unchanged ? rejectionReason : "render_rejected_mutated",
                expectedCount: expectedCount,
                actualCount: remainingCanvasDrawing.strokes.count,
                contentMatches: unchanged
            )
        }

        let chordIDs = Set(outcome.result.renderedChordIDs)
        let committedChords = outcome.chart.measures.flatMap(\.chordEvents).filter { chordIDs.contains($0.id) }
        let originalRoadmapIDs = Set(originalChart.roadmapObjects.map(\.id))
        let newRepeats = outcome.chart.roadmapObjects.filter {
            $0.type == .repeatSpan && !originalRoadmapIDs.contains($0.id)
        }
        var receiptStrokes: [PKStroke] = []
        var receiptsValid = committedChords.count == chordIDs.count
        for data in committedChords.map(\.sourceInkData) + newRepeats.map(\.sourceInkData) {
            guard let data, let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else {
                receiptsValid = false
                continue
            }
            receiptStrokes.append(contentsOf: drawing.strokes)
        }

        // Ordinary barlines intentionally become measure structure without an
        // archived drawing. They are permitted consumption, not lost receipts.
        // Repeat signs must instead be represented by the new repeat receipts.
        let renderedBarlineIDs = Set(outcome.result.renderedBarlineIDs)
        for barline in state.draftBarlines where !barline.kind.isRepeat && renderedBarlineIDs.contains(barline.id) {
            let indices = barline.ownedSourceStrokeIndices
            guard !indices.isEmpty, indices.allSatisfy({ sourceDrawing.strokes.indices.contains($0) }) else {
                receiptsValid = false
                continue
            }
            receiptStrokes.append(contentsOf: indices.sorted().map { sourceDrawing.strokes[$0] })
        }
        let sourceTransferred = receiptsValid && containsVisibleSource(
            sourceDrawing, in: PKDrawing(strokes: receiptStrokes)
        )
        let canvasConsumed = remainingCanvasDrawing.strokes.isEmpty
        return Assessment(
            outcome: sourceTransferred && canvasConsumed ? "passed" : "violated",
            reason: !sourceTransferred ? "render_source_missing"
                : (canvasConsumed ? "render_complete" : "render_canvas_not_cleared"),
            expectedCount: sourceTransferred && !canvasConsumed ? 0 : expectedCount,
            actualCount: sourceTransferred && !canvasConsumed
                ? remainingCanvasDrawing.strokes.count : receiptStrokes.count,
            contentMatches: sourceTransferred
        )
    }

    /// Affine conversion may change coordinates and serialized bytes. Its
    /// measurable contract here is stroke/point conservation and finite output,
    /// not on-screen placement or preservation of a viewport focal point.
    static func rotationAssessment(source: PKDrawing, projected: PKDrawing) -> Assessment {
        let expectedPoints = source.strokes.reduce(0) { $0 + $1.path.count }
        let actualPoints = projected.strokes.reduce(0) { $0 + $1.path.count }
        let reason: String
        if source.strokes.count != projected.strokes.count {
            reason = "rotation_stroke_count_changed"
        } else if expectedPoints != actualPoints {
            reason = "rotation_point_count_changed"
        } else if !hasFiniteGeometry(projected) {
            reason = "rotation_nonfinite_geometry"
        } else {
            reason = "rotation_complete"
        }
        return Assessment(
            outcome: reason == "rotation_complete" ? "passed" : "violated",
            reason: reason,
            expectedCount: source.strokes.count,
            actualCount: projected.strokes.count,
            expectedPointCount: expectedPoints,
            actualPointCount: actualPoints,
            contentMatches: reason == "rotation_complete"
        )
    }

    private static func hasFiniteGeometry(_ drawing: PKDrawing) -> Bool {
        drawing.strokes.allSatisfy { stroke in
            let transform = stroke.transform
            guard [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
                .allSatisfy(\.isFinite) else { return false }
            return stroke.path.allSatisfy { point in
                let projected = point.location.applying(transform)
                return point.location.x.isFinite && point.location.y.isFinite
                    && point.size.width.isFinite && point.size.height.isFinite
                    && projected.x.isFinite && projected.y.isFinite
            }
        }
    }

    /// A combined repeat end/start can legitimately belong to two repeat-span
    /// receipts. Require all original fragments, with their multiplicity, while
    /// allowing this intentional duplication in archived receipt ownership.
    private static func containsVisibleSource(_ source: PKDrawing, in receipts: PKDrawing) -> Bool {
        guard let expected = visibleIdentities(source), let actual = visibleIdentities(receipts) else { return false }
        return expected.allSatisfy { identity, count in (actual[identity] ?? 0) >= count }
    }

    private static func visibleIdentities(_ drawing: PKDrawing) -> [SourceIdentity: Int]? {
        var counts: [SourceIdentity: Int] = [:]
        for stroke in drawing.strokes {
            guard SourceIdentity(stroke) != nil else { return nil }
            for fragment in PencilKitInkAdapter.visibleStrokeFragments(from: stroke) {
                guard let identity = SourceIdentity(fragment) else { return nil }
                counts[identity, default: 0] += 1
            }
        }
        return counts
    }

    /// Matches the source coverage policy's exact local identity: normalization
    /// may change color/type, but cannot change paths, chronology or transforms.
    /// This value is never encoded, persisted, logged, or transmitted.
    private struct SourceIdentity: Hashable {
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
            let value = stroke.transform
            transform = [Double(value.a), Double(value.b), Double(value.c), Double(value.d),
                Double(value.tx), Double(value.ty)]
            randomSeed = stroke.randomSeed
            guard creationTime.isFinite, transform.allSatisfy(\.isFinite),
                  points.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { return nil }
        }
    }
}
#endif

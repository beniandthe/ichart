import Foundation

/// Counts work done in a final review, not recognition accuracy or unique
/// intended chords. Callers retain the original review snapshot locally.
enum ChordWritingWorkflowTelemetry {
    struct ReviewObservation: Equatable {
        var hadSupportedRead: Bool
        var didChangeRead: Bool
    }

    enum RewriteOutcome: String {
        case local
        case page
        case discard
    }

    /// The caller creates a fresh ID for an in-memory writing batch. Never
    /// reuse chart IDs, profile IDs or persisted chord IDs for this property.
    static func batchProperties(batchID: UUID) -> IChartTelemetryProperties {
        ["writing_batch_id": .string(batchID.uuidString.lowercased())]
    }

    static func reviewProperties(
        batchID: UUID,
        observations: [ReviewObservation],
        durationMilliseconds: Double? = nil
    ) -> IChartTelemetryProperties {
        var properties = batchProperties(batchID: batchID)
        properties["reviewed_count"] = .int(observations.count)
        // Edits of an existing supported read and repairs of an unread target
        // are disjoint. Their sum measures final-review effort.
        properties["changed_chord_count"] = .int(observations.filter {
            $0.hadSupportedRead && $0.didChangeRead
        }.count)
        properties["repaired_no_read_count"] = .int(observations.filter {
            !$0.hadSupportedRead
        }.count)
        if let milliseconds = validMilliseconds(durationMilliseconds) {
            properties["review_duration_ms"] = .double(milliseconds)
        }
        return properties
    }

    static func previewTimingProperties(
        batchID: UUID,
        lastStrokeToPreviewMilliseconds: Double?
    ) -> IChartTelemetryProperties {
        var properties = batchProperties(batchID: batchID)
        if let milliseconds = validMilliseconds(lastStrokeToPreviewMilliseconds) {
            properties["last_stroke_to_preview_ms"] = .double(milliseconds)
        }
        return properties
    }

    static func rewriteProperties(
        batchID: UUID,
        outcome: RewriteOutcome
    ) -> IChartTelemetryProperties {
        batchProperties(batchID: batchID).merging([
            "rewrite_outcome": .string(outcome.rawValue)
        ]) { _, value in value }
    }

    /// A missing or clock-reversed start is unknown, not zero latency.
    static func elapsedMilliseconds(from start: Date?, to end: Date) -> Double? {
        guard let start else { return nil }
        return validMilliseconds(end.timeIntervalSince(start) * 1_000)
    }

    private static func validMilliseconds(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...86_400_000).contains(value) else {
            return nil
        }
        return value
    }
}

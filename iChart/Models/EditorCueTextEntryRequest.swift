import Foundation

struct EditorCueTextPlacementPreview: Equatable {
    let measureID: UUID
    let position: CuePosition?
    let beatFraction: Double?

    func snapped(in chart: Chart) -> Self? {
        guard let measure = chart.measure(id: measureID),
              beatFraction == nil || beatFraction?.isFinite == true else { return nil }
        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let fraction = CueText.clampedBeatFraction(beatFraction).map {
            MeasurePlacementGrid.snappedFraction($0, in: meter)
        }
        return Self(measureID: measureID, position: position, beatFraction: fraction)
    }
}

enum EditorCueTextCallerTool: Equatable {
    case select
    case text
}

/// An entry session keeps its destination independent of later canvas selection
/// and keyboard/Scribble changes. Existing cues are always edited by their ID.
struct EditorCueTextEntryRequest: Equatable, Identifiable {
    let id: UUID
    let chartID: UUID
    let placement: EditorCueTextPlacementPreview
    let cueTextID: UUID?
    let horizontalRegion: CueTextHorizontalPlacement.Region?
    let callerTool: EditorCueTextCallerTool
    let initialText: String

    static func adding(in chart: Chart, placement: EditorCueTextPlacementPreview,
                       position: CuePosition, callerTool: EditorCueTextCallerTool) -> Self? {
        guard chart.hasCompletedInitialSetup,
              let destination = EditorCueTextPlacementPreview(measureID: placement.measureID,
                  position: position, beatFraction: placement.beatFraction).snapped(in: chart) else { return nil }
        return Self(id: UUID(), chartID: chart.id, placement: destination, cueTextID: nil, horizontalRegion: nil,
                    callerTool: callerTool, initialText: "")
    }

    static func editing(in chart: Chart, cueTextID: UUID, callerTool: EditorCueTextCallerTool) -> Self? {
        guard chart.hasCompletedInitialSetup, let cue = chart.cueText(id: cueTextID),
              chart.measure(id: cue.anchorMeasureID) != nil else { return nil }
        return Self(id: UUID(), chartID: chart.id,
                    placement: EditorCueTextPlacementPreview(measureID: cue.anchorMeasureID,
                        position: cue.position, beatFraction: cue.beatFraction),
                    cueTextID: cue.id, horizontalRegion: cue.horizontalPlacement?.region,
                    callerTool: callerTool, initialText: cue.text)
    }

    func destinationDescription(in chart: Chart) -> String {
        guard chart.id == chartID, let measure = chart.measure(id: placement.measureID),
              let position = placement.position else { return "Location unavailable" }
        if let margin = horizontalRegion?.marginLabel { return margin }
        let lane: String
        switch position {
        case .above: lane = "Above"
        case .below: lane = "Below"
        case .leadingEdge: lane = "Start of"
        case .trailingEdge: lane = "End of"
        }
        let location = "\(lane) measure \(measure.index)"
        guard horizontalRegion == nil, let fraction = placement.beatFraction else { return location }
        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let beat = MeasurePlacementGrid.beatPosition(for: fraction, in: meter)
        return "\(location) · beat \(beat.displayText)"
    }

    /// A rejected/stale destination leaves the chart and the caller's draft intact.
    func apply(text: String, to chart: inout Chart) -> UUID? {
        guard chart.id == chartID, chart.hasCompletedInitialSetup,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let cueTextID {
            guard let cue = chart.cueText(id: cueTextID), chart.measure(id: cue.anchorMeasureID) != nil,
                  chart.updateCueText(cueTextID, text: text) else { return nil }
            return cueTextID
        }
        guard let position = placement.position else { return nil }
        return chart.addCueText(text, anchorMeasureID: placement.measureID,
            position: position, atFraction: placement.beatFraction)
    }
}

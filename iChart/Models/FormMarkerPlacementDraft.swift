import Foundation

/// A marker and its destination remain local until the user chooses Add.
struct FormMarkerPlacementDraft: Equatable {
    var markerType: RoadmapType
    var measureID: UUID?

    init(chart: Chart, initialMeasureID: UUID?, markerType: RoadmapType = .codaMarker) {
        self.markerType = markerType
        measureID = initialMeasureID.flatMap { chart.measure(id: $0)?.id }
            ?? chart.measures.first?.id
    }

    func canApply(to chart: Chart) -> Bool {
        markerType.isPointMarker && measureID.map { chart.measure(id: $0) != nil } == true
    }

    func targetDescription(in chart: Chart) -> String? {
        guard let measureID, let index = chart.measures.firstIndex(where: { $0.id == measureID }) else {
            return nil
        }
        return "Add \(markerType.editorMenuDisplayText) to measure \(index + 1)"
    }
}

extension RoadmapType {
    var placementMeaning: String {
        switch self {
        case .codaMarker: "Marks the start of the coda."
        case .toCoda: "Jump to the coda when the form calls for it."
        case .segno: "Marks the place to return to for D.S."
        case .ds: "Return to the segno."
        case .dsAlCoda: "Return to the segno, then take To Coda."
        case .dc: "Return to the beginning."
        case .dcAlFine: "Return to the beginning and stop at Fine."
        case .fine: "Marks where to stop after the indicated return."
        case .noChord: "Stop the chord accompaniment here."
        case .repeatSpan: "Repeat a selected range of measures."
        case .ending1, .ending2: "Play this ending on the indicated pass."
        case .vampCount: "Repeat this passage for the indicated count."
        }
    }
}

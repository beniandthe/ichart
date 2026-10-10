import Foundation

// Shared model/layout operation; available to the app and the SwiftPM gate.
enum EditorChordWidthAdjustmentPolicy {
    static let selectionInstruction = "Drag to move · Right handle adjusts width."

    static func canResetWidth(of chord: ChordEvent) -> Bool {
        chord.manualHorizontalScale != nil
            || chord.manualDisplayScale != nil
            || chord.manualDisplayWidth != nil
    }

    @discardableResult
    static func resetWidth(
        for chordEventID: UUID,
        in chart: inout Chart,
        pageSize: CGSize = CGSize(width: 900, height: 1_400)
    ) -> Bool {
        guard let chord = chart.chordEvent(id: chordEventID), canResetWidth(of: chord) else {
            return false
        }
        // Old structured width boxes were positioned from their chosen width.
        // Freeze the existing visible left edge before removing that legacy
        // width, without changing the chord's beat or rhythm placement.
        if chart.layoutStyle != .simpleChordSheet,
           chord.manualDisplayWidth != nil,
           chord.manualVisualLaneFraction == nil {
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            guard let measure = layout.systems.flatMap(\.measures).first(where: {
                $0.sourceMeasureID != nil && $0.chordLayouts.contains { $0.id == chordEventID }
            }), let measureID = measure.sourceMeasureID,
                  let visibleChord = measure.chordLayouts.first(where: { $0.id == chordEventID }),
                  measure.chordBandFrame.width > 0 else { return false }
            let visualFraction = Double(
                (visibleChord.frame.minX - measure.chordBandFrame.minX) / measure.chordBandFrame.width
            )
            guard chart.moveChordEventInCommittedChordLane(
                chordEventID, to: measureID, atFraction: nil,
                visualFraction: visualFraction, preserveMusicalPlacement: true
            ) else { return false }
        }
        chart.setChordEventManualHorizontalScale(nil, for: chordEventID)
        return true
    }
}

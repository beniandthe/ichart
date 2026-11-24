#if canImport(UIKit)
import UIKit
import SwiftUI

enum MeasureLayoutAction: String, CaseIterable, Identifiable, Hashable {
    case startNewRow
    case joinRowAbove
    case moveToRowBelow
    case evenRowWidths
    case mergeWithNext

    var id: String { rawValue }

    func title(isOnlyMeasureInRow: Bool = false) -> String {
        switch self {
        case .startNewRow: "Start New Row"
        case .joinRowAbove: "Join Row Above"
        case .moveToRowBelow: "Move to Row Below"
        case .mergeWithNext: "Merge with Next Measure"
        case .evenRowWidths: isOnlyMeasureInRow ? "Fill Row" : "Even Row Widths"
        }
    }

    func explanation(isOnlyMeasureInRow: Bool = false) -> String {
        switch self {
        case .startNewRow:
            "Make the selected measure the start of a new row."
        case .joinRowAbove:
            "Move this row’s first measure through the selected measure into the row above. Both rows resize evenly."
        case .moveToRowBelow:
            "Move the selected measure and any measures after it in this row into the row below. Both rows resize evenly."
        case .mergeWithNext:
            "Remove the divider after the selected measure, combining it with the next measure."
        case .evenRowWidths:
            isOnlyMeasureInRow
                ? "Expand this single measure to fill its row."
                : "Give the measures in the selected row matching widths."
        }
    }
}

struct MeasureLayoutActionAvailability: Equatable {
    let isEnabled: Bool
    let reason: String?

    static let available = Self(isEnabled: true, reason: nil)
    static func unavailable(_ reason: String) -> Self { .init(isEnabled: false, reason: reason) }
}

/// Uses the existing editing predicates for availability; explanations never
/// grant an operation that the owning Chart or layout policy rejects.
enum MeasureLayoutActionGuidance {
    static func availability(
        for action: MeasureLayoutAction,
        chart: Chart,
        measureID: UUID?,
        pageLayout: LeadSheetPageLayout
    ) -> MeasureLayoutActionAvailability {
        // Start New Row retains its original Chart predicate, including any
        // supported legacy layout, rather than borrowing another action's gate.
        if action == .startNewRow {
            guard let measureID, chart.measure(id: measureID) != nil else {
                return .unavailable("Select a measure first.")
            }
            return chart.canInsertSystemBreak(before: measureID)
                ? .available
                : .unavailable("Select an eligible measure inside a row. Existing row, page and key boundaries stay in place.")
        }
        guard chart.layoutStyle == .simpleChordSheet || chart.layoutStyle == .rhythmSectionSheet else {
            return .unavailable("This layout does not support measure row editing.")
        }
        guard let measureID,
              let selectedIndex = chart.measures.firstIndex(where: { $0.id == measureID }),
              let systemIndex = pageLayout.systems.firstIndex(where: {
                  $0.measures.contains { $0.sourceMeasureID == measureID }
              }) else {
            return .unavailable("Select a measure first.")
        }
        let row = pageLayout.systems[systemIndex]
        let rowIDs = row.measures.compactMap(\.sourceMeasureID)

        switch action {
        case .startNewRow:
            return .unavailable("Select a measure first.")
        case .evenRowWidths:
            let enabled = chart.layoutStyle == .simpleChordSheet ? !rowIDs.isEmpty : rowIDs.count > 1
            return enabled ? .available : .unavailable("This row needs at least two measures to even their widths.")

        case .joinRowAbove, .moveToRowBelow:
            let direction: LeadSheetRowMoveDirection = action == .joinRowAbove ? .above : .below
            switch LeadSheetAdjacentRowMovePolicy.plan(
                for: measureID, direction: direction, in: pageLayout, chart: chart
            ) {
            case .success:
                return .available
            case .failure(.noNeighbor):
                return .unavailable(direction == .above
                    ? "There is no row above this measure."
                    : "There is no row below this measure.")
            case .failure(.pageBreak):
                return .unavailable("A measure cannot move across an explicit page break.")
            case .failure(.keyChange):
                return .unavailable("Keep the row boundary at this key change.")
            case .failure(.measureLimit):
                return .unavailable("The destination row would exceed the measure limit.")
            }

        case .mergeWithNext:
            let selectedInRow = rowIDs.firstIndex(of: measureID)
            let nextInSameRow = selectedInRow.map { rowIDs.indices.contains($0 + 1) } == true
            if chart.canJoinMeasure(after: measureID) && nextInSameRow { return .available }
            guard chart.measures.indices.contains(selectedIndex + 1) else {
                return .unavailable("There is no next measure to merge.")
            }
            guard nextInSameRow else {
                return .unavailable("Select a measure with another measure beside it in the same row.")
            }
            let left = chart.measures[selectedIndex]
            let right = chart.measures[selectedIndex + 1]
            if left.authoringState != .committed {
                return .unavailable("Render or finish this open measure before merging it.")
            }
            if left.barlineAfter != .single {
                return .unavailable("Only an ordinary single barline can be removed by merging.")
            }
            if chart.keyChange(atStartOf: right.id) != nil {
                return .unavailable("The next measure starts a key change.")
            }
            if (left.meterOverride ?? chart.defaultMeter) != (right.meterOverride ?? chart.defaultMeter) {
                return .unavailable("These measures use different time signatures.")
            }
            if chart.layoutStyle == .rhythmSectionSheet,
               chart.hasFreeInkArticulations(in: [left.id, right.id]) {
                return .unavailable("A converted mark uses these measures. Use Restore Ink in Free Ink first.")
            }
            if chart.layoutStyle == .rhythmSectionSheet, left.beatGridPreset != right.beatGridPreset {
                return .unavailable("These measures use different rhythmic grids.")
            }
            return .unavailable("These measures contain rhythm or handwriting that must be preserved separately.")
        }
    }
}

struct MeasureLayoutActionOption: Identifiable {
    let action: MeasureLayoutAction
    let availability: MeasureLayoutActionAvailability
    var isOnlyMeasureInRow = false
    var id: MeasureLayoutAction { action }
}

struct MeasureLayoutActionsView: View {
    let options: [MeasureLayoutActionOption]
    let inLeftMargin: Bool
    let onSelect: (MeasureLayoutAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if inLeftMargin {
                ViewThatFits(in: .vertical) {
                    railButtons
                    ScrollView { railButtons }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 100),
                    spacing: 5)], spacing: 5) {
                    buttons
                }
            }
        }
    }

    private var railButtons: some View {
        VStack(spacing: 5) {
            buttons
        }
    }

    private var buttons: some View {
        ForEach(options) { option in
            let title = option.action.title(isOnlyMeasureInRow: option.isOnlyMeasureInRow)
            IChartTapFeedbackButton {
                onSelect(option.action)
            } label: {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isEnabled && option.availability.isEnabled ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            .disabled(!option.availability.isEnabled)
            .accessibilityLabel(title)
            .accessibilityHint(option.availability.reason
                ?? option.action.explanation(isOnlyMeasureInRow: option.isOnlyMeasureInRow))
            .accessibilityIdentifier("measure-layout-action-\(option.action.rawValue)")
        }
    }
}
#endif

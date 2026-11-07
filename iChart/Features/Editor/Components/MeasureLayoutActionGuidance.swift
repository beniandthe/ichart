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
            "Move this row's first measure to the end of the row above. The remaining measures stay together."
        case .moveToRowBelow:
            "Move this row's last measure to the beginning of the row below."
        case .mergeWithNext:
            "Remove the divider after the selected measure, combining it with the next measure."
        case .evenRowWidths:
            isOnlyMeasureInRow
                ? "Expand this single measure to fill its row."
                : "Give the measures in the selected row matching widths."
        }
    }

    var systemImage: String {
        switch self {
        case .startNewRow: "arrow.down.to.line"
        case .joinRowAbove: "arrow.up.to.line"
        case .moveToRowBelow: "arrow.down.to.line"
        case .mergeWithNext: "rectangle.compress.vertical"
        case .evenRowWidths: "rectangle.split.3x1"
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

        case .moveToRowBelow:
            if LeadSheetMoveMeasureToRowBelowPolicy.plan(for: measureID, in: pageLayout, chart: chart) != nil {
                return .available
            }
            guard rowIDs.last == measureID else {
                return .unavailable("Select the last measure in this row.")
            }
            guard rowIDs.count > 1 else {
                return .unavailable("Keep at least one measure in the current row.")
            }
            guard pageLayout.systems.indices.contains(systemIndex + 1),
                  let nextID = pageLayout.systems[systemIndex + 1].measures.first?.sourceMeasureID else {
                return .unavailable("There is no row below this measure.")
            }
            let nextRow = pageLayout.systems[systemIndex + 1]
            if pageIndex(for: row, in: pageLayout) != pageIndex(for: nextRow, in: pageLayout) {
                return .unavailable("A measure cannot move across a page boundary.")
            }
            if chart.keyChange(atStartOf: measureID) != nil || chart.keyChange(atStartOf: nextID) != nil {
                return .unavailable("Keep the row boundary at this key change.")
            }
            if let cap = chart.layoutStyle.profile.measureDefaults.maximumMeasuresPerSystem,
               nextRow.measures.count + 1 > cap {
                return .unavailable("The row below already has its maximum number of measures.")
            }
            if !chart.canMoveMeasureToRowBelow(measureID, nextRowStartingAt: nextID) {
                return .unavailable("This measure starts a required row or page boundary.")
            }
            return .unavailable("The affected rows need more room to keep every measure at an editable width.")

        case .joinRowAbove:
            let widths = LeadSheetJoinRowEqualizationPolicy.manualLayoutWidths(
                startingAt: measureID, in: pageLayout, chart: chart)
            if chart.measureIDsForJoiningRow(startingAt: measureID) != nil && !widths.isEmpty {
                return .available
            }
            guard rowIDs.first == measureID else {
                return .unavailable("Select the first measure in this row.")
            }
            guard systemIndex > 0 else {
                return .unavailable("There is no row above this measure.")
            }
            if let location = sourceLocation(of: measureID, in: chart), chart.systems[location.systemIndex].startsNewPage {
                return .unavailable("A measure cannot move across a page boundary.")
            }
            if chart.keyChange(atStartOf: measureID) != nil {
                return .unavailable("Keep the row boundary at this key change.")
            }
            if let location = sourceLocation(of: measureID, in: chart),
               location.measureIndex != 0 || chart.systems[location.systemIndex].lineBreakRule != .forced {
                return .unavailable("Select the first measure of a row started with New Row.")
            }
            if chart.measureIDsForJoiningRow(startingAt: measureID) == nil {
                return .unavailable("The row above already has its maximum number of measures.")
            }
            return .unavailable("The row above needs more room to keep every measure at an editable width.")

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

    private static func pageIndex(for system: LeadSheetSystemLayout, in pageLayout: LeadSheetPageLayout) -> Int? {
        pageLayout.pages.first { $0.systemIDs.contains(system.id) }?.index
    }

    private static func sourceLocation(of measureID: UUID, in chart: Chart) -> (systemIndex: Int, measureIndex: Int)? {
        for (systemIndex, system) in chart.systems.enumerated() {
            if let measureIndex = system.measures.firstIndex(where: { $0.id == measureID }) {
                return (systemIndex, measureIndex)
            }
        }
        return nil
    }
}

struct MeasureLayoutSheetRequest: Identifiable {
    let id = UUID()
    let chartID: UUID
    let measureID: UUID?
}

struct MeasureLayoutActionOption: Identifiable {
    let action: MeasureLayoutAction
    let availability: MeasureLayoutActionAvailability
    var isOnlyMeasureInRow = false
    var id: MeasureLayoutAction { action }
}

/// Explanations live outside native menus so they can wrap and scroll at every
/// text size. This sheet reads state; only an available action changes a chart.
struct MeasureLayoutSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let measureNumber: Int?
    let options: [MeasureLayoutActionOption]
    let onSelect: (MeasureLayoutAction) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 7) {
                        Image(systemName: "rectangle.3.group")
                            .font(.title2)
                            .foregroundStyle(IChartInterfaceStyle.sectionAccent)
                            .accessibilityHidden(true)
                        Text("Shape measures and rows")
                            .font(.headline)
                        if let measureNumber {
                            Text("Measure \(measureNumber) selected")
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("measure-layout-context")
                        }
                        Text("Read what each action changes, then tap an available action.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("measure-layout-instruction")
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(16)

                    ForEach(options) { option in
                        MeasureLayoutActionRow(option: option) {
                            guard option.availability.isEnabled else { return }
                            onSelect(option.action)
                            dismiss()
                        }
                        if option.id != options.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Measure Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MeasureLayoutActionRow: View {
    let option: MeasureLayoutActionOption
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onSelect) {
                Label(option.action.title(isOnlyMeasureInRow: option.isOnlyMeasureInRow),
                    systemImage: option.action.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(option.availability.isEnabled ? Color.white : Color.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartInterfaceStyle.actionBlue)
            .disabled(!option.availability.isEnabled)
            .accessibilityIdentifier("measure-layout-action-\(option.action.rawValue)")

            Text(option.action.explanation(isOnlyMeasureInRow: option.isOnlyMeasureInRow))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("measure-layout-explanation-\(option.action.rawValue)")

            if let reason = option.availability.reason {
                Label(reason, systemImage: "info.circle")
                    .font(.subheadline)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("measure-layout-reason-\(option.action.rawValue)")
            }
        }
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}
#endif

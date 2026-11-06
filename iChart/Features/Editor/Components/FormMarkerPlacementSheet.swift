import SwiftUI

struct FormMarkerPlacementSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let chart: Chart
    private let onApply: (RoadmapType, UUID) -> Void
    @State private var draft: FormMarkerPlacementDraft

    init(chart: Chart, initialMeasureID: UUID?, onApply: @escaping (RoadmapType, UUID) -> Void) {
        self.chart = chart
        self.onApply = onApply
        _draft = State(initialValue: FormMarkerPlacementDraft(chart: chart, initialMeasureID: initialMeasureID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Mark the song's form")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    Text("Choose a measure and a marker, then tap Add. Nothing changes until you add it.")
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("form-marker-instruction")
                }

                Section("Place at") {
                    Picker("Measure", selection: $draft.measureID) {
                        ForEach(Array(chart.measures.enumerated()), id: \.element.id) { index, measure in
                            Text("Measure \(index + 1)").tag(Optional(measure.id))
                        }
                    }
                    .accessibilityIdentifier("form-marker-measure")
                }

                Section("Marker") {
                    ForEach(RoadmapType.navigationPointMarkerTypes, id: \.self) { type in
                        Button {
                            draft.markerType = type
                        } label: {
                            VStack(spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(type.editorMenuDisplayText)
                                        .font(.body.weight(.semibold))
                                    if draft.markerType == type {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(IChartInterfaceStyle.actionText)
                                            .accessibilityHidden(true)
                                    }
                                }
                                Text(type.placementMeaning)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft.markerType == type ? [.isSelected] : [])
                        .accessibilityIdentifier("form-marker-option-\(type.rawValue)")
                    }
                }

                if let target = draft.targetDescription(in: chart) {
                    Section {
                        Label(target, systemImage: "signpost.right")
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("form-marker-target")
                        Text("After adding, use Select to move, resize, or delete the marker.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationTitle("Form Markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard draft.canApply(to: chart), let measureID = draft.measureID else { return }
                        onApply(draft.markerType, measureID)
                        dismiss()
                    }
                    .disabled(!draft.canApply(to: chart))
                    .accessibilityIdentifier("form-marker-add")
                }
            }
        }
    }
}

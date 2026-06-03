import SwiftUI

struct ChartHeaderSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var chart: Chart

    @State private var draftTitle: String
    @State private var draftComposerCredit: String
    @State private var draftStyleNote: String
    @State private var draftHeaderInputMode: ChartHeaderInputMode

    init(chart: Binding<Chart>) {
        self._chart = chart
        _draftTitle = State(initialValue: chart.wrappedValue.title)
        _draftComposerCredit = State(initialValue: chart.wrappedValue.composerCredit ?? "")
        _draftStyleNote = State(initialValue: chart.wrappedValue.styleNote ?? "")
        _draftHeaderInputMode = State(initialValue: chart.wrappedValue.headerInputMode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Header Mode") {
                    Picker("Mode", selection: $draftHeaderInputMode) {
                        ForEach(ChartHeaderInputMode.allCases) { mode in
                            Text(mode.displayText)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Chart") {
                    TextField("Title", text: $draftTitle)
                    TextField("Composer / Credit", text: $draftComposerCredit)
                    TextField("Style Note", text: $draftStyleNote)
                }
            }
            .navigationTitle("Header")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        chart.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Untitled Chart"
                            : draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        chart.composerCredit = normalizedText(draftComposerCredit)
                        chart.styleNote = normalizedText(draftStyleNote)
                        chart.setHeaderInputMode(draftHeaderInputMode)
                        chart.updatedAt = .now
                        dismiss()
                    }
                }
            }
        }
    }

    private func normalizedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

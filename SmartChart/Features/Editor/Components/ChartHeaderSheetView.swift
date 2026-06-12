import SwiftUI

struct ChartHeaderSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var chart: Chart

    private enum Field: Hashable {
        case title
        case composerCredit
        case styleNote
    }

    @State private var draftTitle: String
    @State private var draftComposerCredit: String
    @State private var draftStyleNote: String
    @State private var draftHeaderInputMode: ChartHeaderInputMode
    @FocusState private var focusedField: Field?

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
                    headerTextField(
                        title: "Title",
                        text: $draftTitle,
                        field: .title
                    )
                    headerTextField(
                        title: "Composer / Credit",
                        text: $draftComposerCredit,
                        field: .composerCredit
                    )
                    headerTextField(
                        title: "Style Note",
                        text: $draftStyleNote,
                        field: .styleNote
                    )
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
        .task {
            focusedField = .title
        }
    }

    private func headerTextField(
        title: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        HStack(spacing: 10) {
            TextField(title, text: text)
                .focused($focusedField, equals: field)
                .textInputAutocapitalization(.words)

            Button {
                focusedField = field
            } label: {
                Image(systemName: "keyboard")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open keyboard for \(title)")
        }
    }

    private func normalizedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import SwiftUI

enum ChartHeaderTextInputField: CaseIterable, Hashable {
    case title
    case composerCredit
    case styleNote

    var next: ChartHeaderTextInputField? {
        switch self {
        case .title:
            return .composerCredit
        case .composerCredit:
            return .styleNote
        case .styleNote:
            return nil
        }
    }
}

struct ChartHeaderSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var chart: Chart

    @State private var draftTitle: String
    @State private var draftComposerCredit: String
    @State private var draftStyleNote: String
    @FocusState private var focusedField: ChartHeaderTextInputField?

    init(chart: Binding<Chart>) {
        self._chart = chart
        _draftTitle = State(initialValue: chart.wrappedValue.title)
        _draftComposerCredit = State(initialValue: chart.wrappedValue.composerCredit ?? "")
        _draftStyleNote = State(initialValue: chart.wrappedValue.styleNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chart") {
                    VStack(spacing: 0) {
                        headerTextField(
                            title: "Title",
                            text: $draftTitle,
                            field: .title
                        )

                        Divider()

                        headerTextField(
                            title: "Composer / Credit",
                            text: $draftComposerCredit,
                            field: .composerCredit
                        )

                        Divider()

                        headerTextField(
                            title: "Style Note",
                            text: $draftStyleNote,
                            field: .styleNote
                        )
                    }
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
                        applyChanges()
                    }
                }
            }
        }
        .modifier(ChartHeaderSheetPresentationModifier())
    }

    private func headerTextField(
        title: String,
        text: Binding<String>,
        field: ChartHeaderTextInputField
    ) -> some View {
        TextField(title, text: text)
            .focused($focusedField, equals: field)
            .textInputAutocapitalization(.words)
            .submitLabel(field.next == nil ? .done : .next)
            .onSubmit {
                focusedField = field.next
            }
            .frame(minHeight: 52)
            .accessibilityLabel(title)
            .accessibilityHint("Tap to edit with the Apple keyboard and Dictation")
    }

    private func applyChanges() {
        chart.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Chart"
            : draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        chart.composerCredit = normalizedText(draftComposerCredit)
        chart.styleNote = normalizedText(draftStyleNote)
        chart.updatedAt = .now
        dismiss()
    }

    private func normalizedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ChartHeaderSheetPresentationModifier: ViewModifier {
    private let compactHeight: CGFloat = 330

    func body(content: Content) -> some View {
        content
            .presentationDetents([.height(compactHeight)])
            .presentationDragIndicator(.visible)
    }
}

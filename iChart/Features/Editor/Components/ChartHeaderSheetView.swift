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
    @State private var focusedField: ChartHeaderTextInputField?

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
                    .background(IChartTypedSheetScrollSupport())
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Header")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
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
        IChartTypedTextField(
            placeholder: title,
            text: text,
            isFocused: Binding(
                get: { focusedField == field },
                set: { isFocused in
                    if isFocused { focusedField = field }
                    else if focusedField == field { focusedField = nil }
                }
            ),
            autocapitalizationType: .words,
            autocorrectionType: .yes,
            borderStyle: .none,
            onNext: field.next.map { next in
                { requestKeyboard(for: next) }
            }
        )
            .frame(minHeight: 52)
            .accessibilityLabel(title)
            .accessibilityHint("Write with Scribble, or tap the keyboard icon to type")

    }

    private func requestKeyboard(for field: ChartHeaderTextInputField) {
        focusedField = field
    }

    private func applyChanges() {
        focusedField = nil
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
            .presentationDetents([.height(compactHeight), .large])
            .presentationDragIndicator(.visible)
    }
}

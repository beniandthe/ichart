import SwiftUI

/// Optional learning from existing ink, with no preselected or guessed labels.
struct PersonalHandwritingSymbolTeachingView: View {
    @ObservedObject var model: PersonalHandwritingModel
    @State private var draft: PersonalInkSymbolSelectionDraft
    @State private var receipt: PersonalInkSymbolTeachingReview.Receipt?
    @State private var strokeSelection: StrokeSelectionRequest?
    @State private var selectionError: String?
    @State private var pieceRevision = UUID()

    private struct StrokeSelectionRequest: Identifiable {
        let id = UUID()
        let pieceIndex: Int?
        let strokeIndexes: [Int]
    }

    init(model: PersonalHandwritingModel, review: PersonalInkSymbolTeachingReview) {
        self.model = model
        _draft = State(initialValue: .init(review: review))
    }

    private var interactionDisabled: Bool { model.busy || receipt != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Teach from \(draft.review.source.label)").font(.title2.bold())
                Text("Choose ink containing one symbol, then choose its label. Adjust a proposed piece or select a new symbol from the saved strokes. Nothing is learned until you tap Teach.")
                    .font(.callout).foregroundStyle(.secondary)
                PersonalHandwritingExamplePreview(strokes: draft.review.source.recognitionShape?.normalizedRecognitionStrokes ?? draft.review.source.strokes)
                    .frame(height: 96)
                    .accessibilityLabel("Original saved \(draft.review.source.label) handwriting")
                if let error = model.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("personal.symbolTeachingError")
                }
                if let selectionError {
                    Text(selectionError).foregroundStyle(.red)
                        .accessibilityIdentifier("personal.symbolSelectionError")
                }
                VStack(spacing: 12) {
                    ForEach(Array(draft.groups.indices), id: \.self) { index in
                        pieceRow(index)
                    }
                }
                // A transfer can remove a piece and reindex the rest. Rebuild
                // pickers so no previous row retains another piece's label.
                .id(pieceRevision)
                Text(unassignedInkMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("personal.unassignedSymbolInk")
                Button("Select New Symbol") {
                    guard !interactionDisabled else { return }
                    selectionError = nil
                    strokeSelection = .init(pieceIndex: nil, strokeIndexes: [])
                }
                .buttonStyle(.bordered)
                .disabled(interactionDisabled)
                .accessibilityIdentifier("personal.selectNewSymbol")
                if let receipt {
                    Label(receipt.changedSymbolCount == 0 ? "These symbols are already saved" : "Symbol learning saved",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).accessibilityIdentifier("personal.symbolTeachingSaved")
                    Text("\(receipt.previousExampleCount) → \(receipt.savedExampleCount) examples. This does not change charts or past test results. A fresh writing test is needed to check whether recognition improves.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button {
                        guard !interactionDisabled else { return }
                        do {
                            let review = try draft.makeReview()
                            selectionError = nil
                            model.teachSymbols(review, labels: draft.labels) { receipt = $0 }
                        } catch { selectionError = error.localizedDescription }
                    } label: {
                        Text(draft.selectedSymbolCount == 1 ? "Teach 1 Symbol" : "Teach \(draft.selectedSymbolCount) Symbols")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.selectedSymbolCount == 0 || model.busy || !model.profile.isEnabled)
                    .accessibilityIdentifier("personal.confirmSymbols")
                }
                if model.busy { ProgressView("Saving symbols…") }
            }
            .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Teach Symbols").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $strokeSelection) { request in
            PersonalHandwritingStrokeSelectionView(
                strokes: draft.review.source.recognitionInput,
                initialSelection: request.strokeIndexes,
                isDisabled: interactionDisabled,
                errorMessage: selectionError
            ) { indexes in
                guard !interactionDisabled else { return }
                do {
                    try draft.replacePiece(at: request.pieceIndex, withStrokeIndexes: indexes)
                    selectionError = nil
                    pieceRevision = UUID()
                    strokeSelection = nil
                } catch { selectionError = error.localizedDescription }
            }
            .interactiveDismissDisabled(interactionDisabled)
        }
    }

    private var unassignedInkMessage: String {
        let count = draft.unassignedStrokeIndexes.count
        if count == 0 { return "0 unassigned strokes. Only pieces with a chosen label will be taught." }
        return "\(count) unassigned \(count == 1 ? "stroke is" : "strokes are") preserved in the saved example. Select New Symbol to use this ink, or leave it untaught."
    }

    private func pieceRow(_ index: Int) -> some View {
        let strokes = draft.groups[index].map { draft.review.source.recognitionInput[$0] }
        let revision = pieceRevision
        return HStack(spacing: 16) {
            PersonalHandwritingExamplePreview(strokes: PersonalInkShape(strokes: strokes)?.normalizedRecognitionStrokes ?? [])
                .frame(width: 116, height: 88)
                .accessibilityLabel("Ink piece \(index + 1)")
            VStack(alignment: .leading, spacing: 8) {
                Text("Piece \(index + 1)").font(.caption).foregroundStyle(.secondary)
                Picker("Symbol for piece \(index + 1)", selection: labelBinding(forPiece: index)) {
                    Text("Choose symbol…").tag(String?.none)
                    ForEach(PersonalInkSetupCatalog.symbols) { symbol in
                        Text(symbol.title).tag(Optional(symbol.label))
                    }
                }
                .pickerStyle(.menu).labelsHidden()
                .disabled(interactionDisabled)
                .accessibilityIdentifier("personal.symbolLabel.\(index)")
                HStack(spacing: 16) {
                    Button("Adjust Ink") {
                        guard !interactionDisabled, revision == pieceRevision,
                              draft.groups.indices.contains(index) else { return }
                        selectionError = nil
                        strokeSelection = .init(pieceIndex: index, strokeIndexes: draft.groups[index])
                    }
                    .accessibilityIdentifier("personal.adjustSymbolInk.\(index)")
                    Button("Unassign Ink") {
                        guard !interactionDisabled, revision == pieceRevision else { return }
                        do {
                            try draft.removePiece(at: index)
                            selectionError = nil
                            pieceRevision = UUID()
                        } catch { selectionError = error.localizedDescription }
                    }
                    .accessibilityIdentifier("personal.unassignSymbolInk.\(index)")
                }
                .font(.callout).buttonStyle(.borderless)
                .disabled(interactionDisabled)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func labelBinding(forPiece index: Int) -> Binding<String?> {
        let revision = pieceRevision
        return Binding {
            revision == pieceRevision && draft.labels.indices.contains(index) ? draft.labels[index] : nil
        } set: { label in
            guard !interactionDisabled, revision == pieceRevision else { return }
            do {
                try draft.setLabel(label, forPiece: index)
                selectionError = nil
            } catch { selectionError = error.localizedDescription }
        }
    }
}

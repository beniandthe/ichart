import SwiftUI

/// Inspect exactly what was taught before explicitly removing one example.
/// Never guesses a replacement label or edits historical evaluation records.
struct PersonalHandwritingExamplesView: View {
    @ObservedObject var model: PersonalHandwritingModel
    @State private var removal: PersonalInkExample?
    @State private var symbolReview: PersonalInkSymbolTeachingReview?

    var body: some View {
        List {
            Section {
                Text("Check the ink against its saved label. Teach Symbols lets you label individual pieces of a saved chord. Remove accidental examples here. Your charts and past test results stay unchanged.")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = model.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("personal.examplesError")
                }
                if model.busy { ProgressView("Saving…") }
            }
            if model.profile.examples.isEmpty {
                Text("No saved examples").accessibilityIdentifier("personal.noExamples")
            }
            examplesSection(.glyph, title: "Symbols")
            examplesSection(.chord, title: "Whole Chords")
        }
        .navigationTitle("Saved Examples")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.busy)
        .navigationDestination(isPresented: Binding(get: { symbolReview != nil }, set: { if !$0 { symbolReview = nil } })) {
            if let symbolReview { PersonalHandwritingSymbolTeachingView(model: model, review: symbolReview) }
        }
        .alert("Remove this saved example?", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }
        ), presenting: removal) { example in
            Button("Remove \(example.label) Example", role: .destructive) {
                model.removeExample(id: example.id)
                removal = nil
            }
            Button("Cancel", role: .cancel) { removal = nil }
        } message: { example in
            Text("Only this \(example.label) example will be removed. Independently confirmed symbols, other examples, charts, and saved test results will not change.")
        }
    }

    @ViewBuilder
    private func examplesSection(_ kind: PersonalInkExampleKind, title: String) -> some View {
        let examples = model.profile.examples.filter { $0.kind == kind }
        if !examples.isEmpty {
            Section(title) {
                ForEach(examples) { example in
                    HStack(spacing: 14) {
                        PersonalHandwritingExamplePreview(strokes: example.strokes)
                            .frame(width: 124, height: 84)
                            .accessibilityLabel("Handwriting saved as \(example.label)")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(example.label).font(.title3.bold())
                            Text(example.verifiedSymbolOrigin.map { "Symbol confirmed from \($0.chordLabel)" } ?? sourceTitle(example.source))
                                .font(.caption).foregroundStyle(.secondary)
                            if kind == .chord {
                                Button("Teach Symbols") {
                                    do {
                                        symbolReview = try .init(exampleID: example.id, profile: model.profile)
                                        model.error = nil
                                    } catch { model.error = error.localizedDescription }
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("personal.teachSymbols.\(example.id.uuidString)")
                            }
                        }
                        Spacer()
                        Button { removal = example } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                            .buttonStyle(.borderless).tint(.red)
                            .accessibilityLabel("Remove saved \(example.label) example")
                            .accessibilityIdentifier("personal.removeExample.\(example.id.uuidString)")
                    }
                }
            }
        }
    }

    private func sourceTitle(_ source: PersonalInkExampleSource) -> String {
        switch source {
        case .setup: return "Setup"
        case .confirmedReview: return "Confirmed in review"
        case .explicitCorrection: return "Explicit correction"
        case .practice: return "Practice"
        }
    }
}

struct PersonalHandwritingExamplePreview: View {
    let strokes: [InkStroke]

    var body: some View {
        Canvas { context, size in
            // Profile geometry uses the same 48-by-32 space as saved tests.
            let scale = min(size.width / 48, size.height / 32)
            for stroke in strokes {
                var path = Path()
                for (index, point) in stroke.points.enumerated() {
                    let location = CGPoint(x: (size.width - 48 * scale) / 2 + point.x * scale,
                                           y: (size.height - 32 * scale) / 2 + point.y * scale)
                    if stroke.points.count == 1 {
                        context.fill(Path(ellipseIn: CGRect(x: location.x - 1, y: location.y - 1, width: 2, height: 2)),
                                     with: .color(.primary))
                    } else if index == 0 { path.move(to: location) }
                    else { path.addLine(to: location) }
                }
                context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }
}

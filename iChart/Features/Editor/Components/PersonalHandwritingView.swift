import PencilKit
import SwiftUI

/// Owned by the model's serial work queue; never invoked concurrently or from
/// the main actor. The existing recognizer predates Sendable adoption.
private final class PersonalInkComparisonWorker: @unchecked Sendable {
    let recognizer: ChordInkRecognizing
    init(_ recognizer: ChordInkRecognizing) { self.recognizer = recognizer }
    func recognize(_ strokes: [InkStroke]) -> ChordInkRecognitionResult { recognizer.recognize(strokes: strokes) }
}

enum PersonalInkLearning {
    private static let queue = DispatchQueue(label: "com.ichart.personal-handwriting-learning", qos: .utility)

    static func recordReview(text: String, presentedText: String?, drawingData: Data,
                             captureContext: PersonalInkCaptureContext? = nil,
                             store: PersonalInkProfileStore = .shared,
                             evaluationStore: PersonalInkEvaluationStore = .shared,
                             completion: @escaping (String?) -> Void) {
        guard let source = PersonalInkExampleSource.reviewedChoice(acceptedText: text, presentedText: presentedText) else {
            completion(nil)
            return
        }
        record(text: text, drawingData: drawingData, source: source, requiresReviewLearningOptIn: true,
               captureContext: captureContext,
               store: store, evaluationStore: evaluationStore, completion: completion)
    }

    static func record(text: String, drawingData: Data, source: PersonalInkExampleSource,
                       requiresReviewLearningOptIn: Bool = false,
                       captureContext: PersonalInkCaptureContext? = nil,
                       store: PersonalInkProfileStore = .shared,
                       evaluationStore: PersonalInkEvaluationStore = .shared,
                       completion: @escaping (String?) -> Void) {
        let profile = store.snapshot().profile
        let capturedGeneration = profile.generation
        guard !evaluationStore.isCapturing, profile.isEnabled,
              profile.learnsFromReviews || (source == .explicitCorrection && !requiresReviewLearningOptIn)
        else { completion(nil); return }
        queue.async {
            do {
                let strokes = try PencilKitInkAdapter.inkStrokes(from: drawingData)
                try store.update { profile in
                    // A reset or opt-out while this operation waited wins.
                    guard !evaluationStore.isCapturing, profile.isEnabled,
                          profile.generation == capturedGeneration,
                          profile.learnsFromReviews || (source == .explicitCorrection && !requiresReviewLearningOptIn)
                    else { return }
                    try profile.learn(strokes: strokes, label: text, kind: .chord, source: source,
                                      captureContext: captureContext)
                }
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error.localizedDescription) }
            }
        }
    }
}

@MainActor
final class PersonalHandwritingModel: ObservableObject {
    struct Comparison {
        let baseline: String?
        let personalized: String?
        let usedPersonalExample: Bool
        let knownInk: Bool
        let milliseconds: Double
        let strokes: [InkStroke]
        var intendedText: String?
        var captureContext: PersonalInkCaptureContext? = nil
    }
    @Published var profile: PersonalInkProfile
    @Published var busy = false
    @Published var error: String?
    @Published var comparison: Comparison?
    @Published var scoredCount = 0
    @Published var baselineCorrect = 0
    @Published var personalizedCorrect = 0
    @Published var learnedComparison = false
    private let store: PersonalInkProfileStore
    private let evaluationStore: PersonalInkEvaluationStore
    private let recognitionWorker: PersonalInkComparisonWorker
    // Local UI intake lifetime, not authenticated writer/acquisition evidence.
    private let intakeSessionID = UUID()
    private let queue: DispatchQueue

    // A supplied work queue must be serial, matching the default queue.
    init(store: PersonalInkProfileStore = .shared, recognizer: ChordInkRecognizing = ChordInkMaximumTrustRecognizer(),
         evaluationStore: PersonalInkEvaluationStore = .shared, workQueue: DispatchQueue? = nil) {
        self.store = store
        self.evaluationStore = evaluationStore
        self.recognitionWorker = PersonalInkComparisonWorker(recognizer)
        self.queue = workQueue ?? DispatchQueue(label: "com.ichart.personal-handwriting", qos: .userInitiated)
        profile = store.snapshot().profile
        error = store.loadError
    }

    func update(_ edit: @escaping (inout PersonalInkProfile) throws -> Void,
                completion: @escaping () -> Void = {}) {
        guard !busy else { return }
        guard !evaluationStore.isCapturing else {
            error = PersonalInkEvaluationError.activeRun.localizedDescription
            return
        }
        busy = true
        error = nil
        let store = store, evaluation = evaluationStore
        queue.async {
            let result = Result {
                try store.update { profile in
                    // Capture may have started while this edit waited in the queue.
                    guard !evaluation.isCapturing else { throw PersonalInkEvaluationError.activeRun }
                    try edit(&profile)
                }
                return store.snapshot().profile
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let profile): self.profile = profile; completion()
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    func reloadProfile() {
        guard !busy else { return }
        profile = store.snapshot().profile
        error = store.loadError
    }

    func removeExample(id: UUID) {
        update { $0.removeExample(id: id) }
    }

    func teachSymbols(_ review: PersonalInkSymbolTeachingReview, labels: [String?],
                      completion: @escaping (PersonalInkSymbolTeachingReview.Receipt) -> Void) {
        guard !busy else { return }
        guard !evaluationStore.isCapturing else {
            error = PersonalInkEvaluationError.activeRun.localizedDescription
            return
        }
        busy = true
        error = nil
        let store = store, evaluation = evaluationStore
        queue.async {
            let result = Result<PersonalInkSymbolTeachingReview.Receipt, Error> {
                var receipt: PersonalInkSymbolTeachingReview.Receipt?
                try store.update { profile in
                    // Recheck after queueing: capture/reset/opt-out wins.
                    guard !evaluation.isCapturing else { throw PersonalInkEvaluationError.activeRun }
                    receipt = try review.teach(labels: labels, profile: &profile)
                }
                guard let receipt else { throw PersonalInkSymbolTeachingReview.Failure.invalidSelection }
                return receipt
            }
            let current = store.snapshot().profile
            DispatchQueue.main.async {
                self.profile = current
                self.busy = false
                switch result {
                case .success(let receipt): completion(receipt)
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    func learn(_ drawing: PKDrawing, label: String, kind: PersonalInkExampleKind,
               source: PersonalInkExampleSource, completion: @escaping () -> Void) {
        let context = PersonalInkCaptureContext(sessionID: intakeSessionID,
            origin: source == .setup ? .setup : .practice)
        update({ profile in
            try profile.learn(strokes: PencilKitInkAdapter.inkStrokes(from: drawing), label: label, kind: kind,
                              source: source, captureContext: context)
            profile.isEnabled = true
        }, completion: completion)
    }

    func compare(_ drawing: PKDrawing) {
        guard !busy else { return }
        busy = true
        error = nil
        comparison = nil
        learnedComparison = false
        let snapshot = store.snapshot()
        let worker = recognitionWorker
        let context = PersonalInkCaptureContext(sessionID: intakeSessionID, origin: .practice)
        queue.async {
            let strokes = PencilKitInkAdapter.inkStrokes(from: drawing)
            guard PersonalInkShape(strokes: strokes) != nil else {
                DispatchQueue.main.async { self.busy = false; self.error = PersonalInkError.invalidInk.localizedDescription }
                return
            }
            let baseline = worker.recognize(strokes)
            let start = Date()
            let personalized = snapshot.applying(to: baseline, strokes: strokes, previewEvenIfDisabled: true)
            let elapsed = Date().timeIntervalSince(start) * 1000
            let baselineText = baseline.match?.displayText ?? ChordInkRenderResolutionPolicy.candidateTexts(for: baseline).first
            let selection = ChordInkRenderResolutionPolicy.personalSelection(for: personalized)
            let result = Comparison(baseline: baselineText,
                                    personalized: selection.text,
                                    usedPersonalExample: selection.prefersPersonal,
                                    knownInk: snapshot.wasAlreadyLearned(strokes: strokes),
                                    milliseconds: elapsed, strokes: strokes, captureContext: context)
            DispatchQueue.main.async { self.comparison = result; self.busy = false }
        }
    }

    func score(intendedText: String) {
        guard var comparison, comparison.intendedText == nil,
              let match = ChordRecognitionCompendium.match(intendedText) else {
            error = PersonalInkError.invalidLabel.localizedDescription
            return
        }
        comparison.intendedText = match.displayText
        self.comparison = comparison
        if !comparison.knownInk {
            scoredCount += 1
            if comparison.baseline == match.displayText { baselineCorrect += 1 }
            if comparison.personalized == match.displayText { personalizedCorrect += 1 }
        }
    }

    func learnComparison() {
        guard let comparison, let intended = comparison.intendedText, !learnedComparison else { return }
        update({ profile in
            try profile.learn(strokes: comparison.strokes, label: intended, kind: .chord,
                              source: .explicitCorrection, captureContext: comparison.captureContext)
            profile.isEnabled = true
        }, completion: { self.learnedComparison = true })
    }
}

struct PersonalHandwritingView: View {
    var chartID = UUID()
    var layoutStyle: ChartLayoutStyle = .simpleChordSheet
    var hasChordInk = false
    var startsWithEvaluation = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PersonalHandwritingModel()
    @State private var stage = 0 // overview, setup, fresh comparison
    @State private var promptIndex = 0
    // Freeze the chosen plan until it finishes: saving a missing symbol must
    // not shift the next prompt underneath the current drawing.
    @State private var setupPrompts = PersonalInkSetupCatalog.quickSetup
    @State private var setupReturnStage = 2
    @State private var drawing = PKDrawing()
    @State private var clearID = UUID()
    @State private var intendedText = ""
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = model.error {
                        Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("personal.error")
                    }
                    switch stage {
                    case 1: setup
                    case 2: PersonalHandwritingEvaluationView(chartID: chartID, style: layoutStyle, hasChordInk: hasChordInk) { dismiss() }
                    default: overview
                    }
                    if model.busy { ProgressView("Working…").frame(maxWidth: .infinity) }
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("My Handwriting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if stage != 0 { Button("Back") { stage = 0; clear() }.disabled(model.busy) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.disabled(model.busy)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { if startsWithEvaluation { stage = 2 } }
        .onChange(of: stage) { stage in if stage == 0 { model.reloadProfile() } }
        .interactiveDismissDisabled(model.busy)
        .confirmationDialog("Reset your handwriting profile? Your charts and ink will not change.", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Profile", role: .destructive) { model.update { $0 = PersonalInkProfile() } }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make recognition more personal").font(.title2.bold())
            Text("Show iChart how you write, then compare it with the standard recognizer. This is an experimental, example-based profile—not a guarantee of accurate reads.")
                .foregroundStyle(.secondary)
            Text("Trusted standard reads stay in front. Personal alternatives remain available for review; explicit corrections can help ambiguous or missing reads. Personal matches never gain automatic trust.")
                .font(.callout).foregroundStyle(.secondary)
            Label("Private on this iPad. No uploads.", systemImage: "lock.shield")
                .font(.callout)
            Text("\(model.profile.examples.count) saved examples").font(.headline)
                .accessibilityIdentifier("personal.exampleCount")
            Text("\(PersonalInkSetupCatalog.symbols.count - missingSymbols.count) of \(PersonalInkSetupCatalog.symbols.count) supported symbols have examples. This is coverage, not an accuracy score.")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("personal.symbolCoverage")
            HStack(alignment: .top) {
                Button(setupButtonTitle) {
                    beginSetup(PersonalInkSetupCatalog.suggestedSetup(for: model.profile))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("personal.startSetup")
                Menu {
                    Button("Quick setup") { beginSetup(PersonalInkSetupCatalog.quickSetup) }
                    if !missingSymbols.isEmpty {
                        Button("Missing symbols (\(missingSymbols.count))") { beginSetup(missingSymbols) }
                    }
                    Menu("Choose one symbol") {
                        ForEach(PersonalInkSetupCatalog.symbols) { prompt in
                            Button(prompt.title) { beginSetup([prompt]) }
                        }
                    }
                } label: {
                    Label("Choose Examples", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("personal.chooseExamples")
            }
            .disabled(model.busy)
            Button("Saved Chart Test") { stage = 2; clear() }
                .buttonStyle(.bordered).accessibilityIdentifier("personal.startTest")
            NavigationLink("Review Saved Examples") {
                PersonalHandwritingExamplesView(model: model)
            }
            .disabled(model.profile.examples.isEmpty)
            .accessibilityIdentifier("personal.reviewExamples")
            Divider()
            Toggle("Use my profile in charts", isOn: Binding(get: { model.profile.isEnabled }, set: { enabled in
                model.update { $0.isEnabled = enabled }
            }))
            .disabled(model.profile.examples.isEmpty || model.busy)
            .accessibilityIdentifier("personal.enabled")
            Toggle("Learn from chords I confirm", isOn: Binding(get: { model.profile.learnsFromReviews }, set: { enabled in
                model.update { $0.learnsFromReviews = enabled }
            }))
            .disabled(model.busy)
            Text("When enabled, chord review saves the ink and the chord you approve. Changing the proposed chord records a correction; accepting it records a confirmation. Turning this off stops both kinds of review learning. Automatic guesses never teach the profile. Works in both chart styles without rewriting existing chart content.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Reset Profile", role: .destructive) { confirmsReset = true }
                .disabled(model.busy || (model.profile.examples.isEmpty && model.error == nil))
                .accessibilityIdentifier("personal.reset")
        }
        .disabled(model.busy)
    }

    private var setup: some View {
        let prompt = setupPrompts[promptIndex]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Example \(promptIndex + 1) of \(setupPrompts.count)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Finish Early") { stage = setupReturnStage; clear() }.disabled(model.busy)
            }
            ProgressView(value: Double(promptIndex), total: Double(setupPrompts.count))
            Text("Write \(prompt.title)").font(.largeTitle.bold()).accessibilityIdentifier("personal.prompt")
            Text("Use your normal handwriting and size. Write one example, then confirm the label. You can skip any card.")
                .font(.callout).foregroundStyle(.secondary)
            inkCanvas
            HStack {
                Button("Clear") { clear() }.buttonStyle(.bordered)
                Button("Skip") { advancePrompt() }.buttonStyle(.bordered)
                Spacer()
                Button("Save \(prompt.title)") {
                    model.learn(drawing, label: prompt.label, kind: prompt.kind, source: .setup) { advancePrompt() }
                }
                .buttonStyle(.borderedProminent).disabled(drawing.strokes.isEmpty)
                .accessibilityIdentifier("personal.saveExample")
            }
            .disabled(model.busy)
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Does it help on fresh ink?").font(.title2.bold())
            Text("Write any chord—not a copy of the setup ink. Compare first, then tell us what you meant. Testing alone does not train the profile.")
                .font(.callout).foregroundStyle(.secondary)
            inkCanvas
            HStack {
                Button("New Chord") { clear() }.buttonStyle(.bordered)
                Spacer()
                Button("Compare") { model.compare(drawing) }
                    .buttonStyle(.borderedProminent)
                    .disabled(drawing.strokes.isEmpty || model.comparison != nil)
                    .accessibilityIdentifier("personal.compare")
            }.disabled(model.busy)
            if let comparison = model.comparison {
                HStack(spacing: 16) {
                    resultCard("Standard", text: comparison.baseline)
                    resultCard("With my profile", text: comparison.personalized)
                }.accessibilityIdentifier("personal.results")
                Text(comparison.usedPersonalExample ? "Personal example matched · review before rendering" : "No close personal match; standard result kept")
                    .font(.footnote).foregroundStyle(.secondary)
                if comparison.knownInk {
                    Text("This ink matches a saved example. It will not count as a fresh test.").font(.footnote).foregroundStyle(.orange)
                }
                if comparison.intendedText == nil {
                    HStack {
                        TextField("What chord did you mean?", text: $intendedText)
                            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("personal.intended")
                        Button("Record Result") { model.score(intendedText: intendedText) }
                            .buttonStyle(.bordered).disabled(intendedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("personal.score")
                    }
                } else {
                    Label("Recorded as \(comparison.intendedText ?? "")", systemImage: "checkmark.circle")
                    Button(model.learnedComparison ? "Example saved—try another fresh chord" : "Teach This Example") { model.learnComparison() }
                        .buttonStyle(.bordered).disabled(model.learnedComparison || model.busy)
                        .accessibilityIdentifier("personal.teachTest")
                }
                Text("Personal lookup: \(comparison.milliseconds, specifier: "%.0f") ms. Shape-match distance is not a confidence percentage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.scoredCount > 0 {
                Text("This session · \(model.scoredCount) fresh tests\nStandard: \(model.baselineCorrect) correct · Personal: \(model.personalizedCorrect) correct")
                    .font(.callout.weight(.medium)).accessibilityIdentifier("personal.scorecard")
            }
        }
    }

    private var inkCanvas: some View {
        PersonalHandwritingPad(drawing: $drawing, clearID: clearID,
                               enabled: !model.busy && (stage != 2 || model.comparison == nil))
    }

    private func resultCard(_ title: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text ?? "No read").font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func clear() {
        clearID = UUID(); drawing = PKDrawing(); model.comparison = nil; model.learnedComparison = false; intendedText = ""
    }

    private func advancePrompt() {
        clear()
        if promptIndex + 1 < setupPrompts.count { promptIndex += 1 } else { stage = setupReturnStage }
    }

    private var missingSymbols: [PersonalInkSetupCatalog.Prompt] {
        PersonalInkSetupCatalog.missingSymbols(in: model.profile)
    }

    private var setupButtonTitle: String {
        if model.profile.examples.isEmpty { return "Learn My Handwriting" }
        if !missingSymbols.isEmpty { return "Learn Missing Symbols (\(missingSymbols.count))" }
        return "Add Handwriting Examples"
    }

    private func beginSetup(_ prompts: [PersonalInkSetupCatalog.Prompt]) {
        guard !prompts.isEmpty, !model.busy else { return }
        setupPrompts = prompts
        setupReturnStage = prompts == PersonalInkSetupCatalog.quickSetup ? 2 : 0
        promptIndex = 0
        clear()
        stage = 1
    }
}

struct PersonalHandwritingPad: View {
    @Binding var drawing: PKDrawing
    let clearID: UUID
    let enabled: Bool

    var body: some View {
        PersonalHandwritingCanvas(drawing: $drawing, clearID: clearID, enabled: enabled)
            .frame(height: 180)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.3)).allowsHitTesting(false))
            .accessibilityLabel("Write with Apple Pencil here")
            .accessibilityIdentifier("personal.canvas")
    }

}

private struct PersonalHandwritingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let clearID: UUID
    let enabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isScrollEnabled = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.bounces = false
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
        canvas.drawingGestureRecognizer.allowedTouchTypes = [
            UITouch.TouchType.direct.rawValue, UITouch.TouchType.pencil.rawValue,
            UITouch.TouchType.indirectPointer.rawValue
        ].map { NSNumber(value: $0) }
        #else
        canvas.drawingPolicy = .pencilOnly
        #endif
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.isUserInteractionEnabled = enabled
        if context.coordinator.clearID != clearID {
            context.coordinator.clearID = clearID
            canvas.drawing = PKDrawing()
            canvas.undoManager?.removeAllActions()
        }
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PersonalHandwritingCanvas
        var clearID: UUID
        init(_ parent: PersonalHandwritingCanvas) { self.parent = parent; clearID = parent.clearID }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { parent.drawing = canvasView.drawing }
    }
}

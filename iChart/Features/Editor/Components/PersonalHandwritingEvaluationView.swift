import SwiftUI

enum PersonalInkEvaluationCapture {
    static func recordSource(_ source: ChordInkRecognitionPreparedSource, requestID: UUID,
                             inkRevision: UInt64, runID: UUID,
                             store: PersonalInkEvaluationStore = .shared) {
        store.captureSource(runID: runID,
            expectsPredictions: !source.ownership.targetGroups.isEmpty, makeSnapshot: {
                try PersonalInkEvaluationSourceSnapshot(requestID: requestID, inkRevision: inkRevision,
                    normalizedDrawingData: source.normalizedDrawingData,
                    chordFrame: source.chordFrame, pageBounds: source.pageBounds,
                    pages: source.pageLayout?.pages.map {
                        .init(index: $0.index, frame: $0.frame)
                    } ?? [],
                    measures: source.pageLayout?.systems.flatMap(\.measures).map {
                        .init(measureID: $0.id,
                            targetMeasureID: $0.chordInkTargetMeasureID ?? $0.sourceMeasureID,
                            index: $0.index, chordWritingFrame: $0.chordWritingFrame)
                    } ?? [],
                    visibleStrokes: source.visibleStrokes,
                    recognitionVisibleFragmentIndices: source.recognitionVisibleFragmentIndices,
                    ownership: source.ownership, outcome: source.outcome)
            })
    }

    static func record(_ payloads: [ChordInkRecognitionProposalPayload], chart: Chart,
                       bindsSource: Bool = false,
                       store: PersonalInkEvaluationStore = .shared) {
        guard let context = store.context(chartID: chart.id) else { return }
        // Do not replace the test with callbacks from recognition started before
        // the test, or from another profile/run. An empty live preview represents
        // missing targeting/erased ink and is retained as such, not hidden.
        guard payloads.allSatisfy({ $0.evaluationPrediction?.runID == context.runID }) else { return }
        let requestID = payloads.first?.requestID
        guard payloads.allSatisfy({ $0.requestID == requestID }) else { return }
        let sourceRequestID = bindsSource ? requestID : nil
        store.capture(runID: context.runID, sourceRequestID: sourceRequestID, makeRecords: {
            payloads.enumerated().map { ordinal, payload in
                let prediction = payload.evaluationPrediction!
                let shape = PersonalInkShape(strokes: payload.strokes)
                let normalized = shape?.normalizedStrokes ?? []
                return PersonalInkEvaluationRecord(
                    measureIndex: chart.measure(id: payload.target.measureID)?.index ?? -1,
                    fraction: payload.target.fraction, strokes: normalized,
                    fingerprint: PersonalInkEvaluationStore.fingerprint(strokes: shape == nil ? payload.strokes : normalized),
                    baseline: prediction.baseline, personalized: prediction.personalized,
                    baselineAction: prediction.baselineAction, personalizedAction: prediction.personalizedAction,
                    knownInk: prediction.knownInk, recognitionMilliseconds: payload.timing.recognitionMilliseconds,
                    totalMilliseconds: payload.timing.recognitionTotalMilliseconds, cacheHit: payload.timing.cacheHit,
                    groupingIssue: normalized.isEmpty, personalSuggestion: prediction.personalSuggestion,
                    personalArbitration: prediction.personalArbitration, measureID: payload.target.measureID,
                    visualOrder: payload.visualOrder,
                    recognitionStrokes: payload.strokes,
                    requiresEditReview: payload.result.requiresEditReview,
                    baselineRecognitionAction: prediction.baselineRecognitionAction,
                    sourceRequestID: sourceRequestID, targetOrdinal: bindsSource ? ordinal : nil)
            }
        })
    }
}

@MainActor
final class PersonalHandwritingEvaluationModel: ObservableObject {
    @Published var journal = PersonalInkEvaluationJournal()
    @Published var error: String?
    @Published var busy = false
    @Published var profile: PersonalInkProfile
    @Published var teachingFailure: String?
    let store: PersonalInkEvaluationStore
    let profileStore: PersonalInkProfileStore
    init(store: PersonalInkEvaluationStore = .shared, profileStore: PersonalInkProfileStore = .shared) {
        self.store = store; self.profileStore = profileStore
        profile = profileStore.snapshot().profile
        reload()
    }
    func reload() {
        let saved = store.snapshot(); journal = saved.journal
        profile = profileStore.snapshot().profile
        error = saved.error ?? profileStore.loadError
    }
    func teach(runID: UUID, recordID: UUID? = nil) {
        teachingFailure = nil
        perform { completion in
            let finished: (String?) -> Void = { [weak self] error in
                completion(error)
                self?.teachingFailure = error
            }
            if let recordID {
                store.teach(runID: runID, recordID: recordID, profileStore: profileStore, completion: finished)
            } else {
                store.teachLabeledExamples(runID: runID, profileStore: profileStore, completion: finished)
            }
        }
    }
    func perform(_ operation: (@escaping (String?) -> Void) -> Void, then: @escaping () -> Void = {}) {
        guard !busy else { return }
        busy = true
        operation { [weak self] error in
            guard let self else { return }
            self.busy = false; self.reload(); self.error = error ?? self.error
            if error == nil { then() }
        }
    }
}

struct PersonalHandwritingEvaluationView: View {
    let chartID: UUID
    let style: ChartLayoutStyle
    let hasChordInk: Bool
    let returnToChart: () -> Void
    @StateObject private var model = PersonalHandwritingEvaluationModel()
    @State private var selectedRunID: UUID?
    @State private var phase = PersonalInkEvaluationRun.Phase.beforeCorrections
    @State private var expectedCount = ""
    @State private var slowInk = false
    @State private var unexpectedChanges = false
    @State private var cancelConfirmation = false
    @State private var teachingConfirmation = false
    @State private var teachingRun: PersonalInkEvaluationRun?

    private var currentRun: PersonalInkEvaluationRun? {
        if let selectedRunID { return model.journal.runs.first { $0.id == selectedRunID } }
        return model.journal.runs.last { $0.chartID == chartID && ($0.status == .capturing || $0.status == .labeling) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved Chart Test").font(.title2.bold())
            Text("Local test v3 · results stay on this iPad · chart sync is unchanged")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("evaluation.error") }
            if let run = currentRun {
                runView(run)
            } else {
                startView
            }
            if model.busy { ProgressView("Saving…") }
            if !model.journal.runs.isEmpty {
                Divider()
                Text("Saved runs").font(.headline)
                ForEach(model.journal.runs.reversed()) { run in
                    Button {
                        selectedRunID = run.id
                        expectedCount = run.expectedChordCount.map(String.init) ?? ""
                        slowInk = run.inkFeltSlow ?? false
                        unexpectedChanges = run.unexpectedChartChanges ?? false
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(ChartLayoutStyle(rawValue: run.style)?.displayText ?? run.style) · \(phaseTitle(run.phase))")
                            Text("\(run.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(run.status.rawValue) · \(run.records.count) captured")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.bordered)
                }
                if currentRun != nil {
                    Button("Prepare another test") { selectedRunID = nil; expectedCount = "" }
                        .disabled(model.journal.activeRun != nil || currentRun?.status == .labeling)
                }
            }
        }
        .disabled(model.busy)
        .onAppear { model.reload() }
        .confirmationDialog("End this capture without scoring? The captured data is kept and charts are unchanged.", isPresented: $cancelConfirmation, titleVisibility: .visible) {
            if let run = currentRun {
                Button("End Without Scoring", role: .destructive) {
                    model.perform { model.store.cancel(runID: run.id, completion: $0) }
                }
            }
        }
        .confirmationDialog("Teach all labeled examples from this run?", isPresented: $teachingConfirmation,
                            titleVisibility: .visible, presenting: teachingRun) { run in
            Button("Teach \(run.teachableRecords.count) examples") {
                model.teach(runID: run.id)
            }
        } message: { _ in
            Text("Use the labels you supplied to update and enable your local handwriting profile. Incorrectly grouped targets are skipped. Old scores and charts stay unchanged; nothing is uploaded.")
        }
        .alert("Learning was not completed", isPresented: Binding(
            get: { model.teachingFailure != nil },
            set: { if !$0 { model.teachingFailure = nil } }
        )) {
            Button("OK", role: .cancel) { model.teachingFailure = nil }
        } message: {
            Text(model.teachingFailure ?? "Keep your saved results and try again before another test.")
        }
    }

    private var startView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Use a blank test chart—not existing song ink. Start capture, close this panel, and use Write & Render to write the requested set of fresh complete chords across a few measures. Include a full row at normal speed.")
            Text("Do not render, confirm, transpose, or change chart style during capture. When finished writing, wait for previews to settle, reopen this screen, then stop and label. If something goes wrong, record it; do not rewrite just to get a better score.")
                .font(.callout).foregroundStyle(.secondary)
            Text("The profile is frozen during capture. The base recognizer is unchanged. Stopping, scoring, and missing reads do not train anything.")
                .font(.callout)
            Picker("Test phase", selection: $phase) {
                Text("Before learning").tag(PersonalInkEvaluationRun.Phase.beforeCorrections)
                Text("After learning").tag(PersonalInkEvaluationRun.Phase.afterCorrections)
            }.pickerStyle(.segmented)
            Text("Current profile: \(model.profile.examples.count) saved examples. Selecting a phase does not teach anything.")
                .font(.callout).accessibilityIdentifier("evaluation.currentProfile")
            if phase == .afterCorrections && !model.journal.hasCorrectionsSinceBaseline(profile: model.profile) {
                Text(PersonalInkEvaluationError.noSavedCorrections.localizedDescription)
                    .foregroundStyle(.orange).accessibilityIdentifier("evaluation.learningRequired")
            }
            if let active = model.journal.activeRun {
                Text("Another chart test is still capturing. Open its saved run below and stop it first.").foregroundStyle(.orange)
                Button("Open active test") { selectedRunID = active.id }
            } else if hasChordInk {
                Text("This chart already has chord ink. Close this panel and create a blank test chart to keep old samples out of the test.").foregroundStyle(.orange)
            }
            Button("Start capture in \(style.displayText)") {
                model.perform({ completion in
                    model.store.start(chartID: chartID, style: style.rawValue, phase: phase,
                                      profile: model.profileStore.snapshot().profile,
                                      pipeline: ChordInkRecognitionPipelineIdentity.version, completion: completion)
                }, then: { returnToChart() })
            }
            .buttonStyle(.borderedProminent)
            .disabled(hasChordInk || model.journal.activeRun != nil || model.error != nil ||
                      (phase == .afterCorrections && !model.journal.hasCorrectionsSinceBaseline(profile: model.profile)))
            .accessibilityIdentifier("evaluation.start")
        }
    }

    @ViewBuilder private func runView(_ run: PersonalInkEvaluationRun) -> some View {
        Text("\(ChartLayoutStyle(rawValue: run.style)?.displayText ?? run.style) · \(phaseTitle(run.phase))").font(.headline)
        switch run.status {
        case .capturing:
            Text("Capture active · \(run.records.count) current targets saved. Learning is paused. Your frozen profile has \(run.profile.examples.count) examples.")
            Text("Write the requested set of complete chords in this test chart. A target is not necessarily one chord: merged, split, or missing captures must be reported below after stopping.")
                .font(.callout).foregroundStyle(.secondary)
            if run.chartID != chartID { Text("This capture belongs to another chart. Return to that chart to continue writing.").foregroundStyle(.orange) }
            Button("Return to chart") { returnToChart() }.buttonStyle(.bordered).disabled(run.chartID != chartID)
            Button("Refresh saved count") { model.reload() }
            if let state = run.sourceCaptureState {
                if state == .complete {
                    Text("Full-source ink and target ownership saved for this revision.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("The latest ink capture is still pending. Return to Write & Render and let previews settle before stopping. Ending without scoring preserves partial evidence, not a complete test.")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            Button("Stop capture & label") {
                selectedRunID = run.id
                model.perform { model.store.stop(runID: run.id, completion: $0) }
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("evaluation.stop")
            Button("End without scoring", role: .destructive) { cancelConfirmation = true }
        case .labeling:
            Text("Tell us what each saved shape was intended to mean. Predictions stay hidden until the label is saved, so you are not copying the recognizer's answer.")
                .font(.callout)
            Text("If two chords merged, one split, or ink is incomplete, mark Incorrect grouping instead. If a chord is completely missing, the total written count below keeps that failure visible.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(Array(run.records.enumerated()), id: \.element.id) { index, record in
                PersonalEvaluationRecordCard(record: record, ordinal: index + 1, canEdit: true, showTeaching: false,
                    save: { text, grouping in
                        model.perform { model.store.label(runID: run.id, recordID: record.id, text: text, groupingIssue: grouping, completion: $0) }
                    }, teach: {})
            }
            TextField("How many complete chords did you write?", text: $expectedCount)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder).accessibilityIdentifier("evaluation.expectedCount")
            Toggle("Writing felt slow or delayed", isOn: $slowInk)
            Toggle("Earlier chords changed unexpectedly", isOn: $unexpectedChanges)
            Button("Finish & save results") {
                model.perform { model.store.finish(runID: run.id, expectedCount: Int(expectedCount) ?? 0,
                                                  slowInk: slowInk, unexpectedChanges: unexpectedChanges, completion: $0) }
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("evaluation.finish")
        case .complete:
            summary(run)
            #if DEBUG
            if PersonalInkVisualEncoder.bundledDirectory() != nil {
                NavigationLink("Compare learned ML model") { PersonalLearnedComparisonView(run: run) }
                    .buttonStyle(.bordered).accessibilityIdentifier("evaluation.learnedComparison")
            }
            #endif
            if let receipt = run.teachingReceipt {
                Label("Learning saved · \(receipt.taughtRecordIDs.count) labeled examples taught", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).accessibilityIdentifier("evaluation.learningSaved")
                Text("Saved profile: \(receipt.previousExampleCount) → \(receipt.savedExampleCount) examples · \(receipt.savedAt.formatted(date: .abbreviated, time: .shortened)). Old scores are unchanged.")
                    .font(.callout)
            }
            if !run.teachableRecords.isEmpty {
                Button("Teach \(run.teachableRecords.count) labeled examples") {
                    teachingRun = run; teachingConfirmation = true
                }
                    .buttonStyle(.borderedProminent).disabled(model.journal.activeRun != nil)
                    .accessibilityIdentifier("evaluation.teachBatch")
            }
            Text("Optional: save a new setup symbol, teach a selected symbol, or correct a scored chord below. Then start an After learning test on a new blank chart with newly written ink. Old scores and the frozen profile do not change.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(Array(run.records.enumerated()), id: \.element.id) { index, record in
                PersonalEvaluationRecordCard(record: record, ordinal: index + 1, canEdit: false, showTeaching: !record.groupingIssue && record.intended != nil,
                    save: { _, _ in }, teach: {
                        model.teach(runID: run.id, recordID: record.id)
                    })
            }
        case .cancelled:
            Text("Capture ended without a score. Its saved evidence remains on this iPad; it will not count as an accuracy test.")
        }
    }

    private func summary(_ run: PersonalInkEvaluationRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Results saved on this iPad", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Written: \(run.expectedChordCount ?? 0) · Captured targets: \(run.records.count) · Missing-count gap: \(run.missingCount)")
            if run.wholeChartScoreAvailable, let total = run.expectedChordCount {
                Text("Whole-chord exact: Standard \(run.baselineCorrect)/\(total) · With profile \(run.personalizedCorrect)/\(total)")
                    .font(.headline)
            } else {
                Text("Whole-chart accuracy withheld: grouping/count issues or replayed ink need review.").foregroundStyle(.orange)
                Text("Fresh, correctly grouped targets only: Standard \(run.baselineCorrect)/\(run.scoreable.count) · With profile \(run.personalizedCorrect)/\(run.scoreable.count)")
            }
            Text("Errors fixed: \(run.improvements) · New errors: \(run.regressions)")
            Text("Recorded build: \(run.pipeline)").font(.caption).foregroundStyle(.secondary)
            Text("Captured no-reads: Standard \(run.baselineNoReads) · With profile \(run.personalizedNoReads)")
            Text("These are top-choice comparisons, not automatic-commit accuracy. Timing records measure recognition processing, not Pencil-to-screen latency. Your two experience flags are saved separately.")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("evaluation.summary")
    }

    private func phaseTitle(_ phase: PersonalInkEvaluationRun.Phase) -> String {
        phase == .beforeCorrections ? "Before learning" : "After learning"
    }
}

private struct PersonalEvaluationRecordCard: View {
    let record: PersonalInkEvaluationRecord
    let ordinal: Int
    let canEdit: Bool
    let showTeaching: Bool
    let save: (String?, Bool) -> Void
    let teach: () -> Void
    @State private var label = ""
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target \(ordinal) · measure \(record.measureIndex)").font(.headline)
            Canvas { context, size in
                let scale = min(size.width / 48, size.height / 32)
                for stroke in record.strokes {
                    if stroke.points.count == 1, let point = stroke.points.first {
                        let x = (size.width - 48 * scale) / 2 + point.x * scale
                        let y = point.y * scale
                        context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.primary))
                        continue
                    }
                    var path = Path()
                    for (i, point) in stroke.points.enumerated() {
                        let p = CGPoint(x: (size.width - 48 * scale) / 2 + point.x * scale, y: point.y * scale)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }.frame(height: 115).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Captured handwriting for target \(ordinal)")
            if (record.intended == nil && !record.groupingIssue) || editing {
                TextField("Intended chord, e.g. F#m7 or Bb7", text: $label)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Button("Save label") { save(label, false); editing = false }.buttonStyle(.borderedProminent).disabled(label.isEmpty)
                    Button("Incorrect grouping") { save(nil, true); editing = false }.buttonStyle(.bordered)
                }
            } else {
                Text(record.groupingIssue ? "Flagged: incorrect grouping" : "Intended: \(record.intended ?? "")")
                Text("Standard: \(record.baseline ?? "No read") · With profile: \(record.personalized ?? "No read")")
                    .font(.callout)
                if let suggestion = record.personalSuggestion, let arbitration = record.personalArbitration {
                    Text("Personal match: \(suggestion.text) · \(arbitrationDescription(arbitration))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if record.knownInk { Text("Matches previously saved ink; excluded from fresh accuracy.").font(.caption).foregroundStyle(.orange) }
                if canEdit { Button("Edit label") { label = record.intended ?? ""; editing = true } }
                if showTeaching {
                    Button(record.taught ? "Taught — write a fresh example next" : "Teach this example") { teach() }
                        .buttonStyle(.bordered).disabled(record.taught)
                }
            }
        }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func arbitrationDescription(_ value: String) -> String {
        switch PersonalInkArbitrationPolicy.Disposition(rawValue: value) {
        case .protectedBaseline: return "trusted standard read kept"
        case .alternative: return "alternative only"
        case .agreement: return "agrees with standard"
        case .correctedReview: return "corrected example; confirmation required"
        case .personalRecovery: return "personal recovery; confirmation required"
        default: return "standard read kept"
        }
    }
}

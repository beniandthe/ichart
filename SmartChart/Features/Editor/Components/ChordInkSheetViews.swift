import SwiftUI

struct PendingChordInkConfirmation: Identifiable {
    let id = UUID()
    let measureID: UUID
    let measureIndex: Int
    let result: ChordInkRecognitionResult
    let drawingData: Data
    let targetFraction: Double?
    let primaryDecision: ChordInkRecognitionDecision
    let decision: ChordInkRecognitionDecision
    let candidateTexts: [String]
    let bestCandidateText: String?

    init(
        measureID: UUID,
        measureIndex: Int,
        result: ChordInkRecognitionResult,
        drawingData: Data,
        targetFraction: Double?,
        primaryDecision: ChordInkRecognitionDecision,
        decision: ChordInkRecognitionDecision
    ) {
        self.measureID = measureID
        self.measureIndex = measureIndex
        self.result = result
        self.drawingData = drawingData
        self.targetFraction = targetFraction
        self.primaryDecision = primaryDecision
        self.decision = decision

        let ocrCandidateTexts = result.ocrCandidates?.compactMap(\.displayText) ?? []
        let userFacingCandidateTexts = ChordRecognitionCompendium.userFacingCandidateTexts(
            from: result.rawCandidates + ocrCandidateTexts
        )
        self.candidateTexts = userFacingCandidateTexts
        self.bestCandidateText = result.match?.displayText ?? userFacingCandidateTexts.first
    }

    var displayMeasureNumber: Int {
        measureIndex + 1
    }
}

struct PendingChordCorrection: Identifiable {
    let id = UUID()
    let chordEventID: UUID
    let measureID: UUID
    let measureIndex: Int
    let currentText: String
    let rawInput: String?

    var displayMeasureNumber: Int {
        measureIndex + 1
    }

    var candidateTexts: [String] {
        var texts = [currentText]
        if let rawInput {
            texts.append(rawInput)
        }

        return texts.reduce(into: [String]()) { result, text in
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty,
                  !result.contains(trimmedText) else {
                return
            }

            result.append(trimmedText)
        }
    }
}

enum ChordInkFixtureCopyResult: Equatable {
    case copied(displayText: String, fixtureName: String)
    case failed(String)

    var message: String {
        switch self {
        case .copied(let displayText, let fixtureName):
            "Copied \(displayText) sample as \(fixtureName). Watcher will import it."
        case .failed(let message):
            message
        }
    }

    var isFailure: Bool {
        switch self {
        case .copied:
            false
        case .failed:
            true
        }
    }
}

struct ChordInkConfirmationSheetView: View {
    let confirmation: PendingChordInkConfirmation
    let showsFixtureCaptureTools: Bool
    let onAcceptCandidate: (String) -> Void
    let onCopyFixtureJSON: (String) -> ChordInkFixtureCopyResult
    let onKeepInk: () -> Void
    let onClearAndRewrite: () -> Void
    @State private var manualCandidateText: String
    @State private var fixtureCopyStatus: ChordInkFixtureCopyResult?
    @FocusState private var isManualEntryFocused: Bool

    init(
        confirmation: PendingChordInkConfirmation,
        showsFixtureCaptureTools: Bool = false,
        onAcceptCandidate: @escaping (String) -> Void,
        onCopyFixtureJSON: @escaping (String) -> ChordInkFixtureCopyResult,
        onKeepInk: @escaping () -> Void,
        onClearAndRewrite: @escaping () -> Void
    ) {
        self.confirmation = confirmation
        self.showsFixtureCaptureTools = showsFixtureCaptureTools
        self.onAcceptCandidate = onAcceptCandidate
        self.onCopyFixtureJSON = onCopyFixtureJSON
        self.onKeepInk = onKeepInk
        self.onClearAndRewrite = onClearAndRewrite
        _manualCandidateText = State(initialValue: confirmation.bestCandidateText ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    candidateChips
                    manualEntry
                    chartActions
                    if showsFixtureCaptureTools {
                        captureActions
                    }
                }
                .padding(20)
            }
            .navigationTitle("Confirm Chord")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(true)
    }

    private var trimmedCandidateText: String {
        manualCandidateText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measure \(confirmation.displayMeasureNumber)")
                .font(.title3.weight(.bold))

            Text(confirmation.decision.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let match = confirmation.result.match {
                Text("Best read: \(match.displayText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)

                if confirmation.decision.isCloseRace,
                   let competingCandidateText = confirmation.decision.competingCandidateText {
                    Text("Also close: \(competingCandidateText)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Type the intended chord below.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var candidateChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let candidates = Array(confirmation.candidateTexts.prefix(5))
            if candidates.isEmpty {
                Text("No candidates yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(candidates, id: \.self) { candidate in
                        Button {
                            manualCandidateText = candidate
                            fixtureCopyStatus = nil
                        } label: {
                            Text(candidate)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(candidate == trimmedCandidateText ? Color.blue.opacity(0.14) : Color(.secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chord")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Edit") {
                    isManualEntryFocused = true
                }
                .font(.caption.weight(.semibold))
            }

            TextField("Example: C, Bb, F#, C-, C-△7, C△7, Calt, C7alt, Db7(b9), G/B", text: $manualCandidateText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .focused($isManualEntryFocused)
                .submitLabel(.done)
                .animation(nil, value: manualCandidateText)
                .onChange(of: manualCandidateText) { _, _ in
                    if fixtureCopyStatus != nil {
                        fixtureCopyStatus = nil
                    }
                }
        }
    }

    private var captureActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fixture capture")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                fixtureCopyStatus = onCopyFixtureJSON(trimmedCandidateText)
            } label: {
                Text("Copy Test Fixture")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedCandidateText.isEmpty)

            if let fixtureCopyStatus {
                Text(fixtureCopyStatus.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(fixtureCopyStatus.isFailure ? Color.red : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(role: .destructive) {
                onClearAndRewrite()
            } label: {
                Text("Clear Ink & Next Sample")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var chartActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onAcceptCandidate(trimmedCandidateText)
            } label: {
                Text("Use This Chord")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedCandidateText.isEmpty)

            Button {
                onKeepInk()
            } label: {
                Text("Keep Raw Ink")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                onClearAndRewrite()
            } label: {
                Text("Clear & Rewrite")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct ChordCorrectionSheetView: View {
    let correction: PendingChordCorrection
    let onAcceptCandidate: (String) -> Void
    let onCancel: () -> Void
    @State private var candidateText: String
    @FocusState private var isCandidateFocused: Bool

    init(
        correction: PendingChordCorrection,
        onAcceptCandidate: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.correction = correction
        self.onAcceptCandidate = onAcceptCandidate
        self.onCancel = onCancel
        _candidateText = State(initialValue: correction.rawInput ?? correction.currentText)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Measure \(correction.displayMeasureNumber)")
                        .font(.title3.weight(.bold))

                    Text("Correct this rendered chord without collecting a new handwriting sample.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Current: \(correction.currentText)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                if !correction.candidateTexts.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(correction.candidateTexts, id: \.self) { candidate in
                            Button {
                                candidateText = candidate
                            } label: {
                                Text(candidate)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(candidate == trimmedCandidateText ? Color.blue.opacity(0.14) : Color(.secondarySystemBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Chord")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Edit") {
                            isCandidateFocused = true
                        }
                        .font(.caption.weight(.semibold))
                    }

                    TextField("Example: C, Bb, F#, C-△7, Db7(b9), G/B", text: $candidateText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .focused($isCandidateFocused)
                        .submitLabel(.done)
                        .animation(nil, value: candidateText)
                }

                Button {
                    onAcceptCandidate(trimmedCandidateText)
                } label: {
                    Text("Update Chord")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedCandidateText.isEmpty)

                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Correct Chord")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var trimmedCandidateText: String {
        candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import SwiftUI

struct PendingChordInkConfirmation: Identifiable {
    let id = UUID()
    let measureID: UUID
    let measureIndex: Int
    let result: ChordInkRecognitionResult
    let drawingData: Data
    let targetFraction: Double?
    let recognitionTiming: ChordInkRecognitionTiming?
    let proposalDecisionMilliseconds: Double?
    let primaryDecision: ChordInkRecognitionDecision
    let decision: ChordInkRecognitionDecision
    let candidateTexts: [String]
    let bestCandidateText: String?

    static func candidateTexts(for result: ChordInkRecognitionResult) -> [String] {
        ChordInkRenderResolutionPolicy.candidateTexts(for: result)
    }

    init(
        measureID: UUID,
        measureIndex: Int,
        result: ChordInkRecognitionResult,
        drawingData: Data,
        targetFraction: Double?,
        recognitionTiming: ChordInkRecognitionTiming? = nil,
        proposalDecisionMilliseconds: Double? = nil,
        primaryDecision: ChordInkRecognitionDecision,
        decision: ChordInkRecognitionDecision,
        candidateTexts: [String]? = nil
    ) {
        self.measureID = measureID
        self.measureIndex = measureIndex
        self.result = result
        self.drawingData = drawingData
        self.targetFraction = targetFraction
        self.recognitionTiming = recognitionTiming
        self.proposalDecisionMilliseconds = proposalDecisionMilliseconds
        self.primaryDecision = primaryDecision
        self.decision = decision

        let userFacingCandidateTexts = candidateTexts ?? Self.candidateTexts(for: result)
        self.candidateTexts = userFacingCandidateTexts
        self.bestCandidateText = result.match?.displayText ?? userFacingCandidateTexts.first
    }

    var displayMeasureNumber: Int {
        measureIndex + 1
    }

    var requiresDirectEntry: Bool {
        candidateTexts.isEmpty && result.match == nil && decision.acceptedText == nil
    }

    var visibleCandidateTexts: [String] {
        Array(candidateTexts.prefix(3))
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
    case unavailable

    #if DEBUG && targetEnvironment(simulator)
    case copied(displayText: String, fixtureName: String)
    case failed(String)
    #endif

    var message: String {
        #if DEBUG && targetEnvironment(simulator)
        switch self {
        case .copied(let displayText, let fixtureName):
            "Copied \(displayText) ink sample as \(fixtureName)."
        case .failed(let message):
            message
        case .unavailable:
            ""
        }
        #else
        ""
        #endif
    }

    var isFailure: Bool {
        #if DEBUG && targetEnvironment(simulator)
        switch self {
        case .copied:
            false
        case .failed, .unavailable:
            true
        }
        #else
        true
        #endif
    }
}

struct ChordInkConfirmationSheetView: View {
    let confirmation: PendingChordInkConfirmation
    let showsFixtureCaptureTools: Bool
    let onAcceptCandidate: (String) -> Void
    let onCopyFixtureJSON: (String) -> ChordInkFixtureCopyResult
    let onClearAndRewrite: () -> Void
    @State private var manualCandidateText: String
    @State private var fixtureCopyStatus: ChordInkFixtureCopyResult?
    @FocusState private var isManualEntryFocused: Bool

    init(
        confirmation: PendingChordInkConfirmation,
        showsFixtureCaptureTools: Bool = false,
        onAcceptCandidate: @escaping (String) -> Void,
        onCopyFixtureJSON: @escaping (String) -> ChordInkFixtureCopyResult,
        onClearAndRewrite: @escaping () -> Void
    ) {
        self.confirmation = confirmation
        self.showsFixtureCaptureTools = showsFixtureCaptureTools
        self.onAcceptCandidate = onAcceptCandidate
        self.onCopyFixtureJSON = onCopyFixtureJSON
        self.onClearAndRewrite = onClearAndRewrite
        _manualCandidateText = State(initialValue: confirmation.bestCandidateText ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                selectedChordSummary
                candidateChoices
                manualEntry
                manualActions
                #if DEBUG && targetEnvironment(simulator)
                if showsFixtureCaptureTools {
                    captureActions
                }
                #endif
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(confirmation.requiresDirectEntry ? "Enter Chord" : "Choose Chord")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(true)
        .task(id: confirmation.id) {
            guard shouldFocusManualEntry else {
                return
            }

            isManualEntryFocused = true
        }
    }

    private var trimmedCandidateText: String {
        manualCandidateText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldFocusManualEntry: Bool {
        confirmation.requiresDirectEntry || confirmation.visibleCandidateTexts.isEmpty
    }

    private var promptText: String {
        if confirmation.requiresDirectEntry {
            return "Type the chord you meant."
        }

        if confirmation.decision.reason.localizedCaseInsensitiveContains("previously rendered") {
            return "Pick the chord you meant, or type it."
        }

        if confirmation.decision.isCloseRace {
            return "Close match. Pick the chord you meant."
        }

        return "Choose one or type the chord."
    }

    private var selectedChordSummary: some View {
        VStack(spacing: 5) {
            Text("Measure \(confirmation.displayMeasureNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(trimmedCandidateText.isEmpty ? "Type chord" : trimmedCandidateText)
                .font(.system(.title, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)

            Text(promptText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var candidateChoices: some View {
        let candidates = Array(confirmation.visibleCandidateTexts.prefix(3))

        return VStack(spacing: 8) {
            if candidates.isEmpty {
                VStack(spacing: 8) {
                    Text("No confident suggestions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    Button {
                        focusManualEntry()
                    } label: {
                        Label("Keyboard", systemImage: "keyboard")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Open keyboard for manual chord entry")
                }
                .padding(.vertical, 4)
            } else {
                Text("Top 3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: candidates.count),
                    spacing: 8
                ) {
                    ForEach(Array(candidates.enumerated()), id: \.element) { index, candidate in
                        Button {
                            onAcceptCandidate(candidate)
                        } label: {
                            Text(candidate)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.blue.opacity(0.16), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accept suggestion \(index + 1), \(candidate)")
                    }
                }
            }
        }
    }

    private var manualEntry: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Manual entry")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    focusManualEntry()
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                        .labelStyle(.iconOnly)
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Open keyboard for manual chord entry")
            }

            TextField("Type chord", text: $manualCandidateText)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isManualEntryFocused)
                .submitLabel(.done)
                .animation(nil, value: manualCandidateText)
                .onSubmit {
                    acceptTrimmedCandidate()
                }
                #if DEBUG && targetEnvironment(simulator)
                .onChange(of: manualCandidateText) { _, _ in
                    if fixtureCopyStatus != nil {
                        fixtureCopyStatus = nil
                    }
                }
                #endif
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isManualEntryFocused ? Color.blue.opacity(0.45) : Color.black.opacity(0.06), lineWidth: 1)
                }
                .accessibilityLabel("Manual chord entry")
        }
    }

    private var manualActions: some View {
        HStack(spacing: 10) {
            Button {
                acceptTrimmedCandidate()
            } label: {
                Text("Learn Chord")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedCandidateText.isEmpty)

            Button(role: .destructive) {
                onClearAndRewrite()
            } label: {
                Text("Rewrite Ink")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private var captureActions: some View {
        VStack(spacing: 10) {
            Text("Ink sample capture")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                fixtureCopyStatus = onCopyFixtureJSON(trimmedCandidateText)
            } label: {
                Text("Copy Ink Sample")
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
                Text("Clear Ink")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    #endif

    private func acceptTrimmedCandidate() {
        guard !trimmedCandidateText.isEmpty else {
            return
        }

        onAcceptCandidate(trimmedCandidateText)
    }

    private func focusManualEntry() {
        isManualEntryFocused = true
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    correctionHeader
                    correctionCandidates
                    correctionEntry
                    correctionActions
                }
                .padding(22)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Correct Chord")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .task {
            isCandidateFocused = true
        }
    }

    private var correctionHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Update the chord")
                        .font(.title3.weight(.semibold))

                    Text("Measure \(correction.displayMeasureNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text("Make this rendered chord match the chart.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(correction.currentText)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("New")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(trimmedCandidateText.isEmpty ? "Type chord" : trimmedCandidateText)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        }
    }

    private var correctionCandidates: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick choices", systemImage: "list.bullet")
                .font(.headline.weight(.semibold))

            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(correction.candidateTexts, id: \.self) { candidate in
                    Button {
                        candidateText = candidate
                    } label: {
                        HStack(spacing: 6) {
                            Text(candidate)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if candidate == trimmedCandidateText {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(candidate == trimmedCandidateText ? Color.blue.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .foregroundStyle(candidate == trimmedCandidateText ? Color.blue : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var correctionEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Chord", systemImage: "keyboard")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button {
                    isCandidateFocused = true
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Open keyboard for chord correction")
            }

            HStack(spacing: 10) {
                TextField("C, Bb, Db7(b9), G/B", text: $candidateText)
                    .font(.title3.weight(.semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isCandidateFocused)
                    .submitLabel(.done)
                    .animation(nil, value: candidateText)
                    .onSubmit {
                        acceptTrimmedCandidate()
                    }

                Image(systemName: "return")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCandidateFocused ? Color.blue.opacity(0.45) : Color.black.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private var correctionActions: some View {
        VStack(spacing: 10) {
            Button {
                acceptTrimmedCandidate()
            } label: {
                Label(trimmedCandidateText.isEmpty ? "Update Chord" : "Update to \(trimmedCandidateText)", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedCandidateText.isEmpty)

            Button {
                onCancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var trimmedCandidateText: String {
        candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func acceptTrimmedCandidate() {
        guard !trimmedCandidateText.isEmpty else {
            return
        }

        onAcceptCandidate(trimmedCandidateText)
    }
}

import SwiftUI
import UIKit

private enum ChordInkManualEntryShortcut {
    static let chordRepeatText = ChordSymbol.chordRepeatDisplayText
}

/// Review is outside the ink canvas: finger, Pencil and pointer must all work.
/// A bounded height also keeps UIKit buttons from taking the ScrollView's space.
private struct ChordInkReviewButton: View {
    let title: String
    var systemImageName: String?
    var style: PencilOnlyActionButton.Style = .bordered
    var role: PencilOnlyActionButton.Role = .standard
    var isEnabled = true
    var accessibilityLabel: String?
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 44

    var body: some View {
        PencilOnlyActionButton(
            title: title,
            systemImageName: systemImageName,
            style: style,
            role: role,
            isEnabled: isEnabled,
            accessibilityLabel: accessibilityLabel,
            acceptsDirectTouches: true,
            action: action
        )
        .frame(height: buttonHeight)
    }
}

struct PendingChordInkConfirmation: Identifiable {
    let id: UUID
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
        id: UUID = UUID(),
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
        self.id = id
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
        self.bestCandidateText = decision.acceptedText ?? result.match?.displayText ?? userFacingCandidateTexts.first
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

    var reviewMessage: String? {
        decision.action == .confirm ? decision.reason : nil
    }
}

struct PendingChordInkBatchConfirmation: Identifiable {
    enum Source: Hashable {
        case recognitionProposal
        case draftPreview
    }

    let id = UUID()
    let confirmations: [PendingChordInkConfirmation]
    var source: Source = .recognitionProposal

    var displayTitle: String {
        confirmations.count == 1 ? "1 Chord" : "\(confirmations.count) Chords"
    }

    var instructionText: String {
        switch source {
        case .recognitionProposal:
            return "Review each chord, then render them together."
        case .draftPreview:
            return "Check the uncertain reads, then render the draft."
        }
    }

    var actionTitle: String {
        confirmations.count == 1 ? "Render Chord" : "Render All"
    }
}

enum ChordInkDraftReviewPolicy {
    static func batch(for state: ChordPreviewState) -> PendingChordInkBatchConfirmation? {
        let drafts = state.renderableDraftChords
        let confirmations = drafts.compactMap { draft -> PendingChordInkConfirmation? in
            guard let result = draft.recognitionResult else {
                return nil
            }

            let primaryDecision = draft.primaryDecision
                ?? ChordInkRecognitionPolicy.decision(for: result)
            let decision = draft.recognitionDecision ?? ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: primaryDecision.acceptedText,
                reason: "I couldn't verify every part of this chord. Choose a suggestion or type it in.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
            return PendingChordInkConfirmation(
                id: draft.id,
                measureID: draft.measureID,
                measureIndex: draft.measureIndex,
                result: result,
                drawingData: draft.drawingData,
                targetFraction: draft.targetFraction,
                primaryDecision: primaryDecision,
                decision: decision,
                candidateTexts: draft.candidateTexts
            )
        }

        guard !confirmations.isEmpty,
              confirmations.count == drafts.count else {
            return nil
        }

        return PendingChordInkBatchConfirmation(
            confirmations: confirmations,
            source: .draftPreview
        )
    }

    static func reviewedState(
        from state: ChordPreviewState,
        candidateTextByDraftID: [UUID: String]
    ) -> ChordPreviewState? {
        let renderableDrafts = state.renderableDraftChords
        guard !renderableDrafts.isEmpty,
              renderableDrafts.allSatisfy({ draft in
                  guard let candidateText = candidateTextByDraftID[draft.id],
                        !candidateText.isEmpty else {
                      return false
                  }
                  return ChordRecognitionCompendium.match(candidateText) != nil
              }) else {
            return nil
        }

        var reviewedState = state
        for index in reviewedState.draftChords.indices {
            let draftID = reviewedState.draftChords[index].id
            if let candidateText = candidateTextByDraftID[draftID] {
                reviewedState.draftChords[index].selectedText = candidateText
            }
        }
        return reviewedState
    }
}

struct PendingChordCorrection: Identifiable {
    let id = UUID()
    let chordEventID: UUID
    let measureID: UUID
    let measureIndex: Int
    let currentText: String
    let rawInput: String?
    let candidateTexts: [String]
    let enharmonicChoiceTexts: [String]

    var displayMeasureNumber: Int {
        measureIndex + 1
    }

    var currentDisplayText: String {
        Self.normalizedDisplayText(for: currentText) ?? currentText
    }

    var quickChoiceTexts: [String] {
        var blockedTexts = Set([currentText, rawInput].compactMap(Self.normalizedDisplayText))
        blockedTexts.insert(currentDisplayText)

        let preferredTexts = enharmonicChoiceTexts + candidateTexts
        var texts = preferredTexts.reduce(into: [String]()) { result, candidateText in
            guard let displayText = Self.normalizedDisplayText(for: candidateText),
                  !blockedTexts.contains(displayText),
                  !result.contains(displayText) else {
                return
            }

            result.append(displayText)
        }

        if !blockedTexts.contains(ChordInkManualEntryShortcut.chordRepeatText),
           !texts.contains(ChordInkManualEntryShortcut.chordRepeatText) {
            texts.append(ChordInkManualEntryShortcut.chordRepeatText)
        }

        return texts
    }

    private static func normalizedDisplayText(for text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        // A persisted source signature can predate the current chord-domain
        // boundary or come from imported chart data. Keep that evidence intact,
        // but never turn an unsupported string into a one-tap suggestion.
        return ChordRecognitionCompendium.match(trimmedText)?.displayText
    }
}

struct ChordInkBatchConfirmationSheetView: View {
    let batch: PendingChordInkBatchConfirmation
    let highlightsForwardActions: Bool
    let onAcceptAll: ([UUID: String]) -> Void
    let onClearAndRewrite: () -> Void
    @State private var candidateTextByID: [UUID: String]
    // UIKit reports focus through its delegate, not a SwiftUI .focused modifier.
    @State private var focusedConfirmationID: UUID?
    @State private var keyboardConfirmationID: UUID?

    init(
        batch: PendingChordInkBatchConfirmation,
        highlightsForwardActions: Bool = false,
        onAcceptAll: @escaping ([UUID: String]) -> Void,
        onClearAndRewrite: @escaping () -> Void
    ) {
        self.batch = batch
        self.highlightsForwardActions = highlightsForwardActions
        self.onAcceptAll = onAcceptAll
        self.onClearAndRewrite = onClearAndRewrite
        _candidateTextByID = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: batch.confirmations.map { confirmation in
                    (confirmation.id, confirmation.bestCandidateText ?? "")
                }
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(spacing: 5) {
                    Text(batch.displayTitle)
                        .font(.system(.title2, design: .rounded).weight(.bold))

                    Text(batch.instructionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(batch.confirmations) { confirmation in
                                chordRow(for: confirmation)
                                    .id(confirmation.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: focusedConfirmationID) { _, id in
                        if let id {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }

                HStack(spacing: 10) {
                    ChordInkReviewButton(title: "Rewrite Ink") {
                        onClearAndRewrite()
                    }
                    .frame(maxWidth: .infinity)

                    ChordInkReviewButton(
                        title: batch.actionTitle,
                        style: .borderedProminent,
                        isEnabled: canRenderAll
                    ) {
                        onAcceptAll(trimmedCandidateTextByID)
                    }
                    .frame(maxWidth: .infinity)
                    .tourActionHighlight(
                        isActive: highlightsForwardActions && canRenderAll,
                        cornerRadius: 10
                    )
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Confirm Chords")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(true)
    }

    private var trimmedCandidateTextByID: [UUID: String] {
        candidateTextByID.reduce(into: [UUID: String]()) { result, element in
            result[element.key] = element.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var canRenderAll: Bool {
        batch.confirmations.allSatisfy { confirmation in
            !(trimmedCandidateTextByID[confirmation.id] ?? "").isEmpty
        }
    }

    private func chordRow(for confirmation: PendingChordInkConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Measure \(confirmation.displayMeasureNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if confirmation.decision.isCloseRace {
                    Text("Check")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                ChordInkReviewButton(
                    title: "Edit",
                    systemImageName: "keyboard",
                    style: .plain,
                    accessibilityLabel: "Type chord for measure \(confirmation.displayMeasureNumber)"
                ) {
                    keyboardConfirmationID = confirmation.id
                    focusedConfirmationID = confirmation.id
                }
                .frame(width: 92)
            }

            ChordInkScopedScribbleTextField(
                placeholder: "Chord",
                text: Binding(
                    get: { candidateTextByID[confirmation.id] ?? "" },
                    set: { candidateTextByID[confirmation.id] = $0 }
                ),
                isFocused: Binding(
                    get: { focusedConfirmationID == confirmation.id },
                    set: { isFocused in
                        if isFocused {
                            focusedConfirmationID = confirmation.id
                        } else if focusedConfirmationID == confirmation.id {
                            focusedConfirmationID = nil
                        }
                    }
                ),
                allowsScribble: keyboardConfirmationID != confirmation.id
            )
            .frame(height: 52)
            .accessibilityLabel("Chord entry for measure \(confirmation.displayMeasureNumber)")

            if let reviewMessage = confirmation.reviewMessage {
                Text(reviewMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !confirmation.visibleCandidateTexts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(confirmation.visibleCandidateTexts, id: \.self) { candidate in
                        ChordInkReviewButton(title: candidate) {
                            candidateTextByID[confirmation.id] = candidate
                        }
                        .frame(maxWidth: .infinity)
                        .tourActionHighlight(
                            isActive: highlightsForwardActions,
                            cornerRadius: 8
                        )
                    }
                }
            }

            ChordInkReviewButton(
                title: "Chord Repeat \(ChordInkManualEntryShortcut.chordRepeatText)",
                systemImageName: "repeat",
                accessibilityLabel: "Use chord repeat symbol"
            ) {
                candidateTextByID[confirmation.id] = ChordInkManualEntryShortcut.chordRepeatText
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Use chord repeat symbol")
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ChordInkScopedScribbleTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var allowsScribble = true

    func makeUIView(context: Context) -> ChordInkScopedScribbleUITextField {
        let textField = ChordInkScopedScribbleUITextField()
        textField.allowsScribble = allowsScribble
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.returnKeyType = .done
        textField.clearButtonMode = .whileEditing
        textField.font = .systemFont(ofSize: 20, weight: .semibold)
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: ChordInkScopedScribbleUITextField, context: Context) {
        context.coordinator.parent = self
        let inputModeChanged = textField.allowsScribble != allowsScribble
        textField.allowsScribble = allowsScribble

        if textField.text != text {
            textField.text = text
        }

        if isFocused, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        }
        // UIKit transfers first responder to the requested row. Do not resign
        // another row during SwiftUI's update: that can race the transfer and
        // dismiss the keyboard. Return/dismissal still clears the live binding.

        if inputModeChanged, textField.isFirstResponder {
            textField.reloadInputViews()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ChordInkScopedScribbleTextField

        init(parent: ChordInkScopedScribbleTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

private final class ChordInkScopedScribbleUITextField: UITextField, UIScribbleInteractionDelegate {
    private var scopedScribbleInteraction: UIScribbleInteraction?
    var allowsScribble = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        installScopedScribbleInteraction()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installScopedScribbleInteraction()
    }

    private func installScopedScribbleInteraction() {
        let interaction = UIScribbleInteraction(delegate: self)
        addInteraction(interaction)
        scopedScribbleInteraction = interaction
    }

    func scribbleInteraction(
        _ interaction: UIScribbleInteraction,
        shouldBeginAt location: CGPoint
    ) -> Bool {
        allowsScribble && bounds.contains(location)
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
    let highlightsForwardActions: Bool
    let onAcceptCandidate: (String) -> Void
    let onCopyFixtureJSON: (String) -> ChordInkFixtureCopyResult
    let onClearAndRewrite: () -> Void
    @State private var manualCandidateText: String
    @State private var fixtureCopyStatus: ChordInkFixtureCopyResult?
    @FocusState private var isManualEntryFocused: Bool

    init(
        confirmation: PendingChordInkConfirmation,
        showsFixtureCaptureTools: Bool = false,
        highlightsForwardActions: Bool = false,
        onAcceptCandidate: @escaping (String) -> Void,
        onCopyFixtureJSON: @escaping (String) -> ChordInkFixtureCopyResult,
        onClearAndRewrite: @escaping () -> Void
    ) {
        self.confirmation = confirmation
        self.showsFixtureCaptureTools = showsFixtureCaptureTools
        self.highlightsForwardActions = highlightsForwardActions
        self.onAcceptCandidate = onAcceptCandidate
        self.onCopyFixtureJSON = onCopyFixtureJSON
        self.onClearAndRewrite = onClearAndRewrite
        _manualCandidateText = State(initialValue: confirmation.bestCandidateText ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Enter Chord")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let reviewMessage = confirmation.reviewMessage {
                    Text(reviewMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("Type chord", text: $manualCandidateText)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
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
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isManualEntryFocused ? Color.blue.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel("Manual chord entry")

                shortcutButtons
                actionButtons

                #if DEBUG && targetEnvironment(simulator)
                if showsFixtureCaptureTools {
                    Divider()
                    captureActions
                }
                #endif
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
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

    private var shortcutButtons: some View {
        let candidates = Array(confirmation.visibleCandidateTexts.prefix(3))

        return VStack(spacing: 10) {
            if !candidates.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(candidates.enumerated()), id: \.element) { index, candidate in
                        compactButton(title: candidate) {
                            manualCandidateText = candidate
                            isManualEntryFocused = false
                        }
                        .tourActionHighlight(
                            isActive: highlightsForwardActions,
                            cornerRadius: 9
                        )
                        .accessibilityLabel("Use suggestion \(index + 1), \(candidate)")
                    }
                }
            }

            compactButton(title: "Chord Repeat \(ChordInkManualEntryShortcut.chordRepeatText)") {
                manualCandidateText = ChordInkManualEntryShortcut.chordRepeatText
                isManualEntryFocused = false
            }
            .accessibilityLabel("Use chord repeat symbol")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            ChordInkReviewButton(
                title: "Confirm",
                style: .borderedProminent,
                isEnabled: !trimmedCandidateText.isEmpty
            ) {
                acceptTrimmedCandidate()
            }
            .frame(maxWidth: .infinity)
            .tourActionHighlight(
                isActive: highlightsForwardActions && !trimmedCandidateText.isEmpty,
                cornerRadius: 10
            )

            ChordInkReviewButton(
                title: "Rewrite Ink",
                role: .destructive
            ) {
                onClearAndRewrite()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func compactButton(title: String, action: @escaping () -> Void) -> some View {
        ChordInkReviewButton(title: title, action: action)
            .frame(maxWidth: .infinity, minHeight: 42)
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
}

struct ChordCorrectionSheetView: View {
    let correction: PendingChordCorrection
    let canTeachHandwriting: Bool
    let onAcceptCandidate: (String, Bool) -> Void
    let onCancel: () -> Void
    @State private var candidateText: String
    @State private var teachesHandwriting = false
    @FocusState private var isManualEntryFocused: Bool

    init(
        correction: PendingChordCorrection,
        canTeachHandwriting: Bool = false,
        onAcceptCandidate: @escaping (String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.correction = correction
        self.canTeachHandwriting = canTeachHandwriting
        self.onAcceptCandidate = onAcceptCandidate
        self.onCancel = onCancel
        _candidateText = State(initialValue: correction.currentDisplayText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Enter Chord")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                TextField("Type chord", text: $candidateText)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isManualEntryFocused)
                    .submitLabel(.done)
                    .animation(nil, value: candidateText)
                    .onSubmit {
                        acceptTrimmedCandidate()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isManualEntryFocused ? Color.blue.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel("Manual chord entry")

                shortcutButtons
                if canTeachHandwriting {
                    Toggle("Teach this handwriting correction", isOn: $teachesHandwriting)
                        .font(.callout)
                    Text("Only enable this for a misread—not when changing the music or transposing a chord.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                actionButtons
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(true)
        .task(id: correction.id) {
            guard shouldFocusManualEntry else {
                return
            }

            isManualEntryFocused = true
        }
    }

    private var shortcutButtons: some View {
        let candidates = Array(quickShortcutTexts.prefix(3))

        return VStack(spacing: 10) {
            if !candidates.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(candidates.enumerated()), id: \.element) { index, candidate in
                        compactButton(title: candidate) {
                            candidateText = candidate
                            isManualEntryFocused = false
                        }
                        .accessibilityLabel("Use suggestion \(index + 1), \(candidate)")
                    }
                }
            }

            compactButton(title: "Chord Repeat \(ChordInkManualEntryShortcut.chordRepeatText)") {
                candidateText = ChordInkManualEntryShortcut.chordRepeatText
                isManualEntryFocused = false
            }
            .accessibilityLabel("Use chord repeat symbol")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            ChordInkReviewButton(
                title: "Confirm",
                style: .borderedProminent,
                isEnabled: !trimmedCandidateText.isEmpty
            ) {
                acceptTrimmedCandidate()
            }
            .frame(maxWidth: .infinity)

            ChordInkReviewButton(title: "Cancel") {
                onCancel()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func compactButton(title: String, action: @escaping () -> Void) -> some View {
        ChordInkReviewButton(title: title, action: action)
            .frame(maxWidth: .infinity, minHeight: 42)
    }

    private var quickShortcutTexts: [String] {
        correction.quickChoiceTexts.filter { $0 != ChordInkManualEntryShortcut.chordRepeatText }
    }

    private var shouldFocusManualEntry: Bool {
        quickShortcutTexts.isEmpty
    }

    private var trimmedCandidateText: String {
        candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func acceptTrimmedCandidate() {
        guard !trimmedCandidateText.isEmpty else {
            return
        }

        onAcceptCandidate(trimmedCandidateText, canTeachHandwriting && teachesHandwriting)
    }
}

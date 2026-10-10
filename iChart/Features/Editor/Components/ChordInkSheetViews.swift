import SwiftUI
import UIKit

private enum ChordInkManualEntryShortcut {
    static let chordRepeatText = ChordSymbol.chordRepeatDisplayText
}

enum ChordInkReviewEntryValidation: Equatable {
    case valid
    case empty
    case unsupported

    init(text: String?) {
        let trimmedText = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            self = .empty
        } else {
            self = ChordRecognitionCompendium.match(trimmedText) != nil ? .valid : .unsupported
        }
    }

    var isRenderable: Bool { self == .valid }

    func feedbackText(hasMissingChordGuidance: Bool = false) -> String? {
        switch self {
        case .valid:
            return nil
        case .empty:
            return hasMissingChordGuidance ? nil : "Enter a chord"
        case .unsupported:
            return "Check this chord spelling"
        }
    }

    static func remainingCount(for entryTexts: [String?]) -> Int {
        entryTexts.reduce(into: 0) { count, text in
            if !Self(text: text).isRenderable { count += 1 }
        }
    }

    static func remainingMessage(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 chord needs attention" : "\(count) chords need attention"
    }
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
        candidateTexts: [String]? = nil,
        initialEntryText: String? = nil,
        startsWithEmptyEntry: Bool = false
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

        let userFacingCandidateTexts = ChordRecognitionCompendium.userFacingCandidateTexts(
            from: candidateTexts ?? Self.candidateTexts(for: result)
        )
        self.candidateTexts = userFacingCandidateTexts
        self.bestCandidateText = ChordInkRenderResolutionPolicy.bestCandidateText(
            preferredTexts: startsWithEmptyEntry ? []
                : [initialEntryText, decision.acceptedText, result.match?.displayText],
            candidateTexts: userFacingCandidateTexts
        )
    }

    var displayMeasureNumber: Int {
        measureIndex + 1
    }

    var requiresDirectEntry: Bool {
        bestCandidateText == nil
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
    /// Draft/source ownership frozen when review opens. An edited canvas or
    /// regrouped target must reopen review rather than reuse these labels.
    var reviewedDraftState: ChordPreviewState? = nil

    var displayTitle: String {
        confirmations.count == 1 ? "1 Chord" : "\(confirmations.count) Chords"
    }

    var instructionText: String {
        switch source {
        case .recognitionProposal:
            return "Review each chord, then render them together."
        case .draftPreview:
            return "Check the reads and enter any missing chords, then render the draft."
        }
    }

    var actionTitle: String {
        confirmations.count == 1 ? "Render Chord" : "Render All"
    }
}

enum ChordInkDraftReviewRejection: String, Error {
    case wrongReviewSource
    case missingSnapshot
    case draftCountChanged
    case draftsChanged
    case barlinesChanged
    case layoutChanged
    case confirmationIDsChanged
    case emptyDraft
    case entryIDsChanged
    case emptyEntry
    case unsupportedEntry

    /// Content-free explanations identify the failed safeguard without exposing
    /// handwriting, entered chord text or chart/target identifiers.
    var recoveryMessage: String {
        switch self {
        case .wrongReviewSource:
            return "This review is not attached to the current draft. Return to writing and reopen review."
        case .missingSnapshot:
            return "This review is missing its draft snapshot. Return to writing and reopen review."
        case .draftCountChanged:
            return "The number of draft chords changed while review was open. Return to writing and reopen review."
        case .draftsChanged:
            return "The draft chords changed while review was open. Return to writing and reopen review."
        case .barlinesChanged:
            return "The draft barlines changed while review was open. Return to writing and reopen review."
        case .layoutChanged:
            return "The draft layout changed while review was open. Return to writing and reopen review."
        case .confirmationIDsChanged:
            return "The review rows no longer match the draft. Return to writing and reopen review."
        case .emptyDraft:
            return "There are no draft chords in this review. Return to writing and reopen review."
        case .entryIDsChanged:
            return "The review entries do not match this batch. Return to writing and reopen review."
        case .emptyEntry:
            return "One reviewed entry is empty. Enter a chord in every review row, then render again."
        case .unsupportedEntry:
            return "One reviewed entry is unsupported. Correct that entry or choose a suggestion, then render again."
        }
    }
}

enum ChordInkDraftReviewPolicy {
    static func batch(for state: ChordPreviewState) -> PendingChordInkBatchConfirmation? {
        let drafts = state.draftChords
        let confirmations = drafts.compactMap { draft -> PendingChordInkConfirmation? in
            let result = draft.recognitionResult ?? ChordInkRecognitionResult(
                rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0
            )

            let primaryDecision = draft.primaryDecision
                ?? ChordInkRecognitionPolicy.decision(for: result)
            let decision = draft.isRenderable ? (draft.recognitionDecision ?? ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: primaryDecision.acceptedText,
                reason: "I couldn't verify every part of this chord. Choose a suggestion or type it in.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )) : ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: nil,
                reason: "No supported read. Type the chord or rewrite just this ink.",
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
                candidateTexts: draft.candidateTexts,
                initialEntryText: draft.previewText,
                startsWithEmptyEntry: !draft.isRenderable
            )
        }

        guard !confirmations.isEmpty,
              confirmations.count == drafts.count else {
            return nil
        }

        return PendingChordInkBatchConfirmation(
            confirmations: confirmations,
            source: .draftPreview,
            reviewedDraftState: state
        )
    }

    static func reviewedState(
        from state: ChordPreviewState,
        batch: PendingChordInkBatchConfirmation,
        candidateTextByDraftID: [UUID: String]
    ) -> ChordPreviewState? {
        try? validation(from: state, batch: batch, candidateTextByDraftID: candidateTextByDraftID).get()
    }

    static func validation(
        from state: ChordPreviewState,
        batch: PendingChordInkBatchConfirmation,
        candidateTextByDraftID: [UUID: String]
    ) -> Result<ChordPreviewState, ChordInkDraftReviewRejection> {
        guard batch.source == .draftPreview else { return .failure(.wrongReviewSource) }
        guard let expected = batch.reviewedDraftState else { return .failure(.missingSnapshot) }
        guard state.draftChords.count == expected.draftChords.count,
              batch.confirmations.count == state.draftChords.count else {
            return .failure(.draftCountChanged)
        }
        guard state.draftChords == expected.draftChords else { return .failure(.draftsChanged) }
        guard state.draftBarlines == expected.draftBarlines else { return .failure(.barlinesChanged) }
        guard state.layoutPageSize == expected.layoutPageSize else { return .failure(.layoutChanged) }
        guard batch.confirmations.map(\.id) == expected.draftChords.map(\.id) else {
            return .failure(.confirmationIDsChanged)
        }
        return validation(from: state, candidateTextByDraftID: candidateTextByDraftID)
    }

    static func reviewedState(
        from state: ChordPreviewState,
        candidateTextByDraftID: [UUID: String]
    ) -> ChordPreviewState? {
        try? validation(from: state, candidateTextByDraftID: candidateTextByDraftID).get()
    }

    /// A sheet may retain temporary input while its batch changes. Submission
    /// owns only the visible batch's IDs; missing current entries stay empty and
    /// cannot become valid by inheriting a stale row or recognition suggestion.
    static func submissionTexts(
        for batch: PendingChordInkBatchConfirmation,
        candidateTextByDraftID: [UUID: String]
    ) -> [UUID: String] {
        batch.confirmations.reduce(into: [UUID: String]()) { entries, confirmation in
            entries[confirmation.id] = (candidateTextByDraftID[confirmation.id] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func validation(
        from state: ChordPreviewState,
        candidateTextByDraftID: [UUID: String]
    ) -> Result<ChordPreviewState, ChordInkDraftReviewRejection> {
        let drafts = state.draftChords
        guard !drafts.isEmpty else { return .failure(.emptyDraft) }
        guard Set(candidateTextByDraftID.keys) == Set(drafts.map(\.id)) else {
            return .failure(.entryIDsChanged)
        }
        for draft in drafts {
            guard let candidateText = candidateTextByDraftID[draft.id],
                  !candidateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptyEntry)
            }
            guard ChordRecognitionCompendium.match(candidateText) != nil else {
                return .failure(.unsupportedEntry)
            }
        }

        var reviewedState = state
        for index in reviewedState.draftChords.indices {
            let draftID = reviewedState.draftChords[index].id
            if let candidateText = candidateTextByDraftID[draftID] {
                reviewedState.draftChords[index].selectedText = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return .success(reviewedState)
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
    let onBackToInk: (() -> Void)?
    let onRewriteChord: ((PendingChordInkConfirmation) -> Void)?
    let onEntryTextsChanged: (([UUID: String]) -> Void)?
    @State private var candidateTextByID: [UUID: String]
    // UIKit reports focus through its delegate, not a SwiftUI .focused modifier.
    @State private var focusedConfirmationID: UUID?
    @State private var keyboardScrollConfirmationID: UUID?
    @State private var keyboardScrollRequestID = 0
    @State private var confirmsRewriteAll = false

    init(
        batch: PendingChordInkBatchConfirmation,
        highlightsForwardActions: Bool = false,
        onAcceptAll: @escaping ([UUID: String]) -> Void,
        onClearAndRewrite: @escaping () -> Void,
        onBackToInk: (() -> Void)? = nil,
        onRewriteChord: ((PendingChordInkConfirmation) -> Void)? = nil,
        initialEntryTextsByID: [UUID: String] = [:],
        onEntryTextsChanged: (([UUID: String]) -> Void)? = nil
    ) {
        self.batch = batch
        self.highlightsForwardActions = highlightsForwardActions
        self.onAcceptAll = onAcceptAll
        self.onClearAndRewrite = onClearAndRewrite
        self.onBackToInk = onBackToInk
        self.onRewriteChord = onRewriteChord
        self.onEntryTextsChanged = onEntryTextsChanged
        _candidateTextByID = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: batch.confirmations.map { confirmation in
                    (confirmation.id, initialEntryTextsByID[confirmation.id] ?? confirmation.bestCandidateText ?? "")
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
                        .background(IChartTypedSheetScrollSupport())
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: keyboardScrollRequestID) { _, _ in
                        if let id = keyboardScrollConfirmationID {
                            withAnimation { proxy.scrollTo(id, anchor: .top) }
                        }
                    }
                }

                if let remainingMessage = ChordInkReviewEntryValidation.remainingMessage(for: remainingEntryCount) {
                    Text(remainingMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("Chord review remaining entries")
                }

                HStack(spacing: 10) {
                    if let onBackToInk {
                        ChordInkReviewButton(title: "Back to Writing") {
                            focusedConfirmationID = nil
                            onBackToInk()
                        }
                        .frame(maxWidth: .infinity)
                    }

                    ChordInkReviewButton(
                        title: batch.actionTitle,
                        style: .borderedProminent,
                        isEnabled: canRenderAll
                    ) {
                        focusedConfirmationID = nil
                        onAcceptAll(trimmedCandidateTextByID)
                    }
                    .frame(maxWidth: .infinity)
                    .tourActionHighlight(
                        isActive: highlightsForwardActions && canRenderAll,
                        cornerRadius: 10
                    )
                }
                ChordInkReviewButton(title: "Rewrite All Ink", style: .plain, role: .destructive) {
                    focusedConfirmationID = nil
                    confirmsRewriteAll = true
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Confirm Chords")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if focusedConfirmationID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { focusedConfirmationID = nil }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
        .onAppear { onEntryTextsChanged?(candidateTextByID) }
        .onChange(of: candidateTextByID) { _, entries in
            onEntryTextsChanged?(entries)
        }
        .confirmationDialog("Rewrite all chord ink?", isPresented: $confirmsRewriteAll, titleVisibility: .visible) {
            Button("Rewrite All Ink", role: .destructive) { onClearAndRewrite() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all pending chord ink. Use Rewrite This Chord to keep the rest of your writing.")
        }
    }

    private var trimmedCandidateTextByID: [UUID: String] {
        ChordInkDraftReviewPolicy.submissionTexts(for: batch, candidateTextByDraftID: candidateTextByID)
    }

    private var canRenderAll: Bool {
        remainingEntryCount == 0
    }

    private var remainingEntryCount: Int {
        ChordInkReviewEntryValidation.remainingCount(
            for: batch.confirmations.map { candidateTextByID[$0.id] }
        )
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

            }

            IChartTypedTextField(
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
                font: .systemFont(ofSize: 20, weight: .semibold),
                onKeyboardRequested: { requestKeyboard(for: confirmation.id) },
                onNext: nextConfirmationID(after: confirmation.id).map { nextID in
                    { requestKeyboard(for: nextID) }
                }
            )
            .frame(height: 52)
            .accessibilityLabel("Chord entry for measure \(confirmation.displayMeasureNumber)")

            if let feedback = ChordInkReviewEntryValidation(text: candidateTextByID[confirmation.id])
                .feedbackText(hasMissingChordGuidance: confirmation.requiresDirectEntry && confirmation.reviewMessage != nil) {
                Text(feedback)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("Chord entry feedback for measure \(confirmation.displayMeasureNumber)")
            }

            if let reviewMessage = confirmation.reviewMessage {
                Text(reviewMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onRewriteChord {
                ChordInkReviewButton(title: "Rewrite This Chord", style: .plain,
                    accessibilityLabel: "Rewrite this chord in measure \(confirmation.displayMeasureNumber)") {
                    focusedConfirmationID = nil
                    onRewriteChord(confirmation)
                }
                .frame(maxWidth: .infinity)
            }

            if !confirmation.visibleCandidateTexts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(confirmation.visibleCandidateTexts, id: \.self) { candidate in
                        ChordInkReviewButton(title: candidate) {
                            candidateTextByID[confirmation.id] = candidate
                            focusedConfirmationID = nil
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
                focusedConfirmationID = nil
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Use chord repeat symbol")
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func nextConfirmationID(after id: UUID) -> UUID? {
        guard let index = batch.confirmations.firstIndex(where: { $0.id == id }),
              batch.confirmations.indices.contains(index + 1) else { return nil }
        return batch.confirmations[index + 1].id
    }

    private func requestKeyboard(for id: UUID) {
        focusedConfirmationID = id
        keyboardScrollConfirmationID = id
        keyboardScrollRequestID += 1
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
    let onBackToInk: (() -> Void)?
    let onRewriteChord: ((PendingChordInkConfirmation) -> Void)?
    @State private var manualCandidateText: String
    @State private var fixtureCopyStatus: ChordInkFixtureCopyResult?
    @State private var confirmsRewriteAll = false
    @State private var isManualEntryFocused = false

    init(
        confirmation: PendingChordInkConfirmation,
        showsFixtureCaptureTools: Bool = false,
        highlightsForwardActions: Bool = false,
        onAcceptCandidate: @escaping (String) -> Void,
        onCopyFixtureJSON: @escaping (String) -> ChordInkFixtureCopyResult,
        onClearAndRewrite: @escaping () -> Void,
        onBackToInk: (() -> Void)? = nil,
        onRewriteChord: ((PendingChordInkConfirmation) -> Void)? = nil
    ) {
        self.confirmation = confirmation
        self.showsFixtureCaptureTools = showsFixtureCaptureTools
        self.highlightsForwardActions = highlightsForwardActions
        self.onAcceptCandidate = onAcceptCandidate
        self.onCopyFixtureJSON = onCopyFixtureJSON
        self.onClearAndRewrite = onClearAndRewrite
        self.onBackToInk = onBackToInk
        self.onRewriteChord = onRewriteChord
        _manualCandidateText = State(initialValue: confirmation.bestCandidateText ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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

                IChartTypedTextField(
                    placeholder: "Type chord",
                    text: $manualCandidateText,
                    isFocused: $isManualEntryFocused,
                    font: .preferredFont(forTextStyle: .title2),
                    textAlignment: .center,
                    borderStyle: .none
                )
                    .animation(nil, value: manualCandidateText)
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

                if let feedback = ChordInkReviewEntryValidation(text: manualCandidateText)
                    .feedbackText(hasMissingChordGuidance: confirmation.requiresDirectEntry && confirmation.reviewMessage != nil) {
                    Text(feedback)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                shortcutButtons
                actionButtons
                if let onRewriteChord {
                    ChordInkReviewButton(title: "Rewrite This Chord", style: .plain) {
                        isManualEntryFocused = false
                        onRewriteChord(confirmation)
                    }
                }
                ChordInkReviewButton(title: "Rewrite All Ink", style: .plain, role: .destructive) {
                    isManualEntryFocused = false
                    confirmsRewriteAll = true
                }

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
            .frame(maxWidth: .infinity, alignment: .top)
            .background(IChartTypedSheetScrollSupport())
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
        .confirmationDialog("Rewrite all chord ink?", isPresented: $confirmsRewriteAll, titleVisibility: .visible) {
            Button("Rewrite All Ink", role: .destructive) { onClearAndRewrite() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all pending chord ink.")
        }
    }

    private var trimmedCandidateText: String {
        manualCandidateText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                isEnabled: ChordRecognitionCompendium.match(trimmedCandidateText) != nil
            ) {
                acceptTrimmedCandidate()
            }
            .frame(maxWidth: .infinity)
            .tourActionHighlight(
                isActive: highlightsForwardActions && !trimmedCandidateText.isEmpty,
                cornerRadius: 10
            )

            if let onBackToInk {
                ChordInkReviewButton(title: "Back to Writing") {
                    isManualEntryFocused = false
                    onBackToInk()
                }
                .frame(maxWidth: .infinity)
            }
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

        isManualEntryFocused = false
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
    @State private var isManualEntryFocused = false

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
            ScrollView {
            VStack(spacing: 18) {
                Text("Enter Chord")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                IChartTypedTextField(
                    placeholder: "Type chord",
                    text: $candidateText,
                    isFocused: $isManualEntryFocused,
                    font: .preferredFont(forTextStyle: .title2),
                    textAlignment: .center,
                    borderStyle: .none
                )
                    .animation(nil, value: candidateText)
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

                if trimmedCandidateText.isEmpty {
                    Text("Enter a chord")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

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
            .frame(maxWidth: .infinity, alignment: .top)
            .background(IChartTypedSheetScrollSupport())
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
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
                isManualEntryFocused = false
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

    private var trimmedCandidateText: String {
        candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func acceptTrimmedCandidate() {
        guard !trimmedCandidateText.isEmpty else {
            return
        }

        isManualEntryFocused = false
        onAcceptCandidate(trimmedCandidateText, canTeachHandwriting && teachesHandwriting)
    }
}

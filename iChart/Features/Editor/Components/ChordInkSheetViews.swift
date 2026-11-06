import SwiftUI
import UIKit
import PencilKit

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
        .disabled(!isEnabled)
    }
}

/// A display-only crop of the exact source owned by this entry. Rendering the
/// original archive keeps raised extensions, slash basses and stroke shapes
/// visible without changing the source used by recognition or correction.
enum ChordInkSourcePreviewRenderer {
    static func image(for drawingData: Data?) -> UIImage? {
        guard let drawingData, let drawing = try? PKDrawing(data: drawingData),
              !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -6, dy: -6)
        guard bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2, 280 / max(bounds.width, bounds.height))
        return LeadSheetSavedInkRenderer.renderedInkImage(drawingData, in: bounds, scale: scale)
    }
}

private struct ChordInkSourcePreview: View {
    let drawingData: Data?
    var accessibilityDescription = "Original chord handwriting"

    var body: some View {
        let sourceImage = ChordInkSourcePreviewRenderer.image(for: drawingData)
        return Group {
            if let image = sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "pencil.line").font(.title2)
                    Text("No ink preview").font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sourceImage == nil ? "Source handwriting unavailable" : accessibilityDescription)
    }
}

struct ChordInkReviewSourceLocation: Equatable {
    let measureNumber: Int
    var rowNumber: Int? = nil
    var fraction: Double? = nil
    var includesMeasureNumber = true

    var label: String {
        let measure = "Measure \(measureNumber)"
        return rowNumber.map { includesMeasureNumber ? "Row \($0) · \(measure)" : "Row \($0)" } ?? measure
    }

    var positionLabel: String? {
        guard let fraction, fraction.isFinite else { return nil }
        if fraction < 1.0 / 3 { return "Left side" }
        if fraction < 2.0 / 3 { return "Center" }
        return "Right side"
    }
}

private struct ChordInkSourceLocationView: View {
    let location: ChordInkReviewSourceLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(location.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if let positionLabel = location.positionLabel, let fraction = location.fraction {
                HStack(spacing: 7) {
                    GeometryReader { proxy in
                        Capsule().fill(Color.secondary.opacity(0.16))
                            .frame(height: 3)
                            .overlay(alignment: .leading) {
                                Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                                    .offset(x: (proxy.size.width - 7) * CGFloat(min(max(fraction, 0), 1)))
                            }
                    }
                    .frame(width: 64, height: 7)
                    .accessibilityHidden(true)
                    Text(positionLabel).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
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
    let sourceRowNumber: Int?
    let sourcePositionFraction: Double?

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
        startsWithEmptyEntry: Bool = false,
        sourceRowNumber: Int? = nil,
        sourcePositionFraction: Double? = nil
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
        self.sourceRowNumber = sourceRowNumber
        self.sourcePositionFraction = sourcePositionFraction ?? targetFraction

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

    var sourceLocation: ChordInkReviewSourceLocation {
        .init(measureNumber: displayMeasureNumber, rowNumber: sourceRowNumber,
            fraction: sourcePositionFraction, includesMeasureNumber: sourceRowNumber == nil)
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
        if requiresSeparatedChordInk {
            return "Separate the grouped chords before rendering."
        }
        return "Check each recognition guess and enter any missing chords. \(actionTitle) uses the chord text shown in each row."
    }

    var actionTitle: String {
        confirmations.count == 1 ? "Render Chord" : "Render All"
    }

    var requiresSeparatedChordInk: Bool {
        reviewedDraftState?.draftChords.contains(where: \.requiresSeparatedChordInk) == true
    }

    func requiresSeparatedChordInk(for id: UUID) -> Bool {
        reviewedDraftState?.draftChords.contains { $0.id == id && $0.requiresSeparatedChordInk } == true
    }
}

enum ChordInkDraftReviewRejection: String, Error {
    case wrongReviewSource
    case missingSnapshot
    case draftCountChanged
    case draftsChanged
    case barlinesChanged
    case endingsChanged
    case layoutChanged
    case confirmationIDsChanged
    case emptyDraft
    case entryIDsChanged
    case emptyEntry
    case unsupportedEntry
    case requiresSeparatedChordInk

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
        case .endingsChanged:
            return "The draft endings changed while review was open. Return to writing and reopen review."
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
        case .requiresSeparatedChordInk:
            return "Tap Back to Writing, then rewrite the grouped chords with more space between them."
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
                reason: result.requiresTriangleQualityReview
                    ? primaryDecision.reason
                    : "No supported read. Type the chord or rewrite just this ink.",
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
                startsWithEmptyEntry: !draft.isRenderable,
                sourceRowNumber: draft.laneLocation.map { $0.systemIndex + 1 },
                sourcePositionFraction: draft.laneLocation?.fraction
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
        guard zip(state.draftChords, expected.draftChords).allSatisfy({ current, reviewed in
            matchesReviewedSource(current, reviewed: reviewed, submittedText: candidateTextByDraftID[current.id])
        })
        else { return .failure(.draftsChanged) }
        guard state.draftBarlines == expected.draftBarlines else { return .failure(.barlinesChanged) }
        guard state.draftEndings == expected.draftEndings else { return .failure(.endingsChanged) }
        guard state.layoutPageSize == expected.layoutPageSize else { return .failure(.layoutChanged) }
        guard batch.confirmations.map(\.id) == expected.draftChords.map(\.id) else {
            return .failure(.confirmationIDsChanged)
        }
        return validation(from: state, candidateTextByDraftID: candidateTextByDraftID)
    }

    private static func matchesReviewedSource(
        _ current: ChordInkDraft, reviewed: ChordInkDraft, submittedText: String?
    ) -> Bool {
        guard let submittedText, ChordRecognitionCompendium.match(submittedText) != nil else {
            return current == reviewed
        }
        // Render All accepts the supported text displayed in this row. A new
        // reader suggestion cannot change that choice for the same owned ink.
        var comparable = current
        comparable.candidateTexts = reviewed.candidateTexts
        comparable.bestCandidateText = reviewed.bestCandidateText
        comparable.confidence = reviewed.confidence
        comparable.recognitionResult = reviewed.recognitionResult
        comparable.primaryDecision = reviewed.primaryDecision
        comparable.recognitionDecision = reviewed.recognitionDecision
        if var lifecycle = comparable.targetLifecycle, let reviewedLifecycle = reviewed.targetLifecycle {
            lifecycle.generationID = reviewedLifecycle.generationID
            comparable.targetLifecycle = lifecycle
        }
        return comparable == reviewed
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
        guard !drafts.contains(where: \.requiresSeparatedChordInk) else {
            return .failure(.requiresSeparatedChordInk)
        }
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
    var sourceInkData: Data? = nil
    var sourceRowNumber: Int? = nil
    var sourcePositionFraction: Double? = nil

    var sourceLocation: ChordInkReviewSourceLocation {
        .init(measureNumber: displayMeasureNumber, rowNumber: sourceRowNumber,
            fraction: sourcePositionFraction)
    }

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

    /// Keep correction shortcuts separate from persisted recognition evidence.
    /// A legacy signature can contain only the original three wrong guesses.
    var qualityChoiceTexts: [String] {
        ChordInkCorrectionQualityPolicy.choiceTexts(for: currentDisplayText,
            excluding: Set(visibleAlternativeTexts))
    }

    var visibleAlternativeTexts: [String] {
        // Ordinary signatures contain at most three candidates. Bound imported
        // legacy evidence without silently hiding the fourth valid alternative.
        Array(quickChoiceTexts.filter { $0 != ChordInkManualEntryShortcut.chordRepeatText }.prefix(16))
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

struct ChordRenderInlineStatus: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.caption.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("chord-render-inline-status")
    }
}

private extension View {
    func chordRenderStatusInset(_ message: String?) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if let message {
                ChordRenderInlineStatus(message: message)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }
}

struct ChordInkBatchConfirmationSheetView: View {
    let batch: PendingChordInkBatchConfirmation
    let highlightsForwardActions: Bool
    let onAcceptAll: ([UUID: String]) -> Void
    let onClearAndRewrite: () -> Void
    let onBackToInk: (() -> Void)?
    let onRewriteChord: ((PendingChordInkConfirmation) -> Void)?
    let onEditedTextsChanged: (([UUID: String]) -> Void)?
    let initialFocusedConfirmationID: UUID?
    @Binding private var renderError: String?
    @State private var editedTextByID: [UUID: String]
    // UIKit reports focus through its delegate, not a SwiftUI .focused modifier.
    @State private var focusedConfirmationID: UUID?
    @State private var confirmsRewriteAll = false

    init(
        batch: PendingChordInkBatchConfirmation,
        highlightsForwardActions: Bool = false,
        onAcceptAll: @escaping ([UUID: String]) -> Void,
        onClearAndRewrite: @escaping () -> Void,
        onBackToInk: (() -> Void)? = nil,
        onRewriteChord: ((PendingChordInkConfirmation) -> Void)? = nil,
        initialEditedTextsByID: [UUID: String] = [:],
        initialFocusedConfirmationID: UUID? = nil,
        onEditedTextsChanged: (([UUID: String]) -> Void)? = nil,
        renderError: Binding<String?> = .constant(nil)
    ) {
        self.batch = batch
        self.highlightsForwardActions = highlightsForwardActions
        self.onAcceptAll = onAcceptAll
        self.onClearAndRewrite = onClearAndRewrite
        self.onBackToInk = onBackToInk
        self.onRewriteChord = onRewriteChord
        self.onEditedTextsChanged = onEditedTextsChanged
        self.initialFocusedConfirmationID = initialFocusedConfirmationID
        _renderError = renderError
        _focusedConfirmationID = State(initialValue: initialFocusedConfirmationID)
        let confirmationIDs = Set(batch.confirmations.map(\.id))
        _editedTextByID = State(initialValue: initialEditedTextsByID.filter { confirmationIDs.contains($0.key) })
    }

    var body: some View {
        NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 5) {
                            Text(batch.displayTitle)
                                .font(.system(.title2, design: .rounded).weight(.bold))

                            Text(batch.instructionText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)

                        VStack(spacing: 10) {
                            ForEach(batch.confirmations) { confirmation in
                                chordRow(for: confirmation)
                                    .id(confirmation.id)
                            }
                        }
                        .padding(.vertical, 2)

                        if !batch.requiresSeparatedChordInk,
                           let remainingMessage = ChordInkReviewEntryValidation.remainingMessage(for: remainingEntryCount) {
                            Text(remainingMessage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("Chord review remaining entries")
                        }

                        HStack(spacing: 10) {
                            if let onBackToInk {
                                ChordInkReviewButton(title: "Back to Writing") {
                                    onEditedTextsChanged?(editedTextByID)
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
                                guard canRenderAll else { return }
                                onEditedTextsChanged?(editedTextByID)
                                focusedConfirmationID = nil
                                onAcceptAll(trimmedCandidateTextByID)
                            }
                            .frame(maxWidth: .infinity)
                            .tourActionHighlight(
                                isActive: highlightsForwardActions && canRenderAll,
                                cornerRadius: 10
                            )
                        }
                        ChordInkReviewButton(title: "Clear Draft Ink", style: .plain, role: .destructive) {
                            focusedConfirmationID = nil
                            confirmsRewriteAll = true
                        }
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    // Header, entries and actions share the keyboard-resized
                    // viewport. Fixed siblings must not squeeze chord entry
                    // into a sliver in landscape with the software keyboard.
                    .background(IChartTypedSheetScrollSupport())
                }
                .scrollDismissesKeyboard(.interactively)
                // Keep the focused field's border clear of a docked keyboard.
                // UIKit still owns focus scrolling; a bottom safe-area margin
                // prevents its settled target from ending flush at that edge.
                .safeAreaPadding(.bottom, 8)
                .chordRenderStatusInset(renderError)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Review Chords")
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
        .onAppear {
            onEditedTextsChanged?(editedTextByID)
            if let initialFocusedConfirmationID,
               !batch.requiresSeparatedChordInk(for: initialFocusedConfirmationID),
               batch.confirmations.contains(where: { $0.id == initialFocusedConfirmationID }) {
                requestKeyboard(for: initialFocusedConfirmationID)
            }
        }
        .onChange(of: editedTextByID) { _, entries in
            onEditedTextsChanged?(entries)
        }
        .confirmationDialog("Clear draft ink?", isPresented: $confirmsRewriteAll, titleVisibility: .visible) {
            Button("Clear Draft Ink", role: .destructive) { onClearAndRewrite() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all unrendered writing in Write & Render. Rendered notation and Free Ink stay unchanged." + (onRewriteChord == nil ? "" : " Use Rewrite This Chord to keep the rest of your draft writing."))
        }
    }

    private var trimmedCandidateTextByID: [UUID: String] {
        ChordInkDraftReviewPolicy.submissionTexts(
            for: batch,
            candidateTextByDraftID: Dictionary(uniqueKeysWithValues: batch.confirmations.map {
                ($0.id, entryText(for: $0))
            })
        )
    }

    private var canRenderAll: Bool {
        !batch.requiresSeparatedChordInk && remainingEntryCount == 0
    }

    private var remainingEntryCount: Int {
        ChordInkReviewEntryValidation.remainingCount(
            for: batch.confirmations.map { entryText(for: $0) }
        )
    }

    private func entryText(for confirmation: PendingChordInkConfirmation) -> String {
        editedTextByID[confirmation.id] ?? confirmation.bestCandidateText ?? ""
    }

    private func entryOrigin(for confirmation: PendingChordInkConfirmation) -> String {
        if editedTextByID[confirmation.id] != nil {
            return "Your edit"
        }
        return confirmation.bestCandidateText == nil ? "Needs a chord" : "Recognition guess"
    }

    private func chordRow(for confirmation: PendingChordInkConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                ChordInkSourcePreview(drawingData: confirmation.drawingData,
                    accessibilityDescription: "Original handwriting for chord \(chordNumber(for: confirmation.id))")
                    .frame(width: 116, height: 78)
                    .accessibilityIdentifier("Chord review source \(confirmation.id.uuidString)")

                VStack(alignment: .leading, spacing: 5) {
                    Text("Chord \(chordNumber(for: confirmation.id))")
                        .font(.subheadline.weight(.semibold))
                    ChordInkSourceLocationView(location: confirmation.sourceLocation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if batch.requiresSeparatedChordInk(for: confirmation.id) {
                Text(ChordInkDraftReviewRejection.requiresSeparatedChordInk.recoveryMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                chordEntryControls(for: confirmation)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chordEntryControls(for confirmation: PendingChordInkConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entryOrigin(for: confirmation))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("Chord review origin \(confirmation.id.uuidString)")

            IChartTypedTextField(
                placeholder: "Chord",
                text: Binding(
                    get: { entryText(for: confirmation) },
                    set: { editedTextByID[confirmation.id] = $0 }
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
            .accessibilityIdentifier("Chord review entry \(confirmation.id.uuidString)")

            if let feedback = ChordInkReviewEntryValidation(text: entryText(for: confirmation))
                .feedbackText(hasMissingChordGuidance: confirmation.requiresDirectEntry && confirmation.reviewMessage != nil) {
                Text(feedback)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("Chord entry feedback for measure \(confirmation.displayMeasureNumber)")
            }

            if confirmation.requiresDirectEntry && entryText(for: confirmation).isEmpty {
                Text("Type the chord shown in your handwriting.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !confirmation.visibleCandidateTexts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(confirmation.visibleCandidateTexts, id: \.self) { candidate in
                        ChordInkReviewButton(title: candidate) {
                            editedTextByID[confirmation.id] = candidate
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

            HStack(spacing: 10) {
                ChordInkReviewButton(
                    title: "Chord Repeat \(ChordInkManualEntryShortcut.chordRepeatText)",
                    style: .plain,
                    accessibilityLabel: "Use chord repeat symbol"
                ) {
                    editedTextByID[confirmation.id] = ChordInkManualEntryShortcut.chordRepeatText
                    focusedConfirmationID = nil
                }
                .frame(maxWidth: .infinity)

                if let onRewriteChord {
                    ChordInkReviewButton(title: "Rewrite This Chord", style: .plain,
                        accessibilityLabel: "Rewrite chord \(chordNumber(for: confirmation.id)) in measure \(confirmation.displayMeasureNumber)") {
                        focusedConfirmationID = nil
                        onRewriteChord(confirmation)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func chordNumber(for id: UUID) -> Int {
        (batch.confirmations.firstIndex(where: { $0.id == id }) ?? 0) + 1
    }

    private func nextConfirmationID(after id: UUID) -> UUID? {
        guard let index = batch.confirmations.firstIndex(where: { $0.id == id }) else { return nil }
        return batch.confirmations.dropFirst(index + 1)
            .first { !batch.requiresSeparatedChordInk(for: $0.id) }?.id
    }

    private func requestKeyboard(for id: UUID) {
        // UIKit owns focused-field keyboard avoidance. Scrolling a whole row
        // here and again after keyboardDidShow starts competing animations.
        focusedConfirmationID = id
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
    let renderStatus: String?
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
        onRewriteChord: ((PendingChordInkConfirmation) -> Void)? = nil,
        renderStatus: String? = nil
    ) {
        self.confirmation = confirmation
        self.showsFixtureCaptureTools = showsFixtureCaptureTools
        self.highlightsForwardActions = highlightsForwardActions
        self.onAcceptCandidate = onAcceptCandidate
        self.onCopyFixtureJSON = onCopyFixtureJSON
        self.onClearAndRewrite = onClearAndRewrite
        self.onBackToInk = onBackToInk
        self.onRewriteChord = onRewriteChord
        self.renderStatus = renderStatus
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

                HStack(spacing: 16) {
                    ChordInkSourcePreview(drawingData: confirmation.drawingData)
                        .frame(width: 144, height: 88)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your handwriting").font(.subheadline.weight(.semibold))
                        ChordInkSourceLocationView(location: confirmation.sourceLocation)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                ChordInkReviewButton(title: "Clear Draft Ink", style: .plain, role: .destructive) {
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
            .chordRenderStatusInset(renderStatus)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
        .confirmationDialog("Clear draft ink?", isPresented: $confirmsRewriteAll, titleVisibility: .visible) {
            Button("Clear Draft Ink", role: .destructive) { onClearAndRewrite() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all unrendered writing in Write & Render. Rendered notation and Free Ink stay unchanged.")
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
    let renderStatus: String?
    @State private var candidateText: String
    @State private var teachesHandwriting = false
    @State private var isManualEntryFocused = false

    init(
        correction: PendingChordCorrection,
        canTeachHandwriting: Bool = false,
        onAcceptCandidate: @escaping (String, Bool) -> Void,
        onCancel: @escaping () -> Void,
        renderStatus: String? = nil
    ) {
        self.correction = correction
        self.canTeachHandwriting = canTeachHandwriting
        self.onAcceptCandidate = onAcceptCandidate
        self.onCancel = onCancel
        self.renderStatus = renderStatus
        _candidateText = State(initialValue: correction.currentDisplayText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 18) {
                Text("Edit Chord")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("Choose an alternative, change the quality, or edit the text. Save applies the chord shown in Change to.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    if correction.sourceInkData != nil {
                        ChordInkSourcePreview(drawingData: correction.sourceInkData)
                            .frame(width: 144, height: 88)
                            .accessibilityIdentifier("Edited chord source handwriting")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(correction.currentDisplayText)
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .accessibilityLabel("Current chord \(correction.currentDisplayText)")
                        ChordInkSourceLocationView(location: correction.sourceLocation)
                        if correction.sourceInkData != nil {
                            Text("Original handwriting").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                Text("Change to").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
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
                }

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
            .chordRenderStatusInset(renderStatus)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
    }

    private var shortcutButtons: some View {
        let candidates = correction.visibleAlternativeTexts

        return VStack(alignment: .leading, spacing: 10) {
            if !candidates.isEmpty {
                Text("Other spellings and saved alternatives")
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(Array(candidates.enumerated()), id: \.element) { index, candidate in
                        compactButton(title: candidate) {
                            candidateText = candidate
                            isManualEntryFocused = false
                        }
                        .accessibilityLabel("Use suggestion \(index + 1), \(candidate)")
                    }
                }
            }

            if !correction.qualityChoiceTexts.isEmpty {
                Text("Change quality")
                    .font(.subheadline.weight(.semibold))
                Text("These keep the root, extensions and bass. They are editing choices, not new recognition guesses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(correction.qualityChoiceTexts, id: \.self) { candidate in
                        compactButton(title: candidate) {
                            candidateText = candidate
                            teachesHandwriting = false
                            isManualEntryFocused = false
                        }
                        .accessibilityLabel("Change quality to \(candidate)")
                        .accessibilityHint("Sets Change to. Tap Save to apply this edit.")
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
                title: "Save",
                style: .borderedProminent,
                isEnabled: ChordRecognitionCompendium.match(trimmedCandidateText) != nil
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

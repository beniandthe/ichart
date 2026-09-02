#if canImport(UIKit)
import Foundation
import PencilKit
import SwiftUI
import UIKit

private enum ChordLaneLocalBreadcrumbs {
    #if DEBUG
    private static let isEnabled = UserDefaults.standard.bool(forKey: "iChartChordLaneBreadcrumbsEnabled")
    #else
    private static let isEnabled = false
    #endif

    static func reset() {
        guard isEnabled else {
            return
        }

        try? FileManager.default.removeItem(at: logURL)
        record("reset")
    }

    static func record(_ event: String, fields: [String: Any?] = [:]) {
        guard isEnabled else {
            return
        }

        let fieldText = fields
            .compactMap { key, value -> String? in
                guard let value else {
                    return nil
                }
                return "\(key)=\(sanitized(String(describing: value)))"
            }
            .sorted()
            .joined(separator: " ")
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        let line = "t=\(timestamp) event=\(sanitized(event)) \(fieldText)\n"

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("iChart chord lane breadcrumb error: \(error)")
        }

        print("iChart chord lane breadcrumb: \(line)", terminator: "")
    }

    private static var logURL: URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseDirectory.appendingPathComponent("chord-lane-breadcrumbs.log")
    }

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

struct LeadSheetCanvasHostView: UIViewRepresentable {
    @Binding var chart: Chart
    @Binding var selectedMeasureID: UUID?
    @Binding var selectedNoteSelection: LeadSheetNoteSelection?
    @Binding var selectedChordID: UUID?
    @Binding var selectedCommittedBarlineMeasureID: UUID?
    @Binding var selectedCueTextID: UUID?
    @Binding var selectedRoadmapMarkerID: UUID?
    let interactionMode: EditorCanvasMode
    let inkToolMode: EditorInkToolMode
    var recognizesChordInk: Bool = true
    var chordPreviewState: ChordPreviewState = ChordPreviewState()
    var inkResponsivenessValue: Double = LeadSheetInkResponsivenessPolicy.defaultValue
    var onTimeSignatureTargetRequested: ((UUID) -> Void)? = nil
    var onChordInkRecognitionProposal: ((UUID, ChordInkRecognitionResult, Data, Double?, ChordInkRecognitionTiming, ChordInkRecognitionFlow) -> Void)? = nil
    var onChordInkBatchRecognitionProposal: (([ChordInkRecognitionProposalPayload], ChordInkRecognitionFlow) -> Void)? = nil
    var onChordInkDraftPreviewChanged: (([ChordInkRecognitionProposalPayload]) -> Void)? = nil
    var onChordInkDraftBarlinesChanged: (([DraftBarline]) -> Void)? = nil
    var onChordCorrectionRequested: ((UUID) -> Void)? = nil
    var onChordDeleted: ((ChordEvent) -> Void)? = nil
    var onNoteSelectionChanged: ((LeadSheetNoteSelection?) -> Void)? = nil
    var onMeasureSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onChordSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onCueTextSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onCueTextEditRequested: ((UUID) -> Void)? = nil
    var onRoadmapMarkerSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onRepeatSpanSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onEndingSpanSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onTimeSignatureSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onHeaderAuthoringRequested: (() -> Void)? = nil
    var chordDraftRenderInvalidationRequestID: UUID? = nil
    var rhythmicNotationPreviewConfirmationRequestID: UUID? = nil
    var onRhythmicNotationPreviewChanged: ((LeadSheetRhythmicNotationPreviewState?) -> Void)? = nil
    var onRhythmicNotationDiagnostic: ((RhythmRecognitionDiagnosticEvent) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            chart: $chart,
            selectedMeasureID: $selectedMeasureID,
            selectedNoteSelection: $selectedNoteSelection,
            selectedChordID: $selectedChordID,
            selectedCommittedBarlineMeasureID: $selectedCommittedBarlineMeasureID,
            selectedCueTextID: $selectedCueTextID,
            selectedRoadmapMarkerID: $selectedRoadmapMarkerID
        )
    }

    func makeUIView(context: Context) -> LeadSheetCanvasUIKitView {
        ChordLaneLocalBreadcrumbs.reset()
        ChordDraftPreviewDeviceDiagnostics.reset()
        ChordLaneLocalBreadcrumbs.record(
            "make_canvas",
            fields: [
                "mode": interactionMode,
                "inkTool": inkToolMode,
                "measureCount": chart.measures.count,
                "chordCount": chart.measures.reduce(0) { $0 + $1.chordEvents.count }
            ]
        )
        let view = LeadSheetCanvasUIKitView()
        configure(view, context: context)
        return view
    }

    func updateUIView(_ uiView: LeadSheetCanvasUIKitView, context: Context) {
        configure(uiView, context: context)
    }

    private func configure(_ view: LeadSheetCanvasUIKitView, context: Context) {
        view.interactionMode = interactionMode
        view.chart = view.chartByApplyingPendingPersistedInk(to: chart)
        view.applyParentSelectionState(
            selectedMeasureID: selectedMeasureID,
            selectedNoteSelection: selectedNoteSelection,
            selectedChordID: selectedChordID,
            selectedCommittedBarlineMeasureID: selectedCommittedBarlineMeasureID,
            selectedCueTextID: selectedCueTextID,
            selectedRoadmapMarkerID: selectedRoadmapMarkerID
        )
        view.inkToolMode = inkToolMode
        view.recognizesChordInk = recognizesChordInk
        view.chordPreviewState = chordPreviewState
        view.inkResponsivenessValue = inkResponsivenessValue
        view.restrictsParentScrollToOutsideMargins = interactionMode.restrictsPageScrollToOutsideMargins
        view.onMeasureSelectionChanged = { measureID in
            context.coordinator.selectedMeasureID.wrappedValue = measureID
        }
        view.onNoteSelectionChanged = { selection in
            context.coordinator.selectedNoteSelection.wrappedValue = selection
            onNoteSelectionChanged?(selection)
        }
        view.onChordSelectionChanged = { chordID in
            context.coordinator.selectedChordID.wrappedValue = chordID
        }
        view.onCommittedChordBarlineSelectionChanged = { measureID in
            context.coordinator.selectedCommittedBarlineMeasureID.wrappedValue = measureID
        }
        view.onCueTextSelectionChanged = { cueTextID in
            context.coordinator.selectedCueTextID.wrappedValue = cueTextID
        }
        view.onRoadmapMarkerSelectionChanged = { markerID in
            context.coordinator.selectedRoadmapMarkerID.wrappedValue = markerID
        }
        view.onChartChanged = { updatedChart in
            context.coordinator.chart.wrappedValue = updatedChart
        }
        view.onTimeSignatureTargetRequested = onTimeSignatureTargetRequested
        view.onChordInkRecognitionProposal = onChordInkRecognitionProposal
        view.onChordInkBatchRecognitionProposal = onChordInkBatchRecognitionProposal
        view.onChordInkDraftPreviewChanged = onChordInkDraftPreviewChanged
        view.onChordInkDraftBarlinesChanged = onChordInkDraftBarlinesChanged
        view.onChordCorrectionRequested = onChordCorrectionRequested
        view.onChordDeleted = onChordDeleted
        view.onMeasureSelectedFromCanvas = onMeasureSelectedFromCanvas
        view.onChordSelectedFromCanvas = onChordSelectedFromCanvas
        view.onCueTextSelectedFromCanvas = onCueTextSelectedFromCanvas
        view.onCueTextEditRequested = onCueTextEditRequested
        view.onRoadmapMarkerSelectedFromCanvas = onRoadmapMarkerSelectedFromCanvas
        view.onRepeatSpanSelectedFromCanvas = onRepeatSpanSelectedFromCanvas
        view.onEndingSpanSelectedFromCanvas = onEndingSpanSelectedFromCanvas
        view.onTimeSignatureSelectedFromCanvas = onTimeSignatureSelectedFromCanvas
        view.onHeaderAuthoringRequested = onHeaderAuthoringRequested
        view.handleChordDraftRenderInvalidationRequest(chordDraftRenderInvalidationRequestID)
        view.onRhythmicNotationPreviewChanged = onRhythmicNotationPreviewChanged
        view.onRhythmicNotationDiagnostic = onRhythmicNotationDiagnostic
        view.handleRhythmicNotationPreviewConfirmationRequest(rhythmicNotationPreviewConfirmationRequestID)
    }

    final class Coordinator {
        var chart: Binding<Chart>
        var selectedMeasureID: Binding<UUID?>
        var selectedNoteSelection: Binding<LeadSheetNoteSelection?>
        var selectedChordID: Binding<UUID?>
        var selectedCommittedBarlineMeasureID: Binding<UUID?>
        var selectedCueTextID: Binding<UUID?>
        var selectedRoadmapMarkerID: Binding<UUID?>

        init(
            chart: Binding<Chart>,
            selectedMeasureID: Binding<UUID?>,
            selectedNoteSelection: Binding<LeadSheetNoteSelection?>,
            selectedChordID: Binding<UUID?>,
            selectedCommittedBarlineMeasureID: Binding<UUID?>,
            selectedCueTextID: Binding<UUID?>,
            selectedRoadmapMarkerID: Binding<UUID?>
        ) {
            self.chart = chart
            self.selectedMeasureID = selectedMeasureID
            self.selectedNoteSelection = selectedNoteSelection
            self.selectedChordID = selectedChordID
            self.selectedCommittedBarlineMeasureID = selectedCommittedBarlineMeasureID
            self.selectedCueTextID = selectedCueTextID
            self.selectedRoadmapMarkerID = selectedRoadmapMarkerID
        }
    }
}

private final class LeadSheetChordInkConfirmOverlayView: UIView {
    var containsConfirmSurface: ((CGPoint) -> Bool)?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, isUserInteractionEnabled else {
            return false
        }

        return containsConfirmSurface?(point) ?? false
    }
}

enum ChordInkRestoredDraftPreviewPolicy {
    static func shouldBootstrap(
        interactionMode: EditorCanvasMode,
        recognizesChordInk: Bool,
        previewState: ChordPreviewState,
        restoredDrawingData: Data?,
        isDirtyChordInk: Bool,
        currentInkSnapshot: LeadSheetInkDrawingSnapshot?,
        lastBootstrappedSnapshot: LeadSheetInkDrawingSnapshot?
    ) -> Bool {
        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              previewState.isEmpty,
              restoredDrawingData?.isEmpty == false,
              !isDirtyChordInk,
              let currentInkSnapshot else {
            return false
        }

        return currentInkSnapshot != lastBootstrappedSnapshot
    }
}

enum ChordInkEmptyDraftPreviewPolicy {
    static func shouldHandleEmptyChordInk(
        interactionMode: EditorCanvasMode,
        activeRole: LeadSheetInkAuthoringSessionRole?,
        strokeCount: Int
    ) -> Bool {
        interactionMode.allowsChordInkEditing
            && activeRole == .chord
            && strokeCount == 0
    }

    static func shouldDiscardDraftPreview(_ previewState: ChordPreviewState) -> Bool {
        !previewState.isEmpty
    }
}

enum LeadSheetCanvasLayoutInvalidationPolicy {
    static func requiresLayoutRefresh(
        previousMode: EditorCanvasMode,
        nextMode: EditorCanvasMode
    ) -> Bool {
        previousMode.allowsChordInkEditing != nextMode.allowsChordInkEditing
    }
}

enum LeadSheetRhythmicNotationAdvisoryPolicy {
    static let tapToRenderAdvisoryDelay: TimeInterval = 0.72

    static func canUseScheduledSnapshot(
        currentInkSnapshot: LeadSheetInkDrawingSnapshot?,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) -> Bool {
        guard currentInkSnapshot != nil,
              scheduledInkSnapshot != nil else {
            return false
        }

        return LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
            currentInkSnapshot: currentInkSnapshot,
            scheduledInkSnapshot: scheduledInkSnapshot
        )
    }

    static func canRenderProposal(
        _ proposal: RhythmicNotationMeasureProposal,
        requiresNaturalExactFitAfterErase: Bool,
        meter: Meter? = nil
    ) -> Bool {
        proposal.canRenderWithoutReview
            && LeadSheetRhythmicNotationFeedbackPolicy.valuesFitExactlyWithinMeter(proposal.values, meter: meter)
            && (!requiresNaturalExactFitAfterErase || proposal.isNaturalExactFit)
    }
}

enum LeadSheetRhythmicNotationLiveDecisionPolicy {
    enum Route: Equatable {
        case commit(proposal: RhythmicNotationMeasureProposal)
        case readyToRender(proposal: RhythmicNotationMeasureProposal)
        case preserveInk(showsUnreadFeedback: Bool)
    }

    static func route(
        for decision: RhythmRecognitionDecision,
        requiresNaturalExactFitAfterErase: Bool,
        allowsCommit: Bool = false,
        meter: Meter? = nil
    ) -> Route {
        switch decision {
        case .commit(let proposal, _)
            where LeadSheetRhythmicNotationAdvisoryPolicy.canRenderProposal(
                proposal,
                requiresNaturalExactFitAfterErase: requiresNaturalExactFitAfterErase,
                meter: meter
            ):
            guard allowsCommit else {
                return .readyToRender(proposal: proposal)
            }
            return .commit(proposal: proposal)
        case .commit, .keepWriting, .needsReview:
            return .preserveInk(
                showsUnreadFeedback: LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                    for: decision
                )
            )
        }
    }
}

enum LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy {
    static let persistsLiveInkDuringAdvisory = false

    static func shouldAnalyzeStableInk(
        interactionMode: EditorCanvasMode,
        selectedMeasureID: UUID?,
        targetMeasureID: UUID,
        currentInkSnapshot: LeadSheetInkDrawingSnapshot?,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) -> Bool {
        interactionMode.allowsDirectRhythmicNotationInk
            && selectedMeasureID == targetMeasureID
            && LeadSheetRhythmicNotationAdvisoryPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: currentInkSnapshot,
                scheduledInkSnapshot: scheduledInkSnapshot
            )
    }

    static func shouldCommitFromAdvisoryRoute(
        _ route: LeadSheetRhythmicNotationLiveDecisionPolicy.Route
    ) -> Bool {
        false
    }
}

private extension RhythmRecognitionDecision {
    var diagnosticDecisionText: String {
        switch self {
        case .commit:
            return "commit"
        case .keepWriting:
            return "keepWriting"
        case .needsReview:
            return "needsReview"
        }
    }
}

private extension LeadSheetRhythmicNotationLiveDecisionPolicy.Route {
    var isReadyToRender: Bool {
        if case .readyToRender = self {
            return true
        }

        return false
    }

    var diagnosticRouteText: String {
        switch self {
        case .commit:
            return "commit"
        case .readyToRender:
            return "readyToRender"
        case .preserveInk:
            return "preserveInk"
        }
    }
}

private extension RhythmicNotationMeasureProposalSafety {
    var diagnosticText: String {
        switch self {
        case .readyToRender:
            return "readyToRender"
        case .extendedStability:
            return "extendedStability"
        case .manualReview:
            return "manualReview"
        }
    }
}

struct LeadSheetRhythmicNotationPreviewState: Equatable {
    enum ConfirmationAction: Equatable {
        case none
        case confirmSuggestion
    }

    var measureID: UUID
    var meter: Meter
    var reason: RhythmRecognitionReason?
    var values: [RhythmValue]
    var tieOutSlotIndices: Set<Int> = []
    var confirmationAction: ConfirmationAction
    var isCertain: Bool

    var canConfirm: Bool {
        confirmationAction == .confirmSuggestion
    }
}

enum LeadSheetRhythmicNotationFeedbackPolicy {
    static func previewValues(for decision: RhythmRecognitionDecision, meter: Meter) -> [RhythmValue] {
        let values = previewValues(for: decision)
        guard valuesFitWithinMeter(values, meter: meter) else {
            return []
        }
        return values
    }

    static func previewValues(for decision: RhythmRecognitionDecision) -> [RhythmValue] {
        if decision.reason == .nonNaturalExactFit,
           let naturalValues = decision.phrase?.naturalValues,
           !naturalValues.isEmpty,
           naturalValues.contains(where: \.isDottedReferenceValue) {
            return naturalValues
        }

        if let values = decision.proposal?.values,
           !values.isEmpty {
            return values
        }

        if let values = decision.phrase?.naturalValues,
           !values.isEmpty {
            return values
        }

        return []
    }

    static func valuesFitWithinMeter(_ values: [RhythmValue], meter: Meter) -> Bool {
        guard !values.isEmpty else {
            return false
        }

        let units = values.reduce(0) { partialResult, value in
            partialResult + RhythmicNotationQuantizer.rhythmUnits(for: value, meter: meter)
        }
        return units <= RhythmicNotationQuantizer.rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
    }

    static func valuesFitExactlyWithinMeter(_ values: [RhythmValue], meter: Meter?) -> Bool {
        guard let meter else {
            return true
        }
        guard !values.isEmpty else {
            return false
        }

        let units = values.reduce(0) { partialResult, value in
            partialResult + RhythmicNotationQuantizer.rhythmUnits(for: value, meter: meter)
        }
        return units == RhythmicNotationQuantizer.rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
    }

    static func previewTieOutSlotIndices(for decision: RhythmRecognitionDecision) -> Set<Int> {
        decision.proposal?.tieOutSlotIndices ?? []
    }

    static func confirmationAction(
        for decision: RhythmRecognitionDecision,
        meter: Meter
    ) -> LeadSheetRhythmicNotationPreviewState.ConfirmationAction {
        guard hasFullPreviewSuggestion(for: decision, meter: meter) else {
            return .none
        }

        switch decision {
        case .commit:
            return .none
        case .needsReview:
            return .confirmSuggestion
        case .keepWriting(let reason, _):
            switch reason {
            case .ambiguousPhrase, .manualReview:
                return .confirmSuggestion
            case .noInk,
                 .underfilled,
                 .overflow,
                 .unsupported,
                 .nonNaturalExactFit,
                 .uncoveredStrokes:
                return .none
            }
        }
    }

    static func confirmationAction(for decision: RhythmRecognitionDecision) -> LeadSheetRhythmicNotationPreviewState.ConfirmationAction {
        guard hasFullPreviewSuggestion(for: decision) else {
            return .none
        }

        switch decision {
        case .commit:
            return .none
        case .needsReview:
            return .confirmSuggestion
        case .keepWriting(let reason, _):
            switch reason {
            case .ambiguousPhrase, .manualReview:
                return .confirmSuggestion
            case .noInk,
                 .underfilled,
                 .overflow,
                 .unsupported,
                 .nonNaturalExactFit,
                 .uncoveredStrokes:
                return .none
            }
        }
    }

    static func hasFullPreviewSuggestion(for decision: RhythmRecognitionDecision, meter: Meter) -> Bool {
        let values = previewValues(for: decision, meter: meter)
        guard !values.isEmpty,
              let phrase = decision.phrase,
              phrase.targetUnits > 0 else {
            return false
        }

        if let proposal = decision.proposal,
           proposal.values == values,
           proposal.isNaturalExactFit {
            return true
        }

        if values == phrase.naturalValues {
            return phrase.naturalUnits == phrase.targetUnits
        }

        return values.reduce(0) { partialResult, value in
            partialResult + RhythmicNotationQuantizer.rhythmUnits(for: value, meter: meter)
        } == phrase.targetUnits
    }

    static func hasFullPreviewSuggestion(for decision: RhythmRecognitionDecision) -> Bool {
        let values = previewValues(for: decision)
        guard !values.isEmpty,
              let phrase = decision.phrase,
              phrase.targetUnits > 0 else {
            return false
        }

        if let proposal = decision.proposal,
           proposal.values == values,
           proposal.isNaturalExactFit {
            return true
        }

        if values == phrase.naturalValues {
            return phrase.naturalUnits == phrase.targetUnits
        }

        return values.reduce(0) { partialResult, value in
            partialResult + RhythmicNotationQuantizer.rhythmUnits(for: value)
        } == phrase.targetUnits
    }

    static func shouldHighlightUnreadInk(for decision: RhythmRecognitionDecision) -> Bool {
        guard let phrase = decision.phrase else {
            return false
        }

        switch decision {
        case .commit:
            return false
        case .needsReview:
            guard phraseIsReadyForUnreadFeedback(phrase) else {
                return false
            }
            return true
        case .keepWriting(let reason, _):
            switch reason {
            case .noInk:
                return false
            case .underfilled:
                return phraseHasRecognizedInk(phrase)
            case .overflow,
                 .unsupported,
                 .nonNaturalExactFit,
                 .ambiguousPhrase,
                 .manualReview,
                 .uncoveredStrokes:
                return phraseIsReadyForUnreadFeedback(phrase)
            }
        }
    }

    static func feedbackMessage(for decision: RhythmRecognitionDecision) -> String? {
        guard let reason = decision.reason else {
            return nil
        }

        switch reason {
        case .noInk:
            return nil
        case .underfilled:
            guard let phrase = decision.phrase,
                  phrase.targetUnits > phrase.naturalUnits else {
                return "Measure is short"
            }
            return underfilledMessage(missingUnits: phrase.targetUnits - phrase.naturalUnits)
        case .overflow:
            return "Too many beats"
        case .unsupported, .uncoveredStrokes:
            return "Unread rhythm mark"
        case .nonNaturalExactFit:
            return "Does not fit measure"
        case .ambiguousPhrase, .manualReview:
            return "Check rhythm"
        }
    }

    static func unreadInkFrame(
        for drawing: PKDrawing,
        decision: RhythmRecognitionDecision,
        canvasFrame: CGRect,
        padding: CGFloat = 7
    ) -> CGRect? {
        guard let phrase = decision.phrase else {
            return nil
        }

        if decision.reason == .underfilled {
            guard phraseHasRecognizedInk(phrase) else {
                return nil
            }
            return unreadInkFrame(
                for: drawing,
                canvasFrame: canvasFrame,
                padding: padding
            )
        }

        guard phraseIsReadyForUnreadFeedback(phrase) else {
            return nil
        }

        if let phrase = decision.phrase,
           decision.reason == .uncoveredStrokes,
           let uncoveredFrame = unreadEvidenceFrame(
            phrase: phrase,
            strokeIndices: phrase.uncoveredStrokeIndices,
            canvasFrame: canvasFrame,
            padding: padding
           ) {
            return uncoveredFrame
        }

        if let phrase = decision.phrase,
           let unreadSymbolFrame = unreadSymbolFrame(
            phrase: phrase,
            canvasFrame: canvasFrame,
            padding: padding
           ) {
            return unreadSymbolFrame
        }

        return nil
    }

    static func staleInkFrame(
        for drawing: PKDrawing,
        decision: RhythmRecognitionDecision,
        canvasFrame: CGRect,
        padding: CGFloat = 7
    ) -> CGRect? {
        if let targetedFrame = unreadInkFrame(
            for: drawing,
            decision: decision,
            canvasFrame: canvasFrame,
            padding: padding
        ) {
            return targetedFrame
        }

        guard shouldShowStaleInkState(for: decision) else {
            return nil
        }

        return unreadInkFrame(
            for: drawing,
            canvasFrame: canvasFrame,
            padding: padding
        )
    }

    static func readyToRenderFrame(
        for drawing: PKDrawing,
        canvasFrame: CGRect,
        padding: CGFloat = 7
    ) -> CGRect? {
        unreadInkFrame(
            for: drawing,
            canvasFrame: canvasFrame,
            padding: padding
        )
    }

    static func unreadInkFrame(
        for drawing: PKDrawing,
        canvasFrame: CGRect,
        padding: CGFloat = 7
    ) -> CGRect? {
        let localBounds = drawing.strokes.reduce(into: CGRect.null) { partialResult, stroke in
            let points = Array(stroke.path).map(\.location)
            for point in points {
                partialResult = partialResult.union(CGRect(origin: point, size: .zero))
            }
        }
        guard !localBounds.isNull else {
            return nil
        }

        let paddedFrame = localBounds
            .insetBy(dx: -padding, dy: -padding)
            .offsetBy(dx: canvasFrame.minX, dy: canvasFrame.minY)
        return paddedFrame.isEmpty ? nil : paddedFrame
    }

    private static func phraseIsReadyForUnreadFeedback(_ phrase: RhythmPhraseHypothesis) -> Bool {
        phrase.targetUnits > 0 && phrase.naturalUnits >= phrase.targetUnits
    }

    private static func phraseHasRecognizedInk(_ phrase: RhythmPhraseHypothesis) -> Bool {
        phrase.naturalUnits > 0
            || !phrase.naturalValues.isEmpty
            || !phrase.symbols.isEmpty
            || !phrase.glyphEvidence.isEmpty
    }

    private static func underfilledMessage(missingUnits: Int) -> String {
        guard missingUnits > 0 else {
            return "Measure is short"
        }

        if missingUnits == 1 {
            return "Needs 1 more eighth"
        }
        if missingUnits % 2 == 0 {
            let beats = missingUnits / 2
            return beats == 1 ? "Needs 1 more beat" : "Needs \(beats) more beats"
        }
        return "Measure is short"
    }

    private static func shouldShowStaleInkState(for decision: RhythmRecognitionDecision) -> Bool {
        guard let phrase = decision.phrase else {
            return false
        }

        switch decision {
        case .commit:
            return false
        case .needsReview:
            return true
        case .keepWriting(let reason, _):
            switch reason {
            case .noInk:
                return false
            case .underfilled:
                return phrase.naturalUnits > 0
                    || !phrase.naturalValues.isEmpty
                    || !phrase.symbols.isEmpty
                    || !phrase.glyphEvidence.isEmpty
            case .overflow,
                 .unsupported,
                 .nonNaturalExactFit,
                 .ambiguousPhrase,
                 .manualReview,
                 .uncoveredStrokes:
                return true
            }
        }
    }

    private static func unreadEvidenceFrame(
        phrase: RhythmPhraseHypothesis,
        strokeIndices: [Int],
        canvasFrame: CGRect,
        padding: CGFloat
    ) -> CGRect? {
        guard !strokeIndices.isEmpty else {
            return nil
        }

        let indexedEvidence = Dictionary(
            uniqueKeysWithValues: phrase.glyphEvidence.flatMap { evidence in
                evidence.strokeIndices.map { strokeIndex in
                    (strokeIndex, evidence)
                }
            }
        )
        let localBounds = strokeIndices.reduce(into: CGRect.null) { partialResult, strokeIndex in
            guard let evidence = indexedEvidence[strokeIndex],
                  !evidence.bounds.isNull else {
                return
            }
            partialResult = partialResult.union(evidence.bounds)
        }
        guard !localBounds.isNull else {
            return nil
        }

        let paddedFrame = localBounds
            .insetBy(dx: -padding, dy: -padding)
            .offsetBy(dx: canvasFrame.minX, dy: canvasFrame.minY)
        return paddedFrame.isEmpty ? nil : paddedFrame
    }

    private static func unreadSymbolFrame(
        phrase: RhythmPhraseHypothesis,
        canvasFrame: CGRect,
        padding: CGFloat
    ) -> CGRect? {
        let unreadBounds = phrase.symbols.reduce(into: CGRect.null) { partialResult, symbol in
            guard symbol.selectedValue == nil,
                  !symbol.bounds.isNull,
                  !symbol.bounds.isEmpty else {
                return
            }
            partialResult = partialResult.union(symbol.bounds)
        }
        guard !unreadBounds.isNull else {
            return nil
        }

        let paddedFrame = unreadBounds
            .insetBy(dx: -padding, dy: -padding)
            .offsetBy(dx: canvasFrame.minX, dy: canvasFrame.minY)
        return paddedFrame.isEmpty ? nil : paddedFrame
    }
}

struct LeadSheetRhythmicNotationEraseRecovery {
    private(set) var measureRequiringNaturalExactFit: UUID?

    mutating func recordDrawingChange(
        selectedMeasureID: UUID?,
        inkToolMode: EditorInkToolMode
    ) -> Bool {
        guard let selectedMeasureID else {
            return false
        }

        switch inkToolMode {
        case .write:
            if measureRequiringNaturalExactFit == selectedMeasureID {
                measureRequiringNaturalExactFit = nil
            }
            return false
        case .erase:
            measureRequiringNaturalExactFit = selectedMeasureID
            return true
        }
    }

    mutating func reset() {
        measureRequiringNaturalExactFit = nil
    }

    func requiresNaturalExactFit(for measureID: UUID) -> Bool {
        measureRequiringNaturalExactFit == measureID
    }
}

enum LeadSheetLiveInkCanvasAppearancePolicy {
    static func configure(_ canvasView: PKCanvasView) {
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
    }
}

final class LeadSheetCanvasUIKitView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    func applyParentSelectionState(
        selectedMeasureID: UUID?,
        selectedNoteSelection: LeadSheetNoteSelection?,
        selectedChordID: UUID?,
        selectedCommittedBarlineMeasureID: UUID?,
        selectedCueTextID: UUID?,
        selectedRoadmapMarkerID: UUID?
    ) {
        isSyncingSelectionFromSwiftUI = true
        defer { isSyncingSelectionFromSwiftUI = false }

        self.selectedMeasureID = selectedMeasureID
        self.selectedNoteSelection = selectedNoteSelection
        self.selectedChordID = selectedChordID
        self.selectedCommittedBarlineMeasureID = selectedCommittedBarlineMeasureID
        self.selectedCueTextID = selectedCueTextID
        self.selectedRoadmapMarkerID = selectedRoadmapMarkerID
    }

    var chart: Chart = .draft(title: "Preview") {
        didSet {
            guard oldValue != chart else {
                return
            }

            ChordLaneLocalBreadcrumbs.record(
                "chart_changed",
                fields: [
                    "mode": interactionMode,
                    "oldMeasureCount": oldValue.measures.count,
                    "newMeasureCount": chart.measures.count,
                    "oldChordCount": oldValue.measures.reduce(0) { $0 + $1.chordEvents.count },
                    "newChordCount": chart.measures.reduce(0) { $0 + $1.chordEvents.count }
                ]
            )
            if hasNewChordEvent(from: oldValue, to: chart) {
                suppressChordObjectEditingTemporarily()
            }
            if let selectedChordID,
               chart.chordEvent(id: selectedChordID) == nil {
                self.selectedChordID = nil
            }
            if let selectedCommittedBarlineMeasureID,
               !chart.canDeleteCommittedSimpleChordBarline(after: selectedCommittedBarlineMeasureID) {
                self.selectedCommittedBarlineMeasureID = nil
            }
            if let selectedRoadmapMarkerID,
               chart.roadmapObject(id: selectedRoadmapMarkerID) == nil {
                updateSelectedRoadmapMarkerID(nil)
            }
            if let selectedCueTextID,
               chart.cueText(id: selectedCueTextID) == nil {
                self.selectedCueTextID = nil
            }
            if let activeCueTextMoveDrag,
               chart.cueText(id: activeCueTextMoveDrag.cueTextID) == nil {
                self.activeCueTextMoveDrag = nil
            }
            invalidateLayout()
        }
    }
    var inkToolMode: EditorInkToolMode = .write {
        didSet {
            guard oldValue != inkToolMode else {
                return
            }

            updateInteractionMode()
        }
    }
    var recognizesChordInk = true {
        didSet {
            guard oldValue != recognizesChordInk else {
                return
            }

            if !recognizesChordInk {
                chordInkRecognitionRequestState.cancelPendingRequest()
            }
            updateChordInkConfirmOverlayVisibility()
        }
    }
    var chordPreviewState = ChordPreviewState() {
        didSet {
            guard oldValue != chordPreviewState else {
                return
            }

            if let selectedDraftBarlineID,
               !chordPreviewState.draftBarlines.contains(where: { $0.id == selectedDraftBarlineID }) {
                self.selectedDraftBarlineID = nil
            }
            setNeedsDisplay()
        }
    }
    var selectedMeasureID: UUID? {
        didSet {
            guard oldValue != selectedMeasureID else {
                return
            }

            ChordLaneLocalBreadcrumbs.record(
                "selected_measure_changed",
                fields: [
                    "mode": interactionMode,
                    "hadOld": oldValue != nil,
                    "hasNew": selectedMeasureID != nil
                ]
            )
            if shouldFinalizeRhythmicNotation(from: oldValue, to: selectedMeasureID),
               let oldValue,
               !finalizeRhythmicNotationIfNeeded(for: oldValue) {
                restoreSelectedMeasureID(oldValue)
                return
            }

            clearRhythmicNotationUnreadInkFeedback()
            syncPageInkCanvas()
            setNeedsDisplay()
        }
    }
    var selectedNoteSelection: LeadSheetNoteSelection? {
        didSet {
            guard oldValue != selectedNoteSelection else {
                return
            }

            setNeedsDisplay()
        }
    }
    var selectedCueTextID: UUID? {
        didSet {
            guard oldValue != selectedCueTextID else {
                return
            }

            if !isSyncingSelectionFromSwiftUI {
                onCueTextSelectionChanged?(selectedCueTextID)
            }
            setNeedsDisplay()
        }
    }
    var selectedRoadmapMarkerID: UUID? {
        didSet {
            guard oldValue != selectedRoadmapMarkerID else {
                return
            }

            setNeedsDisplay()
        }
    }
    var restrictsParentScrollToOutsideMargins: Bool = false {
        didSet {
            parentScrollGestureGate.updateCanvasView(self)
            setNeedsDisplay()
        }
    }
    var interactionMode: EditorCanvasMode = .browse {
        didSet {
            guard oldValue != interactionMode else {
                return
            }

            ChordLaneLocalBreadcrumbs.record(
                "interaction_mode_changed",
                fields: [
                    "oldMode": oldValue,
                    "newMode": interactionMode,
                    "canvasStrokes": pageInkCanvasView.drawing.strokes.count,
                    "chordDraftCount": chordPreviewState.draftChords.count,
                    "barlineDraftCount": chordPreviewState.draftBarlines.count
                ]
            )
            let previousActiveInkScope = activeInkScope(for: oldValue)
            let nextActiveInkScope = activeInkScope(for: interactionMode)
            if LeadSheetInkCanvasSyncPolicy.shouldPersistOutgoingCanvas(
                previousActiveInkScope: previousActiveInkScope,
                nextActiveInkScope: nextActiveInkScope
            ) {
                persistActiveInkIfNeeded(activeInkScope: previousActiveInkScope)
            }

            if oldValue.allowsDirectRhythmicNotationInk && !interactionMode.allowsDirectRhythmicNotationInk {
                cancelPendingRhythmicNotationAdvisoryWork()
                clearRhythmicNotationUnreadInkFeedback()
            }

            if oldValue.allowsNoteSelectionInk && !interactionMode.allowsNoteSelectionInk {
                clearNoteSelectionInk()
            }

            if interactionMode != .browse {
                activeRoadmapMarkerEditDrag = nil
            }

            if !interactionMode.allowsCueTextEditing {
                activeCueTextMoveDrag = nil
            }

            if oldValue.allowsChordObjectEditing && !interactionMode.allowsChordObjectEditing {
                selectedChordID = nil
                activeChordMoveDrag = nil
                activeChordResizeDrag = nil
                unlockParentScrollForChordMove()
            }

            updateInteractionMode()
            if LeadSheetCanvasLayoutInvalidationPolicy.requiresLayoutRefresh(
                previousMode: oldValue,
                nextMode: interactionMode
            ) {
                invalidateLayout()
            } else {
                syncPageInkCanvas()
                setNeedsDisplay()
            }
        }
    }
    var onMeasureSelectionChanged: ((UUID?) -> Void)?
    var onChartChanged: ((Chart) -> Void)?
    var onTimeSignatureTargetRequested: ((UUID) -> Void)?
    var onChordInkRecognitionProposal: ((UUID, ChordInkRecognitionResult, Data, Double?, ChordInkRecognitionTiming, ChordInkRecognitionFlow) -> Void)?
    var onChordInkBatchRecognitionProposal: (([ChordInkRecognitionProposalPayload], ChordInkRecognitionFlow) -> Void)?
    var onChordInkDraftPreviewChanged: (([ChordInkRecognitionProposalPayload]) -> Void)?
    var onChordInkDraftBarlinesChanged: (([DraftBarline]) -> Void)?
    var onChordCorrectionRequested: ((UUID) -> Void)?
    var onChordDeleted: ((ChordEvent) -> Void)?
    var onNoteSelectionChanged: ((LeadSheetNoteSelection?) -> Void)?
    var onChordSelectionChanged: ((UUID?) -> Void)?
    var onCommittedChordBarlineSelectionChanged: ((UUID?) -> Void)?
    var onCueTextSelectionChanged: ((UUID?) -> Void)?
    var onRoadmapMarkerSelectionChanged: ((UUID?) -> Void)?
    var onMeasureSelectedFromCanvas: ((UUID) -> Void)?
    var onChordSelectedFromCanvas: ((UUID) -> Void)?
    var onCueTextSelectedFromCanvas: ((UUID) -> Void)?
    var onCueTextEditRequested: ((UUID) -> Void)?
    var onRoadmapMarkerSelectedFromCanvas: ((UUID) -> Void)?
    var onRepeatSpanSelectedFromCanvas: ((UUID) -> Void)?
    var onEndingSpanSelectedFromCanvas: ((UUID) -> Void)?
    var onTimeSignatureSelectedFromCanvas: ((UUID) -> Void)?
    var onHeaderAuthoringRequested: (() -> Void)?
    var onRhythmicNotationPreviewChanged: ((LeadSheetRhythmicNotationPreviewState?) -> Void)?
    var onRhythmicNotationDiagnostic: ((RhythmRecognitionDiagnosticEvent) -> Void)?

    private var pageLayout: LeadSheetPageLayout?
    private let pageInkCanvasView = LeadSheetScopedInkCanvasView()
    private let chordInkConfirmOverlayView = LeadSheetChordInkConfirmOverlayView()
    private let renderedEditHitOverlayView = RenderedEditHitOverlayView()
    private let parentScrollGestureGate = LeadSheetParentScrollGestureGate()
    private let chordInkRecognizer = ChordInkRecognizer()
    private var chordInkRecognitionOptions: ChordInkRecognitionOptions {
        var options = ChordInkRecognitionOptions.live
        #if DEBUG && targetEnvironment(simulator)
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-iChartSymbolLedgerDiagnostics")
            || processInfo.environment["ICHART_SYMBOL_LEDGER_DIAGNOSTICS"] == "1" {
            options.includesSymbolLedgerDiagnostics = true
        }
        #endif

        return options
    }
    private let chordInkRecognitionQueue = DispatchQueue(
        label: "com.ichart.chord-ink-recognition",
        qos: .userInitiated
    )
    private lazy var chordInkRecognitionSession = ChordInkRecognitionSession(
        queue: chordInkRecognitionQueue,
        recognizer: chordInkRecognizer
    )
    private lazy var selectionTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleTap(_:))
    )
    private lazy var inkSelectionTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleTap(_:))
    )
    private lazy var measureResizePanRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleMeasureResizePan(_:))
    )
    private lazy var renderedObjectMovePanRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleRenderedObjectMovePan(_:))
    )
    private lazy var renderedEditTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleRenderedEditTapGesture(_:))
    )
    private lazy var chordCorrectionDoubleTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleChordCorrectionDoubleTap(_:))
    )
    private lazy var chordInkConfirmTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleChordInkConfirmTap(_:))
    )
    private var isSyncingInkCanvasFromModel = false
    private var inkAuthoringSessionState = LeadSheetInkAuthoringSessionState()
    var inkResponsivenessValue: Double = LeadSheetInkResponsivenessPolicy.defaultValue
    private var inkSchedulingCoordinator = LeadSheetInkSchedulingCoordinator()
    private var rhythmicNotationEraseRecovery = LeadSheetRhythmicNotationEraseRecovery()
    private var activeCanvasScopeIdentity: LeadSheetActiveInkScope.Identity?
    private var activeCanvasScope: LeadSheetActiveInkScope?
    private var activeCanvasCoordinateSpace: PersistentInkCoordinateSpace?
    private var inkPersistenceCoordinator = LeadSheetInkPersistenceCoordinator()
    private var chordObjectEditingSuppressedUntil: Date?
    private var lastHandledChordDraftRenderInvalidationRequestID: UUID?
    private var lastBootstrappedChordDraftPreviewSnapshot: LeadSheetInkDrawingSnapshot?
    private var lastHandledRhythmicNotationPreviewConfirmationRequestID: UUID?
    private var rhythmicNotationPreviewState: LeadSheetRhythmicNotationPreviewState? {
        didSet {
            onRhythmicNotationPreviewChanged?(rhythmicNotationPreviewState)
        }
    }
    private var chordInkRecognitionRequestState = LeadSheetChordInkRecognitionRequestState()
    private var activeMeasureResizeDrag: ActiveMeasureResizeDrag?
    private var activeChordMoveDrag: ActiveChordMoveDrag?
    private var activeChordResizeDrag: ActiveChordResizeDrag?
    private var activeRoadmapMarkerEditDrag: ActiveRoadmapMarkerEditDrag?
    private var activeCueTextMoveDrag: ActiveCueTextMoveDrag?
    private var parentScrollLockCoordinator = LeadSheetParentScrollLockCoordinator()
    private var isSyncingSelectionFromSwiftUI = false
    var selectedChordID: UUID? {
        didSet {
            guard oldValue != selectedChordID else {
                return
            }

            if !isSyncingSelectionFromSwiftUI {
                onChordSelectionChanged?(selectedChordID)
            }
            setNeedsDisplay()
        }
    }
    private var selectedDraftBarlineID: UUID?
    var selectedCommittedBarlineMeasureID: UUID? {
        didSet {
            guard oldValue != selectedCommittedBarlineMeasureID else {
                return
            }

            if !isSyncingSelectionFromSwiftUI {
                onCommittedChordBarlineSelectionChanged?(selectedCommittedBarlineMeasureID)
            }
            setNeedsDisplay()
        }
    }
    private var isRestoringSelection = false
    private var isApplyingTapSelection = false
    private var performanceLayoutTraceCount = 0
    private var performanceDrawTraceCount = 0
    private var activePerformanceTraceDrawIndex: Int?
    private var editorPerformanceMetrics = LeadSheetEditorPerformanceMetrics()
    private var notationRenderer: LeadSheetNotationRenderer {
        LeadSheetNotationRenderer(chart: chart)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            editorPerformanceMetrics.flush(reason: "removed_from_window")
            inkPersistenceCoordinator.flushMetrics(reason: "removed_from_window")
        }
        updateParentScrollGestureGate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        chordInkConfirmOverlayView.frame = bounds
        renderedEditHitOverlayView.frame = bounds
        invalidateLayout()
        updateParentScrollGestureGate()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let pageLayout else {
            return
        }

        let drawIndex = nextPerformanceDrawTraceIndex()
        let drawSpan = drawIndex.map { index in
            IChartPerformanceTrace.start(
                "editor.canvas.draw",
                metadata: canvasPerformanceTraceMetadata(
                    extra: [
                        "drawIndex": "\(index)",
                        "rect": "\(Int(rect.width))x\(Int(rect.height))",
                        "systems": "\(pageLayout.systems.count)"
                    ]
                )
            )
        }
        let firstDrawSpan = drawIndex == 1
            ? IChartPerformanceTrace.start(
                "editor.canvas.firstDraw",
                metadata: canvasPerformanceTraceMetadata(
                    extra: [
                        "rect": "\(Int(rect.width))x\(Int(rect.height))",
                        "systems": "\(pageLayout.systems.count)"
                    ]
                )
            )
            : nil
        activePerformanceTraceDrawIndex = drawIndex
        defer {
            if let firstDrawSpan {
                IChartPerformanceTrace.end(firstDrawSpan)
            }
            if let drawSpan {
                IChartPerformanceTrace.end(drawSpan)
            }
            activePerformanceTraceDrawIndex = nil
        }

        let renderer = notationRenderer
        context.clear(rect)
        for paperFrame in pageLayout.paperFrames {
            renderer.drawPaper(paperFrame, in: context)
        }
        if restrictsParentScrollToOutsideMargins {
            drawPageScrollDragAreas(pageLayout)
        }
        renderer.drawHeader(pageLayout.header)

        if !interactionMode.allowsHeaderInkEditing,
           chart.headerInputMode == .handwritten {
            drawSavedHeaderInk()
        }

        if interactionMode.allowsChordInkEditing {
            drawChordWritingLanes(pageLayout)
        }

        for system in pageLayout.systems {
            drawSystem(
                system,
                paperFrame: pageLayout.paperFrame(for: system),
                using: renderer
            )
        }

        if !interactionMode.allowsPageInkEditing {
            drawSavedPageInk()
        }

        if interactionMode.allowsChordInkEditing {
            drawChordDraftPreview(pageLayout)
        }

        if interactionMode.allowsChordInkEditing || interactionMode.allowsChordObjectEditing {
            drawSelectedCommittedChordBarline(in: pageLayout)
        }

        if showsSelectedMeasureResizeHandles {
            if let rowGroupAffordance = simpleRowGroupAffordance() {
                drawSimpleRowGroupAffordance(rowGroupAffordance)
            }
            if let preview = activeMeasureResizeDrag?.currentPreview {
                drawMeasureResizePreviewGuides(preview)
            }
            if let selectedMeasure = selectedDisplayMeasureLayout() {
                drawMeasureResizeHandles(for: selectedMeasure, using: renderer)
            }
        }
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        selectionTapRecognizer.delegate = self
        addGestureRecognizer(selectionTapRecognizer)
        measureResizePanRecognizer.delegate = self
        selectionTapRecognizer.require(toFail: measureResizePanRecognizer)
        addGestureRecognizer(measureResizePanRecognizer)

        LeadSheetLiveInkCanvasAppearancePolicy.configure(pageInkCanvasView)
        pageInkCanvasView.delegate = self
        pageInkCanvasView.manualEraseHandler = { [weak self] startPoint, endPoint in
            self?.eraseActiveInk(from: startPoint, to: endPoint)
        }
        pageInkCanvasView.isScrollEnabled = false
        pageInkCanvasView.bounces = false
        pageInkCanvasView.alwaysBounceVertical = false
        pageInkCanvasView.alwaysBounceHorizontal = false
        pageInkCanvasView.drawingPolicy = .anyInput
        pageInkCanvasView.tool = LeadSheetPersistentInkColorPolicy.inkingTool(width: 2.8)
        inkSelectionTapRecognizer.delegate = self
        inkSelectionTapRecognizer.cancelsTouchesInView = false
        pageInkCanvasView.addGestureRecognizer(inkSelectionTapRecognizer)
        pageInkCanvasView.isHidden = true
        addSubview(pageInkCanvasView)

        chordInkConfirmOverlayView.backgroundColor = .clear
        chordInkConfirmOverlayView.isOpaque = false
        chordInkConfirmOverlayView.isHidden = true
        chordInkConfirmOverlayView.containsConfirmSurface = { [weak self] location in
            self?.chordInkConfirmSurfaceContains(location) ?? false
        }
        chordInkConfirmTapRecognizer.delegate = self
        chordInkConfirmTapRecognizer.cancelsTouchesInView = false
        chordInkConfirmOverlayView.addGestureRecognizer(chordInkConfirmTapRecognizer)
        addSubview(chordInkConfirmOverlayView)

        renderedEditHitOverlayView.backgroundColor = .clear
        renderedEditHitOverlayView.isOpaque = false
        renderedEditHitOverlayView.isHidden = true
        renderedEditHitOverlayView.containsEditableControl = { [weak self] location in
            self?.editableOverlayHitTarget(at: location) != nil
        }
        renderedEditTapRecognizer.delegate = self
        chordCorrectionDoubleTapRecognizer.delegate = self
        chordCorrectionDoubleTapRecognizer.numberOfTapsRequired = 2
        renderedEditTapRecognizer.require(toFail: chordCorrectionDoubleTapRecognizer)
        renderedEditHitOverlayView.addGestureRecognizer(chordCorrectionDoubleTapRecognizer)
        renderedEditHitOverlayView.addGestureRecognizer(renderedEditTapRecognizer)
        renderedObjectMovePanRecognizer.delegate = self
        addGestureRecognizer(renderedObjectMovePanRecognizer)
        addSubview(renderedEditHitOverlayView)
        updateInteractionMode()
    }

    private func updateParentScrollGestureGate() {
        guard let scrollView = enclosingParentScrollView() else {
            parentScrollGestureGate.uninstall()
            return
        }

        parentScrollGestureGate.install(in: scrollView, canvasView: self)
    }

    private func enclosingParentScrollView() -> UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }

            candidate = view.superview
        }

        return nil
    }

    private func isParentScrollGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let scrollView = enclosingParentScrollView() else {
            return false
        }

        return gestureRecognizer === scrollView.panGestureRecognizer
            || gestureRecognizer === scrollView.pinchGestureRecognizer
    }

    private func lockParentScrollForChordMove() {
        parentScrollLockCoordinator.lock(enclosingParentScrollView())
    }

    private func unlockParentScrollForChordMove() {
        parentScrollLockCoordinator.unlock()
    }

    fileprivate func allowsParentScrollGestureStart(at point: CGPoint) -> Bool {
        guard restrictsParentScrollToOutsideMargins else {
            return true
        }

        if measureResizeHandleHitTarget(at: point) != nil
            || editableOverlayHitTarget(at: point) != nil {
            return false
        }

        guard let pageLayout else {
            return true
        }

        return !pageLayout.containsPaper(point, hitSlop: LeadSheetScrollMarginPolicy.paperHitSlop)
    }

    fileprivate func shouldBlockParentScrollTouch(_ touch: UITouch) -> Bool {
        LeadSheetParentScrollTouchPolicy.blocksParentScrollStart(
            touchType: touch.type,
            interactionMode: interactionMode
        )
    }

    private func invalidateLayout() {
        editorPerformanceMetrics.recordLayoutInvalidation()
        guard bounds.width > 0, bounds.height > 0 else {
            pageLayout = nil
            syncPageInkCanvas()
            setNeedsDisplay()
            return
        }

        let layoutIndex = nextPerformanceLayoutTraceIndex()
        let layoutSpan = layoutIndex.map { index in
            IChartPerformanceTrace.start(
                "editor.canvas.layout",
                metadata: canvasPerformanceTraceMetadata(
                    extra: [
                        "layoutIndex": "\(index)",
                        "pageSize": "\(Int(bounds.width))x\(Int(bounds.height))"
                    ]
                )
            )
        }
        pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: bounds.size,
            includesChordInkContinuationLanes: interactionMode.allowsChordInkEditing
        )
        if let layoutSpan {
            IChartPerformanceTrace.end(layoutSpan)
        }
        syncPageInkCanvas()
        setNeedsDisplay()
    }

    private func nextPerformanceLayoutTraceIndex() -> Int? {
        guard performanceLayoutTraceCount < 8 else {
            return nil
        }

        performanceLayoutTraceCount += 1
        return performanceLayoutTraceCount
    }

    private func nextPerformanceDrawTraceIndex() -> Int? {
        guard performanceDrawTraceCount < 8 else {
            return nil
        }

        performanceDrawTraceCount += 1
        return performanceDrawTraceCount
    }

    private func canvasPerformanceTraceMetadata(extra: [String: String] = [:]) -> [String: String] {
        var metadata = [
            "layoutStyle": chart.layoutStyle.rawValue,
            "completedSetup": chart.hasCompletedInitialSetup ? "true" : "false",
            "measureCount": "\(chart.measures.count)",
            "interactionMode": interactionMode.activeToolTitle,
            "inkToolMode": inkToolMode.rawValue
        ]
        for (key, value) in extra {
            metadata[key] = value
        }
        return metadata
    }

    private func applyUpdatedChart(_ updatedChart: Chart, reason _: String) {
        chart = updatedChart
        editorPerformanceMetrics.recordChartWriteBack()
        onChartChanged?(updatedChart)
    }

    private func drawSystem(
        _ system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        using renderer: LeadSheetNotationRenderer
    ) {
        if let sectionTextFrame = system.sectionTextFrame,
           let sectionText = system.sectionText {
            renderer.drawSectionText(sectionText, in: sectionTextFrame)
        }

        if let roadmapTextFrame = system.roadmapTextFrame,
           let roadmapText = system.roadmapText {
            renderer.drawRoadmapText(roadmapText, in: roadmapTextFrame)
        }

        for roadmapMarkerLayout in system.roadmapMarkerLayouts {
            let roadmapMarkerLayoutForDisplay = displayRoadmapMarkerLayout(for: roadmapMarkerLayout)
            renderer.drawRoadmapMarker(roadmapMarkerLayoutForDisplay)
            if roadmapMarkerLayoutForDisplay.id == selectedRoadmapMarkerID {
                drawRoadmapMarkerEditOverlay(roadmapMarkerLayoutForDisplay, using: renderer)
            }
        }

        for endingLayout in system.endingLayouts {
            renderer.drawEnding(endingLayout)
        }

        if let activePerformanceTraceDrawIndex {
            let staffSpan = IChartPerformanceTrace.start(
                "editor.renderer.drawStaffLines",
                metadata: canvasPerformanceTraceMetadata(
                    extra: [
                        "drawIndex": "\(activePerformanceTraceDrawIndex)",
                        "systemIndex": "\(system.index)"
                    ]
                )
            )
            renderer.drawStaffLines(for: system)
            IChartPerformanceTrace.end(staffSpan)
        } else {
            renderer.drawStaffLines(for: system)
        }

        if let clefFrame = system.clefFrame {
            if let activePerformanceTraceDrawIndex {
                let clefSpan = IChartPerformanceTrace.start(
                    "editor.renderer.drawClef",
                    metadata: canvasPerformanceTraceMetadata(
                        extra: [
                            "drawIndex": "\(activePerformanceTraceDrawIndex)",
                            "systemIndex": "\(system.index)"
                        ]
                    )
                )
                renderer.drawClef(in: clefFrame)
                IChartPerformanceTrace.end(clefSpan)
            } else {
                renderer.drawClef(in: clefFrame)
            }
        }

        if let activePerformanceTraceDrawIndex {
            let keySignatureSpan = IChartPerformanceTrace.start(
                "editor.renderer.drawKeySignature",
                metadata: canvasPerformanceTraceMetadata(
                    extra: [
                        "drawIndex": "\(activePerformanceTraceDrawIndex)",
                        "systemIndex": "\(system.index)",
                        "symbolCount": "\(system.keySignatureLayouts.count)"
                    ]
                )
            )
            renderer.drawKeySignature(system.keySignatureLayouts)
            IChartPerformanceTrace.end(keySignatureSpan)
        } else {
            renderer.drawKeySignature(system.keySignatureLayouts)
        }

        if let keyTextFrame = system.keyTextFrame,
           let keyText = system.keyText {
            renderer.drawKeyText(keyText, in: keyTextFrame)
        }

        if chart.hasCompletedInitialSetup,
           let timeSignatureFrame = system.timeSignatureFrame {
            if let activePerformanceTraceDrawIndex {
                let timeSignatureSpan = IChartPerformanceTrace.start(
                    "editor.renderer.drawTimeSignature",
                    metadata: canvasPerformanceTraceMetadata(
                        extra: [
                            "drawIndex": "\(activePerformanceTraceDrawIndex)",
                            "systemIndex": "\(system.index)"
                        ]
                    )
                )
                renderer.drawTimeSignature(chart.defaultMeter, in: timeSignatureFrame)
                IChartPerformanceTrace.end(timeSignatureSpan)
            } else {
                renderer.drawTimeSignature(chart.defaultMeter, in: timeSignatureFrame)
            }
        }

        var drawnRepeatMarkerIDs = Set<String>()
        if let firstMeasure = system.measures.first {
            let leadingMarkers = LeadSheetRepeatBoundaryPolicy.leadingMarkers(atStartOf: firstMeasure)
            if leadingMarkers.isEmpty {
                renderer.drawLeadingBarline(
                    firstMeasure.leadingBarline ?? .single,
                    at: firstMeasure.leadingBarlineX,
                    from: firstMeasure.staffFrame.minY,
                    to: firstMeasure.staffFrame.maxY
                )
            } else {
                drawRepeatMarkers(leadingMarkers, using: renderer)
                drawnRepeatMarkerIDs.formUnion(LeadSheetRepeatBoundaryPolicy.markerIDs(leadingMarkers))
            }
        }

        for (measureIndex, measure) in system.measures.enumerated() {
            if interactionMode.allowsMeasureSelection,
               selectedRoadmapMarkerID == nil,
               measure.sourceMeasureID == selectedMeasureID {
                drawMeasureSelection(measure, in: system)
            }

            let leadingMarkers = measure.repeatMarkerLayouts.filter {
                $0.edge == .leading && !drawnRepeatMarkerIDs.contains($0.id)
            }
            drawRepeatMarkers(leadingMarkers, using: renderer)
            drawnRepeatMarkerIDs.formUnion(LeadSheetRepeatBoundaryPolicy.markerIDs(leadingMarkers))

            for chordLayout in measure.chordLayouts {
                let chordLayoutForDisplay = displayChordLayout(for: chordLayout)
                renderer.drawChord(chordLayoutForDisplay)
                if interactionMode.allowsChordObjectEditing,
                   measure.sourceMeasureID != nil,
                   shouldDrawChordEditOverlay(for: chordLayoutForDisplay) {
                    drawChordEditOverlay(for: chordLayoutForDisplay, using: renderer)
                }
            }

            for (noteIndex, noteLayout) in measure.noteLayouts.enumerated() {
                if isSelectedNote(noteIndex: noteIndex, in: measure) {
                    drawNoteSelection(noteLayout)
                }
                renderer.drawNote(noteLayout)
            }

            for cueTextLayout in measure.cueTextLayouts {
                let cueTextLayoutForDisplay = displayCueTextLayout(for: cueTextLayout)
                if cueTextLayoutForDisplay.id == selectedCueTextID {
                    drawCueTextSelection(cueTextLayoutForDisplay)
                }
                renderer.drawCueText(cueTextLayoutForDisplay)
            }

            drawSavedMeasureRhythmicNotation(measure)

            if let meterChange = measure.meterChange,
               let meterChangeFrame = measure.meterChangeFrame {
                renderer.drawTimeSignature(meterChange, in: meterChangeFrame)
            }

            if measure.isOpen && chart.layoutStyle != .simpleChordSheet {
                renderer.drawOpenMeasureHint(measure)
            } else {
                let nextMeasureIndex = measureIndex + 1
                let nextMeasure = system.measures.indices.contains(nextMeasureIndex)
                    ? system.measures[nextMeasureIndex]
                    : nil
                let boundary = LeadSheetSimpleChordTerminalBarlineGeometry.renderedBoundary(
                    after: measure,
                    before: nextMeasure,
                    excludingRepeatMarkerIDs: drawnRepeatMarkerIDs,
                    in: system,
                    paperFrame: paperFrame,
                    layoutStyle: chart.layoutStyle
                )

                switch boundary {
                case .repeatBoundary(let repeatBoundaryMarkers, let terminalTrailingLineX):
                    drawRepeatMarkers(
                        repeatBoundaryMarkers,
                        terminalTrailingLineX: terminalTrailingLineX,
                        using: renderer
                    )
                    drawnRepeatMarkerIDs.formUnion(LeadSheetRepeatBoundaryPolicy.markerIDs(repeatBoundaryMarkers))
                case .normalBarline(let barline, let frame):
                    renderer.drawBarline(barline, in: frame)
                case .none:
                    break
                }
            }
        }

        if LeadSheetSimpleChordTerminalBarlineGeometry.shouldDrawStandaloneTerminalBarline(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: chart.layoutStyle
        ) {
            renderer.drawSimpleChordStanzaTerminalBarline(for: system, paperFrame: paperFrame)
        }
    }

    private func drawRepeatMarkers(
        _ repeatMarkers: [LeadSheetRepeatMarkerLayout],
        terminalTrailingLineX: CGFloat? = nil,
        using renderer: LeadSheetNotationRenderer
    ) {
        guard !repeatMarkers.isEmpty else {
            return
        }

        renderer.drawRepeatBoundary(
            repeatMarkers,
            terminalTrailingLineX: terminalTrailingLineX
        )
    }

    private func drawMeasureSelection(_ measure: LeadSheetMeasureLayout, in system: LeadSheetSystemLayout) {
        let displayMeasure = displayMeasureLayout(measure, in: system)
        var selectionRect = displayMeasure.frame.insetBy(dx: 2, dy: 10)
        if displayMeasure.trailingBarlineFrame.midX > measure.trailingBarlineFrame.midX {
            selectionRect.size.width = max(
                1,
                displayMeasure.trailingBarlineFrame.midX - selectionRect.minX
            )
        }
        let selectionPath = UIBezierPath(roundedRect: selectionRect, cornerRadius: 8)
        UIColor(red: 0.89, green: 0.94, blue: 1, alpha: 0.42).setFill()
        selectionPath.fill()
        UIColor(red: 0.21, green: 0.43, blue: 0.83, alpha: 0.45).setStroke()
        selectionPath.lineWidth = 1.2
        selectionPath.stroke()
    }

    private func drawNoteSelection(_ noteLayout: LeadSheetNoteLayout) {
        let selectionRect = noteLayout.selectionFrame.insetBy(dx: -3, dy: -3)
        let selectionPath = UIBezierPath(roundedRect: selectionRect, cornerRadius: 9)
        UIColor(red: 1.0, green: 0.85, blue: 0.18, alpha: 0.28).setFill()
        selectionPath.fill()
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.84).setStroke()
        selectionPath.lineWidth = 1.4
        selectionPath.stroke()
    }

    private func drawCueTextSelection(_ cueTextLayout: LeadSheetCueTextLayout) {
        let editFrame = LeadSheetCueTextEditOverlayGeometry.editFrame(for: cueTextLayout)
        let selectionPath = UIBezierPath(roundedRect: editFrame, cornerRadius: 7)
        UIColor(red: 0.91, green: 0.96, blue: 1.0, alpha: 0.5).setFill()
        selectionPath.fill()
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.78).setStroke()
        selectionPath.lineWidth = 1.2
        selectionPath.stroke()

        let controlFrames = LeadSheetCueTextEditOverlayGeometry.controlFrames(for: cueTextLayout)
        drawCueTextEditControl(controlFrames.edit, label: "Aa")
        drawCueTextEditControl(controlFrames.shrink, label: "-")
        drawCueTextEditControl(controlFrames.grow, label: "+")
        drawCueTextEditControl(
            controlFrames.delete,
            label: "x",
            fillColor: UIColor(red: 0.99, green: 0.91, blue: 0.89, alpha: 0.96),
            strokeColor: UIColor(red: 0.72, green: 0.18, blue: 0.15, alpha: 0.72),
            textColor: UIColor(red: 0.66, green: 0.12, blue: 0.11, alpha: 0.95)
        )
    }

    private func drawCueTextEditControl(
        _ frame: CGRect,
        label: String,
        fillColor: UIColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.98),
        strokeColor: UIColor = UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.72),
        textColor: UIColor = UIColor(red: 0.14, green: 0.27, blue: 0.58, alpha: 0.96)
    ) {
        let controlPath = UIBezierPath(roundedRect: frame, cornerRadius: 6)
        fillColor.setFill()
        controlPath.fill()
        strokeColor.setStroke()
        controlPath.lineWidth = 1
        controlPath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: textColor
        ]
        let textSize = label.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: frame.midX - textSize.width / 2,
            y: frame.midY - textSize.height / 2
        )
        label.draw(at: textOrigin, withAttributes: attributes)
    }

    private func drawObjectSelection(_ frame: CGRect, cornerRadius: CGFloat) {
        let selectionPath = UIBezierPath(roundedRect: frame, cornerRadius: cornerRadius)
        UIColor(red: 1.0, green: 0.85, blue: 0.18, alpha: 0.24).setFill()
        selectionPath.fill()
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.72).setStroke()
        selectionPath.lineWidth = 1.2
        selectionPath.stroke()
    }

    private func drawRoadmapMarkerEditOverlay(
        _ markerLayout: LeadSheetRoadmapMarkerLayout,
        using renderer: LeadSheetNotationRenderer
    ) {
        let isActiveMove = activeRoadmapMarkerEditDrag?.markerID == markerLayout.id
        let editFrame = LeadSheetRoadmapMarkerEditOverlayGeometry.editFrame(for: markerLayout)
        let controlFrames = LeadSheetRoadmapMarkerEditOverlayGeometry.controlFrames(for: markerLayout)
        let boxPath = UIBezierPath(roundedRect: editFrame, cornerRadius: 5)

        UIColor(
            red: 0.88,
            green: 0.93,
            blue: 1,
            alpha: isActiveMove ? 0.30 : 0.18
        ).setFill()
        boxPath.fill()
        UIColor(
            red: 0.16,
            green: 0.38,
            blue: 0.86,
            alpha: isActiveMove ? 0.92 : 0.62
        ).setStroke()
        boxPath.lineWidth = isActiveMove ? 1.4 : 1
        boxPath.stroke()

        let deletePath = UIBezierPath(ovalIn: controlFrames.delete)
        UIColor.white.withAlphaComponent(0.96).setFill()
        deletePath.fill()
        UIColor(red: 0.92, green: 0.16, blue: 0.20, alpha: 0.86).setStroke()
        deletePath.lineWidth = 1
        deletePath.stroke()
        renderer.drawText(
            "x",
            in: controlFrames.delete.insetBy(dx: 1, dy: -1),
            font: UIFont.systemFont(ofSize: 10, weight: .bold),
            color: UIColor(red: 0.82, green: 0.08, blue: 0.12, alpha: 1),
            alignment: .center
        )
    }

    private func isSelectedNote(noteIndex: Int, in measure: LeadSheetMeasureLayout) -> Bool {
        guard let sourceMeasureID = measure.sourceMeasureID,
              let selectedNoteSelection else {
            return false
        }

        return selectedNoteSelection.measureID == sourceMeasureID
            && selectedNoteSelection.noteIndex == noteIndex
    }

    private func drawMeasureResizeHandles(
        for measure: LeadSheetMeasureLayout,
        using renderer: LeadSheetNotationRenderer
    ) {
        let handleRects = LeadSheetMeasureResizeGeometry.handleFrames(for: measure)
        drawMeasureResizeHandle(handleRects.left, symbol: "⇠", using: renderer)
        drawMeasureResizeHandle(handleRects.right, symbol: "⇢", using: renderer)
    }

    private func drawMeasureResizeHandle(
        _ rect: CGRect,
        symbol: String,
        using renderer: LeadSheetNotationRenderer
    ) {
        let handlePath = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        UIColor.white.withAlphaComponent(0.95).setFill()
        handlePath.fill()
        UIColor(red: 0.18, green: 0.38, blue: 0.78, alpha: 0.88).setStroke()
        handlePath.lineWidth = 1.2
        handlePath.stroke()

        renderer.drawText(
            symbol,
            in: rect.insetBy(dx: 1, dy: 3),
            font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            color: UIColor(red: 0.16, green: 0.33, blue: 0.68, alpha: 1),
            alignment: .center
        )
    }

    private func drawMeasureResizePreviewGuides(_ preview: LeadSheetMeasureResizePreview) {
        let affectedFrames = preview.affectedMeasureIDs.compactMap { preview.measureFrames[$0] }
        guard !affectedFrames.isEmpty else {
            return
        }

        let isAlignedToEvenDivision = preview.activeEvenDivisionGuideX != nil
        let guideColor = isAlignedToEvenDivision
            ? UIColor(red: 0.02, green: 0.62, blue: 0.28, alpha: 1)
            : UIColor(red: 0.06, green: 0.31, blue: 0.94, alpha: 1)
        let affectedFillColor = isAlignedToEvenDivision
            ? UIColor(red: 0.02, green: 0.62, blue: 0.28, alpha: 0.08)
            : UIColor(red: 0.18, green: 0.43, blue: 0.96, alpha: 0.07)
        let affectedStrokeColor = isAlignedToEvenDivision
            ? UIColor(red: 0.02, green: 0.62, blue: 0.28, alpha: 0.40)
            : UIColor(red: 0.18, green: 0.43, blue: 0.96, alpha: 0.34)

        affectedFillColor.setFill()
        affectedStrokeColor.setStroke()

        for frame in affectedFrames {
            let fillRect = frame.insetBy(dx: 2, dy: 12)
            let path = UIBezierPath(roundedRect: fillRect, cornerRadius: 6)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }

        let rowGuide = UIBezierPath()
        rowGuide.move(to: CGPoint(x: preview.rowFrame.minX, y: preview.rowFrame.minY - 6))
        rowGuide.addLine(to: CGPoint(x: preview.rowFrame.maxX, y: preview.rowFrame.minY - 6))
        UIColor(red: 0.18, green: 0.43, blue: 0.96, alpha: 0.24).setStroke()
        rowGuide.lineWidth = 1
        rowGuide.setLineDash([6, 4], count: 2, phase: 0)
        rowGuide.stroke()

        for guideX in preview.evenDivisionGuideXs {
            let isActiveGuide = preview.activeEvenDivisionGuideX.map { abs($0 - guideX) < 0.5 } ?? false
            let evenGuide = UIBezierPath()
            evenGuide.move(to: CGPoint(x: guideX, y: preview.rowFrame.minY - 10))
            evenGuide.addLine(to: CGPoint(x: guideX, y: preview.rowFrame.maxY + 10))
            if isActiveGuide {
                guideColor.withAlphaComponent(0.72).setStroke()
                evenGuide.lineWidth = 1.5
                evenGuide.setLineDash([5, 2], count: 2, phase: 0)
            } else {
                UIColor(red: 0.18, green: 0.43, blue: 0.96, alpha: 0.20).setStroke()
                evenGuide.lineWidth = 0.8
                evenGuide.setLineDash([3, 6], count: 2, phase: 0)
            }
            evenGuide.stroke()
        }

        let edgeGuide = UIBezierPath()
        edgeGuide.move(to: CGPoint(x: preview.draggedEdgeX, y: preview.rowFrame.minY - 10))
        edgeGuide.addLine(to: CGPoint(x: preview.draggedEdgeX, y: preview.rowFrame.maxY + 10))
        guideColor.withAlphaComponent(0.82).setStroke()
        edgeGuide.lineWidth = isAlignedToEvenDivision ? 2.0 : 1.4
        edgeGuide.setLineDash([4, 3], count: 2, phase: 0)
        edgeGuide.stroke()

        guideColor.withAlphaComponent(isAlignedToEvenDivision ? 0.44 : 0.38).setStroke()
        for frame in affectedFrames {
            let leftGuide = UIBezierPath()
            leftGuide.move(to: CGPoint(x: frame.minX, y: preview.rowFrame.minY - 4))
            leftGuide.addLine(to: CGPoint(x: frame.minX, y: preview.rowFrame.maxY + 4))
            leftGuide.lineWidth = 0.8
            leftGuide.stroke()

            let rightGuide = UIBezierPath()
            rightGuide.move(to: CGPoint(x: frame.maxX, y: preview.rowFrame.minY - 4))
            rightGuide.addLine(to: CGPoint(x: frame.maxX, y: preview.rowFrame.maxY + 4))
            rightGuide.lineWidth = 0.8
            rightGuide.stroke()
        }
    }

    private func drawSimpleRowGroupAffordance(_ affordance: LeadSheetSimpleRowGroupAffordance) {
        let guideY = affordance.guideY
        let startX = affordance.groupFrame.minX + 4
        let endX = affordance.groupFrame.maxX - 4

        let guidePath = UIBezierPath()
        guidePath.move(to: CGPoint(x: startX, y: guideY))
        guidePath.addLine(to: CGPoint(x: endX, y: guideY))
        guidePath.move(to: CGPoint(x: startX, y: guideY))
        guidePath.addLine(to: CGPoint(x: startX, y: guideY + 7))
        guidePath.move(to: CGPoint(x: endX, y: guideY))
        guidePath.addLine(to: CGPoint(x: endX, y: guideY + 7))

        UIColor(red: 0.16, green: 0.33, blue: 0.68, alpha: 0.52).setStroke()
        guidePath.lineWidth = 1.1
        guidePath.setLineDash([5, 4], count: 2, phase: 0)
        guidePath.stroke()
    }

    private func drawSavedPageInk() {
        guard let pageLayout else {
            return
        }

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        for paperFrame in pageLayout.paperFrames {
            context.saveGState()
            UIBezierPath(rect: paperFrame).addClip()
            LeadSheetSavedInkRenderer.drawPageInk(
                chart.pageHandwrittenNotationData,
                coordinateSpace: chart.pageHandwrittenNotationCoordinateSpace,
                chart: chart,
                in: pageLayout
            )
            context.restoreGState()
        }
    }

    private func drawSavedHeaderInk() {
        guard let pageLayout else {
            return
        }

        LeadSheetSavedInkRenderer.drawHeaderInk(
            chart.pageHandwrittenHeaderData,
            coordinateSpace: chart.pageHandwrittenHeaderCoordinateSpace,
            in: pageLayout
        )
    }

    private func drawChordWritingLanes(_ pageLayout: LeadSheetPageLayout) {
        for laneFrame in LeadSheetActiveInkScope.chordWritingInputFrames(for: pageLayout) {
            let maskPath = UIBezierPath(rect: laneFrame.insetBy(dx: -1, dy: -1))
            chordLanePaperFillColor.setFill()
            maskPath.fill()

            let lanePath = UIBezierPath(roundedRect: laneFrame, cornerRadius: 7)
            UIColor(red: 0.18, green: 0.36, blue: 0.78, alpha: 0.08).setFill()
            lanePath.fill()

            let railPath = UIBezierPath()
            railPath.move(to: CGPoint(x: laneFrame.minX, y: laneFrame.minY))
            railPath.addLine(to: CGPoint(x: laneFrame.maxX, y: laneFrame.minY))
            railPath.move(to: CGPoint(x: laneFrame.minX, y: laneFrame.maxY))
            railPath.addLine(to: CGPoint(x: laneFrame.maxX, y: laneFrame.maxY))
            UIColor(red: 0.18, green: 0.36, blue: 0.78, alpha: 0.22).setStroke()
            railPath.lineWidth = 1
            railPath.setLineDash([5, 4], count: 2, phase: 0)
            railPath.stroke()

            let leftGuidePath = UIBezierPath()
            leftGuidePath.move(to: CGPoint(x: laneFrame.minX, y: laneFrame.minY))
            leftGuidePath.addLine(to: CGPoint(x: laneFrame.minX, y: laneFrame.maxY))
            UIColor(red: 0.13, green: 0.34, blue: 0.78, alpha: 0.58).setStroke()
            leftGuidePath.lineWidth = 2
            leftGuidePath.lineCapStyle = .round
            leftGuidePath.stroke()
        }
    }

    private func drawChordDraftPreview(_ pageLayout: LeadSheetPageLayout) {
        guard !chordPreviewState.isEmpty else {
            return
        }

        for barline in chordPreviewState.draftBarlines {
            guard let laneFrame = chordDraftLaneFrame(for: barline, in: pageLayout) else {
                continue
            }

            drawDraftBarline(barline, in: laneFrame)
        }
    }

    private func drawSelectedCommittedChordBarline(in pageLayout: LeadSheetPageLayout) {
        guard let selectedCommittedBarlineMeasureID,
              let measure = committedSimpleChordBarlineMeasures(in: pageLayout).first(where: {
                $0.sourceMeasureID == selectedCommittedBarlineMeasureID
              }) else {
            return
        }

        let lineFrame = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: measure)
        let x = lineFrame.midX
        let selectedPath = UIBezierPath()
        selectedPath.move(to: CGPoint(x: x, y: lineFrame.minY))
        selectedPath.addLine(to: CGPoint(x: x, y: lineFrame.maxY))
        UIColor(red: 0.06, green: 0.24, blue: 0.64, alpha: 0.92).setStroke()
        selectedPath.lineWidth = 3
        selectedPath.lineCapStyle = .round
        selectedPath.stroke()

        let controlFrames = LeadSheetCommittedChordBarlineOverlayGeometry.controlFrames(for: measure)
        let deletePath = UIBezierPath(ovalIn: controlFrames.delete)
        UIColor.white.withAlphaComponent(0.98).setFill()
        deletePath.fill()
        UIColor(red: 0.92, green: 0.16, blue: 0.20, alpha: 0.86).setStroke()
        deletePath.lineWidth = 1
        deletePath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor(red: 0.82, green: 0.08, blue: 0.12, alpha: 1)
        ]
        let label = "x"
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: CGPoint(
                x: controlFrames.delete.midX - labelSize.width / 2,
                y: controlFrames.delete.midY - labelSize.height / 2
            ),
            withAttributes: attributes
        )
    }

    private func committedSimpleChordBarlineMeasures(in pageLayout: LeadSheetPageLayout) -> [LeadSheetMeasureLayout] {
        guard chart.layoutStyle == .simpleChordSheet else {
            return []
        }

        return pageLayout.systems.flatMap { system in
            system.measures.enumerated().compactMap { measureIndex, measure in
                let nextMeasureIndex = measureIndex + 1
                let nextMeasure = system.measures.indices.contains(nextMeasureIndex)
                    ? system.measures[nextMeasureIndex]
                    : nil
                guard let measureID = measure.sourceMeasureID,
                      nextMeasure != nil,
                      chart.canDeleteCommittedSimpleChordBarline(after: measureID),
                      LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(
                        after: measure,
                        before: nextMeasure
                      ) else {
                    return nil
                }

                return measure
            }
        }
    }

    private func chordDraftLaneFrameByMeasureID(in pageLayout: LeadSheetPageLayout) -> [UUID: CGRect] {
        pageLayout.systems.reduce(into: [UUID: CGRect]()) { result, system in
            guard let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame(for: system)
            ) else {
                return
            }

            for measure in system.measures {
                if let measureID = measure.sourceMeasureID,
                   result[measureID] == nil {
                    result[measureID] = laneFrame
                }
                if let measureID = measure.chordInkTargetMeasureID,
                   result[measureID] == nil {
                    result[measureID] = laneFrame
                }
            }
        }
    }

    private func chordDraftLaneFrame(for barline: DraftBarline, in pageLayout: LeadSheetPageLayout) -> CGRect? {
        if let laneLocation = barline.laneLocation,
           let system = pageLayout.systems.first(where: { $0.index == laneLocation.systemIndex }),
           let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system,
            paperFrame: pageLayout.paperFrame(for: system)
           ) {
            return laneFrame
        }

        return chordDraftLaneFrameByMeasureID(in: pageLayout)[barline.measureID]
    }

    private func drawDraftBarline(_ barline: DraftBarline, in laneFrame: CGRect) {
        let laneFrame = laneFrame.insetBy(dx: 1, dy: 2)
        let x = laneFrame.minX + laneFrame.width * CGFloat(barline.laneFraction)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: laneFrame.minY))
        path.addLine(to: CGPoint(x: x, y: laneFrame.maxY))
        let color = barline.isRenderable
            ? UIColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.72)
            : UIColor(red: 0.9, green: 0.46, blue: 0.12, alpha: 0.64)
        color.setStroke()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.setLineDash([6, 3], count: 2, phase: 0)
        path.stroke()

        guard selectedDraftBarlineID == barline.id else {
            return
        }

        let selectedPath = UIBezierPath()
        selectedPath.move(to: CGPoint(x: x, y: laneFrame.minY))
        selectedPath.addLine(to: CGPoint(x: x, y: laneFrame.maxY))
        UIColor(red: 0.06, green: 0.24, blue: 0.64, alpha: 0.92).setStroke()
        selectedPath.lineWidth = 3
        selectedPath.lineCapStyle = .round
        selectedPath.stroke()

        let controlFrames = ChordDraftBarlineOverlayGeometry.controlFrames(for: barline, in: laneFrame)
        let deletePath = UIBezierPath(ovalIn: controlFrames.delete)
        UIColor.white.withAlphaComponent(0.98).setFill()
        deletePath.fill()
        UIColor(red: 0.92, green: 0.16, blue: 0.20, alpha: 0.86).setStroke()
        deletePath.lineWidth = 1
        deletePath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor(red: 0.82, green: 0.08, blue: 0.12, alpha: 1)
        ]
        let label = "x"
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: CGPoint(
                x: controlFrames.delete.midX - labelSize.width / 2,
                y: controlFrames.delete.midY - labelSize.height / 2
            ),
            withAttributes: attributes
        )
    }

    private var chordLanePaperFillColor: UIColor {
        switch chart.layoutStyle {
        case .simpleChordSheet, .leadSheet:
            switch chart.stylePreset {
            case .cleanStudio:
                return UIColor(red: 1.0, green: 0.976, blue: 0.892, alpha: 1)
            case .gigSheet:
                return UIColor(red: 0.988, green: 0.965, blue: 0.906, alpha: 1)
            case .plainWhite, .rehearsalDraft:
                return UIColor(white: 1.0, alpha: 1)
            }
        case .rhythmSectionSheet:
            switch chart.stylePreset {
            case .cleanStudio:
                return UIColor(red: 0.992, green: 0.975, blue: 0.922, alpha: 1)
            case .gigSheet:
                return UIColor(red: 0.962, green: 0.986, blue: 0.982, alpha: 1)
            case .plainWhite:
                return UIColor(white: 1.0, alpha: 1)
            case .rehearsalDraft:
                return UIColor(red: 0.988, green: 0.992, blue: 0.996, alpha: 1)
            }
        }
    }

    private func drawPageScrollDragAreas(_ pageLayout: LeadSheetPageLayout) {
        let dragAreaFrames = LeadSheetScrollMarginPolicy.dragAreaFrames(
            in: bounds,
            paperFrame: pageLayout.paperEnvelope
        )

        for dragAreaFrame in dragAreaFrames {
            let areaPath = UIBezierPath(rect: dragAreaFrame)
            UIColor(red: 0.13, green: 0.34, blue: 0.78, alpha: 0.025).setFill()
            areaPath.fill()

            guard let railFrame = scrollDragRailFrame(
                in: dragAreaFrame,
                around: pageLayout.paperEnvelope
            ) else {
                continue
            }

            let railPath = UIBezierPath(roundedRect: railFrame, cornerRadius: min(6, min(railFrame.width, railFrame.height) / 2))
            UIColor(red: 0.13, green: 0.34, blue: 0.78, alpha: 0.055).setFill()
            railPath.fill()
            UIColor(red: 0.13, green: 0.34, blue: 0.78, alpha: 0.20).setStroke()
            railPath.lineWidth = 1
            railPath.stroke()
            drawScrollDragDots(in: railFrame)
        }
    }

    private func scrollDragRailFrame(
        in dragAreaFrame: CGRect,
        around paperFrame: CGRect
    ) -> CGRect? {
        let isVerticalRail = dragAreaFrame.height >= dragAreaFrame.width
        let minimumThickness: CGFloat = 8
        guard dragAreaFrame.width >= minimumThickness || dragAreaFrame.height >= minimumThickness else {
            return nil
        }

        if isVerticalRail {
            let railWidth = min(max(6, dragAreaFrame.width * 0.42), 12)
            let railHeight = min(max(72, dragAreaFrame.height * 0.16), 150)
            let railX = dragAreaFrame.midX - railWidth / 2
            let preferredY = paperFrame.midY - railHeight / 2
            let railY = min(
                max(preferredY, dragAreaFrame.minY + 18),
                max(dragAreaFrame.minY + 18, dragAreaFrame.maxY - railHeight - 18)
            )
            return CGRect(x: railX, y: railY, width: railWidth, height: railHeight)
        }

        let railWidth = min(max(88, dragAreaFrame.width * 0.18), 170)
        let railHeight = min(max(6, dragAreaFrame.height * 0.42), 12)
        let preferredX = paperFrame.midX - railWidth / 2
        let railX = min(
            max(preferredX, dragAreaFrame.minX + 18),
            max(dragAreaFrame.minX + 18, dragAreaFrame.maxX - railWidth - 18)
        )
        let railY = dragAreaFrame.midY - railHeight / 2
        return CGRect(x: railX, y: railY, width: railWidth, height: railHeight)
    }

    private func drawScrollDragDots(in railFrame: CGRect) {
        let isVerticalRail = railFrame.height >= railFrame.width
        let dotDiameter: CGFloat = 3
        let spacing: CGFloat = 8
        UIColor(red: 0.13, green: 0.34, blue: 0.78, alpha: 0.34).setFill()

        for offsetIndex in -1...1 {
            let center: CGPoint
            if isVerticalRail {
                center = CGPoint(
                    x: railFrame.midX,
                    y: railFrame.midY + CGFloat(offsetIndex) * spacing
                )
            } else {
                center = CGPoint(
                    x: railFrame.midX + CGFloat(offsetIndex) * spacing,
                    y: railFrame.midY
                )
            }
            UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - dotDiameter / 2,
                    y: center.y - dotDiameter / 2,
                    width: dotDiameter,
                    height: dotDiameter
                )
            ).fill()
        }
    }

    private func displayChordLayout(for chordLayout: LeadSheetChordLayout) -> LeadSheetChordLayout {
        if let activeChordResizeDrag,
           activeChordResizeDrag.chordID == chordLayout.id {
            var previewLayout = chordLayout
            previewLayout.frame = activeChordResizeDrag.currentFrame
            previewLayout.fitFrame = activeChordResizeDrag.currentFrame
            previewLayout.snapGuideTarget = CGPoint(
                x: activeChordResizeDrag.currentFrame.minX,
                y: activeChordResizeDrag.currentFrame.maxY + 1
            )
            return previewLayout
        }

        guard let activeChordMoveDrag,
              activeChordMoveDrag.chordID == chordLayout.id else {
            return chordLayout
        }

        var previewLayout = chordLayout
        previewLayout.frame = activeChordMoveDrag.currentFrame
        previewLayout.fitFrame = activeChordMoveDrag.currentFrame
        previewLayout.snapGuideTarget = CGPoint(
            x: activeChordMoveDrag.currentFrame.midX,
            y: activeChordMoveDrag.currentFrame.maxY + 1
        )
        return previewLayout
    }

    private func displayCueTextLayout(for cueTextLayout: LeadSheetCueTextLayout) -> LeadSheetCueTextLayout {
        guard let activeCueTextMoveDrag,
              activeCueTextMoveDrag.cueTextID == cueTextLayout.id else {
            return cueTextLayout
        }

        let deltaX = activeCueTextMoveDrag.currentFrame.minX - cueTextLayout.frame.minX
        let deltaY = activeCueTextMoveDrag.currentFrame.minY - cueTextLayout.frame.minY
        var previewLayout = cueTextLayout
        previewLayout.frame = activeCueTextMoveDrag.currentFrame
        previewLayout.hitFrame = cueTextLayout.hitFrame.offsetBy(dx: deltaX, dy: deltaY)
        return previewLayout
    }

    private func displayRoadmapMarkerLayout(
        for markerLayout: LeadSheetRoadmapMarkerLayout
    ) -> LeadSheetRoadmapMarkerLayout {
        guard let activeRoadmapMarkerEditDrag,
              activeRoadmapMarkerEditDrag.markerID == markerLayout.id else {
            return markerLayout
        }

        var previewLayout = markerLayout
        previewLayout.frame = activeRoadmapMarkerEditDrag.currentFrame
        return previewLayout
    }

    private func drawChordEditOverlay(
        for chordLayout: LeadSheetChordLayout,
        using renderer: LeadSheetNotationRenderer
    ) {
        let editFrame = LeadSheetChordEditOverlayGeometry.editFrame(for: chordLayout)
        let controlFrames = LeadSheetChordEditOverlayGeometry.controlFrames(for: chordLayout)
        let isActiveMove = activeChordMoveDrag?.chordID == chordLayout.id
        let isActiveResize = activeChordResizeDrag?.chordID == chordLayout.id
        let drawsControls = shouldDrawChordEditControls(for: chordLayout)

        if isActiveMove {
            drawChordSnapGuide(for: chordLayout)
        }

        let boxPath = UIBezierPath(roundedRect: editFrame, cornerRadius: 5)
        UIColor(
            red: 0.88,
            green: 0.93,
            blue: 1,
            alpha: (isActiveMove || isActiveResize) ? 0.30 : (drawsControls ? 0.18 : 0.08)
        ).setFill()
        boxPath.fill()
        UIColor(
            red: 0.16,
            green: 0.38,
            blue: 0.86,
            alpha: (isActiveMove || isActiveResize) ? 0.92 : (drawsControls ? 0.62 : 0.40)
        ).setStroke()
        boxPath.lineWidth = (isActiveMove || isActiveResize) ? 1.4 : 1
        boxPath.stroke()

        guard drawsControls else {
            return
        }

        let deletePath = UIBezierPath(ovalIn: controlFrames.delete)
        UIColor.white.withAlphaComponent(0.96).setFill()
        deletePath.fill()
        UIColor(red: 0.92, green: 0.16, blue: 0.20, alpha: 0.86).setStroke()
        deletePath.lineWidth = 1
        deletePath.stroke()
        renderer.drawText(
            "x",
            in: controlFrames.delete.insetBy(dx: 1, dy: -1),
            font: UIFont.systemFont(ofSize: 10, weight: .bold),
            color: UIColor(red: 0.82, green: 0.08, blue: 0.12, alpha: 1),
            alignment: .center
        )

        drawChordResizeHandle(controlFrames.trailingResize, isActive: activeChordResizeDrag?.edge == .trailing)
    }

    private func drawChordResizeHandle(_ frame: CGRect, isActive: Bool) {
        let handlePath = UIBezierPath(roundedRect: frame, cornerRadius: 5)
        UIColor.white.withAlphaComponent(0.96).setFill()
        handlePath.fill()
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: isActive ? 0.95 : 0.72).setStroke()
        handlePath.lineWidth = isActive ? 1.3 : 1
        handlePath.stroke()

        let barInset = frame.insetBy(dx: frame.width * 0.38, dy: frame.height * 0.22)
        let barPath = UIBezierPath(roundedRect: barInset, cornerRadius: 1.5)
        UIColor(red: 0.14, green: 0.27, blue: 0.58, alpha: 0.96).setFill()
        barPath.fill()
    }

    private func drawChordSnapGuide(for chordLayout: LeadSheetChordLayout) {
        if let activeChordMoveDrag,
           activeChordMoveDrag.chordID == chordLayout.id,
           let positionPreview = activeChordMoveDrag.currentPositionPreview {
            drawChordMovePositionGuides(positionPreview)
        }

        let startPoint = CGPoint(
            x: chordLayout.frame.midX,
            y: chordLayout.frame.maxY + 1
        )
        let endPoint = chordLayout.snapGuideTarget
        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        guard (deltaX * deltaX + deltaY * deltaY).squareRoot() > 4 else {
            return
        }

        let guidePath = UIBezierPath()
        guidePath.move(to: startPoint)
        guidePath.addLine(to: endPoint)
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.54).setStroke()
        guidePath.lineWidth = 1.2
        guidePath.lineCapStyle = .round
        guidePath.setLineDash([4, 4], count: 2, phase: 0)
        guidePath.stroke()

        let targetRect = CGRect(x: endPoint.x - 3.5, y: endPoint.y - 3.5, width: 7, height: 7)
        let targetPath = UIBezierPath(ovalIn: targetRect)
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.72).setFill()
        targetPath.fill()
    }

    private func drawChordMovePositionGuides(_ preview: LeadSheetChordMovePositionPreview) {
        let isAligned = preview.activeGuideX != nil
        let activeColor = isAligned
            ? UIColor(red: 0.02, green: 0.62, blue: 0.28, alpha: 1)
            : UIColor(red: 0.06, green: 0.31, blue: 0.94, alpha: 1)
        let fieldFrame = preview.guideFrame.insetBy(dx: -4, dy: -8)
        let fieldPath = UIBezierPath(roundedRect: fieldFrame, cornerRadius: 5)
        activeColor.withAlphaComponent(isAligned ? 0.08 : 0.06).setFill()
        fieldPath.fill()
        activeColor.withAlphaComponent(isAligned ? 0.34 : 0.22).setStroke()
        fieldPath.lineWidth = 1
        fieldPath.stroke()

        for guideX in preview.guideXs {
            let isActiveGuide = preview.activeGuideX.map { abs($0 - guideX) < 0.5 } ?? false
            let guidePath = UIBezierPath()
            guidePath.move(to: CGPoint(x: guideX, y: fieldFrame.minY - 2))
            guidePath.addLine(to: CGPoint(x: guideX, y: fieldFrame.maxY + 2))
            if isActiveGuide {
                activeColor.withAlphaComponent(0.82).setStroke()
                guidePath.lineWidth = 1.7
                guidePath.setLineDash([5, 2], count: 2, phase: 0)
            } else {
                UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.24).setStroke()
                guidePath.lineWidth = 0.9
                guidePath.setLineDash([3, 6], count: 2, phase: 0)
            }
            guidePath.stroke()
        }

        let targetPath = UIBezierPath()
        targetPath.move(to: CGPoint(x: preview.targetX, y: fieldFrame.minY - 4))
        targetPath.addLine(to: CGPoint(x: preview.targetX, y: fieldFrame.maxY + 4))
        activeColor.withAlphaComponent(isAligned ? 0.88 : 0.60).setStroke()
        targetPath.lineWidth = isAligned ? 2.0 : 1.3
        targetPath.lineCapStyle = .round
        targetPath.stroke()
    }

    private func drawSavedMeasureRhythmicNotation(_ measure: LeadSheetMeasureLayout) {
        guard let sourceMeasureID = measure.sourceMeasureID else {
            return
        }

        if interactionMode.allowsDirectRhythmicNotationInk,
           selectedMeasureID == sourceMeasureID {
            return
        }

        guard let sourceMeasure = chart.measure(id: sourceMeasureID) else {
            return
        }

        LeadSheetSavedInkRenderer.drawRhythmicNotationInk(
            sourceMeasure.handwrittenRhythmicNotationData,
            coordinateSpace: sourceMeasure.handwrittenRhythmicNotationCoordinateSpace,
            in: measure
        )
    }

    private func selectedMeasureLayout() -> LeadSheetMeasureLayout? {
        guard let selectedMeasureID else {
            return nil
        }

        return measureLayout(for: selectedMeasureID)
    }

    private func selectedDisplayMeasureLayout() -> LeadSheetMeasureLayout? {
        guard let selectedMeasureID,
              let pageLayout else {
            return nil
        }

        for system in pageLayout.systems {
            if let measure = system.measures.first(where: { $0.sourceMeasureID == selectedMeasureID }) {
                return displayMeasureLayout(measure, in: system)
            }
        }

        return nil
    }

    private var showsSelectedMeasureResizeHandles: Bool {
        interactionMode.showsMeasureResizeHandles
            && selectedMeasureID != nil
            && selectedChordID == nil
            && selectedCommittedBarlineMeasureID == nil
            && selectedCueTextID == nil
            && selectedRoadmapMarkerID == nil
    }

    private func displayMeasureLayout(
        _ measure: LeadSheetMeasureLayout,
        in system: LeadSheetSystemLayout
    ) -> LeadSheetMeasureLayout {
        guard let pageLayout else {
            return measure
        }

        let displayMeasure = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
            measure,
            in: system,
            paperFrame: pageLayout.paperFrame(for: system),
            layoutStyle: chart.layoutStyle
        )
        return displayMeasureResizePreviewLayout(displayMeasure)
    }

    private func displayMeasureResizePreviewLayout(
        _ measure: LeadSheetMeasureLayout
    ) -> LeadSheetMeasureLayout {
        guard let activeMeasureResizeDrag,
              let previewFrame = activeMeasureResizeDrag.currentPreview?.frame(for: measure.sourceMeasureID)
                ?? (activeMeasureResizeDrag.measureID == measure.sourceMeasureID
                    ? activeMeasureResizeDrag.currentFrame
                    : nil) else {
            return measure
        }

        let deltaX = previewFrame.minX - measure.frame.minX
        let widthDelta = previewFrame.width - measure.frame.width
        var previewMeasure = measure
        previewMeasure.frame = previewFrame
        previewMeasure.staffFrame.origin.x += deltaX
        previewMeasure.staffFrame.size.width = max(1, previewMeasure.staffFrame.width + widthDelta)
        previewMeasure.chordBandFrame.origin.x += deltaX
        previewMeasure.chordBandFrame.size.width = max(1, previewMeasure.chordBandFrame.width + widthDelta)
        previewMeasure.writableFrame.origin.x += deltaX
        previewMeasure.writableFrame.size.width = max(1, previewMeasure.writableFrame.width + widthDelta)
        previewMeasure.trailingBarlineFrame = previewMeasure.trailingBarlineFrame.offsetBy(
            dx: previewFrame.maxX - measure.frame.maxX,
            dy: 0
        )
        return previewMeasure
    }

    private func simpleRowGroupAffordance() -> LeadSheetSimpleRowGroupAffordance? {
        LeadSheetSimpleRowGroupAffordanceGeometry.affordance(
            for: selectedMeasureID,
            in: pageLayout,
            layoutStyle: chart.layoutStyle
        )
    }

    private func measureAndSystemLayout(
        for measureID: UUID
    ) -> (measure: LeadSheetMeasureLayout, system: LeadSheetSystemLayout)? {
        for system in pageLayout?.systems ?? [] {
            if let measure = system.measures.first(where: { $0.sourceMeasureID == measureID }) {
                return (measure, system)
            }
        }

        return nil
    }

    private func measureLayout(for measureID: UUID) -> LeadSheetMeasureLayout? {
        measureAndSystemLayout(for: measureID)?.measure
    }

    private func measureResizeDisplayedToManualWidthScale() -> CGFloat {
        guard chart.layoutStyle == .simpleChordSheet,
              let pageLayout,
              let selectedMeasureID,
              let selectedSystem = measureAndSystemLayout(for: selectedMeasureID)?.system else {
            return 1
        }

        return LeadSheetPageLayoutEngine.simpleChordSheetManualLayoutWidthScale(
            chart: chart,
            maxSystemWidth: max(1, pageLayout.paperFrame(for: selectedSystem).width - 68)
        )
    }

    private func measureResizeTransaction(
        for measureID: UUID,
        edge: ActiveMeasureResizeDrag.Edge,
        in system: LeadSheetSystemLayout
    ) -> LeadSheetMeasureResizeTransaction? {
        let snapshots = system.measures.compactMap { measure -> LeadSheetMeasureResizeMeasureSnapshot? in
            guard let sourceMeasureID = measure.sourceMeasureID else {
                return nil
            }

            return LeadSheetMeasureResizeMeasureSnapshot(
                measureID: sourceMeasureID,
                frame: measure.frame
            )
        }
        let evenDivisionCommitManualWidths: [UUID: CGFloat]
        if chart.layoutStyle == .simpleChordSheet,
           let pageLayout {
            evenDivisionCommitManualWidths = LeadSheetSimpleChordRowEqualizationPolicy.manualLayoutWidths(
                for: system,
                in: pageLayout,
                chart: chart
            )
        } else {
            evenDivisionCommitManualWidths = [:]
        }

        return LeadSheetMeasureResizeTransaction(
            selectedMeasureID: measureID,
            edge: edge,
            rowMeasures: snapshots,
            displayedToManualWidthScale: measureResizeDisplayedToManualWidthScale(),
            evenDivisionCommitManualWidths: evenDivisionCommitManualWidths
        )
    }

    private func measureResizeHandleHitTarget(at location: CGPoint) -> ActiveMeasureResizeDrag? {
        guard showsSelectedMeasureResizeHandles,
              let hitTarget = renderedEditDragTarget(at: location),
              case .measure(let measureID) = hitTarget.objectID,
              let measureAndSystem = measureAndSystemLayout(for: measureID) else {
            return nil
        }

        let measure = measureAndSystem.measure
        let system = measureAndSystem.system
        switch hitTarget.action {
        case .resizeLeft:
            let displayMeasure = selectedDisplayMeasureLayout() ?? measure
            let transaction = measureResizeTransaction(
                for: measureID,
                edge: .left,
                in: system
            )
            return ActiveMeasureResizeDrag(
                measureID: measureID,
                edge: .left,
                initialWidth: displayMeasure.frame.width,
                initialFrame: displayMeasure.frame,
                currentFrame: displayMeasure.frame,
                transaction: transaction,
                currentPreview: transaction?.preview(for: 0)
            )
        case .resizeRight:
            let displayMeasure = selectedDisplayMeasureLayout() ?? measure
            let transaction = measureResizeTransaction(
                for: measureID,
                edge: .right,
                in: system
            )
            return ActiveMeasureResizeDrag(
                measureID: measureID,
                edge: .right,
                initialWidth: displayMeasure.frame.width,
                initialFrame: displayMeasure.frame,
                currentFrame: displayMeasure.frame,
                transaction: transaction,
                currentPreview: transaction?.preview(for: 0)
            )
        default:
            return nil
        }
    }

    private func hasNewChordEvent(from oldChart: Chart, to newChart: Chart) -> Bool {
        let oldChordIDs = Set(oldChart.measures.flatMap { measure in
            measure.chordEvents.map(\.id)
        })
        let newChordIDs = Set(newChart.measures.flatMap { measure in
            measure.chordEvents.map(\.id)
        })

        return !newChordIDs.subtracting(oldChordIDs).isEmpty
    }

    private func suppressChordObjectEditingTemporarily() {
        chordObjectEditingSuppressedUntil = Date().addingTimeInterval(1.5)
        activeChordMoveDrag = nil
        activeChordResizeDrag = nil
        unlockParentScrollForChordMove()
    }

    private func isChordObjectEditingTemporarilySuppressed() -> Bool {
        if interactionMode.allowsChordInkEditing {
            return false
        }

        guard let chordObjectEditingSuppressedUntil else {
            return false
        }

        if Date() < chordObjectEditingSuppressedUntil {
            return true
        }

        self.chordObjectEditingSuppressedUntil = nil
        return false
    }

    private func shouldDrawChordEditOverlay(for chordLayout: LeadSheetChordLayout) -> Bool {
        LeadSheetChordObjectInteractionPolicy.shouldDrawBox(
            for: chordLayout.id,
            selectedChordID: selectedChordID,
            activeMoveChordID: activeChordMoveDrag?.chordID ?? activeChordResizeDrag?.chordID,
            drawsAllBoxes: interactionMode.drawsAllChordObjectEditBoxes
        )
    }

    private func shouldDrawChordEditControls(for chordLayout: LeadSheetChordLayout) -> Bool {
        LeadSheetChordObjectInteractionPolicy.shouldDrawControls(
            for: chordLayout.id,
            selectedChordID: selectedChordID,
            activeMoveChordID: activeChordMoveDrag?.chordID ?? activeChordResizeDrag?.chordID,
            drawsAllControls: interactionMode.drawsAllChordObjectEditControls
        )
    }

    private func chordEditHitTarget(at location: CGPoint) -> ChordEditHitTarget? {
        guard interactionMode.allowsChordObjectEditing,
              !isChordObjectEditingTemporarilySuppressed(),
              let pageLayout else {
            return nil
        }

        return LeadSheetChordObjectInteractionPolicy.resolvedTapTarget(
            LeadSheetChordEditOverlayGeometry.hitTarget(at: location, in: pageLayout),
            selectedChordID: selectedChordID,
            requiresSelectionBeforeAction: interactionMode.requiresChordSelectionBeforeObjectActions
        )
    }

    private func renderedEditSelectionState() -> RenderedEditSelectionState {
        if let selectedCommittedBarlineMeasureID {
            return RenderedEditSelectionState(
                selectedObjectID: .committedChordBarline(afterMeasureID: selectedCommittedBarlineMeasureID)
            )
        }

        if let selectedCueTextID {
            return RenderedEditSelectionState(selectedObjectID: .cueText(selectedCueTextID))
        }

        if let selectedRoadmapMarkerID {
            return RenderedEditSelectionState(selectedObjectID: .roadmapMarker(selectedRoadmapMarkerID))
        }

        if let selectedChordID {
            return RenderedEditSelectionState(selectedObjectID: .chord(selectedChordID))
        }

        if let selectedMeasureID {
            return RenderedEditSelectionState(selectedObjectID: .measure(selectedMeasureID))
        }

        return RenderedEditSelectionState()
    }

    private func renderedEditTapProviders() -> [any RenderedEditHitTargetProvider] {
        var providers = [any RenderedEditHitTargetProvider]()

        if interactionMode.allowsChordInkEditing || interactionMode.allowsChordObjectEditing {
            providers.append(CommittedChordBarlineRenderedEditHitTargetProvider())
        }

        if interactionMode.allowsCueTextEditing {
            providers.append(CueTextRenderedEditHitTargetProvider())
        }

        if interactionMode == .browse {
            providers.append(RoadmapMarkerRenderedEditHitTargetProvider())
        }

        if interactionMode.allowsChordObjectEditing,
           !isChordObjectEditingTemporarilySuppressed() {
            providers.append(ChordRenderedEditHitTargetProvider())
        }

        if interactionMode == .browse {
            providers.append(RepeatSpanRenderedEditHitTargetProvider())
            providers.append(EndingSpanRenderedEditHitTargetProvider())
            providers.append(TimeSignatureRenderedEditHitTargetProvider())
        }

        if interactionMode.allowsMeasureSelection {
            providers.append(MeasureRenderedEditHitTargetProvider())
        }

        if interactionMode.allowsHeaderAuthoringSelection {
            providers.append(HeaderRenderedEditHitTargetProvider())
        }

        return providers
    }

    private func renderedEditContext() -> RenderedEditContext? {
        guard let pageLayout else {
            return nil
        }

        let committedBarlineMeasures = (interactionMode.allowsChordInkEditing || interactionMode.allowsChordObjectEditing)
            ? committedSimpleChordBarlineMeasures(in: pageLayout)
            : []

        return RenderedEditContext(
            pageLayout: pageLayout,
            layoutStyle: chart.layoutStyle,
            selection: renderedEditSelectionState(),
            committedChordBarlineMeasures: committedBarlineMeasures
        )
    }

    private func renderedEditTapTarget(at location: CGPoint) -> RenderedEditHitTarget? {
        guard let context = renderedEditContext() else {
            return nil
        }

        return RenderedEditRouter(providers: renderedEditTapProviders())
            .tapTarget(at: location, in: context)
    }

    private func renderedEditDragTarget(at location: CGPoint) -> RenderedEditHitTarget? {
        guard let context = renderedEditContext() else {
            return nil
        }

        return RenderedEditRouter(providers: renderedEditTapProviders())
            .dragTarget(at: location, in: context)
    }

    private func renderedEditDragState(at location: CGPoint) -> RenderedEditDragState? {
        guard let target = renderedEditDragTarget(at: location) else {
            return nil
        }

        return RenderedEditDragState(target: target, startLocation: location)
    }

    private func chordMoveHitTarget(at location: CGPoint) -> ChordEditHitTarget? {
        guard interactionMode.allowsChordObjectEditing,
              !isChordObjectEditingTemporarilySuppressed(),
              let pageLayout else {
            return nil
        }

        return LeadSheetChordObjectInteractionPolicy.resolvedMoveTarget(
            LeadSheetChordEditOverlayGeometry.moveHitTarget(at: location, in: pageLayout),
            selectedChordID: selectedChordID,
            requiresSelectionBeforeMove: false
        )
    }

    private func chordResizeHitTarget(at location: CGPoint) -> ChordEditHitTarget? {
        guard interactionMode.allowsChordObjectEditing,
              !isChordObjectEditingTemporarilySuppressed(),
              let pageLayout else {
            return nil
        }

        return LeadSheetChordEditOverlayGeometry.resizeHitTarget(
            at: location,
            in: pageLayout,
            selectedChordID: selectedChordID
        )
    }

    private func chordReviewHitTarget(at location: CGPoint) -> ChordEditHitTarget? {
        guard interactionMode.allowsChordObjectEditing,
              !isChordObjectEditingTemporarilySuppressed(),
              let pageLayout,
              let hitTarget = LeadSheetChordEditOverlayGeometry.hitTarget(at: location, in: pageLayout),
              hitTarget.action == .review else {
            return nil
        }

        return hitTarget
    }

    private enum EditableOverlayHitTarget {
        case draftBarline(ChordDraftBarlineHitTarget)
        case rendered(RenderedEditHitTarget)
    }

    private func editableOverlayHitTarget(at location: CGPoint) -> EditableOverlayHitTarget? {
        if let draftBarlineTarget = chordDraftBarlineHitTarget(at: location) {
            return .draftBarline(draftBarlineTarget)
        }

        if let renderedTarget = renderedEditTapTarget(at: location) {
            return .rendered(renderedTarget)
        }

        return nil
    }

    private func committedChordBarlineHitTarget(at location: CGPoint) -> CommittedChordBarlineHitTarget? {
        guard (interactionMode.allowsChordInkEditing || interactionMode.allowsChordObjectEditing),
              let pageLayout else {
            return nil
        }

        return LeadSheetCommittedChordBarlineOverlayGeometry.hitTarget(
            at: location,
            measures: committedSimpleChordBarlineMeasures(in: pageLayout),
            selectedMeasureID: selectedCommittedBarlineMeasureID
        )
    }

    private func chordDraftBarlineHitTarget(at location: CGPoint) -> ChordDraftBarlineHitTarget? {
        guard interactionMode.allowsChordInkEditing,
              let pageLayout,
              !chordPreviewState.draftBarlines.isEmpty else {
            return nil
        }

        return ChordDraftBarlineOverlayGeometry.hitTarget(
            at: location,
            barlines: chordPreviewState.draftBarlines,
            laneFrameForBarline: { [weak self] barline in
                self?.chordDraftLaneFrame(for: barline, in: pageLayout)
            },
            selectedBarlineID: selectedDraftBarlineID
        )
    }

    private func roadmapMarkerLayouts() -> [LeadSheetRoadmapMarkerLayout] {
        pageLayout?.systems.flatMap(\.roadmapMarkerLayouts) ?? []
    }

    private func cueTextLayouts() -> [LeadSheetCueTextLayout] {
        pageLayout?.systems.flatMap { system in
            system.measures.flatMap(\.cueTextLayouts)
        } ?? []
    }

    private func cueTextEditHitTarget(at location: CGPoint) -> CueTextEditHitTarget? {
        guard interactionMode.allowsCueTextEditing else {
            return nil
        }

        return LeadSheetCueTextEditOverlayGeometry.hitTarget(
            at: location,
            in: cueTextLayouts(),
            selectedCueTextID: selectedCueTextID
        )
    }

    private func cueTextMoveHitTarget(at location: CGPoint) -> LeadSheetCueTextLayout? {
        guard interactionMode.allowsCueTextEditing else {
            return nil
        }

        return LeadSheetCueTextEditOverlayGeometry.moveHitTarget(
            at: location,
            in: cueTextLayouts()
        )
    }

    private func roadmapMarkerEditHitTarget(at location: CGPoint) -> RoadmapMarkerEditHitTarget? {
        guard interactionMode == .browse else {
            return nil
        }

        return LeadSheetRoadmapMarkerEditOverlayGeometry.hitTarget(
            at: location,
            in: roadmapMarkerLayouts(),
            selectedMarkerID: selectedRoadmapMarkerID
        )
    }

    private func roadmapMarkerMoveHitTarget(at location: CGPoint) -> LeadSheetRoadmapMarkerLayout? {
        guard interactionMode == .browse else {
            return nil
        }

        return LeadSheetRoadmapMarkerEditOverlayGeometry.moveHitTarget(
            at: location,
            in: roadmapMarkerLayouts()
        )
    }

    private func roadmapMarkerHitTarget(at location: CGPoint) -> LeadSheetRoadmapMarkerLayout? {
        guard let pageLayout else {
            return nil
        }

        for system in pageLayout.systems.reversed() {
            for markerLayout in system.roadmapMarkerLayouts.reversed() {
                if LeadSheetRoadmapMarkerEditOverlayGeometry.editHitFrame(for: markerLayout).contains(location) {
                    return markerLayout
                }
            }
        }

        return nil
    }

    private func cueTextHitTarget(at location: CGPoint) -> LeadSheetCueTextLayout? {
        guard let pageLayout else {
            return nil
        }

        for system in pageLayout.systems.reversed() {
            for measure in system.measures.reversed() {
                for cueTextLayout in measure.cueTextLayouts.reversed() {
                    if cueTextLayout.hitFrame.contains(location) {
                        return cueTextLayout
                    }
                }
            }
        }

        return nil
    }

    private func objectMovePanStartHitTarget(at location: CGPoint) -> Bool {
        renderedEditDragState(at: location) != nil
    }

    private func panStartLocation(for recognizer: UIPanGestureRecognizer) -> CGPoint {
        let location = recognizer.location(in: self)
        let translation = recognizer.translation(in: self)
        return CGPoint(
            x: location.x - translation.x,
            y: location.y - translation.y
        )
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isSyncingInkCanvasFromModel else {
            ChordLaneLocalBreadcrumbs.record(
                "canvas_drawing_change_ignored_model_sync",
                fields: [
                    "mode": interactionMode,
                    "strokeCount": canvasView.drawing.strokes.count
                ]
            )
            return
        }

        handleActiveCanvasDrawingChange(
            eventName: "canvas_drawing_changed",
            strokeCount: canvasView.drawing.strokes.count
        )
    }

    private func handleActiveCanvasDrawingChange(
        eventName: String,
        strokeCount: Int
    ) {
        ChordLaneLocalBreadcrumbs.record(
            eventName,
            fields: [
                "mode": interactionMode,
                "strokeCount": strokeCount
            ]
        )
        inkPersistenceCoordinator.recordDrawingChange(strokeCount: strokeCount)
        updateChordInkConfirmOverlayVisibility()

        guard !isSyncingInkCanvasFromModel else {
            return
        }

        let activeRole = activeInkAuthoringSessionRole()
        if let role = activeRole {
            inkAuthoringSessionState.markDirty(role)
        }
        if handleEmptyChordInkDrawingChangeIfNeeded(activeRole: activeRole) {
            return
        }
        if interactionMode.allowsDirectRhythmicNotationInk {
            clearRhythmicNotationUnreadInkFeedback()
            recordRhythmicNotationDrawingChange()
        }

        scheduleInkSessionWorkAfterDrawingChange()
    }

    private func handleEmptyChordInkDrawingChangeIfNeeded(
        activeRole: LeadSheetInkAuthoringSessionRole?
    ) -> Bool {
        let rawStrokeCount = pageInkCanvasView.drawing.strokes.count
        let visibleStrokeCount = ChordInkDraftVisibleStrokePolicy.visibleStrokeCount(
            in: pageInkCanvasView.drawing
        )
        guard ChordInkEmptyDraftPreviewPolicy.shouldHandleEmptyChordInk(
            interactionMode: interactionMode,
            activeRole: activeRole,
            strokeCount: visibleStrokeCount
        ) else {
            return false
        }

        ChordLaneLocalBreadcrumbs.record(
            "clear_chord_draft_preview_empty_ink",
            fields: [
                "mode": interactionMode,
                "draftChordCount": chordPreviewState.draftChords.count,
                "draftBarlineCount": chordPreviewState.draftBarlines.count,
                "rawStrokeCount": rawStrokeCount,
                "visibleStrokeCount": visibleStrokeCount
            ]
        )
        lastBootstrappedChordDraftPreviewSnapshot = nil
        if ChordInkEmptyDraftPreviewPolicy.shouldDiscardDraftPreview(chordPreviewState) {
            var updatedPreviewState = chordPreviewState
            updatedPreviewState.discard()
            chordPreviewState = updatedPreviewState
            onChordInkDraftPreviewChanged?([])
            onChordInkDraftBarlinesChanged?([])
        }

        persistActiveInkIfNeeded(knownInkSnapshot: currentCanvasInkSnapshot())
        return true
    }

    private func eraseActiveInk(from startPoint: CGPoint, to endPoint: CGPoint) {
        let indicesToErase = LeadSheetActiveInkErasePolicy.strokeIndicesToErase(
            in: pageInkCanvasView.drawing,
            from: startPoint,
            to: endPoint
        )
        guard !indicesToErase.isEmpty else {
            return
        }

        isSyncingInkCanvasFromModel = true
        pageInkCanvasView.drawing = pageInkCanvasView.drawing.removingStrokes(at: indicesToErase)
        isSyncingInkCanvasFromModel = false

        ChordLaneLocalBreadcrumbs.record(
            "active_ink_erase_applied",
            fields: [
                "mode": interactionMode,
                "removedStrokeCount": indicesToErase.count,
                "remainingStrokeCount": pageInkCanvasView.drawing.strokes.count
            ]
        )
        IChartPerformanceTrace.record(
            "ink.manual_erase.applied",
            metadata: canvasPerformanceTraceMetadata(
                extra: [
                    "removedStrokes": "\(indicesToErase.count)",
                    "remainingStrokes": "\(pageInkCanvasView.drawing.strokes.count)"
                ]
            )
        )
        handleActiveCanvasDrawingChange(
            eventName: "active_ink_erase_changed",
            strokeCount: pageInkCanvasView.drawing.strokes.count
        )
    }

    @objc
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        if interactionMode.allowsChordInkEditing {
            handleChordEntryTap(at: recognizer.location(in: self))
            return
        }

        if interactionMode.allowsNoteSelection {
            handleNoteSelectionTap(at: recognizer.location(in: self))
            return
        }

        let location = recognizer.location(in: self)
        if interactionMode.allowsHeaderAuthoringSelection,
           LeadSheetCanvasInteractionTargeting.headerAuthoringContains(location, in: pageLayout) {
            onHeaderAuthoringRequested?()
            return
        }

        if interactionMode == .browse,
           let roadmapMarkerLayout = roadmapMarkerHitTarget(at: location) {
            selectRoadmapMarkerFromCanvas(roadmapMarkerLayout)
            return
        }

        if interactionMode.allowsCueTextEditing,
           let cueTextLayout = cueTextHitTarget(at: location),
           let cueText = chart.cueText(id: cueTextLayout.id) {
            selectCueTextFromCanvas(cueText)
            return
        }

        guard interactionMode.allowsMeasureSelection else {
            return
        }

        let tappedMeasure = LeadSheetCanvasInteractionTargeting.measure(
            at: location,
            in: pageLayout,
            layoutStyle: chart.layoutStyle
        )
        let tappedMeasureID = tappedMeasure?.sourceMeasureID

        if shouldFinalizeRhythmicNotationTap(at: location, nextMeasureID: tappedMeasureID),
           let activeMeasureID = selectedMeasureID,
           !finalizeRhythmicNotationIfNeeded(for: activeMeasureID) {
            restoreSelectedMeasureID(activeMeasureID)
            return
        }

        if let tappedMeasureID {
            selectMeasureFromCanvas(tappedMeasureID)
        } else {
            applyTapSelection(nil)
        }

        if interactionMode.showsTimeSignatureTargeting,
           let tappedMeasureID {
            onTimeSignatureTargetRequested?(tappedMeasureID)
        }
    }

    private func selectRoadmapMarkerFromCanvas(_ markerLayout: LeadSheetRoadmapMarkerLayout) {
        updateSelectedRoadmapMarkerID(markerLayout.id)
        selectedCueTextID = nil
        selectedChordID = nil
        selectedCommittedBarlineMeasureID = nil
        selectedNoteSelection = nil
        applyTapSelection(markerLayout.anchorMeasureID)
        onRoadmapMarkerSelectedFromCanvas?(markerLayout.id)
        setNeedsDisplay()
    }

    private func updateSelectedRoadmapMarkerID(_ markerID: UUID?) {
        selectedRoadmapMarkerID = markerID
        onRoadmapMarkerSelectionChanged?(markerID)
    }

    private func selectCueTextFromCanvas(_ cueText: CueText) {
        selectedCueTextID = cueText.id
        updateSelectedRoadmapMarkerID(nil)
        selectedChordID = nil
        selectedCommittedBarlineMeasureID = nil
        selectedNoteSelection = nil
        applyTapSelection(cueText.anchorMeasureID)
        onCueTextSelectedFromCanvas?(cueText.id)
        setNeedsDisplay()
    }

    @objc
    private func handleRenderedEditTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        let location = recognizer.location(in: renderedEditHitOverlayView)
        if let hitTarget = chordDraftBarlineHitTarget(at: location) {
            handleDraftBarlineTap(hitTarget)
            return
        }

        if let hitTarget = renderedEditTapTarget(at: location) {
            handleRenderedEditTap(hitTarget)
        }
    }

    private func handleRenderedEditTap(_ hitTarget: RenderedEditHitTarget) {
        switch hitTarget.objectID {
        case .chord(let chordID):
            handleRenderedChordTap(chordID: chordID, action: hitTarget.action)
        case .committedChordBarline(let measureID):
            handleRenderedCommittedBarlineTap(measureID: measureID, action: hitTarget.action)
        case .cueText(let cueTextID):
            handleRenderedCueTextTap(cueTextID: cueTextID, action: hitTarget.action)
        case .roadmapMarker(let markerID):
            handleRenderedRoadmapMarkerTap(markerID: markerID, action: hitTarget.action)
        case .header:
            if hitTarget.action == .openInspector {
                onHeaderAuthoringRequested?()
            }
        case .measure(let measureID):
            guard interactionMode.allowsMeasureSelection else {
                return
            }
            selectMeasureFromCanvas(measureID)
        case .repeatSpan(let roadmapObjectID):
            if hitTarget.action == .openInspector {
                selectRepeatSpanFromCanvas(roadmapObjectID)
            }
        case .endingSpan(let roadmapObjectID):
            if hitTarget.action == .openInspector {
                selectEndingSpanFromCanvas(roadmapObjectID)
            }
        case .timeSignatureChange(let measureID):
            if hitTarget.action == .openInspector {
                selectTimeSignatureFromCanvas(measureID)
            }
        case .keyChange:
            break
        }
    }

    private func selectMeasureFromCanvas(_ measureID: UUID) {
        selectedChordID = nil
        selectedCommittedBarlineMeasureID = nil
        selectedCueTextID = nil
        updateSelectedRoadmapMarkerID(nil)
        selectedNoteSelection = nil
        applyTapSelection(measureID)
        if interactionMode == .browse {
            onMeasureSelectedFromCanvas?(measureID)
        }
        setNeedsDisplay()
    }

    private func selectRepeatSpanFromCanvas(_ roadmapObjectID: UUID) {
        guard let roadmapObject = chart.roadmapObject(id: roadmapObjectID),
              roadmapObject.type == .repeatSpan else {
            return
        }

        selectStructuralMeasureAnchor(roadmapObject.startMeasureID)
        if interactionMode == .browse {
            onRepeatSpanSelectedFromCanvas?(roadmapObjectID)
        }
    }

    private func selectEndingSpanFromCanvas(_ roadmapObjectID: UUID) {
        guard let roadmapObject = chart.roadmapObject(id: roadmapObjectID),
              roadmapObject.type.isEnding else {
            return
        }

        selectStructuralMeasureAnchor(roadmapObject.startMeasureID)
        if interactionMode == .browse {
            onEndingSpanSelectedFromCanvas?(roadmapObjectID)
        }
    }

    private func selectTimeSignatureFromCanvas(_ measureID: UUID) {
        guard chart.measure(id: measureID) != nil else {
            return
        }

        selectStructuralMeasureAnchor(measureID)
        if interactionMode == .browse {
            onTimeSignatureSelectedFromCanvas?(measureID)
        }
    }

    private func selectStructuralMeasureAnchor(_ measureID: UUID) {
        selectedChordID = nil
        selectedCommittedBarlineMeasureID = nil
        selectedCueTextID = nil
        updateSelectedRoadmapMarkerID(nil)
        selectedNoteSelection = nil
        applyTapSelection(measureID)
        setNeedsDisplay()
    }

    private func handleRenderedChordTap(chordID: UUID, action: RenderedEditAction) {
        switch action {
        case .delete:
            deleteChordEvent(chordID)
        case .select, .move, .resizeLeading, .resizeTrailing, .correctChord:
            selectRenderedChordFromCanvas(chordID)
        case .resizeLeft, .resizeRight, .grow, .shrink, .editText, .openInspector:
            break
        }
    }

    private func selectRenderedChordFromCanvas(_ chordID: UUID) {
        selectedChordID = chordID
        selectedCommittedBarlineMeasureID = nil
        selectedCueTextID = nil
        updateSelectedRoadmapMarkerID(nil)
        selectedNoteSelection = nil
        if interactionMode == .browse {
            onChordSelectedFromCanvas?(chordID)
        }
        setNeedsDisplay()
    }

    private func handleRenderedCommittedBarlineTap(measureID: UUID, action: RenderedEditAction) {
        switch action {
        case .select:
            handleCommittedBarlineTap(CommittedChordBarlineHitTarget(measureID: measureID, action: .select))
        case .delete:
            handleCommittedBarlineTap(CommittedChordBarlineHitTarget(measureID: measureID, action: .delete))
        case .move, .resizeLeading, .resizeTrailing, .resizeLeft, .resizeRight,
             .grow, .shrink, .editText, .correctChord, .openInspector:
            break
        }
    }

    private func handleRenderedCueTextTap(cueTextID: UUID, action: RenderedEditAction) {
        switch action {
        case .select, .move:
            guard let cueText = chart.cueText(id: cueTextID) else {
                return
            }
            selectCueTextFromCanvas(cueText)
        case .editText:
            selectedCueTextID = cueTextID
            updateSelectedRoadmapMarkerID(nil)
            selectedChordID = nil
            selectedCommittedBarlineMeasureID = nil
            selectedNoteSelection = nil
            onCueTextEditRequested?(cueTextID)
            setNeedsDisplay()
        case .shrink:
            selectedCommittedBarlineMeasureID = nil
            resizeCueText(cueTextID, by: -CueText.scaleStep)
        case .grow:
            selectedCommittedBarlineMeasureID = nil
            resizeCueText(cueTextID, by: CueText.scaleStep)
        case .delete:
            deleteCueText(cueTextID)
        case .resizeLeading, .resizeTrailing, .resizeLeft, .resizeRight, .correctChord, .openInspector:
            break
        }
    }

    private func handleRenderedRoadmapMarkerTap(markerID: UUID, action: RenderedEditAction) {
        switch action {
        case .delete:
            handleRoadmapMarkerEditTap(RoadmapMarkerEditHitTarget(markerID: markerID, action: .delete))
        case .select, .move:
            handleRoadmapMarkerEditTap(RoadmapMarkerEditHitTarget(markerID: markerID, action: .select))
        case .resizeLeading, .resizeTrailing, .resizeLeft, .resizeRight,
             .grow, .shrink, .editText, .correctChord, .openInspector:
            break
        }
    }

    private func handleCueTextEditTap(_ hitTarget: CueTextEditHitTarget) {
        guard let cueText = chart.cueText(id: hitTarget.cueTextID) else {
            return
        }

        switch hitTarget.action {
        case .select:
            selectCueTextFromCanvas(cueText)
        case .edit:
            selectedCueTextID = hitTarget.cueTextID
            onCueTextEditRequested?(hitTarget.cueTextID)
            setNeedsDisplay()
        case .shrink:
            resizeCueText(hitTarget.cueTextID, by: -CueText.scaleStep)
        case .grow:
            resizeCueText(hitTarget.cueTextID, by: CueText.scaleStep)
        case .delete:
            deleteCueText(hitTarget.cueTextID)
        }
    }

    private func handleRoadmapMarkerEditTap(_ hitTarget: RoadmapMarkerEditHitTarget) {
        switch hitTarget.action {
        case .delete:
            deleteRoadmapMarker(hitTarget.markerID)
        case .move, .select:
            guard let markerLayout = roadmapMarkerLayouts().first(where: { $0.id == hitTarget.markerID }) else {
                updateSelectedRoadmapMarkerID(hitTarget.markerID)
                setNeedsDisplay()
                return
            }

            selectRoadmapMarkerFromCanvas(markerLayout)
        }
    }

    @objc
    private func handleChordCorrectionDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        let location = recognizer.location(in: renderedEditHitOverlayView)
        guard let hitTarget = chordReviewHitTarget(at: location) else {
            return
        }

        selectedChordID = hitTarget.chordID
        onChordCorrectionRequested?(hitTarget.chordID)
        setNeedsDisplay()
    }

    private func handleChordEntryTap(at location: CGPoint) {
        guard let pageLayout else {
            return
        }

        if let hitTarget = chordDraftBarlineHitTarget(at: location) {
            handleDraftBarlineTap(hitTarget)
            return
        }

        if let hitTarget = renderedEditTapTarget(at: location) {
            handleRenderedEditTap(hitTarget)
            return
        }

        if LeadSheetCanvasInteractionTargeting.chordWritingBandContains(location, in: pageLayout) {
            return
        }
    }

    private func handleDraftBarlineTap(_ hitTarget: ChordDraftBarlineHitTarget) {
        switch hitTarget.action {
        case .select:
            selectedDraftBarlineID = hitTarget.barlineID
            selectedChordID = nil
            selectedCommittedBarlineMeasureID = nil
            setNeedsDisplay()
        case .delete:
            deleteDraftBarline(hitTarget.barlineID)
        }
    }

    private func handleCommittedBarlineTap(_ hitTarget: CommittedChordBarlineHitTarget) {
        ChordLaneLocalBreadcrumbs.record(
            "committed_barline_tap",
            fields: [
                "mode": interactionMode,
                "action": hitTarget.action,
                "measureID": hitTarget.measureID
            ]
        )
        switch hitTarget.action {
        case .select:
            selectedCommittedBarlineMeasureID = hitTarget.measureID
            selectedDraftBarlineID = nil
            selectedChordID = nil
            selectedCueTextID = nil
            updateSelectedRoadmapMarkerID(nil)
            selectedNoteSelection = nil
            setNeedsDisplay()
        case .delete:
            deleteCommittedBarline(after: hitTarget.measureID)
        }
    }

    private func deleteCommittedBarline(after measureID: UUID) {
        var updatedChart = chart
        let oldMeasureCount = chart.measures.count
        let canDelete = updatedChart.canDeleteCommittedSimpleChordBarline(after: measureID)
        ChordLaneLocalBreadcrumbs.record(
            "committed_barline_delete_attempt",
            fields: [
                "mode": interactionMode,
                "measureID": measureID,
                "measureCount": chart.measures.count,
                "canDelete": canDelete
            ]
        )
        guard updatedChart.deleteCommittedSimpleChordBarline(after: measureID) else {
            selectedCommittedBarlineMeasureID = nil
            setNeedsDisplay()
            return
        }

        selectedCommittedBarlineMeasureID = nil
        selectedChordID = nil
        selectedDraftBarlineID = nil
        applyUpdatedChart(updatedChart, reason: "delete_committed_barline")
        ChordLaneLocalBreadcrumbs.record(
            "committed_barline_deleted",
            fields: [
                "mode": interactionMode,
                "measureID": measureID,
                "oldMeasureCount": oldMeasureCount,
                "newMeasureCount": chart.measures.count
            ]
        )
        setNeedsDisplay()
    }

    private func deleteDraftBarline(_ barlineID: UUID) {
        var updatedPreviewState = chordPreviewState
        guard let removedBarline = updatedPreviewState.removeDraftBarline(id: barlineID) else {
            selectedDraftBarlineID = nil
            setNeedsDisplay()
            return
        }

        selectedDraftBarlineID = nil
        chordPreviewState = updatedPreviewState
        removeDraftBarlineSourceStrokeIfNeeded(removedBarline)
        onChordInkDraftBarlinesChanged?(updatedPreviewState.draftBarlines)
        setNeedsDisplay()
    }

    private func removeDraftBarlineSourceStrokeIfNeeded(_ barline: DraftBarline) {
        guard let sourceStrokeIndex = barline.sourceStrokeIndex,
              pageInkCanvasView.drawing.strokes.indices.contains(sourceStrokeIndex) else {
            return
        }

        chordInkRecognitionRequestState.cancelPendingRequest()
        pageInkCanvasView.drawing = pageInkCanvasView.drawing.removingStrokes(at: [sourceStrokeIndex])
        inkAuthoringSessionState.markDirty(.chord)
        persistActiveInkIfNeeded(cancelPendingRecognition: false)

        let requestID = UUID()
        let scheduledAt = Date()
        chordInkRecognitionRequestState.beginRequest(requestID)
        recognizeChordInkIfNeeded(
            requestID: requestID,
            scheduledAt: scheduledAt,
            requestedDelay: 0,
            scheduledInkSnapshot: currentCanvasInkSnapshot(),
            flow: .draftPreview
        )
    }

    @objc
    private func handleChordInkConfirmTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              chordInkConfirmSurfaceContains(recognizer.location(in: self)) else {
            return
        }
    }

    private func chordInkConfirmSurfaceContains(_: CGPoint) -> Bool {
        false
    }

    private func deleteChordEvent(_ chordID: UUID) {
        guard let deletedChord = chart.chordEvent(id: chordID) else {
            return
        }

        var updatedChart = chart
        guard updatedChart.deleteChordEvent(chordID) else {
            return
        }

        applyUpdatedChart(updatedChart, reason: "delete_chord_event")
        selectedChordID = nil
        onChordDeleted?(deletedChord)
        setNeedsDisplay()
    }

    private func resizeCueText(_ cueTextID: UUID, by scaleDelta: Double) {
        var updatedChart = chart
        guard updatedChart.resizeCueText(cueTextID, byScaleDelta: scaleDelta) else {
            return
        }

        applyUpdatedChart(updatedChart, reason: "resize_cue_text")
        selectedCueTextID = cueTextID
        setNeedsDisplay()
    }

    private func deleteCueText(_ cueTextID: UUID) {
        var updatedChart = chart
        guard updatedChart.deleteCueText(cueTextID) else {
            return
        }

        if selectedCueTextID == cueTextID {
            selectedCueTextID = nil
        }
        if activeCueTextMoveDrag?.cueTextID == cueTextID {
            activeCueTextMoveDrag = nil
        }

        applyUpdatedChart(updatedChart, reason: "delete_cue_text")
        setNeedsDisplay()
    }

    private func deleteRoadmapMarker(_ markerID: UUID) {
        var updatedChart = chart
        guard updatedChart.deleteRoadmapObject(markerID) else {
            return
        }

        if selectedRoadmapMarkerID == markerID {
            updateSelectedRoadmapMarkerID(nil)
        }
        if activeRoadmapMarkerEditDrag?.markerID == markerID {
            activeRoadmapMarkerEditDrag = nil
        }

        applyUpdatedChart(updatedChart, reason: "delete_roadmap_marker")
        setNeedsDisplay()
    }

    private func handleNoteSelectionTap(at location: CGPoint) {
        guard let pageLayout,
              pageLayout.containsPaper(location) else {
            return
        }

        guard let lassoFrame = LeadSheetNoteSelectionLassoTargeting.lassoFrame(
            for: pageInkCanvasView.drawing,
            activeInkScope: activeInkScope(),
            ignoringTapAt: location,
            allowsNoteSelection: interactionMode.allowsNoteSelection
        ) else {
            return
        }

        let selection = pageLayout.noteSelection(in: lassoFrame)
        selectedNoteSelection = selection
        onNoteSelectionChanged?(selection)

        if selection != nil {
            selectedMeasureID = nil
            onMeasureSelectionChanged?(nil)
        }

        clearNoteSelectionInk()
        clearNoteSelectionInkAfterPencilKitSettles()
        setNeedsDisplay()
    }

    @objc
    private func handleMeasureResizePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: self)
            activeMeasureResizeDrag = measureResizeHandleHitTarget(at: location)
            if activeMeasureResizeDrag != nil {
                editorPerformanceMetrics.recordDragState(kind: .measureResize, state: recognizer.state)
            }
            setNeedsDisplay()
        case .changed:
            guard var activeMeasureResizeDrag else {
                return
            }

            editorPerformanceMetrics.recordDragState(kind: .measureResize, state: recognizer.state)
            let translationX = recognizer.translation(in: self).x
            if let transaction = activeMeasureResizeDrag.transaction {
                let preview = transaction.preview(for: translationX)
                activeMeasureResizeDrag.currentPreview = preview
                activeMeasureResizeDrag.currentFrame = preview.frame(for: activeMeasureResizeDrag.measureID)
                    ?? activeMeasureResizeDrag.currentFrame
            } else {
                activeMeasureResizeDrag.currentFrame = LeadSheetMeasureResizePreviewPolicy.previewFrame(
                    initialFrame: activeMeasureResizeDrag.initialFrame,
                    edge: activeMeasureResizeDrag.edge,
                    translationX: translationX
                )
            }
            self.activeMeasureResizeDrag = activeMeasureResizeDrag
            setNeedsDisplay()
        case .ended:
            guard let activeMeasureResizeDrag else {
                return
            }

            editorPerformanceMetrics.recordDragState(kind: .measureResize, state: recognizer.state)
            var updatedChart = chart
            let translationX = recognizer.translation(in: self).x
            let committedWidths: [UUID: CGFloat]
            if abs(translationX) < 0.5 {
                committedWidths = [:]
            } else if let transaction = activeMeasureResizeDrag.transaction {
                committedWidths = transaction.preview(for: translationX).committedManualWidths
            } else {
                committedWidths = [:]
            }
            var didApplyResize = false
            if committedWidths.isEmpty {
                guard abs(translationX) >= 0.5 else {
                    self.activeMeasureResizeDrag = nil
                    setNeedsDisplay()
                    return
                }
                let proposedWidth = LeadSheetMeasureResizePreviewPolicy.proposedModelWidth(
                    initialWidth: activeMeasureResizeDrag.initialWidth,
                    edge: activeMeasureResizeDrag.edge,
                    translationX: translationX
                )
                didApplyResize = updatedChart.setMeasureManualLayoutWidth(
                    proposedWidth,
                    for: activeMeasureResizeDrag.measureID
                ) != nil
            } else {
                for (measureID, width) in committedWidths {
                    didApplyResize = updatedChart.setMeasureManualLayoutWidth(width, for: measureID) != nil
                        || didApplyResize
                }
            }

            if didApplyResize {
                applyUpdatedChart(updatedChart, reason: "resize_measure")
            }

            self.activeMeasureResizeDrag = nil
            setNeedsDisplay()
        case .cancelled, .failed:
            if activeMeasureResizeDrag != nil {
                editorPerformanceMetrics.recordDragState(kind: .measureResize, state: recognizer.state)
            }
            activeMeasureResizeDrag = nil
            setNeedsDisplay()
        default:
            break
        }
    }

    @objc
    private func handleRenderedObjectMovePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        if activeCueTextMoveDrag != nil {
            handleCueTextMovePan(recognizer)
            return
        }

        if activeRoadmapMarkerEditDrag != nil {
            handleRoadmapMarkerEditPan(recognizer)
            return
        }

        if activeChordResizeDrag != nil {
            handleChordResizePan(recognizer)
            return
        }

        if recognizer.state == .began {
            let startLocation = panStartLocation(for: recognizer)
            guard let dragState = renderedEditDragState(at: startLocation) else {
                activeChordMoveDrag = nil
                setNeedsDisplay()
                return
            }

            switch (dragState.target.objectID, dragState.target.action) {
            case (.cueText(_), .move):
                handleCueTextMovePan(recognizer)
                return
            case (.roadmapMarker(_), .move):
                handleRoadmapMarkerEditPan(recognizer)
                return
            case (.chord(_), .resizeTrailing):
                handleChordResizePan(recognizer)
                return
            case (.chord(_), .move):
                break
            default:
                activeChordMoveDrag = nil
                setNeedsDisplay()
                return
            }
        }

        switch recognizer.state {
        case .began:
            let startLocation = panStartLocation(for: recognizer)
            guard let pageLayout,
                  let hitTarget = chordMoveHitTarget(at: startLocation),
                  let chordLayout = chordLayout(
                    for: hitTarget.chordID,
                    in: pageLayout
                  ) else {
                activeChordMoveDrag = nil
                setNeedsDisplay()
                return
            }

            selectedChordID = hitTarget.chordID
            activeChordMoveDrag = ActiveChordMoveDrag(
                chordID: hitTarget.chordID,
                sourcePageLayout: pageLayout,
                initialFrame: chordLayout.frame,
                currentFrame: chordLayout.frame,
                startLocation: startLocation
            )
            editorPerformanceMetrics.recordDragState(kind: .chordMove, state: recognizer.state)
            lockParentScrollForChordMove()
            setNeedsDisplay()
        case .changed, .ended:
            guard var activeChordMoveDrag,
                  let pageLayout else {
                if recognizer.state == .ended {
                    self.activeChordMoveDrag = nil
                    unlockParentScrollForChordMove()
                    setNeedsDisplay()
                }
                return
            }

            editorPerformanceMetrics.recordDragState(kind: .chordMove, state: recognizer.state)
            activeChordMoveDrag = chordMoveDragWithPositionPreview(
                activeChordMoveDrag,
                at: location,
                in: pageLayout
            )
            self.activeChordMoveDrag = activeChordMoveDrag
            setNeedsDisplay()

            if recognizer.state == .ended {
                commitChordMove(activeChordMoveDrag, at: location)
                self.activeChordMoveDrag = nil
                unlockParentScrollForChordMove()
                setNeedsDisplay()
            }
        case .cancelled, .failed:
            if activeChordMoveDrag != nil {
                editorPerformanceMetrics.recordDragState(kind: .chordMove, state: recognizer.state)
            }
            activeChordMoveDrag = nil
            unlockParentScrollForChordMove()
            setNeedsDisplay()
        default:
            break
        }
    }

    private func handleChordResizePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            let startLocation = panStartLocation(for: recognizer)
            guard let pageLayout,
                  let hitTarget = chordResizeHitTarget(at: startLocation),
                  let chordLayout = chordLayout(
                    for: hitTarget.chordID,
                    in: pageLayout
                  ) else {
                activeChordResizeDrag = nil
                setNeedsDisplay()
                return
            }

            switch hitTarget.action {
            case .resizeTrailing:
                break
            default:
                activeChordResizeDrag = nil
                setNeedsDisplay()
                return
            }

            selectedChordID = hitTarget.chordID
            activeChordResizeDrag = ActiveChordResizeDrag(
                chordID: hitTarget.chordID,
                sourcePageLayout: pageLayout,
                edge: .trailing,
                initialFrame: chordLayout.frame,
                currentFrame: chordLayout.frame,
                startLocation: startLocation
            )
            editorPerformanceMetrics.recordDragState(kind: .chordResize, state: recognizer.state)
            lockParentScrollForChordMove()
            setNeedsDisplay()

        case .changed, .ended:
            guard var activeChordResizeDrag,
                  let pageLayout else {
                if recognizer.state == .ended {
                    self.activeChordResizeDrag = nil
                    unlockParentScrollForChordMove()
                    setNeedsDisplay()
                }
                return
            }

            editorPerformanceMetrics.recordDragState(kind: .chordResize, state: recognizer.state)
            let activePaperFrame = paperFrame(containing: activeChordResizeDrag.initialFrame, in: pageLayout)
            activeChordResizeDrag.currentFrame = LeadSheetChordResizeDragPolicy.previewFrame(
                for: activeChordResizeDrag,
                at: location,
                boundedBy: activePaperFrame
            )
            self.activeChordResizeDrag = activeChordResizeDrag
            setNeedsDisplay()

            if recognizer.state == .ended {
                commitChordResize(activeChordResizeDrag)
                self.activeChordResizeDrag = nil
                unlockParentScrollForChordMove()
                setNeedsDisplay()
            }

        case .cancelled, .failed:
            if activeChordResizeDrag != nil {
                editorPerformanceMetrics.recordDragState(kind: .chordResize, state: recognizer.state)
            }
            activeChordResizeDrag = nil
            unlockParentScrollForChordMove()
            setNeedsDisplay()

        default:
            break
        }
    }

    private func commitChordResize(_ activeChordResizeDrag: ActiveChordResizeDrag) {
        var updatedChart = chart
        var didChange = false

        didChange = updatedChart.setChordEventManualDisplayWidth(
            Double(activeChordResizeDrag.currentFrame.width),
            for: activeChordResizeDrag.chordID
        ) != nil || didChange

        guard didChange else {
            return
        }

        applyUpdatedChart(updatedChart, reason: "resize_chord")
        selectedChordID = activeChordResizeDrag.chordID
    }

    private func chordLayout(
        for chordID: UUID,
        in pageLayout: LeadSheetPageLayout
    ) -> LeadSheetChordLayout? {
        pageLayout.systems
            .flatMap(\.measures)
            .flatMap(\.chordLayouts)
            .first { $0.id == chordID }
    }

    private func paperFrame(containing frame: CGRect, in pageLayout: LeadSheetPageLayout) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return pageLayout.paperFrame(containing: center) ?? pageLayout.paperFrame
    }

    private func chordMoveDragWithPositionPreview(
        _ drag: ActiveChordMoveDrag,
        at location: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> ActiveChordMoveDrag {
        var updatedDrag = drag
        let activePaperFrame = paperFrame(containing: drag.initialFrame, in: pageLayout)
        updatedDrag.currentFrame = LeadSheetChordMoveDragPolicy.previewFrame(
            for: drag,
            at: location,
            boundedBy: activePaperFrame
        )
        updatedDrag.currentPositionPreview = LeadSheetChordMoveDragPolicy.positionPreview(
            at: location,
            for: updatedDrag,
            chart: chart
        )

        guard let activeGuideX = updatedDrag.currentPositionPreview?.activeGuideX else {
            return updatedDrag
        }

        var snappedFrame = updatedDrag.currentFrame
        snappedFrame.origin.x = min(
            max(activeGuideX, activePaperFrame.minX),
            max(activePaperFrame.minX, activePaperFrame.maxX - snappedFrame.width)
        )
        updatedDrag.currentFrame = snappedFrame
        return updatedDrag
    }

    private func commitChordMove(
        _ activeChordMoveDrag: ActiveChordMoveDrag,
        at location: CGPoint
    ) {
        guard let target = LeadSheetChordMoveDragPolicy.target(
            at: location,
            for: activeChordMoveDrag,
            chart: chart
        ) else {
            return
        }

        var updatedChart = chart
        guard updatedChart.moveChordEventInCommittedChordLane(
            activeChordMoveDrag.chordID,
            to: target.measureID,
            atFraction: target.fraction
        ) else {
            return
        }

        applyUpdatedChart(updatedChart, reason: "move_chord")
    }

    private func handleCueTextMovePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let startLocation = panStartLocation(for: recognizer)
            guard let cueTextLayout = cueTextMoveHitTarget(at: startLocation),
                  let cueText = chart.cueText(id: cueTextLayout.id) else {
                activeCueTextMoveDrag = nil
                setNeedsDisplay()
                return
            }

            selectCueTextFromCanvas(cueText)
            activeCueTextMoveDrag = ActiveCueTextMoveDrag(
                cueTextID: cueTextLayout.id,
                startLocation: startLocation,
                initialFrame: cueTextLayout.frame,
                currentFrame: cueTextLayout.frame,
                startingVerticalOffset: cueText.verticalOffset
            )
            editorPerformanceMetrics.recordDragState(kind: .cueTextMove, state: recognizer.state)
            lockParentScrollForChordMove()
            setNeedsDisplay()

        case .changed, .ended:
            guard var activeCueTextMoveDrag else {
                if recognizer.state == .ended {
                    unlockParentScrollForChordMove()
                }
                return
            }

            editorPerformanceMetrics.recordDragState(kind: .cueTextMove, state: recognizer.state)
            let location = recognizer.location(in: self)
            activeCueTextMoveDrag.currentFrame = activeCueTextMoveDrag.initialFrame.offsetBy(
                dx: location.x - activeCueTextMoveDrag.startLocation.x,
                dy: location.y - activeCueTextMoveDrag.startLocation.y
            )
            self.activeCueTextMoveDrag = activeCueTextMoveDrag
            setNeedsDisplay()

            if recognizer.state == .ended {
                if let target = LeadSheetCanvasInteractionTargeting.cueTextMoveTarget(
                    at: location,
                    in: pageLayout,
                    chart: chart
                ) {
                    var updatedChart = chart
                    let verticalOffset = activeCueTextMoveDrag.startingVerticalOffset
                        + Double(location.y - activeCueTextMoveDrag.startLocation.y)
                    if updatedChart.moveCueText(
                        activeCueTextMoveDrag.cueTextID,
                        to: target.measureID,
                        atFraction: target.fraction,
                        verticalOffset: verticalOffset
                    ) {
                        applyUpdatedChart(updatedChart, reason: "move_cue_text")
                        selectedCueTextID = activeCueTextMoveDrag.cueTextID
                    }
                }
                self.activeCueTextMoveDrag = nil
                unlockParentScrollForChordMove()
                setNeedsDisplay()
            }

        case .cancelled, .failed:
            if activeCueTextMoveDrag != nil {
                editorPerformanceMetrics.recordDragState(kind: .cueTextMove, state: recognizer.state)
            }
            activeCueTextMoveDrag = nil
            unlockParentScrollForChordMove()
            setNeedsDisplay()

        default:
            break
        }
    }

    private func handleRoadmapMarkerEditPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let startLocation = panStartLocation(for: recognizer)
            guard let markerLayout = roadmapMarkerMoveHitTarget(at: startLocation) else {
                activeRoadmapMarkerEditDrag = nil
                setNeedsDisplay()
                return
            }

            selectRoadmapMarkerFromCanvas(markerLayout)
            activeRoadmapMarkerEditDrag = ActiveRoadmapMarkerEditDrag(
                markerID: markerLayout.id,
                initialFrame: markerLayout.frame,
                currentFrame: markerLayout.frame,
                movementFrame: markerLayout.movementFrame
            )
            editorPerformanceMetrics.recordDragState(kind: .roadmapMarkerMove, state: recognizer.state)
            lockParentScrollForChordMove()
            setNeedsDisplay()

        case .changed, .ended:
            guard var activeRoadmapMarkerEditDrag else {
                if recognizer.state == .ended {
                    unlockParentScrollForChordMove()
                }
                return
            }

            editorPerformanceMetrics.recordDragState(kind: .roadmapMarkerMove, state: recognizer.state)
            let translation = recognizer.translation(in: self)
            let proposedFrame = activeRoadmapMarkerEditDrag.initialFrame.offsetBy(
                dx: translation.x,
                dy: 0
            )
            let clampedFrame = LeadSheetRoadmapMarkerEditOverlayGeometry.clampedFrame(
                proposedFrame,
                in: activeRoadmapMarkerEditDrag.movementFrame
            )
            activeRoadmapMarkerEditDrag.currentFrame = clampedFrame
            self.activeRoadmapMarkerEditDrag = activeRoadmapMarkerEditDrag
            setNeedsDisplay()

            if recognizer.state == .ended {
                let normalizedOffset = LeadSheetRoadmapMarkerEditOverlayGeometry.normalizedOffset(
                    for: clampedFrame,
                    in: activeRoadmapMarkerEditDrag.movementFrame
                )
                var updatedChart = chart
                if updatedChart.movePointRoadmapMarkerHorizontally(
                    activeRoadmapMarkerEditDrag.markerID,
                    toNormalizedOffset: normalizedOffset
                ) {
                    applyUpdatedChart(updatedChart, reason: "move_roadmap_marker")
                }
                self.activeRoadmapMarkerEditDrag = nil
                unlockParentScrollForChordMove()
                setNeedsDisplay()
            }

        case .cancelled, .failed:
            if activeRoadmapMarkerEditDrag != nil {
                editorPerformanceMetrics.recordDragState(kind: .roadmapMarkerMove, state: recognizer.state)
            }
            activeRoadmapMarkerEditDrag = nil
            unlockParentScrollForChordMove()
            setNeedsDisplay()

        default:
            break
        }
    }

    private func syncPageInkCanvas() {
        ChordLaneLocalBreadcrumbs.record(
            "sync_page_ink_canvas",
            fields: [
                "mode": interactionMode,
                "hasActiveScope": activeInkScope() != nil,
                "canvasStrokes": pageInkCanvasView.drawing.strokes.count,
                "isDirtyChord": inkAuthoringSessionState.isDirty(.chord)
            ]
        )
        guard let activeInkScope = activeInkScope() else {
            if !interactionMode.allowsAnyInkEditing {
                ChordLaneLocalBreadcrumbs.record(
                    "sync_hide_no_ink_mode",
                    fields: ["mode": interactionMode]
                )
                pageInkCanvasView.isHidden = true
                pageInkCanvasView.isUserInteractionEnabled = false
                pageInkCanvasView.localInputFrames = []
                activeCanvasScopeIdentity = nil
                activeCanvasScope = nil
                activeCanvasCoordinateSpace = nil
                updateChordInkConfirmOverlayVisibility()
                return
            }

            persistActiveInkIfNeeded()
            ChordLaneLocalBreadcrumbs.record(
                "sync_hide_no_active_scope",
                fields: ["mode": interactionMode]
            )
            pageInkCanvasView.isHidden = true
            pageInkCanvasView.localInputFrames = []
            activeCanvasScopeIdentity = nil
            activeCanvasScope = nil
            activeCanvasCoordinateSpace = nil
            updateChordInkConfirmOverlayVisibility()
            return
        }

        LeadSheetLiveInkCanvasAppearancePolicy.configure(pageInkCanvasView)
        let targetScopeIdentity = activeInkScope.identity
        let outgoingCanvasScope = activeCanvasScope
        let switchedInkScope = activeCanvasScopeIdentity != nil
            && activeCanvasScopeIdentity != targetScopeIdentity
        let targetCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.coordinateSpace(
            for: activeInkScope,
            pageLayout: pageLayout
        )
        let shouldPreserveDirtyActiveCanvas = LeadSheetInkCanvasSyncPolicy.shouldPreserveDirtyActiveCanvas(
            activeInkScope: activeInkScope,
            interactionMode: interactionMode,
            sessionState: inkAuthoringSessionState,
            didSwitchInkScope: switchedInkScope
        )
        if switchedInkScope {
            if let outgoingCanvasScope {
                persistActiveInkIfNeeded(activeInkScope: outgoingCanvasScope)
            }
            activeCanvasCoordinateSpace = nil
        } else if !shouldPreserveDirtyActiveCanvas {
            reprojectActiveCanvasDrawingIfNeeded(
                activeInkScope: activeInkScope,
                to: targetCoordinateSpace
            )
        }
        pageInkCanvasView.isHidden = false
        pageInkCanvasView.isUserInteractionEnabled = true
        pageInkCanvasView.frame = activeInkScope.frame
        pageInkCanvasView.contentSize = activeInkScope.frame.size
        pageInkCanvasView.localInputFrames = activeInkScope.localInputFrames
        updateChordInkConfirmOverlayVisibility()
        if shouldPreserveDirtyActiveCanvas {
            ChordLaneLocalBreadcrumbs.record(
                "sync_preserve_dirty_active_canvas",
                fields: [
                    "mode": interactionMode,
                    "canvasStrokes": pageInkCanvasView.drawing.strokes.count,
                    "switchedScope": switchedInkScope
                ]
            )
            activeCanvasScopeIdentity = targetScopeIdentity
            activeCanvasScope = activeInkScope
            pageInkCanvasView.becomeFirstResponder()
            bootstrapRestoredChordDraftPreviewIfNeeded(reason: "preserved_dirty_active_canvas")
            return
        }
        normalizePersistentInkCanvasIfNeeded(activeInkScope: activeInkScope)

        let desiredData = activeInkScope.drawingData(in: chart)
        let desiredCoordinateSpace = activeInkScope.drawingCoordinateSpace(in: chart)
        let sourceCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.sourceCoordinateSpace(
            desiredCoordinateSpace,
            for: activeInkScope,
            chart: chart
        )
        let desiredCanvasData = LeadSheetPersistentInkCoordinateSpacePolicy.persistentDrawingData(
            from: desiredData,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        )
        let currentData = currentCanvasDrawingData()
        if LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
            activeInkScope: activeInkScope,
            interactionMode: interactionMode,
            sessionState: inkAuthoringSessionState,
            currentDrawingData: currentData,
            desiredDrawingData: desiredCanvasData,
            didSwitchInkScope: switchedInkScope
        ) {
            ChordLaneLocalBreadcrumbs.record(
                "sync_preserve_active_canvas",
                fields: [
                    "mode": interactionMode,
                    "canvasStrokes": pageInkCanvasView.drawing.strokes.count,
                    "desiredBytes": desiredCanvasData?.count,
                    "switchedScope": switchedInkScope
                ]
            )
            activeCanvasScopeIdentity = targetScopeIdentity
            activeCanvasScope = activeInkScope
            pageInkCanvasView.becomeFirstResponder()
            bootstrapRestoredChordDraftPreviewIfNeeded(reason: "preserved_active_canvas")
            return
        }

        guard currentData != desiredCanvasData else {
            ChordLaneLocalBreadcrumbs.record(
                "sync_canvas_already_current",
                fields: [
                    "mode": interactionMode,
                    "canvasStrokes": pageInkCanvasView.drawing.strokes.count,
                    "desiredBytes": desiredCanvasData?.count
                ]
            )
            activeCanvasScopeIdentity = targetScopeIdentity
            activeCanvasScope = activeInkScope
            activeCanvasCoordinateSpace = targetCoordinateSpace
            bootstrapRestoredChordDraftPreviewIfNeeded(reason: "already_current")
            return
        }

        if LeadSheetInkCanvasSyncPolicy.shouldTreatCanvasAsSynced(
            currentInkSnapshot: currentCanvasInkSnapshot(),
            desiredDrawingData: desiredCanvasData
        ) {
            ChordLaneLocalBreadcrumbs.record(
                "sync_treat_canvas_as_synced",
                fields: [
                    "mode": interactionMode,
                    "canvasStrokes": pageInkCanvasView.drawing.strokes.count,
                    "desiredBytes": desiredCanvasData?.count
                ]
            )
            activeCanvasScopeIdentity = targetScopeIdentity
            activeCanvasScope = activeInkScope
            activeCanvasCoordinateSpace = targetCoordinateSpace
            pageInkCanvasView.becomeFirstResponder()
            bootstrapRestoredChordDraftPreviewIfNeeded(reason: "treated_as_synced")
            return
        }

        inkPersistenceCoordinator.recordSyncLoad(strokeCount: pageInkCanvasView.drawing.strokes.count)
        isSyncingInkCanvasFromModel = true
        ChordLaneLocalBreadcrumbs.record(
            "sync_load_model_drawing",
            fields: [
                "mode": interactionMode,
                "currentBytes": currentData?.count,
                "desiredBytes": desiredCanvasData?.count,
                "sourceBytes": desiredData?.count
            ]
        )
        if let drawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            from: desiredData,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        ) {
            pageInkCanvasView.drawing = drawing
        } else {
            pageInkCanvasView.drawing = PKDrawing()
        }
        isSyncingInkCanvasFromModel = false
        ChordLaneLocalBreadcrumbs.record(
            "sync_loaded_model_drawing",
            fields: [
                "mode": interactionMode,
                "canvasStrokes": pageInkCanvasView.drawing.strokes.count
            ]
        )
        activeCanvasScopeIdentity = targetScopeIdentity
        activeCanvasScope = activeInkScope
        activeCanvasCoordinateSpace = targetCoordinateSpace
        updateChordInkConfirmOverlayVisibility()
        pageInkCanvasView.becomeFirstResponder()
        bootstrapRestoredChordDraftPreviewIfNeeded(reason: "loaded_model_drawing")
    }

    fileprivate func chartByApplyingPendingPersistedInk(to incomingChart: Chart) -> Chart {
        inkPersistenceCoordinator.chartByApplyingPendingPersistedInk(to: incomingChart)
    }

    private func reprojectActiveCanvasDrawingIfNeeded(
        activeInkScope: LeadSheetActiveInkScope,
        to targetCoordinateSpace: PersistentInkCoordinateSpace?
    ) {
        guard let targetCoordinateSpace else {
            activeCanvasCoordinateSpace = nil
            return
        }

        let sourceCoordinateSpace = activeCanvasCoordinateSpace
            ?? PersistentInkCoordinateSpace(size: pageInkCanvasView.bounds.size)
        guard let sourceCoordinateSpace,
              sourceCoordinateSpace != targetCoordinateSpace,
              !pageInkCanvasView.drawing.strokes.isEmpty else {
            activeCanvasCoordinateSpace = targetCoordinateSpace
            return
        }

        let strokeCount = pageInkCanvasView.drawing.strokes.count
        isSyncingInkCanvasFromModel = true
        pageInkCanvasView.drawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            pageInkCanvasView.drawing,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        )
        isSyncingInkCanvasFromModel = false
        activeCanvasCoordinateSpace = targetCoordinateSpace
        recordInkCoordinateSpaceReprojection(
            activeInkScope: activeInkScope,
            strokeCount: strokeCount,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        )
    }

    private func recordInkCoordinateSpaceReprojection(
        activeInkScope: LeadSheetActiveInkScope,
        strokeCount: Int,
        sourceCoordinateSpace: PersistentInkCoordinateSpace,
        targetCoordinateSpace: PersistentInkCoordinateSpace
    ) {
        guard strokeCount > 0,
              activeInkScope.persistsDrawingData else {
            return
        }

        IChartTelemetry.record(
            "ink.coordinate_space_reprojected",
            properties: [
                "scope": .string(activeInkScope.telemetryValue),
                "stroke_count": .int(strokeCount),
                "source_coordinate_width": .double(sourceCoordinateSpace.width),
                "source_coordinate_height": .double(sourceCoordinateSpace.height),
                "target_coordinate_width": .double(targetCoordinateSpace.width),
                "target_coordinate_height": .double(targetCoordinateSpace.height),
                "canvas_bounds_width": .double(Double(pageInkCanvasView.bounds.width)),
                "canvas_bounds_height": .double(Double(pageInkCanvasView.bounds.height))
            ]
        )
    }

    private func updateChordInkConfirmOverlayVisibility() {
        chordInkConfirmOverlayView.isHidden = true
        chordInkConfirmOverlayView.isUserInteractionEnabled = false
    }

    private func schedulePersistActiveInk() {
        switch activeInkAuthoringSessionRole() {
        case .chord:
            inkSchedulingCoordinator.cancelPersistence()
            lastBootstrappedChordDraftPreviewSnapshot = nil
            let scheduledInkSnapshot = currentCanvasInkSnapshot()
            ChordLaneLocalBreadcrumbs.record(
                "schedule_chord_draft_preview",
                fields: [
                    "mode": interactionMode,
                    "strokeCount": pageInkCanvasView.drawing.strokes.count,
                    "delay": ChordInkDraftPreviewPolicy.recognitionDelay
                ]
            )
            let workItem = DispatchWorkItem { [weak self] in
                self?.startDraftChordInkPreviewIfStable(
                    scheduledInkSnapshot: scheduledInkSnapshot
                )
            }
            inkSchedulingCoordinator.schedulePersistence(
                workItem,
                after: ChordInkDraftPreviewPolicy.recognitionDelay
            )
            return

        case .rhythm:
            guard let selectedMeasureID else {
                return
            }
            inkSchedulingCoordinator.cancelPersistence()
            let scheduledInkSnapshot = currentCanvasInkSnapshot()
            let workItem = DispatchWorkItem { [weak self] in
                self?.prepareRhythmicNotationTapToRenderIfStable(
                    for: selectedMeasureID,
                    scheduledInkSnapshot: scheduledInkSnapshot
                )
            }
            inkSchedulingCoordinator.schedulePersistence(
                workItem,
                after: LeadSheetRhythmicNotationAdvisoryPolicy.tapToRenderAdvisoryDelay
            )
            return

        case .passive:
            inkSchedulingCoordinator.cancelPersistence()
            let activeInkScope = activeInkScope()
            let scheduledInkSnapshot = currentCanvasInkSnapshot()
            let workItem = DispatchWorkItem { [weak self] in
                self?.persistPassiveInkIfStable(scheduledInkSnapshot: scheduledInkSnapshot)
            }
            inkSchedulingCoordinator.schedulePersistence(
                workItem,
                after: LeadSheetPassiveInkPersistencePolicy.idleDelay(for: activeInkScope)
            )
            return

        case nil:
            break
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.persistActiveInkIfNeeded()
        }
        inkSchedulingCoordinator.schedulePersistence(workItem, after: 0.22)
    }

    private func scheduleInkSessionWorkAfterDrawingChange() {
        cancelPendingInkSessionScheduledWork()
        inkPersistenceCoordinator.recordScheduledWork(strokeCount: pageInkCanvasView.drawing.strokes.count)
        ChordLaneLocalBreadcrumbs.record(
            "schedule_ink_session_after_drawing",
            fields: [
                "mode": interactionMode,
                "role": activeInkAuthoringSessionRole(),
                "strokeCount": pageInkCanvasView.drawing.strokes.count,
                "coalescingDelay": LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(for: inkResponsivenessValue)
            ]
        )
        let workItem = DispatchWorkItem { [weak self] in
            self?.inkSchedulingCoordinator.clearInputCoalescing()
            self?.schedulePersistActiveInk()
        }
        inkSchedulingCoordinator.scheduleInputCoalescing(
            workItem,
            after: LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(for: inkResponsivenessValue)
        )
    }

    private func cancelPendingInkSessionScheduledWork() {
        inkSchedulingCoordinator.cancelAll()
        chordInkRecognitionRequestState.cancelPendingRequest()
    }

    private func persistPassiveInkIfStable(scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?) {
        let currentInkSnapshot = currentCanvasInkSnapshot()
        guard LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
            currentInkSnapshot: currentInkSnapshot,
            scheduledInkSnapshot: scheduledInkSnapshot
        ) else {
            return
        }

        guard let activeInkScope = activeInkScope() else {
            return
        }

        let currentPersistedSnapshot = LeadSheetPersistedInkSnapshot(
            inkSnapshot: currentInkSnapshot,
            coordinateSpace: persistedCoordinateSpace(for: activeInkScope)
        )
        if inkPersistenceCoordinator.shouldSkipPersistence(
            activeInkScope: activeInkScope,
            currentSnapshot: currentPersistedSnapshot
        ) {
            inkPersistenceCoordinator.recordSkippedPersistence(strokeCount: pageInkCanvasView.drawing.strokes.count)
            clearDirtyInkAuthoringRole(.passive)
            return
        }

        persistActiveInkIfNeeded(knownInkSnapshot: currentInkSnapshot)
    }

    private func startDraftChordInkPreviewIfStable(
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) {
        inkSchedulingCoordinator.cancelPersistence()

        ChordLaneLocalBreadcrumbs.record(
            "start_draft_chord_preview_if_stable",
            fields: [
                "mode": interactionMode,
                "strokeCount": pageInkCanvasView.drawing.strokes.count,
                "hasScheduledSnapshot": scheduledInkSnapshot != nil
            ]
        )
        let requestID = UUID()
        let scheduledAt = Date()
        chordInkRecognitionRequestState.beginRequest(requestID)
        recognizeChordInkIfNeeded(
            requestID: requestID,
            scheduledAt: scheduledAt,
            requestedDelay: ChordInkDraftPreviewPolicy.recognitionDelay,
            scheduledInkSnapshot: scheduledInkSnapshot,
            flow: .draftPreview
        )
    }

    private func bootstrapRestoredChordDraftPreviewIfNeeded(reason: String) {
        let currentInkSnapshot = currentCanvasInkSnapshot()
        guard ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
            interactionMode: interactionMode,
            recognizesChordInk: recognizesChordInk,
            previewState: chordPreviewState,
            restoredDrawingData: chart.pageHandwrittenChordData,
            isDirtyChordInk: inkAuthoringSessionState.isDirty(.chord),
            currentInkSnapshot: currentInkSnapshot,
            lastBootstrappedSnapshot: lastBootstrappedChordDraftPreviewSnapshot
        ) else {
            return
        }

        guard case .chords = activeInkScope() else {
            return
        }

        ChordLaneLocalBreadcrumbs.record(
            "bootstrap_restored_chord_draft_preview",
            fields: [
                "reason": reason,
                "strokeCount": pageInkCanvasView.drawing.strokes.count,
                "hasSavedChordInk": chart.pageHandwrittenChordData != nil
            ]
        )
        lastBootstrappedChordDraftPreviewSnapshot = currentInkSnapshot
        let requestID = UUID()
        let scheduledAt = Date()
        chordInkRecognitionRequestState.beginRequest(requestID)
        inkSchedulingCoordinator.cancelPersistence()
        let workItem = DispatchWorkItem { [weak self] in
            self?.inkSchedulingCoordinator.clearPersistence()
            self?.recognizeChordInkIfNeeded(
                requestID: requestID,
                scheduledAt: scheduledAt,
                requestedDelay: ChordInkDraftPreviewPolicy.recognitionDelay,
                scheduledInkSnapshot: currentInkSnapshot,
                flow: .draftPreview
            )
        }
        inkSchedulingCoordinator.schedulePersistence(
            workItem,
            after: ChordInkDraftPreviewPolicy.recognitionDelay
        )
    }

    private func persistActiveInkIfNeeded(
        cancelPendingRecognition: Bool = true,
        activeInkScope explicitActiveInkScope: LeadSheetActiveInkScope? = nil,
        clearsDirtyAuthoringRole: Bool = true,
        knownInkSnapshot: LeadSheetInkDrawingSnapshot? = nil
    ) {
        inkSchedulingCoordinator.cancelInputCoalescing()

        if cancelPendingRecognition {
            inkSchedulingCoordinator.cancelPersistence()
            chordInkRecognitionRequestState.cancelPendingRequest()
        }

        guard let activeInkScope = explicitActiveInkScope ?? activeInkScope() else {
            return
        }

        let activeInkRole = LeadSheetInkAuthoringSessionRole.resolve(activeInkScope: activeInkScope)
        let strokeCount = pageInkCanvasView.drawing.strokes.count
        let persistenceStartedAt = ProcessInfo.processInfo.systemUptime
        let drawingData = currentCanvasDrawingData(activeInkScope: activeInkScope)
        let coordinateSpace = persistedCoordinateSpace(for: activeInkScope)
        let isDirtyAuthoringRole = activeInkRole.map { inkAuthoringSessionState.isDirty($0) } ?? false
        let persistenceDurationMilliseconds = (ProcessInfo.processInfo.systemUptime - persistenceStartedAt) * 1_000
        inkPersistenceCoordinator.recordPersistence(
            strokeCount: strokeCount,
            bytes: drawingData?.count ?? 0,
            durationMilliseconds: persistenceDurationMilliseconds
        )
        guard let updatedChart = activeInkScope.chartByPersistingDrawingData(
            drawingData,
            coordinateSpace: coordinateSpace,
            in: chart
        ) else {
            if LeadSheetPendingPersistedInkPolicy.shouldRecordEraseTombstone(
                activeInkScope: activeInkScope,
                drawingData: drawingData,
                isDirtyAuthoringRole: isDirtyAuthoringRole
            ) {
                inkPersistenceCoordinator.recordPendingPersistedInk(
                    activeInkScope: activeInkScope,
                    drawingData: nil,
                    coordinateSpace: nil
                )
                inkPersistenceCoordinator.recordPersistedSnapshot(
                    activeInkScope: activeInkScope,
                    inkSnapshot: knownInkSnapshot ?? currentCanvasInkSnapshot(),
                    coordinateSpace: nil
                )
            }
            if clearsDirtyAuthoringRole {
                clearDirtyInkAuthoringRole(activeInkRole)
            }
            return
        }

        inkPersistenceCoordinator.recordPendingPersistedInk(
            activeInkScope: activeInkScope,
            drawingData: drawingData,
            coordinateSpace: coordinateSpace
        )
        inkPersistenceCoordinator.recordPersistedSnapshot(
            activeInkScope: activeInkScope,
            inkSnapshot: knownInkSnapshot ?? currentCanvasInkSnapshot(),
            coordinateSpace: coordinateSpace
        )
        applyUpdatedChart(updatedChart, reason: "persist_active_ink")
        if strokeCount > 0,
           activeInkRole != nil {
            let telemetrySnapshot = LeadSheetInkTelemetrySnapshot.capture(
                drawing: pageInkCanvasView.drawing,
                canvasView: pageInkCanvasView
            )
            IChartTelemetry.record(
                "ink.persisted",
                properties: telemetrySnapshot.telemetryProperties(
                    scope: activeInkScope,
                    normalizedBeforeSave: activeInkScope.persistsDrawingData
                )
            )
            if telemetrySnapshot.normalizationNeeded {
                IChartTelemetry.record(
                    "ink.visibility_probe",
                    properties: telemetrySnapshot.telemetryProperties(
                        scope: activeInkScope,
                        normalizedBeforeSave: true
                    )
                )
            }
        }
        if clearsDirtyAuthoringRole {
            clearDirtyInkAuthoringRole(activeInkRole)
        }
    }

    private func recognizeChordInkIfNeeded(
        requestID: UUID,
        scheduledAt: Date,
        requestedDelay: TimeInterval,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?,
        flow: ChordInkRecognitionFlow
    ) {
        ChordLaneLocalBreadcrumbs.record(
            "recognize_chord_ink_enter",
            fields: [
                "flow": flow,
                "mode": interactionMode,
                "strokeCount": pageInkCanvasView.drawing.strokes.count
            ]
        )
        guard chordInkRecognitionRequestState.isActive(requestID) else {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_inactive_request",
                fields: ["flow": flow]
            )
            return
        }

        guard LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
            currentInkSnapshot: currentCanvasInkSnapshot(),
            scheduledInkSnapshot: scheduledInkSnapshot
        ) else {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_stale_snapshot",
                fields: ["flow": flow]
            )
            chordInkRecognitionRequestState.clearActiveRequest()
            return
        }

        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              let activeInkScope = activeInkScope(),
              case .chords(let chordFrame, _) = activeInkScope else {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_wrong_mode",
                fields: [
                    "flow": flow,
                    "mode": interactionMode,
                    "recognizesChordInk": recognizesChordInk
                ]
            )
            chordInkRecognitionRequestState.clearActiveRequest()
            return
        }

        guard let drawingData = currentCanvasDrawingData() else {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_no_drawing_data",
                fields: [
                    "flow": flow,
                    "dirtyChord": inkAuthoringSessionState.isDirty(.chord)
                ]
            )
            if inkAuthoringSessionState.isDirty(.chord) {
                persistActiveInkIfNeeded(
                    cancelPendingRecognition: false,
                    clearsDirtyAuthoringRole: flow != .draftPreview
                )
            }
            chordInkRecognitionRequestState.clearActiveRequest()
            if flow == .draftPreview {
                onChordInkDraftPreviewChanged?([])
                onChordInkDraftBarlinesChanged?([])
            }
            return
        }

        persistActiveInkIfNeeded(
            cancelPendingRecognition: false,
            clearsDirtyAuthoringRole: flow != .draftPreview
        )
        let sourceDrawing = pageInkCanvasView.drawing
        let visibleSourceContext = ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(
            from: sourceDrawing
        )
        let draftSourceDrawing = flow == .draftPreview
            ? visibleSourceContext.drawing
            : sourceDrawing
        let sourceStrokes = PencilKitInkAdapter.inkStrokes(from: draftSourceDrawing)
        if flow == .draftPreview,
           visibleSourceContext.visibleStrokeCount == 0 {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_no_visible_strokes",
                fields: [
                    "flow": flow,
                    "rawSourceStrokeCount": sourceDrawing.strokes.count,
                    "ignoredInvisibleStrokeCount": visibleSourceContext.invisibleStrokeIndices.count
                ]
            )
            chordInkRecognitionRequestState.clearActiveRequest()
            onChordInkDraftPreviewChanged?([])
            onChordInkDraftBarlinesChanged?([])
            return
        }

        let visibleBarlineRecognition = flow == .draftPreview
            ? ChordDraftBarlineRecognizer.recognize(
                strokes: sourceStrokes,
                chordFrame: chordFrame,
                pageLayout: pageLayout
            )
            : ChordDraftBarlineRecognition(barlines: [], strokeIndices: [])
        let barlineRecognition = flow == .draftPreview
            ? visibleSourceContext.remappedBarlineRecognition(visibleBarlineRecognition)
            : visibleBarlineRecognition
        if flow == .draftPreview {
            onChordInkDraftBarlinesChanged?(barlineRecognition.barlines)
        }
        let recognitionDrawing = flow == .draftPreview
            ? sourceDrawing.removingStrokes(
                at: barlineRecognition.strokeIndices.union(visibleSourceContext.invisibleStrokeIndices)
            )
            : sourceDrawing
        let recognitionDrawingData = flow == .draftPreview
            ? LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: recognitionDrawing)
            : drawingData
        guard let recognitionDrawingData else {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_no_recognition_data",
                fields: [
                    "flow": flow,
                    "sourceStrokeCount": sourceStrokes.count,
                    "barlineCount": barlineRecognition.barlines.count,
                    "rawSourceStrokeCount": sourceDrawing.strokes.count,
                    "ignoredInvisibleStrokeCount": visibleSourceContext.invisibleStrokeIndices.count
                ]
            )
            chordInkRecognitionRequestState.clearActiveRequest()
            if flow == .draftPreview {
                onChordInkDraftPreviewChanged?([])
            }
            return
        }

        let batchTargetingResult = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: recognitionDrawing,
            chordFrame: chordFrame,
            pageLayout: pageLayout,
            draftBarlines: flow == .draftPreview ? barlineRecognition.barlines : []
        )
        let batchTargets = batchTargetingResult.targets
        let boundedBatchTargets = ChordInkDraftPreviewRecognitionLoadPolicy.boundedBatchTargets(
            batchTargets,
            flow: flow
        )
        ChordDraftPreviewDeviceDiagnostics.recordTargeting(
            flow: flow,
            sourceStrokeCount: sourceStrokes.count,
            recognitionStrokeCount: recognitionDrawing.strokes.count,
            visibleStrokeCount: visibleSourceContext.visibleStrokeCount,
            ignoredInvisibleStrokeCount: visibleSourceContext.invisibleStrokeIndices.count,
            barlineCount: barlineRecognition.barlines.count,
            rawBatchTargets: batchTargets,
            boundedBatchTargets: boundedBatchTargets,
            targetingDiagnostics: batchTargetingResult.diagnostics,
            layoutStyle: chart.layoutStyle
        )
        let skippedBatchTargetCount = batchTargets.count - boundedBatchTargets.count
        if skippedBatchTargetCount > 0 {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_skip_large_batch_targets",
                fields: [
                    "flow": flow,
                    "skippedCount": skippedBatchTargetCount,
                    "keptCount": boundedBatchTargets.count,
                    "maxStrokeCount": ChordInkDraftPreviewPolicy.maximumBatchTargetStrokeCount
                ]
            )
        }
        ChordLaneLocalBreadcrumbs.record(
            "recognize_chord_ink_targeted",
            fields: [
                "flow": flow,
                "sourceStrokeCount": sourceStrokes.count,
                "recognitionStrokeCount": recognitionDrawing.strokes.count,
                "barlineCount": barlineRecognition.barlines.count,
                "batchTargetCount": boundedBatchTargets.count,
                "rawSourceStrokeCount": sourceDrawing.strokes.count,
                "ignoredInvisibleStrokeCount": visibleSourceContext.invisibleStrokeIndices.count
            ]
        )
        if batchTargets.count > 1 {
            guard !boundedBatchTargets.isEmpty else {
                ChordLaneLocalBreadcrumbs.record(
                    "recognize_chord_ink_skip_weak_batch_targets",
                    fields: [
                        "flow": flow,
                        "batchTargetCount": batchTargets.count,
                        "sourceStrokeCount": sourceStrokes.count,
                        "recognitionStrokeCount": recognitionDrawing.strokes.count
                    ]
                )
                chordInkRecognitionRequestState.clearActiveRequest()
                if flow == .draftPreview {
                    ChordDraftPreviewDeviceDiagnostics.recordNoTarget(
                        flow: flow,
                        stage: "skip_weak_batch_targets",
                        recognitionStrokeCount: recognitionDrawing.strokes.count,
                        rawBatchTargetCount: batchTargets.count,
                        boundedBatchTargetCount: boundedBatchTargets.count,
                        layoutStyle: chart.layoutStyle
                    )
                    onChordInkDraftPreviewChanged?([])
                }
                return
            }

            let sessionRequests = boundedBatchTargets.map { batchTarget in
                ChordInkRecognitionSessionRequest(
                    requestID: requestID,
                    scheduledAt: scheduledAt,
                    requestedDelay: requestedDelay,
                    strokes: batchTarget.strokes,
                    drawingData: batchTarget.drawingData,
                    target: (batchTarget.measureID, batchTarget.fraction),
                    visualOrder: batchTarget.visualOrder,
                    laneLocation: batchTarget.laneLocation,
                    layoutPageSize: pageLayout?.pageBounds.size,
                    options: chordInkRecognitionOptions
                )
            }

            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_start_batch",
                fields: [
                    "flow": flow,
                    "requestCount": sessionRequests.count
                ]
            )
            chordInkRecognitionSession.startBatch(requests: sessionRequests) { [weak self] payloads in
                self?.finishChordInkBatchRecognition(payloads, flow: flow)
            }
            return
        }

        let strokes = PencilKitInkAdapter.inkStrokes(from: recognitionDrawing)
        if !ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
            strokes: strokes,
            flow: flow
        ) {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_skip_single_target",
                fields: [
                    "flow": flow,
                    "strokeCount": strokes.count,
                    "maxStrokeCount": ChordInkDraftPreviewPolicy.maximumSingleTargetStrokeCount,
                    "batchTargetCount": batchTargets.count,
                    "keptBatchTargetCount": boundedBatchTargets.count
                ]
            )
            chordInkRecognitionRequestState.clearActiveRequest()
            ChordDraftPreviewDeviceDiagnostics.recordNoTarget(
                flow: flow,
                stage: "skip_single_target",
                recognitionStrokeCount: strokes.count,
                rawBatchTargetCount: batchTargets.count,
                boundedBatchTargetCount: boundedBatchTargets.count,
                layoutStyle: chart.layoutStyle
            )
            onChordInkDraftPreviewChanged?([])
            return
        }

        guard let target = LeadSheetChordInkRecognitionTargeting.target(
            for: recognitionDrawing,
            chordFrame: chordFrame,
            pageLayout: pageLayout
        ) else {
            ChordLaneLocalBreadcrumbs.record(
                "recognize_chord_ink_no_target",
                fields: [
                    "flow": flow,
                    "recognitionStrokeCount": recognitionDrawing.strokes.count
                ]
            )
            chordInkRecognitionRequestState.clearActiveRequest()
            if flow == .draftPreview {
                ChordDraftPreviewDeviceDiagnostics.recordNoTarget(
                    flow: flow,
                    stage: "no_target",
                    recognitionStrokeCount: recognitionDrawing.strokes.count,
                    rawBatchTargetCount: batchTargets.count,
                    boundedBatchTargetCount: boundedBatchTargets.count,
                    layoutStyle: chart.layoutStyle
                )
                onChordInkDraftPreviewChanged?([])
            }
            return
        }

        let sessionRequest = ChordInkRecognitionSessionRequest(
            requestID: requestID,
            scheduledAt: scheduledAt,
            requestedDelay: requestedDelay,
            strokes: strokes,
            drawingData: recognitionDrawingData,
            target: target,
            visualOrder: LeadSheetChordInkRecognitionTargeting.visualOrder(
                for: recognitionDrawing,
                chordFrame: chordFrame,
                pageLayout: pageLayout
            ),
            laneLocation: LeadSheetChordInkRecognitionTargeting.laneLocation(
                for: recognitionDrawing,
                chordFrame: chordFrame,
                pageLayout: pageLayout
            ),
            layoutPageSize: pageLayout?.pageBounds.size,
            options: chordInkRecognitionOptions
        )
        ChordDraftPreviewDeviceDiagnostics.recordSingleTarget(
            flow: flow,
            request: sessionRequest,
            layoutStyle: chart.layoutStyle
        )
        ChordLaneLocalBreadcrumbs.record(
            "recognize_chord_ink_start_single",
            fields: [
                "flow": flow,
                "strokeCount": strokes.count
            ]
        )
        chordInkRecognitionSession.start(request: sessionRequest) { [weak self] payload in
            self?.finishChordInkRecognition(payload, flow: flow)
        }
    }

    private func finishChordInkRecognition(
        _ payload: ChordInkRecognitionProposalPayload,
        flow: ChordInkRecognitionFlow
    ) {
        ChordLaneLocalBreadcrumbs.record(
            "finish_chord_ink_single",
            fields: [
                "flow": flow,
                "candidateCount": payload.result.rawCandidates.count,
                "strokeCount": payload.timing.strokeCount
            ]
        )
        guard chordInkRecognitionRequestState.finishActiveRequest(payload.requestID) else {
            ChordLaneLocalBreadcrumbs.record(
                "finish_chord_ink_single_inactive",
                fields: ["flow": flow]
            )
            return
        }

        LeadSheetChordInkRecognitionTimingLogger.log(payload.timing, result: payload.result)
        ChordDraftPreviewDeviceDiagnostics.recordPayloads(
            [payload],
            flow: flow,
            stage: "finish_single",
            layoutStyle: chart.layoutStyle
        )

        if flow == .draftPreview {
            onChordInkDraftPreviewChanged?(payload.result.rawCandidates.isEmpty ? [] : [payload])
            return
        }

        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              !payload.result.rawCandidates.isEmpty else {
            return
        }

        onChordInkRecognitionProposal?(
            payload.target.measureID,
            payload.result,
            payload.drawingData,
            payload.target.fraction,
            payload.timing,
            flow
        )
    }

    private func finishChordInkBatchRecognition(
        _ payloads: [ChordInkRecognitionProposalPayload],
        flow: ChordInkRecognitionFlow
    ) {
        ChordLaneLocalBreadcrumbs.record(
            "finish_chord_ink_batch",
            fields: [
                "flow": flow,
                "payloadCount": payloads.count,
                "candidatePayloadCount": payloads.filter { !$0.result.rawCandidates.isEmpty }.count
            ]
        )
        guard let requestID = payloads.first?.requestID,
              chordInkRecognitionRequestState.finishActiveRequest(requestID) else {
            ChordLaneLocalBreadcrumbs.record(
                "finish_chord_ink_batch_inactive",
                fields: ["flow": flow]
            )
            return
        }

        for payload in payloads {
            LeadSheetChordInkRecognitionTimingLogger.log(payload.timing, result: payload.result)
        }
        ChordDraftPreviewDeviceDiagnostics.recordPayloads(
            payloads,
            flow: flow,
            stage: "finish_batch",
            layoutStyle: chart.layoutStyle
        )

        if flow == .draftPreview {
            onChordInkDraftPreviewChanged?(payloads.filter { !$0.result.rawCandidates.isEmpty })
            return
        }

        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              payloads.count > 1 else {
            return
        }

        onChordInkBatchRecognitionProposal?(payloads, flow)
    }

    private func shouldFinalizeRhythmicNotation(from previousMeasureID: UUID?, to nextMeasureID: UUID?) -> Bool {
        LeadSheetRhythmicNotationFinalization.shouldFinalizeSelectionChange(
            interactionMode: interactionMode,
            isRestoringSelection: isRestoringSelection,
            isApplyingTapSelection: isApplyingTapSelection,
            previousMeasureID: previousMeasureID,
            nextMeasureID: nextMeasureID
        )
    }

    private func shouldFinalizeRhythmicNotationTap(
        at location: CGPoint,
        nextMeasureID: UUID?
    ) -> Bool {
        LeadSheetRhythmicNotationFinalization.shouldFinalizeTap(
            interactionMode: interactionMode,
            selectedMeasureID: selectedMeasureID,
            activeMeasureLayout: selectedMeasureID.flatMap { measureLayout(for: $0) },
            location: location,
            nextMeasureID: nextMeasureID
        )
    }

    private func finalizeRhythmicNotationIfNeeded(for measureID: UUID) -> Bool {
        let liveDrawingData = currentCanvasDrawingData()
        let liveDrawingCoordinateSpace = activeCanvasCoordinateSpace
        var workingChart = chart
        if interactionMode.allowsDirectRhythmicNotationInk,
           let updatedChart = LeadSheetRhythmicNotationFinalization.chartByPersistingLiveDrawing(
               liveDrawingData,
               coordinateSpace: liveDrawingCoordinateSpace,
               for: measureID,
               in: workingChart
            ) {
            clearDirtyInkAuthoringRole(.rhythm)
            applyUpdatedChart(updatedChart, reason: "persist_rhythm_on_finalize")
            workingChart = updatedChart
        }

        guard let measure = workingChart.measure(id: measureID),
              let drawingData = measure.handwrittenRhythmicNotationData,
              !drawingData.isEmpty,
              let measureLayout = measureLayout(for: measureID) else {
            clearRhythmicNotationUnreadInkFeedback()
            return true
        }

        do {
            let requiresNaturalExactFitAfterErase = rhythmicNotationEraseRecovery.requiresNaturalExactFit(
                for: measureID
            )
            let decision = try LeadSheetRhythmicNotationFinalization.recognitionDecision(
                drawingData: drawingData,
                measure: measure,
                defaultMeter: chart.defaultMeter,
                measureLayout: measureLayout
            )
            let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
                for: decision,
                requiresNaturalExactFitAfterErase: requiresNaturalExactFitAfterErase,
                allowsCommit: true,
                meter: measure.resolvedMeter(defaultMeter: chart.defaultMeter)
            )
            guard case .commit(let proposal) = route else {
                recordRhythmicNotationDiagnostic(
                    for: decision,
                    route: route,
                    stage: .inkPreserved,
                    measureID: measureID,
                    measure: measure,
                    drawingStrokeCount: drawingStrokeCount(from: drawingData),
                    drawingData: drawingData,
                    measureLayout: measureLayout
                )
                applyRhythmicNotationUnreadInkFeedback(for: decision, route: route, measureID: measureID)
                return false
            }

            if let updatedChart = LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
                proposal.values,
                drawingData: drawingData,
                drawingCoordinateSpace: measure.handwrittenRhythmicNotationCoordinateSpace,
                tieOutSlotIndices: proposal.tieOutSlotIndices,
                for: measureID,
                measureLayout: measureLayout,
                in: workingChart
            ) {
                clearRhythmicNotationUnreadInkFeedback()
                clearRhythmicNotationCanvas()
                applyUpdatedChart(updatedChart, reason: "finalize_rhythm_tap_render")
                setNeedsDisplay()
                recordRhythmicNotationDiagnostic(
                    for: decision,
                    route: route,
                    stage: .tapRendered,
                    measureID: measureID,
                    measure: measure,
                    drawingStrokeCount: drawingStrokeCount(from: drawingData),
                    drawingData: drawingData,
                    measureLayout: measureLayout
                )
            }

            return true
        } catch _ as RhythmicNotationQuantizationError {
            clearRhythmicNotationUnreadInkFeedback()
            return false
        } catch {
            clearRhythmicNotationUnreadInkFeedback()
            return false
        }
    }

    private func persistRhythmicNotationInkIfStable(
        for measureID: UUID,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) {
        guard interactionMode.allowsDirectRhythmicNotationInk,
              selectedMeasureID == measureID,
              LeadSheetRhythmicNotationAdvisoryPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: currentCanvasInkSnapshot(),
                scheduledInkSnapshot: scheduledInkSnapshot
              ) else {
            return
        }

        if let updatedChart = LeadSheetRhythmicNotationFinalization.chartByPersistingLiveDrawing(
            currentCanvasDrawingData(),
            coordinateSpace: activeCanvasCoordinateSpace,
            for: measureID,
            in: chart
        ) {
            clearDirtyInkAuthoringRole(.rhythm)
            applyUpdatedChart(updatedChart, reason: "persist_rhythm_stable")
            setNeedsDisplay()
        }
        clearRhythmicNotationUnreadInkFeedback()
    }

    private func prepareRhythmicNotationTapToRenderIfStable(
        for measureID: UUID,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) {
        guard LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
            interactionMode: interactionMode,
            selectedMeasureID: selectedMeasureID,
            targetMeasureID: measureID,
            currentInkSnapshot: currentCanvasInkSnapshot(),
            scheduledInkSnapshot: scheduledInkSnapshot
        ) else {
            return
        }

        guard let measure = chart.measure(id: measureID),
              let drawingData = currentCanvasDrawingData(),
              let measureLayout = measureLayout(for: measureID) else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        let requiresNaturalExactFitAfterErase = rhythmicNotationEraseRecovery.requiresNaturalExactFit(
            for: measureID
        )
        let decision: RhythmRecognitionDecision
        do {
            decision = try LeadSheetRhythmicNotationFinalization.recognitionDecision(
                drawingData: drawingData,
                measure: measure,
                defaultMeter: chart.defaultMeter,
                measureLayout: measureLayout
            )
        } catch {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: requiresNaturalExactFitAfterErase,
            allowsCommit: false,
            meter: measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        )
        guard !LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldCommitFromAdvisoryRoute(route) else {
            return
        }
        recordRhythmicNotationDiagnostic(
            for: decision,
            route: route,
            stage: route.isReadyToRender ? .tapToRenderCandidate : .inkPreserved,
            measureID: measureID,
            measure: measure,
            drawingStrokeCount: pageInkCanvasView.drawing.strokes.count,
            drawingData: drawingData,
            measureLayout: measureLayout
        )
        applyRhythmicNotationReadyOrUnreadFeedback(
            for: decision,
            route: route,
            measureID: measureID,
            showsUnreadFeedback: false
        )
    }

    private func confirmRhythmicNotationFeedback(_ feedback: LeadSheetRhythmicNotationPreviewState) {
        rhythmicNotationPreviewState = nil

        guard feedback.confirmationAction == .confirmSuggestion,
              let drawingData = currentCanvasDrawingData(),
              let measure = chart.measure(id: feedback.measureID),
              let measureLayout = measureLayout(for: feedback.measureID) else {
            return
        }

        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        guard RhythmicNotationCompendium.accepts(feedback.values, in: meter),
              let updatedChart = LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
                feedback.values,
                drawingData: drawingData,
                drawingCoordinateSpace: activeCanvasCoordinateSpace,
                tieOutSlotIndices: feedback.tieOutSlotIndices,
                for: feedback.measureID,
                measureLayout: measureLayout,
                in: chart
              ) else {
            return
        }

        inkSchedulingCoordinator.cancelPersistence()
        clearRhythmicNotationCanvas()
        applyUpdatedChart(updatedChart, reason: "confirm_rhythm_feedback")
        setNeedsDisplay()

        if let appliedMeasure = updatedChart.measure(id: feedback.measureID) {
            let event = RhythmRecognitionDiagnosticEvent(
                id: UUID(),
                timestamp: .now,
                chartID: updatedChart.id,
                chartTitle: updatedChart.title,
                measureID: feedback.measureID,
                measureIndex: appliedMeasure.index,
                layoutStyle: updatedChart.layoutStyle,
                meterText: meter.displayText,
                stage: .tapRendered,
                decision: "manualConfirm",
                route: "confirmSuggestion",
                reason: feedback.reason?.rawValue,
                proposalValues: feedback.values,
                proposalSafety: "manualReview",
                proposalIsNaturalExactFit: true,
                phraseSource: nil,
                naturalValues: feedback.values,
                naturalUnits: feedback.values.reduce(0) { partialResult, value in
                    partialResult + RhythmicNotationQuantizer.rhythmUnits(for: value, meter: meter)
                },
                targetUnits: RhythmicNotationQuantizer.rhythmUnits(
                    forWholeNotes: meter.measureLengthInWholeNotes
                ),
                passesCompendium: true,
                glyphEvidenceCount: nil,
                symbolCount: nil,
                unreadSymbolCount: nil,
                uncoveredStrokeCount: nil,
                inkStrokeCount: drawingStrokeCount(from: drawingData),
                pipelinePreview: nil
            )
            publishRhythmicNotationDiagnostic(event)
        }
    }

    func handleRhythmicNotationPreviewConfirmationRequest(_ requestID: UUID?) {
        guard let requestID,
              lastHandledRhythmicNotationPreviewConfirmationRequestID != requestID else {
            return
        }

        lastHandledRhythmicNotationPreviewConfirmationRequestID = requestID
        guard let rhythmicNotationPreviewState else {
            return
        }

        confirmRhythmicNotationFeedback(rhythmicNotationPreviewState)
    }

    func handleChordDraftRenderInvalidationRequest(_ requestID: UUID?) {
        guard let requestID,
              lastHandledChordDraftRenderInvalidationRequestID != requestID else {
            return
        }

        lastHandledChordDraftRenderInvalidationRequestID = requestID
        ChordLaneLocalBreadcrumbs.record(
            "chord_draft_render_invalidation",
            fields: [
                "mode": interactionMode,
                "canvasStrokes": pageInkCanvasView.drawing.strokes.count,
                "draftChordCount": chordPreviewState.draftChords.count,
                "draftBarlineCount": chordPreviewState.draftBarlines.count
            ]
        )
        cancelPendingInkSessionScheduledWork()
        clearChordDraftInkCanvas()
    }

    private func clearChordDraftInkCanvas() {
        ChordLaneLocalBreadcrumbs.record(
            "clear_chord_draft_ink_canvas",
            fields: [
                "mode": interactionMode,
                "canvasStrokes": pageInkCanvasView.drawing.strokes.count
            ]
        )
        guard let activeInkScope = activeInkScope(),
              case .chords = activeInkScope,
              !pageInkCanvasView.drawing.strokes.isEmpty else {
            clearDirtyInkAuthoringRole(.chord)
            return
        }

        isSyncingInkCanvasFromModel = true
        pageInkCanvasView.drawing = PKDrawing()
        isSyncingInkCanvasFromModel = false
        activeCanvasCoordinateSpace = nil
        clearDirtyInkAuthoringRole(.chord)
        updateChordInkConfirmOverlayVisibility()
    }

    private func recordRhythmicNotationDiagnostic(
        for decision: RhythmRecognitionDecision,
        route: LeadSheetRhythmicNotationLiveDecisionPolicy.Route,
        stage: RhythmRecognitionDiagnosticStage,
        measureID: UUID,
        measure: Measure,
        drawingStrokeCount: Int,
        drawingData: Data? = nil,
        measureLayout: LeadSheetMeasureLayout? = nil
    ) {
        guard IChartRuntimeDiagnostics.isRhythmRecognitionDiagnosticsEnabled else {
            return
        }

        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let pipelinePreview = drawingData.flatMap { drawingData in
            measureLayout.flatMap { measureLayout in
                RhythmRecognitionPipelinePreview.make(
                    drawingData: drawingData,
                    meter: meter,
                    drawingFrame: CGRect(
                        origin: .zero,
                        size: LeadSheetRhythmicNotationInkCapturePolicy.analysisFrame(
                            for: measureLayout
                        ).size
                    ),
                    decision: decision,
                    decisionText: decision.diagnosticDecisionText,
                    routeText: route.diagnosticRouteText
                )
            }
        }
        let event = RhythmRecognitionDiagnosticEvent(
            id: UUID(),
            timestamp: .now,
            chartID: chart.id,
            chartTitle: chart.title,
            measureID: measureID,
            measureIndex: measure.index,
            layoutStyle: chart.layoutStyle,
            meterText: meter.displayText,
            stage: stage,
            decision: decision.diagnosticDecisionText,
            route: route.diagnosticRouteText,
            reason: decision.reason?.rawValue,
            proposalValues: decision.proposal?.values ?? [],
            proposalSafety: decision.proposal?.safety.diagnosticText,
            proposalIsNaturalExactFit: decision.proposal?.isNaturalExactFit,
            phraseSource: decision.phrase?.source.rawValue,
            naturalValues: decision.phrase?.naturalValues ?? [],
            naturalUnits: decision.phrase?.naturalUnits,
            targetUnits: decision.phrase?.targetUnits,
            passesCompendium: decision.phrase?.passesCompendium,
            glyphEvidenceCount: decision.phrase?.glyphEvidence.count,
            symbolCount: decision.phrase?.symbols.count,
            unreadSymbolCount: decision.phrase?.symbols.filter { $0.selectedValue == nil }.count,
            uncoveredStrokeCount: decision.phrase?.uncoveredStrokeIndices.count,
            inkStrokeCount: drawingStrokeCount,
            pipelinePreview: pipelinePreview
        )
        publishRhythmicNotationDiagnostic(event)
    }

    private func publishRhythmicNotationDiagnostic(_ event: RhythmRecognitionDiagnosticEvent) {
        #if DEBUG && targetEnvironment(simulator)
        guard IChartRuntimeDiagnostics.isRhythmRecognitionDiagnosticsEnabled else {
            return
        }

        onRhythmicNotationDiagnostic?(event)
        do {
            try RhythmRecognitionDiagnosticsRecorder.live().append(event)
        } catch {
            print("iChart rhythm diagnostic error: \(error)")
        }
        #endif
    }

    private func drawingStrokeCount(from drawingData: Data) -> Int {
        (try? PKDrawing(data: drawingData).strokes.count) ?? 0
    }

    private func cancelPendingRhythmicNotationAdvisoryWork() {
        inkSchedulingCoordinator.cancelAll()
    }

    private func clearRhythmicNotationCanvas() {
        guard !pageInkCanvasView.drawing.strokes.isEmpty else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationEraseRecovery.reset()
        clearRhythmicNotationUnreadInkFeedback()
        isSyncingInkCanvasFromModel = true
        pageInkCanvasView.drawing = PKDrawing()
        isSyncingInkCanvasFromModel = false
        activeCanvasCoordinateSpace = nil
        clearDirtyInkAuthoringRole(.rhythm)
    }

    private func showRhythmicNotationUnreadInkFeedback(
        for decision: RhythmRecognitionDecision,
        measureID: UUID
    ) {
        let meter = rhythmicNotationPreviewMeter(for: measureID)
        let values = LeadSheetRhythmicNotationFeedbackPolicy.previewValues(for: decision, meter: meter)
        guard LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(for: decision),
              !values.isEmpty,
              let reason = decision.reason else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationPreviewState = LeadSheetRhythmicNotationPreviewState(
            measureID: measureID,
            meter: meter,
            reason: reason,
            values: values,
            tieOutSlotIndices: LeadSheetRhythmicNotationFeedbackPolicy.previewTieOutSlotIndices(for: decision),
            confirmationAction: LeadSheetRhythmicNotationFeedbackPolicy.confirmationAction(for: decision, meter: meter),
            isCertain: false
        )
    }

    private func showRhythmicNotationStaleInkFeedback(
        for decision: RhythmRecognitionDecision,
        measureID: UUID
    ) {
        let meter = rhythmicNotationPreviewMeter(for: measureID)
        let values = LeadSheetRhythmicNotationFeedbackPolicy.previewValues(for: decision, meter: meter)
        guard !values.isEmpty,
              let reason = decision.reason else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationPreviewState = LeadSheetRhythmicNotationPreviewState(
            measureID: measureID,
            meter: meter,
            reason: reason,
            values: values,
            tieOutSlotIndices: LeadSheetRhythmicNotationFeedbackPolicy.previewTieOutSlotIndices(for: decision),
            confirmationAction: LeadSheetRhythmicNotationFeedbackPolicy.confirmationAction(for: decision, meter: meter),
            isCertain: false
        )
    }

    private func showRhythmicNotationReadyToRenderFeedback(
        for decision: RhythmRecognitionDecision,
        measureID: UUID
    ) {
        let meter = rhythmicNotationPreviewMeter(for: measureID)
        let values = LeadSheetRhythmicNotationFeedbackPolicy.previewValues(for: decision, meter: meter)
        guard !values.isEmpty else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationPreviewState = LeadSheetRhythmicNotationPreviewState(
            measureID: measureID,
            meter: meter,
            reason: nil,
            values: values,
            tieOutSlotIndices: LeadSheetRhythmicNotationFeedbackPolicy.previewTieOutSlotIndices(for: decision),
            confirmationAction: .none,
            isCertain: true
        )
    }

    private func showRhythmicNotationLivePreviewFeedback(
        for decision: RhythmRecognitionDecision,
        measureID: UUID
    ) {
        let meter = rhythmicNotationPreviewMeter(for: measureID)
        let values = LeadSheetRhythmicNotationFeedbackPolicy.previewValues(for: decision, meter: meter)
        guard !values.isEmpty else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationPreviewState = LeadSheetRhythmicNotationPreviewState(
            measureID: measureID,
            meter: meter,
            reason: decision.reason,
            values: values,
            tieOutSlotIndices: LeadSheetRhythmicNotationFeedbackPolicy.previewTieOutSlotIndices(for: decision),
            confirmationAction: LeadSheetRhythmicNotationFeedbackPolicy.confirmationAction(for: decision, meter: meter),
            isCertain: decision.proposal?.isNaturalExactFit == true
        )
    }

    private func rhythmicNotationPreviewMeter(for measureID: UUID) -> Meter {
        chart.measure(id: measureID)?.resolvedMeter(defaultMeter: chart.defaultMeter) ?? chart.defaultMeter
    }

    @discardableResult
    private func applyRhythmicNotationUnreadInkFeedback(
        for decision: RhythmRecognitionDecision,
        route: LeadSheetRhythmicNotationLiveDecisionPolicy.Route,
        measureID: UUID
    ) -> Bool {
        guard case .preserveInk(let showsUnreadFeedback) = route else {
            clearRhythmicNotationUnreadInkFeedback()
            return false
        }

        if showsUnreadFeedback {
            showRhythmicNotationUnreadInkFeedback(for: decision, measureID: measureID)
        } else {
            showRhythmicNotationLivePreviewFeedback(for: decision, measureID: measureID)
        }
        return rhythmicNotationPreviewState != nil
    }

    @discardableResult
    private func applyRhythmicNotationReadyOrUnreadFeedback(
        for decision: RhythmRecognitionDecision,
        route: LeadSheetRhythmicNotationLiveDecisionPolicy.Route,
        measureID: UUID,
        showsUnreadFeedback: Bool = true
    ) -> Bool {
        if case .readyToRender = route {
            showRhythmicNotationReadyToRenderFeedback(for: decision, measureID: measureID)
            return rhythmicNotationPreviewState != nil
        }

        guard showsUnreadFeedback else {
            showRhythmicNotationLivePreviewFeedback(for: decision, measureID: measureID)
            return rhythmicNotationPreviewState != nil
        }

        return applyRhythmicNotationUnreadInkFeedback(
            for: decision,
            route: route,
            measureID: measureID
        )
    }

    private func clearRhythmicNotationUnreadInkFeedback() {
        rhythmicNotationPreviewState = nil
    }

    private func recordRhythmicNotationDrawingChange() {
        guard let selectedMeasureID else {
            return
        }

        if rhythmicNotationEraseRecovery.recordDrawingChange(
            selectedMeasureID: selectedMeasureID,
            inkToolMode: inkToolMode
        ) {
            cancelPendingRhythmicNotationAdvisoryWork()
        }
    }

    private func restoreSelectedMeasureID(_ measureID: UUID?) {
        guard !isRestoringSelection else {
            return
        }

        isRestoringSelection = true
        selectedMeasureID = measureID
        isRestoringSelection = false

        DispatchQueue.main.async { [weak self] in
            self?.onMeasureSelectionChanged?(measureID)
        }
    }

    private func applyTapSelection(_ measureID: UUID?) {
        isApplyingTapSelection = true
        selectedMeasureID = measureID
        isApplyingTapSelection = false
        onMeasureSelectionChanged?(measureID)
    }

    private func currentCanvasDrawingData() -> Data? {
        currentCanvasDrawingData(activeInkScope: activeInkScope())
    }

    private func currentCanvasDrawingData(activeInkScope: LeadSheetActiveInkScope?) -> Data? {
        let drawing = pageInkCanvasView.drawing
        guard !drawing.strokes.isEmpty else {
            return nil
        }

        if case .noteSelection? = activeInkScope {
            return drawing.dataRepresentation()
        }

        return LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: drawing)
    }

    private func persistedCoordinateSpace(for activeInkScope: LeadSheetActiveInkScope) -> PersistentInkCoordinateSpace? {
        guard activeInkScope.persistsDrawingData else {
            return nil
        }

        return activeCanvasCoordinateSpace
            ?? LeadSheetPersistentInkCoordinateSpacePolicy.coordinateSpace(
                for: activeInkScope,
                pageLayout: pageLayout
            )
    }

    private func currentCanvasInkSnapshot() -> LeadSheetInkDrawingSnapshot? {
        LeadSheetInkDrawingSnapshot(drawing: pageInkCanvasView.drawing)
    }

    private func normalizePersistentInkCanvasIfNeeded(activeInkScope explicitActiveInkScope: LeadSheetActiveInkScope? = nil) {
        guard let activeInkScope = explicitActiveInkScope ?? activeInkScope(),
              let activeInkRole = LeadSheetInkAuthoringSessionRole.resolve(activeInkScope: activeInkScope),
              LeadSheetLiveInkNormalizationPolicy.shouldNormalizeLiveCanvas(
                activeInkRole: activeInkRole,
                sessionState: inkAuthoringSessionState
              ),
              LeadSheetPersistentInkColorPolicy.needsNormalization(pageInkCanvasView.drawing) else {
            return
        }

        let telemetrySnapshot = LeadSheetInkTelemetrySnapshot.capture(
            drawing: pageInkCanvasView.drawing,
            canvasView: pageInkCanvasView
        )
        isSyncingInkCanvasFromModel = true
        pageInkCanvasView.drawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(pageInkCanvasView.drawing)
        isSyncingInkCanvasFromModel = false
        if telemetrySnapshot.strokeCount > 0 {
            IChartTelemetry.record(
                "ink.normalization_applied",
                properties: telemetrySnapshot.telemetryProperties(
                    scope: activeInkScope,
                    normalizedBeforeSave: false
                )
            )
        }
    }

    private func updateInteractionMode() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(
            for: interactionMode,
            inkToolMode: inkToolMode
        )
        selectionTapRecognizer.isEnabled = policy.selectionTapEnabled
        inkSelectionTapRecognizer.isEnabled = policy.inkSelectionTapEnabled
        measureResizePanRecognizer.isEnabled = policy.measureResizePanEnabled
        renderedEditTapRecognizer.isEnabled = policy.renderedEditTapEnabled
        chordCorrectionDoubleTapRecognizer.isEnabled = policy.renderedEditTapEnabled
        renderedObjectMovePanRecognizer.isEnabled = policy.renderedObjectMovePanEnabled
        renderedEditHitOverlayView.isHidden = policy.renderedEditOverlayHidden
        renderedEditHitOverlayView.isUserInteractionEnabled = policy.renderedEditOverlayInteractionEnabled
        LeadSheetLiveInkCanvasAppearancePolicy.configure(pageInkCanvasView)
        pageInkCanvasView.isUserInteractionEnabled = policy.pageInkCanvasInteractionEnabled
        pageInkCanvasView.drawingPolicy = policy.drawingPolicy
        pageInkCanvasView.tool = policy.canvasTool
        pageInkCanvasView.manualEraseEnabled = policy.pageInkCanvasInteractionEnabled
            && policy.inkToolMode == .erase

        if policy.clearsMeasureResizeDrag {
            activeMeasureResizeDrag = nil
        }

        if policy.clearsRenderedObjectInteractionState {
            activeChordMoveDrag = nil
            activeChordResizeDrag = nil
            activeRoadmapMarkerEditDrag = nil
            activeCueTextMoveDrag = nil
            unlockParentScrollForChordMove()
        }

        if !interactionMode.allowsChordInkEditing {
            chordInkRecognitionRequestState.clearForChordEditingDisabled()
        }

        if policy.hidesPageInkCanvas {
            pageInkCanvasView.isHidden = true
            pageInkCanvasView.resignFirstResponder()
        }

        updateChordInkConfirmOverlayVisibility()
    }

    private func clearNoteSelectionInk() {
        guard !pageInkCanvasView.drawing.strokes.isEmpty else {
            return
        }

        isSyncingInkCanvasFromModel = true
        pageInkCanvasView.drawing = PKDrawing()
        isSyncingInkCanvasFromModel = false
        activeCanvasCoordinateSpace = nil
    }

    private func clearNoteSelectionInkAfterPencilKitSettles() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  interactionMode.allowsNoteSelectionInk else {
                return
            }

            clearNoteSelectionInk()
        }
    }

    private func activeInkScope() -> LeadSheetActiveInkScope? {
        activeInkScope(for: interactionMode)
    }

    private func activeInkAuthoringSessionRole() -> LeadSheetInkAuthoringSessionRole? {
        guard let activeInkScope = activeInkScope() else {
            return nil
        }

        return LeadSheetInkAuthoringSessionRole.resolve(
            activeInkScope: activeInkScope,
            interactionMode: interactionMode
        )
    }

    private func clearDirtyInkAuthoringRole(_ role: LeadSheetInkAuthoringSessionRole?) {
        guard let role else {
            return
        }

        inkAuthoringSessionState.clear(role)
    }

    private func activeInkScope(for interactionMode: EditorCanvasMode) -> LeadSheetActiveInkScope? {
        LeadSheetActiveInkScope.resolve(
            interactionMode: interactionMode,
            chartLayoutStyle: chart.layoutStyle,
            selectedMeasureID: selectedMeasureID,
            selectedMeasureLayout: selectedMeasureID.flatMap { measureLayout(for: $0) },
            pageLayout: pageLayout
        )
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === measureResizePanRecognizer {
            let location = gestureRecognizer.location(in: self)
            return measureResizeHandleHitTarget(at: location) != nil
        }

        if gestureRecognizer === selectionTapRecognizer,
           chordInkConfirmSurfaceContains(gestureRecognizer.location(in: self)) {
            return false
        }

        if gestureRecognizer === chordInkConfirmTapRecognizer {
            return chordInkConfirmSurfaceContains(gestureRecognizer.location(in: self))
        }

        if gestureRecognizer === renderedObjectMovePanRecognizer {
            let location = gestureRecognizer.location(in: self)
            let translation = renderedObjectMovePanRecognizer.translation(in: self)
            let startLocation = CGPoint(
                x: location.x - translation.x,
                y: location.y - translation.y
            )
            return objectMovePanStartHitTarget(at: startLocation)
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let involvesRenderedObjectMove = gestureRecognizer === renderedObjectMovePanRecognizer
            || otherGestureRecognizer === renderedObjectMovePanRecognizer
        let involvesParentScroll = isParentScrollGesture(gestureRecognizer)
            || isParentScrollGesture(otherGestureRecognizer)
        if !LeadSheetRenderedObjectMoveScrollLockPolicy.allowsSimultaneousRecognition(
            involvesRenderedObjectMove: involvesRenderedObjectMove,
            involvesParentScroll: involvesParentScroll
        ) {
            return false
        }

        return gestureRecognizer === inkSelectionTapRecognizer
            || otherGestureRecognizer === inkSelectionTapRecognizer
            || involvesRenderedObjectMove
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        if gestureRecognizer === renderedObjectMovePanRecognizer {
            return LeadSheetObjectMoveTouchPolicy.allowsMovePan(
                touchType: touch.type,
                interactionMode: interactionMode,
                startsOnMoveTarget: objectMovePanStartHitTarget(at: touch.location(in: self))
            )
        }

        return LeadSheetLiveInkInputPolicy.allowsCanvasGestureTouch(
            touchType: touch.type,
            interactionMode: interactionMode
        )
    }
}

private final class LeadSheetParentScrollGestureGate: NSObject, UIGestureRecognizerDelegate {
    weak var canvasView: LeadSheetCanvasUIKitView?
    weak var scrollView: UIScrollView?
    private var panBlocker: UIPanGestureRecognizer?
    private var pinchBlocker: UIPinchGestureRecognizer?
    private var blocksCurrentParentScrollGesture = false

    func install(in scrollView: UIScrollView, canvasView: LeadSheetCanvasUIKitView) {
        if self.scrollView !== scrollView {
            uninstall()
            self.scrollView = scrollView

            let panBlocker = UIPanGestureRecognizer(target: self, action: #selector(handleBlockerGesture(_:)))
            configureBlocker(panBlocker)
            self.panBlocker = panBlocker
            scrollView.addGestureRecognizer(panBlocker)
            scrollView.panGestureRecognizer.require(toFail: panBlocker)

            if let pinchGestureRecognizer = scrollView.pinchGestureRecognizer {
                let pinchBlocker = UIPinchGestureRecognizer(target: self, action: #selector(handleBlockerGesture(_:)))
                configureBlocker(pinchBlocker)
                self.pinchBlocker = pinchBlocker
                scrollView.addGestureRecognizer(pinchBlocker)
                pinchGestureRecognizer.require(toFail: pinchBlocker)
            }
        }

        self.canvasView = canvasView
    }

    func updateCanvasView(_ canvasView: LeadSheetCanvasUIKitView) {
        self.canvasView = canvasView
    }

    func uninstall() {
        if let scrollView {
            if let panBlocker {
                scrollView.removeGestureRecognizer(panBlocker)
            }
            if let pinchBlocker {
                scrollView.removeGestureRecognizer(pinchBlocker)
            }
        }

        scrollView = nil
        canvasView = nil
        panBlocker = nil
        pinchBlocker = nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isBlockerGesture(gestureRecognizer),
              let canvasView else {
            return true
        }

        if blocksCurrentParentScrollGesture {
            return true
        }

        return !canvasView.allowsParentScrollGestureStart(at: gestureRecognizer.location(in: canvasView))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        isBlockerGesture(gestureRecognizer) && !isScrollGesture(otherGestureRecognizer)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard isBlockerGesture(gestureRecognizer),
              let canvasView else {
            return true
        }

        let blocksTouch = canvasView.shouldBlockParentScrollTouch(touch)
        blocksCurrentParentScrollGesture = blocksTouch
        return blocksTouch || !canvasView.allowsParentScrollGestureStart(at: touch.location(in: canvasView))
    }

    private func isScrollGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let scrollView else {
            return false
        }

        return gestureRecognizer === scrollView.panGestureRecognizer
            || gestureRecognizer === scrollView.pinchGestureRecognizer
    }

    private func isBlockerGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panBlocker,
           gestureRecognizer === panBlocker {
            return true
        }
        if let pinchBlocker,
           gestureRecognizer === pinchBlocker {
            return true
        }
        return false
    }

    private func configureBlocker(_ recognizer: UIGestureRecognizer) {
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
    }

    @objc private func handleBlockerGesture(_ recognizer: UIGestureRecognizer) {
        // The blocker only exists to make the parent scroll recognizer wait/fail.
        switch recognizer.state {
        case .ended, .cancelled, .failed:
            blocksCurrentParentScrollGesture = false
        default:
            break
        }
    }

    deinit {
        uninstall()
    }
}

private extension PKDrawing {
    func removingStrokes(at indices: Set<Int>) -> PKDrawing {
        guard !indices.isEmpty else {
            return self
        }

        let retainedStrokes = strokes.enumerated().compactMap { index, stroke in
            indices.contains(index) ? nil : stroke
        }
        return PKDrawing(strokes: retainedStrokes)
    }
}

#endif

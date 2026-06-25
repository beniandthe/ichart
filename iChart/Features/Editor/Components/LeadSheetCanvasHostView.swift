#if canImport(UIKit)
import Foundation
import PencilKit
import SwiftUI
import UIKit

struct LeadSheetCanvasHostView: UIViewRepresentable {
    @Binding var chart: Chart
    @Binding var selectedMeasureID: UUID?
    @Binding var selectedNoteSelection: LeadSheetNoteSelection?
    @Binding var selectedCueTextID: UUID?
    @Binding var selectedRoadmapMarkerID: UUID?
    let interactionMode: EditorCanvasMode
    let inkToolMode: EditorInkToolMode
    var recognizesChordInk: Bool = true
    var inkResponsivenessValue: Double = LeadSheetInkResponsivenessPolicy.defaultValue
    var onTimeSignatureTargetRequested: ((UUID) -> Void)? = nil
    var onChordInkRecognitionProposal: ((UUID, ChordInkRecognitionResult, Data, Double?, ChordInkRecognitionTiming, ChordInkRecognitionFlow) -> Void)? = nil
    var onChordInkBatchRecognitionProposal: (([ChordInkRecognitionProposalPayload], ChordInkRecognitionFlow) -> Void)? = nil
    var onChordCorrectionRequested: ((UUID) -> Void)? = nil
    var onChordDeleted: ((ChordEvent) -> Void)? = nil
    var onNoteSelectionChanged: ((LeadSheetNoteSelection?) -> Void)? = nil
    var onMeasureSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onChordSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onCueTextSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onCueTextEditRequested: ((UUID) -> Void)? = nil
    var onRoadmapMarkerSelectedFromCanvas: ((UUID) -> Void)? = nil
    var onHeaderAuthoringRequested: (() -> Void)? = nil
    var onFreehandSymbolSelected: ((UUID) -> Void)? = nil
    var rhythmicNotationPreviewConfirmationRequestID: UUID? = nil
    var onRhythmicNotationPreviewChanged: ((LeadSheetRhythmicNotationPreviewState?) -> Void)? = nil
    var onRhythmicNotationDiagnostic: ((RhythmRecognitionDiagnosticEvent) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            chart: $chart,
            selectedMeasureID: $selectedMeasureID,
            selectedNoteSelection: $selectedNoteSelection,
            selectedRoadmapMarkerID: $selectedRoadmapMarkerID
        )
    }

    func makeUIView(context: Context) -> LeadSheetCanvasUIKitView {
        let view = LeadSheetCanvasUIKitView()
        configure(view, context: context)
        return view
    }

    func updateUIView(_ uiView: LeadSheetCanvasUIKitView, context: Context) {
        configure(uiView, context: context)
    }

    private func configure(_ view: LeadSheetCanvasUIKitView, context: Context) {
        view.chart = chart
        view.selectedMeasureID = selectedMeasureID
        view.selectedNoteSelection = selectedNoteSelection
        view.selectedCueTextID = selectedCueTextID
        view.selectedRoadmapMarkerID = selectedRoadmapMarkerID
        view.interactionMode = interactionMode
        view.inkToolMode = inkToolMode
        view.recognizesChordInk = recognizesChordInk
        view.inkResponsivenessValue = inkResponsivenessValue
        view.restrictsParentScrollToOutsideMargins = interactionMode.restrictsPageScrollToOutsideMargins
        view.onMeasureSelectionChanged = { measureID in
            context.coordinator.selectedMeasureID.wrappedValue = measureID
        }
        view.onNoteSelectionChanged = { selection in
            context.coordinator.selectedNoteSelection.wrappedValue = selection
            onNoteSelectionChanged?(selection)
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
        view.onChordCorrectionRequested = onChordCorrectionRequested
        view.onChordDeleted = onChordDeleted
        view.onMeasureSelectedFromCanvas = onMeasureSelectedFromCanvas
        view.onChordSelectedFromCanvas = onChordSelectedFromCanvas
        view.onCueTextSelectedFromCanvas = onCueTextSelectedFromCanvas
        view.onCueTextEditRequested = onCueTextEditRequested
        view.onRoadmapMarkerSelectedFromCanvas = onRoadmapMarkerSelectedFromCanvas
        view.onHeaderAuthoringRequested = onHeaderAuthoringRequested
        view.onFreehandSymbolSelected = onFreehandSymbolSelected
        view.onRhythmicNotationPreviewChanged = onRhythmicNotationPreviewChanged
        view.onRhythmicNotationDiagnostic = onRhythmicNotationDiagnostic
        view.handleRhythmicNotationPreviewConfirmationRequest(rhythmicNotationPreviewConfirmationRequestID)
    }

    final class Coordinator {
        var chart: Binding<Chart>
        var selectedMeasureID: Binding<UUID?>
        var selectedNoteSelection: Binding<LeadSheetNoteSelection?>
        var selectedRoadmapMarkerID: Binding<UUID?>

        init(
            chart: Binding<Chart>,
            selectedMeasureID: Binding<UUID?>,
            selectedNoteSelection: Binding<LeadSheetNoteSelection?>,
            selectedRoadmapMarkerID: Binding<UUID?>
        ) {
            self.chart = chart
            self.selectedMeasureID = selectedMeasureID
            self.selectedNoteSelection = selectedNoteSelection
            self.selectedRoadmapMarkerID = selectedRoadmapMarkerID
        }
    }
}

enum LeadSheetPassiveInkPersistencePolicy {
    static let defaultIdleDelay: TimeInterval = 0.95
    static let freehandSymbolIdleDelay: TimeInterval = 0.38

    static func idleDelay(for activeInkScope: LeadSheetActiveInkScope?) -> TimeInterval {
        if case .freehandSymbols = activeInkScope {
            return freehandSymbolIdleDelay
        }

        return defaultIdleDelay
    }
}

enum LeadSheetInkResponsivenessPolicy {
    static let storageKey = "iChartInkResponsivenessValue"
    static let defaultValue = 0.5
    static let minimumValue = 0.0
    static let maximumValue = 1.0
    static let step = 0.05

    static func normalized(_ value: Double) -> Double {
        min(max(value, minimumValue), maximumValue)
    }

    static func inputCoalescingDelay(for value: Double) -> TimeInterval {
        let normalizedValue = normalized(value)
        return 0.004 + (normalizedValue * 0.026)
    }
}

struct LeadSheetInkDrawingSnapshot: Equatable {
    private struct StrokeSignature: Equatable {
        var pointCount: Int
        var bounds: CGRect
        var pathLength: CGFloat
        var startPoint: CGPoint
        var endPoint: CGPoint
    }

    private var strokeSignatures: [StrokeSignature]

    init?(drawing: PKDrawing) {
        let signatures = drawing.strokes.compactMap { stroke -> StrokeSignature? in
            let points = Array(stroke.path).map(\.location)
            guard !points.isEmpty else {
                return nil
            }

            let bounds = points.reduce(into: CGRect.null) { partialResult, point in
                partialResult = partialResult.union(CGRect(origin: point, size: .zero))
            }
            let pathLength = points.count < 2
                ? CGFloat.zero
                : zip(points, points.dropFirst()).reduce(CGFloat.zero) { partialResult, segment in
                    partialResult + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
                }

            return StrokeSignature(
                pointCount: points.count,
                bounds: Self.rounded(bounds),
                pathLength: Self.rounded(pathLength),
                startPoint: Self.rounded(points.first ?? .zero),
                endPoint: Self.rounded(points.last ?? .zero)
            )
        }

        guard !signatures.isEmpty else {
            return nil
        }

        strokeSignatures = signatures
    }

    init(testValues: [Int]) {
        strokeSignatures = testValues.map { value in
            StrokeSignature(
                pointCount: value,
                bounds: CGRect(x: value, y: value, width: value, height: value),
                pathLength: CGFloat(value),
                startPoint: CGPoint(x: value, y: value),
                endPoint: CGPoint(x: value + 1, y: value + 1)
            )
        }
    }

    private static func rounded(_ point: CGPoint) -> CGPoint {
        CGPoint(x: rounded(point.x), y: rounded(point.y))
    }

    private static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rounded(rect.origin.x),
            y: rounded(rect.origin.y),
            width: rounded(rect.size.width),
            height: rounded(rect.size.height)
        )
    }

    private static func rounded(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

enum LeadSheetInkAuthoringSessionRole: Hashable {
    case chord
    case rhythm
    case passive

    static func resolve(
        activeInkScope: LeadSheetActiveInkScope,
        interactionMode: EditorCanvasMode
    ) -> LeadSheetInkAuthoringSessionRole? {
        guard let role = resolve(activeInkScope: activeInkScope),
              role.isEnabled(in: interactionMode) else {
            return nil
        }

        return role
    }

    static func resolve(activeInkScope: LeadSheetActiveInkScope) -> LeadSheetInkAuthoringSessionRole? {
        switch activeInkScope {
        case .chords:
            return .chord
        case .rhythmicMeasure:
            return .rhythm
        case .page, .header, .freehandSymbols:
            return .passive
        case .noteSelection:
            return nil
        }
    }

    func isEnabled(in interactionMode: EditorCanvasMode) -> Bool {
        switch self {
        case .chord:
            return interactionMode.allowsChordInkEditing
        case .rhythm:
            return interactionMode.allowsDirectRhythmicNotationInk
        case .passive:
            return interactionMode.allowsPassiveInkPersistence
        }
    }
}

struct LeadSheetInkAuthoringSessionState {
    private var dirtyRoles: Set<LeadSheetInkAuthoringSessionRole> = []

    mutating func markDirty(_ role: LeadSheetInkAuthoringSessionRole) {
        dirtyRoles.insert(role)
    }

    mutating func clear(_ role: LeadSheetInkAuthoringSessionRole) {
        dirtyRoles.remove(role)
    }

    func isDirty(_ role: LeadSheetInkAuthoringSessionRole) -> Bool {
        dirtyRoles.contains(role)
    }
}

private final class LeadSheetScopedInkCanvasView: PKCanvasView {
    var localInputFrames: [CGRect] = [] {
        didSet {
            guard oldValue != localInputFrames else {
                return
            }

            setNeedsLayout()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else {
            return false
        }
        guard !localInputFrames.isEmpty else {
            return true
        }

        return localInputFrames.contains { inputFrame in
            inputFrame.insetBy(dx: -2, dy: -2).contains(point)
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

enum LeadSheetInkAuthoringSessionPolicy {
    static func shouldPreserveActiveCanvas(
        activeInkScope: LeadSheetActiveInkScope,
        interactionMode: EditorCanvasMode,
        sessionState: LeadSheetInkAuthoringSessionState,
        currentDrawingData: Data?,
        desiredDrawingData: Data?
    ) -> Bool {
        guard currentDrawingData != desiredDrawingData,
              let role = LeadSheetInkAuthoringSessionRole.resolve(
                activeInkScope: activeInkScope,
                interactionMode: interactionMode
              ) else {
            return false
        }

        return sessionState.isDirty(role)
    }

    static func canUseScheduledSnapshot(
        currentInkSnapshot: LeadSheetInkDrawingSnapshot?,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) -> Bool {
        guard let currentInkSnapshot,
              let scheduledInkSnapshot else {
            return false
        }

        return currentInkSnapshot == scheduledInkSnapshot
    }
}

enum LeadSheetInkCanvasSyncPolicy {
    static func shouldPreserveActiveCanvas(
        activeInkScope: LeadSheetActiveInkScope,
        interactionMode: EditorCanvasMode,
        sessionState: LeadSheetInkAuthoringSessionState,
        currentDrawingData: Data?,
        desiredDrawingData: Data?
    ) -> Bool {
        LeadSheetInkAuthoringSessionPolicy.shouldPreserveActiveCanvas(
            activeInkScope: activeInkScope,
            interactionMode: interactionMode,
            sessionState: sessionState,
            currentDrawingData: currentDrawingData,
            desiredDrawingData: desiredDrawingData
        )
    }
}

enum LeadSheetRhythmicNotationAutoApplyPolicy {
    static let idleDelay: TimeInterval = 0.58
    static let tapToRenderAdvisoryDelay: TimeInterval = 0.72
    static let exactFitGraceDelay: TimeInterval = 0.70
    static let ambiguousTerminalStemGraceDelay: TimeInterval = 0.85

    static func exactFitGraceDelay(requiresExtendedStability: Bool) -> TimeInterval {
        exactFitGraceDelay + (requiresExtendedStability ? ambiguousTerminalStemGraceDelay : 0)
    }

    static func canUseScheduledSnapshot(
        currentInkSnapshot: LeadSheetInkDrawingSnapshot?,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) -> Bool {
        LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
            currentInkSnapshot: currentInkSnapshot,
            scheduledInkSnapshot: scheduledInkSnapshot
        )
    }

    static func canAttemptAutoApply(
        currentInkSnapshot: LeadSheetInkDrawingSnapshot?,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) -> Bool {
        return canUseScheduledSnapshot(
            currentInkSnapshot: currentInkSnapshot,
            scheduledInkSnapshot: scheduledInkSnapshot
        )
    }

    static func canAutoApplyProposal(
        _ proposal: RhythmicNotationMeasureProposal,
        requiresNaturalExactFitAfterErase: Bool
    ) -> Bool {
        // A live rhythm commit clears the user's ink, so meter-fit rewrites never auto-apply.
        proposal.canAutoApply
            && (!requiresNaturalExactFitAfterErase || proposal.isNaturalExactFit)
    }
}

enum LeadSheetRhythmicNotationLiveDecisionPolicy {
    enum Route: Equatable {
        case commit(values: [RhythmValue], requiresExtendedStability: Bool)
        case readyToRender(values: [RhythmValue])
        case preserveInk(showsUnreadFeedback: Bool)
    }

    static func route(
        for decision: RhythmRecognitionDecision,
        requiresNaturalExactFitAfterErase: Bool,
        allowsCommit: Bool = false
    ) -> Route {
        switch decision {
        case .commit(let proposal, _)
            where LeadSheetRhythmicNotationAutoApplyPolicy.canAutoApplyProposal(
                proposal,
                requiresNaturalExactFitAfterErase: requiresNaturalExactFitAfterErase
            ):
            guard allowsCommit else {
                return .readyToRender(values: proposal.values)
            }
            return .commit(
                values: proposal.values,
                requiresExtendedStability: proposal.requiresExtendedStability
            )
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
            && LeadSheetRhythmicNotationAutoApplyPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: currentInkSnapshot,
                scheduledInkSnapshot: scheduledInkSnapshot
            )
    }

    static func shouldCommitFromAdvisoryRoute(
        _ route: LeadSheetRhythmicNotationLiveDecisionPolicy.Route
    ) -> Bool {
        switch route {
        case .commit:
            return false
        case .readyToRender, .preserveInk:
            return false
        }
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
        case .autoApply:
            return "autoApply"
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
    var confirmationAction: ConfirmationAction
    var isCertain: Bool

    var canConfirm: Bool {
        confirmationAction == .confirmSuggestion
    }
}

enum LeadSheetRhythmicNotationFeedbackPolicy {
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
            case .ambiguousPhrase, .manualReview, .competingExactPhrases:
                return .confirmSuggestion
            case .noInk,
                 .underfilled,
                 .overflow,
                 .unsupported,
                 .nonNaturalExactFit,
                 .nonVisualFallback,
                 .uncoveredStrokes:
                return .none
            }
        }
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
                 .nonVisualFallback,
                 .uncoveredStrokes,
                 .competingExactPhrases:
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
        case .unsupported, .nonVisualFallback, .uncoveredStrokes:
            return "Unread rhythm mark"
        case .nonNaturalExactFit:
            return "Does not fit measure"
        case .ambiguousPhrase, .manualReview, .competingExactPhrases:
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
           let uncoveredFrame = unreadPrimitiveFrame(
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
            || !phrase.primitives.isEmpty
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
                    || !phrase.primitives.isEmpty
            case .overflow,
                 .unsupported,
                 .nonNaturalExactFit,
                 .ambiguousPhrase,
                 .manualReview,
                 .nonVisualFallback,
                 .uncoveredStrokes,
                 .competingExactPhrases:
                return true
            }
        }
    }

    private static func unreadPrimitiveFrame(
        phrase: RhythmPhraseHypothesis,
        strokeIndices: [Int],
        canvasFrame: CGRect,
        padding: CGFloat
    ) -> CGRect? {
        guard !strokeIndices.isEmpty else {
            return nil
        }

        let indexedPrimitives = Dictionary(
            uniqueKeysWithValues: phrase.primitives.map { primitive in
                (primitive.strokeIndex, primitive)
            }
        )
        let localBounds = strokeIndices.reduce(into: CGRect.null) { partialResult, strokeIndex in
            guard let primitive = indexedPrimitives[strokeIndex],
                  !primitive.bounds.isNull else {
                return
            }
            partialResult = partialResult.union(primitive.bounds)
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

final class LeadSheetCanvasUIKitView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    var chart: Chart = .draft(title: "Preview") {
        didSet {
            guard oldValue != chart else {
                return
            }

            if hasNewChordEvent(from: oldValue, to: chart) {
                suppressChordObjectEditingTemporarily()
            }
            if let selectedChordID,
               chart.chordEvent(id: selectedChordID) == nil {
                self.selectedChordID = nil
            }
            if let selectedRoadmapMarkerID,
               chart.roadmapObject(id: selectedRoadmapMarkerID) == nil {
                updateSelectedRoadmapMarkerID(nil)
            }
            if let selectedCueTextID,
               chart.cueText(id: selectedCueTextID) == nil {
                self.selectedCueTextID = nil
                activeCueTextMoveDrag = nil
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
    var selectedMeasureID: UUID? {
        didSet {
            guard oldValue != selectedMeasureID else {
                return
            }

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

            if oldValue.allowsAnyInkEditing && !interactionMode.allowsAnyInkEditing {
                persistActiveInkIfNeeded(activeInkScope: activeInkScope(for: oldValue))
            }

            if oldValue.allowsDirectRhythmicNotationInk && !interactionMode.allowsDirectRhythmicNotationInk {
                cancelPendingRhythmicNotationAutoApply()
                clearRhythmicNotationUnreadInkFeedback()
            }

            if oldValue.allowsNoteSelectionInk && !interactionMode.allowsNoteSelectionInk {
                clearNoteSelectionInk()
            }

            if oldValue.allowsPageInkEditing && !interactionMode.allowsPageInkEditing {
                selectedFreehandSymbolID = nil
                activeFreehandSymbolEditDrag = nil
            }

            if interactionMode != .browse {
                activeRoadmapMarkerEditDrag = nil
                activeCueTextMoveDrag = nil
            }

            if oldValue.allowsChordObjectEditing && !interactionMode.allowsChordObjectEditing {
                selectedChordID = nil
                activeChordMoveDrag = nil
                unlockParentScrollForChordMove()
            }

            updateInteractionMode()
            syncPageInkCanvas()
            setNeedsDisplay()
        }
    }
    var onMeasureSelectionChanged: ((UUID?) -> Void)?
    var onChartChanged: ((Chart) -> Void)?
    var onTimeSignatureTargetRequested: ((UUID) -> Void)?
    var onChordInkRecognitionProposal: ((UUID, ChordInkRecognitionResult, Data, Double?, ChordInkRecognitionTiming, ChordInkRecognitionFlow) -> Void)?
    var onChordInkBatchRecognitionProposal: (([ChordInkRecognitionProposalPayload], ChordInkRecognitionFlow) -> Void)?
    var onChordCorrectionRequested: ((UUID) -> Void)?
    var onChordDeleted: ((ChordEvent) -> Void)?
    var onNoteSelectionChanged: ((LeadSheetNoteSelection?) -> Void)?
    var onRoadmapMarkerSelectionChanged: ((UUID?) -> Void)?
    var onMeasureSelectedFromCanvas: ((UUID) -> Void)?
    var onChordSelectedFromCanvas: ((UUID) -> Void)?
    var onCueTextSelectedFromCanvas: ((UUID) -> Void)?
    var onCueTextEditRequested: ((UUID) -> Void)?
    var onRoadmapMarkerSelectedFromCanvas: ((UUID) -> Void)?
    var onHeaderAuthoringRequested: (() -> Void)?
    var onFreehandSymbolSelected: ((UUID) -> Void)?
    var onRhythmicNotationPreviewChanged: ((LeadSheetRhythmicNotationPreviewState?) -> Void)?
    var onRhythmicNotationDiagnostic: ((RhythmRecognitionDiagnosticEvent) -> Void)?

    private var pageLayout: LeadSheetPageLayout?
    private let pageInkCanvasView = LeadSheetScopedInkCanvasView()
    private let chordInkConfirmOverlayView = LeadSheetChordInkConfirmOverlayView()
    private let chordEditHitOverlayView = ChordEditHitOverlayView()
    private let parentScrollGestureGate = LeadSheetParentScrollGestureGate()
    private let chordInkRecognizer = ChordInkRecognizer()
    private var chordInkRecognitionOptions: ChordInkRecognitionOptions {
        #if DEBUG || targetEnvironment(simulator)
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-iChartSymbolLedgerDiagnostics")
            || processInfo.environment["ICHART_SYMBOL_LEDGER_DIAGNOSTICS"] == "1" {
            return .includingSymbolLedgerDiagnostics
        }
        #endif

        return .live
    }
    private let chordOCRCandidateProvider = ChordOCRCandidateProviderFactory.liveProvider()
    private let chordInkIdleDelay = ChordInkAutomaticRecognitionPolicy.defaultIdleDelay
    private let chordInkContinuationGraceDelay = ChordInkAutomaticRecognitionPolicy.defaultContinuationGraceDelay
    private let chordInkRecognitionQueue = DispatchQueue(
        label: "com.ichart.chord-ink-recognition",
        qos: .userInitiated
    )
    private lazy var chordInkRecognitionSession = ChordInkRecognitionSession(
        queue: chordInkRecognitionQueue,
        recognizer: chordInkRecognizer,
        ocrCandidateProvider: chordOCRCandidateProvider
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
    private lazy var chordMovePanRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleChordMovePan(_:))
    )
    private lazy var chordEditTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleChordEditTap(_:))
    )
    private lazy var chordEditDoubleTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleChordEditDoubleTap(_:))
    )
    private lazy var chordInkConfirmTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleChordInkConfirmTap(_:))
    )
    private lazy var chordInkConfirmPanRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleChordInkConfirmPan(_:))
    )
    private var isSyncingInkCanvasFromModel = false
    private var inkAuthoringSessionState = LeadSheetInkAuthoringSessionState()
    var inkResponsivenessValue: Double = LeadSheetInkResponsivenessPolicy.defaultValue
    private var pendingInkInputCoalescingWorkItem: DispatchWorkItem?
    private var pendingInkPersistWorkItem: DispatchWorkItem?
    private var pendingRhythmicNotationCommitWorkItem: DispatchWorkItem?
    private var rhythmicNotationEraseRecovery = LeadSheetRhythmicNotationEraseRecovery()
    private var chordObjectEditingSuppressedUntil: Date?
    private var lastHandledRhythmicNotationPreviewConfirmationRequestID: UUID?
    private var rhythmicNotationPreviewState: LeadSheetRhythmicNotationPreviewState? {
        didSet {
            onRhythmicNotationPreviewChanged?(rhythmicNotationPreviewState)
        }
    }
    private var chordInkRecognitionRequestState = LeadSheetChordInkRecognitionRequestState()
    private var activeMeasureResizeDrag: ActiveMeasureResizeDrag?
    private var activeChordMoveDrag: ActiveChordMoveDrag?
    private var activeCueTextMoveDrag: ActiveCueTextMoveDrag?
    private var activeRoadmapMarkerEditDrag: ActiveRoadmapMarkerEditDrag?
    private weak var chordMoveLockedParentScrollView: UIScrollView?
    private var chordMoveLockedParentScrollWasEnabled: Bool?
    private var selectedChordID: UUID?
    private var chordInkConfirmPanStartLocation: CGPoint?
    private var selectedFreehandSymbolID: UUID?
    private var activeFreehandSymbolEditDrag: ActiveFreehandSymbolEditDrag?
    private var lastEditableOverlayHitTarget: EditableOverlayHitTarget?
    private var isClearingFreehandSymbolInk = false
    private var isRestoringSelection = false
    private var isApplyingTapSelection = false
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
        updateParentScrollGestureGate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        chordInkConfirmOverlayView.frame = bounds
        chordEditHitOverlayView.frame = bounds
        invalidateLayout()
        updateParentScrollGestureGate()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let pageLayout else {
            return
        }

        let renderer = notationRenderer
        context.clear(rect)
        renderer.drawPaper(pageLayout.paperFrame, in: context)
        if restrictsParentScrollToOutsideMargins {
            drawPageScrollDragAreas(pageLayout)
        }
        renderer.drawHeader(pageLayout.header)

        if !interactionMode.allowsHeaderInkEditing,
           chart.headerInputMode == .handwritten {
            drawSavedHeaderInk()
        }

        for system in pageLayout.systems {
            drawSystem(system, using: renderer)
        }

        if !interactionMode.allowsPageInkEditing {
            drawSavedPageInk()
        }

        if !interactionMode.allowsChordInkEditing {
            drawSavedChordInk()
        }

        if interactionMode.allowsChordInkEditing {
            drawChordWritingLanes(pageLayout)
        }

        if interactionMode.allowsPageInkEditing,
           !chart.layoutStyle.profile.freehandSymbolLanes.isEmpty {
            drawFreehandSymbolLanes(pageLayout)
        }

        drawSavedFreehandSymbols()

        if interactionMode.allowsPageInkEditing,
           !chart.layoutStyle.profile.freehandSymbolLanes.isEmpty {
            drawFreehandSymbolEditOverlays(using: renderer)
        }

        if interactionMode.showsMeasureResizeHandles {
            if let rowGroupAffordance = simpleRowGroupAffordance() {
                drawSimpleRowGroupAffordance(rowGroupAffordance)
            }
            if let selectedMeasure = selectedMeasureLayout() {
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

        pageInkCanvasView.backgroundColor = .clear
        pageInkCanvasView.isOpaque = false
        pageInkCanvasView.delegate = self
        pageInkCanvasView.isScrollEnabled = false
        pageInkCanvasView.bounces = false
        pageInkCanvasView.alwaysBounceVertical = false
        pageInkCanvasView.alwaysBounceHorizontal = false
        pageInkCanvasView.drawingPolicy = .anyInput
        pageInkCanvasView.tool = PKInkingTool(.pen, color: UIColor(white: 0.06, alpha: 1), width: 2.8)
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
        chordInkConfirmPanRecognizer.delegate = self
        chordInkConfirmPanRecognizer.cancelsTouchesInView = false
        chordInkConfirmPanRecognizer.delaysTouchesBegan = false
        chordInkConfirmPanRecognizer.delaysTouchesEnded = false
        chordInkConfirmOverlayView.addGestureRecognizer(chordInkConfirmPanRecognizer)
        addSubview(chordInkConfirmOverlayView)

        chordEditHitOverlayView.backgroundColor = .clear
        chordEditHitOverlayView.isOpaque = false
        chordEditHitOverlayView.isHidden = true
        chordEditHitOverlayView.containsEditableControl = { [weak self] location in
            let hitTarget = self?.editableOverlayHitTarget(at: location)
            self?.lastEditableOverlayHitTarget = hitTarget
            return hitTarget != nil
        }
        chordEditTapRecognizer.delegate = self
        chordEditDoubleTapRecognizer.delegate = self
        chordEditDoubleTapRecognizer.numberOfTapsRequired = 2
        chordEditTapRecognizer.require(toFail: chordEditDoubleTapRecognizer)
        chordEditHitOverlayView.addGestureRecognizer(chordEditDoubleTapRecognizer)
        chordEditHitOverlayView.addGestureRecognizer(chordEditTapRecognizer)
        chordMovePanRecognizer.delegate = self
        addGestureRecognizer(chordMovePanRecognizer)
        addSubview(chordEditHitOverlayView)
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
        guard chordMoveLockedParentScrollView == nil,
              let scrollView = enclosingParentScrollView() else {
            return
        }

        chordMoveLockedParentScrollView = scrollView
        chordMoveLockedParentScrollWasEnabled = scrollView.isScrollEnabled
        scrollView.isScrollEnabled = false
    }

    private func unlockParentScrollForChordMove() {
        defer {
            chordMoveLockedParentScrollView = nil
            chordMoveLockedParentScrollWasEnabled = nil
        }

        guard let scrollView = chordMoveLockedParentScrollView,
              let wasEnabled = chordMoveLockedParentScrollWasEnabled else {
            return
        }

        scrollView.isScrollEnabled = wasEnabled
    }

    fileprivate func allowsParentScrollGestureStart(at point: CGPoint) -> Bool {
        guard restrictsParentScrollToOutsideMargins else {
            return true
        }

        if measureResizeHandleHitTarget(at: point) != nil
            || editableOverlayHitTarget(at: point) != nil {
            return false
        }

        return LeadSheetScrollMarginPolicy.allowsPageScrollStart(
            at: point,
            paperFrame: pageLayout?.paperFrame,
            restrictsToOutsideMargins: true
        )
    }

    private func invalidateLayout() {
        guard bounds.width > 0, bounds.height > 0 else {
            pageLayout = nil
            syncPageInkCanvas()
            setNeedsDisplay()
            return
        }

        pageLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: bounds.size)
        syncPageInkCanvas()
        setNeedsDisplay()
    }

    private func drawSystem(_ system: LeadSheetSystemLayout, using renderer: LeadSheetNotationRenderer) {
        if let sectionTextFrame = system.sectionTextFrame,
           let sectionText = system.sectionText {
            renderer.drawSectionText(sectionText, in: sectionTextFrame)
        }

        if let roadmapTextFrame = system.roadmapTextFrame,
           let roadmapText = system.roadmapText {
            renderer.drawRoadmapText(roadmapText, in: roadmapTextFrame)
        }

        for roadmapMarkerLayout in system.roadmapMarkerLayouts {
            renderer.drawRoadmapMarker(roadmapMarkerLayout)
            if roadmapMarkerLayout.id == selectedRoadmapMarkerID {
                drawRoadmapMarkerEditOverlay(roadmapMarkerLayout, using: renderer)
            }
        }

        for endingLayout in system.endingLayouts {
            renderer.drawEnding(endingLayout)
        }

        renderer.drawStaffLines(for: system)

        if let clefFrame = system.clefFrame {
            renderer.drawClef(in: clefFrame)
        }

        renderer.drawKeySignature(system.keySignatureLayouts)

        if let timeSignatureFrame = system.timeSignatureFrame {
            renderer.drawTimeSignature(chart.defaultMeter, in: timeSignatureFrame)
        }

        var drawnRepeatMarkerIDs = Set<String>()
        if let firstMeasure = system.measures.first {
            let leadingMarkers = LeadSheetRepeatBoundaryPolicy.leadingMarkers(atStartOf: firstMeasure)
            if leadingMarkers.isEmpty {
                renderer.drawLeadingBarline(
                    firstMeasure.leadingBarline ?? .single,
                    at: firstMeasure.frame.minX,
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
                drawMeasureSelection(measure)
            }

            let leadingMarkers = measure.repeatMarkerLayouts.filter {
                $0.edge == .leading && !drawnRepeatMarkerIDs.contains($0.id)
            }
            drawRepeatMarkers(leadingMarkers, using: renderer)
            drawnRepeatMarkerIDs.formUnion(LeadSheetRepeatBoundaryPolicy.markerIDs(leadingMarkers))

            for chordLayout in measure.chordLayouts {
                renderer.drawChord(chordLayout)
                if interactionMode.allowsChordObjectEditing,
                   measure.sourceMeasureID != nil,
                   shouldDrawChordEditOverlay(for: chordLayout) {
                    drawChordEditOverlay(for: chordLayout, using: renderer)
                }
            }

            for (noteIndex, noteLayout) in measure.noteLayouts.enumerated() {
                if isSelectedNote(noteIndex: noteIndex, in: measure) {
                    drawNoteSelection(noteLayout)
                }
                renderer.drawNote(noteLayout)
            }

            for cueTextLayout in measure.cueTextLayouts {
                if cueTextLayout.id == selectedCueTextID {
                    drawCueTextSelection(cueTextLayout)
                }
                renderer.drawCueText(cueTextLayout)
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
                let repeatBoundaryMarkers = LeadSheetRepeatBoundaryPolicy
                    .repeatMarkers(after: measure, before: nextMeasure)
                    .filter { !drawnRepeatMarkerIDs.contains($0.id) }

                if !repeatBoundaryMarkers.isEmpty {
                    drawRepeatMarkers(repeatBoundaryMarkers, using: renderer)
                    drawnRepeatMarkerIDs.formUnion(LeadSheetRepeatBoundaryPolicy.markerIDs(repeatBoundaryMarkers))
                } else if LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(
                    after: measure,
                    before: nextMeasure
                ) {
                    renderer.drawBarline(measure.barlineAfter, in: measure.trailingBarlineFrame)
                }
            }
        }
    }

    private func drawRepeatMarkers(
        _ repeatMarkers: [LeadSheetRepeatMarkerLayout],
        using renderer: LeadSheetNotationRenderer
    ) {
        guard !repeatMarkers.isEmpty else {
            return
        }

        renderer.drawRepeatBoundary(repeatMarkers)
    }

    private func drawMeasureSelection(_ measure: LeadSheetMeasureLayout) {
        let selectionRect = measure.frame.insetBy(dx: 2, dy: 10)
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

        LeadSheetSavedInkRenderer.drawPageInk(chart.pageHandwrittenNotationData, in: pageLayout)
    }

    private func drawSavedHeaderInk() {
        guard let pageLayout else {
            return
        }

        LeadSheetSavedInkRenderer.drawHeaderInk(chart.pageHandwrittenHeaderData, in: pageLayout)
    }

    private func drawSavedChordInk() {
        guard let pageLayout else {
            return
        }

        LeadSheetSavedInkRenderer.drawChordInk(chart.pageHandwrittenChordData, in: pageLayout)
    }

    private func drawSavedFreehandSymbols() {
        guard let pageLayout else {
            return
        }

        LeadSheetSavedInkRenderer.drawFreehandSymbols(pageLayout.freehandSymbolLayouts(for: chart))
    }

    private func drawChordWritingLanes(_ pageLayout: LeadSheetPageLayout) {
        for laneFrame in LeadSheetActiveInkScope.chordWritingInputFrames(for: pageLayout) {
            let lanePath = UIBezierPath(roundedRect: laneFrame, cornerRadius: 7)
            UIColor(red: 0.18, green: 0.36, blue: 0.78, alpha: 0.06).setFill()
            lanePath.fill()
            UIColor(red: 0.18, green: 0.36, blue: 0.78, alpha: 0.18).setStroke()
            lanePath.lineWidth = 1
            lanePath.setLineDash([5, 4], count: 2, phase: 0)
            lanePath.stroke()
        }
    }

    private func drawFreehandSymbolLanes(_ pageLayout: LeadSheetPageLayout) {
        for system in pageLayout.systems {
            for measure in system.measures {
                for laneFrame in [measure.freehandAboveFrame, measure.freehandBelowFrame].compactMap({ $0 }) {
                    let lanePath = UIBezierPath(roundedRect: laneFrame.insetBy(dx: -2, dy: -2), cornerRadius: 7)
                    UIColor(red: 0.12, green: 0.46, blue: 0.42, alpha: 0.045).setFill()
                    lanePath.fill()
                    UIColor(red: 0.12, green: 0.46, blue: 0.42, alpha: 0.16).setStroke()
                    lanePath.lineWidth = 1
                    lanePath.setLineDash([5, 4], count: 2, phase: 0)
                    lanePath.stroke()
                }
            }
        }
    }

    private func drawPageScrollDragAreas(_ pageLayout: LeadSheetPageLayout) {
        let dragAreaFrames = LeadSheetScrollMarginPolicy.dragAreaFrames(
            in: bounds,
            paperFrame: pageLayout.paperFrame
        )

        for dragAreaFrame in dragAreaFrames {
            let areaPath = UIBezierPath(rect: dragAreaFrame)
            UIColor(red: 0.13, green: 0.34, blue: 0.78, alpha: 0.025).setFill()
            areaPath.fill()

            guard let railFrame = scrollDragRailFrame(
                in: dragAreaFrame,
                around: pageLayout.paperFrame
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

    private func drawFreehandSymbolEditOverlays(using renderer: LeadSheetNotationRenderer) {
        guard let selectedFreehandSymbolID,
              let symbolLayout = freehandSymbolLayouts().first(where: { $0.id == selectedFreehandSymbolID }) else {
            return
        }

        drawFreehandSymbolEditOverlay(for: symbolLayout, using: renderer)
    }

    private func drawFreehandSymbolEditOverlay(
        for symbolLayout: LeadSheetFreehandSymbolLayout,
        using renderer: LeadSheetNotationRenderer
    ) {
        let editFrame = LeadSheetFreehandSymbolEditOverlayGeometry.editFrame(for: symbolLayout)
        let controlFrames = LeadSheetFreehandSymbolEditOverlayGeometry.controlFrames(for: symbolLayout)
        let isActiveMove = activeFreehandSymbolEditDrag?.symbolID == symbolLayout.id

        let boxPath = UIBezierPath(roundedRect: editFrame, cornerRadius: 6)
        UIColor(red: 0.80, green: 0.96, blue: 0.91, alpha: isActiveMove ? 0.34 : 0.20).setFill()
        boxPath.fill()
        UIColor(red: 0.08, green: 0.48, blue: 0.42, alpha: isActiveMove ? 0.92 : 0.66).setStroke()
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

        let movePath = UIBezierPath(ovalIn: controlFrames.move)
        UIColor(red: 0.08, green: 0.48, blue: 0.42, alpha: isActiveMove ? 1 : 0.88).setFill()
        movePath.fill()
        UIColor.white.withAlphaComponent(0.95).setStroke()
        movePath.lineWidth = 1
        movePath.stroke()

        let moveGlyph = UIBezierPath()
        let glyphInset: CGFloat = 5
        moveGlyph.move(to: CGPoint(x: controlFrames.move.minX + glyphInset, y: controlFrames.move.midY))
        moveGlyph.addLine(to: CGPoint(x: controlFrames.move.maxX - glyphInset, y: controlFrames.move.midY))
        moveGlyph.move(to: CGPoint(x: controlFrames.move.midX, y: controlFrames.move.minY + glyphInset))
        moveGlyph.addLine(to: CGPoint(x: controlFrames.move.midX, y: controlFrames.move.maxY - glyphInset))
        UIColor.white.withAlphaComponent(0.96).setStroke()
        moveGlyph.lineWidth = 1.5
        moveGlyph.lineCapStyle = .round
        moveGlyph.stroke()
    }

    private func drawChordEditOverlay(
        for chordLayout: LeadSheetChordLayout,
        using renderer: LeadSheetNotationRenderer
    ) {
        let editFrame = LeadSheetChordEditOverlayGeometry.editFrame(for: chordLayout)
        let controlFrames = LeadSheetChordEditOverlayGeometry.controlFrames(for: chordLayout)
        let isActiveMove = activeChordMoveDrag?.chordID == chordLayout.id
        let drawsControls = shouldDrawChordEditControls(for: chordLayout)

        if isActiveMove {
            drawChordSnapGuide(for: chordLayout)
        }

        let boxPath = UIBezierPath(roundedRect: editFrame, cornerRadius: 5)
        UIColor(
            red: 0.88,
            green: 0.93,
            blue: 1,
            alpha: isActiveMove ? 0.30 : (drawsControls ? 0.18 : 0.08)
        ).setFill()
        boxPath.fill()
        UIColor(
            red: 0.16,
            green: 0.38,
            blue: 0.86,
            alpha: isActiveMove ? 0.92 : (drawsControls ? 0.62 : 0.40)
        ).setStroke()
        boxPath.lineWidth = isActiveMove ? 1.4 : 1
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

    }

    private func drawChordSnapGuide(for chordLayout: LeadSheetChordLayout) {
        let startPoint = CGPoint(
            x: chordLayout.frame.midX,
            y: chordLayout.frame.maxY + 1
        )
        let endPoint = chordLayout.snapGuideTarget
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
            in: measure
        )
    }

    private func selectedMeasureLayout() -> LeadSheetMeasureLayout? {
        guard let selectedMeasureID else {
            return nil
        }

        return measureLayout(for: selectedMeasureID)
    }

    private func simpleRowGroupAffordance() -> LeadSheetSimpleRowGroupAffordance? {
        LeadSheetSimpleRowGroupAffordanceGeometry.affordance(
            for: selectedMeasureID,
            in: pageLayout,
            layoutStyle: chart.layoutStyle
        )
    }

    private func measureLayout(for measureID: UUID) -> LeadSheetMeasureLayout? {
        pageLayout?.systems
            .flatMap(\.measures)
            .first(where: { $0.sourceMeasureID == measureID })
    }

    private func measureResizeHandleHitTarget(at location: CGPoint) -> ActiveMeasureResizeDrag? {
        guard interactionMode.showsMeasureResizeHandles,
              let measure = selectedMeasureLayout() else {
            return nil
        }

        return LeadSheetMeasureResizeGeometry.hitTarget(at: location, in: measure)
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
            activeMoveChordID: activeChordMoveDrag?.chordID,
            drawsAllBoxes: interactionMode.drawsAllChordObjectEditBoxes
        )
    }

    private func shouldDrawChordEditControls(for chordLayout: LeadSheetChordLayout) -> Bool {
        LeadSheetChordObjectInteractionPolicy.shouldDrawControls(
            for: chordLayout.id,
            selectedChordID: selectedChordID,
            activeMoveChordID: activeChordMoveDrag?.chordID,
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
        case roadmap(RoadmapMarkerEditHitTarget)
        case cueText(CueTextEditHitTarget)
        case chord(ChordEditHitTarget)
        case freehand(FreehandSymbolEditHitTarget)
    }

    private func editableOverlayHitTarget(at location: CGPoint) -> EditableOverlayHitTarget? {
        if let cueTextTarget = cueTextEditHitTarget(at: location) {
            return .cueText(cueTextTarget)
        }

        if let roadmapTarget = roadmapMarkerEditHitTarget(at: location) {
            return .roadmap(roadmapTarget)
        }

        if let chordTarget = chordEditHitTarget(at: location) {
            return .chord(chordTarget)
        }

        if let freehandTarget = freehandSymbolEditHitTarget(at: location) {
            return .freehand(freehandTarget)
        }

        return nil
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
        guard interactionMode == .browse else {
            return nil
        }

        return LeadSheetCueTextEditOverlayGeometry.hitTarget(
            at: location,
            in: cueTextLayouts(),
            selectedCueTextID: selectedCueTextID
        )
    }

    private func cueTextMoveHitTarget(at location: CGPoint) -> LeadSheetCueTextLayout? {
        guard interactionMode == .browse else {
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

    private func freehandSymbolLayouts() -> [LeadSheetFreehandSymbolLayout] {
        guard let pageLayout else {
            return []
        }

        return pageLayout.freehandSymbolLayouts(for: chart)
    }

    private func freehandSymbolEditHitTarget(at location: CGPoint) -> FreehandSymbolEditHitTarget? {
        guard interactionMode.allowsFreehandObjectSelection,
              !chart.layoutStyle.profile.freehandSymbolLanes.isEmpty else {
            return nil
        }

        let symbolLayouts = freehandSymbolLayouts()
        guard interactionMode.allowsPageInkEditing else {
            for symbolLayout in symbolLayouts.reversed() {
                if LeadSheetFreehandSymbolEditOverlayGeometry.editHitFrame(for: symbolLayout).contains(location) {
                    return FreehandSymbolEditHitTarget(symbolID: symbolLayout.id, action: .select)
                }
            }

            return nil
        }

        if let selectedFreehandSymbolID,
           let selectedLayout = symbolLayouts.first(where: { $0.id == selectedFreehandSymbolID }),
           let selectedHitTarget = LeadSheetFreehandSymbolEditOverlayGeometry.hitTarget(
               at: location,
               in: [selectedLayout]
           ) {
            return selectedHitTarget
        }
        if let selectedFreehandSymbolID,
           let selectedLayout = symbolLayouts.first(where: { $0.id == selectedFreehandSymbolID }),
           LeadSheetFreehandSymbolEditOverlayGeometry.selectedDragFrame(for: selectedLayout).contains(location) {
            return FreehandSymbolEditHitTarget(symbolID: selectedFreehandSymbolID, action: .select)
        }

        for symbolLayout in symbolLayouts.reversed() where symbolLayout.id != selectedFreehandSymbolID {
            if LeadSheetFreehandSymbolEditOverlayGeometry.editHitFrame(for: symbolLayout).contains(location) {
                return FreehandSymbolEditHitTarget(symbolID: symbolLayout.id, action: .select)
            }
        }

        return nil
    }

    private func lastFreehandSymbolDragHitTarget() -> FreehandSymbolEditHitTarget? {
        guard case let .freehand(hitTarget)? = lastEditableOverlayHitTarget,
              hitTarget.action != .delete else {
            return nil
        }

        return hitTarget
    }

    private func lastRoadmapMarkerDragHitTarget() -> RoadmapMarkerEditHitTarget? {
        guard case let .roadmap(hitTarget)? = lastEditableOverlayHitTarget,
              hitTarget.action != .delete else {
            return nil
        }

        return hitTarget
    }

    private func lastCueTextDragHitTarget() -> CueTextEditHitTarget? {
        guard case let .cueText(hitTarget)? = lastEditableOverlayHitTarget,
              hitTarget.action == .select else {
            return nil
        }

        return hitTarget
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
            return
        }
        guard !isClearingFreehandSymbolInk else {
            return
        }

        updateChordInkConfirmOverlayVisibility()

        if let role = activeInkAuthoringSessionRole() {
            inkAuthoringSessionState.markDirty(role)
        }

        if interactionMode.allowsDirectRhythmicNotationInk {
            clearRhythmicNotationUnreadInkFeedback()
            recordRhythmicNotationDrawingChange()
        }

        scheduleInkSessionWorkAfterDrawingChange()
    }

    @objc
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        if interactionMode.allowsPageInkEditing,
           !chart.layoutStyle.profile.freehandSymbolLanes.isEmpty {
            handleFreehandSymbolTap(at: recognizer.location(in: self))
            return
        }

        if interactionMode.allowsChordInkEditing {
            handleChordEntryTap(at: recognizer.location(in: self))
            return
        }

        if interactionMode.allowsNoteSelection {
            handleNoteSelectionTap(at: recognizer.location(in: self))
            return
        }

        guard interactionMode.allowsMeasureSelection else {
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

        if interactionMode == .browse,
           let cueTextLayout = cueTextHitTarget(at: location),
           let cueText = chart.cueText(id: cueTextLayout.id) {
            selectCueTextFromCanvas(cueText)
            return
        }

        let tappedMeasure = LeadSheetCanvasInteractionTargeting.measure(at: location, in: pageLayout)
        let tappedMeasureID = tappedMeasure?.sourceMeasureID

        if shouldFinalizeRhythmicNotationTap(at: location, nextMeasureID: tappedMeasureID),
           let activeMeasureID = selectedMeasureID,
           !finalizeRhythmicNotationIfNeeded(for: activeMeasureID) {
            restoreSelectedMeasureID(activeMeasureID)
            return
        }

        applyTapSelection(tappedMeasureID)

        if interactionMode == .browse,
           let tappedMeasureID {
            onMeasureSelectedFromCanvas?(tappedMeasureID)
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
        selectedFreehandSymbolID = nil
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
        selectedFreehandSymbolID = nil
        selectedNoteSelection = nil
        applyTapSelection(cueText.anchorMeasureID)
        onCueTextSelectedFromCanvas?(cueText.id)
        setNeedsDisplay()
    }

    private func handleFreehandSymbolTap(at location: CGPoint) {
        guard let hitTarget = freehandSymbolEditHitTarget(at: location) else {
            selectedFreehandSymbolID = nil
            setNeedsDisplay()
            return
        }

        switch hitTarget.action {
        case .delete:
            deleteFreehandSymbol(hitTarget.symbolID)
        case .move, .select:
            selectedFreehandSymbolID = hitTarget.symbolID
            setNeedsDisplay()
        }
    }

    @objc
    private func handleChordEditTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        let location = recognizer.location(in: chordEditHitOverlayView)
        if let hitTarget = cueTextEditHitTarget(at: location) {
            handleCueTextEditTap(hitTarget)
            return
        }

        if let hitTarget = roadmapMarkerEditHitTarget(at: location) {
            handleRoadmapMarkerEditTap(hitTarget)
            return
        }

        if interactionMode.allowsPageInkEditing,
           !chart.layoutStyle.profile.freehandSymbolLanes.isEmpty {
            handleFreehandSymbolTap(at: location)
            return
        }

        if interactionMode == .browse,
           let hitTarget = freehandSymbolEditHitTarget(at: location) {
            selectedFreehandSymbolID = hitTarget.symbolID
            onFreehandSymbolSelected?(hitTarget.symbolID)
            setNeedsDisplay()
            return
        }

        guard let hitTarget = chordEditHitTarget(at: location) else {
            return
        }

        switch hitTarget.action {
        case .select:
            selectedChordID = hitTarget.chordID
            if interactionMode == .browse {
                onChordSelectedFromCanvas?(hitTarget.chordID)
            }
            setNeedsDisplay()
        case .delete:
            deleteChordEvent(hitTarget.chordID)
        case .move:
            break
        case .review:
            selectedChordID = hitTarget.chordID
            if interactionMode == .browse {
                onChordSelectedFromCanvas?(hitTarget.chordID)
            }
            setNeedsDisplay()
        }
    }

    private func handleCueTextEditTap(_ hitTarget: CueTextEditHitTarget) {
        switch hitTarget.action {
        case .select:
            guard let cueText = chart.cueText(id: hitTarget.cueTextID) else {
                return
            }

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
    private func handleChordEditDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        let location = recognizer.location(in: chordEditHitOverlayView)
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

        if let hitTarget = chordEditHitTarget(at: location) {
            switch hitTarget.action {
            case .select:
                selectedChordID = hitTarget.chordID
                setNeedsDisplay()
            case .delete:
                deleteChordEvent(hitTarget.chordID)
            case .move:
                break
            case .review:
                selectedChordID = hitTarget.chordID
                setNeedsDisplay()
            }
            return
        }

        if LeadSheetCanvasInteractionTargeting.chordWritingBandContains(location, in: pageLayout),
           !shouldConfirmChordInkTap(at: location) {
            return
        }

        confirmChordInkFromUserTapIfNeeded()
    }

    @objc
    private func handleChordInkConfirmTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              chordInkConfirmSurfaceContains(recognizer.location(in: self)) else {
            return
        }

        confirmChordInkFromUserTapIfNeeded()
    }

    @objc
    private func handleChordInkConfirmPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            chordInkConfirmPanStartLocation = recognizer.location(in: self)
        case .ended:
            defer {
                chordInkConfirmPanStartLocation = nil
            }

            guard let startLocation = chordInkConfirmPanStartLocation,
                  ChordInkTapConfirmGesturePolicy.shouldConfirmOutsideLaneGesture(
                    startLocation: startLocation,
                    currentLocation: recognizer.location(in: self),
                    pageLayout: pageLayout,
                    hasChordInk: currentCanvasDrawingData() != nil
                  ) else {
                return
            }

            confirmChordInkFromUserTapIfNeeded()
        case .cancelled, .failed:
            chordInkConfirmPanStartLocation = nil
        default:
            break
        }
    }

    private func chordInkConfirmSurfaceContains(_ location: CGPoint) -> Bool {
        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              ChordInkTapConfirmGesturePolicy.shouldConfirmOutsideLaneTap(
                location: location,
                pageLayout: pageLayout,
                hasChordInk: currentCanvasDrawingData() != nil
              ),
              editableOverlayHitTarget(at: location) == nil else {
            return false
        }

        return bounds.contains(location)
    }

    private func shouldConfirmChordInkTap(at location: CGPoint) -> Bool {
        guard currentCanvasDrawingData() != nil,
              let inkBounds = currentChordInkBoundsInView() else {
            return false
        }

        return !inkBounds.insetBy(dx: -18, dy: -18).contains(location)
    }

    private func currentChordInkBoundsInView() -> CGRect? {
        guard let activeInkScope = activeInkScope(),
              case .chords(let chordFrame, _) = activeInkScope else {
            return nil
        }

        let inkBounds = LeadSheetChordInkImageRenderer.renderBounds(for: pageInkCanvasView.drawing)
        guard !inkBounds.isNull else {
            return nil
        }

        return inkBounds.offsetBy(dx: chordFrame.minX, dy: chordFrame.minY)
    }

    private func confirmChordInkFromUserTapIfNeeded() {
        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              currentCanvasDrawingData() != nil else {
            return
        }

        chordInkRecognitionRequestState.continuationGraceDrawingData = nil
        scheduleChordInkRecognition(
            after: 0,
            scheduledInkSnapshot: currentCanvasInkSnapshot(),
            flow: .tapToConfirm
        )
    }

    private func deleteChordEvent(_ chordID: UUID) {
        guard let deletedChord = chart.chordEvent(id: chordID) else {
            return
        }

        var updatedChart = chart
        guard updatedChart.deleteChordEvent(chordID) else {
            return
        }

        chart = updatedChart
        selectedChordID = nil
        onChartChanged?(updatedChart)
        onChordDeleted?(deletedChord)
        setNeedsDisplay()
    }

    private func deleteFreehandSymbol(_ symbolID: UUID) {
        var updatedChart = chart
        guard updatedChart.deleteFreehandSymbol(symbolID) else {
            return
        }

        if selectedFreehandSymbolID == symbolID {
            selectedFreehandSymbolID = nil
        }
        if activeFreehandSymbolEditDrag?.symbolID == symbolID {
            activeFreehandSymbolEditDrag = nil
        }
        chart = updatedChart
        onChartChanged?(updatedChart)
        setNeedsDisplay()
    }

    private func resizeCueText(_ cueTextID: UUID, by scaleDelta: Double) {
        var updatedChart = chart
        guard updatedChart.resizeCueText(cueTextID, byScaleDelta: scaleDelta) else {
            return
        }

        chart = updatedChart
        selectedCueTextID = cueTextID
        onChartChanged?(updatedChart)
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
        chart = updatedChart
        onChartChanged?(updatedChart)
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

        chart = updatedChart
        onChartChanged?(updatedChart)
        setNeedsDisplay()
    }

    private func moveFreehandSymbol(
        _ symbolID: UUID,
        to pageFrame: CGRect,
        referenceFrame: CGRect,
        in updatedChart: inout Chart
    ) -> Bool {
        guard let symbol = updatedChart.freehandSymbol(id: symbolID) else {
            return false
        }

        if symbol.lane == .chartArea {
            guard let pageLayout,
                  let anchor = freehandSymbolAnchorTarget(for: pageFrame, in: pageLayout) else {
                return false
            }

            return updatedChart.moveFreehandSymbol(
                symbolID,
                to: FreehandSymbolMeasureFrame(frame: pageFrame, relativeTo: anchor.measureFrame),
                anchorMeasureID: anchor.measureID
            )
        }

        return updatedChart.moveFreehandSymbol(
            symbolID,
            to: FreehandSymbolNormalizedFrame(frame: pageFrame, in: referenceFrame)
        )
    }

    private func handleNoteSelectionTap(at location: CGPoint) {
        guard let pageLayout,
              pageLayout.paperFrame.contains(location) else {
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
        case .changed:
            guard let activeMeasureResizeDrag else {
                return
            }

            let translation = recognizer.translation(in: self)
            let signedDelta = activeMeasureResizeDrag.edge == .right
                ? translation.x
                : -translation.x
            let proposedWidth = activeMeasureResizeDrag.initialWidth + signedDelta

            var updatedChart = chart
            let appliedWidth = updatedChart.setMeasureManualLayoutWidth(
                proposedWidth,
                for: activeMeasureResizeDrag.measureID
            )
            guard appliedWidth != nil else {
                return
            }

            chart = updatedChart
            onChartChanged?(updatedChart)
        case .ended, .cancelled, .failed:
            activeMeasureResizeDrag = nil
        default:
            break
        }
    }

    @objc
    private func handleChordMovePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        if activeCueTextMoveDrag != nil
            || (recognizer.state == .began
                && (cueTextMoveHitTarget(at: panStartLocation(for: recognizer)) != nil
                    || lastCueTextDragHitTarget() != nil)) {
            handleCueTextMovePan(recognizer)
            return
        }

        if activeRoadmapMarkerEditDrag != nil
            || (recognizer.state == .began
                && (roadmapMarkerMoveHitTarget(at: panStartLocation(for: recognizer)) != nil
                    || lastRoadmapMarkerDragHitTarget() != nil)) {
            handleRoadmapMarkerEditPan(recognizer)
            return
        }

        if interactionMode.allowsPageInkEditing,
           !chart.layoutStyle.profile.freehandSymbolLanes.isEmpty {
            handleFreehandSymbolEditPan(recognizer)
            return
        }

        switch recognizer.state {
        case .began:
            guard let hitTarget = chordMoveHitTarget(at: location) else {
                activeChordMoveDrag = nil
                setNeedsDisplay()
                return
            }

            selectedChordID = hitTarget.chordID
            activeChordMoveDrag = ActiveChordMoveDrag(chordID: hitTarget.chordID)
            lockParentScrollForChordMove()
            setNeedsDisplay()
        case .changed, .ended:
            guard let activeChordMoveDrag,
                  let target = LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                    at: recognizer.location(in: self),
                    in: pageLayout
                  ) else {
                if recognizer.state == .ended {
                    self.activeChordMoveDrag = nil
                    unlockParentScrollForChordMove()
                    setNeedsDisplay()
                }
                return
            }

            var updatedChart = chart
            guard updatedChart.moveChordEvent(
                activeChordMoveDrag.chordID,
                to: target.measureID,
                atFraction: target.fraction
            ) else {
                return
            }

            chart = updatedChart
            onChartChanged?(updatedChart)
            setNeedsDisplay()

            if recognizer.state == .ended {
                self.activeChordMoveDrag = nil
                unlockParentScrollForChordMove()
            }
        case .cancelled, .failed:
            activeChordMoveDrag = nil
            unlockParentScrollForChordMove()
            setNeedsDisplay()
        default:
            break
        }
    }

    private func handleCueTextMovePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let startLocation = panStartLocation(for: recognizer)
            let resolvedCueTextLayout = cueTextMoveHitTarget(at: startLocation)
                ?? lastCueTextDragHitTarget().flatMap { hitTarget in
                    cueTextLayouts().first { $0.id == hitTarget.cueTextID }
                }
            guard let cueTextLayout = resolvedCueTextLayout,
                  let cueText = chart.cueText(id: cueTextLayout.id) else {
                activeCueTextMoveDrag = nil
                setNeedsDisplay()
                return
            }

            selectCueTextFromCanvas(cueText)
            activeCueTextMoveDrag = ActiveCueTextMoveDrag(cueTextID: cueTextLayout.id)
            lockParentScrollForChordMove()
            setNeedsDisplay()

        case .changed, .ended:
            guard let activeCueTextMoveDrag else {
                if recognizer.state == .ended {
                    unlockParentScrollForChordMove()
                }
                return
            }

            guard let target = LeadSheetCanvasInteractionTargeting.cueTextMoveTarget(
                at: recognizer.location(in: self),
                in: pageLayout,
                chart: chart
            ) else {
                if recognizer.state == .ended {
                    self.activeCueTextMoveDrag = nil
                    lastEditableOverlayHitTarget = nil
                    unlockParentScrollForChordMove()
                    setNeedsDisplay()
                }
                return
            }

            var updatedChart = chart
            if updatedChart.moveCueText(
                activeCueTextMoveDrag.cueTextID,
                to: target.measureID,
                atFraction: target.fraction
            ) {
                chart = updatedChart
                selectedCueTextID = activeCueTextMoveDrag.cueTextID
                selectedMeasureID = target.measureID
                onChartChanged?(updatedChart)
                setNeedsDisplay()
            }

            if recognizer.state == .ended {
                self.activeCueTextMoveDrag = nil
                lastEditableOverlayHitTarget = nil
                unlockParentScrollForChordMove()
                setNeedsDisplay()
            }

        case .cancelled, .failed:
            activeCueTextMoveDrag = nil
            lastEditableOverlayHitTarget = nil
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
            let resolvedMarkerLayout = roadmapMarkerMoveHitTarget(at: startLocation)
                ?? lastRoadmapMarkerDragHitTarget().flatMap { hitTarget in
                    roadmapMarkerLayouts().first { $0.id == hitTarget.markerID }
                }
            guard let markerLayout = resolvedMarkerLayout else {
                activeRoadmapMarkerEditDrag = nil
                setNeedsDisplay()
                return
            }

            selectRoadmapMarkerFromCanvas(markerLayout)
            activeRoadmapMarkerEditDrag = ActiveRoadmapMarkerEditDrag(
                markerID: markerLayout.id,
                initialFrame: markerLayout.frame,
                movementFrame: markerLayout.movementFrame
            )
            lockParentScrollForChordMove()
            setNeedsDisplay()

        case .changed, .ended:
            guard let activeRoadmapMarkerEditDrag else {
                if recognizer.state == .ended {
                    unlockParentScrollForChordMove()
                }
                return
            }

            let translation = recognizer.translation(in: self)
            let proposedFrame = activeRoadmapMarkerEditDrag.initialFrame.offsetBy(
                dx: translation.x,
                dy: 0
            )
            let clampedFrame = LeadSheetRoadmapMarkerEditOverlayGeometry.clampedFrame(
                proposedFrame,
                in: activeRoadmapMarkerEditDrag.movementFrame
            )
            let normalizedOffset = LeadSheetRoadmapMarkerEditOverlayGeometry.normalizedOffset(
                for: clampedFrame,
                in: activeRoadmapMarkerEditDrag.movementFrame
            )

            var updatedChart = chart
            if updatedChart.movePointRoadmapMarkerHorizontally(
                activeRoadmapMarkerEditDrag.markerID,
                toNormalizedOffset: normalizedOffset
            ) {
                chart = updatedChart
                onChartChanged?(updatedChart)
                setNeedsDisplay()
            }

            if recognizer.state == .ended {
                self.activeRoadmapMarkerEditDrag = nil
                lastEditableOverlayHitTarget = nil
                unlockParentScrollForChordMove()
                setNeedsDisplay()
            }

        case .cancelled, .failed:
            activeRoadmapMarkerEditDrag = nil
            lastEditableOverlayHitTarget = nil
            unlockParentScrollForChordMove()
            setNeedsDisplay()

        default:
            break
        }
    }

    private func handleFreehandSymbolEditPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: self)
            let translation = recognizer.translation(in: self)
            let startLocation = CGPoint(
                x: location.x - translation.x,
                y: location.y - translation.y
            )
            let resolvedHitTarget = freehandSymbolEditHitTarget(at: startLocation)
                ?? lastFreehandSymbolDragHitTarget()
            guard let hitTarget = resolvedHitTarget,
                  hitTarget.action != .delete,
                  let symbolLayout = freehandSymbolLayouts().first(where: { $0.id == hitTarget.symbolID }) else {
                activeFreehandSymbolEditDrag = nil
                setNeedsDisplay()
                return
            }

            selectedFreehandSymbolID = hitTarget.symbolID
            activeFreehandSymbolEditDrag = ActiveFreehandSymbolEditDrag(
                symbolID: hitTarget.symbolID,
                initialFrame: symbolLayout.frame,
                laneFrame: symbolLayout.laneFrame
            )
            setNeedsDisplay()
        case .changed, .ended:
            guard let activeFreehandSymbolEditDrag else {
                return
            }

            let translation = recognizer.translation(in: self)
            let proposedFrame = activeFreehandSymbolEditDrag.initialFrame.offsetBy(
                dx: translation.x,
                dy: translation.y
            )
            let clampedFrame = LeadSheetFreehandSymbolEditOverlayGeometry.clampedFrame(
                proposedFrame,
                in: activeFreehandSymbolEditDrag.laneFrame
            )

            var updatedChart = chart
            if moveFreehandSymbol(
                activeFreehandSymbolEditDrag.symbolID,
                to: clampedFrame,
                referenceFrame: activeFreehandSymbolEditDrag.laneFrame,
                in: &updatedChart
            ) {
                chart = updatedChart
                onChartChanged?(updatedChart)
                setNeedsDisplay()
            }

            if recognizer.state == .ended {
                self.activeFreehandSymbolEditDrag = nil
                lastEditableOverlayHitTarget = nil
            }
        case .cancelled, .failed:
            activeFreehandSymbolEditDrag = nil
            lastEditableOverlayHitTarget = nil
            setNeedsDisplay()
        default:
            break
        }
    }

    private func syncPageInkCanvas() {
        guard let activeInkScope = activeInkScope() else {
            if !interactionMode.allowsAnyInkEditing {
                pageInkCanvasView.isHidden = true
                pageInkCanvasView.isUserInteractionEnabled = false
                pageInkCanvasView.localInputFrames = []
                updateChordInkConfirmOverlayVisibility()
                return
            }

            persistActiveInkIfNeeded()
            pageInkCanvasView.isHidden = true
            pageInkCanvasView.localInputFrames = []
            updateChordInkConfirmOverlayVisibility()
            return
        }

        pageInkCanvasView.isHidden = false
        pageInkCanvasView.isUserInteractionEnabled = true
        pageInkCanvasView.frame = activeInkScope.frame
        pageInkCanvasView.contentSize = activeInkScope.frame.size
        pageInkCanvasView.localInputFrames = activeInkScope.localInputFrames
        updateChordInkConfirmOverlayVisibility()

        let desiredData = activeInkScope.drawingData(in: chart)
        let currentData = currentCanvasDrawingData()
        if LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
            activeInkScope: activeInkScope,
            interactionMode: interactionMode,
            sessionState: inkAuthoringSessionState,
            currentDrawingData: currentData,
            desiredDrawingData: desiredData
        ) {
            pageInkCanvasView.becomeFirstResponder()
            return
        }

        guard currentData != desiredData else {
            return
        }

        isSyncingInkCanvasFromModel = true
        if let desiredData,
           let drawing = try? PKDrawing(data: desiredData) {
            pageInkCanvasView.drawing = drawing
        } else {
            pageInkCanvasView.drawing = PKDrawing()
        }
        isSyncingInkCanvasFromModel = false
        updateChordInkConfirmOverlayVisibility()
        pageInkCanvasView.becomeFirstResponder()
    }

    private func updateChordInkConfirmOverlayVisibility() {
        let isConfirmSurfaceAvailable = interactionMode.allowsChordInkEditing
            && recognizesChordInk
            && currentCanvasDrawingData() != nil
        chordInkConfirmOverlayView.isHidden = !isConfirmSurfaceAvailable
        chordInkConfirmOverlayView.isUserInteractionEnabled = isConfirmSurfaceAvailable
    }

    private func schedulePersistActiveInk() {
        switch activeInkAuthoringSessionRole() {
        case .chord:
            if recognizesChordInk {
                scheduleChordInkRecognition()
            } else {
                schedulePassiveChordInkPersistence()
            }
            return

        case .rhythm:
            guard let selectedMeasureID else {
                return
            }
            pendingInkPersistWorkItem?.cancel()
            pendingRhythmicNotationCommitWorkItem?.cancel()
            pendingRhythmicNotationCommitWorkItem = nil
            let scheduledInkSnapshot = currentCanvasInkSnapshot()
            let workItem = DispatchWorkItem { [weak self] in
                if RhythmRecognitionOverhaulGate.isTapToRenderRecognitionEnabled {
                    self?.prepareRhythmicNotationTapToRenderIfStable(
                        for: selectedMeasureID,
                        scheduledInkSnapshot: scheduledInkSnapshot
                    )
                } else if RhythmRecognitionOverhaulGate.isLegacyAutoRenderParked {
                    self?.persistRhythmicNotationInkIfStable(
                        for: selectedMeasureID,
                        scheduledInkSnapshot: scheduledInkSnapshot
                    )
                } else {
                    self?.autoApplyRhythmicNotationIfReady(
                        for: selectedMeasureID,
                        scheduledInkSnapshot: scheduledInkSnapshot
                    )
                }
            }
            pendingInkPersistWorkItem = workItem
            let recognitionDelay = RhythmRecognitionOverhaulGate.isTapToRenderRecognitionEnabled
                ? LeadSheetRhythmicNotationAutoApplyPolicy.tapToRenderAdvisoryDelay
                : LeadSheetRhythmicNotationAutoApplyPolicy.idleDelay
            DispatchQueue.main.asyncAfter(
                deadline: .now() + recognitionDelay,
                execute: workItem
            )
            return

        case .passive:
            pendingInkPersistWorkItem?.cancel()
            pendingRhythmicNotationCommitWorkItem?.cancel()
            pendingRhythmicNotationCommitWorkItem = nil
            let activeInkScope = activeInkScope()
            let scheduledInkSnapshot = currentCanvasInkSnapshot()
            let workItem = DispatchWorkItem { [weak self] in
                self?.persistPassiveInkIfStable(scheduledInkSnapshot: scheduledInkSnapshot)
            }
            pendingInkPersistWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + LeadSheetPassiveInkPersistencePolicy.idleDelay(for: activeInkScope),
                execute: workItem
            )
            return

        case nil:
            break
        }

        pendingInkPersistWorkItem?.cancel()
        pendingRhythmicNotationCommitWorkItem?.cancel()
        pendingRhythmicNotationCommitWorkItem = nil
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistActiveInkIfNeeded()
        }
        pendingInkPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func schedulePassiveChordInkPersistence() {
        chordInkRecognitionRequestState.cancelPendingRequest()
        pendingInkPersistWorkItem?.cancel()
        pendingRhythmicNotationCommitWorkItem?.cancel()
        pendingRhythmicNotationCommitWorkItem = nil
        let scheduledInkSnapshot = currentCanvasInkSnapshot()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistPassiveInkIfStable(scheduledInkSnapshot: scheduledInkSnapshot)
        }
        pendingInkPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LeadSheetPassiveInkPersistencePolicy.defaultIdleDelay,
            execute: workItem
        )
    }

    private func scheduleInkSessionWorkAfterDrawingChange() {
        pendingInkInputCoalescingWorkItem?.cancel()
        cancelPendingInkSessionScheduledWork()
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingInkInputCoalescingWorkItem = nil
            self?.schedulePersistActiveInk()
        }
        pendingInkInputCoalescingWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(for: inkResponsivenessValue),
            execute: workItem
        )
    }

    private func cancelPendingInkSessionScheduledWork() {
        pendingInkPersistWorkItem?.cancel()
        pendingInkPersistWorkItem = nil
        pendingRhythmicNotationCommitWorkItem?.cancel()
        pendingRhythmicNotationCommitWorkItem = nil
        chordInkRecognitionRequestState.cancelPendingRequest()
    }

    private func persistPassiveInkIfStable(scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?) {
        guard LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
            currentInkSnapshot: currentCanvasInkSnapshot(),
            scheduledInkSnapshot: scheduledInkSnapshot
        ) else {
            return
        }

        persistActiveInkIfNeeded()
    }

    private func scheduleChordInkRecognition() {
        scheduleChordInkRecognition(
            after: ChordInkAutomaticRecognitionPolicy.idleDelay(
                for: pageInkCanvasView.drawing,
                defaultDelay: chordInkIdleDelay
            ),
            scheduledInkSnapshot: currentCanvasInkSnapshot(),
            flow: .automaticPreview
        )
    }

    private func scheduleChordInkRecognition(
        after requestedDelay: TimeInterval,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?,
        flow: ChordInkRecognitionFlow
    ) {
        pendingInkPersistWorkItem?.cancel()
        pendingInkPersistWorkItem = nil

        let requestID = UUID()
        let scheduledAt = Date()
        let workItem = DispatchWorkItem { [weak self] in
            self?.recognizeChordInkIfNeeded(
                requestID: requestID,
                scheduledAt: scheduledAt,
                requestedDelay: requestedDelay,
                scheduledInkSnapshot: scheduledInkSnapshot,
                flow: flow
            )
        }
        chordInkRecognitionRequestState.schedule(requestID: requestID, workItem: workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + requestedDelay, execute: workItem)
    }

    private func persistActiveInkIfNeeded(
        cancelPendingRecognition: Bool = true,
        activeInkScope explicitActiveInkScope: LeadSheetActiveInkScope? = nil
    ) {
        pendingInkInputCoalescingWorkItem?.cancel()
        pendingInkInputCoalescingWorkItem = nil

        if cancelPendingRecognition {
            pendingInkPersistWorkItem?.cancel()
            pendingInkPersistWorkItem = nil
            chordInkRecognitionRequestState.cancelPendingRequest()
        }

        guard let activeInkScope = explicitActiveInkScope ?? activeInkScope() else {
            return
        }

        let activeInkRole = LeadSheetInkAuthoringSessionRole.resolve(activeInkScope: activeInkScope)

        if case .freehandSymbols(let frame) = activeInkScope {
            persistFreehandSymbolInkIfNeeded(canvasFrame: frame)
            clearDirtyInkAuthoringRole(activeInkRole)
            return
        }

        let drawingData = currentCanvasDrawingData()
        guard let updatedChart = activeInkScope.chartByPersistingDrawingData(drawingData, in: chart) else {
            clearDirtyInkAuthoringRole(activeInkRole)
            return
        }

        chart = updatedChart
        onChartChanged?(updatedChart)
        clearDirtyInkAuthoringRole(activeInkRole)
    }

    private func recognizeChordInkIfNeeded(
        requestID: UUID,
        scheduledAt: Date,
        requestedDelay: TimeInterval,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?,
        flow: ChordInkRecognitionFlow
    ) {
        chordInkRecognitionRequestState.markPendingWorkStarted()

        guard chordInkRecognitionRequestState.isActive(requestID) else {
            return
        }

        guard LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
            currentInkSnapshot: currentCanvasInkSnapshot(),
            scheduledInkSnapshot: scheduledInkSnapshot
        ) else {
            chordInkRecognitionRequestState.clearActiveRequest()
            return
        }

        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              let activeInkScope = activeInkScope(),
              case .chords(let chordFrame, _) = activeInkScope else {
            chordInkRecognitionRequestState.clearActiveRequest()
            return
        }

        guard let drawingData = currentCanvasDrawingData() else {
            if inkAuthoringSessionState.isDirty(.chord) {
                persistActiveInkIfNeeded(cancelPendingRecognition: false)
            }
            chordInkRecognitionRequestState.clearActiveRequest()
            return
        }

        guard flow == .tapToConfirm
                || drawingData != chordInkRecognitionRequestState.lastRecognizedDrawingData else {
            chordInkRecognitionRequestState.clearActiveRequest()
            return
        }

        persistActiveInkIfNeeded(cancelPendingRecognition: false)

        if flow == .tapToConfirm {
            let batchTargets = LeadSheetChordInkRecognitionTargeting.batchTargets(
                for: pageInkCanvasView.drawing,
                chordFrame: chordFrame,
                pageLayout: pageLayout
            )
            if batchTargets.count > 1 {
                let sessionRequests = batchTargets.map { batchTarget in
                    let drawingForOCR = batchTarget.drawing
                    return ChordInkRecognitionSessionRequest(
                        requestID: requestID,
                        scheduledAt: scheduledAt,
                        requestedDelay: requestedDelay,
                        strokes: batchTarget.strokes,
                        drawingData: batchTarget.drawingData,
                        target: (batchTarget.measureID, batchTarget.fraction),
                        options: chordInkRecognitionOptions,
                        ocrImageProvider: {
                            LeadSheetChordInkImageRenderer.ocrImage(for: drawingForOCR)
                        }
                    )
                }

                chordInkRecognitionSession.startBatch(requests: sessionRequests) { [weak self] payloads in
                    self?.finishChordInkBatchRecognition(payloads, flow: flow)
                }
                return
            }
        }

        guard let target = LeadSheetChordInkRecognitionTargeting.target(
            for: pageInkCanvasView.drawing,
            chordFrame: chordFrame,
            pageLayout: pageLayout
        ) else {
            chordInkRecognitionRequestState.clearActiveRequest()
            return
        }
        let strokes = PencilKitInkAdapter.inkStrokes(from: pageInkCanvasView.drawing)
        let drawingForOCR = pageInkCanvasView.drawing

        let sessionRequest = ChordInkRecognitionSessionRequest(
            requestID: requestID,
            scheduledAt: scheduledAt,
            requestedDelay: requestedDelay,
            strokes: strokes,
            drawingData: drawingData,
            target: target,
            options: chordInkRecognitionOptions,
            ocrImageProvider: { [weak self, drawingForOCR] in
                guard self != nil else {
                    return nil
                }

                return LeadSheetChordInkImageRenderer.ocrImage(for: drawingForOCR)
            }
        )
        chordInkRecognitionSession.start(request: sessionRequest) { [weak self] payload in
            self?.finishChordInkRecognition(payload, flow: flow)
        }
    }

    private func finishChordInkRecognition(
        _ payload: ChordInkRecognitionProposalPayload,
        flow: ChordInkRecognitionFlow
    ) {
        guard chordInkRecognitionRequestState.finishActiveRequest(payload.requestID) else {
            return
        }

        LeadSheetChordInkRecognitionTimingLogger.log(payload.timing, result: payload.result)

        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              !payload.result.rawCandidates.isEmpty else {
            return
        }

        if shouldGiveChordInkContinuationGrace(
            flow: flow,
            result: payload.result,
            drawingData: payload.drawingData,
            timing: payload.timing
        ) {
            chordInkRecognitionRequestState.continuationGraceDrawingData = payload.drawingData
            scheduleChordInkRecognition(
                after: ChordInkAutomaticRecognitionPolicy.continuationGraceDelay(
                    for: payload.result,
                    defaultDelay: chordInkContinuationGraceDelay
                ),
                scheduledInkSnapshot: currentCanvasInkSnapshot(),
                flow: .automaticPreview
            )
            return
        }

        chordInkRecognitionRequestState.continuationGraceDrawingData = nil
        if flow.recordsPreviewSnapshot {
            chordInkRecognitionRequestState.lastRecognizedDrawingData = payload.drawingData
        } else {
            chordInkRecognitionRequestState.lastRecognizedDrawingData = nil
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
        guard let requestID = payloads.first?.requestID,
              chordInkRecognitionRequestState.finishActiveRequest(requestID) else {
            return
        }

        for payload in payloads {
            LeadSheetChordInkRecognitionTimingLogger.log(payload.timing, result: payload.result)
        }

        guard interactionMode.allowsChordInkEditing,
              recognizesChordInk,
              payloads.count > 1 else {
            return
        }

        chordInkRecognitionRequestState.continuationGraceDrawingData = nil
        chordInkRecognitionRequestState.lastRecognizedDrawingData = nil
        onChordInkBatchRecognitionProposal?(payloads, flow)
    }

    private func shouldGiveChordInkContinuationGrace(
        flow: ChordInkRecognitionFlow,
        result: ChordInkRecognitionResult,
        drawingData: Data,
        timing: ChordInkRecognitionTiming
    ) -> Bool {
        ChordInkAutomaticRecognitionPolicy.shouldGiveContinuationGrace(
            flow: flow,
            previousDrawingData: chordInkRecognitionRequestState.continuationGraceDrawingData,
            drawingData: drawingData,
            timing: timing,
            idleDelay: chordInkIdleDelay,
            result: result
        )
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
        var workingChart = chart
        if interactionMode.allowsDirectRhythmicNotationInk,
           let updatedChart = LeadSheetRhythmicNotationFinalization.chartByPersistingLiveDrawing(
               liveDrawingData,
               for: measureID,
               in: workingChart
           ) {
            clearDirtyInkAuthoringRole(.rhythm)
            chart = updatedChart
            onChartChanged?(updatedChart)
            workingChart = updatedChart
        }

        guard let measure = workingChart.measure(id: measureID),
              let drawingData = measure.handwrittenRhythmicNotationData,
              !drawingData.isEmpty,
              let measureLayout = measureLayout(for: measureID) else {
            clearRhythmicNotationUnreadInkFeedback()
            return true
        }

        guard !(RhythmRecognitionOverhaulGate.isLegacyAutoRenderParked
                && !RhythmRecognitionOverhaulGate.isTapToRenderRecognitionEnabled) else {
            cancelPendingRhythmicNotationAutoApply()
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
                allowsCommit: true
            )
            guard case .commit(let quantizedValues, _) = route else {
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
                quantizedValues,
                drawingData: drawingData,
                for: measureID,
                measureLayout: measureLayout,
                in: workingChart
            ) {
                clearRhythmicNotationUnreadInkFeedback()
                clearRhythmicNotationCanvas()
                chart = updatedChart
                onChartChanged?(updatedChart)
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
              LeadSheetRhythmicNotationAutoApplyPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: currentCanvasInkSnapshot(),
                scheduledInkSnapshot: scheduledInkSnapshot
              ) else {
            return
        }

        if let updatedChart = LeadSheetRhythmicNotationFinalization.chartByPersistingLiveDrawing(
            currentCanvasDrawingData(),
            for: measureID,
            in: chart
        ) {
            clearDirtyInkAuthoringRole(.rhythm)
            chart = updatedChart
            onChartChanged?(updatedChart)
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
            allowsCommit: false
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

    private func autoApplyRhythmicNotationIfReady(
        for measureID: UUID,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?
    ) {
        guard !RhythmRecognitionOverhaulGate.isLegacyAutoRenderParked else {
            persistRhythmicNotationInkIfStable(
                for: measureID,
                scheduledInkSnapshot: scheduledInkSnapshot
            )
            return
        }

        guard let candidate = liveRhythmicNotationCandidate(
            for: measureID,
            scheduledInkSnapshot: scheduledInkSnapshot,
            quietPreserveMode: .scheduleStaleFeedback
        ) else {
            return
        }

        scheduleRhythmicNotationCommitGrace(
            for: measureID,
            scheduledInkSnapshot: candidate.inkSnapshot,
            requiresExtendedStability: candidate.requiresExtendedStability
        )
    }

    private struct LiveRhythmicNotationCandidate {
        var drawingData: Data
        var inkSnapshot: LeadSheetInkDrawingSnapshot
        var values: [RhythmValue]
        var requiresExtendedStability: Bool
    }

    private enum RhythmicNotationQuietPreserveMode {
        case none
        case scheduleStaleFeedback
        case showStaleFeedback
    }

    private func liveRhythmicNotationCandidate(
        for measureID: UUID,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot?,
        quietPreserveMode: RhythmicNotationQuietPreserveMode = .none
    ) -> LiveRhythmicNotationCandidate? {
        let requiresNaturalExactFitAfterErase = rhythmicNotationEraseRecovery.requiresNaturalExactFit(
            for: measureID
        )
        guard interactionMode.allowsDirectRhythmicNotationInk else {
            return nil
        }
        guard selectedMeasureID == measureID else {
            return nil
        }
        guard let measure = chart.measure(id: measureID) else {
            return nil
        }
        guard let drawingData = currentCanvasDrawingData(),
              let inkSnapshot = currentCanvasInkSnapshot() else {
            return nil
        }
        guard LeadSheetRhythmicNotationAutoApplyPolicy.canAttemptAutoApply(
            currentInkSnapshot: inkSnapshot,
            scheduledInkSnapshot: scheduledInkSnapshot
        ) else {
            return nil
        }
        guard let measureLayout = measureLayout(for: measureID) else {
            return nil
        }

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
            return nil
        }

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: requiresNaturalExactFitAfterErase
        )
        guard case .commit(let values, let requiresExtendedStability) = route else {
            recordRhythmicNotationDiagnostic(
                for: decision,
                route: route,
                stage: .inkPreserved,
                measureID: measureID,
                measure: measure,
                drawingStrokeCount: pageInkCanvasView.drawing.strokes.count,
                drawingData: drawingData,
                measureLayout: measureLayout
            )
            let didShowFeedback = applyRhythmicNotationUnreadInkFeedback(
                for: decision,
                route: route,
                measureID: measureID
            )
            if !didShowFeedback {
                switch quietPreserveMode {
                case .none:
                    break
                case .scheduleStaleFeedback:
                    scheduleRhythmicNotationStaleFeedback(
                        for: measureID,
                        scheduledInkSnapshot: inkSnapshot
                    )
                case .showStaleFeedback:
                    showRhythmicNotationStaleInkFeedback(
                        for: decision,
                        measureID: measureID
                    )
                }
            }
            return nil
        }
        guard RhythmicNotationCompendium.accepts(
            values,
            in: measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        ) else {
            clearRhythmicNotationUnreadInkFeedback()
            return nil
        }

        clearRhythmicNotationUnreadInkFeedback()
        recordRhythmicNotationDiagnostic(
            for: decision,
            route: route,
            stage: .autoApplyCandidate,
            measureID: measureID,
            measure: measure,
            drawingStrokeCount: pageInkCanvasView.drawing.strokes.count,
            drawingData: drawingData,
            measureLayout: measureLayout
        )
        return LiveRhythmicNotationCandidate(
            drawingData: drawingData,
            inkSnapshot: inkSnapshot,
            values: values,
            requiresExtendedStability: requiresExtendedStability
        )
    }

    private func scheduleRhythmicNotationCommitGrace(
        for measureID: UUID,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot,
        requiresExtendedStability: Bool
    ) {
        pendingRhythmicNotationCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.commitAutoAppliedRhythmicNotationIfReady(
                for: measureID,
                scheduledInkSnapshot: scheduledInkSnapshot
            )
        }
        pendingRhythmicNotationCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LeadSheetRhythmicNotationAutoApplyPolicy.exactFitGraceDelay(
                requiresExtendedStability: requiresExtendedStability
            ),
            execute: workItem
        )
    }

    private func scheduleRhythmicNotationStaleFeedback(
        for measureID: UUID,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot
    ) {
        pendingRhythmicNotationCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.commitAutoAppliedRhythmicNotationIfReady(
                for: measureID,
                scheduledInkSnapshot: scheduledInkSnapshot
            )
        }
        pendingRhythmicNotationCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LeadSheetRhythmicNotationAutoApplyPolicy.exactFitGraceDelay(
                requiresExtendedStability: false
            ),
            execute: workItem
        )
    }

    private func commitAutoAppliedRhythmicNotationIfReady(
        for measureID: UUID,
        scheduledInkSnapshot: LeadSheetInkDrawingSnapshot
    ) {
        pendingRhythmicNotationCommitWorkItem = nil
        guard let candidate = liveRhythmicNotationCandidate(
            for: measureID,
            scheduledInkSnapshot: scheduledInkSnapshot,
            quietPreserveMode: .showStaleFeedback
        ),
              let measureLayout = measureLayout(for: measureID),
              let updatedChart = LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
                candidate.values,
                drawingData: candidate.drawingData,
                for: measureID,
                measureLayout: measureLayout,
                in: chart
              ) else {
            return
        }

        clearRhythmicNotationCanvas()
        chart = updatedChart
        onChartChanged?(updatedChart)
        setNeedsDisplay()
        if let measure = chart.measure(id: measureID) {
            let event = RhythmRecognitionDiagnosticEvent(
                id: UUID(),
                timestamp: .now,
                chartID: chart.id,
                chartTitle: chart.title,
                measureID: measureID,
                measureIndex: measure.index,
                layoutStyle: chart.layoutStyle,
                meterText: measure.resolvedMeter(defaultMeter: chart.defaultMeter).displayText,
                stage: .autoApplied,
                decision: "commit",
                route: "commit",
                reason: nil,
                proposalValues: candidate.values,
                proposalSafety: "autoApply",
                proposalIsNaturalExactFit: true,
                phraseSource: nil,
                naturalValues: candidate.values,
                naturalUnits: nil,
                targetUnits: nil,
                passesCompendium: true,
                primitiveCount: nil,
                symbolCount: nil,
                unreadSymbolCount: nil,
                uncoveredStrokeCount: nil,
                inkStrokeCount: drawingStrokeCount(from: candidate.drawingData),
                pipelinePreview: nil
            )
            publishRhythmicNotationDiagnostic(event)
        }
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
                for: feedback.measureID,
                measureLayout: measureLayout,
                in: chart
              ) else {
            return
        }

        pendingInkPersistWorkItem?.cancel()
        pendingInkPersistWorkItem = nil
        pendingRhythmicNotationCommitWorkItem?.cancel()
        pendingRhythmicNotationCommitWorkItem = nil
        clearRhythmicNotationCanvas()
        chart = updatedChart
        onChartChanged?(updatedChart)
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
                primitiveCount: nil,
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
            primitiveCount: decision.phrase?.primitives.count,
            symbolCount: decision.phrase?.symbols.count,
            unreadSymbolCount: decision.phrase?.symbols.filter { $0.selectedValue == nil }.count,
            uncoveredStrokeCount: decision.phrase?.uncoveredStrokeIndices.count,
            inkStrokeCount: drawingStrokeCount,
            pipelinePreview: pipelinePreview
        )
        publishRhythmicNotationDiagnostic(event)
    }

    private func publishRhythmicNotationDiagnostic(_ event: RhythmRecognitionDiagnosticEvent) {
        guard IChartRuntimeDiagnostics.isRhythmRecognitionDiagnosticsEnabled else {
            return
        }

        onRhythmicNotationDiagnostic?(event)
        do {
            try RhythmRecognitionDiagnosticsRecorder.live().append(event)
        } catch {
            print("iChart rhythm diagnostic error: \(error)")
        }
    }

    private func drawingStrokeCount(from drawingData: Data) -> Int {
        (try? PKDrawing(data: drawingData).strokes.count) ?? 0
    }

    private func cancelPendingRhythmicNotationAutoApply() {
        pendingInkInputCoalescingWorkItem?.cancel()
        pendingInkInputCoalescingWorkItem = nil
        pendingInkPersistWorkItem?.cancel()
        pendingInkPersistWorkItem = nil
        pendingRhythmicNotationCommitWorkItem?.cancel()
        pendingRhythmicNotationCommitWorkItem = nil
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
        clearDirtyInkAuthoringRole(.rhythm)
        pendingRhythmicNotationCommitWorkItem = nil
    }

    private func showRhythmicNotationUnreadInkFeedback(
        for decision: RhythmRecognitionDecision,
        measureID: UUID
    ) {
        let values = LeadSheetRhythmicNotationFeedbackPolicy.previewValues(for: decision)
        guard LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(for: decision),
              !values.isEmpty,
              let reason = decision.reason else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationPreviewState = LeadSheetRhythmicNotationPreviewState(
            measureID: measureID,
            meter: rhythmicNotationPreviewMeter(for: measureID),
            reason: reason,
            values: values,
            confirmationAction: LeadSheetRhythmicNotationFeedbackPolicy.confirmationAction(for: decision),
            isCertain: false
        )
    }

    private func showRhythmicNotationStaleInkFeedback(
        for decision: RhythmRecognitionDecision,
        measureID: UUID
    ) {
        let values = LeadSheetRhythmicNotationFeedbackPolicy.previewValues(for: decision)
        guard !values.isEmpty,
              let reason = decision.reason else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationPreviewState = LeadSheetRhythmicNotationPreviewState(
            measureID: measureID,
            meter: rhythmicNotationPreviewMeter(for: measureID),
            reason: reason,
            values: values,
            confirmationAction: LeadSheetRhythmicNotationFeedbackPolicy.confirmationAction(for: decision),
            isCertain: false
        )
    }

    private func showRhythmicNotationReadyToRenderFeedback(
        for decision: RhythmRecognitionDecision,
        measureID: UUID
    ) {
        let values = LeadSheetRhythmicNotationFeedbackPolicy.previewValues(for: decision)
        guard !values.isEmpty else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationPreviewState = LeadSheetRhythmicNotationPreviewState(
            measureID: measureID,
            meter: rhythmicNotationPreviewMeter(for: measureID),
            reason: nil,
            values: values,
            confirmationAction: .none,
            isCertain: true
        )
    }

    private func showRhythmicNotationLivePreviewFeedback(
        for decision: RhythmRecognitionDecision,
        measureID: UUID
    ) {
        let values = LeadSheetRhythmicNotationFeedbackPolicy.previewValues(for: decision)
        guard !values.isEmpty else {
            clearRhythmicNotationUnreadInkFeedback()
            return
        }

        rhythmicNotationPreviewState = LeadSheetRhythmicNotationPreviewState(
            measureID: measureID,
            meter: rhythmicNotationPreviewMeter(for: measureID),
            reason: decision.reason,
            values: values,
            confirmationAction: LeadSheetRhythmicNotationFeedbackPolicy.confirmationAction(for: decision),
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
            cancelPendingRhythmicNotationAutoApply()
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
        let drawing = pageInkCanvasView.drawing
        return drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
    }

    private func currentCanvasInkSnapshot() -> LeadSheetInkDrawingSnapshot? {
        LeadSheetInkDrawingSnapshot(drawing: pageInkCanvasView.drawing)
    }

    private func persistFreehandSymbolInkIfNeeded(canvasFrame: CGRect) {
        guard !chart.layoutStyle.profile.freehandSymbolLanes.isEmpty,
              let pageLayout,
              !pageInkCanvasView.drawing.strokes.isEmpty else {
            return
        }

        let groups = freehandSymbolStrokeGroups(
            from: pageInkCanvasView.drawing,
            canvasFrame: canvasFrame,
            pageLayout: pageLayout
        )
        clearFreehandSymbolCanvas()
        guard !groups.isEmpty else {
            return
        }

        var updatedChart = chart
        var didCommitSymbol = false
        for group in groups {
            let groupDrawing = PKDrawing(strokes: group.strokes)
            let localBounds = groupDrawing.bounds
                .standardized
                .insetBy(dx: -4, dy: -4)
            guard localBounds.width > 0,
                  localBounds.height > 0 else {
                continue
            }

            let pageFrame = localBounds.offsetBy(dx: canvasFrame.minX, dy: canvasFrame.minY)
            let normalizedFrame = FreehandSymbolNormalizedFrame(frame: pageFrame, in: group.referenceFrame)
            let measureRelativeFrame = group.lane == .chartArea
                ? FreehandSymbolMeasureFrame(frame: pageFrame, relativeTo: group.measureFrame)
                : nil
            let translatedDrawing = groupDrawing.transformed(
                using: CGAffineTransform(translationX: -localBounds.minX, y: -localBounds.minY)
            )
            guard updatedChart.addFreehandSymbol(
                anchorMeasureID: group.measureID,
                lane: group.lane,
                normalizedFrame: normalizedFrame,
                measureRelativeFrame: measureRelativeFrame,
                drawingData: translatedDrawing.dataRepresentation()
            ) != nil else {
                continue
            }

            didCommitSymbol = true
        }

        guard didCommitSymbol else {
            return
        }

        chart = updatedChart
        onChartChanged?(updatedChart)
        setNeedsDisplay()
    }

    private struct FreehandSymbolStrokeGroupKey: Hashable {
        var measureID: UUID
        var lane: FreehandSymbolLane
    }

    private struct FreehandSymbolStrokeGroup {
        var measureID: UUID
        var lane: FreehandSymbolLane
        var referenceFrame: CGRect
        var measureFrame: CGRect
        var strokes: [PKStroke]
    }

    private func freehandSymbolStrokeGroups(
        from drawing: PKDrawing,
        canvasFrame: CGRect,
        pageLayout: LeadSheetPageLayout
    ) -> [FreehandSymbolStrokeGroup] {
        var groupsByKey: [FreehandSymbolStrokeGroupKey: FreehandSymbolStrokeGroup] = [:]

        for stroke in drawing.strokes {
            guard let firstPoint = stroke.path.first?.location else {
                continue
            }

            let pageStart = CGPoint(
                x: firstPoint.x + canvasFrame.minX,
                y: firstPoint.y + canvasFrame.minY
            )
            guard let target = freehandSymbolTarget(at: pageStart, in: pageLayout) else {
                continue
            }

            let key = FreehandSymbolStrokeGroupKey(measureID: target.measureID, lane: target.lane)
            var group = groupsByKey[key] ?? FreehandSymbolStrokeGroup(
                measureID: target.measureID,
                lane: target.lane,
                referenceFrame: target.referenceFrame,
                measureFrame: target.measureFrame,
                strokes: []
            )
            group.strokes.append(stroke)
            groupsByKey[key] = group
        }

        return groupsByKey.values.sorted {
            if $0.measureID.uuidString == $1.measureID.uuidString {
                return $0.lane.rawValue < $1.lane.rawValue
            }

            return $0.measureID.uuidString < $1.measureID.uuidString
        }
    }

    private func freehandSymbolTarget(
        at pagePoint: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> (measureID: UUID, lane: FreehandSymbolLane, referenceFrame: CGRect, measureFrame: CGRect)? {
        if chart.layoutStyle.profile.freehandSymbolLanes.contains(.chartArea),
           pageLayout.paperFrame.contains(pagePoint),
           let anchor = freehandSymbolAnchorTarget(at: pagePoint, in: pageLayout) {
            return (
                anchor.measureID,
                .chartArea,
                pageLayout.paperFrame,
                anchor.measureFrame
            )
        }

        for measure in pageLayout.systems.flatMap(\.measures) {
            guard let measureID = measure.sourceMeasureID else {
                continue
            }

            if let aboveFrame = measure.freehandAboveFrame,
               aboveFrame.insetBy(dx: -10, dy: -10).contains(pagePoint) {
                return (measureID, .aboveMeasure, aboveFrame, measure.frame)
            }

            if let belowFrame = measure.freehandBelowFrame,
               belowFrame.insetBy(dx: -10, dy: -10).contains(pagePoint) {
                return (measureID, .belowMeasure, belowFrame, measure.frame)
            }
        }

        return nil
    }

    private func freehandSymbolAnchorTarget(
        at pagePoint: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> (measureID: UUID, measureFrame: CGRect)? {
        pageLayout.systems
            .flatMap(\.measures)
            .compactMap { measure -> (measureID: UUID, measureFrame: CGRect, distance: CGFloat)? in
                guard let measureID = measure.sourceMeasureID else {
                    return nil
                }

                return (
                    measureID,
                    measure.frame,
                    LeadSheetCanvasUIKitView.distance(from: pagePoint, to: measure.frame)
                )
            }
            .min { $0.distance < $1.distance }
            .map { ($0.measureID, $0.measureFrame) }
    }

    private func freehandSymbolAnchorTarget(
        for pageFrame: CGRect,
        in pageLayout: LeadSheetPageLayout
    ) -> (measureID: UUID, measureFrame: CGRect)? {
        freehandSymbolAnchorTarget(
            at: CGPoint(x: pageFrame.midX, y: pageFrame.midY),
            in: pageLayout
        )
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return sqrt(dx * dx + dy * dy)
    }

    private func clearFreehandSymbolCanvas() {
        guard !pageInkCanvasView.drawing.strokes.isEmpty else {
            return
        }

        isClearingFreehandSymbolInk = true
        isSyncingInkCanvasFromModel = true
        pageInkCanvasView.drawing = PKDrawing()
        isSyncingInkCanvasFromModel = false
        isClearingFreehandSymbolInk = false
    }

    private func updateInteractionMode() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(
            for: interactionMode,
            inkToolMode: inkToolMode
        )
        selectionTapRecognizer.isEnabled = policy.selectionTapEnabled
        inkSelectionTapRecognizer.isEnabled = policy.inkSelectionTapEnabled
        measureResizePanRecognizer.isEnabled = policy.measureResizePanEnabled
        chordEditTapRecognizer.isEnabled = policy.chordEditTapEnabled
        chordEditDoubleTapRecognizer.isEnabled = policy.chordEditTapEnabled
        chordMovePanRecognizer.isEnabled = policy.chordMovePanEnabled
        chordEditHitOverlayView.isHidden = policy.chordEditOverlayHidden
        chordEditHitOverlayView.isUserInteractionEnabled = policy.chordEditOverlayInteractionEnabled
        pageInkCanvasView.isUserInteractionEnabled = policy.pageInkCanvasInteractionEnabled
        pageInkCanvasView.drawingPolicy = policy.drawingPolicy
        pageInkCanvasView.tool = policy.canvasTool

        if policy.clearsMeasureResizeDrag {
            activeMeasureResizeDrag = nil
        }

        if policy.clearsChordInteractionState {
            activeChordMoveDrag = nil
            activeCueTextMoveDrag = nil
            activeRoadmapMarkerEditDrag = nil
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

        if gestureRecognizer === chordInkConfirmPanRecognizer {
            return chordInkConfirmSurfaceContains(gestureRecognizer.location(in: self))
        }

        if gestureRecognizer === chordMovePanRecognizer {
            let location = gestureRecognizer.location(in: self)
            let translation = chordMovePanRecognizer.translation(in: self)
            let startLocation = CGPoint(
                x: location.x - translation.x,
                y: location.y - translation.y
            )
            if cueTextMoveHitTarget(at: startLocation) != nil
                || lastCueTextDragHitTarget() != nil {
                return true
            }

            if roadmapMarkerMoveHitTarget(at: startLocation) != nil
                || lastRoadmapMarkerDragHitTarget() != nil {
                return true
            }

            if interactionMode.allowsPageInkEditing,
               !chart.layoutStyle.profile.freehandSymbolLanes.isEmpty {
                if let hitTarget = freehandSymbolEditHitTarget(at: startLocation) {
                    return hitTarget.action != .delete
                }

                return lastFreehandSymbolDragHitTarget() != nil
            }

            return chordMoveHitTarget(at: location) != nil
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let involvesChordMove = gestureRecognizer === chordMovePanRecognizer
            || otherGestureRecognizer === chordMovePanRecognizer
        let involvesParentScroll = isParentScrollGesture(gestureRecognizer)
            || isParentScrollGesture(otherGestureRecognizer)
        let involvesChordInkConfirmPan = gestureRecognizer === chordInkConfirmPanRecognizer
            || otherGestureRecognizer === chordInkConfirmPanRecognizer
        if involvesChordInkConfirmPan {
            return true
        }
        if !LeadSheetChordMoveScrollLockPolicy.allowsSimultaneousRecognition(
            involvesChordMove: involvesChordMove,
            involvesParentScroll: involvesParentScroll
        ) {
            return false
        }

        return gestureRecognizer === inkSelectionTapRecognizer
            || otherGestureRecognizer === inkSelectionTapRecognizer
            || involvesChordMove
    }
}

private final class LeadSheetParentScrollGestureGate: NSObject, UIGestureRecognizerDelegate {
    weak var canvasView: LeadSheetCanvasUIKitView?
    weak var scrollView: UIScrollView?
    private var panBlocker: UIPanGestureRecognizer?
    private var pinchBlocker: UIPinchGestureRecognizer?

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

        return !canvasView.allowsParentScrollGestureStart(at: touch.location(in: canvasView))
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

    @objc private func handleBlockerGesture(_: UIGestureRecognizer) {
        // The blocker only exists to make the parent scroll recognizer wait/fail.
    }

    deinit {
        uninstall()
    }
}

#endif

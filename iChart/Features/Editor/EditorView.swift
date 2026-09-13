import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct PendingChordRenderTimingEvidence {
    var event: ChordEntryDiagnosticEvent
    var committedAt: Date
}

private struct PendingMeasureStackInsertion: Identifiable {
    let id = UUID()
    let anchorMeasureID: UUID
}

private enum EditorToolAccent {
    static let semanticRead = Color(red: 0.16, green: 0.38, blue: 0.82)
    static let persistentInk = Color.orange
}

private struct ActiveToolDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
            .foregroundStyle(configuration.isPressed ? Color.white : EditorToolAccent.semanticRead)
            .background(
                configuration.isPressed
                    ? EditorToolAccent.semanticRead
                    : Color(uiColor: .systemBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        EditorToolAccent.semanticRead.opacity(configuration.isPressed ? 0 : 0.48),
                        lineWidth: 1.25
                    )
            )
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

enum IChartEditorGuidedTourStep: String, Identifiable {
    case setup
    case writeChords
    case renderChords
    case shapeForm
    case addCue
    case review
    case export
    case finish

    var id: String { rawValue }

    static let quickStartSteps: [IChartEditorGuidedTourStep] = [
        .setup,
        .writeChords,
        .renderChords,
        .shapeForm,
        .addCue,
        .review,
        .export,
        .finish
    ]

    var progressText: String? {
        guard let index = Self.quickStartSteps.firstIndex(of: self) else {
            return nil
        }

        return "\(index + 1) of \(Self.quickStartSteps.count)"
    }

    var title: String {
        switch self {
        case .setup:
            "Create A Page"
        case .writeChords:
            "Write Four Chords"
        case .renderChords:
            "Check And Render"
        case .shapeForm:
            "Shape The Form"
        case .addCue:
            "Add A Cue"
        case .review:
            "Review The Page"
        case .export:
            "Export When Ready"
        case .finish:
            "Quick Start Complete"
        }
    }

    var message: String {
        switch self {
        case .setup:
            "Four measures are ready. Change the setup if you want, then create the page."
        case .writeChords:
            "Tap Chords and write C, F, G, C in the first four measures. The small labels are previews."
        case .renderChords:
            "If iChart asks, choose the intended chord. When the previews look right, tap Render Chords."
        case .shapeForm:
            "Tap Measures. Select a measure, then use Add, Layout, or Delete. Try one change, or continue."
        case .addCue:
            "Open Tools > Text, choose a measure, then Above or Below. Add a short cue like Intro or Verse."
        case .review:
            "Tap Done. In Select, tap anything you want to move, edit, resize, or delete."
        case .export:
            "Tap Export PDF when the chart is ready. Your editable chart stays in Charts."
        case .finish:
            "You know the core loop. Ink and every advanced structure tool remain available in Help > How To."
        }
    }

    var targetText: String? {
        switch self {
        case .setup:
            "Create Blank Page"
        case .writeChords:
            "Chords • write C, F, G, C"
        case .renderChords:
            "Render Chords"
        case .shapeForm:
            "Measures • Add / Layout / Delete"
        case .addCue:
            "Tools > Text"
        case .review:
            "Done • then Select"
        case .export:
            "Export PDF"
        case .finish:
            nil
        }
    }

    var forwardActionTitle: String? {
        switch self {
        case .setup:
            nil
        case .export:
            "Skip Export"
        case .finish:
            "Done"
        default:
            "Continue"
        }
    }

    var nextStep: IChartEditorGuidedTourStep? {
        guard let index = Self.quickStartSteps.firstIndex(of: self) else {
            return nil
        }

        let nextIndex = index + 1
        guard Self.quickStartSteps.indices.contains(nextIndex) else {
            return nil
        }

        return Self.quickStartSteps[nextIndex]
    }
}

private struct IChartEditorGuidedTourRail: View {
    let step: IChartEditorGuidedTourStep
    let onNext: () -> Void
    let onFinish: () -> Void

    private let accent = IChartTourStyle.navy
    private let actionAccent = IChartTourStyle.orange
    private let paper = IChartTourStyle.paper
    private let ink = IChartTourStyle.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(actionAccent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Quick Start")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(actionAccent)

                        if let progressText = step.progressText {
                            Text(progressText)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accent.opacity(0.74))
                        }

                        Text(step.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent)
                    }

                    Text(step.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onFinish) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent.opacity(0.72))
                .accessibilityLabel("End Quick Start")
            }

            HStack(spacing: 10) {
                if let targetText = step.targetText {
                    Label(targetText, systemImage: "hand.tap")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(IChartTourStyle.orangeSoft)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                if let forwardActionTitle = step.forwardActionTitle {
                    Button(forwardActionTitle) {
                        if step == .finish {
                            onFinish()
                        } else {
                            onNext()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(actionAccent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paper.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(0.88), lineWidth: IChartTourStyle.borderLineWidth)
        }
        .shadow(color: accent.opacity(0.12), radius: 10, y: 5)
        .accessibilityElement(children: .contain)
    }
}

private struct IChartEditorOperationOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct EditorView: View {
    private static let supportedTimeSignatureChoices = [
        Meter(numerator: 4, denominator: 4),
        Meter(numerator: 3, denominator: 4),
        Meter(numerator: 5, denominator: 4),
        Meter(numerator: 6, denominator: 4),
        Meter(numerator: 3, denominator: 8),
        Meter(numerator: 5, denominator: 8),
        Meter(numerator: 6, denominator: 8),
        Meter(numerator: 7, denominator: 8),
        Meter(numerator: 9, denominator: 8),
        Meter(numerator: 12, denominator: 8)
    ]
    private static let showsChordFixtureCaptureTools = false
    private static let chordPreviewTelemetryQueue = DispatchQueue(
        label: "com.ichart.chord-preview-telemetry",
        qos: .utility
    )

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ChartLibraryStore
    @EnvironmentObject private var pdfLibraryStore: IChartPDFLibraryStore
    @Binding var chart: Chart
    @State private var activeSheet: EditorSheet?
    @State private var exportAlertMessage = ""
    @State private var showingExportAlert = false
    @State private var showingSetupSheet = false
    @State private var showingHeaderSheet = false
    @State private var showingTypographySheet = false
    @State private var isExporting = false
    @State private var activeEditorOperationMessage: String?
    @State private var activeEditorOperationID = UUID()
    @State private var didRecordFirstCanvasAppear = false
    @State private var selectedMeasureID: UUID?
    @State private var selectedNoteSelection: LeadSheetNoteSelection?
    @State private var selectedChordID: UUID?
    @State private var selectedCommittedBarlineMeasureID: UUID?
    @State private var selectedCueTextID: UUID?
    @State private var selectedRoadmapMarkerID: UUID?
    @State private var isNoteEditMenuPresented = false
    @State private var noteEditMenuStage: NoteEditMenuStage = .actions
    @State private var noteEditErrorMessage = ""
    @State private var showingNoteEditError = false
    @State private var pendingChordInkConfirmation: PendingChordInkConfirmation?
    @State private var pendingChordInkBatchConfirmation: PendingChordInkBatchConfirmation?
    @State private var pendingChordCorrection: PendingChordCorrection?
    @State private var chordPreviewState = ChordPreviewState()
    @State private var chordDraftRenderInvalidationRequestID: UUID?
    @State private var pendingChordRenderTimingEvidence: [UUID: PendingChordRenderTimingEvidence] = [:]
    @State private var chordInkUserCorrectionMemory: ChordInkUserCorrectionMemory
    @State private var chordInkAutomaticRewriteFailures = ChordInkAutomaticRewriteFailureTracker()
    @State private var chordInkErrorMessage = ""
    @State private var showingChordInkError = false
    @State private var pendingTimeSignatureSourceMeasureID: UUID?
    @State private var pendingTimeSignaturePlacement: PendingTimeSignaturePlacement?
    @State private var pendingRepeatStartMeasureID: UUID?
    @State private var pendingDeleteStartMeasureID: UUID?
    @State private var pendingEndingStartMeasureID: UUID?
    @State private var pendingEndingType: RoadmapType?
    @State private var pendingMeasureStackInsertion: PendingMeasureStackInsertion?
    @State private var pendingCueTextMeasureID: UUID?
    @State private var pendingCueTextPosition: CuePosition?
    @State private var cueTextDraft = ""
    @State private var showingCueTextEntry = false
    @State private var editingCueTextID: UUID?
    @State private var canvasMode: EditorCanvasMode = .browse
    @State private var inkToolMode: EditorInkToolMode = .write
    @State private var editorGuidedTourStep: IChartEditorGuidedTourStep?
    @State private var latestEditorContentSize = CGSize(width: 900, height: 1400)
    @State private var pendingChordDiagnosticReconciliationWorkItem: DispatchWorkItem?
    @State private var latestRhythmPreview: LeadSheetRhythmicNotationPreviewState?
    @State private var rhythmPreviewConfirmationRequestID: UUID?
    @AppStorage("iChartPendingSimpleChartTour") private var pendingSimpleChartTour = false
    private let exporter: any ChartExporting
    private let chordInkUserCorrectionMemoryStore: ChordInkUserCorrectionMemoryStore
    private let onExit: (() -> Void)?

    private static func releaseSafeInitialCanvasMode(_ mode: EditorCanvasMode) -> EditorCanvasMode {
        guard mode != .rhythmicNotationEdit
                || RhythmRecognitionOverhaulGate.shipsDedicatedRhythmTool else {
            return .browse
        }

        return mode
    }

    init(
        chart: Binding<Chart>,
        exporter: any ChartExporting = PDFChartExporter.live(),
        chordInkUserCorrectionMemoryStore: ChordInkUserCorrectionMemoryStore = .live(),
        initialCanvasMode: EditorCanvasMode = .browse,
        onExit: (() -> Void)? = nil
    ) {
        self._chart = chart
        self.exporter = exporter
        self.chordInkUserCorrectionMemoryStore = chordInkUserCorrectionMemoryStore
        self.onExit = onExit
        _canvasMode = State(initialValue: Self.releaseSafeInitialCanvasMode(initialCanvasMode))
        _chordInkUserCorrectionMemory = State(
            initialValue: (try? chordInkUserCorrectionMemoryStore.load()) ?? ChordInkUserCorrectionMemory()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            editorNavigationChrome

            if let editorGuidedTourStep,
               editorGuidedTourStep != .setup {
                IChartEditorGuidedTourRail(
                    step: editorGuidedTourStep,
                    onNext: advanceEditorGuidedTourManually,
                    onFinish: finishEditorGuidedTour
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .overlay(alignment: .bottom) {
                    Divider()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            GeometryReader { proxy in
                editorSurface(availableSize: proxy.size)
            }
        }
        .allowsHitTesting(!showingCueTextEntry)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.94, blue: 0.91),
                    Color(red: 0.90, green: 0.93, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            if let activeEditorOperationMessage {
                IChartEditorOperationOverlay(message: activeEditorOperationMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay {
            if showingCueTextEntry {
                CueTextEntryPanelView(
                    text: $cueTextDraft,
                    actionTitle: editingCueTextID == nil ? "Add" : "Apply",
                    highlightsAction: editorGuidedTourStep == .addCue,
                    onAdd: handleCueTextEntryAccepted,
                    onCancel: clearPendingCueTextEntry
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: activeEditorOperationMessage)
        .animation(.easeOut(duration: 0.16), value: showingCueTextEntry)
        .navigationTitle(chart.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .upgrade(let feature):
                UpgradeSheetView(feature: feature)
                    .environmentObject(store)
            case .export(let exportedPDF):
                PDFExportPreviewView(exportedPDF: exportedPDF)
            }
        }
        .sheet(isPresented: $showingSetupSheet) {
            ChartSetupSheetView(
                chart: $chart,
                isCreateActionHighlighted: editorGuidedTourStep == .setup,
                showsCreateTourBanner: editorGuidedTourStep == .setup,
                onSkipTour: finishEditorGuidedTour,
                onOperationStarted: showEditorOperation,
                onOperationFinished: clearEditorOperation
            )
        }
        .sheet(isPresented: $showingHeaderSheet) {
            ChartHeaderSheetView(chart: $chart)
        }
        .sheet(isPresented: $showingTypographySheet) {
            ChartTypographySheetView(chart: $chart)
        }
        .sheet(item: $pendingMeasureStackInsertion) { insertion in
            MeasureStackInsertionSheetView(
                highlightsAddAction: editorGuidedTourStep == .shapeForm,
                onAdd: { measureCount in
                    handleMeasureStackInsertionAccepted(measureCount, insertion: insertion)
                },
                onCancel: {
                    pendingMeasureStackInsertion = nil
                }
            )
        }
        .sheet(item: $pendingChordInkConfirmation) { confirmation in
            ChordInkConfirmationSheetView(
                confirmation: confirmation,
                showsFixtureCaptureTools: Self.showsChordFixtureCaptureTools,
                highlightsForwardActions: editorGuidedTourStep == .renderChords,
                onAcceptCandidate: { candidateText in
                    handleChordInkCandidateAccepted(candidateText, confirmation: confirmation)
                },
                onCopyFixtureJSON: { candidateText in
                    #if DEBUG && targetEnvironment(simulator)
                    handleChordInkFixtureCopyRequested(candidateText, confirmation: confirmation)
                    #else
                    _ = candidateText
                    return .unavailable
                    #endif
                },
                onClearAndRewrite: {
                    handleChordInkRewriteRequested()
                }
            )
        }
        .sheet(item: $pendingChordInkBatchConfirmation) { batch in
            ChordInkBatchConfirmationSheetView(
                batch: batch,
                highlightsForwardActions: editorGuidedTourStep == .renderChords,
                onAcceptAll: { candidateTextByID in
                    handleChordInkBatchAccepted(candidateTextByID, batch: batch)
                },
                onClearAndRewrite: {
                    handleChordInkRewriteRequested()
                }
            )
        }
        .sheet(item: $pendingChordCorrection) { correction in
            ChordCorrectionSheetView(
                correction: correction,
                onAcceptCandidate: { candidateText in
                    handleChordCorrectionAccepted(candidateText, correction: correction)
                },
                onCancel: {
                    pendingChordCorrection = nil
                }
            )
        }
        .confirmationDialog(
            "Change Time Signature",
            isPresented: Binding(
                get: { pendingTimeSignatureSourceMeasureID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingTimeSignatureSourceMeasureID = nil
                    }
                }
            )
        ) {
            if let sourceMeasureID = pendingTimeSignatureSourceMeasureID {
                ForEach(Self.supportedTimeSignatureChoices, id: \.self) { meter in
                    Button(meter.displayText) {
                        pendingTimeSignatureSourceMeasureID = nil
                        pendingTimeSignaturePlacement = PendingTimeSignaturePlacement(
                            sourceMeasureID: sourceMeasureID,
                            meter: meter
                        )
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                pendingTimeSignatureSourceMeasureID = nil
                pendingTimeSignaturePlacement = nil
            }
        } message: {
            Text("Apply the new time signature starting at the selected measure.")
        }
        .sheet(item: $pendingTimeSignaturePlacement) { placement in
            TimeSignatureScopeSheetView(
                meter: placement.meter,
                highlightsApplyActions: false,
                onApplyCount: { additionalMeasureCount in
                    handleTimeSignatureSelection(
                        placement.meter,
                        startingAt: placement.sourceMeasureID,
                        scope: .fixedMeasureCount(additionalMeasureCount)
                    )
                },
                onApplyToEndOfPiece: {
                    handleTimeSignatureSelection(
                        placement.meter,
                        startingAt: placement.sourceMeasureID,
                        scope: .toEndOfPiece
                    )
                },
                onApplyToNextTimeSignature: {
                    handleTimeSignatureSelection(
                        placement.meter,
                        startingAt: placement.sourceMeasureID,
                        scope: .toNextTimeSignature
                    )
                }
            )
        }
        .alert("Export PDF", isPresented: $showingExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportAlertMessage)
        }
        .alert("Rhythm Edit", isPresented: $showingNoteEditError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noteEditErrorMessage)
        }
        .alert("Chord Recognition", isPresented: $showingChordInkError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(chordInkErrorMessage)
        }
        .onChange(of: selectedNoteSelection) { _, selection in
            if selection == nil {
                isNoteEditMenuPresented = false
                noteEditMenuStage = .actions
            } else if canvasMode == .noteEdit,
                      allowsUserFacingRhythmNoteEditing {
                noteEditMenuStage = .actions
                isNoteEditMenuPresented = true
            }
        }
        .onChange(of: canvasMode) { previousMode, mode in
            guard mode != .rhythmicNotationEdit || isDedicatedRhythmToolAvailable else {
                latestRhythmPreview = nil
                rhythmPreviewConfirmationRequestID = nil
                canvasMode = .browse
                return
            }
            if previousMode != mode {
                IChartTelemetry.record(
                    "editor.mode_changed",
                    properties: [
                        "from_mode": .string(previousMode.telemetryValue),
                        "to_mode": .string(mode.telemetryValue),
                        "layout_style": .string(chart.layoutStyle.rawValue),
                        "measure_count": .int(chart.measures.count),
                        "ink_tool_mode": .string(inkToolMode.rawValue)
                    ]
                )
            }
            if mode != .noteEdit {
                isNoteEditMenuPresented = false
                noteEditMenuStage = .actions
            }
            if mode != .browse {
                clearSelectedCanvasObjectIDs()
            }
            if mode.allowsAnyInkEditing {
                inkToolMode = .write
            }
        }
        .onChange(of: chart) { previousChart, updatedChart in
            if !previousChart.hasCompletedInitialSetup,
               updatedChart.hasCompletedInitialSetup {
                IChartTelemetry.record(
                    "editor.chart_setup_completed",
                    properties: [
                        "layout_style": .string(updatedChart.layoutStyle.rawValue),
                        "measure_count": .int(updatedChart.measures.count)
                    ]
                )
            }
            scheduleChordEntryDiagnosticReconciliation(for: updatedChart)
            advanceEditorGuidedTourAfterSetupIfNeeded(updatedChart)
            #if DEBUG && targetEnvironment(simulator)
            recordPendingChordRenderHandoff()
            #endif
        }
        .onDisappear {
            pendingChordDiagnosticReconciliationWorkItem?.cancel()
            pendingChordDiagnosticReconciliationWorkItem = nil
            IChartTelemetry.record(
                "editor.closed",
                properties: [
                    "mode": .string(canvasMode.telemetryValue),
                    "layout_style": .string(chart.layoutStyle.rawValue),
                    "measure_count": .int(chart.measures.count)
                ]
            )
        }
        .task {
            IChartTelemetry.record(
                "editor.opened",
                properties: [
                    "mode": .string(canvasMode.telemetryValue),
                    "layout_style": .string(chart.layoutStyle.rawValue),
                    "measure_count": .int(chart.measures.count)
                ]
            )
            startPendingSimpleChartTourIfNeeded()

            if chart.staffStyle != .fiveLine {
                chart.staffStyle = .fiveLine
                chart.updatedAt = .now
            }
            if !chart.hasCompletedInitialSetup {
                showingSetupSheet = true
            }
        }
    }

    private func startPendingSimpleChartTourIfNeeded() {
        guard pendingSimpleChartTour,
              chart.layoutStyle == .simpleChordSheet else {
            return
        }

        pendingSimpleChartTour = false
        if chart.hasCompletedInitialSetup {
            canvasMode = .browse
            editorGuidedTourStep = .writeChords
        } else {
            editorGuidedTourStep = .setup
        }
    }

    private func advanceEditorGuidedTourAfterSetupIfNeeded(_ updatedChart: Chart) {
        guard editorGuidedTourStep == .setup,
              updatedChart.hasCompletedInitialSetup else {
            return
        }

        canvasMode = .browse
        completeEditorGuidedTourStep(.setup)
    }

    private func advanceEditorGuidedTourManually() {
        guard let currentStep = editorGuidedTourStep else {
            return
        }

        switch currentStep {
        case .finish:
            finishEditorGuidedTour()
        case .review:
            activateSelectTool()
            completeEditorGuidedTourStep(currentStep)
        case .setup:
            break
        case .writeChords, .renderChords, .shapeForm, .addCue, .export:
            completeEditorGuidedTourStep(currentStep)
        }
    }

    private func completeEditorGuidedTourStep(_ completedStep: IChartEditorGuidedTourStep) {
        guard editorGuidedTourStep == completedStep else {
            return
        }

        guard let nextStep = completedStep.nextStep else {
            finishEditorGuidedTour()
            return
        }

        editorGuidedTourStep = nextStep
    }

    private func finishEditorGuidedTour() {
        pendingSimpleChartTour = false
        withAnimation(.easeInOut(duration: 0.18)) {
            editorGuidedTourStep = nil
        }
    }

    private func runEditorOperation(_ message: String, perform work: @escaping () -> Void) {
        let operationID = UUID()
        activeEditorOperationID = operationID
        activeEditorOperationMessage = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            work()
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard activeEditorOperationID == operationID else {
                return
            }

            activeEditorOperationMessage = nil
        }
    }

    private func showEditorOperation(_ message: String) {
        activeEditorOperationID = UUID()
        activeEditorOperationMessage = message
    }

    private func clearEditorOperation() {
        activeEditorOperationMessage = nil
    }

    private var editorNavigationChrome: some View {
        GeometryReader { geometry in
            let columnWidth = EditorCommandLayoutPolicy.navigationColumnWidth(
                for: geometry.size.width
            )

            HStack(spacing: 0) {
                Button {
                    exitEditor()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Exit Chart")
                .frame(width: columnWidth, alignment: .leading)

                Menu {
                    if canvasMode.locksDocumentActions {
                        Text("Choose Done before changing document settings.")
                    }

                    Group {
                        pageToolMenuContent
                    }
                    .disabled(
                        !EditorCommandLayoutPolicy.canActivate(
                            .documentSettings,
                            chartIsReady: chart.hasCompletedInitialSetup,
                            from: canvasMode
                        )
                    )
                } label: {
                    HStack(spacing: 5) {
                        Text(chart.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Document settings for \(chart.title)")
                .frame(width: columnWidth, alignment: .center)

                Button {
                    activateSelectTool(clearsMeasureSelection: true)
                    handleExportTapped()
                } label: {
                    Group {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Label(exportButtonTitle, systemImage: "square.and.arrow.up")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .disabled(isExporting || !chart.hasCompletedInitialSetup || !canvasMode.allowsTopBarExport)
                .accessibilityLabel(isExporting ? "Exporting PDF" : exportButtonTitle)
                .tourActionHighlight(
                    isActive: editorGuidedTourStep == .export,
                    cornerRadius: 10,
                    tint: IChartTourStyle.orange
                )
                .frame(width: columnWidth, alignment: .trailing)
            }
        }
        .frame(height: EditorCommandLayoutPolicy.minimumTapTarget)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func editorSurface(availableSize: CGSize) -> some View {
        let horizontalPadding = editorHorizontalPadding(for: availableSize.width)
        let verticalPadding = editorVerticalPadding(for: availableSize.height)
        let contentSize = CGSize(
            width: max(1, availableSize.width - horizontalPadding * 2),
            height: max(1, availableSize.height - verticalPadding * 2)
        )

        VStack(spacing: 0) {
            editorToolChrome(minWidth: contentSize.width)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView {
                canvasView
                    .frame(width: contentSize.width, alignment: .topLeading)
                    .frame(minHeight: canvasHeight(for: contentSize), alignment: .topLeading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, verticalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            latestEditorContentSize = contentSize
        }
        .onChange(of: contentSize) { _, newContentSize in
            latestEditorContentSize = newContentSize
        }
    }

    private func editorToolChrome(minWidth: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            toolStrip(minWidth: minWidth)
                .frame(maxWidth: .infinity, alignment: .center)

            Group {
                if showsActiveToolControls {
                    activeToolControls(minWidth: minWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.16), value: canvasMode)
            .animation(.easeOut(duration: 0.16), value: selectedRoadmapMarkerID)

            if showsSelectedRenderedEditActions {
                selectedRenderedEditActionTray(minWidth: minWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: selectedChordID)
        .animation(.easeOut(duration: 0.16), value: selectedCommittedBarlineMeasureID)
        .animation(.easeOut(duration: 0.16), value: selectedMeasureID)
        .animation(.easeOut(duration: 0.16), value: selectedCueTextID)
        .animation(.easeOut(duration: 0.16), value: selectedRoadmapMarkerID)
    }

    private var showsActiveToolControls: Bool {
        canvasMode.showsActiveToolControls
    }

    private var showsSelectedRenderedEditActions: Bool {
        guard canvasMode == .browse else {
            return false
        }

        return selectedChord != nil
            || selectedCommittedBarlineMeasureID != nil
            || selectedCueText != nil
            || selectedRoadmapMarker != nil
            || selectedMeasureID != nil
    }

    private var isEditorGuidedTourDoneActionHighlighted: Bool {
        editorGuidedTourStep == .review
    }

    private var isChordTourSectionActive: Bool {
        switch editorGuidedTourStep {
        case .writeChords, .renderChords:
            true
        default:
            false
        }
    }

    private var isMeasureTourSectionActive: Bool {
        editorGuidedTourStep == .shapeForm
    }

    private var isTextTourSectionActive: Bool {
        editorGuidedTourStep == .addCue
    }

    private var isDedicatedRhythmToolAvailable: Bool {
        RhythmRecognitionOverhaulGate.shipsDedicatedRhythmTool
            && chart.layoutStyle.profile.allowsRhythmicNotationInk
    }

    @ViewBuilder
    private var pageToolMenuContent: some View {
        if !chart.hasCompletedInitialSetup {
            Button {
                activateSelectTool(clearsMeasureSelection: true)
                showingSetupSheet = true
            } label: {
                Label("Setup", systemImage: "doc.text")
            }

            Divider()
        }

        Button {
            handleAddPageTapped()
        } label: {
            Label("Add Page", systemImage: "doc.badge.plus")
        }
        .disabled(!chart.hasCompletedInitialSetup || canvasMode.locksDocumentActions)

        Menu {
            Button {
                activateSelectTool(clearsMeasureSelection: true)
                chart.setHeaderInputMode(.typed)
                showingHeaderSheet = true
            } label: {
                notationMenuLabel("Typed", isSelected: chart.headerInputMode == .typed)
            }

            Button {
                activateHeaderWritingTool()
            } label: {
                notationMenuLabel("Handwritten", isSelected: chart.headerInputMode == .handwritten)
            }

            if chart.pageHandwrittenHeaderData != nil {
                Divider()

                Button(role: .destructive) {
                    activateSelectTool(clearsMeasureSelection: true)
                    chart.setPageHandwrittenHeaderDrawing(nil)
                } label: {
                    Label("Clear Handwritten Header", systemImage: "trash")
                }
            }
        } label: {
            Label("Header (\(chart.headerInputMode.displayText))", systemImage: "character.cursor.ibeam")
        }

        Menu {
            Menu {
                keySelectionMenuItems(selectedKey: chart.displayedDocumentKey) { key in
                    activateSelectTool(clearsMeasureSelection: true)
                    chart.setDisplayedDocumentKey(key)
                }
            } label: {
                Label("Chart Key", systemImage: "key")
            }

            Menu {
                keySelectionMenuItems(selectedKey: selectedMeasureDisplayedEffectiveKey) { key in
                    handleKeyChangeSelection(key)
                }
            } label: {
                Label("Key Change at Selected Measure", systemImage: "arrow.triangle.branch")
            }
            .disabled(resolvedMeasureActionTargetID() == nil)

            if let targetMeasureID = resolvedMeasureActionTargetID(),
               chart.keyChange(atStartOf: targetMeasureID) != nil {
                Divider()

                Button(role: .destructive) {
                    handleRemoveKeyChangeAtSelectedMeasure()
                } label: {
                    Label("Remove Selected Key Change", systemImage: "trash")
                }
            }
        } label: {
            Label(
                "Key (\(chart.displayedDocumentKey.compactDisplayText))",
                systemImage: "key"
            )
        }

        Menu {
            ForEach(TranspositionView.instrumentOptions) { view in
                Button {
                    activateSelectTool(clearsMeasureSelection: true)
                    chart.setInstrumentTranspositionView(view)
                } label: {
                    notationMenuLabel(
                        "\(view.displayText) (\(view.intervalDisplayText))",
                        isSelected: chart.defaultTranspositionView == view
                            && chart.chordTranspositionSemitones == 0
                    )
                }
            }
        } label: {
            Label(
                "Instrument (\(chart.defaultTranspositionView.displayText))",
                systemImage: "music.note"
            )
        }

        Menu {
            Button {
                activateSelectTool(clearsMeasureSelection: true)
                chart.transposeChordsByHalfSteps(1)
            } label: {
                Label("Up Half Step", systemImage: "arrow.up")
            }

            Button {
                activateSelectTool(clearsMeasureSelection: true)
                chart.transposeChordsByHalfSteps(-1)
            } label: {
                Label("Down Half Step", systemImage: "arrow.down")
            }

            Button {
                activateSelectTool(clearsMeasureSelection: true)
                chart.setChordTranspositionSemitones(0)
            } label: {
                Label("Reset to Written", systemImage: "arrow.uturn.backward")
            }

            Divider()

            ForEach(Array(0...11), id: \.self) { semitones in
                Button {
                    activateSelectTool(clearsMeasureSelection: true)
                    chart.setChordTranspositionSemitones(semitones)
                } label: {
                    notationMenuLabel(
                        chordTranspositionOptionTitle(semitones),
                        isSelected: semitones == 0
                    )
                }
            }
        } label: {
            Label(
                "Transpose",
                systemImage: "arrow.up.arrow.down"
            )
        }

        Divider()

        Menu {
            ForEach(StylePreset.sheetPresets(for: chart.layoutStyle), id: \.self) { preset in
                Button {
                    activateSelectTool(clearsMeasureSelection: true)
                    runEditorOperation("Updating page style...") {
                        chart.setStylePreset(preset)
                    }
                } label: {
                    notationMenuLabel(
                        preset.sheetDisplayText(for: chart.layoutStyle),
                        isSelected: chart.stylePreset == preset
                    )
                }
            }
        } label: {
            Label("Style", systemImage: "paintpalette")
        }

        Button {
            activateSelectTool(clearsMeasureSelection: true)
            showingTypographySheet = true
        } label: {
            Label("Fonts", systemImage: "textformat")
        }

        Menu {
            ForEach(EngravingPreset.allCases, id: \.self) { preset in
                Button {
                    activateSelectTool(clearsMeasureSelection: true)
                    runEditorOperation("Updating engraving...") {
                        chart.setEngravingPreset(preset)
                    }
                } label: {
                    notationMenuLabel(preset.displayText, isSelected: chart.engravingPreset == preset)
                }
            }
        } label: {
            Label("Engraving", systemImage: "slider.horizontal.3")
        }

    }

    @ViewBuilder
    private func keySelectionMenuItems(
        selectedKey: DocumentKey,
        action: @escaping (DocumentKey) -> Void
    ) -> some View {
        Menu("Major") {
            ForEach(DocumentKey.standardMajorKeys) { key in
                Button {
                    action(key)
                } label: {
                    notationMenuLabel(
                        key.titleDisplayText,
                        isSelected: selectedKey == key
                    )
                }
            }
        }

        Menu("Minor") {
            ForEach(DocumentKey.standardMinorKeys) { key in
                Button {
                    action(key)
                } label: {
                    notationMenuLabel(
                        key.titleDisplayText,
                        isSelected: selectedKey == key
                    )
                }
            }
        }
    }

    private var selectedMeasureDisplayedEffectiveKey: DocumentKey {
        resolvedMeasureActionTargetID()
            .map { chart.displayedEffectiveKey(forMeasureID: $0) }
            ?? chart.displayedDocumentKey
    }

    @ViewBuilder
    private var codaToolMenuContent: some View {
        if selectedRoadmapMarker != nil {
            Button {
                resizeSelectedRoadmapMarker(by: RoadmapObject.scaleStep)
            } label: {
                Label("Make Marker Larger", systemImage: "plus.magnifyingglass")
            }
            .disabled(!canGrowSelectedRoadmapMarker)

            Button {
                resizeSelectedRoadmapMarker(by: -RoadmapObject.scaleStep)
            } label: {
                Label("Make Marker Smaller", systemImage: "minus.magnifyingglass")
            }
            .disabled(!canShrinkSelectedRoadmapMarker)

            Button(role: .destructive) {
                deleteSelectedRoadmapMarker()
            } label: {
                Label("Delete Selected Marker", systemImage: "trash")
            }

            Divider()
        }

        ForEach(RoadmapType.navigationPointMarkerTypes, id: \.self) { roadmapType in
            Button {
                handleAddPointRoadmapMarker(roadmapType)
            } label: {
                Text(roadmapType.editorMenuDisplayText)
            }
        }
    }

    private func toolStrip(minWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(EditorCommandLayoutPolicy.primaryDestinations) { destination in
                primaryToolControl(for: destination)
                    .frame(maxWidth: .infinity)
            }

            toolsMenuControl
                .frame(maxWidth: .infinity)
        }
        .padding(4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .frame(width: minWidth, alignment: .center)
    }

    @ViewBuilder
    private func primaryToolControl(
        for destination: EditorCommandDestination
    ) -> some View {
        switch destination {
        case .select:
            Button {
                handleActiveToolDoneTapped()
            } label: {
                EditorMenuTabLabel(
                    title: "Select",
                    systemImage: "cursorarrow",
                    isSelected: canvasMode == .browse
                )
            }
            .buttonStyle(.plain)

        case .chords:
            Button {
                handleChordTabTapped()
            } label: {
                EditorMenuTabLabel(
                    title: "Chords",
                    systemImage: "pencil",
                    isSelected: canvasMode == .chordEntry,
                    selectedColor: EditorToolAccent.semanticRead,
                    isTourHighlighted: isChordTourSectionActive
                )
            }
            .disabled(
                !EditorCommandLayoutPolicy.canActivate(
                    .chords,
                    chartIsReady: chart.hasCompletedInitialSetup,
                    from: canvasMode
                )
            )
            .buttonStyle(.plain)

        case .ink:
            Button {
                selectedMeasureID = nil
                selectedNoteSelection = nil
                pendingTimeSignatureSourceMeasureID = nil
                pendingTimeSignaturePlacement = nil
                toggleFreeHandMode()
            } label: {
                EditorMenuTabLabel(
                    title: "Ink",
                    systemImage: canvasMode.freeHandTabSymbol,
                    isSelected: canvasMode == .freeHand,
                    selectedColor: EditorToolAccent.persistentInk,
                    isTourHighlighted: false
                )
            }
            .disabled(
                !EditorCommandLayoutPolicy.canActivate(
                    .ink,
                    chartIsReady: chart.hasCompletedInitialSetup,
                    from: canvasMode
                )
            )
            .buttonStyle(.plain)
            .accessibilityLabel("Ink")
            .accessibilityHint("Persistent free-writing that iChart does not interpret")

        case .measures:
            Button {
                handleMeasureEditRequested()
            } label: {
                EditorMenuTabLabel(
                    title: "Measures",
                    systemImage: "rectangle.split.3x1",
                    isSelected: canvasMode == .measureEdit || isMeasureDeleteContinuationActive,
                    isTourHighlighted: isMeasureTourSectionActive
                )
            }
            .disabled(
                !EditorCommandLayoutPolicy.canActivate(
                    .measures,
                    chartIsReady: chart.hasCompletedInitialSetup,
                    from: canvasMode
                )
            )
            .buttonStyle(.plain)

        case .documentSettings, .repeats, .timeSignature, .rhythm, .text, .formMarkers:
            EmptyView()
        }
    }

    private var toolsMenuControl: some View {
        Menu {
            Section("Structure") {
                Button {
                    handleRepeatToolTapped()
                } label: {
                    Label("Repeats", systemImage: "repeat")
                }

                Button {
                    handleTimeSignatureTabTapped()
                } label: {
                    Label("Time Signature", systemImage: "metronome")
                }

                if isDedicatedRhythmToolAvailable {
                    Button {
                        handleRhythmicNotationTabTapped()
                    } label: {
                        Label("Rhythm", systemImage: "music.note")
                    }
                }
            }

            Section("Annotate") {
                Button {
                    handleTextToolTapped()
                } label: {
                    Label("Text", systemImage: "text.bubble")
                }

                Menu {
                    codaToolMenuContent
                } label: {
                    Label("Form Markers", systemImage: "signpost.right")
                }
            }
        } label: {
            EditorMenuTabLabel(
                title: "Tools",
                systemImage: "ellipsis.circle",
                isSelected: EditorCommandLayoutPolicy.isToolsMenuActive(for: canvasMode),
                isTourHighlighted: isToolsMenuTourHighlighted
            )
        }
        .disabled(
            !EditorCommandLayoutPolicy.canActivate(
                .repeats,
                chartIsReady: chart.hasCompletedInitialSetup,
                from: canvasMode
            )
        )
        .buttonStyle(.plain)
        .accessibilityLabel("Tools")
        .accessibilityHint("Repeats, time signatures, text, and form markers")
    }

    private var isToolsMenuTourHighlighted: Bool {
        isTextTourSectionActive
    }

    private func activeToolControls(minWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                activeToolControlStrip(minWidth: max(1, minWidth - 94))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            activeToolDoneButton
                .layoutPriority(1)
        }
        .frame(maxWidth: minWidth, alignment: .center)
    }

    private func activeToolControlStrip(minWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            activeToolControlItems
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .frame(minWidth: minWidth, alignment: .center)
    }

    @ViewBuilder
    private var activeToolControlItems: some View {
        activeToolContextLabel

        if canvasMode.allowsAnyInkEditing {
            InkToolModeTab(mode: $inkToolMode)
        }

        if canvasMode == .measureEdit {
            measureActiveToolActions
        }

        if canvasMode == .repeatEdit {
            repeatActiveToolActions
        }

        if canvasMode == .headerEntry {
            headerActiveToolActions
        }

        if canvasMode == .rhythmicNotationEdit,
           isDedicatedRhythmToolAvailable {
            rhythmActiveToolActions
            if latestRhythmPreview != nil {
                rhythmDiagnosticStatusChip
            }
        }

        if canvasMode == .chordEntry {
            if !chordPreviewState.isEmpty {
                chordDraftActiveToolActions
                chordDiagnosticStatusChip
            }
        }

        if canvasMode == .textEdit {
            textActiveToolActions
        }
    }

    private var activeToolContextLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(canvasMode.activeToolTitle, systemImage: canvasMode.activeToolSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)

            if let instruction = activeToolInstructionText {
                Text(instruction)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private var activeToolInstructionText: String? {
        if canvasMode == .repeatEdit {
            if pendingRepeatStartMeasureID != nil {
                return "Tap the last measure, then end the repeat."
            }
            if let pendingEndingType {
                return "Tap the last measure, then end \(endingToolTitle(for: pendingEndingType))."
            }
        }
        if canvasMode == .measureEdit,
           pendingDeleteStartMeasureID != nil {
            return "Tap the last measure, then finish the range delete."
        }
        return canvasMode.activeToolInstruction
    }

    private var activeToolDoneButton: some View {
        Button(action: handleActiveToolDoneTapped) {
            Label("Done", systemImage: "checkmark")
        }
        .buttonStyle(ActiveToolDoneButtonStyle())
        .fixedSize()
        .accessibilityLabel("Done")
        .tourActionHighlight(
            isActive: isEditorGuidedTourDoneActionHighlighted,
            cornerRadius: 10,
            tint: EditorToolAccent.semanticRead
        )
    }

    private func selectedRenderedEditActionTray(minWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                selectedRenderedEditLabel

                if selectedChord != nil {
                    activeToolButton(
                        title: "Correct",
                        systemImage: "text.badge.checkmark",
                        action: handleCorrectSelectedChord
                    )

                    activeToolButton(
                        title: "Delete",
                        systemImage: "trash",
                        isDestructive: true,
                        action: deleteSelectedChord
                    )
                } else if selectedCommittedBarlineMeasureID != nil {
                    activeToolButton(
                        title: "Delete",
                        systemImage: "trash",
                        isDestructive: true,
                        isDisabled: !canDeleteSelectedCommittedChordBarline,
                        action: deleteSelectedCommittedChordBarline
                    )
                } else if selectedCueText != nil {
                    activeToolButton(
                        title: "Edit",
                        systemImage: "pencil",
                        action: handleEditSelectedCueText
                    )

                    activeToolButton(
                        title: "Larger",
                        systemImage: "plus.magnifyingglass",
                        isDisabled: !canGrowSelectedCueText
                    ) {
                        resizeSelectedCueText(by: CueText.scaleStep)
                    }

                    activeToolButton(
                        title: "Smaller",
                        systemImage: "minus.magnifyingglass",
                        isDisabled: !canShrinkSelectedCueText
                    ) {
                        resizeSelectedCueText(by: -CueText.scaleStep)
                    }

                    activeToolButton(
                        title: "Delete",
                        systemImage: "trash",
                        isDestructive: true,
                        action: deleteSelectedCueText
                    )
                } else if selectedRoadmapMarker != nil {
                    activeToolButton(
                        title: "Larger",
                        systemImage: "plus.magnifyingglass",
                        isDisabled: !canGrowSelectedRoadmapMarker
                    ) {
                        resizeSelectedRoadmapMarker(by: RoadmapObject.scaleStep)
                    }

                    activeToolButton(
                        title: "Smaller",
                        systemImage: "minus.magnifyingglass",
                        isDisabled: !canShrinkSelectedRoadmapMarker
                    ) {
                        resizeSelectedRoadmapMarker(by: -RoadmapObject.scaleStep)
                    }

                    activeToolButton(
                        title: "Delete",
                        systemImage: "trash",
                        isDestructive: true,
                        action: deleteSelectedRoadmapMarker
                    )
                } else if selectedMeasureID != nil {
                    if canRemoveSystemBreakBeforeSelectedMeasure {
                        activeToolButton(
                            title: "Join Row",
                            systemImage: "arrow.up.to.line",
                            action: handleJoinSelectedMeasureRow
                        )
                    }

                    activeToolButton(
                        title: "Even Row",
                        systemImage: "rectangle.split.3x1",
                        isDisabled: !canEvenSelectedMeasureRow,
                        action: handleEvenSelectedMeasureRow
                    )

                    activeToolButton(
                        title: "Measures",
                        systemImage: "rectangle.split.3x1",
                        action: handleSelectedMeasureActionsRequested
                    )
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .frame(minWidth: minWidth, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var selectedRenderedEditLabel: some View {
        if selectedChord != nil {
            Label("Chord", systemImage: "textformat")
                .font(.subheadline.weight(.semibold))
        } else if selectedCommittedBarlineMeasureID != nil {
            Label("Barline", systemImage: "pause")
                .font(.subheadline.weight(.semibold))
        } else if selectedCueText != nil {
            Label("Text", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
        } else if selectedRoadmapMarker != nil {
            Label("Marker", systemImage: "signpost.right")
                .font(.subheadline.weight(.semibold))
        } else if selectedMeasureID != nil {
            Label("Measure", systemImage: "rectangle.split.3x1")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var measureActiveToolActions: some View {
        HStack(spacing: 5) {
            if pendingDeleteStartMeasureID != nil {
                activeToolButton(
                    title: "Delete To",
                    systemImage: "checkmark.circle",
                    isSelected: true,
                    isDestructive: true,
                    isTourHighlighted: editorGuidedTourStep == .shapeForm,
                    isDisabled: !canDeleteThroughSelectedMeasure,
                    action: handleMeasureRangeDeleteTapped
                )

                activeToolButton(
                    title: "Cancel",
                    systemImage: "xmark.circle",
                    action: clearPendingMeasureDeleteState
                )
            } else {
                Menu {
                    Button {
                        handleAddMeasureAfterSelected()
                    } label: {
                        Label("Add One After", systemImage: "plus.square")
                    }

                    Button {
                        handleAddMeasureStackAfterSelectedRequested()
                    } label: {
                        Label("Add Multiple After…", systemImage: "square.stack.3d.up")
                    }

                    Button {
                        handleAddMeasureAtBeginning()
                    } label: {
                        Label("Add at Beginning", systemImage: "backward.end")
                    }

                    Button {
                        handleAddDoubleBarlineMeasure()
                    } label: {
                        Label("Add Double Barline", systemImage: "pause")
                    }
                } label: {
                    activeToolMenuLabel(
                        title: "Add",
                        systemImage: "plus.square",
                        isTourHighlighted: editorGuidedTourStep == .shapeForm
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        if canRemoveSystemBreakBeforeSelectedMeasure {
                            handleJoinSelectedMeasureRow()
                        } else {
                            handleNewSystemBeforeSelectedMeasure()
                        }
                    } label: {
                        Label(
                            selectedMeasureStartsJoinableRow ? "Join Row Above" : "Start New Row",
                            systemImage: selectedMeasureStartsJoinableRow
                                ? "arrow.up.to.line"
                                : "arrow.down.to.line"
                        )
                    }
                    .disabled(
                        selectedMeasureStartsJoinableRow
                            ? !canRemoveSystemBreakBeforeSelectedMeasure
                            : !canInsertSystemBreakBeforeSelectedMeasure
                    )

                    Button {
                        handleMoveSelectedMeasureToRowBelow()
                    } label: {
                        Label("Move to Row Below", systemImage: "arrow.down.to.line")
                    }
                    .disabled(!canMoveSelectedMeasureToRowBelow)

                    Button {
                        handleEvenSelectedMeasureRow()
                    } label: {
                        Label("Even Row Widths", systemImage: "rectangle.split.3x1")
                    }
                    .disabled(!canEvenSelectedMeasureRow)

                    Button {
                        handleJoinSelectedMeasure()
                    } label: {
                        Label("Merge with Next Measure", systemImage: "rectangle.compress.vertical")
                    }
                    .disabled(!canJoinSelectedMeasure)
                } label: {
                    activeToolMenuLabel(
                        title: "Layout",
                        systemImage: "rectangle.3.group",
                        isTourHighlighted: editorGuidedTourStep == .shapeForm
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    Button(role: .destructive) {
                        handleDeleteSelectedMeasure()
                    } label: {
                        Label("Delete Measure", systemImage: "trash")
                    }
                    .disabled(!canDeleteSelectedMeasure)

                    Button(role: .destructive) {
                        handleMeasureRangeDeleteTapped()
                    } label: {
                        Label("Delete Range…", systemImage: "trash.circle")
                    }
                    .disabled(!canDeleteSelectedMeasure)
                } label: {
                    activeToolMenuLabel(
                        title: "Delete",
                        systemImage: "trash",
                        isDestructive: true,
                        isTourHighlighted: editorGuidedTourStep == .shapeForm
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var repeatActiveToolActions: some View {
        HStack(spacing: 5) {
            if pendingRepeatStartMeasureID != nil {
                activeToolButton(
                    title: "End Repeat",
                    systemImage: "checkmark.circle",
                    isSelected: true,
                    isTourHighlighted: false,
                    action: handleEndRepeatHere
                )

                activeToolButton(
                    title: "Cancel",
                    systemImage: "xmark.circle",
                    action: clearPendingRepeatState
                )
            } else if let pendingEndingType {
                activeToolButton(
                    title: "End \(endingToolTitle(for: pendingEndingType))",
                    systemImage: pendingEndingType == .ending1 ? "1.circle" : "2.circle",
                    isSelected: true,
                    isTourHighlighted: false
                ) {
                    handleRepeatActiveEndingTapped(pendingEndingType)
                }

                activeToolButton(
                    title: "Cancel",
                    systemImage: "xmark.circle",
                    action: clearPendingRepeatState
                )
            } else {
                activeToolButton(
                    title: "One Bar",
                    systemImage: "repeat",
                    isTourHighlighted: false,
                    action: handleRepeatSelectedMeasure
                )

                activeToolButton(
                    title: "Start Repeat",
                    systemImage: "repeat.circle",
                    isTourHighlighted: false,
                    action: handleStartRepeatHere
                )

                activeToolButton(
                    title: "1st",
                    systemImage: "1.circle",
                    isTourHighlighted: false
                ) {
                    handleRepeatActiveEndingTapped(.ending1)
                }

                activeToolButton(
                    title: "2nd",
                    systemImage: "2.circle",
                    isTourHighlighted: false
                ) {
                    handleRepeatActiveEndingTapped(.ending2)
                }

                Menu {
                    Button(role: .destructive) {
                        handleRemoveRepeatAtSelectedMeasure()
                    } label: {
                        Label("Remove Repeat", systemImage: "trash")
                    }
                    .disabled(!canRemoveRepeatAtSelectedMeasure)

                    Button(role: .destructive) {
                        handleRemoveEndingAtSelectedMeasure()
                    } label: {
                        Label("Remove Ending", systemImage: "trash")
                    }
                    .disabled(!canRemoveEndingAtSelectedMeasure)
                } label: {
                    activeToolMenuLabel(
                        title: "Remove",
                        systemImage: "trash",
                        isDestructive: true,
                        isTourHighlighted: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var headerActiveToolActions: some View {
        HStack(spacing: 5) {
            activeToolButton(
                title: "Typed",
                systemImage: "keyboard",
                isSelected: chart.headerInputMode == .typed
            ) {
                chart.setHeaderInputMode(.typed)
                showingHeaderSheet = true
            }

            activeToolButton(
                title: "Handwritten",
                systemImage: "pencil.and.scribble",
                isSelected: chart.headerInputMode == .handwritten
            ) {
                activateHeaderWritingTool()
            }
        }
    }

    private var rhythmActiveToolActions: some View {
        HStack(spacing: 5) {
            activeToolButton(
                title: "Clear",
                systemImage: "trash",
                isDestructive: true,
                isDisabled: !canClearRenderedRhythmAtSelectedMeasure,
                action: handleClearRenderedRhythmAtSelectedMeasure
            )
        }
    }

    private var chordDraftActiveToolActions: some View {
        HStack(spacing: 5) {
            activeToolButton(
                title: chordPreviewState.requiresChordConfirmation ? "Review & Render" : "Render Chords",
                systemImage: chordPreviewState.requiresChordConfirmation ? "checkmark.message" : "checkmark.circle",
                isTourHighlighted: editorGuidedTourStep == .renderChords,
                isDisabled: !canRenderChordDrafts,
                action: handleRenderChordDrafts
            )

            activeToolButton(
                title: "Discard",
                systemImage: "xmark.circle",
                isDestructive: true,
                isDisabled: chordPreviewState.isEmpty,
                action: handleDiscardChordDrafts
            )
        }
    }

    @ViewBuilder
    private var textActiveToolActions: some View {
        if selectedCueText != nil {
            HStack(spacing: 5) {
                activeToolButton(
                    title: "Edit",
                    systemImage: "pencil",
                    action: handleEditSelectedCueText
                )

                activeToolButton(
                    title: "Larger",
                    systemImage: "plus.magnifyingglass",
                    isDisabled: !canGrowSelectedCueText
                ) {
                    resizeSelectedCueText(by: CueText.scaleStep)
                }

                activeToolButton(
                    title: "Smaller",
                    systemImage: "minus.magnifyingglass",
                    isDisabled: !canShrinkSelectedCueText
                ) {
                    resizeSelectedCueText(by: -CueText.scaleStep)
                }

                activeToolButton(
                    title: "Delete",
                    systemImage: "trash",
                    isDestructive: true,
                    action: deleteSelectedCueText
                )
            }
        } else {
            HStack(spacing: 5) {
                activeToolButton(
                    title: "Above",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    isTourHighlighted: editorGuidedTourStep == .addCue,
                    isDisabled: resolvedMeasureActionTargetID() == nil
                ) {
                    handleAddCueText(position: .above)
                }

                activeToolButton(
                    title: "Below",
                    systemImage: "text.line.last.and.arrowtriangle.forward",
                    isDisabled: resolvedMeasureActionTargetID() == nil
                ) {
                    handleAddCueText(position: .below)
                }

                activeToolButton(
                    title: "Remove",
                    systemImage: "trash",
                    isDestructive: true,
                    isDisabled: !canRemoveCueTextAtSelectedMeasure,
                    action: handleRemoveCueTextsAtSelectedMeasure
                )
            }
        }
    }

    private var canRenderChordDrafts: Bool {
        chordPreviewState.canRenderAny && chordPreviewState.unresolvedChordCount == 0
    }

    private func handleActiveToolDoneTapped() {
        let completedStep = editorGuidedTourStep
        activateSelectTool()

        guard let completedStep else {
            return
        }

        switch completedStep {
        case .review:
            completeEditorGuidedTourStep(completedStep)
        default:
            break
        }
    }

    private func activeToolButton(
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        isDestructive: Bool = false,
        isTourHighlighted: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let selectedBackgroundColor = isDestructive
            ? Color.red
            : Color(red: 0.16, green: 0.38, blue: 0.82)

        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
                .foregroundStyle(
                    isSelected
                    ? Color.white
                    : (isDestructive ? Color.red : Color.primary)
                )
                .background(
                    isSelected
                    ? selectedBackgroundColor
                    : Color(uiColor: .tertiarySystemBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(title)
        .tourActionHighlight(
            isActive: isTourHighlighted && !isDisabled,
            cornerRadius: 9,
            tint: isDestructive ? .red : Color(red: 0.16, green: 0.38, blue: 0.82)
        )
    }

    private func activeToolMenuLabel(
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        isDestructive: Bool = false,
        isTourHighlighted: Bool = false
    ) -> some View {
        let selectedBackgroundColor = isDestructive
            ? Color.red
            : Color(red: 0.16, green: 0.38, blue: 0.82)

        return Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
            .foregroundStyle(
                isSelected
                    ? Color.white
                    : (isDestructive ? Color.red : Color.primary)
            )
            .background(
                isSelected
                    ? selectedBackgroundColor
                    : Color(uiColor: .tertiarySystemBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .tourActionHighlight(
                isActive: isTourHighlighted,
                cornerRadius: 9,
                tint: isDestructive ? .red : Color(red: 0.16, green: 0.38, blue: 0.82)
            )
    }

    private var isMeasureDeleteContinuationActive: Bool {
        pendingDeleteStartMeasureID != nil
    }

    private var isRepeatContinuationActive: Bool {
        pendingRepeatStartMeasureID != nil || pendingEndingStartMeasureID != nil
    }

    private func pendingEndingButtonTitle(for type: RoadmapType) -> String {
        pendingEndingType == type ? "End \(endingToolTitle(for: type))" : endingToolTitle(for: type)
    }

    private func endingToolTitle(for type: RoadmapType) -> String {
        switch type {
        case .ending1:
            return "1st"
        case .ending2:
            return "2nd"
        default:
            return type.defaultDisplayText
        }
    }

    private func isEndingButtonDisabled(for type: RoadmapType) -> Bool {
        guard pendingEndingType != nil else {
            return false
        }

        return pendingEndingType != type
    }

    @ViewBuilder
    private var canvasView: some View {
        LeadSheetCanvasHostView(
            chart: $chart,
            selectedMeasureID: $selectedMeasureID,
            selectedNoteSelection: $selectedNoteSelection,
            selectedChordID: $selectedChordID,
            selectedCommittedBarlineMeasureID: $selectedCommittedBarlineMeasureID,
            selectedCueTextID: $selectedCueTextID,
            selectedRoadmapMarkerID: $selectedRoadmapMarkerID,
            interactionMode: canvasMode,
            inkToolMode: inkToolMode,
            recognizesChordInk: true,
            chordPreviewState: chordPreviewState,
            onTimeSignatureTargetRequested: handleTimeSignatureTargetRequested,
            onChordInkRecognitionProposal: handleChordInkRecognitionProposal,
            onChordInkBatchRecognitionProposal: handleChordInkBatchRecognitionProposal,
            onChordInkDraftPreviewChanged: handleChordInkDraftPreviewChanged,
            onChordInkDraftBarlinesChanged: handleChordInkDraftBarlinesChanged,
            onChordCorrectionRequested: handleChordCorrectionRequested,
            onNoteSelectionChanged: handleNoteSelectionChanged,
            onMeasureSelectedFromCanvas: handleMeasureSelectedFromCanvas,
            onChordSelectedFromCanvas: handleChordSelectedFromCanvas,
            onCueTextSelectedFromCanvas: handleCueTextSelectedFromCanvas,
            onCueTextEditRequested: handleCueTextEditRequestedFromCanvas,
            onRoadmapMarkerSelectedFromCanvas: handleRoadmapMarkerSelectedFromCanvas,
            onRepeatSpanSelectedFromCanvas: handleRepeatSpanSelectedFromCanvas,
            onEndingSpanSelectedFromCanvas: handleEndingSpanSelectedFromCanvas,
            onTimeSignatureSelectedFromCanvas: handleTimeSignatureSelectedFromCanvas,
            onHeaderAuthoringRequested: handleHeaderAuthoringRequestedFromCanvas,
            chordDraftRenderInvalidationRequestID: chordDraftRenderInvalidationRequestID,
            rhythmicNotationPreviewConfirmationRequestID: isDedicatedRhythmToolAvailable
                ? rhythmPreviewConfirmationRequestID
                : nil,
            onRhythmicNotationPreviewChanged: isDedicatedRhythmToolAvailable
                ? handleRhythmicNotationPreviewChanged
                : nil
        )
        .onAppear {
            guard !didRecordFirstCanvasAppear else {
                return
            }

            didRecordFirstCanvasAppear = true
            IChartPerformanceTrace.record(
                "editor.canvas.firstAppear",
                metadata: editorPerformanceTraceMetadata
            )
        }
    }

    private var editorPerformanceTraceMetadata: [String: String] {
        [
            "layoutStyle": chart.layoutStyle.rawValue,
            "completedSetup": chart.hasCompletedInitialSetup ? "true" : "false",
            "measureCount": "\(chart.measures.count)",
            "canvasMode": canvasMode.activeToolTitle,
            "inkToolMode": inkToolMode.rawValue,
            "chordToolInputMode": "draftPreview"
        ]
    }

    private var rhythmDiagnosticStatusChip: some View {
        let preview = latestRhythmPreview
        let tint = preview?.canConfirm == true
            ? Color.orange
            : Color(red: 0.16, green: 0.38, blue: 0.82)

        return HStack(spacing: 8) {
            Image(systemName: preview?.canConfirm == true ? "questionmark.circle.fill" : "waveform.path.ecg")
                .font(.caption.weight(.bold))
                .frame(width: 15)

            RhythmDiagnosticPreviewStrip(
                values: preview?.values ?? [],
                meter: preview?.meter ?? chart.defaultMeter,
                tieOutSlotIndices: preview?.tieOutSlotIndices ?? []
            )

            if let preview {
                if preview.canConfirm {
                    HStack(spacing: 7) {
                        Text("Is this correct?")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)

                        Button {
                            latestRhythmPreview = nil
                            rhythmPreviewConfirmationRequestID = UUID()
                        } label: {
                            Text("Confirm")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .foregroundStyle(Color.white)
                                .background(tint)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: RhythmDiagnosticPreviewMetrics.statusWidth, alignment: .leading)
                } else if preview.isCertain {
                    Text("Tap outside measure to render")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .frame(width: RhythmDiagnosticPreviewMetrics.statusWidth, alignment: .leading)
                } else {
                    Text("Reading")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: RhythmDiagnosticPreviewMetrics.statusWidth, alignment: .leading)
                }
            } else {
                Text("Waiting for ink")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(width: RhythmDiagnosticPreviewMetrics.statusWidth, alignment: .leading)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 50)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(rhythmPreviewAccessibilityLabel)
    }

    private var rhythmPreviewAccessibilityLabel: String {
        guard let preview = latestRhythmPreview,
              !preview.values.isEmpty else {
            return "Rhythm preview, waiting for ink"
        }

        let statusText = preview.canConfirm
            ? "needs confirmation"
            : preview.isCertain ? "ready to render" : "reading"
        return "Rhythm preview, \(preview.values.map(\.displayText).joined(separator: ", ")), \(statusText)"
    }

    private var chordDiagnosticStatusChip: some View {
        let isReady = canRenderChordDrafts
        let hasDrafts = !chordPreviewState.isEmpty
        let needsReview = chordPreviewState.requiresChordConfirmation
        let tint = hasDrafts && (!isReady || needsReview)
            ? Color.orange
            : Color(red: 0.16, green: 0.38, blue: 0.82)

        return HStack(spacing: 8) {
            Image(
                systemName: needsReview
                    ? "exclamationmark.bubble.fill"
                    : isReady ? "checkmark.circle.fill" : "waveform.path.ecg"
            )
                .font(.caption.weight(.bold))
                .frame(width: 15)

            ChordDiagnosticPreviewStrip(
                items: chordDiagnosticPreviewItems
            )

            Text(chordPreviewStatusText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .frame(width: ChordDiagnosticPreviewMetrics.statusWidth, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 50)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(chordPreviewAccessibilityLabel)
    }

    private var chordDiagnosticPreviewItems: [ChordDiagnosticPreviewItem] {
        let chordItems = chordPreviewState.draftChords.map { draft in
            ChordDiagnosticPreviewItem(
                id: "chord-\(draft.id.uuidString)",
                visualOrder: draft.visualOrder ?? Double(draft.measureIndex) + (draft.targetFraction ?? 0),
                kind: .chord(draft.previewText ?? "?")
            )
        }
        let barlineItems = chordPreviewState.draftBarlines.map { barline in
            ChordDiagnosticPreviewItem(
                id: "barline-\(barline.id.uuidString)",
                visualOrder: barline.visualOrder,
                kind: .barline
            )
        }
        let implicitBarlineItems = ChordDraftPreviewImplicitBarlinePolicy
            .terminalBarlines(for: chordPreviewState, chart: chart)
            .map { barline in
                ChordDiagnosticPreviewItem(
                    id: "implicit-barline-\(barline.id)",
                    visualOrder: barline.visualOrder,
                    kind: .barline
                )
            }

        return (chordItems + barlineItems + implicitBarlineItems).sorted { lhs, rhs in
            if lhs.visualOrder == rhs.visualOrder {
                return lhs.id < rhs.id
            }

            return lhs.visualOrder < rhs.visualOrder
        }
    }

    private var chordPreviewStatusText: String {
        guard !chordPreviewState.isEmpty else {
            return "Waiting for ink"
        }

        if canRenderChordDrafts {
            return chordPreviewState.requiresChordConfirmation
                ? "Review before render"
                : "Ready to render"
        }

        return "Previewing"
    }

    private var chordPreviewAccessibilityLabel: String {
        guard !chordPreviewState.isEmpty else {
            return "Chord preview, waiting for ink"
        }

        let chordText = chordPreviewState.draftChords
            .map { $0.previewText ?? "unresolved" }
            .joined(separator: ", ")
        let barlineText = chordPreviewState.draftBarlines.isEmpty
            ? "no draft barlines"
            : "\(chordPreviewState.draftBarlines.count) draft barlines"
        return "Chord preview, \(chordText), \(barlineText), \(chordPreviewStatusText)"
    }

    private func exitEditor() {
        if let onExit {
            onExit()
        }
        dismiss()
    }

    private var exportButtonTitle: String {
        "Export PDF"
    }

    private func handleAddPageTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        activateSelectTool(clearsMeasureSelection: true)
        runEditorOperation("Adding page...") {
            selectedMeasureID = chart.appendPage()
        }
    }

    private func handleExportTapped() {
        let chartToExport = chart
        isExporting = true
        let exportStartedAt = Date()
        IChartTelemetry.record(
            "pdf.export_started",
            properties: [
                "layout_style": .string(chartToExport.layoutStyle.rawValue),
                "measure_count": .int(chartToExport.measures.count),
                "mode": .string(canvasMode.telemetryValue)
            ]
        )

        Task {
            do {
                let exportedPDF = try await exporter.exportPDF(for: chartToExport)
                try await MainActor.run {
                    let libraryPDF = try pdfLibraryStore.save(exportedPDF, source: .chartExport)
                    activeSheet = .export(libraryPDF)
                    isExporting = false
                    completeEditorGuidedTourStep(.export)
                    IChartTelemetry.record(
                        "pdf.export_succeeded",
                        properties: [
                            "layout_style": .string(chartToExport.layoutStyle.rawValue),
                            "measure_count": .int(chartToExport.measures.count),
                            "page_count": .int(exportedPDF.pageCount),
                            "pdf_size_bucket": .string(Self.pdfSizeBucket(exportedPDF.fileSizeBytes)),
                            "duration_ms": .double(Date().timeIntervalSince(exportStartedAt) * 1_000)
                        ]
                    )
                }
            } catch {
                await MainActor.run {
                    exportAlertMessage = "Couldn’t generate the PDF right now. \(error.localizedDescription)"
                    showingExportAlert = true
                    isExporting = false
                    IChartTelemetry.record(
                        "pdf.export_failed",
                        properties: [
                            "layout_style": .string(chartToExport.layoutStyle.rawValue),
                            "measure_count": .int(chartToExport.measures.count),
                            "duration_ms": .double(Date().timeIntervalSince(exportStartedAt) * 1_000),
                            "error_code": .string("export_error")
                        ]
                    )
                }
            }
        }
    }

    private var allowsUserFacingRhythmNoteEditing: Bool {
        RhythmRecognitionOverhaulGate.shipsDedicatedRhythmTool
            && chart.layoutStyle.profile.allowsUserFacingRhythmNoteEditing
    }

    private var selectedRhythmActionMeasureID: UUID? {
        selectedNoteSelection?.measureID ?? selectedMeasureID
    }

    private var canClearRenderedRhythmAtSelectedMeasure: Bool {
        guard isDedicatedRhythmToolAvailable,
              let measureID = selectedRhythmActionMeasureID,
              let measure = chart.measure(id: measureID) else {
            return false
        }

        return measure.rhythmMap != nil || measure.handwrittenRhythmicNotationData != nil
    }

    private static func pdfSizeBucket(_ byteCount: Int) -> String {
        switch byteCount {
        case ..<100_000:
            return "lt_100kb"
        case ..<500_000:
            return "100kb_500kb"
        case ..<1_000_000:
            return "500kb_1mb"
        case ..<5_000_000:
            return "1mb_5mb"
        default:
            return "gt_5mb"
        }
    }

    private static func chordTelemetryProperties(
        confirmation: PendingChordInkConfirmation,
        resolution: ChordEntryDiagnosticResolution,
        errorCode: String? = nil
    ) -> IChartTelemetryProperties {
        var properties = chordTelemetryProperties(
            result: confirmation.result,
            candidateCount: confirmation.candidateTexts.count,
            decision: confirmation.decision,
            timing: confirmation.recognitionTiming,
            flow: .tapToConfirm
        )
        properties["decision"] = .string(resolution.rawValue)
        properties["result"] = .string(errorCode == nil ? "committed" : "failed")
        if let errorCode {
            properties["error_code"] = .string(errorCode)
        }
        return properties
    }

    private static func chordTelemetryProperties(
        result: ChordInkRecognitionResult,
        candidateCount: Int,
        decision: ChordInkRecognitionDecision,
        timing: ChordInkRecognitionTiming?,
        flow: ChordInkRecognitionFlow
    ) -> IChartTelemetryProperties {
        var properties: IChartTelemetryProperties = [
            "candidate_count": .int(candidateCount),
            "confidence_bucket": .string(confidenceBucket(result.confidence)),
            "decision": .string(decision.action.rawValue),
            "flow": .string(flow.telemetryValue),
            "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
            "review_candidate_count": .int(result.reviewCandidateScores.count),
            "render_action": .string(decision.action.rawValue),
            "result": .string(result.match == nil ? "unmatched" : "matched"),
            "stroke_count": .int(result.metrics.strokeCount)
        ]

        if let timing {
            properties["recognition_ms"] = .double(timing.recognitionMilliseconds)
        }

        if let evidence = result.trustEvidence {
            properties["trust_outcome"] = .string(evidence.outcome.rawValue)
            properties["trust_probe_count"] = .int(evidence.completedProbeCount)
            properties["trust_symbol_support_count"] = .int(evidence.symbolSupportCount)
            properties["trust_validation_ms"] = .double(evidence.validationMilliseconds)
        }

        return properties
    }

    private static func chordDraftPreviewTelemetryProperties(
        payloads: [ChordInkRecognitionProposalPayload],
        inputs: [ChordInkDraftInput],
        updatedState: ChordPreviewState,
        layoutStyle: String
    ) -> IChartTelemetryProperties {
        let decisions = payloads.map { ChordInkRecognitionPolicy.decision(for: $0.result) }
        let matchedCount = payloads.filter { $0.result.match != nil }.count
        let noReadCount = payloads.count - matchedCount
        let trustedCount = decisions.filter { $0.action == .trusted && $0.acceptedText != nil }.count
        let confirmCount = decisions.filter { $0.action == .confirm }.count
        let closeRaceCount = decisions.filter(\.isCloseRace).count
        let generatedSequenceLimitCount = payloads.filter {
            $0.result.metrics.compositionMetrics.hitGeneratedSequenceLimit
        }.count
        let issueBuckets = ChordInkPreviewIssueBucketPolicy.counts(
            results: payloads.map(\.result),
            decisions: decisions,
            barlineCount: updatedState.draftBarlines.count
        )
        let matchedConfidences = payloads.compactMap { payload -> Double? in
            payload.result.match == nil ? nil : payload.result.confidence
        }
        let recognitionMilliseconds = payloads.reduce(0) { partialResult, payload in
            partialResult + payload.timing.recognitionMilliseconds
        }
        let trustEvidence = payloads.compactMap(\.result.trustEvidence)
        let trustCorroboratedCount = trustEvidence.filter(\.isCorroborated).count
        let trustRejectedCount = trustEvidence.count - trustCorroboratedCount

        var properties: IChartTelemetryProperties = [
            "batch_size": .int(payloads.count),
            "barline_count": .int(updatedState.draftBarlines.count),
            "barline_sequence_issue_count": .int(issueBuckets.barlineSequenceIssueCount),
            "candidate_count": .int(inputs.reduce(0) { $0 + $1.candidateTexts.count }),
            "candidate_limit_issue_count": .int(issueBuckets.candidateLimitIssueCount),
            "close_race_count": .int(closeRaceCount),
            "cluster_count": .int(payloads.reduce(0) { $0 + $1.result.metrics.clusterCount }),
            "confirm_count": .int(confirmCount),
            "decision": .string(previewDecisionSummary(
                totalCount: payloads.count,
                trustedCount: trustedCount,
                confirmCount: confirmCount,
                noReadCount: noReadCount
            )),
            "draft_count": .int(updatedState.draftChords.count),
            "flow": .string(ChordInkRecognitionFlow.draftPreview.telemetryValue),
            "generated_sequence_limit_count": .int(generatedSequenceLimitCount),
            "alteration_issue_count": .int(issueBuckets.alterationIssueCount),
            "dim_quality_issue_count": .int(issueBuckets.dimQualityIssueCount),
            "extension_issue_count": .int(issueBuckets.extensionIssueCount),
            "issue_count": .int(issueBuckets.issueCount),
            "layout_style": .string(layoutStyle),
            "matched_count": .int(matchedCount),
            "no_read_count": .int(noReadCount),
            "quality_issue_count": .int(issueBuckets.qualityIssueCount),
            "raw_candidate_count": .int(payloads.reduce(0) { $0 + $1.result.rawCandidates.count }),
            "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
            "recognition_target_count": .int(payloads.count),
            "review_candidate_count": .int(payloads.reduce(0) {
                $0 + $1.result.reviewCandidateScores.count
            }),
            "result": .string(previewResultSummary(
                totalCount: payloads.count,
                matchedCount: matchedCount,
                noReadCount: noReadCount
            )),
            "root_accidental_issue_count": .int(issueBuckets.rootAccidentalIssueCount),
            "root_issue_count": .int(issueBuckets.rootIssueCount),
            "slash_bass_issue_count": .int(issueBuckets.slashBassIssueCount),
            "stroke_count": .int(inputs.reduce(0) { $0 + $1.strokeCount }),
            "triangle_quality_issue_count": .int(issueBuckets.triangleQualityIssueCount),
            "trust_corroborated_count": .int(trustCorroboratedCount),
            "trust_probe_count": .int(trustEvidence.reduce(0) { $0 + $1.completedProbeCount }),
            "trust_rejected_count": .int(trustRejectedCount),
            "trust_validation_ms": .double(trustEvidence.reduce(0) { $0 + $1.validationMilliseconds }),
            "trusted_count": .int(trustedCount),
            "unknown_issue_count": .int(issueBuckets.unknownIssueCount),
            "unresolved_count": .int(updatedState.unresolvedChordCount)
        ]

        if recognitionMilliseconds > 0 {
            properties["recognition_ms"] = .double(recognitionMilliseconds)
        }

        if let minimumMatchedConfidence = matchedConfidences.min() {
            properties["confidence_bucket"] = .string(confidenceBucket(minimumMatchedConfidence))
        }

        return properties
    }

    private static func previewDecisionSummary(
        totalCount: Int,
        trustedCount: Int,
        confirmCount: Int,
        noReadCount: Int
    ) -> String {
        guard totalCount > 0 else {
            return "none"
        }

        if noReadCount == totalCount {
            return "no_read"
        }

        if trustedCount == totalCount {
            return "trusted"
        }

        if confirmCount == totalCount {
            return "confirm"
        }

        return "mixed"
    }

    private static func previewResultSummary(
        totalCount: Int,
        matchedCount: Int,
        noReadCount: Int
    ) -> String {
        guard totalCount > 0 else {
            return "empty"
        }

        if matchedCount == totalCount {
            return "matched"
        }

        if noReadCount == totalCount {
            return "unmatched"
        }

        return "partial"
    }

    private static func confidenceBucket(_ confidence: Double) -> String {
        switch confidence {
        case ..<1:
            return "lt_1"
        case ..<2:
            return "1_2"
        case ..<3:
            return "2_3"
        case ..<4:
            return "3_4"
        default:
            return "gte_4"
        }
    }

    private var canRemoveRepeatAtSelectedMeasure: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return !chart.repeatSpanIDs(attachedTo: targetMeasureID).isEmpty
    }

    private var canRemoveEndingAtSelectedMeasure: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return !chart.endingSpanIDs(attachedTo: targetMeasureID).isEmpty
    }

    private var canInsertSystemBreakBeforeSelectedMeasure: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return chart.canInsertSystemBreak(before: targetMeasureID)
    }

    private var canRemoveSystemBreakBeforeSelectedMeasure: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return chart.measureIDsForJoiningRow(startingAt: targetMeasureID) != nil
            && !joinRowEqualizedManualWidths(startingAt: targetMeasureID).isEmpty
    }

    private var selectedMeasureStartsJoinableRow: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return chart.measureIDsForJoiningRow(startingAt: targetMeasureID) != nil
    }

    private var canMoveSelectedMeasureToRowBelow: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return moveMeasureToRowBelowPlan(for: targetMeasureID) != nil
    }

    private var canRemoveCueTextAtSelectedMeasure: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return !chart.cueTextIDs(attachedTo: targetMeasureID).isEmpty
    }

    private var selectedCueText: CueText? {
        selectedCueTextID.flatMap { chart.cueText(id: $0) }
    }

    private var selectedRoadmapMarker: RoadmapObject? {
        selectedRoadmapMarkerID.flatMap { chart.roadmapObject(id: $0) }
    }

    private var selectedChord: ChordEvent? {
        selectedChordID.flatMap { chart.chordEvent(id: $0) }
    }

    private var canDeleteSelectedCommittedChordBarline: Bool {
        guard let selectedCommittedBarlineMeasureID else {
            return false
        }

        return chart.canDeleteCommittedSimpleChordBarline(after: selectedCommittedBarlineMeasureID)
    }

    private var canShrinkSelectedCueText: Bool {
        guard let selectedCueText else {
            return false
        }

        return selectedCueText.scale > CueText.minimumScale
    }

    private var canGrowSelectedCueText: Bool {
        guard let selectedCueText else {
            return false
        }

        return selectedCueText.scale < CueText.maximumScale
    }

    private var canShrinkSelectedRoadmapMarker: Bool {
        guard let selectedRoadmapMarker else {
            return false
        }

        return selectedRoadmapMarker.resolvedScale > RoadmapObject.minimumScale
    }

    private var canGrowSelectedRoadmapMarker: Bool {
        guard let selectedRoadmapMarker else {
            return false
        }

        return selectedRoadmapMarker.resolvedScale < RoadmapObject.maximumScale
    }

    private var canDeleteSelectedMeasure: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return chart.canDeleteMeasure(id: targetMeasureID)
    }

    private var canDeleteThroughSelectedMeasure: Bool {
        guard let pendingDeleteStartMeasureID,
              let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return chart.canDeleteMeasures(from: pendingDeleteStartMeasureID, through: targetMeasureID)
    }

    private var canEvenSelectedMeasureRow: Bool {
        guard chart.layoutStyle == .simpleChordSheet || chart.layoutStyle == .rhythmSectionSheet,
              let targetMeasureID = resolvedMeasureActionTargetID() else {
            return false
        }

        return renderedMeasureRowIDs(containing: targetMeasureID).count > 1
    }

    private var canJoinSelectedMeasure: Bool {
        guard let targetMeasureID = resolvedMeasureActionTargetID(),
              chart.canJoinMeasure(after: targetMeasureID) else {
            return false
        }

        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: latestEditorContentSize
        )
        return pageLayout.systems.contains { system in
            let measureIDs = system.measures.compactMap(\.sourceMeasureID)
            guard let selectedIndex = measureIDs.firstIndex(of: targetMeasureID) else {
                return false
            }

            return measureIDs.indices.contains(selectedIndex + 1)
        }
    }

    @discardableResult
    private func enterMeasureEditMode() -> Bool {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return false
        }

        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        clearPendingRepeatState()
        if selectedMeasureID == nil {
            selectedMeasureID = chart.resolvedAuthoringMeasureID()
        }
        canvasMode = .measureEdit
        return true
    }

    private func handleMeasureEditRequested() {
        if canvasMode == .measureEdit {
            activateSelectTool()
            return
        }

        _ = enterMeasureEditMode()
    }

    private func handleSelectedMeasureActionsRequested() {
        guard selectedMeasureID != nil else {
            return
        }

        _ = enterMeasureEditMode()
    }

    private func handleEvenSelectedMeasureRow() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              chart.layoutStyle == .simpleChordSheet || chart.layoutStyle == .rhythmSectionSheet,
              let targetMeasureID else {
            return
        }

        let equalizedWidths = measureRowEqualizedManualWidths(containing: targetMeasureID)
        guard equalizedWidths.count > 1 else {
            return
        }

        var didUpdate = false
        for (measureID, width) in equalizedWidths {
            didUpdate = chart.setMeasureManualLayoutWidth(width, for: measureID) != nil || didUpdate
        }

        if didUpdate {
            selectedMeasureID = targetMeasureID
        }
    }

    private func handleJoinSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              let targetMeasureID,
              canJoinSelectedMeasure,
              chart.joinMeasure(after: targetMeasureID) else {
            return
        }

        clearPendingMeasureStackState()
        selectedMeasureID = targetMeasureID
    }

    private func renderedMeasureRowIDs(containing measureID: UUID) -> [UUID] {
        guard chart.layoutStyle == .simpleChordSheet || chart.layoutStyle == .rhythmSectionSheet else {
            return []
        }

        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: latestEditorContentSize
        )
        return pageLayout.systems
            .first { system in
                system.measures.contains { $0.sourceMeasureID == measureID }
            }?
            .measures
            .compactMap(\.sourceMeasureID)
            ?? []
    }

    private func measureRowEqualizedManualWidths(containing measureID: UUID) -> [UUID: CGFloat] {
        guard chart.layoutStyle == .simpleChordSheet || chart.layoutStyle == .rhythmSectionSheet else {
            return [:]
        }

        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: latestEditorContentSize
        )
        guard let system = pageLayout.systems.first(where: { system in
            system.measures.contains { $0.sourceMeasureID == measureID }
        }) else {
            return [:]
        }

        switch chart.layoutStyle {
        case .simpleChordSheet:
            return LeadSheetSimpleChordRowEqualizationPolicy.manualLayoutWidths(
                for: system,
                in: pageLayout,
                chart: chart
            )
        case .rhythmSectionSheet:
            return LeadSheetRhythmSectionRowEqualizationPolicy.manualLayoutWidths(
                for: system,
                in: pageLayout,
                chart: chart
            )
        case .leadSheet:
            return [:]
        }
    }

    private func joinRowEqualizedManualWidths(startingAt measureID: UUID) -> [UUID: CGFloat] {
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: latestEditorContentSize
        )
        return LeadSheetJoinRowEqualizationPolicy.manualLayoutWidths(
            startingAt: measureID,
            in: pageLayout,
            chart: chart
        )
    }

    private func moveMeasureToRowBelowPlan(
        for measureID: UUID
    ) -> LeadSheetMoveMeasureToRowBelowPlan? {
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: latestEditorContentSize
        )
        return LeadSheetMoveMeasureToRowBelowPolicy.plan(
            for: measureID,
            in: pageLayout,
            chart: chart
        )
    }

    @discardableResult
    private func enterRepeatEditMode() -> Bool {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return false
        }

        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        if selectedMeasureID == nil {
            selectedMeasureID = chart.resolvedAuthoringMeasureID()
        }
        canvasMode = .repeatEdit
        return true
    }

    private func handleRepeatToolTapped() {
        if canvasMode == .repeatEdit {
            activateSelectTool()
            return
        }

        _ = enterRepeatEditMode()
    }

    private func handleAddMeasureAtBeginning() {
        guard enterMeasureEditMode() else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = chart.insertMeasureAtBeginning()
        completeEditorGuidedTourStep(.shapeForm)
    }

    private func handleAddMeasureAfterSelected() {
        handleAddMeasureAfterSelected(barlineAfter: .single)
    }

    private func handleAddMeasureStackAfterSelectedRequested() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              let targetMeasureID else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
        pendingMeasureStackInsertion = PendingMeasureStackInsertion(anchorMeasureID: targetMeasureID)
    }

    private func handleMeasureStackInsertionAccepted(
        _ measureCount: Int,
        insertion: PendingMeasureStackInsertion
    ) {
        let normalizedMeasureCount = min(max(measureCount, 1), 64)
        guard enterMeasureEditMode(),
              chart.measure(id: insertion.anchorMeasureID) != nil else {
            pendingMeasureStackInsertion = nil
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        if chart.measure(id: insertion.anchorMeasureID)?.authoringState == .open {
            _ = chart.commitOpenMeasure()
        }
        guard let insertedMeasureIDs = chart.insertMeasures(
            after: insertion.anchorMeasureID,
            count: normalizedMeasureCount
        ) else {
            pendingMeasureStackInsertion = nil
            return
        }

        pendingMeasureStackInsertion = nil
        selectedMeasureID = insertedMeasureIDs.last ?? insertion.anchorMeasureID
        completeEditorGuidedTourStep(.shapeForm)
    }

    private func handleAddDoubleBarlineMeasure() {
        handleAddMeasureAfterSelected(barlineAfter: .double)
    }

    private func handleAddMeasureAfterSelected(barlineAfter: BarlineType) {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode() else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        guard let targetMeasureID else {
            selectedMeasureID = chart.appendMeasure(barlineAfter: barlineAfter)
            return
        }

        if chart.measure(id: targetMeasureID)?.authoringState == .open {
            selectedMeasureID = chart.commitOpenMeasure(barlineAfter: barlineAfter)
        } else {
            selectedMeasureID = chart.insertMeasure(after: targetMeasureID, barlineAfter: barlineAfter)
        }

        switch barlineAfter {
        case .single:
            completeEditorGuidedTourStep(.shapeForm)
        case .double:
            completeEditorGuidedTourStep(.shapeForm)
        case .final:
            break
        }
    }

    private func handleDeleteSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        let nextSelectionID = targetMeasureID.flatMap(neighboringSelectionAfterDeletingMeasure)
        guard enterMeasureEditMode(),
              let targetMeasureID,
              chart.deleteMeasure(id: targetMeasureID) else {
            return
        }

        clearPendingMeasureStackState()
        selectedMeasureID = nextSelectionID.flatMap { chart.measure(id: $0)?.id }
            ?? chart.resolvedAuthoringMeasureID()
        completeEditorGuidedTourStep(.shapeForm)
    }

    private func handleStartDeleteRangeHere() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              let targetMeasureID else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = targetMeasureID
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
    }

    private func handleDeleteThroughHere() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        let nextSelectionID = pendingDeleteStartMeasureID.flatMap { startID in
            targetMeasureID.flatMap { endID in
                neighboringSelectionAfterDeletingMeasureRange(startMeasureID: startID, endMeasureID: endID)
            }
        }
        guard enterMeasureEditMode(),
              let pendingDeleteStartMeasureID,
              let targetMeasureID,
              chart.deleteMeasures(from: pendingDeleteStartMeasureID, through: targetMeasureID) else {
            return
        }

        clearPendingMeasureStackState()
        selectedMeasureID = nextSelectionID.flatMap { chart.measure(id: $0)?.id }
            ?? chart.resolvedAuthoringMeasureID()
        completeEditorGuidedTourStep(.shapeForm)
    }

    private func handleNewSystemBeforeSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              let targetMeasureID,
              chart.insertSystemBreak(before: targetMeasureID) else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
        completeEditorGuidedTourStep(.shapeForm)
    }

    private func handleJoinSelectedMeasureRow() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              let targetMeasureID,
              chart.joinRow(
                startingAt: targetMeasureID,
                equalizedManualWidths: joinRowEqualizedManualWidths(startingAt: targetMeasureID)
              ) else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
        completeEditorGuidedTourStep(.shapeForm)
    }

    private func handleMoveSelectedMeasureToRowBelow() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              let targetMeasureID,
              let plan = moveMeasureToRowBelowPlan(for: targetMeasureID),
              chart.moveMeasureToRowBelow(
                targetMeasureID,
                nextRowStartingAt: plan.nextRowFirstMeasureID,
                equalizedManualWidths: plan.equalizedManualWidths
              ) else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
        completeEditorGuidedTourStep(.shapeForm)
    }

    private func handleMeasureRangeDeleteTapped() {
        if pendingDeleteStartMeasureID == nil {
            handleStartDeleteRangeHere()
        } else {
            handleDeleteThroughHere()
        }
    }

    private func clearPendingMeasureDeleteState() {
        pendingDeleteStartMeasureID = nil
    }

    private func handleRepeatSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterRepeatEditMode(),
              let targetMeasureID,
              chart.addRepeatSpan(startMeasureID: targetMeasureID, endMeasureID: targetMeasureID) != nil else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
    }

    private func handleStartRepeatHere() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterRepeatEditMode(),
              let targetMeasureID else {
            return
        }

        pendingRepeatStartMeasureID = targetMeasureID
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
    }

    private func handleEndRepeatHere() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterRepeatEditMode(),
              let repeatStartMeasureID = pendingRepeatStartMeasureID,
              let targetMeasureID,
              let orderedBoundaryIDs = orderedRepeatBoundaryIDs(
                startMeasureID: repeatStartMeasureID,
                endMeasureID: targetMeasureID
              ),
              chart.addRepeatSpan(
                startMeasureID: orderedBoundaryIDs.start,
                endMeasureID: orderedBoundaryIDs.end
              ) != nil else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
    }

    private func handleRemoveRepeatAtSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterRepeatEditMode(),
              let targetMeasureID,
              chart.deleteRepeatSpans(attachedTo: targetMeasureID) > 0 else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
    }

    private func handleRepeatActiveEndingTapped(_ type: RoadmapType) {
        if pendingEndingType == type {
            handleEndEndingHere()
        } else {
            handleStartEndingHere(type)
        }
    }

    private func clearPendingRepeatState() {
        pendingRepeatStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
    }

    private func handleEndingSelectedMeasure(_ type: RoadmapType) {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard type.isEnding,
              enterRepeatEditMode(),
              let targetMeasureID,
              chart.addEndingSpan(type, startMeasureID: targetMeasureID, endMeasureID: targetMeasureID) != nil else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
    }

    private func handleStartEndingHere(_ type: RoadmapType) {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard type.isEnding,
              enterRepeatEditMode(),
              let targetMeasureID else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = targetMeasureID
        pendingEndingType = type
        selectedMeasureID = targetMeasureID
    }

    private func handleEndEndingHere() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterRepeatEditMode(),
              let endingStartMeasureID = pendingEndingStartMeasureID,
              let pendingEndingType,
              let targetMeasureID,
              let orderedBoundaryIDs = orderedRepeatBoundaryIDs(
                startMeasureID: endingStartMeasureID,
                endMeasureID: targetMeasureID
              ),
              chart.addEndingSpan(
                pendingEndingType,
                startMeasureID: orderedBoundaryIDs.start,
                endMeasureID: orderedBoundaryIDs.end
              ) != nil else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        self.pendingEndingType = nil
        selectedMeasureID = targetMeasureID

    }

    private func handleRemoveEndingAtSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterRepeatEditMode(),
              let targetMeasureID,
              chart.deleteEndingSpans(attachedTo: targetMeasureID) > 0 else {
            return
        }

        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
    }

    private func handleAddPointRoadmapMarker(_ type: RoadmapType) {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }
        guard type.isPointMarker,
              let targetMeasureID,
              let markerID = chart.addPointRoadmapMarker(type, anchorMeasureID: targetMeasureID) else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedCueTextID = nil
        selectedMeasureID = targetMeasureID
        selectedRoadmapMarkerID = markerID
        canvasMode = .browse
    }

    private func handleAddCueText(position: CuePosition) {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard chart.hasCompletedInitialSetup,
              let targetMeasureID else {
            if !chart.hasCompletedInitialSetup {
                showingSetupSheet = true
            }
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
        pendingCueTextMeasureID = targetMeasureID
        pendingCueTextPosition = position
        editingCueTextID = nil
        cueTextDraft = ""
        canvasMode = .textEdit
        showingCueTextEntry = true
    }

    private func handleCueTextEntryAccepted() {
        defer {
            clearPendingCueTextEntry()
        }

        if let editingCueTextID {
            guard chart.updateCueText(editingCueTextID, text: cueTextDraft),
                  let cueText = chart.cueText(id: editingCueTextID) else {
                return
            }

            selectedCueTextID = editingCueTextID
            selectedMeasureID = cueText.anchorMeasureID
            selectedRoadmapMarkerID = nil
            canvasMode = .textEdit
            return
        }

        guard let pendingCueTextMeasureID,
              let pendingCueTextPosition,
              let cueTextID = chart.addCueText(
                cueTextDraft,
                anchorMeasureID: pendingCueTextMeasureID,
                position: pendingCueTextPosition
              ) else {
            return
        }

        selectedMeasureID = pendingCueTextMeasureID
        selectedCueTextID = cueTextID
        selectedRoadmapMarkerID = nil
        canvasMode = .textEdit
        completeEditorGuidedTourStep(.addCue)
    }

    private func handleRemoveCueTextsAtSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        let shouldStayInTextMode = canvasMode == .textEdit
        guard chart.hasCompletedInitialSetup,
              let targetMeasureID,
              chart.deleteCueTexts(attachedTo: targetMeasureID) > 0 else {
            return
        }

        pendingDeleteStartMeasureID = nil
        selectedCueTextID = nil
        selectedMeasureID = targetMeasureID
        canvasMode = shouldStayInTextMode ? .textEdit : .browse
    }

    private func handleCueTextEditRequestedFromCanvas(_ cueTextID: UUID) {
        beginCueTextEdit(cueTextID)
    }

    private func handleEditSelectedCueText() {
        guard let selectedCueTextID else {
            return
        }

        beginCueTextEdit(selectedCueTextID)
    }

    private func beginCueTextEdit(_ cueTextID: UUID) {
        guard chart.hasCompletedInitialSetup,
              let cueText = chart.cueText(id: cueTextID) else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        pendingMeasureStackInsertion = nil
        pendingCueTextMeasureID = nil
        pendingCueTextPosition = nil
        selectedCueTextID = cueTextID
        selectedRoadmapMarkerID = nil
        selectedMeasureID = cueText.anchorMeasureID
        selectedNoteSelection = nil
        editingCueTextID = cueTextID
        cueTextDraft = cueText.text
        canvasMode = .textEdit
        showingCueTextEntry = true
    }

    private func resizeSelectedCueText(by scaleDelta: Double) {
        let shouldStayInBrowse = canvasMode == .browse
        guard let selectedCueTextID,
              chart.resizeCueText(selectedCueTextID, byScaleDelta: scaleDelta),
              let cueText = chart.cueText(id: selectedCueTextID) else {
            return
        }

        selectedMeasureID = cueText.anchorMeasureID
        selectedRoadmapMarkerID = nil
        canvasMode = shouldStayInBrowse ? .browse : .textEdit
    }

    private func resizeSelectedRoadmapMarker(by scaleDelta: Double) {
        guard let selectedRoadmapMarkerID,
              chart.resizePointRoadmapMarker(selectedRoadmapMarkerID, byScaleDelta: scaleDelta),
              let marker = chart.roadmapObject(id: selectedRoadmapMarkerID) else {
            return
        }

        selectedMeasureID = marker.startMeasureID
        selectedCueTextID = nil
        canvasMode = .browse
    }

    private func deleteSelectedCueText() {
        guard let selectedCueTextID,
              let cueText = chart.cueText(id: selectedCueTextID),
              chart.deleteCueText(selectedCueTextID) else {
            return
        }

        selectedMeasureID = cueText.anchorMeasureID
        self.selectedCueTextID = nil
        selectedRoadmapMarkerID = nil
        canvasMode = .browse
    }

    private func deleteSelectedRoadmapMarker() {
        guard let selectedRoadmapMarkerID,
              let marker = chart.roadmapObject(id: selectedRoadmapMarkerID),
              chart.deleteRoadmapObject(selectedRoadmapMarkerID) else {
            return
        }

        selectedMeasureID = marker.startMeasureID
        self.selectedRoadmapMarkerID = nil
        selectedCueTextID = nil
        canvasMode = .browse
    }

    private func handleCorrectSelectedChord() {
        guard let selectedChordID else {
            return
        }

        handleChordCorrectionRequested(selectedChordID)
    }

    private func deleteSelectedChord() {
        guard let selectedChordID else {
            return
        }

        let sourceMeasureID = chart.measureContainingChordEvent(id: selectedChordID)?.id
        guard chart.deleteChordEvent(selectedChordID) else {
            return
        }

        self.selectedChordID = nil
        selectedCommittedBarlineMeasureID = nil
        selectedMeasureID = sourceMeasureID ?? selectedMeasureID
        canvasMode = .browse
    }

    private func deleteSelectedCommittedChordBarline() {
        guard let selectedCommittedBarlineMeasureID,
              chart.deleteCommittedSimpleChordBarline(after: selectedCommittedBarlineMeasureID) else {
            self.selectedCommittedBarlineMeasureID = nil
            return
        }

        selectedMeasureID = selectedCommittedBarlineMeasureID
        self.selectedCommittedBarlineMeasureID = nil
        selectedChordID = nil
        selectedCueTextID = nil
        selectedRoadmapMarkerID = nil
        canvasMode = .browse
    }

    private func clearPendingCueTextEntry() {
        cueTextDraft = ""
        pendingCueTextMeasureID = nil
        pendingCueTextPosition = nil
        editingCueTextID = nil
        showingCueTextEntry = false
    }

    private func clearPendingMeasureStackState() {
        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        pendingMeasureStackInsertion = nil
        pendingCueTextMeasureID = nil
        pendingCueTextPosition = nil
        editingCueTextID = nil
        cueTextDraft = ""
        showingCueTextEntry = false
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        selectedNoteSelection = nil
    }

    private func clearSelectedCanvasObjectIDs() {
        selectedChordID = nil
        selectedCommittedBarlineMeasureID = nil
        selectedCueTextID = nil
        selectedRoadmapMarkerID = nil
    }

    private func handleTextToolTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        if canvasMode == .textEdit {
            activateSelectTool()
            return
        }

        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        selectedNoteSelection = nil
        if selectedMeasureID == nil {
            selectedMeasureID = chart.resolvedAuthoringMeasureID()
        }
        canvasMode = .textEdit
    }

    private func handleTimeSignatureTabTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        if canvasMode == .timeSignatureEdit {
            activateSelectTool()
            return
        }

        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        selectedNoteSelection = nil
        canvasMode = .timeSignatureEdit
    }

    private func handleRhythmicNotationTabTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }
        guard isDedicatedRhythmToolAvailable else {
            activateFreeHandForRetiredRhythmTool()
            return
        }

        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        selectedNoteSelection = nil
        latestRhythmPreview = nil
        rhythmPreviewConfirmationRequestID = nil

        if canvasMode == .rhythmicNotationEdit {
            activateSelectTool()
            return
        }

        inkToolMode = .write
        selectedMeasureID = resolvedMeasureActionTargetID()
        canvasMode = .rhythmicNotationEdit
    }

    private func handleRhythmicNotationPreviewChanged(_ preview: LeadSheetRhythmicNotationPreviewState?) {
        latestRhythmPreview = preview
    }

    private func handleClearRenderedRhythmAtSelectedMeasure() {
        guard let measureID = selectedRhythmActionMeasureID else {
            noteEditErrorMessage = "Select a measure with rendered rhythm first."
            showingNoteEditError = true
            return
        }

        clearRenderedRhythm(in: measureID)
    }

    @discardableResult
    private func clearRenderedRhythm(in measureID: UUID) -> Bool {
        guard isDedicatedRhythmToolAvailable else {
            noteEditErrorMessage = "Use Ink for page-level handwritten rhythm notes in this version."
            showingNoteEditError = true
            return false
        }

        var updatedChart = chart
        guard updatedChart.clearMeasureRhythmicNotation(for: measureID, clearRhythmMap: true) else {
            noteEditErrorMessage = "There is no rendered rhythm to clear in that measure."
            showingNoteEditError = true
            return false
        }

        chart = updatedChart
        selectedMeasureID = measureID
        selectedNoteSelection = nil
        latestRhythmPreview = nil
        rhythmPreviewConfirmationRequestID = nil
        isNoteEditMenuPresented = false
        noteEditMenuStage = .actions
        inkToolMode = .write
        canvasMode = .rhythmicNotationEdit
        return true
    }

    private func activateFreeHandForRetiredRhythmTool() {
        selectedMeasureID = nil
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        latestRhythmPreview = nil
        rhythmPreviewConfirmationRequestID = nil
        clearPendingRepeatState()
        inkToolMode = .write
        canvasMode = .freeHand
    }

    private func activateSelectTool(clearsMeasureSelection: Bool = false) {
        if clearsMeasureSelection {
            selectedMeasureID = nil
        }
        clearSelectedCanvasObjectIDs()
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        pendingMeasureStackInsertion = nil
        latestRhythmPreview = nil
        rhythmPreviewConfirmationRequestID = nil
        isNoteEditMenuPresented = false
        noteEditMenuStage = .actions
        canvasMode = .browse
    }

    private func handleMeasureSelectedFromCanvas(_ measureID: UUID) {
        guard chart.hasCompletedInitialSetup,
              chart.measure(id: measureID) != nil,
              canvasMode == .browse else {
            return
        }

        selectedMeasureID = measureID
        clearSelectedCanvasObjectIDs()
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        inkToolMode = .write
        canvasMode = .browse
    }

    private func handleChordSelectedFromCanvas(_ chordID: UUID) {
        guard chart.hasCompletedInitialSetup,
              chart.chordEvent(id: chordID) != nil,
              canvasMode == .browse else {
            return
        }

        selectedChordID = chordID
        selectedCommittedBarlineMeasureID = nil
        selectedCueTextID = nil
        selectedRoadmapMarkerID = nil
        selectedMeasureID = nil
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        inkToolMode = .write
        canvasMode = .browse
    }

    private func handleCueTextSelectedFromCanvas(_ cueTextID: UUID) {
        guard chart.hasCompletedInitialSetup,
              let cueText = chart.cueText(id: cueTextID),
              canvasMode == .browse || canvasMode == .textEdit else {
            return
        }

        let shouldStayInBrowse = canvasMode == .browse
        selectedChordID = nil
        selectedCommittedBarlineMeasureID = nil
        selectedCueTextID = cueTextID
        selectedRoadmapMarkerID = nil
        selectedMeasureID = cueText.anchorMeasureID
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        canvasMode = shouldStayInBrowse ? .browse : .textEdit
    }

    private func handleRoadmapMarkerSelectedFromCanvas(_ roadmapMarkerID: UUID) {
        guard chart.hasCompletedInitialSetup,
              let marker = chart.roadmapObject(id: roadmapMarkerID),
              canvasMode == .browse else {
            return
        }

        selectedChordID = nil
        selectedCommittedBarlineMeasureID = nil
        selectedRoadmapMarkerID = roadmapMarkerID
        selectedCueTextID = nil
        selectedMeasureID = marker.startMeasureID
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
    }

    private func handleRepeatSpanSelectedFromCanvas(_ roadmapObjectID: UUID) {
        guard chart.hasCompletedInitialSetup,
              let repeatSpan = chart.roadmapObject(id: roadmapObjectID),
              repeatSpan.type == .repeatSpan,
              canvasMode == .browse else {
            return
        }

        selectedMeasureID = repeatSpan.startMeasureID
        clearSelectedCanvasObjectIDs()
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        _ = enterRepeatEditMode()
    }

    private func handleEndingSpanSelectedFromCanvas(_ roadmapObjectID: UUID) {
        guard chart.hasCompletedInitialSetup,
              let endingSpan = chart.roadmapObject(id: roadmapObjectID),
              endingSpan.type.isEnding,
              canvasMode == .browse else {
            return
        }

        selectedMeasureID = endingSpan.startMeasureID
        clearSelectedCanvasObjectIDs()
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        _ = enterRepeatEditMode()
    }

    private func handleTimeSignatureSelectedFromCanvas(_ measureID: UUID) {
        guard chart.hasCompletedInitialSetup,
              chart.measure(id: measureID) != nil,
              canvasMode == .browse else {
            return
        }

        selectedMeasureID = measureID
        clearSelectedCanvasObjectIDs()
        selectedNoteSelection = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        canvasMode = .timeSignatureEdit
        pendingTimeSignaturePlacement = nil
        pendingTimeSignatureSourceMeasureID = measureID
    }

    private func resolvedMeasureActionTargetID() -> UUID? {
        chart.resolvedAuthoringMeasureID(preferredMeasureID: selectedMeasureID)
    }

    private func neighboringSelectionAfterDeletingMeasure(_ measureID: UUID) -> UUID? {
        let measureIDs = chart.measures.map(\.id)
        guard let deletionIndex = measureIDs.firstIndex(of: measureID) else {
            return nil
        }

        if measureIDs.indices.contains(deletionIndex + 1) {
            return measureIDs[deletionIndex + 1]
        }

        if deletionIndex > 0 {
            return measureIDs[deletionIndex - 1]
        }

        return nil
    }

    private func neighboringSelectionAfterDeletingMeasureRange(
        startMeasureID: UUID,
        endMeasureID: UUID
    ) -> UUID? {
        let measureIDs = chart.measures.map(\.id)
        guard let startIndex = measureIDs.firstIndex(of: startMeasureID),
              let endIndex = measureIDs.firstIndex(of: endMeasureID) else {
            return nil
        }

        let lowerBound = min(startIndex, endIndex)
        let upperBound = max(startIndex, endIndex)
        if lowerBound > 0 {
            return measureIDs[lowerBound - 1]
        }

        if measureIDs.indices.contains(upperBound + 1) {
            return measureIDs[upperBound + 1]
        }

        return nil
    }

    private func orderedRepeatBoundaryIDs(
        startMeasureID: UUID,
        endMeasureID: UUID
    ) -> (start: UUID, end: UUID)? {
        let measureIDs = chart.measures.map(\.id)
        guard let startIndex = measureIDs.firstIndex(of: startMeasureID),
              let endIndex = measureIDs.firstIndex(of: endMeasureID) else {
            return nil
        }

        return startIndex <= endIndex
            ? (startMeasureID, endMeasureID)
            : (endMeasureID, startMeasureID)
    }

    private func toggleFreeHandMode() {
        if canvasMode == .freeHand {
            pendingTimeSignatureSourceMeasureID = nil
            pendingTimeSignaturePlacement = nil
            activateSelectTool()
            return
        }

        guard chart.hasCompletedInitialSetup else {
            if !chart.hasCompletedInitialSetup {
                showingSetupSheet = true
            }
            return
        }
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        selectedNoteSelection = nil
        inkToolMode = .write
        canvasMode = .freeHand
    }

    private func activateHeaderWritingTool() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        selectedMeasureID = nil
        selectedNoteSelection = nil
        clearSelectedCanvasObjectIDs()
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        pendingMeasureStackInsertion = nil
        isNoteEditMenuPresented = false
        noteEditMenuStage = .actions
        chart.setHeaderInputMode(.handwritten)
        inkToolMode = .write
        canvasMode = .headerEntry
    }

    private func handleHeaderAuthoringRequestedFromCanvas() {
        activateHeaderWritingTool()
    }

    private func handleChordTabTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        selectedMeasureID = nil
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()

        if canvasMode == .chordEntry {
            activateSelectTool()
        } else {
            inkToolMode = .write
            canvasMode = .chordEntry
        }
    }

    private func handleEditTabTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }
        guard allowsUserFacingRhythmNoteEditing else {
            selectedNoteSelection = nil
            noteEditMenuStage = .actions
            isNoteEditMenuPresented = false
            return
        }

        selectedMeasureID = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()

        if canvasMode == .noteEdit {
            selectedNoteSelection = nil
            canvasMode = .browse
        } else {
            inkToolMode = .write
            canvasMode = .noteEdit
        }
    }

    private func handleTimeSignatureTargetRequested(_ measureID: UUID) {
        guard canvasMode == .timeSignatureEdit,
              chart.measure(id: measureID) != nil else {
            return
        }

        selectedNoteSelection = nil
        selectedMeasureID = measureID
        pendingTimeSignaturePlacement = nil
        pendingTimeSignatureSourceMeasureID = measureID
    }

    private func handleTimeSignatureSelection(
        _ meter: Meter,
        startingAt sourceMeasureID: UUID,
        scope: TimeSignatureApplicationScope
    ) {
        let appliedMeasureID = chart.applyMeterChange(meter, startingAt: sourceMeasureID, scope: scope)
        selectedMeasureID = appliedMeasureID ?? sourceMeasureID
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil

        if appliedMeasureID == nil {
            canvasMode = .browse
        }
    }

    private func handleKeyChangeSelection(_ key: DocumentKey) {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard chart.hasCompletedInitialSetup,
              let targetMeasureID,
              chart.setDisplayedKeyChange(key, atStartOf: targetMeasureID) else {
            if !chart.hasCompletedInitialSetup {
                showingSetupSheet = true
            }
            return
        }

        selectedMeasureID = targetMeasureID
        selectedNoteSelection = nil
        canvasMode = .browse
    }

    private func handleRemoveKeyChangeAtSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard chart.hasCompletedInitialSetup,
              let targetMeasureID,
              chart.removeKeyChange(atStartOf: targetMeasureID) else {
            return
        }

        selectedMeasureID = targetMeasureID
        selectedNoteSelection = nil
        canvasMode = .browse
    }

    private func handleChordInkDraftPreviewChanged(_ payloads: [ChordInkRecognitionProposalPayload]) {
        let replacementStartedAt = ProcessInfo.processInfo.systemUptime
        guard canvasMode == .chordEntry,
              pendingChordInkConfirmation == nil,
              pendingChordInkBatchConfirmation == nil,
              pendingChordCorrection == nil else {
            return
        }
        guard payloads.isEmpty || chart.pageHandwrittenChordData != nil else {
            return
        }

        let previousDraftByAnchor = Dictionary(
            chordPreviewState.draftChords.map { ($0.anchor, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var reusedResolutionCount = 0
        let inputs = payloads.compactMap { payload -> ChordInkDraftInput? in
            guard let measure = chart.measure(id: payload.target.measureID) else {
                return nil
            }

            let incomingAnchor = ChordInkDraftAnchor(
                measureID: payload.target.measureID,
                laneLocation: payload.laneLocation,
                visualOrder: payload.visualOrder,
                fraction: payload.target.fraction
            )
            if let reusedInput = ChordInkDraftPreviewResolutionReusePolicy.reusedInput(
                previousDraft: previousDraftByAnchor[incomingAnchor],
                measureID: payload.target.measureID,
                measureIndex: measure.index,
                targetFraction: payload.target.fraction,
                visualOrder: payload.visualOrder,
                laneLocation: payload.laneLocation,
                layoutPageSize: payload.layoutPageSize,
                drawingData: payload.drawingData,
                strokeCount: payload.timing.strokeCount,
                isRecognitionCacheHit: payload.timing.cacheHit
            ) {
                reusedResolutionCount += 1
                return reusedInput
            }

            let resolution = ChordInkRenderResolutionPolicy.resolution(
                for: payload.result,
                drawingData: payload.drawingData,
                correctionMemory: chordInkUserCorrectionMemory
            )
            return ChordInkDraftInput(
                measureID: payload.target.measureID,
                measureIndex: measure.index,
                targetFraction: payload.target.fraction,
                visualOrder: payload.visualOrder,
                laneLocation: payload.laneLocation,
                layoutPageSize: payload.layoutPageSize,
                drawingData: payload.drawingData,
                candidateTexts: resolution.candidateTexts,
                bestCandidateText: resolution.decision.acceptedText ?? payload.result.match?.displayText,
                confidence: payload.result.confidence,
                strokeCount: payload.timing.strokeCount,
                recognitionResult: payload.result,
                primaryDecision: resolution.primaryDecision,
                recognitionDecision: resolution.decision
            )
        }

        let previousPreviewState = chordPreviewState
        var updatedPreviewState = chordPreviewState
        updatedPreviewState.replaceDraftChords(with: inputs)
        ChordDraftPreviewDeviceDiagnostics.recordPreviewReplacement(
            previousState: previousPreviewState,
            inputs: inputs,
            updatedState: updatedPreviewState,
            layoutStyle: chart.layoutStyle
        )
        chordPreviewState = updatedPreviewState

        IChartPerformanceTrace.record(
            "chord.preview.replace",
            durationMilliseconds: (ProcessInfo.processInfo.systemUptime - replacementStartedAt) * 1_000,
            metadata: [
                "targets": "\(payloads.count)",
                "drafts": "\(updatedPreviewState.draftChords.count)",
                "cache_hits": "\(payloads.filter { $0.timing.cacheHit }.count)",
                "reused_resolutions": "\(reusedResolutionCount)",
                "layout_style": chart.layoutStyle.rawValue
            ]
        )

        let layoutStyle = chart.layoutStyle.rawValue
        Self.chordPreviewTelemetryQueue.async {
            IChartTelemetry.record(
                "chord.preview_updated",
                properties: Self.chordDraftPreviewTelemetryProperties(
                    payloads: payloads,
                    inputs: inputs,
                    updatedState: updatedPreviewState,
                    layoutStyle: layoutStyle
                )
            )
        }
    }

    private func handleChordInkDraftBarlinesChanged(_ barlines: [DraftBarline]) {
        guard canvasMode == .chordEntry else {
            return
        }

        let previousCount = chordPreviewState.draftBarlines.count
        var updatedPreviewState = chordPreviewState
        updatedPreviewState.replaceDraftBarlines(with: barlines)
        chordPreviewState = updatedPreviewState

        if barlines.count > previousCount {
            IChartTelemetry.record(
                "chord.draft_barline_added",
                properties: [
                    "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
                    "barline_count": .int(barlines.count),
                    "draft_count": .int(updatedPreviewState.draftChords.count),
                    "unresolved_count": .int(updatedPreviewState.unresolvedBarlineCount),
                    "layout_style": .string(chart.layoutStyle.rawValue)
                ]
            )
        }
    }

    private func handleRenderChordDrafts() {
        guard canRenderChordDrafts else {
            if chordPreviewState.unresolvedChordCount > 0 {
                chordInkErrorMessage = "One or more draft chords need a supported read before rendering."
                showingChordInkError = true
            }
            return
        }

        if chordPreviewState.requiresChordConfirmation {
            guard let batch = ChordInkDraftReviewPolicy.batch(for: chordPreviewState) else {
                chordInkErrorMessage = "One or more draft chords could not be prepared for review. Keep the ink and try again."
                showingChordInkError = true
                return
            }

            pendingChordInkBatchConfirmation = batch
            IChartTelemetry.record(
                "chord.confirmation_presented",
                properties: [
                    "batch_size": .int(batch.confirmations.count),
                    "confirm_count": .int(
                        batch.confirmations.filter { $0.decision.action == .confirm }.count
                    ),
                    "result": .string("draft_review"),
                    "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
                    "layout_style": .string(chart.layoutStyle.rawValue)
                ]
            )
            return
        }

        _ = renderChordPreviewState(chordPreviewState, reviewResult: "trusted")
    }

    @discardableResult
    private func renderChordPreviewState(
        _ state: ChordPreviewState,
        reviewResult: String
    ) -> Bool {

        var updatedChart = chart
        let renderResult = updatedChart.commitChordInkDraftBatch(
            state,
            barlineSpacingMode: .drawn
        )
        guard renderResult.renderedChordCount > 0 || renderResult.renderedBarlineCount > 0 else {
            chordInkErrorMessage = "No draft chords or barlines were ready to render yet."
            showingChordInkError = true
            return false
        }
        guard renderResult.unresolvedDraftIDs.isEmpty else {
            chordInkErrorMessage = "One or more reviewed chords could not be rendered. The draft ink is still available."
            showingChordInkError = true
            return false
        }

        chart = updatedChart
        selectedMeasureID = updatedChart.measures.last(where: { !$0.chordEvents.isEmpty })?.id ?? selectedMeasureID
        selectedNoteSelection = nil
        pendingChordInkConfirmation = nil
        pendingChordInkBatchConfirmation = nil
        pendingChordCorrection = nil
        chordDraftRenderInvalidationRequestID = UUID()
        chordPreviewState.discard()
        chordInkAutomaticRewriteFailures.reset()
        completeEditorGuidedTourStep(.writeChords)
        completeEditorGuidedTourStep(.renderChords)

        IChartTelemetry.record(
            "chord.preview_rendered",
            properties: [
                "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
                "draft_count": .int(renderResult.renderedChordCount + renderResult.renderedBarlineCount),
                "rendered_count": .int(renderResult.renderedChordCount),
                "barline_count": .int(renderResult.renderedBarlineCount),
                "unresolved_count": .int(renderResult.unresolvedDraftIDs.count),
                "decision": .string(reviewResult),
                "layout_style": .string(updatedChart.layoutStyle.rawValue)
            ]
        )
        return true
    }

    private func handleDiscardChordDrafts() {
        guard !chordPreviewState.isEmpty || chart.pageHandwrittenChordData != nil else {
            return
        }

        let discardedDraftCount = chordPreviewState.draftChords.count
        let discardedBarlineCount = chordPreviewState.draftBarlines.count
        var updatedChart = chart
        _ = updatedChart.setPageHandwrittenChordDrawing(nil)
        chart = updatedChart
        pendingChordInkConfirmation = nil
        pendingChordInkBatchConfirmation = nil
        pendingChordCorrection = nil
        chordDraftRenderInvalidationRequestID = UUID()
        chordPreviewState.discard()

        IChartTelemetry.record(
            "chord.preview_discarded",
            properties: [
                "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
                "draft_count": .int(discardedDraftCount),
                "barline_count": .int(discardedBarlineCount),
                "layout_style": .string(updatedChart.layoutStyle.rawValue)
            ]
        )
    }

    private func handleChordInkRecognitionProposal(
        measureID: UUID,
        result: ChordInkRecognitionResult,
        drawingData: Data,
        targetFraction: Double?,
        timing: ChordInkRecognitionTiming,
        flow: ChordInkRecognitionFlow
    ) {
        #if DEBUG && targetEnvironment(simulator)
        let proposalReceivedAt = Date()
        #endif
        guard canvasMode == .chordEntry,
              pendingChordInkConfirmation == nil,
              pendingChordInkBatchConfirmation == nil,
              pendingChordCorrection == nil,
              let measure = chart.measure(id: measureID),
              flow.canRenderChord else {
            return
        }

        selectedMeasureID = nil
        selectedNoteSelection = nil
        let resolution = ChordInkRenderResolutionPolicy.resolution(
            for: result,
            drawingData: drawingData,
            correctionMemory: chordInkUserCorrectionMemory
        )
        #if DEBUG && targetEnvironment(simulator)
        let proposalDecisionMilliseconds = Date().timeIntervalSince(proposalReceivedAt) * 1_000
        #else
        let proposalDecisionMilliseconds: Double? = nil
        #endif
        let confirmation = PendingChordInkConfirmation(
            measureID: measureID,
            measureIndex: measure.index,
            result: result,
            drawingData: drawingData,
            targetFraction: targetFraction,
            recognitionTiming: timing,
            proposalDecisionMilliseconds: proposalDecisionMilliseconds,
            primaryDecision: resolution.primaryDecision,
            decision: resolution.decision,
            candidateTexts: resolution.candidateTexts
        )

        #if DEBUG && targetEnvironment(simulator)
        logChordInkProposalTiming(
            result: result,
            primaryDecision: resolution.primaryDecision,
            decision: resolution.decision,
            decisionMilliseconds: proposalDecisionMilliseconds
        )
        #endif
        IChartTelemetry.record(
            "chord.recognition_proposed",
            properties: Self.chordTelemetryProperties(
                result: result,
                candidateCount: resolution.candidateTexts.count,
                decision: resolution.decision,
                timing: timing,
                flow: flow
            )
        )

        handleTapConfirmedChordRecognition(confirmation)
    }

    private func handleChordInkBatchRecognitionProposal(
        payloads: [ChordInkRecognitionProposalPayload],
        flow: ChordInkRecognitionFlow
    ) {
        #if DEBUG && targetEnvironment(simulator)
        let proposalReceivedAt = Date()
        #endif
        guard canvasMode == .chordEntry,
              pendingChordInkConfirmation == nil,
              pendingChordInkBatchConfirmation == nil,
              pendingChordCorrection == nil,
              flow.canRenderChord,
              payloads.count > 1 else {
            return
        }

        selectedMeasureID = nil
        selectedNoteSelection = nil

        let confirmations = payloads.compactMap { payload -> PendingChordInkConfirmation? in
            guard let measure = chart.measure(id: payload.target.measureID) else {
                return nil
            }

            let resolution = ChordInkRenderResolutionPolicy.resolution(
                for: payload.result,
                drawingData: payload.drawingData,
                correctionMemory: chordInkUserCorrectionMemory
            )
            #if DEBUG && targetEnvironment(simulator)
            let proposalDecisionMilliseconds = Date().timeIntervalSince(proposalReceivedAt) * 1_000
            #else
            let proposalDecisionMilliseconds: Double? = nil
            #endif

            return PendingChordInkConfirmation(
                measureID: payload.target.measureID,
                measureIndex: measure.index,
                result: payload.result,
                drawingData: payload.drawingData,
                targetFraction: payload.target.fraction,
                recognitionTiming: payload.timing,
                proposalDecisionMilliseconds: proposalDecisionMilliseconds,
                primaryDecision: resolution.primaryDecision,
                decision: resolution.decision,
                candidateTexts: resolution.candidateTexts
            )
        }

        guard confirmations.count > 1 else {
            return
        }

        let batch = PendingChordInkBatchConfirmation(confirmations: confirmations)
        IChartTelemetry.record(
            "chord.recognition_proposed",
            properties: [
                "batch_size": .int(confirmations.count),
                "flow": .string(flow.telemetryValue),
                "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
                "result": .string("batch"),
                "layout_style": .string(chart.layoutStyle.rawValue),
                "measure_count": .int(chart.measures.count)
            ]
        )
        let isGuidedChordConfirmation = editorGuidedTourStep == .writeChords
            || editorGuidedTourStep == .renderChords
        let trustedTextsByID = Dictionary(
            uniqueKeysWithValues: confirmations.compactMap { confirmation -> (UUID, String)? in
                guard confirmation.decision.action == .trusted,
                      let acceptedText = confirmation.decision.acceptedText else {
                    return nil
                }

                return (confirmation.id, acceptedText)
            }
        )

        if !isGuidedChordConfirmation,
           trustedTextsByID.count == confirmations.count,
           commitChordInkBatchCandidates(
                trustedTextsByID,
                batch: batch,
                resolution: .autoRendered
           ) {
            return
        }

        pendingChordInkBatchConfirmation = batch
        IChartTelemetry.record(
            "chord.confirmation_presented",
            properties: [
                "batch_size": .int(confirmations.count),
                "result": .string("batch_confirmation"),
                "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
                "layout_style": .string(chart.layoutStyle.rawValue)
            ]
        )
    }

    private func handleChordInkBatchAccepted(
        _ candidateTextByID: [UUID: String],
        batch: PendingChordInkBatchConfirmation
    ) {
        let trimmedCandidateTextByID = candidateTextByID.reduce(into: [UUID: String]()) { result, element in
            result[element.key] = element.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let didCommit: Bool
        switch batch.source {
        case .recognitionProposal:
            didCommit = commitChordInkBatchCandidates(
                trimmedCandidateTextByID,
                batch: batch,
                resolution: .confirmedSuggestion
            )
        case .draftPreview:
            didCommit = commitReviewedChordDrafts(
                trimmedCandidateTextByID,
                batch: batch
            )
        }

        guard didCommit else {
            return
        }

        var didUpdateMemory = false
        for confirmation in batch.confirmations {
            guard let acceptedText = trimmedCandidateTextByID[confirmation.id] else {
                continue
            }

            if confirmation.visibleCandidateTexts.contains(acceptedText) {
                didUpdateMemory = chordInkUserCorrectionMemory.recordConfirmedSuggestion(
                    acceptedText: acceptedText,
                    drawingData: confirmation.drawingData,
                    candidateTexts: confirmation.candidateTexts,
                    decision: confirmation.decision
                ) || didUpdateMemory
            } else {
                didUpdateMemory = chordInkUserCorrectionMemory.recordManualCorrection(
                    acceptedText: acceptedText,
                    drawingData: confirmation.drawingData,
                    candidateTexts: confirmation.candidateTexts
                ) || didUpdateMemory
            }
        }

        if didUpdateMemory {
            persistChordInkUserCorrectionMemory()
        }
    }

    private func commitReviewedChordDrafts(
        _ candidateTextByID: [UUID: String],
        batch: PendingChordInkBatchConfirmation
    ) -> Bool {
        guard batch.source == .draftPreview,
              batch.confirmations.count == chordPreviewState.renderableDraftChords.count,
              let reviewedState = ChordInkDraftReviewPolicy.reviewedState(
                  from: chordPreviewState,
                  candidateTextByDraftID: candidateTextByID
              ) else {
            chordInkErrorMessage = "One or more chord candidates are not supported yet. Edit the text and try again."
            showingChordInkError = true
            return false
        }

        return renderChordPreviewState(reviewedState, reviewResult: "confirmed")
    }

    private func handleTapConfirmedChordRecognition(_ confirmation: PendingChordInkConfirmation) {
        let isGuidedChordConfirmation = editorGuidedTourStep == .writeChords
            || editorGuidedTourStep == .renderChords

        completeEditorGuidedTourStep(.writeChords)

        if !isGuidedChordConfirmation,
           confirmation.decision.action == .trusted,
           let acceptedText = confirmation.decision.acceptedText {
            _ = commitChordInkCandidate(
                acceptedText,
                confirmation: confirmation,
                resolution: .autoRendered
            )
            return
        }

        let isCompleteFailure = ChordInkUserCorrectionMemoryPolicy.isCompleteFailure(
            result: confirmation.result,
            decision: confirmation.decision,
            candidateTexts: confirmation.candidateTexts
        )

        if !isCompleteFailure {
            chordInkAutomaticRewriteFailures.reset()
        }

        if !isGuidedChordConfirmation,
           !isCompleteFailure,
           let preferredCandidate = chordInkUserCorrectionMemory.preferredCandidate(
               for: confirmation.candidateTexts,
               drawingData: confirmation.drawingData,
               decision: confirmation.decision
           ) {
            if commitChordInkCandidate(
                preferredCandidate,
                confirmation: confirmation,
                resolution: .userRuleApplied
            ) {
                chordInkUserCorrectionMemory.recordRuleApplication(
                    acceptedText: preferredCandidate,
                    candidateTexts: confirmation.candidateTexts
                )
                persistChordInkUserCorrectionMemory()
            }
            return
        }

        pendingChordInkConfirmation = confirmation
        IChartTelemetry.record(
            "chord.confirmation_presented",
            properties: Self.chordTelemetryProperties(
                confirmation: confirmation,
                resolution: .confirmedSuggestion
            )
        )
    }

    private func handleChordInkCandidateAccepted(
        _ candidateText: String,
        confirmation: PendingChordInkConfirmation
    ) {
        let trimmedCandidateText = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolution: ChordEntryDiagnosticResolution = confirmation.visibleCandidateTexts.contains(trimmedCandidateText)
            ? .confirmedSuggestion
            : .manualCorrection

        let didCommit = commitChordInkCandidate(
            trimmedCandidateText,
            confirmation: confirmation,
            resolution: resolution
        )

        guard didCommit else {
            return
        }

        switch resolution {
        case .confirmedSuggestion:
            if chordInkUserCorrectionMemory.recordConfirmedSuggestion(
                acceptedText: trimmedCandidateText,
                drawingData: confirmation.drawingData,
                candidateTexts: confirmation.candidateTexts,
                decision: confirmation.decision
            ) {
                persistChordInkUserCorrectionMemory()
            }
        case .manualCorrection:
            if chordInkUserCorrectionMemory.recordManualCorrection(
                acceptedText: trimmedCandidateText,
                drawingData: confirmation.drawingData,
                candidateTexts: confirmation.candidateTexts
            ) {
                persistChordInkUserCorrectionMemory()
            }
        case .autoRendered, .userRuleApplied, .renderedChordCorrection, .reconciledRenderedChord:
            break
        }
    }

    @discardableResult
    private func commitChordInkCandidate(
        _ candidateText: String,
        confirmation: PendingChordInkConfirmation,
        resolution: ChordEntryDiagnosticResolution
    ) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        let commitStartedAt = Date()
        #endif
        guard let match = ChordRecognitionCompendium.match(candidateText) else {
            chordInkErrorMessage = "That chord candidate is not supported yet. Try another candidate or edit the text."
            showingChordInkError = true
            IChartTelemetry.record(
                "chord.recognition_failed",
                properties: Self.chordTelemetryProperties(
                    confirmation: confirmation,
                    resolution: resolution,
                    errorCode: "unsupported_candidate"
                )
            )
            return false
        }

        var updatedChart = chart
        guard let chordEventID = updatedChart.commitRecognizedChordInk(
            match.symbol,
            rawInput: candidateText,
            to: confirmation.measureID,
            atFraction: confirmation.targetFraction,
            sourceInkData: confirmation.drawingData,
            sourceCandidateSignature: ChordInkUserCorrectionMemoryPolicy.candidateSignature(
                from: confirmation.candidateTexts
            )
        ) else {
            chordInkErrorMessage = "That measure is no longer available. Keep the ink and try again."
            showingChordInkError = true
            IChartTelemetry.record(
                "chord.recognition_failed",
                properties: Self.chordTelemetryProperties(
                    confirmation: confirmation,
                    resolution: resolution,
                    errorCode: "missing_measure"
                )
            )
            return false
        }

        chart = updatedChart
        chordInkAutomaticRewriteFailures.reset()

        #if DEBUG && targetEnvironment(simulator)
        let commitMutationMilliseconds = Date().timeIntervalSince(commitStartedAt) * 1_000
        let commitObservedAt = Date()
        recordChordEntryDiagnostic(
            acceptedText: candidateText,
            match: match,
            confirmation: confirmation,
            resolution: resolution,
            chordEventID: chordEventID,
            chartSnapshot: updatedChart,
            commitMutationMilliseconds: commitMutationMilliseconds,
            commitObservedAt: commitObservedAt
        )
        #endif

        selectedMeasureID = confirmation.measureID
        selectedNoteSelection = nil
        canvasMode = .chordEntry
        pendingChordInkConfirmation = nil
        completeEditorGuidedTourStep(.writeChords)
        completeEditorGuidedTourStep(.renderChords)

        #if DEBUG && targetEnvironment(simulator)
        logChordInkCommitTiming(
            acceptedText: candidateText,
            resolution: resolution,
            chordEventID: chordEventID,
            commitMilliseconds: commitMutationMilliseconds
        )
        #endif

        IChartTelemetry.record(
            resolution == .manualCorrection ? "chord.correction_applied" : "chord.recognition_committed",
            properties: Self.chordTelemetryProperties(
                confirmation: confirmation,
                resolution: resolution
            )
        )
        return true
    }

    @discardableResult
    private func commitChordInkBatchCandidates(
        _ candidateTextByID: [UUID: String],
        batch: PendingChordInkBatchConfirmation,
        resolution: ChordEntryDiagnosticResolution
    ) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        let commitStartedAt = Date()
        #endif
        let acceptedCandidates = batch.confirmations.compactMap { confirmation -> (PendingChordInkConfirmation, String, ChordRecognitionMatch)? in
            guard let candidateText = candidateTextByID[confirmation.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !candidateText.isEmpty else {
                return nil
            }

            guard let match = ChordRecognitionCompendium.match(candidateText) else {
                return nil
            }

            return (confirmation, candidateText, match)
        }

        guard acceptedCandidates.count == batch.confirmations.count else {
            chordInkErrorMessage = "One or more chord candidates are not supported yet. Edit the text and try again."
            showingChordInkError = true
            IChartTelemetry.record(
                "chord.recognition_failed",
                properties: [
                    "batch_size": .int(batch.confirmations.count),
                    "result": .string("batch_failed"),
                    "error_code": .string("unsupported_candidate")
                ]
            )
            return false
        }

        var updatedChart = chart
        var committedEvents = [(PendingChordInkConfirmation, String, ChordRecognitionMatch, UUID)]()
        for acceptedCandidate in acceptedCandidates {
            let confirmation = acceptedCandidate.0
            let candidateText = acceptedCandidate.1
            let match = acceptedCandidate.2
            guard let chordEventID = updatedChart.appendRecognizedChordEvent(
                match.symbol,
                rawInput: candidateText,
                to: confirmation.measureID,
                atFraction: confirmation.targetFraction,
                sourceInkData: confirmation.drawingData,
                sourceCandidateSignature: ChordInkUserCorrectionMemoryPolicy.candidateSignature(
                    from: confirmation.candidateTexts
                )
            ) else {
                chordInkErrorMessage = "One of those measures is no longer available. Keep the ink and try again."
                showingChordInkError = true
                IChartTelemetry.record(
                    "chord.recognition_failed",
                    properties: [
                        "batch_size": .int(batch.confirmations.count),
                        "result": .string("batch_failed"),
                        "error_code": .string("missing_measure")
                    ]
                )
                return false
            }

            committedEvents.append((confirmation, candidateText, match, chordEventID))
        }

        _ = updatedChart.setPageHandwrittenChordDrawing(nil)
        chart = updatedChart
        chordInkAutomaticRewriteFailures.reset()

        #if DEBUG && targetEnvironment(simulator)
        let commitMutationMilliseconds = Date().timeIntervalSince(commitStartedAt) * 1_000
        let commitObservedAt = Date()
        for committedEvent in committedEvents {
            recordChordEntryDiagnostic(
                acceptedText: committedEvent.1,
                match: committedEvent.2,
                confirmation: committedEvent.0,
                resolution: resolution,
                chordEventID: committedEvent.3,
                chartSnapshot: updatedChart,
                commitMutationMilliseconds: commitMutationMilliseconds,
                commitObservedAt: commitObservedAt
            )
            logChordInkCommitTiming(
                acceptedText: committedEvent.1,
                resolution: resolution,
                chordEventID: committedEvent.3,
                commitMilliseconds: commitMutationMilliseconds
            )
        }
        #endif

        selectedMeasureID = committedEvents.last?.0.measureID
        selectedNoteSelection = nil
        canvasMode = .chordEntry
        pendingChordInkConfirmation = nil
        pendingChordInkBatchConfirmation = nil
        completeEditorGuidedTourStep(.writeChords)
        completeEditorGuidedTourStep(.renderChords)

        IChartTelemetry.record(
            "chord.batch_committed",
            properties: [
                "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
                "layout_style": .string(chart.layoutStyle.rawValue),
                "batch_size": .int(committedEvents.count),
                "decision": .string(resolution.rawValue),
                "result": .string("committed")
            ]
        )
        return true
    }

    private func handleChordCorrectionRequested(_ chordEventID: UUID) {
        guard (canvasMode == .chordEntry || canvasMode == .browse),
              pendingChordInkConfirmation == nil,
              pendingChordInkBatchConfirmation == nil,
              pendingChordCorrection == nil,
              let chordEvent = chart.chordEvent(id: chordEventID),
              let measure = chart.measureContainingChordEvent(id: chordEventID) else {
            return
        }

        pendingChordCorrection = PendingChordCorrection(
            chordEventID: chordEventID,
            measureID: measure.id,
            measureIndex: measure.index,
            currentText: chart.displayedChordSymbol(for: chordEvent, in: measure.id).displayText,
            rawInput: chordEvent.rawInput,
            candidateTexts: chordEvent.sourceCandidateSignature,
            enharmonicChoiceTexts: chart.enharmonicChordSpellingTexts(for: chordEvent, in: measure.id)
        )
    }

    private func handleChordCorrectionAccepted(
        _ candidateText: String,
        correction: PendingChordCorrection
    ) {
        let shouldReturnToBrowse = canvasMode == .browse
        let trimmedCandidateText = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = ChordRecognitionCompendium.match(trimmedCandidateText) else {
            chordInkErrorMessage = "That chord candidate is not supported yet. Try another candidate or edit the text."
            showingChordInkError = true
            return
        }

        guard let originalChordEvent = chart.chordEvent(id: correction.chordEventID) else {
            chordInkErrorMessage = "That chord is no longer available. Try writing it again."
            showingChordInkError = true
            return
        }

        var updatedChart = chart
        guard updatedChart.replaceChordEvent(
            correction.chordEventID,
            with: match.symbol,
            rawInput: trimmedCandidateText
        ) else {
            chordInkErrorMessage = "That chord is no longer available. Try writing it again."
            showingChordInkError = true
            return
        }

        chart = updatedChart

        let previousRecognitionText = originalChordEvent.rawInput ?? originalChordEvent.symbol.displayText
        let didUpdateCorrectionMemory = originalChordEvent.sourceInkData.map { sourceInkData in
            chordInkUserCorrectionMemory.recordRenderedChordCorrection(
                previousText: previousRecognitionText,
                displayedPreviousText: correction.currentText,
                acceptedText: trimmedCandidateText,
                drawingData: sourceInkData,
                candidateTexts: originalChordEvent.sourceCandidateSignature
            )
        } ?? false
        if didUpdateCorrectionMemory {
            persistChordInkUserCorrectionMemory()
        }

        IChartTelemetry.record(
            "chord.rendered_correction_applied",
            properties: [
                "candidate_count": .int(originalChordEvent.sourceCandidateSignature.count),
                "decision": .string(Self.renderedChordCorrectionFeedbackKind(
                    previousRecognitionText: previousRecognitionText,
                    previousRenderedText: correction.currentText,
                    acceptedText: trimmedCandidateText,
                    candidateTexts: originalChordEvent.sourceCandidateSignature
                )),
                "layout_style": .string(updatedChart.layoutStyle.rawValue),
                "result": .string(didUpdateCorrectionMemory ? "memory_updated" : "edit_only")
            ].merging(ChordInkCorrectionTelemetry.sourceProperties(
                hasSourceInk: originalChordEvent.sourceInkData != nil,
                sourceRecognitionPipelineVersion: originalChordEvent.sourceRecognitionPipelineVersion
            )) { _, sourceValue in sourceValue }
        )

        #if DEBUG && targetEnvironment(simulator)
        recordChordCorrectionDiagnostic(
            acceptedText: trimmedCandidateText,
            match: match,
            correction: correction,
            chartSnapshot: updatedChart
        )
        #endif

        selectedChordID = correction.chordEventID
        selectedMeasureID = shouldReturnToBrowse ? nil : correction.measureID
        selectedNoteSelection = nil
        pendingChordCorrection = nil
        canvasMode = shouldReturnToBrowse ? .browse : .chordEntry
    }

    #if DEBUG && targetEnvironment(simulator)
    private func logChordInkProposalTiming(
        result: ChordInkRecognitionResult,
        primaryDecision: ChordInkRecognitionDecision,
        decision: ChordInkRecognitionDecision,
        decisionMilliseconds: Double?
    ) {
        let confidenceGap = decision.confidenceGap ?? -1
        let bestRead = result.match?.displayText ?? "none"
        print(
            String(
                format: "iChart chord proposal: decisionMs=%.0f best=%@ confidence=%.2f primaryAction=%@ finalAction=%@ closeRace=%@ gap=%.2f reason=%@",
                decisionMilliseconds ?? -1,
                bestRead,
                result.confidence,
                primaryDecision.action.rawValue,
                decision.action.rawValue,
                decision.isCloseRace ? "yes" : "no",
                confidenceGap,
                decision.reason
            )
        )
    }

    private func logChordInkCommitTiming(
        acceptedText: String,
        resolution: ChordEntryDiagnosticResolution,
        chordEventID: UUID,
        commitMilliseconds: Double
    ) {
        print(
            String(
                format: "iChart chord commit: commitMs=%.0f accepted=%@ resolution=%@ event=%@",
                commitMilliseconds,
                acceptedText,
                resolution.rawValue,
                chordEventID.uuidString
            )
        )
    }

    private func recordChordEntryDiagnostic(
        acceptedText: String,
        match: ChordRecognitionMatch,
        confirmation: PendingChordInkConfirmation,
        resolution: ChordEntryDiagnosticResolution,
        chordEventID: UUID,
        chartSnapshot: Chart,
        commitMutationMilliseconds: Double?,
        commitObservedAt: Date
    ) {
        let timingEvidence = confirmation.recognitionTiming?.diagnosticEvidence(
            proposalDecisionMilliseconds: confirmation.proposalDecisionMilliseconds,
            commitMutationMilliseconds: commitMutationMilliseconds
        )
        let event = ChordEntryDiagnosticEvent(
            timestamp: .now,
            chartID: chartSnapshot.id,
            chartTitle: chartSnapshot.title,
            measureID: confirmation.measureID,
            measureIndex: confirmation.measureIndex,
            chordEventID: chordEventID,
            resolution: resolution,
            acceptedText: acceptedText,
            previousRenderedDisplayText: nil,
            renderedDisplayText: match.displayText,
            bestCandidateText: confirmation.bestCandidateText,
            suggestedCandidateTexts: confirmation.candidateTexts,
            rawCandidates: confirmation.result.rawCandidates,
            candidateScores: Array(confirmation.result.candidateScores.prefix(12)),
            reviewCandidateScores: Array(confirmation.result.reviewCandidateScores.prefix(4)),
            confidence: confirmation.result.confidence,
            recognitionReason: confirmation.decision.reason,
            wasCloseRace: confirmation.decision.isCloseRace,
            confidenceGap: confirmation.decision.confidenceGap,
            targetFraction: confirmation.targetFraction,
            primaryRecognitionAction: confirmation.primaryDecision.action,
            primaryAcceptedText: confirmation.primaryDecision.acceptedText,
            primaryRecognitionReason: confirmation.primaryDecision.reason,
            primaryWasCloseRace: confirmation.primaryDecision.isCloseRace,
            primaryConfidenceGap: confirmation.primaryDecision.confidenceGap,
            recognitionMetrics: confirmation.result.metrics,
            trustEvidence: confirmation.result.trustEvidence,
            symbolLedger: confirmation.result.symbolLedger,
            symbolLedgerAssessment: confirmation.result.symbolLedger?.assessment(
                primaryDisplayText: match.displayText
            ),
            primarySymbolLedgerAssessment: confirmation.result.symbolLedgerAssessment,
            placementEvidence: chartSnapshot.chordEvent(id: chordEventID)
                .map(ChordEntryPlacementEvidence.init(chordEvent:)),
            timingEvidence: timingEvidence
        )

        pendingChordRenderTimingEvidence[chordEventID] = PendingChordRenderTimingEvidence(
            event: event,
            committedAt: commitObservedAt
        )

        do {
            let recorder = ChordEntryDiagnosticsRecorder.live()
            try recorder.append(event)
            try recorder.reconcileRenderedChordEvents(for: chartSnapshot)
        } catch {
            print("iChart chord diagnostic error: \(error)")
        }
    }

    private func recordPendingChordRenderHandoff() {
        guard !pendingChordRenderTimingEvidence.isEmpty else {
            return
        }

        let pendingEvents = pendingChordRenderTimingEvidence
        pendingChordRenderTimingEvidence.removeAll()
        let observedAt = Date()

        do {
            let recorder = ChordEntryDiagnosticsRecorder.live()
            for (chordEventID, pending) in pendingEvents {
                var event = pending.event
                var timingEvidence = event.timingEvidence ?? ChordEntryTimingEvidence(
                    requestedDelayMilliseconds: nil,
                    idleMilliseconds: nil,
                    recognitionMilliseconds: nil,
                    recognitionTotalMilliseconds: nil,
                    proposalDecisionMilliseconds: nil,
                    commitMutationMilliseconds: nil,
                    renderHandoffMilliseconds: nil
                )
                let renderHandoffMilliseconds = observedAt.timeIntervalSince(pending.committedAt) * 1_000
                timingEvidence.renderHandoffMilliseconds = renderHandoffMilliseconds
                event.timestamp = observedAt
                event.timingEvidence = timingEvidence
                try recorder.replaceLatestMatchingEvent(with: event)
                print(
                    String(
                        format: "iChart chord render: renderHandoffMs=%.0f event=%@ accepted=%@",
                        renderHandoffMilliseconds,
                        chordEventID.uuidString,
                        event.acceptedText
                    )
                )
            }
        } catch {
            print("iChart chord render diagnostic error: \(error)")
        }
    }

    private func recordChordCorrectionDiagnostic(
        acceptedText: String,
        match: ChordRecognitionMatch,
        correction: PendingChordCorrection,
        chartSnapshot: Chart
    ) {
        let event = ChordEntryDiagnosticEvent(
            timestamp: .now,
            chartID: chartSnapshot.id,
            chartTitle: chartSnapshot.title,
            measureID: correction.measureID,
            measureIndex: correction.measureIndex,
            chordEventID: correction.chordEventID,
            resolution: .renderedChordCorrection,
            acceptedText: acceptedText,
            previousRenderedDisplayText: correction.currentText,
            renderedDisplayText: match.displayText,
            bestCandidateText: correction.currentText,
            suggestedCandidateTexts: correction.candidateTexts,
            rawCandidates: correction.candidateTexts,
            candidateScores: [],
            confidence: 0,
            recognitionReason: "Rendered chord correction.",
            wasCloseRace: false,
            confidenceGap: nil,
            targetFraction: nil,
            placementEvidence: chartSnapshot.chordEvent(id: correction.chordEventID)
                .map(ChordEntryPlacementEvidence.init(chordEvent:))
        )

        do {
            let recorder = ChordEntryDiagnosticsRecorder.live()
            try recorder.append(event)
            try recorder.reconcileRenderedChordEvents(for: chartSnapshot)
        } catch {
            print("iChart chord diagnostic error: \(error)")
        }
    }

    #endif

    private func scheduleChordEntryDiagnosticReconciliation(for chartSnapshot: Chart) {
        #if DEBUG && targetEnvironment(simulator)
        let hasRenderedChordEvents = chartSnapshot.systems
            .flatMap(\.measures)
            .contains { !$0.chordEvents.isEmpty }
        guard hasRenderedChordEvents else {
            pendingChordDiagnosticReconciliationWorkItem?.cancel()
            pendingChordDiagnosticReconciliationWorkItem = nil
            return
        }

        pendingChordDiagnosticReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            do {
                _ = try ChordEntryDiagnosticsRecorder.live()
                    .reconcileRenderedChordEvents(for: chartSnapshot)
            } catch {
                print("iChart chord diagnostic reconciliation error: \(error)")
            }
        }
        pendingChordDiagnosticReconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private func handleChordInkFixtureCopyRequested(
        _ candidateText: String,
        confirmation: PendingChordInkConfirmation
    ) -> ChordInkFixtureCopyResult {
        let trimmedCandidate = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = ChordRecognitionCompendium.match(trimmedCandidate) else {
            return .failed("Unsupported chord. Use a supported target like C, Bb, F#, C-, C-△7, C△7, C7alt, Db7(b9), or G/B.")
        }

        do {
            let fixtureJSON = try ChordInkFixtureExporter.fixtureJSONString(
                expectedDisplayText: trimmedCandidate,
                drawingData: confirmation.drawingData
            )

            #if canImport(UIKit)
            UIPasteboard.general.string = fixtureJSON
            return .copied(
                displayText: match.displayText,
                fixtureName: ChordInkFixtureExporter.fixtureName(for: trimmedCandidate)
            )
            #else
            return .copied(displayText: fixtureJSON, fixtureName: "clipboard")
            #endif
        } catch {
            return .failed("Could not copy this ink sample. Keep the ink and try again.")
        }
    }
    #endif

    private func handleChordInkRewriteRequested() {
        chordInkAutomaticRewriteFailures.reset()
        clearChordInkForRewrite()
    }

    private func clearChordInkForRewrite() {
        var updatedChart = chart
        _ = updatedChart.setPageHandwrittenChordDrawing(nil)
        chart = updatedChart
        pendingChordInkConfirmation = nil
        pendingChordInkBatchConfirmation = nil
        chordPreviewState.discard()
        canvasMode = .chordEntry
    }

    private func persistChordInkUserCorrectionMemory() {
        do {
            try chordInkUserCorrectionMemoryStore.save(chordInkUserCorrectionMemory)
        } catch {
            #if DEBUG && targetEnvironment(simulator)
            print("iChart chord user correction memory error: \(error)")
            #endif
        }
    }

    private static func renderedChordCorrectionFeedbackKind(
        previousRecognitionText: String,
        previousRenderedText: String,
        acceptedText: String,
        candidateTexts: [String]
    ) -> String {
        let previousRecognitionDisplayText = ChordRecognitionCompendium
            .match(previousRecognitionText)?
            .displayText
        let previousRenderedDisplayText = ChordRecognitionCompendium
            .match(previousRenderedText)?
            .displayText
        let acceptedDisplayText = ChordRecognitionCompendium
            .match(acceptedText)?
            .displayText

        guard previousRecognitionDisplayText == previousRenderedDisplayText else {
            return "display_space_mismatch"
        }
        guard previousRecognitionDisplayText != acceptedDisplayText else {
            return "equivalent_spelling"
        }

        let signature = ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
        return acceptedDisplayText.map(signature.contains) == true
            ? "candidate_replacement"
            : "outside_candidates"
    }

    private func handleNoteSelectionChanged(_ selection: LeadSheetNoteSelection?) {
        guard allowsUserFacingRhythmNoteEditing else {
            selectedNoteSelection = nil
            noteEditMenuStage = .actions
            isNoteEditMenuPresented = false
            return
        }

        selectedNoteSelection = selection
        if selection != nil {
            selectedMeasureID = nil
            noteEditMenuStage = .actions
            isNoteEditMenuPresented = true
        }
    }

    private var selectedRhythmValue: RhythmValue? {
        guard let selectedNoteSelection,
              let values = chart.measure(id: selectedNoteSelection.measureID)?.rhythmMap?.values,
              values.indices.contains(selectedNoteSelection.noteIndex) else {
            return nil
        }

        return values[selectedNoteSelection.noteIndex]
    }

    private func handleSelectedNoteRhythmReplacement(_ rhythmValue: RhythmValue) {
        guard let selectedNoteSelection else {
            noteEditErrorMessage = "Select a rhythm note first, then choose the replacement value."
            showingNoteEditError = true
            isNoteEditMenuPresented = false
            return
        }

        var updatedChart = chart
        let result = updatedChart.replaceMeasureRhythmValue(
            rhythmValue,
            at: selectedNoteSelection.noteIndex,
            in: selectedNoteSelection.measureID
        )

        guard result.didApply else {
            noteEditErrorMessage = noteEditFailureMessage(for: result)
            showingNoteEditError = true
            isNoteEditMenuPresented = false
            return
        }

        chart = updatedChart
        self.selectedNoteSelection = selectedNoteSelection
        noteEditMenuStage = .actions
        isNoteEditMenuPresented = false
    }

    private func noteEditFailureMessage(for result: MeasureRhythmReplacementResult) -> String {
        switch result {
        case .applied, .unchanged:
            return "That rhythm is already selected."
        case .missingMeasure:
            return "That measure is no longer available."
        case .missingRhythmMap:
            return "That note is not part of an editable rhythm sketch yet."
        case .invalidNoteIndex:
            return "That rhythm note is no longer available."
        case .unsupportedRhythmValue:
            return "Choose a single rhythm or rest value."
        case .invalidMeterFit(let status):
            return "That replacement would make the measure \(noteEditStatusDescription(status)). Choose a value with the same duration for now, or adjust the surrounding rhythms first."
        }
    }

    private func noteEditStatusDescription(_ status: MeasureRhythmMapStatus) -> String {
        switch status {
        case .empty:
            return "empty"
        case .exact:
            return "fit"
        case .underfilled(let beats):
            return "short by \(formattedBeatCount(beats)) beats"
        case .overflow(let beats):
            return "over by \(formattedBeatCount(beats)) beats"
        case .invalidSubdivision:
            return "off the measure grid"
        }
    }

    private func editorHorizontalPadding(for _: CGFloat) -> CGFloat {
        return 10
    }

    private func editorVerticalPadding(for height: CGFloat) -> CGFloat {
        height >= 900 ? 20 : 14
    }

    private func canvasHeight(for availableSize: CGSize) -> CGFloat {
        if !chart.hasCompletedInitialSetup {
            return max(760, availableSize.height)
        }

        let visibleSystemCount = LeadSheetPageLayoutEngine.estimatedSystemCount(
            for: chart,
            pageWidth: availableSize.width
        )
        let estimatedCanvasHeight = LeadSheetPageLayoutEngine.estimatedCanvasHeight(
            for: chart,
            pageSize: availableSize
        )
        return max(
            availableSize.height,
            1200,
            estimatedCanvasHeight,
            CGFloat(visibleSystemCount) * 168 + 320
        )
    }

    @ViewBuilder
    private func notationMenuLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func chordTranspositionOptionTitle(_ semitones: Int) -> String {
        Chart.intervalDisplayText(forNormalizedSemitones: semitones)
    }

    private func formattedBeatCount(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }
}

private enum EditorSheet: Identifiable {
    case upgrade(EntitledFeature)
    case export(ExportedPDF)

    var id: String {
        switch self {
        case .upgrade(let feature):
            return "upgrade-\(feature.id)"
        case .export(let exportedPDF):
            return "export-\(exportedPDF.id.absoluteString)"
        }
    }
}

enum ChordDiagnosticPreviewScrollPolicy {
    #if canImport(UIKit)
    static var allowedTouchTypes: [NSNumber] {
        allowedTouchTypes()
    }

    static func allowedTouchTypes(
        environment: LeadSheetLiveInkInputPolicy.RuntimeEnvironment = .current
    ) -> [NSNumber] {
        switch environment {
        case .device:
            return [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        case .simulator:
            return [
                NSNumber(value: UITouch.TouchType.direct.rawValue),
                NSNumber(value: UITouch.TouchType.pencil.rawValue)
            ]
        }
    }
    #endif

    static func isScrollEnabled(itemCount: Int) -> Bool {
        itemCount > 0
    }
}

private struct ChordDiagnosticPreviewStrip: View {
    let items: [ChordDiagnosticPreviewItem]

    var body: some View {
        ChordDiagnosticPreviewPencilScrollView(
            isScrollEnabled: ChordDiagnosticPreviewScrollPolicy.isScrollEnabled(itemCount: items.count)
        ) {
            ChordDiagnosticPreviewStripContent(items: items)
        }
        .frame(
            width: ChordDiagnosticPreviewMetrics.stripWidth,
            height: ChordDiagnosticPreviewMetrics.stripHeight,
            alignment: .leading
        )
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .foregroundStyle(Color.primary)
    }
}

private struct ChordDiagnosticPreviewStripContent: View {
    let items: [ChordDiagnosticPreviewItem]

    var body: some View {
        HStack(spacing: ChordDiagnosticPreviewMetrics.itemSpacing) {
            if items.isEmpty {
                Text("-")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: ChordDiagnosticPreviewMetrics.placeholderWidth)
            } else {
                ForEach(items) { item in
                    switch item.kind {
                    case .chord(let text):
                        Text(text)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 7)
                            .frame(minWidth: ChordDiagnosticPreviewMetrics.chordMinWidth, minHeight: 28)
                            .background(Color.primary.opacity(0.055))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    case .barline:
                        Text("|")
                            .font(.title3.weight(.semibold))
                            .frame(width: ChordDiagnosticPreviewMetrics.barlineWidth, height: 28)
                    }
                }
            }
        }
        .padding(.horizontal, ChordDiagnosticPreviewMetrics.horizontalInset)
        .frame(minWidth: ChordDiagnosticPreviewMetrics.stripWidth, alignment: .leading)
    }
}

private struct ChordDiagnosticPreviewPencilScrollView<Content: View>: View {
    let isScrollEnabled: Bool
    private let content: Content

    init(isScrollEnabled: Bool, @ViewBuilder content: () -> Content) {
        self.isScrollEnabled = isScrollEnabled
        self.content = content()
    }

    var body: some View {
        #if canImport(UIKit)
        ChordDiagnosticPreviewUIKitScrollView(
            isScrollEnabled: isScrollEnabled,
            content: content
        )
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            content
        }
        .scrollDisabled(!isScrollEnabled)
        #endif
    }
}

#if canImport(UIKit)
private struct ChordDiagnosticPreviewUIKitScrollView<Content: View>: UIViewRepresentable {
    let isScrollEnabled: Bool
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = isScrollEnabled
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.panGestureRecognizer.allowedTouchTypes = ChordDiagnosticPreviewScrollPolicy.allowedTouchTypes

        let hostingView = context.coordinator.hostingController.view!
        hostingView.backgroundColor = .clear
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        context.coordinator.hostingController.view.invalidateIntrinsicContentSize()
        scrollView.isScrollEnabled = isScrollEnabled
        scrollView.alwaysBounceHorizontal = isScrollEnabled
        scrollView.panGestureRecognizer.allowedTouchTypes = ChordDiagnosticPreviewScrollPolicy.allowedTouchTypes
    }

    final class Coordinator {
        let hostingController: UIHostingController<Content>

        init(content: Content) {
            hostingController = UIHostingController(rootView: content)
            hostingController.sizingOptions = .intrinsicContentSize
        }
    }
}
#endif

private struct ChordDiagnosticPreviewItem: Identifiable {
    enum Kind {
        case chord(String)
        case barline
    }

    let id: String
    let visualOrder: Double
    let kind: Kind
}

private enum ChordDiagnosticPreviewMetrics {
    static let stripWidth: CGFloat = 216
    static let stripHeight: CGFloat = 42
    static let chordMinWidth: CGFloat = 32
    static let placeholderWidth: CGFloat = 32
    static let barlineWidth: CGFloat = 16
    static let itemSpacing: CGFloat = 8
    static let horizontalInset: CGFloat = 7
    static let nonScrollingItemCount = 5
    static let statusWidth: CGFloat = 136
}

private struct RhythmDiagnosticPreviewStrip: View {
    let values: [RhythmValue]
    let meter: Meter
    let tieOutSlotIndices: Set<Int>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                HStack(spacing: RhythmDiagnosticPreviewMetrics.glyphSpacing) {
                    if values.isEmpty {
                        RhythmDiagnosticPreviewStaffPlaceholder()
                    } else {
                        ForEach(Array(RhythmDiagnosticPreviewItem.items(for: values, meter: meter).enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .single(let value):
                                RhythmDiagnosticPreviewGlyph(value: value)
                            case .beamedGroup(let values):
                                RhythmDiagnosticPreviewBeamedGroup(values: values)
                            }
                        }
                    }
                }
                .padding(.horizontal, RhythmDiagnosticPreviewMetrics.horizontalInset)

                RhythmDiagnosticTieOverlay(
                    values: values,
                    tieOutSlotIndices: tieOutSlotIndices
                )
            }
            .frame(minWidth: RhythmDiagnosticPreviewMetrics.stripWidth, alignment: .leading)
        }
        .scrollDisabled(values.count <= RhythmDiagnosticPreviewMetrics.nonScrollingGlyphCount)
        .frame(
            width: RhythmDiagnosticPreviewMetrics.stripWidth,
            height: RhythmDiagnosticPreviewMetrics.stripHeight,
            alignment: .leading
        )
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .foregroundStyle(Color.primary)
    }
}

private enum RhythmDiagnosticPreviewMetrics {
    static let stripWidth: CGFloat = 216
    static let stripHeight: CGFloat = 42
    static let glyphWidth: CGFloat = 30
    static let glyphHeight: CGFloat = 42
    static let glyphSpacing: CGFloat = 8
    static let horizontalInset: CGFloat = 7
    static let nonScrollingGlyphCount = 5
    static let statusWidth: CGFloat = 178
    static let notePointSize: CGFloat = 30
    static let wholeNotePointSize: CGFloat = 26
    static let restPointSize: CGFloat = 27
    static let restBlockPointSize: CGFloat = 23
    static let slashPointSize: CGFloat = 27
    static let dotSize: CGFloat = 5
    static let glyphVerticalOffset: CGFloat = -2
    static let noteVerticalOffset: CGFloat = -13
    static let wholeNoteVerticalOffset: CGFloat = -9
    static let beamedGlyphAdvance: CGFloat = 27
    static let beamedDottedTrailingAllowance: CGFloat = 10
    static let beamedDotRightPadding: CGFloat = 1.5
    static let beamedStemWidth: CGFloat = 1.5
    static let beamThickness: CGFloat = 4
    static let tieHeight: CGFloat = 6
    static let tieYOffset: CGFloat = -1
}

private enum RhythmDiagnosticPreviewItem {
    case single(RhythmValue)
    case beamedGroup([RhythmValue])

    static func items(for values: [RhythmValue], meter: Meter) -> [RhythmDiagnosticPreviewItem] {
        var items: [RhythmDiagnosticPreviewItem] = []
        var index = 0

        while index < values.count {
            let value = values[index]
            guard value.isDiagnosticPreviewBeamable else {
                items.append(.single(value))
                index += 1
                continue
            }

            var endIndex = index + 1
            while endIndex < values.count,
                  RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                    beforeValueAt: endIndex,
                    in: values,
                    meter: meter
                  ) {
                endIndex += 1
            }

            let groupValues = Array(values[index..<endIndex])
            if groupValues.count > 1 {
                items.append(.beamedGroup(groupValues))
            } else {
                items.append(.single(value))
            }
            index = endIndex
        }

        return items
    }
}

private extension RhythmValue {
    var isDiagnosticPreviewBeamable: Bool {
        switch self {
        case .eighth, .dottedEighth, .sixteenth:
            return true
        case .slash, .sixteenthRest, .eighthRest, .quarter, .quarterRest, .dottedQuarterRest, .dottedQuarter,
             .half, .halfRest, .dottedHalf, .whole, .wholeRest, .measureRepeat, .tiedContinuation:
            return false
        }
    }
}

private struct RhythmDiagnosticPreviewStaffPlaceholder: View {
    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(Color.primary.opacity(0.16))
                    .frame(height: 1)
            }
        }
        .frame(
            width: RhythmDiagnosticPreviewMetrics.stripWidth - RhythmDiagnosticPreviewMetrics.horizontalInset * 2,
            height: RhythmDiagnosticPreviewMetrics.stripHeight
        )
    }
}

private struct RhythmDiagnosticPreviewGlyph: View {
    let value: RhythmValue

    var body: some View {
        ZStack {
            switch value {
            case .wholeRest:
                RhythmRestBlockContextPreview(
                    value: .wholeRest,
                    width: glyphFrameWidth,
                    height: RhythmDiagnosticPreviewMetrics.glyphHeight,
                    staffLineWidth: 30,
                    blockWidth: 18,
                    blockHeight: 5,
                    staffLineOpacity: 0.32
                )
            case .halfRest:
                RhythmRestBlockContextPreview(
                    value: .halfRest,
                    width: glyphFrameWidth,
                    height: RhythmDiagnosticPreviewMetrics.glyphHeight,
                    staffLineWidth: 30,
                    blockWidth: 18,
                    blockHeight: 5,
                    staffLineOpacity: 0.32
                )
            case .quarterRest:
                symbol(.quarterRest, size: RhythmDiagnosticPreviewMetrics.restPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset)
            case .dottedQuarterRest:
                symbol(.quarterRest, size: RhythmDiagnosticPreviewMetrics.restPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset)
                dot
            case .eighthRest:
                symbol(.eighthRest, size: RhythmDiagnosticPreviewMetrics.restPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset + 1)
            case .sixteenthRest:
                symbol(.sixteenthRest, size: RhythmDiagnosticPreviewMetrics.restPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset - 4)
            case .whole:
                symbol(.noteWhole, size: RhythmDiagnosticPreviewMetrics.wholeNotePointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.wholeNoteVerticalOffset)
            case .measureRepeat:
                Text(ChordSymbol.chordRepeatDisplayText)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset + 2)
            case .half:
                noteSymbol(.noteHalfDown)
            case .dottedHalf:
                noteSymbol(.noteHalfDown)
                dot
            case .slash:
                symbol(.slashNotehead, size: RhythmDiagnosticPreviewMetrics.slashPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset)
            case .quarter:
                noteSymbol(.noteQuarterDown)
            case .dottedQuarter:
                noteSymbol(.noteQuarterDown)
                dot
            case .dottedEighth:
                noteSymbol(.note8thDown)
                dot
            case .eighth:
                noteSymbol(.note8thDown)
            case .sixteenth:
                noteSymbol(.note16thDown)
            case .tiedContinuation:
                RhythmDiagnosticTieShape()
                    .stroke(Color.primary, lineWidth: 1.4)
                    .frame(width: 24, height: 12)
                    .offset(y: -3)
            }
        }
        .frame(
            width: glyphFrameWidth,
            height: RhythmDiagnosticPreviewMetrics.glyphHeight
        )
        .clipped()
    }

    private func noteSymbol(_ symbol: NotationGlyphCatalog.Symbol) -> some View {
        self.symbol(symbol, size: RhythmDiagnosticPreviewMetrics.notePointSize)
            .offset(x: 1, y: RhythmDiagnosticPreviewMetrics.noteVerticalOffset)
    }

    private var dot: some View {
        Circle()
            .fill(Color.primary)
            .frame(
                width: RhythmDiagnosticPreviewMetrics.dotSize,
                height: RhythmDiagnosticPreviewMetrics.dotSize
            )
            .offset(x: 13, y: dotYOffset)
    }

    private func symbol(_ symbol: NotationGlyphCatalog.Symbol, size: CGFloat) -> Text {
        Text(NotationGlyphCatalog.glyph(for: symbol) ?? "")
            .font(NotationFontPreset.bravura.notationPreviewFont(size: size))
    }

    private var glyphFrameWidth: CGFloat {
        if value == .wholeRest || value == .halfRest {
            return RhythmDiagnosticPreviewMetrics.glyphWidth + 10
        }

        return value.isDottedReferenceValue
            ? RhythmDiagnosticPreviewMetrics.glyphWidth + 6
            : RhythmDiagnosticPreviewMetrics.glyphWidth
    }

    private var dotYOffset: CGFloat {
        switch value {
        case .dottedQuarter:
            return RhythmDiagnosticPreviewMetrics.noteVerticalOffset + 5
        case .dottedQuarterRest:
            return RhythmDiagnosticPreviewMetrics.glyphVerticalOffset + 5
        case .dottedEighth, .dottedHalf:
            return RhythmDiagnosticPreviewMetrics.noteVerticalOffset + 8
        case .slash, .sixteenth, .sixteenthRest, .eighth, .eighthRest, .quarter, .quarterRest,
             .half, .halfRest, .whole, .wholeRest, .measureRepeat, .tiedContinuation:
            return RhythmDiagnosticPreviewMetrics.glyphVerticalOffset + 8
        }
    }
}

private struct RhythmDiagnosticPreviewBeamedGroup: View {
    let values: [RhythmValue]

    var body: some View {
        RhythmDiagnosticPreviewBeamedShape(values: values)
            .fill(Color.primary)
            .accessibilityHidden(true)
            .frame(
                width: previewWidth,
                height: RhythmDiagnosticPreviewMetrics.glyphHeight
            )
            .clipped()
    }

    private var previewWidth: CGFloat {
        let baseWidth = CGFloat(max(2, values.count)) * RhythmDiagnosticPreviewMetrics.beamedGlyphAdvance
        guard values.last == .dottedEighth else {
            return baseWidth
        }
        return baseWidth + RhythmDiagnosticPreviewMetrics.beamedDottedTrailingAllowance
    }
}

private struct RhythmDiagnosticPreviewBeamedShape: Shape {
    let values: [RhythmValue]

    func path(in rect: CGRect) -> Path {
        let noteCount = max(2, values.count)
        let trailingDotAllowance = values.prefix(noteCount).last == .dottedEighth
            ? RhythmDiagnosticPreviewMetrics.beamedDottedTrailingAllowance
            : 0
        let contentRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(1, rect.width - trailingDotAllowance),
            height: rect.height
        )
        let advance = contentRect.width / CGFloat(noteCount)
        let stemWidth = RhythmDiagnosticPreviewMetrics.beamedStemWidth
        let beamThickness = RhythmDiagnosticPreviewMetrics.beamThickness
        let beamY = contentRect.maxY - 25
        let headWidth = min(11, advance * 0.42)
        let headHeight = max(11, contentRect.height * 0.27)
        let headCenterY = contentRect.minY + contentRect.height * 0.05
        let stemAnchorRatio: CGFloat = 0.66
        let firstStemX = contentRect.minX + advance * stemAnchorRatio
        let lastStemX = contentRect.minX + CGFloat(noteCount - 1) * advance + advance * stemAnchorRatio

        var path = Path()
        path.addRect(CGRect(
            x: firstStemX,
            y: beamY,
            width: max(stemWidth, lastStemX - firstStemX + stemWidth),
            height: beamThickness
        ))
        path.addPath(secondaryBeamPath(
            in: contentRect,
            advance: advance,
            stemAnchorRatio: stemAnchorRatio,
            stemWidth: stemWidth,
            beamY: beamY - beamThickness - 3,
            beamThickness: max(beamThickness * 0.82, 2.5)
        ))

        for index in 0..<noteCount {
            let originX = contentRect.minX + CGFloat(index) * advance
            let stemX = originX + advance * stemAnchorRatio
            path.addRect(CGRect(
                x: stemX,
                y: headCenterY,
                width: stemWidth,
                height: max(1, beamY - headCenterY)
            ))
            path.addEllipse(in: CGRect(
                x: stemX - headWidth + stemWidth,
                y: headCenterY - headHeight / 2,
                width: headWidth,
                height: headHeight
            ))
            if values.indices.contains(index),
               values[index] == .dottedEighth {
                let dotSize = min(5, max(3.5, headWidth * 0.46))
                let dotX = min(
                    stemX + dotSize * 1.3,
                    rect.maxX - dotSize - RhythmDiagnosticPreviewMetrics.beamedDotRightPadding
                )
                path.addEllipse(in: CGRect(
                    x: dotX,
                    y: headCenterY - dotSize * 0.55,
                    width: dotSize,
                    height: dotSize
                ))
            }
        }

        return path
    }

    private func secondaryBeamPath(
        in rect: CGRect,
        advance: CGFloat,
        stemAnchorRatio: CGFloat,
        stemWidth: CGFloat,
        beamY: CGFloat,
        beamThickness: CGFloat
    ) -> Path {
        var path = Path()
        let noteCount = max(2, values.count)
        let normalizedValues = Array(values.prefix(noteCount))

        func stemX(at index: Int) -> CGFloat {
            rect.minX + CGFloat(index) * advance + advance * stemAnchorRatio
        }

        var index = 0
        while index < normalizedValues.count {
            guard normalizedValues[index] == .sixteenth else {
                index += 1
                continue
            }

            let runStart = index
            while index < normalizedValues.count,
                  normalizedValues[index] == .sixteenth {
                index += 1
            }
            let runEnd = index - 1

            if runEnd > runStart {
                let startX = stemX(at: runStart)
                let endX = stemX(at: runEnd)
                path.addRect(CGRect(
                    x: startX,
                    y: beamY,
                    width: max(stemWidth, endX - startX + stemWidth),
                    height: beamThickness
                ))
            } else {
                let anchorX = stemX(at: runStart)
                let pointsRight = runStart == 0 || runStart < normalizedValues.count - 1
                let width = min(advance * 0.72, 20)
                path.addRect(CGRect(
                    x: pointsRight ? anchorX : anchorX - width + stemWidth,
                    y: beamY,
                    width: width,
                    height: beamThickness
                ))
            }
        }

        return path
    }
}

private struct RhythmDiagnosticTieShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}

private struct RhythmDiagnosticTieOverlay: View {
    let values: [RhythmValue]
    let tieOutSlotIndices: Set<Int>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(validTieIndices, id: \.self) { index in
                RhythmDiagnosticTieShape()
                    .stroke(Color.primary, lineWidth: 1.35)
                    .frame(
                        width: tieWidth(from: index),
                        height: RhythmDiagnosticPreviewMetrics.tieHeight
                    )
                    .offset(
                        x: tieStartX(from: index),
                        y: RhythmDiagnosticPreviewMetrics.tieYOffset
                    )
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }

    private var validTieIndices: [Int] {
        tieOutSlotIndices
            .filter { index in
                values.indices.contains(index)
                    && values.indices.contains(index + 1)
                    && values[index].supportsPitchedLeadSheetNote
                    && values[index + 1].supportsPitchedLeadSheetNote
            }
            .sorted()
    }

    private func tieStartX(from index: Int) -> CGFloat {
        glyphLeadingX(at: index) + glyphWidth(at: index) * 0.55
    }

    private func tieWidth(from index: Int) -> CGFloat {
        let startX = tieStartX(from: index)
        let endX = glyphLeadingX(at: index + 1) + glyphWidth(at: index + 1) * 0.45
        return max(CGFloat(18), endX - startX)
    }

    private func glyphLeadingX(at index: Int) -> CGFloat {
        let precedingWidths = values.prefix(index).reduce(CGFloat(0)) { partialResult, value in
            partialResult + glyphWidth(for: value)
        }
        let precedingSpacing = CGFloat(index) * RhythmDiagnosticPreviewMetrics.glyphSpacing
        return RhythmDiagnosticPreviewMetrics.horizontalInset + precedingWidths + precedingSpacing
    }

    private func glyphWidth(at index: Int) -> CGFloat {
        guard values.indices.contains(index) else {
            return RhythmDiagnosticPreviewMetrics.glyphWidth
        }
        return glyphWidth(for: values[index])
    }

    private func glyphWidth(for value: RhythmValue) -> CGFloat {
        value.isDottedReferenceValue
            ? RhythmDiagnosticPreviewMetrics.glyphWidth + 6
            : RhythmDiagnosticPreviewMetrics.glyphWidth
    }
}

private struct PendingTimeSignaturePlacement: Identifiable {
    let id = UUID()
    let sourceMeasureID: UUID
    let meter: Meter
}

private enum NoteEditMenuStage: Hashable {
    case actions
    case rhythm
}

private struct NoteEditPopoverView: View {
    @Binding var stage: NoteEditMenuStage
    let notationFont: NotationFontPreset
    let selectedRhythmValue: RhythmValue?
    let onSelectRhythm: (RhythmValue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch stage {
            case .actions:
                actionMenu
            case .rhythm:
                rhythmMenu
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    private var actionMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Note")
                .font(.headline)

            Button {
                stage = .rhythm
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .frame(width: 24)
                    Text("Rhythm")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var rhythmMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                stage = .actions
            } label: {
                Label("Edit Note", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(RhythmValue.singularEditPalette, id: \.self) { rhythmValue in
                        Button {
                            onSelectRhythm(rhythmValue)
                        } label: {
                            RhythmEditChoiceRow(
                                value: rhythmValue,
                                notationFont: notationFont,
                                isSelected: selectedRhythmValue == rhythmValue
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 390)
        }
    }
}

private struct RhythmEditChoiceRow: View {
    let value: RhythmValue
    let notationFont: NotationFontPreset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            RhythmValueGlyphPreview(value: value, notationFont: notationFont)
                .frame(width: 48, height: 36)

            Text(value.referenceDisplayTitle)
                .font(.subheadline.weight(.semibold))

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

enum CueTextEntryPanelGeometry {
    static let maximumWidth: CGFloat = 420
    static let horizontalMargin: CGFloat = 20
    static let headerHeight: CGFloat = 36
    static let inputHeight: CGFloat = 72
    static let verticalSpacing: CGFloat = 10
    static let verticalPadding: CGFloat = 14
    static let panelHeight = headerHeight + inputHeight + verticalSpacing + verticalPadding * 2

    static func panelWidth(for availableWidth: CGFloat) -> CGFloat {
        min(maximumWidth, max(1, availableWidth - horizontalMargin * 2))
    }
}

private struct CueTextEntryPanelView: View {
    @Binding var text: String
    let actionTitle: String
    var highlightsAction = false
    let onAdd: () -> Void
    let onCancel: () -> Void
    @State private var keyboardFocusRequestID = 0

    private var canAdd: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Keep outside taps routed back to the editor without visually
                // turning the entire iPad canvas into a modal text surface.
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        requestTextFocus()
                    }

                VStack(alignment: .leading, spacing: CueTextEntryPanelGeometry.verticalSpacing) {
                    HStack {
                        PencilOnlyActionButton(title: "Cancel", style: .plain) {
                            onCancel()
                        }

                        Spacer()

                        Text("Text")
                            .font(.headline.weight(.semibold))

                        Spacer()

                        PencilOnlyActionButton(
                            title: actionTitle,
                            style: .plain,
                            isEnabled: canAdd
                        ) {
                            onAdd()
                        }
                        .tourActionHighlight(
                            isActive: highlightsAction && canAdd,
                            cornerRadius: 8
                        )
                    }
                    // UIKit-backed buttons otherwise accept the full vertical
                    // proposal from this overlay and stretch the panel on iPad.
                    .frame(height: CueTextEntryPanelGeometry.headerHeight)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator).opacity(0.55), lineWidth: 1)
                            )

                        if text.isEmpty {
                            Text("Text")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .allowsHitTesting(false)
                        }

                        CueTextInputView(
                            text: $text,
                            keyboardFocusRequestID: keyboardFocusRequestID
                        )
                        .accessibilityLabel("Text")
                    }
                    .frame(height: CueTextEntryPanelGeometry.inputHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture {
                        requestTextFocus()
                    }
                }
                .padding(CueTextEntryPanelGeometry.verticalPadding)
                .frame(
                    width: CueTextEntryPanelGeometry.panelWidth(for: proxy.size.width),
                    height: CueTextEntryPanelGeometry.panelHeight,
                    alignment: .top
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 22, y: 12)
            }
        }
        .task {
            requestTextFocus()
        }
    }

    private func requestTextFocus() {
        keyboardFocusRequestID += 1
    }
}

#if canImport(UIKit)
private struct CueTextInputView: UIViewRepresentable {
    @Binding var text: String
    let keyboardFocusRequestID: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.keyboardDismissMode = .interactive
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text

        if textView.text != text {
            textView.text = text
        }

        guard keyboardFocusRequestID > 0,
              context.coordinator.lastKeyboardFocusRequestID != keyboardFocusRequestID
        else {
            return
        }

        context.coordinator.lastKeyboardFocusRequestID = keyboardFocusRequestID
        DispatchQueue.main.async {
            textView.resignFirstResponder()
            textView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var lastKeyboardFocusRequestID = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
#endif

private struct MeasureStackInsertionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    var highlightsAddAction = false
    let onAdd: (Int) -> Void
    let onCancel: () -> Void

    @State private var measureCount = 4

    var body: some View {
        NavigationStack {
            Form {
                Section("Measures") {
                    Stepper(value: $measureCount, in: 1...64) {
                        HStack {
                            Text("Measure Count")
                            Spacer()
                            Text("\(measureCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 10) {
                        ForEach([2, 4, 8, 16], id: \.self) { preset in
                            Button {
                                measureCount = preset
                            } label: {
                                Text("\(preset)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle("Measure Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onAdd(measureCount)
                        dismiss()
                    }
                    .tourActionHighlight(
                        isActive: highlightsAddAction,
                        cornerRadius: 8
                    )
                }
            }
        }
        .presentationDetents([.height(260), .medium])
    }
}

private struct TimeSignatureScopeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let meter: Meter
    var highlightsApplyActions = false
    let onApplyCount: (Int) -> Void
    let onApplyToEndOfPiece: () -> Void
    let onApplyToNextTimeSignature: () -> Void

    @State private var additionalMeasureCount = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add measures in this time signature?")
                        .font(.headline)
                    Text("The new \(meter.displayText) starts on the selected measure.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $additionalMeasureCount, in: 0...32) {
                    HStack {
                        Text("Additional measures")
                        Spacer()
                        Text("\(additionalMeasureCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    onApplyCount(additionalMeasureCount)
                    dismiss()
                } label: {
                    Text("Apply Measure Count")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tourActionHighlight(
                    isActive: highlightsApplyActions,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Or choose a span")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        bubbleButton(title: "To next time signature") {
                            onApplyToNextTimeSignature()
                            dismiss()
                        }

                        bubbleButton(title: "To end of piece") {
                            onApplyToEndOfPiece()
                            dismiss()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Apply \(meter.displayText)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
    }

    @ViewBuilder
    private func bubbleButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.90, green: 0.95, blue: 1.0))
                .foregroundStyle(Color(red: 0.11, green: 0.31, blue: 0.64))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .tourActionHighlight(
            isActive: highlightsApplyActions,
            cornerRadius: 18
        )
    }
}

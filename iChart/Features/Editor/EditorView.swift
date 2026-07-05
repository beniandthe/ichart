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

private enum ChordToolInputMode: String, CaseIterable, Identifiable {
    case read
    case inkOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read:
            return "Read"
        case .inkOnly:
            return "Ink Only"
        }
    }

    var systemImageName: String {
        switch self {
        case .read:
            return "text.viewfinder"
        case .inkOnly:
            return "pencil.and.scribble"
        }
    }

    var recognizesChordInk: Bool {
        self == .read
    }
}

private enum IChartEditorGuidedTourStep: String, Identifiable {
    case setup
    case chordWrite
    case chordConfirm
    case chordDone
    case page
    case measures
    case measuresActive
    case repeatsActive
    case coda
    case freeHandActive
    case select

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup:
            "Create The Page"
        case .chordWrite:
            "Write A Chord"
        case .chordConfirm:
            "Confirm The Chord"
        case .chordDone:
            "Leave Chord Mode"
        case .page:
            "Page"
        case .measures:
            "Measures"
        case .measuresActive:
            "Measures Row"
        case .repeatsActive:
            "Repeats Row"
        case .coda:
            "Coda"
        case .freeHandActive:
            "Free-Hand"
        case .select:
            "Select And Finish"
        }
    }

    var message: String {
        switch self {
        case .setup:
            "Confirm the page setup, time signature, starting measure count, and sheet style. Create Blank Page opens the chart for the hands-on tour."
        case .chordWrite:
            "Use the chord lane above the measure. Write a chord, then tap outside the lane to read it. Use Ink Only when the chord should stay handwritten."
        case .chordConfirm:
            "Tap the chord you meant. Keyboard opens manual entry, Keep Ink leaves handwriting in place, and Rewrite clears the attempt."
        case .chordDone:
            "Tap Done to leave Chord mode and return to Select before using the other editor tools."
        case .page:
            "Page holds whole-chart actions: Setup, Export, Header, Instrument Transposition, Transpose, Style, Fonts, Pen Responsiveness, and Engraving."
        case .measures:
            "Measures is for layout only. Select a measure, then use Add, Stack, First, Double, New Row or Join, Delete, and Range."
        case .measuresActive:
            "Measure actions affect the selected measure. Add and Stack insert measures, New Row and Join control row flow, and Range deletes a span."
        case .repeatsActive:
            "Repeats is for repeat structure. Use One Bar, Start, End Rep, 1st and 2nd endings, Remove Repeat, Remove Ending, and Clear."
        case .coda:
            "Coda is for point roadmap markers: Coda, To Coda, Segno, D.S., D.S. al Coda, D.C., D.C. al Fine, Fine, and N.C. In Select, drag a marker or tap its x to delete it."
        case .freeHandActive:
            "Free-Hand is raw page ink for quick marks, notes, and cues. It does not attach to measures or create movable symbols; erase and rewrite it manually."
        case .select:
            "Select is the resting mode for scrolling, choosing rendered objects, editing text or markers, and returning to Page for setup or export."
        }
    }

    var targetText: String? {
        switch self {
        case .setup:
            "Tap Create Blank Page"
        case .chordWrite:
            "Write a chord, then tap outside the lane"
        case .chordConfirm:
            "Tap a chord choice"
        case .chordDone:
            "Tap Done"
        case .page:
            "Tap Page"
        case .measures:
            "Tap Measures"
        case .measuresActive:
            "Tap Repeats"
        case .repeatsActive:
            "Tap Coda"
        case .coda:
            "Tap Free-Hand"
        case .freeHandActive:
            "Tap Done"
        case .select:
            nil
        }
    }

    var contentPromptAlignment: Alignment {
        switch self {
        case .setup:
            .bottomTrailing
        case .chordWrite, .chordConfirm, .select:
            .bottomTrailing
        case .chordDone, .page, .measures, .measuresActive, .repeatsActive, .coda, .freeHandActive:
            .bottomLeading
        }
    }

    var contentPromptPadding: EdgeInsets {
        switch self {
        case .setup:
            EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24)
        case .chordWrite, .chordConfirm, .chordDone, .page, .measures, .measuresActive, .repeatsActive, .coda, .freeHandActive, .select:
            EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24)
        }
    }
}

private struct IChartEditorGuidedTourPrompt: View {
    let step: IChartEditorGuidedTourStep
    let onFinish: () -> Void

    private let accent = Color(red: 0.13, green: 0.42, blue: 0.54)
    private let paper = Color(red: 0.97, green: 0.95, blue: 0.92)
    private let ink = Color(red: 0.08, green: 0.10, blue: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ink)

                    Text(step.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let targetText = step.targetText {
                Label(targetText, systemImage: "hand.tap")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.86, green: 0.93, blue: 0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 10) {
                if step == .select {
                    Button("Finish Tour", action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                }

                Button("Skip Tour", action: onFinish)
                    .buttonStyle(.bordered)
                    .tint(accent)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .background(paper.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ink.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: ink.opacity(0.12), radius: 16, y: 8)
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
    @State private var showingInkResponsivenessSheet = false
    @State private var isExporting = false
    @State private var activeEditorOperationMessage: String?
    @State private var activeEditorOperationID = UUID()
    @State private var selectedMeasureID: UUID?
    @State private var selectedNoteSelection: LeadSheetNoteSelection?
    @State private var selectedCueTextID: UUID?
    @State private var selectedRoadmapMarkerID: UUID?
    @State private var isNoteEditMenuPresented = false
    @State private var noteEditMenuStage: NoteEditMenuStage = .actions
    @State private var noteEditErrorMessage = ""
    @State private var showingNoteEditError = false
    @State private var pendingChordInkConfirmation: PendingChordInkConfirmation?
    @State private var pendingChordInkBatchConfirmation: PendingChordInkBatchConfirmation?
    @State private var pendingChordCorrection: PendingChordCorrection?
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
    @State private var chordToolInputMode: ChordToolInputMode = .read
    @State private var editorGuidedTourStep: IChartEditorGuidedTourStep?
    @State private var pendingChordDiagnosticReconciliationWorkItem: DispatchWorkItem?
    @State private var latestRhythmPreview: LeadSheetRhythmicNotationPreviewState?
    @State private var rhythmPreviewConfirmationRequestID: UUID?
    @AppStorage("iChartPendingSimpleChartTour") private var pendingSimpleChartTour = false
    @AppStorage(LeadSheetInkResponsivenessPolicy.storageKey)
    private var inkResponsivenessValue = LeadSheetInkResponsivenessPolicy.defaultValue
    private let exporter: any ChartExporting
    private let chordInkUserCorrectionMemoryStore: ChordInkUserCorrectionMemoryStore
    private let onExit: (() -> Void)?

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
        _canvasMode = State(initialValue: initialCanvasMode)
        _chordInkUserCorrectionMemory = State(
            initialValue: (try? chordInkUserCorrectionMemoryStore.load()) ?? ChordInkUserCorrectionMemory()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            editorNavigationChrome

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
        .overlay(alignment: editorGuidedTourStep?.contentPromptAlignment ?? .topTrailing) {
            if let editorGuidedTourStep, editorGuidedTourStep != .setup {
                IChartEditorGuidedTourPrompt(
                    step: editorGuidedTourStep,
                    onFinish: finishEditorGuidedTour
                )
                .padding(editorGuidedTourStep.contentPromptPadding)
            }
        }
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
            ZStack(alignment: .bottomTrailing) {
                ChartSetupSheetView(chart: $chart)

                if editorGuidedTourStep == .setup {
                    IChartEditorGuidedTourPrompt(
                        step: .setup,
                        onFinish: finishEditorGuidedTour
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
        }
        .sheet(isPresented: $showingHeaderSheet) {
            ChartHeaderSheetView(chart: $chart)
        }
        .sheet(isPresented: $showingTypographySheet) {
            ChartTypographySheetView(chart: $chart)
        }
        .sheet(isPresented: $showingInkResponsivenessSheet) {
            InkResponsivenessSheetView(value: $inkResponsivenessValue)
        }
        .sheet(item: $pendingMeasureStackInsertion) { insertion in
            MeasureStackInsertionSheetView(
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
            Text("Apply the new time signature after the selected measure.")
        }
        .sheet(item: $pendingTimeSignaturePlacement) { placement in
            TimeSignatureScopeSheetView(
                meter: placement.meter,
                onApplyCount: { additionalMeasureCount in
                    handleTimeSignatureSelection(
                        placement.meter,
                        after: placement.sourceMeasureID,
                        scope: .fixedMeasureCount(additionalMeasureCount)
                    )
                },
                onApplyToEndOfPiece: {
                    handleTimeSignatureSelection(
                        placement.meter,
                        after: placement.sourceMeasureID,
                        scope: .toEndOfPiece
                    )
                },
                onApplyToNextTimeSignature: {
                    handleTimeSignatureSelection(
                        placement.meter,
                        after: placement.sourceMeasureID,
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
        .onChange(of: canvasMode) { _, mode in
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
            advanceEditorGuidedTourIfNeeded(for: mode)
        }
        .onChange(of: chart) { _, updatedChart in
            scheduleChordEntryDiagnosticReconciliation(for: updatedChart)
            advanceEditorGuidedTourAfterSetupIfNeeded(updatedChart)
            #if DEBUG || targetEnvironment(simulator)
            recordPendingChordRenderHandoff()
            #endif
        }
        .onDisappear {
            pendingChordDiagnosticReconciliationWorkItem?.cancel()
            pendingChordDiagnosticReconciliationWorkItem = nil
        }
        .task {
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
            canvasMode = .chordEntry
            editorGuidedTourStep = .chordWrite
        } else {
            editorGuidedTourStep = .setup
        }
    }

    private func advanceEditorGuidedTourIfNeeded(for mode: EditorCanvasMode) {
        switch (editorGuidedTourStep, mode) {
        case (.chordDone, .browse):
            editorGuidedTourStep = .page
        case (.page, .measureEdit):
            editorGuidedTourStep = .measuresActive
        case (.page, .browse):
            editorGuidedTourStep = .measures
        case (.measures, .measureEdit):
            editorGuidedTourStep = .measuresActive
        case (.measuresActive, .repeatEdit):
            editorGuidedTourStep = .repeatsActive
        case (.coda, .freeHand):
            editorGuidedTourStep = .freeHandActive
        case (.freeHandActive, .browse):
            editorGuidedTourStep = .select
        default:
            break
        }
    }

    private func advanceEditorGuidedTourAfterPageToolTapIfNeeded() {
        guard editorGuidedTourStep == .page else {
            return
        }

        editorGuidedTourStep = .measures
    }

    private func advanceEditorGuidedTourAfterCodaToolTapIfNeeded() {
        guard editorGuidedTourStep == .repeatsActive else {
            return
        }

        editorGuidedTourStep = .coda
    }

    private func advanceEditorGuidedTourAfterSetupIfNeeded(_ updatedChart: Chart) {
        guard editorGuidedTourStep == .setup,
              updatedChart.hasCompletedInitialSetup else {
            return
        }

        canvasMode = .chordEntry
        editorGuidedTourStep = .chordWrite
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

    private var editorNavigationChrome: some View {
        HStack(spacing: 12) {
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

            Text(chart.title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button {
                activateSelectTool(clearsMeasureSelection: true)
                handleExportTapped()
            } label: {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Label(exportButtonTitle, systemImage: "square.and.arrow.up")
                }
            }
            .disabled(isExporting || !chart.hasCompletedInitialSetup || !canvasMode.allowsTopBarExport)
        }
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
        }
    }

    private var showsActiveToolControls: Bool {
        canvasMode.showsActiveToolControls
    }

    @ViewBuilder
    private var pageToolControl: some View {
        if editorGuidedTourStep == .page {
            Button {
                advanceEditorGuidedTourAfterPageToolTapIfNeeded()
            } label: {
                pageToolLabel
            }
        } else {
            Menu {
                pageToolMenuContent
            } label: {
                pageToolLabel
            }
        }
    }

    private var pageToolLabel: some View {
        EditorMenuTabLabel(
            title: "Page",
            systemImage: "doc.text",
            isSelected: canvasMode == .headerEntry
        )
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
            activateSelectTool(clearsMeasureSelection: true)
            handleExportTapped()
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(isExporting || !chart.hasCompletedInitialSetup || !canvasMode.allowsTopBarExport)

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
                        isSelected: chart.chordTranspositionSemitones == semitones
                    )
                }
            }
        } label: {
            Label(
                "Transpose (\(chart.chordTranspositionDisplayText))",
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

        Button {
            activateSelectTool(clearsMeasureSelection: true)
            showingInkResponsivenessSheet = true
        } label: {
            Label("Pen Responsiveness", systemImage: "pencil.tip")
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
    private var codaToolControl: some View {
        if editorGuidedTourStep == .repeatsActive {
            Button {
                advanceEditorGuidedTourAfterCodaToolTapIfNeeded()
            } label: {
                codaToolLabel
            }
        } else {
            Menu {
                codaToolMenuContent
            } label: {
                codaToolLabel
            }
        }
    }

    private var codaToolLabel: some View {
        EditorCodaTabLabel(isSelected: selectedRoadmapMarkerID != nil)
    }

    @ViewBuilder
    private var codaToolMenuContent: some View {
        ForEach(RoadmapType.navigationPointMarkerTypes, id: \.self) { roadmapType in
            Button {
                handleAddPointRoadmapMarker(roadmapType)
            } label: {
                Text(roadmapType.editorMenuDisplayText)
            }
        }
    }

    private func toolStrip(minWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pageToolControl
                    .disabled(canvasMode.locksDocumentActions)
                    .buttonStyle(.plain)

                Button {
                    activateSelectTool()
                } label: {
                    EditorMenuTabLabel(
                        title: "Select",
                        systemImage: "cursorarrow",
                        isSelected: canvasMode == .browse
                            && selectedCueTextID == nil
                            && selectedRoadmapMarkerID == nil
                    )
                }
                .buttonStyle(.plain)

                Button {
                    handleMeasureEditRequested()
                } label: {
                    EditorMenuTabLabel(
                        title: "Measures",
                        systemImage: "rectangle.split.3x1",
                        isSelected: canvasMode == .measureEdit || isMeasureDeleteContinuationActive
                    )
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                Button {
                    handleRepeatToolTapped()
                } label: {
                    EditorMenuTabLabel(
                        title: "Repeats",
                        systemImage: "repeat",
                        isSelected: canvasMode == .repeatEdit || isRepeatContinuationActive
                    )
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                codaToolControl
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                Menu {
                    if selectedCueText != nil {
                        Button {
                            handleEditSelectedCueText()
                        } label: {
                            Label("Edit Selected Text", systemImage: "pencil")
                        }

                        Button {
                            resizeSelectedCueText(by: CueText.scaleStep)
                        } label: {
                            Label("Make Text Larger", systemImage: "plus.magnifyingglass")
                        }
                        .disabled(!canGrowSelectedCueText)

                        Button {
                            resizeSelectedCueText(by: -CueText.scaleStep)
                        } label: {
                            Label("Make Text Smaller", systemImage: "minus.magnifyingglass")
                        }
                        .disabled(!canShrinkSelectedCueText)

                        Button(role: .destructive) {
                            deleteSelectedCueText()
                        } label: {
                            Label("Delete Selected Text", systemImage: "trash")
                        }

                        Divider()
                    }

                    Button {
                        handleAddCueText(position: .below)
                    } label: {
                        Label("Add Text Below Selected Measure", systemImage: "text.bubble")
                    }

                    Button {
                        handleAddCueText(position: .above)
                    } label: {
                        Label("Add Text Above Selected Measure", systemImage: "text.bubble")
                    }

                    Button(role: .destructive) {
                        handleRemoveCueTextsAtSelectedMeasure()
                    } label: {
                        Label("Remove Text at Selected Measure", systemImage: "trash")
                    }
                    .disabled(!canRemoveCueTextAtSelectedMeasure)
                } label: {
                    EditorMenuTabLabel(
                        title: "Text",
                        systemImage: "text.bubble",
                        isSelected: showingCueTextEntry || selectedCueTextID != nil
                    )
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                Button {
                    handleTimeSignatureTabTapped()
                } label: {
                    EditorMenuTabLabel(
                        title: "Time",
                        systemImage: "metronome",
                        isSelected: canvasMode == .timeSignatureEdit
                    )
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                if chart.layoutStyle.profile.allowsRhythmicNotationInk {
                    Button {
                        handleRhythmicNotationTabTapped()
                    } label: {
                        EditorMenuTabLabel(
                            title: "Rhythm",
                            systemImage: "music.note",
                            isSelected: canvasMode == .rhythmicNotationEdit
                        )
                    }
                    .disabled(canvasMode.locksDocumentActions)
                    .buttonStyle(.plain)
                }

                Button {
                    handleChordTabTapped()
                } label: {
                    EditorMenuTabLabel(
                        title: "Chord",
                        systemImage: "pencil",
                        isSelected: canvasMode == .chordEntry
                    )
                }
                .disabled(canvasMode.locksDocumentActions && canvasMode != .chordEntry)
                .buttonStyle(.plain)

                Button {
                    selectedMeasureID = nil
                    selectedNoteSelection = nil
                    pendingTimeSignatureSourceMeasureID = nil
                    pendingTimeSignaturePlacement = nil
                    toggleFreeHandMode()
                } label: {
                    EditorMenuTabLabel(
                        title: canvasMode.freeHandTabTitle,
                        systemImage: canvasMode.freeHandTabSymbol,
                        isSelected: canvasMode == .freeHand
                    )
                }
                .disabled(
                    (canvasMode.locksDocumentActions && canvasMode != .freeHand)
                        || (!chart.hasCompletedInitialSetup && canvasMode != .freeHand)
                        || !chart.layoutStyle.profile.allowsFreehandSymbolInk
                )
                .buttonStyle(.plain)
            }
            .padding(7)
            .background(Color.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .frame(minWidth: minWidth, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func activeToolControls(minWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Label(canvasMode.activeToolTitle, systemImage: canvasMode.activeToolSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

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

                if canvasMode == .chordEntry {
                    chordActiveToolActions
                }

                if canvasMode == .chordEntry && chordToolInputMode == .inkOnly {
                    Label(
                        "Ink Only: handwritten chords stay as ink; transposition and chord systems will not apply.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
                }

                if canvasMode == .rhythmicNotationEdit {
                    rhythmActiveToolActions
                    rhythmDiagnosticStatusChip
                }

                Button {
                    activateSelectTool()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .foregroundStyle(Color.white)
                        .background(Color(red: 0.16, green: 0.38, blue: 0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
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

    private var measureActiveToolActions: some View {
        HStack(spacing: 5) {
            activeToolButton(
                title: "Add",
                systemImage: "plus.square",
                action: handleAddMeasureAfterSelected
            )

            activeToolButton(
                title: "Stack",
                systemImage: "square.stack.3d.up",
                action: handleAddMeasureStackAfterSelectedRequested
            )

            activeToolButton(
                title: "First",
                systemImage: "backward.end",
                action: handleAddMeasureAtBeginning
            )

            activeToolButton(
                title: "Double",
                systemImage: "pause",
                action: handleAddDoubleBarlineMeasure
            )

            activeToolButton(
                title: canRemoveSystemBreakBeforeSelectedMeasure ? "Join" : "New Row",
                systemImage: canRemoveSystemBreakBeforeSelectedMeasure ? "arrow.up.to.line" : "arrow.down.to.line",
                isDisabled: !canInsertSystemBreakBeforeSelectedMeasure && !canRemoveSystemBreakBeforeSelectedMeasure
            ) {
                if canRemoveSystemBreakBeforeSelectedMeasure {
                    handleRemoveSystemBreakBeforeSelectedMeasure()
                } else {
                    handleNewSystemBeforeSelectedMeasure()
                }
            }

            activeToolButton(
                title: "Delete",
                systemImage: "trash",
                isDestructive: true,
                isDisabled: !canDeleteSelectedMeasure,
                action: handleDeleteSelectedMeasure
            )

            activeToolButton(
                title: pendingDeleteStartMeasureID == nil ? "Range" : "Delete To",
                systemImage: pendingDeleteStartMeasureID == nil ? "trash.circle" : "checkmark.circle",
                isDestructive: pendingDeleteStartMeasureID != nil,
                isDisabled: pendingDeleteStartMeasureID == nil
                    ? !canDeleteSelectedMeasure
                    : !canDeleteThroughSelectedMeasure,
                action: handleMeasureRangeDeleteTapped
            )

            if pendingDeleteStartMeasureID != nil {
                activeToolButton(
                    title: "Clear",
                    systemImage: "xmark.circle",
                    action: clearPendingMeasureDeleteState
                )
            }
        }
    }

    private var repeatActiveToolActions: some View {
        HStack(spacing: 5) {
            activeToolButton(
                title: "One Bar",
                systemImage: "repeat",
                action: handleRepeatSelectedMeasure
            )

            activeToolButton(
                title: "Start",
                systemImage: "repeat.circle",
                action: handleStartRepeatHere
            )

            activeToolButton(
                title: "End Rep",
                systemImage: "checkmark.circle",
                isDisabled: pendingRepeatStartMeasureID == nil,
                action: handleEndRepeatHere
            )

            activeToolButton(
                title: pendingEndingButtonTitle(for: .ending1),
                systemImage: "1.circle",
                isDisabled: isEndingButtonDisabled(for: .ending1)
            ) {
                handleRepeatActiveEndingTapped(.ending1)
            }

            activeToolButton(
                title: pendingEndingButtonTitle(for: .ending2),
                systemImage: "2.circle",
                isDisabled: isEndingButtonDisabled(for: .ending2)
            ) {
                handleRepeatActiveEndingTapped(.ending2)
            }

            activeToolButton(
                title: "Remove Repeat",
                systemImage: "trash",
                isDestructive: true,
                isDisabled: !canRemoveRepeatAtSelectedMeasure,
                action: handleRemoveRepeatAtSelectedMeasure
            )

            activeToolButton(
                title: "Remove Ending",
                systemImage: "trash",
                isDestructive: true,
                isDisabled: !canRemoveEndingAtSelectedMeasure,
                action: handleRemoveEndingAtSelectedMeasure
            )

            if isRepeatContinuationActive {
                activeToolButton(
                    title: "Clear",
                    systemImage: "xmark.circle",
                    action: clearPendingRepeatState
                )
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

    private var chordActiveToolActions: some View {
        HStack(spacing: 5) {
            ForEach(ChordToolInputMode.allCases) { mode in
                activeToolButton(
                    title: mode.title,
                    systemImage: mode.systemImageName,
                    isSelected: chordToolInputMode == mode
                ) {
                    chordToolInputMode = mode
                }
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

    private func activeToolButton(
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 34)
                .foregroundStyle(
                    isSelected
                    ? Color.white
                    : (isDestructive ? Color.red : Color.primary)
                )
                .background(
                    isSelected
                    ? Color(red: 0.16, green: 0.38, blue: 0.82)
                    : Color(uiColor: .tertiarySystemBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(title)
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
            selectedCueTextID: $selectedCueTextID,
            selectedRoadmapMarkerID: $selectedRoadmapMarkerID,
            interactionMode: canvasMode,
            inkToolMode: inkToolMode,
            recognizesChordInk: chordToolInputMode.recognizesChordInk,
            inkResponsivenessValue: inkResponsivenessValue,
            onTimeSignatureTargetRequested: handleTimeSignatureTargetRequested,
            onChordInkRecognitionProposal: handleChordInkRecognitionProposal,
            onChordInkBatchRecognitionProposal: handleChordInkBatchRecognitionProposal,
            onChordCorrectionRequested: handleChordCorrectionRequested,
            onChordDeleted: handleChordDeleted,
            onNoteSelectionChanged: handleNoteSelectionChanged,
            onMeasureSelectedFromCanvas: handleMeasureSelectedFromCanvas,
            onChordSelectedFromCanvas: handleChordSelectedFromCanvas,
            onCueTextSelectedFromCanvas: handleCueTextSelectedFromCanvas,
            onCueTextEditRequested: handleCueTextEditRequestedFromCanvas,
            onRoadmapMarkerSelectedFromCanvas: handleRoadmapMarkerSelectedFromCanvas,
            onHeaderAuthoringRequested: handleHeaderAuthoringRequestedFromCanvas,
            onFreehandSymbolSelected: handleFreehandSymbolSelectedFromCanvas,
            rhythmicNotationPreviewConfirmationRequestID: rhythmPreviewConfirmationRequestID,
            onRhythmicNotationPreviewChanged: handleRhythmicNotationPreviewChanged
        )
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
                meter: preview?.meter ?? chart.defaultMeter
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

    private func exitEditor() {
        if let onExit {
            onExit()
        }
        dismiss()
    }

    private var exportButtonTitle: String {
        "Export PDF"
    }

    private func handleExportTapped() {
        let chartToExport = chart
        isExporting = true

        Task {
            do {
                let exportedPDF = try await exporter.exportPDF(for: chartToExport)
                try await MainActor.run {
                    let libraryPDF = try pdfLibraryStore.save(exportedPDF, source: .chartExport)
                    activeSheet = .export(libraryPDF)
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportAlertMessage = "Couldn’t generate the PDF right now. \(error.localizedDescription)"
                    showingExportAlert = true
                    isExporting = false
                }
            }
        }
    }

    private var allowsUserFacingRhythmNoteEditing: Bool {
        chart.layoutStyle.profile.allowsUserFacingRhythmNoteEditing
    }

    private var selectedRhythmActionMeasureID: UUID? {
        selectedNoteSelection?.measureID ?? selectedMeasureID
    }

    private var canClearRenderedRhythmAtSelectedMeasure: Bool {
        guard chart.layoutStyle.profile.allowsRhythmicNotationInk,
              let measureID = selectedRhythmActionMeasureID,
              let measure = chart.measure(id: measureID) else {
            return false
        }

        return measure.rhythmMap != nil || measure.handwrittenRhythmicNotationData != nil
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

        return chart.canRemoveSystemBreak(before: targetMeasureID)
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
    }

    private func handleRemoveSystemBreakBeforeSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              let targetMeasureID,
              chart.removeSystemBreak(before: targetMeasureID) else {
            return
        }

        pendingRepeatStartMeasureID = nil
        pendingDeleteStartMeasureID = nil
        pendingEndingStartMeasureID = nil
        pendingEndingType = nil
        selectedMeasureID = targetMeasureID
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
        guard enterMeasureEditMode(),
              let targetMeasureID else {
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
            canvasMode = .browse
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
    }

    private func handleRemoveCueTextsAtSelectedMeasure() {
        let targetMeasureID = resolvedMeasureActionTargetID()
        guard enterMeasureEditMode(),
              let targetMeasureID,
              chart.deleteCueTexts(attachedTo: targetMeasureID) > 0 else {
            return
        }

        pendingDeleteStartMeasureID = nil
        selectedMeasureID = targetMeasureID
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
        canvasMode = .browse
        showingCueTextEntry = true
    }

    private func resizeSelectedCueText(by scaleDelta: Double) {
        guard let selectedCueTextID,
              chart.resizeCueText(selectedCueTextID, byScaleDelta: scaleDelta),
              let cueText = chart.cueText(id: selectedCueTextID) else {
            return
        }

        selectedMeasureID = cueText.anchorMeasureID
        selectedRoadmapMarkerID = nil
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
        selectedCueTextID = nil
        selectedRoadmapMarkerID = nil
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
        guard chart.layoutStyle.profile.allowsRhythmicNotationInk else {
            selectedMeasureID = nil
            selectedNoteSelection = nil
            pendingTimeSignatureSourceMeasureID = nil
            pendingTimeSignaturePlacement = nil
            pendingDeleteStartMeasureID = nil
            pendingMeasureStackInsertion = nil
            clearPendingRepeatState()
            canvasMode = .browse
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
        guard chart.layoutStyle.profile.allowsRhythmicNotationInk else {
            noteEditErrorMessage = "This chart does not support rhythm writing."
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
        _ = enterMeasureEditMode()
    }

    private func handleChordSelectedFromCanvas(_: UUID) {
        guard chart.hasCompletedInitialSetup,
              canvasMode == .browse else {
            return
        }

        selectedMeasureID = nil
        selectedNoteSelection = nil
        clearSelectedCanvasObjectIDs()
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        inkToolMode = .write
        canvasMode = .chordEntry
    }

    private func handleCueTextSelectedFromCanvas(_ cueTextID: UUID) {
        guard chart.hasCompletedInitialSetup,
              let cueText = chart.cueText(id: cueTextID),
              canvasMode == .browse else {
            return
        }

        selectedCueTextID = cueTextID
        selectedRoadmapMarkerID = nil
        selectedMeasureID = cueText.anchorMeasureID
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
    }

    private func handleRoadmapMarkerSelectedFromCanvas(_ roadmapMarkerID: UUID) {
        guard chart.hasCompletedInitialSetup,
              let marker = chart.roadmapObject(id: roadmapMarkerID),
              canvasMode == .browse else {
            return
        }

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
        guard chart.layoutStyle.profile.allowsFreehandSymbolInk else {
            selectedNoteSelection = nil
            pendingDeleteStartMeasureID = nil
            pendingMeasureStackInsertion = nil
            clearPendingRepeatState()
            canvasMode = .browse
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

    private func handleFreehandSymbolSelectedFromCanvas(_: UUID) {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }
        guard chart.layoutStyle.profile.allowsFreehandSymbolInk else {
            activateSelectTool(clearsMeasureSelection: true)
            return
        }

        selectedMeasureID = nil
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        pendingDeleteStartMeasureID = nil
        pendingMeasureStackInsertion = nil
        clearPendingRepeatState()
        inkToolMode = .write
        canvasMode = .freeHand
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
        after sourceMeasureID: UUID,
        scope: TimeSignatureApplicationScope
    ) {
        let appliedMeasureID = chart.applyMeterChange(meter, after: sourceMeasureID, scope: scope)
        selectedMeasureID = appliedMeasureID ?? sourceMeasureID
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil

        if appliedMeasureID == nil {
            canvasMode = .browse
        }
    }

    private func handleChordInkRecognitionProposal(
        measureID: UUID,
        result: ChordInkRecognitionResult,
        drawingData: Data,
        targetFraction: Double?,
        timing: ChordInkRecognitionTiming,
        flow: ChordInkRecognitionFlow
    ) {
        #if DEBUG || targetEnvironment(simulator)
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
        #if DEBUG || targetEnvironment(simulator)
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

        #if DEBUG || targetEnvironment(simulator)
        logChordInkProposalTiming(
            result: result,
            primaryDecision: resolution.primaryDecision,
            decision: resolution.decision,
            decisionMilliseconds: proposalDecisionMilliseconds
        )
        #endif

        handleTapConfirmedChordRecognition(confirmation)
    }

    private func handleChordInkBatchRecognitionProposal(
        payloads: [ChordInkRecognitionProposalPayload],
        flow: ChordInkRecognitionFlow
    ) {
        #if DEBUG || targetEnvironment(simulator)
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
            #if DEBUG || targetEnvironment(simulator)
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
        let isGuidedChordConfirmation = editorGuidedTourStep == .chordWrite
            || editorGuidedTourStep == .chordConfirm
        let autoRenderTextsByID = Dictionary(
            uniqueKeysWithValues: confirmations.compactMap { confirmation -> (UUID, String)? in
                guard confirmation.decision.action == .autoRender,
                      let acceptedText = confirmation.decision.acceptedText else {
                    return nil
                }

                return (confirmation.id, acceptedText)
            }
        )

        if !isGuidedChordConfirmation,
           autoRenderTextsByID.count == confirmations.count,
           commitChordInkBatchCandidates(
                autoRenderTextsByID,
                batch: batch,
                resolution: .autoRendered
           ) {
            return
        }

        pendingChordInkBatchConfirmation = batch
    }

    private func handleChordInkBatchAccepted(
        _ candidateTextByID: [UUID: String],
        batch: PendingChordInkBatchConfirmation
    ) {
        let trimmedCandidateTextByID = candidateTextByID.reduce(into: [UUID: String]()) { result, element in
            result[element.key] = element.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let didCommit = commitChordInkBatchCandidates(
            trimmedCandidateTextByID,
            batch: batch,
            resolution: .confirmedSuggestion
        )

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

    private func handleTapConfirmedChordRecognition(_ confirmation: PendingChordInkConfirmation) {
        let isGuidedChordConfirmation = editorGuidedTourStep == .chordWrite
            || editorGuidedTourStep == .chordConfirm

        if editorGuidedTourStep == .chordWrite {
            editorGuidedTourStep = .chordConfirm
        }

        if !isGuidedChordConfirmation,
           confirmation.decision.action == .autoRender,
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
        #if DEBUG || targetEnvironment(simulator)
        let commitStartedAt = Date()
        #endif
        guard let match = ChordRecognitionCompendium.match(candidateText) else {
            chordInkErrorMessage = "That chord candidate is not supported yet. Try another candidate or edit the text."
            showingChordInkError = true
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
            return false
        }

        chart = updatedChart
        chordInkAutomaticRewriteFailures.reset()

        #if DEBUG || targetEnvironment(simulator)
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
        if editorGuidedTourStep == .chordWrite || editorGuidedTourStep == .chordConfirm {
            editorGuidedTourStep = .chordDone
        }

        #if DEBUG || targetEnvironment(simulator)
        logChordInkCommitTiming(
            acceptedText: candidateText,
            resolution: resolution,
            chordEventID: chordEventID,
            commitMilliseconds: commitMutationMilliseconds
        )
        #endif

        return true
    }

    @discardableResult
    private func commitChordInkBatchCandidates(
        _ candidateTextByID: [UUID: String],
        batch: PendingChordInkBatchConfirmation,
        resolution: ChordEntryDiagnosticResolution
    ) -> Bool {
        #if DEBUG || targetEnvironment(simulator)
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
                return false
            }

            committedEvents.append((confirmation, candidateText, match, chordEventID))
        }

        _ = updatedChart.setPageHandwrittenChordDrawing(nil)
        chart = updatedChart
        chordInkAutomaticRewriteFailures.reset()

        #if DEBUG || targetEnvironment(simulator)
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
        if editorGuidedTourStep == .chordWrite || editorGuidedTourStep == .chordConfirm {
            editorGuidedTourStep = .chordDone
        }

        return true
    }

    private func handleChordCorrectionRequested(_ chordEventID: UUID) {
        guard canvasMode == .chordEntry,
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
            currentText: chordEvent.symbol.displayText,
            rawInput: chordEvent.rawInput
        )
    }

    private func handleChordDeleted(_ chordEvent: ChordEvent) {
        guard let sourceInkData = chordEvent.sourceInkData else {
            return
        }

        let acceptedText = chordEvent.rawInput ?? chordEvent.symbol.displayText
        if chordInkUserCorrectionMemory.recordRejectedAutoRender(
            acceptedText: acceptedText,
            drawingData: sourceInkData,
            candidateSignature: chordEvent.sourceCandidateSignature
        ) {
            persistChordInkUserCorrectionMemory()
        }
    }

    private func handleChordCorrectionAccepted(
        _ candidateText: String,
        correction: PendingChordCorrection
    ) {
        let trimmedCandidateText = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = ChordRecognitionCompendium.match(trimmedCandidateText) else {
            chordInkErrorMessage = "That chord candidate is not supported yet. Try another candidate or edit the text."
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

        #if DEBUG || targetEnvironment(simulator)
        recordChordCorrectionDiagnostic(
            acceptedText: trimmedCandidateText,
            match: match,
            correction: correction,
            chartSnapshot: updatedChart
        )
        #endif

        selectedMeasureID = correction.measureID
        selectedNoteSelection = nil
        pendingChordCorrection = nil
        canvasMode = .chordEntry
    }

    #if DEBUG || targetEnvironment(simulator)
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
                format: "iChart chord proposal: decisionMs=%.0f best=%@ confidence=%.2f primaryAction=%@ finalAction=%@ trust=%@ agreement=%@ closeRace=%@ gap=%.2f reason=%@",
                decisionMilliseconds ?? -1,
                bestRead,
                result.confidence,
                primaryDecision.action.rawValue,
                decision.action.rawValue,
                decision.trustSource.rawValue,
                decision.agreementLevel.rawValue,
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
            confidence: confirmation.result.confidence,
            recognitionReason: confirmation.decision.reason,
            wasCloseRace: confirmation.decision.isCloseRace,
            confidenceGap: confirmation.decision.confidenceGap,
            targetFraction: confirmation.targetFraction,
            ocrCandidates: confirmation.result.ocrCandidates,
            ocrBestCandidateText: confirmation.decision.ocrBestCandidateText,
            ocrRawTexts: confirmation.decision.ocrRawTexts,
            recognitionTrustSource: confirmation.decision.trustSource,
            recognitionAgreementLevel: confirmation.decision.agreementLevel,
            primaryRecognitionAction: confirmation.primaryDecision.action,
            primaryAcceptedText: confirmation.primaryDecision.acceptedText,
            primaryRecognitionReason: confirmation.primaryDecision.reason,
            primaryWasCloseRace: confirmation.primaryDecision.isCloseRace,
            primaryConfidenceGap: confirmation.primaryDecision.confidenceGap,
            recognitionMetrics: confirmation.result.metrics,
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
        #if DEBUG || targetEnvironment(simulator)
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
        canvasMode = .chordEntry
    }

    private func persistChordInkUserCorrectionMemory() {
        do {
            try chordInkUserCorrectionMemoryStore.save(chordInkUserCorrectionMemory)
        } catch {
            #if DEBUG || targetEnvironment(simulator)
            print("iChart chord user correction memory error: \(error)")
            #endif
        }
    }

    private func handleNoteSelectionChanged(_ selection: LeadSheetNoteSelection?) {
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

    private func editorHorizontalPadding(for width: CGFloat) -> CGFloat {
        if width >= 1180 {
            return 10
        }

        if width >= 820 {
            return 14
        }

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
        return max(availableSize.height, 1200, CGFloat(visibleSystemCount) * 168 + 320)
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

private struct RhythmDiagnosticPreviewStrip: View {
    let values: [RhythmValue]
    let meter: Meter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
    static let glyphVerticalOffset: CGFloat = 8
    static let beamedGlyphAdvance: CGFloat = 27
    static let beamedDottedTrailingAllowance: CGFloat = 10
    static let beamedDotRightPadding: CGFloat = 1.5
    static let beamedStemWidth: CGFloat = 1.5
    static let beamThickness: CGFloat = 4
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

            var count = 1
            while index + count < values.count,
                  values[index + count].isDiagnosticPreviewBeamable,
                  RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                    beforeValueAt: index + count,
                    in: values,
                    meter: meter
                  ) {
                count += 1
            }

            if count > 1 {
                items.append(.beamedGroup(Array(values[index..<index + count])))
            } else {
                items.append(.single(value))
            }
            index += count
        }

        return items
    }
}

private extension RhythmValue {
    var isDiagnosticPreviewBeamable: Bool {
        self == .eighth || self == .dottedEighth || self == .sixteenth
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
                symbol(.wholeRest, size: RhythmDiagnosticPreviewMetrics.restBlockPointSize)
                    .offset(y: 0)
            case .halfRest:
                symbol(.halfRest, size: RhythmDiagnosticPreviewMetrics.restBlockPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset - 2)
            case .quarterRest:
                symbol(.quarterRest, size: RhythmDiagnosticPreviewMetrics.restPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset)
            case .eighthRest:
                symbol(.eighthRest, size: RhythmDiagnosticPreviewMetrics.restPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset + 1)
            case .sixteenthRest:
                symbol(.sixteenthRest, size: RhythmDiagnosticPreviewMetrics.restPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset - 4)
            case .whole:
                symbol(.noteWhole, size: RhythmDiagnosticPreviewMetrics.wholeNotePointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset + 3)
            case .half:
                noteSymbol(.noteHalfUp)
            case .dottedHalf:
                noteSymbol(.noteHalfUp)
                dot
            case .slash:
                symbol(.slashNotehead, size: RhythmDiagnosticPreviewMetrics.slashPointSize)
                    .offset(y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset)
            case .quarter:
                noteSymbol(.noteQuarterUp)
            case .dottedQuarter:
                noteSymbol(.noteQuarterUp)
                dot
            case .dottedEighth:
                noteSymbol(.note8thUp)
                dot
            case .eighth:
                noteSymbol(.note8thUp)
            case .sixteenth:
                noteSymbol(.note16thUp)
            case .tiedContinuation:
                RhythmDiagnosticTieShape()
                    .stroke(Color.primary, lineWidth: 1.4)
                    .frame(width: 24, height: 12)
                    .offset(y: 5)
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
            .offset(x: 1, y: RhythmDiagnosticPreviewMetrics.glyphVerticalOffset)
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
        value.isDottedReferenceValue
            ? RhythmDiagnosticPreviewMetrics.glyphWidth + 6
            : RhythmDiagnosticPreviewMetrics.glyphWidth
    }

    private var dotYOffset: CGFloat {
        switch value {
        case .dottedQuarter:
            return RhythmDiagnosticPreviewMetrics.glyphVerticalOffset + 5
        case .dottedEighth, .dottedHalf:
            return RhythmDiagnosticPreviewMetrics.glyphVerticalOffset + 8
        case .slash, .sixteenth, .sixteenthRest, .eighth, .eighthRest, .quarter, .quarterRest,
             .half, .halfRest, .whole, .wholeRest, .tiedContinuation:
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
        let beamY = contentRect.minY + 6
        let headWidth = min(11, advance * 0.42)
        let headHeight = max(11, contentRect.height * 0.27)
        let headCenterY = contentRect.minY + contentRect.height * 0.72
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
            beamY: beamY + beamThickness + 3,
            beamThickness: max(beamThickness * 0.82, 2.5)
        ))

        for index in 0..<noteCount {
            let originX = contentRect.minX + CGFloat(index) * advance
            let stemX = originX + advance * stemAnchorRatio
            path.addRect(CGRect(
                x: stemX,
                y: beamY,
                width: stemWidth,
                height: max(1, headCenterY - beamY)
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
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
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

private struct InkResponsivenessSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var value: Double

    private var normalizedBinding: Binding<Double> {
        Binding(
            get: { LeadSheetInkResponsivenessPolicy.normalized(value) },
            set: { value = LeadSheetInkResponsivenessPolicy.normalized($0) }
        )
    }

    private var percentageText: String {
        "\(Int((LeadSheetInkResponsivenessPolicy.normalized(value) * 100).rounded()))%"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pen Responsiveness") {
                    HStack(spacing: 14) {
                        Button {
                            adjust(-LeadSheetInkResponsivenessPolicy.step)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Decrease pen responsiveness")

                        Slider(
                            value: normalizedBinding,
                            in: LeadSheetInkResponsivenessPolicy.minimumValue...LeadSheetInkResponsivenessPolicy.maximumValue,
                            step: LeadSheetInkResponsivenessPolicy.step
                        ) {
                            Text("Pen Responsiveness")
                        } minimumValueLabel: {
                            Text("Direct")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("Smooth")
                                .font(.caption)
                        }

                        Button {
                            adjust(LeadSheetInkResponsivenessPolicy.step)
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Increase pen responsiveness")
                    }

                    HStack {
                        Spacer()
                        Text(percentageText)
                            .font(.headline.monospacedDigit())
                        Spacer()
                    }

                    Button("Balanced") {
                        value = LeadSheetInkResponsivenessPolicy.defaultValue
                    }
                }
            }
            .navigationTitle("Pen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func adjust(_ delta: Double) {
        value = LeadSheetInkResponsivenessPolicy.normalized(value + delta)
    }
}

private struct CueTextEntryPanelView: View {
    @Binding var text: String
    let actionTitle: String
    let onAdd: () -> Void
    let onCancel: () -> Void
    @State private var keyboardFocusRequestID = 0

    private var canAdd: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.14)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        requestTextFocus()
                    }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }

                        Spacer()

                        Text("Text")
                            .font(.headline.weight(.semibold))

                        Spacer()

                        Button(actionTitle) {
                            onAdd()
                        }
                        .disabled(!canAdd)
                    }

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
                    .frame(height: 118)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture {
                        requestTextFocus()
                    }
                }
                .padding(18)
                .frame(width: min(proxy.size.width - 48, 520))
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
                }
            }
        }
        .presentationDetents([.height(260), .medium])
    }
}

private struct TimeSignatureScopeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let meter: Meter
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
                    Text("The new \(meter.displayText) starts on the next measure.")
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
    }
}

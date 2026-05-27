import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct PendingChordRenderTimingEvidence {
    var event: ChordEntryDiagnosticEvent
    var committedAt: Date
}

struct EditorView: View {
    private static let supportedTimeSignatureChoices = [
        Meter(numerator: 4, denominator: 4),
        Meter(numerator: 3, denominator: 4),
        Meter(numerator: 5, denominator: 4),
        Meter(numerator: 6, denominator: 4)
    ]
    private static let showsChordFixtureCaptureTools = false

    @EnvironmentObject private var store: ChartLibraryStore
    @Binding var chart: Chart
    @State private var activeSheet: EditorSheet?
    @State private var exportAlertMessage = ""
    @State private var showingExportAlert = false
    @State private var showingSetupSheet = false
    @State private var showingHeaderSheet = false
    @State private var showingRhythmicNotationAcceptanceSheet = false
    @State private var activeAppearancePanel: ChartAppearancePanel?
    @State private var hasPresentedRhythmicNotationGuide = false
    @State private var isExporting = false
    @State private var rhythmicNotationErrorMessage = ""
    @State private var showingRhythmicNotationError = false
    @State private var pendingRhythmicNotationConfirmation: PendingRhythmicNotationConfirmation?
    @State private var selectedMeasureID: UUID?
    @State private var selectedNoteSelection: LeadSheetNoteSelection?
    @State private var isNoteEditMenuPresented = false
    @State private var noteEditMenuStage: NoteEditMenuStage = .actions
    @State private var noteEditErrorMessage = ""
    @State private var showingNoteEditError = false
    @State private var pendingChordInkConfirmation: PendingChordInkConfirmation?
    @State private var pendingChordCorrection: PendingChordCorrection?
    @State private var pendingChordRenderTimingEvidence: [UUID: PendingChordRenderTimingEvidence] = [:]
    @State private var chordInkUserCorrectionMemory: ChordInkUserCorrectionMemory
    @State private var chordInkAutomaticRewriteFailures = ChordInkAutomaticRewriteFailureTracker()
    @State private var chordInkErrorMessage = ""
    @State private var showingChordInkError = false
    @State private var pendingTimeSignatureSourceMeasureID: UUID?
    @State private var pendingTimeSignaturePlacement: PendingTimeSignaturePlacement?
    @State private var freeHandReturnMode: EditorCanvasMode = .browse
    @State private var canvasMode: EditorCanvasMode = .browse
    @State private var pendingChordDiagnosticReconciliationWorkItem: DispatchWorkItem?
    private let exporter: any ChartExporting
    private let chordInkUserCorrectionMemoryStore: ChordInkUserCorrectionMemoryStore

    init(
        chart: Binding<Chart>,
        exporter: any ChartExporting = PDFChartExporter.live(),
        chordInkUserCorrectionMemoryStore: ChordInkUserCorrectionMemoryStore = .live(),
        initialCanvasMode: EditorCanvasMode = .browse
    ) {
        self._chart = chart
        self.exporter = exporter
        self.chordInkUserCorrectionMemoryStore = chordInkUserCorrectionMemoryStore
        _canvasMode = State(initialValue: initialCanvasMode)
        _chordInkUserCorrectionMemory = State(
            initialValue: (try? chordInkUserCorrectionMemoryStore.load()) ?? ChordInkUserCorrectionMemory()
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                toolStrip

                canvasView
                    .frame(minHeight: canvasHeight)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .scrollDisabled(canvasMode.disablesPageScroll)
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
        .navigationTitle(chart.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(chart.hasCompletedInitialSetup ? "Page Setup" : "Setup") {
                    selectedMeasureID = nil
                    selectedNoteSelection = nil
                    pendingTimeSignatureSourceMeasureID = nil
                    pendingTimeSignaturePlacement = nil
                    freeHandReturnMode = .browse
                    canvasMode = .browse
                    showingSetupSheet = true
                }
                .disabled(canvasMode.locksDocumentActions)

                Button {
                    selectedMeasureID = nil
                    selectedNoteSelection = nil
                    pendingTimeSignatureSourceMeasureID = nil
                    pendingTimeSignaturePlacement = nil
                    freeHandReturnMode = .browse
                    canvasMode = .browse
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
        }
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
            ChartSetupSheetView(chart: $chart)
        }
        .sheet(isPresented: $showingHeaderSheet) {
            ChartHeaderSheetView(chart: $chart)
        }
        .sheet(item: $activeAppearancePanel) { panel in
            ChartAppearanceSheetView(chart: $chart, panel: panel)
        }
        .sheet(isPresented: $showingRhythmicNotationAcceptanceSheet) {
            RhythmicNotationAcceptanceSheetView()
        }
        .sheet(item: $pendingRhythmicNotationConfirmation) { confirmation in
            RhythmicNotationConfirmationSheetView(
                confirmation: confirmation,
                onAccept: {
                    handleRhythmicNotationConfirmationAccepted(confirmation)
                },
                onRewrite: {
                    handleRhythmicNotationConfirmationRewriteRequested(confirmation)
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
                    handleChordInkFixtureCopyRequested(candidateText, confirmation: confirmation)
                },
                onKeepInk: {
                    pendingChordInkConfirmation = nil
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
        .alert("Rhythmic Notation", isPresented: $showingRhythmicNotationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rhythmicNotationErrorMessage)
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
            } else if canvasMode == .noteEdit {
                noteEditMenuStage = .actions
                isNoteEditMenuPresented = true
            }
        }
        .onChange(of: canvasMode) { _, mode in
            if mode != .noteEdit {
                isNoteEditMenuPresented = false
                noteEditMenuStage = .actions
            }
        }
        .onChange(of: chart) { _, updatedChart in
            scheduleChordEntryDiagnosticReconciliation(for: updatedChart)
            #if DEBUG || targetEnvironment(simulator)
            recordPendingChordRenderHandoff()
            #endif
        }
        .onDisappear {
            pendingChordDiagnosticReconciliationWorkItem?.cancel()
            pendingChordDiagnosticReconciliationWorkItem = nil
        }
        .task {
            if chart.staffStyle != .fiveLine {
                chart.staffStyle = .fiveLine
                chart.updatedAt = .now
            }
            if !chart.hasCompletedInitialSetup {
                showingSetupSheet = true
            }
        }
    }

    private var toolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    selectedMeasureID = nil
                    selectedNoteSelection = nil
                    pendingTimeSignatureSourceMeasureID = nil
                    pendingTimeSignaturePlacement = nil
                    freeHandReturnMode = .browse
                    canvasMode = .browse
                    showingSetupSheet = true
                } label: {
                    EditorMenuTabLabel(title: "Page", systemImage: "doc.text")
                }
                .buttonStyle(.plain)

                Button {
                    handleMeasureTabTapped()
                } label: {
                    EditorMenuTabLabel(
                        title: "Measures",
                        systemImage: "rectangle.split.4x1",
                        isSelected: canvasMode == .measureEdit
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

                Button {
                    handleRhythmicNotationTabTapped()
                } label: {
                    EditorMenuTabLabel(
                        title: "Rhythmic Notation",
                        systemImage: "note.quarter",
                        isSelected: canvasMode == .rhythmicNotationEdit
                    )
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                Button {
                    handleEditTabTapped()
                } label: {
                    EditorMenuTabLabel(
                        title: "Edit",
                        systemImage: "lasso",
                        isSelected: canvasMode == .noteEdit
                    )
                }
                .disabled(canvasMode.locksDocumentActions && canvasMode != .noteEdit)
                .buttonStyle(.plain)
                .popover(
                    isPresented: $isNoteEditMenuPresented,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    NoteEditPopoverView(
                        stage: $noteEditMenuStage,
                        notationFont: chart.notationFont,
                        selectedRhythmValue: selectedRhythmValue,
                        onSelectRhythm: handleSelectedNoteRhythmReplacement
                    )
                    .presentationCompactAdaptation(.popover)
                }

                Button {
                    handleChordTabTapped()
                } label: {
                    EditorMenuTabLabel(
                        title: "Chord",
                        systemImage: "textformat.alt",
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
                )
                .buttonStyle(.plain)

                EditorMenuTabLabel(title: "Jazz", systemImage: "music.quarternote.3", isSelected: true)

                Button {
                    presentAppearancePanel(.documentStyle)
                } label: {
                    EditorMenuTabLabel(
                        title: "Style",
                        systemImage: "paintpalette",
                        isSelected: activeAppearancePanel == .documentStyle
                    )
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                Button {
                    presentAppearancePanel(.notationFont)
                } label: {
                    EditorMenuTabLabel(
                        title: "Fonts",
                        systemImage: "textformat",
                        isSelected: activeAppearancePanel == .notationFont
                    )
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                Button {
                    presentAppearancePanel(.engraving)
                } label: {
                    EditorMenuTabLabel(
                        title: "Engraving",
                        systemImage: "slider.horizontal.3",
                        isSelected: activeAppearancePanel == .engraving
                    )
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                Button {
                    selectedMeasureID = nil
                    selectedNoteSelection = nil
                    pendingTimeSignatureSourceMeasureID = nil
                    pendingTimeSignaturePlacement = nil
                    freeHandReturnMode = .browse
                    canvasMode = .browse
                    showingHeaderSheet = true
                } label: {
                    EditorMenuTabLabel(title: "Header", systemImage: "character.cursor.ibeam")
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)

                Menu {
                    ForEach(TranspositionView.allCases, id: \.self) { view in
                        Button {
                            selectedMeasureID = nil
                            selectedNoteSelection = nil
                            pendingTimeSignatureSourceMeasureID = nil
                            pendingTimeSignaturePlacement = nil
                            freeHandReturnMode = .browse
                            canvasMode = .browse
                            chart.setTranspositionView(view)
                        } label: {
                            notationMenuLabel(view.displayText, isSelected: chart.defaultTranspositionView == view)
                        }
                    }
                } label: {
                    EditorMenuTabLabel(title: "View", systemImage: "guitars")
                }
                .disabled(canvasMode.locksDocumentActions)
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var canvasView: some View {
        LeadSheetCanvasHostView(
            chart: $chart,
            selectedMeasureID: $selectedMeasureID,
            selectedNoteSelection: $selectedNoteSelection,
            interactionMode: canvasMode,
            onTimeSignatureTargetRequested: handleTimeSignatureTargetRequested,
            onRhythmicNotationProposal: handleRhythmicNotationProposal,
            onRhythmicNotationValidationError: handleRhythmicNotationValidationError,
            onChordInkRecognitionProposal: handleChordInkRecognitionProposal,
            onChordCorrectionRequested: handleChordCorrectionRequested,
            onChordDeleted: handleChordDeleted,
            onNoteSelectionChanged: handleNoteSelectionChanged
        )
    }

    private var exportButtonTitle: String {
        store.canUse(.pdfExport) ? "Export PDF" : "Export PDF (Pro)"
    }

    private func handleExportTapped() {
        guard store.canUse(.pdfExport) else {
            activeSheet = .upgrade(.pdfExport)
            return
        }

        let chartToExport = chart
        isExporting = true

        Task {
            do {
                let exportedURL = try await exporter.exportPDF(for: chartToExport)
                await MainActor.run {
                    activeSheet = .export(
                        ExportedPDF(
                            url: exportedURL,
                            chartTitle: chartToExport.title
                        )
                    )
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

    private func handleMeasureTabTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        let targetMeasureID = resolvedMeasureActionTargetID()
        selectedMeasureID = nil
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        freeHandReturnMode = .browse
        canvasMode = .measureEdit

        guard let targetMeasureID else {
            _ = chart.appendMeasure(authoringState: .open)
            return
        }

        if chart.measure(id: targetMeasureID)?.authoringState == .open {
            _ = chart.commitOpenMeasure()
        } else {
            _ = chart.positionOpenMeasure(after: targetMeasureID)
        }
    }

    private func handleTimeSignatureTabTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        selectedNoteSelection = nil
        freeHandReturnMode = .browse
        canvasMode = .timeSignatureEdit
    }

    private func handleRhythmicNotationTabTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        selectedNoteSelection = nil
        freeHandReturnMode = .browse

        if canvasMode == .rhythmicNotationEdit {
            showingRhythmicNotationAcceptanceSheet = true
            return
        }

        canvasMode = .rhythmicNotationEdit

        if !hasPresentedRhythmicNotationGuide {
            showingRhythmicNotationAcceptanceSheet = true
            hasPresentedRhythmicNotationGuide = true
        }
    }

    private func presentAppearancePanel(_ panel: ChartAppearancePanel) {
        selectedMeasureID = nil
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        freeHandReturnMode = .browse
        canvasMode = .browse
        activeAppearancePanel = panel
    }

    private func resolvedMeasureActionTargetID() -> UUID? {
        if let selectedMeasureID,
           chart.measure(id: selectedMeasureID) != nil {
            return selectedMeasureID
        }

        return chart.measures.first(where: { $0.authoringState == .open })?.id
            ?? chart.measures.last?.id
    }

    private func toggleFreeHandMode() {
        if canvasMode == .freeHand {
            pendingTimeSignatureSourceMeasureID = nil
            pendingTimeSignaturePlacement = nil
            canvasMode = freeHandReturnMode
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
        selectedNoteSelection = nil
        freeHandReturnMode = canvasMode
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
        freeHandReturnMode = .browse

        canvasMode = canvasMode == .chordEntry ? .browse : .chordEntry
    }

    private func handleEditTabTapped() {
        guard chart.hasCompletedInitialSetup else {
            showingSetupSheet = true
            return
        }

        selectedMeasureID = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil
        freeHandReturnMode = .browse

        if canvasMode == .noteEdit {
            selectedNoteSelection = nil
            canvasMode = .browse
        } else {
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
        selectedMeasureID = sourceMeasureID
        selectedNoteSelection = nil
        pendingTimeSignatureSourceMeasureID = nil
        pendingTimeSignaturePlacement = nil

        if appliedMeasureID == nil {
            canvasMode = .browse
        }
    }

    private func handleRhythmicNotationValidationError(_ message: String) {
        rhythmicNotationErrorMessage = message
        showingRhythmicNotationError = true
        canvasMode = .rhythmicNotationEdit
    }

    private func handleRhythmicNotationProposal(
        measureID: UUID,
        values: [RhythmValue],
        drawingData: Data
    ) {
        guard let measure = chart.measure(id: measureID) else {
            return
        }

        selectedMeasureID = measureID
        selectedNoteSelection = nil
        canvasMode = .rhythmicNotationEdit
        pendingRhythmicNotationConfirmation = PendingRhythmicNotationConfirmation(
            measureID: measureID,
            measureIndex: measure.index,
            meter: measure.resolvedMeter(defaultMeter: chart.defaultMeter),
            values: values,
            drawingData: drawingData
        )
    }

    private func handleRhythmicNotationConfirmationAccepted(
        _ confirmation: PendingRhythmicNotationConfirmation
    ) {
        var updatedChart = chart
        _ = updatedChart.setMeasureRhythmMap(
            confirmation.values,
            drawingData: confirmation.drawingData,
            for: confirmation.measureID
        )
        _ = updatedChart.clearMeasureRhythmicNotation(
            for: confirmation.measureID,
            clearRhythmMap: false
        )

        chart = updatedChart
        selectedMeasureID = confirmation.measureID
        selectedNoteSelection = nil
        canvasMode = .rhythmicNotationEdit
        pendingRhythmicNotationConfirmation = nil
    }

    private func handleRhythmicNotationConfirmationRewriteRequested(
        _ confirmation: PendingRhythmicNotationConfirmation
    ) {
        var updatedChart = chart
        _ = updatedChart.clearMeasureRhythmicNotation(
            for: confirmation.measureID,
            clearRhythmMap: true
        )

        chart = updatedChart
        selectedMeasureID = confirmation.measureID
        selectedNoteSelection = nil
        canvasMode = .rhythmicNotationEdit
        pendingRhythmicNotationConfirmation = nil
    }

    private func handleChordInkRecognitionProposal(
        measureID: UUID,
        result: ChordInkRecognitionResult,
        drawingData: Data,
        targetFraction: Double?,
        timing: ChordInkRecognitionTiming
    ) {
        #if DEBUG || targetEnvironment(simulator)
        let proposalReceivedAt = Date()
        #endif
        guard canvasMode == .chordEntry,
              pendingChordInkConfirmation == nil,
              let measure = chart.measure(id: measureID) else {
            return
        }

        selectedMeasureID = nil
        selectedNoteSelection = nil
        let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
        var decision = ChordRecognitionTrustArbiter.decision(for: result)
        let candidateTexts = PendingChordInkConfirmation.candidateTexts(for: result)
        if decision.action == .autoRender,
           let acceptedText = decision.acceptedText,
           chordInkUserCorrectionMemory.shouldBlockAutoRender(
               acceptedText: acceptedText,
               drawingData: drawingData,
               candidateTexts: candidateTexts
           ) {
            decision.action = .confirm
            decision.reason = "This ink previously rendered as \(acceptedText) and was deleted. Choose the intended chord, or type it in."
            decision.isCloseRace = false
            decision.competingCandidateText = nil
            decision.confidenceGap = nil
        }
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
            primaryDecision: primaryDecision,
            decision: decision
        )

        #if DEBUG || targetEnvironment(simulator)
        logChordInkProposalTiming(
            result: result,
            primaryDecision: primaryDecision,
            decision: decision,
            decisionMilliseconds: proposalDecisionMilliseconds
        )
        #endif

        if decision.action == .autoRender,
           let acceptedText = decision.acceptedText {
            _ = commitChordInkCandidate(
                acceptedText,
                confirmation: confirmation,
                resolution: .autoRendered
            )
            return
        }

        let isCompleteFailure = ChordInkUserCorrectionMemoryPolicy.isCompleteFailure(
            result: result,
            decision: decision,
            candidateTexts: confirmation.candidateTexts
        )

        if isCompleteFailure {
            let failureCount = chordInkAutomaticRewriteFailures.recordFailure(
                measureID: measureID,
                targetFraction: targetFraction
            )

            if failureCount <= ChordInkUserCorrectionMemoryPolicy.maximumAutomaticRewriteFailures {
                clearChordInkForRewrite()
                return
            }
        } else {
            chordInkAutomaticRewriteFailures.reset()
        }

        if !isCompleteFailure,
           let preferredCandidate = chordInkUserCorrectionMemory.preferredCandidate(
               for: confirmation.candidateTexts,
               decision: decision
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

    private func handleChordCorrectionRequested(_ chordEventID: UUID) {
        guard canvasMode == .chordEntry,
              pendingChordInkConfirmation == nil,
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
                format: "SmartChart chord proposal: decisionMs=%.0f best=%@ confidence=%.2f primaryAction=%@ finalAction=%@ trust=%@ agreement=%@ closeRace=%@ gap=%.2f reason=%@",
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
                format: "SmartChart chord commit: commitMs=%.0f accepted=%@ resolution=%@ event=%@",
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
            print("SmartChart chord diagnostic error: \(error)")
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
                        format: "SmartChart chord render: renderHandoffMs=%.0f event=%@ accepted=%@",
                        renderHandoffMilliseconds,
                        chordEventID.uuidString,
                        event.acceptedText
                    )
                )
            }
        } catch {
            print("SmartChart chord render diagnostic error: \(error)")
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
            print("SmartChart chord diagnostic error: \(error)")
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
                print("SmartChart chord diagnostic reconciliation error: \(error)")
            }
        }
        pendingChordDiagnosticReconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        #endif
    }

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
            return .failed("Could not export this regression fixture. Keep the ink and try again.")
        }
    }

    private func handleChordInkRewriteRequested() {
        chordInkAutomaticRewriteFailures.reset()
        clearChordInkForRewrite()
    }

    private func clearChordInkForRewrite() {
        var updatedChart = chart
        _ = updatedChart.setPageHandwrittenChordDrawing(nil)
        chart = updatedChart
        pendingChordInkConfirmation = nil
        canvasMode = .chordEntry
    }

    private func persistChordInkUserCorrectionMemory() {
        do {
            try chordInkUserCorrectionMemoryStore.save(chordInkUserCorrectionMemory)
        } catch {
            #if DEBUG || targetEnvironment(simulator)
            print("SmartChart chord user correction memory error: \(error)")
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
            return "That note is not part of an editable rhythm map yet."
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
            return "misaligned with the beat grid"
        }
    }

    private var canvasHeight: CGFloat {
        if !chart.hasCompletedInitialSetup {
            return 760
        }

        let visibleSystemCount = LeadSheetPageLayoutEngine.estimatedSystemCount(
            for: chart,
            pageWidth: 900
        )
        return max(1200, CGFloat(visibleSystemCount) * 168 + 320)
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

            Text(value.editMenuTitle)
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

private struct RhythmValueGlyphPreview: View {
    let value: RhythmValue
    let notationFont: NotationFontPreset

    var body: some View {
        ZStack {
            if let restSymbol {
                glyphText(restSymbol, size: restPointSize)
                    .offset(y: restYOffset)
            } else {
                glyphText(noteheadSymbol, size: 24)
                    .offset(x: noteheadXOffset, y: 3)

                if showsStem {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 1.4, height: 25)
                        .offset(x: 8, y: 8)
                }

                if value == .eighth {
                    glyphText(NotationGlyphCatalog.flag8thDown, size: 21)
                        .offset(x: 14, y: 14)
                }

                if value.isDottedEditValue {
                    glyphText(NotationGlyphCatalog.augmentationDot, size: 13)
                        .offset(x: 17, y: 3)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(value.editMenuTitle)
    }

    private var restSymbol: String? {
        switch value {
        case .wholeRest:
            return NotationGlyphCatalog.wholeRest
        case .halfRest:
            return NotationGlyphCatalog.halfRest
        case .quarterRest:
            return NotationGlyphCatalog.quarterRest
        case .eighthRest:
            return NotationGlyphCatalog.eighthRest
        case .slash, .eighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole, .tiedContinuation:
            return nil
        }
    }

    private var noteheadSymbol: String {
        switch value {
        case .whole:
            return NotationGlyphCatalog.slashWholeNotehead
        case .half, .dottedHalf:
            return NotationGlyphCatalog.slashHalfNotehead
        case .slash, .eighth, .quarter, .dottedQuarter:
            return NotationGlyphCatalog.slashNotehead
        case .eighthRest, .quarterRest, .halfRest, .wholeRest, .tiedContinuation:
            return NotationGlyphCatalog.slashNotehead
        }
    }

    private var noteheadXOffset: CGFloat {
        value.isDottedEditValue ? -6 : -8
    }

    private var showsStem: Bool {
        switch value {
        case .slash, .whole, .wholeRest, .halfRest, .quarterRest, .eighthRest, .tiedContinuation:
            return false
        case .eighth, .quarter, .dottedQuarter, .half, .dottedHalf:
            return true
        }
    }

    private var restPointSize: CGFloat {
        switch value {
        case .quarterRest:
            return 29
        case .eighthRest:
            return 27
        case .wholeRest, .halfRest:
            return 24
        case .slash, .eighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole, .tiedContinuation:
            return 24
        }
    }

    private var restYOffset: CGFloat {
        switch value {
        case .quarterRest:
            return 0
        case .eighthRest:
            return 1
        case .wholeRest:
            return -3
        case .halfRest:
            return 2
        case .slash, .eighth, .quarter, .dottedQuarter, .half, .dottedHalf, .whole, .tiedContinuation:
            return 0
        }
    }

    private func glyphText(_ glyph: String, size: CGFloat) -> Text {
        Text(glyph)
            .font(notationFont.notationPreviewFont(size: size))
    }
}

private extension RhythmValue {
    var editMenuTitle: String {
        switch self {
        case .slash:
            return "Slash"
        case .eighth:
            return "Eighth Note"
        case .eighthRest:
            return "Eighth Rest"
        case .quarter:
            return "Quarter Note"
        case .quarterRest:
            return "Quarter Rest"
        case .dottedQuarter:
            return "Dotted Quarter"
        case .half:
            return "Half Note"
        case .halfRest:
            return "Half Rest"
        case .dottedHalf:
            return "Dotted Half"
        case .whole:
            return "Whole Note"
        case .wholeRest:
            return "Whole Rest"
        case .tiedContinuation:
            return "Tie"
        }
    }

    var isDottedEditValue: Bool {
        switch self {
        case .dottedQuarter, .dottedHalf:
            return true
        case .slash, .eighth, .eighthRest, .quarter, .quarterRest, .half, .halfRest, .whole, .wholeRest, .tiedContinuation:
            return false
        }
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
                    Text("Add measures of time?")
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

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var chordInkErrorMessage = ""
    @State private var showingChordInkError = false
    @State private var pendingTimeSignatureSourceMeasureID: UUID?
    @State private var pendingTimeSignaturePlacement: PendingTimeSignaturePlacement?
    @State private var freeHandReturnMode: EditorCanvasMode = .browse
    @State private var canvasMode: EditorCanvasMode = .browse
    @State private var pendingChordDiagnosticReconciliationWorkItem: DispatchWorkItem?
    private let exporter: any ChartExporting

    init(
        chart: Binding<Chart>,
        exporter: any ChartExporting = PDFChartExporter.live(),
        initialCanvasMode: EditorCanvasMode = .browse
    ) {
        self._chart = chart
        self.exporter = exporter
        _canvasMode = State(initialValue: initialCanvasMode)
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
        targetFraction: Double?
    ) {
        guard canvasMode == .chordEntry,
              pendingChordInkConfirmation == nil,
              let measure = chart.measure(id: measureID) else {
            return
        }

        selectedMeasureID = nil
        selectedNoteSelection = nil
        let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
        let decision = ChordRecognitionTrustArbiter.decision(for: result)
        let confirmation = PendingChordInkConfirmation(
            measureID: measureID,
            measureIndex: measure.index,
            result: result,
            drawingData: drawingData,
            targetFraction: targetFraction,
            primaryDecision: primaryDecision,
            decision: decision
        )

        if decision.action == .autoRender,
           let acceptedText = decision.acceptedText {
            commitChordInkCandidate(
                acceptedText,
                confirmation: confirmation,
                resolution: .autoRendered
            )
            return
        }

        pendingChordInkConfirmation = confirmation
    }

    private func handleChordInkCandidateAccepted(
        _ candidateText: String,
        confirmation: PendingChordInkConfirmation
    ) {
        let trimmedCandidateText = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolution: ChordEntryDiagnosticResolution = confirmation.candidateTexts.contains(trimmedCandidateText)
            ? .confirmedSuggestion
            : .manualCorrection

        commitChordInkCandidate(
            trimmedCandidateText,
            confirmation: confirmation,
            resolution: resolution
        )
    }

    private func commitChordInkCandidate(
        _ candidateText: String,
        confirmation: PendingChordInkConfirmation,
        resolution: ChordEntryDiagnosticResolution
    ) {
        guard let match = ChordRecognitionCompendium.match(candidateText) else {
            chordInkErrorMessage = "That chord candidate is not supported yet. Try another candidate or edit the text."
            showingChordInkError = true
            return
        }

        var updatedChart = chart
        guard let chordEventID = updatedChart.appendRecognizedChordEvent(
            match.symbol,
            rawInput: candidateText,
            to: confirmation.measureID,
            atFraction: confirmation.targetFraction,
            sourceInkData: confirmation.drawingData
        ) else {
            chordInkErrorMessage = "That measure is no longer available. Keep the ink and try again."
            showingChordInkError = true
            return
        }

        _ = updatedChart.setPageHandwrittenChordDrawing(nil)
        chart = updatedChart

        #if DEBUG || targetEnvironment(simulator)
        recordChordEntryDiagnostic(
            acceptedText: candidateText,
            match: match,
            confirmation: confirmation,
            resolution: resolution,
            chordEventID: chordEventID,
            chartSnapshot: updatedChart
        )
        #endif

        selectedMeasureID = confirmation.measureID
        selectedNoteSelection = nil
        canvasMode = .chordEntry
        pendingChordInkConfirmation = nil
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
    private func recordChordEntryDiagnostic(
        acceptedText: String,
        match: ChordRecognitionMatch,
        confirmation: PendingChordInkConfirmation,
        resolution: ChordEntryDiagnosticResolution,
        chordEventID: UUID,
        chartSnapshot: Chart
    ) {
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
            primarySymbolLedgerAssessment: confirmation.result.symbolLedgerAssessment
        )

        do {
            let recorder = ChordEntryDiagnosticsRecorder.live()
            try recorder.append(event)
            try recorder.reconcileRenderedChordEvents(for: chartSnapshot)
        } catch {
            print("SmartChart chord diagnostic error: \(error)")
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
            targetFraction: nil
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
            return .failed("Could not export this ink sample. Keep the ink and try again.")
        }
    }

    private func handleChordInkRewriteRequested() {
        var updatedChart = chart
        _ = updatedChart.setPageHandwrittenChordDrawing(nil)
        chart = updatedChart
        pendingChordInkConfirmation = nil
        canvasMode = .chordEntry
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

private struct PendingRhythmicNotationConfirmation: Identifiable {
    let id = UUID()
    let measureID: UUID
    let measureIndex: Int
    let meter: Meter
    let values: [RhythmValue]
    let drawingData: Data

    var displayMeasureNumber: Int {
        measureIndex + 1
    }

    var requiredBeatCount: Double {
        meter.measureLengthInWholeNotes / meter.beatUnitWholeNoteLength
    }

    var recognizedBeatCount: Double {
        values.reduce(0) { partialResult, value in
            partialResult + value.wholeNoteLength / meter.beatUnitWholeNoteLength
        }
    }
}

private struct PendingChordInkConfirmation: Identifiable {
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

private struct PendingChordCorrection: Identifiable {
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

private enum ChordInkFixtureCopyResult: Equatable {
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

private enum NoteEditMenuStage: Hashable {
    case actions
    case rhythm
}

private struct ChordInkConfirmationSheetView: View {
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

private struct ChordCorrectionSheetView: View {
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

private struct RhythmicNotationConfirmationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let confirmation: PendingRhythmicNotationConfirmation
    let onAccept: () -> Void
    let onRewrite: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Measure \(confirmation.displayMeasureNumber)")
                        .font(.title3.weight(.semibold))
                    Text("The app read your handwriting as this rhythm. Accept it if it is right, or keep editing the ink in the measure.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Read as")
                            .font(.headline)
                        Spacer()
                        Text("\(formattedBeats(confirmation.recognizedBeatCount)) / \(formattedBeats(confirmation.requiredBeatCount)) beats")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(Array(confirmation.values.enumerated()), id: \.offset) { _, value in
                            Text(value.debugConfirmationLabel)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(value.isRest ? Color.orange.opacity(0.15) : Color.blue.opacity(0.13))
                                .foregroundStyle(value.isRest ? Color.orange : Color.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 10) {
                    Button {
                        onAccept()
                        dismiss()
                    } label: {
                        Text("Use This Rhythm")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        onRewrite()
                        dismiss()
                    } label: {
                        Text("Clear Measure & Rewrite")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Confirm Rhythm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Keep Editing") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(420), .medium])
    }

    private func formattedBeats(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = layout(in: bounds.width, subviews: subviews).rows
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func layout(in availableWidth: CGFloat, subviews: Subviews) -> FlowLayoutResult {
        let safeWidth = max(1, availableWidth)
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if proposedWidth > safeWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, height: currentHeight, width: currentWidth))
                currentItems = [FlowItem(subview: subview, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(subview: subview, size: size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight, width: currentWidth))
        }

        let height = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.height
        } + max(0, CGFloat(rows.count - 1)) * rowSpacing
        let width = rows.reduce(CGFloat.zero) { partialResult, row in
            max(partialResult, row.width)
        }

        return FlowLayoutResult(size: CGSize(width: width, height: height), rows: rows)
    }
}

private struct FlowLayoutResult {
    let size: CGSize
    let rows: [FlowRow]
}

private struct FlowRow {
    let items: [FlowItem]
    let height: CGFloat
    let width: CGFloat
}

private struct FlowItem {
    let subview: LayoutSubview
    let size: CGSize
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

    var debugConfirmationLabel: String {
        switch self {
        case .slash:
            return "slash"
        case .eighth:
            return "eighth"
        case .eighthRest:
            return "eighth rest"
        case .quarter:
            return "quarter"
        case .quarterRest:
            return "quarter rest"
        case .dottedQuarter:
            return "dotted quarter"
        case .half:
            return "half"
        case .halfRest:
            return "half rest"
        case .dottedHalf:
            return "dotted half"
        case .whole:
            return "whole"
        case .wholeRest:
            return "whole rest"
        case .tiedContinuation:
            return "tie"
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

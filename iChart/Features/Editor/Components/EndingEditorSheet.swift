import SwiftUI
import UIKit

struct EndingEditorRequest: Identifiable {
    let id = UUID()
    let endingID: UUID?
    let type: RoadmapType
    let startMeasureID: UUID
    let endMeasureID: UUID
    let label: String
    let endStyle: EndingEndStyle

    init(startMeasureID: UUID) {
        endingID = nil
        type = .ending1
        self.startMeasureID = startMeasureID
        endMeasureID = startMeasureID
        label = ""
        endStyle = .closed
    }

    init(preset type: RoadmapType, startMeasureID: UUID, endMeasureID: UUID) {
        endingID = nil
        self.type = type
        self.startMeasureID = startMeasureID
        self.endMeasureID = endMeasureID
        label = type.compactEndingDisplayText ?? type.defaultDisplayText
        endStyle = .closed
    }

    init(ending: RoadmapObject) {
        endingID = ending.id
        type = ending.type
        startMeasureID = ending.startMeasureID
        endMeasureID = ending.endMeasureID ?? ending.startMeasureID
        label = ending.resolvedEndingDisplayText
        endStyle = ending.resolvedEndingEndStyle
    }
}

/// Changes stay in this value until Apply, including when the sheet is dismissed.
struct EndingEditorDraft {
    let endingID: UUID?
    let type: RoadmapType
    var label: String
    var startMeasureID: UUID
    var endMeasureID: UUID
    var endStyle: EndingEndStyle

    init(request: EndingEditorRequest) {
        endingID = request.endingID
        type = request.type
        label = request.label
        startMeasureID = request.startMeasureID
        endMeasureID = request.endMeasureID
        endStyle = request.endStyle
    }

    var normalizedLabel: String {
        RoadmapObject.normalizedEndingDisplayText(label) ?? ""
    }

    func hasValidRange(in chart: Chart) -> Bool {
        let measureIDs = chart.measures.map(\.id)
        guard let startIndex = measureIDs.firstIndex(of: startMeasureID),
              let endIndex = measureIDs.firstIndex(of: endMeasureID) else { return false }
        return startIndex <= endIndex
    }

    func canApply(to chart: Chart) -> Bool {
        !normalizedLabel.isEmpty && hasValidRange(in: chart)
    }

    @discardableResult
    func apply(to chart: inout Chart) -> UUID? {
        guard canApply(to: chart) else { return nil }
        if let endingID {
            guard let ending = chart.roadmapObject(id: endingID), ending.type.isEnding else { return nil }
            _ = chart.updateEndingDetails(
                endingID,
                startMeasureID: startMeasureID,
                endMeasureID: endMeasureID,
                displayText: normalizedLabel,
                endStyle: endStyle
            )
            return endingID
        }
        return chart.addEndingSpan(
            type,
            startMeasureID: startMeasureID,
            endMeasureID: endMeasureID,
            displayText: normalizedLabel,
            endStyle: endStyle
        )
    }
}

struct EndingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var chart: Chart
    private let request: EndingEditorRequest
    private let onApplied: (UUID) -> Void
    private let onDeleted: () -> Void
    private let onCancelled: () -> Void

    @State private var draft: EndingEditorDraft
    @State private var isLabelFocused = false
    @State private var showingDeleteConfirmation = false
    @State private var operationError: String?

    init(
        chart: Binding<Chart>,
        request: EndingEditorRequest,
        onApplied: @escaping (UUID) -> Void,
        onDeleted: @escaping () -> Void,
        onCancelled: @escaping () -> Void = {}
    ) {
        _chart = chart
        self.request = request
        self.onApplied = onApplied
        self.onDeleted = onDeleted
        self.onCancelled = onCancelled
        _draft = State(initialValue: EndingEditorDraft(request: request))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IChartTypedTextField(
                        placeholder: "Ending label",
                        text: $draft.label,
                        isFocused: $isLabelFocused,
                        borderStyle: .none
                    )
                    .frame(minHeight: 56)
                    .accessibilityLabel("Ending label")
                    .accessibilityIdentifier("ending-editor-label")
                    .accessibilityHint("Write with Scribble, or tap the keyboard icon to type")
                    .background(IChartTypedSheetScrollSupport())

                    HStack(spacing: 12) {
                        ForEach(["1.", "2."], id: \.self) { preset in
                            Button(preset) {
                                draft.label = preset
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Use ending label \(preset)")
                        }
                    }
                } header: {
                    Text("Ending label")
                } footer: {
                    Text("Write any label, such as 1, 2, 3; 1–3, 5; or On cue.")
                }

                Section("Measures") {
                    Picker("Start measure", selection: $draft.startMeasureID) {
                        measureOptions
                    }
                    Picker("End measure", selection: $draft.endMeasureID) {
                        measureOptions
                    }
                    if !draft.hasValidRange(in: chart) {
                        Text("Choose an end measure at or after the start measure.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Right edge", selection: $draft.endStyle) {
                        ForEach(EndingEndStyle.allCases) { style in
                            Text(style.displayText).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Ending right edge")
                } header: {
                    Text("Right edge")
                } footer: {
                    Text("Closed adds a downward hook. Open leaves the bracket open at its end.")
                }

                Section("Preview") {
                    EndingLabelPreview(chart: chart, label: draft.normalizedLabel, endStyle: draft.endStyle)
                        .frame(minHeight: 88)
                        .listRowBackground(Color.white)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Ending \(draft.normalizedLabel), \(draft.endStyle.displayText.lowercased()) right edge")
                }

                if request.endingID != nil {
                    Section {
                        Button("Delete Ending", role: .destructive) {
                            isLabelFocused = false
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(request.endingID == nil ? "Add Ending" : "Edit Ending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PencilOnlyActionButton(title: "Cancel", style: .plain, acceptsDirectTouches: true) {
                        isLabelFocused = false
                        onCancelled()
                        dismiss()
                    }
                    .frame(width: 66, height: 44)
                    .accessibilityIdentifier("ending-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    PencilOnlyActionButton(
                        title: "Apply",
                        style: .plain,
                        isEnabled: draft.canApply(to: chart),
                        acceptsDirectTouches: true,
                        action: applyChanges
                    )
                    .frame(width: 58, height: 44)
                    .disabled(!draft.canApply(to: chart))
                    .accessibilityIdentifier("ending-editor-apply")
                }
            }
            .alert("Delete Ending?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Ending", role: .destructive, action: deleteEnding)
            } message: {
                Text("Delete this ending bracket and its label?")
            }
            .alert("Ending Could Not Be Saved", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK", role: .cancel) { operationError = nil }
            } message: {
                Text(operationError ?? "")
            }
        }
        .presentationDetents([.large])
    }

    private var measureOptions: some View {
        ForEach(Array(chart.measures.enumerated()), id: \.element.id) { index, measure in
            Text("Measure \(index + 1)").tag(measure.id)
        }
    }

    private func applyChanges() {
        isLabelFocused = false
        guard let endingID = draft.apply(to: &chart) else {
            operationError = "The ending or measure range is no longer available. Close the editor and choose the ending or measures again."
            return
        }
        onApplied(endingID)
        dismiss()
    }

    private func deleteEnding() {
        guard let endingID = request.endingID else { return }
        isLabelFocused = false
        _ = chart.deleteRoadmapObject(endingID)
        onDeleted()
        dismiss()
    }
}

private struct EndingLabelPreview: UIViewRepresentable {
    let chart: Chart
    let label: String
    let endStyle: EndingEndStyle

    func makeUIView(context: Context) -> EndingLabelPreviewView {
        EndingLabelPreviewView()
    }

    func updateUIView(_ view: EndingLabelPreviewView, context: Context) {
        view.chart = chart
        view.label = label
        view.endStyle = endStyle
        view.invalidateIntrinsicContentSize()
        view.setNeedsDisplay()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EndingLabelPreviewView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let metrics = LeadSheetEndingTextLayout.metrics(text: label, width: max(1, width - 36), chart: chart)
        return CGSize(width: width, height: max(88, metrics.bandHeight + 32))
    }
}

private final class EndingLabelPreviewView: UIView {
    var chart = Chart.blank(title: "Ending Preview")
    var label = ""
    var endStyle: EndingEndStyle = .closed

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .white
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 32 else { return }
        let labelWidth = max(1, bounds.width - 36)
        let metrics = LeadSheetEndingTextLayout.metrics(text: label, width: labelWidth, chart: chart)
        let bracketFrame = CGRect(x: 12, y: 16, width: bounds.width - 24, height: metrics.bandHeight)
        let layout = LeadSheetEndingLayout(
            roadmapObjectID: UUID(),
            systemIndex: 0,
            type: .ending1,
            text: label,
            frame: bracketFrame,
            showsText: true,
            showsLeadingHook: true,
            showsTrailingHook: endStyle == .closed,
            labelFrame: CGRect(x: bracketFrame.minX + 6, y: bracketFrame.minY + 4, width: labelWidth, height: max(1, bracketFrame.height - 4)),
            labelFontSize: metrics.fontSize,
            labelLineCount: metrics.lineCount
        )
        LeadSheetNotationRenderer(chart: chart).drawEnding(layout)
    }
}

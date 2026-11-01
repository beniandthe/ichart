#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit

struct ChordDraftEndingReviewSheet: View {
    private let request: PendingChordDraftEndingReview
    private let onApply: (String, EndingEndStyle, ClosedRange<Int>) -> Void
    private let onCancel: () -> Void
    @State private var label: String
    @State private var endStyle: EndingEndStyle
    @State private var startMeasure: Int?
    @State private var endMeasure: Int?
    @State private var isLabelFocused = false

    init(
        request: PendingChordDraftEndingReview,
        onApply: @escaping (String, EndingEndStyle, ClosedRange<Int>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onApply = onApply
        self.onCancel = onCancel
        _label = State(initialValue: request.ending.label)
        _endStyle = State(initialValue: request.ending.endStyle)
        _startMeasure = State(initialValue: request.measureRange?.lowerBound)
        _endMeasure = State(initialValue: request.measureRange?.upperBound)
    }

    private var normalizedLabel: String {
        RoadmapObject.normalizedEndingDisplayText(label) ?? ""
    }

    private var selectedRange: ClosedRange<Int>? {
        guard let startMeasure, let endMeasure,
              startMeasure >= 1, startMeasure <= endMeasure,
              endMeasure <= request.availableMeasureCount else { return nil }
        return startMeasure...endMeasure
    }

    private var canUseEnding: Bool {
        !normalizedLabel.isEmpty && selectedRange != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let range = selectedRange {
                        Label(measureRangeText(range), systemImage: "music.note.list")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("draft-ending-review-measures")
                        Text("Based on the existing and drawn barlines.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Measure range needs review", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("Choose the measures below. If measure choices are unavailable, finish reviewing the drawn barlines and repeat signs first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let image = sourceImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 170)
                            .padding(.vertical, 8)
                            .accessibilityLabel("Original handwritten ending bracket and label")
                    }
                    Text("The bracket suggests a range. You can correct its start and end measures below without redrawing the ink.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Your ending")
                }
                .listRowBackground(Color.white)

                Section {
                    if request.availableMeasureCount > 0 {
                        Picker("Start measure", selection: $startMeasure) {
                            measureOptions
                        }
                        .accessibilityIdentifier("draft-ending-review-start-measure")
                        Picker("End measure", selection: $endMeasure) {
                            measureOptions
                        }
                        .accessibilityIdentifier("draft-ending-review-end-measure")
                        if let startMeasure, let endMeasure, startMeasure > endMeasure {
                            Text("Choose an end measure at or after the start measure.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("Finish reviewing the drawn barlines and repeat signs, then review this ending again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Measures")
                } footer: {
                    Text("Measure numbers include the barlines in the current draft.")
                }

                Section {
                    IChartTypedTextField(
                        placeholder: "Ending label",
                        text: $label,
                        isFocused: $isLabelFocused,
                        borderStyle: .none
                    )
                    .frame(minHeight: 56)
                    .accessibilityLabel("Ending label")
                    .accessibilityIdentifier("draft-ending-review-label")
                    .accessibilityHint("Write with Scribble, or tap the keyboard icon to type")
                    .background(IChartTypedSheetScrollSupport(monitorsKeyboardReachability: true))
                    HStack(spacing: 12) {
                        ForEach(["1.", "2.", "3."], id: \.self) { preset in
                            Button(preset) { label = preset }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Use ending label \(preset)")
                        }
                    }
                } header: {
                    Text("Ending label")
                } footer: {
                    Text("Write or type any label, such as 1–3, 5; Last time; or On cue. Labels from the chart ink are shown above for you to review.")
                }

                Section {
                    Picker("Right edge", selection: $endStyle) {
                        ForEach(EndingEndStyle.allCases) { style in
                            Text(style.displayText).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("draft-ending-review-right-edge")
                } header: {
                    Text("Right edge")
                } footer: {
                    Text("Closed adds a downward hook. Open leaves the bracket open at its end.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review Ending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PencilOnlyActionButton(title: "Back to Ink", style: .plain, acceptsDirectTouches: true) {
                        isLabelFocused = false
                        onCancel()
                    }
                    .frame(width: 100, height: 44)
                    .accessibilityIdentifier("draft-ending-review-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    PencilOnlyActionButton(
                        title: "Use Ending", style: .plain,
                        isEnabled: canUseEnding,
                        acceptsDirectTouches: true
                    ) {
                        isLabelFocused = false
                        guard canUseEnding, let range = selectedRange else { return }
                        onApply(normalizedLabel, endStyle, range)
                    }
                    .frame(width: 104, height: 44)
                    .disabled(!canUseEnding)
                    .accessibilityIdentifier("draft-ending-review-apply")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var sourceImage: UIImage? {
        guard let drawing = try? PKDrawing(data: request.sourceEndingDrawingData) else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        guard !bounds.isNull, !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite else { return nil }
        return drawing.image(from: bounds, scale: 2)
    }

    private func measureRangeText(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? "Measure \(range.lowerBound)"
            : "Measures \(range.lowerBound)–\(range.upperBound)"
    }

    private var measureOptions: some View {
        Group {
            Text("Choose").tag(nil as Int?)
            if request.availableMeasureCount > 0 {
                ForEach(1...request.availableMeasureCount, id: \.self) { index in
                    Text("Measure \(index)").tag(Optional(index))
                }
            }
        }
    }
}
#endif

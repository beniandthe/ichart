#if canImport(UIKit)
import SwiftUI

private let timeSignaturePresets: [Meter] = [
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

struct TimeSignatureToolControls<Done: View>: View {
    let hasTarget: Bool
    let onChoosePreset: (Meter) -> Void
    let onCustom: () -> Void
    @ViewBuilder let done: () -> Done

    @ScaledMetric(relativeTo: .caption) private var buttonWidth: CGFloat = 72

    var body: some View {
        FlowLayout(spacing: 5, rowSpacing: 5, centersRows: true) {
            ForEach(timeSignaturePresets, id: \.self) { meter in
                action(meter.displayText) { onChoosePreset(meter) }
                    .accessibilityIdentifier("editor-time-signature-\(meter.numerator)-\(meter.denominator)")
            }

            action("Custom…", onPress: onCustom)
                .accessibilityHint("Choose your own numerator and denominator.")
                .accessibilityIdentifier("editor-time-signature-custom")
            done()
        }
    }

    private func action(_ title: String, onPress: @escaping () -> Void) -> some View {
        IChartTapFeedbackButton(isRaised: true, action: onPress) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasTarget ? Color.primary : Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
                .frame(minWidth: buttonWidth, minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
        }
        .disabled(!hasTarget)
    }
}

/// Custom entry and placement share one presentation. Editing a meter never
/// changes the chart until the user chooses how far to apply it in the scope.
struct TimeSignaturePlacementFlow<Scope: View>: View {
    private let initialMeter: Meter
    private let scope: (Meter) -> Scope
    @State private var selectedMeter: Meter?

    init(initialMeter: Meter, startsWithCustomEntry: Bool, @ViewBuilder scope: @escaping (Meter) -> Scope) {
        self.initialMeter = initialMeter
        self.scope = scope
        _selectedMeter = State(initialValue: startsWithCustomEntry ? nil : initialMeter)
    }

    var body: some View {
        if let selectedMeter {
            scope(selectedMeter)
        } else {
            CustomTimeSignatureEntry(initialMeter: initialMeter) { meter in
                selectedMeter = meter
            }
        }
    }
}

private struct CustomTimeSignatureEntry: View {
    private static let numeratorRange = 1...24
    private static let denominators = [2, 4, 8, 16]

    @Environment(\.dismiss) private var dismiss
    @State private var numerator: Int
    @State private var denominator: Int
    private let onContinue: (Meter) -> Void

    init(initialMeter: Meter, onContinue: @escaping (Meter) -> Void) {
        let range = Self.numeratorRange
        _numerator = State(initialValue: min(max(initialMeter.numerator, range.lowerBound), range.upperBound))
        _denominator = State(initialValue: Self.denominators.contains(initialMeter.denominator)
            ? initialMeter.denominator : 4)
        self.onContinue = onContinue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Numerator") {
                    HStack(spacing: 8) {
                        adjustNumerator(by: -1)
                        Text("\(numerator)")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Numerator \(numerator)")
                            .accessibilityIdentifier("editor-custom-meter-numerator")
                        adjustNumerator(by: 1)
                    }
                }

                Section("Denominator") {
                    HStack(spacing: 6) {
                        ForEach(Self.denominators, id: \.self) { value in
                            denominatorButton(value)
                        }
                    }
                }
            }
            .navigationTitle("Custom Time Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        onContinue(Meter(numerator: numerator, denominator: denominator))
                    }
                    .accessibilityIdentifier("editor-custom-meter-continue")
                }
            }
        }
        .presentationDetents([.height(340), .large])
    }

    private func adjustNumerator(by delta: Int) -> some View {
        let isIncrease = delta > 0
        return IChartTapFeedbackButton(isRaised: true) {
            let nextValue = numerator + delta
            guard Self.numeratorRange.contains(nextValue) else { return }
            numerator = nextValue
        } label: {
            Image(systemName: isIncrease ? "plus" : "minus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: EditorCommandLayoutPolicy.minimumTapTarget,
                    height: EditorCommandLayoutPolicy.minimumTapTarget)
        }
        .buttonRepeatBehavior(.enabled)
        .disabled(!Self.numeratorRange.contains(numerator + delta))
        .accessibilityLabel(isIncrease ? "Increase numerator" : "Decrease numerator")
        .accessibilityIdentifier(isIncrease ? "editor-custom-meter-increase" : "editor-custom-meter-decrease")
    }

    private func denominatorButton(_ value: Int) -> some View {
        let isSelected = denominator == value
        return IChartTapFeedbackButton(isRaised: true) {
            denominator = value
        } label: {
            Text("\(value)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
                .background(isSelected ? IChartInterfaceStyle.actionBlue : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("editor-custom-meter-denominator-\(value)")
    }
}
#endif

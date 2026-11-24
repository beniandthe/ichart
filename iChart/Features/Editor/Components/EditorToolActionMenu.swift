import SwiftUI

/// An anchored menu with app-drawn rows that share the editor's button feedback.
struct EditorToolActionMenu<Trigger: View>: View {
    private let cornerRadius: CGFloat
    private let menuIdentifier: String
    private let contents: AnyView
    private let label: () -> Trigger

    @State private var isPresented = false
    @State private var acknowledgement: UUID?

    init<Contents: View>(
        cornerRadius: CGFloat = 8,
        menuIdentifier: String,
        @ViewBuilder content: () -> Contents,
        @ViewBuilder label: @escaping () -> Trigger
    ) {
        self.cornerRadius = cornerRadius
        self.menuIdentifier = menuIdentifier
        self.contents = AnyView(content())
        self.label = label
    }

    var body: some View {
        Button {
            acknowledgement = UUID()
            isPresented = true
        } label: {
            label()
        }
        .buttonStyle(IChartTapFeedbackButtonStyle(
            isAcknowledged: acknowledgement != nil,
            cornerRadius: cornerRadius
        ))
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            ViewThatFits(in: .vertical) {
                rows.fixedSize(horizontal: false, vertical: true)
                ScrollView { rows }
            }
            .frame(idealWidth: 320, maxWidth: 320)
            .frame(maxHeight: 360)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(menuIdentifier)
            .presentationCompactAdaptation(.popover)
        }
        .task(id: acknowledgement) {
            guard let current = acknowledgement else { return }
            do {
                try await Task.sleep(for: .milliseconds(140))
            } catch {
                return
            }
            if acknowledgement == current { acknowledgement = nil }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) { contents }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .environment(\.editorToolMenuRowActivated, {
                isPresented = false
                acknowledgement = UUID()
            })
    }
}

struct EditorToolMenuRow: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let role: ButtonRole?
    private let identifier: String?
    private let action: () -> Void

    @Environment(\.editorToolMenuRowActivated) private var rowActivated
    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        role: ButtonRole? = nil,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.role = role
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            rowActivated()
            action()
        } label: {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if isSelected {
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(rowColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: EditorCommandLayoutPolicy.minimumTapTarget, alignment: .leading)
        }
        .buttonStyle(.iChartTapFeedback)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? title)
    }

    private var rowColor: Color {
        guard isEnabled else { return .secondary }
        return role == .destructive ? .red : .primary
    }
}

struct EditorToolMenuHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EditorToolMenuRowActivatedKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private extension EnvironmentValues {
    var editorToolMenuRowActivated: () -> Void {
        get { self[EditorToolMenuRowActivatedKey.self] }
        set { self[EditorToolMenuRowActivatedKey.self] = newValue }
    }
}

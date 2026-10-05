import SwiftUI

/// Selects indexes into the unchanged saved source. Display transforms never
/// become teaching geometry; applying is a local draft edit owned by the caller.
struct PersonalHandwritingStrokeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let strokes: [InkStroke]
    let isDisabled: Bool
    let errorMessage: String?
    let onApply: ([Int]) -> Void
    @State private var selectedIndexes: Set<Int>
    @State private var overlappingStrokeHint = false

    init(strokes: [InkStroke], initialSelection: [Int], isDisabled: Bool = false,
         errorMessage: String? = nil, onApply: @escaping ([Int]) -> Void) {
        self.strokes = strokes
        self.isDisabled = isDisabled
        self.errorMessage = errorMessage
        self.onApply = onApply
        _selectedIndexes = State(initialValue: Set(initialSelection))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select the whole strokes containing one symbol. Tap the ink or use the stroke buttons below; selected strokes are blue and thicker.")
                        .font(.callout).foregroundStyle(.secondary)
                    GeometryReader { proxy in
                        PersonalHandwritingStrokeSelectionPreview(strokes: strokes, selectedIndexes: selectedIndexes)
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { tap in
                                guard !isDisabled else { return }
                                switch PersonalHandwritingStrokeSelectionGeometry(strokes: strokes)
                                    .hitTest(tap.location, in: proxy.size) {
                                case .stroke(let index):
                                    toggleStroke(index)
                                    overlappingStrokeHint = false
                                case .overlap: overlappingStrokeHint = true
                                case .none: break
                                }
                            })
                            .allowsHitTesting(!isDisabled)
                    }
                    .frame(height: 220)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Original saved handwriting")
                    .accessibilityValue("\(selectedIndexes.count) of \(strokes.count) strokes selected")
                    .accessibilityHint("Use the individual stroke buttons below to change the selection.")
                    .accessibilityIdentifier("personal.symbolSelectionCanvas")
                    Label("\(selectedIndexes.count) of \(strokes.count) strokes selected", systemImage: "checkmark.circle")
                        .font(.headline)
                        .accessibilityIdentifier("personal.symbolSelectionCount")
                    if overlappingStrokeHint {
                        Text("These strokes overlap. Use the stroke buttons below to choose exactly which one to include.")
                            .font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("personal.symbolSelectionOverlap")
                    }
                    Text("Selecting ink from another piece moves it into this piece. Any piece whose ink changes will need its label chosen again. Unselected ink stays in the saved example.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("A connected stroke cannot be split here. If one stroke contains more than one symbol, leave it untaught and write the symbol separately in Choose Examples.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                            .accessibilityIdentifier("personal.symbolSelectionApplyError")
                    }
                    Text("Individual strokes").font(.headline)
                    LazyVStack(spacing: 8) {
                        ForEach(Array(strokes.indices), id: \.self) { index in
                            strokeButton(index)
                        }
                    }
                }
                .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Select Symbol Ink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        guard !isDisabled else { return }
                        dismiss()
                    }
                        .disabled(isDisabled)
                        .accessibilityIdentifier("personal.cancelSymbolSelection")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard !isDisabled, !selectedIndexes.isEmpty else { return }
                        onApply(selectedIndexes.sorted())
                    }
                    .disabled(isDisabled || selectedIndexes.isEmpty)
                    .accessibilityIdentifier("personal.applySymbolSelection")
                }
            }
        }
    }

    private func strokeButton(_ index: Int) -> some View {
        let isSelected = selectedIndexes.contains(index)
        return Button {
            guard !isDisabled else { return }
            toggleStroke(index)
            overlappingStrokeHint = false
        } label: {
            HStack(spacing: 16) {
                PersonalHandwritingStrokeSelectionPreview(
                    strokes: [strokes[index]], selectedIndexes: isSelected ? [0] : []
                )
                .frame(width: 88, height: 56)
                .accessibilityHidden(true)
                Text("Stroke \(index + 1)").foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(isDisabled)
        .accessibilityLabel("Stroke \(index + 1)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double-tap to \(isSelected ? "exclude" : "include") this whole stroke.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("personal.symbolStroke.\(index)")
    }

    private func toggleStroke(_ index: Int) {
        if selectedIndexes.contains(index) { selectedIndexes.remove(index) }
        else { selectedIndexes.insert(index) }
    }
}

private struct PersonalHandwritingStrokeSelectionPreview: View {
    let strokes: [InkStroke]
    let selectedIndexes: Set<Int>

    var body: some View {
        Canvas { context, size in
            let geometry = PersonalHandwritingStrokeSelectionGeometry(strokes: strokes)
            // Draw selected ink last so its outline remains visible at crossings.
            let indexes = strokes.indices.filter { !selectedIndexes.contains($0) }
                + strokes.indices.filter { selectedIndexes.contains($0) }
            for index in indexes {
                let points = strokes[index].points.map { geometry.location($0, in: size) }
                guard let first = points.first else { continue }
                let selected = selectedIndexes.contains(index)
                let color: Color = selected ? .blue : .primary.opacity(0.65)
                if points.count == 1 {
                    let radius: CGFloat = selected ? 3 : 1.5
                    context.fill(Path(ellipseIn: CGRect(x: first.x - radius, y: first.y - radius,
                                                       width: radius * 2, height: radius * 2)), with: .color(color))
                } else {
                    var path = Path()
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    context.stroke(path, with: .color(color),
                                   style: StrokeStyle(lineWidth: selected ? 4 : 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Shared display and tap geometry, with an explicit overlap result so a tap
/// never silently chooses between indistinguishable source strokes.
struct PersonalHandwritingStrokeSelectionGeometry {
    enum Hit: Equatable { case none, stroke(Int), overlap }
    let strokes: [InkStroke]
    private let bounds: InkBounds

    init(strokes: [InkStroke]) {
        self.strokes = strokes
        bounds = InkBounds.enclosing(strokes.flatMap(\.points))
    }

    func location(_ point: InkPoint, in size: CGSize) -> CGPoint {
        let scale = min(max(1, size.width - 40) / max(1, bounds.width),
                        max(1, size.height - 40) / max(1, bounds.height))
        return CGPoint(x: (size.width - bounds.width * scale) / 2 + (point.x - bounds.minX) * scale,
                       y: (size.height - bounds.height * scale) / 2 + (point.y - bounds.minY) * scale)
    }

    func hitTest(_ location: CGPoint, in size: CGSize, tolerance: CGFloat = 18) -> Hit {
        let candidates = strokes.enumerated().compactMap { index, stroke -> (Int, CGFloat)? in
            let points = stroke.points.map { self.location($0, in: size) }
            guard let first = points.first else { return nil }
            let distance: CGFloat
            if points.count == 1 { distance = hypot(location.x - first.x, location.y - first.y) }
            else {
                distance = zip(points, points.dropFirst()).map { start, end in
                    Self.distance(location, toSegmentFrom: start, to: end)
                }.min() ?? .infinity
            }
            return distance <= tolerance ? (index, distance) : nil
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        guard let nearest = candidates.first else { return .none }
        if candidates.count > 1, candidates[1].1 - nearest.1 <= 3 { return .overlap }
        return .stroke(nearest.0)
    }

    private static func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let fraction = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength))
        return hypot(point.x - (start.x + fraction * dx), point.y - (start.y + fraction * dy))
    }
}

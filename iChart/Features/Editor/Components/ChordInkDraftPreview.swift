#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit

enum ChordInkDraftPreviewPolicy {
    static let recognitionDelay: TimeInterval = 0.58
    static let maximumSingleTargetStrokeCount = 16
    static let maximumBatchTargetStrokeCount = 16
}

enum ChordInkDraftPreviewRecognitionLoadPolicy {
    private static let minimumTargetWidth = 10.0
    private static let minimumTargetHeight = 12.0
    private static let minimumTargetArea = 140.0
    private static let verticalShardMinimumHeight = 20.0
    private static let verticalShardMaximumWidthToHeightRatio = 0.22

    static func shouldRecognizeSingleTarget(strokeCount: Int, flow: ChordInkRecognitionFlow) -> Bool {
        flow != .draftPreview || strokeCount <= ChordInkDraftPreviewPolicy.maximumSingleTargetStrokeCount
    }

    static func shouldRecognizeSingleTarget(strokes: [InkStroke], flow: ChordInkRecognitionFlow) -> Bool {
        guard shouldRecognizeSingleTarget(strokeCount: strokes.count, flow: flow) else {
            return false
        }

        return flow != .draftPreview || hasChordTargetEvidence(strokes)
    }

    static func boundedBatchTargets(
        _ targets: [LeadSheetChordInkRecognitionBatchTarget],
        flow: ChordInkRecognitionFlow
    ) -> [LeadSheetChordInkRecognitionBatchTarget] {
        guard flow == .draftPreview else {
            return targets
        }

        return targets.filter { target in
            target.strokes.count <= ChordInkDraftPreviewPolicy.maximumBatchTargetStrokeCount
                && hasChordTargetEvidence(target.strokes)
        }
    }

    static func hasChordTargetEvidence(_ strokes: [InkStroke]) -> Bool {
        guard !strokes.isEmpty else {
            return false
        }

        let bounds = InkBounds.enclosing(strokes.map(\.bounds))
        guard bounds.width >= minimumTargetWidth,
              bounds.height >= minimumTargetHeight,
              bounds.width * bounds.height >= minimumTargetArea else {
            return false
        }

        let widthToHeightRatio = bounds.width / max(1, bounds.height)
        if bounds.height >= verticalShardMinimumHeight,
           widthToHeightRatio <= verticalShardMaximumWidthToHeightRatio {
            return false
        }

        return true
    }
}

struct ChordInkDraftVisibleDrawingContext {
    var drawing: PKDrawing
    var originalStrokeIndices: [Int]
    var invisibleStrokeIndices: Set<Int>

    var visibleStrokeCount: Int {
        drawing.strokes.count
    }

    func originalStrokeIndices(for visibleStrokeIndices: Set<Int>) -> Set<Int> {
        Set(
            visibleStrokeIndices.compactMap { visibleIndex in
                guard originalStrokeIndices.indices.contains(visibleIndex) else {
                    return nil
                }
                return originalStrokeIndices[visibleIndex]
            }
        )
    }

    func remappedBarlineRecognition(
        _ recognition: ChordDraftBarlineRecognition
    ) -> ChordDraftBarlineRecognition {
        ChordDraftBarlineRecognition(
            barlines: recognition.barlines.map { barline in
                var remappedBarline = barline
                if let visibleSourceStrokeIndex = barline.sourceStrokeIndex,
                   originalStrokeIndices.indices.contains(visibleSourceStrokeIndex) {
                    remappedBarline.sourceStrokeIndex = originalStrokeIndices[visibleSourceStrokeIndex]
                }
                return remappedBarline
            },
            strokeIndices: originalStrokeIndices(for: recognition.strokeIndices)
        )
    }
}

enum ChordInkDraftVisibleStrokePolicy {
    private static let minimumVisibleArea: CGFloat = 8
    private static let minimumVisibleSpan: CGFloat = 5

    static func visibleDrawingContext(from drawing: PKDrawing) -> ChordInkDraftVisibleDrawingContext {
        var visibleStrokes = [PKStroke]()
        var originalStrokeIndices = [Int]()
        var invisibleStrokeIndices = Set<Int>()

        for (index, stroke) in drawing.strokes.enumerated() {
            if isVisible(stroke) {
                visibleStrokes.append(stroke)
                originalStrokeIndices.append(index)
            } else {
                invisibleStrokeIndices.insert(index)
            }
        }

        return ChordInkDraftVisibleDrawingContext(
            drawing: PKDrawing(strokes: visibleStrokes),
            originalStrokeIndices: originalStrokeIndices,
            invisibleStrokeIndices: invisibleStrokeIndices
        )
    }

    static func visibleStrokeCount(in drawing: PKDrawing) -> Int {
        visibleDrawingContext(from: drawing).visibleStrokeCount
    }

    static func isVisible(_ stroke: PKStroke) -> Bool {
        isVisible(renderBounds: stroke.renderBounds)
    }

    static func isVisible(renderBounds: CGRect) -> Bool {
        let bounds = renderBounds.standardized
        guard !bounds.isNull,
              !bounds.isEmpty,
              !bounds.isInfinite else {
            return false
        }

        let width = max(0, bounds.width)
        let height = max(0, bounds.height)
        return width * height >= minimumVisibleArea
            || max(width, height) >= minimumVisibleSpan
    }
}

enum ChordDraftBarlineSpacingMode: String, CaseIterable, Identifiable {
    case drawn
    case even

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .drawn:
            return "Drawn"
        case .even:
            return "Even"
        }
    }

    var detailText: String {
        switch self {
        case .drawn:
            return "Measure spans follow the barlines you draw."
        case .even:
            return "Draft barlines become evenly spaced measures on render."
        }
    }

    func boundaryFractions(for drawnFractions: [Double]) -> [Double] {
        let sortedFractions = drawnFractions
            .map { min(max($0, 0.0001), 0.9999) }
            .sorted()
        guard !sortedFractions.isEmpty else {
            return []
        }

        switch self {
        case .drawn:
            return sortedFractions
        case .even:
            return (1...sortedFractions.count).map { index in
                Double(index) / Double(sortedFractions.count + 1)
            }
        }
    }
}

struct ChordInkDraftAnchor: Hashable {
    var measureID: UUID
    var fractionBucket: Int

    init(measureID: UUID, fraction: Double?) {
        self.measureID = measureID
        let clampedFraction = min(max(fraction ?? 0, 0), 0.9999)
        self.fractionBucket = Int((clampedFraction * 32).rounded())
    }
}

struct ChordInkDraftLaneLocation: Hashable {
    var systemIndex: Int
    var fraction: Double

    init(systemIndex: Int, fraction: Double) {
        self.systemIndex = systemIndex
        self.fraction = min(max(fraction, 0), 0.9999)
    }

    var visualOrder: Double {
        Double(systemIndex) + fraction
    }
}

struct ChordInkDraftInput: Hashable {
    var measureID: UUID
    var measureIndex: Int
    var targetFraction: Double?
    var visualOrder: Double? = nil
    var laneLocation: ChordInkDraftLaneLocation? = nil
    var layoutPageSize: CGSize? = nil
    var drawingData: Data
    var candidateTexts: [String]
    var bestCandidateText: String?
    var confidence: Double
    var strokeCount: Int

    var anchor: ChordInkDraftAnchor {
        ChordInkDraftAnchor(measureID: measureID, fraction: targetFraction)
    }
}

enum ChordInkDraftPreviewDeduplicationPolicy {
    private static let duplicateLaneFractionDistance = 0.08

    private enum MergeRelationship {
        case sameDisplayText
        case sameRootExpanded
    }

    static func deduplicated(_ inputs: [ChordInkDraftInput]) -> [ChordInkDraftInput] {
        let orderedInputs = inputs.sorted(by: isOrderedBefore)
        var deduplicatedInputs: [ChordInkDraftInput] = []

        for input in orderedInputs {
            guard let duplicateIndex = deduplicatedInputs.lastIndex(where: { isDuplicate($0, input) }) else {
                deduplicatedInputs.append(input)
                continue
            }

            deduplicatedInputs[duplicateIndex] = preferredDuplicate(
                deduplicatedInputs[duplicateIndex],
                input
            )
        }

        return deduplicatedInputs.sorted(by: isOrderedBefore)
    }

    private static func isDuplicate(_ lhs: ChordInkDraftInput, _ rhs: ChordInkDraftInput) -> Bool {
        guard lhs.measureID == rhs.measureID,
              mergeRelationship(lhs, rhs) != nil,
              sameSourceInk(lhs, rhs),
              sameLane(lhs, rhs),
              let lhsFraction = laneFraction(lhs),
              let rhsFraction = laneFraction(rhs) else {
            return false
        }

        return abs(lhsFraction - rhsFraction) <= duplicateLaneFractionDistance
    }

    private static func preferredDuplicate(
        _ lhs: ChordInkDraftInput,
        _ rhs: ChordInkDraftInput
    ) -> ChordInkDraftInput {
        if mergeRelationship(lhs, rhs) == .sameRootExpanded {
            return richness(lhs) >= richness(rhs) ? lhs : rhs
        }

        if lhs.strokeCount != rhs.strokeCount {
            return lhs.strokeCount > rhs.strokeCount ? lhs : rhs
        }

        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence ? lhs : rhs
        }

        return isOrderedBefore(lhs, rhs) ? lhs : rhs
    }

    private static func mergeRelationship(
        _ lhs: ChordInkDraftInput,
        _ rhs: ChordInkDraftInput
    ) -> MergeRelationship? {
        guard let lhsPreviewText = normalizedPreviewText(lhs),
              let rhsPreviewText = normalizedPreviewText(rhs) else {
            return nil
        }

        if lhsPreviewText == rhsPreviewText {
            return .sameDisplayText
        }

        guard let lhsMatch = ChordRecognitionCompendium.match(lhsPreviewText),
              let rhsMatch = ChordRecognitionCompendium.match(rhsPreviewText),
              lhsMatch.symbol.kind == .rooted,
              rhsMatch.symbol.kind == .rooted,
              lhsMatch.symbol.root == rhsMatch.symbol.root,
              lhsMatch.symbol.accidental == rhsMatch.symbol.accidental,
              min(richness(lhs), richness(rhs)) == 0,
              max(richness(lhs), richness(rhs)) > 0 else {
            return nil
        }

        return .sameRootExpanded
    }

    private static func richness(_ input: ChordInkDraftInput) -> Int {
        guard let previewText = normalizedPreviewText(input),
              let match = ChordRecognitionCompendium.match(previewText),
              match.symbol.kind == .rooted else {
            return 0
        }

        let symbol = match.symbol
        return symbol.quality.count
            + symbol.extensions.joined().count
            + symbol.alterations.joined().count
            + (symbol.slashBass?.count ?? 0)
    }

    private static func normalizedPreviewText(_ input: ChordInkDraftInput) -> String? {
        normalizedText(input.bestCandidateText) ?? input.candidateTexts.compactMap(normalizedText).first
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private static func sameLane(_ lhs: ChordInkDraftInput, _ rhs: ChordInkDraftInput) -> Bool {
        if let lhsLaneLocation = lhs.laneLocation,
           let rhsLaneLocation = rhs.laneLocation {
            return lhsLaneLocation.systemIndex == rhsLaneLocation.systemIndex
        }

        if let lhsLaneIndex = laneIndex(lhs),
           let rhsLaneIndex = laneIndex(rhs) {
            return lhsLaneIndex == rhsLaneIndex
        }

        return true
    }

    private static func sameSourceInk(_ lhs: ChordInkDraftInput, _ rhs: ChordInkDraftInput) -> Bool {
        lhs.drawingData == rhs.drawingData
    }

    private static func laneIndex(_ input: ChordInkDraftInput) -> Int? {
        if let laneLocation = input.laneLocation {
            return laneLocation.systemIndex
        }

        guard let visualOrder = input.visualOrder else {
            return nil
        }

        return Int(floor(visualOrder))
    }

    private static func laneFraction(_ input: ChordInkDraftInput) -> Double? {
        if let laneLocation = input.laneLocation {
            return laneLocation.fraction
        }

        if let visualOrder = input.visualOrder {
            return min(max(visualOrder - floor(visualOrder), 0), 0.9999)
        }

        guard let targetFraction = input.targetFraction else {
            return nil
        }

        return min(max(targetFraction, 0), 0.9999)
    }

    private static func isOrderedBefore(_ lhs: ChordInkDraftInput, _ rhs: ChordInkDraftInput) -> Bool {
        let lhsVisualOrder = lhs.laneLocation?.visualOrder
            ?? lhs.visualOrder
            ?? Double(lhs.measureIndex) + (lhs.targetFraction ?? 0)
        let rhsVisualOrder = rhs.laneLocation?.visualOrder
            ?? rhs.visualOrder
            ?? Double(rhs.measureIndex) + (rhs.targetFraction ?? 0)
        if lhsVisualOrder != rhsVisualOrder {
            return lhsVisualOrder < rhsVisualOrder
        }

        if lhs.measureIndex == rhs.measureIndex {
            return (lhs.targetFraction ?? 0) < (rhs.targetFraction ?? 0)
        }

        return lhs.measureIndex < rhs.measureIndex
    }
}

struct ChordInkDraft: Identifiable, Hashable {
    var id: UUID
    var anchor: ChordInkDraftAnchor
    var measureID: UUID
    var measureIndex: Int
    var targetFraction: Double?
    var visualOrder: Double?
    var laneLocation: ChordInkDraftLaneLocation?
    var layoutPageSize: CGSize?
    var drawingData: Data
    var candidateTexts: [String]
    var bestCandidateText: String?
    var selectedText: String?
    var confidence: Double
    var strokeCount: Int
    var isStale: Bool

    init(id: UUID = UUID(), input: ChordInkDraftInput, selectedText: String? = nil, isStale: Bool = false) {
        self.id = id
        self.anchor = input.anchor
        self.measureID = input.measureID
        self.measureIndex = input.measureIndex
        self.targetFraction = input.targetFraction
        self.visualOrder = input.visualOrder
        self.laneLocation = input.laneLocation
        self.layoutPageSize = input.layoutPageSize
        self.drawingData = input.drawingData
        self.candidateTexts = input.candidateTexts
        self.bestCandidateText = input.bestCandidateText
        self.selectedText = selectedText
        self.confidence = input.confidence
        self.strokeCount = input.strokeCount
        self.isStale = isStale
    }

    var previewText: String? {
        normalizedText(selectedText) ?? normalizedText(bestCandidateText) ?? candidateTexts.compactMap(normalizedText).first
    }

    var isRenderable: Bool {
        guard let previewText else {
            return false
        }

        return ChordRecognitionCompendium.match(previewText) != nil
    }

    var sourceCandidateSignature: [String] {
        ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }
}

struct DraftBarlineGestureMetrics: Hashable {
    var height: Double
    var width: Double
    var angleDegreesFromVertical: Double
    var straightness: Double
    var laneCoverage: Double
}

enum DraftBarlineAmbiguity: String, Hashable {
    case none
    case tooShort
    case tooWide
    case tooSlanted
    case tooCurved
    case outOfLane
    case tooClose
}

struct DraftBarline: Identifiable, Hashable {
    var id: UUID
    var measureID: UUID
    var measureIndex: Int
    var fraction: Double
    var laneLocation: ChordInkDraftLaneLocation?
    var layoutPageSize: CGSize?
    var sourceStrokeIndex: Int?
    var metrics: DraftBarlineGestureMetrics
    var ambiguity: DraftBarlineAmbiguity

    init(
        id: UUID = UUID(),
        measureID: UUID,
        measureIndex: Int,
        fraction: Double,
        laneLocation: ChordInkDraftLaneLocation? = nil,
        layoutPageSize: CGSize? = nil,
        sourceStrokeIndex: Int? = nil,
        metrics: DraftBarlineGestureMetrics,
        ambiguity: DraftBarlineAmbiguity = .none
    ) {
        self.id = id
        self.measureID = measureID
        self.measureIndex = measureIndex
        self.fraction = min(max(fraction, 0), 0.9999)
        self.laneLocation = laneLocation
        self.layoutPageSize = layoutPageSize
        self.sourceStrokeIndex = sourceStrokeIndex
        self.metrics = metrics
        self.ambiguity = ambiguity
    }

    var laneFraction: Double {
        laneLocation?.fraction ?? fraction
    }

    var visualOrder: Double {
        laneLocation?.visualOrder ?? Double(measureIndex) + fraction
    }

    var isRenderable: Bool {
        ambiguity == .none
    }
}

struct ChordDraftBarlineIdentitySignature: Hashable {
    var measureID: UUID
    var laneSystemIndex: Int?
    var fractionBucket: Int
    var sourceStrokeIndex: Int?

    init(
        measureID: UUID,
        laneLocation: ChordInkDraftLaneLocation?,
        fraction: Double,
        sourceStrokeIndex: Int?
    ) {
        self.measureID = measureID
        self.laneSystemIndex = laneLocation?.systemIndex
        self.fractionBucket = Int((min(max(laneLocation?.fraction ?? fraction, 0), 0.9999) * 64).rounded())
        self.sourceStrokeIndex = sourceStrokeIndex
    }
}

extension DraftBarline {
    var identitySignature: ChordDraftBarlineIdentitySignature {
        ChordDraftBarlineIdentitySignature(
            measureID: measureID,
            laneLocation: laneLocation,
            fraction: fraction,
            sourceStrokeIndex: sourceStrokeIndex
        )
    }
}

struct ChordPreviewState: Equatable {
    var draftChords: [ChordInkDraft] = []
    var draftBarlines: [DraftBarline] = []
    var layoutPageSize: CGSize?
    var updatedAt: Date?

    var isEmpty: Bool {
        draftChords.isEmpty && draftBarlines.isEmpty
    }

    var renderableDraftChords: [ChordInkDraft] {
        draftChords.filter(\.isRenderable)
    }

    var unresolvedChordCount: Int {
        draftChords.count - renderableDraftChords.count
    }

    var renderableBarlines: [DraftBarline] {
        draftBarlines.filter(\.isRenderable)
    }

    var unresolvedBarlineCount: Int {
        draftBarlines.count - renderableBarlines.count
    }

    var canRenderAllDraftChords: Bool {
        !draftChords.isEmpty && unresolvedChordCount == 0
    }

    var canRenderAny: Bool {
        canRenderAllDraftChords || !renderableBarlines.isEmpty
    }

    mutating func replaceDraftChords(with inputs: [ChordInkDraftInput], updatedAt: Date = .now) {
        let deduplicatedInputs = ChordInkDraftPreviewDeduplicationPolicy.deduplicated(inputs)
        let previousDraftByAnchor = Dictionary(
            draftChords.map { ($0.anchor, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        draftChords = deduplicatedInputs
            .map { input in
                let previousDraft = previousDraftByAnchor[input.anchor]
                return ChordInkDraft(
                    id: previousDraft?.id ?? UUID(),
                    input: input,
                    selectedText: previousDraft?.selectedText,
                    isStale: false
                )
            }
        layoutPageSize = deduplicatedInputs.compactMap(\.layoutPageSize).first ?? layoutPageSize
        self.updatedAt = updatedAt
    }

    mutating func replaceDraftBarlines(with barlines: [DraftBarline], updatedAt: Date = .now) {
        let previousDraftBySignature = Dictionary(
            draftBarlines.map { ($0.identitySignature, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        draftBarlines = barlines
            .sorted {
                if $0.visualOrder == $1.visualOrder {
                    if $0.measureIndex == $1.measureIndex {
                        return $0.fraction < $1.fraction
                    }

                    return $0.measureIndex < $1.measureIndex
                }

                return $0.visualOrder < $1.visualOrder
            }
            .map { barline in
                var resolvedBarline = barline
                if let previousDraft = previousDraftBySignature[barline.identitySignature] {
                    resolvedBarline.id = previousDraft.id
                }
                return resolvedBarline
            }
        layoutPageSize = barlines.compactMap(\.layoutPageSize).first ?? layoutPageSize
        self.updatedAt = updatedAt
    }

    @discardableResult
    mutating func removeDraftBarline(id: UUID, updatedAt: Date = .now) -> DraftBarline? {
        guard let index = draftBarlines.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let removedBarline = draftBarlines.remove(at: index)
        self.updatedAt = updatedAt
        return removedBarline
    }

    mutating func discard() {
        draftChords = []
        draftBarlines = []
        layoutPageSize = nil
        updatedAt = nil
    }
}

struct ChordDraftPreviewImplicitBarline: Identifiable, Hashable {
    var id: String
    var visualOrder: Double
    var laneLocation: ChordInkDraftLaneLocation
}

enum ChordDraftPreviewImplicitBarlinePolicy {
    private static let terminalLaneFraction = 0.9999
    private static let terminalDraftBarlineThreshold = 0.97

    static func terminalBarlines(
        for state: ChordPreviewState,
        chart: Chart
    ) -> [ChordDraftPreviewImplicitBarline] {
        guard !state.isEmpty,
              let pageSize = state.layoutPageSize else {
            return []
        }

        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let contentSystemIndices = systemIndicesWithPreviewContent(in: state)
        guard !contentSystemIndices.isEmpty else {
            return []
        }

        let systemsWithTerminalDraftBarlines = Set(
            state.draftBarlines.compactMap { barline -> Int? in
                guard let laneLocation = laneLocation(for: barline),
                      laneLocation.fraction >= terminalDraftBarlineThreshold else {
                    return nil
                }

                return laneLocation.systemIndex
            }
        )

        return pageLayout.systems.compactMap { system in
            guard contentSystemIndices.contains(system.index),
                  !systemsWithTerminalDraftBarlines.contains(system.index),
                  LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                    for: system,
                    paperFrame: pageLayout.paperFrame,
                    layoutStyle: chart.layoutStyle
                  ) != nil else {
                return nil
            }

            let laneLocation = ChordInkDraftLaneLocation(
                systemIndex: system.index,
                fraction: terminalLaneFraction
            )
            return ChordDraftPreviewImplicitBarline(
                id: "terminal-\(system.id.uuidString)",
                visualOrder: laneLocation.visualOrder,
                laneLocation: laneLocation
            )
        }
    }

    private static func systemIndicesWithPreviewContent(in state: ChordPreviewState) -> Set<Int> {
        let chordSystemIndices = state.draftChords.compactMap { draft -> Int? in
            laneLocation(for: draft)?.systemIndex
        }
        let barlineSystemIndices = state.draftBarlines.compactMap { barline -> Int? in
            guard let laneLocation = laneLocation(for: barline),
                  laneLocation.fraction < terminalDraftBarlineThreshold else {
                return nil
            }

            return laneLocation.systemIndex
        }

        return Set(chordSystemIndices + barlineSystemIndices)
    }

    private static func laneLocation(for draft: ChordInkDraft) -> ChordInkDraftLaneLocation? {
        if let laneLocation = draft.laneLocation {
            return laneLocation
        }

        if let visualOrder = draft.visualOrder {
            return laneLocation(forVisualOrder: visualOrder)
        }

        return nil
    }

    private static func laneLocation(for barline: DraftBarline) -> ChordInkDraftLaneLocation? {
        if let laneLocation = barline.laneLocation {
            return laneLocation
        }

        return laneLocation(forVisualOrder: barline.visualOrder)
    }

    private static func laneLocation(forVisualOrder visualOrder: Double) -> ChordInkDraftLaneLocation {
        ChordInkDraftLaneLocation(
            systemIndex: Int(floor(visualOrder)),
            fraction: visualOrder - floor(visualOrder)
        )
    }
}

struct ChordDraftBarlineControlFrames {
    var delete: CGRect
}

struct ChordDraftBarlineHitTarget: Equatable {
    enum Action: Equatable {
        case select
        case delete
    }

    var barlineID: UUID
    var action: Action
}

enum ChordDraftBarlineOverlayGeometry {
    static let lineHitWidth: CGFloat = 18
    static let deleteControlSize: CGFloat = 18
    static let deleteHitOutset: CGFloat = 12

    static func lineFrame(for barline: DraftBarline, in laneFrame: CGRect) -> CGRect {
        let boundedLaneFrame = laneFrame.insetBy(dx: 1, dy: 2)
        let x = boundedLaneFrame.minX + boundedLaneFrame.width * CGFloat(barline.laneFraction)
        return CGRect(
            x: x - lineHitWidth / 2,
            y: boundedLaneFrame.minY,
            width: lineHitWidth,
            height: boundedLaneFrame.height
        )
    }

    static func controlFrames(for barline: DraftBarline, in laneFrame: CGRect) -> ChordDraftBarlineControlFrames {
        let lineFrame = lineFrame(for: barline, in: laneFrame)
        return ChordDraftBarlineControlFrames(
            delete: CGRect(
                x: lineFrame.midX - deleteControlSize / 2,
                y: lineFrame.minY - deleteControlSize - 3,
                width: deleteControlSize,
                height: deleteControlSize
            )
        )
    }

    static func hitTarget(
        at location: CGPoint,
        barlines: [DraftBarline],
        laneFrameForBarline: (DraftBarline) -> CGRect?,
        selectedBarlineID: UUID?
    ) -> ChordDraftBarlineHitTarget? {
        for barline in barlines.reversed() {
            guard let laneFrame = laneFrameForBarline(barline) else {
                continue
            }

            if selectedBarlineID == barline.id {
                let controls = controlFrames(for: barline, in: laneFrame)
                if controls.delete.insetBy(dx: -deleteHitOutset, dy: -deleteHitOutset).contains(location) {
                    return ChordDraftBarlineHitTarget(barlineID: barline.id, action: .delete)
                }
            }

            if lineFrame(for: barline, in: laneFrame).insetBy(dx: 3, dy: 8).contains(location) {
                return ChordDraftBarlineHitTarget(
                    barlineID: barline.id,
                    action: selectedBarlineID == barline.id ? .delete : .select
                )
            }
        }

        return nil
    }
}

struct ChordDraftBarlineRecognition {
    var barlines: [DraftBarline]
    var strokeIndices: Set<Int>
}

enum ChordDraftBarlineRecognizer {
    private enum AcceptanceThresholds {
        static let minimumHeight: CGFloat = 22
        static let maximumHeightToLaneRatio: CGFloat = 1.35
        static let maximumAngleDegreesFromVertical = 18.0
        static let minimumStraightness = 0.74
        static let maximumWidthRatio = 0.24
        static let maximumAbsoluteWidth: CGFloat = 12
        static let minimumLaneCoverage = 0.62
    }

    static func recognize(
        strokes: [InkStroke],
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> ChordDraftBarlineRecognition {
        guard let pageLayout else {
            return ChordDraftBarlineRecognition(barlines: [], strokeIndices: [])
        }

        var acceptedBarlines = [(barline: DraftBarline, strokeIndex: Int)]()
        for indexedStroke in strokes.enumerated() {
            guard let barline = draftBarline(
                for: indexedStroke.element,
                chordFrame: chordFrame,
                pageLayout: pageLayout
            ) else {
                continue
            }

            acceptedBarlines.append((barline, indexedStroke.offset))
        }

        let deDuplicatedBarlines = removeVeryCloseBarlines(acceptedBarlines)

        return ChordDraftBarlineRecognition(
            barlines: deDuplicatedBarlines.map { pair in
                var barline = pair.barline
                barline.sourceStrokeIndex = pair.strokeIndex
                return barline
            },
            strokeIndices: Set(deDuplicatedBarlines.map(\.strokeIndex))
        )
    }

    private static func draftBarline(
        for stroke: InkStroke,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout
    ) -> DraftBarline? {
        guard stroke.points.count >= 2 else {
            return nil
        }

        let localBounds = stroke.bounds.cgRect
        let bounds = localBounds.offsetBy(dx: chordFrame.minX, dy: chordFrame.minY)
        guard bounds.height >= AcceptanceThresholds.minimumHeight else {
            return nil
        }

        let firstPoint = stroke.points[0].cgPoint.offsetBy(dx: chordFrame.minX, dy: chordFrame.minY)
        let lastPoint = stroke.points[stroke.points.count - 1].cgPoint.offsetBy(dx: chordFrame.minX, dy: chordFrame.minY)
        let dx = Double(abs(lastPoint.x - firstPoint.x))
        let dy = Double(abs(lastPoint.y - firstPoint.y))
        guard dy > 0 else {
            return nil
        }

        let angleDegrees = atan2(dx, dy) * 180 / .pi
        let pathLength = stroke.pathLength
        let diagonal = hypot(Double(bounds.width), Double(bounds.height))
        let straightness = pathLength > 0 ? min(max(diagonal / pathLength, 0), 1) : 0
        let widthRatio = Double(bounds.width / max(1, bounds.height))
        guard angleDegrees <= AcceptanceThresholds.maximumAngleDegreesFromVertical else {
            return nil
        }
        guard straightness >= AcceptanceThresholds.minimumStraightness else {
            return nil
        }
        guard widthRatio <= AcceptanceThresholds.maximumWidthRatio
                || bounds.width <= AcceptanceThresholds.maximumAbsoluteWidth else {
            return nil
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard let target = draftBarlineTarget(
            at: center,
            in: pageLayout
        ) else {
            return nil
        }

        let laneFrame = target.laneFrame
        let laneCoverage = Double(bounds.intersection(laneFrame).height / max(1, laneFrame.height))
        let heightToLaneRatio = bounds.height / max(1, laneFrame.height)
        guard laneCoverage >= AcceptanceThresholds.minimumLaneCoverage,
              heightToLaneRatio <= AcceptanceThresholds.maximumHeightToLaneRatio else {
            return nil
        }

        let rawFraction = (center.x - laneFrame.minX) / max(1, laneFrame.width)
        let metrics = DraftBarlineGestureMetrics(
            height: Double(bounds.height),
            width: Double(bounds.width),
            angleDegreesFromVertical: angleDegrees,
            straightness: straightness,
            laneCoverage: laneCoverage
        )
        return DraftBarline(
            measureID: target.measureID,
            measureIndex: target.measureIndex,
            fraction: Double(rawFraction),
            laneLocation: ChordInkDraftLaneLocation(
                systemIndex: target.systemIndex,
                fraction: Double(rawFraction)
            ),
            layoutPageSize: pageLayout.pageBounds.size,
            metrics: metrics
        )
    }

    private static func draftBarlineTarget(
        at center: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> (measureID: UUID, measureIndex: Int, systemIndex: Int, laneFrame: CGRect)? {
        for system in pageLayout.systems {
            guard let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame
            ),
                  laneFrame.insetBy(dx: -8, dy: -8).contains(center) else {
                continue
            }

            let measures = system.measures.compactMap { measure -> LeadSheetMeasureLayout? in
                guard measure.chordInkTargetMeasureID != nil else {
                    return nil
                }

                return measure
            }
            let measure = measures.first { measure in
                measure.chordWritingFrame.insetBy(dx: -8, dy: -8).contains(center)
            } ?? measures.last
            guard let measure,
                  let measureID = measure.chordInkTargetMeasureID else {
                return nil
            }

            return (measureID, measure.index, system.index, laneFrame)
        }

        return nil
    }

    private static func removeVeryCloseBarlines(
        _ barlines: [(barline: DraftBarline, strokeIndex: Int)]
    ) -> [(barline: DraftBarline, strokeIndex: Int)] {
        var retained = [(barline: DraftBarline, strokeIndex: Int)]()
        for barlinePair in barlines.sorted(by: { lhs, rhs in
            if lhs.barline.visualOrder == rhs.barline.visualOrder {
                return lhs.barline.fraction < rhs.barline.fraction
            }

            return lhs.barline.visualOrder < rhs.barline.visualOrder
        }) {
            if retained.contains(where: { existing in
                existing.barline.measureID == barlinePair.barline.measureID
                    && existing.barline.laneLocation?.systemIndex == barlinePair.barline.laneLocation?.systemIndex
                    && abs(existing.barline.laneFraction - barlinePair.barline.laneFraction) < 0.035
            }) {
                continue
            }

            retained.append(barlinePair)
        }

        return retained
    }
}

struct ChordInkDraftBatchRenderResult: Equatable {
    var renderedChordIDs: [UUID]
    var renderedBarlineIDs: [UUID]
    var unresolvedDraftIDs: [UUID]

    var renderedChordCount: Int {
        renderedChordIDs.count
    }

    var renderedBarlineCount: Int {
        renderedBarlineIDs.count
    }
}

extension Chart {
    private struct ChordDraftBarlineCommitPlan {
        var renderedBarlineIDs: [UUID]
        var segmentMeasureIDsByOriginalMeasureID: [UUID: [UUID]]
        var boundaryFractionsByOriginalMeasureID: [UUID: [Double]]
    }

    private struct ChordDraftResolvedRenderTarget {
        var draft: ChordInkDraft
        var measureID: UUID?
        var fraction: Double?
    }

    private struct ChordDraftBarlineSourceGeometry {
        var laneFrame: CGRect
        var measureFrame: CGRect
        var fractionFrame: CGRect
    }

    private struct ChordDraftBarlineLaneTarget {
        var measureID: UUID
        var measureIndex: Int
        var fraction: Double
        var sourceGeometry: ChordDraftBarlineSourceGeometry
    }

    @discardableResult
    mutating func commitChordInkDraftBatch(
        _ state: ChordPreviewState,
        barlineSpacingMode: ChordDraftBarlineSpacingMode = .drawn
    ) -> ChordInkDraftBatchRenderResult {
        let renderableBarlines = state.renderableBarlines
        let sourceLayout = state.layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: self,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        materializeSimpleChordDraftRowsIfNeeded(
            for: state.renderableDraftChords,
            barlines: renderableBarlines
        )
        let commitLayout = state.layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: self,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        let barlinePlan = commitDraftBarlinesBeforeChordRender(
            renderableBarlines,
            spacingMode: barlineSpacingMode,
            sourcePageLayout: sourceLayout,
            commitPageLayout: commitLayout
        )
        let renderLayout = state.layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: self,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        var renderedChordIDs = [UUID]()
        var unresolvedDraftIDs = [UUID]()
        let sortedDrafts = state.draftChords.sorted(by: { lhs, rhs in
            let lhsVisualOrder = lhs.laneLocation?.visualOrder
                ?? lhs.visualOrder
                ?? Double(lhs.measureIndex) + (lhs.targetFraction ?? 0)
            let rhsVisualOrder = rhs.laneLocation?.visualOrder
                ?? rhs.visualOrder
                ?? Double(rhs.measureIndex) + (rhs.targetFraction ?? 0)
            if lhsVisualOrder != rhsVisualOrder {
                return lhsVisualOrder < rhsVisualOrder
            }

            if lhs.measureIndex == rhs.measureIndex {
                return (lhs.targetFraction ?? 0) < (rhs.targetFraction ?? 0)
            }

            return lhs.measureIndex < rhs.measureIndex
        })
        let renderTargets = sortedDrafts.map { draft in
            let renderTarget = chordDraftRenderTarget(
                for: draft,
                sourcePageLayout: sourceLayout,
                renderPageLayout: renderLayout,
                barlinePlan: barlinePlan
            )
            return ChordDraftResolvedRenderTarget(
                draft: draft,
                measureID: renderTarget?.measureID,
                fraction: renderTarget?.fraction
            )
        }

        for renderTarget in renderTargets {
            let draft = renderTarget.draft
            guard let measureID = renderTarget.measureID,
                  let previewText = draft.previewText,
                  let match = ChordRecognitionCompendium.match(previewText),
                  let chordEventID = appendRecognizedChordEvent(
                    match.symbol,
                    rawInput: previewText,
                    to: measureID,
                    atFraction: renderTarget.fraction,
                    sourceInkData: draft.drawingData,
                    sourceCandidateSignature: draft.sourceCandidateSignature
                  ) else {
                unresolvedDraftIDs.append(draft.id)
                continue
            }

            if layoutStyle == .simpleChordSheet,
               measure(id: measureID)?.rhythmMap == nil,
               let fraction = renderTarget.fraction {
                _ = setChordEventManualLaneFraction(fraction, for: chordEventID)
            }
            renderedChordIDs.append(chordEventID)
        }

        if unresolvedDraftIDs.isEmpty,
           !renderedChordIDs.isEmpty || !barlinePlan.renderedBarlineIDs.isEmpty {
            _ = setPageHandwrittenChordDrawing(nil)
        }

        return ChordInkDraftBatchRenderResult(
            renderedChordIDs: renderedChordIDs,
            renderedBarlineIDs: barlinePlan.renderedBarlineIDs,
            unresolvedDraftIDs: unresolvedDraftIDs
        )
    }

    private mutating func materializeSimpleChordDraftRowsIfNeeded(
        for drafts: [ChordInkDraft],
        barlines: [DraftBarline] = []
    ) {
        guard layoutStyle == .simpleChordSheet,
              let targetSystemIndex = (
                drafts.compactMap { $0.laneLocation?.systemIndex }
                    + barlines.compactMap { $0.laneLocation?.systemIndex }
              ).max(),
              targetSystemIndex > 0 else {
            return
        }

        while systems.count <= targetSystemIndex {
            guard materializeNextSimpleChordDraftRow() else {
                return
            }
        }
    }

    private mutating func materializeNextSimpleChordDraftRow() -> Bool {
        guard layoutStyle == .simpleChordSheet else {
            return false
        }

        let newOpenMeasureID: UUID
        if measures.contains(where: { $0.authoringState == .open }) {
            guard let committedOpenMeasureID = commitOpenMeasure(barlineAfter: .single) else {
                return false
            }
            newOpenMeasureID = committedOpenMeasureID
        } else {
            newOpenMeasureID = appendMeasure(authoringState: .open)
        }

        return insertSimpleSystemBreak(before: newOpenMeasureID)
    }

    @discardableResult
    mutating func commitChordInkDraftBarlines(
        _ barlines: [DraftBarline],
        layoutPageSize: CGSize?,
        barlineSpacingMode: ChordDraftBarlineSpacingMode = .drawn
    ) -> [UUID] {
        let renderableBarlines = barlines.filter(\.isRenderable)
        let sourceLayout = layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: self,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        materializeSimpleChordDraftRowsIfNeeded(for: [], barlines: renderableBarlines)
        let commitLayout = layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: self,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        let barlinePlan = commitDraftBarlinesBeforeChordRender(
            renderableBarlines,
            spacingMode: barlineSpacingMode,
            sourcePageLayout: sourceLayout,
            commitPageLayout: commitLayout
        )
        return barlinePlan.renderedBarlineIDs
    }

    private mutating func commitDraftBarlinesBeforeChordRender(
        _ barlines: [DraftBarline],
        spacingMode: ChordDraftBarlineSpacingMode,
        sourcePageLayout: LeadSheetPageLayout?,
        commitPageLayout: LeadSheetPageLayout?
    ) -> ChordDraftBarlineCommitPlan {
        var renderedBarlineIDs = [UUID]()
        var segmentMeasureIDsByOriginalMeasureID = [UUID: [UUID]]()
        var boundaryFractionsByOriginalMeasureID = [UUID: [Double]]()
        let resolution = resolvedDraftBarlinesForCommit(
            barlines,
            sourcePageLayout: sourcePageLayout,
            commitPageLayout: commitPageLayout
        )
        let resolvedBarlines = resolution.barlines
        let sortedBarlinesByMeasureID = Dictionary(grouping: resolvedBarlines.sorted(by: { lhs, rhs in
            if lhs.visualOrder == rhs.visualOrder {
                if lhs.measureIndex == rhs.measureIndex {
                    return lhs.fraction < rhs.fraction
                }

                return lhs.measureIndex < rhs.measureIndex
            }

            return lhs.visualOrder < rhs.visualOrder
        })) { $0.measureID }

        let orderedMeasureIDs = sortedBarlinesByMeasureID.keys.sorted { lhs, rhs in
            let lhsIndex = sortedBarlinesByMeasureID[lhs]?.first?.measureIndex ?? 0
            let rhsIndex = sortedBarlinesByMeasureID[rhs]?.first?.measureIndex ?? 0
            return lhsIndex < rhsIndex
        }

        for measureID in orderedMeasureIDs {
            guard let measureBarlines = sortedBarlinesByMeasureID[measureID],
                  !measureBarlines.isEmpty else {
                continue
            }

            segmentMeasureIDsByOriginalMeasureID[measureID] = [measureID]
            boundaryFractionsByOriginalMeasureID[measureID] = []
            let boundaryFractions = spacingMode.boundaryFractions(for: measureBarlines.map(\.fraction))
            var previousBoundaryFraction = Double(0)

            for (barlineIndex, barline) in measureBarlines.enumerated() {
                guard boundaryFractions.indices.contains(barlineIndex),
                      let currentSegmentMeasureID = segmentMeasureIDsByOriginalMeasureID[measureID]?.last else {
                    continue
                }

                let boundaryFraction = boundaryFractions[barlineIndex]
                let localSplitFraction = (boundaryFraction - previousBoundaryFraction)
                    / max(0.0001, 1 - previousBoundaryFraction)
                guard let newSegmentMeasureID = splitSimpleChordMeasure(
                    currentSegmentMeasureID,
                    atFraction: localSplitFraction,
                    barlineAfter: .single
                ) else {
                    continue
                }

                segmentMeasureIDsByOriginalMeasureID[measureID, default: [measureID]]
                    .append(newSegmentMeasureID)
                boundaryFractionsByOriginalMeasureID[measureID, default: []]
                    .append(boundaryFraction)
                previousBoundaryFraction = boundaryFraction
                renderedBarlineIDs.append(barline.id)
            }

            applyDraftBarlineSegmentWidths(
                originalMeasureID: measureID,
                segmentMeasureIDs: segmentMeasureIDsByOriginalMeasureID[measureID] ?? [],
                boundaryFractions: boundaryFractionsByOriginalMeasureID[measureID] ?? [],
                sourceGeometryOverride: resolution.sourceGeometryByMeasureID[measureID],
                sourcePageLayout: sourcePageLayout
            )
        }

        return ChordDraftBarlineCommitPlan(
            renderedBarlineIDs: renderedBarlineIDs,
            segmentMeasureIDsByOriginalMeasureID: segmentMeasureIDsByOriginalMeasureID,
            boundaryFractionsByOriginalMeasureID: boundaryFractionsByOriginalMeasureID
        )
    }

    private func resolvedDraftBarlinesForCommit(
        _ barlines: [DraftBarline],
        sourcePageLayout: LeadSheetPageLayout?,
        commitPageLayout: LeadSheetPageLayout?
    ) -> (barlines: [DraftBarline], sourceGeometryByMeasureID: [UUID: ChordDraftBarlineSourceGeometry]) {
        guard let sourcePageLayout else {
            return (barlines, [:])
        }

        var sourceGeometryByMeasureID = [UUID: ChordDraftBarlineSourceGeometry]()
        let resolvedBarlines = barlines.compactMap { barline -> DraftBarline? in
            if isCommittedTerminalFillerLaneLocation(
                barline.laneLocation,
                in: sourcePageLayout
            ) {
                return nil
            }

            guard let sourceTarget = draftBarlineLaneTarget(
                for: barline,
                pageLayout: sourcePageLayout,
                rejectsCommittedTerminalFiller: true
            ) else {
                return barline
            }
            let commitTarget = commitPageLayout.flatMap {
                draftBarlineLaneTarget(
                    for: barline,
                    pageLayout: $0,
                    rejectsCommittedTerminalFiller: false
                )
            }

            var resolvedBarline = barline
            resolvedBarline.measureID = commitTarget?.measureID ?? sourceTarget.measureID
            resolvedBarline.measureIndex = commitTarget?.measureIndex ?? sourceTarget.measureIndex
            resolvedBarline.fraction = sourceTarget.fraction
            sourceGeometryByMeasureID[resolvedBarline.measureID] = sourceTarget.sourceGeometry
            return resolvedBarline
        }

        return (resolvedBarlines, sourceGeometryByMeasureID)
    }

    private func draftBarlineLaneTarget(
        for barline: DraftBarline,
        pageLayout: LeadSheetPageLayout,
        rejectsCommittedTerminalFiller: Bool = true
    ) -> ChordDraftBarlineLaneTarget? {
        guard let laneLocation = barline.laneLocation,
              let system = pageLayout.systems.first(where: { $0.index == laneLocation.systemIndex }),
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame
              ) else {
            return nil
        }

        let laneX = laneFrame.minX + laneFrame.width * CGFloat(laneLocation.fraction)
        if rejectsCommittedTerminalFiller,
           LeadSheetSimpleChordTerminalBarlineGeometry.terminalFillerContainsLaneX(
            laneX,
            in: system,
            paperFrame: pageLayout.paperFrame,
            layoutStyle: layoutStyle
           ) {
            return nil
        }

        let measures = system.measures.compactMap { measure -> LeadSheetMeasureLayout? in
            guard measure.chordInkTargetMeasureID != nil || measure.sourceMeasureID != nil else {
                return nil
            }

            return measure
        }
        guard !measures.isEmpty else {
            return nil
        }

        let targetMeasure = measures.first { measure in
            measure.chordWritingFrame.insetBy(dx: -4, dy: 0).minX <= laneX
                && laneX <= measure.chordWritingFrame.insetBy(dx: -4, dy: 0).maxX
        } ?? measures.min { lhs, rhs in
            horizontalDistance(from: laneX, to: lhs.chordWritingFrame)
                < horizontalDistance(from: laneX, to: rhs.chordWritingFrame)
        }

        guard let targetMeasure,
              let measureID = targetMeasure.chordInkTargetMeasureID ?? targetMeasure.sourceMeasureID else {
            return nil
        }

        let fraction = (laneX - targetMeasure.frame.minX)
            / max(1, targetMeasure.frame.width)
        return ChordDraftBarlineLaneTarget(
            measureID: measureID,
            measureIndex: targetMeasure.index,
            fraction: Double(min(max(fraction, 0), 0.9999)),
            sourceGeometry: ChordDraftBarlineSourceGeometry(
                laneFrame: laneFrame,
                measureFrame: targetMeasure.frame,
                fractionFrame: targetMeasure.frame
            )
        )
    }

    private mutating func applyDraftBarlineSegmentWidths(
        originalMeasureID: UUID,
        segmentMeasureIDs: [UUID],
        boundaryFractions: [Double],
        sourceGeometryOverride: ChordDraftBarlineSourceGeometry? = nil,
        sourcePageLayout: LeadSheetPageLayout?
    ) {
        guard layoutStyle == .simpleChordSheet,
              !segmentMeasureIDs.isEmpty,
              let sourceGeometry = sourceGeometryOverride ?? chordDraftBarlineSourceGeometry(
                for: originalMeasureID,
                sourcePageLayout: sourcePageLayout
              ),
              let maxSystemWidth = sourcePageLayout.map({ max(1, $0.paperFrame.width - 68) }) else {
            return
        }

        let sourceFrame = sourceGeometry.measureFrame
        let fractionFrame = sourceGeometry.fractionFrame
        let clampedBoundaryXs = boundaryFractions
            .map { boundaryFraction in
                fractionFrame.minX + fractionFrame.width * CGFloat(min(max(boundaryFraction, 0.0001), 0.9999))
            }
            .map {
                min(max($0, sourceFrame.minX + 1), sourceFrame.maxX - 1)
            }
            .sorted()
        let targetRowWidths = zip([sourceFrame.minX] + clampedBoundaryXs, clampedBoundaryXs + [sourceFrame.maxX]).map { lower, upper in
            max(1, upper - lower)
        }
        guard targetRowWidths.count == segmentMeasureIDs.count else {
            return
        }

        for (measureID, targetRowWidth) in zip(segmentMeasureIDs, targetRowWidths) {
            let manualLayoutWidth = LeadSheetPageLayoutEngine.simpleChordSheetManualLayoutWidthForTargetRowWidth(
                targetRowWidth,
                chart: self,
                maxSystemWidth: maxSystemWidth
            )
            setDraftBarlineSegmentManualLayoutWidth(
                manualLayoutWidth,
                for: measureID
            )
        }
    }

    private mutating func setDraftBarlineSegmentManualLayoutWidth(
        _ width: CGFloat,
        for measureID: UUID
    ) {
        let storedWidth = Double(min(max(width, 1), Measure.maximumManualLayoutWidth))
        for systemIndex in systems.indices {
            guard let measureIndex = systems[systemIndex].measures.firstIndex(where: { $0.id == measureID }) else {
                continue
            }

            systems[systemIndex].measures[measureIndex].manualLayoutWidth = storedWidth
            return
        }
    }

    private func chordDraftBarlineSourceGeometry(
        for originalMeasureID: UUID,
        sourcePageLayout: LeadSheetPageLayout?
    ) -> ChordDraftBarlineSourceGeometry? {
        guard let sourcePageLayout else {
            return nil
        }

        for system in sourcePageLayout.systems {
            guard let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                    for: system,
                    paperFrame: sourcePageLayout.paperFrame
                  ) else {
                continue
            }

            guard let measureFrame = system.measures.first(where: { measure in
                measure.chordInkTargetMeasureID == originalMeasureID
                    || measure.sourceMeasureID == originalMeasureID
            })?.frame else {
                continue
            }

            return ChordDraftBarlineSourceGeometry(
                laneFrame: laneFrame,
                measureFrame: measureFrame,
                fractionFrame: laneFrame
            )
        }

        return nil
    }

    private func chordDraftRenderTarget(
        for draft: ChordInkDraft,
        sourcePageLayout: LeadSheetPageLayout?,
        renderPageLayout: LeadSheetPageLayout?,
        barlinePlan: ChordDraftBarlineCommitPlan
    ) -> (measureID: UUID, fraction: Double?)? {
        let sourceAllowsLaneProjection: Bool
        if let sourcePageLayout,
           draft.laneLocation != nil {
            if isCommittedTerminalFillerLaneLocation(
                draft.laneLocation,
                in: sourcePageLayout
            ) {
                return nil
            }

            sourceAllowsLaneProjection = chordDraftLaneTarget(
                for: draft,
                pageLayout: sourcePageLayout,
                rejectsCommittedTerminalFiller: true
            ) != nil
        } else {
            sourceAllowsLaneProjection = false
        }

        if let renderPageLayout {
            if isCommittedTerminalFillerLaneLocation(
                draft.laneLocation,
                in: renderPageLayout
            ) {
                guard sourceAllowsLaneProjection else {
                    return nil
                }
            }

            if let laneTarget = chordDraftLaneTarget(
                for: draft,
                pageLayout: renderPageLayout,
                rejectsCommittedTerminalFiller: !sourceAllowsLaneProjection
            ) {
                return laneTarget
            }
        }

        if let segmentTarget = chordDraftSegmentTarget(
            for: draft,
            barlinePlan: barlinePlan
        ) {
            return segmentTarget
        }

        return (draft.measureID, draft.laneLocation?.fraction ?? draft.targetFraction)
    }

    private func isCommittedTerminalFillerLaneLocation(
        _ laneLocation: ChordInkDraftLaneLocation?,
        in pageLayout: LeadSheetPageLayout
    ) -> Bool {
        guard let laneLocation,
              let system = pageLayout.systems.first(where: { $0.index == laneLocation.systemIndex }),
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame
              ) else {
            return false
        }

        let laneX = laneFrame.minX + laneFrame.width * CGFloat(laneLocation.fraction)
        return LeadSheetSimpleChordTerminalBarlineGeometry.terminalFillerContainsLaneX(
            laneX,
            in: system,
            paperFrame: pageLayout.paperFrame,
            layoutStyle: layoutStyle
        )
    }

    private func chordDraftSegmentTarget(
        for draft: ChordInkDraft,
        barlinePlan: ChordDraftBarlineCommitPlan
    ) -> (measureID: UUID, fraction: Double?)? {
        guard let segmentMeasureIDs = barlinePlan.segmentMeasureIDsByOriginalMeasureID[draft.measureID],
              !segmentMeasureIDs.isEmpty,
              let laneFraction = draft.laneLocation?.fraction ?? draft.visualOrder.map({ $0 - floor($0) }) else {
            return nil
        }

        let boundaries = (barlinePlan.boundaryFractionsByOriginalMeasureID[draft.measureID] ?? [])
            .sorted()
        let segmentIndex = boundaries.firstIndex { laneFraction < $0 } ?? boundaries.count
        let clampedSegmentIndex = min(max(0, segmentIndex), segmentMeasureIDs.count - 1)
        let lowerBoundary = clampedSegmentIndex == 0 ? 0 : boundaries[clampedSegmentIndex - 1]
        let upperBoundary = clampedSegmentIndex < boundaries.count ? boundaries[clampedSegmentIndex] : 1
        let localFraction = (laneFraction - lowerBoundary) / max(0.0001, upperBoundary - lowerBoundary)

        return (
            segmentMeasureIDs[clampedSegmentIndex],
            min(max(localFraction, 0), 0.9999)
        )
    }

    private func chordDraftLaneTarget(
        for draft: ChordInkDraft,
        pageLayout: LeadSheetPageLayout,
        rejectsCommittedTerminalFiller: Bool = true
    ) -> (measureID: UUID, fraction: Double?)? {
        guard let laneLocation = draft.laneLocation,
              let system = pageLayout.systems.first(where: { $0.index == laneLocation.systemIndex }),
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame
              ) else {
            return nil
        }

        let laneX = laneFrame.minX + laneFrame.width * CGFloat(laneLocation.fraction)
        if rejectsCommittedTerminalFiller,
           LeadSheetSimpleChordTerminalBarlineGeometry.terminalFillerContainsLaneX(
            laneX,
            in: system,
            paperFrame: pageLayout.paperFrame,
            layoutStyle: layoutStyle
           ) {
            return nil
        }

        let measures = system.measures.compactMap { measure -> LeadSheetMeasureLayout? in
            guard measure.chordInkTargetMeasureID != nil else {
                return nil
            }

            return measure
        }
        guard !measures.isEmpty else {
            return nil
        }

        let targetMeasure = measures.first { measure in
            measure.chordWritingFrame.insetBy(dx: -4, dy: 0).minX <= laneX
                && laneX <= measure.chordWritingFrame.insetBy(dx: -4, dy: 0).maxX
        } ?? measures.min { lhs, rhs in
            horizontalDistance(from: laneX, to: lhs.chordWritingFrame)
                < horizontalDistance(from: laneX, to: rhs.chordWritingFrame)
        }

        guard let targetMeasure,
              let measureID = targetMeasure.chordInkTargetMeasureID else {
            return nil
        }

        let fraction = (laneX - targetMeasure.chordBandFrame.minX)
            / max(1, targetMeasure.chordBandFrame.width)
        return (measureID, Double(min(max(fraction, 0), 0.9999)))
    }

    private func horizontalDistance(from x: CGFloat, to frame: CGRect) -> CGFloat {
        if x < frame.minX {
            return frame.minX - x
        }
        if x > frame.maxX {
            return x - frame.maxX
        }
        return 0
    }
}

private extension InkBounds {
    var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}

private extension InkPoint {
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

private extension InkStroke {
    var pathLength: Double {
        guard points.count > 1 else {
            return 0
        }

        return zip(points, points.dropFirst()).reduce(0) { partial, pair in
            let dx = pair.1.x - pair.0.x
            let dy = pair.1.y - pair.0.y
            return partial + hypot(dx, dy)
        }
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}
#endif

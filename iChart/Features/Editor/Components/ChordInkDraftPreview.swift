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
        Set(originalStrokeIndices).count
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
                remappedBarline.sourceStrokeIndices = originalStrokeIndices(for: barline.ownedSourceStrokeIndices)
                return remappedBarline
            },
            strokeIndices: originalStrokeIndices(for: recognition.strokeIndices)
        )
    }

    func remappedEndingRecognition(_ recognition: ChordDraftEndingRecognition) -> ChordDraftEndingRecognition {
        let endings = recognition.endings.map { ending in
            var remapped = ending
            remapped.sourceStrokeIndices = originalStrokeIndices(for: ending.sourceStrokeIndices)
            return remapped
        }
        return ChordDraftEndingRecognition(endings: endings,
            strokeIndices: originalStrokeIndices(for: recognition.strokeIndices))
    }

    func endingRecognitionWithUnambiguousSourceStrokes(
        _ recognition: ChordDraftEndingRecognition
    ) -> ChordDraftEndingRecognition {
        let counts = originalStrokeIndices.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        let endings = recognition.endings.filter { ending in
            !ending.sourceStrokeIndices.isEmpty && ending.sourceStrokeIndices.allSatisfy { visibleIndex in
                originalStrokeIndices.indices.contains(visibleIndex)
                    && counts[originalStrokeIndices[visibleIndex]] == 1
            }
        }
        return ChordDraftEndingRecognition(endings: endings,
            strokeIndices: endings.reduce(into: Set<Int>()) { $0.formUnion($1.sourceStrokeIndices) })
    }

    /// A draft barline can be deleted only by removing its original PencilKit
    /// stroke from the live canvas. Bitmap erasing can split one original
    /// stroke into several visible fragments, so treating one of those
    /// fragments as a removable barline could also delete unrelated visible
    /// chord ink. Keep barline recognition only when the visible fragment has
    /// one-to-one ownership of its original stroke.
    func barlineRecognitionWithUnambiguousSourceStrokes(
        _ recognition: ChordDraftBarlineRecognition
    ) -> ChordDraftBarlineRecognition {
        let visibleFragmentCountByOriginalIndex = originalStrokeIndices.reduce(
            into: [Int: Int](),
            { counts, originalIndex in
                counts[originalIndex, default: 0] += 1
            }
        )
        let safeBarlines = recognition.barlines.filter { barline in
            let owned = barline.ownedSourceStrokeIndices
            guard let anchor = barline.sourceStrokeIndex, owned.contains(anchor), !owned.isEmpty else {
                return false
            }
            return owned.allSatisfy { visibleIndex in
                guard originalStrokeIndices.indices.contains(visibleIndex) else {
                    return false
                }
                let originalIndex = originalStrokeIndices[visibleIndex]
                return visibleFragmentCountByOriginalIndex[originalIndex] == 1
            }
        }

        return ChordDraftBarlineRecognition(
            barlines: safeBarlines,
            strokeIndices: safeBarlines.reduce(into: Set<Int>()) { $0.formUnion($1.ownedSourceStrokeIndices) }
        )
    }
}

enum ChordInkDraftVisibleStrokePolicy {
    private static let minimumVisibleArea: CGFloat = 8
    private static let minimumVisibleSpan: CGFloat = 5

    /// Preserve small marks only when the structural reader can assign them
    /// to an unambiguous barline or ending.
    static func structuralVisibleDrawingContext(
        from drawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> ChordInkDraftVisibleDrawingContext {
        guard let pageLayout else { return visibleDrawingContext(from: drawing) }
        var fragments = [PKStroke]()
        var originalIndices = [Int]()
        for (index, stroke) in drawing.strokes.enumerated() {
            let visible = PencilKitInkAdapter.visibleStrokeFragments(from: stroke)
            fragments.append(contentsOf: visible)
            originalIndices.append(contentsOf: repeatElement(index, count: visible.count))
        }
        let fullContext = ChordInkDraftVisibleDrawingContext(
            drawing: PKDrawing(strokes: fragments),
            originalStrokeIndices: originalIndices,
            invisibleStrokeIndices: []
        )
        let allStrokes = PencilKitInkAdapter.inkStrokes(from: fullContext.drawing)
        let structures = ChordDraftEndingRecognizer.recognizeStructure(
            strokes: allStrokes, chordFrame: chordFrame, pageLayout: pageLayout)
        let endings = structures.endings
        let barlines = structures.barlines
        let promotedIndices = fullContext.barlineRecognitionWithUnambiguousSourceStrokes(barlines).strokeIndices
            .union(fullContext.endingRecognitionWithUnambiguousSourceStrokes(endings).strokeIndices)
        guard !promotedIndices.isEmpty else { return visibleDrawingContext(from: drawing) }
        let included = fragments.indices.filter { isVisible(fragments[$0]) || promotedIndices.contains($0) }
        let keptOriginalIndices = included.map { originalIndices[$0] }
        return ChordInkDraftVisibleDrawingContext(
            drawing: PKDrawing(strokes: included.map { fragments[$0] }),
            originalStrokeIndices: keptOriginalIndices,
            invisibleStrokeIndices: Set(drawing.strokes.indices).subtracting(keptOriginalIndices)
        )
    }

    static func visibleDrawingContext(from drawing: PKDrawing) -> ChordInkDraftVisibleDrawingContext {
        var visibleStrokes = [PKStroke]()
        var originalStrokeIndices = [Int]()
        var invisibleStrokeIndices = Set<Int>()

        for (index, stroke) in drawing.strokes.enumerated() {
            let fragments = PencilKitInkAdapter.visibleStrokeFragments(from: stroke)
                .filter(isVisible)
            if fragments.isEmpty {
                invisibleStrokeIndices.insert(index)
            } else {
                visibleStrokes.append(contentsOf: fragments)
                originalStrokeIndices.append(contentsOf: repeatElement(index, count: fragments.count))
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
    var laneSystemIndex: Int?
    var fractionBucket: Int

    init(measureID: UUID, laneLocation: ChordInkDraftLaneLocation?, visualOrder: Double?, fraction: Double?) {
        self.measureID = measureID
        if let laneLocation {
            self.laneSystemIndex = laneLocation.systemIndex
        } else if let visualOrder {
            self.laneSystemIndex = Int(floor(visualOrder))
        } else {
            self.laneSystemIndex = nil
        }
        let clampedFraction = min(max(laneLocation?.fraction ?? fraction ?? 0, 0), 0.9999)
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
    var recognitionResult: ChordInkRecognitionResult? = nil
    var primaryDecision: ChordInkRecognitionDecision? = nil
    var recognitionDecision: ChordInkRecognitionDecision? = nil
    var targetLifecycle: ChordInkRecognitionTargetLifecycle? = nil
    var requiresManualReviewOnly: Bool = false

    var anchor: ChordInkDraftAnchor {
        ChordInkDraftAnchor(
            measureID: measureID,
            laneLocation: laneLocation,
            visualOrder: visualOrder,
            fraction: targetFraction
        )
    }
}

enum ChordInkDraftPreviewResolutionReusePolicy {
    static func reusedInput(
        previousDraft: ChordInkDraft?,
        measureID: UUID,
        measureIndex: Int,
        targetFraction: Double?,
        visualOrder: Double?,
        laneLocation: ChordInkDraftLaneLocation?,
        layoutPageSize: CGSize?,
        drawingData: Data,
        strokeCount: Int,
        isRecognitionCacheHit: Bool,
        targetLifecycle: ChordInkRecognitionTargetLifecycle? = nil
    ) -> ChordInkDraftInput? {
        guard isRecognitionCacheHit,
              let previousDraft else {
            return nil
        }
        let incomingAnchor = ChordInkDraftAnchor(
            measureID: measureID,
            laneLocation: laneLocation,
            visualOrder: visualOrder,
            fraction: targetFraction
        )
        guard previousDraft.anchor == incomingAnchor,
              previousDraft.drawingData == drawingData else {
            return nil
        }

        return ChordInkDraftInput(
            measureID: measureID,
            measureIndex: measureIndex,
            targetFraction: targetFraction,
            visualOrder: visualOrder,
            laneLocation: laneLocation,
            layoutPageSize: layoutPageSize,
            drawingData: drawingData,
            candidateTexts: previousDraft.candidateTexts,
            bestCandidateText: previousDraft.bestCandidateText,
            confidence: previousDraft.confidence,
            strokeCount: strokeCount,
            recognitionResult: previousDraft.recognitionResult,
            primaryDecision: previousDraft.primaryDecision,
            recognitionDecision: previousDraft.recognitionDecision,
            targetLifecycle: targetLifecycle,
            requiresManualReviewOnly: previousDraft.requiresManualReviewOnly
        )
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
        ChordInkRenderResolutionPolicy.bestCandidateText(
            preferredTexts: [input.bestCandidateText],
            candidateTexts: input.candidateTexts
        )
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
    var recognitionResult: ChordInkRecognitionResult?
    var primaryDecision: ChordInkRecognitionDecision?
    var recognitionDecision: ChordInkRecognitionDecision?
    var targetLifecycle: ChordInkRecognitionTargetLifecycle?
    var requiresManualReviewOnly: Bool
    var requiresSeparatedChordInk = false

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
        // A stale absorbed target deliberately has no supported suggestion:
        // source ownership must be repaired before reusing its old read.
        let resultCandidateTexts = isStale ? []
            : input.recognitionResult.map(ChordInkRenderResolutionPolicy.candidateTexts(for:)) ?? []
        let userFacingCandidateTexts = ChordRecognitionCompendium.userFacingCandidateTexts(
            from: input.candidateTexts + resultCandidateTexts
        )
        self.candidateTexts = userFacingCandidateTexts
        self.bestCandidateText = ChordInkRenderResolutionPolicy.bestCandidateText(
            preferredTexts: [
                input.bestCandidateText,
                isStale ? nil : input.recognitionDecision?.acceptedText,
                isStale ? nil : input.recognitionResult?.match?.displayText
            ],
            candidateTexts: userFacingCandidateTexts
        )
        self.selectedText = selectedText
        self.confidence = input.confidence
        self.strokeCount = input.strokeCount
        self.isStale = isStale
        self.recognitionResult = input.recognitionResult
        self.primaryDecision = input.primaryDecision
        self.recognitionDecision = input.recognitionDecision
        self.targetLifecycle = input.targetLifecycle
        self.requiresManualReviewOnly = input.requiresManualReviewOnly
    }

    var previewText: String? {
        guard !requiresSeparatedChordInk else { return nil }
        if let selectedText,
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // An invalid explicit edit must stay unresolved; falling back to
            // recognition here would render a different chord than was entered.
            return ChordInkRenderResolutionPolicy.bestCandidateText(
                preferredTexts: [selectedText], candidateTexts: []
            )
        }
        guard recognitionResult?.requiresTriangleQualityReview != true else { return nil }
        return ChordInkRenderResolutionPolicy.bestCandidateText(
            preferredTexts: [bestCandidateText],
            candidateTexts: candidateTexts
        )
    }

    var previewDisplayText: String {
        requiresSeparatedChordInk ? "Separate chords" : (previewText ?? "Add chord")
    }

    var isRenderable: Bool {
        guard let previewText else {
            return false
        }

        return ChordRecognitionCompendium.match(previewText) != nil
    }

    var requiresConfirmation: Bool {
        if let recognitionDecision {
            return recognitionDecision.action == .confirm
        }

        return recognitionResult != nil
    }

    var sourceCandidateSignature: [String] {
        ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
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

enum DraftBarlineKind: String, Hashable {
    case single

    var displayName: String { "Barline" }
}

/// Admission at an existing divider confirms that divider rather than
/// splitting off a narrow duplicate measure.
enum ChordDraftBarlineBoundaryPlacement: Equatable {
    case leading
    case interior
    case trailing

    static func placement(fraction: Double, sourceWidth: CGFloat,
                          barWidth: Double = 0, edgeTolerance: Double = 6) -> Self {
        let tolerance = min(0.15, (edgeTolerance + barWidth / 2) / max(1, Double(sourceWidth)))
        if fraction <= tolerance { return .leading }
        if fraction >= 1 - tolerance { return .trailing }
        return .interior
    }
}

struct DraftBarline: Identifiable, Hashable {
    var id: UUID
    var measureID: UUID
    var measureIndex: Int
    var fraction: Double
    var laneLocation: ChordInkDraftLaneLocation?
    var layoutPageSize: CGSize?
    var sourceStrokeIndex: Int?
    var kind: DraftBarlineKind
    var sourceStrokeIndices: Set<Int>
    var sourceStrokeGeometry: [InkStroke]
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
        ambiguity: DraftBarlineAmbiguity = .none,
        kind: DraftBarlineKind = .single,
        sourceStrokeIndices: Set<Int> = [],
        sourceStrokeGeometry: [InkStroke] = []
    ) {
        self.id = id
        self.measureID = measureID
        self.measureIndex = measureIndex
        self.fraction = min(max(fraction, 0), 0.9999)
        self.laneLocation = laneLocation
        self.layoutPageSize = layoutPageSize
        self.sourceStrokeIndex = sourceStrokeIndex
        self.kind = kind
        self.sourceStrokeIndices = sourceStrokeIndices
        self.sourceStrokeGeometry = sourceStrokeGeometry
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

    var ownedSourceStrokeIndices: Set<Int> {
        sourceStrokeIndices.isEmpty ? Set(sourceStrokeIndex.map { [$0] } ?? []) : sourceStrokeIndices
    }
}

struct ChordDraftBarlineIdentitySignature: Hashable {
    var measureID: UUID
    var laneSystemIndex: Int?
    var fractionBucket: Int
    var sourceStrokeIndex: Int?
    var kind: DraftBarlineKind
    var sourceStrokeIndices: Set<Int>
    var sourceStrokeGeometry: [InkStroke]

    init(
        measureID: UUID,
        laneLocation: ChordInkDraftLaneLocation?,
        fraction: Double,
        sourceStrokeIndex: Int?,
        kind: DraftBarlineKind = .single,
        sourceStrokeIndices: Set<Int> = [],
        sourceStrokeGeometry: [InkStroke] = []
    ) {
        self.measureID = measureID
        self.laneSystemIndex = laneLocation?.systemIndex
        self.fractionBucket = Int((min(max(laneLocation?.fraction ?? fraction, 0), 0.9999) * 64).rounded())
        self.sourceStrokeIndex = sourceStrokeIndex
        self.kind = kind
        self.sourceStrokeIndices = sourceStrokeIndices.isEmpty
            ? Set(sourceStrokeIndex.map { [$0] } ?? []) : sourceStrokeIndices
        self.sourceStrokeGeometry = sourceStrokeGeometry
    }
}

extension DraftBarline {
    var identitySignature: ChordDraftBarlineIdentitySignature {
        ChordDraftBarlineIdentitySignature(
            measureID: measureID,
            laneLocation: laneLocation,
            fraction: fraction,
            sourceStrokeIndex: sourceStrokeIndex,
            kind: kind,
            sourceStrokeIndices: ownedSourceStrokeIndices,
            sourceStrokeGeometry: sourceStrokeGeometry
        )
    }
}

struct ChordPreviewState: Equatable {
    private static let minimumDetachedAddedStrokeGap: CGFloat = 24
    private static let minimumUnresolvedAddedStrokeGap: CGFloat = 10

    var draftChords: [ChordInkDraft] = []
    var draftBarlines: [DraftBarline] = []
    var draftEndings: [DraftEnding] = []
    var layoutPageSize: CGSize?
    var updatedAt: Date?

    var isEmpty: Bool {
        draftChords.isEmpty && draftBarlines.isEmpty && draftEndings.isEmpty
    }

    var renderableDraftChords: [ChordInkDraft] {
        draftChords.filter(\.isRenderable)
    }

    var draftsRequiringConfirmation: [ChordInkDraft] {
        draftChords.filter { !$0.isRenderable || $0.requiresConfirmation }
    }

    var requiresChordConfirmation: Bool {
        !draftsRequiringConfirmation.isEmpty
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

    var renderableEndings: [DraftEnding] { draftEndings.filter(\.isRenderable) }
    var unresolvedEndingCount: Int { draftEndings.count - renderableEndings.count }

    var canRenderAllDraftChords: Bool {
        !draftChords.isEmpty && unresolvedChordCount == 0
    }

    var canRenderAny: Bool {
        canRenderAllDraftChords || !renderableBarlines.isEmpty || !draftEndings.isEmpty
    }

    /// Review can recover a represented unread chord without granting it a
    /// recognition match or automatic trust. Source coverage is checked again
    /// by the atomic commit before any ink can be consumed.
    var canReviewChordDrafts: Bool {
        !draftChords.isEmpty
    }

    mutating func replaceDraftChords(with inputs: [ChordInkDraftInput], updatedAt: Date = .now) {
        let deduplicatedInputs = ChordInkDraftPreviewDeduplicationPolicy.deduplicated(inputs)
        let previousRenderableDrafts = draftChords.filter(\.isRenderable)
        let previousGroupedDrafts = draftChords.filter(\.requiresSeparatedChordInk)
        let previousFrozenDraftByIdentity = Dictionary(
            draftChords.compactMap { draft -> (ChordInkRecognitionFrozenTargetIdentity, ChordInkDraft)? in
                guard let lifecycle = draft.targetLifecycle,
                      lifecycle.stage == .frozen else {
                    return nil
                }
                return (lifecycle.frozenTargetIdentity, draft)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let previousDraftsByAnchor = Dictionary(grouping: draftChords, by: \.anchor)
        let inputsByAnchor = Dictionary(grouping: deduplicatedInputs, by: \.anchor)
        var usedDraftIDs = Set<UUID>()
        var resolvedDrafts = [ChordInkDraft]()

        func append(_ draft: ChordInkDraft) {
            usedDraftIDs.insert(draft.id)
            resolvedDrafts.append(draft)
        }

        for input in deduplicatedInputs {
            let priorAtAnchor = (previousDraftsByAnchor[input.anchor] ?? []).filter {
                !usedDraftIDs.contains($0.id)
            }
            // A placement bucket can contain more than one chord. Only an
            // exact drawing may reuse a row ID when its anchor is shared.
            let previousDraft = priorAtAnchor.first { $0.drawingData == input.drawingData }
                ?? (inputsByAnchor[input.anchor]?.count == 1 ? priorAtAnchor.first : nil)
            let selectedText = previousDraft?.drawingData == input.drawingData ? previousDraft?.selectedText : nil

            if !input.requiresManualReviewOnly,
               let incomingLifecycle = input.targetLifecycle,
               let frozenDraft = previousFrozenDraftByIdentity[incomingLifecycle.frozenTargetIdentity] {
                // A later page-wide pass may assign the same target a slightly
                // different interpretation after unrelated ink is added
                // elsewhere. Exact target anchor plus prepared-stroke
                // ownership is the authority once frozen, so keep both the
                // ownership and interpretation until that target changes.
                if !usedDraftIDs.contains(frozenDraft.id) {
                    append(frozenDraft)
                }
                continue
            }

            var incomingDraft = ChordInkDraft(
                id: previousDraft?.id ?? UUID(),
                input: input,
                selectedText: selectedText,
                isStale: false
            )
            if let stableLifecycle = incomingDraft.targetLifecycle,
               stableLifecycle.stage == .stable {
                incomingDraft.targetLifecycle = stableLifecycle.advanced(to: .frozen)
            }

            if Self.requiresSeparatedInk(
                for: incomingDraft,
                comparedTo: previousGroupedDrafts + previousRenderableDrafts.filter {
                    !usedDraftIDs.contains($0.id)
                        && ($0.anchor == input.anchor || inputsByAnchor[$0.anchor] == nil)
                }
            ) {
                // The combined read has no reliable placement for the detached
                // strokes. Keep it intact and ask the writer to separate it.
                incomingDraft.requiresSeparatedChordInk = true
                incomingDraft.candidateTexts = []
                incomingDraft.bestCandidateText = nil
                incomingDraft.selectedText = nil
                incomingDraft.targetLifecycle = nil
                incomingDraft.isStale = true
            }
            // The current target owns all its ink. The former preview would
            // claim some of those strokes twice.
            append(incomingDraft)
        }

        draftChords = resolvedDrafts
            .sorted(by: Self.isOrderedBefore)
        layoutPageSize = deduplicatedInputs.compactMap(\.layoutPageSize).first ?? layoutPageSize
        self.updatedAt = updatedAt
    }

    mutating func markRenderableDraftsCommitted(updatedAt: Date = .now) {
        for index in draftChords.indices where draftChords[index].isRenderable {
            guard let frozenLifecycle = draftChords[index].targetLifecycle,
                  frozenLifecycle.stage == .frozen else {
                continue
            }
            draftChords[index].targetLifecycle = frozenLifecycle.advanced(to: .committed)
        }
        self.updatedAt = updatedAt
    }

    private static func requiresSeparatedInk(
        for incomingDraft: ChordInkDraft,
        comparedTo previousDrafts: [ChordInkDraft]
    ) -> Bool {
        let incomingPreviewText = incomingDraft.previewText
        guard !previousDrafts.isEmpty, let expanded = try? PKDrawing(data: incomingDraft.drawingData) else {
            return false
        }

        let minimumGap = incomingPreviewText == nil
            ? minimumUnresolvedAddedStrokeGap : minimumDetachedAddedStrokeGap
        return previousDrafts.contains { previousDraft in
            if previousDraft.drawingData == incomingDraft.drawingData {
                return previousDraft.requiresSeparatedChordInk
            }
            guard previousDraft.strokeCount <= incomingDraft.strokeCount,
                  let prior = try? PKDrawing(data: previousDraft.drawingData) else { return false }
            if previousDraft.requiresSeparatedChordInk {
                // A repeated read of the same group cannot clear the request
                // to separate it. A new, independently targeted subset can.
                return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: prior, current: expanded)
                    || ChordInkDraftSourceCoveragePolicy.addedVisibleStrokes(in: expanded, after: prior) != nil
            }
            guard sharesDraftContinuityScope(previousDraft, incomingDraft),
                  let previousPreviewText = previousDraft.previewText,
                  previousPreviewText != incomingPreviewText,
                  !ChordInkSameChordContinuationPolicy.allowsContinuation(
                    from: previousPreviewText, to: incomingPreviewText
                  ),
                  let added = ChordInkDraftSourceCoveragePolicy.addedVisibleStrokes(in: expanded, after: prior),
                  let addedMinX = added.lazy.map(\.renderBounds.minX).min() else { return false }
            return addedMinX - prior.bounds.maxX >= minimumGap
        }
    }

    private static func sharesDraftContinuityScope(
        _ lhs: ChordInkDraft,
        _ rhs: ChordInkDraft
    ) -> Bool {
        guard lhs.measureID == rhs.measureID else {
            return false
        }

        let lhsLane = laneSystemIndex(lhs)
        let rhsLane = laneSystemIndex(rhs)
        if lhsLane != rhsLane {
            return false
        }

        return visualOrder(rhs) + 0.08 >= visualOrder(lhs)
    }

    private static func laneSystemIndex(_ draft: ChordInkDraft) -> Int? {
        if let laneLocation = draft.laneLocation {
            return laneLocation.systemIndex
        }

        guard let visualOrder = draft.visualOrder else {
            return nil
        }

        return Int(floor(visualOrder))
    }

    private static func isOrderedBefore(_ lhs: ChordInkDraft, _ rhs: ChordInkDraft) -> Bool {
        let lhsVisualOrder = visualOrder(lhs)
        let rhsVisualOrder = visualOrder(rhs)
        if lhsVisualOrder != rhsVisualOrder {
            return lhsVisualOrder < rhsVisualOrder
        }

        if lhs.measureIndex == rhs.measureIndex {
            return (lhs.targetFraction ?? 0) < (rhs.targetFraction ?? 0)
        }

        return lhs.measureIndex < rhs.measureIndex
    }

    private static func visualOrder(_ draft: ChordInkDraft) -> Double {
        draft.laneLocation?.visualOrder
            ?? draft.visualOrder
            ?? Double(draft.measureIndex) + (draft.targetFraction ?? 0)
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

    mutating func replaceDraftEndings(with endings: [DraftEnding], updatedAt: Date = .now) {
        let previous = Dictionary(draftEndings.map { ($0.identitySignature, $0) },
            uniquingKeysWith: { first, _ in first })
        draftEndings = endings.sorted { $0.visualOrder < $1.visualOrder }.map { ending in
            var resolved = ending
            if let old = previous[ending.identitySignature] {
                resolved.id = old.id
                resolved.label = old.label
                resolved.endStyle = old.endStyle
                resolved.isReviewed = old.isReviewed
                resolved.reviewedSourceInkData = old.reviewedSourceInkData
                resolved.reviewedMeasureRange = old.reviewedMeasureRange
                resolved.reviewedRangeContext = old.reviewedRangeContext
            }
            return resolved
        }
        layoutPageSize = endings.compactMap(\.layoutPageSize).first ?? layoutPageSize
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
        draftEndings = []
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
                    paperFrame: pageLayout.paperFrame(for: system),
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

    static func sourceInkFrame(for barline: DraftBarline, sourceOrigin: CGPoint) -> CGRect? {
        let points = barline.sourceStrokeGeometry.flatMap(\.points)
        guard !points.isEmpty, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              sourceOrigin.x.isFinite, sourceOrigin.y.isFinite else { return nil }
        let xs = points.map { CGFloat($0.x) + sourceOrigin.x }
        let ys = points.map { CGFloat($0.y) + sourceOrigin.y }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX - 4, y: minY - 4, width: maxX - minX + 8, height: maxY - minY + 8)
    }

    static func selectionFrame(for barline: DraftBarline, in laneFrame: CGRect, sourceOrigin: CGPoint? = nil) -> CGRect {
        return lineFrame(for: barline, in: laneFrame).insetBy(dx: 3, dy: 8)
    }

    static func hitTarget(
        at location: CGPoint,
        barlines: [DraftBarline],
        laneFrameForBarline: (DraftBarline) -> CGRect?,
        selectedBarlineID: UUID?,
        sourceOrigin: CGPoint? = nil
    ) -> ChordDraftBarlineHitTarget? {
        if let selectedBarlineID,
           let selected = barlines.last(where: { $0.id == selectedBarlineID }),
           let laneFrame = laneFrameForBarline(selected) {
            let controls = controlFrames(for: selected, in: laneFrame)
            if controls.delete.insetBy(dx: -deleteHitOutset, dy: -deleteHitOutset).contains(location) {
                return ChordDraftBarlineHitTarget(barlineID: selected.id, action: .delete)
            }
        }

        for barline in barlines.reversed() {
            guard let laneFrame = laneFrameForBarline(barline) else {
                continue
            }

            if selectionFrame(for: barline, in: laneFrame, sourceOrigin: sourceOrigin).contains(location) {
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
    static func candidate(
        for stroke: InkStroke,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout
    ) -> DraftBarline? {
        draftBarline(for: stroke, chordFrame: chordFrame, pageLayout: pageLayout)
    }

    private enum AcceptanceThresholds {
        static let minimumHeight: CGFloat = 22
        static let maximumHeightToLaneRatio: CGFloat = 1.35
        static let maximumAngleDegreesFromVertical = 18.0
        static let minimumStraightness = 0.74
        static let maximumWidthRatio = 0.24
        static let maximumAbsoluteWidth: CGFloat = 12
        static let minimumLaneCoverage = 0.62
        static let gapMaximumAngleDegreesFromVertical = 24.0
        static let gapMaximumWidthRatio = 0.45
        static let gapMinimumStraightness = 0.90
        static let gapMinimumLaneCoverage = 0.78
    }

    static func recognize(
        strokes: [InkStroke],
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> ChordDraftBarlineRecognition {
        guard let pageLayout else {
            return ChordDraftBarlineRecognition(barlines: [], strokeIndices: [])
        }

        var candidateBarlines = [(barline: DraftBarline, strokeIndex: Int)]()
        for indexedStroke in strokes.enumerated() {
            guard let barline = draftBarline(
                for: indexedStroke.element,
                chordFrame: chordFrame,
                pageLayout: pageLayout,
                allowsSlantInRenderedChordGap: true
            ) else {
                continue
            }

            candidateBarlines.append((barline, indexedStroke.offset))
        }

        let candidateIndices = Set(candidateBarlines.map(\.strokeIndex))
        let acceptedBarlines = candidateBarlines.filter { candidate in
            !isOwnedByNeighboringInk(
                candidate,
                strokes: strokes,
                candidateIndices: candidateIndices,
                chordFrame: chordFrame,
                pageLayout: pageLayout
            )
        }
        let deDuplicatedBarlines = removeVeryCloseBarlines(acceptedBarlines)

        let barlines = deDuplicatedBarlines.map { pair in
            var barline = pair.barline
            barline.sourceStrokeIndex = pair.strokeIndex
            let nextIndex = pair.strokeIndex + 1
            if strokes.indices.contains(nextIndex),
               isImmediateEndpointTap(strokes[nextIndex], after: strokes[pair.strokeIndex]) {
                barline.sourceStrokeIndices = [pair.strokeIndex, nextIndex]
                barline.sourceStrokeGeometry = [strokes[pair.strokeIndex], strokes[nextIndex]]
            }
            return barline
        }
        return ChordDraftBarlineRecognition(
            barlines: barlines,
            strokeIndices: barlines.reduce(into: Set<Int>()) { $0.formUnion($1.ownedSourceStrokeIndices) }
        )
    }

    /// A brief Pencil contact at the end of a line belongs to that line.
    /// A nearby dot, a later mark, or a stroke without timing stays separate.
    private static func isImmediateEndpointTap(_ tap: InkStroke, after line: InkStroke) -> Bool {
        guard tap.points.count == 1, let point = tap.points.first, let endpoint = line.points.last,
              let end = line.timelineEndTimeOffset, let start = tap.timelineStartTimeOffset,
              (0...0.10).contains(start - end) else { return false }
        return hypot(point.x - endpoint.x, point.y - endpoint.y) <= 1.5
    }

    /// These relative ratios are conservative ambiguity gates, not calibrated
    /// recognition confidence. A mark touching a local construction, or packed
    /// between comparable ink on both sides, must remain available to chord
    /// recognition. An isolated mark still uses the existing acceptance rules.
    private static func isOwnedByNeighboringInk(
        _ candidate: (barline: DraftBarline, strokeIndex: Int),
        strokes: [InkStroke],
        candidateIndices: Set<Int>,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout
    ) -> Bool {
        let stroke = strokes[candidate.strokeIndex]
        let bounds = stroke.bounds
        let height = bounds.height
        let centerX = (bounds.minX + bounds.maxX) / 2
        guard height > 0,
              let systemIndex = candidate.barline.laneLocation?.systemIndex,
              let first = stroke.points.first, let last = stroke.points.last else {
            return false
        }

        var leftNeighbors = [InkBounds](), rightNeighbors = [InkBounds]()
        for (index, neighbor) in strokes.enumerated() {
            // Another possible barline is not evidence of text ownership.
            guard index != candidate.strokeIndex, !candidateIndices.contains(index) else { continue }
            let other = neighbor.bounds
            let otherCenterX = (other.minX + other.maxX) / 2
            guard other.width >= height * 0.18, other.width <= height * 1.50,
                  other.height <= height * 1.60,
                  draftBarlineTarget(
                    at: CGPoint(x: otherCenterX, y: (other.minY + other.maxY) / 2)
                        .offsetBy(dx: chordFrame.minX, dy: chordFrame.minY),
                    in: pageLayout
                  )?.system.index == systemIndex else {
                continue
            }

            let localBounds = bounds.union(other)
            if other.width >= height * 0.20,
               localBounds.width <= height * 1.80, localBounds.height <= height * 1.80,
               zip(neighbor.points, neighbor.points.dropFirst()).contains(where: {
                   segmentsAreClose(first, last, $0.0, $0.1, tolerance: height * 0.08)
               }) {
                return true
            }

            let referenceHeight = min(height, other.height)
            let verticalOverlap = min(bounds.maxY, other.maxY) - max(bounds.minY, other.minY)
            guard other.height >= height * 0.55,
                  verticalOverlap >= referenceHeight * 0.50 else { continue }
            if otherCenterX < centerX,
               max(0, bounds.minX - other.maxX) <= referenceHeight * 0.30 {
                leftNeighbors.append(other)
            } else if otherCenterX > centerX,
                      max(0, other.minX - bounds.maxX) <= referenceHeight * 0.30 {
                rightNeighbors.append(other)
            }
        }
        return leftNeighbors.contains { left in
            rightNeighbors.contains { right in
                bounds.union(left).union(right).width <= height * 2.75
            }
        }
    }

    private static func segmentsAreClose(
        _ a: InkPoint, _ b: InkPoint, _ c: InkPoint, _ d: InkPoint,
        tolerance: Double
    ) -> Bool {
        func cross(_ first: InkPoint, _ second: InkPoint, _ point: InkPoint) -> Double {
            (second.x - first.x) * (point.y - first.y) - (second.y - first.y) * (point.x - first.x)
        }
        let abC = cross(a, b, c), abD = cross(a, b, d)
        let cdA = cross(c, d, a), cdB = cross(c, d, b)
        if max(min(a.x, b.x), min(c.x, d.x)) <= min(max(a.x, b.x), max(c.x, d.x)),
           max(min(a.y, b.y), min(c.y, d.y)) <= min(max(a.y, b.y), max(c.y, d.y)),
           ((abC >= 0 && abD <= 0) || (abC <= 0 && abD >= 0)),
           ((cdA >= 0 && cdB <= 0) || (cdA <= 0 && cdB >= 0)) {
            return true
        }
        let distanceSquared = min(
            min(pointToSegmentDistanceSquared(a, c, d), pointToSegmentDistanceSquared(b, c, d)),
            min(pointToSegmentDistanceSquared(c, a, b), pointToSegmentDistanceSquared(d, a, b))
        )
        return distanceSquared <= tolerance * tolerance
    }

    private static func pointToSegmentDistanceSquared(_ point: InkPoint, _ a: InkPoint, _ b: InkPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let fraction = lengthSquared > 0
            ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
            : 0
        let distanceX = point.x - (a.x + fraction * dx), distanceY = point.y - (a.y + fraction * dy)
        return distanceX * distanceX + distanceY * distanceY
    }

    private static func draftBarline(
        for stroke: InkStroke,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout,
        allowsSlantInRenderedChordGap: Bool = false
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
        let minimumLaneCoverage = AcceptanceThresholds.minimumLaneCoverage
        let maximumHeightToLaneRatio = Double(AcceptanceThresholds.maximumHeightToLaneRatio)
        let hasStandardBarlineShape = angleDegrees <= AcceptanceThresholds.maximumAngleDegreesFromVertical
            && straightness >= AcceptanceThresholds.minimumStraightness
            && (widthRatio <= AcceptanceThresholds.maximumWidthRatio
                || bounds.width <= AcceptanceThresholds.maximumAbsoluteWidth)
        let hasSlantedBarlineShape = allowsSlantInRenderedChordGap
            && angleDegrees <= AcceptanceThresholds.gapMaximumAngleDegreesFromVertical
            && straightness >= AcceptanceThresholds.gapMinimumStraightness
            && widthRatio <= AcceptanceThresholds.gapMaximumWidthRatio
        guard hasStandardBarlineShape || hasSlantedBarlineShape else { return nil }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard let target = draftBarlineTargets(
            at: center,
            in: pageLayout
        ).first(where: { candidate in
            let coverage = Double(bounds.intersection(candidate.laneFrame).height / max(1, candidate.laneFrame.height))
            let heightRatio = bounds.height / max(1, candidate.laneFrame.height)
            return coverage >= minimumLaneCoverage
                && Double(heightRatio) <= maximumHeightToLaneRatio
                && (hasStandardBarlineShape || (
                    coverage >= AcceptanceThresholds.gapMinimumLaneCoverage
                        && candidate.system.layoutStyle != .leadSheet
                        && hasRenderedChordGap(for: bounds, in: candidate.measure)))
        }) else {
            return nil
        }

        let laneFrame = target.laneFrame
        let laneCoverage = Double(bounds.intersection(laneFrame).height / max(1, laneFrame.height))
        let heightToLaneRatio = bounds.height / max(1, laneFrame.height)
        guard laneCoverage >= minimumLaneCoverage,
              Double(heightToLaneRatio) <= maximumHeightToLaneRatio else {
            return nil
        }
        // A mostly vertical mark can span the lane and still be wide enough
        // to reach chord recognition. Accept that shape only as a plain
        // separator between engraved chords in one measure. Neighboring live
        // ink can still claim the stroke before it becomes a barline.
        guard hasStandardBarlineShape || (
            laneCoverage >= AcceptanceThresholds.gapMinimumLaneCoverage
                && target.system.layoutStyle != .leadSheet
                && hasRenderedChordGap(for: bounds, in: target.measure)
        ) else {
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
            measureIndex: target.measure.index,
            fraction: Double(rawFraction),
            laneLocation: ChordInkDraftLaneLocation(
                systemIndex: target.system.index,
                fraction: Double(rawFraction)
            ),
            layoutPageSize: pageLayout.pageBounds.size,
            metrics: metrics
        )
    }

    private static func hasRenderedChordGap(for bounds: CGRect, in measure: LeadSheetMeasureLayout) -> Bool {
        guard bounds.minX > measure.frame.minX, bounds.maxX < measure.frame.maxX else { return false }
        var hasChordOnLeft = false
        var hasChordOnRight = false
        for chord in measure.chordLayouts {
            let glyphBounds = chord.frame.union(chord.naturalFrame)
            if glyphBounds.maxX <= bounds.minX {
                hasChordOnLeft = true
            } else if glyphBounds.minX >= bounds.maxX {
                hasChordOnRight = true
            } else {
                return false
            }
        }
        return hasChordOnLeft && hasChordOnRight
    }

    private static func draftBarlineTarget(
        at center: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> (measureID: UUID, measure: LeadSheetMeasureLayout, system: LeadSheetSystemLayout, laneFrame: CGRect)? {
        draftBarlineTargets(at: center, in: pageLayout).first
    }

    private static func draftBarlineTargets(
        at center: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> [(measureID: UUID, measure: LeadSheetMeasureLayout, system: LeadSheetSystemLayout, laneFrame: CGRect)] {
        var targets = [(measureID: UUID, measure: LeadSheetMeasureLayout, system: LeadSheetSystemLayout, laneFrame: CGRect)]()
        for system in pageLayout.systems {
            let paper = pageLayout.paperFrame(for: system)
            var laneFrames = [CGRect]()
            for lane in [
                LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system, paperFrame: paper),
                LeadSheetActiveInkScope.legacyChordWritingSystemLaneFrame(for: system, paperFrame: paper)
            ].compactMap({ $0 }) where !laneFrames.contains(lane) {
                // The old reserved ending band can be lower and shorter than
                // the stable lane. Test each real frame independently rather
                // than relaxing coverage against their union.
                laneFrames.append(lane)
            }
            let matchingFrames = laneFrames.filter { $0.insetBy(dx: -8, dy: -8).contains(center) }
            guard !matchingFrames.isEmpty else { continue }

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
                continue
            }

            targets.append(contentsOf: matchingFrames.map { (measureID, measure, system, $0) })
        }

        return targets
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
    var didRejectIncompleteSourceCoverage = false
    var renderedEndingIDs: [UUID] = []

    var renderedChordCount: Int {
        renderedChordIDs.count
    }

    var renderedBarlineCount: Int {
        renderedBarlineIDs.count
    }

    var renderedEndingCount: Int { renderedEndingIDs.count }

    func hasUnplacedPlainBarline(in state: ChordPreviewState) -> Bool {
        state.draftBarlines.contains { unresolvedDraftIDs.contains($0.id) }
    }
}

extension Chart {
    private struct ChordDraftBarlineCommitPlan {
        var renderedBarlineIDs: [UUID]
        var segmentMeasureIDsByOriginalMeasureID: [UUID: [UUID]]
        var boundaryFractionsByOriginalMeasureID: [UUID: [Double]]
        var sourceBoundaryFractionsByOriginalMeasureID: [UUID: [Double]] = [:]
        var unresolvedDraftIDs: [UUID]

        var splitMeasureIDs: Set<UUID> {
            Set(segmentMeasureIDsByOriginalMeasureID.values.filter { $0.count > 1 }.flatMap { $0 })
        }
    }

    private struct ChordDraftEndingMapping {
        var chart: Chart
        var sourceLayout: LeadSheetPageLayout
        var materializedLayout: LeadSheetPageLayout
        var plan: ChordDraftBarlineCommitPlan
    }

    private struct ChordDraftEndingStaging {
        var mapping: ChordDraftEndingMapping? = nil
        var unresolvedBarlineIDs: [UUID] = []
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
        barlineSpacingMode: ChordDraftBarlineSpacingMode = .drawn,
        automaticContinuationSourceLayout: LeadSheetPageLayout? = nil
    ) -> ChordInkDraftBatchRenderResult {
        // Stage every measure/barline/chord mutation together. A changed source
        // or one invalid target cannot leave a partially rendered chart behind.
        var staged = self
        let result = staged.applyChordInkDraftBatch(state, barlineSpacingMode: barlineSpacingMode,
            automaticContinuationSourceLayout: automaticContinuationSourceLayout)
        guard !result.didRejectIncompleteSourceCoverage,
              result.unresolvedDraftIDs.isEmpty,
              state.unresolvedChordCount == 0,
              state.unresolvedBarlineCount == 0,
              state.unresolvedEndingCount == 0 else {
            let unresolved = Set(result.unresolvedDraftIDs)
                .union(state.draftChords.filter { !$0.isRenderable }.map(\.id))
                .union(state.draftBarlines.filter { !$0.isRenderable }.map(\.id))
                .union(state.draftEndings.filter { !$0.isRenderable }.map(\.id))
            let orderedDraftIDs = state.draftChords.map(\.id) + state.draftBarlines.map(\.id) + state.draftEndings.map(\.id)
            return ChordInkDraftBatchRenderResult(
                renderedChordIDs: [], renderedBarlineIDs: [],
                unresolvedDraftIDs: orderedDraftIDs.filter { unresolved.contains($0) },
                didRejectIncompleteSourceCoverage: result.didRejectIncompleteSourceCoverage
            )
        }
        self = staged
        return result
    }

    private mutating func applyChordInkDraftBatch(
        _ state: ChordPreviewState,
        barlineSpacingMode: ChordDraftBarlineSpacingMode,
        automaticContinuationSourceLayout: LeadSheetPageLayout?
    ) -> ChordInkDraftBatchRenderResult {
        // A skipped/oversized target is not an empty patch of canvas. Nothing
        // may be materialized or globally cleared until every current visible
        // source fragment is represented by the reviewed drafts or barlines.
        guard ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: self, state: state) else {
            return ChordInkDraftBatchRenderResult(
                renderedChordIDs: [], renderedBarlineIDs: [], unresolvedDraftIDs: [],
                didRejectIncompleteSourceCoverage: true
            )
        }
        let invalidReviewedRanges = state.draftEndings.filter { ending in
            guard ending.reviewedMeasureRange != nil || ending.reviewedRangeContext != nil else { return false }
            guard let range = ending.reviewedMeasureRange, range.lowerBound > 0,
                  let context = ending.reviewedRangeContext else { return true }
            return !context.matches(chart: self, state: state)
        }
        guard invalidReviewedRanges.isEmpty else {
            return ChordInkDraftBatchRenderResult(renderedChordIDs: [], renderedBarlineIDs: [],
                unresolvedDraftIDs: invalidReviewedRanges.map(\.id))
        }
        let explicitRanges = state.draftEndings.filter { $0.reviewedMeasureRange != nil }
        if !explicitRanges.isEmpty {
            guard let count = draftEndingReviewMeasureCount(state: state),
                  explicitRanges.allSatisfy({ ($0.reviewedMeasureRange?.upperBound ?? Int.max) <= count }) else {
                return ChordInkDraftBatchRenderResult(renderedChordIDs: [], renderedBarlineIDs: [],
                    unresolvedDraftIDs: explicitRanges.map(\.id))
            }
        }
        let renderableBarlines = state.renderableBarlines
        let existingChordIDs = Set(measures.flatMap(\.chordEvents).map(\.id))
        let previouslyOpenIDs = Set(measures.filter { $0.authoringState == .open }.map(\.id))
        let sourceLayout = state.layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: self,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        if barlineSpacingMode == .drawn, state.draftChords.isEmpty, state.draftEndings.isEmpty,
           let sourceLayout,
           let tailResult = commitRhythmTailBarlines(renderableBarlines, sourceLayout: sourceLayout) {
            return tailResult
        }
        guard materializeSimpleChordDraftRowsIfNeeded(
            for: state.renderableDraftChords,
            barlines: renderableBarlines,
            endings: state.draftEndings,
            automaticContinuationSourceLayout: automaticContinuationSourceLayout
        ) else {
            return ChordInkDraftBatchRenderResult(renderedChordIDs: [], renderedBarlineIDs: [],
                unresolvedDraftIDs: state.draftChords.map(\.id) + state.draftBarlines.map(\.id) + state.draftEndings.map(\.id))
        }
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
            commitPageLayout: commitLayout,
            requiresCompleteSplits: true
        )
        guard barlinePlan.unresolvedDraftIDs.isEmpty else {
            return ChordInkDraftBatchRenderResult(
                renderedChordIDs: [], renderedBarlineIDs: [],
                unresolvedDraftIDs: barlinePlan.unresolvedDraftIDs
            )
        }
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
                    sourceCandidateSignature: draft.sourceCandidateSignature,
                    sourceRecognitionPipelineVersion: draft.recognitionResult?.fallbackPipelineVersion(for: previewText)
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

        let endingResult = commitDraftEndings(
            state.draftEndings, sourcePageLayout: sourceLayout, commitPageLayout: commitLayout,
            barlinePlan: barlinePlan
        )
        unresolvedDraftIDs.append(contentsOf: endingResult.unresolved)

        if unresolvedDraftIDs.isEmpty {
            let closedIDs = Set(measures.filter {
                previouslyOpenIDs.contains($0.id) && $0.authoringState == .committed
            }.map(\.id))
            anchorLoneChordsToMeasureStart(in: barlinePlan.splitMeasureIDs.union(closedIDs),
                eligibleChordIDs: existingChordIDs)
        }

        if unresolvedDraftIDs.isEmpty,
           !renderedChordIDs.isEmpty || !barlinePlan.renderedBarlineIDs.isEmpty || !endingResult.rendered.isEmpty {
            _ = setPageHandwrittenChordDrawing(nil)
        }

        return ChordInkDraftBatchRenderResult(
            renderedChordIDs: renderedChordIDs,
            renderedBarlineIDs: barlinePlan.renderedBarlineIDs,
            unresolvedDraftIDs: unresolvedDraftIDs,
            renderedEndingIDs: endingResult.rendered
        )
    }

    private mutating func commitDraftEndings(
        _ endings: [DraftEnding], sourcePageLayout: LeadSheetPageLayout?,
        commitPageLayout: LeadSheetPageLayout?, barlinePlan: ChordDraftBarlineCommitPlan
    ) -> (rendered: [UUID], unresolved: [UUID]) {
        guard !endings.isEmpty else { return ([], []) }
        guard let sourcePageLayout, let commitPageLayout,
              let sourceData = pageHandwrittenChordData,
              let source = try? PKDrawing(data: sourceData) else { return ([], endings.map(\.id)) }
        let finalIDs = measures.map(\.id)
        let positions = Dictionary(uniqueKeysWithValues: finalIDs.enumerated().map { ($0.element, $0.offset) })


        var rendered: [UUID] = [], unresolved: [UUID] = []
        for ending in endings {
            let startID: UUID?
            let endID: UUID?
            if let range = ending.reviewedMeasureRange {
                let validRange = ending.reviewedRangeContext != nil && range.lowerBound > 0
                    && range.upperBound <= finalIDs.count
                startID = validRange ? finalIDs[range.lowerBound - 1] : nil
                endID = validRange ? finalIDs[range.upperBound - 1] : nil
            } else if ending.reviewedRangeContext != nil {
                startID = nil
                endID = nil
            } else {
                startID = draftEndingEndpointMeasureID(ending.start, isStart: true,
                    sourcePageLayout: sourcePageLayout, commitPageLayout: commitPageLayout, barlinePlan: barlinePlan)
                endID = draftEndingEndpointMeasureID(ending.end, isStart: false,
                    sourcePageLayout: sourcePageLayout, commitPageLayout: commitPageLayout, barlinePlan: barlinePlan)
            }
            guard ending.isRenderable,
                  let startID, let endID,
                  let startIndex = positions[startID], let endIndex = positions[endID], startIndex <= endIndex,
                  !ending.sourceStrokeIndices.isEmpty,
                  ending.sourceStrokeIndices.allSatisfy({ source.strokes.indices.contains($0) }),
                  !roadmapObjects.contains(where: {
                      $0.type.isEnding && $0.startMeasureID == startID && $0.endMeasureID == endID
                          && $0.resolvedEndingDisplayText == ending.normalizedLabel
                          && $0.resolvedEndingEndStyle == ending.endStyle
                  }),
                  let endingID = addEndingSpan(.ending1, startMeasureID: startID, endMeasureID: endID,
                    displayText: ending.normalizedLabel, endStyle: ending.endStyle),
                  let objectIndex = roadmapObjects.firstIndex(where: { $0.id == endingID }) else {
                unresolved.append(ending.id)
                continue
            }
            roadmapObjects[objectIndex].sourceInkData = PKDrawing(strokes:
                ending.sourceStrokeIndices.sorted().map { source.strokes[$0] }).dataRepresentation()
            rendered.append(ending.id)
        }
        return (rendered, unresolved)
    }

    private func draftEndingEndpointMeasureID(
        _ endpoint: DraftEndingEndpoint, isStart: Bool,
        sourcePageLayout: LeadSheetPageLayout, commitPageLayout: LeadSheetPageLayout,
        barlinePlan: ChordDraftBarlineCommitPlan
    ) -> UUID? {
        guard endpoint.fraction.isFinite, endpoint.laneLocation.fraction.isFinite,
              let sourceSystem = sourcePageLayout.systems.first(where: {
                  $0.index == endpoint.laneLocation.systemIndex
              }),
              let materializedSystem = commitPageLayout.systems.first(where: {
                  $0.index == endpoint.laneLocation.systemIndex
              }),
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: sourceSystem,
                  paperFrame: sourcePageLayout.paperFrame(for: sourceSystem)) else { return nil }
        let finalIDs = measures.map(\.id)
        let positions = Dictionary(uniqueKeysWithValues: finalIDs.enumerated().map { ($0.element, $0.offset) })
        var candidates: [ChordInkEndingCommitPolicy.PageBoundary] = []
        let terminalRepeatOwnsRowEdge = LeadSheetSimpleChordTerminalBarlineGeometry.usesTerminalBarlineAsTrailingRepeatBoundary(
            for: sourceSystem, paperFrame: sourcePageLayout.paperFrame(for: sourceSystem), layoutStyle: layoutStyle)

        for (sourceIndex, measure) in sourceSystem.measures.enumerated() {
            let materializedID: UUID?
            if let sourceID = measure.sourceMeasureID {
                materializedID = sourceID
            } else if materializedSystem.measures.indices.contains(sourceIndex) {
                let materialized = materializedSystem.measures[sourceIndex]
                materializedID = materialized.sourceMeasureID ?? materialized.chordInkTargetMeasureID
            } else {
                materializedID = nil
            }
            guard let materializedID else { continue }
            let segments = barlinePlan.segmentMeasureIDsByOriginalMeasureID[materializedID] ?? [materializedID]
            let fractions = barlinePlan.sourceBoundaryFractionsByOriginalMeasureID[materializedID] ?? []
            guard !segments.isEmpty, segments.count == fractions.count + 1,
                  let firstPosition = segments.first.flatMap({ positions[$0] }),
                  let lastPosition = segments.last.flatMap({ positions[$0] }) else { continue }
            let display = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(measure,
                in: sourceSystem, paperFrame: sourcePageLayout.paperFrame(for: sourceSystem), layoutStyle: layoutStyle)
            let frame = chordDraftBarlineSegmentFrame(for: display)
            func boundary(at index: Int, ranges: [ClosedRange<CGFloat>]) -> ChordInkEndingCommitPolicy.PageBoundary {
                let left: UUID? = index > 0 ? segments[index - 1]
                    : (firstPosition > 0 ? finalIDs[firstPosition - 1] : nil)
                let right: UUID? = index < segments.count ? segments[index]
                    : (lastPosition + 1 < finalIDs.count ? finalIDs[lastPosition + 1] : nil)
                return .init(leftMeasureID: left, rightMeasureID: right, sourceRanges: ranges)
            }
            candidates.append(boundary(at: 0, ranges: [frame.minX...frame.minX]))
            for (index, fraction) in fractions.enumerated() {
                let x = frame.minX + frame.width * CGFloat(fraction)
                candidates.append(boundary(at: index + 1, ranges: [x...x]))
            }
            // A closing repeat may be painted at the row edge across an empty
            // open continuation. That visible glyph still belongs to the
            // preceding measure, not the continuation's extended writing box.
            let isUnpaintedContinuationEdge = terminalRepeatOwnsRowEdge
                && sourceSystem.measures.last?.id == measure.id && measure.isOpen
                && measure.repeatMarkerLayouts.isEmpty
            if !isUnpaintedContinuationEdge {
                candidates.append(boundary(at: segments.count, ranges: [frame.maxX...frame.maxX]))
            }

            for marker in measure.repeatMarkerLayouts {
                let metrics = LeadSheetRepeatReadabilityMetrics(chart: self, staffHeight: marker.frame.height)
                let terminalLineX = marker.edge == .trailing
                    ? LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(after: measure,
                        in: sourceSystem, paperFrame: sourcePageLayout.paperFrame(for: sourceSystem), layoutStyle: layoutStyle)
                    : nil
                let trailingLineX = terminalLineX ?? marker.frame.midX + metrics.separation / 2
                let leadingLineX = terminalLineX.map { $0 - metrics.separation }
                    ?? marker.frame.midX - metrics.separation / 2
                var lower = leadingLineX - metrics.lineWidth / 2
                var upper = trailingLineX + metrics.lineWidth / 2
                if marker.edge == .trailing {
                    lower = min(lower, leadingLineX - metrics.dotOffset - metrics.dotRadius)
                    if repeatWings {
                        lower = min(lower, trailingLineX - metrics.wingLength - metrics.wingLineWidth / 2)
                    }
                } else {
                    upper = max(upper, trailingLineX + metrics.dotOffset + metrics.dotRadius)
                    if repeatWings {
                        upper = max(upper, leadingLineX + metrics.wingLength + metrics.wingLineWidth / 2)
                    }
                }
                candidates.append(boundary(at: marker.edge == .leading ? 0 : segments.count,
                    ranges: [lower...upper]))
            }
        }
        let sourceX = laneFrame.minX + laneFrame.width * CGFloat(endpoint.laneLocation.fraction)
        return ChordInkEndingCommitPolicy.measureID(atSourceX: sourceX, boundaries: candidates, isStart: isStart)
    }

    /// A temporary split plan gives review the same musical range that commit
    /// will use. Neither chart fields nor source ink change during this query.
    func draftEndingMeasureRange(
        for ending: DraftEnding, state: ChordPreviewState, ignoringReviewedRange: Bool = false
    ) -> ClosedRange<Int>? {
        guard let mapping = stagedDraftEndingMapping(state: state).mapping else { return nil }
        return draftEndingMeasureRange(for: ending, state: state,
            ignoringReviewedRange: ignoringReviewedRange, mapping: mapping)
    }

    private func draftEndingMeasureRange(
        for ending: DraftEnding, state: ChordPreviewState, ignoringReviewedRange: Bool,
        mapping: ChordDraftEndingMapping
    ) -> ClosedRange<Int>? {
        guard state.draftEndings.contains(where: { $0.identitySignature == ending.identitySignature }) else { return nil }
        if !ignoringReviewedRange, ending.reviewedMeasureRange != nil || ending.reviewedRangeContext != nil {
            guard let range = ending.reviewedMeasureRange, range.lowerBound > 0,
                  range.upperBound <= mapping.chart.measures.count,
                  let context = ending.reviewedRangeContext, context.matches(chart: self, state: state) else { return nil }
            return range
        }
        guard let start = mapping.chart.draftEndingEndpointMeasureID(ending.start, isStart: true,
                sourcePageLayout: mapping.sourceLayout, commitPageLayout: mapping.materializedLayout, barlinePlan: mapping.plan),
              let end = mapping.chart.draftEndingEndpointMeasureID(ending.end, isStart: false,
                sourcePageLayout: mapping.sourceLayout, commitPageLayout: mapping.materializedLayout, barlinePlan: mapping.plan),
              let startIndex = mapping.chart.measures.firstIndex(where: { $0.id == start }),
              let endIndex = mapping.chart.measures.firstIndex(where: { $0.id == end }), startIndex <= endIndex else { return nil }
        return (startIndex + 1)...(endIndex + 1)
    }

    func draftEndingReviewMeasureCount(state: ChordPreviewState) -> Int? {
        stagedDraftEndingMapping(state: state).mapping?.chart.measures.count
    }

    func draftEndingReviewPlacement(for ending: DraftEnding, state: ChordPreviewState) -> (
        measureRange: ClosedRange<Int>?, availableMeasureCount: Int, blockingBarlines: [DraftBarline]
    ) {
        let staged = stagedDraftEndingMapping(state: state)
        let unresolvedIDs = Set(staged.unresolvedBarlineIDs)
        let blockers = state.draftBarlines.filter { !$0.isRenderable || unresolvedIDs.contains($0.id) }
        guard blockers.isEmpty, let mapping = staged.mapping else { return (nil, 0, blockers) }
        let range = draftEndingMeasureRange(for: ending, state: state, ignoringReviewedRange: false, mapping: mapping)
            ?? draftEndingMeasureRange(for: ending, state: state, ignoringReviewedRange: true, mapping: mapping)
        return (range, mapping.chart.measures.count, [])
    }

    private func stagedDraftEndingMapping(state: ChordPreviewState) -> ChordDraftEndingStaging {
        guard let pageSize = state.layoutPageSize,
              pageSize.width.isFinite, pageSize.height.isFinite,
              pageSize.width > 0, pageSize.height > 0 else { return .init() }
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(for: self, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        var staged = self
        guard staged.materializeSimpleChordDraftRowsIfNeeded(for: state.draftChords,
            barlines: state.renderableBarlines, endings: state.draftEndings) else { return .init() }
        let materializedLayout = LeadSheetPageLayoutEngine.pageLayout(for: staged, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let plan = staged.commitDraftBarlinesBeforeChordRender(state.renderableBarlines,
            spacingMode: .drawn, sourcePageLayout: sourceLayout,
            commitPageLayout: materializedLayout, requiresCompleteSplits: true)
        guard plan.unresolvedDraftIDs.isEmpty else { return .init(unresolvedBarlineIDs: plan.unresolvedDraftIDs) }
        return .init(mapping: .init(chart: staged, sourceLayout: sourceLayout,
            materializedLayout: materializedLayout, plan: plan))
    }

    @discardableResult
    private mutating func materializeSimpleChordDraftRowsIfNeeded(
        for drafts: [ChordInkDraft],
        barlines: [DraftBarline] = [],
        endings: [DraftEnding] = [],
        automaticContinuationSourceLayout: LeadSheetPageLayout? = nil
    ) -> Bool {
        guard layoutStyle == .simpleChordSheet,
              let targetSystemIndex = (
                drafts.compactMap { $0.laneLocation?.systemIndex }
                    + barlines.compactMap { $0.laneLocation?.systemIndex }
                    + endings.flatMap { [$0.start.laneLocation.systemIndex, $0.end.laneLocation.systemIndex] }
              ).max(),
              targetSystemIndex > 0 else {
            return true
        }

        while systems.count <= targetSystemIndex {
            guard materializeNextSimpleChordDraftRow(
                automaticContinuationSourceLayout: automaticContinuationSourceLayout
            ) else {
                return false
            }
        }
        return true
    }

    private mutating func materializeNextSimpleChordDraftRow(
        automaticContinuationSourceLayout: LeadSheetPageLayout?
    ) -> Bool {
        guard layoutStyle == .simpleChordSheet else {
            return false
        }

        let newOpenMeasureID: UUID
        var closingSource: (measureID: UUID, frame: CGRect, chordBandFrame: CGRect)?
        if let openMeasure = measures.first(where: { $0.authoringState == .open }) {
            if let sourceLayout = automaticContinuationSourceLayout {
                guard let source = automaticContinuationSourceMeasure(for: openMeasure.id,
                    sourceLayout: sourceLayout) else { return false }
                closingSource = (openMeasure.id, source.measure.frame, source.measure.chordBandFrame)
                if openMeasure.manualLayoutWidth == nil {
                    guard preserveAutomaticContinuationWidth(for: openMeasure.id,
                        sourceSystem: source.system, sourceMeasure: source.measure, sourceLayout: sourceLayout) else {
                        return false
                    }
                }
            }
            guard let committedOpenMeasureID = commitOpenMeasure(barlineAfter: .single,
                normalizeSingleChordToMeasureStart: false) else {
                return false
            }
            newOpenMeasureID = committedOpenMeasureID
        } else {
            newOpenMeasureID = appendMeasure(authoringState: .open)
        }

        guard insertSimpleSystemBreak(before: newOpenMeasureID) else { return false }
        if let sourceLayout = automaticContinuationSourceLayout, let closingSource {
            let committedLayout = LeadSheetPageLayoutEngine.pageLayout(for: self,
                pageSize: sourceLayout.pageBounds.size, includesChordInkContinuationLanes: true)
            guard let committedMeasure = committedLayout.systems.flatMap(\.measures).first(where: {
                $0.sourceMeasureID == closingSource.measureID
            }), automaticContinuationFramesMatch(closingSource.frame, committedMeasure.frame),
                automaticContinuationFramesMatch(closingSource.chordBandFrame, committedMeasure.chordBandFrame) else {
                // Custom width intent and overfull row weights remain intact.
                // If they cannot retain the displayed source geometry, reject
                // this staged transaction instead of silently contracting it.
                return false
            }
        }
        return true
    }

    /// Opening a continuation lane closes the previous open measure. Its
    /// default compact width must not replace the width on which the visible
    /// automatic glyph fractions were authored. This runs only inside the
    /// explicitly requested automatic value transaction; custom widths retain
    /// their authority and ordinary manual rendering keeps its existing path.
    private mutating func preserveAutomaticContinuationWidth(
        for measureID: UUID, sourceSystem: LeadSheetSystemLayout,
        sourceMeasure: LeadSheetMeasureLayout, sourceLayout: LeadSheetPageLayout
    ) -> Bool {
        let width = sourceMeasure.frame.width
        guard width.isFinite, width > 0 else { return false }
        let storedWidth = LeadSheetPageLayoutEngine.simpleChordSheetManualLayoutWidthForTargetRowWidth(
            width, chart: self, maxSystemWidth: sourceLayout.paperFrame(for: sourceSystem).width - 68)
        guard storedWidth.isFinite,
              storedWidth >= Measure.minimumManualLayoutWidth,
              storedWidth <= Measure.maximumManualLayoutWidth else { return false }
        return setMeasureManualLayoutWidth(storedWidth, for: measureID) != nil
    }

    private func automaticContinuationSourceMeasure(
        for measureID: UUID, sourceLayout: LeadSheetPageLayout
    ) -> (system: LeadSheetSystemLayout, measure: LeadSheetMeasureLayout)? {
        // A model system can be packed into more than one displayed row.
        // Existing measure identity is the authority before any row-index
        // fallback for an ID which has not been materialized in the source.
        let realMatches = sourceLayout.systems.flatMap { system in
            system.measures.compactMap { measure -> (LeadSheetSystemLayout, LeadSheetMeasureLayout)? in
                measure.sourceMeasureID == measureID ? (system, measure) : nil
            }
        }
        if realMatches.count == 1, let real = realMatches.first { return real }
        guard realMatches.isEmpty else { return nil }
        guard let systemIndex = systems.firstIndex(where: { system in
            system.measures.contains { $0.id == measureID }
        }), let sourceSystem = sourceLayout.systems.first(where: { $0.index == systemIndex }) else { return nil }
        // One batch may materialize several virtual continuation rows. Their
        // future measure IDs do not yet exist in the source layout; use the
        // verified single open ghost lane at the matching index.
        let sourceOpenIDs = Set(sourceLayout.systems.flatMap(\.measures).compactMap {
            $0.isOpen ? $0.sourceMeasureID : nil
        })
        guard sourceSystem.measures.count == 1,
              let ghost = sourceSystem.measures.first, ghost.sourceMeasureID == nil,
              let originalOpenID = ghost.chordInkTargetMeasureID,
              sourceOpenIDs.contains(originalOpenID) else { return nil }
        return (sourceSystem, ghost)
    }

    private func automaticContinuationFramesMatch(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 0.01 && abs(first.minY - second.minY) < 0.01
            && abs(first.width - second.width) < 0.01 && abs(first.height - second.height) < 0.01
    }

    /// Extend a short committed Rhythm row without splitting any of its existing measures.
    /// The writable lane can extend beyond its final engraved barline.
    private mutating func commitRhythmTailBarlines(
        _ barlines: [DraftBarline], sourceLayout: LeadSheetPageLayout
    ) -> ChordInkDraftBatchRenderResult? {
        guard layoutStyle == .rhythmSectionSheet,
              let rowIndex = barlines.first?.laneLocation?.systemIndex,
              let row = sourceLayout.systems.first(where: { $0.index == rowIndex }),
              let last = row.measures.last, let lastID = last.sourceMeasureID,
              measure(id: lastID)?.authoringState == .committed, last.barlineAfter == .single,
              let lane = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                  for: row, paperFrame: sourceLayout.paperFrame(for: row)
              ) else { return nil }

        let ordered = barlines.sorted { $0.laneFraction < $1.laneFraction }
        let positions = ordered.map { lane.minX + lane.width * CGFloat($0.laneFraction) }
        let existingDivider = last.trailingBarlineFrame.midX
        guard zip(ordered, positions).allSatisfy({ barline, x in
            barline.kind == .single && barline.laneLocation?.systemIndex == rowIndex
                && x > existingDivider && x < lane.maxX
        }) else { return nil }

        let ids = ordered.map(\.id)
        let rejected = ChordInkDraftBatchRenderResult(
            renderedChordIDs: [], renderedBarlineIDs: [], unresolvedDraftIDs: ids
        )
        let widths = zip([existingDivider] + positions, positions).map { $1 - $0 }
        let maximumChordX = last.chordLayouts.map { $0.frame.union($0.naturalFrame).maxX }.max() ?? existingDivider
        guard let firstX = positions.first, firstX > maximumChordX,
              widths.allSatisfy({ (Measure.minimumDrawnRhythmTailWidth...Measure.maximumManualLayoutWidth).contains($0) })
        else { return rejected }

        var staged = self
        guard let insertedIDs = staged.insertMeasures(after: lastID, count: widths.count) else { return rejected }
        for (id, width) in zip(insertedIDs, widths) {
            staged.setDraftBarlineSegmentManualLayoutWidth(width, for: id, usesDrawnRhythmTailWidth: true)
        }

        let proposed = LeadSheetPageLayoutEngine.pageLayout(
            for: staged, pageSize: sourceLayout.pageBounds.size, includesChordInkContinuationLanes: true
        )
        // Inserting at the tail must not repack other rows or move existing
        // chord/staff anchors, including those used by persistent Free Ink.
        guard automaticContinuationFramesMatch(sourceLayout.paperEnvelope, proposed.paperEnvelope),
              sourceLayout.systems.allSatisfy({ oldRow in
                  guard let newRow = proposed.systems.first(where: { $0.index == oldRow.index }) else { return false }
                  return oldRow.measures.allSatisfy { old in
                      guard let new = newRow.measures.first(where: { $0.sourceMeasureID == old.sourceMeasureID }) else {
                          return false
                      }
                      return automaticContinuationFramesMatch(old.staffFrame, new.staffFrame)
                          && automaticContinuationFramesMatch(old.chordWritingFrame, new.chordWritingFrame)
                          && old.chordLayouts == new.chordLayouts
                  }
              }), let proposedRow = proposed.systems.first(where: { $0.index == rowIndex }),
              zip(insertedIDs, positions).allSatisfy({ id, x in
                  guard let measure = proposedRow.measures.first(where: { $0.sourceMeasureID == id }) else { return false }
                  return abs(measure.trailingBarlineFrame.midX - x) < 0.01
              }) else { return rejected }

        _ = staged.setPageHandwrittenChordDrawing(nil)
        self = staged
        return ChordInkDraftBatchRenderResult(renderedChordIDs: [], renderedBarlineIDs: ids, unresolvedDraftIDs: [])
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
        var staged = self
        let previouslyOpenIDs = Set(measures.filter { $0.authoringState == .open }.map(\.id))
        staged.materializeSimpleChordDraftRowsIfNeeded(for: [], barlines: renderableBarlines)
        let commitLayout = layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: staged,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        let barlinePlan = staged.commitDraftBarlinesBeforeChordRender(
            renderableBarlines,
            spacingMode: barlineSpacingMode,
            sourcePageLayout: sourceLayout,
            commitPageLayout: commitLayout
        )
        if !barlinePlan.renderedBarlineIDs.isEmpty {
            let closedIDs = Set(staged.measures.filter {
                previouslyOpenIDs.contains($0.id) && $0.authoringState == .committed
            }.map(\.id))
            staged.anchorLoneChordsToMeasureStart(in: barlinePlan.splitMeasureIDs.union(closedIDs))
            self = staged
        }
        return barlinePlan.renderedBarlineIDs
    }

    private mutating func commitDraftBarlinesBeforeChordRender(
        _ barlines: [DraftBarline],
        spacingMode: ChordDraftBarlineSpacingMode,
        sourcePageLayout: LeadSheetPageLayout?,
        commitPageLayout: LeadSheetPageLayout?,
        requiresCompleteSplits: Bool = false
    ) -> ChordDraftBarlineCommitPlan {
        var renderedBarlineIDs = [UUID]()
        var unresolvedDraftIDs = [UUID]()
        var segmentMeasureIDsByOriginalMeasureID = [UUID: [UUID]]()
        var boundaryFractionsByOriginalMeasureID = [UUID: [Double]]()
        var sourceBoundaryFractionsByOriginalMeasureID = [UUID: [Double]]()
        let resolution = resolvedDraftBarlinesForCommit(
            barlines,
            sourcePageLayout: sourcePageLayout,
            commitPageLayout: commitPageLayout
        )
        let resolvedBarlines = resolution.barlines
        let committedSplitMeasureIDs = Set(resolvedBarlines.filter {
            guard layoutStyle == .rhythmSectionSheet else { return false }
            guard measure(id: $0.measureID)?.authoringState == .committed else { return false }
            let geometry = resolution.sourceGeometryByMeasureID[$0.measureID]
                ?? chordDraftBarlineSourceGeometry(for: $0.measureID, sourcePageLayout: sourcePageLayout)
            return ChordDraftBarlineBoundaryPlacement.placement(fraction: $0.fraction,
                sourceWidth: geometry?.fractionFrame.width ?? 1_000,
                barWidth: $0.metrics.width, edgeTolerance: 9) == .interior
        }.map(\.measureID))
        let splitsCommittedRhythm = !committedSplitMeasureIDs.isEmpty
        let originalWidths = Dictionary(uniqueKeysWithValues: measures.map {
            ($0.id, (width: $0.manualLayoutWidth, drawn: $0.usesDrawnRhythmTailWidth,
                source: $0.rhythmSectionSplitLayoutSource))
        })
        var didSplitCommittedRhythm = false
        var frozenSourceMeasureIDs = Set<UUID>()
        if splitsCommittedRhythm, let sourcePageLayout {
            // Keep the same row footprint when a stored measure becomes two.
            // Otherwise automatic/equal-row width resolution can move every
            // later measure even though the divider was drawn in-place.
            for row in sourcePageLayout.systems where row.measures.contains(where: {
                $0.sourceMeasureID.map(committedSplitMeasureIDs.contains) == true
            }) {
                for source in row.measures {
                    guard let id = source.sourceMeasureID,
                          let original = measure(id: id) else { continue }
                    frozenSourceMeasureIDs.insert(id)
                    for systemIndex in systems.indices {
                        guard let index = systems[systemIndex].measures.firstIndex(where: { $0.id == id }) else { continue }
                        if systems[systemIndex].measures[index].rhythmSectionSplitLayoutSource == nil {
                            systems[systemIndex].measures[index].rhythmSectionSplitLayoutSource = RhythmSectionSplitLayoutSource(
                                groupID: id, manualLayoutWidth: original.manualLayoutWidth,
                                authoringState: original.authoringState)
                        }
                    }
                    setDraftBarlineSegmentManualLayoutWidth(source.staffFrame.width,
                        for: id, usesDrawnRhythmTailWidth: true)
                }
            }
        }
        let sortedBarlinesByMeasureID = Dictionary(grouping: resolvedBarlines.sorted(by: { lhs, rhs in
            if lhs.measureIndex != rhs.measureIndex { return lhs.measureIndex < rhs.measureIndex }
            if lhs.fraction != rhs.fraction { return lhs.fraction < rhs.fraction }
            return lhs.id.uuidString < rhs.id.uuidString
        })) { $0.measureID }
        let orderedMeasureIDs = sortedBarlinesByMeasureID.keys.sorted { lhs, rhs in
            let lhsIndex = sortedBarlinesByMeasureID[lhs]?.first?.measureIndex ?? 0
            let rhsIndex = sortedBarlinesByMeasureID[rhs]?.first?.measureIndex ?? 0
            return lhsIndex < rhsIndex
        }

        for measureID in orderedMeasureIDs {
            guard let measureBarlines = sortedBarlinesByMeasureID[measureID],
                  !measureBarlines.isEmpty else { continue }
            let sourceGeometry = resolution.sourceGeometryByMeasureID[measureID]
                ?? chordDraftBarlineSourceGeometry(for: measureID, sourcePageLayout: sourcePageLayout)
            // Drawing over an existing divider confirms that boundary rather
            // than participating in split spacing or creating a tiny measure.
            let splitBarlines = measureBarlines.filter { barline in
                let placement = ChordDraftBarlineBoundaryPlacement.placement(
                    fraction: barline.fraction,
                    sourceWidth: sourceGeometry?.fractionFrame.width ?? 1_000,
                    barWidth: barline.metrics.width,
                    edgeTolerance: layoutStyle == .rhythmSectionSheet ? 9 : 6
                )
                if placement == .interior { return true }
                renderedBarlineIDs.append(barline.id)
                return false
            }
            segmentMeasureIDsByOriginalMeasureID[measureID] = [measureID]
            boundaryFractionsByOriginalMeasureID[measureID] = []
            sourceBoundaryFractionsByOriginalMeasureID[measureID] = []
            let boundaryFractions = spacingMode.boundaryFractions(for: splitBarlines.map(\.fraction))
            var previousBoundaryFraction = Double(0)
            var previousMusicalBoundaryFraction = Double(0)
            let originalRhythmMeasure = layoutStyle == .rhythmSectionSheet ? measure(id: measureID) : nil
            let originalMeter = originalRhythmMeasure?.resolvedMeter(defaultMeter: defaultMeter)
            let originalSlotFractions: [Double]? = originalRhythmMeasure?.rhythmMap.flatMap { map in
                guard let meter = originalMeter, let slots = map.resolvedSlots(for: meter) else { return nil }
                return slots.dropFirst().compactMap {
                    $0.startPosition.startOffset(in: meter).map { $0 / meter.measureLengthInWholeNotes }
                }
            }

            for (barlineIndex, barline) in splitBarlines.enumerated() {
                guard boundaryFractions.indices.contains(barlineIndex),
                      let currentSegmentMeasureID = segmentMeasureIDsByOriginalMeasureID[measureID]?.last else {
                    if requiresCompleteSplits { unresolvedDraftIDs.append(barline.id) }
                    continue
                }
                let boundaryFraction = boundaryFractions[barlineIndex]
                let localSplitFraction = (boundaryFraction - previousBoundaryFraction)
                    / max(0.0001, 1 - previousBoundaryFraction)
                var musicalBoundaryFraction: Double?
                if let originalSlotFractions {
                    // Keep the source timeline separate from the remaining
                    // visual width. Earlier segments have already been padded
                    // back to full-meter rhythm maps by this point.
                    let tolerance = sourceGeometry.map { 9 / max(1, Double($0.fractionFrame.width)) } ?? 0.0001
                    guard let onset = originalSlotFractions.min(by: {
                        abs($0 - boundaryFraction) < abs($1 - boundaryFraction)
                    }), abs(onset - boundaryFraction) <= tolerance,
                          onset > previousMusicalBoundaryFraction else {
                        if requiresCompleteSplits { unresolvedDraftIDs.append(barline.id) }
                        continue
                    }
                    musicalBoundaryFraction = onset
                }
                let wasCommittedRhythm = layoutStyle == .rhythmSectionSheet
                    && measure(id: currentSegmentMeasureID)?.authoringState == .committed
                guard (!requiresCompleteSplits || (localSplitFraction > 0 && localSplitFraction < 1)),
                      let newSegmentMeasureID = splitMeasureForDraftBarline(
                        currentSegmentMeasureID,
                        atFraction: localSplitFraction,
                        barlineAfter: .single,
                        sourceGeometry: sourceGeometry,
                        sourcePageLayout: sourcePageLayout,
                        precedingBoundaryFraction: previousBoundaryFraction,
                        musicalSplitFraction: musicalBoundaryFraction.map { $0 - previousMusicalBoundaryFraction }
                      ) else {
                    // The batch may clear source ink only after each
                    // unsatisfied structural boundary has been placed.
                    if requiresCompleteSplits { unresolvedDraftIDs.append(barline.id) }
                    continue
                }
                didSplitCommittedRhythm = didSplitCommittedRhythm || wasCommittedRhythm
                segmentMeasureIDsByOriginalMeasureID[measureID, default: [measureID]].append(newSegmentMeasureID)
                boundaryFractionsByOriginalMeasureID[measureID, default: []].append(boundaryFraction)
                sourceBoundaryFractionsByOriginalMeasureID[measureID, default: []].append(barline.fraction)
                previousBoundaryFraction = boundaryFraction
                if let musicalBoundaryFraction { previousMusicalBoundaryFraction = musicalBoundaryFraction }
                renderedBarlineIDs.append(barline.id)
            }

            guard !splitBarlines.isEmpty else { continue }
            let segmentMeasureIDs = segmentMeasureIDsByOriginalMeasureID[measureID] ?? []
            let committedBoundaryFractions = boundaryFractionsByOriginalMeasureID[measureID] ?? []
            switch layoutStyle {
            case .simpleChordSheet:
                applyDraftBarlineSegmentWidths(originalMeasureID: measureID,
                    segmentMeasureIDs: segmentMeasureIDs, boundaryFractions: committedBoundaryFractions,
                    sourceGeometryOverride: sourceGeometry, sourcePageLayout: sourcePageLayout)
            case .rhythmSectionSheet:
                let sourceMeasure = sourcePageLayout?.systems.flatMap(\.measures).first {
                    $0.sourceMeasureID == measureID
                }
                applyRhythmSectionDraftBarlineSegmentWidths(segmentMeasureIDs: segmentMeasureIDs,
                    boundaryFractions: committedBoundaryFractions, sourceGeometryOverride: sourceGeometry,
                    dividerCenterOffset: sourceMeasure?.isOpen == false
                        ? (sourceMeasure?.trailingBarlineFrame.width ?? 0) / 2 : 0)
            case .leadSheet:
                break
            }
        }

        if didSplitCommittedRhythm, let sourcePageLayout {
            preserveCommittedRhythmChordFrames(from: sourcePageLayout, sourceMeasureIDs: frozenSourceMeasureIDs)
        } else if splitsCommittedRhythm {
            for systemIndex in systems.indices {
                for measureIndex in systems[systemIndex].measures.indices {
                    guard let original = originalWidths[systems[systemIndex].measures[measureIndex].id] else { continue }
                    systems[systemIndex].measures[measureIndex].manualLayoutWidth = original.width
                    systems[systemIndex].measures[measureIndex].usesDrawnRhythmTailWidth = original.drawn
                    systems[systemIndex].measures[measureIndex].rhythmSectionSplitLayoutSource = original.source
                }
            }
        }

        var seenRendered = Set<UUID>()
        var seenUnresolved = Set<UUID>()
        return ChordDraftBarlineCommitPlan(
            renderedBarlineIDs: renderedBarlineIDs.filter { seenRendered.insert($0).inserted },
            segmentMeasureIDsByOriginalMeasureID: segmentMeasureIDsByOriginalMeasureID,
            boundaryFractionsByOriginalMeasureID: boundaryFractionsByOriginalMeasureID,
            sourceBoundaryFractionsByOriginalMeasureID: sourceBoundaryFractionsByOriginalMeasureID,
            unresolvedDraftIDs: unresolvedDraftIDs.filter { seenUnresolved.insert($0).inserted }
        )
    }

    private mutating func splitMeasureForDraftBarline(
        _ measureID: UUID,
        atFraction fraction: Double,
        barlineAfter: BarlineType,
        sourceGeometry: ChordDraftBarlineSourceGeometry?,
        sourcePageLayout: LeadSheetPageLayout?,
        precedingBoundaryFraction: Double,
        musicalSplitFraction: Double?
    ) -> UUID? {
        switch layoutStyle {
        case .simpleChordSheet:
            return splitSimpleChordMeasure(
                measureID,
                atFraction: fraction,
                barlineAfter: barlineAfter,
                normalizeSingleChordToMeasureStart: false
            )
        case .rhythmSectionSheet:
            if measure(id: measureID)?.authoringState == .committed {
                if let frame = sourceGeometry?.fractionFrame {
                    let width = frame.width * CGFloat(1 - precedingBoundaryFraction)
                    guard width * CGFloat(fraction) - 0.8 >= Measure.minimumDrawnRhythmTailWidth,
                          width * CGFloat(1 - fraction) >= Measure.minimumDrawnRhythmTailWidth else { return nil }
                }
                var visualFractions = [UUID: Double]()
                if let frame = sourceGeometry?.fractionFrame, let sourcePageLayout {
                    let eventIDs = Set(measure(id: measureID)?.chordEvents.map(\.id) ?? [])
                    for chord in sourcePageLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
                    where eventIDs.contains(chord.id) {
                        let originalFraction = Double((chord.frame.minX - frame.minX) / max(1, frame.width))
                        visualFractions[chord.id] = (originalFraction - precedingBoundaryFraction)
                            / max(0.0001, 1 - precedingBoundaryFraction)
                    }
                }
                return splitCommittedRhythmSectionMeasure(measureID, atFraction: fraction,
                    barlineAfter: barlineAfter, visualChordFractions: visualFractions,
                    sourceWidth: sourceGeometry.map { Double($0.fractionFrame.width) * (1 - precedingBoundaryFraction) },
                    musicalSplitFraction: musicalSplitFraction,
                    normalizeSingleChordToMeasureStart: false)
            }
            return splitOpenRhythmSectionMeasure(
                measureID,
                atFraction: fraction,
                barlineAfter: barlineAfter,
                normalizeSingleChordToMeasureStart: false
            )
        case .leadSheet:
            return nil
        }
    }

    private mutating func preserveCommittedRhythmChordFrames(from sourceLayout: LeadSheetPageLayout,
        sourceMeasureIDs: Set<UUID>) {
        let sourceFrames = Dictionary(uniqueKeysWithValues: sourceLayout.systems
            .flatMap(\.measures).filter { $0.sourceMeasureID.map(sourceMeasureIDs.contains) == true }
            .flatMap(\.chordLayouts).map { ($0.id, $0.frame) })
        let outputLayout = LeadSheetPageLayoutEngine.pageLayout(for: self,
            pageSize: sourceLayout.pageBounds.size, includesChordInkContinuationLanes: true)
        for output in outputLayout.systems.flatMap(\.measures) {
            guard let measureID = output.sourceMeasureID,
                  let systemIndex = systems.firstIndex(where: { $0.measures.contains { $0.id == measureID } }),
                  let measureIndex = systems[systemIndex].measures.firstIndex(where: { $0.id == measureID })
            else { continue }
            for index in systems[systemIndex].measures[measureIndex].chordEvents.indices {
                let id = systems[systemIndex].measures[measureIndex].chordEvents[index].id
                guard let frame = sourceFrames[id] else { continue }
                let fraction = Double((frame.minX - output.chordBandFrame.minX) / max(1, output.chordBandFrame.width))
                systems[systemIndex].measures[measureIndex].chordEvents[index]
                    .manualVisualLaneFraction = ChordEvent.clampedManualLaneFraction(fraction)
            }
        }
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
            if isTerminalBoundaryLaneLocation(
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
                paperFrame: pageLayout.paperFrame(for: system)
              ) else {
            return nil
        }

        let laneX = laneFrame.minX + laneFrame.width * CGFloat(laneLocation.fraction)
        if rejectsCommittedTerminalFiller,
            LeadSheetSimpleChordTerminalBarlineGeometry.terminalBoundaryContainsLaneX(
            laneX,
            in: system,
            paperFrame: pageLayout.paperFrame(for: system),
            layoutStyle: layoutStyle
           ) {
            return nil
        }

        let measures = system.measures.compactMap { measure -> (source: LeadSheetMeasureLayout, display: LeadSheetMeasureLayout)? in
            guard measure.chordInkTargetMeasureID != nil || measure.sourceMeasureID != nil else {
                return nil
            }

            return (
                source: measure,
                display: LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                    measure,
                    in: system,
                    paperFrame: pageLayout.paperFrame(for: system),
                    layoutStyle: layoutStyle
                )
            )
        }
        guard !measures.isEmpty else {
            return nil
        }

        let targetMeasure = measures.first { measure in
            measure.display.chordWritingFrame.insetBy(dx: -4, dy: 0).minX <= laneX
                && laneX <= measure.display.chordWritingFrame.insetBy(dx: -4, dy: 0).maxX
        } ?? measures.min { lhs, rhs in
            horizontalDistance(from: laneX, to: lhs.display.chordWritingFrame)
                < horizontalDistance(from: laneX, to: rhs.display.chordWritingFrame)
        }

        guard let targetMeasure,
              let measureID = targetMeasure.source.chordInkTargetMeasureID ?? targetMeasure.source.sourceMeasureID else {
            return nil
        }

        let segmentFrame = chordDraftBarlineSegmentFrame(for: targetMeasure.display)
        let fraction = (laneX - segmentFrame.minX)
            / max(1, segmentFrame.width)
        return ChordDraftBarlineLaneTarget(
            measureID: measureID,
            measureIndex: targetMeasure.source.index,
            fraction: Double(min(max(fraction, 0), 0.9999)),
            sourceGeometry: ChordDraftBarlineSourceGeometry(
                laneFrame: laneFrame,
                measureFrame: segmentFrame,
                fractionFrame: segmentFrame
            )
        )
    }

    private func chordDraftBarlineSegmentFrame(for measure: LeadSheetMeasureLayout) -> CGRect {
        switch layoutStyle {
        case .rhythmSectionSheet:
            return measure.staffFrame
        case .simpleChordSheet, .leadSheet:
            return measure.frame
        }
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

    private mutating func applyRhythmSectionDraftBarlineSegmentWidths(
        segmentMeasureIDs: [UUID],
        boundaryFractions: [Double],
        sourceGeometryOverride: ChordDraftBarlineSourceGeometry?,
        dividerCenterOffset: CGFloat = 0
    ) {
        guard layoutStyle == .rhythmSectionSheet,
              !segmentMeasureIDs.isEmpty,
              let sourceGeometry = sourceGeometryOverride else {
            return
        }

        let sourceFrame = sourceGeometry.measureFrame
        let fractionFrame = sourceGeometry.fractionFrame
        let clampedBoundaryXs = boundaryFractions
            .map { boundaryFraction in
                fractionFrame.minX + fractionFrame.width * CGFloat(min(max(boundaryFraction, 0.0001), 0.9999))
                    - dividerCenterOffset
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
            setDraftBarlineSegmentManualLayoutWidth(
                targetRowWidth,
                for: measureID,
                usesDrawnRhythmTailWidth: measure(id: measureID)?.authoringState == .committed
            )
        }
    }

    private mutating func setDraftBarlineSegmentManualLayoutWidth(
        _ width: CGFloat,
        for measureID: UUID,
        usesDrawnRhythmTailWidth: Bool = false
    ) {
        let storedWidth = Double(min(max(width, 1), Measure.maximumManualLayoutWidth))
        for systemIndex in systems.indices {
            guard let measureIndex = systems[systemIndex].measures.firstIndex(where: { $0.id == measureID }) else {
                continue
            }

            systems[systemIndex].measures[measureIndex].manualLayoutWidth = storedWidth
            systems[systemIndex].measures[measureIndex].usesDrawnRhythmTailWidth = usesDrawnRhythmTailWidth
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
                    paperFrame: sourcePageLayout.paperFrame(for: system)
                  ) else {
                continue
            }

            guard let measure = system.measures.first(where: { measure in
                measure.chordInkTargetMeasureID == originalMeasureID
                    || measure.sourceMeasureID == originalMeasureID
            }) else {
                continue
            }
            let segmentFrame = chordDraftBarlineSegmentFrame(for: measure)
            let fractionFrame = layoutStyle == .rhythmSectionSheet ? segmentFrame : laneFrame

            return ChordDraftBarlineSourceGeometry(
                laneFrame: laneFrame,
                measureFrame: segmentFrame,
                fractionFrame: fractionFrame
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
        if layoutStyle == .rhythmSectionSheet,
           let segmentTarget = chordDraftSegmentTarget(
            for: draft,
            barlinePlan: barlinePlan
           ) {
            return segmentTarget
        }

        if let renderPageLayout {
            if let laneTarget = chordDraftLaneTarget(
                for: draft,
                pageLayout: renderPageLayout,
                rejectsCommittedTerminalFiller: false
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

    private func isTerminalBoundaryLaneLocation(
        _ laneLocation: ChordInkDraftLaneLocation?,
        in pageLayout: LeadSheetPageLayout
    ) -> Bool {
        guard let laneLocation,
              let system = pageLayout.systems.first(where: { $0.index == laneLocation.systemIndex }),
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame(for: system)
              ) else {
            return false
        }

        let laneX = laneFrame.minX + laneFrame.width * CGFloat(laneLocation.fraction)
        return LeadSheetSimpleChordTerminalBarlineGeometry.terminalBoundaryContainsLaneX(
            laneX,
            in: system,
            paperFrame: pageLayout.paperFrame(for: system),
            layoutStyle: layoutStyle
        )
    }

    private func chordDraftSegmentTarget(
        for draft: ChordInkDraft,
        barlinePlan: ChordDraftBarlineCommitPlan
    ) -> (measureID: UUID, fraction: Double?)? {
        guard let segmentMeasureIDs = barlinePlan.segmentMeasureIDsByOriginalMeasureID[draft.measureID],
              !segmentMeasureIDs.isEmpty,
              let measureFraction = chordDraftSegmentFraction(for: draft) else {
            return nil
        }

        let boundaries = (barlinePlan.boundaryFractionsByOriginalMeasureID[draft.measureID] ?? [])
            .sorted()
        let segmentIndex = boundaries.firstIndex { measureFraction < $0 } ?? boundaries.count
        let clampedSegmentIndex = min(max(0, segmentIndex), segmentMeasureIDs.count - 1)
        let lowerBoundary = clampedSegmentIndex == 0 ? 0 : boundaries[clampedSegmentIndex - 1]
        let upperBoundary = clampedSegmentIndex < boundaries.count ? boundaries[clampedSegmentIndex] : 1
        let localFraction = (measureFraction - lowerBoundary) / max(0.0001, upperBoundary - lowerBoundary)

        return (
            segmentMeasureIDs[clampedSegmentIndex],
            min(max(localFraction, 0), 0.9999)
        )
    }

    private func chordDraftSegmentFraction(for draft: ChordInkDraft) -> Double? {
        let rawFraction: Double?
        switch layoutStyle {
        case .rhythmSectionSheet:
            rawFraction = draft.targetFraction
                ?? draft.visualOrder.map { $0 - floor($0) }
                ?? draft.laneLocation?.fraction
        case .simpleChordSheet, .leadSheet:
            rawFraction = draft.laneLocation?.fraction
                ?? draft.visualOrder.map { $0 - floor($0) }
                ?? draft.targetFraction
        }

        return rawFraction.map { min(max($0, 0), 0.9999) }
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
                paperFrame: pageLayout.paperFrame(for: system)
              ) else {
            return nil
        }

        let laneX = laneFrame.minX + laneFrame.width * CGFloat(laneLocation.fraction)
        if rejectsCommittedTerminalFiller,
           LeadSheetSimpleChordTerminalBarlineGeometry.terminalFillerContainsLaneX(
            laneX,
            in: system,
            paperFrame: pageLayout.paperFrame(for: system),
            layoutStyle: layoutStyle
           ) {
            return nil
        }

        let measures = system.measures.compactMap { measure -> (source: LeadSheetMeasureLayout, display: LeadSheetMeasureLayout)? in
            guard measure.chordInkTargetMeasureID != nil else {
                return nil
            }

            return (
                source: measure,
                display: LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                    measure,
                    in: system,
                    paperFrame: pageLayout.paperFrame(for: system),
                    layoutStyle: layoutStyle
                )
            )
        }
        guard !measures.isEmpty else {
            return nil
        }

        let targetMeasure = measures.first { measure in
            measure.display.chordWritingFrame.insetBy(dx: -4, dy: 0).minX <= laneX
                && laneX <= measure.display.chordWritingFrame.insetBy(dx: -4, dy: 0).maxX
        } ?? measures.min { lhs, rhs in
            horizontalDistance(from: laneX, to: lhs.display.chordWritingFrame)
                < horizontalDistance(from: laneX, to: rhs.display.chordWritingFrame)
        }

        guard let targetMeasure,
              let measureID = targetMeasure.source.chordInkTargetMeasureID else {
            return nil
        }

        let fraction = (laneX - targetMeasure.source.chordBandFrame.minX)
            / max(1, targetMeasure.source.chordBandFrame.width)
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

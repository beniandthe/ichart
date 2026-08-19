#if canImport(UIKit)
import CoreGraphics
import Foundation

enum ChordInkDraftPreviewPolicy {
    static let recognitionDelay: TimeInterval = 0.58
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
    var sourceStrokeIndex: Int?
    var metrics: DraftBarlineGestureMetrics
    var ambiguity: DraftBarlineAmbiguity

    init(
        id: UUID = UUID(),
        measureID: UUID,
        measureIndex: Int,
        fraction: Double,
        sourceStrokeIndex: Int? = nil,
        metrics: DraftBarlineGestureMetrics,
        ambiguity: DraftBarlineAmbiguity = .none
    ) {
        self.id = id
        self.measureID = measureID
        self.measureIndex = measureIndex
        self.fraction = min(max(fraction, 0), 0.9999)
        self.sourceStrokeIndex = sourceStrokeIndex
        self.metrics = metrics
        self.ambiguity = ambiguity
    }

    var isRenderable: Bool {
        ambiguity == .none
    }
}

struct ChordDraftBarlineIdentitySignature: Hashable {
    var measureID: UUID
    var fractionBucket: Int
    var sourceStrokeIndex: Int?

    init(measureID: UUID, fraction: Double, sourceStrokeIndex: Int?) {
        self.measureID = measureID
        self.fractionBucket = Int((min(max(fraction, 0), 0.9999) * 64).rounded())
        self.sourceStrokeIndex = sourceStrokeIndex
    }
}

extension DraftBarline {
    var identitySignature: ChordDraftBarlineIdentitySignature {
        ChordDraftBarlineIdentitySignature(
            measureID: measureID,
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
        let previousDraftByAnchor = Dictionary(uniqueKeysWithValues: draftChords.map { ($0.anchor, $0) })
        draftChords = inputs
            .sorted { lhs, rhs in
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
            .map { input in
                let previousDraft = previousDraftByAnchor[input.anchor]
                return ChordInkDraft(
                    id: previousDraft?.id ?? UUID(),
                    input: input,
                    selectedText: previousDraft?.selectedText,
                    isStale: false
                )
            }
        layoutPageSize = inputs.compactMap(\.layoutPageSize).first ?? layoutPageSize
        self.updatedAt = updatedAt
    }

    mutating func replaceDraftBarlines(with barlines: [DraftBarline], updatedAt: Date = .now) {
        let previousDraftBySignature = Dictionary(
            draftBarlines.map { ($0.identitySignature, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        draftBarlines = barlines
            .sorted {
                if $0.measureIndex == $1.measureIndex {
                    return $0.fraction < $1.fraction
                }

                return $0.measureIndex < $1.measureIndex
            }
            .map { barline in
                var resolvedBarline = barline
                if let previousDraft = previousDraftBySignature[barline.identitySignature] {
                    resolvedBarline.id = previousDraft.id
                }
                return resolvedBarline
            }
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
        let x = boundedLaneFrame.minX + boundedLaneFrame.width * CGFloat(barline.fraction)
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
        laneFrameForMeasureID: (UUID) -> CGRect?,
        selectedBarlineID: UUID?
    ) -> ChordDraftBarlineHitTarget? {
        for barline in barlines.reversed() {
            guard let laneFrame = laneFrameForMeasureID(barline.measureID) else {
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
        guard bounds.height >= 22 else {
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
        guard angleDegrees <= 13 else {
            return nil
        }
        guard straightness >= 0.74 else {
            return nil
        }
        guard widthRatio <= 0.24 || bounds.width <= 10 else {
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
        guard laneCoverage >= 0.72,
              bounds.minY <= laneFrame.minY + 12,
              bounds.maxY >= laneFrame.maxY - 12 else {
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
            metrics: metrics
        )
    }

    private static func draftBarlineTarget(
        at center: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> (measureID: UUID, measureIndex: Int, laneFrame: CGRect)? {
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

            return (measureID, measure.index, laneFrame)
        }

        return nil
    }

    private static func removeVeryCloseBarlines(
        _ barlines: [(barline: DraftBarline, strokeIndex: Int)]
    ) -> [(barline: DraftBarline, strokeIndex: Int)] {
        var retained = [(barline: DraftBarline, strokeIndex: Int)]()
        for barlinePair in barlines.sorted(by: { lhs, rhs in
            if lhs.barline.measureIndex == rhs.barline.measureIndex {
                return lhs.barline.fraction < rhs.barline.fraction
            }

            return lhs.barline.measureIndex < rhs.barline.measureIndex
        }) {
            if retained.contains(where: { existing in
                existing.barline.measureID == barlinePair.barline.measureID
                    && abs(existing.barline.fraction - barlinePair.barline.fraction) < 0.035
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
        var measureID: UUID
        var fraction: Double?
    }

    @discardableResult
    mutating func commitChordInkDraftBatch(
        _ state: ChordPreviewState,
        barlineSpacingMode: ChordDraftBarlineSpacingMode = .drawn
    ) -> ChordInkDraftBatchRenderResult {
        let sourceLayout = state.layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: self,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        let barlinePlan = commitDraftBarlinesBeforeChordRender(
            state.renderableBarlines,
            spacingMode: barlineSpacingMode,
            sourcePageLayout: sourceLayout
        )
        materializeSimpleChordDraftRowsIfNeeded(for: state.renderableDraftChords)
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
                pageLayout: renderLayout,
                barlinePlan: barlinePlan
            )
            return ChordDraftResolvedRenderTarget(
                draft: draft,
                measureID: renderTarget.measureID,
                fraction: renderTarget.fraction
            )
        }

        for renderTarget in renderTargets {
            let draft = renderTarget.draft
            guard let previewText = draft.previewText,
                  let match = ChordRecognitionCompendium.match(previewText),
                  let chordEventID = appendRecognizedChordEvent(
                    match.symbol,
                    rawInput: previewText,
                    to: renderTarget.measureID,
                    atFraction: renderTarget.fraction,
                    sourceInkData: draft.drawingData,
                    sourceCandidateSignature: draft.sourceCandidateSignature
                  ) else {
                unresolvedDraftIDs.append(draft.id)
                continue
            }

            if layoutStyle == .simpleChordSheet,
               measure(id: renderTarget.measureID)?.rhythmMap == nil,
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

    private mutating func materializeSimpleChordDraftRowsIfNeeded(for drafts: [ChordInkDraft]) {
        guard layoutStyle == .simpleChordSheet,
              let targetSystemIndex = drafts.compactMap({ $0.laneLocation?.systemIndex }).max(),
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
        let sourceLayout = layoutPageSize.map {
            LeadSheetPageLayoutEngine.pageLayout(
                for: self,
                pageSize: $0,
                includesChordInkContinuationLanes: true
            )
        }
        let barlinePlan = commitDraftBarlinesBeforeChordRender(
            barlines.filter(\.isRenderable),
            spacingMode: barlineSpacingMode,
            sourcePageLayout: sourceLayout
        )
        return barlinePlan.renderedBarlineIDs
    }

    private mutating func commitDraftBarlinesBeforeChordRender(
        _ barlines: [DraftBarline],
        spacingMode: ChordDraftBarlineSpacingMode,
        sourcePageLayout: LeadSheetPageLayout?
    ) -> ChordDraftBarlineCommitPlan {
        var renderedBarlineIDs = [UUID]()
        var segmentMeasureIDsByOriginalMeasureID = [UUID: [UUID]]()
        var boundaryFractionsByOriginalMeasureID = [UUID: [Double]]()
        let sortedBarlinesByMeasureID = Dictionary(grouping: barlines.sorted(by: { lhs, rhs in
            if lhs.measureIndex == rhs.measureIndex {
                return lhs.fraction < rhs.fraction
            }

            return lhs.measureIndex < rhs.measureIndex
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
                sourcePageLayout: sourcePageLayout
            )
        }

        return ChordDraftBarlineCommitPlan(
            renderedBarlineIDs: renderedBarlineIDs,
            segmentMeasureIDsByOriginalMeasureID: segmentMeasureIDsByOriginalMeasureID,
            boundaryFractionsByOriginalMeasureID: boundaryFractionsByOriginalMeasureID
        )
    }

    private mutating func applyDraftBarlineSegmentWidths(
        originalMeasureID: UUID,
        segmentMeasureIDs: [UUID],
        boundaryFractions: [Double],
        sourcePageLayout: LeadSheetPageLayout?
    ) {
        guard layoutStyle == .simpleChordSheet,
              !segmentMeasureIDs.isEmpty,
              let sourceGeometry = chordDraftBarlineSourceGeometry(
                for: originalMeasureID,
                sourcePageLayout: sourcePageLayout
              ),
              let maxSystemWidth = sourcePageLayout.map({ max(1, $0.paperFrame.width - 68) }) else {
            return
        }

        let sourceFrame = sourceGeometry.measureFrame
        let clampedBoundaryXs = boundaryFractions
            .map { boundaryFraction in
                sourceGeometry.laneFrame.minX + sourceGeometry.laneFrame.width * CGFloat(min(max(boundaryFraction, 0.0001), 0.9999))
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

    private struct ChordDraftBarlineSourceGeometry {
        var laneFrame: CGRect
        var measureFrame: CGRect
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
                measureFrame: measureFrame
            )
        }

        return nil
    }

    private func chordDraftRenderTarget(
        for draft: ChordInkDraft,
        pageLayout: LeadSheetPageLayout?,
        barlinePlan: ChordDraftBarlineCommitPlan
    ) -> (measureID: UUID, fraction: Double?) {
        if let segmentTarget = chordDraftSegmentTarget(
            for: draft,
            barlinePlan: barlinePlan
        ) {
            return segmentTarget
        }

        if let pageLayout,
           let laneTarget = chordDraftLaneTarget(
                for: draft,
                pageLayout: pageLayout
           ) {
            return laneTarget
        }

        return (draft.measureID, draft.laneLocation?.fraction ?? draft.targetFraction)
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
        pageLayout: LeadSheetPageLayout
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

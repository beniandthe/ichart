#if canImport(UIKit)
import CoreGraphics
import Foundation

enum ChordInkDraftPreviewPolicy {
    static let recognitionDelay: TimeInterval = 0.58
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

struct ChordInkDraftInput: Hashable {
    var measureID: UUID
    var measureIndex: Int
    var targetFraction: Double?
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
    var metrics: DraftBarlineGestureMetrics
    var ambiguity: DraftBarlineAmbiguity

    init(
        id: UUID = UUID(),
        measureID: UUID,
        measureIndex: Int,
        fraction: Double,
        metrics: DraftBarlineGestureMetrics,
        ambiguity: DraftBarlineAmbiguity = .none
    ) {
        self.id = id
        self.measureID = measureID
        self.measureIndex = measureIndex
        self.fraction = min(max(fraction, 0), 0.9999)
        self.metrics = metrics
        self.ambiguity = ambiguity
    }

    var isRenderable: Bool {
        ambiguity == .none
    }
}

struct ChordPreviewState: Equatable {
    var draftChords: [ChordInkDraft] = []
    var draftBarlines: [DraftBarline] = []
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
        self.updatedAt = updatedAt
    }

    mutating func replaceDraftBarlines(with barlines: [DraftBarline], updatedAt: Date = .now) {
        draftBarlines = barlines
            .sorted {
                if $0.measureIndex == $1.measureIndex {
                    return $0.fraction < $1.fraction
                }

                return $0.measureIndex < $1.measureIndex
            }
        self.updatedAt = updatedAt
    }

    mutating func discard() {
        draftChords = []
        draftBarlines = []
        updatedAt = nil
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
            barlines: deDuplicatedBarlines.map(\.barline),
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
        guard let measure = pageLayout.systems
            .flatMap(\.measures)
            .compactMap({ measure -> LeadSheetMeasureLayout? in
                guard measure.sourceMeasureID != nil else {
                    return nil
                }

                return measure
            })
            .first(where: { measure in
                measure.chordWritingFrame.insetBy(dx: -8, dy: -8).contains(center)
            }),
              let measureID = measure.sourceMeasureID else {
            return nil
        }

        let laneFrame = measure.chordWritingFrame
        let laneCoverage = Double(bounds.intersection(laneFrame).height / max(1, laneFrame.height))
        guard laneCoverage >= 0.42 else {
            return nil
        }

        let rawFraction = (center.x - measure.chordBandFrame.minX) / max(1, measure.chordBandFrame.width)
        let metrics = DraftBarlineGestureMetrics(
            height: Double(bounds.height),
            width: Double(bounds.width),
            angleDegreesFromVertical: angleDegrees,
            straightness: straightness,
            laneCoverage: laneCoverage
        )
        return DraftBarline(
            measureID: measureID,
            measureIndex: measure.index,
            fraction: Double(rawFraction),
            metrics: metrics
        )
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
    @discardableResult
    mutating func commitChordInkDraftBatch(_ state: ChordPreviewState) -> ChordInkDraftBatchRenderResult {
        var renderedChordIDs = [UUID]()
        var unresolvedDraftIDs = [UUID]()

        for draft in state.draftChords.sorted(by: { lhs, rhs in
            if lhs.measureIndex == rhs.measureIndex {
                return (lhs.targetFraction ?? 0) < (rhs.targetFraction ?? 0)
            }

            return lhs.measureIndex < rhs.measureIndex
        }) {
            guard let previewText = draft.previewText,
                  let match = ChordRecognitionCompendium.match(previewText),
                  let chordEventID = appendRecognizedChordEvent(
                    match.symbol,
                    rawInput: previewText,
                    to: draft.measureID,
                    atFraction: draft.targetFraction,
                    sourceInkData: draft.drawingData,
                    sourceCandidateSignature: draft.sourceCandidateSignature
                  ) else {
                unresolvedDraftIDs.append(draft.id)
                continue
            }

            renderedChordIDs.append(chordEventID)
        }

        var renderedBarlineIDs = [UUID]()
        var committedOpenMeasureIDs = Set<UUID>()
        for barline in state.renderableBarlines {
            guard !committedOpenMeasureIDs.contains(barline.measureID),
                  measure(id: barline.measureID)?.authoringState == .open,
                  commitOpenMeasure(barlineAfter: .single) != nil else {
                continue
            }

            committedOpenMeasureIDs.insert(barline.measureID)
            renderedBarlineIDs.append(barline.id)
        }

        if unresolvedDraftIDs.isEmpty,
           !renderedChordIDs.isEmpty || !renderedBarlineIDs.isEmpty {
            _ = setPageHandwrittenChordDrawing(nil)
        }

        return ChordInkDraftBatchRenderResult(
            renderedChordIDs: renderedChordIDs,
            renderedBarlineIDs: renderedBarlineIDs,
            unresolvedDraftIDs: unresolvedDraftIDs
        )
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

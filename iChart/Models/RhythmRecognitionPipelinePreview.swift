import CoreGraphics
import Foundation

#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
#endif

struct RhythmRecognitionPipelinePreview: Codable, Equatable, Hashable {
    struct GlyphEvidence: Codable, Equatable, Hashable {
        var strokeIndices: [Int]
        var kind: String
        var bounds: RhythmRecognitionPipelineBounds
        var confidence: Double
    }

    struct SymbolGroup: Codable, Equatable, Hashable {
        var index: Int
        var strokeIndices: [Int]
        var evidenceKinds: [String]
        var bounds: RhythmRecognitionPipelineBounds
    }

    struct ReasoningPath: Codable, Equatable, Hashable {
        var kind: String
        var outcome: String
        var values: [RhythmValue]
        var reason: String?
        var summary: String
    }

    var strokeCount: Int
    var evidenceCounts: [String: Int]
    var evidence: [GlyphEvidence]
    var symbolGroups: [SymbolGroup]
    var decision: String
    var route: String
    var selectedValues: [RhythmValue]
    var naturalUnits: Int?
    var targetUnits: Int?
    var reasoningPaths: [ReasoningPath]
    var notes: [String]

    var statusText: String {
        let evidenceText = evidenceCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .prefix(3)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let valueText = selectedValues.isEmpty
            ? "no values"
            : selectedValues.map(\.displayText).joined(separator: ", ")
        let noteText = notes.first.map { " • \($0)" } ?? ""

        return "\(strokeCount) strokes; \(evidenceText.isEmpty ? "no glyph evidence" : evidenceText); \(valueText)\(noteText)"
    }
}

#if canImport(UIKit) && canImport(PencilKit)
extension RhythmRecognitionPipelinePreview {
    static func make(
        drawingData: Data,
        meter: Meter,
        drawingFrame: CGRect,
        decision: RhythmRecognitionDecision,
        decisionText: String,
        routeText: String
    ) -> RhythmRecognitionPipelinePreview? {
        guard let drawing = try? PKDrawing(data: drawingData) else {
            return nil
        }

        return make(
            drawing: drawing,
            meter: meter,
            drawingFrame: drawingFrame,
            decision: decision,
            decisionText: decisionText,
            routeText: routeText
        )
    }

    static func make(
        drawing: PKDrawing,
        meter: Meter,
        drawingFrame: CGRect,
        decision: RhythmRecognitionDecision,
        decisionText: String,
        routeText: String
    ) -> RhythmRecognitionPipelinePreview {
        let strokeObservations = RhythmicNotationQuantizer.strokeObservations(from: drawing)
        let phraseEvidence = decision.phrase?.glyphEvidence ?? []
        let evidenceCounts = phraseEvidence.reduce(into: [String: Int]()) { counts, evidence in
            counts[evidence.kind.rawValue, default: 0] += 1
        }
        let evidenceSummaries = phraseEvidence.map { evidence in
            GlyphEvidence(
                strokeIndices: Array(evidence.strokeIndices).sorted(),
                kind: evidence.kind.rawValue,
                bounds: RhythmRecognitionPipelineBounds(evidence.bounds),
                confidence: evidence.confidence
            )
        }
        let symbolSummaries = (decision.phrase?.symbols ?? []).enumerated().map { index, symbol in
            let strokeIndices = Array(symbol.coveredStrokeIndices).sorted()
            return SymbolGroup(
                index: index,
                strokeIndices: strokeIndices,
                evidenceKinds: symbol.evidence.map(\.kind.rawValue),
                bounds: RhythmRecognitionPipelineBounds(symbol.bounds)
            )
        }

        return RhythmRecognitionPipelinePreview(
            strokeCount: strokeObservations.count,
            evidenceCounts: evidenceCounts,
            evidence: evidenceSummaries,
            symbolGroups: symbolSummaries,
            decision: decisionText,
            route: routeText,
            selectedValues: decision.proposal?.values ?? decision.phrase?.naturalValues ?? [],
            naturalUnits: decision.phrase?.naturalUnits,
            targetUnits: decision.phrase?.targetUnits,
            reasoningPaths: (decision.phrase?.reasoningPaths ?? []).map {
                ReasoningPath(
                    kind: $0.kind.rawValue,
                    outcome: $0.outcome.rawValue,
                    values: $0.values,
                    reason: $0.reason?.rawValue,
                    summary: $0.summary
                )
            },
            notes: notes(
                evidence: phraseEvidence,
                symbolGroups: symbolSummaries,
                decision: decision
            )
        )
    }

    private static func notes(
        evidence: [RhythmGlyphEvidence],
        symbolGroups: [SymbolGroup],
        decision: RhythmRecognitionDecision
    ) -> [String] {
        var notes: [String] = []
        let kinds = Set(evidence.map(\.kind))
        let hasSpecificRest = kinds.contains(.quarterRestZigzag)
            || kinds.contains(.eighthRestHook)
            || kinds.contains(.sixteenthRestDoubleHook)
            || kinds.contains(.halfRestBlock)
            || kinds.contains(.wholeRestBlock)
        let hasSpecificNote = kinds.contains(.filledNotehead)
            || kinds.contains(.openNotehead)
        if hasSpecificRest, hasSpecificNote {
            notes.append("rest and notehead evidence both present")
        }
        if symbolGroups.contains(where: { symbol in
            let symbolKinds = Set(symbol.evidenceKinds)
            let symbolHasRest = symbolKinds.contains(RhythmGlyphEvidenceKind.quarterRestZigzag.rawValue)
                || symbolKinds.contains(RhythmGlyphEvidenceKind.eighthRestHook.rawValue)
                || symbolKinds.contains(RhythmGlyphEvidenceKind.sixteenthRestDoubleHook.rawValue)
                || symbolKinds.contains(RhythmGlyphEvidenceKind.halfRestBlock.rawValue)
                || symbolKinds.contains(RhythmGlyphEvidenceKind.wholeRestBlock.rawValue)
            let symbolHasNote = symbolKinds.contains(RhythmGlyphEvidenceKind.filledNotehead.rawValue)
                || symbolKinds.contains(RhythmGlyphEvidenceKind.openNotehead.rawValue)
            return symbolHasRest && symbolHasNote
        }) {
            notes.append("rest and notehead share a symbol group")
        }
        if decision.reason == .underfilled {
            notes.append("phrase is recognized but short")
        }
        if decision.reason == .uncoveredStrokes {
            notes.append("some strokes were not owned by a symbol")
        }
        if decision.phrase?.reasoningPaths.isEmpty == false {
            notes.append("multiple reasoning paths available")
        }

        return notes
    }
}
#endif

struct RhythmRecognitionPipelineBounds: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
    }
}

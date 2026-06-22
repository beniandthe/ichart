import CoreGraphics
import Foundation

#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
#endif

struct RhythmRecognitionPipelinePreview: Codable, Equatable, Hashable {
    struct Primitive: Codable, Equatable, Hashable {
        var strokeIndex: Int
        var kind: String
        var bounds: RhythmRecognitionPipelineBounds
    }

    struct SymbolGroup: Codable, Equatable, Hashable {
        var index: Int
        var strokeIndices: [Int]
        var primitiveKinds: [String]
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
    var primitiveCounts: [String: Int]
    var primitives: [Primitive]
    var symbolGroups: [SymbolGroup]
    var decision: String
    var route: String
    var selectedValues: [RhythmValue]
    var naturalUnits: Int?
    var targetUnits: Int?
    var reasoningPaths: [ReasoningPath]
    var notes: [String]

    var statusText: String {
        let primitiveText = primitiveCounts
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

        return "\(strokeCount) strokes; \(primitiveText.isEmpty ? "no primitives" : primitiveText); \(valueText)\(noteText)"
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
        meter _: Meter,
        drawingFrame: CGRect,
        decision: RhythmRecognitionDecision,
        decisionText: String,
        routeText: String
    ) -> RhythmRecognitionPipelinePreview {
        let strokeObservations = RhythmicNotationQuantizer.strokeObservations(from: drawing)
        let orderedStrokes = strokeObservations.sortedByVisualPosition()
        let primitives = RhythmicNotationQuantizer.rhythmInkPrimitives(
            from: strokeObservations,
            drawingFrame: drawingFrame
        )
        let primitiveCounts = primitives.reduce(into: [String: Int]()) { counts, primitive in
            counts[primitive.kind.rawValue, default: 0] += 1
        }
        let primitiveSummaries = primitives.map { primitive in
            Primitive(
                strokeIndex: primitive.strokeIndex,
                kind: primitive.kind.rawValue,
                bounds: RhythmRecognitionPipelineBounds(primitive.bounds)
            )
        }
        let symbolGroups = RhythmicNotationQuantizer.groupedSymbols(
            from: strokeObservations,
            drawingFrame: drawingFrame
        )
        let symbolSummaries = symbolGroups.enumerated().map { index, group in
            let strokeIndices = group.strokes.compactMap { orderedStrokes.firstIndex(of: $0) }
            let strokeIndexSet = Set(strokeIndices)
            return SymbolGroup(
                index: index,
                strokeIndices: strokeIndices,
                primitiveKinds: primitives
                    .filter { strokeIndexSet.contains($0.strokeIndex) }
                    .map(\.kind.rawValue),
                bounds: RhythmRecognitionPipelineBounds(group.bounds)
            )
        }

        return RhythmRecognitionPipelinePreview(
            strokeCount: strokeObservations.count,
            primitiveCounts: primitiveCounts,
            primitives: primitiveSummaries,
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
                primitives: primitives,
                symbolGroups: symbolSummaries,
                decision: decision
            )
        )
    }

    private static func notes(
        primitives: [RhythmInkPrimitive],
        symbolGroups: [SymbolGroup],
        decision: RhythmRecognitionDecision
    ) -> [String] {
        var notes: [String] = []
        let kinds = Set(primitives.map(\.kind))
        if kinds.contains(.restShape), kinds.contains(.notehead) {
            notes.append("rest and notehead evidence both present")
        }
        if symbolGroups.contains(where: { Set($0.primitiveKinds).contains("restShape") && Set($0.primitiveKinds).contains("notehead") }) {
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

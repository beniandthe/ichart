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

    struct GlyphClosureGroup: Codable, Equatable, Hashable {
        var index: Int
        var strokeIndices: [Int]
        var bounds: RhythmRecognitionPipelineBounds
        var isBeamed: Bool
        var closure: String
    }

    struct GlyphClosureLane: Codable, Equatable, Hashable {
        var name: String
        var status: String
        var values: [RhythmValue]
        var units: Int?
        var groups: [GlyphClosureGroup]
        var notes: [String]
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
    var glyphClosureLanes: [GlyphClosureLane]? = nil
    var notes: [String]

    var laneStatusText: String? {
        guard let glyphClosureLanes,
              !glyphClosureLanes.isEmpty else {
            return nil
        }

        return glyphClosureLanes
            .prefix(4)
            .map { lane in
                let valueText = lane.values.isEmpty
                    ? "noRead"
                    : lane.values.map(\.displayText).joined(separator: "+")
                return "\(lane.name)=\(lane.status):\(valueText)"
            }
            .joined(separator: " | ")
    }

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
        let laneText = laneStatusText.map { " • lanes \($0)" } ?? ""

        return "\(strokeCount) strokes; \(primitiveText.isEmpty ? "no primitives" : primitiveText); \(valueText)\(noteText)\(laneText)"
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
            glyphClosureLanes: glyphClosureLanes(
                strokeObservations: strokeObservations,
                orderedStrokes: orderedStrokes,
                meter: meter,
                drawingFrame: drawingFrame
            ),
            notes: notes(
                primitives: primitives,
                symbolGroups: symbolSummaries,
                decision: decision
            )
        )
    }

    private enum GlyphClosureMode: String {
        case current
        case spacingOnly
        case beamOpen
        case beamOpenConservative
    }

    private static func glyphClosureLanes(
        strokeObservations: [StrokeObservation],
        orderedStrokes: [StrokeObservation],
        meter: Meter,
        drawingFrame: CGRect
    ) -> [GlyphClosureLane] {
        [
            glyphClosureLane(
                name: "current",
                mode: .current,
                strokeObservations: strokeObservations,
                orderedStrokes: orderedStrokes,
                meter: meter,
                drawingFrame: drawingFrame
            ),
            glyphClosureLane(
                name: "spacingOnly",
                mode: .spacingOnly,
                strokeObservations: strokeObservations,
                orderedStrokes: orderedStrokes,
                meter: meter,
                drawingFrame: drawingFrame
            ),
            glyphClosureLane(
                name: "beamOpen",
                mode: .beamOpen,
                strokeObservations: strokeObservations,
                orderedStrokes: orderedStrokes,
                meter: meter,
                drawingFrame: drawingFrame
            ),
            glyphClosureLane(
                name: "beamOpenConservative",
                mode: .beamOpenConservative,
                strokeObservations: strokeObservations,
                orderedStrokes: orderedStrokes,
                meter: meter,
                drawingFrame: drawingFrame
            )
        ]
    }

    private static func glyphClosureLane(
        name: String,
        mode: GlyphClosureMode,
        strokeObservations: [StrokeObservation],
        orderedStrokes: [StrokeObservation],
        meter: Meter,
        drawingFrame: CGRect
    ) -> GlyphClosureLane {
        let groups: [SymbolObservation]
        switch mode {
        case .current:
            groups = RhythmicNotationQuantizer.groupedSymbols(
                from: strokeObservations,
                drawingFrame: drawingFrame
            )
        case .spacingOnly, .beamOpen, .beamOpenConservative:
            groups = glyphClosureGroups(
                from: orderedStrokes,
                mode: mode,
                drawingFrame: drawingFrame
            ).map(SymbolObservation.init(strokes:))
        }

        let candidateGroups = groups.flatMap { group in
            diagnosticCandidateGroups(for: group, drawingFrame: drawingFrame)
        }
        let path = RhythmicNotationQuantizer.bestNaturalPath(from: candidateGroups, meter: meter)
        let targetUnits = RhythmicNotationQuantizer.rhythmUnits(
            forWholeNotes: meter.measureLengthInWholeNotes
        )
        let groupSummaries = groups.enumerated().map { index, group in
            GlyphClosureGroup(
                index: index,
                strokeIndices: group.strokes.compactMap { orderedStrokes.firstIndex(of: $0) },
                bounds: RhythmRecognitionPipelineBounds(group.bounds),
                isBeamed: group.hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame),
                closure: closureSummary(for: group, mode: mode, drawingFrame: drawingFrame)
            )
        }

        let status: String
        if candidateGroups.isEmpty {
            status = "noRead"
        } else if path.units == targetUnits {
            status = "exact"
        } else if path.units < targetUnits {
            status = "underfilled"
        } else {
            status = "overflow"
        }

        return GlyphClosureLane(
            name: name,
            status: status,
            values: path.values,
            units: candidateGroups.isEmpty ? nil : path.units,
            groups: groupSummaries,
            notes: notesForLane(
                mode: mode,
                groups: groups,
                candidateGroupCount: candidateGroups.count,
                drawingFrame: drawingFrame
            )
        )
    }

    private static func glyphClosureGroups(
        from orderedStrokes: [StrokeObservation],
        mode: GlyphClosureMode,
        drawingFrame: CGRect
    ) -> [[StrokeObservation]] {
        guard !orderedStrokes.isEmpty else {
            return []
        }

        let sceneBounds = orderedStrokes.nonEmptyBounds ?? drawingFrame
        let separationGap = mode == .beamOpen ? drawingFrame.width * 0.12 : drawingFrame.width * 0.075
        let attachmentGap = mode == .beamOpen ? drawingFrame.width * 0.07 : drawingFrame.width * 0.04
        let sortedStrokes = orderedStrokes.sortedByVisualPosition()
        var groups: [[StrokeObservation]] = []
        var current: [StrokeObservation] = []

        func closeCurrent() {
            guard !current.isEmpty else {
                return
            }
            groups.append(current)
            current = []
        }

        for stroke in sortedStrokes {
            guard !current.isEmpty,
                  let currentBounds = current.nonEmptyBounds else {
                current = [stroke]
                continue
            }

            let candidate = current + [stroke]
            let candidateSymbol = SymbolObservation(strokes: candidate)
            let currentIsBeamed = SymbolObservation(strokes: current)
                .hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame)
            let candidateIsBeamed = candidateSymbol
                .hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame)
            let horizontalGap = stroke.bounds.minX - currentBounds.maxX
            let verticalOverlap = stroke.bounds.minY <= currentBounds.maxY + sceneBounds.height * 0.28
                && stroke.bounds.maxY >= currentBounds.minY - sceneBounds.height * 0.28
            let nearCurrent = horizontalGap <= attachmentGap && verticalOverlap
            let separatedAway = horizontalGap > separationGap && !candidateIsBeamed
            let canMutateOpenBeam = mode != .spacingOnly
                && (currentIsBeamed || candidateIsBeamed || stroke.looksLikeVisualBeamSeed(in: sceneBounds))
                && horizontalGap <= separationGap
                && stroke.bounds.minY <= currentBounds.maxY + sceneBounds.height * 0.34
                && stroke.bounds.maxY >= currentBounds.minY - sceneBounds.height * 0.34

            if canMutateOpenBeam || (nearCurrent && !separatedAway) {
                current.append(stroke)
            } else {
                closeCurrent()
                current = [stroke]
            }
        }

        closeCurrent()
        return groups
            .mergingLooseDots(drawingFrame: drawingFrame)
            .reattachingLeadingNoteheadsToFollowingBeams(drawingFrame: drawingFrame)
    }

    private static func diagnosticCandidateGroups(
        for group: SymbolObservation,
        drawingFrame: CGRect
    ) -> [[RhythmCandidate]] {
        let beamedCount = group.beamedEighthNoteCount(drawingFrame: drawingFrame)
        if beamedCount >= 2 {
            return (0..<beamedCount).map { _ in
                [RhythmCandidate(value: .eighth, score: 0.0)]
            }
        }

        let candidates = RhythmicNotationQuantizer.classifyCandidates(
            group,
            drawingFrame: drawingFrame
        )
        return candidates.isEmpty ? [] : [candidates]
    }

    private static func closureSummary(
        for group: SymbolObservation,
        mode: GlyphClosureMode,
        drawingFrame: CGRect
    ) -> String {
        if group.hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame) {
            return mode == .spacingOnly ? "beamPresentButSpacingClosed" : "beamHeldOpenUntilSeparation"
        }
        return "spacingClosed"
    }

    private static func notesForLane(
        mode: GlyphClosureMode,
        groups: [SymbolObservation],
        candidateGroupCount: Int,
        drawingFrame: CGRect
    ) -> [String] {
        var notes: [String] = []
        switch mode {
        case .current:
            notes.append("production grouping surface")
        case .spacingOnly:
            notes.append("spaces close glyphs unless tiny marks attach")
        case .beamOpen:
            notes.append("beam evidence keeps glyph open through later connected ink")
        case .beamOpenConservative:
            notes.append("beam-open lane with earlier separation close")
        }
        if groups.contains(where: { $0.strokes.count >= 3 && $0.hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame) }) {
            notes.append("beamed group candidate present")
        }
        if candidateGroupCount == 0 {
            notes.append("no candidate values from this grouping")
        }
        return notes
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

#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation

/// Detects structure only. A label is retained as source ink until the user
/// supplies its exact text in review; no chord or language recognizer is used.
enum ChordDraftEndingRecognizer {
    private struct Roof {
        var index: Int
        var left: CGFloat
        var right: CGFloat
        var y: CGFloat
        var rightY: CGFloat
        var attachedLeftDepth: CGFloat
        var attachedRightDepth: CGFloat
    }

    static func recognize(
        strokes: [InkStroke], chordFrame: CGRect, pageLayout: LeadSheetPageLayout?
    ) -> ChordDraftEndingRecognition {
        guard let pageLayout, chordFrame.minX.isFinite, chordFrame.minY.isFinite,
              strokes.allSatisfy(hasFiniteGeometry) else {
            return ChordDraftEndingRecognition(endings: [], strokeIndices: [])
        }
        var candidates = [DraftEnding]()
        for system in pageLayout.systems {
            guard let lane = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system, paperFrame: pageLayout.paperFrame(for: system)), lane.height > 0 else { continue }
            for (index, stroke) in strokes.enumerated() {
                guard let roof = roof(in: stroke, index: index, lane: lane, origin: chordFrame.origin),
                      let ending = ending(for: roof, strokes: strokes, lane: lane,
                        system: system, origin: chordFrame.origin, pageLayout: pageLayout) else { continue }
                candidates.append(ending)
            }
        }
        // Overlapping interpretations are not resolved by input order.
        let counts = candidates.reduce(into: [Int: Int]()) { counts, ending in
            for index in ending.sourceStrokeIndices { counts[index, default: 0] += 1 }
        }
        let accepted = candidates.filter { candidate in
            candidate.sourceStrokeIndices.allSatisfy { counts[$0] == 1 }
        }.sorted { $0.visualOrder < $1.visualOrder }
        return ChordDraftEndingRecognition(endings: accepted,
            strokeIndices: accepted.reduce(into: Set<Int>()) { $0.formUnion($1.sourceStrokeIndices) })
    }

    /// Ending hooks and labels cannot become barlines or chord stems. The
    /// returned indices remain in the caller's original source index space.
    static func recognizeBarlinesExcludingEndings(
        strokes: [InkStroke], chordFrame: CGRect, pageLayout: LeadSheetPageLayout?
    ) -> ChordDraftBarlineRecognition {
        let endings = recognize(strokes: strokes, chordFrame: chordFrame, pageLayout: pageLayout)
        let remaining = strokes.indices.filter { !endings.strokeIndices.contains($0) }
        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: remaining.map { strokes[$0] }, chordFrame: chordFrame, pageLayout: pageLayout)
        let barlines = recognition.barlines.map { draft -> DraftBarline in
            var result = draft
            result.sourceStrokeIndex = draft.sourceStrokeIndex.map { remaining[$0] }
            result.sourceStrokeIndices = Set(draft.ownedSourceStrokeIndices.map { remaining[$0] })
            return result
        }
        return ChordDraftBarlineRecognition(barlines: barlines,
            strokeIndices: Set(recognition.strokeIndices.map { remaining[$0] }))
    }

    private static func roof(in stroke: InkStroke, index: Int, lane: CGRect, origin: CGPoint) -> Roof? {
        let bounds = stroke.bounds.cgRect.offsetBy(dx: origin.x, dy: origin.y)
        let tolerance = max(3, lane.height * 0.055)
        let legTolerance = max(5, lane.height * 0.075)
        let minimumHook = max(5, lane.height * 0.08)
        guard bounds.width >= max(44, lane.height * 0.8),
              bounds.minX >= lane.minX - 12, bounds.maxX <= lane.maxX + 12,
              bounds.minY >= lane.minY - 6,
              bounds.maxY <= lane.maxY + 3 else { return nil }
        // Sample the roof subpath so sparse and dense PencilKit paths have
        // the same fit. Exclude only the endpoint-leg neighborhoods: removing
        // a fixed share of a long roof would bias a wave's fitted slope and
        // extrapolate its otherwise valid endpoints outside the tolerance.
        let original = stroke.points.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
        var points = [CGPoint]()
        for (a, b) in zip(original, original.dropFirst()) {
            let distance = hypot(b.x - a.x, b.y - a.y)
            guard distance.isFinite else { return nil }
            let count = max(1, Int(min(256, ceil(distance / max(3, lane.height * 0.04)))))
            for index in 0..<count {
                let fraction = CGFloat(index) / CGFloat(count)
                points.append(CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction))
            }
        }
        if let last = original.last { points.append(last) }
        let left = bounds.minX, right = bounds.maxX
        let roofInset = min(bounds.width * 0.12, legTolerance + 1)
        let central = points.filter { $0.x >= left + roofInset && $0.x <= right - roofInset }
        guard central.count >= 2 else { return nil }
        let meanX = central.map(\.x).reduce(0, +) / CGFloat(central.count)
        let meanY = central.map(\.y).reduce(0, +) / CGFloat(central.count)
        let variance = central.reduce(CGFloat(0)) { $0 + pow($1.x - meanX, 2) }
        guard variance > 1 else { return nil }
        let slope = central.reduce(CGFloat(0)) { $0 + ($1.x - meanX) * ($1.y - meanY) } / variance
        guard abs(slope) <= 0.12 else { return nil }
        func roofY(at x: CGFloat) -> CGFloat { meanY + slope * (x - meanX) }
        guard central.allSatisfy({ abs($0.y - roofY(at: $0.x)) <= tolerance }),
              min(roofY(at: left), roofY(at: right)) >= lane.minY - 6,
              max(roofY(at: left), roofY(at: right)) <= lane.minY + lane.height * 0.34 else { return nil }
        func fitsBracket(_ point: CGPoint) -> Bool {
            abs(point.y - roofY(at: point.x)) <= tolerance
                || (point.y >= roofY(at: point.x) - tolerance
                    && (abs(point.x - left) <= legTolerance || abs(point.x - right) <= legTolerance))
        }
        guard points.allSatisfy(fitsBracket), zip(points, points.dropFirst()).allSatisfy({ a, b in
            // Endpoints alone would accept a diagonal chord body crossing the
            // empty space inside the bracket.
            [CGFloat(0.25), 0.5, 0.75].allSatisfy { fraction in
                fitsBracket(CGPoint(x: a.x + (b.x - a.x) * fraction,
                    y: a.y + (b.y - a.y) * fraction))
            }
        }) else { return nil }
        let leftDepth = points.filter { abs($0.x - left) <= legTolerance }.map { $0.y - roofY(at: left) }.max() ?? 0
        let rightDepth = points.filter { abs($0.x - right) <= legTolerance }.map { $0.y - roofY(at: right) }.max() ?? 0
        let usedDepth = (leftDepth >= minimumHook ? leftDepth : 0) + (rightDepth >= minimumHook ? rightDepth : 0)
        let expectedLength = right - left + usedDepth
        let length = pathLength(of: stroke)
        guard length >= Double((right - left) * 0.92),
              length <= Double(expectedLength * 1.38 + tolerance * 2) else { return nil }
        return Roof(index: index, left: left, right: right, y: roofY(at: left), rightY: roofY(at: right),
            attachedLeftDepth: leftDepth >= minimumHook ? leftDepth : 0,
            attachedRightDepth: rightDepth >= minimumHook ? rightDepth : 0)
    }

    private static func ending(
        for roof: Roof, strokes: [InkStroke], lane: CGRect, system: LeadSheetSystemLayout,
        origin: CGPoint, pageLayout: LeadSheetPageLayout
    ) -> DraftEnding? {
        let tolerance = max(3.5, lane.height * 0.055)
        let minimumHook = max(5, lane.height * 0.08)
        var members: Set<Int> = [roof.index]
        let fullHeightBars = strokes.indices.filter { $0 != roof.index && ChordDraftBarlineRecognizer.candidate(
            for: strokes[$0], chordFrame: CGRect(origin: origin, size: .zero), pageLayout: pageLayout) != nil }
        let existingAnchors = renderedBoundaryRanges(system: system, pageLayout: pageLayout)
        let drawnAnchors = fullHeightBars.compactMap { index -> ClosedRange<CGFloat>? in
            let bounds = strokes[index].bounds.cgRect.offsetBy(dx: origin.x, dy: origin.y)
            guard bounds.minY <= max(roof.y, roof.rightY) + 18 else { return nil }
            return bounds.minX...bounds.maxX
        }
        let hasLeftAnchor = hasUniqueAnchor(at: roof.left, ranges: existingAnchors + drawnAnchors)
        // A connected full-height leg owns the whole original stroke only
        // when that barline already exists. New split effects cannot share a
        // source index with an ending or silently drop a leg's semantics.
        guard roof.attachedLeftDepth <= lane.height * 0.48
                || hasUniqueAnchor(at: roof.left, ranges: existingAnchors),
              roof.attachedRightDepth <= lane.height * 0.48
                || hasUniqueAnchor(at: roof.right, ranges: existingAnchors) else { return nil }
        func detachedHooks(at x: CGFloat, roofY: CGFloat) -> [Int] {
            strokes.indices.filter { index in
                guard index != roof.index else { return false }
                let stroke = strokes[index]
                let bounds = stroke.bounds.cgRect.offsetBy(dx: origin.x, dy: origin.y)
                return bounds.height >= minimumHook
                    && bounds.height <= lane.height * 0.48
                    && bounds.width <= tolerance
                    && abs(bounds.midX - x) <= tolerance
                    && abs(bounds.minY - roofY) <= max(8, tolerance)
                    && pathLength(of: stroke) <= Double(bounds.height * 1.3 + tolerance)
            }
        }
        let left = detachedHooks(at: roof.left, roofY: roof.y)
        let right = detachedHooks(at: roof.right, roofY: roof.rightY)
        guard left.count <= 1, right.count <= 1,
              !(roof.attachedLeftDepth > 0 && !left.isEmpty),
              !(roof.attachedRightDepth > 0 && !right.isEmpty),
              roof.attachedLeftDepth > 0 || !left.isEmpty || hasLeftAnchor else { return nil }
        members.formUnion(left)
        members.formUnion(right)

        // Full-height written boundaries can meet or cross a bracket roof.
        // They remain separate structural sources and are not part of the
        // ending's label ownership.
        let otherIndices = strokes.indices.filter { !members.contains($0) }
        let boundaries = ChordDraftBarlineRecognizer.recognize(
            strokes: otherIndices.map { strokes[$0] },
            chordFrame: CGRect(origin: origin, size: .zero), pageLayout: pageLayout)
        var structuralIndices = Set(boundaries.strokeIndices.map { otherIndices[$0] })
        for index in fullHeightBars {
            structuralIndices.insert(index)
        }

        // Labels belong wholly below the roof, away from its hooks and above
        // the normal chord body. A stroke crossing that boundary is ambiguous.
        let labelTop = max(roof.y, roof.rightY) + max(3.5, lane.height * 0.055)
        let labelBottom = min(lane.minY + lane.height * 0.59, min(roof.y, roof.rightY) + max(18, lane.height * 0.36))
        let labelLeft = roof.left + max(3, tolerance)
        let labelRight = roof.right - max(3, tolerance)
        guard labelBottom > labelTop else { return nil }
        for index in strokes.indices where !members.contains(index) {
            if structuralIndices.contains(index) { continue }
            let bounds = strokes[index].bounds.cgRect.offsetBy(dx: origin.x, dy: origin.y)
            let fullyEnclosed = bounds.minX >= labelLeft && bounds.maxX <= labelRight
                && bounds.minY >= labelTop && bounds.maxY <= labelBottom
            if fullyEnclosed {
                members.insert(index)
                continue
            }
            let overlapsHeader = bounds.maxX >= roof.left - tolerance && bounds.minX <= roof.right + tolerance
                && bounds.maxY >= min(roof.y, roof.rightY) - tolerance && bounds.minY <= labelBottom
            if overlapsHeader { return nil }
        }
        guard let start = endpoint(at: roof.left, lane: lane, system: system, pageLayout: pageLayout),
              let end = endpoint(at: roof.right, lane: lane, system: system, pageLayout: pageLayout) else { return nil }
        var result = DraftEnding(start: start, end: end, layoutPageSize: pageLayout.pageBounds.size,
            sourceStrokeIndices: members, sourceStrokeGeometry: members.sorted().map { strokes[$0] },
            endStyle: roof.attachedRightDepth > 0 || !right.isEmpty ? .closed : .open)
        let reviewMinY = min(roof.y, roof.rightY) - tolerance - 18
        let reviewMaxY = min(max(roof.y, roof.rightY) + tolerance + 2, labelTop - 0.5)
        result.roofReviewFrame = CGRect(x: roof.left - 3 - origin.x, y: reviewMinY - origin.y,
            width: roof.right - roof.left + 6, height: max(1, reviewMaxY - reviewMinY))
        return result
    }

    private static func renderedBoundaryRanges(
        system: LeadSheetSystemLayout, pageLayout: LeadSheetPageLayout
    ) -> [ClosedRange<CGFloat>] {
        var result = [ClosedRange<CGFloat>]()
        for measure in system.measures where measure.sourceMeasureID != nil || measure.chordInkTargetMeasureID != nil {
            let display = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(measure,
                in: system, paperFrame: pageLayout.paperFrame(for: system), layoutStyle: system.layoutStyle)
            let frame = system.layoutStyle == .rhythmSectionSheet ? display.staffFrame : display.frame
            result.append(frame.minX...frame.minX)
            result.append(frame.maxX...frame.maxX)
            for marker in measure.repeatMarkerLayouts {
                let rendered = LeadSheetSimpleChordTerminalBarlineGeometry.renderedRepeatMarkerFrame(marker,
                    after: measure, in: system, paperFrame: pageLayout.paperFrame(for: system), layoutStyle: system.layoutStyle)
                result.append(rendered.minX...rendered.maxX)
            }
        }
        return result
    }

    private static func hasUniqueAnchor(at x: CGFloat, ranges: [ClosedRange<CGFloat>]) -> Bool {
        // Adjacent aliases of one printed double/repeat line form one spatial
        // anchor. Musical membership is independently resolved during review.
        var clusters = [ClosedRange<CGFloat>]()
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = clusters.last, range.lowerBound <= last.upperBound + 4 {
                clusters[clusters.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else { clusters.append(range) }
        }
        let distances = clusters.map { max($0.lowerBound - x, x - $0.upperBound, 0) }.sorted()
        guard let nearest = distances.first, nearest <= 18 else { return false }
        return distances.count == 1 || distances[1] - nearest >= 4
    }

    private static func endpoint(
        at x: CGFloat, lane: CGRect, system: LeadSheetSystemLayout, pageLayout: LeadSheetPageLayout
    ) -> DraftEndingEndpoint? {
        let measures = system.measures.filter { $0.chordInkTargetMeasureID != nil || $0.sourceMeasureID != nil }
        guard let source = measures.min(by: { left, right in
            distance(from: x, to: left.chordWritingFrame) < distance(from: x, to: right.chordWritingFrame)
        }), let measureID = source.chordInkTargetMeasureID ?? source.sourceMeasureID else { return nil }
        let display = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(source,
            in: system, paperFrame: pageLayout.paperFrame(for: system), layoutStyle: system.layoutStyle)
        let frame = system.layoutStyle == .rhythmSectionSheet ? display.staffFrame : display.frame
        return DraftEndingEndpoint(measureID: measureID, measureIndex: source.index,
            fraction: Double((x - frame.minX) / max(1, frame.width)),
            laneLocation: ChordInkDraftLaneLocation(systemIndex: system.index,
                fraction: Double((x - lane.minX) / max(1, lane.width))))
    }

    private static func distance(from x: CGFloat, to frame: CGRect) -> CGFloat {
        max(frame.minX - x, x - frame.maxX, 0)
    }

    private static func hasFiniteGeometry(_ stroke: InkStroke) -> Bool {
        !stroke.points.isEmpty && stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && [stroke.bounds.minX, stroke.bounds.minY, stroke.bounds.maxX, stroke.bounds.maxY].allSatisfy(\.isFinite)
            && stroke.bounds.maxX >= stroke.bounds.minX && stroke.bounds.maxY >= stroke.bounds.minY
    }

    private static func pathLength(of stroke: InkStroke) -> Double {
        zip(stroke.points, stroke.points.dropFirst()).reduce(0) { length, pair in
            length + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }
}

private extension InkBounds {
    var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}
#endif

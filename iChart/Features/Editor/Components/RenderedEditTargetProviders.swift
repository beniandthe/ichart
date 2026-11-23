#if canImport(UIKit)
import CoreGraphics
import Foundation

struct RenderedEditContext {
    var pageLayout: LeadSheetPageLayout
    var layoutStyle: ChartLayoutStyle
    var selection: RenderedEditSelectionState
    var committedChordBarlineMeasures: [LeadSheetMeasureLayout]
    var screenPointsPerDisplayedPoint: CGFloat
    var allowsUnselectedChordMove: Bool

    init(
        pageLayout: LeadSheetPageLayout,
        layoutStyle: ChartLayoutStyle = .leadSheet,
        selection: RenderedEditSelectionState = RenderedEditSelectionState(),
        committedChordBarlineMeasures: [LeadSheetMeasureLayout] = [],
        screenPointsPerDisplayedPoint: CGFloat = 1,
        allowsUnselectedChordMove: Bool = false
    ) {
        self.pageLayout = pageLayout
        self.layoutStyle = layoutStyle
        self.selection = selection
        self.committedChordBarlineMeasures = committedChordBarlineMeasures
        self.screenPointsPerDisplayedPoint = screenPointsPerDisplayedPoint
        self.allowsUnselectedChordMove = allowsUnselectedChordMove
    }
}

protocol RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget]
}

struct RenderedEditRouter {
    var providers: [any RenderedEditHitTargetProvider]

    init(providers: [any RenderedEditHitTargetProvider] = RenderedEditTargetProviderSet.renderedPageProviders) {
        self.providers = providers
    }

    func hitTargets(at location: CGPoint, in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        providers
            .flatMap { $0.hitTargets(in: context) }
            .filter { $0.contains(location) }
    }

    func topHitTarget(at location: CGPoint, in context: RenderedEditContext) -> RenderedEditHitTarget? {
        RenderedEditHitTarget.highestPriority(
            in: hitTargets(at: location, in: context),
            nearestTo: location
        )
    }

    func tapTarget(at location: CGPoint, in context: RenderedEditContext) -> RenderedEditHitTarget? {
        let tapCandidates = hitTargets(at: location, in: context)
            .filter { !$0.action.isMove && !$0.action.isResize }
        return RenderedEditSelectionPolicy.resolvedTapTarget(
            RenderedEditHitTarget.highestPriority(in: tapCandidates, nearestTo: location),
            selection: context.selection
        )
    }

    func dragTarget(at location: CGPoint, in context: RenderedEditContext) -> RenderedEditHitTarget? {
        let hits = hitTargets(at: location, in: context)
        // Starting on an explicit chord X is a tap intent, never a body drag
        // through the selected object's forgiving outer halo.
        if hits.contains(where: {
            if case .chord = $0.objectID { return $0.action.isDestructive }
            return false
        }) { return nil }
        let dragCandidates = hits
            .filter { $0.action.isMove || $0.action.isResize }
            .compactMap {
                RenderedEditSelectionPolicy.resolvedDragTarget(
                    $0,
                    selection: context.selection
                )
            }
        return RenderedEditHitTarget.highestPriority(
            in: dragCandidates,
            nearestTo: location
        )
    }
}

enum RenderedEditTargetProviderSet {
    static var renderedPageProviders: [any RenderedEditHitTargetProvider] {
        [
            CommittedChordBarlineRenderedEditHitTargetProvider(),
            CueTextRenderedEditHitTargetProvider(),
            RoadmapMarkerRenderedEditHitTargetProvider(),
            ChordRenderedEditHitTargetProvider(),
            RepeatSpanRenderedEditHitTargetProvider(),
            EndingSpanRenderedEditHitTargetProvider(),
            TimeSignatureRenderedEditHitTargetProvider(),
            MeasureRenderedEditHitTargetProvider(),
            HeaderRenderedEditHitTargetProvider()
        ]
    }
}

struct ChordRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        let protectedBodies = context.pageLayout.systems.flatMap(\.measures)
            .flatMap(\.chordLayouts)
            .map { LeadSheetChordEditOverlayGeometry.bodySelectionFrame(for: $0) }
        return context.pageLayout.systems.flatMap { system in
            system.measures.flatMap { measure in
                chordTargets(in: measure, selection: context.selection,
                    allowsUnselectedMove: context.allowsUnselectedChordMove,
                    protectedBodies: protectedBodies, canvasBounds: context.pageLayout.pageBounds,
                    screenPointsPerDisplayedPoint: context.screenPointsPerDisplayedPoint)
            }
        }
    }

    private func chordTargets(
        in measure: LeadSheetMeasureLayout,
        selection: RenderedEditSelectionState,
        allowsUnselectedMove: Bool,
        protectedBodies: [CGRect],
        canvasBounds: CGRect,
        screenPointsPerDisplayedPoint: CGFloat
    ) -> [RenderedEditHitTarget] {
        guard measure.sourceMeasureID != nil else {
            return []
        }

        return measure.chordLayouts.flatMap { chordLayout in
            let objectID = RenderedEditObjectID.chord(chordLayout.id)
            let selectionFrame = LeadSheetChordEditOverlayGeometry.bodySelectionFrame(for: chordLayout)
            let isSelected = selection.contains(objectID)
            var targets = [
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .select,
                    priority: .objectBodySelect,
                    frame: selectionFrame,
                    requiresSelection: false,
                    mutationRisk: .nonMutating
                ),
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .move,
                    priority: .objectBodyMove,
                    frame: selectionFrame,
                    requiresSelection: !allowsUnselectedMove,
                    mutationRisk: .visual
                )
            ]

            if isSelected {
                targets.append(RenderedEditHitTarget(objectID: objectID, action: .move,
                    priority: .selectedObjectMoveBody,
                    frame: LeadSheetChordEditOverlayGeometry.selectedMoveBodyFrame(for: chordLayout),
                    requiresSelection: true, mutationRisk: .visual))
            }

            guard selection.contains(objectID) else {
                return targets
            }

            let controlFrames = LeadSheetChordEditOverlayGeometry.controlFrames(for: chordLayout,
                within: canvasBounds, avoiding: protectedBodies,
                screenPointsPerDisplayedPoint: screenPointsPerDisplayedPoint)
            let controlOutset = LeadSheetChordEditOverlayGeometry.controlHitOutset / max(0.05, screenPointsPerDisplayedPoint)
            targets.append(
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .resizeLeading,
                    priority: .selectedObjectResizeHandle,
                    frame: LeadSheetChordEditOverlayGeometry.resizeHitFrame(for: controlFrames.leadingResize,
                        edge: .leading, screenPointsPerDisplayedPoint: screenPointsPerDisplayedPoint),
                    requiresSelection: true,
                    mutationRisk: .visual,
                    excludedFrames: protectedBodies
                )
            )
            targets.append(
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .delete,
                    priority: .selectedObjectDestructiveControl,
                    frame: controlFrames.delete.insetBy(dx: -controlOutset, dy: -controlOutset),
                    requiresSelection: true,
                    mutationRisk: .destructive,
                    excludedFrames: protectedBodies
                )
            )
            targets.append(
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .resizeTrailing,
                    priority: .selectedObjectResizeHandle,
                    frame: LeadSheetChordEditOverlayGeometry.resizeHitFrame(for: controlFrames.trailingResize,
                        edge: .trailing, screenPointsPerDisplayedPoint: screenPointsPerDisplayedPoint),
                    requiresSelection: true,
                    mutationRisk: .visual,
                    excludedFrames: protectedBodies
                )
            )

            return targets
        }
    }
}

struct CommittedChordBarlineRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        context.committedChordBarlineMeasures.flatMap { measure -> [RenderedEditHitTarget] in
            guard let measureID = measure.sourceMeasureID else {
                return []
            }
            guard !isTerminalTrailingBoundary(measure, in: context) else {
                return []
            }

            let objectID = RenderedEditObjectID.committedChordBarline(afterMeasureID: measureID)
            let lineFrame = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: measure, layoutStyle: context.layoutStyle)
                .insetBy(dx: 3, dy: 8)
            var targets = [
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .select,
                    priority: .objectBodySelect,
                    frame: lineFrame,
                    requiresSelection: false,
                    mutationRisk: .nonMutating
                )
            ]

            guard context.selection.contains(objectID) else {
                return targets
            }

            let controlFrames = LeadSheetCommittedChordBarlineOverlayGeometry.controlFrames(for: measure, layoutStyle: context.layoutStyle)
            targets.append(
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .delete,
                    priority: .selectedObjectDestructiveControl,
                    frame: controlFrames.delete.insetBy(
                        dx: -LeadSheetCommittedChordBarlineOverlayGeometry.deleteHitOutset,
                        dy: -LeadSheetCommittedChordBarlineOverlayGeometry.deleteHitOutset
                    ),
                    requiresSelection: true,
                    mutationRisk: .structural
                )
            )

            return targets
        }
    }

    private func isTerminalTrailingBoundary(
        _ measure: LeadSheetMeasureLayout,
        in context: RenderedEditContext
    ) -> Bool {
        guard context.layoutStyle == .simpleChordSheet else {
            return false
        }

        return context.pageLayout.systems.contains { system in
            system.measures.last?.id == measure.id
                && LeadSheetSimpleChordTerminalBarlineGeometry.usesTerminalBarlineAsTrailingBoundary(
                    for: system,
                    paperFrame: context.pageLayout.paperFrame(for: system),
                    layoutStyle: context.layoutStyle
                )
        }
    }
}

struct CueTextRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        let cues = context.pageLayout.systems.flatMap(\.measures).flatMap(\.cueTextLayouts)
        let glyphIndex = GlyphBandIndex(cues: cues)
        return cues.flatMap { cue in
            cueTextTargets(for: cue, selection: context.selection, glyphIndex: glyphIndex)
        }
    }

    private func cueTextTargets(
        for cueTextLayout: LeadSheetCueTextLayout,
        selection: RenderedEditSelectionState,
        glyphIndex: GlyphBandIndex
    ) -> [RenderedEditHitTarget] {
        let objectID = RenderedEditObjectID.cueText(cueTextLayout.id)
        let isSelected = selection.contains(objectID)
        let bodyHit = LeadSheetCueTextEditOverlayGeometry.editHitFrame(for: cueTextLayout)
        let controls = isSelected ? LeadSheetCueTextEditOverlayGeometry.controlFrames(for: cueTextLayout) : nil
        let hits = isSelected ? LeadSheetCueTextEditOverlayGeometry.controlHitFrames(for: cueTextLayout) : nil
        let controlHits = hits.map { [$0.edit, $0.shrink, $0.grow, $0.delete] } ?? []
        let hitBounds = controlHits.reduce(bodyHit) { $0.union($1) }
        let otherGlyphFrames = glyphIndex.frames(overlapping: hitBounds, excluding: cueTextLayout.id)
        var targets = [
            RenderedEditHitTarget(objectID: objectID, action: .select,
                priority: .objectBodySelect,
                frame: bodyHit,
                requiresSelection: false, mutationRisk: .nonMutating,
                excludedFrames: otherGlyphFrames),
            // A real glyph remains selectable even where two glyphs overlap;
            // only another cue's padded body yields to it.
            RenderedEditHitTarget(objectID: objectID, action: .select,
                priority: .objectBodySelect, frame: cueTextLayout.frame,
                requiresSelection: false, mutationRisk: .nonMutating),
            RenderedEditHitTarget(objectID: objectID, action: .move,
                priority: .selectedObjectMoveBody,
                frame: bodyHit,
                requiresSelection: true, mutationRisk: .visual,
                excludedFrames: otherGlyphFrames + controlHits)
        ]
        guard let controls, let hits else { return targets }

        // Retain the selected cue's visible move body over a chord beneath it.
        targets.append(RenderedEditHitTarget(objectID: objectID, action: .move,
            priority: .selectedObjectEditControl, frame: cueTextLayout.frame,
            requiresSelection: true, mutationRisk: .visual))

        func control(_ visible: CGRect, hit: CGRect, action: RenderedEditAction,
            priority: RenderedEditHitPriority, risk: RenderedEditMutationRisk) {
            // Padding yields to a neighboring cue's actual glyph. The visible
            // button itself keeps its explicit action where artwork overlaps.
            targets.append(RenderedEditHitTarget(objectID: objectID, action: action,
                priority: priority, frame: hit, requiresSelection: true,
                mutationRisk: risk, excludedFrames: otherGlyphFrames))
            targets.append(RenderedEditHitTarget(objectID: objectID, action: action,
                priority: priority, frame: visible, requiresSelection: true, mutationRisk: risk))
        }
        control(controls.edit, hit: hits.edit, action: .editText,
            priority: .selectedObjectEditControl, risk: .content)
        control(controls.shrink, hit: hits.shrink, action: .shrink,
            priority: .selectedObjectEditControl, risk: .visual)
        control(controls.grow, hit: hits.grow, action: .grow,
            priority: .selectedObjectEditControl, risk: .visual)
        control(controls.delete, hit: hits.delete, action: .delete,
            priority: .selectedObjectDestructiveControl, risk: .destructive)
        return targets
    }

    private struct GlyphBandIndex {
        private struct Glyph {
            let id: UUID
            let frame: CGRect
        }
        private var bands: [Int: [Glyph]] = [:]

        init(cues: [LeadSheetCueTextLayout]) {
            for cue in cues {
                let glyph = Glyph(id: cue.id, frame: cue.frame)
                for band in Self.bandNumbers(for: cue.frame) {
                    bands[band, default: []].append(glyph)
                }
            }
        }

        func frames(overlapping bounds: CGRect, excluding id: UUID) -> [CGRect] {
            var seen = Set<UUID>()
            return Self.bandNumbers(for: bounds).flatMap { bands[$0] ?? [] }.compactMap { glyph in
                guard glyph.id != id, seen.insert(glyph.id).inserted,
                      glyph.frame.intersects(bounds) else { return nil }
                return glyph.frame
            }
        }

        private static func bandNumbers(for frame: CGRect) -> [Int] {
            guard !frame.isEmpty,
                  let first = Int(exactly: floor(frame.minY / 96)),
                  let last = Int(exactly: floor(frame.maxY / 96)), first <= last else { return [] }
            return Array(first...last)
        }
    }
}

struct RoadmapMarkerRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        context.pageLayout.systems.flatMap { system in
            system.roadmapMarkerLayouts.flatMap { markerLayout in
                markerTargets(for: markerLayout, selection: context.selection)
            }
        }
    }

    private func markerTargets(
        for markerLayout: LeadSheetRoadmapMarkerLayout,
        selection: RenderedEditSelectionState
    ) -> [RenderedEditHitTarget] {
        let objectID = RenderedEditObjectID.roadmapMarker(markerLayout.id)
        var targets = [
            RenderedEditHitTarget(
                objectID: objectID,
                action: .select,
                priority: .objectBodySelect,
                frame: LeadSheetRoadmapMarkerEditOverlayGeometry.editHitFrame(for: markerLayout),
                requiresSelection: false,
                mutationRisk: .nonMutating
            ),
            RenderedEditHitTarget(
                objectID: objectID,
                action: .move,
                priority: .selectedObjectMoveBody,
                frame: LeadSheetRoadmapMarkerEditOverlayGeometry.editHitFrame(for: markerLayout),
                requiresSelection: true,
                mutationRisk: .visual
            )
        ]

        guard selection.contains(objectID) else {
            return targets
        }

        let controls = LeadSheetRoadmapMarkerEditOverlayGeometry.controlFrames(for: markerLayout)
        let controlOutset = LeadSheetRoadmapMarkerEditOverlayGeometry.controlHitOutset
        targets.append(
            RenderedEditHitTarget(
                objectID: objectID,
                action: .delete,
                priority: .selectedObjectDestructiveControl,
                frame: controls.delete.insetBy(dx: -controlOutset, dy: -controlOutset),
                requiresSelection: true,
                mutationRisk: .destructive
            )
        )

        return targets
    }
}

struct RepeatSpanRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        context.pageLayout.systems.flatMap { system in
            system.measures.flatMap { measure in
                measure.repeatMarkerLayouts.map { marker in
                    let renderedFrame = LeadSheetSimpleChordTerminalBarlineGeometry.renderedRepeatMarkerFrame(
                        marker,
                        after: measure,
                        in: system,
                        paperFrame: context.pageLayout.paperFrame(for: system),
                        layoutStyle: context.layoutStyle
                    )
                    return RenderedEditHitTarget(
                        objectID: .repeatSpan(marker.roadmapObjectID),
                        action: .openInspector,
                        priority: .objectBodySelect,
                        frame: renderedFrame.insetBy(dx: -8, dy: -8),
                        requiresSelection: false,
                        mutationRisk: .nonMutating
                    )
                }
            }
        }
    }
}

struct EndingSpanRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        var targets = context.pageLayout.systems.flatMap { system in
            system.endingLayouts.map { ending in
                let selected = context.selection.contains(.endingSpan(ending.roadmapObjectID))
                return RenderedEditHitTarget(
                    objectID: .endingSpan(ending.roadmapObjectID),
                    action: selected ? .openInspector : .select,
                    priority: .objectBodySelect,
                    frame: ending.frame.insetBy(dx: -6, dy: -8),
                    requiresSelection: selected,
                    mutationRisk: .nonMutating
                )
            }
        }
        guard case .endingSpan(let endingID) = context.selection.selectedObjectID else { return targets }
        for controls in LeadSheetEndingEditOverlay.controlFrames(for: endingID, in: context.pageLayout,
            screenPointsPerDisplayedPoint: context.screenPointsPerDisplayedPoint) {
            func control(_ frame: CGRect, action: RenderedEditAction, priority: RenderedEditHitPriority) {
                targets.append(RenderedEditHitTarget(objectID: .endingSpan(endingID), action: action,
                    priority: priority, frame: frame, requiresSelection: true, mutationRisk: .structural))
                // A tap on a visible drag control keeps its selection instead
                // of activating a chart object painted beneath the chip.
                targets.append(RenderedEditHitTarget(objectID: .endingSpan(endingID), action: .select,
                    priority: priority, frame: frame, requiresSelection: true, mutationRisk: .nonMutating))
            }
            control(controls.moveHandle, action: .move, priority: .selectedObjectEditControl)
            if let length = controls.lengthenHandle {
                control(length, action: .resizeTrailing, priority: .selectedObjectResizeHandle)
            }
        }
        return targets
    }
}

struct TimeSignatureRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        context.pageLayout.systems.flatMap { system in
            var targets: [RenderedEditHitTarget] = []
            if let timeSignatureFrame = system.timeSignatureFrame,
               let firstMeasureID = system.measures.first?.sourceMeasureID {
                targets.append(
                    timeSignatureTarget(
                        measureID: firstMeasureID,
                        frame: timeSignatureFrame
                    )
                )
            }

            targets.append(
                contentsOf: system.measures.compactMap { measure in
                    guard let measureID = measure.sourceMeasureID,
                          let meterChangeFrame = measure.meterChangeFrame else {
                        return nil
                    }

                    return timeSignatureTarget(
                        measureID: measureID,
                        frame: meterChangeFrame
                    )
                }
            )
            return targets
        }
    }

    private func timeSignatureTarget(measureID: UUID, frame: CGRect) -> RenderedEditHitTarget {
        RenderedEditHitTarget(
            objectID: .timeSignatureChange(afterMeasureID: measureID),
            action: .openInspector,
            priority: .objectBodySelect,
            frame: frame.insetBy(dx: -8, dy: -8),
            requiresSelection: false,
            mutationRisk: .nonMutating
        )
    }
}

struct MeasureRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        context.pageLayout.systems.flatMap { system in
            system.measures.flatMap { measure -> [RenderedEditHitTarget] in
                guard let measureID = measure.sourceMeasureID else {
                    return []
                }

                let renderedMeasure = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                    measure,
                    in: system,
                    paperFrame: context.pageLayout.paperFrame(for: system),
                    layoutStyle: context.layoutStyle
                )
                let displayMeasure = LeadSheetMeasureResizeGeometry.editableMeasureLayout(
                    renderedMeasure,
                    layoutStyle: context.layoutStyle
                )
                let objectID = RenderedEditObjectID.measure(measureID)
                var targets = [
                    RenderedEditHitTarget(
                        objectID: objectID,
                        action: .select,
                        priority: .measureSelect,
                        frame: displayMeasure.frame.insetBy(dx: -6, dy: -6),
                        requiresSelection: false,
                        mutationRisk: .nonMutating
                    )
                ]

                guard context.selection.contains(objectID) else {
                    return targets
                }

                let handles = LeadSheetMeasureResizeGeometry.handleFrames(for: displayMeasure)
                let touchInsetX: CGFloat = -12
                let touchInsetY: CGFloat = -10
                targets.append(
                    RenderedEditHitTarget(
                        objectID: objectID,
                        action: .resizeLeft,
                        priority: .selectedObjectResizeHandle,
                        frame: handles.left.insetBy(dx: touchInsetX, dy: touchInsetY),
                        requiresSelection: true,
                        mutationRisk: .visual
                    )
                )
                targets.append(
                    RenderedEditHitTarget(
                        objectID: objectID,
                        action: .resizeRight,
                        priority: .selectedObjectResizeHandle,
                        frame: handles.right.insetBy(dx: touchInsetX, dy: touchInsetY),
                        requiresSelection: true,
                        mutationRisk: .visual
                    )
                )

                return targets
            }
        }
    }
}

struct HeaderRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        [
            RenderedEditHitTarget(
                objectID: .header,
                action: .openInspector,
                priority: .objectBodySelect,
                frame: context.pageLayout.header.handwrittenFrame.insetBy(dx: -12, dy: -10),
                requiresSelection: false,
                mutationRisk: .nonMutating
            )
        ]
    }
}
#endif

#if canImport(UIKit)
import CoreGraphics
import Foundation

struct RenderedEditContext {
    var pageLayout: LeadSheetPageLayout
    var selection: RenderedEditSelectionState
    var committedChordBarlineMeasures: [LeadSheetMeasureLayout]

    init(
        pageLayout: LeadSheetPageLayout,
        selection: RenderedEditSelectionState = RenderedEditSelectionState(),
        committedChordBarlineMeasures: [LeadSheetMeasureLayout] = []
    ) {
        self.pageLayout = pageLayout
        self.selection = selection
        self.committedChordBarlineMeasures = committedChordBarlineMeasures
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
            .filter { $0.frame.contains(location) }
    }

    func topHitTarget(at location: CGPoint, in context: RenderedEditContext) -> RenderedEditHitTarget? {
        RenderedEditHitTarget.highestPriority(in: hitTargets(at: location, in: context))
    }

    func tapTarget(at location: CGPoint, in context: RenderedEditContext) -> RenderedEditHitTarget? {
        let tapCandidates = hitTargets(at: location, in: context)
            .filter { !$0.action.isMove && !$0.action.isResize }
        return RenderedEditSelectionPolicy.resolvedTapTarget(
            RenderedEditHitTarget.highestPriority(in: tapCandidates),
            selection: context.selection
        )
    }

    func dragTarget(at location: CGPoint, in context: RenderedEditContext) -> RenderedEditHitTarget? {
        let dragCandidates = hitTargets(at: location, in: context)
            .filter { $0.action.isMove || $0.action.isResize }
        return RenderedEditSelectionPolicy.resolvedDragTarget(
            RenderedEditHitTarget.highestPriority(in: dragCandidates),
            selection: context.selection
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
        context.pageLayout.systems.flatMap { system in
            system.measures.flatMap { measure in
                chordTargets(in: measure, selection: context.selection)
            }
        }
    }

    private func chordTargets(
        in measure: LeadSheetMeasureLayout,
        selection: RenderedEditSelectionState
    ) -> [RenderedEditHitTarget] {
        guard measure.sourceMeasureID != nil else {
            return []
        }

        return measure.chordLayouts.flatMap { chordLayout in
            let objectID = RenderedEditObjectID.chord(chordLayout.id)
            let editFrame = LeadSheetChordEditOverlayGeometry.editFrame(for: chordLayout)
            let bodyFrame = editFrame.insetBy(dx: -8, dy: -8)
            var targets = [
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .select,
                    priority: .objectBodySelect,
                    frame: bodyFrame,
                    requiresSelection: false,
                    mutationRisk: .nonMutating
                ),
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .move,
                    priority: .selectedObjectMoveBody,
                    frame: bodyFrame,
                    requiresSelection: true,
                    mutationRisk: .visual
                )
            ]

            guard selection.contains(objectID) else {
                return targets
            }

            let controlFrames = LeadSheetChordEditOverlayGeometry.controlFrames(for: chordLayout)
            let controlOutset = LeadSheetChordEditOverlayGeometry.controlHitOutset
            targets.append(
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .delete,
                    priority: .selectedObjectDestructiveControl,
                    frame: controlFrames.delete.insetBy(dx: -controlOutset, dy: -controlOutset),
                    requiresSelection: true,
                    mutationRisk: .destructive
                )
            )
            targets.append(
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .resizeLeading,
                    priority: .selectedObjectResizeHandle,
                    frame: controlFrames.leadingResize.insetBy(dx: -controlOutset, dy: -controlOutset),
                    requiresSelection: true,
                    mutationRisk: .visual
                )
            )
            targets.append(
                RenderedEditHitTarget(
                    objectID: objectID,
                    action: .resizeTrailing,
                    priority: .selectedObjectResizeHandle,
                    frame: controlFrames.trailingResize.insetBy(dx: -controlOutset, dy: -controlOutset),
                    requiresSelection: true,
                    mutationRisk: .visual
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

            let objectID = RenderedEditObjectID.committedChordBarline(afterMeasureID: measureID)
            let lineFrame = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: measure)
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

            let controlFrames = LeadSheetCommittedChordBarlineOverlayGeometry.controlFrames(for: measure)
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
}

struct CueTextRenderedEditHitTargetProvider: RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget] {
        context.pageLayout.systems.flatMap { system in
            system.measures.flatMap { measure in
                measure.cueTextLayouts.flatMap { cueTextLayout in
                    cueTextTargets(for: cueTextLayout, selection: context.selection)
                }
            }
        }
    }

    private func cueTextTargets(
        for cueTextLayout: LeadSheetCueTextLayout,
        selection: RenderedEditSelectionState
    ) -> [RenderedEditHitTarget] {
        let objectID = RenderedEditObjectID.cueText(cueTextLayout.id)
        var targets = [
            RenderedEditHitTarget(
                objectID: objectID,
                action: .select,
                priority: .objectBodySelect,
                frame: LeadSheetCueTextEditOverlayGeometry.editHitFrame(for: cueTextLayout),
                requiresSelection: false,
                mutationRisk: .nonMutating
            ),
            RenderedEditHitTarget(
                objectID: objectID,
                action: .move,
                priority: .selectedObjectMoveBody,
                frame: LeadSheetCueTextEditOverlayGeometry.editHitFrame(for: cueTextLayout),
                requiresSelection: true,
                mutationRisk: .visual
            )
        ]

        guard selection.contains(objectID) else {
            return targets
        }

        let controls = LeadSheetCueTextEditOverlayGeometry.controlFrames(for: cueTextLayout)
        let controlOutset = LeadSheetCueTextEditOverlayGeometry.controlHitOutset
        targets.append(
            RenderedEditHitTarget(
                objectID: objectID,
                action: .editText,
                priority: .selectedObjectEditControl,
                frame: controls.edit.insetBy(dx: -controlOutset, dy: -controlOutset),
                requiresSelection: true,
                mutationRisk: .content
            )
        )
        targets.append(
            RenderedEditHitTarget(
                objectID: objectID,
                action: .shrink,
                priority: .selectedObjectEditControl,
                frame: controls.shrink.insetBy(dx: -controlOutset, dy: -controlOutset),
                requiresSelection: true,
                mutationRisk: .visual
            )
        )
        targets.append(
            RenderedEditHitTarget(
                objectID: objectID,
                action: .grow,
                priority: .selectedObjectEditControl,
                frame: controls.grow.insetBy(dx: -controlOutset, dy: -controlOutset),
                requiresSelection: true,
                mutationRisk: .visual
            )
        )
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
                    RenderedEditHitTarget(
                        objectID: .repeatSpan(marker.roadmapObjectID),
                        action: .openInspector,
                        priority: .objectBodySelect,
                        frame: marker.frame.insetBy(dx: -8, dy: -8),
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
        context.pageLayout.systems.flatMap { system in
            system.endingLayouts.map { ending in
                RenderedEditHitTarget(
                    objectID: .endingSpan(ending.roadmapObjectID),
                    action: .openInspector,
                    priority: .objectBodySelect,
                    frame: ending.frame.insetBy(dx: -6, dy: -8),
                    requiresSelection: false,
                    mutationRisk: .nonMutating
                )
            }
        }
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

                let objectID = RenderedEditObjectID.measure(measureID)
                var targets = [
                    RenderedEditHitTarget(
                        objectID: objectID,
                        action: .select,
                        priority: .measureSelect,
                        frame: measure.frame.insetBy(dx: -6, dy: -6),
                        requiresSelection: false,
                        mutationRisk: .nonMutating
                    )
                ]

                guard context.selection.contains(objectID) else {
                    return targets
                }

                let handles = LeadSheetMeasureResizeGeometry.handleFrames(for: measure)
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

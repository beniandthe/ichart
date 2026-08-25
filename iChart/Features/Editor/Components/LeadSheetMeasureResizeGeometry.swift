#if canImport(UIKit)
import Foundation
import UIKit

struct ActiveMeasureResizeDrag {
    enum Edge {
        case left
        case right
    }

    var measureID: UUID
    var edge: Edge
    var initialWidth: CGFloat
    var initialFrame: CGRect
    var currentFrame: CGRect
    var transaction: LeadSheetMeasureResizeTransaction? = nil
    var currentPreview: LeadSheetMeasureResizePreview? = nil
}

struct LeadSheetMeasureResizeHandleFrames {
    let left: CGRect
    let right: CGRect
}

struct LeadSheetMeasureResizeMeasureSnapshot: Hashable {
    var measureID: UUID
    var frame: CGRect
}

struct LeadSheetMeasureResizePreview: Hashable {
    var rowFrame: CGRect
    var measureFrames: [UUID: CGRect]
    var affectedMeasureIDs: [UUID]
    var draggedEdgeX: CGFloat
    var evenDivisionGuideXs: [CGFloat]
    var activeEvenDivisionGuideX: CGFloat?
    var committedManualWidths: [UUID: CGFloat]

    func frame(for measureID: UUID?) -> CGRect? {
        guard let measureID else {
            return nil
        }

        return measureFrames[measureID]
    }
}

struct LeadSheetMeasureResizeTransaction: Hashable {
    var selectedMeasureID: UUID
    var edge: ActiveMeasureResizeDrag.Edge
    var rowMeasures: [LeadSheetMeasureResizeMeasureSnapshot]
    var selectedIndex: Int
    var displayedToManualWidthScale: CGFloat
    var evenDivisionCommitManualWidths: [UUID: CGFloat]
    var minimumDisplayedWidth: CGFloat
    var maximumDisplayedWidth: CGFloat

    init?(
        selectedMeasureID: UUID,
        edge: ActiveMeasureResizeDrag.Edge,
        rowMeasures: [LeadSheetMeasureResizeMeasureSnapshot],
        displayedToManualWidthScale: CGFloat,
        evenDivisionCommitManualWidths: [UUID: CGFloat] = [:]
    ) {
        guard let selectedIndex = rowMeasures.firstIndex(where: { $0.measureID == selectedMeasureID }) else {
            return nil
        }

        self.selectedMeasureID = selectedMeasureID
        self.edge = edge
        self.rowMeasures = rowMeasures
        self.selectedIndex = selectedIndex
        self.displayedToManualWidthScale = max(0.0001, displayedToManualWidthScale)
        self.evenDivisionCommitManualWidths = evenDivisionCommitManualWidths
        minimumDisplayedWidth = Measure.minimumManualLayoutWidth / self.displayedToManualWidthScale
        maximumDisplayedWidth = Measure.maximumManualLayoutWidth / self.displayedToManualWidthScale
    }

    func preview(for translationX: CGFloat) -> LeadSheetMeasureResizePreview {
        var frames = Dictionary(uniqueKeysWithValues: rowMeasures.map { ($0.measureID, $0.frame) })
        let selected = rowMeasures[selectedIndex]
        var affectedMeasureIDs = [selected.measureID]
        let rowFrame = frozenRowFrame()

        switch edge {
        case .right:
            let neighborIndex = rowMeasures.index(after: selectedIndex)
            if rowMeasures.indices.contains(neighborIndex) {
                let neighbor = rowMeasures[neighborIndex]
                affectedMeasureIDs.append(neighbor.measureID)
                let delta = clampedRightEdgeDelta(
                    translationX,
                    selectedWidth: selected.frame.width,
                    neighborWidth: neighbor.frame.width
                )
                frames[selected.measureID]?.size.width = max(1, selected.frame.width + delta)
                frames[neighbor.measureID]?.origin.x = neighbor.frame.minX + delta
                frames[neighbor.measureID]?.size.width = max(1, neighbor.frame.width - delta)
            } else {
                let delta = clampedTerminalRightEdgeDelta(
                    translationX,
                    selectedFrame: selected.frame,
                    rowFrame: rowFrame
                )
                frames[selected.measureID]?.size.width = max(1, selected.frame.width + delta)
            }
        case .left:
            let neighborIndex = selectedIndex - 1
            if rowMeasures.indices.contains(neighborIndex) {
                let neighbor = rowMeasures[neighborIndex]
                affectedMeasureIDs.insert(neighbor.measureID, at: 0)
                let delta = clampedLeftEdgeDelta(
                    translationX,
                    selectedWidth: selected.frame.width,
                    neighborWidth: neighbor.frame.width
                )
                frames[neighbor.measureID]?.size.width = max(1, neighbor.frame.width + delta)
                frames[selected.measureID]?.origin.x = selected.frame.minX + delta
                frames[selected.measureID]?.size.width = max(1, selected.frame.width - delta)
            } else {
                let delta = clampedTerminalLeftEdgeDelta(
                    translationX,
                    selectedFrame: selected.frame,
                    rowFrame: rowFrame
                )
                frames[selected.measureID]?.origin.x = selected.frame.minX + delta
                frames[selected.measureID]?.size.width = max(1, selected.frame.width - delta)
            }
        }

        let committedManualWidths: [UUID: CGFloat] = Dictionary(
            uniqueKeysWithValues: affectedMeasureIDs.compactMap { measureID in
                guard let frame = frames[measureID] else {
                    return nil
                }

                return (
                    measureID,
                    Measure.clampedManualLayoutWidth(frame.width * displayedToManualWidthScale)
                )
            }
        )
        let draggedEdgeX: CGFloat
        if let selectedFrame = frames[selected.measureID] {
            draggedEdgeX = edge == .right ? selectedFrame.maxX : selectedFrame.minX
        } else {
            draggedEdgeX = edge == .right ? selected.frame.maxX : selected.frame.minX
        }
        let evenDivisionGuideXs = evenDivisionGuideXs(in: rowFrame, measureCount: rowMeasures.count)
        let activeEvenDivisionGuideX = activeEvenDivisionGuideX(
            for: draggedEdgeX,
            guides: evenDivisionGuideXs,
            expectedDivisionIndex: expectedEvenDivisionIndex()
        )

        if let activeEvenDivisionGuideX {
            let evenFrames = evenDivisionFrames(in: rowFrame)
            let evenAffectedMeasureIDs = rowMeasures.map(\.measureID)
            let evenCommittedManualWidths = evenDivisionCommitManualWidths.isEmpty
                ? manualWidths(for: evenAffectedMeasureIDs, in: evenFrames)
                : evenDivisionCommitManualWidths
            return LeadSheetMeasureResizePreview(
                rowFrame: rowFrame,
                measureFrames: evenFrames,
                affectedMeasureIDs: evenAffectedMeasureIDs,
                draggedEdgeX: activeEvenDivisionGuideX,
                evenDivisionGuideXs: evenDivisionGuideXs,
                activeEvenDivisionGuideX: activeEvenDivisionGuideX,
                committedManualWidths: evenCommittedManualWidths
            )
        }

        return LeadSheetMeasureResizePreview(
            rowFrame: rowFrame,
            measureFrames: frames,
            affectedMeasureIDs: affectedMeasureIDs,
            draggedEdgeX: draggedEdgeX,
            evenDivisionGuideXs: evenDivisionGuideXs,
            activeEvenDivisionGuideX: activeEvenDivisionGuideX,
            committedManualWidths: committedManualWidths
        )
    }

    private func manualWidths(
        for measureIDs: [UUID],
        in frames: [UUID: CGRect]
    ) -> [UUID: CGFloat] {
        Dictionary(
            uniqueKeysWithValues: measureIDs.compactMap { measureID in
                guard let frame = frames[measureID] else {
                    return nil
                }

                return (
                    measureID,
                    Measure.clampedManualLayoutWidth(frame.width * displayedToManualWidthScale)
                )
            }
        )
    }

    private func frozenRowFrame() -> CGRect {
        rowMeasures
            .map(\.frame)
            .reduce(CGRect.null) { partialResult, frame in
                partialResult.union(frame)
            }
    }

    private func minimumWidth(for currentWidth: CGFloat) -> CGFloat {
        min(currentWidth, minimumDisplayedWidth)
    }

    private func evenDivisionGuideXs(in rowFrame: CGRect, measureCount: Int) -> [CGFloat] {
        guard measureCount > 1, rowFrame.width > 1 else {
            return []
        }

        let divisionWidth = rowFrame.width / CGFloat(measureCount)
        return (1..<measureCount).map { divisionIndex in
            rowFrame.minX + CGFloat(divisionIndex) * divisionWidth
        }
    }

    private func evenDivisionFrames(in rowFrame: CGRect) -> [UUID: CGRect] {
        guard !rowMeasures.isEmpty, rowFrame.width > 1 else {
            return Dictionary(uniqueKeysWithValues: rowMeasures.map { ($0.measureID, $0.frame) })
        }

        let divisionWidth = rowFrame.width / CGFloat(rowMeasures.count)
        return Dictionary(
            uniqueKeysWithValues: rowMeasures.enumerated().map { index, measure in
                var frame = measure.frame
                frame.origin.x = rowFrame.minX + CGFloat(index) * divisionWidth
                frame.size.width = divisionWidth
                return (measure.measureID, frame)
            }
        )
    }

    private func expectedEvenDivisionIndex() -> Int? {
        switch edge {
        case .right:
            let divisionIndex = selectedIndex + 1
            return divisionIndex < rowMeasures.count ? divisionIndex : nil
        case .left:
            return selectedIndex > 0 ? selectedIndex : nil
        }
    }

    private func activeEvenDivisionGuideX(
        for draggedEdgeX: CGFloat,
        guides: [CGFloat],
        expectedDivisionIndex: Int?,
        tolerance: CGFloat = 5
    ) -> CGFloat? {
        guard let expectedDivisionIndex,
              expectedDivisionIndex > 0,
              guides.indices.contains(expectedDivisionIndex - 1) else {
            return nil
        }

        let guideX = guides[expectedDivisionIndex - 1]
        return abs(guideX - draggedEdgeX) <= tolerance ? guideX : nil
    }

    private func clampedRightEdgeDelta(
        _ delta: CGFloat,
        selectedWidth: CGFloat,
        neighborWidth: CGFloat
    ) -> CGFloat {
        let minimumSelectedWidth = minimumWidth(for: selectedWidth)
        let minimumNeighborWidth = minimumWidth(for: neighborWidth)
        let lowerBound = -(selectedWidth - minimumSelectedWidth)
        let upperBound = neighborWidth - minimumNeighborWidth
        return min(max(delta, lowerBound), upperBound)
    }

    private func clampedLeftEdgeDelta(
        _ delta: CGFloat,
        selectedWidth: CGFloat,
        neighborWidth: CGFloat
    ) -> CGFloat {
        let minimumSelectedWidth = minimumWidth(for: selectedWidth)
        let minimumNeighborWidth = minimumWidth(for: neighborWidth)
        let lowerBound = -(neighborWidth - minimumNeighborWidth)
        let upperBound = selectedWidth - minimumSelectedWidth
        return min(max(delta, lowerBound), upperBound)
    }

    private func clampedTerminalRightEdgeDelta(
        _ delta: CGFloat,
        selectedFrame: CGRect,
        rowFrame: CGRect
    ) -> CGFloat {
        let lowerBound = -(selectedFrame.width - minimumWidth(for: selectedFrame.width))
        let upperBound = min(
            maximumDisplayedWidth - selectedFrame.width,
            max(0, rowFrame.maxX - selectedFrame.maxX)
        )
        return min(max(delta, lowerBound), upperBound)
    }

    private func clampedTerminalLeftEdgeDelta(
        _ delta: CGFloat,
        selectedFrame: CGRect,
        rowFrame: CGRect
    ) -> CGFloat {
        let lowerBound = max(
            -(maximumDisplayedWidth - selectedFrame.width),
            rowFrame.minX - selectedFrame.minX
        )
        let upperBound = selectedFrame.width - minimumWidth(for: selectedFrame.width)
        return min(max(delta, lowerBound), upperBound)
    }
}

enum LeadSheetMeasureResizePreviewPolicy {
    static func proposedModelWidth(
        initialWidth: CGFloat,
        edge: ActiveMeasureResizeDrag.Edge,
        translationX: CGFloat
    ) -> CGFloat {
        let signedDelta = edge == .right
            ? translationX
            : -translationX
        return Measure.clampedManualLayoutWidth(initialWidth + signedDelta)
    }

    static func previewFrame(
        initialFrame: CGRect,
        edge: ActiveMeasureResizeDrag.Edge,
        translationX: CGFloat
    ) -> CGRect {
        let proposedWidth = proposedModelWidth(
            initialWidth: initialFrame.width,
            edge: edge,
            translationX: translationX
        )
        var frame = initialFrame
        frame.size.width = proposedWidth
        if edge == .left {
            frame.origin.x = initialFrame.maxX - proposedWidth
        }
        return frame
    }
}

struct LeadSheetSimpleRowGroupAffordance {
    var selectedMeasureID: UUID
    var groupedMeasureIDs: [UUID]
    var groupFrame: CGRect
    var guideY: CGFloat
}

enum LeadSheetRenderedMeasureBoundary {
    case none
    case normalBarline(type: BarlineType, frame: CGRect)
    case repeatBoundary(markers: [LeadSheetRepeatMarkerLayout], terminalTrailingLineX: CGFloat?)
}

enum LeadSheetSimpleChordTerminalBarlineGeometry {
    static func barlineFrame(
        for system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> CGRect? {
        guard layoutStyle == .simpleChordSheet,
              let referenceMeasure = system.measures.last,
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: paperFrame
              ) else {
            return nil
        }

        return referenceMeasure.trailingBarlineFrame.offsetBy(
            dx: laneFrame.maxX - 1 - referenceMeasure.trailingBarlineFrame.midX,
            dy: 0
        )
    }

    static func displayMeasure(
        _ measure: LeadSheetMeasureLayout,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> LeadSheetMeasureLayout {
        guard system.measures.last?.id == measure.id,
              (measure.isOpen || usesTerminalBarlineAsTrailingBoundary(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              )),
              let terminalFrame = barlineFrame(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ) else {
            return measure
        }

        let terminalX = terminalFrame.midX
        guard terminalX > measure.frame.maxX else {
            return measure
        }

        var displayMeasure = measure
        let addedWidth = terminalX - measure.frame.maxX
        displayMeasure.frame.size.width += addedWidth
        displayMeasure.staffFrame.size.width += addedWidth
        displayMeasure.chordBandFrame.size.width += addedWidth
        displayMeasure.writableFrame.size.width += addedWidth
        displayMeasure.trailingBarlineFrame = terminalFrame
        return displayMeasure
    }

    static func renderedBoundary(
        after measure: LeadSheetMeasureLayout,
        before nextMeasure: LeadSheetMeasureLayout?,
        excludingRepeatMarkerIDs drawnRepeatMarkerIDs: Set<String>,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> LeadSheetRenderedMeasureBoundary {
        guard !(measure.isOpen && layoutStyle != .simpleChordSheet) else {
            return .none
        }

        let allRepeatBoundaryMarkers = LeadSheetRepeatBoundaryPolicy.repeatMarkers(
            after: measure,
            before: nextMeasure
        )
        let visibleRepeatBoundaryMarkers = allRepeatBoundaryMarkers.filter {
            !drawnRepeatMarkerIDs.contains($0.id)
        }

        if !visibleRepeatBoundaryMarkers.isEmpty {
            return .repeatBoundary(
                markers: visibleRepeatBoundaryMarkers,
                terminalTrailingLineX: terminalTrailingRepeatLineX(
                    after: measure,
                    before: nextMeasure,
                    repeatBoundaryMarkers: visibleRepeatBoundaryMarkers,
                    in: system,
                    paperFrame: paperFrame,
                    layoutStyle: layoutStyle
                )
            )
        }

        guard allRepeatBoundaryMarkers.isEmpty,
              LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(
                after: measure,
                before: nextMeasure
              ) else {
            return .none
        }

        let barlineMeasure = displayMeasure(
            measure,
            in: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        )
        return .normalBarline(
            type: measure.barlineAfter,
            frame: barlineMeasure.trailingBarlineFrame
        )
    }

    static func shouldDrawStandaloneTerminalBarline(
        for system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> Bool {
        !usesTerminalBarlineAsTrailingBoundary(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        ) && !usesTerminalBarlineAsTrailingRepeatBoundary(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        )
    }

    static func usesTerminalBarlineAsTrailingBoundary(
        for system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> Bool {
        guard layoutStyle == .simpleChordSheet,
              let referenceMeasure = system.measures.last,
              referenceMeasure.sourceMeasureID != nil,
              LeadSheetRepeatBoundaryPolicy.shouldDrawNormalTrailingBarline(
                after: referenceMeasure,
                before: nil
              ),
              let terminalFrame = barlineFrame(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ) else {
            return false
        }

        return terminalFrame.midX > referenceMeasure.trailingBarlineFrame.midX + 1
    }

    static func usesTerminalBarlineAsTrailingRepeatBoundary(
        for system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> Bool {
        guard layoutStyle == .simpleChordSheet else {
            return false
        }

        for measureIndex in system.measures.indices {
            let measure = system.measures[measureIndex]
            let nextMeasureIndex = measureIndex + 1
            let nextMeasure = system.measures.indices.contains(nextMeasureIndex)
                ? system.measures[nextMeasureIndex]
                : nil
            let repeatBoundaryMarkers = LeadSheetRepeatBoundaryPolicy.repeatMarkers(
                after: measure,
                before: nextMeasure
            )

            if terminalTrailingRepeatLineX(
                after: measure,
                before: nextMeasure,
                repeatBoundaryMarkers: repeatBoundaryMarkers,
                in: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
            ) != nil {
                return true
            }
        }

        return false
    }

    static func terminalTrailingRepeatLineX(
        after measure: LeadSheetMeasureLayout,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> CGFloat? {
        guard let measureIndex = system.measures.firstIndex(where: { $0.id == measure.id }) else {
            return nil
        }

        let nextMeasureIndex = measureIndex + 1
        let nextMeasure = system.measures.indices.contains(nextMeasureIndex)
            ? system.measures[nextMeasureIndex]
            : nil
        let repeatBoundaryMarkers = LeadSheetRepeatBoundaryPolicy.repeatMarkers(
            after: measure,
            before: nextMeasure
        )

        return terminalTrailingRepeatLineX(
            after: measure,
            before: nextMeasure,
            repeatBoundaryMarkers: repeatBoundaryMarkers,
            in: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        )
    }

    static func terminalTrailingRepeatLineX(
        after measure: LeadSheetMeasureLayout,
        before nextMeasure: LeadSheetMeasureLayout?,
        repeatBoundaryMarkers: [LeadSheetRepeatMarkerLayout],
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> CGFloat? {
        guard layoutStyle == .simpleChordSheet,
              repeatBoundaryMarkers.contains(where: { $0.edge == .trailing }),
              isTerminalBoundary(
                after: measure,
                before: nextMeasure,
                in: system
              ),
              let terminalFrame = barlineFrame(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ) else {
            return nil
        }

        return terminalFrame.midX
    }

    static func renderedRepeatMarkerFrame(
        _ marker: LeadSheetRepeatMarkerLayout,
        after measure: LeadSheetMeasureLayout,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> CGRect {
        guard marker.edge == .trailing,
              let terminalTrailingLineX = terminalTrailingRepeatLineX(
                after: measure,
                in: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ) else {
            return marker.frame
        }

        let staffSpace = max(CGFloat(1), (marker.frame.height - 4) / 4)
        let lineWidth = LeadSheetBarlineMetrics.repeatLineWidth(
            staffSpace: staffSpace,
            strokeScale: 1,
            layoutStyle: layoutStyle
        )
        let markerWidth = max(lineWidth, 1)
        return CGRect(
            x: terminalTrailingLineX - markerWidth / 2,
            y: marker.frame.minY,
            width: markerWidth,
            height: marker.frame.height
        )
    }

    private static func isTerminalBoundary(
        after measure: LeadSheetMeasureLayout,
        before nextMeasure: LeadSheetMeasureLayout?,
        in system: LeadSheetSystemLayout
    ) -> Bool {
        guard nextMeasure == nil else {
            return remainingMeasuresAfter(measure, in: system).allSatisfy(isTerminalContinuationMeasure)
        }

        return system.measures.last?.id == measure.id
    }

    private static func remainingMeasuresAfter(
        _ measure: LeadSheetMeasureLayout,
        in system: LeadSheetSystemLayout
    ) -> ArraySlice<LeadSheetMeasureLayout> {
        guard let measureIndex = system.measures.firstIndex(where: { $0.id == measure.id }) else {
            return []
        }

        return system.measures.suffix(from: system.measures.index(after: measureIndex))
    }

    private static func isTerminalContinuationMeasure(_ measure: LeadSheetMeasureLayout) -> Bool {
        measure.sourceMeasureID == nil || measure.isOpen
    }

    static func terminalFillerFrame(
        for system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> CGRect? {
        guard layoutStyle == .simpleChordSheet,
              !usesTerminalBarlineAsTrailingBoundary(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ),
              !usesTerminalBarlineAsTrailingRepeatBoundary(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ),
              system.staffLineYPositions.isEmpty,
              let referenceMeasure = system.measures.last,
              !referenceMeasure.isOpen,
              referenceMeasure.sourceMeasureID != nil,
              LeadSheetRepeatBoundaryPolicy.repeatMarkers(
                after: referenceMeasure,
                before: nil
              ).isEmpty,
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: paperFrame
              ),
              let terminalFrame = barlineFrame(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ) else {
            return nil
        }

        let fillerStartX = max(referenceMeasure.frame.maxX, referenceMeasure.trailingBarlineFrame.midX)
        let fillerEndX = terminalFrame.midX
        guard fillerEndX > fillerStartX + 1 else {
            return nil
        }

        return CGRect(
            x: fillerStartX,
            y: laneFrame.minY,
            width: fillerEndX - fillerStartX,
            height: laneFrame.height
        )
    }

    static func containsTerminalFiller(
        _ location: CGPoint,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> Bool {
        terminalFillerFrame(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        )?.insetBy(dx: -4, dy: -4).contains(location) == true
    }

    static func terminalFillerContainsLaneX(
        _ laneX: CGFloat,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> Bool {
        guard let frame = terminalFillerFrame(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        ) else {
            return false
        }

        return frame.minX < laneX && laneX < frame.maxX
    }

    static func terminalBoundaryContainsLaneX(
        _ laneX: CGFloat,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> Bool {
        guard let terminalFrame = barlineFrame(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        ) else {
            return false
        }

        return abs(laneX - terminalFrame.midX) <= 12
    }
}

enum LeadSheetMeasureResizeGeometry {
    static func handleFrames(for measure: LeadSheetMeasureLayout) -> LeadSheetMeasureResizeHandleFrames {
        let handleSize = CGSize(width: 18, height: 34)
        let handleY = measure.staffFrame.midY - handleSize.height / 2
        return LeadSheetMeasureResizeHandleFrames(
            left: CGRect(
                x: measure.frame.minX - handleSize.width / 2,
                y: handleY,
                width: handleSize.width,
                height: handleSize.height
            ),
            right: CGRect(
                x: measure.frame.maxX - handleSize.width / 2,
                y: handleY,
                width: handleSize.width,
                height: handleSize.height
            )
        )
    }

    static func hitTarget(at location: CGPoint, in measure: LeadSheetMeasureLayout) -> ActiveMeasureResizeDrag? {
        guard let measureID = measure.sourceMeasureID else {
            return nil
        }

        let handleFrames = handleFrames(for: measure)
        let touchInsetX: CGFloat = -12
        let touchInsetY: CGFloat = -10

        if handleFrames.left.insetBy(dx: touchInsetX, dy: touchInsetY).contains(location) {
            return ActiveMeasureResizeDrag(
                measureID: measureID,
                edge: .left,
                initialWidth: measure.frame.width,
                initialFrame: measure.frame,
                currentFrame: measure.frame
            )
        }

        if handleFrames.right.insetBy(dx: touchInsetX, dy: touchInsetY).contains(location) {
            return ActiveMeasureResizeDrag(
                measureID: measureID,
                edge: .right,
                initialWidth: measure.frame.width,
                initialFrame: measure.frame,
                currentFrame: measure.frame
            )
        }

        return nil
    }
}

enum LeadSheetSimpleRowGroupAffordanceGeometry {
    static func affordance(
        for selectedMeasureID: UUID?,
        in pageLayout: LeadSheetPageLayout?,
        layoutStyle: ChartLayoutStyle
    ) -> LeadSheetSimpleRowGroupAffordance? {
        guard layoutStyle == .simpleChordSheet,
              let selectedMeasureID,
              let pageLayout else {
            return nil
        }

        for system in pageLayout.systems {
            guard let selectedIndex = system.measures.firstIndex(where: { measure in
                measure.sourceMeasureID == selectedMeasureID
            }) else {
                continue
            }

            let groupedMeasures = system.measures[selectedIndex...]
                .filter { $0.sourceMeasureID != nil }
            guard let firstMeasure = groupedMeasures.first else {
                return nil
            }

            let displayMeasures = groupedMeasures.map { measure in
                LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                    measure,
                    in: system,
                    paperFrame: pageLayout.paperFrame,
                    layoutStyle: layoutStyle
                )
            }
            let groupFrame = displayMeasures
                .dropFirst()
                .reduce(displayMeasures.first?.frame ?? firstMeasure.frame) { partialFrame, measure in
                    partialFrame.union(measure.frame)
                }
            let guideY = max(system.frame.minY + 10, groupFrame.minY - 11)

            return LeadSheetSimpleRowGroupAffordance(
                selectedMeasureID: selectedMeasureID,
                groupedMeasureIDs: groupedMeasures.compactMap(\.sourceMeasureID),
                groupFrame: groupFrame,
                guideY: guideY
            )
        }

        return nil
    }
}

enum LeadSheetSimpleChordRowEqualizationPolicy {
    static func manualLayoutWidths(
        for system: LeadSheetSystemLayout,
        in pageLayout: LeadSheetPageLayout,
        chart: Chart
    ) -> [UUID: CGFloat] {
        guard chart.layoutStyle == .simpleChordSheet else {
            return [:]
        }

        let sourceMeasures = system.measures.compactMap { measure -> (id: UUID, frame: CGRect)? in
            guard let measureID = measure.sourceMeasureID else {
                return nil
            }

            return (measureID, measure.frame)
        }
        guard let firstMeasure = sourceMeasures.first else {
            return [:]
        }

        let maxSystemWidth = max(1, pageLayout.paperFrame.width - 68)
        let rawRowBodyWidth = LeadSheetPageLayoutEngine.simpleChordSheetMaximumRowBodyWidth(
            chart: chart,
            maxSystemWidth: maxSystemWidth
        )
        let rawRowEndX = firstMeasure.frame.minX + rawRowBodyWidth
        let terminalFrame = LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
            for: system,
            paperFrame: pageLayout.paperFrame,
            layoutStyle: chart.layoutStyle
        )
        let terminalDisplayExtension = max(
            0,
            (terminalFrame?.midX ?? rawRowEndX) - rawRowEndX
        )
        let visibleMeasureWidth = max(
            1,
            (rawRowBodyWidth + terminalDisplayExtension) / CGFloat(sourceMeasures.count)
        )
        let lastIndex = sourceMeasures.index(before: sourceMeasures.endIndex)

        return Dictionary(
            uniqueKeysWithValues: sourceMeasures.enumerated().map { index, measure in
                let targetRawWidth = index == lastIndex
                    ? max(1, visibleMeasureWidth - terminalDisplayExtension)
                    : visibleMeasureWidth
                let manualWidth = LeadSheetPageLayoutEngine.simpleChordSheetManualLayoutWidthForTargetRowWidth(
                    targetRawWidth,
                    chart: chart,
                    maxSystemWidth: maxSystemWidth
                )

                return (measure.id, manualWidth)
            }
        )
    }
}
#endif

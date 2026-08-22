#if canImport(UIKit)
import PencilKit
import UIKit

enum LeadSheetPersistentInkColorPolicy {
    static let inkColor = UIColor(white: 0.06, alpha: 1)

    private static let componentTolerance: CGFloat = 0.015

    static func inkingTool(width: CGFloat) -> PKInkingTool {
        PKInkingTool(.pen, color: inkColor, width: width)
    }

    static func normalizedDrawing(_ drawing: PKDrawing) -> PKDrawing {
        guard needsNormalization(drawing) else {
            return drawing
        }

        return PKDrawing(strokes: drawing.strokes.map(normalizedStroke))
    }

    static func normalizedDrawingData(_ drawingData: Data?) -> Data? {
        guard let drawingData,
              let drawing = try? PKDrawing(data: drawingData) else {
            return drawingData
        }

        guard !drawing.strokes.isEmpty else {
            return drawingData == PKDrawing().dataRepresentation() ? nil : drawingData
        }

        let normalizedDrawing = normalizedDrawing(drawing)
        return normalizedDrawing.strokes.isEmpty ? nil : normalizedDrawing.dataRepresentation()
    }

    static func persistentDrawingData(for drawing: PKDrawing) -> Data? {
        let normalizedDrawing = normalizedDrawing(drawing)
        return normalizedDrawing.strokes.isEmpty ? nil : normalizedDrawing.dataRepresentation()
    }

    static func needsNormalization(_ drawing: PKDrawing) -> Bool {
        drawing.strokes.contains(where: needsNormalization)
    }

    private static func normalizedStroke(_ stroke: PKStroke) -> PKStroke {
        PKStroke(
            ink: PKInk(.pen, color: inkColor),
            path: stroke.path,
            transform: stroke.transform,
            mask: stroke.mask
        )
    }

    private static func needsNormalization(_ stroke: PKStroke) -> Bool {
        stroke.ink.inkType != .pen || !matchesPersistentInkColor(stroke.ink.color)
    }

    static func matchesPersistentInkColor(_ color: UIColor) -> Bool {
        matchesPersistentInkComponents(color)
    }

    private static func matchesPersistentInkComponents(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return false
        }

        return abs(red - 0.06) <= componentTolerance
            && abs(green - 0.06) <= componentTolerance
            && abs(blue - 0.06) <= componentTolerance
            && alpha >= 0.98
    }
}

enum LeadSheetPersistentInkCoordinateSpacePolicy {
    static func coordinateSpace(for frame: CGRect) -> PersistentInkCoordinateSpace? {
        PersistentInkCoordinateSpace(size: frame.size)
    }

    static func coordinateSpace(
        for activeInkScope: LeadSheetActiveInkScope,
        pageLayout: LeadSheetPageLayout?
    ) -> PersistentInkCoordinateSpace? {
        switch activeInkScope {
        case .page(let frame):
            guard let pageLayout else {
                return coordinateSpace(for: frame)
            }
            return pageCoordinateSpace(for: pageLayout, relativeTo: frame)

        case .header(let frame),
             .chords(let frame, _),
             .rhythmicMeasure(_, let frame),
             .noteSelection(let frame):
            return coordinateSpace(for: frame)
        }
    }

    static func pageCoordinateSpace(
        for pageLayout: LeadSheetPageLayout,
        relativeTo frame: CGRect
    ) -> PersistentInkCoordinateSpace? {
        PersistentInkCoordinateSpace(
            size: frame.size,
            measureAnchors: measureAnchors(in: pageLayout, relativeTo: frame),
            chordAnchors: chordAnchors(in: pageLayout, relativeTo: frame)
        )
    }

    static func pageSourceCoordinateSpace(
        _ coordinateSpace: PersistentInkCoordinateSpace?,
        chart: Chart
    ) -> PersistentInkCoordinateSpace? {
        guard var coordinateSpace else {
            return nil
        }

        if coordinateSpace.chordAnchors?.isEmpty == false {
            return coordinateSpace
        }

        guard let sourceLayout = inferredPageLayout(
            for: chart,
            pageWritingSize: coordinateSpace.size
        ) else {
            return coordinateSpace
        }

        let sourceFrame = LeadSheetActiveInkScope.pageWritingFrame(for: sourceLayout)
        coordinateSpace.chordAnchors = chordAnchors(in: sourceLayout, relativeTo: sourceFrame)
        if coordinateSpace.measureAnchors?.isEmpty != false {
            coordinateSpace.measureAnchors = measureAnchors(in: sourceLayout, relativeTo: sourceFrame)
        }
        return coordinateSpace
    }

    static func sourceCoordinateSpace(
        _ coordinateSpace: PersistentInkCoordinateSpace?,
        for activeInkScope: LeadSheetActiveInkScope,
        chart: Chart
    ) -> PersistentInkCoordinateSpace? {
        switch activeInkScope {
        case .page:
            return pageSourceCoordinateSpace(coordinateSpace, chart: chart)
        case .header,
             .chords,
             .rhythmicMeasure,
             .noteSelection:
            return coordinateSpace
        }
    }

    static func measureAnchors(
        in pageLayout: LeadSheetPageLayout,
        relativeTo frame: CGRect
    ) -> [PersistentInkMeasureAnchor] {
        pageLayout.systems
            .flatMap(\.measures)
            .compactMap { measureLayout in
                guard let measureID = measureLayout.sourceMeasureID else {
                    return nil
                }

                let anchorFrame = measureLayout.chordWritingFrame.offsetBy(
                    dx: -frame.minX,
                    dy: -frame.minY
                )
                return PersistentInkMeasureAnchor(
                    measureID: measureID,
                    frame: anchorFrame
                )
            }
    }

    static func chordAnchors(
        in pageLayout: LeadSheetPageLayout,
        relativeTo frame: CGRect
    ) -> [PersistentInkChordAnchor] {
        pageLayout.systems
            .flatMap(\.measures)
            .flatMap { measureLayout -> [PersistentInkChordAnchor] in
                guard let measureID = measureLayout.sourceMeasureID else {
                    return []
                }

                return measureLayout.chordLayouts.compactMap { chordLayout in
                    let anchorFrame = chordLayout.frame.offsetBy(
                        dx: -frame.minX,
                        dy: -frame.minY
                    )
                    return PersistentInkChordAnchor(
                        measureID: measureID,
                        chordID: chordLayout.id,
                        frame: anchorFrame,
                        registrationPoint: CGPoint(
                            x: chordLayout.snapGuideTarget.x - frame.minX,
                            y: chordLayout.snapGuideTarget.y - frame.minY
                        )
                    )
                }
            }
    }

    private static func inferredPageLayout(
        for chart: Chart,
        pageWritingSize: CGSize
    ) -> LeadSheetPageLayout? {
        guard pageWritingSize.width > 0,
              pageWritingSize.height > 0,
              pageWritingSize.width.isFinite,
              pageWritingSize.height.isFinite else {
            return nil
        }

        let pageWidthCandidates = [
            pageWritingSize.width + 68,
            pageWritingSize.width + 56,
            pageWritingSize.width + 160,
            pageWritingSize.width
        ]
        let pageHeightCandidates = [
            pageWritingSize.height + 80,
            pageWritingSize.height + 60,
            pageWritingSize.height
        ]

        var bestLayout: LeadSheetPageLayout?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for pageWidth in pageWidthCandidates {
            for pageHeight in pageHeightCandidates {
                let layout = LeadSheetPageLayoutEngine.pageLayout(
                    for: chart,
                    pageSize: CGSize(width: pageWidth, height: pageHeight)
                )
                let inferredWritingSize = LeadSheetActiveInkScope.pageWritingFrame(for: layout).size
                let distance = abs(inferredWritingSize.width - pageWritingSize.width)
                    + abs(inferredWritingSize.height - pageWritingSize.height)
                if distance < bestDistance {
                    bestDistance = distance
                    bestLayout = layout
                }
            }
        }

        return bestLayout
    }

    static func drawing(
        from drawingData: Data?,
        sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        targetFrame: CGRect
    ) -> PKDrawing? {
        guard let drawingData,
              let drawing = try? PKDrawing(data: drawingData) else {
            return nil
        }

        let normalizedDrawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(drawing)
        return Self.drawing(
            normalizedDrawing,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: coordinateSpace(for: targetFrame)
        )
    }

    static func drawing(
        from drawingData: Data?,
        sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        targetCoordinateSpace: PersistentInkCoordinateSpace?
    ) -> PKDrawing? {
        guard let drawingData,
              let drawing = try? PKDrawing(data: drawingData) else {
            return nil
        }

        let normalizedDrawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(drawing)
        return Self.drawing(
            normalizedDrawing,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        )
    }

    static func drawing(
        _ drawing: PKDrawing,
        sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        targetCoordinateSpace: PersistentInkCoordinateSpace?
    ) -> PKDrawing {
        guard let sourceCoordinateSpace,
              let targetCoordinateSpace,
              sourceCoordinateSpace != targetCoordinateSpace else {
            return drawing
        }

        let sourceSize = sourceCoordinateSpace.size
        let targetSize = targetCoordinateSpace.size
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return drawing
        }

        let pageTransform = CGAffineTransform(
            scaleX: targetSize.width / sourceSize.width,
            y: targetSize.height / sourceSize.height
        )
        let anchoredDrawing = anchoredDrawing(
            drawing,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace,
            fallbackTransform: pageTransform
        )
        return anchoredDrawing ?? drawing.transformed(using: pageTransform)
    }

    static func persistentDrawingData(
        from drawingData: Data?,
        sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        targetFrame: CGRect
    ) -> Data? {
        guard let drawing = drawing(
            from: drawingData,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetFrame: targetFrame
        ) else {
            return nil
        }

        return LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: drawing)
    }

    static func persistentDrawingData(
        from drawingData: Data?,
        sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        targetCoordinateSpace: PersistentInkCoordinateSpace?
    ) -> Data? {
        guard let drawing = drawing(
            from: drawingData,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        ) else {
            return nil
        }

        return LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: drawing)
    }

    private static func anchoredDrawing(
        _ drawing: PKDrawing,
        sourceCoordinateSpace: PersistentInkCoordinateSpace,
        targetCoordinateSpace: PersistentInkCoordinateSpace,
        fallbackTransform: CGAffineTransform
    ) -> PKDrawing? {
        let sourceMeasureAnchors = sourceCoordinateSpace.measureAnchors ?? []
        let targetMeasureAnchors = targetCoordinateSpace.measureAnchors ?? []
        let sourceChordAnchors = sourceCoordinateSpace.chordAnchors ?? []
        let targetChordAnchors = targetCoordinateSpace.chordAnchors ?? []
        let canUseMeasureAnchors = !sourceMeasureAnchors.isEmpty && !targetMeasureAnchors.isEmpty
        let canUseChordAnchors = !sourceChordAnchors.isEmpty && !targetChordAnchors.isEmpty

        guard canUseMeasureAnchors || canUseChordAnchors else {
            return nil
        }

        let targetMeasureAnchorsByMeasureID = Dictionary(
            uniqueKeysWithValues: targetMeasureAnchors.map { ($0.measureID, $0) }
        )
        let targetChordAnchorsByChordID = Dictionary(
            uniqueKeysWithValues: targetChordAnchors.map { ($0.chordID, $0) }
        )
        let transformedStrokes = drawing.strokes.map { stroke -> PKStroke in
            let transform = chordAnchorTransform(
                for: stroke,
                sourceAnchors: sourceChordAnchors,
                targetAnchorsByChordID: targetChordAnchorsByChordID
            ) ?? measureAnchorTransform(
                for: stroke,
                sourceAnchors: sourceMeasureAnchors,
                targetAnchorsByMeasureID: targetMeasureAnchorsByMeasureID
            ) ?? fallbackTransform
            return PKDrawing(strokes: [stroke]).transformed(using: transform).strokes.first ?? stroke
        }

        return PKDrawing(strokes: transformedStrokes)
    }

    private static func chordAnchorTransform(
        for stroke: PKStroke,
        sourceAnchors: [PersistentInkChordAnchor],
        targetAnchorsByChordID: [UUID: PersistentInkChordAnchor]
    ) -> CGAffineTransform? {
        let strokeBounds = stroke.renderBounds
        guard !strokeBounds.isNull,
              !strokeBounds.isEmpty,
              let sourceAnchor = sourceChordAnchor(for: strokeBounds, in: sourceAnchors),
              let targetAnchor = targetAnchorsByChordID[sourceAnchor.chordID] else {
            return nil
        }

        let sourceFrame = sourceAnchor.frame.rect
        let targetFrame = targetAnchor.frame.rect
        guard sourceFrame.width > 0,
              sourceFrame.height > 0,
              targetFrame.width > 0,
              targetFrame.height > 0 else {
            return nil
        }

        let sourceRegistrationPoint = sourceAnchor.registrationPoint?.point ?? sourceFrame.origin
        let targetRegistrationPoint = targetAnchor.registrationPoint?.point ?? targetFrame.origin
        return CGAffineTransform(
            translationX: targetRegistrationPoint.x - sourceRegistrationPoint.x,
            y: targetRegistrationPoint.y - sourceRegistrationPoint.y
        )
    }

    private static func measureAnchorTransform(
        for stroke: PKStroke,
        sourceAnchors: [PersistentInkMeasureAnchor],
        targetAnchorsByMeasureID: [UUID: PersistentInkMeasureAnchor]
    ) -> CGAffineTransform? {
        let strokeBounds = stroke.renderBounds
        guard !strokeBounds.isNull,
              !strokeBounds.isEmpty else {
            return nil
        }

        guard let sourceAnchor = sourceAnchor(
            for: strokeBounds,
            in: sourceAnchors
        ),
              let targetAnchor = targetAnchorsByMeasureID[sourceAnchor.measureID] else {
            return nil
        }

        let sourceFrame = sourceAnchor.frame.rect
        let targetFrame = targetAnchor.frame.rect
        guard sourceFrame.width > 0,
              sourceFrame.height > 0,
              targetFrame.width > 0,
              targetFrame.height > 0 else {
            return nil
        }

        let scaleX = targetFrame.width / sourceFrame.width
        let scaleY = targetFrame.height / sourceFrame.height
        return CGAffineTransform(
            a: scaleX,
            b: 0,
            c: 0,
            d: scaleY,
            tx: targetFrame.minX - sourceFrame.minX * scaleX,
            ty: targetFrame.minY - sourceFrame.minY * scaleY
        )
    }

    private static func sourceAnchor(
        for strokeBounds: CGRect,
        in sourceAnchors: [PersistentInkMeasureAnchor]
    ) -> PersistentInkMeasureAnchor? {
        guard !strokeBounds.isNull,
              !strokeBounds.isEmpty else {
            return nil
        }

        let strokeCenter = CGPoint(x: strokeBounds.midX, y: strokeBounds.midY)
        return sourceAnchors
            .filter { measureAnchorHitFrame($0.frame.rect).contains(strokeCenter) }
            .min {
                distanceSquared(from: strokeCenter, to: $0.frame.rect)
                    < distanceSquared(from: strokeCenter, to: $1.frame.rect)
            }
    }

    private static func sourceChordAnchor(
        for strokeBounds: CGRect,
        in sourceAnchors: [PersistentInkChordAnchor]
    ) -> PersistentInkChordAnchor? {
        guard !strokeBounds.isNull,
              !strokeBounds.isEmpty else {
            return nil
        }

        let strokeCenter = CGPoint(x: strokeBounds.midX, y: strokeBounds.midY)
        return sourceAnchors
            .filter { chordAnchorHitFrame($0.frame.rect).contains(strokeCenter) }
            .min {
                distanceSquared(from: strokeCenter, to: $0.frame.rect)
                    < distanceSquared(from: strokeCenter, to: $1.frame.rect)
            }
    }

    private static func measureAnchorHitFrame(_ frame: CGRect) -> CGRect {
        let horizontalPadding = CGFloat(10)
        let verticalPadding = max(CGFloat(28), frame.height * 0.45)
        return frame.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }

    private static func chordAnchorHitFrame(_ frame: CGRect) -> CGRect {
        let horizontalPadding = max(CGFloat(18), frame.width * 0.45)
        let verticalPadding = max(CGFloat(48), frame.height * 0.95)
        return frame.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }
}

struct LeadSheetInteractionModeStatePolicy {
    var selectionTapEnabled: Bool
    var inkSelectionTapEnabled: Bool
    var measureResizePanEnabled: Bool
    var renderedEditTapEnabled: Bool
    var renderedObjectMovePanEnabled: Bool
    var renderedEditOverlayHidden: Bool
    var renderedEditOverlayInteractionEnabled: Bool
    var pageInkCanvasInteractionEnabled: Bool
    var clearsMeasureResizeDrag: Bool
    var clearsRenderedObjectInteractionState: Bool
    var hidesPageInkCanvas: Bool
    var inkTool: PKInkingTool
    var inkToolMode: EditorInkToolMode
    var drawingPolicy: PKCanvasViewDrawingPolicy

    var canvasTool: PKTool {
        switch inkToolMode {
        case .write:
            return inkTool
        case .erase:
            return PKEraserTool(.bitmap)
        }
    }

    static func resolve(
        for interactionMode: EditorCanvasMode,
        inkToolMode: EditorInkToolMode = .write
    ) -> LeadSheetInteractionModeStatePolicy {
        let allowsTransparentEditOverlay = interactionMode.allowsChordObjectEditing
            || interactionMode.allowsCueTextEditing
            || interactionMode.allowsPageInkEditing
        return LeadSheetInteractionModeStatePolicy(
            selectionTapEnabled: interactionMode.allowsMeasureSelection || interactionMode.allowsNoteSelection,
            inkSelectionTapEnabled: interactionMode.allowsNoteSelection
                || interactionMode.allowsChordInkEditing
                || interactionMode.allowsHeaderInkEditing
                || interactionMode.allowsPageInkEditing,
            measureResizePanEnabled: interactionMode.showsMeasureResizeHandles,
            renderedEditTapEnabled: allowsTransparentEditOverlay,
            renderedObjectMovePanEnabled: allowsTransparentEditOverlay,
            renderedEditOverlayHidden: !allowsTransparentEditOverlay,
            renderedEditOverlayInteractionEnabled: allowsTransparentEditOverlay,
            pageInkCanvasInteractionEnabled: interactionMode.allowsAnyInkEditing,
            clearsMeasureResizeDrag: !interactionMode.showsMeasureResizeHandles,
            clearsRenderedObjectInteractionState: !interactionMode.allowsChordObjectEditing
                && !interactionMode.allowsCueTextEditing,
            hidesPageInkCanvas: !interactionMode.allowsAnyInkEditing,
            inkTool: inkTool(for: interactionMode),
            inkToolMode: interactionMode.allowsAnyInkEditing ? inkToolMode : .write,
            drawingPolicy: drawingPolicy(for: interactionMode)
        )
    }

    private static func inkTool(for interactionMode: EditorCanvasMode) -> PKInkingTool {
        if interactionMode.allowsNoteSelectionInk {
            return PKInkingTool(
                .pen,
                color: UIColor(red: 0.12, green: 0.36, blue: 0.88, alpha: 0.9),
                width: 2.4
            )
        }

        if interactionMode.allowsChordInkEditing {
            return LeadSheetPersistentInkColorPolicy.inkingTool(width: 2.5)
        }

        return LeadSheetPersistentInkColorPolicy.inkingTool(width: 2.8)
    }

    private static func drawingPolicy(for interactionMode: EditorCanvasMode) -> PKCanvasViewDrawingPolicy {
        guard interactionMode.allowsChordInkEditing else {
            return .anyInput
        }

        #if targetEnvironment(simulator)
        return .anyInput
        #else
        return .pencilOnly
        #endif
    }
}

enum LeadSheetScrollMarginPolicy {
    static let paperHitSlop: CGFloat = 8

    static func allowsPageScrollStart(
        at point: CGPoint,
        paperFrame: CGRect?,
        restrictsToOutsideMargins: Bool
    ) -> Bool {
        guard restrictsToOutsideMargins,
              let paperFrame else {
            return true
        }

        return !paperFrame
            .insetBy(dx: -paperHitSlop, dy: -paperHitSlop)
            .contains(point)
    }

    static func dragAreaFrames(in bounds: CGRect, paperFrame: CGRect?) -> [CGRect] {
        guard let paperFrame,
              !bounds.isEmpty,
              !bounds.isNull else {
            return []
        }

        let protectedFrame = paperFrame.insetBy(dx: -paperHitSlop, dy: -paperHitSlop)
        let candidates = [
            CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: max(0, protectedFrame.minX - bounds.minX),
                height: bounds.height
            ),
            CGRect(
                x: protectedFrame.maxX,
                y: bounds.minY,
                width: max(0, bounds.maxX - protectedFrame.maxX),
                height: bounds.height
            ),
            CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: max(0, protectedFrame.minY - bounds.minY)
            ),
            CGRect(
                x: bounds.minX,
                y: protectedFrame.maxY,
                width: bounds.width,
                height: max(0, bounds.maxY - protectedFrame.maxY)
            )
        ]

        return candidates.filter { $0.width > 1 && $0.height > 1 }
    }
}

enum LeadSheetRenderedObjectMoveScrollLockPolicy {
    static func allowsSimultaneousRecognition(
        involvesRenderedObjectMove: Bool,
        involvesParentScroll: Bool
    ) -> Bool {
        !(involvesRenderedObjectMove && involvesParentScroll)
    }
}

enum LeadSheetObjectMoveTouchPolicy {
    static func allowsMovePan(
        touchType: UITouch.TouchType,
        startsOnMoveTarget: Bool
    ) -> Bool {
        touchType != .pencil || startsOnMoveTarget
    }
}
#endif

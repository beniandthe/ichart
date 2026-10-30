#if canImport(UIKit)
import PencilKit
import UIKit

struct LeadSheetPersistentInkSerialization {
    var drawingData: Data?
    var normalizationNeeded: Bool
}

enum LeadSheetPersistentInkColorPolicy {
    static let inkColor = UIColor(white: 0.06, alpha: 1)

    private static let componentTolerance: CGFloat = 0.015

    static func inkingTool(width: CGFloat) -> PKInkingTool {
        PKInkingTool(.pen, color: inkColor, width: width)
    }

    static func normalizedDrawing(_ drawing: PKDrawing) -> PKDrawing {
        let strokes = drawing.strokes
        guard strokes.contains(where: needsNormalization) else {
            return drawing
        }

        return PKDrawing(strokes: strokes.map(normalizedStroke))
    }

    static func normalizedDrawingData(_ drawingData: Data?) -> Data? {
        guard let drawingData,
              let drawing = try? PKDrawing(data: drawingData) else {
            return drawingData
        }

        let strokes = drawing.strokes
        guard !strokes.isEmpty else {
            return drawingData == PKDrawing().dataRepresentation() ? nil : drawingData
        }

        // PencilKit can rewrite an otherwise identical archive across OS
        // versions. Keep the original source bytes when its ink already has
        // the persistent color/type; decoding alone must not rewrite it.
        guard strokes.contains(where: needsNormalization) else { return drawingData }
        return PKDrawing(strokes: strokes.map(normalizedStroke)).dataRepresentation()
    }

    static func persistentDrawingData(for drawing: PKDrawing) -> Data? {
        serialization(for: drawing).drawingData
    }

    static func serialization(for drawing: PKDrawing) -> LeadSheetPersistentInkSerialization {
        let strokes = drawing.strokes
        let strokeCount = strokes.count
        guard strokeCount > 0 else {
            return LeadSheetPersistentInkSerialization(
                drawingData: nil,
                normalizationNeeded: false
            )
        }

        let normalizationNeeded = strokes.contains(where: needsNormalization)
        let persistentDrawing = normalizationNeeded
            ? PKDrawing(strokes: strokes.map(normalizedStroke))
            : drawing
        return LeadSheetPersistentInkSerialization(
            drawingData: persistentDrawing.dataRepresentation(),
            normalizationNeeded: normalizationNeeded
        )
    }

    static func needsNormalization(_ drawing: PKDrawing) -> Bool {
        drawing.strokes.contains(where: needsNormalization)
    }

    private static func normalizedStroke(_ stroke: PKStroke) -> PKStroke {
        PKStroke(
            ink: PKInk(.pen, color: inkColor),
            path: stroke.path,
            transform: stroke.transform,
            mask: stroke.mask,
            randomSeed: stroke.randomSeed
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
        // Free Ink belongs to the paper, not inferred musical objects. Keep
        // legacy source metadata intact when opening or rotating a chart.
        coordinateSpace
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
              targetSize.height > 0,
              sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              targetSize.width.isFinite,
              targetSize.height.isFinite else {
            return drawing
        }

        // Page spaces carry musical anchors as layout metadata, but Free Ink
        // must retain its exact paper coordinates. The editor and PDF exporter
        // preserve that paper's logical width; rotation only changes the view.
        if isPageCoordinateSpace(sourceCoordinateSpace)
            || isPageCoordinateSpace(targetCoordinateSpace) {
            return drawing
        }

        // Header, chord and rhythmic canvases retain their existing mapping.
        return drawing.transformed(using: CGAffineTransform(
            scaleX: targetSize.width / sourceSize.width,
            y: targetSize.height / sourceSize.height
        ))
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

    private static func isPageCoordinateSpace(_ space: PersistentInkCoordinateSpace) -> Bool {
        space.measureAnchors?.isEmpty == false || space.chordAnchors?.isEmpty == false
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
            drawingPolicy: LeadSheetLiveInkInputPolicy.drawingPolicy(for: interactionMode)
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

}

enum LeadSheetLiveInkInputPolicy {
    enum RuntimeEnvironment {
        case device
        case simulator

        static var current: RuntimeEnvironment {
            #if targetEnvironment(simulator)
            return .simulator
            #else
            return .device
            #endif
        }
    }

    static func drawingPolicy(
        for interactionMode: EditorCanvasMode,
        environment: RuntimeEnvironment = .current
    ) -> PKCanvasViewDrawingPolicy {
        guard interactionMode.allowsAnyInkEditing else {
            return .anyInput
        }

        switch environment {
        case .device:
            return .pencilOnly
        case .simulator:
            return .anyInput
        }
    }

    static func allowsCanvasGestureTouch(
        touchType: UITouch.TouchType,
        interactionMode: EditorCanvasMode,
        environment: RuntimeEnvironment = .current
    ) -> Bool {
        guard interactionMode.allowsAnyInkEditing,
              environment == .device else {
            return true
        }

        return touchType == .pencil
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
        interactionMode: EditorCanvasMode,
        startsOnMoveTarget: Bool,
        environment: LeadSheetLiveInkInputPolicy.RuntimeEnvironment = .current
    ) -> Bool {
        guard LeadSheetLiveInkInputPolicy.allowsCanvasGestureTouch(
            touchType: touchType,
            interactionMode: interactionMode,
            environment: environment
        ) else {
            return false
        }

        return touchType != .pencil || startsOnMoveTarget
    }
}

enum LeadSheetParentScrollTouchPolicy {
    static func blocksParentScrollStart(
        touchType: UITouch.TouchType,
        interactionMode: EditorCanvasMode,
        environment: LeadSheetLiveInkInputPolicy.RuntimeEnvironment = .current
    ) -> Bool {
        !LeadSheetLiveInkInputPolicy.allowsCanvasGestureTouch(
            touchType: touchType,
            interactionMode: interactionMode,
            environment: environment
        )
    }
}
#endif

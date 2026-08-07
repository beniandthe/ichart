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

    private static func matchesPersistentInkColor(_ color: UIColor) -> Bool {
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

struct LeadSheetInteractionModeStatePolicy {
    var selectionTapEnabled: Bool
    var inkSelectionTapEnabled: Bool
    var measureResizePanEnabled: Bool
    var chordEditTapEnabled: Bool
    var chordMovePanEnabled: Bool
    var chordEditOverlayHidden: Bool
    var chordEditOverlayInteractionEnabled: Bool
    var pageInkCanvasInteractionEnabled: Bool
    var clearsMeasureResizeDrag: Bool
    var clearsChordInteractionState: Bool
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
            chordEditTapEnabled: allowsTransparentEditOverlay,
            chordMovePanEnabled: allowsTransparentEditOverlay,
            chordEditOverlayHidden: !allowsTransparentEditOverlay,
            chordEditOverlayInteractionEnabled: allowsTransparentEditOverlay,
            pageInkCanvasInteractionEnabled: interactionMode.allowsAnyInkEditing,
            clearsMeasureResizeDrag: !interactionMode.showsMeasureResizeHandles,
            clearsChordInteractionState: !interactionMode.allowsChordObjectEditing
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

enum LeadSheetChordMoveScrollLockPolicy {
    static func allowsSimultaneousRecognition(
        involvesChordMove: Bool,
        involvesParentScroll: Bool
    ) -> Bool {
        !(involvesChordMove && involvesParentScroll)
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

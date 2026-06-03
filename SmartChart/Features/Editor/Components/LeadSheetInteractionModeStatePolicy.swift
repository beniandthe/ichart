#if canImport(UIKit)
import PencilKit
import UIKit

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
            clearsChordInteractionState: !interactionMode.allowsChordObjectEditing,
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
            return PKInkingTool(
                .pen,
                color: UIColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1),
                width: 2.5
            )
        }

        return PKInkingTool(.pen, color: UIColor(white: 0.06, alpha: 1), width: 2.8)
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
}
#endif

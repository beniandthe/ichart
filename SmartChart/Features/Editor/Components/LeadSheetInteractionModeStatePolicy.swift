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
    var drawingPolicy: PKCanvasViewDrawingPolicy

    static func resolve(for interactionMode: EditorCanvasMode) -> LeadSheetInteractionModeStatePolicy {
        LeadSheetInteractionModeStatePolicy(
            selectionTapEnabled: interactionMode.allowsMeasureSelection || interactionMode.allowsNoteSelection,
            inkSelectionTapEnabled: interactionMode.allowsNoteSelection || interactionMode.allowsChordInkEditing,
            measureResizePanEnabled: interactionMode.showsMeasureResizeHandles,
            chordEditTapEnabled: interactionMode.allowsChordInkEditing,
            chordMovePanEnabled: interactionMode.allowsChordInkEditing,
            chordEditOverlayHidden: !interactionMode.allowsChordInkEditing,
            chordEditOverlayInteractionEnabled: interactionMode.allowsChordInkEditing,
            pageInkCanvasInteractionEnabled: interactionMode.allowsAnyInkEditing,
            clearsMeasureResizeDrag: !interactionMode.showsMeasureResizeHandles,
            clearsChordInteractionState: !interactionMode.allowsChordInkEditing,
            hidesPageInkCanvas: !interactionMode.allowsAnyInkEditing,
            inkTool: inkTool(for: interactionMode),
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
#endif

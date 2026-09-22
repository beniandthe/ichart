#if canImport(PencilKit) && canImport(UIKit)
import PencilKit
import SwiftUI
import UIKit

enum RecognitionStudyCanvasCommandKind: Equatable {
    case clear
    case reset
    case undo
}

struct RecognitionStudyCanvasCommand: Equatable {
    let id: UUID
    let kind: RecognitionStudyCanvasCommandKind

    init(_ kind: RecognitionStudyCanvasCommandKind) {
        id = UUID()
        self.kind = kind
    }
}

/// The study canvas deliberately has no dependency on the chart editor. On a
/// physical iPad it accepts Apple Pencil input only; Simulator keeps direct
/// input enabled so the isolated target remains automatable.
struct RecognitionStudyCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var canUndo: Bool

    let command: RecognitionStudyCanvasCommand?
    let isDrawingEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView(frame: .zero)
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.bounces = false
        canvasView.tool = PKInkingTool(
            .pen,
            color: UIColor.label,
            width: 4
        )
#if targetEnvironment(simulator)
        canvasView.drawingPolicy = .anyInput
#else
        canvasView.drawingPolicy = .pencilOnly
#endif
        canvasView.drawing = drawing
        canvasView.isUserInteractionEnabled = isDrawingEnabled
        context.coordinator.canvasView = canvasView
        context.coordinator.publishUndoState(from: canvasView)
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvasView.isUserInteractionEnabled = isDrawingEnabled

        guard let command,
              command.id != context.coordinator.lastCommandID else {
            context.coordinator.publishUndoState(from: canvasView)
            return
        }

        context.coordinator.lastCommandID = command.id
        switch command.kind {
        case .clear:
            canvasView.drawing = PKDrawing()
            canvasView.undoManager?.removeAllActions()
        case .reset:
            canvasView.drawing = PKDrawing()
            canvasView.undoManager?.removeAllActions()
        case .undo:
            canvasView.undoManager?.undo()
        }
        context.coordinator.publishDrawing(from: canvasView)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: RecognitionStudyCanvasView
        weak var canvasView: PKCanvasView?
        var lastCommandID: UUID?

        init(parent: RecognitionStudyCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            publishDrawing(from: canvasView)
        }

        func publishDrawing(from canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            publishUndoState(from: canvasView)
        }

        func publishUndoState(from canvasView: PKCanvasView) {
            let nextValue = canvasView.undoManager?.canUndo == true
            guard parent.canUndo != nextValue else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.parent.canUndo = nextValue
            }
        }
    }
}
#endif

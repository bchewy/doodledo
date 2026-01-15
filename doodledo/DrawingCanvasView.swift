import PencilKit
import SwiftUI

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var tool: PKTool
    var onDrawingChange: ((PKDrawing) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.isScrollEnabled = false
        canvasView.tool = tool
        canvasView.delegate = context.coordinator
        context.coordinator.isUpdatingFromSwiftUI = true
        defer { context.coordinator.isUpdatingFromSwiftUI = false }
        canvasView.drawing = drawing
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.isUpdatingFromSwiftUI = true
        defer { context.coordinator.isUpdatingFromSwiftUI = false }
        uiView.drawing = drawing
        uiView.tool = tool
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: DrawingCanvasView
        var isUpdatingFromSwiftUI = false

        init(_ parent: DrawingCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingFromSwiftUI else { return }
            parent.drawing = canvasView.drawing
            parent.onDrawingChange?(canvasView.drawing)
        }
    }
}

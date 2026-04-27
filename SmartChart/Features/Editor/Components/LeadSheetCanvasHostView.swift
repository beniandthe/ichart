#if canImport(UIKit)
import PencilKit
import SwiftUI
import UIKit

struct LeadSheetCanvasHostView: UIViewRepresentable {
    @Binding var chart: Chart
    @Binding var selectedMeasureID: UUID?
    @Binding var selectedNoteSelection: LeadSheetNoteSelection?
    let interactionMode: EditorCanvasMode
    var onTimeSignatureTargetRequested: ((UUID) -> Void)? = nil
    var onRhythmicNotationProposal: ((UUID, [RhythmValue], Data) -> Void)? = nil
    var onRhythmicNotationValidationError: ((String) -> Void)? = nil
    var onNoteSelectionChanged: ((LeadSheetNoteSelection?) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            chart: $chart,
            selectedMeasureID: $selectedMeasureID,
            selectedNoteSelection: $selectedNoteSelection
        )
    }

    func makeUIView(context: Context) -> LeadSheetCanvasUIKitView {
        let view = LeadSheetCanvasUIKitView()
        view.chart = chart
        view.selectedMeasureID = selectedMeasureID
        view.selectedNoteSelection = selectedNoteSelection
        view.interactionMode = interactionMode
        view.onMeasureSelectionChanged = { measureID in
            context.coordinator.selectedMeasureID.wrappedValue = measureID
        }
        view.onNoteSelectionChanged = { selection in
            context.coordinator.selectedNoteSelection.wrappedValue = selection
            onNoteSelectionChanged?(selection)
        }
        view.onChartChanged = { updatedChart in
            context.coordinator.chart.wrappedValue = updatedChart
        }
        view.onTimeSignatureTargetRequested = onTimeSignatureTargetRequested
        view.onRhythmicNotationProposal = onRhythmicNotationProposal
        view.onRhythmicNotationValidationError = onRhythmicNotationValidationError
        return view
    }

    func updateUIView(_ uiView: LeadSheetCanvasUIKitView, context: Context) {
        uiView.chart = chart
        uiView.selectedMeasureID = selectedMeasureID
        uiView.selectedNoteSelection = selectedNoteSelection
        uiView.interactionMode = interactionMode
        uiView.onMeasureSelectionChanged = { measureID in
            context.coordinator.selectedMeasureID.wrappedValue = measureID
        }
        uiView.onNoteSelectionChanged = { selection in
            context.coordinator.selectedNoteSelection.wrappedValue = selection
            onNoteSelectionChanged?(selection)
        }
        uiView.onChartChanged = { updatedChart in
            context.coordinator.chart.wrappedValue = updatedChart
        }
        uiView.onTimeSignatureTargetRequested = onTimeSignatureTargetRequested
        uiView.onRhythmicNotationProposal = onRhythmicNotationProposal
        uiView.onRhythmicNotationValidationError = onRhythmicNotationValidationError
    }

    final class Coordinator {
        var chart: Binding<Chart>
        var selectedMeasureID: Binding<UUID?>
        var selectedNoteSelection: Binding<LeadSheetNoteSelection?>

        init(
            chart: Binding<Chart>,
            selectedMeasureID: Binding<UUID?>,
            selectedNoteSelection: Binding<LeadSheetNoteSelection?>
        ) {
            self.chart = chart
            self.selectedMeasureID = selectedMeasureID
            self.selectedNoteSelection = selectedNoteSelection
        }
    }
}

final class LeadSheetCanvasUIKitView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    var chart: Chart = .draft(title: "Preview") {
        didSet {
            guard oldValue != chart else {
                return
            }

            invalidateLayout()
        }
    }
    var selectedMeasureID: UUID? {
        didSet {
            guard oldValue != selectedMeasureID else {
                return
            }

            if shouldFinalizeRhythmicNotation(from: oldValue, to: selectedMeasureID),
               let oldValue,
               !finalizeRhythmicNotationIfNeeded(for: oldValue) {
                restoreSelectedMeasureID(oldValue)
                return
            }

            syncPageInkCanvas()
            setNeedsDisplay()
        }
    }
    var selectedNoteSelection: LeadSheetNoteSelection? {
        didSet {
            guard oldValue != selectedNoteSelection else {
                return
            }

            setNeedsDisplay()
        }
    }
    var interactionMode: EditorCanvasMode = .browse {
        didSet {
            guard oldValue != interactionMode else {
                return
            }

            if oldValue.allowsAnyInkEditing && !interactionMode.allowsAnyInkEditing {
                persistActiveInkIfNeeded()
            }

            if oldValue.allowsNoteSelectionInk && !interactionMode.allowsNoteSelectionInk {
                clearNoteSelectionInk()
            }

            updateInteractionMode()
            syncPageInkCanvas()
            setNeedsDisplay()
        }
    }
    var onMeasureSelectionChanged: ((UUID?) -> Void)?
    var onChartChanged: ((Chart) -> Void)?
    var onTimeSignatureTargetRequested: ((UUID) -> Void)?
    var onRhythmicNotationProposal: ((UUID, [RhythmValue], Data) -> Void)?
    var onRhythmicNotationValidationError: ((String) -> Void)?
    var onNoteSelectionChanged: ((LeadSheetNoteSelection?) -> Void)?

    private var pageLayout: LeadSheetPageLayout?
    private let pageInkCanvasView = PKCanvasView()
    private lazy var selectionTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleTap(_:))
    )
    private lazy var inkSelectionTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleTap(_:))
    )
    private lazy var measureResizePanRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleMeasureResizePan(_:))
    )
    private var isSyncingInkCanvasFromModel = false
    private var pendingInkPersistWorkItem: DispatchWorkItem?
    private var activeMeasureResizeDrag: ActiveMeasureResizeDrag?
    private var isRestoringSelection = false
    private var isApplyingTapSelection = false
    private var notationRenderer: LeadSheetNotationRenderer {
        LeadSheetNotationRenderer(chart: chart)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateLayout()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let pageLayout else {
            return
        }

        let renderer = notationRenderer
        context.clear(rect)
        renderer.drawPaper(pageLayout.paperFrame, in: context)
        renderer.drawHeader(pageLayout.header)

        for system in pageLayout.systems {
            drawSystem(system, using: renderer)
        }

        if !interactionMode.allowsPageInkEditing {
            drawSavedPageInk()
        }

        if interactionMode.showsMeasureResizeHandles,
           let selectedMeasure = selectedMeasureLayout() {
            drawMeasureResizeHandles(for: selectedMeasure, using: renderer)
        }
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        selectionTapRecognizer.delegate = self
        addGestureRecognizer(selectionTapRecognizer)
        measureResizePanRecognizer.delegate = self
        selectionTapRecognizer.require(toFail: measureResizePanRecognizer)
        addGestureRecognizer(measureResizePanRecognizer)

        pageInkCanvasView.backgroundColor = .clear
        pageInkCanvasView.isOpaque = false
        pageInkCanvasView.delegate = self
        pageInkCanvasView.isScrollEnabled = false
        pageInkCanvasView.bounces = false
        pageInkCanvasView.alwaysBounceVertical = false
        pageInkCanvasView.alwaysBounceHorizontal = false
        pageInkCanvasView.drawingPolicy = .anyInput
        pageInkCanvasView.tool = PKInkingTool(.pen, color: UIColor(white: 0.06, alpha: 1), width: 2.8)
        inkSelectionTapRecognizer.delegate = self
        inkSelectionTapRecognizer.cancelsTouchesInView = false
        pageInkCanvasView.addGestureRecognizer(inkSelectionTapRecognizer)
        pageInkCanvasView.isHidden = true
        addSubview(pageInkCanvasView)
        updateInteractionMode()
    }

    private func invalidateLayout() {
        guard bounds.width > 0, bounds.height > 0 else {
            pageLayout = nil
            syncPageInkCanvas()
            setNeedsDisplay()
            return
        }

        pageLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: bounds.size)
        syncPageInkCanvas()
        setNeedsDisplay()
    }

    private func drawSystem(_ system: LeadSheetSystemLayout, using renderer: LeadSheetNotationRenderer) {
        if let sectionTextFrame = system.sectionTextFrame,
           let sectionText = system.sectionText {
            renderer.drawSectionText(sectionText, in: sectionTextFrame)
        }

        if let roadmapTextFrame = system.roadmapTextFrame,
           let roadmapText = system.roadmapText {
            renderer.drawRoadmapText(roadmapText, in: roadmapTextFrame)
        }

        renderer.drawStaffLines(for: system)

        if let clefFrame = system.clefFrame {
            renderer.drawClef(in: clefFrame)
        }

        if let timeSignatureFrame = system.timeSignatureFrame {
            renderer.drawTimeSignature(chart.defaultMeter, in: timeSignatureFrame)
        }

        if let firstMeasure = system.measures.first {
            renderer.drawSingleBarline(
                at: firstMeasure.frame.minX,
                from: firstMeasure.staffFrame.minY,
                to: firstMeasure.staffFrame.maxY
            )
        }

        for measure in system.measures {
            if measure.sourceMeasureID == selectedMeasureID {
                drawMeasureSelection(measure)
            }

            for chordLayout in measure.chordLayouts {
                renderer.drawChord(chordLayout)
            }

            for (noteIndex, noteLayout) in measure.noteLayouts.enumerated() {
                if isSelectedNote(noteIndex: noteIndex, in: measure) {
                    drawNoteSelection(noteLayout)
                }
                renderer.drawNote(noteLayout)
            }

            drawSavedMeasureRhythmicNotation(measure)

            if let trailingMeterChange = measure.trailingMeterChange,
               let trailingMeterChangeFrame = measure.trailingMeterChangeFrame {
                renderer.drawTimeSignature(trailingMeterChange, in: trailingMeterChangeFrame)
            }

            if measure.isOpen {
                renderer.drawOpenMeasureHint(measure)
            } else {
                renderer.drawBarline(measure.barlineAfter, in: measure.trailingBarlineFrame)
            }
        }
    }

    private func drawMeasureSelection(_ measure: LeadSheetMeasureLayout) {
        let selectionRect = measure.frame.insetBy(dx: 2, dy: 10)
        let selectionPath = UIBezierPath(roundedRect: selectionRect, cornerRadius: 8)
        UIColor(red: 0.89, green: 0.94, blue: 1, alpha: 0.42).setFill()
        selectionPath.fill()
        UIColor(red: 0.21, green: 0.43, blue: 0.83, alpha: 0.45).setStroke()
        selectionPath.lineWidth = 1.2
        selectionPath.stroke()
    }

    private func drawNoteSelection(_ noteLayout: LeadSheetNoteLayout) {
        let selectionRect = noteLayout.selectionFrame.insetBy(dx: -3, dy: -3)
        let selectionPath = UIBezierPath(roundedRect: selectionRect, cornerRadius: 9)
        UIColor(red: 1.0, green: 0.85, blue: 0.18, alpha: 0.28).setFill()
        selectionPath.fill()
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.84).setStroke()
        selectionPath.lineWidth = 1.4
        selectionPath.stroke()
    }

    private func isSelectedNote(noteIndex: Int, in measure: LeadSheetMeasureLayout) -> Bool {
        guard let sourceMeasureID = measure.sourceMeasureID,
              let selectedNoteSelection else {
            return false
        }

        return selectedNoteSelection.measureID == sourceMeasureID
            && selectedNoteSelection.noteIndex == noteIndex
    }

    private func drawMeasureResizeHandles(
        for measure: LeadSheetMeasureLayout,
        using renderer: LeadSheetNotationRenderer
    ) {
        let handleRects = measureResizeHandleRects(for: measure)
        drawMeasureResizeHandle(handleRects.left, symbol: "⇠", using: renderer)
        drawMeasureResizeHandle(handleRects.right, symbol: "⇢", using: renderer)
    }

    private func drawMeasureResizeHandle(
        _ rect: CGRect,
        symbol: String,
        using renderer: LeadSheetNotationRenderer
    ) {
        let handlePath = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        UIColor.white.withAlphaComponent(0.95).setFill()
        handlePath.fill()
        UIColor(red: 0.18, green: 0.38, blue: 0.78, alpha: 0.88).setStroke()
        handlePath.lineWidth = 1.2
        handlePath.stroke()

        renderer.drawText(
            symbol,
            in: rect.insetBy(dx: 1, dy: 3),
            font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            color: UIColor(red: 0.16, green: 0.33, blue: 0.68, alpha: 1),
            alignment: .center
        )
    }

    private func drawSavedPageInk() {
        guard let pageLayout,
              let drawingData = chart.pageHandwrittenNotationData,
              let drawing = try? PKDrawing(data: drawingData),
              !drawing.strokes.isEmpty else {
            return
        }

        let writingFrame = pageWritingFrame(for: pageLayout)
        let image = drawing.image(
            from: CGRect(origin: .zero, size: writingFrame.size),
            scale: UIScreen.main.scale
        )
        image.draw(in: writingFrame)
    }

    private func drawSavedMeasureRhythmicNotation(_ measure: LeadSheetMeasureLayout) {
        guard let sourceMeasureID = measure.sourceMeasureID,
              let drawingData = chart.measure(id: sourceMeasureID)?.handwrittenRhythmicNotationData,
              let drawing = try? PKDrawing(data: drawingData),
              !drawing.strokes.isEmpty else {
            return
        }

        if interactionMode.allowsDirectRhythmicNotationInk,
           selectedMeasureID == sourceMeasureID {
            return
        }

        let image = drawing.image(
            from: CGRect(origin: .zero, size: measure.writableFrame.size),
            scale: UIScreen.main.scale
        )
        image.draw(in: measure.writableFrame)
    }

    private func selectedMeasureLayout() -> LeadSheetMeasureLayout? {
        guard let selectedMeasureID else {
            return nil
        }

        return measureLayout(for: selectedMeasureID)
    }

    private func measureLayout(for measureID: UUID) -> LeadSheetMeasureLayout? {
        pageLayout?.systems
            .flatMap(\.measures)
            .first(where: { $0.sourceMeasureID == measureID })
    }

    private func measureResizeHandleRects(
        for measure: LeadSheetMeasureLayout
    ) -> (left: CGRect, right: CGRect) {
        let handleSize = CGSize(width: 18, height: 34)
        let handleY = measure.staffFrame.midY - handleSize.height / 2
        let leftRect = CGRect(
            x: measure.frame.minX - handleSize.width / 2,
            y: handleY,
            width: handleSize.width,
            height: handleSize.height
        )
        let rightRect = CGRect(
            x: measure.frame.maxX - handleSize.width / 2,
            y: handleY,
            width: handleSize.width,
            height: handleSize.height
        )
        return (leftRect, rightRect)
    }

    private func measureResizeHandleHitTarget(at location: CGPoint) -> ActiveMeasureResizeDrag? {
        guard interactionMode.showsMeasureResizeHandles,
              let measure = selectedMeasureLayout(),
              let measureID = measure.sourceMeasureID else {
            return nil
        }

        let handleRects = measureResizeHandleRects(for: measure)
        let touchInsetX: CGFloat = -12
        let touchInsetY: CGFloat = -10

        if handleRects.left.insetBy(dx: touchInsetX, dy: touchInsetY).contains(location) {
            return ActiveMeasureResizeDrag(
                measureID: measureID,
                edge: .left,
                initialWidth: measure.frame.width
            )
        }

        if handleRects.right.insetBy(dx: touchInsetX, dy: touchInsetY).contains(location) {
            return ActiveMeasureResizeDrag(
                measureID: measureID,
                edge: .right,
                initialWidth: measure.frame.width
            )
        }

        return nil
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isSyncingInkCanvasFromModel else {
            return
        }

        schedulePersistActiveInk()
    }

    @objc
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        if interactionMode.allowsNoteSelection {
            handleNoteSelectionTap(at: recognizer.location(in: self))
            return
        }

        guard interactionMode.allowsMeasureSelection else {
            return
        }

        let location = recognizer.location(in: self)
        let tappedMeasure = measureLayout(at: location)
        let tappedMeasureID = tappedMeasure?.sourceMeasureID

        if shouldFinalizeRhythmicNotationTap(at: location, nextMeasureID: tappedMeasureID),
           let activeMeasureID = selectedMeasureID,
           !finalizeRhythmicNotationIfNeeded(for: activeMeasureID) {
            restoreSelectedMeasureID(activeMeasureID)
            return
        }

        applyTapSelection(tappedMeasureID)

        if interactionMode.showsTimeSignatureTargeting,
           let tappedMeasureID {
            onTimeSignatureTargetRequested?(tappedMeasureID)
        }
    }

    private func handleNoteSelectionTap(at location: CGPoint) {
        guard let pageLayout,
              pageLayout.paperFrame.contains(location) else {
            return
        }

        guard let lassoFrame = noteSelectionLassoFrame(ignoringTapAt: location) else {
            return
        }

        let selection = pageLayout.noteSelection(in: lassoFrame)
        selectedNoteSelection = selection
        onNoteSelectionChanged?(selection)

        if selection != nil {
            selectedMeasureID = nil
            onMeasureSelectionChanged?(nil)
        }

        clearNoteSelectionInk()
        clearNoteSelectionInkAfterPencilKitSettles()
        setNeedsDisplay()
    }

    @objc
    private func handleMeasureResizePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: self)
            activeMeasureResizeDrag = measureResizeHandleHitTarget(at: location)
        case .changed:
            guard let activeMeasureResizeDrag else {
                return
            }

            let translation = recognizer.translation(in: self)
            let signedDelta = activeMeasureResizeDrag.edge == .right
                ? translation.x
                : -translation.x
            let proposedWidth = activeMeasureResizeDrag.initialWidth + signedDelta

            var updatedChart = chart
            let appliedWidth = updatedChart.setMeasureManualLayoutWidth(
                proposedWidth,
                for: activeMeasureResizeDrag.measureID
            )
            guard appliedWidth != nil else {
                return
            }

            chart = updatedChart
            onChartChanged?(updatedChart)
        case .ended, .cancelled, .failed:
            activeMeasureResizeDrag = nil
        default:
            break
        }
    }

    private func syncPageInkCanvas() {
        guard let activeInkScope = activeInkScope() else {
            if !interactionMode.allowsAnyInkEditing {
                pageInkCanvasView.isHidden = true
                pageInkCanvasView.isUserInteractionEnabled = false
                return
            }

            persistActiveInkIfNeeded()
            pageInkCanvasView.isHidden = true
            return
        }

        pageInkCanvasView.isHidden = false
        pageInkCanvasView.isUserInteractionEnabled = true
        pageInkCanvasView.frame = activeInkScope.frame
        pageInkCanvasView.contentSize = activeInkScope.frame.size

        let desiredData = drawingData(for: activeInkScope)
        let currentData = currentCanvasDrawingData()
        guard currentData != desiredData else {
            return
        }

        isSyncingInkCanvasFromModel = true
        if let desiredData,
           let drawing = try? PKDrawing(data: desiredData) {
            pageInkCanvasView.drawing = drawing
        } else {
            pageInkCanvasView.drawing = PKDrawing()
        }
        isSyncingInkCanvasFromModel = false
        pageInkCanvasView.becomeFirstResponder()
    }

    private func schedulePersistActiveInk() {
        pendingInkPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistActiveInkIfNeeded()
        }
        pendingInkPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func persistActiveInkIfNeeded() {
        pendingInkPersistWorkItem?.cancel()
        pendingInkPersistWorkItem = nil

        guard let activeInkScope = activeInkScope() else {
            return
        }

        let drawingData = currentCanvasDrawingData()
        var updatedChart = chart

        switch activeInkScope {
        case .page:
            guard chart.pageHandwrittenNotationData != drawingData,
                  updatedChart.setPageHandwrittenNotationDrawing(drawingData) else {
                return
            }
        case .rhythmicMeasure(let measureID, _):
            guard chart.measure(id: measureID)?.handwrittenRhythmicNotationData != drawingData,
                  updatedChart.setMeasureHandwrittenRhythmicNotationDrawing(drawingData, for: measureID) else {
                return
            }
        case .noteSelection:
            return
        }

        chart = updatedChart
        onChartChanged?(updatedChart)
    }

    private func shouldFinalizeRhythmicNotation(from previousMeasureID: UUID?, to nextMeasureID: UUID?) -> Bool {
        interactionMode.allowsDirectRhythmicNotationInk
            && !isRestoringSelection
            && !isApplyingTapSelection
            && previousMeasureID != nil
            && previousMeasureID != nextMeasureID
    }

    private func shouldFinalizeRhythmicNotationTap(
        at location: CGPoint,
        nextMeasureID: UUID?
    ) -> Bool {
        guard interactionMode.allowsDirectRhythmicNotationInk,
              let activeMeasureID = selectedMeasureID,
              let activeMeasureLayout = measureLayout(for: activeMeasureID) else {
            return false
        }

        if nextMeasureID != activeMeasureID {
            return true
        }

        let activeWritingFrame = activeMeasureLayout.writableFrame.insetBy(dx: -8, dy: -8)
        return !activeWritingFrame.contains(location)
    }

    private func finalizeRhythmicNotationIfNeeded(for measureID: UUID) -> Bool {
        let liveDrawingData = currentCanvasDrawingData()
        var workingChart = chart
        if interactionMode.allowsDirectRhythmicNotationInk,
           workingChart.setMeasureHandwrittenRhythmicNotationDrawing(liveDrawingData, for: measureID) {
            chart = workingChart
            onChartChanged?(workingChart)
        }

        guard let measure = workingChart.measure(id: measureID),
              let drawingData = measure.handwrittenRhythmicNotationData,
              !drawingData.isEmpty,
              let measureLayout = measureLayout(for: measureID) else {
            return true
        }

        do {
            let quantizedValues = try RhythmicNotationQuantizer.quantize(
                drawingData: drawingData,
                meter: measure.resolvedMeter(defaultMeter: chart.defaultMeter),
                drawingFrame: CGRect(
                    origin: .zero,
                    size: measureLayout.writableFrame.insetBy(dx: 2, dy: 2).size
                )
            )

            if let onRhythmicNotationProposal {
                onRhythmicNotationProposal(measureID, quantizedValues, drawingData)
                return false
            }

            var updatedChart = workingChart
            let appliedRhythmMap = updatedChart.setMeasureRhythmMap(
                quantizedValues,
                drawingData: drawingData,
                for: measureID
            )
            let clearedInk = updatedChart.clearMeasureRhythmicNotation(
                for: measureID,
                clearRhythmMap: false
            )

            if appliedRhythmMap || clearedInk {
                chart = updatedChart
                onChartChanged?(updatedChart)
            }

            return true
        } catch let error as RhythmicNotationQuantizationError {
            onRhythmicNotationValidationError?(error.userFacingMessage)
            return false
        } catch {
            onRhythmicNotationValidationError?(
                "That rhythm couldn’t be matched yet. The measure is still selected so you can adjust or rewrite it."
            )
            return false
        }
    }

    private func restoreSelectedMeasureID(_ measureID: UUID?) {
        guard !isRestoringSelection else {
            return
        }

        isRestoringSelection = true
        selectedMeasureID = measureID
        isRestoringSelection = false

        DispatchQueue.main.async { [weak self] in
            self?.onMeasureSelectionChanged?(measureID)
        }
    }

    private func applyTapSelection(_ measureID: UUID?) {
        isApplyingTapSelection = true
        selectedMeasureID = measureID
        isApplyingTapSelection = false
        onMeasureSelectionChanged?(measureID)
    }

    private func currentCanvasDrawingData() -> Data? {
        let drawing = pageInkCanvasView.drawing
        return drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
    }

    private func updateInteractionMode() {
        selectionTapRecognizer.isEnabled = interactionMode.allowsMeasureSelection || interactionMode.allowsNoteSelection
        inkSelectionTapRecognizer.isEnabled = interactionMode.allowsNoteSelection
        measureResizePanRecognizer.isEnabled = interactionMode.showsMeasureResizeHandles
        pageInkCanvasView.isUserInteractionEnabled = interactionMode.allowsAnyInkEditing
        updateInkTool()

        if !interactionMode.showsMeasureResizeHandles {
            activeMeasureResizeDrag = nil
        }

        if !interactionMode.allowsAnyInkEditing {
            pageInkCanvasView.isHidden = true
            pageInkCanvasView.resignFirstResponder()
        }
    }

    private func updateInkTool() {
        if interactionMode.allowsNoteSelectionInk {
            pageInkCanvasView.tool = PKInkingTool(
                .pen,
                color: UIColor(red: 0.12, green: 0.36, blue: 0.88, alpha: 0.9),
                width: 2.4
            )
        } else {
            pageInkCanvasView.tool = PKInkingTool(.pen, color: UIColor(white: 0.06, alpha: 1), width: 2.8)
        }
    }

    private func clearNoteSelectionInk() {
        guard !pageInkCanvasView.drawing.strokes.isEmpty else {
            return
        }

        isSyncingInkCanvasFromModel = true
        pageInkCanvasView.drawing = PKDrawing()
        isSyncingInkCanvasFromModel = false
    }

    private func clearNoteSelectionInkAfterPencilKitSettles() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  interactionMode.allowsNoteSelectionInk else {
                return
            }

            clearNoteSelectionInk()
        }
    }

    private func pageWritingFrame(for pageLayout: LeadSheetPageLayout) -> CGRect {
        pageLayout.paperFrame.insetBy(dx: 10, dy: 10)
    }

    private func activeInkScope() -> ActiveInkScope? {
        if interactionMode.allowsDirectRhythmicNotationInk,
           let selectedMeasureID,
           let targetMeasureLayout = measureLayout(for: selectedMeasureID) {
            return .rhythmicMeasure(
                measureID: selectedMeasureID,
                frame: targetMeasureLayout.writableFrame.insetBy(dx: 2, dy: 2)
            )
        }

        if interactionMode.allowsNoteSelectionInk,
           let pageLayout {
            return .noteSelection(frame: pageWritingFrame(for: pageLayout))
        }

        guard interactionMode.allowsPageInkEditing else {
            return nil
        }

        guard let pageLayout else {
            return nil
        }

        return .page(frame: pageWritingFrame(for: pageLayout))
    }

    private func drawingData(for inkScope: ActiveInkScope) -> Data? {
        switch inkScope {
        case .page:
            return chart.pageHandwrittenNotationData
        case .rhythmicMeasure(let measureID, _):
            return chart.measure(id: measureID)?.handwrittenRhythmicNotationData
        case .noteSelection:
            return nil
        }
    }

    private func noteSelectionLassoFrame(ignoringTapAt tapLocation: CGPoint) -> CGRect? {
        guard let activeInkScope = activeInkScope() else {
            return nil
        }

        let tapLocationInInkScope = CGPoint(
            x: tapLocation.x - activeInkScope.frame.minX,
            y: tapLocation.y - activeInkScope.frame.minY
        )
        let lassoBounds = pageInkCanvasView.drawing.strokes.reduce(CGRect?.none) { partialResult, stroke in
            let strokeBounds = stroke.renderBounds
            guard !isIncidentalTapStroke(strokeBounds, near: tapLocationInInkScope) else {
                return partialResult
            }

            return partialResult?.union(strokeBounds) ?? strokeBounds
        }

        guard let lassoBounds,
              !lassoBounds.isNull,
              lassoBounds.width >= 10,
              lassoBounds.height >= 10 else {
            return nil
        }

        return lassoBounds
            .offsetBy(dx: activeInkScope.frame.minX, dy: activeInkScope.frame.minY)
            .insetBy(dx: -4, dy: -4)
    }

    private func isIncidentalTapStroke(_ strokeBounds: CGRect, near tapLocation: CGPoint) -> Bool {
        let maximumTapDotSize: CGFloat = 12
        let tapSlop: CGFloat = 18
        guard strokeBounds.width <= maximumTapDotSize,
              strokeBounds.height <= maximumTapDotSize else {
            return false
        }

        return interactionMode.allowsNoteSelection
            || strokeBounds.insetBy(dx: -tapSlop, dy: -tapSlop).contains(tapLocation)
    }

    private func measureLayout(at location: CGPoint) -> LeadSheetMeasureLayout? {
        pageLayout?.systems
            .flatMap(\.measures)
            .first(where: { $0.frame.insetBy(dx: -6, dy: -6).contains(location) })
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === measureResizePanRecognizer {
            let location = gestureRecognizer.location(in: self)
            return measureResizeHandleHitTarget(at: location) != nil
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === inkSelectionTapRecognizer || otherGestureRecognizer === inkSelectionTapRecognizer
    }
}

private struct ActiveMeasureResizeDrag {
    enum Edge {
        case left
        case right
    }

    var measureID: UUID
    var edge: Edge
    var initialWidth: CGFloat
}

private enum ActiveInkScope {
    case page(frame: CGRect)
    case rhythmicMeasure(measureID: UUID, frame: CGRect)
    case noteSelection(frame: CGRect)

    var frame: CGRect {
        switch self {
        case .page(let frame), .rhythmicMeasure(_, let frame), .noteSelection(let frame):
            return frame
        }
    }
}
#endif

#if canImport(UIKit)
import Foundation
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
    var onChordInkRecognitionProposal: ((UUID, ChordInkRecognitionResult, Data, Double?) -> Void)? = nil
    var onChordCorrectionRequested: ((UUID) -> Void)? = nil
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
        configure(view, context: context)
        return view
    }

    func updateUIView(_ uiView: LeadSheetCanvasUIKitView, context: Context) {
        configure(uiView, context: context)
    }

    private func configure(_ view: LeadSheetCanvasUIKitView, context: Context) {
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
        view.onChordInkRecognitionProposal = onChordInkRecognitionProposal
        view.onChordCorrectionRequested = onChordCorrectionRequested
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
    var onChordInkRecognitionProposal: ((UUID, ChordInkRecognitionResult, Data, Double?) -> Void)?
    var onChordCorrectionRequested: ((UUID) -> Void)?
    var onNoteSelectionChanged: ((LeadSheetNoteSelection?) -> Void)?

    private var pageLayout: LeadSheetPageLayout?
    private let pageInkCanvasView = PKCanvasView()
    private let chordEditHitOverlayView = ChordEditHitOverlayView()
    private let chordInkRecognizer = ChordInkRecognizer()
    private var chordInkRecognitionOptions: ChordInkRecognitionOptions {
        #if DEBUG || targetEnvironment(simulator)
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-SmartChartSymbolLedgerDiagnostics")
            || processInfo.environment["SMART_CHART_SYMBOL_LEDGER_DIAGNOSTICS"] == "1" {
            return .includingSymbolLedgerDiagnostics
        }
        #endif

        return .live
    }
    private let chordOCRCandidateProvider = ChordOCRCandidateProviderFactory.liveProvider()
    private let chordInkIdleDelay: TimeInterval = 1.2
    private let chordInkContinuationGraceDelay: TimeInterval = 1.2
    private let chordInkRecognitionQueue = DispatchQueue(
        label: "com.smartchart.chord-ink-recognition",
        qos: .userInitiated
    )
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
    private lazy var chordMovePanRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleChordMovePan(_:))
    )
    private lazy var chordEditTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(handleChordEditTap(_:))
    )
    private var isSyncingInkCanvasFromModel = false
    private var pendingInkPersistWorkItem: DispatchWorkItem?
    private var pendingChordRecognitionWorkItem: DispatchWorkItem?
    private var activeChordRecognitionRequestID: UUID?
    private var lastRecognizedChordDrawingData: Data?
    private var chordInkContinuationGraceDrawingData: Data?
    private var activeMeasureResizeDrag: ActiveMeasureResizeDrag?
    private var activeChordMoveDrag: ActiveChordMoveDrag?
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
        chordEditHitOverlayView.frame = bounds
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

        if !interactionMode.allowsChordInkEditing {
            drawSavedChordInk()
        }

        if interactionMode.allowsChordInkEditing {
            drawChordWritingLanes(pageLayout)
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

        chordEditHitOverlayView.backgroundColor = .clear
        chordEditHitOverlayView.isOpaque = false
        chordEditHitOverlayView.isHidden = true
        chordEditHitOverlayView.containsEditableControl = { [weak self] location in
            self?.chordEditHitTarget(at: location) != nil
        }
        chordEditTapRecognizer.delegate = self
        chordEditHitOverlayView.addGestureRecognizer(chordEditTapRecognizer)
        chordMovePanRecognizer.delegate = self
        chordEditHitOverlayView.addGestureRecognizer(chordMovePanRecognizer)
        addSubview(chordEditHitOverlayView)
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
            if interactionMode.allowsMeasureSelection,
               measure.sourceMeasureID == selectedMeasureID {
                drawMeasureSelection(measure)
            }

            for chordLayout in measure.chordLayouts {
                renderer.drawChord(chordLayout)
                if interactionMode.allowsChordInkEditing,
                   measure.sourceMeasureID != nil {
                    drawChordEditOverlay(for: chordLayout, using: renderer)
                }
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
        let handleRects = LeadSheetMeasureResizeGeometry.handleFrames(for: measure)
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
        guard let pageLayout else {
            return
        }

        LeadSheetSavedInkRenderer.drawPageInk(chart.pageHandwrittenNotationData, in: pageLayout)
    }

    private func drawSavedChordInk() {
        guard let pageLayout else {
            return
        }

        LeadSheetSavedInkRenderer.drawChordInk(chart.pageHandwrittenChordData, in: pageLayout)
    }

    private func drawChordWritingLanes(_ pageLayout: LeadSheetPageLayout) {
        for system in pageLayout.systems {
            let measureFrames = system.measures.map(\.chordBandFrame)
            guard let firstFrame = measureFrames.first else {
                continue
            }

            let laneFrame = measureFrames
                .dropFirst()
                .reduce(firstFrame) { partialFrame, measureFrame in
                    partialFrame.union(measureFrame)
                }
                .insetBy(dx: -2, dy: -2)
            let lanePath = UIBezierPath(roundedRect: laneFrame, cornerRadius: 7)
            UIColor(red: 0.18, green: 0.36, blue: 0.78, alpha: 0.06).setFill()
            lanePath.fill()
            UIColor(red: 0.18, green: 0.36, blue: 0.78, alpha: 0.18).setStroke()
            lanePath.lineWidth = 1
            lanePath.setLineDash([5, 4], count: 2, phase: 0)
            lanePath.stroke()
        }
    }

    private func drawChordEditOverlay(
        for chordLayout: LeadSheetChordLayout,
        using renderer: LeadSheetNotationRenderer
    ) {
        let editFrame = LeadSheetChordEditOverlayGeometry.editFrame(for: chordLayout)
        let controlFrames = LeadSheetChordEditOverlayGeometry.controlFrames(for: chordLayout)

        let boxPath = UIBezierPath(roundedRect: editFrame, cornerRadius: 5)
        UIColor(red: 0.88, green: 0.93, blue: 1, alpha: 0.18).setFill()
        boxPath.fill()
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.62).setStroke()
        boxPath.lineWidth = 1
        boxPath.stroke()

        let deletePath = UIBezierPath(ovalIn: controlFrames.delete)
        UIColor.white.withAlphaComponent(0.96).setFill()
        deletePath.fill()
        UIColor(red: 0.92, green: 0.16, blue: 0.20, alpha: 0.86).setStroke()
        deletePath.lineWidth = 1
        deletePath.stroke()
        renderer.drawText(
            "x",
            in: controlFrames.delete.insetBy(dx: 1, dy: -1),
            font: UIFont.systemFont(ofSize: 10, weight: .bold),
            color: UIColor(red: 0.82, green: 0.08, blue: 0.12, alpha: 1),
            alignment: .center
        )

        let movePath = UIBezierPath(ovalIn: controlFrames.move)
        UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.88).setFill()
        movePath.fill()
        UIColor.white.withAlphaComponent(0.95).setStroke()
        movePath.lineWidth = 1
        movePath.stroke()
    }

    private func drawSavedMeasureRhythmicNotation(_ measure: LeadSheetMeasureLayout) {
        guard let sourceMeasureID = measure.sourceMeasureID else {
            return
        }

        if interactionMode.allowsDirectRhythmicNotationInk,
           selectedMeasureID == sourceMeasureID {
            return
        }

        LeadSheetSavedInkRenderer.drawRhythmicNotationInk(
            chart.measure(id: sourceMeasureID)?.handwrittenRhythmicNotationData,
            in: measure
        )
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

    private func measureResizeHandleHitTarget(at location: CGPoint) -> ActiveMeasureResizeDrag? {
        guard interactionMode.showsMeasureResizeHandles,
              let measure = selectedMeasureLayout() else {
            return nil
        }

        return LeadSheetMeasureResizeGeometry.hitTarget(at: location, in: measure)
    }

    private func chordEditHitTarget(at location: CGPoint) -> ChordEditHitTarget? {
        guard interactionMode.allowsChordInkEditing,
              let pageLayout else {
            return nil
        }

        return LeadSheetChordEditOverlayGeometry.hitTarget(at: location, in: pageLayout)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isSyncingInkCanvasFromModel else {
            return
        }

        schedulePersistActiveInk()
    }

    @objc
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        if interactionMode.allowsChordInkEditing {
            handleChordEntryTap(at: recognizer.location(in: self))
            return
        }

        if interactionMode.allowsNoteSelection {
            handleNoteSelectionTap(at: recognizer.location(in: self))
            return
        }

        guard interactionMode.allowsMeasureSelection else {
            return
        }

        let location = recognizer.location(in: self)
        let tappedMeasure = LeadSheetCanvasInteractionTargeting.measure(at: location, in: pageLayout)
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

    @objc
    private func handleChordEditTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        let location = recognizer.location(in: chordEditHitOverlayView)
        guard let hitTarget = chordEditHitTarget(at: location) else {
            return
        }

        switch hitTarget.action {
        case .delete:
            deleteChordEvent(hitTarget.chordID)
        case .move:
            break
        case .review:
            onChordCorrectionRequested?(hitTarget.chordID)
        }
    }

    private func handleChordEntryTap(at location: CGPoint) {
        guard let pageLayout else {
            return
        }

        if let hitTarget = chordEditHitTarget(at: location) {
            switch hitTarget.action {
            case .delete:
                deleteChordEvent(hitTarget.chordID)
            case .move:
                break
            case .review:
                onChordCorrectionRequested?(hitTarget.chordID)
            }
            return
        }

        if LeadSheetCanvasInteractionTargeting.chordWritingBandContains(location, in: pageLayout) {
            return
        }
    }

    private func deleteChordEvent(_ chordID: UUID) {
        var updatedChart = chart
        guard updatedChart.deleteChordEvent(chordID) else {
            return
        }

        chart = updatedChart
        onChartChanged?(updatedChart)
        setNeedsDisplay()
    }

    private func handleNoteSelectionTap(at location: CGPoint) {
        guard let pageLayout,
              pageLayout.paperFrame.contains(location) else {
            return
        }

        guard let lassoFrame = LeadSheetNoteSelectionLassoTargeting.lassoFrame(
            for: pageInkCanvasView.drawing,
            activeInkScope: activeInkScope(),
            ignoringTapAt: location,
            allowsNoteSelection: interactionMode.allowsNoteSelection
        ) else {
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

    @objc
    private func handleChordMovePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: self)
            guard let hitTarget = chordEditHitTarget(at: location),
                  hitTarget.action == .move else {
                activeChordMoveDrag = nil
                return
            }

            activeChordMoveDrag = ActiveChordMoveDrag(chordID: hitTarget.chordID)
        case .changed, .ended:
            guard let activeChordMoveDrag,
                  let target = LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                    at: recognizer.location(in: self),
                    in: pageLayout
                  ) else {
                if recognizer.state == .ended {
                    self.activeChordMoveDrag = nil
                }
                return
            }

            var updatedChart = chart
            guard updatedChart.moveChordEvent(
                activeChordMoveDrag.chordID,
                to: target.measureID,
                atFraction: target.fraction
            ) else {
                return
            }

            chart = updatedChart
            onChartChanged?(updatedChart)
            setNeedsDisplay()

            if recognizer.state == .ended {
                self.activeChordMoveDrag = nil
            }
        case .cancelled, .failed:
            activeChordMoveDrag = nil
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

        let desiredData = activeInkScope.drawingData(in: chart)
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
        if interactionMode.allowsChordInkEditing {
            scheduleChordInkRecognition()
            return
        }

        pendingInkPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistActiveInkIfNeeded()
        }
        pendingInkPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func scheduleChordInkRecognition() {
        scheduleChordInkRecognition(
            after: LeadSheetChordInkRecognitionScheduling.idleDelay(
                for: pageInkCanvasView.drawing,
                defaultDelay: chordInkIdleDelay
            )
        )
    }

    private func scheduleChordInkRecognition(after requestedDelay: TimeInterval) {
        pendingInkPersistWorkItem?.cancel()
        pendingInkPersistWorkItem = nil
        pendingChordRecognitionWorkItem?.cancel()

        let requestID = UUID()
        let scheduledAt = Date()
        activeChordRecognitionRequestID = requestID
        let workItem = DispatchWorkItem { [weak self] in
            self?.recognizeChordInkIfNeeded(
                requestID: requestID,
                scheduledAt: scheduledAt,
                requestedDelay: requestedDelay
            )
        }
        pendingChordRecognitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + requestedDelay, execute: workItem)
    }

    private func persistActiveInkIfNeeded() {
        pendingInkPersistWorkItem?.cancel()
        pendingInkPersistWorkItem = nil
        pendingChordRecognitionWorkItem?.cancel()
        pendingChordRecognitionWorkItem = nil
        activeChordRecognitionRequestID = nil

        guard let activeInkScope = activeInkScope() else {
            return
        }

        let drawingData = currentCanvasDrawingData()
        guard let updatedChart = activeInkScope.chartByPersistingDrawingData(drawingData, in: chart) else {
            return
        }

        chart = updatedChart
        onChartChanged?(updatedChart)
    }

    private func recognizeChordInkIfNeeded(
        requestID: UUID,
        scheduledAt: Date,
        requestedDelay: TimeInterval
    ) {
        pendingChordRecognitionWorkItem?.cancel()
        pendingChordRecognitionWorkItem = nil

        guard activeChordRecognitionRequestID == requestID else {
            return
        }

        guard interactionMode.allowsChordInkEditing,
              let activeInkScope = activeInkScope(),
              case .chords(let chordFrame) = activeInkScope,
              let drawingData = currentCanvasDrawingData(),
              drawingData != lastRecognizedChordDrawingData,
              let target = LeadSheetChordInkRecognitionTargeting.target(
                for: pageInkCanvasView.drawing,
                chordFrame: chordFrame,
                pageLayout: pageLayout
              ) else {
            activeChordRecognitionRequestID = nil
            return
        }
        let strokes = PencilKitInkAdapter.inkStrokes(from: pageInkCanvasView.drawing)
        let drawingForOCR = pageInkCanvasView.drawing

        let recognizer = chordInkRecognizer
        let recognitionOptions = chordInkRecognitionOptions
        let ocrCandidateProvider = chordOCRCandidateProvider
        chordInkRecognitionQueue.async { [weak self] in
            let recognitionStartedAt = Date()
            var result = recognizer.recognize(
                strokes: strokes,
                options: recognitionOptions
            )
            let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
            if ChordRecognitionTrustArbiter.shouldRequestOCR(
                for: result,
                primaryDecision: primaryDecision
            ),
               let ocrCandidateProvider,
               self != nil,
               let ocrImage = LeadSheetChordInkImageRenderer.ocrImage(for: drawingForOCR) {
                let ocrStartedAt = Date()
                result.ocrCandidates = ocrCandidateProvider.recognizeCandidates(in: ocrImage)
                result.metrics.ocrMilliseconds = Date().timeIntervalSince(ocrStartedAt) * 1_000
            }
            let recognitionFinishedAt = Date()
            DispatchQueue.main.async { [weak self] in
                self?.finishChordInkRecognition(
                    requestID: requestID,
                    result: result,
                    drawingData: drawingData,
                    target: target,
                    timing: ChordInkRecognitionTiming(
                        scheduledAt: scheduledAt,
                        requestedDelay: requestedDelay,
                        recognitionStartedAt: recognitionStartedAt,
                        recognitionFinishedAt: recognitionFinishedAt,
                        strokeCount: strokes.count,
                        ocrCandidateCount: result.ocrCandidates?.count ?? 0
                    )
                )
            }
        }
    }

    private func finishChordInkRecognition(
        requestID: UUID,
        result: ChordInkRecognitionResult,
        drawingData: Data,
        target: (measureID: UUID, fraction: Double),
        timing: ChordInkRecognitionTiming
    ) {
        guard activeChordRecognitionRequestID == requestID else {
            return
        }
        activeChordRecognitionRequestID = nil

        LeadSheetChordInkRecognitionTimingLogger.log(timing, result: result)

        guard interactionMode.allowsChordInkEditing,
              !result.rawCandidates.isEmpty else {
            return
        }

        if shouldGiveChordInkContinuationGrace(
            result: result,
            drawingData: drawingData,
            timing: timing
        ) {
            chordInkContinuationGraceDrawingData = drawingData
            scheduleChordInkRecognition(after: chordInkContinuationGraceDelay)
            return
        }

        chordInkContinuationGraceDrawingData = nil
        lastRecognizedChordDrawingData = drawingData
        onChordInkRecognitionProposal?(
            target.measureID,
            result,
            drawingData,
            target.fraction
        )
    }

    private func shouldGiveChordInkContinuationGrace(
        result: ChordInkRecognitionResult,
        drawingData: Data,
        timing: ChordInkRecognitionTiming
    ) -> Bool {
        LeadSheetChordInkRecognitionScheduling.shouldGiveContinuationGrace(
            previousDrawingData: chordInkContinuationGraceDrawingData,
            drawingData: drawingData,
            timing: timing,
            idleDelay: chordInkIdleDelay,
            result: result
        )
    }

    private func shouldFinalizeRhythmicNotation(from previousMeasureID: UUID?, to nextMeasureID: UUID?) -> Bool {
        LeadSheetRhythmicNotationFinalization.shouldFinalizeSelectionChange(
            interactionMode: interactionMode,
            isRestoringSelection: isRestoringSelection,
            isApplyingTapSelection: isApplyingTapSelection,
            previousMeasureID: previousMeasureID,
            nextMeasureID: nextMeasureID
        )
    }

    private func shouldFinalizeRhythmicNotationTap(
        at location: CGPoint,
        nextMeasureID: UUID?
    ) -> Bool {
        LeadSheetRhythmicNotationFinalization.shouldFinalizeTap(
            interactionMode: interactionMode,
            selectedMeasureID: selectedMeasureID,
            activeMeasureLayout: selectedMeasureID.flatMap { measureLayout(for: $0) },
            location: location,
            nextMeasureID: nextMeasureID
        )
    }

    private func finalizeRhythmicNotationIfNeeded(for measureID: UUID) -> Bool {
        let liveDrawingData = currentCanvasDrawingData()
        var workingChart = chart
        if interactionMode.allowsDirectRhythmicNotationInk,
           let updatedChart = LeadSheetRhythmicNotationFinalization.chartByPersistingLiveDrawing(
               liveDrawingData,
               for: measureID,
               in: workingChart
           ) {
            chart = updatedChart
            onChartChanged?(updatedChart)
            workingChart = updatedChart
        }

        guard let measure = workingChart.measure(id: measureID),
              let drawingData = measure.handwrittenRhythmicNotationData,
              !drawingData.isEmpty,
              let measureLayout = measureLayout(for: measureID) else {
            return true
        }

        do {
            let quantizedValues = try LeadSheetRhythmicNotationFinalization.quantize(
                drawingData: drawingData,
                measure: measure,
                defaultMeter: chart.defaultMeter,
                measureLayout: measureLayout
            )

            if let onRhythmicNotationProposal {
                onRhythmicNotationProposal(measureID, quantizedValues, drawingData)
                return false
            }

            if let updatedChart = LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
                quantizedValues,
                drawingData: drawingData,
                for: measureID,
                in: workingChart
            ) {
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
        inkSelectionTapRecognizer.isEnabled = interactionMode.allowsNoteSelection || interactionMode.allowsChordInkEditing
        measureResizePanRecognizer.isEnabled = interactionMode.showsMeasureResizeHandles
        chordEditTapRecognizer.isEnabled = interactionMode.allowsChordInkEditing
        chordMovePanRecognizer.isEnabled = interactionMode.allowsChordInkEditing
        chordEditHitOverlayView.isHidden = !interactionMode.allowsChordInkEditing
        chordEditHitOverlayView.isUserInteractionEnabled = interactionMode.allowsChordInkEditing
        pageInkCanvasView.isUserInteractionEnabled = interactionMode.allowsAnyInkEditing
        updateInkTool()

        if !interactionMode.showsMeasureResizeHandles {
            activeMeasureResizeDrag = nil
        }

        if !interactionMode.allowsChordInkEditing {
            activeChordMoveDrag = nil
            pendingChordRecognitionWorkItem?.cancel()
            pendingChordRecognitionWorkItem = nil
            activeChordRecognitionRequestID = nil
            lastRecognizedChordDrawingData = nil
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
        } else if interactionMode.allowsChordInkEditing {
            pageInkCanvasView.tool = PKInkingTool(
                .pen,
                color: UIColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1),
                width: 2.5
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

    private func activeInkScope() -> LeadSheetActiveInkScope? {
        LeadSheetActiveInkScope.resolve(
            interactionMode: interactionMode,
            selectedMeasureID: selectedMeasureID,
            selectedMeasureLayout: selectedMeasureID.flatMap { measureLayout(for: $0) },
            pageLayout: pageLayout
        )
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === measureResizePanRecognizer {
            let location = gestureRecognizer.location(in: self)
            return measureResizeHandleHitTarget(at: location) != nil
        }

        if gestureRecognizer === chordMovePanRecognizer {
            let location = gestureRecognizer.location(in: self)
            return chordEditHitTarget(at: location)?.action == .move
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

#endif

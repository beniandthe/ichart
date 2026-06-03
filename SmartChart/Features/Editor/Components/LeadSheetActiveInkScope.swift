#if canImport(UIKit)
import Foundation
import UIKit

enum LeadSheetActiveInkScope {
    case page(frame: CGRect)
    case header(frame: CGRect)
    case chords(frame: CGRect)
    case rhythmicMeasure(measureID: UUID, frame: CGRect)
    case noteSelection(frame: CGRect)
    case freehandSymbols(frame: CGRect)

    var frame: CGRect {
        switch self {
        case .page(let frame),
             .header(let frame),
             .chords(let frame),
             .rhythmicMeasure(_, let frame),
             .noteSelection(let frame),
             .freehandSymbols(let frame):
            return frame
        }
    }

    static func resolve(
        interactionMode: EditorCanvasMode,
        chartLayoutStyle: ChartLayoutStyle,
        selectedMeasureID: UUID?,
        selectedMeasureLayout: LeadSheetMeasureLayout?,
        pageLayout: LeadSheetPageLayout?
    ) -> LeadSheetActiveInkScope? {
        if interactionMode.allowsDirectRhythmicNotationInk,
           chartLayoutStyle.profile.allowsRhythmicNotationInk,
           let selectedMeasureID,
           let selectedMeasureLayout {
            return .rhythmicMeasure(
                measureID: selectedMeasureID,
                frame: selectedMeasureLayout.writableFrame.insetBy(dx: 2, dy: 2)
            )
        }

        if interactionMode.allowsNoteSelectionInk,
           let pageLayout {
            return .noteSelection(frame: pageWritingFrame(for: pageLayout))
        }

        if interactionMode.allowsHeaderInkEditing,
           let pageLayout {
            return .header(frame: pageLayout.header.handwrittenFrame)
        }

        if interactionMode.allowsChordInkEditing,
           let pageLayout {
            return .chords(frame: chordWritingFrame(for: pageLayout))
        }

        guard interactionMode.allowsPageInkEditing,
              let pageLayout else {
            return nil
        }

        guard chartLayoutStyle.profile.allowsFreehandSymbolInk else {
            return nil
        }

        return .freehandSymbols(
            frame: freehandSymbolWritingFrame(
                for: pageLayout,
                layoutStyle: chartLayoutStyle
            )
        )
    }

    static func pageWritingFrame(for pageLayout: LeadSheetPageLayout) -> CGRect {
        pageLayout.paperFrame.insetBy(dx: 10, dy: 10)
    }

    static func chordWritingFrame(for pageLayout: LeadSheetPageLayout) -> CGRect {
        pageLayout.paperFrame.insetBy(dx: 10, dy: 10)
    }

    static func freehandSymbolWritingFrame(
        for pageLayout: LeadSheetPageLayout,
        layoutStyle: ChartLayoutStyle
    ) -> CGRect {
        if layoutStyle.profile.freehandSymbolLanes.contains(.chartArea) {
            return pageWritingFrame(for: pageLayout)
        }

        let laneFrames = pageLayout.systems
            .flatMap(\.measures)
            .flatMap { measure -> [CGRect] in
                [measure.freehandAboveFrame, measure.freehandBelowFrame].compactMap { $0 }
            }

        guard let firstFrame = laneFrames.first else {
            return pageWritingFrame(for: pageLayout)
        }

        return laneFrames
            .dropFirst()
            .reduce(firstFrame) { partialFrame, laneFrame in
                partialFrame.union(laneFrame)
            }
            .insetBy(dx: -8, dy: -8)
    }

    func drawingData(in chart: Chart) -> Data? {
        switch self {
        case .page:
            return chart.pageHandwrittenNotationData
        case .header:
            return chart.pageHandwrittenHeaderData
        case .chords:
            return chart.pageHandwrittenChordData
        case .rhythmicMeasure(let measureID, _):
            return chart.measure(id: measureID)?.handwrittenRhythmicNotationData
        case .noteSelection, .freehandSymbols:
            return nil
        }
    }

    func chartByPersistingDrawingData(_ drawingData: Data?, in chart: Chart) -> Chart? {
        var updatedChart = chart

        switch self {
        case .page:
            guard chart.pageHandwrittenNotationData != drawingData,
                  updatedChart.setPageHandwrittenNotationDrawing(drawingData) else {
                return nil
            }
        case .header:
            guard chart.pageHandwrittenHeaderData != drawingData,
                  updatedChart.setPageHandwrittenHeaderDrawing(drawingData) else {
                return nil
            }
        case .chords:
            guard chart.pageHandwrittenChordData != drawingData,
                  updatedChart.setPageHandwrittenChordDrawing(drawingData) else {
                return nil
            }
        case .rhythmicMeasure(let measureID, _):
            guard chart.measure(id: measureID)?.handwrittenRhythmicNotationData != drawingData,
                  updatedChart.setMeasureHandwrittenRhythmicNotationDrawing(drawingData, for: measureID) else {
                return nil
            }
        case .noteSelection, .freehandSymbols:
            return nil
        }

        return updatedChart
    }
}
#endif

#if canImport(UIKit)
import Foundation
import UIKit

struct LeadSheetActiveInkRegion: Equatable {
    var frame: CGRect
    var inputFrames: [CGRect]

    var localInputFrames: [CGRect] {
        inputFrames.map { inputFrame in
            inputFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
    }
}

enum LeadSheetRhythmicNotationInkCapturePolicy {
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 16
    static let measureEdgePadding: CGFloat = 8

    static func captureFrame(for measureLayout: LeadSheetMeasureLayout) -> CGRect {
        let expandedFrame = measureLayout.writableFrame.insetBy(
            dx: -horizontalPadding,
            dy: -verticalPadding
        )
        let boundedFrame = expandedFrame.intersection(
            measureLayout.frame.insetBy(
                dx: -measureEdgePadding,
                dy: -measureEdgePadding
            )
        )

        return usableFrame(boundedFrame, fallback: measureLayout.writableFrame)
    }

    static func analysisFrame(for measureLayout: LeadSheetMeasureLayout) -> CGRect {
        captureFrame(for: measureLayout).insetBy(dx: 2, dy: 2)
    }

    static func tapFinalizeFrame(for measureLayout: LeadSheetMeasureLayout) -> CGRect {
        captureFrame(for: measureLayout).insetBy(dx: -8, dy: -8)
    }

    private static func usableFrame(_ frame: CGRect, fallback: CGRect) -> CGRect {
        frame.isNull || frame.isEmpty ? fallback : frame
    }
}

enum LeadSheetActiveInkScope {
    case page(frame: CGRect)
    case header(frame: CGRect)
    case chords(frame: CGRect, inputFrames: [CGRect])
    case rhythmicMeasure(measureID: UUID, frame: CGRect)
    case noteSelection(frame: CGRect)

    var frame: CGRect {
        switch self {
        case .page(let frame),
             .header(let frame),
             .rhythmicMeasure(_, let frame),
             .noteSelection(let frame):
            return frame
        case .chords(let frame, _):
            return frame
        }
    }

    var inputFrames: [CGRect] {
        switch self {
        case .chords(_, let inputFrames):
            return inputFrames
        case .page,
             .header,
             .rhythmicMeasure,
             .noteSelection:
            return [frame]
        }
    }

    var localInputFrames: [CGRect] {
        inputFrames.map { inputFrame in
            inputFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
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
                frame: LeadSheetRhythmicNotationInkCapturePolicy.captureFrame(
                    for: selectedMeasureLayout
                )
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
            let region = chordWritingRegion(for: pageLayout)
            return .chords(frame: region.frame, inputFrames: region.inputFrames)
        }

        guard interactionMode.allowsPageInkEditing,
              let pageLayout else {
            return nil
        }

        return .page(frame: pageWritingFrame(for: pageLayout))
    }

    static func pageWritingFrame(for pageLayout: LeadSheetPageLayout) -> CGRect {
        pageLayout.paperFrame.insetBy(dx: 10, dy: 10)
    }

    static func chordWritingFrame(for pageLayout: LeadSheetPageLayout) -> CGRect {
        chordWritingRegion(for: pageLayout).frame
    }

    static func chordWritingInputFrames(for pageLayout: LeadSheetPageLayout) -> [CGRect] {
        chordWritingRegion(for: pageLayout).inputFrames
    }

    static func chordWritingRegion(for pageLayout: LeadSheetPageLayout) -> LeadSheetActiveInkRegion {
        let laneFrames = pageLayout.systems
            .flatMap(\.measures)
            .compactMap { measure -> CGRect? in
                guard measure.sourceMeasureID != nil else {
                    return nil
                }

                let expandedLane = measure.chordWritingFrame.insetBy(dx: -4, dy: -4)
                let boundedLane = expandedLane.intersection(pageLayout.paperFrame)
                return boundedLane.isNull || boundedLane.isEmpty ? nil : boundedLane
            }

        guard let firstFrame = laneFrames.first else {
            let fallbackFrame = pageWritingFrame(for: pageLayout)
            return LeadSheetActiveInkRegion(frame: fallbackFrame, inputFrames: [fallbackFrame])
        }

        let frame = laneFrames
            .dropFirst()
            .reduce(firstFrame) { partialFrame, laneFrame in
                partialFrame.union(laneFrame)
            }
            .insetBy(dx: -2, dy: -2)
            .intersection(pageLayout.paperFrame)

        let resolvedFrame = frame.isNull || frame.isEmpty ? firstFrame : frame
        return LeadSheetActiveInkRegion(frame: resolvedFrame, inputFrames: laneFrames)
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
        case .noteSelection:
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
        case .noteSelection:
            return nil
        }

        return updatedChart
    }
}
#endif

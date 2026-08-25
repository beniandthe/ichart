#if canImport(UIKit)
import Foundation
import UIKit

enum LeadSheetEditorPerformanceDragKind: String {
    case measureResize = "measure_resize"
    case chordMove = "chord_move"
    case chordResize = "chord_resize"
    case cueTextMove = "cue_text_move"
    case roadmapMarkerMove = "roadmap_marker_move"
}

struct LeadSheetEditorPerformanceMetrics {
    private static let flushEventThreshold = 40
    private static let flushInterval: TimeInterval = 5

    private var layoutInvalidationCount = 0
    private var chartWriteBackCount = 0
    private var dragBeginCount = 0
    private var dragChangeCount = 0
    private var dragCommitCount = 0
    private var dragCancelCount = 0
    private var measureResizeChangeCount = 0
    private var chordMoveChangeCount = 0
    private var chordResizeChangeCount = 0
    private var cueTextMoveChangeCount = 0
    private var roadmapMarkerMoveChangeCount = 0
    private var currentDragChangeCountByKind: [LeadSheetEditorPerformanceDragKind: Int] = [:]
    private var maxDragChangesPerSession = 0
    private var lastFlushUptime = ProcessInfo.processInfo.systemUptime

    mutating func recordLayoutInvalidation() {
        layoutInvalidationCount += 1
        flushIfNeeded(reason: "layout")
    }

    mutating func recordChartWriteBack() {
        chartWriteBackCount += 1
        flushIfNeeded(reason: "chart_writeback")
    }

    mutating func recordDragState(
        kind: LeadSheetEditorPerformanceDragKind,
        state: UIGestureRecognizer.State
    ) {
        switch state {
        case .began:
            dragBeginCount += 1
            currentDragChangeCountByKind[kind] = 0
        case .changed:
            dragChangeCount += 1
            currentDragChangeCountByKind[kind, default: 0] += 1
            recordKindChange(kind)
        case .ended:
            dragCommitCount += 1
            finishDragSession(kind)
        case .cancelled, .failed:
            dragCancelCount += 1
            finishDragSession(kind)
        default:
            break
        }

        flushIfNeeded(reason: "drag")
    }

    mutating func flush(reason: String) {
        guard hasEvents else {
            return
        }

        IChartPerformanceTrace.record(
            "editor.interaction.aggregate",
            metadata: [
                "reason": reason,
                "layout_invalidations": "\(layoutInvalidationCount)",
                "chart_writebacks": "\(chartWriteBackCount)",
                "drag_begins": "\(dragBeginCount)",
                "drag_changes": "\(dragChangeCount)",
                "drag_commits": "\(dragCommitCount)",
                "drag_cancels": "\(dragCancelCount)",
                "measure_resize_changes": "\(measureResizeChangeCount)",
                "chord_move_changes": "\(chordMoveChangeCount)",
                "chord_resize_changes": "\(chordResizeChangeCount)",
                "cue_text_move_changes": "\(cueTextMoveChangeCount)",
                "roadmap_marker_changes": "\(roadmapMarkerMoveChangeCount)",
                "max_drag_changes": "\(reportedMaxDragChangesPerSession)"
            ]
        )
        reset()
    }

    var testSnapshot: [String: Int] {
        [
            "layout_invalidations": layoutInvalidationCount,
            "chart_writebacks": chartWriteBackCount,
            "drag_begins": dragBeginCount,
            "drag_changes": dragChangeCount,
            "drag_commits": dragCommitCount,
            "drag_cancels": dragCancelCount,
            "measure_resize_changes": measureResizeChangeCount,
            "chord_move_changes": chordMoveChangeCount,
            "chord_resize_changes": chordResizeChangeCount,
            "cue_text_move_changes": cueTextMoveChangeCount,
            "roadmap_marker_changes": roadmapMarkerMoveChangeCount,
            "max_drag_changes": reportedMaxDragChangesPerSession
        ]
    }

    private mutating func recordKindChange(_ kind: LeadSheetEditorPerformanceDragKind) {
        switch kind {
        case .measureResize:
            measureResizeChangeCount += 1
        case .chordMove:
            chordMoveChangeCount += 1
        case .chordResize:
            chordResizeChangeCount += 1
        case .cueTextMove:
            cueTextMoveChangeCount += 1
        case .roadmapMarkerMove:
            roadmapMarkerMoveChangeCount += 1
        }
    }

    private mutating func finishDragSession(_ kind: LeadSheetEditorPerformanceDragKind) {
        maxDragChangesPerSession = max(
            maxDragChangesPerSession,
            currentDragChangeCountByKind[kind] ?? 0
        )
        currentDragChangeCountByKind[kind] = nil
    }

    private var reportedMaxDragChangesPerSession: Int {
        max(
            maxDragChangesPerSession,
            currentDragChangeCountByKind.values.max() ?? 0
        )
    }

    private var hasEvents: Bool {
        layoutInvalidationCount > 0
            || chartWriteBackCount > 0
            || dragBeginCount > 0
            || dragChangeCount > 0
            || dragCommitCount > 0
            || dragCancelCount > 0
    }

    private mutating func flushIfNeeded(reason: String) {
        let eventCount = layoutInvalidationCount
            + chartWriteBackCount
            + dragBeginCount
            + dragChangeCount
            + dragCommitCount
            + dragCancelCount
        let now = ProcessInfo.processInfo.systemUptime
        guard eventCount >= Self.flushEventThreshold
                || now - lastFlushUptime >= Self.flushInterval else {
            return
        }

        flush(reason: reason)
    }

    private mutating func reset() {
        layoutInvalidationCount = 0
        chartWriteBackCount = 0
        dragBeginCount = 0
        dragChangeCount = 0
        dragCommitCount = 0
        dragCancelCount = 0
        measureResizeChangeCount = 0
        chordMoveChangeCount = 0
        chordResizeChangeCount = 0
        cueTextMoveChangeCount = 0
        roadmapMarkerMoveChangeCount = 0
        maxDragChangesPerSession = 0
        lastFlushUptime = ProcessInfo.processInfo.systemUptime
    }
}
#endif

#if canImport(UIKit)
import CoreGraphics
import XCTest
@testable import iChart

final class ChordInkDraftPreviewTests: XCTestCase {
    func testDraftStateReplacesBatchAndPreservesEditedTextByAnchor() {
        let measureID = UUID()
        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(measureID: measureID, measureIndex: 0, fraction: 0.24, bestCandidateText: "C")
        ])

        let draftID = state.draftChords[0].id
        state.draftChords[0].selectedText = "Cmaj7"
        state.replaceDraftChords(with: [
            draftInput(measureID: measureID, measureIndex: 0, fraction: 0.245, bestCandidateText: "C6")
        ])

        XCTAssertEqual(state.draftChords.count, 1)
        XCTAssertEqual(state.draftChords[0].id, draftID)
        XCTAssertEqual(state.draftChords[0].previewText, "Cmaj7")
    }

    func testDraftBarlineRecognizerAcceptsTallStraightLaneStrokeAndRejectsSlashStroke() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let verticalStroke = InkStroke(points: [
            InkPoint(x: 150, y: 104, timeOffset: 0),
            InkPoint(x: 151, y: 130, timeOffset: 0.1),
            InkPoint(x: 150, y: 164, timeOffset: 0.2)
        ])
        let slashStroke = InkStroke(points: [
            InkPoint(x: 190, y: 110, timeOffset: 0),
            InkPoint(x: 226, y: 160, timeOffset: 0.2)
        ])

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [verticalStroke, slashStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertEqual(recognition.barlines.count, 1)
        XCTAssertEqual(recognition.barlines[0].measureID, measureID)
        XCTAssertEqual(recognition.strokeIndices, [0])
        XCTAssertTrue(recognition.barlines[0].isRenderable)
    }

    func testDraftBarlineRecognizerAcceptsOpenLaneStrokeBeyondRenderedMeasureBox() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let openLaneStroke = InkStroke(points: [
            InkPoint(x: 312, y: 104, timeOffset: 0),
            InkPoint(x: 313, y: 130, timeOffset: 0.1),
            InkPoint(x: 312, y: 164, timeOffset: 0.2)
        ])

        XCTAssertFalse(
            pageLayout.systems[0].measures[0].chordWritingFrame.contains(
                CGPoint(x: 312, y: 130)
            )
        )
        XCTAssertTrue(
            LeadSheetActiveInkScope.chordWritingInputFrames(for: pageLayout)[0].contains(
                CGPoint(x: 312, y: 130)
            )
        )

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [openLaneStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertEqual(recognition.barlines.count, 1)
        XCTAssertEqual(recognition.barlines[0].measureID, measureID)
        XCTAssertGreaterThan(recognition.barlines[0].fraction, 0.9)
    }

    func testDraftBatchRenderCommitsOnlyOnExplicitRender() throws {
        var chart = Chart.draft(title: "Draft Chords")
        chart.completeInitialSetup(
            title: "Draft Chords",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 2
        )
        let firstMeasureID = chart.measures[0].id
        let openMeasureID = chart.measures[1].id
        XCTAssertEqual(chart.measures[1].authoringState, .open)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: firstMeasureID,
                measureIndex: 0,
                fraction: 0.1,
                bestCandidateText: "C",
                drawingData: Data("ink-C".utf8)
            )
        ])
        state.replaceDraftBarlines(with: [
            DraftBarline(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.92,
                metrics: DraftBarlineGestureMetrics(
                    height: 54,
                    width: 2,
                    angleDegreesFromVertical: 2,
                    straightness: 0.98,
                    laneCoverage: 0.8
                )
            )
        ])

        XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertEqual(chart.measures.count, 2)

        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("full-draft-ink".utf8)))
        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 1)
        XCTAssertEqual(result.renderedBarlineCount, 1)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures[0].chordEvents.first?.symbol.displayText, "C")
        XCTAssertEqual(chart.measures.count, 3)
        XCTAssertEqual(chart.measures[1].authoringState, .committed)
        XCTAssertEqual(chart.measures[2].authoringState, .open)
        XCTAssertNil(chart.pageHandwrittenChordData)
    }

    func testTelemetryAllowsOnlyAggregateDraftPreviewProperties() {
        let sanitized = IChartTelemetryPrivacy.sanitizedProperties([
            "draft_count": .int(2),
            "barline_count": .int(1),
            "rendered_count": .int(2),
            "unresolved_count": .int(0),
            "raw_chord_text": .string("Cmaj7"),
            "drawing_payload": .string("not allowed")
        ])

        XCTAssertEqual(sanitized["draft_count"], .int(2))
        XCTAssertEqual(sanitized["barline_count"], .int(1))
        XCTAssertEqual(sanitized["rendered_count"], .int(2))
        XCTAssertEqual(sanitized["unresolved_count"], .int(0))
        XCTAssertNil(sanitized["raw_chord_text"])
        XCTAssertNil(sanitized["drawing_payload"])
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.preview_updated"))
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.preview_rendered"))
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.preview_discarded"))
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.draft_barline_added"))
    }

    private func draftInput(
        measureID: UUID,
        measureIndex: Int,
        fraction: Double,
        bestCandidateText: String,
        drawingData: Data = Data("ink".utf8)
    ) -> ChordInkDraftInput {
        ChordInkDraftInput(
            measureID: measureID,
            measureIndex: measureIndex,
            targetFraction: fraction,
            drawingData: drawingData,
            candidateTexts: [bestCandidateText],
            bestCandidateText: bestCandidateText,
            confidence: 4.2,
            strokeCount: 2
        )
    }

    private static func pageLayout(measureID: UUID) -> LeadSheetPageLayout {
        let measure = LeadSheetMeasureLayout(
            id: measureID,
            sourceMeasureID: measureID,
            index: 1,
            frame: CGRect(x: 90, y: 96, width: 220, height: 84),
            staffFrame: CGRect(x: 100, y: 112, width: 200, height: 56),
            chordBandFrame: CGRect(x: 104, y: 104, width: 192, height: 34),
            writableFrame: CGRect(x: 100, y: 104, width: 200, height: 64),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: nil,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: 300, y: 112, width: 1.6, height: 56),
            isOpen: false
        )
        let system = LeadSheetSystemLayout(
            id: UUID(),
            index: 0,
            frame: CGRect(x: 80, y: 90, width: 240, height: 100),
            staffLineYPositions: [],
            clefFrame: nil,
            keySignatureLayouts: [],
            keyTextFrame: nil,
            keyText: nil,
            timeSignatureFrame: nil,
            sectionTextFrame: nil,
            sectionText: nil,
            roadmapTextFrame: nil,
            roadmapText: nil,
            roadmapMarkerLayouts: [],
            endingLayouts: [],
            measures: [measure]
        )
        return LeadSheetPageLayout(
            pageBounds: CGRect(x: 0, y: 0, width: 400, height: 400),
            paperFrame: CGRect(x: 20, y: 20, width: 360, height: 360),
            header: LeadSheetHeaderLayout(
                frame: CGRect(x: 40, y: 32, width: 320, height: 40),
                handwrittenFrame: CGRect(x: 40, y: 32, width: 320, height: 40),
                titleFrame: CGRect(x: 40, y: 32, width: 320, height: 40),
                composerFrame: nil,
                styleNoteFrame: nil,
                keyFrame: nil,
                meterFrame: nil
            ),
            systems: [system]
        )
    }
}
#endif
